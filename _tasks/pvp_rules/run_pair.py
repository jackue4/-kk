"""真人对打规则的双开自检：同时起两个隐藏窗口（a / b），等它们跑完，把两边的 [pvp] 行和报错数打出来。
用法：python -I _tasks/pvp_rules/run_pair.py <标签> [--gl] <剧本参数...>
例：python -I _tasks/pvp_rules/run_pair.py mash_new --pvp-rules=mash --pvp-realm=5
    加 --gl = 手机那套渲染（gl_compatibility + --touch）"""
import os, subprocess, sys, re

PROJ = r"D:\GodotProjects\修仙游戏"
RUN = os.path.join(PROJ, "_tasks", "trailer", "run_hidden.py")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    tag = sys.argv[1]
    extra = sys.argv[2:]
    gl = "--gl" in extra
    extra = [a for a in extra if a != "--gl"]
    procs = []
    for role in "ab":
        log = os.path.join(PROJ, "_shots", "pvp_%s_%s" % (tag, role))
        args = [sys.executable, "-I", RUN, PROJ, log, "--resolution", "640x360"]
        if gl:
            args += ["--rendering-method", "gl_compatibility"]
        args += ["--", "--hub-shot", "--arena-duel", "--arena-net=" + role] + extra + (["--touch"] if gl else [])
        procs.append(subprocess.Popen(args, stdout=subprocess.DEVNULL))
    for p in procs:
        p.wait()
    for role in "ab":
        base = os.path.join(PROJ, "_shots", "pvp_%s_%s" % (tag, role))
        out = open(base + "_out.txt", encoding="utf-8", errors="replace").read()
        err = open(base + "_err.txt", encoding="utf-8", errors="replace").read()
        for ln in out.splitlines():
            if ln.startswith("[pvp]"):
                print(role, ln)
        n_err = len(re.findall(r"SCRIPT ERROR|^ERROR", out + "\n" + err, re.M))
        print("%s 报错行数 %d" % (role, n_err))
        if n_err:
            seen = set()
            for ln in (out + "\n" + err).splitlines():
                if ("SCRIPT ERROR" in ln or ln.startswith("ERROR")) and ln not in seen:
                    seen.add(ln)
                    print("   ", ln[:260])
                    if len(seen) >= 6:
                        break


main()
