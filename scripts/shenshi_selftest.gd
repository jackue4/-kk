extends RefCounted
## 神识自检（2026-11-23）：`-- --raid-shot --shenshi [--touch]`（run_hidden，约 2 分钟；main.gd 用 load() 调，写坏了不连累主流程）。
## 流程：
##   1 找出生点附近一座没搜过的禁制宝库，主角站到它 70 米外、面朝它；身边摆一批目标（精英 / 首领 / 红名修士 / 储物袋 / 古宝掉落），怪定住
##   2 交互：鼠标点小地图 → 起扫；冷却中再点 → 不扫、有提示；按住半秒 → 切远近景、不扫；（--touch）摇杆按着、第二根手指点小地图 → 起扫
##   3 逐境界（炼气 … 大乘）各扫一次：光环近景、波前三成 / 七成的远景、扫完的透视、透视过后的描边各拍一张（ss_<境界>_*），打印揭示了什么、挂了多少影子网格
##   4 帧耗时：炼气、元婴、大乘各扫一次，量「扫的那三秒」和「不扫的一秒半」的中位 / 最长帧（同一进程里前后对照）
## 打印 `[shenshi]` 开头的行；断言不过的行带「✗」。

const Data := preload("res://scripts/raid_data.gd")

static var _fails := 0


static func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
	print("[shenshi] %s %s" % ["✓" if cond else "✗", what])


## 地表材质上光波的强度（没设过时材质返回 null = 着色器默认值 0）
static func _look_x(mats: Array) -> float:
	if mats.is_empty():
		return -1.0
	var v: Variant = (mats[0] as ShaderMaterial).get_shader_parameter("ss_look")
	return (v as Vector4).x if v is Vector4 else 0.0


static func _vp_pos(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local


static func _mouse(m: Node, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	var wp: Vector2 = m.get_viewport().get_final_transform() * pos
	ev.position = wp
	ev.global_position = wp
	Input.parse_input_event(ev)


## 用一台临时相机拍一张（俯瞰光波 / 贴近目标看透视和描边），拍完交还跟随相机
static func _eye_shot(m: Node, eye: Camera3D, c3: Camera3D, from: Vector3, look: Vector3, tag: String) -> void:
	eye.global_position = from
	eye.look_at(look, Vector3.UP)
	eye.make_current()
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	await m._shot(tag)
	c3.make_current()


## 量一段时间里的帧耗时：[中位, 最长]（毫秒）
static func _frames(m: Node, secs: float) -> Array:
	var tree: SceneTree = m.get_tree()
	var ts: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while float(Time.get_ticks_usec() - t0) / 1.0e6 < secs:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		ts.append(float(now - last) / 1000.0)
		last = now
	ts.sort()
	if ts.is_empty():
		return [0.0, 0.0]
	return [float(ts[ts.size() / 2]), float(ts[ts.size() - 1])]


static func run(m: Node) -> void:
	_fails = 0
	var rd: Node = m.level.raid
	var ss: Node = rd.shenshi
	var player: Node3D = m.player
	var cam: Node = m.cam
	var tree: SceneTree = m.get_tree()
	var touch := OS.get_cmdline_user_args().has("--touch")
	rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED

	# ---- 1 选点、摆目标 ----
	var vault: Dictionary = {}
	var vd := INF
	for s: Dictionary in rd.search.sites:
		if str(s["kind"]) == "vault" and not bool(s["done"]):
			var b: Vector2 = s["base"]
			if b.length() < vd:
				vd = b.length()
				vault = s
	_ok(not vault.is_empty(), "找到一座禁制宝库（离出生点 %d 米）" % int(vd))
	var vb: Vector2 = vault["base"] if not vault.is_empty() else Vector2(300.0, 0.0)
	var dir := vb.normalized()
	var p2 := vb - dir * 70.0
	var yaw := atan2(-dir.x, -dir.y)
	await m._raid_goto(p2, yaw)
	await m._wait(0.6)
	var side := Vector2(-dir.y, dir.x)
	var place := func(fwd: float, lat: float) -> Vector3:
		var q := p2 + dir * fwd + side * lat
		return Vector3(q.x, float(rd._ground(q.x, q.y)), q.y)
	var reg: Dictionary = Data.REGIONS[0]
	var elite: Node3D = rd._spawn_mob(int(reg["mobs"][0]), 0, place.call(32.0, -14.0), true, 3)
	var boss: Node3D = rd._spawn_mob(int(reg["boss"]), 0, place.call(95.0, 38.0), false, 3)
	rd._mobs.append(elite)      # _spawn_mob 不登记，调用方自己 append（刷怪点 / 导演都是这样）
	rd._mobs.append(boss)
	var rival: Node3D = rd.spawn_rival((place.call(55.0, 16.0) as Vector3) + Vector3(0.0, 0.5, 0.0), true)
	if rival != null:
		rival.set("ai_enabled", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	rd._drop_chest(place.call(22.0, 9.0), [Data.make_pill(2), Data.make_gear(2, rng)], "测试修士 的储物袋")
	rd._drop_item(place.call(40.0, -3.0), Data.make_gear(3, rng), 999.0)
	rd._drop_item(place.call(-18.0, -10.0), Data.make_gear(4, rng), 999.0)      # 身后（镜头外）
	await m._wait(1.0)
	print("[shenshi] 目标：精英 %s 首领 %s 修士 %s 掉落 %d 件（另有导演刷的怪 %d 只）" % [is_instance_valid(elite), is_instance_valid(boss),
			is_instance_valid(rival), rd._pickups.size(), rd._mobs.size()])
	var mats: Array = ss._world_mats()
	_ok(mats.size() == 2, "地表 / 水面两个材质都拿到了（%d）" % mats.size())
	_ok(_look_x(mats) == 0.0, "没扫的时候地表光波强度是 0")

	# ---- 2 交互 ----
	var mm: Control = rd.hud.minimap
	var mc := _vp_pos(mm, Vector2(mm.SIZE * 0.5, mm.SIZE * 0.55))
	player.set_realm(2, false)
	ss.cd_left = 0.0
	var n0 := int(ss.scans)
	_mouse(m, mc, true)
	await m._wait(0.08)
	_mouse(m, mc, false)
	await m._wait(0.1)
	_ok(int(ss.scans) == n0 + 1 and bool(ss.wave_on), "鼠标点小地图 → 神识一扫（扫了 %d 次）" % (int(ss.scans) - n0))
	await m._wait(0.3)
	_mouse(m, mc, true)
	await m._wait(0.08)
	_mouse(m, mc, false)
	await m._wait(0.1)
	_ok(int(ss.scans) == n0 + 1, "冷却中再点不扫（冷却还剩 %.1f 秒）" % float(ss.cd_left))
	var ri0 := int(mm._range_i)
	_mouse(m, mc, true)
	await m._wait(0.65)
	_mouse(m, mc, false)
	await m._wait(0.1)
	_ok(int(mm._range_i) != ri0 and int(ss.scans) == n0 + 1, "按住半秒切远近景（%d → %d）、不扫" % [ri0, int(mm._range_i)])
	mm._range_i = ri0
	await m._wait_until(func() -> bool: return not bool(ss.wave_on), 6.0)
	await m._wait(0.5)
	await m._shot("ss_ui_map")
	if touch:
		ss.cd_left = 0.0
		var n1 := int(ss.scans)
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		m._tt_touch(0, Vector2(vs.x * 0.15, vs.y * 0.75), true)
		await m._wait(0.1)
		m._tt_touch(1, mc, true)
		await m._wait(0.1)
		m._tt_touch(1, mc, false)
		await m._wait(0.1)
		m._tt_touch(0, Vector2(vs.x * 0.15, vs.y * 0.75), false)
		_ok(int(ss.scans) == n1 + 1, "触屏：摇杆按着、第二根手指点小地图 → 神识一扫")
		await m._wait_until(func() -> bool: return not bool(ss.wave_on), 6.0)
	ss.clear_marks()

	# ---- 3 逐境界 ----
	var Ss: GDScript = ss.get_script()
	var c3: Camera3D = cam.cam
	var eye := Camera3D.new()
	eye.fov = 72.0
	eye.near = 0.1
	eye.far = c3.far
	m.add_child(eye)
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var s3 := Vector3(side.x, 0.0, side.y)
	var pp := player.global_position
	var ep: Vector3 = elite.global_position if is_instance_valid(elite) else pp + d3 * 30.0
	for realm in (Ss.TIERS as Array).size():
		player.set_realm(realm, false)
		ss.clear_marks()
		ss.cd_left = 0.0
		cam.snap(yaw, -0.32, 9.0)
		await m._wait(0.5)
		var ok: bool = ss.scan()
		_ok(ok, "%d 档：起扫（半径 %d 米，冷却 %d 秒）" % [realm, int(ss.wave_max), int(ss.cd_total)])
		await m._wait(0.45)
		await m._shot("ss_%d_aura" % realm)
		var wm := float(ss.wave_max)
		# 俯瞰：身后 40 米、60 米高，看前方 60 米
		var over := pp - d3 * 40.0 + Vector3.UP * 60.0
		await m._wait_until(func() -> bool: return float(ss.wave_r) >= wm * 0.35, 4.0)
		await _eye_shot(m, eye, c3, over, pp + d3 * 60.0, "ss_%d_wave1" % realm)
		await m._wait_until(func() -> bool: return float(ss.wave_r) >= wm * 0.72, 4.0)
		await _eye_shot(m, eye, c3, over + Vector3.UP * 40.0, pp + d3 * 120.0, "ss_%d_wave2" % realm)
		await m._wait_until(func() -> bool: return not bool(ss.wave_on), 5.0)
		# 透视：贴着主角头顶朝前看（首领、修士、宝库多半隔着树和土坡）
		await _eye_shot(m, eye, c3, pp - d3 * 5.0 + Vector3.UP * 3.2, pp + d3 * 60.0 + Vector3.UP * 2.0, "ss_%d_xray" % realm)
		var st: Dictionary = ss.stats()
		print("[shenshi] %d 档：揭示 %s，藏着的修士 %d｜标记 %d 个，影子网格 %d 个目标 / %d 件，光柱 %d" % [realm, str(ss.found), int(ss.hidden),
				int(st["marks"]), int(st["ghost_targets"]), int(st["meshes"]), int(st["beams"])])
		if realm == 0 or realm == 3 or realm == 7:
			# 贴近精英：透视那几秒（底色 + 边缘光 + 描边）
			var near := ep - d3 * 8.0 + s3 * 3.0 + Vector3.UP * 3.5
			await _eye_shot(m, eye, c3, near, ep + Vector3.UP * 1.4, "ss_%d_xclose" % realm)
			# 透视过了以后：只剩描边 + 光柱余光
			var xr := float(ss.cur["xray"])
			await m._wait(maxf(xr - 0.2, 0.5))
			await _eye_shot(m, eye, c3, near, ep + Vector3.UP * 1.4, "ss_%d_line" % realm)
	eye.queue_free()
	_ok(int((ss.found as Dictionary).get("site", 0)) > 0, "大乘一扫揭示了搜点")
	_ok(int((ss.found as Dictionary).get("mob", 0)) >= 1, "大乘一扫揭示了精英 / 首领")
	_ok(int((ss.found as Dictionary).get("drop", 0)) >= 2, "大乘一扫揭示了掉落")
	_ok(not vault.is_empty() and bool(vault["known"]), "宝库被探明（小地图上有）")

	# ---- 4 帧耗时 ----
	cam.snap(yaw, -0.32, 9.0)
	for realm: int in [0, 3, 7]:
		player.set_realm(realm, false)
		ss.clear_marks()
		await m._wait(1.0)
		var base: Array = await _frames(m, 1.5)
		ss.cd_left = 0.0
		ss.scan()
		var during: Array = await _frames(m, 3.0)
		print("[shenshi] 帧耗时 %d 档：不扫 中位 %.1f / 最长 %.1f ms｜扫的三秒 中位 %.1f / 最长 %.1f ms（渲染器 %s）" % [realm, base[0], base[1], during[0], during[1],
				RenderingServer.get_current_rendering_method()])
		await m._wait_until(func() -> bool: return not bool(ss.wave_on), 5.0)
	await m._wait(0.3)
	_ok(not mats.is_empty() and _look_x(mats) == 0.0, "扫完地表光波强度回到 0")
	print("[shenshi] 完成：%s" % ("全部通过" if _fails == 0 else "%d 项没过" % _fails))
	await tree.process_frame
