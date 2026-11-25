extends Control
## 主城「元界面」的壳（2026-11-24 界面重做）：备战 / 商店 / 段位三张全屏页共用的底 —— 虚化压暗的场景、顶栏（返回 + 题头 + 灵石 / 仙玉）、
## 进场 / 换页 / 退场的动画、提示条、二次确认、图标飞过去的小动画、音效。三张页各是一个脚本（meta_prep.gd / meta_shop.gd / meta_rank.gd），
## 英雄是另一个全屏界面（hero_select_ui.gd，open_heroes() 盖在这上面）。
## 用户定的结构：英雄、备战（原来的「备战」+「仓库」合成一个：左边人物和身上的装备，右边背包 / 仓库）、商店、段位 —— 主城里四个独立入口，
## 所以这里没有页签；一次只开一页，返回就回主城。
## 老接口照 ex_lobby_ui.gd（level_select.gd 的 open_abode 现在 load 的是这个脚本，hub_hall.open_abode / 各自检照旧能用）：
##   signal closed / font / _set_tab(t) / _tab / tab_key() / _close()。_set_tab 认老编号（0 仓库 → 备战页翻到仓库、1 坊市 → 商店……见 LEGACY）、
##   也认页名（prep / stash / shop / trader / black / rank / hero）。暂停树、放鼠标由开它的人管（hud._open_abode）；自己开用 open(host, key)。
## 老的纸面板大厅 ex_lobby_ui.gd 还在：命令行带 --old-lobby（或它的自检 --lobby-test）时 level_select 仍然开它。
## 小样 / 自检：_tasks/ui_kit/meta_ui_test.gd。故意不写 class_name。

signal closed

const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SELF_PATH := "res://scripts/ex/meta_ui.gd"
const HERO_UI := "res://scripts/ex/hero_select_ui.gd"
const PAGES := {"prep": "res://scripts/ex/meta_prep.gd", "shop": "res://scripts/ex/meta_shop.gd", "rank": "res://scripts/ex/meta_rank.gd"}
## 每页的题头：[朱印上的字, 题目, 一句话]。2026-11-24 用户看过第一版：「现在有太多废话文字了，备战标题可以不要，
## 穿在身上的...不掉落，这些提示词也不用（商店也是一样）」—— 三页都不写题头了（全空 = 朱印 / 题目 / 那句话都不出），顶栏只剩返回和货币
const TITLES := {
	"prep": ["", "", ""],
	"shop": ["", "", ""],
	"rank": ["", "", ""],
}
## ex_lobby_ui.gd 的老编号 → [页, 页里翻到哪]（0 仓库 1 坊市 2 商人 3 备战 4 黑市 5 英雄 6 段位）
const LEGACY := [["prep", "stash"], ["shop", ""], ["shop", "sell"], ["prep", "bag"], ["shop", "black"], ["hero", ""], ["rank", ""]]
const BAR_H := 96.0              # 顶栏占多高（页的内容从它下面排起）
const MARGIN := 28.0
const BG_H := 216
const BG_PITCH := 7.0
const INK_BASE := Color(0.06, 0.055, 0.065)

var font: Font
var manage_pause := false        # 自己暂停树、放鼠标（open() 开的才管；level_select.open_abode 开的由 hud 管）
var page: Control                # 现在这一页
var _key := ""
var _tab := 3                    # 老编号（hub_hall 的自检读它）
var _sub := ""                   # 交给页的：翻到哪（stash / bag / sell / black）
var _closing := false
var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _hid_3d := false
var _bg_ready := false
var _hero_ui: Control

var _bg: TextureRect
var _ui: Control                 # 顶栏 + 页（画面窄时整块缩小）
var _host: Control               # 页挂在这下面
var _bar: Control
var _back: Button
var _seal_lab: Label
var _title: Label
var _subtitle: Label
var _money: HBoxContainer
var _rule: TextureRect            # 顶栏底下一道淡金线
var _ls: Label
var _xy: Label
var _ls_v := -1.0
var _xy_v := -1.0
var _toast: PanelContainer
var _toast_lab: Label
var _toast_n := 0
var _modal: Control
var _modal_yes: Button
var _fx: Control                 # 飞图标的那一层
var _snd: AudioStreamPlayer
var _t := 0.0


## 自己开一页（不经过 level_select）：挂到 host 下、暂停树放鼠标，关掉时恢复
static func open(host: Node, key: Variant = "prep") -> Control:
	var scr: GDScript = load(SELF_PATH)
	var ui: Control = scr.new()
	ui.set("manage_pause", true)
	host.add_child(ui)
	ui.call("_set_tab", key)
	return ui


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if font == null:
		font = UiStyle.kai()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 22
	theme = th
	if manage_pause:
		_was_paused = get_tree().paused
		_was_mouse = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_back()
	_build_bar()
	resized.connect(_layout)
	_layout()
	# 进场：整块淡入，顶栏从上面落下来
	modulate.a = 0.0
	MetaKit.tween(self).tween_property(self, "modulate:a", 1.0, 0.2)
	_bar.position.y = -40.0
	MetaKit.tween(_bar).tween_property(_bar, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_capture_bg()
	if _key == "":
		_set_tab("prep")
	else:
		_show_page()
	var note := ExProfile.take_notice()
	if note != "":
		toast(note, MetaKit.BAD)


func _exit_tree() -> void:
	_restore()


func _restore() -> void:
	if _hid_3d:
		_hid_3d = false
		var rv := get_viewport()
		if rv != null:
			rv.disable_3d = false
	if manage_pause:
		manage_pause = false
		var tree := get_tree()
		if tree != null:
			tree.paused = _was_paused
		Input.mouse_mode = _was_mouse


# ====================================================================
# 底：虚化的场景 + 暗角
# ====================================================================

func _cover(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	return r


func _build_back() -> void:
	var base := ColorRect.new()
	base.color = INK_BASE
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_bg = _cover(MetaKit.grad_tex([[0.0, Color(0.15, 0.16, 0.22)], [0.6, Color(0.3, 0.28, 0.34)], [1.0, Color(0.16, 0.15, 0.16)]], Vector2(0.5, 0.0), Vector2(0.5, 1.0)))
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# 整体压暗一层（东西是直接浮在场景上的，底要沉下去），四周再暗一圈
	var ink := Color(0.04, 0.035, 0.04)
	var dim := ColorRect.new()
	dim.color = Color(ink, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_cover(MetaKit.grad_tex([[0.0, Color(ink, 0.7)], [0.2, Color(ink, 0.1)], [0.75, Color(ink, 0.1)], [1.0, Color(ink, 0.75)]], Vector2(0.5, 0.0), Vector2(0.5, 1.0)))
	_cover(MetaKit.grad_tex([[0.0, Color(ink, 0.0)], [0.55, Color(ink, 0.0)], [1.0, Color(ink, 0.6)]], Vector2(0.5, 0.5), Vector2(1.0, 0.95), true))


## 拍一张当前场景糊开当背景，拍完把主视口的 3D 关掉（做法同 hero_select_ui.gd）
func _capture_bg() -> void:
	var rv := get_viewport()
	var cam := rv.get_camera_3d() if rv != null else null
	if cam == null or rv.disable_3d:
		_bg_ready = true
		return
	var vs := size
	var w := clampi(int(roundf(float(BG_H) * vs.x / maxf(vs.y, 1.0))), 64, 1024)
	var sv := SubViewport.new()
	sv.size = Vector2i(w, BG_H)
	sv.world_3d = rv.find_world_3d()
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var c := Camera3D.new()
	c.fov = cam.fov
	c.near = cam.near
	c.far = cam.far
	c.environment = cam.environment
	c.attributes = cam.attributes
	c.cull_mask = cam.cull_mask
	sv.add_child(c)
	var xf := cam.global_transform
	var fwd := -xf.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.FORWARD
	xf.basis = Basis(Vector3.UP, atan2(-flat.x, -flat.z)) * Basis(Vector3.RIGHT, deg_to_rad(BG_PITCH))
	var scene := get_tree().current_scene
	var pv: Variant = scene.get("player") if scene != null else null
	if is_instance_valid(pv) and pv is Node3D:
		xf.origin = (pv as Node3D).global_position + Vector3(0.0, 3.2, 0.0) + flat * 1.2
	c.global_transform = xf
	c.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(sv) or _closing or not is_inside_tree():
		return
	var img := sv.get_texture().get_image()
	sv.queue_free()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		img.shrink_x2()
		img.shrink_x2()
		img.resize(w, BG_H, Image.INTERPOLATE_CUBIC)
		_bg.texture = ImageTexture.create_from_image(img)
	_bg_ready = true
	if rv != null and not rv.disable_3d:
		rv.disable_3d = true
		_hid_3d = true


# ====================================================================
# 顶栏
# ====================================================================

func _build_bar() -> void:
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_host)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bar)
	_back = MetaKit.round_button("meta_icon_back", 68.0)
	_back.pressed.connect(func() -> void:
		click()
		_close())
	_bar.add_child(_back)
	var seal := UiStyle.seal("", 50.0)
	_seal_lab = seal.get_child(0) as Label
	seal.name = "Seal"
	_bar.add_child(seal)
	_title = MetaKit.outlined(MetaKit.label("", 44, MetaKit.TEXT, true))
	_bar.add_child(_title)
	_subtitle = MetaKit.outlined(MetaKit.label("", 21, Color(MetaKit.TEXT, 0.72)), 5)
	_bar.add_child(_subtitle)
	_rule = MetaKit.rule(600.0, Color(MetaKit.GOLD, 0.38))
	_bar.add_child(_rule)
	_money = HBoxContainer.new()
	_money.add_theme_constant_override("separation", 12)
	_money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_money)
	var m1 := MetaKit.money("lingshi", MetaKit.GOLD)
	_money.add_child(m1[0])
	_ls = m1[1]
	var m2 := MetaKit.money("ex_jade", MetaKit.JADE)
	_money.add_child(m2[0])
	_xy = m2[1]
	# 提示条、飞图标层、二次确认都压在页上面
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fx)
	_toast = PanelContainer.new()
	var ts := MetaKit.box(Color(0.07, 0.065, 0.08, 0.92), Color(MetaKit.GOLD, 0.5), 1.5, 22.0, 8.0).duplicate() as StyleBoxFlat
	ts.content_margin_left = 26.0
	ts.content_margin_right = 26.0
	ts.content_margin_top = 9.0
	ts.content_margin_bottom = 9.0
	_toast.add_theme_stylebox_override("panel", ts)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_lab = MetaKit.label("", 24)
	_toast.add_child(_toast_lab)
	_ui.add_child(_toast)
	_snd = AudioStreamPlayer.new()
	add_child(_snd)
	refresh_money(false)


## 界面自己的坐标里画面多大（画面窄于 1500 时整块缩小，这个数就比画面大）
func ui_size() -> Vector2:
	var k := _ui.scale.x if _ui != null else 1.0
	return size / maxf(k, 0.01)


func _layout() -> void:
	var vs := size
	if vs.x < 10.0 or vs.y < 10.0 or _ui == null:
		return
	var k := minf(1.0, minf(vs.x / 1500.0, vs.y / 820.0))
	_ui.scale = Vector2(k, k)
	var us := vs / k
	_ui.size = us
	_host.size = us
	_fx.size = us
	_back.position = Vector2(MARGIN, 14.0)
	var seal := _bar.get_node("Seal") as Control
	seal.position = Vector2(MARGIN + 68.0 + 20.0, 23.0)
	_title.position = Vector2(seal.position.x + 62.0, 14.0)
	_title.size = _title.get_minimum_size()
	_subtitle.position = Vector2(_title.position.x + _title.size.x + 18.0, 14.0 + (_title.size.y - _subtitle.get_minimum_size().y) * 0.5 + 4.0)
	_money.size = _money.get_combined_minimum_size()
	_money.position = Vector2(us.x - MARGIN - _money.size.x, 22.0)
	_rule.size = Vector2(us.x - MARGIN * 2.0, 12.0)
	_rule.position = Vector2(MARGIN, BAR_H - 12.0)
	if _bg != null:
		_bg.pivot_offset = vs * 0.5
	if is_instance_valid(page) and page.has_method("layout"):
		page.size = us
		page.call("layout", us)


func _process(dt: float) -> void:
	_t += dt
	if _bg != null:
		var z := 1.08 + 0.012 * sin(_t * 0.3)
		_bg.scale = Vector2(z, z)


## 灵石 / 仙玉换成存档里的数（animate = 数字滚过去）
func refresh_money(animate := true) -> void:
	var ls := float(ExProfile.lingshi())
	var xy := float(ExProfile.xianyu())
	if animate and _ls_v >= 0.0 and not is_equal_approx(ls, _ls_v):
		MetaKit.roll(_ls, _ls_v, ls, func(v: float) -> String: return NumFmt.fmt(v))
	else:
		_ls.text = NumFmt.fmt(ls)
	if animate and _xy_v >= 0.0 and not is_equal_approx(xy, _xy_v):
		MetaKit.roll(_xy, _xy_v, xy, func(v: float) -> String: return str(int(roundf(v))))
	else:
		_xy.text = str(int(xy))
	_ls_v = ls
	_xy_v = xy
	if is_inside_tree():
		_relayout_money.call_deferred()


func _relayout_money() -> void:
	if _money == null:
		return
	_money.size = _money.get_combined_minimum_size()
	_money.position.x = ui_size().x - MARGIN - _money.size.x


# ====================================================================
# 换页 / 开关
# ====================================================================

## t：老编号（见 LEGACY）或页名（prep / stash / bag / shop / trader / sell / black / rank / hero）
func _set_tab(t: Variant) -> void:
	var key := "prep"
	var sub := ""
	if t is int or t is float:
		var i := clampi(int(t), 0, LEGACY.size() - 1)
		key = str(LEGACY[i][0])
		sub = str(LEGACY[i][1])
		_tab = i
	else:
		match str(t):
			"stash", "仓库":
				key = "prep"
				sub = "stash"
				_tab = 0
			"prep", "bag", "备战":
				key = "prep"
				sub = "bag"
				_tab = 3
			"shop", "坊市", "商店":
				key = "shop"
				_tab = 1
			"trader", "sell", "商人":
				key = "shop"
				sub = "sell"
				_tab = 2
			"black", "黑市":
				key = "shop"
				sub = "black"
				_tab = 4
			"rank", "段位":
				key = "rank"
				_tab = 6
			"hero", "英雄":
				key = "hero"
				_tab = 5
	if key == "hero":
		if _key == "":
			_key = "prep"
			_sub = "bag"
		if is_inside_tree():
			if not is_instance_valid(page):
				_show_page()
			open_heroes()
		return
	var same := key == _key and is_instance_valid(page)
	_key = key
	_sub = sub
	if not is_inside_tree():
		return          # 还没进树：_ready 里再建页
	if same:
		if sub != "" and page.has_method("goto"):
			page.call("goto", sub)
		return
	_show_page()


## 现在在哪一页（prep / shop / rank）
func tab_key() -> String:
	return _key


func _show_page() -> void:
	var old := page
	if is_instance_valid(old):
		# 旧页往左淡出去
		var t := MetaKit.tween(old)
		t.set_parallel(true)
		t.tween_property(old, "modulate:a", 0.0, 0.14)
		t.tween_property(old, "position:x", old.position.x - 60.0, 0.14)
		t.chain().tween_callback(old.queue_free)
	var info: Array = TITLES.get(_key, ["", "", ""])
	_seal_lab.text = str(info[0])
	_title.text = str(info[1])
	_subtitle.text = str(info[2])
	(_bar.get_node("Seal") as CanvasItem).visible = str(info[0]) != ""
	_title.visible = str(info[1]) != ""
	_subtitle.visible = str(info[2]) != ""
	var scr: GDScript = load(str(PAGES[_key]))
	page = scr.new()
	page.set("shell", self)
	page.set("start", _sub)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(page)
	_layout()
	if page.has_method("enter"):
		page.call("enter")


func _close() -> void:
	if _closing:
		return
	_closing = true
	# 退场：整块很快淡掉。淡完才发 closed（开它的人在那时解除暂停）
	var t := MetaKit.tween(self)
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.tween_callback(func() -> void:
		_restore()
		closed.emit()
		queue_free())


func close() -> void:
	_close()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if is_instance_valid(_modal):
			_modal.queue_free()
		else:
			_close()
		get_viewport().set_input_as_handled()


## 开全屏的英雄选择界面，盖在这上面；它关掉后页刷新一下（英雄换了，备战页的人要跟着换）
func open_heroes() -> void:
	if is_instance_valid(_hero_ui) or get_parent() == null or not ResourceLoader.exists(HERO_UI):
		return
	var ui: Control = (load(HERO_UI) as GDScript).call("open", get_parent(), false)
	_hero_ui = ui
	visible = false
	set_process_unhandled_input(false)
	tree_exiting.connect(ui.queue_free)
	ui.connect("closed", func() -> void:
		if _hero_ui == ui:
			_hero_ui = null
		visible = true
		set_process_unhandled_input(true)
		modulate.a = 0.0
		MetaKit.tween(self).tween_property(self, "modulate:a", 1.0, 0.18)
		if is_instance_valid(page) and page.has_method("refresh"):
			page.call("refresh"))


# ====================================================================
# 页用得上的几样
# ====================================================================

## 顶上正中滑下来一条提示，两秒后收走
func toast(text: String, col := MetaKit.TEXT) -> void:
	_toast_n += 1
	var n := _toast_n
	_toast_lab.text = text
	_toast_lab.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast.size = _toast.get_combined_minimum_size()
	var us := ui_size()
	_toast.position = Vector2((us.x - _toast.size.x) * 0.5, -10.0)
	_toast.modulate.a = 0.0
	var t := MetaKit.tween(_toast)
	t.set_parallel(true)
	t.tween_property(_toast, "modulate:a", 1.0, 0.16)
	t.tween_property(_toast, "position:y", 22.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(2.0)
	t.chain().tween_callback(func() -> void:
		if n == _toast_n:
			MetaKit.tween(_toast).tween_property(_toast, "modulate:a", 0.0, 0.25)
			MetaKit.tween(_subtitle).tween_property(_subtitle, "modulate:a", 1.0, 0.25))
	# 提示条出来时题头那句小字先让开（两样叠在顶栏正中）
	MetaKit.tween(_subtitle).tween_property(_subtitle, "modulate:a", 0.0, 0.12)


func ok(text: String) -> void:
	toast(text, MetaKit.JADE)


func warn(text: String) -> void:
	toast(text, MetaKit.BAD)
	sfx("block", -14.0)


## 二次确认：正中一张墨玉片，text 一句话，yes 按钮上的字，点了调 on_yes
func confirm(text: String, yes: String, on_yes: Callable) -> void:
	if is_instance_valid(_modal):
		_modal.queue_free()
	var us := ui_size()
	_modal = Control.new()
	_modal.size = us
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.62)
	dim.size = us
	_modal.add_child(dim)
	var card := PanelContainer.new()
	var s := MetaKit.glass(18.0, 0.55, Color(0.085, 0.08, 0.095, 0.97)).duplicate() as StyleBoxFlat
	s.set_content_margin_all(30.0)
	card.add_theme_stylebox_override("panel", s)
	_modal.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	card.add_child(v)
	var l := MetaKit.para(text, 26, 560.0, MetaKit.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	v.add_child(MetaKit.divider(560.0))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	v.add_child(row)
	var no := MetaKit.button("再想想", 210.0, 66.0, "ghost")
	var m := _modal
	no.pressed.connect(func() -> void:
		click()
		m.queue_free())
	row.add_child(no)
	var yb := MetaKit.button(yes, 250.0, 66.0, "primary")
	yb.pressed.connect(func() -> void:
		m.queue_free()
		on_yes.call())
	row.add_child(yb)
	_modal_yes = yb
	card.size = card.get_combined_minimum_size()
	card.position = ((us - card.size) * 0.5).floor()
	MetaKit.fade_in(dim, 0.0, 0.12)
	MetaKit.pop(card, 0.9)
	MetaKit.fade_in(card, 0.0, 0.12)


## 自检用：确认框开着就点「确认」那颗，返回点到没有
func press_confirm() -> bool:
	if not is_instance_valid(_modal) or _modal.is_queued_for_deletion() or not is_instance_valid(_modal_yes):
		return false
	_modal_yes.pressed.emit()
	return true


func modal_open() -> bool:
	return is_instance_valid(_modal) and not _modal.is_queued_for_deletion()


## 一张图标从 from 飞到 to（都是画面上的位置），到了调 done（穿戴 / 买到手的那一下）
func fly(tex: Texture2D, from: Vector2, to: Vector2, done := Callable(), s0 := 76.0, s1 := 40.0) -> void:
	if tex == null:
		if done.is_valid():
			done.call()
		return
	var inv := _ui.get_global_transform().affine_inverse()
	var a := inv * from
	var b := inv * to
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = Vector2(s0, s0)
	r.position = a - r.size * 0.5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(r)
	var t := MetaKit.tween(r)
	t.set_parallel(true)
	t.tween_property(r, "position", b - Vector2(s1, s1) * 0.5, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(r, "size", Vector2(s1, s1), 0.3)
	t.tween_property(r, "modulate:a", 0.25, 0.3).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func() -> void:
		r.queue_free()
		if done.is_valid():
			done.call())


## 界面开着时树是暂停的，音效池（sfx.gd）里的播放器不走：用自己这一个
func sfx(snd: String, db := -8.0, pitch := 1.0) -> void:
	var st := Sfx.gen_stream(snd)
	if st == null or _snd == null:
		return
	_snd.stream = st
	_snd.volume_db = db + float(Sfx.GAIN.get(snd, 0.0))
	_snd.pitch_scale = pitch
	_snd.play()


func click(pitch := 1.0) -> void:
	sfx("ui_click", -8.0, pitch)
