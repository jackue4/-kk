extends Node3D
## 大厅传送门门心里的木兰草原（LevelPortal 的预览世界，挂在门的 SubViewport 里）：
## 同一套天空 / 光照 / 地形着色器 / 草 / 树 / 村子，地形只算回门正前方 5×5 块（8 米一格，带树和灌木）+ 一张粗远景，
## 草只铺门口正前方几块；地形和草在工作线程里算，算好再挂上，不卡大厅开场。门正对着土路和远处的村子。
## 故意不写 class_name：用 preload 引用。

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const MeadowLevel := preload("res://scripts/meadow_level.gd")
const MeadowTerrain := preload("res://scripts/meadow_terrain.gd")
const MeadowGrass := preload("res://scripts/meadow_grass.gd")
const MeadowVillage := preload("res://scripts/meadow_village.gd")
const LevelPortal := preload("res://scripts/level_portal.gd")
const JobPool := preload("res://scripts/job_pool.gd")

const AHEAD := 30.0

var gen := MeadowGen.new()
var vista := Vector3.FORWARD
var pool := JobPool.new()
var _jobs := {}      # job -> ["chunk", key] / ["horizon"] / ["grass"]
var _keys: Array[Vector2i] = []
var _mat: ShaderMaterial
var _gmat: ShaderMaterial


## 预览世界里"那一头的门"：就是草原里那扇回大厅的门
static func eye() -> Transform3D:
	var g := MeadowGen.new()
	var xf := MeadowLevel.exit_xf(g, MeadowLevel.vista_dir(g))
	xf.origin.y += LevelPortal.LIFT
	return xf


func _ready() -> void:
	vista = MeadowLevel.vista_dir(gen)
	var we := WorldEnvironment.new()
	we.environment = MeadowLevel.make_environment()
	add_child(we)
	add_child(MeadowLevel.make_sun(vista))
	_mat = MeadowTerrain.make_material(false, gen)
	_gmat = MeadowGrass.make_grass_material()
	var village := MeadowVillage.new()
	village.gen = gen
	village.with_collision = false
	add_child(village)
	var e := MeadowLevel.exit_xf(gen, vista).origin
	_mat.set_shader_parameter("grass_ring_center", e + vista * AHEAD)
	var g := gen
	var k0 := MeadowGen.key_of(e.x + vista.x * 200.0, e.z + vista.z * 200.0)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var key := k0 + Vector2i(dx, dz)
			_keys.append(key)
			_jobs[pool.submit(func() -> Dictionary: return g.build_chunk(key, 1))] = ["chunk", key]
	_jobs[pool.submit(func() -> Dictionary: return g.build_horizon(96))] = ["horizon"]
	var c := e + vista * AHEAD
	_gmat.set_shader_parameter("character_position", c)
	_gmat.set_shader_parameter("fade_far", 58.0)
	var pats := MeadowGrass.patterns()
	_jobs[pool.submit(func() -> Array: return _grass_job(g, c, pats))] = ["grass"]


func _exit_tree() -> void:
	pool.drain()


## 门口正前方的草：先在 128 米见方里按 4 米采一张高度网格，再把离 c 50 米内的整块草地建出来
static func _grass_job(g: MeadowGen, c: Vector3, pats: Array[PackedFloat32Array]) -> Array:
	var sp := 4.0
	var n := 33
	var x0 := floorf((c.x - 64.0) / sp) * sp
	var z0 := floorf((c.z - 64.0) / sp) * sp
	var grid := g.sample_rect(x0, z0, n, sp)
	var out: Array = []
	var t0 := Vector2i(ceili(x0 / MeadowGen.TILE), ceili(z0 / MeadowGen.TILE))
	var t1 := Vector2i(floori((x0 + 128.0) / MeadowGen.TILE) - 1, floori((z0 + 128.0) / MeadowGen.TILE) - 1)
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			var t := Vector2i(tx, tz)
			var tc := Vector2((tx + 0.5) * MeadowGen.TILE, (tz + 0.5) * MeadowGen.TILE)
			if tc.distance_to(Vector2(c.x, c.z)) > 50.0:
				continue
			out.append([t, g.build_tile(t, grid, n, sp, x0, z0, pats[absi(hash(t)) % pats.size()])])
	return out


func _process(_dt: float) -> void:
	for r: Array in pool.collect():
		var meta: Array = _jobs.get(r[0], [])
		_jobs.erase(r[0])
		if meta.is_empty():
			continue
		match String(meta[0]):
			"chunk":
				_add_chunk(meta[1], r[1])
			"horizon":
				_add_horizon(r[1])
			"grass":
				_add_grass(r[1])


func _add_chunk(key: Vector2i, d: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["verts"]
	arrays[Mesh.ARRAY_NORMAL] = d["norms"]
	arrays[Mesh.ARRAY_INDEX] = MeadowGen.make_indices(MeadowGen.CELLS[1])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat
	mi.position = Vector3(key.x * MeadowGen.CHUNK, 0.0, key.y * MeadowGen.CHUNK)
	add_child(mi)
	MeadowTerrain.add_flora(self, d, mi.position, 1)


func _add_horizon(d: Dictionary) -> void:
	var img := Image.create(MeadowGen.GRID, MeadowGen.GRID, false, Image.FORMAT_R8)
	for k: Vector2i in _keys:
		img.set_pixel(k.x + (MeadowGen.GRID >> 1), k.y + (MeadowGen.GRID >> 1), Color(1.0, 0.0, 0.0))
	var hm := MeadowTerrain.make_material(true, gen)
	hm.set_shader_parameter("cover_mask", ImageTexture.create_from_image(img))
	hm.set_shader_parameter("mask_origin", Vector2(-MeadowGen.WORLD_HALF, -MeadowGen.WORLD_HALF))
	hm.set_shader_parameter("mask_span", MeadowGen.WORLD_HALF * 2.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["verts"]
	arrays[Mesh.ARRAY_NORMAL] = d["norms"]
	arrays[Mesh.ARRAY_INDEX] = d["idx"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = hm
	add_child(mi)


func _add_grass(tiles: Array) -> void:
	var fly_at := Vector3.INF
	for e: Array in tiles:
		var res: Dictionary = e[1]
		add_child(MeadowGrass.make_tile_node(e[0], res, _gmat))
		var pc: PackedVector3Array = res["patches"]
		if fly_at == Vector3.INF and not pc.is_empty():
			fly_at = pc[0]
	if fly_at != Vector3.INF:
		var gp := MeadowGrass.make_butterflies(8)
		add_child(gp)
		gp.position = fly_at + Vector3.UP * 1.3
