extends SceneTree
## QA 探索性测试（2026-11-21 测试专项，只读测试脚本，不改产品代码）：
## 以「正常游玩」模式开机（不带任何演示参数；用户参数里只放 --qa-flow，使存档走自检档 xiuxian_profile_selftest.json），
## 用 Input.parse_input_event 发真实按键事件走 3C / 主城 / 进图 / 战斗 / 陨落 / 撤离 / 回城，连跑多局，记录异常。
## 跑法：python run_hidden.py . <log> --resolution 1280x720 -s res://_tasks/qa_20261121/qa_flow.gd -- --qa-flow [--touch]
## 每一条输出以 [qa] 开头；判定写「通过 / 不通过 / 记录」。

var m: Node
var fails: Array = []
var passes := 0
var _ft: Array = []        # 帧耗时采样
var _sampling := false
var _last_us := 0
var immortal := false
var dmg_acc := 0.0          # immortal 期间被补回去的伤害总量     # 测 3C / 战斗时别让主角被围死（量伤害的那几下当帧读数）


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 隐藏窗口别抓用户的鼠标
	if immortal and m != null and m.get("player") != null:
		var me: Node = (m.get("player") as Node).get("melee")
		if me != null and float(me.get("hp")) < 100.0:
			dmg_acc += 100.0 - float(me.get("hp"))
			me.set("hp", 100.0)
	var now := Time.get_ticks_usec()
	if _sampling and _last_us > 0:
		_ft.append(float(now - _last_us) / 1000.0)
	_last_us = now


func say(s: String) -> void:
	print("[qa] " + s)


func check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passes += 1
	else:
		fails.append(name)
	print("[qa] %s %s｜%s" % ["通过" if ok else "不通过", name, detail])


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


func key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func tap(code: Key, hold := 0.08) -> void:
	key(code, true)
	await wait(hold)
	key(code, false)


func hold_key(code: Key, sec: float) -> void:
	key(code, true)
	await wait(sec)
	key(code, false)


func ft_begin() -> void:
	_ft.clear()
	_sampling = true


func ft_end() -> String:
	_sampling = false
	if _ft.is_empty():
		return "无帧"
	var s: Array = _ft.duplicate()
	s.sort()
	var sum := 0.0
	for v: float in s:
		sum += v
	return "帧耗时 平均 %.1fms 中位 %.1fms 九成 %.1fms 最长 %.1fms（%d 帧）" % [sum / float(s.size()), float(s[s.size() / 2]),
			float(s[int(float(s.size()) * 0.9)]), float(s[s.size() - 1]), s.size()]


## 存一张 800 宽的 JPG 证据图到 _tasks/qa_20261121/shots（无界面模式没有画面，跳过）
func shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	var w := 800
	img.resize(w, int(float(img.get_height()) * float(w) / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_tasks/qa_20261121/shots"))
	var suffix := "_touch" if OS.get_cmdline_user_args().has("--touch") else ""
	img.save_jpg("res://_tasks/qa_20261121/shots/%s%s.jpg" % [tag, suffix], 0.85)
	say("截图 " + tag + suffix)


func pl() -> Node3D:
	return m.get("player") as Node3D


func st_name() -> String:
	var names := ["GROUND", "TAKEOFF", "FLY", "AIR", "DIVE"]
	var i := int(pl().get("st"))
	return names[i] if i >= 0 and i < names.size() else str(i)


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func mem_mb() -> float:
	return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0


func _run() -> void:
	var touch := OS.get_cmdline_user_args().has("--touch")
	say("开机：正常游玩模式（%s）" % ("触屏 / 手机画质档" if touch else "键鼠"))
	await wait(3.0)
	var hub: Node = m.get("hub")
	check("开机落在主城", hub != null and bool(hub.get("active")), "hub=%s active=%s 主角 %s" % [hub != null, hub != null and bool(hub.get("active")), str(pl().global_position.round())])
	if hub == null:
		_end()
		return
	var hconst: Dictionary = (hub.get_script() as GDScript).get_script_constant_map()
	var gates: Array = hconst["GATES"]
	var terrace: float = hconst["TERRACE_H"]
	var wall_z: float = hconst["WALL_Z"]
	ft_begin()
	await wait(3.0)
	say("主城站立 3 秒：" + ft_end())
	var n0 := nodes()
	var mem0 := mem_mb()
	say("主城初始：节点 %d 孤儿节点 %d 静态内存 %.1f MB" % [n0, orphans(), mem0])

	await _test_3c_hub(hub)
	# ---- 连跑三局：陨落 / 撤离 / 立即撤回 ----
	var rounds := ["death", "extract", "quick"]
	var after: Array = []
	for ri in rounds.size():
		var kind: String = rounds[ri]
		say("==== 第 %d 局（%s）====" % [ri + 1, kind])
		var ok := await _enter_raid_via_gate(hub, gates, terrace, wall_z, ri == 0)
		if not ok:
			fails.append("进图失败（第 %d 局）" % (ri + 1))
			break
		if ri == 0:
			await _test_raid_3c_combat()
		match kind:
			"death":
				await _do_death(hub)
			"extract":
				await _do_extract(hub)
			"quick":
				await _do_quick_exit(hub)
		await wait(2.0)
		after.append([nodes(), orphans(), mem_mb()])
		say("第 %d 局回城后：节点 %d 孤儿节点 %d 静态内存 %.1f MB" % [ri + 1, nodes(), orphans(), mem_mb()])
	if after.size() >= 2:
		var a1: Array = after[0]
		var a3: Array = after[after.size() - 1]
		check("多局往返节点不涨", int(a3[0]) - int(a1[0]) < 300, "第一局后 %d → 最后 %d（开机 %d）；孤儿 %d → %d；内存 %.1f → %.1f MB" % [
				int(a1[0]), int(a3[0]), n0, int(a1[1]), int(a3[1]), float(a1[2]), float(a3[2])])
	_end()


func _end() -> void:
	say("小结：通过 %d 项，不通过 %d 项 %s" % [passes, fails.size(), str(fails)])
	await wait(0.5)
	quit()


# ---------------- 主城里的 3C ----------------

func _test_3c_hub(hub: Node) -> void:
	var p := pl()
	var cam: Node3D = m.get("cam") as Node3D
	var sp: Vector3 = hub.call("spawn_point")
	p.global_position = sp
	await wait(0.6)
	# 1 走：W 按 2 秒
	var a := p.global_position
	await hold_key(KEY_W, 2.0)
	var walked := flat_dist(a, p.global_position)
	await wait(0.4)
	var drift := flat_dist(a, p.global_position) - walked
	check("W 键走路", walked > 4.0, "2 秒走了 %.1f 米；松键后 0.4 秒又滑了 %.2f 米" % [walked, drift])
	check("松键即停", drift < 1.2, "松键后滑行 %.2f 米" % drift)
	# 2 疾行：Shift 长按 + W
	a = p.global_position
	key(KEY_SHIFT, true)
	await wait(0.35)
	await hold_key(KEY_W, 2.0)
	key(KEY_SHIFT, false)
	var ran := flat_dist(a, p.global_position)
	check("Shift 长按疾行比走快", ran > walked * 1.2, "疾行 2 秒 %.1f 米 vs 走 %.1f 米" % [ran, walked])
	await wait(0.5)
	# 3 跳
	var y0 := p.global_position.y
	var ymax := y0
	key(KEY_SPACE, true)
	var t := 0.0
	while t < 0.9:
		await process_frame
		t += 1.0 / 60.0
		ymax = maxf(ymax, p.global_position.y)
		if t > 0.12:
			key(KEY_SPACE, false)
	await wait(1.2)
	check("空格跳起并落回", ymax - y0 > 0.8 and absf(p.global_position.y - y0) < 0.6 and st_name() == "GROUND",
			"最高 +%.2f 米，落回高差 %.2f 米，状态 %s" % [ymax - y0, p.global_position.y - y0, st_name()])
	# 4 炼气连点两下跳 = 御剑起飞
	await tap(KEY_SPACE, 0.08)
	await wait(0.22)
	await tap(KEY_SPACE, 0.08)
	await wait(1.2)
	var flying := st_name()
	check("炼气连点两下跳起飞", flying == "FLY" or flying == "AIR" or flying == "TAKEOFF", "0.3 秒内两下跳后状态 %s，离地 %.1f 米" % [flying, p.global_position.y - y0])
	# 飞着往前 2 秒，再看怎么落地（按 F 或空格都试）
	await hold_key(KEY_W, 1.5)
	var hy := p.global_position.y
	await tap(KEY_F)
	await wait(2.5)
	if st_name() != "GROUND":
		say("按 F 后 2.5 秒状态 %s（高度 %.1f → %.1f），再试长按 Shift 下降 / 什么都不按等 4 秒" % [st_name(), hy, p.global_position.y])
		await wait(4.0)
	say("记录：飞行落地后状态 %s，离起点高差 %.1f 米" % [st_name(), p.global_position.y - y0])
	if st_name() != "GROUND":
		p.call("force_ground")
		p.global_position = sp
		await wait(0.5)
	# 5 镜头：滚轮拉远拉近的范围（触屏模式不处理滚轮，双指缩放另见 qa_touch_zoom.gd）
	if OS.get_cmdline_user_args().has("--touch"):
		say("记录：触屏模式不处理鼠标滚轮，缩放见双指缩放用例")
		await _cam_wall_probe(hub)
		return
	var zoom0 := float(cam.get("zoom"))
	for i in 20:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_WHEEL_DOWN
		mb.pressed = true
		Input.parse_input_event(mb)
		await process_frame
	await wait(0.5)
	var zmax := float(cam.get("zoom"))
	for i in 40:
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_WHEEL_UP
		mb2.pressed = true
		Input.parse_input_event(mb2)
		await process_frame
	await wait(0.5)
	var zmin := float(cam.get("zoom"))
	cam.set("zoom", zoom0)
	check("滚轮缩放有上下限", zmax <= 16.01 and zmin >= 2.99 and zmax > zmin, "默认 %.1f，最远 %.1f，最近 %.1f" % [zoom0, zmax, zmin])
	# 6 镜头进墙：主角背贴商店主楼的墙（楼墙在 x=-45 附近），镜头朝墙外，看镜头是不是穿进楼里
	await _cam_wall_probe(hub)


func _cam_wall_probe(hub: Node) -> void:
	var p := pl()
	var cam: Node3D = m.get("cam") as Node3D
	var c3d: Camera3D = cam.get("cam") as Camera3D
	var shop: Vector3 = (hub.get_script() as GDScript).get_script_constant_map()["SHOP_POS"]
	# 从商店门口往楼里走，直到被墙挡住
	p.global_position = shop + Vector3(6.0, 0.2, 0.0)
	p.call("face_now", PI * 0.5)       # 朝 -X（楼的方向）
	cam.call("snap", PI * 0.5, -0.2, 8.0)
	await wait(0.5)
	await hold_key(KEY_W, 2.5)
	var blocked_x := p.global_position.x
	# 转身：主角背对墙，镜头放在墙那一侧（看主角的脸 = 镜头在楼里）
	cam.call("snap", -PI * 0.5, -0.15, 8.0)
	await wait(1.0)
	var cpos := c3d.global_position
	var g: float = float(hub.call("ground", cpos.x, cpos.z))
	var solid_top: float = float(hub.call("_solid_at", cpos.x, cpos.z))
	var own_top: float = float(hub.call("_solid_at", p.global_position.x, p.global_position.z))
	var inside := solid_top > 0.0 and cpos.y < solid_top
	# 主城实心格 2 米一格、比楼的实际墙面大一圈：镜头和主角在同一格里时按商店主楼真实墙面（x = -45，hub 自检里的数）判
	var same_cell := inside and absf(solid_top - own_top) < 0.01 and Vector2(cpos.x - p.global_position.x, cpos.z - p.global_position.z).length() < 2.0
	var past_wall := cpos.x < -45.0
	await shot("hub_cam_wall")
	# 主城实心格比楼的实际墙面大约大一圈（主角停在 x=-44.1，墙面在 -45），格子判不准：以「镜头有没有越过楼的实际墙面」为准，并配截图
	check("主城背贴墙时镜头不进楼", not past_wall, "主角挡在 x=%.1f；镜头在 %s（离主角 %.1f 米），镜头脚下地面高 %.1f，该格实心体顶高 %.1f（主角站的格 %.1f）→ 在别的实心格里=%s，过了 x=-45 的墙面=%s" % [
			blocked_x, str(cpos.snapped(Vector3.ONE * 0.1)), cpos.distance_to(p.global_position + Vector3(0, 1.45, 0)), g, solid_top, own_top, inside and not same_cell, past_wall])
	# 再沿 4 个方向背贴墙各试一次（东面仓库楼、北墙）
	var store: Vector3 = (hub.get_script() as GDScript).get_script_constant_map()["STORE_POS"]
	var wall_z: float = (hub.get_script() as GDScript).get_script_constant_map()["WALL_Z"]
	var probes := [[store + Vector3(-6.0, 0.2, 0.0), -PI * 0.5, PI * 0.5, "仓库楼"], [Vector3(-17.0, 3.2, wall_z + 10.0), 0.0, PI, "北面石墙"]]
	for pr: Array in probes:
		p.global_position = pr[0]
		p.call("face_now", float(pr[1]))
		cam.call("snap", float(pr[1]), -0.2, 8.0)
		await wait(0.3)
		await hold_key(KEY_W, 2.5)
		cam.call("snap", float(pr[2]), -0.15, 8.0)
		await wait(1.0)
		var cp := c3d.global_position
		var stop: float = float(hub.call("_solid_at", cp.x, cp.z))
		var otop: float = float(hub.call("_solid_at", p.global_position.x, p.global_position.z))
		var in2 := stop > 0.0 and cp.y < stop
		var same2 := in2 and absf(stop - otop) < 0.01 and Vector2(cp.x - p.global_position.x, cp.z - p.global_position.z).length() < 2.0
		var past2 := (cp.x > 45.0) if str(pr[3]) == "仓库楼" else (cp.z < -57.0)     # 仓库楼墙面 x=45；北面石墙墙面 z≈-57（墙心 -58）
		check("主城背贴%s时镜头不越过墙面" % str(pr[3]), not past2, "主角在 %s；镜头 %s，该格实心体顶高 %.1f（主角站的格 %.1f）→ 在别的实心格里=%s，过了墙面=%s" % [
				str(p.global_position.snapped(Vector3.ONE * 0.1)), str(cp.snapped(Vector3.ONE * 0.1)), stop, otop, in2 and not same2, past2])
		await shot("hub_cam_wall_" + str(pr[3]))
	p.global_position = hub.call("spawn_point")
	await wait(0.4)


# ---------------- 进图 ----------------

func _enter_raid_via_gate(hub: Node, gates: Array, terrace: float, wall_z: float, first: bool) -> bool:
	var p := pl()
	var ui: Node = m.get("level_ui")
	# 主角放到木兰草原门前 12 米、朝北，按住 W 走进门洞（真实触发）
	p.call("force_ground")
	p.global_position = Vector3(float(gates[0]["x"]), terrace + 0.1, wall_z + 12.0)
	p.call("face_now", 0.0)
	(m.get("cam") as Node).call("snap", 0.0, -0.2, 8.0)
	await wait(0.6)
	key(KEY_W, true)
	var opened: bool = await wait_until(func() -> bool: return bool(ui.call("is_open")), 6.0)
	key(KEY_W, false)
	check("走进木兰草原门打开选关", opened, "走了 %.1f 米后 选关界面=%s 暂停=%s" % [flat_dist(p.global_position, Vector3(float(gates[0]["x"]), 0.0, wall_z + 12.0)), opened, paused])
	if not opened:
		return false
	await wait(0.5)
	if first:
		# 选关界面开着时按 W / B / 空格，主角不该动
		var pp := p.global_position
		await hold_key(KEY_W, 0.6)
		await tap(KEY_B)
		await tap(KEY_SPACE)
		await wait(0.3)
		check("选关界面开着时主角不动", flat_dist(pp, p.global_position) < 0.3, "按 W 0.6 秒后位移 %.2f 米" % flat_dist(pp, p.global_position))
	# 单人快速入境（pick quick=true 不开房间，免得和用户自己开着的游戏互相匹配）
	var t0 := Time.get_ticks_msec()
	ui.call("pick", 0, true)
	var b_in_load := OS.get_cmdline_user_args().has("--qa-bload") and first
	if first:
		# 黑场载入期间乱按：W、空格、F、E（B 单独一条用例：--qa-bload）
		await wait(0.2)
		key(KEY_W, true)
		if b_in_load:
			await tap(KEY_B)
		await tap(KEY_SPACE)
		await tap(KEY_F)
		await tap(KEY_E)
	var entered: bool = await wait_until(func() -> bool: return m.get("level") != null and not bool(m.get("_switching")), 90.0)
	var load_s := float(Time.get_ticks_msec() - t0) / 1000.0
	if first:
		key(KEY_W, false)
	check("入境载入", entered, "用时 %.1f 秒" % load_s)
	if not entered:
		return false
	await wait(1.0)
	var lv: Node = m.get("level")
	var rd: Node = lv.get("raid")
	check("进图后是搜打撤、主城关闭", rd != null and not bool(hub.get("active")), "raid=%s 主城 active=%s" % [rd != null, bool(hub.get("active"))])
	await shot("raid_arrive" + ("_bload" if b_in_load else ""))
	var ab: Variant = ui.get("_abode")
	var ab_open := ab != null and is_instance_valid(ab)
	check("进图后游戏没被暂停、洞府没开着", not paused and not ab_open, "暂停=%s 洞府界面开着=%s（载入黑场期间按过 B=%s）" % [paused, ab_open, b_in_load])
	if ab_open:
		# 记录：在大世界里开着的洞府能不能用（仓库页 / 坊市页），然后关掉继续
		await wait(0.5)
		(ab as Node).call("_close")
		await wait(0.5)
		say("关掉洞府后：暂停=%s" % paused)
	if first:
		var rh: Node = rd.get("hud")
		var bag_open := bool(rh.call("bag_open")) if rh != null else false
		check("载入期间按的键没把背包留开", not bag_open, "背包开着=%s 状态 %s 速度 %.1f" % [bag_open, st_name(), (pl() as CharacterBody3D).velocity.length()])
		var v := (pl() as CharacterBody3D).velocity
		await wait(1.0)
		var p1 := pl().global_position
		await wait(1.0)
		check("载入期间按住又松开的 W 不卡键", flat_dist(p1, pl().global_position) < 0.5, "进图后 1 秒内自己走了 %.2f 米（速度 %.1f）" % [flat_dist(p1, pl().global_position), v.length()])
	return true


# ---------------- 大世界里的 3C / 战斗 ----------------

func _test_raid_3c_combat() -> void:
	var p := pl()
	var lv: Node = m.get("level")
	var rd: Node = lv.get("raid")
	immortal = true
	ft_begin()
	await hold_key(KEY_W, 3.0)
	say("大世界走 3 秒：" + ft_end())
	await _cam_cliff_probe(lv)
	# 找最近的怪（导演刷怪要几秒，最多等 25 秒）
	var mob: Node3D = await _nearest_mob(rd, 25.0)
	say("场上自己名下的怪 %d 只" % (rd.get("_mobs") as Array).size())
	if mob == null:
		check("找到小怪", false, "等 25 秒场上没有怪")
		return
	# 冻住其它怪的处理，免得被围
	var mroot: Node = rd.get("_mob_root")
	# 把主角放到怪面前 3 米，面朝它，按 J 攻击十下
	var mp := mob.global_position
	var dir := Vector3(p.global_position.x - mp.x, 0.0, p.global_position.z - mp.z).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector3.BACK
	var spot := mp + dir * 3.0
	spot.y = float(lv.call("ground", spot.x, spot.z)) + 0.1
	p.global_position = spot
	var yaw := atan2(dir.x, dir.z)
	p.call("face_now", yaw)
	(m.get("cam") as Node).call("snap", yaw, -0.2, 8.0)
	await wait(0.4)
	var hp0 := float(mob.get("hp")) if mob.get("hp") != null else -1.0
	var php0 := float(p.get("melee").get("hp"))
	ft_begin()
	for i in 10:
		await tap(KEY_J, 0.06)
		await wait(0.22)
	var hp1 := float(mob.get("hp")) if is_instance_valid(mob) and mob.get("hp") != null else -1.0
	say("近战十下：" + ft_end())
	check("地面按 J 打得到怪", (not is_instance_valid(mob)) or hp1 < hp0, "怪血 %.0f → %s；主角状态 %s 气血 %.0f → %.0f" % [hp0,
			("%.0f" % hp1) if is_instance_valid(mob) else "已死", st_name(), php0, float(p.get("melee").get("hp"))])
	# 地面格挡 / 弹反（炼气是地面近战）：面朝怪按住 K 挨一下应返回 1（挡下），刚按下 K 的一瞬挨一下应返回 2（弹反）
	if is_instance_valid(mob):
		p.call("force_ground")
		var to_m := mob.global_position - p.global_position
		p.call("face_now", atan2(-to_m.x, -to_m.z))
		await wait(1.2)
		key(KEY_K, true)
		await wait(0.45)
		var r_block := _mob_hit(mob, 5.0, false, Vector3.FORWARD, false)
		key(KEY_K, false)
		await wait(1.2)
		key(KEY_K, true)
		await process_frame
		await process_frame
		var r_parry := _mob_hit(mob, 5.0, false, Vector3.FORWARD, false)
		key(KEY_K, false)
		check("地面按住 K 格挡挡得下", r_block == 1, "返回 %d（1 = 挡下，0 = 挨打，2 = 弹反，-1 = 打不到）" % r_block)
		check("地面刚按 K 的一瞬弹反", r_parry == 2, "返回 %d（2 = 弹反）" % r_parry)
		await wait(0.8)
	# 小怪的受击入口（raid_mob._hit_player）对主角各状态的返回值：-1 = 打不到
	if is_instance_valid(mob):
		var rets := {}
		p.call("force_ground")
		await wait(0.3)
		var mh := float(p.get("melee").get("hp"))
		rets["GROUND"] = _mob_hit(mob, 1.0, false, Vector3.FORWARD, false)
		var mh_g := float(p.get("melee").get("hp"))
		await wait(0.6)
		await tap(KEY_SPACE, 0.08)
		await wait(0.22)
		await tap(KEY_SPACE, 0.08)
		await wait(1.0)
		var mh2 := float(p.get("melee").get("hp"))
		rets[st_name()] = _mob_hit(mob, 1.0, false, Vector3.FORWARD, false)
		var mh3 := float(p.get("melee").get("hp"))
		check("记录·小怪打主角的返回值（-1 = 打不到）", true, "%s；地面挨一下气血 %.1f → %.1f，%s 时挨一下 %.1f → %.1f" % [str(rets), mh, mh_g, st_name(), mh2, mh3])
		p.call("force_ground")
		await wait(0.5)
	# 飞行状态下会不会挨打：起飞后停在怪身边，看 6 秒内（不死，补血前记下伤害）挨了多少
	if is_instance_valid(mob):
		p.call("force_ground")
		await wait(0.8)
		for attempt in 3:
			await tap(KEY_SPACE, 0.08)
			await wait(0.22)
			await tap(KEY_SPACE, 0.08)
			await wait(1.0)
			if st_name() != "GROUND":
				break
			await wait(0.6)
		var stn := st_name()
		dmg_acc = 0.0
		var min_d := INF
		var t := 0.0
		var stays := {}
		while t < 6.0 and is_instance_valid(mob):
			var mp2 := mob.global_position
			p.global_position = mp2 + Vector3(2.0, 1.4, 0.0)
			(p as CharacterBody3D).velocity = Vector3.ZERO
			min_d = minf(min_d, p.global_position.distance_to(mp2))
			stays[st_name()] = true
			await process_frame
			t += 1.0 / 60.0
		check("记录·飞行（%s）时贴着怪 6 秒挨不挨打" % stn, true, "期间状态 %s，离怪最近 %.1f 米，累计受到伤害 %.0f" % [str(stays.keys()), min_d, dmg_acc])
		# 对照：同样贴着，地面上 6 秒
		p.call("force_ground")
		dmg_acc = 0.0
		t = 0.0
		while t < 6.0 and is_instance_valid(mob):
			var mp3 := mob.global_position
			var gp := mp3 + Vector3(2.0, 0.0, 0.0)
			gp.y = float(lv.call("ground", gp.x, gp.z)) + 0.1
			p.global_position = gp
			await process_frame
			t += 1.0 / 60.0
		check("记录·对照：地面上贴着同一只怪 6 秒", true, "累计受到伤害 %.0f" % dmg_acc)
		await wait(0.3)
	# 背包：B 打开 / 关闭
	var rh: Node = rd.get("hud")
	await tap(KEY_B)
	await wait(0.4)
	var o1 := bool(rh.call("bag_open"))
	var pp := p.global_position
	await hold_key(KEY_W, 0.6)
	var moved := flat_dist(pp, p.global_position)
	await tap(KEY_B)
	await wait(0.4)
	var o2 := bool(rh.call("bag_open"))
	check("B 开关背包", o1 and not o2, "按一下开=%s 再按一下关=%s；背包开着时按 W 走了 %.2f 米" % [o1, not o2, moved])
	# 联机受击路径：raid_manager.net_take_hit 收到的攻击来源找不到（别人的怪在我这边没有木偶 / 已释放）时回退成 player 自己
	p.call("force_ground")
	await wait(0.5)
	var hpa := float(p.get("melee").get("hp"))
	say("调用 net_take_hit(src=null, 伤害 5) —— 看 stderr 里有没有 player_melee.gd 的 SCRIPT ERROR")
	immortal = false
	rd.call("net_take_hit", null, 0, 5.0, Vector3.FORWARD, 6.0, false, "", false)
	var hpb := float(p.get("melee").get("hp"))
	var mstate := int(p.get("melee").get("state"))
	immortal = true
	say("记录·net_take_hit(null)：气血 %.1f → %.1f，近战状态码 %d（受击硬直应变成 HURT=7）" % [hpa, hpb, mstate])
	immortal = false
	p.get("melee").set("hp", 100.0)
	if mroot != null:
		pass


## 镜头 × 方块地形：主角背靠一面高崖站着，镜头从崖上扫过去（模拟鼠标 / 手指转视角），看镜头高度有没有一帧跳上去、主角会不会被地形挡住
func _cam_cliff_probe(lv: Node) -> void:
	var p := pl()
	var rig: Node3D = m.get("cam") as Node3D
	var c3d: Camera3D = rig.get("cam") as Camera3D
	var o := p.global_position
	var best := 0.0
	var low := Vector3.ZERO
	var up_dir := Vector3.ZERO
	for gx in range(-30, 31):
		for gz in range(-30, 31):
			var x := o.x + float(gx) * 4.0
			var z := o.z + float(gz) * 4.0
			var h := float(lv.call("ground", x, z))
			if h < 0.0:
				continue     # 海面
			for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				var h2 := float(lv.call("ground", x + d.x * 4.0, z + d.z * 4.0))
				# 要的是「一面墙」：崖顶往后 8 米也还高（不是一根柱子）
				var h3 := float(lv.call("ground", x + d.x * 12.0, z + d.z * 12.0))
				if h2 - h > best and h3 - h > (h2 - h) * 0.7:
					best = h2 - h
					low = Vector3(x, h, z)
					up_dir = d
	if best < 6.0:
		say("记录：出生点附近 120 米内没找到 6 米以上的崖（最高 %.1f 米），跳过镜头 × 崖壁" % best)
		return
	var face := -up_dir          # 主角背对崖
	var stand := low + face * 1.0 + Vector3(0.0, 0.1, 0.0)
	stand.y = float(lv.call("ground", stand.x, stand.z)) + 0.1
	p.call("force_ground")
	p.global_position = stand
	var yaw_face := atan2(-face.x, -face.z)
	p.call("face_now", yaw_face)
	rig.call("snap", yaw_face + PI * 0.5, -0.2, 8.0)     # 先侧着看（镜头不在崖上）
	await wait(0.8)
	var max_dy := 0.0
	var occl := 0
	var frames := 0
	var prev_y := c3d.global_position.y
	var y_lo := INF
	var y_hi := -INF
	# 1.6 秒内把镜头从侧面转到正后方（崖上）再转到另一侧：每秒约 110°
	var t := 0.0
	while t < 3.2:
		var k := t / 3.2
		rig.set("yaw", yaw_face + PI * 0.5 - PI * k)
		await process_frame
		t += get_process_delta_time_safe()
		var cp := c3d.global_position
		if absf(cp.y - prev_y) > 4.0:
			say("调试·镜头高度跳 %.1f：t=%.2f 镜头 %s 脚下地面 %.1f 主角 %s 主角脚下 %.1f yaw %.2f _occ_d %.2f" % [cp.y - prev_y, t, str(cp.snapped(Vector3.ONE * 0.1)),
					float(lv.call("ground", cp.x, cp.z)), str(p.global_position.snapped(Vector3.ONE * 0.1)), float(lv.call("ground", p.global_position.x, p.global_position.z)),
					float(rig.get("yaw")), float(rig.get("_occ_d"))])
		max_dy = maxf(max_dy, absf(cp.y - prev_y))
		prev_y = cp.y
		y_lo = minf(y_lo, cp.y)
		y_hi = maxf(y_hi, cp.y)
		frames += 1
		# 镜头 → 主角胸口这段线上有没有地形比线高（被挡住）
		var aim := p.global_position + Vector3(0.0, 1.2, 0.0)
		var blocked := false
		for s in range(1, 12):
			var q := cp.lerp(aim, float(s) / 12.0)
			if float(lv.call("ground", q.x, q.z)) > q.y + 0.3:
				blocked = true
				break
		if blocked:
			occl += 1
	await shot("raid_cam_cliff")
	check("大世界背靠高崖转镜头：镜头高度不硬跳", max_dy < 2.0, "崖高 %.1f 米（主角在 %s）；扫 180° 共 %d 帧，镜头高度 %.1f ~ %.1f，单帧最大升降 %.2f 米" % [best,
			str(stand.round()), frames, y_lo, y_hi, max_dy])
	check("大世界背靠高崖转镜头：主角不被地形挡住", occl == 0, "镜头 → 主角视线被地形挡住的帧 %d / %d" % [occl, frames])


func get_process_delta_time_safe() -> float:
	var f := Engine.get_frames_per_second()
	return 1.0 / maxf(float(f), 10.0)


func _nearest_mob(rd: Node, sec: float) -> Node3D:
	var p := pl()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		var mobs: Array = rd.get("_mobs")
		var mob: Node3D = null
		var best := INF
		for mo: Variant in mobs:
			if is_instance_valid(mo) and mo is Node3D and float((mo as Node3D).get("hp")) > 0.0:
				var d := (mo as Node3D).global_position.distance_to(p.global_position)
				if d < best:
					best = d
					mob = mo
		if mob != null:
			return mob
		await wait(0.5)
	return null



## 怪可能在测试途中被打死释放：先判再调（2026-11-21 回归时修的测试脚本问题）
func _mob_hit(mob: Variant, dmg: float, heavy: bool, dir: Vector3, ranged: bool) -> int:
	if not is_instance_valid(mob):
		return -9
	return int((mob as Node).call("_hit_player", dmg, heavy, dir, ranged))


# ---------------- 结束一局的三种方式 ----------------

func _back_home(hub: Node, sec: float) -> bool:
	return await wait_until(func() -> bool: return m.get("level") == null and not bool(m.get("_switching")) and bool(hub.get("active")), sec)


func _do_death(hub: Node) -> void:
	var p := pl()
	immortal = false
	var lv: Node = m.get("level")
	if lv == null or not is_instance_valid(lv):
		check("陨落用例前还在大世界里", false, "level 已经没了（前面的测试里主角被打死了？）")
		return
	var rd: Node = lv.get("raid")
	var prof: GDScript = load("res://scripts/raid_profile.gd")
	var st0: Dictionary = (prof.call("data") as Dictionary).get("stats", {}).duplicate()
	p.call("force_ground")
	await wait(0.4)
	# 找一只怪当凶手，走它真实的出手入口（raid_mob._hit_player → player_melee.receive_attack）
	var src: Node3D = await _nearest_mob(rd, 25.0)
	var melee: Node = p.get("melee")
	var res := -9
	if src != null:
		var to := src.global_position - p.global_position
		res = int(src.call("_hit_player", 99999.0, true, to.normalized() if to.length() > 0.1 else Vector3.FORWARD, false))
	else:
		say("没有怪：改用 raid_manager.net_take_hit（联机里「别人的怪 / 玩家」打中我，攻击来源找不到时的路径）")
		rd.call("net_take_hit", null, 0, 99999.0, Vector3.FORWARD, 6.0, true, "", false)
	await wait(0.6)
	check("致命一击后陨落", bool(p.get("dead")) or not bool(rd.get("running")), "receive_attack 返回 %d，dead=%s，局还在跑=%s 气血 %.0f" % [res, p.get("dead"), rd.get("running"), float(melee.get("hp"))])
	# 陨落后按键不该还能动
	var pp := p.global_position
	await hold_key(KEY_W, 1.0)
	await tap(KEY_J)
	check("陨落后不能操作", flat_dist(pp, p.global_position) < 0.5, "按 W 1 秒走了 %.2f 米" % flat_dist(pp, p.global_position))
	var home: bool = await _back_home(hub, 20.0)
	await wait(1.0)
	var st1: Dictionary = (prof.call("data") as Dictionary).get("stats", {})
	var hp := float(melee.get("hp"))
	check("陨落结算后回主城", home, "回城=%s dead=%s 气血 %.0f 状态 %s 位置 %s" % [home, p.get("dead"), hp, st_name(), str(p.global_position.round())])
	check("回城后复活满血", not bool(p.get("dead")) and hp >= float(melee.get("HP_MAX")) - 0.5, "dead=%s 气血 %.0f / %.0f" % [p.get("dead"), hp, float(melee.get("HP_MAX"))])
	check("存档记一次陨落", int(st1.get("dead", 0)) == int(st0.get("dead", 0)) + 1, "陨落次数 %d → %d；入境次数 %d → %d" % [int(st0.get("dead", 0)), int(st1.get("dead", 0)),
			int(st0.get("raids", 0)), int(st1.get("raids", 0))])
	await _after_return_checks(hub)


func _do_extract(hub: Node) -> void:
	var p := pl()
	var lv: Node = m.get("level")
	if lv == null or not is_instance_valid(lv):
		check("撤离用例前还在大世界里", false, "level 已经没了")
		return
	var rd: Node = lv.get("raid")
	var prof: GDScript = load("res://scripts/raid_profile.gd")
	var st0: Dictionary = (prof.call("data") as Dictionary).get("stats", {}).duplicate()
	var ex: Array = rd.get("_extracts")
	var target: Dictionary = {}
	for e: Dictionary in ex:
		if bool(e["active"]) and str(e.get("kind", "gate")) == "gate":
			target = e
			break
	if target.is_empty():
		for e2: Dictionary in ex:
			if bool(e2["active"]):
				target = e2
				break
	if target.is_empty():
		check("找到亮着的撤离阵", false, "撤离点 %d 个，没有亮着的" % ex.size())
		return
	var pos: Vector3 = target["pos"]
	p.call("force_ground")
	# 先放到阵外 20 米，走进去（真实路径）
	var out := pos + Vector3(14.0, 0.0, 0.0)
	out.y = float(lv.call("ground", out.x, out.z)) + 0.2
	p.global_position = out
	p.call("face_now", PI * 0.5)
	(m.get("cam") as Node).call("snap", PI * 0.5, -0.2, 8.0)
	rd.get("_mob_root").set("process_mode", Node.PROCESS_MODE_DISABLED)   # 撤离读条期间别被怪打断
	await wait(1.0)
	key(KEY_W, true)
	await wait_until(func() -> bool: return flat_dist(p.global_position, pos) < 2.0, 6.0)
	key(KEY_W, false)
	var t0 := Time.get_ticks_msec()
	var started: bool = await wait_until(func() -> bool: return float(rd.get("extract_k")) > 0.0, 3.0)
	var done: bool = await wait_until(func() -> bool: return not bool(rd.get("running")), 40.0)
	check("走进亮着的阵读条撤离", started and done, "阵「%s」(%s) 读条开始=%s 完成=%s 用时 %.1f 秒；主角离阵心 %.1f 米" % [str(target.get("name", "")), str(target.get("kind", "")),
			started, done, float(Time.get_ticks_msec() - t0) / 1000.0, flat_dist(p.global_position, pos)])
	var home: bool = await _back_home(hub, 20.0)
	await wait(1.0)
	var st1: Dictionary = (prof.call("data") as Dictionary).get("stats", {})
	check("撤离结算后回主城", home, "回城=%s 状态 %s" % [home, st_name()])
	check("存档记一次撤离", int(st1.get("out", 0)) == int(st0.get("out", 0)) + 1, "撤离次数 %d → %d" % [int(st0.get("out", 0)), int(st1.get("out", 0))])
	await _after_return_checks(hub)


func _do_quick_exit(hub: Node) -> void:
	# 进图马上用 main._return_to_hall（主城 / 洞府界面上的「回城」同款入口），看回城后状态
	var p := pl()
	await hold_key(KEY_W, 1.0)
	set_meta("held_w", true)
	key(KEY_W, true)        # 按着 W 回城
	m.call("_return_to_hall")
	var home: bool = await _back_home(hub, 20.0)
	await wait(0.3)
	key(KEY_W, false)
	await wait(0.6)
	var p1 := p.global_position
	await wait(1.0)
	check("按着 W 回城、松开后不卡键", home and flat_dist(p1, p.global_position) < 0.5, "回城=%s 松键后 1 秒又走了 %.2f 米" % [home, flat_dist(p1, p.global_position)])
	await _after_return_checks(hub)


func _after_return_checks(hub: Node) -> void:
	var p := pl()
	var ui: Node = m.get("level_ui")
	await wait(1.5)
	var rp: Vector3 = hub.call("return_point", 0)
	var tol := 8.0 if bool(get_meta("held_w", false)) else 4.0      # 「按着 W 回城」那一局人会往前走几步
	check("回城落点在木兰草原门前、选关没自己弹出来", flat_dist(p.global_position, rp) < tol and not bool(ui.call("is_open")) and not paused,
			"离门前落点 %.1f 米，选关开着=%s 暂停=%s 状态 %s" % [flat_dist(p.global_position, rp), ui.call("is_open"), paused, st_name()])
	# 回城后马上往前（门的方向）走一步，看会不会立刻又触发选关（落点就在门口）
	var hud: Node = m.get("hud")
	var lobby := bool(hud.get("lobby"))
	check("回城后界面是主城样式", lobby, "hud.lobby=%s" % lobby)
	var net: Node = m.get("net")
	check("单人回城后没留着联机房间", not bool(net.get("active")), "net.active=%s" % net.get("active"))
