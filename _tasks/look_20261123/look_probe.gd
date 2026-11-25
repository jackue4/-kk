extends SceneTree
## 画面专项（2026-11-23）的探针：以「正常游玩」模式开机（用户参数里放 --qa-look，存档走自检档），
## 在主城和木兰草原按固定机位拍图（改之前 / 改之后对照），并可把场景里的静态网格导出给 zfight.py 找共面重叠的面。
## 跑法：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1280x720 -s res://_tasks/look_20261123/look_probe.gd -- --qa-look --tag=before [--touch] [--hub] [--meadow] [--dump]
##   手机档再加引擎参数 --rendering-method gl_compatibility，用户参数 --touch
## 图存 _shots/look/<tag>_*.jpg（1100 宽）；网格存 _shots/look/geo_<tag>_<场景>.bin

var m: Node
var tag := "x"
var out_dir := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
	out_dir = ProjectSettings.globalize_path("res://_shots/look")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func say(s: String) -> void:
	print("[look] " + s)


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	var lum := _stats(img)
	if img.get_width() > 1100:
		img.resize(1100, int(1100.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_jpg("%s/%s_%s.jpg" % [out_dir, tag, name], 0.9)
	say("图 %s_%s｜%s" % [tag, name, lum])


## 画面统计：平均亮度、过曝（任一通道 ≥ 0.98）占比、近黑占比、平均饱和度、灰白（亮而不饱和）占比
func _stats(img: Image) -> String:
	var s := img.duplicate() as Image
	s.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var n := 0
	var lum := 0.0
	var sat := 0.0
	var hot := 0
	var dark := 0
	var pale := 0
	for y in 90:
		for x in 160:
			var c := s.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lum += l
			sat += c.s
			if maxf(c.r, maxf(c.g, c.b)) >= 0.98:
				hot += 1
			if l < 0.06:
				dark += 1
			if l > 0.72 and c.s < 0.12:
				pale += 1
			n += 1
	return "亮度 %.3f 饱和 %.3f 过曝 %.1f%% 近黑 %.1f%% 灰白 %.1f%%" % [lum / n, sat / n, 100.0 * hot / n, 100.0 * dark / n, 100.0 * pale / n]


func cine(pos: Vector3, look: Vector3, fov: float) -> void:
	var cam: Node = m.get("cam")
	cam.set("cine_xf", Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos))
	cam.set("cine_fov", fov)
	cam.set("cine_k", 1.0)


func cine_off() -> void:
	(m.get("cam") as Node).set("cine_k", 0.0)


## 帧耗时：量 sec 秒，返回 [中位, 九成, 最长]（毫秒）
func frames(sec: float) -> Array:
	var ft: Array = []
	var last := Time.get_ticks_usec()
	var t0 := last
	while Time.get_ticks_usec() - t0 < int(sec * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
	ft.sort()
	if ft.is_empty():
		return [0.0, 0.0, 0.0]
	return [ft[ft.size() / 2], ft[int(ft.size() * 0.9)], ft[ft.size() - 1]]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var do_hub := args.has("--hub") or not args.has("--meadow")
	var do_meadow := args.has("--meadow") or not args.has("--hub")
	var ok: bool = await wait_until(func() -> bool:
		var h: Variant = m.get("hub")
		return h != null and bool(h.get("active")) and (m.get("player") as Node).process_mode != Node.PROCESS_MODE_DISABLED, 240.0)
	say("开机到主城 %s｜渲染器 %s｜窗口 %s｜3D 缩放 %.2f" % ["成功" if ok else "超时", RenderingServer.get_current_rendering_method(), str(root.size), root.scaling_3d_scale])
	await wait(2.5)
	var player := m.get("player") as Node3D
	var cam: Node = m.get("cam")
	var hub: Node = m.get("hub")
	if args.has("--perf"):
		await perf_ab(hub, "主城")
		if args.has("--meadow"):
			m.call("_open_level_select")
			await wait(0.8)
			(m.get("level_ui") as Node).call("pick", 0, true)
			await wait_until(func() -> bool:
				return m.get("level") != null and (m.get("player") as Node).process_mode != Node.PROCESS_MODE_DISABLED and float((m.get("level_ui") as Node).get("_fade").color.a) < 0.05, 240.0)
			await wait(5.0)
			await perf_ab(m.get("level"), "草原")
		say("完成")
		quit()
		return
	if args.has("--farm"):
		# 灵田农场（和主城共用同一套环境 / 调色）：站到主城那道门前、走过去，在农场里拍两张
		player.global_position = Vector3(54.0, 0.1, 16.0)
		await wait(0.3)
		hub.call("_through", hub.get("_portal_town"), "farm")
		await wait(1.2)
		var fp := player.global_position
		for fv: Array in [["farm_p0", 0.0, -0.14], ["farm_p1", PI * 0.5, -0.1], ["farm_p2", -PI * 0.5, -0.1]]:
			cam.call("snap", float(fv[1]), float(fv[2]), 8.0)
			await wait(1.0)
			await shot(str(fv[0]))
		cine(fp + Vector3(0.0, 46.0, 60.0), fp + Vector3(0.0, 0.0, -30.0), 60.0)
		await wait(0.8)
		await shot("farm_c0")
		cine_off()
		say("完成")
		quit()
		return
	if do_hub:
		# 机位：[名字, 机位, 看向, 视角]
		var views := [
			["hub_0_overview", Vector3(0.0, 112.0, 176.0), Vector3(0.0, 0.0, -8.0), 56.0],
			["hub_1_plaza", Vector3(10.0, 12.0, 46.0), Vector3(0.0, 8.0, -10.0), 62.0],
			["hub_2_gates", Vector3(0.0, 12.0, -14.0), Vector3(0.0, 11.0, -58.0), 80.0],
			["hub_3_west", Vector3(-30.0, 16.0, 16.0), Vector3(-122.0, 4.0, -28.0), 66.0],
			["hub_4_east", Vector3(30.0, 16.0, 16.0), Vector3(122.0, 4.0, -28.0), 66.0],
			["hub_5_pond", Vector3(-12.0, 9.0, 62.0), Vector3(-40.0, 0.0, 42.0), 60.0],
			["hub_6_far", Vector3(150.0, 30.0, 150.0), Vector3(0.0, 4.0, 0.0), 50.0],
			["hub_a0_west_arena", Vector3(-56.0, 30.0, 30.0), Vector3(-124.0, 3.0, -30.0), 64.0],
			["hub_a1_east_top", Vector3(122.0, 96.0, 44.0), Vector3(122.0, 3.0, -30.0), 60.0],
			["hub_a2_east_stairs", Vector3(52.0, 9.0, -20.0), Vector3(104.0, 6.0, -28.0), 64.0],
			["hub_a3_ref", Vector3(0.0, 150.0, 190.0), Vector3(0.0, 0.0, -14.0), 62.0],
		]
		for v: Array in views:
			cine(v[1], v[2], float(v[3]))
			await wait(0.6)
			await shot(str(v[0]))
		cine_off()
		# 玩家视角：站在出生点朝北、站在广场南口
		for pv: Array in [["hub_p0_spawn", Vector3(0.0, 0.1, 78.0), 0.0, -0.12], ["hub_p1_plaza", Vector3(0.0, 0.1, 34.0), 0.0, -0.1], ["hub_p2_west", Vector3(-26.0, 0.1, 4.0), PI * 0.5, -0.1],
				["hub_p3_east", Vector3(26.0, 0.1, 4.0), -PI * 0.5, -0.1],
				["hub_p4_on_arena", Vector3(-122.0, 3.1, -2.0), 0.0, -0.16], ["hub_p5_arena_path", Vector3(40.0, 0.1, -28.0), -PI * 0.5, -0.08]]:
			player.global_position = pv[1]
			cam.call("snap", float(pv[2]), float(pv[3]), 8.0)
			await wait(1.0)
			await shot(str(pv[0]))
		var ft: Array = await frames(4.0)
		say("主城玩家视角 帧耗时 中位 %.1f 九成 %.1f 最长 %.1f ms｜绘制调用 %d 图元 %dk" % [ft[0], ft[1], ft[2],
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
		if args.has("--dump"):
			dump(hub, "hub")
	if do_meadow:
		m.call("_open_level_select")
		await wait(0.8)
		var ui: Node = m.get("level_ui")
		ui.call("pick", 0, true)
		var in_ok: bool = await wait_until(func() -> bool:
			var lv: Variant = m.get("level")
			return lv != null and (m.get("player") as Node).process_mode != Node.PROCESS_MODE_DISABLED and float(ui.get("_fade").color.a) < 0.05, 240.0)
		say("进木兰草原 %s" % ("成功" if in_ok else "超时"))
		await wait(4.0)
		var lv: Node = m.get("level")
		var p0 := player.global_position
		for pv2: Array in [["mea_p0_n", 0.0, -0.12], ["mea_p1_e", -PI * 0.5, -0.1], ["mea_p2_s", PI, -0.14], ["mea_p3_w", PI * 0.5, -0.1]]:
			cam.call("snap", float(pv2[1]), float(pv2[2]), 8.0)
			await wait(1.0)
			await shot(str(pv2[0]))
		var ft2: Array = await frames(4.0)
		say("草原玩家视角 帧耗时 中位 %.1f 九成 %.1f 最长 %.1f ms｜绘制调用 %d 图元 %dk" % [ft2[0], ft2[1], ft2[2],
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
		# 高处俯瞰：城垣、港湾方向
		for cv: Array in [["mea_c0_high", p0 + Vector3(30.0, 46.0, 70.0), p0 + Vector3(0.0, 0.0, -20.0), 60.0], ["mea_c1_town", p0 + Vector3(-50.0, 22.0, 40.0), p0 + Vector3(40.0, 4.0, -30.0), 62.0],
				["mea_c2_low", p0 + Vector3(14.0, 3.0, 20.0), p0 + Vector3(-30.0, 6.0, -60.0), 66.0]]:
			cine(cv[1], cv[2], float(cv[3]))
			await wait(1.2)
			await shot(str(cv[0]))
		cine_off()
		if args.has("--dump"):
			dump(lv, "meadow")
	say("完成")
	quit()


## 把 root 下面所有看得见的网格（世界坐标的三角形 + 顶点色）写进一个二进制文件：
## 每个网格：int32 顶点数 n（三角形列表，已按索引展开）、int32 名字字节数、名字、n×3 float32 位置、n×4 float32 颜色
func dump(from: Node, name: String) -> void:
	var f := FileAccess.open("%s/geo_%s_%s.bin" % [out_dir, tag, name], FileAccess.WRITE)
	var count := 0
	var tris := 0
	for c: Node in from.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs := PackedColorArray()
			if arr[Mesh.ARRAY_COLOR] != null:
				cs = arr[Mesh.ARRAY_COLOR]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			var n := idx.size() if not idx.is_empty() else vs.size()
			if n < 3:
				continue
			var pos := PackedFloat32Array()
			pos.resize(n * 3)
			var col := PackedFloat32Array()
			col.resize(n * 4)
			for k in n:
				var vi := idx[k] if not idx.is_empty() else k
				var p := xf * vs[vi]
				pos[k * 3] = p.x
				pos[k * 3 + 1] = p.y
				pos[k * 3 + 2] = p.z
				var cc := cs[vi] if vi < cs.size() else Color(0.5, 0.5, 0.5, 0.0)
				col[k * 4] = cc.r
				col[k * 4 + 1] = cc.g
				col[k * 4 + 2] = cc.b
				col[k * 4 + 3] = cc.a
			var label := ("%s#%d" % [str(from.get_path_to(mi)), si]).to_utf8_buffer()
			f.store_32(n)
			f.store_32(label.size())
			f.store_buffer(label)
			f.store_buffer(pos.to_byte_array())
			f.store_buffer(col.to_byte_array())
			count += 1
			tris += n / 3
	f.close()
	say("导出网格 %s：%d 张，%d 个三角形" % [name, count, tris])


## 同一个进程里开 / 关交替着量（这台机器的显卡常被别的窗口占着，跨进程比不准）：调色表、柔辉光、花瓣各自多花多少
func perf_ab(scene: Node, label: String) -> void:
	var env: Environment = root.get_camera_3d().get_world_3d().environment
	if env == null:
		for c: Node in scene.find_children("*", "WorldEnvironment", true, false):
			env = (c as WorldEnvironment).environment
	var petals: Node3D = null
	for c: Node in scene.find_children("*", "MultiMeshInstance3D", true, false):
		if (c as MultiMeshInstance3D).custom_aabb.size.x > 1000.0:
			petals = c
	var lut := env.adjustment_color_correction
	var tests := [["调色表", func(on: bool) -> void: env.adjustment_color_correction = lut if on else null],
			["辉光", func(on: bool) -> void: env.glow_enabled = on]]
	if petals != null:
		tests.append(["花瓣", func(on: bool) -> void: petals.visible = on])
	for t: Array in tests:
		var off: Array = []
		var on: Array = []
		for r in 5:
			(t[1] as Callable).call(false)
			await wait(0.3)
			off.append((await frames(1.2))[0])
			(t[1] as Callable).call(true)
			await wait(0.3)
			on.append((await frames(1.2))[0])
		off.sort()
		on.sort()
		say("%s｜%s 关 %.2f ms → 开 %.2f ms（各 5 轮交替的中位帧耗时的中位数；差 %+.2f ms）" % [label, t[0], off[2], on[2], float(on[2]) - float(off[2])])
	var ft: Array = await frames(4.0)
	say("%s｜全开 帧耗时 中位 %.2f 九成 %.2f 最长 %.2f ms｜绘制调用 %d 图元 %dk" % [label, ft[0], ft[1], ft[2],
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
