extends RefCounted
## 近战穿模自检：`-- --duel-shot --spark --spark-clip [--touch] [--clip-quick] [--clip-mobs=10,12]`（main.gd 的 _run_spark_demo 调 run），打印 [clip]。
## 在试剑台里直接摆大世界的怪（raid_mob.gd），逐只量「主角的身体陷进怪的模型多深」：
##   怪的身体 = 模型待机姿势的包围盒（水平方向收一成半，角上是空的）；主角 = 脚底往上 0.35 / 0.95 / 1.5 米三个点，各带 0.3 米的身体半径。
##   深度 > 0 = 身体进了模型；报最深多少米、超过 0.25 米（看得出穿模）的帧占多少。
## 每只怪四段：
##   1 怪定住、主角从正面打一套五连（结丹：追身突进 + 贴身出拳）
##   2 怪定住、合体期从正面打一套（每一下瞬步换位 + 乱舞，落点绕着怪一圈）
##   3 怪放开来打主角 6 秒，主角悬着不动（怪扑过来会不会整个盖住人）
##   4 炼气在地面对着怪砍三下（够不够得着、踏步会不会踩进模型）
## 故意不写 class_name：用 load 引用。

const Mob := preload("res://scripts/raid_mob.gd")
const RaidData := preload("res://scripts/raid_data.gd")
const VISIBLE := 0.25
const Combat := preload("res://scripts/combat.gd")


static func _shot(main: Node, tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await main._shot(tag)


static func _spawn(main: Node, idx: int, pos: Vector3) -> Node3D:
	var m := Mob.new()
	m.player = main.player
	m.def = RaidData.MOBS[idx]
	m.region = 0
	m.lv = 1
	m.elite = false
	m.hp_max = 9.0e6
	m.atk = 0.5
	m.xp_k = 0.0
	m.floor_fn = func(_x: float, _z: float) -> float: return 0.0
	m.position = pos
	main.add_child(m)
	return m


## 主角的身体陷进怪模型多深（米；≤ 0 = 没碰到，没有模型的怪返回 -9）
static func depth(m: Node3D, player: Node3D) -> float:
	var md: Dictionary = m.get("_model")
	if md.is_empty():
		return -9.0
	var root: Node3D = md["root"]
	var bb: AABB = md["aabb"]
	var xf := root.global_transform
	var inv := xf.affine_inverse()
	var sc := xf.basis.get_scale()
	var c := bb.get_center()
	var h := bb.size * 0.5
	var best := -9.0
	for y: float in [0.35, 0.95, 1.5]:
		var lp: Vector3 = inv * (player.global_position + Vector3(0.0, y, 0.0)) - c
		var d := minf((h.x * 0.85 - absf(lp.x)) * sc.x, minf((h.y - absf(lp.y)) * sc.y, (h.z * 0.85 - absf(lp.z)) * sc.z)) + 0.3
		best = maxf(best, d)
	return best


## 采样 secs 秒：返回 [最深, 超过 VISIBLE 的帧占比]
static func _sample(main: Node, m: Node3D, secs: float, until := Callable()) -> Array:
	var worst := -9.0
	var bad := 0
	var n := 0
	var t := 0.0
	while t < secs:
		await main.get_tree().process_frame
		t += main.get_process_delta_time()
		if not is_instance_valid(m):
			break
		var d := depth(m, main.player)
		worst = maxf(worst, d)
		n += 1
		if d > VISIBLE:
			bad += 1
		if until.is_valid() and bool(until.call()):
			break
	return [worst, float(bad) / float(maxi(n, 1))]


static func _fmt(r: Array) -> String:
	return "%+.2fm / %d%%" % [float(r[0]), int(round(float(r[1]) * 100.0))]


static func run(main: Node) -> void:
	var player: Player = main.player
	var air: Variant = player.air
	var cam: CameraRig = main.cam
	var args := OS.get_cmdline_user_args()
	cam.lock_turn = true
	for e: Variant in [main.foe, main.rival, main.sandbag, main.duelist]:
		if is_instance_valid(e):
			if e.get("ai_enabled") != null:
				e.set("ai_enabled", false)
			if e.has_method("demo_reset") and e != main.duelist:
				e.call("demo_reset", Vector3(120.0, 0.0, 120.0))
			elif e == main.duelist:
				(e as Node3D).global_position = Vector3(-120.0, 0.0, 120.0)
	var list: Array = [0, 5, 7, 10, 11, 12, 13, 14]
	if args.has("--clip-quick"):
		list = [0, 10, 11, 12]
	for a: String in args:
		if a.begins_with("--clip-mobs="):
			list = []
			for part: String in a.get_slice("=", 1).split(","):
				list.append(int(part))
	print("[clip] 渲染器 %s；深度 = 主角身体陷进怪模型多少米（正数才算进去了），后面是看得出穿模（> %.2f 米）的帧占比" % [RenderingServer.get_current_rendering_method(), VISIBLE])
	# 和别的空战自检同一块空地：出生点往 -Z 方向十几米内没有柱子
	main._home()
	await main._wait(0.2)
	var home: Vector3 = player.global_position
	home.y = 0.0
	var sum := {"结丹五连": [], "合体连段": [], "怪打主角": [], "地面走近": [], "地面三斩": []}
	for idx: int in list:
		var def: Dictionary = RaidData.MOBS[idx]
		var nm := str(def["name"])
		# ---- 1 / 2：怪定住，主角从正面打 ----
		var res := {}
		for ri: int in [2, 6]:
			var m := _spawn(main, idx, home + Vector3(0.0, 0.0, -14.0))
			await main.get_tree().process_frame
			m.set("_facing", PI)          # 脸朝主角（+Z）
			m.rotation.y = PI
			m.set_process(false)
			player.set_realm(ri, false)
			player.force_ground()
			player.global_position = home
			player.velocity = Vector3.ZERO
			player.face_now(0.0)
			await main._wait(0.3)
			for k in 4:
				# 上一段地面挥砍的收招里起不了飞：等到真的腾空为止
				if player.st == Player.St.AIR:
					break
				player.take_air()
				await main._wait(0.9)
			player.global_position = home + Vector3(0.0, float(m.get("_mid")) - 0.95, 0.0)
			cam.snap(0.6, CameraRig.PITCH_DEFAULT, 9.0)
			air.target = m
			air._engage = 99.0
			cam.lock = m          # 试剑台里到处是木人桩：锁住这只怪，不然起手会挑最近的木人
			var hp0: float = float(m.hp)
			var worst := -9.0
			var bad := 0.0
			var frames := 0.0
			for i in 5:
				air.press_attack()
				var r: Array = await _sample(main, m, 2.5, func() -> bool: return air.state == Player.AirMelee.A.ATTACK and air.step == i and air._hit_done)
				worst = maxf(worst, float(r[0]))
				bad += float(r[1])
				frames += 1.0
				if args.has("--clip-debug"):
					print("[clip]   %s 境界 %d 第 %d 下：主角「%s」%s step %d 命中=%s 怪还在=%s 距怪心 %.1fm 深度 %.2f 目标=%s" % [nm, ri, i, air.state_name(), player.state_text(), air.step,
							air._hit_done, is_instance_valid(m), player.center().distance_to(m.call("center")) if is_instance_valid(m) else -1.0, float(r[0]), air.target])
				if i == 2 and ri == 2:
					await _shot(main, "duel_clip_%02d_%s_air" % [idx, nm])
				var r2: Array = await _sample(main, m, 0.14)
				worst = maxf(worst, float(r2[0]))
			var tail: Array = await _sample(main, m, 0.6)
			worst = maxf(worst, float(tail[0]))
			var rr := [worst, bad / maxf(frames, 1.0)]
			res[ri] = [rr, hp0 - float(m.hp), float(m.call("hit_radius")), Player.AirMelee.STICK]
			(sum["结丹五连" if ri == 2 else "合体连段"] as Array).append(worst)
			air.target = null
			cam.lock = null
			m.queue_free()
			await main._wait(0.5)
		# ---- 3：怪放开来打主角，主角悬着不动 ----
		player.set_realm(2, false)
		player.global_position = home + Vector3(0.0, 0.3, 0.0)
		if player.st != Player.St.AIR:
			player.take_air()
			await main._wait(0.9)
		var m3 := _spawn(main, idx, home + Vector3(0.0, 0.0, -9.0))
		await main.get_tree().process_frame
		m3.call("alert")
		m3.set("_cd", 0.3)
		player.melee.hp = 100.0
		var dbg := [0]
		var hits := [0]
		var keep := func() -> bool:
			if player.melee.hp < 99.9:
				hits[0] = int(hits[0]) + 1       # 怪这一下打中了（穿模修了，不能把怪修得打不着人）
			player.melee.hp = 100.0
			if args.has("--clip-debug") and int(dbg[0]) < 14 and is_instance_valid(m3) and depth(m3, player) > VISIBLE:
				dbg[0] = int(dbg[0]) + 1
				var pp := player.global_position
				var mp: Vector3 = m3.global_position
				print("[clip]   %s 深 %.2f：怪状态 %d 顿帧=%s 水平距 %.2f 表面 %.2f 主角脚 %.2f 怪脚 %.2f 顶 %.2f 遁光=%s 冲刺=%s 主角「%s」" % [nm, depth(m3, player), int(m3.get("state")),
						Combat.frozen(), Vector2(pp.x - mp.x, pp.z - mp.z).length(), float(m3.call("body_reach", pp)), pp.y, mp.y, mp.y + float(m3.get("_top")),
						player.dun_active, player.is_dashing(), air.state_name()])
			return false
		var r3: Array = await _sample(main, m3, 6.0, keep)
		await _shot(main, "duel_clip_%02d_%s_mob" % [idx, nm])
		(sum["怪打主角"] as Array).append(float(r3[0]))
		m3.queue_free()
		await main._wait(0.4)
		# ---- 4：炼气在地面砍三下 ----
		player.set_realm(0, false)
		player.force_ground()
		player.global_position = home + Vector3(0.0, 0.1, 0.0)
		player.velocity = Vector3.ZERO
		player.face_now(0.0)
		var m4 := _spawn(main, idx, home + Vector3(0.0, 0.0, -7.0))
		await main.get_tree().process_frame
		m4.set("_facing", PI)
		m4.rotation.y = PI
		# 怪照常活动（会转身、会让路 / 顶人），只是不出手
		var calm := func() -> bool:
			if is_instance_valid(m4):
				m4.set("_cd", 9.0)
				m4.set("_slam_cd", 9.0)
			player.melee.hp = 100.0
			return false
		await main._wait(0.4)
		# 按住前进 2.2 秒：一直往怪身上顶
		Input.action_press("move_forward")
		cam.snap(0.0, CameraRig.PITCH_DEFAULT, 8.0)
		var walk: Array = await _sample(main, m4, 2.2, calm)
		Input.action_release("move_forward")
		var hp4: float = float(m4.hp)
		var w4 := float(walk[0])
		var a4 := -9.0
		for i in 3:
			player.melee.press_attack()
			var r4: Array = await _sample(main, m4, 0.55, calm)
			a4 = maxf(a4, float(r4[0]))
		await _shot(main, "duel_clip_%02d_%s_ground" % [idx, nm])
		var dist4 := Vector2(player.global_position.x - m4.global_position.x, player.global_position.z - m4.global_position.z).length()
		(sum["地面走近"] as Array).append(w4)
		(sum["地面三斩"] as Array).append(a4)
		var hit4: float = hp4 - float(m4.hp)
		m4.queue_free()
		await main._wait(0.4)
		print("[clip] %s（体型 %.2f，判定半径 %.2fm）：结丹五连 %s 打掉 %d ｜ 合体连段 %s 打掉 %d ｜ 怪打主角 %s 打中 %d 次 ｜ 地面按住前进 2.2 秒 %+.2fm，三斩 %+.2fm 打掉 %d，最后离怪心 %.1fm" % [nm,
				float(def["size"]), float((res[2] as Array)[2]), _fmt((res[2] as Array)[0]), int((res[2] as Array)[1]), _fmt((res[6] as Array)[0]), int((res[6] as Array)[1]),
				_fmt(r3), int(hits[0]), w4, a4, int(hit4), dist4])
	for k: String in sum:
		var arr: Array = sum[k]
		var mx := -9.0
		var over := 0
		for v: float in arr:
			mx = maxf(mx, v)
			if v > VISIBLE:
				over += 1
		print("[clip] 汇总 %s：最深 %+.2fm，%d / %d 只怪看得出穿模" % [k, mx, over, arr.size()])
	print("[clip] 完")
