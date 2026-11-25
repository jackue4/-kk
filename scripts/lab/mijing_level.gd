extends Node3D
## 天南秘境（实验关卡，2026-11-24）：独立的小样，不进正式流程。入口只有命令行 `-- --mijing[=种子]`（main.gd 的探针 → mijing_boot.gd）。
## 关卡结构：一串「段」各抽一间房（mijing_rooms.gd 的 SEQ），门对门拼成主路；主路上多出来的门接支线 / 死胡同，没接上的封死。
## 每局现拼（换种子就是另一种排法）。世界 = 一张 2 米一格的高度表（墙就是高出地面十来米的格子），没有另外的实心盒子：
##   落脚 / 撞墙 / 缓坡 的规矩照 ex_level.gd（两格以内走缓坡，再高是墙；飞着也翻不过墙）；每间房有自己的飞行上限（禁空）。
## 和 main.gd 的约定（同 ex_level.gd）：player / cam / font / mobile / net 由外面塞；exit_requested、spawn_point()、spawn_yaw()、prewarm()、stats_text()、raid。
## 故意不写 class_name。

signal exit_requested

const Rooms := preload("res://scripts/lab/mijing_rooms.gd")
const BlockWorld := preload("res://scripts/block_world.gd")
const WORLD_SHADER := preload("res://shaders/block_world.gdshader")
const UiStyle := preload("res://scripts/ui_style.gd")
const MOB_PATH := "res://scripts/raid_mob.gd"
const EXMOBS_PATH := "res://scripts/ex/ex_mobs.gd"

var player: Player
var cam: CameraRig
var font: Font
var mobile := false
var net: Node = null
var raid: Node = null            # 没有玩法管理器（main.gd 会读这个属性）
var map_id := "mijing"
var seed_n := 0                  # 0 = 随机
static var boot_seed := 0        # 命令行给的种子（mijing_boot.gd 设）


static func set_boot(n: int) -> void:
	boot_seed = n

var env: Environment
var sun: DirectionalLight3D
var worst_frame_ms := 0.0
var wall_bumps := 0
var no_mobs := false             # 自检：不刷怪

const CELL := 2.0
const BASE_Y := 24.0
const MARGIN := 8
const CHUNK := 24
const STEP_UP := 2.25
const BODY_H := 2.1
const BODY_R := 0.42
const RAMP_MIN := 0.55
const RAMP_K := 0.4
const RAMP_MAX := 1.5
const MANTLE_SPD := 12.0
const OPP := {"N": "S", "S": "N", "E": "W", "W": "E"}
const NUMS := ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮", "⑯"]

# 这一局
var run_seed := 0
var rooms: Array = []            # 摆好的房间（字典，见 _attach）
var main_n := 0                  # 主路几间
var path_len := 0.0              # 主路全长（各房间中心连线，米）
var zones: Array = []            # 刷怪区 {pos, r, n, elite, done, room}
var chests: Array = []           # 灵匣的位置
var _extract := Vector3.INF      # 撤离阵
var _extract_t := 0.0

# 高度表
var _gx0 := 0
var _gz0 := 0
var _gw := 0
var _gl := 0
var _h := PackedFloat32Array()
var _t := PackedByteArray()
var _fb := PackedFloat32Array()   # 镜头用的「地面」：能走的格 = 它自己的高度，墙 / 柱 = 所在房间的基准面
var _cap := PackedFloat32Array()  # 飞行上限
var _room := PackedInt32Array()
var _rock_top := 0.0
var _base_min := 0.0

var _root: Node3D                # 这一局的全部东西（换一局时整个扔掉重建）
var _mat: ShaderMaterial
var _floor: StaticBody3D
var _last := Vector3(INF, 0, 0)
var _last_phys := Vector2(INF, 0)
var _bump_t := 0.0
var _safe := Vector3.INF         # 上一个踩实的落脚点（掉进云渊送回这里）
var _safe_t := 0.0
var _old_hook: Callable
var _zone_t := 0.0
var _mobs: Array = []
var _spawn := Vector3.ZERO
var _spawn_yaw := 0.0
var _busy := false

# 界面
var _ui: CanvasLayer
var _map_tex: ImageTexture
var _mini: TextureRect
var _dot: ColorRect
var _big: Control
var _big_tex: TextureRect
var _big_dot: ColorRect
var _big_tags: Array = []
var _info: Label
var _toast: Label
var _toast_t := 0.0

# 网格缓冲（一块一块攒）
var _mv := PackedVector3Array()
var _mn := PackedVector3Array()
var _mc := PackedColorArray()
var _mi := PackedInt32Array()


# ---------- 约定 ----------

func ground(x: float, z: float) -> float:
	return height(x, z)


func floor_at(x: float, z: float, _y := INF) -> float:
	return height(x, z)


func spawn_point() -> Vector3:
	return Vector3(_spawn.x, height(_spawn.x, _spawn.z) + 0.05, _spawn.z)


func spawn_yaw() -> float:
	return _spawn_yaw


func remote_blast(_p: Vector3, _r: float) -> void:
	pass


func prewarm(_timeout := 10.0) -> float:
	await get_tree().process_frame
	await get_tree().process_frame
	return 0.0


func stats_text() -> String:
	var side := rooms.size() - main_n
	return "天南秘境（实验）：种子 %d · 主路 %d 间 / 支线 %d 间 · 主路全长约 %.0f 米 · 占地 %d × %d 米 · 刷怪区 %d · 灵匣 %d" % [
			run_seed, main_n, side, path_len, int(float(_gw - MARGIN * 2) * CELL), int(float(_gl - MARGIN * 2) * CELL), zones.size(), chests.size()]


func _ready() -> void:
	process_priority = 10
	process_physics_priority = 50
	var we := WorldEnvironment.new()
	env = BlockWorld.make_environment()
	env.fog_density *= 0.7
	we.environment = env
	add_child(we)
	sun = BlockWorld.make_sun()
	# 太阳抬高：十一米的墙只投五六米的影子，窄路不至于整条埋在影子里
	sun.transform = Transform3D(Basis.looking_at(Vector3(-0.42, -0.82, -0.38).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(sun)
	if mobile:
		sun.directional_shadow_max_distance = 80.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_blend_splits = false
		sun.shadow_blur = 1.8
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	else:
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.1
		env.ssao_power = 1.4
	_old_hook = Vfx.terrain_hook
	Vfx.terrain_hook = func(_p: Vector3, _r: float) -> bool: return false
	_mat = ShaderMaterial.new()
	_mat.shader = WORLD_SHADER
	_floor = StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(6.0, 2.0, 6.0)
	fcs.shape = fsh
	_floor.add_child(fcs)
	add_child(_floor)
	_build_ui()
	_new_run(seed_n if seed_n > 0 else boot_seed)
	if cam != null:
		cam.floor_fn = _cam_floor
		cam.occl_fn = _cam_occl
	if player != null:
		player.bound = 1.0e9
		player.ground_ref = spawn_point().y
		_floor.global_position = spawn_point() - Vector3(0, 1.0, 0)


func _exit_tree() -> void:
	Vfx.terrain_hook = _old_hook if _old_hook.is_valid() else Callable()
	if cam != null:
		cam.floor_fn = Callable()
		cam.occl_fn = Callable()
	if player != null:
		player.ground_ref = 0.0
		player.bound = Player.BOUND


# ---------- 拼一局 ----------

## 房间转 k 个直角（顺时针，俯视）后的大小和门
static func _rot_def(def: Dictionary, k: int) -> Dictionary:
	var w := int(def["w"])
	var l := int(def["l"])
	var out: Array = []
	var di := 0
	for d: Array in def["doors"]:
		var side := str(d[0])
		var off := int(d[1])
		var cw := w
		var cl := l
		for _r in k:
			if side == "N":
				side = "E"
			elif side == "E":
				side = "S"
				off = cl - off - Rooms.DW
			elif side == "S":
				side = "W"
			else:
				side = "N"
				off = cl - off - Rooms.DW
			var tmp := cw
			cw = cl
			cl = tmp
		out.append({"side": side, "off": off, "dy": float(d[2]), "spare": bool(d[3]), "idx": di, "used": false, "arch": false})
		di += 1
	return {"w": w if k % 2 == 0 else l, "l": l if k % 2 == 0 else w, "doors": out}


## 房间里的一点（格坐标）转 k 个直角之后在哪
static func _rot_pt(x: float, z: float, w: int, l: int, k: int) -> Vector2:
	var cw := w
	var cl := l
	for _r in k:
		var nx := float(cl) - z
		z = x
		x = nx
		var tmp := cw
		cw = cl
		cl = tmp
	return Vector2(x, z)


func _overlaps(x: int, z: int, w: int, l: int) -> bool:
	for p: Dictionary in rooms:
		if x < int(p["x"]) + int(p["w"]) and int(p["x"]) < x + w and z < int(p["z"]) + int(p["l"]) and int(p["z"]) < z + l:
			return true
	return false


## 把 id 这间房接到 cur 的某道空门上（only >= 0：只试这一道门）。strict：主路不走备用门。接不上返回空字典
func _attach(cur: Dictionary, id: String, rng: RandomNumberGenerator, only := -1, strict := true) -> Dictionary:
	var def: Dictionary = Rooms.DEFS[id]
	var cd: Array = cur["doors"]
	var cands: Array = []
	for di in cd.size():
		var dc: Dictionary = cd[di]
		if bool(dc["used"]) or (only >= 0 and di != only):
			continue
		if strict and only < 0 and bool(dc["spare"]):
			continue
		for k in 4:
			var rr := _rot_def(def, k)
			var nw := int(rr["w"])
			var nl := int(rr["l"])
			var rd: Array = rr["doors"]
			for ti in rd.size():
				var dt: Dictionary = rd[ti]
				if strict and bool(dt["spare"]):
					continue
				if str(dt["side"]) != str(OPP[str(dc["side"])]):
					continue
				var nx := 0
				var nz := 0
				match str(dc["side"]):
					"E":
						nx = int(cur["x"]) + int(cur["w"])
						nz = int(cur["z"]) + int(dc["off"]) - int(dt["off"])
					"W":
						nx = int(cur["x"]) - nw
						nz = int(cur["z"]) + int(dc["off"]) - int(dt["off"])
					"S":
						nz = int(cur["z"]) + int(cur["l"])
						nx = int(cur["x"]) + int(dc["off"]) - int(dt["off"])
					_:
						nz = int(cur["z"]) - nl
						nx = int(cur["x"]) + int(dc["off"]) - int(dt["off"])
				if _overlaps(nx, nz, nw, nl):
					continue
				cands.append([di, k, ti, nx, nz, rr])
	if cands.is_empty():
		return {}
	var c: Array = cands[rng.randi() % cands.size()]
	var dcu: Dictionary = cd[int(c[0])]
	var rr2: Dictionary = c[5]
	var doors: Array = rr2["doors"]
	var dtu: Dictionary = doors[int(c[2])]
	dcu["used"] = true
	dtu["used"] = true
	dtu["arch"] = true
	var room := {"id": id, "k": int(c[1]), "x": int(c[3]), "z": int(c[4]), "w": int(rr2["w"]), "l": int(rr2["l"]),
			"base": float(cur["base"]) + float(dcu["dy"]) - float(dtu["dy"]), "doors": doors, "main": -1}
	rooms.append(room)
	return room


func _generate(sd: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	rooms.clear()
	var used := {}
	var cur := {}
	var mains: Array = []
	for si in Rooms.SEQ.size():
		var pool: Array = (Rooms.SEQ[si] as Array).duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var tmp: String = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		var fresh: Array = []
		var stale: Array = []
		for id: String in pool:
			if used.has(id):
				stale.append(id)
			else:
				fresh.append(id)
		var got := {}
		for id2: String in fresh + stale:
			if cur.is_empty():
				var rr := _rot_def(Rooms.DEFS[id2], rng.randi() % 4)
				got = {"id": id2, "k": 0, "x": 0, "z": 0, "w": int(rr["w"]), "l": int(rr["l"]), "base": 0.0, "doors": rr["doors"], "main": -1}
				# 开场那间的朝向也随机
				var k0 := rng.randi() % 4
				var r0 := _rot_def(Rooms.DEFS[id2], k0)
				got["k"] = k0
				got["w"] = int(r0["w"])
				got["l"] = int(r0["l"])
				got["doors"] = r0["doors"]
				rooms.append(got)
			else:
				got = _attach(cur, id2, rng, -1, true)
				if got.is_empty():
					got = _attach(cur, id2, rng, -1, false)
			if not got.is_empty():
				break
		if got.is_empty():
			return false
		got["main"] = mains.size()
		used[str(got["id"])] = true
		mains.append(got)
		cur = got
	main_n = mains.size()
	# 支线：主路房间多出来的门，七成半接东西（四成先接一间支线房再封口，其余直接接一个死胡同）
	for m: Dictionary in mains:
		var md: Array = m["doors"]
		for di in md.size():
			if bool((md[di] as Dictionary)["used"]):
				continue
			var roll := rng.randf()
			if roll > 0.75:
				continue
			var c := m
			var cdoor := di
			if roll < 0.4:
				var sr := _attach(c, str(Rooms.SIDE[rng.randi() % Rooms.SIDE.size()]), rng, di, false)
				if not sr.is_empty():
					c = sr
					cdoor = -1
					var sd2: Array = sr["doors"]
					for k in sd2.size():
						if not bool((sd2[k] as Dictionary)["used"]):
							cdoor = k
			if cdoor >= 0:
				var caps: Array = Rooms.CAPS.duplicate()
				var st := rng.randi() % caps.size()
				for q in caps.size():
					if not _attach(c, str(caps[(st + q) % caps.size()]), rng, cdoor, false).is_empty():
						break
	return true


func _new_run(sd: int) -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Run"
	add_child(_root)
	_mobs.clear()
	zones.clear()
	chests.clear()
	_extract = Vector3.INF
	_extract_t = 0.0
	if sd <= 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		sd = 1 + r.randi() % 99999
	var t0 := Time.get_ticks_msec()
	var ok := false
	var tries := 0
	while not ok and tries < 200:
		ok = _generate(sd + tries * 7919)
		tries += 1
	run_seed = sd
	if not ok:
		push_error("[mijing] 拼不出来（种子 %d）" % sd)
		return
	_build_grid()
	var t1 := Time.get_ticks_msec()
	_build_mesh()
	_build_props()
	_build_tags()
	_bake_map()
	_last = Vector3(INF, 0, 0)
	_last_phys = Vector2(INF, 0)
	_safe = Vector3.INF
	print("[mijing] %s | 试了 %d 次 · 拼 + 画房间 %d ms · 建网格 %d ms" % [stats_text(), tries, t1 - t0, Time.get_ticks_msec() - t1])
	var order := ""
	for rm: Dictionary in rooms:
		if int(rm["main"]) >= 0:
			order += "%s%s " % [NUMS[int(rm["main"]) % NUMS.size()], str(Rooms.DEFS[str(rm["id"])]["name"])]
	print("[mijing] 主路：", order)
	if _info != null:
		_info.text = ("天南秘境 · 第 %d 局" % run_seed) if mobile else ("天南秘境 · 第 %d 局    M 全图 · F6 换一局" % run_seed)


# ---------- 高度表 ----------

func _idx(x: float, z: float) -> int:
	var i := int(floorf(x / CELL)) - _gx0
	var j := int(floorf(z / CELL)) - _gz0
	if i < 0 or j < 0 or i >= _gw or j >= _gl:
		return -1
	return j * _gw + i


func height(x: float, z: float) -> float:
	var k := _idx(x, z)
	return _rock_top if k < 0 else _h[k]


func type_at(x: float, z: float) -> int:
	var k := _idx(x, z)
	return 0 if k < 0 else int(_t[k])


func y_cap(p: Vector3) -> float:
	var k := _idx(p.x, p.z)
	return 1.0e9 if k < 0 else _cap[k]


func _hc(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _gw or j >= _gl:
		return _rock_top
	return _h[j * _gw + i]


static func _hash(i: int, j: int) -> float:
	var n := (i * 73856093) ^ (j * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


func _build_grid() -> void:
	var x0 := 1 << 30
	var z0 := 1 << 30
	var x1 := -(1 << 30)
	var z1 := -(1 << 30)
	var bmax := -1.0e9
	_base_min = 1.0e9
	for rm: Dictionary in rooms:
		x0 = mini(x0, int(rm["x"]))
		z0 = mini(z0, int(rm["z"]))
		x1 = maxi(x1, int(rm["x"]) + int(rm["w"]))
		z1 = maxi(z1, int(rm["z"]) + int(rm["l"]))
		bmax = maxf(bmax, float(rm["base"]))
		_base_min = minf(_base_min, float(rm["base"]))
	_gx0 = x0 - MARGIN
	_gz0 = z0 - MARGIN
	_gw = x1 - x0 + MARGIN * 2
	_gl = z1 - z0 + MARGIN * 2
	_rock_top = BASE_Y + bmax + Rooms.WALL + 3.0
	var n := _gw * _gl
	_h.resize(n)
	_h.fill(_rock_top)
	_t.resize(n)
	_t.fill(0)
	_fb.resize(n)
	_fb.fill(BASE_Y + _base_min)
	_cap.resize(n)
	_cap.fill(1.0e9)
	_room.resize(n)
	_room.fill(-1)
	path_len = 0.0
	var prev := Vector2.INF
	for ri in rooms.size():
		var rm: Dictionary = rooms[ri]
		var def: Dictionary = Rooms.DEFS[str(rm["id"])]
		var open: Array = []
		open.resize((def["doors"] as Array).size())
		open.fill(false)
		for d: Dictionary in rm["doors"]:
			open[int(d["idx"])] = bool(d["used"])
		var R: Rooms.Room = Rooms.make(str(rm["id"]), open)
		var by := BASE_Y + float(rm["base"])
		var k := int(rm["k"])
		for j in R.l:
			for i in R.w:
				var c := _rot_pt(float(i) + 0.5, float(j) + 0.5, R.w, R.l, k)
				var gi := int(rm["x"]) + int(floorf(c.x)) - _gx0
				var gj := int(rm["z"]) + int(floorf(c.y)) - _gz0
				var g := gj * _gw + gi
				var ty := int(R.t[j * R.w + i])
				_h[g] = by + R.h[j * R.w + i]
				_t[g] = ty
				_fb[g] = by if (ty == Rooms.T_ROCK or ty == Rooms.T_PILLAR) else _h[g]
				_cap[g] = by + R.cap
				_room[g] = ri
		rm["by"] = by
		rm["props"] = R.props
		rm["rw"] = R.w
		rm["rl"] = R.l
		var cen := Vector2((float(rm["x"]) + float(rm["w"]) * 0.5) * CELL, (float(rm["z"]) + float(rm["l"]) * 0.5) * CELL)
		rm["cen"] = cen
		if int(rm["main"]) >= 0:
			if prev.x != INF:
				path_len += prev.distance_to(cen)
			prev = cen
		for z: Array in R.zones:
			var zp := _rot_pt(float(z[0]), float(z[1]), R.w, R.l, k)
			var wx := (float(rm["x"]) + zp.x) * CELL
			var wz := (float(rm["z"]) + zp.y) * CELL
			zones.append({"pos": Vector3(wx, 0.0, wz), "r": float(z[2]) * CELL, "n": int(z[3]), "elite": bool(z[4]), "done": false, "room": ri})
	# 山体的天际线：每格随机高 0 ~ 2 米
	for j in _gl:
		for i in _gw:
			var g2 := j * _gw + i
			if _t[g2] == 0:
				_h[g2] += floorf(_hash(i + _gx0, j + _gz0) * 3.0)
	for z2: Dictionary in zones:
		var p: Vector3 = z2["pos"]
		z2["pos"] = Vector3(p.x, height(p.x, p.z), p.z)
	# 出生点：开场那间的阵心，面朝它的门
	var s: Dictionary = rooms[0]
	var sc := _rot_pt(11.0, 11.0, int(s["rw"]), int(s["rl"]), int(s["k"]))
	_spawn = Vector3((float(s["x"]) + sc.x) * CELL, 0.0, (float(s["z"]) + sc.y) * CELL)
	var dir := Vector3(1, 0, 0)
	match str(((s["doors"] as Array)[0] as Dictionary)["side"]):
		"N":
			dir = Vector3(0, 0, -1)
		"S":
			dir = Vector3(0, 0, 1)
		"W":
			dir = Vector3(-1, 0, 0)
	_spawn_yaw = atan2(-dir.x, -dir.z)


# ---------- 网格 ----------

func _flush(shadow: bool) -> void:
	if _mv.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _mv
	arrays[Mesh.ARRAY_NORMAL] = _mn
	arrays[Mesh.ARRAY_COLOR] = _mc
	arrays[Mesh.ARRAY_INDEX] = _mi
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	_mv = PackedVector3Array()
	_mn = PackedVector3Array()
	_mc = PackedColorArray()
	_mi = PackedInt32Array()


func _top_col(ty: int, i: int, j: int) -> Color:
	var hs := _hash(i * 3 + 1, j * 5 + 2)
	var even := (i + j) % 2 == 0
	match ty:
		Rooms.T_ROCK:
			return Color(0.36, 0.52, 0.34) if hs > 0.72 else Color(0.50, 0.47, 0.52).lerp(Color(0.58, 0.55, 0.56), hs)
		Rooms.T_STONE:
			return (Color(0.84, 0.78, 0.69) if even else Color(0.78, 0.72, 0.65)) * (0.96 + 0.08 * hs)
		Rooms.T_PATH:
			return (Color(0.63, 0.68, 0.74) if even else Color(0.58, 0.63, 0.70)) * (0.96 + 0.08 * hs)
		Rooms.T_GRASS:
			var c := Color(0.36, 0.63, 0.29).lerp(Color(0.49, 0.73, 0.33), hs)
			return c if hs > 0.12 else Color(0.31, 0.56, 0.27)
		Rooms.T_MOSS:
			return Color(0.33, 0.50, 0.36).lerp(Color(0.44, 0.58, 0.40), hs)
		Rooms.T_WATER:
			return Color(0.36, 0.80, 0.86).lerp(Color(0.30, 0.70, 0.84), hs)
		Rooms.T_JADE:
			return (Color(0.36, 0.64, 0.60) if even else Color(0.32, 0.58, 0.56)) * (0.94 + 0.1 * hs)
		Rooms.T_RED:
			return (Color(0.60, 0.25, 0.21) if even else Color(0.54, 0.22, 0.19)) * (0.96 + 0.08 * hs)
		Rooms.T_DARK:
			return (Color(0.42, 0.40, 0.47) if even else Color(0.37, 0.35, 0.42)) * (0.96 + 0.08 * hs)
		Rooms.T_SOIL:
			return Color(0.50, 0.36, 0.24) * (0.92 + 0.14 * hs)
		Rooms.T_WOOD:
			return (Color(0.64, 0.45, 0.27) if even else Color(0.56, 0.39, 0.24)) * (0.95 + 0.1 * hs)
		Rooms.T_GOLD:
			return (Color(0.90, 0.68, 0.30) if even else Color(0.82, 0.60, 0.26)) * (0.96 + 0.08 * hs)
		Rooms.T_PILLAR:
			return Color(0.50, 0.50, 0.57)
	return Color(0.6, 0.6, 0.6)


static func _top_em(ty: int) -> float:
	match ty:
		Rooms.T_WATER:
			return 0.35
		Rooms.T_JADE:
			return 0.06
		Rooms.T_GOLD:
			return 0.22
	return 0.0


func _ao(i: int, j: int, dx: int, dz: int, h: float) -> float:
	var n := 0
	if _hc(i + dx, j) > h + 0.4:
		n += 1
	if _hc(i, j + dz) > h + 0.4:
		n += 1
	if _hc(i + dx, j + dz) > h + 0.4:
		n += 1
	return float([1.0, 0.84, 0.72, 0.62][n])


func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, em: float) -> void:
	var b := _mv.size()
	_mv.append(p0)
	_mv.append(p1)
	_mv.append(p2)
	_mv.append(p3)
	var cc := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), em)
	for _k in 4:
		_mn.append(n)
		_mc.append(cc)
	_mi.append_array([b, b + 2, b + 1, b, b + 3, b + 2])


## 一面侧壁（p0 → p1 是顶边，朝 n），从 ytop 到 ybot。山体按绝对高度两米一层换色（一道道岩层横着连过去），墙根压暗；
## 石柱 / 碑上半截嵌一道发光的青纹；其余（台阶、路肩）用顶面颜色压暗
func _side(p0: Vector3, p1: Vector3, n: Vector3, ytop: float, ybot: float, ty: int, top_c: Color, hs: float) -> void:
	if ty == Rooms.T_PILLAR:
		var cuts := [ytop, ytop - 1.0, ytop - 1.5, ybot]
		for s in 3:
			var ya: float = cuts[s]
			var yb: float = maxf(cuts[s + 1], ybot)
			if yb >= ya - 0.01:
				continue
			var c := Color(0.42, 0.78, 0.76) if s == 1 else Color(0.47, 0.47, 0.55).lerp(Color(0.38, 0.38, 0.47), float(s) * 0.5)
			_quad(Vector3(p0.x, ya, p0.z), Vector3(p1.x, ya, p1.z), Vector3(p1.x, yb, p1.z), Vector3(p0.x, yb, p0.z), n, c, 0.55 if s == 1 else 0.0)
		return
	if ty != Rooms.T_ROCK:
		_quad(Vector3(p0.x, ytop, p0.z), Vector3(p1.x, ytop, p1.z), Vector3(p1.x, ybot, p1.z), Vector3(p0.x, ybot, p0.z), n,
				Color(top_c.r * 0.74, top_c.g * 0.72, top_c.b * 0.76), 0.0)
		return
	var y := ytop
	while y > ybot + 0.01:
		var yb2 := maxf(floorf((y - 0.01) / 2.0) * 2.0, ybot)
		var band := int(floorf((y - 0.01) / 2.0))
		var c2: Color = [Color(0.66, 0.53, 0.45), Color(0.57, 0.49, 0.48), Color(0.50, 0.46, 0.53), Color(0.60, 0.55, 0.52)][posmod(band, 4)]
		c2 = c2 * (0.93 + 0.12 * hs)
		var k := lerpf(0.70, 1.0, clampf(((y + yb2) * 0.5 - ybot) / 5.0, 0.0, 1.0))
		_quad(Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Vector3(p1.x, yb2, p1.z), Vector3(p0.x, yb2, p0.z), n,
				Color(c2.r * k, c2.g * lerpf(k, 1.0, 0.08), c2.b * lerpf(k, 1.0, 0.24)), 0.0)
		y = yb2


func _build_mesh() -> void:
	# 离能走的地方 5 格以外的山体不画（镜头在墙里头，看不到）
	var near := PackedByteArray()
	near.resize(_gw * _gl)
	near.fill(0)
	for j in _gl:
		for i in _gw:
			if _t[j * _gw + i] != 0:
				for dj in range(maxi(j - 5, 0), mini(j + 6, _gl)):
					for di in range(maxi(i - 5, 0), mini(i + 6, _gw)):
						near[dj * _gw + di] = 1
	var cj := 0
	while cj < _gl:
		var ci := 0
		while ci < _gw:
			for j in range(cj, mini(cj + CHUNK, _gl)):
				for i in range(ci, mini(ci + CHUNK, _gw)):
					_mesh_cell(i, j, near)
			_flush(true)
			ci += CHUNK
		cj += CHUNK
	# 云面：云渊底下、山外面都是它
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(_gw) * CELL + 1600.0, float(_gl) * CELL + 1600.0)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.93, 0.90, 0.93)
	var cl := MeshInstance3D.new()
	cl.mesh = pm
	cl.material_override = cm
	cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cl.position = Vector3((float(_gx0) + float(_gw) * 0.5) * CELL, BASE_Y + _base_min + Rooms.VOID_H + 0.9, (float(_gz0) + float(_gl) * 0.5) * CELL)
	_root.add_child(cl)


func _mesh_cell(i: int, j: int, near: PackedByteArray) -> void:
	var g := j * _gw + i
	var ty := int(_t[g])
	if ty == Rooms.T_VOID or (ty == 0 and near[g] == 0):
		return
	var h := _h[g]
	var x0 := float(i + _gx0) * CELL
	var z0 := float(j + _gz0) * CELL
	var c := _top_col(ty, i + _gx0, j + _gz0)
	var em := _top_em(ty)
	var ao := [_ao(i, j, -1, -1, h), _ao(i, j, 1, -1, h), _ao(i, j, 1, 1, h), _ao(i, j, -1, 1, h)]
	var b := _mv.size()
	_mv.append(Vector3(x0, h, z0))
	_mv.append(Vector3(x0 + CELL, h, z0))
	_mv.append(Vector3(x0 + CELL, h, z0 + CELL))
	_mv.append(Vector3(x0, h, z0 + CELL))
	for k in 4:
		var a: float = ao[k]
		_mn.append(Vector3.UP)
		_mc.append(Color(minf(c.r * a, 1.0), minf(c.g * lerpf(a, 1.0, 0.06), 1.0), minf(c.b * lerpf(a, 1.0, 0.22), 1.0), em))
	if absf(float(ao[0]) - float(ao[2])) <= absf(float(ao[1]) - float(ao[3])):
		_mi.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		_mi.append_array([b, b + 1, b + 3, b + 1, b + 2, b + 3])
	var hs := _hash(i * 7 + 3, j * 11 + 5)
	for k2 in 4:
		var ni: int = i + int([-1, 1, 0, 0][k2])
		var nj: int = j + int([0, 0, -1, 1][k2])
		if ni < 0 or nj < 0 or ni >= _gw or nj >= _gl:
			continue
		var nh := _h[nj * _gw + ni]
		if _t[nj * _gw + ni] == Rooms.T_VOID:
			nh -= 2.0          # 云渊边的崖壁多往下画一截，扎进云面里
		if nh >= h - 0.01:
			continue
		match k2:
			0:
				_side(Vector3(x0, 0, z0 + CELL), Vector3(x0, 0, z0), Vector3.LEFT, h, nh, ty, c, hs)
			1:
				_side(Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3.RIGHT, h, nh, ty, c, hs)
			2:
				_side(Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3.FORWARD, h, nh, ty, c, hs)
			3:
				_side(Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL), Vector3.BACK, h, nh, ty, c, hs)


# ---------- 点缀 ----------

var _pa: Array = []

func _bx(size: Vector3, pos: Vector3, c: Color, yaw := 0.0, em := 0.0, tilt := Vector3.ZERO) -> void:
	BlockWorld._box(_pa, size, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(tilt), pos), c, em, 0.74)


func _build_props() -> void:
	for ri in rooms.size():
		var rm: Dictionary = rooms[ri]
		_pa = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
		var k := int(rm["k"])
		for p: Array in rm["props"]:
			var q := _rot_pt(float(p[1]), float(p[2]), int(rm["rw"]), int(rm["rl"]), k)
			var wx := (float(rm["x"]) + q.x) * CELL
			var wz := (float(rm["z"]) + q.y) * CELL
			_prop(str(p[0]), Vector3(wx, height(wx, wz), wz), float(p[3]) - float(k) * PI * 0.5, float(p[4]), float(rm["by"]))
		# 接上的门：一座牌坊
		for d: Dictionary in rm["doors"]:
			if not bool(d["arch"]):
				continue
			var mid := float(d["off"]) + float(Rooms.DW) * 0.5
			var pos := Vector3.ZERO
			var yaw := 0.0
			match str(d["side"]):
				"N":
					pos = Vector3((float(rm["x"]) + mid) * CELL, 0.0, float(rm["z"]) * CELL)
				"S":
					pos = Vector3((float(rm["x"]) + mid) * CELL, 0.0, (float(rm["z"]) + float(rm["l"])) * CELL)
				"W":
					pos = Vector3(float(rm["x"]) * CELL, 0.0, (float(rm["z"]) + mid) * CELL)
					yaw = PI * 0.5
				"E":
					pos = Vector3((float(rm["x"]) + float(rm["w"])) * CELL, 0.0, (float(rm["z"]) + mid) * CELL)
					yaw = PI * 0.5
			pos.y = float(rm["by"]) + float(d["dy"])
			_arch(pos, yaw)
		_mv = _pa[0]
		_mn = _pa[1]
		_mc = _pa[2]
		_mi = _pa[3]
		_flush(true)


func _arch(p: Vector3, yaw: float) -> void:
	var ax := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var red := Color(0.70, 0.22, 0.17)
	for s: float in [-1.0, 1.0]:
		_bx(Vector3(0.9, 6.2, 0.9), p + ax * s * 4.2 + Vector3(0, 3.1, 0), red, yaw)
		_bx(Vector3(1.3, 0.7, 1.3), p + ax * s * 4.2 + Vector3(0, 0.35, 0), Color(0.62, 0.60, 0.63), yaw)
	_bx(Vector3(9.8, 0.7, 0.8), p + Vector3(0, 5.6, 0), red * 0.9, yaw)
	_bx(Vector3(10.8, 0.4, 1.9), p + Vector3(0, 6.5, 0), Color(0.20, 0.42, 0.45), yaw)
	_bx(Vector3(8.6, 0.35, 1.3), p + Vector3(0, 6.95, 0), Color(0.24, 0.48, 0.50), yaw)
	_bx(Vector3(2.4, 0.9, 0.98), p + Vector3(0, 4.75, 0), Color(0.16, 0.14, 0.16), yaw)
	_bx(Vector3(1.7, 0.36, 1.12), p + Vector3(0, 4.75, 0), Color(1.0, 0.82, 0.42), yaw, 0.6)


func _prop(kind: String, p: Vector3, yaw: float, s: float, by: float) -> void:
	var stone := Color(0.62, 0.60, 0.63)
	var red := Color(0.72, 0.22, 0.17)
	var teal := Color(0.20, 0.42, 0.45)
	var gold := Color(1.0, 0.82, 0.42)
	var cyan := Color(0.45, 0.90, 0.95)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.BACK
	var rgt := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	match kind:
		"lamp":
			_bx(Vector3(0.7, 0.3, 0.7), p + Vector3(0, 0.15, 0), stone)
			_bx(Vector3(0.36, 2.2, 0.36), p + Vector3(0, 1.3, 0), stone * 0.9)
			_bx(Vector3(0.62, 0.56, 0.62), p + Vector3(0, 2.68, 0), Color(1.0, 0.78, 0.42), 0.0, 1.0)
			_bx(Vector3(0.9, 0.18, 0.9), p + Vector3(0, 3.05, 0), teal)
		"stele":
			_bx(Vector3(1.8, 0.34, 0.9), p + Vector3(0, 0.17, 0), stone, yaw)
			_bx(Vector3(1.3, 3.2, 0.46), p + Vector3(0, 1.9, 0), Color(0.42, 0.44, 0.50), yaw)
			_bx(Vector3(0.34, 2.0, 0.60), p + Vector3(0, 2.0, 0), cyan, yaw, 0.6)
		"crystal":
			_bx(Vector3(0.55, 2.0, 0.55) * s, p + Vector3(0, 0.9 * s, 0), cyan, yaw, 0.8, Vector3(0.18, 0, 0.12))
			_bx(Vector3(0.42, 1.4, 0.42) * s, p + rgt * 0.6 * s + Vector3(0, 0.6 * s, 0), Color(0.55, 0.80, 1.0), yaw + 0.8, 0.8, Vector3(-0.3, 0, 0.25))
			_bx(Vector3(0.36, 1.0, 0.36) * s, p - rgt * 0.5 * s + fwd * 0.3 * s + Vector3(0, 0.45 * s, 0), cyan, yaw + 2.0, 0.8, Vector3(0.2, 0, -0.35))
		"pine":
			_bx(Vector3(0.5, 3.0, 0.5), p + Vector3(0, 1.5, 0), Color(0.42, 0.29, 0.20))
			_bx(Vector3(2.8, 1.0, 2.8), p + Vector3(0, 2.7, 0), Color(0.20, 0.42, 0.30), 0.3)
			_bx(Vector3(2.1, 1.0, 2.1), p + Vector3(0, 3.7, 0), Color(0.23, 0.47, 0.32), 0.7)
			_bx(Vector3(1.25, 1.1, 1.25), p + Vector3(0, 4.75, 0), Color(0.27, 0.52, 0.35), 1.1)
		"maple":
			_bx(Vector3(0.5, 2.8, 0.5), p + Vector3(0, 1.4, 0), Color(0.36, 0.25, 0.20))
			_bx(Vector3(3.0, 1.5, 3.0), p + Vector3(0.2, 3.3, 0.1), Color(0.86, 0.36, 0.20), yaw * 0.37)
			_bx(Vector3(2.1, 1.3, 2.1), p + Vector3(-0.7, 4.3, 0.5), Color(0.93, 0.52, 0.24), yaw * 0.6 + 0.5)
			_bx(Vector3(1.7, 1.1, 1.7), p + Vector3(0.9, 4.1, -0.7), Color(0.80, 0.27, 0.19), yaw * 0.8 + 1.1)
		"bamboo":
			for k in 3:
				var o := Vector3(cos(yaw + float(k) * 2.1) * 0.5, 0, sin(yaw + float(k) * 2.1) * 0.5)
				var hh := 4.2 + 0.7 * float(k)
				_bx(Vector3(0.2, hh, 0.2), p + o + Vector3(0, hh * 0.5, 0), Color(0.42, 0.66, 0.32), 0.0, 0.0, Vector3(0.04 * float(k - 1), 0, 0.03))
				_bx(Vector3(1.0, 0.5, 1.0), p + o + Vector3(0, hh - 0.1, 0), Color(0.36, 0.60, 0.30), yaw + float(k))
		"rock":
			_bx(Vector3(1.5, 1.0, 1.2) * s, p + Vector3(0, 0.45 * s, 0), Color(0.52, 0.50, 0.55), yaw)
			_bx(Vector3(0.9, 0.7, 0.9) * s, p + rgt * 0.8 * s + Vector3(0, 0.3 * s, 0), Color(0.58, 0.55, 0.58), yaw + 0.7)
		"banner":
			_bx(Vector3(0.16, 4.4, 0.16), p + Vector3(0, 2.2, 0), Color(0.30, 0.22, 0.18))
			_bx(Vector3(0.9, 2.3, 0.1), p + rgt * 0.5 + Vector3(0, 3.1, 0), red, yaw)
			_bx(Vector3(0.9, 0.26, 0.16), p + rgt * 0.5 + Vector3(0, 3.9, 0), gold, yaw, 0.35)
		"chest":
			_bx(Vector3(1.2, 0.72, 0.8), p + Vector3(0, 0.36, 0), Color(0.50, 0.32, 0.18), yaw)
			_bx(Vector3(1.28, 0.3, 0.88), p + Vector3(0, 0.86, 0), Color(0.60, 0.38, 0.20), yaw)
			_bx(Vector3(0.24, 1.08, 0.96), p + Vector3(0, 0.52, 0), gold, yaw, 0.5)
			_bx(Vector3(0.14, 3.2, 0.14), p + Vector3(0, 2.7, 0), gold, 0.0, 0.9)
			chests.append(p)
		"censer":
			_bx(Vector3(1.3, 0.3, 1.3), p + Vector3(0, 0.15, 0), stone)
			_bx(Vector3(0.9, 0.8, 0.9), p + Vector3(0, 0.7, 0), Color(0.50, 0.40, 0.24))
			_bx(Vector3(1.1, 0.16, 1.1), p + Vector3(0, 1.18, 0), Color(0.42, 0.33, 0.20))
			_bx(Vector3(0.5, 0.3, 0.5), p + Vector3(0, 1.4, 0), Color(1.0, 0.6, 0.3), 0.0, 0.9)
		"brazier":
			_bx(Vector3(0.5, 0.9, 0.5), p + Vector3(0, 0.45, 0), Color(0.34, 0.32, 0.36))
			_bx(Vector3(1.0, 0.36, 1.0), p + Vector3(0, 1.06, 0), Color(0.30, 0.28, 0.32))
			_bx(Vector3(0.64, 0.6, 0.64), p + Vector3(0, 1.5, 0), Color(1.0, 0.55, 0.2), 0.6, 1.0)
		"altar":
			_bx(Vector3(2.6, 0.9, 1.3), p + Vector3(0, 0.45, 0), stone, yaw)
			_bx(Vector3(2.7, 0.1, 0.9), p + Vector3(0, 0.96, 0), red, yaw)
			_bx(Vector3(0.5, 0.5, 0.5), p + Vector3(0, 1.4, 0), cyan, yaw + 0.6, 0.9)
		"shelf":
			_bx(Vector3(2.6, 3.1, 0.6), p + Vector3(0, 1.55, 0), Color(0.36, 0.24, 0.17), yaw)
			for k2 in 3:
				_bx(Vector3(2.3, 0.44, 0.72), p + Vector3(0, 0.75 + float(k2) * 0.9, 0),
						[Color(0.60, 0.46, 0.30), Color(0.36, 0.48, 0.52), Color(0.62, 0.30, 0.24)][k2], yaw)
		"beam":
			_bx(Vector3(s * CELL, 0.6, 0.6), Vector3(p.x, by + 8.7, p.z), Color(0.52, 0.19, 0.15), yaw)
		"pavilion":
			for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				_bx(Vector3(0.42, 3.5, 0.42), p + Vector3(q.x * 2.4 * s, 1.75, q.y * 2.4 * s), red)
			_bx(Vector3(6.6, 0.45, 6.6) * Vector3(s, 1, s), p + Vector3(0, 3.7, 0), teal)
			_bx(Vector3(4.6, 0.5, 4.6) * Vector3(s, 1, s), p + Vector3(0, 4.2, 0), Color(0.24, 0.48, 0.50))
			_bx(Vector3(2.4, 0.6, 2.4) * Vector3(s, 1, s), p + Vector3(0, 4.75, 0), teal)
			_bx(Vector3(0.5, 0.7, 0.5), p + Vector3(0, 5.4, 0), gold, 0.0, 0.5)
		"sealgate":
			for sx: float in [-1.0, 1.0]:
				_bx(Vector3(1.0, 6.4, 1.0), p + rgt * sx * 3.6 + Vector3(0, 3.2, 0), Color(0.36, 0.36, 0.44), yaw)
				_bx(Vector3(0.4, 4.4, 1.14), p + rgt * sx * 3.6 + Vector3(0, 3.0, 0), cyan, yaw, 0.6)
			_bx(Vector3(9.4, 0.9, 1.2), p + Vector3(0, 6.6, 0), Color(0.32, 0.32, 0.40), yaw)
			_bx(Vector3(10.6, 0.4, 2.0), p + Vector3(0, 7.25, 0), teal, yaw)
			for k3 in 3:
				_bx(Vector3(0.6, 1.1, 0.12), p + rgt * (float(k3) - 1.0) * 1.6 + Vector3(0, 5.5, 0), cyan, yaw, 0.8)
		"gsword":
			var lean := Vector3(0.10, 0, 0.07)
			var up := (Basis(Vector3.UP, yaw) * Basis.from_euler(lean)) * Vector3.UP
			_bx(Vector3(1.0, 7.0, 0.24) * s, p + up * 3.3 * s, Color(0.60, 0.64, 0.72), yaw, 0.0, lean)
			_bx(Vector3(0.16, 6.6, 0.32) * s, p + up * 3.3 * s, cyan, yaw, 0.5, lean)
			_bx(Vector3(2.5, 0.42, 0.56) * s, p + up * 6.95 * s, Color(0.55, 0.42, 0.24), yaw, 0.0, lean)
			_bx(Vector3(0.36, 1.5, 0.36) * s, p + up * 7.9 * s, Color(0.24, 0.20, 0.22), yaw, 0.0, lean)
			_bx(Vector3(0.6, 0.5, 0.6) * s, p + up * 8.85 * s, gold, yaw, 0.4, lean)
		"waterfall":
			_bx(Vector3(3.2, 11.0, 0.7), Vector3(p.x, by + 5.2, p.z), Color(0.75, 0.92, 1.0), yaw, 0.55)
			_bx(Vector3(2.0, 11.0, 0.9), Vector3(p.x, by + 5.2, p.z), Color(0.90, 0.98, 1.0), yaw, 0.7)
			_bx(Vector3(4.0, 0.5, 2.0), Vector3(p.x, by - 0.5, p.z) + fwd * 0.9, Color(0.92, 0.98, 1.0), yaw, 0.6)
		"herb":
			var fc: Color = [Color(0.5, 0.95, 0.9), Color(1.0, 0.6, 0.8), Color(1.0, 0.85, 0.45), Color(0.75, 0.65, 1.0)][posmod(int(yaw), 4)]
			_bx(Vector3(0.16, 0.8 * s, 0.16), p + Vector3(0, 0.4 * s, 0), Color(0.30, 0.55, 0.28))
			_bx(Vector3(0.7, 0.14, 0.7), p + Vector3(0, 0.3 * s, 0), Color(0.34, 0.62, 0.30), 0.6)
			_bx(Vector3(0.42, 0.42, 0.42) * s, p + Vector3(0, 0.95 * s, 0), fc, 0.5, 0.7)
		"extract":
			for k4 in 8:
				var a := float(k4) * TAU / 8.0
				_bx(Vector3(2.6, 0.14, 0.4), p + Vector3(cos(a) * 3.3, 0.1, sin(a) * 3.3), gold, -a + PI * 0.5, 0.9)
			for k5 in 4:
				var a2 := float(k5) * TAU / 4.0 + PI * 0.25
				_bx(Vector3(0.5, 2.6, 0.5), p + Vector3(cos(a2) * 3.4, 1.3, sin(a2) * 3.4), Color(0.36, 0.36, 0.44))
				_bx(Vector3(0.6, 0.5, 0.6), p + Vector3(cos(a2) * 3.4, 2.85, sin(a2) * 3.4), gold, 0.0, 0.9)
			_extract = p


## 每间房头顶一块名牌（主路带序号）：看结构用
func _build_tags() -> void:
	for rm: Dictionary in rooms:
		var lb := Label3D.new()
		var nm: String = str(Rooms.DEFS[str(rm["id"])]["name"])
		lb.text = ("%s %s" % [NUMS[int(rm["main"]) % NUMS.size()], nm]) if int(rm["main"]) >= 0 else nm
		lb.font = font if font != null else UiStyle.kai()
		lb.font_size = 120
		lb.pixel_size = 0.02
		lb.outline_size = 28
		lb.modulate = Color(1.0, 0.95, 0.84) if int(rm["main"]) >= 0 else Color(1.0, 0.86, 0.5)
		lb.outline_modulate = Color(0.08, 0.06, 0.05, 0.9)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.visibility_range_end = 150.0
		var c: Vector2 = rm["cen"]
		lb.position = Vector3(c.x, float(rm["by"]) + 12.5, c.y)
		_root.add_child(lb)


# ---------- 落脚 / 撞墙（规矩同 ex_level.gd，只是没有另外的实心盒子） ----------

func _wall_at(q: Vector2, y: float) -> bool:
	return height(q.x, q.y) - y > STEP_UP


func _clip(from: Vector2, to: Vector2, y: float) -> Vector2:
	var d := to - from
	var ln := d.length()
	if ln < 0.0005:
		return to
	var dn := d / ln
	if _wall_at(from, y):
		return to
	var n := maxi(int(ceilf(ln / 0.3)), 1)
	var lo := 0.0
	var hit := -1.0
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		if _wall_at(from + d * t + dn * BODY_R, y):
			hit = t
			break
		lo = t
	if hit < 0.0:
		return to
	var hi := hit
	for k in 4:
		var mid := (lo + hi) * 0.5
		if _wall_at(from + d * mid + dn * BODY_R, y):
			hi = mid
		else:
			lo = mid
	var at := from + d * lo
	var rest := to - at
	if absf(rest.x) > 0.0005 and not _wall_at(Vector2(at.x + rest.x + signf(rest.x) * BODY_R, at.y), y):
		return Vector2(at.x + rest.x, at.y)
	if absf(rest.y) > 0.0005 and not _wall_at(Vector2(at.x, at.y + rest.y + signf(rest.y) * BODY_R), y):
		return Vector2(at.x, at.y + rest.y)
	return at


func _ramp(nx: float, nz: float, d: float, h0: float) -> float:
	var up := height(nx, nz) - h0
	if up < 0.05 or up > STEP_UP:
		return h0
	var w := clampf(RAMP_MIN + RAMP_K * up, RAMP_MIN, RAMP_MAX)
	if d >= w:
		return h0
	var t := 1.0 - d / w
	return h0 + up * t * t * (3.0 - 2.0 * t)


func _walk_h(x: float, z: float, h0: float) -> float:
	var fx := fposmod(x, CELL)
	var fz := fposmod(z, CELL)
	var best := h0
	var ex: Array = [[fx, -1.0], [CELL - fx, 1.0]]
	var ez: Array = [[fz, -1.0], [CELL - fz, 1.0]]
	for a: Array in ex:
		if float(a[0]) < RAMP_MAX:
			best = maxf(best, _ramp(x + float(a[1]) * (float(a[0]) + 0.05), z, float(a[0]), h0))
	for b: Array in ez:
		if float(b[0]) < RAMP_MAX:
			best = maxf(best, _ramp(x, z + float(b[1]) * (float(b[0]) + 0.05), float(b[0]), h0))
	for a2: Array in ex:
		for b2: Array in ez:
			var d := Vector2(float(a2[0]), float(b2[0])).length()
			if d < RAMP_MAX:
				best = maxf(best, _ramp(x + float(a2[1]) * (float(a2[0]) + 0.05), z + float(b2[1]) * (float(b2[0]) + 0.05), d, h0))
	return best


func _jump_reach(y: float) -> float:
	var vy := maxf(player.velocity.y, 0.0)
	return y + vy * vy / (2.0 * Player.GRAVITY)


## 怪走不走得过去（raid_mob 的 block_fn）
func blocked(from: Vector3, to: Vector3) -> bool:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var n := maxi(int(ceilf(d.length() / 1.0)), 1)
	var y := from.y
	for i in range(1, n + 1):
		var q := Vector2(from.x, from.z) + d * (float(i) / float(n))
		var h := height(q.x, q.y)
		if h - y > STEP_UP or type_at(q.x, q.y) == Rooms.T_VOID:
			return true
		y = h
	return false


func _process(dt: float) -> void:
	worst_frame_ms = maxf(worst_frame_ms, dt * 1000.0)
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
		_toast.position = Vector2((get_viewport().get_visible_rect().size.x - _toast.size.x) * 0.5, get_viewport().get_visible_rect().size.y * 0.24)
	if player == null or _busy or _gw == 0:
		return
	_constrain()
	_update_map()


func _constrain() -> void:
	var p := player.global_position
	if _last.x == INF:
		_last = p
	var mv := Vector2(p.x - _last.x, p.z - _last.z)
	var warp := mv.length() > 6.0
	if not warp:
		# 头顶：每间房自己的飞行上限（禁空，翻不过墙）
		var cap := minf(y_cap(Vector3(p.x, 0, p.z)), y_cap(Vector3(_last.x, 0, _last.z)) + 6.0)
		if p.y > cap:
			p.y = cap
			if player.velocity.y > 0.0:
				player.velocity.y = 0.0
		if mv.length() > 0.0005:
			var np := _clip(Vector2(_last.x, _last.z), Vector2(p.x, p.z), minf(p.y, maxf(_last.y, p.y - 0.5)))
			if np.distance_to(Vector2(p.x, p.z)) > 0.0005:
				if absf(np.x - p.x) > 0.0005:
					player.velocity.x = 0.0
				if absf(np.y - p.z) > 0.0005:
					player.velocity.z = 0.0
				p.x = np.x
				p.z = np.y
				if _bump_t <= 0.0:
					wall_bumps += 1
				_bump_t = 0.5
		if player.st == Player.St.GROUND:
			var h := height(p.x, p.z)
			if h - p.y <= STEP_UP:
				var he := _walk_h(p.x, p.z, h)
				var rise := he - p.y
				if (rise > 0.02 and rise <= STEP_UP and (player.is_on_floor() or rise < 0.6)) \
						or (rise < -0.02 and rise >= -STEP_UP and player.velocity.y <= 0.01 and (player.is_on_floor() or rise > -0.6)):
					p.y = he
					_floor.global_position = Vector3(p.x, he - 1.0, p.z)
	player.global_position = p
	_last = p


func _physics_process(dt: float) -> void:
	if player == null or _busy or _gw == 0:
		return
	var p := player.global_position
	var h := height(p.x, p.z)
	_bump_t -= dt
	var air := player.st != Player.St.GROUND and player.st != Player.St.DIVE
	var warped := _last_phys.x == INF or Vector2(p.x, p.z).distance_to(_last_phys) > 4.0
	if air:
		if h > p.y + 0.02 and h - p.y <= STEP_UP:
			player.global_position.y = h
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
	elif player.st == Player.St.GROUND and not warped:
		if h - p.y > STEP_UP:
			var hb2 := height(_last_phys.x, _last_phys.y)
			if not player.is_on_floor() and hb2 - p.y <= STEP_UP and h - p.y <= STEP_UP * 2.0 and player.velocity.y > -6.0 \
					and _jump_reach(p.y) >= h - STEP_UP and h + BODY_H < y_cap(p) + BODY_H:
				player.global_position.x = _last_phys.x
				player.global_position.z = _last_phys.y
				var my := p.y + MANTLE_SPD * dt
				player.global_position.y = my
				player.velocity.y = maxf(player.velocity.y, 0.0)
				_floor.global_position = Vector3(_last_phys.x, minf(hb2, my) - 1.0, _last_phys.y)
				_last_phys = Vector2(player.global_position.x, player.global_position.z)
				_last = player.global_position
				return
			var np := _clip(_last_phys, Vector2(p.x, p.z), p.y)
			player.global_position.x = np.x
			player.global_position.z = np.y
			p = player.global_position
			h = height(p.x, p.z)
		var he := _walk_h(p.x, p.z, h)
		var rise := he - p.y
		if rise > 0.02 and rise <= STEP_UP:
			if player.is_on_floor() or rise < 0.6:
				player.global_position.y = he
			else:
				player.global_position.y = minf(he, p.y + MANTLE_SPD * dt)
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
		elif rise < -0.02 and rise >= -STEP_UP and player.velocity.y <= 0.01 and (player.is_on_floor() or rise > -0.6):
			player.global_position.y = he
		if rise <= STEP_UP:
			h = he
	p = player.global_position
	player.ground_ref = lerpf(player.ground_ref, h, 1.0 - exp(-3.0 * dt))
	if p.y < h - 0.05 and h - p.y <= STEP_UP * 2.0:
		player.global_position.y = h
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	_last_phys = Vector2(player.global_position.x, player.global_position.z)
	_floor.global_position = Vector3(_last_phys.x, h - 1.0, _last_phys.y)
	_rules(dt)


## 这张图自己的规矩：掉进云渊送回上一个落脚点；走近刷怪区才刷；撤离阵里站三秒离开
func _rules(dt: float) -> void:
	var p := player.global_position
	var ty := type_at(p.x, p.z)
	var h := height(p.x, p.z)
	_safe_t -= dt
	if ty == Rooms.T_VOID:
		if p.y < h + 2.2 and _safe.x != INF:
			player.global_position = _safe
			player.velocity = Vector3.ZERO
			if player.st != Player.St.GROUND:
				player.force_ground()
			_last = _safe
			_last_phys = Vector2(_safe.x, _safe.z)
			say("云渊之下是虚空 · 已送回崖边")
	elif player.st == Player.St.GROUND and absf(p.y - h) < 0.3 and ty != Rooms.T_PILLAR and ty != Rooms.T_ROCK and _safe_t <= 0.0:
		# 只记离云渊两格以外的点（不然送回来一脚又踩空）
		var ok := true
		for o: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			if type_at(p.x + o.x, p.z + o.y) == Rooms.T_VOID:
				ok = false
		if ok:
			_safe = Vector3(p.x, h + 0.05, p.z)
			_safe_t = 0.4
	_zone_t -= dt
	if _zone_t <= 0.0:
		_zone_t = 0.5
		if not no_mobs:
			for z: Dictionary in zones:
				if not bool(z["done"]) and (z["pos"] as Vector3).distance_to(p) < 46.0:
					z["done"] = true
					_spawn_zone(z)
	if _extract.x != INF:
		if Vector2(p.x - _extract.x, p.z - _extract.z).length() < 3.6 and absf(p.y - _extract.y) < 3.0:
			if _extract_t <= 0.0:
				say("撤离阵启动 · 三息后离开秘境")
			_extract_t += dt
			if _extract_t > 3.0:
				_extract_t = -1.0e9
				say("已撤离 · 天南秘境")
				exit_requested.emit()
		elif _extract_t > 0.0:
			_extract_t = 0.0
			say("离开了撤离阵 · 已中断")


func _spawn_zone(z: Dictionary) -> void:
	if not ResourceLoader.exists(MOB_PATH) or not ResourceLoader.exists(EXMOBS_PATH):
		return
	var mob_scr: GDScript = load(MOB_PATH)
	var ex_scr: GDScript = load(EXMOBS_PATH)
	if mob_scr == null or ex_scr == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(z["pos"]) ^ run_seed
	var kinds := ["scorpion", "wolf_sand", "sand_guard"]
	var c: Vector3 = z["pos"]
	for i in int(z["n"]):
		var q := c
		for _try in 8:
			var o := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.6, float(z["r"]))
			var t := Vector3(c.x + o.x, 0.0, c.z + o.y)
			var ty := type_at(t.x, t.z)
			if ty != Rooms.T_ROCK and ty != Rooms.T_PILLAR and ty != Rooms.T_VOID and absf(height(t.x, t.z) - c.y) < 2.5:
				q = Vector3(t.x, height(t.x, t.z), t.z)
				break
		var m: Node3D = mob_scr.new()
		m.set("player", player)
		var elite := bool(z["elite"]) and i == 0
		ex_scr.call("setup", m, "sand_guard" if elite else str(kinds[rng.randi() % 2]), elite)
		m.set("floor_fn", Callable(self, "ground"))
		m.set("block_fn", Callable(self, "blocked"))
		m.set("dmg_in", func(d: float) -> float: return d / maxf(float(player.call("hero_base")), 1.0) * 10.0)
		m.set("atk_out", func(d: float) -> float: return d)
		m.position = q
		m.set("home", q)
		_root.add_child(m)
		_mobs.append(m)


# ---------- 镜头 ----------

func _cam_floor(x: float, z: float) -> float:
	var k := _idx(x, z)
	return BASE_Y + _base_min if k < 0 else _fb[k]


func _cam_occl(x: float, z: float) -> float:
	return height(x, z)


# ---------- 界面：小地图 / 全图 / 换一局 ----------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	add_child(_ui)
	_mini = TextureRect.new()
	_mini.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.modulate.a = 0.92
	_ui.add_child(_mini)
	_dot = ColorRect.new()
	_dot.color = UiStyle.CINNABAR
	_dot.size = Vector2(9, 9)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_dot)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", UiStyle.TEXT)
	_info.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_info.add_theme_constant_override("outline_size", 5)
	_info.add_theme_font_override("font", font if font != null else UiStyle.kai())
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_info)
	var names := [["全图", "_toggle_big"], ["换一局", "reroll"], ["离开", "leave"]]
	for i in names.size():
		var b := Button.new()
		b.text = str(names[i][0])
		b.custom_minimum_size = Vector2(96, 50)
		b.add_theme_font_size_override("font_size", 22)
		if font != null:
			b.add_theme_font_override("font", font)
		UiStyle.style_button(b)
		b.focus_mode = Control.FOCUS_NONE
		b.add_to_group("touch_ui")
		b.pressed.connect(Callable(self, str(names[i][1])))
		b.set_meta("slot", i)
		_ui.add_child(b)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26 if mobile else 22)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_font_override("font", font if font != null else UiStyle.kai())
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_toast)
	_big = Control.new()
	_big.visible = false
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_big)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.04, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.add_child(shade)
	_big_tex = TextureRect.new()
	_big_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_big_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.add_child(_big_tex)
	_big_dot = ColorRect.new()
	_big_dot.color = UiStyle.CINNABAR
	_big_dot.size = Vector2(12, 12)
	_big_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.add_child(_big_dot)


func say(text: String, col := Color(1.0, 0.86, 0.62)) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.reset_size()
	_toast_t = 2.6


## 俯视全图：一格一个像素（能走的地方亮、山体不画）；主路房间的序号牌另外叠在全图上
func _bake_map() -> void:
	var img := map_image()
	_map_tex = ImageTexture.create_from_image(img)
	_mini.texture = _map_tex
	_big_tex.texture = _map_tex
	for t: Node in _big_tags:
		t.queue_free()
	_big_tags.clear()
	for rm: Dictionary in rooms:
		var lb := Label.new()
		var nm: String = str(Rooms.DEFS[str(rm["id"])]["name"])
		lb.text = ("%s %s" % [NUMS[int(rm["main"]) % NUMS.size()], nm]) if int(rm["main"]) >= 0 else nm
		lb.add_theme_font_size_override("font_size", 20 if int(rm["main"]) >= 0 else 16)
		lb.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86) if int(rm["main"]) >= 0 else Color(1.0, 0.84, 0.5))
		lb.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.95))
		lb.add_theme_constant_override("outline_size", 6)
		lb.add_theme_font_override("font", font if font != null else UiStyle.kai())
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.set_meta("cen", rm["cen"])
		_big.add_child(lb)
		_big_tags.append(lb)


func map_image(scale := 1) -> Image:
	var img := Image.create(_gw * scale, _gl * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.09, 0.10, 0.80))
	for j in _gl:
		for i in _gw:
			var g := j * _gw + i
			var ty := int(_t[g])
			if ty == 0:
				continue
			var c := Color(0.93, 0.90, 0.82)
			match ty:
				Rooms.T_PATH:
					c = Color(0.80, 0.84, 0.88)
				Rooms.T_GRASS, Rooms.T_MOSS:
					c = Color(0.60, 0.76, 0.50)
				Rooms.T_WATER:
					c = Color(0.48, 0.76, 0.88)
				Rooms.T_JADE:
					c = Color(0.50, 0.82, 0.76)
				Rooms.T_RED:
					c = Color(0.78, 0.34, 0.28)
				Rooms.T_DARK:
					c = Color(0.66, 0.64, 0.72)
				Rooms.T_SOIL:
					c = Color(0.66, 0.50, 0.36)
				Rooms.T_VOID:
					c = Color(0.62, 0.68, 0.84, 0.75)
				Rooms.T_WOOD:
					c = Color(0.74, 0.56, 0.36)
				Rooms.T_GOLD:
					c = Color(1.0, 0.82, 0.36)
				Rooms.T_PILLAR:
					c = Color(0.26, 0.26, 0.32)
			# 高的地方亮一点
			if ty != Rooms.T_VOID and ty != Rooms.T_PILLAR and _room[g] >= 0:
				var rel := _h[g] - float((rooms[_room[g]] as Dictionary)["by"])
				c = c * clampf(1.0 + rel * 0.03, 0.85, 1.12)
				c.a = 1.0
			if scale == 1:
				img.set_pixel(i, j, c)
			else:
				img.fill_rect(Rect2i(i * scale, j * scale, scale, scale), c)
	return img


func _update_map() -> void:
	var vs := get_viewport().get_visible_rect().size
	var mw := 230.0 if not mobile else 250.0
	var mh := mw * float(_gl) / maxf(float(_gw), 1.0)
	if mh > 230.0:
		mh = 230.0
		mw = mh * float(_gw) / maxf(float(_gl), 1.0)
	var mp := Vector2((vs.x - mw) * 0.5, 10.0)
	_mini.position = mp
	_mini.size = Vector2(mw, mh)
	var p := player.global_position
	var u := Vector2((p.x / CELL - float(_gx0)) / float(_gw), (p.z / CELL - float(_gz0)) / float(_gl))
	_dot.position = mp + Vector2(u.x * mw, u.y * mh) - _dot.size * 0.5
	_info.position = Vector2(mp.x + mw + 14.0, 12.0)
	var bi := 0
	for b: Node in _ui.get_children():
		if b is Button:
			(b as Button).position = Vector2(mp.x + mw + 14.0 + float(bi) * 104.0, 44.0)
			(b as Button).visible = not _big.visible or bi == 0
			bi += 1
	if _big.visible:
		var k := minf(vs.x * 0.86 / float(_gw), vs.y * 0.82 / float(_gl))
		var bs := Vector2(float(_gw), float(_gl)) * k
		var bp := (vs - bs) * 0.5 + Vector2(0, 16)
		_big_tex.position = bp
		_big_tex.size = bs
		_big_dot.position = bp + Vector2(u.x * bs.x, u.y * bs.y) - _big_dot.size * 0.5
		for t: Node in _big_tags:
			var lb := t as Label
			var c: Vector2 = lb.get_meta("cen")
			var cu := Vector2((c.x / CELL - float(_gx0)) / float(_gw), (c.y / CELL - float(_gz0)) / float(_gl))
			lb.position = bp + Vector2(cu.x * bs.x, cu.y * bs.y) - lb.size * 0.5


func _toggle_big() -> void:
	_big.visible = not _big.visible
	_mini.visible = not _big.visible
	_dot.visible = not _big.visible


## 换一局：换个种子重新拼，人回到新的接引阵台
func reroll(sd := 0) -> void:
	if _busy:
		return
	_busy = true
	if _big.visible:
		_toggle_big()
	player.force_ground()
	_new_run(sd)
	var sp := spawn_point()
	player.global_position = sp
	player.velocity = Vector3.ZERO
	player.face_now(_spawn_yaw)
	player.ground_ref = sp.y
	_floor.global_position = sp - Vector3(0, 1.0, 0)
	if cam != null:
		cam.snap(_spawn_yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
	say("第 %d 局 · 主路 %d 间 · 支线 %d 间" % [run_seed, main_n, rooms.size() - main_n])
	_busy = false


func leave() -> void:
	exit_requested.emit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_M:
			_toggle_big()
		elif k == KEY_F6:
			reroll()


## 自检：从 a 附近能走的格子出发，按「相邻格高差不超过两格、不进云渊」能不能走到 b 附近（房间中心可能是柱子 / 水，取最近的能走格）
func reachable(a: Vector2, b: Vector2) -> bool:
	var s := _near_walk(a)
	var e := _near_walk(b)
	if s < 0 or e < 0:
		return false
	var seen := PackedByteArray()
	seen.resize(_gw * _gl)
	seen.fill(0)
	var q := PackedInt32Array([s])
	seen[s] = 1
	var head := 0
	while head < q.size():
		var g := q[head]
		head += 1
		if g == e:
			return true
		var i := g % _gw
		var j := g / _gw
		for k in 4:
			var ni: int = i + int([-1, 1, 0, 0][k])
			var nj: int = j + int([0, 0, -1, 1][k])
			if ni < 0 or nj < 0 or ni >= _gw or nj >= _gl:
				continue
			var ng := nj * _gw + ni
			if seen[ng] == 1 or _t[ng] == Rooms.T_ROCK or _t[ng] == Rooms.T_PILLAR or _t[ng] == Rooms.T_VOID:
				continue
			if absf(_h[ng] - _h[g]) > STEP_UP:
				continue
			seen[ng] = 1
			q.append(ng)
	return false


func _near_walk(p: Vector2) -> int:
	var ci := int(floorf(p.x / CELL)) - _gx0
	var cj := int(floorf(p.y / CELL)) - _gz0
	for r in 14:
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var i := ci + di
				var j := cj + dj
				if i < 0 or j < 0 or i >= _gw or j >= _gl:
					continue
				var t := int(_t[j * _gw + i])
				if t != Rooms.T_ROCK and t != Rooms.T_PILLAR and t != Rooms.T_VOID:
					return j * _gw + i
	return -1
