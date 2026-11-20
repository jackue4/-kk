"""结婴演出用的噪声贴图（fx/cine/cine_noise.png，512×512，可无缝平铺）。
cine_sky / sword_qi / spirit_halo 三个着色器原来每个像素现算分形噪声（天幕一个像素要算二十层），手机上吃不消；
兼容渲染器（网页 / 手机）那条分支改成查这张图。算法和着色器里的 hash2 / vnoise / fbm 是同一套，只是做成了周期的：
  R：四层分形噪声，周期 8 个噪声单位（着色器里 texture(noise, p / 8).r ≈ fbm(p, 4)，取值 0 ~ 0.9375）
  G：单层值噪声，周期 64 格（texture(noise, p / 64).g ≈ vnoise(p)）
  B：另一套随机数的四层分形噪声（给云的第二层、扰动场用，和 R 不相关）
每一层的坐标乘整数矩阵 [[2,-1],[1,2]]（转 26.6°、放大 √5 倍）再平移，格点按「原始坐标周期 8」折回去取随机数，
所以整张图在两个方向上都严丝合缝（不是简单地对格点取模：那样高频层几格就重复一次，看得出规律）。
用法：python _tasks/cine_noise/bake.py   然后用 Godot 重新导入一次（--headless --import）
"""
import os
import numpy as np
from PIL import Image

N = 512          # 贴图边长
P = 8            # 分形噪声的周期（噪声单位）
OCT = 4
VP = 64          # 单层值噪声的周期（格）
M = np.array([[2, -1], [1, 2]], dtype=np.int64)       # 每层的坐标变换
ADJ = np.array([[2, 1], [-1, 2]], dtype=np.int64)     # 它的伴随矩阵（M 的逆 = ADJ / 5）
SHIFT = np.array([13.1, 7.7])


def hash2(qx, qy, seed):
    """和着色器里的 hash2 同一个整数哈希（32 位回绕），seed 换一套随机数"""
    x = (qx.astype(np.int64) + seed * 7919) & 0xFFFFFFFF
    y = (qy.astype(np.int64) + seed * 104729) & 0xFFFFFFFF
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 65535).astype(np.float64) / 65535.0


def wrap(qx, qy, o):
    """第 o 层的格点 (qx, qy) 折回到「原始坐标周期 P」的那一份里。全用整数算，边界上的格点不会因为浮点误差折到两个地方去"""
    mo = np.linalg.matrix_power(M, o)
    ao = np.linalg.matrix_power(ADJ, o)
    den = P * (5 ** o)
    rx = ao[0, 0] * qx + ao[0, 1] * qy       # = 5^o × 原始坐标
    ry = ao[1, 0] * qx + ao[1, 1] * qy
    kx = np.floor_divide(rx, den)
    ky = np.floor_divide(ry, den)
    return qx - P * (mo[0, 0] * kx + mo[0, 1] * ky), qy - P * (mo[1, 0] * kx + mo[1, 1] * ky)


def vnoise(x, y, cell_hash):
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    fy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
    a = cell_hash(ix, iy)
    b = cell_hash(ix + 1, iy)
    c = cell_hash(ix, iy + 1)
    d = cell_hash(ix + 1, iy + 1)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(px, py, seed):
    s = np.zeros_like(px)
    amp = 0.5
    x, y = px.copy(), py.copy()
    for o in range(OCT):
        s += vnoise(x, y, lambda qx, qy, o=o: hash2(*wrap(qx, qy, o), seed + o * 31)) * amp
        x, y = M[0, 0] * x + M[0, 1] * y + SHIFT[0], M[1, 0] * x + M[1, 1] * y + SHIFT[1]
        amp *= 0.5
    return s


def main():
    u = (np.arange(N) + 0.5) / N
    gx, gy = np.meshgrid(u, u)          # gx 沿贴图的横向（U），gy 沿纵向（V）
    r = fbm(gx * P, gy * P, 0)
    b = fbm(gx * P, gy * P, 1000)
    g = vnoise(gx * VP, gy * VP, lambda qx, qy: hash2(np.mod(qx, VP), np.mod(qy, VP), 77))
    # 接缝自检：把图平移半张再算一遍，应该一模一样
    r2 = fbm((gx + 0.5) * P, (gy + 0.5) * P, 0)
    seam = float(np.abs(np.roll(np.roll(r, -N // 2, 0), -N // 2, 1) - r2).max())
    img = np.stack([r, g, b], -1)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "fx", "cine", "cine_noise.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.fromarray(np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8), "RGB").save(out, optimize=True)
    print("R 均值 %.4f 范围 %.3f~%.3f ｜G 均值 %.4f ｜B 均值 %.4f ｜平铺接缝最大误差 %.2e ｜%s %d 字节" % (
        r.mean(), r.min(), r.max(), g.mean(), b.mean(), seam, os.path.normpath(out), os.path.getsize(out)))


if __name__ == "__main__":
    main()
