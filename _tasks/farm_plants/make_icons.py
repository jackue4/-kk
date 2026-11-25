"""灵种图标加工（2026-11-23）：plant_icons.gd 拍的 512 透明底成熟模型 → 裁到内容、留一点边、加一圈墨线描边和淡投影，缩成 256 见方。
用法：python -I make_icons.py <原图目录> <输出目录>（输出 = <项目>/assets/plants/icons）
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
INK = (43, 36, 31)
S = 256
for fn in sorted(os.listdir(src)):
    if not fn.endswith(".png"):
        continue
    im = Image.open(os.path.join(src, fn)).convert("RGBA")
    # 模型里飘着的零碎（血灵花头上的光点）：不连着主体、面积不到最大一块 2% 的抠掉
    arr = np.array(im)
    n, lab, st, _ = cv2.connectedComponentsWithStats((arr[:, :, 3] > 10).astype(np.uint8), 8)
    if n > 2:
        big = st[1:, cv2.CC_STAT_AREA].max()
        for i in range(1, n):
            if st[i, cv2.CC_STAT_AREA] < big * 0.02:
                arr[lab == i, 3] = 0
        im = Image.fromarray(arr)
    a = im.split()[3]
    bb = a.point(lambda v: 255 if v > 10 else 0).getbbox()
    im = im.crop(bb)
    w, h = im.size
    side = int(max(w, h) * 1.12)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - w) // 2, (side - h) // 2))
    inner = 232
    sq = sq.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    off = ((S - inner) // 2, (S - inner) // 2)
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(sq, off)
    al = body.split()[3]
    # 淡投影：往下挪 5 像素、糊开
    sh = al.filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * 0.28))
    shadow = Image.new("RGBA", (S, S), INK + (0,))
    shadow.putalpha(sh)
    canvas.alpha_composite(shadow, (0, 5))
    # 墨线描边：轮廓往外扩 3 像素
    ring = al.point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(0.7))
    edge = Image.new("RGBA", (S, S), INK + (0,))
    edge.putalpha(ring.point(lambda v: int(v * 0.92)))
    canvas.alpha_composite(edge)
    canvas.alpha_composite(body)
    canvas.save(os.path.join(dst, fn))
    print(fn, bb)
