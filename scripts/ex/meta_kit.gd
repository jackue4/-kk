extends RefCounted
## 主城「元界面」（备战 / 商店 / 段位，scripts/ex/meta_ui.gd 和三张页）共用的一套样式和小部件。
## 2026-11-24 用户原话：「现在游戏的整体的ui都不够艺术，没有什么设计感，交互体验也很老套，ui切换的时候也没动画……通用的ui背景元素很丑，
## 排版布局也不好看，我希望你按照自己的审美，重构现在的ui交互界面，包括交互体验，美术资源」。
## 定的调子（和英雄选择界面一脉）：
##   · 不再铺一整张宣纸大面板。底是虚化压暗的场景，东西直接浮在上面；要圈一块地方时用「墨玉片」—— 半透明的深色圆角片 + 一圈细金线
##   · 金线（GOLD）= 结构和装饰，朱砂 = 主操作 / 选中，青玉 = 好消息，品质色只给物品；字是暖白，题字用行楷
##   · 线稿素材（assets/ui/meta_*.png，_tasks/ui_meta/make_meta_art.py 画的）：星盘 / 回纹角花 / 分隔线 / 入口图标，都是白 + 透明度、这里染色
##   · 会动：进场各块错开滑入、格子一格格冒出来、按下缩一点、选中弹一下、数字滚动（都在这里的 anim 小函数里）
## 2026-11-25 主干解耦：物品 / 战力改走修仙那套（raid_items.gd 的物品、Data.TIER_COLORS 品阶色、CS.power 战力），不再引用搜打撤的 ex_data / ex_item_view。
## 故意不写 class_name：const MetaKit := preload("res://scripts/ex/meta_kit.gd")。

const UiStyle := preload("res://scripts/ui_style.gd")
const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const CS := preload("res://scripts/combat_stats.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const INK := Color(0.055, 0.05, 0.06)
const GLASS := Color(0.085, 0.08, 0.095, 0.8)
const GLASS_HI := Color(0.17, 0.16, 0.18, 0.94)
const SLATE := Color(0.14, 0.135, 0.15, 0.95)
const GOLD := Color(0.9, 0.76, 0.46)
const GOLD_DIM := Color(0.62, 0.52, 0.33)
const TEXT := Color(0.95, 0.92, 0.85)
const TEXT_DIM := Color(0.76, 0.72, 0.65)
const TEXT_FAINT := Color(0.56, 0.53, 0.48)
const CINNABAR := Color(0.82, 0.25, 0.18)
const JADE := Color(0.47, 0.82, 0.7)
const BAD := Color(1.0, 0.52, 0.42)

## 徽记图样的颜色（老的段位档：未入流 / 炼气 / 筑基 / 结丹 / 元婴 / 化神）；境界徽记另按 Realm.LIST 的境界色（realm_col）
const TIER_COL := [Color(0.6, 0.58, 0.54), Color(0.86, 0.6, 0.38), Color(0.66, 0.8, 0.94), Color(0.97, 0.82, 0.42), Color(0.78, 0.6, 1.0), Color(1.0, 0.95, 0.82)]

static var _sb := {}
static var _grad_up: GradientTexture2D
static var _grad_glow: GradientTexture2D


static func font() -> Font:
	return UiStyle.kai()


static func brush() -> Font:
	return UiStyle.brush()


static func tex(name: String) -> Texture2D:
	return UiStyle.tex(name)


# ====================================================================
# 样式
# ====================================================================

## 圆角色块（缓存）：bg 底色、line 描边色（透明 = 不描）、w 线宽、r 圆角
static func box(bg: Color, line := Color(0, 0, 0, 0), w := 0.0, r := 12.0, shadow := 0.0) -> StyleBoxFlat:
	var key := "%s|%s|%.1f|%.1f|%.1f" % [bg.to_html(), line.to_html(), w, r, shadow]
	if not _sb.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(int(r))
		s.corner_detail = 6
		s.anti_aliasing = true
		if w > 0.0:
			s.border_color = line
			s.set_border_width_all(int(maxf(roundf(w), 1.0)))
		if shadow > 0.0:
			s.shadow_color = Color(0, 0, 0, 0.35)
			s.shadow_size = int(shadow)
			s.shadow_offset = Vector2(0, 3)
		_sb[key] = s
	return _sb[key]


## 墨玉片：半透明深色圆角片 + 一圈细金线
static func glass(r := 16.0, line_a := 0.3, bg := GLASS) -> StyleBoxFlat:
	return box(bg, Color(GOLD, line_a), 1.5, r, 10.0)


## 自下而上的一抹光（白 → 透明），格子底下的品质色、按钮的高光
static func grad_up() -> GradientTexture2D:
	if _grad_up == null:
		_grad_up = _grad([[0.0, Color(1, 1, 1, 0.0)], [0.55, Color(1, 1, 1, 0.12)], [1.0, Color(1, 1, 1, 0.5)]], Vector2(0.5, 0.0), Vector2(0.5, 1.0), false)
	return _grad_up


## 一团柔光（白 → 透明）
static func grad_glow() -> GradientTexture2D:
	if _grad_glow == null:
		_grad_glow = _grad([[0.0, Color(1, 1, 1, 0.9)], [0.4, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]], Vector2(0.5, 0.5), Vector2(1.0, 0.5), true)
	return _grad_glow


static func _grad(stops: Array, from: Vector2, to: Vector2, radial: bool) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	t.fill_from = from
	t.fill_to = to
	return t


## 一条渐变贴图（界面自己要的各种暗角）
static func grad_tex(stops: Array, from: Vector2, to: Vector2, radial := false) -> GradientTexture2D:
	return _grad(stops, from, to, radial)


## 品阶色（压在深色底上用的亮色）：物品的 tier 0 凡品 … 4 通天灵宝，取 Data.TIER_COLORS
static func q_col(tier: int) -> Color:
	return Data.TIER_COLORS[clampi(tier, 0, Data.TIER_COLORS.size() - 1)]


static func item_col(it: Dictionary) -> Color:
	return q_col(int(it.get("tier", 0)))


## 物品图标：Items.icon_name（丹药 / 破境丹各有一张），没有图就退回种类的通用图，再没有用储物袋
static func icon(it: Dictionary) -> Texture2D:
	var t := UiStyle.icon(Items.icon_name(it))
	if t == null:
		t = UiStyle.icon(str(it.get("kind", "")))
	if t == null:
		t = UiStyle.icon("pouch")
	return t


## 物品种类的名字（法宝 / 丹药 / 破境丹……）
static func kind_name(it: Dictionary) -> String:
	if str(it.get("kind", "")) == "herb" and bool(it.get("fruit", false)):
		return "灵果"
	return str(Items.KIND_NAMES.get(str(it.get("kind", "")), ""))


# ====================================================================
# 战力（只给人看的总分，不参与任何结算）
# ====================================================================

## 2026-11-25 主干解耦：和左上玩家牌 / 一键服丹同一个口径 —— CS.power(境界, 修为等级, 佩戴法宝的被动合计)
static func power(realm: int, lv: int, gear: Array) -> int:
	return int(roundf(CS.power(realm, lv, Items.fx_total(gear))))


## 境界的颜色（Realm.LIST 的主色，压在深色底上提亮一点）
static func realm_col(realm: int) -> Color:
	var c: Color = Realm.LIST[clampi(realm, 0, Realm.LIST.size() - 1)]["col_b"]
	return c.lerp(Color(1, 1, 1), 0.2)


## 整数加千分位（17,683）
static func fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


# ====================================================================
# 小部件
# ====================================================================

static func label(text: String, size: int, col := TEXT, use_brush := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", brush() if use_brush else font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 压在场景上的字：加一圈深色描边
static func outlined(l: Label, w := 6) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.035, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", w)
	return l


static func para(text: String, size: int, width: float, col := TEXT_DIM) -> Label:
	var l := label(text, size, col)
	# 2026-11-25 W5：ARBITRARY 会把「气血 +30%」拆成「+3 / 0%」（手机备战页）。改按词断行：中文照样逐字可断，
	# 数字 / 百分号 / 英文连在一起（入境页 level_select、灵田 farm_plots 早就这么用，网页包上正常）
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_constant_override("line_spacing", 3)
	return l


## 一张线稿图（白 + 透明度）染个颜色
static func art(name: String, size: Vector2, col := GOLD) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = size
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 分隔线：一笔枯墨，正中一朵莲（生图的水墨线稿，保持比例居中；宽出来的地方空着）
static func divider(width: float, col := Color(GOLD, 0.8)) -> TextureRect:
	var h := clampf(width * 0.13, 18.0, 44.0)
	var t := art("meta_divider", Vector2(width, h), col)
	t.custom_minimum_size = Vector2(width, h)      # 放在容器里要占住这么宽
	return t


## 一道长线：两头淡出的细金线，正中三枚小菱形（顶栏底下那道，拉多长都行）
static func rule(width: float, col := Color(GOLD, 0.4)) -> TextureRect:
	var t := art("meta_rule", Vector2(width, 12.0), col)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(width, 12.0)
	return t


## 按钮。kind："primary" 朱砂主按钮 / "gold" 金线按钮 / "ghost" 素按钮（只有一圈淡线）。按下缩一点
static func button(text: String, w: float, h := 64.0, kind := "gold", fs := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", fs)
	style_button(b, kind)
	press_fx(b)
	return b


static func style_button(b: Button, kind: String) -> void:
	var r := 12.0
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", box(CINNABAR, Color(GOLD, 0.55), 1.5, r, 8.0))
			b.add_theme_stylebox_override("hover", box(CINNABAR.lightened(0.1), Color(GOLD, 0.9), 1.5, r, 8.0))
			b.add_theme_stylebox_override("pressed", box(CINNABAR.darkened(0.2), Color(GOLD, 0.9), 1.5, r))
			b.add_theme_stylebox_override("disabled", box(Color(0.3, 0.26, 0.25, 0.7), Color(GOLD, 0.15), 1.5, r))
			for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, Color(1.0, 0.96, 0.88))
		"ghost":
			b.add_theme_stylebox_override("normal", box(Color(0.1, 0.095, 0.11, 0.55), Color(TEXT, 0.18), 1.5, r))
			b.add_theme_stylebox_override("hover", box(Color(0.16, 0.15, 0.17, 0.75), Color(GOLD, 0.6), 1.5, r))
			b.add_theme_stylebox_override("pressed", box(Color(0.2, 0.18, 0.2, 0.9), Color(GOLD, 0.8), 1.5, r))
			b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.095, 0.11, 0.3), Color(TEXT, 0.08), 1.5, r))
			for k: String in ["font_color", "font_focus_color"]:
				b.add_theme_color_override(k, TEXT_DIM)
			for k: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, GOLD)
		_:
			b.add_theme_stylebox_override("normal", box(Color(0.12, 0.11, 0.12, 0.88), Color(GOLD, 0.55), 1.5, r, 8.0))
			b.add_theme_stylebox_override("hover", box(Color(0.2, 0.18, 0.17, 0.94), Color(GOLD, 0.95), 1.5, r, 8.0))
			b.add_theme_stylebox_override("pressed", box(Color(0.26, 0.22, 0.18, 0.96), GOLD, 1.5, r))
			b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.095, 0.11, 0.4), Color(GOLD, 0.12), 1.5, r))
			for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, GOLD.lightened(0.25))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_disabled_color", Color(TEXT_FAINT, 0.6))


## 分段页签（背包 / 仓库、商店的分类）：选中 = 金线 + 亮字，没选中 = 淡
static func tab(text: String, w: float, h := 58.0, fs := 25) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", fs)
	var r := 10.0
	b.add_theme_stylebox_override("normal", box(Color(0.1, 0.095, 0.11, 0.5), Color(TEXT, 0.12), 1.5, r))
	b.add_theme_stylebox_override("hover", box(Color(0.16, 0.15, 0.17, 0.7), Color(GOLD, 0.5), 1.5, r))
	b.add_theme_stylebox_override("pressed", box(Color(0.24, 0.2, 0.15, 0.92), GOLD, 2.0, r, 6.0))
	b.add_theme_stylebox_override("hover_pressed", box(Color(0.24, 0.2, 0.15, 0.92), GOLD, 2.0, r, 6.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	for k: String in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, GOLD.lightened(0.3))
	press_fx(b)
	return b


## 一小枚标签（品质 / 种类 / 冷却）：淡底 + 细线
static func tag(text: String, col: Color, fs := 20) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col, 0.14)
	s.border_color = Color(col, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, fs, col.lightened(0.25)))
	return p


## 货币小牌：图标 + 数。返回 [整块, 数字 Label]
static func money(icon_name: String, col := GOLD) -> Array:
	var p := PanelContainer.new()
	var s := box(Color(0.07, 0.065, 0.08, 0.72), Color(col, 0.4), 1.5, 24.0).duplicate() as StyleBoxFlat
	s.content_margin_left = 12.0
	s.content_margin_right = 20.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := TextureRect.new()
	ic.texture = UiStyle.icon(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(36, 36)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var l := label("", 26, col.lightened(0.3))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return [p, l]


## 圆片按钮：深色圆片 + 一圈金线 + 正中一张线稿图标（返回 / 主城入口）。label 非空 = 底下压一行小字
static func round_button(icon_name: String, d := 84.0, text := "") -> Button:
	var b := Button.new()
	var hh := d + (30.0 if text != "" else 0.0)
	b.custom_minimum_size = Vector2(d, hh)
	b.size = Vector2(d, hh)
	b.focus_mode = Control.FOCUS_NONE
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.draw.connect(func() -> void:
		var mode := b.get_draw_mode()
		var down := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var hot := mode == BaseButton.DRAW_HOVER
		var c := Vector2(d * 0.5, d * 0.5)
		var r := d * 0.5 - 3.0
		b.draw_circle(c + Vector2(0, 3), r + 1.0, Color(0, 0, 0, 0.3), true, -1.0, true)
		b.draw_circle(c, r, Color(0.3, 0.2, 0.14, 0.95) if down else Color(0.09, 0.085, 0.1, 0.9 if hot else 0.8), true, -1.0, true)
		b.draw_arc(c, r, 0.0, TAU, 56, Color(GOLD, 1.0 if hot or down else 0.75), 2.0, true)
		b.draw_arc(c, r - 5.0, 0.0, TAU, 56, Color(GOLD, 0.22), 1.0, true)
		var ic := tex(icon_name)
		if ic != null:
			var s := d * 0.66
			b.draw_texture_rect(ic, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, GOLD.lightened(0.35 if hot or down else 0.12))
		if text != "":
			var f := font()
			var fs := 20
			var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p := Vector2(c.x - ts.x * 0.5, d + 3.0 + f.get_ascent(fs))
			b.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.04, 0.035, 0.04, 0.9))
			b.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT if not hot else GOLD.lightened(0.3)))
	press_fx(b)
	return b


# ====================================================================
# 动画（界面开着时树是暂停的：补间都设成暂停时照走）
# ====================================================================

static func tween(n: Node) -> Tween:
	return n.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


## 按下缩一点、松开弹回
static func press_fx(b: BaseButton) -> void:
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		tween(b).tween_property(b, "scale", Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		tween(b).tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## 弹一下（选中 / 到账）
static func pop(c: Control, k := 1.12) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(k, k)
	tween(c).tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 从偏移 off 处滑到原位并淡入（进场）。位置由调用方先摆好；容器里的孩子别用（容器会把位置改回去），用 fade_in
static func slide_in(c: Control, off: Vector2, delay := 0.0, dur := 0.32) -> void:
	var to := c.position
	c.position = to + off
	c.modulate.a = 0.0
	var t := tween(c)
	t.set_parallel(true)
	t.tween_property(c, "position", to, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, dur * 0.8).set_delay(delay)


static func fade_in(c: CanvasItem, delay := 0.0, dur := 0.22) -> void:
	c.modulate.a = 0.0
	tween(c).tween_property(c, "modulate:a", 1.0, dur).set_delay(delay)


## 一格格冒出来（格子 / 列表项）：从 0.6 倍放大到原样，一个接一个
static func cascade(items: Array, step := 0.018, delay := 0.0) -> void:
	var i := 0
	for it: Variant in items:
		var c := it as Control
		if c == null:
			continue
		c.pivot_offset = c.custom_minimum_size * 0.5
		c.scale = Vector2(0.6, 0.6)
		c.modulate.a = 0.0
		var d := delay + minf(float(i) * step, 0.42)
		var t := tween(c)
		t.set_parallel(true)
		t.tween_property(c, "scale", Vector2.ONE, 0.2).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(d)
		i += 1


## 数字滚到新值（灵石）：fmt 把数变成字
static func roll(l: Label, from: float, to: float, fmt: Callable, dur := 0.45) -> void:
	if is_equal_approx(from, to):
		l.text = str(fmt.call(to))
		return
	tween(l).tween_method(func(v: float) -> void: l.text = str(fmt.call(v)), from, to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pop(l, 1.18)


# ====================================================================
# 段位徽记（现画的矢量图，会慢慢转）
# ====================================================================

## 段位 → [档（0 未入流 … 5 化神）, 阶（0 三阶 / 1 二阶 / 2 一阶；没有阶的是 -1）]
static func rank_tier(rank: int) -> Array:
	if rank <= 0:
		return [0, -1]
	if rank >= 13:
		return [5, -1]
	return [(rank - 1) / 3 + 1, (rank - 1) % 3]


static func tier_col(rank: int) -> Color:
	return TIER_COL[int(rank_tier(rank)[0])]


## 在 ci 上画一枚段位徽记：圆心 c、半径 r；t = 时间（里面的花慢慢转）；dim = 还没到的段位（压暗）
static func draw_crest(ci: CanvasItem, c: Vector2, r: float, rank: int, t := 0.0, dim := false) -> void:
	var tr := rank_tier(rank)
	var tier := int(tr[0])
	var step := int(tr[1])
	var col: Color = TIER_COL[tier]
	if dim:
		col = Color(col.lerp(Color(0.4, 0.39, 0.38), 0.7), 0.7)
	var lw := maxf(r * 0.045, 1.5)
	ci.draw_circle(c, r, Color(0.07, 0.065, 0.08, 0.92), true, -1.0, true)
	ci.draw_arc(c, r, 0.0, TAU, 72, col, lw, true)
	ci.draw_arc(c, r * 0.86, 0.0, TAU, 72, Color(col, 0.35), maxf(lw * 0.5, 1.0), true)
	var rot := t * 0.25
	var emblem := tex("meta_crest_%d" % tier)
	if emblem != null:
		var es := r * (1.36 + 0.02 * sin(t * 1.6))
		ci.draw_texture_rect(emblem, Rect2(c - Vector2(es, es) * 0.5, Vector2(es, es)), false, col.lightened(0.15))
		tier = -1          # 下面的矢量图不画了
	match tier:
		-1:
			pass
		0:
			ci.draw_circle(c, r * 0.16, Color(col, 0.8), true, -1.0, true)
		1:
			# 炼气：三缕气旋
			for i in 3:
				var a0 := rot + TAU * float(i) / 3.0
				var pts := PackedVector2Array()
				for k in 13:
					var u := float(k) / 12.0
					pts.append(c + Vector2.from_angle(a0 + u * 2.6) * r * lerpf(0.14, 0.66, u))
				ci.draw_polyline(pts, col, lw * 1.2, true)
			ci.draw_circle(c, r * 0.1, col, true, -1.0, true)
		2:
			# 筑基：六角台基 + 里面一个倒三角
			var hex := PackedVector2Array()
			for i in 7:
				hex.append(c + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 6.0) * r * 0.66)
			ci.draw_polyline(hex, col, lw * 1.2, true)
			var tri := PackedVector2Array()
			for i in 4:
				tri.append(c + Vector2.from_angle(rot + TAU * float(i) / 3.0) * r * 0.4)
			ci.draw_polyline(tri, Color(col, 0.85), lw, true)
			ci.draw_circle(c, r * 0.09, col, true, -1.0, true)
		3:
			# 结丹：一颗丹 + 十二道光
			for i in 12:
				var d := Vector2.from_angle(rot + TAU * float(i) / 12.0)
				ci.draw_line(c + d * r * 0.42, c + d * r * (0.7 if i % 2 == 0 else 0.58), col, lw, true)
			ci.draw_circle(c, r * 0.3, col, true, -1.0, true)
			ci.draw_circle(c - Vector2(r, r) * 0.08, r * 0.09, Color(1, 1, 1, 0.5 if not dim else 0.15), true, -1.0, true)
		4:
			# 元婴：八瓣莲 + 莲心
			_lotus(ci, c, r * 0.7, 8, rot, col, lw)
			ci.draw_circle(c, r * 0.16, col, true, -1.0, true)
		_:
			# 化神：十六道光 + 莲 + 双环
			for i in 16:
				var d2 := Vector2.from_angle(-rot + TAU * float(i) / 16.0)
				ci.draw_line(c + d2 * r * 0.58, c + d2 * r * (0.8 if i % 2 == 0 else 0.7), col, lw, true)
			_lotus(ci, c, r * 0.54, 8, rot, col, lw)
			ci.draw_arc(c, r * 0.2, 0.0, TAU, 32, col, lw, true)
			ci.draw_circle(c, r * 0.1, col, true, -1.0, true)
	# 阶：底下几粒（三阶一粒、一阶三粒）
	if step >= 0:
		var n := step + 1
		for i in n:
			var p := c + Vector2((float(i) - float(n - 1) * 0.5) * r * 0.24, r * 1.0)
			ci.draw_circle(p, r * 0.085, Color(0.07, 0.065, 0.08), true, -1.0, true)
			ci.draw_circle(p, r * 0.06, col, true, -1.0, true)


## 境界徽记（2026-11-25「段位」页改成「境界」）：realm 0 炼气 … 7 大乘，图样借老段位的六枚（炼虚往上共用化神那枚、颜色按境界），
## step = 这一境里第几级（0..2，底下几粒；-1 不画）
static func draw_realm_crest(ci: CanvasItem, c: Vector2, r: float, realm: int, step := -1, t := 0.0, dim := false) -> void:
	var col := realm_col(realm)
	if dim:
		col = Color(col.lerp(Color(0.4, 0.39, 0.38), 0.7), 0.7)
	var lw := maxf(r * 0.045, 1.5)
	ci.draw_circle(c, r, Color(0.07, 0.065, 0.08, 0.92), true, -1.0, true)
	ci.draw_arc(c, r, 0.0, TAU, 72, col, lw, true)
	ci.draw_arc(c, r * 0.86, 0.0, TAU, 72, Color(col, 0.35), maxf(lw * 0.5, 1.0), true)
	if realm >= 5:
		ci.draw_arc(c, r * 0.93, 0.0, TAU, 72, Color(col, 0.55), maxf(lw * 0.6, 1.0), true)      # 炼虚往上多一道环
	var emblem := tex("meta_crest_%d" % clampi(realm + 1, 1, 5))
	if emblem != null:
		var es := r * (1.36 + 0.02 * sin(t * 1.6))
		ci.draw_texture_rect(emblem, Rect2(c - Vector2(es, es) * 0.5, Vector2(es, es)), false, col.lightened(0.15))
	else:
		_lotus(ci, c, r * 0.7, 8, t * 0.25, col, lw)
		ci.draw_circle(c, r * 0.16, col, true, -1.0, true)
	if step >= 0:
		var n := step + 1
		for i in n:
			var p := c + Vector2((float(i) - float(n - 1) * 0.5) * r * 0.24, r * 1.0)
			ci.draw_circle(p, r * 0.085, Color(0.07, 0.065, 0.08), true, -1.0, true)
			ci.draw_circle(p, r * 0.06, col, true, -1.0, true)


static func _lotus(ci: CanvasItem, c: Vector2, r: float, n: int, rot: float, col: Color, lw: float) -> void:
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		var tip := c + Vector2.from_angle(a) * r
		var side := Vector2.from_angle(a + PI * 0.5) * r * 0.24
		var mid := c + Vector2.from_angle(a) * r * 0.5
		var pts := PackedVector2Array([c + Vector2.from_angle(a) * r * 0.2, mid + side, tip, mid - side, c + Vector2.from_angle(a) * r * 0.2])
		ci.draw_polyline(pts, col, lw, true)


# ====================================================================
# 物品格子
# ====================================================================

## 深色石片格子：底下一抹品质色、一圈品质色细线，大图标 + 一行名字；选中 = 金线 + 四角；可以带一行价钱
class Tile:
	extends Button
	var item := {}
	var selected := false
	var note := ""              # 名字下面多一行（价钱 / 值多少）
	var note_col := Color(0.9, 0.76, 0.46)
	var empty_text := ""        # 空格子正中的淡字（装备栏：兵 / 冠 / 衣……）
	var empty_icon: Texture2D   # 空格子正中的水墨淡影（装备栏那一格是什么；有它就不写字）
	var corner := ""            # 右上角小字；空 = 自动（叠了几个 / 装备的品质）
	var faded := false          # 不合筛选条件：压暗
	var show_name := true
	var _t := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(k, StyleBoxEmpty.new())

	func _ready() -> void:
		set_process(false)
		button_down.connect(func() -> void:
			pivot_offset = size * 0.5
			create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(self, "scale", Vector2(0.93, 0.93), 0.05))
		button_up.connect(func() -> void:
			pivot_offset = size * 0.5
			create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func set_selected(v: bool) -> void:
		if v == selected:
			return
		selected = v
		queue_redraw()

	func _draw() -> void:
		var kit: GDScript = load("res://scripts/ex/meta_kit.gd")
		var r := Rect2(Vector2.ZERO, size)
		var mode := get_draw_mode()
		var hot := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED
		var f: Font = kit.call("font")
		if item.is_empty():
			draw_style_box(kit.call("box", Color(0.1, 0.095, 0.11, 0.42), Color(0.95, 0.92, 0.85, 0.3 if selected or hot else 0.11), 1.5, 12.0), r)
			if empty_icon != null:
				var es := minf(size.x, size.y) * 0.66
				draw_texture_rect(empty_icon, Rect2((size - Vector2(es, es)) * 0.5, Vector2(es, es)), false, Color(0.95, 0.9, 0.78, 0.34 if hot else 0.2))
			elif empty_text != "":
				var fs0 := int(minf(size.x, size.y) * 0.3)
				var bf: Font = kit.call("brush")
				var ts0 := bf.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0)
				draw_string(bf, Vector2((size.x - ts0.x) * 0.5, size.y * 0.5 + bf.get_ascent(fs0) - bf.get_height(fs0) * 0.5), empty_text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, Color(0.95, 0.92, 0.85, 0.2))
			return
		var q := int(item.get("tier", 0)) + 1      # 品阶 0..4 → 1..5（下面的浓淡按它走）
		var qc: Color = kit.call("q_col", q - 1)
		var a := 0.45 if faded else 1.0
		draw_style_box(kit.call("box", Color(0.14, 0.135, 0.15, 0.95 * a), Color(0, 0, 0, 0), 0.0, 12.0), r)
		draw_texture_rect(kit.call("grad_up"), r.grow(-2.0), false, Color(qc, (0.3 + 0.07 * float(mini(q, 6))) * a))
		# 图标
		var name_h := 30.0 if show_name else 0.0
		var note_h := 28.0 if note != "" else 0.0
		var room := size.y - name_h - note_h - 14.0
		var ic_s := clampf(minf(size.x - 26.0, room), 24.0, 112.0)
		var ic: Texture2D = kit.call("icon", item)
		if ic != null:
			draw_texture_rect(ic, Rect2((size.x - ic_s) * 0.5, 8.0 + (room - ic_s) * 0.5, ic_s, ic_s), false, Color(1, 1, 1, a))
		# 名字
		if show_name:
			var fs := 21 if size.x < 150.0 else 23
			var nm := str(item.get("name", ""))
			var ts := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			while ts.x > size.x - 10.0 and nm.length() > 2:
				nm = nm.left(nm.length() - 1)
				ts = f.get_string_size(nm + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			if nm != str(item.get("name", "")):
				nm += "…"
			var ny := size.y - note_h - name_h - 3.0
			draw_string(f, Vector2((size.x - ts.x) * 0.5, ny + name_h * 0.5 + f.get_ascent(fs) - f.get_height(fs) * 0.5), nm,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(qc.lightened(0.18), a))
		if note != "":
			var ns := 20
			var nts := f.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, ns)
			draw_string(f, Vector2((size.x - nts.x) * 0.5, size.y - note_h * 0.5 - 4.0 + f.get_ascent(ns) - f.get_height(ns) * 0.5), note,
					HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color(note_col, a))
		# 右上角：叠了几个 / 品质
		var cn := corner
		var cn_col := Color(0.95, 0.92, 0.85)
		if cn == "":
			if int(item.get("n", 1)) > 1:
				cn = "×%d" % int(item.get("n", 1))
			elif str(item.get("kind", "")) == "gear":
				cn = Items.tier_word(item)
				cn_col = qc.lightened(0.2)
		if cn != "":
			var cs := 18
			var cts := f.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, cs)
			var cp := Vector2(size.x - cts.x - 8.0, 6.0 + f.get_ascent(cs))
			draw_string_outline(f, cp, cn, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 4, Color(0.05, 0.045, 0.05, 0.85 * a))
			draw_string(f, cp, cn, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(cn_col, a))
		# 描边：品阶色；选中 = 金线 + 外面一圈光
		var line := qc
		if selected:
			draw_style_box(kit.call("box", Color(0, 0, 0, 0), Color(1.0, 0.9, 0.62), 3.0, 12.0), r)
			draw_style_box(kit.call("box", Color(0, 0, 0, 0), Color(1.0, 0.9, 0.62, 0.28), 2.0, 15.0), r.grow(4.0))
		else:
			draw_style_box(kit.call("box", Color(0, 0, 0, 0), Color(line, (0.5 + 0.08 * float(mini(q, 6))) * a if not hot else 1.0), 2.0 if q >= 4 else 1.5, 12.0), r)


## 建一格。size 写进 custom_minimum_size
static func tile(it: Dictionary, size: Vector2, selected := false, note := "", empty_text := "") -> Tile:
	var t := Tile.new()
	t.item = it
	t.selected = selected
	t.note = note
	t.empty_text = empty_text
	t.custom_minimum_size = size
	t.size = size
	return t
