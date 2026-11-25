extends Control
## 「坊市」页（商店，挂在 meta_ui.gd 的壳里）。2026-11-24 用户：「商店也独立成一个单独的入口，重构这块的交互布局，美术」。
## 2026-11-25 主干解耦：改成修仙版坊市，数据全走 raid_profile.gd / raid_items.gd（老洞府 abode_ui.gd 的坊市 + 丹房 + 出售并在这一页），只用灵石：
##   左：一列分类 —— 丹药 / 符箓 / 法宝 / 破境丹（货都来自 Items.shop()）｜丹房（Items.recipes()）/ 储物戒（扩格）/ 出售；最底下一枚小牌写仓库占了几格（买的东西进仓库）
##   中：货架（大格子，底下一行价钱，买不起的价钱是红的）；丹房那一栏底下写的是炼制费；「出售」那一栏是仓库里值钱的东西（一样的叠成一格），底下一颗一键出售
##   右：选中那件的大图标、名字、说明、仓库里有几个，下面「买 1 / 买 10」「炼制」「扩到 N 格」或「卖出 / 卖出这一摞」
## 买到手图标飞进仓库那枚小牌、灵石数字滚动；古宝以上 / 破境丹卖之前问一句；一键出售先问一句（件数、总价）。
## 自检用的接口：goto / select / press_action / action_texts / press_bulk / cat_key / find_id（按名字找）。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")
const Abode := preload("res://scripts/abode_ui.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const RAIL_W := 206.0
const DETAIL_W := 352.0
const CORNER := 54.0
const GAP := 12.0
const COLS := 5
## 分类：[键, 名字, 图标]。前四栏是 Items.shop() 按物品种类分的；"|" = 一道分隔线
const CATS := [["pill", "丹药", "pill_heal"], ["tool", "符箓", "tool"], ["gear", "法宝", "gear"], ["key", "破境丹", "key_1"], ["|", "", ""],
		["alchemy", "丹房", "pill_0"], ["ring", "储物戒", "ring"], ["sell", "出售", "lingshi"]]

var shell: Control
var start := ""

var _cat := "pill"
var _sel := -1                   # 货架上第几件
var _us := Vector2(1600, 900)
var _goods: Array = []           # 这一栏的货：[{item, price, cur（"ls" 买 / "craft" 炼 / "ring" 扩格 / "sell" 卖）, good / recipe / i, n, key}]
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
	if start == "sell" or start == "alchemy" or start == "ring":
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
		if key == "|":
			var dv := MetaKit.divider(RAIL_W, Color(MetaKit.GOLD, 0.5))
			dv.position = Vector2(0.0, y + 2.0)
			_rail.add_child(dv)
			y += 20.0
			continue
		var b := MetaKit.tab(str(c[1]), RAIL_W, 64.0, 27)
		b.icon = UiStyle.icon(str(c[2]))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.add_theme_constant_override("h_separation", 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = Vector2(0.0, y)
		b.size = Vector2(RAIL_W, 64.0)
		b.pressed.connect(goto.bind(key))
		_rail.add_child(b)
		_cat_btns[key] = b
		y += 72.0
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

## 储物戒那一栏格子里摆的「物品」（只为了画一格：图标 icon_ring，品阶色按格数走）
static func _ring_item() -> Dictionary:
	var c := Profile.ring_cap()
	return {"kind": "ring", "name": "储物戒 %d 格" % c, "tier": clampi(c - 1, 0, 4)}


func _load_goods() -> void:
	_goods.clear()
	match _cat:
		"alchemy":
			for r: Dictionary in Items.recipes():
				_goods.append({"item": r["out"], "price": int(r["cost"]), "cur": "craft", "recipe": r})
		"ring":
			_goods.append({"item": _ring_item(), "price": Profile.ring_next_price(), "cur": "ring"})
		"sell":
			var st := Profile.stash()
			for row: Array in Abode._stacks(st):
				var it: Dictionary = st[int(row[0])]
				if int(it.get("value", 0)) > 0:
					_goods.append({"item": it, "price": int(it.get("value", 0)) * int(row[1]), "cur": "sell", "i": int(row[0]), "n": int(row[1]),
							"key": Abode._stack_key(it)})
		_:
			for g: Dictionary in Items.shop():
				if str((g["item"] as Dictionary).get("kind", "")) == _cat:
					_goods.append({"item": g["item"], "price": int(g["price"]), "cur": "ls", "good": g})


func _have(name: String) -> int:
	return Profile.count(name)


func _can_pay(g: Dictionary, n := 1) -> bool:
	if str(g["cur"]) == "craft":
		return Profile.can_craft(g["recipe"])
	return int(g["price"]) > 0 and Profile.lingshi() >= int(g["price"]) * n


func _price_text(g: Dictionary) -> String:
	if str(g["cur"]) == "ring" and int(g["price"]) <= 0:
		return "已是最大"
	return NumFmt.fmt(float(g["price"]))


## 一键出售会卖掉的东西（和 Profile.sell_junk 一个口径：凡品法宝、灵材、服不了的本境丹）：[件数, 灵石]
static func _junk_preview() -> Array:
	var cur := Profile.realm()
	var n := 0
	var v := 0
	for it: Dictionary in Profile.stash():
		var k := str(it.get("kind", ""))
		var dead_pill := k == "pill" and it.has("realm") and not it.has("min_realm") and int(it["realm"]) < cur
		if (k == "gear" and int(it.get("tier", 0)) == 0) or k == "mat" or dead_pill:
			n += 1
			v += int(it.get("value", 0))
	return [n, v]


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
	_bag_lab.text = "仓库 %d/%d" % [Profile.stash_slots(), Profile.STASH_CAP]
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
			if int(g["n"]) > 1:
				t.corner = "×%d" % int(g["n"])
		else:
			t.note_col = MetaKit.GOLD if _can_pay(g) else MetaKit.BAD
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


## 出售那一栏底下：一键出售（凡品法宝、灵材、服不了的本境丹）
func _rebuild_bulk() -> void:
	for c in _bulk.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	_bulk.visible = _cat == "sell"
	if _cat != "sell":
		return
	var jp := _junk_preview()
	var b := MetaKit.button("一键出售 凡品法宝 · 灵材 · 过期丹　%s" % NumFmt.fmt(float(jp[1])), 10.0, 58.0, "primary", 23)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = int(jp[0]) == 0
	b.set_meta("src", "junk")
	b.pressed.connect(_do_bulk)
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
	var qc := MetaKit.item_col(it)
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
	ic.texture = MetaKit.icon(it)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size = Vector2(120, 120)
	ic.position = Vector2((w - 120.0) * 0.5, 6.0)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ic)
	MetaKit.pop(ic, 1.25)
	var cur := str(g["cur"])
	var n := int(g.get("n", 1))
	var nm := MetaKit.label(str(it.get("name", "")) + (("  ×%d" % n) if n > 1 else ""), 34, qc.lightened(0.2), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(w, 0)
	_d_box.add_child(nm)
	if cur != "ring":
		var tags := HBoxContainer.new()
		tags.alignment = BoxContainer.ALIGNMENT_CENTER
		tags.add_theme_constant_override("separation", 8)
		var tw := Items.tier_word(it)
		if tw != "" and tw != MetaKit.kind_name(it):      # 品阶「法宝」和种类「法宝」同名时只写一个
			tags.add_child(MetaKit.tag(tw, qc))
		tags.add_child(MetaKit.tag(MetaKit.kind_name(it), MetaKit.TEXT_DIM))
		_d_box.add_child(tags)
	_d_box.add_child(MetaKit.divider(w))
	MetaKit.fade_in(_d_box, 0.0, 0.16)
	match cur:
		"ring":
			_d_box.add_child(MetaKit.para("放在储物戒里的东西陨落也不会丢", 22, w, MetaKit.TEXT))
			var p := int(g["price"])
			if p > 0:
				_act("扩到 %d 格　%s" % [Profile.ring_cap() + 1, NumFmt.fmt(float(p))], "primary", _do_ring, Profile.lingshi() < p)
			else:
				_act("储物戒已是最大", "ghost", _do_ring, true)
			return
		"craft":
			_d_box.add_child(MetaKit.para(Items.desc(it).replace("；", "\n"), 22, w, MetaKit.TEXT))
			var need: Dictionary = (g["recipe"] as Dictionary)["need"]
			for k: String in need.keys():
				var have := Profile.count(k)
				_d_box.add_child(MetaKit.para("%s　%d / %d" % [k, have, int(need[k])], 22, w, MetaKit.JADE if have >= int(need[k]) else MetaKit.BAD))
			_d_box.add_child(MetaKit.para("仓库里已有 %d" % _have(str(it.get("name", ""))), 21, w, MetaKit.TEXT_DIM))
			_act("炼制　%s" % NumFmt.fmt(float(g["price"])), "primary", _do_craft, not _can_pay(g))
			return
		"sell":
			_d_box.add_child(MetaKit.para(Items.desc(it).replace("；", "\n"), 22, w, MetaKit.TEXT))
			var unit := int(it.get("value", 0))
			var val := "值 %s 灵石" % NumFmt.fmt(float(unit))
			if n > 1:
				val = "每个 %s，共 %s 灵石" % [NumFmt.fmt(float(unit)), NumFmt.fmt(float(unit * n))]
			_d_box.add_child(MetaKit.para(val, 21, w, MetaKit.GOLD))
			if n > 1:
				_act("卖 1 个　%s" % NumFmt.fmt(float(unit)), "gold", _do_sell.bind(1), false)
			_act(("全部卖出　%s" if n > 1 else "卖出　%s") % NumFmt.fmt(float(unit * n)), "primary", _do_sell.bind(-1), false)
			return
	_d_box.add_child(MetaKit.para(Items.desc(it).replace("；", "\n"), 22, w, MetaKit.TEXT))
	_d_box.add_child(MetaKit.para("仓库里已有 %d" % _have(str(it.get("name", ""))), 21, w, MetaKit.TEXT_DIM))
	_act("买 1　%s" % NumFmt.fmt(float(g["price"])), "primary", _do_buy.bind(1), not _can_pay(g))
	if str(it.get("kind", "")) != "gear":
		_act("买 10　%s" % NumFmt.fmt(float(int(g["price"]) * 10)), "gold", _do_buy.bind(10), not _can_pay(g, 10))


func _act(text: String, kind: String, fn: Callable, off: bool) -> void:
	var b := MetaKit.button(text, DETAIL_W - 40.0, 62.0, kind, 25)
	b.disabled = off
	b.pressed.connect(fn)
	_acts.add_child(b)


# ====================================================================
# 操作
# ====================================================================

## 翻到哪一栏：pill / tool / gear / key / alchemy / ring / sell
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


## 做完一件事之后重画，还选着同一格（货架顺序不变）
func _after(keep: int, it: Dictionary, fly_to_bag: bool) -> void:
	var from: Control = _tiles[keep] if keep >= 0 and keep < _tiles.size() else null
	var p0 := _center(from) if from != null else Vector2.ZERO
	_rebuild(false)
	_sel = keep if keep < _goods.size() else -1
	for k in _tiles.size():
		(_tiles[k] as MetaKit.Tile).set_selected(k == _sel)
	_rebuild_detail()
	if fly_to_bag and from != null:
		shell.call("fly", MetaKit.icon(it), p0, _center(_bag_chip), func() -> void: MetaKit.pop(_bag_chip, 1.1))


## 买 n 个：一个个买（Profile.buy），中途灵石不够 / 仓库满了就停，说一声
func _do_buy(n: int) -> void:
	if _sel < 0:
		return
	var g: Dictionary = _goods[_sel]
	var got := 0
	var e := ""
	for _k in n:
		e = Profile.buy(g["good"])
		if e != "":
			break
		got += 1
	if got == 0:
		shell.call("warn", e)
		return
	_after(_sel, g["item"], true)
	shell.call("sfx", "pickup", -8.0, 1.0)
	if e != "":
		shell.call("warn", "买了 %d 个 · %s" % [got, e])


func _do_craft() -> void:
	if _sel < 0:
		return
	var g: Dictionary = _goods[_sel]
	var e := Profile.craft(g["recipe"])
	if e != "":
		shell.call("warn", e)
		return
	_after(_sel, g["item"], true)
	shell.call("sfx", "ascend", -10.0, 1.2)
	shell.call("ok", "炼成 %s" % str((g["item"] as Dictionary).get("name", "")))


func _do_ring() -> void:
	var e := Profile.upgrade_ring()
	if e != "":
		shell.call("warn", e)
		return
	_after(0, _ring_item(), false)
	shell.call("sfx", "pickup", -8.0, 0.9)
	shell.call("ok", "储物戒扩到 %d 格" % Profile.ring_cap())


## 卖出这一叠里的 cnt 件（-1 = 整叠）：古宝以上 / 破境丹先问一句
func _do_sell(cnt: int) -> void:
	if _sel < 0:
		return
	var g: Dictionary = _goods[_sel]
	var it: Dictionary = g["item"]
	var key := str(g["key"])
	var n := int(g["n"]) if cnt < 0 else 1
	var gain := int(it.get("value", 0)) * n
	var go := func() -> void:
		if Profile.in_raid():
			shell.call("warn", Profile.RAID_LOCK)
			return
		var got := 0
		var left := n
		var st := Profile.stash()
		var j := st.size() - 1
		while j >= 0 and left > 0:
			if Abode._stack_key(st[j]) == key:
				got += Profile.sell(j)
				left -= 1
			j -= 1
		var keep := _sel
		_rebuild(false)
		# 还是同一样东西（一叠卖掉一个）就接着选它
		_sel = keep if keep < _goods.size() and str(_goods[keep].get("key", "")) == key else (0 if not _goods.is_empty() else -1)
		for k in _tiles.size():
			(_tiles[k] as MetaKit.Tile).set_selected(k == _sel)
		_rebuild_detail()
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "+%s 灵石" % NumFmt.fmt(float(got)))
	if int(it.get("tier", 0)) >= 3 or str(it.get("kind", "")) == "key":
		shell.call("confirm", "%s%s 卖出得 %s 灵石\n确定卖掉吗？" % [str(it.get("name", "")), (" ×%d" % n) if n > 1 else "", NumFmt.fmt(float(gain))], "卖出", go)
	else:
		go.call()


## 一键出售（Profile.sell_junk）：先问一句件数和总价
func _do_bulk() -> void:
	var jp := _junk_preview()
	if int(jp[0]) == 0:
		return
	var go := func() -> void:
		var r := Profile.sell_junk()
		_sel = -1
		_rebuild(true)
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "卖了 %d 件 · +%s 灵石" % [int(r[0]), NumFmt.fmt(float(r[1]))])
	shell.call("confirm", "凡品法宝、灵材、服不了的本境丹\n一共 %d 件、%s 灵石\n确定全卖掉吗？" % [int(jp[0]), NumFmt.fmt(float(jp[1]))], "全部卖出", go)


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


## 点底下的一键出售（参数留着兼容老自检，不看）
func press_bulk(_src := "") -> bool:
	for c in _bulk.get_children():
		if c is Button and not (c as Button).disabled and not c.is_queued_for_deletion():
			(c as Button).pressed.emit()
			return true
	return false


func cat_key() -> String:
	return _cat


## 货架上第一件名字是 nm 的货（没有 = -1；老自检按 id 找，修仙物品没有 id，用名字）
func find_id(nm: String) -> int:
	for i in _goods.size():
		if str((_goods[i]["item"] as Dictionary).get("name", "")) == nm:
			return i
	return -1
