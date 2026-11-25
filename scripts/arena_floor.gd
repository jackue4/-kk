extends Node3D
## 擂台台面的真破坏（2026-11-25，scripts/destruct.gd 调）：主城的地面是一整张静态网格，挖不了坑 ——
## 这里的做法是「把那一格的顶面收掉、底下露出一个现拼的坑」：
##   · 台面每一格（2 米见方）的顶面在地面网格里是一个四边形：打碎 = 把这四个顶点就地收成一个点
##     （RenderingServer.mesh_surface_update_vertex_region，只传 48 个字节，网格不重建）；压在这一格上的金纹方块同样收掉
##   · 坑：一张小网格（_liner），只有碎掉的格子的坑底 + 挨着没碎的格子的那几面坑壁，碎的格子变了就重拼（几十个四边形）
##   · 落脚：hub_hall.gd 的高度表 _h 里把这一格压低 DEPTH 米（主角 / 陪练 / 镜头都问 hub.ground()）
##   · REPAIR_T 秒后自己复原（顶点写回去、高度表写回去）：擂台不会越打越烂，下一场还是平的
## 台沿一圈（石栏、石阶口，R_BREAK 以外）不碎。开机时核对一次网格的顶点布局（位置一段连排、每个 12 字节）：
## 对不上就整个不启用（Destruct 退回「只叠表现」）；网页版不回读网格（慢），直接按桌面验过的布局用。
## 由 hub_arena.gd 的 build() 建、挂在主城的 _root 下面（主城藏起来它也跟着藏）。
## 故意不写 class_name，也不 preload hub_hall.gd / hub_arena.gd（它们 preload 这个文件）：hub 不标类型。

const Destruct := preload("res://scripts/destruct.gd")
const SHADER := preload("res://shaders/block_world.gdshader")
const DEPTH := 1.0             # 坑深：不超过主城「直接迈上去」的高度（hub_hall.gd 的 STEP_UP = 1.1），走着的人掉进去能自己走出来
const REPAIR_T := 30.0
const MAX_CELLS := 30          # 一次爆破最多碎几格
const CELL := 2.0

var hub
var h_top := 3.0
var top_col_fn := Callable()   # func(i, j, x, z) -> 这一格台面的颜色（碎块用）
var cells := {}                # Vector2i(i, j) → 顶面四边形在地面网格里的第一个顶点
var inlay := {}                # Vector2i(i, j) → PackedInt32Array：中心落在这一格的金纹方块各自的第一个顶点（点缀网格里）
var broken := {}               # 格子 → 碎掉的时刻（毫秒）
var state := 0                 # 0 还没核对 1 能用 -1 对不上（不启用）
var stat := {"broken": 0, "repaired": 0, "blasts": 0}
var repair_t := REPAIR_T

var _g_rid := RID()
var _a_rid := RID()
var _liner: MeshInstance3D
var _dirty := false
var _acc := 0.0


static func _oct(lx: float, lz: float) -> float:
	return maxf(maxf(absf(lx), absf(lz)), (absf(lx) + absf(lz)) * 0.70710678)


## hub_arena.build() 末尾调：记下两座擂台台面每一格的顶面在哪、金纹方块在哪。
## r_break = 离台心（八角距离）这么远以内的格子能碎；inlay_ranges = [[起, 止], ...]（点缀网格里金纹那几段顶点，每 20 个一个方块）
func setup(hub_node, top: float, cx: float, cz: float, r_break: float, inlay_ranges: Array, col_fn: Callable) -> void:
	hub = hub_node
	h_top = top
	top_col_fn = col_fn
	var v: PackedVector3Array = hub._g[0]
	var q := 0
	var n := v.size()
	while q + 3 < n:
		var p := v[q]
		if absf(p.y - top) < 0.001:
			var p2 := v[q + 2]
			if absf(p2.y - top) < 0.001 and absf(p2.x - p.x - CELL) < 0.001 and absf(p2.z - p.z - CELL) < 0.001 \
					and _oct(absf(p.x + 1.0) - cx, p.z + 1.0 - cz) <= r_break:
				cells[Vector2i(int(hub._ci(p.x + 1.0)), int(hub._ci(p.z + 1.0)))] = q
		q += 4
	var av: PackedVector3Array = hub._a[0]
	for rg: Array in inlay_ranges:
		var b := int(rg[0])
		while b + 20 <= int(rg[1]):
			var c := Vector3.ZERO
			for k in 20:
				c += av[b + k]
			c /= 20.0
			var key := Vector2i(int(hub._ci(c.x)), int(hub._ci(c.z)))
			if cells.has(key):
				var arr: PackedInt32Array = inlay.get(key, PackedInt32Array())
				arr.append(b)
				inlay[key] = arr
			b += 20


func _ready() -> void:
	name = "ArenaFloor"
	_liner = MeshInstance3D.new()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_liner.material_override = m
	_liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_liner)
	Destruct.attach(self)
	_resolve.call_deferred()       # 主城建完之后核对一次网格（要回读一次地面网格，几毫秒；放在开机载入里，不留到头一回打碎的时候）


func _exit_tree() -> void:
	Destruct.detach(self)


## 联机节点：擂台对决自己那一个（arena_net.gd），真人对打时两边的台面一起碎
func dx_net() -> Node:
	if hub == null:
		return null
	var d: Variant = hub.get("duel")
	if d == null or not is_instance_valid(d):
		return null
	var nn: Variant = (d as Node).get("_net")
	return nn as Node if nn != null and is_instance_valid(nn) and bool((nn as Node).get("active")) else null


## 找到那两张网格、核对顶点布局。返回能不能用
func _resolve() -> bool:
	if state != 0:
		return state > 0
	state = -1
	if hub == null or cells.is_empty():
		return false
	var gv: PackedVector3Array = hub._g[0]
	var av: PackedVector3Array = hub._a[0]
	for ch: Node in (hub._root as Node).get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi == _liner or not (mi.mesh is ArrayMesh) or mi.mesh.get_surface_count() != 1:
			continue
		var cnt := (mi.mesh as ArrayMesh).surface_get_array_len(0)
		if cnt == gv.size() and not _g_rid.is_valid():
			_g_rid = mi.mesh.get_rid()
		elif cnt == av.size() and not _a_rid.is_valid():
			_a_rid = mi.mesh.get_rid()
	if not _g_rid.is_valid():
		return false
	if not OS.has_feature("web"):
		# 核对：随便挑一格，网格里那个位置上存的是不是它的坐标
		var v0: int = cells.values()[cells.size() / 2]
		var sd: Dictionary = RenderingServer.mesh_get_surface(_g_rid, 0)
		var vd: PackedByteArray = sd.get("vertex_data", PackedByteArray())
		if vd.size() < (v0 + 4) * 12:
			return false
		for k in 4:
			var o := (v0 + k) * 12
			if Vector3(vd.decode_float(o), vd.decode_float(o + 4), vd.decode_float(o + 8)).distance_to(gv[v0 + k]) > 0.002:
				return false
	state = 1
	return true


func _write(rid: RID, v0: int, pts: PackedVector3Array) -> void:
	var b := PackedByteArray()
	b.resize(pts.size() * 12)
	for k in pts.size():
		b.encode_float(k * 12, pts[k].x)
		b.encode_float(k * 12 + 4, pts[k].y)
		b.encode_float(k * 12 + 8, pts[k].z)
	RenderingServer.mesh_surface_update_vertex_region(rid, 0, v0 * 12, b)


func _cell_pos(k: Vector2i) -> Vector3:
	return Vector3((float(k.x - int(hub.HN)) + 0.5) * CELL, h_top, (float(k.y - int(hub.HN)) + 0.5) * CELL)


func _break(k: Vector2i) -> void:
	var c := _cell_pos(k) - Vector3(0.0, DEPTH + 0.05, 0.0)
	_write(_g_rid, int(cells[k]), PackedVector3Array([c, c, c, c]))
	if inlay.has(k) and _a_rid.is_valid():
		var flat := PackedVector3Array()
		flat.resize(20)
		flat.fill(c)
		for b: int in (inlay[k] as PackedInt32Array):
			_write(_a_rid, b, flat)
	hub._h[k.y * int(hub.N) + k.x] = h_top - DEPTH
	broken[k] = Time.get_ticks_msec()
	_dirty = true
	stat["broken"] = int(stat["broken"]) + 1


func _restore(k: Vector2i) -> void:
	var gv: PackedVector3Array = hub._g[0]
	var v0 := int(cells[k])
	_write(_g_rid, v0, gv.slice(v0, v0 + 4))
	if inlay.has(k) and _a_rid.is_valid():
		var av: PackedVector3Array = hub._a[0]
		for b: int in (inlay[k] as PackedInt32Array):
			_write(_a_rid, b, av.slice(b, b + 20))
	hub._h[k.y * int(hub.N) + k.x] = h_top
	broken.erase(k)
	_dirty = true
	stat["repaired"] = int(stat["repaired"]) + 1


## Destruct.blast 进来：pos 周围 radius 米。返回 {cells 碎了几格, y 台面高度, cols 碎块的颜色}；不在擂台上 / 够不着台面 = cells 0
func dx_tiles(pos: Vector3, radius: float) -> Dictionary:
	var out := {"cells": 0, "y": h_top, "cols": []}
	if hub == null or not is_visible_in_tree() or absf(pos.y - h_top) > radius * 0.75 + 0.8 or pos.y < h_top - DEPTH - 0.5:
		return out
	var ci := int(hub._ci(pos.x))
	var cj := int(hub._ci(pos.z))
	var rr := maxf(radius * 0.7, 1.2)
	var n := int(ceilf(rr / CELL))
	var hits: Array = []
	for dj in range(-n, n + 1):
		for di in range(-n, n + 1):
			var k := Vector2i(ci + di, cj + dj)
			if not cells.has(k) or broken.has(k):
				continue
			var c := _cell_pos(k)
			var d2 := (c.x - pos.x) * (c.x - pos.x) + (c.z - pos.z) * (c.z - pos.z)
			if d2 <= rr * rr:
				hits.append([d2, k])
	if hits.is_empty() or not _resolve():
		return out
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cols: Array = []
	for i in mini(hits.size(), MAX_CELLS):
		var k2: Vector2i = hits[i][1]
		_break(k2)
		if cols.size() < 6 and top_col_fn.is_valid():
			var cp := _cell_pos(k2)
			cols.append(top_col_fn.call(k2.x, k2.y, cp.x, cp.z))
	cols.append(Color(0.62, 0.58, 0.62))
	cols.append(Color(0.52, 0.50, 0.58))
	out["cells"] = mini(hits.size(), MAX_CELLS)
	out["cols"] = cols
	stat["blasts"] = int(stat["blasts"]) + 1
	return out


## 全部复原（自检 / 以后对决收场时可以调）
func repair_all() -> void:
	for k: Vector2i in broken.keys():
		_restore(k)


func _quad(a: Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, c: Color, top: bool) -> void:
	var v: PackedVector3Array = a[0]
	var b := v.size()
	v.append_array(PackedVector3Array([p0, p1, p2, p3]))
	a[0] = v
	var nr: PackedVector3Array = a[1]
	var cl: PackedColorArray = a[2]
	for _k in 4:
		nr.append(nrm)
		cl.append(Color(c.r, c.g, c.b, 0.0))
	a[1] = nr
	a[2] = cl
	var ix: PackedInt32Array = a[3]
	if top:
		ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		ix.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	a[3] = ix


## 坑：碎掉的每一格一块坑底，挨着没碎的格子的那几面补坑壁（面朝坑里；绕向照 hub_hall.gd 的 _side）
func _rebuild_liner() -> void:
	_dirty = false
	if broken.is_empty():
		_liner.mesh = null
		return
	var a := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	var yb := h_top - DEPTH
	var lip := Color(0.70, 0.64, 0.70)
	var wall := Color(0.60, 0.56, 0.60)
	var floor_c := Color(0.47, 0.44, 0.50)
	for k: Vector2i in broken:
		var x0 := float(k.x - int(hub.HN)) * CELL
		var z0 := float(k.y - int(hub.HN)) * CELL
		var x1 := x0 + CELL
		var z1 := z0 + CELL
		var sh := 0.94 + 0.1 * float(hub._hash(k.x * 7 + 3, k.y * 11 + 5))
		_quad(a, Vector3(x0, yb, z0), Vector3(x1, yb, z0), Vector3(x1, yb, z1), Vector3(x0, yb, z1), Vector3.UP, floor_c * sh, true)
		# 每面坑壁两段：上沿一道镶边石，往下是砌石
		for e: Array in [[Vector2i(-1, 0), Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.RIGHT], [Vector2i(1, 0), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3.LEFT],
				[Vector2i(0, -1), Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.BACK], [Vector2i(0, 1), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD]]:
			if broken.has(k + (e[0] as Vector2i)):
				continue
			var p0: Vector3 = e[1]
			var p1: Vector3 = e[2]
			var ym := h_top - 0.3
			_quad(a, Vector3(p0.x, h_top, p0.z), Vector3(p1.x, h_top, p1.z), Vector3(p1.x, ym, p1.z), Vector3(p0.x, ym, p0.z), e[3], lip, false)
			_quad(a, Vector3(p0.x, ym, p0.z), Vector3(p1.x, ym, p1.z), Vector3(p1.x, yb, p1.z), Vector3(p0.x, yb, p0.z), e[3], wall * sh, false)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_liner.mesh = mesh


func _process(dt: float) -> void:
	if broken.is_empty() and not _dirty:
		return
	_acc += dt
	if _acc >= 0.5:
		_acc = 0.0
		var now := Time.get_ticks_msec()
		var lim := int(repair_t * 1000.0)
		var n := 0
		for k: Vector2i in broken.keys():
			if now - int(broken[k]) > lim:
				_restore(k)
				n += 1
				if n >= 12:
					break      # 一次别补太多：一片一片长回来
	if _dirty:
		_rebuild_liner()
