"""境界光环贴图：从用户给的八张效果图（_tasks/realm_halo/ref/tier1~8.webp，1672×941，每个境界一张）里把光环抠出来。

效果图是「主角背对镜头悬在半空，光环衬在他身后」。游戏里光环也是一张始终衬在角色身后的图（scripts/realm_halo.gd），
所以要的是：去掉天空、去掉人物、把被人物挡住的那块补上，剩下的光环连同它的柔光存成一张带透明度的图。

做法（都是对原图像素的运算，不重画）：
  1. 估背景：把光环 + 人物那一片挖掉，用周围的天空往里填（由粗到细的加权平均）；再把洞里明显还是天空的像素加回去重估两遍，
     这样环里露出来的天空 / 云也能对上。
  2. 透明度：和背景差得多的、有清晰线条的算「实的」（a → 1），只是比背景亮一点的算「光」（a → 0）。
     存的是预乘颜色 P = C − (1 − a)·B：盖回原来那片天上就是原图；换到别的背景上，实的部分还是原画的颜色，光的部分是往上加的亮。
  3. 人物：按身高比例的模板（头、羽饰、身子、腿）加各张图自己补的几块，挖掉以后沿圆周方向用两侧同半径的像素补（环被腿挡住的那段就接上了）；
     花心这种中心对称的图案先用转 180° 的对面那块补。
  4. 裁成以光环为中心的方图，四周渐隐，放大存 PNG（RGB 是预乘色，A 是遮挡度；纯发光的像素 A 给 1/255，免得压缩时颜色被丢掉）。
同时打印每档在游戏里要用的尺寸：方图边长、中心离脚底多高（按人物身高 = 1.74 米折算）。

用法：python _tasks/realm_halo/make_halo.py [档位…]     不带参数 = 八档全做
输出：assets/halo/halo_<n>.png；核对图在 _tasks/realm_halo/work/（chk_<n>_*.jpg：人物遮罩 / 背景 / 盖回原图 / 换三种底色）
"""
import json
import math
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REF = os.path.join(HERE, "ref")
WORK = os.path.join(HERE, "work")
OUT = os.path.join(ROOT, "assets", "halo")
HERO_H = 1.74          # 游戏里主角脚底到头顶（米）

# 每档：crop = 光环方图的中心 x / y、半边长（原图像素）；char = 人物中线 x、头顶 y、鞋底 y；
#       ring = 补人物时用的圆心（不写 = 方图中心）；sym = (几重旋转对称, 半径)：这个半径以内先用转过去的那块补；
#       polar = [(内半径, 外半径)…]：这些环带里沿圆周用两侧接上（环身被腿 / 头挡住的那一段）；其余被挡的地方平滑填，
#       under = 人物身后怎么办："clear"（默认）挖空、边上渐隐；"glow" 填一团柔光；"fill" 用四周的画面平滑地填；fill = 被线条围住的地方填多实（半透明花瓣给 0.85）；
#       sky_tol = 洞里认天空的颜色容差（0 = 不认：里面是半透明花瓣 / 光的那几档）；nosky = [(cx, cy, r)…] 这些圆里不认天空
#       hole = 估背景时挖掉的椭圆半轴相对半边长的比例（x, y）；extra = 人物遮罩另补的椭圆 [cx, cy, rx, ry]（原图像素）
#       solid = 强制算实的椭圆 [cx, cy, rx, ry, 透明度下限]（化神的星空门里面）
#       out = 输出边长
TIERS = {
    1: dict(name="炼气", crop=(836, 432, 150), char=(836, 384, 603), ring=(836, 436), polar=[(83, 98)], under="clear", light_lines=True, hole=(0.9, 0.9), out=512),
    2: dict(name="筑基", crop=(824, 452, 195), char=(824, 413, 622), ring=(824, 460), sym=(8, 124), polar=[(124, 152)], fill_light=True, hole=(0.93, 0.93), out=512),
    3: dict(name="结丹", crop=(836, 380, 250), char=(833, 379, 643), ring=(833, 403), polar=[(116, 148)], under="clear", fill=0.85, nosky=[(836, 352, 222)], hole=(0.92, 0.92), out=640),
    4: dict(name="元婴", crop=(838, 320, 285), char=(841, 356, 638), ring=(840, 277), polar=[(160, 202)], nosky=[(840, 277, 198)], hole=(0.92, 0.92), out=768),
    5: dict(name="化神", crop=(832, 378, 262), char=(837, 405, 620), ring=(833, 393), polar=[(148, 188)], under="fill", hole=(0.92, 0.9),
            solid=[[833, 385, 150, 122, 0.94]], out=768),
    6: dict(name="炼虚", crop=(832, 396, 285), char=(833, 384, 614), ring=(833, 404), polar=[(164, 198)], under="glow", hole=(0.92, 0.92), out=768),
    7: dict(name="合体", crop=(834, 392, 310), char=(836, 356, 544), ring=(836, 370), floor=684, hole=(0.93, 0.93), out=768),
    8: dict(name="大乘", crop=(840, 400, 332), char=(839, 396, 618), ring=(839, 394), under="glow", fill=0.85, nosky=[(839, 394, 255)], hole=(0.93, 0.93), out=768),
}

# 人物模板：单位 = 身高，原点 = (中线, 头顶)。椭圆 [cx, cy, rx, ry]、多边形 [[x, y], …]
T_ELLIPSES = [
    [0.035, 0.245, 0.30, 0.265],      # 头（连两侧的发梢）
    [-0.14, 0.02, 0.05, 0.04],        # 头顶翘起来的那撮
    [0.255, 0.075, 0.075, 0.14],      # 抹额上的羽饰
    [0.0, 0.93, 0.15, 0.085],         # 鞋
]
T_POLYS = [
    # 肩 → 两臂 → 腰带飘带 → 裤脚
    [[-0.19, 0.50], [0.20, 0.50], [0.25, 0.60], [0.25, 0.80], [0.20, 0.82], [0.20, 0.93], [-0.17, 0.93],
     [-0.28, 0.92], [-0.28, 0.76], [-0.25, 0.60]],
]


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def load(t):
    path = os.path.join(REF, "tier%d.webp" % t)
    im = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
    return im[:, :, ::-1].astype(np.float32) / 255.0


def save_jpg(name, rgb):
    arr = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)[:, :, ::-1]
    cv2.imencode(".jpg", arr, [cv2.IMWRITE_JPEG_QUALITY, 90])[1].tofile(os.path.join(WORK, name))


def char_mask(cfg, shape):
    cx, top, sole = cfg["char"]
    h = float(sole - top)
    m = np.zeros(shape[:2], np.uint8)
    for e in T_ELLIPSES:
        cv2.ellipse(m, (int(round(cx + e[0] * h)), int(round(top + e[1] * h))), (int(round(e[2] * h)), int(round(e[3] * h))), 0, 0, 360, 255, -1)
    for poly in T_POLYS:
        pts = np.array([[cx + p[0] * h, top + p[1] * h] for p in poly], np.int32)
        cv2.fillPoly(m, [pts], 255)
    for e in cfg.get("extra", []):
        cv2.ellipse(m, (int(e[0]), int(e[1])), (int(e[2]), int(e[3])), 0, 0, 360, 255, -1)
    m = cv2.dilate(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
    return m > 0


def pushpull(img, known):
    """known（0~1）是可信度；不可信的地方用周围可信像素由粗到细填上"""
    levels = []
    a = img * known[..., None]
    w = known.astype(np.float32)
    while min(a.shape[:2]) > 6:
        levels.append((a, w))
        size = (max(a.shape[1] // 2, 1), max(a.shape[0] // 2, 1))
        a = cv2.resize(a, size, interpolation=cv2.INTER_AREA)
        w = cv2.resize(w, size, interpolation=cv2.INTER_AREA)
    cur = a / np.maximum(w[..., None], 1e-6)
    for a_l, w_l in reversed(levels):
        up = cv2.resize(cur, (a_l.shape[1], a_l.shape[0]), interpolation=cv2.INTER_CUBIC)
        up = cv2.GaussianBlur(up, (0, 0), 1.2)
        t = np.clip(w_l, 0.0, 1.0)[..., None]
        cur = a_l / np.maximum(w_l[..., None], 1e-6) * t + up * (1.0 - t)
    return cur


def gradient(C):
    g = np.zeros(C.shape[:2], np.float32)
    for c in range(3):
        gx = cv2.Scharr(C[:, :, c], cv2.CV_32F, 1, 0) / 16.0
        gy = cv2.Scharr(C[:, :, c], cv2.CV_32F, 0, 1) / 16.0
        g = np.maximum(g, np.sqrt(gx * gx + gy * gy))
    return g


def polar_fill(P4, mask, center, rmax):
    """mask 里的像素：沿圆周方向用两侧同半径的已知像素线性补"""
    n_ang = int(2 * math.pi * rmax)
    n_rad = int(rmax)
    flags = cv2.WARP_POLAR_LINEAR | cv2.INTER_LINEAR
    pol = cv2.warpPolar(P4, (n_rad, n_ang), center, rmax, flags)
    pm = cv2.warpPolar(mask.astype(np.float32), (n_rad, n_ang), center, rmax, flags) > 0.02
    ang = np.arange(n_ang, dtype=np.float32)
    for j in range(n_rad):
        bad = pm[:, j]
        if not bad.any():
            continue
        good = ~bad
        if good.sum() < 8:
            pol[:, j, :] = 0.0
            continue
        for c in range(4):
            pol[bad, j, c] = np.interp(ang[bad], ang[good], pol[good, j, c], period=n_ang)
    back = cv2.warpPolar(pol, (P4.shape[1], P4.shape[0]), center, rmax, flags | cv2.WARP_INVERSE_MAP)
    return back


def process(t):
    cfg = TIERS[t]
    C = load(t)
    H, W = C.shape[:2]
    cx, cy, R = cfg["crop"]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cm = char_mask(cfg, C.shape)

    # ---- 1 背景 ----
    hx, hy = cfg["hole"]
    hole = ((xx - cx) / (R * hx)) ** 2 + ((yy - cy) / (R * hy)) ** 2 < 1.0
    hole |= cv2.dilate(cm.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    known = (~hole).astype(np.float32)
    B = pushpull(C, known)
    g = gradient(C)
    gb = cv2.GaussianBlur(g, (0, 0), 1.5)
    # 天空颜色模型：洞外面那一圈天空（方图范围内、平台以上）的颜色聚成若干类；洞里「颜色像天空、又平滑、离线条远」的像素也算天空
    near = (~hole) & (np.abs(xx - cx) < R * 2.0) & (np.abs(yy - cy) < R * 1.8) & (yy < cfg.get("floor", 650)) & (gb < 0.02)
    samples = C[near].reshape(-1, 3)
    if len(samples) > 60000:
        samples = samples[np.random.RandomState(1).choice(len(samples), 60000, replace=False)]
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 1e-4)
    _c, _l, centers = cv2.kmeans(samples.astype(np.float32), 48, None, crit, 2, cv2.KMEANS_PP_CENTERS)
    dn = np.full(C.shape[:2], 9.0, np.float32)
    for c in centers:
        dn = np.minimum(dn, np.sqrt(((C - c) ** 2).sum(-1) / 3.0))
    # 洞里「颜色和外面某处天空一样、平滑、离线条远」的地方当作看得见的天空，按把握大小给权重（软的，不一刀切），重估背景
    tol = float(cfg.get("sky_tol", 0.035))
    strong = ((gb > 0.035) & (~cv2.dilate(cm.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool))).astype(np.uint8)      # 人物自己的轮廓不算
    kc0 = int(cfg.get("close", 13))
    # 两道线夹着的窄条（玉环的环身）颜色可能很像天空，不能算天空：先把线条闭合起来再量距离
    strong = cv2.morphologyEx(strong, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kc0, kc0)))
    dist = cv2.distanceTransform(1 - strong, cv2.DIST_L2, 3)
    if tol > 0.0:
        w_sky = (1.0 - smoothstep(tol * 0.35, tol, dn)) * (1.0 - smoothstep(0.02, 0.035, gb)) * smoothstep(4.0, 9.0, dist)
        w_sky = np.where(hole & (~cm), w_sky, 0.0).astype(np.float32)
        for nx, ny, nr in cfg.get("nosky", []):
            w_sky[(xx - nx) ** 2 + (yy - ny) ** 2 < nr * nr] = 0.0
    else:
        w_sky = np.zeros(C.shape[:2], np.float32)      # 这一档里面是半透明的花瓣 / 光，颜色和天空太像，不在洞里认天空
    B = np.clip(pushpull(C, np.maximum(known, w_sky)), 0.0, 1.0)
    if "--debug" in sys.argv:
        x0d, y0d = int(cx - R), int(cy - R)
        cut = lambda a: a[max(y0d, 0):y0d + 2 * R, max(x0d, 0):x0d + 2 * R]
        dbg = np.concatenate([np.repeat(np.clip(cut(dn) / 0.1, 0, 1)[..., None], 3, -1), np.repeat(np.clip(cut(gb) / 0.05, 0, 1)[..., None], 3, -1),
                              np.repeat(cut(w_sky)[..., None], 3, -1)], axis=1)
        save_jpg("dbg_%d_dn_gb_sky.jpg" % t, dbg)

    # ---- 2 透明度 + 预乘色 ----
    # 三种东西分开看：
    #   线条 / 花纹（梯度大）和颜色跟天空差得远的（金、深紫、红）→ 实的，a = 1，颜色就是原画的颜色；
    #   被它们围住的窄条（玉环的环身、龙身、翅羽）→ 也填实；
    #   其余平滑的地方是「光」：a 只取刚好够用的那一点（某个通道比背景暗多少就遮多少），剩下的都算往背景上加的亮。
    #   这样暖色的柔光盖到别的背景上是一层淡淡的暖色，而不是一块不透明的肉色。
    d = np.sqrt(((C - B) ** 2).sum(-1) / 3.0)
    gs = cv2.GaussianBlur(cv2.dilate(g, np.ones((3, 3), np.uint8)), (0, 0), 1.1)
    unlike = smoothstep(tol * 0.4, tol * 1.6, dn) if tol > 0.0 else np.ones(C.shape[:2], np.float32)
    for nx, ny, nr in cfg.get("nosky", []):
        unlike = np.where((xx - nx) ** 2 + (yy - ny) ** 2 < nr * nr, 1.0, unlike)
    # light_lines（只有炼气那档：整个光环都是白色细线）：「实的」只给比背景暗的像素，纯粹比背景亮的白线按下面
    # 「半透明的白」来存（a = 亮了多少）—— 不然线条边上「白和天空各一半」的像素会被当成实心的粉白色，换个背景就发灰。
    # 别的档不能这么干（试过）：金、玉、龙身上的高光也是「比背景亮」，一刀切下去花纹里实一块虚一块，全是麻点。
    a_dark = np.clip((B - C) / np.maximum(B, 1e-3), 0.0, 1.0).max(axis=-1)
    k_dark = smoothstep(0.03, 0.12, a_dark) if cfg.get("light_lines", False) else np.ones(C.shape[:2], np.float32)
    a_edge = smoothstep(0.035, 0.11, 0.55 * gs) * smoothstep(0.02, 0.06, d) * k_dark
    a_col = smoothstep(float(cfg.get("col0", 0.14)), float(cfg.get("col1", 0.26)), d) * k_dark
    a_solid = np.maximum(a_edge, a_col)
    core = (a_solid > 0.6).astype(np.uint8)
    kc = int(cfg.get("close", 13))
    closed = cv2.morphologyEx(core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kc, kc)))
    closed = cv2.GaussianBlur(closed.astype(np.float32), (0, 0), 0.8)
    # 围住的地方填实；填多实随「和背景差多少」缓缓变化（坡放得很宽：背景估不准时是深浅渐变，不会一块有一块没有）。
    # 试过改成按「颜色像不像天空」来定：金、玉、龙身上的高光颜色和亮云很像，结果花纹里全是没填上的麻点，不能用。
    k_fill = 1.0 if (cfg.get("fill_light", False) or not cfg.get("light_lines", False)) else k_dark
    a_solid = np.maximum(a_solid, closed * float(cfg.get("fill", 1.0)) * smoothstep(0.005, 0.07, d) * k_fill)
    # 和背景几乎一样的不要；颜色跟外面某处天空一样的也淡掉（背景估不准时留下的云影就是这种）
    live = smoothstep(0.012, 0.04, d) * unlike
    # 光的遮挡度取「刚好够」的值，两头都要够：某个通道比背景暗 → 至少遮这么多（颜色不能是负的）；
    # 某个通道比背景亮 → 也至少遮这么多（颜色不能比纯白还亮）。后一条等于把光看成一层半透明的白 / 金色：
    # 白光盖在粉色天上是「绿和蓝多了一点」，要是只把多出来的加到别的背景上会发青；按半透明的白来存，在哪儿都是白光。
    # 分母留了底（背景的红色通道本来就快到 1 了，不留底的话一点点噪声就会算出一大片白雾）
    a_light = np.clip((C - B) / np.maximum(1.0 - B, 0.3), 0.0, 1.0).max(axis=-1)
    # 「比背景暗」的那种遮挡只在颜色确实不像天空时才算（紫色的琉璃瓣、暖色的环内光）：
    # 原画里的暗云比估出来的背景暗，颜色却是天空的颜色，不能让它变成光环外面的一片灰影
    if tol > 0.0:
        far_sky = smoothstep(tol * 1.0, tol * 2.5, dn)
        for nx, ny, nr in cfg.get("nosky", []):
            far_sky = np.where((xx - nx) ** 2 + (yy - ny) ** 2 < nr * nr, 1.0, far_sky)
        a_dark = a_dark * far_sky
    a_min = np.maximum(a_dark, a_light) * live
    alpha = np.maximum(a_solid, a_min)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.85)          # 边缘磨一下（阈值是在有压缩噪声的图上卡的，不磨会有锯齿）
    forced = np.zeros(C.shape[:2], np.float32)
    for sdef in cfg.get("solid", []):
        inside = ((xx - sdef[0]) / sdef[2]) ** 2 + ((yy - sdef[1]) / sdef[3]) ** 2
        forced = np.maximum(forced, sdef[4] * smoothstep(1.0, 0.86, inside))
    alpha = np.maximum(alpha, forced)
    P = np.clip(C - (1.0 - alpha[..., None]) * B, 0.0, 1.0) * np.maximum(np.maximum(a_solid, live), smoothstep(0.0, 0.5, forced))[..., None]
    P4 = np.concatenate([P, alpha[..., None]], axis=-1).astype(np.float32)

    # ---- 3 人物挖掉、补上 ----
    rc = cfg.get("ring", (cx, cy))
    cm_left = cm.copy()
    sym = cfg.get("sym")
    if sym:
        # 花心这类旋转对称的图案：转 k/n 圈后的那块没被挡，就直接拿来（先试转得少的）
        n_fold, r_sym = sym
        rr = np.sqrt((xx - rc[0]) ** 2 + (yy - rc[1]) ** 2)
        order = sorted(range(1, n_fold), key=lambda k: min(k, n_fold - k))
        for k in order:
            ang = 2.0 * math.pi * k / n_fold
            ca, sa = math.cos(ang), math.sin(ang)
            px = np.clip((rc[0] + (xx - rc[0]) * ca - (yy - rc[1]) * sa).round().astype(np.int32), 0, W - 1)
            py = np.clip((rc[1] + (xx - rc[0]) * sa + (yy - rc[1]) * ca).round().astype(np.int32), 0, H - 1)
            can = cm_left & (~cm[py, px]) & (rr < r_sym)
            P4[can] = P4[py, px][can]
            cm_left &= ~can
    # 指定半径的环带（环身被腿 / 头挡住的那一段）：沿圆周用两侧接上
    rr = np.sqrt((xx - rc[0]) ** 2 + (yy - rc[1]) ** 2)
    bands = cfg.get("polar", [])
    if bands:
        rmax = float(R) * 1.5
        filled = polar_fill(P4, cm_left, (float(rc[0]), float(rc[1])), rmax)
        inband = np.zeros(C.shape[:2], bool)
        for r0, r1 in bands:
            inband |= (rr >= r0) & (rr <= r1)
        use = cm_left & inband
        P4 = np.where(use[..., None], cv2.GaussianBlur(filled, (0, 0), 0.8), P4)
        cm_left &= ~use
    if cm_left.any():
        if cfg.get("under", "clear") == "clear":
            # 这一档人物身后本来就是空的（只有原画里贴着人物的一圈柔光）：挖空，边上渐隐，不留人形的光影
            keep = 1.0 - cv2.GaussianBlur(cv2.dilate(cm_left.astype(np.uint8), np.ones((25, 25), np.uint8)).astype(np.float32), (0, 0), 8.0)
            keep = np.clip(keep, 0.0, 1.0)
            solid_part = smoothstep(0.5, 0.9, P4[..., 3])                  # 实心的花纹不受影响，只淡掉光
            w = np.where(cm_left, 0.0, np.maximum(keep, solid_part))
            P4 = P4 * w[..., None]
        else:
            # "glow"：身后是一团亮光（大乘的莲心、炼虚的光柱）→ 按四周最亮的那些像素平滑地填成一团柔光；
            # "fill"：身后是实心的画面（化神的星空）→ 四周直接平滑地填
            grow = cv2.dilate(cm_left.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
            lum = P4[..., :3].max(axis=-1)
            if cfg.get("under") == "glow":
                smooth = pushpull(P4, (~grow).astype(np.float32) * (0.02 + lum ** 2.5))
                smooth = cv2.GaussianBlur(smooth, (0, 0), 5.0) * 0.6
            else:
                smooth = pushpull(P4, (~grow).astype(np.float32))
                smooth = cv2.GaussianBlur(smooth, (0, 0), 3.0)
            # 边上羽化着接过去（不然补的那块和四周的花纹之间是一道人形的硬边）
            wmask = cv2.GaussianBlur(grow.astype(np.float32), (0, 0), 6.0)[..., None]
            P4 = P4 * (1.0 - wmask) + smooth * wmask

    # ---- 4 裁方图、四周渐隐、放大 ----
    x0, y0 = int(cx - R), int(cy - R)
    sq = np.zeros((2 * R, 2 * R, 4), np.float32)
    sx0, sy0 = max(x0, 0), max(y0, 0)
    sx1, sy1 = min(x0 + 2 * R, W), min(y0 + 2 * R, H)
    sq[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = P4[sy0:sy1, sx0:sx1]
    q = np.linspace(-1.0, 1.0, 2 * R, dtype=np.float32)
    qx, qy = np.meshgrid(q, q)
    rad = np.sqrt(qx * qx + qy * qy)
    win = smoothstep(1.0, 0.94, rad)
    if "floor" in cfg:
        # 平台的台面在方图里露了头：那条线以下不要
        fy = (np.arange(2 * R, dtype=np.float32) + y0)[:, None]
        win = win * smoothstep(float(cfg["floor"]), float(cfg["floor"]) - 6.0, fy)
    sq *= win[..., None]
    n = int(cfg["out"])
    big = cv2.resize(sq, (n, n), interpolation=cv2.INTER_LANCZOS4)
    big = np.clip(big, 0.0, 1.0)
    big[..., :3] = np.minimum(big[..., :3], 1.0)
    rgb8 = np.clip(big[..., :3] * 255.0 + 0.5, 0, 255).astype(np.uint8)
    a8 = np.clip(big[..., 3] * 255.0 + 0.5, 0, 255).astype(np.uint8)
    a8 = np.where((a8 == 0) & (rgb8.max(axis=-1) > 0), 1, a8).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    png = np.dstack([rgb8[:, :, ::-1], a8])
    cv2.imencode(".png", png, [cv2.IMWRITE_PNG_COMPRESSION, 9])[1].tofile(os.path.join(OUT, "halo_%d.png" % t))

    # ---- 游戏里用的尺寸 ----
    ch_x, top, sole = cfg["char"]
    k = HERO_H / float(sole - top)
    solid_rows = np.where((sq[..., 3] > 0.35).sum(axis=1) >= 3)[0]
    rc2 = cfg.get("ring", (cx, cy))
    info = {"tier": t, "name": cfg["name"], "size": round(2 * R * k, 3), "center_y": round((sole - cy) * k, 3), "center_x": round((cx - ch_x) * k, 3),
            "bottom_y": round((sole - (y0 + int(solid_rows.max()))) * k, 3), "top_y": round((sole - (y0 + int(solid_rows.min()))) * k, 3),
            "ring": [round((rc2[0] - cx) / float(R), 4), round((rc2[1] - cy) / float(R), 4)], "px_per_unit": R,
            "sky": [round(float(v), 3) for v in B[sy0:sy1, sx0:sx1].reshape(-1, 3).mean(axis=0)]}

    # ---- 核对图 ----
    crop = lambda a: a[sy0:sy1, sx0:sx1]
    ov = C.copy()
    ov[cm] = ov[cm] * 0.45 + np.array([1.0, 0.1, 0.1], np.float32) * 0.55
    save_jpg("chk_%d_mask.jpg" % t, crop(ov))
    save_jpg("chk_%d_bg.jpg" % t, crop(B))
    recon = P4[..., :3] + (1.0 - P4[..., 3:4]) * B
    save_jpg("chk_%d_recon.jpg" % t, np.concatenate([crop(C), crop(recon)], axis=1))
    tiles = []
    for bg in ([0.12, 0.14, 0.2], [0.42, 0.66, 0.34], [0.93, 0.95, 0.98], [0.55, 0.75, 0.95]):
        tiles.append(big[..., :3] + (1.0 - big[..., 3:4]) * np.array(bg, np.float32))
    save_jpg("chk_%d_over.jpg" % t, np.concatenate([np.concatenate(tiles[:2], axis=1), np.concatenate(tiles[2:], axis=1)], axis=0))
    save_jpg("chk_%d_alpha.jpg" % t, np.repeat(big[..., 3:4], 3, axis=-1))
    return info


def main():
    os.makedirs(WORK, exist_ok=True)
    want = [int(a) for a in sys.argv[1:] if not a.startswith("--")] or sorted(TIERS.keys())
    infos = []
    for t in want:
        info = process(t)
        infos.append(info)
        print(json.dumps(info, ensure_ascii=False))
    if len(want) == len(TIERS):
        with open(os.path.join(HERE, "halo_info.json"), "w", encoding="utf-8") as f:
            json.dump(infos, f, ensure_ascii=False, indent=1)


main()
