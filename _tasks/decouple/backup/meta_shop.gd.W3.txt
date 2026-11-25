extends Control
## 「坊市」页（商店，挂在 meta_ui.gd 的壳里）。2026-11-24 用户：「商店也独立成一个单独的入口，重构这块的交互布局，美术」。
## 原来分在三个页签里的 坊市（灵石买装备 / 丹符）、黑市（仙玉）、商人（卖售卖物）并到这一页：
##   左：一列分类 —— 兵刃 / 法衣 / 丹药 / 符箓 / 法宝 / 黑市 / 出售；最底下一枚小牌写背包还剩几格（买的东西先进背包）
##   中：货架（大格子，底下一行价钱，买不起的价钱是红的）；「出售」那一栏是背包 + 仓库里能卖的东西，底下一排一键卖出
##   右：选中那件的大图标、名字、说明、手里有几个，下面「买 1 / 买 10 / 买入」或「卖出」
## 买到手图标飞进背包那枚小牌、灵石数字滚动；品质高的（史诗起）卖之前问一句。存档全走 ex_profile.gd。
## 自检用的接口：goto / select / press_action / action_texts / press_bulk。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const ExItemView := preload("res://scripts/ex/ex_item_view.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const RAIL_W := 206.0
const DETAIL_W := 352.0
const CORNER := 54.0
const GAP := 12.0
const COLS := 5
## 分类：[键, 名字, 图标]
const CATS := [["weapon", "兵刃", "ex_sword"], ["armor", "法衣", "ex_robe"], ["med", "丹药", "pill_heal"], ["throw", "符箓", "ex_talisman"],
		["chip", "法宝", "ex_mirror"], ["black", "黑市", "ring"], ["sell", "出售", "lingshi"]]

var shell: Control
var start := ""

var _cat := "weapon"
var _sel := -1                   # 货架上第几件
var _us := Vector2(1600, 900)
var _goods: Array = []           # 这一栏的货：[{item, price, cur（"ls" / "xy" / "sell"）, src, i}]
var _tiles: Array = []

var _rail: Control
var _cat_btns := {}
var _bag_chip: PanelContainer
var _bag_lab: Label
var _mid: Control
var _scroll: ScrollContainer
var _grid: GridContainer
var _bulk: HBoxContainer
var _detail: PanelContainer
var _d_box: VBoxContainer
var _acts: VBoxContainer
var _tile_w := 172.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start == "black" or start == "sell":
		_cat = start
	_build()
	_rebuild(false)


func _build() -> void:
	_rail = Control.new()
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rail)
	var y := 0.0
	for c: Array in CATS:
		var key := str(c[0])
		if key == "black":
			var dv := MetaKit.divider(RAIL_W, Color(MetaKit.GOLD, 0.5))
			dv.position = Vector2(0.0, y + 2.0)
			_rail.add_child(dv)
			y += 20.0
		var b := MetaKit.tab(str(c[1]), RAIL_W, 68.0, 27)
		b.icon = UiStyle.icon(str(c[2]))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.add_theme_constant_override("h_separation", 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = Vector2(0.0, y)
		b.size = Vector2(RAIL_W, 68.0)
		b.pressed.connect(goto.bind(key))
		_rail.add_child(b)
		_cat_btns[key] = b
		y += 78.0
	_bag_chip = PanelContainer.new()
	var bs := MetaKit.glass(12.0, 0.25).duplicate() as StyleBoxFlat
	bs.content_margin_left = 14.0
	bs.content_margin_right = 14.0
	bs.content_margin_top = 8.0
	bs.content_margin_bottom = 8.0
	_bag_chip.add_theme_stylebox_override("panel", bs)
	_bag_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(_bag_chip)
	_bag_lab = MetaKit.label("", 21, MetaKit.TEXT_DIM)
	_bag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bag_chip.add_child(_bag_lab)

	_mid = Control.new()
	_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mid)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mid.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_scroll.add_child(_grid)
	_bulk = HBoxContainer.new()
	_bulk.add_theme_constant_override("separation", 12)
	_mid.add_child(_bulk)

	_detail = PanelContainer.new()
	var s := MetaKit.glass(18.0, 0.32).duplicate() as StyleBoxFlat
	s.set_content_margin_all(20.0)
	_detail.add_theme_stylebox_override("panel", s)
	add_child(_detail)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_detail.add_child(v)
	_d_box = VBoxContainer.new()
	_d_box.add_theme_constant_override("separation", 8)
	_d_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_d_box)
	_acts = VBoxContainer.new()
	_acts.add_theme_constant_override("separation", 10)
	v.add_child(_acts)
	for i in 4:
		var c := MetaKit.art("meta_corner", Vector2(CORNER, CORNER), Color(MetaKit.GOLD, 0.85))
		c.flip_h = i % 2 == 1
		c.flip_v = i >= 2
		c.name = "Corner%d" % i
		add_child(c)


func layout(us: Vector2) -> void:
	_us = us
	var bottom := us.y - 18.0
	var dx := us.x - MARGIN - DETAIL_W - 6.0
	_detail.position = Vector2(dx, BAR_H + 12.0)
	_detail.size = Vector2(DETAIL_W, bottom - BAR_H - 20.0)
	for i in 4:
		var c := get_node("Corner%d" % i) as Control
		c.position = _detail.position + Vector2((DETAIL_W - CORNER + 11.0) if i % 2 == 1 else -11.0, (_detail.size.y - CORNER + 11.0) if i >= 2 else -11.0)
	_rail.position = Vector2(MARGIN, BAR_H + 4.0)
	_rail.size = Vector2(RAIL_W, bottom - BAR_H - 4.0)
	_bag_chip.size = Vector2(RAIL_W, _bag_chip.get_combined_minimum_size().y)
	_bag_chip.position = Vector2(0.0, _rail.size.y - _bag_chip.size.y)
	var mx := MARGIN + RAIL_W + 24.0
	var mw := dx - 24.0 - mx
	_mid.position = Vector2(mx, BAR_H + 4.0)
	_mid.size = Vector2(mw, bottom - BAR_H - 4.0)
	var bulk_h := 70.0 if _cat == "sell" else 0.0
	_scroll.position = Vector2(0.0, 0.0)
	_scroll.size = Vector2(mw, _mid.size.y - bulk_h)
	_bulk.position = Vector2(0.0, _mid.size.y - 60.0)
	_bulk.size = Vector2(mw - 14.0, 60.0)
	var tw := floorf((mw - 14.0 - float(COLS - 1) * GAP) / float(COLS))
	if absf(tw - _tile_w) > 0.5:
		_tile_w = tw
		for t: Variant in _tiles:
			(t as Control).custom_minimum_size = Vector2(_tile_w, _tile_h())


func _tile_h() -> float:
	return _tile_w + 18.0


func enter() -> void:
	MetaKit.slide_in(_rail, Vector2(-70, 0), 0.04)
	MetaKit.slide_in(_mid, Vector2(0, 46), 0.08)
	MetaKit.slide_in(_detail, Vector2(80, 0), 0.14)
	for i in 4:
		MetaKit.fade_in(get_node("Corner%d" % i) as CanvasItem, 0.34, 0.3)
	_cascade(0.16)


# ====================================================================
# 数据
# ====================================================================

func _load_goods() -> void:
	_goods.clear()
	match _cat:
		"black":
			for g: Dictionary in ExData.BLACK:
				_goods.append({"item": ExData.make(str(g["id"])), "price": int(g["price"]), "cur": "xy", "id": str(g["id"])})
		"sell":
			for src: String in ["bag", "stash"]:
				var l := ExProfile.bag() if src == "bag" else ExProfile.stash()
				for i in l.size():
					var it: Dictionary = l[i]
					if ExData.is_sellable(it) and ExData.can_sell(it):
						_goods.append({"item": it, "price": ExData.value_of(it), "cur": "sell", "src": src, "i": i})
		_:
			for g2: Dictionary in ExData.shop(_cat):
				_goods.append({"item": ExData.make(str(g2["id"])), "price": int(g2["price"]), "cur": "ls", "id": str(g2["id"])})


func _have(id: String) -> int:
	if id == "voucher":
		return ExProfile.vouchers()
	return ExData.count_id(ExProfile.bag(), id) + ExData.count_id(ExProfile.stash(), id)


func _can_pay(g: Dictionary, n := 1) -> bool:
	if str(g["cur"]) == "xy":
		return ExProfile.xianyu() >= int(g["price"]) * n
	return ExProfile.lingshi() >= int(g["price"]) * n


func _price_text(g: Dictionary) -> String:
	if str(g["cur"]) == "xy":
		return "%d 仙玉" % int(g["price"])
	return NumFmt.fmt(float(g["price"]))


# ====================================================================
# 刷新
# ====================================================================

func _rebuild(animate: bool) -> void:
	_load_goods()
	if _sel >= _goods.size():
		_sel = -1
	for k: String in _cat_btns:
		(_cat_btns[k] as Button).button_pressed = k == _cat
	if _sel < 0 and not _goods.is_empty():
		_sel = 0          # 一进来 / 换一栏 / 卖空了当前这件：自动选第一件，右边不空着
	_bag_lab.text = "背包 %d/%d" % [ExProfile.bag().size(), ExProfile.BAG_CAP]
	for c in _grid.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	_tiles.clear()
	_grid.columns = COLS
	for i in _goods.size():
		var g: Dictionary = _goods[i]
		var t := MetaKit.tile(g["item"], Vector2(_tile_w, _tile_h()), i == _sel, _price_text(g))
		if str(g["cur"]) == "sell":
			t.note_col = MetaKit.GOLD
			t.corner = ("背包" if str(g["src"]) == "bag" else "仓库") + (("×%d" % int((g["item"] as Dictionary).get("n", 1))) if int((g["item"] as Dictionary).get("n", 1)) > 1 else "")
		else:
			t.note_col = MetaKit.GOLD if _can_pay(g) else MetaKit.BAD
			if str(g["cur"]) == "xy":
				t.note_col = MetaKit.JADE if _can_pay(g) else MetaKit.BAD
		t.pressed.connect(select.bind(i))
		_grid.add_child(t)
		_tiles.append(t)
	if _goods.is_empty():
		var none := MetaKit.label("没有可卖的东西", 23, MetaKit.TEXT_FAINT)
		none.custom_minimum_size = Vector2(_tile_w * float(COLS), 120.0)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.columns = 1
		_grid.add_child(none)
	_rebuild_bulk()
	_rebuild_detail()
	shell.call("refresh_money")
	if _us.x > 0.0:
		layout(_us)
	if animate:
		_cascade(0.0)


func _cascade(delay: float) -> void:
	MetaKit.cascade(_tiles.slice(0, 30), 0.016, delay)


## 出售那一栏底下：一键卖背包 / 仓库 / 全部
func _rebuild_bulk() -> void:
	for c in _bulk.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	_bulk.visible = _cat == "sell"
	if _cat != "sell":
		return
	for src: String in ["bag", "stash", "all"]:
		var sm := ExProfile.sellable_sum(src)
		var where := {"bag": "背包", "stash": "仓库", "all": "全部"}[src] as String
		var b := MetaKit.button("卖%s %s" % [where, NumFmt.fmt(float(sm[1]))], 10.0, 58.0, "primary" if src == "all" else "gold", 23)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = int(sm[0]) == 0
		b.set_meta("src", src)
		b.pressed.connect(_do_bulk.bind(src))
		_bulk.add_child(b)


func _clear(box: Node) -> void:
	for c in box.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()


func _rebuild_detail() -> void:
	_clear(_d_box)
	_clear(_acts)
	var w := DETAIL_W - 40.0
	var has := _sel >= 0 and _sel < _goods.size()
	_detail.visible = has
	for ci in 4:
		(get_node("Corner%d" % ci) as CanvasItem).visible = has
	if not has:
		_sel = -1
		return
	var g: Dictionary = _goods[_sel]
	var it: Dictionary = g["item"]
	var q := int(it.get("q", 1))
	var qc := MetaKit.q_col(q)
	var top := Control.new()
	top.custom_minimum_size = Vector2(w, 132.0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_box.add_child(top)
	var glow := TextureRect.new()
	glow.texture = MetaKit.grad_glow()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = Vector2(210, 210)
	glow.position = Vector2((w - 210.0) * 0.5, -40.0)
	glow.modulate = Color(qc, 0.5)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(glow)
	var ic := TextureRect.new()
	ic.texture = ExItemView.icon(it)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size = Vector2(120, 120)
	ic.position = Vector2((w - 120.0) * 0.5, 6.0)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ic)
	MetaKit.pop(ic, 1.25)
	var n := maxi(int(it.get("n", 1)), 1)
	var nm := MetaKit.label(str(it.get("name", "")) + (("  ×%d" % n) if n > 1 else ""), 34, qc.lightened(0.2), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(w, 0)
	_d_box.add_child(nm)
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 8)
	tags.add_child(MetaKit.tag(ExData.q_name(q), qc))
	tags.add_child(MetaKit.tag(ExData.kind_name(it), MetaKit.TEXT_DIM))
	_d_box.add_child(tags)
	_d_box.add_child(MetaKit.divider(w))
	_d_box.add_child(MetaKit.para(ExData.desc(it).replace("　", "
"), 22, w, MetaKit.TEXT))      # 说明里用全角空格隔开的几项：一项一行
	MetaKit.fade_in(_d_box, 0.0, 0.16)
	if str(g["cur"]) == "sell":
		var val := "值 %s 灵石" % NumFmt.fmt(float(ExData.unit_value(it)))
		if n > 1:
			val = "每个 %s，共 %s 灵石" % [NumFmt.fmt(float(ExData.unit_value(it))), NumFmt.fmt(float(ExData.value_of(it)))]
		_d_box.add_child(MetaKit.para(val, 21, w, MetaKit.GOLD))
		if n > 1:
			_act("卖 1 个　%s" % NumFmt.fmt(float(ExData.unit_value(it))), "gold", _do_sell.bind(1), false)
		_act(("全部卖出　%s" if n > 1 else "卖出　%s") % NumFmt.fmt(float(ExData.value_of(it))), "primary", _do_sell.bind(-1), false)
		return
	_d_box.add_child(MetaKit.para("已有 %d" % _have(str(g["id"])), 21, w, MetaKit.TEXT_DIM))
	if str(g["cur"]) == "xy":
		_act("买入　%d 仙玉" % int(g["price"]), "primary", _do_buy.bind(1), not _can_pay(g))
	else:
		_act("买 1　%s" % NumFmt.fmt(float(g["price"])), "primary", _do_buy.bind(1), not _can_pay(g))
		if ExData.stacks(it):
			_act("买 10　%s" % NumFmt.fmt(float(int(g["price"]) * 10)), "gold", _do_buy.bind(10), not _can_pay(g, 10))


func _act(text: String, kind: String, fn: Callable, off: bool) -> void:
	var b := MetaKit.button(text, DETAIL_W - 40.0, 62.0, kind, 25)
	b.disabled = off
	b.pressed.connect(fn)
	_acts.add_child(b)


# ====================================================================
# 操作
# ====================================================================

## 翻到哪一栏：weapon / armor / med / throw / chip / black / sell
func goto(cat: String) -> void:
	if not _cat_btns.has(cat):
		return
	if cat == _cat:
		(_cat_btns[cat] as Button).button_pressed = true
		return
	_cat = cat
	_sel = -1
	shell.call("click", 1.1)
	_rebuild(true)
	_scroll.scroll_vertical = 0


func select(i: int) -> void:
	_sel = i
	shell.call("click")
	for k in _tiles.size():
		(_tiles[k] as MetaKit.Tile).set_selected(k == _sel)
	_rebuild_detail()


func _center(c: Control) -> Vector2:
	return c.get_global_transform() * (c.size * 0.5)


func _do_buy(n: int) -> void:
	if _sel < 0:
		return
	var g: Dictionary = _goods[_sel]
	var it: Dictionary = g["item"]
	var e := ExProfile.buy_black(str(g["id"])) if str(g["cur"]) == "xy" else ExProfile.buy(str(g["id"]), n)
	if e != "":
		shell.call("warn", e)
		return
	var from: Control = _tiles[_sel]
	var p0 := _center(from)
	var keep := _sel
	_rebuild(false)
	_sel = keep
	for k in _tiles.size():
		(_tiles[k] as MetaKit.Tile).set_selected(k == _sel)
	_rebuild_detail()
	shell.call("sfx", "pickup", -8.0, 1.0)
	shell.call("fly", ExItemView.icon(it), p0, _center(_bag_chip), func() -> void: MetaKit.pop(_bag_chip, 1.1))


func _do_sell(cnt: int) -> void:
	if _sel < 0:
		return
	var g: Dictionary = _goods[_sel]
	var it: Dictionary = g["item"]
	var n := maxi(int(it.get("n", 1)), 1)
	var gain := ExData.unit_value(it) * (n if cnt < 0 else cnt)
	var id := str(it.get("id", ""))
	var go := func() -> void:
		var e := ExProfile.sell(str(g["src"]), int(g["i"]), cnt)
		if e != "":
			shell.call("warn", e)
			return
		var keep := _sel
		_rebuild(false)
		# 还是同一样东西（一叠卖掉一个）就接着选它
		_sel = keep if keep < _goods.size() and str((_goods[keep]["item"] as Dictionary).get("id", "")) == id else -1
		for k in _tiles.size():
			(_tiles[k] as MetaKit.Tile).set_selected(k == _sel)
		_rebuild_detail()
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "+%s 灵石" % NumFmt.fmt(float(gain)))
	if ExData.sell_confirm(it):
		shell.call("confirm", "%s 是%s之物，卖出得 %s 灵石\n确定卖掉吗？" % [str(it.get("name", "")), ExData.q_name(int(it.get("q", 1))), NumFmt.fmt(float(gain))],
				"卖出", go)
	else:
		go.call()


## 一键卖出：里面有史诗以上的先问一句
func _do_bulk(src: String) -> void:
	var sm := ExProfile.sellable_sum(src)
	if int(sm[0]) == 0:
		return
	var where := {"bag": "背包里", "stash": "仓库里", "all": "背包和仓库里"}[src] as String
	var go := func() -> void:
		var gain := ExProfile.sell_all_sellables(src)
		_sel = -1
		_rebuild(true)
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "+%s 灵石" % NumFmt.fmt(float(gain)))
	if int(sm[2]) > 0:
		shell.call("confirm", "%s的售卖物一共 %d 堆、%s 灵石\n其中 %d 堆是史诗以上的宝物\n确定全卖掉吗？" % [where, int(sm[0]), NumFmt.fmt(float(sm[1])), int(sm[2])],
				"全部卖出", go)
	else:
		go.call()


# ====================================================================
# 自检用
# ====================================================================

func press_action(prefix: String) -> bool:
	for c in _acts.get_children():
		if c is Button and not (c as Button).disabled and (c as Button).text.begins_with(prefix) and not c.is_queued_for_deletion():
			(c as Button).pressed.emit()
			return true
	return false


func action_texts() -> Array:
	var out: Array = []
	for c in _acts.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


## 点底下的一键卖出（bag / stash / all）
func press_bulk(src: String) -> bool:
	for c in _bulk.get_children():
		if c is Button and str(c.get_meta("src", "")) == src and not (c as Button).disabled and not c.is_queued_for_deletion():
			(c as Button).pressed.emit()
			return true
	return false


func cat_key() -> String:
	return _cat


## 货架上第一件 id 是 id 的货（没有 = -1）
func find_id(id: String) -> int:
	for i in _goods.size():
		if str((_goods[i]["item"] as Dictionary).get("id", "")) == id:
			return i
	return -1
