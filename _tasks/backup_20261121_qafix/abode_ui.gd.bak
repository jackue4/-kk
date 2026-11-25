extends Control
## 洞府（2026-11-20 搜打撤三档改造的局外界面）：择境门 → 木兰草原 → 入境页的「洞府 · 备战」打开。三页：
##   储物：左边仓库（最多 60 件），右边是这次要带进去的 —— 佩戴法宝 3 件（陨落即失）、随身丹符 4 件（进图直接放进背包）、
##         储物戒（陨落也保得住，坊市里能扩格）；穷到一无所有时可以领一份「散修行囊」
##   坊市：买丹药、符箓、凡品 / 灵器法宝，扩储物戒；破境丹只卖筑基丹、降尘丹（Prog.SHOP_KEY，2026-11-20 数值框架）；
##         仓库里的东西点了能卖，另有「一键出售」凡品法宝和灵材
##   丹房：灵草 + 灵石 → 修为丹（下品）；破境丹残片 × Prog.FRAG_N + 灵石 → 破境丹（2026-11-20 数值框架）
## 点一件 → 底下一行说明和能做的事。存档都走 raid_profile.gd（每次操作立即存盘）。
## 宣纸面板、墨字、朱砂只点一两处（见 ui_style.gd）。手机上按钮都在 54 像素以上。
## 故意不写 class_name：用 preload 引用。

signal closed

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const ItemView := preload("res://scripts/item_view.gd")
const Prog := preload("res://scripts/progression.gd")

const TABS := ["储物", "坊市", "丹房"]

var font: Font
var _tab := 0
var _sel := {}                  # {src: stash / gear / carry / ring / shop, i}
var _msg := ""
var _msg_col := UiStyle.TEXT_SOFT
var _body: Control
var _head_ls: Label
var _head_realm: Label
var _tab_btns: Array[Button] = []
var _note: Label
var _detail: Label
var _acts: HBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	theme = th
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.scroll(26.0))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	# 题头
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiStyle.seal("府", 50.0))
	var t := _ink("洞府", 48)
	t.add_theme_font_override("font", UiStyle.brush())
	head.add_child(t)
	var g0 := Control.new()
	g0.custom_minimum_size = Vector2(24, 0)
	head.add_child(g0)
	_tab_btns.clear()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 58)
		b.add_theme_font_size_override("font_size", 26)
		UiStyle.style_button(b, true)
		b.pressed.connect(_set_tab.bind(i))
		head.add_child(b)
		_tab_btns.append(b)
	var g1 := Control.new()
	g1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(g1)
	var ls_ic := TextureRect.new()
	ls_ic.texture = UiStyle.icon("lingshi")
	ls_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ls_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ls_ic.custom_minimum_size = Vector2(44, 44)
	ls_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ls_ic)
	_head_ls = _ink("", 26)
	_head_ls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_head_ls)
	_head_realm = _ink("", 22, UiStyle.TEXT_SOFT)
	_head_realm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_head_realm)
	var back := _btn("返回", 140.0)
	back.pressed.connect(_close)
	head.add_child(back)
	v.add_child(UiStyle.rule(560.0, 9.0, Color(UiStyle.LINE, 0.82)))
	_note = _ink("", 18, UiStyle.TEXT_SOFT)
	v.add_child(_note)
	_body = Control.new()
	_body.custom_minimum_size = Vector2(1380, 560)
	v.add_child(_body)
	v.add_child(UiStyle.rule(560.0, 6.0, Color(UiStyle.LINE, 0.6)))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_detail = _ink("", 19, UiStyle.TEXT_SOFT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_detail)
	_acts = HBoxContainer.new()
	_acts.add_theme_constant_override("separation", 10)
	foot.add_child(_acts)
	if Profile.notice != "":
		_say(Profile.notice, UiStyle.CINNABAR)
		Profile.notice = ""
	_set_tab(0)


func _ink(text: String, size: int, col := UiStyle.TEXT_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(text: String, w := 150.0, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 21)
	if primary:
		UiStyle.style_primary(b)
	else:
		UiStyle.style_button(b, true)
	return b


func _say(text: String, col := UiStyle.TEXT_SOFT) -> void:
	_msg = text
	_msg_col = col


func _set_tab(i: int) -> void:
	_tab = i
	_sel = {}
	for k in _tab_btns.size():
		_tab_btns[k].button_pressed = k == i
	_refresh()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	var vs := get_viewport_rect().size
	_panel.position = ((vs - _panel.size) * 0.5).floor()


# ---------- 重建 ----------

func _refresh() -> void:
	_head_ls.text = "%d 灵石" % Profile.lingshi()
	_head_realm.text = "　%s期" % Realm.LIST[Profile.realm()]["name"]
	# 2026-11-20 数值框架：坊市的破境丹只剩筑基丹、降尘丹；丹房用残片合破境丹；突破要 修为到瓶颈 + 破境丹 + 灵石
	var notes := ["佩戴的法宝和随身丹符跟着进图；陨落时法宝、背包全失，储物戒里的保得住。",
			"灵石只在洞府里花（局内「灵石阵」也从这里扣）。破境丹这里只卖%s，再往上要去禁地里找。" % _shop_keys(),
			"灵草加灵石炼修为丹（出下品）；巢穴首领掉的破境丹残片，%d 片加灵石合一颗；突破到修炼场，另要灵石。" % Prog.FRAG_N]
	_note.text = _msg if _msg != "" else notes[_tab]
	_note.add_theme_color_override("font_color", _msg_col if _msg != "" else UiStyle.TEXT_SOFT)
	for c in _body.get_children():
		c.queue_free()
	match _tab:
		0:
			_build_store()
		1:
			_build_shop()
		2:
			_build_alchemy()
	_build_detail()


## 坊市卖的几种破境丹的名字（「筑基丹、降尘丹」），跟着 Prog.SHOP_KEY 走
static func _shop_keys() -> String:
	var ks: Array = Prog.SHOP_KEY.keys()
	ks.sort()
	var names: Array = []
	for k: Variant in ks:
		names.append(str(Items.KEYS[clampi(int(k), 1, Items.KEYS.size() - 1)]))
	return "、".join(names)


func _scroll_grid(cols: int, size: Vector2) -> Array:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	sc.add_child(g)
	return [sc, g]


func _section(parent: Control, text: String) -> void:
	var l := _ink(text, 24, UiStyle.TEXT_INK)
	l.add_theme_font_override("font", UiStyle.brush())
	parent.add_child(l)


func _is_sel(src: String, i: int) -> bool:
	return not _sel.is_empty() and str(_sel["src"]) == src and int(_sel["i"]) == i


func _select(src: String, i: int) -> void:
	if _is_sel(src, i):
		_sel = {}
	else:
		_sel = {"src": src, "i": i}
	_msg = ""
	_refresh()


## 储物页
func _build_store() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_body.add_child(row)
	# 左：仓库
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	left.add_child(lh)
	_section(lh, "仓库 %d / %d" % [Profile.stash().size(), Profile.STASH_CAP])
	var sg := _scroll_grid(4, Vector2(860, 500))
	left.add_child(sg[0])
	var stash := Profile.stash()
	for i in stash.size():
		var b := ItemView.slot(stash[i], Vector2(204, 80), _is_sel("stash", i))
		b.pressed.connect(_select.bind("stash", i))
		(sg[1] as GridContainer).add_child(b)
	if stash.is_empty():
		var e := _ink("仓库空空如也：去禁地里搜，或者到坊市买", 19, UiStyle.TEXT_SOFT)
		(sg[1] as GridContainer).add_child(e)
	# 右：这次带什么
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_section(right, "佩戴法宝（陨落即失）")
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	right.add_child(gr)
	var gear := Profile.gear()
	for i in Profile.GEAR_SLOTS:
		var it: Dictionary = gear[i] if i < gear.size() else {}
		var b := ItemView.slot(it, Vector2(160, 76), _is_sel("gear", i), -1, "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("gear", i))
		gr.add_child(b)
	var fx := Items.fx_total(gear)
	var fx_txt: Array = []
	for k: String in ["atk", "guard", "seek", "vital"]:
		if float(fx[k]) > 0.0:
			fx_txt.append("%s +%d%%" % [Items.FX_NAMES[k], int(roundf(float(fx[k]) * 100.0))])
	right.add_child(_ink("　".join(fx_txt) if not fx_txt.is_empty() else "未佩戴法宝：空手入境", 17, UiStyle.TEXT_SOFT))
	_section(right, "随身丹符（进图放进背包）")
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 8)
	cg.add_theme_constant_override("v_separation", 8)
	right.add_child(cg)
	var carry := Profile.carry()
	for i in Profile.CARRY_SLOTS:
		var it: Dictionary = carry[i] if i < carry.size() else {}
		var b := ItemView.slot(it, Vector2(244, 70), _is_sel("carry", i), -1, "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("carry", i))
		cg.add_child(b)
	_section(right, "储物戒 %d / %d 格（陨落不失）" % [Items.slots_used(Profile.ring()), Profile.ring_cap()])
	var rg := GridContainer.new()
	rg.columns = 2
	rg.add_theme_constant_override("h_separation", 8)
	rg.add_theme_constant_override("v_separation", 8)
	right.add_child(rg)
	var ring := Profile.ring()
	for i in ring.size():
		var b := ItemView.slot(ring[i], Vector2(244, 70), _is_sel("ring", i))
		b.pressed.connect(_select.bind("ring", i))
		rg.add_child(b)
	for i in maxi(Profile.ring_cap() - Items.slots_used(ring), 0):
		rg.add_child(ItemView.slot({}, Vector2(244, 70), false, -1, "空"))
	if Profile.kit_ok():
		var kit := _btn("领取散修行囊", 300.0, true)
		kit.pressed.connect(func() -> void:
			var err := Profile.take_kit()
			_say("领了一份散修行囊：铁木剑、青钢盾、回春丹两颗" if err == "" else err, UiStyle.QING if err == "" else UiStyle.CINNABAR)
			_refresh())
		right.add_child(kit)
	var st: Dictionary = Profile.data()["stats"]
	right.add_child(_ink("入境 %d 次　撤出 %d　陨落 %d　单次最多带出 %d 灵石" % [int(st.get("raids", 0)), int(st.get("out", 0)),
			int(st.get("dead", 0)), int(st.get("best", 0))], 16, UiStyle.TEXT_SOFT))


## 坊市页
func _build_shop() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_section(left, "货架")
	var sg := _scroll_grid(4, Vector2(900, 500))
	left.add_child(sg[0])
	var goods := Items.shop()
	for i in goods.size():
		var g: Dictionary = goods[i]
		var b := ItemView.slot(g["item"], Vector2(214, 80), _is_sel("shop", i), int(g["price"]))
		b.pressed.connect(_select.bind("shop", i))
		(sg[1] as GridContainer).add_child(b)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	_section(right, "出售")
	right.add_child(_ink("仓库里的东西在「储物」页点一下就能卖。", 18, UiStyle.TEXT_SOFT))
	var junk := _btn("一键出售：凡品法宝、全部灵材", 420.0)
	junk.pressed.connect(func() -> void:
		var r := Profile.sell_junk()
		_say("卖了 %d 件，得 %d 灵石" % [int(r[0]), int(r[1])] if int(r[0]) > 0 else "没有可一键出售的东西", UiStyle.QING)
		_refresh())
	right.add_child(junk)
	_section(right, "储物戒")
	var price := Profile.ring_next_price()
	right.add_child(_ink("现在 %d 格：放在里面的东西陨落也不会丢" % Profile.ring_cap(), 18, UiStyle.TEXT_SOFT))
	var up := _btn("扩到 %d 格（%d 灵石）" % [Profile.ring_cap() + 1, price] if price > 0 else "储物戒已是最大", 420.0, price > 0)
	up.disabled = price < 0
	up.pressed.connect(func() -> void:
		var err := Profile.upgrade_ring()
		_say("储物戒扩到 %d 格" % Profile.ring_cap() if err == "" else err, UiStyle.QING if err == "" else UiStyle.CINNABAR)
		_refresh())
	right.add_child(up)


## 丹房页
func _build_alchemy() -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1380, 540)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var rs := Items.recipes()
	for i in rs.size():
		var r: Dictionary = rs[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		list.add_child(row)
		var b := ItemView.slot(r["out"], Vector2(250, 72))
		b.disabled = false
		row.add_child(b)
		var need: Dictionary = r["need"]
		var parts: Array = []
		for nm: String in need.keys():
			parts.append("%s %d/%d" % [nm, Profile.count(nm), int(need[nm])])
		parts.append("灵石 %d" % int(r["cost"]))
		var ok := Profile.can_craft(r)
		var l := _ink("　".join(parts), 20, UiStyle.TEXT_INK if ok else UiStyle.TEXT_SOFT)
		l.custom_minimum_size = Vector2(760, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var go := _btn("炼制", 150.0, ok)
		go.disabled = not ok
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void:
			var err := Profile.craft(r)
			_say("炼成 %s，已入仓库" % r["out"]["name"] if err == "" else err, UiStyle.QING if err == "" else UiStyle.CINNABAR)
			_refresh())
		row.add_child(go)


# ---------- 选中 → 说明和按钮 ----------

func _build_detail() -> void:
	for c in _acts.get_children():
		c.queue_free()
	var it := _sel_item()
	if it.is_empty():
		_detail.text = "点一件看看能做什么"
		_detail.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
		return
	_detail.text = ItemView.detail_text(it)
	_detail.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	var src := str(_sel["src"])
	var i := int(_sel["i"])
	match src:
		"stash":
			var k := str(it.get("kind", ""))
			if k == "gear":
				_act_btn("佩戴", func() -> String: return Profile.equip(i), true)
			elif ["pill", "key", "tool"].has(k):
				_act_btn("随身带上", func() -> String: return Profile.pack(i), true)
			_act_btn("收进储物戒", func() -> String: return Profile.to_ring(i))
			var sell := func() -> String:
				var v := Profile.sell(i)
				_say("卖出 %s，得 %d 灵石" % [it["name"], v], UiStyle.QING)
				return ""
			_act_btn("卖出 %d" % int(it.get("value", 0)), sell)
		"gear":
			_act_btn("取下", func() -> String: return Profile.unequip(i))
		"carry":
			_act_btn("放回仓库", func() -> String: return Profile.unpack(i))
		"ring":
			_act_btn("取回仓库", func() -> String: return Profile.from_ring(i))
		"shop":
			var g: Dictionary = Items.shop()[i]
			var buy := func() -> String:
				var err := Profile.buy(g)
				if err == "":
					_say("买下 %s，已入仓库（灵石余 %d）" % [it["name"], Profile.lingshi()], UiStyle.QING)
				return err
			_act_btn("买入（%d 灵石）" % int(g["price"]), buy, true)


func _act_btn(text: String, fn: Callable, primary := false) -> void:
	var b := _btn(text, 190.0, primary)
	b.pressed.connect(func() -> void:
		var err: String = fn.call()
		if err != "":
			_say(err, UiStyle.CINNABAR)
		if str(_sel.get("src", "")) != "shop":
			_sel = {}
		_refresh())
	_acts.add_child(b)


func _sel_item() -> Dictionary:
	if _sel.is_empty():
		return {}
	var i := int(_sel["i"])
	var list: Array = []
	match str(_sel["src"]):
		"stash":
			list = Profile.stash()
		"gear":
			list = Profile.gear()
		"carry":
			list = Profile.carry()
		"ring":
			list = Profile.ring()
		"shop":
			var goods := Items.shop()
			return goods[i]["item"] if i < goods.size() else {}
	return list[i] if i < list.size() else {}


## 入境页上那一行：这次带了什么
static func summary() -> String:
	var names: Array = []
	for it: Dictionary in Profile.gear():
		names.append(str(it["name"]))
	return "佩戴 %s　随身 %d 件　储物戒 %d/%d　洞府 %d 灵石" % ["、".join(names) if not names.is_empty() else "无（空手入境）",
			Profile.carry().size(), Items.slots_used(Profile.ring()), Profile.ring_cap(), Profile.lingshi()]
