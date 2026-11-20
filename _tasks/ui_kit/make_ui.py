"""把生图服务出的原图（raw/）加工成界面素材（assets/ui/）。重跑：python -I _tasks/ui_kit/make_ui.py

原图（都是 gpt-image-2 出的，白底）：
  paper     宣纸底纹              → paper.png      384 见方、四方连续，面板 / 按钮 / 格子共用这一张（ui_paper_box.gd 平铺）
  mountain  淡墨远山              → mountain.png   白 + 透明度，大面板底边的点缀
  enso      一笔圆                → enso.png       白 + 透明度（把笔画沿半径压细了），触屏按钮 / 摇杆 / 小地图的圈
  stroke    枯笔横划              → stroke.png     白 + 透明度，标题下的一笔、分隔线
  cloud     祥云线描              → cloud.png      白 + 透明度，标题两侧 / 面板一角
  seal      朱砂印（空白）        → seal.png       白 + 透明度，上面的字游戏里用字体写
  mulan     木兰草原淡彩          → level_mulan.png 择境卡片上的画
  icon_*    丹药 / 飞剑 / 灵材 / 储物袋 → icon_*.png 抠掉白底
  icon_pill_heal / icon_pill_0..4   回春丹 + 五个品阶的修为丹（瓶子一族：陶葫芦 → 青玉瓶 → 青花瓶 → 紫晶瓶 → 金玉葫芦）
  icon_key_1..7                     七种破境丹（盒子一族，颜色跟着要去的境界走）
      只加工丹药这十三张：python -I _tasks/ui_kit/make_ui.py pills（提示词记在 PILL_ICONS 上面）
另外几张细墨线框（九宫格，白 + 透明度，游戏里染成墨色 / 朱砂色）和一张柔和的投影是这里直接画的。
「白 + 透明度」的图在游戏里用 modulate 上色，所以同一张图能当墨色也能当朱砂色。
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE.parent.parent / "assets" / "ui"
OUT.mkdir(parents=True, exist_ok=True)

S = 2    # 线框贴图：每个界面单位（1600×900 下的 1 像素）画几个像素
SS = 4   # 画线时的超采样


def load(name):
    return np.asarray(Image.open(RAW / f"{name}.png").convert("RGB")).astype(np.float32)


def lum(a):
    return a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)


def ink_alpha(a, white=248.0, black=28.0):
    """白底黑墨 → 墨的浓度（0..1）"""
    return np.clip((white - lum(a)) / (white - black), 0.0, 1.0)


def bbox(alpha, thr=0.04, pad=6):
    ys, xs = np.where(alpha > thr)
    h, w = alpha.shape
    return max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad + 1, w), min(ys.max() + pad + 1, h)


def save_white(alpha, name, size=None):
    """存成 白色 + 透明度"""
    al = Image.fromarray((np.clip(alpha, 0, 1) * 255.0 + 0.5).astype(np.uint8), "L")
    if size is not None:
        al = al.resize(size, Image.LANCZOS)
    im = Image.merge("RGBA", [Image.new("L", al.size, 255)] * 3 + [al])
    im.save(OUT / f"{name}.png", optimize=True)
    return im


def gblur(a, sigma):
    """高斯模糊（二维浮点数组；这版 PIL 的滤镜不收浮点图，自己做可分离卷积）"""
    r = max(int(sigma * 3.0 + 0.5), 1)
    k = np.exp(-0.5 * (np.arange(-r, r + 1, dtype=np.float32) / sigma) ** 2)
    k /= k.sum()
    out = a.astype(np.float32)
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r, r)
        p = np.pad(out, pad, mode="reflect")
        acc = np.zeros_like(out)
        n = out.shape[axis]
        for i in range(2 * r + 1):
            acc += k[i] * (p[i:i + n, :] if axis == 0 else p[:, i:i + n])
        out = acc
    return out


def blur(arr, radius):
    return np.dstack([gblur(arr[:, :, c], radius) for c in range(arr.shape[2])])


# ---------- 宣纸底纹：压平大块的明暗、做成四方连续 ----------

def make_paper():
    n = 384
    src = np.asarray(Image.open(RAW / "paper.png").convert("RGB").resize((512, 512), Image.LANCZOS)).astype(np.float32)
    low = blur(src, 22.0)
    hi = (src - low)[64:64 + n, 64:64 + n]
    lo = (low - src.mean(axis=(0, 1)))[64:64 + n, 64:64 + n]

    def seam(x, axis, keep_var):
        # 和自己错开半张的那份按余弦窗混合：边上用的是错开的那份（它在边界处是连续的），它自己的接缝落在正中、被窗压掉
        i = np.arange(n, dtype=np.float32)
        w = 0.5 - 0.5 * np.cos(2.0 * math.pi * (i + 0.5) / n)
        w = w.reshape((n, 1, 1)) if axis == 0 else w.reshape((1, n, 1))
        y = w * x + (1.0 - w) * np.roll(x, n // 2, axis=axis)
        if keep_var:   # 两份不相关的纹理相加会变淡，把反差补回来
            y = y / np.sqrt(w * w + (1.0 - w) * (1.0 - w))
        return y

    hi = seam(seam(hi, 0, True), 1, True)
    lo = seam(seam(lo, 0, False), 1, False)
    base = np.array([244.0, 238.0, 223.0], dtype=np.float32)   # 比原图略白、略去一点黄：干净
    out = base + hi * 1.25 + lo * 0.35
    Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB").save(OUT / "paper.png", optimize=True)
    return out


# ---------- 墨迹类：白底 → 透明度 ----------

def make_mountain():
    a = load("mountain")
    al = np.clip((249.0 - lum(a)) / 150.0, 0.0, 1.0)
    x0, y0, x1, y1 = bbox(al, 0.03, 10)
    al = al[y0:y1, :]
    h, w = al.shape
    # 上下左右都淡出去，放在面板底边不会有硬边
    fy = np.clip(np.arange(h) / 40.0, 0, 1) * np.clip((h - 1 - np.arange(h)) / 30.0, 0, 1)
    fx = np.clip(np.arange(w) / 90.0, 0, 1) * np.clip((w - 1 - np.arange(w)) / 90.0, 0, 1)
    al = al * fy[:, None] * fx[None, :]
    return save_white(al, "mountain", (1024, round(1024 * h / w)))


def make_stroke():
    al = ink_alpha(load("stroke"))
    x0, y0, x1, y1 = bbox(al, 0.06, 4)
    al = al[y0:y1, x0:x1]
    h, w = al.shape
    return save_white(al, "stroke", (768, round(768 * h / w)))


def make_cloud():
    al = ink_alpha(load("cloud"))
    x0, y0, x1, y1 = bbox(al, 0.06, 6)
    al = al[y0:y1, x0:x1]
    h, w = al.shape
    return save_white(np.clip(al * 1.15, 0, 1), "cloud", (320, round(320 * h / w)))


def make_seal():
    a = load("seal")
    al = np.clip((246.0 - np.minimum(a[:, :, 1], a[:, :, 2])) / 200.0, 0.0, 1.0)
    x0, y0, x1, y1 = bbox(al, 0.1, 6)
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    al = al[cy - side // 2:cy + side // 2, cx - side // 2:cx + side // 2]
    return save_white(al, "seal", (128, 128))


def sample(img, x, y):
    """双线性取样（出界取 0）"""
    h, w = img.shape
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    fx = x - x0
    fy = y - y0
    ok = (x0 >= 0) & (y0 >= 0) & (x0 < w - 1) & (y0 < h - 1)
    x0 = np.clip(x0, 0, w - 2)
    y0 = np.clip(y0, 0, h - 2)
    v = (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
         + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)
    return np.where(ok, v, 0.0)


def make_enso(thin=0.42, fit=0.84):
    """一笔圆：原图笔画有直径的七分之一那么粗，按钮上太重。沿半径方向把笔画压细（飞白是顺着笔势的，压细后还在）。"""
    al = ink_alpha(load("enso"))
    h, w = al.shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    m = al.sum()
    cx, cy = (al * xs).sum() / m, (al * ys).sum() / m
    r0 = (al * np.hypot(xs - cx, ys - cy)).sum() / m
    n = 512
    v, u = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = u - (n - 1) / 2.0, v - (n - 1) / 2.0
    rho = np.hypot(dx, dy) + 1e-6
    k = (n / 2.0 * fit) / r0                       # 圆的平均半径画到贴图半宽的 fit 处
    rs = r0 + (rho / k - r0) / thin
    out = np.where(rs > 0.0, sample(al, cx + dx / rho * rs, cy + dy / rho * rs), 0.0)   # rs < 0 是穿过圆心取到对面去了
    return save_white(out, "enso", (256, 256))


# ---------- 图标：从四角漫水填充去掉白底（瓷瓶上的留白不会被抠掉） ----------

# 丹药图标（2026-11-20 用户要求每种丹药一张独立的图）：十三张都是 gpt-image-2 出的原图（1024 见方、白底）
# 提示词 = 开头 + 各自的描述 + 结尾：
#   开头：Single game item icon, traditional Chinese gongbi painting with soft watercolor wash, fine ink outlines and delicate
#         shading, xianxia fantasy alchemy medicine item.（破境丹把 medicine item 换成 breakthrough elixir）
#   结尾：One compact object centered, filling about 70 percent of the canvas, seen from a slight three-quarter top angle. No glow or
#         halo around it. Pure white background, nothing else, no text, no seal, no calligraphy, no border, no ground shadow.
#   描述：普通丹药 =「什么瓶子 + 旁边三颗什么颜色的丹」
#           回春丹 红布封口的白瓷圆罐 + 青绿丹 + 一枝嫩叶 · 黄龙丹 画黄龙的粗陶葫芦 + 土黄丹 · 聚灵丹 云纹青玉细瓶 + 碧绿丹
#           养元丹 青花海浪纹长颈瓶 + 宝蓝丹 · 凝魂丹 六棱紫晶银盖瓶 + 紫丹带两缕魂焰 · 培婴丹 金龙盘绕的白玉葫芦 + 金丹
#         破境丹 =「什么盒子（开着盖）+ 里面一颗什么样的大丹」
#           筑基丹 素木盒绿绸 + 翠绿云纹丹 · 降尘丹 青花瓷圆盒 + 天蓝星点丹 · 定灵丹 紫漆银角盒 + 紫色灵纹丹
#           化神丹 红漆描金盒 + 橙金火纹丹带两朵小火苗 · 炼虚丹 墨玉八角盒青线 + 淡青漩涡丹
#           合体丹 朱红圆盒金龙扣 + 半红半金的太极丹 · 大乘丹 金莲花盒 + 缠三道金环的珠白丹
PILL_ICONS = ["icon_pill_heal"] + [f"icon_pill_{i}" for i in range(5)] + [f"icon_key_{i}" for i in range(1, 8)]


def make_pill_icons():
    out = {}
    for n in PILL_ICONS:
        if (RAW / f"{n}.png").exists():
            out[n] = make_icon(n)
        else:
            print(f"{n}: 缺原图，跳过")
    return out


def make_icon(name, size=128):
    im = Image.open(RAW / f"{name}.png").convert("RGB")
    a = np.asarray(im).astype(np.float32)
    white = Image.fromarray(((a.min(axis=2) > 236.0) * 255).astype(np.uint8), "L").copy()   # copy：fromarray 出来的图是只读的，漫水填充写不进去
    w, h = white.size
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if white.getpixel(xy) == 255:
            ImageDraw.floodfill(white, xy, 128)
    al = (np.asarray(white) != 128).astype(np.float32)
    al = gblur(al, 1.6)
    al = np.clip((al - 0.35) / 0.5, 0.0, 1.0)      # 往里收一点，去白边
    x0, y0, x1, y1 = bbox(al, 0.05, 10)
    side = max(x1 - x0, y1 - y0)
    canvas = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    rgba = np.dstack([a, al * 255.0]).astype(np.uint8)
    piece = Image.fromarray(rgba, "RGBA").crop((x0, y0, x1, y1))
    canvas.paste(piece, ((side - piece.width) // 2, (side - piece.height) // 2))
    canvas = canvas.resize((size, size), Image.LANCZOS)
    canvas.save(OUT / f"{name}.png", optimize=True)
    return canvas


def make_level():
    im = Image.open(RAW / "mulan.png").convert("RGB")
    # 取中间一条：落日、远山、亭子、河
    im = im.crop((0, 250, 1536, 250 + 684)).resize((808, 360), Image.LANCZOS)
    im.save(OUT / "level_mulan.png", optimize=True)
    return im


# ---------- 细墨线框（九宫格）和投影：直接画 ----------

def _canvas(w, h):
    k = S * SS
    return Image.new("L", (round(w * k), round(h * k)), 0), k


def _line(layer, pts, width, alpha, k, closed=False):
    d = ImageDraw.Draw(layer)
    p = [(x * k, y * k) for x, y in pts]
    if closed:
        p = p + [p[0], p[1]]
    d.line(p, fill=round(alpha * 255), width=max(round(width * k), 1), joint="curve")


def _merge(layers, w, h, name):
    acc = np.zeros((layers[0].size[1], layers[0].size[0]), dtype=np.float32)
    for l in layers:
        acc = np.maximum(acc, np.asarray(l).astype(np.float32) / 255.0)
    return save_white(acc, name, (round(w * S), round(h * S)))


def _notched(w, h, i, n):
    """四角内收一个小方角（委角）的框"""
    return [(i + n, i), (w - i - n, i), (w - i - n, i + n), (w - i, i + n), (w - i, h - i - n), (w - i - n, h - i - n),
            (w - i - n, h - i), (i + n, h - i), (i + n, h - i - n), (i, h - i - n), (i, i + n), (i + n, i + n)]


def frame_panel():
    """大面板：委角双线框，角上一个小墨点。边距 32"""
    w = h = 80
    a, k = _canvas(w, h)
    b, _ = _canvas(w, h)
    c, _ = _canvas(w, h)
    _line(a, _notched(w, h, 9.0, 9.0), 1.5, 0.92, k, True)
    _line(b, _notched(w, h, 13.0, 9.0), 0.7, 0.42, k, True)
    d = ImageDraw.Draw(c)
    for sx in (0, 1):
        for sy in (0, 1):
            cx = 13.5 if sx == 0 else w - 13.5
            cy = 13.5 if sy == 0 else h - 13.5
            d.rectangle([(cx - 1.5) * k, (cy - 1.5) * k, (cx + 1.5) * k, (cy + 1.5) * k], fill=round(0.85 * 255))
    return _merge([a, b, c], w, h, "frame_panel")


def frame_line():
    """按钮 / 小纸条：一圈细线。边距 10"""
    w = h = 28
    a, k = _canvas(w, h)
    _line(a, [(3, 3), (w - 3, 3), (w - 3, h - 3), (3, h - 3)], 1.2, 0.85, k, True)
    return _merge([a], w, h, "frame_line")


def frame_slot():
    """背包格：一圈淡线，四角各一个小折角。边距 16"""
    w = h = 40
    a, k = _canvas(w, h)
    b, _ = _canvas(w, h)
    i = 2.5
    _line(a, [(i, i), (w - i, i), (w - i, h - i), (i, h - i)], 0.9, 0.4, k, True)
    q = 9.0
    for sx in (0, 1):
        for sy in (0, 1):
            x = i if sx == 0 else w - i
            y = i if sy == 0 else h - i
            dx = q if sx == 0 else -q
            dy = q if sy == 0 else -q
            _line(b, [(x + dx, y), (x, y), (x, y + dy)], 1.7, 0.95, k)
    return _merge([a, b], w, h, "frame_slot")


def frame_bar():
    """血条 / 读条的框：细线一圈，两头各一根略高的轴头。左右边距 8，上下 4"""
    w, h = 24, 12
    a, k = _canvas(w, h)
    b, _ = _canvas(w, h)
    _line(a, [(1.6, 1.8), (w - 1.6, 1.8), (w - 1.6, h - 1.8), (1.6, h - 1.8)], 1.2, 0.95, k, True)
    for x in (1.6, w - 1.6):
        _line(b, [(x, 0.0), (x, h)], 2.2, 1.0, k)
    return _merge([a, b], w, h, "frame_bar")


def make_shadow():
    """纸片下面的投影：只画纸外面那一圈（九宫格不画中心），下边比上边重。边距 24"""
    m, c = 24, 16
    n = m * 2 + c
    im = Image.new("L", (n, n), 0)
    ImageDraw.Draw(im).rectangle([m - 2, m + 3, n - m + 1, n - m + 6], fill=255)
    im = im.filter(ImageFilter.GaussianBlur(7.0))
    al = np.asarray(im).astype(np.float32) / 255.0
    rgba = np.dstack([np.zeros((n, n, 3), dtype=np.float32), al * 255.0]).astype(np.uint8)
    out = Image.fromarray(rgba, "RGBA")
    out.save(OUT / "shadow.png", optimize=True)
    return out


def main():
    made = {
        "paper": make_paper(), "mountain": make_mountain(), "stroke": make_stroke(), "cloud": make_cloud(),
        "seal": make_seal(), "enso": make_enso(), "level_mulan": make_level(),
        "frame_panel": frame_panel(), "frame_line": frame_line(), "frame_slot": frame_slot(), "frame_bar": frame_bar(),
        "shadow": make_shadow(),
    }
    for n in ["icon_pill", "icon_gear", "icon_mat", "icon_pouch"]:
        made[n] = make_icon(n)
    # 2026-11-20 搜打撤改造加的：灵草 / 破境丹 / 符箓 / 储物戒 / 灵石 / 守·识·养 三类法宝
    for n in ["icon_herb", "icon_key", "icon_tool", "icon_ring", "icon_lingshi", "icon_guard", "icon_seek", "icon_vital"]:
        if (RAW / f"{n}.png").exists():
            made[n] = make_icon(n)
    made.update(make_pill_icons())
    total = 0
    for p in sorted(OUT.glob("*.png")):
        im = Image.open(p)
        total += p.stat().st_size
        print(f"{p.name:18s} {im.size[0]:5d}x{im.size[1]:<5d} {im.mode:5s} {p.stat().st_size / 1024:7.1f} KB")
    print(f"total {total / 1024:.0f} KB")


if __name__ == "__main__":
    import sys
    if "pills" in sys.argv[1:]:
        for n, im in make_pill_icons().items():
            print(f"{n:18s} {im.size[0]}x{im.size[1]} {(OUT / (n + '.png')).stat().st_size / 1024:6.1f} KB")
    else:
        main()
