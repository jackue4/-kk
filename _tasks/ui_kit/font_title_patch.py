"""题字字体（assets/fonts/SourceHanSerifSC-Heavy.subset.ttf）是 2026-11-19 按当时用到的字裁的，之后新写的题字（英雄名「苍鸿」的「苍」、
「择英雄」的「雄」……）不在里面，网页 / 手机上会落到正文字体上 —— 同一个名字里一个粗宋一个细黑。
这个脚本把「指定脚本的字符串里用到、题字字体里没有」的字从本机的思源宋体 Heavy 里裁出来，存成一个小的补字字体
assets/fonts/SourceHanSerifSC-Heavy.patch.ttf；ui_style.gd 把它挂成题字字体的第一个后备（题字 → 题字补字 → 正文 → 正文补字）。

用法（改了英雄名 / 技能名 / 英雄选择界面的题字之后、导出网页版之前跑一遍，之后要 --import）：
    python -I _tasks/ui_kit/font_title_patch.py            只核对，结果写到 _shots/font_title_patch.txt（UTF-8）
    python -I _tasks/ui_kit/font_title_patch.py --patch    核对并重做题字补字字体
要查的脚本写在 FILES 里（只查会用题字字体显示的那几个，免得把全游戏的字都裁一遍粗宋）。
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent.parent
FONTS = ROOT / "assets" / "fonts"
TITLE = FONTS / "SourceHanSerifSC-Heavy.subset.ttf"
PATCH = FONTS / "SourceHanSerifSC-Heavy.patch.ttf"
DONOR = Path("C:/Windows/Fonts/Source Han Serif SC Heavy (TrueType).ttf")
FILES = ["scripts/hero_defs.gd", "scripts/heroes/def_zhenyue.gd", "scripts/heroes/def_canghong.gd", "scripts/heroes/def_shuanghua.gd", "scripts/ex/hero_select_ui.gd", "scripts/ex/meta_ui.gd", "scripts/ex/meta_prep.gd",
         "scripts/ex/meta_shop.gd", "scripts/ex/meta_rank.gd", "scripts/ex/meta_kit.gd"]


def cmap(path):
    return set(TTFont(path).getBestCmap().keys()) if path.exists() else set()


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
    title = cmap(TITLE)
    used = set()
    for rel in FILES:
        used |= {c for c in lit_chars((ROOT / rel).read_text(encoding="utf-8")) if ord(c) >= 0x3400}      # 只要汉字：标点落到正文字体上本来就好
    need = sorted(c for c in used if ord(c) not in title)
    lines = ["题字字体 %d 字；%s 里用到汉字 %d 个，题字字体里没有的 %d 个：%s" % (len(title), " + ".join(FILES), len(used), len(need), "".join(need))]
    if "--patch" in sys.argv:
        if not DONOR.exists():
            lines.append("本机没有 %s，没法补" % DONOR)
        elif not need:
            lines.append("不缺字，不用补")
        else:
            donor = cmap(DONOR)
            miss = [c for c in need if ord(c) not in donor]
            opt = subset.Options()
            opt.layout_features = []
            opt.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
            opt.notdef_outline = True
            opt.glyph_names = False
            sub = subset.Subsetter(opt)
            f = TTFont(DONOR)
            sub.populate(unicodes=[ord(c) for c in need if ord(c) in donor])
            sub.subset(f)
            f.save(PATCH)
            lines.append("写了 %s（%d 字节，%d 字）%s" % (PATCH.name, PATCH.stat().st_size, len(cmap(PATCH)),
                                                    ("；思源宋体里也没有：" + "".join(miss)) if miss else ""))
    else:
        have = cmap(PATCH)
        left = [c for c in need if ord(c) not in have]
        lines.append("题字补字字体现有 %d 字；还缺：%s" % (len(have), "".join(left) if left else "无"))
    out = ROOT / "_shots" / "font_title_patch.txt"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("see", out)


main()
