extends SceneTree
## W5 探针（不进包）：英雄档 vs 老角色在木兰草原真按「攻」打地面小怪，同一局里轮流比。
## 正常开机（主城，自检档）→ 设境界 → 单人进木兰草原 → 对每种模式（英雄 yujian / canghong / shuanghua、老角色 ""）各打两段：
##   ground：站在地上贴着怪按攻；air：先起飞到怪身边再按攻。每 0.25 秒按一下，3 秒；离怪超过 9 米才把主角挪回怪身边（模拟真人追过去）。
## 用法：Godot --headless --path . -s res://_tasks/decouple/w5/hero_mob_probe.gd -- --qa-w5hero --probe-realm=N [--no-lan]
const Profile := preload("res://scripts/raid_profile.gd")
var m: Node
var realm := 3
var keep := true


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--probe-realm="):
			realm = int(a.get_slice("=", 1))
	m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(m)
	current_scene = m
	_run.call_deferred()


func _process(_dt: float) -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if m != null and is_instance_valid(m):
		var c: Variant = m.get("cam")
		if c != null:
			c.set("capture_mouse", false)
		var p: Variant = m.get("player")
		if keep and p != null and not p.dead:
			p.melee.hp = p.melee.HP_MAX
	return false


func wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _pick(mgr: Variant, player: Variant) -> Variant:
	var mob: Variant = null
	for mb: Variant in mgr.get("_mobs"):
		if is_instance_valid(mb) and mb.is_alive() and not mb.boss and not mb.puppet and str(mb.def.get("shape", "")) != "floater" and not mb.elite:
			if mob == null or mb.global_position.distance_to(player.global_position) < mob.global_position.distance_to(player.global_position):
				mob = mb
	return mob


func _run() -> void:
	await process_frame
	await process_frame
	var t := 0.0
	while t < 120.0:
		var hub: Variant = m.get("hub")
		if hub != null and bool(hub.get("active")) and m.player.process_mode != Node.PROCESS_MODE_DISABLED:
			break
		await process_frame
		t += 0.016
	await wait(2.0)
	var player = m.player
	Profile.data()["realm"] = realm
	player.set_realm(realm, false)
	var cu: Array = Profile.cult(realm)
	Profile.set_cult(int(cu[0]), float(cu[1]))
	m.level_ui.set("mode", "solo")
	await m._enter_level("mulan")
	while bool(m.get("_switching")):
		await process_frame
	await wait(3.0)
	var lvl: Variant = m.get("level")
	if lvl == null:
		print("[w5h] 进图失败")
		quit(1)
		return
	var mgr: Variant = lvl.get("raid")
	var res := {}
	for rep in 2:
		for hid: String in ["yujian", "", "canghong", "shuanghua"]:
			player.force_ground()
			player.set_realm(realm, false)
			player.set_hero(hid)
			await wait(0.5)
			for phase: String in ["ground", "air"]:
				var mob: Variant = _pick(mgr, player)
				if mob == null:
					print("[w5h] 没找到地面小怪")
					continue
				mob.hp_max = 1.0e15
				mob.hp = 1.0e15
				var hp0: float = mob.hp
				var others := {}      # 身边别的怪也设成打不死、记下起始血量：连段会自己挑最近的目标，打到别的怪身上也算
				for ob: Variant in mgr.get("_mobs"):
					if is_instance_valid(ob) and ob != mob and ob.global_position.distance_to(mob.global_position) < 40.0:
						ob.hp_max = 1.0e15
						ob.hp = 1.0e15
						others[ob] = 1.0e15
				player.force_ground()
				player.global_position = mob.global_position + Vector3(0, 0.1, 2.2)
				player.velocity = Vector3.ZERO
				player.face_now(0.0)
				if phase == "air":
					player.global_position = mob.global_position + Vector3(0, 1.5, 2.6)
					var ok: bool = player.take_air()
					await wait(0.5)
					if not ok or player.st != Player.St.AIR:
						print("[w5h] 「%s」起飞失败 st=%d" % [hid, int(player.st)])
				var tt := 0.0
				var moves := 0
				var air_n := 0
				while tt < 3.0 and is_instance_valid(mob) and mob.is_alive():
					var to: Vector3 = mob.global_position - player.global_position
					if Vector2(to.x, to.z).length() > 9.0:
						player.global_position = mob.global_position + Vector3(0, 0.1 if player.st != Player.St.AIR else 1.5, 2.2)
						player.velocity = Vector3.ZERO
						player.face_now(0.0)
						moves += 1
					if player.st == Player.St.AIR:
						air_n += 1
						player.air.press_attack()
					else:
						player.melee.press_attack()
					await wait(0.25)
					tt += 0.25
				var dropped: float = hp0 - (mob.hp if is_instance_valid(mob) else hp0)
				var other_drop := 0.0
				for ob: Variant in others:
					if is_instance_valid(ob):
						other_drop += float(others[ob]) - float(ob.hp)
				var key := "%s/%s" % [hid if hid != "" else "legacy", phase]
				res[key] = (res.get(key, []) as Array) + [roundi(dropped + other_drop)]
				print("[w5h] %s 境界 %d：%s 打 %s（Lv.%d）3 秒 掉血 %.0f（%.1f 个 dmg 单位）空中按了 %d/12 下、挪回 %d 次、最后 st=%d；打到别的怪 %.0f" % [
						hid if hid != "" else "老角色", realm, phase, str(mob.display_name), int(mob.lv), dropped,
						dropped / maxf(float(player.realm["dmg"]), 1.0), air_n, moves, int(player.st), other_drop])
				player.force_ground()
				await wait(1.2)
	print("[w5h] 汇总 ", res)
	print("[w5h] done")
	quit(0)
