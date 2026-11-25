extends Node3D
## 营救天工师（研究所，SPEC 4.10；2026-11-24 E_core）。只管「人」本身：模型、跟随走位、联机木偶的插值、头顶的字。
## 什么时候刷、归谁、距离警告 / 失去归属、带着时刷尸傀、撤离奖励、联机消息都在 extract_manager.gd 的「天工师」一节。
## 模型 assets/creatures/doctor.glb（资源库 虚空博士_310101）：原始贴图 alpha 全 0（B_mobs 拷贝时已去掉透明通道），这里再把材质强制成不透明，免得整只看不见。
## 跟随：保持 FOLLOW_KEEP 米；离持有者超过 STOP_R 米就停下等（管理器另按 10~15 米警告、>15 米 5 秒失去归属）；移速 = 主角地面跑速 × 0.8；
##   每一步问关卡的 block_fn（不穿墙），贴 floor_fn（能跟着上楼梯 / 下坡道）。
## 联机：持有者那台机器模拟位置（remote = false），别人那边 remote = true，按收到的位置（每秒 3 次）插值。
## 故意不写 class_name：用 preload 引用。

const Models := preload("res://scripts/creature_model.gd")
const RING := preload("res://shaders/mob_ring.gdshader")

const FOLLOW_KEEP := 3.0       # 跟在持有者身后这么远
const STOP_R := 10.0           # 离持有者超过这么远就停下（SPEC：超过 10 米停下）
const SPEED := 5.8             # 走路速度（主角地面跑速 7.2 × 0.8）
const HEIGHT := 1.9            # 模型缩到这么高（粗壮方块人约 1.9 米）
const COL := Color(0.7, 0.85, 1.0)

var floor_fn := Callable()     # func(x, z, y) -> float：关卡的 floor_at（脚在 y 的人站在多高）
var block_fn := Callable()     # func(from, to) -> bool：关卡的 blocked（走得过去吗）
var font: Font
var remote := false            # 别人持有：位置跟着收到的走
var target: Node3D = null      # 跟着谁（本机主角 / 别人的木偶）；null = 原地等人
var mode_i := 0                # 0 等人 / 1 跟着 / 2 离太远停下
var moved := 0.0               # 自检：一共走了多远

var _net_pos := Vector3.INF
var _net_yaw := 0.0
var _anim: AnimationPlayer
var _clips := {}
var _cur := ""
var _tag: Label3D
var _yaw := 0.0
var _gone := false


func _ready() -> void:
	var info := Models.place("doctor", self, false)
	if not info.is_empty():
		var root: Node3D = info["root"]
		var bb: AABB = info["aabb"]
		var k := HEIGHT / maxf(bb.size.y, 0.01)
		root.scale = Vector3.ONE * k
		var c := bb.get_center()
		root.position = Vector3(-c.x * k, -bb.position.y * k, -c.z * k)
		_force_opaque(info["meshes"])
		_anim = info.get("anim")
		_clips = info.get("clips", {})
	else:
		_build_blocks()
	var ring := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(2.4, 2.4)
	ring.mesh = rp
	var rm := ShaderMaterial.new()
	rm.shader = RING
	rm.set_shader_parameter("tint", COL)
	rm.set_shader_parameter("power", 0.8)
	rm.set_shader_parameter("spokes", 4.0)
	ring.material_override = rm
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_tag = Label3D.new()
	_tag.font = font if font != null else Vfx.font
	_tag.font_size = 44
	_tag.pixel_size = 0.006
	_tag.outline_size = 10
	_tag.modulate = COL.lerp(Color.WHITE, 0.4)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position.y = HEIGHT + 0.55
	add_child(_tag)
	_refresh_tag()
	_play("idle")
	Vfx.reappear(global_position + Vector3.UP, COL)


## 贴图透明通道全 0 的模型：材质一律换成不透明的副本（透明度关掉、alpha 拉满）
func _force_opaque(meshes: Array) -> void:
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			var d := m.duplicate() as BaseMaterial3D
			d.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			d.albedo_color.a = 1.0
			d.cull_mode = BaseMaterial3D.CULL_BACK
			mi.set_surface_override_material(s, d)


## 模型缺失时：白大褂方块人
func _build_blocks() -> void:
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.9, 0.92, 0.95)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.92, 0.76, 0.62)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.25, 0.22, 0.3)
	for e: Array in [[Vector3(0.7, 0.9, 0.4), Vector3(0, 1.15, 0), coat], [Vector3(0.5, 0.5, 0.5), Vector3(0, 1.85, 0), skin],
			[Vector3(0.28, 0.75, 0.3), Vector3(-0.18, 0.38, 0), dark], [Vector3(0.28, 0.75, 0.3), Vector3(0.18, 0.38, 0), dark]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[0]
		mi.mesh = bm
		mi.material_override = e[2]
		mi.position = e[1]
		add_child(mi)


func _play(role: String) -> void:
	if _anim == null or role == _cur:
		return
	var nm: String = str(_clips.get(role, _clips.get("walk" if role == "run" else "idle", "")))
	if nm == "" or not _anim.has_animation(nm):
		return
	_cur = role
	_anim.play(nm, 0.2)


func _refresh_tag() -> void:
	if _tag == null:
		return
	match mode_i:
		1:
			_tag.text = "天工师 · 随行"
		2:
			_tag.text = "天工师 · 跟不上了"
		_:
			_tag.text = "天工师 · 待救"


func center() -> Vector3:
	return global_position + Vector3.UP * 1.0


## 跟着 n 走（null = 原地等人）
func follow(n: Node3D) -> void:
	target = n
	mode_i = 1 if n != null else 0
	_refresh_tag()


## 联机：持有者发来的位置
func push(pos: Vector3, yaw: float, mode: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if mode != mode_i:
		mode_i = mode
		_refresh_tag()


func snap_floor() -> void:
	if floor_fn.is_valid():
		var p := global_position
		global_position.y = float(floor_fn.call(p.x, p.z, p.y + 1.0))


## 被救走 / 入夜消失
func vanish() -> void:
	if _gone:
		return
	_gone = true
	Vfx.vanish(center(), COL)
	queue_free()


func _process(dt: float) -> void:
	if _gone:
		return
	var p := global_position
	var spd := 0.0
	if remote:
		if _net_pos.is_finite():
			var np := p.lerp(_net_pos, 1.0 - exp(-8.0 * dt)) if p.distance_to(_net_pos) < 20.0 else _net_pos
			spd = np.distance_to(p) / maxf(dt, 0.001)
			global_position = np
			_yaw = lerp_angle(_yaw, _net_yaw, 1.0 - exp(-10.0 * dt))
	elif target != null and is_instance_valid(target):
		var tp := target.global_position
		var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
		var d := to.length()
		var m0 := mode_i
		if d > STOP_R:
			mode_i = 2
		else:
			mode_i = 1
			if d > FOLLOW_KEEP:
				var dir := to / d
				var step := minf(SPEED * dt, d - FOLLOW_KEEP)
				var np2 := p + dir * step
				if block_fn.is_valid() and bool(block_fn.call(p, np2)):
					# 撞墙：只走 X / 只走 Z
					var nx := p + Vector3(dir.x * step, 0.0, 0.0)
					var nz := p + Vector3(0.0, 0.0, dir.z * step)
					if not bool(block_fn.call(p, nx)):
						np2 = nx
					elif not bool(block_fn.call(p, nz)):
						np2 = nz
					else:
						np2 = p
				if floor_fn.is_valid():
					np2.y = float(floor_fn.call(np2.x, np2.z, p.y + 1.0))
				spd = np2.distance_to(p) / maxf(dt, 0.001)
				moved += np2.distance_to(p)
				global_position = np2
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * dt))
		if m0 != mode_i:
			_refresh_tag()
	rotation.y = _yaw
	_play("run" if spd > 4.0 else ("walk" if spd > 0.4 else "idle"))
