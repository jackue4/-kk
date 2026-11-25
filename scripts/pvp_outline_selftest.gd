extends RefCounted
## 2026-11-21 PvP 锁定描边的自检（只读测试，不改玩法）：`-- --duel-shot --spark --spark-feat --pvp-outline [--touch]`
## （借 fight_feat_selftest.gd 的入口分流过来；网页版也能跑：探针页 args 照抄，网页上不存图，打印 [pvpline] shot 后停 0.7 秒等外面截图）。
## 单机里造两个别队玩家的木偶（remote_player.gd，和联机时 net.gd 建的一样，只是没有网络）、一个队友木偶，陪练（AI）留在旁边，逐项打印 [pvpline] 通过 / 不通过：
##   1 改之前（RemotePlayer.outline_off）/ 现在：同一机位锁定敌甲，截图对照
##   2 镜头锁定（空战交战）：只描敌甲；敌乙、队友、自己、陪练（AI）都不描；线色是红的
##   3 跟着动作贴合：敌甲换几套出招动作、边飞边打，描边一直挂在他身上（同一份网格外扩），截两张
##   4 切换锁定：交战目标换成敌乙 → 敌乙描、敌甲淡出清掉
##   5 准星自动锁（不在交战）：谁近锁谁；把敌甲挪近 → 换到敌甲
##   6 解锁：两人都拉到准星锁定距离外 → 都不描
##   7 倒下：锁着敌甲时他血量归零 → 当帧清掉，锁到敌乙
##   8 换成队友：锁着敌乙时他变成队友 → 清掉；硬把镜头锁到队友身上也不描
##   9 锁的是 AI 陪练：玩家木偶都不描
##  10 觉醒描边 + 锁定：红色优先；解锁后回到觉醒色；觉醒结束后清掉
##  11 离场：锁着的敌甲被释放（掉线 / 退出）→ 不报错、别人身上不残留
##  12 地面近战（炼气）：交战目标是敌乙 → 描；收剑不交战 → 清
## 故意不写 class_name：用 load 引用。

const Remote := preload("res://scripts/remote_player.gd")
const AirFoe := preload("res://scripts/air_foe.gd")
const Combat := preload("res://scripts/combat.gd")
const P0 := Vector3(0.0, 14.0, 0.0)

static var _fails := 0
static var _drivers := {}     # 木偶 -> {pos, st, pose, n, hp}
static var _t := 0.0


static func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("[pvpline] %s %s｜%s" % ["通过" if ok else "不通过", name, detail])


static func _shot(main: Node, tag: String) -> void:
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	if OS.has_feature("web"):
		print("[pvpline] shot ", tag)
		await main._wait(0.7)
		return
	if DisplayServer.get_name() == "headless":
		return
	await main._shot("pvpline_" + tag)


## 某个人身上现在的描边：「红」/「无」/ 其他颜色
static func _line_of(n: Node) -> String:
	var hero: Node = n.get("hero") if n != null and is_instance_valid(n) else null
	if hero == null or not hero.has_method("outline_state"):
		return "无"
	var s: Array = hero.call("outline_state")
	if not bool(s[0]):
		return "无"
	var c: Color = s[1]
	return "红" if c.r > 0.9 and c.g < 0.2 and c.b < 0.2 else "其他(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]


static func _who(m: Dictionary) -> String:
	var parts: Array = []
	for k: String in m.keys():
		parts.append("%s=%s" % [k, _line_of(m[k])])
	return " ".join(parts)


static func _make(main: Node, nm: String, mate: bool, pos: Vector3) -> Node3D:
	var r: Node3D = Remote.new()
	r.set("player", main.player)
	r.set("peer_id", 900 + _drivers.size())
	main.add_child(r)
	r.call("set_info", {"name": nm}, mate)
	_drivers[r] = {"pos": pos, "st": 1, "pose": "f_idle", "n": 0, "hp": 100.0, "realm": 4}
	r.call("push_state", pos, 0.0, 1, 4, 100.0, "f_idle", 0, 30, Vector3.ZERO, 0)
	return r


## 每帧给木偶推一次状态（联机里是对方每秒发 15 次；这里每帧推，省得三秒没消息被藏起来）
static func _drive(main: Node) -> void:
	var tree: SceneTree = main.get_tree()
	while _drivers.size() > 0:
		await tree.process_frame
		_t += main.get_process_delta_time()
		for r: Variant in _drivers.keys():
			if not is_instance_valid(r):
				_drivers.erase(r)
				continue
			var d: Dictionary = _drivers[r]
			var face := atan2(-(P0.x - (d["pos"] as Vector3).x), -(P0.z - (d["pos"] as Vector3).z))
			(r as Node3D).call("push_state", d["pos"], face, int(d["st"]), int(d["realm"]), float(d["hp"]), str(d["pose"]), int(d["n"]), 30, Vector3.ZERO, 0)


static func _pose(r: Node3D, pose: String) -> void:
	var d: Dictionary = _drivers[r]
	d["pose"] = pose
	d["n"] = int(d["n"]) + 1


static func _move(r: Node3D, pos: Vector3) -> void:
	(_drivers[r] as Dictionary)["pos"] = pos


static func _engage(main: Node, t: Node3D) -> void:
	var p: Player = main.player
	p.air.target = t
	p.air.set("_engage", 99.0)


static func _disengage(main: Node) -> void:
	var p: Player = main.player
	p.air.set("_engage", 0.0)
	p.air.target = null


static func run(main: Node) -> void:
	_fails = 0
	_drivers.clear()
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var tree: SceneTree = main.get_tree()
	var touch := OS.get_cmdline_user_args().has("--touch")
	print("[pvpline] 自检开始（%s，%s）" % ["触屏 / 手机画质档" if touch else "键鼠 / 桌面", RenderingServer.get_current_rendering_method()])
	var foe: AirFoe = main.foe
	var rival: AirFoe = main.rival
	foe.ai_enabled = false
	foe.demo_reset(P0 + Vector3(120.0, 0.0, -120.0))
	main.sandbag.ai_enabled = false
	main.sandbag.demo_reset(P0 + Vector3(-120.0, 0.0, -120.0))
	rival.ai_enabled = false
	rival.demo_reset(P0 + Vector3(-60.0, 0.0, -10.0))      # AI 陪练：先放远处，第 9 项再拉近
	# 主角：化神，空中
	player.force_ground()
	player.global_position = Vector3(0.0, 0.1, 0.0)
	player.set_realm(4, false)
	await main._wait(0.3)
	player.take_air()
	await main._wait(0.6)
	player.global_position = P0
	player.velocity = Vector3.ZERO
	player.melee.hp = 100.0
	var e1 := _make(main, "敌甲", false, P0 + Vector3(0.6, 0.3, -5.0))
	var e2 := _make(main, "敌乙", false, P0 + Vector3(4.5, -0.4, -10.0))
	var m1 := _make(main, "队友丙", true, P0 + Vector3(-3.2, 0.0, -6.5))
	_drive(main)
	await main._wait(0.5)
	cam.lock_turn = false
	cam.snap(0.0, -0.12, 7.0)
	var who := {"敌甲": e1, "敌乙": e2, "队友": m1, "自己": player, "陪练AI": rival}

	# 1 改之前 / 现在
	Remote.outline_off = true
	_engage(main, e1)
	await main._wait(0.5)
	cam.snap(0.0, -0.12, 7.0)
	await main._wait(0.15)
	_check("改之前（对照）：锁定敌甲但不描", _line_of(e1) == "无" and cam.lock == e1, "镜头锁定=%s %s" % [_name(cam.lock, who), _who(who)])
	await _shot(main, "01_before_locked")
	Remote.outline_off = false
	await main._wait(0.25)
	cam.snap(0.0, -0.12, 7.0)
	await main._wait(0.15)
	# 2 镜头锁定
	_check("镜头锁定敌甲：只有敌甲是红色描边", _line_of(e1) == "红" and _line_of(e2) == "无" and _line_of(m1) == "无" and _line_of(player) == "无"
			and _line_of(rival) == "无", "镜头锁定=%s %s" % [_name(cam.lock, who), _who(who)])
	await _shot(main, "02_after_locked")
	# 3 动作贴合：换几套出招动作、边飞边打
	var stay := true
	for pose: String in ["f_sm", "f_up", "f_rush", "f_guard"]:
		_pose(e1, pose)
		_move(e1, P0 + Vector3(0.6 + randf_range(-0.8, 0.8), 0.3 + randf_range(-0.4, 0.6), -5.0))
		await main._wait(0.18)
		stay = stay and _line_of(e1) == "红"
		if pose == "f_sm" or pose == "f_rush":
			await _shot(main, "03_pose_" + pose)
	_check("跟着动作贴合：换四套动作、边飞边打，描边一直在敌甲身上", stay, "最后 %s" % _who(who))
	_pose(e1, "f_idle")
	# 4 切换锁定
	_engage(main, e2)
	await main._wait(0.05)
	var mid_e1 := float(e1.call("lock_outline_k"))
	await main._wait(0.25)
	_check("切换锁定到敌乙：敌乙描、敌甲淡出清掉", cam.lock == e2 and _line_of(e2) == "红" and _line_of(e1) == "无",
			"镜头锁定=%s，切换 0.05 秒时敌甲还剩 %.2f；%s" % [_name(cam.lock, who), mid_e1, _who(who)])
	cam.snap(0.25, -0.12, 8.0)
	await _shot(main, "04_switch_to_e2")
	# 5 准星自动锁（不在交战）：先让敌乙近、敌甲远，再对调
	_disengage(main)
	_move(e1, P0 + Vector3(2.0, 0.2, -14.0))
	_move(e2, P0 + Vector3(-1.0, -0.2, -3.5))
	await main._wait(0.4)
	var auto1 := Remote.current_lock(player)
	var l5a := "敌甲=%s 敌乙=%s" % [_line_of(e1), _line_of(e2)]
	var ok5a := cam.lock == null and auto1 == e2 and _line_of(e2) == "红" and _line_of(e1) == "无"
	_move(e1, P0 + Vector3(0.5, 0.2, -3.0))
	_move(e2, P0 + Vector3(5.0, -0.4, -16.0))
	await main._wait(0.35)
	var auto2 := Remote.current_lock(player)
	_check("准星自动锁：不在交战时描准星锁到的那个（近的），两人对调位置就跟着换", ok5a and cam.lock == null and auto2 == e1 and _line_of(e1) == "红" and _line_of(e2) == "无",
			"敌乙近时锁=%s（%s）→ 对调后锁=%s；%s" % [_name(auto1, who), l5a, _name(auto2, who), _who(who)])
	# 6 解锁
	_move(e1, P0 + Vector3(-20.0, 0.0, -70.0))
	_move(e2, P0 + Vector3(25.0, 0.0, -75.0))
	_move(m1, P0 + Vector3(-3.2, 0.0, -6.5))
	await main._wait(0.4)
	var lk6 := Remote.current_lock(player)
	_check("解锁（两人都在准星锁定距离 45 米外）：玩家木偶都不描", lk6 != e1 and lk6 != e2 and _line_of(e1) == "无" and _line_of(e2) == "无" and _line_of(m1) == "无",
			"锁=%s（不是玩家）；%s" % [_name(lk6, who), _who(who)])
	cam.snap(0.0, -0.12, 7.0)
	await _shot(main, "05_unlocked")
	# 7 倒下
	_move(e1, P0 + Vector3(0.6, 0.3, -5.0))
	_move(e2, P0 + Vector3(4.5, -0.4, -10.0))
	await main._wait(0.3)
	_engage(main, e1)
	await main._wait(0.3)
	var before := _line_of(e1)
	(_drivers[e1] as Dictionary)["hp"] = 0.0
	await tree.process_frame
	await tree.process_frame
	var just := _line_of(e1)
	await main._wait(0.35)
	_check("锁着的敌甲倒下：当帧清掉，锁落到敌乙", before == "红" and just == "无" and _line_of(e1) == "无" and _line_of(e2) == "红",
			"倒下前 %s → 两帧后 %s；之后锁=%s %s" % [before, just, _name(Remote.current_lock(player), who), _who(who)])
	await _shot(main, "06_e1_down")
	(_drivers[e1] as Dictionary)["hp"] = 100.0
	# 8 换成队友 / 硬锁队友
	_engage(main, e2)
	await main._wait(0.3)
	var b8 := _line_of(e2)
	e2.call("set_info", {"name": "敌乙"}, true)
	await tree.process_frame
	await tree.process_frame
	var a8 := _line_of(e2)
	e2.call("set_info", {"name": "敌乙"}, false)
	_disengage(main)
	cam.lock = m1          # 硬塞（正常索敌锁不到队友）
	await main._wait(0.3)
	_check("锁着的敌乙变成队友：当帧清掉；镜头硬锁到队友身上也不描", b8 == "红" and a8 == "无" and _line_of(m1) == "无",
			"变队友前 %s → 两帧后 %s；硬锁队友时 %s" % [b8, a8, _who(who)])
	cam.lock = null
	# 9 锁 AI 陪练
	rival.demo_reset(P0 + Vector3(-1.5, 0.2, -3.5))
	_engage(main, rival)
	await main._wait(0.4)
	_check("锁的是 AI 陪练：玩家木偶都不描、陪练也不描", cam.lock == rival and _line_of(e1) == "无" and _line_of(e2) == "无" and _line_of(rival) == "无",
			"镜头锁定=%s %s" % [_name(cam.lock, who), _who(who)])
	_disengage(main)
	rival.demo_reset(P0 + Vector3(-60.0, 0.0, -10.0))
	# 10 觉醒 + 锁定
	_engage(main, e1)
	e1.call("awaken_fx", 1.6)
	await main._wait(0.5)
	var c10a := _line_of(e1)
	await _shot(main, "07_awaken_and_locked")
	_engage(main, e2)
	await main._wait(0.35)
	var c10b := _line_of(e1)
	await main._wait(2.0)
	var c10c := _line_of(e1)
	_check("觉醒 + 锁定：红色优先；解锁后回到觉醒色；觉醒结束后清掉", c10a == "红" and c10b.begins_with("其他") and c10c == "无",
			"锁着 %s → 换锁后 %s → 觉醒完 %s" % [c10a, c10b, c10c])
	# 11 离场
	_engage(main, e1)
	await main._wait(0.3)
	var b11 := _line_of(e1)
	_drivers.erase(e1)
	e1.queue_free()
	await tree.process_frame
	await tree.process_frame
	await main._wait(0.3)
	var lk := Remote.current_lock(player)
	_check("锁着的敌甲离场：不报错，别人身上不残留", b11 == "红" and not is_instance_valid(e1) and _line_of(m1) == "无" and (_line_of(e2) == "无" or lk == e2),
			"离场前 %s；之后锁=%s 敌乙=%s 队友=%s" % [b11, _name(lk, who), _line_of(e2), _line_of(m1)])
	_disengage(main)
	await main._wait(0.3)
	# 12 地面近战（炼气）
	player.force_ground()
	player.set_realm(0, false)
	player.global_position = Vector3(0.0, 0.1, 6.0)
	_drivers[e2]["st"] = 0
	_drivers[e2]["realm"] = 0
	_move(e2, Vector3(0.5, 0.0, 3.0))
	_move(m1, Vector3(-2.5, 0.0, 3.5))
	(_drivers[m1] as Dictionary)["st"] = 0
	await main._wait(0.5)
	player.melee.target = e2
	player.melee.state = player.melee.M.READY
	await main._wait(0.3)
	var g1 := _line_of(e2)
	cam.snap(0.3, -0.25, 6.0)
	await main._wait(0.1)
	await _shot(main, "08_ground_locked")
	var gs := "近战状态 %d 目标=%s 镜头焦点=%s" % [int(player.melee.state), _name(player.melee.target, who), _name(cam.focus, who)]
	# 收剑、敌乙退到二十米外（不交战了）
	_move(e2, Vector3(0.5, 0.0, -16.0))
	player.melee.target = null
	player.melee.state = player.melee.M.SHEATHED
	await main._wait(0.4)
	var g2 := _line_of(e2)
	_check("地面近战（炼气）：交战目标描红、收剑不交战就清掉；队友不描", g1 == "红" and g2 == "无" and _line_of(m1) == "无",
			"交战中 %s（%s）→ 收剑后 %s（近战状态 %d 焦点=%s 锁=%s）；队友 %s" % [g1, gs, g2, int(player.melee.state), _name(cam.focus, who),
			_name(Remote.current_lock(player), who), _line_of(m1)])
	_drivers.clear()
	for r: Node in [e2, m1]:
		if is_instance_valid(r):
			r.queue_free()
	print("[pvpline] 小结：不通过 %d 项" % _fails)
	print("[pvpline] 完")


static func _name(n: Variant, who: Dictionary) -> String:
	if n == null or not is_instance_valid(n):
		return "无"
	for k: String in who.keys():
		if who[k] == n:
			return k
	return str((n as Node).name)

