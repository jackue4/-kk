"""找 z-fighting 的来源：同朝向、共面（或只差几厘米）、而且在面内有重叠的三角形对。
输入是 look_probe.gd --dump 写的 geo_*.bin（世界坐标三角形 + 顶点色）。
用法：python -I zfight.py <geo.bin> [--tol 0.04] [--top 40] [--min-area 0.02] [--box x0,z0,x1,z1]
输出：按「哪两张网格」和「在哪一带（8 米一格）」汇总的重叠面积，并列出面积最大的若干对（位置、朝向、两边颜色、两个面相隔多远）。
相隔 < 1 毫米算「完全共面」（任何渲染器、任何距离都闪）；1 毫米 ~ tol 算「贴得太近」（手机 / 网页的 24 位深度在几十米外会闪）。
"""
import struct
import sys
from collections import defaultdict

import numpy as np


SKIP = []


def load(path):
    data = open(path, "rb").read()
    off = 0
    names, P, C, M = [], [], [], []
    while off < len(data):
        n, ln = struct.unpack_from("<ii", data, off)
        off += 8
        name = data[off:off + ln].decode("utf-8")
        off += ln
        pos = np.frombuffer(data, dtype="<f4", count=n * 3, offset=off).reshape(-1, 3, 3)
        off += n * 12
        col = np.frombuffer(data, dtype="<f4", count=n * 4, offset=off).reshape(-1, 3, 4)
        off += n * 16
        if "PortalView/" in name or any(x in name for x in SKIP):
            continue        # 透视门里的场景副本（另一个世界），不算
        P.append(pos.astype(np.float64))
        C.append(col.astype(np.float64))
        M.append(np.full(len(pos), len(names), dtype=np.int32))
        names.append(name)
    return names, np.concatenate(P), np.concatenate(C), np.concatenate(M)


def clip_area(a2, b2):
    """两个二维三角形的重叠面积（Sutherland–Hodgman：拿 a 的三条边去裁 b）"""
    def area(poly):
        s = 0.0
        for i in range(len(poly)):
            x0, y0 = poly[i]
            x1, y1 = poly[(i + 1) % len(poly)]
            s += x0 * y1 - x1 * y0
        return s * 0.5
    if area(a2) < 0:
        a2 = a2[::-1]
    poly = [tuple(p) for p in b2]
    for i in range(3):
        ax, ay = a2[i]
        bx, by = a2[(i + 1) % 3]
        ex, ey = bx - ax, by - ay
        out = []
        m = len(poly)
        if m == 0:
            return 0.0
        for j in range(m):
            px, py = poly[j]
            qx, qy = poly[(j + 1) % m]
            sp = ex * (py - ay) - ey * (px - ax)
            sq = ex * (qy - ay) - ey * (qx - ax)
            if sp >= 0:
                out.append((px, py))
            if (sp >= 0) != (sq >= 0):
                t = sp / (sp - sq)
                out.append((px + (qx - px) * t, py + (qy - py) * t))
        poly = out
    if len(poly) < 3:
        return 0.0
    return abs(area(poly))


class Occl:
    """这个点是不是埋在实心里（看不见）：从点往 上 / ±x / ±z 五个方向打射线，最近的命中是「从背面打到」的方向 ≥ 4 个就算埋住。
    网格全是没有底面的方块 + 地面的面片：人在方块里往外看，四周和头顶都是方块自己的背面。"""
    def __init__(self, P, nrm):
        self.P = P
        self.n = nrm          # 这里的法线 = (p1-p0)×(p2-p0)，对顺时针的正面来说指向背面一侧（朝里）
        self.lo = P.min(axis=1)
        self.hi = P.max(axis=1)
        self.cache = {}

    def _ray(self, o, axis, sign):
        a1, a2 = [(1, 2), (0, 2), (0, 1)][axis]
        m = (self.lo[:, a1] <= o[a1]) & (self.hi[:, a1] >= o[a1]) & (self.lo[:, a2] <= o[a2]) & (self.hi[:, a2] >= o[a2])
        if sign > 0:
            m &= self.hi[:, axis] > o[axis] + 0.05
        else:
            m &= self.lo[:, axis] < o[axis] - 0.05
        idx = np.nonzero(m)[0]
        if len(idx) == 0:
            return 0
        T = self.P[idx]
        d = np.zeros(3)
        d[axis] = sign
        e1 = T[:, 1] - T[:, 0]
        e2 = T[:, 2] - T[:, 0]
        h = np.cross(d[None, :], e2)
        det = np.einsum("ij,ij->i", e1, h)
        ok = np.abs(det) > 1e-9
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = o[None, :] - T[:, 0]
        u = np.einsum("ij,ij->i", s, h) * inv
        q = np.cross(s, e1)
        v = (q @ d) * inv
        t = np.einsum("ij,ij->i", e2, q) * inv
        hit = ok & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6) & (t > 0.05)
        if not hit.any():
            return 0
        k = np.argmin(np.where(hit, t, 1e18))
        # 自算法线朝里：射线方向和它同向 = 从正面打进去；反向 = 从背面（里面）打到
        return 1 if float(self.n[idx[k]] @ d) < 0 else -1

    def buried(self, c, n_in):
        o = c - n_in * 0.03       # 面前 3 厘米处（n_in 朝里，所以减）
        key = (round(o[0] * 8), round(o[1] * 8), round(o[2] * 8))
        if key in self.cache:
            return self.cache[key]
        back = 0
        for axis, sign in ((1, 1), (0, 1), (0, -1), (2, 1), (2, -1)):
            if self._ray(o, axis, sign) == 1:
                back += 1
        r = back >= 4
        self.cache[key] = r
        return r


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    path = sys.argv[1]
    tol, top, min_area, box = 0.04, 40, 0.02, None
    a = sys.argv[2:]
    for i, s in enumerate(a):
        if s == "--tol":
            tol = float(a[i + 1])
        if s == "--top":
            top = int(a[i + 1])
        if s == "--min-area":
            min_area = float(a[i + 1])
        if s == "--box":
            box = [float(v) for v in a[i + 1].split(",")]
        if s == "--skip":
            SKIP.extend(a[i + 1].split(","))
    names, P, C, M = load(path)
    nrm = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    ar = np.linalg.norm(nrm, axis=1) * 0.5
    keep = ar > 1e-5
    if box:
        cen = P.mean(axis=1)
        keep &= (cen[:, 0] >= box[0]) & (cen[:, 0] <= box[2]) & (cen[:, 2] >= box[1]) & (cen[:, 2] <= box[3])
    P, C, M, nrm, ar = P[keep], C[keep], M[keep], nrm[keep], ar[keep]
    nrm = nrm / (2.0 * ar[:, None])
    d = np.einsum("ij,ij->i", nrm, P[:, 0])
    print("三角形 %d 个，网格 %d 张" % (len(P), len(names)))
    GRID = 4.0
    DB = max(tol * 2.0, 0.02)
    nq = np.round(nrm * 48).astype(np.int32)
    lo = np.floor((P.min(axis=1) - tol) / GRID).astype(np.int32)
    hi = np.floor((P.max(axis=1) + tol) / GRID).astype(np.int32)
    buckets = defaultdict(list)
    big = 0
    for t in range(len(P)):
        k0 = (int(nq[t, 0]), int(nq[t, 1]), int(nq[t, 2]))
        d0 = int(np.floor(d[t] / DB))
        d1 = int(np.floor(d[t] / DB + 0.5))
        cells = (hi[t] - lo[t] + 1)
        if int(cells[0]) * int(cells[1]) * int(cells[2]) > 4000:
            big += 1
        for cx in range(lo[t, 0], hi[t, 0] + 1):
            for cy in range(lo[t, 1], hi[t, 1] + 1):
                for cz in range(lo[t, 2], hi[t, 2] + 1):
                    buckets[(k0, cx, cy, cz, 0, d0)].append(t)
                    buckets[(k0, cx, cy, cz, 1, d1)].append(t)
    seen = set()
    hits = []
    for key, lst in buckets.items():
        if len(lst) < 2:
            continue
        for ii in range(len(lst)):
            ta = lst[ii]
            for jj in range(ii + 1, len(lst)):
                tb = lst[jj]
                pr = (ta, tb) if ta < tb else (tb, ta)
                if pr in seen:
                    continue
                seen.add(pr)
                na = nrm[ta]
                if float(np.dot(na, nrm[tb])) < 0.9995:
                    continue
                sep = np.abs(P[tb] @ na - d[ta])
                if sep.max() > tol:
                    continue
                # 投到 ta 的平面上
                u = P[ta, 1] - P[ta, 0]
                u = u / np.linalg.norm(u)
                v = np.cross(na, u)
                a2 = [(float(np.dot(p - P[ta, 0], u)), float(np.dot(p - P[ta, 0], v))) for p in P[ta]]
                b2 = [(float(np.dot(p - P[ta, 0], u)), float(np.dot(p - P[ta, 0], v))) for p in P[tb]]
                if max(x for x, _ in a2) <= min(x for x, _ in b2) + 1e-4 or max(x for x, _ in b2) <= min(x for x, _ in a2) + 1e-4:
                    continue
                if max(y for _, y in a2) <= min(y for _, y in b2) + 1e-4 or max(y for _, y in b2) <= min(y for _, y in a2) + 1e-4:
                    continue
                ov = clip_area(a2, b2)
                if ov < 1e-4:
                    continue
                ca = C[ta, :, :3].mean(axis=0)
                cb = C[tb, :, :3].mean(axis=0)
                hits.append((ov, float(sep.mean()), ta, tb, float(np.abs(ca - cb).max())))
    print("候选对 %d，重叠的 %d" % (len(seen), len(hits)))
    # 同色又完全共面的看不出来，不算；其余的逐对看是不是埋在实心里
    occ = Occl(P, nrm)
    vis = []
    hidden = 0
    for h in hits:
        ov, sep, ta, tb, dc = h
        if sep < 0.001 and dc <= 0.02:
            continue
        # 重叠区的代表点：两个三角形重心的中点往两边各试一下（取在两个三角形里都算数的那个）
        c = (P[ta].mean(axis=0) + P[tb].mean(axis=0)) * 0.5
        if occ.buried(c, nrm[ta]):
            hidden += 1
            continue
        vis.append(h)
    print("其中埋在实心里看不见的 %d 对；剩下可能看得见的 %d 对" % (hidden, len(vis)))
    hits = vis
    # 汇总
    exact = [h for h in hits if h[1] < 0.001]
    near = [h for h in hits if h[1] >= 0.001]
    def tot(hs, vis_only):
        return sum(h[0] for h in hs if (h[4] > 0.02 or not vis_only))
    print("完全共面：%d 对，重叠 %.1f m²（其中两边颜色不同、看得出闪的 %.1f m²）" % (len(exact), tot(exact, False), tot(exact, True)))
    print("贴得太近（1mm~%.0fmm）：%d 对，重叠 %.1f m²" % (tol * 1000, len(near), tot(near, False)))
    for title, hs in (("完全共面且颜色不同", [h for h in exact if h[4] > 0.02]), ("完全共面但同色（看不出，只是白画）", [h for h in exact if h[4] <= 0.02]), ("贴得太近", near)):
        if not hs:
            continue
        print("\n==== %s ====" % title)
        by_mesh = defaultdict(float)
        by_place = defaultdict(lambda: [0.0, 0, None])
        for ov, sep, ta, tb, dc in hs:
            by_mesh[(names[M[ta]], names[M[tb]])] += ov
            c = (P[ta].mean(axis=0) + P[tb].mean(axis=0)) * 0.5
            nn = nrm[ta]
            face = "顶" if abs(nn[1]) > 0.9 else ("侧" if abs(nn[1]) < 0.1 else "斜")
            k = (int(np.floor(c[0] / 8.0)) * 8, int(np.floor(c[2] / 8.0)) * 8, face)
            e = by_place[k]
            e[0] += ov
            e[1] += 1
            if e[2] is None or ov > e[2][0]:
                e[2] = (ov, c, sep, C[ta, :, :3].mean(axis=0), C[tb, :, :3].mean(axis=0), nn)
        for k, v in sorted(by_mesh.items(), key=lambda kv: -kv[1])[:8]:
            print("  网格 %s × %s：%.1f m²" % (k[0][-40:], k[1][-40:], v))
        n_shown = 0
        for k, e in sorted(by_place.items(), key=lambda kv: -kv[1][0]):
            if e[0] < min_area:
                continue
            ov, c, sep, ca, cb, nn = e[2]
            print("  x %5d~%-5d z %5d~%-5d %s面 共 %.2f m² / %d 对｜最大一对 %.2f m² 在 (%.1f, %.1f, %.1f) 法线 (%.2f,%.2f,%.2f) 相隔 %.1f mm 颜色 (%.2f,%.2f,%.2f) vs (%.2f,%.2f,%.2f)" % (
                k[0], k[0] + 8, k[1], k[1] + 8, k[2], e[0], e[1], ov, c[0], c[1], c[2], nn[0], nn[1], nn[2], sep * 1000, ca[0], ca[1], ca[2], cb[0], cb[1], cb[2]))
            n_shown += 1
            if n_shown >= top:
                print("  …（还有 %d 处）" % (len([1 for v in by_place.values() if v[0] >= min_area]) - n_shown))
                break


main()
