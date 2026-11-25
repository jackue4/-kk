"""主城「元界面」（备战 / 坊市 / 段位 / 英雄，scripts/ex/meta_*.gd）用的线稿素材（白 + 透明度，游戏里用 modulate 染成金色 / 墨色）。

2026-11-24 晚：用户提高了生图预算，水墨图腾改用生图服务出的（gpt-image-2，白底黑墨，五张原图在 raw/，提示词记在下面 PROMPTS 里）：
  raw/dock.png       2×2：束发侠客 / 行囊与剑 / 灯笼与铜钱 / 山峰与日   → meta_icon_hero / _prep / _shop / _rank.png（主城四个入口）
  raw/slots.png      3×2：剑 / 冠 / 衣 / 护腿 / 履 / 玉佩               → meta_slot_weapon / _armor0..3 / _chip.png（空装备栏里的淡影）
  raw/ring.png       星盘                                              → meta_ring.png（人物 / 段位徽记背后慢慢转）
  raw/ornaments.png  2×2：云纹角花 / 祥云 / 莲花分隔线 / 中国结          → meta_corner / meta_cloud / meta_divider.png（结没用）
  raw/crests.png     3×2：卵石 / 气旋 / 台基 / 火焰丹 / 莲中婴 / 日月山   → meta_crest_0..5.png（段位徽记：未入流 / 炼气 / 筑基 / 结丹 / 元婴 / 化神）
加工 = 按亮度转透明度、按格子裁出各自的外框、补成方的、缩到合适大小。
另外两张还是程序画的：meta_rule.png（顶栏底下那道两头淡出的长线）、meta_icon_back.png（返回的尖角）。
原图不在（或加 --vector）时退回全套程序画的矢量线稿（第一版，生图预算被拦时顶上的）。

重跑：python -I _tasks/ui_meta/make_meta_art.py   之后 godot --headless --path . --import
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent.parent / "assets" / "ui"
RAW = Path(__file__).resolve().parent / "raw"
SS = 4      # 超采样倍数

## 五张原图的提示词（gpt-image-2；1024×1024 或 1536×1024）
PROMPTS = {
    "dock": "Four separate black ink brush icons arranged in a 2x2 grid on a pure white background, each icon centered in its own quadrant with wide empty white margins around it, bold expressive Chinese ink-brush strokes with dry-brush texture, solid black ink, minimal emblem style, thick readable silhouettes, no text, no characters, no seal, no border, no dividing lines. Top-left: head-and-shoulders silhouette of a xianxia swordsman hero with a topknot hair crown and two flowing ribbons. Top-right: a travelling cloth bundle backpack with a straight sword strapped diagonally across it. Bottom-left: a hanging shop lantern with a tassel beside a string of three ancient round coins with square holes. Bottom-right: a mountain peak crest with a rising sun halo behind it and three ascending steps.",
    "slots": "Six separate black ink brush icons arranged in a grid of 3 columns and 2 rows on a pure white background, each icon centered in its own cell with wide empty white margins, simple bold Chinese ink-brush silhouettes with dry-brush texture, solid black ink, minimal, thick readable shapes, no text, no characters, no seal, no border, no dividing lines. Row 1 from left: a straight Chinese jian sword pointing diagonally up; an ancient Chinese hair crown (guan) with a hairpin through it; a cross-collar hanfu robe top with wide sleeves. Row 2 from left: a pair of armored leg guards (greaves); a pair of cloth boots with upturned toes; a round jade pendant talisman hanging from a cord with a tassel.",
    "ring": "A large circular astrolabe ring drawn in black Chinese ink brush on a pure white background, perfectly centered and filling most of the image: three concentric thin dry-brush rings, short tick marks all around like a compass dial, eight groups of bagua trigram line marks spaced evenly around the middle ring, a few small constellation dots joined by fine lines, the centre of the circle left completely empty white. Elegant, sparse, hand-drawn ink, no text, no Chinese characters, no seal, nothing outside the circle.",
    "ornaments": "Four separate black ink brush ornaments arranged in a 2x2 grid on a pure white background, each centered in its own quadrant with wide empty white margins, elegant Chinese ink-brush line work, solid black ink, no text, no characters, no seal, no border, no dividing lines. Top-left: an L-shaped corner bracket ornament for the top-left corner of a picture frame, made of two thin lines meeting at a right angle with a small auspicious ruyi cloud scroll curling at the corner. Top-right: a single standalone auspicious cloud (xiangyun) swirl with a trailing tail. Bottom-left: a long horizontal divider flourish, a thin dry-brush line with a small lotus bud knot at its centre. Bottom-right: a diamond-shaped Chinese knot with a short tassel.",
    "crests": "Six separate black ink brush crest emblems arranged in a grid of 3 columns and 2 rows on a pure white background, each emblem centered in its own cell with wide empty white margins, bold Chinese ink-brush silhouettes with dry-brush texture, solid black ink, emblem style, no text, no characters, no seal, no border, no dividing lines. Row 1 from left: a plain smooth round river stone; a swirling wisp of rising qi vapor like a small spiral cloud; a three-tier stone pagoda foundation base. Row 2 from left: a radiant round pearl core surrounded by a flame aura; a tiny seated meditating figure inside an open lotus flower; a crown-like crest of a sun and crescent moon above a mountain peak with rays.",
}


class Canvas:
    """单通道画布（0~255 的透明度）。坐标一律 0~1（乘上 w / h），线宽也是 0~1（乘上 w）"""

    def __init__(self, w, h=None):
        self.w, self.h = w, h or w
        self.im = Image.new("L", (self.w * SS, self.h * SS), 0)
        self.d = ImageDraw.Draw(self.im)

    def _p(self, p):
        return (p[0] * self.w * SS, p[1] * self.h * SS)

    def line(self, pts, width, a=255, closed=False):
        pts = list(pts) + ([pts[0]] if closed else [])
        px = [self._p(p) for p in pts]
        wpx = max(1, int(round(width * self.w * SS)))
        self.d.line(px, fill=a, width=wpx, joint="curve")
        r = wpx / 2.0
        for x, y in px:      # 圆头、圆角
            self.d.ellipse((x - r, y - r, x + r, y + r), fill=a)

    def poly(self, pts, a=255):
        self.d.polygon([self._p(p) for p in pts], fill=a)

    def circle(self, c, r, a=255):
        x, y = self._p(c)
        rr = r * self.w * SS
        self.d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=a)

    def ellipse(self, c, rx, ry, a=255):
        x, y = self._p(c)
        self.d.ellipse((x - rx * self.w * SS, y - ry * self.h * SS, x + rx * self.w * SS, y + ry * self.h * SS), fill=a)

    def ring(self, c, r, width, a=255):
        x, y = self._p(c)
        rr = r * self.w * SS
        wpx = max(1, int(round(width * self.w * SS)))
        self.d.ellipse((x - rr, y - rr, x + rr, y + rr), outline=a, width=wpx)

    def arc(self, c, r, a0, a1, width, a=255):
        n = max(8, int(abs(a1 - a0) / 3.0))
        pts = [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
        self.line(pts, width, a)

    def rect(self, x0, y0, x1, y1, a=255):
        self.d.rectangle((x0 * self.w * SS, y0 * self.h * SS, x1 * self.w * SS, y1 * self.h * SS), fill=a)

    def alpha(self):
        return np.asarray(self.im.resize((self.w, self.h), Image.LANCZOS)).astype(np.float32)

    def save(self, name, mul=None):
        a = self.alpha()
        if mul is not None:
            a = a * mul
        rgba = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        rgba[..., :3] = 255
        rgba[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
        Image.fromarray(rgba, "RGBA").save(OUT / f"{name}.png")
        print("wrote", name, (self.w, self.h))


def polar(c, r, deg):
    return (c[0] + r * math.cos(math.radians(deg)), c[1] + r * math.sin(math.radians(deg)))


# ---------------- 星盘 ----------------

def ring():
    cv = Canvas(768)
    c = (0.5, 0.5)
    cv.ring(c, 0.474, 0.0045, 230)
    cv.ring(c, 0.446, 0.002, 170)
    for i in range(120):
        deg = i * 3.0
        long = i % 5 == 0
        cv.line([polar(c, 0.446 if long else 0.458, deg), polar(c, 0.472, deg)], 0.003 if long else 0.0018, 220 if long else 130)
    for i in range(4):      # 四正位各一枚小菱形
        p = polar(c, 0.474, i * 90.0 - 90.0)
        s = 0.013
        cv.poly([(p[0], p[1] - s), (p[0] + s, p[1]), (p[0], p[1] + s), (p[0] - s, p[1])], 255)
    cv.ring(c, 0.368, 0.003, 200)
    # 八卦：每卦三爻，阳爻一整条、阴爻中间断开；先天八卦的次序（乾在上）
    gua = ["111", "011", "101", "001", "110", "010", "100", "000"]
    order = [0, 4, 5, 6, 7, 3, 2, 1]      # 顺时针：乾 巽 坎 艮 坤 震 离 兑
    for k in range(8):
        deg = -90.0 + k * 45.0
        bits = gua[order[k]]
        for j in range(3):
            r = 0.386 + j * 0.016
            half = 5.2
            if bits[j] == "1":
                cv.arc(c, r, deg - half, deg + half, 0.0075, 235)
            else:
                cv.arc(c, r, deg - half, deg - 1.3, 0.0075, 235)
                cv.arc(c, r, deg + 1.3, deg + half, 0.0075, 235)
    for i in range(60):      # 里圈：虚线
        cv.arc(c, 0.305, i * 6.0, i * 6.0 + 3.6, 0.0022, 150)
    rng = np.random.default_rng(11)
    stars = []
    for i in range(16):
        deg = float(rng.uniform(0, 360))
        r = float(rng.uniform(0.318, 0.352))
        stars.append(polar(c, r, deg))
        cv.circle(stars[-1], float(rng.uniform(0.0035, 0.0065)), 240)
    stars.sort(key=lambda p: math.atan2(p[1] - 0.5, p[0] - 0.5))
    for i in range(0, 15, 3):      # 相邻的几颗连成小星座
        cv.line([stars[i], stars[i + 1]], 0.0014, 120)
        cv.line([stars[i + 1], stars[i + 2]], 0.0014, 120)
    cv.save("meta_ring")


# ---------------- 回纹角花 / 分隔线 ----------------

def corner():
    cv = Canvas(160)
    w = 0.03
    # 两条边（L 形），里面一个方回纹
    cv.line([(1.0, 0.09), (0.09, 0.09), (0.09, 1.0)], w)
    cv.line([(0.24, 0.24), (0.6, 0.24), (0.6, 0.6), (0.24, 0.6), (0.24, 0.38), (0.46, 0.38), (0.46, 0.46)], w)
    # 两条边往外淡出
    a = np.ones((160, 160), dtype=np.float32)
    ramp = np.clip((np.arange(160, dtype=np.float32) - 96.0) / 64.0, 0.0, 1.0)
    fade = 1.0 - ramp
    a *= np.minimum(fade[None, :], 1.0)
    a *= np.minimum(fade[:, None], 1.0)
    cv.save("meta_corner", a)


def divider(name="meta_rule"):
    cv = Canvas(512, 24)
    cy = 0.5

    def dia(cx, s):
        sx = s
        sy = s * 512.0 / 24.0
        cv.poly([(cx, cy - sy), (cx + sx, cy), (cx, cy + sy), (cx - sx, cy)], 255)

    dia(0.5, 0.012)
    dia(0.468, 0.006)
    dia(0.532, 0.006)
    cv.rect(0.0, cy - 0.045, 0.445, cy + 0.045, 255)
    cv.rect(0.555, cy - 0.045, 1.0, cy + 0.045, 255)
    x = np.arange(512, dtype=np.float32) / 511.0
    fade = np.clip(np.minimum(x, 1.0 - x) / 0.42, 0.0, 1.0) ** 1.4
    cv.save(name, fade[None, :].repeat(24, axis=0))


# ---------------- 四个入口图标 ----------------

def icon_hero():
    cv = Canvas(192)
    # 束发侠客：肩 + 头 + 发髻 + 发簪
    cv.ellipse((0.5, 0.98), 0.4, 0.34)
    cv.rect(0.0, 0.9, 1.0, 1.0, 0)
    cv.circle((0.5, 0.46), 0.225, 0)          # 头和肩之间留一圈空
    cv.circle((0.5, 0.46), 0.175)
    cv.circle((0.5, 0.2), 0.105, 0)
    cv.circle((0.5, 0.2), 0.075)
    cv.line([(0.3, 0.215), (0.7, 0.175)], 0.035, 0)
    cv.line([(0.3, 0.215), (0.7, 0.175)], 0.02)
    # 衣领
    cv.line([(0.4, 0.69), (0.5, 0.82), (0.6, 0.69)], 0.028, 0)
    cv.save("meta_icon_hero")


def icon_prep():
    cv = Canvas(192)
    # 乾坤袋 + 斜背的剑
    a, b = (0.13, 0.9), (0.87, 0.1)
    cv.line([a, b], 0.05)
    # 护手：垂直于剑身的一小横
    gx, gy = 0.3, 0.716
    cv.line([(gx - 0.085, gy - 0.08), (gx + 0.085, gy + 0.08)], 0.045)
    cv.circle(a, 0.045)
    cv.ellipse((0.52, 0.64), 0.31, 0.29, 0)      # 袋子压住剑：先挖一圈空
    cv.ellipse((0.52, 0.64), 0.265, 0.245)
    cv.rect(0.4, 0.3, 0.64, 0.46, 0)
    cv.poly([(0.44, 0.44), (0.6, 0.44), (0.66, 0.3), (0.38, 0.3)])      # 束口上面散开的袋口
    cv.line([(0.4, 0.43), (0.64, 0.43)], 0.035, 0)                      # 束口的绳
    cv.line([(0.42, 0.43), (0.62, 0.43)], 0.018)
    cv.circle((0.52, 0.66), 0.075, 0)                                   # 袋子上一枚圆扣
    cv.circle((0.52, 0.66), 0.04)
    cv.save("meta_icon_prep")


def icon_shop():
    cv = Canvas(192)

    def coin(c, r):
        cv.circle(c, r + 0.04, 0)
        cv.circle(c, r)
        cv.ring(c, r * 0.8, 0.02, 0)
        s = r * 0.3
        cv.rect(c[0] - s, c[1] - s, c[0] + s, c[1] + s, 0)

    coin((0.68, 0.33), 0.21)
    coin((0.42, 0.6), 0.31)
    cv.save("meta_icon_shop")


def icon_rank():
    cv = Canvas(192)
    # 日 + 山：主峰、侧峰，峰顶一道雪线
    cv.circle((0.66, 0.27), 0.14)
    m = [(0.06, 0.86), (0.4, 0.26), (0.56, 0.56), (0.7, 0.4), (0.94, 0.86)]
    cv.line(m, 0.07, 0, closed=True)
    cv.poly(m, 0)
    cv.poly(m)
    cv.line([(0.31, 0.46), (0.38, 0.52), (0.44, 0.44), (0.5, 0.52)], 0.026, 0)
    cv.line([(0.06, 0.94), (0.94, 0.94)], 0.035)
    cv.save("meta_icon_rank")


def icon_back():
    cv = Canvas(96)
    cv.line([(0.6, 0.2), (0.32, 0.5), (0.6, 0.8)], 0.1)
    cv.save("meta_icon_back")


# ---------------- 生图原图 → 素材 ----------------

def ink_alpha(name):
    """白底黑墨 → 透明度（0~1）：越黑越实，淡墨留一点"""
    a = np.asarray(Image.open(RAW / f"{name}.png").convert("RGB")).astype(np.float32) / 255.0
    lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    return np.clip((0.95 - lum) / 0.8, 0.0, 1.0) ** 0.85


def save_alpha(al, name):
    rgba = np.zeros(al.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(al * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(OUT / f"{name}.png")
    print("wrote", name, al.shape[::-1])


def bbox(al, thr=0.1):
    ys, xs = np.where(al > thr)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def cut(al, col, row, cols, rows, name, size=256, pad=0.06, anchor="center", keep_aspect=False):
    """从格子图里裁一格：取这一格里墨迹的外框，补成方的（anchor = corner 时贴左上角），缩到 size"""
    h, w = al.shape
    cw, ch = w // cols, h // rows
    cell = al[row * ch:(row + 1) * ch, col * cw:(col + 1) * cw]
    x0, y0, x1, y1 = bbox(cell)
    part = cell[y0:y1, x0:x1]
    ph, pw = part.shape
    if keep_aspect:
        m = int(round(ph * 0.25))
        canvas = np.zeros((ph + m * 2, pw + m * 2), dtype=np.float32)
        canvas[m:m + ph, m:m + pw] = part
        out_w = size
        out_h = max(8, int(round(size * canvas.shape[0] / canvas.shape[1])))
        im = Image.fromarray((canvas * 255).astype(np.uint8), "L").resize((out_w, out_h), Image.LANCZOS)
    else:
        side = max(ph, pw)
        m = int(round(side * pad))
        canvas = np.zeros((side + m * 2, side + m * 2), dtype=np.float32)
        if anchor == "corner":
            canvas[m:m + ph, m:m + pw] = part
        else:
            oy = m + (side - ph) // 2
            ox = m + (side - pw) // 2
            canvas[oy:oy + ph, ox:ox + pw] = part
        im = Image.fromarray((canvas * 255).astype(np.uint8), "L").resize((size, size), Image.LANCZOS)
    save_alpha(np.asarray(im).astype(np.float32) / 255.0, name)


def from_raw():
    dock = ink_alpha("dock")
    for i, n in enumerate(["hero", "prep", "shop", "rank"]):
        cut(dock, i % 2, i // 2, 2, 2, "meta_icon_" + n, 256)
    slots = ink_alpha("slots")
    for i, n in enumerate(["weapon", "armor0", "armor1", "armor2", "armor3", "chip"]):
        cut(slots, i % 3, i // 3, 3, 2, "meta_slot_" + n, 192)
    crests = ink_alpha("crests")
    for i in range(6):
        cut(crests, i % 3, i // 3, 3, 2, "meta_crest_%d" % i, 256, 0.04)
    orn = ink_alpha("ornaments")
    cut(orn, 0, 0, 2, 2, "meta_corner", 192, 0.02, "corner")
    cut(orn, 1, 0, 2, 2, "meta_cloud", 256, 0.04)
    cut(orn, 0, 1, 2, 2, "meta_divider", 512, keep_aspect=True)
    ring_al = ink_alpha("ring")
    x0, y0, x1, y1 = bbox(ring_al)
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    half = side // 2 + 6
    part = ring_al[max(cy - half, 0):cy + half, max(cx - half, 0):cx + half]
    im = Image.fromarray((part * 255).astype(np.uint8), "L").resize((768, 768), Image.LANCZOS)
    save_alpha(np.asarray(im).astype(np.float32) / 255.0, "meta_ring")


if __name__ == "__main__":
    have_raw = all((RAW / f"{n}.png").exists() for n in PROMPTS)
    divider("meta_rule")
    icon_back()
    if have_raw and "--vector" not in sys.argv:
        from_raw()
    else:
        ring()
        corner()
        divider("meta_divider")
        icon_hero()
        icon_prep()
        icon_shop()
        icon_rank()
