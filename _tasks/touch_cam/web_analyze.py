"""网页版滑屏量测（web_touch_probe.py 的 web_frames.csv）→ 每帧转速均不均匀。
时间轴用引擎自己的帧间隔（eng_dt，游戏就是按它播放画面的），不靠 Python 端发送时刻对齐：
  在手指匀速滑动的那一段（开始滑 0.15 秒后到停手前 0.1 秒）看每帧 画面转角 / 引擎帧间隔：
  抖动 %       每帧转速的变异系数（标准差 / 平均，手指是匀速的，理想是 0）
  停顿帧/秒    这一帧转速不到中位数的 30%（画面这一帧几乎没动）
  最大一步 ×   最快那一帧是中位转速的几倍
  末差 °       停手后画面和 yaw 的差（应为 0）
用法：python -I web_analyze.py <输出目录>
"""
import csv
import json
import math
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

NAMES = {"mid60": "中速 200 CSS px/s · 60Hz 触摸", "slow60q": "慢滑 40 CSS px/s · 60Hz · 整像素", "fast60": "快滑 450 CSS px/s · 60Hz",
         "mid30": "中速 · 30Hz 触摸"}


def wrapd(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def main():
    out = Path(sys.argv[1])
    sent = json.load(open(out / "web_sent.json", encoding="utf-8"))
    rows = defaultdict(list)
    with open(out / "web_frames.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows[(r["scene"], r["mode"])].append(r)
    lines = ["| 剧本 | 模式 | 抖动 % | 停顿帧/秒 | 最大一步 × | 帧数 | 引擎帧间隔 中位 / 最长 ms | 末差 ° |", "|---|---|---|---|---|---|---|---|"]
    summ = defaultdict(list)
    for sc in NAMES:
        for mode in ("raw", "new"):
            rs = rows.get((sc, mode))
            if not rs:
                continue
            log = sent["%s|%s" % (sc, mode)]
            t_mv0, t_mv1 = log[1][0], log[-1][0]
            pt = [float(r["t_ms"]) for r in rs]
            vy = [float(r["view_yaw"]) for r in rs]
            ly = [float(r["yaw"]) for r in rs]
            dt = [float(r["eng_dt"]) for r in rs]
            vel = []
            dts = []
            for i in range(1, len(rs)):
                if t_mv0 + 150 <= pt[i] <= t_mv1 - 100 and dt[i] > 0:
                    vel.append(abs(wrapd(vy[i] - vy[i - 1])) / dt[i])
                    dts.append(dt[i] * 1000)
            if len(vel) < 5:
                continue
            mean = st.mean(vel)
            med = st.median(vel)
            cv = st.pstdev(vel) / mean * 100
            span = (t_mv1 - 100 - (t_mv0 + 150)) / 1000.0
            stalls = sum(1 for v in vel if v < 0.3 * med) / span
            mx = max(vel) / med
            end = abs(wrapd(vy[-1] - ly[-1])) * 180 / math.pi
            summ[mode].append((cv, stalls, mx))
            lines.append("| %s | %s | %.1f | %.1f | %.2f | %d | %.1f / %.1f | %.4f |" % (NAMES[sc], "改之前" if mode == "raw" else "现在", cv, stalls, mx, len(vel),
                         st.median(dts), max(dts), end))
    lines.append("")
    lines.append("| 平均（四个剧本） | 抖动 % | 停顿帧/秒 | 最大一步 × |")
    lines.append("|---|---|---|---|")
    for mode in ("raw", "new"):
        if summ[mode]:
            a = summ[mode]
            lines.append("| %s | %.1f | %.1f | %.2f |" % ("改之前" if mode == "raw" else "现在", st.mean(x[0] for x in a), st.mean(x[1] for x in a), st.mean(x[2] for x in a)))
    txt = "\n".join(lines)
    (out / "web_metrics.md").write_text(txt, encoding="utf-8")
    sys.stdout.buffer.write(txt.encode("utf-8"))


if __name__ == "__main__":
    main()
