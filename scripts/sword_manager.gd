class_name SwordManager
extends Node3D
## 飞剑阵（技能，Q 召出）：默认身边没有飞剑；按 Q 后飞剑按境界数量逐柄在环位上亮出，
## 全部就位后自动向四周随机索敌出剑；持续 SKILL_DUR 秒后散去，期间再按 Q 提前收起。
## 数量按境界；阵型按法相档位（Realm.ARTS form）整套更换，出剑轨迹见 flying_sword.gd：
##   炼气/筑基 水平环身、剑尖朝下 | 结丹 平卧剑轮、剑尖顺着转向追逐 | 元婴 两环斜交的陀螺、反向旋转 |
##   化神 背后竖立的光轮、剑尖朝外放射 | 炼虚 五方五簇、每簇三柄五行同色 | 合体 背后一对剑翼、缓缓扇动 |
##   大乘 三层剑莲、剑尖斜指天外
## E 万剑齐发（需飞剑已召出）。
## 灵力：按 Q 起手扣 MP_COST，技能开着期间每秒持续扣 MP_DRAIN（都按灵力上限的比例），期间灵力不回复；
## 灵力不够起手则召不出（灰光一闪 + 闷响），中途耗尽则飞剑阵自动散去。
## 每次按 Q 放出时，阵名（Realm.ARTS form，如"千剑莲台"）化作 3D 发光毛笔字立在主角两侧（见 skill_calligraphy.gd）。

const Sfx := preload("res://scripts/sfx.gd")
const Calligraphy := preload("res://scripts/skill_calligraphy.gd")
const TIP_DOWN := true  # 环绕时剑尖朝下；改 false 则朝上
const SPAWN_GAP := 0.12   # 召剑：每隔这么久亮出一柄
const SKILL_DUR := 20.0   # 全部就位后持续时长
const MP_COST := 0.12     # 起手消耗（灵力上限的比例）
const MP_DRAIN := 0.035   # 开着期间每秒消耗（灵力上限的比例）

var player: Player
var swords: Array[FlyingSword] = []
var auto_attack := true
var active := false       # 技能开着（召剑中 / 已就位）

var _want := 0            # 本次召出的总柄数（随境界）
var _spawn_cd := 0.0
var _ready_t := -1.0      # 全部就位后经过的时间，-1 = 还没全部就位
var _keep := false        # 演示用：不计时散去
var _cd := 0.0
var _ang := 0.0
var _time := 0.0
var _burst_left := 0
var _burst_cd := 0.0
var _ring_of := PackedInt32Array()
var _ring_idx := PackedInt32Array()
var _ring_cnt := PackedInt32Array()
var _art := 0             # 法相档位（Realm.art）


func _ready() -> void:
	process_priority = 10


## 换境界：所有飞剑换色 / 换剑光；技能开着时按新数量补齐（逐柄亮出）或收掉多余的，并换成新阵型
func apply_realm(realm: Dictionary) -> void:
	_art = Realm.art(realm)
	if active:
		_want = realm["swords"]
		while swords.size() > _want:
			var s: FlyingSword = swords.pop_back()
			s.dismiss()
		_layout(_want)
	for i in swords.size():
		swords[i].set_color(realm["col_a"] as Color, color_for(i))
		swords[i].set_art(_art)


## 第 i 柄的剑色：炼虚按所在的簇取五行色，大乘三色轮流，其余用境界主色
func color_for(i: int) -> Color:
	var r := player.realm
	match _art:
		4:
			return Vfx.FIVE_ELEM[i % 5]
		6:
			var cols := Realm.lines(r)
			return cols[i % cols.size()]
	return Realm.line_color(r)


## Q：没开 → 扣起手灵力、召剑、阵名化作 3D 题字；开着（召剑中或已就位）→ 收起
func toggle_summon() -> void:
	if active:
		dismiss_all()
		return
	var cost := player.mp_max() * MP_COST
	if player.mp < cost:
		Vfx.cast_flash(player.center(), Color(0.55, 0.6, 0.7), 0.6)
		Sfx.play("block", -10.0, 0.7)
		return
	player.mp -= cost
	summon()
	Calligraphy.show_text(str(Realm.art_info(player.realm)["form"]), player.center(), Realm.line_color(player.realm))


## 召剑：飞剑逐柄在环位上亮出。instant=true 当帧全部就位；keep=true 不计时散去（演示用）
func summon(instant := false, keep := false) -> void:
	active = true
	_keep = keep
	player.mp_busy = not keep  # 演示用的常驻飞剑不耗灵力
	_art = Realm.art(player.realm)
	_want = player.realm["swords"]
	_layout(_want)
	_ready_t = -1.0
	_spawn_cd = 0.0
	_cd = 0.25
	Sfx.play("swing", -8.0, 0.75)
	if instant:
		while swords.size() < _want:
			_spawn_one()
		_ready_t = 0.0


## 收剑：所有飞剑原地收缩消失
func dismiss_all() -> void:
	active = false
	player.mp_busy = false
	_ready_t = -1.0
	_burst_left = 0
	var lc := Realm.line_color(player.realm)
	for s in swords:
		Vfx.glint(s.global_position, Color.WHITE.lerp(lc, 0.4), 0.45)
		s.dismiss()
	swords.clear()


## 全部飞剑已就位（可以出剑）
func is_ready() -> bool:
	return active and _ready_t >= 0.0


## 技能剩余秒数（HUD 用）；没开返回 -1
func time_left() -> float:
	if not active:
		return -1.0
	if _keep or _ready_t < 0.0:
		return SKILL_DUR
	return maxf(SKILL_DUR - _ready_t, 0.0)


func _spawn_one() -> void:
	var i := swords.size()
	var s := FlyingSword.new()
	s.mgr = self
	add_child(s)
	var so := slot_offset(i)
	s.place(so, slot_basis_for(i, so))
	swords.append(s)
	var r := player.realm
	s.set_color(r["col_a"] as Color, color_for(i))
	s.set_art(_art)
	s.spawn_pop()
	s.set_cloaked(player.dun_active)
	if not player.dun_active:
		Vfx.cast_flash(s.global_position, color_for(i), 0.55)
	Sfx.play("swing", -12.0, 1.5 + 0.03 * i)


## 遁光开始/结束：所有飞剑本体（含正在收起的）立刻隐藏/恢复
func set_cloaked(on: bool) -> void:
	for c in get_children():
		var s := c as FlyingSword
		if s != null:
			s.set_cloaked(on)


func _layout(n: int) -> void:
	# 低阶 / 默认：≤9 单环；≤18 双环；更多三环。外环更大更高且反向旋转
	# 元婴双环陀螺固定两环对半分；大乘剑莲固定三层
	var counts: Array[int] = []
	if _art == 2:
		var a := (n + 1) / 2
		counts = [a, n - a]
	elif _art == 6:
		var a := int(round(n * 0.25))
		var b := int(round(n * 0.33))
		counts = [a, b, n - a - b]
	elif n <= 9:
		counts = [n]
	elif n <= 18:
		var inner := int(round(n * 0.4))
		counts = [inner, n - inner]
	else:
		var a := int(round(n * 0.25))
		var b := int(round(n * 0.33))
		counts = [a, b, n - a - b]
	_ring_cnt = PackedInt32Array(counts)
	_ring_of.resize(n)
	_ring_idx.resize(n)
	var i := 0
	for r in counts.size():
		for k in counts[r]:
			_ring_of[i] = r
			_ring_idx[i] = k
			i += 1


func slot_offset(i: int) -> Vector3:
	var orbit := _orbit_offset(i)
	var k := player.melee_k
	if k < 0.001:
		return orbit
	return orbit.lerp(_fan_offset(i), k)


## 近战时飞剑收拢到背后，排成一面剑尖朝外的扇形，不挡对刀视线
func _fan_offset(i: int) -> Vector3:
	var n := maxi(swords.size(), 1)
	var a := 0.0 if n == 1 else lerpf(-1.05, 1.05, float(i) / float(n - 1))
	var fb := player.facing_basis()
	var back := fb * Vector3.BACK
	var right := fb * Vector3.RIGHT
	var rad := 0.55 + 0.012 * n
	return back * (0.42 + 0.03 * absf(a)) + Vector3.UP * 1.2 + (right * sin(a) + Vector3.UP * cos(a)) * rad


func slot_basis_for(i: int, off: Vector3) -> Basis:
	var k := player.melee_k
	if k < 0.5:
		return slot_basis(off) if _art == 0 else _orbit_xf(i).basis
	var fb := player.facing_basis()
	var y := (off - Vector3.UP * 1.2 - fb * Vector3.BACK * 0.42).normalized()
	var z := fb * Vector3.BACK
	z = (z - y * z.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


func _orbit_offset(i: int) -> Vector3:
	if _art != 0:
		return _orbit_xf(i).origin
	if i >= _ring_of.size():
		return Vector3(0, 1.2, 0)
	var r := _ring_of[i]
	var cnt := _ring_cnt[r]
	var dirn := 1.0 if r % 2 == 0 else -1.0
	var a := _ang * dirn * (1.0 - 0.22 * r) + TAU * float(_ring_idx[i]) / float(cnt)
	var rad := 1.3 + 0.04 * cnt + 0.95 * r
	var y := 1.05 + 0.4 * r + sin(_time * 2.0 + i * 1.7) * 0.07
	return Vector3(cos(a) * rad, y, sin(a) * rad)


## 剑尖沿 y、剑面尽量朝 z 的正交基
static func _basis_yz(y: Vector3, z: Vector3) -> Basis:
	var yy := y.normalized()
	var x := yy.cross(z)
	if x.length_squared() < 1e-6:
		x = yy.cross(Vector3.FORWARD if absf(yy.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, yy, x.cross(yy))


func _ring_slot(i: int, n: int) -> Vector3i:
	if i < _ring_of.size():
		var r := _ring_of[i]
		return Vector3i(r, _ring_idx[i], _ring_cnt[r])
	return Vector3i(0, i, n)


## 结丹起各阶阵型里第 i 柄的位姿（相对玩家脚底）：origin 为偏移，basis 剑尖 +Y、剑面 +Z
func _orbit_xf(i: int) -> Transform3D:
	var n := maxi(_want, 1)
	var t := float(i) / float(n)
	var fb := player.facing_basis()
	var back := fb * Vector3.BACK
	var right := fb * Vector3.RIGHT
	var bob := sin(_time * 2.0 + i * 1.7) * 0.07
	match _art:
		1:
			# 平卧剑轮：腰间一圈，剑身放平、剑尖顺着转向首尾追逐，转得比低阶快
			var a := _ang * 1.7 + TAU * t
			var out := Vector3(cos(a), 0.0, sin(a))
			var tang := Vector3(-sin(a), 0.0, cos(a))
			return Transform3D(_basis_yz(tang, Vector3.UP), out * (1.45 + 0.03 * n) + Vector3.UP * (1.0 + bob))
		2:
			# 双环陀螺：两环各斜 0.6 弧度、倾斜轴错开 90°，反向旋转，整体再慢慢进动
			var rs := _ring_slot(i, n)
			var dirn := 1.0 if rs.x == 0 else -1.0
			var a := _ang * 1.5 * dirn + TAU * float(rs.y) / float(maxi(rs.z, 1))
			var tilt := Basis(Vector3.RIGHT, 0.6) if rs.x == 0 else Basis(Vector3.FORWARD, 0.6)
			var g := Basis(Vector3.UP, _time * 0.5 * dirn) * tilt
			var p := g * (Vector3(cos(a), 0.0, sin(a)) * 1.65)
			var tang := g * (Vector3(-sin(a), 0.0, cos(a)) * dirn)
			return Transform3D(_basis_yz(tang, g * Vector3.UP), p + Vector3.UP * 1.2)
		3:
			# 背后光轮：背后竖起一面剑轮，剑尖朝外放射，绕轮心转
			var a := _ang * 1.1 + TAU * t
			var d := right * cos(a) + Vector3.UP * sin(a)
			var c := Vector3.UP * 1.6 + back * 0.75
			return Transform3D(_basis_yz(d, back), c + d * (1.1 + 0.035 * n))
		4:
			# 五行五簇：五个方位各立一簇（三柄上下叠起、剑尖朝上），整阵缓转
			var cl := i % 5
			var layer := i / 5
			var a := _ang * 0.45 + TAU * float(cl) / 5.0
			var out := Vector3(cos(a), 0.0, sin(a))
			var y := 0.55 + 0.5 * float(layer) + sin(_time * 1.6 + cl * 1.3) * 0.1
			return Transform3D(_basis_yz(Vector3.UP, out), out * (1.9 + 0.15 * float(layer % 2)) + Vector3.UP * y)
		5:
			# 双翼剑翅：从两肩向外展开的一对剑翼，内高短、外低长，缓缓扇动
			var s := -1.0 if i % 2 == 0 else 1.0
			var m := maxi((n + 1) / 2, 2)
			var k := clampf(float(i / 2) / float(m - 1), 0.0, 1.0)
			var flap := sin(_time * 2.4) * 0.14
			var th := lerpf(1.1, -0.45, k) + flap * (0.5 + k)
			var d := (right * s * cos(th) + Vector3.UP * sin(th) + back * 0.35).normalized()
			var anchor := Vector3.UP * 1.45 + back * 0.4 + right * s * 0.25
			return Transform3D(_basis_yz(d, back), anchor + d * (0.75 + 1.05 * k))
		6:
			# 三层剑莲：内低外高三圈花瓣，剑尖斜指天外，层层反向缓转
			var rs := _ring_slot(i, n)
			var r := float(rs.x)
			var dirn := 1.0 if rs.x % 2 == 0 else -1.0
			var a := _ang * 0.6 * dirn + TAU * (float(rs.y) + 0.5 * r) / float(maxi(rs.z, 1))
			var out := Vector3(cos(a), 0.0, sin(a))
			var tilt := 0.25 + 0.3 * r
			var tip := out * sin(tilt) + Vector3.UP * cos(tilt)
			var face := out * cos(tilt) - Vector3.UP * sin(tilt)
			return Transform3D(_basis_yz(tip, face), out * (0.9 + 0.7 * r) + Vector3.UP * (0.55 + 0.25 * r + bob))
	return Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))


## 竖立姿态：剑面朝外
func slot_basis(off: Vector3) -> Basis:
	var out := Vector3(off.x, 0.0, off.z)
	out = out.normalized() if out.length_squared() > 1e-6 else Vector3.BACK
	var y := Vector3.DOWN if TIP_DOWN else Vector3.UP
	var x := y.cross(out).normalized()
	return Basis(x, y, out)


func pick_enemy(from: Vector3, rng: float, exclude: EnemyDummy = null) -> EnemyDummy:
	var pool: Array[EnemyDummy] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyDummy
		if e == null or not e.alive or e == exclude:
			continue
		if e.aim_point().distance_squared_to(from) <= rng * rng:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _launch_one() -> bool:
	var idle: Array[FlyingSword] = []
	for s in swords:
		if s.is_idle():
			idle.append(s)
	if idle.is_empty():
		return false
	var rng: float = player.realm["range"]
	var e := pick_enemy(player.center(), rng)
	if e == null:
		return false
	idle[randi() % idle.size()].strike(e, int(player.realm["chain"]))
	return true


## 万剑齐发：所有待命飞剑依次出击（飞剑全部就位后才行）
func burst() -> void:
	if not is_ready():
		return
	_burst_left = swords.size()
	_burst_cd = 0.0


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("summon"):
		toggle_summon()
	elif e.is_action_pressed("burst") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# 地面上左键归近战、空战中左键归法术连段，万剑齐发改用 E；御剑 / 光遁飞行中左键照旧
		if e is InputEventMouseButton and (player.st == Player.St.GROUND or player.st == Player.St.AIR):
			return
		burst()
	elif e.is_action_pressed("toggle_auto"):
		auto_attack = not auto_attack


func _process(dt: float) -> void:
	_time += dt
	_ang += dt * 1.1
	if active and swords.size() < _want:
		_spawn_cd -= dt
		if _spawn_cd <= 0.0:
			_spawn_cd = SPAWN_GAP
			_spawn_one()
	elif active and _ready_t < 0.0:
		# 最后一柄的弹出动画走完再开始出剑
		_spawn_cd -= dt
		if _spawn_cd <= SPAWN_GAP - 0.3:
			_ready_t = 0.0
	if _ready_t >= 0.0:
		_ready_t += dt
		if not _keep and _ready_t >= SKILL_DUR:
			dismiss_all()
	# 技能开着（召剑中 / 已就位）持续耗灵力，耗尽即散
	if active and not _keep:
		player.mp = maxf(player.mp - player.mp_max() * MP_DRAIN * dt, 0.0)
		if player.mp <= 0.0:
			dismiss_all()
			Sfx.play("block", -10.0, 0.7)
	# 化光冲天的那半秒不出新剑，保持起飞画面只有丝线
	var rising := player.dun_active and player.st == Player.St.TAKEOFF
	# 近战拔剑时飞剑在背后待命，不自动出剑
	if is_ready() and auto_attack and not rising and player.melee_k < 0.5:
		_cd -= dt
		if _cd <= 0.0:
			_cd = float(player.realm["atk_cd"]) if _launch_one() else 0.1
	if _burst_left > 0:
		_burst_cd -= dt
		while _burst_cd <= 0.0 and _burst_left > 0:
			_launch_one()
			_burst_left -= 1
			_burst_cd += 0.035
	for i in swords.size():
		swords[i].tick(dt, i)
