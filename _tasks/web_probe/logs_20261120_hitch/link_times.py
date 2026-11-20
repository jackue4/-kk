"""run_probe_t.py 的日志：把每个着色器程序的等待时间（[gl] linked #n ms）按段、按「默认特化 / 实际用到的」汇总。"""
import re, sys
for path in sys.argv[1:]:
    seg = "开机之前"; sig = {}; rows = {}
    for line in open(path, encoding="utf-8"):
        b = line[9:] if line[7:9] == "s " else line
        if b.startswith("[hp] <<< "): seg = b[9:].strip()
        elif b.startswith("[hp] >>> "): seg = "（段间）"
        m = re.match(r"\[gl\] link #(\d+) (.*)", b)
        if m:
            sig[int(m.group(1))] = ("DISABLE_LIGHTMAP" not in m.group(2)) and ("MATERIAL_UNIFORMS_USED" in m.group(2) or "MAX_FORWARD_LIGHTS" in m.group(2))
            continue
        m = re.match(r"\[gl\] linked #(\d+) (\d+)", b)
        if m:
            n, ms = int(m.group(1)), int(m.group(2))
            r = rows.setdefault(seg, [0, 0, 0, 0])
            if sig.get(n):
                r[0] += 1; r[1] += ms
            else:
                r[2] += 1; r[3] += ms
    print("====", path)
    for k, r in rows.items():
        if r[0] + r[2]:
            print("  %-30s 默认特化的场景着色器 %3d 个 %6d ms ｜ 其余 %3d 个 %6d ms" % (k, r[0], r[1], r[2], r[3]))
