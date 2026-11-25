extends CanvasLayer
## 全屏播报：一条横贯整个屏幕的宣纸横幅——大世界里有人结婴成功时通告全场（raid_manager.gd 的 _on_yuanying / net_announce）。
## 样式走 ui_style.gd 的纸片（见记忆里的界面定调）：宣纸面、细墨线、底边一抹远山，左边一方朱印，中间行楷大字，下面一笔枯墨和一行小字。
## 用法：var b = Broadcast.make(host, "结婴功成", "某某 于木兰草原凝结元婴 · 天地同贺", "贺", 0.7)，到点了调 b.play()。
##   · make 之后节点就在场景里了，只是全透明：大号字形趁这时候先光栅化，真正亮出来的那一帧不卡
##   · 横幅的高度跟着文字算（网页 / 手机的字体行高比桌面的大），不写死；y_frac 是横幅中线在屏幕高度的几成处
##   · 动画全用 Tween（展开 → 停留 → 淡出），不每帧重画
## 故意不写 class_name：用 preload 引用。

const UiStyle := preload("res://scripts/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")
const HOLD := 3.6          # 亮着多久
const IDLE_FREE := 40.0    # 建好之后一直没人调 play（过场被跳过 / 出了岔子）：这么久后自己清掉

var title := ""
var line := ""
var seal_text := "贺"
var y_frac := 0.2

var _root: Control
var _band: PanelContainer
var _played := false


static func make(host: Node, title_text: String, line_text: String, seal := "贺", y := 0.2) -> CanvasLayer:
	var b: CanvasLayer = (load("res://scripts/realm_broadcast.gd") as GDScript).new()
	b.title = title_text
	b.line = line_text
	b.seal_text = seal
	b.y_frac = y
	host.add_child(b)
	return b


func _ready() -> void:
	layer = 37                  # 压在过场的黑边（36）上面
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vs := get_viewport().get_visible_rect().size
	var k := clampf(vs.y / 720.0, 0.6, 2.4)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)
	# 横幅：左右各伸出屏幕一截，纸的竖边留在画面外，看着就是一条横贯全屏的长卷
	_band = PanelContainer.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_theme_stylebox_override("panel", UiStyle.scroll(8.0 * k, true))
	_band.anchor_left = 0.0
	_band.anchor_right = 1.0
	_band.anchor_top = y_frac
	_band.anchor_bottom = y_frac
	_band.offset_left = -70.0
	_band.offset_right = 70.0
	_band.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_band)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(26.0 * k))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var sl := UiStyle.seal(seal_text, 64.0 * k)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(2.0 * k))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiStyle.brush())
	t.add_theme_font_size_override("font_size", int(58.0 * k))
	t.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	t.add_theme_constant_override("line_spacing", 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var stroke := UiStyle.rule(380.0 * k, 9.0 * k)
	stroke.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(stroke)
	var s := Label.new()
	s.text = line
	s.add_theme_font_override("font", UiStyle.kai())
	s.add_theme_font_size_override("font_size", int(23.0 * k))
	s.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	# 右边留一块和朱印一样宽的空，字才在正中
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(64.0 * k, 1.0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	get_tree().create_timer(IDLE_FREE, true, false, true).timeout.connect(func() -> void:
		if not _played and is_inside_tree():
			queue_free())


## 亮出来：横幅从一条线展开，停一会儿，淡出，自己清掉
func play() -> void:
	if _played:
		return
	_played = true
	_band.pivot_offset = _band.size * 0.5
	_band.scale = Vector2(1.0, 0.08)
	Sfx.play("thud", -8.0, 1.25)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_root, "modulate:a", 1.0, 0.22)
	tw.tween_property(_band, "scale:y", 1.0, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(HOLD)
	tw.chain().tween_property(_root, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(queue_free)
