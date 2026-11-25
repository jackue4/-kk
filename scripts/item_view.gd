extends RefCounted
## 物品格子（局内背包 raid_hud.gd、洞府 abode_ui.gd 共用）。
## tile：手机上用的方格 —— 一个大图标 + 一行名字，别的不写（2026-11-23 起背包 / 洞府都用它）。
## slot：老的横条格子 —— 左边图标 + 右边名字 / 品阶 / 一行小字（字小，手机上看不清，现在没人用了，留着备查）。
## card：大世界里的拾取小卡片。选中时换朱砂描边。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const Prog := preload("res://scripts/progression.gd")    # 2026-11-23：灵石 / 价值也走统一的短写（short_num）


static func _ink(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	return l


## it 为空 = 空格子（disabled）。size 是格子的最小尺寸；price >= 0 时右下角写价钱
static func slot(it: Dictionary, size: Vector2, selected := false, price := -1, empty_text := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiStyle.slot(it.is_empty(), selected))
	b.add_theme_stylebox_override("hover", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("pressed", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("disabled", UiStyle.slot(true))
	if selected:
		b.add_theme_stylebox_override("normal", UiStyle.outline(UiStyle.CINNABAR))
		b.add_theme_stylebox_override("hover", UiStyle.outline(UiStyle.CINNABAR))
	if it.is_empty():
		b.disabled = true
		if empty_text != "":
			var e := _ink(empty_text, 15, Color(UiStyle.TEXT_SOFT, 0.55))
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(e)
		return b
	var h := size.y
	var ic_s := minf(h - 20.0, 64.0)
	var tier := int(it.get("tier", 0))
	var col := UiStyle.on_paper(Data.TIER_COLORS[tier])
	var ic := TextureRect.new()
	ic.texture = UiStyle.icon(Items.icon_name(it))
	if ic.texture == null:
		ic.texture = UiStyle.icon(str(it.get("kind", "")))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(8.0, (h - ic_s) * 0.5)
	ic.size = Vector2(ic_s, ic_s)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var x0 := ic_s + 14.0
	var w := size.x - x0 - 8.0
	var fs := 19 if h >= 80.0 else 17
	var nm := _ink(str(it.get("name", "")), fs, UiStyle.TEXT_INK)
	nm.position = Vector2(x0, h * 0.5 - fs - 4.0)
	nm.size = Vector2(w, fs + 6)
	b.add_child(nm)
	# 窄格子（佩戴栏）放不下品阶 + 小字：只留小字，品阶看名字的颜色
	var narrow := size.x < 200.0
	if narrow:
		nm.add_theme_color_override("font_color", col.darkened(0.25))
	else:
		var tl := _ink(Items.tier_word(it), 15, col)      # 修为丹名字里带了品质，这里空着（Items.tier_word）
		tl.position = Vector2(x0, h * 0.5 + 4.0)
		tl.size = Vector2(56.0, 20.0)
		b.add_child(tl)
	var extra := _ink(("%s 灵石" % Prog.short_num(price)) if price >= 0 else Items.badge(it), 15, UiStyle.CINNABAR if price >= 0 else UiStyle.TEXT_SOFT)
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if narrow else HORIZONTAL_ALIGNMENT_RIGHT
	extra.position = Vector2(x0 if narrow else x0 + 40.0, h * 0.5 + 4.0)
	extra.size = Vector2(w if narrow else maxf(w - 40.0, 20.0), 20.0)
	b.add_child(extra)
	if Items.size_of(it) > 1:
		var two := _ink("2格", 13, UiStyle.CINNABAR)
		two.position = Vector2(size.x - 34.0, 4.0)
		two.size = Vector2(30.0, 16.0)
		b.add_child(two)
	return b


## 手机上用的方格（2026-11-23，用户原话：仓库「展示的信息太多了，导致也有点看不清」）：
## 上面一个大图标，下面一行名字（品阶色，放不下截掉），别的都不写 —— 品阶、效果、价值点中了在面板底下看。
## corner 非空 = 右上角的小字（叠了几件「×12」/ 灵材「2格」）；note 非空 = 名字下面多一行朱砂小字（坊市的价钱）。
## 选中换朱砂描边；it 为空 = 空格子（empty_text 写在正中）。
static func tile(it: Dictionary, size: Vector2, selected := false, corner := "", note := "", empty_text := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiStyle.slot(it.is_empty(), selected))
	b.add_theme_stylebox_override("hover", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("pressed", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("disabled", UiStyle.slot(true))
	if selected:
		b.add_theme_stylebox_override("normal", UiStyle.outline(UiStyle.CINNABAR))
		b.add_theme_stylebox_override("hover", UiStyle.outline(UiStyle.CINNABAR))
	if it.is_empty():
		b.disabled = true
		if empty_text != "":
			var e := _ink(empty_text, 18, Color(UiStyle.TEXT_SOFT, 0.5))
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(e)
		return b
	var fs := 24 if size.x >= 140.0 else 20
	var name_h := float(fs) + 12.0
	var note_h := 26.0 if note != "" else 0.0
	var col := UiStyle.on_paper(Data.TIER_COLORS[clampi(int(it.get("tier", 0)), 0, Data.TIER_COLORS.size() - 1)])
	# 图标：占掉名字上面的那块，居中
	var room := size.y - name_h - note_h - 12.0
	var ic_s := clampf(minf(size.x - 28.0, room), 28.0, 92.0)
	var ic := TextureRect.new()
	ic.texture = UiStyle.icon(Items.icon_name(it))
	if ic.texture == null:
		ic.texture = UiStyle.icon(str(it.get("kind", "")))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2((size.x - ic_s) * 0.5, 7.0 + (room - ic_s) * 0.5)
	ic.size = Vector2(ic_s, ic_s)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	# 名字：定好的框里竖直居中（网页 / 手机上的字体行高和桌面不一样）
	var nm := _ink(str(it.get("name", "")), fs, col.darkened(0.25))
	nm.position = Vector2(4.0, size.y - note_h - name_h - 4.0)
	nm.size = Vector2(size.x - 8.0, name_h)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(nm)
	if note != "":
		var nt := _ink(note, 18, UiStyle.CINNABAR)
		nt.position = Vector2(4.0, size.y - note_h - 4.0)
		nt.size = Vector2(size.x - 8.0, note_h)
		nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(nt)
	if corner != "":
		var cn := _ink(corner, 18, UiStyle.CINNABAR)
		cn.position = Vector2(size.x - 70.0, 3.0)
		cn.size = Vector2(64.0, 24.0)
		cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(cn)
	return b


## 拾取小卡片（2026-11-20 按用户给的参考图改的）：一张窄纸条 = 左边道具图标 + 名字（品阶色）+ 一行小字；点一下就拾取。
## key 非空时右上角写个小键位提示（键盘 T 拾取最上面那张）
static func card(it: Dictionary, size: Vector2, key := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiStyle.slot(false))
	b.add_theme_stylebox_override("hover", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("pressed", UiStyle.slot(false, true))
	var h := size.y
	var tier := int(it.get("tier", 0))
	var col := UiStyle.on_paper(Data.TIER_COLORS[tier])
	# 窄卡片（2026-11-20 用户要求缩到一半宽）：左边图标，右边一列字——名字放不下就折成两行，下面一行小字放不下就截掉
	# 2026-11-23 用户说手机上卡片太小：卡片高到 80 以上（触屏那一档）图标和字都按大一号排
	var big := h >= 80.0
	var ic_s := minf(h - 20.0, 58.0 if big else 42.0)
	var ic := TextureRect.new()
	ic.texture = UiStyle.icon(Items.icon_name(it))
	if ic.texture == null:
		ic.texture = UiStyle.icon(str(it.get("kind", "")))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(6.0, (h - ic_s) * 0.5 - 2.0)
	ic.size = Vector2(ic_s, ic_s)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	# 图标底下一道品阶色的短线
	var bar := ColorRect.new()
	bar.color = Color(col, 0.85)
	bar.position = Vector2(8.0, ic.position.y + ic_s + 2.0)
	bar.size = Vector2(ic_s - 4.0, 2.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	var x0 := ic_s + (15.0 if big else 12.0)
	var w := size.x - x0 - (14.0 if key != "" else 6.0)
	var col_box := VBoxContainer.new()
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col_box.add_theme_constant_override("separation", 0)
	col_box.position = Vector2(x0, 3.0)
	col_box.size = Vector2(w, h - 6.0)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col_box)
	var nm := _ink(str(it.get("name", "")), 21 if big else 17, col.darkened(0.2))
	nm.clip_text = false
	nm.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY      # 中文没有空格，按字折行
	nm.max_lines_visible = 2
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS      # 两行还放不下的截掉（卡片在触屏上收窄了）
	nm.custom_minimum_size = Vector2(w, 0.0)
	nm.add_theme_constant_override("line_spacing", -3)
	col_box.add_child(nm)
	var tw := Items.tier_word(it)
	var sub := _ink(("%s·%s" % [tw, Items.badge(it)]) if tw != "" else Items.badge(it), 16 if big else 13, UiStyle.TEXT_SOFT)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.custom_minimum_size = Vector2(w, 0.0)
	col_box.add_child(sub)
	if key != "":
		var k := _ink(key, 13, UiStyle.CINNABAR)
		k.position = Vector2(size.x - 13.0, 2.0)
		k.size = Vector2(12.0, 16.0)
		b.add_child(k)
	return b


## 选中物品的说明：名字 · 品阶 · 种类 —— 一句话效果 —— 价值
static func detail_text(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	return "%s · %s%s　%s　值 %s 灵石" % [str(it.get("name", "")), Items.tier_word(it),
			str(Items.KIND_NAMES.get(str(it.get("kind", "")), "")), Items.desc(it), Prog.short_num(float(it.get("value", 0)))]
