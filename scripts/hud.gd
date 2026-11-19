class_name Hud
extends CanvasLayer
## 调试 HUD：境界条、飞行方式、飞剑阵状态、速度、灵力条、操作说明；升阶时右侧的毛笔题字见 realm_banner.gd。

const RealmBanner := preload("res://scripts/realm_banner.gd")
const AirCaster := preload("res://scripts/air_caster.gd")

var font: Font
var trailer := false  # 宣传片录制：只留境界条、境界名和战斗条，藏掉调试信息与操作说明
var _realm_fx: Control
var _strip: Array[Label] = []
var _title: Label
var _info: Label
var _speed: Label

# 近战：玩家生命/架势（底部），当前目标生命/架势（右上）；"弹反""破防""斩"等短提示改成 3D 字（combat_word.gd）
var _combat: Control
var _p_hp: ColorRect
var _p_hp_lag: ColorRect
var _p_pst: ColorRect
var _p_hp_txt: Label
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
# 灵力（蓝量）条：底部居中，空战中或灵力没满时显示
var _mp_root: Control
var _mp_bar: ColorRect
var _mp_txt: Label


func _ready() -> void:
	layer = 10
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 22)
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	root.theme = th
	add_child(root)

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
		"WASD 移动　鼠标 视角（飞行时低头下降、抬头上升）　滚轮 镜头距离　空格 跳跃 / 腾空空战(结丹起)　"
		+ "Shift 短按闪现 · 长按疾行/疾遁（出招/受击/施法中按下即闪，可打断任何动作）\n"
		+ "Q 飞剑阵（起手耗 12% 灵力、开着每秒耗 3.5%，持续 20s，再按收起）　F 起飞/降落（空战中 F 转光遁）　E 万剑齐发(需先 Q 召剑)　G 自动出剑开关\n"
		+ "R 大罡剑阵（大乘专属，耗 50% 灵力，地面 / 空战可放）　1-8 或 [ ] 切换境界　Backspace 回出生点　Esc 释放鼠标", 16)
	help.modulate = Color(1, 1, 1, 0.85)
	col.add_child(help)
	var chelp := _mk(
		"近战：J / 左键 三段连招　K / 右键 点按弹反 · 按住格挡　敌人破防后 J 处决　炼气/筑基：空格跳起 → J 空中斩（最多两段）\n"
		+ "结丹起空战：空格腾空 → 点按 J / 左键 法术三段：御剑三连刺 → 火球 → 剑火齐发；"
		+ "长按 J / 左键 万剑连发（持续耗灵力）；往下飞碰到地面即落地", 17)
	chelp.add_theme_color_override("font_color", Color(1.0, 0.9, 0.72))
	col.add_child(chelp)
	for n: Control in [_info, _speed, help, chelp]:
		n.visible = not trailer
	_build_combat()
	_cross = Control.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_realm_fx = RealmBanner.new()
	add_child(_realm_fx)
	_build_mp()


func _build_mp() -> void:
	_mp_root = Control.new()
	_mp_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = font
	_mp_root.theme = th
	add_child(_mp_root)
	_mp_bar = _bar(_mp_root, Vector2.ZERO, Vector2(360, 8), Color(0.35, 0.62, 1.0))
	_mp_txt = _mk("", 15)
	_mp_root.add_child(_mp_txt)


## 灵力条：不够起手连发时闪红
func _refresh_mp(p: Player) -> void:
	var r := p.mp / p.mp_max()
	_mp_root.visible = p.st == Player.St.AIR or r < 0.999
	if not _mp_root.visible:
		return
	var vs := get_viewport().get_visible_rect().size
	var x := vs.x * 0.5 - 180.0
	var y := vs.y - 120.0
	(_mp_bar.get_parent() as Control).position = Vector2(x, y)
	_set_bar(_mp_bar, r)
	var low := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02) if p.mp < AirCaster.MP_START else 0.0
	_mp_bar.color = Color(0.35, 0.62, 1.0).lerp(Color(1.0, 0.35, 0.3), low)
	_mp_txt.position = Vector2(x - 110.0, y - 8.0)
	_mp_txt.text = "灵力 %d/%d" % [int(p.mp), int(p.mp_max())]


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
	var locked := p.caster.aim_target() != null
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

	# 玩家：底部居中，上面一条细长生命、下面一条从中间向两边涨的架势
	_p_hp_lag = _bar(_combat, Vector2.ZERO, Vector2(420, 9), Color(1.0, 0.92, 0.85, 0.85))
	_p_hp = _bar(_p_hp_lag.get_parent() as Control, Vector2.ZERO, Vector2(420, 9), Color(0.86, 0.2, 0.18), false, false)
	_p_pst = _bar(_combat, Vector2.ZERO, Vector2(420, 8), Color(1.0, 0.7, 0.3), true)
	_p_hp_txt = _mk("", 15)
	_combat.add_child(_p_hp_txt)
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
	_t_hp_lag = _bar(_tgt, Vector2(0, 56), Vector2(360, 9), Color(1.0, 0.92, 0.85, 0.85))
	_t_hp = _bar(_t_hp_lag.get_parent() as Control, Vector2.ZERO, Vector2(360, 9), Color(0.86, 0.2, 0.18), false, false)
	_t_pst = _bar(_tgt, Vector2(0, 72), Vector2(360, 8), Color(1.0, 0.7, 0.3), true)
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
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.06, 0.08, 0.6)
		bg.position = pos
		bg.size = size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bg)
		host = bg
		if centered:
			var notch := ColorRect.new()
			notch.color = Color(1, 1, 1, 0.35)
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
	return Color(1.0, 0.78, 0.35).lerp(Color(1.0, 0.22, 0.12), smoothstep(0.45, 0.95, r))


func _refresh_combat(p: Player) -> void:
	var m := p.melee
	var vs := get_viewport().get_visible_rect().size
	var vis := p.st == Player.St.GROUND and m.engaged()
	_combat.visible = vis
	for n: Control in [_p_hp_lag.get_parent(), _p_pst.get_parent(), _p_hp_txt, _p_pst_lab]:
		n.visible = vis
	if vis:
		var x := vs.x * 0.5 - 210.0
		var y := vs.y - 168.0
		(_p_hp_lag.get_parent() as Control).position = Vector2(x, y)
		(_p_pst.get_parent() as Control).position = Vector2(x, y + 18.0)
		_p_hp_txt.position = Vector2(x - 120.0, y - 7.0)
		_p_hp_txt.text = "生命 %d" % int(ceil(m.hp))
		_p_pst_lab.position = Vector2(x + 430.0, y + 9.0)
		_set_bar(_p_hp, m.hp_ratio())
		_set_bar(_p_hp_lag, lerpf(_p_hp_lag.size.x / 420.0, m.hp_ratio(), 0.04) if _p_hp_lag.size.x / 420.0 > m.hp_ratio() else m.hp_ratio())
		_set_bar(_p_pst, m.posture_ratio())
		_p_pst.color = _posture_col(m.posture_ratio())

	var t := m.target
	_tgt.visible = vis and t != null and is_instance_valid(t)
	if _tgt.visible:
		_tgt.position = Vector2(vs.x - 22.0 - 360.0, 150.0)
		_t_name.text = str(t.get("display_name"))
		_t_state.text = t.state_name()
		_set_bar(_t_hp, t.hp_ratio())
		var lag := _t_hp_lag.size.x / 360.0
		_set_bar(_t_hp_lag, lerpf(lag, t.hp_ratio(), 0.04) if lag > t.hp_ratio() else t.hp_ratio())
		_set_bar(_t_pst, t.posture_ratio())
		_t_pst.color = _posture_col(t.posture_ratio())
		_hint.text = "破绽！按 J / 左键 处决" if t.is_broken() else ""


func _mk(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.98))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.11, 0.13, 0.9))
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
	var spell_txt := "空战法术：结丹起"
	if Realm.art(r) > 0:
		spell_txt = "空战法术：%s　长按连发：%s %d 柄/秒" % [" · ".join(PackedStringArray(art["stages"])), art["volley"], int(r["volley"])]
	_info.text = "飞行方式：%s\n飞剑阵：%s　阵型 %s · %s　出剑间隔 %.2fs　连斩 %d　索敌 %dm　自动出剑：%s\n%s\n遁速上限：%d m/s　闪现：%s　状态：%s" % [
		r["flight"], sw_txt, art["form"], art["strike"], float(r["atk_cd"]), int(r["chain"]), int(r["range"]),
		"开" if sm.auto_attack else "关", spell_txt, int(r["speed"]), blink_txt, p.state_text()]
	_speed.text = "%d m/s　高度 %dm" % [int(round(p.speed())), int(round(p.global_position.y))]
	_speed.modulate.a = 1.0 if p.st != Player.St.GROUND else 0.0
	_refresh_combat(p)
	_refresh_cross(p)
	_refresh_mp(p)
