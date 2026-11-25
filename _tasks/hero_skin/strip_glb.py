"""主角皮肤（资源库「01_主角动画皮肤」）精简成游戏里用的 GLB。

游戏里的招式是程序摆的（voxel_hero.gd 的十五个关节 + fighter_rig.gd），皮肤模型的骨骼逐帧跟着那副关节走
（scripts/hero_skin.gd），所以源文件里自带的动画绝大多数用不上。这里做的事：
  · 动画只留 --anims 点名的几段（按动作编号；2026-11-23 起留待机 / 走 / 跑三段给地面移动用），其余全删
    （源文件 11.9MB 里有 10MB 多是这 162 段动画）；留下的也只带留用骨骼的位移 / 旋转两种轨道，缩放轨道不要
  · 只留指定的几件网格（身体 / 外搭 / 两张脸）；飞毯、茶壶、书、手套这些靠零缩放骨骼藏起来的道具连同贴图一起删
  · 骨骼只留这些网格用得到的和它们的上级，蒙皮下标跟着重排
  · 切线不要（没有法线贴图）
  · 眨眼用的那张脸不留网格（游戏里是在同一张脸上换贴图），贴图用 --image 单独另存
  · 蒙皮并回一副骨架（2026-11-23 加，魔炎 / 冰雪战士这类源文件需要）：转换出来的源文件里，网格往往不是直接绑在骨骼上，
    而是绑在骨骼下面挂的辅助节点上（「仿射TUR_ / 仿射S_ / 仿射V_骨骼名」「镜像补偿_骨骼名」，不带动画），有的还给每件网格
    各配了一份骨架副本（「独立蒙皮骨架_N」，和主骨架同名同姿势、被同一段动画重复驱动）。这里把每个绑定点改绑到它所属的
    那根主骨架骨骼上：新绑定矩阵 = 主骨骼静止世界矩阵的逆 × 绑定点静止世界矩阵 × 原绑定矩阵（辅助节点跟着骨骼刚性走，
    所以任何姿势下结果都和原来一样），辅助节点和骨架副本全部丢掉。各件网格的绑定矩阵不一样时各用各的蒙皮（骨骼还是同一副）。
  · --merge：留下的网格并成一件（贴图一样的面并成同一个表面）。冰雪战士原来是 10 件网格 = 每个人 10 次绘制 + 10 次蒙皮，
    并完是 1 件 1 个表面。前提是各件网格改绑后能共用一份蒙皮（不能就报错）。并完的网格节点叫 body。
用法：python strip_glb.py <源 GLB> <输出 GLB> [--keep 网格节点名,…] [--name 根节点名] [--image 源图片名=另存路径 …] [--anims 动作编号,…] [--merge]
阿拉灯：python _tasks/hero_skin/strip_glb.py <资源库>/01_主角动画皮肤/阿拉灯_140161/阿拉灯_第三人称主体_PREFAB_body.glb assets/hero/aladeng.glb
        --name aladeng --image face_100100.png=assets/hero/aladeng_face_blink.png --anims 100100,100111
其余几个皮肤的命令见 memory 的 hero-skin-model（网格名先用 glb_info.py 看）。
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
    stride = bv.get("byteStride", 0)
    if stride and stride != dt.itemsize * n:
        out = np.zeros((a["count"], n), dtype=dt)
        for k in range(a["count"]):
            out[k] = np.frombuffer(blob, dtype=dt, count=n, offset=start + k * stride)
        return out
    return np.frombuffer(blob, dtype=dt, count=a["count"] * n, offset=start).reshape(a["count"], n).copy()


class Out:
    """新文件的缓冲区 / 视图 / 访问器"""

    def __init__(self):
        self.buf = bytearray()
        self.views = []
        self.accs = []

    def view(self, raw, target=None):
        while len(self.buf) % 4:
            self.buf.append(0)
        v = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.buf.extend(raw)
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, arr, kind, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        ct = {v: k for k, v in CT.items()}[arr.dtype.type]
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ct, "count": int(arr.shape[0]), "type": kind}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = [float(v) for v in arr.min(axis=0)]
            a["max"] = [float(v) for v in arr.max(axis=0)]
        self.accs.append(a)
        return len(self.accs) - 1


HELPERS = ("仿射", "镜像补偿")
COPY = "独立蒙皮骨架"


def trs(n):
    """节点的本地矩阵（列向量约定）"""
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    rm = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                   [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                   [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = rm * np.array(n.get("scale", [1, 1, 1]), dtype=np.float64)
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def main():
    src, dst = sys.argv[1], sys.argv[2]
    keep = ["face", "body", "body1"]
    root_name = "hero_skin"
    extra_images = []
    keep_anims = []
    args = sys.argv[3:]
    for i, a in enumerate(args):
        if a == "--keep":
            keep = args[i + 1].split(",")
        if a == "--name":
            root_name = args[i + 1]
        if a == "--image":
            extra_images.append(args[i + 1].split("=", 1))
        if a == "--anims":
            keep_anims = [x for x in args[i + 1].split(",") if x]
    merge = "--merge" in args

    js, blob = load(src)
    nodes = js["nodes"]
    for name, path in extra_images:
        for im in js["images"]:
            if im.get("name") == name:
                bv = js["bufferViews"][im["bufferView"]]
                with open(path, "wb") as f:
                    f.write(blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
                print("另存贴图", name, "→", path)
                break
        else:
            raise SystemExit("源文件里没有图片 " + name)
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    world = {}

    def wm(i):
        if i not in world:
            world[i] = (wm(parent[i]) @ trs(nodes[i])) if i in parent else trs(nodes[i])
        return world[i]

    def name(i):
        return nodes[i].get("name", "")

    def is_helper(i):
        return name(i).startswith(HELPERS)

    def in_copy(i):
        while i in parent:
            i = parent[i]
            if name(i).startswith(COPY):
                return True
        return False

    mesh_nodes = [i for i, n in enumerate(nodes) if "mesh" in n and n.get("name") in keep]
    if len(mesh_nodes) != len(keep):
        raise SystemExit("没找全要留的网格：%s" % [nodes[i]["name"] for i in mesh_nodes])
    mesh_anc = set()
    for ni in mesh_nodes:
        b = ni
        while b in parent:
            b = parent[b]
            mesh_anc.add(b)

    # 主骨架：不在骨架副本里、不是辅助节点、不是网格的节点，按名字认
    main_by_name = {}
    for i, n in enumerate(nodes):
        if "mesh" in n or is_helper(i) or name(i).startswith(COPY) or in_copy(i):
            continue
        main_by_name.setdefault(name(i), []).append(i)

    def canon(j):
        """绑定点 j 归到主骨架的哪根骨骼"""
        r = j
        while is_helper(r):
            r = parent[r]
        if in_copy(r):
            cands = main_by_name.get(name(r), [])
            if len(cands) != 1:
                raise SystemExit("骨架副本里的 %s 在主骨架里对不上（%d 个同名）" % (name(r), len(cands)))
            c = cands[0]
            for key, dv in (("translation", [0, 0, 0]), ("rotation", [0, 0, 0, 1]), ("scale", [1, 1, 1])):
                if not np.allclose(nodes[r].get(key, dv), nodes[c].get(key, dv), atol=2e-3):
                    print("  注意：骨架副本里的 %s 和主骨架的静止 %s 不一样" % (name(r), key))
            return c
        return r

    # 每件网格：用到的绑定点 → 主骨架骨骼 + 改绑后的绑定矩阵
    used = set()
    per_mesh = {}
    for ni in mesh_nodes:
        skin = js["skins"][nodes[ni]["skin"]]
        ibm = read_acc(js, blob, skin["inverseBindMatrices"]).astype(np.float64).reshape(-1, 4, 4).transpose(0, 2, 1)
        prims = []
        hit = set()
        for p in js["meshes"][nodes[ni]["mesh"]]["primitives"]:
            at = p["attributes"]
            J = read_acc(js, blob, at["JOINTS_0"]).astype(np.int64)
            W = read_acc(js, blob, at["WEIGHTS_0"]).astype(np.float32)
            for j in np.unique(J[W > 1e-4]):
                hit.add(int(j))
            prims.append((p, J, W))
        to_bone = {}       # 蒙皮里的下标 → 主骨架骨骼节点
        bind = {}          # 主骨架骨骼节点 → 改绑后的绑定矩阵
        for k in sorted(hit):
            j = skin["joints"][k]
            c = canon(j)
            nb = np.linalg.inv(wm(c)) @ wm(j) @ ibm[k]
            if c in bind and not np.allclose(bind[c], nb, atol=1e-3 * max(1.0, float(np.abs(nb).max()))):
                raise SystemExit("网格 %s 里有两个绑定点都归到骨骼 %s、绑定矩阵却不一样，这种没处理" % (name(ni), name(c)))
            bind.setdefault(c, nb)
            to_bone[k] = c
            used.add(c)
        per_mesh[ni] = (skin, prims, to_bone, bind)

    # 骨骼 = 用到的 + 它们的上级（到网格和骨架共同的那层为止）
    bones = set(used)
    for b in list(used):
        while b in parent and parent[b] not in mesh_anc:
            b = parent[b]
            bones.add(b)
    odd = [name(b) for b in bones if np.abs(np.linalg.norm(trs(nodes[b])[:3, :3], axis=0) - 1.0).max() > 1e-3]
    if odd:
        print("  注意：这些留用骨骼静止时带缩放（游戏里只摆位置 / 旋转）：", odd)

    # 留下的节点：骨骼、网格节点，以及它们到场景根的那几层
    carrier = mesh_nodes[0]      # --merge 时并完的网格挂在第一件的节点上
    keep_nodes = set(bones) | (set([carrier]) if merge else set(mesh_nodes))
    for b in list(keep_nodes):
        while b in parent:
            b = parent[b]
            keep_nodes.add(b)
    order = [i for i in range(len(nodes)) if i in keep_nodes]
    remap = {old: new for new, old in enumerate(order)}

    out = Out()
    new_nodes = []
    for old in order:
        n = dict(nodes[old])
        n.pop("extras", None)
        n.pop("mesh", None)
        n.pop("skin", None)
        if "children" in n:
            ch = [remap[c] for c in n["children"] if c in remap]
            if ch:
                n["children"] = ch
            else:
                n.pop("children")
        new_nodes.append(n)

    # 材质 / 贴图 / 图片：只带留下的网格用到的
    mat_map, tex_map, img_map = {}, {}, {}
    new_mats, new_texs, new_imgs = [], [], []

    def take_image(i):
        if i not in img_map:
            im = js["images"][i]
            bv = js["bufferViews"][im["bufferView"]]
            raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
            new_imgs.append({"name": im.get("name", "tex%d" % i), "mimeType": im.get("mimeType", "image/png"), "bufferView": out.view(raw)})
            img_map[i] = len(new_imgs) - 1
        return img_map[i]

    def take_tex(i):
        if i not in tex_map:
            t = dict(js["textures"][i])
            t["source"] = take_image(t["source"])
            new_texs.append(t)
            tex_map[i] = len(new_texs) - 1
        return tex_map[i]

    def take_mat(i):
        if i not in mat_map:
            m = json.loads(json.dumps(js["materials"][i]))
            m.pop("extras", None)
            pbr = m.get("pbrMetallicRoughness", {})
            if "baseColorTexture" in pbr:
                pbr["baseColorTexture"]["index"] = take_tex(pbr["baseColorTexture"]["index"])
            # 内容一样的材质（身体和外搭用的是同一张贴图）并成一份；--merge 时名字不同也算一样（只看贴图和参数）
            for k, have in enumerate(new_mats):
                if have == m or (merge and {x: y for x, y in have.items() if x != "name"} == {x: y for x, y in m.items() if x != "name"}):
                    mat_map[i] = k
                    break
            else:
                new_mats.append(m)
                mat_map[i] = len(new_mats) - 1
        return mat_map[i]

    # 蒙皮：骨骼是同一副（按节点顺序排）；绑定矩阵一样的网格共用一份蒙皮，不一样的各用各的
    joint_old = [j for j in order if j in bones]
    joint_new = {j: k for k, j in enumerate(joint_old)}
    rest_inv = [np.linalg.inv(wm(j)) for j in joint_old]
    new_skins = []
    skin_mats = []

    def take_skin(bind):
        mats = np.stack([bind.get(j, rest_inv[k]) for k, j in enumerate(joint_old)])
        for si, have in enumerate(skin_mats):
            # 这件网格没用到的骨骼填的是默认值，不参与比较：只要用到的那些一样就能共用
            same = True
            for k, j in enumerate(joint_old):
                if j in bind and not np.allclose(have[0][k], mats[k], atol=1e-3 * max(1.0, float(np.abs(mats[k]).max()))):
                    same = j not in have[1]
                    if not same:
                        break
                    have[0][k] = mats[k]
            if same:
                have[1].update(bind.keys())
                return si
        skin_mats.append([mats, set(bind.keys())])
        return len(skin_mats) - 1

    new_meshes = []
    stats = []
    mesh_skin = {}
    merged = {}        # 材质 → [pos, nor, uv, joints, weights, idx] 各一串，最后接起来
    for ni in mesh_nodes:
        skin, prims, to_bone, bind = per_mesh[ni]
        m = js["meshes"][nodes[ni]["mesh"]]
        nprims = []
        for p, J, W in prims:
            at = p["attributes"]
            pos = read_acc(js, blob, at["POSITION"]).astype(np.float32)
            nor = read_acc(js, blob, at["NORMAL"]).astype(np.float32)
            uv = read_acc(js, blob, at["TEXCOORD_0"]).astype(np.float32)
            idx = read_acc(js, blob, p["indices"]).reshape(-1)
            W = W.copy()
            W[W < 1e-4] = 0.0
            W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-8)
            lut = np.zeros(len(skin["joints"]), dtype=np.int64)
            for k in range(len(skin["joints"])):
                lut[k] = joint_new[to_bone[k]] if k in to_bone else 0
            J2 = lut[J]
            J2[W == 0.0] = 0
            stats.append((nodes[ni]["name"], len(pos), len(idx) // 3))
            if merge:
                g = merged.setdefault(take_mat(p["material"]) if "material" in p else -1, [[], [], [], [], [], [], 0])
                for k, arr in enumerate((pos, nor, uv, J2, W, idx.astype(np.int64) + g[6])):
                    g[k].append(arr)
                g[6] += len(pos)
                continue
            a = {"POSITION": out.acc(pos, "VEC3", 34962, minmax=True), "NORMAL": out.acc(nor, "VEC3", 34962),
                 "TEXCOORD_0": out.acc(uv, "VEC2", 34962),
                 "JOINTS_0": out.acc(J2.astype(np.uint8 if len(joint_old) < 256 else np.uint16), "VEC4", 34962),
                 "WEIGHTS_0": out.acc(W.astype(np.float32), "VEC4", 34962)}
            it = idx.astype(np.uint16 if len(pos) < 65536 else np.uint32)
            np_ = {"attributes": a, "indices": out.acc(it.reshape(-1, 1), "SCALAR", 34963), "mode": p.get("mode", 4)}
            if "material" in p:
                np_["material"] = take_mat(p["material"])
            nprims.append(np_)
        mesh_skin[ni] = take_skin(bind)
        if merge:
            continue
        new_meshes.append({"name": m.get("name", nodes[ni]["name"]), "primitives": nprims})
        nn = new_nodes[remap[ni]]
        nn["mesh"] = len(new_meshes) - 1
    if merge:
        if len(skin_mats) != 1:
            raise SystemExit("--merge：各件网格的绑定矩阵不一样，共用不了一份蒙皮，并不成一件")
        nprims = []
        for mat in sorted(merged.keys()):
            g = merged[mat]
            pos, nor, uv, J2, W, idx = [np.concatenate(x) for x in g[:6]]
            a = {"POSITION": out.acc(pos, "VEC3", 34962, minmax=True), "NORMAL": out.acc(nor, "VEC3", 34962),
                 "TEXCOORD_0": out.acc(uv, "VEC2", 34962),
                 "JOINTS_0": out.acc(J2.astype(np.uint8 if len(joint_old) < 256 else np.uint16), "VEC4", 34962),
                 "WEIGHTS_0": out.acc(W.astype(np.float32), "VEC4", 34962)}
            it = idx.astype(np.uint16 if len(pos) < 65536 else np.uint32)
            np_ = {"attributes": a, "indices": out.acc(it.reshape(-1, 1), "SCALAR", 34963), "mode": 4}
            if mat >= 0:
                np_["material"] = mat
            nprims.append(np_)
        new_meshes.append({"name": "body", "primitives": nprims})
        nn = new_nodes[remap[carrier]]
        nn["mesh"] = 0
        nn["name"] = "body_mesh"
        mesh_skin = {carrier: 0}
    for si, (mats, _used) in enumerate(skin_mats):
        sk = {"name": root_name if si == 0 else "%s_%d" % (root_name, si), "joints": [remap[j] for j in joint_old],
              "inverseBindMatrices": out.acc(mats.transpose(0, 2, 1).reshape(-1, 16).astype(np.float32), "MAT4")}
        new_skins.append(sk)
    for ni in mesh_skin:
        new_nodes[remap[ni]]["skin"] = mesh_skin[ni]

    # 留用的动画：按编号认（片段名以 _编号 结尾），名字改成纯编号；只带留用骨骼的位移 / 旋转轨道
    new_anims = []
    for want in keep_anims:
        src_anim = None
        for a in js.get("animations", []):
            nm = a.get("name", "")
            if nm == want or nm.endswith("_" + want):
                src_anim = a
                break
        if src_anim is None:
            raise SystemExit("源文件里没有动画 " + want)
        samplers, channels, smap, acc_map = [], [], {}, {}
        for ch in src_anim["channels"]:
            tgt = ch["target"]
            if tgt.get("node") not in bones or tgt["path"] not in ("translation", "rotation"):
                continue
            si = ch["sampler"]
            if si not in smap:
                sm = src_anim["samplers"][si]
                pair = {}
                for key in ("input", "output"):
                    ai = sm[key]
                    if ai not in acc_map:
                        acc_map[ai] = out.acc(read_acc(js, blob, ai).astype(np.float32), js["accessors"][ai]["type"], None, key == "input")
                    pair[key] = acc_map[ai]
                pair["interpolation"] = sm.get("interpolation", "LINEAR")
                samplers.append(pair)
                smap[si] = len(samplers) - 1
            channels.append({"sampler": smap[si], "target": {"node": remap[tgt["node"]], "path": tgt["path"]}})
        new_anims.append({"name": want, "samplers": samplers, "channels": channels})

    scene_roots = [remap[r] for r in js["scenes"][js.get("scene", 0)]["nodes"] if r in remap]
    if len(scene_roots) == 1:
        new_nodes[scene_roots[0]]["name"] = root_name
    while len(out.buf) % 4:
        out.buf.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "strip_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": scene_roots}],
        "nodes": new_nodes,
        "meshes": new_meshes,
        "skins": new_skins,
        "animations": new_anims,
        "materials": new_mats,
        "textures": new_texs,
        "images": new_imgs,
        "samplers": js.get("samplers", []),
        "bufferViews": out.views,
        "accessors": out.accs,
        "buffers": [{"byteLength": len(out.buf)}],
    }
    if not new_anims:
        gltf.pop("animations")
    jraw = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(jraw) % 4:
        jraw += b" "
    total = 12 + 8 + len(jraw) + 8 + len(out.buf)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jraw), 0x4E4F534A))
        f.write(jraw)
        f.write(struct.pack("<II", len(out.buf), 0x004E4942))
        f.write(bytes(out.buf))
    import os
    print("源文件 %d 字节 → %d 字节" % (os.path.getsize(src), total))
    print("动画 %d 段 → %d %s；骨骼 %d → %d；蒙皮 %d 份；网格 %s" % (len(js.get("animations", [])), len(new_anims),
          [(a["name"], len(a["channels"])) for a in new_anims], len(js["skins"][nodes[mesh_nodes[0]]["skin"]]["joints"]), len(joint_old),
          len(new_skins), stats))
    print("贴图：", [i["name"] for i in new_imgs], "材质：", [(m.get("name"), m.get("alphaMode", "OPAQUE")) for m in new_mats])
    print("骨骼：", [nodes[j]["name"] for j in joint_old])


main()
