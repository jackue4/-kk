extends "res://scripts/kit_base.gd"
## 英雄「霜华」（冰修，第三位英雄，id "shuanghua"）的技能脚本（2026-11-25 TSB 式重做）。招式表在 def_shuanghua.gd，状态机是 air_melee.gd。
## 这里管：寒意 / 冻结 / 碎冰这套规则、四个技能（都是「到点交给脚本」的招：判定在这里做）、所有冰的画面（方块搭的冰棱 / 冰刺 / 冰块）。
##   E 冰锥 → 觉醒 连珠（三根）   Z 霜环 → 凛冬（一圈直接冻）   Q 冰棘 → 冰川   R 冰狱 → 永冻（终结，冰莲）
## 寒意：冰锥 +1、霜环 +2、冰棘 +1、M1 最后一掌 +1；CHILL_KEEP 秒不补全退；满 CHILL_MAX 层 = 冻结 FREEZE_T 秒；解冻后 FREEZE_IMMUNE 秒内不叠、也冻不住
## （只有终结技「永冻」无视这一条）。冻着的人挨她一记重手（M1 最后一掌 / 冰锥 / 冰棘）= 碎冰，多 SHATTER_U 个单位。
## 冻结怎么生效：命中 info 里带 freeze（真人：过网后在他那边的 air_melee._hurt 里定住）+ stun（AI / 怪认这个）；同一下不再击飞、不推人。
## 对真人：打没打中由对面结算，这边看不到「被护体挡下」—— 寒意 / 冰块是这边先画上的；他要是其实没被冻住（挡了 / 闪了），一动起来这边的冰就自己碎掉（_tick 里看位移）。
## 画面的联机同步：别人那边只画不判伤害，HeroFx.send(kind …) → 对面 remote_fx（号段 70 ~ 99）；被冻的人自己身上那块冰走 hero_fx.frozen_self → frozen_fx。
## 故意不写 class_name。

const HeroSkin := preload("res://scripts/hero_skin.gd")

const ICE := Color(0.62, 0.9, 1.0)
const DEEP := Color(0.34, 0.64, 0.96)
const FROST := Color(0.93, 0.98, 1.0)
const ICE_CHIPS: Array = [Color(0.72, 0.93, 1.0), Color(0.5, 0.78, 0.98), Color(0.93, 0.98, 1.0), Color(0.38, 0.64, 0.93)]

const CHILL_MAX := 3
const CHILL_KEEP := 6.0
const FREEZE_T := 1.2
const FREEZE_IMMUNE := 6.0
const SHATTER_U := 0.6        # 碎冰多打几个单位

const LANCE_RANGE := 46.0
const LANCE_SPD := 62.0
const LANCE_LIFE := 0.75
const LANCE_R := 0.85         # 冰锥擦到多近算中（另加对手体型）
const LANCE_DMG := 0.9
const LANCE3_DMG := 0.7
const NOVA_R := 6.0
const NOVA_DMG := 0.6
const NOVA2_R := 9.0
const NOVA2_DMG := 1.0
const SPIKE_N := 8            # 冰棘几簇
const SPIKE_GAP := 1.8        # 簇与簇隔多远（8 簇 ≈ 14 米）
const SPIKE_R := 1.7
const SPIKE_DMG := 0.9
const SPIKE_STEP := 0.04      # 一簇接一簇拱出来的间隔（秒）
const SPIKE2_N := 11          # 冰川：11 簇 × 2 米 ≈ 22 米
const SPIKE2_GAP := 2.0
const SPIKE2_R := 2.6
const SPIKE2_DMG := 1.6
const PRISON_RANGE := 26.0
const PRISON_R := 4.5
const PRISON_DELAY := 0.6     # 圈出来到炸开隔多久（躲的窗口）
const PRISON_DMG := 1.2
const PRISON_FREEZE := 1.4
const LOTUS_R := 9.0
const LOTUS_DMG := 2.4
const LOTUS_FREEZE := 2.0
## 联机画面号（70 ~ 99）
const FX_LANCE := 70          # 一根冰锥：pos 出手点，dir 方向
const FX_NOVA := 71           # 霜环 / 凛冬：roll = 半径（+100 = 凛冬）
const FX_SPIKES := 72         # 冰棘 / 冰川：pos 起点，dir 方向，roll = 簇数（+100 = 冰川；小数 .5 = 贴地）
const FX_PRISON := 73         # 冰狱：pos 圈心，roll 1 = 贴地
const FX_FREEZE := 74         # 有人被冻住了：pos 位置，roll = 秒数
const FX_LOTUS := 75          # 永冻的冰莲：pos 圈心，roll 1 = 贴地
const FX_SHATTER := 76        # 碎冰：pos 位置
const FX_BLOOM := 77          # 霜华绽那一捧冰棱：pos，dir，roll = 力度

var _chill := {}              # 目标的 instance id → {e, n 几层, t 还剩多久退, fz 还冻多久, imm 免疫还剩多久, pos 冻住时的位置, pips 头顶的小冰块, cage 身上那块冰}
var _claws: Array = []        # 两只手上的冰刃
var _claw_k := 0.0
var _fin_center := Vector3.ZERO
var _fin_ground := true
var _fin_ok := false
## 自检开关（命令行 `-- --sh-selftest`，配合 --tsb-show=shuanghua 用）：进空战后把寒意 / 冻结 / 碎冰 / 免疫那套规则对着一个临时木桩走一遍，
## 再让自己挨一下带 freeze 的（看 air_melee._hurt 定没定住、身上的冰出没出），打印 [shtest] 行
var _self_on := OS.get_cmdline_user_args().has("--sh-selftest")
var _self_done := false

## 冰的几种体块（名字 → ArrayMesh，整局只拼一次）记在 Vfx.root 的 meta 上，不用 static var（技能脚本里的静态变量攥着网格，退出时引擎会报资源没释放）
static func _mc() -> Dictionary:
	if Vfx.root == null or not is_instance_valid(Vfx.root):
		return {}
	if not Vfx.root.has_meta("sh_mesh"):
		Vfx.root.set_meta("sh_mesh", {})
	return Vfx.root.get_meta("sh_mesh")


func _init() -> void:
	stat = {"lances": 0, "lance_hits": 0, "novas": 0, "spikes": 0, "spike_hits": 0, "prisons": 0, "lotus": 0,
			"chills": 0, "freezes": 0, "shatters": 0}


func _ready() -> void:
	if player == null or player.hero == null:
		return
	# 两只手上的冰刃：顺着小臂往外长出去的三根冰棱，出手 / 交战时凝出来，闲下来化掉
	for hand: Node3D in [player.hero.hand_r, player.hero.hand_l]:
		if hand == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _claw_mesh()
		var m := HeroFx.block_mat(Color.WHITE.lerp(ICE, 0.7), 0.88)
		m.next_pass = HeroFx.outline_mat(Color(0.2, 0.44, 0.8), 0.7, 0.012)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		hand.add_child(mi)
		_claws.append(mi)
	# 觉醒描边要用的磨平网格趁换英雄这会儿算好（冰雪战士一万五千个顶点，别等觉醒那一下才算）
	var sk: Variant = player.hero.get("skin")
	if sk != null and is_instance_valid(sk):
		var ms: Variant = (sk as Object).get("_meshes")
		if ms is Array:
			for mm: Variant in (ms as Array):
				if mm is MeshInstance3D and (mm as MeshInstance3D).mesh != null:
					HeroSkin._smooth_mesh((mm as MeshInstance3D).mesh)


func detach() -> void:
	for mi: Variant in _claws:
		if is_instance_valid(mi):
			(mi as Node).queue_free()
	_claws.clear()
	for id: int in _chill.keys():
		_drop(_chill[id])
	_chill.clear()
	if player != null and is_instance_valid(player) and player.hero != null:
		player.hero.set_glow(0.0, ICE)


func _cast(i: int, aw: bool) -> bool:
	var air := player.air
	match i:
		0:
			return air.kit_move("sh_ae1" if aw else "sh_e", near_target(LANCE_RANGE), false, false)
		1:
			return air.kit_move("sh_az" if aw else "sh_z", null, false, false)
		2:
			var reach := (float(SPIKE2_N) * SPIKE2_GAP if aw else float(SPIKE_N) * SPIKE_GAP) + 6.0
			return air.kit_move("sh_aq" if aw else "sh_q", near_target(reach), false, false)
		3:
			return air.kit_move("sh_ar" if aw else "sh_r", near_target(PRISON_RANGE), false, false)
	return false


func _tick(dt: float) -> void:
	var airborne := player.st == Player.St.AIR and not player.dead
	if _self_on and not _self_done and airborne and player.air.state == player.air.A.IDLE:
		_selftest()
	if _awake() and airborne:
		# 玄冰之心：周身一层冰蓝的寒光（模型本身就白，光给轻一点、颜色给深一点，不然整个人糊成一团白）
		player.hero.set_glow(0.15 + 0.05 * sin(Time.get_ticks_msec() * 0.005), DEEP)
	# 冰刃：交战中凝出来
	var want := 1.0 if airborne and player.air.engaged() and not player.dun_active else 0.0
	_claw_k = move_toward(_claw_k, want, dt * (9.0 if want > 0.5 else 3.0))
	var grow := 1.0 + (0.9 if _awake() else 0.0)
	for mi: Variant in _claws:
		if not is_instance_valid(mi):
			continue
		var c := mi as MeshInstance3D
		c.visible = _claw_k > 0.02
		c.scale = Vector3(1.0, maxf(_claw_k, 0.02) * grow, 1.0)
	# 寒意 / 冻结
	var tnow := Time.get_ticks_msec() * 0.001
	for id: int in _chill.keys():
		var st: Dictionary = _chill[id]
		var e: Variant = st["e"]
		if not Proj.alive(e):
			_drop(st)
			_chill.erase(id)
			continue
		var en := e as Node3D
		st["imm"] = maxf(float(st["imm"]) - dt, 0.0)
		if float(st["fz"]) > 0.0:
			st["fz"] = float(st["fz"]) - dt
			var moved := Proj.aim_of(en).distance_to(st["pos"] as Vector3) > 1.6
			if moved or float(st["fz"]) <= 0.0:
				# 到点化掉 / 人已经动了（被别的重手打飞，或者真人那边其实没冻住）：冰碎掉
				st["fz"] = 0.0
				var cg: Variant = st["cage"]
				if is_instance_valid(cg):
					if moved:
						(cg as Cage).shatter()
					else:
						(cg as Cage).crumble()
				st["cage"] = null
		elif int(st["n"]) > 0:
			st["t"] = float(st["t"]) - dt
			if float(st["t"]) <= 0.0:
				st["n"] = 0
				_set_pips(st)
		# 头顶转着的小冰块 = 寒意几层
		var pips: Array = st["pips"]
		if not pips.is_empty():
			var top := Proj.aim_of(en) + Vector3.UP * (1.2 + 0.6 * Proj.body_r(en))
			for k in pips.size():
				var p: Variant = pips[k]
				if is_instance_valid(p):
					var a := tnow * 3.2 + TAU * float(k) / float(pips.size())
					(p as Node3D).global_position = top + Vector3(cos(a), 0.12 * sin(a * 2.0), sin(a)) * 0.42
					(p as Node3D).rotation = Vector3(a, a * 1.3, 0.0)
		if int(st["n"]) == 0 and float(st["fz"]) <= 0.0 and float(st["imm"]) <= 0.0:
			_drop(st)
			_chill.erase(id)


func on_awaken() -> void:
	super.on_awaken()
	Sfx.play("ult", -6.0, 1.35)


func on_awake_end() -> void:
	player.hero.set_glow(0.0, ICE)


func _selftest() -> void:
	_self_done = true
	var d := EnemyDummy.new()
	d.kind = 0
	d.max_hp = 1000000.0
	d.hp = d.max_hp
	Vfx.root.add_child(d)
	d.global_position = player.global_position + player.air._fwd() * -40.0
	var u := player.air._base()
	var rows: Array = [["轻 +1", 1, 0.0, false, false], ["轻 +1", 1, 0.0, false, false], ["轻 +1（该冻住）", 1, 0.0, false, false],
			["冻着挨轻的（不碎不叠）", 1, 0.0, false, false], ["重手（该碎冰 +0.6）", 1, 0.0, true, true], ["免疫期 +2（不叠）", 2, 0.0, false, false],
			["免疫期 冰狱直接冻（冻不住）", 0, PRISON_FREEZE, false, true], ["免疫期 永冻（无视免疫）", 0, LOTUS_FREEZE, false, true]]
	var ok := true
	var want: Array = [[1.0, 1, false], [2.0, 2, false], [3.0, 0, true], [4.0, 0, true], [5.6, 0, false], [6.6, 0, false], [7.6, 0, false], [8.6, 0, true]]
	for i in rows.size():
		var r: Array = rows[i]
		var info := {"dmg": u, "dir": Vector3.FORWARD, "kb": 3.0, "stun": 0.5, "heavy": bool(r[3]), "launch": "", "contact": d.aim_point()}
		var res := _strike(d, info, int(r[1]), float(r[2]), bool(r[4]))
		var dealt := (d.max_hp - d.hp) / u
		var w: Array = want[i]
		var good := absf(dealt - float(w[0])) < 0.02 and chill_of(d) == int(w[1]) and is_frozen(d) == bool(w[2])
		ok = ok and good
		print("[shtest] %d %s：结果 %d 累计 %.2f 单位 寒意 %d 冻着 %s 免疫 %s freeze=%.1f %s" % [i + 1, r[0], res, dealt, chill_of(d), str(is_frozen(d)),
				str(_immune(_entry(d))), float(info.get("freeze", 0.0)), "√" if good else "×"])
	# 自己挨一下带冻结的
	var pr := player.air.receive_attack(d, {"dmg": 1.0, "freeze": 1.0, "heavy": false, "kb": 6.0, "dir": Vector3.FORWARD, "contact": player.center()})
	var cages := 0
	for n: Node in Vfx.root.get_children():
		if n is Cage and (n as Cage).target == player:
			cages += 1
	var dur := float(player.air.get("_dur"))
	var push: Vector3 = player.air.get("_push")
	var pgood := pr == 0 and cages == 1 and absf(dur - 1.0) < 0.05 and push.length() < 0.01
	print("[shtest] 自己被冻：返回 %d 状态 %s 硬直 %.2f 秒 推力 %.1f 身上的冰 %d 块 %s" % [pr, player.air.state_name(), dur, push.length(), cages, "√" if pgood else "×"])
	print("[shtest] 结论 %s，统计 %s" % ["PASS" if ok and pgood else "FAIL", str(stat)])
	d.queue_free()


# ---------- 寒意 / 冻结 / 碎冰 ----------

func _entry(e: Node3D) -> Dictionary:
	if e == null or not is_instance_valid(e):
		return {}
	return _chill.get(e.get_instance_id(), {})


func _entry_new(e: Node3D) -> Dictionary:
	var id := e.get_instance_id()
	if not _chill.has(id):
		_chill[id] = {"e": e, "n": 0, "t": 0.0, "fz": 0.0, "imm": 0.0, "pos": Vector3.ZERO, "pips": [], "cage": null}
	return _chill[id]


func chill_of(e: Node3D) -> int:
	return int(_entry(e).get("n", 0))


func is_frozen(e: Node3D) -> bool:
	return float(_entry(e).get("fz", 0.0)) > 0.0


func _immune(st: Dictionary) -> bool:
	return float(st.get("imm", 0.0)) > 0.0


func _would_freeze(st: Dictionary, add: int) -> bool:
	return add > 0 and not _immune(st) and float(st.get("fz", 0.0)) <= 0.0 and int(st.get("n", 0)) + add >= CHILL_MAX


func _drop(st: Dictionary) -> void:
	for p: Variant in (st["pips"] as Array):
		if is_instance_valid(p):
			(p as Node).queue_free()
	(st["pips"] as Array).clear()
	var cg: Variant = st["cage"]
	if is_instance_valid(cg):
		(cg as Cage).crumble()
	st["cage"] = null


func _set_pips(st: Dictionary) -> void:
	var pips: Array = st["pips"]
	var n := int(st["n"])
	while pips.size() > n:
		var p: Variant = pips.pop_back()
		if is_instance_valid(p):
			(p as Node).queue_free()
	while pips.size() < n and HeroFx.ok():
		var e := st["e"] as Node3D
		var mi := HeroFx.block(HeroFx.cube_mesh(), Proj.aim_of(e) + Vector3.UP * 1.2, Vector3.FORWARD, Color.WHITE.lerp(ICE, 0.6), 0.2, 0.92,
				false, Color(FROST.r, FROST.g, FROST.b, 0.8))
		pips.append(mi)


func _add_chill(e: Node3D, n: int) -> void:
	if n <= 0 or not Proj.alive(e):
		return
	var st := _entry_new(e)
	if _immune(st) or float(st["fz"]) > 0.0:
		return
	st["n"] = mini(int(st["n"]) + n, CHILL_MAX - 1)
	st["t"] = CHILL_KEEP
	_set_pips(st)
	stat["chills"] = int(stat["chills"]) + n
	var at := Proj.aim_of(e)
	Vfx.glint(at + Vector3.UP * 0.6, FROST, 0.9)
	Sfx.play("ice_form", -9.0, 1.6)


func _freeze(e: Node3D, sec: float) -> void:
	if not Proj.alive(e):
		return
	var st := _entry_new(e)
	st["n"] = 0
	st["t"] = 0.0
	st["fz"] = sec
	st["imm"] = sec + FREEZE_IMMUNE
	st["pos"] = Proj.aim_of(e)
	_set_pips(st)
	var old: Variant = st["cage"]
	if is_instance_valid(old):
		(old as Node).queue_free()
	var size := 1.0 + 0.9 * Proj.body_r(e)
	st["cage"] = _spawn_cage(e, Proj.aim_of(e), sec, size)
	stat["freezes"] = int(stat["freezes"]) + 1
	var at: Vector3 = st["pos"]
	_freeze_fx(at, size)
	HeroFx.send(player, FX_FREEZE, at, Vector3.UP, sec)
	player.melee.combat_event.emit("hero_freeze", {"pos": at, "t": sec})


func _shatter(e: Node3D) -> void:
	var st := _entry(e)
	if st.is_empty():
		return
	st["fz"] = 0.0
	var cg: Variant = st["cage"]
	var at := Proj.aim_of(e) if Proj.alive(e) else (st["pos"] as Vector3)
	if is_instance_valid(cg):
		(cg as Cage).shatter()
	else:
		_shatter_fx(at, 1.0)
	st["cage"] = null
	stat["shatters"] = int(stat["shatters"]) + 1
	HeroFx.send(player, FX_SHATTER, at, Vector3.UP, 1.0)
	player.cam.add_trauma(0.25)
	Combat.hitstop(0.05)


## 脚本自己做判定的一下（四个技能都走这里）：按目标身上的寒意决定这一下是 叠寒意 / 冻住 / 碎冰。
## chill 叠几层 · force > 0 = 这一下直接冻这么久（解冻后的免疫期里冻不住；永冻除外）· crack = 这一下算重手，打在冰上碎冰加伤
func _strike(e: Node3D, info: Dictionary, chill: int, force := 0.0, crack := false) -> int:
	var st := _entry(e)
	var frozen := float(st.get("fz", 0.0)) > 0.0
	var fz := 0.0
	if not frozen:
		if force > 0.0 and (not _immune(st) or force >= LOTUS_FREEZE):
			fz = force
		elif _would_freeze(st, chill):
			fz = FREEZE_T
	var shatter := frozen and crack
	if shatter:
		info["dmg"] = float(info.get("dmg", 0.0)) + units(SHATTER_U)
	if fz > 0.0:
		info["freeze"] = fz
		info["stun"] = fz
		info["heavy"] = false
		info["launch"] = ""
		info["kb"] = 0.0
	var res := _hit_one(e, info)
	if res == 0 or res == 2:
		player.air.on_spell_hit(float(info.get("dmg", 0.0)))      # 计入连击数、攒觉醒槽（和拳脚命中一样）
		if fz > 0.0:
			_freeze(e, fz)
		elif shatter:
			_shatter(e)
		elif not frozen:
			_add_chill(e, chill)
	return res


## 这两点之间有没有墙（新图里技能隔着墙打不着；别的关卡恒通）
func _los(a: Vector3, b: Vector3) -> bool:
	if player.ex_level() == null:
		return true
	return player.solid_hit(a, b, 0.35, 0.3, 0.5) == Vector3.INF


func _near_k(p: Vector3) -> float:
	return clampf(1.0 - p.distance_to(player.center()) / 60.0, 0.3, 1.0)


func _last_res(id: String) -> int:
	var sh: Array = player.air.stat_hits
	if sh.is_empty():
		return -1
	var last: Array = sh.back()
	return int(last[2]) if str(last[0]) == id else -1


# ---------- air_melee 的招式到了 起手 / 判定：这一招的画面，M1 最后一掌换变体 ----------

func on_move_fx(tag: String, phase: String, id: String, data: Dictionary) -> void:
	var air := player.air
	var c := player.center()
	var fwd: Vector3 = air._fwd()
	var cam := player.cam
	if phase == "start":
		match tag:
			"s4":
				# 最后一掌出手的这一刻看目标：正冻着 → 碎冰；这一掌正好叠满 → 凝冰（不打飞）；否则照常把人推飞
				var t: Node3D = air.target
				if t != null and Proj.alive(t):
					var st := _entry(t)
					var nid := ""
					if float(st.get("fz", 0.0)) > 0.0:
						nid = id + "x"
					elif _would_freeze(st, 1):
						nid = id + "f"
					var mvs: Dictionary = player.hero_def.get("moves", {})
					if nid != "" and mvs.has(nid):
						air._atk = mvs[nid]
						air.move_id = nid
			"e":
				Vfx.glint(player.melee.rig.hand_pos(), FROST, 0.8)
			"z":
				Vfx.cast_charge(c, ICE, 0.16)
				Sfx.play("ascend", -10.0, 1.8)
			"q":
				Vfx.cast_charge(player.melee.rig.hand_pos(), ICE, 0.16)
				Sfx.play("ascend", -10.0, 1.6)
			"r":
				Sfx.play("ascend", -9.0, 1.4)
			"fin":
				_fin_begin()
			"awk":
				Vfx.sky_ring(c, ICE, 2.8, 0.5)
		return
	if phase != "hit":
		return
	var hit := bool(data.get("hit", false))
	var pos: Vector3 = data.get("pos", c + fwd * 1.6)
	var tgt: Variant = data.get("target", null)
	var landed := hit and tgt != null and is_instance_valid(tgt) and [0, 2].has(_last_res(id))
	match tag:
		"s":
			if hit:
				Vfx.debris(pos, fwd + Vector3.UP * 0.4, ICE_CHIPS, 3 if Vfx.lite else 5, 5.5, 0.8)
				Vfx.glint(pos, FROST, 0.8)
				Sfx.play("ice_spike", -10.0, 1.4)
		"s3":
			Vfx.crescent(c + fwd * 1.3, fwd, Color.WHITE.lerp(ICE, 0.5), 2.3)
			if hit:
				Vfx.debris(pos, fwd + Vector3.UP * 0.4, ICE_CHIPS, 4 if Vfx.lite else 7, 6.5, 0.9)
				Sfx.play("ice_spike", -8.0, 1.2)
		"s4":
			_bloom(c + fwd * 0.9, fwd, 1.0)
			if landed:
				_add_chill(tgt as Node3D, 1)
		"s4x":
			_bloom(c + fwd * 0.9, fwd, 1.35)
			if landed:
				_shatter(tgt as Node3D)
			cam.fov_punch(6.0)
		"s4f":
			_bloom(c + fwd * 0.9, fwd, 0.8)
			if landed:
				_freeze(tgt as Node3D, FREEZE_T)
		"awk":
			_nova_fx(c, 3.6, false)
			Sfx.play("ice_shatter", -4.0, 1.2)
			cam.push_in(0.22)
			cam.fov_punch(-6.0)
			if alt() < 4.0:
				blast(Vector3(c.x, floor_y(c), c.z), 2.6, 0.7)


## 霜华绽：一捧冰棱朝前炸开
func _bloom(at: Vector3, dir: Vector3, power: float) -> void:
	_bloom_fx(at, dir, power)
	HeroFx.send(player, FX_BLOOM, at, dir, power)
	Sfx.play("ice_shatter", -8.0, 1.5)


# ---------- air_melee 的招式到了判定时刻、而这一招是交给脚本放的（英雄表 proj 字段）----------

func on_proj(kind: String, move_id: String, t: Node3D) -> void:
	match kind:
		"lance":
			_fire_lance(t, LANCE_DMG, move_id)
		"lance3":
			_fire_lance(t, LANCE3_DMG, move_id)
		"nova":
			_nova(NOVA_R, NOVA_DMG, false)
		"nova2":
			_nova(NOVA2_R, NOVA2_DMG, true)
		"spikes":
			_spikes(t, false)
		"spikes2":
			_spikes(t, true)
		"prison":
			_prison(t)
		"lotus":
			_lotus()


# ---------- E 冰锥 / 连珠 ----------

func _fire_lance(t: Node3D, dmg_u: float, move_id: String) -> void:
	stat["lances"] = int(stat["lances"]) + 1
	var c := player.center()
	var fwd: Vector3 = player.air._fwd()
	var hand := player.melee.rig.left_hand_pos() if move_id == "sh_ae2" else player.melee.rig.hand_pos()
	var from := hand + fwd * 0.5
	if from.distance_to(c) > 2.5:
		from = c + fwd * 0.9      # 手的位置不对劲（模型还没摆好）就从胸前出
	var aim: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else c + fwd * 30.0
	var dir := aim - from
	dir = dir.normalized() if dir.length_squared() > 1e-4 else fwd
	var l := _make_lance(from, dir, false)
	if l != null:
		l.kit = self
		l.player = player
		l.dmg = units(dmg_u)
	HeroFx.send(player, FX_LANCE, from, dir, 0.0)
	Vfx.cast_flash(from, ICE, 0.7)
	Vfx.line_sparks(from, dir, FROST, 4 if Vfx.lite else 8, 26.0, 16.0, 0.22)
	Sfx.play("frost_wave", -6.0, 1.5)
	Sfx.play("ice_spike", -8.0, 1.3)
	player.cam.add_trauma(0.06)


## 冰锥打到人了（Lance 调）
func lance_hit(e: Node3D, at: Vector3, dir: Vector3, dmg: float) -> void:
	var info := {"dmg": dmg, "dir": dir, "kb": 5.0, "stun": 0.5, "heavy": false, "launch": "", "ranged": true, "contact": at}
	var res := _strike(e, info, 1, 0.0, true)
	if res == 0 or res == 2:
		stat["lance_hits"] = int(stat["lance_hits"]) + 1
		player.cam.add_trauma(0.12)


# ---------- Z 霜环 / 凛冬 ----------

func _nova(radius: float, dmg_u: float, big: bool) -> void:
	stat["novas"] = int(stat["novas"]) + 1
	var c := player.center()
	_nova_fx(c, radius, big)
	HeroFx.send(player, FX_NOVA, c, Vector3.UP, radius + (100.0 if big else 0.0))
	var cam := player.cam
	cam.add_trauma(0.45 if big else 0.3)
	cam.fov_punch(8.0 if big else 5.0)
	Sfx.play("frost_wave", -1.0, 0.85 if big else 1.1)
	Sfx.play("ice_shatter", -6.0, 1.3)
	for e in Proj.targets(player.get_tree()):
		var ec := Proj.aim_of(e)
		var d := ec - c
		if d.length() > radius + Proj.body_r(e) or not _los(c, ec):
			continue
		var flat := Vector3(d.x, 0.0, d.z)
		var dir := (flat.normalized() if flat.length_squared() > 0.01 else player.air._fwd()) + Vector3.UP * 0.25
		var info := {"dmg": units(dmg_u), "dir": dir.normalized(), "kb": 22.0 if big else 16.0, "stun": 0.55, "pstun": 0.5,
				"heavy": false, "launch": "", "contact": ec - dir.normalized() * minf(Proj.body_r(e), 0.8)}
		_strike(e, info, 0 if big else 2, FREEZE_T if big else 0.0)
	if alt() < 3.5:
		blast(Vector3(c.x, floor_y(c), c.z), radius * 0.42, 0.9 if big else 0.6)


# ---------- Q 冰棘 / 冰川 ----------

func _spikes(t: Node3D, big: bool) -> void:
	stat["spikes"] = int(stat["spikes"]) + 1
	var n := SPIKE2_N if big else SPIKE_N
	var gap := SPIKE2_GAP if big else SPIKE_GAP
	var c := player.center()
	var feet := player.global_position
	var fwd: Vector3 = player.air._fwd()
	var aim: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else c + fwd * 10.0
	# 自己和目标都离地不远：冰刺沿地面走（从地里拱出来）；否则在半空里朝目标一路结出去
	var ground := alt() < 4.0 and aim.y - floor_y(aim) < 4.5
	var dir: Vector3
	var start: Vector3
	if ground:
		var fd := Vector3(aim.x - feet.x, 0.0, aim.z - feet.z)
		dir = fd.normalized() if fd.length_squared() > 0.04 else fwd
		start = Vector3(feet.x, floor_y(feet), feet.z) + dir * 1.6
	else:
		dir = aim - c
		dir = dir.normalized() if dir.length_squared() > 0.04 else fwd
		start = c + dir * 1.8
	_spikes_fx(start, dir, n, gap, big, ground)
	HeroFx.send(player, FX_SPIKES, start, dir, float(n) + (100.0 if big else 0.0) + (0.5 if ground else 0.0))
	Sfx.play("ice_form", -3.0, 1.2 if not big else 0.9)
	player.cam.add_trauma(0.3 if big else 0.2)
	var cast := {"hit": {}, "any": false}
	for i in n:
		var tw := create_tween()
		tw.tween_interval(SPIKE_STEP * float(i) + 0.001)
		tw.tween_callback(_spike_hit.bind(start, dir, i, gap, big, ground, cast))
	if ground:
		var te := create_tween()
		te.tween_interval(SPIKE_STEP * float(n) + 0.05)
		te.tween_callback(trench.bind(start, start + dir * gap * float(n - 1), 1.8 if big else 1.0, 1.2 if big else 0.7))


func _spike_hit(start: Vector3, dir: Vector3, i: int, gap: float, big: bool, ground: bool, cast: Dictionary) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var p := start + dir * gap * float(i)
	if ground:
		p.y = floor_y(p)
	var rad := SPIKE2_R if big else SPIKE_R
	var done: Dictionary = cast["hit"]
	for e in Proj.targets(player.get_tree()):
		if done.has(e.get_instance_id()):
			continue
		var ec := Proj.aim_of(e)
		# 贴地：冰刺是一根竖着的东西（地面往上三四米都算）；半空：一团
		var near := Geometry3D.get_closest_point_to_segment(ec, p, p + Vector3.UP * (4.2 if big else 3.2)) if ground else p
		if near.distance_to(ec) > rad + Proj.body_r(e) or not _los(near + Vector3.UP * 0.3, ec):
			continue
		done[e.get_instance_id()] = true
		var kd := (Vector3.UP + dir * 0.35).normalized()
		var info := {"dmg": units(SPIKE2_DMG if big else SPIKE_DMG), "dir": kd, "kb": 30.0, "stun": 0.9, "heavy": true, "launch": "up",
				"contact": ec - Vector3.UP * minf(Proj.body_r(e), 0.8)}
		var res := _strike(e, info, 2 if big else 1, 0.0, true)
		if res == 0 or res == 2:
			stat["spike_hits"] = int(stat["spike_hits"]) + 1
			Vfx.impact(ec, dir.cross(Vector3.UP), ICE, 1)
			if not bool(cast["any"]):
				cast["any"] = true
				Combat.hitstop(0.07)
				player.cam.add_trauma(0.3 * _near_k(ec))
				Sfx.play("hit_heavy", -2.0, 1.15)


# ---------- R 冰狱 ----------

func _area_center(t: Node3D, max_alt: float) -> Array:
	var c := player.center()
	var aim: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else c + player.air._fwd() * 10.0
	var g := floor_y(aim)
	var ground := aim.y - g < max_alt
	return [Vector3(aim.x, g + 0.05, aim.z) if ground else aim, ground]


func _prison(t: Node3D) -> void:
	stat["prisons"] = int(stat["prisons"]) + 1
	var ac := _area_center(t, 3.0)
	var center: Vector3 = ac[0]
	var ground: bool = ac[1]
	_prison_fx(center, ground)
	HeroFx.send(player, FX_PRISON, center, Vector3.UP, 1.0 if ground else 0.0)
	var tw := create_tween()
	tw.tween_interval(PRISON_DELAY)
	tw.tween_callback(_prison_burst.bind(center, ground))


func _prison_burst(center: Vector3, ground: bool) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var k := _near_k(center)
	player.cam.add_trauma(0.4 * k)
	Sfx.play("ice_shatter", 0.0, 0.9)
	Sfx.play("slam", -5.0, 1.2)
	var mid := center + Vector3.UP * 1.2 if ground else center
	for e in Proj.targets(player.get_tree()):
		var ec := Proj.aim_of(e)
		# 贴地的冰晶是一簇立着的东西（四米高）：悬在两三米高的也罩得住
		var near := Geometry3D.get_closest_point_to_segment(ec, center + Vector3.UP * 0.6, center + Vector3.UP * 4.0) if ground else mid
		if ec.distance_to(near) > PRISON_R + Proj.body_r(e) or not _los(mid, ec):
			continue
		var info := {"dmg": units(PRISON_DMG), "dir": Vector3.UP, "kb": 0.0, "stun": 0.6, "heavy": false, "launch": "",
				"contact": ec - Vector3.UP * minf(Proj.body_r(e), 0.8)}
		if _immune(_entry(e)) and not is_frozen(e):
			# 刚解冻、冻不住的：冰晶把人顶上天
			info["heavy"] = true
			info["launch"] = "up"
			info["kb"] = 24.0
			info["stun"] = 0.9
		_strike(e, info, 0, PRISON_FREEZE, true)
	if ground:
		blast(center, 3.0, 0.9)


# ---------- 觉醒 R 永冻（终结）----------

## 起手：冰莲要开在哪先定下来（对手看得见那两圈、有 0.6 秒跑出去），放的时候就开在这儿
func _fin_begin() -> void:
	var ac := _area_center(player.air.target, 6.0)
	_fin_center = ac[0]
	_fin_ground = ac[1]
	_fin_ok = true
	Vfx.sky_ring(_fin_center + Vector3.UP * 0.1, ICE, LOTUS_R, 0.66)
	Vfx.sky_ring(_fin_center + Vector3.UP * 0.1, FROST, LOTUS_R * 0.55, 0.66)
	Vfx.cast_charge(player.center() + Vector3.UP * 1.3, FROST, 0.6)
	Sfx.play("ice_form", 0.0, 0.7)
	player.cam.push_in(0.14)


func _lotus() -> void:
	stat["lotus"] = int(stat["lotus"]) + 1
	if not _fin_ok:
		var ac := _area_center(player.air.target, 6.0)
		_fin_center = ac[0]
		_fin_ground = ac[1]
	_fin_ok = false
	var center := _fin_center
	_lotus_fx(center, _fin_ground)
	HeroFx.send(player, FX_LOTUS, center, Vector3.UP, 1.0 if _fin_ground else 0.0)
	var k := _near_k(center)
	var cam := player.cam
	cam.slam(1.2 * k)
	cam.fov_punch(12.0 * k)
	Sfx.play("ult", -2.0, 0.9)
	Sfx.play("ice_shatter", 2.0, 0.7)
	Sfx.play("slam", -1.0, 0.7)
	Combat.hitstop(0.1)
	Combat.slowmo(0.3, 0.08, 0.25)
	var mid := center + Vector3.UP * 1.5 if _fin_ground else center
	for e in Proj.targets(player.get_tree()):
		var ec := Proj.aim_of(e)
		var near := Geometry3D.get_closest_point_to_segment(ec, center + Vector3.UP * 0.6, center + Vector3.UP * 6.5) if _fin_ground else mid
		if ec.distance_to(near) > LOTUS_R + Proj.body_r(e) or not _los(mid, ec):
			continue
		var info := {"dmg": units(LOTUS_DMG), "dir": Vector3.UP, "kb": 0.0, "stun": 0.6, "heavy": false, "launch": "", "brk": true,
				"contact": ec - Vector3.UP * minf(Proj.body_r(e), 0.8)}
		_strike(e, info, 0, LOTUS_FREEZE, true)
	if _fin_ground:
		blast(center, 6.5, 1.6)
	player.air.end_awaken()


# ====================================================================================================================
# 画面（全是 static：出手方和别人那边画的是同一套）
# ====================================================================================================================

## 一根冰晶：从 base 沿 axis 长出去 h 米、根部粗 w，三截越来越细（方块搭的，截与截之间拧 45 度）
static func _crystal(st: SurfaceTool, base: Vector3, axis: Vector3, h: float, w: float, tint := Color.WHITE, twist := 0.0) -> void:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var b := Basis(x, y, z) * Basis(Vector3.UP, twist)
	# 四截：[从哪开始, 多长, 多粗, 再拧多少]（都按总长 / 根部粗细的比例），根部深蓝、越往尖上越白
	var segs := [[0.0, 0.34, 1.0, 0.0], [0.3, 0.3, 0.76, PI * 0.25], [0.56, 0.26, 0.52, 0.0], [0.78, 0.22, 0.28, PI * 0.25]]
	for i in segs.size():
		var s: Array = segs[i]
		var u := float(i) / 3.0
		var c := Color(tint.r * lerpf(0.56, 1.0, u), tint.g * lerpf(0.8, 1.0, u), tint.b)
		HeroFx.add_box(st, base + y * h * (float(s[0]) + float(s[1]) * 0.5), Vector3(w * float(s[2]), h * float(s[1]), w * float(s[2])),
				b * Basis(Vector3.UP, float(s[3])), c)


static func _mesh_done(key: String, st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	_mc()[key] = m
	return m


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## 手上的冰刃：顺着小臂（本地 -Y）长出去的三根冰棱
static func _claw_mesh() -> ArrayMesh:
	if _mc().has("claw"):
		return _mc()["claw"]
	var st := _begin()
	_crystal(st, Vector3(0.0, -0.04, 0.0), Vector3(0.0, -1.0, 0.0), 0.62, 0.075, Color(0.95, 0.98, 1.0))
	_crystal(st, Vector3(-0.055, -0.03, 0.0), Vector3(-0.2, -1.0, 0.0), 0.42, 0.06, Color(0.85, 0.94, 1.0), 0.5)
	_crystal(st, Vector3(0.055, -0.03, 0.0), Vector3(0.2, -1.0, 0.0), 0.42, 0.06, Color(0.85, 0.94, 1.0), 0.5)
	return _mesh_done("claw", st)


## 冰锥 / 冰棱：尖朝 -Z，长两米
static func _lance_mesh() -> ArrayMesh:
	if _mc().has("lance"):
		return _mc()["lance"]
	var st := _begin()
	_crystal(st, Vector3(0.0, 0.0, 1.1), Vector3.FORWARD, 2.4, 0.26, Color(0.95, 0.98, 1.0))
	HeroFx.add_box(st, Vector3(0.0, 0.0, 1.05), Vector3(0.44, 0.06, 0.26), Basis.IDENTITY, Color(0.7, 0.88, 1.0))
	HeroFx.add_box(st, Vector3(0.0, 0.0, 1.05), Vector3(0.06, 0.44, 0.26), Basis.IDENTITY, Color(0.7, 0.88, 1.0))
	return _mesh_done("lance", st)


## 一簇冰刺（从原点往上长，三种样子）
static func _spike_mesh(v: int) -> ArrayMesh:
	var key := "spike%d" % (v % 3)
	if _mc().has(key):
		return _mc()[key]
	var st := _begin()
	match v % 3:
		0:
			_crystal(st, Vector3(0.0, -0.2, 0.0), Vector3(0.1, 1.0, -0.22), 2.9, 0.66)
			_crystal(st, Vector3(-0.5, -0.2, 0.15), Vector3(-0.5, 1.0, -0.1), 1.7, 0.44, Color(0.86, 0.94, 1.0), 0.6)
			_crystal(st, Vector3(0.45, -0.2, -0.2), Vector3(0.42, 1.0, -0.35), 2.0, 0.48, Color(0.9, 0.96, 1.0), 0.3)
		1:
			_crystal(st, Vector3(0.1, -0.2, 0.0), Vector3(-0.16, 1.0, -0.26), 2.6, 0.6)
			_crystal(st, Vector3(0.55, -0.2, 0.1), Vector3(0.55, 1.0, 0.0), 1.9, 0.46, Color(0.86, 0.94, 1.0), 0.4)
			_crystal(st, Vector3(-0.4, -0.2, -0.25), Vector3(-0.3, 1.0, -0.45), 1.5, 0.4, Color(0.9, 0.96, 1.0), 0.8)
		_:
			_crystal(st, Vector3(-0.1, -0.2, 0.05), Vector3(0.0, 1.0, -0.34), 3.2, 0.7)
			_crystal(st, Vector3(0.4, -0.2, 0.2), Vector3(0.4, 1.0, 0.2), 1.6, 0.42, Color(0.86, 0.94, 1.0), 0.5)
			_crystal(st, Vector3(-0.5, -0.2, -0.1), Vector3(-0.48, 1.0, -0.2), 2.1, 0.5, Color(0.9, 0.96, 1.0), 0.2)
	return _mesh_done(key, st)


## 冻住人的那块冰：一整块歪着的冰坨（把人罩在里面）+ 脚边几根小冰棱
static func _cage_mesh() -> ArrayMesh:
	if _mc().has("cage"):
		return _mc()["cage"]
	var st := _begin()
	var tilt := Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.07)
	HeroFx.add_box(st, Vector3(0.0, -0.05, 0.0), Vector3(1.3, 2.1, 1.3), tilt, Color(0.72, 0.9, 1.0))
	HeroFx.add_box(st, Vector3(0.05, 1.12, 0.0), Vector3(0.9, 0.42, 0.9), tilt * Basis(Vector3.UP, PI * 0.25), Color(0.86, 0.95, 1.0))
	HeroFx.add_box(st, Vector3(0.0, 1.46, 0.05), Vector3(0.5, 0.4, 0.5), tilt, Color(1.0, 1.0, 1.0))
	HeroFx.add_box(st, Vector3(-0.04, 1.8, 0.02), Vector3(0.24, 0.36, 0.24), tilt * Basis(Vector3.UP, PI * 0.25), Color(1.0, 1.0, 1.0))
	_crystal(st, Vector3(0.62, -1.1, 0.3), Vector3(0.55, 1.0, 0.25), 1.3, 0.42, Color(0.86, 0.94, 1.0))
	_crystal(st, Vector3(-0.6, -1.1, 0.2), Vector3(-0.6, 1.0, 0.1), 1.1, 0.38, Color(0.86, 0.94, 1.0), 0.4)
	_crystal(st, Vector3(0.1, -1.1, -0.66), Vector3(0.05, 1.0, -0.6), 1.2, 0.4, Color(0.9, 0.96, 1.0), 0.7)
	return _mesh_done("cage", st)


## 冰狱：中间一根高的、外面一圈往里收的冰晶（像合拢的爪）
static func _prison_mesh() -> ArrayMesh:
	if _mc().has("prison"):
		return _mc()["prison"]
	var st := _begin()
	_crystal(st, Vector3(0.0, -0.3, 0.0), Vector3(0.04, 1.0, 0.03), 4.8, 1.3)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var o := Vector3(cos(a), 0.0, sin(a))
		var h := 3.0 + 0.8 * float(i % 2)
		_crystal(st, o * 2.7 + Vector3(0.0, -0.3, 0.0), Vector3.UP - o * 0.42, h, 0.86, Color(0.88, 0.95, 1.0), float(i) * 0.4)
	return _mesh_done("prison", st)


## 永冻的冰莲：当中一根七米多的冰柱，里外两圈往外张开的花瓣
static func _lotus_mesh() -> ArrayMesh:
	if _mc().has("lotus"):
		return _mc()["lotus"]
	var st := _begin()
	_crystal(st, Vector3(0.0, -0.4, 0.0), Vector3(0.03, 1.0, 0.02), 7.6, 1.9)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var o := Vector3(cos(a), 0.0, sin(a))
		_crystal(st, o * 2.3 + Vector3(0.0, -0.4, 0.0), Vector3.UP + o * 0.62, 5.2, 1.3, Color(0.9, 0.96, 1.0), float(i) * 0.5)
	for i in 9:
		var a2 := TAU * float(i) / 9.0 + 0.35
		var o2 := Vector3(cos(a2), 0.0, sin(a2))
		_crystal(st, o2 * 5.4 + Vector3(0.0, -0.4, 0.0), Vector3.UP + o2 * 1.05, 3.5, 1.0, Color(0.82, 0.92, 1.0), float(i) * 0.3)
	return _mesh_done("lotus", st)


## 一块冰（网格朝 dir，立着的网格给水平方向）。line_a = 亮边多亮
static func _ice(mesh: Mesh, pos: Vector3, dir: Vector3, size: float, alpha := 0.82, line_a := 0.85) -> MeshInstance3D:
	# 勾线用深一点的冰蓝（白边在浅色的冰上看不出来；和方块小人的勾线一个意思）
	return HeroFx.block(mesh, pos, dir, Color.WHITE.lerp(ICE, 0.72), size, alpha, false, Color(0.2, 0.44, 0.8, line_a * 0.85))


## 本机主角脚下那套地面查询（别人那边画贴地的冰刺也要落在本机的地面上）
static func _ground_y(p: Vector3) -> float:
	if not HeroFx.ok():
		return p.y
	var pl := Vfx.root.get_tree().get_first_node_in_group("player")
	return HeroFx.floor_y(pl, p) if pl != null else p.y


static func _make_lance(from: Vector3, dir: Vector3, visual: bool) -> Lance:
	if not HeroFx.ok():
		return null
	var l := Lance.new()
	l.dir = dir
	l.visual_only = visual
	var mi := MeshInstance3D.new()
	mi.mesh = _lance_mesh()
	var m := HeroFx.block_mat(Color.WHITE.lerp(ICE, 0.7), 0.9)
	m.next_pass = HeroFx.outline_mat(Color(0.2, 0.44, 0.8), 0.75, 0.035)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.add_child(mi)
	# 身后拖一道寒光（飞得快，光看那根冰锥一晃就过去了）
	var tail := MeshInstance3D.new()
	tail.mesh = HeroFx.cube_mesh()
	tail.material_override = HeroFx.block_mat(FROST, 0.42, true)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.scale = Vector3(0.08, 0.08, 4.2)
	tail.position = Vector3(0.0, 0.0, 3.2)
	l.add_child(tail)
	Vfx.root.add_child(l)
	l.global_position = from
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	l.look_at(from + dir, up)
	return l


static func _spawn_cage(target: Node3D, pos: Vector3, sec: float, size: float) -> Cage:
	if not HeroFx.ok():
		return null
	var cg := Cage.new()
	cg.target = target
	cg.life = sec
	cg.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = _cage_mesh()
	var m := HeroFx.block_mat(Color.WHITE.lerp(ICE, 0.85), 0.5)
	m.next_pass = HeroFx.outline_mat(Color(0.2, 0.44, 0.8), 0.5, 0.03)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cg.add_child(mi)
	Vfx.root.add_child(cg)
	cg.global_position = pos
	cg.rotation.y = randf() * TAU
	cg.scale = Vector3.ONE * size * 0.35
	var tw := cg.create_tween()
	tw.tween_property(cg, "scale", Vector3.ONE * size, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return cg


static func _freeze_fx(at: Vector3, size: float) -> void:
	Vfx.shockwave(at, Vector3.UP, FROST, 1.3 * size)
	Vfx.space_ring(at, 2.2 * size, ICE, 0.4, 0.05)
	Vfx.debris(at, Vector3.UP, ICE_CHIPS, 6 if Vfx.lite else 12, 6.0, 1.0)
	Sfx.play("ice_form", -2.0, 1.3)
	Sfx.play("perfect", -8.0, 1.5)


static func _shatter_fx(at: Vector3, size: float) -> void:
	Vfx.shockwave(at, Vector3.UP, FROST, 1.8 * size)
	Vfx.debris(at, Vector3.UP, ICE_CHIPS, 12 if Vfx.lite else 26, 11.0 * size, 1.5)
	Vfx.line_sparks(at, Vector3.UP, FROST, 8 if Vfx.lite else 16, 18.0, 80.0, 0.4)
	Vfx.glint(at, FROST, 1.6)
	Sfx.play("ice_shatter", 0.0, 1.15)


## 霜华绽：朝前炸开的一捧冰棱
static func _bloom_fx(at: Vector3, dir: Vector3, power: float) -> void:
	if not HeroFx.ok():
		return
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(d)
	var n := 3 if Vfx.lite else 5
	for i in n:
		var u := float(i) / float(n - 1) - 0.5
		var sd := (d + side * u * 1.1 + up * randf_range(-0.22, 0.34)).normalized()
		var sz := randf_range(0.5, 0.8) * power
		var mi := _ice(_lance_mesh(), at + sd * 0.3, sd, sz * 0.4, 0.88)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", at + sd * randf_range(2.4, 3.6) * power, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * sz, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		HeroFx.fade_out(mi, 0.14, 0.16)
	Vfx.shockwave(at + d * 0.5, d, FROST, 0.9 * power)
	Vfx.debris(at + d * 0.8, d + Vector3.UP * 0.3, ICE_CHIPS, 5 if Vfx.lite else 10, 9.0 * power, 1.0)


## 霜环 / 凛冬：一圈冰棱朝四周炸出去
static func _nova_fx(c: Vector3, radius: float, big: bool) -> void:
	if not HeroFx.ok():
		return
	Vfx.shockwave(c, Vector3.UP, FROST, 3.4 if big else 2.4)
	Vfx.sky_ring(c - Vector3.UP * 0.5, ICE, radius, 0.45)
	Vfx.space_ring(c, radius * 0.7, ICE, 0.45, 0.05)
	var n := (12 if Vfx.lite else 20) if big else (8 if Vfx.lite else 14)
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var d := Vector3(cos(a), randf_range(-0.12, 0.26), sin(a)).normalized()
		var sz := randf_range(0.7, 1.15) * (1.5 if big else 1.0)
		var mi := _ice(_lance_mesh(), c + d * radius * 0.22, d, sz * 0.45, 0.88)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", c + d * radius * randf_range(0.82, 1.0), 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * sz, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		HeroFx.fade_out(mi, 0.16, 0.2)
	Vfx.debris(c, Vector3.UP, ICE_CHIPS, 10 if Vfx.lite else 20, 10.0, 1.2)
	Vfx.line_sparks(c, Vector3.UP, FROST, 10 if Vfx.lite else 20, 20.0, 85.0, 0.4)


## 冰棘 / 冰川：n 簇冰刺沿 dir 一簇接一簇拱出来
static func _spikes_fx(start: Vector3, dir: Vector3, n: int, gap: float, big: bool, ground: bool) -> void:
	if not HeroFx.ok():
		return
	for i in n:
		var tw := Vfx.root.create_tween()
		tw.tween_interval(SPIKE_STEP * float(i) + 0.001)
		tw.tween_callback(_spike_pop.bind(start + dir * gap * float(i), dir, i, big, ground))


static func _spike_pop(p: Vector3, dir: Vector3, i: int, big: bool, ground: bool) -> void:
	if not HeroFx.ok():
		return
	var size := randf_range(0.85, 1.15) * (1.55 if big else 1.0) * (0.8 + 0.04 * float(mini(i, 8)))
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.FORWARD
	var mi: MeshInstance3D
	if ground:
		p.y = _ground_y(p)
		mi = _ice(_spike_mesh(i), p, flat.rotated(Vector3.UP, randf_range(-0.35, 0.35)), size)
	else:
		# 半空：整簇顺着去向斜着长（网格的「上」对着 去向 + 上）
		mi = _ice(_spike_mesh(i), p - Vector3.UP * size, flat, size)
		var yv := (dir + Vector3.UP * 0.8).normalized()
		var xv := yv.cross(flat)
		xv = xv.normalized() if xv.length_squared() > 1e-4 else Vector3.RIGHT
		mi.global_transform = Transform3D(Basis(xv, yv, xv.cross(yv)).scaled(Vector3.ONE * size), p - yv * size)
	var full := mi.scale
	mi.scale = Vector3(full.x, full.y * 0.06, full.z)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", full, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HeroFx.fade_out(mi, 0.22, 0.62 + 0.03 * float(i))
	if not Vfx.lite or i % 2 == 0:
		Vfx.debris(p + Vector3.UP * 0.4, Vector3.UP + flat * 0.4, ICE_CHIPS, 3 if Vfx.lite else 6, 7.0, 1.0 if not big else 1.3)
	if i % 2 == 0:
		Sfx.play("ice_spike", -7.0, 0.95 + 0.07 * float(i))
	if ground and (i % 3 == 0):
		Vfx.dust(p, 4, 4.0, 1.0)


## 冰狱：先两圈标记，PRISON_DELAY 秒后一簇冰晶合拢炸开
static func _prison_fx(center: Vector3, ground: bool) -> void:
	if not HeroFx.ok():
		return
	Vfx.sky_ring(center + Vector3.UP * 0.1, ICE, PRISON_R, PRISON_DELAY)
	Vfx.sky_ring(center + Vector3.UP * 0.1, FROST, PRISON_R * 0.5, PRISON_DELAY)
	Vfx.cast_charge(center + Vector3.UP * (1.2 if ground else 0.0), FROST, PRISON_DELAY)
	Sfx.play("ice_form", -4.0, 0.85)
	var tw := Vfx.root.create_tween()
	tw.tween_interval(PRISON_DELAY)
	tw.tween_callback(_prison_pop.bind(center, ground))


static func _prison_pop(center: Vector3, ground: bool) -> void:
	if not HeroFx.ok():
		return
	var base := center if ground else center - Vector3.UP * 1.6
	var mi := _ice(_prison_mesh(), base, Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU), 1.0, 0.6, 0.6)
	var full := mi.scale
	mi.scale = Vector3(full.x * 0.5, full.y * 0.05, full.z * 0.5)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", full, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HeroFx.fade_out(mi, 0.35, 0.55)      # 冰晶本身不留太久（挡视线）：人身上那块冰才是「还冻着」的标志
	var mid := base + Vector3.UP * 1.4
	Vfx.shockwave(mid, Vector3.UP, FROST, 2.6)
	Vfx.space_ring(mid, 4.2, ICE, 0.5, 0.06)
	Vfx.debris(mid, Vector3.UP, ICE_CHIPS, 12 if Vfx.lite else 24, 11.0, 1.4)
	Vfx.line_sparks(mid, Vector3.UP, FROST, 10 if Vfx.lite else 20, 22.0, 80.0, 0.45)
	var t2 := Vfx.root.create_tween()
	t2.tween_interval(0.8)
	t2.tween_callback(_crumble_fx.bind(mid, 1.6))


## 一大块冰到点化掉：碎屑落下来
static func _crumble_fx(at: Vector3, size: float) -> void:
	if not HeroFx.ok():
		return
	Vfx.debris(at, Vector3.UP * 0.4, ICE_CHIPS, 8 if Vfx.lite else 16, 5.0 * size, 1.2)
	Sfx.play("ice_shatter", -9.0, 1.5)


## 永冻：一朵九米的冰莲从地里（半空就在脚下）绽开
static func _lotus_fx(center: Vector3, ground: bool) -> void:
	if not HeroFx.ok():
		return
	var base := center if ground else center - Vector3.UP * 2.4
	var mi := _ice(_lotus_mesh(), base, Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU), 1.0, 0.6, 0.55)
	var full := mi.scale
	mi.scale = Vector3(full.x * 0.3, full.y * 0.04, full.z * 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", full, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HeroFx.fade_out(mi, 0.5, 0.65)
	var mid := base + Vector3.UP * 1.6
	Vfx.shockwave(mid, Vector3.UP, FROST, 4.6)
	Vfx.sky_ring(base + Vector3.UP * 0.3, ICE, LOTUS_R * 1.1, 0.7)
	Vfx.space_ring(mid, 8.5, ICE, 0.7, 0.09)
	if ground:
		HeroFx.block_ring(base, LOTUS_R * 0.9, ICE_CHIPS, 14, 0.7, 1.8, 0.5)
		Vfx.dust(base, 10 if Vfx.lite else 20, 11.0, 2.0)
	Vfx.debris(mid, Vector3.UP, ICE_CHIPS, 16 if Vfx.lite else 36, 15.0, 1.9)
	Vfx.line_sparks(mid, Vector3.UP, FROST, 14 if Vfx.lite else 30, 30.0, 80.0, 0.55)
	var t2 := Vfx.root.create_tween()
	t2.tween_interval(1.05)
	t2.tween_callback(_crumble_fx.bind(mid + Vector3.UP * 1.5, 2.6))


# ---------- 别人那边只画（net.gd → hero_fx.gd 的 remote）----------

static func remote_fx(kind: int, pos: Vector3, dir: Vector3, roll: float, _col: Color) -> void:
	match kind:
		FX_LANCE:
			_make_lance(pos, dir, true)
			Vfx.cast_flash(pos, ICE, 0.7)
		FX_NOVA:
			var big := roll >= 100.0
			_nova_fx(pos, clampf(roll - (100.0 if big else 0.0), 2.0, 12.0), big)
		FX_SPIKES:
			var bigs := roll >= 100.0
			var r := roll - (100.0 if bigs else 0.0)
			var n := clampi(int(floorf(r)), 1, 16)
			_spikes_fx(pos, dir, n, SPIKE2_GAP if bigs else SPIKE_GAP, bigs, r - floorf(r) > 0.25)
		FX_PRISON:
			_prison_fx(pos, roll > 0.5)
		FX_FREEZE:
			# 被冻的就是本机主角：身上那块冰由 frozen_fx 画（真冻住了才有），这里不再叠一块
			var me := Vfx.root.get_tree().get_first_node_in_group("player") if HeroFx.ok() else null
			if me != null and me.has_method("center") and (me.call("center") as Vector3).distance_to(pos) < 1.6:
				return
			_spawn_cage(null, pos, clampf(roll, 0.2, 2.5), 1.0)
			_freeze_fx(pos, 1.0)
		FX_LOTUS:
			_lotus_fx(pos, roll > 0.5)
		FX_SHATTER:
			_shatter_fx(pos, 1.0)
		FX_BLOOM:
			_bloom_fx(pos, dir, clampf(roll, 0.5, 2.0))


## 自己被冻住了（hero_fx.frozen_self → 这里）：身上那块冰跟着自己，到点化掉
static func frozen_fx(pl: Node, sec: float) -> void:
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return
	var at: Vector3 = (pl as Node3D).global_position + Vector3.UP * 1.0
	if pl.has_method("center"):
		at = pl.call("center")
	_spawn_cage(pl as Node3D, at, sec, 1.0)
	_freeze_fx(at, 1.0)


# ====================================================================================================================
# 冰锥：自己飞、自己判定；别人那边的只画（visual_only）
# ====================================================================================================================
class Lance extends Node3D:
	const P := preload("res://scripts/spell_projectile.gd")
	const S := preload("res://scripts/sfx.gd")
	var kit: Node = null
	var player: Player = null
	var dir := Vector3.FORWARD
	var dmg := 10.0
	var visual_only := false
	var _t := 0.0
	var _probe: Player = null      # 挡墙用（新图没有物理碰撞体，问 player.solid_hit）：出手方 = player，别人那边只画的 = 本机主角

	func _ready() -> void:
		_probe = player if player != null and is_instance_valid(player) else get_tree().get_first_node_in_group("player") as Player

	func _process(dt: float) -> void:
		_t += dt
		if _probe == null and player != null and is_instance_valid(player):
			_probe = player
		var from := global_position
		var to := from + dir * LANCE_SPD * dt
		# 这一帧能飞到哪：先看墙（新图的实心格 / 物理碰撞体），再在这一段里找人 —— 先找人再碎在墙上
		# （帧很长的时候一步十几米：对手自己的碰撞体也会挡住射线，先判墙的话这一下就白飞了）
		var stop := to
		var blocked := false
		if _probe != null and is_instance_valid(_probe):
			var wall := _probe.solid_hit(from, to, 0.4)
			if wall != Vector3.INF:
				stop = wall
				blocked = true
		if not visual_only and player != null and is_instance_valid(player):
			var q := PhysicsRayQueryParameters3D.create(from, stop, 1)
			q.exclude = [player.get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				stop = hit["position"] as Vector3
				blocked = true
			if _sweep(from, stop + dir * 0.3):
				return
		if blocked:
			_break(stop)
			return
		global_position = to
		rotate_object_local(Vector3.FORWARD, dt * 9.0)      # 一边飞一边自转
		if _t >= LANCE_LIFE:
			Vfx.glint(to, FROST, 0.7)
			queue_free()

	func _sweep(from: Vector3, to: Vector3) -> bool:
		for e in P.targets(player.get_tree()):
			var ap := P.aim_of(e)
			var cp := Geometry3D.get_closest_point_to_segment(ap, from, to)
			if cp.distance_to(ap) > LANCE_R + P.body_r(e):
				continue
			if _probe != null and is_instance_valid(_probe) and _probe.solid_hit(cp, ap, 0.35, 0.0, 0.5) != Vector3.INF:
				continue      # 新图：擦到了，但人在墙 / 楼板后面
			if kit != null and is_instance_valid(kit):
				kit.call("lance_hit", e, ap - dir * minf(P.body_r(e), 0.8), dir, dmg)
			_break(cp)
			return true
		return false

	func _break(at: Vector3) -> void:
		Vfx.debris(at, -dir + Vector3.UP * 0.3, ICE_CHIPS, 4 if Vfx.lite else 8, 7.0, 0.9)
		Vfx.line_sparks(at, -dir, FROST, 6, 12.0, 60.0, 0.3)
		Vfx.glint(at, FROST, 1.0)
		S.play("shatter", -8.0, 1.8)
		queue_free()


# ====================================================================================================================
# 冻住人的那块冰：跟着目标（没有目标就原地），到点化掉（crumble）；被重手打碎（shatter）
# ====================================================================================================================
class Cage extends Node3D:
	const P := preload("res://scripts/spell_projectile.gd")
	const S := preload("res://scripts/sfx.gd")
	var target: Node3D = null
	var life := 1.2
	var size := 1.0
	var _t := 0.0
	var _gone := false

	func _process(dt: float) -> void:
		if _gone:
			return
		_t += dt
		if target != null:
			if not is_instance_valid(target):
				crumble()
				return
			global_position = P.aim_of(target) if (target is EnemyDummy or target.has_method("center")) else target.global_position + Vector3.UP
		if life - _t < 0.3:
			rotation.z = sin(_t * 70.0) * 0.035      # 快化了：抖两下
		if _t >= life:
			crumble()

	func crumble() -> void:
		if _gone:
			return
		_gone = true
		Vfx.debris(global_position, Vector3.UP * 0.5, ICE_CHIPS, 6 if Vfx.lite else 12, 5.0 * size, 1.1)
		S.play("shatter", -9.0, 1.6)
		queue_free()

	func shatter() -> void:
		if _gone:
			return
		_gone = true
		Vfx.shockwave(global_position, Vector3.UP, FROST, 1.8 * size)
		Vfx.debris(global_position, Vector3.UP, ICE_CHIPS, 12 if Vfx.lite else 26, 11.0 * size, 1.5)
		Vfx.line_sparks(global_position, Vector3.UP, FROST, 8 if Vfx.lite else 16, 18.0, 80.0, 0.4)
		Vfx.glint(global_position, FROST, 1.6)
		S.play("shatter", 0.0, 1.25)
		queue_free()


## 开机预热用（warmup.gd 可以把这几个节点摆一下再删）：冰的几种材质（半透体块 / 勾线 / 加色的拖尾）头一回进画面要现编着色器，
## 不预热的话开局第一根冰锥、第一次冻人会卡一下。返回的节点还没进树
static func warm_nodes() -> Array:
	var out: Array = []
	for mesh: Mesh in [_lance_mesh(), _cage_mesh(), _spike_mesh(0)]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := HeroFx.block_mat(Color.WHITE.lerp(ICE, 0.7), 0.6)
		m.next_pass = HeroFx.outline_mat(Color(0.2, 0.44, 0.8), 0.7, 0.03)
		mi.material_override = m
		out.append(mi)
	var tail := MeshInstance3D.new()
	tail.mesh = HeroFx.cube_mesh()
	tail.material_override = HeroFx.block_mat(FROST, 0.42, true)
	out.append(tail)
	return out
