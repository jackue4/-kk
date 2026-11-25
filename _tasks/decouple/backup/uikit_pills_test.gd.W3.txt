extends SceneTree
## 丹药图标小样页：把游戏里所有的丹药（回春丹、五个品阶的修为丹、七种破境丹）按背包格子 / 拾取卡片 / 坊市格子各摆一遍截一张图，
## 顺带检查每种丹药是不是都取到了自己那张图（没取到 = 退回通用图标，会打印出来）。
## 用法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/pills --resolution 1600x900 -s res://_tasks/ui_kit/pills_test.gd -- <输出 jpg 的绝对路径>

const UiStyle := preload("res://scripts/ui_style.gd")
const Items := preload("res://scripts/raid_items.gd")
const ItemView := preload("res://scripts/item_view.gd")

var _n := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	UiStyle.force_bundled = args.has("--web-fonts")
	_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else ProjectSettings.globalize_path("res://_shots/preview/ui_pills.jpg")
	var all: Array = [Items.heal_pill()]
	for t in Items.PILLS.size():
		all.append(Items.pill(t))
	for r in range(1, Items.KEYS.size()):
		all.append(Items.key(r))
	var seen := {}
	for it: Dictionary in all:
		var nm := Items.icon_name(it)
		var ok := ResourceLoader.exists(UiStyle.UI_DIR + "icon_" + nm + ".png") or FileAccess.file_exists(ProjectSettings.globalize_path(UiStyle.UI_DIR + "icon_" + nm + ".png"))
		print("[pills] %s → icon_%s %s%s" % [it["name"], nm, "有图" if ok else "【没图，退回通用图标】", "　【和别的丹药重了】" if seen.has(nm) else ""])
		seen[nm] = true
	print("[pills] 共 %d 种丹药，%d 张不同的图" % [all.size(), seen.size()])

	var th := Theme.new()
	th.default_font = UiStyle.kai()
	th.default_font_size = 18
	var base := Control.new()
	base.theme = th
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.5, 0.42)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.scroll(22.0, false))
	panel.position = Vector2(40, 30)
	base.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(_ink("背包格子（丹药 / 破境丹）", 22))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for it: Dictionary in all:
		grid.add_child(ItemView.slot(it, Vector2(222, 86)))
	v.add_child(_ink("拾取卡片（触屏大小）", 22))
	var row := HFlowContainer.new()
	row.custom_minimum_size = Vector2(920, 0)
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	v.add_child(row)
	for it: Dictionary in all:
		row.add_child(ItemView.card(it, Vector2(168, 76)))
	# 右边：只看图，放大
	var big := GridContainer.new()
	big.columns = 4
	big.position = Vector2(1030, 40)
	big.add_theme_constant_override("h_separation", 6)
	big.add_theme_constant_override("v_separation", 6)
	base.add_child(big)
	for it: Dictionary in all:
		var cell := Panel.new()
		cell.add_theme_stylebox_override("panel", UiStyle.slot(false))
		cell.custom_minimum_size = Vector2(132, 150)
		big.add_child(cell)
		var ic := TextureRect.new()
		ic.texture = UiStyle.icon(Items.icon_name(it))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(10, 6)
		ic.size = Vector2(112, 112)
		cell.add_child(ic)
		var l := _ink(str(it["name"]), 18)
		l.position = Vector2(0, 120)
		l.size = Vector2(132, 26)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(l)


func _ink(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	return l


func _process(_dt: float) -> bool:
	_n += 1
	if _n == 12:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(_out, 0.92)
		print("saved ", _out, " ", img.get_size())
		return true
	return false
