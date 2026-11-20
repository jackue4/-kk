extends Node
## 心得光点（2026-11-20 晚，用户要求：「杀怪后获得的心得，要有一个小特效飞到玩家身上，然后有个对应的数值增加表现」）。
## 杀怪那一刻心得就已经记进 raid_manager.insight（结算只认它）；这里只管「看得见」的那一半：
##   · 怪倒下处冒出几颗灵光（十字星芒 + 一道顺着飞行方向的针形拖尾），先往上一弹，再拐弯追到主角胸口：追的速度 = 基础速度 + 主角自己的速度，
##     还不够就按「剩下的距离 ÷ 剩下的时间」托底，所以 1.4 秒内一定飞到身上（主角在遁光里飞、在百米外分到队友的击杀也一样）；
##   · 到了：胸口一圈细线环收一下，头顶飘「心得 +N」（0.25 秒内到的合成一行，一群怪一起倒不会刷屏）；
##   · 每颗到的时候把它那份加到 mgr.insight_shown（右上角信息牌显示的是这个数，跟着光点一颗颗往上跳）。
## 手机档：只用 Vfx 现成的特效面片着色器（进图预热里已经有，不新编着色器），光点 / 拖尾 / 飘字都从池子里拿，
## 一个 _process 统一推，不起 Tween；同时在飞的最多 MAX_ORBS 颗（手机 MAX_ORBS_MOBILE），再多就并进还在飞的那颗。
## 故意不写 class_name：用 preload 引用（raid_manager.gd）。

const Prog := preload("res://scripts/progression.gd")

const MAX_ORBS := 24
const MAX_ORBS_MOBILE := 14
const POP_T := 0.16              # 先往外弹多久，然后才开始追
const MAX_T := 1.4               # 这时候一定到了（追的速度按剩下的距离托底）
const HARD_T := 1.7              # 兜底：再久还没到就当场收掉，记一次 timeouts（自检要它是 0）
const TELEPORT := 40.0           # 主角一帧挪了这么远（瞬身 / 传送）：在飞的光点直接算到
const ARRIVE_R := 0.75
const MERGE_T := 0.25            # 这么久之内到的光点合成一行飘字
## 颜色 / 大小按手机档截图定的（1701×900、镜头十米上下）：一开始用青玉色、0.42 米，草原的嫩绿地上几乎看不见，又被怪倒下的金色碎光盖住
const COL_MOB := Color(0.55, 0.9, 1.0)       # 天青：普通怪（草地、红土、紫雾上都跳得出来）
const COL_RICH := Color(1.0, 0.84, 0.4)      # 金色：精英 / 首领 / 修士
const FLOAT_COL := Color(0.66, 0.93, 1.0)
const ORB_SIZE := 0.95                       # 十字星芒的边长（米），精英那几颗再大三成
const TRAIL_W := 0.3
const FLOAT_SCALE := 1.5                     # 飘字放大（字号仍是 46，和别处的飘字共用字形缓存）

var mgr: Node3D                  # raid_manager.gd
var player: Node3D
var mobile := false
var _orbs: Array = []            # 在飞的：{head, tail, pos, vel, t, amt, delay}
var _pool: Array = []            # 用完收回的 [head, tail]
var _rings: Array = []           # 胸口的收光环：{mi, t}
var _floats: Array = []          # 头顶飘字：{label, t, up}
var _float_pool: Array = []
var _pend := 0.0                 # 这一拨（MERGE_T 内）到了多少
var _pend_t := -1.0
var _pend_rich := false
# 自检用的计数
var launched := 0
var arrived := 0
var timeouts := 0
var floats_made := 0
var _last_target := Vector3.INF
var _warm := 0                   # 进图头两帧把飘字要用到的字先排一遍版（字形第一次用要现画，别留到第一只怪倒下）


func _ready() -> void:
	process_priority = 10
	_warm = 3


## 池子里的面片 / 飘字挂在 Vfx.root（不跟着这个节点走）：离开大世界时一起收掉
func _exit_tree() -> void:
	for o: Dictionary in _orbs:
		_release(o)
	_orbs.clear()
	for pair: Array in _pool:
		for mi: Variant in pair:
			if is_instance_valid(mi):
				(mi as Node).queue_free()
	_pool.clear()
	for r: Dictionary in _rings:
		if is_instance_valid(r["mi"]):
			(r["mi"] as Node).queue_free()
	_rings.clear()
	for f: Dictionary in _floats:
		_float_pool.append(f["label"])
	_floats.clear()
	for l: Variant in _float_pool:
		if is_instance_valid(l):
			(l as Node).queue_free()
	_float_pool.clear()


## 杀了一只、记上了 amount 心得：从 from 放光点。kind：0 普通 / 1 精英 / 2 首领、修士
func launch(from: Vector3, amount: float, kind := 0) -> void:
	if amount <= 0.0 or not is_instance_valid(player):
		_credit(amount)
		return
	var n: int = [1, 3, 5][clampi(kind, 0, 2)]
	var cap := MAX_ORBS_MOBILE if mobile else MAX_ORBS
	var col := COL_MOB if kind == 0 else COL_RICH
	for i in n:
		var share := amount / float(n)
		if _orbs.size() >= cap:
			# 太多了：并进最新那颗还在飞的（数照样加，只是少画一颗）
			var last: Dictionary = _orbs[_orbs.size() - 1]
			last["amt"] = float(last["amt"]) + share
			continue
		var o := _take_orb(col)
		var a := randf() * TAU
		var side := Vector3(cos(a), 0.0, sin(a))
		o["pos"] = from + Vector3(0.0, 0.3, 0.0)
		o["vel"] = Vector3.UP * randf_range(5.5, 7.5) + side * randf_range(2.0, 3.5)
		o["t"] = 0.0
		o["delay"] = 0.05 * float(i)
		o["amt"] = share
		o["rich"] = kind > 0
		o["size"] = ORB_SIZE if kind == 0 else ORB_SIZE * 1.3
		_orbs.append(o)
		launched += 1


## 还有几颗在飞（raid_manager 用它判断信息牌的数能不能直接追平）
func pending() -> int:
	return _orbs.size()


## 局结束 / 换场景：全部收掉，没到的数一次加上
func clear() -> void:
	for o: Dictionary in _orbs:
		_credit(float(o["amt"]))
		_release(o)
	_orbs.clear()
	for r: Dictionary in _rings:
		(r["mi"] as Node3D).visible = false
	for f: Dictionary in _floats:
		(f["label"] as Label3D).visible = false
		_float_pool.append(f["label"])
	_floats.clear()
	_pend = 0.0
	_pend_t = -1.0


func _credit(v: float) -> void:
	if v > 0.0 and mgr != null:
		mgr.insight_arrived(v)


func _take_orb(col: Color) -> Dictionary:
	var pair: Array
	if _pool.is_empty():
		var head := Vfx.marker_sprite(col, 0, ORB_SIZE)
		var tail := Vfx.persistent_sprite(col, 2)
		pair = [head, tail]
	else:
		pair = _pool.pop_back()
	var h: MeshInstance3D = pair[0]
	var tl: MeshInstance3D = pair[1]
	for mi: MeshInstance3D in [h, tl]:
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("alpha", 0.0)
		mi.visible = true
	return {"head": h, "tail": tl}


func _release(o: Dictionary) -> void:
	var h: MeshInstance3D = o["head"]
	var tl: MeshInstance3D = o["tail"]
	if is_instance_valid(h) and is_instance_valid(tl):
		h.visible = false
		tl.visible = false
		_pool.append([h, tl])


func _process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	var target: Vector3 = player.global_position + Vector3(0.0, 1.15, 0.0)
	if _warm > 0:
		_warm_glyphs(target)
	var tv := Vector3.ZERO
	var jumped := false
	if _last_target.is_finite() and dt > 0.0:
		var step := target - _last_target
		jumped = step.length() > TELEPORT
		if not jumped:
			tv = step / dt
	_last_target = target
	var i := _orbs.size() - 1
	while i >= 0:
		var o: Dictionary = _orbs[i]
		var h: MeshInstance3D = o["head"]
		var tl: MeshInstance3D = o["tail"]
		if not is_instance_valid(h) or not is_instance_valid(tl):
			_credit(float(o["amt"]))
			_orbs.remove_at(i)
			i -= 1
			continue
		if float(o["delay"]) > 0.0:
			o["delay"] = float(o["delay"]) - dt
			i -= 1
			continue
		var t: float = float(o["t"]) + dt
		o["t"] = t
		var pos: Vector3 = o["pos"]
		var vel: Vector3 = o["vel"]
		var to := target - pos
		if t < POP_T:
			vel = vel.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * dt))       # 往外弹、慢慢收住
			pos += vel * dt + tv * dt * clampf(t / POP_T, 0.0, 1.0)  # 主角在飞：弹的时候就开始跟着走
		else:
			# 追：速度从 8 涨到 45 米 / 秒，再加上主角自己的速度；按剩下的时间托底，MAX_T 之前一定到
			var k := clampf((t - POP_T) / 0.6, 0.0, 1.0)
			var spd := lerpf(8.0, 45.0, k * k) + tv.length()
			spd = maxf(spd, to.length() / maxf(MAX_T - t, 0.1))
			var want := to.normalized() * spd if to.length() > 0.01 else Vector3.ZERO
			vel = vel.lerp(want, 1.0 - exp(-(4.0 + 14.0 * k) * dt))
			var mv := vel * dt
			if mv.length() >= to.length() or t > MAX_T - 0.08:
				pos = pos.lerp(target, clampf(mv.length() / maxf(to.length(), 0.001), 0.35, 1.0))   # 最后一段直接贴上去，不会冲过头
			else:
				pos += mv
		o["pos"] = pos
		o["vel"] = vel
		var a := clampf(t / 0.08, 0.0, 1.0)
		var size: float = o["size"]
		h.global_position = pos
		h.scale = Vector3.ONE * size * (1.0 + 0.2 * sin(t * 30.0))
		(h.material_override as ShaderMaterial).set_shader_parameter("alpha", a)
		var sp := vel.length()
		if sp > 0.5:
			tl.visible = true
			var ln := clampf(sp * 0.05, 0.6, 2.4)
			Vfx.place_streak(tl, pos - vel.normalized() * ln * 0.5, vel, ln, TRAIL_W)
			(tl.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.75 * a)
		else:
			tl.visible = false
		if pos.distance_to(target) < ARRIVE_R or jumped or t > HARD_T:
			if t > HARD_T and not jumped:
				timeouts += 1
			_arrive(o)
			_release(o)
			_orbs.remove_at(i)
		i -= 1
	_tick_rings(dt)
	_tick_floats(dt, target)
	if _pend_t >= 0.0:
		_pend_t += dt
		if _pend_t >= MERGE_T:
			_spawn_float(_pend, _pend_rich)
			_pend = 0.0
			_pend_t = -1.0
			_pend_rich = false


func _arrive(o: Dictionary) -> void:
	arrived += 1
	var amt := float(o["amt"])
	_credit(amt)
	if _pend_t < 0.0:
		_pend_t = 0.0
		_ring(bool(o["rich"]))
	_pend += amt
	_pend_rich = _pend_rich or bool(o["rich"])


## 胸口一圈细线环收一下（一拨只放一个）
func _ring(rich: bool) -> void:
	var mi: MeshInstance3D = null
	for r: Dictionary in _rings:
		if not (r["mi"] as Node3D).visible:
			mi = r["mi"]
			r["t"] = 0.0
			break
	if mi == null:
		if _rings.size() >= 4:
			return
		mi = Vfx.marker_sprite(COL_MOB, 1, 0.5)
		_rings.append({"mi": mi, "t": 0.0})
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", COL_RICH if rich else COL_MOB)
	mi.visible = true


func _tick_rings(dt: float) -> void:
	var c: Vector3 = player.global_position + Vector3(0.0, 1.15, 0.0)
	var cam := player.get_viewport().get_camera_3d()
	if cam != null:
		c += (cam.global_position - c).normalized() * 0.6      # 往镜头那边挪一点：别被主角自己的身子挡住（不另编不测深度的着色器）
	for r: Dictionary in _rings:
		var mi: MeshInstance3D = r["mi"]
		if not mi.visible:
			continue
		var t: float = float(r["t"]) + dt
		r["t"] = t
		var k := clampf(t / 0.3, 0.0, 1.0)
		mi.global_position = c
		mi.scale = Vector3.ONE * lerpf(1.3, 0.35, k)      # 往里收：光被吸进身体
		(mi.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.9 * (1.0 - k))
		if k >= 1.0:
			mi.visible = false


## 头顶飘「心得 +N」：跟着主角走（主角在飞也不会被甩在身后），0.9 秒往上飘 1.3 米、后半段淡出
func _spawn_float(v: float, rich: bool) -> void:
	if v <= 0.0:
		return
	floats_made += 1
	var l := _new_float()
	l.text = "心得 +%s" % _num(v)
	l.modulate = COL_RICH if rich else FLOAT_COL
	# 还很新的几行往上让一行字高，新的一行在原位（最多让两行）
	for g: Dictionary in _floats:
		if float(g["t"]) < 0.5:
			g["up"] = minf(float(g["up"]) + 0.42 * FLOAT_SCALE, 0.84 * FLOAT_SCALE)
	var nf := {"label": l, "t": 0.0, "up": 0.0}
	_floats.append(nf)
	_place_float(nf, player.global_position + Vector3(0.0, 1.15, 0.0))      # 先摆好再显示，不会在旧位置闪一帧
	l.visible = true
	if _floats.size() > 5:
		var old: Dictionary = _floats.pop_front()
		(old["label"] as Label3D).visible = false
		_float_pool.append(old["label"])


## 飘字和 raid_manager._float_text / hall_pills 用同一套字号、描边（46 / 12）：字形缓存是按字号分的，同一套就不用再画一遍
func _new_float() -> Label3D:
	if not _float_pool.is_empty():
		return _float_pool.pop_back()
	var l := Label3D.new()
	l.font = Vfx.font
	l.font_size = 46
	l.pixel_size = 0.0075
	l.outline_size = 12
	l.outline_modulate = Color(0.06, 0.06, 0.08, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 2
	l.visible = false
	Vfx.root.add_child(l)
	return l


## 数：不到一万照写整数（至少写 1），再大用「1.2万」
func _num(v: float) -> String:
	return str(maxi(roundi(v), 1)) if v < 10000.0 else Prog.short_num(v)


func _place_float(f: Dictionary, chest: Vector3) -> void:
	var l: Label3D = f["label"]
	var t: float = f["t"]
	var k := clampf(t / 0.9, 0.0, 1.0)
	l.scale = Vector3.ONE * FLOAT_SCALE * (0.6 + 0.4 * clampf(t / 0.12, 0.0, 1.0))
	l.global_position = chest + Vector3(0.0, 1.35 + float(f["up"]) + 1.3 * (1.0 - pow(1.0 - k, 2.0)), 0.0)
	var a := 1.0 - clampf((k - 0.55) / 0.45, 0.0, 1.0)
	l.modulate.a = a
	l.outline_modulate.a = 0.9 * a


## 进图头几帧：拿池子里的一个飘字把会用到的字（心得 + 数字 + 万亿）排一遍、几乎透明地画两帧
func _warm_glyphs(chest: Vector3) -> void:
	if _floats.is_empty() and _float_pool.is_empty():
		_float_pool.append(_new_float())
	if _float_pool.is_empty():
		_warm = 0
		return
	var l: Label3D = _float_pool[_float_pool.size() - 1]
	_warm -= 1
	if _warm > 0:
		l.text = "心得 +0123456789.万亿"
		l.modulate = Color(FLOAT_COL, 0.02)
		l.outline_modulate.a = 0.02
		l.global_position = chest + Vector3(0.0, 1.4, 0.0)
		l.visible = true
	else:
		l.visible = false


func _tick_floats(dt: float, chest: Vector3) -> void:
	var i := _floats.size() - 1
	while i >= 0:
		var f: Dictionary = _floats[i]
		var l: Label3D = f["label"]
		var t: float = float(f["t"]) + dt
		f["t"] = t
		_place_float(f, chest)
		var k := clampf(t / 0.9, 0.0, 1.0)
		if k >= 1.0:
			l.visible = false
			_float_pool.append(l)
			_floats.remove_at(i)
		i -= 1
