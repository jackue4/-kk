extends Control
## 「武侠漫画分镜」风格的英雄选择界面 —— 样张（2026-11-25）。
## 用户：「整个游戏的ui还是很丑……这种美漫漫画手绘风，你能还原吗」，商定先只做这一张样张给他看，不动现有界面（现在线上用的还是 scripts/ex/hero_select_ui.gd）。
## 版式：左边一列选人格子（没选中的是两色墨稿）、中间主色斜切色块上压着大号的人（冲出画框）、左下黑底大字名牌 + 关键词、
## 右边六块招式 + 说明 + 「出战」。左右划 / 方向键 / 点格子换人；点招式块人会比划一遍。
## 中间的人有两条路：3D 模型过一遍漫画着色器（comic_figure.gd），或者一张 2D 立绘（art 里放了这位英雄的图、use_art 为真时）。
## 样张不碰存档：「出战」只改自己身上的 picked。数据全读 hero_defs.gd。

signal closed

const Kit := preload("res://_tasks/ui_comic/comic_kit.gd")
const Slab := preload("res://_tasks/ui_comic/comic_slab.gd")
const Paper := preload("res://_tasks/ui_comic/comic_paper.gd")
const Figure := preload("res://_tasks/ui_comic/comic_figure.gd")
const HeroDefs := preload("res://scripts/hero_defs.gd")
const PANEL_SH := preload("res://_tasks/ui_comic/comic_panel.gdshader")
const BRUSH_SH := preload("res://_tasks/ui_comic/comic_brush.gdshader")
const FLAT_SH := preload("res://_tasks/ui_comic/comic_flat.gdshader")

const COL_W := 540.0
const TILE_H := 88.0
const TILE_GAP := 12.0
const MARGIN := 40.0
const DESC_PX := 27
const AWAKE_PX := 25

var ids: Array = []
var cur := 0
var picked := ""
var skill := 1
var use_art := false          # 中间放 2D 立绘（art 里有这位英雄的图才生效）
var art := {}                 # 英雄 id → Texture2D

var _paper: Paper
var _brush: ColorRect            # 色块后面那一大笔干刷
var _brush2: ColorRect           # 「出战」底下那一小笔墨
var _panel_drop: ColorRect
var _panel_old: ColorRect
var _panel: ColorRect
var _stage: Control
var _fig: Figure
var _art: TextureRect
var _art_drop: TextureRect       # 立绘身后的硬投影（同一张图压成纯色，往右下错开）
var _swipe: Control
var _name_slab: Slab
var _name: Label
var _title_slab: Slab
var _title: Label
var _seal: Control
var _tag_box: Control
var _roster: Array = []
var _tiles: Array = []
var _desc_box: Slab
var _desc_tab: Slab
var _desc_name: Label
var _desc_meta: Label
var _desc: Label
var _awake_tag: Slab
var _awake_tag_l: Label
var _awake: Label
var _go: Button
var _go_slab: Slab
var _go_label: Label
var _back: Button
var _head: Label
var _cap: Label
var _page: Label
var _page2: Label
var _mode: Button
var _mode_slab: Slab
var _mode_label: Label
var _cx := 700.0
var _drag := false
var _drag_x0 := 0.0
var _busy := false
var _entered := false
var _desc_raw := ""
var _awake_raw := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ids = HeroDefs.ids()
	if picked == "" or not ids.has(picked):
		picked = HeroDefs.DEFAULT
	cur = maxi(ids.find(picked), 0)
	_paper = Paper.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_paper)
	_brush = _brush_rect(1.0, 64.0)
	_brush2 = _brush_rect(4.0, 26.0)
	_panel_drop = _panel_rect(true)
	_panel_old = _panel_rect(false)
	_panel_old.visible = false
	_panel = _panel_rect(false)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_fig = Figure.new()
	_fig.hero_id = str(ids[cur])
	_stage.add_child(_fig)
	_art_drop = TextureRect.new()
	var dm := ShaderMaterial.new()
	dm.shader = FLAT_SH
	_art_drop.material = dm
	_art = TextureRect.new()
	for a: TextureRect in [_art_drop, _art]:
		a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		a.flip_h = true              # 立绘里出拳朝左（会被名牌挡住），翻过来朝右：拳头冲出色块、指向右边的招式
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.visible = false
		_stage.add_child(a)
	_swipe = Control.new()
	_swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_swipe.gui_input.connect(_on_swipe)
	add_child(_swipe)
	_build_name()
	_build_roster()
	_build_right()
	_build_top()
	resized.connect(_layout)
	_refresh()
	_layout()
	_enter.call_deferred()


func _panel_rect(shadow: bool) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = PANEL_SH
	m.set_shader_parameter("flat_only", 1.0 if shadow else 0.0)
	if shadow:
		m.set_shader_parameter("fill", Kit.INK)
	r.material = m
	add_child(r)
	return r


func _brush_rect(seed: float, rows: float) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = BRUSH_SH
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("rows", rows)
	r.material = m
	add_child(r)
	return r


func _pm(r: ColorRect) -> ShaderMaterial:
	return r.material as ShaderMaterial


func _set_panel(r: ColorRect, ac: Color) -> void:
	_pm(r).set_shader_parameter("fill", ac)
	_pm(r).set_shader_parameter("fill2", ac.darkened(0.2).lerp(Kit.INK, 0.06))


# ---------- 搭 ----------

func _build_name() -> void:
	_name_slab = Slab.new()
	_name_slab.fill = Kit.INK
	_name_slab.edge_w = 0.0
	_name_slab.drop = Vector2(10.0, 10.0)
	add_child(_name_slab)
	_name = Kit.label("", 104, Kit.PAPER_HI)
	Kit.bold(_name, 3)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_slab.add_child(_name)
	_title_slab = Slab.new()
	_title_slab.edge_w = 3.0
	add_child(_title_slab)
	_title = Kit.label("", 32, Kit.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_slab.add_child(_title)
	_seal = Control.new()
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal.size = Vector2(70.0, 70.0)
	_seal.pivot_offset = Vector2(35.0, 35.0)
	_seal.rotation = -0.16
	var ss := Slab.new()
	ss.skew = 0.0
	ss.fill = Kit.VERMILION
	ss.edge = Kit.PAPER_HI
	ss.edge_w = 3.0
	ss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal.add_child(ss)
	var sl := Kit.label("战", 48, Kit.PAPER_HI)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal.add_child(sl)
	add_child(_seal)
	_tag_box = Control.new()
	_tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag_box)


func _build_roster() -> void:
	for i in ids.size():
		var b := Kit.ghost_button()
		add_child(b)
		var slab := Slab.new()
		slab.skew = 0.12
		slab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slab.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		b.add_child(slab)
		var f := Figure.new()
		f.bust = true
		f.view_h = 1.5
		f.look_y = 1.38
		f.eye_drop = 0.06
		f.base_yaw = 0.5
		f.res_scale = 1.6
		f.hero_id = str(ids[i])
		f.mat.set_shader_parameter("line_px", 2.6)
		f.mat.set_shader_parameter("dot_cell", 5.0)
		f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slab.add_child(f)
		var frame := Slab.new()          # 裁掉头像之后再描一遍边（裁剪会把边线吃掉一半）
		frame.skew = 0.12
		frame.fill = Color(0, 0, 0, 0)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(frame)
		var bar := Slab.new()
		bar.fill = Kit.INK
		bar.edge_w = 0.0
		b.add_child(bar)
		var nm := Kit.label(HeroDefs.hero_name(str(ids[i])), 26, Kit.PAPER_HI)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.add_child(nm)
		b.pressed.connect(_on_roster.bind(i))
		_roster.append({"btn": b, "slab": slab, "fig": f, "frame": frame, "bar": bar, "name": nm})


func _build_right() -> void:
	for i in 6:
		var b := Kit.ghost_button()
		add_child(b)
		var slab := Slab.new()
		slab.edge_w = 3.0
		slab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(slab)
		var gs := Slab.new()
		gs.fill = Kit.INK
		gs.edge_w = 0.0
		b.add_child(gs)
		var glyph := Kit.label("", 46, Kit.PAPER_HI)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		gs.add_child(glyph)
		var nm := Kit.label("", 32, Kit.INK)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.clip_text = true
		b.add_child(nm)
		b.pressed.connect(_pick_skill.bind(i, true))
		_tiles.append({"btn": b, "slab": slab, "gs": gs, "glyph": glyph, "name": nm, "home": Vector2.ZERO})
	_desc_box = Slab.new()
	_desc_box.skew = 0.0
	_desc_box.fill = Kit.PAPER_HI
	_desc_box.drop = Vector2(10.0, 10.0)
	add_child(_desc_box)
	_desc_tab = Slab.new()
	_desc_tab.edge_w = 3.0
	add_child(_desc_tab)
	_desc_name = Kit.label("", 38, Kit.INK)
	_desc_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desc_tab.add_child(_desc_name)
	_desc_meta = Kit.label("", 24, Kit.INK_SOFT)
	_desc_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_desc_meta)
	_desc = Kit.label("", DESC_PX, Kit.INK, false)
	_desc.add_theme_constant_override("line_spacing", 6)
	add_child(_desc)
	_awake_tag = Slab.new()
	_awake_tag.fill = Kit.INK
	_awake_tag.edge_w = 0.0
	add_child(_awake_tag)
	_awake_tag_l = Kit.label("觉醒后", 24, Kit.PAPER_HI)
	_awake_tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_awake_tag_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_awake_tag_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_awake_tag.add_child(_awake_tag_l)
	_awake = Kit.label("", AWAKE_PX, Kit.INK, false)
	_awake.add_theme_constant_override("line_spacing", 5)
	add_child(_awake)
	_go = Kit.ghost_button()
	add_child(_go)
	_go_slab = Slab.new()
	_go_slab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_go.add_child(_go_slab)
	_go_label = Kit.label("出战", 60, Kit.PAPER_HI)
	Kit.bold(_go_label, 2)
	_go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_go_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_go_slab.add_child(_go_label)
	_go.pressed.connect(_on_go)
	_press_fx(_go, _go_slab)


func _build_top() -> void:
	_back = Kit.ghost_button()
	add_child(_back)
	var bs := Slab.new()
	bs.fill = Kit.INK
	bs.edge_w = 0.0
	bs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.add_child(bs)
	var arrow := Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.draw.connect(func() -> void:
		var c := arrow.size * 0.5
		arrow.draw_polyline(PackedVector2Array([c + Vector2(9.0, -15.0), c + Vector2(-9.0, 0.0), c + Vector2(9.0, 15.0)]), Kit.PAPER_HI, 6.0, true))
	bs.add_child(arrow)
	_back.pressed.connect(func() -> void: closed.emit())
	_press_fx(_back, bs)
	_head = Kit.label("择英雄", 58, Kit.INK)
	Kit.bold(_head, 2)
	add_child(_head)
	_cap = Kit.label("英雄谱 · 卷一", 22, Kit.INK_SOFT, false)
	add_child(_cap)
	_page = Kit.label("01", 70, Kit.INK)
	Kit.bold(_page, 2)
	_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_page)
	_page2 = Kit.label("/ 03", 32, Kit.INK_SOFT)
	add_child(_page2)
	_mode = Kit.ghost_button()
	_mode.visible = false
	add_child(_mode)
	_mode_slab = Slab.new()
	_mode_slab.fill = Kit.PAPER_HI
	_mode_slab.edge_w = 3.0
	_mode_slab.drop = Vector2(5.0, 5.0)
	_mode_slab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode.add_child(_mode_slab)
	_mode_label = Kit.label("", 26, Kit.INK)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode_slab.add_child(_mode_label)
	_mode.pressed.connect(func() -> void: set_art_mode(not use_art))


## 按下去：色块落到投影的位置上（投影藏起来），松手弹回
func _press_fx(b: Button, slab: Slab) -> void:
	b.button_down.connect(func() -> void:
		slab.set_meta("drop0", slab.drop)
		slab.position = slab.drop * 0.8
		slab.drop = Vector2.ZERO
		slab.queue_redraw())
	b.button_up.connect(func() -> void:
		slab.drop = slab.get_meta("drop0", Vector2.ZERO)
		slab.position = Vector2.ZERO
		slab.queue_redraw())


# ---------- 摆 ----------

func _layout() -> void:
	var vs := size
	if vs.x < 100.0 or vs.y < 100.0:
		return
	var rx := vs.x - MARGIN - COL_W                        # 右边那一栏的左沿
	_cx = clampf((214.0 + rx) * 0.5 + 6.0, 560.0, vs.x * 0.5)
	var py := 232.0
	var psize := Vector2(610.0, vs.y - py - 46.0)
	var ppos := Vector2(_cx - psize.x * 0.5, py)
	for r: ColorRect in [_panel, _panel_old, _panel_drop]:
		r.position = ppos
		r.size = psize
		_pm(r).set_shader_parameter("rect_px", psize)
	_panel_drop.position = ppos + Vector2(16.0, 16.0)
	_paper.focus = Vector2(_cx, py + psize.y * 0.36)
	_paper.queue_redraw()
	# 一大笔干刷：从左下往右上斜着刷过色块后面，两头都冲出色块
	_brush.size = Vector2(1180.0, 300.0)
	_brush.pivot_offset = _brush.size * 0.5
	_brush.rotation = -0.2
	_brush.position = Vector2(_cx - 590.0 + 30.0, py + psize.y * 0.5 - 150.0 - 40.0)
	_brush2.size = Vector2(430.0, 74.0)
	_brush2.pivot_offset = _brush2.size * 0.5
	_brush2.rotation = -0.05
	_brush2.position = Vector2(vs.x - MARGIN - 430.0, vs.y - 96.0)
	_stage.size = vs
	var fsize := Vector2(860.0, vs.y - 16.0)
	_fig.position = Vector2(_cx - fsize.x * 0.5, 8.0)
	_fig.size = fsize
	_art.position = Vector2(_cx - fsize.x * 0.5 + 24.0, 36.0)
	_art.size = Vector2(fsize.x, vs.y - 36.0 - 30.0)
	_art_drop.position = _art.position + Vector2(16.0, 12.0)
	_art_drop.size = _art.size
	_swipe.position = Vector2(214.0, 110.0)
	_swipe.size = Vector2(rx - 214.0 - 16.0, vs.y - 110.0)
	# 名牌 + 关键词
	_name_slab.size = Vector2(380.0, 138.0)
	_name_slab.position = Vector2(_cx - 404.0, vs.y - 276.0)
	_name_slab.pivot_offset = _name_slab.size * 0.5
	_title_slab.size = Vector2(150.0, 52.0)
	_title_slab.position = _name_slab.position + Vector2(262.0, -38.0)
	_seal.position = _name_slab.position + Vector2(-12.0, -40.0)
	_tag_box.position = Vector2(_cx - 414.0, vs.y - 118.0)
	# 选人格子
	var ty := 190.0
	for i in _roster.size():
		var e: Dictionary = _roster[i]
		var b := e["btn"] as Button
		b.size = Vector2(150.0, 138.0)
		b.set_meta("home", Vector2(MARGIN + 6.0, ty))
		var bar := e["bar"] as Slab
		bar.size = Vector2(118.0, 36.0)
		bar.position = Vector2(26.0, 138.0 - 30.0)
		ty += 138.0 + 30.0
	_style_roster()
	# 右栏：六块招式
	var tw := (COL_W - TILE_GAP * 2.0) / 3.0
	var y0 := 120.0
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var b2 := t["btn"] as Button
		b2.size = Vector2(tw, TILE_H)
		t["home"] = Vector2(rx + float(i % 3) * (tw + TILE_GAP), y0 + float(i / 3) * (TILE_H + TILE_GAP + 4.0))
		var gs := t["gs"] as Slab
		gs.size = Vector2(66.0, TILE_H)
		gs.position = Vector2.ZERO
		var nm := t["name"] as Label
		nm.position = Vector2(70.0, 0.0)
		nm.size = Vector2(tw - 78.0, TILE_H)
	_style_tiles()
	# 说明
	var dy := y0 + TILE_H * 2.0 + TILE_GAP + 4.0 + 44.0
	var tx := rx + 26.0
	var tw2 := COL_W - 10.0 - 52.0
	_desc.text = Kit.wrap(_desc_raw, Kit.body(), DESC_PX, tw2)
	_awake.text = Kit.wrap(_awake_raw, Kit.body(), AWAKE_PX, tw2)
	_desc.reset_size()
	_awake.reset_size()
	var need := 50.0 + _desc.get_minimum_size().y + 26.0
	if _awake_raw != "":
		need += 16.0 + 44.0 + _awake.get_minimum_size().y
	_desc_box.position = Vector2(rx, dy)
	_desc_box.size = Vector2(COL_W - 10.0, clampf(need, 250.0, vs.y - dy - 150.0))
	_desc_tab.size = Vector2(maxf(_desc_name.get_minimum_size().x + 64.0, 150.0), 56.0)
	_desc_tab.position = Vector2(rx + 16.0, dy - 30.0)
	_desc_meta.size = Vector2(240.0, 34.0)
	_desc_meta.position = Vector2(rx + COL_W - 10.0 - 22.0 - 240.0, dy + 8.0)
	_desc.position = Vector2(tx, dy + 50.0)
	var ay := _desc.position.y + _desc.get_minimum_size().y + 16.0
	_awake_tag.size = Vector2(100.0, 36.0)
	_awake_tag.position = Vector2(tx, ay)
	_awake.position = Vector2(tx, ay + 44.0)
	# 出战
	_go.size = Vector2(300.0, 90.0)
	_go.position = Vector2(rx + COL_W - 10.0 - 300.0, vs.y - 132.0)
	# 顶上
	_back.position = Vector2(MARGIN, 30.0)
	_back.size = Vector2(98.0, 60.0)
	_head.position = Vector2(MARGIN + 116.0, 20.0)
	_cap.position = Vector2(MARGIN + 120.0, 88.0)
	_page.size = Vector2(120.0, 80.0)
	_page.position = Vector2(vs.x - MARGIN - 210.0, 14.0)
	_page2.position = Vector2(vs.x - MARGIN - 84.0, 46.0)
	_mode.size = Vector2(150.0, 42.0)
	_mode.position = Vector2(MARGIN + 4.0, vs.y - 72.0)


func _style_roster() -> void:
	for i in _roster.size():
		var e: Dictionary = _roster[i]
		var b := e["btn"] as Button
		var sel := i == cur
		var ac := Kit.accent(str(ids[i]))
		var slab := e["slab"] as Slab
		var frame := e["frame"] as Slab
		slab.fill = ac if sel else Kit.PAPER_LO
		slab.edge_w = 0.0
		frame.edge_w = 5.0 if sel else 3.0
		frame.drop = Vector2.ZERO
		slab.drop = Vector2.ZERO
		slab.queue_redraw()
		frame.queue_redraw()
		(e["fig"] as Figure).mat.set_shader_parameter("mono", 0.0 if sel else 1.0)
		var home: Vector2 = b.get_meta("home", Vector2.ZERO)
		b.position = home + (Vector2(18.0, 0.0) if sel else Vector2.ZERO)
		b.z_index = 1 if sel else 0
		var bar := e["bar"] as Slab
		bar.fill = Kit.INK if sel else Kit.PAPER_HI
		bar.edge_w = 0.0 if sel else 3.0
		bar.queue_redraw()
		Kit.recolor(e["name"] as Label, Kit.PAPER_HI if sel else Kit.INK)


func _style_tiles() -> void:
	var ac := Kit.accent(str(ids[cur]))
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var sel := i == skill
		var slab := t["slab"] as Slab
		slab.fill = ac if sel else Kit.PAPER_HI
		slab.drop = Vector2(7.0, 8.0) if sel else Vector2.ZERO
		slab.queue_redraw()
		Kit.recolor(t["name"] as Label, Kit.on(ac) if sel else Kit.INK)
		(t["btn"] as Button).position = (t["home"] as Vector2) + (Vector2(-4.0, -7.0) if sel else Vector2.ZERO)
		(t["btn"] as Button).z_index = 1 if sel else 0


# ---------- 内容 ----------

func _refresh() -> void:
	var id := str(ids[cur])
	var d := HeroDefs.def_of(id)
	var ac := Kit.accent(id)
	_paper.accent = ac
	_paper.queue_redraw()
	_pm(_brush).set_shader_parameter("fill", Color(ac.lerp(Kit.PAPER_HI, 0.42), 1.0))
	_pm(_brush2).set_shader_parameter("fill", Color(ac.lerp(Kit.PAPER_HI, 0.25), 1.0))
	_set_panel(_panel, ac)
	_fig.mat.set_shader_parameter("drop", Vector2(0.02, 0.014))
	_fig.mat.set_shader_parameter("drop_col", Color(ac.darkened(0.42).lerp(Kit.INK, 0.25), 1.0))
	_name.text = str(d.get("name", ""))
	_title.text = str(d.get("title", ""))
	_title_slab.fill = ac
	_title_slab.queue_redraw()
	Kit.recolor(_title, Kit.on(ac))
	_name_slab.drop_col = ac.darkened(0.25)
	_name_slab.queue_redraw()
	for c in _tag_box.get_children():
		c.queue_free()
	var x := 0.0
	var show: Dictionary = Kit.SHOW.get(id, {})
	for s: Variant in show.get("tags", []):
		var l := Kit.label(str(s), 26, Kit.INK)
		var w := l.get_minimum_size().x + 40.0
		var chip := Slab.new()
		chip.fill = Kit.PAPER_HI
		chip.edge_w = 3.0
		chip.drop = Vector2(4.0, 4.0)
		chip.size = Vector2(w, 42.0)
		chip.position = Vector2(x, 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chip.add_child(l)
		_tag_box.add_child(chip)
		x += w + 4.0
	var touch: Array = d.get("touch", [])
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var g := "攻"
		var n := "连段"
		if i == 5:
			g = "觉"
			n = "觉醒"
		elif i > 0:
			var sk := HeroDefs.skill(id, i - 1)
			g = str(touch[i - 1]) if touch.size() >= i else str(sk.get("key", ""))
			n = str(sk.get("name", ""))
		(t["glyph"] as Label).text = g
		(t["name"] as Label).text = n
	_page.text = "%02d" % (cur + 1)
	_page2.text = "/ %02d" % ids.size()
	_seal.visible = id == picked
	_go_state()
	_style_roster()
	_show_art()
	_pick_skill(skill, false)


func _go_state() -> void:
	var on := str(ids[cur]) == picked
	_go_label.text = "出战中" if on else "出战"
	_go_slab.fill = Kit.PAPER_HI if on else Kit.INK
	_go_slab.edge_w = 4.0
	_go_slab.drop = Vector2.ZERO if on else Vector2(9.0, 9.0)
	_go_slab.drop_col = Kit.accent(str(ids[cur]))
	_go_slab.queue_redraw()
	Kit.recolor(_go_label, Kit.INK if on else Kit.PAPER_HI)
	_go.disabled = on


func _show_art() -> void:
	var id := str(ids[cur])
	var has := art.has(id)
	_mode.visible = not art.is_empty()
	_mode_label.text = "立绘 → 3D" if use_art else "3D → 立绘"
	var on := use_art and has
	_art.visible = on
	_art_drop.visible = on
	_fig.visible = not on
	if on:
		_art.texture = art[id]
		_art_drop.texture = art[id]
		var ac := Kit.accent(id)
		(_art_drop.material as ShaderMaterial).set_shader_parameter("tint", Color(ac.darkened(0.42).lerp(Kit.INK, 0.25), 1.0))


func set_art_mode(on: bool) -> void:
	use_art = on
	_show_art()


func _chain_text(id: String, chain: Array) -> String:
	var names: PackedStringArray = []
	for m: Variant in chain:
		var mv := HeroDefs.move_of(id, str(m))
		names.append(str(mv.get("name", str(m))))
	return " → ".join(names)


## 选中第 i 块招式：换说明；play = 人比划一遍
func _pick_skill(i: int, play: bool) -> void:
	skill = clampi(i, 0, 5)
	var id := str(ids[cur])
	var d := HeroDefs.def_of(id)
	var ac := Kit.accent(id)
	var name_t := ""
	var desc_t := ""
	var awake_t := ""
	var meta_t := ""
	if skill == 0:
		name_t = "连段"
		desc_t = "连点「攻」：" + _chain_text(id, d.get("chain", []))
		var ca: Array = d.get("chain_awake", [])
		if not ca.is_empty():
			awake_t = _chain_text(id, ca)
	elif skill == 5:
		var aw := str(d.get("awaken", ""))
		var head := aw.get_slice(" ", 0)
		name_t = ("觉醒 · " + head) if head.length() <= 5 and head != "" else "觉醒"
		desc_t = aw
	else:
		var sk := HeroDefs.skill(id, skill - 1)
		name_t = str(sk.get("name", ""))
		desc_t = str(sk.get("desc", ""))
		if float(sk.get("cd", 0.0)) >= 1.0:
			meta_t = "冷却 %d 秒" % int(float(sk.get("cd", 0.0)))
		awake_t = str(sk.get("awake", ""))
	_desc_name.text = name_t
	_desc_meta.text = meta_t
	_desc_raw = desc_t
	_awake_raw = awake_t
	_awake.visible = awake_t != ""
	_awake_tag.visible = awake_t != ""
	_desc_tab.fill = ac
	_desc_tab.queue_redraw()
	Kit.recolor(_desc_name, Kit.on(ac))
	Kit.recolor(_awake, ac.darkened(0.45).lerp(Kit.INK, 0.2))
	_style_tiles()
	_layout()
	if play:
		var t: Dictionary = _tiles[skill]
		var b := t["btn"] as Button
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(1.08, 1.08)
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_demo()


func _demo() -> void:
	var show: Dictionary = Kit.SHOW.get(str(ids[cur]), {})
	var demos: Array = show.get("demo", [])
	if skill < demos.size() and _fig.visible:
		_fig.flourish(demos[skill])


# ---------- 动 ----------

## 进场：色块擦进来、人弹出来、名牌从左滑入、右边一块块错开落位
func _enter() -> void:
	if _entered:
		return
	_entered = true
	_pm(_panel).set_shader_parameter("reveal", 0.0)
	_pm(_panel_drop).set_shader_parameter("reveal", 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_reveal, 0.0, 1.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _pm(_brush).set_shader_parameter("reveal", v), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _pm(_brush2).set_shader_parameter("reveal", v), 0.0, 1.0, 0.25).set_delay(0.3)
	_stage.modulate.a = 0.0
	_stage.position = Vector2(60.0, 0.0)
	tw.tween_property(_stage, "modulate:a", 1.0, 0.16).set_delay(0.14)
	tw.tween_property(_stage, "position:x", 0.0, 0.34).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_slide_in(_name_slab, Vector2(-90.0, 0.0), 0.2)
	_slide_in(_title_slab, Vector2(-60.0, 0.0), 0.28)
	_slide_in(_tag_box, Vector2(-60.0, 0.0), 0.32)
	for i in _roster.size():
		_slide_in((_roster[i] as Dictionary)["btn"], Vector2(-70.0, 0.0), 0.06 + 0.05 * float(i))
	_cascade()
	_slide_in(_desc_box, Vector2(50.0, 0.0), 0.26)
	_slide_in(_go, Vector2(0.0, 50.0), 0.34)
	var show: Dictionary = Kit.SHOW.get(str(ids[cur]), {})
	create_tween().tween_callback(func() -> void: _fig.flourish(show.get("enter", []))).set_delay(0.3)


func _set_reveal(v: float) -> void:
	_pm(_panel).set_shader_parameter("reveal", v)
	_pm(_panel_drop).set_shader_parameter("reveal", v)


func _slide_in(n: Control, from: Vector2, delay: float) -> void:
	var home := n.position
	n.position = home + from
	n.modulate.a = 0.0
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position", home, 0.26).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, 0.12).set_delay(delay)


func _cascade() -> void:
	for i in _tiles.size():
		var b := (_tiles[i] as Dictionary)["btn"] as Button
		_slide_in(b, Vector2(46.0, 0.0), 0.16 + 0.035 * float(i))


## 换到第 i 位：dir 1 = 往后翻（新的从右边来），-1 = 往前翻
func _goto(i: int, dir: int) -> void:
	i = posmod(i, ids.size())
	if i == cur or _busy:
		return
	_busy = true
	var old_ac := Kit.accent(str(ids[cur]))
	cur = i
	_set_panel(_panel_old, old_ac)
	_pm(_panel_old).set_shader_parameter("reveal", 1.0)
	_panel_old.visible = true
	_pm(_panel).set_shader_parameter("wipe_dir", -float(dir))
	_pm(_panel).set_shader_parameter("reveal", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _pm(_panel).set_shader_parameter("reveal", v), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _panel_old.visible = false)
	var out := create_tween()
	out.tween_property(_stage, "position:x", -float(dir) * 150.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out.parallel().tween_property(_stage, "modulate:a", 0.0, 0.1)
	out.tween_callback(func() -> void:
		_fig.set_hero(str(ids[cur]))
		_show_art()
		_stage.position.x = float(dir) * 200.0)
	out.tween_property(_stage, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	out.parallel().tween_property(_stage, "modulate:a", 1.0, 0.1)
	out.tween_callback(func() -> void:
		_busy = false
		var show: Dictionary = Kit.SHOW.get(str(ids[cur]), {})
		_fig.flourish(show.get("enter", [])))
	# 名牌翻面
	var nt := create_tween()
	nt.tween_property(_name_slab, "scale:x", 0.0, 0.09)
	nt.tween_callback(_refresh)
	nt.tween_property(_name_slab, "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	nt.parallel().tween_callback(_cascade)


func _on_roster(i: int) -> void:
	if i != cur:
		_goto(i, 1 if i > cur else -1)


func _on_go() -> void:
	picked = str(ids[cur])
	_go_state()
	_seal.visible = true
	_seal.scale = Vector2(2.4, 2.4)
	_seal.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_seal, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_seal, "modulate:a", 1.0, 0.08)
	var show: Dictionary = Kit.SHOW.get(picked, {})
	_fig.flourish(show.get("enter", []))


func _on_swipe(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_drag = true
			_drag_x0 = mb.position.x
		elif _drag:
			_drag = false
			var dx := mb.position.x - _drag_x0
			if absf(dx) >= 70.0:
				_goto(cur + (1 if dx < 0.0 else -1), 1 if dx < 0.0 else -1)
			else:
				_demo()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_LEFT:
			_goto(cur - 1, -1)
		KEY_RIGHT:
			_goto(cur + 1, 1)
		KEY_ENTER, KEY_SPACE:
			if not _go.disabled:
				_on_go()
		KEY_TAB:
			if not art.is_empty():
				set_art_mode(not use_art)
		KEY_ESCAPE:
			closed.emit()
