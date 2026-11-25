extends Node
## 英雄技能脚本的共用底子（2026-11-25 TSB 式重做）：四个技能键（E / Z / Q / R）的冷却、觉醒后换成另外四招、给界面的那套接口、范围判定的小工具。
## 各英雄的脚本（scripts/heroes/kit_*.gd）extends 这个文件，主要只写 _cast(i, awake) 和各招的画面。
##
## 英雄表（hero_defs.gd / scripts/heroes/def_*.gd）里技能条目的字段：
##   {key, name, desc, cd, mp（缺省 0：技能只看冷却）, awake_name / awake（觉醒后叫什么 / 说明）, awake_cd（觉醒那一招的冷却，缺省同 cd）}
##   英雄表的 touch = 触屏四个键上的字，touch_awake = 觉醒后的字
## 觉醒的四招各有各的冷却（和平时的分开记：一觉醒四招全都能放）；标了 finisher 的那一招放完觉醒结束。
## 由 player.gd 建（set_hero）、player._unhandled_input 转按键（press / release）、player._process 调 tick。
## 故意不写 class_name：用 preload / extends 路径引用。

const HeroDefs := preload("res://scripts/hero_defs.gd")
const Proj := preload("res://scripts/spell_projectile.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Combat := preload("res://scripts/combat.gd")
const HeroFx := preload("res://scripts/hero_fx.gd")

var player: Player
var cds: Array[float] = [0.0, 0.0, 0.0, 0.0]        # 平时四招的冷却
var cds_aw: Array[float] = [0.0, 0.0, 0.0, 0.0]     # 觉醒四招的冷却
var log_lines: Array = []     # 自检用：放过的技能 [时刻, 第几个, 名字]
var stat := {}
const BUFFER := 0.3          # 技能键的输入缓冲（秒）
var _buf_i := -1             # 缓冲着的那个技能键（-1 = 没有）
var _buf_t := 0.0


func detach() -> void:
	pass


func _awake() -> bool:
	return player.air.awake_t > 0.0


func _air() -> bool:
	if player.st == Player.St.AIR:
		return true
	return player.enter_air_combat()


func _def(i: int) -> Dictionary:
	return HeroDefs.skill(player.hero_id, i)


func _deny() -> void:
	Vfx.cast_flash(player.center(), Color(0.55, 0.6, 0.7), 0.6)
	Sfx.play("block", -10.0, 0.7)


func _col() -> Color:
	return Realm.line_color(player.realm)


func _log(i: int) -> void:
	log_lines.append([Time.get_ticks_msec() * 0.001, i, skill_name(i)])
	if log_lines.size() > 64:
		log_lines.pop_front()


func _cd_full(i: int, aw: bool) -> float:
	var d := _def(i)
	return float(d.get("awake_cd", d.get("cd", 1.0))) if aw else float(d.get("cd", 1.0))


func _cd_left(i: int, aw: bool) -> float:
	return cds_aw[i] if aw else cds[i]


## 冷却好了、灵力够
func _pay(i: int) -> bool:
	if _cd_left(i, _awake()) > 0.0 or player.mp < float(_def(i).get("mp", 0.0)):
		_deny()
		return false
	return true


func _commit(i: int, aw: bool) -> void:
	var mp := float(_def(i).get("mp", 0.0))
	if mp > 0.0:
		player.mp = maxf(player.mp - mp, 0.0)
		player.caster.hold_regen()
	if aw:
		cds_aw[i] = _cd_full(i, true)
	else:
		cds[i] = _cd_full(i, false)
	_log(i)
	player.melee.combat_event.emit("air_skill", {"idx": i, "name": skill_name(i), "pos": player.center()})


func press(i: int) -> void:
	if player.dead or player.is_downed() or player.ult.active:
		return
	if not _pay(i) or not _air():
		return
	var aw := _awake()
	if _cast(i, aw):
		_commit(i, aw)
		_buf_i = -1
	else:
		# 这会儿出不了招（上一拳还没打出去、挨打硬直……）：先记着，BUFFER 秒内一能出就出（手感：技能键按早了一点不该被吞掉）
		_buf_i = i
		_buf_t = BUFFER


func release(_i: int) -> void:
	pass


## 各英雄自己写：放第 i 个技能（aw = 觉醒中）。返回放没放出来
func _cast(_i: int, _aw: bool) -> bool:
	return false


func tick(dt: float) -> void:
	for i in 4:
		cds[i] = maxf(cds[i] - dt, 0.0)
		cds_aw[i] = maxf(cds_aw[i] - dt, 0.0)
	if _buf_i >= 0:
		_buf_t -= dt
		var aw := _awake()
		if _buf_t <= 0.0 or player.dead or player.is_downed():
			_buf_i = -1
			_deny()      # 等了一会儿还是出不了：这一下作废（冷却不转）
		elif player.st == Player.St.AIR and _cd_left(_buf_i, aw) <= 0.0 and _cast(_buf_i, aw):
			_commit(_buf_i, aw)
			_buf_i = -1
	_tick(dt)


func _tick(_dt: float) -> void:
	pass


## 觉醒那一下（air_melee._awaken 调）：觉醒四招全部就绪
func on_awaken() -> void:
	for i in 4:
		cds_aw[i] = 0.0


func on_awake_end() -> void:
	pass


# ---------- 小工具 ----------

## 够得着的目标：交战中的 / 镜头锁着的 / 最近的，离得不超过 r（另加体型）；没有返回 null
func near_target(r: float) -> Node3D:
	var t: Node3D = player.air.pick_target()
	if t == null or not Proj.alive(t):
		return null
	return t if Proj.aim_of(t).distance_to(player.center()) - Proj.body_r(t) <= r + 1.5 else null


## 朝哪打：有目标朝目标（带俯仰），没有就朝人面对的方向
func aim_dir(t: Node3D = null) -> Vector3:
	if t != null and Proj.alive(t):
		var d := Proj.aim_of(t) - player.center()
		if d.length_squared() > 0.01:
			return d.normalized()
	return player.air._fwd()


## 范围判定：center 周围 radius 米内的敌方各挨一下（info 同 air_hit：dmg / kb / stun / launch / heavy / brk / gd……dir 缺省 = 从 center 往外）。
## 返回打中了几个。skip = 这一下已经单独结算过的目标
func hit_area(center: Vector3, radius: float, info: Dictionary, skip: Array = []) -> int:
	var n := 0
	for e in Proj.targets(player.get_tree()):
		if skip.has(e) or not Proj.alive(e):
			continue
		var ec := Proj.aim_of(e)
		var d := ec - center
		if d.length() > radius + Proj.body_r(e):
			continue
		var one := info.duplicate()
		if not one.has("dir") or (one["dir"] as Vector3) == Vector3.ZERO:
			one["dir"] = d.normalized() if d.length_squared() > 0.01 else Vector3.UP
		one["contact"] = ec - (one["dir"] as Vector3) * minf(Proj.body_r(e), 0.8)
		if _hit_one(e, one) >= 0:
			n += 1
	return n


## 一条线上的判定（拳劲 / 剑气）：from 沿 dir 走 length 米、粗 width 米（半径）
func hit_line(from: Vector3, dir: Vector3, length: float, width: float, info: Dictionary, skip: Array = []) -> int:
	var n := 0
	var d := dir.normalized()
	for e in Proj.targets(player.get_tree()):
		if skip.has(e) or not Proj.alive(e):
			continue
		var ec := Proj.aim_of(e)
		var along := (ec - from).dot(d)
		if along < -1.0 or along > length + Proj.body_r(e):
			continue
		var off := (ec - from) - d * along
		if off.length() > width + Proj.body_r(e):
			continue
		var one := info.duplicate()
		if not one.has("dir") or (one["dir"] as Vector3) == Vector3.ZERO:
			one["dir"] = d
		one["contact"] = ec - d * minf(Proj.body_r(e), 0.8)
		if _hit_one(e, one) >= 0:
			n += 1
	return n


func _hit_one(e: Node3D, info: Dictionary) -> int:
	if not info.has("stun"):
		info["stun"] = 0.6
	if not info.has("kb"):
		info["kb"] = 6.0
	if not info.has("heavy"):
		info["heavy"] = false
	if not info.has("launch"):
		info["launch"] = ""
	if e.has_method("air_hit"):
		return int(e.call("air_hit", player, info))
	return Proj.hurt(player, e, float(info.get("dmg", 0.0)), info["dir"] as Vector3, _col(), bool(info["heavy"]))


## 场景破坏（scripts/destruct.gd，场景破坏那条线做的；文件还没有 / 关卡不支持时退回老的假坑特效）
static func _destruct() -> GDScript:
	if ResourceLoader.exists("res://scripts/destruct.gd"):
		return load("res://scripts/destruct.gd") as GDScript
	return null


## 这里炸一下：地形成坑、能碎的东西打碎。power 1 = 普通重手，1.5 以上 = 大招
func blast(pos: Vector3, radius: float, power := 1.0, dir := Vector3.ZERO) -> void:
	var d := _destruct()
	if d != null and d.has_method("blast"):
		d.call("blast", pos, radius, power, dir, {})
	else:
		Vfx.quake(pos, radius)


## 沿线犁一道沟
func trench(from: Vector3, to: Vector3, width: float, power := 1.0) -> void:
	var d := _destruct()
	if d != null and d.has_method("trench"):
		d.call("trench", from, to, width, power)
	else:
		var n := int(from.distance_to(to) / 5.0) + 1
		for i in n:
			Vfx.quake(from.lerp(to, float(i) / float(n)), width)


func floor_y(p: Vector3) -> float:
	return HeroFx.floor_y(player, p)


## 离地多高（脚底）
func alt() -> float:
	return player.global_position.y - floor_y(player.global_position)


## 几个招式单位合多少伤害（已含觉醒加成）
func units(u: float) -> float:
	return player.air._base() * u


# ---------- 给界面（触屏按钮 / 桌面技能框 / 大厅英雄页）----------

func skill_name(i: int) -> String:
	var d := _def(i)
	if _awake() and d.has("awake_name"):
		return str(d["awake_name"])
	return str(d.get("name", ""))


## 第 i 个技能键的冷却比例（0 = 可用）
func cd_ratio(i: int) -> float:
	var aw := _awake()
	return clampf(_cd_left(i, aw) / maxf(_cd_full(i, aw), 0.01), 0.0, 1.0)


func skill_ready(i: int) -> bool:
	return _cd_left(i, _awake()) <= 0.0 and player.mp >= float(_def(i).get("mp", 0.0))


func btn_visible(_i: int) -> bool:
	return true


func touch_text(i: int) -> String:
	var key := "touch_awake" if _awake() and player.hero_def.has("touch_awake") else "touch"
	var t: Array = player.hero_def.get(key, [])
	return str(t[i]) if i < t.size() else ""


func skill_info(i: int) -> Dictionary:
	var d := _def(i).duplicate()
	d["name"] = skill_name(i)
	d["cd_ratio"] = cd_ratio(i)
	d["ready"] = skill_ready(i)
	return d


## 桌面技能框「诀」那一格（hud.gd 照老接口问 air_melee，air_melee 转到这里）：显示 Z
func z_slot(field: String) -> Variant:
	match field:
		"name":
			return skill_name(1)
		"mp":
			return float(_def(1).get("mp", 0.0))
		"ready":
			return skill_ready(1)
		"cd":
			return cd_ratio(1)
	return null
