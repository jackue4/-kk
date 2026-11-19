extends Control
## 境界突破题字（参考 _ref/realm_calligraphy.png）：屏幕右侧一列竖排手写毛笔字"××期"。
## 墨色烟带打底、边缘毛糙并散着飞墨碎屑；顶端一枚剑翎纹章；字芯近白、外晕境界色；
## 左侧一行小字"境界突破"，末尾钤一方朱印。字体优先用系统里的行楷 / 舒体（华文行楷、方正舒体），没有再退到楷体。
## 时间轴（真实时间，不受慢动作影响）：烟带由中间向两头铺开 → 纹章放大落定一闪 → 逐字由上往下"写"出
## （brush_reveal.gdshader 遮罩，前沿是毛糙的笔锋）→ 每写完一字溅几点飞墨、字光一亮 → 钤印 → 停留 → 整列上飘淡出、飞墨四散。
## 故意不写 class_name：用 preload 引用。

const Sfx := preload("res://scripts/sfx.gd")
const REVEAL := preload("res://shaders/brush_reveal.gdshader")
const FONT_FILES := ["C:/Windows/Fonts/STXINGKA.TTF", "C:/Windows/Fonts/FZSTK.TTF",
		"C:/Windows/Fonts/STKAITI.TTF", "C:/Windows/Fonts/simkai.ttf"]
const FONT_NAMES := ["STXingkai", "FZShuTi", "STKaiti", "KaiTi"]
const S := 100            # 主字字号（以 900 高的画面为基准，按画面高度缩放）
const PITCH := 104.0      # 字距
const ORN_H := 100.0      # 顶端纹章区高度
const T_CHAR0 := 0.42     # 第一个字开始书写
const T_CHAR := 0.3       # 字与字的间隔
const T_WRITE := 0.22     # 每字书写时长
const T_HOLD := 3.2       # 开始淡出
const T_OUT := 0.8
const SUB := "境界突破"
const INK := Color(0.03, 0.025, 0.045)
const SEAL := Color(0.78, 0.13, 0.11)

var x_frac := -1.0     # >= 0：题字这一列摆在画面宽度的这个比例处（区域题名用）；默认贴右侧
var size_k := 1.0
var _font: Font
var _back: Control
var _ink: Control
var _reveal: ShaderMaterial
var _top: Control
var _text := ""
var _sub := SUB
var _seal := "破"                   # 一字印或四字印（四字按 2×2 自右向左竖读）
var _col := Color.WHITE
var _t := -1.0
var _spark_acc := 0.0
var _scattered := false
var _snd := 0
var _stamped := false
var _edge := PackedFloat32Array()   # 烟带左右边缘的毛糙偏移（交替存左 / 右）
var _jit := PackedVector2Array()    # 每字的 (倾斜, 横向偏移)：手写不齐的感觉
var _flare := PackedFloat32Array()  # 每字写完时的一亮；-1 = 还没写完
var _flakes: Array = []             # 飞墨 [pos, vel, size, rot, spin, age, life, color]
var _sparks: Array = []             # 光点 [pos, vel, size, age, life]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = _load_font()
	_back = _layer(self, _draw_back)
	_ink = _layer(self, _draw_ink)
	_reveal = ShaderMaterial.new()
	_reveal.shader = REVEAL
	_ink.material = _reveal
	_top = _layer(self, _draw_top)


static func _load_font() -> Font:
	for p: String in FONT_FILES:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				return f
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(FONT_NAMES)
	return sf


func _layer(parent: Node, fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	parent.add_child(c)
	return c


## 题字：text 竖排写出（如"筑基期"），col 为该境界主色；sub 为左侧小字、seal 为印文（Boss 登场题名也走这里）
func show_realm(text: String, col: Color, sub := SUB, seal := "破") -> void:
	_text = text
	_sub = sub
	_seal = seal
	_col = col
	_t = 0.0
	_spark_acc = 0.0
	_scattered = false
	_stamped = false
	_snd = 0
	visible = true
	modulate.a = 1.0
	var n := text.length()
	_jit.resize(n)
	_flare.resize(n)
	for i in n:
		_jit[i] = Vector2(randf_range(-0.07, 0.07), randf_range(-7.0, 7.0))
		_flare[i] = -1.0
	# 烟带边缘：随机游走，左右各一条
	var m := 40
	_edge.resize(m * 2)
	var a := 0.0
	var b := 0.0
	for i in m:
		a = clampf(a + randf_range(-9.0, 9.0), -16.0, 16.0)
		b = clampf(b + randf_range(-9.0, 9.0), -16.0, 16.0)
		_edge[i * 2] = a
		_edge[i * 2 + 1] = b
	_flakes.clear()
	_sparks.clear()
	# 烟带两侧本来就散着一些墨屑
	for i in 24:
		var side := -1.0 if i % 2 == 0 else 1.0
		_flake(Vector2(side * randf_range(58.0, 96.0), randf_range(0.0, _bottom())),
				Vector2(side * randf_range(2.0, 12.0), randf_range(-8.0, 4.0)), randf_range(1.5, 4.5), T_HOLD + T_OUT, false)


func _char_top(i: int) -> float:
	return ORN_H + 8.0 + PITCH * i


func _bottom() -> float:
	return _char_top(_text.length()) + 8.0


func _char_t(i: int) -> float:
	return T_CHAR0 + T_CHAR * i


func _done_t() -> float:
	return _char_t(_text.length() - 1) + T_WRITE


static func _ease_out(x: float) -> float:
	var u := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - u * u * u


func _flake(p: Vector2, v: Vector2, size: float, life: float, ember: bool) -> void:
	var c := Color(_col.lightened(0.25), 0.9) if ember else Color(INK, 0.88)
	_flakes.append([p, v, size, randf() * TAU, randf_range(-4.0, 4.0), 0.0, life, c])


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 0.05)
	_t += dt
	var vs := get_viewport_rect().size
	var k := vs.y / 900.0
	var out := smoothstep(T_HOLD, T_HOLD + T_OUT, _t)
	k *= size_k
	scale = Vector2(k, k)
	position = Vector2(vs.x - 150.0 * k if x_frac < 0.0 else vs.x * x_frac, vs.y * 0.12 - 34.0 * k * out)
	modulate.a = 1.0 - out
	var n := _text.length()
	if _snd < n and _t >= _char_t(_snd):
		_snd += 1
		Sfx.play("swing", -16.0, 0.55)
	for i in n:
		if _flare[i] < 0.0:
			if _t >= _char_t(i) + T_WRITE:
				_flare[i] = 1.0
				var cy := _char_top(i) + PITCH * 0.5
				for j in 8:
					var side := -1.0 if j % 2 == 0 else 1.0
					_flake(Vector2(side * randf_range(28.0, 58.0), cy + randf_range(-40.0, 40.0)),
							Vector2(side * randf_range(60.0, 170.0), randf_range(-60.0, 30.0)),
							randf_range(2.0, 5.5), randf_range(0.6, 1.2), j % 3 == 0)
		else:
			_flare[i] = maxf(_flare[i] - dt * 3.0, 0.0)
	if not _stamped and _t >= _done_t() + 0.18:
		_stamped = true
		Sfx.play("thud", -9.0, 1.4)
	if not _scattered and _t >= T_HOLD:
		_scattered = true
		for f: Array in _flakes:
			var p: Vector2 = f[0]
			f[1] = (f[1] as Vector2) + Vector2(signf(p.x) * randf_range(40.0, 120.0), randf_range(-50.0, -10.0))
			f[6] = minf(float(f[6]), float(f[5]) + randf_range(0.5, 0.9))
		for i in 26:
			var side := -1.0 if i % 2 == 0 else 1.0
			_flake(Vector2(side * randf_range(40.0, 70.0), randf_range(0.0, _bottom())),
					Vector2(side * randf_range(50.0, 160.0), randf_range(-70.0, 0.0)),
					randf_range(1.5, 5.0), randf_range(0.5, 0.9), i % 4 == 0)
	if _t < T_HOLD + 0.3 and _t > T_CHAR0:
		_spark_acc += dt
		while _spark_acc > 0.06:
			_spark_acc -= 0.06
			var y := randf_range(ORN_H * 0.5, minf(_front() + 20.0, _bottom()))
			_sparks.append([Vector2(randf_range(-48.0, 48.0), y), Vector2(randf_range(-10.0, 10.0), randf_range(-65.0, -25.0)),
					randf_range(1.2, 2.6), 0.0, randf_range(0.8, 1.4)])
	_step_bits(dt)
	if _t >= T_HOLD + T_OUT + 0.2:
		_t = -1.0
		visible = false
		return
	var front := _front()
	_reveal.set_shader_parameter("front", front if front >= 0.0 else -1000.0)
	for c: Control in [_back, _ink, _top]:
		c.queue_redraw()


func _step_bits(dt: float) -> void:
	for i in range(_flakes.size() - 1, -1, -1):
		var f: Array = _flakes[i]
		f[5] = float(f[5]) + dt
		if float(f[5]) >= float(f[6]):
			_flakes.remove_at(i)
			continue
		var v: Vector2 = f[1]
		f[0] = (f[0] as Vector2) + v * dt
		v *= exp(-1.8 * dt)
		v.y += 25.0 * dt
		f[1] = v
		f[3] = float(f[3]) + float(f[4]) * dt
	for i in range(_sparks.size() - 1, -1, -1):
		var s: Array = _sparks[i]
		s[3] = float(s[3]) + dt
		if float(s[3]) >= float(s[4]):
			_sparks.remove_at(i)
			continue
		s[0] = (s[0] as Vector2) + (s[1] as Vector2) * dt


## 书写前沿（本地 y）：正在写的字从字顶往下推，写完停在下一字顶；还没开写返回 -1
func _front() -> float:
	var front := -1.0
	for i in _text.length():
		var t0 := _char_t(i)
		if _t >= t0:
			front = _char_top(i) + (PITCH + 6.0) * _ease_out((_t - t0) / T_WRITE)
	return front


# ---------- 绘制 ----------

func _draw_back() -> void:
	var grow := maxf(_ease_out(_t / 0.32), 0.05)
	var top := -20.0
	var bot := _bottom() + 40.0
	var tint := INK.lerp(Color(_col.r * 0.25, _col.g * 0.25, _col.b * 0.25), 0.3)
	_strip(top, bot, grow, 88.0, 1.3, Color(tint, 0.36))
	_strip(top, bot, grow, 62.0, 1.0, Color(tint, 0.82))
	# 字后一道淡淡的境界色光
	var lit := clampf((_t - T_CHAR0) / 0.6, 0.0, 1.0)
	_strip(ORN_H * 0.4, bot - 20.0, grow, 30.0, 0.3, Color(_col, 0.14 * lit))
	for f: Array in _flakes:
		var age: float = f[5]
		var life: float = f[6]
		var c: Color = f[7]
		c.a *= 1.0 - smoothstep(life * 0.55, life, age)
		var p: Vector2 = f[0]
		var r: float = f[2]
		var rot: float = f[3]
		var pts := PackedVector2Array()
		for j in 4:
			var rr: float = [1.0, 0.6, 1.15, 0.7][j]
			var a: float = rot + [0.0, 1.7, 3.3, 4.6][j]
			pts.append(p + Vector2(cos(a), sin(a)) * r * rr)
		_back.draw_colored_polygon(pts, c)


## 一条竖向烟带：两头收窄淡出、左右边缘毛糙；grow 让它从中间向两头铺开
func _strip(top: float, bot: float, grow: float, hw: float, rough: float, col: Color) -> void:
	var m := _edge.size() / 2
	var mid := (top + bot) * 0.5
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(m * 2)
	cols.resize(m * 2)
	for i in m:
		var u := float(i) / float(m - 1)
		var y := mid + (lerpf(top, bot, u) - mid) * grow
		var taper := 0.55 + 0.45 * sin(PI * clampf(u * 1.1 - 0.05, 0.0, 1.0))
		var fade := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.84, 1.0, u))
		var c := Color(col, col.a * fade)
		pts[i] = Vector2(-hw * taper + _edge[i * 2] * rough, y)
		cols[i] = c
		pts[m * 2 - 1 - i] = Vector2(hw * taper + _edge[i * 2 + 1] * rough, y)
		cols[m * 2 - 1 - i] = c
	_back.draw_polygon(pts, cols)


## 字层：书写遮罩在 brush_reveal.gdshader 里按层内 y 做，所以这里不用 draw_set_transform（每字只做横向错位）
func _draw_ink() -> void:
	var base := (_font.get_ascent(S) - _font.get_descent(S)) * 0.5
	var w := float(S) * 2.0
	for i in _text.length():
		var ch := _text[i]
		var f := maxf(_flare[i], 0.0)
		var p := Vector2(-float(S) + _jit[i].y, _char_top(i) + PITCH * 0.5 + base)
		var al := HORIZONTAL_ALIGNMENT_CENTER
		_ink.draw_string_outline(_font, p + Vector2(4.0, 6.0), ch, al, w, S, 12, Color(0.0, 0.0, 0.0, 0.5))
		_ink.draw_string_outline(_font, p, ch, al, w, S, 28, Color(_col, 0.09 + 0.14 * f))
		_ink.draw_string_outline(_font, p, ch, al, w, S, 16, Color(_col, 0.22 + 0.22 * f))
		_ink.draw_string_outline(_font, p, ch, al, w, S, 7, Color(_col.lightened(0.15), 0.8))
		_ink.draw_string(_font, p, ch, al, w, S, Color.WHITE.lerp(_col, 0.15 * (1.0 - f)))


func _draw_top() -> void:
	_draw_crest()
	# 左侧小字（默认"境界突破"）
	var sa := clampf((_t - _done_t() - 0.05) / 0.35, 0.0, 1.0)
	if sa > 0.0:
		var fs := 26
		var b := (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
		for i in _sub.length():
			var p := Vector2(-132.0,ORN_H + 34.0 + 31.0 * i + b - 8.0 * (1.0 - sa))
			_top.draw_string_outline(_font, p, _sub[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs, 6, Color(_col, 0.55 * sa))
			_top.draw_string(_font, p, _sub[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs, Color(1.0, 0.97, 0.92, 0.9 * sa))
	# 末尾钤一方朱印
	var sk := clampf((_t - _done_t() - 0.18) / 0.12, 0.0, 1.0)
	if sk > 0.0:
		var s := lerpf(1.8, 1.0, _ease_out(sk))
		var four := _seal.length() == 4
		var h := 28.0 if four else 20.0
		_top.draw_set_transform(Vector2(40.0, _bottom() - 6.0 + (8.0 if four else 0.0)), -0.08, Vector2(s, s))
		_top.draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), Color(SEAL, 0.92 * sk))
		_top.draw_rect(Rect2(-h + 4.0, -h + 4.0, h * 2.0 - 8.0, h * 2.0 - 8.0), Color(1.0, 0.9, 0.85, 0.5 * sk), false, 1.5)
		if four:
			var fs4 := 20
			var b4 := (_font.get_ascent(fs4) - _font.get_descent(fs4)) * 0.5
			for i in 4:
				var cx := 10.0 if i < 2 else -10.0  # 印文自右向左竖读
				var cy := (-10.0 if i % 2 == 0 else 10.0) + b4
				_top.draw_string(_font, Vector2(cx - 12.0, cy), _seal[i], HORIZONTAL_ALIGNMENT_CENTER, 24.0, fs4, Color(1.0, 0.94, 0.9, sk))
		else:
			var fs2 := 27
			var b2 := (_font.get_ascent(fs2) - _font.get_descent(fs2)) * 0.5
			_top.draw_string(_font, Vector2(-20.0, b2), _seal, HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs2, Color(1.0, 0.94, 0.9, sk))
		_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 上飘的光点
	var sc := Color.WHITE.lerp(_col, 0.45)
	for s: Array in _sparks:
		var a := 1.0 - float(s[3]) / float(s[4])
		var p: Vector2 = s[0]
		var r: float = s[2]
		_top.draw_circle(p, r * 2.6, Color(_col, 0.2 * a))
		_top.draw_circle(p, r, Color(sc, a))


## 顶端剑翎纹章：五片向上张开的剑翎 + 一根下垂短锋 + 托底一道弧，先放大一闪再落定
func _draw_crest() -> void:
	var ok := _ease_out((_t - 0.1) / 0.25)
	if ok <= 0.0:
		return
	var flash := 1.0 - clampf((_t - 0.35) / 0.45, 0.0, 1.0)
	var b := Vector2(0.0, ORN_H - 14.0)
	var s := lerpf(1.6, 1.0, ok)
	_top.draw_set_transform(b * (1.0 - s), 0.0, Vector2(s, s))
	var blades := [[0.0, 76.0, 8.0], [0.42, 58.0, 6.5], [-0.42, 58.0, 6.5], [0.95, 40.0, 5.5], [-0.95, 40.0, 5.5], [PI, 24.0, 6.0]]
	var glow := Color(_col, (0.3 + 0.45 * flash) * ok)
	var core := Color(Color.WHITE.lerp(_col, 0.22 * (1.0 - flash)), ok)
	for pass_i in 2:
		var wk := 2.7 if pass_i == 0 else 1.0
		var c := glow if pass_i == 0 else core
		for bl: Array in blades:
			var ang: float = bl[0]
			var d := Vector2(sin(ang), -cos(ang))
			var side := Vector2(-d.y, d.x) * float(bl[2]) * wk
			var ln: float = bl[1]
			var tip := b + d * (ln + (6.0 if pass_i == 0 else 0.0))
			var mid := b + d * ln * 0.28
			_top.draw_colored_polygon(PackedVector2Array([b, mid + side, tip, mid - side]), c)
		_top.draw_arc(b + Vector2(0.0, -8.0), 32.0, 0.15 * PI, 0.85 * PI, 24, c, 3.0 * wk, true)
		_top.draw_circle(b, 5.0 * wk, c)
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
