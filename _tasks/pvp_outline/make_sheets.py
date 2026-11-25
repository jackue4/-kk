"""PvP 锁定描边自检截图 → 对照图（只读原图、另存 JPG）。
用法：python -I make_sheets.py <桌面档截图目录> <手机档截图目录> <网页截图目录> <输出目录>
  compare.jpg：三行（桌面 / 手机画质 / 网页）× 两列（改之前 / 现在），同一机位锁定敌甲
  states_<档>.jpg：各状态（动作贴合 ×2、切换、解锁、倒下、觉醒 + 锁定、地面近战）
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\msyh.ttc"
STATES = [("03_pose_f_sm", "动作贴合：砸击"), ("03_pose_f_rush", "动作贴合：突进"), ("04_switch_to_e2", "切换锁定 → 敌乙"), ("05_unlocked", "解锁：都不描"),
          ("06_e1_down", "敌甲倒下 → 锁到敌乙"), ("07_awaken_and_locked", "觉醒中被锁：红色优先"), ("08_ground_locked", "地面近战（炼气）")]


def f(sz):
    return ImageFont.truetype(FONT, sz)


def find(d: Path, key: str):
    for p in sorted(d.glob("*%s*.jpg" % key)) + sorted(d.glob("*%s*.png" % key)):
        return p
    return None


def tile(p, w):
    im = Image.open(p).convert("RGB")
    return im.resize((w, int(w * im.height / im.width)), Image.LANCZOS)


def main():
    dirs = [("桌面档（Forward+）", Path(sys.argv[1])), ("手机画质档（兼容渲染 + 触屏）", Path(sys.argv[2])), ("网页版（无界面 Edge 手机模拟 740×360）", Path(sys.argv[3]))]
    out = Path(sys.argv[4])
    out.mkdir(parents=True, exist_ok=True)
    tw = 760
    rows = []
    for name, d in dirs:
        a, b = find(d, "01_before_locked"), find(d, "02_after_locked")
        if a and b:
            rows.append((name, tile(a, tw), tile(b, tw)))
    th = max(r[1].height for r in rows)
    W, H = 30 + 2 * (tw + 16), 110 + len(rows) * (th + 60)
    can = Image.new("RGB", (W, H), (248, 246, 240))
    d = ImageDraw.Draw(can)
    d.text((24, 18), "PvP 锁定描边：同一机位锁定敌甲（中间那位），改之前 vs 现在", font=f(32), fill=(30, 30, 30))
    d.text((24, 62), "左：改之前（不描）　右：现在（只有被锁的敌方玩家一圈红色轮廓；左边青色名牌是队友、右边是另一个敌人、前景是自己，都不描）", font=f(19), fill=(90, 85, 80))
    for j, (name, a, b) in enumerate(rows):
        y = 110 + j * (th + 60)
        d.text((24, y), name, font=f(24), fill=(30, 30, 30))
        can.paste(a, (24, y + 34))
        can.paste(b, (24 + tw + 16, y + 34))
    can.save(out / "compare.jpg", quality=90)
    for name, dd in dirs:
        ims = [(cap, find(dd, key)) for key, cap in STATES]
        ims = [(c, p) for c, p in ims if p]
        if not ims:
            continue
        cw = 560
        tiles = [(c, tile(p, cw)) for c, p in ims]
        ch = max(t.height for _, t in tiles)
        cols = 4
        nr = (len(tiles) + cols - 1) // cols
        can = Image.new("RGB", (24 + cols * (cw + 12), 80 + nr * (ch + 44)), (248, 246, 240))
        d = ImageDraw.Draw(can)
        d.text((24, 18), "PvP 锁定描边 · 各状态（%s）" % name, font=f(28), fill=(30, 30, 30))
        for i, (c, t) in enumerate(tiles):
            x = 24 + (i % cols) * (cw + 12)
            y = 80 + (i // cols) * (ch + 44)
            d.text((x, y), c, font=f(20), fill=(40, 40, 40))
            can.paste(t, (x, y + 30))
        tag = "desktop" if name.startswith("桌面") else ("mobile" if name.startswith("手机") else "web")
        can.save(out / ("states_%s.jpg" % tag), quality=88)
    print("ok")


if __name__ == "__main__":
    main()
