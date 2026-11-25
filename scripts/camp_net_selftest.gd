extends RefCounted
## 固定刷怪点（raid_camps.gd）的联机自检（2026-11-21）：同一台机器开两个实例
##   `-- --net=camp_host`（房主）和 `-- --net=camp_mate`（队友，晚 7 秒加入），两人站到草原同一片刷怪点上。查：
##   一、同一个点只有一个人建（编号小的房主），队友那边只有木偶，没有重复；
##   二、队友打死房主名下的一只：两边都记上这只死了（复活前谁都不再建它）；
##   三、房主先把身边一只的血压到一半，然后急飞走（御剑、每秒 60 米）：队友接手这些点，那只接着半血、死了的那只还是空着；
##   四、两人手里加起来的点上的怪不超过一个人的同屏上限。
## 打印 `[campnet:角色]`，最后一行 PASS / FAIL；房主等队友跑完再退。

const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")


static func _camp_mobs(rd: Variant) -> Array:
	return rd._mobs.filter(func(m: Variant) -> bool: return is_instance_valid(m) and m.is_alive() and m.has_meta("camp"))


static func _camp_puppets(rd: Variant) -> Array:
	return rd._puppets.values().filter(func(m: Variant) -> bool: return is_instance_valid(m) and m.is_alive() and m.has_meta("camp"))


static func _codes(list: Array) -> Array:
	return list.map(func(m: Variant) -> int: return int(m.get_meta("camp")))


static func run(main: Node, role: String) -> void:
	var host := role == "camp_host"
	var fails: Array = []
	var say := func(s: String) -> void:
		print("[campnet:%s] %s" % [role, s])
	var nt: Variant = main.net
	var player: Player = main.player
	await main._wait(1.0)
	nt.my_name = "房主甲" if host else "队友乙"
	main.level_ui.team_size = 2
	player.set_realm(4, false)
	if host:
		main.level_ui.mode = "host"
	else:
		await main._wait(7.0)
		main.level_ui.mode = "join"
		main.level_ui.join_ip = "127.0.0.1"
	await main._enter_level("meadow")
	if main.level == null:
		say.call("没进去（加入失败） FAIL")
		main.get_tree().quit()
		return
	var rd: Variant = main.level.raid
	rd._mob_root.visible = true
	rd.camps.reset()
	rd.camps.on = true      # 自检模式默认是老导演，这里开刷怪点
	for m: Variant in rd._mobs.duplicate():      # 进图那几秒老导演刷的怪清掉
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()
	main._net_immortal()
	var spot := Vector2(0.6, 0.8) * (0.3 * Prog.MEADOW_DEPTH_R) + (Vector2.ZERO if host else Vector2(12.0, 4.0))
	await main._raid_goto(spot, 0.0)
	await main._wait(3.0)
	say.call("〇、到位 3 秒（房间 %d 人）：我建着 %d 只（%d 个点）、木偶 %d 只、急飞=%s、被压着=%s、点数 %.0f 波次计时 %.1f" % [nt.players.size(),
			_camp_mobs(rd).size(), rd.camps.live_camps(), _camp_puppets(rd).size(), str(rd.camps.traveling), str(rd._credits < -1000.0 or rd._wave_t > 900.0),
			float(rd._credits), float(rd._wave_t)])
	var t_end := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < t_end and (nt.players.size() < 2 or nt.remotes.size() < 1):
		await main._wait(0.5)
	for id: int in nt.remotes.keys():
		var rp: Variant = nt.remotes[id]
		var v: Vector3 = rp.velocity()
		say.call("〇、看到 %d：活着=%s 离我 %.0f 米 水平速度 %.1f 状态 %d" % [id, str(rp.is_alive()), (rp.global_position as Vector3).distance_to(player.global_position),
				Vector2(v.x, v.z).length(), int(rp.st)])
	if nt.players.size() < 2:
		say.call("没等到两个人到齐 FAIL")
		main.get_tree().quit()
		return
	await main._wait(9.0 if host else 8.0)
	# 一、谁建、有没有重复
	var mine := _codes(_camp_mobs(rd))
	var pups := _codes(_camp_puppets(rd))
	var dup := mine.filter(func(c: int) -> bool: return pups.has(c))
	say.call("一、我编号 %d：我建着 %d 只刷怪点的怪（%d 个点），别人名下的木偶 %d 只；两边重复 %d 只 %s" % [int(nt.my_id), mine.size(),
			rd.camps.live_camps(), pups.size(), dup.size(), str(dup)])
	if not dup.is_empty():
		fails.append("重复建了 %d 只" % dup.size())
	if host and mine.is_empty():
		fails.append("房主身边一只都没建")
	if not host and not mine.is_empty() and pups.is_empty():
		fails.append("队友自己建了、看不到房主的")
	if mine.size() + pups.size() > 24:
		fails.append("两人加起来 %d 只，超过一个人的上限" % (mine.size() + pups.size()))
	# 二、队友打死房主名下的一只；房主把另一只压到半血
	var killed := -1
	var halved := -1
	if not host:
		var best: Variant = null
		var bd := 1.0e9
		for m: Variant in _camp_puppets(rd):
			var d: float = (m as Node3D).global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = m
		if best != null:
			killed = int(best.get_meta("camp"))
			best.receive_hit(player, {"dmg": 1.0e7, "dir": Vector3.FORWARD, "heavy": true, "kb": 0.5, "raw": true})
			say.call("二、打死房主名下的 %d（离我 %.0f 米）" % [killed, bd])
		else:
			fails.append("队友身边没有房主的木偶可打")
	else:
		var near: Array = _camp_mobs(rd)
		near.sort_custom(func(a: Variant, b: Variant) -> bool:
			return (a as Node3D).global_position.distance_to(player.global_position) > (b as Node3D).global_position.distance_to(player.global_position))
		if not near.is_empty():
			var m: Variant = near[0]
			m.hp = m.hp_max * 0.5
			halved = int(m.get_meta("camp"))
			say.call("二、把我名下的 %d 压到半血" % halved)
	rd.camps.debug = true
	var t_w := 0.0
	while t_w < 15.0:
		await main._wait(0.5)
		t_w += 0.5
		var nd := 0
		for id: int in rd.camps._dead.keys():
			nd += (rd.camps._dead[id] as Dictionary).size()
		if nd > 0 and t_w >= 3.0:
			break
	var dead_n := 0
	for id: int in rd.camps._dead.keys():
		dead_n += (rd.camps._dead[id] as Dictionary).size()
	say.call("　　我这边记着死了 %d 只：%s" % [dead_n, str(rd.camps._dead)])
	if dead_n < 1:
		fails.append("没记上那只死了")
	# 三、交接：房主急飞走，队友接手
	var half_seen := -1
	var half_hp := -1.0
	if not host:
		for m: Variant in _camp_puppets(rd):
			if float(m.hp) / maxf(float(m.hp_max), 0.01) < 0.8:
				half_seen = int(m.get_meta("camp"))
				half_hp = float(m.hp) / maxf(float(m.hp_max), 0.01)
		say.call("三、房主那只半血的木偶：%d（%.2f）" % [half_seen, half_hp])
	if host:
		await main._wait(1.0)
		player.st = Player.St.FLY
		player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var dir := Vector3(-0.8, 0.0, 0.6)
		var t := 0.0
		while t < 8.0:
			await main.get_tree().process_frame
			var dt: float = main.get_process_delta_time()
			t += dt
			var q: Vector3 = player.global_position + dir * 60.0 * dt
			q.y = float(main.level.ground(q.x, q.z)) + 30.0
			player.global_position = q
			player.velocity = dir * 60.0
		say.call("三、飞走了 %.0f 米：我还建着 %d 只、急飞=%s" % [Vector2(player.global_position.x, player.global_position.z).distance_to(spot),
				_camp_mobs(rd).size(), str(rd.camps.traveling)])
		if _camp_mobs(rd).size() > 0:
			fails.append("飞远了还留着 %d 只" % _camp_mobs(rd).size())
		await main._wait(16.0)      # 等队友查完
	else:
		await main._wait(12.0)
		var now_mine := _camp_mobs(rd)
		var codes := _codes(now_mine)
		var hp_after := -1.0
		for m: Variant in now_mine:
			if int(m.get_meta("camp")) == half_seen:
				hp_after = float(m.hp) / maxf(float(m.hp_max), 0.01)
		say.call("三、房主走后：我建着 %d 只（%d 个点）、别人的木偶 %d 只；死了那只 %d 重建了=%s；半血那只 %d 接手后血量 %.2f" % [now_mine.size(),
				rd.camps.live_camps(), _camp_puppets(rd).size(), killed, str(codes.has(killed)), half_seen, hp_after])
		if now_mine.is_empty():
			fails.append("房主走了没人接手")
		if killed >= 0 and codes.has(killed):
			fails.append("死了的那只被重建了")
		if half_seen >= 0 and (hp_after < 0.0 or hp_after > 0.8):
			fails.append("半血那只接手后血量 %.2f（应约 0.5）" % hp_after)
	say.call(("PASS" if fails.is_empty() else "FAIL ") + "；".join(fails))
	main.get_tree().quit()
