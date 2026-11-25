extends Node
## 英雄「御剑」的四个技能（2026-11-24，hero_defs.gd 的 yujian）：老角色那一套，按扁平数值收了收。
##   E 飞剑：点按一柄追踪飞剑；按住万剑连发（对着也在连发的对手 = 飞剑对波）。连发的按住时长由 air_melee 读 air_shot 动作，这里只管按下
##   Z 剑诀：紫霄雷法三式轮放（air_melee.press_art），三式共用冷却（英雄档 2.5 / 6 / 10 秒）
##   Q 飞剑阵：七柄飞剑环身自动索敌（sword_manager.gd），英雄档下 10 秒自动散、散了冷却 12 秒；开着再按收起
##   R 大罡剑阵：只有觉醒中能放（觉醒的终结技），放完觉醒结束（gate_array.gd 问 ult_ok）
## 地面上按也行：先腾空进空战（和「攻」一样）。
## 由 player.gd 建（set_hero）、player._unhandled_input 转按键（press / release）、player._process 调 tick。
## 故意不写 class_name：用 preload 引用。

const HeroDefs := preload("res://scripts/hero_defs.gd")
const Sfx := preload("res://scripts/sfx.gd")

const Q_DUR := 10.0
const Q_CD := 12.0

var player: Player
var _q_cd := 0.0
var _q_on := -1.0             # 飞剑阵开着多久了（-1 = 没开）
var log_lines: Array = []     # 自检用：放过的技能 [时刻, 第几个, 名字]


func detach() -> void:
	if _sm() != null and bool(_sm().get("active")):
		_sm().call("dismiss_all")


func _sm() -> Node:
	var s: Node = player.sword_mgr
	return s if s != null and is_instance_valid(s) else null


func _air() -> bool:
	if player.st == Player.St.AIR:
		return true
	return player.enter_air_combat()


func _deny() -> void:
	Vfx.cast_flash(player.center(), Color(0.55, 0.6, 0.7), 0.6)
	Sfx.play("block", -10.0, 0.7)


func _log(i: int) -> void:
	log_lines.append([Time.get_ticks_msec() * 0.001, i, skill_name(i)])
	if log_lines.size() > 64:
		log_lines.pop_front()


func press(i: int) -> void:
	if player.dead or player.is_downed():
		return
	match i:
		0:
			if _air():
				player.air.press_shot()
				_log(0)
		1:
			if _air():
				player.air.press_art()
				_log(1)
		2:
			_press_q()
		3:
			_press_r()


func release(_i: int) -> void:
	pass


func _press_q() -> void:
	var sm := _sm()
	if sm == null:
		return
	if bool(sm.get("active")):
		sm.call("dismiss_all")
		return
	if _q_cd > 0.0:
		_deny()
		return
	var before := player.mp
	sm.call("toggle_summon")
	if bool(sm.get("active")):
		_q_on = 0.0
		_log(2)
	elif player.mp >= before:
		pass      # 灵力不够，toggle_summon 自己闪过灰光了


## R：只有觉醒中能放（大罡剑阵，gate_array.gd 起手前问 ult_ok）
func _press_r() -> void:
	if not ult_ok():
		_deny()
		return
	player.ult.try_cast()
	if player.ult.active:
		player.air.end_awaken()      # 终结技：放了觉醒就结束
		_log(3)


func ult_ok() -> bool:
	return player.air.awake_t > 0.0


func tick(dt: float) -> void:
	var sm := _sm()
	var on := sm != null and bool(sm.get("active"))
	if _q_on >= 0.0:
		if on:
			_q_on += dt
			if _q_on >= Q_DUR:
				sm.call("dismiss_all")
				on = false
		if not on:
			_q_on = -1.0
			_q_cd = Q_CD
	elif _q_cd > 0.0:
		_q_cd = maxf(_q_cd - dt, 0.0)


# ---------- 给界面（触屏按钮 / 桌面技能框 / 大厅英雄页）----------

func skill_name(i: int) -> String:
	return str(HeroDefs.skill("yujian", i).get("name", ""))


## 第 i 个技能键的冷却比例（0 = 可用）
func cd_ratio(i: int) -> float:
	match i:
		1:
			return player.air.art_cd()
		2:
			return 0.0 if _q_on >= 0.0 else clampf(_q_cd / Q_CD, 0.0, 1.0)
	return 0.0


func skill_ready(i: int) -> bool:
	match i:
		0:
			return player.mp >= player.air.SHOT_MP
		1:
			return player.air.skill_ready(player.air.next_skill())
		2:
			return _q_on >= 0.0 or (_q_cd <= 0.0 and player.mp >= player.mp_max() * 0.12)
		3:
			return ult_ok() and player.can_ult() and player.mp >= player.mp_max() * player.ult.COST
	return true


## 触屏上这个技能键要不要露出来（R 只在觉醒中）
func btn_visible(i: int) -> bool:
	if i == 3:
		return ult_ok() and not player.ult.active
	return true


func touch_text(i: int) -> String:
	if i == 2 and _q_on >= 0.0:
		return "收"
	var t: Array = player.hero_def.get("touch", ["剑", "诀", "阵", "罡"])
	return str(t[i]) if i < t.size() else ""


func skill_info(i: int) -> Dictionary:
	var d := HeroDefs.skill("yujian", i).duplicate()
	d["cd_ratio"] = cd_ratio(i)
	d["ready"] = skill_ready(i)
	return d
