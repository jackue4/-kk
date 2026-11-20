extends SceneTree
## 玩家牌（scripts/player_plate.gd）+ 右上角圆按钮的小样页：不进游戏，摆几种境界 / 血量截一张图。
## 用法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/plate --resolution 1600x900 -s res://_tasks/ui_kit/plate_test.gd -- <输出 jpg 的绝对路径> [--web-fonts]

const UiStyle := preload("res://scripts/ui_style.gd")
const Plate := preload("res://scripts/player_plate.gd")

var _n := 0
var _out := ""
var _todo: Array = []      # [牌, 参数]：等牌进了场景树（_ready 跑过）再给数


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	UiStyle.force_bundled = args.has("--web-fonts")
	_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else ProjectSettings.globalize_path("res://_shots/preview/plate.jpg")
	var base := Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)
	_rect(base, Rect2(0, 0, 800, 380), Color(0.55, 0.78, 0.95))
	_rect(base, Rect2(0, 380, 800, 520), Color(0.36, 0.66, 0.26))
	_rect(base, Rect2(800, 0, 800, 900), Color(0.10, 0.08, 0.12))
	# 原大：三种境界，亮底 / 暗底各一列
	var rows := [[0, 1.0, 90.0, 90.0, 1, 0.0], [4, 0.62, 33.6, 112.0, 13, 0.55], [7, 0.22, 104.0, 130.0, 24, 0.9]]      # 2026-11-20 夜：灵力按单位（combat_stats.MP_UNITS）
	for k in 2:
		for i in rows.size():
			var r: Array = rows[i]
			var pl := _plate(base, Vector2(14.0 + 800.0 * k, 12.0 + 130.0 * i))
			var lv := int(r[4])
			_todo.append([pl, [int(r[0]), float(r[1]), Plate.hp_cap(lv), float(r[2]), float(r[3]), lv, float(r[5]),
					Plate.power(int(r[0]), lv, {"atk": 0.12 * i, "guard": 0.06 * i}), i == 2 and k == 1, i == 1 and k == 1]])
		# 放大两倍的一块，看细节
		var big := Control.new()
		big.position = Vector2(14.0 + 800.0 * k, 430.0)
		big.scale = Vector2(1.7, 1.7)
		base.add_child(big)
		var pl2 := _plate(big, Vector2.ZERO)
		_todo.append([pl2, [2 + 3 * k, 0.8, Plate.hp_cap(7 + 9 * k), 70.0, 100.0, 7 + 9 * k, 0.35, Plate.power(2 + 3 * k, 7 + 9 * k, {})]])
		# 圆按钮
		for j in 3:
			var b := UiStyle.round_icon_button("pouch")
			b.position = Vector2(480.0 + 800.0 * k + 104.0 * j, 8.0)
			b.set_meta("badge", ["", "3/12", "12/12"][j])
			b.set_meta("badge_hot", j == 2)
			base.add_child(b)
		var b2 := UiStyle.round_icon_button("pouch")
		b2.position = Vector2(520.0 + 800.0 * k, 160.0)
		b2.scale = Vector2(1.7, 1.7)
		b2.set_meta("badge", "洞府")
		base.add_child(b2)


func _plate(parent: Control, pos: Vector2) -> Control:
	var pl: Control = Plate.new()
	pl.font = UiStyle.kai()
	pl.position = pos
	parent.add_child(pl)
	return pl


func _rect(parent: Control, r: Rect2, col: Color) -> void:
	var c := ColorRect.new()
	c.color = col
	c.position = r.position
	c.size = r.size
	parent.add_child(c)


func _process(_dt: float) -> bool:
	_n += 1
	if _n >= 2:
		for t: Array in _todo:
			(t[0] as Control).callv("set_values", t[1])
	if _n == 14:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(_out, 0.92)
		print("saved ", _out, " ", img.get_size())
		return true
	return false
