extends "res://scripts/kit_base.gd"
## 英雄「苍鸿」（剑修）的技能脚本（2026-11-25 TSB 式重做：藏锋 / 拔剑术 + 剑痕引爆）。招式数据在 def_canghong.gd，状态机是 air_melee.gd；
## 这里管：剑痕（记在目标身上、画出来、联机同步）、归剑引爆、四个技能出哪一招、斩击的弧光 / 裂空的斩痕 / 一线天的画面。
##   E 惊鸿 → 觉醒 瞬狱   Z 听风 → 剑域   Q 裂空 → 天裂   R 落英 → 一线天（终结）
## 剑痕怎么来：凡是经 air_melee 结算、真的打中了（没被护体挡下）的那一下，都会发 combat_event "air_hit" —— 这里听这个事件给锁着的目标加痕
## （招式的 marks 字段 = 加几道，缺省 1）；裂空 / 一线天这些自己判定的招自己加。
## 画面的联机同步：别人那边只画不判伤害，HeroFx.send(kind …) → 对面 remote_fx（号段 40 ~ 69）。
## 故意不写 class_name。

const MarkView := preload("res://scripts/heroes/cg_mark_view.gd")

const CYAN := Color(0.45, 0.85, 1.0)
const MARK_MAX := 5           # 剑痕上限
const MARK_MAX_AW := 8        # 觉醒中的上限
const MARK_LIFE := 6.0        # 这么久不补就散
const MARK_DMG := 0.25        # 引爆时每道几个单位
const MARK_FULL := 0.25       # 满痕再加
const MARK_HEAVY := 3         # 这么多道以上：把人炸飞（算重击）
const GJ_M1 := 0.42           # M1 第四段：短劈判定之后多久引爆（剑背到身后定住再过一拍）
const GJ_SHOW := 0.34         # 单独的归剑收势：摆出来之后多久引爆
const GJ_GAP := 0.032         # 剑痕一道一道炸亮的间隔
const JH_R := 14.0            # 惊鸿够得着多远（另加对手体型）
const LY_R := 9.0             # 落英：这么近才放得出来
const LY_ANG: Array[float] = [2.3, -2.6, 2.0, -2.4, 2.8]
const LK_DELAY := 0.42        # 裂空：一挑之后多久裂开
const LK_GAP := 0.07          # 几道斩痕之间隔多久
const LK_R := 3.2
const LK_N := 3
const LK_DMG := 0.3
const TL_R := 6.0
const TL_N := 5
const TL_DMG := 0.36
const PARRY_T := 0.7
const DOMAIN_T := 1.6
const DOMAIN_R := 6.0
const YX_R := 18.0            # 一线天：面前多远
const YX_COS := 0.26          # 左右各约 75 度
const YX_CUT := 0.4           # 横抹那一下
const YX_SPLIT := 2.0         # 一线齐断
const YX_DELAY := 0.74        # 横抹之后多久断
## 斩击弧光的预设：[挥剑方向 x（右）, y（上）, 半径, 张角（度）]，招式的 arc 字段填序号
const ARCS: Array = [
	[0.8, 0.6, 2.9, 150],       # 0 起：左下 → 右上
	[-1.0, -0.12, 3.0, 150],    # 1 承：右 → 左平抹
	[1.0, 0.0, 3.0, 300],       # 2 转：绕身一圈
	[-0.6, -0.8, 2.4, 120],     # 3 收：短促斜劈
	[0.15, 1.0, 3.0, 150],      # 4 自下而上
	[-0.1, -1.0, 3.0, 150],     # 5 自上而下
	[1.0, 0.04, 4.2, 170],      # 6 平掠（惊鸿 / 瞬狱）
]
## 联机画面号
const FX_ARC := 40            # 一道弧光：roll = 预设序号（+0.5 = 觉醒的大号）
const FX_RIFT := 41           # 裂空 / 天裂：pos = 裂开的位置，roll 1 = 天裂
const FX_MARK := 42           # 剑痕数变了：pos = 目标位置，roll = 现在几道
const FX_DET := 43            # 归剑引爆：pos = 目标位置
const FX_LINE := 44           # 惊鸿 / 瞬狱的一线：pos 起点，dir × roll 终点
const FX_YX := 45             # 一线天横抹
const FX_YX2 := 46            # 一线天齐断
const FX_DOM := 47            # 剑域的圈：pos 圆心

## 这个脚本里不放 static var：技能脚本是 load() 进来的 Node 脚本，静态函数里用到的静态变量会让它在退出时释放不掉
## （一串「shaders were never freed / RIDs leaked」的报错）。弧光网格缓存在 Vfx.root 的 meta 上，别人打出来的剑痕记在目标节点自己的 meta 上。
const META_RMARK := "cg_rmarks"

var _views: Dictionary = {}              # 我打出来的剑痕：目标节点 id → MarkView
var _gj_on := false
var _gj_t := 0.0
var _gj_queue := -1.0                    # 听风反斩之后隔这么久自动接归剑（< 0 = 没有）
var _dom_live := false
var _domain: MeshInstance3D
var _domain_t := 0.0
var _jh_from := Vector3.ZERO
var _yx_t := -1.0
var _yx_c := Vector3.ZERO
var _yx_fwd := Vector3.FORWARD
var _yx_hit: Array = []
var _dbg := false
var _c3_side := 1.0
var _dbg_last := ""


func _init() -> void:
	_dbg = OS.get_cmdline_user_args().has("--cg-dbg")
	stat = {"marks": 0, "det": 0, "det_dmg": 0.0, "parries": 0, "rift": 0, "rift_hits": 0, "yx": 0, "yx_hits": 0, "gj_cut": 0}


func _ready() -> void:
	if player != null and player.melee != null and not player.melee.combat_event.is_connected(_on_event):
		player.melee.combat_event.connect(_on_event)
	if OS.get_cmdline_user_args().has("--cg-test") and ResourceLoader.exists("res://_tasks/tsb/canghong/cg_test.gd"):
		# 调试用（_tasks/tsb/canghong/cg_test.gd）：归剑连拍、替木桩出手验招架。正式包里没有这个文件
		var tn: Node = (load("res://_tasks/tsb/canghong/cg_test.gd") as GDScript).new()
		tn.set("kit", self)
		tn.set("player", player)
		add_child(tn)


func detach() -> void:
	if player != null and player.melee != null and player.melee.combat_event.is_connected(_on_event):
		player.melee.combat_event.disconnect(_on_event)
	for v: Variant in _views.values():
		if is_instance_valid(v):
			(v as MarkView).drop()
	_views.clear()
	player.set_blade_glow(0.0)
	if is_instance_valid(_domain):
		_domain.queue_free()


func _mark_cap() -> int:
	return MARK_MAX_AW if _awake() else MARK_MAX


# ---------- 剑痕 ----------

static func _new_view(t: Node3D, col: Color) -> MarkView:
	var v := MarkView.new()
	v.who = t
	v.col = col
	Vfx.root.add_child(v)
	return v


func marks_on(t: Node3D) -> int:
	if t == null or not is_instance_valid(t):
		return 0
	var v: Variant = _views.get(t.get_instance_id())
	return (v as MarkView).n if is_instance_valid(v) else 0


## 给目标加 n 道剑痕（到上限为止），续上时间
func add_mark(t: Node3D, n := 1) -> void:
	if n <= 0 or t == null or not Proj.alive(t) or not HeroFx.ok():
		return
	var id := t.get_instance_id()
	var v: MarkView = null
	if _views.has(id) and is_instance_valid(_views[id]) and not (_views[id] as MarkView)._bursting:
		v = _views[id]
	else:
		v = _new_view(t, _col())
		_views[id] = v
	var cap := _mark_cap()
	var before := v.n
	v.set_n(mini(maxi(v.n, 0) + n, maxi(cap, v.n)))
	v.life = MARK_LIFE
	if v.n == before:
		return
	stat["marks"] = int(stat["marks"]) + v.n - before
	HeroFx.send(player, FX_MARK, v.center(), Vector3.UP, float(v.n))
	if v.n >= cap and before < cap:
		# 满痕：亮一下、响一声 —— 该归剑了
		Vfx.glint(v.center(), Color.WHITE, 1.3)
		Sfx.play("blade_cut", -7.0, 1.5)


func _on_event(kind: String, _info: Dictionary) -> void:
	if kind != "air_hit":
		return
	var air := player.air
	var t: Node3D = air.target
	if t != null and Proj.alive(t):
		add_mark(t, int((air._atk as Dictionary).get("marks", 1)) if air.state == air.A.ATTACK else 1)


# ---------- 归剑：引爆 ----------

## 约好 delay 秒后引爆（这段时间里自己挨了打就作废，剑痕留着）
func guijian(delay: float) -> void:
	_gj_on = true
	_gj_t = delay
	Sfx.play("sheath", -1.0, 1.0)


func _any_marks() -> bool:
	for v: Variant in _views.values():
		if is_instance_valid(v) and (v as MarkView).n > 0 and not (v as MarkView)._bursting:
			return true
	return false


func _detonate() -> void:
	_gj_on = false
	var c := player.center()
	# 归剑入定的那一声脆响（有没有剑痕都响）
	Sfx.play("perfect", -7.0, 1.5)
	Vfx.glint(player.melee.rig.tip_pos(), Color.WHITE.lerp(_col(), 0.3), 0.9)
	var total := 0
	for id: Variant in _views.keys():
		var v: Variant = _views[id]
		if not is_instance_valid(v):
			_views.erase(id)
			continue
		var mv := v as MarkView
		if mv.n <= 0 or mv._bursting or not is_instance_valid(mv.who) or mv.center().distance_to(c) > 60.0:
			continue
		var n := mv.n
		total += n
		HeroFx.send(player, FX_DET, mv.center(), Vector3.UP, float(n))
		mv.burst(GJ_GAP)
		_views.erase(id)
		var tw := create_tween()
		tw.tween_interval(GJ_GAP * float(n))
		tw.tween_callback(_det_hit.bind(mv.who, n, n >= _mark_cap()))
	if total > 0:
		stat["det"] = int(stat["det"]) + total


func _det_hit(t: Variant, n: int, full: bool) -> void:
	if not is_instance_valid(t) or not Proj.alive(t) or not is_instance_valid(player) or player.dead:
		return
	var e := t as Node3D
	var air := player.air
	var ec := Proj.aim_of(e)
	var dir: Vector3 = air._flat(ec - player.center())
	dir = dir.normalized() if dir.length_squared() > 0.01 else air._fwd()
	var heavy := n >= MARK_HEAVY
	var dmg := units(MARK_DMG * float(n) + (MARK_FULL if full else 0.0))
	var info := {"dmg": dmg, "dir": dir, "kb": 28.0 if heavy else 5.0, "stun": 0.9 if heavy else 0.5, "launch": "fwd" if heavy else "",
			"heavy": heavy, "ranged": true, "contact": ec, "pstun": 0.5}
	var res := _hit_one(e, info)
	det_fx(ec, dir, n, full, _col())
	if res < 0 or res == 1:
		return
	stat["det_dmg"] = float(stat["det_dmg"]) + dmg
	air._add_combo(dmg)
	Combat.hitstop(0.05 + 0.012 * float(n))
	var cam := player.cam
	cam.add_trauma(0.22 + 0.05 * float(n))
	cam.fov_punch(3.0 + float(n))
	Sfx.play("cut_burst", -1.0, 1.0)
	if full:
		Sfx.play("cut_burst", -4.0, 1.25)
	if heavy and e.has_method("is_launched") and bool(e.call("is_launched")):
		air._on_launch(e, "fwd", ec, dir, 0.1)


## 剑痕炸开的那一下：十字斩光 + 一圈震波；满痕多一道空间裂缝
static func det_fx(pos: Vector3, dir: Vector3, n: int, full: bool, col: Color) -> void:
	if not HeroFx.ok():
		return
	var k := clampf(0.6 + 0.14 * float(n), 0.7, 1.8)
	Vfx.blade_hit(pos, dir.cross(Vector3.UP), col, k)
	Vfx.shockwave(pos, dir, Color.WHITE.lerp(col, 0.4), 0.9 * k)
	if n >= MARK_HEAVY:
		Vfx.space_ring(pos, 1.6 * k, col, 0.4, 0.05)
	if full and not Vfx.lite:
		Vfx.space_crack(pos, col, 1.6, 3, 0.4, 0.3)


# ---------- 技能 ----------

func _cast(i: int, aw: bool) -> bool:
	var air := player.air
	match i:
		0:
			var t := near_target(JH_R)
			var ok: bool = air.kit_move("cg_sy1" if aw else "cg_jh", t, true, false)
			if ok:
				player.cam.fov_punch(5.0)
			return ok
		1:
			var okp: bool = air.start_parry(DOMAIN_T if aw else PARRY_T, DOMAIN_R if aw else 0.0, 4 if aw else 1)
			if okp:
				_dom_live = aw
				Sfx.play("blade_draw", -6.0, 1.2)
				if aw:
					_domain_fx()
					HeroFx.send(player, FX_DOM, player.global_position + Vector3(0.0, 0.9, 0.0), Vector3.UP, 0.0)
			return okp
		2:
			return air.kit_move("cg_tl" if aw else "cg_lk", air.pick_target(), false, true)
		3:
			if aw:
				return air.kit_move("cg_yx", air.pick_target(), false, true)
			var tr := near_target(LY_R)
			if tr == null:
				return false       # 落英要绕着人打：身边没人放不出来（不进冷却）
			return air.kit_move("cg_ly1", tr, false, false)
	return false


func _tick(dt: float) -> void:
	var air := player.air
	var st: int = air.state
	if _dbg:
		var s := "%s/%s hit_done=%s" % [air.state_name(), air.move_id, str(air.get("_hit_done"))]
		if s != _dbg_last:
			_dbg_last = s
			print("[cg] %.2f %s t=%.2f gj=%s/%.2f marks=%d det=%d" % [Time.get_ticks_msec() * 0.001, s, float(air.get("_t")), str(_gj_on), _gj_t, int(stat["marks"]), int(stat["det"])])
	var hurt := st == air.A.HURT or st == air.A.BLOWN or st == air.A.CRUSH or st == air.A.DOWN or st == air.A.DEAD or st == air.A.GRABBED
	if _gj_on:
		if hurt or player.st != Player.St.AIR:
			_gj_on = false       # 归剑的半拍里挨了打 / 落了地：炸不出来，剑痕留着
		else:
			_gj_t -= dt
			if _gj_t <= 0.0:
				_detonate()
	if _gj_queue >= 0.0:
		_gj_queue -= dt
		if hurt:
			_gj_queue = -1.0
		elif _gj_queue <= 0.0 and not (st == air.A.ATTACK and not bool(air.get("_hit_done"))):
			_gj_queue = -1.0
			air.kit_move("cg_gj", air.target if Proj.alive(air.target) else null, false, false)
	if _dom_live and air.parry_t <= 0.0 and not (st == air.A.ATTACK and air.move_id == "cg_ctr"):
		# 剑域收了：身上有痕的一起归剑炸掉
		_dom_live = false
		if _any_marks() and not hurt:
			_gj_queue = 0.05
	if _yx_t >= 0.0:
		_yx_t -= dt
		if _yx_t <= 0.0:
			_yx_t = -1.0
			_yx_split()
	if is_instance_valid(_domain):
		_domain_t += dt
		_domain.global_position = player.global_position + Vector3(0.0, 0.9, 0.0)
		var k := clampf(_domain_t / DOMAIN_T, 0.0, 1.0)
		(_domain.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - k * k)
		_domain.rotation.y += dt * 2.5
		if _domain_t >= DOMAIN_T or air.parry_t <= 0.0:
			_domain.queue_free()
			_domain = null


func on_awaken() -> void:
	super.on_awaken()
	player.set_blade_glow(1.0)
	Sfx.play("skill_sword", -4.0, 0.9)


func on_awake_end() -> void:
	player.set_blade_glow(0.0)


func on_parried(_src: Node3D) -> void:
	stat["parries"] = int(stat["parries"]) + 1


## air_melee 的招式到了 起手 / 判定：这一招的画面和归剑的时机
func on_move_fx(tag: String, phase: String, id: String, _data: Dictionary) -> void:
	var air := player.air
	var c := player.center()
	var col := _col()
	var fwd: Vector3 = air._fwd()
	var cam := player.cam
	var a: Dictionary = air._atk
	if phase == "start":
		match tag:
			"jh":
				_jh_from = c
				Vfx.glint(player.melee.rig.hand_pos(), Color.WHITE.lerp(col, 0.3), 0.8)
				if id == "cg_jh":
					Sfx.play("blade_draw", -4.0, 1.1)
			"ly":
				var k := clampi(int(id.substr(5)) - 1, 0, LY_ANG.size() - 1)
				air._flash_step(LY_ANG[k])
			"lyg":
				_step_to_cam_side()
			"lk":
				Sfx.play("blade_draw", -6.0, 1.4)
			"yx":
				Vfx.cast_charge(c, Color.WHITE.lerp(col, 0.5), 0.5)
				Vfx.sky_ring(c, col, 2.8, 0.5)
				Sfx.play("ascend", -4.0, 1.1)
				cam.push_in(0.2)
			"awk":
				Vfx.glint(player.melee.rig.tip_pos(), Color.WHITE, 1.2)
				Sfx.play("skill_sword", -5.0, 1.1)
		return
	if phase != "hit":
		return
	if a.has("arc"):
		var t: Node3D = air.target
		if tag == "c3" and t != null and Proj.alive(t):
			# 转：一圈弧光画在对手身上，人贴着它闪到侧后（左右轮着来；不直着穿到正背后，那样从镜头看人被对手挡住）
			_arc(Proj.aim_of(t) - fwd * 0.2, fwd, int(a["arc"]))
			if not air._is_launched(t):
				_c3_side = -_c3_side
				air._flash_step(2.4 * _c3_side)
		elif bool(a.get("pass", false)) and t != null and Proj.alive(t):
			# 穿身而过的那几招：判定完人已经闪到对手身后了 —— 弧光画在对手身上、顺着穿过去的方向
			var tc := Proj.aim_of(t)
			var through: Vector3 = air._flat(c - tc)
			through = through.normalized() if through.length_squared() > 0.01 else -fwd
			_arc(tc - through * 1.2, through, int(a["arc"]))
		else:
			_arc(c, fwd, int(a["arc"]))
	match tag:
		"c4":
			stat["gj_cut"] = int(stat["gj_cut"]) + 1
			guijian(GJ_M1)
		"jh":
			var to := player.center()
			var d := to - _jh_from
			if d.length() > 1.5:
				line_fx(_jh_from, to + d.normalized() * 1.5, col)
				HeroFx.send(player, FX_LINE, _jh_from, d.normalized(), d.length() + 1.5)
			Sfx.play("swing_heavy", -5.0, 1.35)
		"ctr":
			Vfx.space_ring(c + fwd * 1.2, 1.6, col, 0.3, 0.05)
			if not (air.parry_r > 0.0 and air.parry_t > 0.0):
				_gj_queue = 0.14      # 听风：反斩之后自己接归剑（剑域里不接，留到收势）
		"gj", "lyg":
			guijian(GJ_SHOW)
		"yx":
			_yx_cut(c, fwd)
		"awk":
			Vfx.shockwave(c, Vector3.UP, Color.WHITE.lerp(col, 0.5), 1.5)
			_arc(c, fwd, 2)
			cam.push_in(0.2)
			cam.fov_punch(-5.0)


func _arc(c: Vector3, fwd: Vector3, idx: int) -> void:
	var big := _awake()
	arc_preset(c, fwd, idx, big, _col())
	HeroFx.send(player, FX_ARC, c, fwd, float(idx) + (0.5 if big else 0.0))


## 落英收尾：闪到对手靠镜头的这一侧（归剑转身之后正好面朝镜头、背对对手）
func _step_to_cam_side() -> void:
	var air := player.air
	var t: Node3D = air.target
	if t == null or not Proj.alive(t):
		return
	var cam3 := player.get_viewport().get_camera_3d()
	if cam3 == null:
		air._flash_step(PI)
		return
	var cur: Vector3 = air._dir_to(t)
	var want: Vector3 = air._flat(Proj.aim_of(t) - cam3.global_position)
	if want.length_squared() < 0.01:
		air._flash_step(PI)
		return
	# 再偏开一点：正挡在对手和镜头之间的话，后面炸开的那一下就看不全了
	air._flash_step(cur.signed_angle_to(want.normalized(), Vector3.UP) + 0.6)


# ---------- 裂空 / 天裂 ----------

## air_melee 的招式到了判定时刻、而这一招是「放东西」的（英雄表 proj 字段）
func on_proj(kind: String, _move_id: String, t: Node3D) -> void:
	if kind != "lk" and kind != "tl":
		return
	var big := kind == "tl"
	var c := player.center()
	var pos: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else c + player.air._fwd() * 12.0
	stat["rift"] = int(stat["rift"]) + 1
	rift_fx(pos, big, _col())
	HeroFx.send(player, FX_RIFT, pos, Vector3.UP, 1.0 if big else 0.0)
	var tip := player.melee.rig.tip_pos()
	Vfx.warp_line(tip, tip + (pos - c).normalized() * 2.2, _col())
	var n := TL_N if big else LK_N
	var tw := create_tween()
	tw.tween_interval(LK_DELAY)
	for k in n:
		tw.tween_callback(_rift_hit.bind(pos, TL_R if big else LK_R, TL_DMG if big else LK_DMG, k, n))
		tw.tween_interval(LK_GAP)


func _rift_hit(pos: Vector3, r: float, dmg: float, k: int, n: int) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var air := player.air
	var last := k == n - 1
	# 天裂五道里第 1 / 3 / 5 道留痕，裂空三道里第 1 / 3 道留痕
	var marks := 1 if k % 2 == 0 else 0
	for e in Proj.targets(get_tree()):
		if not Proj.alive(e):
			continue
		var ec := Proj.aim_of(e)
		var d := ec - pos
		if d.length() > r + Proj.body_r(e):
			continue
		var dir := d.normalized() if d.length_squared() > 0.04 else Vector3.UP
		var info := {"dmg": units(dmg), "dir": dir, "kb": 7.0 if last else 1.5, "stun": 0.55, "launch": "", "heavy": false,
				"ranged": true, "contact": ec, "pstun": 0.45}
		var res := _hit_one(e, info)
		if res == 0 or res == 2:
			stat["rift_hits"] = int(stat["rift_hits"]) + 1
			air._add_combo(float(info["dmg"]))
			Vfx.blade_hit(ec, Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), 0.0), _col(), 0.8)
			if marks > 0:
				add_mark(e, marks)
			if ec.distance_to(player.center()) < 40.0:
				player.cam.add_trauma(0.12)


## 裂空的画面：先是一圈往里收的细环（预告：这儿要裂），到点之后几道长斩痕交错着凭空划开
static func rift_fx(pos: Vector3, big: bool, col: Color) -> void:
	if not HeroFx.ok():
		return
	var r := TL_R if big else LK_R
	var n := TL_N if big else LK_N
	# 预告的圈：从外面一点收到正好是会被划到的范围（圈多大，裂开的地方就多大）
	var ring := Vfx._sprite(pos, Color.WHITE.lerp(col, 0.4), 1, r * 2.9)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * r * 2.1, LK_DELAY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ring.material_override, "shader_parameter/alpha", 0.0, 0.12)
	tw.tween_callback(ring.queue_free)
	Vfx.glint(pos, Color.WHITE.lerp(col, 0.3), 0.9)
	var cam := Vfx.root.get_viewport().get_camera_3d()
	var rx := cam.global_basis.x if cam != null else Vector3.RIGHT
	var uy := cam.global_basis.y if cam != null else Vector3.UP
	var a0 := randf() * PI
	for k in n:
		var a := a0 + PI * float(k) / float(n) + randf_range(-0.2, 0.2)
		var d := (rx * cos(a) + uy * sin(a)).normalized()
		var off := (rx * randf_range(-0.4, 0.4) + uy * randf_range(-0.4, 0.4)) * r * 0.35
		var t2 := Vfx.root.create_tween()
		t2.tween_interval(LK_DELAY + LK_GAP * float(k))
		t2.tween_callback(_rift_cut.bind(pos + off, d, r, col, k == n - 1, big))


static func _rift_cut(p: Vector3, d: Vector3, r: float, col: Color, last: bool, big: bool) -> void:
	if not HeroFx.ok():
		return
	var l := r * 1.35
	Vfx._stroke(p - d * l, p + d * l, Color.WHITE, 0.14, 0.05, 0.2)
	Vfx._stroke(p - d * l * 0.92, p + d * l * 0.92, Color.WHITE.lerp(col, 0.7), 0.34, 0.03, 0.26)
	Vfx.line_sparks(p, d, Color.WHITE.lerp(col, 0.4), 5 if Vfx.lite else 10, 26.0, 12.0, 0.25)
	Sfx.play("blade_cut", -4.0, 1.2 + 0.1 * randf())
	if last:
		Vfx.space_ring(p, r * 0.8, col, 0.4, 0.06)
		if not Vfx.lite:
			Vfx.space_crack(p, col, r * (0.5 if big else 0.6), 4 if big else 3, 0.42, 0.3)
		Sfx.play("shatter", -8.0, 1.3)


# ---------- 一线天 ----------

func _yx_cut(c: Vector3, fwd: Vector3) -> void:
	stat["yx"] = int(stat["yx"]) + 1
	_yx_c = c
	_yx_fwd = fwd
	_yx_hit.clear()
	yx_fx(c, fwd, _col())
	HeroFx.send(player, FX_YX, c, fwd, 0.0)
	Combat.slowmo(0.3, 0.1, 0.3)
	var cam := player.cam
	cam.fov_punch(10.0)
	cam.kick_rush(0.8)
	Sfx.play("blade_draw", 0.0, 0.75)
	Sfx.play("skill_sword", -3.0, 0.7)
	for e in Proj.targets(get_tree()):
		if not Proj.alive(e):
			continue
		var ec := Proj.aim_of(e)
		var v := ec - c
		var fl := Vector3(v.x, 0.0, v.z)
		if fl.length() > YX_R + Proj.body_r(e) or absf(v.y) > 7.0:
			continue
		if fl.length() > 1.5 and fl.normalized().dot(fwd) < YX_COS:
			continue
		var info := {"dmg": units(YX_CUT), "dir": fwd, "kb": 1.0, "stun": 1.1, "launch": "", "heavy": false, "brk": true,
				"contact": ec, "pstun": 0.9}
		var res := _hit_one(e, info)
		if res == 0 or res == 2:
			add_mark(e, 3)
			_yx_hit.append(e)
			Vfx.blade_hit(ec, fwd.cross(Vector3.UP), _col(), 1.2)
	_yx_t = YX_DELAY


func _yx_split() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var air := player.air
	var c := _yx_c
	var fwd := _yx_fwd
	yx_split_fx(c, fwd, _col())
	HeroFx.send(player, FX_YX2, c, fwd, 0.0)
	var cam := player.cam
	cam.add_trauma(0.7)
	cam.fov_punch(12.0)
	Combat.hitstop(0.12)
	Sfx.play("cut_burst", 2.0, 0.8)
	Sfx.play("shatter", -2.0, 0.8)
	Sfx.play("slam", -3.0, 0.9)
	for t: Variant in _yx_hit:
		if not is_instance_valid(t) or not Proj.alive(t):
			continue
		var e := t as Node3D
		var ec := Proj.aim_of(e)
		var dir: Vector3 = air._flat(ec - c)
		dir = dir.normalized() if dir.length_squared() > 0.01 else fwd
		var info := {"dmg": units(YX_SPLIT), "dir": dir, "kb": 36.0, "stun": 1.0, "launch": "fwd", "heavy": true, "brk": true,
				"ranged": true, "contact": ec}
		var res := _hit_one(e, info)
		if res == 0 or res == 2:
			stat["yx_hits"] = int(stat["yx_hits"]) + 1
			air._add_combo(float(info["dmg"]))
			if e.has_method("is_launched") and bool(e.call("is_launched")):
				air._on_launch(e, "fwd", ec, dir, 0.12)
	_yx_hit.clear()
	# 贴着地放的：沿着那一线把地犁开
	var a := c + fwd * 2.5
	var b := c + fwd * YX_R
	var ga := floor_y(a)
	var gb := floor_y(b)
	if a.y - ga < 5.0 or b.y - gb < 5.0:
		trench(Vector3(a.x, minf(a.y, ga + 0.5), a.z), Vector3(b.x, minf(b.y, gb + 0.5), b.z), 1.5, 1.3)
	_detonate()
	air.end_awaken()


## 横抹：一道铺到面前的大弧光 + 远处横着的一线（先只是一线，挂着）
static func yx_fx(c: Vector3, fwd: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var side := fwd.cross(Vector3.UP).normalized()
	slash(c + fwd * 0.3, fwd, side, YX_R * 0.82, 170, col, 0.5)
	slash(c + fwd * 0.3, fwd, side, YX_R * 0.42, 170, Color.WHITE, 0.36)
	var mid := c + fwd * YX_R * 0.55
	Vfx._stroke(mid - side * 30.0, mid + side * 30.0, Color.WHITE, 0.07, YX_DELAY, 0.12, true)
	Vfx._stroke(mid - side * 30.0, mid + side * 30.0, Color.WHITE.lerp(col, 0.7), 0.2, YX_DELAY, 0.12)
	Vfx.line_sparks(c + fwd * 2.0, side, Color.WHITE.lerp(col, 0.4), 10 if Vfx.lite else 22, 50.0, 10.0, 0.4)


## 齐断：那一线上一排裂隙张开、合上
static func yx_split_fx(c: Vector3, fwd: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var side := fwd.cross(Vector3.UP).normalized()
	var mid := c + fwd * YX_R * 0.55
	Vfx._stroke(mid - side * 34.0, mid + side * 34.0, Color.WHITE, 0.5, 0.04, 0.3)
	Vfx._stroke(mid - side * 34.0 + Vector3.UP * 0.25, mid + side * 34.0 + Vector3.UP * 0.25, Color.WHITE.lerp(col, 0.6), 0.9, 0.02, 0.36)
	var n := 3 if Vfx.lite else 5
	for i in n:
		var p := mid + side * (float(i) - float(n - 1) * 0.5) * 6.5
		Vfx.rift(p, fwd, col, 2.2, 0.45)
		Vfx.shockwave(p, Vector3.UP, Color.WHITE.lerp(col, 0.4), 1.6)
	Vfx.space_ring(mid, 9.0, col, 0.6, 0.09)
	if not Vfx.lite:
		Vfx.space_crack(mid, col, 3.2, 5, 0.5, 0.4)


# ---------- 剑域的圈 ----------

func _domain_fx() -> void:
	if is_instance_valid(_domain):
		_domain.queue_free()
	_domain = domain_ring(player.global_position + Vector3(0.0, 0.9, 0.0), _col())
	_domain_t = 0.0
	Vfx.shockwave(player.center(), Vector3.UP, Color.WHITE.lerp(_col(), 0.5), 1.6)


static func domain_ring(pos: Vector3, col: Color) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = DOMAIN_R - 0.08
	tm.outer_radius = DOMAIN_R
	tm.rings = 48
	tm.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(Color.WHITE.lerp(col, 0.5), 0.55)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	mi.global_position = pos
	return mi


# ---------- 斩击的弧光（一片又薄又利的新月：一个网格、一次绘制）----------

## 新月网格：躺在 XZ 平面上、朝 -Z 鼓出去，从 -X 一侧扫到 +X 一侧（+X 是剑尖去的方向，那一头更厚）；外缘实、往里淡掉
static func arc_mesh(span: int) -> ArrayMesh:
	var key := "cg_arc_%d" % span
	if Vfx.root.has_meta(key):
		return Vfx.root.get_meta(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 30 if span > 200 else 18
	var half := deg_to_rad(float(span)) * 0.5
	var rows: Array = []
	for i in seg + 1:
		var u := float(i) / float(seg)
		var a := lerpf(-half, half, u)
		var w := 0.17 * pow(sin(PI * u), 0.7) * (0.4 + 0.6 * u)
		var ends := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.9, 1.0, u))
		var dirv := Vector3(sin(a), 0.0, -cos(a))
		rows.append([dirv, dirv * (1.0 - w * 0.28), dirv * (1.0 - w), ends])
	for i in seg:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var e0: float = r0[3]
		var e1: float = r1[3]
		var co0 := Color(1, 1, 1, e0)
		var co1 := Color(1, 1, 1, e1)
		var cm0 := Color(1, 1, 1, 0.6 * e0)
		var cm1 := Color(1, 1, 1, 0.6 * e1)
		var ci := Color(1, 1, 1, 0.0)
		for q: Array in [[r0[0], co0, r1[0], co1, r1[1], cm1], [r0[0], co0, r1[1], cm1, r0[1], cm0],
				[r0[1], cm0, r1[1], cm1, r1[2], ci], [r0[1], cm0, r1[2], ci, r0[2], ci]]:
			for j in 3:
				st.set_normal(Vector3.UP)
				st.set_color(q[j * 2 + 1])
				st.add_vertex(q[j * 2])
	var m := st.commit()
	Vfx.root.set_meta(key, m)
	return m


## 一道弧光：圆心 center，朝 fwd 鼓出去，沿 swing 的方向扫过（swing 不必和 fwd 垂直），半径 radius。带一点顺着挥剑方向的转动，随即淡掉
static func slash(center: Vector3, fwd: Vector3, swing: Vector3, radius: float, span: int, col: Color, dur := 0.2) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var z := -fwd.normalized()
	var x := swing - z * swing.dot(z)
	if x.length_squared() < 1e-5:
		x = Vector3.UP.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_fog = true
	var cc := Color.WHITE.lerp(col, 0.3)
	m.albedo_color = Color(cc.r, cc.g, cc.b, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = arc_mesh(span)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	mi.global_transform = Transform3D(b.rotated(y, 0.42).scaled(Vector3.ONE * radius * 0.86), center)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_transform", Transform3D(b.rotated(y, -0.12).scaled(Vector3.ONE * radius * 1.08), center), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur * 0.6).set_delay(dur * 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


static func arc_preset(center: Vector3, fwd: Vector3, idx: int, big: bool, col: Color) -> void:
	if idx < 0 or idx >= ARCS.size():
		return
	var a: Array = ARCS[idx]
	var f := fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var side := f.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(f).normalized()
	var swing := side * float(a[0]) + up * float(a[1])
	var r := float(a[2]) * (1.45 if big else 1.0)
	slash(center + f * 0.2, f, swing, r, int(a[3]), col, 0.2 if int(a[3]) < 200 else 0.26)
	if big and not Vfx.lite:
		slash(center + f * 0.2, f, swing, r * 0.72, int(a[3]), Color.WHITE, 0.16)


## 惊鸿 / 瞬狱的那一线：从起点到终点一道又细又直的光，停一瞬再淡
static func line_fx(from: Vector3, to: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	Vfx._stroke(from, to, Color.WHITE, 0.09, 0.1, 0.2)
	Vfx._stroke(from, to, Color.WHITE.lerp(col, 0.7), 0.3, 0.04, 0.24)
	Vfx.glint(to, Color.WHITE.lerp(col, 0.3), 0.8)


# ---------- 别人那边只画（net.gd → hero_fx.gd 的 remote）----------

static func _center_of(n: Node3D) -> Vector3:
	if n is EnemyDummy:
		return (n as EnemyDummy).aim_point()
	if n.has_method("center"):
		return n.call("center")
	return n.global_position + Vector3(0.0, 1.0, 0.0)


## pos 附近（r 米内）最近的一个人 / 怪 / 木桩（含本机主角）
static func _node_near(pos: Vector3, r: float) -> Node3D:
	if not HeroFx.ok():
		return null
	var tree := Vfx.root.get_tree()
	var best: Node3D = null
	var bd := r
	var list: Array = []
	list.append_array(Proj.targets(tree))
	list.append_array(tree.get_nodes_in_group("player"))
	for n: Variant in list:
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		var d := _center_of(e).distance_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


static func remote_fx(kind: int, pos: Vector3, dir: Vector3, roll: float, col: Color) -> void:
	match kind:
		FX_ARC:
			arc_preset(pos, dir, int(floorf(roll)), roll - floorf(roll) > 0.25, col)
		FX_RIFT:
			rift_fx(pos, roll > 0.5, col)
		FX_MARK:
			var t := _node_near(pos, 5.0)
			if t == null:
				return
			var v: MarkView = null
			var old: Variant = t.get_meta(META_RMARK) if t.has_meta(META_RMARK) else null      # get_meta 的缺省值给 null 等于没给：没有这条 meta 时照样报错
			if is_instance_valid(old) and not (old as MarkView)._bursting:
				v = old
			else:
				v = _new_view(t, col)
				t.set_meta(META_RMARK, v)
			v.set_n(clampi(int(roll), 0, MARK_MAX_AW))
			v.life = MARK_LIFE
		FX_DET:
			var t2 := _node_near(pos, 6.0)
			var old2: Variant = t2.get_meta(META_RMARK) if t2 != null and t2.has_meta(META_RMARK) else null
			if is_instance_valid(old2) and not (old2 as MarkView)._bursting:
				var v2: MarkView = old2
				var n := v2.n
				v2.burst(GJ_GAP)
				t2.remove_meta(META_RMARK)
				var tw := Vfx.root.create_tween()
				tw.tween_interval(GJ_GAP * float(n))
				tw.tween_callback(det_fx.bind(pos, Vector3.FORWARD, n, n >= MARK_MAX, col))
			else:
				det_fx(pos, Vector3.FORWARD, int(roll), int(roll) >= MARK_MAX, col)
		FX_LINE:
			line_fx(pos, pos + dir * clampf(roll, 1.0, 40.0), col)
		FX_YX:
			yx_fx(pos, dir, col)
		FX_YX2:
			yx_split_fx(pos, dir, col)
		FX_DOM:
			var ring := domain_ring(pos, col)
			var tr := ring.create_tween()
			tr.tween_property(ring.material_override, "albedo_color:a", 0.0, DOMAIN_T).set_ease(Tween.EASE_IN)
			tr.parallel().tween_property(ring, "rotation:y", 4.0, DOMAIN_T)
			tr.tween_callback(ring.queue_free)
