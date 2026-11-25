extends Node
## 关卡里「方块摆出来的东西有没有碰撞」的自检（2026-11-23，用户：「就算你用方块去做装饰，也要保证地面有碰撞，不穿模」）。
## `-- --qa-solid [--touch]`：以正常游玩模式开机（存档走自检档），单人进木兰草原，先在天南城一带、再到坠魔谷 / 血色禁地，
## 各自从已登记的实心盒子（block_world.gd 的 _scells）里挑：
##   · 台基（比地面高 0.35 ~ 2 米、够宽）：从外面走上去，看人站在顶面上、上台是不是缓坡（改之前 = 陷进去多深）
##   · 高墙 / 殿身 / 石柱（比地面高 3 米以上）：朝它走 2 秒，看停在外面（改之前 = 穿进去）
##   · 屋顶：从上面落下来，看落在顶面上
## 每项都跑两遍：MeadowLevel.solid_off = true（改之前的样子）和 false。最后量 solid_h 的开销。
## main.gd 见到这个参数就 load 这个脚本挂上（网页包里也能跑：探针页的 args 写 ["--","--qa-solid","--touch"]）。
## 截图存 _shots/solid/*.jpg。打印以 [solid] 开头。故意不写 class_name。

const Data := preload("res://scripts/raid_data.gd")

var m: Node            # main.gd
var player: Player
var level: Node3D
var world: Node3D
var out_dir := ""
var keep_clear := false


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://_shots/solid")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().process_frame.connect(_on_frame)
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null and is_instance_valid(player) and player.melee != null and not player.dead:
		player.melee.hp = 100.0      # 测试时不让怪把人打死
	if keep_clear and level != null and is_instance_valid(level):
		clear_mobs()                 # 深处的怪一下就能打死一级的测试角色：这类检查全程清怪


func say(s: String) -> void:
	print("[solid] " + s)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	if img.get_width() > 1100:
		img.resize(1100, int(1100.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out_dir.path_join(name + ".jpg"), 0.86)
	say("shot " + name)


func clear_mobs() -> void:
	var raid: Variant = level.get("raid")
	if raid == null:
		return
	for g: String in ["swordsmen", "air_foes"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n != player and n.get("net") == null:
				n.queue_free()


func put(pos: Vector3) -> void:
	player.force_ground()
	player.global_position = pos
	player.velocity = Vector3.ZERO


## 主角周围 r 米内登记着的实心盒子：[中心, 半轴 a（世界向量）, 半轴 b, 底, 顶, 那里的地形高度]
func boxes(r: float) -> Array:
	var out: Array = []
	var seen := {}
	var p := player.global_position
	var cells: Dictionary = world.get("_scells")
	for k: Vector2i in cells:
		if Vector2((float(k.x) + 0.5) * 4.0 - p.x, (float(k.y) + 0.5) * 4.0 - p.z).length() > r:
			continue
		for s: PackedFloat32Array in (cells[k] as Dictionary).values():
			var i := 0
			while i < s.size():
				var id := "%.2f,%.2f,%.2f,%.2f" % [s[i], s[i + 1], s[i + 6], s[i + 7]]
				if not seen.has(id):
					seen[id] = true
					var u := Vector2(s[i + 2], s[i + 3])
					var w := Vector2(s[i + 4], s[i + 5])
					out.append([Vector2(s[i], s[i + 1]), u / u.length_squared(), w / w.length_squared(), s[i + 6], s[i + 7],
							float(world.call("height", s[i], s[i + 1]))])
				i += 8
	return out


func inside(b: Array, x: float, z: float, grow := 0.0) -> bool:
	var d := Vector2(x, z) - (b[0] as Vector2)
	var a: Vector2 = b[1]
	var c: Vector2 = b[2]
	return absf(d.dot(a.normalized())) <= a.length() + grow and absf(d.dot(c.normalized())) <= c.length() + grow


## 朝 to 走 sec 秒（镜头转过去、按住前进）。每个物理帧记：最低陷进 box 顶面多少、单帧最大抬升
func walk(to: Vector2, sec: float, b: Array) -> Dictionary:
	var cam: Node = m.get("cam")
	var d := to - Vector2(player.global_position.x, player.global_position.z)
	cam.call("snap", atan2(-d.x, -d.y), -0.25, 7.0)
	await wait(0.25)
	Input.action_press("move_forward")
	var sink := 0.0
	var jump := 0.0
	var in_n := 0
	var last_y := player.global_position.y
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().physics_frame
		var q := player.global_position
		jump = maxf(jump, q.y - last_y)
		last_y = q.y
		if inside(b, q.x, q.z, -0.15):
			in_n += 1
			sink = maxf(sink, float(b[4]) - q.y)
	Input.action_release("move_forward")
	await wait(0.2)
	return {"sink": sink, "jump": jump, "in": in_n}


func test_area(label: String, shots: bool) -> void:
	var st: Vector2i = world.call("solid_stats")
	var bs := boxes(90.0)
	say("%s：主角在 %s，登记着 %d 个格子 / %d 条盒子记录；90 米内不重复的盒子 %d 个" % [label, str(player.global_position.round()), st.x, st.y, bs.size()])
	var plinths: Array = []
	var walls: Array = []
	for b: Array in bs:
		var up := float(b[4]) - float(b[5])
		var ha := (b[1] as Vector2).length()
		var hb := (b[2] as Vector2).length()
		if up >= 0.35 and up <= 2.0 and ha >= 1.2 and hb >= 1.2 and float(b[3]) <= float(b[5]) + 0.3:
			plinths.append(b)
		elif up >= 3.0 and ha >= 0.6 and hb >= 0.6 and float(b[3]) <= float(b[5]) + 0.6:
			walls.append(b)
	say("%s：其中台基一类 %d 个、高墙 / 殿身一类 %d 个" % [label, plinths.size(), walls.size()])
	var lv := level
	# —— 台基：从外面走上去 ——
	var n := 0
	for b: Array in plinths:
		if n >= 5:
			break
		var c: Vector2 = b[0]
		var a: Vector2 = b[1]
		var start := c + a.normalized() * (a.length() + 2.6)
		var hs := float(world.call("height", start.x, start.y))
		if absf(hs - float(b[5])) > 0.6 or float(world.call("solid_h", start.x, start.y, hs + 1.6)) > hs + 0.2:
			continue      # 起步的地方不平 / 有别的东西挡着：换一个
		n += 1
		var res: Array = []
		for off: bool in [true, false]:
			lv.set("solid_off", off)
			clear_mobs()
			put(Vector3(start.x, hs + 0.1, start.y))
			await wait(0.4)
			var r: Dictionary = await walk(c - a.normalized() * (a.length() - 0.7), (a.length() + 2.2) / 5.0 + 0.5, b)
			res.append(r)
			if shots and n == 1:
				var cam: Node = m.get("cam")
				var side := (b[2] as Vector2).normalized()
				var q := player.global_position
				cam.set("cine_xf", Transform3D(Basis.looking_at(Vector3(-side.x, -0.35, -side.y), Vector3.UP), q + Vector3(side.x * 6.0, 2.6, side.y * 6.0)))
				cam.set("cine_fov", 55.0)
				cam.set("cine_k", 1.0)
				await wait(0.4)
				await shot("%s_台基_%s" % [label, "改前" if off else "改后"])
				cam.set("cine_k", 0.0)
		say("%s 台基 #%d（比地面高 %.2f 米，%.1f × %.1f 米）：改前 陷进去最深 %.2f 米（在它上面 %d 帧）；改后 最深 %.2f 米（%d 帧），上台时单帧最多抬 %.2f 米，停在 %.2f（顶面 %.2f）" % [
				label, n, float(b[4]) - float(b[5]), a.length() * 2.0, (b[2] as Vector2).length() * 2.0, float(res[0]["sink"]), int(res[0]["in"]),
				float(res[1]["sink"]), int(res[1]["in"]), float(res[1]["jump"]), player.global_position.y, float(b[4])])
	# —— 高墙 / 殿身：朝它走 ——
	n = 0
	for b: Array in walls:
		if n >= 5:
			break
		var c: Vector2 = b[0]
		var a: Vector2 = b[1]
		var start := c + a.normalized() * (a.length() + 3.0)
		var hs := float(world.call("height", start.x, start.y))
		if absf(hs - float(b[5])) > 1.2 or float(world.call("solid_h", start.x, start.y, hs + 1.6)) > hs + 0.2:
			continue
		n += 1
		var got: Array = []
		for off: bool in [true, false]:
			lv.set("solid_off", off)
			clear_mobs()
			put(Vector3(start.x, hs + 0.1, start.y))
			await wait(0.4)
			var r: Dictionary = await walk(c, 2.0, b)
			var q := player.global_position
			got.append([int(r["in"]), inside(b, q.x, q.z, -0.05), q.y - hs])
		say("%s 高墙 #%d（高出地面 %.1f 米，%.1f × %.1f 米）：改前 走进它里面 %d 帧、停下时在里面=%s；改后 走进去 %d 帧、停下时在里面=%s（人的高度变化 %.2f 米）" % [
				label, n, float(b[4]) - float(b[5]), a.length() * 2.0, (b[2] as Vector2).length() * 2.0, int(got[0][0]), bool(got[0][1]), int(got[1][0]), bool(got[1][1]), float(got[1][2])])
	# —— 从上面落到最高的那个盒子上 ——
	lv.set("solid_off", false)
	n = 0
	for b: Array in walls:
		if n >= 3:
			break
		var c: Vector2 = b[0]
		var top := float(world.call("solid_h", c.x, c.y, 1.0e9))
		if top < float(b[4]) - 0.01:
			continue
		n += 1
		put(Vector3(c.x, top + 4.0, c.y))
		await wait(2.2)
		say("%s 屋顶 #%d：从顶面上方 4 米落下，停在 %.2f（顶面 %.2f，地面 %.2f）" % [label, n, player.global_position.y, top, float(b[5])])


# ---------- 2026-11-24 逐面检查（`--audit`）：画出来的每个朝上的面，底下有没有落脚 ----------
## 用户又发来一张坠魔谷的截图（人陷在紫色的方块里半截）：「坠魔谷的关卡，地面上的地形还是会出现穿模的情况」。
## 这里不挑样本，把主角周围 r 米内所有地块网格里朝上的面逐个过一遍：
##   · 地形的格子面（两米见方、贴着格线）：高度和 world.height() 对不对得上（对不上 = 网格和高度表不同步）
##   · 点缀物的顶面：它那个高度上有没有登记实心盒子（没有 = 人会陷进去 / 穿过去），按颜色 + 大小归组，看是哪一类东西
## 返回 {terr_bad, soft_n, worst: Vector3}

func audit(label: String, r: float, verbose := true) -> Dictionary:
	var chunks: Dictionary = world.get("_chunks")
	var p := player.global_position
	var terr_n := 0
	var terr_bad := 0
	var terr_worst := 0.0
	var terr_at := Vector3.ZERO
	var coarse_n := 0
	var coarse_bad := 0
	var coarse_worst := 0.0
	var prop_n := 0
	var groups := {}
	var worst := Vector3.ZERO
	var worst_gap := 0.0
	var liq_n: Array[int] = [0, 0, 0, 0, 0]
	var liq_sink: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for key: Vector2i in chunks:
		var e: Dictionary = chunks[key]
		var mi := e["node"] as MeshInstance3D
		var lod := int(e["lod"])
		if Vector2((float(key.x) + 0.5) * 96.0 - p.x, (float(key.y) + 0.5) * 96.0 - p.z).length() > r + 70.0:
			continue
		var off := mi.position
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cl: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var cs := 2.0 if lod == 0 else 6.0
		for q in v.size() / 4:
			var b := q * 4
			if nr[b].y < 0.95:
				continue
			var x0 := minf(minf(v[b].x, v[b + 1].x), minf(v[b + 2].x, v[b + 3].x))
			var x1 := maxf(maxf(v[b].x, v[b + 1].x), maxf(v[b + 2].x, v[b + 3].x))
			var z0 := minf(minf(v[b].z, v[b + 1].z), minf(v[b + 2].z, v[b + 3].z))
			var z1 := maxf(maxf(v[b].z, v[b + 1].z), maxf(v[b + 2].z, v[b + 3].z))
			var c := Vector3((x0 + x1) * 0.5 + off.x, v[b].y, (z0 + z1) * 0.5 + off.z)
			if Vector2(c.x - p.x, c.z - p.z).length() > r:
				continue
			var h := float(world.call("height", c.x, c.z))
			var fx := fposmod(x0, cs)
			var fz := fposmod(z0, cs)
			var grid := absf(x1 - x0 - cs) < 0.01 and absf(z1 - z0 - cs) < 0.01 and minf(fx, cs - fx) < 0.01 and minf(fz, cs - fz) < 0.01 \
					and absf(v[b + 2].y - v[b].y) < 0.001
			if grid:
				var diff := c.y - h
				if cl[b].a > 0.0 and lod == 0 and float(world.call("_shaped", c.x, c.z)) < 0.0:
					# 低处填的那层（海水 / 溪河 / 血河 / 云海 / 魔雾）：按区域记人会陷进去多深
					var lri := int(world.call("_region", c.x, c.z, float(world.call("_hash", int(floorf(c.x / 2.0)) * 3 + 1, int(floorf(c.z / 2.0)) * 3 + 2))))
					liq_n[lri] += 1
					liq_sink[lri] = maxf(liq_sink[lri], diff)
					continue
				if lod != 0:
					coarse_n += 1
					if absf(diff) > 0.55:
						coarse_bad += 1
						coarse_worst = maxf(coarse_worst, absf(diff))
					continue
				terr_n += 1
				if absf(diff) > 0.05:
					terr_bad += 1
					if absf(diff) > absf(terr_worst):
						terr_worst = diff
						terr_at = c
				continue
			if lod != 0:
				continue
			var dx := x1 - x0
			var dz := z1 - z0
			if maxf(dx, dz) < 0.6 or minf(dx, dz) < 0.3 or c.y <= h + 0.25:
				continue
			prop_n += 1
			var s := float(world.call("solid_h", c.x, c.z, c.y + 0.01))
			if s >= c.y - 0.25:
				continue
			var gap := c.y - maxf(h, s)
			var col := cl[b]
			var gk := "%s｜颜色 %.1f %.1f %.1f｜%.1f × %.1f 米" % ["陷得进去（高出落脚 2.25 米以内）" if gap <= 2.25 else "高处（墙 / 树冠 / 悬空）", snappedf(col.r, 0.1), snappedf(col.g, 0.1), snappedf(col.b, 0.1),
					snappedf(dx, 0.5), snappedf(dz, 0.5)]
			var g: Array = groups.get(gk, [0, 1.0e9, 0.0, c])
			g[0] = int(g[0]) + 1
			g[1] = minf(float(g[1]), gap)
			g[2] = maxf(float(g[2]), gap)
			groups[gk] = g
			if gap <= 2.25 and dx * dz > 1.0 and gap > worst_gap:
				worst_gap = gap
				worst = c
	var soft_n := 0
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b2: String) -> bool: return int((groups[a] as Array)[0]) > int((groups[b2] as Array)[0]))
	for gk: String in keys:
		if gk.begins_with("陷"):
			soft_n += int((groups[gk] as Array)[0])
	say("%s 逐面检查（%d 米内）：地形格子面 %d 个，和高度表对不上的 %d 个（最大差 %.2f 米，在 %s）；粗地块的格子面 %d 个、差半米以上 %d 个（最大 %.1f 米）；点缀物顶面 %d 个，其中没落脚、陷得进去的 %d 个" % [
			label, int(r), terr_n, terr_bad, terr_worst, str(terr_at.round()), coarse_n, coarse_bad, coarse_worst, prop_n, soft_n])
	for lri in 5:
		if liq_n[lri] > 0:
			say("    低处填的那层 · %s：%d 个面，画出来的顶面比落脚高 %.2f 米" % [str(Data.REGIONS[lri]["name"]), liq_n[lri], liq_sink[lri]])
	if verbose:
		var shown := 0
		for gk: String in keys:
			if shown >= 28:
				break
			var g: Array = groups[gk]
			if not gk.begins_with("陷") and shown > 20:
				continue
			shown += 1
			say("    %4d 个  %s  高出落脚 %.2f ~ %.2f 米  例：%s" % [int(g[0]), gk, float(g[1]), float(g[2]), str((g[3] as Vector3).snappedf(0.1))])
	return {"terr_bad": terr_bad, "soft_n": soft_n, "worst": worst, "worst_gap": worst_gap, "liq_sink": liq_sink, "liq_n": liq_n}


## (x, z) 这一点上，画出来的朝上的面里不高于 ymax 的最高的那个（只看所在的那一块地）
func visual_top(x: float, z: float, ymax: float) -> float:
	var best := -1.0e9
	if not is_instance_valid(world):
		return best
	var chunks: Dictionary = world.get("_chunks")
	var key := Vector2i(int(floorf(x / 96.0)), int(floorf(z / 96.0)))
	if not chunks.has(key):
		return best
	var mi := (chunks[key] as Dictionary)["node"] as MeshInstance3D
	if not is_instance_valid(mi) or mi.mesh == null:
		return best
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var lx := x - mi.position.x
	var lz := z - mi.position.z
	for q in v.size() / 4:
		var b := q * 4
		if nr[b].y < 0.95 or v[b].y > ymax or v[b].y <= best:
			continue
		if lx < minf(minf(v[b].x, v[b + 1].x), minf(v[b + 2].x, v[b + 3].x)) or lx > maxf(maxf(v[b].x, v[b + 1].x), maxf(v[b + 2].x, v[b + 3].x)):
			continue
		if lz < minf(minf(v[b].z, v[b + 1].z), minf(v[b + 2].z, v[b + 3].z)) or lz > maxf(maxf(v[b].z, v[b + 1].z), maxf(v[b + 2].z, v[b + 3].z)):
			continue
		best = v[b].y
	return best


func settle(sec := 30.0) -> float:
	var t0 := Time.get_ticks_msec()
	await wait(0.6)
	await wait_until(func() -> bool:
		return not is_instance_valid(world) or (bool(world.call("ready_near", player.global_position)) and int(world.call("rebuilding")) == 0 and not bool(world.call("busy"))), sec)
	if not is_instance_valid(world):
		say("关卡没了（主角陨落 / 被传走）：停")
		if not OS.has_feature("web"):
			get_tree().quit()
		await wait(1.0e6)
	await wait(0.5)
	return float(Time.get_ticks_msec() - t0) / 1000.0


func look_at_spot(c: Vector3, name: String) -> void:
	var cam: Node = m.get("cam")
	# 八个方向里挑一个没被地形挡住视线的
	var off := Vector3(4.2, 3.4, 4.2)
	for d in 8:
		var a := float(d) * PI * 0.25 + 0.4
		var o := Vector3(cos(a) * 5.6, 3.4, sin(a) * 5.6)
		var clear := true
		for i in range(1, 9):
			var q := c + o * (float(i) / 8.0)
			if float(world.call("height", q.x, q.z)) > q.y - 0.4:
				clear = false
		if clear:
			off = o
			break
	cam.set("cine_xf", Transform3D(Basis.looking_at((Vector3(0.0, 0.5, 0.0) - off).normalized(), Vector3.UP), c + off))
	cam.set("cine_fov", 55.0)
	cam.set("cine_k", 1.0)
	await wait(0.5)
	await shot(name)
	cam.set("cine_k", 0.0)


func _run_audit() -> void:
	keep_clear = true
	var prog: GDScript = load("res://scripts/progression.gd")
	player.set_realm(Realm.count() - 1, false)
	# 坠魔谷里按深度挑几处
	var cand: Array = []
	for k in 72 * 30:
		var ang := TAU * float(k % 72) / 72.0
		var rr := 480.0 + 40.0 * float(k / 72)
		var q := Vector2(cos(ang), sin(ang)) * rr
		if Data.region_at(q.x, q.y) == 4 and float(world.call("height", q.x, q.y)) > 2.0:
			cand.append([float(prog.call("depth_at", 4, q.x, q.y)), q])
	say("坠魔谷候选点 %d 个" % cand.size())
	var spots: Array = []
	for want: float in [0.68, 0.3, 0.5, 0.85, 0.68, 0.95]:
		var best: Array = []
		for c: Array in cand:
			var far := true
			for s: Array in spots:
				if (s[1] as Vector2).distance_to(c[1]) < 150.0:
					far = false
			if far and (best.is_empty() or absf(float(c[0]) - want) < absf(float(best[0]) - want)):
				best = c
		if not best.is_empty():
			spots.append(best)
	var total_soft := 0
	var total_terr := 0
	var first := true
	for s: Array in ([] if OS.get_cmdline_user_args().has("--dyn") else spots):
		var q: Vector2 = s[1]
		clear_mobs()
		put(Vector3(q.x, float(world.call("height", q.x, q.y)) + 0.2, q.y))
		var t := await settle()
		var label := "坠魔谷 深度 %d%%" % roundi(float(s[0]) * 100.0)
		say("%s：%s，地块 %.1f 秒备齐" % [label, str(player.global_position.round()), t])
		var res: Dictionary = audit(label, 110.0, true)
		total_soft += int(res["soft_n"])
		total_terr += int(res["terr_bad"])
		if float(res["worst_gap"]) > 0.3 and first:
			first = false
			var w: Vector3 = res["worst"]
			put(Vector3(w.x, float(world.call("height", w.x, w.z)) + 0.1, w.z))
			await wait(0.8)
			say("  站到最深的那个上面：人在 %.2f，画出来的顶面 %.2f，地形 %.2f" % [player.global_position.y, w.y, float(world.call("height", w.x, w.z))])
			await look_at_spot(player.global_position, "坠魔谷_陷得最深的一处")
	say("静态合计：地形对不上 %d 个面，点缀物陷得进去 %d 个面" % [total_terr, total_soft])
	# —— 斗法炸坑之后：网格跟不跟得上高度表 ——
	var q0: Vector2 = spots[0][1]
	put(Vector3(q0.x, float(world.call("height", q0.x, q0.y)) + 0.2, q0.y))
	await settle()
	var worst_lag := 0.0
	var lag_n := 0
	for round_i in 6:
		var t0 := Time.get_ticks_msec()
		var pp := player.global_position
		for i in 5:
			var a := float(round_i * 5 + i) * 1.9
			pp = player.global_position
			var bp := Vector3(pp.x + cos(a) * (1.0 + float(i) * 1.5), 0.0, pp.z + sin(a) * (1.0 + float(i) * 1.5))
			bp.y = float(world.call("height", bp.x, bp.z)) + 0.3
			level.call("terrain_blast", bp, 3.5)
			await wait(0.12)
		# 每帧看脚下：画出来的顶面比人高多少、高了多久
		var sunk_t := 0.0
		var sunk_max := 0.0
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 2500:
			await get_tree().physics_frame
			var q := player.global_position
			var vt := visual_top(q.x, q.z, q.y + 14.0)
			if vt - q.y > 0.3:
				sunk_t += 1.0 / 60.0
				sunk_max = maxf(sunk_max, vt - q.y)
		await settle()
		worst_lag = maxf(worst_lag, sunk_t)
		if sunk_t > 0.0:
			lag_n += 1
		say("炸坑 第 %d 轮：累计炸了 %d 格；这一轮里脚下的画面比人高（> 0.3 米）共 %.2f 秒、最多高 %.2f 米；到重建完 %.1f 秒" % [
				round_i + 1, int(level.get("dug_total")), sunk_t, sunk_max, float(Time.get_ticks_msec() - t0) / 1000.0])
	var res2: Dictionary = audit("炸坑之后", 60.0, false)
	say("炸坑之后：地形对不上 %d 个面；六轮里有 %d 轮脚下短暂陷进画面，最长 %.2f 秒" % [int(res2["terr_bad"]), lag_n, worst_lag])
	# —— 破山（world.dig）之后 ——
	for i in 4:
		var pp := player.global_position
		world.call("dig", pp + Vector3(8.0 + float(i) * 5.0, 0.0, 3.0), 4.0, pp.y - 3.0)
		await wait(0.1)
	await settle()
	var res3: Dictionary = audit("破山之后", 60.0, false)
	say("破山之后：地形对不上 %d 个面" % int(res3["terr_bad"]))
	# —— 快速赶路之后落地：脚下还是粗地块的那段时间 ——
	for trial in 3:
		var dir := Vector2(cos(float(trial) * 2.1 + 0.4), sin(float(trial) * 2.1 + 0.4))
		var start := Vector2(player.global_position.x, player.global_position.z)
		var spd := 95.0
		var t0 := Time.get_ticks_msec()
		var at := start
		while Time.get_ticks_msec() - t0 < 4500:
			await get_tree().process_frame
			at = start + dir * spd * float(Time.get_ticks_msec() - t0) / 1000.0
			player.global_position = Vector3(at.x, float(world.call("height", at.x, at.y)) + 40.0, at.y)
			player.velocity = Vector3.ZERO
		var gy := float(world.call("height", at.x, at.y))
		put(Vector3(at.x, gy + 0.1, at.y))
		var t1 := Time.get_ticks_msec()
		var coarse_t := 0.0
		var off_max := 0.0
		var none_t := 0.0
		while Time.get_ticks_msec() - t1 < 6000:
			await get_tree().physics_frame
			var q := player.global_position
			var ck: Variant = (world.get("_chunks") as Dictionary).get(Vector2i(int(floorf(q.x / 96.0)), int(floorf(q.z / 96.0))))
			if ck == null:
				none_t += 1.0 / 60.0
			elif int((ck as Dictionary)["lod"]) != 0:
				coarse_t += 1.0 / 60.0
				var vt := visual_top(q.x, q.z, 1.0e9)
				off_max = maxf(off_max, absf(vt - q.y))
			else:
				break
		say("赶路 #%d（每秒 %d 米飞 4.5 秒后落地，区域 %d）：脚下没有真地形 %.2f 秒、是粗地块 %.2f 秒（那时画面和落脚差最多 %.1f 米）" % [
				trial + 1, int(spd), Data.region_at(at.x, at.y), none_t, coarse_t, off_max])
		await settle()
	say("完成")
	if not OS.has_feature("web"):
		get_tree().quit()


## `--cloud [--far=3]`：某个区域低处填的那层（坠魔谷的魔雾 / 云梦山的云海）上走一走——人陷进画出来的方块里多深
func _run_cloud() -> void:
	keep_clear = true
	var ri := 4
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--cloud-ri="):
			ri = int(a.get_slice("=", 1))
	var rname := str(Data.REGIONS[ri]["name"])
	var spots: Array = []
	for k in 72 * 30:
		var ang := TAU * float(k % 72) / 72.0
		var rr := 660.0 + 40.0 * float(k / 72)
		var q := Vector2(cos(ang), sin(ang)) * rr
		if Data.region_at(q.x, q.y) != ri:
			continue
		var all := true
		for o: Vector2 in [Vector2.ZERO, Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10), Vector2(18, 0), Vector2(0, 18)]:
			if float(world.call("_shaped", q.x + o.x, q.y + o.y)) > -1.0 or Data.region_at(q.x + o.x, q.y + o.y) != ri:
				all = false
		var far := true
		for s: Vector2 in spots:
			if s.distance_to(q) < 200.0:
				far = false
		if all and far:
			spots.append(q)
		if spots.size() >= 3:
			break
	say("%s 谷底 / 云海上找到 %d 处" % [rname, spots.size()])
	var n := 0
	var bw: GDScript = load("res://scripts/block_world.gd")
	for q: Vector2 in spots:
		n += 1
		if n > 1 and OS.get_cmdline_user_args().has("--quick"):
			break
		for old: bool in [true, false]:
			bw.set("liquid_old", old)
			var tag := "改前" if old else "改后"
			clear_mobs()
			put(Vector3(q.x, float(world.call("height", q.x, q.y)) + 0.3, q.y))
			await settle()
			var p := player.global_position
			if OS.has_feature("web"):
				# 网页端读不回网格（一读就崩）：直接问生成网格用的那个函数这一格顶面多高
				var ct: Array = world.call("_cell", int(floorf(p.x / 2.0)), int(floorf(p.z / 2.0)), 2.0, world.get("_dug"))
				say("%s #%d %s：人站在 %.2f，这一格画出来的顶面 %.2f（陷进去 %.2f 米）" % [rname, n, tag, p.y, float(ct[0]), float(ct[0]) - p.y])
			else:
				say("%s #%d %s：人站在 %.2f，脚下画出来的顶面 %.2f（陷进去 %.2f 米）" % [rname, n, tag, p.y, visual_top(p.x, p.z, 1.0e9), visual_top(p.x, p.z, 1.0e9) - p.y])
				audit("%s #%d %s" % [rname, n, tag], 60.0, false)
			if n == 1:
				await look_at_spot(player.global_position, "%s_谷底_%s" % [rname, tag])
			if OS.get_cmdline_user_args().has("--quick"):
				continue
			# 朝四个方向各走 2.5 秒：每 0.1 秒量一次陷进去多深（每帧都量会把帧率拖垮）
			var sink := 0.0
			var sum := 0.0
			var cnt := 0
			var cam: Node = m.get("cam")
			for d in 4:
				clear_mobs()
				cam.call("snap", float(d) * PI * 0.5 + 0.3, -0.25, 7.0)
				await wait(0.2)
				Input.action_press("move_forward")
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 2500:
					await wait(0.1)
					if not is_instance_valid(world):
						say("关卡没了（被传走 / 结算了）：停")
						get_tree().quit()
						return
					var w := player.global_position
					var sk := visual_top(w.x, w.z, w.y + 1.4) - w.y
					sink = maxf(sink, sk)
					sum += maxf(sk, 0.0)
					cnt += 1
				Input.action_release("move_forward")
				await wait(0.2)
			say("%s #%d %s 走四个方向共 10 秒：陷进画面最深 %.2f 米，平均 %.2f 米" % [rname, n, tag, sink, sum / float(maxi(cnt, 1))])
	bw.set("liquid_old", false)
	say("完成")
	if not OS.has_feature("web"):
		get_tree().quit()


func _run() -> void:
	var ok: bool = await wait_until(func() -> bool:
		var h: Variant = m.get("hub")
		return h != null and bool(h.get("active")) and (m.get("player") as Node).process_mode != Node.PROCESS_MODE_DISABLED, 240.0)
	say("开机到主城 %s｜渲染器 %s" % ["成功" if ok else "超时", RenderingServer.get_current_rendering_method()])
	await wait(1.5)
	player = m.get("player") as Player
	m.call("_open_level_select")
	await wait(0.8)
	(m.get("level_ui") as Node).call("pick", 0, true)
	await wait_until(func() -> bool:
		return m.get("level") != null and (m.get("player") as Node).process_mode != Node.PROCESS_MODE_DISABLED and float((m.get("level_ui") as Node).get("_fade").color.a) < 0.05, 240.0)
	level = m.get("level") as Node3D
	world = level.get("world") as Node3D
	await wait(3.0)
	if OS.get_cmdline_user_args().has("--cloud"):
		await _run_cloud()
		return
	if OS.get_cmdline_user_args().has("--audit"):
		await _run_audit()
		return
	# 一、天南城（草原中心）
	put(Vector3(8.0, float(world.call("height", 8.0, 30.0)) + 0.2, 30.0))
	await wait(6.0)
	await test_area("天南城", true)
	# 二、坠魔谷：沿各个方向往外找第一处属于坠魔谷（区域 4）、附近有建筑的地方
	var found := false
	for ri: int in [4, 2]:
		var spot := Vector2.ZERO
		for k in 720:
			var ang := TAU * float(k % 72) / 72.0
			var rr := 520.0 + 60.0 * float(k / 72)
			var q := Vector2(cos(ang), sin(ang)) * rr
			if Data.region_at(q.x, q.y) == ri and float(world.call("height", q.x, q.y)) > 2.0:
				spot = q
				break
		if spot == Vector2.ZERO:
			say("没找到区域 %d" % ri)
			continue
		# 在那一带挪几处，找盒子多的地方
		var best := spot
		var best_n := -1
		for step in 6:
			var q2 := spot + Vector2(cos(float(step) * 1.05), sin(float(step) * 1.05)) * (90.0 * float(step > 0))
			if Data.region_at(q2.x, q2.y) != ri:
				continue
			put(Vector3(q2.x, float(world.call("height", q2.x, q2.y)) + 0.2, q2.y))
			await wait(5.0)
			var nb := boxes(90.0).size()
			if nb > best_n:
				best_n = nb
				best = q2
		put(Vector3(best.x, float(world.call("height", best.x, best.y)) + 0.2, best.y))
		await wait(5.0)
		await test_area(str(Data.REGIONS[ri]["name"]), ri == 4)
		found = true
	# 三、开销：在盒子最多的地方问一万次
	var p := player.global_position
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 10000:
		acc += float(world.call("solid_h", p.x + float(i % 40) * 0.5 - 10.0, p.z + float(i / 40 % 40) * 0.5 - 10.0, p.y + 1.6))
	var us := float(Time.get_ticks_usec() - t0) / 10000.0
	say("solid_h 问一万次：每次 %.2f 微秒（走路时每个物理帧问二十来次 ≈ %.3f 毫秒）%s" % [us, us * 22.0 / 1000.0, "" if found else "（没到坠魔谷）"])
	say("完成")
	if not OS.has_feature("web"):
		get_tree().quit()
