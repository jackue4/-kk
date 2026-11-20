extends EnemyDummy
## 剑冢 Boss「血河剑魔 · 厉沧溟」（元婴初期）：一头方块搭成的血河魔像（参考 _ref/boss_voxel.jpg）——
## 深紫、近黑的甲块层层堆出佝偻的巨躯，骨白的双角、獠牙、爪与脚趾，胸口嵌着发光的魔婴核（也是索敌瞄准点），
## 赤色裂痕从核心爬满胸腹和四肢，赤目，肩背竖着骨刺，腰间金带回纹扣，身后一条带刺的长尾。
## 沉睡时立在剑冢正中（脚踏地面、弓背垂首），开战一蹬升空；悬空时腿、尾照样搭全，只是收腿垂尾。
## 继承 EnemyDummy：飞剑阵、空战法术、大罡剑阵的索敌 / 伤害都走现成的 aim_point() / take_hit()，不用另接。
##
## 状态：DORMANT 立地垂首闭目（不可索敌）→ INTRO 睁眼、蹬地升空、骨刺竖起、一声魔啸 → FIGHT 随机出弹幕 →
## SHIFT 转阶段（护体无伤、清屏、换色）→ ... → DYING 定格碎裂 → DEAD。
## 三阶段（血量 70% / 35% 分界），每阶段从自己的招式池里随机挑招，不连续重复：
##   一阶「血河剑雨」：锁定扇射针弹、锥环花弹、九刺锁魂（肩背骨刺尖悬停后锁定射出）、魔婴吐珠（大玉炸裂）
##   二阶「魔婴出窍」：上面加强 + 螺旋涡流、双蛇缠（两道弧线流交汇在你当时的位置）
##   三阶「血海无涯」：血海天幕（留缺口的弹幕墙）、血莲万瓣（扭转的锥环）、加密螺旋，且常常两招叠放，
##                     平时还有骨刺零散点射
## 招式底下还垫着一层「血河底流」：魔婴核一直朝你所在方向旋着吐几道大锥角慢弹，像一条朝你卷来的弹幕隧道，
## 画面里始终铺着弹，阶段越高旋臂越多、越密。
## 所有"锁定"都是锁玩家出招那一刻的位置（不追踪），躲法是横移 / 闪现（Shift 闪现全程无敌，可穿弹）。
## 招式用时间表驱动：出招时把每一波排进 _jobs，_process 到点执行——转阶段 / 击败时清空即可，不留协程。
##
## 造型：每个部件下的方块按材质（甲 / 金 / 裂光）各烘成一个 MultiMesh（甲块颜色走实例色），
## 方块清单存在 meta "blocks" 里，碎裂时按当前姿势把每块切成小方块崩开。

signal phase_changed(idx: int)
signal defeated
signal roared

const Sfx := preload("res://scripts/sfx.gd")
const Combat := preload("res://scripts/combat.gd")
const CombatWord := preload("res://scripts/combat_word.gd")
const Bullets := preload("res://scripts/boss_bullets.gd")

const NAME := "厉沧溟"
const TITLE := "血河剑魔"
const RANK := "元婴初期"
const HP_MAX := 12000.0
const PHASE_AT := [0.7, 0.35]
const PHASE_NAMES := ["血河剑雨", "魔婴出窍", "血海无涯"]
const PHASE_TAGS := ["一阶", "二阶", "三阶"]
## 每阶段的弹色（sRGB）：主色 / 副色 / 点缀，彼此反差大、在灰白大厅里一眼分得清
const PAL := [
	[Color(1.0, 0.2, 0.25), Color(1.0, 0.56, 0.16), Color(1.0, 0.3, 0.72)],
	[Color(0.72, 0.32, 1.0), Color(1.0, 0.36, 0.74), Color(0.34, 0.76, 1.0)],
	[Color(1.0, 0.82, 0.3), Color(1.0, 0.2, 0.3), Color(0.34, 0.9, 1.0)],
]
## 身上裂痕 / 赤目的光：始终是赤色一系（一阶熔赤、二阶血红偏玫、三阶熔金赤）
const CRACK := [Color(1.0, 0.24, 0.1), Color(1.0, 0.16, 0.36), Color(1.0, 0.46, 0.12)]
## 甲块配色（sRGB）：深紫 / 近黑带灰的紫黑 / 骨白 / 暗金
const PURP := [Color(0.38, 0.21, 0.52), Color(0.3, 0.16, 0.43), Color(0.46, 0.27, 0.6), Color(0.24, 0.13, 0.34)]
const DARK := [Color(0.11, 0.08, 0.14), Color(0.17, 0.13, 0.21), Color(0.25, 0.21, 0.29), Color(0.32, 0.28, 0.37)]
const BONE := [Color(0.9, 0.86, 0.78), Color(0.8, 0.75, 0.67), Color(0.95, 0.92, 0.86)]
const GOLD := Color(0.78, 0.6, 0.3)
const POOLS := [
	["fan", "ring", "swords", "orbs"],
	["fan", "ring", "swords", "orbs", "spiral", "curve"],
	["wall", "rose", "spiral", "orbs", "curve", "fan", "swords"],
]
const GAP := [1.0, 0.7, 0.45]       # 两招之间的喘息
const SPD := [1.0, 1.15, 1.3]       # 弹速倍率
const DMG := [8.0, 10.0, 12.0]      # 每颗弹的伤害（玩家护体 100）
const AMB_STEP := [0.16, 0.13, 0.11]  # 血河底流：每隔这么久吐一圈旋臂
const AMB_CONE := 36.0                # 底流锥角（度）：弹从你身边四周掠过，正中留出躲闪的空当
const SCALE := 1.35                 # 整体放大：造型按约二十五个单位搭（脚底到角尖），放大后三十多米
const FOOT := 15.1                  # 节点原点（胸口）到脚底的距离（放大前）
const WAIST := Vector3(0.0, -2.4, 0.4)  # 弓背 / 挺身的腰部枢轴
const DORMANT_H := FOOT * SCALE     # 沉睡：脚踏剑冢地面
const FIGHT_H := 30.0               # 战斗时离地高度（以节点原点计，脚底约在九米高处）
const KEEP_DIST := 32.0             # 和玩家保持的水平距离
const ROAM_R := 44.0                # 不离开剑冢中心这么远
const CONTACT_R := 6.0 * SCALE      # 贴身撞上魔婴核的判定

enum S { DORMANT, INTRO, FIGHT, SHIFT, DYING, DEAD }

var player: Player
var bullets: Bullets
var center := Vector3.ZERO   # 剑冢中心（地面）
var state := S.DORMANT
var phase := 0

var _clock := 0.0
var _state_t := 0.0
var _jobs: Array = []        # [到点时刻, Callable]
var _next_at := 0.0
var _last_pat := ""
var _pepper := 0.0           # 三阶零散点射计时
var _amb := 0.0              # 血河底流计时
var _amb_phi := 0.0          # 底流旋臂的当前相位
var _axis := Vector3.FORWARD # 螺旋涡流当前锁定的轴
var _cast_k := 0.0           # 出招发力（出招时拉满，随后回落）
var _wake := 0.0             # 0 沉睡姿态 ↔ 1 战斗姿态（平滑过渡）
var _yaw := 0.0
var _rest_yaw := 0.0         # 沉睡时面朝的方向（剑冢入口）
var _roam := 0.0
var _vel := Vector3.ZERO
var _guard_fx := 0.0
var _crack := 0.0
var _flash_b := 0.0
var _death_dir := Vector3.FORWARD

var _root: Node3D            # 整个造型（受击后坐、颤抖都动它）
var _torso: Node3D           # 腰部枢轴：上身、头、双臂都挂在下面
var _pelvis: Node3D          # 胯：腰带、布摆、双腿、尾巴
var _head: Node3D
var _core: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _legs: Array[Node3D] = []     # 大腿（左、右）
var _shins: Array[Node3D] = []    # 小腿连脚
var _tail: Array[Node3D] = []     # 尾巴一节节串下去
var _tail_rest: Array[Vector3] = []
var _tatters: Array[Node3D] = []  # 腰下前后的布摆
var _spikes: Array[Node3D] = []   # 九根出弹骨刺（左肩三、右肩三、背三）：局部 +Y 朝外，meta "len" 为刺长
var _eyes: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _m_body: StandardMaterial3D
var _m_gold: StandardMaterial3D
var _m_glow: StandardMaterial3D
var _m_core: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _blocks := {}            # 部件 Node3D -> {"body"/"gold"/"glow": [[Transform3D, 尺寸, 颜色], ...]}


func _ready() -> void:
	add_to_group("enemies")
	kind = 3
	max_hp = HP_MAX
	hp = HP_MAX
	alive = false
	home = position
	scale = Vector3.ONE * SCALE
	_build()
	_apply_palette()
	_pose_dormant(1.0)


# ---------- 造型 ----------

static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


## 甲 / 金饰用的材质：颜色走 MultiMesh 实例色；自发光留给受击闪白
static func _vc_mat(rough: float, metal: float, glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 0.0
	return m


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _pick(pal: Array) -> Color:
	return pal[_rng.randi() % pal.size()]


## 记一块方块（部件局部坐标），_bake 时按材质烘成 MultiMesh
func _put(part: Node3D, key: String, xf: Transform3D, size: Vector3, col: Color) -> void:
	if not _blocks.has(part):
		_blocks[part] = {}
	var d: Dictionary = _blocks[part]
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append([xf, size, col])


func _blk(part: Node3D, key: String, pos: Vector3, size: Vector3, col: Color, rot_deg := Vector3.ZERO) -> void:
	_put(part, key, Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), size, col)


## 一块甲：近黑的芯块 + 表面一层随机凸起的小方块（颜色取自 pal），做出参考图里层层叠叠、边缘参差的体素甲面。
## skip 里列出的面不贴（"-y" = 底面），dens 为每平方单位贴几块
func _chunk(part: Node3D, c: Vector3, s: Vector3, pal: Array, dens := 0.42, skip := "-y") -> void:
	_blk(part, "body", c, s, DARK[0])
	var u0 := clampf(minf(s.x, minf(s.y, s.z)) * 0.3, 0.35, 1.05)
	for ax in 3:
		for sg: float in [-1.0, 1.0]:
			if skip.contains(("-" if sg < 0.0 else "+") + "xyz"[ax]):
				continue
			var o1 := (ax + 1) % 3
			var o2 := (ax + 2) % 3
			var n := int(s[o1] * s[o2] * dens + _rng.randf())
			for i in n:
				var u := u0 * _rng.randf_range(0.75, 1.3)
				var t := u * _rng.randf_range(0.55, 1.0)
				var sz := Vector3(u, u, u)
				sz[o2] = u * _rng.randf_range(0.7, 1.35)
				sz[ax] = t
				var p := c
				p[ax] += sg * (s[ax] * 0.5 - t * 0.5 + t * _rng.randf_range(0.2, 0.5))
				p[o1] += snappedf(_rng.randf_range(-0.5, 0.5) * (s[o1] - u * 0.4), 0.15)
				p[o2] += snappedf(_rng.randf_range(-0.5, 0.5) * (s[o2] - u * 0.4), 0.15)
				_blk(part, "body", p, sz, _pick(pal))


## 一道发光裂痕：沿折线 pts 铺一串细长条（n 为所在甲面朝外的法线），略凸出甲面，像熔岩从缝里透出来；折点各缀一粒光
func _vein(part: Node3D, pts: Array, n: Vector3, w := 0.32) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var y := d.normalized()
		var x := y.cross(n).normalized()
		_put(part, "glow", Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5 + n * 0.12), Vector3(w, d.length() + w, 1.0), Color.WHITE)
		if i > 0:
			_blk(part, "glow", a + n * 0.2, Vector3(w, w, w) * 1.7, Color.WHITE)


## 回纹金饰：金底板 + 一圈深色回字槽 + 中心金块 + 一道勾出去的金条，n 为朝外法线
func _glyph(part: Node3D, c: Vector3, sz: float, n: Vector3) -> void:
	var z := n.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var b := Basis(x, z.cross(x), z)
	_put(part, "gold", Transform3D(b, c), Vector3(sz, sz, 0.3), GOLD)
	_put(part, "body", Transform3D(b, c + z * 0.12), Vector3(sz * 0.7, sz * 0.7, 0.2), DARK[0])
	_put(part, "gold", Transform3D(b, c + z * 0.2), Vector3(sz * 0.38, sz * 0.38, 0.2), GOLD)
	_put(part, "gold", Transform3D(b, c + z * 0.2 + b.x * sz * 0.17 - b.y * sz * 0.25), Vector3(sz * 0.36, sz * 0.11, 0.2), GOLD)


## 骨刺：根在 pos、沿 dir 伸出，四节由粗到细的骨白方块；返回刺的节点（局部 +Y 朝外，meta "len" 为刺长）
func _spike(parent: Node3D, pos: Vector3, dir: Vector3, k: float) -> Node3D:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var sp := Node3D.new()
	sp.transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	parent.add_child(sp)
	var segs := [[1.05, 1.3, 0.35], [0.74, 1.1, 1.45], [0.46, 1.0, 2.4], [0.22, 0.7, 3.15]]
	for i in segs.size():
		var e: Array = segs[i]
		_blk(sp, "body", Vector3(0.0, float(e[2]) * k, 0.0), Vector3(e[0], e[1], e[0]) * k,
				(BONE[1] as Color).lerp(BONE[2], float(i) / 3.0))
	sp.set_meta("len", 3.5 * k)
	return sp


func _build() -> void:
	_rng.seed = 20261112
	_m_body = _vc_mat(0.85, 0.0, Color.WHITE)
	_m_gold = _vc_mat(0.4, 0.45, GOLD)
	_m_glow = StandardMaterial3D.new()
	_m_glow.emission_enabled = true
	_m_glow.emission_energy_multiplier = 2.5
	_m_core = MeshLib.std_mat(Color(1.0, 0.3, 0.3), 0.3)
	_m_core.emission_enabled = true
	_m_core.emission = Color(1.0, 0.2, 0.25)
	_m_core.emission_energy_multiplier = 4.0
	var armor: Array = PURP + DARK.slice(1)

	_root = _node(self, Vector3.ZERO)
	_pelvis = _node(_root, Vector3(0.0, -4.6, 0.2))
	_torso = _node(_root, WAIST)
	var up := _node(_torso, -WAIST)  # 上身：静止时坐标与 _root 一致，下面都按 _root 坐标摆
	_build_upper(up, armor)
	_head = _node(up, Vector3(0.0, 4.2, -2.2))
	_build_head(armor)
	_arm_l = _build_arm(up, -1.0, armor)
	_arm_r = _build_arm(up, 1.0, armor)
	_fore_l = _arm_l.get_meta("fore")
	_fore_r = _arm_r.get_meta("fore")
	_build_pelvis()
	_build_leg(-1.0, armor)
	_build_leg(1.0, armor)
	_build_tail(armor)
	_bake()

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.25, 0.25)
	_light.omni_range = 30.0
	_light.light_energy = 0.0
	_light.position = _core.position + Vector3(0, 0, -2.5)
	_light.shadow_enabled = false
	up.add_child(_light)


## 胸腹、魔婴核、肩甲与肩背骨刺
func _build_upper(up: Node3D, armor: Array) -> void:
	var f := Vector3.FORWARD
	# 腹 + 腰缝里透出的赤光 + 宽厚前压的胸膛 + 两块胸甲 + 胸甲下两排肋甲 + 驼起的背 + 颈
	_chunk(up, Vector3(0, -2.6, 0.2), Vector3(6.2, 3.2, 4.6), DARK, 0.4)
	_blk(up, "glow", Vector3(0, -1.0, 0.3), Vector3(6.7, 0.45, 5.1), Color.WHITE)
	_chunk(up, Vector3(0, 1.6, 0.6), Vector3(9.4, 5.6, 6.6), armor, 0.42)
	for s: float in [-1.0, 1.0]:
		_chunk(up, Vector3(2.6 * s, 2.1, -3.0), Vector3(3.4, 3.0, 1.2), PURP, 0.5)
		_chunk(up, Vector3(2.7 * s, -0.25, -2.95), Vector3(3.2, 1.1, 0.8), DARK, 0.3)
	_chunk(up, Vector3(0, 2.7, 3.7), Vector3(7.6, 4.4, 2.6), armor, 0.4)
	_chunk(up, Vector3(0, 4.5, -0.6), Vector3(4.2, 1.6, 3.6), DARK, 0.3)
	_blk(up, "glow", Vector3(0, 4.0, -1.0), Vector3(4.6, 0.4, 3.0), Color.WHITE)
	# 魔婴核：两块胸甲之间一颗竖着的赤晶菱块（索敌瞄准点），身后一片菱形赤光
	_blk(up, "glow", Vector3(0, 0.9, -3.05), Vector3(2.5, 2.5, 0.4), Color.WHITE, Vector3(0, 0, 45))
	_core = MeshInstance3D.new()
	_core.mesh = _box(Vector3(1.5, 1.5, 1.5))
	_core.material_override = _m_core
	_core.position = Vector3(0, 0.9, -3.5)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	up.add_child(_core)
	# 裂痕：核心往下劈过腰缝直到小腹，往两侧爬上胸甲，胸侧、后背各几道
	_vein(up, [Vector3(0, 0.2, -2.7), Vector3(0.35, -0.5, -2.7), Vector3(-0.25, -1.2, -2.7)], f)
	_vein(up, [Vector3(-0.25, -1.3, -2.1), Vector3(0.3, -2.2, -2.1), Vector3(-0.2, -3.0, -2.1), Vector3(0.25, -3.9, -2.1)], f)
	_vein(up, [Vector3(0.3, -2.2, -2.1), Vector3(1.4, -2.6, -2.1), Vector3(2.5, -2.3, -2.1)], f)
	_vein(up, [Vector3(-0.2, -3.0, -2.1), Vector3(-1.5, -3.4, -2.1), Vector3(-2.6, -3.1, -2.1)], f)
	for s: float in [-1.0, 1.0]:
		_vein(up, [Vector3(1.0 * s, 1.5, -3.6), Vector3(1.9 * s, 2.15 - 0.2 * s, -3.6), Vector3(2.8 * s, 1.7, -3.6),
				Vector3(3.6 * s, 2.5 + 0.2 * s, -3.6), Vector3(4.1 * s, 3.4, -3.6)], f)
		_vein(up, [Vector3(4.7 * s, -0.6, -1.6), Vector3(4.7 * s, 0.6, -0.4), Vector3(4.7 * s, 0.1, 0.9),
				Vector3(4.7 * s, 1.6, 2.0), Vector3(4.7 * s, 2.6, 2.8)], Vector3(s, 0, 0))
	_vein(up, [Vector3(0, 0.6, 5.0), Vector3(0.5, 1.8, 5.0), Vector3(-0.4, 3.0, 5.0), Vector3(0.2, 4.4, 5.0)], Vector3.BACK)
	# 肩甲：高耸的两大块 + 下沿一圈紫甲，正面金回纹，顶上三根骨刺（出弹点）
	for s: float in [-1.0, 1.0]:
		_chunk(up, Vector3(6.1 * s, 3.4, 0.4), Vector3(4.8, 3.8, 5.4), armor, 0.45)
		_chunk(up, Vector3(6.5 * s, 1.6, 0.4), Vector3(4.4, 1.2, 5.8), PURP, 0.35)
		_glyph(up, Vector3(6.1 * s, 3.5, -2.45), 2.0, f)
		_vein(up, [Vector3(4.9 * s, 2.1, -2.95), Vector3(6.0 * s, 1.8, -2.95), Vector3(7.4 * s, 2.0, -2.95)], f, 0.26)
		_spikes.append(_spike(up, Vector3(4.9 * s, 5.2, -0.6), Vector3(0.35 * s, 1.0, 0.15), 1.3))
		_spikes.append(_spike(up, Vector3(6.6 * s, 5.2, 0.8), Vector3(0.7 * s, 1.0, 0.35), 1.15))
		_spikes.append(_spike(up, Vector3(8.4 * s, 4.1, 1.4), Vector3(1.0 * s, 0.55, 0.3), 0.95))
	_spikes.append(_spike(up, Vector3(0, 4.8, 3.4), Vector3(0, 1.0, 0.55), 1.25))
	_spikes.append(_spike(up, Vector3(-2.5, 4.6, 3.6), Vector3(-0.35, 1.0, 0.6), 1.0))
	_spikes.append(_spike(up, Vector3(2.5, 4.6, 3.6), Vector3(0.35, 1.0, 0.6), 1.0))
	# 背脊往下一串小骨刺
	for i in 3:
		_spike(up, Vector3(0, 3.4 - 1.3 * i, 5.0), Vector3(0, 0.45, 1.0), 0.75 - 0.12 * i)


## 头：低压在两肩之间，眉骨、张开的嘴里透出赤光、上下獠牙、斜吊赤目、额前金回纹、一对骨白巨角、两腮骨刺
func _build_head(armor: Array) -> void:
	var h := _head
	var f := Vector3.FORWARD
	_chunk(h, Vector3(0, 1.2, -0.6), Vector3(4.2, 3.4, 4.0), armor, 0.45)
	_chunk(h, Vector3(0, 2.0, -2.75), Vector3(4.6, 0.9, 1.0), DARK, 0.3)
	_chunk(h, Vector3(0, 0.5, -3.0), Vector3(3.4, 1.1, 1.6), PURP, 0.35)
	_blk(h, "glow", Vector3(0, -0.35, -2.9), Vector3(2.8, 0.8, 1.4), Color.WHITE)
	_chunk(h, Vector3(0, -1.05, -2.6), Vector3(3.8, 1.0, 2.4), DARK, 0.3, "")
	_glyph(h, Vector3(0, 2.75, -2.68), 1.1, f)
	_spike(h, Vector3(0, 2.9, -1.4), Vector3(0, 1.0, -0.15), 0.7)
	for s: float in [-1.0, 1.0]:
		# 獠牙：上颚两长两短朝下，下颚两根朝上外翻
		_blk(h, "body", Vector3(0.95 * s, -0.4, -3.55), Vector3(0.5, 1.4, 0.5), BONE[0])
		_blk(h, "body", Vector3(0.95 * s, -1.2, -3.6), Vector3(0.3, 0.5, 0.3), BONE[2])
		_blk(h, "body", Vector3(0.35 * s, -0.2, -3.6), Vector3(0.35, 0.8, 0.35), BONE[1])
		_blk(h, "body", Vector3(1.55 * s, -0.05, -3.45), Vector3(0.55, 1.6, 0.55), BONE[0], Vector3(0, 0, -12 * s))
		_blk(h, "body", Vector3(1.72 * s, 0.9, -3.45), Vector3(0.32, 0.6, 0.32), BONE[2], Vector3(0, 0, -12 * s))
		# 两腮骨刺
		_spike(h, Vector3(2.1 * s, 0.1, -1.7), Vector3(1.0 * s, 0.2, -0.2), 0.7)
		_spike(h, Vector3(2.1 * s, 1.4, -0.3), Vector3(1.0 * s, 0.5, 0.25), 0.5)
		# 角：紫甲角座 + 金箍，往外再往上弯的一串骨白方块，越往上越细、略向后仰
		_chunk(h, Vector3(2.4 * s, 2.3, -0.3), Vector3(1.6, 1.6, 1.6), PURP, 0.3)
		_blk(h, "gold", Vector3(2.85 * s, 2.3, -0.3), Vector3(0.4, 1.85, 1.85), GOLD)
		var horn := [[Vector3(3.4, 2.9, -0.1), Vector3(1.35, 1.35, 1.35)], [Vector3(4.0, 4.0, 0.1), Vector3(1.1, 1.8, 1.1)],
				[Vector3(4.3, 5.6, 0.4), Vector3(0.85, 1.8, 0.85)], [Vector3(4.35, 7.1, 0.85), Vector3(0.6, 1.6, 0.6)],
				[Vector3(4.3, 8.2, 1.3), Vector3(0.32, 1.0, 0.32)]]
		for i in horn.size():
			var p: Vector3 = horn[i][0]
			_blk(h, "body", Vector3(p.x * s, p.y, p.z), horn[i][1], BONE[[1, 0, 2, 0, 2][i]], Vector3(8.0 * i, 0, -6.0 * s))
		# 赤目：两道斜吊的光条（内低外高），开战才睁开
		var eye := MeshInstance3D.new()
		eye.mesh = _box(Vector3(1.0, 0.42, 0.3))
		eye.material_override = _m_glow
		eye.position = Vector3(1.05 * s, 1.35, -2.82)
		eye.rotation_degrees = Vector3(0, 0, 14 * s)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(eye)
		_eyes.append(eye)


## 手臂：肩点 → 上臂 → 小臂（meta "fore"）连手。小臂粗过上臂，金护腕、外侧与肘后骨刺，四根骨白弯爪 + 拇爪
func _build_arm(up: Node3D, s: float, armor: Array) -> Node3D:
	var f := Vector3.FORWARD
	var sh := _node(up, Vector3(6.6 * s, 2.2, 0.3))
	_chunk(sh, Vector3(0, -2.6, 0), Vector3(3.0, 5.0, 3.0), armor, 0.45, "")
	_vein(sh, [Vector3(1.5 * s, -0.9, -0.6), Vector3(1.5 * s, -2.2, 0.3), Vector3(1.5 * s, -3.4, -0.3), Vector3(1.5 * s, -4.5, 0.4)], Vector3(s, 0, 0))
	_vein(sh, [Vector3(0.2, -1.6, -1.5), Vector3(-0.4, -2.9, -1.5), Vector3(0.3, -4.2, -1.5)], f)
	var fore := _node(sh, Vector3(0, -5.0, 0))
	sh.set_meta("fore", fore)
	_chunk(fore, Vector3(0, -2.4, 0), Vector3(3.8, 4.8, 3.8), armor, 0.45, "")
	_blk(fore, "gold", Vector3(0, -3.95, 0), Vector3(4.15, 0.8, 4.15), GOLD)
	_vein(fore, [Vector3(-0.5, -0.5, -1.9), Vector3(0.4, -1.5, -1.9), Vector3(-0.3, -2.5, -1.9), Vector3(0.2, -3.4, -1.9)], f)
	_vein(fore, [Vector3(1.9 * s, -0.4, -0.8), Vector3(1.9 * s, -1.6, -0.2), Vector3(1.9 * s, -3.2, -0.7)], Vector3(s, 0, 0))
	_spike(fore, Vector3(1.9 * s, -1.0, 0.5), Vector3(s, 0.35, 0.4), 0.85)
	_spike(fore, Vector3(1.9 * s, -2.6, 0.9), Vector3(s, 0.1, 0.5), 0.7)
	_spike(fore, Vector3(0, -0.3, 1.8), Vector3(0, -0.25, 1.0), 0.95)
	_chunk(fore, Vector3(0, -5.55, -0.2), Vector3(3.4, 2.0, 3.2), PURP, 0.35, "")
	for i in 4:
		var x := -1.2 + 0.8 * float(i)
		_blk(fore, "body", Vector3(x, -7.1, -1.0), Vector3(0.62, 1.5, 0.72), BONE[1])
		_blk(fore, "body", Vector3(x, -8.15, -1.45), Vector3(0.48, 1.1, 0.52), BONE[0], Vector3(28, 0, 0))
		_blk(fore, "body", Vector3(x, -8.85, -2.0), Vector3(0.28, 0.7, 0.3), BONE[2], Vector3(50, 0, 0))
	_blk(fore, "body", Vector3(-1.9 * s, -6.3, -1.3), Vector3(0.6, 1.3, 0.65), BONE[1], Vector3(20, 0, -25 * s))
	_blk(fore, "body", Vector3(-2.15 * s, -7.1, -1.7), Vector3(0.35, 0.7, 0.4), BONE[2], Vector3(40, 0, -25 * s))
	return sh


## 胯：腰间金带 + 回纹扣 + 下垂的金坠，前后垂下参差的紫布摆
func _build_pelvis() -> void:
	var p := _pelvis
	var f := Vector3.FORWARD
	_chunk(p, Vector3(0, -0.6, 0), Vector3(7.0, 2.6, 5.0), DARK, 0.35)
	_blk(p, "gold", Vector3(0, 0.55, -2.6), Vector3(7.4, 1.0, 0.5), GOLD)
	_blk(p, "gold", Vector3(0, 0.55, 2.6), Vector3(7.4, 1.0, 0.5), GOLD)
	for s: float in [-1.0, 1.0]:
		_blk(p, "gold", Vector3(3.6 * s, 0.55, 0), Vector3(0.5, 1.0, 5.7), GOLD)
	_glyph(p, Vector3(0, 0.45, -2.95), 2.4, f)
	_blk(p, "gold", Vector3(0, -1.5, -3.05), Vector3(0.7, 1.9, 0.3), GOLD)
	_glyph(p, Vector3(0, -2.9, -3.1), 1.2, f)
	for side: float in [-1.0, 1.0]:  # -1 前摆，+1 后摆（更长）
		for i in 3:
			var x := (float(i) - 1.0) * 1.75
			var t := _node(p, Vector3(x, 0.0, 2.8 * side))
			var ln := (5.0 if side < 0.0 else 6.6) - absf(x) * 0.5
			var col := _pick(PURP)
			_blk(t, "body", Vector3(0, -ln * 0.5, 0), Vector3(1.55, ln, 0.35), col)
			_blk(t, "body", Vector3(0, -ln * 0.35, -0.12 * side), Vector3(1.1, ln * 0.5, 0.2), col.darkened(0.3))
			for j in 3:
				var hj := _rng.randf_range(0.4, 1.3)
				_blk(t, "body", Vector3((float(j) - 1.0) * 0.5, -ln - hj * 0.5 + 0.1, 0), Vector3(0.45, hj, 0.3), _pick(PURP))
			_tatters.append(t)


## 腿：粗短、往下越来越粗，膝甲 + 膝刺，小腿上一道金箍，外翻的脚踝、宽脚掌，三根骨白大趾、后跟骨刺
func _build_leg(s: float, armor: Array) -> void:
	var f := Vector3.FORWARD
	var th := _node(_pelvis, Vector3(2.5 * s, -1.4, 0.2))
	_chunk(th, Vector3(0, -2.0, 0), Vector3(3.4, 4.2, 3.6), armor, 0.45, "")
	_vein(th, [Vector3(-0.6, -0.5, -1.8), Vector3(0.3, -1.7, -1.8), Vector3(-0.3, -2.9, -1.8), Vector3(0.2, -3.7, -1.8)], f)
	_vein(th, [Vector3(1.7 * s, -0.8, 0.3), Vector3(1.7 * s, -2.0, -0.4), Vector3(1.7 * s, -3.2, 0.4)], Vector3(s, 0, 0))
	var sh := _node(th, Vector3(0, -4.0, 0))
	_chunk(sh, Vector3(0, 0.1, -1.5), Vector3(2.6, 1.6, 1.4), PURP, 0.3)
	_spike(sh, Vector3(0, 0.3, -2.1), Vector3(0, 0.35, -1.0), 0.6)
	_chunk(sh, Vector3(0, -2.1, 0), Vector3(3.8, 4.2, 4.0), armor, 0.45, "")
	_blk(sh, "gold", Vector3(0, -0.75, 0), Vector3(4.15, 0.8, 4.35), GOLD)
	_vein(sh, [Vector3(0.4, -1.4, -2.0), Vector3(-0.4, -2.3, -2.0), Vector3(0.3, -3.3, -2.0)], f)
	_chunk(sh, Vector3(0, -3.9, 0), Vector3(4.6, 1.2, 4.6), DARK, 0.3)
	_chunk(sh, Vector3(0, -4.6, -0.9), Vector3(4.6, 1.0, 5.4), DARK, 0.25)
	for i in 3:
		var x := (float(i) - 1.0) * 1.5
		_blk(sh, "body", Vector3(x, -4.35, -3.9), Vector3(1.25, 1.5, 1.6), BONE[1])
		_blk(sh, "body", Vector3(x, -4.6, -4.95), Vector3(0.85, 1.0, 0.8), BONE[0])
		_blk(sh, "body", Vector3(x, -4.75, -5.6), Vector3(0.5, 0.7, 0.6), BONE[2])
	_blk(sh, "body", Vector3(0, -4.6, 2.3), Vector3(0.9, 1.0, 1.0), BONE[1])
	_legs.append(th)
	_shins.append(sh)


## 尾巴：从胯后伸出，先往后下垂、再一节节往上往一侧卷起；每节背上一根骨刺、两侧隔节一对小刺，腹面一道赤光，尾尖一根长刺
func _build_tail(armor: Array) -> void:
	var parent := _pelvis
	var pos := Vector3(0, -1.2, 2.3)
	var n := 10
	for i in n:
		var u := float(i) / float(n - 1)
		var w := lerpf(2.6, 0.8, u)
		var ln := lerpf(2.3, 1.5, u)
		var seg := _node(parent, pos)
		var rest := Vector3(0.55, 0.0, 0.0) if i == 0 else Vector3(-0.16, -0.13, 0.0)
		seg.rotation = rest
		_chunk(seg, Vector3(0, 0, ln * 0.5), Vector3(w, w * 0.9, ln + 0.3), armor, 0.35, "")
		_vein(seg, [Vector3(0, -w * 0.45, 0.1), Vector3(0, -w * 0.45, ln)], Vector3.DOWN, 0.28)
		_spike(seg, Vector3(0, w * 0.45, ln * 0.5), Vector3(0, 1.0, 0.45), lerpf(0.75, 0.35, u))
		if i % 2 == 1:
			for s: float in [-1.0, 1.0]:
				_spike(seg, Vector3(w * 0.5 * s, 0, ln * 0.5), Vector3(s, 0.3, 0.3), lerpf(0.5, 0.25, u))
		_tail.append(seg)
		_tail_rest.append(rest)
		parent = seg
		pos = Vector3(0, 0, ln)
	_spike(parent, Vector3(0, 0, 1.3), Vector3(0, 0.2, 1.0), 0.65)


## 每个部件的方块按材质烘成一个 MultiMesh（单位立方体 × 每块的变换与尺寸），甲块颜色走实例色
func _bake() -> void:
	var mats := {"body": _m_body, "gold": _m_gold, "glow": _m_glow}
	var unit := BoxMesh.new()
	for part: Node3D in _blocks:
		var d: Dictionary = _blocks[part]
		for key: String in d:
			var list: Array = d[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = unit
			mm.instance_count = list.size()
			for i in list.size():
				var b: Array = list[i]
				var xf: Transform3D = b[0]
				mm.set_instance_transform(i, Transform3D(xf.basis * Basis.from_scale(b[1]), xf.origin))
				mm.set_instance_color(i, MeshLib.vcol(b[2] as Color))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mats[key]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key == "body" \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta("blocks", list)
			mmi.set_meta("glow", key == "glow")
			part.add_child(mmi)
	_blocks.clear()


## 碎裂用的方块：每块按 cell 切成小方块，按当前姿势取世界坐标；裂光块换成泛白的阶段赤光
func _shatter_cubes(cell: float) -> Array:
	var out: Array = []
	var glow := Color.WHITE.lerp(CRACK[phase], 0.6)
	for n in _root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if not mmi.is_visible_in_tree():
			continue
		var gx := mmi.global_transform
		var sc := gx.basis.get_scale().x
		var is_glow: bool = mmi.get_meta("glow")
		for b: Array in mmi.get_meta("blocks"):
			var xf: Transform3D = b[0]
			var s: Vector3 = b[1]
			var col: Color = glow if is_glow else b[2]
			var nx := maxi(roundi(s.x / cell), 1)
			var ny := maxi(roundi(s.y / cell), 1)
			var nz := maxi(roundi(s.z / cell), 1)
			var sub := Vector3(s.x / nx, s.y / ny, s.z / nz)
			var cs := minf(sub.x, minf(sub.y, sub.z)) * sc * 0.95
			var bx := gx.basis * xf.basis
			for ix in nx:
				for iy in ny:
					for iz in nz:
						var lp := Vector3(ix + 0.5, iy + 0.5, iz + 0.5) * sub - s * 0.5
						out.append([Transform3D(bx, gx * (xf * lp)), cs, col])
	return out


## 各阶段的配色：裂痕 / 赤目 / 点光走 CRACK，魔婴核走弹色主色
func _apply_palette() -> void:
	var c0: Color = (PAL[phase] as Array)[0]
	var cr: Color = CRACK[phase]
	_m_glow.albedo_color = cr
	_m_glow.emission = cr
	_m_core.emission = c0
	_m_core.albedo_color = Color.WHITE.lerp(c0, 0.5)
	_light.light_color = cr


# ---------- 查询 ----------

func aim_point() -> Vector3:
	return _core.global_position


## 体型半径（Proj.body_r）：法术打到魔婴核前这么远就算命中，直飞的剑擦过胸膛也算，不必正中瞄准点
func hit_radius() -> float:
	return 4.2 * SCALE


## 骨刺尖（世界坐标）
static func _tip(sp: Node3D) -> Vector3:
	return sp.global_transform * Vector3(0.0, float(sp.get_meta("len")), 0.0)


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func phase_title() -> String:
	return "%s · %s" % [PHASE_TAGS[phase], PHASE_NAMES[phase]]


func fighting() -> bool:
	return state == S.INTRO or state == S.FIGHT or state == S.SHIFT


func invulnerable() -> bool:
	return state != S.FIGHT


func _pal(i: int) -> Color:
	return (PAL[phase] as Array)[i]


func _player_c() -> Vector3:
	return player.center() if is_instance_valid(player) else global_position + Vector3.FORWARD * 30.0


# ---------- 流程 ----------

## 玩家踏进剑冢：睁眼、蹬地升空、骨刺竖起、魔啸，之后开打
func begin() -> void:
	if state != S.DORMANT:
		return
	_set_state(S.INTRO)
	alive = true
	Sfx.play("perfect", -2.0, 0.45)
	Vfx.glint(aim_point(), Color.WHITE.lerp(_pal(0), 0.4), 3.0)
	for e in _eyes:
		Vfx.glint(e.global_position, _pal(0), 1.6)


## 回到沉睡：满血、一阶、落回剑冢中心立地闭目（玩家倒下或跑出剑冢后由 boss_arena 调）
func reset_dormant() -> void:
	_jobs.clear()
	if bullets != null:
		bullets.clear_all(0.4)
	hp = max_hp
	phase = 0
	_apply_palette()
	alive = false
	_root.visible = true
	_root.scale = Vector3.ONE
	_crack = 0.0
	_set_state(S.DORMANT)


func _set_state(s: S) -> void:
	state = s
	_state_t = 0.0


func take_hit(dmg: float, dir: Vector3, color: Color) -> void:
	if not alive:
		return
	if invulnerable():
		# 护体：开场 / 转阶段时打不动，只在魔婴核上闪一下
		_flash_b = maxf(_flash_b, 0.25)
		if _guard_fx <= 0.0:
			_guard_fx = 0.12
			Vfx.glint(aim_point() - dir.normalized() * 1.2, Color(1.0, 0.9, 0.8), 1.4)
		return
	var floor_hp := 0.0
	if phase < PHASE_AT.size():
		floor_hp = float(PHASE_AT[phase]) * max_hp  # 一下打穿也要先进下一阶段，不跳阶段
	hp = maxf(hp - dmg, floor_hp)
	_flash_b = 1.0
	_wob_v += dir.normalized() * 2.2
	var jitter := Vector3(randf_range(-2.5, 2.5), randf_range(0.5, 3.5), randf_range(-1.0, 1.0))
	Vfx.damage_number(aim_point() + jitter, dmg, color)
	if phase < PHASE_AT.size() and hp <= floor_hp:
		_begin_shift()
	elif hp <= 0.0:
		_begin_death(dir)


func _process(dt: float) -> void:
	dt = minf(dt, 1.0 / 20.0)
	_clock += dt
	_state_t += dt
	_t += dt
	_guard_fx -= dt
	match state:
		S.DORMANT:
			_pose_dormant(dt)
		S.INTRO:
			_tick_intro(dt)
		S.FIGHT:
			_tick_fight(dt)
		S.SHIFT:
			_tick_shift(dt)
		S.DYING:
			_tick_dying(dt)
		S.DEAD:
			return
	_run_jobs()
	_animate(dt)


func _run_jobs() -> void:
	var i := 0
	while i < _jobs.size():
		var j: Array = _jobs[i]
		if _clock >= float(j[0]):
			_jobs.remove_at(i)
			(j[1] as Callable).call()
			if state != S.FIGHT:
				return  # 这一波把它打进了转阶段 / 击败：剩下的已被清空
		else:
			i += 1


func _at(delay: float, fn: Callable) -> void:
	_jobs.append([_clock + delay, fn])


# ---------- 各状态 ----------

## 沉睡：立在剑冢正中、面朝入口，弓背垂首、骨刺收伏，裂痕和魔婴核暗暗明灭（从空中回来时慢慢落地、转回去）
func _pose_dormant(dt: float) -> void:
	position = position.lerp(center + Vector3(0, DORMANT_H, 0), 1.0 - exp(-2.0 * dt))
	_yaw = lerp_angle(_yaw, _rest_yaw, 1.0 - exp(-1.0 * dt))
	rotation.y = _yaw


## 沉睡时面朝 p（水平面），立即转过去
func face_rest(p: Vector3) -> void:
	var d := p - global_position
	_rest_yaw = atan2(-d.x, -d.z)
	_yaw = _rest_yaw
	rotation.y = _yaw


## 开场：睁眼 → 蹬地（脚下一圈尘浪、镜头一震）→ 升空挺身 → 魔啸（登场题名由 Boss HUD 接魔啸信号写，只写第一次）
func _tick_intro(dt: float) -> void:
	var u := clampf((_state_t - 0.35) / 1.4, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var want := center + Vector3(0, lerpf(DORMANT_H, FIGHT_H, e), 0)
	position = position.lerp(want, 1.0 - exp(-6.0 * dt))
	_face_player(dt, 3.0)
	if _state_t >= 0.35 and _state_t - dt < 0.35:
		Vfx.sky_ring(center + Vector3.UP * 0.4, Color(0.6, 0.45, 0.7), 16.0, 0.9)
		Vfx.sky_ring(center + Vector3.UP * 0.6, _pal(0), 9.0, 0.6)
		Sfx.play("slam", -3.0, 0.4)
		if is_instance_valid(player):
			player.cam.add_trauma(0.3)
	if _state_t >= 1.5 and _state_t - dt < 1.5:
		_roar(1.0)
	if _state_t >= 3.4:
		_set_state(S.FIGHT)
		_next_at = _clock + 0.3


## 魔啸：身外一圈天环、面朝玩家的法相光环、镜头重震，还有一圈只作声势的慢弹（无判定）
func _roar(power: float) -> void:
	var c := aim_point()
	var to := _player_c() - c
	Vfx.sky_ring(c + Vector3.UP * 2.0, _pal(0), 16.0 * power, 1.0)
	Vfx.halo(c, to.normalized(), _pal(0), 11.0 * power, 0.7)
	Vfx.flash_light(c, _pal(0), 6.0, 40.0, 0.5)
	Sfx.play("slam", 0.0, 0.5)
	Sfx.play("clash", -6.0, 0.4)
	_cast_k = 1.0
	if is_instance_valid(player):
		player.cam.add_trauma(0.55 * power)
		player.cam.fov_punch(9.0 * power)
	var n := 72
	for k in n:
		var y := 1.0 - 2.0 * (float(k) + 0.5) / float(n)
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var a := 2.39996 * float(k)
		var d := Vector3(cos(a) * rr, y, sin(a) * rr)
		bullets.spawn(c + d * 3.0, d * 26.0, Bullets.R_ROUND, _pal(k % 3), Bullets.K.ROUND, {"life": 1.2, "harm": false})
	roared.emit()


func _tick_fight(dt: float) -> void:
	_move(dt)
	_face_player(dt, 2.5)
	if _clock >= _next_at:
		var dur := _cast(_pick_pattern())
		# 三阶：常常再叠一招短的
		if phase == 2 and randf() < 0.45:
			_cast(["fan", "swords"][randi() % 2])
		_next_at = _clock + dur + GAP[phase]
	_amb -= dt
	if _amb <= 0.0:
		_amb = AMB_STEP[phase]
		_ambient_shot()
	if phase == 2:
		_pepper -= dt
		if _pepper <= 0.0:
			_pepper = 0.85
			_pepper_shot()
	# 贴身：撞上魔婴核要挨一下（并被弹开），不许一直贴着打
	if is_instance_valid(player) and player.center().distance_to(aim_point()) < CONTACT_R:
		var hit_cb: Callable = bullets.on_hit
		var can_cb: Callable = bullets.can_hit
		if hit_cb.is_valid() and can_cb.is_valid() and can_cb.call():
			hit_cb.call(player.center(), (player.center() - aim_point()).normalized(), 15.0)


## 保持和玩家约 KEEP_DIST 的水平距离，在剑冢上空绕着游走；高度随玩家起落，阶段越高走得越快
func _move(dt: float) -> void:
	var pc := _player_c()
	_roam += dt * (0.12 + 0.08 * phase)
	var away := Vector3(position.x - pc.x, 0.0, position.z - pc.z)
	away = away.normalized() if away.length_squared() > 1e-4 else Vector3.BACK
	away = away.rotated(Vector3.UP, sin(_roam) * 0.9 * dt)
	var want := pc + away * KEEP_DIST + away.cross(Vector3.UP) * sin(_roam * 1.7) * (6.0 + 4.0 * phase)
	var flat := Vector3(want.x - center.x, 0.0, want.z - center.z).limit_length(ROAM_R)
	want = center + flat
	want.y = clampf(pc.y + 12.0, FIGHT_H - 4.0, FIGHT_H + 16.0) + sin(_t * 0.8) * 1.2  # 袍脚不擦地
	var spd: float = 7.0 + 3.0 * phase
	_vel = _vel.lerp((want - position).limit_length(spd), 1.0 - exp(-1.5 * dt))
	position += _vel * dt


func _face_player(dt: float, rate: float) -> void:
	var d := _player_c() - global_position
	if Vector2(d.x, d.z).length() < 0.5:
		return
	_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), 1.0 - exp(-rate * dt))
	rotation.y = _yaw


func _pick_pattern() -> String:
	var pool: Array = (POOLS[phase] as Array).duplicate()
	pool.erase(_last_pat)
	var p: String = pool[randi() % pool.size()]
	_last_pat = p
	return p


## 出一招：把每一波排进时间表，返回这招总时长
func _cast(p: String) -> float:
	_cast_k = 1.0
	Vfx.glint(aim_point(), Color.WHITE.lerp(_pal(0), 0.5), 2.6)
	Sfx.play("swing_heavy", -6.0, 0.55)
	match p:
		"fan":
			return _p_fan()
		"ring":
			return _p_ring()
		"swords":
			return _p_swords()
		"orbs":
			return _p_orbs()
		"spiral":
			return _p_spiral()
		"curve":
			return _p_curve()
		"wall":
			return _p_wall()
		"rose":
			return _p_rose()
	return 1.0


# ---------- 弹幕 ----------

func _src() -> Vector3:
	return aim_point() + _fwd() * 1.6


func _fwd() -> Vector3:
	return -global_basis.z.normalized()  # 节点整体放大过，基向量不是单位长


## 以 f 为前方的一组正交轴 [side, up]
static func _frame(f: Vector3) -> Array:
	var side := f.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	return [side, side.cross(f).normalized()]


func _aim_from(from: Vector3) -> Vector3:
	var to := _player_c() - from
	return to.normalized() if to.length_squared() > 1e-4 else _fwd()


## 锁定提示：在玩家"此刻"的位置亮一圈赤环（这一波就打这里）
func _lock_mark(col: Color) -> void:
	var pc := _player_c()
	Vfx.halo(pc, aim_point() - pc, col, 1.8, 0.35)


func _cone(f: Vector3, ax: Array, theta: float, phi: float) -> Vector3:
	var side: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	return (f * cos(theta) + (side * cos(phi) + up * sin(phi)) * sin(theta)).normalized()


func _wave_sfx(pitch: float) -> void:
	Sfx.play("swing", -12.0, pitch)


## 血河剑气：锁定扇射针弹。每波重新瞄准你此刻的位置，奇偶波错开半格；二阶两层、三阶三层
func _p_fan() -> float:
	var waves := 4 + phase
	var n := 9 + 3 * phase
	var spread := deg_to_rad(64.0 + 10.0 * phase)
	var rows := phase + 1
	var spd: float = 25.0 * SPD[phase]
	for w in waves:
		_at(0.2 + 0.42 * w, func() -> void:
			var from := _src()
			var f := _aim_from(from)
			var ax := _frame(f)
			_lock_mark(_pal(2))
			_wave_sfx(0.9)
			for row in rows:
				var pitch := (float(row) - float(rows - 1) * 0.5) * 0.13
				for k in n:
					var a := (float(k) / float(n - 1) - 0.5) * spread + (0.5 * spread / float(n - 1) if w % 2 == 1 else 0.0)
					var d := f.rotated(ax[1], a).rotated(ax[0], pitch)
					bullets.spawn(from + d * 2.0, d * spd, Bullets.R_NEEDLE, _pal(2), Bullets.K.NEEDLE, {"dmg": DMG[phase]}))
	return 0.2 + 0.42 * waves


## 血莲绽：朝你所在方向射出的锥环——画面里是一圈圈向镜头扩开的花环；奇数波正中再补一颗大弹逼你挪位
func _p_ring() -> float:
	var waves := 6 + phase
	var n := 24 + 6 * phase
	var spd: float = 16.0 * SPD[phase]
	for w in waves:
		_at(0.2 + 0.45 * w, func() -> void:
			var from := _src()
			var f := _aim_from(from)
			var ax := _frame(f)
			var theta := deg_to_rad([9.0, 18.0, 27.0][w % (2 + mini(phase, 1))])
			var col := _pal(w % 2)
			_wave_sfx(0.7)
			for k in n:
				var d := _cone(f, ax, theta, TAU * float(k) / float(n) + 0.13 * w)
				bullets.spawn(from + d * 2.0, d * spd, Bullets.R_ROUND, col, Bullets.K.ROUND, {"dmg": DMG[phase]})
			if w % 2 == 1:
				_lock_mark(col)
				bullets.spawn(from + f * 2.0, f * spd * 1.1, Bullets.R_BIG, _pal(2), Bullets.K.ROUND, {"dmg": DMG[phase] * 1.5}))
	return 0.2 + 0.45 * waves


## 九刺锁魂：肩背九根骨刺的刺尖各凝出针弹，悬停一拍、依次朝你"那一刻"的位置射出（二阶起每根三颗）
func _p_swords() -> float:
	var volleys := 2 if phase == 0 else 3
	var per := 1 if phase == 0 else 3
	for v in volleys:
		_at(0.15 + 1.3 * v, func() -> void:
			Sfx.play("swing_heavy", -8.0, 0.7)
			var pc := _player_c()
			for i in _spikes.size():
				var sp := _spikes[i]
				var tip := _tip(sp)
				var out := (tip - sp.global_position).normalized()
				for j in per:
					var p := tip + out * (1.2 + 1.6 * j)
					bullets.spawn(p, (pc - p).normalized() * 0.01, Bullets.R_NEEDLE, _pal(2), Bullets.K.NEEDLE,
							{"hold": 0.55 + 0.06 * i + 0.1 * j, "aim": 30.0 * SPD[phase], "dmg": DMG[phase], "life": 7.0})
				Vfx.glint(tip, Color.WHITE.lerp(_pal(2), 0.4), 1.6))
		_at(0.15 + 1.3 * v + 0.5, func() -> void: _lock_mark(_pal(2)))
	return 0.15 + 1.3 * volleys + 0.4


## 魔婴吐珠：魔婴核接连吐出大玉，飞到半路炸成一整球小弹
func _p_orbs() -> float:
	var n := 2 + phase
	for i in n:
		_at(0.2 + 0.55 * i, func() -> void:
			var from := _src()
			var f := _aim_from(from)
			_lock_mark(_pal(1))
			Sfx.play("hit_heavy", -8.0, 0.5)
			bullets.spawn(from + f * 2.5, f * 10.0 * SPD[phase], Bullets.R_BIG, _pal(1), Bullets.K.ROUND,
					{"split": 1.35, "split_n": 18 + 6 * phase, "dmg": DMG[phase] * 1.8, "life": 6.0}))
	return 0.2 + 0.55 * n + 1.2


## 血河倒卷：几条旋臂绕着锁定轴转着喷出，形成朝你卷来的涡流；轴每 0.7s 重新锁一次你当时的位置（三阶加一组反旋）
func _p_spiral() -> float:
	var dur := 3.2 if phase < 2 else 3.8
	var arms := 4 if phase < 2 else 5
	var step := 0.075
	var spd: float = 15.0 * SPD[phase]
	var theta := deg_to_rad(32.0)
	var t := 0.0
	while t < dur:
		if fmod(t, 0.7) < step:
			_at(t, func() -> void:
				_axis = _aim_from(_src())
				_lock_mark(_pal(0)))
		var tt := t
		_at(t + 0.01, func() -> void:
			var from := _src()
			var ax := _frame(_axis)
			for a in arms:
				var phi := TAU * float(a) / float(arms) + tt * 2.4
				var d := _cone(_axis, ax, theta, phi)
				bullets.spawn(from + d * 2.0, d * spd, Bullets.R_ROUND, _pal(0).lerp(_pal(1), float(a % 2)), Bullets.K.ROUND, {"dmg": DMG[phase]})
				if phase == 2:
					var d2 := _cone(_axis, ax, theta * 0.6, -phi)
					bullets.spawn(from + d2 * 2.0, d2 * spd * 0.85, Bullets.R_ROUND, _pal(2), Bullets.K.ROUND, {"dmg": DMG[phase]})
			if int(tt / step) % 4 == 0:
				_wave_sfx(1.2))
		t += step
	return dur


## 双蛇缠：剑轮两侧各一道弧线流，起手朝外撇开、半路弯回来，正好交汇在你出手那一刻的位置
func _p_curve() -> float:
	var dur := 2.6
	var step := 0.09
	var pairs := 1 if phase < 2 else 2
	var spd: float = 17.0 * SPD[phase]
	var t := 0.0
	while t < dur:
		var k := int(t / step)
		_at(t, func() -> void:
			var pc := _player_c()
			for pi in pairs:
				for s: float in [-1.0, 1.0]:
					var from := aim_point() + global_basis.x * s * (7.0 + 3.0 * pi) + Vector3.UP * (2.0 + 2.0 * pi)
					var chord := pc - from
					var dist := chord.length()
					if dist < 1.0:
						continue
					var f := chord / dist
					var ax := _frame(f)
					var alpha := 0.75 + 0.2 * pi
					var d := f.rotated(ax[1], alpha * s)
					# 圆弧：起手偏 alpha，弦两端切线夹角 2·alpha，走完弦长要转过 2·alpha
					var rate := 2.0 * alpha / (dist / spd)
					bullets.spawn(from, d * spd, Bullets.R_ROUND, _pal(0) if s < 0.0 else _pal(2), Bullets.K.ROUND,
							{"curl": ax[1] * (-s * rate), "dmg": DMG[phase], "life": dist / spd + 2.5})
			if k % 3 == 0:
				_wave_sfx(1.4))
		t += step
	_at(0.0, func() -> void: _lock_mark(_pal(0)))
	return dur


## 血海天幕：一整面弹幕墙朝你压过来，墙上只留一处缺口（偏离你当时的位置），三面墙缺口各不相同
func _p_wall() -> float:
	var walls := 3
	for w in walls:
		_at(0.2 + 1.35 * w, func() -> void:
			var from := _src()
			var f := _aim_from(from)
			var ax := _frame(f)
			var cols := 15
			var rows := 9
			var gx := randi_range(3, cols - 6)
			var gy := randi_range(2, rows - 5)
			var col := _pal(1) if w % 2 == 0 else _pal(0)
			_lock_mark(col)
			Sfx.play("swing_heavy", -6.0, 0.45)
			for x in cols:
				for y in rows:
					if x >= gx and x < gx + 3 and y >= gy and y < gy + 3:
						continue
					var off := (ax[0] as Vector3) * (float(x) - float(cols - 1) * 0.5) * 2.7 \
							+ (ax[1] as Vector3) * (float(y) - float(rows - 1) * 0.5) * 2.7
					bullets.spawn(from + f * 2.0 + off, f * 13.0 * SPD[phase], Bullets.R_ROUND, col, Bullets.K.ROUND,
							{"dmg": DMG[phase], "life": 6.0}))
	return 0.2 + 1.35 * walls


## 血莲万瓣：一圈圈锥环边飞边绕飞行轴扭转，相邻两波反向，像层层旋开的血莲
func _p_rose() -> float:
	var waves := 7
	var n := 30
	var spd: float = 15.0 * SPD[phase]
	for w in waves:
		_at(0.2 + 0.4 * w, func() -> void:
			var from := _src()
			var f := _aim_from(from)
			var ax := _frame(f)
			var col := _pal(0) if w % 2 == 0 else _pal(2)
			var spin := 0.9 if w % 2 == 0 else -0.9
			_wave_sfx(0.8)
			for k in n:
				var d := _cone(f, ax, deg_to_rad(15.0), TAU * float(k) / float(n) + 0.2 * w)
				bullets.spawn(from + d * 2.0, d * spd, Bullets.R_ROUND, col, Bullets.K.ROUND,
						{"curl": f * spin, "dmg": DMG[phase]})
			if w % 3 == 0:
				_lock_mark(col))
	return 0.2 + 0.4 * waves


## 血河底流：绕着"指向你此刻位置"的轴旋出几道大锥角慢弹，二阶起每隔一圈反向再吐一层
func _ambient_shot() -> void:
	var from := _src()
	var f := _aim_from(from)
	var ax := _frame(f)
	var arms := 3 + phase
	var spd: float = 11.0 * SPD[phase]
	_amb_phi += 0.21
	var rev := phase >= 1 and int(_amb_phi / 0.21) % 2 == 0
	for a in arms:
		var phi := TAU * float(a) / float(arms) + (-_amb_phi * 1.3 if rev else _amb_phi)
		var d := _cone(f, ax, deg_to_rad(AMB_CONE * (0.7 if rev else 1.0)), phi)
		bullets.spawn(from + d * 2.5, d * spd, Bullets.R_ROUND, _pal(2) if rev else _pal(1), Bullets.K.ROUND,
				{"dmg": DMG[phase], "life": 7.0})


## 三阶的零散点射：随便一根骨刺尖朝你此刻的位置补三颗针弹
func _pepper_shot() -> void:
	var tip := _tip(_spikes[randi() % _spikes.size()])
	var f := _aim_from(tip)
	var ax := _frame(f)
	for k in 3:
		var d := f.rotated(ax[1], (float(k) - 1.0) * 0.07)
		bullets.spawn(tip, d * 32.0, Bullets.R_NEEDLE, _pal(2), Bullets.K.NEEDLE, {"dmg": DMG[phase]})


# ---------- 转阶段 / 击败 ----------

func _begin_shift() -> void:
	_jobs.clear()
	bullets.clear_all(0.35)
	_set_state(S.SHIFT)
	Combat.slowmo(0.2, 0.25, 0.5)
	Sfx.play("clash", -2.0, 0.55)
	Sfx.play("hit_heavy", -2.0, 0.6)
	if is_instance_valid(player):
		player.cam.add_trauma(0.5)


## 转阶段：先被打得后仰、身上窜电弧，再一声魔啸换形换色，3 秒后接着打
func _tick_shift(dt: float) -> void:
	_face_player(dt, 2.0)
	var k := _state_t
	if k < 0.9:
		_wob_v += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0 * dt
		_crack -= dt
		if _crack <= 0.0:
			_crack = 0.09
			_arc_on_body(_pal(0))
	if k >= 0.9 and k - dt < 0.9:
		phase = mini(phase + 1, 2)
		_apply_palette()
		_roar(1.15)
		CombatWord.pop(PHASE_NAMES[phase], aim_point() + Vector3.UP * 12.0, _pal(0), 4.2)
		phase_changed.emit(phase)
	if k >= 3.0:
		_set_state(S.FIGHT)
		_next_at = _clock + 0.2


## 身上随机一道电弧（从魔婴核窜向躯干表面）
func _arc_on_body(col: Color) -> void:
	var c := aim_point()
	var p := global_transform * Vector3(randf_range(-6.0, 6.0), randf_range(-13.0, 6.0), randf_range(-3.0, 3.0))
	Vfx.lightning(c, p, Color.WHITE.lerp(col, 0.6), 0.25, 0.18, 7)
	Vfx.glint(p, col, 1.2)


func _begin_death(dir: Vector3) -> void:
	_jobs.clear()
	bullets.clear_all(0.5)
	alive = false
	_set_state(S.DYING)
	_death_dir = dir
	Combat.slowmo(0.1, 0.7, 1.0)
	Sfx.play("execute", 0.0, 0.6)
	Sfx.play("perfect", -4.0, 0.5)
	if is_instance_valid(player):
		player.cam.add_trauma(0.6)
		player.cam.fov_punch(-8.0)


## 击败：定在空中剧烈颤抖、电弧越窜越密、裂痕与魔婴核越烧越亮 → 整个身躯从核心崩成方块坠向地面、核心爆开
func _tick_dying(dt: float) -> void:
	var k := _state_t
	if k < 2.2:
		_wob_v += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (8.0 + 10.0 * k) * dt
		_crack -= dt
		if _crack <= 0.0:
			_crack = lerpf(0.14, 0.04, k / 2.2)
			_arc_on_body(_pal(0))
		_m_core.emission_energy_multiplier = 4.0 + 10.0 * k
		_m_glow.emission_energy_multiplier = 2.5 + 5.0 * k  # 裂痕越烧越亮
		_light.light_energy = 2.0 + 4.0 * k
		_root.position.y = -k * 0.6
		return
	if k - dt < 2.2:
		_shatter()
	if k >= 4.0:
		_set_state(S.DEAD)


func _shatter() -> void:
	var c := aim_point()
	var hit := c - _death_dir.normalized() * 1.0
	Vfx.shatter(_root, hit, _death_dir, Color.WHITE.lerp(_pal(0), 0.4), 1.8, [], 0.85, _shatter_cubes(1.5))
	_root.visible = false
	Vfx.death_burst(c, _pal(0))
	Vfx.sky_ring(c, _pal(0), 18.0, 1.2)
	Vfx.halo(c, _player_c() - c, Color.WHITE.lerp(_pal(0), 0.3), 14.0, 0.9)
	Vfx.heaven_strike(c, [_pal(0), _pal(1), Color.WHITE], 2.2)
	Vfx.flash_light(c, _pal(0), 8.0, 60.0, 0.8)
	Sfx.play("shatter", 0.0, 0.6)
	Sfx.play("slam", 0.0, 0.45)
	if is_instance_valid(player):
		player.cam.add_trauma(0.9)
		player.cam.fov_punch(12.0)
	CombatWord.pop("伏诛", c + Vector3.UP * 6.0, Color(1.0, 0.85, 0.4), 4.5)
	defeated.emit()


# ---------- 每帧姿态 ----------

func _animate(dt: float) -> void:
	_cast_k = maxf(_cast_k - dt * 1.4, 0.0)
	_wake = move_toward(_wake, 0.0 if state == S.DORMANT else 1.0, dt * 1.6)
	var w := _wake
	var air := clampf((position.y - center.y - DORMANT_H) / 4.0, 0.0, 1.0)  # 0 脚踏地面 ↔ 1 悬空
	# 受击后坐：弹簧
	_wob_v += (-_wob * 30.0 - _wob_v * 6.0) * dt
	_wob += _wob_v * dt
	_root.position.x = _wob.x
	_root.position.z = _wob.z
	if state != S.DYING:
		_root.position.y = lerpf(_root.position.y, _wob.y * air, 1.0 - exp(-8.0 * dt))
	_root.rotation.z = clampf(-_wob.x * 0.03, -0.2, 0.2)
	# 上身：沉睡时弓背垂首，醒来挺身抬头；出招时往前一压、头一扬
	var breathe := sin(_t * 1.3)
	_torso.rotation.x = lerpf(-0.32 + 0.02 * breathe, -0.1 + 0.03 * breathe - 0.1 * _cast_k, w)
	_head.rotation = Vector3(lerpf(-0.35, 0.1 + 0.03 * breathe + 0.25 * _cast_k, w), sin(_t * 0.5) * 0.08 * w, 0.0)
	# 手臂沿 -Y 垂下：绕 X 转正角 = 往前抬，绕 Z 转（左负右正）= 往外张；左手出招时往前一探
	var sway := sin(_t * 0.9) * 0.05
	_arm_l.rotation = Vector3(lerpf(0.34, 0.5 + 0.8 * _cast_k, w) + sway, 0.0, lerpf(-0.1, -0.42 - 0.15 * _cast_k, w))
	_arm_r.rotation = Vector3(lerpf(0.34, 0.42, w) - sway, 0.0, lerpf(0.1, 0.4, w))
	_fore_l.rotation.x = lerpf(0.1, 0.7 + 0.3 * _cast_k, w)
	_fore_r.rotation.x = lerpf(0.1, 0.6, w)
	# 腿：落地时站直、略分开；悬空时大腿前收、小腿后垂，微微划动
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var kick := sin(_t * 1.1 + float(i) * 1.7) * 0.06 * air
		_legs[i].rotation = Vector3(0.38 * air + kick, 0.0, s * (0.05 + 0.06 * air))
		_shins[i].rotation.x = -0.75 * air - kick
	# 布摆：悬空时前摆被腿顶起、后摆往后飘；尾巴一节节传过去的摆动
	for i in _tatters.size():
		var fr := _tatters[i].position.z < 0.0
		_tatters[i].rotation.x = (0.32 if fr else -0.2) * air + sin(_t * 1.7 + float(i) * 1.3) * (0.04 + 0.03 * phase + 0.05 * air)
	for i in _tail.size():
		_tail[i].rotation = _tail_rest[i] + Vector3(sin(_t * 1.2 - float(i) * 0.45) * 0.04,
				sin(_t * (1.0 + 0.3 * phase) - float(i) * 0.55) * (0.05 + 0.04 * w), 0.0)
	# 骨刺：沉睡时收伏，醒来竖起，出招时再一挺
	var sk := lerpf(0.6, 1.0, w) + 0.08 * _cast_k
	for sp in _spikes:
		sp.scale = Vector3.ONE * sk
	# 裂痕、魔婴核、赤目、点光；受击闪白
	_flash_b = maxf(_flash_b - dt * 6.0, 0.0)
	_m_body.emission_energy_multiplier = _flash_b * 0.8
	_m_gold.emission_energy_multiplier = 0.12 + _flash_b * 1.0
	if state != S.DYING:
		var pulse := 0.5 + 0.5 * sin(_t * (2.0 + phase))
		_m_glow.emission_energy_multiplier = lerpf(0.5 + 0.4 * pulse, 2.0 + 1.0 * pulse + 2.0 * _cast_k, w)
		_m_core.emission_energy_multiplier = lerpf(0.6, 3.5 + 2.5 * pulse + 3.0 * _cast_k, w)
		_light.light_energy = lerpf(0.3, 1.8 + 1.2 * pulse + 2.0 * _cast_k, w)
	var eye_on := w if state != S.INTRO else clampf(_state_t / 0.3, 0.0, 1.0)
	for e in _eyes:
		e.visible = eye_on > 0.05
		e.scale = Vector3.ONE * (0.6 + 0.4 * eye_on)
	_core.scale = Vector3.ONE * (1.0 + 0.3 * float(phase >= 1) + 0.12 * _cast_k)
	_core.rotation = Vector3(0.0, _t * 1.5, PI * 0.25)
