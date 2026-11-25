extends Node
## 英雄技能的走查 / 连拍（2026-11-25 TSB 式重做）：`-- --tsb-show[=英雄id] [--tsb-only=m1,e,z,q,r,awk,ae,az,aq,ar] [--tsb-air] [--touch]`。
## main.gd 正常开机后把这个脚本挂上来（m = main，arg = 英雄 id，缺省 yujian）。
## 流程：去试剑台 → 面前摆木人桩（正中一个血很厚的 + 两侧各一个，看范围招）→ 这位英雄 M1 整套、四个技能、觉醒、觉醒四式各放一遍；
## 每一招在几个时刻各截一张（先留在内存里，一招放完再存盘：存盘慢，放在中间会把特效的补间跳过去），
## 存 _shots/preview/tsb_<英雄>_<招>_<n>.jpg；打印每一招打掉正中木桩多少个招式单位、两侧各多少、有没有脚本报错靠 stderr 看。
## --tsb-air：木桩换成会被打飞的浮空桩（看击飞 / 砸地）。
## 故意不写 class_name。

const HeroDefs := preload("res://scripts/hero_defs.gd")

var m: Node
var arg := ""
var player: Player
var dummies: Array = []
var hid := "yujian"
var _snaps: Array = []       # [名字, Image]
var _only: Array = []
var _air := false
var _side_cam := false
var _yaw0 := 0.0
var _input := false         # --tsb-input：技能 / 觉醒走真实按键动作（不直接调技能脚本）
var _level := ""           # --tsb-level=desert|lab：在新图里走查
var _walk := 24.0          # 进图后离出生点往前走多远再摆木桩


func _ready() -> void:
	get_tree().process_frame.connect(_on_frame)
	_run.call_deferred()


func _on_frame() -> void:
	if _side_cam and player != null and is_instance_valid(player) and player.cam != null:
		# 侧面机位：每帧按住（空战的镜头会自己绕回身后）
		player.cam.yaw = _yaw0 + 1.2
		player.cam.pitch = -0.1
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null and is_instance_valid(player) and not player.dead and player.melee != null:
		player.melee.hp = maxf(player.melee.hp, 60.0)


func _fire(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func say(s: String) -> void:
	print("[tsb] " + s)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## 这一帧的画面留一张（不存盘）
func snap(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_snaps.append([tag, get_viewport().get_texture().get_image()])


func flush() -> void:
	for s: Array in _snaps:
		var img: Image = s[1]
		img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.save_jpg("res://_shots/preview/tsb_%s_%s.jpg" % [hid, s[0]], 0.86)
		print("[shot] tsb_%s_%s" % [hid, s[0]])
	_snaps.clear()


func _want(k: String) -> bool:
	return _only.is_empty() or _only.has(k)


func _run() -> void:
	player = m.get("player")
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	if arg != "":
		hid = arg
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tsb-only="):
			_only = Array(a.get_slice("=", 1).split(","))
		elif a == "--tsb-air":
			_air = true
		elif a == "--tsb-side":
			_side_cam = true
		elif a == "--tsb-input":
			_input = true
		elif a.begins_with("--tsb-level="):
			_level = a.get_slice("=", 1)
		elif a.begins_with("--tsb-walk="):
			_walk = float(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	await wait(1.5)
	var host: Node3D = null
	if _level != "":
		# 新图里走查（看场景破坏）：进图后离开出生点的保护范围一段再摆木桩
		m.get("level_ui").set("mode", "solo")
		await m.call("_enter_level", _level)
		while bool(m.get("_switching")):
			await get_tree().process_frame
		host = m.get("level")
		if host == null:
			say("FAIL 进不了图 " + _level)
			get_tree().quit(1)
			return
		await wait(2.0)
		var f0: Vector3 = player.cam.flat_forward()
		var to := player.global_position + f0 * _walk
		to.y = float(player.cam.floor_fn.call(to.x, to.z)) + 0.2
		player.global_position = to
		player.velocity = Vector3.ZERO
		await wait(1.5)
	else:
		await m.call("_goto_test_hall")
		await wait(1.0)
		host = m.get("_hall_root")
	player.set_hero(hid)
	await wait(0.3)
	var fwd: Vector3 = player.cam.flat_forward()
	var side := fwd.cross(Vector3.UP).normalized()
	for k in 3:
		var d := EnemyDummy.new()
		d.kind = 1 if _air else 0
		d.max_hp = 1000000.0
		d.hp = d.max_hp
		d.position = player.global_position + fwd * 7.0 + side * (float(k - 1) * 3.4) + Vector3(0.0, 2.2 if _air else 0.0, 0.0) \
				+ fwd * (1.5 if k != 1 else 0.0)
		if _level != "":
			d.position.y = float(player.cam.floor_fn.call(d.position.x, d.position.z)) + (2.2 if _air else 0.0)
		host.add_child(d)
		dummies.append(d)
	await wait(0.4)
	say("英雄 %s（%s），基数 %.0f" % [hid, HeroDefs.hero_name(hid), player.hero_base()])
	if _only.has("gather"):
		await _gather()
	for ck: String in ["cs", "csu", "csd"]:
		if _only.has(ck):
			await _charge(ck, false)
	if _only.has("clash"):
		await _clash("clash", false, 1.0)
	if _only.has("clashw"):
		await _clash("clashw", false, 0.3)      # 对面那道只蓄了三成：不对冲，被我这道劈碎
	if _want("m1"):
		await _m1("m1", false)
	var keys := ["e", "z", "q", "r"]
	for i in 4:
		if _want(keys[i]):
			await _skill(i, keys[i], false)
	if _want("awk") or _want("ae") or _want("az") or _want("aq") or _want("ar") or _want("am1") or _only.has("acs") or _only.has("aclash"):
		await _awaken()
		if _want("am1"):
			await _m1("am1", true)
		if _only.has("acs"):
			await _charge("acs", true)
		if _only.has("aclash"):
			await _clash("aclash", true, 1.0)
		for i in 4:
			if _want("a" + keys[i]):
				_keep_awake()
				await _skill(i, "a" + keys[i], true)
	if _only.has("net"):
		await _net_ext_check()
	say("结束")
	await wait(0.4)
	get_tree().quit()


func _reset() -> void:
	for d: EnemyDummy in dummies:
		d.hp = d.max_hp
		d.alive = true
		d.position = d.home
		d.set("_kv", Vector3.ZERO)
		d.set("_koff", Vector3.ZERO)
	for i in 4:
		(player.kit.get("cds") as Array)[i] = 0.0
		(player.kit.get("cds_aw") as Array)[i] = 0.0
	player.mp = player.mp_max()


func _park(dist := 4.0) -> void:
	var d0: EnemyDummy = dummies[1]
	if player.st != Player.St.AIR:
		player.enter_air_combat()
	var to := d0.home
	var back: Vector3 = -player.cam.flat_forward()
	player.global_position = to + back * dist + Vector3(0.0, 0.6, 0.0)
	if _level != "":
		player.set_invuln(3.0)
	player.velocity = Vector3.ZERO
	player.face_now(atan2(-(to - player.global_position).x, -(to - player.global_position).z))
	player.air.target = d0
	var yaw := atan2(-(-back).x, -(-back).z)
	_yaw0 = yaw


func _dealt() -> String:
	var out: Array = []
	for d: EnemyDummy in dummies:
		out.append("%.2f" % ((d.max_hp - d.hp) / player.hero_base()))
	return " / ".join(out)


func _keep_awake() -> void:
	if player.air.awake_t <= 0.0:
		player.air.awaken = 100.0
		player.air.press_awaken()
	player.air.awake_t = maxf(player.air.awake_t, 8.0)


func _m1(tag: String, _aw: bool) -> void:
	_reset()
	_park(3.0)
	await wait(0.5)
	var chain: Array = player.air.ATK
	for k in chain.size():
		if player.st != Player.St.AIR:
			# 浏览器里头几帧在现编着色器、一帧好几百毫秒，摆好的人可能已经落回地面了（press_attack 只在空战里出手）
			player.enter_air_combat()
			player.air.target = dummies[1]
		player.air.press_attack()
		var mv: Dictionary = player.air._mv(str(chain[k]))
		await wait(float(mv["hit"]) + 0.03)
		await snap("%s_%d" % [tag, k + 1])
		await wait(maxf(float(mv["chain"]) if float(mv["chain"]) < 5.0 else 0.25, 0.12) - float(mv["hit"]) + 0.02)
	await wait(0.8)
	say("%s：打掉 %s 单位（中 / 左右），连击 %d" % [tag, _dealt(), player.air.combo])
	flush()
	await wait(0.6)


func _skill(i: int, tag: String, aw: bool) -> void:
	_reset()
	var chain: bool = i == 0 and player.kit.get("_e_k") != null      # 苍鸿的飞光 / 赤霄：连按的一串，站远一点看刀光飞
	_park((11.0 if chain else 5.0) if i != 1 else 3.0)
	await wait(0.5)
	if aw:
		_keep_awake()
	var name := str(player.kit.call("skill_name", i))
	var t0 := Time.get_ticks_msec()
	if _input:
		# 走真实的按键路径（触屏按钮 / 键盘都是发这几个动作）
		_fire(str(Player.SKILL_ACTIONS[i]), true)
		await get_tree().process_frame
		_fire(str(Player.SKILL_ACTIONS[i]), false)
	else:
		player.kit.call("press", i)
	var mv: Dictionary = player.air._atk
	var hit_t := float(mv.get("hit", 0.2))
	say("%s「%s」起手：招 %s，判定 %.2f 秒，状态 %s" % [tag, name, player.air.move_id, hit_t, player.air.state_name()])
	# 连拍：蓄势中一张；然后等判定那一帧（战斗时钟在长帧 / 顿帧时走得比真实时间慢，不能按真实时间掐），之后隔几帧一张
	await wait(maxf(hit_t * 0.5, 0.02))
	await snap(tag + "_0")
	var g0 := 0
	while not bool(player.air.get("_hit_done")) and player.air.state == player.air.A.ATTACK and g0 < 240:
		g0 += 1
		await get_tree().process_frame
	var th := Time.get_ticks_msec()
	var marks: Array = [0.02, 0.07, 0.14, 0.24, 0.38, 0.58, 0.9]
	if chain:
		marks = [0.02, 0.06, 0.12, 0.2, 0.3, 0.36, 0.44, 0.58, 0.66, 0.74, 0.9, 1.0, 1.15, 1.3, 1.45, 1.6, 1.75, 1.95] if aw else [0.02, 0.06, 0.12, 0.2, 0.3, 0.36, 0.44, 0.58, 0.66, 0.74, 0.9, 1.1]
		_chain_press()
	elif i == 3 and aw and player.kit.get("_e_k") != null:
		marks = [0.02, 0.07, 0.14, 0.3, 0.5, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.45, 1.7]      # 一线天：一直拍到齐断的那张冲击帧
	var k := 0
	while k < marks.size():
		if (Time.get_ticks_msec() - th) * 0.001 >= float(marks[k]):
			k += 1
			await snap("%s_%d" % [tag, k])
		else:
			await get_tree().process_frame
	# 等这一招彻底放完
	var guard := 0
	while player.air.state == player.air.A.ATTACK and guard < 300:
		guard += 1
		await get_tree().process_frame
	await wait(1.0)
	say("%s「%s」：打掉 %s 单位（中 / 左右），用时 %.2f 秒，冷却 %.1f，霸体扛 %d 下" % [tag, name, _dealt(),
			(Time.get_ticks_msec() - t0) * 0.001 - 1.0, float(player.kit.call("cd_ratio", i)) * float(player.kit.call("_cd_full", i, aw)), player.air.stat_armor])
	flush()
	await wait(0.5)


## 连按的技能（苍鸿 E）：这一串没放完就每隔 0.28 秒再按一下
func _chain_press() -> void:
	var guard := 0
	while int(player.kit.get("_e_k")) > 0 and guard < 12:
		guard += 1
		await wait(0.28)
		if int(player.kit.get("_e_k")) > 0:
			if _input:
				_fire(str(Player.SKILL_ACTIONS[0]), true)
				await get_tree().process_frame
				_fire(str(Player.SKILL_ACTIONS[0]), false)
			else:
				player.kit.call("press", 0)


## 蓄力（--tsb-only=cs / csu / csd / acs 才跑）：蓄满松手，连拍。cs 平、csu 上挑、csd 下劈，acs = 觉醒中的
func _charge(tag: String, aw: bool) -> void:
	_reset()
	_park(12.0)
	await wait(0.5)
	if aw:
		_keep_awake()
	var air := player.air
	air.demo_heavy("up" if tag == "csu" else ("down" if tag == "csd" else "fwd"), 0.75)
	await wait(0.45)
	await snap(tag + "_chg")
	var g := 0
	while air.state == air.A.CHARGE and g < 240:
		g += 1
		await get_tree().process_frame
	say("%s 松手：招 %s，状态 %s" % [tag, air.move_id, air.state_name()])
	g = 0
	while not bool(air.get("_hit_done")) and air.state == air.A.ATTACK and g < 240:
		g += 1
		await get_tree().process_frame
	var th := Time.get_ticks_msec()
	var marks: Array = [0.02, 0.08, 0.16, 0.26, 0.38, 0.52, 0.7, 0.9, 1.15, 1.4]
	var k := 0
	while k < marks.size():
		if (Time.get_ticks_msec() - th) * 0.001 >= float(marks[k]):
			k += 1
			await snap("%s_%d" % [tag, k])
		else:
			await get_tree().process_frame
	await wait(0.6)
	say("%s：打掉 %s 单位（中 / 左右），连击 %d" % [tag, _dealt(), air.combo])
	flush()
	await wait(0.4)


## 蓄力刀光对冲（--tsb-only=clash / clashw / aclash 才跑）：我蓄满放一道，同时在前面 22 米处迎面放一道「别人的」（只画的那种，
## 就是联机里对面放的那道在我这边的样子，蓄力 foe_k），连拍相持 → 黑白 → 炸开
func _clash(tag: String, aw: bool, foe_k: float) -> void:
	_reset()
	_park(16.0)
	await wait(0.5)
	if aw:
		_keep_awake()
	var air := player.air
	var kit: Node = player.kit
	var Cl: GDScript = load("res://scripts/heroes/cg_clash.gd")
	var n0 := int(Cl.get("played"))
	air.demo_heavy("fwd", 0.75)
	var g := 0
	while air.state == air.A.CHARGE and g < 240:
		g += 1
		await get_tree().process_frame
	g = 0
	while not bool(air.get("_hit_done")) and air.state == air.A.ATTACK and g < 240:
		g += 1
		await get_tree().process_frame
	var d: Vector3 = kit.call("aim_dir", air.target)
	# 平时那道不贯穿、会打在木桩上：放在木桩靠我这一侧（木桩在 16 米）；觉醒的贯穿，放远一点
	var from: Vector3 = player.center() + d * (22.0 if aw else 13.0)
	var sw: Vector3 = kit.call("cs_swing", -d, "fwd")
	kit.call("cs_wave", from, -d, sw, foe_k, aw, Realm.line_color(player.realm), null, Callable())
	var th := Time.get_ticks_msec()
	var marks: Array = [0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 0.95, 1.02, 1.1, 1.2, 1.35, 1.55, 1.8]
	var k := 0
	while k < marks.size():
		if (Time.get_ticks_msec() - th) * 0.001 >= float(marks[k]):
			k += 1
			await snap("%s_%02d" % [tag, k])
		else:
			await get_tree().process_frame
	await wait(0.6)
	say("%s：对冲了 %d 回（带镜头累计 %d），打掉 %s 单位，镜头接管 %.2f" % [tag, int(Cl.get("played")) - n0, int(Cl.get("cine_n")), _dealt(), player.cam.cine_k])
	flush()
	await wait(0.4)


## 攒气（--tsb-only=gather 才跑）：按住聚气 1.9 秒，每 0.1 秒拍一张（看灵气一圈圈往身上收）
func _gather() -> void:
	_reset()
	_park(5.0)
	await wait(0.5)
	player.air.awaken = 0.0
	player.air.demo_gather = true
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 1900 and n < 20:
		if Time.get_ticks_msec() - t0 >= n * 100:
			await snap("gather_%02d" % n)
			n += 1
		else:
			await get_tree().process_frame
	say("攒气：状态 %s，觉醒槽 %.0f" % [player.air.state_name(), player.air.awaken])
	player.air.demo_gather = false
	await wait(0.5)


func _awaken() -> void:
	_reset()
	_park(5.0)
	await wait(0.4)
	player.air.awaken = 100.0
	var ok := false
	if _input:
		_fire("gather", true)
		await get_tree().process_frame
		await get_tree().process_frame
		_fire("gather", false)
		ok = player.air.awake_t > 0.0
	else:
		ok = player.air.press_awaken()
	say("觉醒：%s，时长 %.1f 秒，M1 表 %s" % [str(ok), player.air.awake_t, str(player.air.ATK)])
	# 觉醒演出（awaken_cine.gd）：一秒多里蓄势 → 三张漫画帧 → 放开，隔 70 毫秒拍一张（留在内存里，演完再存）
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 2100 and n < 30:
		if Time.get_ticks_msec() - t0 >= n * 70:
			await snap("awk_%02d" % n)
			n += 1
		else:
			await get_tree().process_frame
	var AC: GDScript = load("res://scripts/awaken_cine.gd")
	say("觉醒演出：演了 %d 回，最近一回漫画帧画了 %d 帧，演完镜头接管 %.2f，无敌剩 %.2f 秒，觉醒剩 %.1f 秒；机位 %s" % [int(AC.get("played")), int(AC.get("last_frames")),
			player.cam.cine_k, float(player.air.get("_iframe")), player.air.awake_t, str(AC.get("dbg"))])
	flush()
	await wait(0.4)


## 真人打过来的那一下附带的东西（破防 / 硬直 / 冻结）在受击方生不生效：不起联机，直接照 net.gd 的 _hit 那样写 Combat.net_ext 再调受击。
## --tsb-only=net 才跑
func _net_ext_check() -> void:
	const Combat := preload("res://scripts/combat.gd")
	var air := player.air
	var src: EnemyDummy = dummies[1]
	_reset()
	_park(3.0)
	await wait(0.6)
	var fwd: Vector3 = air._fwd()
	var ev := {}
	player.melee.combat_event.connect(func(k: String, _i: Dictionary) -> void:
		ev[k] = int(ev.get(k, 0)) + 1)
	# 1 护体中挨一下普通的：挡下
	Input.action_press("guard")
	air.press_guard()
	await wait(0.4)      # 过了瞬身的窗口
	var r1: int = air.receive_attack(src, {"dmg": 5.0, "dir": -fwd, "kb": 4.0, "heavy": false, "contact": player.center() + fwd * 0.6})
	var st1: String = air.state_name()
	await wait(0.5)
	# 2 护体中挨一下带破防的（过网的附加表）：护体被破开
	if air.state != air.A.GUARD:
		air.press_guard()
		await wait(0.4)
	Combat.net_ext = {"brk": true}
	var r2: int = air.receive_attack(src, {"dmg": 5.0, "dir": -fwd, "kb": 4.0, "heavy": false, "contact": player.center() + fwd * 0.6})
	Combat.net_ext = {}
	var st2: String = air.state_name()
	Input.action_release("guard")
	air.release_guard()
	await wait(1.6)
	# 3 带硬直的一下：受击要定够 0.9 秒左右
	Combat.net_ext = {"pstun": 0.9}
	air.receive_attack(src, {"dmg": 3.0, "dir": -fwd, "kb": 2.0, "heavy": false, "contact": player.center()})
	Combat.net_ext = {}
	var d3: float = await _hurt_secs(3.0)
	await wait(1.2)
	# 4 带冻结的一下：定 1.2 秒、不被推走
	var p4 := player.global_position
	Combat.net_ext = {"freeze": 1.2}
	air.receive_attack(src, {"dmg": 3.0, "dir": -fwd, "kb": 9.0, "heavy": false, "contact": player.center()})
	Combat.net_ext = {}
	var d4: float = await _hurt_secs(4.0)
	var moved := player.global_position.distance_to(p4)
	# 5 不带附加的一下：还是原来的 0.34 秒左右
	await wait(1.2)
	air.receive_attack(src, {"dmg": 3.0, "dir": -fwd, "kb": 2.0, "heavy": false, "contact": player.center()})
	var d5: float = await _hurt_secs(3.0)
	say("过网附加：护体挡普通的=%d（%s）· 带破防=%d（%s）· 硬直 0.9 → 实际 %.2f 秒 · 冻结 1.2 → 实际 %.2f 秒（挪了 %.2f 米）· 不带 → %.2f 秒；事件 %s" % [r1, st1, r2, st2,
			d3, d4, moved, d5, str(ev)])
	var ok := r1 == 1 and st2 != st1 and int(ev.get("air_crushed", 0)) >= 1 and d3 > 0.6 and d4 > 0.9 and moved < 1.0 and d5 < 0.6
	say("过网附加 " + ("PASS" if ok else "FAIL"))


## 受击硬直持续了多久（按战斗时钟：每帧最多算 1/30 秒，和 Combat.cdt 一个口径）
func _hurt_secs(limit: float) -> float:
	var acc := 0.0
	while player.air.state == player.air.A.HURT and acc < limit:
		await get_tree().process_frame
		acc += minf(get_process_delta_time(), 1.0 / 30.0)
	return acc
