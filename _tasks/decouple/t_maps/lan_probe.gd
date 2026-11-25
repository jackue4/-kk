extends "res://scripts/xiu_map_selftest.gd"
## T_maps 局域网双开补测（不进包，测试端口 +100，可 --headless）：
##   Godot -s res://_tasks/decouple/t_maps/maps_run.gd -- --qa-maps=desert --qa-probe=lan_probe --qa-role=host   （先开）
##   Godot -s res://_tasks/decouple/t_maps/maps_run.gd -- --qa-maps=desert --qa-probe=lan_probe --qa-role=join
## 测：L1 房主打死首领 → 加入方那边巢穴记空、镇守阵亮、记着凶手；L2 加入方打死房主名下刷怪点的怪（木偶）→ 两边刷怪点都记死；
##     L3 加入方陨落 → 房主那边出现「加入乙 的储物袋」；L4 加入方死前 10 秒被房主打过 → 房主的 pk_kills +1（§k）

var role := "host"


func _run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--qa-role="):
			role = a.get_slice("=", 1)
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	var host := role == "host"
	var tag := "lan2-" + role
	var net: Node = m.get("net")
	await wait(0.5 if host else 10.0)
	net.set("my_name", "房主甲" if host else "加入乙")
	var ui: Node = m.get("level_ui")
	set_realm(3)
	var entered := false
	for attempt in (1 if host else 5):
		ui.set("team_size", 2)
		ui.set("mode", "host" if host else "join")
		ui.set("join_ip", "127.0.0.1")
		await m.call("_enter_level", map_id)
		while bool(m.get("_switching")):
			await get_tree().process_frame
		if m.get("level") != null:
			entered = true
			break
		await wait(4.0)
	level = m.get("level")
	mgr = level.get("raid") if level != null else null
	if not check(tag + " 进图", entered and mgr != null and bool(net.get("active")), "端口偏移 %d" % int(net.get("port_off"))):
		_end()
		return
	keep = true
	mgr.set("lv", 99)
	if not check(tag + " 看见对方", await _lan_wait(func() -> bool: return (net.get("remotes") as Dictionary).size() >= 1, 60.0), ""):
		_end()
		return
	var other := int((net.get("remotes") as Dictionary).keys()[0])
	var pk0 := int(Profile.stats().get("pk_kills", 0))
	var b: Dictionary = {}
	for e: Dictionary in mgr.get("_bosses"):
		if str(e["layer"]) == "surface" and str(e.get("key2", "")) == "":
			b = e
			break
	var bp: Vector3 = b["pos"]
	await put(Vector3(bp.x + (14.0 if host else 18.0), bp.y, bp.z + 4.0))
	# ---- L1 首领 ----
	if host:
		await _lan_wait(func() -> bool: return int(b["state"]) == 1 and b.get("node") != null and is_instance_valid(b["node"]) and not bool(b["node"].get("puppet")), 15.0)
		await wait(8.0)      # 等加入方建好木偶
		var n: Variant = b.get("node")
		var killed := n != null and is_instance_valid(n) and await _kill(n, 10.0)
		await wait(1.0)
		var chest := false
		for pk: Variant in mgr.get("_pickups"):
			if is_instance_valid(pk) and bool(pk.is_chest()) and str(pk.get("title")).ends_with("的遗藏"):
				chest = true
		check(tag + " L1 房主打死首领、出遗藏", killed and int(b["state"]) == 2 and chest, "状态 %d 遗藏 %s" % [int(b["state"]), str(chest)])
	else:
		await _lan_wait(func() -> bool: return int(b["state"]) == 1 and b.get("node") != null and is_instance_valid(b["node"]), 15.0)
		var ok2 := await _lan_wait(func() -> bool: return int(b["state"]) == 2, 25.0)
		await wait(1.0)
		var lit := false
		for e2: Dictionary in mgr.get("_extracts"):
			if str(e2.get("kind", "")) == "boss" and int(e2.get("lair", -1)) == int(b["lid"]) and bool(e2["active"]):
				lit = true
		var pup: Variant = b.get("node")
		check(tag + " L1 别人打死首领 → 巢穴空 / 镇守阵亮 / 木偶没了", ok2 and lit and (pup == null or not is_instance_valid(pup) or not bool(pup.is_alive())) and int(b["killer"]) == other,
				"状态 %d 镇守阵 %s 凶手 %d（应 %d）冷却到 %.0f（现在 %.0f）" % [int(b["state"]), str(lit), int(b["killer"]), other, float(b["back"]), float(mgr.call("world_t"))])
	# ---- L2 刷怪点的怪（房主名下，加入方打木偶）----
	if not host:
		await wait(1.0)
		var target: Variant = null
		for pp: Variant in (mgr.get("_puppets") as Dictionary).values():
			if is_instance_valid(pp) and pp.has_meta("camp") and bool(pp.is_alive()) and not bool(pp.get("boss")):
				target = pp
				break
		if target == null:
			check(tag + " L2 打别人名下刷怪点的怪", false, "身边没有刷怪点木偶")
		else:
			var cd := int(target.get_meta("camp"))
			var t := 0.0
			while is_instance_valid(target) and bool(target.is_alive()) and t < 8.0:
				mgr.call("_on_puppet_hit", target, {"dmg": 1.0e13, "raw": true, "dir": Vector3.FORWARD})
				await wait(0.3)
				t += 0.3
			await wait(1.0)
			var dead_mark := ((mgr.get("camps")._dead as Dictionary).get(cd / 8, {}) as Dictionary).has(cd % 8)
			check(tag + " L2 打死别人名下刷怪点的怪 → 我这边记死", (not is_instance_valid(target) or not bool(target.is_alive())) and dead_mark,
					"刷怪点 %d 第 %d 只 用时 %.1f 秒 记死 %s" % [cd / 8, cd % 8, t, str(dead_mark)])
			say("%s L2 打的是 %d" % [tag, cd])
	else:
		var d0 := 0
		for v: Variant in (mgr.get("camps")._dead as Dictionary).values():
			d0 += (v as Dictionary).size()
		var got := await _lan_wait(func() -> bool:
			var dn := 0
			for v2: Variant in (mgr.get("camps")._dead as Dictionary).values():
				dn += (v2 as Dictionary).size()
			return dn > d0, 20.0)
		var info := []
		for k: Variant in (mgr.get("camps")._dead as Dictionary).keys():
			info.append("%d:%s" % [int(k), str(((mgr.get("camps")._dead as Dictionary)[k] as Dictionary).keys())])
		check(tag + " L2 别人打死我名下刷怪点的怪 → 我这边记死", got, "记死的 %s" % str(info))
	# ---- L3 / L4 加入方陨落 ----
	if not host:
		await wait(2.0)
		var bag: Array = mgr.get("bag")
		bag.append(Items.herb(2))
		bag.append(Items.herb(3))
		mgr.set("_killer", other)
		mgr.set("_killer_t", float(mgr.get("run_t")))
		var dead0 := int(Profile.stats().get("dead", 0))
		keep = false
		mgr.set("lv", 1)
		await frames(2)
		player.melee.hp = 0.0
		var tw := 0.0
		while bool(mgr.get("running")) and tw < 6.0:
			await get_tree().process_frame
			tw += get_process_delta_time()
		check(tag + " L3 陨落结算", not bool(mgr.get("running")) and int(Profile.stats().get("dead", 0)) == dead0 + 1, "陨落次数 %d → %d" % [dead0, int(Profile.stats().get("dead", 0))])
		await wait(4.0)
	else:
		var bag_ok := await _lan_wait(func() -> bool:
			for pk2: Variant in mgr.get("_pickups"):
				if is_instance_valid(pk2) and str(pk2.get("title")).contains("加入乙 的储物袋"):
					return true
			return false, 30.0)
		var n_items := 0
		for pk3: Variant in mgr.get("_pickups"):
			if is_instance_valid(pk3) and str(pk3.get("title")).contains("加入乙 的储物袋"):
				n_items = (pk3.get("items") as Array).size()
		check(tag + " L3 别人陨落 → 原地留储物袋", bag_ok and n_items >= 2, "储物袋 %s %d 件" % [str(bag_ok), n_items])
		var pk_ok := await _lan_wait(func() -> bool: return int(Profile.stats().get("pk_kills", 0)) > pk0, 8.0)
		check(tag + " L4 §k → 我的 pk_kills +1", pk_ok, "pk_kills %d → %d" % [pk0, int(Profile.stats().get("pk_kills", 0))])
	_end()


func _end() -> void:
	keep = false
	say("总计 失败 %d 项（通过 %d 项，用时 %.0f 秒）" % [fails, passes, float(Time.get_ticks_msec() - _t0) / 1000.0])
	await wait(1.0)
	get_tree().quit(0 if fails == 0 else 1)
