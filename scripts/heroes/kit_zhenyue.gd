extends "res://scripts/kit_base.gd"
## 英雄「镇岳」（体修，英雄 id "yujian"）的四个技能（2026-11-25 TSB 式重做）。招式数据在 def_zhenyue.gd，状态机是 air_melee.gd；
## 这里只管：按哪个键出哪一招、各招的画面（方块拳印 + 线条特效）、镇世那只从天上砸下来的拳印、场景破坏。
##   E 崩山 → 觉醒 碎星（一条线打穿）   Z 连环 → 千臂（一片）   Q 靠山 → 撞山   R 震岳 → 镇世（终结）
## 画面的联机同步：别人那边只画不判伤害，HeroFx.send(kind …) → 对面 remote_fx（号段 10 ~ 39）。
## 故意不写 class_name。

const GOLD := Color(1.0, 0.74, 0.28)
const ROCK: Array = [Color(0.5, 0.47, 0.42), Color(0.38, 0.36, 0.34), Color(0.62, 0.58, 0.5), Color(0.3, 0.29, 0.3)]

const BS_R := 12.0            # 崩山够得着多远（另加对手体型）
const LH_R := 6.0             # 连环：这么近才贴上去
const KAO_R := 9.0
const ZHUANG_R := 18.0
const ZS_R := 8.0             # 镇世：砸下来炸多大一圈
const ZS_DMG := 2.4
const ZS_H := 24.0            # 拳印从多高砸下来
const ZS_FALL := 0.34         # 砸到地用多久
const ZS_SIZE := 5.4          # 拳印多大（米）
## 联机画面号
const FX_FIST := 10           # 一只拳印：roll = 大小 × 100 + 飞多远
const FX_QUAKE := 11          # 震岳的一圈
const FX_STAR := 12           # 碎星
const FX_ZS := 13             # 镇世的天降拳印（pos = 落点）
const FX_BOOM := 14           # 撞山 / 推山的一炸

var _zs_n := 0


func _init() -> void:
	stat = {"fists": 0, "quake": 0, "star": 0, "zs": 0, "zs_hits": 0}


func _cast(i: int, aw: bool) -> bool:
	var air := player.air
	match i:
		0:
			if aw:
				return air.kit_move("zy_star", air.pick_target(), false, true)
			return air.kit_move("zy_bs", near_target(BS_R), true, false)
		1:
			if aw:
				return air.kit_move("zy_q1", air.pick_target(), false, true)
			return air.kit_move("zy_r1", near_target(LH_R), false, false)
		2:
			if aw:
				return air.kit_move("zy_zhuang", near_target(ZHUANG_R), true, false)
			return air.kit_move("zy_kao", near_target(KAO_R), true, false)
		3:
			if aw:
				return air.kit_move("zy_zs", air.pick_target(), false, true)
			return air.kit_move("zy_quake", null, false, false)
	return false


func _tick(_dt: float) -> void:
	if _awake() and player.st == Player.St.AIR and not player.dead:
		# 金身：通体一层鎏金的光，一呼一吸
		player.hero.set_glow(0.3 + 0.08 * sin(Time.get_ticks_msec() * 0.006), GOLD)


func on_awaken() -> void:
	super.on_awaken()


func on_awake_end() -> void:
	player.hero.set_glow(0.0, GOLD)


func _hand() -> Vector3:
	return player.melee.rig.hand_pos()


func _fist(pos: Vector3, dir: Vector3, size: float, travel: float, dur := 0.26) -> void:
	stat["fists"] = int(stat["fists"]) + 1
	HeroFx.fist(pos, dir, GOLD, size, travel, dur)
	HeroFx.send(player, FX_FIST, pos, dir, floorf(size * 100.0) + clampf(travel, 0.0, 99.0) * 0.01)


## air_melee 的招式到了 起手 / 判定：这一招的画面
func on_move_fx(tag: String, phase: String, _id: String, data: Dictionary) -> void:
	var air := player.air
	var c := player.center()
	var col := _col()
	var fwd: Vector3 = air._fwd()
	var cam := player.cam
	var hit := bool(data.get("hit", false))
	var pos: Vector3 = data.get("pos", c + fwd * 1.6)
	if phase == "start":
		match tag:
			"bs":
				Vfx.cast_charge(c + fwd * 0.2 + Vector3(0.0, -0.1, 0.0), col, 0.2)
				Sfx.play("fist_charge", -6.0, 1.9)
				cam.push_in(0.06)
			"kao":
				Vfx.dash_start(c, fwd, col, 0.8)
				Sfx.play("dodge", -4.0, 0.8)
			"zhuang":
				Vfx.dash_start(c, fwd, col, 1.4)
				Vfx.sonic_boom(c, fwd, col, 0.6, 1, player)
				Sfx.play("dodge", -2.0, 0.65)
				cam.fov_punch(7.0)
			"quake":
				Vfx.cast_charge(c + Vector3.UP * 1.1, col, 0.26)
				Sfx.play("fist_charge", -5.0, 1.6)
			"star":
				Vfx.cast_charge(c + fwd * 0.1, Color.WHITE.lerp(col, 0.5), 0.52)
				Vfx.sky_ring(c, col, 3.2, 0.5)
				Sfx.play("fist_charge", 0.0, 0.85)
				cam.push_in(0.2)
				cam.add_trauma(0.15)
			"zs":
				Sfx.play("fist_charge", 0.0, 0.7)
				cam.push_in(0.12)
				var aim := _zs_aim()
				Vfx.sky_ring(aim + Vector3.UP * ZS_H, GOLD, ZS_R * 0.9, 0.9)
				Vfx.sky_ring(Vector3(aim.x, floor_y(aim) + 0.15, aim.z), Color.WHITE.lerp(GOLD, 0.3), ZS_R, 0.9)
			"awk":
				Vfx.sky_ring(c, GOLD, 2.6, 0.5)
				if alt() < 4.0:
					var g := Vector3(c.x, floor_y(c), c.z)
					HeroFx.block_ring(g, 2.8, ROCK, 9, 0.55, 1.6, 0.7)
		return
	if phase != "hit":
		return
	match tag:
		"m4":
			if hit:
				_fist(pos - fwd * 1.2, fwd, 1.2, 2.6, 0.22)
		"am":
			_fist(c + fwd * 0.9, fwd, 1.25, 2.4, 0.2)
		"am4":
			_fist(c + fwd * 0.9, fwd, 2.1, 4.5, 0.26)
		"bs":
			_fist(c + fwd * 0.6, fwd, 2.3, 5.5, 0.3)
			Vfx.launch_ring(c + fwd * 1.0, fwd, col, 1.5)
			Sfx.play("fist_boom" if hit else "whoosh_fist", -2.0, 1.1 if hit else 0.7)
			cam.fov_punch(9.0)
			if hit:
				Vfx.space_ring(pos, 2.4, col, 0.4, 0.06)
				if alt() < 3.0:
					blast(Vector3(pos.x, floor_y(pos), pos.z), 2.4, 0.8, fwd)
		"lh":
			if hit:
				var side := fwd.cross(Vector3.UP).normalized()
				var o := side * randf_range(-0.9, 0.9) + Vector3.UP * randf_range(-0.5, 0.7)
				_fist(pos - fwd * 1.5 + o, fwd, 0.7, 1.5, 0.14)
		"palm":
			Vfx.launch_ring(c + fwd * 1.0, fwd, col, 1.3)
			if hit:
				_fist(pos - fwd * 1.0, fwd, 1.8, 3.6, 0.26)
				Sfx.play("slam", -3.0, 1.1)
		"kao":
			if hit:
				Vfx.space_ring(pos, 2.0, col, 0.35, 0.06)
				Vfx.shockwave(pos, fwd, Color.WHITE.lerp(col, 0.4), 1.6)
				Sfx.play("guard_break", -2.0, 0.95)
				cam.fov_punch(6.0)
		"zhuang":
			_boom(pos if hit else c + fwd * 1.5, fwd, 1.5)
			HeroFx.send(player, FX_BOOM, pos if hit else c + fwd * 1.5, fwd, 1.5)
			if hit or alt() < 3.0:
				blast(pos if hit else c + fwd * 2.0, 3.6, 1.2, fwd)
		"quake":
			_quake(c)
		"star":
			_star(c, air.aim_fwd())
		"qb":
			var side2 := fwd.cross(Vector3.UP).normalized()
			for k in (2 if Vfx.lite else 3):
				var o2 := side2 * randf_range(-3.0, 3.0) + Vector3.UP * randf_range(-1.4, 2.0)
				_fist(c + fwd * 1.0 + o2, (fwd * 6.0 - o2 * 0.5).normalized(), randf_range(1.0, 1.7), randf_range(3.0, 4.6), 0.2)
		"qb_end":
			_fist(c + fwd * 0.8, fwd, 3.4, 7.0, 0.32)
			_boom(c + fwd * 4.0, fwd, 1.3)
			HeroFx.send(player, FX_BOOM, c + fwd * 4.0, fwd, 1.3)
			cam.fov_punch(10.0)
			if alt() < 4.0:
				blast(Vector3(c.x, floor_y(c), c.z) + fwd * 4.0, 3.2, 1.0, fwd)
		"awk":
			Vfx.glint(c + fwd * 0.5, Color.WHITE.lerp(GOLD, 0.3), 1.8)
			Sfx.play("clash", -3.0, 0.7)
			cam.push_in(0.25)
			cam.fov_punch(-6.0)
			if alt() < 4.0:
				blast(Vector3(c.x, floor_y(c), c.z), 3.0, 0.9)


## 一炸：两圈震波 + 空间一荡 + 碎石
static func _boom(pos: Vector3, dir: Vector3, power: float) -> void:
	Vfx.shockwave(pos, dir, Color.WHITE.lerp(GOLD, 0.4), 2.0 * power)
	Vfx.shockwave(pos, Vector3.UP, GOLD, 1.6 * power)
	Vfx.space_ring(pos, 2.6 * power, GOLD, 0.45, 0.07)
	Vfx.debris(pos, dir + Vector3.UP * 0.6, ROCK, 10 if Vfx.lite else 20, 9.0 * power, 1.5)
	Sfx.play("fist_boom", -2.0, 0.95)


# ---------- 震岳 ----------

func _quake(c: Vector3) -> void:
	stat["quake"] = int(stat["quake"]) + 1
	var low := alt() < 5.0
	var g := Vector3(c.x, floor_y(c), c.z) if low else c - Vector3(0.0, 0.9, 0.0)
	_quake_fx(g, low, _col())
	HeroFx.send(player, FX_QUAKE, g, Vector3.UP, 1.0 if low else 0.0)
	player.cam.slam(1.0)
	player.cam.fov_punch(8.0)
	Sfx.play("quake", 0.0, 1.0)
	Sfx.play("punch_heavy", -2.0, 0.7)
	if low:
		blast(g, 4.2, 1.1)


static func _quake_fx(g: Vector3, low: bool, col: Color) -> void:
	Vfx.shockwave(g + Vector3.UP * 0.3, Vector3.UP, Color.WHITE.lerp(col, 0.3), 3.4)
	Vfx.sky_ring(g + Vector3.UP * 0.25, col, 7.0, 0.45)
	Vfx.space_ring(g + Vector3.UP * 0.8, 5.0, col, 0.5, 0.07)
	if low:
		HeroFx.block_ring(g, 3.0, ROCK, 10, 0.6, 1.7, 0.45)
		HeroFx.block_ring(g, 6.2, ROCK, 14, 0.45, 1.1, 0.3)
		Vfx.dust(g, 10 if Vfx.lite else 18, 9.0, 1.8)
	Vfx.line_sparks(g + Vector3.UP * 0.3, Vector3.UP, Color.WHITE.lerp(col, 0.4), 12 if Vfx.lite else 24, 22.0, 70.0, 0.45)


# ---------- 碎星 ----------

func _star(c: Vector3, dir: Vector3) -> void:
	stat["star"] = int(stat["star"]) + 1
	_star_fx(c, dir, _col())
	HeroFx.send(player, FX_STAR, c, dir, 0.0)
	var cam := player.cam
	cam.fov_punch(15.0)
	cam.kick_rush(1.2)
	Sfx.play("fist_boom", 2.0, 0.75)
	Sfx.play("quake", -3.0, 1.1)
	Combat.slowmo(0.3, 0.06, 0.25)
	# 犁一道沟：只犁贴着地的那一段（往下斜着打的会犁进地里，朝天打的不犁）
	var a := c + dir * 3.0
	var b := c + dir * 26.0
	var ga := floor_y(a)
	var gb := floor_y(b)
	if a.y - ga < 5.0 or b.y - gb < 5.0:
		trench(Vector3(a.x, minf(a.y, ga + 0.6), a.z), Vector3(b.x, minf(b.y, gb + 0.6), b.z), 2.4, 1.4)


static func _star_fx(c: Vector3, dir: Vector3, col: Color) -> void:
	HeroFx.fist(c + dir * 1.2, dir, GOLD, 5.2, 21.0, 0.42, 0.85)
	HeroFx.shock_line(c, dir, 26.0, col, 1.7)
	Vfx.launch_ring(c + dir * 1.5, dir, col, 2.6)
	Vfx.space_ring(c + dir * 4.0, 5.5, col, 0.6, 0.09)
	Vfx.rift(c + dir * 6.0, dir, col, 1.6, 0.4)


# ---------- 镇世 ----------

func _zs_aim() -> Vector3:
	var t: Node3D = player.air.target
	if t != null and Proj.alive(t):
		return Proj.aim_of(t)
	return player.center() + player.air._fwd() * 10.0


## air_melee 的招式到了判定时刻、而这一招是放「飞行道具」的（英雄表 proj 字段）：镇世的拳印从天上砸下来
func on_proj(kind: String, _move_id: String, t: Node3D) -> void:
	if kind != "zhenshi":
		return
	stat["zs"] = int(stat["zs"]) + 1
	var aim: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else _zs_aim()
	var g := floor_y(aim)
	# 目标离地不远就砸在地上（砸出坑）；在高空就砸在它身上
	var land := Vector3(aim.x, g, aim.z) if aim.y - g < 12.0 else aim
	_zs_fx(land, _col())
	HeroFx.send(player, FX_ZS, land, Vector3.DOWN, 0.0)
	Sfx.play("ult", -2.0, 0.7)
	_zs_n += 1
	var tw := player.create_tween()
	tw.tween_interval(ZS_FALL)
	tw.tween_callback(_zs_land.bind(land, aim.y - g < 12.0, _zs_n))
	player.air.end_awaken()


func _zs_land(land: Vector3, ground: bool, _n: int) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var cam := player.cam
	var near := clampf(1.0 - land.distance_to(player.center()) / 60.0, 0.3, 1.0)
	cam.slam(1.4 * near)
	cam.fov_punch(12.0 * near)
	Sfx.play("fist_boom", 3.0, 0.65)
	Sfx.play("quake", 0.0, 0.85)
	Sfx.play("rock_break", -2.0, 0.8)
	Combat.hitstop(0.12)
	var info := {"dmg": units(ZS_DMG), "kb": 34.0, "stun": 1.1, "launch": "down", "heavy": true, "brk": true, "ranged": true, "dir": Vector3.DOWN}
	stat["zs_hits"] = int(stat["zs_hits"]) + hit_area(land + Vector3.UP * 1.0, ZS_R, info)
	if ground:
		blast(land, 7.5, 1.8)


static func _zs_fx(land: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var top := land + Vector3.UP * ZS_H
	# 拳面朝下的一只大拳印（五米多宽）：砸到地就停在地面上、马上散掉（留久了镜头一靠近整屏都是它）
	var mi := HeroFx.block(HeroFx.fist_mesh(), top, Vector3.DOWN, Color.WHITE.lerp(GOLD, 0.72), 2.4, 0.62, false, Color(0.5, 0.3, 0.08, 0.4))
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", land + Vector3.UP * ZS_SIZE * 0.62, ZS_FALL).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "scale", Vector3.ONE * ZS_SIZE, ZS_FALL * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HeroFx.fade_out(mi, 0.16, ZS_FALL + 0.05)
	Vfx.sky_ring(top, GOLD, 7.0, 0.5)
	for k in 3:
		var at := top.lerp(land, 0.3 + 0.25 * float(k))
		var t2 := Vfx.root.create_tween()
		t2.tween_interval(ZS_FALL * (0.25 + 0.25 * float(k)))
		t2.tween_callback(Vfx.shockwave.bind(at, Vector3.DOWN, GOLD, 3.0))
	var t3 := Vfx.root.create_tween()
	t3.tween_interval(ZS_FALL)
	t3.tween_callback(_zs_boom.bind(land, col))


static func _zs_boom(land: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	Vfx.shockwave(land + Vector3.UP * 0.4, Vector3.UP, Color.WHITE.lerp(GOLD, 0.3), 4.5)
	Vfx.sky_ring(land + Vector3.UP * 0.3, GOLD, ZS_R * 1.15, 0.6)
	Vfx.space_ring(land + Vector3.UP * 1.5, 8.0, col, 0.7, 0.1)
	HeroFx.block_ring(land, 3.6, ROCK, 10, 0.7, 2.2, 0.5)
	HeroFx.block_ring(land, 7.0, ROCK, 14, 0.5, 1.4, 0.35)
	Vfx.debris(land + Vector3.UP * 0.5, Vector3.UP, ROCK, 16 if Vfx.lite else 34, 14.0, 2.0)
	Vfx.dust(land, 12 if Vfx.lite else 22, 11.0, 2.2)
	Vfx.line_sparks(land + Vector3.UP * 0.4, Vector3.UP, Color.WHITE.lerp(GOLD, 0.4), 14 if Vfx.lite else 30, 30.0, 75.0, 0.55)


# ---------- 别人那边只画（net.gd → hero_fx.gd 的 remote）----------

static func remote_fx(kind: int, pos: Vector3, dir: Vector3, roll: float, col: Color) -> void:
	match kind:
		FX_FIST:
			var size := floorf(roll) * 0.01
			var travel := (roll - floorf(roll)) * 100.0
			HeroFx.fist(pos, dir, GOLD, clampf(size, 0.3, 8.0), clampf(travel, 0.5, 30.0), 0.26)
		FX_QUAKE:
			_quake_fx(pos, roll > 0.5, col)
		FX_STAR:
			_star_fx(pos, dir, col)
		FX_ZS:
			_zs_fx(pos, col)
		FX_BOOM:
			_boom(pos, dir, clampf(roll, 0.5, 2.0))
