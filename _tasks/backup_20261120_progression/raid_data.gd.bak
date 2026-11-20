extends RefCounted
## 搜打撤（木兰草原开放世界）的数据表：区域、小怪 / Boss、物品、掉落、修为经验。纯数据 + 纯函数。
## 区域取材自《凡人修仙传》：木兰草原（出生地）· 黄枫谷 · 血色禁地 · 阴冥之地 · 坠魔谷，难度对应的修为逐级升高。
## 布局：出生点周围 R0 米内是草原；外面按方位分四个扇区 —— 北 黄枫谷、东 血色禁地、南 阴冥之地、西 坠魔谷。
## region_weights() 和 shaders/meadow_terrain.gdshader 里的区域染色是同一套算法。
## 故意不写 class_name：用 preload 引用。

const R0 := 420.0
const BLEND := 80.0
const PLAY_R := 1450.0       # 陆地的范围（怪、撤离点都在这以内）；再往外是外海
const BOUND_R := 1540.0      # 旧的活动边界（2026-11-20 起大世界不再用：改成循环世界了，见下面）
## 循环世界（2026-11-20）：整张图是一块边长 LOOP 的方块，上下、左右首尾相接——朝一个方向一直走 / 飞，会从对面的区域绕回来，
## 没有边界、没有空气墙。陆地都在中间半径 PLAY_R 的圆里；圆外到方块边缘是外海（和中间那片海一个样），接缝落在海里，看不出来。
## · 地形函数（block_world.gd）把坐标折回 [-HALF, HALF) 再算，所以主角的坐标可以一直涨下去，脚下的地形照样对得上
## · 地标（出生点 / 巢穴 / 传送阵）是固定位置的东西：用到它们的地方一律先取「离主角最近的那个像」（near）
## LOOP 必须是 96（地块）、6（远景格）、12 和 16（色块格）的整数倍。
const LOOP := 3456.0
const HALF := 1728.0
const COAST := 110.0         # 陆地沉进外海的过渡带有多宽


static func wrap(v: float) -> float:
	return wrapf(v, -HALF, HALF)


## 循环世界里的一个固定点 base，离 ref 最近的那个「像」（高度不变）
static func near(base: Vector3, ref: Vector3) -> Vector3:
	return Vector3(base.x + LOOP * roundf((ref.x - base.x) / LOOP), base.y, base.z + LOOP * roundf((ref.z - base.z) / LOOP))


static func near2(base: Vector2, ref: Vector2) -> Vector2:
	return Vector2(base.x + LOOP * roundf((ref.x - base.x) / LOOP), base.y + LOOP * roundf((ref.y - base.y) / LOOP))


## (x, z) 折回之后离世界中心多远（大于 PLAY_R 就是在外海上）
static func land_r(x: float, z: float) -> float:
	x = wrapf(x, -HALF, HALF)
	z = wrapf(z, -HALF, HALF)
	return sqrt(x * x + z * z)

## realm：建议修为（境界表下标）| lv：区域基础等级（怪的等级从这里起算）
## 地貌（各自从云海里立起来，见 block_world.gd）：草原 = 云上的层层草台；黄枫谷 = 赤岩峡谷和钙华彩池；血色禁地 = 落日下的残垒方山；
##   云梦山 = 云海石峰和落云宗；坠魔谷 = 紫雾裂谷和镇魔古殿（2026-11-20 按《凡人修仙传》天南的五张参考图重做过）
## sun_alt：日头的仰角（度；傍晚 / 日落的区域很低，影子拉得长）| sun_size：天上日轮的大小倍数 | sun_az：日头在哪个方位（x, z）
## top / top2：地表方块两种色 | dirt：土 | stone：岩石 / 石板 | water：低处填的东西的颜色（海水 / 溪水 / 血河 / 云海 / 魔雾），water_e 自发光强度（崖壁的岩层色在 block_world.gd 里）
## water_h：云面基准高度 | sky_top / sky_hor：天顶 / 天际 | sky_cloud：天上云的多少 | fog / fog_d：雾色和浓度 | amb / amb_e：环境光 | sun / sun_e：主光
## light：灯火 / 晶体的发光色 | mote：空中飘浮物的颜色 | dir：扇区方向（草原无）| mobs / boss：怪物种类下标
const REGIONS := [
	{"name": "木兰草原", "sub": "滨水台地 · 天南城", "realm": 0, "lv": 1,
	 "top": Color(0.50, 0.62, 0.26), "top2": Color(0.64, 0.70, 0.32), "dirt": Color(0.86, 0.52, 0.22), "stone": Color(0.66, 0.63, 0.64),
	 "water": Color(0.18, 0.60, 0.68), "water_e": 0.04, "water_h": 0.0,
	 "sky_top": Color(0.50, 0.62, 0.88), "sky_hor": Color(1.0, 0.82, 0.64), "fog": Color(0.98, 0.86, 0.76), "fog_d": 0.0006,
	 "amb": Color(0.86, 0.84, 0.86), "amb_e": 0.85, "sun": Color(1.0, 0.92, 0.76), "sun_e": 1.55, "sky_cloud": 0.45,
	 "sun_alt": 34.0, "sun_size": 1.0, "sun_az": Vector2(0.69, 0.72),
	 "light": Color(1.0, 0.68, 0.3), "mote": Color(1.0, 0.8, 0.92),
	 "dir": Vector2.ZERO, "mobs": [0, 1], "boss": 10},
	{"name": "黄枫谷", "sub": "金枫石台 · 黄枫宗门", "realm": 2, "lv": 6,
	 "top": Color(0.52, 0.56, 0.22), "top2": Color(0.74, 0.62, 0.20), "dirt": Color(0.70, 0.44, 0.22), "stone": Color(0.58, 0.56, 0.57),
	 "water": Color(0.24, 0.64, 0.70), "water_e": 0.06, "water_h": 0.0,
	 "sky_top": Color(0.46, 0.36, 0.64), "sky_hor": Color(1.0, 0.66, 0.36), "fog": Color(1.0, 0.74, 0.54), "fog_d": 0.0011,
	 "amb": Color(0.88, 0.72, 0.72), "amb_e": 0.8, "sun": Color(1.0, 0.72, 0.42), "sun_e": 1.75, "sky_cloud": 0.55,
	 "sun_alt": 17.0, "sun_size": 2.6, "sun_az": Vector2(-0.64, -0.77),
	 "light": Color(1.0, 0.62, 0.24), "mote": Color(1.0, 0.58, 0.18),
	 "dir": Vector2(0, -1), "mobs": [2, 3], "boss": 11},
	{"name": "血色禁地", "sub": "赤红荒原 · 上古禁制", "realm": 3, "lv": 10,
	 "top": Color(0.46, 0.12, 0.14), "top2": Color(0.60, 0.17, 0.16), "dirt": Color(0.40, 0.16, 0.15), "stone": Color(0.39, 0.36, 0.40),
	 "water": Color(0.92, 0.20, 0.09), "water_e": 0.8, "water_h": 0.0,
	 "sky_top": Color(0.22, 0.08, 0.20), "sky_hor": Color(0.98, 0.38, 0.19), "fog": Color(0.64, 0.28, 0.27), "fog_d": 0.0010,
	 "amb": Color(0.66, 0.57, 0.70), "amb_e": 0.9, "sun": Color(1.0, 0.62, 0.42), "sun_e": 1.3, "sky_cloud": 0.7,
	 "sun_alt": 15.0, "sun_size": 4.0, "sun_az": Vector2(0.97, 0.24),
	 "light": Color(1.0, 0.42, 0.14), "mote": Color(1.0, 0.3, 0.2),
	 "dir": Vector2(1, 0), "mobs": [4, 5], "boss": 12},
	{"name": "云梦山", "sub": "云海石峰 · 落云宗", "realm": 4, "lv": 13,
	 "top": Color(0.24, 0.50, 0.22), "top2": Color(0.38, 0.60, 0.26), "dirt": Color(0.58, 0.42, 0.24), "stone": Color(0.70, 0.70, 0.72),
	 "water": Color(0.97, 0.98, 1.0), "water_e": 0.14, "water_h": 0.0,
	 "sky_top": Color(0.30, 0.50, 0.90), "sky_hor": Color(0.99, 0.90, 0.86), "fog": Color(0.86, 0.90, 0.98), "fog_d": 0.0009,
	 "amb": Color(0.82, 0.86, 0.94), "amb_e": 0.9, "sun": Color(1.0, 0.95, 0.82), "sun_e": 1.55, "sky_cloud": 0.6,
	 "sun_alt": 27.0, "sun_size": 1.6, "sun_az": Vector2(-0.5, 0.87),
	 "light": Color(1.0, 0.80, 0.40), "mote": Color(1.0, 0.95, 0.9),
	 "dir": Vector2(0, 1), "mobs": [6, 7], "boss": 13},
	{"name": "坠魔谷", "sub": "紫雾裂谷 · 镇魔古殿", "realm": 5, "lv": 16,
	 "top": Color(0.33, 0.30, 0.45), "top2": Color(0.50, 0.17, 0.23), "dirt": Color(0.27, 0.24, 0.38), "stone": Color(0.33, 0.30, 0.44),
	 "water": Color(0.35, 0.29, 0.53), "water_e": 0.16, "water_h": 0.0,
	 "sky_top": Color(0.10, 0.07, 0.21), "sky_hor": Color(0.44, 0.30, 0.66), "fog": Color(0.36, 0.28, 0.56), "fog_d": 0.0013,
	 "amb": Color(0.60, 0.58, 0.86), "amb_e": 0.86, "sun": Color(0.90, 0.82, 1.0), "sun_e": 1.2, "sky_cloud": 0.95,
	 "sun_alt": 52.0, "sun_size": 0.6, "sun_az": Vector2(-0.8, 0.6),
	 "light": Color(0.75, 0.35, 1.0), "mote": Color(0.8, 0.5, 1.0),
	 "dir": Vector2(-1, 0), "mobs": [8, 9], "boss": 14},
]

## 坠魔谷深处（魔渊）的天色：由云阙的晴空渐变过来（见 storm_k）
const STORM := {"sky_top": Color(0.10, 0.07, 0.21), "sky_hor": Color(0.44, 0.30, 0.66), "fog": Color(0.36, 0.28, 0.56), "fog_d": 0.0013,
	"amb": Color(0.60, 0.58, 0.86), "amb_e": 0.86, "sun": Color(0.90, 0.82, 1.0), "sun_e": 1.2, "sky_cloud": 0.95, "mote": Color(0.8, 0.5, 1.0)}

## 各区域「看得清」的一组参数（和 REGIONS 一一对应，raid_manager.gd 的 _blend_atmosphere 按主角位置渐变）。
## 暗的区域（血色禁地 / 坠魔谷）靠这组参数保证：影子里不死黑、地面的起伏看得出来、怪不会融进背景；氛围交给天色、雾色和色相，不靠把画面压黑。
## shadow：影子浓度（1 = 影子里一点主光都没有）| fill：不受影子影响的补光（背着日头的那一侧更强；乘在地表底色上，线性值）
## hemi_s / hemi_g：朝上 / 朝下的面各染一点什么色 | expo / sat / con：曝光、饱和度、对比度 | ao：屏幕空间遮蔽的强度（桌面档才有）
## rim / rim_col：所有小怪身上的一圈轮廓光（亮的区域不需要，是 0）| vortex：天上的魔气漩涡
const LOOK := [
	{"shadow": 0.86, "fill": Color(0.0, 0.0, 0.0), "hemi_s": Color(1.0, 1.0, 1.0), "hemi_g": Color(0.84, 0.84, 0.88),
	 "expo": 1.05, "sat": 1.16, "con": 1.1, "ao": 1.3, "rim": 0.0, "rim_col": Color(1.0, 1.0, 1.0), "vortex": 0.0},
	{"shadow": 0.86, "fill": Color(0.0, 0.0, 0.0), "hemi_s": Color(1.0, 1.0, 1.0), "hemi_g": Color(0.84, 0.84, 0.88),
	 "expo": 1.05, "sat": 1.16, "con": 1.1, "ao": 1.3, "rim": 0.0, "rim_col": Color(1.0, 1.0, 1.0), "vortex": 0.0},
	{"shadow": 0.66, "fill": Color(0.12, 0.08, 0.16), "hemi_s": Color(1.0, 0.97, 0.98), "hemi_g": Color(0.84, 0.76, 0.90),
	 "expo": 1.04, "sat": 1.0, "con": 1.06, "ao": 0.9, "rim": 0.32, "rim_col": Color(1.0, 0.80, 0.52), "vortex": 0.0},
	{"shadow": 0.86, "fill": Color(0.0, 0.0, 0.0), "hemi_s": Color(1.0, 1.0, 1.0), "hemi_g": Color(0.84, 0.84, 0.88),
	 "expo": 1.05, "sat": 1.16, "con": 1.1, "ao": 1.3, "rim": 0.0, "rim_col": Color(1.0, 1.0, 1.0), "vortex": 0.0},
	{"shadow": 0.6, "fill": Color(0.10, 0.10, 0.20), "hemi_s": Color(0.98, 0.98, 1.0), "hemi_g": Color(0.80, 0.78, 0.94),
	 "expo": 1.02, "sat": 1.08, "con": 1.06, "ao": 0.9, "rim": 0.36, "rim_col": Color(0.66, 0.84, 1.0), "vortex": 1.0},
]


## 坠魔谷由内到外：0 云阙 → 1 魔渊（和 block_world.gd 的 _storm 同一条线）
static func storm_k(x: float, z: float) -> float:
	return smoothstep(540.0, 660.0, land_r(x, z)) * region_weights(x, z)[4]

# ---------- 数值（取自《雨中冒险2数值体系完整合订本》的核心公式） ----------
## 等级成长：属性 = 基础 + 每级成长 ×(等级-1)；每级生命 = 基础 ×0.3，每级伤害 = 基础 ×0.2
## 升级累计经验：20×(1.55^(L-1) - 1)/0.55
## 难度系数：C = (1 + 0.0506 × 难度参数 × 完整分钟数) × 1.15^已击败的区域 Boss 数；环境等级 = 1 + (C连续 - 1)/0.33
## 刷怪导演：每秒攒点数，按怪的点数花掉；精英 = 点数 ×6、生命 ×4、伤害 ×2
## 价格：基础 × C^1.25（这里用在箱子里物品的价值上：拖得越久越值钱）
const DIFF_S := 2.0              # 难度参数（细雨 1 / 暴雨 2 / 季风 3），取暴雨
const PLAYER_HP := 110.0
const PLAYER_DMG := 12.0
const LV_PER_REALM := 3          # 每 3 级突破一个大境界
const ELITE_COST := 6.0
const ELITE_HP := 3.0            # 2026-11-20 收了一档：原来 4.0 / 2.0
const ELITE_DMG := 1.5
## 2026-11-20 整体削弱（用户反馈：大世界里的怪和修士太强）：
const MOB_DMG := 0.8             # 所有怪（含首领）的伤害再乘这个
const RIVAL_HP := 260.0          # 其他修士的 1 级气血（原来 380）
const RIVAL_DMG := 0.42          # 其他修士打主角的伤害倍率（原来 0.6）
const RIVAL_SKILL := 0.35        # 其他修士的水平 0 ~ 1（原来 0.5：读招、瞬身、抢攻都按它来）
const DIFF_NAMES := ["风平浪静", "暗流涌动", "妖气渐浓", "群魔乱舞", "劫云压顶", "万劫不复"]
const DIFF_COLORS: Array[Color] = [Color(0.5, 0.95, 0.6), Color(0.95, 0.9, 0.4), Color(1.0, 0.65, 0.3), Color(1.0, 0.4, 0.3),
		Color(0.95, 0.25, 0.5), Color(0.8, 0.3, 1.0)]


static func coeff(sec: float, clears: int, whole_minutes := true) -> float:
	var m := floorf(sec / 60.0) if whole_minutes else sec / 60.0
	return (1.0 + 0.0506 * DIFF_S * m) * pow(1.15, float(clears))


## 环境等级（怪在区域基础等级上再加这么多级 - 1）
static func ambient_level(sec: float, clears: int) -> float:
	return minf(1.0 + (coeff(sec, clears, false) - 1.0) / 0.33, 99.0)


static func diff_tier(c: float) -> int:
	return clampi(int((c - 1.0) / 0.55), 0, DIFF_NAMES.size() - 1)


static func stat(base: float, per_level_k: float, lv: int) -> float:
	return base + base * per_level_k * float(lv - 1)


static func xp_total(lv: int) -> float:
	return floorf(20.0 * (pow(1.55, float(lv - 1)) - 1.0) / 0.55)


static func xp_need(lv: int) -> float:
	return xp_total(lv + 1) - xp_total(lv)


## 击杀 lv 级的怪给的经验：同级小怪约 8 只升一级
static func xp_reward(lv: int, k: float) -> float:
	return xp_need(lv) / 8.0 * k


static func scaled_value(base: float, c: float) -> int:
	return int(base * pow(c, 1.25))


# ---------- 地标（地形生成和玩法管理器共用，位置写死） ----------
## kind：spawn 出生点 | boss 区域 Boss 巢穴 | extract 传送阵；r 内压平，再过 blend 米过渡回原地形
static func pois() -> Array:
	var out: Array = [{"kind": "spawn", "region": 0, "pos": Vector2.ZERO, "r": 10.0, "blend": 26.0},
			{"kind": "boss", "region": 0, "pos": Vector2(-210.0, 170.0), "r": 26.0, "blend": 30.0},
			{"kind": "extract", "region": 0, "pos": Vector2(250.0, -150.0), "r": 12.0, "blend": 20.0}]
	for i in range(1, 5):
		var d: Vector2 = REGIONS[i]["dir"]
		out.append({"kind": "boss", "region": i, "pos": d * 1020.0, "r": 30.0, "blend": 36.0})
		out.append({"kind": "extract", "region": i, "pos": d.rotated(0.5 if i % 2 == 0 else -0.5) * 800.0, "r": 12.0, "blend": 20.0})
	return out


## 小怪 / Boss。shape：beast 四足兽 | floater 浮空 | brute 人形巨汉
## hp / atk：倍率（× SHAPE_BASE 里该体型的 1 级基础值）| spd 移速 | size 体型 | ranged 远程 | cols [主色, 副色, 眼 / 发光色]
## model：assets/creatures 里的模型名（creature_model.gd）；elite_model / elite_name：精英换的模型和名字（没有就用原模型放大）
## mh：模型包围盒里算作身高的比例（翅膀扬得很高的）| mk：模型额外放大 | fly：不是浮空体型但悬在半空
## 体型基础值 [生命, 伤害, 导演点数, 经验系数]：主角 1 级一下 100% 伤害的招式打 12
const SHAPE_BASE := {"beast": [48.0, 12.0, 10.0, 1.0], "floater": [36.0, 9.0, 9.0, 0.9], "brute": [150.0, 16.0, 26.0, 2.4]}
const BOSS_HP := 70.0            # Boss 的 1 级生命 = BOSS_HP × hp 倍率
const BOSS_DMG := 14.0
const MOBS := [
	{"name": "草原妖狼", "shape": "beast", "hp": 1.0, "atk": 1.0, "spd": 7.5, "size": 1.0, "ranged": false,
	 "model": "wolf_grey", "elite_model": "wolf_sand", "elite_name": "棘背妖狼",
	 "cols": [Color(0.5, 0.5, 0.52), Color(0.32, 0.32, 0.36), Color(1.0, 0.85, 0.3)]},
	{"name": "噬金虫", "shape": "floater", "hp": 0.6, "atk": 0.7, "spd": 6.0, "size": 0.7, "ranged": true,
	 "model": "bee", "elite_model": "firefly", "elite_name": "噬金虫王",
	 "cols": [Color(0.85, 0.7, 0.25), Color(0.5, 0.4, 0.15), Color(1.0, 0.95, 0.5)]},
	{"name": "枫林傀儡", "shape": "brute", "hp": 1.3, "atk": 1.1, "spd": 5.0, "size": 1.1, "ranged": false,
	 "model": "scarecrow", "elite_model": "sand_guard", "elite_name": "金甲傀儡",
	 "cols": [Color(0.55, 0.36, 0.22), Color(0.36, 0.24, 0.16), Color(1.0, 0.5, 0.2)]},
	{"name": "赤火蝠", "shape": "floater", "hp": 0.7, "atk": 0.9, "spd": 8.0, "size": 0.8, "ranged": true,
	 "model": "bat",
	 "cols": [Color(0.7, 0.22, 0.14), Color(0.3, 0.12, 0.1), Color(1.0, 0.7, 0.2)]},
	{"name": "血线毒蝎", "shape": "beast", "hp": 1.2, "atk": 1.2, "spd": 8.5, "size": 1.25, "ranged": false,
	 "model": "scorpion",
	 "cols": [Color(0.5, 0.1, 0.12), Color(0.2, 0.06, 0.08), Color(1.0, 0.3, 0.3)]},
	{"name": "腐尸傀", "shape": "brute", "hp": 1.5, "atk": 1.1, "spd": 4.5, "size": 1.2, "ranged": false,
	 "model": "void_merc", "elite_model": "butcher", "elite_name": "血屠尸傀",
	 "cols": [Color(0.4, 0.44, 0.34), Color(0.26, 0.2, 0.2), Color(0.8, 1.0, 0.4)]},
	{"name": "阴冥兽", "shape": "beast", "hp": 1.3, "atk": 1.3, "spd": 9.0, "size": 1.3, "ranged": false,
	 "model": "panther_void",
	 "cols": [Color(0.2, 0.26, 0.32), Color(0.1, 0.12, 0.16), Color(0.5, 0.9, 1.0)]},
	{"name": "鬼雾幽魂", "shape": "floater", "hp": 0.8, "atk": 1.1, "spd": 7.0, "size": 1.1, "ranged": true,
	 "model": "void_apostle", "elite_model": "eye_small", "elite_name": "冥瞳",
	 "cols": [Color(0.7, 0.82, 0.88), Color(0.36, 0.46, 0.54), Color(0.5, 1.0, 0.9)]},
	{"name": "裂风兽", "shape": "beast", "hp": 1.4, "atk": 1.4, "spd": 11.0, "size": 1.35, "ranged": false,
	 "model": "fox_void",
	 "cols": [Color(0.4, 0.3, 0.56), Color(0.2, 0.14, 0.3), Color(0.9, 0.6, 1.0)]},
	{"name": "古魔傀影", "shape": "brute", "hp": 1.7, "atk": 1.4, "spd": 6.0, "size": 1.3, "ranged": true,
	 "model": "crystal_golem",
	 "cols": [Color(0.24, 0.16, 0.34), Color(0.12, 0.08, 0.18), Color(1.0, 0.4, 0.9)]},
	# ---- Boss（每个区域一头，守在巢穴）----
	{"name": "啸月狼王", "shape": "beast", "hp": 14.0, "atk": 1.8, "spd": 9.0, "size": 2.8, "ranged": false, "boss": true,
	 "model": "wolf_void",
	 "cols": [Color(0.82, 0.84, 0.9), Color(0.4, 0.42, 0.5), Color(0.5, 0.8, 1.0)]},
	{"name": "巨猿傀儡", "shape": "brute", "hp": 16.0, "atk": 1.9, "spd": 6.0, "size": 3.0, "ranged": false, "boss": true,
	 "model": "lava_giant",
	 "cols": [Color(0.6, 0.38, 0.2), Color(0.34, 0.2, 0.12), Color(1.0, 0.55, 0.15)]},
	{"name": "墨蛟", "shape": "beast", "hp": 18.0, "atk": 2.0, "spd": 9.5, "size": 3.4, "ranged": true, "boss": true,
	 "model": "black_dragon", "mh": 0.45, "fly": true,
	 "cols": [Color(0.12, 0.12, 0.16), Color(0.3, 0.06, 0.08), Color(1.0, 0.25, 0.2)]},
	{"name": "阴冥兽王", "shape": "beast", "hp": 20.0, "atk": 2.1, "spd": 10.0, "size": 3.4, "ranged": true, "boss": true,
	 "model": "ice_guard", "mk": 1.25,
	 "cols": [Color(0.16, 0.22, 0.3), Color(0.06, 0.08, 0.12), Color(0.4, 1.0, 1.0)]},
	{"name": "古魔分魂", "shape": "brute", "hp": 24.0, "atk": 2.3, "spd": 7.5, "size": 3.6, "ranged": true, "boss": true,
	 "model": "bull_king",
	 "cols": [Color(0.2, 0.1, 0.3), Color(0.08, 0.04, 0.12), Color(1.0, 0.3, 0.8)]},
]

## 品阶：凡品 / 灵器 / 法宝 / 古宝 / 通天灵宝
const TIER_NAMES := ["凡品", "灵器", "法宝", "古宝", "通天灵宝"]
const TIER_COLORS: Array[Color] = [Color(0.78, 0.8, 0.84), Color(0.4, 0.9, 0.5), Color(0.35, 0.65, 1.0),
		Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3)]
const TIER_VALUE := [30, 120, 480, 1800, 7500]
## 法宝名（每个品阶四件；带被动的完整表在 raid_items.gd 的 GEAR，这里只给 roll_tier 数件数）
const GEAR := [
	["铁木剑", "青钢盾", "寻灵罗盘", "温玉佩"],
	["金蚨子母刃", "青蛟旗", "照妖镜", "神风舟"],
	["青竹蜂云剑", "玄龟甲", "天目灵珠", "风雷翅"],
	["血魔剑", "八灵尺", "虚天鼎残片", "养魂木"],
	["玄天斩灵剑", "元磁神山", "虚天鼎", "掌天瓶"],
]
const MATS := ["妖狼内丹", "枫木灵芯", "蛟血晶", "阴冥石", "古魔残骨"]
const BAG_SIZE := 12             # 背包的格数（灵材占 2 格，见 raid_items.gd 的 size_of）
## 各境界主角的伤害基准（同 Realm.LIST 的 dmg）：怪的血量按区域建议修为的伤害来定
const REALM_DMG := [8.0, 12.0, 18.0, 26.0, 38.0, 52.0, 75.0, 110.0]
const AI_NAMES := ["散修·韩立", "黄枫谷·陈巧倩", "灵兽山·钟吾", "掩月宗·南宫", "鬼灵门·王蝉", "化刀坞·封岳", "天阙堡·宋蒙", "乱星海·曲魂",
		"巨剑门·厉飞", "清虚门·浮云", "灵兽山·菡云", "散修·墨大夫", "御灵宗·柳眉", "魔焰门·孙火", "合欢宗·云露", "千竹教·林师兄"]


## 五个区域在 (x, z) 处的权重（和为 1）
static func region_weights(x: float, z: float) -> PackedFloat32Array:
	var w := PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])
	x = wrapf(x, -HALF, HALF)
	z = wrapf(z, -HALF, HALF)
	var r := sqrt(x * x + z * z)
	# 出了陆地就是外海：天色、海色都回到和中间那片海一样（方块的四条边都在外海里，循环的接缝两边自然是同一个样）
	var outer := smoothstep(R0 - BLEND, R0 + BLEND, r) * (1.0 - smoothstep(PLAY_R + 10.0, PLAY_R + COAST + 60.0, r))
	if outer <= 0.0:
		return w
	var dx := x / maxf(r, 1.0)
	var dz := z / maxf(r, 1.0)
	var s := [smoothstep(0.55, 0.85, -dz), smoothstep(0.55, 0.85, dx), smoothstep(0.55, 0.85, dz), smoothstep(0.55, 0.85, -dx)]
	var sum := 1e-4
	for v: float in s:
		sum += v
	w[0] = 1.0 - outer
	for i in 4:
		w[i + 1] = outer * float(s[i]) / sum
	return w


## (x, z) 所在的区域（权重最大的）
static func region_at(x: float, z: float) -> int:
	var w := region_weights(x, z)
	var best := 0
	for i in range(1, 5):
		if w[i] > w[best]:
			best = i
	return best


## 区域中心（扇区方向上 r 米处）
static func region_point(idx: int, r: float) -> Vector2:
	var d: Vector2 = REGIONS[idx]["dir"]
	return d * r


## 物品都由 raid_items.gd 造（运行时 load：两个脚本互相 preload 会成环）
static func _items() -> GDScript:
	return load("res://scripts/raid_items.gd")


static func make_gear(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	return _items().rand_gear(tier, rng)


static func make_pill(tier: int) -> Dictionary:
	return _items().pill(tier)


static func make_mat(region: int) -> Dictionary:
	return _items().mat(region)


## 抽一个品阶：单件权重 × 该品阶的件数（合订本「基础掉落表」的算法），luck = 区域序号 + 箱子加成，每点把每高一阶的权重再乘 1.6
const TIER_W := [1.0, 0.2, 0.04, 0.008, 0.0015]
static func roll_tier(level: int, rng: RandomNumberGenerator, bonus := 0.0) -> int:
	var luck := float(level) + bonus
	var ws: Array[float] = []
	var acc := 0.0
	for t in 5:
		var wv := float(TIER_W[t]) * float((GEAR[t] as Array).size()) * pow(1.6, luck * float(t))
		ws.append(wv)
		acc += wv
	var x := rng.randf() * acc
	for t in 5:
		x -= ws[t]
		if x <= 0.0:
			return t
	return 0


## 一次掉落：n 件，丹药 / 法宝 / 灵材 / 灵草 / 符箓 / 偶尔破境丹（raid_items.gd 的 roll）
static func roll_loot(level: int, n: int, rng: RandomNumberGenerator, bonus := 0.0) -> Array:
	return _items().roll(level, n, rng, bonus)


## 往 SurfaceTool 里加一个顶点色方块（点缀物、小怪的合并网格都用它）
static func add_box(st: SurfaceTool, size: Vector3, xf: Transform3D, col: Color) -> void:
	var h := size * 0.5
	var c := MeshLib.vcol(col)
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var q: Array[Vector3] = []
		for sg: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			q.append(xf * ((n + u * sg.x + v * sg.y) * h))
		var wn := (xf.basis * n).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.set_color(c)
			st.add_vertex(q[k])


## 指向日头的方向（单位向量）：按区域的 sun_az / sun_alt
static func sun_to(idx: int) -> Vector3:
	var r: Dictionary = REGIONS[idx]
	var az: Vector2 = (r["sun_az"] as Vector2).normalized()
	var e := deg_to_rad(float(r["sun_alt"]))
	return Vector3(az.x * cos(e), sin(e), az.y * cos(e))
