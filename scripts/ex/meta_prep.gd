extends Control
## 「备战」页（挂在 meta_ui.gd 的壳里）。2026-11-24 用户定的：原来的「备战」和「仓库」合成一个入口 ——
## 「左侧是玩家形象，周围是装备的武器，右侧就是仓库」（给的参考是：左边人物 + 装备格，中间物品格子，右边选中那件的说明）。
## 同一天第二轮（用户看过第一版）：「现在有太多废话文字了，备战标题可以不要，穿在身上的...不掉落，这些提示词也不用」
## 「备战的界面我不希望能跳到换角色的入口」「角色下面不用说明打怪，打人的伤害值，我希望是一个战力值在这里，玩家穿脱装备这里的数值实时更新，让玩家看的更爽」。
## 所以这一页现在只有三块，没有说明性的句子：
##   左：当前出战的英雄（3D 小像，手指能转着看；不能点进英雄选择），左右两列装备栏（左：兵刃 + 三个法宝；右：冠 衣 护腿 履，空格子里是那一格的水墨淡影），
##       人物脚下一个大大的战力值：穿 / 脱装备时数字滚过去、弹一下、旁边冒出「+N / -N」。不能入境时（背包里有售卖物……）左上角一行红字说原因，能入境就什么都不写
##   中：「背包」「仓库」两段切换 + 一排筛选（全部 / 兵刃 / 法衣 / 法宝 / 丹符 / 宝物）+ 物品格子；仓库底下是扩容
##   右：选中那件的大图标、名字、品质、说明、值多少、穿上 / 卸下后战力变多少，下面是能做的事（穿戴 / 带上 / 存进仓库 / 卸下 / 修理 / 卖出）
## 一进来 / 换一边 / 做完一件事都自动选中一件（右边不会空着）；一件都没有时右边那块收起来。
## 点空的装备栏 = 筛出能穿在这一格的东西（自动翻到有货的那一边）。穿戴 / 挪动时图标飞过去、人亮个相。存档全走 ex_profile.gd。
## 战力是只给人看的总分（meta_kit.gd 的 power），不参与结算。
## 自检用的接口：goto / set_filter / select / press_action / action_texts / detail_name / power_shown。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const HeroDoll := preload("res://scripts/ex/hero_doll.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const ExItemView := preload("res://scripts/ex/ex_item_view.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const SLOT := Vector2(98.0, 98.0)
const SLOT_BIG := Vector2(116.0, 116.0)
const TILE := Vector2(110.0, 124.0)
const GAP := 10.0
const COLS := 5
const DETAIL_W := 352.0
const CORNER := 54.0
const POWER_H := 108.0
const FILTERS := [["all", "全部"], ["weapon", "兵刃"], ["armor", "法衣"], ["chip", "法宝"], ["use", "丹符"], ["loot", "宝物"]]
## 穿戴时人摆的姿势（combat_poses.gd 的 SEQ；没有的英雄只亮石台）
const WEAR_POSE := {"canghong": ["ck_iai"], "yujian": ["f_point"]}

var shell: Control               # meta_ui.gd
var start := ""                  # 一进来翻到哪（"stash" = 仓库）

var _list := "bag"               # 中间显示哪一边：bag / stash
var _filter := "all"
var _sel := {}                   # {src: bag / stash / equip, i, slot}
var _us := Vector2(1600, 900)
var _power := -1                 # 现在显示的战力（-1 = 还没算过）
var _power_n := 0

var _ring: TextureRect
var _doll: HeroDoll
var _slots := {}                 # "weapon:0" / "armor:2" / "chip:1" → Tile
var _slot_box: Control
var _pw_box: Control
var _pw_cap: Label
var _pw_num: Label
var _pw_delta: Label
var _entry: Label
var _mid: Control
var _tab_bag: Button
var _tab_stash: Button
var _sort: Button
var _filter_row: HBoxContainer
var _filter_btns := {}
var _scroll: ScrollContainer
var _grid: GridContainer
var _grow: Button
var _tiles: Array = []           # 现在格子里的 [在 _items() 里的下标, Tile]
var _detail: PanelContainer
var _d_box: VBoxContainer
var _acts: VBoxContainer
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start == "stash":
		_list = "stash"
	_build_left()
	_build_mid()
	_build_detail()
	refresh()


# ====================================================================
# 搭
# ====================================================================

func _build_left() -> void:
	_ring = MetaKit.art("meta_ring", Vector2(600, 600), Color(MetaKit.GOLD, 0.3))
	add_child(_ring)
	_doll = HeroDoll.new()
	_doll.hero_id = ExProfile.hero()
	add_child(_doll)
	_slot_box = Control.new()
	_slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_box)
	# 战力：一行小字 + 一个大数，两边各一朵祥云
	_pw_box = Control.new()
	_pw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pw_box)
	for i in 2:
		var cl := MetaKit.art("meta_cloud", Vector2(92, 92), Color(MetaKit.GOLD, 0.55))
		cl.flip_h = i == 0
		cl.name = "Cloud%d" % i
		_pw_box.add_child(cl)
	_pw_cap = MetaKit.outlined(MetaKit.label("战力", 23, Color(MetaKit.GOLD, 0.9)), 5)
	_pw_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pw_box.add_child(_pw_cap)
	_pw_num = MetaKit.outlined(MetaKit.label("", 66, MetaKit.GOLD.lightened(0.35)), 8)
	_pw_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pw_box.add_child(_pw_num)
	_pw_delta = MetaKit.outlined(MetaKit.label("", 32, MetaKit.JADE), 6)
	_pw_delta.modulate.a = 0.0
	_pw_box.add_child(_pw_delta)
	_entry = MetaKit.outlined(MetaKit.label("", 22, MetaKit.BAD), 5)
	_entry.visible = false
	add_child(_entry)


func _build_mid() -> void:
	_mid = Control.new()
	_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mid)
	_tab_bag = MetaKit.tab("背包", 196.0)
	_tab_bag.pressed.connect(goto.bind("bag"))
	_mid.add_child(_tab_bag)
	_tab_stash = MetaKit.tab("仓库", 196.0)
	_tab_stash.pressed.connect(goto.bind("stash"))
	_mid.add_child(_tab_stash)
	_sort = MetaKit.button("整理", 110.0, 58.0, "ghost", 24)
	_sort.pressed.connect(func() -> void:
		_sel = {}
		ExProfile.sort_list(_list)
		shell.call("click")
		_rebuild_grid(true)
		_rebuild_detail())
	_mid.add_child(_sort)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
	_mid.add_child(_filter_row)
	for f: Array in FILTERS:
		var b := MetaKit.tab(str(f[1]), 91.0, 46.0, 22)
		b.pressed.connect(set_filter.bind(str(f[0])))
		_filter_row.add_child(b)
		_filter_btns[str(f[0])] = b
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mid.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_scroll.add_child(_grid)
	_grow = MetaKit.button("", 420.0, 56.0, "gold", 23)
	_grow.pressed.connect(func() -> void:
		var e := ExProfile.upgrade_warehouse()
		if e == "":
			shell.call("sfx", "pickup", -8.0, 0.9)
			MetaKit.pop(_tab_stash, 1.1)
		else:
			shell.call("warn", e)
		refresh())
	_mid.add_child(_grow)


func _build_detail() -> void:
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
	# 四角云纹
	for i in 4:
		var c := MetaKit.art("meta_corner", Vector2(CORNER, CORNER), Color(MetaKit.GOLD, 0.85))
		c.flip_h = i % 2 == 1
		c.flip_v = i >= 2
		c.name = "Corner%d" % i
		add_child(c)


## 壳告诉这一页画面多大（界面单位）：摆位置
func layout(us: Vector2) -> void:
	_us = us
	var bottom := us.y - 18.0
	# 右：说明
	var dx := us.x - MARGIN - DETAIL_W - 6.0
	_detail.position = Vector2(dx, BAR_H + 12.0)
	_detail.size = Vector2(DETAIL_W, bottom - BAR_H - 20.0)
	for i in 4:
		var c := get_node("Corner%d" % i) as Control
		c.position = _detail.position + Vector2((DETAIL_W - CORNER + 11.0) if i % 2 == 1 else -11.0, (_detail.size.y - CORNER + 11.0) if i >= 2 else -11.0)
	# 中：格子
	var gw := float(COLS) * TILE.x + float(COLS - 1) * GAP
	var mw := gw + 14.0
	var mx := dx - 24.0 - mw
	_mid.position = Vector2(mx, BAR_H + 4.0)
	_mid.size = Vector2(mw, bottom - BAR_H - 4.0)
	_tab_bag.position = Vector2.ZERO
	_tab_stash.position = Vector2(206.0, 0.0)
	_sort.position = Vector2(gw - 110.0, 0.0)
	_filter_row.position = Vector2(0.0, 70.0)
	_filter_row.size = Vector2(gw, 46.0)
	var foot := 68.0 if _list == "stash" else 0.0
	_scroll.position = Vector2(0.0, 130.0)
	_scroll.size = Vector2(mw, _mid.size.y - 130.0 - foot)
	_grow.position = Vector2(0.0, _mid.size.y - 58.0)
	_grow.size = Vector2(gw, 56.0)
	# 左：人、装备栏、战力
	var lx := MARGIN
	var lw := mx - 24.0 - lx
	var top := BAR_H + 26.0
	_entry.position = Vector2(lx + 2.0, BAR_H - 6.0)
	_slot_box.position = Vector2(lx, top)
	_slot_box.size = Vector2(lw, 10.0)
	var col_r := lw - SLOT.x
	for k: String in _slots:
		var t := _slots[k] as Control
		var parts := k.split(":")
		var idx := int(parts[1])
		match parts[0]:
			"weapon":
				t.position = Vector2(0.0, 0.0)
			"chip":
				t.position = Vector2(0.0, SLOT_BIG.y + 14.0 + float(idx) * (SLOT.y + 12.0))
			"armor":
				t.position = Vector2(col_r, float(idx) * (SLOT.y + 12.0))
	var dl := SLOT_BIG.x - 30.0
	var dw := lw - dl - (SLOT.x - 30.0)
	_doll.position = Vector2(lx + dl, BAR_H - 6.0)
	_doll.size = Vector2(dw, bottom - POWER_H + 4.0 - (BAR_H - 6.0))      # 石台的底边停在「战力」那行字上面
	var cx := lx + dl + dw * 0.5
	var rs := minf(dw * 1.18, 600.0)
	_ring.size = Vector2(rs, rs)
	_ring.pivot_offset = _ring.size * 0.5
	_ring.position = Vector2(cx - rs * 0.5, _doll.position.y + _doll.size.y * 0.47 - rs * 0.5)
	# 战力：居中在人脚下
	var pw := minf(lw, 460.0)
	_pw_box.position = Vector2(cx - pw * 0.5, bottom - POWER_H)
	_pw_box.size = Vector2(pw, POWER_H)
	_pw_box.pivot_offset = _pw_box.size * 0.5
	_pw_cap.position = Vector2(0.0, -2.0)
	_pw_cap.size = Vector2(pw, _pw_cap.get_minimum_size().y)
	_pw_num.size = Vector2(pw, _pw_num.get_minimum_size().y)
	_pw_num.position = Vector2(0.0, POWER_H - _pw_num.size.y + 6.0)
	_pw_num.pivot_offset = _pw_num.size * 0.5
	var nw := MetaKit.font().get_string_size(MetaKit.fmt_int(maxi(_power, 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 66).x
	(_pw_box.get_node("Cloud0") as Control).position = Vector2(pw * 0.5 - nw * 0.5 - 104.0, POWER_H - 86.0)
	(_pw_box.get_node("Cloud1") as Control).position = Vector2(pw * 0.5 + nw * 0.5 + 12.0, POWER_H - 86.0)


## 进场：三块错开滑进来，格子一格格冒出来，战力从低处滚上去
func enter() -> void:
	MetaKit.slide_in(_slot_box, Vector2(-70, 0), 0.04)
	MetaKit.fade_in(_doll, 0.02, 0.3)
	MetaKit.fade_in(_ring, 0.1, 0.5)
	MetaKit.slide_in(_pw_box, Vector2(0, 40), 0.12)
	MetaKit.slide_in(_mid, Vector2(0, 46), 0.08)
	MetaKit.slide_in(_detail, Vector2(80, 0), 0.14)
	for i in 4:
		MetaKit.fade_in(get_node("Corner%d" % i) as CanvasItem, 0.34, 0.3)
	_cascade(0.16)
	var to := float(maxi(_power, 0))
	MetaKit.tween(_pw_num).tween_method(func(v: float) -> void: _pw_num.text = MetaKit.fmt_int(int(roundf(v))), to * 0.6, to, 0.7).set_delay(0.15).set_trans(
			Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	if _ring != null:
		_ring.rotation = _t * 0.05
		_ring.self_modulate = Color(_doll.col.lerp(MetaKit.GOLD, 0.5), 1.0)


# ====================================================================
# 数据
# ====================================================================

func _items() -> Array:
	return ExProfile.stash() if _list == "stash" else ExProfile.bag()


static func _match(it: Dictionary, f: String) -> bool:
	var kind := str(it.get("kind", ""))
	match f:
		"all":
			return true
		"weapon", "armor", "chip":
			return kind == f
		"use":
			return ["med", "revive", "throw", "key", "ward"].has(kind)
		"loot":
			return ["sell", "tag", "mat", "voucher"].has(kind)
	return true


func _sel_item() -> Dictionary:
	if _sel.is_empty():
		return {}
	var i := int(_sel["i"])
	match str(_sel["src"]):
		"bag":
			var b := ExProfile.bag()
			return b[i] if i >= 0 and i < b.size() else {}
		"stash":
			var st := ExProfile.stash()
			return st[i] if i >= 0 and i < st.size() else {}
		"equip":
			return _equip_item(str(_sel.get("slot", "")), i)
	return {}


func _equip_item(slot: String, i: int) -> Dictionary:
	var eq := ExProfile.equipment()
	if slot == "weapon":
		return eq["weapon"]
	var arr: Array = eq.get(slot, [])
	return arr[i] if i >= 0 and i < arr.size() else {}


## 选中的这件穿上（背包 / 仓库里的）或卸下（身上的）之后战力变多少；算不了的（法宝栏满了、不是装备）返回 null
func _power_change(it: Dictionary) -> Variant:
	if it.is_empty() or not ExData.wearable(it):
		return null
	var eq: Dictionary = ExProfile.equipment().duplicate(true)
	var now := MetaKit.power(eq)
	if str(_sel.get("src", "")) == "equip":
		var slot := str(_sel.get("slot", ""))
		if slot == "weapon":
			eq["weapon"] = {}
		else:
			(eq[slot] as Array)[int(_sel["i"])] = {}
		return MetaKit.power(eq) - now
	match str(it.get("kind", "")):
		"weapon":
			eq["weapon"] = it
		"armor":
			(eq["armor"] as Array)[clampi(int(it.get("slot", 0)), 0, 3)] = it
		"chip":
			var chips: Array = eq["chip"]
			var free := -1
			for k in chips.size():
				if (chips[k] as Dictionary).is_empty() and free < 0:
					free = k
			if free < 0:
				return null
			chips[free] = it
	return MetaKit.power(eq) - now


# ====================================================================
# 刷新
# ====================================================================

## 整页按存档重画（做完一件事之后；英雄换了也走这里）
func refresh() -> void:
	_doll.set_hero(ExProfile.hero())
	_rebuild_slots()
	_rebuild_status()
	_rebuild_grid(false)
	_rebuild_detail()
	shell.call("refresh_money")
	if _us.x > 0.0:
		layout(_us)


func _rebuild_slots() -> void:
	for k: String in _slots:
		(_slots[k] as Node).queue_free()
	_slots.clear()
	var eq := ExProfile.equipment()
	var defs: Array = [["weapon", 0, eq["weapon"], SLOT_BIG, "meta_slot_weapon"]]
	for s in 3:
		defs.append(["chip", s, (eq["chip"] as Array)[s], SLOT, "meta_slot_chip"])
	for s in 4:
		defs.append(["armor", s, (eq["armor"] as Array)[s], SLOT, "meta_slot_armor%d" % s])
	for e: Array in defs:
		var slot := str(e[0])
		var idx := int(e[1])
		var it: Dictionary = e[2]
		var t := MetaKit.tile(it, e[3], str(_sel.get("src", "")) == "equip" and str(_sel.get("slot", "")) == slot and int(_sel.get("i", -1)) == idx)
		t.empty_icon = MetaKit.tex(str(e[4]))
		t.show_name = false
		t.pressed.connect(_on_slot.bind(slot, idx))
		_slot_box.add_child(t)
		_slots["%s:%d" % [slot, idx]] = t


## 战力（变了就滚过去、冒出差值）和「能不能入境」（只有不能时才写）
func _rebuild_status() -> void:
	var v := MetaKit.power(ExProfile.equipment())
	if _power < 0:
		_power = v
		_pw_num.text = MetaKit.fmt_int(v)
	elif v != _power:
		var d := v - _power
		var from := _power
		_power = v
		_power_n += 1
		var n := _power_n
		MetaKit.tween(_pw_num).tween_method(func(x: float) -> void: _pw_num.text = MetaKit.fmt_int(int(roundf(x))), float(from), float(v), 0.5).set_trans(
				Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		MetaKit.pop(_pw_num, 1.22)
		var col := MetaKit.JADE if d > 0 else MetaKit.BAD
		_pw_num.add_theme_color_override("font_color", col.lightened(0.3))
		MetaKit.tween(_pw_num).tween_callback(func() -> void:
			if n == _power_n:
				_pw_num.add_theme_color_override("font_color", MetaKit.GOLD.lightened(0.35))).set_delay(0.7)
		# 差值：从数字右边冒出来往上飘
		_pw_delta.text = ("+" if d > 0 else "-") + MetaKit.fmt_int(absi(d))
		_pw_delta.add_theme_color_override("font_color", col)
		var nw := MetaKit.font().get_string_size(MetaKit.fmt_int(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 66).x
		var p0 := Vector2(_pw_box.size.x * 0.5 + nw * 0.5 + 16.0, POWER_H - 78.0)
		_pw_delta.position = p0
		_pw_delta.modulate.a = 1.0
		var t := MetaKit.tween(_pw_delta)
		t.set_parallel(true)
		t.tween_property(_pw_delta, "position:y", p0.y - 34.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_pw_delta, "modulate:a", 0.0, 0.5).set_delay(0.8)
		shell.call("sfx", "pickup", -9.0, 1.25 if d > 0 else 0.75)
	var err := ExProfile.entry_check()
	if ExProfile.in_raid():
		err = ExProfile.LOCK
	_entry.visible = err != ""
	_entry.text = err


func _rebuild_grid(animate: bool) -> void:
	_tab_bag.text = "背包 %d/%d" % [ExProfile.bag().size(), ExProfile.BAG_CAP]
	_tab_stash.text = "仓库 %d/%d" % [ExProfile.stash().size(), ExProfile.stash_cap()]
	_tab_bag.button_pressed = _list == "bag"
	_tab_stash.button_pressed = _list == "stash"
	for k: String in _filter_btns:
		(_filter_btns[k] as Button).button_pressed = k == _filter
	for c in _grid.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	_tiles.clear()
	var items := _items()
	for i in items.size():
		var it: Dictionary = items[i]
		if not _match(it, _filter):
			continue
		var t := MetaKit.tile(it, TILE, str(_sel.get("src", "")) == _list and int(_sel.get("i", -1)) == i)
		t.pressed.connect(select.bind(_list, i))
		_grid.add_child(t)
		_tiles.append([i, t])
	# 空格子补到整行（看得出还有多少地方）；筛选时不补
	if _filter == "all":
		var cap := ExProfile.stash_cap() if _list == "stash" else ExProfile.BAG_CAP
		for _i in maxi(cap - items.size(), 0):
			var e := MetaKit.tile({}, TILE)
			e.disabled = true
			_grid.add_child(e)
	_grid.columns = COLS
	# 仓库底下：扩容
	var cost := ExData.wh_next_cost(ExProfile.wh_level())
	_grow.visible = _list == "stash"
	if cost.is_empty():
		_grow.text = "仓库已满级"
		_grow.disabled = true
	else:
		_grow.disabled = false
		_grow.text = ("扩容 +6 格　%s 灵石" % NumFmt.fmt(float(cost[0]))) if int(cost[0]) > 0 else "扩容 +6 格　仓库凭证 %d/%d" % [ExProfile.vouchers(), int(cost[1])]
	# 没选着东西（刚进来 / 刚做完一件事 / 换了一边）：自动选第一件，右边不空着
	if _sel.is_empty() and not _tiles.is_empty():
		_sel = {"src": _list, "i": int((_tiles[0] as Array)[0]), "slot": ""}
		((_tiles[0] as Array)[1] as MetaKit.Tile).set_selected(true)
	if animate:
		_cascade(0.0)


func _cascade(delay: float) -> void:
	var arr: Array = []
	for c in _grid.get_children():
		if not c.is_queued_for_deletion() and c is Control:
			arr.append(c)
	MetaKit.cascade(arr.slice(0, 40), 0.014, delay)


func _clear(box: Node) -> void:
	for c in box.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()


func _rebuild_detail() -> void:
	_clear(_d_box)
	_clear(_acts)
	var it := _sel_item()
	var w := DETAIL_W - 40.0
	var has := not it.is_empty()
	_detail.visible = has
	for i in 4:
		(get_node("Corner%d" % i) as CanvasItem).visible = has
	if not has:
		_sel = {}
		return
	var q := int(it.get("q", 1))
	var qc := MetaKit.q_col(q)
	# 大图标：一团品质色的光 + 图标
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
	_d_box.add_child(MetaKit.para(ExData.desc(it).replace("　", "\n"), 22, w, MetaKit.TEXT))      # 说明里用全角空格隔开的几项：一项一行
	if ExData.can_sell(it):
		var val := "值 %s 灵石" % NumFmt.fmt(float(ExData.unit_value(it)))
		if n > 1:
			val = "每个 %s，共 %s 灵石" % [NumFmt.fmt(float(ExData.unit_value(it))), NumFmt.fmt(float(ExData.value_of(it)))]
		_d_box.add_child(MetaKit.para(val, 21, w, MetaKit.GOLD))
	# 穿上 / 卸下之后战力变多少
	var pc: Variant = _power_change(it)
	if pc != null:
		var d := int(pc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := MetaKit.label("战力", 24, MetaKit.TEXT_DIM)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
		row.add_child(MetaKit.label(("+" if d > 0 else ("-" if d < 0 else "")) + MetaKit.fmt_int(absi(d)), 30,
				MetaKit.JADE if d > 0 else (MetaKit.BAD if d < 0 else MetaKit.TEXT_DIM)))
		_d_box.add_child(row)
	MetaKit.fade_in(_d_box, 0.0, 0.16)
	# 能做的事
	var src := str(_sel["src"])
	var i := int(_sel["i"])
	if src == "equip":
		var slot := str(_sel.get("slot", ""))
		_act("卸下", "gold", _do_unequip.bind(slot, i))
		if slot == "chip" and ExData.repair_cost(it) > 0:
			_act("修理　%s 灵石" % NumFmt.fmt(float(ExData.repair_cost(it))), "ghost", _do_repair.bind("chip", i))
		return
	var wear := ExData.wearable(it)
	if wear:
		_act("穿戴", "primary", _do_equip.bind(src, i))
	if src == "bag":
		_act("存进仓库", "gold", _do_move.bind("bag", i, "stash"))
	else:
		_act("带上", "gold" if wear else "primary", _do_move.bind("stash", i, "bag"))
	if ExData.repair_cost(it) > 0:
		_act("修理　%s 灵石" % NumFmt.fmt(float(ExData.repair_cost(it))), "ghost", _do_repair.bind(src, i))
	if ExData.can_sell(it):
		if n > 1:
			_act("卖 1 个　%s" % NumFmt.fmt(float(ExData.unit_value(it))), "ghost", _do_sell.bind(src, i, 1))
		_act(("全部卖出　%s" if n > 1 else "卖出　%s") % NumFmt.fmt(float(ExData.value_of(it))), "ghost", _do_sell.bind(src, i, -1))


func _act(text: String, kind: String, fn: Callable) -> void:
	var b := MetaKit.button(text, DETAIL_W - 40.0, 62.0, kind, 25)
	b.pressed.connect(fn)
	_acts.add_child(b)


# ====================================================================
# 操作
# ====================================================================

## 翻到背包 / 仓库
func goto(which: String) -> void:
	which = "stash" if which == "stash" else "bag"
	if which == _list and not _tiles.is_empty():
		_tab_bag.button_pressed = _list == "bag"
		_tab_stash.button_pressed = _list == "stash"
		return
	_list = which
	_sel = {}
	_sync_selected()
	shell.call("click", 1.1)
	_rebuild_grid(true)
	_rebuild_detail()
	_scroll.scroll_vertical = 0
	if _us.x > 0.0:
		layout(_us)


func set_filter(f: String) -> void:
	_filter = f
	_sel = {}
	_sync_selected()
	shell.call("click", 1.2)
	_rebuild_grid(true)
	_rebuild_detail()
	_scroll.scroll_vertical = 0


## 选中一件。src：bag / stash / equip；equip 时 slot = weapon / armor / chip
func select(src: String, i: int, slot := "") -> void:
	_sel = {"src": src, "i": i, "slot": slot}
	shell.call("click")
	_sync_selected()
	_rebuild_detail()


func _sync_selected() -> void:
	var src := str(_sel.get("src", ""))
	for e: Array in _tiles:
		(e[1] as MetaKit.Tile).set_selected(src == _list and int(_sel.get("i", -1)) == int(e[0]))
	for k: String in _slots:
		var parts := k.split(":")
		(_slots[k] as MetaKit.Tile).set_selected(src == "equip" and str(_sel.get("slot", "")) == parts[0] and int(_sel.get("i", -1)) == int(parts[1]))


## 点装备栏：有东西 = 选中它；空的 = 筛出能穿在这一格的（这一边没有就翻到另一边，都没有就说一声）
func _on_slot(slot: String, idx: int) -> void:
	if not _equip_item(slot, idx).is_empty():
		select("equip", idx, slot)
		return
	var has_here := false
	var has_other := false
	for it: Dictionary in _items():
		if str(it.get("kind", "")) == slot:
			has_here = true
	for it2: Dictionary in (ExProfile.bag() if _list == "stash" else ExProfile.stash()):
		if str(it2.get("kind", "")) == slot:
			has_other = true
	if not has_here and not has_other:
		shell.call("toast", "还没有%s" % str(ExData.KIND_NAMES.get(slot, "")))
		return
	if not has_here:
		_list = "bag" if _list == "stash" else "stash"
	_sel = {}
	_filter = slot
	_sync_selected()
	shell.call("click", 1.2)
	_rebuild_grid(true)
	_rebuild_detail()
	if _us.x > 0.0:
		layout(_us)
	MetaKit.pop(_slots["%s:%d" % [slot, idx]] as Control, 1.15)


func _center(c: Control) -> Vector2:
	return c.get_global_transform() * (c.size * 0.5)


func _tile_at(i: int) -> Control:
	for e: Array in _tiles:
		if int(e[0]) == i:
			return e[1]
	return null


func _fail(e: String) -> bool:
	if e != "":
		shell.call("warn", e)
		_rebuild_detail()
		return true
	return false


func _do_equip(src: String, i: int) -> void:
	var it := _sel_item()
	var from := _tile_at(i)
	var p0 := _center(from) if from != null else Vector2.ZERO
	var tex := ExItemView.icon(it)
	var so := ExData.slot_of(it)
	if _fail(ExProfile.equip(src, i)):
		return
	_sel = {}
	refresh()
	_doll.flourish(WEAR_POSE.get(ExProfile.hero(), []))
	# 图标飞到它那一格
	var key := "%s:%d" % [str(so[0]) if so.size() > 0 else "", int(so[1]) if so.size() > 1 else 0]
	var to: Control = _slots.get(key)
	if to == null:
		for k: String in _slots:      # 法宝穿到哪一格由存档定：找名字对得上的那一格
			var t := _slots[k] as MetaKit.Tile
			if k.begins_with(str(it.get("kind", ""))) and str(t.item.get("id", "")) == str(it.get("id", "")):
				to = t
	if to != null and from != null:
		shell.call("fly", tex, p0, _center(to), func() -> void:
			if is_instance_valid(to):
				MetaKit.pop(to, 1.2))


func _do_unequip(slot: String, idx: int) -> void:
	var it := _sel_item()
	var from: Control = _slots.get("%s:%d" % [slot, idx])
	var p0 := _center(from) if from != null else Vector2.ZERO
	if _fail(ExProfile.unequip(slot, idx)):
		return
	_sel = {}
	refresh()
	_doll.flourish()
	shell.call("fly", ExItemView.icon(it), p0, _center(_tab_bag), func() -> void: MetaKit.pop(_tab_bag, 1.08))


func _do_move(src: String, i: int, dst: String) -> void:
	var it := _sel_item()
	var from := _tile_at(i)
	var p0 := _center(from) if from != null else Vector2.ZERO
	if _fail(ExProfile.move(src, i, dst)):
		return
	_sel = {}
	refresh()
	shell.call("click", 0.9)
	var tab := _tab_stash if dst == "stash" else _tab_bag
	shell.call("fly", ExItemView.icon(it), p0, _center(tab), func() -> void: MetaKit.pop(tab, 1.08))


func _do_repair(src_or_slot: String, i: int) -> void:
	if _fail(ExProfile.repair(src_or_slot, i)):
		return
	refresh()
	shell.call("sfx", "pickup", -8.0, 1.2)


## 卖出：品质高的（史诗起）先问一句
func _do_sell(src: String, i: int, cnt: int) -> void:
	var it := _sel_item()
	if it.is_empty():
		return
	var n := maxi(int(it.get("n", 1)), 1)
	var gain := ExData.unit_value(it) * (n if cnt < 0 else cnt)
	var go := func() -> void:
		if _fail(ExProfile.sell(src, i, cnt)):
			return
		var keep := _sel.duplicate()
		_sel = {}
		refresh()
		# 还是同一样东西（一叠卖掉一个）就接着选它
		var l := ExProfile.stash() if src == "stash" else ExProfile.bag()
		if src == _list and i < l.size() and str((l[i] as Dictionary).get("id", "")) == str(it.get("id", "")):
			_sel = keep
			_sync_selected()
			_rebuild_detail()
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "+%s 灵石" % NumFmt.fmt(float(gain)))
	if ExData.sell_confirm(it):
		shell.call("confirm", "%s 是%s之物，卖出得 %s 灵石\n确定卖掉吗？" % [str(it.get("name", "")), ExData.q_name(int(it.get("q", 1))), NumFmt.fmt(float(gain))],
				"卖出", go)
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


func detail_name() -> String:
	return str(_sel_item().get("name", ""))


func list_key() -> String:
	return _list


## 现在算出来的战力（数字可能还在滚）
func power_shown() -> int:
	return _power
