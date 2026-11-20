extends RefCounted
## 体素模型构建器：往整数格子里填色块，build() 时只为外露面生成四边形。
## 倒角与方块缝由 voxel.gdshader 逐像素计算。
## 故意不写 class_name：用 preload 引用，命令行直接运行时不依赖编辑器重建全局类缓存。

const SHADER := preload("res://shaders/voxel.gdshader")
const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const QUAD: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]

static var _mat: ShaderMaterial

var cells: Dictionary = {}  # Vector3i -> Color


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


func put(x: int, y: int, z: int, col: Color) -> void:
	cells[Vector3i(x, y, z)] = col


## 填充一个长方体（坐标含两端）
func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, col: Color) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				cells[Vector3i(x, y, z)] = col


## 左右对称填充（镜像面在 x=0，格子 x 对应 -1-x）
func sym(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, col: Color) -> void:
	box(x0, y0, z0, x1, y1, z1, col)
	box(-1 - x1, y0, z0, -1 - x0, y1, z1, col)


## 只给已有的方块改色
func paint(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, col: Color) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				var k := Vector3i(x, y, z)
				if cells.has(k):
					cells[k] = col


func sym_paint(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, col: Color) -> void:
	paint(x0, y0, z0, x1, y1, z1, col)
	paint(-1 - x1, y0, z0, -1 - x0, y1, z1, col)


func cut(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				cells.erase(Vector3i(x, y, z))


func sym_cut(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	cut(x0, y0, z0, x1, y1, z1)
	cut(-1 - x1, y0, z0, -1 - x0, y1, z1)


## 左右镜像后的副本（用于另一侧的手臂/腿）
func flipped() -> RefCounted:
	var m: RefCounted = (get_script() as GDScript).new()
	var out: Dictionary = {}
	for k: Vector3i in cells:
		out[Vector3i(-1 - k.x, k.y, k.z)] = cells[k]
	m.set("cells", out)
	return m


## unit: 每格边长(米)；pivot: 网格原点所在的体素坐标（连续值，格子 i 占据 [i, i+1]）
func build(unit: float, pivot: Vector3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for key: Vector3i in cells:
		var col: Color = (cells[key] as Color).srgb_to_linear()
		var c := Vector3(key) + Vector3(0.5, 0.5, 0.5) - pivot
		for d: Vector3i in DIRS:
			if cells.has(key + d):
				continue
			var n := Vector3(d)
			var t := Vector3(n.z, n.x, n.y)
			var b := n.cross(t)
			var base := verts.size()
			for q: Vector2 in QUAD:
				var s := (n + t * q.x + b * q.y) * 0.5
				verts.append((c + s) * unit)
				norms.append(n)
				cols.append(col)
				uvs.append(Vector2(s.x, s.y))
				uv2s.append(Vector2(s.z, 0.0))
			# Godot 正面为顺时针：按实际叉积决定索引顺序，不依赖手算的手性
			var e1 := verts[base + 1] - verts[base]
			var e2 := verts[base + 2] - verts[base]
			if e1.cross(e2).dot(n) > 0.0:
				idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
			else:
				idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
