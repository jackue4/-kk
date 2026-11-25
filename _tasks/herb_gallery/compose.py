"""把 tiles/<页>_<序号>.png 拼成带中文名的总览图：A 单株灵草、B 作物分阶段（每种作物一行）、I 道具。"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
T = os.path.join(HERE, "tiles")
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(T, "tiles.tsv"), encoding="utf-8") if l.strip()]
F = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
F2 = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
TS = 240


def tile(page, idx, name, dims):
    p = os.path.join(T, "%s_%s.png" % (page, idx))
    im = Image.open(p).convert("RGB").resize((TS, TS), Image.LANCZOS) if os.path.exists(p) else Image.new("RGB", (TS, TS), (200, 200, 200))
    c = Image.new("RGB", (TS, TS + 46), (246, 246, 248))
    c.paste(im, (0, 0))
    d = ImageDraw.Draw(c)
    d.text((6, TS + 2), name, fill=(20, 20, 24), font=F)
    d.text((6, TS + 25), "原始尺寸 " + dims, fill=(110, 110, 120), font=F2)
    return c


def sheet(cells_rows, out, title):
    cols = max(len(r) for r in cells_rows)
    W = cols * (TS + 6) + 6
    H = len(cells_rows) * (TS + 52) + 46
    s = Image.new("RGB", (W, H), (60, 62, 70))
    d = ImageDraw.Draw(s)
    d.text((10, 8), title, fill=(255, 255, 255), font=F)
    for ri, r in enumerate(cells_rows):
        for ci, t in enumerate(r):
            s.paste(t, (6 + ci * (TS + 6), 40 + ri * (TS + 52)))
    s.save(out, quality=86)
    print(out, s.size)


by = {"A": [], "B": [], "I": []}
for page, idx, name, dims in rows:
    by[page].append((idx, name, dims))
# A：每行 8 个，分两张
a = [tile("A", i, n, dm) for i, n, dm in by["A"]]
sheet([a[k:k + 8] for k in range(0, 24, 8)], os.path.join(HERE, "灵草候选_单株_1.jpg"), "单株灵草候选（一）：07_方块模型，按包围盒统一缩放")
sheet([a[k:k + 8] for k in range(24, len(a), 8)], os.path.join(HERE, "灵草候选_单株_2.jpg"), "单株灵草候选（二）")
# B：按作物分行
groups = []
keys = {}
for i, n, dm in by["B"]:
    k = n.split("·")[0].replace("丰硕", "").replace("作物", "")
    if k not in keys:
        keys[k] = len(groups)
        groups.append([])
    groups[keys[k]].append(tile("B", i, n, dm))
sheet(groups[:7], os.path.join(HERE, "灵草候选_作物分阶段_1.jpg"), "作物（每行一种：默认组 → 非默认组 1/2/3… → 丰硕）（一）")
sheet(groups[7:], os.path.join(HERE, "灵草候选_作物分阶段_2.jpg"), "作物（每行一种）（二）")
it = [tile("I", i, n, dm) for i, n, dm in by["I"]]
sheet([it[k:k + 8] for k in range(0, len(it), 8)], os.path.join(HERE, "灵草候选_道具.jpg"), "道具：果实 / 种子 / 菌种 / 草木灰 / 花洒 / 稻草人（03_道具）")
