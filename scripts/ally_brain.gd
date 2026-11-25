extends RefCounted
## AI 道友的「大脑」（2026-11-20 重做。用户反馈：「联机时的 AI 太呆了，一直跟随在玩家旁边……请重做成真实能用、能模拟真人玩家表现的 AI，
## 不要只是贴身跟随；结合游戏现有玩法，让它能自主行动、选择目标并合理战斗」）。
## 原来的 AI 道友（air_foe.gd 里 ally = true 的那段）：没怪就回到主角身侧那个固定站位，只打主角 34 米内的怪，打不死、不会躲。
## 现在每个 AI 道友挂一个这个对象（raid_manager.gd 的 _spawn_ally → ally_team.gd 的 attach），air_foe.gd 的 _tick_roam / mob_hit 交给它：
##   · 自己找事做（SCOUT）：往队友前进的方向前面去探、在队友周围十几到几十米换地方转、去探没搜过的搜点（探到就标在小地图上、喊一声）
##   · 自己选目标（FIGHT）：正贴着队友打的怪最优先，其次冲着自己来的、残血的、离得近的；别的 AI 道友已经在打的小怪往后排（分头打）；
##     首领要队友已经跟它交上手才上；手上这只有加权，不来回换；正在围攻主角的红名 AI 修士也帮着打
##   · 像人一样打：靠近时带一点横移绕着打，四下一套、最后一下重，套与套之间挪个位；目标起手（怪的 WIND）时按水平有几成会后撤闪开；
##     隔着七到二十几米先放一道剑气；身边怪多 / 打精英、首领时隔一阵放一次范围的剑轮
##   · 会受伤、会撤（RETREAT）：血到三四成就脱战拉开、服丹回一口再回来；被打空了血「重伤遁走」，十来秒后回到队友身边（DOWN）
##   · 跟队但不贴身（REGROUP）：离队友超过各自的牵引距离、或队友御剑飞远了才追，追到十几米内就散开各忙各的
##   · 看场合：队友渡劫时退到二十米外看着（WATCH），队友读条撤离时过来一起走（EXTRACT）
##   · 三种性子（kind，按第几个道友轮着来）：0 冲锋（感知远、敢打精英、血很低才撤）1 稳健（离队近、早撤）2 探路（走得远、爱去探搜点）
##   · 头顶偶尔冒一句话（SAY），十几秒最多一句
## 「队友」是谁：ally_team.gd 把同队的真人（本机主角 + 别人的木偶）轮着分给各个 AI 道友当 anchor。
## 联机：AI 道友只在本队编号最小的那位真人机器上算（ally_team.gd 的 is_owner），其余人看到的是木偶（ally_puppet.gd）。
## 自检：`-- --raid-shot --raid-ally [--ally-old] [--touch]`（ally_selftest.gd）。
## 故意不写 class_name：用 preload 引用。

const AirFoe := preload("res://scripts/air_foe.gd")
const Mob := preload("res://scripts/raid_mob.gd")
const Data := preload("res://scripts/raid_data.gd")
const Sfx := preload("res://scripts/sfx.gd")

enum M { SCOUT, FIGHT, REGROUP, RETREAT, WATCH, EXTRACT, DOWN }
const M_NAMES := ["探路", "交战", "归队", "撤退回气", "观劫", "同撤", "重伤离场"]
const KIND_NAMES := ["冲锋", "稳健", "探路"]
## 头顶冒的话（联机时只同步下标）
const SAY := ["我去前面探探", "这边有怪，我先上", "这只精英交给我", "顶住，我来了", "我先撤一步，缓口气", "等等我", "这边有处可搜的地方",
		"回来了", "这只归我", "当心，它要出招了", "一起撤", "道友安心渡劫，我替你看着", "首领！一起上"]
const LEASH := [50.0, 40.0, 62.0]        # 离队友多远就该往回赶（队友在赶路时收到六成，见 _leash）
const SENSE := [48.0, 36.0, 32.0]        # 多远的怪会去打（探路的只打身边的，其余时间去探）
const FLEE_AT := [0.26, 0.42, 0.34]      # 血剩几成就撤
const HURT_K := 0.55                     # 挨怪打的伤害系数（比主角经打一点，免得老倒）
## 打怪的伤害系数。新大脑比老的勤快得多（打得远、会放剑气和剑轮、不站着发呆）：同一段自检里老逻辑两位道友 95 秒打死 7 只，
## 新大脑不折算时是 18 只——队友打死的怪照常给主角经验和掉落，放着不管等于把升级速度翻了一倍多。光降伤害不够（乘 0.38 还有 15 ~ 20 只：它们主要是打得勤、打得远），所以再加一条：没动手的怪只打身边的（IDLE_R）。
const DMG_K := 0.3
const IDLE_R := [34.0, 24.0, 22.0]       # 还没动手的怪（没在追任何人）：离自己这么近才去招惹，远处的留给主角

var rd: Variant                 # raid_manager.gd
var f: AirFoe                   # 这个大脑管着的那位道友
var kind := 0
var skill := 0.7                # 反应 / 读招的水平（0 ~ 1）
var anchor: Node3D              # 跟着哪位队友行动（本机主角，或同队真人的木偶）
var mode := M.SCOUT
var target: Node3D = null
var say_i := -1
var say_n := 0                  # 说过几句（联机：木偶看到它变了就冒泡）
## 自检用的统计
var stat := {"t": 0.0, "mode_t": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "swings": 0, "kills": 0, "bolts": 0, "bursts": 0, "dodges": 0,
		"hits": 0, "heals": 0, "retreats": 0, "downs": 0, "says": 0, "sites": 0, "targets": 0, "assists": 0}

var _think := 0.0
var _way := Vector3.INF
var _way_t := 0.0
var _wait_t := 0.0
var _look := 0.0
var _cruise := 9.0
var _poi: Dictionary = {}
var _seen := {}                 # 去探过的搜点编号
var _swing_cd := 0.0
var _swung := false
var _ci := 0
var _pause := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _dodge_t := 0.0
var _dodge_v := Vector3.ZERO
var _dodged := false            # 目标这一次起手已经判过躲不躲了
var _bolt_cd := 3.0
var _skill_cd := 8.0
var _heal_cd := 0.0
var _flee_t := 0.0
var _down_t := 0.0
var _since_hit := 99.0
var _say_cd := 4.0
var _bubble: Label3D
var _bubble_t := 0.0
var _told := {}                 # 一次性的话说过没有


func setup(raid: Variant, foe: AirFoe, slot: int) -> void:
	rd = raid
	f = foe
	kind = [0, 2, 1][slot % 3]
	skill = clampf([0.82, 0.7, 0.76][kind] + randf_range(-0.08, 0.08), 0.4, 0.95)
	anchor = rd.player
	_bolt_cd = randf_range(2.0, 5.0)
	_skill_cd = randf_range(6.0, 10.0)
	_think = randf_range(0.2, 0.8)


# ---------- 队友（anchor）的情况 ----------

func _apos() -> Vector3:
	return anchor.global_position


func _avel() -> Vector3:
	if anchor is CharacterBody3D:
		return (anchor as CharacterBody3D).velocity
	var v: Variant = anchor.get("_vel")
	return v if v is Vector3 else Vector3.ZERO


func _aspeed() -> float:
	return _avel().length()


## 队友的气血（0 ~ 1）
func _ahp() -> float:
	if anchor == rd.player:
		return clampf(float(rd.player.melee.hp) / 100.0, 0.0, 1.0)
	var h: Variant = anchor.get("hp")
	return clampf(float(h) / 100.0, 0.0, 1.0) if h != null else 1.0


## 现在的牵引距离：队友站着 / 在打就按性子给的；队友在赶路（每秒四米以上）就收到六成，别落在后面几十米
func _leash() -> float:
	return float(LEASH[kind]) * (0.7 if _aspeed() > 4.0 else 1.0)


func _hover(p: Vector3, up := 1.4) -> Vector3:
	var fy := float(f.floor_fn.call(p.x, p.z)) if f.floor_fn.is_valid() else 0.0
	p.y = maxf(fy + up, p.y if p.y > fy + up + 4.0 else fy + up)
	return p


## 目标身上的布尔标记（怪有 boss / elite，AI 修士没有这两个属性：get 回来是 null，不能直接 bool()）
static func _flag(t: Variant, prop: String) -> bool:
	var v: Variant = t.get(prop)
	return v != null and bool(v)


static func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _near_viewer() -> bool:
	return rd.player.global_position.distance_to(f.global_position) < 70.0


# ---------- 每帧（air_foe.gd 的 _tick_roam 调） ----------

func tick(dt: float, yaw: float) -> float:
	if anchor == null or not is_instance_valid(anchor):
		anchor = rd.player
	stat["t"] = float(stat["t"]) + dt
	(stat["mode_t"] as Array)[mode] += dt
	_swing_cd -= dt
	_bolt_cd -= dt
	_skill_cd -= dt
	_heal_cd -= dt
	_say_cd -= dt
	_since_hit += dt
	if _bubble_t > 0.0:
		_bubble_t -= dt
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false
	if mode == M.DOWN:
		_down_t -= dt
		f._vel = Vector3.ZERO
		if _down_t <= 0.0:
			_revive()
		return yaw
	# 脱战几秒后慢慢回气
	if _since_hit > 6.0 and f.hp < f.hp_max:
		f.hp = minf(f.hp + f.hp_max * 0.03 * dt, f.hp_max)
	if _swung and _swing_cd <= 0.2:
		_swung = false
		f.rig.play("f_idle")
	if target != null and not (is_instance_valid(target) and bool(target.call("is_alive"))):
		target = null
		_think = minf(_think, 0.15)
	_think -= dt
	if _think <= 0.0:
		# 人的反应有快有慢：半秒到一秒多才重新拿一次主意
		_think = randf_range(0.45, 0.8) + (1.0 - skill) * 0.4
		_decide()
	match mode:
		M.FIGHT:
			yaw = _do_fight(dt, yaw)
		M.REGROUP:
			yaw = _do_regroup(dt, yaw)
		M.RETREAT:
			yaw = _do_retreat(dt, yaw)
		M.WATCH:
			yaw = _do_watch(dt, yaw)
		M.EXTRACT:
			yaw = _do_extract(dt, yaw)
		_:
			yaw = _do_scout(dt, yaw)
	return yaw


# ---------- 拿主意 ----------

func _set_mode(m: M) -> void:
	if m == mode:
		return
	mode = m
	_way = Vector3.INF
	_wait_t = 0.0


func _decide() -> void:
	var me := f.global_position
	var ap := _apos()
	var da := _hd(me, ap)
	if bool(rd.get("_in_trib")):
		if mode != M.WATCH and not _told.has("trib"):
			_told["trib"] = true
			say(11)
		target = null
		_set_mode(M.WATCH)
		return
	_told.erase("trib")
	if float(rd.get("extract_k")) > 0.02:
		if mode != M.EXTRACT:
			say(10)
		target = null
		_set_mode(M.EXTRACT)
		return
	if mode == M.RETREAT:
		return          # 回完气才算完（_do_retreat 里收）
	if f.hp < f.hp_max * float(FLEE_AT[kind]) and _heal_cd <= 0.0:
		stat["retreats"] = int(stat["retreats"]) + 1
		target = null
		_flee_t = 0.0
		_set_mode(M.RETREAT)
		say(4)
		return
	# 离队太远 / 队友御剑飞走了：归队。归队途中要回到十几米内才算到
	var far := da > _leash() or (da > 34.0 and _aspeed() > 22.0)
	if mode == M.REGROUP:
		far = da > 16.0
	if far:
		if mode != M.REGROUP and da > 90.0:
			say(5)
		target = null
		_set_mode(M.REGROUP)
		return
	var t := _pick_target(me, ap)
	if t != null:
		if t != target:
			stat["targets"] = int(stat["targets"]) + 1
			var threat := t.global_position.distance_to(ap) < 16.0 and bool(t.call("is_hostile"))
			if threat:
				stat["assists"] = int(stat["assists"]) + 1
			if _flag(t, "boss"):
				say(12)
			elif threat and _ahp() < 0.5:
				say(3)
			elif _flag(t, "elite"):
				say(2)
			elif randf() < 0.25:
				say(1)
		target = t
		_set_mode(M.FIGHT)
		return
	target = null
	if mode != M.SCOUT:
		_set_mode(M.SCOUT)


## 打谁：分数越低越想打
func _pick_target(me: Vector3, ap: Vector3) -> Node3D:
	var best: Node3D = null
	var bs := 1.0e9
	var list: Array = rd._mobs + rd._puppets.values() + rd._boss_nodes()
	for m: Variant in list:
		if not is_instance_valid(m) or not bool(m.is_alive()):
			continue
		var mp: Vector3 = m.global_position
		var dm := mp.distance_to(me)
		var da := mp.distance_to(ap)
		var threat := da < 16.0 and bool(m.is_hostile())      # 正贴着队友打
		if not threat and (dm > float(SENSE[kind]) or da > _leash() - 4.0):
			continue
		if threat and dm > 130.0:
			continue
		var boss := bool(m.boss)
		if boss and not threat:
			continue          # 首领：队友跟它交上手了才上
		if not bool(m.is_hostile()) and m != target and dm > float(IDLE_R[kind]):
			continue          # 远处还没动手的怪：不去满场清
		var s := dm + maxf(da - 26.0, 0.0) * 0.5      # 离队友远的往后排
		if threat:
			s -= 22.0 + (14.0 if _ahp() < 0.5 else 0.0)
		if m.decoy == f:
			s -= 8.0
		if float(m.hp) / maxf(float(m.hp_max), 1.0) < 0.35:
			s -= 6.0
		if bool(m.elite):
			s += -4.0 if kind == 0 else (10.0 if not threat else 0.0)
		if not boss and not bool(m.elite):
			for o: Variant in rd._allies:
				if o != f and is_instance_valid(o) and o.brain != null and o.brain.target == m:
					s += 16.0      # 别的道友已经在打这只小怪：分头打
		if m == target:
			s -= 14.0         # 手上这只：差不多的就不换（别打两下换一只）
		if s < bs:
			bs = s
			best = m
	# 正在围攻队友的红名 AI 修士：帮着打（不去招惹没动手的）
	for r: Variant in rd._rivals:
		if not is_instance_valid(r) or not bool(r.hostile) or r.state == AirFoe.S.IDLE or r.state == AirFoe.S.DEAD:
			continue
		var rp: Vector3 = r.global_position
		if rp.distance_to(ap) > 32.0 or rp.distance_to(me) > 110.0:
			continue
		var s2 := rp.distance_to(me) - 18.0 - (7.0 if r == target else 0.0)
		if s2 < bs:
			bs = s2
			best = r
	return best


# ---------- 打 ----------

func _winding(t: Variant) -> bool:
	if t.get_script() == Mob:
		return int(t.state) == Mob.S.WIND
	return t.get_script() == AirFoe and int(t.state) == AirFoe.S.WINDUP


func _strike(t: Variant, dmg: float, dir: Vector3, heavy := false) -> void:
	if t.has_method("sim_damage"):
		t.call("sim_damage", dmg * DMG_K, dir, f)
	else:
		# AI 修士：走它的受击入口（硬直、护体照常）。2026-11-23：直接给实伤（real），量级和打怪一样（prey_dmg × DMG_K）——
		# 原来借主角的 dmg_in 按主角的境界折算，主角境界越高这一下反而越小
		t.call("receive_hit", f, {"dmg": dmg * DMG_K, "real": true, "dir": dir, "heavy": heavy, "kb": 1.2})
	if not (is_instance_valid(t) and bool(t.call("is_alive"))):
		stat["kills"] = int(stat["kills"]) + 1
		if randf() < 0.3:
			say(8)


func _do_fight(dt: float, yaw: float) -> float:
	if target == null:
		return yaw
	var pc: Vector3 = target.call("center")
	var to := pc - f.center()
	var d := to.length() - (float(target.call("hit_radius")) if target.has_method("hit_radius") else 0.6)      # AI 修士没有这个函数
	var dir := to.normalized() if to.length_squared() > 1e-4 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	yaw = atan2(-to.x, -to.z)
	# 侧闪的那零点几秒
	if _dodge_t > 0.0:
		_dodge_t -= dt
		f._vel = f._vel.move_toward(_dodge_v, 160.0 * dt)
		if _dodge_t <= 0.0:
			_swing_cd = minf(_swing_cd, 0.08)      # 闪完马上还手
		return yaw
	# 读招：盯着我的那只起手了、我就在它跟前 → 按水平有几成会往侧面闪一步（每次起手只判一次）
	var wind := _winding(target)
	if wind and d < 4.6 and not _dodged and target.get("decoy") == f:
		_dodged = true
		if randf() < skill * 0.6:
			stat["dodges"] = int(stat["dodges"]) + 1
			_dodge_t = 0.22
			_dodge_v = side * _strafe * 11.0 - dir * 4.0
			_dodge_v.y = 0.0
			if randf() < 0.2:
				say(9)
			if _near_viewer():
				Sfx.play("dodge", -14.0, 1.1)
			return yaw
	elif not wind:
		_dodged = false
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.8)
		_strafe = -_strafe if randf() < 0.7 else _strafe
	if d > 3.2:
		# 靠过去：带一点横移，不走直线；隔着七到二十几米先放一道剑气
		var spd := minf(AirFoe.FLY_SPD, (d - 1.6) * 4.0 + 3.0)
		f._vel = f._vel.move_toward((dir + side * _strafe * (0.28 if d < 14.0 else 0.0)).normalized() * spd, 50.0 * dt)
		if d > 7.0 and d < 24.0 and _bolt_cd <= 0.0:
			_bolt_cd = randf_range(2.6, 4.2) / maxf(skill, 0.4)
			stat["bolts"] = int(stat["bolts"]) + 1
			_swing_cd = 0.4
			_swung = true
			f.rig.play("f_point")
			if _near_viewer():
				Vfx._ray(f.center() + dir * 0.8, dir, f.qi, 2.6, 0.2, maxf(d - 2.0, 1.0), 0.16)
				Vfx.hit(pc, dir, f.qi, 0.6)
				Sfx.play("swing", -15.0, 1.5)
			_strike(target, f.prey_dmg * 0.9, dir)
		return yaw
	# 贴身（三米二以内都够得着）：远一点就边打边贴上去，近了绕着它慢慢横移；一套四下、最后一下重，套与套之间挪个位
	if d > 2.2:
		f._vel = f._vel.move_toward(dir * 5.0 + side * _strafe * 1.2, 40.0 * dt)
	else:
		f._vel = f._vel.move_toward(side * _strafe * 2.0, 40.0 * dt)
	if _pause > 0.0:
		_pause -= dt
		return yaw
	# 剑轮：身边挤了两只以上，或打的是精英 / 首领
	if _skill_cd <= 0.0 and (_crowd(6.0) >= 2 or _flag(target, "elite") or _flag(target, "boss")):
		_burst()
		return yaw
	if _swing_cd <= 0.0:
		var last := _ci % 4 == 3
		_swing_cd = (0.42 + (1.0 - skill) * 0.2) * (1.25 if last else 1.0)
		_swung = true
		f.rig.play(["f1", "f2", "f3", "f4"][_ci % 4])
		_ci += 1
		stat["swings"] = int(stat["swings"]) + 1
		if _near_viewer():
			Vfx.hit(pc, dir, f.qi, 1.0 if last else 0.7)
			Sfx.play("swing_heavy" if last else "swing", -14.0, 1.1)
		_strike(target, f.prey_dmg * (1.6 if last else 1.0), dir, last)
		if last:
			_pause = randf_range(0.3, 0.6)
			_strafe = -_strafe
	return yaw


func _crowd(r: float) -> int:
	var n := 0
	var c := f.global_position
	for m: Variant in rd._mobs + rd._puppets.values():
		if is_instance_valid(m) and bool(m.is_alive()) and c.distance_to(m.global_position) < r:
			n += 1
	return n


## 剑轮：身周一圈的范围伤害
func _burst() -> void:
	_skill_cd = randf_range(9.0, 14.0)
	_swing_cd = 0.6
	_pause = 0.3
	_swung = true
	f.rig.play("f4")
	stat["bursts"] = int(stat["bursts"]) + 1
	var c := f.center()
	if _near_viewer():
		Vfx.shockwave(c, Vector3.UP, f.qi, 1.2)
		Sfx.play("skill_sword", -9.0, 1.0)
	for m: Variant in rd._mobs + rd._puppets.values() + rd._boss_nodes():
		if is_instance_valid(m) and bool(m.is_alive()) and c.distance_to(m.global_position) < 6.5:
			var dd: Vector3 = m.global_position - c
			dd.y = 0.0
			_strike(m, f.prey_dmg * 1.8, dd.normalized() if dd.length_squared() > 0.01 else Vector3.FORWARD, true)


# ---------- 走 ----------

func _fly(to: Vector3, spd: float, dt: float, accel := 45.0) -> float:
	var d := to - f.global_position
	var dist := d.length()
	var v := d / dist * minf(spd, dist * 3.5 + 0.5) if dist > 0.3 else Vector3.ZERO
	f._vel = f._vel.move_toward(v, accel * dt)
	return dist


func _heading(yaw: float) -> float:
	var v := Vector2(f._vel.x, f._vel.z)
	return atan2(-v.x, -v.y) if v.length() > 1.0 else yaw


func _do_scout(dt: float, yaw: float) -> float:
	if _wait_t > 0.0:
		# 到地方了：停一停，左右张望
		_wait_t -= dt
		_look += dt
		f._vel = f._vel.move_toward(Vector3.ZERO, 30.0 * dt)
		return f._facing + cos(_look * 1.6) * 1.1 * dt
	_way_t -= dt
	if _way == Vector3.INF or _way_t <= 0.0:
		_next_way()
	var dist := _fly(_way, _cruise, dt, 22.0)
	if dist < 2.4:
		_wait_t = randf_range(0.7, 2.4)
		_way = Vector3.INF
		if not _poi.is_empty():
			_found(_poi)
			_poi = {}
	return _heading(yaw)


## 下一个去处：探没搜过的搜点 / 往队友前进方向的前面去 / 在队友周围换个地方
func _next_way() -> void:
	var ap := _apos()
	var av := _avel()
	av.y = 0.0
	_poi = {}
	_cruise = randf_range(7.5, 10.5)
	_way_t = 9.0
	var srch: Variant = rd.get("search")
	if srch != null and is_instance_valid(srch) and randf() < float([0.3, 0.25, 0.65][kind]):
		var best: Dictionary = {}
		var bd := 1.0e9
		for s: Dictionary in srch.sites:
			if bool(s["done"]) or not bool(s["live"]) or _seen.has(int(s["id"])):
				continue
			var sp: Vector3 = s["pos"]
			if sp.distance_to(ap) > float(LEASH[kind]) + 40.0:
				continue
			var d := sp.distance_to(f.global_position)
			if d < bd:
				bd = d
				best = s
		if not best.is_empty():
			var a0 := randf() * TAU
			_way = _hover((best["pos"] as Vector3) + Vector3(cos(a0), 0.0, sin(a0)) * 3.0)
			_poi = best
			_way_t = 16.0
			_cruise = 11.0
			if randf() < 0.5:
				say(0)
			return
	if av.length() > 2.5:
		# 队友在赶路：往他前面去探（左右错开），不是跟在后面
		var fw := av.normalized()
		var sd := Vector3(-fw.z, 0.0, fw.x)
		_way = ap + fw * (randf_range(10.0, 20.0) + av.length() * 1.2) + sd * randf_range(-12.0, 12.0)
		_cruise = maxf(_cruise, av.length() * 1.2)
		_way_t = 5.0
	else:
		var a := randf() * TAU
		var r := randf_range(12.0, 36.0) * float([1.0, 0.8, 1.5][kind])
		_way = ap + Vector3(cos(a), 0.0, sin(a)) * r
	_way = _hover(_way)


## 探到一处搜点：标到小地图上，喊一声
func _found(s: Dictionary) -> void:
	_seen[int(s["id"])] = true
	if bool(s["done"]):
		return
	if not bool(s["known"]):
		s["known"] = true
		stat["sites"] = int(stat["sites"]) + 1
		if rd.hud != null:
			rd.hud.toast("%s 探到一处可搜的地方（已标在地图上）" % f.display_name, Color(0.5, 0.95, 0.8))
	say(6)


func _do_regroup(dt: float, yaw: float) -> float:
	var ap := _apos()
	if _way == Vector3.INF or _way.distance_to(ap) > 18.0:
		# 落点跟着队友走：他周围七到十三米的随便一处（不是那个固定的身侧站位）
		var a := randf() * TAU
		_way = ap + Vector3(cos(a), 0.0, sin(a)) * randf_range(7.0, 13.0)
		_way.y = ap.y + 0.3
		_way = _hover(_way)
	var d := _hd(f.global_position, ap)
	var spd := clampf(maxf(maxf(AirFoe.FLY_SPD, _aspeed() * 1.35), d * 0.9), AirFoe.FLY_SPD, 110.0)
	if _fly(_way, spd, dt, 90.0) < 2.5 and _aspeed() < 3.0:
		# 到落点了、队友也停下了：归队完成，马上重新拿主意（不等下一次思考）
		mode = M.SCOUT
		_way = Vector3.INF
		_think = 0.0
	return _heading(yaw)


func _do_retreat(dt: float, yaw: float) -> float:
	_flee_t += dt
	var me := f.global_position
	var away := Vector3.ZERO
	var nearest := 99.0
	for m: Variant in rd._mobs:
		if not is_instance_valid(m) or not bool(m.is_alive()) or not bool(m.is_hostile()):
			continue
		var mp: Vector3 = m.global_position
		var d := me.distance_to(mp)
		nearest = minf(nearest, d)
		if d < 18.0:
			away += (me - mp).normalized() * (18.0 - d)
	away.y = 0.0
	var to := _apos() - me
	to.y = 0.0
	var dir := away.normalized() * 1.2 + (to.normalized() * 0.6 if to.length() > 12.0 else Vector3.ZERO)
	f._vel = f._vel.move_toward(dir.normalized() * 13.0 if dir.length() > 0.1 else Vector3.ZERO, 60.0 * dt)
	# 拉开了（或者跑了三秒多还甩不掉）：服丹回一口，回去接着打
	if _flee_t > 1.4 and (nearest > 8.0 or _flee_t > 3.2):
		f.hp = minf(f.hp + f.hp_max * 0.5, f.hp_max)
		_heal_cd = 20.0
		stat["heals"] = int(stat["heals"]) + 1
		if _near_viewer():
			Vfx.glint(f.center() + Vector3(0.0, 0.5, 0.0), Color(0.5, 1.0, 0.7), 1.2)
			Sfx.play("heal", -9.0, 1.0)
		mode = M.SCOUT
		_way = Vector3.INF
		_think = 0.2
	return _heading(yaw)


## 队友渡劫：退到二十米外悬着看
func _do_watch(dt: float, yaw: float) -> float:
	var ap := _apos()
	if _way == Vector3.INF:
		var a := float(f.ally_slot) * 2.1 + 0.7
		_way = _hover(ap + Vector3(cos(a), 0.0, sin(a)) * randf_range(18.0, 24.0), 2.6)
	var dist := _fly(_way, 12.0, dt)
	var to := ap - f.global_position
	return atan2(-to.x, -to.z) if dist < 3.0 else _heading(yaw)


## 队友在读条撤离：过去站到他身边
func _do_extract(dt: float, yaw: float) -> float:
	var ap := _apos()
	var a := float(f.ally_slot) * 2.4 + 1.0
	_fly(_hover(ap + Vector3(cos(a), 0.0, sin(a)) * 2.6), 18.0, dt, 70.0)
	return _heading(yaw)


# ---------- 挨打、重伤、归队 ----------

## 被怪打中（air_foe.gd 的 mob_hit 调）
func on_hit(dmg: float, _dir: Vector3, _mob: Node3D, _heavy: bool) -> void:
	if mode == M.DOWN or _dodge_t > 0.0:
		return
	_since_hit = 0.0
	stat["hits"] = int(stat["hits"]) + 1
	f.hp -= dmg * HURT_K
	if f.hp <= 0.0:
		_go_down()


func _go_down() -> void:
	f.hp = 0.0
	mode = M.DOWN
	_down_t = randf_range(8.0, 11.0)
	target = null
	stat["downs"] = int(stat["downs"]) + 1
	f._vel = Vector3.ZERO
	Vfx.vanish(f.center(), f.qi)
	f.visible = false
	for m: Variant in rd._mobs:
		if is_instance_valid(m) and m.decoy == f:
			m.decoy = null
	if rd.hud != null:
		rd.hud.toast("%s 重伤遁走，稍后归队" % f.display_name, Color(1.0, 0.6, 0.45))


func _revive() -> void:
	var ap := _apos()
	var a := randf() * TAU
	f.global_position = _hover(ap + Vector3(cos(a), 0.0, sin(a)) * 9.0)
	f.hp = f.hp_max * 0.6
	f.visible = true
	_heal_cd = 8.0
	mode = M.SCOUT
	_way = Vector3.INF
	_think = 0.3
	Vfx.vanish(f.center(), f.qi)
	if rd.hud != null:
		rd.hud.toast("%s 归队" % f.display_name, Color(0.5, 0.95, 0.8))
	say(7, true)


# ---------- 头顶冒一句话 ----------

static func make_bubble(host: Node3D) -> Label3D:
	var l := Label3D.new()
	l.font = Vfx.font
	l.font_size = 38
	l.pixel_size = 0.0065
	l.outline_size = 10
	l.modulate = Color(1.0, 0.97, 0.86)
	l.outline_modulate = Color(0.08, 0.07, 0.09, 0.92)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position.y = 3.05
	l.visible = false
	host.add_child(l)
	return l


func say(i: int, force := false) -> void:
	if (_say_cd > 0.0 and not force) or mode == M.DOWN:
		return
	_say_cd = randf_range(9.0, 15.0)
	say_i = i
	say_n += 1
	stat["says"] = int(stat["says"]) + 1
	if _bubble == null:
		_bubble = make_bubble(f)
	_bubble.text = SAY[i]
	_bubble.visible = true
	_bubble_t = 2.6


## 联机：这位道友现在的状态位（位 0 = 重伤离场，其余是在干什么）
func flags() -> int:
	return (1 if mode == M.DOWN else 0) | (int(mode) << 1)
