extends RefCounted
## 「武侠漫画分镜」界面样张的样式件（2026-11-25，样张阶段：放在 _tasks 下、不进包、不动现有界面）。
## 用户给的参考是美漫格斗游戏的主菜单 / 选人界面（存了一份在 ref/），要的是那套设计语言，不是照搬：
##   稿纸底 + 淡淡的制图线、一暖一冷两块平涂色 + 黑墨线 + 纸白、斜切的色块（没有圆角矩形）、选中 = 整块反色、
##   超粗的斜体标题字配很小的标注字、角色压在色块上冲出画框。
## 本地化：制图线换成阵图 / 罗盘刻度，小字标注用中文，橙蓝换成每位英雄自己的主色（镇岳鎏金橙 / 苍鸿靛青 / 霜华冰青）。
## 标题字 = 得意黑（Smiley Sans Oblique，SIL OFL 1.1，_tasks/ui_fonts/donor_smileysans/，样张里直接从那儿读，没进 assets/）；
## 正文 = 随包的 Noto Sans（手机上就是这款）。
## 故意不写 class_name：const Kit := preload("res://_tasks/ui_comic/comic_kit.gd")。

const UiStyle := preload("res://scripts/ui_style.gd")

const PAPER := Color(0.937, 0.906, 0.839)
const PAPER_HI := Color(0.976, 0.957, 0.906)
const PAPER_LO := Color(0.868, 0.828, 0.742)
const INK := Color(0.09, 0.078, 0.102)
const INK_SOFT := Color(0.09, 0.078, 0.102, 0.6)
const BLUE := Color(0.14, 0.34, 0.66)            # 稿纸上的制图线
const VERMILION := Color(0.91, 0.27, 0.165)      # 印章 / 警示
const SKEW := 0.21                               # 斜切：每高 1 像素上边往右偏多少（约 12 度，和得意黑的斜度接近）

const ACCENT := {
	"yujian": Color(0.945, 0.545, 0.1),          # 镇岳：鎏金橙
	"canghong": Color(0.17, 0.39, 0.84),         # 苍鸿：靛青
	"shuanghua": Color(0.13, 0.7, 0.78),         # 霜华：冰青
}
## 三个关键词 + 各招比划哪几个姿势（照 scripts/ex/hero_select_ui.gd 的 SHOW 抄的；样张不引用那个脚本，免得它在改的时候把样张带崩）
const SHOW := {
	"yujian": {"tags": ["重拳连段", "霸体破防", "开山裂地"], "enter": ["zy_awk"],
		"demo": [["zy1", "zy2", "zy3", "zy4"], ["zy_bs"], ["zy_j1", "zy_j2", "zy_j1", "zy_j2", "zy_palm"], ["zy_kao"], ["zy_quake"], ["zy_awk"]]},
	"canghong": {"tags": ["藏锋拔剑", "剑痕引爆", "招架反斩"], "enter": ["cg_gj"],
		"demo": [["cg1", "cg2", "cg3", "cg4"], ["cg_w1", "cg_w2", "cg_w3"], ["cg_parry", "cg_f2", "cg_gj"], ["cg_lk"], ["cg_f1", "cg_f2", "cg_f1", "cg_f2", "cg_f1", "cg_gj"], ["cg_awk"]]},
	"shuanghua": {"tags": ["中距控场", "寒意冻结", "碎冰爆发"], "enter": ["sh_awk"],
		"demo": [["sh1", "sh2", "sh3", "sh4"], ["sh_cast"], ["sh_nova"], ["sh_q"], ["sh_r"], ["sh_awk"]]},
}
const TITLE_PATH := "res://_tasks/ui_fonts/donor_smileysans/SmileySans-Oblique.ttf"

static var _title: Font
static var _body: Font


static func accent(id: String) -> Color:
	return ACCENT.get(id, Color(0.945, 0.545, 0.1))


## 压在主色块上的字用墨色还是纸色（主色暗就用纸色）
static func on(c: Color) -> Color:
	return INK if c.get_luminance() > 0.34 else PAPER_HI


static func body() -> Font:
	if _body == null:
		_body = UiStyle.bundled(UiStyle.BODY_FILE)
		if _body == null:
			_body = ThemeDB.fallback_font
	return _body


static func title() -> Font:
	if _title == null:
		var ff := FontFile.new()
		var p := ProjectSettings.globalize_path(TITLE_PATH)
		if FileAccess.file_exists(p) and ff.load_dynamic_font(p) == OK:
			var chain: Array[Font] = [body()]
			ff.fallbacks = chain
			_title = ff
		else:
			push_warning("没找到得意黑（%s），标题先用正文字体" % p)
			_title = body()
	return _title


static func label(text: String, px: int, col: Color, use_title := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title() if use_title else body())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 同色描边把字加粗（得意黑只有一个字重，大标题要更压得住）
static func bold(l: Label, px: int) -> void:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", l.get_theme_color("font_color"))


static func recolor(l: Label, col: Color) -> void:
	l.add_theme_color_override("font_color", col)
	if l.has_theme_constant_override("outline_size"):
		l.add_theme_color_override("font_outline_color", col)


const NO_START := "，。；：、！？）」』》〉】％…—·,.;:!?)]}%"      # 不能落在行首的
const NO_END := "（「『《〈【([{"                                # 不能落在行尾的


static func _alnum(ch: String) -> bool:
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


## 自己断行（中文排版的避头尾：标点不落行首、开括号不落行尾、连着的数字不拆）。
## 网页版的文字引擎没有中文断行规则，全游戏的说明文字都是按字硬断的（行首会落标点），所以这里不用 Label 的自动换行
static func wrap(text: String, font: Font, px: int, width: float) -> String:
	var out: PackedStringArray = []
	for para: String in text.split("\n"):
		var line := ""
		var w := 0.0
		var i := 0
		var n := para.length()
		while i < n:
			var j := i
			while j < n and NO_END.contains(para[j]):            # 开括号粘住后面那个字
				j += 1
			if j < n:
				if _alnum(para[j]):                              # 连着的数字 / 字母（含小数点）不拆
					j += 1
					while j < n and (_alnum(para[j]) or (para[j] == "." and j + 1 < n and _alnum(para[j + 1]))):
						j += 1
				else:
					j += 1
			while j < n and NO_START.contains(para[j]):          # 后面的标点粘在这个字上
				j += 1
			var unit := para.substr(i, j - i)
			var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if line != "" and w + uw > width:
				out.append(line.strip_edges(false, true))
				line = ""
				w = 0.0
				if unit.begins_with(" "):
					unit = unit.lstrip(" ")
					uw = font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			line += unit
			w += uw
			i = j
		out.append(line)
	return "\n".join(out)


## 透明底的按钮（样子由里面的色块自己画）
static func ghost_button() -> Button:
	var b := Button.new()
	var e := StyleBoxEmpty.new()
	for n: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(n, e)
	b.focus_mode = Control.FOCUS_NONE
	return b
