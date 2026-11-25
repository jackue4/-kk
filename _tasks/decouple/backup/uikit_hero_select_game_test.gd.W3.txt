extends SceneTree
## 英雄选择界面在真游戏里的自检（2026-11-24）：正常游玩模式开机进主城（用户参数里放 --qa-heroui：不在 raid_profile.gd 的 PLAY_ARGS 里，
## 存档走自检档，不碰玩家的档），然后两条入口各走一遍：
##   ① 点左上角头像（hud._open_heroes）→ 全屏界面：背景是虚化的主城、主视口 3D 关掉、游戏暂停 → 转到苍鸿 → 出战 → 主角当场换 → 关掉全恢复
##   ② 右上角洞府 →「英雄」页签 → 同一个界面盖在洞府上（洞府藏起来）→ 换回御剑 → 关掉回到洞府「备战」页，那一页的英雄按钮写着御剑
## 跑法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/heroui_game --resolution 1701x900 -s res://_tasks/ui_kit/hero_select_game_test.gd -- <输出目录> --qa-heroui [--touch] [--tag=xxx]
##   网页那一档（兼容渲染器）：godot 参数里加 --rendering-method gl_compatibility
## 每条输出以 [heroui] 开头，最后一行「结论」；有不通过的退出码是 1。

const ExProfile := preload("res://scripts/ex/ex_profile.gd")

var m: Node
var fails := 0
var _dir := ""
var _tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--qa-heroui"):
		push_error("要带 --qa-heroui（否则会读写玩家自己的存档）")
		quit(1)
		return
	for a: String in args:
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif not a.begins_with("--") and _dir == "":
			_dir = a
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://_shots/preview")
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Variant = m.get("cam")
	if is_instance_valid(cam):
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 隐藏窗口别抓用户的鼠标


func say(s: String) -> void:
	print("[heroui] " + s)


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[heroui] %s %s%s" % ["通过" if ok else "不通过", what, ("｜" + detail) if detail != "" else ""])


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func frames(n := 2) -> void:
	for _i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGB8)
	var path := _dir.path_join("heroui_game%s_%s.jpg" % [_tag, name])
	img.save_jpg(path, 0.9)
	print("[heroui] saved ", path, " ", img.get_size())


## 开着的英雄选择界面（挂在 level_select.gd 那一层下面）
func hero_ui() -> Control:
	var host: Node = m.get("level_ui")
	if host == null:
		return null
	for c in host.get_children():
		var scr: Variant = c.get_script()
		if scr is Script and (scr as Script).resource_path.ends_with("hero_select_ui.gd") and not c.is_queued_for_deletion():
			return c as Control
	return null


func wait_bg(ui: Control) -> int:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(ui) and not bool(ui.get("_bg_ready")) and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	return Time.get_ticks_msec() - t0


func _run() -> void:
	var hub: Node = null
	var p: Node3D = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var h: Variant = m.get("hub")
		var pl: Variant = m.get("player")
		if is_instance_valid(h) and bool(h.get("active")) and is_instance_valid(pl) and (pl as Node).process_mode != Node.PROCESS_MODE_DISABLED:
			hub = h
			p = pl
			break
		await process_frame
	if hub == null:
		check("开机", false, "300 秒内没进主城")
		quit(1)
		return
	await wait(3.0)
	say("开机完成（%.0f 秒），画面 %s，渲染 %s，存档 %s" % [float(Time.get_ticks_msec() - t0) * 0.001, root.get_visible_rect().size,
			RenderingServer.get_current_rendering_method(), ExProfile._path()])
	check("存档走自检档", ExProfile.test_mode())
	if not ExProfile.test_mode():
		quit(1)
		return
	if ExProfile.hero() != "yujian":
		ExProfile.set_hero("yujian")
		p.call("set_hero", "yujian")
		await wait(0.5)
	var hud: Node = m.get("hud")
	var hb: Button = hud.get("_hero_btn")
	check("主城里头像上有「换英雄」的入口", hb != null and hb.visible, "按钮在 %s 大小 %s 缩放 %s" % [hb.position, hb.size, hb.scale])
	await shot("0_hub")

	# ---------- ① 点头像 ----------
	var ta := Time.get_ticks_msec()
	hud.call("_open_heroes")
	await frames(1)
	var ui := hero_ui()
	check("点头像开出全屏的英雄选择界面", ui != null, "建界面 %d 毫秒" % (Time.get_ticks_msec() - ta))
	if ui == null:
		quit(1)
		return
	ui.set("wheel", false)
	var bgms := await wait_bg(ui)
	await wait(0.6)
	check("开着时游戏暂停、主视口 3D 关掉、背景是拍下来的场景", paused and root.disable_3d and (ui.get("_bg") as TextureRect).texture is ImageTexture,
			"暂停=%s 3D 关=%s 背景=%s，拍好用了 %d 毫秒" % [paused, root.disable_3d, (ui.get("_bg") as TextureRect).texture, bgms])
	check("停在出战的那位", str(ui.call("current_id")) == "yujian")
	await shot("1_open")
	ui.call("goto_id", "canghong")
	await wait(1.3)
	await shot("2_canghong")
	var ok := bool(ui.call("pick"))
	await wait(0.9)
	check("出战：存档和主城里的主角都换成苍鸿", ok and ExProfile.hero() == "canghong" and str(p.get("hero_id")) == "canghong",
			"pick=%s 存档=%s 主角=%s" % [ok, ExProfile.hero(), p.get("hero_id")])
	await shot("3_picked")
	# 量一下开着的时候每帧多久
	var n := 0
	var t1 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t1
	while n < 90:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) * 0.001)
		last = now
		n += 1
	say("界面开着时 90 帧平均 %.2f 毫秒，最长 %.2f 毫秒" % [float(Time.get_ticks_usec() - t1) * 0.001 / 90.0, worst])
	ui.call("close")
	await frames(4)
	check("关掉：暂停解除、3D 恢复、节点拆了", not paused and not root.disable_3d and hero_ui() == null, "暂停=%s 3D 关=%s" % [paused, root.disable_3d])
	await wait(0.8)
	await shot("4_hub_canghong")
	n = 0
	t1 = Time.get_ticks_usec()
	while n < 90:
		await process_frame
		n += 1
	say("对照：回到主城 90 帧平均 %.2f 毫秒" % (float(Time.get_ticks_usec() - t1) * 0.001 / 90.0))

	# ---------- ② 洞府 →「英雄」页签 ----------
	hud.call("_open_abode")
	await frames(4)
	var ab: Variant = m.get("level_ui").get("_abode")
	check("洞府开了", is_instance_valid(ab) and paused)
	if not is_instance_valid(ab):
		_finish()
		return
	await shot("5_lobby_prep")
	ab.call("_set_tab", "hero")
	await frames(2)
	ui = hero_ui()
	check("「英雄」页签开同一个界面，洞府藏起来", ui != null and not (ab as CanvasItem).visible)
	if ui == null:
		_finish()
		return
	ui.set("wheel", false)
	await wait_bg(ui)
	await wait(0.6)
	check("停在出战的那位（苍鸿）", str(ui.call("current_id")) == "canghong")
	await shot("6_from_lobby")
	ui.call("goto_id", "yujian")
	await wait(1.2)
	ok = bool(ui.call("pick"))
	await wait(0.8)
	check("换回御剑", ok and ExProfile.hero() == "yujian" and str(p.get("hero_id")) == "yujian")
	ui.call("close")
	await frames(4)
	check("关掉回到洞府「备战」页，还是暂停的，3D 恢复", (ab as CanvasItem).visible and str(ab.call("tab_key")) == "prep" and paused and not root.disable_3d,
			"洞府可见=%s 页=%s 暂停=%s 3D 关=%s" % [(ab as CanvasItem).visible, ab.call("tab_key"), paused, root.disable_3d])
	var hero_btn_ok := false
	for nd: Node in (ab as Node).find_children("*", "Button", true, false):
		if (nd as Button).text == "英雄：御剑" and (nd as Button).is_visible_in_tree():
			hero_btn_ok = true
	check("备战页上的英雄按钮写着御剑", hero_btn_ok)
	await shot("7_lobby_back")
	ab.call("_close")
	await frames(4)
	check("洞府关掉后不再暂停", not paused)
	_finish()


func _finish() -> void:
	ExProfile.set_hero("yujian")
	say("结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))
	quit(1 if fails > 0 else 0)
