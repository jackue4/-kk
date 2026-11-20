extends CanvasLayer
## 择境：走进大厅传送门弹出的关卡选择（游戏暂停、放出鼠标；回车 / 点卡片进入，Esc 返回）。
## 也负责切关时的黑场淡入淡出和"载入中"字样。关卡表 LEVELS 加一行就多一张卡片
## （art = assets/ui/ 里的一张画，没有就用 sky / land 两个颜色画一张渐变小景）。
## 卡片和入境页都是宣纸面板（样式见 ui_style.gd）。
## 故意不写 class_name：用 preload 引用。

signal picked(id: String)
signal closed

const LEVELS := [
	{"id": "mulan", "title": "木兰草原", "tag": "开放世界 · 搜打撤 · 最多 40 人",
		"desc": "暮色草海，四方是黄枫谷、血色禁地、云梦山、坠魔谷。\n采灵药、破禁制、杀怪夺宝，20 分钟内找到亮着的阵撤离，东西才归洞府。\n可单人进入，也可局域网组队。",
		"art": "level_mulan", "sky": Color(0.96, 0.52, 0.24), "land": Color(0.12, 0.36, 0.32)},
]

const UiStyle := preload("res://scripts/ui_style.gd")
const Abode := preload("res://scripts/abode_ui.gd")

var font: Font
var _abode: Control = null        # 开着的洞府界面
var _loadout_lab: Label = null    # 入境页上「这次带什么」那一行
var net: Node = null          # 联机（net.gd）：列房间用
## 选好的进入方式（main.gd 在 picked 之后读）：match 一键匹配（界面上只有这一种）；solo 单机 / host 建房 / join 加入 join_ip 留给自检脚本
var mode := "solo"
var team_size := 1
var join_ip := ""
var _lv := 0
var _size_btns: Array[Button] = []
var _menu: Control
var _fade: ColorRect
var _loading: Label
var _first: Button


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_loading = _label("", 34, Color(0.92, 0.9, 0.84))
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_loading)


func is_open() -> bool:
	return _menu != null


func fade(to_alpha: float, dur: float) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", to_alpha, dur)
	await tw.finished


func set_loading(text: String) -> void:
	_loading.text = text


func open() -> void:
	if _menu != null:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	move_child(_menu, 0)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	_menu.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 26)
	col.add_child(head)
	var cloud_l := UiStyle.deco("cloud", Vector2(132, 54), Color(UiStyle.PAPER, 0.85))
	cloud_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cloud_l.flip_h = true
	head.add_child(cloud_l)
	var title := _label("择  境", 72, UiStyle.PAPER)
	title.add_theme_font_override("font", UiStyle.brush())
	title.add_theme_color_override("font_outline_color", Color(UiStyle.INK, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	head.add_child(title)
	var cloud_r := UiStyle.deco("cloud", Vector2(132, 54), Color(UiStyle.PAPER, 0.85))
	cloud_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cloud_r)
	var sub := _label("踏入传送门，择一方天地", 22, Color(UiStyle.PAPER, 0.82))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)
	_first = null
	for i in LEVELS.size():
		var b := _card(LEVELS[i])
		row.add_child(b)
		b.pressed.connect(pick.bind(i))
		if _first == null:
			_first = b
	var hint := _label("回车 / 点击 进入　　Esc 返回", 20, Color(UiStyle.PAPER, 0.62))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	if _first != null:
		_first.grab_focus()


func close() -> void:
	if _menu == null:
		return
	if net != null:
		net.stop_discovery()
	if is_instance_valid(_abode):
		_abode.queue_free()
	_size_btns.clear()
	_menu.queue_free()
	_menu = null
	get_tree().paused = false
	closed.emit()


## 点了关卡卡片：换成「入境」一页（选组队人数 → 开始匹配）。quick = 直接单机进入（自检脚本用）
func pick(i: int, quick := false) -> void:
	if _menu == null:
		return
	_lv = i
	if quick or net == null:
		mode = "solo"
		_go()
		return
	_show_modes()


func _go() -> void:
	var id: String = LEVELS[_lv]["id"]
	if net != null and mode != "match":
		net.stop_discovery()
	if is_instance_valid(_abode):
		_abode.queue_free()
	_menu.queue_free()
	_menu = null
	_size_btns.clear()
	get_tree().paused = false
	picked.emit(id)


func _btn(text: String, w := 420.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 56.0)
	b.add_theme_font_size_override("font_size", 24)
	UiStyle.style_button(b)
	return b


func _set_size(n: int) -> void:
	team_size = n
	for i in _size_btns.size():
		_size_btns[i].button_pressed = [1, 2, 4][i] == n


## 入境页：选组队人数（独行 / 双人 / 四人）→「开始匹配」。
## 匹配由 main.gd 接手：局域网里有房间就进去、和同样人数还有空位的队伍拼到一起；没有房间就自己开一间等别人进来；
## 队伍里缺的人先由 AI 道友补上，之后有真人进队再把 AI 换下来。
func _show_modes() -> void:
	for c in _menu.get_children():
		c.queue_free()
	net.start_discovery()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.scroll(34.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var title := _label("%s · 入境" % LEVELS[_lv]["title"], 50, UiStyle.TEXT_INK)
	title.add_theme_font_override("font", UiStyle.brush())
	head.add_child(title)
	var seal := UiStyle.seal("境", 46.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(seal)
	var rule := UiStyle.rule(420.0, 9.0, Color(UiStyle.LINE, 0.82))
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 14)
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(r2)
	_size_btns.clear()
	for n: int in [1, 2, 4]:
		var b := Button.new()
		b.text = ["独行", "双人队", "四人队"][[1, 2, 4].find(n)]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(168.0, 76.0)
		b.add_theme_font_size_override("font_size", 28)
		UiStyle.style_button(b, true)
		b.pressed.connect(_set_size.bind(n))
		r2.add_child(b)
		_size_btns.append(b)
	_set_size(team_size)
	# 备战（2026-11-20）：这次带什么进去 + 去洞府整理
	var prep := HBoxContainer.new()
	prep.add_theme_constant_override("separation", 14)
	prep.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(prep)
	_loadout_lab = _label(Abode.summary(), 19, UiStyle.TEXT_INK)
	_loadout_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prep.add_child(_loadout_lab)
	var abode := _btn("洞府 · 备战", 220.0)
	abode.custom_minimum_size = Vector2(220.0, 60.0)
	abode.pressed.connect(open_abode)
	prep.add_child(abode)
	var go := _btn("开始匹配", 540.0)
	go.custom_minimum_size = Vector2(540.0, 84.0)
	go.add_theme_font_size_override("font_size", 38)
	UiStyle.style_primary(go)
	go.pressed.connect(func() -> void:
		mode = "match"
		_go())
	col.add_child(go)
	var tip := _label("自动匹配同队道友，人不够由 AI 道友补位；队友之间互不伤害。\n佩戴的法宝和背包陨落即失，储物戒里的保得住；20 分钟内找到亮着的阵撤离。", 18, UiStyle.TEXT_SOFT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tip)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(160.0, 52.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 22)
	UiStyle.style_button(back, true)
	back.pressed.connect(close)
	col.add_child(back)
	go.grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if _menu == null or is_instance_valid(_abode):
		return
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 洞府（abode_ui.gd）：盖在入境页上面，关掉后刷新「这次带什么」那一行
func open_abode() -> void:
	if is_instance_valid(_abode):
		return
	_abode = Abode.new()
	_abode.font = font
	add_child(_abode)
	_abode.closed.connect(func() -> void:
		if is_instance_valid(_loadout_lab):
			_loadout_lab.text = Abode.summary())


## 关卡卡片：一张宣纸，上面一幅小画（右下角钤一方「境」印），下面是题名、一行朱字的标签和说明
func _card(lv: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(460.0, 452.0)
	b.focus_mode = Control.FOCUS_ALL
	var normal := UiStyle.scroll(0.0, false)
	var hover := UiStyle.scroll(0.0, false)
	hover.frame_col = UiStyle.CINNABAR
	hover.shadow_a = 0.85
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", hover)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 30.0
	box.offset_right = -30.0
	box.offset_top = 30.0
	box.offset_bottom = -26.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	b.add_child(box)
	var thumb := TextureRect.new()
	var art := UiStyle.tex(str(lv.get("art", ""))) if lv.has("art") else null
	if art != null:
		thumb.texture = art
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# 没有画的关卡：天色 → 草色的渐变，叠几道起伏的山脊
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 0.6, 1.0])
		g.colors = PackedColorArray([lv["sky"], (lv["sky"] as Color).lerp(Color(0.85, 0.88, 0.9), 0.6),
				(lv["land"] as Color).lightened(0.15), lv["land"]])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0.0, 0.0)
		gt.fill_to = Vector2(0.0, 1.0)
		gt.width = 64
		gt.height = 64
		thumb.texture = gt
		thumb.stretch_mode = TextureRect.STRETCH_SCALE
		var hills := _Hills.new()
		hills.land = lv["land"]
		hills.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hills.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.add_child(hills)
	thumb.custom_minimum_size = Vector2(0.0, 178.0)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb)
	var rim := Panel.new()         # 画的边：一圈细墨线
	rim.add_theme_stylebox_override("panel", UiStyle.outline(Color(UiStyle.LINE, 0.7)))
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.offset_left = -3.0
	rim.offset_top = -3.0
	rim.offset_right = 3.0
	rim.offset_bottom = 3.0
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(rim)
	var seal := UiStyle.seal("境", 40.0)
	seal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	seal.position = Vector2(-52.0, -52.0)
	thumb.add_child(seal)
	var t := _label(String(lv["title"]), 44, UiStyle.TEXT_INK)
	t.add_theme_font_override("font", UiStyle.brush())
	box.add_child(t)
	var tag := _label(String(lv["tag"]), 18, UiStyle.CINNABAR)
	box.add_child(tag)
	box.add_child(UiStyle.rule(220.0, 6.0, Color(UiStyle.LINE, 0.7)))
	var d := _label(String(lv["desc"]), 18, UiStyle.TEXT_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(d)
	# 卡片的高度跟着内容走：说明文字折几行、字体行高多少，网页 / 手机和桌面不一样，写死会顶出纸面。
	# 直接拿字体量（自动换行的 Label 在排版之前报的最小高度不可信）。
	var df: Font = font if font != null else ThemeDB.fallback_font
	var text_w := b.custom_minimum_size.x - 60.0
	var dh := df.get_multiline_string_size(String(lv["desc"]), HORIZONTAL_ALIGNMENT_LEFT, text_w, 18).y
	dh += 3.0 * ceilf(dh / maxf(df.get_height(18), 1.0))      # Label 每行另加的行距
	# 上边距 30 + 画 178 + 题名 + 标签 + 一笔 6 + 说明 + 四道间距 + 下边距 30（卡片还没进场景树，Label 自己报的高度不准，都拿字体量）
	var need := 30.0 + 178.0 + UiStyle.brush().get_height(44) + df.get_height(18) + 6.0 + dh + 8.0 * 4.0 + 30.0
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, ceilf(need))
	return b


func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


## 缩略图上的几道山脊剪影
class _Hills:
	extends Control
	var land := Color(0.3, 0.5, 0.2)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for k in 3:
			var pts := PackedVector2Array()
			var base := h * (0.58 + 0.12 * k)
			var amp := h * (0.12 - 0.03 * k)
			for i in 33:
				var x := w * i / 32.0
				pts.append(Vector2(x, base - amp * (0.6 * sin(x * 0.021 + k * 1.7) + 0.4 * sin(x * 0.057 + k * 0.6))))
			pts.append(Vector2(w, h))
			pts.append(Vector2(0.0, h))
			var c := land.darkened(0.25 - 0.1 * k).lerp(Color(0.62, 0.7, 0.78), 0.45 - 0.2 * k)
			draw_colored_polygon(pts, c)
