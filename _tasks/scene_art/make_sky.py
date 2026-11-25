"""主城 / 农场的全景天空盒（2026-11-21 场景美术专项）。

输入：raw/sky_gen_b.png（生图服务出的 2048x1024 粉紫云海图，地平线约在正中，左右两边并不接得上）
输出：assets/sky/hub_pano.jpg（2048x1024 等距柱状投影，左右无缝、两极抹平、整体略微虚化）
      _tasks/scene_art/check/*.jpg（接缝处拼图、几个方向的透视预览，自查用）

做法：
1. 接缝：取最右 B 列和最左 B 列做重叠带，按「两边差异最小的一条竖直路径」切开（image quilting 的最小误差切割），
   路径左边用右边缘的内容、右边用左边缘的内容，切口两侧再羽化几个像素 —— 每个像素只来自一边，没有半透明重影；
   带宽 B 的那一截被叠掉了，再横向重采样回 2048。
2. 两极：等距柱状图越靠近天顶 / 天底，一圈像素在球面上越小（横向被拉了 1/cos(纬度) 倍）。
   画面里的云团离极点近了会被捏成放射状的尖。按纬度做循环的横向模糊（越近极点模糊越大，到极点就是整行平均色），
   天顶成一片平滑的天色、天底是一片平滑的云色。
3. 整体再轻轻高斯模糊一下（用户要「可以虚化一点」），远处的浮岛保留轮廓但不锐。
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "raw", "sky_gen_b.png")
OUT = os.path.join(PROJ, "assets", "sky", "hub_pano.jpg")
CHECK = os.path.join(HERE, "check")
W, H = 2048, 1024
B = 220          # 重叠带宽（像素）
FEATHER = 10     # 切口两边羽化的半宽


def seam_cut(img: np.ndarray) -> np.ndarray:
    """返回宽 w-B 的图：第 w-B-1 列接回第 0 列是连续的。"""
    h, w, _ = img.shape
    L = img[:, w - B:]          # 右边缘那一截：输出的第 0 列要接着原图第 w-B-1 列往下走
    R = img[:, :B]              # 左边缘那一截：输出的第 B-1 列要接着原图第 B 列
    # 差异：亮度 + 颜色的平方差，先糊一下（按块比较，切口不会被单个像素的噪点带偏）
    d = ((L - R) ** 2).sum(axis=2)
    d = cv2.blur(d.astype(np.float32), (7, 7))
    # 靠近带子两头加罚分：切口尽量走在中间，两边都留出羽化的余地
    xs = np.arange(B)
    edge = np.minimum(xs, B - 1 - xs).astype(np.float32)
    d = d + np.where(edge < FEATHER * 2, (FEATHER * 2 - edge) * 50.0, 0.0)[None, :]
    # 动态规划：每行只能比上一行左右挪一格
    cost = d.copy()
    back = np.zeros((h, B), np.int32)
    for y in range(1, h):
        prev = cost[y - 1]
        left = np.concatenate([[np.inf], prev[:-1]])
        right = np.concatenate([prev[1:], [np.inf]])
        stack = np.stack([left, prev, right])
        k = np.argmin(stack, axis=0)
        back[y] = k - 1
        cost[y] = d[y] + stack[k, xs]
    path = np.zeros(h, np.int32)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(h - 1, 0, -1):
        path[y - 1] = path[y] + back[y, path[y]]
    # 路径左边 = L，右边 = R，切口羽化
    t = (xs[None, :] - path[:, None]).astype(np.float32)
    wR = np.clip((t + FEATHER) / (2.0 * FEATHER), 0.0, 1.0)[:, :, None]
    band = L * (1.0 - wR) + R * wR
    out = np.concatenate([band, img[:, B:w - B]], axis=1)
    return out, path


def pole_smooth(img: np.ndarray) -> np.ndarray:
    h, w, _ = img.shape
    out = img.copy()
    for y in range(h):
        lat = (0.5 - (y + 0.5) / h) * np.pi          # +90° 天顶 ~ -90° 天底
        stretch = 1.0 / max(np.cos(lat), 1e-4)        # 这一行在球面上被横向拉了多少倍
        if stretch < 1.6:
            continue
        sigma = (stretch - 1.6) * 5.0                 # 像素
        row = img[y]
        if sigma > w * 0.5:
            out[y] = row.mean(axis=0)
            continue
        # 循环卷积（频域乘高斯）：左右接得上
        f = np.fft.rfft(row, axis=0)
        freqs = np.fft.rfftfreq(w)
        g = np.exp(-2.0 * (np.pi * freqs * sigma) ** 2)
        out[y] = np.fft.irfft(f * g[:, None], n=w, axis=0)
    # 竖直方向再顺一下极点附近（行与行之间模糊量变化快，避免出横纹）
    return out


def gauss(img: np.ndarray, sigma: float) -> np.ndarray:
    # 横向循环、纵向夹边的高斯模糊
    pad = int(sigma * 4) + 1
    ext = np.concatenate([img[:, -pad:], img, img[:, :pad]], axis=1)
    res = cv2.GaussianBlur(ext.astype(np.float32), (0, 0), sigma, borderType=cv2.BORDER_REPLICATE)
    return res[:, pad:-pad]


def persp(img: np.ndarray, yaw_deg: float, pitch_deg: float, fov_deg=75.0, size=(640, 400)) -> Image.Image:
    """从等距柱状图里切一张透视图（自查用）：yaw 0 = 图的正中（u=0.5），往右为正；pitch 向上为正。"""
    h, w, _ = img.shape
    sw, sh = size
    f = 0.5 * sw / np.tan(np.radians(fov_deg) * 0.5)
    xs, ys = np.meshgrid(np.arange(sw) - sw / 2 + 0.5, np.arange(sh) - sh / 2 + 0.5)
    d = np.stack([xs, -ys, np.full_like(xs, f)], axis=2)
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    p, yw = np.radians(pitch_deg), np.radians(yaw_deg)
    y1 = d[..., 1] * np.cos(p) + d[..., 2] * np.sin(p)
    z1 = -d[..., 1] * np.sin(p) + d[..., 2] * np.cos(p)
    x1 = d[..., 0]
    x2 = x1 * np.cos(yw) + z1 * np.sin(yw)
    z2 = -x1 * np.sin(yw) + z1 * np.cos(yw)
    lon = np.arctan2(x2, z2)
    lat = np.arcsin(np.clip(y1, -1, 1))
    u = (lon / (2 * np.pi) + 0.5) * w
    v = (0.5 - lat / np.pi) * h
    ui = np.mod(np.floor(u).astype(int), w)
    vi = np.clip(np.floor(v).astype(int), 0, h - 1)
    return Image.fromarray(np.clip(img[vi, ui], 0, 255).astype(np.uint8))


def main() -> None:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    os.makedirs(CHECK, exist_ok=True)
    src = np.asarray(Image.open(SRC).convert("RGB").resize((W, H), Image.LANCZOS)).astype(np.float32)
    cut, path = seam_cut(src)
    print("seam path x range in band: %d..%d (band %d)" % (path.min(), path.max(), B))
    wide = np.asarray(Image.fromarray(np.clip(cut, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)).astype(np.float32)
    sm = pole_smooth(wide)
    sm = gauss(sm, 1.3)
    out = np.clip(sm, 0, 255).astype(np.uint8)
    Image.fromarray(out).save(OUT, quality=94, subsampling=0)
    print("wrote", OUT, out.shape)
    # 自查：接缝两边各 300 像素拼一起（原图的接缝 vs 处理后的接缝）
    raw_seam = np.concatenate([src[:, -300:], src[:, :300]], axis=1)
    new_seam = np.concatenate([out[:, -300:], out[:, :300]], axis=1).astype(np.float32)
    Image.fromarray(np.concatenate([raw_seam, new_seam], axis=0).astype(np.uint8)).resize((600, 1024)).save(os.path.join(CHECK, "seam_before_after.jpg"), quality=88)
    # 透视预览：接缝方向（图的左右边 = yaw 180°）平视 / 仰视、天顶、天底、正中的太阳
    views = [("seam_level", 180, 0), ("seam_up40", 180, 40), ("zenith", 30, 85), ("nadir", 30, -80), ("sun", 0, 5), ("side", 90, 10)]
    tiles = [persp(out.astype(np.float32), y, p) for _, y, p in views]
    sheet = Image.new("RGB", (640 * 3, 400 * 2))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 3) * 640, (i // 3) * 400))
    sheet.save(os.path.join(CHECK, "persp_views.jpg"), quality=86)
    raw_tiles = [persp(src, y, p) for _, y, p in views[:3]]
    sheet2 = Image.new("RGB", (640 * 3, 400))
    for i, t in enumerate(raw_tiles):
        sheet2.paste(t, (i * 640, 0))
    sheet2.save(os.path.join(CHECK, "persp_views_raw.jpg"), quality=86)
    print("views:", [v[0] for v in views])


if __name__ == "__main__":
    main()
