extends Control
## 「备战」页（挂在 meta_ui.gd 的壳里）。2026-11-24 用户定的：原来的「备战」和「仓库」合成一个入口 ——
## 「左侧是玩家形象，周围是装备的武器，右侧就是仓库」（给的参考是：左边人物 + 装备格，中间物品格子，右边选中那件的说明）。
## 同一天第二轮（用户看过第一版）：「现在有太多废话文字了，备战标题可以不要，穿在身上的...不掉落，这些提示词也不用」
## 「备战的界面我不希望能跳到换角色的入口」「角色下面不用说明打怪，打人的伤害值，我希望是一个战力值在这里，玩家穿脱装备这里的数值实时更新，让玩家看的更爽」。
## 2026-11-25 主干解耦：回到吃丹修仙，数据全走 raid_profile.gd（老洞府 abode_ui.gd 那套），版式 / 动画照旧：
##   左：出战的英雄（3D 小像，手指能转着看）；左列 3 格 = 佩戴法宝（陨落即失），右列 4 格 = 随身丹符（进图直接放进背包）；
##       人物脚下：境界 · 第几层 + 一道修为细条，下面一个大大的战力（CS.power，和左上玩家牌同一个数），佩戴 / 取下法宝时滚数 + 「+N / -N」。
##       局内（洞府锁着）或修为到了瓶颈时左上角一行字，平时不写
##   中：「仓库」「储物戒」两页 + 一排筛选（全部 / 法宝 / 丹药 / 破境 / 灵草 / 灵材 / 符箓）+ 物品格子（仓库里一样的东西叠成一格）；
##       仓库底下「领取散修行囊」（穷到没法宝时才有），储物戒底下「扩到 N 格」
##   右：选中那件的大图标、名字、品阶、说明、值多少、佩戴 / 取下后战力变多少，下面能做的事：
##       佩戴 / 随身带上 / 服下（和主城底部一键服丹同一份逻辑：hall_pills.gd 的 eat_stack）/ 收进储物戒 / 卖出 / 取下 / 放回仓库 / 取回仓库
## 一进来 / 换一边 / 做完一件事都自动选中一件（右边不会空着）；一件都没有时右边那块收起来。
## 点空的法宝格 = 筛出法宝、点空的随身格 = 筛出丹药。穿戴 / 挪动时图标飞过去、人亮个相。
## 自检用的接口：goto / set_filter / select / press_action / action_texts / detail_name / power_shown / list_key / foot_text / press_foot。故意不写 class_name。

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const HeroDoll := preload("res://scripts/ex/hero_doll.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const HallPills := preload("res://scripts/hall_pills.gd")
const Abode := preload("res://scripts/abode_ui.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const BAR_H := 96.0
const MARGIN := 28.0
const SLOT := Vector2(98.0, 98.0)
const TILE := Vector2(110.0, 124.0)
const GAP := 10.0
const COLS := 5
const DETAIL_W := 352.0
const CORNER := 54.0
const POWER_H := 150.0
const FILTERS := [["all", "全部"], ["gear", "法宝"], ["pill", "丹药"], ["break", "破境"], ["herb", "灵草"], ["mat", "灵材"], ["tool", "符箓"]]
## 穿戴时人摆的姿势（combat_poses.gd 的 SEQ；没有的英雄只亮石台）
const WEAR_POSE := {"canghong": ["ck_iai"], "yujian": ["f_point"]}

var shell: Control               # meta_ui.gd
var start := ""                  # 一进来翻到哪（"ring" = 储物戒，别的 = 仓库）

var _list := "stash"             # 中间显示哪一边：stash / ring
var _filter := "all"
var _sel := {}                   # {src: stash / ring / gear / carry, i, key（仓库里那一叠的叠放键）}
var _us := Vector2(1600, 900)
var _power := -1                 # 现在显示的战力（-1 = 还没算过）
var _power_n := 0

var _ring: TextureRect
var _doll: HeroDoll
var _slots := {}                 # "gear:0" / "carry:2" → Tile
var _slot_box: Control
var _pw_box: Control
var _pw_cap: Label
var _pw_num: Label
var _pw_delta: Label
var _rl: Label                   # 「元婴期 · 第 2 层」
var _xb: Control                 # 修为细条
var _xb_k := 0.0
var _xb_cap := false
var _entry: Label
var _mid: Control
var _tab_bag: Button             # 「仓库」（变量名照旧：飞图标都认它）
var _tab_stash: Button           # 「储物戒」
var _filter_row: HBoxContainer
var _filter_btns := {}
var _scroll: ScrollContainer
var _grid: GridContainer
var _grow: Button
var _tiles: Array = []           # 现在格子里的 [下标, Tile]
var _detail: PanelContainer
var _d_box: VBoxContainer
var _acts: VBoxContainer
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start == "ring":
		_list = "ring"
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
	_doll.hero_id = Profile.hero()
	add_child(_doll)
	_slot_box = Control.new()
	_slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_box)
	# 境界 + 修为条 + 战力：一行字、一道细条、一行小字 + 一个大数，两边各一朵祥云
	_pw_box = Control.new()
	_pw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pw_box)
	for i in 2:
		var cl := MetaKit.art("meta_cloud", Vector2(92, 92), Color(MetaKit.GOLD, 0.55))
		cl.flip_h = i == 0
		cl.name = "Cloud%d" % i
		_pw_box.add_child(cl)
	_rl = MetaKit.outlined(MetaKit.label("", 24, MetaKit.TEXT), 5)
	_rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pw_box.add_child(_rl)
	_xb = Control.new()
	_xb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xb.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _xb.size)
		_xb.draw_style_box(MetaKit.box(Color(0.07, 0.065, 0.08, 0.85), Color(MetaKit.GOLD, 0.45), 1.0, 5.0), r)
		var w := (r.size.x - 4.0) * _xb_k
		if w > 2.0:
			_xb.draw_style_box(MetaKit.box(MetaKit.CINNABAR if _xb_cap else MetaKit.JADE, Color(0, 0, 0, 0), 0.0, 3.0), Rect2(2.0, 2.0, w, r.size.y - 4.0)))
	_pw_box.add_child(_xb)
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
	_tab_bag = MetaKit.tab("仓库", 232.0)
	_tab_bag.pressed.connect(goto.bind("stash"))
	_mid.add_child(_tab_bag)
	_tab_stash = MetaKit.tab("储物戒", 232.0)
	_tab_stash.pressed.connect(goto.bind("ring"))
	_mid.add_child(_tab_stash)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 7)
	_mid.add_child(_filter_row)
	for f: Array in FILTERS:
		var b := MetaKit.tab(str(f[1]), 78.0, 46.0, 21)
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
	_grow.pressed.connect(_do_foot)
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
	_tab_stash.position = Vector2(242.0, 0.0)
	_filter_row.position = Vector2(0.0, 70.0)
	_filter_row.size = Vector2(gw, 46.0)
	var foot := 68.0 if _grow.visible else 0.0
	_scroll.position = Vector2(0.0, 130.0)
	_scroll.size = Vector2(mw, _mid.size.y - 130.0 - foot)
	_grow.position = Vector2(0.0, _mid.size.y - 58.0)
	_grow.size = Vector2(gw, 56.0)
	# 左：人、两列格子、境界 + 战力
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
		if parts[0] == "gear":
			t.position = Vector2(0.0, 18.0 + float(idx) * (SLOT.y + 16.0))
		else:
			t.position = Vector2(col_r, float(idx) * (SLOT.y + 12.0))
	var dl := SLOT.x - 16.0
	var dw := lw - dl * 2.0
	_doll.position = Vector2(lx + dl, BAR_H - 6.0)
	_doll.size = Vector2(dw, bottom - POWER_H + 4.0 - (BAR_H - 6.0))      # 石台的底边停在境界那行字上面
	var cx := lx + dl + dw * 0.5
	var rs := minf(dw * 1.18, 600.0)
	_ring.size = Vector2(rs, rs)
	_ring.pivot_offset = _ring.size * 0.5
	_ring.position = Vector2(cx - rs * 0.5, _doll.position.y + _doll.size.y * 0.47 - rs * 0.5)
	# 境界 + 战力：居中在人脚下
	var pw := minf(lw, 460.0)
	_pw_box.position = Vector2(cx - pw * 0.5, bottom - POWER_H)
	_pw_box.size = Vector2(pw, POWER_H)
	_pw_box.pivot_offset = _pw_box.size * 0.5
	_rl.position = Vector2(0.0, -4.0)
	_rl.size = Vector2(pw, _rl.get_minimum_size().y)
	var bw := minf(pw - 40.0, 300.0)
	_xb.position = Vector2((pw - bw) * 0.5, 30.0)
	_xb.size = Vector2(bw, 9.0)
	_pw_cap.position = Vector2(0.0, 42.0)
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

func _src_list(src: String) -> Array:
	match src:
		"stash":
			return Profile.stash()
		"ring":
			return Profile.ring()
		"gear":
			return Profile.gear()
		"carry":
			return Profile.carry()
	return []


func _items() -> Array:
	return _src_list(_list)


static func _match(it: Dictionary, f: String) -> bool:
	var kind := str(it.get("kind", ""))
	match f:
		"all":
			return true
		"break":
			return kind == "key" or kind == "frag"
	return kind == f


func _sel_item() -> Dictionary:
	if _sel.is_empty():
		return {}
	var l := _src_list(str(_sel["src"]))
	var i := int(_sel["i"])
	return l[i] if i >= 0 and i < l.size() else {}


## 仓库里选中那一叠有几件（不是仓库 = 1）
func _sel_count() -> int:
	if str(_sel.get("src", "")) != "stash":
		return 1
	var key := str(_sel.get("key", ""))
	var n := 0
	for it: Dictionary in Profile.stash():
		if Abode._stack_key(it) == key:
			n += 1
	return maxi(n, 1)


func _power_of(gear: Array) -> int:
	var r := Profile.realm()
	return MetaKit.power(r, int(Profile.cult(r)[0]), gear)


## 选中的法宝佩戴上（仓库里的）或取下（身上的）之后战力变多少；算不了的（法宝栏满了、不是法宝）返回 null
func _power_change(it: Dictionary) -> Variant:
	if it.is_empty() or str(it.get("kind", "")) != "gear":
		return null
	var g: Array = Profile.gear().duplicate()
	var now := _power_of(g)
	var src := str(_sel.get("src", ""))
	if src == "gear":
		g.remove_at(int(_sel["i"]))
		return _power_of(g) - now
	if src != "stash" or g.size() >= Profile.GEAR_SLOTS:
		return null
	g.append(it)
	return _power_of(g) - now


# ====================================================================
# 刷新
# ====================================================================

## 整页按存档重画（做完一件事之后；英雄换了也走这里）
func refresh() -> void:
	_doll.set_hero(Profile.hero())
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
	var defs: Array = []
	var gear := Profile.gear()
	for s in Profile.GEAR_SLOTS:
		defs.append(["gear", s, gear[s] if s < gear.size() else {}, MetaKit.tex("meta_slot_chip")])
	var carry := Profile.carry()
	for s in Profile.CARRY_SLOTS:
		defs.append(["carry", s, carry[s] if s < carry.size() else {}, UiStyle.icon("tool" if s == Profile.CARRY_SLOTS - 1 else "pill")])
	for e: Array in defs:
		var slot := str(e[0])
		var idx := int(e[1])
		var it: Dictionary = e[2]
		var t := MetaKit.tile(it, SLOT, str(_sel.get("src", "")) == slot and int(_sel.get("i", -1)) == idx)
		t.empty_icon = e[3]
		t.show_name = false
		t.pressed.connect(_on_slot.bind(slot, idx))
		_slot_box.add_child(t)
		_slots["%s:%d" % [slot, idx]] = t


## 境界 / 修为条、战力（变了就滚过去、冒出差值）和左上角那行字（局内锁着 / 修为到了瓶颈才写）
func _rebuild_status() -> void:
	var r := Profile.realm()
	var cu := Profile.cult(r)
	var lv := int(cu[0])
	_rl.text = "%s期 · 第 %d 层" % [str(Realm.LIST[r]["name"]), lv - r * Prog.LV_PER_REALM]
	_rl.add_theme_color_override("font_color", MetaKit.realm_col(r).lightened(0.3))
	_xb_cap = Prog.profile_at_cap()
	_xb_k = 1.0 if _xb_cap else clampf(float(cu[1]) / maxf(Prog.xp_need(lv), 1.0), 0.0, 1.0)
	_xb.queue_redraw()
	var v := _power_of(Profile.gear())
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
	var err := ""
	var col2 := MetaKit.BAD
	if Profile.in_raid():
		err = Profile.RAID_LOCK
	elif _xb_cap and r < Prog.REALMS - 1:
		err = "修为已至瓶颈 · 带上%s去修炼场渡劫" % str(Items.KEYS[r + 1])
		col2 = MetaKit.GOLD
	_entry.visible = err != ""
	_entry.text = err
	_entry.add_theme_color_override("font_color", col2)


func _rebuild_grid(animate: bool) -> void:
	_tab_bag.text = "仓库 %d/%d" % [Profile.stash_slots(), Profile.STASH_CAP]
	_tab_stash.text = "储物戒 %d/%d" % [Items.slots_used(Profile.ring()), Profile.ring_cap()]
	_tab_bag.button_pressed = _list == "stash"
	_tab_stash.button_pressed = _list == "ring"
	for k: String in _filter_btns:
		(_filter_btns[k] as Button).button_pressed = k == _filter
	for c in _grid.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	_tiles.clear()
	var items := _items()
	var sel_src := str(_sel.get("src", ""))
	# 仓库：一样的东西叠成一格（abode_ui._stacks，和老洞府一致）；储物戒一件一格
	var rows: Array = []
	if _list == "stash":
		rows = Abode._stacks(items)
	else:
		for i in items.size():
			rows.append([i, 1])
	for st: Array in rows:
		var i := int(st[0])
		var it: Dictionary = items[i]
		if not _match(it, _filter):
			continue
		var on := sel_src == _list and (int(_sel.get("i", -1)) == i or (_list == "stash" and str(_sel.get("key", "")) == Abode._stack_key(it)))
		var t := MetaKit.tile(it, TILE, on)
		if int(st[1]) > 1:
			t.corner = "×%d" % int(st[1])
		elif Items.size_of(it) > 1 and _list == "ring":
			t.corner = "2格"
		t.pressed.connect(select.bind(_list, i))
		_grid.add_child(t)
		_tiles.append([i, t])
	# 空格子补到上限（看得出还有多少地方）；筛选时不补
	if _filter == "all":
		var left := (Profile.STASH_CAP - Profile.stash_slots()) if _list == "stash" else (Profile.ring_cap() - Items.slots_used(Profile.ring()))
		for _i in maxi(left, 0):
			var e := MetaKit.tile({}, TILE)
			e.disabled = true
			_grid.add_child(e)
	_grid.columns = COLS
	# 底下一颗：仓库 = 领散修行囊（穷到没法宝时才有）；储物戒 = 扩格
	if _list == "stash":
		_grow.visible = Profile.kit_ok()
		_grow.disabled = false
		_grow.text = "领取散修行囊"
	else:
		var price := Profile.ring_next_price()
		_grow.visible = true
		_grow.disabled = price <= 0
		_grow.text = ("扩到 %d 格　%s 灵石" % [Profile.ring_cap() + 1, NumFmt.fmt(float(price))]) if price > 0 else "储物戒已是最大"
	# 没选着东西（刚进来 / 刚做完一件事 / 换了一边）：自动选第一件，右边不空着
	if _sel.is_empty() and not _tiles.is_empty():
		var i0 := int((_tiles[0] as Array)[0])
		_sel = {"src": _list, "i": i0, "key": Abode._stack_key(items[i0]) if _list == "stash" else ""}
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
	var qc := MetaKit.item_col(it)
	# 大图标：一团品阶色的光 + 图标
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
	var n := _sel_count()
	var nm := MetaKit.label(str(it.get("name", "")) + (("  ×%d" % n) if n > 1 else ""), 34, qc.lightened(0.2), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(w, 0)
	_d_box.add_child(nm)
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 8)
	var tw := Items.tier_word(it)
	if tw != "" and tw != MetaKit.kind_name(it):      # 品阶「法宝」和种类「法宝」同名时只写一个
		tags.add_child(MetaKit.tag(tw, qc))
	tags.add_child(MetaKit.tag(MetaKit.kind_name(it), MetaKit.TEXT_DIM))
	_d_box.add_child(tags)
	_d_box.add_child(MetaKit.divider(w))
	_d_box.add_child(MetaKit.para(Items.desc(it).replace("；", "\n"), 22, w, MetaKit.TEXT))      # 说明里用分号隔开的几项：一项一行
	var src := str(_sel["src"])
	var i := int(_sel["i"])
	var kind := str(it.get("kind", ""))
	var val := int(it.get("value", 0))
	if val > 0:
		var vt := "值 %s 灵石" % NumFmt.fmt(float(val))
		if n > 1:
			vt = "每个 %s，共 %s 灵石" % [NumFmt.fmt(float(val)), NumFmt.fmt(float(val * n))]
		_d_box.add_child(MetaKit.para(vt, 21, w, MetaKit.GOLD))
	# 通往下一境的破境丹：修为到了瓶颈时多一行
	var r := Profile.realm()
	if kind == "key" and int(it.get("to", 0)) == r + 1 and Prog.profile_at_cap():
		_d_box.add_child(MetaKit.para("修为已至瓶颈 · 去修炼场渡劫（另需 %s 灵石）" % NumFmt.fmt(float(Prog.break_cost(r + 1))), 21, w, MetaKit.JADE))
	# 佩戴 / 取下之后战力变多少
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
	match src:
		"gear":
			_act("取下", "gold", _do_move.bind("gear", i, "stash"))
			return
		"carry":
			_act("放回仓库", "gold", _do_move.bind("carry", i, "stash"))
			return
		"ring":
			_act("取回仓库", "gold", _do_move.bind("ring", i, "stash"))
			return
	if kind == "gear":
		_act("佩戴", "primary", _do_move.bind("stash", i, "gear"))
	elif ["pill", "key", "tool"].has(kind):
		_act("随身带上", "gold" if Items.is_xp_pill(it) else "primary", _do_move.bind("stash", i, "carry"))
	if Items.is_xp_pill(it):
		var e := Prog.pill_use_err(it, r)
		if e == "":
			_act("服下", "primary", _do_eat.bind(i, 1))
			if n > 1:
				_act("服下这一摞 ×%d" % n, "gold", _do_eat.bind(i, -1))
		else:
			_d_box.add_child(MetaKit.para(e, 20, w, MetaKit.BAD))
	_act("收进储物戒", "ghost", _do_move.bind("stash", i, "ring"))
	if val > 0:
		_act("卖出　%s" % NumFmt.fmt(float(val)), "ghost", _do_sell.bind(i, 1))
		if n > 1:
			_act("卖出这一摞　%s" % NumFmt.fmt(float(val * n)), "ghost", _do_sell.bind(i, -1))


func _act(text: String, kind: String, fn: Callable) -> void:
	var b := MetaKit.button(text, DETAIL_W - 40.0, 58.0, kind, 24)
	b.pressed.connect(fn)
	_acts.add_child(b)


# ====================================================================
# 操作
# ====================================================================

## 翻到仓库 / 储物戒（老的 bag 当仓库）
func goto(which: String) -> void:
	which = "ring" if which == "ring" else "stash"
	if which == _list and not _tiles.is_empty():
		_tab_bag.button_pressed = _list == "stash"
		_tab_stash.button_pressed = _list == "ring"
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


## 选中一件。src：stash / ring / gear / carry（第三个参数留着兼容老调用，不用）
func select(src: String, i: int, _slot := "") -> void:
	var l := _src_list(src)
	_sel = {"src": src, "i": i, "key": Abode._stack_key(l[i]) if src == "stash" and i >= 0 and i < l.size() else ""}
	shell.call("click")
	_sync_selected()
	_rebuild_detail()


func _sync_selected() -> void:
	var src := str(_sel.get("src", ""))
	var key := str(_sel.get("key", ""))
	var items := _items()
	for e: Array in _tiles:
		var i := int(e[0])
		var on := src == _list and (int(_sel.get("i", -1)) == i or (key != "" and i < items.size() and Abode._stack_key(items[i]) == key))
		(e[1] as MetaKit.Tile).set_selected(on)
	for k: String in _slots:
		var parts := k.split(":")
		(_slots[k] as MetaKit.Tile).set_selected(src == parts[0] and int(_sel.get("i", -1)) == int(parts[1]))


## 点左右两列：有东西 = 选中它；空的 = 仓库里筛出能放进这一格的（法宝 / 丹药）
func _on_slot(slot: String, idx: int) -> void:
	if idx < _src_list(slot).size():
		select(slot, idx)
		return
	var want := "gear" if slot == "gear" else "pill"
	var has := false
	for it: Dictionary in Profile.stash():
		var k := str(it.get("kind", ""))
		if k == want or (slot == "carry" and (k == "key" or k == "tool")):
			has = true
	if not has:
		shell.call("toast", "仓库里还没有%s" % ("法宝" if slot == "gear" else "丹符"))
		return
	_list = "stash"
	_sel = {}
	_filter = want
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


## 做完一件事之后：仓库里那一叠还有剩的就接着选它（连着卖、连着带，不用回头再点）
func _reselect(key: String) -> void:
	_sel = {}
	if key == "" or _list != "stash":
		return
	var st := Profile.stash()
	for j in st.size():
		if Abode._stack_key(st[j]) == key:
			_sel = {"src": "stash", "i": j, "key": key}
			return


## 挪一件：stash → gear 佩戴 / carry 随身带上 / ring 收进储物戒；gear / carry / ring → stash 取下 / 放回 / 取回
func _do_move(src: String, i: int, dst: String) -> void:
	var it := _sel_item()
	var key := str(_sel.get("key", ""))
	var from: Control = _tile_at(i) if src == "stash" or src == "ring" else _slots.get("%s:%d" % [src, i])
	var p0 := _center(from) if from != null else Vector2.ZERO
	var e := "动不了"
	match src + ">" + dst:
		"stash>gear":
			e = Profile.equip(i)
		"stash>carry":
			e = Profile.pack(i)
		"stash>ring":
			e = Profile.to_ring(i)
		"gear>stash":
			e = Profile.unequip(i)
		"carry>stash":
			e = Profile.unpack(i)
		"ring>stash":
			e = Profile.from_ring(i)
	if _fail(e):
		return
	_reselect(key if src == "stash" else "")
	refresh()
	var to: Control = null
	match dst:
		"gear":
			to = _slots.get("gear:%d" % (Profile.gear().size() - 1))
			_doll.flourish(WEAR_POSE.get(Profile.hero(), []))
		"carry":
			to = _slots.get("carry:%d" % (Profile.carry().size() - 1))
		"ring":
			to = _tab_stash
		_:
			to = _tab_bag
			if src == "gear":
				_doll.flourish()
	shell.call("click", 0.9)
	if to != null and from != null:
		shell.call("fly", MetaKit.icon(it), p0, _center(to), func() -> void:
			if is_instance_valid(to):
				MetaKit.pop(to, 1.12))


## 服下仓库第 i 件那一摞里的 cnt 颗（-1 = 整摞）：和主城底部「一键服丹」同一份逻辑（hall_pills.gd 的 eat_stack）
func _do_eat(i: int, cnt: int) -> void:
	var key := str(_sel.get("key", ""))
	var res: Dictionary = HallPills.eat_stack(i, cnt)
	if _fail(str(res["err"]) if int(res["n"]) == 0 else ""):
		return
	_reselect(key)
	refresh()
	shell.call("sfx", "ascend", -10.0, 1.3)
	var txt := "修为 +%s" % NumFmt.fmt(float(res["got"]))
	if int(res["ups"]) > 0:
		txt += "　修为精进 Lv.%d" % int(res["lv"])
	shell.call("ok", txt)


## 卖出仓库第 i 件那一叠里的 cnt 件（-1 = 整叠）：古宝以上 / 破境丹先问一句
func _do_sell(i: int, cnt: int) -> void:
	var it := _sel_item()
	if it.is_empty():
		return
	if Profile.in_raid():
		_fail(Profile.RAID_LOCK)
		return
	var key := str(_sel.get("key", ""))
	var n := _sel_count() if cnt < 0 else 1
	var gain := int(it.get("value", 0)) * n
	var go := func() -> void:
		var got := 0
		var left := n
		var st := Profile.stash()
		if left == 1 and i < st.size():
			got += Profile.sell(i)
			left = 0
		var j := st.size() - 1
		while j >= 0 and left > 0:
			if Abode._stack_key(st[j]) == key:
				got += Profile.sell(j)
				left -= 1
			j -= 1
		_reselect(key)
		refresh()
		shell.call("sfx", "pickup", -8.0, 1.3)
		shell.call("ok", "+%s 灵石" % NumFmt.fmt(float(got)))
	if int(it.get("tier", 0)) >= 3 or str(it.get("kind", "")) == "key":
		shell.call("confirm", "%s%s 卖出得 %s 灵石\n确定卖掉吗？" % [str(it.get("name", "")), (" ×%d" % n) if n > 1 else "", NumFmt.fmt(float(gain))], "卖出", go)
	else:
		go.call()


## 底下那一颗：仓库 = 领散修行囊；储物戒 = 扩格
func _do_foot() -> void:
	var e := Profile.take_kit() if _list == "stash" else Profile.upgrade_ring()
	if e == "":
		shell.call("sfx", "pickup", -8.0, 0.9)
		MetaKit.pop(_tab_stash if _list == "ring" else _tab_bag, 1.1)
		shell.call("ok", "领了一份散修行囊" if _list == "stash" else "储物戒扩到 %d 格" % Profile.ring_cap())
	else:
		shell.call("warn", e)
	_sel = {}
	refresh()


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


## 底下那颗按钮现在写什么（自检用；藏着时返回 ""）
func foot_text() -> String:
	return _grow.text if _grow.visible else ""


func press_foot() -> bool:
	if not _grow.visible or _grow.disabled:
		return false
	_grow.pressed.emit()
	return true
