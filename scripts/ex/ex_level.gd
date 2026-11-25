extends Node3D
## 搜打撤 PvP 新图的关卡节点（2026-11-24，SPEC 第 1.3 / 5 节）：沙海古墟（desert）/ 天工秘所（lab）。main.gd 按 map_id 建。
## 管的事：环境 / 太阳 / 昼夜（房间时钟）、方块世界（grid_world.gd）、主角落脚与挡路（地上走缓坡、空中撞墙、楼里撞顶）、
##   镜头不钻地 / 不被自己所在那栋楼的屋顶挡、进出洞窟（0.4 秒黑场传送）、边界（沙暴推回 + 掉血 / 禁制光幕弹回 / 掉进深谷送回）、
##   小地图整图底图 + 全屏大地图、点位表（points()，给 extract_manager.gd 用）。
## 玩法（搜箱 / 撤离 / 怪 / Boss）全在 extract_manager.gd（E 写），有这个脚本就建、没有 raid = null，关卡照样能走。
## 关卡契约（main.gd / net.gd 鸭子类型调用）：exit_requested；player / cam / font / mobile / net / map_id / raid / env / sun / world；
##   spawn_point / spawn_yaw / prewarm / stats_text / ground / remote_blast；另给 E：solid_at / blocked / layer_of / teleport_links /
##   points / is_night / day_phase / floor_at / set_door / door_open / find_spawn_near / y_cap。
## 故意不写 class_name：用 preload 引用。

signal exit_requested
signal layer_changed(layer: String)      # 进出洞窟之后（新层名）
signal hazard(kind: String, k: float)    # 边界：「sand」沙暴（k = 浓度）/「barrier」光幕 /「chasm」掉谷

const MapDef := preload("res://scripts/ex/map_def.gd")
const GridWorld := preload("res://scripts/ex/grid_world.gd")
const Destruct := preload("res://scripts/destruct.gd")      # 2026-11-25 场景破坏
const BlockWorld := preload("res://scripts/block_world.gd")
const CreatureModels := preload("res://scripts/creature_model.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const RaidProfile := preload("res://scripts/raid_profile.gd")
const Minimap := preload("res://scripts/minimap.gd")
const MANAGER_PATH := "res://scripts/ex/extract_manager.gd"

var player: Player
var cam: CameraRig
var font: Font
var mobile := false
var net: Node = null
var map_id := "desert"
var raid: Node = null           # extract_manager.gd 实例（没有这个脚本时为 null）
var env: Environment
var sun: DirectionalLight3D
var world: GridWorld
var motes: CPUParticles3D
var map: Dictionary = {}
var layer := "surface"          # 主角现在在哪一层（"surface" / "cavern"）
var teleport_links: Array = []  # 进出洞窟的点（见 map_def.gd 的 links）
var worst_frame_ms := 0.0
var clock_off := 0.0            # 自检：房间时钟往后拨多少秒（看夜景）
var wall_bumps := 0             # 撞墙次数（自检看）
var ceil_bumps := 0             # 撞顶次数（自检看）
var teleports := 0
var storm_hurt := 0.0           # 沙暴一共掉了多少点（自检看）

const STEP_UP := 2.25           # 两格以内是台阶（走缓坡），再高是墙
const BODY_HEAD := 1.6          # 整个在这以上的盒子（屋檐 / 楼板）从底下过
const BODY_H := 2.1             # 头顶：天花板夹到这里
const BODY_R := 0.42            # 身体半宽：撞墙按身前这么远的点算
const AIR_LIFT := 1.0           # 飞着：比脚面高不出这么多的实心顶面直接托上去，再高的是墙
const TERR_LIFT := 2.25         # 飞着碰到地形：两格以内托上去，再高的是崖壁（挡住、沿着滑）
const RAMP_MIN := 0.55
const RAMP_K := 0.4
const RAMP_MAX := 1.5
const MANTLE_SPD := 12.0
const RAMP_DIRS: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0),
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071)]
const TP_FADE := 0.2            # 进出洞窟：黑场 0.2 秒 + 亮回来 0.2 秒
const WARP_MIN := 6.0           # 一帧水平挪了这么多以上、又不是主角自己的速度带过去的，才当成传送（见 _is_warp）

var _floor: StaticBody3D
var _last := Vector3(INF, 0, 0)          # 上一帧（渲染帧）摆正后的位置
var _last_phys := Vector2(INF, 0)
var _bump_t := 0.0
var _spawn := {}
var _stats: Label
var _old_far := 4000.0
var _old_dof := Vector2(260.0, 500.0)
var _old_dof_on := true
var _old_hook: Callable
var _clock := 0.0
var _tp_busy := false
var _tp_cool := 0.0
var _hurt_t := 0.0
var _tip_t := 0.0
var _storm_k := 0.0
var _sun_k := 1.0                         # 兼容渲染器：带影子的主光乘 0.11（同 raid_manager）
var _atmo := {}                          # 现在的天色参数（逐帧往目标渐变）
var _maps := {}                          # 层 → {tex, center, span, img}
var _big: CanvasLayer
var _bigc: Control                       # 大地图本体（minimap.gd 的 BigMap）
var _big_3d_off := false                 # 大地图盖严之后把 3D 关了（关图时还原）
var _big_3d_was := false
var _toast: Label
var _toast_t := 0.0
var _late: Node
var _early: Node
var _v_pre := Vector3.ZERO               # 这一帧主角挪之前的速度（_early 在主角之前记）
var _old_shadows := true


# ---------- 契约：出生 / 地面 ----------

func ground(x: float, z: float) -> float:
	return world.height(x, z)


## 脚在 y 高度的人 / 怪 / 掉落物，在 (x, z) 这一点踩在多高（地形 + 实心盒子的顶面；整个在头顶以上的不算）。y 省略 = 最高的那个顶面
func floor_at(x: float, z: float, y := INF) -> float:
	var h := world.height(x, z)
	var below := (maxf(y, h) + BODY_HEAD) if y < 1.0e8 else 1.0e9
	return maxf(h, world.solid_h(x, z, below))


func spawn_point() -> Vector3:
	var p: Vector3 = _spawn.get("pos", Vector3.ZERO)
	return Vector3(p.x, floor_at(p.x, p.z, p.y + 0.5) + 0.05, p.z)


func spawn_yaw() -> float:
	return float(_spawn.get("yaw", 0.0))


## 老接口（net.gd 的 _dig 进来的碗形坑）：新图的破坏走 Destruct 自己那几条 RPC，这里留着兜底
func remote_blast(p: Vector3, r: float) -> void:
	Destruct.blast(p, r, 1.0, Vector3.ZERO, {"remote": true})


## 出生点：照 map_def 随机挑（沙漠地面 4 + 地下 4，研究所 5）；自检固定第一个
func _choose_spawn() -> void:
	var sp: Array = map["spawns"]
	var i := 0
	if not RaidProfile.test_mode():
		var r := RandomNumberGenerator.new()
		r.randomize()
		i = r.randi() % sp.size()
	_spawn = (sp[i] as Dictionary).duplicate()
	layer = str(_spawn["layer"])


func _ready() -> void:
	process_priority = 10                 # 在主角（0）之后、镜头（20）之前：主角挪完当帧摆正，镜头跟的是摆正后的位置
	process_physics_priority = 50
	map = MapDef.map(map_id)
	teleport_links = map["links"]
	var we := WorldEnvironment.new()
	env = BlockWorld.make_environment()
	we.environment = env
	add_child(we)
	sun = BlockWorld.make_sun()
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
	_sun_k = 0.11 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0
	_choose_spawn()
	world = GridWorld.new()
	world.name = "World"
	world.target = player
	world.mobile = mobile
	world.setup(map_id)
	world.active_layer = layer
	_old_shadows = CreatureModels.shadows
	CreatureModels.shadows = not mobile
	_old_hook = Vfx.terrain_hook
	add_child(world)
	# 2026-11-25 场景破坏：新图能炸坑、能打碎方块了（原来这里把 Vfx.terrain_hook 接成「什么都不做」）。
	# Destruct.attach 把钩子接到 Destruct.blast 上、按点表划出不可破坏的范围、联机时向房主要这间房已有的破坏
	Destruct.attach(self)
	_floor = StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(6.0, 2.0, 6.0)
	fcs.shape = fsh
	_floor.add_child(fcs)
	add_child(_floor)
	_build_motes()
	_build_ui()
	_old_far = cam.cam.far
	cam.cam.far = 900.0 if mobile else 1300.0
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		_old_dof = Vector2(attr.dof_blur_far_distance, attr.dof_blur_far_transition)
		_old_dof_on = attr.dof_blur_far_enabled
		attr.dof_blur_far_enabled = not mobile
		attr.dof_blur_far_distance = 150.0
		attr.dof_blur_far_transition = 420.0
	cam.floor_fn = _cam_floor
	cam.occl_fn = _cam_occl
	player.bound = 1.0e9          # 矩形边界在 _clamp_bound 里夹（player.bound 只能夹正方形）
	var sp := spawn_point()
	player.ground_ref = sp.y
	_floor.global_position = sp - Vector3(0, 1.0, 0)
	_bake_maps()
	_apply_atmo(0.0, true)
	_late = _Tick.new()
	(_late as _Tick).cb = _late_process
	_late.process_priority = 30
	add_child(_late)
	_early = _Tick.new()
	(_early as _Tick).cb = _early_process
	_early.process_priority = -100        # 在主角（0）挪之前：记下这一帧挪之前的速度（_is_warp 用）
	add_child(_early)
	if ResourceLoader.exists(MANAGER_PATH):
		var ms: GDScript = load(MANAGER_PATH)
		if ms != null:
			raid = ms.new()
			raid.name = "Raid"
			raid.set("level", self)
			raid.set("player", player)
			raid.set("cam", cam)
			raid.set("net", net)
			raid.set("map_id", map_id)
			raid.set("font", font)
			raid.set("mobile", mobile)
			add_child(raid)


## 按自己的 process_priority 回调一下：镜头之后（洞窟里镜头别钻进洞顶上面）/ 主角之前（记速度）
class _Tick extends Node:
	var cb: Callable
	func _process(dt: float) -> void:
		if cb.is_valid():
			cb.call(dt)


func _exit_tree() -> void:
	Destruct.detach(self)
	Vfx.terrain_hook = _old_hook if _old_hook.is_valid() else Callable()
	cam.floor_fn = Callable()
	cam.occl_fn = Callable()
	cam.cam.far = _old_far
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		attr.dof_blur_far_enabled = _old_dof_on
		attr.dof_blur_far_distance = _old_dof.x
		attr.dof_blur_far_transition = _old_dof.y
	player.ground_ref = 0.0
	player.bound = Player.BOUND
	CreatureModels.shadows = _old_shadows
	close_big_map(false)          # 退图时不再把鼠标抓回去（黑场里 / 回主城由主城自己管）


## 载入：等出生点周围的细地块建好（网页单线程：黑屏时一帧给 45 毫秒）
func prewarm(timeout := 10.0) -> float:
	var t := 0.0
	var boost := world.sliced()
	if boost:
		world.slice_us = 45000
		timeout = maxf(timeout, 45.0)
	while t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		if world.ready_near(player.global_position):
			break
	if boost:
		world.slice_us = world.SLICE_US
	return t


func stats_text() -> String:
	return "%s：%s 地块 %d（细 %d）色块 %d 累计生成 %d · 静态实心盒子 %d · 烘表 %.0f ms · 最长帧 %.1f ms" % [
			map.get("name", map_id), "洞窟" if layer == "cavern" else "地面", world.chunk_count(), world.lod0_count(), world.far_count(),
			world.built, world.static_boxes, world.gen_ms, worst_frame_ms]


# ---------- 给 E 用的查询 ----------

func layer_of(p: Vector3) -> String:
	return MapDef.layer_at(p)


## p 在不在实心的东西里（地形下面、实心盒子里、洞顶上面）
func solid_at(p: Vector3) -> bool:
	if p.y < world.height(p.x, p.z) - 0.05:
		return true
	if p.y > world.ceil_at(p.x, p.z):
		return true
	return world.solid_box_at(p)


## 从 from 走到 to（怪 / AI，脚在 from.y）路上有没有墙：每 0.5 米探一下，比脚下高出两格以上的地形 / 实心盒子就是墙
func blocked(from: Vector3, to: Vector3) -> bool:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var ln := d.length()
	if ln < 0.01:
		return false
	var y := from.y
	var n := int(ceilf(ln / 0.5))
	for i in range(1, n + 1):
		var q := Vector2(from.x, from.z) + d * (float(i) / float(n))
		var h := _fl(q.x, q.y, y)
		if h - y > STEP_UP:
			return true
		y = maxf(y, h) if h - y > 0.0 else y      # 走上台阶之后按新的脚面接着探
	return false


## 绝对高度上限（脚的高度）：飞行上限 / 洞顶 / 头顶的楼板，取最低的
func y_cap(p: Vector3) -> float:
	var lay: Dictionary = (map["layers"] as Dictionary)[layer_of(p)]
	var cap: float = float(lay["fly_cap"])
	var cc := world.ceil_at(p.x, p.z)
	if cc < 1.0e8:
		cap = minf(cap, cc - BODY_H)
	var sc := world.solid_ceil(p.x, p.z, p.y + 0.5)
	if sc < 1.0e8:
		cap = minf(cap, sc - BODY_H)
	return cap


## 点表（深拷贝，y 摆到实际落脚处）。kind 和形状见交付报告 reports/W_maps.md：
## "spawn" "extract" "key_room" "box" "camp" "boss" "altar" "doctor" "link" "building" "cavern" "horde" "horde_point" "poi" "bound"
func points(kind: String) -> Array:
	var out: Array = []
	match kind:
		"spawn", "extract", "camp", "box":
			var src: Array = map[{"spawn": "spawns", "extract": "extracts", "camp": "camps", "box": "boxes"}[kind]]
			for e: Dictionary in src:
				var d := e.duplicate(true)
				var p: Vector3 = d["pos"]
				d["pos"] = Vector3(p.x, floor_at(p.x, p.z, p.y + 0.5), p.z)
				if not d.has("layer"):
					d["layer"] = layer_of(p)
				out.append(d)
		"key_room":
			for e2: Dictionary in map["key_rooms"]:
				var d2 := e2.duplicate(true)
				d2["open"] = world.door_open(str(e2["id"]))
				out.append(d2)
		"boss":
			for e3: Dictionary in map["bosses"]:
				out.append(e3.duplicate(true))
		"altar":
			for e4: Dictionary in map["bosses"]:
				if e4["altar"] != null:
					out.append({"id": "altar_" + str(e4["id"]), "boss": e4["id"], "pos": e4["altar"], "layer": e4["layer"]})
		"doctor":
			var dd: Dictionary = map.get("doctor", {})
			if not dd.is_empty():
				out.append(dd.duplicate(true))
		"link":
			for e5: Dictionary in map["links"]:
				var d5 := e5.duplicate(true)
				for k: String in ["a", "a_out", "b", "b_out"]:
					var q: Vector3 = d5[k]
					d5[k] = Vector3(q.x, floor_at(q.x, q.z, q.y + 1.0), q.z)
				out.append(d5)
		"building":
			for e6: Dictionary in map.get("buildings", []):
				var d6 := {"id": e6["id"], "name": e6["name"], "rect": e6["rect"], "floor": MapDef.LAB_Y,
						"top": MapDef.LAB_Y + float(int(e6.get("storeys", 1))) * GridWorld.STOREY + 0.6, "enterable": true,
						"storeys": e6.get("storeys", 1), "layer": layer_of(Vector3((e6["rect"] as Rect2).position.x, 0, 0))}
				if e6.has("upper"):
					d6["upper"] = e6["upper"]
					d6["upper_y"] = MapDef.LAB_Y + GridWorld.STOREY
				out.append(d6)
		"cavern":
			var lay: Dictionary = (map["layers"] as Dictionary)["cavern"]
			out.append({"id": "cavern", "layer": "cavern", "rect": lay["grid"], "ceil": float((map["cave"] as Dictionary)["ceil"]),
					"floor_min": 10.0, "fly_cap": lay["fly_cap"]})
		"horde":
			var hd: Dictionary = map.get("horde", {})
			if not hd.is_empty():
				out.append(hd.duplicate(true))
		"horde_point":
			for hp: Vector3 in map.get("horde_points", []):
				out.append({"pos": Vector3(hp.x, floor_at(hp.x, hp.z), hp.z), "layer": "surface"})
		"poi":
			for e7: Dictionary in map.get("pois", []):
				out.append(e7.duplicate(true))
		"bound":
			for ln: String in ["surface", "cavern"]:
				var l2: Dictionary = (map["layers"] as Dictionary)[ln]
				out.append({"layer": ln, "rect": l2["bound"], "play": l2["play"], "fly_cap": l2["fly_cap"], "ceil": l2["ceil"]})
	return out


## 在 center 周围 r_min ~ r_max 米的环上找一处能站人的地方（同一层、在边界里、不在墙里、地面不比 center 高出太多）。找不到返回 center
func find_spawn_near(center: Vector3, r_min: float, r_max: float, rng: RandomNumberGenerator = null) -> Vector3:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var ln := layer_of(center)
	var bnd: Rect2 = ((map["layers"] as Dictionary)[ln] as Dictionary)["play"]
	for i in 24:
		var a := r.randf() * TAU
		var d := r.randf_range(r_min, r_max)
		var q := Vector3(center.x + cos(a) * d, center.y, center.z + sin(a) * d)
		if not bnd.grow(-6.0).has_point(Vector2(q.x, q.z)) or layer_of(q) != ln:
			continue
		var h := floor_at(q.x, q.z, center.y + 1.0)
		if absf(h - center.y) > 6.0 or world.solid_box_at(Vector3(q.x, h + 1.0, q.z)):
			continue
		if h > world.ceil_at(q.x, q.z) - 3.0:
			continue
		return Vector3(q.x, h, q.z)
	return center


func set_door(id: String, open: bool) -> void:
	world.set_door(id, open)


func door_open(id: String) -> bool:
	return world.door_open(id)


# ---------- 昼夜（房间时钟，SPEC 4.9） ----------

## 房间时钟（秒）：联机时用 net.room_t（全房一致），单机用关卡自己的时钟
func room_time() -> float:
	if net != null and bool(net.get("active")):
		return float(net.get("room_t")) + clock_off
	return _clock + clock_off


## 一个昼夜周期（1200 秒）里的第几秒：0 ~ 600 白天、600 ~ 1200 黑夜
func day_phase() -> float:
	return fposmod(room_time(), MapDef.DAY_LEN + MapDef.NIGHT_LEN)


func is_night() -> bool:
	return day_phase() >= MapDef.DAY_LEN


## 白天的第几秒（夜里返回 -1）：营救天工师「白天第 180 ~ 300 秒」用
func day_sec() -> float:
	var c := day_phase()
	return c if c < MapDef.DAY_LEN else -1.0


## 天色有多「夜」：0 白天 ~ 1 黑夜；交界前 6 秒渐变（白天最后 6 秒入夜、夜里最后 6 秒天亮）
func night_k() -> float:
	var c := day_phase()
	var full := MapDef.DAY_LEN + MapDef.NIGHT_LEN
	if c < MapDef.DAY_LEN - MapDef.DUSK:
		return 0.0
	if c < MapDef.DAY_LEN:
		return smoothstep(MapDef.DAY_LEN - MapDef.DUSK, MapDef.DAY_LEN, c)
	if c < full - MapDef.DUSK:
		return 1.0
	return 1.0 - smoothstep(full - MapDef.DUSK, full, c)


const ATMO := {
	"desert": {
		"day": {"top": Color(0.34, 0.55, 0.90), "hor": Color(1.0, 0.86, 0.64), "fog": Color(0.96, 0.85, 0.66), "fog_d": 0.0010,
				"amb": Color(0.80, 0.78, 0.78), "amb_e": 0.62, "sun": Color(1.0, 0.92, 0.76), "sun_e": 1.6, "clouds": 0.3, "stars": 0.0,
				"emis": 2.0, "hs": Color(1.0, 1.0, 1.0), "hg": Color(0.86, 0.80, 0.76), "fill": Color(0, 0, 0), "shadow": 0.84,
				"expo": 1.0, "sat": 1.06, "con": 1.06, "mote": Color(1.0, 0.88, 0.62), "alt": 52.0, "az": Vector2(0.55, 0.83)},
		"night": {"top": Color(0.02, 0.035, 0.09), "hor": Color(0.12, 0.14, 0.26), "fog": Color(0.10, 0.12, 0.22), "fog_d": 0.0020,
				"amb": Color(0.42, 0.48, 0.74), "amb_e": 0.5, "sun": Color(0.60, 0.70, 1.0), "sun_e": 0.42, "clouds": 0.2, "stars": 1.0,
				"emis": 2.6, "hs": Color(0.86, 0.90, 1.0), "hg": Color(0.60, 0.62, 0.76), "fill": Color(0.04, 0.05, 0.09), "shadow": 0.7,
				"expo": 1.08, "sat": 0.95, "con": 1.04, "mote": Color(0.72, 0.82, 1.0), "alt": 40.0, "az": Vector2(-0.6, 0.8)},
		"cave": {"top": Color(0.03, 0.03, 0.04), "hor": Color(0.06, 0.05, 0.06), "fog": Color(0.10, 0.08, 0.08), "fog_d": 0.0085,
				"amb": Color(0.56, 0.50, 0.54), "amb_e": 0.66, "sun": Color(1, 1, 1), "sun_e": 0.0, "clouds": 0.0, "stars": 0.0,
				"emis": 2.4, "hs": Color(0.78, 0.74, 0.82), "hg": Color(0.66, 0.60, 0.62), "fill": Color(0.13, 0.10, 0.08), "shadow": 0.6,
				"expo": 1.05, "sat": 1.0, "con": 1.06, "mote": Color(1.0, 0.72, 0.42), "alt": 50.0, "az": Vector2(0.55, 0.83)},
	},
	"lab": {
		"day": {"top": Color(0.38, 0.55, 0.84), "hor": Color(0.92, 0.88, 0.80), "fog": Color(0.80, 0.80, 0.80), "fog_d": 0.0013,
				"amb": Color(0.74, 0.77, 0.88), "amb_e": 0.62, "sun": Color(1.0, 0.94, 0.84), "sun_e": 1.45, "clouds": 0.5, "stars": 0.0,
				"emis": 2.0, "hs": Color(1.0, 1.0, 1.0), "hg": Color(0.80, 0.80, 0.88), "fill": Color(0, 0, 0), "shadow": 0.84,
				"expo": 1.0, "sat": 1.04, "con": 1.06, "mote": Color(0.9, 0.9, 0.86), "alt": 50.0, "az": Vector2(0.62, 0.78)},
		"night": {"top": Color(0.015, 0.03, 0.06), "hor": Color(0.07, 0.11, 0.16), "fog": Color(0.06, 0.10, 0.13), "fog_d": 0.0028,
				"amb": Color(0.34, 0.46, 0.56), "amb_e": 0.46, "sun": Color(0.58, 0.74, 0.96), "sun_e": 0.32, "clouds": 0.3, "stars": 1.0,
				"emis": 3.2, "hs": Color(0.82, 0.90, 0.98), "hg": Color(0.54, 0.62, 0.70), "fill": Color(0.03, 0.06, 0.08), "shadow": 0.7,
				"expo": 1.1, "sat": 0.92, "con": 1.05, "mote": Color(0.6, 0.95, 0.85), "alt": 42.0, "az": Vector2(-0.5, 0.86)},
		"cave": {"top": Color(0.02, 0.03, 0.03), "hor": Color(0.04, 0.06, 0.05), "fog": Color(0.06, 0.10, 0.08), "fog_d": 0.0095,
				"amb": Color(0.44, 0.56, 0.50), "amb_e": 0.64, "sun": Color(1, 1, 1), "sun_e": 0.0, "clouds": 0.0, "stars": 0.0,
				"emis": 2.6, "hs": Color(0.70, 0.82, 0.76), "hg": Color(0.54, 0.64, 0.58), "fill": Color(0.06, 0.12, 0.09), "shadow": 0.6,
				"expo": 1.12, "sat": 0.98, "con": 1.06, "mote": Color(0.55, 1.0, 0.7), "alt": 50.0, "az": Vector2(0.62, 0.78)},
	},
}
const STORM := {"fog": Color(0.86, 0.66, 0.42), "fog_d": 0.024, "amb": Color(0.98, 0.80, 0.58), "mote": Color(0.95, 0.76, 0.48)}


## 天色 / 雾 / 日光 / 地表补光 / 曝光按「层 + 昼夜 + 沙暴」渐变（snap = 一下到位：进图、进出洞窟的黑场里）
func _apply_atmo(dt: float, snap: bool) -> void:
	var tab: Dictionary = ATMO["lab" if map_id == "lab" else "desert"]
	var tgt := {}
	if layer == "cavern":
		tgt = (tab["cave"] as Dictionary).duplicate()
	else:
		var nk := night_k()
		var a: Dictionary = tab["day"]
		var b: Dictionary = tab["night"]
		for k: String in a:
			var va: Variant = a[k]
			var vb: Variant = b[k]
			if va is Color:
				tgt[k] = (va as Color).lerp(vb as Color, nk)
			elif va is Vector2:
				tgt[k] = (va as Vector2).lerp(vb as Vector2, nk)
			else:
				tgt[k] = lerpf(float(va), float(vb), nk)
		if _storm_k > 0.001:
			var sk := _storm_k
			tgt["fog"] = (tgt["fog"] as Color).lerp(STORM["fog"], sk)
			tgt["fog_d"] = lerpf(float(tgt["fog_d"]), float(STORM["fog_d"]), sk * sk)
			tgt["amb"] = (tgt["amb"] as Color).lerp(STORM["amb"], sk * 0.6)
			tgt["mote"] = (tgt["mote"] as Color).lerp(STORM["mote"], sk)
			tgt["hor"] = (tgt["hor"] as Color).lerp(STORM["fog"], sk * 0.8)
			tgt["sun_e"] = float(tgt["sun_e"]) * (1.0 - 0.45 * sk)
	var w := 1.0 if snap or _atmo.is_empty() else 1.0 - exp(-2.4 * dt)
	for k2: String in tgt:
		var tv: Variant = tgt[k2]
		if not _atmo.has(k2) or w >= 1.0:
			_atmo[k2] = tv
		elif tv is Color:
			_atmo[k2] = (_atmo[k2] as Color).lerp(tv as Color, w)
		elif tv is Vector2:
			_atmo[k2] = (_atmo[k2] as Vector2).lerp(tv as Vector2, w)
		else:
			_atmo[k2] = lerpf(float(_atmo[k2]), float(tv), w)
	var A := _atmo
	var cave := layer == "cavern"
	env.background_mode = Environment.BG_COLOR if cave else Environment.BG_SKY
	env.background_color = A["fog"]
	env.fog_light_color = A["fog"]
	env.fog_density = float(A["fog_d"]) * (1.3 if mobile else 1.0)
	env.fog_height_density = 0.0 if cave else 0.02
	env.ambient_light_color = A["amb"]
	env.ambient_light_energy = A["amb_e"]
	env.tonemap_exposure = A["expo"]
	env.adjustment_saturation = A["sat"]
	env.adjustment_contrast = A["con"]
	sun.visible = not cave
	sun.light_color = A["sun"]
	sun.light_energy = float(A["sun_e"]) * _sun_k
	var sh: float = A["shadow"]
	sun.shadow_opacity = sh if _sun_k >= 1.0 else 1.0 - minf(1.46 * pow(1.0 - sh, 2.18), 1.0)
	var alt := deg_to_rad(float(A["alt"]))
	var az: Vector2 = (A["az"] as Vector2).normalized()
	var sto := Vector3(az.x * cos(alt), sin(alt), az.y * cos(alt))
	sun.basis = Basis.looking_at(-sto, Vector3.UP)
	var sm := env.sky.sky_material as ShaderMaterial if env.sky != null else null
	if sm != null:
		sm.set_shader_parameter("top_col", A["top"])
		sm.set_shader_parameter("hor_col", A["hor"])
		sm.set_shader_parameter("glow_col", A["sun"])
		sm.set_shader_parameter("low_col", (A["fog"] as Color).lerp(A["hor"] as Color, 0.35))
		sm.set_shader_parameter("clouds", A["clouds"])
		sm.set_shader_parameter("stars", A["stars"])
		sm.set_shader_parameter("sun_size", 1.0)
		sm.set_shader_parameter("vortex", 0.0)
	var wm: ShaderMaterial = world.mat
	if wm != null:
		var fill: Color = A["fill"]
		wm.set_shader_parameter("fill_col", Vector3(fill.r, fill.g, fill.b))
		wm.set_shader_parameter("fill_dir", Vector3(-sto.x, 0.6, -sto.z).normalized())
		var hs := (A["hs"] as Color).srgb_to_linear()
		var hg := (A["hg"] as Color).srgb_to_linear()
		wm.set_shader_parameter("hemi_sky", Vector3(hs.r, hs.g, hs.b))
		wm.set_shader_parameter("hemi_ground", Vector3(hg.r, hg.g, hg.b))
		wm.set_shader_parameter("emis", A["emis"])
	if motes != null:
		motes.color = A["mote"]


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	worst_frame_ms = maxf(worst_frame_ms, dt * 1000.0)
	_clock += dt / maxf(Engine.time_scale, 0.01)
	_tp_cool -= dt
	if motes != null:
		var sk := _storm_k
		motes.global_position = player.global_position + Vector3(0.0, 5.0, 0.0) + player.velocity * 1.5
		motes.speed_scale = 1.0 + sk * 5.0
		motes.direction = Vector3(0.4, 0.5, 0.2).lerp(_storm_dir(), sk)
	_apply_atmo(dt, false)
	if _stats.visible:
		_stats.text = stats_text()
		_stats.position = Vector2(18.0, get_viewport().get_visible_rect().size.y - 92.0)
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
		_toast.position = Vector2((get_viewport().get_visible_rect().size.x - _toast.size.x) * 0.5, get_viewport().get_visible_rect().size.y * 0.22)
	if _big != null:
		_tick_big_map()
	if _tp_busy:
		return
	# 被别的东西直接挪到了另一层（回出生点 Backspace、玩法管理器拉人）：跟着换层
	var lp := layer_of(player.global_position)
	if lp != layer:
		_set_layer(lp)
		_last = player.global_position
		_last_phys = Vector2(_last.x, _last.z)
	_constrain(dt)
	world.update_roofs(player.global_position)


## 主角挪之前（process_priority -100）：记下这一帧挪之前的速度
func _early_process(_dt: float) -> void:
	if player != null:
		_v_pre = player.velocity


## 这一帧的水平位移 mv 算不算「传送」（传送不当成走着 / 飞着撞墙，不扫墙）。
## 2026-11-24 F_maps（review combat-8）：原来只看「一帧挪了 6 米以上」。掉帧时（手机 / 网页 16 帧上下，首次出一闪 / 瞬斩编着色器的卡顿）
##   突进（无目标 lunge_v 100 米/秒、有目标最快 150 米/秒，都走 player.velocity + move_and_slide）一帧就过 6 米，整个穿过楼墙。
##   现在 6 米以上还要看主角自己的速度：位移方向和「速度 × 这帧时长」对得上、长度不超过它多少的，是招式 / 移动自己走的，照样扫墙
##   （_clip 按 0.3 米一步扫，长位移也不漏）；对不上的（速度清零的瞬身换位、回出生点、管理器拉人、洞口传送）才是传送。
##   速度取挪之前（_v_pre）和挪之后两个：突进最后一帧招式会把速度清零，第一帧挪之前还是零。
func _is_warp(mv: Vector2, dt: float) -> bool:
	var ln := mv.length()
	if ln <= WARP_MIN:
		return false
	for v: Vector3 in [_v_pre, player.velocity]:
		var e := Vector2(v.x, v.z) * dt
		var el := e.length()
		if el > 0.5 and ln <= el * 1.35 + 1.5 and mv.dot(e) >= 0.8 * ln * el:
			return false
	return true


## 渲染帧里：主角刚挪完（主角在 _process 里移动）。当帧就摆正：头顶夹住、撞墙沿墙滑、地上走贴缓坡、夹进边界
func _constrain(dt: float) -> void:
	var p := player.global_position
	if _last.x == INF:
		_last = p
	var air := player.st != Player.St.GROUND and player.st != Player.St.DIVE
	var mv := Vector2(p.x - _last.x, p.z - _last.z)
	var warp := _is_warp(mv, dt)           # 被传送 / 回出生点：不当成走着撞墙（招式突进不算，见 _is_warp）
	if not warp:
		# 1 头顶：楼板 / 洞顶 / 飞行上限
		var cap := minf(y_cap(Vector3(p.x, minf(p.y, _last.y), p.z)), y_cap(Vector3(_last.x, _last.y, _last.z)) + 6.0)
		if p.y > cap:
			p.y = cap
			if player.velocity.y > 0.0:
				player.velocity.y = 0.0
			ceil_bumps += 1 if _last.y < cap - 0.01 else 0
		# 2 墙：地上走两格以上、飞着一米以上的实心盒子 / 两格以上的崖壁
		if mv.length() > 0.0005:
			var np := _clip(Vector2(_last.x, _last.z), Vector2(p.x, p.z), minf(p.y, maxf(_last.y, p.y - 0.5)), air)
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
		# 3 地上走：缓坡
		if player.st == Player.St.GROUND:
			var h := _fl(p.x, p.z, p.y)
			if h - p.y <= STEP_UP:
				var he := _walk_h(p.x, p.z, h)
				var rise := he - p.y
				if (rise > 0.02 and rise <= STEP_UP and (player.is_on_floor() or rise < 0.6)) \
						or (rise < -0.02 and rise >= -STEP_UP and player.velocity.y <= 0.01 and (player.is_on_floor() or rise > -0.6)):
					p.y = he
					_floor.global_position = Vector3(p.x, he - 1.0, p.z)
	p = _clamp_bound(p)
	player.global_position = p
	_last = p


## 硬夹钳：当前这一层的 bound 矩形（藏在沙暴最浓处 / 洞窟岩壁里 / 研究所墙上）
func _clamp_bound(p: Vector3) -> Vector3:
	var b: Rect2 = ((map["layers"] as Dictionary)[layer_of(p)] as Dictionary)["bound"]
	var q := p
	q.x = clampf(p.x, b.position.x, b.end.x)
	q.z = clampf(p.z, b.position.y, b.end.y)
	if q.x != p.x:
		player.velocity.x = 0.0
	if q.z != p.z:
		player.velocity.z = 0.0
	return q


## 这一点对脚在 y 高度、正在 air（飞着 / 空战）的身体来说是不是墙
func _wall_at(q: Vector2, y: float, air: bool) -> bool:
	var h := world.height(q.x, q.y)
	if air:
		if h - y > TERR_LIFT:
			return true
		return world.solid_h(q.x, q.y, y + BODY_H - 0.05) - y > AIR_LIFT
	return _fl(q.x, q.y, y) - y > STEP_UP


## 从 from 挪到 to：途中撞墙就停在墙前，再试着只保留一个方向的位移（沿墙滑）。按身前 BODY_R 的点判
## 2026-11-24 F_maps（combat-8）：沿墙滑的那一段也一步步扫（_sweep）。原来只看滑到的终点在不在墙里：一帧挪得长（掉帧时的突进）
##   正面撞上薄墙时，「只留 z 方向」的终点就在墙那头、是空的，整段位移原样放行、穿墙过去。平常走 / 飞一帧挪不到墙厚，不受影响。
func _clip(from: Vector2, to: Vector2, y: float, air: bool) -> Vector2:
	var d := to - from
	if d.length() < 0.0005:
		return to
	if _wall_at(from, y, air):
		return to            # 已经在墙里（刚传过来 / 楼板落下来）：别把人卡死
	var at := _sweep(from, to, y, air)
	if at == to:
		return to
	var rest := to - at
	var sx := _sweep(at, Vector2(at.x + rest.x, at.y), y, air) if absf(rest.x) > 0.0005 else at
	var sz := _sweep(at, Vector2(at.x, at.y + rest.y), y, air) if absf(rest.y) > 0.0005 else at
	return sx if sx.distance_squared_to(at) >= sz.distance_squared_to(at) else sz


## 从 from 往 to 一步步（0.3 米）扫：身前 BODY_R 的点碰到墙就停在墙前（再二分四次贴近），一路没墙返回 to
func _sweep(from: Vector2, to: Vector2, y: float, air: bool) -> Vector2:
	var d := to - from
	var ln := d.length()
	if ln < 0.0005:
		return to
	var dn := d / ln
	var n := maxi(int(ceilf(ln / 0.3)), 1)
	var lo := 0.0
	var hit := -1.0
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		if _wall_at(from + d * t + dn * BODY_R, y, air):
			hit = t
			break
		lo = t
	if hit < 0.0:
		return to
	var hi := hit
	for k in 4:
		var mid := (lo + hi) * 0.5
		if _wall_at(from + d * mid + dn * BODY_R, y, air):
			hi = mid
		else:
			lo = mid
	return from + d * lo


## 脚在 y 高度的人在 (x, z) 踩在多高：地形 + 底面低于头顶的实心盒子（同 meadow_level._fl）
func _fl(x: float, z: float, y: float) -> float:
	var h := world.height(x, z)
	return maxf(h, world.solid_h(x, z, maxf(y, h) + BODY_HEAD))


## 主角自己脚下：地上同 _fl；飞着只接比脚面高不出 AIR_LIFT 的实心顶面（地形照算）
func _fl_own(p: Vector3) -> float:
	var h := world.height(p.x, p.z)
	var y := maxf(p.y, h)
	if player.st != Player.St.GROUND and player.st != Player.St.DIVE:
		return maxf(h, world.solid_h(p.x, p.z, y + AIR_LIFT, y + AIR_LIFT))
	return maxf(h, world.solid_h(p.x, p.z, y + BODY_HEAD))


func _solid_ramp(x: float, z: float, h0: float) -> float:
	var best := h0
	var lim := h0 + BODY_HEAD
	for dir: Vector2 in RAMP_DIRS:
		var prev := 0.0
		var r := 0.3
		while r <= RAMP_MAX + 0.01:
			var up: float = world.solid_h(x + dir.x * r, z + dir.y * r, lim) - h0
			if up > STEP_UP:
				break
			if up >= 0.05:
				var lo := prev
				var hi := r
				for k in 3:
					var mid := (lo + hi) * 0.5
					if float(world.solid_h(x + dir.x * mid, z + dir.y * mid, lim)) - h0 >= 0.05:
						hi = mid
					else:
						lo = mid
				var w := clampf(RAMP_MIN + RAMP_K * up, RAMP_MIN, RAMP_MAX)
				if hi < w:
					var t := 1.0 - hi / w
					best = maxf(best, h0 + up * t * t * (3.0 - 2.0 * t))
				break
			prev = r
			r += 0.3
	return best


## 带台阶缓坡的行走高度（同 meadow_level._walk_h）
func _walk_h(x: float, z: float, h0: float) -> float:
	var cs: float = BlockWorld.CELL
	var fx := fposmod(x, cs)
	var fz := fposmod(z, cs)
	var best := h0
	var ex: Array = [[fx, -1.0], [cs - fx, 1.0]]
	var ez: Array = [[fz, -1.0], [cs - fz, 1.0]]
	for a: Array in ex:
		if float(a[0]) < RAMP_MAX:
			best = maxf(best, _ramp(x + float(a[1]) * (float(a[0]) + 0.05), z, float(a[0]), h0))
	for b: Array in ez:
		if float(b[0]) < RAMP_MAX:
			best = maxf(best, _ramp(x, z + float(b[1]) * (float(b[0]) + 0.05), float(b[0]), h0))
	for a: Array in ex:
		for b: Array in ez:
			var d := Vector2(float(a[0]), float(b[0])).length()
			if d < RAMP_MAX:
				best = maxf(best, _ramp(x + float(a[1]) * (float(a[0]) + 0.05), z + float(b[1]) * (float(b[0]) + 0.05), d, h0))
	if world.solid_any(x, z, RAMP_MAX):
		best = maxf(best, _solid_ramp(x, z, h0))
	return best


func _ramp(nx: float, nz: float, d: float, h0: float) -> float:
	var up := _fl(nx, nz, h0) - h0
	if up < 0.05 or up > STEP_UP:
		return h0
	var w := clampf(RAMP_MIN + RAMP_K * up, RAMP_MIN, RAMP_MAX)
	if d >= w:
		return h0
	var t := 1.0 - d / w
	return h0 + up * t * t * (3.0 - 2.0 * t)


func _jump_reach(y: float) -> float:
	var vy := maxf(player.velocity.y, 0.0)
	return y + vy * vy / (2.0 * Player.GRAVITY)


func _physics_process(dt: float) -> void:
	if _tp_busy:
		return
	var p := player.global_position
	var h := _fl_own(p)
	_bump_t -= dt
	var air := player.st != Player.St.GROUND and player.st != Player.St.DIVE
	var warped := _last_phys.x == INF or Vector2(p.x, p.z).distance_to(_last_phys) > 4.0
	if air:
		# 飞着：脚下的地形 / 箱顶在托举范围内就托上去（墙在渲染帧里已经挡住了）
		if h > p.y + 0.02:
			player.global_position.y = h
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
	elif player.st == Player.St.GROUND and not warped:
		if h - p.y > STEP_UP:
			# 跳起来了、再升一点就够得着沿：贴着墙翻上去（同 meadow_level）
			var hb2 := _fl(_last_phys.x, _last_phys.y, p.y)
			if not player.is_on_floor() and hb2 - p.y <= STEP_UP and h - p.y <= STEP_UP * 2.0 and player.velocity.y > -6.0 \
					and _jump_reach(p.y) >= h - STEP_UP and p.y + BODY_H + 0.5 < y_cap(p) + BODY_H:
				player.global_position.x = _last_phys.x
				player.global_position.z = _last_phys.y
				var my := p.y + MANTLE_SPD * dt
				player.global_position.y = my
				player.velocity.y = maxf(player.velocity.y, 0.0)
				_floor.global_position = Vector3(_last_phys.x, minf(hb2, my) - 1.0, _last_phys.y)
				_last_phys = Vector2(player.global_position.x, player.global_position.z)
				_last = player.global_position
				_hazards(dt)
				return
			var np := _clip(_last_phys, Vector2(p.x, p.z), p.y, false)
			player.global_position.x = np.x
			player.global_position.z = np.y
			p = player.global_position
			h = _fl_own(p)
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
	if p.y < h - 0.05:
		player.global_position.y = h
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	_last_phys = Vector2(player.global_position.x, player.global_position.z)
	_floor.global_position = Vector3(_last_phys.x, h - 1.0, _last_phys.y)
	_hazards(dt)
	_clamp_mobs()


## 镜头之后：洞窟里镜头别钻到洞顶上面（看到岩体顶面）
func _late_process(_dt: float) -> void:
	if layer != "cavern" or _tp_busy:
		return
	var cp := cam.global_position
	var top := world.ceil_at(cp.x, cp.z) - 0.6
	if cp.y > top:
		cam.global_position.y = maxf(top, player.global_position.y + 0.8)


## 洞窟里的怪也夹在洞顶下面（extract_manager 的 _mobs 里有的才管）
func _clamp_mobs() -> void:
	if raid == null or layer != "cavern":
		return
	var mobs: Variant = raid.get("_mobs")
	if not (mobs is Array):
		return
	for m: Variant in mobs:
		if is_instance_valid(m) and m is Node3D:      # 2026-11-24 I_int：先看在不在（怪死了还留在 _mobs 里时，`is` 碰到已释放的会报错）
			var n3 := m as Node3D
			var top := world.ceil_at(n3.global_position.x, n3.global_position.z) - 3.0
			if n3.global_position.y > top:
				n3.global_position.y = top


# ---------- 镜头 ----------

## 镜头不低于地形（不算建筑：建筑由 occl 管）
func _cam_floor(x: float, z: float) -> float:
	return world.height(x, z)


## 挡镜头的最高处：地形 + 底面低于主角头顶的实心盒子（墙）。主角所在那栋楼的屋顶 / 楼板底面都在头顶以上，不算
func _cam_occl(x: float, z: float) -> float:
	var h := world.height(x, z)
	return maxf(h, world.solid_h(x, z, player.global_position.y + 2.2))


# ---------- 边界 / 进出洞窟 ----------

func _storm_dir() -> Vector3:
	var p := player.global_position
	var pl: Rect2 = ((map["layers"] as Dictionary)["surface"] as Dictionary)["play"]
	var c := pl.get_center()
	return Vector3(c.x - p.x, 0.0, c.y - p.z).normalized()


func _hazards(dt: float) -> void:
	var p := player.global_position
	_hurt_t -= dt
	_tip_t -= dt
	# 进出洞窟
	if _tp_cool <= 0.0:
		for lk: Dictionary in teleport_links:
			for end: String in ["a", "b"]:
				var q: Vector3 = lk[end]
				if layer_of(q) != layer:
					continue
				if Vector2(p.x - q.x, p.z - q.z).length() < float(lk["r"]) and absf(p.y - q.y) < 4.0:
					_teleport(lk, end == "a")
					return
	_storm_k = 0.0
	if layer != "surface":
		return
	if map_id == "desert":
		var pl: Rect2 = ((map["layers"] as Dictionary)["surface"] as Dictionary)["play"]
		var st: Dictionary = map["storm"]
		var e := maxf(absf(p.x - pl.get_center().x) - pl.size.x * 0.5, absf(p.z - pl.get_center().y) - pl.size.y * 0.5)
		var k := smoothstep(float(st["in"]), float(st["full"]), e)
		_storm_k = k
		if k > 0.0:
			# 越往里推力越大：直接往回挪（不跟主角自己的速度打架），朝外的速度削掉
			var inward := Vector3(pl.get_center().x - p.x, 0.0, pl.get_center().y - p.z).normalized()
			var push := float(st["push"]) * (k * 0.6 + k * k * 0.4) * dt
			player.global_position += inward * push
			var vo := player.velocity.dot(-inward)
			if vo > 0.0:
				player.velocity += inward * vo * minf(k * 2.6, 1.0)
			if k > 0.08 and _hurt_t <= 0.0:
				_hurt_t = 1.0
				_env_hurt(float(st["dps"]))
			if k > 0.15 and _tip_t <= 0.0:
				_tip_t = 7.0
				say("风沙太烈，寸步难行")
			hazard.emit("sand", k)
	else:
		var wl: Dictionary = map["wall"]
		var e2 := maxf(absf(p.x), absf(p.z))
		var bar: float = wl["barrier"]
		if e2 > bar and p.y > float(wl["top"]) - 1.5:
			# 禁制光幕：弹回墙里
			var ax := absf(p.x) >= absf(p.z)
			if ax:
				player.global_position.x = signf(p.x) * (bar - 0.6)
				player.velocity.x = -signf(p.x) * 9.0
			else:
				player.global_position.z = signf(p.z) * (bar - 0.6)
				player.velocity.z = -signf(p.z) * 9.0
			_last = player.global_position
			if _tip_t <= 0.0:
				_tip_t = 6.0
				say("禁制光幕：此路不通")
			hazard.emit("barrier", 1.0)
		elif e2 > float(wl["out"]) and p.y < float(wl["top"]) - 12.0:
			# 掉进墙外的深谷：送回最近的墙内
			var q2 := Vector3(clampf(p.x, -388.0, 388.0), 0.0, clampf(p.z, -388.0, 388.0))
			q2.y = floor_at(q2.x, q2.z) + 0.3
			player.global_position = q2
			player.velocity = Vector3.ZERO
			_last = q2
			_last_phys = Vector2(q2.x, q2.z)
			say("跌入深谷，被禁制送回园中")
			hazard.emit("chasm", 1.0)


func _env_hurt(pts: float) -> void:
	storm_hurt += pts
	if raid != null and raid.has_method("env_damage"):
		raid.call("env_damage", pts, "sand")
	elif player.melee != null:
		player.melee.hp = maxf(player.melee.hp - pts, 1.0)


## 走进洞口 / 光井：黑场 0.2 秒 → 传到另一头 → 等脚下的地块 → 亮回来
func _teleport(lk: Dictionary, down: bool) -> void:
	_tp_busy = true
	var ui: Variant = _main_ui()
	if ui != null:
		await ui.fade(1.0, TP_FADE)
	var to: Vector3 = lk["b_out"] if down else lk["a_out"]
	var yaw: float = lk["b_yaw"] if down else lk["a_yaw"]
	to.y = floor_at(to.x, to.z, to.y + 1.0) + 0.05
	var nl := layer_of(to)
	player.force_ground()
	player.global_position = to
	player.velocity = Vector3.ZERO
	player.face_now(yaw)
	cam.snap(yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
	_set_layer(nl)
	_last = to
	_last_phys = Vector2(to.x, to.z)
	_floor.global_position = to - Vector3(0, 1.05, 0)
	player.ground_ref = to.y
	teleports += 1
	var t := 0.0
	var lim := 6.0 if world.sliced() else 2.5
	if world.sliced():
		world.slice_us = 30000
	while t < lim and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
		player.global_position = to
		player.velocity = Vector3.ZERO
		if world.ready_near(to):
			break
	if world.sliced():
		world.slice_us = world.SLICE_US
	_tp_cool = 1.2
	_tp_busy = false
	if ui != null and is_inside_tree():
		await ui.fade(0.0, TP_FADE)


## 直接换层（进出洞窟）：方块世界只排这一层的块、天色一下到位
func _set_layer(nl: String) -> void:
	if nl == layer:
		return
	layer = nl
	world.set_layer(nl)
	_storm_k = 0.0
	_apply_atmo(0.0, true)
	layer_changed.emit(nl)


func _main_ui() -> Variant:
	var m: Node = player.get_parent()
	if m == null or bool(m.get("_switching")):
		return null
	var ui: Variant = m.get("level_ui")
	if ui != null and (ui as Object).has_method("fade"):
		return ui
	return null


# ---------- 界面：F3 统计、提示、小地图底图、大地图 ----------

func _build_motes() -> void:
	motes = CPUParticles3D.new()
	motes.amount = 40 if mobile else 80
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(34.0, 9.0, 34.0)
	motes.direction = Vector3(0.4, 0.5, 0.2)
	motes.spread = 60.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.3
	motes.initial_velocity_max = 1.4
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.0))
	sc.add_point(Vector2(0.15, 1.0))
	sc.add_point(Vector2(0.8, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	motes.scale_amount_curve = sc
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.16
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(2.4, 2.4, 2.4)
	mm.vertex_color_use_as_albedo = true
	bm.material = mm
	motes.mesh = bm
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)


func _build_ui() -> void:
	var layer_ui := CanvasLayer.new()
	layer_ui.layer = 4
	add_child(layer_ui)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	_stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_stats.add_theme_constant_override("outline_size", 4)
	if font != null:
		_stats.add_theme_font_override("font", font)
	_stats.visible = false
	layer_ui.add_child(_stats)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26 if mobile else 22)
	_toast.add_theme_color_override("font_color", UiStyle.TEXT)
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_font_override("font", font if font != null else UiStyle.kai())
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_ui.add_child(_toast)


## 一行提示：有玩法管理器就走它的 hud.toast，没有就用关卡自己的
func say(text: String, col := Color(1.0, 0.86, 0.62)) -> void:
	if raid != null:
		var h: Variant = raid.get("hud")
		if h != null and is_instance_valid(h) and (h as Object).has_method("toast"):
			h.call("toast", text, col)
			return
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.reset_size()
	_toast_t = 2.6


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_F3:
			_stats.visible = not _stats.visible
		elif k == KEY_M:
			if _big != null:
				close_big_map()
			else:
				open_big_map()


## 两层的整图底图各烘一张（手机 / 网页 4 米一像素，桌面 3 米）
func _bake_maps() -> void:
	var lite := mobile or world.sliced()
	for ln: String in ["surface", "cavern"]:
		var b: Dictionary = world.bake_map(ln, 4.0 if lite else 3.0)
		b["tex"] = ImageTexture.create_from_image(b["img"])
		_maps[ln] = b


## 小地图的固定底图（minimap.gd 的固定底图模式调）：p 所在那一层的 {tex, center, span, layer}
func map_tex(p: Vector3) -> Dictionary:
	var ln := layer_of(p)
	var b: Dictionary = _maps[ln]
	return {"tex": b["tex"], "center": b["center"], "span": b["span"], "layer": ln}


func map_tex_layer(ln: String) -> Dictionary:
	var b: Dictionary = _maps[ln]
	return {"tex": b["tex"], "center": b["center"], "span": b["span"], "layer": ln}


## 大地图上要画的点（minimap.gd 的大地图 / 自检都用）：[[世界坐标, 种类, 名字], ...]
## 种类：extract 撤离点、key 钥匙房（open = 门开着）、boss、link 洞口 / 光井、poi 地名、doctor 天工师
func map_marks(ln: String) -> Array:
	var out: Array = []
	for e: Dictionary in map["extracts"]:
		if str(e["layer"]) == ln:
			out.append([e["pos"], "extract", str(e["id"])])
	for kr: Dictionary in map["key_rooms"]:
		if str(kr["layer"]) == ln:
			out.append([kr["door"], "key_open" if world.door_open(str(kr["id"])) else "key", str(kr["num"])])
	for bo: Dictionary in map["bosses"]:
		if str(bo["layer"]) == ln:
			out.append([bo["pos"], "boss", str(bo["name"])])
	for lk: Dictionary in map["links"]:
		out.append([lk["a"] if ln == "surface" else lk["b"], "link", str(lk["id"])])
	for po: Dictionary in map.get("pois", []):
		if str(po["layer"]) == ln and str(po["kind"]) != "boss":
			out.append([po["pos"], "poi", str(po["name"])])
	return out


## 全屏大地图（点小地图 / 按 M）：撤离点、钥匙房、Boss、洞口、队友、自己。不暂停（搜打撤里地图开着照样会挨打）
## 2026-11-24 F_maps（review uxperf-1）：重伤倒地 / 陨落 / 结算页 / 储物袋开着时不开（它们都要点自己的按钮，大地图在层 30 会盖住）；
##   开着的时候进了这几种状态，_tick_big_map 当帧就关掉，且不把鼠标抓回去。
func open_big_map() -> void:
	if _big != null or _map_blocked():
		return
	_big = CanvasLayer.new()
	_big.layer = 30
	_big.name = "BigMap"
	add_child(_big)
	var bm: Control = Minimap.BigMap.new()
	bm.set("level", self)
	bm.set("font", font if font != null else UiStyle.kai())
	bm.set("mobile", mobile)
	bm.closed.connect(close_big_map)
	_big.add_child(bm)
	_bigc = bm
	_big_3d_off = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_block_touch()


## recapture = 关图后照镜头的设置把鼠标抓回去（桌面）。重伤 / 结算 / 储物袋开着时不抓（要点按钮）
func close_big_map(recapture := true) -> void:
	if _big == null:
		return
	_big.queue_free()
	_big = null
	_bigc = null
	if _big_3d_off:
		_big_3d_off = false
		get_viewport().disable_3d = _big_3d_was
	if recapture and cam != null and cam.capture_mouse and is_inside_tree() and not _map_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func big_map_open() -> bool:
	return _big != null


## 现在不该开着大地图：重伤倒地 / 陨落 / 结算页 / 储物袋（manager 的字段鸭子类型地问，没有就跳过）
func _map_blocked() -> bool:
	if player != null and (player.dead or player.is_downed()):
		return true
	if raid == null or not is_instance_valid(raid):
		return false
	var dn: Variant = raid.get("downed")
	if dn is bool and dn:
		return true
	var res: Variant = raid.get("result")
	if res is Dictionary and not (res as Dictionary).is_empty():
		return true
	var h: Variant = raid.get("hud")
	return h != null and is_instance_valid(h) and (h as Object).has_method("bag_open") and bool(h.call("bag_open"))


## 大地图开着时每帧（_process，主角 / main 之后）：
## · 进了重伤 / 结算 / 储物袋 → 关掉（uxperf-1）
## · 触屏层让出触摸（uxperf-2）：不然点地图会同时按到底下的摇杆 / 转镜头 / 技能键，点地图外面合上时还会出招
## · 面板盖严之后关掉 3D 渲染（I_int §6：大地图开着时网页档绘制调用 264~277；地图外面是不透明的墨色底，3D 画了也看不见），关图还原
func _tick_big_map() -> void:
	if _map_blocked():
		close_big_map()
		return
	_block_touch()
	if not _big_3d_off and _bigc != null and float(_bigc.get("cover")) >= 1.0:
		var vp := get_viewport()
		_big_3d_was = vp.disable_3d
		vp.disable_3d = true
		_big_3d_off = true


## main.gd 每帧按 _level_bag_open() 重写 touch.blocked（主角之前、关卡之前），这里在它之后补成 true：
## 触屏层见到 blocked 就把按着的摇杆 / 按钮都松开、不再接管触摸，大地图照样收得到系统模拟的鼠标点击（同储物袋开着时）。
## 交叉请求：main._level_bag_open() 也问 level.big_map_open()，那样就只剩一个写的人；这里写 true 和它不冲突。
func _block_touch() -> void:
	var m: Node = player.get_parent() if player != null else null
	if m == null:
		return
	var tc: Variant = m.get("touch")
	if tc != null and is_instance_valid(tc):
		(tc as Object).set("blocked", true)


## 大地图上画队友 / 别人用（没有管理器时只有自己）
func mates() -> Array:
	var out: Array = []
	if raid != null:
		var al: Variant = raid.get("_allies")
		if al is Array:
			for a: Variant in al:
				if is_instance_valid(a) and a is Node3D:      # 先看在不在（AI 道友死了还留在 _allies 里时，`is` 碰到已释放的会报错）
					out.append((a as Node3D).global_position)
	if net != null and bool(net.get("active")):
		var rm: Variant = net.get("remotes")
		if rm is Dictionary:
			for r: Variant in (rm as Dictionary).values():
				if is_instance_valid(r) and r is Node3D and bool((r as Object).get("mate")):
					out.append((r as Node3D).global_position)
	return out
