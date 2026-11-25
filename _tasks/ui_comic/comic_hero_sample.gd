extends SceneTree
## 「武侠漫画分镜」英雄选择样张的启动脚本（不起主场景、不碰存档）。
## 出图（隐藏窗口）：
##   python _tasks/trailer/run_hidden.py . _shots/comic_run --resolution 1600x900 -s res://_tasks/ui_comic/comic_hero_sample.gd -- <输出目录> --comic-sample --shots [--lite] [--tag=xxx] [--grab]
## 上手试（真窗口）：
##   Godot --path . --resolution 1600x900 -s res://_tasks/ui_comic/comic_hero_sample.gd -- --comic-sample
##   左右划 / 方向键 / 点左边格子换人，点招式块看比划，回车出战，Tab 在 3D 和 2D 立绘之间切（_tasks/ui_comic/art/<英雄 id>.png 有图才有这个开关），Esc 退出。
## --grab：把三位英雄的 3D 原图（没过漫画着色器、透明底）存到输出目录，给生 2D 立绘当参考。

const SCREEN := "res://_tasks/ui_comic/comic_hero_screen.gd"
const HeroDefs := preload("res://scripts/hero_defs.gd")

var ui: Control
var _dir := ""
var _tag := ""
var _shots := false
var _grab := false
var _check := false
var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--comic-sample"):
		push_error("要带 --comic-sample")
		quit(1)
		return
	for a: String in args:
		if a == "--shots":
			_shots = true
		elif a == "--grab":
			_grab = true
		elif a == "--check":
			_check = true
		elif a == "--lite":
			Vfx.lite = true
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif not a.begins_with("--") and _dir == "":
			_dir = a
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://_shots/comic")
	DirAccess.make_dir_recursive_absolute(_dir)
	_start.call_deferred()


func _start() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	ui = (load(SCREEN) as GDScript).new()
	var art: Dictionary = ui.get("art")
	var art_dir := ProjectSettings.globalize_path("res://_tasks/ui_comic/art")
	for id: Variant in HeroDefs.ids():
		var p := art_dir.path_join(str(id) + ".png")
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null:
				img.generate_mipmaps()
				art[str(id)] = ImageTexture.create_from_image(img)
	layer.add_child(ui)
	ui.connect("closed", func() -> void: quit(0))
	if _shots or _grab or _check:
		_run.call_deferred()


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGB8)
	var path := _dir.path_join("comic%s_%s.jpg" % [_tag, name])
	img.save_jpg(path, 0.92)
	print("[comic] saved ", path, " ", img.get_size())


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[comic] %s %s%s" % ["通过" if ok else "不通过", what, ("｜" + detail) if detail != "" else ""])


func mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func click(pos: Vector2) -> void:
	mouse(pos, true)
	await process_frame
	await process_frame
	mouse(pos, false)
	await process_frame


func drag(from: Vector2, to: Vector2) -> void:
	mouse(from, true)
	for i in 6:
		await process_frame
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, float(i + 1) / 6.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm, true)
	await process_frame
	mouse(to, false)
	await process_frame


func center_of(n: Variant) -> Vector2:
	return (n as Control).get_global_rect().get_center()


## 真用鼠标事件走一遍：点格子换人、划一下换人、点招式块、点「出战」、方向键
func _checks() -> void:
	var ids: Array = HeroDefs.ids()
	var roster: Array = ui.get("_roster")
	var tiles: Array = ui.get("_tiles")
	var n := ids.size()
	var to := (int(ui.get("cur")) + 1) % n
	await click(center_of((roster[to] as Dictionary)["btn"]))
	await wait(0.9)
	check("点左边的格子换到那一位", int(ui.get("cur")) == to, "点第 %d 格，cur=%d" % [to, int(ui.get("cur"))])
	var sw := ui.get("_swipe") as Control
	var c := center_of(sw)
	var before := int(ui.get("cur"))
	await drag(c + Vector2(120.0, 0.0), c + Vector2(-120.0, 0.0))
	await wait(0.9)
	check("往左划换到下一位", int(ui.get("cur")) == (before + 1) % n, "%d → %d" % [before, int(ui.get("cur"))])
	var sk := 3 if int(ui.get("skill")) != 3 else 2
	await click(center_of((tiles[sk] as Dictionary)["btn"]))
	await wait(0.3)
	check("点招式块选中它", int(ui.get("skill")) == sk, "点第 %d 块，skill=%d" % [sk, int(ui.get("skill"))])
	if str(ui.get("picked")) == str(ids[int(ui.get("cur"))]):       # 正好停在出战的那位上：再往后翻一位
		ui.call("_goto", int(ui.get("cur")) + 1, 1)
		await wait(0.9)
	var want := str(ids[int(ui.get("cur"))])
	await click(center_of(ui.get("_go")))
	await wait(0.4)
	check("点「出战」换成这一位", str(ui.get("picked")) == want, "picked=%s" % str(ui.get("picked")))
	check("出战后按钮变成出战中、不能再点", (ui.get("_go") as Button).disabled and (ui.get("_go_label") as Label).text == "出战中")
	before = int(ui.get("cur"))
	var ke := InputEventKey.new()
	ke.keycode = KEY_LEFT
	ke.pressed = true
	root.push_input(ke)
	await wait(0.9)
	check("方向键左换回上一位", int(ui.get("cur")) == posmod(before - 1, n), "%d → %d" % [before, int(ui.get("cur"))])
	var desc := ui.get("_desc") as Label
	var box := ui.get("_desc_box") as Control
	var awake := ui.get("_awake") as Label
	var bottom := maxf(desc.get_global_rect().end.y, awake.get_global_rect().end.y if awake.visible else 0.0)
	check("说明文字没有超出说明框", bottom <= box.get_global_rect().end.y + 1.0 and desc.get_global_rect().end.x <= box.get_global_rect().end.x,
			"字到 %.0f，框到 %.0f" % [bottom, box.get_global_rect().end.y])
	print("[comic] 结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))


func _run() -> void:
	await wait(3.4)
	var ids: Array = HeroDefs.ids()
	if _grab:
		var fig: Object = ui.get("_fig")
		for i in ids.size():
			if i > 0:
				ui.call("_goto", i, 1)
				await wait(2.2)
			var img: Image = fig.call("grab")
			if img != null:
				var p := _dir.path_join("raw_%s.png" % str(ids[i]))
				img.save_png(p)
				print("[comic] raw ", p, " ", img.get_size())
		quit(0)
		return
	if not _shots:
		await _checks()
		quit(1 if fails > 0 else 0)
		return
	await shot("1_open")
	ui.call("_pick_skill", 4, true)
	await wait(0.75)
	await shot("2_skill")
	for i in range(1, ids.size()):
		ui.call("_goto", i, 1)
		await wait(0.16)
		await shot("3_switching_%d" % i)
		await wait(3.2)
		await shot("4_hero_%d" % i)
	ui.call("_on_go")
	await wait(0.7)
	await shot("5_picked")
	if not (ui.get("art") as Dictionary).is_empty():
		ui.call("set_art_mode", true)
		ui.call("_goto", 0, 1)
		await wait(1.8)
		await shot("6_art_0")
		ui.call("_pick_skill", 1, true)
		await wait(0.5)
		await shot("6_art_0_skill")
	if _check:
		await _checks()
	print("[comic] done")
	quit(1 if fails > 0 else 0)
