extends Node
## 新图的截图 / 走位自检（2026-11-24，SPEC 第 9 节 W）：`-- --level-shot=desert|lab [--rendering-method gl_compatibility --touch]`。
## main.gd 见到参数就 load 这个脚本、设 m（main）和 arg（图 id）。正常开机到主城 → 单人进图 → 依次：
##   出生点 / 全图俯瞰 / 主地标（金字塔 · 天工楼）/ 楼里（屋顶藏起来）/ 洞窟（走进洞口传下去、走进光井传回来）/ 边界（沙暴推回 · 禁制光幕弹回）/
##   夜景 / 全屏大地图，每张打印绘制调用、图元、地块数（[lvshot] 开头）；楼里撞墙 / 撞顶、边界推不出去也各测一遍（[lvshot] TEST 行）。
## 最后导出主角周围的网格（_shots/lvshot/geo_*.bin，给 _tasks/look_20261123/zfight.py 查 z-fighting），回主城，退出。
## 截图：_shots/lvshot_<图>_<名>[_gl].png + _shots/preview/ 同名 .jpg（只看 preview 的 jpg）。故意不写 class_name。

const MapDef := preload("res://scripts/ex/map_def.gd")
const Minimap := preload("res://scripts/minimap.gd")

var m: Node
var arg := ""
var level: Node3D
var world: Node3D
var player: Player
var cam: CameraRig
var gl := false
var fails := 0
var _mini: Control
var _mgr: Node3D


## 给小地图用的假管理器（没有 extract_manager 时）：小地图只读 player / cam / level
class FakeMgr extends Node3D:
	var player: Node3D
	var cam: Node3D
	var level: Node3D
	var net: Node


func _ready() -> void:
	gl = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var c: Node = m.get("cam")
	if c != null:
		c.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if arg == "":
		arg = "desert"
	_run()


func say(s: String) -> void:
	print("[lvshot] " + s)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	say("TEST %s %s · %s" % [name, "PASS" if ok else "FAIL", detail])


func shot(tag: String) -> void:
	var full := "lvshot_%s_%s%s" % [arg, tag, "_gl" if gl else ""]
	# 量一秒：帧率、绘制调用、图元（取最后一帧）
	var n0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await wait(1.0)
	var fps := float(Engine.get_frames_drawn() - n0) * 1000.0 / float(maxi(Time.get_ticks_msec() - t0, 1))
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if DisplayServer.get_name() != "headless":
		await m.call("_shot", full)      # --headless 没有渲染、frame_post_draw 不来：不截图，走位 / 规则自检照跑（绘制数是 0）
	var maxv := 0
	for k: Vector2i in world.get("_chunks"):
		var e: Dictionary = (world.get("_chunks") as Dictionary)[k]
		if int(e["lod"]) == 0:
			var mi: MeshInstance3D = e["node"]
			if mi != null and mi.mesh != null:
				maxv = maxi(maxv, mi.mesh.surface_get_array_len(0))
	var p := player.global_position
	say("%s fps %.0f draw %d prim %dk chunks %d lod0 %d (max %dk verts) far %d roofs_hidden %d layer %s pos (%.0f, %.1f, %.0f)%s" % [
			tag, fps, dc, prim / 1000, world.chunk_count(), world.lod0_count(), maxv / 1000, world.far_count(), world.roofs_hidden(),
			level.layer, p.x, p.y, p.z, "  OVER-BUDGET" if dc > 220 or prim > 220000 or maxv > 60000 else ""])


## 把主角放到 p（贴地），面朝 yaw；镜头跟上
func put(p: Vector3, yaw := 0.0, pitch := CameraRig.PITCH_DEFAULT, zoom := CameraRig.ZOOM_DEFAULT) -> void:
	player.force_ground()
	var y: float = level.call("floor_at", p.x, p.z, p.y + 1.0)
	player.global_position = Vector3(p.x, y + 0.05, p.z)
	player.velocity = Vector3.ZERO
	player.face_now(yaw)
	cam.snap(yaw, pitch, zoom)
	await frames(2)


func settle(sec := 1.2) -> void:
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if world.ready_near(player.global_position) and t > sec:
			break


func cine(at: Vector3, look: Vector3, fov := 60.0) -> void:
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		attr.dof_blur_far_enabled = false     # 俯瞰图：远景不虚化
	cam.set("cine_xf", Transform3D(Basis.looking_at((look - at).normalized(), Vector3.UP), at))
	cam.set("cine_fov", fov)
	cam.set("cine_k", 1.0)
	await frames(3)


func cine_off() -> void:
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		attr.dof_blur_far_enabled = not bool(level.get("mobile"))
	cam.set("cine_k", 0.0)
	await frames(2)


## 按住前进 sec 秒（镜头朝 yaw）；返回 [最远走到哪, 一路最高到多高]
func walk(yaw: float, sec: float, sprint := false) -> Array:
	cam.snap(yaw, -0.2, CameraRig.ZOOM_DEFAULT)
	await frames(2)
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	var top := -1.0e9
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await wait(0.25)
	return [player.global_position, top]


## 起飞（空战腾空：同地上按跳）
func take_off() -> void:
	await frames(2)
	var ok: bool = player.take_air()
	if not ok:
		ok = player.enter_air_combat()
	await wait(0.6)
	say("起飞 %s 状态 %d y %.1f" % [ok, player.st, player.global_position.y])


## 空中镜头朝天、按住前进 sec 秒（飞行方向跟镜头，抬头 = 往上飞），返回最高到过多高
func rise(sec: float) -> float:
	var top := -1.0e9
	cam.snap(cam.yaw, 1.25, CameraRig.ZOOM_DEFAULT)
	await frames(2)
	Input.action_press("move_forward")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	cam.snap(cam.yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
	return top


func _mini_setup() -> void:
	var raid: Variant = level.get("raid")
	var cl := CanvasLayer.new()
	cl.layer = 6
	level.add_child(cl)
	_mini = Minimap.new()
	if raid != null and is_instance_valid(raid) and (raid as Node).get("player") != null:
		_mini.set("mgr", raid)
	else:
		_mgr = FakeMgr.new()
		_mgr.player = player
		_mgr.cam = cam
		_mgr.level = level
		level.add_child(_mgr)
		_mini.set("mgr", _mgr)
	_mini.set("font", m.get("font"))
	_mini.position = Vector2(get_viewport().get_visible_rect().size.x - 214.0, 24.0)
	cl.add_child(_mini)


func _run() -> void:
	await wait(1.5)
	m.get("level_ui").set("mode", "solo")
	var t0 := Time.get_ticks_msec()
	# 2026-11-25 主干解耦：新图元婴才能进（ex_level 境界守卫），自检里先升到元婴
	(m.get("player") as Node).call("set_realm", 3, false)
	await m.call("_enter_level", arg)
	while bool(m.get("_switching")):
		await get_tree().process_frame
	level = m.get("level")
	if level == null:
		say("FAIL 进不了图 " + arg)
		get_tree().quit(1)
		return
	world = level.get("world")
	player = m.get("player")
	cam = m.get("cam")
	var mp: Dictionary = level.get("map")
	say("进图 %s（%s）%d ms · 出生 %s · %s" % [arg, mp["name"], Time.get_ticks_msec() - t0, player.global_position, level.call("stats_text")])
	say("点表：出生 %d 撤离 %d 箱子 %d 刷怪点 %d 钥匙房 %d Boss %d 洞口 %d 楼 %d" % [level.call("points", "spawn").size(),
			level.call("points", "extract").size(), level.call("points", "box").size(), level.call("points", "camp").size(),
			level.call("points", "key_room").size(), level.call("points", "boss").size(), level.call("points", "link").size(),
			level.call("points", "building").size()])
	_mini_setup()
	await settle(1.5)
	await shot("spawn")
	if arg == "lab":
		await _lab()
	else:
		await _desert()
	await _dump_geo()
	say("自检结束：失败 %d 项" % fails)
	m.call("_return_to_hall")
	var tw := 0.0
	while m.get("level") != null and tw < 20.0:
		await get_tree().process_frame
		tw += get_process_delta_time()
	await wait(1.0)
	say("回到主城：level=%s" % [m.get("level")])
	get_tree().quit(0 if fails == 0 else 2)


# ---------- 沙海古墟 ----------

func _desert() -> void:
	var py: Dictionary = (level.get("map") as Dictionary)["pyramid"]
	var pc: Vector2 = py["c"]
	# 全图俯瞰：主角站在塔顶，镜头在塔南面高处往北看
	await put(Vector3(pc.x, 40, pc.y), 0.0)
	await settle(2.0)
	await cine(Vector3(pc.x + 40.0, 230.0, pc.y + 330.0), Vector3(pc.x, 30.0, pc.y - 60.0), 62.0)
	await wait(1.5)
	await shot("overview")
	await cine_off()
	# 金字塔：从南面石阶脚下仰看
	await put(Vector3(pc.x, 20, pc.y + 75.0), 0.0, -0.05, 11.0)
	await settle(1.0)
	await shot("pyramid")
	# 爬金字塔石阶（一米一级的台阶要走得上去）
	var r: Array = await walk(0.0, 7.0, true)
	var top_y: float = (r[0] as Vector3).y
	check("climb_pyramid", top_y > 30.0, "沿南面石阶走 7 秒，到了 y=%.1f（塔顶 38）" % top_y)
	# 塔顶的 Boss 台
	await put(Vector3(pc.x + 8.0, 40, pc.y + 14.0), PI * 0.8, -0.35, 9.0)
	await settle(0.8)
	await shot("pyramid_top")
	# 撞墙：塔的退台三米一级，走着上不去
	await put(Vector3(pc.x + 40.0, 20, pc.y + 66.0), PI, -0.2)
	var z0 := player.global_position.z
	r = await walk(0.0, 3.0)
	var pw: Vector3 = r[0]
	check("wall_tier", pw.y < 25.0, "朝退台（非石阶处）走 3 秒：y %.1f（地面 20、第一级 23）z %.1f → %.1f" % [pw.y, z0, pw.z])
	# 进洞：走进 U1 坑底的洞口 → 传到洞窟
	var lk: Dictionary = _link("U1")
	var a: Vector3 = lk["a"]
	await put(a + Vector3(0, 0, 5.0), 0.0)
	var t := 0.0
	while level.get("layer") != "cavern" and t < 5.0:
		await walk(0.0, 0.4)
		t += 0.4
	await settle(1.0)
	check("tp_down", level.get("layer") == "cavern", "走进 U1 洞口 → 层 %s，位置 %s" % [level.get("layer"), player.global_position])
	await shot("cavern")
	# 洞窟里撞顶：起飞、一直往上
	await take_off()
	var top := await rise(2.5)
	var cap: float = world.call("ceil_at", player.global_position.x, player.global_position.z)
	check("cave_ceiling", top <= cap - 1.9, "洞里起飞按住上升 2.5 秒：最高 %.1f，洞顶 %.1f" % [top, cap])
	# 钥匙房 11：开门、进去看
	level.call("set_door", "k11", true)
	await wait(0.8)
	var kr: Dictionary = _kroom("k11")
	var room: AABB = kr["room"]
	await put(room.get_center() + Vector3(4.0, 0, 0), -PI * 0.5, -0.3, 7.0)
	await settle(0.8)
	await shot("keyroom")
	# 关门后从外面撞门
	level.call("set_door", "k11", false)
	await wait(0.8)
	var door: Vector3 = kr["door"]
	await put(door + Vector3(6.0, 0, 0), -PI * 0.5)
	r = await walk(-PI * 0.5 + PI, 2.0)
	check("door_blocks", (r[0] as Vector3).x > door.x + 0.2, "门关着朝门走 2 秒：x %.1f（门在 %.1f）" % [(r[0] as Vector3).x, door.x])
	# 沙虫竞技场
	var wb: Dictionary = _boss("worm")
	var ar: AABB = wb["arena"]
	await put(ar.get_center() + Vector3(-10.0, 0, 40.0), 0.25, -0.25, 12.0)
	await settle(0.8)
	await shot("worm_arena")
	# 回地面：走进 U1 的光井
	var b: Vector3 = lk["b"]
	await put(b + Vector3(6.0, 0, 0), -PI * 0.5)
	await frames(2)
	t = 0.0
	while level.get("layer") != "surface" and t < 5.0:
		await walk(PI * 0.5 * -1.0 + PI, 0.4)
		t += 0.4
	await settle(1.0)
	check("tp_up", level.get("layer") == "surface", "走进 U1 光井 → 层 %s，位置 %s" % [level.get("layer"), player.global_position])
	# 沙暴：从南面崖缺口走出去
	var hp0: float = player.melee.hp
	await put(Vector3(-120.0, 20, 352.0), PI)
	r = await walk(PI, 9.0, true)
	var ps: Vector3 = r[0]
	var bound: Rect2 = ((level.get("map") as Dictionary)["layers"]["surface"] as Dictionary)["bound"]
	check("storm_push", ps.z < bound.end.y - 0.5, "朝南冲进沙暴 9 秒：停在 z %.1f（硬边界 %.0f，沙暴从 %.0f 起）掉血 %.0f" % [ps.z, bound.end.y, 346.0 + 30.0, hp0 - player.melee.hp])
	await shot("storm")
	# 飞着往外冲：也推得回来
	await take_off()
	cam.snap(PI, -0.05, CameraRig.ZOOM_DEFAULT)
	r = await walk(PI, 5.0, true)
	check("storm_fly", (r[0] as Vector3).z < bound.end.y - 0.5, "飞着往南冲 5 秒：z %.1f" % (r[0] as Vector3).z)
	# 夜景：时钟拨到夜里
	level.set("clock_off", 600.0 - float(level.call("room_time")) + 30.0)
	await put(Vector3(pc.x + 30.0, 20, pc.y + 90.0), PI * 0.1 - 0.4, -0.12, 10.0)
	# review gap-desert-night：沙漠夜里也加刷（map_def 的 horde，管理器的 _horde 照点表刷）。计时拨到马上
	var mgr: Node = level.get("raid")
	var h0 := -1
	if mgr != null and is_instance_valid(mgr) and mgr.get("stat") is Dictionary:
		h0 = int((mgr.get("stat") as Dictionary).get("horde", 0))
		mgr.set("_horde_t", 0.1)
	await wait(3.0)
	check("night", bool(level.call("is_night")), "拨钟后 is_night=%s day_phase=%.0f" % [level.call("is_night"), level.call("day_phase")])
	await shot("night")
	if h0 >= 0:
		var h1 := int((mgr.get("stat") as Dictionary).get("horde", 0))
		var kinds: Array = []
		for mm: Variant in (mgr.get("_mobs") as Array):
			if is_instance_valid(mm) and (mm as Node).has_meta("horde"):
				kinds.append(str((mm as Node).get_meta("ex_id", "?")))
		check("desert_horde", h1 > h0 and h1 - h0 <= 3, "入夜加刷 %d 只 %s（每波 2~3 只，points(\"horde\") 有 %d 项）" % [h1 - h0, kinds, level.call("points", "horde").size()])
		var mobs: Array = mgr.get("_mobs")
		for i in range(mobs.size() - 1, -1, -1):
			var mm2: Variant = mobs[i]
			if is_instance_valid(mm2) and (mm2 as Node).has_meta("horde"):
				(mm2 as Node).queue_free()
				mobs.remove_at(i)
	level.set("clock_off", 0.0)
	await wait(0.5)
	await _bigmap()


# ---------- 天工秘所 ----------

func _lab() -> void:
	# 全图俯瞰：主角在天工楼院子里，镜头从南面高处看
	await put(Vector3(2.0, 50, 50.0), 0.0)
	await settle(2.0)
	await cine(Vector3(60.0, 240.0, 380.0), Vector3(0.0, 40.0, -60.0), 62.0)
	await wait(1.5)
	await shot("overview")
	await cine_off()
	# 天工楼正门
	await put(Vector3(4.0, 50, 46.0), 0.0, -0.08, 11.0)
	await settle(1.0)
	await shot("hall")
	# 走进楼里：屋顶 / 二层楼板要藏起来
	await put(Vector3(10.0, 50, 20.0), PI * 0.2, -0.35, 8.0)
	await frames(4)
	var hid: int = world.call("roofs_hidden")
	check("roof_hide", hid >= 1, "进天工楼一层：藏起来的屋顶 / 楼板 %d 块" % hid)
	await settle(0.6)
	await shot("inside")
	# 撞墙：朝西墙走 3 秒
	await put(Vector3(-20.0, 50, 0.0), PI * 0.5)
	var r: Array = await walk(PI * 0.5, 3.0)
	var pw: Vector3 = r[0]
	check("wall_walk", pw.x > -29.2 + 0.3, "楼里朝西墙走 3 秒：x %.2f（墙里侧 -29.2）" % pw.x)
	# 飞着撞墙：起飞后朝北墙飞 3 秒（二层楼板底下）
	await put(Vector3(-10.0, 50, 4.0), 0.0)
	await take_off()
	r = await walk(0.0, 3.0)
	var pf: Vector3 = r[0]
	check("wall_fly", pf.z > -19.2 + 0.3, "楼里飞着朝北墙冲 3 秒：z %.2f（墙里侧 -19.2）y %.1f" % [pf.z, pf.y])
	_lunge_wall(pf, -19.2)
	# 撞顶：二层楼板（底面 55）底下起飞、按住上升
	await put(Vector3(-10.0, 50, -2.0), 0.0)
	await take_off()
	var top := await rise(2.0)
	check("ceil_fly", top <= 55.0 - 2.0, "二层楼板底下起飞上升 2 秒：最高 %.2f（楼板底 55，头顶夹到 %.1f）" % [top, 55.0 - 2.1])
	# 上楼：楼梯走上二层（天工师的房间）
	await put(Vector3(22.0, 50, 21.0), 0.0)
	r = await walk(0.0, 4.0)
	check("stairs", (r[0] as Vector3).y > 54.5, "沿楼梯往上走 4 秒：到了 y %.2f（二层 55.5）" % (r[0] as Vector3).y)
	await shot("upstairs")
	# 钥匙房 K1：开门进去
	level.call("set_door", "K1", true)
	await wait(0.8)
	var kr: Dictionary = _kroom("K1")
	var room: AABB = kr["room"]
	await put(room.get_center() + Vector3(-6.0, 0, 0), PI * 0.5, -0.4, 7.0)
	await settle(0.6)
	check("pit_roof", int(world.call("roofs_hidden")) >= 1, "进钥匙房 1：盖板藏起来 %d" % world.call("roofs_hidden"))
	await shot("keyroom")
	# 楼梯口 u3 → 地下室
	var lk: Dictionary = _link("u3")
	var a: Vector3 = lk["a"]
	var cc: Vector3 = lk["center"]
	var f: Vector3 = lk["f"]
	await put(cc + f * 3.5, MapDef.yaw_of(-f))
	var t := 0.0
	while level.get("layer") != "cavern" and t < 6.0:
		await walk(MapDef.yaw_of(-f), 0.4)
		t += 0.4
	await settle(1.0)
	check("tp_down", level.get("layer") == "cavern", "走下 u3 梯井 → 层 %s，位置 %s（触发点 %s）" % [level.get("layer"), player.global_position, a])
	var bo: Dictionary = _boss("lingying")
	var ar: AABB = bo["arena"]
	await put(ar.get_center() + Vector3(0, 0, 24.0), 0.0, -0.3, 10.0)
	await settle(0.8)
	await shot("cavern")
	await take_off()
	var top2 := await rise(2.5)
	check("cave_ceiling", top2 <= 28.0 - 1.9, "地下室起飞上升 2.5 秒：最高 %.1f（洞顶 28）" % top2)
	var b: Vector3 = lk["b"]
	var bd: Vector3 = (lk["b_out"] as Vector3) - b
	await put(lk["b_out"], MapDef.yaw_of(-bd))
	t = 0.0
	while level.get("layer") != "surface" and t < 5.0:
		await walk(MapDef.yaw_of(-bd), 0.4)
		t += 0.4
	await settle(1.0)
	check("tp_up", level.get("layer") == "surface", "走进地下室光井 → 层 %s，位置 %s" % [level.get("layer"), player.global_position])
	# 边界：地上朝东墙走（墙挡住）
	await put(Vector3(380.0, 50, 60.0), -PI * 0.5)
	r = await walk(-PI * 0.5, 3.0)
	check("wall_edge", (r[0] as Vector3).x < 396.0, "朝东边围墙走 3 秒：x %.1f（墙从 396 起）" % (r[0] as Vector3).x)
	# 飞过墙头：禁制光幕弹回
	await take_off()
	await rise(2.2)
	r = await walk(-PI * 0.5, 4.0, true)
	var pb: Vector3 = r[0]
	check("barrier", pb.x < 399.5, "飞着越墙往东冲 4 秒：x %.1f y %.1f（光幕在 398）" % [pb.x, pb.y])
	await put(Vector3(372.0, 50, 60.0), -PI * 0.5, -0.05, 10.0)
	await settle(0.6)
	await shot("barrier")
	# 夜景
	level.set("clock_off", 600.0 - float(level.call("room_time")) + 30.0)
	await put(Vector3(4.0, 50, 60.0), 0.0, -0.1, 12.0)
	await wait(3.0)
	check("night", bool(level.call("is_night")), "拨钟后 is_night=%s" % level.call("is_night"))
	await shot("night")
	level.set("clock_off", 0.0)
	await wait(0.5)
	await _bigmap()


## review combat-8：掉帧时的招式突进不穿楼墙。直接喂关卡一帧（_constrain）：挪之前在楼里离北墙 6 米，一帧 0.08 秒（约 12 帧/秒）往北挪 14 米、穿过北墙。
## 速度对得上（招式突进，175 米/秒，走 player.velocity）→ 要停在墙里侧；同样的位移但速度是零（瞬身换位 / 回出生点这类传送）→ 照样过去
func _lunge_wall(at: Vector3, wall_z: float) -> void:
	var from := Vector3(at.x, at.y, wall_z + 6.0)
	var to := Vector3(at.x, at.y, wall_z - 8.0)
	var dt := 0.08
	var zs: Array[float] = []
	for vk: float in [1.0, 0.0]:
		level.set("_last", from)
		level.set("_v_pre", Vector3.ZERO)
		player.global_position = to
		player.velocity = (to - from) / dt * vk
		level.call("_constrain", dt)
		zs.append(player.global_position.z)
	player.global_position = from
	player.velocity = Vector3.ZERO
	level.set("_last", from)
	check("lunge_wall", zs[0] > wall_z and zs[1] < wall_z - 6.0,
			"楼里一帧 %.2f 秒往北挪 14 米：突进（速度对得上）停在 z %.2f（墙里侧 %.1f）；传送（速度为零）到了 z %.2f（%s 状态 %d）" % [
			dt, zs[0], wall_z, zs[1], "空中" if player.st != Player.St.GROUND else "地上", player.st])


func _bigmap() -> void:
	level.call("open_big_map")
	await wait(0.4)
	check("bigmap_3d_off", get_viewport().disable_3d, "大地图开着、面板外盖严之后 3D 渲染关掉：disable_3d=%s" % get_viewport().disable_3d)
	await shot("bigmap")
	# review uxperf-1：大地图开着时重伤倒地 → 当帧合上（不盖住「自救」）、重伤时也开不了；起身后 3D 渲染还原
	player.set_downed(true)
	await frames(3)
	var shut := not bool(level.call("big_map_open"))
	level.call("open_big_map")
	await frames(2)
	var refused := not bool(level.call("big_map_open"))
	player.set_downed(false)
	await frames(2)
	check("bigmap_downed", shut and refused and not get_viewport().disable_3d,
			"重伤时大地图自己合上 %s、再开被拒 %s、3D 渲染还原 %s" % [shut, refused, not get_viewport().disable_3d])
	level.call("close_big_map")
	await frames(2)


func _link(id: String) -> Dictionary:
	for l: Dictionary in level.call("points", "link"):
		if str(l["id"]) == id:
			return l
	return {}


func _kroom(id: String) -> Dictionary:
	for k: Dictionary in level.call("points", "key_room"):
		if str(k["id"]) == id:
			return k
	return {}


func _boss(key: String) -> Dictionary:
	for b: Dictionary in level.call("points", "boss"):
		if str(b["key"]) == key:
			return b
	return {}


## 导出主角周围（细地块 + 屋顶 + 门）的网格给 zfight.py
func _dump_geo() -> void:
	var out_dir := ProjectSettings.globalize_path("res://_shots/lvshot")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var spots: Array = [["main", Vector3(4, 50, 10)] if arg == "lab" else ["main", Vector3(12, 20, 82)]]
	for sp: Array in spots:
		await put(sp[1], 0.0)
		await settle(1.5)
		var f := FileAccess.open("%s/geo_%s_%s.bin" % [out_dir, arg, sp[0]], FileAccess.WRITE)
		var tris := 0
		for c: Node in world.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree() or mi.name == "Curtain":
				continue
			if mi.global_position.distance_to(player.global_position) > 260.0 and mi.name.begins_with("Roof"):
				continue
			var xf := mi.global_transform
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var n := idx.size()
				if n < 3:
					continue
				var pos := PackedFloat32Array()
				pos.resize(n * 3)
				var col := PackedFloat32Array()
				col.resize(n * 4)
				for k in n:
					var vi := idx[k]
					var p := xf * vs[vi]
					pos[k * 3] = p.x
					pos[k * 3 + 1] = p.y
					pos[k * 3 + 2] = p.z
					var cc := cs[vi] if vi < cs.size() else Color(0.5, 0.5, 0.5, 0.0)
					col[k * 4] = cc.r
					col[k * 4 + 1] = cc.g
					col[k * 4 + 2] = cc.b
					col[k * 4 + 3] = cc.a
				var label := ("%s#%d" % [str(world.get_path_to(mi)), si]).to_utf8_buffer()
				f.store_32(n)
				f.store_32(label.size())
				f.store_buffer(label)
				f.store_buffer(pos.to_byte_array())
				f.store_buffer(col.to_byte_array())
				tris += n / 3
		f.close()
		say("导出网格 geo_%s_%s.bin：%d 个三角形" % [arg, sp[0], tris])
