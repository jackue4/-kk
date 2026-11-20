extends Node3D
## 大世界里的固定搜点（2026-11-20 搜打撤改造第二档）：东西不再只从怪身上来，地图上有固定的值钱去处。
##   藏物陶罐 jar   草原和各区边上最多，读条短，一两件小东西
##   灵药圃   herb  各区域的灵草（炼丹的主料），偶尔有守着的妖兽
##   古修坟冢 grave 两三件，品阶高一点，常有妖兽徘徊
##   禁制宝库 vault 读条长（9 秒）、一开始破禁就亮光柱、引来一拨守卫（多半带精英）；东西最好，常出破境丹
##   宗门宝罐 urn   每个首领巢穴边上一只，首领守着
## 位置是固定的（同一个种子，每局、每个人都一样，可以记图）；里面出什么每局现摇。越往外圈、越危险的区域越值钱。
## 站在搜点旁边就自动读条（手机上不用按键）；挨一下打读条倒退 1.5 秒，走开慢慢回落。搜完的东西直接进背包，装不下的掉在脚边。
## 联机：搜完发一条「§s」播报（raid_manager.net_send），别人那边同一个搜点也变成已搜。
## 循环世界：搜点的位置每次 tick 都换到离主角最近的像（Data.near），节点只在 190 米内建、240 米外拆。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Models := preload("res://scripts/creature_model.gd")
const RING := preload("res://shaders/mob_ring.gdshader")

const SEED := 20261120
## name 名字 | t 读条秒数 | n 出几件 | bonus 掉落加成 | r 站多近算在旁边 | col 底下法阵的颜色 | verb 读条时的字
const KINDS := {
	"jar": {"name": "藏物陶罐", "t": 1.4, "n": [1, 2], "bonus": 0.0, "r": 3.2, "col": Color(0.92, 0.78, 0.55), "verb": "翻找陶罐…"},
	"herb": {"name": "灵药圃", "t": 2.4, "n": [2, 3], "bonus": 0.0, "r": 3.6, "col": Color(0.45, 0.95, 0.55), "verb": "采药中…"},
	"grave": {"name": "古修坟冢", "t": 3.0, "n": [2, 3], "bonus": 0.5, "r": 3.6, "col": Color(0.75, 0.78, 0.85), "verb": "搜检遗骸…"},
	"vault": {"name": "禁制宝库", "t": 9.0, "n": [4, 5], "bonus": 1.4, "r": 4.6, "col": Color(0.78, 0.45, 1.0), "verb": "破除禁制…别挨打"},
	"urn": {"name": "宗门宝罐", "t": 4.5, "n": [3, 4], "bonus": 1.0, "r": 3.8, "col": Color(1.0, 0.75, 0.3), "verb": "撬开宝罐…"},
}
## 各区域放几个：[陶罐, 灵药圃, 坟冢, 宝库]
const COUNTS := [[9, 6, 3, 1], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3]]
const URN_MODELS := ["urn_giant", "urn_lava", "urn_dragon", "chest_ruin", "urn_void"]
const BUILD_R := 190.0
const FREE_R := 240.0

var mgr: Node3D                  # raid_manager.gd
var sites: Array = []            # {id, kind, region, base: Vector2, pos: Vector3, done, known, node, guard, prog, live}
var reveal_t := 0.0              # 寻宝符还亮着几秒
var active: Dictionary = {}      # 正在读条的那个（没有为空）
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_place()


# ---------- 摆位置（固定种子）----------

func _place() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = SEED
	var taken: Array[Vector2] = []
	for p: Dictionary in Data.pois():
		taken.append(p["pos"])
	var kinds := ["jar", "herb", "grave", "vault"]
	for ri in 5:
		var cnt: Array = COUNTS[ri]
		for ki in 4:
			for n in int(cnt[ki]):
				var at := _spot(r, ri, str(kinds[ki]), taken)
				if at.x > 1.0e8:
					continue
				taken.append(at)
				_add(str(kinds[ki]), ri, at)
	# 宗门宝罐：每个巢穴边上一只（往世界中心那一侧挪一点，落在巢穴的台子上）
	for p: Dictionary in Data.pois():
		if str(p["kind"]) != "boss":
			continue
		var bp: Vector2 = p["pos"]
		var off := (-bp).normalized() * (14.0 if int(p["region"]) == 0 else 20.0) if bp.length() > 1.0 else Vector2(14.0, 0.0)
		_add("urn", int(p["region"]), bp + off.rotated(0.35))


func _add(kind: String, ri: int, at: Vector2) -> void:
	sites.append({"id": sites.size(), "kind": kind, "region": ri, "base": at, "pos": Vector3(at.x, 0.0, at.y),
			"done": false, "known": false, "node": null, "guard": false, "prog": 0.0, "live": false})


## 在区域 ri 里找一块能放 kind 的平地；找不到返回一个很远的点
func _spot(r: RandomNumberGenerator, ri: int, kind: String, taken: Array[Vector2]) -> Vector2:
	for attempt in 80:
		var at := Vector2.ZERO
		if ri == 0:
			var lo := 250.0 if kind == "vault" else 60.0
			var hi := Data.R0 - 50.0
			var rr := sqrt(r.randf_range(lo * lo, hi * hi))
			at = Vector2.from_angle(r.randf() * TAU) * rr
		else:
			var d: Vector2 = Data.REGIONS[ri]["dir"]
			var lo := Data.R0 + (330.0 if kind == "vault" else 70.0)
			var hi := Data.PLAY_R - 70.0
			var rr := sqrt(r.randf_range(lo * lo, hi * hi))
			at = d.rotated(r.randf_range(-0.62, 0.62)) * rr
		if Data.region_at(at.x, at.y) != ri:
			continue
		var ok := true
		for q: Vector2 in taken:
			if q.distance_to(at) < (55.0 if kind == "vault" else 38.0):
				ok = false
				break
		if not ok:
			continue
		var h := _h(at.x, at.y)
		if h < Data.REGIONS[ri]["water_h"] + 1.5:
			continue      # 云海 / 海面上不放
		var flat := true
		for o: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			if absf(_h(at.x + o.x, at.y + o.y) - h) > 2.6:
				flat = false
				break
		if flat:
			return at
	return Vector2(1.0e9, 1.0e9)


func _h(x: float, z: float) -> float:
	return mgr.level.ground(x, z)


# ---------- 每 0.4 秒：换像、建 / 拆节点、探明、守卫 ----------

func tick(p: Vector3, seek: float) -> void:
	var see := 70.0 * (1.0 + seek)
	for s: Dictionary in sites:
		var b: Vector2 = s["base"]
		var img := Data.near2(b, Vector2(p.x, p.z))
		var pos: Vector3 = s["pos"]
		if absf(pos.x - img.x) > 0.5 or absf(pos.z - img.y) > 0.5 or not bool(s["live"]):
			pos = Vector3(img.x, _h(img.x, img.y), img.y)
			s["pos"] = pos
			s["live"] = true
			if is_instance_valid(s["node"]):
				(s["node"] as Node3D).global_position = pos
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if not bool(s["known"]) and (d < see or (reveal_t > 0.0 and d < 400.0)):
			s["known"] = true
		var n: Variant = s["node"]
		if d < BUILD_R and not is_instance_valid(n):
			s["node"] = _build(s)
		elif d > FREE_R and is_instance_valid(n):
			(n as Node3D).queue_free()
			s["node"] = null
		# 守卫：走近灵药圃 / 坟冢时，有一定机会窜出一两只妖兽（只判一次）
		if not bool(s["guard"]) and not bool(s["done"]) and d < 46.0:
			s["guard"] = true
			var k := str(s["kind"])
			var chance := 0.4 if k == "herb" else (0.55 if k == "grave" else 0.0)
			if _rng.randf() < chance:
				mgr.spawn_guards(pos, int(s["region"]), 1 if k == "herb" else 2, false, false)


## 每帧：站在搜点旁边读条
func step(dt: float, p: Vector3, hurt: bool, speed: float) -> float:
	var best: Dictionary = {}
	var bd := INF
	for s: Dictionary in sites:
		if bool(s["done"]) or not is_instance_valid(s["node"]):
			if float(s["prog"]) > 0.0:
				s["prog"] = maxf(float(s["prog"]) - dt, 0.0)
			continue
		var pos: Vector3 = s["pos"]
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		var info: Dictionary = KINDS[str(s["kind"])]
		if d < float(info["r"]) and absf(p.y - pos.y) < 5.0 and d < bd:
			bd = d
			best = s
		elif float(s["prog"]) > 0.0:
			s["prog"] = maxf(float(s["prog"]) - dt * 0.5, 0.0)      # 走开了：慢慢回落
	active = best
	if best.is_empty():
		return 0.0
	var info2: Dictionary = KINDS[str(best["kind"])]
	var t := float(info2["t"])
	var was := float(best["prog"])
	if hurt:
		best["prog"] = maxf(was - 1.5, 0.0)      # 挨一下倒退 1.5 秒（守卫要先清掉，不然宝库开不完）
		return float(best["prog"]) / t
	best["prog"] = was + dt * speed
	if str(best["kind"]) == "vault" and not bool(best.get("alarm", false)):
		best["alarm"] = true
		_vault_alarm(best)
	if float(best["prog"]) >= t:
		_finish(best)
		active = {}
		return 0.0
	return float(best["prog"]) / t


func verb() -> String:
	if active.is_empty():
		return ""
	return str(KINDS[str(active["kind"])]["verb"])


## 开始破禁：光柱大亮、守卫扑上来（多半带精英），联机时别人也能在小地图上看到
func _vault_alarm(s: Dictionary) -> void:
	var pos: Vector3 = s["pos"]
	mgr.spawn_guards(pos, int(s["region"]), 3, _rng.randf() < 0.65, true)
	mgr.hud.toast("禁制震动，守卫被惊动了！", Color(0.85, 0.55, 1.0))
	mgr.ping(pos, 2)
	var n: Variant = s["node"]
	if is_instance_valid(n) and (n as Node3D).has_meta("beam"):
		var beam: Node3D = (n as Node3D).get_meta("beam")
		beam.scale = Vector3(2.2, 1.8, 2.2)


func _finish(s: Dictionary) -> void:
	s["done"] = true
	s["prog"] = 0.0
	var info: Dictionary = KINDS[str(s["kind"])]
	var ri := int(s["region"])
	var n := _rng.randi_range(int(info["n"][0]), int(info["n"][1]))
	var items: Array = []
	match str(s["kind"]):
		"herb":
			for i in n:
				items.append(Items.herb(ri if _rng.randf() > 0.12 or ri >= 4 else ri + 1))
			if _rng.randf() < 0.2:
				items.append(Items.pill(Data.roll_tier(ri, _rng)))
		"vault":
			items = Items.roll(ri, n, _rng, float(info["bonus"]))
			if _rng.randf() < 0.45:
				items.append(Items.key(clampi(ri + 1 + (1 if _rng.randf() < 0.3 else 0), 1, 7)))
		_:
			items = Items.roll(ri, n, _rng, float(info["bonus"]))
	mgr.site_loot(items, s["pos"], "%s" % info["name"])
	_dress_done(s)
	mgr.net_send("§s", str(int(s["id"])))


## 别人搜完了（联机）：这边也标成已搜
func mark_done(id: int) -> void:
	if id < 0 or id >= sites.size():
		return
	var s: Dictionary = sites[id]
	if bool(s["done"]):
		return
	s["done"] = true
	s["prog"] = 0.0
	if is_same(active, s):
		active = {}
	_dress_done(s)


## 搜过的样子：灵草拔光、宝箱 / 陶罐收走、光柱熄灭，法阵变暗
func _dress_done(s: Dictionary) -> void:
	var n: Variant = s["node"]
	if not is_instance_valid(n):
		return
	var root: Node3D = n
	for c in root.get_children():
		if c.has_meta("loot"):
			(c as Node3D).visible = false
	if root.has_meta("beam"):
		(root.get_meta("beam") as Node3D).visible = false
	if root.has_meta("ring"):
		var rm := (root.get_meta("ring") as MeshInstance3D).material_override as ShaderMaterial
		rm.set_shader_parameter("tint", Color(0.35, 0.33, 0.32))
		rm.set_shader_parameter("power", 0.25)
	if root.has_meta("label"):
		(root.get_meta("label") as Label3D).modulate = Color(0.7, 0.68, 0.66, 0.6)


# ---------- 造型 ----------

func _model(root: Node3D, key: String, size: float, at: Vector3, yaw: float, loot: bool) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	if loot:
		holder.set_meta("loot", true)
	root.add_child(holder)
	var info := Models.place(key, holder, Models.shadows)
	if info.is_empty():
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size * 0.8, size) * 0.7
		box.mesh = bm
		box.position.y = bm.size.y * 0.5
		holder.add_child(box)
		return
	var mroot: Node3D = info["root"]
	var bb: AABB = info["aabb"]
	var k := size / maxf(maxf(bb.size.x, bb.size.y), maxf(bb.size.z, 0.01))
	mroot.scale = Vector3.ONE * k
	var c := bb.get_center()
	mroot.position = Vector3(-c.x * k, -bb.position.y * k, -c.z * k)


func _build(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = s["pos"]
	var kind := str(s["kind"])
	var info: Dictionary = KINDS[kind]
	var col: Color = info["col"]
	var ri := int(s["region"])
	var r := RandomNumberGenerator.new()
	r.seed = SEED + int(s["id"]) * 7919
	var ring_r := 2.6
	match kind:
		"jar":
			var jn := 2 + r.randi() % 2
			for i in jn:
				var a := TAU * float(i) / float(jn) + r.randf() * 0.6
				_model(root, "jar_painted" if r.randf() < 0.4 else "jar_clay", r.randf_range(0.8, 1.15), Vector3(cos(a), 0.0, sin(a)) * 0.9, r.randf() * TAU, true)
		"herb":
			var key := str(Items.HERB_MODELS[ri])
			for i in 5:
				var a := TAU * float(i) / 5.0 + r.randf() * 0.5
				_model(root, key, r.randf_range(0.7, 1.05), Vector3(cos(a), 0.0, sin(a)) * r.randf_range(0.6, 1.8), r.randf() * TAU, true)
			ring_r = 3.0
		"grave":
			_model(root, "grave_stele", 2.0, Vector3(0.0, 0.0, -0.8), r.randf_range(-0.3, 0.3), false)
			_model(root, "bone", 0.8, Vector3(0.7, 0.0, 0.6), r.randf() * TAU, true)
			_model(root, "jar_clay", 0.7, Vector3(-0.8, 0.0, 0.5), r.randf() * TAU, true)
		"vault":
			_model(root, "altar_rune", 3.0, Vector3.ZERO, r.randf() * TAU, false)
			_model(root, "chest_gold", 1.2, Vector3(0.0, 1.05, 0.0), r.randf() * TAU, true)
			ring_r = 4.2
			var beam := _beam(root, col, 70.0, 1.4)
			root.set_meta("beam", beam)
		"urn":
			_model(root, str(URN_MODELS[ri]), 1.6, Vector3.ZERO, r.randf() * TAU, true)
			ring_r = 2.8
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ring_r * 2.0, ring_r * 2.0)
	ring.mesh = pm
	var rm := ShaderMaterial.new()
	rm.shader = RING
	rm.set_shader_parameter("tint", col)
	rm.set_shader_parameter("power", 0.75)
	rm.set_shader_parameter("spokes", 8.0 if kind == "vault" else 0.0)
	ring.material_override = rm
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	root.set_meta("ring", ring)
	if Vfx.font != null:
		var l := Label3D.new()
		l.text = str(info["name"])
		l.font = Vfx.font
		l.font_size = 34
		l.pixel_size = 0.006
		l.outline_size = 8
		l.modulate = Color.WHITE.lerp(col, 0.45)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position.y = 3.6 if kind == "vault" else 2.4
		l.visibility_range_end = 60.0
		root.add_child(l)
		root.set_meta("label", l)
	if bool(s["done"]):
		_dress_done(s)
	return root


func _beam(parent: Node3D, col: Color, height: float, width: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	for i in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(width, height)
		q.mesh = qm
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lm.albedo_color = Color(col.r, col.g, col.b, 0.32)
		lm.disable_fog = true
		q.material_override = lm
		q.position.y = height * 0.5
		q.rotation.y = PI * 0.5 * float(i)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
	return root


# ---------- 小地图 / 自检用 ----------

## 已探明、没搜过、在 range 米内的搜点：[位置, 种类]
func marks(p: Vector3, range_m: float) -> Array:
	var out: Array = []
	for s: Dictionary in sites:
		if not bool(s["known"]) or bool(s["done"]) or not bool(s["live"]):
			continue
		var pos: Vector3 = s["pos"]
		if Vector2(pos.x - p.x, pos.z - p.z).length() < range_m:
			out.append([pos, str(s["kind"])])
	return out


func count_kind(kind: String) -> int:
	var n := 0
	for s: Dictionary in sites:
		if str(s["kind"]) == kind:
			n += 1
	return n
