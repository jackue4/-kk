extends RefCounted
## 英雄技能共用的画面（2026-11-25 TSB 式重做）：方块搭的拳印 / 冰棱 / 光刃这类「体块」，加上现成的线条特效（vfx.gd）拼起来。
## 体块一律是方块：和方块小人、方块世界同一种质感；不受光、按面给明暗（顶面亮、侧面暗），半透明、不写深度。
## 联机：别人机器上只画不判伤害 —— 技能脚本放特效时调 net 的 send_hero_fx(kind, pos, dir, roll)，对面 net._hero_fx 收到后调这里的 remote()，
## 再按 kind 的号段转给各英雄技能脚本的 static remote_fx(kind, pos, dir, roll, col)：
##   10 ~ 39 镇岳（kit_zhenyue.gd）· 40 ~ 69 苍鸿（kit_canghong2.gd）· 70 ~ 99 霜华（kit_shuanghua.gd）；1 / 2 是苍鸿老的新月剑气（net.gd 里直接处理）
## 故意不写 class_name：用 preload 引用。

const MeshLib := preload("res://scripts/mesh_lib.gd")

const KITS := [
	[10, 39, "res://scripts/heroes/kit_zhenyue.gd"],
	[40, 69, "res://scripts/heroes/kit_canghong2.gd"],
	[70, 99, "res://scripts/heroes/kit_shuanghua.gd"],
]

## 网格缓存放在 Vfx.root 的 meta 上，不用 static var：这类 load() / preload 进来的脚本里静态变量攥着网格 / 材质，
## 退出时引擎会报一串「shaders were never freed / RIDs leaked」（角色二那条线二分出来的）
static func _cached(key: String) -> ArrayMesh:
	if Vfx.root != null and is_instance_valid(Vfx.root) and Vfx.root.has_meta(key):
		return Vfx.root.get_meta(key) as ArrayMesh
	return null


static func _keep(key: String, m: ArrayMesh) -> ArrayMesh:
	if Vfx.root != null and is_instance_valid(Vfx.root):
		Vfx.root.set_meta(key, m)
	return m


static func ok() -> bool:
	return Vfx.root != null and is_instance_valid(Vfx.root) and Vfx.root.is_inside_tree()


## 别人放的英雄技能画面（net.gd 的 _hero_fx）
static func remote(kind: int, pos: Vector3, dir: Vector3, roll: float, col: Color) -> void:
	if not ok():
		return
	for k: Array in KITS:
		if kind >= int(k[0]) and kind <= int(k[1]):
			if ResourceLoader.exists(str(k[2])):
				var ks: GDScript = load(str(k[2]))
				if ks != null and ks.has_method("remote_fx"):
					ks.call("remote_fx", kind, pos, dir, roll, col)
			return


## 把这一下画面发给别人（没联网 / 单机时什么都不做）
static func send(player: Node, kind: int, pos: Vector3, dir: Vector3, roll := 0.0) -> void:
	var net: Variant = player.get_meta("net") if player.has_meta("net") else null
	if net != null and is_instance_valid(net) and (net as Node).has_method("send_hero_fx"):
		(net as Node).call("send_hero_fx", kind, pos, dir, roll)


# ---------- 体块 ----------

## 不受光的半透明体块材质（按颜色缓存；每个节点自己 duplicate 一份去做淡出）
static func block_mat(color: Color, alpha := 0.8, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_BACK
	# 先写一遍深度再上色：体块是好几个方块叠起来的，不这样里面被挡住的面会透出来，看着一团乱
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if add else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.disable_fog = true
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m


## 体块的描边（方块小人那种勾线）：把网格往外撑一圈、只画背面的一遍深色，挂在主材质的 next_pass 上
static func outline_mat(color: Color, alpha := 0.9, grow := 0.045) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_fog = true
	m.grow = true
	m.grow_amount = grow
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m


## 往 SurfaceTool 里加一个方块（按面给明暗：顶 1.0、前后 0.82、左右 0.68、底 0.5）
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis.IDENTITY, tint := Color.WHITE) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, 1.0],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, 0.56],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, 0.88],
		[Vector3.BACK, Vector3.LEFT, Vector3.DOWN, 0.84],
		[Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, 0.72],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN, 0.72],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var k: float = f[3]
		var c := MeshLib.vcol(Color(tint.r * k, tint.g * k, tint.b * k, 1.0))
		var o := n * Vector3(h.x, h.y, h.z).dot(n.abs())
		var eu := u * h.dot(u.abs())
		var ev := v * h.dot(v.abs())
		var p0 := o - eu - ev
		var p1 := o + eu - ev
		var p2 := o + eu + ev
		var p3 := o - eu + ev
		var wn := (basis * n).normalized()
		for p: Vector3 in [p0, p2, p1, p0, p3, p2]:
			st.set_normal(wn)
			st.set_color(c)
			st.add_vertex(center + basis * p)


static func cube_mesh() -> ArrayMesh:
	var c := _cached("hfx_cube")
	if c != null:
		return c
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_box(st, Vector3.ZERO, Vector3.ONE)
	return _keep("hfx_cube", st.commit())


## 方块搭的拳头：拳面朝 -Z，一个单位大约一米宽
static func fist_mesh() -> ArrayMesh:
	var c := _cached("hfx_fist")
	if c != null:
		return c
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 从哪边看都得认得出是只拳头：四根手指各是一块、中间留缝，指根在手背上顶起一排骨节，拇指横压在拳面下半
	add_box(st, Vector3(0.0, -0.04, 0.16), Vector3(0.98, 0.8, 0.86), Basis.IDENTITY, Color(0.9, 0.9, 0.9))    # 手背 / 掌
	for i in 4:
		var fx := -0.375 + 0.25 * float(i)
		var fh := 0.56 if i == 1 or i == 2 else 0.5
		add_box(st, Vector3(fx, 0.16, -0.46), Vector3(0.21, fh, 0.42))                # 四指的第一节（拳面）
		add_box(st, Vector3(fx, 0.42, -0.12), Vector3(0.19, 0.16, 0.3))               # 指根的骨节（手背上顶起来的一排）
		add_box(st, Vector3(fx, -0.3, -0.36), Vector3(0.21, 0.3, 0.3), Basis.IDENTITY, Color(0.8, 0.8, 0.8))    # 蜷进去的指尖
	add_box(st, Vector3(0.14, -0.24, -0.66), Vector3(0.66, 0.24, 0.2), Basis(Vector3.BACK, 0.18))    # 拇指：横压在拳面下半
	add_box(st, Vector3(0.56, -0.2, -0.3), Vector3(0.22, 0.3, 0.56), Basis.IDENTITY, Color(0.86, 0.86, 0.86))  # 拇指根
	add_box(st, Vector3(0.0, -0.06, 0.84), Vector3(0.7, 0.62, 0.5), Basis.IDENTITY, Color(0.74, 0.74, 0.74))   # 腕
	add_box(st, Vector3(0.0, -0.06, 0.62), Vector3(0.84, 0.74, 0.12), Basis.IDENTITY, Color(1.0, 1.0, 1.0))    # 腕上一道箍
	return _keep("hfx_fist", st.commit())


## 一个体块节点（挂在 Vfx.root 下）：mesh 朝 dir（-Z 对准 dir）
static func block(mesh: Mesh, pos: Vector3, dir: Vector3, color: Color, size: float, alpha := 0.8, add := false, line := Color(0, 0, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var bm := block_mat(color, alpha, add)
	if line.a > 0.0:
		bm.next_pass = outline_mat(line, line.a)
	mi.material_override = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.97 else Vector3.BACK
	mi.global_transform = Transform3D(Basis.looking_at(d, up).scaled(Vector3.ONE * size), pos)
	return mi


## 淡出并销毁（材质必须是 block_mat 的）
static func fade_out(mi: MeshInstance3D, dur: float, delay := 0.0) -> void:
	var m := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	if m.next_pass != null:
		tw.parallel().tween_property(m.next_pass, "albedo_color:a", 0.0, dur * 0.8)
	tw.tween_callback(mi.queue_free)


## 拳印：一只方块拳头从 pos 沿 dir 打出去 travel 米（dur 秒），由小变大，到头淡掉。返回节点（调用方可以再加补间）
static func fist(pos: Vector3, dir: Vector3, color: Color, size: float, travel: float, dur: float, alpha := 0.8) -> MeshInstance3D:
	if not ok():
		return null
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	# 大拳印（两米以上）透一点、起点往前挪：不然刚打出来的那一瞬整只罩在出拳的人身上，人和对手都看不见了
	var big := clampf((size - 1.6) / 3.0, 0.0, 1.0)
	pos += d * size * 0.35 * big
	alpha = lerpf(alpha, minf(alpha, 0.56), big)
	# 透的体块描边也跟着淡（不然深色的那一圈从半透的身子里透出来，整只发乌）
	var mi := block(fist_mesh(), pos, d, Color.WHITE.lerp(color, 0.72), size * 0.45, alpha, false,
			Color(color.r * 0.5, color.g * 0.34, color.b * 0.2, lerpf(0.85, 0.3, big)))
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", pos + d * travel, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fade_out(mi, dur * 0.4, dur * 0.72)
	# 拳面前头一道线环（线条语言：体块只管形，亮边交给细线）
	if size >= 1.4 or not Vfx.lite:      # 手机档：连打里的小拳印不再各带一圈线环（一秒二十来只，线环比拳印本身还贵）
		Vfx.shockwave(pos + d * 0.6 * size, d, color, clampf(size * 0.55, 0.5, 3.0))
	return mi


## 一圈从地里拱出来的石块 / 冰块（震波扫过的地方）：n 块沿半径 r 的圈排开，先拱起再沉下去
static func block_ring(pos: Vector3, r: float, colors: Array, n: int, size := 0.7, rise := 1.2, hold := 0.5) -> void:
	if not ok() or colors.is_empty():
		return
	if Vfx.lite:
		n = int(ceil(float(n) * 0.6))
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + randf_range(-0.12, 0.12)
		var o := Vector3(cos(a), 0.0, sin(a)) * r * randf_range(0.9, 1.08)
		var s := size * randf_range(0.7, 1.35)
		var col: Color = colors[i % colors.size()]
		var mi := block(cube_mesh(), pos + o + Vector3(0.0, -s, 0.0), Vector3(cos(a + 0.6), 0.0, sin(a + 0.6)), col, s, 1.0)
		mi.rotation.x = randf_range(-0.5, 0.5)
		mi.rotation.z = randf_range(-0.5, 0.5)
		var top := pos + o + Vector3(0.0, rise * randf_range(0.55, 1.0) - s * 0.3, 0.0)
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", top, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(hold * randf_range(0.7, 1.2))
		tw.tween_property(mi, "global_position", pos + o + Vector3(0.0, -s * 1.2, 0.0), 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


## 沿一条线依次炸开的震波（拳劲 / 剑气犁过去）：len 米、每 gap 米一圈
static func shock_line(from: Vector3, dir: Vector3, length: float, color: Color, power := 1.0, gap := 3.2) -> void:
	if not ok():
		return
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var n := int(length / gap)
	if Vfx.lite:
		n = int(ceil(float(n) * 0.6))
		gap = length / maxf(float(n), 1.0)
	for i in n:
		var at := from + d * (gap * float(i + 1))
		var tw := Vfx.root.create_tween()
		tw.tween_interval(0.022 * float(i))
		tw.tween_callback(Vfx.shockwave.bind(at, d, color, power * (1.0 + 0.08 * float(i))))
	Vfx.line_sparks(from + d * 1.5, d, Color.WHITE.lerp(color, 0.4), 18 if not Vfx.lite else 9, 60.0, 14.0, 0.35)


## 地面在哪（英雄技能要贴地放东西时用）：镜头的 floor_fn；没有就按 y = 0
static func floor_y(player: Node, p: Vector3) -> float:
	var cam: Variant = player.get("cam")
	if cam != null and is_instance_valid(cam):
		var fn: Callable = cam.floor_fn
		if fn.is_valid():
			return float(fn.call(p.x, p.z))
	return 0.0


## 自己被冻住了（air_melee._hurt 收到带 freeze 的一下时调）：身上那层冰由霜华的技能脚本画（static frozen_fx(player, sec)）
static func frozen_self(player: Node, sec: float) -> void:
	var path := "res://scripts/heroes/kit_shuanghua.gd"
	if not ok() or not ResourceLoader.exists(path):
		return
	var ks: GDScript = load(path)
	if ks != null and ks.has_method("frozen_fx"):
		ks.call("frozen_fx", player, sec)


## 载入时预热（warmup.gd 的「推演新招」那一批调）：体块用到的几种材质各摆一个小的，编好着色器；
## 各英雄技能脚本有 static warm(holder, at, right) 的也调一下（它们自己的飞行道具 / 特殊材质）
static func warm(holder: Node3D, at: Vector3, right: Vector3) -> void:
	var gold := Color(1.0, 0.74, 0.28)
	var kinds: Array = [
		[fist_mesh(), block_mat(gold, 0.8), true],
		[cube_mesh(), block_mat(gold, 0.6, true), false],
		[cube_mesh(), block_mat(Color(0.6, 0.85, 1.0), 1.0), true],
	]
	for i in kinds.size():
		var mi := MeshInstance3D.new()
		mi.mesh = kinds[i][0]
		var m: StandardMaterial3D = kinds[i][1]
		if bool(kinds[i][2]):
			m.next_pass = outline_mat(Color(0.4, 0.25, 0.1), 0.8)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.3), at + right * (float(i) - 1.0) * 0.6)
	for k: Array in KITS:
		if ResourceLoader.exists(str(k[2])):
			var ks: GDScript = load(str(k[2]))
			if ks != null and ks.has_method("warm"):
				ks.call("warm", holder, at, right)
			if ks != null and ks.has_method("warm_nodes"):
				# 另一种写法：技能脚本交出一组节点（它自己的材质各一个），这里摆到镜头前
				var ns: Variant = ks.call("warm_nodes")
				if ns is Array:
					var wi := 0
					for n: Variant in ns:
						if n is Node3D:
							if (n as Node3D).get_parent() == null:
								holder.add_child(n)
							(n as Node3D).global_position = at + right * (float(wi % 8) - 3.5) * 0.5 + Vector3.UP * (0.6 + 0.4 * float(wi / 8))
							(n as Node3D).scale = Vector3.ONE * 0.25
							wi += 1
