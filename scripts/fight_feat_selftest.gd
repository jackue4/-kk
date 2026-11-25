extends RefCounted
## 2026-11-21 这一轮四项改动的自检：`-- --duel-shot --spark --spark-feat [--touch]`（main.gd 的 _run_spark_demo 调 run，约 2 分钟），打印 [feat]：
##   1 远处长按「攻」：结丹 / 炼虚，木人在 22 米外。
##     点按（按 0.08 秒松手）：按着的时候没动、松手才冲过去（炼虚是缩地），量松手到出发的延迟；
##     长按：按着没冲没瞬移 → 转蓄力 → 松手高速飞过去一记重击：多久打到、最快多少、途中有没有瞬移、打没打中
##   2 拳劲对拼的空间裂缝：结丹 → 大乘各开一场（每秒点 9 下），数裂缝道数、帧耗时；截图 feat_crack_<境界下标>
##   3 飞剑打走：护体对着高手陪练的剑流，数被拨开打着旋飞走的剑、掌拨了几下、自己掉的血；气弹抽回去打中对手；截图 feat_deflect / feat_swat
##   4 对波中途别的操作：放剑诀（应被拦下、对波照常）；硬切出对波状态（模拟开大 / 瞬身这类别的路径）→ 镜头多久交还、
##     主角往外飞时还在不在画面里、对手退没退出相持；按 F 转光遁离开对波；最后用改之前的做法（不收尾）再切一次做对照
## 故意不写 class_name：用 load 引用（写坏了不连累 main.gd 编译）。

const DUEL := "duel_"
const Combat := preload("res://scripts/combat.gd")
const AirFoe := preload("res://scripts/air_foe.gd")
const Proj := preload("res://scripts/spell_projectile.gd")


static func _shot(main: Node, tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await main._shot(tag)


static func _seen(main: Node, n: Node3D) -> bool:
	var cam: CameraRig = main.cam
	var vp: Rect2 = main.get_viewport().get_visible_rect()
	var c: Vector3 = n.call("center") if n.has_method("center") else n.global_position
	return not cam.cam.is_position_behind(c) and vp.grow(-8.0).has_point(cam.cam.unproject_position(c))


static func run(main: Node) -> void:
	if OS.get_cmdline_user_args().has("--brawl-gallery"):
		# 只截图：各境界拳劲对拼的各阶段（见 _tasks/brawl_gallery/brawl_gallery.gd）
		await (load("res://_tasks/brawl_gallery/brawl_gallery.gd") as GDScript).call("run", main)
		return
	if OS.get_cmdline_user_args().has("--pvp-outline"):
		# PvP 锁定描边的自检（scripts/pvp_outline_selftest.gd，网页版也能跑）
		await (load("res://scripts/pvp_outline_selftest.gd") as GDScript).call("run", main)
		return
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var foe: AirFoe = main.foe
	var rival: AirFoe = main.rival
	foe.ai_enabled = false
	rival.ai_enabled = false
	cam.lock_turn = true
	print("[feat] 自检开始（%s）" % ["触屏 / 手机画质档" if OS.get_cmdline_user_args().has("--touch") else "键鼠"])
	# 先空打一下：自检不走载入预热，头一次放音效会卡两百多毫秒（音效库现合成），别算到点按的延迟上
	var sb := _place_far(main)
	await main._wait(0.4)
	player.air.press_attack()
	await main._wait(1.5)
	for r: int in [2, 5]:
		await _far(main, r)
	await _cracks(main)
	await _deflect(main)
	await _clash_cut(main)
	print("[feat] 完")


# ---------- 1 远处长按 ----------

static func _place_far(main: Node) -> AirFoe:
	var sb: AirFoe = main.sandbag
	sb.hp_max = 99999.0
	sb.demo_reset(Vector3(-9.0, 18.0, -13.0))
	main._spark_setup(sb, 22.0, 8.0)
	var cam: CameraRig = main.cam
	cam.lock_turn = true
	cam.snap(0.0, -0.15, 8.0)
	return sb


static func _far(main: Node, realm: int) -> void:
	var player: Player = main.player
	var air := player.air
	var tree: SceneTree = main.get_tree()
	player.set_realm(realm, false)
	await main._wait(0.3)
	var rn: String = player.realm["name"]
	# 点按
	var sb := _place_far(main)
	await main._wait(0.6)
	var p0 := player.global_position
	Input.action_press("attack")
	air.press_attack()
	await main._wait(0.08)
	var held_mv := player.global_position.distance_to(p0)
	var held_st: String = air.state_name()
	Input.action_release("attack")
	var t0 := Time.get_ticks_msec()
	var went: bool = await main._wait_until(func() -> bool: return player.global_position.distance_to(p0) > 1.0, 1.2)
	var lag := Time.get_ticks_msec() - t0
	var st_go: String = air.state_name()
	var hit_tap: bool = await main._wait_until(func() -> bool: return int(air.state) == Player.AirMelee.A.ATTACK and air._hit_done, 1.5)
	print("[feat] 1 远处点按（%s，22 米）：按着 0.08 秒时挪了 %.2fm、状态「%s」；松手后出发=%s 延迟 %dms 状态「%s」打到=%s" % [rn, held_mv, held_st, went, lag, st_go, hit_tap])
	await main._wait(1.4)
	# 长按
	sb = _place_far(main)
	await main._wait(0.6)
	p0 = player.global_position
	var hp0 := sb.hp
	Input.action_press("attack")
	air.press_attack()
	await main._wait(0.15)
	var mv1 := player.global_position.distance_to(p0)
	var st1: String = air.state_name()
	var chg: bool = await main._wait_until(func() -> bool: return int(air.state) == Player.AirMelee.A.CHARGE, 1.0)
	var mv2 := player.global_position.distance_to(p0)
	await main._wait(0.6)
	var d0 := player.center().distance_to(sb.center())
	Input.action_release("attack")
	var tr := Time.get_ticks_msec()
	var vmax := 0.0
	var jmp := 0.0
	var prev := player.global_position
	var hit := false
	var shot_done := false
	var skip := 0
	var tt := 0.0
	while tt < 1.5:
		await tree.process_frame
		var dt := main.get_process_delta_time()
		tt += dt
		vmax = maxf(vmax, player.velocity.length())
		var step := player.global_position.distance_to(prev)
		if not Combat.hold and skip <= 0:
			jmp = maxf(jmp, step - player.velocity.length() * dt)
		skip -= 1
		prev = player.global_position
		if not shot_done and tt > 0.07 and realm == 5:
			shot_done = true
			await _shot(main, DUEL + "feat_fly_%d" % realm)
			prev = player.global_position
			skip = 2      # 存截图那一帧很长（零点几秒），下一帧按速度一步走得特别远：不算瞬移
		if int(air.state) == Player.AirMelee.A.SMASH and air._hit_done:
			hit = true
			break
	var t_hit := Time.get_ticks_msec() - tr
	await main._wait(0.15)
	print("[feat] 1 远处长按（%s，22 米）：按着 0.15 秒挪了 %.2fm 状态「%s」；转蓄力=%s（蓄力前共挪 %.2fm）；松手时相距 %.1fm → 打到=%s 用时 %dms（含截图）最快 %.0f m/s 单帧最大瞬移 %.2fm 木人掉血 %d 被打飞=%s" % [
			rn, mv1, st1, chg, mv2, d0, hit, t_hit, vmax, jmp, int(hp0 - sb.hp), sb.is_launched()])
	await main._wait(1.6)


# ---------- 2 拳劲对拼的空间裂缝 ----------

static func _cracks(main: Node) -> void:
	var player: Player = main.player
	var air := player.air
	var rival: AirFoe = main.rival
	var tree: SceneTree = main.get_tree()
	for r: int in [2, 3, 4, 5, 6, 7]:
		player.set_realm(r, false)
		await main._wait(0.3)
		rival.hp_max = 99999.0
		rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.8))
		rival.ai_enabled = true
		rival._cd = 99.0
		rival._vanish_cd = 99.0
		rival.no_react = true
		main._spark_setup(rival, 2.8, 8.0)
		air._brawl_cd = 0.0
		await main._wait(0.5)
		var c0 := Vfx.crack_n
		air.demo_mash = 9.0
		air.call("_start_brawl", rival)
		var ms: Array = []
		var us := Time.get_ticks_usec()
		var tt := 0.0
		var shot := false
		while air.in_brawl() and tt < 5.0:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			if not Combat.hold:
				ms.append(float(now - us) * 0.001)
			us = now
			tt += main.get_process_delta_time()
			if not shot and tt > 0.8 and (r == 3 or r == 5 or r == 7):
				shot = true
				await _shot(main, DUEL + "feat_crack_%d" % r)
				us = Time.get_ticks_usec()
		air.demo_mash = 0.0
		ms.sort()
		var tot := 0.0
		for v: float in ms:
			tot += v
		var n := maxi(ms.size(), 1)
		print("[feat] 2 拳劲对拼（%s，档位 %d）：%.1f 秒裂了 %d 道空间裂缝；帧耗时 平均 %.1fms 九成 %.1fms 最长 %.1fms" % [player.realm["name"],
				int(air.get("_brawl_ct")), tt, Vfx.crack_n - c0, tot / float(n), float(ms[int(ms.size() * 0.9)]) if ms.size() > 0 else 0.0,
				float(ms[ms.size() - 1]) if ms.size() > 0 else 0.0])
		rival.ai_enabled = false
		await main._wait(1.6)
		if player.st != Player.St.AIR:
			player.take_air()
			await main._wait(0.9)
	rival.no_react = false


# ---------- 3 飞剑打走 ----------

static func _deflect(main: Node) -> void:
	var player: Player = main.player
	var air := player.air
	var rival: AirFoe = main.rival
	player.set_realm(4, false)
	await main._wait(0.3)
	rival.hp_max = 99999.0
	rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -18.0))
	rival.skill = 0.9
	rival.ai_enabled = true
	rival._cd = 99.0
	rival._shoot_cd = 99.0
	rival._dash_cd = 99.0
	rival._vanish_cd = 99.0
	main._spark_setup(rival, 18.0, 9.0)
	await main._wait(0.5)
	var hp0: float = player.melee.hp
	var d0: int = Proj._deflect_n
	var s0: int = air._swat_n
	rival._start_volley(0.45)
	await main._wait(0.5)
	air.press_guard()
	var tt := 0.0
	var shot := false
	while rival.state == AirFoe.S.VOLLEY and tt < 4.0:
		await main.get_tree().process_frame
		tt += main.get_process_delta_time()
		player.mp = player.mp_max()
		if not shot and tt > 0.7:
			shot = true
			await _shot(main, DUEL + "feat_deflect")
	print("[feat] 3 护体挡剑流（化神，%.1f 秒）：被拨开打着旋飞走的剑 %d 柄、掌拨 %d 下、主角状态「%s」掉血 %d" % [tt, Proj._deflect_n - d0, air._swat_n - s0,
			air.state_name(), int(hp0 - player.melee.hp)])
	air.release_guard()
	rival.ai_enabled = false
	await main._wait(1.2)
	# 气弹抽回去
	rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -14.0))
	main._spark_setup(rival, 14.0, 9.0)
	await main._wait(0.5)
	var rhp: float = rival.hp
	rival.call("_fire_bolt", player.center())
	var cue: bool = await main._wait_until(func() -> bool: return air.swat_cue(), 2.0)
	air.press_attack()
	var swat_st: String = air.state_name()
	await main._wait(0.05)
	await _shot(main, DUEL + "feat_swat")
	var back: bool = await main._wait_until(func() -> bool: return rival.hp < rhp, 2.0)
	print("[feat] 3 气弹抽回：提示=%s 抽到后主角「%s」气弹打回对手=%s 对手掉血 %d" % [cue, swat_st, back, int(rhp - rival.hp)])
	await main._wait(1.2)


# ---------- 4 对波中途别的操作 ----------

static func _start_clash(main: Node) -> bool:
	var player: Player = main.player
	var air := player.air
	var rival: AirFoe = main.rival
	if player.st == Player.St.FLY:
		player.call("_fly_to_air")
		await main._wait(0.6)
	elif player.st != Player.St.AIR:
		player.take_air()
		await main._wait(0.9)
	rival.hp_max = 99999.0
	rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -26.0))
	rival.skill = 0.92
	rival.ai_enabled = true
	rival._cd = 99.0
	rival._shoot_cd = 99.0
	rival._dash_cd = 99.0
	rival._vanish_cd = 99.0
	main._spark_setup(rival, 26.0, 12.0)
	air.demo_mash = 4.0
	await main._wait(0.4)
	rival._start_volley(0.3)
	var t_w := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_w < 350:
		await main.get_tree().process_frame
	air.press_shot()
	var ok: bool = await main._wait_until(func() -> bool: return air.in_clash(), 3.0)
	await main._wait(1.0)
	return ok and air.in_clash()


## 切出对波后主角往右疾行 0.8 秒：每隔一会儿看镜头接管量、主角在不在画面里
static func _after_cut(main: Node, tag: String) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var rival: AirFoe = main.rival
	Input.action_press("move_right")
	Input.action_press("sprint")
	var marks: Array = []
	var tt := 0.0
	var next := 0.1
	var p0 := player.global_position
	while tt < 0.8:
		await main.get_tree().process_frame
		tt += main.get_process_delta_time()
		if tt >= next:
			next += 0.2
			marks.append("%.1fs 接管%.2f 主角在画面里=%s" % [tt, cam.cine_k, _seen(main, player)])
	Input.action_release("move_right")
	Input.action_release("sprint")
	print("[feat] 4 %s：主角挪了 %.1fm；%s；对手状态「%s」剑流还开着=%s 对波光核还在=%s" % [tag, player.global_position.distance_to(p0), "  ".join(marks),
			rival.state_name(), player.caster.clash_mode, air.get("_cfx") != null and is_instance_valid(air.get("_cfx"))])


static func _clash_cut(main: Node) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var rival: AirFoe = main.rival
	player.set_realm(4, false)
	await main._wait(0.3)
	# 放剑诀：应被拦下
	var ok: bool = await _start_clash(main)
	var mp0 := player.mp
	air.press_art()
	await main._wait(0.1)
	print("[feat] 4 对波中按「诀」：进入对波=%s 按后仍在对波=%s 镜头接管 %.2f 灵力 %d -> %d（剑诀没放出来就只是对波在耗）" % [ok, air.in_clash(), cam.cine_k, int(mp0), int(player.mp)])
	# 硬切出对波状态（别的路径改了状态）
	air.state = Player.AirMelee.A.IDLE
	await _after_cut(main, "硬切出对波（现在）")
	air.demo_mash = 0.0
	await main._wait(1.5)
	# 按 F 转光遁离开
	ok = await _start_clash(main)
	player.call("_air_to_fly")
	await main._wait(0.3)
	print("[feat] 4 对波中按 F：进入=%s 0.3 秒后 镜头接管 %.2f 主角在画面里=%s 状态 %d 对手「%s」剑流还开着=%s" % [ok, cam.cine_k, _seen(main, player), int(player.st),
			rival.state_name(), player.caster.clash_mode])
	air.demo_mash = 0.0
	await main._wait(1.2)
	# 对照：改之前没有收尾（把「对波进行中」的标记清掉再切，等于旧代码）
	ok = await _start_clash(main)
	print("[feat] 4 对照：进入对波=%s" % ok)
	air.set("_clash_live", false)
	air.state = Player.AirMelee.A.IDLE
	await _after_cut(main, "硬切出对波（改之前的做法，对照）")
	air.call("_end_cine")
	if rival.state == AirFoe.S.CLASH:
		rival.clash_end(false)
	air.demo_mash = 0.0
	rival.ai_enabled = false
	await _shot(main, DUEL + "feat_clash_cut")
