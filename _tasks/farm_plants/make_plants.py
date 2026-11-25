"""灵田种植系统的植物模型（2026-11-23）：从 H:\\游戏资源\\miniw_assets 的方块模型里取各生长阶段，
把每种作物各阶段 GLB 里重复内嵌的同一张贴图抽出来共用（assets/plants/<作物>.png），各阶段 GLB 只留几何、贴图改成外部引用。
冰果作物原来每个阶段都嵌一张 525 KB 的 PNG（五个阶段 2.9 MB），抽出来以后只剩一张图 + 几 KB 的几何。

用法：python -I _tasks/farm_plants/make_plants.py      （之后要 --headless --import 一遍）
"""
import hashlib
import json
import os
import struct
import sys

SRC = "H:/游戏资源/miniw_assets/07_方块模型"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "plants"))

# 作物 → [(阶段名, 源目录, 文件名)]（阶段从小到大，最后一个是成熟可收的样子）
CROPS = {
    "berry": [("s0", "彩虹草莓作物_200172", "彩虹草莓作物_方块模型.glb"),
              ("s1", "彩虹草莓作物_200172", "彩虹草莓作物_方块模型_非默认组_1.glb"),
              ("s2", "彩虹草莓作物_200172", "彩虹草莓作物_方块模型_非默认组_2.glb"),
              ("s3", "彩虹草莓作物_200172", "彩虹草莓作物_方块模型_非默认组_3.glb"),
              ("ripe", "彩虹草莓作物_200172", "彩虹草莓作物_方块模型_非默认组_4.glb")],
    "lotusroot": [("s0", "莲藕作物_200131", "莲藕作物_方块模型.glb"),
                  ("s1", "莲藕作物_200131", "莲藕作物_方块模型_非默认组_1.glb"),
                  ("s2", "莲藕作物_200131", "莲藕作物_方块模型_非默认组_2.glb"),
                  ("ripe", "莲藕作物_200131", "莲藕作物_方块模型_非默认组_3.glb")],
    "flamemelon": [("s0", "烈焰瓜作物_200189", "烈焰瓜作物_方块模型.glb"),
                   ("s1", "烈焰瓜作物_200189", "烈焰瓜作物_方块模型_非默认组_1.glb"),
                   ("s2", "烈焰瓜作物_200189", "烈焰瓜作物_方块模型_非默认组_2.glb"),
                   ("s3", "烈焰瓜作物_200189", "烈焰瓜作物_方块模型_非默认组_3.glb"),
                   ("ripe", "丰硕烈焰瓜作物_200192", "丰硕烈焰瓜作物_方块模型.glb")],
    "icefruit": [("s0", "冰果作物_200185", "冰果作物_方块模型.glb"),
                 ("s1", "冰果作物_200185", "冰果作物_方块模型_非默认组_1.glb"),
                 ("s2", "冰果作物_200185", "冰果作物_方块模型_非默认组_2.glb"),
                 ("s3", "冰果作物_200185", "冰果作物_方块模型_非默认组_3.glb"),
                 ("ripe", "丰硕冰果作物_200188", "丰硕冰果作物_方块模型.glb")],
    # 五味灵草没有成套的生长阶段：嫩芽用龙血花的苗、彼岸花用自己的花苞，往后是成熟模型按比例放大（模型在 assets/creatures/herb_*.glb）
    "sprout": [("s0", "龙血花（苗）_1498", "龙血花（苗）_方块模型.glb")],
    "higanbud": [("s0", "彼岸种子_1194", "彼岸种子_方块模型.glb")],
}


def read_glb(p):
    b = open(p, "rb").read()
    magic, ver, total = struct.unpack("<4sII", b[:12])
    assert magic == b"glTF", p
    off = 12
    js = None
    binc = b""
    while off < total:
        ln, typ = struct.unpack("<I4s", b[off:off + 8])
        data = b[off + 8:off + 8 + ln]
        if typ == b"JSON":
            js = json.loads(data)
        elif typ == b"BIN\x00":
            binc = data
        off += 8 + ln
    return js, binc


def write_glb(p, js, binc):
    jb = json.dumps(js, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binc += b"\x00" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(binc) if binc else 0)
    out = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(jb), b"JSON") + jb
    if binc:
        out += struct.pack("<I4s", len(binc), b"BIN\x00") + binc
    open(p, "wb").write(out)


def strip_images(js, binc, uri_for):
    """images 里引用 bufferView 的图换成外部 uri，并把这些 bufferView 的字节从 BIN 里拿掉（其余 bufferView 重新排偏移）"""
    img_views = set()
    for i, im in enumerate(js.get("images", [])):
        if "bufferView" in im:
            img_views.add(im["bufferView"])
    views = js.get("bufferViews", [])
    remap = {}
    newbin = bytearray()
    newviews = []
    for vi, v in enumerate(views):
        if vi in img_views:
            continue
        start = v.get("byteOffset", 0)
        data = binc[start:start + v["byteLength"]]
        while len(newbin) % 4:
            newbin.append(0)
        nv = dict(v)
        nv["byteOffset"] = len(newbin)
        nv["buffer"] = 0
        newbin += data
        remap[vi] = len(newviews)
        newviews.append(nv)
    images = []
    for i, im in enumerate(js.get("images", [])):
        if "bufferView" in im:
            images.append({"uri": uri_for(i, im)})
        else:
            images.append(im)
    js["images"] = images
    js["bufferViews"] = newviews
    for acc in js.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
        sp = acc.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    js["buffers"] = [{"byteLength": len(newbin)}]
    return js, bytes(newbin)


def main():
    os.makedirs(OUT, exist_ok=True)
    report = []
    for crop, stages in CROPS.items():
        pngs = {}      # sha → 文件名
        for st, d, f in stages:
            js, binc = read_glb(os.path.join(SRC, d, f))
            names = {}
            for i, im in enumerate(js.get("images", [])):
                if "bufferView" not in im:
                    continue
                v = js["bufferViews"][im["bufferView"]]
                data = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
                sha = hashlib.sha1(data).hexdigest()
                if sha not in pngs:
                    nm = crop + ("" if not pngs else "_%d" % len(pngs)) + ".png"
                    open(os.path.join(OUT, nm), "wb").write(data)
                    pngs[sha] = nm
                names[i] = pngs[sha]
            js, nb = strip_images(js, binc, lambda i, im: names[i])
            dst = os.path.join(OUT, "%s_%s.glb" % (crop, st))
            write_glb(dst, js, nb)
            report.append("%s_%s.glb %d 字节（原 %d）贴图 %s" % (crop, st, os.path.getsize(dst), os.path.getsize(os.path.join(SRC, d, f)), ",".join(sorted(set(names.values())))))
        report.append("%s：共用贴图 %d 张 %s" % (crop, len(pngs), ", ".join("%s %d 字节" % (n, os.path.getsize(os.path.join(OUT, n))) for n in pngs.values())))
    open(os.path.join(HERE, "make_plants_report.txt"), "w", encoding="utf-8").write("\n".join(report) + "\n")


if __name__ == "__main__":
    main()
