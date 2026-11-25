extends RefCounted
## 真人对打规则的双开自检（2026-11-23，规则见 air_moves.gd 的「真人对打」）。走擂台联机那条路（arena_selftest.gd 的 _run_net 开头分流过来），
## 同一台电脑开两个窗口：`-- --hub-shot --arena-duel --arena-net=a --pvp-rules=<剧本>` 和 `… --arena-net=b --pvp-rules=<剧本>`
## 剧本：
##   mash     a 每 0.11 秒点一下「攻」一直打，b 站着不动 —— 量 b 最长连续多久动不了、每次脱出来能自由多久、a 打空了多少
##   defend   a 照旧乱按；b 也按「攻」，另外会卡「御」的提示圈瞬身、被打飞了按「闪」受身、挨打里有罡气就挣脱 —— 量两边各掉多少血
##   clash    a 朝 b 连发飞剑；b 等预警过了再过 1 秒才点「剑」接波（--pvp-early：预警里 0.4 秒就点）—— 看两边进没进对波
## 其他参数：`--pvp-legacy` 关掉新规则（改之前的对照）· `--pvp-realm=5` 两边的境界（默认炼虚：近身是缩地；3 元婴是冲过去）· `--pvp-secs=22` 量多久
##   `--pvp-shots` 存几张截图（_shots/arena/pvp_*.jpg）。打印以 [pvp] 开头，末尾一行 `[pvp] RESULT …` 是汇总。
## 为了量得久，两边的气血每帧补回 60 以上（掉了多少另外累计）；被打出台子太远就挪回台心附近（出界判负会把这一场结束掉）。
## 故意不写 class_name。

const Arena := preload("res://scripts/hub_arena.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const AirMelee := preload("res://scripts/air_melee.gd")
const Remote := preload("res://scripts/remote_player.gd")
const Moves := preload("res://scripts/air_moves.gd")


static func _arg(prefix: String, def := "") -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return def


static func _has(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


static func _now() -> float:
	return Time.get_ticks_msec() * 0.001


static func _wait(hub, sec: float) -> void:
	var t1 := _now() + sec
	while _now() < t1:
		await hub.get_tree().process_frame


static func _until(hub, cond: Callable, sec: float) -> float:
	var t0 := _now()
	while _now() - t0 < sec:
		if bool(cond.call()):
			return _now() - t0
		await hub.get_tree().process_frame
	return _now() - t0 if bool(cond.call()) else -1.0


static func _shot(hub, tag: String) -> void:
	if DisplayServer.get_name() == "headless" or not _has("--pvp-shots"):
		return
	await RenderingServer.frame_post_draw
	var img: Image = hub.get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(1100, int(1100.0 * float(img.get_height()) / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/arena"))
	img.save_jpg(ProjectSettings.globalize_path("res://_shots/arena/pvp_%s.jpg" % tag), 0.86)
	print("[pvp] shot ", tag)


static func run(hub, role: String) -> void:
	var p: Player = hub.player
	var duel = hub.duel
	var is_a := role == "a"
	var scen := _arg("--pvp-rules=", "mash")
	var legacy := _has("--pvp-legacy")
	var realm := int(_arg("--pvp-realm=", "5"))
	var secs := float(_arg("--pvp-secs=", "22"))
	if legacy:
		AirMelee.pvp_legacy = true
		Remote.pvp_rules = false
	if scen == "hero":
		# 2026-11-25 英雄技能对真人：先换英雄再配对（握手里带的是这时的英雄）
		p.set_hero(_arg("--pvp-hero-%s=" % role, "yujian"))
	# 2026-11-25 主干解耦：英雄档下 set_realm 也生效了（以前被吞掉、两边实际都是结丹）。两个窗口要给同一个 --pvp-realm，
	# 不然伤害 / 封顶会多出 ×1.08^境界差（CS.PVP_REALM_ADV）
	p.set_realm(realm, false)
	Profile.data()["lv"] = 3 * realm + 1
	duel.queue_t = 45.0
	await _wait(hub, 2.0 if is_a else 6.0)
	p.force_ground()
	p.global_position = Arena.center(0) + Vector3(-3.0 if is_a else 3.0, 0.1, 5.0)
	p.velocity = Vector3.ZERO
	hub.cam.snap(PI * 0.5 if is_a else -PI * 0.5, -0.25, 9.0)
	var tq := await _until(hub, func() -> bool: return duel.busy(), 50.0)
	if duel.kind != "pvp":
		print("[pvp] %s：没配到真人（等了 %.1f 秒，对手类型=%s），自检中止" % [role, tq, duel.kind])
		hub.get_tree().quit()
		return
	await _until(hub, func() -> bool: return duel.phase == duel.Ph.FIGHT, 8.0)
	var pup: Node3D = duel._rival_puppet()
	if pup == null:
		print("[pvp] %s：没有对手的木偶，自检中止" % role)
		hub.get_tree().quit()
		return
	p.enter_air_combat()
	await _wait(hub, 1.4)
	p.mp = p.mp_max()
	print("[pvp] %s：开打。剧本=%s 旧规则=%s 境界 %d（%s）灵力上限 %.0f 我在空战=%s 对手木偶离我 %.1f 米" % [role, scen, legacy, realm, str(p.realm["name"]),
			p.mp_max(), p.st == Player.St.AIR, pup.global_position.distance_to(p.global_position)])
	if scen == "hero":
		await _hero(hub, role, pup)
	elif scen == "clash":
		await _clash(hub, role, pup)
	elif scen == "clash2":
		await _clash2(hub, role, pup)
	else:
		await _fight(hub, role, pup, scen, secs, legacy, realm)
	await _wait(hub, 0.5)
	hub.get_tree().quit()


## mash / defend：打 secs 秒，逐帧量
static func _fight(hub, role: String, pup: Node3D, scen: String, secs: float, legacy: bool, realm: int) -> void:
	var p: Player = hub.player
	var duel = hub.duel
	var air: AirMelee = p.air
	var is_a := role == "a"
	var defend := scen == "defend" and not is_a
	var attack := is_a or defend
	var A := air.A
	var t0 := _now()
	var last := t0
	var press_t := 0.0
	var guard_until := -1.0
	var stun_run := 0.0
	var stun_max := 0.0
	var stun_total := 0.0
	var free_run := 0.0
	var frees: Array[float] = []
	var was_stun := false
	var dmg_taken := 0.0
	var hits_taken := 0
	var hp_prev: float = p.melee.hp
	var mp_min: float = p.mp
	var mp_sum := 0.0
	var frames := 0
	var since_stun := 9.0
	var press_run := 0.0
	var press_max := 0.0
	var press_sum := 0.0
	var press_n := 0
	var ts_sum := 0.0
	var open_t := 0.0
	var prot_t := 0.0
	var hold_t := 0.0
	var cnt := {"vanish": 0, "tech": 0, "burst": 0}      # 事件回调里数（匿名函数改不了外面的局部变量，用字典）
	var cue_n := 0
	var cue_was := false
	var back_n := 0
	var trace := _has("--pvp-trace")
	var st_prev := -1
	var key_prev := ""
	var mv_prev := ""
	var pr_prev := false
	var shot_prot := false
	var shot_cue := false
	var ev := func(k: String, _i: Dictionary) -> void:
		if k == "air_vanish":
			cnt["vanish"] = int(cnt["vanish"]) + 1
		elif k == "air_tech":
			cnt["tech"] = int(cnt["tech"]) + 1
		elif k == "air_burst":
			cnt["burst"] = int(cnt["burst"]) + 1
	p.melee.combat_event.connect(ev)
	while _now() - t0 < secs and duel.phase == duel.Ph.FIGHT and is_instance_valid(pup):
		await hub.get_tree().process_frame
		var now := _now()
		var dt := now - last
		last = now
		frames += 1
		# 气血：掉了多少累计下来，再补回去（别把这一场打完）
		var hp: float = p.melee.hp
		if hp < hp_prev - 0.01:
			dmg_taken += hp_prev - hp
			hits_taken += 1
		if hp < 60.0:
			p.melee.hp = 60.0
		hp_prev = p.melee.hp
		if p.st != Player.St.AIR and not p.dead:
			p.enter_air_combat()      # 被砸回地面 / 落地了：再升起来
		# 被打出台子太远：挪回台心附近
		var c: Vector3 = Arena.center(0)
		if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() > 46.0:
			p.global_position = c + Vector3(-6.0 if is_a else 6.0, 9.0, 0.0)
			p.velocity = Vector3.ZERO
			back_n += 1
		if trace and (air.state != st_prev or air.move_id != mv_prev or air.protected() != pr_prev):
			print("[pvp] %s t=%.2f %s%s 连段 %d 下 / 飞 %d 次 保护 %.2f 灵力 %.0f 离对手 %.1f 米%s" % [role, now - t0, air.state_name(),
					("·" + air.move_id) if air.state == A.ATTACK else "", air._pc_n, air._pc_launch, air._prot, p.mp,
					pup.global_position.distance_to(p.global_position), "（对手木偶：被打飞）" if bool(pup.call("is_launched")) else ("（对手木偶：保护中）" if bool(pup.call("protected")) else "")])
			st_prev = air.state
			mv_prev = air.move_id
			pr_prev = air.protected()
		if trace and is_a and _has("--pvp-trace2"):
			var key := "%s %s q=%s wl=%s hd=%s w=%s" % [air.state_name(), air.move_id, air._queued, air._whiff_lock, air._hit_done, air._whiff]
			if key != key_prev:
				key_prev = key
				print("[pvp] a2 t=%.3f _t=%.3f %s hold=%.2f buf=%.2f combo=%d" % [now - t0, air._t, key, air._open_hold, air._now() - air._buf_at, air.combo])
		var stun: bool = air.state == A.HURT or air.state == A.BLOWN or air.state == A.DOWN or air.state == A.CRUSH
		if stun:
			stun_run += dt
			stun_total += dt
			stun_max = maxf(stun_max, stun_run)
			if not was_stun and free_run > 0.0 and hits_taken > 0:
				frees.append(free_run)
			free_run = 0.0
		else:
			stun_run = 0.0
			free_run += dt
		was_stun = stun
		# 被压着打的一整段：挨第一下起算，硬直里出来 0.5 秒没再挨打才算断（规则开不开都这么量）
		since_stun = 0.0 if stun else since_stun + dt
		if stun or (press_run > 0.0 and since_stun < 0.5):
			press_run += dt
			press_max = maxf(press_max, press_run)
		else:
			if press_run > 0.0:
				press_n += 1
				press_sum += press_run
			press_run = 0.0
		mp_min = minf(mp_min, p.mp)
		mp_sum += p.mp
		ts_sum += Engine.time_scale
		if air.is_open():
			open_t += dt
		if air.protected():
			prot_t += dt
			if not shot_prot and air._prot < 0.7:
				shot_prot = true
				await _shot(hub, "%s_%s_%s_protect" % [scen, "old" if legacy else "new", role])
		if air._open_hold > 0.0:
			hold_t += dt
		var cue: bool = air.vanish_cue()
		if cue and not cue_was:
			cue_n += 1
			if not shot_cue:
				shot_cue = true
				await _shot(hub, "%s_%s_%s_cue" % [scen, "old" if legacy else "new", role])
		cue_was = cue
		# 出手
		if attack and (is_a or now - t0 > 3.0):      # 会防守的一方开头 3 秒先不出手：让乱按的先手打一套
			var far: bool = pup.global_position.distance_to(p.global_position) > 30.0
			air.demo_dash = far and is_a
			press_t -= dt
			if press_t <= 0.0:
				press_t = 0.11
				air.press_attack()
		if defend:
			if guard_until > 0.0 and now >= guard_until:
				guard_until = -1.0
				air.release_guard()
			if cue and guard_until < 0.0:
				var v0: int = cnt["vanish"]
				var st0: String = air.state_name()
				var tth := float(pup.call("time_to_hit"))
				air.press_guard()             # 提示圈亮了：卡着按「御」= 瞬身
				guard_until = now + 0.12
				if trace:
					print("[pvp] %s t=%.2f 提示圈亮：还有 %.3f 秒打到，按「御」前状态=%s 灵力 %.0f → 瞬身了=%s 按后状态=%s" % [role, now - t0, tth, st0, p.mp, int(cnt["vanish"]) > v0, air.state_name()])
			elif air.tech_ready() or (legacy and air.state == A.BLOWN and air.can_blink()):
				p.request_blink()             # 被打飞了：受身
			elif air.can_burst() and air._pc_n >= 4 and guard_until < 0.0:
				air.press_guard()             # 连着挨了四下以上、有罡气：挣脱
				guard_until = now + 0.05
	p.melee.combat_event.disconnect(ev)
	air.demo_dash = false
	var el := maxf(_now() - t0, 0.01)
	var fmin := 0.0
	var favg := 0.0
	if not frees.is_empty():
		fmin = frees.min()
		for f in frees:
			favg += f
		favg /= float(frees.size())
	print("[pvp] RESULT 剧本=%s 规则=%s 境界=%d 角色=%s(%s) 时长=%.1f | 掉血 %.0f（%d 次） 被压着打最长一段 %.2f 秒（%d 段，平均 %.2f） 最长连续动不了 %.2f 秒 共 %.1f 秒（%.0f%%） 两段硬直之间能自由 最短 %.2f 平均 %.2f 秒（%d 段）| 保护中 %.1f 秒 起手前摇 %.1f 秒 收招破绽 %.1f 秒 | 灵力 最低 %.0f 平均 %.0f / %.0f | 瞬身 %d 受身 / 脱身 %d 挣脱 %d 提示圈亮 %d 次 | 挪回场内 %d 次 | 帧率 %.0f 时间流速 %.2f | 账 %s" % [
			scen, "旧" if legacy else "新", realm, role, "乱按" if is_a else ("会防守" if defend else "不动"), el,
			dmg_taken, hits_taken, press_max, press_n, press_sum / float(maxi(press_n, 1)), stun_max, stun_total, 100.0 * stun_total / el, fmin, favg, frees.size(),
			prot_t, hold_t, open_t, mp_min, mp_sum / float(maxi(frames, 1)), p.mp_max(), int(cnt["vanish"]), int(cnt["tech"]), int(cnt["burst"]), cue_n, back_n, float(frames) / el, ts_sum / float(maxi(frames, 1)), str(air.pvp_stat)])


## clash：a 连发飞剑，b 接波
static func _clash(hub, role: String, pup: Node3D) -> void:
	var p: Player = hub.player
	var air: AirMelee = p.air
	var is_a := role == "a"
	var early := _has("--pvp-early")
	air.target = pup
	if is_a:
		await _wait(hub, 2.5)
		Input.action_press("air_shot")
		var tc := await _until(hub, func() -> bool: return p.caster.channeling, 4.0)
		var tg: Variant = p.caster.aim_target()
		print("[pvp] a：按住「剑」%.2f 秒后开始连发=%s，瞄着的是对手木偶=%s" % [tc, p.caster.channeling, tg == pup])
		var ti := await _until(hub, func() -> bool: return air.in_clash(), 8.0)
		print("[pvp] a：%s" % ("%.2f 秒后被接波，进了对波" % ti if ti >= 0.0 else "8 秒里一直没进对波（对面没接上）"))
		air.demo_mash = 6.0
		if ti >= 0.0:
			await _wait(hub, 1.0)
			await _shot(hub, "clash_a")
		var te := await _until(hub, func() -> bool: return not air.in_clash(), 12.0)
		Input.action_release("air_shot")
		air.demo_mash = 0.0
		print("[pvp] RESULT 剧本=clash%s 角色=a 进了对波=%s 对波打了 %.1f 秒 结束后状态=%s 气血 %.0f" % ["-early" if early else "", ti >= 0.0, maxf(te, 0.0), air.state_name(), p.melee.hp])
	else:
		var hp0: float = p.melee.hp
		var tw := await _until(hub, func() -> bool: return air.warn_k() > 0.0, 10.0)
		print("[pvp] b：%s" % ("%.2f 秒后收到对波预警" % tw if tw >= 0.0 else "10 秒里没收到对波预警"))
		# 早接：预警窗口里；晚接：预警过了（1 秒）再等 1 秒 —— 这时候 a 的飞剑已经在往身上打了
		await _wait(hub, 0.4 if early else 2.0)
		var st_before: String = air.state_name()
		var can: bool = air.can_accept_clash()
		print("[pvp] b：要点「剑」了：这会儿状态=%s 气血 %.0f → %.0f 对方在连发=%s 能接波=%s" % [st_before, hp0, p.melee.hp, bool(pup.call("is_volleying")), can])
		var ok := false
		var tries := 0
		var t1 := _now()
		while _now() - t1 < 4.0 and not ok:
			air.press_shot()
			tries += 1
			await _wait(hub, 0.15)
			ok = air.in_clash()
		air.demo_mash = 6.0
		print("[pvp] b：点了 %d 下「剑」（%.2f 秒），进了对波=%s" % [tries, _now() - t1, ok])
		if ok:
			await _wait(hub, 1.0)
			await _shot(hub, "clash_b")
		var te := await _until(hub, func() -> bool: return not air.in_clash(), 12.0)
		air.demo_mash = 0.0
		print("[pvp] RESULT 剧本=clash%s 角色=b 收到预警=%s 点「剑」前的状态=%s 进了对波=%s（点了 %d 下）对波打了 %.1f 秒 结束后状态=%s 气血 %.0f" % ["-early" if early else "", tw >= 0.0, st_before, ok, tries,
				maxf(te, 0.0), air.state_name(), p.melee.hp])
		await _wait(hub, 1.5)


## clash2：两边都按住「剑」连发（a 先按，b 晚 0.7 秒也按住，不另外点）—— 两股剑流对上应该自动进对波。
## 顺带量 b 这边：a 连发期间被时停了多久（Engine.time_scale < 0.5 的真实时间）、收到几次预警、挨了多少飞剑
static func _clash2(hub, role: String, pup: Node3D) -> void:
	var p: Player = hub.player
	var air: AirMelee = p.air
	var is_a := role == "a"
	air.target = pup
	var warns := {"n": 0}
	var ev := func(k: String, _i: Dictionary) -> void:
		if k == "air_clash_warn":
			warns["n"] = int(warns["n"]) + 1
	p.melee.combat_event.connect(ev)
	var hold_b := not _has("--pvp-nohold")      # --pvp-nohold：b 不还手，只挨着（量时停 / 预警次数 / 掉血）
	await _wait(hub, 2.5 if is_a else 3.2)
	if is_a or hold_b:
		Input.action_press("air_shot")
	var t0 := _now()
	var slow := 0.0
	var hp0: float = p.melee.hp
	var t_in := -1.0
	var last := t0
	while _now() - t0 < 7.0:
		await hub.get_tree().process_frame
		var now := _now()
		if Engine.time_scale < 0.5:
			slow += now - last
		last = now
		if t_in < 0.0 and air.in_clash():
			t_in = now - t0
			air.demo_mash = 6.0
			break
	var st: String = air.state_name()
	var te := -1.0
	if t_in >= 0.0:
		te = await _until(hub, func() -> bool: return not air.in_clash(), 12.0)
	Input.action_release("air_shot")
	air.demo_mash = 0.0
	p.melee.combat_event.disconnect(ev)
	print("[pvp] RESULT 剧本=clash2 角色=%s 按住「剑」后 %s 进了对波=%s（对波打了 %.1f 秒）| 这 %.1f 秒里：被时停 %.2f 秒 收到预警 %d 次 掉血 %.0f 状态=%s 我在连发=%s 对方在连发=%s" % [role,
			("%.2f 秒" % t_in) if t_in >= 0.0 else "7 秒内都没", t_in >= 0.0, maxf(te, 0.0), (t_in if t_in >= 0.0 else 7.0), slow, int(warns["n"]), hp0 - p.melee.hp, st,
			p.caster.channeling, bool(pup.call("is_volleying"))])
	await _wait(hub, 1.0)


## 2026-11-25 英雄技能对真人（--pvp-rules=hero --pvp-hero-a=<id> --pvp-hero-b=<id>）：
## a 把自己这位英雄的 M1 / 四技能 / 觉醒 / 觉醒四式挨个朝 b 放两轮；b 第一轮一直按着护体、第二轮不防，逐帧记自己挨了什么。
## 看的是：打到真人身上算不算数（每招的判定结果）、破防 / 硬直 / 冻结过没过网、范围招打不打得到木偶、对面看得见画面（联机画面号有没有收到）。
static func _hero(hub, role: String, pup: Node3D) -> void:
	var p: Player = hub.player
	var duel = hub.duel
	var is_a := role == "a"
	var ev := {}
	p.melee.combat_event.connect(func(k: String, _i: Dictionary) -> void:
		ev[k] = int(ev.get(k, 0)) + 1)
	# 机器忙的时候（同时好几个隐藏窗口）开打前的倒数会拖过 run() 里等的那 8 秒：这里再等一次
	await _until(hub, func() -> bool: return duel.phase == duel.Ph.FIGHT, 40.0)
	p.enter_air_combat()
	await _wait(hub, 1.0)
	print("[pvp] %s：进入对决 phase=%d 空战=%s 英雄=%s" % [role, int(duel.phase), p.st == Player.St.AIR, p.hero_id])
	var t0 := _now()
	var A := p.air.A
	if not is_a:
		# b：前 28 秒按着护体，之后不防；记各状态最长持续、掉了多少血
		var longest := {}
		var cur := -1
		var cur_t := 0.0
		var lost := 0.0
		var hp_prev: float = p.melee.hp
		var guard_on := false
		while _now() - t0 < 110.0 and duel.phase == duel.Ph.FIGHT and is_instance_valid(pup):
			await hub.get_tree().process_frame
			duel.set("_t", 0.0)      # 别让对决到点结束（这套要跑一分多钟）
			if p.melee.hp < hp_prev:
				lost += hp_prev - p.melee.hp
			if p.melee.hp < 60.0:
				p.melee.hp = 100.0
			hp_prev = p.melee.hp
			if p.st != Player.St.AIR and not p.dead:
				p.enter_air_combat()
			p.mp = maxf(p.mp, 80.0)
			var c: Vector3 = Arena.center(0)
			if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() > 30.0 or p.global_position.y > c.y + 30.0:
				p.global_position = c + Vector3(6.0, 6.0, 0.0)
				p.velocity = Vector3.ZERO
			var want := _now() - t0 < 50.0
			if want != guard_on:
				guard_on = want
				if want:
					Input.action_press("guard")
					p.air.press_guard()
				else:
					Input.action_release("guard")
					p.air.release_guard()
			elif want and p.air.state == A.IDLE:
				p.air.press_guard()
			var st: int = p.air.state
			if st != cur:
				cur = st
				cur_t = _now()
			var nm: String = p.air.state_name()
			longest[nm] = maxf(float(longest.get(nm, 0.0)), _now() - cur_t)
		Input.action_release("guard")
		print("[pvp] b 结果：掉血 %.0f 点；事件 %s；各状态最长持续 %s；霸体扛 %d" % [lost, str(ev), str(longest), p.air.stat_armor])
		return
	# a：两轮
	var names := ["M1", "E", "Z", "Q", "R", "觉醒", "觉E", "觉Z", "觉Q", "觉R"]
	for round_i in 2:
		for step in names.size():
			if duel.phase != duel.Ph.FIGHT or not is_instance_valid(pup):
				break
			duel.set("_t", 0.0)
			if p.st != Player.St.AIR:
				p.enter_air_combat()
			var pc: Vector3 = pup.global_position
			var back := (p.global_position - pc)
			back.y = 0.0
			back = back.normalized() if back.length() > 0.1 else Vector3.BACK
			p.global_position = pc + back * 4.5
			p.velocity = Vector3.ZERO
			p.air.target = pup
			p.mp = p.mp_max()
			for i in 4:
				(p.kit.get("cds") as Array)[i] = 0.0
				(p.kit.get("cds_aw") as Array)[i] = 0.0
			await _wait(hub, 0.5)
			var n0: int = p.air.stat_hits.size()
			var mark: int = n0
			var what: String = names[step]
			if step == 0:
				for k in p.air.ATK.size():
					p.air.press_attack()
					await _wait(hub, 0.27)
			elif step <= 4:
				if p.air.awake_t > 0.0:
					p.air.awake_t = 0.001
					await _wait(hub, 0.1)
				p.kit.call("press", step - 1)
			elif step == 5:
				p.air.awaken = 100.0
				p.air.press_awaken()
			else:
				if p.air.awake_t <= 0.0:
					p.air.awaken = 100.0
					p.air.press_awaken()
					await _wait(hub, 1.9)      # 觉醒演出（awaken_cine.gd）约 1.55 秒，演完才出得了招
				p.air.awake_t = maxf(p.air.awake_t, 6.0)
				p.kit.call("press", step - 6)
			var nm2: String = p.air.state_name()
			await _wait(hub, 0.3)
			var g := 0
			while p.air.state == A.ATTACK and g < 400:
				g += 1
				await hub.get_tree().process_frame
			await _wait(hub, 1.2)
			var res: Array = []
			var hits: Array = p.air.stat_hits
			for k in range(maxi(hits.size() - 14, 0), hits.size()):
				res.append("%s:%d" % [str((hits[k] as Array)[0]), int((hits[k] as Array)[2])])
			if not is_instance_valid(pup):
				print("[pvp] a：对手没了（对决结束 phase=%d），中止" % int(duel.phase))
				return
			print("[pvp] a 第 %d 轮 %s（%s）：最近判定 %s 木偶状态 %s 被保护=%s" % [round_i + 1, what, nm2, " ".join(res.slice(-8)), str(pup.call("state_name")),
					str(pup.call("protected"))])
			if _has("--pvp-shots") and step >= 1:
				await _shot(hub, "hero_%s_%d_%d" % [role, round_i, step])
			mark = hits.size()
	print("[pvp] a 结果：事件 %s；技能记录 %d 条" % [str(ev), (p.kit.get("log_lines") as Array).size()])
