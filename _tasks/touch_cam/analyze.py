"""滑屏转镜头量测（touch_look_probe.gd 的 CSV）→ 指标表 + 角速度曲线图。只读 CSV，不碰游戏文件。
用法：python -I analyze.py <输出目录> <csv> [<csv> ...]
指标（每个 档位×剧本×模式）：
  滞后 ms        画面朝向对齐理想手指轨迹需要往后挪多少时间（最小二乘找最佳平移）
  抖动 %         对齐后每帧转角和理想每帧转角之差的均方根 / 理想每帧转角的均方根（0 = 和手指一样匀）
  停顿帧/秒      手指在动、这一帧画面却几乎没转（< 理想的 30%）
  最大一步 ×     最大的一帧转角是理想平均每帧转角的几倍（一格格跳时是 2 倍以上）
  停手后 ms      手指停下后画面再过多久停稳（和最终角度差 < 0.03°）
  过冲 °         停手后画面越过最终角度多少（应为 0）
  末差 °         最后画面和 yaw 的差（应为 0：总量一分不差）
"""
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\msyh.ttc"
DEG = 180.0 / math.pi
NAMES = {"fast60": "快滑 900px/s · 60Hz", "mid60": "中速 400px/s · 60Hz", "slow60q": "慢滑 80px/s · 60Hz · 整 2 像素",
         "mid30": "中速 · 30Hz 采样", "mid120": "中速 · 120Hz 采样", "flick": "一甩（先快后慢）", "sine": "左右来回",
         "pitchcap": "斜着推到俯仰上限"}


def unwrap(a):
    out = [a[0]]
    for v in a[1:]:
        d = v - out[-1]
        d = (d + math.pi) % (2 * math.pi) - math.pi
        out.append(out[-1] + d)
    return out


def load(paths):
    rows = defaultdict(list)
    for p in paths:
        with open(p, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                rows[(r["tag"], r["scene"], r["mode"])].append(r)
    data = {}
    for k, rs in rows.items():
        t = [float(r["t"]) for r in rs]
        ph = [int(r["phase"]) for r in rs]
        vy = unwrap([float(r["view_yaw"]) for r in rs])
        iy = [float(r["ideal_yaw"]) for r in rs]
        ly = [float(r["yaw"]) for r in rs]
        vp = [float(r["view_pitch"]) for r in rs]
        ip = [float(r["ideal_pitch"]) for r in rs]
        # 画面偏航和 yaw 只差 2π 的整数倍：对齐到 yaw 的那一圈
        off = round((ly[0] - vy[0]) / (2 * math.pi)) * 2 * math.pi
        vy = [v + off for v in vy]
        data[k] = dict(t=t, ph=ph, vy=vy, iy=iy, ly=ly, vp=vp, ip=ip)
    return data


def interp(ts, vs, x):
    if x <= ts[0]:
        return vs[0]
    if x >= ts[-1]:
        return vs[-1]
    lo, hi = 0, len(ts) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if ts[mid] <= x:
            lo = mid
        else:
            hi = mid
    u = (x - ts[lo]) / max(ts[hi] - ts[lo], 1e-9)
    return vs[lo] + (vs[hi] - vs[lo]) * u


def metrics(d, use_pitch=False):
    t, ph = d["t"], d["ph"]
    v = d["vp"] if use_pitch else d["vy"]
    ideal = d["ip"] if use_pitch else d["iy"]
    mv = [i for i in range(len(t)) if ph[i] == 1 and t[i] > 0.08]
    dur = max(t[i] for i in range(len(t)) if ph[i] == 1)
    # 最佳平移（滞后）：0 ~ 150ms，1ms 一档
    best = (1e9, 0.0)
    for lag_ms in range(0, 151):
        L = lag_ms / 1000.0
        e = sum((v[i] - interp(t, ideal, t[i] - L)) ** 2 for i in mv)
        if e < best[0]:
            best = (e, L)
    L = best[1]
    dv, di = [], []
    for i in mv:
        if i == 0:
            continue
        dv.append(v[i] - v[i - 1])
        di.append(interp(t, ideal, t[i] - L) - interp(t, ideal, t[i - 1] - L))
    rms_i = math.sqrt(sum(x * x for x in di) / len(di))
    jit = math.sqrt(sum((a - b) ** 2 for a, b in zip(dv, di)) / len(di)) / max(rms_i, 1e-12)
    mean_i = sum(abs(x) for x in di) / len(di)
    stalls = sum(1 for a, b in zip(dv, di) if abs(b) > 0.25 * mean_i and abs(a) < 0.3 * abs(b))
    span = (t[mv[-1]] - t[mv[0]]) or 1.0
    mx = max(abs(a) for a in dv) / max(mean_i, 1e-12)
    # 停手
    fin = v[-1]
    # 过冲按停手前最后那一段的运动方向算（来回、一甩这种剧本，最后的方向不一定是总位移的方向）
    last = [i for i in range(len(t)) if ph[i] == 1]
    i1 = last[-1]
    i0 = max(last[0], i1 - 6)
    dd = ideal[i1] - ideal[i0]
    if abs(dd) < 1e-6:
        dd = ideal[-1] - ideal[0]
    sgn = 1.0 if dd >= 0 else -1.0
    settle = 0.0
    for i in range(len(t)):
        if t[i] > dur and abs(v[i] - fin) >= 0.0005:
            settle = t[i] - dur + (t[i + 1] - t[i] if i + 1 < len(t) else 0.0)
    over = max(0.0, max((v[i] - fin) * sgn for i in range(len(t)) if t[i] > dur))
    lend = (d["ly"][-1] - d["vy"][-1]) if not use_pitch else 0.0
    return dict(lag=L * 1000, jit=jit * 100, stall=stalls / span, mx=mx, settle=settle * 1000, over=over * DEG, end=abs(lend) * DEG)


def fps_spread(data, scene, mode, tags):
    """同一剧本在不同帧率下的画面轨迹差多少（°，按最快那档的时刻对齐比较，含停手后）"""
    have = [tg for tg in tags if (tg, scene, mode) in data]
    if len(have) < 2:
        return None
    ref = data[(have[0], scene, mode)]
    r0 = ref["vy"][0]
    worst = 0.0
    for tg in have[1:]:
        o = data[(tg, scene, mode)]
        o0 = o["vy"][0]
        for i in range(len(o["t"])):
            if o["t"][i] < 0.0:
                continue
            a = interp(ref["t"], [x - r0 for x in ref["vy"]], o["t"][i])
            worst = max(worst, abs((o["vy"][i] - o0) - a))
    return worst * DEG


def chart(data, picks, out, title):
    W, H = 1500, 300 * len(picks) + 90
    im = Image.new("RGB", (W, H), (250, 248, 242))
    d = ImageDraw.Draw(im)
    f1, f2, f3 = ImageFont.truetype(FONT, 30), ImageFont.truetype(FONT, 22), ImageFont.truetype(FONT, 17)
    d.text((24, 16), title, font=f1, fill=(30, 30, 30))
    d.line((W - 560, 34, W - 520, 34), fill=(205, 70, 60), width=3)
    d.text((W - 512, 22), "改之前", font=f2, fill=(60, 60, 60))
    d.line((W - 420, 34, W - 380, 34), fill=(40, 110, 200), width=4)
    d.text((W - 372, 22), "现在", font=f2, fill=(60, 60, 60))
    d.line((W - 290, 34, W - 250, 34), fill=(120, 120, 120), width=2)
    d.text((W - 242, 22), "手指（理想）", font=f2, fill=(60, 60, 60))
    for j, (tg, sc, cap) in enumerate(picks):
        y0 = 80 + j * 300
        x0, x1, ph = 90, W - 30, 230
        d.rectangle((x0, y0 + 30, x1, y0 + 30 + ph), outline=(190, 185, 175))
        d.text((x0, y0), cap, font=f2, fill=(30, 30, 30))
        series = []
        vmax = 1.0
        for mode in ("raw", "new"):
            k = (tg, sc, mode)
            if k not in data:
                continue
            dd = data[k]
            pts = []
            for i in range(1, len(dd["t"])):
                dt = dd["t"][i] - dd["t"][i - 1]
                if dt <= 0:
                    continue
                pts.append((dd["t"][i], -(dd["vy"][i] - dd["vy"][i - 1]) / dt * DEG))
            ideal = []
            for i in range(1, len(dd["t"])):
                dt = dd["t"][i] - dd["t"][i - 1]
                if dt > 0:
                    ideal.append((dd["t"][i], -(dd["iy"][i] - dd["iy"][i - 1]) / dt * DEG))
            series.append((mode, pts, ideal))
            vmax = max(vmax, max(abs(p[1]) for p in pts), max(abs(p[1]) for p in ideal))
        if not series:
            continue
        tmin = min(p[0] for p in series[0][1])
        tmax = max(p[0] for p in series[0][1])
        vmin = min(0.0, min(min(p[1] for p in s[1]) for s in series))
        vtop = vmax * 1.08

        def X(t):
            return x0 + (t - tmin) / (tmax - tmin) * (x1 - x0)

        def Y(v):
            return y0 + 30 + ph - (v - vmin) / (vtop - vmin) * ph

        d.line((x0, Y(0), x1, Y(0)), fill=(215, 210, 200))
        for tick in range(0, int(vtop) + 1, max(1, int(vtop / 4 / 50 + 1) * 50)):
            d.text((8, Y(tick) - 10), f"{tick}°/s", font=f3, fill=(120, 115, 110))
        d.line([(X(t), Y(v)) for t, v in series[0][2]], fill=(120, 120, 120), width=2)
        for mode, pts, _ in series:
            col, w = ((205, 70, 60), 2) if mode == "raw" else ((40, 110, 200), 3)
            d.line([(X(t), Y(v)) for t, v in pts], fill=col, width=w)
        d.text((x1 - 260, y0 + 4), f"横轴 {tmin:.2f}~{tmax:.2f} 秒（0 = 开始滑）", font=f3, fill=(120, 115, 110))
    im.save(out, quality=92)


def main():
    outdir = Path(sys.argv[1])
    data = load(sys.argv[2:])
    tags = sorted({k[0] for k in data})
    scenes = []
    for k in data:
        if k[1] not in scenes:
            scenes.append(k[1])
    lines = ["| 档位 | 剧本 | 模式 | 滞后 ms | 抖动 % | 停顿帧/秒 | 最大一步 × | 停手后 ms | 过冲 ° | 末差 ° |", "|---|---|---|---|---|---|---|---|---|---|"]
    summ = defaultdict(list)
    for tg in tags:
        for sc in scenes:
            for mode in ("raw", "new"):
                k = (tg, sc, mode)
                if k not in data:
                    continue
                m = metrics(data[k])
                summ[(tg, mode)].append(m)
                lines.append("| %s | %s | %s | %.0f | %.1f | %.1f | %.2f | %.0f | %.3f | %.4f |" % (tg, NAMES.get(sc, sc), "改之前" if mode == "raw" else "现在",
                             m["lag"], m["jit"], m["stall"], m["mx"], m["settle"], m["over"], m["end"]))
                if sc == "pitchcap":
                    mp = metrics(data[k], use_pitch=True)
                    pmax = max(data[k]["vp"])
                    lines.append("| %s | %s（俯仰） | %s | %.0f | %.1f | %.1f | %.2f | %.0f | %.3f | 画面俯仰最大 %.4f（上限 1.3） |" % (tg, NAMES.get(sc, sc),
                                 "改之前" if mode == "raw" else "现在", mp["lag"], mp["jit"], mp["stall"], mp["mx"], mp["settle"], mp["over"], pmax))
    lines.append("")
    lines.append("各档位平均（八个剧本）：")
    lines.append("| 档位 | 模式 | 滞后 ms | 抖动 % | 停顿帧/秒 | 最大一步 × | 停手后 ms（最长） | 过冲 °（最大） |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for tg in tags:
        for mode in ("raw", "new"):
            ms = summ[(tg, mode)]
            if not ms:
                continue
            avg = lambda key: sum(x[key] for x in ms) / len(ms)
            lines.append("| %s | %s | %.0f | %.1f | %.1f | %.2f | %.0f | %.3f |" % (tg, "改之前" if mode == "raw" else "现在", avg("lag"), avg("jit"), avg("stall"),
                         avg("mx"), max(x["settle"] for x in ms), max(x["over"] for x in ms)))
    fixed = [tg for tg in tags if tg.rstrip("0123456789").endswith("f")]
    fixed.sort(key=lambda s: int(s.split("f")[-1]))
    if len(fixed) >= 2:
        lines.append("")
        lines.append("帧率依赖（同一剧本在 %s 下）：抖动 %% / 滞后 ms" % " / ".join(fixed))
        lines.append("| 剧本 | 改之前 抖动 | 现在 抖动 | 改之前 滞后 | 现在 滞后 |")
        lines.append("|---|---|---|---|---|")
        for sc in scenes:
            row = {}
            for mode in ("raw", "new"):
                row[mode] = [metrics(data[(tg, sc, mode)]) for tg in fixed if (tg, sc, mode) in data]
            if not row["raw"] or not row["new"]:
                continue
            f = lambda ms, key: " / ".join("%.0f" % x[key] for x in ms)
            lines.append("| %s | %s | %s | %s | %s |" % (NAMES.get(sc, sc), f(row["raw"], "jit"), f(row["new"], "jit"),
                         f(row["raw"], "lag"), f(row["new"], "lag")))
    txt = "\n".join(lines)
    (outdir / "touch_look_metrics.md").write_text(txt, encoding="utf-8")
    print(txt)
    pick = []
    for tg, sc, cap in [("f120", "mid120", "120 帧画面 · 中速滑（手机高刷屏）"), ("f120", "mid60", "120 帧画面 · 60Hz 触摸（高刷屏常见组合）"),
                        ("rt", "mid60", "真实时间运行（处理时刻抖动，按引擎显示时钟量）· 60Hz 触摸"), ("f60", "mid30", "60 帧画面 · 30Hz 触摸采样"),
                        ("f60", "slow60q", "60 帧画面 · 慢滑、整 2 像素（网页里常见）"), ("f60", "flick", "60 帧画面 · 一甩到停")]:
        full = [k for k in tags if k.endswith(tg)]
        if full:
            pick.append((full[0], sc, cap))
    if pick:
        chart(data, pick, outdir / "touch_look_chart.jpg", "手机滑屏转镜头：画面每帧的转速（°/秒）改之前 vs 现在")


if __name__ == "__main__":
    main()
