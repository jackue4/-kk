extends SceneTree
## 择境 / 入境两页的小样（不进游戏）：python _tasks/trailer/run_hidden.py . _shots/uikit -s res://_tasks/ui_kit/select_test.gd -- <输出目录的绝对路径> [--select-test]
## 2026-11-25 主干解耦：带 --select-test（存档走自检档）时多走一段：每张图的入境页都有英雄那一排；
## 炼气期 open_level("desert") 不开（元婴门槛），存档境界设到元婴再开 → 拍 select_modes_desert.jpg

const LevelSelect := preload("res://scripts/level_select.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const Profile := preload("res://scripts/raid_profile.gd")

var _n := 0
var _dir := ""
var _ui: CanvasLayer


class FakeNet:
	extends Node
	func start_discovery() -> void:
		pass
	func stop_discovery() -> void:
		pass


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	UiStyle.force_bundled = args.has("--web-fonts")     # 用随包字体预览网页 / 手机上的样子
	_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview")
	var bg := ColorRect.new()      # 假装后面是大厅
	bg.color = Color(0.42, 0.44, 0.47)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_ui = LevelSelect.new()
	_ui.font = UiStyle.kai()
	root.add_child(_ui)


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(_dir.path_join(name), 0.9)
	print("saved ", name)


func _process(_dt: float) -> bool:
	_n += 1
	if _n == 5:
		_ui.open()
	elif _n == 14:
		_save("select_cards.jpg")
		var net := FakeNet.new()
		root.add_child(net)
		_ui.net = net
		_ui.pick(0)
	elif _n == 24:
		_save("select_modes.jpg")
		if not OS.get_cmdline_user_args().has("--select-test"):
			return true
		print("[select] 木兰草原入境页英雄按钮 %d 个（应为 >= 2）" % (_ui.get("_hero_btns") as Array).size())
		_ui.close()
	elif _n == 28:
		Profile.data()["realm"] = 0
		_ui.open_level("desert")
		print("[select] 炼气期开沙海古墟入境页：开了=%s（应为 false）；门槛提示「%s」" % [_ui.is_open(), _ui.realm_lock(1)])
	elif _n == 32:
		Profile.data()["realm"] = 3
		_ui.open_level("desert")
	elif _n == 44:
		print("[select] 元婴期开沙海古墟入境页：开了=%s（应为 true）英雄按钮 %d 个、这次带什么「%s」" % [_ui.is_open(), (_ui.get("_hero_btns") as Array).size(),
				_ui.call("_summary")])
		_save("select_modes_desert.jpg")
		return true
	return false
