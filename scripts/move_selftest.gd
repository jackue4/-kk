extends RefCounted
## 关卡里地形移动的自检（2026-11-20）：`-- --raid-shot --raid-move [--move-old] [--touch]`（main.gd 的 _run_raid_demo 调 run）。
## 在出生点附近找一块够高的地，用 block_world.gd 的 dig 挖出一条已知形状的测试道（只降不升，所以台阶从原地面往下挖）：
##   A 道：平地 → 七级一米的台阶（= 坡面）→ 平台          B 道：平地 → 三级两米的台阶 → 一级一米 → 平台
##   C 道：平地 → 七米高墙                               D 道：平地 → 三米矮墙（跳起来够得着沿）
## 主角是炼气（没有腾空空战的最低境界），用真实的输入动作（move_forward / jump / fly / sprint）走：
##   1 A 道走上去、走下来、疾行上去   2 B 道上、下   3 顶着七米墙走四秒   4 连点两下跳 → 起飞 → 飞过七米墙 → 落地
##   5 对着三米墙边走边跳 → 翻上去   6 贴地御剑撞七米墙
## 每一趟按渲染帧记主角的高度（画面上每一帧看到的位置），打印：单帧最大竖直位移、跳变帧数（一帧动了 0.25 米以上）、有没有到该到的地方；
## 顶墙那趟另外看：升了多高（应为 0）、被墙挡住记了几次（一直顶着应只记一次）。
## `--move-old` 把 meadow_level.gd 切回改之前的落脚逻辑（step_old），同一条测试道再走一遍，做前后对比。
## 故意不写 class_name：用 load 引用（写坏了不连累 main.gd 编译）。

const F_DROP := 7          # 测试道最低处比原地面低几米


static func _tap(tree: SceneTree, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	await tree.physics_frame
	await tree.physics_frame
	var ev2 := InputEventAction.new()
	ev2.action = action
	ev2.pressed = false
	Input.parse_input_event(ev2)


## 走 secs 秒，按物理帧记录；返回 {ys, xs, st}
static func _walk(main: Node, secs: float, each := Callable()) -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var player: Player = main.player
	var ys := PackedFloat32Array()
	var xs := PackedFloat32Array()
	var sts: Array = []
	var dbg: Array = []
	var t := 0.0
	while t < secs:
		await tree.process_frame          # 渲染帧开始前：上一帧主角走完、关卡也摆完之后的位置（画面上看到的就是它）
		t += main.get_process_delta_time()
		player.melee.hp = 100.0
		ys.append(player.global_position.y)
		xs.append(player.global_position.x)
		dbg.append("z%.2f %s vy%.1f" % [player.global_position.z, "地" if player.is_on_floor() else "空", player.velocity.y])
		if sts.is_empty() or int(sts[sts.size() - 1]) != int(player.st):
			sts.append(int(player.st))
		if each.is_valid():
			each.call(t)
	return {"ys": ys, "xs": xs, "st": sts, "dbg": dbg}


## 调试：最大那一下跳变前后几帧
static func _dump(r: Dictionary, x0: float, y0: float) -> String:
	var ys: PackedFloat32Array = r["ys"]
	var xs: PackedFloat32Array = r["xs"]
	var bi := 1
	for i in range(1, ys.size()):
		if absf(ys[i] - ys[i - 1]) > absf(ys[bi] - ys[bi - 1]):
			bi = i
	var out: Array = []
	for i in range(maxi(bi - 4, 0), mini(bi + 4, ys.size())):
		out.append("x%.2f y%.2f %s" % [xs[i] - x0, ys[i] - y0, str((r["dbg"] as Array)[i])])
	return " | ".join(out)


static func _dx(r: Dictionary) -> float:
	var xs: PackedFloat32Array = r["xs"]
	return xs[xs.size() - 1] - xs[0] if xs.size() > 1 else 0.0


## [单帧最大竖直位移, 原地拔高的帧数（水平没怎么动、竖直却动了 0.2 米以上 = 一帧跳一格那种）]
static func _stats(ys: PackedFloat32Array, xs := PackedFloat32Array()) -> Array:
	var mx := 0.0
	var pops := 0
	for i in range(1, ys.size()):
		var d := absf(ys[i] - ys[i - 1])
		mx = maxf(mx, d)
		var dx := absf(xs[i] - xs[i - 1]) if xs.size() == ys.size() else 1.0
		if d > 0.2 and d > dx * 3.0:
			pops += 1
	return [mx, pops]


static func _place(main: Node, pos: Vector3, yaw: float) -> void:
	var player: Player = main.player
	Input.action_release("move_forward")
	Input.action_release("sprint")
	player.force_ground()
	player._shift_t = 0.0
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.face_now(yaw)
	main.cam.snap(yaw, CameraRig.PITCH_DEFAULT, 6.5)
	await main._wait(0.35)


static func run(main: Node) -> void:
	var rd: Variant = main.level.raid
	var level: Variant = main.level
	var player: Player = main.player
	var tree: SceneTree = main.get_tree()
	var world: Variant = level.world
	var old := OS.get_cmdline_user_args().has("--move-old")
	(level.get_script() as GDScript).set("step_old", old)
	const ST := ["地面", "起飞", "飞行", "空战", "俯冲"]
	# 清场：不要怪
	rd._wave_t = 99999.0
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()
	rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_realm(0, false)
	# 找一块 16×12 格、最低处也有 F_DROP + 2 米高的地（往下挖得出台阶）
	var cs := 2.0
	var ox := 0.0
	var oz := 0.0
	var hmin := -1.0
	var found := false
	for ring in range(1, 40):
		for k in 8:
			var a := TAU * float(k) / 8.0 + float(ring) * 0.37
			var cx := floorf(cos(a) * float(ring) * 24.0 / cs) * cs
			var cz := floorf(sin(a) * float(ring) * 24.0 / cs) * cs
			var lo := 1.0e9
			for i in 16:
				for j in 16:
					lo = minf(lo, float(world.height(cx + (float(i) + 0.5) * cs, cz + (float(j) + 0.5) * cs)))
			if lo >= float(F_DROP) + 2.0:
				ox = cx
				oz = cz
				hmin = lo
				found = true
				break
		if found:
			break
	if not found:
		print("[move] 没找到够高的地方挖测试道")
		return
	var f0 := hmin - float(F_DROP)
	await main._raid_goto(Vector2(ox + 4.0, oz + 2.0), 0.0)
	# 挖：每格 [列, 行] → 地面高度；没列出的保持原样（都 ≥ hmin，是墙）
	var plan := {}
	for c in 16:
		var ha := f0 + clampf(float(c - 2), 0.0, 7.0)                       # A：c=3..9 每格 +1
		var hb := f0 + (0.0 if c < 3 else (2.0 * float(mini(c - 2, 3)) + (1.0 if c >= 6 else 0.0)))   # B：+2 +2 +2 +1
		var hc := f0 if c < 6 else hmin                                      # C：七米墙
		var hd := f0 if c < 6 else f0 + 3.0                                  # D：三米墙
		for r: Array in [[0, ha], [1, ha], [2, ha], [4, hb], [5, hb], [6, hb], [8, hc], [9, hc], [10, hc], [12, hd], [13, hd], [14, hd]]:
			plan[Vector2i(c, int(r[0]))] = float(r[1])
	var bad := 0
	for key: Vector2i in plan.keys():
		var px := ox + (float(key.x) + 0.5) * cs
		var pz := oz + (float(key.y) + 0.5) * cs
		world.dig(Vector3(px, 0.0, pz), 0.9, float(plan[key]))
		if absf(float(world.height(px, pz)) - float(plan[key])) > 0.01:
			bad += 1
	print("[move] %s｜测试道挖在 (%.0f, %.0f)，原地面最低 %.0f 米，道底 %.0f 米；%d 格里有 %d 格高度不对；主角 %s期，物理帧 %d 次/秒" % [
			"改之前的逻辑（--move-old）" if old else "新逻辑", ox, oz, hmin, f0, plan.size(), bad, player.realm["name"], Engine.physics_ticks_per_second])
	await main._wait(1.0)
	var lane := func(row: float, col: float, y: float) -> Vector3:
		return Vector3(ox + col * cs, y + 0.05, oz + (row + 1.5) * cs)      # 每条道三格宽，站在中间那格的正中
	var east := -PI * 0.5        # 朝 +X
	var west := PI * 0.5
	# ---- 1 A 道：一米台阶 ----
	await _place(main, lane.call(0.0, 1.0, f0), east)
	Input.action_press("move_forward")
	var r1: Dictionary = await _walk(main, 5.2)
	Input.action_release("move_forward")
	var s1 := _stats(r1["ys"], r1["xs"])
	print("[move] 1 上七级一米台阶（走）：升了 %.1f 米（应 7），单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [player.global_position.y - f0, float(s1[0]), int(s1[1])])
	await _place(main, lane.call(0.0, 11.0, hmin), west)
	Input.action_press("move_forward")
	var r2: Dictionary = await _walk(main, 5.2)
	Input.action_release("move_forward")
	var s2 := _stats(r2["ys"], r2["xs"])
	print("[move] 1 下七级一米台阶（走）：降了 %.1f 米（应 7），单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [hmin - player.global_position.y, float(s2[0]), int(s2[1])])
	await _place(main, lane.call(0.0, 1.0, f0), east)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var r3: Dictionary = await _walk(main, 3.2, func(_t: float) -> void: player._shift_t = 1.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var s3 := _stats(r3["ys"], r3["xs"])
	print("[move] 1 上七级一米台阶（疾行，3.2 秒走了 %.0f 米）：升了 %.1f 米，单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [
			_dx(r3), player.global_position.y - f0, float(s3[0]), int(s3[1])])
	await main._shot("move_1_stairs")
	# ---- 2 B 道：两米台阶 ----
	await _place(main, lane.call(4.0, 1.0, f0), east)
	Input.action_press("move_forward")
	var r4: Dictionary = await _walk(main, 4.0)
	Input.action_release("move_forward")
	var s4 := _stats(r4["ys"], r4["xs"])
	if OS.get_cmdline_user_args().has("--move-dbg"):
		print("[move-dbg] oz=%.1f 道中线 z=%.1f｜" % [oz, oz + 8.0] + _dump(r4, ox, f0))
	print("[move] 2 上三级两米台阶（走）：升了 %.1f 米（应 7），单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [player.global_position.y - f0, float(s4[0]), int(s4[1])])
	await _place(main, lane.call(4.0, 9.0, hmin), west)
	Input.action_press("move_forward")
	var r5: Dictionary = await _walk(main, 4.0)
	Input.action_release("move_forward")
	var s5 := _stats(r5["ys"], r5["xs"])
	print("[move] 2 下三级两米台阶（走，水平走了 %.1f 米）：降了 %.1f 米（应 7），单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [_dx(r5), hmin - player.global_position.y, float(s5[0]), int(s5[1])])
	# ---- 3 C 道：顶着七米墙走 ----
	await _place(main, lane.call(8.0, 3.0, f0), east)
	level.set("wall_bumps", 0)
	Input.action_press("move_forward")
	var r6: Dictionary = await _walk(main, 4.0)
	Input.action_release("move_forward")
	var s6 := _stats(r6["ys"], r6["xs"])
	var wall_x := ox + 6.0 * cs
	print("[move] 3 顶着七米高墙走 4 秒：升了 %.1f 米（应 0），最后离墙 %.2f 米（没穿进去应 ≥ 0），单帧最大竖直位移 %.2f 米，原地拔高帧 %d，记了 %d 次「被墙挡住」（应 1）" % [
			player.global_position.y - f0, wall_x - player.global_position.x, float(s6[0]), int(s6[1]), int(level.get("wall_bumps"))])
	await main._shot("move_3_wall")
	# 斜着顶墙：应该沿墙滑
	await _place(main, lane.call(8.0, 4.5, f0) + Vector3(0.0, 0.0, -1.2), east - 0.6)
	Input.action_press("move_forward")
	var z0 := player.global_position.z
	await _walk(main, 1.2)
	Input.action_release("move_forward")
	print("[move] 3 斜着（偏 34 度）顶墙 1.2 秒：沿墙滑了 %.1f 米，高度变化 %.1f 米" % [absf(player.global_position.z - z0), player.global_position.y - f0])
	# ---- 4 连点两下跳起飞，飞过七米墙，落地 ----
	if not old:
		await _place(main, lane.call(8.0, 2.0, f0), east)
		var t_log: Array = []
		await _tap(tree, "jump")
		await main._wait(0.25)
		t_log.append("跳起后离地 %.1f 米（状态 %s）" % [player.global_position.y - f0, ST[int(player.st)]])
		await _tap(tree, "jump")
		await main._wait(0.15)
		t_log.append("再点一下跳 → %s" % ST[int(player.st)])
		await main._wait(0.6)
		t_log.append("0.75 秒后 %s、离地 %.1f 米" % [ST[int(player.st)], player.global_position.y - f0])
		Input.action_press("move_forward")
		var r7: Dictionary = await _walk(main, 3.0)
		Input.action_release("move_forward")
		var s7 := _stats(r7["ys"])
		t_log.append("往前飞 3 秒：过墙 %.1f 米、离道底 %.1f 米（墙高 7），单帧最大竖直位移 %.2f 米" % [player.global_position.x - wall_x, player.global_position.y - f0, float(s7[0])])
		await main._shot("move_4_fly")
		await _tap(tree, "fly")
		var r8: Dictionary = await _walk(main, 1.6)
		t_log.append("点「落」→ %s，1.6 秒后离墙顶 %.2f 米（在地面=%s）" % [ST[int(player.st)], player.global_position.y - hmin, player.is_on_floor()])
		var s8 := _stats(r8["ys"])
		print("[move] 4 炼气期连点两下跳起飞 → 飞过七米墙 → 落地：%s；落地过程单帧最大竖直位移 %.2f 米" % ["；".join(t_log), float(s8[0])])
	# ---- 5 D 道：三米墙，边走边跳 ----
	await _place(main, lane.call(12.0, 4.0, f0), east)
	Input.action_press("move_forward")
	await _walk(main, 0.25)
	await _tap(tree, "jump")
	var r9: Dictionary = await _walk(main, 1.6)
	Input.action_release("move_forward")
	var s9 := _stats(r9["ys"], r9["xs"])
	print("[move] 5 对着三米墙边走边跳：最后在 %.1f 米高（翻上去应 3）、过墙 %.1f 米，状态 %s，单帧最大竖直位移 %.2f 米，原地拔高帧 %d" % [
			player.global_position.y - f0, player.global_position.x - wall_x, ST[int(player.st)], float(s9[0]), int(s9[1])])
	# 不跳、直接走：三米墙也该挡住
	await _place(main, lane.call(12.0, 4.0, f0), east)
	Input.action_press("move_forward")
	await _walk(main, 1.5)
	Input.action_release("move_forward")
	print("[move] 5 不跳、顶着三米墙走 1.5 秒：升了 %.1f 米（应 0）" % (player.global_position.y - f0))
	# ---- 6 贴地御剑撞七米墙 ----
	await _place(main, lane.call(8.0, 1.5, f0), east)
	await _tap(tree, "fly")
	await main._wait(0.8)
	Input.action_press("move_forward")
	var r10: Dictionary = await _walk(main, 2.4)
	Input.action_release("move_forward")
	var s10 := _stats(r10["ys"], r10["xs"])
	print("[move] 6 炼气期贴地御剑（离地 %.1f 米起）撞七米墙飞 2.4 秒：过墙 %.1f 米、离道底 %.1f 米，单帧最大竖直位移 %.2f 米，原地拔高帧 %d，状态 %s" % [
			float(r10["ys"][0]) - f0, player.global_position.x - wall_x, player.global_position.y - f0, float(s10[0]), int(s10[1]), ST[int(player.st)]])
	await _tap(tree, "fly")
	await main._wait(1.2)
	print("[move] 结束：状态 %s，在地面=%s" % [ST[int(player.st)], player.is_on_floor()])
	(level.get_script() as GDScript).set("step_old", false)
