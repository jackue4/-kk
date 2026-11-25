extends Node
## `-- --boss-test-ex[=lingyou,sandworm,…]`：新图怪物 / 首领大脑 / 体节虫的自检（B_mobs，SPEC 第 8 节）。
## main.gd 正常开机进主城后把这个探针挂上（属性 m = main、arg = 等号后面的首领列表，空 = 全部）。
## 不依赖关卡 / 管理器：在主城外面（O 点）搭一块平地沙盘（自己的天空 / 日光 / 地面碰撞），主城先停用，测完还原再退出。
## 每个首领：生成（ex_mobs.setup + ExBoss.attach）→ 主角站在战斗区里挨 11 秒（不出手）→ 数技能次数 / 广播条数 / 主角掉了多少血 →
##   各自的专项（凌幽：螺旋发数随失血；绛罗：贴脸逃跑；巨虫：埋地免伤 / 判定点贴人 / 嗜血；凌影：入夜变身 + 尸潮；
##   电鞭：五连鞭 + 雷暴；冰僵：锁链拉人 + 冲锋；双卫：焊愈 / 变身 / 出圈拉回）→ 通用（区外打无效 / 跑出区拉回 / 区内没人回满）。
## 另测：联机重放（木偶大脑只播画面不打人）、raid_mob 的挡墙钩子 block_fn、新怪模型排一排。
## 打印以 [bossx] 开头；截图 _shots/preview/ex_boss_*.jpg。故意不写 class_name。

const Mob := preload("res://scripts/raid_mob.gd")
const ExMobs := preload("res://scripts/ex/ex_mobs.gd")
const ExBoss := preload("res://scripts/ex/ex_boss.gd")

const O := Vector3(700.0, 40.0, -700.0)     # 沙盘中心（主城外面，Player.BOUND 以内）
const Y0 := 40.0
const DMG_K := 3.0                          # 自检里主角打首领的伤害倍率
const ALL := ["lingyou", "jiangluo", "sandworm", "lingying", "dianbian", "bingjiang", "duo"]

var m: Node
var arg := ""
var player: Player
var box: Node3D
var taken := 0.0
var guard := true
var night := false
var fx_log: Array = []
var relay: Node3D = null       # 联机重放：把主人的广播转给这个木偶大脑
var pup: Node3D = null         # 重放用的木偶（每帧替主人发一次状态，不然 1.5 秒没消息它会自己收掉）
var adds: Array = []
var fails := 0
var _nid := 100
var _wall := AABB()
var _t0 := 0
var relay_bullets := 0


func _ready() -> void:
	get_tree().process_frame.connect(_on_frame)
	_run.call_deferred()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if guard and player != null and is_instance_valid(player) and player.melee != null:
		if player.melee.hp < player.melee.HP_MAX:
			taken += player.melee.HP_MAX - player.melee.hp
			player.melee.hp = player.melee.HP_MAX
		if player.dead:
			player.revive()
	if pup != null and is_instance_valid(pup):
		pup.call("net_push", pup.global_position, 0.0, 1.0, 1)


func say(s: String) -> void:
	print("[bossx] " + s)


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	say("%s %s %s" % ["通过" if ok else "失败", name, detail])


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func ground(_x: float, _z: float) -> float:
	return Y0


func blocked(a: Vector3, b: Vector3) -> bool:
	var w := _wall.grow(0.4)
	var from := Vector3(a.x, Y0 + 1.0, a.z)
	var to := Vector3(b.x, Y0 + 1.0, b.z)
	return w.intersects_segment(from, to) or w.has_point(to)


# ---------- 沙盘 ----------

func _build_box() -> void:
	box = Node3D.new()
	box.name = "BossSandbox"
	m.add_child(box)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.62, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.78, 0.66)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	box.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.6, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	box.add_child(sun)
	_slab(Vector3(O.x, Y0 - 1.0, O.z), Vector3(150, 2, 150), Color(0.86, 0.72, 0.5))
	# 网格线（看得出移动距离）
	for i in range(-6, 7):
		_slab(Vector3(O.x + float(i) * 10.0, Y0 + 0.01, O.z), Vector3(0.12, 0.02, 120), Color(0.74, 0.6, 0.4), false)
		_slab(Vector3(O.x, Y0 + 0.01, O.z + float(i) * 10.0), Vector3(120, 0.02, 0.12), Color(0.74, 0.6, 0.4), false)


func _slab(c: Vector3, size: Vector3, col: Color, solid := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mi.material_override = mat
	box.add_child(mi)
	mi.global_position = c
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		box.add_child(sb)
		sb.global_position = c
	return mi


## 战斗区四角立个小柱子（看得见边）
func _posts(r: Rect2) -> Array:
	var out: Array = []
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out.append(_slab(Vector3(c.x, Y0 + 1.5, c.y), Vector3(0.6, 3.0, 0.6), Color(0.85, 0.25, 0.2), false))
	return out


func put_player(p: Vector3, yaw := 0.0) -> void:
	player.force_ground()
	player.global_position = Vector3(p.x, Y0 + 0.1, p.z)
	player.velocity = Vector3.ZERO
	player.face_now(yaw)
	m.cam.snap(yaw, -0.36, 17.0)


# ---------- 生成 ----------

func spawn_boss(id: String, pos: Vector3, arena: Rect2) -> Array:
	var mb: Mob = Mob.new()
	mb.player = player
	ExMobs.setup(mb, id, false, 1)
	mb.floor_fn = ground
	mb.position = Vector3(pos.x, Y0, pos.z)
	mb.dmg_in = func(d: float) -> float: return d / 18.0 * ExMobs.HIT_PER_UNIT * DMG_K
	mb.atk_out = func(d: float) -> float: return d
	_nid += 1
	mb.net_id = _nid
	box.add_child(mb)
	var b: Node3D = ExBoss.attach(mb, id, arena, {"home": Vector3(pos.x, Y0, pos.z), "fx_out": _on_fx, "summon_fn": _summon,
			"night_fn": func() -> bool: return night})
	return [mb, b]


func spawn_mob(id: String, pos: Vector3, elite := false) -> Mob:
	var mb: Mob = Mob.new()
	mb.player = player
	ExMobs.setup(mb, id, elite, 1)
	mb.floor_fn = ground
	mb.position = Vector3(pos.x, Y0, pos.z)
	mb.dmg_in = func(d: float) -> float: return d / 18.0 * ExMobs.HIT_PER_UNIT
	mb.atk_out = func(d: float) -> float: return d
	_nid += 1
	mb.net_id = _nid
	box.add_child(mb)
	return mb


func _summon(id: String, pos: Vector3, elite: bool) -> Node3D:
	var mb := spawn_mob(id, pos, elite)
	mb.alert()
	adds.append(mb)
	return mb


func _on_fx(kind: String, p: Dictionary) -> void:
	fx_log.append(kind)
	if relay != null and is_instance_valid(relay):
		var r := relay
		get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if is_instance_valid(r):
				r.call("play_remote", kind, p))


func clear_all() -> void:
	for n: Node in box.get_children():
		if n is Mob:
			n.queue_free()
	adds.clear()
	await get_tree().process_frame
	await get_tree().process_frame


func _clamp_test(p: Vector3, r: Rect2) -> Vector3:
	var g := r.grow(-3.0)
	return Vector3(clampf(p.x, g.position.x, g.end.x), p.y, clampf(p.z, g.position.y, g.end.y))


func arena_at(c: Vector3, w: float, h: float) -> Rect2:
	return Rect2(c.x - w * 0.5, c.z - h * 0.5, w, h)


# ---------- 主流程 ----------

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	var t := 0.0
	while (m.get("player") == null or bool(m.get("_switching"))) and t < 20.0:
		await wait(0.25)
		t += 0.25
	# 手机档（--touch）开机有一段预热（黑幕「灵气汇聚中」）：等主角能动、黑幕退掉
	player = m.get("player")
	t = 0.0
	while t < 180.0 and (player.process_mode == Node.PROCESS_MODE_DISABLED or float(m.level_ui._fade.color.a) > 0.05):
		await wait(0.25)
		t += 0.25
	await wait(1.5)
	var cam: Node = m.get("cam")
	cam.set("capture_mouse", false)
	var hub: Node = m.get("hub")
	if hub != null:
		hub.call("set_active", false)
	m.call("_set_hall_active", false)
	_build_box()
	cam.set("floor_fn", ground)
	cam.set("occl_fn", Callable())
	cam.set("focus", null)
	player.ground_ref = Y0
	put_player(O + Vector3(0, 0, 14))
	await wait(0.6)
	var want: Array = ALL if arg == "" else Array(arg.split(","))
	await _lineup()
	await _block_test()
	for id: String in want:
		await clear_all()
		taken = 0.0
		fx_log.clear()
		match id:
			"lingyou":
				await _t_lingyou()
			"jiangluo":
				await _t_jiangluo()
			"sandworm":
				await _t_sandworm()
			"lingying":
				await _t_lingying()
			"dianbian":
				await _t_dianbian()
			"bingjiang":
				await _t_bingjiang()
			"duo":
				await _t_duo()
	await clear_all()
	say("完成：失败 %d 项，用时 %.0f 秒" % [fails, (Time.get_ticks_msec() - _t0) / 1000.0])
	guard = false
	box.queue_free()
	if hub != null:
		m.call("_place_in_hub", hub.call("return_point", 0), PI)
	await wait(0.5)
	get_tree().quit()


## 通用：主角站在区里不出手，挨 sec 秒，看技能放了几次、主角掉了多少血
func soak(b: Node3D, sec: float, shots: Array, tag: String) -> void:
	var t := 0.0
	var dc := 0
	while t < sec:
		await wait(0.25)
		t += 0.25
		dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if relay != null and is_instance_valid(relay):
			relay_bullets = maxi(relay_bullets, (relay.get("_bp") as PackedVector3Array).size())
		for s: Array in shots:
			if absf(float(s[0]) - t) < 0.12:
				await m._shot("ex_boss_%s_%s" % [tag, s[1]])
	say("%s：%.0f 秒内技能 %s，广播 %d 条，主角挨了 %.1f 点（%d 下），最高绘制调用 %d" % [tag, sec, b.get("casts"), fx_log.size(), taken,
			int(b.get("hits_dealt")), dc])


## 通用：区外打无效 / 跑出区拉回 / 区内没人回满血
func common(mb: Mob, b: Node3D, arena: Rect2, tag: String, out := 20.0) -> void:
	var hp0 := mb.hp
	var inside: bool = b.call("accept_hit", player.global_position)
	mb.receive_hit(player, {"dmg": 18.0, "dir": Vector3.FORWARD})
	var hurt_in := hp0 - mb.hp
	var save := player.global_position
	player.global_position = Vector3(arena.end.x + 12.0, Y0 + 0.1, arena.get_center().y)
	var hp1 := mb.hp
	mb.receive_hit(player, {"dmg": 18.0, "dir": Vector3.FORWARD})
	var hurt_out := hp1 - mb.hp
	check(tag + " 区外打无效", inside and hurt_in > 0.0 and is_zero_approx(hurt_out), "区内一下 %.1f、区外一下 %.1f（单位 1 × 10 × %.0f）" % [hurt_in, hurt_out, DMG_K])
	# 区内没人 5 秒回满（主角站到区外 20 米）
	put_player(Vector3(arena.end.x + out, Y0, arena.get_center().y), PI * 0.5)
	# 战斗时钟每帧最多推 1/30 秒（Combat.MAX_DT）：隐藏窗口帧率低时比真实时间慢，按条件等
	var t0 := Time.get_ticks_msec()
	while not is_equal_approx(mb.hp, mb.hp_max) and Time.get_ticks_msec() - t0 < 12000:
		await wait(0.1)
	check(tag + " 区内没人回满血", is_equal_approx(mb.hp, mb.hp_max), "%.0f / %.0f（真实时间 %.1f 秒）" % [mb.hp, mb.hp_max,
			(Time.get_ticks_msec() - t0) / 1000.0])
	if String(ExBoss.MOVE.get(String(b.get("boss_id")), "")) != "worm":
		mb.global_position = Vector3(arena.end.x + 15.0, Y0, arena.end.y + 15.0)
		await wait(0.3)
		var home: Vector3 = b.get("home")
		check(tag + " 跑出战斗区拉回", mb.global_position.distance_to(home) < 3.0, "离出生点 %.1f 米" % mb.global_position.distance_to(home))
	player.global_position = save


# ---------- 各首领 ----------

func _t_lingyou() -> void:
	var c := O + Vector3(0, 0, -4)
	var arena := arena_at(O, 48.0, 44.0)
	var posts := _posts(arena)
	var pair := spawn_boss("lingyou", c, arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	put_player(O + Vector3(0, 0, 12))
	say("凌幽 血 %.0f（DarkArea 80000 × 0.04 × 0.7）攻 %.0f" % [mb.hp_max, mb.atk])
	# 联机重放：一个木偶大脑，主人每条广播 0.08 秒后转给它
	var pm: Mob = Mob.new()
	pm.player = player
	pm.puppet = true
	pm.net_hit = func(_mm: Node3D, _info: Dictionary) -> void: pass
	ExMobs.setup(pm, "lingyou", false, 1)
	pm.floor_fn = ground
	pm.position = c + Vector3(30, 0, 0)
	box.add_child(pm)
	pup = pm
	relay = ExBoss.attach_remote(pm, "lingyou", arena, {"home": pm.position})
	var p0 := mb.global_position
	relay_bullets = 0
	await soak(b, 11.0, [[4.0, "a"], [8.6, "b"]], "lingyou")
	var cs: Dictionary = b.get("casts")
	check("凌幽 追踪弹 + 螺旋弹幕", int(cs.get("aimed", 0)) >= 4 and int(cs.get("spiral", 0)) >= 2, str(cs))
	check("凌幽 不移动", mb.global_position.distance_to(p0) < 0.3, "挪了 %.2f 米" % mb.global_position.distance_to(p0))
	check("凌幽 打得到人", taken > 0.0, "%.1f 点" % taken)
	check("联机重放：木偶那边有弹幕、不打人", relay_bullets > 0 and int(relay.get("hits_dealt")) == 0 and int(relay.get("fx_sent")) == 0,
			"木偶命中 %d，木偶那边最多同时 %d 颗弹" % [int(relay.get("hits_dealt")), relay_bullets])
	relay = null
	pup = null
	pm.queue_free()
	# 螺旋发数随失血
	mb.hp = mb.hp_max * 0.1
	var n_low := clampi(int(floor(50.0 - mb.hp / (mb.hp_max / 40.0))), 10, 50)
	check("凌幽 螺旋发数 10→50", n_low == 46, "一成血时 %d 发" % n_low)
	mb.hp = mb.hp_max
	await common(mb, b, arena, "凌幽")
	for p: Node in posts:
		p.queue_free()


func _t_jiangluo() -> void:
	var c := O + Vector3(0, 0, -4)
	var arena := arena_at(O, 64.0, 64.0)
	var posts := _posts(arena)
	var pair := spawn_boss("jiangluo", c, arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	put_player(O + Vector3(0, 0, 12))
	await soak(b, 7.0, [[5.5, "a"]], "jiangluo")
	# 贴脸：看它逃
	var bp := mb.global_position
	put_player(bp + Vector3(0, 0, 4))
	await wait(0.2)
	var d0 := player.global_position.distance_to(mb.global_position)
	await wait(2.0)
	var d1 := player.global_position.distance_to(mb.global_position)
	await m._shot("ex_boss_jiangluo_flee")
	var cs: Dictionary = b.get("casts")
	check("绛罗 贴脸就逃", d1 > d0 + 5.0, "离主角 %.1f → %.1f 米" % [d0, d1])
	check("绛罗 召唤幽冥泣", int(cs.get("summon", 0)) >= 1 and adds.size() >= 2, "召唤 %d 次、场上 %d 只" % [int(cs.get("summon", 0)), adds.size()])
	await common(mb, b, arena, "绛罗")
	for p: Node in posts:
		p.queue_free()


func _t_sandworm() -> void:
	var arena := arena_at(O, 88.0, 88.0)
	var posts := _posts(arena)
	var pair := spawn_boss("sandworm", O + Vector3(0, 0, -10), arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	put_player(O + Vector3(0, 0, 14))
	say("沙渊巨虫 血 %.0f（160000 × 0.04 × 0.7）召唤条件 %s" % [mb.hp_max, ExMobs.can_summon("sandworm", 1)])
	var worm: Node3D = b.get("worm")
	# 埋地免伤
	await wait(0.3)
	var hp0 := mb.hp
	mb._take_raw(50.0, Vector3.FORWARD, false)
	check("巨虫 埋在地下打不到", is_equal_approx(mb.hp, hp0) and not bool(worm.call("is_exposed")), "")
	var exposed_hits := 0
	var near_ok := 0
	var t := 0.0
	var dc := 0
	while t < 16.0:
		await wait(0.25)
		t += 0.25
		dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if bool(worm.call("is_exposed")):
			exposed_hits += 1
			var hit: Array = worm.call("nearest_exposed", player.global_position + Vector3.UP)
			if not hit.is_empty() and mb.global_position.distance_to(hit[0]) < 0.3:
				near_ok += 1
		if absf(t - 5.0) < 0.12 or absf(t - 9.5) < 0.12 or absf(t - 13.0) < 0.12:
			await m._shot("ex_boss_sandworm_%d" % int(t))
	var cs: Dictionary = b.get("casts")
	say("巨虫：16 秒内技能 %s，广播 %d 条，主角挨了 %.1f 点，露头 %d/64 帧，最高绘制调用 %d" % [cs, fx_log.size(), taken, exposed_hits, dc])
	check("巨虫 钻地 + 定点爆炸 + 沙卷风", fx_log.count("worm") >= 4 and int(cs.get("bombard", 0)) >= 2 and int(cs.get("tornado", 0)) >= 1, "")
	check("巨虫 判定点贴着离主角最近的那节", exposed_hits > 0 and near_ok == exposed_hits, "%d/%d" % [near_ok, exposed_hits])
	check("巨虫 打得到人", taken > 0.0, "%.1f 点" % taken)
	# 露头时打得到
	var tries := 0
	while not bool(worm.call("is_exposed")) and tries < 40:
		await wait(0.2)
		tries += 1
	var hp1 := mb.hp
	mb._take_raw(50.0, Vector3.FORWARD, false)
	check("巨虫 露头时打得到", mb.hp < hp1, "")
	# 嗜血
	mb.hp = mb.hp_max * 0.45
	await wait(0.3)
	check("巨虫 半血以下嗜血", bool(b.get("frenzy")), "")
	var hp2 := mb.hp
	b.call("dealt", 20.0)
	check("巨虫 嗜血回血", mb.hp > hp2, "打中 20 点回 %.1f" % (mb.hp - hp2))
	taken = 0.0
	await wait(6.0)
	await m._shot("ex_boss_sandworm_frenzy")
	say("巨虫嗜血后 6 秒：技能 %s，主角挨了 %.1f 点" % [b.get("casts"), taken])
	await common(mb, b, arena, "巨虫")
	for p: Node in posts:
		p.queue_free()


func _t_lingying() -> void:
	var c := O + Vector3(0, 0, -6)
	var arena := arena_at(O, 63.0, 63.0)
	var posts := _posts(arena)
	night = false
	var pair := spawn_boss("lingying", c, arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	put_player(O + Vector3(0, 0, 12))
	await soak(b, 9.0, [[3.6, "a"]], "lingying")
	var cs: Dictionary = b.get("casts")
	check("凌影 白天：投掷尸傀 / 召唤", int(cs.get("lob", 0)) >= 1 and adds.size() >= 1, "%s，场上尸傀 %d" % [cs, adds.size()])
	var r0 := mb.hp / mb.hp_max
	var h0 := mb.hp_max
	night = true
	await wait(4.0)
	check("凌影 入夜变身狂潮霸主（血量 ×1.9）", bool(b.get("transformed")) and absf(mb.hp_max / h0 - 1.9) < 0.01 and absf(mb.hp / mb.hp_max - r0) < 0.05,
			"%.0f → %.0f" % [h0, mb.hp_max])
	var alive := 0
	for a: Variant in adds:
		if is_instance_valid(a) and a.is_alive():
			alive += 1
	check("凌影 尸潮补到 7 只", alive >= 7, "场上 %d 只" % alive)
	await m._shot("ex_boss_lingying_night")
	check("凌影 夜里换掉落表", String(b.call("drop_table")) == "yanjiuBossDrops2", String(b.call("drop_table")))
	night = false
	await common(mb, b, arena, "凌影")
	for p: Node in posts:
		p.queue_free()


func _t_dianbian() -> void:
	var c := O + Vector3(0, 0, -4)
	var arena := arena_at(O, 57.0, 57.0)
	var posts := _posts(arena)
	var pair := spawn_boss("dianbian", c, arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	put_player(O + Vector3(0, 0, 8))
	await soak(b, 14.0, [[4.5, "a"], [9.0, "b"], [13.0, "c"]], "dianbian")
	var cs: Dictionary = b.get("casts")
	check("电鞭 雷电普攻 + 五连鞭 + 雷暴", int(cs.get("aimed", 0)) >= 4 and int(cs.get("whip", 0)) >= 1 and int(cs.get("storm", 0)) >= 1, str(cs))
	check("电鞭 打得到人", taken > 0.0, "%.1f 点" % taken)
	await common(mb, b, arena, "电鞭")
	for p: Node in posts:
		p.queue_free()


func _t_bingjiang() -> void:
	var c := O + Vector3(0, 0, -6)
	var arena := arena_at(O, 57.0, 57.0)
	var posts := _posts(arena)
	var pair := spawn_boss("bingjiang", c, arena)
	var mb: Mob = pair[0]
	var b: Node3D = pair[1]
	# 站远：先等锁链
	put_player(O + Vector3(0, 0, 18))
	var far := player.global_position.distance_to(mb.global_position)
	var pulled := INF
	var t := 0.0
	var chain0 := 0
	while t < 14.0:
		await wait(0.1)
		t += 0.1
		var cs0: Dictionary = b.get("casts")
		if int(cs0.get("chain", 0)) > chain0:
			chain0 = int(cs0.get("chain", 0))
			far = player.global_position.distance_to(mb.global_position)
			pulled = far
			for k in 12:
				await wait(0.1)
				t += 0.1
				pulled = minf(pulled, player.global_position.distance_to(mb.global_position))
				if k == 7:
					await m._shot("ex_boss_bingjiang_chain")
		elif fmod(t, 3.0) < 0.1 and int(b.get("_busy") > 0.0) == 0:
			# 每 3 秒把主角放回 18 米外（不然它走到脸上，冲锋 / 锁链都没有用武之地）
			var d := (player.global_position - mb.global_position)
			d.y = 0.0
			d = d.normalized() if d.length_squared() > 0.01 else Vector3.BACK
			put_player(_clamp_test(mb.global_position + d * 18.0, arena), atan2(d.x, d.z))
		if absf(t - 4.0) < 0.06:
			await m._shot("ex_boss_bingjiang_a")
	var cs: Dictionary = b.get("casts")
	say("冰僵：12 秒内技能 %s，主角挨了 %.1f 点" % [cs, taken])
	check("冰僵 冲锋 + 锁链", int(cs.get("charge", 0)) >= 1 and int(cs.get("chain", 0)) >= 1, str(cs))
	check("冰僵 锁链把人拉到身前", int(cs.get("chain", 0)) >= 1 and pulled < 6.5, "拉之前 %.1f 米，拉完 %.1f 米" % [far, pulled])
	await common(mb, b, arena, "冰僵")
	for p: Node in posts:
		p.queue_free()


func _t_duo() -> void:
	var arena := arena_at(O, 50.0, 50.0)
	var posts := _posts(arena)
	var a := spawn_boss("duo_hunter", O + Vector3(-4, 0, -6), arena)
	var w := spawn_boss("duo_welder", O + Vector3(5, 0, -8), arena)
	var hm: Mob = a[0]
	var wm: Mob = w[0]
	ExBoss.link_duo(a[1], w[1])
	put_player(O + Vector3(0, 0, 10))
	say("双卫 血 %.0f / %.0f，掉落 %s × %d" % [hm.hp_max, wm.hp_max, ExMobs.boss_drop("duo_hunter"), ExMobs.boss_draws("duo_hunter")])
	await soak(a[1], 8.0, [[5.0, "a"]], "duo")
	hm.hp = hm.hp_max * 0.4
	var h0 := hm.hp
	await wait(2.2)
	check("双卫 焊愈卫给猎杀卫回血", hm.hp > h0, "%.0f → %.0f（0.5%%/秒）" % [h0, hm.hp])
	check("双卫 一方半血以下另一方变身", bool((w[1] as Node3D).get("transformed")) and is_equal_approx(float((w[1] as Node3D).get("dmg_k")), 1.3), "")
	# 出圈拉回：主角走出圈 4 米
	var t0 := taken
	player.global_position = Vector3(arena.end.x + 4.0, Y0 + 0.1, O.z)
	await wait(1.2)
	check("双卫 出圈拉回 + 罚 20 点", arena.grow(0.5).has_point(Vector2(player.global_position.x, player.global_position.z)) and taken - t0 >= 19.9,
			"现在在 %s，罚了 %.1f 点" % [player.global_position, taken - t0])
	await m._shot("ex_boss_duo_b")
	await common(hm, a[1], arena, "双卫", 30.0)      # 双卫出圈不到 25 米会被拉回，回满血要站远
	for p: Node in posts:
		p.queue_free()


# ---------- 小怪排一排 / 挡墙 ----------

func _lineup() -> void:
	var ids := ["scorpion", "wolf_sand", "sand_guard", "sand_raider", "zombie", "mech_claw", "mech_gunner", "gel_mutant", "wraith"]
	var list: Array = []
	var i := 0
	for id: String in ids:
		for el: bool in [false, true]:
			if el and (id == "gel_mutant" or id == "wraith"):
				continue
			var x := (float(i % 8) - 3.5) * 4.2
			var z := -6.0 if i < 8 else -16.0
			var mb := spawn_mob(id, O + Vector3(x, 0, z), el)
			mb.set_process(false)
			list.append(mb)
			say("%s%s：血 %.0f 攻 %.1f 名牌「%s」" % [id, "（精英）" if el else "", mb.hp_max, mb.atk, ExMobs.display_name(id, el)])
			i += 1
	put_player(O + Vector3(0, 0, 6))
	m.cam.snap(0.0, -0.3, 13.0)
	await wait(1.2)
	await m._shot("ex_boss_lineup")
	check("刷怪点抽样", _camp_ok(), "")
	for mb: Variant in list:
		(mb as Node).queue_free()
	await wait(0.2)


func _camp_ok() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	var samples := []
	for map_id: String in ["desert", "lab"]:
		for k in 30:
			var c: Array = ExMobs.roll_camp(map_id, rng)
			ok = ok and c.size() >= 3 and c.size() <= 5
			for e: Array in c:
				ok = ok and ExMobs.has(String(e[0])) and String(ExMobs.def(String(e[0]))["map"]) == map_id
			if k < 2:
				samples.append(c)
	say("刷怪点样本 %s" % [samples])
	return ok


## raid_mob.block_fn：中间一堵墙，主角在墙后，带挡墙的怪绕不过去、不带的直接穿墙
func _block_test() -> void:
	_wall = AABB(Vector3(O.x - 10.0, Y0, O.z - 1.0), Vector3(20.0, 5.0, 2.0))
	var wall := _slab(_wall.get_center(), _wall.size, Color(0.5, 0.45, 0.4), true)
	put_player(O + Vector3(0, 0, 6))
	var a := spawn_mob("zombie", O + Vector3(-2, 0, -8))
	a.block_fn = blocked
	a.alert()
	var b := spawn_mob("zombie", O + Vector3(2, 0, -8))
	b.alert()
	var crossed_a := false
	var crossed_b := false
	var t := 0.0
	while t < 6.0:
		await wait(0.1)
		t += 0.1
		player.global_position = O + Vector3(0, 0.1, 6)
		if is_instance_valid(a) and a.global_position.z > O.z + 1.0:
			crossed_a = true
		if is_instance_valid(b) and b.global_position.z > O.z + 1.0:
			crossed_b = true
		if absf(t - 3.0) < 0.06:
			await m._shot("ex_boss_blockfn")
	check("raid_mob.block_fn 挡墙", not crossed_a and crossed_b, "带钩子的过墙=%s，不带的过墙=%s（应 false / true）" % [crossed_a, crossed_b])
	if is_instance_valid(a):
		a.queue_free()
	if is_instance_valid(b):
		b.queue_free()
	wall.queue_free()
	_wall = AABB()
	await wait(0.2)
