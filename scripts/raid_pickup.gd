extends Node3D
## 搜打撤的地面掉落：单件物品（走近自动拾取）或箱子（其他修士 / Boss 掉的，站在旁边读条开启，一次给出多件）。
## 造型就是一个慢慢转的小方块，按品阶染色；法宝及以上再立一道细光柱，远处也看得见。
## 拾取判定由 raid_manager.gd 统一做（不给每个掉落物挂碰撞体）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")

var item: Dictionary = {}     # 单件物品
var items: Array = []         # 箱子里的东西（非空 = 箱子）
var title := ""               # 箱子的名字（"韩立的储物袋"）
var open_t := 0.0             # 箱子已读条时间
var grace := 0.0              # 刚丢下 / 刚掉出来的一小段时间不拾取
var base_y := 0.0

var _box: MeshInstance3D
var _t := 0.0


func is_chest() -> bool:
	return not items.is_empty()


func tier() -> int:
	if is_chest():
		var best := 0
		for it: Dictionary in items:
			best = maxi(best, int(it["tier"]))
		return best
	return int(item.get("tier", 0))


func _ready() -> void:
	_t = randf() * 6.0
	var col: Color = Data.TIER_COLORS[tier()]
	var chest := is_chest()
	_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.6, 0.6) if chest else Vector3(0.36, 0.36, 0.36)
	if not chest and item.get("kind", "") == "pill":
		bm.size = Vector3(0.28, 0.42, 0.28)
	_box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.26, 0.18) if chest else col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.5 if chest else 1.1
	_box.material_override = m
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_box)
	if chest:
		var band := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.94, 0.12, 0.64)
		band.mesh = b2
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = col
		m2.emission_enabled = true
		m2.emission = col
		m2.emission_energy_multiplier = 1.4
		band.material_override = m2
		band.position.y = 0.12
		_box.add_child(band)
	if chest or tier() >= 2:
		# 细光柱：一片朝天的加色面片（十字两片）
		for i in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.22 if not chest else 0.4, 9.0 if not chest else 16.0)
			q.mesh = qm
			var lm := StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			lm.cull_mode = BaseMaterial3D.CULL_DISABLED
			lm.albedo_color = Color(col.r, col.g, col.b, 0.35)
			q.material_override = lm
			q.position.y = qm.size.y * 0.5
			q.rotation.y = PI * 0.5 * float(i)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(q)
	if chest and Vfx.font != null:
		var l := Label3D.new()
		l.text = title
		l.font = Vfx.font
		l.font_size = 40
		l.pixel_size = 0.006
		l.outline_size = 8
		l.modulate = Color.WHITE.lerp(col, 0.5)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position.y = 1.5
		add_child(l)


func _process(dt: float) -> void:
	_t += dt
	grace -= dt
	_box.rotation.y = _t * (0.6 if is_chest() else 1.8)
	_box.position.y = (0.35 if is_chest() else 0.55 + sin(_t * 2.4) * 0.1)
