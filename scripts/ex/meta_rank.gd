extends Control
## 「境界」页（挂在 meta_ui.gd 的壳里；主城右上角第四颗入口）。2026-11-24 用户：「段位也单独独立一个入口」——
## 2026-11-25 主干解耦：主干回到吃丹修仙，没有搜打撤的段位了，这一页改成「境界」，版式 / 动画照旧，数据全走 raid_profile.gd / progression.gd：
##   左：一枚大徽记（按境界换颜色，底下几粒 = 这一境的第几层），背后星盘慢慢转；境界名（大字）、第几层、本层修为进度条；
##       修为到了瓶颈时进度条转朱砂，底下写渡劫要什么（破境丹 + Prog.break_cost 灵石，到修炼场渡劫）
##   右：六张战绩小牌（入境 / 撤离 / 陨落 / 单局最高 / 擂台胜 / 身家）+ 一行战力
##   底：八个境界一条横着的路（能左右划），走过的亮、没到的暗，当前那境有一圈金线，每一境底下写到了能做什么（元婴：开放沙海古墟 / 天工秘所）；
##       进来时自动滑到当前这一境
## 进场：徽记弹出来、进度条从零涨上去、数字滚动、底下那排一格格冒出来。只读存档，不改东西。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const NODE := Vector2(176.0, 196.0)
const CARD := Vector2(214.0, 112.0)
## 每一境到了能做什么（底下那条路上的小字；一行放不下用 \n 分两行）
const OPENS := ["初入仙途", "御器腾空", "遁光空战", "开放沙海古墟\n天工秘所", "借天地元气", "五行遁术", "法相合一", "大罡剑阵"]

var shell: Control
var start := ""

var _realm := 0
var _lv := 1
var _k := 0.0                    # 本层修为走了多少（0~1）
var _k_show := 0.0
var _cap := false                # 修为到了瓶颈
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
	_realm = Profile.realm()
	var cu := Profile.cult(_realm)
	_lv = int(cu[0])
	_cap = Prog.profile_at_cap() and _realm < Prog.REALMS - 1
	_k = 1.0 if _cap else clampf(float(cu[1]) / maxf(Prog.xp_need(_lv), 1.0), 0.0, 1.0)
	var col := MetaKit.realm_col(_realm)
	var step := clampi(_lv - _realm * Prog.LV_PER_REALM - 1, 0, 2) if _realm < Prog.REALMS - 1 else -1
	_ring = MetaKit.art("meta_ring", Vector2(560, 560), Color(col.lerp(MetaKit.GOLD, 0.4), 0.42))
	add_child(_ring)
	_crest = Control.new()
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crest.draw.connect(func() -> void:
		var c := _crest.size * 0.5
		_crest.draw_texture_rect(MetaKit.grad_glow(), Rect2(c - _crest.size * 0.75, _crest.size * 1.5), false, Color(col, 0.35))
		MetaKit.draw_realm_crest(_crest, c, _crest.size.x * 0.42, _realm, step, _t))
	add_child(_crest)
	_name = MetaKit.outlined(MetaKit.label("%s期" % str(Realm.LIST[_realm]["name"]), 68, col.lightened(0.25), true), 8)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_sum = MetaKit.outlined(MetaKit.label("", 26, MetaKit.TEXT), 5)
	_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sum)
	var in_realm := _lv - _realm * Prog.LV_PER_REALM
	if _realm >= Prog.REALMS - 1:
		_sum.text = "第 %d 层 · 修为再无瓶颈" % in_realm
	else:
		_sum.text = "第 %d 层 / 共 %d 层" % [in_realm, Prog.LV_PER_REALM]
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _bar.size)
		_bar.draw_style_box(MetaKit.box(Color(0.07, 0.065, 0.08, 0.85), Color(MetaKit.GOLD, 0.5), 1.5, 9.0), r)
		var w := (r.size.x - 6.0) * _k_show
		if w > 4.0:
			_bar.draw_style_box(MetaKit.box(MetaKit.CINNABAR if _cap else col, Color(0, 0, 0, 0), 0.0, 6.0), Rect2(3.0, 3.0, w, r.size.y - 6.0))
			_bar.draw_texture_rect(MetaKit.grad_up(), Rect2(3.0, 3.0, w, r.size.y - 6.0), false, Color(1, 1, 1, 0.35)))
	add_child(_bar)
	_next = MetaKit.outlined(MetaKit.label("", 23, MetaKit.TEXT_DIM), 5)
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_next)
	_next.text = _bottleneck_text() if _cap else ("本层修为 %s / %s" % [NumFmt.fmt(float(cu[1])), NumFmt.fmt(Prog.xp_need(_lv))])
	if _cap:
		_next.add_theme_color_override("font_color", MetaKit.GOLD.lightened(0.2))

	# 战绩
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 14)
	_cards.add_theme_constant_override("v_separation", 14)
	add_child(_cards)
	var st: Dictionary = Profile.stats()
	var rows := [["入境", str(int(st.get("raids", 0))), MetaKit.TEXT], ["撤离", str(int(st.get("out", 0))), MetaKit.JADE],
			["陨落", str(int(st.get("dead", 0))), MetaKit.BAD], ["单局最高", NumFmt.fmt(float(st.get("best", 0))), MetaKit.GOLD],
			["擂台胜", str(int(st.get("arena_wins", 0))), MetaKit.TEXT], ["身家", NumFmt.fmt(float(Profile.wealth())), MetaKit.GOLD]]
	for r: Array in rows:
		_cards.add_child(_card(str(r[0]), str(r[1]), r[2]))
	_note = MetaKit.outlined(MetaKit.label("战力 %s" % MetaKit.fmt_int(MetaKit.power(_realm, _lv, Profile.gear())), 26, MetaKit.GOLD.lightened(0.25)), 5)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)

	# 底下那条路：八个境界
	_path = ScrollContainer.new()
	_path.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_path.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_path)
	_path_box = Control.new()
	var n := Realm.LIST.size()
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


## 瓶颈时那一行：渡下一境要什么（破境丹有没有、灵石够不够）
func _bottleneck_text() -> String:
	var to := _realm + 1
	var key := str(Items.KEYS[to])
	var have := Profile.count(key)
	var cost := Prog.break_cost(to)
	return "修为已至瓶颈 · 需%s ×1（有 %d）+ 灵石 %s，到修炼场渡劫" % [key, have, NumFmt.fmt(float(cost))]


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
	# 星盘在上（徽记在它正中），名字、层数、进度条依次排在下面
	var tail := _name.size.y + _sum.size.y + 12.0 + 22.0 + 8.0 + _next.size.y - 14.0
	var rs := clampf(mid_h - tail, 200.0, 430.0)
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
	# 进度条从零涨上去
	MetaKit.tween(self).tween_method(func(v: float) -> void:
		_k_show = v
		_bar.queue_redraw(), 0.0, _k, 0.8).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 底下滑到当前这一境
	var want := maxf(20.0 + (float(_realm) + 0.5) * NODE.x - _path.size.x * 0.5, 0.0)
	MetaKit.tween(_path).tween_property(_path, "scroll_horizontal", int(want), 0.6).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	_ring.rotation = _t * 0.05
	_crest.queue_redraw()


## 境与境之间的连线：走过的金、没到的暗
func _draw_path() -> void:
	var y := 52.0
	for i in _nodes.size() - 1:
		var a := Vector2(20.0 + (float(i) + 0.5) * NODE.x + 40.0, y)
		var b := Vector2(20.0 + (float(i) + 1.5) * NODE.x - 40.0, y)
		_path_box.draw_line(a, b, Color(MetaKit.GOLD, 0.8) if i < _realm else Color(MetaKit.TEXT, 0.16), 2.0, true)


func _draw_node(nd: Control, i: int) -> void:
	var c := Vector2(NODE.x * 0.5, 52.0)
	var cur := i == _realm
	if cur:
		nd.draw_style_box(MetaKit.box(Color(0.2, 0.17, 0.12, 0.6), Color(MetaKit.GOLD, 0.8), 1.5, 14.0), Rect2(6.0, 2.0, NODE.x - 12.0, NODE.y - 4.0))
	MetaKit.draw_realm_crest(nd, c, 34.0 if not cur else 38.0, i, -1, _t if cur else 0.0, i > _realm)
	var f := MetaKit.font()
	var nm := "%s期" % str(Realm.LIST[i]["name"])
	var fs := 23
	var ts := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var col := MetaKit.realm_col(i).lightened(0.2) if i <= _realm else MetaKit.TEXT_FAINT
	var p := Vector2(c.x - ts.x * 0.5, 100.0 + f.get_ascent(fs))
	nd.draw_string_outline(f, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.04, 0.035, 0.04, 0.9))
	nd.draw_string(f, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var lines := str(OPENS[i]).split("\n")
	var ns := 19
	for li in lines.size():
		var tx := lines[li]
		var nts := f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, ns)
		var np := Vector2(c.x - nts.x * 0.5, 132.0 + float(li) * 26.0 + f.get_ascent(ns))
		var hi := i == 3      # 元婴那一格：新两关，金字
		var tc := (MetaKit.GOLD if hi else MetaKit.TEXT_DIM) if i <= _realm else Color(MetaKit.GOLD if hi else MetaKit.TEXT_FAINT, 0.8)
		nd.draw_string_outline(f, np, tx, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 5, Color(0.04, 0.035, 0.04, 0.9))
		nd.draw_string(f, np, tx, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, tc)


# ====================================================================
# 自检用
# ====================================================================

## 这一页显示的境界 / 层 / 是否瓶颈 / 瓶颈那一行
func info() -> Dictionary:
	return {"realm": _realm, "lv": _lv, "cap": _cap, "next": _next.text, "name": _name.text, "cards": _cards.get_child_count(), "nodes": _nodes.size()}
