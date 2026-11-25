class_name Hud
extends CanvasLayer
## 主界面：左上角玩家牌（头像 + 气血 / 灵力 + 境界 / 战力，player_plate.gd）、右上角的圆按钮（大厅里是洞府；大世界的背包按钮在 raid_hud.gd，同一个位置）、
## 打起来才出现的目标面板 / 架势条 / 技能栏 / 连击数；F1 打开的调试信息（境界条、飞行方式、飞剑阵状态、速度、操作说明）。
## 升阶时右侧的毛笔题字见 realm_banner.gd。

const RealmBanner := preload("res://scripts/realm_banner.gd")
const UiStyle := preload("res://scripts/ink_style.gd")      # 2026-11-24 界面重做：换成墨玉样式（接口同 ui_style.gd，见那个文件头）
const Plate := preload("res://scripts/player_plate.gd")
const CS := preload("res://scripts/combat_stats.gd")      # 战斗数值中枢（2026-11-20 夜）
const Tribulation := preload("res://scripts/tribulation.gd")
const YuanCine := preload("res://scripts/yuanying_cine.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")      # 2026-11-23 大数短写
## 条的颜色（条框是纸底墨线，见 ui_style.gd 的 bar_frame）：纸面上要用压得住的重色
const LAG_COL := Color(0.90, 0.60, 0.44, 0.92)      # 掉血后慢慢收的那一截：淡朱
const POSTURE_COL := Color(0.86, 0.56, 0.16)        # 架势 / 蓄力：赭黄

var font: Font
var compact := false  # 正式关卡（搜打撤）：收起键位说明、境界条、调试信息，见 set_compact
var lobby := false    # 主城（hub_hall.gd）：也是收起的，但右上角的洞府按钮留着
var _hints: Array[Control] = []
var _strip_row: Control
var touch := false    # 手机触屏：藏掉键位说明和调试信息，技能冷却画在触屏按钮上
var trailer := false  # 宣传片录制：只留境界条、境界名和战斗条，藏掉调试信息与操作说明
## 大厅里那几大段键位 / 招式说明、飞行参数、境界数字条：2026-11-20 用户要求默认藏起来（满屏字）；F1 临时打开 / 关上
var show_hints := false
## 2026-11-24 F_ui（gap-onboarding）：英雄档的 F1 说明按 hero_defs 的四个技能 + 共用的基本操作现写；老模式原文不动
var _help_lab: Label
var _chelp_lab: Label
var _help_for := "-"                 # 说明现在是按哪位英雄写的（"" = 老模式）
var _hero_help := false
## 2026-11-24 F_ui（gap-skills-hidden-ground）：新图里英雄档的技能框 / 觉醒槽落地也留着（以前只在空中）。主城要也这样就把它改成 true
const GROUND_SKILLS_IN_HUB := false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_F1:
		show_hints = not show_hints
		set_compact(compact)
	elif _bag_btn != null and _bag_btn.visible and InputMap.has_action("bag") and e.is_action_pressed("bag"):
		_open_abode()      # 大厅里按 B = 点右上角的洞府按钮（大世界里 B 是 raid_hud.gd 的背包）
var _realm_fx: Control
var _strip: Array[Label] = []
var _title: Label
var _info: Label
var _speed: Label

# 近战：玩家架势（底部；气血 / 灵力在左上角的玩家牌上），当前目标生命/架势（右上）；"弹反""破防""斩"等短提示改成 3D 字（combat_word.gd）
var plate: Control       # 左上角玩家牌（player_plate.gd）
var _bag_btn: Button     # 右上角圆按钮：大厅里开洞府
var _hero_btn: Button    # 2026-11-24：盖在左上角头像上的透明按钮，主城里点头像 = 开英雄选择界面
var _combat: Control
var _p_pst: ColorRect
var _p_pst_lab: Label
var _tgt: Control
var _t_name: Label
var _t_hp: ColorRect
var _t_hp_lag: ColorRect
var _t_pst: ColorRect
var _t_state: Label
var _hint: Label
# 法术空战准星：锁定到目标时变暖色、收紧
var _cross: Control
var _cross_lock := 0.0
var _cross_col := Color.WHITE
## 空战斗法：技能栏（E Z X C）、连击数、蓄力条
var _sk_root: Control
var _sk_cd: Array[ColorRect] = []
var _sk_name: Array[Label] = []
var _sk_box: Array[ColorRect] = []
var _sk_key: Array[Label] = []      # 2026-11-24 英雄档：四格的键字 E Z Q R（老模式 E Z X C，只露前两格）
var _combo_lab: Label
var _combo_sub: Label
var _combo_n := 0
var _combo_pop := 0.0
var _chg: ColorRect
var _clash_lab: Label
var _awk_lab: Label
var _awk_bg: ColorRect
var _awk_fill: ColorRect


func _ready() -> void:
	layer = 10
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 22)
	if not trailer:
		root.add_theme_constant_override("margin_top", 128)    # 左上角让给玩家牌：F1 的调试信息从它下面排起
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	root.theme = th
	add_child(root)
	plate = Plate.new()
	plate.font = font
	plate.position = Vector2(14, 12)
	if touch:
		plate.scale = Vector2(1.15, 1.15)     # 手机上字小：整块放大一点（再大就顶到中上方的 Boss 血条了）
	add_child(plate)
	# 2026-11-24 界面重做：右上角原来一颗「洞府」，现在是一排四个独立入口 英雄 / 备战 / 坊市 / 境界（_build_dock；2026-11-25 段位改成境界）。
	# _bag_btn 还是这个变量（B 键、别处的显隐判断都认它），现在是「备战」那一颗
	_bag_btn = _dock_button("meta_icon_prep", "备战", "pouch")
	_bag_btn.visible = false
	_bag_btn.pressed.connect(_open_abode)
	_bag_btn.add_to_group("touch_ui")      # 触屏操作层不把按在它上面的手指当成转镜头（touch_controls.gd）
	add_child(_bag_btn)
	_hero_btn = Button.new()
	_hero_btn.focus_mode = Control.FOCUS_NONE
	_hero_btn.visible = false
	for sk: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_hero_btn.add_theme_stylebox_override(sk, StyleBoxEmpty.new())
	_hero_btn.size = Vector2(Plate.AV_R, Plate.AV_R) * 2.0
	_hero_btn.draw.connect(_draw_hero_btn)
	_hero_btn.pressed.connect(_open_heroes)
	_hero_btn.add_to_group("touch_ui")
	add_child(_hero_btn)
	_build_dock()

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 18)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(strip)
	for i in Realm.count():
		var l := _mk("%d %s" % [i + 1, Realm.LIST[i]["name"]], 20)
		strip.add_child(l)
		_strip.append(l)

	_title = _mk("", 40)
	col.add_child(_title)
	_info = _mk("", 19)
	col.add_child(_info)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_speed = _mk("", 34)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_speed)

	var help := _mk(
		LEGACY_HELP, 16)
	_help_lab = help
	help.modulate = Color(1, 1, 1, 0.85)
	col.add_child(help)
	var chelp := _mk(LEGACY_CHELP, 17)
	_chelp_lab = chelp
	chelp.add_theme_color_override("font_color", Color(1.0, 0.9, 0.72))
	col.add_child(chelp)
	_hints = [_info, _speed, help, chelp]
	_strip_row = strip
	set_compact(compact)
	_build_combat()
	_cross = Control.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_realm_fx = RealmBanner.new()
	add_child(_realm_fx)
	_build_air()


## F1 操作说明（老模式：境界 / 飞剑阵那一套，原文不动）
const LEGACY_HELP := ("WASD 移动　鼠标 视角（飞行时低头下降、抬头上升）　滚轮 镜头距离　空格 跳跃 / 腾空空战(结丹起)　"
		+ "Shift 短按闪现 · 长按疾行/疾遁（出招/受击/施法中按下即闪，可打断任何动作）\n"
		+ "Q 飞剑阵（起手耗 12% 灵力、开着每秒耗 3.5%，持续 20s，再按收起）　F 起飞/降落（空战中 F 转光遁）　E 万剑齐发(需先 Q 召剑)　G 自动出剑开关\n"
		+ "R 大罡剑阵（大乘专属，耗 50% 灵力，地面 / 空战可放）　1-8 或 [ ] 切换境界　Backspace 回出生点　Esc 释放鼠标")
const LEGACY_CHELP := ("地面近战：J / 左键 三段连招　K / 右键 点按弹反 · 按住格挡　敌人破防后 J 处决　炼气/筑基：空格跳起 → J 空中斩（最多两段）
"
		+ "结丹起空战：点按 J / 左键 五段连击，第二段起带方向 = 派生（W 挑月 · S 坠星 · A/D 绕身击）· 长按蓄力重击（W/空格 挑飞 · S 陨落；蓄过半破防）
"
		+ "击飞后：J = 瞬身追击 → 再点三下空中连击 → 终结重击（长按直接终结）· Shift = 追身　有目标时按住 Shift = 御风突进，途中 J = 冲刺攻击
"
		+ "K / 右键 护体（挡不住红光重击）　对手出手前一瞬间按 K 或 Shift = 瞬身，随后 J = 瞬身反击　挨打时 K = 挣脱（耗罡气）· 被打飞时 Shift = 受身
"
		+ "E 飞剑点射 · 长按连发　Z 剑诀（三式按顺序轮放）　长按 K 聚气　往下飞碰到地面即落地")


## 大厅里右上角的圆按钮：打开洞府（储物 / 坊市 / 丹房，abode_ui.gd）。和择境门的菜单一样，开着的时候游戏暂停、放开鼠标。
func _open_abode() -> void:
	if _cine_busy():
		return
	var m := get_parent()
	var ui: Variant = m.get("level_ui") if m != null else null
	if not is_instance_valid(ui) or get_tree().paused or bool(ui.is_open()):
		return
	# 2026-11-21 QA BUG-01：入境载入 / 切场景途中、人已在关卡里，都不开洞府。以前选关「开始匹配」后的载入黑场里按 B / 点这个按钮，
	# 洞府会被带进大世界、在局内改存档（取下法宝 → 撤离后复制一份、陨落不丢）
	if bool(m.get("_switching")) or m.get("level") != null:
		return
	ui.open_abode()
	var ab: Variant = ui.get("_abode")
	if not is_instance_valid(ab):
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ab.closed.connect(func() -> void:
		get_tree().paused = false
		var cam: Variant = m.get("cam")
		if is_instance_valid(cam) and bool(cam.capture_mouse):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)


var _hub_q: Array = []             # 主城里排着队要说的话 [字, 停多久]（hub_hall.say 一次只有一行）
var _hub_q_t := 0.0
var _hub_q_chk := 0.0
## 新号第一次进主城的三句引导（2026-11-25 主干解耦改成修仙版；一个号只说一次，记在 raid_profile 的 stats.intro）
const INTRO_LINES := [
	["门 0 木兰草原：采药、杀怪夺宝，找到亮着的传送阵撤出，东西才带得走", 4.5],
	["右上角「备战」佩戴法宝、带上丹符；「坊市」买丹卖货、炼丹；仓库里的修为丹底下一键服下", 4.5],
	["修炼场打坐、渡劫破境；到了元婴，门 2 沙海古墟 / 门 3 天工秘所才放行", 4.5],
]
const Profile := preload("res://scripts/raid_profile.gd")


## 主城 / 老大厅这会儿看得见、没在切场景 / 开菜单 / 黑场 / 演出
func _hall_clear() -> bool:
	var m := get_parent()
	if m == null or m.get("level") != null or get_tree().paused or bool(m.get("_switching")) or _cine_busy():
		return false
	var ui: Variant = m.get("level_ui")
	if ui != null and is_instance_valid(ui):
		if bool(ui.call("is_open")):
			return false
		if ui.has_method("is_clear") and not bool(ui.call("is_clear")):
			return false
	return true


## 主城里排队说话：读档时的通知（Profile.notice：存档迁移、上局中途离线还回来的东西）和新号引导，一句句交给 hub.say
## （2026-11-25 主干解耦：原来这里还播搜打撤的段位晋升题字，删了）
func _hub_notes() -> void:
	var dt := get_process_delta_time()
	_hub_q_t -= dt
	_hub_q_chk -= dt
	if _hub_q_chk > 0.0:
		return
	_hub_q_chk = 0.5
	var m := get_parent()
	if not _hall_clear():
		return
	var hub: Variant = m.get("hub")
	if hub == null or not is_instance_valid(hub) or not hub.has_method("say") or not bool(hub.get("active")) or _in_duel():
		return
	if Profile.notice != "":
		_hub_q.append([Profile.notice, 5.0])
		Profile.notice = ""
	var st: Dictionary = Profile.stats()
	if int(st.get("intro", 0)) == 0 and int(st.get("raids", 0)) == 0 and not Profile.test_mode():
		st["intro"] = 1
		Profile.save()
		for e: Array in INTRO_LINES:
			_hub_q.append(e)
	if not _hub_q.is_empty() and _hub_q_t <= 0.0 and _hub_toast_idle(hub):
		var e2: Array = _hub_q.pop_front()
		hub.call("say", str(e2[0]), float(e2[1]))
		_hub_q_t = float(e2[1]) + 0.7


## 主城那一行字现在空着：hub 没有攒着要飘的（_later：开机离线闭关结算、渡劫结果），上一句也淡完了。
## 2026-11-25 T_hub：读档通知（上局中途离线还回来的东西）和离线闭关结算常常同一次开机出现，以前共用一行字、后说的把先说的盖掉
func _hub_toast_idle(hub: Object) -> bool:
	if str(hub.get("_later_txt")) != "":
		return false
	var t: Variant = hub.get("_toast")
	return not (t is CanvasItem) or (t as CanvasItem).modulate.a < 0.05


## F1 说明：英雄档按 hero_defs 现写（四个技能 + 觉醒 + 共用的基本操作 + 局内 raid_hud 的几个键）；老模式（hero_id == ""）照旧
func _build_help(p: Player) -> void:
	_help_for = p.hero_id
	_hero_help = p.hero_id != ""
	if _help_lab == null or _chelp_lab == null:
		return
	if not _hero_help:
		_help_lab.text = LEGACY_HELP
		_chelp_lab.text = LEGACY_CHELP
		set_compact(compact)
		return
	var d: Dictionary = p.hero_def
	_help_lab.text = ("WASD 移动　鼠标 视角　滚轮 镜头距离　空格 跳跃 / 腾空　F 起飞 / 降落　Shift 短按闪现（两次，自己回）· 长按朝目标突进　Esc 释放鼠标\n"
			+ "J / 左键 攻（四段连打，第二段起带方向 = 上挑 / 下砸 / 绕身，长按蓄力）　K / 右键 护体；对手出手前一瞬按 K 或 Shift = 瞬身反打　E Z Q R 四个技能　V 觉醒（槽满时）\n"
			+ "大世界 / 禁地里：T 拾取最近的　B 背包（服丹、用符都在里面点）　站在搜点旁自动读条　点小地图 = 神识一扫　走进亮着的传送阵撤离")
	var rows: Array = ["%s · %s" % [str(d.get("name", p.hero_id)), str(d.get("title", ""))]]
	var sk: Variant = d.get("skills", [])
	if sk is Array:
		for s: Variant in sk:
			if s is Dictionary:
				rows.append("%s %s：%s" % [str((s as Dictionary).get("key", "")), str((s as Dictionary).get("name", "")), str((s as Dictionary).get("desc", ""))])
	var aw := str(d.get("awaken", ""))
	if aw != "":
		rows.append("觉醒　" + aw)
	_chelp_lab.text = "\n".join(PackedStringArray(rows))
	set_compact(compact)


## 2026-11-20 修：雷劫 / 结婴演出在播时洞府按钮藏起来、B 键也不开（以前渡劫中途能开洞府把破境丹卖掉、还会把雷劫停在半截）
func _cine_busy() -> bool:
	return Tribulation.running or YuanCine.playing != null


## 主城擂台对决进行中（入场倒数 / 对决 / 结算，hub_hall.gd 的 duel_busy）。
## 这时顶上正中有双方的气血条（arena_duel.gd 的 _vs），右上角的目标面板就重复了
func _in_duel() -> bool:
	var m := get_parent()
	var hub: Variant = m.get("hub") if m != null else null
	return is_instance_valid(hub) and hub.has_method("duel_busy") and bool(hub.call("duel_busy"))


## 升阶：屏幕右侧竖排毛笔题字"××期"
func realm_up(r: Dictionary) -> void:
	_realm_fx.show_realm("%s期" % r["name"], Realm.line_color(r))


func _draw_cross() -> void:
	var c := _cross.size * 0.5
	var gap := lerpf(9.0, 5.0, _cross_lock)
	var tick := lerpf(7.0, 9.0, _cross_lock)
	var shade := Color(0.08, 0.09, 0.12, 0.8)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_cross.draw_line(c + d * gap, c + d * (gap + tick), shade, 4.0)
		_cross.draw_line(c + d * gap, c + d * (gap + tick), _cross_col, 2.0)
	_cross.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), _cross_col)


func _refresh_cross(p: Player) -> void:
	_cross.visible = p.st == Player.St.AIR
	if not _cross.visible:
		return
	var locked := p.caster.aim_target() != null or (p.air.target != null and is_instance_valid(p.air.target))
	_cross_lock = move_toward(_cross_lock, 1.0 if locked else 0.0, get_process_delta_time() * 8.0)
	_cross_col = Color(1, 1, 1, 0.85).lerp(Color(1.0, 0.62, 0.3, 1.0), _cross_lock)
	_cross.queue_redraw()


func _build_combat() -> void:
	_combat = Control.new()
	_combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combat)
	var th := Theme.new()
	th.default_font = font
	_combat.theme = th

	# 玩家：气血 / 灵力在左上角的玩家牌上；底部居中只留一条从中间向两边涨的架势（地面近战才有）
	_p_pst = _bar(_combat, Vector2.ZERO, Vector2(420, 8), POSTURE_COL, true)
	_p_pst_lab = _mk("架势", 15)
	_combat.add_child(_p_pst_lab)

	# 目标：右上
	_tgt = Control.new()
	_tgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat.add_child(_tgt)
	_t_name = _mk("", 22)
	_tgt.add_child(_t_name)
	_t_state = _mk("", 15)
	_t_state.position = Vector2(0, 30)
	_tgt.add_child(_t_state)
	_t_hp_lag = _bar(_tgt, Vector2(0, 56), Vector2(360, 9), LAG_COL)
	_t_hp = _bar(_t_hp_lag.get_parent() as Control, Vector2.ZERO, Vector2(360, 9), UiStyle.CINNABAR, false, false)
	_t_pst = _bar(_tgt, Vector2(0, 72), Vector2(360, 8), POSTURE_COL, true)
	var lab := _mk("生命", 13)
	lab.position = Vector2(-38, 50)
	_tgt.add_child(lab)
	var lab2 := _mk("架势", 13)
	lab2.position = Vector2(-38, 66)
	_tgt.add_child(lab2)
	_hint = _mk("", 18)
	_hint.position = Vector2(0, 88)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
	_tgt.add_child(_hint)



## 底条 + 填充条；centered=true 时填充从中间向两边涨（只狼式架势条）
## make_bg=false 时直接在 parent 里放填充（用来叠在"滞后条"上）
func _bar(parent: Control, pos: Vector2, size: Vector2, fill: Color, centered := false, make_bg := true) -> ColorRect:
	var host := parent
	if make_bg:
		var bg := Panel.new()   # 条框：纸底细墨线
		bg.add_theme_stylebox_override("panel", UiStyle.bar_frame())
		bg.position = pos
		bg.size = size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bg)
		host = bg
		if centered:
			var notch := ColorRect.new()
			notch.color = Color(UiStyle.LINE, 0.7)
			notch.position = Vector2(size.x * 0.5 - 1.0, -2.0)
			notch.size = Vector2(2.0, size.y + 4.0)
			notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bg.add_child(notch)
	var f := ColorRect.new()
	f.color = fill
	f.size = size
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.set_meta("w", size.x)
	f.set_meta("centered", centered)
	host.add_child(f)
	return f


func _set_bar(f: ColorRect, ratio: float) -> void:
	var w: float = f.get_meta("w")
	f.size.x = w * clampf(ratio, 0.0, 1.0)
	if f.get_meta("centered"):
		f.position.x = (w - f.size.x) * 0.5


static func _posture_col(r: float) -> Color:
	return POSTURE_COL.lerp(UiStyle.CINNABAR, smoothstep(0.45, 0.95, r))


func _refresh_combat(p: Player) -> void:
	var m := p.melee
	var vs := get_viewport().get_visible_rect().size
	var air_on := p.st == Player.St.AIR and p.air.engaged()
	var vis := (p.st == Player.St.GROUND and m.engaged()) or air_on
	_combat.visible = vis
	var pst_on := vis and not air_on
	(_p_pst.get_parent() as Control).visible = pst_on
	_p_pst_lab.visible = pst_on
	if pst_on:
		var x := vs.x * 0.5 - 210.0
		var y := vs.y - 150.0
		(_p_pst.get_parent() as Control).position = Vector2(x, y)
		_p_pst_lab.position = Vector2(x + 430.0, y - 9.0)
		_set_bar(_p_pst, m.posture_ratio())
		_p_pst.color = _posture_col(m.posture_ratio())

	var tv: Variant = p.air.target if air_on else m.target
	var t: Node3D = null
	if is_instance_valid(tv) and (tv as Node3D).has_method("state_name"):
		t = tv   # 木桩 / Boss 没有这套面板；已释放的目标（搜打撤的怪）不取
	# 2026-11-24 用户：擂台对决时右上角这块和顶上的对决血条重复，不要了（对手的架势 / 破绽本来也用不上：陪练和真人都不会破绽）
	_tgt.visible = vis and t != null and is_instance_valid(t) and not _in_duel()
	if _tgt.visible:
		# 大世界里右上角是背包 + 小地图 + 区域纸条（raid_hud.gd）：目标面板让到它们左下、Boss 血条下面
		_tgt.position = Vector2(vs.x - 310.0 - 360.0, 150.0) if compact else Vector2(vs.x - 22.0 - 360.0, 150.0)
		_t_name.text = str(t.get("display_name"))
		_t_state.text = t.state_name()
		_set_bar(_t_hp, t.hp_ratio())
		var lag := _t_hp_lag.size.x / 360.0
		_set_bar(_t_hp_lag, lerpf(lag, t.hp_ratio(), 0.04) if lag > t.hp_ratio() else t.hp_ratio())
		_set_bar(_t_pst, t.posture_ratio())
		_t_pst.color = _posture_col(t.posture_ratio())
		_hint.text = "破绽！按 J / 左键 处决" if t.is_broken() else ""
		(_t_pst.get_parent() as Control).visible = not air_on


## 纸面上的字：墨色、不描边
func _mk_ink(text: String, size: int, col := UiStyle.TEXT_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _mk(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiStyle.TEXT)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.92))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func refresh(p: Player, sm: SwordManager) -> void:
	var r := p.realm
	var cb: Color = r["col_b"]
	for i in _strip.size():
		_strip[i].modulate = Color.WHITE.lerp(cb, 0.6) if i == p.realm_idx else Color(1, 1, 1, 0.45)
	_title.text = "%s期" % r["name"]
	_title.modulate = Color.WHITE.lerp(cb, 0.45)
	var blink_txt := "%dm · %dm/s" % [int(r["blink"]), int(r["blink_spd"])] if float(r["blink"]) > 0.0 else "未掌握"
	var sw_txt := "未召出（Q）"
	if sm.is_ready():
		sw_txt = "%d 柄 · 剩 %ds" % [sm.swords.size(), int(ceil(sm.time_left()))]
	elif sm.active:
		sw_txt = "召剑中 %d/%d" % [sm.swords.size(), int(r["swords"])]
	var art := Realm.art_info(r)
	var spell_txt := "空战斗法：结丹起"
	if Realm.art(r) > 0:
		spell_txt = "空战剑诀 Z/X/C：%s　E 长按连发：%s %d 柄/秒" % [" · ".join(PackedStringArray(art["stages"])), art["volley"], int(r["volley"])]
	_info.text = "飞行方式：%s\n飞剑阵：%s　阵型 %s · %s　出剑间隔 %.2fs　连斩 %d　索敌 %dm　自动出剑：%s\n%s\n遁速上限：%d m/s　闪现：%s　状态：%s" % [
		r["flight"], sw_txt, art["form"], art["strike"], float(r["atk_cd"]), int(r["chain"]), int(r["range"]),
		"开" if sm.auto_attack else "关", spell_txt, int(r["speed"]), blink_txt, p.state_text()]
	_speed.text = "%d m/s　高度 %dm" % [int(round(p.speed())), int(round(p.global_position.y))]
	_speed.modulate.a = 1.0 if p.st != Player.St.GROUND else 0.0
	_refresh_combat(p)
	_refresh_cross(p)
	plate.refresh(p)
	_hub_notes()
	if p.hero_id != _help_for:
		_build_help(p)
	# 右上角的洞府按钮：只在大厅（大世界里那个位置是 raid_hud.gd 的背包按钮）
	_bag_btn.visible = (not compact or lobby) and not trailer and get_parent().get("level") == null and not _cine_busy()
	if _bag_btn.visible:
		_bag_btn.position = UiStyle.corner_pos(get_viewport().get_visible_rect().size)
	_layout_dock()
	# 头像上的「换英雄」：和洞府按钮同进同出（只在主城）
	_hero_btn.visible = _bag_btn.visible and p.hero_id != "" and ResourceLoader.exists(HERO_UI)
	if _hero_btn.visible:
		_hero_btn.scale = plate.scale
		_hero_btn.position = plate.position + (Plate.AV_C - Vector2(Plate.AV_R, Plate.AV_R)) * plate.scale
	_refresh_air(p)


# ---------- 空战斗法：技能栏 / 连击数 / 蓄力条 ----------

func _build_air() -> void:
	_sk_root = Control.new()
	_sk_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sk_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = font
	_sk_root.theme = th
	add_child(_sk_root)
	for i in 4:
		var box := ColorRect.new()     # 小纸条：纸色底 + 一圈细墨线，冷却从上往下盖一层境界色
		box.color = Color(UiStyle.SURF, 0.86)
		box.size = Vector2(118, 46)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sk_root.add_child(box)
		_sk_box.append(box)
		var cd := ColorRect.new()
		cd.color = Color(0.35, 0.62, 1.0, 0.4)
		cd.size = Vector2(118, 46)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cd)
		_sk_cd.append(cd)
		var rim := Panel.new()
		rim.add_theme_stylebox_override("panel", UiStyle.outline(Color(UiStyle.LINE, 0.8)))
		rim.size = Vector2(118, 46)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rim)
		var key := _mk_ink(["E", "Z", "X", "C"][i], 20, UiStyle.CINNABAR)
		key.position = Vector2(8, 9)
		box.add_child(key)
		_sk_key.append(key)
		var nm := _mk_ink("", 14)
		nm.position = Vector2(28, 4)
		nm.size = Vector2(88, 40)
		nm.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		box.add_child(nm)
		_sk_name.append(nm)
	_combo_lab = _mk("", 54)
	_combo_lab.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_combo_lab.add_theme_constant_override("outline_size", 8)
	_sk_root.add_child(_combo_lab)
	_combo_sub = _mk("", 18)
	_sk_root.add_child(_combo_sub)
	_chg = _bar(_sk_root, Vector2.ZERO, Vector2(200, 7), POSTURE_COL)
	_clash_lab = _mk("", 34)
	_clash_lab.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_sk_root.add_child(_clash_lab)
	_awk_lab = _mk("", 18)
	_sk_root.add_child(_awk_lab)
	# 2026-11-25 觉醒槽画成一根条（原来只有一行「觉醒 N%」的字）：底 + 填充，满了发金光
	_awk_bg = ColorRect.new()
	_awk_bg.color = Color(0.05, 0.06, 0.08, 0.55)
	_awk_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sk_root.add_child(_awk_bg)
	_awk_fill = ColorRect.new()
	_awk_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sk_root.add_child(_awk_fill)
	if touch:
		for b in _sk_box:
			b.visible = false


## 正式关卡里不要满屏的操作说明：只留血条、技能冷却这些打起来要看的
func set_compact(on: bool) -> void:
	compact = on
	for n in _hints:
		n.visible = show_hints and not trailer and not touch and not on
	if _strip_row != null:
		_strip_row.visible = show_hints and not touch and not on and not _hero_help      # 英雄档：境界条没用（改不了战斗档）
	if _title != null:
		_title.visible = trailer and not on     # 境界名平时在玩家牌上；录宣传片不要玩家牌，留这行大字
	if plate != null:
		plate.visible = not trailer


## 2026-11-23：连击伤害 combo_dmg 累加的是原始数（base(境界) × 倍率，air_melee.gd 里，这次不动）；大世界里按 raid_manager
## 记的「最近一次 实伤 / 原始」（dmg_ratio）折成和飘字同一个口径。大厅（没有 mgr）照旧写原始数
func _combo_ratio() -> float:
	if plate == null:
		return 1.0
	var mgr: Variant = plate.get("raid")
	if mgr == null or not is_instance_valid(mgr):
		return EnemyDummy.shown_dmg(plate, 1.0)      # 主城：和木人 / 刀客 / 剑冢首领的飘字同一个口径
	var k: Variant = (mgr as Object).get("dmg_ratio")
	if k == null or not (k is float or k is int) or float(k) <= 0.0:
		return 1.0
	return float(k)


const LEGACY_KEYS := ["E", "Z", "X", "C"]
const HERO_KEYS := ["E", "Z", "Q", "R"]


## 键字 / 技能名字色只在变了的时候改（每帧 add_theme_color_override 会让 Label 重排）
func _ink_key(i: int, key: String, name_col: Color) -> void:
	if _sk_key[i].text != key:
		_sk_key[i].text = key
	if _sk_name[i].get_theme_color("font_color") != name_col:
		_sk_name[i].add_theme_color_override("font_color", name_col)


## 2026-11-24 搜打撤 PvP 重构：英雄档（player.hero_id != ""）的桌面技能框 —— E / Z / Q / R 四格，每格读技能脚本的
## skill_info(i)（{key, name, desc, cd, mp, cd_ratio, ready, awake_name?, awake_only?}，kit_yujian.gd / kit_canghong.gd）：
## 名字（苍鸿觉醒后换成 瞬狱 / 剑域 / 天斩 / 万剑归宗，字转朱色）、灵力、冷却从上往下盖。
## 御剑的 R（大罡剑阵）只在 kit.btn_visible(3)（觉醒中）露出来；御剑的 Z 照老框写下一式的名字和灵力（三式轮放）。手机不画（冷却画在触屏键上）
func _refresh_hero_skills(p: Player, kit: Node, x0: float, y0: float, lc: Color) -> void:
	var a := p.air
	var aw := a.awake_t > 0.0
	for i in 4:
		var box := _sk_box[i]
		box.visible = not touch and (not kit.has_method("btn_visible") or bool(kit.call("btn_visible", i)))
		if not box.visible:
			continue
		box.position = Vector2(x0 + 124.0 * float(i), y0)
		var v: Variant = kit.call("skill_info", i)
		var info: Dictionary = v if v is Dictionary else {}
		var nm := str(info.get("name", ""))
		var mp := float(info.get("mp", 0.0))
		if i == 1 and p.hero_id == "yujian":
			var k: int = a.next_skill()
			nm = a.skill_name(k)
			mp = a.skill_cost(k)
		var sub := "灵力 %d" % int(roundf(CS.mp_shown(p.realm_idx, mp))) if mp > 0.0 else ""
		if kit.has_method("touch_text") and str(kit.call("touch_text", i)) == "收":
			sub = "再按收起"      # 御剑飞剑阵开着
		_sk_name[i].text = nm + ("\n" + sub if sub != "" else "")
		var changed := aw and (info.has("awake_name") or bool(info.get("awake_only", false)))
		_ink_key(i, HERO_KEYS[i], UiStyle.CINNABAR if changed else UiStyle.TEXT_INK)
		_sk_cd[i].size.y = 46.0 * clampf(float(info.get("cd_ratio", 0.0)), 0.0, 1.0)
		_sk_cd[i].color = Color(lc.r, lc.g, lc.b, 0.45)
		box.modulate = Color(1, 1, 1, 1.0) if bool(info.get("ready", true)) else Color(0.82, 0.82, 0.84, 0.7)


## 英雄档的技能框 / 觉醒槽落地也留着的场合：任何关卡里（2026-11-25 主干解耦：英雄到处都用，原来只在新图）；主城看 GROUND_SKILLS_IN_HUB
func _ground_skills() -> bool:
	var m := get_parent()
	if m == null:
		return false
	if m.get("level") != null:
		return true
	return GROUND_SKILLS_IN_HUB


func _refresh_air(p: Player) -> void:
	var air := p.st == Player.St.AIR
	var kit: Node = p.kit if p.hero_id != "" else null
	var hero_ui := kit != null and is_instance_valid(kit) and kit.has_method("skill_info")
	# 2026-11-24 F_ui（gap-skills-hidden-ground）：新图里英雄档在地上也露技能框（桌面）和觉醒槽：出生、走路、开箱、打地面的怪都是站着的，
	# 以前得先被打飞 / 腾空才知道有 E Z Q R 和觉醒。地上只露这两样，连击数 / 对波 / 蓄力条照旧只在空中
	var on := (air or (hero_ui and _ground_skills())) and not trailer
	_sk_root.visible = on
	if not on:
		_combo_n = 0
		return
	var a := p.air
	var vs := get_viewport().get_visible_rect().size
	var x0 := vs.x - 4.0 * 124.0 - 18.0
	var y0 := vs.y - 250.0
	var lc := Realm.line_color(p.realm)
	if hero_ui:
		_refresh_hero_skills(p, kit, x0, y0, lc)      # 2026-11-24 英雄档：E Z Q R 四格，读技能脚本
	if not air:
		_combo_n = 0
		_combo_lab.visible = false
		_combo_sub.visible = false
		_clash_lab.visible = false
		(_chg.get_parent() as Control).visible = false
		_awk_update(vs, a, lc, false)
		return
	x0 = vs.x - 2.0 * 124.0 - 18.0
	for i in (0 if hero_ui else 4):      # 老模式（hero_id == ""，门 0 木兰草原 / 老演示）：下面原样
		var box := _sk_box[i]
		box.visible = i < 2 and not touch     # 技能栏只剩两格：E 飞剑、Z 诀（下一式）
		if i >= 2:
			continue
		_ink_key(i, LEGACY_KEYS[i], UiStyle.TEXT_INK)      # 从英雄档切回老模式（门 0）时把键字 / 字色换回来；老模式本来就是这个样子
		box.position = Vector2(x0 + 124.0 * float(i), y0)
		var ready := true
		var frac := 0.0
		if i == 0:
			_sk_name[i].text = "飞剑点射\n长按连发 / 对波"
			ready = p.mp >= a.SHOT_MP
		else:
			var k: int = a.next_skill()
			_sk_name[i].text = "%s\n灵力 %d" % [a.skill_name(k), int(roundf(CS.mp_shown(a.player.realm_idx, a.skill_cost(k))))]      # 和玩家牌一样按 60 ~ 300 显示
			ready = a.skill_ready(k)
			frac = a.art_cd()      # 三式共用冷却
		_sk_cd[i].size.y = 46.0 * clampf(frac, 0.0, 1.0)
		_sk_cd[i].color = Color(lc.r, lc.g, lc.b, 0.45)
		box.modulate = Color(1, 1, 1, 1.0) if ready else Color(0.82, 0.82, 0.84, 0.7)
	# 连击数：数字变化时弹一下
	if a.combo != _combo_n:
		if a.combo > _combo_n:
			_combo_pop = 1.0
		_combo_n = a.combo
	_combo_pop = maxf(_combo_pop - get_process_delta_time() * 6.0, 0.0)
	var show := a.combo >= 2
	_combo_lab.visible = show
	_combo_sub.visible = show
	if show:
		_combo_lab.text = "%d 连击" % a.combo
		_combo_lab.position = Vector2(vs.x - 330.0, vs.y * 0.36 - 10.0 * _combo_pop)
		_combo_lab.scale = Vector2.ONE * (1.0 + 0.25 * _combo_pop)
		_combo_lab.modulate = Color.WHITE.lerp(Color(1.0, 0.5, 0.3), clampf(float(a.combo) / 30.0, 0.0, 1.0))
		_combo_sub.text = "伤害 %s" % NumFmt.fmt(float(a.combo_dmg) * _combo_ratio())
		_combo_sub.position = Vector2(vs.x - 322.0, vs.y * 0.36 + 68.0)
	# 觉醒槽：底部居中一行字
	_awk_update(vs, a, lc, true)
	# 对波：屏幕中上方提示 + 相持条（借蓄力条）
	var wk: float = a.warn_k()
	_clash_lab.visible = a.in_clash() or wk > 0.0
	if a.in_clash():
		_clash_lab.text = "飞剑对波！连点「攻击」"
		_clash_lab.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
		_clash_lab.position = Vector2(vs.x * 0.5 - 240.0, vs.y * 0.2)
		_clash_lab.scale = Vector2.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.03))
	elif wk > 0.0:
		# 预警：对手的飞剑要来了，点「剑」接下来对波（下面的条是剩余时间）
		_clash_lab.text = "飞剑来袭！点「剑」对波" if touch else "飞剑来袭！按 E 对波"
		_clash_lab.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		_clash_lab.position = Vector2(vs.x * 0.5 - 250.0, vs.y * 0.2)
		_clash_lab.scale = Vector2.ONE * (1.1 + 0.1 * sin(Time.get_ticks_msec() * 0.04))
	# 蓄力条：准星下方（对波时是交汇点位置，预警时是剩余时间）
	var ck := a.clash_u() if a.in_clash() else (wk if wk > 0.0 else a.charge_k())
	(_chg.get_parent() as Control).visible = ck > 0.0
	if ck > 0.0:
		(_chg.get_parent() as Control).position = Vector2(vs.x * 0.5 - 100.0, vs.y * 0.5 + 60.0)
		_set_bar(_chg, ck)
		_chg.color = POSTURE_COL if ck < 1.0 else UiStyle.CINNABAR.lerp(lc, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))


# ---------- 英雄选择（2026-11-24 界面专项）----------

const HERO_UI := "res://scripts/ex/hero_select_ui.gd"


## 头像左下角一枚小纸片写「换」：告诉人头像能点（右下角那枚朱印是段位）
func _draw_hero_btn() -> void:
	if not _dock.is_empty():
		return          # 右上角已经有单独的「英雄」入口：头像还能点，但不再多画一枚「换」
	var mode := _hero_btn.get_draw_mode()
	var hot := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var c := Vector2(Plate.AV_R, Plate.AV_R) + Vector2(-37.0, 38.0)
	_hero_btn.draw_circle(c, 15.5, UiStyle.CINNABAR if hot else UiStyle.LINE, true, -1.0, true)
	_hero_btn.draw_circle(c, 13.5, UiStyle.PAPER, true, -1.0, true)
	var f: Font = font if font != null else ThemeDB.fallback_font
	var ts := f.get_string_size("换", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	_hero_btn.draw_string(f, c + Vector2(-ts.x * 0.5, f.get_ascent(16) - f.get_height(16) * 0.5), "换", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			UiStyle.CINNABAR if hot else UiStyle.TEXT_INK)


## 主城里点左上角头像：开全屏的英雄选择界面（scripts/ex/hero_select_ui.gd，它自己暂停树、放鼠标，关掉时恢复）。
## 能不能开的条件和 _open_abode 一样：演出中 / 已经暂停 / 开着选关 / 切场景途中 / 人在关卡里都不开
func _open_heroes() -> void:
	if _cine_busy():
		return
	var m := get_parent()
	var ui: Variant = m.get("level_ui") if m != null else null
	if not is_instance_valid(ui) or get_tree().paused or bool(ui.is_open()):
		return
	if bool(m.get("_switching")) or m.get("level") != null or not ResourceLoader.exists(HERO_UI):
		return
	(load(HERO_UI) as GDScript).call("open", ui, true)


# ---------- 主城右上角的四个入口（2026-11-24 界面重做）----------
## 用户原话：「英雄的入口单独领出来，仓库跟备战的入口我觉得可以合并成一个入口（备战）……商店也独立成一个单独的入口……段位也单独独立一个入口」。
## 从左到右 英雄 / 备战 / 坊市 / 段位：深色圆片 + 金线图标 + 底下一行小字（scripts/ex/meta_kit.gd 的 round_button）。
## 备战那一颗就是 _bag_btn（在 _ready 里建）；另外三颗在 _dock 里。显隐跟 _bag_btn 走（只在主城）

const META_KIT := "res://scripts/ex/meta_kit.gd"
const DOCK_D := 84.0
const DOCK_GAP := 16.0
var _dock: Array[Button] = []       # [英雄, 坊市, 境界]


## 一颗入口圆片。新样式库不在（老分支）时退回原来的纸片圆按钮
func _dock_button(icon_name: String, text: String, old_icon: String) -> Button:
	var b: Button = null
	if ResourceLoader.exists(META_KIT):
		b = (load(META_KIT) as GDScript).call("round_button", icon_name, DOCK_D, text)
	if b == null:
		b = UiStyle.round_icon_button(old_icon)
		b.set_meta("badge", text)
	return b


func _build_dock() -> void:
	if not ResourceLoader.exists(META_KIT):
		return
	for e: Array in [["meta_icon_hero", "英雄", _open_heroes], ["meta_icon_shop", "坊市", _open_meta.bind("shop")], ["meta_icon_rank", "境界", _open_meta.bind("rank")]]:
		var b := _dock_button(str(e[0]), str(e[1]), "pouch")
		b.visible = false
		b.pressed.connect(e[2] as Callable)
		b.add_to_group("touch_ui")
		add_child(b)
		_dock.append(b)


## 四颗排在右上角：英雄 备战 坊市 境界（靠右对齐）
func _layout_dock() -> void:
	if _dock.is_empty():
		return
	var on := _bag_btn.visible
	for b in _dock:
		b.visible = on
	if not on:
		return
	var vs := get_viewport().get_visible_rect().size
	var step := DOCK_D + DOCK_GAP
	var x0 := vs.x - 18.0 - DOCK_D - step * 3.0
	var order: Array[Button] = [_dock[0], _bag_btn, _dock[1], _dock[2]]
	for i in order.size():
		order[i].position = Vector2(x0 + step * float(i), 10.0)


## 开元界面的某一页（shop 坊市 / rank 境界 / prep 备战）：走洞府按钮的同一条路（暂停、放鼠标都在 _open_abode 里），再翻到那一页
func _open_meta(key: String) -> void:
	_open_abode()
	var m := get_parent()
	var ui: Variant = m.get("level_ui") if m != null else null
	var ab: Variant = ui.get("_abode") if is_instance_valid(ui) else null
	if is_instance_valid(ab) and (ab as Object).has_method("_set_tab"):
		ab.call("_set_tab", key)


## 2026-11-25 觉醒槽：底部居中一根细条 + 一行字。英雄档满了提示「点『觉』/ 按 V」直接觉醒（不用再按住聚气），觉醒中条随剩余时间缩短。
## air = 人在空战里（地上觉醒不了：提示先腾空）
func _awk_update(vs: Vector2, a: Node, lc: Color, air: bool) -> void:
	var touch_on := touch
	var w := 240.0
	var x0 := vs.x * 0.5 - w * 0.5
	var y0 := vs.y - 122.0
	_awk_lab.position = Vector2(x0 + w + 12.0, y0 - 10.0)      # 字放在条的右边：条上面那一行是锁定目标的血条 / 状态，叠在一起看不清
	_awk_bg.position = Vector2(x0 - 2.0, y0 - 2.0)
	_awk_bg.size = Vector2(w + 4.0, 10.0)
	_awk_fill.position = Vector2(x0, y0)
	var hero: bool = a.player.hero_id != ""
	if a.awake_t > 0.0:
		var full := float(a.get("_awake_dur")) if a.get("_awake_dur") != null else 14.0
		_awk_fill.size = Vector2(w * clampf(a.awake_t / maxf(full, 0.1), 0.0, 1.0), 6.0)
		_awk_fill.color = Color.WHITE.lerp(lc, 0.55)
		_awk_lab.text = "觉醒中 %ds" % int(ceil(a.awake_t))
		_awk_lab.modulate = Color.WHITE.lerp(lc, 0.6)
		return
	var k := clampf(a.awaken / 100.0, 0.0, 1.0)
	_awk_fill.size = Vector2(w * k, 6.0)
	if k >= 1.0:
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_awk_fill.color = Color(1.0, 0.8 + 0.12 * p, 0.35 + 0.25 * p)
		var how := ("点「觉」觉醒" if touch_on else "按 V 觉醒") if hero else ("按住「御」聚气觉醒" if touch_on else "按住 V 聚气觉醒")
		_awk_lab.text = "觉醒已满　" + ("" if air else "腾空后") + how
		_awk_lab.modulate = Color(1.0, 0.86, 0.45)
	else:
		_awk_fill.color = Color(lc.r, lc.g, lc.b, 0.9)
		_awk_lab.text = "觉醒 %d%%" % int(a.awaken)
		_awk_lab.modulate = Color(1, 1, 1, 0.7)
