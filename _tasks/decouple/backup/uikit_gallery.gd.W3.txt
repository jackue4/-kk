extends SceneTree
## 界面样式小样页：不进游戏，把 ui_style.gd 发的各种样式摆出来截一张图（调样式用，几秒钟出图）。
## 用法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/uikit --resolution 1600x900 -s res://_tasks/ui_kit/gallery.gd -- <输出 jpg 的绝对路径>

const UiStyle := preload("res://scripts/ui_style.gd")

var _n := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	UiStyle.force_bundled = args.has("--web-fonts")     # 用随包字体预览网页 / 手机上的样子
	_out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview/uikit.jpg")
	var th := Theme.new()
	th.default_font = UiStyle.kai()
	th.default_font_size = 18
	var base := Control.new()
	base.theme = th
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)
	# 背景：左亮（草地 / 天）右暗（暗区），看纸片压在两种场景上的样子
	_rect(base, Rect2(0, 0, 900, 420), Color(0.55, 0.78, 0.95))
	_rect(base, Rect2(0, 420, 900, 480), Color(0.36, 0.66, 0.26))
	_rect(base, Rect2(900, 0, 700, 900), Color(0.10, 0.08, 0.12))

	# 大面板
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.scroll(22.0))
	panel.position = Vector2(60, 150)
	base.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(UiStyle.seal("储", 46.0))
	var t := _ink("储物袋", 38)
	t.add_theme_font_override("font", UiStyle.brush())
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_ink("10 / 12　共 417 灵石", 20, UiStyle.TEXT_SOFT))
	v.add_child(UiStyle.rule(360.0, 8.0, Color(UiStyle.LINE, 0.8)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var kinds := ["pill", "gear", "mat", "gear", "pill", "mat", "", ""]
	var names := ["黄龙丹", "精铁飞镖", "妖狼内丹", "青钢盾", "筑基丹", "枫木灵芯", "", ""]
	var cols := [Color(0.78, 0.8, 0.84), Color(0.78, 0.8, 0.84), Color(0.78, 0.8, 0.84), Color(0.4, 0.9, 0.5), Color(0.4, 0.9, 0.5), Color(0.35, 0.65, 1.0)]
	for i in 8:
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 92)
		var empty: bool = kinds[i] == ""
		b.add_theme_stylebox_override("normal", UiStyle.slot(empty))
		b.add_theme_stylebox_override("hover", UiStyle.slot(false, true))
		b.add_theme_stylebox_override("pressed", UiStyle.slot(false, true))
		b.add_theme_stylebox_override("disabled", UiStyle.slot(true))
		b.disabled = empty
		grid.add_child(b)
		if empty:
			continue
		var ic := TextureRect.new()
		ic.texture = UiStyle.icon(kinds[i])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(10, 14)
		ic.size = Vector2(64, 64)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var nm := _ink(names[i], 21)
		nm.position = Vector2(82, 16)
		b.add_child(nm)
		var sub := _ink("灵器 · 修为 +57", 15, UiStyle.on_paper(cols[i]))
		sub.position = Vector2(82, 50)
		b.add_child(sub)
	v.add_child(_ink("点丹药 = 服用（涨修为、回气血）　点装备 / 材料 = 丢在脚边", 16, UiStyle.TEXT_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	for i in 3:
		var b := Button.new()
		b.text = ["关闭", "双人队", "不可用"][i]
		b.custom_minimum_size = Vector2(150, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.disabled = i == 2
		UiStyle.style_button(b, true)
		row.add_child(b)
	var go := Button.new()
	go.text = "开始匹配"
	go.custom_minimum_size = Vector2(260, 60)
	go.add_theme_font_size_override("font_size", 30)
	UiStyle.style_primary(go)
	row.add_child(go)

	# 小纸条 + 条框：亮处和暗处各一份
	for k in 2:
		var x := 60.0 + 940.0 * k
		var pl := Panel.new()
		pl.add_theme_stylebox_override("panel", UiStyle.plaque())
		pl.position = Vector2(x, 20)
		pl.size = Vector2(300, 108)
		base.add_child(pl)
		var info := _ink("木兰草原　怪物 Lv.2\n化神期　修为 Lv.14\n\n01:46　风平浪静", 19)
		info.position = Vector2(14, 8)
		pl.add_child(info)
		_bar(pl, Vector2(14, 60), Vector2(240, 7), UiStyle.QING, 0.6)
		var bt := Button.new()
		bt.text = "背包 10/12"
		bt.position = Vector2(x + 320, 20)
		bt.size = Vector2(150, 54)
		bt.add_theme_font_size_override("font_size", 22)
		UiStyle.style_button(bt)
		base.add_child(bt)
		var y := 780.0
		_bar(base, Vector2(x, y), Vector2(420, 10), UiStyle.CINNABAR, 0.72, 0.86)
		_bar(base, Vector2(x, y + 24), Vector2(420, 8), UiStyle.INDIGO, 0.45)
		_bar(base, Vector2(x, y + 46), Vector2(420, 8), Color(0.86, 0.56, 0.2), 0.3)
		var lab := Label.new()
		lab.text = "生命 96"
		lab.position = Vector2(x + 440, y - 10)
		lab.add_theme_color_override("font_color", UiStyle.TEXT)
		lab.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.92))
		lab.add_theme_constant_override("outline_size", 4)
		base.add_child(lab)

	# 触屏按钮小样
	var pad := Control.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad.bind(pad))
	base.add_child(pad)

	# 装饰
	var cl := UiStyle.deco("cloud", Vector2(160, 66), Color(UiStyle.PAPER, 0.9))
	cl.position = Vector2(1100, 180)
	base.add_child(cl)
	var mt := UiStyle.deco("mountain", Vector2(600, 103), Color(UiStyle.PAPER, 0.7))
	mt.position = Vector2(960, 260)
	base.add_child(mt)


func _draw_pad(pad: Control) -> void:
	var enso := UiStyle.tex("enso")
	var bf := UiStyle.brush()
	var items := [[Vector2(700, 620), 86.0, "攻", false], [Vector2(830, 500), 54.0, "闪", false], [Vector2(560, 700), 58.0, "御", true],
			[Vector2(1380, 620), 86.0, "攻", false], [Vector2(1510, 500), 54.0, "闪", true], [Vector2(1240, 700), 58.0, "御", false]]
	for it: Array in items:
		var c: Vector2 = it[0]
		var r: float = it[1]
		var on: bool = it[3]
		var fill := Color(UiStyle.CINNABAR, 0.9) if on else Color(UiStyle.PAPER, 0.86)
		pad.draw_circle(c, r * 0.97, fill, true, -1.0, true)
		var er := r * 1.19
		pad.draw_texture_rect(enso, Rect2(c - Vector2(er, er), Vector2(er, er) * 2.0), false, Color(UiStyle.LINE, 0.92))
		var txt: String = it[2]
		var fs := int(r * 0.7)
		var ts := bf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		pad.draw_string(bf, c + Vector2(-ts.x * 0.5, ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.PAPER if on else UiStyle.TEXT_INK)


func _rect(parent: Control, r: Rect2, col: Color) -> void:
	var c := ColorRect.new()
	c.color = col
	c.position = r.position
	c.size = r.size
	parent.add_child(c)


func _ink(text: String, size: int, col := UiStyle.TEXT_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(parent: Control, pos: Vector2, size: Vector2, col: Color, ratio: float, lag := 0.0) -> void:
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UiStyle.bar_frame())
	bg.position = pos
	bg.size = size
	parent.add_child(bg)
	if lag > 0.0:
		var l := ColorRect.new()
		l.color = Color(0.9, 0.6, 0.45, 0.9)
		l.size = Vector2(size.x * lag, size.y)
		bg.add_child(l)
	var f := ColorRect.new()
	f.color = col
	f.size = Vector2(size.x * ratio, size.y)
	bg.add_child(f)


func _process(_dt: float) -> bool:
	_n += 1
	if _n == 12:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(_out, 0.9)
		print("saved ", _out, " ", img.get_size())
		return true
	return false
