"""拳劲对拼各境界各阶段截图的整理（只读原图、另存 JPG，不改原图）。
用法：python -I make_sheets.py <截图根目录 _shots/brawl_gallery> <档位 desktop|mobile> [标题补充]
产出（都在 <根目录>/<档位>/ 下）：
  labeled/<原名>.jpg        每张原图顶上加一条「境界 · 序号 · 阶段 · 说明」的标注条
  overview_<档位>.jpg        总览：行 = 境界（炼气 → 大乘），列 = 六个阶段
  climax_<档位>.jpg          裂缝对照：每个境界的「换位对撞」「分胜负」两张，裁画面中间一半、按原像素放（看特效层次）
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\msyh.ttc"
STAGES = ["起手撞拳", "连续互殴", "换位冲刺", "换位对撞", "分胜负", "分开"]
NOTE = {
    "起手撞拳": "两拳相撞：慢放、冲击波 + 火花 + 空间波动；元婴起第一道大裂缝",
    "连续互殴": "每 0.085 秒一拳；元婴起隔几拳裂一道小缝",
    "换位冲刺": "两人裹在一起冲到下一处（残影 + 连线）",
    "换位对撞": "冲到位撞在一起：大裂缝、炼虚起竖缝、画面碎一下",
    "分胜负": "赢的一方重手打飞对面：最大的裂缝，合体起裂隙内塌",
    "分开": "对面被打飞出去，镜头从侧面机位混回跟随",
}
CRACK = {"炼气": "无空战\n（强制进入，仅对照）", "筑基": "无空战\n（强制进入，仅对照）", "结丹": "无裂缝（对照）",
         "元婴": "裂缝 1 档", "化神": "裂缝 2 档", "炼虚": "裂缝 3 档 + 竖缝", "合体": "裂缝 4 档 + 竖缝", "大乘": "裂缝 5 档 + 竖缝"}
PAT = re.compile(r"^(\d\d)_(.+?)(（强制）)?_(\d)_(.+)\.png$")


def font(size):
    return ImageFont.truetype(FONT, size)


def load(dir_: Path):
    shots = {}
    for p in sorted(dir_.glob("*.png")):
        m = PAT.match(p.name)
        if not m:
            continue
        r = int(m.group(1))
        shots[(r, int(m.group(4)))] = (p, m.group(2), bool(m.group(3)), m.group(5))
    return shots


def labeled(shots, out: Path):
    out.mkdir(exist_ok=True)
    f1, f2 = font(30), font(22)
    for (r, s), (p, realm, forced, stage) in shots.items():
        im = Image.open(p).convert("RGB")
        bar = 64
        can = Image.new("RGB", (im.width, im.height + bar), (24, 22, 30))
        can.paste(im, (0, bar))
        d = ImageDraw.Draw(can)
        d.text((16, 12), f"{r:02d} {realm}{'（强制）' if forced else ''} · {s} {stage}", font=f1, fill=(245, 235, 210))
        d.text((16 + d.textlength(f"{r:02d} {realm}{'（强制）' if forced else ''} · {s} {stage}", font=f1) + 24, 20),
               NOTE.get(stage, "") + "　｜　" + CRACK.get(realm, "").replace("\n", ""), font=f2, fill=(190, 185, 175))
        can.save(out / (p.stem + ".jpg"), quality=88)


def overview(shots, out: Path, title: str):
    realms = sorted({r for r, _ in shots})
    tw, th = 400, int(400 * 9 / 16)
    sample = next(iter(shots.values()))[0]
    w0, h0 = Image.open(sample).size
    th = int(tw * h0 / w0)
    left, top, gap = 230, 120, 8
    W = left + len(STAGES) * (tw + gap) + 12
    H = top + len(realms) * (th + gap + 26) + 12
    can = Image.new("RGB", (W, H), (20, 19, 26))
    d = ImageDraw.Draw(can)
    d.text((16, 12), title, font=font(34), fill=(245, 235, 210))
    for i, st in enumerate(STAGES):
        x = left + i * (tw + gap)
        d.text((x + 6, 70), f"{i + 1} {st}", font=font(26), fill=(235, 215, 160))
    for j, r in enumerate(realms):
        y = top + j * (th + gap + 26)
        info = next((v for (rr, _), v in shots.items() if rr == r), None)
        realm, forced = info[1], info[2]
        d.text((14, y + 8), f"{r:02d} {realm}", font=font(34), fill=(245, 235, 210))
        d.multiline_text((14, y + 56), CRACK.get(realm, ""), font=font(19), fill=(190, 185, 175), spacing=6)
        for i in range(len(STAGES)):
            x = left + i * (tw + gap)
            v = shots.get((r, i + 1))
            if v is None:
                d.rectangle((x, y + 26, x + tw, y + 26 + th), outline=(90, 80, 80))
                d.text((x + 12, y + 26 + th // 2 - 12), "没截到", font=font(22), fill=(200, 120, 110))
                continue
            im = Image.open(v[0]).convert("RGB").resize((tw, th), Image.LANCZOS)
            can.paste(im, (x, y + 26))
            d.text((x + 4, y + 2), f"{r:02d}-{i + 1} {realm}{'·强制' if forced else ''} · {STAGES[i]}", font=font(18), fill=(225, 220, 210))
    can.save(out, quality=88)


def climax(shots, out: Path, title: str):
    realms = sorted({r for r, _ in shots})
    sample = next(iter(shots.values()))[0]
    w0, h0 = Image.open(sample).size
    cw, chh = w0 // 2, h0 // 2
    left, top, gap = 230, 110, 10
    W = left + 2 * (cw + gap) + 12
    H = top + len(realms) * (chh + gap + 26) + 12
    can = Image.new("RGB", (W, H), (20, 19, 26))
    d = ImageDraw.Draw(can)
    d.text((16, 12), title, font=font(34), fill=(245, 235, 210))
    for i, s in enumerate((4, 5)):
        d.text((left + i * (cw + gap) + 6, 66), f"{s} {STAGES[s - 1]}（画面中间一半，原像素）", font=font(24), fill=(235, 215, 160))
    for j, r in enumerate(realms):
        y = top + j * (chh + gap + 26)
        info = next((v for (rr, _), v in shots.items() if rr == r), None)
        d.text((14, y + 8), f"{r:02d} {info[1]}", font=font(34), fill=(245, 235, 210))
        d.multiline_text((14, y + 56), CRACK.get(info[1], ""), font=font(19), fill=(190, 185, 175), spacing=6)
        for i, s in enumerate((4, 5)):
            x = left + i * (cw + gap)
            v = shots.get((r, s))
            if v is None:
                d.text((x + 12, y + 26 + chh // 2), "没截到", font=font(22), fill=(200, 120, 110))
                continue
            im = Image.open(v[0]).convert("RGB")
            can.paste(im.crop((w0 // 4, h0 // 4, w0 // 4 + cw, h0 // 4 + chh)), (x, y + 26))
            d.text((x + 4, y + 2), f"{r:02d}-{s} {info[1]} · {STAGES[s - 1]}", font=font(18), fill=(225, 220, 210))
    can.save(out, quality=90)


def main():
    root, tier = Path(sys.argv[1]), sys.argv[2]
    extra = sys.argv[3] if len(sys.argv) > 3 else ""
    d = root / tier
    shots = load(d)
    print(f"{tier}: {len(shots)} 张")
    labeled(shots, d / "labeled")
    name = "桌面档" if tier == "desktop" else "手机画质档"
    overview(shots, d / f"overview_{tier}.jpg", f"拳劲对拼 · 各境界各阶段实机截图（{name}{extra}）")
    climax(shots, d / f"climax_{tier}.jpg", f"拳劲对拼 · 换位对撞 / 分胜负 的特效层次（{name}{extra}）")


if __name__ == "__main__":
    main()
