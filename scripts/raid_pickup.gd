extends Node3D
## 搜打撤的地面掉落：单件物品（走近自动拾取）或箱子（其他修士 / Boss 掉的，站在旁边读条开启，一次给出多件）。
## 造型用资源库的模型（creature_model.gd）：Boss 遗藏 = 大宝箱、精英遗物 = 小宝箱、修士的储物袋 = 锦囊；
##   单件：法器 = 钱袋、丹药 = 一颗按品阶染色的丹丸（破境丹大一圈）、灵材 = 聚宝盆 / 兽骨、灵草 = 各区域的灵草模型、符箓 = 卷轴。
##   模型缺失时退回按品阶染色的小方块。
## 品阶怎么看：底下一圈按品阶染色的法阵光 + 模型轮廓泛光；法宝及以上再立一道细光柱，远处也看得见。
## 拾取判定由 raid_manager.gd 统一做（不给每个掉落物挂碰撞体）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Models := preload("res://scripts/creature_model.gd")
const OVERLAY := preload("res://shaders/creature_overlay.gdshader")
const RING := preload("res://shaders/mob_ring.gdshader")

var item: Dictionary = {}     # 单件物品
var items: Array = []         # 箱子里的东西（非空 = 箱子）
var title := ""               # 箱子的名字（"韩立的储物袋"）
var open_t := 0.0             # 箱子已读条时间
var grace := 0.0              # 刚丢下 / 刚掉出来的一小段时间不拾取
var base_y := 0.0

var _box: Node3D              # 转动 / 浮动的那个节点（模型或方块挂在它下面）
var _t := 0.0

static var _pill_mats := {}   # 品阶 → 丹丸材质


func is_chest() -> bool:
	return not items.is_empty()


func tier() -> int:
	if is_chest():
		var best := 0
		for it: Dictionary in items:
			best = maxi(best, int(it["tier"]))
		return best
	return int(item.get("tier", 0))


## [模型名, 最长边缩到多少米]
func _look() -> Array:
	if is_chest():
		if title.ends_with("储物袋"):
			return ["pouch", 1.0]
		return ["chest", 1.05 if title == "精英的遗物" else 1.7]
	match str(item.get("kind", "")):
		"pill":
			return ["pearl", 0.44]
		"key":
			return ["pearl", 0.62]      # 破境丹：大一圈的丹丸
		"mat":
			return ["bone" if int(item.get("region", 0)) % 2 == 0 else "bowl", 0.85]
		"herb":
			return [str(Items.HERB_MODELS[clampi(int(item.get("region", 0)), 0, 4)]), 0.8]
		"tool":
			return ["scroll", 0.7]
	return ["purse", 0.85]


func _ready() -> void:
	_t = randf() * 6.0
	var col: Color = Data.TIER_COLORS[tier()]
	var chest := is_chest()
	_box = Node3D.new()
	add_child(_box)
	var look := _look()
	var info := Models.place(str(look[0]), _box, false)
	if info.is_empty():
		_build_block(col, chest)
	else:
		var root: Node3D = info["root"]
		var bb: AABB = info["aabb"]
		var k := float(look[1]) / maxf(maxf(bb.size.x, bb.size.y), maxf(bb.size.z, 0.01))
		root.scale = Vector3.ONE * k
		var c := bb.get_center()
		root.position = Vector3(-c.x * k, -bb.position.y * k, -c.z * k)
		if str(look[0]) == "pearl":
			# 丹丸：整颗按品阶染色
			if not _pill_mats.has(tier()):
				var pm := StandardMaterial3D.new()
				pm.albedo_color = col.lerp(Color.WHITE, 0.25)
				pm.roughness = 0.3
				pm.emission_enabled = true
				pm.emission = col
				pm.emission_energy_multiplier = 0.7
				_pill_mats[tier()] = pm
			for mi: MeshInstance3D in info["meshes"]:
				mi.material_override = _pill_mats[tier()]
		else:
			var ov := ShaderMaterial.new()
			ov.shader = OVERLAY
			ov.set_shader_parameter("tint", col)
			ov.set_shader_parameter("rim", 0.45 + 0.15 * float(tier()))
			for mi: MeshInstance3D in info["meshes"]:
				mi.material_overlay = ov
	# 底下一圈品阶色的法阵光
	var ring := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	var rr := (1.5 if chest else 0.55) + 0.06 * float(tier())
	rp.size = Vector2(rr * 2.0, rr * 2.0)
	ring.mesh = rp
	var rm := ShaderMaterial.new()
	rm.shader = RING
	rm.set_shader_parameter("tint", col)
	rm.set_shader_parameter("power", 0.9 if chest else 0.7)
	rm.set_shader_parameter("spokes", 6.0 if chest else 0.0)
	ring.material_override = rm
	ring.position.y = 0.1
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
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
		l.position.y = 2.0
		add_child(l)


## 老造型：按品阶染色的小方块（模型缺失时用）
func _build_block(col: Color, chest: bool) -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.6, 0.6) if chest else Vector3(0.36, 0.36, 0.36)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.26, 0.18) if chest else col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.5 if chest else 1.1
	box.material_override = m
	box.position.y = bm.size.y * 0.5
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.add_child(box)


func _process(dt: float) -> void:
	_t += dt
	grace -= dt
	if is_chest():
		# 箱子落地不转；正在开的时候抖动、鼓起来
		var k := clampf(open_t * 2.0, 0.0, 1.0)
		_box.rotation.y = sin(_t * 0.5) * 0.25 + sin(_t * 31.0) * 0.05 * k
		_box.scale = Vector3.ONE * (1.0 + 0.08 * k * (0.5 + 0.5 * sin(_t * 14.0)))
		_box.position.y = 0.05
	else:
		_box.rotation.y = _t * 1.8
		_box.position.y = 0.4 + sin(_t * 2.4) * 0.1
