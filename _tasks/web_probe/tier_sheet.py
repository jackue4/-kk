"""把 --spark-tiers 拍的各境界截图拼成两张总览（崩拳命中 / 对波中段），方便一眼比各档。
用法：python tier_sheet.py <_shots 目录> <输出前缀>   → <前缀>_hit.jpg / <前缀>_clash.jpg（各 3 列 2 行，结丹 ~ 大乘）"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

shots, out = sys.argv[1], sys.argv[2]
names = ["结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
try:
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 30)
except Exception:
    font = ImageFont.load_default()
for kind in ["hit", "clash"]:
    W, H = 640, 360
    sheet = Image.new("RGB", (W * 3, H * 2), (20, 20, 24))
    for i, nm in enumerate(names):
        fs = glob.glob(os.path.join(shots, "duel_tr_%d_*_%s.png" % (i + 2, kind)))
        if not fs:
            continue
        im = Image.open(fs[0]).convert("RGB").resize((W, H), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 110, 44), fill=(0, 0, 0))
        d.text((10, 4), nm, fill=(255, 230, 150), font=font)
        sheet.paste(im, ((i % 3) * W, (i // 3) * H))
    sheet.save("%s_%s.jpg" % (out, kind), quality=88)
print("ok")
