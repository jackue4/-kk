extends CanvasLayer
## 搜打撤的界面：右上角（背包圆按钮贴角、左边小地图、再左边一张小纸条写所在区域 / 禁地倒计时）、中上方区域与 Boss 横幅、
## 修为等级和进度在左上角的玩家牌上（player_plate.gd，hud.gd 建的；进图时把 mgr 交给它），
## 右侧拾取提示、Boss 血条、撤离 / 搜点 / 开箱读条、储物袋面板、结算面板。
## 储物袋面板（2026-11-20 改；同日晚按手机横屏重排，见 _build_panel）：左边背包格子（灵材占 2 格）+ 一排储物戒，右边一列佩戴的法宝（3 件）；
##   点一件 → 底下说明 + 能做的事（服用 / 使用 / 佩戴 / 收进储物戒 / 丢弃；法宝取下；储物戒取回），不再「一点就丢」。
##   题头右边「整理」按种类和每格价值排好，「关闭」在右上角；点面板外面的暗处也是关。B 键或画面右上角的背包按钮（触屏也是它）开关。
## 手机上各块怎么不打架（2026-11-20 晚，用户给了两张实机截图）：
##   · 拾取卡片整列放在右下角那簇战斗按钮的左边（LOOT_RIGHT_TOUCH），卡片收窄、最多露三张
##   · 拾取提示（toast）挪到左边玩家牌下面，不再压在右边的按钮和卡片上
##   · Boss 血条夹在玩家牌和右上角纸条之间，放不下就缩短
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const ItemView := preload("res://scripts/item_view.gd")
const RealmBanner := preload("res://scripts/realm_banner.gd")
const Minimap := preload("res://scripts/minimap.gd")
const Prog := preload("res://scripts/progression.gd")

const LOOT_SHOW := 4           # 拾取卡片的滚动容器最多露出几张，多的上下滑动看
const LOOT_SHOW_TOUCH := 3     # 触屏：三张（再多就伸到下面的按钮那儿去了）
const LOOT_RIGHT := 230.0      # 卡片那一列离屏幕右边缘多远（2026-11-20 用户嫌太靠右）
## 触屏：整列在右下角那簇战斗按钮的左边（touch_controls.gd 里最靠左的「诀」左缘在 -446、「罡」右缘在 -470）
const LOOT_RIGHT_TOUCH := 470.0
const LOOT_TOP_TOUCH := 270.0  # 触屏：卡片从这儿往下排（上面是空战目标面板，hud.gd 的 _tgt）
## 储物袋面板的尺寸（1600×900 的界面单位）
const BAG_SLOT := Vector2(200, 80)     # 背包格子：4 列 3 行（宽到 200 才写得下品阶那两个字，见 item_view.gd）
const RING_SLOT := Vector2(160, 62)    # 储物戒：最多 4 格，排在背包格子下面
const GEAR_W := 200.0                  # 佩戴的法宝：右边一列 3 件，高度凑到和左边一样
const PANEL_PAD := Vector2(24, 18)     # 面板离画面边缘至少留这么多（放不下就整块缩小）
const ACT_NAMES := {"use": "服用", "equip": "佩戴", "ring": "收进储物戒", "drop": "丢弃", "unequip": "取下", "unring": "取回背包"}

var font: Font
var mgr: Node3D
var touch := false
var boss: Node3D = null
var chest_k := 0.0

var _root: Control
var _info: Label
var _bag_btn: Button
var _banner: Label
var _banner_sub: Label
var _banner_t := 0.0
var _toasts: VBoxContainer
var _boss_name: Label
var _boss_bar: ColorRect
var _boss_bg: Panel
var _prog_bg: Panel
var _prog: ColorRect
var _prog_lab: Label
var _panel: PanelContainer
var _dim: ColorRect            # 面板开着时压在后面的一层淡墨：把别的界面压暗，点它 = 关闭
var _plate: Control            # 左上角的玩家牌（hud.gd 建的），摆 Boss 血条时要让开它
var _grid: GridContainer
var _gear_row: BoxContainer
var _ring_row: HBoxContainer
var _ring_lab: Label
var _detail: Label
var _acts: HBoxContainer
var _panel_title: Label
var _result: PanelContainer
var _sig := ""
var _sel := {}                 # 选中的那件：{src: bag / gear / ring, i}
var _title_fx: RealmBanner     # 进入区域时的毛笔题字
var _info_bg: Panel
var minimap: Control
var _loot_wrap: VBoxContainer   # 拾取卡片那一列（滚动容器 + 底下一行提示）
var _loot_scroll: ScrollContainer
var _loot_box: VBoxContainer    # 卡片本身
var _loot_hint: Label
var _loot_sig := ""


## 宣纸面板上的字：墨色、不描边
func _mk_ink(text: String, size: int, col := UiStyle.TEXT_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _mk(text: String, size: int, col := UiStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.92))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rect(parent: Control, col: Color, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _ready() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	_root.theme = th
	add_child(_root)

	# 右上角（位置每帧按画面宽度摆，见 _process）：背包圆按钮贴角，左边小地图，再左边一张小纸条（所在区域 / 禁地倒计时，墨字）。
	# 左上角是玩家牌（hud.gd 建的）：把 mgr 交给它，修为等级 / 进度 / 战力就按局内的算
	_plate = get_tree().get_first_node_in_group("player_plate") as Control
	if _plate != null:
		_plate.set("raid", mgr)
	minimap = Minimap.new()
	minimap.mgr = mgr
	minimap.font = font
	_root.add_child(minimap)
	_info_bg = Panel.new()
	_info_bg.add_theme_stylebox_override("panel", UiStyle.plaque())
	_info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info_bg)
	_info = _mk_ink("", 20)
	_root.add_child(_info)
	_bag_btn = UiStyle.round_icon_button("pouch")
	_bag_btn.pressed.connect(toggle_bag)
	_root.add_child(_bag_btn)
	# 触屏：手指按在这几块上时，触屏操作层（touch_controls.gd）不把它当成转镜头
	for c: Control in [_bag_btn, minimap]:
		c.add_to_group("touch_ui")
	# 拾取面板：走近掉落物时出现在画面中下方
	_loot_wrap = VBoxContainer.new()
	_loot_wrap.add_theme_constant_override("separation", 4)
	_loot_wrap.visible = false
	_loot_wrap.add_to_group("touch_ui")
	_root.add_child(_loot_wrap)
	_loot_scroll = ScrollContainer.new()
	_loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER    # 不画滚动条（底下有「上下滑动」的字）
	_loot_scroll.scroll_deadzone = 8
	_loot_wrap.add_child(_loot_scroll)
	_loot_box = VBoxContainer.new()
	_loot_box.add_theme_constant_override("separation", 6)
	_loot_scroll.add_child(_loot_box)
	_loot_hint = _mk("", 15, UiStyle.TEXT)
	_loot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_wrap.add_child(_loot_hint)
	for a: Array in [["pickup", KEY_T]]:
		if not InputMap.has_action(str(a[0])):
			InputMap.add_action(str(a[0]))
			var ev := InputEventKey.new()
			ev.physical_keycode = a[1]
			InputMap.action_add_event(str(a[0]), ev)

	_banner = _mk("", 60)
	_banner.add_theme_font_override("font", UiStyle.brush())
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_root.add_child(_banner)
	_banner_sub = _mk("", 22)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.modulate.a = 0.0
	_root.add_child(_banner_sub)

	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN if touch else BoxContainer.ALIGNMENT_END     # 触屏：贴着玩家牌往下排
	_root.add_child(_toasts)

	_boss_name = _mk("", 34, Color(1.0, 0.5, 0.4))
	_boss_name.add_theme_font_override("font", UiStyle.brush())
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_boss_name)
	_boss_bg = _frame(Vector2(560, 12))
	_boss_bar = _rect(_boss_bg, UiStyle.CINNABAR.lightened(0.15), Vector2(560, 12))

	_prog_bg = _frame(Vector2(300, 12))
	_prog = _rect(_prog_bg, UiStyle.QING, Vector2(300, 12))
	_prog_lab = _mk("", 22)
	_prog_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prog_lab)

	_build_panel()
	_title_fx = RealmBanner.new()
	_title_fx.x_frac = 0.7
	_title_fx.size_k = 0.9
	_root.add_child(_title_fx)


## 条框：细墨线、纸底（见 ui_style.gd 的 bar_frame）
func _frame(size: Vector2) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UiStyle.bar_frame())
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	return p


## 进入区域：毛笔竖排题字（一笔笔写出来，旁边一行小字，末尾钤印），不再用横幅
func title(text: String, sub: String, col: Color, seal := "境") -> void:
	_title_fx.show_realm(text, col, sub, seal)


func _small_btn(text: String, w := 150.0, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 21)
	if primary:
		UiStyle.style_primary(b)
	else:
		UiStyle.style_button(b, true)
	return b


## 储物袋面板（按手机横屏排的：宽而矮，不盖住上面的玩家牌 / 小地图）：
##   题头：朱印 + 题字 + 格数 / 价值 + 整理 + 关闭（关闭在右上角，拇指够得着）
##   中间：左边背包格子（4 列 3 行）和它下面一排储物戒；右边一列佩戴的法宝（3 件，和左边等高）
##   底下：选中物品的说明（两行的位置）+ 能做的事的按钮
## 按钮、格子都在 54 像素以上；整块的大小和位置见 _place_panel
func _build_panel() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.045, 0.04, 0.32)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _panel.visible:
			toggle_bag())
	_root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UiStyle.scroll(18.0))
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var seal := UiStyle.seal("储", 42.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(seal)
	var t := _mk_ink("储物袋", 34)
	t.add_theme_font_override("font", UiStyle.brush())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_panel_title = _mk_ink("", 20, UiStyle.TEXT_SOFT)
	_panel_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_panel_title)
	var sort := _small_btn("整理", 110.0)
	sort.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sort.pressed.connect(func() -> void:
		mgr.sort_bag()
		_sel = {})
	head.add_child(sort)
	var close := _small_btn("关闭", 120.0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(toggle_bag)
	head.add_child(close)
	v.add_child(UiStyle.rule(380.0, 7.0, Color(UiStyle.LINE, 0.82)))
	# 中间：左（背包 + 储物戒）右（法宝）
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	v.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.custom_minimum_size = Vector2(BAG_SLOT.x * 4.0 + 24.0, BAG_SLOT.y * 3.0 + 16.0)     # 格子少的时候面板也不缩
	left.add_child(_grid)
	var ring_line := HBoxContainer.new()
	ring_line.add_theme_constant_override("separation", 8)
	left.add_child(ring_line)
	_ring_lab = _mk_ink("储物戒", 20, UiStyle.TEXT_INK)
	_ring_lab.add_theme_font_override("font", UiStyle.brush())
	_ring_lab.custom_minimum_size = Vector2(112, RING_SLOT.y)
	_ring_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring_line.add_child(_ring_lab)
	_ring_row = HBoxContainer.new()
	_ring_row.add_theme_constant_override("separation", 8)
	ring_line.add_child(_ring_row)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var gl := _mk_ink("佩戴法宝", 20, UiStyle.TEXT_INK)
	gl.add_theme_font_override("font", UiStyle.brush())
	gl.custom_minimum_size = Vector2(GEAR_W, 26)
	right.add_child(gl)
	_gear_row = VBoxContainer.new()
	_gear_row.add_theme_constant_override("separation", 8)
	right.add_child(_gear_row)
	v.add_child(UiStyle.rule(380.0, 6.0, Color(UiStyle.LINE, 0.6)))
	# 底下：说明（两行的位置，免得选中 / 取消时面板一跳一跳）+ 按钮
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_detail = _mk_ink("点一件看看能做什么", 18, UiStyle.TEXT_SOFT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail.max_lines_visible = 2
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail.custom_minimum_size = Vector2(260, 56)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_detail)
	_acts = HBoxContainer.new()
	_acts.add_theme_constant_override("separation", 10)
	_acts.custom_minimum_size = Vector2(0, 54)
	_acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_acts)


## 面板居中；画面放不下（四周各留 PANEL_PAD）就整块缩小，不放大
func _place_panel(vs: Vector2) -> void:
	var ps := _panel.get_combined_minimum_size()
	_panel.size = ps
	var k := minf(1.0, minf((vs.x - PANEL_PAD.x * 2.0) / ps.x, (vs.y - PANEL_PAD.y * 2.0) / ps.y))
	_panel.scale = Vector2(k, k)
	_panel.position = ((vs - ps * k) * 0.5).round()


func bag_open() -> bool:
	return _panel.visible


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("bag"):
		toggle_bag()
	elif e.is_action_pressed("pickup"):
		mgr.pick_nearest()


## 附近的掉落物 → 屏幕右侧（离右边缘留出两百来像素）一列窄卡片（图标 + 名字，名字长了折行），一件一张，点一下就拾取。
## 箱子里的东西也拆成一张张卡片（每件单拿；联机共享的箱子点哪张都是整箱向房主申请）。
## 卡片放在一个滚动容器里，最多露出 LOOT_SHOW 张，多的上下滑动看；超过时底下写「共 N 件 · 上下滑动」。
func _card_size() -> Vector2:
	return Vector2(150, 72) if touch else Vector2(160, 72)      # 触屏：收窄（名字放不下折成两行，再长截掉）


func _loot_show() -> int:
	return LOOT_SHOW_TOUCH if touch else LOOT_SHOW


func _rebuild_loot() -> void:
	for c in _loot_box.get_children():
		_loot_box.remove_child(c)      # 立刻拿掉（只 queue_free 的话这一帧量出来的高度还是旧的）
		c.queue_free()
	var size := _card_size()
	var es: Array = mgr.loot_entries()
	for i in es.size():
		var e: Array = es[i]
		var card := ItemView.card(e[2], size, "T" if i == 0 and not touch else "")
		card.mouse_filter = Control.MOUSE_FILTER_PASS      # 按在卡片上拖也能滚动（滚动容器要收到拖动）
		card.pressed.connect(Callable(mgr, "pick_up").bind(e[0], int(e[1])))
		_loot_box.add_child(card)
	var n := es.size()
	var gap := float(_loot_box.get_theme_constant("separation"))
	_loot_scroll.custom_minimum_size = Vector2(size.x, float(mini(n, _loot_show())) * (size.y + gap) - gap)
	_loot_hint.visible = n > _loot_show()
	_loot_hint.text = "共 %d 件 · 上下滑动" % n


func toggle_bag() -> void:
	_panel.visible = not _panel.visible
	_sig = ""
	_sel = {}
	if not touch:
		if _panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif mgr.cam.capture_mouse:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _select(src: String, i: int) -> void:
	if not _sel.is_empty() and str(_sel["src"]) == src and int(_sel["i"]) == i:
		_sel = {}
	else:
		_sel = {"src": src, "i": i}
	_sig = ""


func _act(act: String) -> void:
	if _sel.is_empty():
		return
	var i := int(_sel["i"])
	match act:
		"unequip":
			mgr.unequip(i)
		"unring":
			mgr.from_ring(i)
		_:
			mgr.use_item(i, act)
	_sel = {}
	_sig = ""


func _is_sel(src: String, i: int) -> bool:
	return not _sel.is_empty() and str(_sel["src"]) == src and int(_sel["i"]) == i


func _rebuild_grid() -> void:
	# 旧的立刻拿掉（只 queue_free 的话这一帧新旧并排，面板会先撑大一下再缩回来）
	for box: Node in [_grid, _gear_row, _ring_row, _acts]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var bag: Array = mgr.bag
	for i in bag.size():
		var b := ItemView.slot(bag[i], BAG_SLOT, _is_sel("bag", i))
		b.pressed.connect(_select.bind("bag", i))
		_grid.add_child(b)
	var free: int = Data.BAG_SIZE - int(mgr.bag_used())
	for i in maxi(free, 0):
		_grid.add_child(ItemView.slot({}, BAG_SLOT))
	var gear: Array = mgr.gear
	# 右边一列法宝：三件的总高度 = 左边（背包格子 + 储物戒那一排）减掉「佩戴法宝」那行字
	var gear_h := floorf((BAG_SLOT.y * 3.0 + 16.0 + 8.0 + RING_SLOT.y - 26.0 - 6.0 - 16.0) / float(Profile.GEAR_SLOTS))
	for i in Profile.GEAR_SLOTS:
		var it: Dictionary = gear[i] if i < gear.size() else {}
		var b := ItemView.slot(it, Vector2(GEAR_W, gear_h), _is_sel("gear", i), -1, "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("gear", i))
		_gear_row.add_child(b)
	var ring: Array = mgr.ring
	var cap := Profile.ring_cap()
	_ring_lab.text = "储物戒 %d/%d" % [Items.slots_used(ring), cap]
	for i in ring.size():
		var b := ItemView.slot(ring[i], RING_SLOT, _is_sel("ring", i))
		b.pressed.connect(_select.bind("ring", i))
		_ring_row.add_child(b)
	for i in maxi(cap - Items.slots_used(ring), 0):
		_ring_row.add_child(ItemView.slot({}, RING_SLOT, false, -1, "空"))
	# 说明和按钮
	var it_sel: Dictionary = {}
	var acts: Array = []
	if not _sel.is_empty():
		var src := str(_sel["src"])
		var i := int(_sel["i"])
		var list: Array = bag if src == "bag" else (gear if src == "gear" else ring)
		if i < list.size():
			it_sel = list[i]
			if src == "bag":
				acts = mgr.bag_actions(i)
			elif src == "gear":
				acts = ["unequip"]
			else:
				acts = ["unring"]
		else:
			_sel = {}
	if it_sel.is_empty():
		_detail.text = "点一件看看能做什么。佩戴的法宝和背包陨落即失，储物戒里的保得住。"
		_detail.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	else:
		_detail.text = ItemView.detail_text(it_sel)
		_detail.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	for a: String in acts:
		var label: String = ACT_NAMES.get(a, a)
		if a == "use" and str(it_sel.get("kind", "")) == "tool":
			label = "使用"
		var b := _small_btn(label, 150.0, a == "use" or a == "equip")
		b.pressed.connect(_act.bind(a))
		_acts.add_child(b)


## 背包 / 法宝 / 储物戒 / 选中 有变化才重建
func _signature() -> String:
	var parts: Array = [str(_sel)]
	for list: Array in [mgr.bag, mgr.gear, mgr.ring]:
		var names: Array = []
		for it: Dictionary in list:
			names.append(str(it["name"]))
		parts.append(",".join(names))
	return "|".join(parts)


## 屏幕中上方的大字横幅（进入区域 / Boss 现身 / 突破）
func banner(text: String, sub: String, col: Color) -> void:
	_banner.text = text
	_banner_sub.text = sub
	_banner.add_theme_color_override("font_color", col)
	_banner_t = 3.2


func toast(text: String, col: Color) -> void:
	var l := _mk(text, 19, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if touch else HORIZONTAL_ALIGNMENT_RIGHT     # 触屏：在左边玩家牌下面（见 _process）
	_toasts.add_child(l)
	if _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## 结算。extra：{res: Profile.end_raid 的返回, lost_gear: 带进去的法宝, ring: 储物戒}
func show_result(success: bool, items: Array, value: int, kills: int, stash: int, extra := {}) -> void:
	_panel.visible = false
	_result = PanelContainer.new()
	_result.add_theme_stylebox_override("panel", UiStyle.scroll(34.0))
	_root.add_child(_result)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_result.add_child(v)
	# 题头：大字 + 一方朱印（成了钤「归」，没成钤「陨」），下面一笔枯墨
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	var big := _mk_ink("撤离成功" if success else "身死道消", 84, UiStyle.TEXT_INK if success else UiStyle.CINNABAR)
	big.add_theme_font_override("font", UiStyle.brush())
	head.add_child(big)
	var seal := UiStyle.seal("归" if success else "陨", 58.0, UiStyle.CINNABAR if success else UiStyle.TEXT_INK)
	seal.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(seal)
	var rule := UiStyle.rule(460.0, 9.0, Color(UiStyle.LINE, 0.82))
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rule)
	var res: Dictionary = extra.get("res", {})
	var lost: Array = extra.get("lost_gear", [])
	var ring: Array = extra.get("ring", [])
	## 2026-11-20 数值框架：心得的结算（raid_manager._finish 算好放进 extra）
	var ins := float(extra.get("ins", 0.0))
	var ins_gain := float(extra.get("ins_gain", 0.0))
	var ins_lost := float(extra.get("ins_lost", 0.0))
	if success:
		v.add_child(_mk_ink("带出 %d 件，共 %d 灵石，已入洞府仓库　击杀 %d" % [items.size(), value, kills], 22))
		if ins > 0.5:
			var up_txt := ("，升至 Lv.%d" % int(extra.get("lv", 0))) if int(extra.get("ins_ups", 0)) > 0 else ""
			v.add_child(_mk_ink("本局心得 %s 化作修为 +%s%s" % [Prog.short_num(ins), Prog.short_num(ins_gain), up_txt], 20, UiStyle.QING))
			if ins_lost > 0.5:
				v.add_child(_mk_ink("修为已至瓶颈，余下 %s 心得散去（先突破再来）" % Prog.short_num(ins_lost), 18, UiStyle.TEXT_SOFT))
		for i in mini(items.size(), 6):
			var it: Dictionary = items[i]
			var tw := Items.tier_word(it)      # 修为丹名字里带了品质，不再跟一个「凡品」
			v.add_child(_mk_ink("· %s　%s%d 灵石" % [it["name"], (tw + "　") if tw != "" else "", int(it["value"])], 20,
					UiStyle.on_paper(Data.TIER_COLORS[int(it["tier"])])))
		if items.size() > 6:
			v.add_child(_mk_ink("…… 另有 %d 件" % (items.size() - 6), 18, UiStyle.TEXT_SOFT))
		if int(res.get("sold", 0)) > 0:
			v.add_child(_mk_ink("仓库满了：%d 件折成 %d 灵石" % [int(res["sold"]), int(res["sold_value"])], 19, UiStyle.CINNABAR))
		if not lost.is_empty():
			v.add_child(_mk_ink("随身法宝 %d 件安然带回" % lost.size(), 19, UiStyle.TEXT_SOFT))
	else:
		v.add_child(_mk_ink("背包里的 %d 件（%d 灵石）尽数遗失　击杀 %d" % [items.size(), value, kills], 22))
		if ins > 0.5:
			if ins_gain > 0.5:
				v.add_child(_mk_ink("本局心得 %s 只留下 %s" % [Prog.short_num(ins), Prog.short_num(ins_gain)], 20, UiStyle.CINNABAR))
			else:
				v.add_child(_mk_ink("本局心得 %s 随之散去" % Prog.short_num(ins), 20, UiStyle.CINNABAR))
		if not lost.is_empty():
			var names: Array = []
			for it: Dictionary in lost:
				names.append(str(it["name"]))
			v.add_child(_mk_ink("佩戴的法宝也丢了：%s" % "、".join(names), 20, UiStyle.CINNABAR))
		if not ring.is_empty():
			var rn: Array = []
			for it: Dictionary in ring:
				rn.append(str(it["name"]))
			v.add_child(_mk_ink("储物戒保住了：%s" % "、".join(rn), 20, UiStyle.QING))
		v.add_child(_mk_ink("境界、修为不跌；回洞府重整行囊再来", 18, UiStyle.TEXT_SOFT))
	v.add_child(_mk_ink("洞府灵石 %d　· 即将返回试剑大厅…" % stash, 18, UiStyle.TEXT_SOFT))
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	_result.position = (vs - _result.size) * 0.5


func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	# 右上角的区域纸条
	var r: Dictionary = Data.REGIONS[int(mgr.region)]
	var left := int(ceilf(float(mgr.time_left())))
	var here_lv := int(mgr.here_lv)
	# 传送阵的方向和距离看小地图（贴边的青色圈 + 地图下面那行字），信息牌里不再重复
	var net_txt := ""
	if mgr.net_on():
		# 2026-11-20：回了主城看着房间的房主不算在禁地里的人
		net_txt = "\n房间 %d 人　本队 %d / %d" % [mgr.net.in_world_count(), mgr.net.team_count(), int(mgr.net.team_size)]
	# 修为等级 / 进度在左上角的玩家牌上，背包格数在背包按钮的纸签上，这里写「在哪、多凶、心得攒了多少、还剩多久」
	## 2026-11-20 数值框架：怪的等级 / 深度按主角所在处（不再有随时间涨的难度名）；心得 当前 / 本局上限；天道压制时多一行
	var cap: float = mgr.insight_cap()
	var ins: float = mgr.insight
	var where := "无涯海" if mgr.at_sea else ("%s · 怪物 Lv.%d · 深度 %d%%" % [r["name"], here_lv, roundi(float(mgr.here_depth) * 100.0)])
	var ins_txt := ("心得已满 %s" % Prog.short_num(cap)) if ins >= cap - 0.5 else ("心得 %s / %s" % [Prog.short_num(ins), Prog.short_num(cap)])
	var sup_txt := ""
	if int(mgr.sup_gap) > 0:
		sup_txt = "　天道压制 ×%d%%" % roundi(float(mgr.sup_dmg_k()) * 100.0)
	# 2026-11-20 七点之三：传送阵按房间时间轮换，写一下离下次轮换还有多久
	var rot := int(ceilf(float(mgr.rotation_left())))
	# 三行，每行都不长（一长纸条就顶到中上方的 Boss 血条和左边的玩家牌）：在哪 / 心得 + 禁地倒计时 / 阵轮转 + 天道压制
	_info.text = "%s\n%s · 禁地 %02d:%02d\n阵轮转 %d:%02d%s%s" % [where, ins_txt, left / 60, left % 60, rot / 60, rot % 60, sup_txt, net_txt]
	_info.add_theme_color_override("font_color", UiStyle.CINNABAR if int(r["lv"]) > int(mgr.lv) + 2 or left < 180 else UiStyle.TEXT_INK)
	# 右上角三件从右往左排：背包按钮贴角、小地图、纸条（大小跟着文字走：网页 / 手机上的字体行高和桌面的楷体不一样）
	_bag_btn.position = UiStyle.corner_pos(vs)
	minimap.position = Vector2(_bag_btn.position.x - 12.0 - Minimap.SIZE, 12.0)
	var ts := _info.get_minimum_size()
	_info_bg.size = Vector2(ts.x + 28.0, ts.y + 16.0)
	_info_bg.position = Vector2(minimap.position.x - 14.0 - _info_bg.size.x, 12.0)
	_info.position = _info_bg.position + Vector2(14.0, 8.0)
	# 横幅
	_banner_t -= dt
	var ba := clampf(_banner_t / 0.6, 0.0, 1.0) * clampf((3.2 - _banner_t) / 0.3, 0.0, 1.0)
	_banner.modulate.a = ba
	_banner_sub.modulate.a = ba
	_banner.size = Vector2(vs.x, 70)
	_banner.position = Vector2(0, vs.y * 0.16)
	_banner_sub.size = Vector2(vs.x, 30)
	_banner_sub.position = Vector2(0, vs.y * 0.16 + 72)
	# 拾取提示
	_toasts.size = Vector2(620, 180)
	if touch:
		# 触屏：右边是按钮和拾取卡片，提示放到左边玩家牌下面（摇杆在更下面）
		var ty := 168.0
		if is_instance_valid(_plate):
			ty = _plate.position.y + _plate.size.y * _plate.scale.y + 20.0
		_toasts.position = Vector2(26.0, ty)
	else:
		_toasts.position = Vector2(vs.x - 640, vs.y * 0.3)
	# Boss 血条
	var bon := boss != null and is_instance_valid(boss)
	_boss_name.visible = bon
	_boss_bg.visible = bon
	if bon:
		# 夹在左上角玩家牌和右上角纸条之间：尽量居中，空当不够 560 就缩短；实在太窄（竖一点的屏）就放到纸条下面
		var gl := 16.0
		if is_instance_valid(_plate) and _plate.is_visible_in_tree():
			gl = _plate.position.x + _plate.size.x * _plate.scale.x + 16.0
		var gr := _info_bg.position.x - 16.0
		var bw := clampf(gr - gl, 320.0, 560.0)
		var by := 70.0
		var bcx := vs.x * 0.5
		if gr - gl >= 320.0:
			bcx = clampf(bcx, gl + bw * 0.5, gr - bw * 0.5)
		else:
			by = _info_bg.position.y + _info_bg.size.y + 10.0
		_boss_name.text = "%s  Lv.%d" % [str(boss.get("display_name")), int(boss.get("lv"))]
		# 血条跟在名字那行字下面（网页 / 手机上的字体行高比桌面的行楷大，写死 36 会压到字）
		var nh := _boss_name.get_minimum_size().y
		_boss_name.size = Vector2(vs.x, nh)
		_boss_name.position = Vector2(bcx - vs.x * 0.5, by)
		_boss_bg.size.x = bw
		_boss_bg.position = Vector2(roundf(bcx - bw * 0.5), by + nh + 2.0)
		_boss_bar.size.x = bw * clampf(float(boss.hp_ratio()), 0.0, 1.0)
	# 读条：撤离优先，其次搜点，再其次开箱
	var k: float = mgr.extract_k
	var lab := ""
	var bar_col := UiStyle.QING
	if k > 0.0:
		match str(mgr.extract_kind):
			"paid":
				lab = "献祭 %d 灵石启阵…别挨打" % int(mgr.paid_cost())
				bar_col = Color(0.72, 0.52, 0.12)
			"rune":
				lab = "破界符阵读条…位置已暴露"
				bar_col = Color(0.72, 0.52, 0.12)
			"rift":
				lab = "穿过空间裂隙…"
				bar_col = UiStyle.INDIGO
			"boss":
				lab = "镇守阵启动中…别挨打"
			_:
				lab = "传送阵启动中…别挨打"
	elif float(mgr.search_k) > 0.0:
		k = mgr.search_k
		lab = str(mgr.search.verb())
		bar_col = Color(0.30, 0.50, 0.24)
	elif chest_k > 0.0:
		k = chest_k
		lab = "开启中…"
	_prog_bg.visible = k > 0.0
	_prog_lab.visible = k > 0.0
	if k > 0.0:
		_prog_bg.position = Vector2(vs.x * 0.5 - 150, vs.y * 0.62)
		_prog.size.x = 300.0 * clampf(k, 0.0, 1.0)
		_prog.color = bar_col
		_prog_lab.text = lab
		_prog_lab.size = Vector2(vs.x, 30)
		_prog_lab.position = Vector2(0, vs.y * 0.62 - 36)
	# 拾取卡片：附近有掉落物才出现，屏幕右侧偏里（触屏：右下角那簇战斗按钮的左边，不压按钮）
	var loot_on: bool = not (mgr.near_loot as Array).is_empty() and not _panel.visible and bool(mgr.running)
	_loot_wrap.visible = loot_on
	if loot_on:
		var parts: Array = []
		for pk: Variant in mgr.near_loot:
			if is_instance_valid(pk):
				parts.append("%d:%d:%s" % [pk.get_instance_id(), (pk.items as Array).size(), bool(mgr._shared(pk))])
		var lsig := ",".join(parts)
		if lsig != _loot_sig:
			_loot_sig = lsig
			_rebuild_loot()
		_loot_wrap.reset_size()
		if touch:
			_loot_wrap.position = Vector2(roundf(vs.x - LOOT_RIGHT_TOUCH - _loot_wrap.size.x), LOOT_TOP_TOUCH)
		else:
			_loot_wrap.position = Vector2(roundf(vs.x - LOOT_RIGHT - _loot_wrap.size.x), roundf(vs.y * 0.34))
			# 拾取提示挪到卡片上面，别叠在一起
			_toasts.position.y = minf(vs.y * 0.3, _loot_wrap.position.y - _toasts.size.y - 8.0)
	else:
		_loot_sig = ""
	# 背包面板
	var badge := "%d/%d" % [int(mgr.bag_used()), Data.BAG_SIZE]
	if badge != str(_bag_btn.get_meta("badge", "")):
		_bag_btn.set_meta("badge", badge)
		_bag_btn.set_meta("badge_hot", int(mgr.bag_used()) >= Data.BAG_SIZE)     # 满了：纸签上的字变朱砂
		_bag_btn.queue_redraw()
	if _panel.visible:
		var sig := _signature()
		if sig != _sig:
			_sig = sig
			_rebuild_grid()
		_panel_title.text = "%d / %d 格　共 %d 灵石" % [int(mgr.bag_used()), Data.BAG_SIZE, mgr.bag_value()]
		_place_panel(vs)
	_dim.visible = _panel.visible
