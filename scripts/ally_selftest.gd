extends RefCounted
## AI 道友（ally_brain.gd / ally_team.gd / ally_puppet.gd）的自检。
## 单机行为：`-- --raid-shot --raid-ally [--ally-old] [--touch]`（main.gd 的 _run_raid_demo 调 solo）
##   两位 AI 道友，主角按脚本走五段：原地站着 → 走路赶路 → 御剑急飞后停下 → 被三只怪围着、残血 → 把道友打到残血 / 打空。
##   每段每位道友打印：离主角平均 / 最远多少米、贴在七米内的时间占比、各种状态各占多少；最后是每位道友的出手、击杀、闪避、
##   剑气、剑轮、服丹、重伤、喊话、探到的搜点，以及整段的帧耗时。`--ally-old` = 不挂大脑（老的贴身跟随），做前后对比。
## 联机同步：同一台机器开两个实例，`-- --net=ally_host`（房主，四人队）和 `-- --net=ally_mate`（加入，同队）。
##   房主那边应该有 2 个 AI 道友（4 人队 - 2 个真人），队友那边本机 0 个、看到 2 个木偶；两边各按系统时钟每 0.1 秒记一次（同一台机器，时钟是同一个）
##   这位道友的位置 / 血量 / 状态 / 招式序号 / 喊话数，存 _shots/net_ally_<角色>.txt，用 _tasks/ally_net/compare.py 对账。
##   队友那边另外数「被房主那边打过的、我名下的怪」（房主本人站着不动，所以只能是他的 AI 道友打的 → 伤害过网了）。
##   最后队友先退，房主那边 AI 道友应该补到 3 个。
## 故意不写 class_name：用 preload 引用。

const Brain := preload("res://scripts/ally_brain.gd")


static func _pct(a: float, b: float) -> int:
	return int(round(100.0 * a / maxf(b, 0.0001)))


## 跑一段：step(dt, t) 每帧挪主角；返回这段的帧耗时
static func _phase(main: Node, rd: Variant, title: String, secs: float, step: Callable, hp_keep: float, frames: PackedFloat32Array) -> void:
	var tree: SceneTree = main.get_tree()
	var player: Player = main.player
	var acc: Array = []
	for i in rd._allies.size():
		acc.append({"d": 0.0, "n": 0, "near": 0, "max": 0.0, "m": [0, 0, 0, 0, 0, 0, 0], "path": 0.0, "last": Vector3.INF})
	var t := 0.0
	while t < secs:
		await tree.process_frame
		var dt: float = main.get_process_delta_time()
		t += dt
		frames.append(dt * 1000.0)
		if hp_keep > 0.0:
			player.melee.hp = hp_keep
		step.call(dt, t)
		for i in mini(acc.size(), rd._allies.size()):
			var f: Variant = rd._allies[i]
			if not is_instance_valid(f):
				continue
			var a: Dictionary = acc[i]
			var d: float = f.global_position.distance_to(player.global_position)
			a["d"] = float(a["d"]) + d
			a["n"] = int(a["n"]) + 1
			a["max"] = maxf(float(a["max"]), d)
			if d < 7.0:
				a["near"] = int(a["near"]) + 1
			if f.brain != null:
				(a["m"] as Array)[int(f.brain.mode)] += 1
			if a["last"] != Vector3.INF:
				a["path"] = float(a["path"]) + (f.global_position - (a["last"] as Vector3)).length()
			a["last"] = f.global_position
	for i in acc.size():
		var a: Dictionary = acc[i]
		var f: Variant = rd._allies[i] if i < rd._allies.size() else null
		var n := float(a["n"])
		var parts: Array = []
		for k in Brain.M_NAMES.size():
			if int((a["m"] as Array)[k]) > 0:
				parts.append("%s %d%%" % [Brain.M_NAMES[k], _pct(float((a["m"] as Array)[k]), n)])
		print("[ally] %s｜%s：离主角平均 %.1f 米、最远 %.0f 米，贴在 7 米内 %d%%，自己飞了 %.0f 米｜%s" % [title,
				str(f.display_name) if is_instance_valid(f) else "（没了）", float(a["d"]) / maxf(n, 1.0), float(a["max"]), _pct(float(a["near"]), n),
				float(a["path"]), "、".join(parts) if not parts.is_empty() else "（老逻辑：没有状态）"])


static func solo(main: Node) -> void:
	var rd: Variant = main.level.raid
	var player: Player = main.player
	var level: Variant = main.level
	var old := OS.get_cmdline_user_args().has("--ally-old")
	main.net.team_size = 3
	rd._mob_root.visible = true
	await main._raid_goto(Vector2(20.0, 30.0), 0.0)
	var t0 := Time.get_ticks_msec()
	while rd._allies.size() < 2 and Time.get_ticks_msec() - t0 < 8000:
		await main._wait(0.2)
	print("[ally] 开始：%s；AI 道友 %d 位：%s；同屏怪上限 %d" % ["老逻辑（贴身跟随，--ally-old）" if old else "新大脑", rd._allies.size(),
			"、".join(rd._allies.map(func(f: Variant) -> String: return "%s（%s）" % [f.display_name,
			Brain.KIND_NAMES[f.brain.kind] if f.brain != null else "老"])), int(rd.mob_cap())])
	if rd._allies.size() < 2:
		print("[ally] 道友没到齐，退出")
		return
	# 主角按脚本走：关掉他自己的处理，位置和速度由这里摆（大脑只读这两样）
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var frames := PackedFloat32Array()
	var kills0 := int(rd.kills)
	var place := func(p: Vector3, v: Vector3) -> void:
		player.global_position = p
		player.velocity = v
	var stand := func(_dt: float, _t: float) -> void:
		player.velocity = Vector3.ZERO
	await _phase(main, rd, "1 原地站着（前 12 秒）", 12.0, stand, 100.0, frames)
	await main._shot("ally_1_stand")
	await _phase(main, rd, "1 原地站着（后 13 秒）", 13.0, stand, 100.0, frames)
	var walk := func(dt: float, _t: float) -> void:
		var p := player.global_position + Vector3(8.0 * dt, 0.0, 0.0)
		p.y = float(level.ground(p.x, p.z)) + 0.05
		place.call(p, Vector3(8.0, 0.0, 0.0))
	await _phase(main, rd, "2 走路 8 米/秒 20 秒", 20.0, walk, 100.0, frames)
	await main._shot("ally_2_walk")
	var fly := func(dt: float, _t: float) -> void:
		var p := player.global_position + Vector3(0.0, 0.0, 45.0 * dt)
		p.y = float(level.ground(p.x, p.z)) + 14.0
		place.call(p, Vector3(0.0, 0.0, 45.0))
	await _phase(main, rd, "3 御剑急飞 45 米/秒 8 秒", 8.0, fly, 100.0, frames)
	# 停下来：数多久全员回到 20 米内
	var land := player.global_position
	land.y = float(level.ground(land.x, land.z)) + 0.05
	place.call(land, Vector3.ZERO)
	var back := -1.0
	var tb := 0.0
	while tb < 12.0:
		await main.get_tree().process_frame
		tb += main.get_process_delta_time()
		player.melee.hp = 100.0
		var all_in := true
		for f: Variant in rd._allies:
			if is_instance_valid(f) and f.global_position.distance_to(player.global_position) > 20.0:
				all_in = false
		if all_in:
			back = tb
			break
	print("[ally] 3 急飞 360 米后停下：全员回到 20 米内用了 %s" % ("%.1f 秒" % back if back >= 0.0 else "超过 12 秒（没回来）"))
	await _phase(main, rd, "3 停下后 8 秒", 8.0, stand, 100.0, frames)
	# 被围、残血
	var assists0 := 0
	for f: Variant in rd._allies:
		if f.brain != null:
			assists0 += int(f.brain.stat["assists"])
	rd.spawn_guards(player.global_position, int(rd.region), 3, false, true)
	var kills4 := int(rd.kills)
	var react := -1.0
	var tr := 0.0
	var mobs_near0 := 0
	for m: Variant in rd._mobs:
		if is_instance_valid(m) and m.global_position.distance_to(player.global_position) < 16.0:
			mobs_near0 += 1
	while tr < 14.0:
		await main.get_tree().process_frame
		tr += main.get_process_delta_time()
		player.melee.hp = 28.0
		if react < 0.0:
			for f: Variant in rd._allies:
				var pr: Variant = f.brain.target if f.brain != null else f.get("_prey")
				if pr != null and is_instance_valid(pr) and pr.global_position.distance_to(player.global_position) < 16.0:
					react = tr
	await main._shot("ally_4_assist")
	var mobs_near1 := 0
	for m: Variant in rd._mobs:
		if is_instance_valid(m) and m.is_alive() and m.global_position.distance_to(player.global_position) < 16.0:
			mobs_near1 += 1
	var assists1 := 0
	for f: Variant in rd._allies:
		if f.brain != null:
			assists1 += int(f.brain.stat["assists"])
	print("[ally] 4 主角残血、身边刷三只怪：第一位道友盯上主角身边的怪用了 %s；这 14 秒里击杀 %d 只（16 米内的怪 %d → %d 只，期间照常刷新）；「来救」次数 +%d" % [
			"%.1f 秒" % react if react >= 0.0 else "14 秒内没人来", int(rd.kills) - kills4, mobs_near0, mobs_near1, assists1 - assists0])
	player.melee.hp = 100.0
	print("[ally] 前四段（约 95 秒，主角自己不出手）这一队共击杀 %d 只" % (int(rd.kills) - kills0))
	if not old:
		# 道友残血 → 撤、服丹；打空 → 重伤离场、归队
		var a0: Variant = rd._allies[0]
		var heals0 := int(a0.brain.stat["heals"])
		a0.hp = a0.hp_max * 0.15
		a0.brain._heal_cd = 0.0
		var th := 0.0
		var seen_retreat := false
		while th < 9.0 and int(a0.brain.stat["heals"]) == heals0:
			await main.get_tree().process_frame
			th += main.get_process_delta_time()
			player.melee.hp = 100.0
			if int(a0.brain.mode) == Brain.M.RETREAT:
				seen_retreat = true
		print("[ally] 5 把 %s 的血压到一成半：进了撤退=%s，%s，现在血 %d%%" % [a0.display_name, seen_retreat,
				"%.1f 秒后服丹回气" % th if int(a0.brain.stat["heals"]) > heals0 else "9 秒内没服丹", _pct(float(a0.hp), float(a0.hp_max))])
		var a1: Variant = rd._allies[1]
		a1.brain._dodge_t = 0.0
		a1.brain.on_hit(float(a1.hp_max) * 4.0, Vector3.FORWARD, null, true)
		var down: bool = int(a1.brain.mode) == Brain.M.DOWN and not bool(a1.visible)
		var td := 0.0
		while td < 24.0 and int(a1.brain.mode) == Brain.M.DOWN:
			await main.get_tree().process_frame
			td += main.get_process_delta_time()
			player.melee.hp = 100.0
		print("[ally] 5 把 %s 打空：重伤离场=%s，%.1f 秒后归队=%s（离主角 %.0f 米、血 %d%%）" % [a1.display_name, down, td,
				a1.visible and int(a1.brain.mode) != Brain.M.DOWN, a1.global_position.distance_to(player.global_position),
				_pct(float(a1.hp), float(a1.hp_max))])
		for f: Variant in rd._allies:
			var s: Dictionary = f.brain.stat
			var mt: Array = s["mode_t"]
			var parts: Array = []
			for k in Brain.M_NAMES.size():
				if float(mt[k]) > 0.2:
					parts.append("%s %d%%" % [Brain.M_NAMES[k], _pct(float(mt[k]), float(s["t"]))])
			print("[ally] 全程｜%s（%s，水平 %.2f）：%s｜换过 %d 个目标（其中来救 %d 次）出手 %d 下 击杀 %d 剑气 %d 剑轮 %d 闪避 %d｜挨打 %d 下 撤退 %d 次 服丹 %d 次 重伤 %d 次｜喊话 %d 句 探到搜点 %d 处" % [
					f.display_name, Brain.KIND_NAMES[f.brain.kind], float(f.brain.skill), "、".join(parts), int(s["targets"]), int(s["assists"]),
					int(s["swings"]), int(s["kills"]), int(s["bolts"]), int(s["bursts"]), int(s["dodges"]), int(s["hits"]), int(s["retreats"]),
					int(s["heals"]), int(s["downs"]), int(s["says"]), int(s["sites"])])
	if not old and rd.search != null:
		# 6 清场 25 秒（不刷怪）：把主角挪到最近一处没探明的搜点 30 米外，看道友会不会自己去探、标到小地图上
		var best: Dictionary = {}
		var bd := 1.0e9
		for sd: Dictionary in rd.search.sites:
			if bool(sd["done"]) or bool(sd["known"]) or not bool(sd["live"]):
				continue
			var dd: float = (sd["pos"] as Vector3).distance_to(player.global_position)
			if dd < bd:
				bd = dd
				best = sd
		if best.is_empty():
			print("[ally] 6 附近没有没探明的搜点，跳过")
		else:
			rd._wave_t = 99999.0
			for m: Variant in rd._mobs.duplicate():
				if is_instance_valid(m):
					m.queue_free()
			rd._mobs.clear()
			var sp: Vector3 = best["pos"]
			var at := sp + Vector3(30.0, 0.0, 0.0)
			at.y = float(level.ground(at.x, at.z)) + 0.05
			place.call(at, Vector3.ZERO)
			rd.search.reveal_t = 0.0
			var sites0 := 0
			for f: Variant in rd._allies:
				sites0 += int(f.brain.stat["sites"])
				f.global_position = at + Vector3(randf_range(-6.0, 6.0), 1.5, randf_range(-6.0, 6.0))
				f.brain._way = Vector3.INF
				f.brain._seen.clear()
			var ts := 0.0
			var known_at := -1.0
			while ts < 25.0:
				await main.get_tree().process_frame
				ts += main.get_process_delta_time()
				player.melee.hp = 100.0
				# 搜点自己的「走近 70 米就探明」会抢先：这里一直把它按回没探明，只让道友来标
				if bool(best["known"]) and known_at < 0.0:
					var by_ally := false
					for f: Variant in rd._allies:
						if f.brain._seen.has(int(best["id"])):
							by_ally = true
					if by_ally:
						known_at = ts
					else:
						best["known"] = false
			var sites1 := 0
			for f: Variant in rd._allies:
				sites1 += int(f.brain.stat["sites"])
			print("[ally] 6 清场、主角站在一处没探明的搜点 30 米外：%s；这 25 秒里道友探到并标上地图的搜点 +%d 处" % [
					"%.1f 秒后有道友飞过去把它探明了" % known_at if known_at >= 0.0 else "25 秒内没人去探它", sites1 - sites0])
	var fs: Array = Array(frames)
	fs.sort()
	print("[ally] 帧耗时（%d 帧）：中位 %.1f ms、95 分位 %.1f ms、最长 %.1f ms；超过 33 ms 的 %d 帧" % [fs.size(), float(fs[fs.size() / 2]),
			float(fs[int(fs.size() * 0.95)]), float(fs[fs.size() - 1]), fs.filter(func(v: float) -> bool: return v > 33.0).size()])
	player.process_mode = Node.PROCESS_MODE_INHERIT


# ---------- 联机同步 ----------

static func net(main: Node, role: String) -> void:
	var out: Array = []
	var say := func(s: String) -> void:
		print("[net:%s] %s" % [role, s])
		out.append(s)
	var nt: Variant = main.net
	var player: Player = main.player
	var host := role == "ally_host"
	await main._wait(1.0)
	nt.my_name = "房主甲" if host else "队友乙"
	main.level_ui.team_size = 4      # 队伍定员只有 1 / 2 / 4（net.gd 的 _hello 会把别的数归到这三档）
	if host:
		main.level_ui.mode = "host"
	else:
		await main._wait(7.0)
		main.level_ui.mode = "join"
		main.level_ui.join_ip = "127.0.0.1"
	await main._enter_level("meadow")
	if main.level == null:
		say.call("没进去（加入失败）")
		main.get_tree().quit()
		return
	var rd: Variant = main.level.raid
	rd._mob_root.visible = true
	main._net_immortal()
	player.global_position = main.level.spawn_point() + (Vector3.ZERO if host else Vector3(14.0, 0.0, 4.0))
	var t_end := Time.get_ticks_msec() + 70000
	while Time.get_ticks_msec() < t_end and (nt.players.size() < 2 or nt.remotes.size() < 1):
		await main._wait(0.5)
	if nt.players.size() < 2:
		say.call("没等到两个人到齐（房间 %d 人）" % nt.players.size())
		main.get_tree().quit()
		return
	await main._wait(4.0)
	say.call("到齐：联机=%s 我的编号 %d 房间 %d 人 本队真人 %d 人（队伍定员 %d）；AI 道友归我算=%s，我这边应生成 %d 个，实际 %d 个，看到别人的 AI 道友木偶 %d 个" % [
			nt.active, nt.my_id, nt.players.size(), nt.team_count(), nt.team_size, rd.ally_team.is_owner(rd), rd.ally_want(), rd._allies.size(),
			rd.ally_team.puppets.size()])
	# 两边各记 30 秒：[房间时钟, 第几个, x, y, z, 血量比例, 状态, 喊话数, 招式序号, 名字]
	var rows: Array = []
	var hit_mobs := {}
	var host_id := 1
	var seen_st: Array = []           # 房主：队友木偶的状态序列（0 地面 1 起飞 2 飞行）
	var obs := {"dy": 0.0, "top": -1.0e9, "y0": 0.0, "v": 0.0}      # 房主：队友木偶单帧最大竖直位移、最高处、起点（匿名函数里改外面的普通变量不生效，放字典里）
	if host:
		var watch := func() -> void:
			var last_y := INF
			while main.level != null and rows.size() < 100000 and is_instance_valid(main.level):
				await main.get_tree().process_frame
				for id: int in nt.remotes.keys():
					var r: Variant = nt.remotes[id]
					if not is_instance_valid(r) or not r.visible:
						continue
					if seen_st.is_empty() or int(seen_st[seen_st.size() - 1]) != int(r.st):
						seen_st.append(int(r.st))
					var y: float = r.global_position.y
					if last_y != INF:
						obs["dy"] = maxf(float(obs["dy"]), absf(y - last_y))
						obs["v"] = maxf(float(obs["v"]), absf(y - last_y) / maxf(main.get_process_delta_time(), 1.0 / 120.0))
					else:
						obs["y0"] = y
					obs["top"] = maxf(float(obs["top"]), y)
					last_y = y
		watch.call()
	else:
		# 队友：10 秒后连点两下跳起飞（炼气期）、往前飞 3 秒、再点「飞」落地
		var flight := func() -> void:
			await main._wait(10.0)
			for k in 2:
				var ev := InputEventAction.new()
				ev.action = "jump"
				ev.pressed = true
				Input.parse_input_event(ev)
				await main._wait(0.05)
				var ev2 := InputEventAction.new()
				ev2.action = "jump"
				ev2.pressed = false
				Input.parse_input_event(ev2)
				await main._wait(0.25)
			var st_a := int(player.st)
			await main._wait(0.8)
			var st_b := int(player.st)
			Input.action_press("move_forward")
			await main._wait(3.0)
			Input.action_release("move_forward")
			var top: float = player.global_position.y
			var ev3 := InputEventAction.new()
			ev3.action = "fly"
			ev3.pressed = true
			Input.parse_input_event(ev3)
			await main._wait(0.05)
			var ev4 := InputEventAction.new()
			ev4.action = "fly"
			ev4.pressed = false
			Input.parse_input_event(ev4)
			await main._wait(2.0)
			say.call("我（%s期）连点两下跳：状态 %d → 0.8 秒后 %d（1 起飞 / 2 飞行）；飞了 3 秒到 %.1f 米高；点落后状态 %d、在地面=%s" % [
					player.realm["name"], st_a, st_b, top, int(player.st), player.is_on_floor()])
		flight.call()
	for i in 300:
		await main._wait(0.1)
		var t: float = fmod(Time.get_unix_time_from_system(), 100000.0)
		if host:
			for f: Variant in rd._allies:
				if is_instance_valid(f):
					rows.append("%.3f %d %.2f %.2f %.2f %.3f %d %d %d %s" % [t, int(f.ally_slot), f.global_position.x, f.global_position.y, f.global_position.z,
							float(f.hp) / float(f.hp_max), int(f.brain.mode) if f.brain != null else -1, int(f.brain.say_n) if f.brain != null else 0,
							int(f.rig.play_n), f.display_name])
		else:
			for p: Variant in rd.ally_team.puppets.values():
				if is_instance_valid(p) and p._got:
					rows.append("%.3f %d %.2f %.2f %.2f %.3f %d %d %d %s" % [t, int(p.slot), p.global_position.x, p.global_position.y, p.global_position.z,
							float(p.hp_r), int(p.mode), int(p._say_n), int(p._pose_n), p.display_name])
			for m: Variant in rd._mobs:
				if is_instance_valid(m) and int(m.get_meta("hitter", 0)) == host_id:
					hit_mobs[int(m.net_id)] = true
	var fw := FileAccess.open("res://_shots/net_ally_%s.txt" % ("host" if host else "mate"), FileAccess.WRITE)
	if fw != null:
		fw.store_string("\n".join(rows))
		fw.close()
	if host:
		var parts: Array = []
		for f: Variant in rd._allies:
			if is_instance_valid(f) and f.brain != null:
				var s: Dictionary = f.brain.stat
				parts.append("%s：换过 %d 个目标、出手 %d 下、击杀 %d、喊话 %d 句" % [f.display_name, int(s["targets"]), int(s["swings"]), int(s["kills"]), int(s["says"])])
		say.call("30 秒里：记了 %d 行；发出去 %d 批 AI 道友状态；%s" % [rows.size(), int(rd.ally_team.sent), "；".join(parts)])
		say.call("看队友（真人）起飞落地：他的木偶在我这边的状态序列 %s（0 地面 1 起飞 2 飞行），最高比起点高 %.1f 米，木偶单帧最大竖直位移 %.2f 米、最大竖直速度 %.1f 米/秒（卡顿帧之后木偶会一帧追上，所以看速度）" % [
				str(seen_st), float(obs["top"]) - float(obs["y0"]), float(obs["dy"]), float(obs["v"])])
		# 队友退了以后：AI 道友应该补到 2 个
		var t2 := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < t2 and nt.players.size() > 1:
			await main._wait(0.5)
		await main._wait(3.0)
		say.call("队友退出后：房间 %d 人，AI 道友 %d 个（应为 3）" % [nt.players.size(), rd._allies.size()])
	else:
		var pn := 0
		var says := 0
		var names: Array = []
		for p: Variant in rd.ally_team.puppets.values():
			if is_instance_valid(p):
				pn += 1
				says += int(p.says)
				names.append("%s（标成队友=%s，收到 %d 次状态）" % [p.display_name, p.mate, int(p.pushes)])
		say.call("30 秒里：记了 %d 行；本机 AI 道友 %d 个（应为 0）、木偶 %d 个：%s；收到 %d 批；木偶头顶冒过 %d 句话；我名下的怪被房主那边打过的有 %d 只（房主本人没动手 → 是他的 AI 道友打的）" % [
				rows.size(), rd._allies.size(), pn, "、".join(names), int(rd.ally_team.got), says, hit_mobs.size()])
	var f2 := FileAccess.open("res://_shots/net_ally_%s_log.txt" % ("host" if host else "mate"), FileAccess.WRITE)
	if f2 != null:
		f2.store_string("\n".join(out))
		f2.close()
	if host:
		main.get_tree().root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		await main._wait(3.0)
	main.get_tree().quit()
