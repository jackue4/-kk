extends RefCounted
## 局域网在场（lan_presence.gd）的双开自检（2026-11-23）。同一台电脑开两个窗口：
##   `-- --hub-shot --lan-test=a` 和 `-- --hub-shot --lan-test=b`（hub_hall.gd 的 selftest 开头分流过来）
## 两边都以「第一次看见对方」为零点对表，按同一条时间线走：
##   主城互见（站定、名牌）→ a 挪位置 / 走一段，b 那边的木偶跟不跟 → a 进灵田（b 这边应消失）→ b 也进灵田（又互见）→ 都回主城
##   → 两人上同一座擂台配上对决（对手只画一个：擂台那条连接的木偶，在场的那个不画）→ a 打倒 b，收场后又互见
##   → a 点「开始匹配」进木兰草原开房；b 在入境页看到「局域网道友」那一行，再匹配进同一间房，两边在副本里互见
##   → b 退出，a 这边应看到人数归零
## 打印以 [lan] 开头；截图存 _shots/lan/*.jpg。故意不写 class_name。

const Arena := preload("res://scripts/hub_arena.gd")
const CS := preload("res://scripts/combat_stats.gd")

static var _t0 := 0


static func _say(role: String, s: String) -> void:
	print("[lan] %s：%s" % [role, s])


static func _wait(hub, sec: float) -> void:
	await hub.get_tree().create_timer(sec, true, false, true).timeout


## 等到零点之后第 sec 秒
static func _at(hub, sec: float) -> void:
	while Time.get_ticks_msec() - _t0 < int(sec * 1000.0):
		await hub.get_tree().process_frame


static func _until(hub, cond: Callable, sec: float) -> float:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(sec * 1000.0):
		if bool(cond.call()):
			return float(Time.get_ticks_msec() - s) * 0.001
		await hub.get_tree().process_frame
	return float(Time.get_ticks_msec() - s) * 0.001 if bool(cond.call()) else -1.0


static func _shot(hub, tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = hub.get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(1100, int(1100.0 * float(img.get_height()) / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/lan"))
	img.save_jpg(ProjectSettings.globalize_path("res://_shots/lan/%s.jpg" % tag), 0.86)


static func _put(hub, pos: Vector3) -> void:
	var p: Player = hub.player
	p.force_ground()
	p.global_position = pos
	p.velocity = Vector3.ZERO


static func _other(pres) -> Dictionary:
	for tk: int in pres.peers:
		return pres.peers[tk]
	return {}


static func run(hub, role: String) -> void:
	var p: Player = hub.player
	var pres = hub.presence
	var duel = hub.duel
	var main: Node = hub.main
	var is_a := role == "a"
	duel.verbose = true
	duel.queue_t = 30.0
	# 自检窗口不抓鼠标：这台电脑上要是有人正在玩，他的鼠标移动会漏进隐藏的自检窗口、把镜头转走（走位就歪了）
	hub.cam.set("capture_mouse", false)
	hub.get_tree().process_frame.connect(func() -> void:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	_say(role, "在场广播 开着=%s 端口 %d 令牌 %d 名字 %s" % [pres.enabled, int(pres.get("_port")), pres.token, pres.my_name()])
	var t_seen := await _until(hub, func() -> bool: return pres.online() >= 1, 60.0)
	_t0 = Time.get_ticks_msec()
	var o := _other(pres)
	var nm := str(o.get("name", "?"))
	_say(role, "%.1f 秒后看见对方：%s（%s Lv.%d，在%s）；已发 %d 个包、收 %d 个" % [t_seen, nm, str(Realm.LIST[int(o.get("realm", 0))]["name"]),
			int(o.get("lv", 0)), str(pres.WHERE_NAMES[int(o.get("where", 0))]), pres.sent, pres.got])
	if t_seen < 0.0:
		return
	# 1) 主城互见：两人相隔 6 米站定
	var mine := Vector3(3.0 if is_a else -3.0, 0.1, 62.0)
	var theirs := Vector3(-3.0 if is_a else 3.0, 0.1, 62.0)
	await _at(hub, 2.0)
	_put(hub, mine)
	hub.cam.snap(PI * 0.5 if is_a else -PI * 0.5, -0.12, 8.0)
	await _at(hub, 4.0)
	var pu: Node3D = pres.puppet_of(nm)
	_say(role, "主城互见：对方的木偶 有=%s 看得见=%s 离他该在的位置 %.2f 米；名牌「%s」；左上角「%s」（显示=%s）" % [pu != null, pres.shown(nm),
			pu.global_position.distance_to(Vector3(theirs.x, 0.0, theirs.z)) if pu != null else -1.0,
			str((pu.get("_tag") as Label3D).text) if pu != null else "", str(pres.get("_lab").text), bool(pres.get("_lab").visible)])
	await _shot(hub, "%s_1_hub" % role)
	# 2) a 挪到别处、再往北走两秒；b 看木偶跟不跟
	var p1 := Vector3(12.0, 0.1, 50.0)
	if is_a:
		await _at(hub, 5.0)
		_put(hub, p1)
		hub.cam.snap(0.0, -0.15, 8.0)
		await _at(hub, 8.0)
		Input.action_press("move_forward")
		await _at(hub, 10.0)
		Input.action_release("move_forward")
		await _at(hub, 11.0)
		_say(role, "我挪到 %s 再往北走了两秒，现在在 %s" % [str(p1.round()), str(p.global_position.snapped(Vector3.ONE * 0.1))])
	else:
		await _at(hub, 7.0)
		pu = pres.puppet_of(nm)
		_say(role, "a 挪了位置：木偶离 %s 有 %.2f 米" % [str(p1.round()), pu.global_position.distance_to(Vector3(p1.x, 0.0, p1.z)) if pu != null else -1.0])
		await _at(hub, 11.0)
		pu = pres.puppet_of(nm)
		_say(role, "a 往北走了两秒：木偶现在在 %s（和 a 自己打印的位置对一下）" % (str(pu.global_position.snapped(Vector3.ONE * 0.1)) if pu != null else "-"))
	# 3) 灵田：a 先进（b 这边应消失），b 再进（又互见），再都回主城
	if is_a:
		await _at(hub, 12.0)
		hub.call("_through", hub.get("_portal_town"), "farm")
	await _at(hub, 14.5)
	o = _other(pres)
	_say(role, "a 进了灵田：我在%s，对方记为在%s；对方的木偶看得见=%s（b 这边应为 false）；入境页那一行：%s" % [str(pres.WHERE_NAMES[pres.my_where()]),
			str(pres.WHERE_NAMES[int(o.get("where", 0))]), pres.shown(nm), pres.roster_text().replace("\n", " / ")])
	if not is_a:
		hub.call("_through", hub.get("_portal_town"), "farm")
	await _at(hub, 16.5 if not is_a else 17.0)
	_say(role, "两人都在灵田：对方的木偶看得见=%s（应为 true）" % pres.shown(nm))
	await _shot(hub, "%s_2_farm" % role)
	await _at(hub, 17.6)
	hub.call("_through", hub.get("_portal_farm"), "town")
	await _at(hub, 19.5)
	_say(role, "都回到主城：对方的木偶看得见=%s（应为 true）" % pres.shown(nm))
	# 4) 擂台：两人上同一座，配上对决
	# a 先上台（b 这时还在台下看：a 的名牌应带「寻找对手」），b 晚两秒再上
	await _at(hub, 20.0)
	_put(hub, Arena.center(0) + (Vector3(-3.0, 0.1, 5.0) if is_a else Vector3(Arena.R + 12.0, -Arena.H + 0.1, 7.0)))
	hub.cam.snap(PI * 0.5 if is_a else PI * 0.5, -0.2, 9.0)
	await _at(hub, 21.8)
	o = _other(pres)
	pu = pres.puppet_of(nm)
	_say(role, "a 先站上白虎擂：对方的木偶看得见=%s，名牌「%s」（b 这边看到的应带「寻找对手」）" % [pres.shown(nm), str((pu.get("_tag") as Label3D).text) if pu != null else ""])
	if not is_a:
		await _shot(hub, "b_2b_see_queue")
		_put(hub, Arena.center(0) + Vector3(3.0, 0.1, 5.0))
	var tq := await _until(hub, func() -> bool: return duel.phase == duel.Ph.FIGHT, 40.0)
	await _wait(hub, 0.8)
	var arena_pu: Node3D = duel.call("_rival_puppet")
	_say(role, "擂台配上（%.1f 秒），对手类型=%s 名字=%s：擂台木偶 有=%s；在场的那个 看得见=%s（应为 false，不然一个人两个影子）" % [tq, duel.kind, duel.get("_rival_name"),
			arena_pu != null, pres.shown(nm)])
	await _shot(hub, "%s_3_duel" % role)
	if duel.kind == "pvp" and arena_pu != null and is_a:
		var n := 0
		while duel.phase == duel.Ph.FIGHT and n < 80:
			arena_pu.call("receive_hit", p, {"dmg": CS.base(p.realm_idx) * 6.0, "dir": Vector3.RIGHT, "kb": 1.0})
			n += 1
			await _wait(hub, 0.25)
	await _until(hub, func() -> bool: return duel.phase == duel.Ph.IDLE, 60.0)
	await _wait(hub, 1.0)
	_say(role, "对决收场（结果 %s）：在场的木偶又看得见=%s（应为 true）" % [duel.last_result, pres.shown(nm)])
	# 5) 副本：a 先匹配进木兰草原（开房）；b 在入境页看那一行，再匹配进同一间。
	# 这一段走的是正式的副本联机端口：局域网里要是有人正开着房间，自检的窗口会进到他们的房间里——默认不跑，加 --lan-raid 才跑
	if not OS.get_cmdline_user_args().has("--lan-raid"):
		await _wait(hub, 3.0 if is_a else 1.0)
		_say(role, "结束（副本那一段没跑：要跑加 --lan-raid）")
		return
	var ui: Node = main.get("level_ui")
	var net: Node = main.get("net")
	if is_a:
		_put(hub, Vector3(0.0, 0.1, 60.0))
		await _wait(hub, 0.5)
		main.call("_open_level_select")
		await _wait(hub, 0.8)
		ui.call("pick", 0)
		await _wait(hub, 0.8)
		var note: Variant = pres.get("_note")
		_say(role, "入境页那一行：「%s」" % (str(note.text).replace("\n", " / ") if is_instance_valid(note) else "（没加上）"))
		await _shot(hub, "a_4_enter_page")
		ui.set("mode", "match")
		ui.call("_go")
		var tl := await _until(hub, func() -> bool: return main.get("level") != null and p.process_mode != Node.PROCESS_MODE_DISABLED, 120.0)
		_say(role, "匹配进了木兰草原（%.1f 秒）：联机开着=%s 我是房主=%s 房间 %d 人" % [tl, net.active, net.is_host, (net.players as Dictionary).size()])
		var tj := await _until(hub, func() -> bool: return (net.players as Dictionary).size() >= 2 and (net.remotes as Dictionary).size() >= 1, 150.0)
		await _wait(hub, 2.0)
		_say(role, "b 进来了（%.1f 秒）：房间 %d 人，副本里看得见的别人 %d 个；在场记录里对方在%s" % [tj, (net.players as Dictionary).size(), (net.remotes as Dictionary).size(),
				str(pres.WHERE_NAMES[int(_other(pres).get("where", 0))])])
		var tg := await _until(hub, func() -> bool: return pres.online() == 0, 60.0)
		_say(role, "b 退出后 %.1f 秒：局域网在线人数归零=%s，房间剩 %d 人" % [tg, pres.online() == 0, (net.players as Dictionary).size()])
	else:
		var tw := await _until(hub, func() -> bool:
			var q := _other(pres)
			return int(q.get("where", 0)) == pres.W.LEVEL and int(q.get("room", 0)) >= 1, 150.0)
		await _wait(hub, 1.0)
		_say(role, "a 进了副本（等了 %.1f 秒）：主城里他的木偶看得见=%s（应为 false）；左上角「%s」" % [tw, pres.shown(nm), str(pres.get("_lab").text)])
		_put(hub, Vector3(0.0, 0.1, 60.0))
		await _wait(hub, 0.5)
		main.call("_open_level_select")
		await _wait(hub, 0.8)
		ui.call("pick", 0)
		await _wait(hub, 1.0)
		var note2: Variant = pres.get("_note")
		_say(role, "入境页那一行：「%s」" % (str(note2.text).replace("\n", " / ") if is_instance_valid(note2) else "（没加上）"))
		await _shot(hub, "b_4_enter_page")
		ui.set("mode", "match")
		ui.call("_go")
		var tl2 := await _until(hub, func() -> bool: return main.get("level") != null and p.process_mode != Node.PROCESS_MODE_DISABLED, 120.0)
		await _wait(hub, 3.0)
		_say(role, "匹配进了木兰草原（%.1f 秒）：联机开着=%s 我是房主=%s 房间 %d 人，副本里看得见的别人 %d 个" % [tl2, net.active, net.is_host,
				(net.players as Dictionary).size(), (net.remotes as Dictionary).size()])
		await _shot(hub, "b_5_in_level")
		await _wait(hub, 3.0)
		_say(role, "退出")
