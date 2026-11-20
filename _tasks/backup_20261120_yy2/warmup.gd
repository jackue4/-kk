extends RefCounted
## 首次使用预热：把「打起来才第一次用到」的东西挪到载入幕布后面先用一遍，免得第一下出招、第一次放飞剑时卡住。
## 网页版 / 手机用的 Compatibility 渲染器，每种材质第一次被画到时才现编着色器（一个几十到几百毫秒，手机上更久），
## 而且同一个材质「附近有没有点光源」算两个版本、换一套环境（大厅 / 大世界，雾和阳光设置不同）又要重编。
## 所以这里每个环境做一次（run 的 tag），在镜头前面真的画出来，无光、有光各画两帧：
##   1 着色器：shaders/ 和 fx/ 下所有 .gdshader 各套一张小面片（粒子着色器套一个粒子系统，界面着色器套一个小色块）
##   2 主角身上平时藏着的部件（御剑、护体罩、遁光粒子……）：照原样的网格和材质复制一份摆出来
##   3 特效：vfx.gd 里各种命中 / 斩击 / 起落 / 雷火 / 碎块 …… 各放一次（放出来就定住，不等它自己播完）
##   4 文字：伤害数字、战斗题字、剑诀题字用到的字先写一遍（字形光栅化也是第一次用才做）
##   5 大世界：这一区的小怪 / 精英 / 首领模型和各种掉落物各摆一个
## 期间静音；做完全部清掉。音效库（sfx.gd 现合成的那一批）也在这里先合成好。
## 故意不写 class_name：用 preload 引用。

const Sfx := preload("res://scripts/sfx.gd")
const CombatWord := preload("res://scripts/combat_word.gd")
const Calligraphy := preload("res://scripts/skill_calligraphy.gd")
const RaidData := preload("res://scripts/raid_data.gd")

## 单独点名要先编译的着色器文件。别把 shaders/ 整个扫一遍：网页版里每个着色器现编要一秒上下（实测 28 个花了 41 秒），
## 只列「打起来一定会用到、而下面几轮又画不到」的。
const SWEEP: Array = ["res://shaders/voxel_dissolve.gdshader", "res://shaders/brush_reveal.gdshader"]
## 结婴演出（yuanying_cine.gd）的五个着色器。只在大世界、而且主角还没到元婴（这一局还可能结婴）时才编：
## 不然它们要等到剑气拔起、元婴现形的那一帧才现编，演出正好在最要紧的地方各卡一拍。
const CINE: Array = ["res://shaders/cine_sky.gdshader", "res://shaders/sword_qi.gdshader", "res://shaders/space_ripple.gdshader",
		"res://shaders/spirit_body.gdshader", "res://shaders/spirit_halo.gdshader",
		"res://shaders/clash_beam.gdshader", "res://shaders/clash_core.gdshader", "res://shaders/clash_disc.gdshader"]
const Arc := preload("res://scripts/slash_arc.gd")
const Proj := preload("res://scripts/spell_projectile.gd")

static var done := false          # 至少做完过一轮
static var last_ms := 0           # 最近一轮花了多久
static var last_note := ""
static var _envs := {}


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


## 放一批东西出来：新冒出来的节点当场定住（不让它自己播完消失），无光画两帧、有光画两帧，然后清掉
## phases = 2：无光、有光各画两帧（场景里常驻的东西：远处没有光、打起来身边有闪光，两种都会遇到）；
## phases = 1：只在有光的状态下画（战斗特效总是出现在主角身边 / 自带闪光，基本只会遇到有光的那一种，省一半编译时间）
static func _batch(tree: SceneTree, roots: Array, lights: Node3D, spawn: Callable, freeze := true, phases := 1) -> void:
	var before := {}
	for r: Node in roots:
		for c in r.get_children():
			before[c] = true
	spawn.call()
	var made: Array = []
	for r: Node in roots:
		for c in r.get_children():
			if not before.has(c) and c is Node3D:      # 只管画面上的东西；音效播放器、计时器这些别人新建的节点不碰
				if freeze:
					c.process_mode = Node.PROCESS_MODE_DISABLED
				made.append(c)
	if not Vfx.lights:
		# 手机档没有动态点光（main.gd 的 _apply_mobile_tier）：实际只会遇到「无光」这一种，就只编这一种
		lights.visible = false
		await _frames(tree, 2)
	else:
		if phases >= 2:
			lights.visible = false
			await _frames(tree, 2)
		lights.visible = true
		await _frames(tree, 2)
	for c in made:
		if is_instance_valid(c):
			c.queue_free()


## 一个着色器套到一个能画出来的东西上：空间着色器 → 小面片；粒子着色器 → 小粒子系统；界面着色器 → 小色块
static func _spawn_shader(path: String, holder: Node3D, layer: CanvasLayer, quad: Mesh, slot: Vector3) -> void:
	var sh := load(path) as Shader
	if sh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mode := sh.get_mode()
	if mode == Shader.MODE_SPATIAL:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.global_position = slot
		mi.scale = Vector3.ONE * 0.3
	elif mode == Shader.MODE_PARTICLES:
		var gp := GPUParticles3D.new()
		gp.amount = 4
		gp.lifetime = 1.0
		gp.process_material = mat
		gp.draw_pass_1 = quad
		holder.add_child(gp)
		gp.global_position = slot
	elif mode == Shader.MODE_CANVAS_ITEM:
		var cr := ColorRect.new()
		cr.size = Vector2(8.0, 8.0)
		cr.material = mat
		layer.add_child(cr)


## 主角身上此刻没在显示的网格 / 粒子（御剑、护体罩、遁光……）：照原样的网格和材质各复制一份摆出来
static func _spawn_hidden(player: Node3D, holder: Node3D, at: Vector3, right: Vector3, fwd: Vector3) -> void:
	var k := 0
	for n in player.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var copy: Node3D = null
		if gi is GPUParticles3D:
			if (gi as GPUParticles3D).emitting and gi.is_visible_in_tree():
				continue
			copy = gi.duplicate(0) as Node3D
			(copy as GPUParticles3D).emitting = true
			(copy as GPUParticles3D).one_shot = false
		elif gi is MeshInstance3D:
			var src := gi as MeshInstance3D
			if gi.is_visible_in_tree() or src.mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.material_overlay = src.material_overlay
			for si in src.get_surface_override_material_count():
				mi.set_surface_override_material(si, src.get_surface_override_material(si))
			copy = mi
		elif gi is MultiMeshInstance3D:
			if gi.is_visible_in_tree():
				continue
			copy = gi.duplicate(0) as Node3D
		if copy == null:
			continue
		copy.visible = true
		holder.add_child(copy)
		copy.global_position = at + right * (float(k % 9) - 4.0) * 0.6 + fwd * float(k / 9) * 0.6
		k += 1


## tag：环境名（每个环境只做一次）；note：进度回调（文字）；raid：大世界管理器（有就把这一区的怪和掉落也摆一遍）
## extra：除主角之外还要翻一遍「藏着的部件」的节点（飞剑阵）
static func run(host: Node, player: Player, cam: CameraRig, tag: String, note := Callable(), raid: Variant = null, extra: Array = []) -> void:
	if _envs.has(tag) or Vfx.root == null:
		return
	_envs[tag] = true
	var t0 := Time.get_ticks_msec()
	var tree := host.get_tree()
	var c3: Camera3D = cam.cam
	var was_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var prog := [0, 1]      # [做完几批, 一共几批]
	var stage := [""]
	var say := func(text: String) -> void:
		if text != "":
			stage[0] = text
		last_note = "%s %d%%" % [stage[0], int(100.0 * float(prog[0]) / float(maxi(int(prog[1]), 1)))]
		if note.is_valid():
			note.call(last_note)
	var tick := func() -> void:
		prog[0] = int(prog[0]) + 1
		say.call("")
	say.call("凝练音律")
	await _frames(tree, 1)
	if Sfx._bank.is_empty():
		Sfx._build()
	Sfx.play("thud", -80.0)      # 顺手把播放器池建好（它挂在主场景下面，得赶在下面记「新冒出来的节点」之前）
	var marks: Array = ["音效 %d" % (Time.get_ticks_msec() - t0)]
	var tm := Time.get_ticks_msec()
	await _frames(tree, 1)
	var fwd := -c3.global_basis.z
	var right := c3.global_basis.x
	var up := c3.global_basis.y
	var at := c3.global_position + fwd * 7.0
	var holder := Node3D.new()
	holder.name = "Warm"
	host.add_child(holder)
	var lights := Node3D.new()
	holder.add_child(lights)
	var ol := OmniLight3D.new()
	ol.omni_range = 90.0
	ol.light_energy = 0.002
	ol.shadow_enabled = false
	lights.add_child(ol)
	lights.visible = Vfx.lights
	lights.global_position = c3.global_position
	var body: Node3D = player.visual if player.visual != null else player
	var roots: Array = [Vfx.root, host, holder, player, body]
	var col: Color = Realm.line_color(player.realm)

	# ---- 1 着色器 ----
	say.call("淬炼灵光")
	var files: Array = []
	for f: String in SWEEP:
		files.append(f)
	var layer := CanvasLayer.new()
	layer.layer = -50
	holder.add_child(layer)
	var quad := QuadMesh.new()
	var n_sh := 0
	var cine_on: bool = tag == "raid" and (player.realm_idx < 3 or OS.get_cmdline_user_args().has("--warm-cine"))      # 后一个是自检用的开关
	prog[1] = int(ceil(float(files.size()) / 8.0)) + 9 + (6 if raid != null and not raid.net_on() else 0) + (1 if cine_on else 0)
	for i0 in range(0, files.size(), 8):
		await _batch(tree, roots, lights, func() -> void:
			for i in range(i0, mini(i0 + 8, files.size())):
				_spawn_shader(str(files[i]), holder, layer, quad, at + right * (float(i % 8) - 3.5) * 0.5 + up * (float(i / 8 % 5) - 2.0) * 0.5))
		n_sh = mini(i0 + 8, files.size())
		tick.call()
	marks.append("着色器 %d" % (Time.get_ticks_msec() - tm))
	tm = Time.get_ticks_msec()
	if cine_on:
		await _batch(tree, roots, lights, func() -> void:
			for i in CINE.size():
				_spawn_shader(str(CINE[i]), holder, layer, quad, at + right * (float(i) - 2.0) * 0.5 - up * 2.4))
		tick.call()
		marks.append("结婴演出 %d" % (Time.get_ticks_msec() - tm))
		tm = Time.get_ticks_msec()

	# ---- 2 主角身上藏着的部件 ----
	say.call("温养法器")
	await _batch(tree, roots, lights, func() -> void:
		_spawn_hidden(player, holder, at - up * 1.2, right, fwd)
		for ex: Variant in extra:
			if is_instance_valid(ex):
				_spawn_hidden(ex, holder, at - up * 1.8, right, fwd))
	tick.call()
	# 兵刃：近战的刀光弧（两种材质）、飞剑（实体剑 / 光剑，带拖尾和剑光）
	await _batch(tree, roots, lights, func() -> void:
		var mats: Array = [Arc.make_material(col, Color.WHITE), Arc.make_tex_material(col)]
		for i in mats.size():
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mats[i]
			holder.add_child(mi)
			mi.global_position = at + right * (float(i) - 0.5) + up * 1.5
			mi.scale = Vector3.ONE * 0.3
		Proj.launch(player, Proj.K.SWORD, at + up, null, at + up + fwd * 4.0, {"sfx": false, "color": col, "life": 0.3, "dmg": 0.0})
		Proj.launch(player, Proj.K.SWORD, at + up + right, null, at + up + right + fwd * 4.0, {"sfx": false, "color": col, "life": 0.3, "dmg": 0.0, "light": true, "scale": 2.2}))
	tick.call()
	# 法术弹：火球 / 大火球（连同炸开的那一下）、法球、法轮 —— 各境界剑诀里会放出来的
	await _batch(tree, roots, lights, func() -> void:
		var kinds: Array = [Proj.K.FIRE, Proj.K.BIG_FIRE, Proj.K.ORB, Proj.K.WHEEL]
		for i in kinds.size():
			var from := at + right * (float(i) - 1.5) * 1.2 + up * 0.5
			var pj: Node3D = Proj.launch(player, int(kinds[i]), from, null, from + fwd * 4.0, {"sfx": false, "color": col, "life": 0.3, "dmg": 0.0})
			if pj != null and i < 2:
				pj._fireball_impact(from + up * 1.5, fwd))
	tick.call()

	marks.append("藏着的部件 %d" % (Time.get_ticks_msec() - tm))
	tm = Time.get_ticks_msec()
	# ---- 3 特效 ----
	say.call("推演招式")
	var d := fwd
	var rock: Array = [Color(0.42, 0.43, 0.47), Color(0.32, 0.33, 0.37), Color(0.55, 0.55, 0.58)]
	var lines: Array = Realm.lines(player.realm)
	var calls: Array = [
		func() -> void:
			Vfx.hit(at, d, col)
			Vfx.damage_number(at, 1234567890.0, col)
			Vfx.damage_number(at + up, 88.0, Color(1.0, 0.3, 0.25))
			Vfx.takeoff_burst(at, col, 1.0)
			Vfx.launch_ring(at, d, col, 1.0)
			Vfx.sword_form(at, col)
			Vfx.dash_start(at, d, col, 1.0)
			Vfx.dash_end(at, d, col, 1.0)
			Vfx.breakthrough(at, col, 1.0)
			Vfx.reappear(at, col)
			Vfx.line_sparks(at, d, col, 6, 12.0)
			Vfx.ribbon_burst(at, d, col, 6, 8.0)
			Vfx.flash_light(at, col, 0.5, 4.0, 0.2),
		func() -> void:
			# 剑影 / 身形残影：用完就扔的半透明材质，先放一次，让 main.gd 的「留住着色器」记下这种组合
			Vfx.blade_ghost(Transform3D(Basis.IDENTITY, at + up * 0.5), MeshLib.blade_mesh(), col)
			Vfx.body_ghost(body, col)
			Vfx.blade_hit(at, d, col)
			Vfx.blade_clash(at, d)
			Vfx.ground_slam(at, col)
			Vfx.glint(at, col)
			Vfx.step_ring(at, col)
			Vfx.deathblow(at, d)
			for tier in 3:
				Vfx.impact(at + right * float(tier), d, col, tier)
			Vfx.debris(at, d, rock, 6)
			Vfx.dust(at, 6)
			Vfx.launch_lines(at, col)
			Vfx.slam_impact(at, col)
			Vfx.dun_slam(at, col),
		func() -> void:
			Vfx.death_burst(at, col)
			Vfx.death_implode(at, col)
			Vfx.body_ghost(body, col)
			Vfx.perfect_dodge(at, at + d * 2.0, col)
			Vfx.warp_line(at, at + d * 3.0, col)
			Vfx.blink_start(at, d, col)
			Vfx.cast_flash(at, col)
			Vfx.cast_charge(at, col, 0.4)
			Vfx.fire_explode(at, d, false)
			Vfx.fire_explode(at + right, d, true)
			Vfx.lightning(at + up * 3.0, at, col)
			Vfx.thunder(at, col),
		func() -> void:
			Vfx.rift(at, -d, col)
			Vfx.rift_collapse(at, col, 2.0)
			Vfx.pentagram(at, Vector3.UP, 2.0)
			Vfx.fire_lotus(at)
			Vfx.sky_ring(at, col, 2.0)
			Vfx.halo(at, -d, col, 1.5)
			Vfx.halo(at + right, -d, col, 1.5, 0.3, 1.0)
			Vfx.crescent(at, d, col)
			Vfx.heaven_strike(at, lines)
			for art in 7:
				Vfx.art_hit(at + right * (float(art) - 3.0) * 0.6, d, col, art)
				Vfx.art_hit(at + right * (float(art) - 3.0) * 0.6 + up, d, col, art, true)
			Vfx.shockwave(at, d, col)
			Vfx.vanish(at, col)
			Vfx.wall_crash(at, -d)
			Vfx.ground_break(at - up * 2.0, 1.0, 0.5),
		func() -> void:
			for idx in Realm.count():
				Vfx.realm_ascend(body, idx, Realm.lines(Realm.LIST[idx]), float(Realm.LIST[idx]["fx"]))
			var gs := Vfx.persistent_sprite(col, 0)
			Vfx.place_streak(gs, at, d, 2.0, 0.2)
			for mode in 4:
				var ms := Vfx.marker_sprite(col, mode, 0.5)
				ms.global_position = at + right * float(mode) * 0.5
			var rs := Vfx.ribbon_stream(col, 8)
			holder.add_child(rs)
			rs.global_position = at
			rs.emitting = true
			var ws := Vfx.wind_stream(col)
			holder.add_child(ws)
			ws.global_position = at
			ws.emitting = true,
	]
	for cb: Callable in calls:
		await _batch(tree, roots, lights, cb)
		tick.call()

	marks.append("特效 %d" % (Time.get_ticks_msec() - tm))
	tm = Time.get_ticks_msec()
	# ---- 4 文字 ----
	say.call("研墨题字")
	CombatWord.prewarm()      # 常用的战斗字先各画一张贴图留着（之后每次蹦字只是摆几层面片）
	await _batch(tree, roots, lights, func() -> void:
		CombatWord.pop("破防", at + up, col)
		CombatWord.pop("斩", at + up * 2.0, Color(1.0, 0.3, 0.25), 1.6)
		Calligraphy.show_text("万剑归宗", at + right * 2.0, col)
		Calligraphy.show_text("天地", at - right * 2.0, col, 1.0, 1.0), false)
	tick.call()

	marks.append("文字 %d" % (Time.get_ticks_msec() - tm))
	tm = Time.get_ticks_msec()
	# ---- 5 大世界：这一区的怪和掉落 ----
	if raid != null and not raid.net_on():
		say.call("探查妖踪")
		var ri: int = int(raid.region)
		var reg: Dictionary = RaidData.REGIONS[ri]
		var defs: Array = [[int(reg["mobs"][0]), false], [int(reg["mobs"][1]), false], [int(reg["mobs"][0]), true], [int(reg["mobs"][1]), true], [int(reg["boss"]), false]]
		for i in defs.size():
			var made_mob := [null]
			await _batch(tree, roots, lights, func() -> void:
				var q := at + right * (float(i) - 2.0) * 2.0 + fwd * 6.0
				var m: Node3D = raid._spawn_mob(int(defs[i][0]), ri, q, bool(defs[i][1]), 1)
				m.set_process(false)
				m.process_mode = Node.PROCESS_MODE_DISABLED
				if m.has_method("_set_overlay"):
					m._flash = 1.0
					m._set_overlay(true)
				made_mob[0] = m, true, 2)
			tick.call()
			var mm: Variant = made_mob[0]
			if is_instance_valid(mm):
				raid._mobs.erase(mm)
				mm.queue_free()
		var n_pick: int = raid._pickups.size()
		await _batch(tree, roots, lights, func() -> void:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for t in 5:
				var q := at + right * (float(t) - 2.0) * 1.2 - up * 1.5 + fwd * 12.0
				raid._drop_item(q, RaidData.make_gear(t, rng) if t % 3 == 0 else (RaidData.make_pill(t) if t % 3 == 1 else RaidData.make_mat(t)), 999.0)
			raid._drop_chest(at + right * 4.0 - up * 1.5 + fwd * 12.0, [RaidData.make_pill(1)], "精英的遗物")
			raid._drop_chest(at - right * 4.0 - up * 1.5 + fwd * 12.0, [RaidData.make_pill(1)], "预热 的储物袋")
			# 摆出来只为画一遍：定住、不让捡
			for j in range(n_pick, raid._pickups.size()):
				raid._pickups[j].grace = 999.0
				raid._pickups[j].process_mode = Node.PROCESS_MODE_DISABLED, true, 2)
		while raid._pickups.size() > n_pick:
			var pk: Variant = raid._pickups.pop_back()
			if is_instance_valid(pk):
				pk.queue_free()

	holder.queue_free()
	await _frames(tree, 2)
	AudioServer.set_bus_mute(0, was_mute)
	done = true
	last_ms = Time.get_ticks_msec() - t0
	marks.append("怪和掉落 %d" % (Time.get_ticks_msec() - tm))
	print("[warm] %s：预热 %d ms（着色器文件 %d 个）｜%s" % [tag, last_ms, n_sh, " · ".join(marks)])
