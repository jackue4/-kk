class_name EnemyDummy
extends Node3D
## 木人桩：受击闪白 + 弹簧晃动 + 伤害数字；击破后延时复活。
## kind: 0 地面  1 浮空  2 绕圈巡游

var kind := 0
var max_hp := 400.0
var hp := 400.0
var alive := true
var home := Vector3.ZERO

var _t := 0.0
var _wob := Vector3.ZERO
var _wob_v := Vector3.ZERO
var _flash := 0.0
var _model: Node3D
var _mat: StandardMaterial3D
var _bar: MeshInstance3D
var _respawn := 0.0


func _ready() -> void:
	add_to_group("enemies")
	_t = randf() * 10.0
	home = position
	_model = Node3D.new()
	add_child(_model)
	_mat = MeshLib.std_mat(Color(0.78, 0.33, 0.27), 0.75)
	_mat.emission_enabled = true
	_mat.emission = Color(1, 1, 1)
	_mat.emission_energy_multiplier = 0.0
	var wood := MeshLib.std_mat(Color(0.42, 0.4, 0.4), 0.9)

	var torso := CapsuleMesh.new()
	torso.radius = 0.32
	torso.height = 1.0
	_add(torso, _mat, Vector3(0, 1.1, 0))
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	_add(head, _mat, Vector3(0, 1.88, 0))
	var arm := CylinderMesh.new()
	arm.top_radius = 0.06
	arm.bottom_radius = 0.06
	arm.height = 1.3
	_add(arm, wood, Vector3(0, 1.3, 0), Vector3(0, 0, 90))
	if kind == 0:
		var post := CylinderMesh.new()
		post.top_radius = 0.1
		post.bottom_radius = 0.14
		post.height = 0.7
		_add(post, wood, Vector3(0, 0.35, 0))
		var base := CylinderMesh.new()
		base.top_radius = 0.4
		base.bottom_radius = 0.45
		base.height = 0.1
		_add(base, wood, Vector3(0, 0.05, 0))
	else:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.38
		ring.outer_radius = 0.46
		_add(ring, wood, Vector3(0, 0.45, 0))

	_bar = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 0.09)
	_bar.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.95, 0.3, 0.25)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.no_depth_test = true
	_bar.material_override = bm
	_bar.position.y = 2.4
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	_model.add_child(mi)


func aim_point() -> Vector3:
	return global_position + Vector3(0.0, 1.15, 0.0)


func take_hit(dmg: float, dir: Vector3, color: Color) -> void:
	if not alive:
		return
	hp -= dmg
	_flash = 1.0
	_wob_v += Vector3(dir.x, 0.0, dir.z) * 7.0
	Vfx.damage_number(aim_point() + Vector3(0, 0.8, 0), dmg, color)
	if hp <= 0.0:
		alive = false
		_respawn = 2.5
		# 碎成方块再消融：按各部件的基本体体积采样成小方块（颜色取部件材质）
		var parts := []
		for n in _model.get_children():
			var mi := n as MeshInstance3D
			parts.append([mi, (mi.material_override as StandardMaterial3D).albedo_color])
		var hit := aim_point() - dir.normalized() * 0.25
		Vfx.shatter(_model, hit, dir, Color.WHITE.lerp(color, 0.55), 1.1, parts, 0.11)
		_model.visible = false
		_bar.visible = false
		Vfx.ribbon_burst(hit, Vector3.UP, color, 8, 7.0, 160.0, 0.4)


func _process(dt: float) -> void:
	_t += dt
	if kind == 1:
		position = home + Vector3(0, sin(_t * 0.9) * 1.2, 0)
	elif kind == 2:
		position = home + Vector3(cos(_t * 0.55) * 7.0, sin(_t * 0.8) * 0.8, sin(_t * 0.55) * 7.0)

	if not alive:
		_respawn -= dt
		if _respawn <= 0.0:
			alive = true
			hp = max_hp
			_model.visible = true
			_bar.visible = true
			_model.scale = Vector3.ONE * 0.01
			var tw := create_tween()
			tw.tween_property(_model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return

	_flash = maxf(_flash - dt * 7.0, 0.0)
	_mat.emission_energy_multiplier = _flash * 1.2
	_wob_v += (-_wob * 140.0 - _wob_v * 9.0) * dt
	_wob += _wob_v * dt
	_model.rotation.x = clampf(_wob.z * 0.16, -0.6, 0.6)
	_model.rotation.z = clampf(-_wob.x * 0.16, -0.6, 0.6)
	_bar.scale.x = maxf(hp / max_hp, 0.001)
