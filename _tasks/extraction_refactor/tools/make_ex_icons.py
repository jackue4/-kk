"""搜打撤 PvP 重构（D 经济）：把生图服务出的 12 张类别图标原图（白底）加工成 assets/ui/icon_ex_*.png（128 见方、透明底）。
重跑：python -I _tasks/extraction_refactor/tools/make_ex_icons.py
原图在 _tasks/extraction_refactor/icons_raw/（有 .gdignore，Godot 不导入）。做法照 _tasks/ui_kit/make_ui.py 的 make_icon：
从四周漫水填充去白底（瓷器 / 玉上的留白不会被抠掉），往里收一点去白边，按内容裁成正方形再缩到 128。
另出一张小样 _tasks/extraction_refactor/icons_raw/../logs/icons_sheet.jpg（灰底，看抠得干不干净）。

提示词（gpt-image-2，1024 见方）= 开头 + 描述 + 结尾：
  开头：Single game item icon, traditional Chinese gongbi painting with soft watercolor wash, fine ink outlines and delicate shading,
        xianxia fantasy treasure item.
  结尾：One compact object centered, filling about 70 percent of the canvas, seen from a slight three-quarter top angle. No glow or
        halo around it. Pure white background, nothing else, no text, no seal, no calligraphy, no border, no ground shadow.
  描述：jade 云纹青白玉璧 + 红穗 · gold 饕餮纹金爵 + 小金元宝 · scroll 半展开的旧绢轴（空白）· crystal 灰石上一簇蓝紫灵晶 ·
        bone 象牙色兽牙 + 小爪骨皮绳缚 · bronze 绿锈三足小丹鼎 · sword 铜格红柄直剑 · robe 叠好的靛蓝道袍 + 玉带扣 ·
        talisman 黄纸符（朱砂云雷纹，无字）· mirror 蟠龙纹铜镜 · tag 深色木命牌 + 红绳 · pearl 红漆莲台上的夜明珠
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
RAW = HERE.parent / "icons_raw"
OUT = HERE.parent.parent.parent / "assets" / "ui"
SHEET = HERE.parent / "logs" / "icons_sheet.jpg"
NAMES = ["jade", "gold", "scroll", "crystal", "bone", "bronze", "sword", "robe", "talisman", "mirror", "tag", "pearl"]


def gblur(a, sigma):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(sigma))
    return np.asarray(im).astype(np.float32) / 255.0


def make_icon(src: Path, dst: Path, size=128):
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.float32)
    white = Image.fromarray(((a.min(axis=2) > 236.0) * 255).astype(np.uint8), "L").copy()
    w, h = white.size
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if white.getpixel(xy) == 255:
            ImageDraw.floodfill(white, xy, 128)
    al = (np.asarray(white) != 128).astype(np.float32)
    al = gblur(al, 1.6)
    al = np.clip((al - 0.35) / 0.5, 0.0, 1.0)
    ys, xs = np.where(al > 0.05)
    x0, y0 = max(xs.min() - 10, 0), max(ys.min() - 10, 0)
    x1, y1 = min(xs.max() + 11, w), min(ys.max() + 11, h)
    side = max(x1 - x0, y1 - y0)
    canvas = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    rgba = np.dstack([a, al * 255.0]).astype(np.uint8)
    piece = Image.fromarray(rgba, "RGBA").crop((x0, y0, x1, y1))
    canvas.paste(piece, ((side - piece.width) // 2, (side - piece.height) // 2))
    canvas = canvas.resize((size, size), Image.LANCZOS)
    canvas.save(dst, optimize=True)
    return canvas


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for n in NAMES:
        src = RAW / f"icon_ex_{n}.png"
        if not src.exists():
            print(f"{n}: 缺原图，跳过")
            continue
        tiles.append(make_icon(src, OUT / f"icon_ex_{n}.png"))
        print("ok", n)
    if tiles:
        SHEET.parent.mkdir(parents=True, exist_ok=True)
        sheet = Image.new("RGB", (136 * 6, 136 * ((len(tiles) + 5) // 6)), (150, 140, 128))
        for i, t in enumerate(tiles):
            sheet.paste(t, (136 * (i % 6) + 4, 136 * (i // 6) + 4), t)
        sheet.save(SHEET, quality=88)
        print("sheet", SHEET)


if __name__ == "__main__":
    main()
