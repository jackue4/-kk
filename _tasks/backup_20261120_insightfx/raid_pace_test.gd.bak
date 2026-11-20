extends RefCounted
## 大世界节奏探针（2026-11-20 第二版，按新数值框架）：
##   `-- --raid-shot --raid-pace [--touch] [--pace-min=5] [--pace-speed=6] [--pace-regions=0,1,2,3,4] [--pace-depth=0.35] [--pace-hit=1.5]`
## 每个区域：主角设成「该区域的入门境界、境界中间那一级」，落到该区域 pace-depth 深度处，自动打怪的假主角跑 pace-min 分钟（局内时间）。
## 打印：每分钟击杀（普通 / 精英 / 首领）、场上平均几只、身边 40 米内几只、身边 120 米一只都没有的时间占比、平均几下打死一只、
## 心得（原始，不封顶）、怪掉的东西（修为丹按品阶×品质折成修为、破境丹 / 残片件数、其余按价值折成灵石）。
## 最后每个区域一行 `[pace-json]`（机读），给 `_tasks/numbers_sim/life_sim.gd` 当输入。
## 假主角怎么玩（都是假设，改这里就能换一种玩法再量）：
##   · 找 120 米内最近的活怪（游荡首领排在小怪后面），飞过去（结丹前 10 米/秒，之后 18 米/秒），贴身后每 0.4 秒一下，
##     每下 = 当前境界基准伤害 × pace-hit（走真实的受击入口：等级、怪的血量、天道压制都算在内）。pace-hit 1.5 ≈ 普攻夹技能
##   · 身边没怪就朝一个慢慢转的方向逛（导演会在新地方刷），离开落点 200 米就往回
##   · 不搜点、不撤离、不会死（主角无敌）——量的是怪的供给、打一只要多久、杀怪的产出
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const Profile := preload("res://scripts/raid_profile.gd")

const SEEK_R := 120.0
const NEAR_R := 40.0
const ENTRY_REALM := [0, 2, 3, 4, 5]      # 各区域的入门境界（和 sim / life_sim 的选图规则一致）


static func _spot(ri: int, depth: float) -> Vector2:
	if ri <= 0:
		return Vector2(0.6, 0.8) * (depth * Prog.MEADOW_DEPTH_R)
	var d: Vector2 = Data.REGIONS[ri]["dir"]
	return d * (Data.R0 + depth * (Prog.LAIR_R - Data.R0))


static func run(main: Node) -> void:
	var rd: Variant = main.level.raid
	var player: Player = main.player
	var level: Variant = main.level
	var tree: SceneTree = main.get_tree()
	var minutes := 5.0
	var speed := 6.0
	var depth := 0.35
	var hit_k := 1.5
	var regions: Array = [0, 1, 2, 3, 4]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pace-min="):
			minutes = float(a.get_slice("=", 1))
		elif a.begins_with("--pace-speed="):
			speed = float(a.get_slice("=", 1))
		elif a.begins_with("--pace-depth="):
			depth = float(a.get_slice("=", 1))
		elif a.begins_with("--pace-hit="):
			hit_k = float(a.get_slice("=", 1))
		elif a.begins_with("--pace-regions="):
			regions = []
			for s: String in a.get_slice("=", 1).split(","):
				regions.append(int(s))
	if OS.get_cmdline_user_args().has("--pace-perf"):
		await _perf(main, rd, player, tree)
		return
	print("[pace] 开始：每个区域 %.0f 分钟（局内），%.0f 倍速，深度 %.2f，出手 ×%.1f；同屏上限 %d 只" % [minutes, speed, depth, hit_k, int(rd.mob_cap())])
	var lines: Array = []
	for ri: int in regions:
		var out: Dictionary = await _one(main, rd, player, level, tree, ri, depth, minutes, speed, hit_k)
		lines.append(out)
	Engine.time_scale = 1.0
	for o: Dictionary in lines:
		print("[pace-json] " + JSON.stringify(o))


## `--pace-perf`：怪加密以后的帧耗时。原地站着等导演把周围铺满（1 倍速、主角不出手），各量 10 秒：
## 照常 / 怪藏起来（只省渲染）/ 怪藏起来又停了逻辑。手机档配 `--touch --rendering-method gl_compatibility --disable-vsync`
static func _perf(main: Node, rd: Variant, player: Player, tree: SceneTree) -> void:
	Engine.time_scale = 1.0
	player.set_realm(0, false)
	rd._credits = 420.0
	await main._raid_goto(_spot(0, 0.35), 0.0)
	var t := 0.0
	while t < 30.0:
		await tree.process_frame
		t += main.get_process_delta_time()
		player.velocity = Vector3.ZERO
	var res: Array = []
	for mode in 3:
		rd._mob_root.visible = mode == 0
		rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED if mode == 2 else Node.PROCESS_MODE_INHERIT
		await main._wait(0.5)
		var ms: Array[float] = []
		var alive := 0
		var tt := 0.0
		while tt < 10.0:
			await tree.process_frame
			var dt: float = main.get_process_delta_time()
			tt += dt
			ms.append(dt * 1000.0)
			alive = rd._mobs.size()
		ms.sort()
		var avg := 0.0
		for v: float in ms:
			avg += v
		avg /= maxf(float(ms.size()), 1.0)
		res.append([avg, ms[int(0.95 * float(ms.size() - 1))], ms[ms.size() - 1], alive])
		print("[perf] %s：%d 只怪，平均 %.2f ms、95%% %.2f ms、最长 %.1f ms" % [["照常", "怪藏起来", "怪藏起来 + 停逻辑"][mode], alive,
				avg, float(res[mode][1]), float(res[mode][2])])
	rd._mob_root.visible = true
	rd._mob_root.process_mode = Node.PROCESS_MODE_INHERIT
	var n := maxf(float(res[0][3]), 1.0)
	print("[perf] 每只怪：渲染 %.3f ms、逻辑 %.3f ms（%d 只合计 %.2f ms）" % [(float(res[0][0]) - float(res[1][0])) / n, (float(res[1][0]) - float(res[2][0])) / n,
			int(n), float(res[0][0]) - float(res[2][0])])


static func _one(main: Node, rd: Variant, player: Player, level: Variant, tree: SceneTree, ri: int, depth: float, minutes: float, speed: float, hit_k: float) -> Dictionary:
	Engine.time_scale = 1.0
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()
	for pk: Variant in rd._pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	rd._pickups.clear()
	var realm: int = ENTRY_REALM[ri]
	player.set_realm(realm, false)
	Profile.data()["realm"] = realm
	Profile.set_cult(realm * Prog.LV_PER_REALM + 2, 0.0)
	rd._sync_cult()
	rd.run_t = 0.0
	rd.kills = 0
	rd.insight = 0.0
	rd._credits = 70.0
	rd._wave_t = 2.5
	rd._event_t = 200.0
	var home := _spot(ri, depth)
	await main._raid_goto(home, 0.0)
	await main._wait(1.0)
	rd._update_here(player.global_position)
	print("[pace] —— %s（入门 %s Lv.%d）深度 %.2f：脚下怪 Lv.%d，天道压制 %d 档 ——" % [Data.REGIONS[ri]["name"], Realm.LIST[realm]["name"], int(rd.lv),
			float(rd.here_depth), int(rd.here_lv), int(rd.sup_gap)])
	Engine.time_scale = speed
	var t0: float = rd.run_t
	var seen := {}
	var tally := {"n": 0, "pill_n": 0, "pill_exp": 0.0, "heal": 0, "key": 0, "frag": 0, "coin": 0.0, "gear": 0, "items": 0}
	var kinds := {"mob": 0, "elite": 0, "boss": 0, "k_sum": 0.0}
	var hits := 0
	var hit_cd := 0.0
	var wander := 0.0
	var idle := 0.0
	var span := 0.0
	var mob_sum := 0.0
	var near_sum := 0.0
	var samples := 0
	var ins_raw := 0.0
	var minute := 0
	var k_at := 0
	var hooked := {}
	var v := 10.0 if realm < 2 else 18.0
	var dmg := float(player.realm["dmg"]) * hit_k
	while float(rd.run_t) - t0 < minutes * 60.0 and bool(rd.running):
		await tree.process_frame
		var dt: float = main.get_process_delta_time()
		span += dt
		var p := player.global_position
		var best: Variant = null
		var bd := 1.0e9
		var alive := 0
		var near := 0
		for m: Variant in rd._mobs:
			if not is_instance_valid(m) or not m.is_alive():
				continue
			alive += 1
			var dd: float = m.global_position.distance_to(p)
			if dd < NEAR_R:
				near += 1
			if dd > SEEK_R:
				continue
			var score := dd + (200.0 if bool(m.boss) else 0.0)
			if score < bd:
				bd = score
				best = m
		# 谁死了：每只怪第一次见到时挂上 died 信号记种类（rd.kills 只给总数；死了的怪很快就从 _mobs 里拿掉，轮询看不到）
		for m: Variant in rd._mobs:
			if is_instance_valid(m) and not hooked.has(m.get_instance_id()):
				hooked[m.get_instance_id()] = true
				var tag := "boss" if bool(m.boss) else ("elite" if bool(m.elite) else "mob")
				var xk := float(m.xp_k)
				m.died.connect(func(_x: Node3D) -> void:
					kinds[tag] = int(kinds[tag]) + 1
					kinds["k_sum"] = float(kinds["k_sum"]) + xk)
		mob_sum += float(alive)
		near_sum += float(near)
		samples += 1
		if best == null:
			idle += dt
			wander += dt * 0.05
			var w := Vector3(cos(wander), 0.0, sin(wander)) * v * dt
			var back := Vector3(home.x - p.x, 0.0, home.y - p.z)
			if back.length() > 200.0:
				w = back.normalized() * v * dt
			p += w
		else:
			var to: Vector3 = best.global_position - p
			to.y = 0.0
			if to.length() > 2.6:
				p += to.normalized() * minf(v * dt, to.length() - 2.0)
			else:
				hit_cd -= dt
				if hit_cd <= 0.0:
					hit_cd = 0.4
					hits += 1
					best.receive_hit(player, {"dmg": dmg, "dir": to.normalized() if to.length() > 0.01 else Vector3.FORWARD, "heavy": false, "kb": 0.5})
		p.y = float(level.ground(p.x, p.z)) + 0.05
		player.global_position = p
		player.velocity = Vector3.ZERO
		# 心得：每帧收走（不让本局上限截掉，量的是原始产出）
		ins_raw += float(rd.insight)
		rd.insight = 0.0
		# 新掉的东西
		for pk: Variant in rd._pickups:
			if not is_instance_valid(pk) or seen.has(pk.get_instance_id()):
				continue
			seen[pk.get_instance_id()] = true
			var list: Array = pk.items if not (pk.items as Array).is_empty() else [pk.item]
			for it: Dictionary in list:
				tally["items"] = int(tally["items"]) + 1
				var kind := str(it.get("kind", ""))
				if kind == "pill":
					if Items.is_xp_pill(it):
						tally["pill_n"] = int(tally["pill_n"]) + 1
						tally["pill_exp"] = float(tally["pill_exp"]) + Prog.pill_exp(int(it.get("tier", 0)), int(it.get("grade", 0)))
					else:
						tally["heal"] = int(tally["heal"]) + 1
				elif kind == "key":
					tally["key"] = int(tally["key"]) + 1
				elif kind == "frag":
					tally["frag"] = int(tally["frag"]) + 1
				else:
					if kind == "gear":
						tally["gear"] = int(tally["gear"]) + 1
					tally["coin"] = float(tally["coin"]) + float(it.get("value", 0))
		var mi := int((float(rd.run_t) - t0) / 60.0)
		if mi > minute:
			minute = mi
			print("[pace] %s 第 %d 分钟：杀 %2d 只（累计 %3d）｜场上平均 %.1f 只、40 米内 %.1f 只｜身边没怪 %2d%%｜心得累计 %.0f（本局上限 %.0f）" % [
					Data.REGIONS[ri]["name"], minute, int(rd.kills) - k_at, int(rd.kills), mob_sum / maxf(float(samples), 1.0),
					near_sum / maxf(float(samples), 1.0), int(100.0 * idle / maxf(span, 0.01)), ins_raw, float(rd.insight_cap())])
			k_at = int(rd.kills)
	Engine.time_scale = 1.0
	var mins := maxf((float(rd.run_t) - t0) / 60.0, 0.01)
	var kills := int(rd.kills)
	var o := {"region": ri, "realm": realm, "lv": int(rd.lv), "depth": depth, "mob_lv": int(Prog.mob_level(ri, depth)), "minutes": snappedf(mins, 0.01),
			"kpm": snappedf(float(kills) / mins, 0.01), "mob": kinds["mob"], "elite": kinds["elite"], "boss": kinds["boss"],
			"avg_k": snappedf(float(kinds["k_sum"]) / maxf(float(int(kinds["mob"]) + int(kinds["elite"]) + int(kinds["boss"])), 1.0), 0.01),
			"hits_per_kill": snappedf(float(hits) / maxf(float(kills), 1.0), 0.1), "alive": snappedf(mob_sum / maxf(float(samples), 1.0), 0.1),
			"near": snappedf(near_sum / maxf(float(samples), 1.0), 0.1), "idle": snappedf(idle / maxf(mins * 60.0, 0.01), 0.01),
			"insight_pm": snappedf(ins_raw / mins, 0.1), "insight_cap": snappedf(float(rd.insight_cap()), 1.0),
			"pill_pm": snappedf(float(tally["pill_n"]) / mins, 0.01), "pill_exp_pm": snappedf(float(tally["pill_exp"]) / mins, 0.1),
			"coin_pm": snappedf(float(tally["coin"]) / mins, 0.1), "items_pm": snappedf(float(tally["items"]) / mins, 0.01),
			"key": tally["key"], "frag": tally["frag"], "heal": tally["heal"], "gear": tally["gear"]}
	print("[pace] %s 小结：%.1f 分钟杀 %d 只（每分钟 %.1f；普通 %d / 精英 %d / 首领 %d），平均 %.1f 下打死一只；场上 %.1f 只、40 米内 %.1f 只、身边没怪 %d%%；" % [
			Data.REGIONS[ri]["name"], mins, kills, float(kills) / mins, int(kinds["mob"]), int(kinds["elite"]), int(kinds["boss"]), float(o["hits_per_kill"]),
			float(o["alive"]), float(o["near"]), int(100.0 * float(o["idle"]))] +
			"每分钟心得 %.0f（本局上限 %.0f）、修为丹 %.2f 颗（%.0f 修为）、其余掉落折 %.0f 灵石；破境丹 %d、残片 %d" % [float(o["insight_pm"]), float(o["insight_cap"]),
			float(o["pill_pm"]), float(o["pill_exp_pm"]), float(o["coin_pm"]), int(tally["key"]), int(tally["frag"])])
	return o
