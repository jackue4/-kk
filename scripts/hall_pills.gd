extends CanvasLayer
## 大厅里的「一键服丹」（2026-11-20 用户要求：这个按钮只在大厅出现、放在屏幕底部）。
## 吃的是洞府仓库里涨修为的丹（raid_profile.gd 的 stash；只回气血的回春丹不吃），一颗颗来：每 EAT_GAP 秒服一颗，
## 每颗在主角头上单独飘一个「修为 +N」，吃几颗飘几个，不合成一个总数；升了小境界另飘一行「修为精进」。
## 修为（境界内的小等级 + 经验）存在存档里，进大世界接着用（raid_manager.gd 开局读 Profile.cult）。
## 到了大境界的瓶颈就停：剩下的丹留在仓库，提示去修炼场渡劫。
## 底部一条：左边「修为 Lv.x」+ 一道修为条，右边按钮「一键服丹 ×N」（仓库里没有修为丹就整条藏起来）；键盘 H 同样。
## 只在大厅显示（main.gd 的 level 为空、择境 / 洞府界面没开）。
## 2026-11-20 数值框架：药力服的时候按 Prog.eat_pill 现算（丹毒越重药效越低；在修炼场打坐时服 ×1.3），飘字写实际涨的修为；
##   丹不再一次性搬出仓库排队——每服一颗才从仓库拿走一颗、立刻存档（服到一半关游戏不丢丹）；离开大厅就停。
##   挑丹的顺序：先挑放得进「离瓶颈还差多少」的最大一颗（药效最高时服大丹）；都放不进就服最小的那颗补满，大丹留给下个境界。
##   到瓶颈提示去修炼场渡劫；渡劫 / 结婴演出时整条藏起来。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Prog := preload("res://scripts/progression.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Tribulation := preload("res://scripts/tribulation.gd")
const YuanCine := preload("res://scripts/yuanying_cine.gd")

const EAT_GAP := 0.3

var main: Node                  # main.gd（看 level / level_ui 判断是不是在大厅）
var player: Node3D
var font: Font
var touch := false

var _bar: PanelContainer
var _lab: Label
var _exp_bg: Panel
var _exp: ColorRect
var _btn: Button
var _eating := false            # 一键服丹进行中（丹还在仓库里，服一颗拿一颗）
var _t := 0.0
var _float_n := 0


func _ready() -> void:
	layer = 11
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiStyle.plaque(0.96, 1, 8.0))
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	_bar.theme = th
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_bar.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	_lab = Label.new()
	_lab.add_theme_font_size_override("font_size", 19)
	_lab.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	info.add_child(_lab)
	_exp_bg = Panel.new()
	_exp_bg.add_theme_stylebox_override("panel", UiStyle.bar_frame())
	_exp_bg.custom_minimum_size = Vector2(180, 7)
	info.add_child(_exp_bg)
	_exp = ColorRect.new()
	_exp.color = UiStyle.QING
	_exp.size = Vector2(0, 7)
	_exp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exp_bg.add_child(_exp)
	_btn = Button.new()
	_btn.icon = UiStyle.icon("pill")
	_btn.expand_icon = true
	_btn.add_theme_constant_override("icon_max_width", 34)
	_btn.custom_minimum_size = Vector2(220, 56)
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 22)
	UiStyle.style_primary(_btn)
	_btn.pressed.connect(eat_all)
	row.add_child(_btn)
	if not InputMap.has_action("eat_all"):
		InputMap.add_action("eat_all")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_H
		InputMap.action_add_event("eat_all", ev)


func in_hall() -> bool:
	if main == null or main.get("level") != null:
		return false
	var ui: Variant = main.get("level_ui")
	return ui == null or not bool(ui.is_open())


## 仓库里能一键服下的丹（2026-11-20 数值框架：用 Items.is_xp_pill 认，回春丹不算）
func count() -> int:
	var n := 0
	for it: Dictionary in Profile.stash():
		if Items.is_xp_pill(it):
			n += 1
	return n


## 2026-11-20 数值框架：修为按存档里的境界算（和 Prog 一致），不看主角身上的 realm_idx（GM 换境界时两者会不一样）
func _realm() -> int:
	return Profile.realm()


## 有雷劫 / 结婴演出在播：整条藏起来、不服丹
func _busy() -> bool:
	return Tribulation.running or YuanCine.playing != null


## 主城修炼场里正在打坐（这时服丹算炼化，药力 ×Prog.MED_PILL）
func _meditating() -> bool:
	var hub: Variant = main.get("hub") if main != null else null
	return is_instance_valid(hub) and bool(hub.get("meditating"))


## 离这一境界的瓶颈还差多少修为（大乘没有瓶颈，按 99 级封顶算）
func _room() -> float:
	var r := _realm()
	var cu := Profile.cult(r)
	var lv := int(cu[0])
	var s := -float(cu[1])
	for l in range(lv, Prog.top_lv(r) + 1):
		s += Prog.xp_need(l)
	return maxf(s, 0.0)


## 下一颗服哪颗（仓库里的下标，没有返回 -1）：放得进剩余修为的最大一颗；都放不进就挑最小的（补满瓶颈，浪费最少）
func _pick() -> int:
	var s := Profile.stash()
	var eff := Prog.pill_eff(Prog.tox()) * (Prog.MED_PILL if _meditating() else 1.0)
	var room := _room()
	var fit := -1
	var fit_v := -1.0
	var small := -1
	var small_v := INF
	for i in s.size():
		var it: Dictionary = s[i]
		if not Items.is_xp_pill(it):
			continue
		var g := Items.pill_exp_now(it) * eff
		if g <= room and g > fit_v:
			fit = i
			fit_v = g
		if g < small_v:
			small = i
			small_v = g
	return fit if fit >= 0 else small


func eat_all() -> void:
	if not in_hall() or _busy() or _eating or count() == 0:
		return
	if Prog.profile_at_cap():
		_float("修为已至瓶颈 · 去修炼场渡劫", Color(1.0, 0.7, 0.45))
		return
	_eating = true
	_t = 0.0


## 服一颗（已经从仓库里拿出来了）：Prog.eat_pill 按丹毒折算药力、丹毒 +1，主角头上飘实际涨的数
func _eat_one(it: Dictionary) -> void:
	var r: Dictionary = Prog.eat_pill(Items.pill_exp_now(it), _meditating())
	Profile.save()
	var got := float(r["used"])
	var eff := float(r["eff"])
	var txt := "修为 +%s" % Prog.short_num(got)
	if eff < 0.8:
		txt += "　丹毒 药效 %d%%" % roundi(eff * 100.0)
	_float(txt, Color(0.55, 1.0, 0.8) if eff >= 0.8 else Color(0.85, 0.95, 0.6))
	Vfx.breakthrough(player.global_position, Data.TIER_COLORS[clampi(int(it.get("tier", 0)), 0, 4)], 0.25)
	Sfx.play("ascend", -12.0, 1.4 + 0.05 * float(_float_n % 6))
	if int(r["ups"]) > 0:
		_float("修为精进 Lv.%d" % int(r["lv"]), Color(1.0, 0.86, 0.45), 0.7)      # 抬高一截，不和同一刻的「修为 +N」叠在一起


## 主角头上飘一行字：匀速往上走（1.5 m/s），连着飘的左右稍微错开，排成一列不叠在一起
func _float(text: String, col: Color, up := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font
	l.font_size = 46
	l.pixel_size = 0.0075
	l.outline_size = 12
	l.modulate = col
	l.outline_modulate = Color(0.06, 0.06, 0.08, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	player.get_parent().add_child(l)
	var k := _float_n % 2
	_float_n += 1
	var cam := player.get_viewport().get_camera_3d()
	var side := cam.global_basis.x if cam != null else Vector3.RIGHT
	l.global_position = player.global_position + Vector3.UP * (2.6 + up) + side * (0.0 if up > 0.0 else (0.3 if k == 1 else -0.3) + randf_range(-0.06, 0.06))
	l.scale = Vector3.ONE * 0.5
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.8, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("eat_all") and _bar.visible:
		eat_all()


func _process(dt: float) -> void:
	# 一颗颗服：每次从仓库里挑一颗拿出来服掉（没服的一直在仓库里）；离开大厅、有演出、到瓶颈、服完就停
	if _eating:
		if not in_hall() or _busy():
			_eating = false
		else:
			_t -= dt
			if _t <= 0.0:
				_t = EAT_GAP
				if Prog.profile_at_cap():
					_eating = false
					_float("修为已至瓶颈 · 余下的丹留在洞府，去修炼场渡劫", Color(1.0, 0.7, 0.45))
				else:
					var i := _pick()
					if i < 0:
						_eating = false
					else:
						var s := Profile.stash()
						var it: Dictionary = s[i]
						s.remove_at(i)
						_eat_one(it)
	var n := count()
	var show := in_hall() and not _busy() and (n > 0 or _eating)
	_bar.visible = show
	if not show:
		return
	var cu2 := Profile.cult(_realm())
	var lv := int(cu2[0])
	_lab.text = "%s期 · 修为 Lv.%d" % [Realm.LIST[_realm()]["name"], lv]
	# 丹毒没消干净时补一句药效（短，手机一行放得下）
	var eff := roundi(Prog.pill_eff(Prog.tox()) * 100.0)
	if eff < 100:
		_lab.text += "　药效 %d%%" % eff
	var cap := Prog.profile_at_cap()
	_exp.size.x = 180.0 * clampf(float(cu2[1]) / maxf(Prog.xp_need(lv), 1.0), 0.0, 1.0)
	_exp.color = UiStyle.CINNABAR if cap else UiStyle.QING
	_btn.text = ("服丹中… 余 %d" % n) if _eating else (("一键服丹 ×%d" % n) + ("" if touch else "　H"))
	_btn.disabled = _eating
	var vs := get_viewport().get_visible_rect().size
	_bar.reset_size()
	_bar.position = Vector2(roundf((vs.x - _bar.size.x) * 0.5), roundf(vs.y - 14.0 - _bar.size.y))
