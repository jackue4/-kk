extends Control
## 大世界小地图（raid_hud.gd 放在左上角）。上方 = 镜头正前方，主角在正中。
## 2026-11-23 神识：点一下 = 神识一扫（shen_shi.gd）；按住约半秒 = 在近景（90 米）/ 远景（260 米）之间切换（原来点一下就切）。
##   一扫的半径比当前范围大时自动拉到远景，标记消失后回来；左上角一枚「识」字小印：朱红 = 神识可用，纸色 + 朱红弧 = 冷却进度。
##   扫的时候地图上画一圈往外扩的光波，扫到的东西按颜色一圈圈闪（出了范围的要紧目标贴边画个小箭头指方向）。
##   手机上第二根手指点也认（touch_controls.gd 转来 ui_touch，系统只把第一根手指当成鼠标）。
## 底图：一张 48×48 的地形色小图（区域配色 + 高度明暗 + 水面 + 被破开的地方发暗），在工作线程里算（block_world.gd 的 map_colors），
##   主角走出一段才重算一次，平移 / 旋转都在着色器里做，主线程每帧只改几个参数。
## 标记（每帧画，都是几十个小图形）：
##   · 主角：正中的白色箭头（指向身体朝向）
##   · 小怪红点、精英橙点带圈、Boss 红菱形（在场的会贴到边上指方向）
##   · 其他修士：红名是红三角，白名是小白点；队友（真人 / AI）青色圆点，出了范围贴边
##   · 别队的真人：红三角
##   · 掉落物按品阶颜色的小方块，箱子大一号带白边
##   · 传送阵：青色双圈（探明可用）/ 灰蓝问号圈（未探明），始终贴边指方向；最近的一座在地图下面写距离
##   · 「北」字标在圆环上
## 2026-11-24 搜打撤 PvP 新图（scripts/ex/ex_level.gd）：固定底图模式——关卡有 map_tex(p) 就用它载入时烘好的整图（按主角在哪一层换图），
##   不再围着主角现算；撤离点从关卡的点表画（mgr 没有 _extracts 也行）；点一下打开全屏大地图（关卡的 open_big_map，画法见下面的 BigMap）。
##   mgr 上的字段（_pickups / _mobs / _puppets / _bosses / _rivals / _allies / pings / _extracts / net_on / ex_col）没有就跳过，老大世界照旧。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/minimap.gdshader")
const Data := preload("res://scripts/raid_data.gd")
const UiStyle := preload("res://scripts/ink_style.gd")      # 2026-11-24 界面重做：换成墨玉样式（接口同 ui_style.gd，见那个文件头）
const MapDef := preload("res://scripts/ex/map_def.gd")

const TEX_N := 48
const TEX_N_LITE := 28         # 没有线程的平台（网页版）：底图在主线程上算，分辨率低一些、不算坡向明暗
const RANGES: Array[float] = [90.0, 260.0]
const SPAN_K := 3.0            # 小图边长 = 地图半径 × 这个数（留出旋转和走动的余量）
const SIZE := 178.0

var mgr: Node3D                # raid_manager.gd
var font: Font

var _range_i := 0
var _bg: ColorRect
var _mat: ShaderMaterial
var _tex: ImageTexture
var _tex_center := Vector2(1.0e9, 1.0e9)
var _tex_span := 1.0
var _task := -1
var _gen_center := Vector2.ZERO
var _gen_span := 1.0
var _gen_bytes := PackedByteArray()
var _lite := OS.has_feature("nothreads") or OS.get_cmdline_user_args().has("--sliced")
var _n := TEX_N
## 没有线程的平台：底图在主线程上分帧算，每帧只算一小段（一口气算完手机上要卡将近十分之一秒）
const INC_US := 400            # 每帧最多花这么多微秒
const INC_MIN := 12            # 每帧至少算这么多个像素
var _inc_at := -1              # 算到第几个像素了（-1 = 没在算）
var _fixed := false            # 固定底图模式（新图，关卡给整图）
var _fixed_tex: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 22.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.size = Vector2(SIZE, SIZE)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_bg.material = _mat
	add_child(_bg)
	_n = TEX_N_LITE if _lite else TEX_N
	var img := Image.create(_n, _n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.13, 0.14))
	_tex = ImageTexture.create_from_image(img)
	_mat.set_shader_parameter("terrain", _tex)
	_mat.set_shader_parameter("ring_col", UiStyle.GOLD)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## 点按 / 长按：鼠标（含系统把第一根手指当成的鼠标）和 touch_controls 转来的触点两路都收，谁先按下就只认谁那一路的抬起（同一下不会算两次）
const LONG_PRESS := 0.45
var _down := false
var _down_src := 0            # 1 鼠标 / 2 触点
var _down_t := 0.0
var _long_done := false
var _auto_t := 0.0            # 神识一扫自动拉到远景还剩几秒
var _seen_scans := 0
var taps := 0                 # 点了几下（自检看）


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (e as InputEventMouseButton).pressed:
			_press(1)
		else:
			_release(1)
		accept_event()


## touch_controls.gd 转来的触点（第二根手指点小地图时只有这一路）
func ui_touch(_idx: int, pressed: bool) -> void:
	if pressed:
		_press(2)
	else:
		_release(2)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _press(src: int) -> void:
	if _down:
		return
	_down = true
	_down_src = src
	_down_t = _now()
	_long_done = false


func _release(src: int) -> void:
	if not _down or src != _down_src:
		return
	_down = false
	if not _long_done:
		taps += 1
		if _fixed and mgr != null and mgr.get("level") != null and (mgr.level as Object).has_method("open_big_map"):
			mgr.level.call("open_big_map")
			return
		var ss: Variant = mgr.get("shenshi") if mgr != null else null
		if ss != null and is_instance_valid(ss):
			ss.scan()
		else:
			_range_i = (_range_i + 1) % RANGES.size()


func radius() -> float:
	var r := RANGES[_range_i]
	if _auto_t > 0.0:
		r = maxf(r, RANGES[RANGES.size() - 1])
	return r


## 工作线程：算一张底图
func _gen(world: Node3D, center: Vector2, span: float) -> void:
	_gen_bytes = world.call("map_colors", center, span, _n, not _lite)


func _process(dt: float) -> void:
	if mgr == null or mgr.player == null or mgr.level == null or mgr.level.world == null:
		return
	# 长按：切近景 / 远景（按住时就切，手指还没抬也看得到变化）
	if _down and not _long_done and _now() - _down_t >= LONG_PRESS:
		_long_done = true
		_range_i = (_range_i + 1) % RANGES.size()
		_auto_t = 0.0
	# 神识刚扫了一下（点小地图或键盘 C）：半径比当前范围大就自动拉到远景，标记留多久就拉多久
	_auto_t = maxf(_auto_t - dt, 0.0)
	var ss: Variant = mgr.get("shenshi")
	if ss != null and is_instance_valid(ss) and int(ss.scans) != _seen_scans:
		_seen_scans = int(ss.scans)
		if float(ss.wave_max) > RANGES[_range_i] * 0.95:
			_auto_t = float(ss.cur["hold"])
	var p3: Vector3 = mgr.player.global_position
	var p := Vector2(p3.x, p3.z)
	var rng := radius()
	var span := rng * SPAN_K
	if (mgr.level as Object).has_method("map_tex"):
		# 固定底图：关卡载入时烘好的整图，按主角在哪一层换
		_fixed = true
		var mt: Dictionary = mgr.level.call("map_tex", p3)
		var tx: Texture2D = mt["tex"]
		if tx != _fixed_tex:
			_fixed_tex = tx
			_mat.set_shader_parameter("terrain", tx)
		_tex_center = mt["center"]
		_tex_span = float(mt["span"])
		_mat.set_shader_parameter("offset", (p - _tex_center) / _tex_span)
		_mat.set_shader_parameter("zoom", rng / _tex_span)
		_mat.set_shader_parameter("yaw", mgr.cam.yaw)
		queue_redraw()
		return
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _gen_bytes.size() == _n * _n * 3:
			_tex.update(Image.create_from_data(_n, _n, false, Image.FORMAT_RGB8, _gen_bytes))
			_tex_center = _gen_center
			_tex_span = _gen_span
	if _inc_at >= 0:
		var t0 := Time.get_ticks_usec()
		var total := _n * _n
		while _inc_at < total:
			mgr.level.world.map_cells(_gen_center, _gen_span, _n, false, _inc_at, _inc_at + INC_MIN, _gen_bytes)
			_inc_at += INC_MIN
			if Time.get_ticks_usec() - t0 > INC_US:
				break
		if _inc_at >= total:
			_inc_at = -1
			_tex.update(Image.create_from_data(_n, _n, false, Image.FORMAT_RGB8, _gen_bytes))
			_tex_center = _gen_center
			_tex_span = _gen_span
	if _task < 0 and _inc_at < 0 and (absf(span - _tex_span) > 0.5 or p.distance_to(_tex_center) > rng * (0.55 if _lite else 0.3)):
		# 往前进方向多看一点：飞得快时重算赶得上
		var v: Vector3 = mgr.player.velocity
		_gen_center = p + Vector2(v.x, v.z).limit_length(rng * 0.5) * 0.4
		_gen_span = span
		if _lite:
			_gen_bytes = PackedByteArray()
			_gen_bytes.resize(_n * _n * 3)
			_inc_at = 0
		else:
			_task = WorkerThreadPool.add_task(_gen.bind(mgr.level.world, _gen_center, span))
	_mat.set_shader_parameter("offset", (p - _tex_center) / _tex_span)
	_mat.set_shader_parameter("zoom", rng / _tex_span)
	_mat.set_shader_parameter("yaw", mgr.cam.yaw)
	queue_redraw()


## 画标记的笔：老大世界（不是固定底图）原样逐个 draw_*；新图合成一次绘制调用（见文件末尾的 Painter）
var _pt: Painter


func _painter() -> Painter:
	if _pt == null:
		_pt = Painter.new(self)
	_pt.direct = not _fixed
	return _pt


func _draw() -> void:
	if mgr == null or mgr.player == null:
		return
	var pt := _painter()
	var c := Vector2(SIZE, SIZE) * 0.5
	var rad := SIZE * 0.5 * 0.86
	var rng := radius()
	var yaw: float = mgr.cam.yaw
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var p3: Vector3 = mgr.player.global_position
	var p := Vector2(p3.x, p3.z)
	# 外圈：纸色环（着色器画的）上压一笔墨圆
	var enso := UiStyle.tex("enso")
	if enso != null:
		var er := SIZE * 0.5 * 1.1
		draw_texture_rect(enso, Rect2(c - Vector2(er, er), Vector2(er, er) * 2.0), false, Color(UiStyle.LINE, 0.92))
	# 世界坐标 → [地图上的位置, 是不是出了范围（已经贴到边上）]
	var at := func(w: Vector3) -> Array:
		var d := Vector2(w.x, w.z) - p
		var q := Vector2(d.dot(right), -d.dot(fwd)) / rng * rad
		var out := q.length() > rad
		if out:
			q = q.normalized() * rad
		return [c + q, out]

	# 掉落物
	for pk: Variant in _arr("_pickups"):
		if not is_instance_valid(pk):
			continue
		var a: Array = at.call(pk.global_position)
		if a[1]:
			continue
		var col: Color = Data.TIER_COLORS[int(pk.tier())]
		if pk.is_chest():
			pt.rect(Rect2(a[0] - Vector2(4.5, 4.5), Vector2(9, 9)), Color.WHITE)
			pt.rect(Rect2(a[0] - Vector2(3.5, 3.5), Vector2(7, 7)), col)
		else:
			pt.rect(Rect2(a[0] - Vector2(2, 2), Vector2(4, 4)), col)
	# 怪（自己名下的 + 别人名下的木偶）
	var pup: Variant = mgr.get("_puppets")
	var mobs: Array = _arr("_mobs") + ((pup as Dictionary).values() if pup is Dictionary else [])
	for m: Variant in mobs:
		if not is_instance_valid(m) or not m.is_alive() or m.boss:
			continue
		var a: Array = at.call(m.global_position)
		if a[1]:
			continue
		if m.elite:
			pt.circle(a[0], 4.0, Color(1.0, 0.62, 0.2))
			pt.arc(a[0], 6.0, 0.0, TAU, 12, Color(1.0, 0.75, 0.3), 1.2)
		else:
			pt.circle(a[0], 2.6, Color(0.95, 0.3, 0.25))
	# Boss：巢穴里的 + 游荡的
	for b: Variant in _arr("_bosses"):
		if not (b is Dictionary) or not (b as Dictionary).has("state"):
			continue
		if int(b["state"]) == 2:
			continue
		var bp: Vector3 = b["pos"]
		var live := int(b["state"]) == 1 and is_instance_valid(b["node"])
		if live:
			bp = (b["node"] as Node3D).global_position
		if Vector2(bp.x, bp.z).distance_to(p) > 520.0:
			continue
		_diamond((at.call(bp) as Array)[0], 6.5 if live else 5.0, Color(0.95, 0.2, 0.18) if live else Color(0.6, 0.2, 0.2))
	for m: Variant in mobs:
		if is_instance_valid(m) and m.is_alive() and m.boss and m.roaming:
			_diamond((at.call(m.global_position) as Array)[0], 6.5, Color(0.95, 0.2, 0.18))
	# 其他修士（AI）
	for f: Variant in _arr("_rivals"):
		if not is_instance_valid(f) or not f.is_alive():
			continue
		var a: Array = at.call(f.global_position)
		if a[1]:
			continue
		if f.hostile:
			_tri(a[0], 5.0, Color(1.0, 0.35, 0.3))
		else:
			pt.circle(a[0], 2.4, Color(0.92, 0.94, 0.96))
	# 队友（AI 补位的）
	for f: Variant in _arr("_allies"):
		if is_instance_valid(f):
			_mate((at.call(f.global_position) as Array)[0])
	# 联机里的真人
	if mgr.has_method("net_on") and mgr.net_on():
		for id: int in mgr.net.remotes.keys():
			var r: Variant = mgr.net.remotes[id]
			if not is_instance_valid(r) or not r.is_alive():
				continue
			var a: Array = at.call(r.global_position)
			if r.mate:
				_mate(a[0])
			elif not a[1]:
				_tri(a[0], 5.5, Color(1.0, 0.3, 0.25))
	# 搜点（2026-11-20）：只画探明了、没搜过、在范围里的。陶罐 = 小方块、灵药圃 = 绿点、坟冢 = 灰十字、宝库 = 紫星、宗门宝罐 = 金方块
	if mgr.get("search") != null and is_instance_valid(mgr.search):
		for mk: Array in mgr.search.marks(p3, rng * 1.02):
			var a: Array = at.call(mk[0])
			if a[1]:
				continue
			var q: Vector2 = a[0]
			match str(mk[1]):
				"jar":
					pt.rect(Rect2(q - Vector2(3.0, 3.0), Vector2(6, 6)), Color(0.05, 0.04, 0.03))
					pt.rect(Rect2(q - Vector2(2.0, 2.0), Vector2(4, 4)), Color(0.95, 0.82, 0.58))
				"herb":
					pt.circle(q, 3.8, Color(0.03, 0.06, 0.03))
					pt.circle(q, 2.8, Color(0.45, 0.95, 0.5))
				"grave":
					pt.line(q + Vector2(-3.5, 0), q + Vector2(3.5, 0), Color(0.82, 0.84, 0.9), 2.0)
					pt.line(q + Vector2(0, -4.5), q + Vector2(0, 3.5), Color(0.82, 0.84, 0.9), 2.0)
				"vault":
					_star(q, 6.0, Color(0.82, 0.5, 1.0))
				"urn":
					pt.rect(Rect2(q - Vector2(4.0, 4.0), Vector2(8, 8)), Color(0.05, 0.04, 0.02))
					pt.rect(Rect2(q - Vector2(3.0, 3.0), Vector2(6, 6)), Color(1.0, 0.76, 0.3))
	# 闪点：有人在撤离（白圈）/ 空间裂隙（紫）/ 宝库破禁（紫星）——一圈圈往外扩
	var tnow := float(Time.get_ticks_msec()) / 1000.0
	for pg: Variant in _arr("pings"):
		if not (pg is Array):
			continue
		var q2: Vector2 = (at.call(pg[0]) as Array)[0]
		var pc := [Color(1.0, 0.95, 0.85), Color(0.85, 0.55, 1.0), Color(0.82, 0.5, 1.0)][clampi(int(pg[1]), 0, 2)] as Color
		var ph := fmod(tnow * 1.4, 1.0)
		pt.arc(q2, 4.0 + 10.0 * ph, 0.0, TAU, 20, Color(pc, 1.0 - ph), 2.0)
		pt.circle(q2, 3.0, pc)
	# 传送阵：按种类上色（古传送阵青、灵石阵金、镇守阵朱、裂隙紫、破界符阵淡金）；没探明的是灰蓝问号圈
	var near_d := INF
	var near_ok := false
	if _fixed:
		# 新图：撤离点随时开放、位置公开（照 DarkArea），直接画关卡点表里的
		for mk: Array in mgr.level.call("map_marks", MapDef.layer_at(p3)):
			if str(mk[1]) != "extract":
				continue
			var ep2: Vector3 = mk[0]
			var q3: Vector2 = (at.call(ep2) as Array)[0]
			pt.circle(q3, 7.0, Color(0.03, 0.05, 0.08, 0.85))
			pt.arc(q3, 6.5, 0.0, TAU, 18, UiStyle.JADE, 2.0)
			pt.circle(q3, 2.8, UiStyle.JADE)
			var d2 := Vector2(ep2.x, ep2.z).distance_to(p)
			if d2 < near_d:
				near_d = d2
				near_ok = true
	for e: Dictionary in ([] if _fixed else _arr("_extracts")):
		var known: bool = e["known"]
		var ok: bool = e["active"]
		if known and not ok:
			continue
		var ep: Vector3 = e["pos"]
		var q: Vector2 = (at.call(ep) as Array)[0]
		var kind := str(e.get("kind", "gate"))
		var col: Color = (mgr.call("ex_col", kind) if mgr.has_method("ex_col") else UiStyle.JADE) if known else Color(0.55, 0.65, 0.8)
		pt.circle(q, 6.5, Color(0.03, 0.05, 0.08, 0.85))
		pt.arc(q, 6.0, 0.0, TAU, 16, col, 1.6)
		if known:
			pt.circle(q, 2.6, col)
		elif font != null:
			pt.text(font, q + Vector2(-4.0, 4.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		if kind == "rift":
			pt.arc(q, 8.5 + 2.0 * sin(tnow * 6.0), 0.0, TAU, 18, Color(col, 0.7), 1.4)
		var d := Vector2(ep.x, ep.z).distance_to(p)
		if d < near_d:
			near_d = d
			near_ok = known
	# 神识（2026-11-23）：一扫的光波圈 + 扫到的东西一圈圈闪
	var ss: Variant = mgr.get("shenshi")
	if ss != null and is_instance_valid(ss):
		var wv: Array = ss.map_wave()
		if not wv.is_empty():
			var wc: Vector3 = wv[0]
			var dq := Vector2(wc.x, wc.z) - p
			var q0 := c + Vector2(dq.dot(right), -dq.dot(fwd)) / rng * rad
			var rr := float(wv[1]) / rng * rad
			var wcol: Color = ss.wave_color()
			var wa := float(wv[2])
			if rr > 1.0 and rr < rad * 1.02:
				pt.arc(q0, rr, 0.0, TAU, 64, Color(wcol, 0.9 * wa), 2.2)
				pt.arc(q0, rr * 0.9, 0.0, TAU, 64, Color(wcol, 0.28 * wa), 1.2)
		for mk: Array in ss.map_marks():
			var mp: Vector3 = mk[0]
			var mcol: Color = mk[1]
			var age := float(mk[2])
			var hold := float(mk[3])
			var fade := 1.0 - clampf((age - (hold - 1.5)) / 1.5, 0.0, 1.0)
			var a: Array = at.call(mp)
			var q: Vector2 = a[0]
			if a[1]:
				# 出了范围：要紧的贴边画个小箭头指方向
				if float(mk[5]) >= 6.0:
					var od := (q - c).normalized()
					var os := Vector2(-od.y, od.x)
					var tip := c + od * (rad + 7.0)
					pt.poly(PackedVector2Array([tip + od * 5.0, tip - od * 3.0 + os * 4.5, tip - od * 3.0 - os * 4.5]), Color(mcol, 0.9 * fade))
				continue
			var ph := fmod(age * 1.25, 1.0)
			pt.arc(q, 4.5 + 8.0 * ph, 0.0, TAU, 20, Color(mcol, (1.0 - ph) * 0.95 * fade), 1.8)
			pt.arc(q, 5.0, 0.0, TAU, 16, Color(mcol.lerp(Color.WHITE, 0.3), 0.85 * fade), 1.4)
	# 「北」
	var n := Vector2(Vector2(0, -1).dot(right), -Vector2(0, -1).dot(fwd))   # 世界 -Z 在地图上的方向
	if font != null:
		var np := c + n * (SIZE * 0.5 * 0.94)
		pt.circle(np, 9.5, UiStyle.LINE)
		pt.circle(np, 8.3, UiStyle.SURF)
		pt.text(font, np + Vector2(-6.5, 5.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.CINNABAR)
	# 主角：箭头指向身体朝向（相对镜头）
	var body: float = mgr.player.visual.rotation.y - yaw
	var up := Vector2(-sin(body), -cos(body))
	var side := Vector2(-up.y, up.x)
	pt.poly(PackedVector2Array([c + up * 9.5, c - up * 6.0 + side * 6.5, c - up * 2.5, c - up * 6.0 - side * 6.5]), Color(0.05, 0.05, 0.06))
	pt.poly(PackedVector2Array([c + up * 7.5, c - up * 4.5 + side * 4.8, c - up * 2.0, c - up * 4.5 - side * 4.8]), Color.WHITE)
	# 最近的传送阵有多远、当前看多大范围
	if font != null:
		var txt := ("传送阵 %dm%s" % [int(near_d), "" if near_ok else "（未探明）"]) if near_d < INF else "传送阵皆毁"
		if _fixed:
			txt = ("撤离点 %dm" % int(near_d)) if near_d < INF else "此层无撤离点"
		pt.text_outline(font, Vector2(0.0, SIZE + 16.0), txt, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 15, 5, Color(0.04, 0.04, 0.05, 0.9))
		pt.text(font, Vector2(0.0, SIZE + 16.0), txt, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 15, UiStyle.TEXT)
	# 左上角「识」字小印：朱红 = 神识可用（点小地图就扫），纸色 + 一道朱红弧 = 冷却中
	if ss != null and is_instance_valid(ss):
		var sp := Vector2(14.0, 14.0)
		var rk := float(ss.ready_k())
		if rk >= 1.0:
			var pl := 0.5 + 0.5 * sin(tnow * 3.2)
			pt.circle(sp, 14.5 + 1.5 * pl, Color(UiStyle.CINNABAR, 0.22 * pl))
			pt.circle(sp, 12.5, UiStyle.CINNABAR)
			pt.arc(sp, 12.5, 0.0, TAU, 28, Color(UiStyle.LINE, 0.9), 1.2)
		else:
			pt.circle(sp, 12.5, UiStyle.SURF)
			pt.arc(sp, 12.5, 0.0, TAU, 28, Color(UiStyle.LINE, 0.55), 1.0)
			pt.arc(sp, 11.0, -PI * 0.5, -PI * 0.5 + TAU * rk, 28, UiStyle.CINNABAR, 2.6)
		if font != null:
			pt.text(font, sp + Vector2(-7.5, 5.5), "识", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiStyle.PAPER if rk >= 1.0 else Color(UiStyle.LINE, 0.6))
	pt.flush()      # 合批时：攒下的图形一次画完，再画字（老大世界逐个画过了，这里什么也不做）


## mgr 上的一个数组字段（没有就当空的：新图的管理器不一定有老大世界的全部字段）
func _arr(field: String) -> Array:
	var v: Variant = mgr.get(field) if mgr != null else null
	return v if v is Array else []


func _mate(q: Vector2) -> void:
	_pt.circle(q, 5.0, Color(0.04, 0.08, 0.07))
	_pt.circle(q, 3.8, UiStyle.JADE.lightened(0.15))


func _tri(q: Vector2, s: float, col: Color) -> void:
	_pt.poly(PackedVector2Array([q + Vector2(0, -s), q + Vector2(s * 0.87, s * 0.6), q + Vector2(-s * 0.87, s * 0.6)]), col)


func _star(q: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var r := s if i % 2 == 0 else s * 0.45
		pts.append(q + Vector2.from_angle(-PI * 0.5 + PI * 0.25 * float(i)) * r)
	var outline := PackedVector2Array()
	for v: Vector2 in pts:
		outline.append(q + (v - q) * 1.3)
	_pt.poly(outline, Color(0.05, 0.03, 0.06))
	_pt.poly(pts, col)


func _diamond(q: Vector2, s: float, col: Color) -> void:
	_pt.poly(PackedVector2Array([q + Vector2(0, -s - 1.5), q + Vector2(s + 1.5, 0), q + Vector2(0, s + 1.5), q + Vector2(-s - 1.5, 0)]), Color(0.05, 0.03, 0.03))
	_pt.poly(PackedVector2Array([q + Vector2(0, -s), q + Vector2(s, 0), q + Vector2(0, s), q + Vector2(-s, 0)]), col)


## 2026-11-24 新图的全屏大地图（ex_level.gd 的 open_big_map 建）：宣纸面板上铺这一层的整图，北朝上；
## 画撤离点（青圈）、钥匙房（朱红方印 + 号，门开着是青框）、Boss（红菱 + 名）、洞口 / 光井（墨色三角）、地名、队友（青点）、自己（白箭头）。
## 地下有洞窟的图右上角多一个「看洞窟 / 看地表」。点面板外面或「合上」关掉。手机上面板占满短边。
## 2026-11-24 F_maps（I_int §6：网页档大地图开着时绘制调用 264~277）：标记合成一次绘制（Painter），字统一画在最上面；
##   面板外的暗底 0.15 秒内由六成压到不透明（cover 0 → 1），盖严之后 ex_level 把 3D 渲染关掉（看不见的就不画），关图时还原。
class BigMap extends Control:
	signal closed
	const COVER_T := 0.15
	var level: Node3D
	var font: Font
	var mobile := false
	var cover := 0.0              # 面板外暗底盖严了多少（1 = 不透明，ex_level 见了就关 3D）
	var _ln := "surface"
	var _panel := Rect2()
	var _inner := Rect2()
	var _btn_close: Button
	var _btn_layer: Button
	var _pt: Painter
	var _sb: StyleBox             # 宣纸面板（只建一次，不每帧新建）

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_ALWAYS
		_ln = str(level.get("layer"))
		_pt = Painter.new(self)
		_pt.direct = false
		_sb = UiStyle.scroll(18.0, false)
		_btn_close = Button.new()
		_btn_close.text = "合上"
		UiStyle.style_button(_btn_close, true)
		_btn_close.add_theme_font_override("font", font)
		_btn_close.add_theme_font_size_override("font_size", 26 if mobile else 20)
		_btn_close.pressed.connect(func() -> void: closed.emit())
		add_child(_btn_close)
		_btn_layer = Button.new()
		UiStyle.style_button(_btn_layer, true)
		_btn_layer.add_theme_font_override("font", font)
		_btn_layer.add_theme_font_size_override("font_size", 26 if mobile else 20)
		_btn_layer.pressed.connect(func() -> void:
			_ln = "cavern" if _ln == "surface" else "surface"
			queue_redraw())
		add_child(_btn_layer)

	func _gui_input(e: InputEvent) -> void:
		var tap := (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed)
		if tap:
			var pos: Vector2 = (e as InputEventMouseButton).position if e is InputEventMouseButton else (e as InputEventScreenTouch).position
			if not _panel.has_point(pos):
				closed.emit()
			accept_event()

	func _process(dt: float) -> void:
		cover = minf(cover + dt / COVER_T, 1.0)
		var vs := get_viewport_rect().size
		var side := minf(vs.x - 24.0, vs.y - 24.0)
		_panel = Rect2((vs - Vector2(side, side)) * 0.5, Vector2(side, side))
		_inner = _panel.grow(-side * 0.06)
		var bs := Vector2(118, 56) if mobile else Vector2(96, 42)
		_btn_close.size = bs
		_btn_close.position = Vector2(_panel.end.x - bs.x - side * 0.035, _panel.position.y + side * 0.012)
		_btn_layer.size = Vector2(bs.x * 1.3, bs.y)
		_btn_layer.position = Vector2(_panel.position.x + side * 0.035, _panel.position.y + side * 0.012)
		_btn_layer.text = "看地表" if _ln == "cavern" else "看洞窟"
		queue_redraw()

	func _w2m(w: Vector3, c: Vector2, span: float) -> Vector2:
		return _inner.position + (Vector2(w.x, w.z) - c + Vector2(span, span) * 0.5) / span * _inner.size

	func _draw() -> void:
		if level == null:
			return
		var pt := _pt
		var vs := get_viewport_rect().size
		# 底：贴图类的（暗底 / 宣纸面板 / 整图）先直接画，图形攒到 pt 里最后一次画完，字在最上面
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.02, 0.03, 0.6).lerp(Color(UiStyle.INK, 1.0), cover))
		draw_style_box(_sb, _panel)
		var mt: Dictionary = level.call("map_tex_layer", _ln)
		var c: Vector2 = mt["center"]
		var span: float = mt["span"]
		draw_texture_rect(mt["tex"] as Texture2D, _inner, false)
		pt.rect(_inner, UiStyle.LINE, false, 2.0)
		var fs := 22 if mobile else 16
		var mp: Dictionary = level.get("map")
		var title := "%s · %s" % [str(mp.get("name", "")), "洞窟" if _ln == "cavern" else "地表"]
		pt.text(font, Vector2(_panel.position.x, _panel.position.y + _panel.size.y * 0.045), title, HORIZONTAL_ALIGNMENT_CENTER, _panel.size.x, fs + 6, UiStyle.TEXT_INK)
		var k := _inner.size.x / 600.0
		for mk: Array in level.call("map_marks", _ln):
			var q := _w2m(mk[0], c, span)
			if not _inner.grow(4.0).has_point(q):
				continue
			match str(mk[1]):
				"extract":
					pt.circle(q, 11.0 * k + 4.0, Color(0.03, 0.05, 0.08, 0.85))
					pt.arc(q, 10.0 * k + 4.0, 0.0, TAU, 24, UiStyle.JADE, 2.5)
					pt.circle(q, 4.0 * k + 1.5, UiStyle.JADE)
					pt.text_outline(font, q + Vector2(10.0 * k + 6.0, 6.0), "撤", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.03, 0.03))
					pt.text(font, q + Vector2(10.0 * k + 6.0, 6.0), "撤", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.JADE.lightened(0.3))
				"key", "key_open":
					var s := 8.0 * k + 4.0
					pt.rect(Rect2(q - Vector2(s, s), Vector2(s, s) * 2.0), UiStyle.CINNABAR)
					pt.rect(Rect2(q - Vector2(s, s), Vector2(s, s) * 2.0), UiStyle.JADE if str(mk[1]) == "key_open" else UiStyle.LINE, false, 2.0)
					pt.text(font, q + Vector2(-s, s * 0.55), str(mk[2]), HORIZONTAL_ALIGNMENT_CENTER, s * 2.0, fs - 4, UiStyle.PAPER)
				"boss":
					var s2 := 9.0 * k + 4.0
					pt.poly(PackedVector2Array([q + Vector2(0, -s2 - 2), q + Vector2(s2 + 2, 0), q + Vector2(0, s2 + 2), q + Vector2(-s2 - 2, 0)]), Color(0.06, 0.02, 0.02))
					pt.poly(PackedVector2Array([q + Vector2(0, -s2), q + Vector2(s2, 0), q + Vector2(0, s2), q + Vector2(-s2, 0)]), Color(0.92, 0.22, 0.18))
					pt.text_outline(font, q + Vector2(s2 + 5.0, 6.0), str(mk[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.02, 0.02))
					pt.text(font, q + Vector2(s2 + 5.0, 6.0), str(mk[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.78, 0.7))
				"link":
					var s3 := 7.0 * k + 3.0
					pt.poly(PackedVector2Array([q + Vector2(0, s3), q + Vector2(s3, -s3), q + Vector2(-s3, -s3)]), UiStyle.LINE)
					pt.poly(PackedVector2Array([q + Vector2(0, s3 * 0.5), q + Vector2(s3 * 0.55, -s3 * 0.6), q + Vector2(-s3 * 0.55, -s3 * 0.6)]), UiStyle.GOLD)
				"poi":
					pt.text_outline(font, q + Vector2(-60, 6), str(mk[2]), HORIZONTAL_ALIGNMENT_CENTER, 120, fs, 5, Color(0.96, 0.93, 0.86, 0.9))
					pt.text(font, q + Vector2(-60, 6), str(mk[2]), HORIZONTAL_ALIGNMENT_CENTER, 120, fs, UiStyle.TEXT_INK)
		for mp2: Vector3 in level.call("mates"):
			if str(level.call("layer_of", mp2)) == _ln:
				var qm := _w2m(mp2, c, span)
				pt.circle(qm, 7.0, Color(0.03, 0.06, 0.05))
				pt.circle(qm, 5.2, UiStyle.JADE.lightened(0.15))
		var pl: Node3D = level.get("player")
		if pl != null and str(level.call("layer_of", pl.global_position)) == _ln:
			var qp := _w2m(pl.global_position, c, span)
			var vis: Node3D = pl.get("visual")
			var yaw := vis.rotation.y if vis != null else 0.0
			var up := Vector2(-sin(yaw), -cos(yaw))
			var sd := Vector2(-up.y, up.x)
			var sz := 13.0 if mobile else 10.0
			pt.poly(PackedVector2Array([qp + up * sz * 1.3, qp - up * sz * 0.8 + sd * sz * 0.9, qp - up * sz * 0.3, qp - up * sz * 0.8 - sd * sz * 0.9]), Color(0.05, 0.05, 0.06))
			pt.poly(PackedVector2Array([qp + up * sz, qp - up * sz * 0.6 + sd * sz * 0.65, qp - up * sz * 0.25, qp - up * sz * 0.6 - sd * sz * 0.65]), Color.WHITE)
		# 图例
		var ly := _panel.end.y - _panel.size.y * 0.025
		var legend := "青圈 撤离点　朱印 禁室　红菱 首领　金角 洞口" if _ln == "surface" else "朱印 禁室　红菱 首领　金角 光井（上地表）"
		pt.text(font, Vector2(_panel.position.x, ly), legend, HORIZONTAL_ALIGNMENT_CENTER, _panel.size.x, fs - 2, UiStyle.TEXT_SOFT)
		pt.flush()


## 2026-11-24 F_maps（I_int §5 / §6）：标记合批的笔。网页（兼容渲染器）里每个 draw_circle / draw_arc / draw_colored_polygon 都是单独一次
## 绘制调用，字和图形交替画时字也连不成批：小地图一帧 24~51 次、大地图约 100 次。
## · direct = false（新图的小地图、大地图）：所有图形的三角形攒进一个顶点数组（带逐点颜色），flush() 时一次 canvas_item_add_triangle_array 画完
##   （= 1 次绘制调用，三角形按调用顺序叠，半透明照旧）；字按「描边 → 填字」、同描边同字号的放一起画在最上面（同一张字形贴图连成一批）。
##   圆 / 整圈的弧用缓存的单位圆 / 圆环模板（按段数和内外半径比）乘一个 Transform2D 生成，GDScript 里逐点的活很少。
## · direct = true（老大世界的小地图）：每个调用原样转给 CanvasItem 的 draw_*，参数、顺序和以前一条不差，画面不变。
class Painter extends RefCounted:
	const RING_Q := 256.0         # 圆环内外半径比的量化档（宽度误差 ≤ 外半径 / 512）
	var ci: CanvasItem
	var direct := true
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _txt: Array = []          # [描边粗细（0 = 填字）, font, pos, text, align, width, size, color]
	var _tpl := {}                # Vector2i(段数, 内外半径比档) → 单位圆环（档 0 = 实心圆）的三角形

	func _init(owner: CanvasItem) -> void:
		ci = owner

	func _put(tri: PackedVector2Array, col: Color) -> void:
		_pts.append_array(tri)
		var ca := PackedColorArray()
		ca.resize(tri.size())
		ca.fill(col)
		_cols.append_array(ca)

	func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		_put(PackedVector2Array([a, b, c, a, c, d]), col)

	## 单位圆环（qi / RING_Q = 内半径 / 外半径；qi = 0 是实心圆）的三角形，seg 段，从 0 弧度起
	func _ring(seg: int, qi: int) -> PackedVector2Array:
		var key := Vector2i(seg, qi)
		if _tpl.has(key):
			return _tpl[key]
		if _tpl.size() > 256:
			_tpl.clear()          # 一圈圈往外扩的弧每帧内外比都在变：别无限攒
		var q := float(qi) / RING_Q
		var out := PackedVector2Array()
		for i in seg:
			var a := Vector2.from_angle(TAU * float(i) / float(seg))
			var b := Vector2.from_angle(TAU * float(i + 1) / float(seg))
			if qi <= 0:
				out.append(Vector2.ZERO)
				out.append(a)
				out.append(b)
			else:
				out.append(a)
				out.append(b)
				out.append(b * q)
				out.append(a)
				out.append(b * q)
				out.append(a * q)
		_tpl[key] = out
		return out

	func circle(c: Vector2, r: float, col: Color) -> void:
		if direct:
			ci.draw_circle(c, r, col)
			return
		_put(Transform2D(0.0, Vector2(r, r), 0.0, c) * _ring(16 if r <= 6.0 else 32, 0), col)

	## 同 draw_arc(c, r, a0, a1, n 个点, col, w)：线宽 w 跨在半径 r 两侧
	func arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
		if direct:
			ci.draw_arc(c, r, a0, a1, n, col, w)
			return
		var ro := r + w * 0.5
		var ri := maxf(r - w * 0.5, 0.0)
		var seg := maxi(n - 1, 3)
		if ro <= 0.0:
			return
		if absf(a1 - a0) >= TAU - 0.001:
			_put(Transform2D(a0, Vector2(ro, ro), 0.0, c) * _ring(seg, maxi(roundi(ri / ro * RING_Q), 1)), col)
			return
		var strip := PackedVector2Array()
		for i in seg:
			var u := Vector2.from_angle(lerpf(a0, a1, float(i) / float(seg)))
			var v := Vector2.from_angle(lerpf(a0, a1, float(i + 1) / float(seg)))
			strip.append(c + u * ro)
			strip.append(c + v * ro)
			strip.append(c + v * ri)
			strip.append(c + u * ro)
			strip.append(c + v * ri)
			strip.append(c + u * ri)
		_put(strip, col)

	## 同 draw_rect：不填充时线宽 w 跨在边框两侧（同引擎的画法）
	func rect(r: Rect2, col: Color, filled := true, w := -1.0) -> void:
		if direct:
			ci.draw_rect(r, col, filled, w)
			return
		if filled:
			_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col)
			return
		var t := maxf(w, 1.0)
		var h := t * 0.5
		var a := r.position - Vector2(h, h)
		var b := r.end + Vector2(h, h)
		rect(Rect2(a, Vector2(b.x - a.x, t)), col)
		rect(Rect2(Vector2(a.x, b.y - t), Vector2(b.x - a.x, t)), col)
		rect(Rect2(Vector2(a.x, a.y + t), Vector2(t, b.y - a.y - 2.0 * t)), col)
		rect(Rect2(Vector2(b.x - t, a.y + t), Vector2(t, b.y - a.y - 2.0 * t)), col)

	func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
		if direct:
			ci.draw_line(a, b, col, w)
			return
		var d := (b - a).normalized().orthogonal() * (maxf(w, 1.0) * 0.5)
		_quad(a + d, b + d, b - d, a - d, col)

	func poly(p: PackedVector2Array, col: Color) -> void:
		if direct:
			ci.draw_colored_polygon(p, col)
			return
		if p.size() == 3:
			_put(p, col)
			return
		var idx := Geometry2D.triangulate_polygon(p)
		var tri := PackedVector2Array()
		for i: int in idx:
			tri.append(p[i])
		_put(tri, col)

	func text(f: Font, pos: Vector2, s: String, al: HorizontalAlignment, w: float, sz: int, col: Color) -> void:
		if direct:
			ci.draw_string(f, pos, s, al, w, sz, col)
		else:
			_txt.append([0, f, pos, s, al, w, sz, col])

	func text_outline(f: Font, pos: Vector2, s: String, al: HorizontalAlignment, w: float, sz: int, osz: int, col: Color) -> void:
		if direct:
			ci.draw_string_outline(f, pos, s, al, w, sz, osz, col)
		else:
			_txt.append([osz, f, pos, s, al, w, sz, col])

	## 合批时：图形一次画完，再画字（先全部描边、再全部填字；同描边同字号的挨着画）。direct 时什么也不做
	func flush() -> void:
		if direct:
			return
		if not _pts.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), _pts, _cols)
		_pts = PackedVector2Array()
		_cols = PackedColorArray()
		var groups := {}
		for t: Array in _txt:
			var key := Vector2i(int(t[0]), int(t[6]))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(t)
		for fill_pass in 2:
			for key: Vector2i in groups:
				if (key.x == 0) != (fill_pass == 1):
					continue
				for t: Array in groups[key]:
					if key.x > 0:
						ci.draw_string_outline(t[1], t[2], t[3], t[4], t[5], t[6], key.x, t[7])
					else:
						ci.draw_string(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
		_txt.clear()
