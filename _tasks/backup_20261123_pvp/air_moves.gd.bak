extends RefCounted
## 空战招式表 + 攻防规则。主角（air_melee.gd）和空战对手（air_foe.gd）共用这一份数据：
## 改手感、调克制关系只改这里，两边的状态机照着表走。
## 故意不写 class_name：用 preload 引用。
##
## —— 招式字段（时间 = 招式内的战斗时间，秒）——
##   seq     用 combat_poses.gd 里哪条姿势时间轴
##   hit     判定时刻
##   chain   连招窗口起点：这之后可以接下一招（早按的进输入缓冲，到点自动接上）
##   cancel  取消窗口起点：这之后可以用 护体 / 闪现 / 剑诀 取消后摇（判定前 CANCEL_HEAD 秒内也能取消，算「收手」）
##   end     收招（打空了收得快一些）；收招后 LINK 秒内再按攻击，连段接着往下打
##   next    点按攻击接哪一招（空 = 这一招是收尾）
##   dmg     伤害（× 境界 dmg × 连段衰减）   kb 击退速度   stun 对手硬直（× 硬直衰减）   gd 削对手多少护体值
##   stop    顿帧   trauma / push 镜头震动 / 前推   limb 用哪儿打（rh / lh 拳 · rf / lf 脚 · sw 剑）   tier 0 轻 1 重
##   swords  命中后跟上几柄飞剑   launch 击飞方向（"" 不击飞 / fwd / up / down）
##   brk     破防：护体挡不住，直接破开   rear 出手前先绕到对手身后（背后挨打不算格挡）   mp 出招耗灵力
##
## —— 克制关系 ——
##   轻击 快，能打断重击的蓄势；被 护体 挡下（每挡一下削一点护体值，削光即破防）
##   重击 蓄力过半即破防（护体挡不住）、把人打飞；蓄势慢，会被轻击打断、被 瞬身 躲开后反打
##   护体 挡轻击和没蓄够的重击；怕 蓄力重击、绕身击（从背后打）、一直压着打（护体值削光）
##   瞬身 判定前一瞬间按 御 / 闪：闪到对手身后，对手露出破绽，可以立刻「瞬身反击」；耗灵力，连续瞬身窗口越来越窄
##   挣脱 挨打硬直中按 御：耗一格罡气把身边的人震开（连段再长也有出路）；罡气慢慢回
##   受身 被打飞后按 闪：稳住身形，不吃后面的追击
## —— 防止无限连 ——
##   连段越长伤害越低（dmg_scale）、硬直越短（stun_scale）；瞬身追击每套最多 CHASE_MAX 次且耗灵力；
##   被打飞的次数越多越早能受身（TECH）；空中连击打到 JUGGLE_MAX 下对手自动脱身；对手有罡气就会挣脱。

const CANCEL_HEAD := 0.04
const LINK := 0.45

const CHAIN: Array[String] = ["l1", "l2", "l3", "l4", "l5"]
const JUGGLE: Array[String] = ["j1", "j2", "j3"]

const MOVES := {
	# ---- 轻击五段（点按「攻」）----
	"l1": {"name": "冲拳", "seq": "f1", "hit": 0.085, "chain": 0.19, "cancel": 0.14, "end": 0.4, "next": "l2",
		"dmg": 0.45, "kb": 3.0, "stun": 0.5, "gd": 1.0, "stop": 0.045, "limb": "rh", "tier": 0, "trauma": 0.16, "push": 0.03, "swords": 1},
	"l2": {"name": "摆拳", "seq": "f2", "hit": 0.085, "chain": 0.19, "cancel": 0.14, "end": 0.42, "next": "l3",
		"dmg": 0.45, "kb": 3.0, "stun": 0.5, "gd": 1.0, "stop": 0.05, "limb": "lh", "tier": 0, "trauma": 0.18, "push": 0.03, "swords": 1},
	"l3": {"name": "蹬踢", "seq": "f3", "hit": 0.1, "chain": 0.22, "cancel": 0.16, "end": 0.46, "next": "l4",
		"dmg": 0.6, "kb": 5.0, "stun": 0.55, "gd": 1.0, "stop": 0.06, "limb": "rf", "tier": 0, "trauma": 0.2, "push": 0.04, "swords": 1},
	"l4": {"name": "回旋踢", "seq": "f4", "hit": 0.14, "chain": 0.28, "cancel": 0.22, "end": 0.54, "next": "l5",
		"dmg": 0.8, "kb": 7.0, "stun": 0.6, "gd": 1.5, "stop": 0.075, "limb": "lf", "tier": 1, "trauma": 0.26, "push": 0.05, "swords": 2},
	"l5": {"name": "掣剑横斩", "seq": "f5", "hit": 0.135, "chain": 99.0, "cancel": 0.26, "end": 0.6, "next": "",
		"dmg": 1.3, "kb": 27.0, "stun": 0.9, "gd": 2.0, "stop": 0.11, "limb": "sw", "tier": 1, "trauma": 0.38, "push": 0.08, "swords": 3,
		"launch": "fwd"},
	# ---- 方向派生（连段里 摇杆方向 + 点按「攻」）：前 = 挑月（向上打飞）· 后 = 坠星（向下砸）· 左右 = 绕身击（绕到背后）----
	"d_up": {"name": "挑月", "seq": "f_up", "hit": 0.11, "chain": 99.0, "cancel": 0.24, "end": 0.5, "next": "",
		"dmg": 0.9, "kb": 31.0, "stun": 0.9, "gd": 2.0, "stop": 0.1, "limb": "rf", "tier": 1, "trauma": 0.34, "push": 0.07, "swords": 0,
		"launch": "up"},
	"d_dn": {"name": "坠星", "seq": "f_dn", "hit": 0.12, "chain": 99.0, "cancel": 0.24, "end": 0.52, "next": "",
		"dmg": 1.0, "kb": 40.0, "stun": 0.9, "gd": 2.0, "stop": 0.1, "limb": "rh", "tier": 1, "trauma": 0.36, "push": 0.07, "swords": 0,
		"launch": "down"},
	"d_fl": {"name": "绕身击", "seq": "f4", "hit": 0.14, "chain": 0.28, "cancel": 0.24, "end": 0.56, "next": "l5",
		"dmg": 0.85, "kb": 8.0, "stun": 0.75, "gd": 0.0, "stop": 0.08, "limb": "lf", "tier": 1, "trauma": 0.28, "push": 0.05, "swords": 1,
		"rear": true, "mp": 4.0},
	# ---- 冲刺攻击（御风突进途中点按「攻」）：带着冲势的飞踢，削护体多，命中后接轻击第三段 ----
	"dash": {"name": "破空蹬", "seq": "f_dk", "hit": 0.09, "chain": 0.22, "cancel": 0.2, "end": 0.5, "next": "l3",
		"dmg": 1.1, "kb": 15.0, "stun": 0.8, "gd": 3.0, "stop": 0.1, "limb": "rf", "tier": 1, "trauma": 0.36, "push": 0.08, "swords": 2},
	# ---- 空中连击（对手被打飞 / 浮空时点按「攻」）：把人按在半空连打，第三下之后接终结重击 ----
	"j1": {"name": "追击·截", "seq": "f3", "hit": 0.07, "chain": 0.16, "cancel": 0.13, "end": 0.38, "next": "j2",
		"dmg": 0.4, "kb": 2.0, "stun": 0.62, "gd": 0.0, "stop": 0.05, "limb": "rf", "tier": 0, "trauma": 0.2, "push": 0.04, "swords": 1},
	"j2": {"name": "追击·连", "seq": "f1", "hit": 0.075, "chain": 0.16, "cancel": 0.13, "end": 0.38, "next": "j3",
		"dmg": 0.4, "kb": 2.0, "stun": 0.62, "gd": 0.0, "stop": 0.05, "limb": "rh", "tier": 0, "trauma": 0.2, "push": 0.04, "swords": 1},
	"j3": {"name": "追击·旋", "seq": "f4", "hit": 0.13, "chain": 0.25, "cancel": 0.2, "end": 0.5, "next": "",
		"dmg": 0.6, "kb": 3.0, "stun": 0.7, "gd": 0.0, "stop": 0.07, "limb": "lf", "tier": 1, "trauma": 0.26, "push": 0.05, "swords": 2},
	# ---- 瞬身反击（瞬身闪到对手背后之后 COUNTER_T 秒内点按「攻」）----
	"ctr": {"name": "瞬身反击", "seq": "f_sm", "hit": 0.06, "chain": 99.0, "cancel": 0.24, "end": 0.46, "next": "",
		"dmg": 1.6, "kb": 34.0, "stun": 1.0, "gd": 0.0, "stop": 0.13, "limb": "rh", "tier": 1, "trauma": 0.45, "push": 0.1, "swords": 0,
		"launch": "fwd", "brk": true},
}

## 蓄力重击三式（长按「攻」松手，摇杆定去向）：hit 判定时刻 | end 收招 | spd 击飞速度
const SMASH := {
	"fwd": {"name": "崩拳", "seq": "f_sm", "hit": 0.055, "end": 0.5, "limb": "rh", "spd": 42.0},
	"up": {"name": "挑飞", "seq": "f_up", "hit": 0.11, "end": 0.56, "limb": "rf", "spd": 36.0},
	"down": {"name": "陨落", "seq": "f_dn", "hit": 0.12, "end": 0.56, "limb": "rh", "spd": 50.0},
}
const BRK_AT := 0.5           # 蓄力过半（或瞬身追击的终结重击）即破防
const CHAIN_HEAD := 0.35      # 连段里转蓄力：直接从这么多起蓄（不用从头攒）

# ---- 护体 / 破防 ----
const GUARD_MAX := 6.0        # 护体值：轻击挡一下 -1，重手 -1.5 ~ -3，削光即破防
const GUARD_REST := 1.2       # 不护体这么久后开始回
const GUARD_REGEN := 1.6
const CRUSH_T := 1.35         # 破防后的硬直（这段时间挡不了、闪不了）
const CRUSH_DMG := 1.25       # 破防硬直中多吃这么多伤害

# ---- 瞬身 ----
const VANISH_WIN := 0.22      # 判定前这么久内按下 御 / 闪 = 瞬身
const VANISH_SHRINK := 0.78   # 连续瞬身（VANISH_KEEP 秒内）：每多一次，窗口缩成这么多
const VANISH_MIN := 0.1
const VANISH_KEEP := 2.5
const VANISH_MP := 8.0
const COUNTER_T := 0.9        # 瞬身后这么久内点攻击 = 瞬身反击

# ---- 挣脱（罡气）----
const BURST_MAX := 2.0
const BURST_REGEN := 14.0     # 这么久回一格
const BURST_R := 6.5          # 震开这么远内的人

# ---- 飞剑对波 ----
## 每一方的输出 = CLASH_BASE × 技能强度 × 灵力余量 × (1 + 发力)，交汇点按两边输出的差往弱的那边移（全程为 1）：
##   技能强度：主角看境界（每高一档 +6%），觉醒 ×1.3；对手看水平（0.8 + 0.4 × skill）
##   同境界不觉醒时，大致每秒点 3 下能赢入门档、5 下赢进阶档、8 下赢高手档
##   灵力余量：满灵力 ×1，越打越少，见底只剩 ×0.25（撑不住了）—— 相持中双方都按 CLASH_MP 每秒掉灵力
##   发力：主角每点一下「攻击」+CLASH_TAP，随后很快衰减（所以要一直点，点得越快顶得越狠）；对手是一阵一阵地发力
const CLASH_BASE := 0.12      # 调小 = 交汇点挪得慢、一场对波打得久（现在差一倍输出大约四秒分胜负）
const CLASH_MP := 14.0
const CLASH_TAP := 0.5
const CLASH_SURGE_MAX := 2.2
const CLASH_SURGE_DECAY := 2.6
const CLASH_PRESS := 0.72      # 交汇点过了这条线算「压制」（镜头切到压制方身后，被压的那束发虚）
const CLASH_SWORD := 1.9       # 对波时飞剑比平时大这么多倍
const CLASH_SWORD_SPD := 46.0  # 对波时飞剑的速度（平时七八十）：慢一些，半空里同时在飞的剑才多

# ---- 投技「擒拿抡摔」----
## 空手起手时 摇杆后拉 + 点按「攻」：探手擒住对手，抡两圈甩出去（松手时摇杆：不推 / 前 = 朝镜头前方甩，后 = 往地面砸，左右 = 往两侧甩）。
## 护体挡不住（克龟缩）；怕拳脚 —— 对手正在出手时抓不住，自己伸手的那一下挨打就被打断；瞬身 / 闪开也躲得掉。
## 对手被摔过之后 THROW_IMMUNE 秒内抓不住第二次；对手也会用（看主角一直举着护体时），被擒住的那一小会儿连点「攻」能挣开。
const THROW_REACH := 0.2       # 探手到擒住
const THROW_SPIN := 0.62       # 抡两圈
const THROW_END := 0.4         # 甩出去之后的收招（抓空了更长，是破绽）
const THROW_R := 4.5           # 目标在这么近才抓得着
const THROW_SPD := 48.0        # 甩出去的速度
const THROW_DMG := 1.5         # 伤害（× 境界 dmg），撞上东西另算
const THROW_IMMUNE := 4.0
const GRAB_HOLD := 0.65        # 对手擒住主角到甩出去的时间（挣脱的窗口）
const GRAB_ESCAPE := 4         # 这段时间里连点这么多下「攻」挣开

# ---- 拳劲对拼（高速互殴）----
## 两边的拳头同时打向对方（一方出手的判定落在另一方还没打出去的起手里）→ 不各挨一下，而是进入对拼：
## 两个人贴身快拳互殴，每隔半秒一起闪到别处接着打，原地只留一圈冲击波。连点「攻」把优势条往对面顶（算法同对波，但不耗灵力），
## 赢的一方一记重手把对面打飞。BRAWL_CD 秒内不会连着触发。
const BRAWL_MAX := 3.2
const BRAWL_BASE := 0.16
const BRAWL_CD := 9.0

# ---- 坠地追击：对手被砸进地里、趴在坑里的那一秒，补一发收尾（一次坠地只能补一发，二选一）----
#   「攻」= 坠星踏：闪到它正上方，整个人打直了砸下去踩进坑里
#   「剑」= 剑雨灌顶：人不下去，一轮飞剑从坑的上空直插下去，最后一波落地炸开（耗灵力）
# 补完对手再趴 OTG_HOLD 秒就起身（起身带无敌），不会被压在地上接着连
const OTG_DIVE_H := 9.0        # 踏击从对手正上方这么高处砸下来（头顶有东西挡着就矮一点）
const OTG_DIVE_T := 0.16       # 俯冲用时
const OTG_END := 0.36          # 踏击收招
const OTG_DMG := 2.2           # 踏击伤害倍率
const OTG_HOLD := 0.6
const RAIN_MP := 0.12          # 剑雨耗灵力（占上限的比例）
const RAIN_T := 0.62           # 剑雨从出手到最后一波落地
const RAIN_DMG := 1.9          # 剑雨落地那一下的伤害倍率

# ---- 弹开气弹 ----
#   护体中：正面飞来的气弹 / 飞剑单手一拨，斜着崩飞（不掉血，耗的灵力是硬挡的三分之一）
#   气弹离打到自己不到 SWAT_WIN 秒时按「攻」：反手抽回去，打中放它的人
const SWAT_WIN := 0.24
const SWAT_MP := 2.0
const SWAT_BACK := 1.5         # 抽回去的气弹速度倍率
const SWAT_DMG := 0.6          # 抽回去打中的伤害倍率（乘主角的伤害基数）

# ---- 追击 / 受身 ----
const CHASE_MAX := 3
const TECH: Array[float] = [1.05, 0.8, 0.6]   # 一套连段里第 n 次被打飞，这么久后可以受身
const JUGGLE_MAX := 4         # 空中连击连着挨到第几下自动脱身（三下之内接终结重击就没事）


static func move(id: String) -> Dictionary:
	return MOVES[id]


## 连段第 n 下拳脚的伤害倍率：前 8 下不衰减，之后每下少 4.5%，最低四成
static func dmg_scale(n: int) -> float:
	return clampf(1.0 - 0.045 * float(maxi(n - 8, 0)), 0.4, 1.0)


## 连着挨到第 n 下时的硬直倍率：前 6 下不衰减，之后每下短 7%，最低四成五
static func stun_scale(n: int) -> float:
	return clampf(1.0 - 0.07 * float(maxi(n - 6, 0)), 0.45, 1.0)


## 连续第 n 次（从 0 起）瞬身的窗口
static func vanish_window(n: int) -> float:
	return maxf(VANISH_WIN * pow(VANISH_SHRINK, float(n)), VANISH_MIN)


## 第 n 次（从 1 起）被打飞后多久可以受身
static func tech_time(n: int) -> float:
	return TECH[clampi(n - 1, 0, TECH.size() - 1)]


## 击飞方向（三维，已归一）：kind 对应 前 / 上 / 下，flat 为水平基准方向
static func knock_dir(kind: String, flat: Vector3) -> Vector3:
	match kind:
		"up":
			return (flat * 0.22 + Vector3.UP).normalized()
		"down":
			return (flat * 0.3 + Vector3.DOWN).normalized()
	return (flat + Vector3.UP * 0.16).normalized()
