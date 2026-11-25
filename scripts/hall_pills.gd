extends CanvasLayer
## 大厅里的「一键服丹」（2026-11-20 用户要求：这个按钮只在大厅出现、放在屏幕底部）。
## 吃的是洞府仓库里涨修为的丹（raid_profile.gd 的 stash；只回气血的回春丹不吃），一颗颗来：每 EAT_GAP 秒服一颗，
## 每颗在主角头上单独飘一个「修为 +N」，吃几颗飘几个，不合成一个总数；升了小境界另飘一行「修为精进」。
## 修为（境界内的小等级 + 经验）存在存档里，进大世界接着用（raid_manager.gd 开局读 Profile.cult）。
## 到了大境界的瓶颈就停：剩下的丹留在仓库，提示去修炼场渡劫。
## 底部一条：左边「修为 Lv.x」+ 一道修为条，右边按钮「一键服丹 ×N」（仓库里没有修为丹时也显示，写「暂无丹药」、按了提示去哪找）；键盘 H 同样。
## 只在大厅显示（main.gd 的 level 为空、择境 / 洞府界面没开）。
## 2026-11-20 数值框架：药力服的时候按 Prog.eat_pill 现算（丹毒越重药效越低；在修炼场打坐时服 ×1.3），飘字写实际涨的修为；
##   丹不再一次性搬出仓库排队——每服一颗才从仓库拿走一颗、立刻存档（服到一半关游戏不丢丹）；离开大厅就停。
##   挑丹的顺序：先挑放得进「离瓶颈还差多少」的最大一颗（药效最高时服大丹）；都放不进就服最小的那颗补满，大丹留给下个境界。
##   到瓶颈提示去修炼场渡劫；渡劫 / 结婴演出时整条藏起来。
## 2026-11-23 数值重构（照 Hammer 的精魄 / 霸主精魄）：
##   · 只吃「能服」的丹（Prog.pill_use_err：本境丹要正处在那一境界、霸主精魄要境界够），按钮上的数也只数能服的；
##   · 从大到小一摞一摞地吃（同名同境同品质的一次吃完，每摞一个飘字），比以前一颗颗快得多；
##   · 瓶颈时照样能吃（修为照收、突破时结转），存到结转上限（add_xp 用掉 0）就停、那颗不扣，提示「修为已满，先去渡劫」；
##   · 没有丹毒 / 药效了；升了级在头上飘一行「战力 A → B」（0.6 秒内的合成一次）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Prog := preload("res://scripts/progression.gd")
const UiStyle := preload("res://scripts/ink_style.gd")      # 2026-11-24 界面重做：换成墨玉样式（接口同 ui_style.gd，见那个文件头）
const Sfx := preload("res://scripts/sfx.gd")
const Tribulation := preload("res://scripts/tribulation.gd")
const YuanCine := preload("res://scripts/yuanying_cine.gd")
const CS := preload("res://scripts/combat_stats.gd")      # 战力（升级后飘「战力 A → B」）

const EAT_GAP := 0.16           # 2026-11-23：每次吃一摞，间隔也缩短（原来一颗 0.3 秒）
const PW_MERGE := 0.6           # 这么久之内的战力变化合成一行

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
var _pw_from := -1.0            # 这一串升级之前的战力（< 0 = 没有待飘的）
var _pw_t := 0.0


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
	# 2026-11-24 用户：擂台对战时不要这个按钮（入场倒数 / 对决 / 结算都算；匹配等人的那十秒还在大厅里，照常显示）
	var hub: Variant = main.get("hub")
	if is_instance_valid(hub) and hub.has_method("duel_busy") and bool(hub.call("duel_busy")):
		return false
	var ui: Variant = main.get("level_ui")
	return ui == null or not bool(ui.is_open())


## 仓库里能一键服下的丹（2026-11-20 数值框架：用 Items.is_xp_pill 认，回春丹不算；2026-11-23 起只数现在的境界能服的）
func count() -> int:
	var n := 0
	var r := _realm()
	for it: Dictionary in Profile.stash():
		if _edible(it, r):
			n += 1
	return n


## 仓库里境界不符、现在服不了的修为丹有几颗
func count_locked() -> int:
	var n := 0
	var r := _realm()
	for it: Dictionary in Profile.stash():
		if Items.is_xp_pill(it) and Prog.pill_use_err(it, r) != "":
			n += 1
	return n


func _edible(it: Dictionary, realm: int) -> bool:
	return Items.is_xp_pill(it) and Prog.pill_use_err(it, realm) == ""


## 同一摞：名字、境界、霸主门槛、品质都一样（和仓库叠格 raid_profile.stacks / abode_ui._stack_key 一个口径）
static func _stack_key(it: Dictionary) -> String:
	return "%s|%d|%d|%d" % [str(it.get("name", "")), int(it.get("realm", -1)), int(it.get("min_realm", -1)), int(it.get("grade", -1))]


## 2026-11-20 数值框架：修为按存档里的境界算（和 Prog 一致），不看主角身上的 realm_idx（GM 换境界时两者会不一样）
func _realm() -> int:
	return Profile.realm()


## 有雷劫 / 结婴演出在播：整条藏起来、不服丹
func _busy() -> bool:
	return Tribulation.running or YuanCine.playing != null


## 主城修炼场里正在打坐（2026-11-23 起打坐时服丹不再加成，Prog.MED_PILL = 1；参数留着）
func _meditating() -> bool:
	var hub: Variant = main.get("hub") if main != null else null
	return is_instance_valid(hub) and bool(hub.get("meditating"))


## 修为已经存到结转上限（瓶颈那一级 + 一整个下一境界）：再服也加不进去
func _full() -> bool:
	var r := _realm()
	if r >= Prog.REALMS - 1:
		return false
	var cu := Profile.cult(r)
	return int(cu[0]) >= Prog.top_lv(r) and float(cu[1]) >= Prog.overflow_cap(r) - 0.5


## 下一摞服哪颗（仓库里的下标，没有返回 -1）：照 Hammer 从大到小吃——能服的丹里药力最大的那一颗
func _pick() -> int:
	var s := Profile.stash()
	var r := _realm()
	var best := -1
	var best_v := -1.0
	for i in s.size():
		var it: Dictionary = s[i]
		if not _edible(it, r):
			continue
		var g := Items.pill_exp_now(it, r)
		if g > best_v:
			best = i
			best_v = g
	return best


func _pw_now() -> float:
	var r := _realm()
	return CS.power(r, int(Profile.cult(r)[0]), Items.fx_total(Profile.gear()))


func eat_all() -> void:
	if not in_hall() or _busy() or _eating:
		return
	if count() == 0:
		var nl := count_locked()
		if nl > 0:
			_float("仓库里 %d 颗丹境界不符 · 本境丹要正处在那一境界才可服用" % nl, Color(1.0, 0.8, 0.55))
		else:
			_float("洞府里没有修为丹 · 坊市 / 丹房 / 禁地里找", Color(1.0, 0.8, 0.55))
		return
	if _full():
		_float("修为已满，先去渡劫", Color(1.0, 0.7, 0.45))
		return
	_eating = true
	_t = 0.0


## 服一摞（同名同境同品质的一次吃完）：每颗都按 Prog.eat_pill 加修为、服一颗从仓库拿走一颗；
## 加不进去（used == 0，结转存满了）就停，那颗留在仓库。返回 false = 存满了、该停了
## 2026-11-25：存档那一半挪进静态的 eat_stack（备战页的「服下」也调它，吃丹规矩只有这一份）
func _eat_stack(i0: int) -> bool:
	var s := Profile.stash()
	var tier := clampi(int((s[i0] as Dictionary).get("tier", 0)), 0, 4)
	var lv0 := int(Profile.cult(_realm())[0])
	var pw0 := _pw_now() if _pw_from < 0.0 else _pw_from
	var res := eat_stack(i0, -1, _meditating())
	var n := int(res["n"])
	if int(res["ups"]) > 0:
		_pw_from = pw0
		_pw_t = PW_MERGE
	if n > 0:
		_float(("修为 +%s" % Prog.short_num(float(res["got"]))) + ("　×%d" % n if n > 1 else ""), Color(0.55, 1.0, 0.8))
		Vfx.breakthrough(player.global_position, Data.TIER_COLORS[tier], 0.25)
		Sfx.play("ascend", -12.0, 1.4 + 0.05 * float(_float_n % 6))
	if int(res["ups"]) > 0 and int(res["lv"]) > lv0:
		_float("修为精进 Lv.%d" % int(res["lv"]), Color(1.0, 0.86, 0.45), 0.7)      # 抬高一截，不和同一刻的「修为 +N」叠在一起
	return not bool(res["full"])


## 服仓库第 i0 件所在的那一摞（同名同境同品质），最多 max_n 颗（-1 = 整摞）。纯存档逻辑、不飘字：
## 一键服丹（上面的 _eat_stack）和备战页的「服下」（scripts/ex/meta_prep.gd）共用这一份，丹的规矩不会分叉。
## 返回 {n 服了几颗, got 涨了多少修为, ups 升了几个小等级, lv 现在的等级, full 结转存满了（那颗没扣）, err 服不了的原因（"" = 能服）}
static func eat_stack(i0: int, max_n := -1, meditating := false) -> Dictionary:
	var out := {"n": 0, "got": 0.0, "ups": 0, "lv": 0, "full": false, "err": ""}
	var s := Profile.stash()
	if i0 < 0 or i0 >= s.size():
		out["err"] = "仓库里没有这件"
		return out
	if Profile.in_raid():
		out["err"] = Profile.RAID_LOCK
		return out
	var r0 := Profile.realm()
	var first: Dictionary = s[i0]
	if not Items.is_xp_pill(first):
		out["err"] = "这不是修为丹"
		return out
	var e := Prog.pill_use_err(first, r0)
	if e != "":
		out["err"] = e
		return out
	var key := _stack_key(first)
	var i := i0
	while i < s.size() and (max_n < 0 or int(out["n"]) < max_n):
		var it: Dictionary = s[i]
		if _stack_key(it) != key or not (Items.is_xp_pill(it) and Prog.pill_use_err(it, r0) == ""):
			i += 1
			continue
		var res: Dictionary = Prog.eat_pill(Items.pill_exp_now(it, r0), meditating)
		var used := float(res["used"])
		if used <= 0.0:
			out["full"] = true      # 结转存满：这颗不扣
			break
		s.remove_at(i)
		out["got"] = float(out["got"]) + used
		out["n"] = int(out["n"]) + 1
		if int(res["ups"]) > 0:
			out["ups"] = int(out["ups"]) + int(res["ups"])
			out["lv"] = int(res["lv"])
	if int(out["n"]) > 0:
		Profile.save()
	elif bool(out["full"]):
		out["err"] = "修为已满，先去渡劫"
	return out


## 战力变化（照 Hammer 的战力面板：一串变化合成一次）：升级停下 PW_MERGE 秒后飘「战力 A → B」
func _tick_power(dt: float) -> void:
	if _pw_from < 0.0:
		return
	_pw_t -= dt
	if _pw_t > 0.0:
		return
	var now := _pw_now()
	if now > _pw_from + 0.5:
		_float("战力 %s → %s" % [Prog.short_num(_pw_from), Prog.short_num(now)], Color(1.0, 0.62, 0.45), 1.4)
	_pw_from = -1.0


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
	# 一摞摞服：每次挑能服的最大那一摞吃完（没服的一直在仓库里）；离开大厅、有演出、结转存满、服完就停（瓶颈时照样吃，修为结转）
	if _eating:
		if not in_hall() or _busy():
			_eating = false
		else:
			_t -= dt
			if _t <= 0.0:
				_t = EAT_GAP
				var i := _pick()
				if i < 0:
					_eating = false
					if Prog.profile_at_cap():
						_float("修为已至瓶颈 · 去修炼场渡劫，多出的修为突破后结转", Color(1.0, 0.7, 0.45))
				elif not _eat_stack(i):
					_eating = false
					_float("修为已满，先去渡劫", Color(1.0, 0.7, 0.45))
	_tick_power(dt)
	var n := count()
	# 2026-11-23 用户：大厅里要一直看得到这个按钮（以前仓库里没有修为丹就整条藏起来，用户以为按钮没了）
	var show := in_hall() and not _busy()
	_bar.visible = show
	if not show:
		return
	var cu2 := Profile.cult(_realm())
	var lv := int(cu2[0])
	_lab.text = "%s期 · 修为 Lv.%d" % [Realm.LIST[_realm()]["name"], lv]
	var cap := Prog.profile_at_cap()
	# 2026-11-23：瓶颈时修为照收（突破时结转），满格后写一下已经结转了多少（没有丹毒 / 药效了）
	if cap:
		var ov := Prog.carry_over(lv, float(cu2[1]), _realm())      # 突破后带进下一境界的量（下一境界的单位，和渡劫成功的提示一致）
		_lab.text += ("　已满 · 结转 +%s" % Prog.short_num(ov)) if ov >= 0.5 else "　已满"
	_exp.size.x = 180.0 * clampf(float(cu2[1]) / maxf(Prog.xp_need(lv), 1.0), 0.0, 1.0)
	_exp.color = UiStyle.CINNABAR if cap else UiStyle.QING
	if _eating:
		_btn.text = "服丹中… 余 %d" % n
	elif n == 0:
		_btn.text = "一键服丹 · 暂无可服的丹" if count_locked() > 0 else "一键服丹 · 暂无丹药"
	else:
		_btn.text = ("一键服丹 ×%d" % n) + ("" if touch else "　H")
	_btn.modulate.a = 0.7 if n == 0 and not _eating else 1.0
	_btn.disabled = _eating
	var vs := get_viewport().get_visible_rect().size
	_bar.reset_size()
	_bar.position = Vector2(roundf((vs.x - _bar.size.x) * 0.5), roundf(vs.y - 14.0 - _bar.size.y))
