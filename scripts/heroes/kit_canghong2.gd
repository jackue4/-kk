extends "res://scripts/kit_base.gd"
## 英雄「苍鸿」（剑修）的技能脚本（2026-11-25 TSB 式重做：藏锋 / 拔剑术 + 剑痕引爆）。招式数据在 def_canghong.gd，状态机是 air_melee.gd；
## 这里管：剑痕（记在目标身上、画出来、联机同步）、归剑引爆、四个技能出哪一招、斩击的弧光 / 裂空的斩痕 / 一线天的画面。
##   E 惊鸿 → 觉醒 瞬狱   Z 听风 → 剑域   Q 裂空 → 天裂   R 落英 → 一线天（终结）
## 剑痕怎么来：凡是经 air_melee 结算、真的打中了（没被护体挡下）的那一下，都会发 combat_event "air_hit" —— 这里听这个事件给锁着的目标加痕
## （招式的 marks 字段 = 加几道，缺省 1）；裂空 / 一线天这些自己判定的招自己加。
## 画面的联机同步：别人那边只画不判伤害，HeroFx.send(kind …) → 对面 remote_fx（号段 40 ~ 69）。
## 故意不写 class_name。

const MarkView := preload("res://scripts/heroes/cg_mark_view.gd")
const CgFx := preload("res://scripts/heroes/cg_fx.gd")
const Wave := preload("res://scripts/heroes/cg_wave.gd")
const UltCine := preload("res://scripts/heroes/cg_ult_cine.gd")
const AwakenCine := preload("res://scripts/awaken_cine.gd")

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
## 一线天（2026-11-25 第四轮，用户：「飞出去的刀光可以延长一下飞行的距离，现在一下就没了，强化一下」）：
## 横抹出去的是一道真的往前飞的巨大刀光（横着 18 米宽），飞 YX_R 米、一路贯穿；扫到谁谁先挨 YX_CUT、留三道痕，
## 归剑定住之后（YX_DELAY）一线齐断：扫到过的每人 YX_SPLIT + 所有剑痕；齐断之后才被扫到的当场补上。
const YX_R := 70.0            # 刀光飞多远
const YX_SPEED := 50.0        # 每秒多少米（飞完约 1.4 秒）
const YX_RAD := 9.0           # 刀光的半径（横着一半的宽度）
const YX_CUT := 0.4           # 被刀光扫到的那一下
const YX_SPLIT := 2.0         # 一线齐断
const YX_DELAY := 1.2         # 横抹之后多久断
## 斩击弧光的预设：[挥剑方向 x（右）, y（上）, 半径, 张角（度）]，招式的 arc 字段填序号
const ARCS: Array = [
	[0.8, 0.6, 2.9, 150],       # 0 起：左下 → 右上
	[-1.0, -0.12, 3.0, 150],    # 1 承：右 → 左平抹
	[1.0, 0.0, 3.0, 300],       # 2 转：绕身一圈
	[-0.6, -0.8, 2.4, 120],     # 3 收：短促斜劈
	[0.15, 1.0, 3.0, 150],      # 4 自下而上
	[-0.1, -1.0, 3.0, 150],     # 5 自上而下
	[1.0, 0.04, 4.2, 170],      # 6 平掠（惊鸿 / 瞬狱）
	[1.0, 0.05, 3.1, 160],      # 7 掠：反手自左向右（觉醒平砍一）
	[-0.75, -0.7, 3.0, 150],    # 8 落：右上 → 左下（觉醒平砍二）
	[-0.05, -1.0, 3.2, 160],    # 9 纵：直劈（觉醒平砍四）
]
## E 飞光 / 觉醒 赤霄（2026-11-25 第三轮）：连按的那一串。每一式一道飞出去的刀光（scripts/heroes/cg_wave.gd）
const E_MOVES: Array[String] = ["cg_w1", "cg_w2", "cg_w3"]
const E_MOVES_AW: Array[String] = ["cg_x1", "cg_x2", "cg_x3", "cg_x4", "cg_x5", "cg_x6"]
const E_DMG: Array[float] = [0.5, 0.5, 0.7]
const E_DMG_AW: Array[float] = [0.4, 0.4, 0.4, 0.4, 0.4, 0.9]
## 每一式的刀光怎么斜（和挥剑的架势对上）：[右, 上]
const E_SWING: Array = [[-1.0, 0.08], [0.7, 0.75], [0.06, -1.0]]
const E_SWING_AW: Array = [[1.0, 0.0], [1.0, 0.12], [0.7, 0.75], [-0.75, -0.7], [0.06, -1.0], [0.75, 0.68]]
const E_WIN := 1.2            # 放完一下之后这么久之内可以接下一下；过了这一串就算完、冷却开始转
const E_GAP := 0.18           # 两下之间最少隔这么久
const NUM: Array[String] = ["", "一", "二", "三", "四", "五", "六"]
## 蓄力放的光刀（2026-11-25 第五轮）：平时一道青白的光刀；觉醒 = 一道巨大的血刃，一路把空气劈开（用户给了两张参考图）。
## 蓄得越久越大、越疼；蓄过半破防。松手时的方向决定这一刀怎么斜、把人往哪打（照旧：平 / 上挑 / 下劈）
const CS_MOVE := {"fwd": "cg_cs_f", "up": "cg_cs_u", "down": "cg_cs_d"}
const CS_SWING := {"fwd": [1.0, 0.06], "up": [0.25, 1.0], "down": [-0.2, -1.0]}
const CS_DMG := 1.2           # 平时：1.2 + 1.0 × 蓄力
const CS_DMG_K := 1.0
const CS_DMG_AW := 1.6        # 觉醒：1.6 + 1.4 × 蓄力（贯穿）
const CS_DMG_AW_K := 1.4
const FX_CS := 50             # 蓄力的光刀 / 血刃：pos 起点，dir 方向，roll = 蓄力 0~1 的百分数 + 100 × 方向（0 平 1 上 2 下）+ 1000 × 觉醒
## 联机画面号
const FX_ARC := 40            # 一道弧光：roll = 预设序号（+0.5 = 觉醒的大号）
const FX_RIFT := 41           # 裂空 / 天裂：pos = 裂开的位置，roll 1 = 天裂
const FX_MARK := 42           # 剑痕数变了：pos = 目标位置，roll = 现在几道
const FX_DET := 43            # 归剑引爆：pos = 目标位置
const FX_LINE := 44           # 惊鸿 / 瞬狱的一线：pos 起点，dir × roll 终点
const FX_YX := 45             # 一线天横抹
const FX_YX2 := 46            # 一线天齐断
const FX_DOM := 47            # 剑域的圈：pos 圆心
const FX_WAVE := 48           # 飞光 / 赤霄的一道刀光：pos 起点，dir 方向，roll = 第几式（+10 = 觉醒）
const FX_HIT := 49            # 剑砍中人的斩线 + 针芒：pos 命中点，dir 挥剑方向，roll = 1 觉醒 + 2 重手

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
var _yx_done := true                     # 这一回的齐断已经断过了（之后才被刀光扫到的当场补）
var _dbg := false
var _c3_side := 1.0
var _dbg_last := ""
var _e_k := 0                            # 飞光这一串已经放了几下（0 = 不在放）
var _e_aw := false                       # 这一串是不是觉醒的
var _e_win := 0.0
var _e_gap := 0.0
var _e_buf := 0.0
var _blade_em := Color.WHITE
var _blade_saved := false
var _cine: Node = null
var _cs_k := 0.0                         # 这一记蓄力蓄了几成
var _cs_kind := "fwd"


func _init() -> void:
	_dbg = OS.get_cmdline_user_args().has("--cg-dbg")
	stat = {"marks": 0, "det": 0, "det_dmg": 0.0, "parries": 0, "rift": 0, "rift_hits": 0, "yx": 0, "yx_hits": 0, "gj_cut": 0, "waves": 0, "wave_hits": 0, "cs": 0, "cs_hits": 0}


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
	_blade_tint(false)
	if is_instance_valid(_cine):
		_cine.queue_free()
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
		# 砍中了：顺着这一剑的刀路，一道贯穿对手的斩线 + 迸出来的针芒（第三轮：以前只有一弯细弧，看不清）
		var a: Dictionary = air._atk if air.state == air.A.ATTACK else {}
		var fwd: Vector3 = air._fwd()
		var sw := swing_of(int(a.get("arc", 0)), fwd)
		var heavy := bool(_info.get("heavy", false)) or int(a.get("tier", 0)) >= 1
		var aw := _awake()
		var tc := Proj.aim_of(t)
		CgFx.hit_fx(tc, sw, fwd, _col(), aw, heavy)
		HeroFx.send(player, FX_HIT, tc, sw, (1.0 if aw else 0.0) + (2.0 if heavy else 0.0))


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
		HeroFx.send(player, FX_DET, mv.center(), Vector3.UP, float(n) + (100.0 if _awake() else 0.0))
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
	det_fx(ec, dir, n, full, _col(), _awake())
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


## 剑痕炸开的那一下：每道剑痕各是一道贯穿的斩线（最多画四道）+ 往四面迸的针芒 + 一圈震波；三道以上荡开空间波动，满痕再裂几道空间裂缝
static func det_fx(pos: Vector3, dir: Vector3, n: int, full: bool, col: Color, aw := false) -> void:
	if not HeroFx.ok():
		return
	var k := clampf(0.6 + 0.14 * float(n), 0.7, 1.8)
	var mc := CgFx.main_col(col, aw)
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var lines := mini(n, 2 if Vfx.lite else 4)
	for i in lines:
		var a := PI * (float(i) + randf_range(0.15, 0.85)) / float(lines)
		CgFx.cut(pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), 0.0), side * cos(a) + Vector3.UP * sin(a), 3.4 * k, col, aw, 0.05, 0.9)
	CgFx.needles(pos, dir, 1, col, aw, 1.9 + 0.3 * float(n), 0.36)
	Vfx.shockwave(pos, dir, Color.WHITE.lerp(mc, 0.4), 0.9 * k)
	if n >= MARK_HEAVY:
		Vfx.space_ring(pos, 1.8 * k, mc, 0.42, 0.06)
	if full and not Vfx.lite:
		Vfx.space_crack(pos, mc, 1.6, 3, 0.4, 0.3)


# ---------- 技能 ----------

func _cast(i: int, aw: bool) -> bool:
	var air := player.air
	match i:
		0:
			var ok: bool = air.kit_move(_e_moves(aw)[0], air.pick_target(), false, true)
			if ok:
				_e_k = 1
				_e_aw = aw
				_e_win = E_WIN
				_e_gap = E_GAP
				_e_buf = 0.0
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


# ---------- 蓄力：放一道飞出去的光刀 / 血刃 ----------

## air_melee 松开蓄力时来问（k = 蓄了几成 0~1，kind = fwd / up / down）：接了返回 true，这一下就不走老的冲过去重击
func on_charge_release(k: float, kind: String) -> bool:
	var air := player.air
	_cs_k = clampf(k, 0.0, 1.0)
	_cs_kind = kind if CS_MOVE.has(kind) else "fwd"
	var tv: Variant = air.target      # 可能已经被释放了（怪死了）：先验有效
	return air.kit_move(str(CS_MOVE[_cs_kind]), (tv as Node3D) if is_instance_valid(tv) else null, false, true)


static func cs_swing(d: Vector3, kind: String) -> Vector3:
	var sw: Array = CS_SWING.get(kind, CS_SWING["fwd"])
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(d).normalized()
	return (side * float(sw[0]) + up * float(sw[1])).normalized()


## 那一刀挥出去了（招式到了判定时刻 → on_proj("cs")）
func _cs_proj(t: Node3D) -> void:
	var air := player.air
	var aw := _awake()
	var k := _cs_k
	var kind := _cs_kind
	var c := player.center()
	var d := aim_dir(t)
	var col := _col()
	var swing := cs_swing(d, kind)
	stat["cs"] = int(stat["cs"]) + 1
	var from := c + d * 1.6
	cs_fx(from, d, swing, k, aw, col)
	cs_wave(from, d, swing, k, aw, col, player, _cs_hit.bind(k, kind, aw, d))
	HeroFx.send(player, FX_CS, from, d, roundf(k * 99.0) + 100.0 * float(["fwd", "up", "down"].find(kind)) + (1000.0 if aw else 0.0))
	Vfx.glint(player.melee.rig.tip_pos(), Color.WHITE, 1.2)
	air._warp(c + d * 2.5, 1.2 + 1.0 * k)
	var cam := player.cam
	cam.fov_punch(7.0 + 6.0 * k)
	cam.add_trauma((0.4 if aw else 0.28) + 0.2 * k)
	cam.kick_rush(0.7)
	if aw:
		cam.impact(0.3)
	Sfx.play("swing_heavy", -2.0, 0.7 if aw else 0.95)
	Sfx.play("blade_draw", -4.0, 0.8 if aw else 1.1)
	if aw:
		Sfx.play("cut_burst", -5.0, 0.7)
		# 贴着地放的：沿着血刃飞出去的方向把地犁开一段
		var a := c + d * 3.0
		var b := c + d * (16.0 + 14.0 * k)
		if a.y - floor_y(a) < 5.0:
			trench(Vector3(a.x, minf(a.y, floor_y(a) + 0.5), a.z), Vector3(b.x, minf(b.y, floor_y(b) + 0.5), b.z), 1.4, 1.2)


## 出手那一下的画面：身前一道大弧 + 一圈立着的空间波动；血刃再加一圈黑红的气浪
static func cs_fx(from: Vector3, d: Vector3, swing: Vector3, k: float, aw: bool, col: Color) -> void:
	if not HeroFx.ok():
		return
	var r := (5.0 + 2.5 * k) if aw else (3.2 + 1.0 * k)
	CgFx.slash(from - d * 1.2, d, swing, r, 160, col, aw, 0.3)
	CgFx.air_split(from, d, r * 0.7, col, aw, aw)
	CgFx.needles(from, d, 3, col, aw, r * 1.2, 0.35, 0.09, 14)


## 飞出去的那一道。平时：一道青白光刀，飞 50 米，打中第一个人炸开；觉醒：巨大的血刃（半径 5 ~ 7.5 米、外面裹着暗红的影），
## 飞 75 米、贯穿、越飞越大，每隔几米把空气劈开一圈（cg_fx.air_split）
static func cs_wave(from: Vector3, d: Vector3, swing: Vector3, k: float, aw: bool, col: Color, who: Node3D, cb: Callable) -> void:
	if not HeroFx.ok():
		return
	var w: Node3D = Wave.new()
	var r := (5.0 + 2.5 * k) if aw else (2.8 + 1.2 * k)
	w.set("dir", d)
	w.set("swing", swing)
	w.set("aw", aw)
	w.set("big", true)
	w.set("col", col)
	w.set("pierce", aw)
	w.set("radius", r)
	w.set("hit_r", 1.0 + r * (0.5 if aw else 0.3))
	w.set("speed", 54.0 if aw else 58.0)
	w.set("reach", 75.0 if aw else 50.0)
	w.set("split", 2 if aw else 1)
	w.set("ring_gap", 4.0 if aw else 6.0)
	w.set("ring_r", r * (0.9 if aw else 0.8))
	w.set("smoke", aw)
	w.set("skim", aw)
	w.set("grow_far", 1.5 if aw else 1.0)
	w.set("skip", who)
	w.set("on_hit", cb)
	w.set("clash_k", k)       # 能和迎面来的另一道蓄力刀光对冲（cg_wave._meet → cg_clash.gd）
	# 场景破坏：血刃一路把碰到的方块打碎（贴着地犁过去，力度拉满）；平时的光刀只在打中的地方崩一小块浅坑
	# （第一版平时的也很猛，用户：「未觉醒的蓄力刀光效果太强了……可以弱化一半，觉醒的刀光可以强一点」）
	w.set("wreck", (1.9 + 0.6 * k) if aw else (0.45 + 0.25 * k))
	w.set("wreck_rk", 1.0 if aw else 0.5)
	w.set("wreck_shallow", not aw)
	w.set("wreck_path", aw)
	if who != null and who.get("kit") != null and (who.get("kit") as Node).has_method("on_wave_clash"):
		w.set("on_clash", Callable(who.get("kit"), "on_wave_clash"))
	if who != null and not aw:
		w.set("floor_fn", func(p: Vector3) -> float: return HeroFx.floor_y(who, p))
	w.position = from
	Vfx.root.add_child(w)


## 我放的那一道和对面的一道顶上了（强度一样）：镜头和黑白帧给我
func on_wave_clash(cl: Node) -> void:
	stat["cs_clash"] = int(stat.get("cs_clash", 0)) + 1
	if is_instance_valid(player) and not player.dead and AwakenCine.enabled:
		cl.call("attach", player)


func _cs_hit(e: Node3D, pos: Vector3, k: float, kind: String, aw: bool, d: Vector3) -> void:
	if not is_instance_valid(player) or player.dead or not is_instance_valid(e) or not Proj.alive(e):
		return
	var air := player.air
	var dmg := units((CS_DMG_AW + CS_DMG_AW_K * k) if aw else (CS_DMG + CS_DMG_K * k))
	var kd: Vector3 = d
	if kind == "up":
		kd = (d * 0.35 + Vector3.UP).normalized()
	elif kind == "down":
		kd = (d * 0.35 + Vector3.DOWN).normalized()
	var info := {"dmg": dmg, "dir": kd, "kb": (38.0 if aw else 30.0) * (0.85 + 0.3 * k), "stun": 1.0, "launch": kind, "heavy": true,
			"brk": k >= 0.5, "ranged": true, "contact": pos, "pstun": 0.7}
	var res := _hit_one(e, info)
	if res != 0 and res != 2:
		return
	stat["cs_hits"] = int(stat["cs_hits"]) + 1
	add_mark(e, 2)
	air._add_combo(dmg)
	if pos.distance_to(player.center()) < 60.0:
		player.cam.add_trauma(0.4)
		Combat.hitstop(0.08 + 0.05 * k)
	if aw:
		CgFx.wave_hit(pos, d, cs_swing(d, kind), _col(), true, true)
	if e.has_method("is_launched") and bool(e.call("is_launched")):
		air._on_launch(e, kind, pos, kd, 0.12)


# ---------- E 飞光 / 赤霄：连按的那一串 ----------

func _e_moves(aw: bool) -> Array[String]:
	return E_MOVES_AW if aw else E_MOVES


## 这一串还没放完时再按 E = 接下一下（不看冷却：冷却要等这一串放完 / 断了才开始转）
func press(i: int) -> void:
	if i == 0 and _e_k > 0:
		if not _e_fire():
			_e_buf = BUFFER       # 上一剑还没挥出去：先记着，一能出就出
		return
	super.press(i)


func _commit(i: int, aw: bool) -> void:
	super._commit(i, aw)
	if i == 0 and _e_k > 0:
		if aw:
			cds_aw[0] = 0.0
		else:
			cds[0] = 0.0


func _e_fire() -> bool:
	if player.dead or player.is_downed() or player.ult.active or _e_gap > 0.0:
		return false
	var mv := _e_moves(_e_aw)
	if _e_k <= 0 or _e_k >= mv.size() or _awake() != _e_aw:
		return false
	if not player.air.kit_move(mv[_e_k], player.air.pick_target(), false, true):
		return false
	_e_k += 1
	_e_win = E_WIN
	_e_gap = E_GAP
	_e_buf = 0.0
	if _e_k >= mv.size():
		_e_close()
	return true


## 这一串到此为止：冷却开始转
func _e_close() -> void:
	if _e_k <= 0:
		return
	_e_k = 0
	_e_buf = 0.0
	if _e_aw:
		cds_aw[0] = _cd_full(0, true)
	else:
		cds[0] = _cd_full(0, false)


## 触屏键上的字：一串没放完时显示还能接几下
func touch_text(i: int) -> String:
	if i == 0 and _e_k > 0:
		return NUM[clampi(_e_moves(_e_aw).size() - _e_k, 0, NUM.size() - 1)]
	return super.touch_text(i)


## 一式的刀光出手（air_melee 的招到了判定时刻 → on_proj("w")）
func _e_proj(move_id: String, t: Node3D) -> void:
	var aw := move_id.begins_with("cg_x")
	var mv := _e_moves(aw)
	var k := maxi(mv.find(move_id), 0)
	var last := k == mv.size() - 1
	var air := player.air
	var c := player.center()
	var d := aim_dir(t)
	var col := _col()
	var swing := e_swing(d, k, aw, false)
	stat["waves"] = int(stat["waves"]) + 1
	# 出手：身前一道挥剑的弧、剑尖一闪、空间一扭
	CgFx.slash(c + d * 0.2, d, swing, 3.5 if aw else 3.0, 160, col, aw, 0.24)
	Vfx.glint(player.melee.rig.tip_pos(), Color.WHITE, 0.9)
	air._warp(c + d * 2.0, 1.0 if last else 0.6)
	var cam := player.cam
	cam.fov_punch(6.0 if last else 3.0)
	cam.add_trauma(0.24 if last else 0.1)
	Sfx.play("swing_heavy", -4.0 if last else -6.0, (0.95 if last else 1.5) - 0.05 * float(k))
	Sfx.play("blade_draw", -8.0, 1.25 + 0.06 * float(k))
	var from := c + d * 1.4
	wave_spawn(from, d, swing, aw, last, col, player, _wave_hit.bind(k, aw, last, d), false)
	if aw and last:
		# 觉醒收尾：交叉的两道（第二道只画）
		var sw2 := e_swing(d, k, aw, true)
		CgFx.slash(c + d * 0.2, d, sw2, 3.5, 160, col, aw, 0.28)
		wave_spawn(from, d, sw2, aw, last, col, player, Callable(), true)
	HeroFx.send(player, FX_WAVE, from, d, float(k) + (10.0 if aw else 0.0))


## 第 k 式的刀光朝哪斜（mirror = 交叉的另一道）
static func e_swing(d: Vector3, k: int, aw: bool, mirror: bool) -> Vector3:
	var tab: Array = E_SWING_AW if aw else E_SWING
	var sw: Array = tab[clampi(k, 0, tab.size() - 1)]
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(d).normalized()
	return (side * float(sw[0]) * (-1.0 if mirror else 1.0) + up * float(sw[1])).normalized()


## 放一道飞出去的刀光。who = 放它的人（本机主角；别人放的给 null：只画），cb = 打中了谁的回调，quiet = 只画的第二道
static func wave_spawn(from: Vector3, d: Vector3, swing: Vector3, aw: bool, big: bool, col: Color, who: Node3D, cb: Callable, quiet: bool) -> void:
	if not HeroFx.ok():
		return
	var w: Node3D = Wave.new()
	w.set("dir", d)
	w.set("swing", swing)
	w.set("aw", aw)
	w.set("big", big)
	w.set("col", col)
	w.set("pierce", aw and not big)
	w.set("quiet", quiet)
	var r := (3.4 if aw else 2.6) * (1.35 if big else 1.0)
	w.set("radius", r)
	w.set("hit_r", 1.1 + r * 0.25)
	w.set("skip", who)
	w.set("on_hit", cb)
	w.set("reach", 56.0 if aw else 44.0)
	if who != null:
		w.set("floor_fn", func(p: Vector3) -> float: return HeroFx.floor_y(who, p))
	w.position = from
	Vfx.root.add_child(w)


func _wave_hit(e: Node3D, pos: Vector3, k: int, aw: bool, last: bool, d: Vector3) -> void:
	if not is_instance_valid(player) or player.dead or not is_instance_valid(e) or not Proj.alive(e):
		return
	var air := player.air
	var tab: Array[float] = E_DMG_AW if aw else E_DMG
	var dmg := units(tab[clampi(k, 0, tab.size() - 1)])
	var blow := last and aw
	var info := {"dmg": dmg, "dir": d, "kb": (30.0 if aw else 20.0) if last else 2.5, "stun": 0.85 if last else 0.5,
			"launch": "fwd" if blow else "", "heavy": last, "ranged": true, "contact": pos, "pstun": 0.6 if last else 0.4}
	var res := _hit_one(e, info)
	if res != 0 and res != 2:
		return
	stat["wave_hits"] = int(stat["wave_hits"]) + 1
	add_mark(e, 1)
	air._add_combo(dmg)
	if pos.distance_to(player.center()) < 45.0:
		player.cam.add_trauma(0.3 if last else 0.14)
		Combat.hitstop(0.07 if last else 0.03)
		if blow:
			player.cam.impact(0.3)
	if blow and e.has_method("is_launched") and bool(e.call("is_launched")):
		air._on_launch(e, "fwd", pos, d, 0.1)


func _tick(dt: float) -> void:
	var air := player.air
	var st: int = air.state
	if _dbg:
		var s := "%s/%s hit_done=%s" % [air.state_name(), air.move_id, str(air.get("_hit_done"))]
		if s != _dbg_last:
			_dbg_last = s
			print("[cg] %.2f %s t=%.2f gj=%s/%.2f marks=%d det=%d" % [Time.get_ticks_msec() * 0.001, s, float(air.get("_t")), str(_gj_on), _gj_t, int(stat["marks"]), int(stat["det"])])
	var hurt := st == air.A.HURT or st == air.A.BLOWN or st == air.A.CRUSH or st == air.A.DOWN or st == air.A.DEAD or st == air.A.GRABBED
	_e_gap = maxf(_e_gap - dt, 0.0)
	if _e_k > 0:
		_e_win -= dt
		if _e_buf > 0.0:
			_e_buf -= dt
			_e_fire()
		if _e_k > 0 and (_e_win <= 0.0 or hurt or _awake() != _e_aw or player.st != Player.St.AIR):
			_e_close()
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
	_blade_tint(true)
	Sfx.play("skill_sword", -4.0, 0.9)


func on_awake_end() -> void:
	player.set_blade_glow(0.0)
	_blade_tint(false)


## 觉醒「赤霄」：剑身的光转成赤红，觉醒结束换回来
func _blade_tint(on: bool) -> void:
	if player == null or player.melee == null or player.melee.sword == null or not player.melee.sword.has_meta("blade_mat"):
		return
	var bm := player.melee.sword.get_meta("blade_mat") as StandardMaterial3D
	if bm == null:
		return
	if on:
		if not _blade_saved:
			_blade_em = bm.emission
			_blade_saved = true
		bm.emission = CgFx.CRIMSON
	elif _blade_saved:
		bm.emission = _blade_em
		_blade_saved = false


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
				Vfx.cast_charge(c, Color.WHITE.lerp(CgFx.CRIMSON, 0.4), 0.5)
				Vfx.sky_ring(c, CgFx.CRIMSON, 2.8, 0.5)
				Vfx.space_ring(c, 3.0, CgFx.CRIMSON, 0.5, 0.06)
				Sfx.play("ascend", -4.0, 1.1)
				_ult_cine()
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
	if kind == "w":
		_e_proj(_move_id, t)
		return
	if kind == "cs":
		_cs_proj(t)
		return
	if kind != "lk" and kind != "tl":
		return
	var big := kind == "tl"
	var c := player.center()
	var pos: Vector3 = Proj.aim_of(t) if t != null and Proj.alive(t) else c + player.air._fwd() * 12.0
	stat["rift"] = int(stat["rift"]) + 1
	rift_fx(pos, big, _col())
	HeroFx.send(player, FX_RIFT, pos, Vector3.UP, 1.0 if big else 0.0)
	var tip := player.melee.rig.tip_pos()
	Vfx.warp_line(tip, tip + (pos - c).normalized() * 2.2, CgFx.main_col(_col(), big))
	Vfx.space_ring(pos, (TL_R if big else LK_R) * 0.9, CgFx.main_col(_col(), big), LK_DELAY, 0.05)
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
			Vfx.blade_hit(ec, Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), 0.0), CgFx.main_col(_col(), _awake()), 0.8)
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
	var mc := CgFx.main_col(col, big)
	var ring := Vfx._sprite(pos, Color.WHITE.lerp(mc, 0.4), 1, r * 2.9)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * r * 2.1, LK_DELAY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ring.material_override, "shader_parameter/alpha", 0.0, 0.12)
	tw.tween_callback(ring.queue_free)
	Vfx.glint(pos, Color.WHITE.lerp(mc, 0.3), 0.9)
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
	var mc := CgFx.main_col(col, big)
	# 一道凭空划开的长斩痕（深色衬底 + 刀色 + 白芯）+ 顺着、逆着刀路各迸一把针
	CgFx.cut(p, d, l * 2.0, col, big, 0.08, 2.4 if big else 2.0)
	CgFx.needles(p, d, 3, col, big, r * 0.9, 0.3, 0.07, 12)
	CgFx.needles(p, -d, 3, col, big, r * 0.7, 0.3, 0.07, 12)
	Vfx.line_sparks(p, d, Color.WHITE.lerp(mc, 0.4), 5 if Vfx.lite else 10, 26.0, 12.0, 0.25)
	Sfx.play("blade_cut", -4.0, 1.2 + 0.1 * randf())
	if last:
		Vfx.space_ring(p, r * 0.9, mc, 0.45, 0.07)
		CgFx.needles(p, Vector3.UP, 1, col, big, r, 0.4)
		if not Vfx.lite:
			Vfx.space_crack(p, mc, r * (0.5 if big else 0.6), 4 if big else 3, 0.42, 0.3)
		Sfx.play("shatter", -8.0, 1.3)


# ---------- 一线天 ----------

func _yx_cut(c: Vector3, fwd: Vector3) -> void:
	stat["yx"] = int(stat["yx"]) + 1
	_yx_c = c
	_yx_fwd = fwd
	_yx_hit.clear()
	_yx_done = false
	yx_fx(c, fwd, _col())
	yx_wave(c + fwd * 1.5, fwd, _col(), player, _yx_wave_hit)
	HeroFx.send(player, FX_YX, c, fwd, 0.0)
	Combat.slowmo(0.3, 0.1, 0.3)
	if is_instance_valid(_cine):
		_cine.call("cut")
	var cam := player.cam
	cam.fov_punch(10.0)
	cam.kick_rush(0.8)
	cam.add_trauma(0.4)
	player.air._warp(c + fwd * 3.0, 2.0)
	Sfx.play("blade_draw", 0.0, 0.75)
	Sfx.play("skill_sword", -3.0, 0.7)
	Sfx.play("swing_heavy", -2.0, 0.7)
	_yx_t = YX_DELAY


## 那道大刀光扫到了谁（cg_wave 的回调）：一剑 + 三道痕；已经齐断过了就当场把齐断那一下也补上
func _yx_wave_hit(e: Node3D, pos: Vector3) -> void:
	if not is_instance_valid(player) or player.dead or not is_instance_valid(e) or not Proj.alive(e):
		return
	var fwd := _yx_fwd
	var info := {"dmg": units(YX_CUT), "dir": fwd, "kb": 1.0, "stun": 1.3, "launch": "", "heavy": false, "brk": true,
			"ranged": true, "contact": pos, "pstun": 1.1}
	var res := _hit_one(e, info)
	if res != 0 and res != 2:
		return
	add_mark(e, 3)
	player.air._add_combo(float(info["dmg"]))
	if pos.distance_to(player.center()) < 60.0:
		player.cam.add_trauma(0.2)
	Sfx.play("blade_cut", -3.0, 0.9)
	if _yx_done:
		_yx_split_one(e)
	else:
		_yx_hit.append(e)


func _yx_split_one(e: Node3D) -> void:
	var air := player.air
	var ec := Proj.aim_of(e)
	var dir: Vector3 = air._flat(ec - _yx_c)
	dir = dir.normalized() if dir.length_squared() > 0.01 else _yx_fwd
	var info := {"dmg": units(YX_SPLIT), "dir": dir, "kb": 36.0, "stun": 1.0, "launch": "fwd", "heavy": true, "brk": true,
			"ranged": true, "contact": ec}
	var res := _hit_one(e, info)
	if res == 0 or res == 2:
		stat["yx_hits"] = int(stat["yx_hits"]) + 1
		air._add_combo(float(info["dmg"]))
		CgFx.wave_hit(ec, dir, dir.cross(Vector3.UP), _col(), true, true)
		if e.has_method("is_launched") and bool(e.call("is_launched")):
			air._on_launch(e, "fwd", ec, dir, 0.12)


func _yx_split() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var air := player.air
	var c := _yx_c
	var fwd := _yx_fwd
	_yx_done = true
	yx_split_fx(c, fwd, _col())
	HeroFx.send(player, FX_YX2, c, fwd, 0.0)
	if is_instance_valid(_cine):
		_cine.call("split")
	var cam := player.cam
	cam.add_trauma(0.8)
	cam.fov_punch(12.0)
	Combat.hitstop(0.12)
	Sfx.play("cut_burst", 2.0, 0.8)
	Sfx.play("shatter", -2.0, 0.8)
	Sfx.play("slam", -3.0, 0.9)
	for t: Variant in _yx_hit:
		if is_instance_valid(t) and Proj.alive(t):
			_yx_split_one(t as Node3D)
	_yx_hit.clear()
	# 贴着地放的：沿着刀光飞过的那一路把地犁开（头 36 米）
	var a := c + fwd * 2.5
	var b := c + fwd * 36.0
	var ga := floor_y(a)
	var gb := floor_y(b)
	if a.y - ga < 5.0 or b.y - gb < 5.0:
		trench(Vector3(a.x, minf(a.y, ga + 0.5), a.z), Vector3(b.x, minf(b.y, gb + 0.5), b.z), 1.8, 1.4)
	_detonate()
	air.end_awaken()


## 一线天的镜头（只有本机主角有：技能脚本只挂在本机主角身上）
func _ult_cine() -> void:
	if not AwakenCine.enabled or DisplayServer.get_name() == "headless" or is_instance_valid(_cine):
		return
	var n: Node = UltCine.new()
	n.set("player", player)
	n.set("air", player.air)
	n.set("col", CgFx.CRIMSON)
	_cine = n
	add_child(n)


## 横抹出手的那一下：身前两道赤红的大弧 + 贴着地往四面迸的一圈针 + 一圈空间波动（飞出去的那道刀光另算：yx_wave）
static func yx_fx(c: Vector3, fwd: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var side := fwd.cross(Vector3.UP).normalized()
	CgFx.slash(c + fwd * 0.3, fwd, side, YX_RAD * 1.1, 170, col, true, 0.5)
	CgFx.slash(c + fwd * 0.3, fwd, side, YX_RAD * 0.6, 170, col, true, 0.36)
	CgFx.needles(c + fwd * 1.5, Vector3.UP, 2, col, true, 9.0, 0.5, 0.1, 30)
	Vfx.space_ring(c + fwd * 3.0, 6.0, CgFx.CRIMSON, 0.6, 0.08)
	Vfx.line_sparks(c + fwd * 2.0, side, Color.WHITE.lerp(CgFx.CRIMSON, 0.4), 10 if Vfx.lite else 22, 50.0, 10.0, 0.4)


## 飞出去的那道大刀光：横着 18 米宽，一路贯穿、贴地不停，沿途荡空间波动、往两侧和上方迸针，飞到头炸开；身后留一道合不上的黑缝。
## who = 放它的人（别人机器上给 null：只画），cb = 扫到了谁
static func yx_wave(from: Vector3, fwd: Vector3, col: Color, who: Node3D, cb: Callable) -> void:
	if not HeroFx.ok():
		return
	var side := fwd.cross(Vector3.UP).normalized()
	for k in 2:
		# 两层：外面一道大的（判定、拖尾、波动都在它身上），里面套一道小一圈、慢半拍的（只画）
		var w: Node3D = Wave.new()
		var inner := k == 1
		w.set("dir", fwd)
		w.set("swing", -side if inner else side)
		w.set("aw", true)
		w.set("big", not inner)
		w.set("col", col)
		w.set("pierce", true)
		w.set("skim", true)
		w.set("quiet", inner)
		w.set("radius", YX_RAD * (0.62 if inner else 1.0))
		w.set("hit_r", YX_RAD * 0.85)
		w.set("speed", YX_SPEED * (0.94 if inner else 1.0))
		w.set("reach", YX_R * (0.94 if inner else 1.0))
		w.set("ring_gap", 8.0)
		w.set("ring_r", 5.0)
		w.set("ring_k", 0.07)
		w.set("spray", not inner)
		w.set("grow_far", 1.9)
		w.set("skip", who)
		if not inner:
			w.set("on_hit", cb)
		w.position = from
		Vfx.root.add_child(w)


## 齐断：刀光飞过的那一路上，一排裂隙挨个张开、往上迸出成片的针芒、各横着断一刀，整条线炸成一道粗的黑红裂口
static func yx_split_fx(c: Vector3, fwd: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var mc := CgFx.CRIMSON
	var side := fwd.cross(Vector3.UP).normalized()
	CgFx.cut(c + fwd * (YX_R * 0.5), fwd, YX_R, col, true, 0.12, 2.8)
	var n := 4 if Vfx.lite else 7
	for i in n:
		var p := c + fwd * (5.0 + float(i) * (YX_R - 12.0) / float(n - 1))
		var tw := Vfx.root.create_tween()
		tw.tween_interval(0.035 * float(i))
		tw.tween_callback(_yx_burst_at.bind(p, fwd, side, col))
	Vfx.space_ring(c + fwd * 8.0, 9.0, mc, 0.6, 0.1)
	if not Vfx.lite:
		Vfx.space_crack(c + fwd * 6.0, mc, 3.2, 5, 0.5, 0.4)


static func _yx_burst_at(p: Vector3, fwd: Vector3, side: Vector3, col: Color) -> void:
	if not HeroFx.ok():
		return
	var mc := CgFx.CRIMSON
	Vfx.rift(p, fwd, mc, 2.4, 0.45)
	Vfx.shockwave(p, Vector3.UP, Color.WHITE.lerp(mc, 0.4), 1.6)
	CgFx.cut(p, side, 18.0, col, true, 0.06, 1.6)
	CgFx.needles(p, Vector3.UP, 0, col, true, 6.5, 0.55, 0.11)
	Vfx.space_ring(p, 3.0, mc, 0.4, 0.06)


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


# ---------- 斩击的弧光（画法在 cg_fx.gd：三层色阶 + 勾边的新月）----------

## 招式的 arc 预设这一剑朝哪挥（世界方向）
static func swing_of(idx: int, fwd: Vector3) -> Vector3:
	var a: Array = ARCS[clampi(idx, 0, ARCS.size() - 1)]
	var f := fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var side := f.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(f).normalized()
	return (side * float(a[0]) + up * float(a[1])).normalized()


## big = 觉醒（赤霄）：赤红的、大三成，并且往前送出一道短刀光（剑气延伸）
static func arc_preset(center: Vector3, fwd: Vector3, idx: int, big: bool, col: Color) -> void:
	if idx < 0 or idx >= ARCS.size():
		return
	var a: Array = ARCS[idx]
	var f := fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var swing := swing_of(idx, f)
	var r := float(a[2]) * (1.3 if big else 1.0)
	var span := int(a[3])
	CgFx.slash(center + f * 0.2, f, swing, r, span, col, big, 0.24 if span < 200 else 0.3)
	if big and span < 200:
		CgFx.fly_arc(center + f * 0.9, f, swing, r * 0.8, 130, col, true, 3.4, 0.24)


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
			var daw := roll >= 100.0
			roll = fmod(roll, 100.0)
			var t2 := _node_near(pos, 6.0)
			var old2: Variant = t2.get_meta(META_RMARK) if t2 != null and t2.has_meta(META_RMARK) else null
			if is_instance_valid(old2) and not (old2 as MarkView)._bursting:
				var v2: MarkView = old2
				var n := v2.n
				v2.burst(GJ_GAP)
				t2.remove_meta(META_RMARK)
				var tw := Vfx.root.create_tween()
				tw.tween_interval(GJ_GAP * float(n))
				tw.tween_callback(det_fx.bind(pos, Vector3.FORWARD, n, n >= MARK_MAX, col, daw))
			else:
				det_fx(pos, Vector3.FORWARD, int(roll), int(roll) >= MARK_MAX, col, daw)
		FX_LINE:
			line_fx(pos, pos + dir * clampf(roll, 1.0, 40.0), col)
		FX_WAVE:
			var waw := roll >= 10.0
			var wk := int(fmod(roll, 10.0))
			var wlast := wk == (E_MOVES_AW if waw else E_MOVES).size() - 1
			var wsw := e_swing(dir, wk, waw, false)
			CgFx.slash(pos - dir * 1.2, dir, wsw, 3.5 if waw else 3.0, 160, col, waw, 0.24)
			wave_spawn(pos, dir, wsw, waw, wlast, col, null, Callable(), false)
			if waw and wlast:
				wave_spawn(pos, dir, e_swing(dir, wk, waw, true), waw, wlast, col, null, Callable(), true)
		FX_CS:
			var caw := roll >= 1000.0
			var ckind: String = ["fwd", "up", "down"][clampi(int(fmod(roll, 1000.0) / 100.0), 0, 2)]
			var ck := clampf(fmod(roll, 100.0) / 99.0, 0.0, 1.0)
			var csw := cs_swing(dir, ckind)
			cs_fx(pos, dir, csw, ck, caw, col)
			cs_wave(pos, dir, csw, ck, caw, col, null, Callable())
		FX_HIT:
			var hf := dir.cross(Vector3.UP)
			CgFx.hit_fx(pos, dir, hf.normalized() if hf.length_squared() > 1e-4 else Vector3.FORWARD, col, int(roll) % 2 == 1, int(roll) >= 2)
		FX_YX:
			yx_fx(pos, dir, col)
			yx_wave(pos + dir * 1.5, dir, col, null, Callable())
		FX_YX2:
			yx_split_fx(pos, dir, col)
		FX_DOM:
			var ring := domain_ring(pos, col)
			var tr := ring.create_tween()
			tr.tween_property(ring.material_override, "albedo_color:a", 0.0, DOMAIN_T).set_ease(Tween.EASE_IN)
			tr.parallel().tween_property(ring, "rotation:y", 4.0, DOMAIN_T)
			tr.tween_callback(ring.queue_free)


## 载入时预热（hero_fx.warm 调）：刀光 / 针芒两种新材质各摆一个
static func warm_nodes() -> Array:
	return CgFx.warm_nodes()
