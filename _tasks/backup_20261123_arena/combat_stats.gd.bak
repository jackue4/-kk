extends RefCounted
## 战斗数值中枢（2026-11-20 夜，用户要求：「给所有修炼阶段建立一套完善的战斗数值机制，整体打磨攻击力、血量 / 血条、蓝量 / 蓝条、技能伤害」）。
## 各境界、各等级的攻击 / 气血 / 灵力 / 回复、普攻和技能的倍率、连发 / 飞剑阵的速率折算、首领和 PvP 的上限都从这里取，别处不再各写各的。
##
## 一、三种「单位」
##   · 招式倍率（单位）：一招打出 base(境界) × 倍率 的原始伤害。base = Realm.LIST 的 dmg（8 / 12 / 18 / 26 / 38 / 52 / 75 / 110）。
##     大厅（试剑台陪练、剑冢首领）直接按原始伤害结算——对手的血也按 base 配，所以同一档对手在哪个境界都差不多耐打。
##   · 攻击力：大世界里一招 = 倍率 × atk(lv)（局内等级），境界的 base 先除掉（raid_manager.player_dmg）。atk = 12 × (1 + 0.2·(lv−1))。
##   · 气血条：player.melee.hp 是 0 ~ 100 的百分比条（联机同步、几十处自检都按 100 写，不动）。主角的「气血」= hp(lv) = 110 × (1 + 0.3·(lv−1))，
##     受到的原始伤害按 to_bar() 折成条上的点数；玩家牌上显示的是 hp(lv) 的实数。
## 二、灵力：内部按「灵力单位」算，池子 90 ~ 130（境界越高越大），各种固定消耗（点射 3、护体 6、瞬身 8……）都是按 100 单位配的，
##   所以在每个境界都是同样的百分比；回复按池子大小折（满池 6.25 秒回满）。玩家牌上显示的数按 Realm.LIST 的 mp（60 ~ 300）换算，只是好看。
##   （以前：池子 60 ~ 300、回复固定每秒 16——炼气 3.75 秒回满、大乘要 18.75 秒；固定消耗到了高境界几乎不要钱，剑诀按比例扣反而越来越难回）
## 三、速率型技能（连发、飞剑阵）的折算：剑越来越多、越来越快是境界的「观感」，但每柄的伤害按 volley_k / q_k 折，
##   让每秒伤害（招式单位）只按 skill_g(境界) 慢慢涨（每个境界 ×1.1），不再到大乘翻五六十倍（以前联机 PvP 大乘连发零点几秒秒人、剑冢首领一管灵力就倒）。
## 四、PvP：一下最多打掉对方 PVP_HIT_CAP 点气血条（境界差再大也不会一招秒）。
## 故意不写 class_name：用 preload 引用。

const MAX_REALM := 7

# ---------- 攻击 / 气血 ----------
const ATK_BASE := 12.0           # 1 级、倍率 1.0 的一招
const ATK_G := 0.2               # 每级 +20%
const HP_BASE := 110.0           # 1 级的气血
const HP_G := 0.3                # 每级 +30%
const GEAR_ATK_CAP := 0.8        # 「攻」法宝加起来最多 +80%（「守」本来就封顶 60%）


static func base(realm: int) -> float:
	return float(Realm.LIST[clampi(realm, 0, MAX_REALM)]["dmg"])


static func atk(lv: int) -> float:
	return ATK_BASE * (1.0 + ATK_G * float(maxi(lv, 1) - 1))


static func hp(lv: int) -> float:
	return HP_BASE * (1.0 + HP_G * float(maxi(lv, 1) - 1))


## 原始伤害 → 主角气血条上的点数（条满 100）
static func to_bar(raw: float, lv: int, guard := 0.0) -> float:
	return raw * 100.0 / hp(lv) * (1.0 - clampf(guard, 0.0, 0.6))


## 一招（原始伤害 d，按境界 realm 的 base 打出来的）→ 大世界里实际的伤害
static func raid_hit(d: float, realm: int, lv: int, gear_atk := 0.0) -> float:
	return d / base(realm) * atk(lv) * (1.0 + minf(gear_atk, GEAR_ATK_CAP))


# ---------- 灵力 ----------
const MP_UNITS: Array[float] = [90.0, 95.0, 100.0, 106.0, 112.0, 118.0, 124.0, 130.0]   # 灵力池（单位）
const MP_REGEN_PER100 := 16.0    # 每 100 单位池子每秒回多少（满池 6.25 秒回满）


static func mp_max(realm: int) -> float:
	return MP_UNITS[clampi(realm, 0, MAX_REALM)]


## 每秒回复的倍数（air_caster 的 MP_REGEN 16 × 它）
static func mp_regen_k(realm: int) -> float:
	return mp_max(realm) / 100.0


## 玩家牌上显示的灵力（按 Realm.LIST 的 mp 换算：炼气 60 … 大乘 300）
static func mp_shown(realm: int, units: float) -> float:
	var r := clampi(realm, 0, MAX_REALM)
	return units * float(Realm.LIST[r]["mp"]) / mp_max(r)


# ---------- 技能 ----------
## 境界给技能（剑诀、连发、飞剑阵）每秒伤害的额外成长：结丹 1.0，每高一个境界 ×1.1（炼气 / 筑基按 1.1^r 往回推）
static func skill_g(realm: int) -> float:
	return pow(1.1, float(clampi(realm, 0, MAX_REALM) - 2))


## 连发（长按 E）每柄的伤害倍率（原来固定 0.3）：每秒伤害 = VOLLEY_DPS × skill_g（单位 / 秒），按该境界每秒出剑数折。
## VOLLEY_DPS 定 6.0：实测对着单个目标只有五到八成五的剑扎得中（散布），按 3.6 配的话打出来比白给的空中普攻（实测每秒 3.8 ~ 4.6 单位）还低
const VOLLEY_DPS := 6.0


static func volley_k(realm: int) -> float:
	var rate := float(Realm.LIST[clampi(realm, 0, MAX_REALM)]["volley"])
	return VOLLEY_DPS * skill_g(realm) / maxf(rate, 1.0)


## 飞剑阵（Q）每柄扎中的伤害倍率（原来 1.0）：单体每秒伤害 = 1.8 × 1.1^r（单位 / 秒），按出剑间隔 atk_cd 折；连斩（chain）是打群的额外收益
const Q_DPS := 1.8


static func q_k(realm: int) -> float:
	var r := clampi(realm, 0, MAX_REALM)
	return minf(Q_DPS * pow(1.1, float(r)) * float(Realm.LIST[r]["atk_cd"]), 1.0)


## 剑诀 Z / X / C 每次施放（全中）的目标总伤害（单位）：2 / 3 / 6 × skill_g；
## SKILL_K[境界][式] 是在游戏里实测各境界剑诀「全中」的总伤害后折出来的倍率（raid_pace_test.gd 的 --pace-combat）
const SKILL_TARGET: Array[float] = [2.0, 3.0, 6.0]
## 折算前各境界「全中」的总伤害（单位）：结丹 1.8 / 1.5 / 5.6（实测）、元婴 1.95 / 1.6 / 5.8、化神 1.9 / 1.8 / 6.4（Z / X 实测）、
## 炼虚 3.25 / 3.15 / 8.0（C 实测）、合体 2.1 / 3.85 / 5.6（X 实测）、大乘 2.4 / 5.6 / 10.4（Z 实测）；倍率 = 目标 × skill_g ÷ 它。
## 结丹 ~ 化神的 X 原来只有目标的一半（扣 18% 灵力、冷却 3.5 秒，打出来还不如 Z），翻一倍；合体 C 原来比 X 还低
const SKILL_K := [
	[1.0, 1.0, 1.0], [1.0, 1.0, 1.0],
	[1.11, 2.0, 1.07], [1.13, 2.06, 1.14], [1.27, 2.02, 1.13],
	[0.82, 1.27, 1.0], [1.39, 1.14, 1.57], [1.34, 0.86, 0.93],
]


static func skill_k(realm: int, i: int) -> float:
	return float((SKILL_K[clampi(realm, 0, MAX_REALM)] as Array)[clampi(i, 0, 2)])


## 地面连招（player_melee 的 ATK 表 9 / 11 / 17 / 8 / 9）：按炼气的 base 8 配的，换成倍率 × 当前境界的 base
const GROUND_REF := 8.0


static func ground_k(realm: int) -> float:
	return base(realm) / GROUND_REF


const BLOCK_CHIP := 0.15         # 地面格挡也擦掉这么多（和空战护体的 0.15 一样）


# ---------- 回复 ----------
const CALM_REGEN := 4.0          # 大世界里脱战（5 秒没掉血）在地面每秒回多少气血条（养法宝加成）；空中由空战自己的回复（6 / 秒）管，不叠加


# ---------- 首领 / PvP ----------
const BOSS_REF_REALM := 3        # 剑冢首领的 12000 血是按元婴配的


## 剑冢首领的血量倍数：按「该境界的 base × 技能成长」和元婴比，打的时间在各境界差不多（结丹约 7550；炼气 / 筑基进去会被临时拔到元婴）
static func boss_k(realm: int) -> float:
	var r := clampi(realm, 2, MAX_REALM)
	return base(r) * skill_g(r) / (base(BOSS_REF_REALM) * skill_g(BOSS_REF_REALM))


const PVP_HIT_CAP := 22.0        # 联机互殴：一下最多打掉对方 22 点气血条
const PVP_BURST := 30.0          # 同一个人短时间内最多连着打掉 30 点
const PVP_SUSTAIN := 25.0        # 之后每秒最多 25 点（高境界连发、飞剑阵剑多，单下封顶拦不住；这样从满血打死至少要三秒）


# ---------- 战力（玩家牌上给人看的总分） ----------
## 攻（攻击力 × 10 × 法宝「攻」）+ 守（气血 ÷ 法宝「守」的减伤，「养」略加），再乘境界给技能的成长 1.1^境界（「识」只给一点）。
## 以前乘的是 base(境界) / 8（大乘 ×13.75），可大世界里一招的伤害早就把 base 除掉了，显示的战力把境界夸大了十几倍
static func power(realm: int, lv: int, fx: Dictionary) -> int:
	var a := atk(lv) * (1.0 + minf(float(fx.get("atk", 0.0)), GEAR_ATK_CAP)) * 10.0
	var d := hp(lv) / maxf(1.0 - float(fx.get("guard", 0.0)), 0.4) * (1.0 + 0.2 * float(fx.get("vital", 0.0)))
	return int(round((a + d) * pow(1.1, float(clampi(realm, 0, MAX_REALM))) * (1.0 + 0.05 * float(fx.get("seek", 0.0)))))
