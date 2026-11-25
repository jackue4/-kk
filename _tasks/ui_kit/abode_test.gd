extends SceneTree
## 洞府（仓库）界面的小样页：不进游戏，直接把 abode_ui.gd 建出来，塞一仓库假东西，截四张图（储物 / 储物选中一叠 / 坊市 / 丹房）。
## 一定要带 --abode-test：有这个参数 raid_profile.gd 就走自检专用存档，不碰玩家的档（塞的东西只在内存里，不存盘）。
## 用法（要真窗口，走 run_hidden；分辨率就是手机上的界面大小，约 1701×900，最窄 1600×900）：
##   python _tasks/trailer/run_hidden.py . _shots/abode --resolution 1701x900 -s res://_tasks/ui_kit/abode_test.gd -- <输出目录> [前缀] --abode-test [--web-fonts]

const UiStyle := preload("res://scripts/ui_style.gd")
const Abode := preload("res://scripts/abode_ui.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")

var _n := 0
var _dir := ""
var _pre := "abode"
var _ab: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not Profile.test_mode():
		push_error("要带 --abode-test（否则会读写玩家自己的存档）")
		quit(1)
		return
	UiStyle.force_bundled = args.has("--web-fonts")
	var plain: Array = []
	for a: String in args:
		if not a.begins_with("--"):
			plain.append(a)
	_dir = plain[0] if plain.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview")
	if plain.size() > 1:
		_pre = plain[1]
	var bg := ColorRect.new()
	bg.color = Color(0.5, 0.66, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# 一仓库假东西：和玩家真实的仓库差不多的构成（一堆灵材、几样法宝、几种丹）
	var d := Profile.data()
	var stash: Array = []
	for i in 12:
		stash.append(Items.mat(0))
	for i in 5:
		stash.append(Items.herb(0))
	for i in 3:
		stash.append(Items.gear(0, 0))
	for i in 3:
		stash.append(Items.gear(0, 1))
	stash.append_array([Items.gear(0, 2), Items.gear(0, 3), Items.gear(0, 3), Items.gear(1, 0), Items.gear(1, 2), Items.gear(2, 1)])
	for i in 4:
		stash.append(Items.pill(0, 1))
	stash.append_array([Items.pill(1, 1), Items.pill(1, 1), Items.pill(3, 1), Items.heal_pill(), Items.heal_pill(), Items.heal_pill()])
	stash.append_array([Items.key(1), Items.key(4), Items.tool("reveal"), Items.tool("reveal"), Items.tool("rune"), Items.herb(1), Items.herb(2), Items.mat(1), Items.mat(1)])
	d["stash"] = stash
	d["gear"] = [Items.gear(1, 0), Items.gear(0, 1)]
	d["carry"] = [Items.pill(1, 1), Items.heal_pill()]
	d["ring"] = [Items.key(2)]
	d["ring_cap"] = 2
	d["lingshi"] = 1291
	_ab = Abode.new()
	_ab.font = UiStyle.kai()
	root.add_child(_ab)


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := _dir.path_join("%s_%s.jpg" % [_pre, name])
	img.save_jpg(path, 0.9)
	print("saved ", path, " ", img.get_size())


func _process(_dt: float) -> bool:
	_n += 1
	if _n == 10:
		_save("1_store")
		print("[abode] 画面 %s　面板 %s 缩放 %s　仓库 %d 件叠成 %d 格" % [root.get_visible_rect().size, Rect2(_ab._panel.position, _ab._panel.size * _ab._panel.scale),
				_ab._panel.scale, Profile.stash().size(), Abode._stacks(Profile.stash()).size()])
		_ab._select("stash", 0)
	elif _n == 20:
		_save("2_store_sel")
		_ab._set_tab(1)
		_ab._select("shop", 2)
	elif _n == 30:
		_save("3_shop")
		_ab._set_tab(2)
	elif _n == 40:
		_save("4_alchemy")
		return true
	return false
