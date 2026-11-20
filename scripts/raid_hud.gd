extends CanvasLayer
## 搜打撤的界面：左侧一栏（所在区域 / 修为进度 / 禁地倒计时 / 背包格数与价值 / 储物戒）、中上方区域与 Boss 横幅、
## 右侧拾取提示、Boss 血条、撤离 / 搜点 / 开箱读条、储物袋面板、结算面板。
## 储物袋面板（2026-11-20 改）：上面是背包格子（灵材占 2 格），下面一排是佩戴的法宝（3 件）和储物戒；
##   点一件 → 底下一行说明 + 能做的事（服用 / 使用 / 佩戴 / 收进储物戒 / 丢弃；法宝取下；储物戒取回），不再「一点就丢」。
##   右上角「整理」按种类和每格价值排好。B 键或左侧「背包」按钮（触屏是右上角「包」）开关。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const ItemView := preload("res://scripts/item_view.gd")
const RealmBanner := preload("res://scripts/realm_banner.gd")
const Minimap := preload("res://scripts/minimap.gd")

const ACT_NAMES := {"use": "服用", "equip": "佩戴", "ring": "收进储物戒", "drop": "丢弃", "unequip": "取下", "unring": "取回背包"}

var font: Font
var mgr: Node3D
var touch := false
var boss: Node3D = null
var chest_k := 0.0

var _root: Control
var _info: Label
var _exp_bar: ColorRect
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
var _grid: GridContainer
var _gear_row: HBoxContainer
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
var _exp_bg: Panel
var minimap: Control


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

	# 左上角：小地图，右边挨着信息牌（一张小纸条，墨字）
	minimap = Minimap.new()
	minimap.mgr = mgr
	minimap.font = font
	minimap.position = Vector2(14, 12)
	_root.add_child(minimap)
	_info_bg = Panel.new()
	_info_bg.add_theme_stylebox_override("panel", UiStyle.plaque())
	_info_bg.position = Vector2(206, 12)
	_info_bg.size = Vector2(292, 158)
	_info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info_bg)
	_info = _mk_ink("", 21)
	_info.position = Vector2(222, 20)
	_root.add_child(_info)
	var eb := Panel.new()
	eb.add_theme_stylebox_override("panel", UiStyle.bar_frame())
	eb.size = Vector2(256, 7)
	eb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(eb)
	eb.position = _info.position + Vector2(2, 70)
	_exp_bg = eb
	_exp_bar = _rect(eb, UiStyle.QING, Vector2(256, 7))
	_bag_btn = Button.new()
	_bag_btn.text = "背包"
	_bag_btn.icon = UiStyle.icon("pouch")
	_bag_btn.expand_icon = true
	_bag_btn.add_theme_constant_override("icon_max_width", 34)
	_bag_btn.custom_minimum_size = Vector2(176, 54)
	_bag_btn.position = Vector2(206, 182)
	_bag_btn.visible = not touch   # 触屏用右上角的「包」按钮
	_bag_btn.focus_mode = Control.FOCUS_NONE
	_bag_btn.add_theme_font_size_override("font_size", 22)
	_bag_btn.pressed.connect(toggle_bag)
	UiStyle.style_button(_bag_btn)
	_root.add_child(_bag_btn)

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
	_toasts.alignment = BoxContainer.ALIGNMENT_END
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


## 储物袋面板：朱印 + 题字 + 格数 / 价值 + 整理，一笔枯墨，背包格子；下面法宝栏 + 储物戒；再下面是选中物品的说明和按钮
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UiStyle.scroll(20.0))
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(UiStyle.seal("储", 46.0))
	var t := _mk_ink("储物袋", 38)
	t.add_theme_font_override("font", UiStyle.brush())
	head.add_child(t)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_panel_title = _mk_ink("", 21, UiStyle.TEXT_SOFT)
	_panel_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_panel_title)
	var sort := _small_btn("整理", 110.0)
	sort.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sort.pressed.connect(func() -> void:
		mgr.sort_bag()
		_sel = {})
	head.add_child(sort)
	v.add_child(UiStyle.rule(380.0, 8.0, Color(UiStyle.LINE, 0.82)))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(_grid)
	# 法宝栏、储物戒各一排
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var gl := _mk_ink("佩戴法宝", 22, UiStyle.TEXT_INK)
	gl.add_theme_font_override("font", UiStyle.brush())
	gl.custom_minimum_size = Vector2(150, 0)
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gl)
	_gear_row = HBoxContainer.new()
	_gear_row.add_theme_constant_override("separation", 8)
	row.add_child(_gear_row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)
	_ring_lab = _mk_ink("储物戒", 22, UiStyle.TEXT_INK)
	_ring_lab.add_theme_font_override("font", UiStyle.brush())
	_ring_lab.custom_minimum_size = Vector2(150, 0)
	_ring_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(_ring_lab)
	_ring_row = HBoxContainer.new()
	_ring_row.add_theme_constant_override("separation", 8)
	row2.add_child(_ring_row)
	v.add_child(UiStyle.rule(380.0, 6.0, Color(UiStyle.LINE, 0.6)))
	# 说明 + 按钮
	_detail = _mk_ink("点一件看看能做什么", 18, UiStyle.TEXT_SOFT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(900, 0)
	v.add_child(_detail)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_acts = HBoxContainer.new()
	_acts.add_theme_constant_override("separation", 10)
	_acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_acts)
	var close := _small_btn("关闭", 150.0)
	close.pressed.connect(toggle_bag)
	foot.add_child(close)


func bag_open() -> bool:
	return _panel.visible


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("bag"):
		toggle_bag()


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
	for c in _grid.get_children():
		c.queue_free()
	for c in _gear_row.get_children():
		c.queue_free()
	for c in _ring_row.get_children():
		c.queue_free()
	for c in _acts.get_children():
		c.queue_free()
	var bag: Array = mgr.bag
	for i in bag.size():
		var b := ItemView.slot(bag[i], Vector2(222, 86), _is_sel("bag", i))
		b.pressed.connect(_select.bind("bag", i))
		_grid.add_child(b)
	var free: int = Data.BAG_SIZE - int(mgr.bag_used())
	for i in maxi(free, 0):
		_grid.add_child(ItemView.slot({}, Vector2(222, 86)))
	var gear: Array = mgr.gear
	for i in Profile.GEAR_SLOTS:
		var it: Dictionary = gear[i] if i < gear.size() else {}
		var b := ItemView.slot(it, Vector2(222, 70), _is_sel("gear", i), -1, "空")
		if not it.is_empty():
			b.pressed.connect(_select.bind("gear", i))
		_gear_row.add_child(b)
	var ring: Array = mgr.ring
	var cap := Profile.ring_cap()
	_ring_lab.text = "储物戒 %d/%d" % [Items.slots_used(ring), cap]
	for i in ring.size():
		var b := ItemView.slot(ring[i], Vector2(222, 70), _is_sel("ring", i))
		b.pressed.connect(_select.bind("ring", i))
		_ring_row.add_child(b)
	for i in maxi(cap - Items.slots_used(ring), 0):
		_ring_row.add_child(ItemView.slot({}, Vector2(110, 70), false, -1, "空"))
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
		var b := _small_btn(label, 168.0, a == "use" or a == "equip")
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
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	if success:
		v.add_child(_mk_ink("带出 %d 件，共 %d 灵石，已入洞府仓库　击杀 %d" % [items.size(), value, kills], 22))
		for i in mini(items.size(), 6):
			var it: Dictionary = items[i]
			v.add_child(_mk_ink("· %s　%s　%d 灵石" % [it["name"], Data.TIER_NAMES[int(it["tier"])], int(it["value"])], 20,
					UiStyle.on_paper(Data.TIER_COLORS[int(it["tier"])])))
		if items.size() > 6:
			v.add_child(_mk_ink("…… 另有 %d 件" % (items.size() - 6), 18, UiStyle.TEXT_SOFT))
		if int(res.get("sold", 0)) > 0:
			v.add_child(_mk_ink("仓库满了：%d 件折成 %d 灵石" % [int(res["sold"]), int(res["sold_value"])], 19, UiStyle.CINNABAR))
		if not lost.is_empty():
			v.add_child(_mk_ink("随身法宝 %d 件安然带回" % lost.size(), 19, UiStyle.TEXT_SOFT))
	else:
		v.add_child(_mk_ink("背包里的 %d 件（%d 灵石）尽数遗失　击杀 %d" % [items.size(), value, kills], 22))
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
		v.add_child(_mk_ink("境界不跌；回洞府重整行囊再来", 18, UiStyle.TEXT_SOFT))
	v.add_child(_mk_ink("洞府灵石 %d　· 即将返回试剑大厅…" % stash, 18, UiStyle.TEXT_SOFT))
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	_result.position = (vs - _result.size) * 0.5


func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var p: Player = mgr.player
	# 左侧信息栏
	var r: Dictionary = Data.REGIONS[int(mgr.region)]
	var need: int = r["lv"]
	var c: float = mgr.coeff()
	var tier := Data.diff_tier(c)
	var left := int(ceilf(float(mgr.time_left())))
	# 传送阵的方向和距离看小地图（贴边的青色圈 + 地图下面那行字），信息牌里不再重复
	var net_txt := ""
	if mgr.net_on():
		net_txt = "\n房间 %d 人　本队 %d / %d" % [mgr.net.players.size(), mgr.net.team_count(), int(mgr.net.team_size)]
	_info.text = "%s　怪物 Lv.%d\n%s期　修为 Lv.%d\n\n禁地 %02d:%02d　%s\n背包 %d/%d格　%d 灵石　戒 %d/%d%s" % [
			"无涯海" if mgr.at_sea else r["name"], int(mgr.enemy_level(int(mgr.region))),
			p.realm["name"], int(mgr.lv), left / 60, left % 60, Data.DIFF_NAMES[tier], int(mgr.bag_used()), Data.BAG_SIZE, mgr.bag_value(),
			Items.slots_used(mgr.ring), Profile.ring_cap(), net_txt]
	_info.add_theme_color_override("font_color", UiStyle.CINNABAR if need > int(mgr.lv) + 2 or left < 180 else UiStyle.TEXT_INK)
	_exp_bar.size.x = 256.0 * float(mgr.exp_ratio())
	_exp_bar.color = UiStyle.CINNABAR if int(mgr._need_key) >= 0 else UiStyle.QING     # 卡在瓶颈、缺破境丹：修为条变朱砂色
	# 纸条的高度跟着文字走（网页 / 手机上的字体行高和桌面的楷体不一样，写死会掉出去）；修为条放在空着的第三行正中
	var lh := float(_info.get_line_height() + _info.get_theme_constant("line_spacing"))
	_exp_bg.position.y = _info.position.y + lh * 2.0 + (lh - _exp_bg.size.y) * 0.5
	_info_bg.size.y = _info.get_minimum_size().y + 18.0
	_info_bg.size.x = maxf(292.0, _info.get_minimum_size().x + 32.0)
	_bag_btn.position.y = _info_bg.position.y + _info_bg.size.y + 12.0
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
	_toasts.position = Vector2(vs.x - 640, vs.y * 0.3)
	# Boss 血条
	var bon := boss != null and is_instance_valid(boss)
	_boss_name.visible = bon
	_boss_bg.visible = bon
	if bon:
		_boss_name.text = "%s  Lv.%d" % [str(boss.get("display_name")), int(boss.get("lv"))]
		_boss_name.size = Vector2(vs.x, 30)
		_boss_name.position = Vector2(0, 70)
		_boss_bg.position = Vector2(vs.x * 0.5 - 280, 106)
		_boss_bar.size.x = 560.0 * clampf(float(boss.hp_ratio()), 0.0, 1.0)
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
	# 背包面板
	_bag_btn.text = "背包 %d/%d" % [int(mgr.bag_used()), Data.BAG_SIZE]
	_bag_btn.visible = not touch and not _panel.visible     # 面板开着时收起来（面板会压到它；关闭用面板上的按钮 / B 键）
	if _panel.visible:
		var sig := _signature()
		if sig != _sig:
			_sig = sig
			_rebuild_grid()
		_panel_title.text = "%d / %d 格　共 %d 灵石" % [int(mgr.bag_used()), Data.BAG_SIZE, mgr.bag_value()]
		_panel.position = (vs - _panel.size) * 0.5
