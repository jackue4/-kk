extends RefCounted
## 生物 / 掉落物的模型库：assets/creatures 下的带骨骼 GLB（来自资源库「05_生物动画」），按名字取用。
## place() 把一个模型放到已经进树的节点下面，返回：
##   root   模型根节点（这批模型导进来就是脸朝 -Z，和游戏里其他东西一个朝向）
##   anim   AnimationPlayer（没有动画时是 null）
##   clips  {idle / walk / run / attack / hurt / death: 动画名}，缺的不在里面
##   aabb   待机姿势下的包围盒（root 的父节点空间），用来按身高缩放、把脚放到地面
##   meshes 所有 MeshInstance3D（挂受击闪光 / 精英泛光的 material_overlay 用）
## 动画名都以编号结尾（…_100100 待机、_100101 走、_100111 跑、_100105 攻击、_100107 受击、_100106 死亡），按编号认。
## 同一个模型的材质、动画资源是共用的，只在第一次用到时调整一遍（循环方式、贴图过滤）。
## 故意不写 class_name：用 preload 引用。

const DIR := "res://assets/creatures/"

## 各动作按顺序找的编号（前面的没有就用后面的）
const ROLES := {
	"idle": ["100100", "100204"],
	"walk": ["100101", "100111"],
	"run": ["100111", "100101"],
	"attack": ["100105", "100108", "100113", "100184", "100500", "100201"],
	"hurt": ["100107"],
	"death": ["100106"],
}
const LOOPED := ["idle", "walk", "run"]
const GLOW_FLOOR := 0.2     # 模型自带的底光：贴图色的这么多倍，不受光照和影子影响

static var _cache := {}   # 名字 → {scene, clips, aabb, ok}
static var shadows := true   # 模型投不投影（手机上关掉，meadow_level.gd 设）


static func has(key: String) -> bool:
	return key != "" and not _entry(key).is_empty()


static func _entry(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var e := {}
	var path := DIR + key + ".glb"
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			e = {"scene": ps, "ready": false, "clips": {}, "aabb": AABB()}
	if e.is_empty():
		push_warning("creature_model: 没有模型 " + key)
	_cache[key] = e
	return e


static func place(key: String, parent: Node3D, shadows := false) -> Dictionary:
	var e := _entry(key)
	if e.is_empty():
		return {}
	var root := (e["scene"] as PackedScene).instantiate() as Node3D
	if root == null:
		return {}
	parent.add_child(root)
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	var players: Array = root.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = players[0] if not players.is_empty() else null
	if not bool(e["ready"]):
		e["ready"] = true
		_prepare(e, root, anim, meshes)
	for mi: MeshInstance3D in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 骨骼动画会把顶点带出静态包围盒，给足余量免得在屏幕边上被裁掉
		mi.extra_cull_margin = 4.0
	var clips: Dictionary = e["clips"]
	if anim != null and clips.has("idle"):
		anim.play(str(clips["idle"]))
		anim.seek(randf() * 1.5, true)
	return {"root": root, "anim": anim, "clips": clips, "aabb": e["aabb"], "meshes": meshes}


## 第一次用到这个模型：认动画、设循环、调材质、量待机姿势的包围盒
static func _prepare(e: Dictionary, root: Node3D, anim: AnimationPlayer, meshes: Array) -> void:
	var clips := {}
	if anim != null:
		var names := anim.get_animation_list()
		for role: String in ROLES:
			for id: String in ROLES[role]:
				var hit := ""
				for n: String in names:
					if n.ends_with("_" + id) or n == id:
						hit = n
						break
				if hit != "":
					clips[role] = hit
					break
		for role: String in LOOPED:
			if clips.has(role):
				anim.get_animation(str(clips[role])).loop_mode = Animation.LOOP_LINEAR
		if clips.has("idle"):
			anim.play(str(clips["idle"]))
			anim.advance(0.0)
	e["clips"] = clips
	# 材质：方块世界里用最近点采样（像素贴图不糊）、不要金属高光
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				m.metallic = 0.0
				m.roughness = maxf(m.roughness, 0.8)
				# 自己带一点底光（按贴图本来的颜色）：站在影子里、站在暗的区域里也不会黑成一团。不多绘制调用
				if m.albedo_texture != null and not m.emission_enabled:
					m.emission_enabled = true
					m.emission_texture = m.albedo_texture
					m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					m.emission = Color.WHITE
					m.emission_energy_multiplier = GLOW_FLOOR
	# 包围盒：蒙皮网格烘成当前姿势再量
	var box := AABB()
	var first := true
	var inv := (root.get_parent() as Node3D).global_transform.affine_inverse()
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var bb := mi.get_aabb()
		if mi.skin != null and DisplayServer.get_name() != "headless":   # 无界面模式烘不了蒙皮，用静态包围盒
			for sk: Skeleton3D in root.find_children("*", "Skeleton3D", true, false):
				sk.force_update_all_bone_transforms()
			var baked := mi.bake_mesh_from_current_skeleton_pose()
			if baked != null and baked.get_surface_count() > 0:
				bb = baked.get_aabb()
		bb = (inv * mi.global_transform) * bb
		if OS.get_cmdline_user_args().has("--model-debug"):
			print("   [mesh] ", mi.name, " skin=", mi.skin != null, " ", bb)
		box = bb if first else box.merge(bb)
		first = false
	e["aabb"] = box
