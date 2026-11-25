"""搜打撤 PvP 重构（D 经济）：从 DarkArea 数据表（_tasks/extraction_refactor/darkarea_data/*.json）生成 scripts/ex/ex_data.gd 里的常量表。
重跑：python -I _tasks/extraction_refactor/tools/gen_ex_data.py
只改写 ex_data.gd 里 「# ==== GENERATED BEGIN ====」 和 「# ==== GENERATED END ====」 两行之间的部分（手写的逻辑在外面，不动）。
要改起名 / 类别就改下面的 SELL_NAMES / UNIQUE / MAT_NAMES，再重跑。

生成的表：
  SELL      售卖物 93 件（DarkArea Trader Type=1 的 94 件去掉身份牌 → 命牌另算 kind=tag）+ 表外 5 件 BOSS 专属（沙虫巨牙等，DarkArea 卖不掉，本作按描述价能卖）
  UNIQUE    独特兵刃（近战武器 9 件 + 表外 7 件：越王勾剑、毁灭射线 …）→ 同档兵刃数值，名字 / 家族另起
  MATS      炼器材料（DarkArea 枪械升级 / 赋能材料 14 种 + 永恒晶石 6 种 + 天启配方 11 种）：本轮没有兵刃升级，只能卖给商人
  WEAPON_SHOP / WEAPON_VALUE  兵刃各档的坊市价（DarkArea 同档枪族商店价的中位数）和回收价（同档 Trader 价中位数）
  ARMOR_SHOP / ARMOR_VALUE    法衣 4 部位 × 7 档（照 DarkArea 护甲）
  CHIP_BASE / CHIP_DUR        法宝 5 档的基础价 / 耐久上限（照扩展芯片）
  MED / THROW_DA              药 8 种、符 4 种的 DarkArea 原始数（治疗量在 ex_data.gd 里按 ×0.5 折）
  POOLS     53 个物品池（换成本作物品 id；枪池 → "@w<品质>" = 同档随机家族兵刃）
  TABLES    21 张箱子表 + 25 张怪 / 首领掉落表（抽数、权重、组照搬；组 = 池名或内联 id 列表）
  WAREHOUSE 仓库 14 级；RANK_NEED 段位 13 档的累计带出价值
  DA_BOSSES 20 个首领的 DarkArea 原始血量 / 重生 / 掉落表
"""
import json
import sys
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / "darkarea_data"
TARGET = HERE.parent.parent.parent / "scripts" / "ex" / "ex_data.gd"
BEGIN = "# ==== GENERATED BEGIN ===="
END = "# ==== GENERATED END ===="

# ---------- 售卖物改名：DarkArea 名 → (本作名, 图标类别) ----------
# 图标类别 = assets/ui/icon_ex_<cat>.png（生图出的 12 张）或老图标（herb / mat / tool / pouch）
SELL_NAMES = {
    # 白（600–1600）
    "杯子": ("粗陶碗", "bronze"), "马桶塞": ("竹刷子", "tool"), "文件夹": ("旧书匣", "scroll"), "蜡烛": ("残烛", "tool"),
    "口哨": ("骨哨", "bone"), "卷纸": ("草纸卷", "scroll"), "毛巾": ("粗布巾", "pouch"), "扑克牌": ("竹叶牌", "scroll"),
    "沐浴露": ("皂角露", "herb"), "空喷气罐": ("空葫芦", "pouch"),
    # 绿（2000–6000）
    "手铐": ("玄铁镣", "mat"), "雨伞": ("油纸伞", "tool"), "盆栽": ("灵草盆景", "herb"), "哑铃": ("石锁", "mat"),
    "生存手册": ("游方手札", "scroll"), "电动小风扇": ("机关小扇", "tool"), "罐头": ("腌肉坛", "pouch"), "订书机": ("铜钉匣", "bronze"),
    "玩具熊": ("布老虎", "pouch"), "玩具猫": ("木雕灵猫", "mat"),
    # 蓝（1万–2.5万）
    "台灯": ("琉璃灯", "crystal"), "灭火器": ("避火铜瓶", "bronze"), "人体工学拐杖": ("青藤拐", "herb"), "手电筒": ("夜明火折", "tool"),
    "收音机": ("传音海螺", "bone"), "棒球手套": ("鹿皮护手", "pouch"), "售卖物-防毒面具": ("辟毒面罩", "jade"),
    "平底锅": ("铸铁丹锅", "bronze"), "柴油桶": ("火油坛", "pouch"), "摄像头": ("留影石", "crystal"), "售卖物-银簪": ("银簪", "gold"),
    "RGB机械键盘": ("机关算盘", "mat"), "售卖物-银元宝": ("银元宝", "gold"),
    # 紫（3万–14万）
    "耳机": ("听风耳坠", "jade"), "售卖物-蝴蝶结": ("彩蝶结", "pouch"), "售卖物-公主裙": ("云锦罗裙", "pouch"),
    "售卖物-食人花苞": ("噬人花苞", "herb"), "售卖物-荆棘花": ("血棘花", "herb"), "售卖物-僵尸拳套": ("尸傀拳套", "bone"),
    "售卖物-废弃药芯": ("残丹药芯", "crystal"), "售卖物-机械臂": ("机关臂", "mat"), "售卖物-黄金狗便": ("黄金狗宝", "gold"),
    "电锯": ("锯齿飞轮", "mat"), "破旧手机": ("残破传讯符", "jade"), "扫地机器人": ("扫尘傀儡", "mat"), "电路板": ("阵纹铜板", "bronze"),
    "芯片": ("阵眼灵核", "crystal"), "大天才手表": ("铜壶滴漏", "bronze"), "显示屏": ("水镜屏", "crystal"), "照相机": ("留影玉璧", "jade"),
    "金元宝": ("金元宝", "gold"), "平板电脑": ("上古玉简", "scroll"), "黄金面具": ("黄金面具", "gold"),
    # 橙（15万–80万）
    "钻石戒指": ("灵钻戒", "crystal"), "限量吉他": ("焦尾古琴", "mat"), "稀有雕塑": ("玉雕麒麟", "jade"),
    "售卖物-白毛": ("尸王白毫", "bone"), "售卖物-眼罩": ("守灵眼纱", "pouch"), "售卖物-眼镜": ("天工琉璃镜", "crystal"),
    "售卖物-鞭子": ("雷纹铁鞭", "mat"), "华丽宝石": ("七宝琉璃", "crystal"), "售卖物-月环": ("铁穹月环", "gold"),
    "售卖物-月刺": ("铁穹月刺", "bone"), "售卖物-烬棠花": ("绛罗烬花", "herb"), "黄金权杖": ("金玉如意", "gold"),
    "大金条": ("赤金锭", "gold"), "金樽": ("金樽", "gold"), "金蟾": ("招财金蟾", "gold"), "黄金佛像": ("鎏金天尊像", "gold"),
    "献王珠": ("献王珠", "pearl"),
    # 红（88.9万–350万）
    "售卖物-九彩玲珑": ("九彩玲珑", "crystal"), "售卖物-踏雪玉马": ("踏雪玉马", "jade"), "售卖物-万彩灵芯": ("万彩灵芯", "crystal"),
    "售卖物-博士身份牌": ("天工师玉牒", "jade"), "售卖物-凌幽的伞": ("凌幽罗伞", "pouch"), "售卖物-烬棠发簪": ("绛罗凤簪", "gold"),
    "售卖物-月寒发簪": ("月寒玉簪", "jade"), "售卖物-洛神佩": ("洛神佩", "jade"), "蛇眉铜鱼": ("蛇眉铜鱼", "bronze"),
    "售卖物-黄金蛋糕": ("金丝寿桃", "gold"), "售卖物-纪念奖杯": ("鎏金宝鼎", "bronze"), "售卖物-星光坠梦": ("星辰坠", "pearl"),
    "售卖物-碎星蓝钻": ("碎星蓝晶", "crystal"), "四羊方尊": ("四羊方尊", "bronze"), "双鱼玉佩": ("双鱼玉佩", "jade"),
    "九龙玉杯": ("九龙玉杯", "jade"), "玉枕": ("游仙玉枕", "jade"),
    # 彩（888.9万–2000万）
    "售卖物-海洋之星": ("沧海明珠", "pearl"), "售卖物-寒月冰晶": ("寒月冰魄", "crystal"), "售卖物-万象琉璃": ("万象琉璃", "crystal"),
    "售卖物-沧月星冕": ("沧月星冕", "gold"), "金缕玉衣": ("金缕玉衣", "jade"), "龙骨天书": ("龙骨天书", "scroll"),
    # 表外（BOSS 专属，DarkArea 不在 Trader 表）
    "售卖物-沙虫巨牙": ("沙渊虫牙", "bone"), "售卖物-沙虫钳角": ("沙渊钳角", "bone"), "售卖物-镇符幽帽": ("镇符幽冠", "pouch"),
    "售卖物-幽冥嫁衣": ("幽冥嫁衣", "pouch"), "售卖物-鬼将盔甲": ("鬼将残甲", "bone"),
}
DOG_TAG = "身份牌"
# DarkArea 商场 BOSS 表里写错的两个 id（da_tables.md 第 7 节第 2 条）→ 正确的蝴蝶结 / 公主裙
FIX_IDS = {"r2_7670376222706107602_142803": "r2_7670376222706107602_143803",
           "r2_7665607138265269458_26765": "r2_7665607138265269458_27765"}

# ---------- 独特兵刃：DarkArea 名 → (本作 id, 名, 家族) ----------
UNIQUE = {
    "小丑叉子": ("w_u_sancha", "三叉戟", "panlong"), "钩锁": ("w_u_feizhua", "飞爪钩镰", "zhanma"),
    "捕猎网": ("w_u_tianluo", "天罗印", "zhenyue"), "指挥棒": ("w_u_dashen", "打神鞭", "liuguang"),
    "手术刀": ("w_u_liuye", "柳叶刀", "liuguang"), "双头狗项圈": ("w_u_shuangquan", "双犬链锤", "pojun"),
    "棒球棍": ("w_u_langya", "狼牙棒", "pojun"), "锤子": ("w_u_kaishan", "开山锤", "pojun"),
    "方天画戟": ("w_u_fangtian", "方天画戟", "panlong"), "幽灯法杖": ("w_u_youdeng", "幽灯法杖", "zhenyue"),
    "永恒-越王勾剑": ("w_u_goujian", "越王勾剑", "qingfeng"), "神话-黄金匕首": ("w_u_jindao", "金錾短剑", "liuguang"),
    "神话-黄金战锤": ("w_u_jinchui", "鎏金战锤", "pojun"), "永恒-毁灭射线": ("w_u_taiyi", "太乙神雷印", "zhenyue"),
    "永恒-粒子炮": ("w_u_jiuxiao", "九霄雷锤", "pojun"), "永恒加特林": ("w_u_bahuang", "八荒破军锤", "pojun"),
    "永恒-喷火器": ("w_u_fentian", "焚天斩马刀", "zhanma"),
}
# 特殊枪械池 → 独特兵刃
UNIQUE_POOLS = {"DarkAreaBoxWeapon.Gatling": "永恒加特林", "DarkAreaBoxWeapon.lizipao": "永恒-粒子炮",
                "DarkAreaBoxWeapon.huimie": "永恒-毁灭射线", "DarkAreaBoxWeapon.flamethrower": "永恒-喷火器",
                "DarkAreaBoxWeapon.goujianofyue": "永恒-越王勾剑", "DarkAreaBoxWeapon.goldendagger": "神话-黄金匕首",
                "DarkAreaBoxWeapon.goldenwarhammer": "神话-黄金战锤"}

# ---------- 炼器材料 ----------
MAT_UP = ["", "粗铁砂", "精钢砂", "寒铁砂", "玄铁砂", "陨星砂", "赤金砂", "混元砂"]        # 枪械升级材料
MAT_EN = ["", "粗灵髓", "清灵髓", "碧灵髓", "紫灵髓", "赤灵髓", "金灵髓", "七彩灵髓"]      # 枪械赋能材料
MAT_RARE = {"永恒晶石": "太初晶石", "雷神之力": "九霄雷髓", "黄金神石": "黄金神石", "冰魄玄晶": "冰魄玄晶",
            "熔岩之心": "地火熔心", "摇滚之星": "天籁星核"}
RECIPE_PART = {"冲锋枪": "连弩", "机枪": "雷锤", "手枪": "短剑", "步枪": "长枪", "狙击枪": "神弓", "喷火器": "火轮",
               "霰弹枪": "重锤", "头盔": "道冠", "护腿": "护腿", "战靴": "云履", "胸甲": "法衣"}

# ---------- 消耗品：DarkArea id → 本作 id ----------
MED_IDS = {"r2_7402573647317042386_30226": "med_zhixue", "r2_7402573651612009682_30230": "med_lingguo",
           "r2_7402573651612009682_30234": "med_xiao", "r2_7402573647317042386_30242": "med_jinchuang",
           "r2_7402573651612009682_30238": "med_zhong", "r2_7402573647317042386_30246": "med_jiuzhuan",
           "r2_7696070297618744530_119731": "med_da", "r2_7696071985540891858_120602": "med_xuming"}
REVIVE_DA = "r2_7441524878523254602_39621"
THROW_IDS = {"r2_7383168188066910958_11880": "thr_lei", "r2_7591798198297953490_79980": "thr_tianlei",
             "r2_7402811614275044562_42258": "thr_yan", "r2_7683001833123480786_19550": "thr_huo"}

QNAME = {"普通": 1, "精致": 2, "精良": 2, "卓越": 3, "传奇": 4, "史诗": 5, "神话": 6, "永恒": 7, "天启": 8}
ARMOR_SLOT = {"头盔": 0, "胸甲": 1, "护腿": 2, "靴子": 3}

RANK_NAMES = ["未入流", "炼气三阶", "炼气二阶", "炼气一阶", "筑基三阶", "筑基二阶", "筑基一阶", "结丹三阶", "结丹二阶", "结丹一阶",
              "元婴三阶", "元婴二阶", "元婴一阶", "化神"]


def load(name):
    return json.loads((DATA / f"{name}.json").read_text(encoding="utf-8"))


def gd(v, ind=0):
    """Python 值 → GDScript 字面量（字典 / 数组展开成多行时按 ind 缩进）"""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = repr(v)
        return s if ("." in s or "e" in s) else s + ".0"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{gd(k)}: {gd(x)}" for k, x in v.items()) + "}"
    if v is None:
        return "null"
    raise TypeError(type(v))


def gd_dict_lines(name, d, comment=""):
    out = []
    if comment:
        out.append("## " + comment)
    out.append(f"const {name} := {{")
    for k, v in d.items():
        out.append(f"\t{gd(k)}: {gd(v)},")
    out.append("}")
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sell = load("sellables")
    gear = load("gear")
    cons = load("consumables")
    loot = load("loot_tables")
    econ = load("economy")

    # --- 售卖物 ---
    da2id = {}          # DarkArea id → 本作 id
    SELL = {}
    n = 0
    missing = []
    for it in sell["items"]:
        if it["name"] == DOG_TAG:
            da2id[it["id"]] = "tag"
            continue
        n += 1
        sid = f"s{n:02d}"
        if it["name"] not in SELL_NAMES:
            missing.append(it["name"])
            continue
        nm, cat = SELL_NAMES[it["name"]]
        tags = [t for t in it.get("tags", []) if t in ("古墓专属", "BOSS专属", "箱子专属")]
        if any("无掉落来源" in t for t in it.get("tags", [])):
            tags.append("无来源")
        SELL[sid] = {"name": nm, "da": it["name"], "q": int(it["quality"]), "v": int(it["sell_price"]), "cat": cat,
                     "tag": tags[0] if tags else ""}
        da2id[it["id"]] = sid
    x = 0
    for it in sell["loot_sellables_not_in_trader"]:
        if not it.get("prefab_exists") or not it.get("name") or not it["name"].startswith("售卖物-"):
            continue
        x += 1
        sid = f"sx{x}"
        nm, cat = SELL_NAMES[it["name"]]
        SELL[sid] = {"name": nm, "da": it["name"], "q": int(it["quality"]), "v": int(it["desc_price"]), "cat": cat, "tag": "BOSS专属"}
        da2id[it["id"]] = sid
    for bad, good in FIX_IDS.items():
        da2id[bad] = da2id[good]
    if missing:
        raise SystemExit("售卖物缺名字：" + "、".join(missing))
    names = [v["name"] for v in SELL.values()]
    dup = {nm for nm in names if names.count(nm) > 1}
    if dup:
        raise SystemExit("售卖物重名：" + "、".join(dup))

    # --- 兵刃价 ---
    shop_by_q, val_by_q = {}, {}
    for g in gear["guns"]:
        q = int(g["quality"])
        val_by_q.setdefault(q, []).append(int(g["sell_price"]))
        for s in g.get("shop") or []:
            shop_by_q.setdefault(q, []).append(int(s["buy_price"]))
    WEAPON_SHOP = [0] + [int(statistics.median(shop_by_q[q])) if q in shop_by_q else 0 for q in range(1, 8)]
    WEAPON_VALUE = [0] + [int(statistics.median(val_by_q[q])) for q in range(1, 8)]

    # --- 独特兵刃 ---
    UNI = {}
    by_name = {}
    for g in gear["melee_weapons"] + gear["extra_gear_not_in_trader"] + gear["guns"]:
        if g.get("name"):
            by_name.setdefault(g["name"], g)
    for da_name, (uid, nm, fam) in UNIQUE.items():
        g = by_name.get(da_name)
        q = int(g["quality"]) if g else 7
        sp = g.get("sell_price") if g else None
        v = int(sp) if isinstance(sp, (int, float)) and sp else WEAPON_VALUE[q]
        UNI[uid] = {"name": nm, "da": da_name, "q": q, "v": v, "fam": fam}
        if g:
            da2id[g["id"]] = uid

    # --- 法衣 ---
    ARMOR_SHOP = [[0] * 8 for _ in range(4)]
    ARMOR_VALUE = [[0] * 8 for _ in range(4)]
    for a in gear["armor"]:
        q = int(a["quality"])
        s = ARMOR_SLOT[a["stats"]["slot"]]
        ARMOR_VALUE[s][q] = int(a["sell_price"])
        for sh in a.get("shop") or []:
            ARMOR_SHOP[s][q] = int(sh["buy_price"])
        da2id[a["id"]] = f"a_{s}_{q}"

    # --- 法宝（扩展芯片）---
    CHIP_BASE, CHIP_DUR = [0] * 9, [0] * 9
    for c in gear["extension_chips"]:
        q = int(c["quality"])
        CHIP_BASE[q] = int(c["base_price"])
        CHIP_DUR[q] = int(c["max_durability"])

    # --- 药 / 符 ---
    MED, THROW_DA = {}, {}
    for it in cons["items"]:
        if it["id"] in MED_IDS:
            f = it.get("food") or {}
            sh = (it.get("shop") or [{}])[0]
            MED[MED_IDS[it["id"]]] = {"da": it["name"], "q": int(it["quality"]), "v": int(it["sell_price"] or 0),
                                      "price": int(sh.get("buy_price", 0)) // max(int(sh.get("num", 1)), 1),
                                      "use_t": float(f.get("useTime", 0)), "da_heal": int(f.get("healAmount", 0)),
                                      "desc": it.get("effect_desc", "").split("\n")[1].strip() if it.get("effect_desc") else ""}
            da2id[it["id"]] = MED_IDS[it["id"]]
        elif it["id"] == REVIVE_DA:
            da2id[it["id"]] = "revive"
        elif it["id"] in THROW_IDS:
            sh = (it.get("shop") or [{}])[0]
            pj = it.get("projectile") or {}
            sp = it.get("sell_price")
            THROW_DA[THROW_IDS[it["id"]]] = {"da": it["name"], "q": int(it["quality"]), "v": int(sp) if isinstance(sp, (int, float)) else 0,
                                             "price": int(sh.get("buy_price", 0)) // max(int(sh.get("num", 1)), 1),
                                             "da_dmg": int(pj.get("attackValue", 0) or 0), "r": float(pj.get("explodeRange", 0) or 0)}
            da2id[it["id"]] = THROW_IDS[it["id"]]

    # --- 炼器材料 ---
    MATS = {}
    for m in cons["materials"]:
        q = int(m["quality"])
        up = "升级" in m["name"]
        mid = f"m_{'up' if up else 'en'}_{q}"
        MATS[mid] = {"name": (MAT_UP if up else MAT_EN)[q], "da": m["name"], "q": q, "v": int(m["sell_price"])}
        da2id[m["id"]] = mid
    k = 0
    for pool in ("ItemList.color1", "ItemList.tianqiwuqi1", "ItemList.tianqiwuqi2", "ItemList.tianqizhuangbei1", "ItemList.tianqizhuangbei2"):
        for it in loot["pools"][pool]["items"]:
            k += 1
            mid = f"m_x{k}"
            if pool == "ItemList.color1":
                nm, v = MAT_RARE[it["name"]], 1600
            else:
                part = it["name"].replace("天启-", "").replace("配方", "")
                nm, v = "天启图谱·" + RECIPE_PART.get(part, part), 0
            MATS[mid] = {"name": nm, "da": it["name"], "q": int(it["quality"]), "v": v}
            da2id[it["id"]] = mid

    # --- 物品池 ---
    POOLS = {}
    for pname, p in loot["pools"].items():
        if pname in UNIQUE_POOLS:
            POOLS[pname] = [UNIQUE[UNIQUE_POOLS[pname]][0]]
        elif pname.startswith("DarkAreaBoxWeapon."):
            qs = sorted({int(i["quality"]) for i in p["items"]})
            assert len(qs) == 1, pname
            POOLS[pname] = [f"@w{qs[0]}"]
        else:
            ids = []
            for it in p["items"]:
                iid = da2id.get(it["id"])
                if iid is None:
                    raise SystemExit(f"池 {pname} 里的 {it['name']} ({it['id']}) 没有对应")
                ids.append(iid)
            POOLS[pname] = ids

    # --- 掉落表 ---
    TABLES = {}
    for sec in ("boxes", "monster_and_boss_drops"):
        for tname, t in loot[sec].items():
            groups = []
            for e in t["entries"]:
                if e.get("pool"):
                    groups.append([int(e["weight"]), e["pool"]])
                else:
                    ids = []
                    for iid in e["items"]:
                        mid = da2id.get(iid) or da2id.get(FIX_IDS.get(iid, ""))
                        if mid is None:
                            raise SystemExit(f"表 {tname} 的内联物品 {iid} 没有对应")
                        ids.append(mid)
                    groups.append([int(e["weight"]), ids])
            TABLES[tname] = {"draws": int(t["draws"]), "groups": groups}

    # --- 首领原始数 ---
    DA_BOSSES = {}
    for b in loot["bosses"]:
        hp = b.get("hp")
        if isinstance(hp, dict):
            hp = max(hp.values())
        DA_BOSSES[b["boss"]] = {"hp": int(hp or 0), "respawn": int(b.get("respawn_s") or b.get("summon_cooldown_s") or 0),
                                "table": b["drop_table"], "draws": TABLES[b["drop_table"]]["draws"]}

    # --- 仓库 / 段位 ---
    WAREHOUSE = []
    for lv in econ["warehouse"]["levels"]:
        c = lv.get("cost") or {}
        WAREHOUSE.append([int(lv["total_grids"]), int(c.get("num", 0)) if c.get("type") == 5 else 0,
                          int(c.get("num", 0)) if c.get("type") == 2 else 0])
    RANK_NEED = [int(r["need_extract_value"]) for r in econ["rank_by_extract_value"]["ranks"]]
    assert len(RANK_NEED) == len(RANK_NAMES)

    # --- 写出 ---
    L = [BEGIN, "## 下面这段由 _tasks/extraction_refactor/tools/gen_ex_data.py 从 darkarea_data/*.json 生成，别手改（改了重跑会被覆盖）。", ""]
    L += gd_dict_lines("SELL", SELL, "售卖物：id → {name 本作名, da DarkArea 原名, q 品质, v 回收价（灵石）, cat 图标类别, tag 古墓专属 / BOSS专属 / 箱子专属 / 无来源}")
    L.append("")
    L += gd_dict_lines("UNIQUE", UNI, "独特兵刃：id → {name, da, q, v 回收价, fam 外观家族}（数值按同档兵刃）")
    L.append("")
    L += gd_dict_lines("MATS", MATS, "炼器材料：id → {name, da, q, v}（本轮只能卖给商人；v = 0 的卖不掉）")
    L.append("")
    L.append("## 兵刃各档（下标 = 品质 1..7）：坊市价（DarkArea 同档枪商店价中位数，神话 / 永恒不卖 = 0）、回收价（同档 Trader 价中位数）")
    L.append(f"const WEAPON_SHOP := {gd(WEAPON_SHOP)}")
    L.append(f"const WEAPON_VALUE := {gd(WEAPON_VALUE)}")
    L.append("## 法衣 [部位 0 冠 / 1 衣 / 2 护腿 / 3 履][品质 1..7]：坊市价（神话 / 永恒不卖 = 0）、回收价（照 DarkArea 护甲）")
    L.append(f"const ARMOR_SHOP := {gd(ARMOR_SHOP)}")
    L.append(f"const ARMOR_VALUE := {gd(ARMOR_VALUE)}")
    L.append("## 法宝各档（下标 = 品质 4..8）：基础价（回收价 = 基础价 × 耐久比例，坊市价 = 基础价 × 2）、耐久上限（照扩展芯片）")
    L.append(f"const CHIP_BASE := {gd(CHIP_BASE)}")
    L.append(f"const CHIP_DUR := {gd(CHIP_DUR)}")
    L.append("")
    L += gd_dict_lines("MED_DA", MED, "药的 DarkArea 原始数：id → {da, q, v 回收价, price 坊市单价（10 个一组的价 ÷ 10）, use_t 读条秒, da_heal 立即回血, desc}")
    L.append("")
    L += gd_dict_lines("THROW_DA", THROW_DA, "符的 DarkArea 原始数：id → {da, q, v 回收价（0 = 卖不掉）, price 坊市单价, da_dmg 原伤害, r 爆炸半径}")
    L.append("")
    L += gd_dict_lines("POOLS", POOLS, "物品池：池名 → 本作物品 id 列表（组内等概率）；\"@w5\" = 史诗档随机家族的兵刃")
    L.append("")
    L.append("## 掉落表：表名 → {draws 抽数, groups [[权重, 池名 或 内联 id 列表], ...]}（每抽按权重选组、组内等概率、有放回）")
    L.append("const TABLES := {")
    for tname, t in TABLES.items():
        L.append(f"\t{gd(tname)}: {{\"draws\": {t['draws']}, \"groups\": [")
        for g in t["groups"]:
            L.append(f"\t\t{gd(g)},")
        L.append("\t]},")
    L.append("}")
    L.append("")
    L += gd_dict_lines("DA_BOSSES", DA_BOSSES, "DarkArea 首领原始数：名 → {hp, respawn 重生 / 召唤冷却秒, table 掉落表, draws}")
    L.append("")
    L.append("## 仓库 14 级（下标 = 等级 − 1）：[总格数, 灵石价, 仓库凭证张数]")
    L.append(f"const WAREHOUSE := {gd(WAREHOUSE)}")
    L.append("## 段位：名字（本作改名）和累计带出价值门槛（下标 0 = 未入流）")
    L.append(f"const RANK_NAMES := {gd(RANK_NAMES)}")
    L.append(f"const RANK_NEED := {gd(RANK_NEED)}")
    L.append(END)
    block = "\n".join(L)

    src = TARGET.read_text(encoding="utf-8")
    pat = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.S)
    if not pat.search(src):
        raise SystemExit(f"{TARGET} 里找不到 {BEGIN} / {END}")
    src = pat.sub(lambda _m: block, src)
    TARGET.write_text(src, encoding="utf-8", newline="\n")
    print(f"写入 {TARGET}：售卖物 {len(SELL)}，独特兵刃 {len(UNI)}，材料 {len(MATS)}，池 {len(POOLS)}，表 {len(TABLES)}，首领 {len(DA_BOSSES)}")
    print("兵刃坊市价", WEAPON_SHOP, "回收价", WEAPON_VALUE)


if __name__ == "__main__":
    main()
