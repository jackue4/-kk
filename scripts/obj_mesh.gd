extends RefCounted
## 读 res:// 里的 .obj 小模型（草叶、花、长草丛、蝴蝶）。编辑器导入过就直接用导入的 Mesh；
## 没导入过（命令行直接跑、还没开过编辑器）就现场解析文本 OBJ，约定和 Godot 的 OBJ 导入器一致：
## UV 的 v 取 1 - v、面按扇形三角化并反转绕序（Godot 正面是顺时针）。
## 故意不写 class_name：用 preload 引用。

static var _cache := {}


static func get_mesh(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var m: Mesh = null
	if ResourceLoader.exists(path, "Mesh"):
		m = load(path) as Mesh
	if m == null:
		m = _parse(path)
	_cache[path] = m
	return m


static func _parse(path: String) -> ArrayMesh:
	var text := FileAccess.get_file_as_string(path)
	var vs := PackedVector3Array()
	var vts := PackedVector2Array()
	var vns := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_n := false
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("v "):
			var p := line.split(" ", false)
			vs.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
		elif line.begins_with("vt "):
			var p := line.split(" ", false)
			vts.append(Vector2(p[1].to_float(), 1.0 - p[2].to_float()))
		elif line.begins_with("vn "):
			var p := line.split(" ", false)
			vns.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
		elif line.begins_with("f "):
			var p := line.split(" ", false)
			var corners: Array[PackedInt32Array] = []
			for k in range(1, p.size()):
				var ids := p[k].split("/")
				var c := PackedInt32Array([-1, -1, -1])
				for j in mini(ids.size(), 3):
					if ids[j] != "":
						var i := ids[j].to_int()
						var cnt := [vs.size(), vts.size(), vns.size()][j] as int
						c[j] = i - 1 if i > 0 else cnt + i
				corners.append(c)
			for k in range(1, corners.size() - 1):
				for c: PackedInt32Array in [corners[0], corners[k + 1], corners[k]]:
					if c[1] >= 0:
						st.set_uv(vts[c[1]])
					if c[2] >= 0:
						st.set_normal(vns[c[2]])
						has_n = true
					st.add_vertex(vs[c[0]])
	if not has_n:
		st.generate_normals()
	return st.commit()
