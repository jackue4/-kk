"""把 web_probe.py 收下来的日志按探针的段标记（scripts/hitch_probe.gd 打的 `[hp] <<< 段名` / `[hp] >>> 段名：…`）汇总：
每一段里现编了几个着色器程序（`[gl] link` 行数）、最长帧、长帧合计多花的时间；加 -v 再列出每段里现编的是哪种着色器。
「默认」那一列：宏里没有 DISABLE_LIGHTMAP 的程序 —— 引擎（Compatibility）给每个新着色器先把四个变体（着色 / 实例化 / 深度 / 深度实例化）
按默认特化各编一个，这个项目实际画的时候用的都是别的特化，所以它们是白编的，但时间照花。
用法：python hitch_report.py [-v] <日志文件> [<日志文件> …]
"""
import re, sys

# 每个着色器开头都有的宏，列出来没有信息量
BORING = {"USE_GLES_OVER_GL", "USE_RADIANCE_MAP", "M_PI", "M_TAU", "M_E", "MAX_GLOBAL_SHADER_UNIFORMS", "MAX_LIGHT_DATA_STRUCTS",
          "MAX_DIRECTIONAL_LIGHT_DATA_STRUCTS", "MAX_FORWARD_LIGHTS", "MAX_ROUGHNESS_LOD", "MAX_VIEWS", "BASE_PASS", "APPLY_TONEMAPPING",
          "USE_WEBGL", "HAS_DEPTH_TEXTURE", "USE_HIGHP_PRECISION"}


def sig_of(text: str) -> str:
    m = re.search(r"len=(\d+) defs=(.*?) \| (.*)$", text)
    if not m:
        return text.strip()
    defs = [d for d in m.group(2).split() if d not in BORING]
    blk = m.group(3)
    names = re.findall(r"\bm_\w+", blk)
    mat = ",".join(dict.fromkeys(names)) if names else ("无材质参数" if blk.startswith("no-ubo") else blk[:60])
    return "%s ｜ %s ｜ 长度 %s" % (" ".join(defs) or "（无特别的宏）", mat, m.group(1))


def report(path: str, verbose: bool) -> None:
    seg = None
    rows = []          # [段名, 现编个数, 结果行, [签名…], 其中默认特化的个数]
    loose = 0
    last = "开机之前"
    gaps = {}          # 两段之间漏出来的：上一段的名字 → 个数
    notes = []
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        body = line[9:] if len(line) > 9 and line[7:9] == "s " else line
        if body.startswith("[hp] <<< "):
            seg = [body[9:], 0, "", [], 0]
            rows.append(seg)
        elif body.startswith("[hp] >>> "):
            if seg is not None:
                seg[2] = body[9:].split("：", 1)[-1]
                last = seg[0]
            seg = None
        elif body.startswith("[gl] link #"):      # 不带「linked」那种计时行
            if seg is not None:
                seg[1] += 1
                seg[3].append(sig_of(body))
                seg[4] += 0 if "DISABLE_LIGHTMAP" in body else 1
            else:
                loose += 1
                gaps[last] = gaps.get(last, 0) + 1
        elif body.startswith(("[hp] ", "[warm]", "[meadow]", "[probe]")) or "SCRIPT ERROR" in body or body.startswith("<exception>"):
            notes.append(body)
    print("==== %s" % path)
    for n in notes:
        print("  " + n)
    print("  段外现编 %d 个：%s" % (loose, "；".join("「%s」之后 %d" % kv for kv in gaps.items()) or "无"))
    print("  %-34s %4s %4s  %s" % ("段", "现编", "默认", "帧"))
    for name, n, res, sigs, dflt in rows:
        print("  %-34s %4d %4d  %s" % (name, n, dflt, res))
        if verbose and sigs and not name.startswith(("开机", "进大世界")):
            cnt = {}
            for s in sigs:
                cnt[s] = cnt.get(s, 0) + 1
            for s, c in cnt.items():
                print("      ×%d  %s" % (c, s))


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "-v"]
    for p in args:
        report(p, "-v" in sys.argv)


main()
