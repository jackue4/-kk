"""网页 / 手机包里只有两款按用字裁剪过的字体（assets/fonts/），脚本里新写的字不在里面就会显示成方块。
这个脚本核对所有脚本字符串用到的字，缺的字从本机的思源黑体（C:/Windows/Fonts/SourceHanSansCN-Normal.ttf，2014 年那版是 Apache 2.0 授权）
里裁出来，存成一个很小的补字字体 assets/fonts/SourceHanSansCN-Normal.patch.ttf；ui_style.gd 把它挂成两款字体的后备。

用法（改了界面文字、导出网页版之前跑一遍）：
    python -I _tasks/ui_kit/font_check.py            只核对，结果写到 _shots/font_check.txt（UTF-8；控制台是 GBK，直接打印会乱码）
    python -I _tasks/ui_kit/font_check.py --patch    核对并重做补字字体（之后要 --import 一遍）
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent.parent
FONTS = ROOT / "assets" / "fonts"
BODY = FONTS / "NotoSansSC-Medium.subset.otf"
TITLE = FONTS / "SourceHanSerifSC-Heavy.subset.ttf"
PATCH = FONTS / "SourceHanSansCN-Normal.patch.ttf"
DONOR = Path("C:/Windows/Fonts/SourceHanSansCN-Normal.ttf")


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
    body, title = cmap(BODY), cmap(TITLE)
    used = {}
    for p in sorted((ROOT / "scripts").glob("*.gd")):
        for c in lit_chars(p.read_text(encoding="utf-8")):
            if ord(c) > 0x2000:
                used.setdefault(c, set()).add(p.name)
    # 题字字体缺的字会先落到正文字体上（标点基本都是这样），两边都没有的才需要补
    need = sorted(c for c in used if ord(c) not in body)
    if "--patch" in sys.argv and need:
        donor = cmap(DONOR)
        ok = [c for c in need if ord(c) in donor]
        opt = subset.Options()
        opt.layout_features = []
        opt.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]     # 留着版权和授权信息
        opt.notdef_outline = True
        f = TTFont(DONOR)
        sub = subset.Subsetter(opt)
        sub.populate(unicodes=[ord(c) for c in ok])
        sub.subset(f)
        f.save(PATCH)
    patch = cmap(PATCH)
    lines = ["正文字体 %d 字，题字字体 %d 字，补字字体 %d 字；脚本字符串里用到 %d 个非英文字符" % (len(body), len(title), len(patch), len(used))]
    lines.append("正文字体里没有的字（%d 个）：" % len(need))
    for c in need:
        lines.append("  %s U+%04X %s %s" % (c, ord(c), "已补" if ord(c) in patch else "【没补上】", ", ".join(sorted(used[c])[:4])))
    only_title = sorted(c for c in used if ord(c) not in title and ord(c) in body)
    lines.append("题字字体里没有、落到正文字体上的字（%d 个）：%s" % (len(only_title), "".join(only_title)))
    still = [c for c in need if ord(c) not in patch]
    lines.append("仍然会显示成方块的字：%s" % ("".join(still) if still else "无"))
    out = ROOT / "_shots" / "font_check.txt"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("need %d, patched %d, still missing %d -> %s" % (len(need), len([c for c in need if ord(c) in patch]), len(still), out.name))


main()
