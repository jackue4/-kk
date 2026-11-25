"""把生图出来的白底漫画立绘抠成透明底，存成样张用的 _tasks/ui_comic/art/<英雄 id>.png。
用法：python -I _tasks/ui_comic/make_art.py <英雄 id>   （原图是 art/raw/gen_<id>.png）
做法：从四边往里漫水填充接近白的像素（人身上被墨线围住的白裤子 / 白头巾不会被填掉），填到的变透明，边上羽化一个像素。
提示词（2026-11-25，edit_image / gpt-image-2，参考图 = 3D 模型的小图 art/raw/ref_<id>_tiny.jpg）记在 PROMPTS 里。"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
PROMPTS = {
    "yujian": "Redraw this chibi 3D game character as a hand-inked comic book key-art illustration. Keep exactly the same character design: "
              "big-head chibi proportions, cream-blonde short hair, white headscarf with a tall purple feather and a gold crescent-moon-and-stars ornament, "
              "tanned skin, purple eyes, confident grin, white cropped vest with purple and gold trim, purple star-patterned armband, gold coin belt, "
              "white baggy pants, gold bracers, dark pointed shoes. New pose: a dynamic martial-arts punch toward the viewer with strong foreshortening, "
              "one big fist in front, body twisted, feet wide apart. Style: bold thick black brush outlines of varying weight, flat cel shading with two tones, "
              "halftone dot shadows, a few hatching strokes, vivid saturated colours, American comic mixed with wuxia manhua. Full body, centered, "
              "portrait format, pure white background, no text, no logo, no frame, no ground shadow.",
}


def main():
    hid = sys.argv[1]
    im = Image.open(HERE / "art" / "raw" / ("gen_%s.png" % hid)).convert("RGB")
    w, h = im.size
    key = (255, 0, 255)
    work = im.copy()
    seeds = [(x, y) for x in range(0, w, 16) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 16) for x in (0, w - 1)]
    for s in seeds:
        px = work.getpixel(s)
        if px != key and min(px) > 232:
            ImageDraw.floodfill(work, s, key, thresh=26)
    mask = Image.new("L", (w, h), 255)
    mp = mask.load()
    wp = work.load()
    for y in range(h):
        for x in range(w):
            if wp[x, y] == key:
                mp[x, y] = 0
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = im.convert("RGBA")
    out.putalpha(mask)
    bbox = mask.point(lambda v: 255 if v > 8 else 0).getbbox()
    out = out.crop(bbox)
    dst = HERE / "art" / ("%s.png" % hid)
    out.save(dst)
    prev = Image.new("RGBA", out.size, (240, 140, 30, 255))
    prev.alpha_composite(out)
    prev = prev.convert("RGB")
    prev.thumbnail((700, 700))
    prev.save(HERE / "art" / "raw" / ("cut_%s_preview.jpg" % hid), quality=88)
    print("wrote", dst, out.size)


main()
