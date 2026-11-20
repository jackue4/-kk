extends SceneTree
## 大世界界面的手机布局小样页：不进游戏，用假数据（mock_raid.gd）把 raid_hud.gd 真的建出来，
## 再把玩家牌、触屏按钮（按 touch_controls.gd 的 BUTTONS 画圈，空战才有的也画上）、空战目标面板的位置摆上，
## 截三张图看有没有互相压着：① 拾取卡片 + Boss 血条 ② 背包打开 ③ 背包里选中一件。
## 用法（要真窗口，走 run_hidden；分辨率就是手机上的界面大小，2868×1320 的手机去掉两边黑边约等于 1701×900）：
##   python _tasks/trailer/run_hidden.py . _shots/rhud --resolution 1701x900 -s res://_tasks/ui_kit/raid_hud_test.gd -- <输出目录> [前缀] [--desktop] [--web-fonts]

const UiStyle := preload("res://scripts/ui_style.gd")
const Plate := preload("res://scripts/player_plate.gd")
const RaidHud := preload("res://scripts/raid_hud.gd")
const Mock := preload("res://_tasks/ui_kit/mock_raid.gd")
const Items := preload("res://scripts/raid_items.gd")
const TC := preload("res://scripts/touch_controls.gd")


class Boss:
	extends Node3D
	var display_name := "枫谷妖王"
	var lv := 6
	func hp_ratio() -> float:
		return 0.62


var _n := 0
var _dir := ""
var _pre := "rhud"
var _touch := true
var _hud: CanvasLayer
var _mgr: Node3D
var _plate: Control
var _pad: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	UiStyle.force_bundled = args.has("--web-fonts")
	_touch = not args.has("--desktop")
	var plain: Array = []
	for a: String in args:
		if not a.begins_with("--"):
			plain.append(a)
	_dir = plain[0] if plain.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview")
	if plain.size() > 1:
		_pre = plain[1]
	var font := UiStyle.kai()
	# 背景：天 + 草地
	var bg := CanvasLayer.new()
	bg.layer = -1
	root.add_child(bg)
	var sky := ColorRect.new()
	sky.color = Color(0.62, 0.74, 0.86)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(sky)
	var grass := ColorRect.new()
	grass.color = Color(0.62, 0.78, 0.24)
	grass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grass.anchor_top = 0.42
	bg.add_child(grass)
	# 玩家牌（游戏里是 hud.gd 建的，层 10）
	var l10 := CanvasLayer.new()
	l10.layer = 10
	root.add_child(l10)
	_plate = Plate.new()
	_plate.font = font
	_plate.position = Vector2(14, 12)
	if _touch:
		_plate.scale = Vector2(1.15, 1.15)
	l10.add_child(_plate)
	# 空战目标面板的位置（hud.gd 的 _tgt，大世界里）
	var tgt := Control.new()
	tgt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tgt.draw.connect(func() -> void:
		var vs := tgt.size
		var r := Rect2(vs.x - 310.0 - 360.0 - 38.0, 150.0, 398.0, 112.0)
		tgt.draw_rect(r, Color(0.9, 0.3, 0.2, 0.22))
		tgt.draw_rect(r, Color(0.6, 0.1, 0.1, 0.8), false, 1.5)
		tgt.draw_string(font, r.position + Vector2(44, 26), "空战目标面板（打其他修士时）", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.3, 0.05, 0.05)))
	l10.add_child(tgt)
	# 假管理器 + 真界面
	_mgr = Mock.new()
	root.add_child(_mgr)
	_mgr.bag = [Items.gear(1, 1), Items.pill(1, 1), Items.herb(0), Items.herb(0), Items.tool("reveal"), Items.gear(0, 1),
			Items.gear(2, 1), Items.mat(0), Items.mat(0), Items.pill(3, 1)]
	_mgr.gear = [Items.gear(1, 0)]
	_hud = RaidHud.new()
	_hud.font = font
	_hud.mgr = _mgr
	_hud.touch = _touch
	var boss := Boss.new()
	root.add_child(boss)
	_hud.boss = boss
	root.add_child(_hud)
	# 触屏按钮（游戏里是层 20，压在卡片上面；背包开着时不画）
	var l20 := CanvasLayer.new()
	l20.layer = 20
	root.add_child(l20)
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	_pad.visible = _touch
	l20.add_child(_pad)


func _draw_pad() -> void:
	var vs := _pad.size
	var bf := UiStyle.brush()
	var ring := UiStyle.tex("enso")
	var items: Array = [[Vector2(210.0, vs.y - 210.0), 110.0, ""]]
	for b: Dictionary in TC.BUTTONS:
		if str(b["id"]) == "rp" or str(b["id"]) == "rn":
			continue      # 境± 只在大厅
		var off: Vector2 = b["off"]
		items.append([Vector2(vs.x + off.x, off.y) if str(b["anchor"]) == "tr" else vs + off, float(b["r"]), str(b["text"])])
	for it: Array in items:
		var c: Vector2 = it[0]
		var r: float = it[1]
		_pad.draw_circle(c, r * 0.97, Color(UiStyle.PAPER, 0.86 if str(it[2]) != "" else 0.4), true, -1.0, true)
		if ring != null:
			var er := r * 1.19
			_pad.draw_texture_rect(ring, Rect2(c - Vector2(er, er), Vector2(er, er) * 2.0), false, Color(UiStyle.LINE, 0.9))
		var txt: String = it[2]
		if txt != "":
			var fs := int(r * 0.7)
			var ts := bf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			_pad.draw_string(bf, c + Vector2(-ts.x * 0.5, ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.TEXT_INK)


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := _dir.path_join("%s_%s.jpg" % [_pre, name])
	img.save_jpg(path, 0.9)
	print("saved ", path, " ", img.get_size())


func _process(_dt: float) -> bool:
	_n += 1
	if _n >= 2:
		_plate.set_values(3, 1.0, 407, 106.0, 106.0, 10, 0.4, 989)      # 2026-11-20 夜：灵力按单位传（元婴 106，显示 130）、战力按 combat_stats.power
	if _n == 2:
		_mgr.set_loot([Items.pill(3, 1), Items.mat(0), Items.pill(0, 1), Items.gear(2, 0), Items.key(4)])
		_hud.toast("拾得 中品凝魂丹", Color(0.86, 0.7, 1.0))
		_hud.toast("背包满了，先腾一格", Color(1.0, 0.6, 0.5))
	elif _n == 16:
		_save("1_loot")
		print("[rhud] 画面 %s　卡片列 %s　纸条 %s　Boss 条 %s" % [root.get_visible_rect().size, Rect2(_hud._loot_wrap.position, _hud._loot_wrap.size),
				Rect2(_hud._info_bg.position, _hud._info_bg.size), Rect2(_hud._boss_bg.position, _hud._boss_bg.size)])
		_hud.toggle_bag()
		_pad.visible = false
	elif _n == 30:
		_save("2_bag")
		print("[rhud] 面板 %s 缩放 %s" % [Rect2(_hud._panel.position, _hud._panel.size * _hud._panel.scale), _hud._panel.scale])
		_hud._select("bag", 0)
	elif _n == 44:
		_save("3_bag_sel")
		return true
	return false
