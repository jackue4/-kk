extends RefCounted
## 「墨玉」样式：和 ui_style.gd（宣纸纸片）同一套接口、另一身皮 —— 半透明的深色圆角片 + 细金线，字是暖白，朱砂 / 青玉点色。
## 2026-11-24 用户：「现在游戏的整体的ui都不够艺术……通用的ui背景元素很丑」「不只是局外的ui系统，局内的UI系统也都要重构，
## 玩家血条，拾取卡片等这些所有用到ui的地方」。局外那几张全屏页（scripts/ex/meta_*.gd）用的是 meta_kit.gd；局内的界面
## （玩家牌 / 技能框 / 触屏按钮 / 小地图 / ex_hud.gd 的计时牌、拾取卡片、储物袋、读条、重伤、结算……）原来都从 ui_style.gd 取样式，
## 结构和文字别的会话还在改、自检也按它们找按钮 —— 所以做法是「换皮不换骨」：这些脚本顶上的
##     const UiStyle := preload("res://scripts/ui_style.gd")   改成   preload("res://scripts/ink_style.gd")
## 其余一行不用动，面板 / 按钮 / 格子 / 条框就都换成这一套了。名字、参数和 ui_style.gd 一一对应（返回的是 StyleBoxFlat，不是纸片样式）。
## 换过来之后要留意的只有两种地方：
##   · 原来把 PAPER 当「纸色底面」画的（圆片、小方块）：这里 PAPER 仍是亮色（当字色用：朱砂块上的字），底面改用 SURF
##   · 原来用 ExData.q_ink（压暗了的品质墨色，给纸面用的）写字的：深色底上要用本色 ExData.q_color
## 字体 / 贴图 / 朱印照旧走 ui_style.gd。故意不写 class_name：用 preload 引用。

const Base := preload("res://scripts/ui_style.gd")

const INK := Color(0.055, 0.05, 0.06)
const SURF := Color(0.09, 0.085, 0.1)            # 深色底面（原来画成纸色的圆片 / 小方块）
const SURF_HI := Color(0.17, 0.16, 0.18)
const PAPER := Color(0.96, 0.93, 0.86)           # 亮色（压在朱砂 / 深色块上的字）
const PAPER_DARK := Color(0.8, 0.76, 0.68)
const GOLD := Color(0.9, 0.76, 0.46)
const GOLD_DIM := Color(0.62, 0.52, 0.33)
const CINNABAR := Color(0.86, 0.28, 0.2)
const JADE := Color(0.47, 0.82, 0.7)
const QING := Color(0.4, 0.8, 0.72)              # 进度（修为 / 读条）：深色底上用亮的青
const INDIGO := Color(0.4, 0.64, 0.98)           # 灵力
const TEXT := Color(0.96, 0.93, 0.85)
const TEXT_INK := Color(0.95, 0.92, 0.85)        # 面板上的字（原来是墨色）
const TEXT_SOFT := Color(0.74, 0.7, 0.63)        # 面板上的次要文字
const LINE := Color(0.86, 0.72, 0.44)            # 线（原来是墨线，现在是金线）
const SELECT := Color(1.0, 0.9, 0.62)            # 选中的描边

const TINT_PLAIN := Color(1.0, 1.0, 1.0)
const TINT_BTN := Color(0.945, 0.92, 0.865)
const TINT_PRESS := Color(0.87, 0.84, 0.78)
const TINT_TRACK := Color(0.9, 0.87, 0.8)
const TINT_CINNABAR := Color(0.8, 0.25, 0.19)

const CORNER_BTN := 100.0
const UI_DIR := "res://assets/ui/"
const BODY_FILE := "res://assets/fonts/NotoSansSC-Medium.subset.otf"
const TITLE_FILE := "res://assets/fonts/SourceHanSerifSC-Heavy.subset.ttf"
const PATCH_FILE := "res://assets/fonts/SourceHanSansCN-Normal.patch.ttf"


## 调试：在 Windows 上也用随包字体（和 ui_style.gd 的同名开关是同一个，读写都落到那边）
static var force_bundled: bool:
	get:
		return Base.force_bundled
	set(v):
		Base.force_bundled = v


static func system_fonts() -> bool:
	return Base.system_fonts()


static func bundled(path: String) -> Font:
	return Base.bundled(path)


static func kai() -> Font:
	return Base.kai()


static func brush() -> Font:
	return Base.brush()


static func tex(name: String) -> Texture2D:
	return Base.tex(name)


static func icon(kind: String) -> Texture2D:
	return Base.icon(kind)


## 一块圆角色片（每次给新的：调用方可能再改边距）
static func _flat(bg: Color, line: Color, w: float, r: float, shadow := 0.0, margin := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(r))
	s.corner_detail = 5
	s.anti_aliasing = true
	if w > 0.0 and line.a > 0.0:
		s.border_color = line
		s.set_border_width_all(int(maxf(roundf(w), 1.0)))
	if shadow > 0.0:
		s.shadow_color = Color(0, 0, 0, 0.34)
		s.shadow_size = int(shadow)
		s.shadow_offset = Vector2(0, 3)
	s.set_content_margin_all(margin)
	return s


## 压在场景上的小牌（信息栏、提示、技能格）：半透明深色片、一圈细金线
static func plaque(alpha := 0.96, _border := 1, margin := 10.0) -> StyleBoxFlat:
	return _flat(Color(SURF, 0.84 * clampf(alpha, 0.0, 1.0)), Color(GOLD, 0.42), 1.5, 10.0, 8.0, margin)


## 大面板（储物袋 / 入境 / 结算）：更实的深色片、金线，四角圆一点。mountain 留着只是为了接口一致（不画远山）
static func scroll(margin := 26.0, _mountain := true) -> StyleBoxFlat:
	return _flat(Color(0.075, 0.07, 0.085, 0.95), Color(GOLD, 0.55), 1.5, 18.0, 16.0, margin + 10.0)


## 条的外框：深色槽 + 细金线，线画在填充条的外面
static func bar_frame() -> StyleBoxFlat:
	var s := _flat(Color(0.03, 0.03, 0.04, 0.82), Color(GOLD, 0.5), 1.5, 5.0)
	s.set_expand_margin_all(3.0)
	return s


## 背包格：深色石片；empty = 空格（更淡）；hot = 悬停 / 选中（金线）
static func slot(empty := false, hot := false) -> StyleBoxFlat:
	var bg := Color(0.1, 0.095, 0.11, 0.42) if empty else Color(0.14, 0.135, 0.15, 0.95)
	var line := Color(SELECT, 0.95) if hot else (Color(TEXT, 0.1) if empty else Color(GOLD, 0.26))
	return _flat(bg, line, 2.0 if hot else 1.5, 10.0, 0.0, 8.0)


## 只有一圈线、没有底（选中 / 键盘焦点）。col 不给 = 选中用的亮金
static func outline(col := SELECT) -> StyleBoxFlat:
	return _flat(Color(0, 0, 0, 0), col, 3.0, 10.0)


## 按钮：深色片 + 金线、金字；悬停 / 按下变亮。on_paper 留着只是为了接口一致
static func style_button(b: Button, _on_paper := false) -> void:
	b.add_theme_font_override("font", kai())
	b.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.11, 0.12, 0.9), Color(GOLD, 0.55), 1.5, 12.0, 6.0, 10.0))
	b.add_theme_stylebox_override("hover", _flat(Color(0.2, 0.18, 0.17, 0.95), Color(GOLD, 0.95), 1.5, 12.0, 6.0, 10.0))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.27, 0.22, 0.17, 0.97), GOLD, 2.0, 12.0, 0.0, 10.0))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(0.27, 0.22, 0.17, 0.97), GOLD, 2.0, 12.0, 0.0, 10.0))
	b.add_theme_stylebox_override("disabled", _flat(Color(0.1, 0.095, 0.11, 0.45), Color(GOLD, 0.14), 1.5, 12.0, 0.0, 10.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var gold := GOLD.lightened(0.25)
	for k: String in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(k, gold)
	for k: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, PAPER)
	b.add_theme_color_override("font_disabled_color", Color(TEXT_SOFT, 0.5))


## 主按钮（开始匹配 / 使用 / 回主城）：朱砂片、金线、亮字
static func style_primary(b: Button) -> void:
	b.add_theme_font_override("font", brush())
	b.add_theme_stylebox_override("normal", _flat(CINNABAR, Color(GOLD, 0.6), 1.5, 12.0, 8.0, 10.0))
	b.add_theme_stylebox_override("hover", _flat(CINNABAR.lightened(0.1), Color(GOLD, 0.95), 1.5, 12.0, 8.0, 10.0))
	b.add_theme_stylebox_override("pressed", _flat(CINNABAR.darkened(0.2), GOLD, 1.5, 12.0, 0.0, 10.0))
	b.add_theme_stylebox_override("disabled", _flat(Color(0.3, 0.26, 0.25, 0.7), Color(GOLD, 0.15), 1.5, 12.0, 0.0, 10.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color(1.0, 0.96, 0.88))
	b.add_theme_color_override("font_disabled_color", Color(TEXT_SOFT, 0.55))


## 圆片按钮：深色圆片 + 一圈金线 + 正中一个图标；按下变朱砂。底边可以压一枚小签：
## b.set_meta("badge", "3/12") 之后 queue_redraw；"badge_hot" 为真时签上的字变朱砂（背包满了）
static func round_icon_button(icon_kind: String, d := CORNER_BTN) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.draw.connect(func() -> void: _draw_round_button(b, icon_kind))
	return b


static func corner_pos(vs: Vector2) -> Vector2:
	return Vector2(vs.x - CORNER_BTN - 14.0, 8.0)


static func _draw_round_button(b: Button, icon_kind: String) -> void:
	var mode := b.get_draw_mode()
	var down := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var hot := mode == BaseButton.DRAW_HOVER
	var c := b.size * 0.5
	var r := minf(b.size.x, b.size.y) * 0.5 - 4.0
	b.draw_circle(c + Vector2(0, 3), r + 1.0, Color(0, 0, 0, 0.3), true, -1.0, true)
	b.draw_circle(c, r, Color(CINNABAR.darkened(0.25), 0.95) if down else Color(SURF, 0.92 if hot else 0.82), true, -1.0, true)
	b.draw_arc(c, r, 0.0, TAU, 56, Color(GOLD, 1.0 if hot or down else 0.75), 2.0, true)
	b.draw_arc(c, r - 5.0, 0.0, TAU, 56, Color(GOLD, 0.2), 1.0, true)
	var ic := icon(icon_kind)
	if ic != null:
		var s := r * 1.24
		var lift := r * 0.14 if b.has_meta("badge") else 0.0      # 底下压着小签时图标往上让一点
		b.draw_texture_rect(ic, Rect2(c - Vector2(s, s) * 0.5 - Vector2(0.0, lift), Vector2(s, s)), false)
	var badge := str(b.get_meta("badge", ""))
	if badge != "":
		var f := kai()
		var fs := 15
		var ts := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var box := Rect2(roundf(c.x - ts.x * 0.5 - 8.0), roundf(c.y + r * 0.66), roundf(ts.x + 16.0), 22.0)
		b.draw_style_box(_flat(Color(0.05, 0.045, 0.055, 0.95), Color(GOLD, 0.6), 1.0, 8.0), box)
		b.draw_string(f, Vector2(box.position.x + 8.0, box.position.y + 11.0 + f.get_ascent(fs) - f.get_height(fs) * 0.5), badge,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CINNABAR.lightened(0.2) if bool(b.get_meta("badge_hot", false)) else TEXT)


## 一张不挡点击的装饰图（白 + 透明度的那几张），染成 col（不给 = 金线色）
static func deco(name: String, size: Vector2, col := LINE) -> TextureRect:
	return Base.deco(name, size, col)


## 标题下面的一笔（金色的枯笔）
static func rule(width := 320.0, height := 9.0, col := LINE) -> TextureRect:
	return Base.deco("stroke", Vector2(width, height), col)


## 朱砂印：红底上一个亮色的字
static func seal(text: String, size := 44.0, col := CINNABAR) -> Control:
	return Base.seal(text, size, col)


## 原来是「品阶色在宣纸上太浅：压深一点」；深色底上本色就够亮，原样返回
static func on_paper(c: Color) -> Color:
	return c
