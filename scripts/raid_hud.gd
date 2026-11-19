extends CanvasLayer
## 搜打撤的界面：左侧一栏（所在区域 / 修为进度 / 背包格数与价值 / 最近传送阵的方位）、中上方区域与 Boss 横幅、
## 右侧拾取提示、Boss 血条、开箱 / 撤离读条、背包面板、结算面板。
## 背包面板是大格子按钮（手机上好点）：点丹药 = 服用，点其它 = 丢在脚边。B 键或左侧「背包」按钮开关。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")

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
var _boss_bg: ColorRect
var _prog_bg: ColorRect
var _prog: ColorRect
var _prog_lab: Label
var _panel: PanelContainer
var _grid: GridContainer
var _panel_title: Label
var _result: PanelContainer
var _bag_n := -1


func _mk(text: String, size: int, col := Color(0.97, 0.97, 0.98)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.11, 0.9))
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

	_info = _mk("", 22)
	_info.position = Vector2(22, 18)
	_root.add_child(_info)
	var eb := _rect(_root, Color(0.05, 0.06, 0.08, 0.6), Vector2(260, 8))
	eb.position = _info.position + Vector2(0, 70)
	_exp_bar = _rect(eb, Color(0.5, 0.9, 1.0), Vector2(260, 8))
	_bag_btn = Button.new()
	_bag_btn.text = "背包"
	_bag_btn.custom_minimum_size = Vector2(150, 54)
	_bag_btn.position = _info.position + Vector2(0, 200)
	_bag_btn.visible = not touch   # 触屏用右上角的「包」按钮
	_bag_btn.focus_mode = Control.FOCUS_NONE
	_bag_btn.add_theme_font_size_override("font_size", 22)
	_bag_btn.pressed.connect(toggle_bag)
	_root.add_child(_bag_btn)

	_banner = _mk("", 52)
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

	_boss_name = _mk("", 26, Color(1.0, 0.5, 0.4))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_boss_name)
	_boss_bg = _rect(_root, Color(0.05, 0.06, 0.08, 0.65), Vector2(560, 12))
	_boss_bar = _rect(_boss_bg, Color(0.9, 0.22, 0.18), Vector2(560, 12))

	_prog_bg = _rect(_root, Color(0.05, 0.06, 0.08, 0.65), Vector2(300, 12))
	_prog = _rect(_prog_bg, Color(0.4, 1.0, 1.0), Vector2(300, 12))
	_prog_lab = _mk("", 22)
	_prog_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prog_lab)

	_build_panel()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	sb.border_color = Color(0.5, 0.8, 0.9, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	_panel_title = _mk("", 24)
	v.add_child(_panel_title)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(_grid)
	var hint := _mk("点丹药 = 服用（涨修为、回气血）　点装备 / 材料 = 丢在脚边　带到亮着的传送阵才算数", 17, Color(1.0, 0.9, 0.7))
	v.add_child(hint)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(160, 52)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(toggle_bag)
	v.add_child(close)


func bag_open() -> bool:
	return _panel.visible


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("bag"):
		toggle_bag()


func toggle_bag() -> void:
	_panel.visible = not _panel.visible
	_bag_n = -1
	if not touch:
		if _panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif mgr.cam.capture_mouse:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var bag: Array = mgr.bag
	for i in Data.BAG_SIZE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 96)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		if i < bag.size():
			var it: Dictionary = bag[i]
			var col: Color = Data.TIER_COLORS[int(it["tier"])]
			var extra := "修为 +%d" % int(it["exp"]) if it["kind"] == "pill" else "%d 灵石" % int(it["value"])
			b.text = "%s\n%s · %s" % [it["name"], Data.TIER_NAMES[int(it["tier"])], extra]
			b.add_theme_color_override("font_color", col)
			b.add_theme_color_override("font_hover_color", col.lightened(0.3))
			b.pressed.connect(mgr.use_item.bind(i))
		else:
			b.text = "—"
			b.disabled = true
		_grid.add_child(b)


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


func show_result(success: bool, items: Array, value: int, kills: int, stash: int) -> void:
	_panel.visible = false
	_result = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	sb.border_color = Color(0.4, 1.0, 1.0, 0.8) if success else Color(1.0, 0.35, 0.3, 0.8)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	_result.add_theme_stylebox_override("panel", sb)
	_root.add_child(_result)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_result.add_child(v)
	v.add_child(_mk("撤 离 成 功" if success else "陨 落", 56, Color(0.5, 1.0, 1.0) if success else Color(1.0, 0.35, 0.3)))
	if success:
		v.add_child(_mk("带出 %d 件，共 %d 灵石　击杀 %d　仓库累计 %d 灵石" % [items.size(), value, kills, stash], 22))
		for i in mini(items.size(), 8):
			var it: Dictionary = items[i]
			v.add_child(_mk("· %s　%s　%d 灵石" % [it["name"], Data.TIER_NAMES[int(it["tier"])], int(it["value"])], 19,
					Data.TIER_COLORS[int(it["tier"])]))
	else:
		v.add_child(_mk("背包里的 %d 件（%d 灵石）尽数遗失　击杀 %d" % [items.size(), value, kills], 22))
	v.add_child(_mk("即将返回试剑大厅…", 18, Color(1, 1, 1, 0.7)))
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
	var sec := int(mgr.run_t)
	var ex: Dictionary = mgr.nearest_extract()
	var ex_txt := "传送阵：全部探明皆毁？"
	if not ex.is_empty():
		var to: Vector3 = (ex["pos"] as Vector3) - p.global_position
		var rel := wrapf(atan2(-to.x, -to.z) - mgr.cam.yaw, -PI, PI)
		var arrow: String = ["↑", "↖", "←", "↙", "↓", "↘", "→", "↗"][int(round(rel / (PI / 4.0))) & 7]
		var st := "可撤离" if bool(ex["known"]) and bool(ex["active"]) else "未探明"
		ex_txt = "传送阵 %s %dm（%s）" % [arrow, int(float(ex["dist"])), st]
	_info.text = "%s　怪物 Lv.%d\n%s期　修为 Lv.%d\n\n%02d:%02d　%s\n背包 %d/%d　%d 灵石\n%s" % [r["name"], int(mgr.enemy_level(int(mgr.region))),
			p.realm["name"], int(mgr.lv), sec / 60, sec % 60, Data.DIFF_NAMES[tier], mgr.bag.size(), Data.BAG_SIZE, mgr.bag_value(), ex_txt]
	_info.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5) if need > int(mgr.lv) + 2 else Color(0.97, 0.97, 0.98))
	_exp_bar.size.x = 260.0 * float(mgr.exp_ratio())
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
	_toasts.size = Vector2(520, 180)
	_toasts.position = Vector2(vs.x - 540 - (0.0 if not touch else 0.0), vs.y * 0.3)
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
	# 读条：撤离优先，其次开箱
	var k: float = mgr.extract_k
	var lab := "传送阵启动中…别挨打"
	if k <= 0.0:
		k = chest_k
		lab = "开启中…"
	_prog_bg.visible = k > 0.0
	_prog_lab.visible = k > 0.0
	if k > 0.0:
		_prog_bg.position = Vector2(vs.x * 0.5 - 150, vs.y * 0.62)
		_prog.size.x = 300.0 * clampf(k, 0.0, 1.0)
		_prog_lab.text = lab
		_prog_lab.size = Vector2(vs.x, 30)
		_prog_lab.position = Vector2(0, vs.y * 0.62 - 36)
	# 背包面板
	_bag_btn.text = "背包 %d/%d" % [mgr.bag.size(), Data.BAG_SIZE]
	if _panel.visible:
		if _bag_n != mgr.bag.size():
			_bag_n = mgr.bag.size()
			_rebuild_grid()
		_panel_title.text = "储物袋　%d/%d　共 %d 灵石" % [mgr.bag.size(), Data.BAG_SIZE, mgr.bag_value()]
		_panel.position = (vs - _panel.size) * 0.5
