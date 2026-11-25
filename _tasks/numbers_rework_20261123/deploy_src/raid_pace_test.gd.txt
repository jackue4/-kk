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
## 2026-11-23 数值重构（对标 Hammer）：`--pace-byrealm[=0,1,...]`（默认八个境界、每档 --pace-min 默认 3 分钟）：每个境界的第 1 / 2 / 3 级各量一次，
##   区域 = Prog.REALM_REGION[境界]、深度 = (Prog.REALM_MOB_LV[境界] − 区域基础等级) / Prog.DEPTH_LV（怪正好是本境界那一档），
##   假主角只打 Prog.mob_tag ≤ 自己境界、离起点 200 米内的怪；每次一行 `[pace-json]`，带 "by": "realm" / realm / lv，life_sim 按（境界, 境内第几级）读。
##   --pace-combat 的「单位」改成 掉的血 ÷ CS.raid_hit(base, 境界, 等级, 0, 木桩的防量级)（伤害公式带防御项以后不再和攻击力成正比）；木桩血 1e13
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const CS := preload("res://scripts/combat_stats.gd")

const SEEK_R := 120.0
const DUMMY_HP := 1.0e13         # 「打不死」的木桩 / 受击测试那只怪的血（2026-11-23：1e7 在新曲线下会被打穿）
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
	var byrealm: Array = []
	var min_set := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pace-cap="):
			rd.cap_override = int(a.get_slice("=", 1))      # 量改前的上限（例如手机档原来的 15）
		if a == "--pace-byrealm":
			byrealm = [0, 1, 2, 3, 4, 5, 6, 7]
		elif a.begins_with("--pace-byrealm="):
			for s: String in a.get_slice("=", 1).split(","):
				byrealm.append(clampi(int(s), 0, 7))
		if a.begins_with("--pace-min="):
			minutes = float(a.get_slice("=", 1))
			min_set = true
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
	if OS.get_cmdline_user_args().has("--pace-spawn"):
		await _spawn_probe(main, rd, player, tree)
		return
	if OS.get_cmdline_user_args().has("--pace-combat"):
		await _combat(main, rd, player, tree)
		return
	if OS.get_cmdline_user_args().has("--pace-insight"):
		await _insight(main, rd, player, tree)
		return
	if OS.get_cmdline_user_args().has("--pace-perf"):
		await _perf(main, rd, player, tree)
		return
	if not byrealm.is_empty():
		# 2026-11-23：按境界量（每个境界第 1 / 2 / 3 级各一次），见文件头
		if not min_set:
			minutes = 3.0
		print("[pace] 按境界开始：境界 %s，每次 %.0f 分钟（局内），%.0f 倍速，出手 ×%.1f；同屏上限 %d 只" % [str(byrealm), minutes, speed, hit_k, int(rd.mob_cap())])
		var rows: Array = []
		for r: int in byrealm:
			var rri: int = Prog.REALM_REGION[r]
			var rdep := clampf(float(Prog.REALM_MOB_LV[r] - int(Data.REGIONS[rri]["lv"])) / float(Prog.DEPTH_LV[rri]), 0.0, 1.0)
			for j in range(1, Prog.LV_PER_REALM + 1):
				if not is_instance_valid(rd) or not bool(rd.running):
					print("[pace] 局已结束，按境界量到此为止")
					break
				var o: Dictionary = await _one(main, rd, player, level, tree, rri, rdep, minutes, speed, hit_k, r, r * Prog.LV_PER_REALM + j)
				rows.append(o)
				print("[pace-row] " + JSON.stringify(o))      # 边量边打印：中途断了也留得下前面的
		Engine.time_scale = 1.0
		for o: Dictionary in rows:
			print("[pace-json] " + JSON.stringify(o))
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
	var cost: Array = []
	_cost_begin(main)
	for mode in 3:
		rd._mob_root.visible = mode == 0
		rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED if mode == 2 else Node.PROCESS_MODE_INHERIT
		await main._wait(0.5)
		var ms: Array[float] = []
		var alive := 0
		var tt := 0.0
		var acc := [0.0, 0.0, 0.0, 0.0, 0]
		while tt < 10.0:
			await tree.process_frame
			var dt: float = main.get_process_delta_time()
			tt += dt
			ms.append(dt * 1000.0)
			alive = rd._mobs.size()
			_cost_add(main, acc)
		ms.sort()
		var avg := 0.0
		for v: float in ms:
			avg += v
		avg /= maxf(float(ms.size()), 1.0)
		res.append([avg, ms[int(0.95 * float(ms.size() - 1))], ms[ms.size() - 1], alive])
		cost.append(_cost_avg(acc))
		print("[perf] %s：%d 只怪，帧间隔平均 %.2f ms、95%% %.2f ms、最长 %.1f ms｜实际耗时（不受锁帧影响）：逻辑 %.2f + 物理 %.2f + 渲染提交 %.2f ms，显卡 %.2f ms" % [
				["照常", "怪藏起来", "怪藏起来 + 停逻辑"][mode], alive, avg, float(res[mode][1]), float(res[mode][2]),
				float(cost[mode][0]), float(cost[mode][1]), float(cost[mode][2]), float(cost[mode][3])])
	rd._mob_root.visible = true
	rd._mob_root.process_mode = Node.PROCESS_MODE_INHERIT
	var n := maxf(float(res[0][3]), 1.0)
	var c0: Array = cost[0]
	var c1: Array = cost[1]
	var c2: Array = cost[2]
	var r_cpu := float(c0[2]) - float(c1[2])
	var r_gpu := float(c0[3]) - float(c1[3])
	var logic := (float(c1[0]) + float(c1[1])) - (float(c2[0]) + float(c2[1]))
	print("[perf] 每只怪（按实际耗时算）：渲染提交 %.3f ms、显卡 %.3f ms、逻辑 + 物理 %.3f ms；%d 只合计 %.2f ms（显卡另算 %.2f ms）" % [r_cpu / n, r_gpu / n, logic / n,
			int(n), r_cpu + logic, r_gpu])


## 实际耗时：逻辑（_process）/ 物理 / 渲染提交（CPU）/ 显卡，都按毫秒；锁了帧率也量得出来
static func _cost_begin(main: Node) -> void:
	RenderingServer.viewport_set_measure_render_time(main.get_viewport().get_viewport_rid(), true)


static func _cost_add(main: Node, acc: Array) -> void:
	var rid: RID = main.get_viewport().get_viewport_rid()
	acc[0] = float(acc[0]) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	acc[1] = float(acc[1]) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	acc[2] = float(acc[2]) + RenderingServer.viewport_get_measured_render_time_cpu(rid)
	acc[3] = float(acc[3]) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
	acc[4] = int(acc[4]) + 1


static func _cost_avg(acc: Array) -> Array:
	var n := maxf(float(acc[4]), 1.0)
	return [float(acc[0]) / n, float(acc[1]) / n, float(acc[2]) / n, float(acc[3]) / n]


## `--pace-insight [--touch]`：心得光点（insight_fx.gd）自检，约 1 分钟：
##   一、身边摆五只小怪一齐打死：放了几颗光点、多久开始到 / 全部到齐、信息牌上的数（insight_shown）怎么追上真数（insight）、头顶飘字合成了几行；
##   二、打一只精英：三颗金色光点；三、心得满了再杀：不该放光点、数不动；
##   四、主角在飞（每秒 60 米横着飞）时杀的、80 米外分到的：光点都要在 1.4 秒上下追到身上，不许「超时当场消失」（timeouts 要是 0）；
##   五、信息牌：数是滚着涨上去的、纸条下面冒过「心得 +N」；
##   六、再来一拨拍图（光点在飞 / 飘字和纸条下的「+N」）raid_ins_*；
##   七、帧耗时：同一进程里交替量「身边一直有十颗上下光点在飞」和「没有光点」各 1.2 秒 × 4 轮（要配 --disable-vsync，帧耗时才不被垂直同步抹平）。
## 打印 `[insight]`，最后一行是 PASS / FAIL 小结。
static func _insight(main: Node, rd: Variant, player: Player, tree: SceneTree) -> void:
	Engine.time_scale = 1.0
	player.set_realm(0, false)
	Profile.data()["realm"] = 0
	Profile.set_cult(2, 0.0)
	rd._sync_cult()
	await main._raid_goto(_spot(0, 0.3), 0.0)
	await main._wait(1.5)
	_quiet(rd)
	_clear_mobs(rd)
	rd.insight = 0.0
	rd.insight_shown = 0.0
	var fx: Variant = rd._ins_fx
	var fails: Array = []
	var cam: Variant = main.cam
	# 一、五只小怪一齐打死
	var mobs := _ring_mobs(rd, player, 5, 0, 7.0)
	cam.snap(0.6, -0.32, 10.0)
	await _quiet_wait(main, rd, 0.5)
	_quiet(rd)
	var l0 := int(fx.launched)
	var a0 := int(fx.arrived)
	var f0 := int(fx.floats_made)
	var to0 := int(fx.timeouts)
	var ins0: float = rd.insight
	var chip_seen := false
	var disp_steps := 0
	var last_disp := -1.0
	_kill(mobs, player)
	var ins1: float = rd.insight
	var t := 0.0
	var first := -1.0
	var done := -1.0
	var peak := 0
	var trace: Array = []
	var next_s := 0.0
	while t < 2.2:
		await tree.process_frame
		t += main.get_process_delta_time()
		_quiet(rd)
		peak = maxi(peak, int(fx.pending()))
		var hud: Variant = rd.hud
		if hud._ins_chip != null and bool(hud._ins_chip.visible) and float(hud._ins_chip.modulate.a) > 0.5 and str(hud._ins_chip.text).begins_with("心得 +"):
			chip_seen = true
		var dsp: float = hud._ins_disp
		if dsp > last_disp + 0.001 and last_disp >= 0.0:
			disp_steps += 1
		last_disp = dsp
		var sh: float = rd.insight_shown
		if first < 0.0 and sh > ins0 + 0.01:
			first = t
		if done < 0.0 and sh >= ins1 - 0.01:
			done = t
		if t >= next_s:
			next_s += 0.2
			trace.append("%.1fs %s" % [t, Prog.short_num(sh)])
	var nl := int(fx.launched) - l0
	var na := int(fx.arrived) - a0
	var nf := int(fx.floats_made) - f0
	print("[insight] 五只小怪：心得 %s → %s（杀的那一刻就记上），光点放了 %d 颗（应为 5）、到了 %d 颗，同时在飞最多 %d 颗；信息牌的数 %.2f 秒开始涨、%.2f 秒追平；头顶飘字 %d 行（合成过，应少于 5）" % [
			Prog.short_num(ins0), Prog.short_num(ins1), nl, na, peak, first, done, nf])
	print("[insight]   信息牌的数：" + "　".join(trace))
	print("[insight]   信息牌：纸条上的数分 %d 帧滚上去（应多于 1 帧），纸条下冒过「心得 +N」=%s；超时消失 %d 颗（应为 0）" % [disp_steps, str(chip_seen), int(fx.timeouts) - to0])
	if nl != 5 or na != 5:
		fails.append("小怪光点数 %d / %d" % [nl, na])
	if disp_steps < 2 or not chip_seen:
		fails.append("信息牌没滚 / 没冒 +N（%d 帧，%s）" % [disp_steps, str(chip_seen)])
	if int(fx.timeouts) - to0 > 0:
		fails.append("站着杀也有光点超时")
	if first < 0.15 or done < 0.0 or done > 1.6:
		fails.append("追平时间 %.2f / %.2f" % [first, done])
	if nf < 1 or nf >= 5:
		fails.append("飘字行数 %d" % nf)
	# 二、精英
	await _quiet_wait(main, rd, 0.6)
	var el := _ring_mobs(rd, player, 1, 1, 8.0)
	await _quiet_wait(main, rd, 0.4)
	l0 = int(fx.launched)
	ins0 = rd.insight
	_kill(el, player)
	await _quiet_wait(main, rd, 1.8)
	_quiet(rd)
	nl = int(fx.launched) - l0
	print("[insight] 精英：光点 %d 颗（应为 3，金色），心得 +%s，信息牌追平=%s" % [nl, Prog.short_num(float(rd.insight) - ins0), str(absf(float(rd.insight_shown) - float(rd.insight)) < 0.01)])
	if nl != 3:
		fails.append("精英光点数 %d" % nl)
	# 三、心得满了
	rd.insight = rd.insight_cap()
	await tree.process_frame
	var full := _ring_mobs(rd, player, 1, 0, 7.0)
	await _quiet_wait(main, rd, 0.3)
	l0 = int(fx.launched)
	ins0 = rd.insight
	_kill(full, player)
	await _quiet_wait(main, rd, 0.5)
	nl = int(fx.launched) - l0
	print("[insight] 心得已满再杀：光点 %d 颗（应为 0），心得 %s → %s（应不变）" % [nl, Prog.short_num(ins0), Prog.short_num(rd.insight)])
	if nl != 0 or absf(float(rd.insight) - ins0) > 0.01:
		fails.append("满了还放光点 %d" % nl)
	rd.insight = 0.0
	await _quiet_wait(main, rd, 0.3)
	if absf(float(rd.insight_shown)) > 0.01:
		fails.append("清零后信息牌没跟着清 %.1f" % float(rd.insight_shown))
	# 四、主角在飞时杀的 / 80 米外分到的
	var fly := _ring_mobs(rd, player, 3, 0, 9.0)
	await _quiet_wait(main, rd, 0.4)
	to0 = int(fx.timeouts)
	a0 = int(fx.arrived)
	l0 = int(fx.launched)
	_kill(fly, player)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var far: Vector3 = player.global_position + Vector3(cos(a), 0.6, sin(a)) * 80.0
		rd.insight = float(rd.insight) + 5.0
		fx.launch(far, 5.0, 0)
	var dirv := Vector3(1.0, 0.0, 0.3).normalized()
	var tf := 0.0
	var arrive_t := -1.0
	while tf < 2.4:
		await tree.process_frame
		var dt2: float = main.get_process_delta_time()
		tf += dt2
		_quiet(rd)
		if tf < 1.6:
			var pp: Vector3 = player.global_position + dirv * 60.0 * dt2
			pp.y = float(rd._ground(pp.x, pp.z)) + 3.0
			player.global_position = pp
			player.velocity = Vector3.ZERO
		if arrive_t < 0.0 and int(fx.arrived) - a0 >= int(fx.launched) - l0:
			arrive_t = tf
	print("[insight] 主角每秒 60 米横飞时杀 3 只 + 80 米外分到 3 份：放了 %d 颗、到了 %d 颗，%.2f 秒全到，超时消失 %d 颗（应为 0）" % [
			int(fx.launched) - l0, int(fx.arrived) - a0, arrive_t, int(fx.timeouts) - to0])
	if int(fx.timeouts) - to0 > 0 or int(fx.arrived) - a0 != int(fx.launched) - l0 or arrive_t < 0.0 or arrive_t > 1.6:
		fails.append("飞着 / 远处的光点没追上（超时 %d，%.2f 秒）" % [int(fx.timeouts) - to0, arrive_t])
	await main._raid_goto(_spot(0, 0.3), 0.0)
	await _quiet_wait(main, rd, 1.0)
	# 六、拍图：一圈六只（含一只精英），光点在飞时一张、飘字 + 纸条下「+N」时一张
	mobs = _ring_mobs(rd, player, 6, 1, 8.0)
	cam.snap(0.6, -0.3, 10.0)
	await _quiet_wait(main, rd, 0.6)
	_quiet(rd)
	_kill(mobs, player)
	await _quiet_wait(main, rd, 0.25)
	await main._shot("raid_ins_1_fly")
	await _quiet_wait(main, rd, 0.6)      # 头一颗约 0.65 秒到、再过 0.25 秒合成一行飘字
	await main._shot("raid_ins_2_float")
	await _quiet_wait(main, rd, 1.6)
	# 五、帧耗时：同一进程里交替量
	var with_ms: Array = []
	var none_ms: Array = []
	var with_cost: Array = []
	var none_cost: Array = []
	_cost_begin(main)
	var with_max := 0.0
	var none_max := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for rn in 8:
		await _quiet_wait(main, rd, 0.3)
		var wait_t := 0.0
		while (int(fx.pending()) > 0 or not (fx._floats as Array).is_empty()) and wait_t < 3.0:      # 上一轮的光点 / 飘字都收完再量
			await tree.process_frame
			wait_t += main.get_process_delta_time()
			_quiet(rd)
		var ms: Array[float] = []
		var tt := 0.0
		var feed := 0.0
		var acc := [0.0, 0.0, 0.0, 0.0, 0]
		while tt < 1.2:
			await tree.process_frame
			var dt: float = main.get_process_delta_time()
			tt += dt
			_quiet(rd)
			ms.append(dt * 1000.0)
			_cost_add(main, acc)
			if rn % 2 == 0:
				feed -= dt
				if feed <= 0.0:
					feed = 0.12
					var a := rng.randf() * TAU
					var from: Vector3 = player.global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(6.0, 14.0)
					rd.insight = minf(float(rd.insight) + 1.0, float(rd.insight_cap()))      # 照真杀怪的顺序：先记上，再放光点（信息牌那半也跟着跑）
					fx.launch(from, 1.0, 0 if rng.randf() < 0.8 else 1)
		ms.sort()
		var avg := 0.0
		for v: float in ms:
			avg += v
		avg /= maxf(float(ms.size()), 1.0)
		var ca := _cost_avg(acc)
		var tot := float(ca[2]) + float(ca[3])      # 渲染提交 + 显卡（逻辑另用直接计时量；Performance 的 TIME_PROCESS 在这台机器上含等待，不可比）
		if rn % 2 == 0:
			with_ms.append(avg)
			with_max = maxf(with_max, ms[ms.size() - 1])
			with_cost.append(tot)
		else:
			none_ms.append(avg)
			none_max = maxf(none_max, ms[ms.size() - 1])
			none_cost.append(tot)
	var wm := _median(with_ms)
	var nm := _median(none_ms)
	print("[insight] 帧耗时（同一进程交替各 4 轮，光点那轮每 0.12 秒补一颗、同时在飞十颗上下）：帧间隔 有光点 %.2f ms（最长 %.1f）、没有 %.2f ms（最长 %.1f）；" % [
			wm, with_max, nm, none_max] + "渲染提交 + 显卡 有光点 %.2f ms、没有 %.2f ms，差 %.3f ms" % [
			_median(with_cost), _median(none_cost), _median(with_cost) - _median(none_cost)])
	# 八、光点逻辑的纯耗时：一次放 12 颗，直接计时调 30 帧 _process（覆盖「往外弹」和「追」两段），重复 10 轮取平均
	await _quiet_wait(main, rd, 2.0)
	var us_sum := 0.0
	var calls := 0
	for b in 10:
		for i in 12:
			var a2 := TAU * float(i) / 12.0
			rd.insight = minf(float(rd.insight) + 1.0, float(rd.insight_cap()))
			fx.launch(player.global_position + Vector3(cos(a2), 0.0, sin(a2)) * 10.0, 1.0, 0)
		var t0 := Time.get_ticks_usec()
		for c in 30:
			fx._process(1.0 / 60.0)
		us_sum += float(Time.get_ticks_usec() - t0)
		calls += 30
		fx.clear()
		await tree.process_frame
	print("[insight] 光点逻辑：12 颗在飞时每帧 %.3f ms（直接计时 %d 次 _process，不含渲染）" % [us_sum / float(calls) / 1000.0, calls])
	print("[insight] 小结：%s" % ("PASS" if fails.is_empty() else "FAIL " + "；".join(fails)))


## `--pace-combat [--touch] [--pace-realms=0,1,2,4,7]`：战斗数值实测（2026-11-20 夜，combat_stats.gd 的验收），每个境界约 40 秒：
##   主角设成该境界中间那级、不带法宝，在该境界常去的区域：
##   一、灵力从 0 回满要几秒；
##   二、炼气 / 筑基：地面连招打一只不会死、不会动的木桩怪，每秒 / 每下多少「单位」
##       （2026-11-23 起单位 = 掉的血 ÷ 一个招式单位打这只木桩掉多少：CS.raid_hit(base, 境界, 等级, 0, 木桩的防量级 rd._target_scale)）；
##   三、结丹起：空中普攻连段、剑诀 Z / X / C 各放一次（单体，全中）、长按 E 连发 1.5 秒、Q 飞剑阵 4 秒，各打出多少单位；
##   四、本区一只正常的小怪贴身打主角：每下掉多少气血条，和公式 CS.to_bar 对一下；炼气 / 筑基再举着格挡挨几下，看是不是只擦掉一成五。
## 打印 `[combat]` 和每个境界一行 `[combat-json]`（剑诀全中的单位给 combat_stats.gd 的 SKILL_K 校准用）。
static func _combat(main: Node, rd: Variant, player: Player, tree: SceneTree) -> void:
	var realms: Array = [0, 1, 2, 4, 7]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pace-realms="):
			realms = []
			for x: String in a.get_slice("=", 1).split(","):
				realms.append(int(x))
	var rows: Array = []
	for r: int in realms:
		rows.append(await _combat_one(main, rd, player, tree, r))
	for o: Dictionary in rows:
		print("[combat-json] " + JSON.stringify(o))


static func _region_of(r: int) -> int:
	return [0, 0, 1, 2, 3, 4, 4, 4][clampi(r, 0, 7)]


## 主角正前方 dist 米、和主角同高处摆一只木桩怪（血极厚、不处理：不动不打），返回它。
## 2026-11-23：血 1e7 → 1e13（新曲线下大乘一下几亿；也别用 1e30：浮点精度会把小伤害整个吃掉）
static func _dummy(rd: Variant, player: Player, dist: float, idx := -1) -> Node3D:
	var ri := _region_of(player.realm_idx)
	var pool: Array = Data.REGIONS[ri]["mobs"]
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var pos := player.global_position + fwd * dist
	var m: Node3D = rd._spawn_mob(int(pool[0]) if idx < 0 else idx, ri, pos)
	rd._mobs.append(m)
	m.hp_max = DUMMY_HP
	m.hp = DUMMY_HP
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.global_position = pos
	return m


static func _units(list: Array, hp0: Array, unit: float) -> float:
	var s := 0.0
	for i in list.size():
		if is_instance_valid(list[i]):
			s += float(hp0[i]) - float(list[i].hp)
	return s / unit


## 2026-11-23：一个招式单位（境界 r 的 base）打木桩 d 实际掉多少血——和游戏里 player_dmg_vs 同一条路（不带法宝：自检前已 gear.clear()）
static func _unit_vs(rd: Variant, r: int, lv: int, d: Node3D) -> float:
	return CS.raid_hit(CS.base(r), r, lv, 0.0, float(rd._target_scale(d, CS.ATK_K_MOB)))


static func _combat_one(main: Node, rd: Variant, player: Player, tree: SceneTree, r: int) -> Dictionary:
	Engine.time_scale = 1.0
	_quiet(rd)
	_clear_mobs(rd)
	if player.st == Player.St.AIR or player.st != Player.St.GROUND:
		player.force_ground()
	player.set_realm(r, false)
	Profile.data()["realm"] = r
	Profile.set_cult(r * 3 + 2, 0.0)
	rd._sync_cult()
	rd.gear.clear()
	rd._recalc_fx()
	await main._raid_goto(_spot(_region_of(r), 0.3), 0.0)
	await _quiet_wait(main, rd, 1.0)
	var lv: int = rd.lv
	var atk := CS.atk(lv)
	var out := {"realm": r, "lv": lv, "atk": snappedf(atk, 0.1)}
	# 一、灵力回满
	player.mp = 0.0
	var t := 0.0
	while player.mp < player.mp_max() - 0.5 and t < 15.0:
		await tree.process_frame
		t += main.get_process_delta_time()
		_quiet(rd)
	out["mp_refill"] = snappedf(t, 0.01)
	out["mp_units"] = player.mp_max()
	if OS.get_cmdline_user_args().has("--pace-shots"):
		player.melee.hp = 100.0
		player.mp = player.mp_max() * 0.6
		await _quiet_wait(main, rd, 0.4)
		await main._shot("raid_cb_%d" % r)      # 玩家牌：气血按 CS.hp、灵力按 CS.mp_shown 显示
	print("[combat] %s Lv.%d 攻击力 %s：灵力 %.0f 单位（显示 %.0f），从 0 回满 %.2f 秒（应约 6.25 秒）" % [Realm.LIST[r]["name"], lv, Prog.short_num(atk),
			player.mp_max(), CS.mp_shown(r, player.mp_max()), t])
	if r <= 1:
		# 二、地面连招
		var d := _dummy(rd, player, 1.9)
		await _quiet_wait(main, rd, 0.3)
		var unit := _unit_vs(rd, r, lv, d)
		out["unit"] = snappedf(unit, 0.01)
		var hp0 := [float(d.hp)]
		var hits := 0
		var last := float(d.hp)
		t = 0.0
		var press := 0.0
		while t < 3.0:
			await tree.process_frame
			var dt: float = main.get_process_delta_time()
			t += dt
			_quiet(rd)
			press -= dt
			if press <= 0.0:
				press = 0.15
				player.melee.press_attack()
			if float(d.hp) < last - 0.01:
				hits += 1
				last = float(d.hp)
		var u := _units([d], hp0, unit)
		out["ground_ups"] = snappedf(u / 3.0, 0.01)
		out["ground_per_hit"] = snappedf(u / maxf(float(hits), 1.0), 0.01)
		print("[combat]   地面连招 3 秒：命中 %d 下、共 %.2f 单位（每下 %.2f，表里起手 / 二段 / 三段 = 1.125 / 1.375 / 2.125），每秒 %.2f" % [hits, u, u / maxf(float(hits), 1.0), u / 3.0])
		d.queue_free()
		rd._mobs.erase(d)
	else:
		# 三、空战
		player.enter_air_combat()
		await _quiet_wait(main, rd, 1.0)
		var air: Variant = player.air
		var d := _dummy(rd, player, 3.0)
		d.global_position = player.global_position + (-player.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 3.0
		air.target = d
		await _quiet_wait(main, rd, 0.3)
		var unit := _unit_vs(rd, r, lv, d)
		out["unit"] = snappedf(unit, 0.01)
		var hp0 := [float(d.hp)]
		t = 0.0
		var press := 0.0
		while t < 3.0:
			await tree.process_frame
			var dt: float = main.get_process_delta_time()
			t += dt
			_quiet(rd)
			player.mp = player.mp_max()
			press -= dt
			if press <= 0.0:
				press = 0.12
				air.press_attack()
		var u := _units([d], hp0, unit)
		out["chain_ups"] = snappedf(u / 3.0, 0.01)
		print("[combat]   空中普攻连按 3 秒：%.2f 单位（每秒 %.2f）" % [u, u / 3.0])
		# 剑诀：单体全中
		var sk: Array = []
		for i in 3:
			await _quiet_wait(main, rd, 0.6)
			d.global_position = player.global_position + (-player.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 12.0
			air.target = d
			air.cds = [0.0, 0.0, 0.0] as Array[float]
			player.mp = player.mp_max()
			var su := 0.0
			var spent := 0.0
			var ok := true
			for rep_i in 2:      # 放两次取平均（飞剑有散布，偶尔擦过）
				await _quiet_wait(main, rd, 0.4)
				air.target = d
				air.cds = [0.0, 0.0, 0.0] as Array[float]
				player.mp = player.mp_max()
				var h0 := [float(d.hp)]
				var mp0: float = player.mp
				ok = bool(air.press_skill(i)) and ok
				spent += (mp0 - player.mp) / player.mp_max() * 0.5
				await _quiet_wait(main, rd, 3.2)
				su += _units([d], h0, unit) * 0.5
			sk.append(snappedf(su, 0.01))
			print("[combat]   剑诀 %d「%s」%s：单体 %.2f 单位（目标 %.1f，两次平均），扣灵力 %.0f%%" % [i + 1, air.skill_name(i), "" if ok else "（没放出来）", su,
					CS.SKILL_TARGET[i] * CS.skill_g(r), 100.0 * spent])
		out["skills"] = sk
		# 连发 1.5 秒
		await _quiet_wait(main, rd, 0.8)
		player.mp = player.mp_max()
		air.target = d
		var hv := float(d.hp)
		Input.action_press("air_shot")
		var tv := 0.0
		var first := -1.0
		var hfirst := hv
		var drain := 0.0
		while tv < 3.5:
			await tree.process_frame
			var dtv: float = main.get_process_delta_time()
			tv += dtv
			_quiet(rd)
			if first < 0.0 and float(d.hp) < hv - 0.01:
				first = tv
				hfirst = hv
			if tv < 1.0:
				drain = player.mp      # 头一秒不补灵力：看连发每秒扣多少
			else:
				player.mp = player.mp_max()
		Input.action_release("air_shot")
		var vsec := 3.5 - maxf(first, 0.0)
		var vu := (hfirst - float(d.hp)) / unit
		out["volley_ups"] = snappedf(vu / maxf(vsec, 0.1), 0.01)
		print("[combat]   连发：第一剑 %.2f 秒到，之后 %.1f 秒共 %.2f 单位（每秒 %.2f，公式 %.2f），头一秒扣灵力 %.0f%%" % [first, vsec, vu, vu / maxf(vsec, 0.1),
				CS.volley_k(r) * float(Realm.LIST[r]["volley"]), 100.0 * (1.0 - drain / player.mp_max())])
		await _quiet_wait(main, rd, 1.0)
		# 飞剑阵 4 秒（召出来以后）
		player.mp = player.mp_max()
		main.swords.toggle_summon()
		# 飞剑要一柄柄召齐（is_ready）才开始出剑：大乘 24 柄要好几秒，等齐了再量稳定的每秒伤害
		var tr := 0.0
		while not bool(main.swords.is_ready()) and tr < 8.0:
			await tree.process_frame
			tr += main.get_process_delta_time()
			_quiet(rd)
			player.mp = player.mp_max()
		await _quiet_wait(main, rd, 0.5)
		var h2 := [float(d.hp)]
		var mq0: float = player.mp
		await _quiet_wait(main, rd, 4.0)
		var qu := _units([d], h2, unit)
		main.swords.toggle_summon()
		out["q_ups"] = snappedf(qu / 4.0, 0.01)
		print("[combat]   飞剑阵 4 秒：%.2f 单位（每秒 %.2f，目标 %.2f），这 4 秒扣灵力 %.0f%%" % [qu, qu / 4.0, CS.q_k(r) / float(Realm.LIST[r]["atk_cd"]),
				100.0 * (mq0 - player.mp) / player.mp_max()])
		air.target = null
		await _quiet_wait(main, rd, 0.2)
		d.queue_free()
		rd._mobs.erase(d)
		player.force_ground()
		await _quiet_wait(main, rd, 0.8)
	# 四、受击：本区一只正常的小怪
	var ri := _region_of(r)
	var pool: Array = Data.REGIONS[ri]["mobs"]
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	var mpos: Vector3 = player.global_position + fwd.normalized() * 2.5
	var mob: Node3D = rd._spawn_mob(int(pool[0]), ri, mpos)
	rd._mobs.append(mob)
	mob.hp_max = DUMMY_HP
	mob.hp = DUMMY_HP
	mob.alert()
	# 2026-11-23：公式那一下要带上这只怪的攻量级（主角的防御系数按它算；和 to_player_from 同一条路）
	var want := CS.to_bar(float(mob.atk), lv, 0.0, float(rd._target_scale(mob, CS.ATK_K_MOB)))
	var drops: Array = []
	var last_hp: float = player.melee.hp
	t = 0.0
	while t < 14.0 and drops.size() < 5:
		await tree.process_frame
		t += main.get_process_delta_time()
		_quiet(rd)
		var h: float = player.melee.hp
		if h < last_hp - 0.05:
			drops.append(last_hp - h)
		last_hp = h
		if h < 40.0:
			player.melee.hp = 100.0
			last_hp = 100.0
	var avg := 0.0
	for v: float in drops:
		avg += v
	avg /= maxf(float(drops.size()), 1.0)
	out["mob_bar"] = snappedf(avg, 0.01)
	out["mob_bar_want"] = snappedf(want, 0.01)
	print("[combat]   %s 贴身打主角：挨了 %d 下，每下平均掉 %.2f 点气血条（公式：普攻 %.2f，远程 ×0.7）" % [Data.MOBS[int(pool[0])]["name"], drops.size(), avg, want])
	if r <= 1:
		# 举着格挡挨打：只擦掉一成五
		player.melee.press_guard()
		var gd: Array = []
		last_hp = player.melee.hp
		t = 0.0
		while t < 12.0 and gd.size() < 3:
			await tree.process_frame
			t += main.get_process_delta_time()
			_quiet(rd)
			player.melee.guard_held = true
			var h: float = player.melee.hp
			if h < last_hp - 0.01:
				gd.append(last_hp - h)
			last_hp = h
		player.melee.release_guard()
		var ga := 0.0
		for v: float in gd:
			ga += v
		ga /= maxf(float(gd.size()), 1.0)
		out["block_bar"] = snappedf(ga, 0.01)
		print("[combat]   举着格挡：挨了 %d 下，每下掉 %.2f（应约 %.2f = 一成五；以前是 0）" % [gd.size(), ga, want * CS.BLOCK_CHIP])
	mob.queue_free()
	rd._mobs.erase(mob)
	player.melee.hp = 100.0
	return out


## `--pace-spawn [--touch] [--spawn-reps=2] [--spawn-only=walk,cross,...]`：刷怪「看得见 / 够得着」实测（2026-11-21，raid_manager 的赶路 / 落地补怪）。
## 八个场景，每个场景都从同一个起点重新开始（清怪、点数 120、导演 / 刷怪点状态归零），老规矩（导演围着人刷）和新规矩（固定刷怪点）各跑一遍，
## 两边用同一个刷怪随机种子；每轮谁先跑轮换着来（去掉先后顺序的影响），跑 reps 轮。1 倍速，帧耗时是真的：
##   walk   草原先站 8 秒，再朝前走 40 秒（每秒 7 米）：身边 40 / 70 米内平均几只、屏幕里一只都看不到的时间占比、最长连续看不到多久；
##   cross  草原站 10 秒（周围铺开）→ 急飞到黄枫谷（离地 30 米、每秒 60 米、约 840 米）→ 落地站 12 秒；
##   round  草原站 10 秒 → 每秒 150 米飞到黄枫谷、悬停 4 秒 → 再飞回草原 → 落地站 12 秒（往返）；
##   hop    草原站 10 秒 → 每秒 40 米飞 200 米 → 落地站 12 秒；
##   stand  草原原地站 50 秒（10 秒以后才算）；
##   refill 草原站 20 秒 → 80 米内的怪全打死 → 再站 12 秒。
## 落地类量：多久屏幕里有第一只（70 米内、在镜头视野里 = 看得见）、多久有一只在 30 米内（够得着）、落地后 3 / 6 / 10 秒身边 40 / 70 米内几只。
## 帧：帧间隔平均 / 95% / 最长，外加不受别的程序抢显卡影响的实际耗时（逻辑 / 物理 / 渲染提交 / 显卡 ms）、平均怪数、绘制调用。
## 打印 `[spawn]` 每一项、`[spawn-sum]` 老 / 新的平均对照，`[spawn-json]` 原始数。主角不出手、气血一直补满（只量刷怪），怪照常会扑过来。
static func _spawn_probe(main: Node, rd: Variant, player: Player, tree: SceneTree) -> void:
	var reps := 2
	var only: Array = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--spawn-reps="):
			reps = int(a.get_slice("=", 1))
		elif a.begins_with("--spawn-only="):
			only = Array(a.get_slice("=", 1).split(","))
	player.set_realm(4, false)
	Profile.data()["realm"] = 4
	Profile.set_cult(14, 0.0)
	rd._sync_cult()
	_cost_begin(main)
	# 刷怪点布局普查：各区域几个点、几只怪、精英点几个（整张图 54 × 54 格算一遍）
	var t_lay := Time.get_ticks_msec()
	var per := [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
	var half: int = rd.camps.N / 2
	for cx in range(-half, half):
		for cz in range(-half, half):
			var c: Variant = rd.camps.camp(cx, cz)
			if c == null:
				continue
			var ri: int = c["ri"]
			per[ri][0] = int(per[ri][0]) + 1
			per[ri][1] = int(per[ri][1]) + (c["defs"] as Array).size()
			if bool((c["elite"] as Array)[0]):
				per[ri][2] = int(per[ri][2]) + 1
	print("[spawn-camps] 布局 %d ms：" % (Time.get_ticks_msec() - t_lay) + "，".join(range(5).map(func(i: int) -> String:
			return "%s %d 个点 %d 只（精英点 %d）" % [Data.REGIONS[i]["name"], per[i][0], per[i][1], per[i][2]])))
	# 站在各区域的陆地上（自检的起点 / 落点）百米内有几个点、几只
	for ri in 5:
		for dep: float in [0.15, 0.3, 0.6]:
			var sp := _spot(ri, dep)
			var nc := 0
			var nm := 0
			var cr := floori(100.0 / float(rd.camps.CELL)) + 1
			var ccx := floori(sp.x / float(rd.camps.CELL))
			var ccz := floori(sp.y / float(rd.camps.CELL))
			for cx in range(ccx - cr, ccx + cr + 1):
				for cz in range(ccz - cr, ccz + cr + 1):
					var c: Variant = rd.camps.camp(rd.camps._wrapi(cx), rd.camps._wrapi(cz))
					if c != null and Data.near2(c["base"], sp).distance_to(sp) < 100.0:
						nc += 1
						nm += (c["defs"] as Array).size()
			print("[spawn-camps] %s 深度 %.2f (%.0f, %.0f) 地面 %.1f：百米内 %d 个点 %d 只" % [Data.REGIONS[ri]["name"], dep, sp.x, sp.y, float(main.level.ground(sp.x, sp.y)), nc, nm])
	var names := ["walk", "cross", "landwalk", "round", "hop", "cruise", "stand", "refill"]
	var rows: Array = []
	for rep_i in reps:
		for si in names.size():
			if not only.is_empty() and not only.has(names[si]):
				continue
			var order := [0, 1] if (rep_i + si) % 2 == 0 else [1, 0]
			for mode: int in order:
				var o := await _sp_scene(main, rd, player, tree, names[si], mode == 1, 9100 + rep_i * 17 + si)
				o["rep"] = rep_i
				rows.append(o)
				_sp_print(o)
	# 老 / 新平均对照
	for nm: String in names:
		for mode in 2:
			var sel := rows.filter(func(r: Dictionary) -> bool: return r["scene"] == nm and r["mode"] == ("新" if mode == 1 else "老"))
			if sel.is_empty():
				continue
			var keys := ["t_vis", "t_far", "near10", "t_eng", "n40_3", "n70_3", "n40_6", "n70_6", "n40_10", "n70_10", "n40", "n70", "novis", "gap", "ms_avg", "ms_p95", "ms_max", "real_avg", "real_p95", "real_max", "logic", "phys", "rcpu", "gpu", "mobs", "dc"]
			var avg := {}
			for k: String in keys:
				var sum := 0.0
				var cnt := 0
				for r: Dictionary in sel:
					if r.has(k):
						var v := float(r[k])
						if (k == "t_vis" or k == "t_eng" or k == "t_far") and v < 0.0:
							v = float(r["secs"]) + 3.0      # 一直没见到：按「站满还没有」再加 3 秒算（偏乐观，另记次数）
						sum += v
						cnt += 1
				if cnt > 0:
					avg[k] = snappedf(sum / float(cnt), 0.01)
			var miss_v := sel.filter(func(r: Dictionary) -> bool: return r.has("t_vis") and float(r["t_vis"]) < 0.0).size()
			var miss_e := sel.filter(func(r: Dictionary) -> bool: return r.has("t_eng") and float(r["t_eng"]) < 0.0).size()
			avg["miss_vis"] = miss_v
			avg["miss_eng"] = miss_e
			avg["n"] = sel.size()
			print("[spawn-sum] %s %s %s" % [nm, "新" if mode == 1 else "老", JSON.stringify(avg)])
	for o: Dictionary in rows:
		print("[spawn-json] " + JSON.stringify(o))


static func _sp_reset(rd: Variant, seed_v: int, assist: bool) -> void:
	rd.camps.reset()
	rd.camps._cache.clear()      # 布局缓存也清掉：每个场景落地都要现算周围的格子，跟真人第一次到一样
	rd.camps.on = assist      # 新 = 固定刷怪点（raid_camps.gd），老 = 改之前的导演
	_clear_mobs(rd)
	rd._rng.seed = seed_v
	rd._credits = 120.0
	rd._wave_t = 2.5
	rd._elite_t = 999.0
	rd._event_t = 999.0
	rd.run_t = 60.0      # 局内 20 分钟的倒计时：每个场景重新算，免得跑满 20 分钟整局结算
	rd.camps._prev_t = rd.run_t
	if is_instance_valid(rd.search):
		for st: Dictionary in rd.search.sites:
			st["guard"] = true      # 搜点守卫每个点只出一次：先跑的那边吃到、后跑的吃不到。自检只量导演刷的怪，全关掉


static func _face(main: Node, dir: Vector3) -> void:
	main.cam.snap(atan2(-dir.x, -dir.z), -0.18, 9.0)


## 这一帧：70 米内在镜头视野里的怪几只、30 米内几只、40 / 70 米内几只
static func _sp_sample(main: Node, rd: Variant, player: Player) -> Array:
	var p := player.global_position
	var cam3: Camera3D = main.cam.cam
	var vis := 0
	var eng := 0
	var n40 := 0
	var n70 := 0
	var far := 0
	var nearest := 999.0
	for m: Variant in rd._mobs:
		if not is_instance_valid(m) or not m.is_alive():
			continue
		var c: Vector3 = (m as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		var d := c.distance_to(p)
		nearest = minf(nearest, d)
		if d < 70.0:
			n70 += 1
			if cam3.is_position_in_frustum(c):
				vis += 1
		if d < 150.0 and cam3.is_position_in_frustum(c):
			far += 1
		if d < 40.0:
			n40 += 1
		if d < 30.0:
			eng += 1
	return [vis, eng, n40, n70, far, nearest]


## 一段计时：帧间隔、实际耗时、怪数、绘制调用
static func _seg() -> Dictionary:
	return {"ms": [], "acc": [0.0, 0.0, 0.0, 0.0, 0], "mobs": 0.0, "dc": 0.0, "real": [], "t0": 0, "ts": 1.0}


static func _seg_add(main: Node, rd: Variant, seg: Dictionary, dt: float) -> void:
	(seg["ms"] as Array).append(dt * 1000.0)
	var now := Time.get_ticks_usec()
	if int(seg["t0"]) > 0:
		(seg["real"] as Array).append(float(now - int(seg["t0"])) / 1000.0)
	seg["t0"] = now
	seg["ts"] = minf(float(seg["ts"]), Engine.time_scale)
	_cost_add(main, seg["acc"])
	seg["mobs"] = float(seg["mobs"]) + float(rd._mobs.size())
	seg["dc"] = float(seg["dc"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)


static func _seg_put(seg: Dictionary, o: Dictionary, pre := "") -> void:
	var st := _ms_stats(seg["ms"])
	var c := _cost_avg(seg["acc"])
	var n := maxf(float((seg["ms"] as Array).size()), 1.0)
	o[pre + "ms_avg"] = st[0]
	o[pre + "ms_p95"] = st[1]
	o[pre + "ms_max"] = st[2]
	o[pre + "logic"] = snappedf(float(c[0]), 0.01)
	o[pre + "phys"] = snappedf(float(c[1]), 0.01)
	o[pre + "rcpu"] = snappedf(float(c[2]), 0.01)
	o[pre + "gpu"] = snappedf(float(c[3]), 0.01)
	o[pre + "mobs"] = snappedf(float(seg["mobs"]) / n, 0.1)
	o[pre + "dc"] = roundi(float(seg["dc"]) / n)
	var rs := _ms_stats(seg["real"])
	o[pre + "real_avg"] = rs[0]
	o[pre + "real_p95"] = rs[1]
	o[pre + "real_max"] = rs[2]
	o[pre + "ts_min"] = snappedf(float(seg["ts"]), 0.01)


static func _ms_stats(ms: Array) -> Array:
	if ms.is_empty():
		return [0.0, 0.0, 0.0]
	var s := ms.duplicate()
	s.sort()
	var avg := 0.0
	for v: float in s:
		avg += v
	avg /= float(s.size())
	return [snappedf(avg, 0.01), snappedf(float(s[int(0.95 * float(s.size() - 1))]), 0.01), snappedf(float(s[s.size() - 1]), 0.1)]


static func _sp_hold(main: Node, player: Player, secs: float, tree: SceneTree) -> void:
	var t := 0.0
	while t < secs:
		await tree.process_frame
		t += main.get_process_delta_time()
		player.velocity = Vector3.ZERO
		if player.melee.hp < 60.0:
			player.melee.hp = 100.0


## 朝 dir 飞 dist 米（离地 alt 米、每秒 v 米）
static func _sp_fly(main: Node, rd: Variant, player: Player, tree: SceneTree, dir: Vector3, v: float, dist: float, alt: float, seg: Dictionary) -> void:
	_face(main, dir)
	# 真的进御剑状态（刷怪点的「急飞不建」只认御剑 FLY / DIVE），落地时 _sp_land 里 force_ground() 再落回地面
	if player.st != Player.St.FLY:
		player.st = Player.St.FLY
		player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var gone := 0.0
	while gone < dist:
		await tree.process_frame
		var dt: float = main.get_process_delta_time()
		_seg_add(main, rd, seg, dt)
		var stp := minf(v * dt, dist - gone)
		gone += stp
		var p: Vector3 = player.global_position + dir * stp
		p.y = float(main.level.ground(p.x, p.z)) + alt
		player.global_position = p
		player.velocity = Vector3.ZERO
		main.cam.yaw = atan2(-dir.x, -dir.z)
		if player.melee.hp < 60.0:
			player.melee.hp = 100.0


## 落地，站 secs 秒
static func _sp_land(main: Node, rd: Variant, player: Player, tree: SceneTree, dir: Vector3, secs: float, o: Dictionary, walk_on := Vector3.ZERO) -> void:
	var p := player.global_position
	p.y = float(main.level.ground(p.x, p.z)) + 0.05
	player.global_position = p
	player.force_ground()
	_face(main, dir)
	var seg := _seg()
	var t := 0.0
	var t_vis := -1.0
	var t_eng := -1.0
	var t_far := -1.0
	var near10 := 999.0
	var at := {3.0: [0, 0], 6.0: [0, 0], 10.0: [0, 0]}
	var vis0 := 0.0
	var frames := 0.0
	while t < secs:
		await tree.process_frame
		var dt: float = main.get_process_delta_time()
		t += dt
		_seg_add(main, rd, seg, dt)
		if walk_on != Vector3.ZERO:
			var q: Vector3 = player.global_position + walk_on * dt
			q.y = float(main.level.ground(q.x, q.z)) + 0.05
			player.global_position = q
			main.cam.yaw = atan2(-walk_on.x, -walk_on.z)
		player.velocity = Vector3.ZERO
		var smp := _sp_sample(main, rd, player)
		frames += dt
		if int(smp[0]) == 0:
			vis0 += dt
		if t_vis < 0.0 and int(smp[0]) > 0:
			t_vis = t
		if t_eng < 0.0 and int(smp[1]) > 0:
			t_eng = t
		if t_far < 0.0 and int(smp[4]) > 0:
			t_far = t
		for k: float in at.keys():
			if t >= k and t - dt < k:
				at[k] = [smp[2], smp[3]]
				if k == 10.0:
					near10 = float(smp[5])
		if player.melee.hp < 60.0:
			player.melee.hp = 100.0
	o["secs"] = secs
	o["t_vis"] = snappedf(t_vis, 0.01)
	o["t_eng"] = snappedf(t_eng, 0.01)
	o["t_far"] = snappedf(t_far, 0.01)
	o["near10"] = snappedf(near10, 0.1)
	o["n40_3"] = at[3.0][0]
	o["n70_3"] = at[3.0][1]
	o["n40_6"] = at[6.0][0]
	o["n70_6"] = at[6.0][1]
	o["n40_10"] = at[10.0][0]
	o["n70_10"] = at[10.0][1]
	o["novis"] = snappedf(vis0 / maxf(frames, 0.01), 0.01)
	_seg_put(seg, o)


## 原地站 / 朝前走 secs 秒，量平均几只、看不到的占比、最长连续看不到多久（skip 秒以前不算）
static func _sp_dwell(main: Node, rd: Variant, player: Player, tree: SceneTree, secs: float, walk: Vector3, skip: float, o: Dictionary) -> void:
	var seg := _seg()
	var t := 0.0
	var s40 := 0.0
	var s70 := 0.0
	var nvis := 0.0
	var n := 0.0
	var gap := 0.0
	var gap_max := 0.0
	var mn := 99
	while t < secs:
		await tree.process_frame
		var dt: float = main.get_process_delta_time()
		t += dt
		if walk != Vector3.ZERO:
			var p: Vector3 = player.global_position + walk * dt
			p.y = float(main.level.ground(p.x, p.z)) + 0.05
			player.global_position = p
			main.cam.yaw = atan2(-walk.x, -walk.z)
		player.velocity = Vector3.ZERO
		if player.melee.hp < 60.0:
			player.melee.hp = 100.0
		if t < skip:
			continue
		_seg_add(main, rd, seg, dt)
		var smp := _sp_sample(main, rd, player)
		s40 += float(smp[2]) * dt
		s70 += float(smp[3]) * dt
		mn = mini(mn, int(smp[2]))
		n += dt
		if int(smp[0]) == 0:
			nvis += dt
			gap += dt
			gap_max = maxf(gap_max, gap)
		else:
			gap = 0.0
	o["n40"] = snappedf(s40 / maxf(n, 0.01), 0.1)
	o["n70"] = snappedf(s70 / maxf(n, 0.01), 0.1)
	o["n40_min"] = mn
	o["novis"] = snappedf(nvis / maxf(n, 0.01), 0.01)
	o["gap"] = snappedf(gap_max, 0.01)
	_seg_put(seg, o)


static func _sp_to(player: Player, p2: Vector2) -> Vector3:
	var d := Vector3(p2.x - player.global_position.x, 0.0, p2.y - player.global_position.z)
	return d


static func _sp_scene(main: Node, rd: Variant, player: Player, tree: SceneTree, nm: String, assist: bool, seed_v: int) -> Dictionary:
	Engine.time_scale = 1.0
	if player.st != Player.St.GROUND:
		player.force_ground()
	var start := _spot(0, 0.3)
	var far := _spot(1, 0.3)
	_sp_reset(rd, seed_v, assist)
	await main._raid_goto(start, 0.0)
	_sp_reset(rd, seed_v, assist)      # 传送 / 预热期间导演可能动过：再归一次零
	var o := {"scene": nm, "mode": "新" if assist else "老", "seed": seed_v}
	var a0: int = rd.camps.built
	var fwd := Vector3(1.0, 0.0, 0.25).normalized()
	_face(main, fwd)
	match nm:
		"walk":
			await _sp_dwell(main, rd, player, tree, 48.0, fwd * 7.0, 8.0, o)
		"stand":
			if OS.get_cmdline_user_args().has("--spawn-diag") and assist:
				for k in 10:
					await _sp_hold(main, player, 5.0, tree)
					var nd := 0
					for id: int in rd.camps._dead.keys():
						nd += (rd.camps._dead[id] as Dictionary).size()
					var riv := 0
					var rnear := 0
					for r: Variant in rd._rivals:
						if is_instance_valid(r):
							riv += 1
							if (r as Node3D).global_position.distance_to(player.global_position) < 120.0:
								rnear += 1
					var near100 := 0
					var cr := 4
					var ccx := floori(player.global_position.x / 32.0)
					var ccz := floori(player.global_position.z / 32.0)
					for cx in range(ccx - cr, ccx + cr + 1):
						for cz in range(ccz - cr, ccz + cr + 1):
							var c: Variant = rd.camps.camp(rd.camps._wrapi(cx), rd.camps._wrapi(cz))
							if c != null and Data.near2(c["base"], Vector2(player.global_position.x, player.global_position.z)).distance_to(Vector2(player.global_position.x, player.global_position.z)) < 100.0:
								near100 += (c["defs"] as Array).size()
					print("[spawn-diag] %d 秒：我的怪 %d 只（建着 %d 个点、队列 %d），百米内点上共 %d 只，记着死了 %d 只，对手修士 %d 个（120 米内 %d），急飞=%s 建过 %d" % [
							(k + 1) * 5, rd._mobs.size(), rd.camps.live_camps(), rd.camps._queue.size(), near100, nd, riv, rnear, str(rd.camps.traveling), rd.camps.built])
			else:
				await _sp_dwell(main, rd, player, tree, 50.0, Vector3.ZERO, 10.0, o)
		"cross":
			await _sp_hold(main, player, 10.0, tree)
			var d := _sp_to(player, far)
			var fs := _seg()
			await _sp_fly(main, rd, player, tree, d.normalized(), 60.0, d.length(), 30.0, fs)
			_seg_put(fs, o, "fly_")
			await _sp_land(main, rd, player, tree, d.normalized(), 12.0, o)
		"landwalk":
			# 急飞跨区后落地接着往前走（每秒 10.2 米 = 大乘的走路 / 各境界的跑步都在这一档）
			await _sp_hold(main, player, 10.0, tree)
			var d := _sp_to(player, far)
			var fs := _seg()
			await _sp_fly(main, rd, player, tree, d.normalized(), 60.0, d.length(), 30.0, fs)
			_seg_put(fs, o, "fly_")
			await _sp_land(main, rd, player, tree, d.normalized(), 12.0, o, d.normalized() * 10.2)
		"cruise":
			# 筑基慢飞：每秒 20 米、离地 12 米飞 400 米（不算赶路，照常刷），落地
			await _sp_hold(main, player, 10.0, tree)
			var cd := Vector3(-0.8, 0.0, 0.6)
			var fs := _seg()
			await _sp_fly(main, rd, player, tree, cd, 20.0, 400.0, 12.0, fs)
			_seg_put(fs, o, "fly_")
			await _sp_land(main, rd, player, tree, cd, 12.0, o)
		"round":
			await _sp_hold(main, player, 10.0, tree)
			var d := _sp_to(player, far)
			var fs := _seg()
			await _sp_fly(main, rd, player, tree, d.normalized(), 150.0, d.length(), 40.0, fs)
			# 悬停 4 秒（不落地）
			var t := 0.0
			while t < 4.0:
				await tree.process_frame
				var dt: float = main.get_process_delta_time()
				t += dt
				_seg_add(main, rd, fs, dt)
				player.velocity = Vector3.ZERO
			var b := _sp_to(player, start)
			await _sp_fly(main, rd, player, tree, b.normalized(), 150.0, b.length(), 40.0, fs)
			_seg_put(fs, o, "fly_")
			await _sp_land(main, rd, player, tree, b.normalized(), 12.0, o)
		"hop":
			await _sp_hold(main, player, 10.0, tree)
			var hop := Vector3(0.6, 0.0, -0.8)
			var fs := _seg()
			await _sp_fly(main, rd, player, tree, hop, 40.0, 200.0, 15.0, fs)
			_seg_put(fs, o, "fly_")
			await _sp_land(main, rd, player, tree, hop, 12.0, o)
		"refill":
			await _sp_hold(main, player, 20.0, tree)
			var killed := 0
			for m: Variant in rd._mobs.duplicate():
				if is_instance_valid(m) and m.is_alive() and (m as Node3D).global_position.distance_to(player.global_position) < 80.0:
					m.hp = 0.5
					m.receive_hit(player, {"dmg": 8.0, "dir": Vector3.FORWARD, "heavy": true, "kb": 0.5})
					killed += 1
			o["killed"] = killed
			var left := 0
			for m: Variant in rd._mobs:
				if is_instance_valid(m) and m.is_alive() and (m as Node3D).global_position.distance_to(player.global_position) < 80.0:
					left += 1
			o["alive_after"] = left
			await _sp_land(main, rd, player, tree, fwd, 12.0, o)
	o["built"] = int(rd.camps.built) - a0
	return o


static func _sp_print(o: Dictionary) -> void:
	if not o.has("real_avg"):
		return      # --spawn-diag 的长停只打诊断行
	var tail := "｜真实帧间隔 平均 %.2f / 95%% %.2f / 最长 %.1f ms（流速最低 %.2f）｜游戏帧 平均 %.2f / 95%% %.2f / 最长 %.1f ms，实际 逻辑 %.2f + 物理 %.2f + 渲染 %.2f ms、显卡 %.2f ms，平均 %.1f 只怪、%d 次绘制" % [
			float(o["real_avg"]), float(o["real_p95"]), float(o["real_max"]), float(o["ts_min"]), float(o["ms_avg"]), float(o["ms_p95"]), float(o["ms_max"]), float(o["logic"]), float(o["phys"]), float(o["rcpu"]), float(o["gpu"]), float(o["mobs"]), int(o["dc"])]
	if o.has("t_vis"):
		print("[spawn] %s %s 第%d轮：第一只看得见 %.2f 秒（150 米内 %.2f 秒）、够得着 %.2f 秒、10 秒时最近一只 %.0f 米；40 / 70 米内 3 秒 %d / %d、6 秒 %d / %d、10 秒 %d / %d；看不到 %d%%%s%s" % [
				o["mode"], o["scene"], int(o["rep"]) + 1, float(o["t_vis"]), float(o["t_far"]), float(o["t_eng"]), float(o["near10"]), int(o["n40_3"]), int(o["n70_3"]), int(o["n40_6"]), int(o["n70_6"]),
				int(o["n40_10"]), int(o["n70_10"]), roundi(100.0 * float(o["novis"])), tail,
				("｜飞行段 帧平均 %.2f / 95%% %.2f ms、逻辑 %.2f ms" % [float(o["fly_ms_avg"]), float(o["fly_ms_p95"]), float(o["fly_logic"])]) if o.has("fly_ms_avg") else ""])
	else:
		print("[spawn] %s %s 第%d轮：40 / 70 米内平均 %.1f / %.1f 只（40 米内最少 %d），看不到 %d%%、最长连续看不到 %.1f 秒%s" % [
				o["mode"], o["scene"], int(o["rep"]) + 1, float(o["n40"]), float(o["n70"]), int(o["n40_min"]), roundi(100.0 * float(o["novis"])), float(o["gap"]), tail])

## 等 secs 秒，期间一直压着导演（别在间隙里刷怪）
static func _quiet_wait(main: Node, rd: Variant, secs: float) -> void:
	var t := 0.0
	while t < secs:
		await main.get_tree().process_frame
		t += main.get_process_delta_time()
		_quiet(rd)


## 自检里别让导演 / 游荡首领 / 精英计时插进来
static func _quiet(rd: Variant) -> void:
	rd._credits = 0.0
	rd._wave_t = 999.0
	rd._elite_t = 999.0
	rd._event_t = 999.0


static func _clear_mobs(rd: Variant) -> void:
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()


## 主角周围摆一圈 n 只草原小怪（前 elite_n 只是精英）
static func _ring_mobs(rd: Variant, player: Player, n: int, elite_n: int, r: float) -> Array:
	var out: Array = []
	var pool: Array = Data.REGIONS[0]["mobs"]
	for i in n:
		var a := TAU * float(i) / float(maxi(n, 1)) + 0.4
		var q: Vector3 = player.global_position + Vector3(cos(a), 0.0, sin(a)) * r
		q.y = float(rd._ground(q.x, q.z))
		var m: Node3D = rd._spawn_mob(int(pool[i % pool.size()]), 0, q, i < elite_n)
		rd._mobs.append(m)
		out.append(m)
	return out


static func _kill(list: Array, player: Player) -> void:
	for m: Variant in list:
		if is_instance_valid(m) and m.is_alive():
			m.hp = 0.5      # 先压到残血再补一下：照常走受击 → 倒下，截图里也不会飘一串百万伤害
			m.receive_hit(player, {"dmg": 8.0, "dir": Vector3.FORWARD, "heavy": true, "kb": 0.5})


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[int(float(s.size()) / 2.0)])


## realm_o / lv_o >= 0（--pace-byrealm）：主角设成这个境界、这一级，只打 Prog.mob_tag ≤ 自己境界、离起点 200 米内的怪，[pace-json] 带 "by": "realm"
static func _one(main: Node, rd: Variant, player: Player, level: Variant, tree: SceneTree, ri: int, depth: float, minutes: float, speed: float, hit_k: float,
		realm_o := -1, lv_o := -1) -> Dictionary:
	Engine.time_scale = 1.0
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()
	for pk: Variant in rd._pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	rd._pickups.clear()
	var by_realm := realm_o >= 0
	var realm: int = realm_o if by_realm else int(ENTRY_REALM[ri])
	player.set_realm(realm, false)
	Profile.data()["realm"] = realm
	Profile.set_cult(lv_o if by_realm and lv_o > 0 else realm * Prog.LV_PER_REALM + 2, 0.0)
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
	print("[pace] —— %s（%s %s Lv.%d）深度 %.3f：脚下怪 Lv.%d（%s档），天道压制 %d 档 ——" % [Data.REGIONS[ri]["name"], "按境界" if by_realm else "入门", Realm.LIST[realm]["name"],
			int(rd.lv), float(rd.here_depth), int(rd.here_lv), Realm.LIST[Prog.mob_tag(ri, int(rd.here_lv))]["name"], int(rd.sup_gap)])
	Engine.time_scale = speed
	var t0: float = rd.run_t
	var seen := {}
	var tally := {"n": 0, "pill_n": 0, "pill_ok": 0, "pill_exp": 0.0, "pill_ok_exp": 0.0, "heal": 0, "key": 0, "frag": 0, "coin": 0.0, "gear": 0, "items": 0}
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
	var face_on := OS.get_cmdline_user_args().has("--pace-face")
	var home_r := 0.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pace-home="):
			home_r = float(a.get_slice("=", 1))
	if by_realm and home_r <= 0.0:
		home_r = 200.0
	var tag_skip := 0
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
			if home_r > 0.0 and Vector2(m.global_position.x - home.x, m.global_position.z - home.y).length() > home_r:
				continue      # --pace-home=R：只打离起点 R 米内的（老 / 新对照时别让假主角越打越往深处跑，等级漂了杀怪就慢）
			if by_realm and Prog.mob_tag(int(m.region), int(m.lv)) > realm:
				tag_skip += 1
				continue      # 2026-11-23：高一档的怪（一下掉一大截、几十下打不死）真人不会去碰
			var score := dd + (200.0 if bool(m.boss) else 0.0)
			if score < bd:
				bd = score
				best = m
		# 谁死了：每只怪第一次见到时挂上 died 信号记种类（rd.kills 只给总数；死了的怪很快就从 _mobs 里拿掉，轮询看不到）
		for m: Variant in rd._mobs:
			if is_instance_valid(m) and not hooked.has(m.get_instance_id()):
				hooked[m.get_instance_id()] = true
				if by_realm and Prog.mob_tag(int(m.region), int(m.lv)) > realm:
					m.atk_out = func(_d: float) -> float: return 0.0      # 假主角不打越档的怪，也别让它们一下把假主角秒了（局一结束后面的就量不成）
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
		if face_on:
			# --pace-face：镜头跟着走的方向转（真人看着前进方向；老的假主角镜头一直朝北，朝镜头前方刷的怪对它就是随机方向）
			var mv := Vector3(p.x - player.global_position.x, 0.0, p.z - player.global_position.z)
			if mv.length() > 0.001:
				main.cam.yaw = lerp_angle(float(main.cam.yaw), atan2(-mv.x, -mv.z), 1.0 - exp(-4.0 * dt / maxf(Engine.time_scale, 0.05)))
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
						# 2026-11-23：丹按境界锁，药力一律 Items.pill_exp_now 现算；另记「自己现在能服的」那部分
						var pe := Items.pill_exp_now(it, realm)
						tally["pill_n"] = int(tally["pill_n"]) + 1
						tally["pill_exp"] = float(tally["pill_exp"]) + pe
						if Prog.pill_use_err(it, realm) == "":
							tally["pill_ok"] = int(tally["pill_ok"]) + 1
							tally["pill_ok_exp"] = float(tally["pill_ok_exp"]) + pe
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
			"key": tally["key"], "frag": tally["frag"], "heal": tally["heal"], "gear": tally["gear"],
			"pill_ok_pm": snappedf(float(tally["pill_ok"]) / mins, 0.01), "pill_ok_exp_pm": snappedf(float(tally["pill_ok_exp"]) / mins, 0.1)}
	if by_realm:
		o["by"] = "realm"
		o["kill_base"] = Prog.KILL_BASE      # 量的时候的心得基数（life_sim 换算用）
		o["home_r"] = home_r
		o["tag_skip_pm"] = snappedf(float(tag_skip) / maxf(float(samples), 1.0), 0.01)      # 平均每帧跳过几只高一档的怪（看身边混进来多少）
	print("[pace] %s 小结：%.1f 分钟杀 %d 只（每分钟 %.1f；普通 %d / 精英 %d / 首领 %d），平均 %.1f 下打死一只；场上 %.1f 只、40 米内 %.1f 只、身边没怪 %d%%；" % [
			Data.REGIONS[ri]["name"], mins, kills, float(kills) / mins, int(kinds["mob"]), int(kinds["elite"]), int(kinds["boss"]), float(o["hits_per_kill"]),
			float(o["alive"]), float(o["near"]), int(100.0 * float(o["idle"]))] +
			"每分钟心得 %.0f（本局上限 %.0f）、修为丹 %.2f 颗（%.0f 修为）、其余掉落折 %.0f 灵石；破境丹 %d、残片 %d" % [float(o["insight_pm"]), float(o["insight_cap"]),
			float(o["pill_pm"]), float(o["pill_exp_pm"]), float(o["coin_pm"]), int(tally["key"]), int(tally["frag"])])
	return o
