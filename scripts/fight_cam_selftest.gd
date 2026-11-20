extends RefCounted
## 打斗镜头 / 护体受击的自检（2026-11-20）：`-- --duel-shot --spark --spark-cam [--touch] [--cam-quick]`（main.gd 的 _run_spark_demo 调 run，约 3 分钟）。
## 新旧对照：每一项先用改之前的镜头 / 护体（CameraRig.legacy_duel、air_melee.gd 的 legacy_guard）跑一遍，再用现在的跑一遍，剧本相同，打印 [cam]：
##   A 大乘连段：五段（几乎每一下都瞬步换位）+ 乱舞 + 瞬身追击两轮（空中连击 + 终结重击）
##   B 对手瞬身绕背：慢的三次（隔 1.4 秒）+ 快的四次（隔 0.45 秒，前后来回换）
##   C 护体连续受击：轻击四下 + 一记不破防的重手 —— 每一下滑退多远、状态、两人间距，累计后退；这一段的帧耗时
##   D 大乘「假玩家」和高手陪练对打（main.gd 的 _spark_duel：有瞬身、绕身、追击、互殴…）
##   E 化神 / 结丹对打各一段（只跑现在的）：低境界的镜头没被改坏
## 镜头的量（采的是跟随机位本身，不含镜头震动）：偏航累计转了多少度、最快每秒多少度、
## 「来回」次数（一段 ≥ 12° 的转动之后 1.5 秒内又反方向转 ≥ 12°）、≥ 60° 的大转次数、单帧镜头位置跳变（扣掉主角自己速度能走的）、
## 两个人都在画面里的帧占比、判到的换位次数。截图 cam_*。
## `--cam-quick` 只跑 A、B、C。故意不写 class_name：用 load 引用（写坏了不连累 main.gd 编译）。

const DUEL := "duel_"
const Combat := preload("res://scripts/combat.gd")
const AirFoe := preload("res://scripts/air_foe.gd")


class Probe:
	var rig: CameraRig
	var a: Player
	var b: Node3D
	var t := 0.0
	var travel := 0.0
	var w_max := 0.0
	var runs: Array = []          # [方向, 转了多少弧度, 起始时刻, 结束时刻]
	var run_s := 0.0
	var run_amt := 0.0
	var run_t0 := 0.0
	var run_t1 := 0.0
	var prev_yaw := 99.0
	var prev_pos := Vector3.INF
	var jump_max := 0.0
	var jumps := 0                # 单帧跳变超过 1.5 米的帧数
	var both := 0
	var frames := 0
	var swaps0 := 0
	var ms: Array = []
	var stop := false
	var skip_ms := 0              # 截图那几帧不算帧耗时
	var dbg := false
	var _dbg_t := 0.0
	var miss_a := 0
	var miss_b := 0
	var miss_run := 0.0
	var miss_max := 0.0
	var miss_ctx := {}
	var _us := 0

	func _init(r: CameraRig, pa: Player, pb: Node3D) -> void:
		rig = r
		a = pa
		b = pb
		swaps0 = r.swaps
		_us = Time.get_ticks_usec()
		dbg = OS.get_cmdline_user_args().has("--cam-debug")

	func _yaw_now() -> float:
		var f := -rig.global_transform.basis.z
		return atan2(-f.x, -f.z)

	func _seen(n: Node3D, vp: Rect2) -> bool:
		if not is_instance_valid(n):
			return false
		var c: Vector3 = n.call("center") if n.has_method("center") else n.global_position
		var cam := rig.cam
		return not cam.is_position_behind(c) and vp.grow(-8.0).has_point(cam.unproject_position(c))

	func tick(dt: float, vp: Rect2) -> void:
		var now := Time.get_ticks_usec()
		var real := float(now - _us) * 1e-6
		if skip_ms > 0:
			skip_ms -= 1
		else:
			ms.append(real * 1000.0)
		_us = now
		if dt <= 0.0:
			return
		t += dt
		var y := _yaw_now()
		var p := rig.global_transform.origin
		if prev_yaw < 98.0 and t > 0.15:
			var dy := wrapf(y - prev_yaw, -PI, PI)
			travel += absf(dy)
			var w := absf(dy) / maxf(real, 0.004)     # 按真实时间算（慢动作里游戏时间的 dt 很小，会把转速放大好几倍）
			if real < 0.1:
				w_max = maxf(w_max, w)
			if w > 0.5:
				var s := signf(dy)
				if s != run_s:
					_close()
					run_s = s
					run_t0 = t
				run_amt += absf(dy)
				run_t1 = t
			var jmp := p.distance_to(prev_pos) - a.velocity.length() * dt
			jump_max = maxf(jump_max, jmp)
			if jmp > 1.5:
				jumps += 1
		prev_yaw = y
		prev_pos = p
		frames += 1
		var sa := _seen(a, vp)
		var sb := _seen(b, vp)
		if sa and sb:
			both += 1
			miss_run = 0.0
		else:
			miss_a += 0 if sa else 1
			miss_b += 0 if sb else 1
			miss_run += real
			miss_max = maxf(miss_max, miss_run)
			var ctx := "%s%s/%s" % ["" if sa else "主角出画 ", a.air.state_name(), str(b.call("state_name")) if b.has_method("state_name") else ""]
			miss_ctx[ctx] = int(miss_ctx.get(ctx, 0)) + 1
		if dbg:
			_dbg_t += dt
			if _dbg_t >= 0.2:
				_dbg_t = 0.0
				var dd: Vector3 = (b.call("center") as Vector3) - a.center()
				print("[camdbg] t=%.2f hold=%.2f idle=%.2f yaw=%.2f yaw_v=%.2f duel=%s lock=%s turn=%s swing=%.0f 主角「%s」 e=%.2f dh=%.2f lk=%.2f calm=%.2f" % [t, float(rig.get("_hold")), float(rig.get("_mouse_idle")),
						rig.yaw, float(rig.get("_yaw_v")), rig.duel, rig.lock != null, rig.lock_turn, float(rig.get("_swing")), a.air.state_name(),
						wrapf(atan2(-dd.x, -dd.z) - rig.yaw, -PI, PI), Vector2(dd.x, dd.z).length(), float(rig.get("_lock_k")), float(rig.get("_calm"))])

	func _close() -> void:
		if run_amt > deg_to_rad(12.0):
			runs.append([run_s, run_amt, run_t0, run_t1])
		run_amt = 0.0

	func report(tag: String) -> String:
		_close()
		var back := 0
		var big := 0
		for i in runs.size():
			var r: Array = runs[i]
			if float(r[1]) >= deg_to_rad(60.0):
				big += 1
			if i > 0:
				var q: Array = runs[i - 1]
				if float(r[0]) != float(q[0]) and float(r[2]) - float(q[3]) < 1.5:
					back += 1
		var seq: Array = []
		for r: Array in runs:
			seq.append("%s%d" % ["左" if float(r[0]) > 0.0 else "右", int(rad_to_deg(float(r[1])))])
		var ctx_s: Array = []
		for k: String in miss_ctx.keys():
			ctx_s.append("%s×%d" % [k, int(miss_ctx[k])])
		print("[cam]    出画：主角 %d 帧、对手 %d 帧，最长连续 %.2fs；出画时 %s" % [miss_a, miss_b, miss_max, "  ".join(ctx_s.slice(0, 8))])
		return "%s：%.1f 秒 偏航累计 %d° 最快 %d°/s 来回 %d 次 大转(≥60°) %d 次 单帧跳变最大 %.2fm（>1.5m 的 %d 帧）两人都在画面里 %d%% 判到换位 %d 次｜转动序列 %s" % [
				tag, t, int(rad_to_deg(travel)), int(rad_to_deg(w_max)), back, big, jump_max, jumps,
				int(100.0 * float(both) / maxf(float(frames), 1.0)), rig.swaps - swaps0, " ".join(seq)]

	func frame_ms() -> String:
		if ms.is_empty():
			return "-"
		var s := ms.duplicate()
		s.sort()
		var tot := 0.0
		for v: float in s:
			tot += v
		return "帧耗时 平均 %.1fms 中位 %.1fms 最长 %.1fms（%d 帧）" % [tot / float(s.size()), float(s[s.size() / 2]), float(s[s.size() - 1]), s.size()]


## 截图（--headless 没有画面、frame_post_draw 不会来：跳过，免得卡住）
static func _shot(main: Node, tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await main._shot(tag)


static func _sample(main: Node, pr: Probe) -> void:
	var tree: SceneTree = main.get_tree()
	var vp: Rect2 = main.get_viewport().get_visible_rect()
	while not pr.stop:
		await tree.process_frame
		if Combat.hold:
			pr.skip_ms = 3
		else:
			pr.tick(main.get_process_delta_time(), vp)


static func _legacy(main: Node, on: bool) -> void:
	var cam: CameraRig = main.cam
	var player: Player = main.player
	cam.legacy_duel = on
	player.air.legacy_guard = on


static func run(main: Node) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var quick := OS.get_cmdline_user_args().has("--cam-quick")
	var touch := OS.get_cmdline_user_args().has("--touch")
	print("[cam] 打斗镜头 / 护体受击自检（%s）" % ["触屏 / 手机画质档" if touch else "键鼠"])
	cam.lock_turn = true
	var foe: AirFoe = main.foe
	var rival: AirFoe = main.rival
	foe.ai_enabled = false
	rival.ai_enabled = false
	player.set_realm(7, false)      # 大乘：连段每一下都瞬步换位、乱舞七下
	await main._wait(0.5)
	for legacy: bool in [true, false]:
		_legacy(main, legacy)
		var tag := "旧" if legacy else "新"
		var pa: Probe = await _combo(main, legacy)
		print("[cam] A 大乘连段（%s）%s" % [tag, pa.report("")])
		await main._wait(1.0)
		var pb: Probe = await _swaps(main, legacy)
		print("[cam] B 对手瞬身绕背（%s）%s" % [tag, pb.report("")])
		await main._wait(1.0)
		await _guard_chain(main, legacy)
		await main._wait(1.0)
	_legacy(main, false)
	await _fx_cost(main)
	if not quick:
		for legacy: bool in [true, false]:
			_legacy(main, legacy)
			var tag2 := "old" if legacy else "new"
			player.set_realm(7, false)
			var pd: Probe = await _duel(main, rival, 20.0, "cam_duel_" + tag2)
			print("[cam] D 大乘对打 20 秒（%s）%s" % ["旧" if legacy else "新", pd.report("")])
			await main._wait(1.0)
		_legacy(main, false)
		player.set_realm(4, false)
		var pe: Probe = await _duel(main, rival, 12.0, "cam_duel_huashen")
		print("[cam] E 化神对打 12 秒（新）%s" % pe.report(""))
		await main._wait(1.0)
		player.set_realm(2, false)
		var pf: Probe = await _duel(main, foe, 10.0, "cam_duel_jiedan")
		print("[cam] E 结丹对打 10 秒（新）%s" % pf.report(""))
	print("[cam] 完")


## A：大乘五段 + 乱舞 + 两轮瞬身追击（照着 main.gd 高速格斗自检第 1 项的按法）
static func _combo(main: Node, legacy: bool) -> Probe:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var sb: AirFoe = main.sandbag
	sb.demo_reset(Vector3(-9.0, 18.0, -13.0))
	main._spark_setup(sb, 5.0, 6.5)
	cam.lock_turn = true
	cam.snap(0.0, -0.2, 6.5)
	await main._wait(0.6)
	var pr := Probe.new(cam, player, sb)
	_sample(main, pr)
	for i in 5:
		air.press_attack()
		await main._wait_until(func() -> bool: return int(air.state) == Player.AirMelee.A.ATTACK and air.step == i and air._hit_done, 2.5)
		await main._wait(0.03)
		if i == 3 and not legacy:
			await _shot(main, DUEL + "cam_a_combo")
	await main._wait_until(func() -> bool: return sb.is_launched(), 2.5)
	for rnd in 2:
		air.press_attack()
		await main._wait_until(func() -> bool: return air.move_id == "j1" and air._hit_done, 1.5)
		for j: String in ["j2", "j3"]:
			await main._wait(0.03)
			air.press_attack()
			await main._wait_until(func() -> bool: return air.move_id == j and air._hit_done, 1.5)
		await main._wait(0.03)
		air.press_attack()
		await main._wait_until(func() -> bool: return int(air.state) == Player.AirMelee.A.SMASH and air._hit_done, 1.5)
		await main._wait(0.12)
	await main._wait(1.8)       # 打完：看它怎么回正
	if not legacy:
		await _shot(main, DUEL + "cam_a_after")
	pr.stop = true
	return pr


## B：对手连着瞬身绕到主角背后、停在那儿（只看镜头：绕过去之后把它的反打收掉）。慢的三次每次都该平稳转过去一次；快的四次（前后来回）该按住不跟着甩
static func _swaps(main: Node, legacy: bool) -> Probe:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var e: AirFoe = main.rival
	e.hp_max = 99999.0
	e.demo_reset(player.global_position + Vector3(0.0, 0.0, -4.0))
	main._spark_setup(e, 4.0, 7.0)
	cam.lock_turn = true
	cam.snap(0.0, -0.2, 7.0)
	await main._wait(0.6)
	var pr := Probe.new(cam, player, e)
	_sample(main, pr)
	for k in 7:
		e.mp = 999.0
		e.call("_vanish_behind")
		e.home = e.global_position      # 停在绕过去的地方（不然 AI 关着时它会飘回原位，镜头就不用转了）
		e.call("_enter", AirFoe.S.IDLE, 0.0)
		e.rig.play("f_idle")
		player.melee.hp = 100.0
		await main._wait(1.4 if k < 3 else 0.45)
		if k == 4 and not legacy:
			await _shot(main, DUEL + "cam_b_swaps")
	await main._wait(1.8)
	pr.stop = true
	return pr


## C：护体连续受击 —— 轻击四下 + 一记不破防的重手（侧面机位看滑退）
static func _guard_chain(main: Node, legacy: bool) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var e: AirFoe = main.foe
	var tag := "旧" if legacy else "新"
	e.hp_max = 99999.0
	e.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.6))
	main._spark_setup(e, 2.6, 7.5)
	cam.lock_turn = false
	cam.snap(PI * 0.5, -0.12, 8.0)
	await main._wait(0.6)
	air.press_guard()
	await main._wait(0.35)
	var pr := Probe.new(cam, player, e)
	_sample(main, pr)
	var p_start := player.global_position
	var sep_max := 0.0
	for i in 5:
		var heavy := i == 4
		player.melee.hp = 100.0
		player.mp = player.mp_max()
		e.set("_string", 1)
		e.call("_begin_windup", 0.3, heavy, false)
		var ok: bool = await main._wait_until(func() -> bool: return e.state == AirFoe.S.STRIKE and bool(e.get("_hit_done")), 2.0)
		var p0 := player.global_position
		var dir := player.center() - e.center()
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.BACK
		if heavy:
			await main._wait(0.07)
			await _shot(main, DUEL + "cam_c_guard_%s" % ("old" if legacy else "new"))
		var tt := 0.0
		var peak := 0.0
		while tt < 0.4:
			await main.get_tree().process_frame
			tt += main.get_process_delta_time()
			peak = maxf(peak, (player.global_position - p0).dot(dir))
			sep_max = maxf(sep_max, player.center().distance_to(e.center()))
		print("[cam] C 护体受击（%s）第 %d 下%s：判定=%s 结果 %d（1 = 挡下）滑退 %.2fm 状态「%s」两人相距 %.1fm" % [tag, i + 1, "（重手）" if heavy else "",
				ok, int(e.get("_last_res")), peak, air.state_name(), player.center().distance_to(e.center())])
	var back := player.global_position - p_start
	back.y = 0.0
	pr.stop = true
	print("[cam] C 护体受击（%s）五下累计后退 %.2fm，最远相距 %.1fm；%s" % [tag, back.length(), sep_max, pr.frame_ms()])
	air.release_guard()
	cam.lock_turn = true


## D / E：假玩家和 e 对打 secs 秒（main.gd 的 _spark_duel），同时采镜头
static func _duel(main: Node, e: AirFoe, secs: float, tag: String) -> Probe:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var pr := Probe.new(cam, player, e)
	_sample(main, pr)
	await main._spark_duel(e, secs, tag)
	pr.stop = true
	e.ai_enabled = false
	return pr


## C2：护体受击特效的开销 —— 同一个进程里新旧轮流放（各两轮、每轮 2.5 秒、每 0.25 秒挡一下），比帧耗时。
## 跨进程 / 隔一段时间比不可信（这台机器的显卡常被别的窗口占着），所以交替测
static func _fx_cost(main: Node) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var e: AirFoe = main.foe
	e.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.6))
	main._spark_setup(e, 2.6, 7.5)
	cam.lock_turn = false
	cam.snap(PI * 0.5, -0.12, 8.0)
	await main._wait(0.5)
	air.press_guard()
	await main._wait(0.3)
	var home := player.global_position
	var res := {"old": [], "new": []}
	for round_i in 3:
		for mode: String in ["new", "old"]:
			air.legacy_guard = mode == "old"
			player.global_position = home
			player.velocity = Vector3.ZERO
			var tree: SceneTree = main.get_tree()
			var t := 0.0
			var next := 0.0
			var us := Time.get_ticks_usec()
			var n := 0
			while t < 2.5:
				if t >= next:
					next += 0.25
					player.mp = player.mp_max()
					player.melee.hp = 100.0
					var heavy := n % 4 == 3
					n += 1
					var dir := player.center() - e.center()
					dir.y = 0.0
					dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.BACK
					air.receive_attack(e, {"dmg": 6.0, "heavy": heavy, "brk": false, "kb": 6.0, "dir": dir, "contact": e.center() + dir * 0.9})
				await tree.process_frame
				var now := Time.get_ticks_usec()
				t += main.get_process_delta_time()
				if round_i > 0:      # 第一轮只当预热（头一次放的特效要现编着色器）
					(res[mode] as Array).append(float(now - us) * 0.001)
				us = now
	air.legacy_guard = false
	air.release_guard()
	for mode: String in ["old", "new"]:
		var a: Array = res[mode]
		a.sort()
		var tot := 0.0
		for v: float in a:
			tot += v
		var nn := maxi(a.size(), 1)
		print("[cam] C2 护体受击特效开销（%s，每 0.25 秒挡一下、每四下一记重手，交替两轮）：帧耗时 平均 %.1fms 中位 %.1fms 九成 %.1fms 最长 %.1fms（%d 帧）" % [
				"旧" if mode == "old" else "新", tot / float(nn), float(a[a.size() / 2]) if a.size() > 0 else 0.0,
				float(a[int(a.size() * 0.9)]) if a.size() > 0 else 0.0, float(a[a.size() - 1]) if a.size() > 0 else 0.0, a.size()])
	cam.lock_turn = true
