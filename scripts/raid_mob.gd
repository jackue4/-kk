extends Node3D
## 搜打撤的小怪 / 区域 Boss（数据见 raid_data.gd 的 MOBS）。
## 造型是几块方块拼的（四足兽 / 浮空 / 人形巨汉），不带骨架，手机上十来只同屏也便宜。
## 行为：闲逛 → 发现主角追上去 → 蓄势（身上一闪）→ 扑击 / 吐弹 → 喘息。Boss 另有震地（脚下一圈预警后炸开）。
## 伤害出入口和现有三套战斗都接上：
##   · 地面近战（PlayerMelee 找 "swordsmen" 组）：receive_hit / is_hostile / is_airborne / chip_colors …
##   · 飞剑 / 法术（spell_projectile.gd 找 "air_foes" 组）：receive_hit
##   · 空战拳脚（air_melee.gd）：air_hit，重击可以把小怪打飞、砸地
##   打主角：主角在地面走 PlayerMelee.receive_attack（能弹反 / 格挡 / 闪避），在空战走 AirMelee.receive_attack。
## 故意不写 class_name：用 preload 引用。

signal died(mob: Node3D)

const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Data := preload("res://scripts/raid_data.gd")

enum S { IDLE, CHASE, WIND, STRIKE, RECOVER, STUN, BLOWN, SLAM, DEAD }

const AGGRO := 26.0
const LEASH := 70.0
const G := 22.0

var player: Player
var def: Dictionary = {}
var region := 0
var hp_max := 100.0
var hp := 100.0
var atk := 6.0
var display_name := "妖兽"
var boss := false
var floor_fn := Callable()     # func(x, z) -> 地面高度
var home := Vector3.ZERO
var state := S.IDLE
## 数值（raid_manager.gd 生成时填，算法见 raid_data.gd）：lv 等级；elite 精英（生命 ×4、伤害 ×2，身上泛光、个头大一圈）
var lv := 1
var elite := false
var xp_k := 1.0
var roaming := false           # 游荡 Boss（不守巢穴）
var dmg_in := Callable()       # func(主角打出的伤害) -> 实际扣的血（按主角等级换算）
var atk_out := Callable()      # func(怪的伤害) -> 打在主角 100 点血条上的值
## 被别的修士（AI）引走：追着它打，打中调它的 mob_hit；主角一动手就转回来打主角
## 联机：puppet = 别人名下的怪在自己这边的木偶（不跑 AI，按主人发来的位置 / 血量走；挨打把伤害发回给主人）
var puppet := false
var net_owner := 0
var net_id := 0
var net_hit := Callable()      # func(木偶, info)：打在木偶上
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_stale := 0.0
var decoy: Node3D = null
var slain_by_rival := false

var _body: Node3D
var _mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _dur := 0.0
var _vel := Vector3.ZERO
var _facing := 0.0
var _cd := 1.0
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _hit_done := false
var _flash := 0.0
var _size := 1.0
var _float := false
var _ranged := false
var _spd := 7.0
var _bolts: Array = []
var _bar: MeshInstance3D
var _tag: Label3D
var _slam_cd := 6.0
var _slam_pos := Vector3.ZERO
var _phase := 0.0
var _legs: Array[Node3D] = []


func _ready() -> void:
	add_to_group("swordsmen")
	add_to_group("air_foes")
	home = global_position
	display_name = ("精英·" if elite else "") + str(def["name"])
	boss = def.get("boss", false)
	_size = float(def["size"]) * (1.25 if elite else 1.0)
	_float = def["shape"] == "floater"
	_ranged = def["ranged"]
	_spd = def["spd"]
	hp = hp_max
	_cd = randf_range(0.5, 1.5)
	_phase = randf() * TAU
	_build()


func _exit_tree() -> void:
	for b: Array in _bolts:
		if is_instance_valid(b[0]):
			(b[0] as Node).queue_free()
	_bolts.clear()


# ---------- 造型 ----------
## 每种怪的方块合并成三个网格（身体一个、两组肢体各一个），同种怪共用；一只怪只有三次绘制调用，不投影。

static var _mesh_cache := {}


static func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


## 返回 [身体网格, 肢体 A 网格, 肢体 B 网格, 肢体轴心 A, 肢体轴心 B]
static func _meshes(d: Dictionary) -> Array:
	var key: String = d["name"]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cols: Array = d["cols"]
	var a: Color = cols[0]
	var b: Color = cols[1]
	var e: Color = cols[2]
	e = Color(e.r * 1.8, e.g * 1.8, e.b * 1.8)
	var body := SurfaceTool.new()
	var la := SurfaceTool.new()
	var lb := SurfaceTool.new()
	for st: SurfaceTool in [body, la, lb]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pa := Vector3(0, 0.6, 0)
	var pb := Vector3(0, 0.6, 0)
	match str(d["shape"]):
		"beast":
			Data.add_box(body, Vector3(0.7, 0.6, 1.5), _at(Vector3(0, 0.85, 0)), a)
			Data.add_box(body, Vector3(0.6, 0.55, 0.6), _at(Vector3(0, 1.1, -0.95)), a)
			Data.add_box(body, Vector3(0.4, 0.3, 0.4), _at(Vector3(0, 0.98, -1.35)), b)
			Data.add_box(body, Vector3(0.16, 0.3, 0.12), _at(Vector3(-0.2, 1.5, -0.85)), b)
			Data.add_box(body, Vector3(0.16, 0.3, 0.12), _at(Vector3(0.2, 1.5, -0.85)), b)
			Data.add_box(body, Vector3(0.12, 0.1, 0.06), _at(Vector3(-0.17, 1.2, -1.26)), e)
			Data.add_box(body, Vector3(0.12, 0.1, 0.06), _at(Vector3(0.17, 1.2, -1.26)), e)
			Data.add_box(body, Vector3(0.18, 0.18, 0.8), _at(Vector3(0, 1.0, 1.05)), b)
			# 对角的两条腿一组：一组前摆时另一组后摆
			Data.add_box(la, Vector3(0.2, 0.6, 0.22), _at(Vector3(-0.28, -0.3, -0.5)), b)
			Data.add_box(la, Vector3(0.2, 0.6, 0.22), _at(Vector3(0.28, -0.3, 0.5)), b)
			Data.add_box(lb, Vector3(0.2, 0.6, 0.22), _at(Vector3(0.28, -0.3, -0.5)), b)
			Data.add_box(lb, Vector3(0.2, 0.6, 0.22), _at(Vector3(-0.28, -0.3, 0.5)), b)
		"floater":
			Data.add_box(body, Vector3(0.8, 0.8, 0.8), _at(Vector3(0, 1.0, 0)), a)
			Data.add_box(body, Vector3(0.2, 0.16, 0.06), _at(Vector3(-0.2, 1.08, -0.42)), e)
			Data.add_box(body, Vector3(0.2, 0.16, 0.06), _at(Vector3(0.2, 1.08, -0.42)), e)
			Data.add_box(body, Vector3(0.3, 0.5, 0.3), _at(Vector3(0, 0.4, 0.1)), b)
			pa = Vector3(-0.4, 1.25, 0.1)
			pb = Vector3(0.4, 1.25, 0.1)
			Data.add_box(la, Vector3(0.7, 0.08, 0.5), _at(Vector3(-0.35, 0, 0)), b)
			Data.add_box(lb, Vector3(0.7, 0.08, 0.5), _at(Vector3(0.35, 0, 0)), b)
		_:
			Data.add_box(body, Vector3(1.0, 0.9, 0.55), _at(Vector3(0, 1.45, 0)), a)
			Data.add_box(body, Vector3(0.55, 0.5, 0.5), _at(Vector3(0, 2.15, 0)), b)
			Data.add_box(body, Vector3(0.34, 0.1, 0.06), _at(Vector3(0, 2.2, -0.27)), e)
			pa = Vector3(0, 1.4, 0)
			pb = Vector3(0, 1.4, 0)
			# 左臂 + 右腿一组，右臂 + 左腿一组
			Data.add_box(la, Vector3(0.34, 1.0, 0.36), _at(Vector3(-0.68, -0.1, 0)), b)
			Data.add_box(la, Vector3(0.38, 1.0, 0.4), _at(Vector3(0.26, -0.9, 0)), a)
			Data.add_box(lb, Vector3(0.34, 1.0, 0.36), _at(Vector3(0.68, -0.1, 0)), b)
			Data.add_box(lb, Vector3(0.38, 1.0, 0.4), _at(Vector3(-0.26, -0.9, 0)), a)
	var out := [body.commit(), la.commit(), lb.commit(), pa, pb]
	_mesh_cache[key] = out
	return out


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_body.scale = Vector3.ONE * _size
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	m.set_meta("glow", false)
	if elite:
		# 精英：整身泛着发光色
		var ec: Color = (def["cols"] as Array)[2]
		m.emission = ec
		m.emission_energy_multiplier = 0.55
		m.set_meta("glow", true)
	_mats.append(m)
	var ms := _meshes(def)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = ms[i]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 0:
			_body.add_child(mi)
		else:
			var piv := Node3D.new()
			piv.position = ms[2 + i]
			_body.add_child(piv)
			piv.add_child(mi)
			_legs.append(piv)
	# 血条（挨过打或是 Boss 才显示）+ 名牌（只有 Boss）
	_bar = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2 * maxf(_size, 1.0), 0.09 * maxf(_size, 1.0))
	_bar.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.95, 0.3, 0.25)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.no_depth_test = true
	_bar.material_override = bm
	_bar.position.y = top_y() + 0.35
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = boss or elite
	add_child(_bar)
	if (boss or elite) and Vfx.font != null:
		_tag = Label3D.new()
		_tag.text = "%s  Lv.%d" % [display_name, lv]
		_tag.font = Vfx.font
		_tag.font_size = 64
		_tag.pixel_size = 0.008 if boss else 0.0045
		_tag.outline_size = 12
		_tag.modulate = Color(1.0, 0.5, 0.4)
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.position.y = top_y() + 0.9
		add_child(_tag)


func top_y() -> float:
	return (2.5 if def["shape"] == "brute" else 1.7) * _size


# ---------- 查询（三套战斗共用的接口） ----------

func is_alive() -> bool:
	return state != S.DEAD


func is_hostile() -> bool:
	return state != S.IDLE and state != S.DEAD


func is_broken() -> bool:
	return false


func is_airborne() -> bool:
	return state == S.BLOWN or _float


func is_downed() -> bool:
	return false


func is_launched() -> bool:
	return state == S.BLOWN


func velocity() -> Vector3:
	return _vel


func center() -> Vector3:
	return global_position + Vector3(0.0, (1.5 if def["shape"] == "brute" else 0.95) * _size, 0.0)


func aim_point() -> Vector3:
	return center()


func hit_radius() -> float:
	return maxf(_size - 1.0, 0.0) * 0.8


func blade_hand() -> Vector3:
	return center()


func blade_tip() -> Vector3:
	return center() + Basis(Vector3.UP, _facing) * Vector3(0.0, 0.0, -1.2 * _size)


func chip_colors() -> Array:
	var cols: Array = def["cols"]
	return [cols[0], cols[0], cols[1], cols[2]]


func hp_ratio() -> float:
	return hp / hp_max


func posture_ratio() -> float:
	return 0.0


func state_name() -> String:
	match state:
		S.WIND, S.SLAM:
			return "蓄势"
		S.STRIKE:
			return "扑击"
		S.STUN:
			return "硬直"
		S.BLOWN:
			return "击飞"
		S.RECOVER:
			return "破绽"
	return "游荡" if state == S.IDLE else "追击"


func begin_deathblow() -> void:
	pass


func deathblow_hit(_dir: Vector3) -> void:
	pass


func _ground(x: float, z: float) -> float:
	return float(floor_fn.call(x, z)) if floor_fn.is_valid() else 0.0


func _enter(s: S, dur := 0.0) -> void:
	state = s
	_t = 0.0
	_dur = dur


# ---------- 受击 ----------

## 被飞剑对波的空间波动震开（Boss 纹丝不动）
func blast_away(from: Vector3, spd: float) -> void:
	if state == S.DEAD or boss:
		return
	var d := center() - from
	d = (Vector3(d.x, 0.0, d.z).normalized() + Vector3.UP * 0.3).normalized() if d.length_squared() > 0.01 else Vector3.UP
	_enter(S.BLOWN, 0.9)
	_vel = d * spd
	_flash = 0.6


## 联机：主人发来的最新状态
func net_push(pos: Vector3, yaw: float, hp_r: float, st: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_stale = 0.0
	hp = hp_r * hp_max
	state = st as S
	_bar.visible = boss or elite or hp_r < 0.999


## 联机：主人说它死了
func net_die() -> void:
	if state == S.DEAD:
		return
	state = S.DEAD
	var cols: Array = def["cols"]
	Vfx.death_burst(center(), cols[2])
	Vfx.debris(center(), Vector3.UP, chip_colors(), 26 if boss else 12, 7.0, 1.6 * _size)
	Sfx.play("execute" if boss else "hit_heavy", -5.0, 0.9)
	queue_free()


## 联机：别人打在我名下这只怪上的伤害（已经按对方的等级换算过）
func net_damage(dmg: float, dir: Vector3, heavy: bool, launch: String, kb: float) -> void:
	if state == S.DEAD or puppet:
		return
	_take_raw(dmg, dir, heavy)
	if state == S.DEAD:
		return
	if state == S.IDLE:
		_enter(S.CHASE)
	if boss:
		return
	if launch != "":
		_enter(S.BLOWN, 1.6)
		_vel = dir * kb * 0.8
	elif state != S.BLOWN:
		_enter(S.STUN, 0.35)
		_vel = Vector3(dir.x, 0.0, dir.z) * minf(kb, 4.0)


func _tick_puppet(dt: float) -> void:
	_net_stale += dt
	if _net_stale > 1.5:
		queue_free()   # 主人不再发它了（走远回收 / 主人离开）
		return
	var before := global_position
	global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * dt)) if global_position.distance_to(_net_pos) < 25.0 else _net_pos
	_facing = lerp_angle(_facing, _net_yaw, 1.0 - exp(-10.0 * dt))
	rotation.y = _facing
	var spd := global_position.distance_to(before) / maxf(dt, 1e-3)
	_phase += dt * (4.0 + spd * 1.2)
	var sw := sin(_phase) * clampf(spd / maxf(_spd, 1.0), 0.0, 1.0)
	for i in _legs.size():
		if _float:
			_legs[i].rotation.z = sin(_phase * 2.0) * 0.6 * (1.0 if i == 0 else -1.0)
		else:
			_legs[i].rotation.x = sw * (0.7 if i % 2 == 0 else -0.7)
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 7.0, 0.0)
		for m in _mats:
			if not bool(m.get_meta("glow")):
				m.emission_energy_multiplier = _flash * 1.3
	_bar.scale.x = maxf(hp / hp_max, 0.001)


## 马上盯上主角（导演刷出来的怪不用等主角走近）
func alert() -> void:
	if state == S.IDLE:
		_enter(S.CHASE)
		home = player.global_position


func _target_valid() -> bool:
	return decoy != null and is_instance_valid(decoy) and bool(decoy.call("is_alive"))


## 别的修士打过来的伤害（不走主角的换算）
func sim_damage(dmg: float, dir: Vector3, from: Node3D) -> void:
	if state == S.DEAD:
		return
	decoy = from
	slain_by_rival = true
	_take_raw(dmg, dir, false)
	slain_by_rival = false
	if state == S.DEAD:
		return
	if state == S.IDLE:
		_enter(S.CHASE)
	if not boss and state != S.BLOWN and state != S.STRIKE:
		_enter(S.STUN, 0.25)
		_vel = Vector3(dir.x, 0.0, dir.z) * 2.0


func _take(dmg: float, dir: Vector3, heavy: bool) -> void:
	decoy = null
	_take_raw(float(dmg_in.call(dmg)) if dmg_in.is_valid() else dmg, dir, heavy)


func _take_raw(dmg: float, dir: Vector3, heavy: bool) -> void:
	hp = maxf(hp - dmg, 0.0)
	_flash = 1.0
	_bar.visible = true
	Vfx.damage_number(center() + Vector3(0, 0.6 * _size, 0), dmg, Color(1.0, 0.85, 0.5) if heavy else Color.WHITE)
	if hp <= 0.0:
		_die(dir)


## 地面近战 / 飞剑 / 法术
func receive_hit(_attacker: Node3D, info: Dictionary) -> int:
	if state == S.DEAD:
		return -1
	if puppet:
		_flash = 1.0
		net_hit.call(self, info)
		return 0
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	_take(float(info.get("dmg", 10.0)), dir, heavy)
	if state == S.DEAD:
		return 0
	if state == S.IDLE:
		_enter(S.CHASE)
	if not boss and state != S.BLOWN:
		_enter(S.STUN, 0.45 if heavy else 0.3)
		_vel = Vector3(dir.x, 0.0, dir.z) * float(info.get("kb", 2.0))
	return 0


## 空战拳脚 / 重击：小怪可以被打飞，Boss 只吃伤害和短硬直
func air_hit(_attacker: Node3D, info: Dictionary) -> int:
	if state == S.DEAD:
		return -1
	if puppet:
		_flash = 1.0
		net_hit.call(self, info)
		return 0
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	var launch: String = info.get("launch", "")
	_take(float(info.get("dmg", 10.0)), dir, heavy)
	if state == S.DEAD:
		return 0
	if boss:
		if heavy and state != S.SLAM:
			_enter(S.STUN, 0.35)
		return 0
	if launch != "":
		_enter(S.BLOWN, 1.6)
		_vel = dir * float(info.get("kb", 20.0)) * 0.8
	else:
		_enter(S.STUN, float(info.get("stun", 0.4)))
		_vel = dir * float(info.get("kb", 3.0))
	return 0


func _die(dir: Vector3) -> void:
	_enter(S.DEAD)
	var cols: Array = def["cols"]
	Vfx.death_burst(center(), cols[2])
	Vfx.debris(center(), dir + Vector3.UP * 0.4, chip_colors(), 26 if boss else 12, 7.0, 1.6 * _size)
	Sfx.play("execute" if boss else "hit_heavy", -3.0, 0.9)
	if boss:
		Vfx.shockwave(center(), Vector3.UP, cols[2], 3.0)
		Combat.slowmo(0.25, 0.25, 0.4)
	died.emit(self)
	queue_free()


# ---------- 打主角 ----------

## 返回 2 被弹反 / 瞬身 · 1 被挡 · 0 命中 · -1 无效
func _hit_player(dmg: float, heavy: bool, dir: Vector3, ranged: bool) -> int:
	if _target_valid():
		decoy.call("mob_hit", dmg, dir, self, heavy)
		return 0
	if atk_out.is_valid():
		dmg = float(atk_out.call(dmg))
	if player.st == Player.St.GROUND:
		return player.melee.receive_attack(self, {"dmg": dmg, "heavy": heavy, "block_pst": 14.0, "hit_pst": 10.0})
	if player.st == Player.St.AIR:
		return player.air.receive_attack(self, {"dmg": dmg, "heavy": heavy, "kb": 22.0 if heavy else 6.0, "dir": dir,
				"contact": player.center(), "ranged": ranged})
	return -1


func _fire(n: int) -> void:
	var cols: Array = def["cols"]
	var from := center() + Basis(Vector3.UP, _facing) * Vector3(0.0, 0.2, -0.8 * _size)
	var aim: Vector3 = (decoy.call("center") as Vector3) if _target_valid() else player.center() + player.velocity * 0.2
	var to := aim - from
	var d := to.normalized() if to.length_squared() > 0.01 else Vector3.FORWARD
	for i in n:
		var a := (float(i) - float(n - 1) * 0.5) * 0.22
		var mi := Vfx.persistent_sprite(cols[2], 2)
		_bolts.append([mi, from, d.rotated(Vector3.UP, a) * (26.0 + 2.0 * float(region)), 2.4])
	Vfx.cast_flash(from, cols[2], 0.6 * _size)
	Sfx.play("swing", -9.0, 1.4)


func _tick_bolts(dt: float) -> void:
	var i := _bolts.size() - 1
	while i >= 0:
		var b: Array = _bolts[i]
		var pos: Vector3 = b[1]
		var v: Vector3 = b[2]
		var life: float = float(b[3]) - dt
		var np := pos + v * dt
		var done := life <= 0.0
		if not done:
			var c: Vector3 = (decoy.call("center") as Vector3) if _target_valid() else player.center()
			if Geometry3D.get_closest_point_to_segment(c, pos, np).distance_to(c) < 0.9:
				if _hit_player(atk * 0.7, false, v.normalized(), true) != -1:
					Vfx.hit(c, v.normalized(), (def["cols"] as Array)[2], 0.8)
					done = true
		if done:
			(b[0] as Node).queue_free()
			_bolts.remove_at(i)
		else:
			b[1] = np
			b[3] = life
			Vfx.place_streak(b[0] as Node3D, np, v.normalized(), 1.4, 0.2)
		i -= 1


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	var cdt := Combat.cdt(dt)
	_t += cdt
	_cd -= cdt
	_slam_cd -= cdt
	_tick_bolts(dt)
	if puppet:
		_tick_puppet(dt)
		return
	if state == S.DEAD or player == null:
		return
	var lured := _target_valid()
	var pc: Vector3 = (decoy.call("center") as Vector3) if lured else player.center()
	var to := pc - center()
	var dist := to.length() - hit_radius()
	var flat := Vector3(to.x, 0.0, to.z)
	var fdir := flat.normalized() if flat.length_squared() > 0.01 else Vector3.FORWARD
	var p := global_position
	var gy := _ground(p.x, p.z)
	var hover := gy + (2.2 if _float else 0.0)
	var cols: Array = def["cols"]

	match state:
		S.IDLE:
			_wander_t -= cdt
			if _wander_t <= 0.0:
				_wander_t = randf_range(2.0, 5.0)
				var a := randf() * TAU
				_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 9.0)
			var w := _wander - p
			w.y = 0.0
			_vel = w.limit_length(1.0) * _spd * 0.25
			if w.length() > 0.5:
				_facing = lerp_angle(_facing, atan2(-w.x, -w.z), 1.0 - exp(-4.0 * cdt))
			if lured or (dist < AGGRO * (1.6 if boss else 1.0) and not player.dun_active):
				_enter(S.CHASE)
				Vfx.glint(center() + Vector3.UP * _size, cols[2], 1.0 * _size)
		S.CHASE:
			_facing = lerp_angle(_facing, atan2(-fdir.x, -fdir.z), 1.0 - exp(-8.0 * cdt))
			if roaming:
				home = p
			if p.distance_to(home) > LEASH * (2.0 if boss else 1.0) or dist > 90.0:
				_enter(S.IDLE)
				home = p
			else:
				var keep := 9.0 if _ranged and not boss else 1.6 * _size
				var want := fdir * _spd * clampf((dist - keep) / 2.0, -0.6, 1.0)
				_vel = _vel.move_toward(want, 40.0 * cdt)
				if _float:
					hover = clampf(pc.y - 0.9, gy + 1.5, gy + 60.0)
				if boss and _slam_cd <= 0.0 and dist < 9.0:
					_slam_cd = randf_range(7.0, 10.0)
					_enter(S.SLAM, 1.0)
					_slam_pos = Vector3(p.x, gy, p.z)
					_vel = Vector3.ZERO
					Vfx.cast_charge(_slam_pos + Vector3.UP * 0.2, Color(1.0, 0.3, 0.2), 1.0)
					Sfx.play("swing_heavy", -6.0, 0.6)
				elif _cd <= 0.0 and ((_ranged and dist < 26.0) or dist < 2.6 * _size + 0.8):
					_enter(S.WIND, 0.55 if not boss else 0.7)
					Vfx.glint(center() + fdir * 0.6 * _size, Color(1.0, 0.9, 0.8), 0.9 * _size)
		S.WIND:
			_vel = _vel.move_toward(-fdir * 1.5, 30.0 * cdt)
			_facing = lerp_angle(_facing, atan2(-fdir.x, -fdir.z), 1.0 - exp(-10.0 * cdt))
			if _t >= _dur:
				_enter(S.STRIKE, 0.4)
				_hit_done = false
				var melee := dist < 4.0 * _size + 1.0
				if _ranged and not melee:
					_fire(5 if boss else 1)
					_hit_done = true
				else:
					_vel = fdir * clampf(dist - 1.0, 0.0, 6.0 * _size) / 0.12
					if _float or lured or player.st != Player.St.GROUND:
						_vel.y = clampf(to.y, -6.0, 8.0) / 0.12
					Sfx.play("swing_heavy" if boss else "swing", -7.0, 0.85)
		S.STRIKE:
			if not _hit_done and _t >= 0.12:
				_hit_done = true
				if dist < 2.4 * _size + 0.6:
					var res := _hit_player(atk * (1.5 if boss else 1.0), boss, to.normalized(), false)
					if res == 2:
						_enter(S.STUN, 1.0)
			if _t >= 0.12:
				_vel = _vel.move_toward(Vector3.ZERO, 90.0 * cdt)
			if _t >= _dur and state == S.STRIKE:
				_enter(S.RECOVER, 0.7 if not boss else 0.9)
				_cd = randf_range(1.2, 2.2)
		S.SLAM:
			if _t >= _dur:
				Vfx.dun_slam(_slam_pos, cols[2], 1.6)
				Vfx.ground_break(_slam_pos, 1.3, 5.0)
				Sfx.play("slam", -1.0, 0.7)
				player.cam.add_trauma(0.5)
				var d := (pc - Vector3.UP) - _slam_pos
				if Vector2(d.x, d.z).length() < 8.0 and absf(d.y) < 4.0:
					_hit_player(atk * 2.0, true, (d.normalized() + Vector3.UP * 0.6).normalized(), false)
				_enter(S.RECOVER, 1.1)
		S.RECOVER:
			_vel = _vel.move_toward(Vector3.ZERO, 30.0 * cdt)
			if _t >= _dur:
				_enter(S.CHASE)
		S.STUN:
			_vel = _vel.move_toward(Vector3.ZERO, maxf(_vel.length() * 5.0, 8.0) * cdt)
			if _t >= _dur:
				_enter(S.CHASE)
		S.BLOWN:
			_vel.y -= G * cdt
			_vel -= _vel * 0.6 * cdt
			if p.y <= gy + 0.05 and _vel.y < 0.0:
				var spd := _vel.length()
				global_position.y = gy
				if spd > 12.0:
					Vfx.dun_slam(Vector3(p.x, gy, p.z), cols[2], 0.9)
					Vfx.crater(Vector3(p.x, gy, p.z), clampf(spd / 34.0, 0.6, 1.2))
					Sfx.play("slam", -4.0, 0.9)
					player.cam.add_trauma(0.3)
					_vel = Vector3.ZERO
					_take_raw(hp_max * 0.12, Vector3.DOWN, true)
					if state == S.DEAD:
						return
				_enter(S.STUN, 0.7)
			elif _t >= _dur:
				_enter(S.STUN, 0.3)

	if not Combat.frozen():
		global_position += _vel * cdt
	if state != S.BLOWN:
		# 贴地 / 悬浮高度
		var ty := hover if state != S.STRIKE or _float else maxf(global_position.y, gy)
		if state == S.STRIKE and not _float:
			_vel.y -= G * cdt
			global_position.y = maxf(global_position.y, gy)
		else:
			global_position.y = lerpf(global_position.y, ty, 1.0 - exp(-8.0 * cdt))
	rotation.y = _facing

	# 简单的肢体摆动：走动时腿前后摆，蓄势时下沉，浮空的上下浮动
	_phase += cdt * (4.0 + _vel.length() * 1.2)
	var sw := sin(_phase) * clampf(_vel.length() / maxf(_spd, 1.0), 0.0, 1.0)
	for i in _legs.size():
		if _float:
			_legs[i].rotation.z = sin(_phase * 2.0) * 0.6 * (1.0 if i == 0 else -1.0)   # 扇翅
		else:
			_legs[i].rotation.x = sw * (0.7 if i % 2 == 0 else -0.7)
	var squash := 0.0
	if state == S.WIND or state == S.SLAM:
		squash = clampf(_t / maxf(_dur, 0.01), 0.0, 1.0) * 0.22
	_body.scale = Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5) * _size
	_body.position.y = sin(_phase * 0.5) * 0.12 if _float else 0.0
	if state == S.BLOWN:
		_body.rotation.x += 9.0 * cdt
	else:
		_body.rotation.x = lerp_angle(_body.rotation.x, -0.35 if state == S.STRIKE else 0.0, 1.0 - exp(-12.0 * cdt))
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 7.0, 0.0)
		for m in _mats:
			if not bool(m.get_meta("glow")):
				m.emission_energy_multiplier = _flash * 1.3
	if _bar.visible:
		_bar.scale.x = maxf(hp / hp_max, 0.001)
