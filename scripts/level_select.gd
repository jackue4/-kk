extends CanvasLayer
## 择境：走进大厅传送门弹出的关卡选择（游戏暂停、放出鼠标；回车 / 点卡片进入，Esc 返回）。
## 也负责切关时的黑场淡入淡出和"载入中"字样。关卡表 LEVELS 加一行就多一张卡片
## （art = assets/ui/ 里的一张画，没有就用 sky / land 两个颜色画一张渐变小景）。
## 卡片和入境页都是宣纸面板（样式见 ui_style.gd）。
## 故意不写 class_name：用 preload 引用。

signal picked(id: String)
signal closed

const LEVELS := [
	{"id": "mulan", "title": "木兰草原", "tag": "开放世界 · 搜打撤 · 最多 40 人",
		"desc": "暮色草海，四方是黄枫谷、血色禁地、云梦山、坠魔谷。\n采灵药、破禁制、杀怪夺宝，20 分钟内找到亮着的阵撤离，东西才归洞府。\n可单人进入，也可局域网组队。",
		"art": "level_mulan", "sky": Color(0.96, 0.52, 0.24), "land": Color(0.12, 0.36, 0.32)},
	# 两张新图（主城门 2 / 3 直接进入境页，不在门 0 的选关里出现）。2026-11-25 主干解耦：hard = 元婴以上的高危禁地，规矩和木兰草原一样
	{"id": "desert", "title": "沙海古墟", "tag": "元婴及以上 · 高危禁地 · 地面 + 地下", "hard": true, "min_realm": 3,
		"desc": "黄沙埋着上古神塔，地底还有暗窟与首领巢穴。\n妖兽比大世界更凶，灵药、法宝、破境丹也更多；找到亮着的传送阵撤出，东西才归洞府。\n可单人进入，也可局域网组队。",
		"art": "", "sky": Color(0.98, 0.72, 0.38), "land": Color(0.62, 0.42, 0.22)},
	{"id": "lab", "title": "天工秘所", "tag": "元婴及以上 · 高危禁地 · 楼宇 + 密窟", "hard": true, "min_realm": 3,
		"desc": "被尸傀占了的机关坊园区，楼里有禁制宝库、楼下有密窟。\n比沙海古墟更凶险，深处是化神以上的妖物；找到亮着的传送阵撤出，东西才归洞府。\n可单人进入，也可局域网组队。",
		"art": "", "sky": Color(0.62, 0.56, 0.86), "land": Color(0.26, 0.28, 0.34)},
]
const EX_META := "res://scripts/ex/meta_ui.gd"           # 2026-11-24 界面重做：全屏的「元界面」（备战 / 坊市 / 境界三张页）；2026-11-25 起走修仙存档 raid_profile
const Profile := preload("res://scripts/raid_profile.gd")
const HeroDefs := preload("res://scripts/hero_defs.gd")

const UiStyle := preload("res://scripts/ink_style.gd")      # 2026-11-24 界面重做：换成墨玉样式（接口同 ui_style.gd，见那个文件头）
const Abode := preload("res://scripts/abode_ui.gd")

var font: Font
var _abode: Control = null        # 开着的洞府界面
var _loadout_lab: Label = null    # 入境页上「这次带什么」那一行
var net: Node = null          # 联机（net.gd）：列房间用
## 选好的进入方式（main.gd 在 picked 之后读）：match 一键匹配（界面上只有这一种）；solo 单机 / host 建房 / join 加入 join_ip 留给自检脚本
var mode := "solo"
var team_size := 1
var join_ip := ""
var _lv := 0
var _size_btns: Array[Button] = []
var _menu: Control
var _fade: ColorRect
var _loading: Label
var _first: Button
var _hero_btns: Array = []        # 入境页的英雄按钮 [[id, Button], …]（2026-11-25 起每张图都有）


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_loading = _label("", 34, Color(0.92, 0.9, 0.84))
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_loading)


func is_open() -> bool:
	return _menu != null


## 2026-11-24 F_ui：画面这会儿是亮的（没开选关、没在黑场里）—— hud.gd 在主城里排的提示（段位题字 / 离线结算 / 新号引导）等到这时才说
func is_clear() -> bool:
	return _menu == null and _fade.color.a < 0.05


func fade(to_alpha: float, dur: float) -> void:
	# 2026-11-21 QA BUG-01：黑场盖着的时候吃掉点击（以前一直是 IGNORE，载入黑场里点击会落到下面主城的洞府按钮上）
	if to_alpha > 0.0:
		_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", to_alpha, dur)
	await tw.finished
	if to_alpha <= 0.0:
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_loading(text: String) -> void:
	_loading.text = text


func open() -> void:
	if _menu != null:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	move_child(_menu, 0)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	_menu.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 26)
	col.add_child(head)
	var cloud_l := UiStyle.deco("cloud", Vector2(132, 54), Color(UiStyle.PAPER, 0.85))
	cloud_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cloud_l.flip_h = true
	head.add_child(cloud_l)
	var title := _label("择  境", 72, UiStyle.PAPER)
	title.add_theme_font_override("font", UiStyle.brush())
	title.add_theme_color_override("font_outline_color", Color(UiStyle.INK, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	head.add_child(title)
	var cloud_r := UiStyle.deco("cloud", Vector2(132, 54), Color(UiStyle.PAPER, 0.85))
	cloud_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cloud_r)
	var sub := _label("踏入传送门，择一方天地", 22, Color(UiStyle.PAPER, 0.82))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)
	_first = null
	for i in LEVELS.size():
		if bool(LEVELS[i].get("hard", false)):
			continue        # 新图走主城门 2 / 3（open_level）
		var b := _card(LEVELS[i])
		row.add_child(b)
		b.pressed.connect(pick.bind(i))
		if _first == null:
			_first = b
	var hint := _label("回车 / 点击 进入　　Esc 返回", 20, Color(UiStyle.PAPER, 0.62))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	if _first != null:
		_first.grab_focus()


func close() -> void:
	if _menu == null:
		return
	if net != null:
		net.stop_discovery()
	if is_instance_valid(_abode):
		_abode.queue_free()
	_size_btns.clear()
	_hero_btns.clear()
	_menu.queue_free()
	_menu = null
	get_tree().paused = false
	closed.emit()


## 主城门 2 / 3：直接打开 id 那张图的入境页（不经过卡片页）。境界不到门槛就不开（主城门口、main._on_hub_gate 已经挡过，这里兜底）
func open_level(id: String) -> void:
	var idx := -1
	for i in LEVELS.size():
		if String(LEVELS[i]["id"]) == id:
			idx = i
	if idx < 0:
		open()
		return
	if realm_lock(idx) != "":
		return
	open()
	pick(idx)


## 第 i 张图的境界门槛：够了返回 ""，不够返回提示（存档境界，和主城门口同一个口径）
func realm_lock(i: int) -> String:
	var need := int(LEVELS[clampi(i, 0, LEVELS.size() - 1)].get("min_realm", 0))
	var r := Profile.realm()
	if r >= need:
		return ""
	return "%s凶险 · %s期方可入内（你现在是%s期）" % [str(LEVELS[i]["title"]), str(Realm.LIST[need]["name"]),
			str(Realm.LIST[clampi(r, 0, Realm.LIST.size() - 1)]["name"])]


## 入境页那一行「这次带什么」：出战英雄 + 洞府里带的法宝 / 丹符（abode_ui.summary）
func _summary() -> String:
	var d: Dictionary = HeroDefs.def_of(Profile.hero())
	var nm := str(d.get("name", ""))
	var s := Abode.summary()
	return s if nm == "" else "出战 %s　%s" % [nm, s]


## 开始前的入场检查，返回原因；空 = 能进：一局没结束不能再进（Profile.in_raid）、新图要元婴
func _entry_err() -> String:
	if Profile.in_raid():
		return Profile.RAID_LOCK
	return realm_lock(_lv)


## 点了关卡卡片：换成「入境」一页（选组队人数 → 开始匹配）。quick = 直接单机进入（自检脚本用；境界不够照样挡）
func pick(i: int, quick := false) -> void:
	if _menu == null:
		return
	_lv = i
	if quick or net == null:
		if realm_lock(i) != "":
			push_warning("[select] " + realm_lock(i))
			return
		mode = "solo"
		_go()
		return
	_show_modes()


func _go() -> void:
	var id: String = LEVELS[_lv]["id"]
	if net != null and mode != "match":
		net.stop_discovery()
	if is_instance_valid(_abode):
		_abode.queue_free()
	_menu.queue_free()
	_menu = null
	_size_btns.clear()
	_hero_btns.clear()
	get_tree().paused = false
	picked.emit(id)


func _btn(text: String, w := 420.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 56.0)
	b.add_theme_font_size_override("font_size", 24)
	UiStyle.style_button(b)
	return b


func _set_size(n: int) -> void:
	team_size = n
	for i in _size_btns.size():
		_size_btns[i].button_pressed = [1, 2, 4][i] == n


## 入境页：选组队人数（独行 / 双人 / 四人）→「开始匹配」。
## 匹配由 main.gd 接手：局域网里有房间就进去、和同样人数还有空位的队伍拼到一起；没有房间就自己开一间等别人进来；
## 队伍里缺的人先由 AI 道友补上，之后有真人进队再把 AI 换下来。
func _show_modes() -> void:
	for c in _menu.get_children():
		c.queue_free()
	net.start_discovery()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.045, 0.04, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.scroll(34.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var title := _label("%s · 入境" % LEVELS[_lv]["title"], 50, UiStyle.TEXT_INK)
	title.add_theme_font_override("font", UiStyle.brush())
	head.add_child(title)
	var seal := UiStyle.seal("境", 46.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(seal)
	var rule := UiStyle.rule(420.0, 9.0, Color(UiStyle.LINE, 0.82))
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 14)
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(r2)
	_size_btns.clear()
	for n: int in [1, 2, 4]:
		var b := Button.new()
		b.text = ["独行", "双人队", "四人队"][[1, 2, 4].find(n)]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(168.0, 76.0)
		b.add_theme_font_size_override("font_size", 28)
		UiStyle.style_button(b, true)
		b.pressed.connect(_set_size.bind(n))
		r2.add_child(b)
		_size_btns.append(b)
	_set_size(team_size)
	_hero_row(col)      # 英雄到处都用（2026-11-25 起每张图的入境页都有这一排）
	# 备战（2026-11-20）：这次带什么进去 + 去洞府整理
	var prep := HBoxContainer.new()
	prep.add_theme_constant_override("separation", 14)
	prep.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(prep)
	_loadout_lab = _label(_summary(), 19, UiStyle.TEXT_INK)
	_loadout_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prep.add_child(_loadout_lab)
	var abode := _btn("备战", 220.0)
	abode.custom_minimum_size = Vector2(220.0, 60.0)
	abode.pressed.connect(open_abode)
	prep.add_child(abode)
	var go := _btn("开始匹配", 540.0)
	go.custom_minimum_size = Vector2(540.0, 84.0)
	go.add_theme_font_size_override("font_size", 38)
	UiStyle.style_primary(go)
	col.add_child(go)
	var tip := _label("自动匹配同队道友，人不够由 AI 道友补位；队友之间互不伤害。\n佩戴的法宝和背包陨落即失，储物戒里的保得住；20 分钟内找到亮着的阵撤离。", 18, UiStyle.TEXT_SOFT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tip)
	if bool(LEVELS[_lv].get("hard", false)):
		tip.text += "\n元婴及以上方可入境；妖兽更凶，掉落更好。"
	go.pressed.connect(func() -> void:
		var err := _entry_err()
		if err != "":
			tip.text = err
			tip.add_theme_color_override("font_color", UiStyle.CINNABAR)
			return
		mode = "match"
		_go())
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(160.0, 52.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 22)
	UiStyle.style_button(back, true)
	back.pressed.connect(close)
	col.add_child(back)
	go.grab_focus()


## 入境页上一排英雄按钮（2026-11-24 F_ui 起；2026-11-25 主干解耦：读写 raid_profile，全部免费、每张图都有），点一下就换（存档 + 主城里的主角当场换）。
## 新号（一局都没进过）上面多一行朱字提示先挑英雄
func _hero_row(col: VBoxContainer) -> void:
	_hero_btns.clear()
	var ids: Array = Profile.hero_ids()
	if ids.size() < 2:
		return
	if int(Profile.stats().get("raids", 0)) == 0:
		var first := _label("第一次入境：先挑一位英雄（右上角「英雄」能看每一招）", 20, UiStyle.CINNABAR)
		first.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(first)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var cap := _label("英雄", 26, UiStyle.TEXT_SOFT)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	for id: Variant in ids:
		var d: Dictionary = HeroDefs.def_of(str(id))
		var nm := str(d.get("name", id))
		var tt := str(d.get("title", ""))
		var b := Button.new()
		b.text = nm + ("·" + tt if tt != "" else "")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(200.0, 64.0)
		b.add_theme_font_size_override("font_size", 26)
		UiStyle.style_button(b, true)
		b.pressed.connect(_pick_hero.bind(str(id)))
		row.add_child(b)
		_hero_btns.append([str(id), b])
	_sync_hero_btns()


func _sync_hero_btns() -> void:
	var cur := Profile.hero()
	for e: Array in _hero_btns:
		if is_instance_valid(e[1]):
			(e[1] as Button).set_pressed_no_signal(str(e[0]) == cur)


func _pick_hero(id: String) -> void:
	var err := Profile.set_hero(id)
	if err == "":
		# 主城里（还没进图）主角当场换，和「英雄」界面一样
		var m := get_parent()
		if m != null and m.get("level") == null:
			var p: Variant = m.get("player")
			if p != null and is_instance_valid(p) and (p as Object).has_method("set_hero"):
				p.call("set_hero", id)
	_sync_hero_btns()
	if is_instance_valid(_loadout_lab):
		_loadout_lab.text = _summary()


func _unhandled_input(e: InputEvent) -> void:
	if _menu == null or is_instance_valid(_abode):
		return
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 开新的全屏元界面（meta_ui.gd，备战 / 坊市 / 境界）还是老的洞府三页（abode_ui.gd）：
## 命令行带 --old-abode（或老洞府自己的自检 --abode-test / --abode-open-test）时开老的
func _use_meta() -> bool:
	if not ResourceLoader.exists(EX_META):
		return false
	for a: String in OS.get_cmdline_user_args():
		if a == "--old-abode" or a.begins_with("--abode-test") or a.begins_with("--abode-open-test"):
			return false
	return true


## 洞府：主城右上角「备战」/ 仓库 / 商店 / 入境页的「备战」都走这里。2026-11-25 主干解耦：默认开修仙版的 meta_ui.gd
## （接口 closed / _set_tab / _tab / _close，和 abode_ui.gd 一样），关掉后刷新入境页「这次带什么」那一行
func open_abode() -> void:
	if is_instance_valid(_abode):
		return
	_abode = (load(EX_META) as GDScript).new() if _use_meta() else Abode.new()
	_abode.set("font", font)
	add_child(_abode)
	_abode.closed.connect(func() -> void:
		_sync_hero_btns()
		if is_instance_valid(_loadout_lab):
			_loadout_lab.text = _summary())


## 关卡卡片：一张宣纸，上面一幅小画（右下角钤一方「境」印），下面是题名、一行朱字的标签和说明
func _card(lv: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(460.0, 452.0)
	b.focus_mode = Control.FOCUS_ALL
	var normal := UiStyle.scroll(0.0, false)
	var hover := UiStyle.scroll(0.0, false)
	hover.border_color = UiStyle.SELECT
	hover.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", hover)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 30.0
	box.offset_right = -30.0
	box.offset_top = 30.0
	box.offset_bottom = -26.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	b.add_child(box)
	var thumb := TextureRect.new()
	var art := UiStyle.tex(str(lv.get("art", ""))) if lv.has("art") else null
	if art != null:
		thumb.texture = art
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# 没有画的关卡：天色 → 草色的渐变，叠几道起伏的山脊
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 0.6, 1.0])
		g.colors = PackedColorArray([lv["sky"], (lv["sky"] as Color).lerp(Color(0.85, 0.88, 0.9), 0.6),
				(lv["land"] as Color).lightened(0.15), lv["land"]])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0.0, 0.0)
		gt.fill_to = Vector2(0.0, 1.0)
		gt.width = 64
		gt.height = 64
		thumb.texture = gt
		thumb.stretch_mode = TextureRect.STRETCH_SCALE
		var hills := _Hills.new()
		hills.land = lv["land"]
		hills.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hills.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.add_child(hills)
	thumb.custom_minimum_size = Vector2(0.0, 178.0)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb)
	var rim := Panel.new()         # 画的边：一圈细墨线
	rim.add_theme_stylebox_override("panel", UiStyle.outline(Color(UiStyle.LINE, 0.7)))
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.offset_left = -3.0
	rim.offset_top = -3.0
	rim.offset_right = 3.0
	rim.offset_bottom = 3.0
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(rim)
	var seal := UiStyle.seal("境", 40.0)
	seal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	seal.position = Vector2(-52.0, -52.0)
	thumb.add_child(seal)
	var t := _label(String(lv["title"]), 44, UiStyle.TEXT_INK)
	t.add_theme_font_override("font", UiStyle.brush())
	box.add_child(t)
	var tag := _label(String(lv["tag"]), 18, UiStyle.CINNABAR)
	box.add_child(tag)
	box.add_child(UiStyle.rule(220.0, 6.0, Color(UiStyle.LINE, 0.7)))
	var d := _label(String(lv["desc"]), 18, UiStyle.TEXT_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(d)
	# 卡片的高度跟着内容走：说明文字折几行、字体行高多少，网页 / 手机和桌面不一样，写死会顶出纸面。
	# 直接拿字体量（自动换行的 Label 在排版之前报的最小高度不可信）。
	var df: Font = font if font != null else ThemeDB.fallback_font
	var text_w := b.custom_minimum_size.x - 60.0
	var dh := df.get_multiline_string_size(String(lv["desc"]), HORIZONTAL_ALIGNMENT_LEFT, text_w, 18).y
	dh += 3.0 * ceilf(dh / maxf(df.get_height(18), 1.0))      # Label 每行另加的行距
	# 上边距 30 + 画 178 + 题名 + 标签 + 一笔 6 + 说明 + 四道间距 + 下边距 30（卡片还没进场景树，Label 自己报的高度不准，都拿字体量）
	var need := 30.0 + 178.0 + UiStyle.brush().get_height(44) + df.get_height(18) + 6.0 + dh + 8.0 * 4.0 + 30.0
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, ceilf(need))
	return b


func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


## 缩略图上的几道山脊剪影
class _Hills:
	extends Control
	var land := Color(0.3, 0.5, 0.2)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for k in 3:
			var pts := PackedVector2Array()
			var base := h * (0.58 + 0.12 * k)
			var amp := h * (0.12 - 0.03 * k)
			for i in 33:
				var x := w * i / 32.0
				pts.append(Vector2(x, base - amp * (0.6 * sin(x * 0.021 + k * 1.7) + 0.4 * sin(x * 0.057 + k * 0.6))))
			pts.append(Vector2(w, h))
			pts.append(Vector2(0.0, h))
			var c := land.darkened(0.25 - 0.1 * k).lerp(Color(0.62, 0.7, 0.78), 0.45 - 0.2 * k)
			draw_colored_polygon(pts, c)
