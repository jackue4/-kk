extends Control
## 洞府（2026-11-20 搜打撤三档改造的局外界面）：择境门 → 木兰草原 → 入境页的「洞府 · 备战」打开。三页：
##   储物：左边仓库（最多 60 件），右边是这次要带进去的 —— 佩戴法宝 3 件（陨落即失）、随身丹符 4 件（进图直接放进背包）、
##         储物戒（陨落也保得住，坊市里能扩格）；穷到一无所有时可以领一份「散修行囊」
##   坊市：买丹药、符箓、凡品 / 灵器法宝，扩储物戒；破境丹只卖筑基丹、降尘丹（Prog.SHOP_KEY，2026-11-20 数值框架）；
##         仓库里的东西点了能卖，另有「一键出售」凡品法宝和灵材
##   丹房：灵草 + 灵石 → 修为丹（下品）；破境丹残片 × Prog.FRAG_N + 灵石 → 破境丹（2026-11-20 数值框架）
## 点一件 → 底下一行说明和能做的事。存档都走 raid_profile.gd（每次操作立即存盘）。
## 宣纸面板、墨字、朱砂只点一两处（见 ui_style.gd）。
## 2026-11-23 按手机重排（用户原话：仓库的界面「展示的信息太多了，导致也有点看不清」）：
##   · 物品一律是「大图标 + 一行名字」的方格（item_view.gd 的 tile）；品阶、效果、价值点中了在底下那一行看
##   · 仓库里一样的东西叠成一格、右上角写 ×N（只是显示上叠：点中的是这一叠的第一件，卖 / 带上还是一件一件来，做完接着选这一叠）
##   · 原来顶上那行说明挪到底下：没选东西时才显示；刚做完的事的结果（卖了多少、买了什么）也显示在那儿
##   · 字号和按钮整体加大（按钮高 62）；整块放不下就缩小（_process）。桌面和手机是同一套排法。
## 故意不写 class_name：用 preload 引用。

signal closed

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const ItemView := preload("res://scripts/item_view.gd")
const Prog := preload("res://scripts/progression.gd")

const TABS := ["储物", "坊市", "丹房"]
## 2026-11-23 按手机重排的尺寸（1600×900 的界面单位；手机上一个单位不到 0.1 毫米，所以字和格子都往大里放）
const BODY := Vector2(1500, 590)         # 中间那块
const GRID_W := 964.0                    # 左边 6 列方格（6×150 + 5×10）加滚动条
const TILE := Vector2(150, 128)          # 仓库的方格
const SHOP_TILE := Vector2(150, 150)     # 货架的方格：多一行价钱
const GEAR_TILE := Vector2(164, 112)     # 佩戴法宝（3 件一排）
const CARRY_TILE := Vector2(120, 106)    # 随身丹符（4 件一排）、储物戒

var font: Font
var _tab := 0
var _sel := {}                  # {src: stash / gear / carry / ring / shop, i}
var _msg := ""
var _msg_col := UiStyle.TEXT_SOFT
var _body: Control
var _head_ls: Label
var _head_realm: Label
var _tab_btns: Array[Button] = []
var _detail: Label
var _acts: HBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 20
	theme = th
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.scroll(22.0))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	# 题头：朱印 + 题字 + 三个页签 + 灵石 + 返回
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var seal := UiStyle.seal("府", 46.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(seal)
	var t := _ink("洞府", 42)
	t.add_theme_font_override("font", UiStyle.brush())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var g0 := Control.new()
	g0.custom_minimum_size = Vector2(16, 0)
	head.add_child(g0)
	_tab_btns.clear()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 62)
		b.add_theme_font_size_override("font_size", 28)
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
	ls_ic.custom_minimum_size = Vector2(46, 46)
	ls_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ls_ic)
	_head_ls = _ink("", 28)
	_head_ls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_head_ls)
	_head_realm = _ink("", 22, UiStyle.TEXT_SOFT)
	_head_realm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_head_realm)
	var back := _btn("返回", 150.0)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close)
	head.add_child(back)
	v.add_child(UiStyle.rule(560.0, 8.0, Color(UiStyle.LINE, 0.82)))
	_body = Control.new()
	_body.custom_minimum_size = BODY
	v.add_child(_body)
	v.add_child(UiStyle.rule(560.0, 6.0, Color(UiStyle.LINE, 0.6)))
	# 底下：一行话（选中的东西的说明 / 刚才那一下的结果 / 这一页的提示）+ 能做的事的按钮
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_detail = _ink("", 21, UiStyle.TEXT_SOFT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail.max_lines_visible = 2
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail.custom_minimum_size = Vector2(300, 68)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_detail)
	_acts = HBoxContainer.new()
	_acts.add_theme_constant_override("separation", 10)
	_acts.custom_minimum_size = Vector2(0, 62)
	_acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	b.custom_minimum_size = Vector2(w, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
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


## 面板居中；画面放不下（四周留一点边）就整块缩小，不放大
func _process(_dt: float) -> void:
	var vs := get_viewport_rect().size
	var ps := _panel.get_combined_minimum_size()
	_panel.size = ps
	var k := minf(1.0, minf((vs.x - 28.0) / ps.x, (vs.y - 20.0) / ps.y))
	_panel.scale = Vector2(k, k)
	_panel.position = ((vs - ps * k) * 0.5).floor()


# ---------- 重建 ----------

func _refresh() -> void:
	_head_ls.text = "%d 灵石" % Profile.lingshi()
	_head_realm.text = "　%s期" % Realm.LIST[Profile.realm()]["name"]
	for c in _body.get_children():
		(c as CanvasItem).visible = false      # 这一帧末才真删：先藏起来，免得新旧叠在一起闪一下
		c.queue_free()
	match _tab:
		0:
			_build_store()
		1:
			_build_shop()
		2:
			_build_alchemy()
	_build_detail()


## 每一页的一句提示（没选东西、也没有刚做完的事要说时，显示在底下那一行）
## 2026-11-20 数值框架：坊市的破境丹只剩筑基丹、降尘丹；丹房用残片合破境丹；突破要 修为到瓶颈 + 破境丹 + 灵石
func _hint() -> String:
	match _tab:
		0:
			return "佩戴的法宝和随身丹符跟着进图；陨落时法宝、背包全失，储物戒里的保得住。"
		1:
			return "灵石只在洞府里花（局内「灵石阵」也从这里扣）。破境丹这里只卖%s，再往上要去禁地里找。" % _shop_keys()
	return "灵草加灵石炼修为丹（出下品）；巢穴首领掉的破境丹残片，%d 片加灵石合一颗；突破到修炼场，另要灵石。" % Prog.FRAG_N


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
	# 小标题用正文字体：题字那款字体是按用字裁剪的，缺字时会半个词换成另一种字体（网页 / 手机上「货架」就是这样）
	var l := _ink(text, 26, UiStyle.TEXT_INK)
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


## 两件东西算不算「一样的」（仓库里一样的叠成一格）：种类、名字、品阶、被动都一样；价值差几块灵石不管。
## 2026-11-23：修为丹按境界分（本境丹 / 霸主精魄 / 旧丹），另加 境界 / 最低境界 / 品质（没有的记 -1）——和 raid_profile.gd 的 stack_key 一个写法
static func _stack_key(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var s := "%s|%s|%d|%s|%d" % [str(it.get("kind", "")), str(it.get("name", "")), int(it.get("tier", 0)), str(it.get("fx", "")), int(it.get("amt", 0))]
	if str(it.get("kind", "")) == "pill":
		s += "|%d|%d|%d" % [int(it.get("realm", -1)), int(it.get("min_realm", -1)), int(it.get("grade", -1))]
	return s


## 把一列东西叠起来：[[这一叠第一件的下标, 件数], ...]，按第一次出现的先后排。
## 灵草 / 灵果一叠满 Profile.STACK_MAX 件另起一叠（和仓库按格算一致：raid_profile.gd 的 stash_slots）
static func _stacks(list: Array) -> Array:
	var out: Array = []
	var at := {}
	for i in list.size():
		var key := _stack_key(list[i])
		if at.has(key) and not (Profile.stacks(list[i]) and int((out[int(at[key])] as Array)[1]) >= Profile.STACK_MAX):
			var st: Array = out[int(at[key])]
			st[1] = int(st[1]) + 1
		else:
			at[key] = out.size()
			out.append([i, 1])
	return out


## 一排方格（佩戴法宝 / 随身丹符 / 储物戒）
func _tile_row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	parent.add_child(r)
	return r


## 储物页：左边仓库（一样的东西叠成一格），右边三排是这次带进去的
func _build_store() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_body.add_child(row)
	# 左：仓库
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var stash := Profile.stash()
	_section(left, "仓库 %d / %d 格" % [Profile.stash_slots(), Profile.STASH_CAP])      # 2026-11-23：灵草 / 灵果叠成一格算（raid_profile.gd 的 stash_slots）
	var sg := _scroll_grid(6, Vector2(GRID_W, BODY.y - 48.0))
	left.add_child(sg[0])
	var sel_key := _stack_key(_sel_item()) if str(_sel.get("src", "")) == "stash" else ""
	for st: Array in _stacks(stash):
		var i := int(st[0])
		var it: Dictionary = stash[i]
		var b := ItemView.tile(it, TILE, sel_key != "" and _stack_key(it) == sel_key, ("×%d" % int(st[1])) if int(st[1]) > 1 else "")
		b.pressed.connect(_select.bind("stash", i))
		(sg[1] as GridContainer).add_child(b)
	if stash.is_empty():
		var e := _ink("仓库空空如也：去禁地里搜，或者到坊市买", 22, UiStyle.TEXT_SOFT)
		(sg[1] as GridContainer).add_child(e)
	# 右：这次带什么
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(BODY.x - GRID_W - 24.0, 0)
	row.add_child(right)
	_section(right, "佩戴法宝")
	var gr := _tile_row(right)
	var gear := Profile.gear()
	for i in Profile.GEAR_SLOTS:
		var it: Dictionary = gear[i] if i < gear.size() else {}
		var b := ItemView.tile(it, GEAR_TILE, _is_sel("gear", i), "", "", "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("gear", i))
		gr.add_child(b)
	var fx := Items.fx_total(gear)
	var fx_txt: Array = []
	for k: String in ["atk", "guard", "seek", "vital"]:
		if float(fx[k]) > 0.0:
			fx_txt.append("%s +%d%%" % [Items.FX_NAMES[k], int(roundf(float(fx[k]) * 100.0))])
	right.add_child(_ink("　".join(fx_txt) if not fx_txt.is_empty() else "未佩戴法宝：空手入境", 19, UiStyle.TEXT_SOFT))
	_section(right, "随身丹符")
	var cg := _tile_row(right)
	var carry := Profile.carry()
	for i in Profile.CARRY_SLOTS:
		var it: Dictionary = carry[i] if i < carry.size() else {}
		var b := ItemView.tile(it, CARRY_TILE, _is_sel("carry", i), "", "", "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("carry", i))
		cg.add_child(b)
	_section(right, "储物戒 %d / %d" % [Items.slots_used(Profile.ring()), Profile.ring_cap()])
	var rg := _tile_row(right)
	var ring := Profile.ring()
	for i in ring.size():
		var b := ItemView.tile(ring[i], CARRY_TILE, _is_sel("ring", i), "2格" if Items.size_of(ring[i]) > 1 else "")
		b.pressed.connect(_select.bind("ring", i))
		rg.add_child(b)
	for i in maxi(Profile.ring_cap() - Items.slots_used(ring), 0):
		rg.add_child(ItemView.tile({}, CARRY_TILE, false, "", "", "空"))
	if Profile.kit_ok():
		var kit := _btn("领取散修行囊", 300.0, true)
		kit.pressed.connect(func() -> void:
			var err := Profile.take_kit()
			_say("领了一份散修行囊：铁木剑、青钢盾、回春丹两颗" if err == "" else err, UiStyle.QING if err == "" else UiStyle.CINNABAR)
			_refresh())
		right.add_child(kit)
	else:
		# 战绩只留一行小字（领行囊的按钮在的时候让给它）
		var st: Dictionary = Profile.data()["stats"]
		right.add_child(_ink("入境 %d　撤出 %d　陨落 %d　最多带出 %d 灵石" % [int(st.get("raids", 0)), int(st.get("out", 0)),
				int(st.get("dead", 0)), int(st.get("best", 0))], 17, UiStyle.TEXT_SOFT))


## 一段会自动折行的小字（右边那一栏的说明）
func _para(parent: Control, text: String, w: float) -> void:
	var l := _ink(text, 21, UiStyle.TEXT_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(w, 0)
	parent.add_child(l)


## 坊市页：左边货架（方格下面写价钱），右边出售和扩储物戒
func _build_shop() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_section(left, "货架")
	var sg := _scroll_grid(6, Vector2(GRID_W, BODY.y - 48.0))
	left.add_child(sg[0])
	var goods := Items.shop()
	for i in goods.size():
		var g: Dictionary = goods[i]
		var b := ItemView.tile(g["item"], SHOP_TILE, _is_sel("shop", i), "", "%d 灵石" % int(g["price"]))
		b.pressed.connect(_select.bind("shop", i))
		(sg[1] as GridContainer).add_child(b)
	var rw := BODY.x - GRID_W - 24.0
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(rw, 0)
	row.add_child(right)
	_section(right, "出售")
	_para(right, "仓库里的东西在「储物」页点中就能卖。", rw)
	var junk := _btn("一键出售：凡品法宝、全部灵材", rw)
	junk.pressed.connect(func() -> void:
		var r := Profile.sell_junk()
		_say("卖了 %d 件，得 %d 灵石" % [int(r[0]), int(r[1])] if int(r[0]) > 0 else "没有可一键出售的东西", UiStyle.QING)
		_refresh())
	right.add_child(junk)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	right.add_child(gap)
	_section(right, "储物戒")
	var price := Profile.ring_next_price()
	_para(right, "现在 %d 格：放在里面的东西陨落也不会丢" % Profile.ring_cap(), rw)
	var up := _btn("扩到 %d 格（%d 灵石）" % [Profile.ring_cap() + 1, price] if price > 0 else "储物戒已是最大", rw, price > 0)
	up.disabled = price < 0
	up.pressed.connect(func() -> void:
		var err := Profile.upgrade_ring()
		_say("储物戒扩到 %d 格" % Profile.ring_cap() if err == "" else err, UiStyle.QING if err == "" else UiStyle.CINNABAR)
		_refresh())
	right.add_child(up)


## 丹房页：一行一个丹方 —— 图标 + 丹名 + 要的东西（有几 / 要几）+ 炼制
func _build_alchemy() -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = BODY
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var rs := Items.recipes()
	for i in rs.size():
		var r: Dictionary = rs[i]
		var out: Dictionary = r["out"]
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UiStyle.slot(false))
		box.custom_minimum_size = Vector2(BODY.x - 16.0, 84)
		list.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		var ic := TextureRect.new()
		ic.texture = UiStyle.icon(Items.icon_name(out))
		if ic.texture == null:
			ic.texture = UiStyle.icon(str(out.get("kind", "")))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(64, 64)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var nm := _ink(str(out.get("name", "")), 24, UiStyle.on_paper(Data.TIER_COLORS[clampi(int(out.get("tier", 0)), 0, Data.TIER_COLORS.size() - 1)]).darkened(0.25))
		nm.custom_minimum_size = Vector2(230, 0)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		var need: Dictionary = r["need"]
		var parts: Array = []
		for k: String in need.keys():
			parts.append("%s %d/%d" % [k, Profile.count(k), int(need[k])])
		parts.append("灵石 %d" % int(r["cost"]))
		var ok := Profile.can_craft(r)
		var l := _ink("　".join(parts), 22, UiStyle.TEXT_INK if ok else UiStyle.TEXT_SOFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
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
		(c as CanvasItem).visible = false
		c.queue_free()
	var it := _sel_item()
	# 底下那一行：刚做完的事的结果优先，其次是选中的东西的说明，都没有就写这一页的提示
	if _msg != "":
		_detail.text = _msg
		_detail.add_theme_color_override("font_color", _msg_col)
	elif it.is_empty():
		_detail.text = _hint()
		_detail.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	else:
		_detail.text = ItemView.detail_text(it)
		_detail.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	if it.is_empty():
		return
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
	var b := _btn(text, 170.0, primary)
	b.pressed.connect(func() -> void:
		var src := str(_sel.get("src", ""))
		var key := _stack_key(_sel_item()) if src == "stash" else ""
		_msg = ""
		var err: String = fn.call()
		if err != "":
			_say(err, UiStyle.CINNABAR)
		if src != "shop":
			_sel = {}
			if key != "":
				# 仓库里的一叠：做完一件接着选这一叠剩下的（连着卖、连着带，不用回头再点一次）
				var st := Profile.stash()
				for j in st.size():
					if _stack_key(st[j]) == key:
						_sel = {"src": "stash", "i": j}
						break
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
