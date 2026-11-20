extends SceneTree
## 随包字体的后备链小样（Windows 上游戏本身走系统楷体，看不到随包字体；这里直接拿随包字体写几行字截图）：
##   python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1200x420 -s res://_tasks/ui_kit/font_test.gd -- <输出 jpg 绝对路径>

const UiStyle := preload("res://scripts/ui_style.gd")

var _n := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview/ui_fonts.jpg")
	var bg := ColorRect.new()
	bg.color = UiStyle.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var body := UiStyle.bundled(UiStyle.BODY_FILE)
	var title := UiStyle.bundled(UiStyle.TITLE_FILE)
	var txt := "云梦山　挣脱　派生　温养　淬炼　海滨　荒原　、。「」（），：；？〔〕｜"
	var rows := [[body, "正文：" + txt], [title, "题字：" + txt], [title, "储物袋　择境　开始匹配　归　陨　木兰草原 · 入境"], [body, "暮色草海，四方是黄枫谷、血色禁地、云梦山、坠魔谷。"]]
	for i in rows.size():
		var l := Label.new()
		l.text = rows[i][1]
		l.add_theme_font_override("font", rows[i][0])
		l.add_theme_font_size_override("font_size", 34)
		l.add_theme_color_override("font_color", UiStyle.TEXT_INK)
		l.position = Vector2(24, 24 + 92 * i)
		root.add_child(l)


func _process(_dt: float) -> bool:
	_n += 1
	if _n == 10:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(_out, 0.9)
		print("saved ", _out)
		return true
	return false
