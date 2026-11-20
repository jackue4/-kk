class_name Realm
extends RefCounted
## 境界数据表：飞剑数量、飞行方式、遁速、遁光丝线配色/样式、镜头效果强度。
## 所有数值集中在这里，方便调手感。

enum Mode { SWORD, WIND, LIGHT }  # 御剑 / 御器御风 / 自身遁光

## 字段说明：
## swords 飞剑数 | speed 遁速(m/s) | boost 疾遁倍率 | rise 起飞上升高度 | ceiling 升限(0=无)
## fx 镜头与速度感强度(0~1) | col_a 浅色（HUD/风粒子） col_b 境界主色（HUD）
## lines 遁光/剑光丝线颜色：第 0 条是主线，其余是绕主线的副线（总数 1~3 条）
## style 丝线样式 | width 主线宽度(米，很细) | life 丝线留存秒数 | motes 伴飞的微型剑影数量（点缀，≤4）
## blink 闪现距离(米) | blink_spd 闪现速度(m/s)：炼气/筑基人形冲刺留残影；结丹起化作光剑，距离统一、速度随境界提高
## atk_cd 出剑间隔 | range 索敌范围 | dmg 伤害 | chain 连斩次数
## mp 灵力上限（空战长按连发飞剑时消耗） | volley 空战长按每秒射出的飞剑数
## art 法相档位：0 炼气/筑基共用的低阶表现；1~6 对应结丹~大乘，每档的法术、飞剑阵型/出剑轨迹/剑光、连发队形都换一套（见 ARTS）
const LIST := [
	{
		"name": "炼气", "flight": "飞剑 · 飞行法器", "mode": Mode.SWORD, "swords": 3,
		"speed": 12.0, "boost": 1.3, "rise": 2.0, "ceiling": 25.0, "fx": 0.08,
		"col_a": Color(0.8, 0.92, 1.0), "col_b": Color(0.35, 0.6, 1.0),
		"lines": [Color(0.35, 0.62, 1.0)],
		"style": 0, "width": 0.07, "life": 0.3, "motes": 0, "blink": 6.0, "blink_spd": 40.0,
		"atk_cd": 0.55, "range": 14.0, "dmg": 8.0, "chain": 0, "mp": 60.0, "volley": 6.0, "art": 0,
	},
	{
		"name": "筑基", "flight": "御器飞行 · 腾空御风", "mode": Mode.WIND, "swords": 5,
		"speed": 20.0, "boost": 1.35, "rise": 3.0, "ceiling": 80.0, "fx": 0.16,
		"col_a": Color(0.85, 1.0, 0.9), "col_b": Color(0.3, 0.9, 0.6),
		"lines": [Color(0.28, 0.9, 0.6)],
		"style": 0, "width": 0.08, "life": 0.32, "motes": 0, "blink": 6.0, "blink_spd": 40.0,
		"atk_cd": 0.42, "range": 17.0, "dmg": 12.0, "chain": 0, "mp": 80.0, "volley": 8.0, "art": 0,
	},
	{
		"name": "结丹", "flight": "自身遁光 · 法宝飞行", "mode": Mode.LIGHT, "swords": 7,
		"speed": 45.0, "boost": 1.5, "rise": 7.0, "ceiling": 0.0, "fx": 0.35,
		"col_a": Color(0.7, 1.0, 1.0), "col_b": Color(0.1, 0.7, 1.0),
		"lines": [Color(0.1, 0.72, 1.0)],
		"style": 0, "width": 0.11, "life": 0.38, "motes": 2, "blink": 8.0, "blink_spd": 60.0,
		"atk_cd": 0.32, "range": 21.0, "dmg": 18.0, "chain": 0, "mp": 100.0, "volley": 12.0, "art": 1,
	},
	{
		"name": "元婴", "flight": "遁光 · 高级遁术 · 瞬移", "mode": Mode.LIGHT, "swords": 9,
		"speed": 65.0, "boost": 1.5, "rise": 9.0, "ceiling": 0.0, "fx": 0.5,
		"col_a": Color(0.92, 0.8, 1.0), "col_b": Color(0.55, 0.2, 1.0),
		"lines": [Color(0.6, 0.26, 1.0), Color(0.86, 0.5, 1.0)],
		"style": 2, "width": 0.12, "life": 0.4, "motes": 2, "blink": 8.0, "blink_spd": 70.0,
		"atk_cd": 0.25, "range": 25.0, "dmg": 26.0, "chain": 1, "mp": 130.0, "volley": 24.0, "art": 2,
	},
	{
		"name": "化神", "flight": "遁光 · 借天地元气飞遁", "mode": Mode.LIGHT, "swords": 12,
		"speed": 90.0, "boost": 1.5, "rise": 11.0, "ceiling": 0.0, "fx": 0.62,
		"col_a": Color(1.0, 0.96, 0.75), "col_b": Color(1.0, 0.6, 0.1),
		"lines": [Color(1.0, 0.6, 0.1), Color(1.0, 0.84, 0.3), Color(1.0, 0.36, 0.1)],
		"style": 1, "width": 0.13, "life": 0.42, "motes": 3, "blink": 8.0, "blink_spd": 80.0,
		"atk_cd": 0.19, "range": 29.0, "dmg": 38.0, "chain": 1, "mp": 160.0, "volley": 40.0, "art": 3,
	},
	{
		"name": "炼虚", "flight": "遁光 · 五行及特殊遁术", "mode": Mode.LIGHT, "swords": 15,
		"speed": 120.0, "boost": 1.5, "rise": 13.0, "ceiling": 0.0, "fx": 0.74,
		"col_a": Color(1.0, 1.0, 1.0), "col_b": Color(0.4, 1.0, 0.6),
		"lines": [Color(0.3, 1.0, 0.55), Color(1.0, 0.86, 0.4), Color(0.3, 0.6, 1.0)],
		"style": 3, "width": 0.14, "life": 0.45, "motes": 3, "blink": 8.0, "blink_spd": 90.0,
		"atk_cd": 0.15, "range": 33.0, "dmg": 52.0, "chain": 2, "mp": 200.0, "volley": 60.0, "art": 4,
	},
	{
		"name": "合体", "flight": "高速遁光 · 部分空间神通", "mode": Mode.LIGHT, "swords": 18,
		"speed": 160.0, "boost": 1.5, "rise": 15.0, "ceiling": 0.0, "fx": 0.87,
		"col_a": Color(1.0, 0.88, 0.65), "col_b": Color(1.0, 0.15, 0.2),
		"lines": [Color(1.0, 0.16, 0.22), Color(1.0, 0.55, 0.3), Color(0.8, 0.1, 0.35)],
		"style": 5, "width": 0.15, "life": 0.45, "motes": 4, "blink": 8.0, "blink_spd": 100.0,
		"atk_cd": 0.11, "range": 38.0, "dmg": 75.0, "chain": 2, "mp": 240.0, "volley": 80.0, "art": 5,
	},
	{
		"name": "大乘", "flight": "高速遁光 · 空间移动神通", "mode": Mode.LIGHT, "swords": 24,
		"speed": 210.0, "boost": 1.5, "rise": 18.0, "ceiling": 0.0, "fx": 1.0,
		"col_a": Color(1.0, 1.0, 1.0), "col_b": Color(0.75, 0.85, 1.0),
		"lines": [Color(0.5, 0.78, 1.0), Color(1.0, 0.5, 0.8), Color(1.0, 0.85, 0.4)],
		"style": 4, "width": 0.16, "life": 0.5, "motes": 4, "blink": 8.0, "blink_spd": 110.0,
		"atk_cd": 0.08, "range": 45.0, "dmg": 110.0, "chain": 3, "mp": 300.0, "volley": 100.0, "art": 6,
	},
]


## 法相档位表（下标 = 境界表的 art）。form 召剑阵型 | strike 飞剑阵出剑方式 | stages 空战三段 | volley 长按连发队形
## trail 飞剑剑光样式（trail.gdshader 的 style） | tw 剑光宽度
const ARTS := [
	{"form": "环身剑阵", "strike": "弧线飞斩", "stages": ["御剑·三连刺", "火球", "剑火齐发"],
	 "volley": "万剑连发", "trail": 0, "tw": 0.07},
	{"form": "平卧剑轮", "strike": "金丹剑气·蓄势直刺", "stages": ["御剑·三连刺", "火球", "剑火齐发"],
	 "volley": "扇面点射", "trail": 0, "tw": 0.1},
	{"form": "双环陀螺", "strike": "雷闪折线·电弧连锁", "stages": ["雷剑·折光", "掌心雷", "九霄雷引"],
	 "volley": "双剑螺旋绞", "trail": 2, "tw": 0.1},
	{"form": "背后光轮", "strike": "火轮环斩", "stages": ["焚天剑轮", "三昧火莲", "金乌坠"],
	 "volley": "焚天剑轮", "trail": 1, "tw": 0.13},
	{"form": "五行五簇", "strike": "遁虚天降", "stages": ["五行剑阵", "五行轮转", "五行归一"],
	 "volley": "五行剑列", "trail": 0, "tw": 0.11},
	{"form": "双翼剑翅", "strike": "裂空穿刺", "stages": ["裂空剑", "空间裂隙", "乾坤挪移斩"],
	 "volley": "裂空剑列", "trail": 5, "tw": 0.12},
	{"form": "千剑莲台", "strike": "天剑下贯", "stages": ["天剑", "天门", "万剑归宗"],
	 "volley": "万剑朝宗", "trail": 4, "tw": 0.15},
]


## 战斗表现档位（下标 = 境界）：同一招在不同境界打出来的「分量」。只管看着、打着有多猛，不改伤害（伤害是 LIST 的 dmg）。
## 结丹是基准（倍率都是 1）；每一档都要比上一档明显强一截。别把整列一起乘一个数 —— 要改就一档一档地核对
## （自检：main.gd 的 `-- --duel-shot --spark --spark-tiers`，逐境界打印顿帧 / 震动 / 击飞 / 对波出剑数）。
##   fx     命中特效的大小倍率（冲击圈、刀光、气浪环）
##   burst  命中特效的数量倍率（碎块颗数）
##   kb     重手 / 击飞的速度倍率（飞得多远）；轻击只吃它的三分之一，免得连段接不上
##   stop   顿帧倍率 | shake 镜头震动 / 推镜倍率
##   clash_n    飞剑对波时每秒出多少柄剑（桌面档） | clash_lite 手机画质档的
##   clash_sz   对波飞剑相对平时的放大倍数
##   clash_wide 对波剑阵的散布宽度倍率（越高阶铺得越开，从一束变成一堵剑墙）
##   clash_core 交汇点（光核、碰撞盘、光晕）的大小倍率
## 炼气 / 筑基不能空战，对波那几项只给装束是这两档的对手用。
const COMBAT := [
	{"fx": 0.72, "burst": 0.7, "kb": 0.8, "stop": 0.85, "shake": 0.7,
	 "clash_n": 16.0, "clash_lite": 10.0, "clash_sz": 1.5, "clash_wide": 0.7, "clash_core": 0.8},      # 炼气
	{"fx": 0.86, "burst": 0.85, "kb": 0.9, "stop": 0.92, "shake": 0.85,
	 "clash_n": 20.0, "clash_lite": 12.5, "clash_sz": 1.7, "clash_wide": 0.85, "clash_core": 0.9},     # 筑基
	{"fx": 1.0, "burst": 1.0, "kb": 1.0, "stop": 1.0, "shake": 1.0,
	 "clash_n": 26.0, "clash_lite": 15.5, "clash_sz": 1.9, "clash_wide": 1.0, "clash_core": 1.0},      # 结丹
	{"fx": 1.14, "burst": 1.2, "kb": 1.12, "stop": 1.07, "shake": 1.12,
	 "clash_n": 32.0, "clash_lite": 18.0, "clash_sz": 2.05, "clash_wide": 1.15, "clash_core": 1.1},   # 元婴
	{"fx": 1.28, "burst": 1.4, "kb": 1.25, "stop": 1.14, "shake": 1.24,
	 "clash_n": 38.0, "clash_lite": 20.5, "clash_sz": 2.2, "clash_wide": 1.3, "clash_core": 1.2},     # 化神
	{"fx": 1.43, "burst": 1.65, "kb": 1.4, "stop": 1.21, "shake": 1.36,
	 "clash_n": 45.0, "clash_lite": 23.5, "clash_sz": 2.4, "clash_wide": 1.5, "clash_core": 1.32},     # 炼虚
	{"fx": 1.6, "burst": 1.9, "kb": 1.55, "stop": 1.28, "shake": 1.48,
	 "clash_n": 53.0, "clash_lite": 27.0, "clash_sz": 2.6, "clash_wide": 1.7, "clash_core": 1.45},      # 合体
	{"fx": 1.8, "burst": 2.2, "kb": 1.72, "stop": 1.36, "shake": 1.6,
	 "clash_n": 62.0, "clash_lite": 31.0, "clash_sz": 2.85, "clash_wide": 1.95, "clash_core": 1.6},    # 大乘
]


static func count() -> int:
	return LIST.size()


## 第 idx 个境界的战斗表现档位（见 COMBAT）
static func combat(idx: int) -> Dictionary:
	return COMBAT[clampi(idx, 0, COMBAT.size() - 1)]


## 境界的法相档位 0~6
static func art(realm: Dictionary) -> int:
	return int(realm.get("art", 0))


static func art_info(realm: Dictionary) -> Dictionary:
	return ARTS[art(realm)]


static func hdr(c: Color, mul: float) -> Color:
	return Color(c.r * mul, c.g * mul, c.b * mul, 1.0)


## 丝线颜色表（第 0 条为主线）
static func lines(realm: Dictionary) -> Array:
	return realm["lines"]


## 该境界特效的主色：饱和、不发白
static func line_color(realm: Dictionary) -> Color:
	return (realm["lines"] as Array)[0]
