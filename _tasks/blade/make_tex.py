import sys
import numpy as np
from PIL import Image
src, rm, out, prev = sys.argv[1:5]
o = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
r = np.asarray(Image.open(rm).convert("RGBA")).astype(np.float32) / 255.0
a_body = r[..., 3]
# 黑底亮度键：火星 / 金星 / 外发光（JPEG 噪点压掉）
lum = o.max(axis=2)
a_glow = np.clip((lum - 0.06) / 0.30, 0.0, 1.0) ** 0.9
a = np.maximum(a_body, a_glow)
# 颜色：刀身（含墨边）用原图色；纯发光区按 alpha 反预乘，免得边缘发灰
un = np.clip(o / np.maximum(a_glow[..., None], 1e-3), 0.0, 1.0)
w = a_body[..., None]
rgb = o * w + un * (1.0 - w)
rgba = np.dstack([rgb, a])
# 裁成横向刀光：按 alpha 的包围盒，左右留 2%，上下留 6%
ys, xs = np.where(a > 0.04)
x0, x1 = xs.min(), xs.max(); y0, y1 = ys.min(), ys.max()
mx = int((x1 - x0) * 0.02); my = int((y1 - y0) * 0.06)
H, W = a.shape
x0 = max(x0 - mx, 0); x1 = min(x1 + mx, W - 1); y0 = max(y0 - my, 0); y1 = min(y1 + my, H - 1)
crop = rgba[y0:y1 + 1, x0:x1 + 1]
img = Image.fromarray((crop * 255.0 + 0.5).astype(np.uint8), "RGBA")
# 宽 1024，高按比例取到 4 的倍数
nh = max(4, int(round(img.height * 1024 / img.width / 4.0)) * 4)
img = img.resize((1024, nh), Image.LANCZOS)
img.save(out)
print("crop box", (x0, y0, x1, y1), "->", img.size)
bg = Image.new("RGBA", img.size, (40, 44, 52, 255)); bg.alpha_composite(img)
chk = Image.new("RGBA", img.size, (255, 255, 255, 255)); chk.alpha_composite(img)
both = Image.new("RGB", (img.width, img.height * 2)); both.paste(bg.convert("RGB"), (0, 0)); both.paste(chk.convert("RGB"), (0, img.height))
both.thumbnail((800, 800)); both.save(prev)
# 竖向 alpha 剖面（找刀芯所在的 v）
prof = np.asarray(img)[..., 3].astype(np.float32).mean(axis=1)
print("alpha profile (per 10% of height):", [round(float(prof[int(i * (len(prof) - 1) / 10)]), 1) for i in range(11)])
