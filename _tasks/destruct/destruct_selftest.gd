extends SceneTree
## 场景破坏自检（2026-11-25，scripts/destruct.gd）：正常开机进主城 → 主城里试一下「只叠表现」→ 单人进图 → 依次：
##   平地炸坑（高度表 / 落脚高度确实低了、同处再炸不加深、连着猛炸不会低过上限）、打碎一个小件（实心查询没了）、
##   高速撞墙（撞穿、墙上只开一个洞、慢速撞不坏）、斜着犁一道沟（分帧）、坠地砸坑、不可破坏的范围（出生点 / 钥匙房）、
##   碎块池不超上限、把这一路的操作在另一个新建的世界上重放一遍（验联机补进度的结果一致）。每次爆破打印耗时和之后一秒里最长的一帧。
## 跑法（要真窗口，走 run_hidden；必须带 --qa-destruct：存档走自检档）：
##   python -I _tasks/trailer/run_hidden.py . _tasks/destruct/logs/desert --resolution 1280x720 -s res://_tasks/destruct/destruct_selftest.gd -- --qa-destruct --map=desert
##   手机档：godot 参数里加 --rendering-method gl_compatibility，用户参数里加 --touch
## 截图：_shots/preview/destruct_<图>_<名>[_gl].jpg。每条输出以 [destruct] 开头，最后一行「结论」；有不通过的退出码是 2。

const Destruct := preload("res://scripts/destruct.gd")
const GridWorld := preload("res://scripts/ex/grid_world.gd")

var m: Node
var level: Node3D
var world: GridWorld
var player: Player
var cam: CameraRig
var map_id := "desert"
var gl := false
var shots := true
var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--qa-destruct"):
		push_error("要带 --qa-destruct（否则会读写玩家自己的存档）")
		quit(1)
		return
	for a: String in args:
		if a.begins_with("--map="):
			map_id = a.substr(6)
		elif a == "--no-shots":
			shots = false
	# 主线同时在改战斗脚本：哪个脚本这会儿编不过，主场景就起不来（隐藏窗口不会自己退）—— 先验一遍，起不来就直接退
	var ms: Variant = load("res://scripts/main.gd")
	if ms == null or not (ms as GDScript).can_instantiate():
		print("[destruct] 结论：没跑（main.gd 这会儿编不过，多半是别的脚本正改到一半，看 stderr）")
		quit(3)
		return
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m
	gl = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var c: Variant = m.get("cam")
	if is_instance_valid(c):
		c.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 隐藏窗口别抓用户的鼠标


func say(s: String) -> void:
	print("[destruct] " + s)


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	say("TEST %s %s · %s" % [what, "PASS" if ok else "FAIL", detail])


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(tag: String) -> void:
	if not shots or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var name := "destruct_%s_%s%s" % [map_id, tag, "_gl" if gl else ""]
	img.save_jpg("res://_shots/preview/%s.jpg" % name, 0.88)
	say("shot " + name)


func put(p: Vector3, yaw := 0.0) -> void:
	player.force_ground()
	var y: float = level.call("floor_at", p.x, p.z, p.y + 1.0)
	player.global_position = Vector3(p.x, y + 0.05, p.z)
	player.velocity = Vector3.ZERO
	player.face_now(yaw)
	cam.snap(yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
	await frames(2)


func settle(sec := 1.0) -> void:
	var t := 0.0
	var t0 := Time.get_ticks_msec()
	while t < 10.0:
		await process_frame
		t = float(Time.get_ticks_msec() - t0) / 1000.0
		if world.ready_near(player.global_position) and world.rebuilding() == 0 and t > sec:
			break


func cine(at: Vector3, look: Vector3, fov := 62.0) -> void:
	cam.set("cine_xf", Transform3D(Basis.looking_at((look - at).normalized(), Vector3.UP), at))
	cam.set("cine_fov", fov)
	cam.set("cine_k", 1.0)
	await frames(3)


## 这之后 sec 秒里最长的一帧（毫秒）、地块重排完用了多久（毫秒，-1 = 没等到）、最长那一帧是第几帧 / 那一帧里有没有地块落地
func spike(sec := 1.0) -> Array:
	var worst := 0.0
	var rebuilt := -1.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var fi := 0
	var note := ""
	var built := world.built
	var head := ""
	while Time.get_ticks_usec() - t0 < int(sec * 1.0e6):
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		if fi < 6:
			head += "%.0f " % ms
		if ms > worst:
			worst = ms
			note = "第 %d 帧%s" % [fi, "（有地块落地）" if world.built != built else ""]
		built = world.built
		last = now
		fi += 1
		if rebuilt < 0.0 and world.rebuilding() == 0 and (world.get("_dx_split_dirty") as Dictionary).is_empty():
			rebuilt = float(now - t0) / 1000.0
	return [worst, rebuilt, note + " 头几帧 " + head]


func ground(p: Vector3) -> float:
	return world.height(p.x, p.z)


func in_play(p: Vector3) -> bool:
	var lay: Dictionary = ((level.get("map") as Dictionary)["layers"] as Dictionary)[str(level.call("layer_of", p))]
	return (lay["play"] as Rect2).grow(-12.0).has_point(Vector2(p.x, p.z))


## center 周围找一处平地：不在保护范围里、周围没方块、四下一样高
func find_flat(center: Vector3, r0: float, r1: float, clear := 7.0) -> Vector3:
	var r := r0
	while r <= r1:
		for i in 16:
			var a := TAU * float(i) / 16.0 + r * 0.37
			var q := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
			q.y = ground(q)
			if not in_play(q) or world.dx_protected(q.x, q.z) or absf(q.y - center.y) > 4.0:
				continue
			var ok := world.dx_box_at(q + Vector3(0, 1.0, 0), clear) < 0
			for d: Vector3 in [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4), Vector3(8, 0, 8), Vector3(-8, 0, -8)]:
				if absf(ground(q + d) - q.y) > 0.6 or world.dx_protected(q.x + d.x, q.z + d.z):
					ok = false
			if ok:
				return q
		r += 4.0
	return Vector3.INF


## 离 near 最近的、满足 pred(尺寸, 变换) 的、打得坏的实心方块（-1 = 没有）
func find_box(near: Vector3, pred: Callable, skip := {}) -> int:
	var n := world.dx_box_count().x
	var bi: PackedInt32Array = world.get("_bx_i")
	var cands: Array = []
	for id in n:
		if (bi[id * 5 + 4] & 3) != 3 or bi[id * 5] == GridWorld.DX_ROOF or skip.has(id):
			continue
		var xf: Transform3D = world.call("_bx_xf", id)
		if absf(xf.origin.y - near.y) > 30.0:
			continue
		var d := Vector2(xf.origin.x - near.x, xf.origin.z - near.z).length()
		if d > 420.0:
			continue
		if bool(pred.call(world.call("_bx_size", id), xf)):
			cands.append([d, id])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in cands:
		var xf2: Transform3D = world.call("_bx_xf", int(e[1]))
		if world.dx_box_breakable(int(e[1])) and in_play(xf2.origin):
			return int(e[1])
	return -1


## 一根细高的实心柱（半高 ≥ 2 米）和坐在它顶上的一个小件：[下, 上]；找不到返回 []
func find_stack() -> Array:
	var n := world.dx_box_count().x
	var bi: PackedInt32Array = world.get("_bx_i")
	var grid: Dictionary = world.get("_bx_grid")
	for a in n:
		if (bi[a * 5 + 4] & 3) != 3 or bi[a * 5] == GridWorld.DX_ROOF:
			continue
		var sa: Vector3 = world.call("_bx_size", a)
		if sa.y < 3.0 or maxf(sa.x, sa.z) > 3.0 or minf(sa.x, sa.z) < 0.5:
			continue
		var xa: Transform3D = world.call("_bx_xf", a)
		if xa.basis.y.y < 0.99 or not in_play(xa.origin) or not world.dx_box_breakable(a):
			continue
		var top := xa.origin.y + sa.y * 0.5
		var e: Variant = grid.get(Vector2i(int(floorf(xa.origin.x / GridWorld.DX_GRID)), int(floorf(xa.origin.z / GridWorld.DX_GRID))))
		if e == null:
			continue
		for b: int in (e as PackedInt32Array):
			if b == a or (bi[b * 5 + 4] & 1) == 0:
				continue
			var sb: Vector3 = world.call("_bx_size", b)
			var xb: Transform3D = world.call("_bx_xf", b)
			if maxf(sb.x, maxf(sb.y, sb.z)) > 5.0 or xb.basis.y.y < 0.99:
				continue
			var bot := xb.origin.y - sb.y * 0.5
			if bot >= top - 0.05 and bot <= top + 0.3 and absf(xb.origin.x - xa.origin.x) < sa.x * 0.5 and absf(xb.origin.z - xa.origin.z) < sa.z * 0.5:
				return [a, b]
	return []


## 离 near 最近的、屋顶 / 楼板组里的、打得坏的实心方块
func find_roof_box(near: Vector3) -> int:
	var n := world.dx_box_count().x
	var bi: PackedInt32Array = world.get("_bx_i")
	var best := -1
	var bd := 1.0e9
	for id in n:
		if (bi[id * 5 + 4] & 3) != 3 or bi[id * 5] != GridWorld.DX_ROOF:
			continue
		var sz: Vector3 = world.call("_bx_size", id)
		if maxf(sz.x, sz.z) < 5.0 or sz.y > 1.5:
			continue
		var xf: Transform3D = world.call("_bx_xf", id)
		var d := Vector2(xf.origin.x - near.x, xf.origin.z - near.z).length()
		if d < bd and in_play(xf.origin) and world.dx_box_breakable(id):
			bd = d
			best = id
	return best


func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	# 手机档开机先走一遍载入预热（黑场、主角定住）：等它收了再测、再截图
	var tb := 0.0
	var fd: Variant = (m.get("level_ui") as Node).get("_fade")
	while tb < 120.0 and (player.process_mode == Node.PROCESS_MODE_DISABLED or (fd != null and float(fd.color.a) > 0.02)):
		await wait(0.25)
		tb += 0.25
	if tb > 0.0:
		say("等开机预热 %.1f 秒" % tb)
	# —— 主城：只叠表现 ——
	var hp := player.global_position
	var f0 := Destruct.fx()
	var hub_ret := Destruct.blast(hp + Vector3(3.0, 0.2, 0.0), 4.0, 1.0)
	await frames(3)
	check("主城只叠表现", not hub_ret and f0 != null and f0.live > 0 and Destruct.mode() == 3,
			"返回 %s（没有真破坏）· 翻起的石板 / 碎块 %d 块 · 模式 %d" % [hub_ret, f0.live if f0 != null else -1, Destruct.mode()])
	await wait(0.6)
	await shot("hub_overlay")
	# —— 擂台：台面真碎（arena_floor.gd）——
	var hub: Node = m.get("hub")
	var fl: Node = (hub.get("_root") as Node).get_node_or_null("ArenaFloor") if hub != null else null
	check("擂台台面登记", fl != null and (fl.get("cells") as Dictionary).size() > 1000, "能碎的格子 %d 个（两座）· 压着金纹的格子 %d 个" % [
			(fl.get("cells") as Dictionary).size() if fl != null else -1, (fl.get("inlay") as Dictionary).size() if fl != null else -1])
	if fl != null:
		# 人要站到台面上：先把擂台对决停掉（站上去会开始匹配、到局域网里开房找人；这里只测台面）
		var duel: Node = hub.get("duel")
		if duel != null:
			duel.set("use_net", false)
			duel.process_mode = Node.PROCESS_MODE_DISABLED
		var ac := Vector3(-122.0, 3.0, -28.0)        # 西「白虎擂」台心
		player.force_ground()
		player.global_position = ac + Vector3(12.0, 0.1, 9.0)
		player.velocity = Vector3.ZERO
		cam.snap(0.9, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
		await wait(0.6)
		cam.set("cine_xf", Transform3D(Basis.looking_at((ac + Vector3(2.0, 0.0, 1.0) - (ac + Vector3(15.0, 11.0, 15.0))).normalized(), Vector3.UP), ac + Vector3(15.0, 11.0, 15.0)))
		cam.set("cine_fov", 62.0)
		cam.set("cine_k", 1.0)
		await frames(4)
		await shot("arena_before")
		var ap := ac + Vector3(5.0, 0.3, 4.0)
		var ag0: float = hub.call("ground", ap.x, ap.z)
		var aok := Destruct.blast(ap, 4.0, 1.0)
		var ams := float(Destruct.stat["last_ms"])
		var ag1: float = hub.call("ground", ap.x, ap.z)
		var nb := (fl.get("broken") as Dictionary).size()
		check("擂台台面真碎", aok and int(fl.get("state")) == 1 and ag1 < ag0 - 0.9 and nb > 0,
				"返回 %s · 网格核对 %d（1 = 对上了）· 落脚 %.1f → %.1f · 碎了 %d 格 · %.2f ms" % [aok, fl.get("state"), ag0, ag1, nb, ams])
		# 台心的莲纹（金纹方块跟着收掉）+ Vfx.quake 的入口 + 台沿不碎
		var aok2 := Destruct.blast(ac + Vector3(0.0, 0.3, 0.0), 5.0, 1.0)
		var ams2 := float(Destruct.stat["last_ms"])
		var aq := Vfx.quake(ac + Vector3(-9.0, 0.4, 6.0), 3.2)
		var nb2 := (fl.get("broken") as Dictionary).size()
		var rim_ret := Destruct.blast(ac + Vector3(38.0, 0.3, 0.0), 3.0, 1.0, Vector3.ZERO, {"quiet": true})
		check("擂台：台心 / Vfx.quake / 台沿", aok2 and aq and not rim_ret and (fl.get("broken") as Dictionary).size() == nb2,
				"台心 %s（%.2f ms）· quake %s · 一共碎了 %d 格 · 台沿返回 %s（不碎）" % [aok2, ams2, aq, nb2, rim_ret])
		await wait(0.7)
		await shot("arena_broken")
		fl.call("repair_all")
		await frames(3)
		check("擂台复原", (fl.get("broken") as Dictionary).is_empty() and absf(float(hub.call("ground", ap.x, ap.z)) - ag0) < 0.01,
				"落脚回到 %.1f · 修了 %d 格" % [float(hub.call("ground", ap.x, ap.z)), int((fl.get("stat") as Dictionary)["repaired"])])
		await wait(0.3)
		await shot("arena_repaired")
		# 到点自己复原
		fl.set("repair_t", 1.0)
		Destruct.blast(ap + Vector3(-12.0, 0.0, -10.0), 3.0, 1.0)
		var had := (fl.get("broken") as Dictionary).size()
		await wait(2.4)
		check("擂台到点自己复原", had > 0 and (fl.get("broken") as Dictionary).is_empty(), "碎了 %d 格，%.0f 秒后剩 %d 格" % [had, 1.0, (fl.get("broken") as Dictionary).size()])
		fl.set("repair_t", 30.0)
		cam.set("cine_k", 0.0)
		# 人挪回广场再把对决放开
		player.global_position = hp
		player.velocity = Vector3.ZERO
		await frames(3)
		if duel != null:
			duel.process_mode = Node.PROCESS_MODE_INHERIT

	var arena_ms := float(Destruct.stat["max_ms"])
	Destruct.stat["max_ms"] = 0.0
	say("主城 / 擂台这一段爆破最慢 %.2f ms" % arena_ms)
	# —— 进图 ——
	m.get("level_ui").set("mode", "solo")
	var t0 := Time.get_ticks_msec()
	await m.call("_enter_level", map_id)
	while bool(m.get("_switching")):
		await process_frame
	level = m.get("level")
	if level == null:
		say("FAIL 进不了图 " + map_id)
		quit(1)
		return
	world = level.get("world")
	Destruct.log_on = true
	Destruct.ops.clear()
	var bc := world.dx_box_count()
	say("进图 %s %d ms · 方块登记 %d 个 · 实心格 %s · 保护范围 %d 个 · 载入时摆件 %.0f ms · 模式 %d · 渲染 %s%s" % [map_id,
			Time.get_ticks_msec() - t0, bc.x, world.solid_stats(), world.dx_zones.size(), world.gen_ms, Destruct.mode(),
			RenderingServer.get_current_rendering_method(), " 手机档" if Vfx.lite else ""])
	check("接上了", Destruct.mode() == 1 and Vfx.terrain_hook.is_valid(), "模式 1 = 真破坏，Vfx.terrain_hook 已接")
	var spawn: Vector3 = level.call("spawn_point")
	await settle(1.5)
	var fx := Destruct.fx()

	if OS.get_cmdline_user_args().has("--idle-first"):
		# 什么都还没炸：站着不动量十二段（每段 0.6 秒里最长的一帧），看这会儿机器本身有多挤
		var idle_w: Array = []
		for i in 12:
			var si: Array = await spike(0.6)
			idle_w.append(snappedf(float(si[0]), 0.1))
		say("开炸之前站着不动：十二段各自最长的一帧 %s ms" % [idle_w])

	# —— 1 平地炸坑 ——
	var p1 := find_flat(spawn, 16.0, 120.0)
	check("找到平地", p1 != Vector3.INF, str(p1))
	if p1 != Vector3.INF:
		await put(p1 + Vector3(-9.0, 0.0, 5.0), 0.0)
		await settle()
		await cine(p1 + Vector3(-11.0, 7.0, 9.0), p1 + Vector3(0, -0.5, 0))
		await shot("1_crater_before")
		var h0 := ground(p1)
		var ok1 := Destruct.blast(p1 + Vector3(0, 0.3, 0), 4.5, 1.0)
		var ms1 := float(Destruct.stat["last_ms"])
		var sp1: Array = await spike(1.2)
		var h1 := ground(p1)
		var fl1: float = level.call("floor_at", p1.x, p1.z, h0 + 0.5)
		check("平地炸坑", ok1 and h1 <= h0 - 1.0 and absf(fl1 - h1) < 0.01,
				"高度 %.1f → %.1f · 落脚 %.1f · 爆破 %.2f ms · 之后最长一帧 %.1f ms（%s）· 地块 %.0f ms 后排完 · 碎块 %d" % [h0, h1, fl1, ms1, sp1[0], sp1[2], sp1[1], fx.live])
		await settle(0.6)
		await shot("1_crater_after")
		await wait(0.3)
		var again := Destruct.blast(p1 + Vector3(0, 0.3, 0), 4.5, 1.0)
		check("同处再炸不加深", not again and absf(ground(p1) - h1) < 0.01, "返回 %s · 高度 %.1f" % [again, ground(p1)])
		for i in 6:
			await wait(0.25)
			Destruct.blast(Vector3(p1.x, ground(p1) + 0.3, p1.z), 8.0, 2.0)
		var hmin := ground(p1)
		check("猛炸不低过上限", hmin >= h0 - GridWorld.DX_MAX_DIG - 0.01 and hmin < h1, "原 %.1f → %.1f（上限 %.0f 米）· 最慢一次 %.2f ms" % [h0, hmin,
				GridWorld.DX_MAX_DIG, Destruct.stat["max_ms"]])
		await settle(0.8)
		await shot("1_crater_deep")

	# —— 2 打碎一个小件（石柱 / 石块）——
	var used := {}
	var id2 := find_box(spawn, func(sz: Vector3, xf: Transform3D) -> bool:
		return sz.y >= 2.5 and maxf(sz.x, sz.z) <= 3.5 and minf(sz.x, sz.z) >= 0.8 and xf.basis.y.y > 0.95)
	check("找到小件", id2 >= 0, "方块 %d" % id2)
	if id2 >= 0:
		var xf2: Transform3D = world.call("_bx_xf", id2)
		var sz2: Vector3 = world.call("_bx_size", id2)
		var c2 := xf2.origin
		await put(c2 + Vector3(-8.0, 0.0, 6.0))
		await settle()
		await cine(c2 + Vector3(-9.0, 5.0, 8.0), c2)
		await shot("2_box_before")
		var a0 := world.dx_box_count().y
		var s0 := world.solid_box_at(c2)
		var top0 := world.solid_h(c2.x, c2.z, 1.0e9)
		var ok2 := Destruct.blast(c2, 3.0, 1.0, Vector3(1, 0, 0))
		var ms2 := float(Destruct.stat["last_ms"])
		var sp2: Array = await spike(1.2)
		check("打碎小件", ok2 and s0 and not world.solid_box_at(c2) and world.dx_box_count().y < a0,
				"尺寸 %s · 实心 %s → %s · 顶面 %.1f → %.1f · 还在的方块 %d → %d · 爆破 %.2f ms · 最长一帧 %.1f ms（%s）· %.0f ms 后排完" % [sz2, s0,
				world.solid_box_at(c2), top0, world.solid_h(c2.x, c2.z, 1.0e9), a0, world.dx_box_count().y, ms2, sp2[0], sp2[2], sp2[1]])
		await settle(0.6)
		await shot("2_box_after")

	# —— 3 高速撞墙：撞穿，墙上只开一个洞 ——
	var id3 := find_box(spawn, func(sz: Vector3, xf: Transform3D) -> bool:
		return sz.y >= 3.0 and maxf(sz.x, sz.z) >= 7.0 and minf(sz.x, sz.z) <= 1.8 and minf(sz.x, sz.z) >= 0.4 and xf.basis.y.y > 0.95)
	say("找墙：方块 %d%s" % [id3, "" if id3 >= 0 else "（这张图主角附近没有够长的墙，撞墙这一项跳过）"])
	if id3 >= 0:
		var xf3: Transform3D = world.call("_bx_xf", id3)
		var sz3: Vector3 = world.call("_bx_size", id3)
		var along := xf3.basis.z if sz3.z >= sz3.x else xf3.basis.x
		var nrm := xf3.basis.x if sz3.z >= sz3.x else xf3.basis.z
		var half_len := maxf(sz3.x, sz3.z) * 0.5
		var hit := xf3.origin + Vector3(0, -sz3.y * 0.5 + 1.6, 0)
		var far := hit + along * (half_len - 0.6)
		await put(hit - nrm * 10.0 + along * 4.0)
		await settle()
		await cine(hit - nrm * 11.0 + along * 5.0 + Vector3(0, 4.0, 0), hit)
		await shot("3_wall_before")
		var slow := Destruct.body_crash(hit - nrm * 1.0, nrm * 8.0, 0.6)
		var s_slow := world.solid_box_at(hit)
		var a3 := world.dx_box_count()
		var pierced := Destruct.body_crash(hit - nrm * 1.0, nrm * 42.0, 0.6)
		var ms3 := float(Destruct.stat["last_ms"])
		var sp3: Array = await spike(1.2)
		var lintel := world.solid_box_at(Vector3(hit.x, xf3.origin.y + sz3.y * 0.5 - 0.3, hit.z))
		check("慢速撞不坏", not slow and s_slow, "8 米 / 秒：返回 %s，墙还在 %s" % [slow, s_slow])
		check("高速撞穿墙", pierced and not world.solid_box_at(hit) and (world.solid_box_at(far) or half_len < 4.2),
				"墙 %s · 42 米 / 秒：返回 %s · 撞点实心 %s · 墙那头还实心 %s · 洞上面的门楣 %s（墙高 %.1f）· 方块 %s → %s · 爆破 %.2f ms · 最长一帧 %.1f ms（%s）" % [sz3,
				pierced, world.solid_box_at(hit), world.solid_box_at(far), lintel, sz3.y, a3, world.dx_box_count(), ms3, sp3[0], sp3[2]])
		await settle(0.6)
		await shot("3_wall_after")

	# —— 4 斜着犁一道沟（分帧）——
	var p4 := find_flat(spawn + Vector3(30, 0, -20), 12.0, 140.0, 4.0)
	if p4 == Vector3.INF:
		p4 = find_flat(spawn, 40.0, 200.0, 4.0)
	check("找到犁沟的地方", p4 != Vector3.INF, str(p4))
	if p4 != Vector3.INF:
		var dir4 := Vector3(1, 0, 1).normalized()
		var a4 := p4 + Vector3(0, 0.6, 0)
		var b4 := a4 + dir4 * 34.0
		var hs0: Array = []
		for i in 18:
			var q := a4.lerp(b4, float(i) / 17.0)
			hs0.append(ground(q))
		await put(a4 - dir4 * 7.0 + Vector3(4, 0, -4), 0.0)
		await settle()
		var side := Vector3(dir4.z, 0, -dir4.x)
		await cine(a4 - dir4 * 9.0 + side * 6.0 + Vector3(0, 9.0, 0), a4 + dir4 * 14.0)
		await shot("4_trench_before")
		var tt0 := Time.get_ticks_usec()
		Destruct.trench(a4, b4, 5.0, 1.2)
		var call_ms := float(Time.get_ticks_usec() - tt0) / 1000.0
		var worst4 := 0.0
		var last4 := Time.get_ticks_usec()
		var nfr := 0
		while not fx.jobs.is_empty() and nfr < 600:
			await process_frame
			var now4 := Time.get_ticks_usec()
			worst4 = maxf(worst4, float(now4 - last4) / 1000.0)
			last4 = now4
			nfr += 1
		var lowered := 0
		var counted := 0
		for i in 18:
			var q2 := a4.lerp(b4, float(i) / 17.0)
			if world.dx_protected(q2.x, q2.z):
				continue
			counted += 1
			if ground(q2) <= float(hs0[i]) - 1.0:
				lowered += 1
		check("犁沟", counted > 0 and float(lowered) >= float(counted) * 0.7,
				"34 米、宽 5：沿线 %d / %d 处低了 1 米以上 · 调用当帧 %.2f ms · 分 %d 帧挖完 · 期间最长一帧 %.1f ms" % [lowered, counted, call_ms, nfr, worst4])
		await settle(0.8)
		await shot("4_trench_after")

	# —— 5 坠地砸坑 ——
	var p5 := find_flat(spawn + Vector3(-30, 0, 30), 10.0, 140.0)
	if p5 != Vector3.INF:
		var h5 := ground(p5)
		var r5 := Destruct.body_crash(p5 + Vector3(0, 0.7, 0), Vector3(6, -34, 0), 0.6)
		await frames(2)
		check("坠地砸坑", not r5 and ground(p5) < h5 - 0.9, "返回 %s（没撞穿）· 高度 %.1f → %.1f · %.2f ms" % [r5, h5, ground(p5), Destruct.stat["last_ms"]])

	# —— 6 不可破坏的范围 ——
	var hs := ground(spawn)
	var r6 := Destruct.blast(spawn + Vector3(0, 0.3, 0), 5.0, 1.5)
	check("出生点不坏", absf(ground(spawn) - hs) < 0.01, "返回 %s · 高度 %.1f → %.1f" % [r6, hs, ground(spawn)])
	var krs: Array = level.call("points", "key_room")
	if not krs.is_empty():
		var rm: AABB = (krs[0] as Dictionary)["room"]
		var wp := Vector3(rm.position.x, rm.position.y + 1.5, rm.position.z + rm.size.z * 0.5)
		var a6 := world.dx_box_count().y
		var g6 := ground(wp + Vector3(1.5, 0, 0))
		Destruct.blast(wp, 5.0, 2.0)
		check("钥匙房不坏", world.dx_box_count().y == a6 and absf(ground(wp + Vector3(1.5, 0, 0)) - g6) < 0.01,
				"墙角 %s：方块 %d → %d · 屋里地面 %.1f → %.1f" % [wp, a6, world.dx_box_count().y, g6, ground(wp + Vector3(1.5, 0, 0))])
	var bx: Array = level.call("points", "box")
	if not bx.is_empty():
		var bp: Vector3 = (bx[0] as Dictionary)["pos"]
		var g7 := ground(bp)
		Destruct.blast(bp + Vector3(0, 0.3, 0), 4.0, 1.5)
		check("箱子脚下不坏", absf(ground(bp) - g7) < 0.01, "%.1f → %.1f" % [g7, ground(bp)])

	# —— 7 碎块池不超上限 ——
	var p7 := find_flat(spawn + Vector3(20, 0, 30), 10.0, 160.0)
	if p7 != Vector3.INF:
		await put(p7 + Vector3(-12, 0, 0))
		for i in 16:
			var a := TAU * float(i) / 16.0
			Destruct.blast(p7 + Vector3(cos(a) * 9.0, 0.3, sin(a) * 9.0), 3.0, 1.0)
			await frames(1)
		check("碎块池不超上限", fx.peak <= fx.cap() and fx.live <= fx.cap(), "池子 %d · 最多同时 %d · 现在 %d · 一共放过 %d 块" % [fx.cap(), fx.peak, fx.live, fx.spawned])
		await wait(0.5)
		await cine(p7 + Vector3(-14.0, 9.0, 12.0), p7)
		await shot("7_many")

	# —— 6b 现有招式的入口：Vfx.quake（砸地 / 击飞 / 坠地追击都走它）在新图里出真坑 ——
	var p6 := find_flat(spawn + Vector3(40, 0, 40), 10.0, 160.0)
	if p6 != Vector3.INF:
		var h6 := ground(p6)
		var q6 := Vfx.quake(p6 + Vector3(0, 0.3, 0), 3.2)
		check("Vfx.quake 出真坑", q6 and ground(p6) < h6 - 0.9, "返回 %s · 高度 %.1f → %.1f" % [q6, h6, ground(p6)])

	# —— 6c 连带坍塌：把柱子拦腰打断，坐在柱顶上的小件跟着没 ——
	var pair := find_stack()
	say("找叠着的两件：%s" % [pair])
	if pair.size() == 2:
		var xa: Transform3D = world.call("_bx_xf", int(pair[0]))
		var xb: Transform3D = world.call("_bx_xf", int(pair[1]))
		var bi2: PackedInt32Array = world.get("_bx_i")
		var f0n := int(world.dx_stat["falls"])
		Destruct.blast(xa.origin, 1.2, 1.0, Vector3.ZERO, {"depth_k": 0.3})
		bi2 = world.get("_bx_i")
		check("连带坍塌", (bi2[int(pair[1]) * 5 + 4] & 1) == 0 and int(world.dx_stat["falls"]) > f0n,
				"下面那件 %s 高 %.1f，上面那件在 %s：打断下面的之后上面的还在 = %s · 连带塌了 %d 件" % [xa.origin, (world.call("_bx_size", int(pair[0])) as Vector3).y,
				xb.origin, (bi2[int(pair[1]) * 5 + 4] & 1) != 0, int(world.dx_stat["falls"]) - f0n])

	# —— 6d 楼板 / 屋顶组里的方块（研究所）：打得掉，那栋楼的屋顶网格跟着重传 ——
	var idr := find_roof_box(spawn)
	if idr >= 0:
		var xr: Transform3D = world.call("_bx_xf", idr)
		var szr: Vector3 = world.call("_bx_size", idr)
		await put(Vector3(xr.origin.x - 14.0, 0.0, xr.origin.z + 10.0))
		await settle()
		await cine(xr.origin + Vector3(-13.0, 12.0, 13.0), xr.origin)
		await shot("6_roof_before")
		var sr0 := world.solid_box_at(xr.origin)
		var okr := Destruct.blast(xr.origin, 3.2, 1.0, Vector3.DOWN)
		await frames(4)
		check("打穿楼板 / 屋顶", okr and sr0 and not world.solid_box_at(xr.origin) and (world.get("_dx_roof_dirty") as Dictionary).is_empty(),
				"屋顶组里的方块 %d 尺寸 %s：实心 %s → %s · %.2f ms" % [idr, szr, sr0, world.solid_box_at(xr.origin), Destruct.stat["last_ms"]])
		await wait(0.5)
		await shot("6_roof_after")

	# —— 7b 耗时对照：同一个地方站定（怪 / 模型都载完了），三种情况轮着来、各十段、每段 0.6 秒，记每段里最长的一帧：
	#      不炸 / 只改场景（quiet：炸坑 + 地块重排，不放碎块）/ 带表现。隐藏窗口 + 别的进程同时在跑，单段的数会跳，轮着量、看中位数；
	#      不炸那组的中位数都上了 40 ms = 这会儿机器太挤，这组数不能用（判定只看下面「主线程上属于破坏的开销」那几项）——
	var p9 := find_flat(spawn + Vector3(-20, 0, -30), 10.0, 160.0, 14.0)
	if p9 == Vector3.INF:
		p9 = find_flat(spawn + Vector3(-20, 0, -30), 10.0, 160.0)
	if p9 != Vector3.INF:
		cam.set("cine_k", 0.0)
		await put(p9 + Vector3(-10, 0, 0), -PI * 0.5)
		await settle(3.0)
		var res := {0: [], 1: [], 2: []}
		for i in 10:
			for mode: int in [0, 1, 2]:
				if mode > 0:
					var a9 := TAU * float(i) / 10.0 + float(mode)
					var q9 := p9 + Vector3(cos(a9), 0.0, sin(a9)) * (7.0 if mode == 1 else 14.0)
					q9.y = ground(q9) + 0.3
					Destruct.blast(q9, 4.0, 1.0, Vector3(cos(a9), 0, sin(a9)), {"quiet": mode == 1})
				var s9: Array = await spike(0.6)
				(res[mode] as Array).append(float(s9[0]))
		var med := func(v: Array) -> float:
			var c := v.duplicate()
			c.sort()
			return (float(c[c.size() / 2 - 1]) + float(c[c.size() / 2])) * 0.5
		var m0: float = med.call(res[0])
		var m1: float = med.call(res[1])
		var m2: float = med.call(res[2])
		say("耗时对照（每段 0.6 秒里最长一帧，十段的中位数 / 最大）：不炸 %.1f / %.1f ms · 只改场景 %.1f / %.1f ms · 带表现 %.1f / %.1f ms%s" % [m0, (res[0] as Array).max(),
				m1, (res[1] as Array).max(), m2, (res[2] as Array).max(), "　← 机器太挤，这组数不能用" if m0 > 40.0 else ""])

	# —— 8 重放：另建一个世界，把这一路的操作照做一遍，结果要一模一样 ——
	fx.flush_jobs()
	var w2 := GridWorld.new()
	w2.setup(map_id)
	w2.dx_zones = Destruct.zones_of(level)
	var tr := Time.get_ticks_usec()
	Destruct.replay_on(w2, Destruct.ops)
	var rep_ms := float(Time.get_ticks_usec() - tr) / 1000.0
	var d1: Dictionary = world.get("_dug")
	var d2: Dictionary = w2.get("_dug")
	var diff := 0
	for k: Vector2i in d1:
		if not d2.has(k) or absf(float(d2[k]) - float(d1[k])) > 0.01:
			diff += 1
	for k: Vector2i in d2:
		if not d1.has(k):
			diff += 1
	check("重放一致", diff == 0 and w2.dx_box_count() == world.dx_box_count() and w2.solid_stats() == world.solid_stats(),
			"%d 条操作重放 %.1f ms · 破坏表 %d 格 / %d 格（差 %d）· 方块 %s / %s · 实心记录 %s / %s" % [Destruct.ops.size(), rep_ms, d1.size(), d2.size(), diff,
			world.dx_box_count(), w2.dx_box_count(), world.solid_stats(), w2.solid_stats()])
	w2.free()

	cam.set("cine_k", 0.0)
	say("统计 %s · 世界 %s" % [Destruct.stat, world.dx_stat])
	say("主线程上属于破坏的开销（各自最慢的一次）：爆破 %.2f ms · 被炸的地块落地 %.2f ms（%d 次）· 摆件网格重传 %.2f ms（%d 次）· 碎块模拟 %.2f ms / 帧（池子满 %d 块时）%s" % [
			Destruct.stat["max_ms"], world.dx_stat["apply_ms"], world.dx_stat["apply_n"], world.dx_stat["split_ms"], world.dx_stat["split_n"], fx.sim_ms, fx.peak,
			" · 单线程分帧档" if world.sliced() else ""])
	check("破坏的开销在预算内", float(Destruct.stat["max_ms"]) <= 5.0 and float(world.dx_stat["apply_ms"]) <= 6.0 and float(world.dx_stat["split_ms"]) <= 3.0 and fx.sim_ms <= 4.0,
			"爆破 ≤ 5 · 地块落地 ≤ 6 · 摆件重传 ≤ 3 · 碎块模拟 ≤ 4（毫秒）")
	say("结论：%s（失败 %d 项）" % ["通过" if fails == 0 else "有不通过的", fails])
	m.call("_return_to_hall")
	var tw := 0.0
	while m.get("level") != null and tw < 20.0:
		await process_frame
		tw += 0.016
	await wait(0.8)
	# 回到主城：新图那一套撤了，接回擂台台面（Vfx.terrain_hook 这时是擂台的）
	var back := Destruct.blast(Vector3(-122.0 + 6.0, 3.3, -28.0 - 5.0), 3.0, 1.0, Vector3.ZERO, {"quiet": true})
	check("回主城后撤掉、擂台接回", Destruct.mode() == 3 and back, "模式 %d · 擂台上再炸一处：%s" % [Destruct.mode(), back])
	quit(0 if fails == 0 else 2)
