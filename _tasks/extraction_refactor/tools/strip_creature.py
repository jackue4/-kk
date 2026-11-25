"""资源库生物 GLB（05_生物动画 / 06_其他实体待核名）精简成游戏里用的 assets/creatures/<名>.glb。

和 _tasks/hero_skin/strip_glb.py（主角皮肤用，会重排骨骼、只留位移 / 旋转轨道）不同，这里**不动网格 / 骨骼 / 蒙皮**，只做三件事：
  · 动画只留 scripts/creature_model.gd 的 ROLES 用得到的那几段（每个动作取第一个找得到的编号）+ --extra 点名的，
    其余删掉；留下的动画保留全部轨道（含缩放 —— 生物常用零缩放藏部件，删了会露馅）
  · 贴图边长超过 --max（默认 512）的按比例缩小重新存 PNG；--opaque 把贴图透明通道填满、材质改成不透明
    （虚空博士 / 骷罗这类源文件贴图 alpha 全是 0，导进来会整只看不见）
  · 没人用的缓冲区视图 / 访问器丢掉，重新打包
用法：
  python -I strip_creature.py <源 GLB> <输出 GLB> [--max 512] [--opaque] [--extra 100102,100130] [--info]
  --info 只打印源文件概况（动画 / 材质 / 贴图 / 网格），不写文件。
"""
import io
import json
import struct
import sys

ROLES = {
    "idle": ["100100", "100204"],
    "walk": ["100101", "100111"],
    "run": ["100111", "100101"],
    "attack": ["100105", "100108", "100113", "100184", "100500", "100201"],
    "hurt": ["100107"],
    "death": ["100106"],
}


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


def anim_id(name):
    return name.rsplit("_", 1)[-1]


def pick_anims(js, extra):
    names = [a.get("name", "") for a in js.get("animations", [])]
    keep = []
    roles = {}
    for role, ids in ROLES.items():
        for want in ids:
            hit = next((i for i, n in enumerate(names) if n == want or n.endswith("_" + want)), None)
            if hit is not None:
                roles[role] = names[hit]
                if hit not in keep:
                    keep.append(hit)
                break
    for want in extra:
        hit = next((i for i, n in enumerate(names) if n == want or n.endswith("_" + want)), None)
        if hit is not None and hit not in keep:
            keep.append(hit)
    return sorted(keep), roles


def info(js, blob):
    print("动画 %d 段：%s" % (len(js.get("animations", [])), [a.get("name") for a in js.get("animations", [])]))
    for i, m in enumerate(js.get("materials", [])):
        pbr = m.get("pbrMetallicRoughness", {})
        print("  材质", i, m.get("name"), m.get("alphaMode", "OPAQUE"), "贴图", pbr.get("baseColorTexture", {}).get("index"),
              "色", pbr.get("baseColorFactor"))
    for i, im in enumerate(js.get("images", [])):
        bv = js["bufferViews"][im["bufferView"]]
        raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        try:
            from PIL import Image
            img = Image.open(io.BytesIO(raw))
            amin = amax = None
            if img.mode in ("RGBA", "LA"):
                a = img.getchannel("A")
                amin, amax = a.getextrema()
            print("  图片", i, im.get("name"), img.size, img.mode, "alpha", amin, amax, "%d 字节" % len(raw))
        except Exception as e:      # noqa: BLE001
            print("  图片", i, im.get("name"), "%d 字节" % len(raw), e)
    nm = sum(1 for n in js["nodes"] if "mesh" in n)
    print("节点 %d，网格节点 %d，网格 %d，蒙皮 %d" % (len(js["nodes"]), nm, len(js.get("meshes", [])), len(js.get("skins", []))))
    scale_anims = []
    for a in js.get("animations", []):
        if any(ch["target"]["path"] == "scale" for ch in a["channels"]):
            scale_anims.append(a.get("name"))
    print("带缩放轨道的动画：", len(scale_anims))


def main():
    src = sys.argv[1]
    args = sys.argv[2:]
    dst = None if (not args or args[0].startswith("--")) else args[0]
    max_px = 512
    opaque = "--opaque" in args
    extra = []
    for i, a in enumerate(args):
        if a == "--max":
            max_px = int(args[i + 1])
        if a == "--extra":
            extra = [x for x in args[i + 1].split(",") if x]
    js, blob = load(src)
    if "--info" in args or dst is None:
        info(js, blob)
        keep, roles = pick_anims(js, extra)
        print("会留下的动画：", roles)
        return

    keep, roles = pick_anims(js, extra)
    anims = [js["animations"][i] for i in keep] if "animations" in js else []
    # 退化的缩放（0 或者 1e16 这种垃圾值，铁穹两只的 700 / 701 节点就是）：Godot 导入 / 播放时会刷
    # 「Basis must be normalized」报错。改成 0.001（照样看不见），节点静止缩放和留用动画的缩放轨道都改
    fixed = 0
    for n in js.get("nodes", []):
        if "scale" in n:
            sc = [0.001 if (abs(v) < 1e-6 or abs(v) > 1e4) else v for v in n["scale"]]
            if sc != n["scale"]:
                n["scale"] = sc
                fixed += 1
    patch_scale = set()
    for a in anims:
        for ch in a["channels"]:
            if ch["target"]["path"] == "scale":
                patch_scale.add(a["samplers"][ch["sampler"]]["output"])

    # 用到的访问器 / 缓冲区视图
    used_acc = set()
    for m in js.get("meshes", []):
        for p in m["primitives"]:
            used_acc.update(p["attributes"].values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for t in p.get("targets", []):
                used_acc.update(t.values())
    for s in js.get("skins", []):
        if "inverseBindMatrices" in s:
            used_acc.add(s["inverseBindMatrices"])
    for a in anims:
        for sm in a["samplers"]:
            used_acc.add(sm["input"])
            used_acc.add(sm["output"])
    used_bv = set()
    for ai in used_acc:
        acc = js["accessors"][ai]
        if "bufferView" in acc:
            used_bv.add(acc["bufferView"])
        if "sparse" in acc:
            raise SystemExit("不支持稀疏访问器")

    # 图片：缩小 / 去透明
    from PIL import Image
    new_img_raw = {}
    for i, im in enumerate(js.get("images", [])):
        bv = js["bufferViews"][im["bufferView"]]
        raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        img = Image.open(io.BytesIO(raw))
        img.load()
        changed = False
        w, h = img.size
        if max(w, h) > max_px:
            k = max_px / float(max(w, h))
            img = img.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.NEAREST)
            changed = True
        if opaque and img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGB")
            changed = True
        if changed:
            b = io.BytesIO()
            img.save(b, format="PNG", optimize=True)
            raw = b.getvalue()
            print("  图片 %s %s → %s %s" % (im.get("name"), (w, h), img.size, img.mode))
        new_img_raw[i] = raw

    out = bytearray()
    views = []
    bv_map = {}

    def add_view(raw, src_bv=None):
        while len(out) % 4:
            out.append(0)
        v = {"buffer": 0, "byteOffset": len(out), "byteLength": len(raw)}
        if src_bv is not None:
            for k in ("byteStride", "target"):
                if k in src_bv:
                    v[k] = src_bv[k]
        out.extend(raw)
        views.append(v)
        return len(views) - 1

    import numpy as np
    patch_by_bv = {}
    for ai in patch_scale:
        acc = js["accessors"][ai]
        if acc.get("componentType") == 5126 and "bufferView" in acc and not js["bufferViews"][acc["bufferView"]].get("byteStride"):
            patch_by_bv.setdefault(acc["bufferView"], []).append(acc)
    for bi in sorted(used_bv):
        bv = js["bufferViews"][bi]
        raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        if bi in patch_by_bv:
            buf = bytearray(raw)
            for acc in patch_by_bv[bi]:
                o = acc.get("byteOffset", 0)
                n = acc["count"] * 3
                arr = np.frombuffer(bytes(buf[o:o + n * 4]), dtype=np.float32).copy()
                bad = (np.abs(arr) < 1e-6) | (np.abs(arr) > 1e4)
                if bad.any():
                    arr[bad] = 0.001
                    buf[o:o + n * 4] = arr.tobytes()
                    fixed += 1
            raw = bytes(buf)
        bv_map[bi] = add_view(raw, bv)
    if fixed:
        print("  退化缩放修了 %d 处" % fixed)
    accs = []
    acc_map = {}
    for ai in sorted(used_acc):
        a = dict(js["accessors"][ai])
        if "bufferView" in a:
            a["bufferView"] = bv_map[a["bufferView"]]
        acc_map[ai] = len(accs)
        accs.append(a)
    images = []
    for i, im in enumerate(js.get("images", [])):
        n = {k: v for k, v in im.items() if k not in ("bufferView", "uri")}
        n["mimeType"] = "image/png"
        n["bufferView"] = add_view(new_img_raw[i])
        images.append(n)
    while len(out) % 4:
        out.append(0)

    meshes = json.loads(json.dumps(js.get("meshes", [])))
    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in p["targets"]]
    skins = json.loads(json.dumps(js.get("skins", [])))
    for s in skins:
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    new_anims = []
    for a in anims:
        a = json.loads(json.dumps(a))
        for sm in a["samplers"]:
            sm["input"] = acc_map[sm["input"]]
            sm["output"] = acc_map[sm["output"]]
        a.pop("extras", None)
        new_anims.append(a)
    mats = json.loads(json.dumps(js.get("materials", [])))
    if opaque:
        for m in mats:
            m["alphaMode"] = "OPAQUE"
            m.pop("alphaCutoff", None)
            pbr = m.get("pbrMetallicRoughness", {})
            if "baseColorFactor" in pbr:
                pbr["baseColorFactor"][3] = 1.0
    gltf = {k: v for k, v in js.items() if k not in ("buffers", "bufferViews", "accessors", "images", "meshes", "skins",
                                                       "animations", "materials")}
    gltf["asset"] = {"version": "2.0", "generator": "strip_creature.py"}
    gltf["meshes"] = meshes
    if skins:
        gltf["skins"] = skins
    if new_anims:
        gltf["animations"] = new_anims
    gltf["materials"] = mats
    gltf["images"] = images
    gltf["bufferViews"] = views
    gltf["accessors"] = accs
    gltf["buffers"] = [{"byteLength": len(out)}]
    for n in gltf.get("nodes", []):
        n.pop("extras", None)
    jraw = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(jraw) % 4:
        jraw += b" "
    total = 12 + 8 + len(jraw) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jraw), 0x4E4F534A))
        f.write(jraw)
        f.write(struct.pack("<II", len(out), 0x004E4942))
        f.write(bytes(out))
    import os
    print("%s：%d → %d 字节；动画 %d → %d 段 %s" % (os.path.basename(dst), os.path.getsize(src), total,
          len(js.get("animations", [])), len(new_anims), roles))


main()
