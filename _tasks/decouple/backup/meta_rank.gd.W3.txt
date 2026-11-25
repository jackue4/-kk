extends Control
## 「段位」页（挂在 meta_ui.gd 的壳里）。2026-11-24 用户：「段位也单独独立一个入口」。
##   左：一枚大徽记（现画的矢量图，按档换样子和颜色：未入流 / 炼气 / 筑基 / 结丹 / 元婴 / 化神，底下几粒 = 第几阶），背后星盘慢慢转；
##       段位名（大字）、累计带出多少灵石、到下一档的进度条
##   右：六张战绩小牌（入境 / 撤离 / 陨落 / 击杀 / 单局最高 / 撤离率）+ 一句晋升给什么
##   底：十四档一条横着的路（能左右划），走过的亮、没到的暗，当前那档有一圈金线；进来时自动滑到当前这一档
## 进场：徽记弹出来、进度条从零涨上去、数字滚动、底下那排一格格冒出来。只读存档，不改东西。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const NODE := Vector2(148.0, 168.0)
const CARD := Vector2(214.0, 112.0)

var shell: Control
var start := ""

var _rank := 0
var _total := 0
var _k := 0.0                    # 到下一档走了多少（0~1）
var _k_show := 0.0
var _t := 0.0
var _us := Vector2(1600, 900)

var _ring: TextureRect
var _crest: Control
var _name: Label
var _sum: Label
var _bar: Control
var _next: Label
var _cards: GridContainer
var _note: Label
var _path: ScrollContainer
var _path_box: Control
var _nodes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank = ExProfile.rank()
	_total = ExProfile.extract_total()
	var need := ExData.rank_next_need(_rank)
	if need > 0:
		var base := int(ExData.RANK_NEED[_rank])
		_k = clampf(float(_total - base) / maxf(float(need - base), 1.0), 0.0, 1.0)
	else:
		_k = 1.0
	var col := MetaKit.tier_col(_rank)
	_ring = MetaKit.art("meta_ring", Vector2(560, 560), Color(col.lerp(MetaKit.GOLD, 0.4), 0.42))
	add_child(_ring)
	_crest = Control.new()
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crest.draw.connect(func() -> void:
		var c := _crest.size * 0.5
		_crest.draw_texture_rect(MetaKit.grad_glow(), Rect2(c - _crest.size * 0.75, _crest.size * 1.5), false, Color(col, 0.35))
		MetaKit.draw_crest(_crest, c, _crest.size.x * 0.42, _rank, _t))
	add_child(_crest)
	_name = MetaKit.outlined(MetaKit.label(ExData.rank_name(_rank), 68, col.lightened(0.25), true), 8)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_sum = MetaKit.outlined(MetaKit.label("", 26, MetaKit.TEXT), 5)
	_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sum)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _bar.size)
		_bar.draw_style_box(MetaKit.box(Color(0.07, 0.065, 0.08, 0.85), Color(MetaKit.GOLD, 0.5), 1.5, 9.0), r)
		var w := (r.size.x - 6.0) * _k_show
		if w > 4.0:
			_bar.draw_style_box(MetaKit.box(col, Color(0, 0, 0, 0), 0.0, 6.0), Rect2(3.0, 3.0, w, r.size.y - 6.0))
			_bar.draw_texture_rect(MetaKit.grad_up(), Rect2(3.0, 3.0, w, r.size.y - 6.0), false, Color(1, 1, 1, 0.35)))
	add_child(_bar)
	_next = MetaKit.outlined(MetaKit.label("", 23, MetaKit.TEXT_DIM), 5)
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_next)
	_next.text = ("距 %s 还差 %s 灵石" % [ExData.rank_name(_rank + 1), NumFmt.fmt(float(need - _total))]) if need > 0 else "已至最高段位"

	# 战绩
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 14)
	_cards.add_theme_constant_override("v_separation", 14)
	add_child(_cards)
	var st: Dictionary = ExProfile.data().get("stats", {})
	var raids := int(st.get("raids", 0))
	var out := int(st.get("out", 0))
	var rows := [["入境", str(raids), MetaKit.TEXT], ["撤离", str(out), MetaKit.JADE], ["陨落", str(int(st.get("dead", 0))), MetaKit.BAD],
			["击杀", str(int(st.get("kills", 0))), MetaKit.TEXT], ["单局最高", NumFmt.fmt(float(st.get("best", 0))), MetaKit.GOLD],
			["撤离率", ("%d%%" % int(roundf(100.0 * float(out) / float(raids)))) if raids > 0 else "—", MetaKit.TEXT]]
	for r: Array in rows:
		_cards.add_child(_card(str(r[0]), str(r[1]), r[2]))
	_note = MetaKit.outlined(MetaKit.label("每晋升一档得 %d 仙玉" % ExData.XIANYU_RANK, 21, MetaKit.TEXT_DIM), 5)
	_note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	add_child(_note)

	# 底下那条路
	_path = ScrollContainer.new()
	_path.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_path.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_path)
	_path_box = Control.new()
	var n := ExData.RANK_NAMES.size()
	_path_box.custom_minimum_size = Vector2(float(n) * NODE.x + 40.0, NODE.y)
	_path_box.draw.connect(_draw_path)
	_path.add_child(_path_box)
	for i in n:
		var nd := Control.new()
		nd.custom_minimum_size = NODE
		nd.size = NODE
		nd.position = Vector2(20.0 + float(i) * NODE.x, 0.0)
		nd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nd.draw.connect(_draw_node.bind(nd, i))
		_path_box.add_child(nd)
		_nodes.append(nd)


func _card(title: String, value: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := MetaKit.glass(14.0, 0.25).duplicate() as StyleBoxFlat
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 12.0
	s.content_margin_bottom = 12.0
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = CARD
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(MetaKit.label(title, 21, MetaKit.TEXT_DIM))
	v.add_child(MetaKit.label(value, 38, col))
	return p


func layout(us: Vector2) -> void:
	_us = us
	var bottom := us.y - 18.0
	var path_y := bottom - NODE.y
	_path.position = Vector2(MARGIN, path_y)
	_path.size = Vector2(us.x - MARGIN * 2.0, NODE.y)
	var top := BAR_H + 8.0
	var mid_h := path_y - top - 10.0
	# 右：战绩两列
	var cw := CARD.x * 2.0 + 14.0
	var cx0 := us.x - MARGIN - cw - 40.0
	_cards.size = _cards.get_combined_minimum_size()
	_note.custom_minimum_size = Vector2(cw, 0.0)
	_note.size = Vector2(cw, _note.get_minimum_size().y)
	var block_h := _cards.size.y + 16.0 + _note.size.y
	_cards.position = Vector2(cx0, top + maxf((mid_h - block_h) * 0.5, 0.0))
	_note.position = Vector2(cx0, _cards.position.y + _cards.size.y + 16.0)
	# 左：徽记 + 名字 + 进度
	var lw := cx0 - MARGIN - 40.0
	var lc := MARGIN + lw * 0.5
	_name.size = Vector2(lw, _name.get_minimum_size().y)
	_sum.size = Vector2(lw, _sum.get_minimum_size().y)
	_next.size = Vector2(lw, _next.get_minimum_size().y)
	# 星盘在上（徽记在它正中），名字、累计、进度条依次排在下面
	var tail := _name.size.y + _sum.size.y + 12.0 + 22.0 + 8.0 + _next.size.y - 14.0
	var rs := clampf(mid_h - tail, 240.0, 430.0)
	var cs := rs * 0.56
	var y := top + maxf((mid_h - rs - tail) * 0.5, 0.0)
	_ring.size = Vector2(rs, rs)
	_ring.pivot_offset = _ring.size * 0.5
	_ring.position = Vector2(lc - rs * 0.5, y)
	_crest.size = Vector2(cs, cs)
	_crest.pivot_offset = _crest.size * 0.5
	_crest.position = Vector2(lc - cs * 0.5, y + (rs - cs) * 0.5)
	y += rs - 14.0
	_name.position = Vector2(MARGIN, y)
	y += _name.size.y
	_sum.position = Vector2(MARGIN, y)
	y += _sum.size.y + 12.0
	var bw := minf(lw - 60.0, 560.0)
	_bar.size = Vector2(bw, 22.0)
	_bar.position = Vector2(lc - bw * 0.5, y)
	y += 30.0
	_next.position = Vector2(MARGIN, y)


func enter() -> void:
	MetaKit.fade_in(_ring, 0.05, 0.5)
	_crest.scale = Vector2(0.4, 0.4)
	_crest.modulate.a = 0.0
	var t := MetaKit.tween(_crest)
	t.set_parallel(true)
	t.tween_property(_crest, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	t.tween_property(_crest, "modulate:a", 1.0, 0.2).set_delay(0.06)
	MetaKit.slide_in(_name, Vector2(0, 30), 0.18)
	MetaKit.slide_in(_sum, Vector2(0, 30), 0.24)
	MetaKit.fade_in(_bar, 0.28)
	MetaKit.fade_in(_next, 0.34)
	MetaKit.slide_in(_cards, Vector2(80, 0), 0.12)
	MetaKit.fade_in(_note, 0.4)
	MetaKit.slide_in(_path, Vector2(0, 60), 0.16)
	MetaKit.cascade(_nodes, 0.03, 0.26)
	# 进度条从零涨上去、累计数字滚上去
	MetaKit.tween(self).tween_method(func(v: float) -> void:
		_k_show = v
		_bar.queue_redraw(), 0.0, _k, 0.8).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	MetaKit.tween(_sum).tween_method(func(v: float) -> void: _sum.text = "累计带出 %s 灵石" % NumFmt.fmt(v), 0.0, float(_total), 0.8).set_delay(0.2).set_trans(
			Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 底下滑到当前这一档
	var want := maxf(20.0 + (float(_rank) + 0.5) * NODE.x - _path.size.x * 0.5, 0.0)
	MetaKit.tween(_path).tween_property(_path, "scroll_horizontal", int(want), 0.6).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	_ring.rotation = _t * 0.05
	_crest.queue_redraw()


## 档与档之间的连线：走过的金、没到的暗
func _draw_path() -> void:
	var y := 52.0
	for i in _nodes.size() - 1:
		var a := Vector2(20.0 + (float(i) + 0.5) * NODE.x + 40.0, y)
		var b := Vector2(20.0 + (float(i) + 1.5) * NODE.x - 40.0, y)
		_path_box.draw_line(a, b, Color(MetaKit.GOLD, 0.8) if i < _rank else Color(MetaKit.TEXT, 0.16), 2.0, true)


func _draw_node(nd: Control, i: int) -> void:
	var c := Vector2(NODE.x * 0.5, 52.0)
	var cur := i == _rank
	if cur:
		nd.draw_style_box(MetaKit.box(Color(0.2, 0.17, 0.12, 0.6), Color(MetaKit.GOLD, 0.8), 1.5, 14.0), Rect2(6.0, 2.0, NODE.x - 12.0, NODE.y - 4.0))
	MetaKit.draw_crest(nd, c, 34.0 if not cur else 38.0, i, _t if cur else 0.0, i > _rank)
	var f := MetaKit.font()
	var nm := ExData.rank_name(i)
	var fs := 22
	var ts := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var col := MetaKit.tier_col(i).lightened(0.2) if i <= _rank else MetaKit.TEXT_FAINT
	var p := Vector2(c.x - ts.x * 0.5, 104.0 + f.get_ascent(fs))
	nd.draw_string_outline(f, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.04, 0.035, 0.04, 0.9))
	nd.draw_string(f, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var need := NumFmt.fmt(float(ExData.RANK_NEED[i])) if i > 0 else "起步"
	var ns := 19
	var nts := f.get_string_size(need, HORIZONTAL_ALIGNMENT_LEFT, -1, ns)
	var np := Vector2(c.x - nts.x * 0.5, 134.0 + f.get_ascent(ns))
	nd.draw_string_outline(f, np, need, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 5, Color(0.04, 0.035, 0.04, 0.9))
	nd.draw_string(f, np, need, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color(MetaKit.GOLD, 0.9) if i <= _rank else Color(MetaKit.TEXT_FAINT, 0.8))
