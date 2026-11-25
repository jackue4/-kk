extends RefCounted
## 英雄「霜华」（冰修，第三位英雄，id "shuanghua"）的整张表（2026-11-25 TSB 式重做；用户原话「做完这些后，你自己设计一个角色3」）。
## 定位：中距离控场。和体修（贴身猛打）、剑修（先划后爆）不是一路 —— 她靠技能给对手叠「寒意」，叠满三层冻住，再一记重手把冰打碎。
##   · 寒意（技能脚本 kit_shuanghua.gd 记）：冰锥 +1、霜环 +2、冰棘 +1、M1 最后一掌 +1；6 秒不补就全退；满 3 层 = 冻结 1.2 秒；
##     解冻后 6 秒内不再叠（不会被连着冻到死）。被护体挡下 / 拨开的不叠。
##   · 冻结：定在原地、不被推走（命中 info 里的 freeze，真人那边由 air_melee._hurt 生效；AI / 怪认同时带的 stun）。
##     冻着的人再挨她一记重手（M1 最后一掌、冰锥、冰棘）= 碎冰，多 0.6 个单位。
##   · M1 最后一掌有三个变体，出手那一刻由技能脚本看目标的状态换（同一个姿势、同样的时刻）：
##     sh4 平时（打飞）· sh4f 这一掌正好叠满（不打飞，直接冻住）· sh4x 对面正冻着（碎冰 +0.6，打飞）。觉醒那张表同理（sa4 / sa4f / sa4x）。
##   · 四个技能的判定都由技能脚本做（招式里写的是 proj：到点交给脚本），所以这里技能招的 dmg 都是 0，数值在 kit_shuanghua.gd 的常量里。
## 字段说明见 hero_defs.gd 文件头和 def_zhenyue.gd 文件头。
## 故意不写 class_name。

const ICE := Color(0.62, 0.9, 1.0)
const FROST := Color(0.93, 0.98, 1.0)

const DEF := {
	"enabled": true,
	"name": "霜华", "title": "冰修",
	"desc": "不跟人贴身硬拼的冰修：冰锥点射、霜环震开近身的、冰棘隔着十几米把人挑上天、冰狱圈地冻人；命中叠寒意，满三层冻结，再一掌碎冰。觉醒「玄冰之心」四式皆变。",
	"skin": "evelyn", "blade": "fist", "blade_always": false, "volley": false, "no_swords": true,
	"art": 1, "flair": 1,
	"chain": ["sh1", "sh2", "sh3", "sh4"], "chain_awake": ["sa1", "sa2", "sa3", "sa4"],
	"juggle": ["j1", "j2", "j3"],
	"derive": {"up": "d_up", "down": "d_dn", "side": "d_fl"},
	"counter": "ctr", "dash_move": "dash",
	"smash": {
		"fwd": {"name": "寒霜掌", "seq": "sh_sm", "hit": 0.055, "end": 0.5, "limb": "rh", "spd": 42.0},
		"up": {"name": "挑飞", "seq": "f_up", "hit": 0.11, "end": 0.56, "limb": "rf", "spd": 36.0},
		"down": {"name": "陨落", "seq": "f_dn", "hit": 0.12, "end": 0.56, "limb": "rh", "spd": 50.0},
	},
	"pose_map": {"f_idle": "sh_idle", "f_guard": "sh_guard"},
	"rush_r": 11.0,
	"awake_dur": 16.0, "awake_move": "sh_awk",
	"moves": {
		# ---- M1 四段（手上凝着冰刃，比拳多够 0.5 米）：拂雪 0.5 → 挑霜 0.55 → 回风 0.75 → 霜华绽 1.2（把人推飞，寒意 +1）= 3.0 单位 ----
		"sh1": {"name": "拂雪", "seq": "sh1", "hit": 0.085, "chain": 0.2, "cancel": 0.15, "end": 0.42, "next": "sh2",
			"dmg": 0.5, "kb": 3.0, "stun": 0.5, "gd": 1.0, "stop": 0.045, "limb": "rh", "tier": 0, "trauma": 0.15, "push": 0.03, "swords": 0, "pstun": 0.36,
			"reach": 0.5, "fx": "s"},
		"sh2": {"name": "挑霜", "seq": "sh2", "hit": 0.09, "chain": 0.21, "cancel": 0.16, "end": 0.44, "next": "sh3",
			"dmg": 0.55, "kb": 3.5, "stun": 0.52, "gd": 1.0, "stop": 0.05, "limb": "lh", "tier": 0, "trauma": 0.17, "push": 0.03, "swords": 0, "pstun": 0.38,
			"reach": 0.5, "fx": "s"},
		"sh3": {"name": "回风", "seq": "sh3", "hit": 0.13, "chain": 0.26, "cancel": 0.22, "end": 0.52, "next": "sh4",
			"dmg": 0.75, "kb": 5.5, "stun": 0.6, "gd": 1.5, "stop": 0.07, "limb": "rh", "tier": 0, "trauma": 0.24, "push": 0.05, "swords": 0, "pstun": 0.5,
			"reach": 0.6, "fx": "s3"},
		"sh4": {"name": "霜华绽", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.62, "next": "",
			"dmg": 1.2, "kb": 28.0, "stun": 0.95, "gd": 2.0, "stop": 0.12, "limb": "rh", "tier": 1, "trauma": 0.4, "push": 0.08, "swords": 0,
			"launch": "fwd", "reach": 0.6, "fx": "s4"},
		"sh4x": {"name": "霜华绽·碎冰", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.62, "next": "",
			"dmg": 1.8, "kb": 30.0, "stun": 0.95, "gd": 2.0, "stop": 0.16, "limb": "rh", "tier": 1, "trauma": 0.5, "push": 0.1, "swords": 0,
			"launch": "fwd", "reach": 0.6, "fx": "s4x"},
		"sh4f": {"name": "霜华绽·凝冰", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.56, "next": "",
			"dmg": 1.2, "kb": 0.0, "stun": 1.2, "gd": 2.0, "stop": 0.12, "limb": "rh", "tier": 1, "trauma": 0.36, "push": 0.07, "swords": 0,
			"heavy": false, "freeze": 1.2, "reach": 0.6, "fx": "s4f"},
		# ---- 觉醒 M1「玄冰之心」：同样四段，冰刃暴长（多够 1.2 米），每一下带一道冰弧 ----
		"sa1": {"name": "玄冰·拂", "seq": "sh1", "hit": 0.085, "chain": 0.2, "cancel": 0.15, "end": 0.42, "next": "sa2",
			"dmg": 0.5, "kb": 3.0, "stun": 0.5, "gd": 1.0, "stop": 0.05, "limb": "rh", "tier": 0, "trauma": 0.17, "push": 0.03, "swords": 0, "pstun": 0.36,
			"reach": 1.2, "qi": true, "fx": "s"},
		"sa2": {"name": "玄冰·挑", "seq": "sh2", "hit": 0.09, "chain": 0.21, "cancel": 0.16, "end": 0.44, "next": "sa3",
			"dmg": 0.55, "kb": 3.5, "stun": 0.52, "gd": 1.0, "stop": 0.055, "limb": "lh", "tier": 0, "trauma": 0.19, "push": 0.03, "swords": 0, "pstun": 0.38,
			"reach": 1.2, "qi": true, "fx": "s"},
		"sa3": {"name": "玄冰·旋", "seq": "sh3", "hit": 0.13, "chain": 0.26, "cancel": 0.22, "end": 0.52, "next": "sa4",
			"dmg": 0.75, "kb": 5.5, "stun": 0.6, "gd": 1.5, "stop": 0.075, "limb": "rh", "tier": 0, "trauma": 0.26, "push": 0.05, "swords": 0, "pstun": 0.5,
			"reach": 1.2, "qi": true, "fx": "s3"},
		"sa4": {"name": "玄冰·绽", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.62, "next": "",
			"dmg": 1.2, "kb": 30.0, "stun": 0.95, "gd": 2.0, "stop": 0.13, "limb": "rh", "tier": 1, "trauma": 0.44, "push": 0.09, "swords": 0,
			"launch": "fwd", "reach": 1.2, "qi": true, "fx": "s4"},
		"sa4x": {"name": "玄冰·碎冰", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.62, "next": "",
			"dmg": 1.8, "kb": 32.0, "stun": 0.95, "gd": 2.0, "stop": 0.17, "limb": "rh", "tier": 1, "trauma": 0.54, "push": 0.1, "swords": 0,
			"launch": "fwd", "reach": 1.2, "qi": true, "fx": "s4x"},
		"sa4f": {"name": "玄冰·凝冰", "seq": "sh4", "hit": 0.15, "chain": 99.0, "cancel": 0.3, "end": 0.56, "next": "",
			"dmg": 1.2, "kb": 0.0, "stun": 1.2, "gd": 2.0, "stop": 0.13, "limb": "rh", "tier": 1, "trauma": 0.4, "push": 0.08, "swords": 0,
			"heavy": false, "freeze": 1.2, "reach": 1.2, "qi": true, "fx": "s4f"},
		# 觉醒起手：抱臂团身 → 双臂一展（只摆姿势，没有判定；震开身边的人是 air_melee._awaken 做的）
		"sh_awk": {"name": "玄冰之心", "seq": "sh_awk", "hit": 0.3, "chain": 99.0, "cancel": 99.0, "end": 0.75, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 0, "trauma": 0.0, "push": 0.0, "swords": 0,
			"show": true, "root": true, "armor": true, "fx": "awk"},
		# ---- E 冰锥：一指点出一根冰锥（直线飞，46 米，护体能拨），0.9，寒意 +1 ----
		"sh_e": {"name": "冰锥", "seq": "sh_cast", "hit": 0.14, "chain": 99.0, "cancel": 0.3, "end": 0.44, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 0, "trauma": 0.1, "push": 0.02, "swords": 0,
			"proj": "lance", "fx": "e"},
		# ---- Z 霜环：身周 6 米一圈霜爆，把贴身的人震开（0.6），寒意 +2。蓄势中霸体 ----
		"sh_z": {"name": "霜环", "seq": "sh_nova", "hit": 0.16, "chain": 99.0, "cancel": 0.4, "end": 0.56, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 1, "trauma": 0.2, "push": 0.04, "swords": 0,
			"proj": "nova", "armor": true, "fx": "z"},
		# ---- Q 冰棘：一掌按下去，一排冰刺朝目标一路拱出去（14 米），把沿途的人挑上天（0.9），寒意 +1 ----
		"sh_q": {"name": "冰棘", "seq": "sh_q", "hit": 0.18, "chain": 99.0, "cancel": 0.42, "end": 0.6, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 1, "trauma": 0.2, "push": 0.04, "swords": 0,
			"proj": "spikes", "fx": "q"},
		# ---- R 冰狱：圈住目标所在的那一片（4.5 米），0.6 秒后一大簇冰晶炸开（1.2），圈里的直接冻住 1.4 秒；跑出圈就躲掉了 ----
		"sh_r": {"name": "冰狱", "seq": "sh_r", "hit": 0.14, "chain": 99.0, "cancel": 0.4, "end": 0.56, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 0, "trauma": 0.1, "push": 0.02, "swords": 0,
			"proj": "prison", "fx": "r"},
		# ---- 觉醒 E 连珠：左右手连点三根冰锥（各 0.7，寒意各 +1：三根全中正好冻住）----
		"sh_ae1": {"name": "连珠", "seq": "sh_cast_q", "hit": 0.1, "chain": 0.19, "cancel": 0.3, "end": 0.34, "next": "sh_ae2",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 0, "trauma": 0.1, "push": 0.02, "swords": 0,
			"proj": "lance3", "auto": true, "fx": "e"},
		"sh_ae2": {"name": "连珠", "seq": "sh_castl_q", "hit": 0.1, "chain": 0.19, "cancel": 0.3, "end": 0.34, "next": "sh_ae3",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "lh", "tier": 0, "trauma": 0.1, "push": 0.02, "swords": 0,
			"proj": "lance3", "auto": true, "fx": "e"},
		"sh_ae3": {"name": "连珠", "seq": "sh_cast_q", "hit": 0.1, "chain": 99.0, "cancel": 0.3, "end": 0.44, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 0, "trauma": 0.12, "push": 0.02, "swords": 0,
			"proj": "lance3", "fx": "e"},
		# ---- 觉醒 Z 凛冬：身周 9 米一圈（1.0），圈里的直接冻住 1.2 秒。全程霸体 ----
		"sh_az": {"name": "凛冬", "seq": "sh_nova2", "hit": 0.2, "chain": 99.0, "cancel": 0.45, "end": 0.64, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 1, "trauma": 0.3, "push": 0.06, "swords": 0,
			"proj": "nova2", "armor": true, "fx": "z"},
		# ---- 觉醒 Q 冰川：更宽更长的一道冰刺（22 米，1.6），寒意 +2，沿途犁出一道沟 ----
		"sh_aq": {"name": "冰川", "seq": "sh_q", "hit": 0.18, "chain": 99.0, "cancel": 0.42, "end": 0.62, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 1, "trauma": 0.3, "push": 0.06, "swords": 0,
			"proj": "spikes2", "armor": true, "fx": "q"},
		# ---- 觉醒 R 永冻（终结）：双臂擎天，目标脚下一朵九米的冰莲轰然绽开（2.4），圈里的全部冻住 2 秒。放完觉醒结束 ----
		"sh_ar": {"name": "永冻", "seq": "sh_fin", "hit": 0.64, "chain": 99.0, "cancel": 99.0, "end": 1.12, "next": "",
			"dmg": 0.0, "kb": 0.0, "stun": 0.0, "gd": 0.0, "stop": 0.0, "limb": "rh", "tier": 1, "trauma": 0.3, "push": 0.05, "swords": 0,
			"proj": "lotus", "armor": true, "fx": "fin"},
	},
	"follow_k": 0.0,
	"skill_cd": [],
	"skills": [
		{"key": "E", "name": "冰锥", "desc": "一指点出一根冰锥：直线飞 46 米（0.9），寒意 +1。护体能拨开、侧移能躲", "cd": 5.0, "mp": 0.0,
			"awake_name": "连珠", "awake": "连珠：左右手连点三根冰锥（3 × 0.7），三根全中正好冻住", "awake_cd": 6.0},
		{"key": "Z", "name": "霜环", "desc": "身周 6 米一圈霜爆：把贴上来的人震开（0.6），寒意 +2。蓄势中霸体", "cd": 10.0, "mp": 0.0,
			"awake_name": "凛冬", "awake": "凛冬：身周 9 米一圈（1.0），圈里的直接冻住 1.2 秒", "awake_cd": 9.0},
		{"key": "Q", "name": "冰棘", "desc": "一掌按下，一排冰刺朝目标一路拱出去 14 米：把沿途的人挑上天（0.9），寒意 +1", "cd": 9.0, "mp": 0.0,
			"awake_name": "冰川", "awake": "冰川：更宽更长的一道冰刺（22 米，1.6），寒意 +2，地上犁出一道沟", "awake_cd": 8.0},
		{"key": "R", "name": "冰狱", "desc": "圈住目标所在的一片（4.5 米），0.6 秒后冰晶炸开（1.2）、圈里的直接冻住 1.4 秒；跑出圈就躲掉", "cd": 14.0, "mp": 0.0,
			"awake_name": "永冻", "awake": "终结「永冻」：目标脚下一朵九米的冰莲绽开（2.4），圈里的全部冻住 2 秒。放完觉醒结束", "awake_cd": 3.0, "finisher": true},
	],
	"awaken": "玄冰之心 16 秒：周身寒光，伤害 ×1.3，冰刃暴长（M1 多够 1.2 米、带冰弧）；冰锥 → 连珠、霜环 → 凛冬、冰棘 → 冰川、冰狱 → 永冻。",
	"touch": ["锥", "环", "棘", "狱"], "touch_awake": ["珠", "冬", "川", "冻"],
	"fly_speed": 28.0, "blink": 8.0, "blink_spd": 60.0,
	"realm": {"lines": [ICE, FROST], "col_a": Color(0.9, 0.98, 1.0), "col_b": Color(0.35, 0.7, 1.0),
		"style": 0, "motes": 2, "boost": 1.4, "rise": 7.0, "swords": 0},
	"kit": "res://scripts/heroes/kit_shuanghua.gd",
}
