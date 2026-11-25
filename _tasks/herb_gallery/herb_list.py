import csv, os, json, sys

ROOT = "H:/游戏资源/miniw_assets"
OUT = sys.argv[1]
rows = list(csv.DictReader(open(ROOT + "/目录清单.csv", encoding="utf-8-sig")))
byname = {}
for r in rows:
    byname.setdefault((r["分类"], r["资源名称"]), []).append(r)
pageA = ["人参", "灵芝", "庇佑雪莲", "星辉花", "星辉莲花", "龙血花", "龙血花（苗）", "龙爪草", "若兰", "星辰花", "风铃花", "雪滴花", "黄钟花", "冬温花",
         "光须茸草", "荧光草", "虚空彼岸花", "彼岸种子", "冰晶蕨幼苗", "冰晶蕨苗", "冰晶蕨", "冰晶喷菇幼苗", "有光冰晶喷菇", "无光冰晶喷菇", "幻觉菇", "音乐菇",
         "滑伞菇", "荧光小菇", "新荧光小菇", "食用小红菇", "薰衣草", "红色忘忧草", "红色忘忧草（苗）", "粉色忘忧草", "三叶草", "星芒麦(野外)", "神圣果实",
         "星辉浮藻", "荧光藻", "荷花"]
pageB = ["冰果作物", "丰硕冰果作物", "星辉三叶草作物", "星芒麦作物", "晶髓花簇", "荧菇作物", "彩虹草莓作物", "丰硕彩虹草莓", "烈焰瓜作物", "丰硕烈焰瓜作物",
         "水晶西瓜作物", "丰硕水晶西瓜作物", "星露莓丛", "星点草", "莲藕作物", "丰硕莲藕", "独葵作物", "萝卜王作物"]
items = ["星露莓", "星辉果", "星影果", "小星影果", "虚空风铃花", "虚空龙爪草", "虚空果实", "冰果种子", "荧菇菌种", "巨大荧菇菌种", "星光孢子种子", "神圣树种子",
         "神圣树叶", "草木灰", "木制花洒", "花洒", "铁制花洒", "钛制花洒", "稻草人", "星辉药剂", "冰灵精粹", "夜光菇笠"]


def glbs(cat, name):
    out = []
    for r in byname.get((cat, name), []):
        d = os.path.join(ROOT, r["目录"])
        for f in sorted(os.listdir(d)):
            if not f.endswith(".glb"):
                continue
            tag = ""
            if "非默认组" in f:
                tag = "·组" + f.rsplit("_", 1)[-1][:-4]
            out.append([name + tag, os.path.join(d, f).replace(os.sep, "/")])
    return out


res = {"A": [], "B": [], "I": []}
miss = []
for n in pageA:
    g = glbs("07_方块模型", n)
    res["A"] += g[:1]
    if not g:
        miss.append(n)
for n in pageB:
    g = glbs("07_方块模型", n)
    res["B"] += g
    if not g:
        miss.append(n)
for n in items:
    g = glbs("03_道具", n)
    res["I"] += g[:1]
    if not g:
        miss.append(n)
json.dump(res, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
open(OUT + ".log", "w", encoding="utf-8").write("%s missing %s\n" % ({k: len(v) for k, v in res.items()}, miss))
