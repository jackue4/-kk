extends RefCounted
## 英雄表（2026-11-24 搜打撤 PvP 重构，规格见 _tasks/extraction_refactor/SPEC.md 第 6 节）。
##
## 英雄 = 一套「招式档 + 花样档 + M1 表 + 四个技能 + 觉醒形态 + 模型 / 兵器 + 飞行速度」。
## 2026-11-25 主干解耦：战斗数值跟玩家境界走（player.realm 的底子 = Realm.LIST[realm_idx]：base / 灵力 / 遁速 / 升限都随境界），
## 英雄只覆盖外观键（丝线配色 / 样式 / 伴飞剑影，见 player.gd 的 HERO_LOOK_KEYS）+ 招式档 art + 空战模式 LIGHT；三位英雄之间没有强弱倍率。
## AI 修士（air_foe.gd）照旧读 air_moves.gd 的 MOVES / CHAIN：英雄自己的招式（新增的、或覆盖老招式数值的）都放在这里的 moves 里，
## 只对本机主角生效（air_melee.gd 的 _mv 先查英雄表，查不到再查 MOVES），AI 的手感一点不变。
##
## 每项字段：
##   name / title / desc        名字 / 称号 / 一句话介绍（大厅英雄页）
##   skin                       hero_skin.gd 的 SKINS（模型）；blade = "fist" 拳脚 / "sword" 剑；blade_always = 剑一直拿在手里
##   volley                     有没有万剑连发 / 飞剑对波（按住 E 连发、对着连发的对手接波；缺省 true。苍鸿 false：E 是一闪）
##   sword_col / sword_glow     手里那把剑的剑身色 / 剑光色（blade_always 才用）
##   art / flair                招式档（Realm.art：剑诀、连发队形、飞剑阵型）/ 花样档（air_melee.flair：1 = 每下拖残影、重手一圈空间波动）
##   chain / chain_awake        M1 连段表（招式名）；觉醒时换的那张（空 = 不换）
##   juggle                     空中连击（追击接上后的三下）
##   derive                     连段里摇杆方向派生：up 前推 / down 后拉 / side 左右
##   counter / dash_move        瞬身反击 / 御风突进途中点「攻」出的招
##   smash                      蓄力重击三式的覆盖（fwd / up / down；空 = 用 MOVES.SMASH）
##   pose_map                   通用姿势换成英雄自己的（空战待机 / 护体 / 蓄力：持剑的英雄手里拿着剑摆）
##   moves                      新增 / 覆盖的招式（字段同 air_moves.gd 的 MOVES，另加：reach 多够几米、lunge 远距离吸附更快、
##                              lunge_v 没目标时往前冲多快、pass 判定后穿到对手身后、auto 不用按键自动接下一招、proj 判定那一下交给技能脚本放飞行道具、
##                              qi 挥出去带一道剑气弧光）
##   follow_k                   拳脚命中后跟上的飞剑每柄几个单位（御剑）
##   skill_cd                   「诀」三式共用冷却（御剑，英雄档下拉长）
##   skills[4]                  E / Z / Q / R 四个技能：{key, name, desc, cd, mp}（cd 秒、mp 灵力单位；awake = 觉醒后变成什么）
##   awaken                     觉醒形态说明
##   touch[4]                   触屏四个技能键上的字（E / Z / Q / R）
##   fly_speed / blink          （2026-11-25 起主干不读：遁速 / 闪现跟境界走，遁速下限 player.HERO_SPEED_MIN）
##   realm                      覆盖到 player.realm 上的境界表字段：主干只取外观键 lines / col_a / col_b / style / motes / width / swords（boost / rise 不取）
##   kit                        技能脚本
## 故意不写 class_name：用 preload 引用。别的脚本用 HeroDefs.def_of(id)（不能叫 get：和 Object.get 撞名，编译不过）。

const DEFAULT := "yujian"
## 展台（hero_doll / 英雄选择界面 / 样张）上的方块人默认穿哪档衣服（只管看，只在 --block-hero 方块人模式下看得出）。
## 2026-11-25 起和数值无关：英雄的数值跟玩家境界走（原来的 BASE 已删）
const TIER := 2

## 2026-11-25：一位英雄一个文件（scripts/heroes/def_*.gd 的 DEF），这里只把它们拼成一张表。
## "yujian" 这个 id 现在是体修「镇岳」（原来的飞剑法修「御剑」重做成纯拳脚了；id 存在存档 / 联机握手里，不改）。
const DefZhenyue := preload("res://scripts/heroes/def_zhenyue.gd")
const DefCanghong := preload("res://scripts/heroes/def_canghong.gd")
const DefShuanghua := preload("res://scripts/heroes/def_shuanghua.gd")

const HEROES := {
	"yujian": DefZhenyue.DEF,
	"canghong": DefCanghong.DEF,
	"shuanghua": DefShuanghua.DEF,
}


## 英雄 id 列表（大厅英雄页的顺序）
static func ids() -> Array:
	var out := ["yujian", "canghong"]
	if bool(DefShuanghua.DEF.get("enabled", false)):
		out.append("shuanghua")      # 第三位英雄做好之前先不露出来
	return out


static func has(id: String) -> bool:
	return ids().has(id)


## 一位英雄的整张表（找不到 = 空表）。不能叫 get（和 Object.get 撞名）
static func def_of(id: String) -> Dictionary:
	return HEROES.get(id, {})


static func hero_name(id: String) -> String:
	return str(def_of(id).get("name", "镇岳"))


## 四个技能里第 i 个（0 E · 1 Z · 2 Q · 3 R）
static func skill(id: String, i: int) -> Dictionary:
	var sk: Array = def_of(id).get("skills", [])
	return sk[i] if i >= 0 and i < sk.size() else {}


## 这位英雄的招式 id（新增 / 覆盖的优先，否则 air_moves.gd 的 MOVES）
static func move_of(id: String, move_id: String) -> Dictionary:
	var mv: Dictionary = def_of(id).get("moves", {})
	return mv.get(move_id, {})


## 一整套 M1 打满的单位（自检 / 报告用；随击飞剑按 follow_k 算）
static func m1_units(id: String, awake := false) -> float:
	var d := def_of(id)
	var chain: Array = d.get("chain_awake", []) if awake and not (d.get("chain_awake", []) as Array).is_empty() else d.get("chain", [])
	var u := 0.0
	for m: String in chain:
		var mv := move_of(id, m)
		u += float(mv.get("dmg", 0.0)) + float(mv.get("swords", 0)) * float(d.get("follow_k", 0.2))
	return u
