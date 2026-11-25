"""数值重构的回归批：按顺序跑一串隐藏窗口自检，记每项 SCRIPT ERROR 数和关键结果行。用法：python -I regress.py <工程目录> <日志目录>"""
import subprocess, sys, os, time, re
ROOT, LOG = sys.argv[1], sys.argv[2]
RUN = os.path.join(os.path.dirname(__file__), "run_hidden_long.py")
os.makedirs(LOG, exist_ok=True)
TESTS = [
    ("econ", ["--resolution", "1280x720", "--", "--raid-shot", "--raid-econ"]),
    ("rtrib", ["--resolution", "1280x720", "--", "--raid-shot", "--raid-trib"]),
    ("hub", ["--resolution", "1280x720", "--", "--hub-shot"]),
    ("hub_touch", ["--resolution", "1280x720", "--rendering-method", "gl_compatibility", "--", "--hub-shot", "--touch"]),
    ("raid", ["--resolution", "1280x720", "--", "--raid-shot"]),
    ("raid_touch", ["--resolution", "1280x720", "--rendering-method", "gl_compatibility", "--", "--raid-shot", "--touch"]),
    ("rally", ["--resolution", "1280x720", "--", "--raid-shot", "--raid-ally"]),
    ("rai", ["--resolution", "1280x720", "--", "--raid-shot", "--raid-ai"]),
    ("insight", ["--resolution", "1280x720", "--", "--raid-shot", "--raid-pace", "--pace-insight"]),
    ("combat", ["--resolution", "1280x720", "--", "--combat-shot"]),
    ("spark", ["--resolution", "1280x720", "--", "--duel-shot", "--spark"]),
]
KEY = re.compile(r"PASS|FAIL|应为|应涨|失败|\[econ\].*(结算|渡劫)|\[hub\].*(打坐|渡劫|瓶颈)|\[insight\].*小结|\[raid\].*(服丹|战力|压制)|\[ally\].*击杀")
only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
for name, args in TESTS:
    if only and name not in only:
        continue
    t0 = time.time()
    pre = os.path.join(LOG, "rg_" + name)
    subprocess.run([sys.executable, "-I", RUN, ROOT, pre] + args, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    err = open(pre + "_err.txt", encoding="utf-8", errors="replace").read() if os.path.exists(pre + "_err.txt") else ""
    out = open(pre + "_out.txt", encoding="utf-8", errors="replace").read() if os.path.exists(pre + "_out.txt") else ""
    n_err = (err + out).count("SCRIPT ERROR")
    keys = [l for l in out.splitlines() if KEY.search(l)][:12]
    with open(os.path.join(LOG, "regress_summary.txt"), "a", encoding="utf-8") as f:
        f.write("=== %s  %.0fs  SCRIPT ERROR %d\n" % (name, time.time() - t0, n_err))
        for l in keys:
            f.write("   " + l[:220] + "\n")
        if n_err:
            for m in re.finditer(r"SCRIPT ERROR:[^\n]*\n[^\n]*\n", err + out):
                f.write("   !! " + m.group(0).replace("\n", " | ")[:300] + "\n")
                break
print("done")
