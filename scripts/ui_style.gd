extends RefCounted
## 全游戏界面的修仙风格：素净的宣纸面 + 细墨线，点一点朱砂和石青；正文用楷体、题字用行楷。
## 面板 / 按钮 / 背包格 / 条框都是「纸片」（ui_paper_box.gd）：共用一张宣纸底纹，上面压一圈细墨线。
## 各界面（hud.gd / raid_hud.gd / level_select.gd / touch_controls.gd …）都从这里取颜色、字体、样式和装饰图，别各写各的。
## 素材在 assets/ui/（由 _tasks/ui_kit/make_ui.py 从生图服务出的原图加工而来，说明见那个脚本）。
## 字体取系统里的楷体 / 行楷（Windows 自带）；找不到时退回黑体。手机包里要另外带一套可分发的字体。
## 故意不写 class_name：用 preload 引用。

const PaperBox := preload("res://scripts/ui_paper_box.gd")

const INK := Color(0.07, 0.06, 0.055)
const PAPER := Color(0.957, 0.933, 0.875)        # 和宣纸底纹的平均色一致
const PAPER_DARK := Color(0.87, 0.83, 0.74)
const GOLD := Color(0.86, 0.71, 0.40)
const GOLD_DIM := Color(0.56, 0.45, 0.25)
const CINNABAR := Color(0.74, 0.19, 0.14)        # 朱砂
const JADE := Color(0.45, 0.80, 0.68)            # 青玉（压在场景上的亮色：队友、提示）
const QING := Color(0.20, 0.46, 0.44)            # 石青（纸面上的进度：修为、读条）
const INDIGO := Color(0.19, 0.35, 0.58)          # 靛蓝（纸面上的灵力）
const TEXT := Color(0.96, 0.93, 0.85)            # 直接压在场景上的字（配深色描边）
const TEXT_INK := Color(0.13, 0.11, 0.10)        # 纸面上的字
const TEXT_SOFT := Color(0.40, 0.34, 0.28)       # 纸面上的次要文字
const LINE := Color(0.17, 0.14, 0.12)            # 墨线

## 宣纸底纹的几种染色（底纹本身就是纸色，这里是乘上去的）
const TINT_PLAIN := Color(1.0, 1.0, 1.0)
const TINT_BTN := Color(0.945, 0.92, 0.865)
const TINT_PRESS := Color(0.87, 0.84, 0.78)
const TINT_TRACK := Color(0.90, 0.87, 0.80)
const TINT_CINNABAR := Color(0.80, 0.25, 0.19)

const CORNER_BTN := 100.0                        # 主界面右上角那颗圆按钮（背包 / 洞府）的边长
const UI_DIR := "res://assets/ui/"
const BRUSH_FILES := ["C:/Windows/Fonts/STXINGKA.TTF", "C:/Windows/Fonts/FZSTK.TTF", "C:/Windows/Fonts/STKAITI.TTF", "C:/Windows/Fonts/simkai.ttf"]

## 随包带的开源字体（SIL OFL 1.1，已按游戏里用到的字裁剪，见 assets/fonts/）：网页 / 手机上没有系统楷体，用这两个
const BODY_FILE := "res://assets/fonts/NotoSansSC-Medium.subset.otf"
const TITLE_FILE := "res://assets/fonts/SourceHanSerifSC-Heavy.subset.ttf"
const PATCH_FILE := "res://assets/fonts/SourceHanSansCN-Normal.patch.ttf"   # 上面两款里都没有的字（Apache 2.0）

static var _kai: Font
static var _brush: Font
static var _tex := {}
## 调试：在 Windows 上也用随包字体（预览网页 / 手机上的字形和行高；小样页加 --web-fonts）
static var force_bundled := false


## 这台设备上能不能用系统字体（只有 Windows 桌面版走系统楷体）
static func system_fonts() -> bool:
	return OS.has_feature("windows") and not force_bundled


## 随包字体是按用字裁剪的：题字字体里没有的字（标点居多）落到正文字体上，两边都没有的落到补字字体上，
## 不然网页 / 手机上就是一个个方块。补字字体由 _tasks/ui_kit/font_check.py 生成（改了界面文字、导出前跑一遍）。
static func bundled(path: String) -> Font:
	var f := load(path) as Font if ResourceLoader.exists(path) else null
	if f == null or not f.fallbacks.is_empty():
		return f
	# 后备链只有一个方向：题字 → 正文 → 补字（补字字体自己没有后备，不然就绕回来了）
	var back := ""
	if path == TITLE_FILE:
		back = BODY_FILE
	elif path == BODY_FILE:
		back = PATCH_FILE
	if back != "":
		var fb := bundled(back)
		if fb != null:
			var chain: Array[Font] = [fb]
			f.fallbacks = chain
	return f


## 正文：楷体
static func kai() -> Font:
	if _kai == null and not system_fonts():
		_kai = bundled(BODY_FILE)
		if _brush == null:
			_brush = bundled(TITLE_FILE)   # 顺手把题字字体的后备也挂上（realm_banner.gd 自己 load 的是同一份资源）
	if _kai == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["KaiTi", "STKaiti", "Kaiti SC", "AR PL UKai CN", "Noto Serif CJK SC", "Microsoft YaHei", "PingFang SC", "SimHei"])
		f.font_weight = 500
		_kai = f
	return _kai


## 题字：行楷 / 舒体
static func brush() -> Font:
	if _brush == null and not system_fonts():
		_brush = bundled(TITLE_FILE)
	if _brush == null:
		for p: String in BRUSH_FILES:
			if FileAccess.file_exists(p):
				var ff := FontFile.new()
				if ff.load_dynamic_font(p) == OK:
					_brush = ff
					break
		if _brush == null:
			_brush = kai()
	return _brush


## assets/ui/ 里的一张图（只读一次）。新加的图还没被编辑器导入时（直接从命令行起的游戏）退回去读文件本身。
static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var path := UI_DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null and not OS.has_feature("web"):
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				t = ImageTexture.create_from_image(img)
	_tex[name] = t
	return t


## 道具图标：丹药 pill / 装备 gear / 材料 mat / 储物袋 pouch
static func icon(kind: String) -> Texture2D:
	return tex("icon_" + kind)


static func _box(frame_name: String, frame_m: Vector2, margin: float, tint := TINT_PLAIN, line := LINE) -> PaperBox:
	var sb := PaperBox.new()
	sb.paper = tex("paper")
	sb.paper_col = tint
	if frame_name != "":
		sb.frame = tex(frame_name)
		sb.frame_m = frame_m
		sb.frame_col = line
	sb.set_content_margin_all(margin)
	return sb


static func _shadow(sb: PaperBox, a: float) -> PaperBox:
	sb.shadow = tex("shadow")
	sb.shadow_a = a
	return sb


## 压在场景上的小纸条（信息栏、提示、技能格）：纸面略透一点，一圈细墨线
static func plaque(alpha := 0.96, _border := 1, margin := 10.0) -> PaperBox:
	var sb := _box("frame_line", Vector2(10, 10), margin, Color(1, 1, 1, alpha), Color(LINE.r, LINE.g, LINE.b, 0.8))
	return _shadow(sb, 0.3)


## 大面板（储物袋 / 入境 / 结算）：宣纸面、委角双线框，底边一抹淡墨远山
static func scroll(margin := 26.0, mountain := true) -> PaperBox:
	var sb := _shadow(_box("frame_panel", Vector2(32, 32), margin + 10.0), 0.6)
	if mountain:
		sb.mountain = tex("mountain")
		sb.mountain_col = Color(LINE.r, LINE.g, LINE.b, 0.42)
	return sb


## 条的外框：细墨线一圈、两头各一根轴头，线里面垫一层纸（填充条放在里面，线画在填充条的外面）
static func bar_frame() -> PaperBox:
	var sb := _box("frame_bar", Vector2(8, 4), 0.0, Color(TINT_TRACK.r, TINT_TRACK.g, TINT_TRACK.b, 0.94))
	sb.grow = 3.0
	sb.paper_inset = 1.8
	return sb


## 背包格：一圈淡线、四角各一个小折角；empty = 空格（更淡）
static func slot(empty := false, hot := false) -> PaperBox:
	var line := CINNABAR if hot else LINE
	var sb := _box("frame_slot", Vector2(16, 16), 8.0, Color(1, 1, 1, 0.45) if empty else (TINT_PLAIN if hot else TINT_BTN),
			Color(line.r, line.g, line.b, 0.3 if empty else 0.9))
	return sb


## 只有一圈线、没有纸底（键盘焦点）
static func outline(col := CINNABAR) -> PaperBox:
	var sb := PaperBox.new()
	sb.frame = tex("frame_line")
	sb.frame_m = Vector2(10, 10)
	sb.frame_col = col
	return sb


static func _btn_box(tint: Color, line: Color, shadow_a: float) -> PaperBox:
	var sb := _box("frame_line", Vector2(10, 10), 10.0, tint, line)
	return _shadow(sb, shadow_a) if shadow_a > 0.0 else sb


## 按钮：纸色底、墨字，悬停 / 按下时墨线变朱砂。on_paper = 放在宣纸面板上的（投影淡一些）
static func style_button(b: Button, on_paper := false) -> void:
	var sh := 0.16 if on_paper else 0.34
	b.add_theme_font_override("font", kai())
	b.add_theme_stylebox_override("normal", _btn_box(TINT_BTN, Color(LINE.r, LINE.g, LINE.b, 0.78), sh))
	b.add_theme_stylebox_override("hover", _btn_box(TINT_PLAIN, CINNABAR, sh))
	b.add_theme_stylebox_override("pressed", _btn_box(TINT_PRESS, CINNABAR, 0.0))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(1, 1, 1, 0.45), Color(LINE.r, LINE.g, LINE.b, 0.25), 0.0))
	b.add_theme_stylebox_override("focus", outline())
	b.add_theme_color_override("font_color", TEXT_INK)
	b.add_theme_color_override("font_hover_color", CINNABAR)
	b.add_theme_color_override("font_pressed_color", CINNABAR)
	b.add_theme_color_override("font_hover_pressed_color", CINNABAR)
	b.add_theme_color_override("font_focus_color", TEXT_INK)
	b.add_theme_color_override("font_disabled_color", Color(TEXT_SOFT.r, TEXT_SOFT.g, TEXT_SOFT.b, 0.45))


## 主按钮（开始匹配这类）：朱砂笺、纸色字
static func style_primary(b: Button) -> void:
	var pale := Color(PAPER.r, PAPER.g, PAPER.b, 0.6)
	b.add_theme_font_override("font", brush())
	b.add_theme_stylebox_override("normal", _btn_box(TINT_CINNABAR, pale, 0.42))
	b.add_theme_stylebox_override("hover", _btn_box(TINT_CINNABAR.lightened(0.1), PAPER, 0.42))
	b.add_theme_stylebox_override("pressed", _btn_box(TINT_CINNABAR.darkened(0.16), PAPER, 0.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, PAPER)


## 圆纸片按钮（和触屏按钮同一套：纸色圆片 + 一笔墨圆，按下变朱砂底），中间一个图标。主界面右上角的背包 / 洞府用。
## 底边可以压一张小纸签：b.set_meta("badge", "3/12") 之后 queue_redraw；"badge_hot" 为真时签上的字变朱砂（背包满了）
static func round_icon_button(icon_kind: String, d := CORNER_BTN) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.draw.connect(func() -> void: _draw_round_button(b, icon_kind))
	return b


## 右上角那颗按钮放哪（vs = 画面大小）
static func corner_pos(vs: Vector2) -> Vector2:
	return Vector2(vs.x - CORNER_BTN - 14.0, 8.0)


static func _draw_round_button(b: Button, icon_kind: String) -> void:
	var mode := b.get_draw_mode()
	var down := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var hot := mode == BaseButton.DRAW_HOVER
	var er := minf(b.size.x, b.size.y) * 0.5 - 1.0       # 墨圆那张图的半径
	var r := er / 1.19                                   # 纸片的半径
	var c := b.size * 0.5
	b.draw_circle(c, r * 0.97, Color(CINNABAR, 0.92) if down else Color(PAPER, 0.96 if hot else 0.88), true, -1.0, true)
	var ring := tex("enso")
	if ring != null:
		b.draw_texture_rect(ring, Rect2(c - Vector2(er, er), Vector2(er, er) * 2.0), false, Color(CINNABAR if hot else LINE, 0.94))
	else:
		b.draw_arc(c, r, 0.0, TAU, 48, LINE, 3.0, true)
	var ic := icon(icon_kind)
	if ic != null:
		var s := r * 1.26
		var lift := r * 0.16 if b.has_meta("badge") else 0.0      # 底下压着纸签时图标往上让一点
		b.draw_texture_rect(ic, Rect2(c - Vector2(s, s) * 0.5 - Vector2(0.0, lift), Vector2(s, s)), false)
	var badge := str(b.get_meta("badge", ""))
	if badge != "":
		var f := kai()
		var fs := 15
		var ts := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var box := Rect2(roundf(c.x - ts.x * 0.5 - 8.0), roundf(c.y + r * 0.7), roundf(ts.x + 16.0), 22.0)
		b.draw_rect(box, PAPER)
		b.draw_rect(box, Color(LINE, 0.85), false, 1.5)
		b.draw_string(f, Vector2(box.position.x + 8.0, box.position.y + 11.0 + f.get_ascent(fs) - f.get_height(fs) * 0.5), badge,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CINNABAR if bool(b.get_meta("badge_hot", false)) else TEXT_INK)


## 一张不挡点击的装饰图（assets/ui/ 里白 + 透明度的那几张：stroke 枯笔 / cloud 祥云 / mountain 远山 / enso 圆 / seal 印），染成 col
static func deco(name: String, size: Vector2, col := LINE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = size
	t.size = size
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 标题下面的一笔枯墨
static func rule(width := 320.0, height := 9.0, col := LINE) -> TextureRect:
	return deco("stroke", Vector2(width, height), col)


## 朱砂印：红底上一个纸色的字
static func seal(text: String, size := 44.0, col := CINNABAR) -> Control:
	var s := deco("seal", Vector2(size, size), col)
	s.self_modulate = col
	s.modulate = Color.WHITE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", brush())
	l.add_theme_font_size_override("font_size", int(size * 0.6))
	l.add_theme_color_override("font_color", PAPER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(l)
	return s


## 品阶色在宣纸上太浅：压深一点当墨色用
static func on_paper(c: Color) -> Color:
	return Color(c.r * 0.5, c.g * 0.5, c.b * 0.5).lerp(TEXT_INK, 0.25)
