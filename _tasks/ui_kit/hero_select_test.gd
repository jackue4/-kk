extends SceneTree
## 英雄选择界面（scripts/ex/hero_select_ui.gd）的小样 + 自检：不起主场景，搭一片假场景（地面 + 一堆彩色方块）当「要被虚化的背景」，
## 真把界面建出来，照着用户的操作走一遍：点技能圆片 → 真用鼠标事件划一下换人 → 点「出战」→ 方向键 / 点两侧换回来 → 关掉。
## 每一步截一张 JPG，逐项核对（正中是谁 / 存档换没换 / 主视口的 3D 关了没、关界面后恢复没）。
## 跑法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/heroui --resolution 1701x900 -s res://_tasks/ui_kit/hero_select_test.gd -- <输出目录> --hero-ui-test [--touch] [--lite] [--web-fonts] [--tag=xxx]
## 必须带 --hero-ui-test（不在 raid_profile.gd 的 PLAY_ARGS 里 → 存档走自检档，不碰玩家的档）。
## --lite = 手机画质档（展台不开抗锯齿、封顶 720 高）；--web-fonts = 用随包字体（网页 / 手机上的字形和行高）。
## 每条输出以 [heroui] 开头，最后一行「结论」；有不通过的退出码是 1。

const UI := "res://scripts/ex/hero_select_ui.gd"
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

var ui: Control
var layer: CanvasLayer
var fails := 0
var _dir := ""
var _tag := ""
var _closed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--hero-ui-test"):
		push_error("要带 --hero-ui-test（否则会读写玩家自己的存档）")
		quit(1)
		return
	for a: String in args:
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif not a.begins_with("--") and _dir == "":
			_dir = a
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://_shots/preview")
	if args.has("--web-fonts"):
		UiStyle.force_bundled = true
	for a: String in args:
		if a.begins_with("--brush-font="):
			# 预览：正文 / 题字都换成这个字体文件（缺字落到随包正文字体上）；要先于任何界面建出来
			UiStyle.force_bundled = true
			var ff := FontFile.new()
			if ff.load_dynamic_font(a.get_slice("=", 1)) == OK:
				var chain: Array[Font] = [UiStyle.bundled(UiStyle.BODY_FILE)]
				ff.fallbacks = chain
				UiStyle._kai = ff
				UiStyle._brush = ff
				print("[font] 预览字体 ", a.get_slice("=", 1))
	if args.has("--lite"):
		Vfx.lite = true
	_build_scene.call_deferred()


## 假场景：一片草地、一圈高高低低的彩色方块、偏暖的天。只是为了看「虚化的场景」那一层出来是什么样
func _build_scene() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.4, -0.8, -0.5).normalized(), Vector3.UP)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(200, 200)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.66, 0.36)
	ground.material_override = gmat
	world.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cols := [Color(0.95, 0.62, 0.7), Color(0.55, 0.42, 0.75), Color(0.9, 0.82, 0.6), Color(0.35, 0.6, 0.8), Color(0.8, 0.35, 0.3), Color(0.92, 0.9, 0.86)]
	for i in 60:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := rng.randf_range(1.5, 9.0)
		bm.size = Vector3(rng.randf_range(1.5, 4.0), h, rng.randf_range(1.5, 4.0))
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % cols.size()]
		b.material_override = m
		b.position = Vector3(rng.randf_range(-45.0, 45.0), h * 0.5, rng.randf_range(-70.0, -8.0))
		world.add_child(b)
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.12, -1.0).normalized(), Vector3.UP), Vector3(0.0, 4.0, 10.0))
	cam.current = true
	layer = CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	_run.call_deferred()


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
	var path := _dir.path_join("heroui%s_%s.jpg" % [_tag, name])
	img.save_jpg(path, 0.9)
	print("[heroui] saved ", path, " ", img.get_size())


func mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


## 从 a 划到 b（界面坐标），steps 帧走完；hold_shot 非空 = 划到一半截一张
func swipe(a: Vector2, b: Vector2, steps := 10, mid_shot := "") -> void:
	mouse(a, true)
	await frames(1)
	var prev := a
	for i in steps:
		var p := a.lerp(b, float(i + 1) / float(steps))
		move(p, p - prev)
		prev = p
		await frames(1)
		if mid_shot != "" and i == steps / 2:
			await shot(mid_shot)
	mouse(b, false)
	await frames(1)


func key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await frames(1)
	var e2 := InputEventAction.new()
	e2.action = action
	e2.pressed = false
	Input.parse_input_event(e2)


func _run() -> void:
	await frames(3)
	var vs := root.get_visible_rect().size
	say("画面 %s，渲染 %s，存档 %s（自检档 %s），手机画质档 %s，随包字体 %s" % [vs, RenderingServer.get_current_rendering_method(), ExProfile._path(),
			ExProfile.test_mode(), Vfx.lite, UiStyle.force_bundled])
	check("存档走自检档", ExProfile.test_mode())
	if not ExProfile.test_mode():
		quit(1)
		return
	ExProfile.set_hero("yujian")
	var t0 := Time.get_ticks_msec()
	ui = (load(UI) as GDScript).call("open", layer, true)
	ui.connect("closed", func() -> void: _closed += 1)
	ui.set("wheel", false)             # 隐藏窗口也会收到真鼠标的滚轮（用户正在用这台电脑），会把人换走
	await frames(1)
	say("建界面 %d 毫秒" % (Time.get_ticks_msec() - t0))
	check("打开时游戏暂停", paused)
	# 冷启动头几帧在现编着色器，一帧几百毫秒：等背景拍好再往下
	var tw := Time.get_ticks_msec()
	while not bool(ui.get("_bg_ready")) and Time.get_ticks_msec() - tw < 8000:
		await process_frame
	say("背景拍好用了 %d 毫秒" % (Time.get_ticks_msec() - t0))
	await wait(0.6)
	check("打开停在存档里出战的那位", str(ui.call("current_id")) == "yujian", "正中 %s" % ui.call("current_id"))
	check("背景拍到了场景、主视口的 3D 关了", bool(ui.get("_bg_ready")) and root.disable_3d and (ui.get("_bg") as TextureRect).texture is ImageTexture,
			"拍好=%s 主视口 3D 关=%s 背景贴图=%s" % [ui.get("_bg_ready"), root.disable_3d, (ui.get("_bg") as TextureRect).texture])
	var vp: SubViewport = ui.get("_vp")
	say("展台画 %s，抗锯齿 %d；英雄 %s" % [vp.size, vp.msaa_3d, str(ui.get("_ids"))])
	check("出战中的那位按钮是「出战中」、不能点", (ui.get("_pick") as Button).disabled and (ui.get("_pick") as Button).text == "出战中")
	await shot("0_open")

	# 点六颗圆片：说明跟着换，人比划
	var names: Array = []
	for i in 6:
		ui.call("_pick_skill", i, true)
		await wait(0.25)
		names.append("%s｜%s" % [(ui.get("_sk_name") as Label).text, (ui.get("_sk_desc") as Label).text.left(16)])
		if i == 0:
			await shot("1_yujian_m1")
		elif i == 4:
			await shot("1_yujian_r")
		await wait(0.9 if i == 0 else 0.5)
	say("御剑六颗圆片：" + " ／ ".join(names))
	check("六颗圆片都有名字和说明", names.all(func(s: String) -> bool: return s.length() > 6 and not s.begins_with("｜")))
	ui.call("_pick_skill", 1, false)
	await wait(0.6)

	# 真划一下：往左划 = 换到右边那位
	await swipe(Vector2(vs.x * 0.62, vs.y * 0.45), Vector2(vs.x * 0.36, vs.y * 0.47), 12, "2_drag")
	await wait(0.25)
	await shot("2_settling")
	await wait(0.8)
	check("往左划换到苍鸿", str(ui.call("current_id")) == "canghong", "正中 %s，转盘位置 %.3f" % [ui.call("current_id"), float(ui.get("_offset"))])
	check("没出战的那位按钮是「出战」、能点", not (ui.get("_pick") as Button).disabled and (ui.get("_pick") as Button).text == "出战")
	await wait(0.5)
	await shot("3_canghong")
	names.clear()
	for i in 6:
		ui.call("_pick_skill", i, true)
		await wait(0.22)
		names.append("%s｜%s" % [(ui.get("_sk_name") as Label).text, (ui.get("_sk_desc") as Label).text.left(16)])
		if i == 1:
			await shot("4_canghong_e")
		elif i == 4:
			await wait(0.5)
			await shot("4_canghong_r")
		elif i == 5:
			await wait(0.3)
			await shot("4_canghong_awaken")
		await wait(0.7)
	say("苍鸿六颗圆片：" + " ／ ".join(names))
	check("苍鸿技能带觉醒后的说明", (ui.get("_sk_awake") as Label).text == "" and names.size() == 6)      # 最后停在「觉醒」那颗：没有第二行
	ui.call("_pick_skill", 1, false)
	await frames(3)
	check("一闪带「觉醒后 → 瞬狱」", (ui.get("_sk_awake") as Label).text.contains("瞬狱"), (ui.get("_sk_awake") as Label).text)

	# 再往左划：已经是最后一位，拉得动一点、松手弹回来
	await swipe(Vector2(vs.x * 0.62, vs.y * 0.45), Vector2(vs.x * 0.3, vs.y * 0.45), 8)
	await wait(0.7)
	check("最后一位再往左划会弹回来", str(ui.call("current_id")) == "canghong" and absf(float(ui.get("_offset")) - 1.0) < 0.02,
			"转盘位置 %.3f" % float(ui.get("_offset")))

	# 出战
	var ok := bool(ui.call("pick"))
	await wait(0.12)
	await shot("5_pick_stamp")
	await wait(0.7)
	check("点「出战」存档换成苍鸿", ok and ExProfile.hero() == "canghong", "pick=%s 存档=%s" % [ok, ExProfile.hero()])
	check("出战后按钮变成「出战中」", (ui.get("_pick") as Button).disabled and (ui.get("_pick") as Button).text == "出战中")
	await shot("5_picked")

	# 方向键换回去；点右边那位再换回来
	await key("ui_left")
	await wait(0.9)
	check("方向键左换回御剑", str(ui.call("current_id")) == "yujian")
	await shot("6_back_yujian")
	mouse(Vector2(vs.x * 0.74, vs.y * 0.5), true)
	await frames(2)
	mouse(Vector2(vs.x * 0.74, vs.y * 0.5), false)
	await wait(0.9)
	check("点右侧那位换过去", str(ui.call("current_id")) == "canghong")
	# 真点底下第三颗圆片（按钮吃得到点击、不会被当成划）
	var chip: Button = (ui.get("_chips") as Array)[3]
	var cp := chip.get_global_transform_with_canvas() * (chip.size * Vector2(0.5, 0.36))
	mouse(cp, true)
	await frames(2)
	mouse(cp, false)
	await frames(3)
	check("真点圆片选中技能", int(ui.get("_skill")) == 3 and str(ui.call("current_id")) == "canghong", "选中第 %d 颗「%s」" % [int(ui.get("_skill")),
			(ui.get("_sk_name") as Label).text])

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
	say("开着时 90 帧平均 %.2f 毫秒，最长 %.2f 毫秒" % [float(Time.get_ticks_usec() - t1) * 0.001 / 90.0, worst])

	# 关掉：ESC
	await key("ui_cancel")
	await frames(4)
	check("ESC 关掉：发了 closed、节点拆了", _closed == 1 and not is_instance_valid(ui), "closed %d 次" % _closed)
	check("关掉后主视口的 3D 恢复、暂停解除", not root.disable_3d and not paused, "3D 关=%s 暂停=%s" % [root.disable_3d, paused])
	await shot("7_closed")
	ExProfile.set_hero("yujian")
	say("结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))
	quit(1 if fails > 0 else 0)
