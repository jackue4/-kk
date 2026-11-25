extends SceneTree
## 主城「元界面」在真游戏里的自检（2026-11-24 界面重做）：正常游玩模式开机进主城（用户参数里放 --qa-metaui：存档走自检档），然后：
##   ① 右上角四个入口 英雄 / 备战 / 坊市 / 段位 都在；真用鼠标点「备战」→ 开的是 meta_ui.gd 的备战页（背景是虚化的主城、游戏暂停、主视口 3D 关）
##   ② 备战页里穿一件、关掉 → 暂停解除、3D 恢复
##   ③ 点「坊市」「段位」「英雄」各开各的；④ 主城里的仓库 / 商店两座建筑（hub_hall.open_abode(0 / 1)）开到备战页的仓库 / 坊市
##   ⑤ 命令行带 --old-lobby 时开的还是老的纸面板大厅（另跑一遍）
## 跑法：python _tasks/trailer/run_hidden.py . _shots/metaui_game --resolution 1701x900 -s res://_tasks/ui_kit/meta_game_test.gd -- <输出目录> --qa-metaui [--touch] [--tag=xxx] [--old-lobby]
##   网页那一档（兼容渲染器）：godot 参数里加 --rendering-method gl_compatibility
## 每条输出以 [metaui] 开头，最后一行「结论」；有不通过的退出码是 1。

const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")

var m: Node
var fails := 0
var _dir := ""
var _tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--qa-metaui"):
		push_error("要带 --qa-metaui（否则会读写玩家自己的存档）")
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
	print("[metaui] " + s)


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[metaui] %s %s%s" % ["通过" if ok else "不通过", what, ("｜" + detail) if detail != "" else ""])


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
	var path := _dir.path_join("metaui_game%s_%s.jpg" % [_tag, name])
	img.save_jpg(path, 0.9)
	print("[metaui] saved ", path, " ", img.get_size())


func click(pos: Vector2) -> void:
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await frames(2)


func abode() -> Control:
	var ui: Variant = m.get("level_ui")
	var ab: Variant = ui.get("_abode") if is_instance_valid(ui) else null
	return ab if is_instance_valid(ab) and not (ab as Node).is_queued_for_deletion() else null


func is_meta(ab: Control) -> bool:
	return ab != null and (ab.get_script() as Script).resource_path.ends_with("meta_ui.gd")


func wait_bg(ui: Control) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(ui) and not bool(ui.get("_bg_ready")) and Time.get_ticks_msec() - t0 < 8000:
		await process_frame


func close_abode() -> void:
	var ab := abode()
	if ab != null:
		ab.call("_close")
	var t0 := Time.get_ticks_msec()
	while abode() != null and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	await frames(3)


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
	var old := OS.get_cmdline_user_args().has("--old-lobby")
	var hud: Node = m.get("hud")
	var dock: Array = hud.get("_dock")
	var bag: Button = hud.get("_bag_btn")
	check("主城右上角四个入口都在", dock.size() == 3 and bag.visible and dock.all(func(b: Button) -> bool: return b.visible),
			"备战在 %s；另外三颗 %s" % [bag.position, str(dock.map(func(b: Button) -> Vector2: return b.position))])
	await shot("0_hub")

	# ① 真点「备战」（隐藏窗口会收到真鼠标的事件：用户正好在动鼠标时这一下会被打断，没开出来就再点，最多三次）
	var ab: Control = null
	for try in 3:
		await click(bag.get_global_transform_with_canvas() * (bag.size * Vector2(0.5, 0.4)))
		await frames(3)
		ab = abode()
		if ab != null:
			break
		say("第 %d 次点「备战」没开出来（多半是真鼠标在动），再点" % (try + 1))
		await wait(0.4)
	if old:
		check("--old-lobby：开的还是老的纸面板大厅", ab != null and (ab.get_script() as Script).resource_path.ends_with("ex_lobby_ui.gd"))
		await wait(0.5)
		await shot("1_old_lobby")
		await close_abode()
		check("关掉后不再暂停", not paused)
		_finish()
		return
	check("点「备战」开的是新的元界面、备战页", is_meta(ab) and str(ab.call("tab_key")) == "prep")
	if not is_meta(ab):
		_finish()
		return
	await wait_bg(ab)
	await wait(1.0)
	check("开着时游戏暂停、主视口 3D 关、背景是拍下来的主城", paused and root.disable_3d and (ab.get("_bg") as TextureRect).texture is ImageTexture)
	await shot("1_prep")
	var page: Control = ab.get("page")
	var hero0 := ExProfile.hero()
	check("备战页的人就是出战的英雄", str((page.get("_doll") as Control).get("hero_id")) == hero0, hero0)
	# 卸下兵刃再穿回去
	page.call("select", "equip", 0, "weapon")
	await frames(3)
	var wid := str((ExProfile.equipment()["weapon"] as Dictionary).get("id", ""))
	page.call("press_action", "卸下")
	await wait(0.6)
	var bi := -1
	for i in ExProfile.bag().size():
		if str(ExProfile.bag()[i].get("id", "")) == wid:
			bi = i
	check("卸下兵刃", (ExProfile.equipment()["weapon"] as Dictionary).is_empty() and bi >= 0)
	await shot("2_prep_unequipped")
	page.call("select", "bag", bi)
	await frames(3)
	page.call("press_action", "穿戴")
	await wait(0.8)
	check("再穿回去", str((ExProfile.equipment()["weapon"] as Dictionary).get("id", "")) == wid)
	var n := 0
	var t1 := Time.get_ticks_usec()
	while n < 90:
		await process_frame
		n += 1
	say("备战页开着时 90 帧平均 %.2f 毫秒" % (float(Time.get_ticks_usec() - t1) * 0.001 / 90.0))
	await close_abode()
	check("关掉：暂停解除、3D 恢复", not paused and not root.disable_3d)

	# ③ 坊市 / 段位 / 英雄
	await click((dock[1] as Button).get_global_transform_with_canvas() * ((dock[1] as Button).size * Vector2(0.5, 0.4)))
	await frames(3)
	if abode() == null:
		(dock[1] as Button).pressed.emit()
		await frames(3)
	ab = abode()
	check("点「坊市」开坊市页", is_meta(ab) and str(ab.call("tab_key")) == "shop")
	if is_meta(ab):
		await wait_bg(ab)
		await wait(0.9)
		await shot("3_shop")
		(ab.get("page") as Control).call("goto", "sell")
		await wait(0.6)
		await shot("4_shop_sell")
	await close_abode()
	await click((dock[2] as Button).get_global_transform_with_canvas() * ((dock[2] as Button).size * Vector2(0.5, 0.4)))
	await frames(3)
	if abode() == null:
		(dock[2] as Button).pressed.emit()
		await frames(3)
	ab = abode()
	check("点「段位」开段位页", is_meta(ab) and str(ab.call("tab_key")) == "rank")
	if is_meta(ab):
		await wait_bg(ab)
		await wait(1.4)
		await shot("5_rank")
	await close_abode()
	await click((dock[0] as Button).get_global_transform_with_canvas() * ((dock[0] as Button).size * Vector2(0.5, 0.4)))
	await frames(3)
	if not paused:
		(dock[0] as Button).pressed.emit()
		await frames(3)
	var hs: Control = null
	for c in (m.get("level_ui") as Node).get_children():
		var scr: Variant = c.get_script()
		if scr is Script and (scr as Script).resource_path.ends_with("hero_select_ui.gd") and not c.is_queued_for_deletion():
			hs = c as Control
	check("点「英雄」开英雄选择界面", hs != null and paused)
	if hs != null:
		await wait(1.0)
		await shot("6_hero")
		hs.call("close")
		await frames(4)
	check("关掉后不再暂停", not paused and not root.disable_3d)

	# ④ 主城里的两座建筑
	hub.call("open_abode", 0)
	await frames(4)
	ab = abode()
	check("仓库建筑 → 备战页翻到仓库", is_meta(ab) and str(ab.call("tab_key")) == "prep" and str((ab.get("page") as Control).call("list_key")) == "stash"
			and int(ab.get("_tab")) == 0)
	await wait(0.8)
	await shot("7_store_building")
	await close_abode()
	hub.call("open_abode", 1)
	await frames(4)
	ab = abode()
	check("商店建筑 → 坊市页", is_meta(ab) and str(ab.call("tab_key")) == "shop" and int(ab.get("_tab")) == 1)
	await close_abode()
	check("都关掉后不再暂停、3D 恢复", not paused and not root.disable_3d)
	_finish()


func _finish() -> void:
	say("结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))
	quit(1 if fails > 0 else 0)
