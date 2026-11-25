"""网页 / 手机版的毛笔字体：从开源的 Ma Shan Zheng（马善政毛笔楷书，SIL OFL 1.1，Copyright 2018 The MaShanZheng Project Authors，
https://github.com/googlefonts/mashanzheng；原文件 2026-11-24 从 Google Fonts 官方仓库 ofl/mashanzheng/ 下载，放在
_tasks/ui_fonts/donor_mashanzheng/，那个目录有 .gdignore、不进包）里，按游戏脚本字符串用到的字裁一份随包带上。

2026-11-24 用户：「所有的文字太素了，能不能来点风格化的字体，比如毛笔字这种效果」。桌面版用的是本机自带的华文新魏（系统字体，不能分发），
网页 / 手机上原来正文是黑体（Noto Sans）、题字是粗宋（思源宋体 Heavy）—— 这份裁出来的字体挂在它们前面（ui_style.gd 的 kai() / brush()），
它没有的字（它只有 GB2312 的 6763 个汉字，「·」「→」这类符号也没有）照旧落到 Noto / 补字字体上。

用法（改了界面文字、导出网页版之前跑一遍，之后要 --import）：
    python -I _tasks/ui_kit/font_brush_subset.py            只核对，结果写到 _shots/font_brush_subset.txt（UTF-8）
    python -I _tasks/ui_kit/font_brush_subset.py --write    核对并重做 assets/fonts/MaShanZheng-Regular.subset.ttf
    python -I _tasks/ui_kit/font_brush_subset.py --out <路径>   裁到别处（先看效果、不动 assets/）
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent.parent
DONOR = ROOT / "_tasks" / "ui_fonts" / "donor_mashanzheng" / "MaShanZheng-Regular.ttf"
OUT = ROOT / "assets" / "fonts" / "MaShanZheng-Regular.subset.ttf"
## 拉丁字母 / 数字 / 半角符号不从这款字体里取：它的数字是手写体（1 像 l、7 像 1），价钱、战力、格数这些要一眼认得清，
## 留给后备的 Noto Sans；这款只管汉字和全角标点
ASCII = []
EXTRA = "，。：；、！？（）「」『』《》〈〉【】—…％＋－×÷／～·"          # 常用标点（有就带上）


def lit_chars(text):
    """脚本里字符串字面量用到的字（注释不算）"""
    out = set()
    for line in text.splitlines():
        q = None
        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            if q is not None:
                if ch == "\\":
                    i += 2
                    continue
                if ch == q:
                    q = None
                else:
                    out.add(ch)
            elif ch == '"' or ch == "'":
                q = ch
            elif ch == "#":
                break
            i += 1
    return out


def main():
    donor = set(TTFont(DONOR).getBestCmap().keys())
    used = set(ASCII) | set(EXTRA)
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        used |= lit_chars(p.read_text(encoding="utf-8"))
    used = {c for c in used if ord(c) >= 0x2E80}      # 只要汉字和全角标点
    have = sorted(c for c in used if ord(c) in donor)
    miss = sorted(c for c in used if ord(c) not in donor)
    han_miss = [c for c in miss if 0x3400 <= ord(c) <= 0x9FFF]
    lines = ["脚本字符串里用到 %d 个字符；Ma Shan Zheng 里有 %d 个，没有的 %d 个（其中汉字 %d 个，会落到 Noto / 补字字体上）" % (
        len(used), len(have), len(miss), len(han_miss)),
        "没有的汉字：" + "".join(han_miss), "没有的其它字符：" + "".join(c for c in miss if c not in han_miss)]
    out = None
    if "--write" in sys.argv:
        out = OUT
    elif "--out" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--out") + 1])
    if out is not None:
        opt = subset.Options()
        opt.layout_features = ["kern"]
        opt.name_IDs = [0, 1, 2, 3, 4, 5, 6, 7, 13, 14]      # 版权 / 许可那几条留着（OFL 要求）
        opt.notdef_outline = True
        opt.glyph_names = False
        opt.hinting = False
        sub = subset.Subsetter(opt)
        f = TTFont(DONOR)
        sub.populate(unicodes=[ord(c) for c in have])
        sub.subset(f)
        out.parent.mkdir(parents=True, exist_ok=True)
        f.save(out)
        lines.append("写了 %s（%d 字节，%d 个字符）" % (out, out.stat().st_size, len(TTFont(out).getBestCmap())))
    else:
        cur = set(TTFont(OUT).getBestCmap().keys()) if OUT.exists() else set()
        left = [c for c in have if ord(c) not in cur]
        lines.append("随包那份现有 %d 个字符；还没裁进去的：%s" % (len(cur), "".join(left) if left else "无"))
    rep = ROOT / "_shots" / "font_brush_subset.txt"
    rep.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("see", rep)


main()
