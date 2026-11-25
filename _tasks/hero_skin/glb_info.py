"""看一个皮肤源 GLB 里有什么：网格节点（顶点数 / 材质 / 贴图）、图片（名字 / 字节）、骨骼树（静止位置）、指定动画的概况。
挑要留的网格、认骨骼名、估包体时先跑它。
用法：python _tasks/hero_skin/glb_info.py <GLB> [--bones] [--anim 动作编号]
"""
import json
import struct
import sys

import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    off = 12
    js = None
    blob = b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        if ctype == 0x4E4F534A:
            js = json.loads(data[off:off + clen].decode("utf-8"))
        else:
            blob = data[off:off + clen]
        off += clen
    return js, blob


def read_acc(js, blob, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(blob, dtype=dt, count=a["count"] * n, offset=start).reshape(a["count"], n).copy()


def trs(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    t = n.get("translation", [0, 0, 0])
    r = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    x, y, z, w = r
    rm = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                   [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                   [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = rm * np.array(s)
    m[:3, 3] = t
    return m


def main():
    path = sys.argv[1]
    js, blob = load(path)
    nodes = js["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    world = {}

    def wm(i):
        if i not in world:
            world[i] = (wm(parent[i]) @ trs(nodes[i])) if i in parent else trs(nodes[i])
        return world[i]

    print("节点 %d · 网格 %d · 蒙皮 %d · 图片 %d · 动画 %d" % (len(nodes), len(js.get("meshes", [])), len(js.get("skins", [])),
          len(js.get("images", [])), len(js.get("animations", []))))
    print("== 图片")
    for i, im in enumerate(js.get("images", [])):
        bv = js["bufferViews"][im["bufferView"]]
        raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + 32]
        wh = ""
        if raw[:8] == b"\x89PNG\r\n\x1a\n":
            wh = "%dx%d" % struct.unpack(">II", raw[16:24])
        print("  %d %-28s %8d 字节 %s" % (i, im.get("name"), bv["byteLength"], wh))
    print("== 网格节点")
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        m = js["meshes"][n["mesh"]]
        for p in m["primitives"]:
            at = p["attributes"]
            pos = read_acc(js, blob, at["POSITION"])
            mat = js["materials"][p["material"]] if "material" in p else {}
            tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index")
            img = js["images"][js["textures"][tex]["source"]].get("name") if tex is not None else None
            # 这件网格跟着哪些骨骼（权重最大的前几根）
            top = ""
            if "JOINTS_0" in at and "skin" in n:
                J = read_acc(js, blob, at["JOINTS_0"]).astype(np.int64)
                W = read_acc(js, blob, at["WEIGHTS_0"]).astype(np.float64)
                acc = {}
                joints = js["skins"][n["skin"]]["joints"]
                for k in range(4):
                    for j, w in zip(J[:, k], W[:, k]):
                        if w > 1e-4:
                            acc[joints[j]] = acc.get(joints[j], 0.0) + w
                rank = sorted(acc.items(), key=lambda kv: -kv[1])[:5]
                top = ", ".join("%s %.0f%%" % (nodes[j].get("name"), 100.0 * w / len(pos)) for j, w in rank)
            print("  %-22s 顶点 %6d 三角 %6d 材质 %-18s 贴图 %-24s alpha=%s  min=%s max=%s" % (
                n.get("name"), len(pos), js["accessors"][p["indices"]]["count"] // 3, mat.get("name"), img, mat.get("alphaMode", "OPAQUE"),
                np.round(pos.min(axis=0), 1), np.round(pos.max(axis=0), 1)))
            print("      骨骼：", top)
    if "--bones" in sys.argv:
        print("== 骨骼（世界静止位置，源文件单位）")
        joints = js["skins"][0]["joints"]
        for j in joints:
            w = wm(j)
            sc = np.linalg.norm(w[:3, :3], axis=0)
            print("  %-26s 父=%-22s pos=(%8.2f, %8.2f, %8.2f) 缩放=%.3f" % (nodes[j].get("name"), nodes[parent[j]].get("name") if j in parent else "-",
                  w[0, 3], w[1, 3], w[2, 3], sc.mean()))
    for k, a in enumerate(sys.argv):
        if a == "--anim":
            want = sys.argv[k + 1]
            for an in js.get("animations", []):
                nm = an.get("name", "")
                if nm == want or nm.endswith("_" + want):
                    size = 0
                    seen = set()
                    paths = {}
                    for ch in an["channels"]:
                        sm = an["samplers"][ch["sampler"]]
                        paths[ch["target"]["path"]] = paths.get(ch["target"]["path"], 0) + 1
                        for key in ("input", "output"):
                            if sm[key] not in seen:
                                seen.add(sm[key])
                                acc = js["accessors"][sm[key]]
                                size += acc["count"] * NC[acc["type"]] * np.dtype(CT[acc["componentType"]]).itemsize
                    print("== 动画 %s：通道 %s，数据约 %d 字节" % (nm, paths, size))
                    # 这段动画里被缩到零的骨骼（= 藏起来的部件 / 另一个形态）；缩放有变化的也列出来
                    zero, vary = [], []
                    for ch in an["channels"]:
                        if ch["target"]["path"] != "scale":
                            continue
                        sc = read_acc(js, blob, an["samplers"][ch["sampler"]]["output"])
                        mag = np.abs(sc).max(axis=1)
                        nmn = nodes[ch["target"]["node"]].get("name")
                        if mag.max() < 0.02:
                            zero.append(nmn)
                        elif mag.min() < 0.02 or (mag.max() - mag.min()) > 0.05:
                            vary.append("%s(%.2f~%.2f)" % (nmn, mag.min(), mag.max()))
                    print("   全程缩到零：", zero)
                    print("   缩放有变化：", vary)


main()
