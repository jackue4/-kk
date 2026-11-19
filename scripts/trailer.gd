extends Node
## 宣传片自动演示（-- --trailer）：从炼气一路演到大乘，每阶拍它独有的东西，逐帧存 JPG 到 res://_shots/trailer/
## （f_00000.jpg 起，1280×720），再由 _tasks/trailer/make_video.py 用 cv2 拼成 _shots/trailer.mp4。
## 必须配合 --fixed-fps 30 运行：每帧画面时间固定 1/30s，Combat.fixed_dt 同步改成按帧走，存盘再慢也不会跳帧。
## 无界面录制用 _tasks/trailer/run_hidden.py（headless 只有 dummy 渲染器出不了画面，所以开隐藏窗口渲染）。
## 段落之间用短暂黑场转场遮住回出生点 / 摆位；每段左下角一行字幕点出这一阶的看点；HUD 只留境界条和战斗条。
## 机位都用固定角度或缓慢平移（_pan），不跟鼠标。
## 故意不写 class_name：用 preload 引用。

const Combat := preload("res://scripts/combat.gd")
const Banner := preload("res://scripts/realm_banner.gd")
const Swordsman := preload("res://scripts/swordsman.gd")
const FPS := 30
const W := 1280
const H := 720
const DIR := "res://_shots/trailer/"

var m  # main.gd（不标类型：直接调它的演示辅助函数 _home / _duel_reset / _bot_parry / _wait_event 等）
var player: Player
var cam: CameraRig
var _frame := 0
var _rec := false
var _fade: ColorRect
var _caption: Control
var _cap_title: Label
var _cap_sub: Label
var _card: Label
var _used: Array = []   # 空战已经打过的木桩（每阶换一个靶子，换个方向）


func _ready() -> void:
	player = m.player
	cam = m.cam
	var abs_dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	for f in DirAccess.get_files_at(abs_dir):
		if f.begins_with("f_") and f.ends_with(".jpg"):
			DirAccess.remove_absolute(abs_dir.path_join(f))
	Combat.fixed_dt = 1.0 / FPS
	_build_overlay()
	RenderingServer.frame_post_draw.connect(_grab)
	_run.call_deferred()


func _grab() -> void:
	if not _rec:
		return
	var img := get_viewport().get_texture().get_image()
	if img.get_width() != W or img.get_height() != H:
		img.resize(W, H, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(DIR + "f_%05d.jpg" % _frame, 0.92)
	if _frame % FPS == 0:
		print("[trailer] %ds" % (_frame / FPS))
	_frame += 1


# ---------- 字幕 / 转场 ----------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var brush := Banner._load_font()
	_caption = Control.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_caption.position = Vector2(70, -215)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	layer.add_child(_caption)
	_cap_title = _label(brush, 76, 6)
	_caption.add_child(_cap_title)
	_cap_sub = _label(Vfx.font, 28, 5)
	_cap_sub.position = Vector2(6, 100)
	_caption.add_child(_cap_sub)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_card = _label(brush, 96, 8)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.modulate.a = 0.0
	layer.add_child(_card)


func _label(font: Font, size: int, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.98))
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.08, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 左下角字幕：境界名（毛笔字，染境界色）+ 一行看点
func _say(title: String, sub: String, col: Color) -> void:
	_cap_title.text = title
	_cap_title.add_theme_color_override("font_color", Color.WHITE.lerp(col, 0.45))
	_cap_sub.text = sub
	_caption.modulate.a = 0.0
	_caption.position.x = 40.0
	var tw := _caption.create_tween().set_parallel()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.45)
	tw.tween_property(_caption, "position:x", 70.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unsay() -> void:
	_caption.create_tween().tween_property(_caption, "modulate:a", 0.0, 0.3)


## 黑场转场：压黑 → setup（瞬移、摆机位）→ 亮回来
func _cut(setup: Callable) -> void:
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.2)
	await tw.finished
	setup.call()
	await _w(0.15)
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 0.28)


func _w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 机位缓慢平移到 (yaw, pitch, zoom)，先慢后快再慢
func _pan(yaw1: float, pitch1: float, zoom1: float, dur: float) -> void:
	var y0 := cam.yaw
	var p0 := cam.pitch
	var z0 := cam.zoom
	yaw1 = y0 + wrapf(yaw1 - y0, -PI, PI)
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		var u := smoothstep(0.0, 1.0, clampf(t / dur, 0.0, 1.0))
		cam.yaw = lerpf(y0, yaw1, u)
		cam.pitch = lerpf(p0, pitch1, u)
		cam.zoom = lerpf(z0, zoom1, u)


func _home() -> void:
	m._home()
	player.face_now(0.0)


# ---------- 段落 ----------

func _run() -> void:
	m.swords.auto_attack = false
	cam.focus_yaw = false
	cam.focus_mix = 0.5
	for n in m.get_tree().get_nodes_in_group("swordsmen"):
		if n.get_script() == Swordsman:
			n.ai_enabled = false
			n.block_chance = 0.0
	m.duelist.place(Vector3(0, 0, -16.0), PI)
	cam.snap(PI * 0.86, -0.12, 4.4)
	await _w(1.2)  # 预热：着色器编译、飞剑就位
	_rec = true

	await _intro()
	await _lianqi()
	await _zhuji()
	await _jiedan()
	var subs := {
		3: "紫霄雷法：雷剑折光 · 掌心雷 · 九霄雷引　长按连发「双剑螺旋绞」",
		4: "焚天火法：焚天剑轮 · 三昧火莲 · 金乌坠　长按连发「火轮漩涡」",
		5: "五行遁法：五行剑阵 · 五行轮转 · 五行归一　长按连发「五行剑雨」",
		6: "裂空神通：裂空剑 · 空间裂隙 · 乾坤挪移斩　长按连发「八方裂隙」",
	}
	for idx: int in [3, 4, 5, 6]:
		await _air_realm(idx, subs[idx])
	await _dacheng()
	await _outro()
	_rec = false
	print("[trailer] 共 %d 帧，约 %.1f 秒" % [_frame, float(_frame) / FPS])
	get_tree().quit()


func _intro() -> void:
	_fade.color.a = 1.0
	_card.text = "修仙 · 八境"
	var tw := _card.create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.3)
	tw.tween_property(_card, "modulate:a", 0.0, 0.4)
	await tw.finished
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 0.5)


func _realm_col(idx: int) -> Color:
	return Realm.line_color(Realm.LIST[idx])


## 炼气：三柄飞剑环身 → 万剑齐发 → 地面闪现留残影 → 御剑飞行
func _lianqi() -> void:
	_say("炼气", "三柄飞剑环身 · 万剑齐发 · 闪现留影 · 御剑飞行", _realm_col(0))
	await _pan(PI * 0.6, -0.16, 4.6, 2.6)
	await _cut(func() -> void:
		_home()
		cam.snap(0.0, -0.32, 7.5))
	await _w(0.4)
	m.swords.burst()
	await _w(1.9)
	await _cut(func() -> void:
		_home()
		cam.snap(PI * 0.5, -0.12, 7.5))
	await _w(0.5)
	await m._tap_shift_toward("move_right")
	await _w(1.1)
	await m._tap_shift_toward("move_left")
	await _w(1.1)
	await _cut(func() -> void:
		_home()
		cam.snap(0.35, -0.2, 6.0))
	await _w(0.3)
	player.toggle_flight()
	await _w(0.6)
	Input.action_press("move_forward")
	await _w(3.2)
	Input.action_release("move_forward")
	_unsay()


## 升阶突破：正面机位看聚气 / 破境 / 右侧题字
func _ascend(idx: int, title: String, sub: String) -> void:
	await _cut(func() -> void:
		Input.action_release("move_forward")
		Input.action_release("attack")
		_home()
		m.duelist.demo_reset()
		m.duelist.place(Vector3(0, 0, -16.0), PI)
		cam.snap(PI * 0.82, -0.1, 5.2))
	await _w(0.3)
	player.set_realm(idx)
	await _w(0.5)
	_say(title, sub, _realm_col(idx))
	await _w(2.5)


## 筑基：破境 → 腾空御风 → 三段连斩 → 读招弹反（3D 字）
func _zhuji() -> void:
	await _ascend(1, "筑基", "腾空御风 · 三段连斩 · 读招弹反")
	await _cut(func() -> void:
		_home()
		cam.snap(0.0, -0.2, 6.5))
	await _w(0.3)
	player.toggle_flight()
	await _w(0.6)
	Input.action_press("move_forward")
	await _w(3.0)
	Input.action_release("move_forward")
	var mel = player.melee
	var d: Swordsman = m.duelist
	await _cut(func() -> void:
		player.force_ground()
		d.demo_reset()
		m._duel_reset(2.3)
		cam.snap(1.1, -0.16, 4.8))
	await _w(0.6)
	for i in 3:
		mel.press_attack()
		await _w(0.42 if i < 2 else 1.3)
	await _cut(func() -> void:
		d.demo_reset()
		m._duel_reset(2.1)
		cam.snap(PI * 0.5, -0.1, 4.8))
	await _w(0.8)
	d.force_attack(Swordsman.A.SWEEP)
	await m._bot_parry()
	await _w(1.6)
	_unsay()


## 结丹：破境 → 完美闪避 → 瞬移斩 → 弹反破防 → 处决「斩」→ 碎裂消融 → 空战三段（火球）
func _jiedan() -> void:
	await _ascend(2, "结丹", "完美闪避 · 瞬移斩 · 弹反破防 · 处决碎裂 · 空战火球")
	var mel = player.melee
	var d: Swordsman = m.duelist
	await _cut(func() -> void:
		d.demo_reset()
		m._duel_reset(2.1)
		cam.snap(PI * 0.5, -0.12, 6.0))
	await _w(1.4)
	d.force_attack(Swordsman.A.SWEEP)
	await m._wait_until(func() -> bool: return d.time_to_hit() <= 0.12, 3.0)
	Input.action_press("move_left")
	player.blink()
	Input.action_release("move_left")
	await m._wait_event("perfect_dodge", m._evn("perfect_dodge"), 1.0)
	await _w(0.12)
	mel.press_attack()
	await _w(1.6)

	# 弹反重击：架势本就快满，这一下弹反直接破防；镜头缓缓转到斜前方看处决
	await _cut(func() -> void:
		d.demo_reset()
		m._duel_reset(2.1)
		cam.snap(PI * 0.5, -0.1, 4.8))
	await _w(1.0)
	d.posture = Swordsman.POSTURE_MAX - 12.0
	d.force_attack(Swordsman.A.HEAVY)
	await m._bot_parry()
	await m._wait_until(func() -> bool: return d.is_broken(), 1.5)
	await _pan(0.85, -0.16, 5.0, 0.7)
	await _w(0.2)
	mel.press_attack()
	await _w(2.6)

	# 空战：空格腾空 → 御剑三连刺 → 火球 → 剑火齐发
	await _air_combat(2, 0.0)
	_unsay()


## 选一个地面木桩当靶子，镜头转过去：只挑出生点 -Z 方向开阔处的（其它方向近处有墙挡画面），优先没打过的
func _pick_dummy() -> EnemyDummy:
	var best: EnemyDummy = null
	var best_s := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyDummy
		if e == null or e.kind != 0 or not e.alive:
			continue
		var dv := e.global_position - player.global_position
		var dd := Vector2(dv.x, dv.z).length()
		if dd < 9.0 or dd > 24.0 or -dv.z < absf(dv.x) * 0.9:
			continue
		var s := dd + (100.0 if _used.has(e) else 0.0)
		if s < best_s:
			best_s = s
			best = e
	if best != null:
		_used.append(best)
	return best


## 空战：转向靶子 → 腾空 → 法术三段 → 长按连发 volley 秒
func _air_combat(idx: int, volley: float) -> void:
	var tgt := _pick_dummy()
	var yaw := cam.yaw
	if tgt != null:
		var dv := tgt.global_position - player.global_position
		yaw = atan2(-dv.x, -dv.z)
	await _pan(yaw, CameraRig.PITCH_DEFAULT, 6.5, 0.8)
	player.take_air()
	await _w(0.6)
	var c = player.caster
	c.press_attack()
	await _w(0.55)
	c.press_attack()
	await _w(0.6)
	if tgt != null and idx <= 2:
		tgt.hp = minf(tgt.hp, 90.0)  # 低阶伤害不够：让第三段把木桩打碎，看碎裂
	c.press_attack()
	await _w(1.7)
	if volley > 0.0:
		Input.action_press("attack")
		await _w(volley)
		Input.action_release("attack")
		await _w(0.9)


## 元婴 ~ 合体：破境 → 空战三段 → 长按连发队形
func _air_realm(idx: int, sub: String) -> void:
	var nm: String = Realm.LIST[idx]["name"]
	await _ascend(idx, nm, sub)
	await _air_combat(idx, 2.6)
	_unsay()


## 大乘：破境 → 空战三段 → 暴雨梨花 → R 大罡剑阵
func _dacheng() -> void:
	await _ascend(7, "大乘", "万剑归宗 · 暴雨梨花 · R「大罡剑阵」")
	await _air_combat(7, 3.0)
	await _w(0.3)
	player.ult.try_cast()
	await _w(0.2)
	await m._wait_until(func() -> bool: return not player.ult.active, 8.0)
	await _w(1.4)


func _outro() -> void:
	_unsay()
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	await tw.finished
	_card.text = "炼气 → 大乘"
	tw = _card.create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.6)
	tw.tween_property(_card, "modulate:a", 0.0, 0.5)
	await tw.finished
	await _w(0.2)
