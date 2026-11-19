extends CanvasLayer
## 手机触屏操作层：左半屏虚拟摇杆（按下处即摇杆中心）、右半屏空白处拖动转镜头、右下一组按钮。
## 按钮只是把对应的输入动作按下 / 松开（Input.parse_input_event + InputEventAction），
## 所以长按蓄力、按住护体、按住聚气、短按闪现 / 长按疾行这些逻辑和键盘完全一致，不另写一套。
## 按钮按场合显示：空战才有的（剑诀、飞剑、对波、聚气）落地后收起；冷却中的按钮画一圈进度。
## 触屏设备上自动启用；桌面调试加命令行参数 `-- --touch`（鼠标当手指用）。
## 故意不写 class_name：用 preload 引用。

const LOOK_SENS := 0.0052
const STICK_R := 110.0

## id | 字 | 动作 | 相对角的偏移 | 半径 | 场合（all / air / ground）| 锚点（br 右下 / tr 右上）
const BUTTONS := [
	{"id": "attack", "text": "攻", "action": "attack", "off": Vector2(-165, -165), "r": 86.0, "mode": "all", "anchor": "br"},
	{"id": "guard", "text": "御", "action": "guard", "off": Vector2(-335, -105), "r": 58.0, "mode": "all", "anchor": "br"},
	{"id": "dash", "text": "闪", "action": "sprint", "off": Vector2(-100, -335), "r": 54.0, "mode": "all", "anchor": "br"},
	{"id": "jump", "text": "腾", "action": "jump", "off": Vector2(-240, -345), "r": 54.0, "mode": "all", "anchor": "br"},
	{"id": "beam", "text": "波", "action": "beam", "off": Vector2(-360, -250), "r": 54.0, "mode": "air", "anchor": "br"},
	{"id": "gather", "text": "聚", "action": "gather", "off": Vector2(-480, -140), "r": 48.0, "mode": "air", "anchor": "br"},
	{"id": "shot", "text": "剑", "action": "air_shot", "off": Vector2(-470, -290), "r": 46.0, "mode": "air", "anchor": "br"},
	{"id": "s1", "text": "一", "action": "skill_1", "off": Vector2(-95, -470), "r": 44.0, "mode": "air", "anchor": "br"},
	{"id": "s2", "text": "二", "action": "skill_2", "off": Vector2(-205, -480), "r": 44.0, "mode": "air", "anchor": "br"},
	{"id": "s3", "text": "三", "action": "skill_3", "off": Vector2(-315, -440), "r": 44.0, "mode": "air", "anchor": "br"},
	{"id": "fly", "text": "遁", "action": "fly", "off": Vector2(-80, 262), "r": 40.0, "mode": "all", "anchor": "tr"},
	{"id": "summon", "text": "阵", "action": "summon", "off": Vector2(-180, 262), "r": 40.0, "mode": "all", "anchor": "tr"},
	{"id": "bag", "text": "包", "action": "bag", "off": Vector2(-280, 262), "r": 40.0, "mode": "all", "anchor": "tr"},
	{"id": "rp", "text": "境-", "action": "realm_prev", "off": Vector2(-180, 90), "r": 36.0, "mode": "all", "anchor": "tr"},
	{"id": "rn", "text": "境+", "action": "realm_next", "off": Vector2(-80, 90), "r": 36.0, "mode": "all", "anchor": "tr"},
]

var player: Player
var cam: CameraRig
var font: Font

## 正式关卡（搜打撤）：不摆满屏按钮。调试用的（阵、境±）收掉；空战的进阶按钮（波、聚、剑、三式剑诀）
## 只在腾空且附近有敌人时才浮出来，平时只有 摇杆 + 攻 / 御 / 闪 / 腾 + 遁 / 包。
var compact := false
var _foe_near := false
var _foe_t := 0.0
var blocked := false    # 背包等面板打开时：不接管触摸（让面板上的按钮收到点击）
var _pad: Control
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_idx := -1
var _held := {}          # 触点序号 → 按钮下标
var _down := {}          # 按钮下标 → true


func _ready() -> void:
	layer = 20
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)


func _size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _btn_pos(b: Dictionary) -> Vector2:
	var vs := _size()
	var off: Vector2 = b["off"]
	if str(b["anchor"]) == "tr":
		return Vector2(vs.x + off.x, off.y)
	return vs + off


func _btn_on(b: Dictionary) -> bool:
	var air := player != null and player.st == Player.St.AIR
	if compact:
		var id := str(b["id"])
		if id == "summon" or id == "rp" or id == "rn":
			return false
		if str(b["mode"]) == "air":
			return air and _foe_near
	match str(b["mode"]):
		"air":
			return air
		"ground":
			return not air
	return true


func _fire(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _input(e: InputEvent) -> void:
	if blocked:
		if _stick_idx >= 0 or not _held.is_empty():
			_release_all()
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _stick_idx:
			_set_stick((d.position - _stick_origin) / STICK_R)
		elif d.index == _look_idx and cam != null:
			cam.yaw -= d.relative.x * LOOK_SENS
			cam.pitch = clampf(cam.pitch - d.relative.y * LOOK_SENS, CameraRig.PITCH_MIN, CameraRig.PITCH_MAX)
			cam.touch_look()
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, pos: Vector2) -> void:
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if _btn_on(b) and pos.distance_to(_btn_pos(b)) <= float(b["r"]) * 1.15:
			_held[idx] = i
			_down[i] = true
			_fire(b["action"], true)
			return
	var vs := _size()
	if _stick_idx < 0 and pos.x < vs.x * 0.42 and pos.y > vs.y * 0.25:
		_stick_idx = idx
		_stick_origin = pos
		_set_stick(Vector2.ZERO)
	elif _look_idx < 0:
		_look_idx = idx


func _touch_up(idx: int) -> void:
	if _held.has(idx):
		var i: int = _held[idx]
		_held.erase(idx)
		_down.erase(i)
		_fire(BUTTONS[i]["action"], false)
	if idx == _stick_idx:
		_stick_idx = -1
		_set_stick(Vector2.ZERO)
	if idx == _look_idx:
		_look_idx = -1


func _release_all() -> void:
	for idx: int in _held.keys():
		_fire(BUTTONS[int(_held[idx])]["action"], false)
	_held.clear()
	_down.clear()
	_stick_idx = -1
	_look_idx = -1
	_set_stick(Vector2.ZERO)


## 摇杆 → 四个移动动作的力度
func _set_stick(v: Vector2) -> void:
	_stick_vec = v.limit_length(1.0)
	var s := _stick_vec if _stick_vec.length() > 0.16 else Vector2.ZERO
	_axis("move_right", maxf(s.x, 0.0))
	_axis("move_left", maxf(-s.x, 0.0))
	_axis("move_back", maxf(s.y, 0.0))
	_axis("move_forward", maxf(-s.y, 0.0))


func _axis(action: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(action, v)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _process(dt: float) -> void:
	_pad.queue_redraw()
	if compact and player != null:
		_foe_t -= dt
		if _foe_t <= 0.0:
			_foe_t = 0.3
			_foe_near = false
			var p := player.global_position
			for n: Node in get_tree().get_nodes_in_group("air_foes"):
				var n3 := n as Node3D
				if n3 != null and n3.global_position.distance_to(p) < 42.0 and n3.has_method("is_alive") and bool(n3.call("is_alive")):
					_foe_near = true
					break


## 按钮上的冷却比例（0 = 可用）和是否可用
func _btn_state(id: String) -> Vector2:
	if player == null:
		return Vector2(0.0, 1.0)
	var a := player.air
	match id:
		"s1", "s2", "s3":
			var k := int(id.substr(1)) - 1
			return Vector2(a.cds[k] / float(a.SKILL_CD[k]), 1.0 if a.skill_ready(k) else 0.0)
		"beam":
			return Vector2(a.beam_cd / a.BEAM_CD, 1.0 if a.beam_ready() else 0.0)
		"shot":
			return Vector2(0.0, 1.0 if player.mp >= a.SHOT_MP else 0.0)
	return Vector2(0.0, 1.0)


func _draw_pad() -> void:
	if blocked:
		return
	var lc := Realm.line_color(player.realm) if player != null else Color(0.4, 0.7, 1.0)
	# 摇杆
	var vs := _size()
	var base := _stick_origin if _stick_idx >= 0 else Vector2(210.0, vs.y - 210.0)
	_pad.draw_circle(base, STICK_R, Color(0.05, 0.06, 0.08, 0.28))
	_pad.draw_arc(base, STICK_R, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	_pad.draw_circle(base + _stick_vec * STICK_R * 0.75, 46.0, Color(1, 1, 1, 0.5 if _stick_idx >= 0 else 0.28))
	# 按钮
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if not _btn_on(b):
			continue
		var c := _btn_pos(b)
		var r: float = b["r"]
		var st := _btn_state(str(b["id"]))
		var on := _down.has(i)
		var clash: bool = str(b["id"]) == "attack" and player != null and player.air.in_clash()
		var fill := Color(lc.r, lc.g, lc.b, 0.55) if on else Color(0.05, 0.06, 0.08, 0.42)
		if clash:
			fill = Color(1.0, 0.8, 0.3, 0.55 + 0.3 * sin(Time.get_ticks_msec() * 0.03))
		_pad.draw_circle(c, r, fill)
		_pad.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.75 if st.y > 0.5 else 0.25), 3.0, true)
		if st.x > 0.0:
			_pad.draw_arc(c, r - 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(st.x, 0.0, 1.0), 40, Color(lc.r, lc.g, lc.b, 0.9), 6.0, true)
		if font != null:
			var txt: String = "连点" if clash else str(b["text"])
			if str(b["id"]) == "jump" and player != null and player.st != Player.St.AIR and not player.is_light_mode():
				txt = "跳"
			var fs := int(r * (0.62 if txt.length() <= 1 else 0.42))
			var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			_pad.draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 1, 1, 0.95 if st.y > 0.5 else 0.45))
