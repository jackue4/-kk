extends Node3D
## 木兰草原的村子（参考 Europa 的吉卜力式小村）：布局来自 MeadowGen（村中空地、两排房子门朝空地、出村土路、风车位置）。
## · 房子：石砌勒脚；一层木板墙带前廊栏杆（或灰泥墙），二层米色灰泥略挑出，木梁收边；
##   双坡筒瓦屋顶（红 / 绿交替）、屋脊筒瓦、檐沟、烟囱带两只陶土烟囱帽；深绿木框十字棂窗、木门；墙角爬藤。
## · 空地中间一口带小瓦顶的石井，旁边木桶；进村土路两侧、几户门前是木栅栏（跟着地面起伏）。
## · 村口外一座木架风车（轮子一直转）；空地周围和出生点路边几棵伞形大树，房前屋后几丛灌木。
## 所有网格在 _ready 里一次建好（每栋房子一个多材质 ArrayMesh），房子 / 井 / 大树有碰撞。
## 择境门的预览世界也用它（with_collision = false）。
## 故意不写 class_name：用 preload 引用。

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const Kit := preload("res://scripts/ghibli_kit.gd")

var gen: MeadowGen
var with_collision := true
var _rotor: Node3D


## 按材质分面的网格拼装器：同一材质的零件写进同一个 SurfaceTool，最后合成一个多面 ArrayMesh
class Builder:
	var tools := {}
	var mats := {}

	func st(key: String, mat: Material) -> SurfaceTool:
		if not tools.has(key):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = s
			mats[key] = mat
		return tools[key]

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for k: String in tools:
			var s: SurfaceTool = tools[k]
			s.commit(m)
			m.surface_set_material(m.get_surface_count() - 1, mats[k])
		return m


func _plaster(b: Builder) -> SurfaceTool:
	return b.st("plaster", Kit.prop_mat(Kit.PLASTER, Kit.PAT_PLASTER))

func _plank(b: Builder) -> SurfaceTool:
	return b.st("plank", Kit.prop_mat(Kit.WOOD, Kit.PAT_PLANK))

func _wood(b: Builder) -> SurfaceTool:
	return b.st("wood", Kit.prop_mat(Kit.WOOD, Kit.PAT_GRAIN))

func _dark(b: Builder) -> SurfaceTool:
	return b.st("dark", Kit.prop_mat(Kit.WOOD_DARK, Kit.PAT_GRAIN))

func _stone(b: Builder) -> SurfaceTool:
	return b.st("stone", Kit.prop_mat(Kit.STONE, Kit.PAT_STONE))

func _frame(b: Builder) -> SurfaceTool:
	return b.st("frame", Kit.prop_mat(Kit.FRAME, Kit.PAT_GRAIN))

func _glass(b: Builder) -> SurfaceTool:
	return b.st("glass", Kit.prop_mat(Kit.GLASS, Kit.PAT_GLASS))

func _roof_st(b: Builder, green: bool) -> SurfaceTool:
	if green:
		return b.st("roof_g", Kit.prop_mat(Kit.ROOF_GREEN, Kit.PAT_TILE))
	return b.st("roof_r", Kit.prop_mat(Kit.ROOF_RED, Kit.PAT_TILE))

func _ivy(b: Builder) -> SurfaceTool:
	return b.st("ivy", Kit.foliage_mat(Kit.IVY_LEAF, 0.3))


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


func _ready() -> void:
	for h: Dictionary in gen.houses:
		_house(h)
	_well()
	_fences()
	_mill()
	_trees()


func _process(dt: float) -> void:
	if _rotor != null:
		_rotor.rotate_object_local(Vector3.BACK, dt * 1.2)


func _body(parent: Node3D, shape: Shape3D, xf: Transform3D) -> void:
	if not with_collision:
		return
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	parent.add_child(body)


# ---------- 房子 ----------

## 窗：深色木框 + 玻璃 + 十字窗棂 + 窗台；c 墙面上的中心，n 墙面朝外的法线（水平）
func _window(b: Builder, c: Vector3, n: Vector3, w := 0.95, h := 1.1) -> void:
	var r := Vector3.UP.cross(n).normalized()
	var bs := Basis(r, Vector3.UP, n)
	Kit.box(_frame(b), Vector3(w, h, 0.12), Transform3D(bs, c + n * 0.06))
	Kit.box(_glass(b), Vector3(w - 0.23, h - 0.24, 0.03), Transform3D(bs, c + n * 0.135))
	Kit.box(_frame(b), Vector3(0.07, h - 0.24, 0.04), Transform3D(bs, c + n * 0.16))
	Kit.box(_frame(b), Vector3(w - 0.23, 0.07, 0.04), Transform3D(bs, c + n * 0.16 + Vector3.UP * 0.06))
	Kit.box(_dark(b), Vector3(w + 0.16, 0.08, 0.26), Transform3D(bs, c + n * 0.13 - Vector3.UP * (h * 0.5 + 0.04)))


## 双坡屋顶，屋脊沿 x：墙顶高 y_w、墙体 wu × du（x × z）；返回屋脊高度
func _roof(b: Builder, tiles: SurfaceTool, gable: SurfaceTool, wu: float, du: float, y_w: float, over := 0.65) -> float:
	var s := du * 0.5 + over
	var slope := 0.68
	var rise := s * slope
	var y_r := y_w + du * 0.5 * slope
	var l := wu + 1.0
	var th := 0.16
	var slen := Vector2(s, rise).length()
	var dark := _dark(b)
	for side: float in [-1.0, 1.0]:
		var n := Vector3(0.0, s, rise * side).normalized()
		var down := Vector3(0.0, -rise, s * side).normalized()
		var r0 := Vector3(-l * 0.5, y_r, 0.0)
		var r1 := Vector3(l * 0.5, y_r, 0.0)
		var e1 := Vector3(l * 0.5, y_r - rise, s * side)
		var e0 := Vector3(-l * 0.5, y_r - rise, s * side)
		var o := n * th
		Kit.quad(tiles, r0 + o, r1 + o, e1 + o, e0 + o, n, Vector2(0, 0), Vector2(l, 0), Vector2(l, slen), Vector2(0, slen))
		Kit.quad(dark, r0, r1, e1, e0, -n)
		Kit.quad(dark, e0, e1, e1 + o, e0 + o, down)
		Kit.quad(dark, r0, e0, e0 + o, r0 + o, Vector3.LEFT)
		Kit.quad(dark, r1, e1, e1 + o, r1 + o, Vector3.RIGHT)
		# 檐沟
		Kit.cyl(_metal(b), 0.07, 0.07, l, 6, Transform3D(Basis(Vector3.BACK, -PI * 0.5), e0 + down * 0.05 + Vector3(0, -0.08, 0)))
	# 山墙
	for sx: float in [-1.0, 1.0]:
		var x := wu * 0.5 * sx
		Kit.tri(gable, Vector3(x, y_w, -du * 0.5), Vector3(x, y_w, du * 0.5), Vector3(x, y_r, 0.0),
				Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0))
	# 屋脊筒瓦
	Kit.cyl(tiles, 0.18, 0.18, l + 0.1, 8, Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-l * 0.5 - 0.05, y_r + th * 0.7, 0.0)))
	return y_r


func _metal(b: Builder) -> SurfaceTool:
	return b.st("metal", Kit.prop_mat(Kit.METAL, Kit.PAT_PLAIN))


func _house(h: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(h["seed"])
	var w: float = h["w"]
	var d: float = h["d"]
	var floors: int = h["floors"]
	var timber: bool = h["timber"]
	var green: bool = int(h["roof"]) == 1
	var b := Builder.new()
	var plinth := 0.45
	var gh := 2.7
	var uh := 2.4
	Kit.box(_stone(b), Vector3(w + 0.3, plinth + 0.3, d + 0.3), _at(0, (plinth - 0.3) * 0.5, 0))
	var y := plinth
	var door_x := rng.randf_range(-0.15, 0.25) * w
	if timber:
		Kit.box(_plank(b), Vector3(w, gh, d), _at(0, y + gh * 0.5, 0))
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				Kit.box(_dark(b), Vector3(0.32, gh, 0.32), _at(cx * w * 0.5, y + gh * 0.5, cz * d * 0.5))
		# 前廊：木地台 + 栏杆（门口留缺口）
		var fz := d * 0.5 + 1.7
		Kit.box(_wood(b), Vector3(w + 0.4, 0.18, 1.8), _at(0, y - 0.05, d * 0.5 + 0.9))
		var x := -w * 0.5
		while x <= w * 0.5 + 0.01:
			if absf(x - door_x) > 0.75:
				Kit.box(_wood(b), Vector3(0.09, 0.85, 0.09), _at(x, y + 0.47, fz))
			x += 0.32
		Kit.box(_dark(b), Vector3(door_x - 0.75 + w * 0.5 + 0.2, 0.1, 0.13), _at((-w * 0.5 - 0.2 + door_x - 0.75) * 0.5, y + 0.92, fz))
		Kit.box(_dark(b), Vector3(w * 0.5 + 0.2 - door_x - 0.75, 0.1, 0.13), _at((w * 0.5 + 0.2 + door_x + 0.75) * 0.5, y + 0.92, fz))
		for px: float in [-w * 0.5 - 0.1, w * 0.5 + 0.1]:
			Kit.box(_dark(b), Vector3(0.18, 1.1, 0.18), _at(px, y + 0.5, fz))
		_window(b, Vector3(door_x + (2.2 if door_x < 0.0 else -2.2), y + 1.55, d * 0.5), Vector3.BACK)
	else:
		Kit.box(_plaster(b), Vector3(w, gh, d), _at(0, y + gh * 0.5, 0))
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				Kit.box(_dark(b), Vector3(0.26, gh, 0.26), _at(cx * w * 0.5, y + gh * 0.5, cz * d * 0.5))
		_window(b, Vector3(door_x + (2.0 if door_x < 0.0 else -2.0), y + 1.5, d * 0.5), Vector3.BACK)
		Kit.box(_stone(b), Vector3(1.6, 0.22, 0.8), _at(door_x, 0.11, d * 0.5 + 0.4))
	for wx: float in [-0.25, 0.25]:
		_window(b, Vector3(wx * w, y + 1.5, -d * 0.5), Vector3.FORWARD)
	_window(b, Vector3(w * 0.5, y + 1.5, 0.0), Vector3.RIGHT, 0.85, 1.0)
	# 门
	Kit.box(_dark(b), Vector3(1.35, 2.25, 0.14), _at(door_x, y + 1.1, d * 0.5 + 0.04))
	Kit.box(_wood(b), Vector3(1.05, 2.0, 0.08), _at(door_x, y + 1.0, d * 0.5 + 0.12))
	var top := y + gh
	Kit.box(_dark(b), Vector3(w + 0.25, 0.26, d + 0.25), _at(0, top + 0.13, 0))
	top += 0.26
	var wu := w
	var du := d
	if floors == 2:
		wu = w + 0.5
		du = d + 0.5
		Kit.box(_plaster(b), Vector3(wu, uh, du), _at(0, top + uh * 0.5, 0))
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				Kit.box(_dark(b), Vector3(0.24, uh, 0.24), _at(cx * wu * 0.5, top + uh * 0.5, cz * du * 0.5))
		for wx: float in [-0.25, 0.25]:
			_window(b, Vector3(wx * wu, top + uh * 0.55, du * 0.5), Vector3.BACK)
			_window(b, Vector3(wx * wu, top + uh * 0.55, -du * 0.5), Vector3.FORWARD)
		_window(b, Vector3(-wu * 0.5, top + uh * 0.55, 0.0), Vector3.LEFT, 0.85, 1.0)
		top += uh
		Kit.box(_dark(b), Vector3(wu + 0.12, 0.16, du + 0.12), _at(0, top - 0.08, 0))
	var y_r := _roof(b, _roof_st(b, green), _plaster(b), wu, du, top)
	# 烟囱：后坡上，冒出屋脊，顶上两只陶土烟囱帽
	var chx := wu * rng.randf_range(0.18, 0.32) * (1.0 if rng.randf() < 0.5 else -1.0)
	var chz := -du * 0.22
	var ch_top := y_r + 1.0
	Kit.box(_plaster(b), Vector3(0.8, ch_top - top, 0.8), _at(chx, (top + ch_top) * 0.5, chz))
	Kit.box(_stone(b), Vector3(1.0, 0.18, 1.0), _at(chx, ch_top + 0.09, chz))
	for px: float in [-0.18, 0.18]:
		Kit.cyl(b.st("pot", Kit.prop_mat(Kit.TERRACOTTA, Kit.PAT_PLAIN)), 0.14, 0.12, 0.42, 8, _at(chx + px, ch_top + 0.18, chz))
	# 爬藤
	if h["ivy"]:
		var ivy := _ivy(b)
		var wall_h := top - 0.2
		Kit.ivy(ivy, Vector3(w * 0.5 + 0.02, 0.2, d * 0.5 - 0.05), wall_h * rng.randf_range(0.6, 1.0), Vector3.BACK, rng)
		Kit.ivy(ivy, Vector3(-w * 0.5 + 0.1, 0.2, d * 0.5 - 0.05), wall_h * rng.randf_range(0.4, 0.9), Vector3.BACK, rng)
		if rng.randf() < 0.6:
			Kit.ivy(ivy, Vector3(w * 0.5 + 0.02, 0.2, -d * 0.3), wall_h * rng.randf_range(0.5, 1.0), Vector3.RIGHT, rng)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.transform = Transform3D(Basis(Vector3.UP, float(h["yaw"])), Vector3(float(h["x"]), gen.village.y, float(h["z"])))
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, top, d)
	_body(mi, shape, _at(0, top * 0.5, 0))
	# 房前屋后的灌木
	var mm_xf: Array[Transform3D] = []
	for i in rng.randi_range(1, 3):
		var lp := Vector3((w * 0.5 + rng.randf_range(0.8, 1.6)) * (1.0 if i % 2 == 0 else -1.0), 0.0, rng.randf_range(-d * 0.5, d * 0.3))
		mm_xf.append(mi.transform * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 0.9)), lp))
	for xf in mm_xf:
		var bush := MeshInstance3D.new()
		bush.mesh = Kit.bush_mesh(rng.randi() % Kit.BUSH_VARIANTS)
		bush.transform = xf
		add_child(bush)


# ---------- 井 / 木桶 ----------

func _barrel(b: Builder, p: Vector3) -> void:
	var wood := _wood(b)
	Kit.cyl(wood, 0.36, 0.43, 0.45, 12, _at(p.x, p.y, p.z), false)
	Kit.cyl(wood, 0.43, 0.36, 0.45, 12, _at(p.x, p.y + 0.45, p.z), true)
	for hy: float in [0.16, 0.74]:
		Kit.cyl(_dark(b), 0.44, 0.44, 0.07, 12, _at(p.x, p.y + hy, p.z), false)


func _well() -> void:
	var c := Vector3(gen.village.x, gen.village.y, gen.village.z)
	var b := Builder.new()
	Kit.cyl(_stone(b), 1.15, 1.1, 0.85, 16, _at(0, 0, 0), false)
	Kit.cyl(_stone(b), 1.28, 1.28, 0.16, 16, _at(0, 0.85, 0))
	Kit.cyl(_glass(b), 0.92, 0.92, 0.02, 16, _at(0, 0.72, 0))
	for sx: float in [-1.0, 1.0]:
		Kit.box(_wood(b), Vector3(0.18, 2.3, 0.18), _at(sx * 1.05, 1.15, 0))
	Kit.cyl(_dark(b), 0.08, 0.08, 2.3, 6, Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-1.15, 1.9, 0)))
	Kit.box(_dark(b), Vector3(0.03, 0.7, 0.03), _at(0.1, 1.55, 0))
	Kit.cyl(_wood(b), 0.18, 0.22, 0.3, 8, _at(0.1, 1.05, 0))
	_roof(b, _roof_st(b, true), _wood(b), 2.1, 1.2, 2.3, 0.45)
	_barrel(b, Vector3(1.9, 0.0, 1.0))
	_barrel(b, Vector3(2.5, 0.0, 0.2))
	Kit.box(_wood(b), Vector3(0.7, 0.6, 0.7), Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 0.3, 1.1)))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.transform = Transform3D(Basis(Vector3.UP, atan2(gen.village_dir.x, gen.village_dir.z)), c)
	add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 1.0
	_body(mi, shape, _at(0, 0.5, 0))


# ---------- 栅栏 ----------

func _fence_line(st: SurfaceTool, pts: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for i in pts.size():
		var p := pts[i]
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.06))
		Kit.box(st, Vector3(0.17, 1.2, 0.17), Transform3D(tilt, p + Vector3(0, 0.45, 0)))
		if i == 0:
			continue
		var a := pts[i - 1]
		for hy: float in [0.42, 0.85]:
			Kit.beam(st, a + Vector3(0, hy, 0), p + Vector3(0, hy, 0) + Vector3(0, rng.randf_range(-0.04, 0.04), 0), 0.11, 0.08)


func _fences() -> void:
	var b := Builder.new()
	var st := _wood(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# 进村土路两边
	for side: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		var s := gen.plaza_s - 58.0
		while s < gen.plaza_s - (MeadowGen.PLAZA_R + 7.0):
			var q := gen.path_at(s)
			var nrm := Vector2(-q.w, q.z)
			var p2 := Vector2(q.x, q.y) + nrm * side * (MeadowGen.PATH_HW + 1.7)
			pts.append(Vector3(p2.x, gen.height(p2.x, p2.y), p2.y))
			s += 2.5
			if pts.size() == 9:   # 中间留一道口子
				_fence_line(st, pts, rng)
				pts.clear()
				s += 3.0
		_fence_line(st, pts, rng)
	# 几户门前的小院栅栏（门口留缺口）
	for h: Dictionary in gen.houses:
		if int(h["seed"]) % 3 == 0:
			continue
		var w: float = h["w"]
		var d: float = h["d"]
		var fz := d * 0.5 + (4.4 if h["timber"] else 3.0)
		var xf := Transform3D(Basis(Vector3.UP, float(h["yaw"])), Vector3(float(h["x"]), 0.0, float(h["z"])))
		for half: float in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			var x := 1.1
			while x <= w * 0.5 + 1.2:
				var p := xf * Vector3(x * half, 0.0, fz)
				pts.append(Vector3(p.x, gen.height(p.x, p.z), p.z))
				x += 2.3
			var corner := xf * Vector3((w * 0.5 + 1.2) * half, 0.0, d * 0.5 + 0.6)
			pts.append(Vector3(corner.x, gen.height(corner.x, corner.z), corner.z))
			_fence_line(st, pts, rng)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)


# ---------- 风车 ----------

func _mill() -> void:
	var b := Builder.new()
	var dk := _dark(b)
	var hgt := 9.0
	var legs: Array[Vector3] = []
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		legs.append(Vector3(c.x, 0.0, c.y))
	var at := func(corner: Vector3, y: float) -> Vector3:
		var hw := lerpf(1.7, 0.4, (y + 0.3) / (hgt + 0.3))
		return Vector3(corner.x * hw, y, corner.z * hw)
	for c in legs:
		Kit.beam(dk, at.call(c, -0.3), at.call(c, hgt), 0.18)
	var levels: Array[float] = [0.4, 2.8, 5.2, 7.4]
	for li in levels.size():
		for k in 4:
			var c0 := legs[k]
			var c1 := legs[(k + 1) % 4]
			Kit.beam(dk, at.call(c0, levels[li]), at.call(c1, levels[li]), 0.1)
			if li < levels.size() - 1:
				Kit.beam(dk, at.call(c0, levels[li]), at.call(c1, levels[li + 1]), 0.07)
	Kit.box(_wood(b), Vector3(1.3, 0.12, 1.3), _at(0, hgt, 0))
	Kit.box(dk, Vector3(0.5, 0.5, 1.0), _at(0, hgt + 0.4, 0.1))
	Kit.beam(dk, Vector3(0, hgt + 0.4, 0), Vector3(0, hgt + 0.45, -2.6), 0.1)
	Kit.box(b.st("canvas", Kit.prop_mat(Kit.CANVAS, Kit.PAT_PLAIN)), Vector3(0.06, 1.0, 1.4), _at(0, hgt + 0.55, -2.9))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.transform = Transform3D(Basis(Vector3.UP, gen.mill.w), Vector3(gen.mill.x, gen.mill.y, gen.mill.z))
	add_child(mi)
	# 风轮：一圈帆布叶片 + 外圈，绕前后轴转
	var rb := Builder.new()
	var canvas := rb.st("canvas", Kit.prop_mat(Kit.CANVAS, Kit.PAT_PLAIN))
	var rdk := rb.st("dark", Kit.prop_mat(Kit.WOOD_DARK, Kit.PAT_GRAIN))
	Kit.cyl(rdk, 0.22, 0.22, 0.35, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.15)))
	var blades := 12
	for i in blades:
		var a := TAU * i / blades
		var dir := Vector3(cos(a), sin(a), 0.0)
		var bs := Basis(Vector3.BACK, a - PI * 0.5) * Basis(Vector3.UP, 0.35)
		Kit.box(canvas, Vector3(0.36, 1.55, 0.04), Transform3D(bs, dir * 1.25))
		Kit.beam(rdk, dir * 0.2, dir * 2.1, 0.05)
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		Kit.beam(rdk, Vector3(cos(a0), sin(a0), 0) * 2.05, Vector3(cos(a1), sin(a1), 0) * 2.05, 0.06)
	_rotor = MeshInstance3D.new()
	(_rotor as MeshInstance3D).mesh = rb.commit()
	_rotor.position = Vector3(0, hgt + 0.45, 0.75)
	mi.add_child(_rotor)


# ---------- 大树 ----------

func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in gen.big_trees.size():
		var t := gen.big_trees[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.tree_mesh(i % Kit.TREE_VARIANTS)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * t.w), Vector3(t.x, t.y - 0.15, t.z))
		add_child(mi)
		var shape := CylinderShape3D.new()
		shape.radius = 0.45
		shape.height = 5.0
		_body(mi, shape, _at(0, 2.4, 0))
