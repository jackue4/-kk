extends Node3D
## 入口：注册输入、搭建大厅、生成角色/相机/飞剑/木人桩/刀客/后处理/HUD。
## 命令行追加 `-- --shot` 会跑一段自动演示并截图到 res://_shots（3C 回归）；
## `-- --combat-shot` 跑近战演示（三连击、命中顿刀与碎块、弹反对刃、破防处决、跳斩、空中弹反）
## 并截图到 res://_shots/combat_feel_*。
## `-- --fx-shot` 跑飞行表现演示（筑基风丝、化身光剑起飞/巡航/现形、闪现）并截图到 res://_shots/fx_*。
## `-- --hitfx-shot` 把飞剑命中、近战分档命中、弹反、死亡特效并排放一遍并截图到 res://_shots/hitfx_*。
## `-- --air-shot` 跑 Shift 短按闪现 / 长按疾行、炼气残影闪现、结丹空格腾空与法术三段、俯冲落地，截图到 res://_shots/air_*。
## `-- --trailer` 录宣传片：炼气→大乘逐阶演示，逐帧存到 res://_shots/trailer/（见 trailer.gd，需配合 --fixed-fps 30）。
## `-- --realm-shot` 跑升阶突破（右侧毛笔题字 + 各境界突破特效）、完美闪避 → 瞬移斩、敌人碎裂消融，截图到 res://_shots/realm_*。
## `-- --boss-test` 剑冢 Boss 空战自检：走进剑冢 → 开战 → 打进二、三阶段 → 中弹 → 击败，打印各阶段弹数和状态；
## 有渲染时（非 --headless）顺带截图到 res://_shots/boss_*。
## `-- --meadow-shot` 跑择境传送门 → 选关 → 木兰草原：出生点、草地近景、低空 / 高空飞行、大乘高速巡航时的流式加载统计，
## 最后穿回程门回大厅；截图到 res://_shots/meadow_*。
##
## `-- --duel-shot` 跑空战斗法演示（R15 定妆、五段追身连击、击飞 → 瞬身追击 → 陨落砸地、蓄力崩拳、追身突进、
## 瞬身 / 护体 / 挨打、飞剑点射与三式剑诀），打印各步结算并截图到 res://_shots/duel_*。
##
## `-- --raid-shot` 跑搜打撤自检（进木兰草原 → 各区域风格 / 小怪 / Boss / 其他修士 → 拾取、背包、服丹 → 传送阵撤离结算），
## 打印各步状态和帧率并截图到 res://_shots/raid_*；加 `--touch` 看手机布局和手机画质档。
##
## 大厅西侧的择境传送门（level_portal.gd）：走进去弹出关卡选择（level_select.gd），选中后黑场切到关卡
## （目前只有木兰草原 meadow_level.gd）。切关时大厅整体停用（隐藏、停处理、关碰撞、敌人移出索敌分组），回来原样恢复。

const BLUR_SHADER := preload("res://shaders/speed_blur.gdshader")
const Swordsman := preload("res://scripts/swordsman.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const CombatWord := preload("res://scripts/combat_word.gd")
const Trailer := preload("res://scripts/trailer.gd")
const BossArena := preload("res://scripts/boss_arena.gd")
const MeadowGen := preload("res://scripts/meadow_gen.gd")
const MeadowLevel := preload("res://scripts/meadow_level.gd")
const MeadowPreview := preload("res://scripts/meadow_preview.gd")
const LevelPortal := preload("res://scripts/level_portal.gd")
const LevelSelect := preload("res://scripts/level_select.gd")
const AirFoe := preload("res://scripts/air_foe.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const FEEL := "combat_feel_"  # 近战演示截图前缀（不覆盖 3C 回归图和上一轮的 combat_ 图）
const FX := "fx_"             # 飞行表现演示截图前缀
const HITFX := "hitfx_"       # 打击特效对照截图前缀
const AIR := "air_"           # Shift 闪现 / 空战法术演示截图前缀

var player: Player
var cam: CameraRig
var swords: SwordManager
var hud: Hud
var duelist: Swordsman
var foe: AirFoe          # 空战对手（魔修）
var sandbag: AirFoe      # 空战陪练木人（不还手）
var _duel_demo := false
var rival: AirFoe        # 真人陪练（真人式打法的 NPC）
var touch: TouchControls
var _raid_demo := false
var _touch := false      # 手机触屏模式（触屏设备自动开；桌面调试加 --touch）
var arena: BossArena
var hall: TestHall
var hall_portal: LevelPortal
var level: MeadowLevel
var level_ui: LevelSelect
var font: Font
var _hall_root: Node3D
var _hall_groups: Array = []   # 停用大厅时移出索敌分组的 [节点, 分组名]
var _switching := false
var _meadow_demo := false
var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _autotest := false
var _combat_demo := false
var _fx_demo := false
var _hitfx_demo := false
var _air_demo := false
var _realm_demo := false
var _trailer := false
var _boss_test := false
var _evc: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_autotest = args.has("--shot")
	_combat_demo = args.has("--combat-shot")
	_fx_demo = args.has("--fx-shot")
	_hitfx_demo = args.has("--hitfx-shot")
	_air_demo = args.has("--air-shot")
	_realm_demo = args.has("--realm-shot")
	_trailer = args.has("--trailer")
	_boss_test = args.has("--boss-test")
	_meadow_demo = args.has("--meadow-shot")
	_duel_demo = args.has("--duel-shot")
	_raid_demo = args.has("--raid-shot")
	_touch = args.has("--touch") or DisplayServer.is_touchscreen_available()
	_setup_input()
	Sfx.root = self
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "SimHei"])
	Vfx.font = font

	_hall_root = Node3D.new()
	_hall_root.name = "HallRoot"
	add_child(_hall_root)
	hall = TestHall.new()
	hall.font = font
	_hall_root.add_child(hall)

	var vfx := Node3D.new()
	vfx.name = "Vfx"
	add_child(vfx)
	Vfx.root = vfx

	cam = CameraRig.new()
	cam.touch_mode = _touch
	cam.capture_mouse = not (_raid_demo or _touch or _duel_demo or _autotest or _combat_demo or _fx_demo or _hitfx_demo or _air_demo or _realm_demo or _trailer or _boss_test or _meadow_demo)
	add_child(cam)

	player = Player.new()
	player.cam = cam
	player.vfx_root = vfx
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	cam.target = player

	# 老演示（--air-shot / 宣传片 / Boss 自检）里"按住攻击键 = 连发"照旧
	player.caster.demo_hold_attack = _air_demo or _trailer or _boss_test or _autotest or _realm_demo

	swords = SwordManager.new()
	swords.player = player
	add_child(swords)

	_spawn_enemies()
	# 3C 回归 / 飞行表现截图不放刀客，保证画面干净、与上一轮一致
	if not (_autotest or _fx_demo or _hitfx_demo or _air_demo):
		_spawn_duelists()
	# 空战对手：老的回归截图里不放
	if not (_autotest or _fx_demo or _hitfx_demo or _air_demo or _combat_demo or _realm_demo or _trailer or _boss_test or _meadow_demo):
		_spawn_air_foes()
	_build_postfx()

	hud = Hud.new()
	hud.font = font
	hud.trailer = _trailer
	hud.touch = _touch
	add_child(hud)
	if _touch:
		# 桌面调试：鼠标当手指
		if not DisplayServer.is_touchscreen_available():
			Input.emulate_touch_from_mouse = true
		touch = TouchControls.new()
		touch.player = player
		touch.cam = cam
		touch.font = font
		add_child(touch)

	# 剑冢 Boss 空战（大厅东侧，见 boss_arena.gd）
	arena = BossArena.new()
	arena.player = player
	arena.cam = cam
	arena.hud = hud
	arena.font = font
	_hall_root.add_child(arena)

	# 择境传送门 + 关卡选择（老的回归截图 / 演示里不放，画面和以前一致）
	level_ui = LevelSelect.new()
	level_ui.font = font
	add_child(level_ui)
	level_ui.picked.connect(_enter_level)
	level_ui.closed.connect(_on_menu_closed)
	if not (_duel_demo or _autotest or _fx_demo or _hitfx_demo or _air_demo or _combat_demo or _realm_demo or _trailer or _boss_test):
		hall_portal = LevelPortal.new()
		hall_portal.name = "HallPortal"
		hall_portal.font = font
		hall_portal.title = "择 境 门"
		hall_portal.subtitle = "木兰草原"
		hall_portal.position = TestHall.PORTAL_POS
		hall_portal.rotation.y = PI * 0.5   # 门口朝 +X（出生点）
		hall_portal.preview_eye = MeadowPreview.eye()
		var pgen := MeadowGen.new()
		hall_portal.preview_floor = func(x: float, z: float) -> float: return pgen.height(x, z)
		hall_portal.preview_builder = func(vp: SubViewport) -> void: vp.add_child(MeadowPreview.new())
		hall_portal.entered.connect(_open_level_select)
		_hall_root.add_child(hall_portal)

	player.realm_changed.connect(_on_realm_changed)
	player.realm_ascended.connect(func(_i: int) -> void: hud.realm_up(player.realm))
	player.dun_changed.connect(swords.set_cloaked)  # 遁光：飞剑本体随主角一起隐藏/恢复
	player.melee.combat_event.connect(_on_combat_event)
	player.set_realm(0, false)
	if _autotest or _combat_demo or _fx_demo or _hitfx_demo or _air_demo or _realm_demo or _trailer:
		swords.summon(true, true)  # 演示沿用以前"飞剑常驻"的画面
	if _autotest:
		_run_autotest()
	elif _combat_demo:
		_run_combat_demo()
	elif _fx_demo:
		_run_fx_demo()
	elif _hitfx_demo:
		_run_hitfx_demo()
	elif _air_demo:
		_run_air_demo()
	elif _realm_demo:
		_run_realm_demo()
	elif _boss_test:
		_run_boss_test()
	elif _meadow_demo:
		_run_meadow_demo()
	elif _duel_demo:
		_run_duel_demo()
	elif _raid_demo:
		_run_raid_demo()
	elif _trailer:
		var tr := Trailer.new()
		tr.m = self
		add_child(tr)


func _on_realm_changed(_idx: int) -> void:
	swords.apply_realm(player.realm)


## 战斗字：3D 发光毛笔字立在角色身边（见 combat_word.gd），敌方状态写在敌人头顶，自己的写在主角头顶
func _on_combat_event(kind: String, info: Dictionary) -> void:
	_evc[kind] = int(_evc.get(kind, 0)) + 1
	var head := player.center() + Vector3.UP * 1.35
	match kind:
		"parry":
			CombatWord.pop("弹反", info.get("contact", head) + Vector3.UP * 1.0, Color(1.0, 0.78, 0.35))
		"enemy_break":
			CombatWord.pop("破防", info.get("pos", head) + Vector3.UP * 1.45, Color(1.0, 0.32, 0.22), 1.1)
		"execute":
			CombatWord.pop("斩", info.get("pos", head) + Vector3.UP * 1.3, Color(1.0, 0.18, 0.14), 1.6)
		"self_broken":
			CombatWord.pop("架势崩溃", head, Color(1.0, 0.5, 0.25), 0.8)
		"recoiled":
			CombatWord.pop("被弹开", head, Color(0.7, 0.8, 1.0), 0.8)
		# ---- 空战斗法（air_melee.gd / air_foe.gd）----
		"air_launch":
			var w: String = {"fwd": "崩", "up": "挑", "down": "陨"}.get(str(info.get("kind", "fwd")), "崩")
			CombatWord.pop(w, (info.get("pos", head) as Vector3) + Vector3.UP * 1.6, Color(1.0, 0.82, 0.4), 1.3)
		"air_chase":
			CombatWord.pop("瞬身追击", head, Realm.line_color(player.realm).lerp(Color.WHITE, 0.4), 0.8)
		"air_vanish":
			CombatWord.pop("瞬身", head, Color(0.75, 0.9, 1.0), 1.1)
		"air_break":
			CombatWord.pop("破", (info.get("pos", head) as Vector3) + Vector3.UP * 1.4, Color(1.0, 0.32, 0.22), 1.1)
		"air_crash":
			if bool(info.get("ground", true)):
				CombatWord.pop("坠", (info.get("pos", head) as Vector3) + Vector3.UP * 2.6, Color(1.0, 0.6, 0.3), 1.5)
		"air_kill":
			CombatWord.pop("斩", (info.get("pos", head) as Vector3) + Vector3.UP * 1.3, Color(1.0, 0.18, 0.14), 1.6)
		"air_skill":
			CombatWord.pop(str(info.get("name", "")), head + Vector3.UP * 0.3, Realm.line_color(player.realm).lerp(Color.WHITE, 0.3), 0.9)
		"air_clash":
			CombatWord.pop("对波", (info.get("pos", head) as Vector3) + Vector3.UP * 2.2, Color(1.0, 0.85, 0.4), 1.6)
		"air_clash_end":
			var won := bool(info.get("win", false))
			CombatWord.pop("破" if won else "溃", (info.get("pos", head) as Vector3) + Vector3.UP * 1.8,
					Color(1.0, 0.82, 0.4) if won else Color(1.0, 0.3, 0.25), 1.6)
		"air_awaken":
			CombatWord.pop("觉醒", head + Vector3.UP * 0.4, Realm.line_color(player.realm).lerp(Color.WHITE, 0.3), 1.6)
		"air_hurt":
			if bool(info.get("dead", false)):
				CombatWord.pop("败", head, Color(1.0, 0.25, 0.22), 1.4)


# ---------- 输入 ----------

func _setup_input() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	# Shift：短按闪现，长按疾行 / 疾遁（见 Player._unhandled_input）
	_key("sprint", KEY_SHIFT)
	_key("fly", KEY_F)
	_key("toggle_auto", KEY_G)
	_key("summon", KEY_Q)  # 飞剑阵技能：逐柄召出 → 自动索敌；再按收起
	_key("ult", KEY_R)  # 大罡剑阵（大乘专属，见 gate_array.gd）
	_key("reset", KEY_BACKSPACE)  # 回出生点（R 让给大罡剑阵）
	_key("realm_prev", KEY_BRACKETLEFT)
	_key("realm_next", KEY_BRACKETRIGHT)
	# 万剑齐发：E；左键在空中照旧是万剑齐发，在地面归近战（见 SwordManager）
	_key("burst", KEY_E)
	_mouse("burst", MOUSE_BUTTON_LEFT)
	# 近战：攻击 J / 左键；格挡·弹反 K / 右键
	_key("attack", KEY_J)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_key("guard", KEY_K)
	_mouse("guard", MOUSE_BUTTON_RIGHT)
	# 空战：E 飞剑点射 / 长按连发；Z X C 三式剑诀（见 air_melee.gd）
	_key("air_shot", KEY_E)
	_key("skill_1", KEY_Z)
	_key("skill_2", KEY_X)
	_key("skill_3", KEY_C)
	# 对波光柱 T；聚气（按住回灵力、攒觉醒槽，满了继续按 = 觉醒）V
	_key("beam", KEY_T)
	_key("gather", KEY_V)
	_key("bag", KEY_B)   # 搜打撤：背包


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	InputMap.action_add_event(action, mb)


func _key(action: String, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("realm_prev"):
		player.set_realm(player.realm_idx - 1)
	elif e.is_action_pressed("realm_next"):
		player.set_realm(player.realm_idx + 1)
	elif e.is_action_pressed("reset"):
		player.force_ground()
		player.global_position = level.spawn_point() if level != null else Vector3(0, 0.1, 0)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_8:
			player.set_realm(k - KEY_1)


# ---------- 木人桩 ----------

func _enemy(pos: Vector3, kind: int) -> void:
	var e := EnemyDummy.new()
	e.kind = kind
	e.position = pos
	_hall_root.add_child(e)


func _spawn_enemies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 地面一圈
	for i in 10:
		var a := TAU * i / 10.0 + 0.3
		var r := rng.randf_range(8.0, 15.0)
		_enemy(Vector3(cos(a) * r, 0, sin(a) * r - 4.0), 0)
	# 近处浮空
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 38.0)
		_enemy(Vector3(cos(a) * r, rng.randf_range(5.0, 32.0), sin(a) * r), 1)
	# 巡游
	_enemy(Vector3(0, 2.0, -24.0), 2)
	_enemy(Vector3(18, 12.0, -6.0), 2)
	_enemy(Vector3(-18, 8.0, 6.0), 2)
	# 长廊上空：空战靶
	var z := 60.0
	while z <= 660.0:
		_enemy(Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(15.0, 60.0), -z), 1)
		_enemy(Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(15.0, 60.0), -z - 20.0), 1)
		z += 60.0


## 空战对手：出生点左前方半空一个不还手的陪练木人；右前方远处高空一个会追打、放剑气的魔修
func _spawn_air_foes() -> void:
	sandbag = _air_foe(Vector3(-9.0, 7.0, -13.0), "陪练木人", false, 1, 1500.0)
	foe = _air_foe(Vector3(20.0, 11.0, -34.0), "魔修·厉无咎", true, 0, 900.0)
	# 真人陪练：打法照着真人玩家来（连段、击飞追击、瞬身反打、对波），在出生点正后方的半空
	rival = _air_foe(Vector3(6.0, 9.0, 26.0), "陪练·青禾", true, 2, 1600.0)
	rival.pro = true
	rival.qi = Color(0.3, 0.95, 0.85)


func _air_foe(pos: Vector3, nm: String, ai: bool, style: int, hp: float) -> AirFoe:
	var e := AirFoe.new()
	e.player = player
	e.display_name = nm
	e.ai_enabled = ai
	e.style = style
	e.hp_max = hp
	e.position = pos
	_hall_root.add_child(e)
	return e


## 刀客：出生点正前方一个（走两步就会迎上来），右前方远一点再放一个，默认一对一
func _spawn_duelists() -> void:
	duelist = _duelist(Vector3(0, 0, -10.0), "刀客")
	_duelist(Vector3(10.0, 0, -17.0), "刀客·二")


func _duelist(pos: Vector3, nm: String) -> Swordsman:
	var e := Swordsman.new()
	e.player = player
	e.display_name = nm
	e.home_yaw = PI
	e.position = pos
	_hall_root.add_child(e)
	return e


# ---------- 择境：大厅 ⇄ 关卡 ----------

func _open_level_select() -> void:
	if _switching or level != null:
		return
	Input.action_release("move_forward")
	level_ui.open()


func _on_menu_closed() -> void:
	if cam.capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 大厅整体停用 / 恢复：隐藏、停处理、关碰撞、敌人移出索敌分组、摘掉大厅的环境
func _set_hall_active(on: bool) -> void:
	_hall_root.visible = on
	_hall_root.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		for e: Array in _hall_groups:
			var n: Node = e[0]
			if is_instance_valid(n):
				n.add_to_group(String(e[1]))
		_hall_groups.clear()
	else:
		for g: String in ["enemies", "swordsmen", "air_foes"]:
			for n in get_tree().get_nodes_in_group(g):
				if _hall_root.is_ancestor_of(n):
					n.remove_from_group(g)
					_hall_groups.append([n, g])
	_set_collision(_hall_root, on)
	hall.set_env_active(on)
	if hall_portal != null:
		hall_portal.preview_on = on


func _set_collision(n: Node, on: bool) -> void:
	var co := n as CollisionObject3D
	if co != null:
		if on and co.has_meta("hall_layers"):
			var lm: Array = co.get_meta("hall_layers")
			co.collision_layer = int(lm[0])
			co.collision_mask = int(lm[1])
			co.remove_meta("hall_layers")
		elif not on and not co.has_meta("hall_layers"):
			co.set_meta("hall_layers", [co.collision_layer, co.collision_mask])
			co.collision_layer = 0
			co.collision_mask = 0
	for c in n.get_children():
		_set_collision(c, on)


func _enter_level(_id: String) -> void:
	if _switching or level != null:
		return
	_switching = true
	var t0 := Time.get_ticks_msec()
	await level_ui.fade(1.0, 0.45)
	level_ui.set_loading("木兰草原 · 载入中")
	player.force_ground()
	swords.dismiss_all()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_set_hall_active(false)
	level = MeadowLevel.new()
	level.name = "Meadow"
	level.player = player
	level.cam = cam
	level.font = font
	level.raid_enabled = not _meadow_demo or _raid_demo
	level.mobile = _touch
	level.exit_requested.connect(_return_to_hall)
	add_child(level)
	player.global_position = level.spawn_point()
	player.velocity = Vector3.ZERO
	player.face_now(level.spawn_yaw())
	cam.snap(level.spawn_yaw(), CameraRig.PITCH_DEFAULT, 6.5)
	var waited: float = await level.prewarm()
	# 正式关卡：收起键位说明和调试按钮
	hud.set_compact(level.raid != null)
	if touch != null:
		touch.compact = level.raid != null
	print("[meadow] 载入 %.2fs（黑场起 %dms），%s" % [waited, Time.get_ticks_msec() - t0, level.stats_text().replace("\n", " | ")])
	player.process_mode = Node.PROCESS_MODE_INHERIT
	level_ui.set_loading("")
	if cam.capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await level_ui.fade(0.0, 0.7)
	_switching = false


func _return_to_hall() -> void:
	if _switching or level == null:
		return
	_switching = true
	await level_ui.fade(1.0, 0.4)
	player.force_ground()
	swords.dismiss_all()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	level.queue_free()
	level = null
	hud.set_compact(false)
	if touch != null:
		touch.compact = false
	await get_tree().process_frame
	_set_hall_active(true)
	var out := hall_portal.front(8.0) if hall_portal != null else Vector3.ZERO
	player.global_position = out + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	player.face_now(-PI * 0.5)
	cam.snap(-PI * 0.5, CameraRig.PITCH_DEFAULT, 6.5)
	if hall_portal != null:
		hall_portal.rearm()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await level_ui.fade(0.0, 0.5)
	_switching = false


# ---------- 后处理 ----------

func _build_postfx() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = BLUR_SHADER
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.material = _blur_mat
	_blur_rect.visible = false
	layer.add_child(_blur_rect)


func _process(dt: float) -> void:
	Combat.tick(dt)
	var mt: Variant = player.melee.target
	cam.focus = mt if player.melee.engaged() and is_instance_valid(mt) else null
	hud.refresh(player, swords)
	if touch != null:
		touch.blocked = level != null and level.raid != null and level.raid.hud.bag_open()
	var s := cam.blur_strength
	_blur_mat.set_shader_parameter("impact", cam.impact_k)
	_blur_mat.set_shader_parameter("rush", cam.rush_k)
	_blur_rect.visible = s > 0.01 or cam.impact_k > 0.01 or cam.rush_k > 0.01
	if _blur_rect.visible:
		var c := Vector2(0.5, 0.5)
		var pc := player.center()
		if not cam.cam.is_position_behind(pc):
			var sz := get_viewport().get_visible_rect().size
			c = cam.cam.unproject_position(pc) / sz
			c = c.clamp(Vector2(0.25, 0.25), Vector2(0.75, 0.75))
		_blur_mat.set_shader_parameter("strength", s)
		_blur_mat.set_shader_parameter("center", c)
		_blur_mat.set_shader_parameter("tint", Realm.line_color(player.realm))


# ---------- 自动演示截图 ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 截图：原图 PNG 存 _shots，另存一张 800 宽的 JPG 预览到 _shots/preview（方便快速验收）。
## 存盘期间冻结战斗时钟，长帧不会让招式时间轴跳帧。
func _shot(tag: String) -> void:
	Combat.hold = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/%s.png" % tag)
	var pv := img.duplicate() as Image
	pv.resize(800, int(800.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	pv.save_jpg("res://_shots/preview/%s.jpg" % tag, 0.85)
	Combat.hold = false
	print("[shot] ", tag)


## 镜头临时偏转 yaw_off 拍一张侧视，再转回去（只隔两帧，飞行方向几乎不受影响）
func _side_shot(tag: String, yaw_off: float) -> void:
	cam.yaw += yaw_off
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot(tag)
	cam.yaw -= yaw_off


func _home() -> void:
	player.force_ground()
	player.global_position = Vector3(0, 0.1, 0)


func _run_autotest() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	await _wait(1.5)
	await _shot("01_lianqi_ground")

	# 主角近景：地面站立，多角度（先停掉自动出剑，画面里只留人和待命飞剑）
	swords.auto_attack = false
	await _wait(0.8)
	var views := [["front", PI, -0.1], ["front34", PI * 0.78, -0.2], ["side", PI * 0.5, -0.1],
			["back34", PI * 0.22, -0.3], ["back", 0.0, -0.26]]
	for v: Array in views:
		cam.snap(float(v[1]), float(v[2]), 2.4)
		await _wait(0.25)
		await _shot("hero_%s" % v[0])
	# 行走：朝镜头斜向走来，拍迈步摆臂
	cam.snap(PI * 0.8, -0.16, 3.2)
	Input.action_press("move_back")
	Input.action_press("move_right")
	await _wait(0.45)
	await _shot("hero_walk")
	Input.action_release("move_back")
	Input.action_release("move_right")
	await _wait(0.4)
	_home()
	cam.snap(0.0, -0.26, 6.5)
	swords.auto_attack = true

	player.set_realm(4)
	await _wait(1.6)
	await _shot("02_huashen_swords")

	# 出剑拖尾：万剑齐发，看剑光是否是一条条可读的细线
	player.set_realm(5)
	await _wait(0.6)
	swords.burst()
	await _wait(0.3)
	await _shot("04_strike_trails")
	cam.snap(0.7, -0.32, 11.0)
	swords.burst()
	await _wait(0.35)
	await _shot("04_strike_trails_wide")
	cam.snap(0.0, -0.26, 6.5)

	player.set_realm(0)
	await _wait(0.4)
	player.toggle_flight()
	Input.action_press("move_forward")
	await _wait(1.6)
	await _shot("03_lianqi_sword_ride")
	await _side_shot("03_lianqi_sword_ride_side", 1.25)
	Input.action_release("move_forward")
	player.toggle_flight()
	await _wait(1.0)

	# 结丹 / 元婴 / 炼虚 / 大乘：起飞、破空瞬间、巡航（背后 + 侧视）
	for idx: int in [2, 3, 5, 7]:
		_home()
		player.set_realm(idx)
		await _wait(0.8)
		player.toggle_flight()
		await _wait(0.4)
		await _shot("r%d_a_takeoff" % idx)
		await _wait(0.25)
		await _shot("r%d_a2_launch" % idx)
		Input.action_press("move_forward")
		await _wait(1.1)
		await _shot("r%d_b_cruise" % idx)
		await _side_shot("r%d_c_cruise_side" % idx, 1.05)
		Input.action_release("move_forward")
		player.toggle_flight()
		await _wait(1.2)
	get_tree().quit()


# ---------- 近战演示截图（-- --combat-shot） ----------

func _evn(kind: String) -> int:
	return int(_evc.get(kind, 0))


## 等到第 n0+1 次 kind 事件（返回是否等到）
func _wait_event(kind: String, n0: int, timeout := 3.0) -> bool:
	var t := 0.0
	while _evn(kind) == n0 and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	if _evn(kind) == n0:
		print("[combat-shot] 未等到事件 ", kind)
	return _evn(kind) > n0


func _wait_until(cond: Callable, timeout := 3.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


## 两人面对面站好：主角在原点面朝 -Z，刀客在 dist 米外面朝主角
func _duel_reset(dist: float) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 0.02, 0)
	player.face_now(0.0)
	duelist.place(Vector3(0, 0, -dist), PI)


## 读招弹反（演示用"玩家"）：刀客出刀判定前 0.07s 点按格挡；hold=true 则一直按住
func _bot_parry(hold := false) -> void:
	await _wait_until(func() -> bool: return duelist.time_to_hit() <= 0.07, 3.0)
	player.melee.press_guard()
	if not hold:
		await _wait(0.05)
		player.melee.release_guard()


## 刀客出一招，主角读招弹反；先从主角身后拍刀客的前摇，再切到侧面拍对刃
func _parry_round(kind: int, dist: float, windup_t: float, tag: String) -> void:
	_duel_reset(dist)
	cam.snap(0.42, -0.14, 5.2)
	await _wait(0.45)
	duelist.force_attack(kind)
	await _wait_until(func() -> bool: return duelist.attack_time() >= windup_t)
	await _shot(FEEL + "%s_windup" % tag)
	cam.snap(PI * 0.5, -0.1, 4.3)
	var n := _evn("parry")
	_bot_parry()
	if await _wait_event("parry", n):
		await _shot(FEEL + "%s_parry_clash" % tag)
		await _wait(0.22)
		await _shot(FEEL + "%s_parry_after" % tag)
	await _wait(0.7)


## 三连击：每段拍蓄势/命中顿刀/收势关键姿势
func _combo_round(prefix: String) -> void:
	var m := player.melee
	_duel_reset(2.3)
	cam.snap(1.1, -0.16, 4.8)
	await _wait(0.5)
	var n := _evn("hit")
	m.press_attack()
	await _wait_until(func() -> bool: return m.attack_time() >= 0.11)
	await _shot("%s_a1_windup" % prefix)
	await _wait_event("hit", n)
	await _shot("%s_a1_hit" % prefix)
	await _wait_until(func() -> bool: return m.attack_time() >= 0.25)
	await _shot("%s_a1_pose" % prefix)
	n = _evn("hit")
	m.press_attack()
	await _wait_until(func() -> bool: return m.step == 1 and m.attack_time() >= 0.085)
	await _shot("%s_a2_windup" % prefix)
	await _wait_event("hit", n)
	await _shot("%s_a2_hit" % prefix)
	await _wait_until(func() -> bool: return m.step == 1 and m.attack_time() >= 0.24)
	await _shot("%s_a2_pose" % prefix)
	n = _evn("hit")
	m.press_attack()
	await _wait_until(func() -> bool: return m.step == 2 and m.attack_time() >= 0.3)
	await _shot("%s_a3_windup" % prefix)
	await _wait_event("hit", n)
	await _shot("%s_a3_impact" % prefix)
	await _wait_until(func() -> bool: return m.step == 2 and m.attack_time() >= 0.95)
	await _shot("%s_a3_finish" % prefix)
	await _wait(0.6)


## 单刀命中：顿刀那一帧 → 碎块飞出 → 碎块落地
func _debris_round() -> void:
	var m := player.melee
	duelist.demo_reset()
	_duel_reset(2.3)
	cam.snap(0.9, -0.24, 4.2)
	await _wait(1.6)  # 等连续受击计数清零，避免刀客格挡
	var nh := _evn("hit")
	m.press_attack()
	if await _wait_event("hit", nh):
		await _shot(FEEL + "15_hit_impact")
		await _wait(0.12)
		await _shot(FEEL + "16_debris_fly")
		await _wait(0.4)
		await _shot(FEEL + "17_debris_ground")
	await _wait(0.6)


## 跳跃攻击：落下来时的空中斩
func _jump_attack_round() -> void:
	var m := player.melee
	duelist.demo_reset()
	_duel_reset(2.4)
	cam.snap(1.2, -0.1, 5.8)
	await _wait(1.6)
	player.jump()
	await _wait_until(func() -> bool: return player.velocity.y < 0.0 and player.global_position.y < 1.1, 1.5)
	var nh := _evn("hit")
	m.press_attack()
	await _wait_until(func() -> bool: return m.attack_time() >= 0.09, 0.5)
	await _shot(FEEL + "40_jump_slash")
	if await _wait_event("hit", nh, 0.6):
		await _shot(FEEL + "41_jump_slash_hit")
	await _wait(1.3)


## 空中弹反：刀客上撩防空，主角跳起后在空中点按弹反，再空中反击
func _air_parry_round() -> void:
	var m := player.melee
	duelist.demo_reset()
	_duel_reset(2.4)
	cam.snap(PI * 0.5, -0.04, 5.6)
	await _wait(0.8)
	duelist.force_attack(Swordsman.A.RISE)
	await _wait_until(func() -> bool: return duelist.attack_time() >= 0.3, 1.0)
	player.jump()
	var np := _evn("parry")
	_bot_parry()
	if await _wait_event("parry", np, 1.5):
		await _shot(FEEL + "44_air_parry")
		await _wait(0.1)
		var nh := _evn("hit")
		m.press_attack()
		if await _wait_event("hit", nh, 1.0):
			await _shot(FEEL + "45_air_counter")
	await _wait(1.2)


func _run_combat_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	player.set_realm(2, false)
	duelist.ai_enabled = false
	duelist.block_chance = 0.0
	cam.focus_yaw = false
	cam.focus_mix = 0.5
	var m := player.melee

	# 0. 刀客进入 8m 内自动拔剑：戒备架势 + 飞剑收到背后
	_duel_reset(6.5)
	cam.snap(0.75, -0.2, 6.0)
	await _wait(1.4)
	await _shot(FEEL + "00_ready")
	# 放大一圈后的近战持剑（近景）
	cam.snap(0.95, -0.1, 2.6)
	await _wait(0.3)
	await _shot(FEEL + "00b_weapon")

	# 1. 挥空：干脆收招，只有剑光，没有火星、碎块和顿帧
	cam.snap(1.1, -0.16, 4.8)
	m.press_attack()
	await _wait_until(func() -> bool: return m.attack_time() >= 0.19)
	await _shot(FEEL + "01_whiff")
	await _wait(0.8)

	# 2. 三段连招
	await _combo_round(FEEL + "02")

	# 3. 读招弹反：横斩 / 刺击；中间穿插一次按住格挡
	await _parry_round(Swordsman.A.SWEEP, 2.1, 0.46, "03_sweep")
	if not duelist.is_broken():
		await _parry_round(Swordsman.A.THRUST, 2.6, 0.5, "04_thrust")
	if not duelist.is_broken():
		_duel_reset(2.1)
		cam.snap(PI * 0.5, -0.1, 4.3)
		await _wait(0.4)
		duelist.force_attack(Swordsman.A.SWEEP)
		await _wait_until(func() -> bool: return duelist.attack_time() >= 0.3)
		var nb := _evn("block")
		m.press_guard()
		if await _wait_event("block", nb):
			await _shot(FEEL + "05_block")
		await _wait(0.2)
		m.release_guard()
		await _wait(0.8)
	# 延迟重击：举刀悬停骗早弹，红光亮起后才落刀
	var tries := 0
	while not duelist.is_broken() and tries < 3:
		await _parry_round(Swordsman.A.HEAVY, 2.1, 0.75, "06_heavy" if tries == 0 else "06_heavy_%d" % tries)
		if not duelist.is_broken():
			await _combo_round(FEEL + "07_extra_%d" % tries)
		tries += 1

	# 4. 破防 → 处决
	await _wait_until(func() -> bool: return duelist.is_broken(), 1.0)
	await _wait(0.5)
	cam.snap(0.8, -0.18, 5.0)
	await _wait(0.1)
	await _shot(FEEL + "08_posture_break")
	var ne := _evn("execute")
	m.press_attack()
	if await _wait_event("execute", ne):
		await _shot(FEEL + "09_deathblow")
		await _wait(0.5)
		await _shot(FEEL + "10_deathblow_after")
	await _wait(1.2)
	await _shot(FEEL + "11_fallen")
	await _wait_until(func() -> bool: return not duelist.visual.visible, 2.0)
	await _wait(0.12)
	await _shot(FEEL + "11b_dissolve")

	# 5. 不防不弹：硬吃一刀（扣血、涨架势、主角身上崩出碎块）
	await _wait_until(func() -> bool: return duelist.is_alive() and duelist.visual.scale.x > 0.95, 6.0)
	_duel_reset(2.1)
	cam.snap(0.42, -0.14, 5.2)
	await _wait(0.4)
	var nh := _evn("hurt")
	duelist.force_attack(Swordsman.A.SWEEP)
	if await _wait_event("hurt", nh):
		await _shot(FEEL + "12_player_hit")
		await _wait(0.3)
		await _shot(FEEL + "12b_player_debris")
	await _wait(0.8)

	# 6. 打击感细节：单刀命中的顿刀 / 碎块飞出 / 碎块落地
	await _debris_round()
	# 7. 跳斩；空中弹反
	await _jump_attack_round()
	await _air_parry_round()

	# 8. 收剑起飞再落地：遁光规则不受影响，落地后重新拔剑
	duelist.demo_reset()
	_duel_reset(3.0)
	await _wait(0.6)
	player.toggle_flight()
	await _wait(0.35)
	await _shot(FEEL + "13_takeoff_sheathed")
	player.toggle_flight()
	await _wait(1.6)
	_duel_reset(3.0)
	cam.snap(0.75, -0.2, 6.0)
	await _wait(0.8)
	await _shot(FEEL + "14_landed_ready")
	print("[combat-shot] 事件计数 ", _evc)
	get_tree().quit()


# ---------- 飞行表现演示截图（-- --fx-shot） ----------

func _run_fx_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	await _wait(1.2)

	# 筑基御风：巡航时的风丝（背后 + 侧视）
	player.set_realm(1, false)
	await _wait(0.4)
	player.toggle_flight()
	await _wait(0.6)
	Input.action_press("move_forward")
	await _wait(1.4)
	await _shot(FX + "01_zhuji_cruise")
	await _side_shot(FX + "02_zhuji_cruise_side", 1.1)
	Input.action_release("move_forward")
	player.toggle_flight()
	await _wait(1.0)

	# 结丹：化作光剑起飞（化剑途中 → 光剑升空）
	_home()
	player.set_realm(2, false)
	cam.snap(0.9, -0.12, 5.0)
	await _wait(1.0)
	player.toggle_flight()
	await _wait(0.07)
	await _shot(FX + "03_jiedan_morph")
	await _wait_until(func() -> bool: return player.morph_k() >= 1.0, 1.0)
	await _wait(0.05)
	await _shot(FX + "04_jiedan_sword_rise")
	await _wait(0.6)
	cam.snap(0.0, CameraRig.PITCH_DEFAULT, 6.5)
	Input.action_press("move_forward")
	await _wait(1.0)
	await _shot(FX + "05_jiedan_cruise")
	await _side_shot(FX + "06_jiedan_cruise_side", 1.1)

	# 飞行跟随镜头俯仰：默认视角平飞，抬头爬升，低头俯冲
	var y0 := player.global_position.y
	await _wait(0.5)
	print("[fx-shot] 默认视角 0.5s 高度 %.1f -> %.1f" % [y0, player.global_position.y])
	y0 = player.global_position.y
	cam.pitch = 0.5
	await _wait(0.8)
	print("[fx-shot] 抬头 0.8s 高度 %.1f -> %.1f" % [y0, player.global_position.y])
	await _shot(FX + "07_pitch_up_climb")
	y0 = player.global_position.y
	cam.pitch = -0.9
	await _wait(0.5)
	print("[fx-shot] 低头 0.5s 高度 %.1f -> %.1f" % [y0, player.global_position.y])
	Input.action_release("move_forward")
	cam.pitch = CameraRig.PITCH_DEFAULT

	# 悬停：由光剑现形
	await _wait_until(func() -> bool: return player.morph_k() < 0.55, 3.0)
	await _shot(FX + "08_reappear")
	await _wait(0.5)
	player.toggle_flight()
	await _wait(1.5)

	# 闪现：结丹在地面横向闪现（侧视，朝 -Z 的空旷方向；+Z 方向 10m 处有方块会挡住）
	_home()
	cam.snap(PI * 0.5, -0.12, 8.0)
	await _wait(0.6)
	var p0 := player.global_position
	Input.action_press("move_right")
	player.blink()
	Input.action_release("move_right")
	await _wait(0.1)
	await _shot(FX + "09_blink_ground_mid")
	await _wait_until(func() -> bool: return not player.is_dashing(), 1.0)
	print("[fx-shot] 结丹闪现位移 %.1fm" % player.global_position.distance_to(p0))
	await _wait(0.05)
	await _shot(FX + "10_blink_ground_end")
	await _wait(1.0)

	# 闪现：大乘空中闪现（结丹起距离统一 8m，只是更快）
	_home()
	player.set_realm(7, false)
	cam.snap(0.0, CameraRig.PITCH_DEFAULT, 6.5)
	await _wait(0.6)
	player.toggle_flight()
	await _wait_until(func() -> bool: return player.morph_k() <= 0.0 and player.st == Player.St.FLY, 4.0)
	await _wait(0.3)
	cam.snap(PI * 0.5, -0.12, 9.0)
	await _wait(0.2)
	p0 = player.global_position
	Input.action_press("move_left")
	player.blink()
	Input.action_release("move_left")
	await _wait(0.06)
	await _shot(FX + "11_blink_air_mid")
	await _wait_until(func() -> bool: return not player.is_dashing(), 1.0)
	print("[fx-shot] 大乘闪现位移 %.1fm" % player.global_position.distance_to(p0))
	await _wait(0.03)
	await _shot(FX + "12_blink_air_end")
	await _wait(0.8)
	get_tree().quit()


# ---------- Shift 闪现 / 空战法术演示截图（-- --air-shot） ----------

## 模拟一次 Shift 按下 / 松开（走真实的输入事件，验证短按 / 长按判定）
func _shift(on: bool) -> void:
	_act("sprint", on)


func _act(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)


func _tap_shift_toward(move: String) -> void:
	Input.action_press(move)
	_shift(true)
	await _wait(0.08)
	_shift(false)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(move)


func _run_air_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	await _wait(1.2)

	# 炼气：短按 Shift 闪现（侧视，朝 -Z 的空旷方向），沿途留残影
	cam.snap(PI * 0.5, -0.12, 8.0)
	await _wait(0.5)
	var p0 := player.global_position
	await _tap_shift_toward("move_right")
	await _wait(0.04)
	await _shot(AIR + "01_lianqi_blink_ghosts")
	await _wait_until(func() -> bool: return not player.is_dashing(), 1.0)
	print("[air-shot] 炼气短按 Shift：闪现位移 %.1fm" % player.global_position.distance_to(p0))
	await _shot(AIR + "02_lianqi_blink_end")
	await _wait(0.6)

	# 长按 Shift：只疾行，松开也不闪现
	_home()
	await _wait(0.5)
	p0 = player.global_position
	_shift(true)
	await _wait(0.45)
	var sprint_on := player.sprinting()
	_shift(false)
	await _wait(0.2)
	print("[air-shot] 长按 Shift 0.45s：疾行=%s，松开后闪现=%s，位移 %.1fm" % [
		sprint_on, player.is_dashing(), player.global_position.distance_to(p0)])

	# 结丹：闪现统一 8m，化光剑
	player.set_realm(2, false)
	_home()
	await _wait(0.6)
	p0 = player.global_position
	await _tap_shift_toward("move_right")
	await _wait_until(func() -> bool: return not player.is_dashing(), 1.0)
	print("[air-shot] 结丹短按 Shift：闪现位移 %.1fm" % player.global_position.distance_to(p0))
	await _wait(0.6)

	# 结丹空战：空格腾空，镜头对准一个木桩
	_home()
	var tgt: EnemyDummy = null
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyDummy
		var dd := e.global_position.distance_to(player.global_position)
		if e.kind == 0 and dd > 10.0 and (tgt == null or dd < tgt.global_position.distance_to(player.global_position)):
			tgt = e
	var d := tgt.global_position - player.global_position
	cam.snap(atan2(-d.x, -d.z), CameraRig.PITCH_DEFAULT, 6.0)
	await _wait(0.8)
	var y0 := player.global_position.y
	_act("jump", true)
	await _wait(0.05)
	_act("jump", false)
	await _wait(0.08)
	await _shot(AIR + "03_takeoff")
	await _wait(0.5)
	print("[air-shot] 空格腾空：%s，高度 %.1f -> %.1f" % [player.state_text(), y0, player.global_position.y])
	var hp0 := tgt.hp

	# 三段：御剑三连刺 → 火球 → 剑火齐发（出招中预输入下一段）
	var c := player.caster
	c.press_attack()
	await _wait(0.1)
	await _shot(AIR + "04_s1_summon")
	await _wait(0.16)
	await _shot(AIR + "05_s1_swords_fly")
	c.press_attack()
	await _wait_until(func() -> bool: return c.step == 1, 1.0)
	await _wait(0.2)
	await _shot(AIR + "06_s2_fireball_fly")
	await _wait(0.22)
	await _shot(AIR + "07_s2_fireball_boom")
	c.press_attack()
	await _wait_until(func() -> bool: return c.step == 2, 1.0)
	await _wait(0.22)
	await _shot(AIR + "08_s3_charge")
	await _wait(0.3)
	await _shot(AIR + "09_s3_volley")
	await _wait(0.3)
	await _shot(AIR + "10_s3_boom")
	await _wait(0.3)
	await _shot(AIR + "11_s3_after")
	await _wait(0.4)
	print("[air-shot] 三段打完：木桩血量 %d -> %d（预期约 -%d），连段结束 step=%d" % [
		hp0, tgt.hp, int(float(player.realm["dmg"]) * (0.6 * 3 + 1.5 + 2.6 + 0.5 * 6)), c.step])

	# 低头俯冲：碰到地面即落地
	cam.pitch = -1.1
	Input.action_press("move_forward")
	var landed: bool = await _wait_until(func() -> bool: return player.st == Player.St.GROUND, 3.0)
	Input.action_release("move_forward")
	cam.pitch = CameraRig.PITCH_DEFAULT
	print("[air-shot] 低头俯冲：落地=%s，状态 %s，高度 %.2f" % [landed, player.state_text(), player.global_position.y])
	await _wait(0.1)
	await _shot(AIR + "12_landed")
	await _wait(0.5)
	get_tree().quit()


# ---------- 升阶 / 闪避 / 碎裂演示截图（-- --realm-shot） ----------

const REALM := "realm_"


func _run_realm_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	duelist.ai_enabled = false
	duelist.block_chance = 0.0
	cam.focus_yaw = false
	duelist.place(Vector3(0, 0, -14.0), PI)
	cam.snap(PI * 0.82, -0.1, 5.2)
	await _wait(1.0)

	# 1. 炼气 → 筑基：聚气 / 破境 / 题字书写中 / 题字写完 / 淡出
	player.set_realm(1)
	await _wait(0.25)
	await _shot(REALM + "01_zhuji_gather")
	await _wait(0.3)
	await _shot(REALM + "02_zhuji_burst")
	await _wait(0.55)
	await _shot(REALM + "03_zhuji_writing")
	await _wait(1.0)
	await _shot(REALM + "04_zhuji_full")
	await _wait(1.5)
	await _shot(REALM + "05_zhuji_fadeout")
	await _wait(1.0)

	# 2. 其余各阶：破境那一下 + 题字写完
	for idx: int in [2, 3, 4, 5, 6, 7]:
		player.set_realm(idx)
		await _wait(0.6)
		await _shot(REALM + "1%d_burst" % idx)
		await _wait(1.55)
		await _shot(REALM + "1%d_full" % idx)
		await _wait(1.6)

	# 3. 完美闪避 → 瞬移斩（结丹）
	player.set_realm(2, false)
	duelist.demo_reset()
	_duel_reset(2.1)
	cam.snap(PI * 0.5, -0.12, 6.0)
	await _wait(1.6)
	duelist.force_attack(Swordsman.A.SWEEP)
	await _wait_until(func() -> bool: return duelist.time_to_hit() <= 0.12, 3.0)
	var p0 := player.global_position
	Input.action_press("move_left")
	player.blink()
	Input.action_release("move_left")
	var ok := await _wait_event("perfect_dodge", 0, 1.0)
	await _wait(0.05)
	print("[realm-shot] 完美闪避=%s 闪避距离 %.1fm 时间流速 %.2f" % [ok, player.global_position.distance_to(p0), Engine.time_scale])
	await _shot(REALM + "20_perfect_dodge_slowmo")
	var nw := _evn("warp")
	player.melee.press_attack()
	var warped := await _wait_event("warp", nw, 1.0)
	await _wait(0.03)
	print("[realm-shot] 瞬移斩=%s 离刀客 %.1fm" % [warped, player.global_position.distance_to(duelist.global_position)])
	await _shot(REALM + "21_warp_strike")
	await _wait(0.6)

	# 4. 死亡碎裂 + 消融：刀客被斩 / 木桩被击碎
	duelist.demo_reset()
	_duel_reset(2.4)
	cam.snap(0.9, -0.2, 5.5)
	await _wait(0.5)
	duelist.begin_deathblow()
	duelist.deathblow_hit(Vector3(0, 0, -1))
	await _wait(0.5)
	await _shot(REALM + "30_shatter")
	await _wait(0.5)
	await _shot(REALM + "31_shatter_fall")
	await _wait(0.6)
	await _shot(REALM + "32_dissolve")
	await _wait(0.6)
	await _shot(REALM + "33_dissolve_late")
	var tgt: EnemyDummy = null
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyDummy
		if e.kind == 0 and (tgt == null or e.global_position.length() < tgt.global_position.length()):
			tgt = e
	var d := tgt.global_position - player.global_position
	cam.snap(atan2(-d.x, -d.z), -0.2, 4.0)
	player.global_position = tgt.global_position - d.normalized() * 3.0
	await _wait(0.4)
	tgt.take_hit(9999.0, d.normalized(), Realm.line_color(player.realm))
	await _wait(0.3)
	await _shot(REALM + "34_dummy_shatter")
	await _wait(1.1)
	await _shot(REALM + "35_dummy_dissolve")
	await _wait(0.5)
	get_tree().quit()


# ---------- 剑冢 Boss 空战自检（-- --boss-test） ----------

const BOSS_SHOT := "boss_"


## 有渲染才截图（--headless 下只跑逻辑、打印）
func _boss_shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _shot(BOSS_SHOT + tag)


func _boss_walk_in() -> bool:
	var to := arena.center() - player.global_position
	cam.snap(atan2(-to.x, -to.z), -0.1, 6.5)
	Input.action_press("move_forward")
	var ok: bool = await _wait_until(func() -> bool: return arena.active(), 12.0)
	Input.action_release("move_forward")
	return ok


func _boss_watch(tag: String, sec: float) -> void:
	var peak := 0
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
		peak = maxi(peak, arena.bullets.count())
		arena.hp = maxf(arena.hp, 40.0)  # 自检不让主角倒下
	print("[boss-test] %s：%.1fs 内同屏弹数峰值 %d，当前 %d，主角中弹 %d 次，护体 %d" % [
		tag, sec, peak, arena.bullets.count(), arena.hits, int(arena.hp)])


func _run_boss_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	player.set_realm(0, false)
	await _wait(0.8)
	var b := arena.boss
	print("[boss-test] Boss：%s · %s（%s）血量 %d，剑冢中心 %s，状态 %d" % [
		BossArena.Boss.TITLE, BossArena.Boss.NAME, BossArena.Boss.RANK, int(b.max_hp), arena.center(), b.state])

	# 0. 沉睡：入口处看立在剑冢正中的方块魔像
	player.force_ground()
	player.global_position = arena.entrance()
	var to0 := arena.center() - player.global_position
	cam.snap(atan2(-to0.x, -to0.z), 0.22, 9.0)
	await _wait(0.6)
	await _boss_shot("00_dormant")

	# 1. 炼气从入口走进赤线：自动压境元婴、切空战、镜头锁定、Boss 开场
	var ok := await _boss_walk_in()
	print("[boss-test] 走进赤线自动开战=%s 境界=%s 状态=%s 镜头锁定=%s" % [
		ok, player.realm["name"], player.state_text(), cam.lock == b])
	await _wait(1.6)
	await _boss_shot("01_intro_roar")
	await _wait(1.3)
	print("[boss-test] 首次开战登场题名=%s" % arena.ui._banner.visible)
	await _boss_shot("01b_name")
	await _wait_until(func() -> bool: return b.state == BossArena.Boss.S.FIGHT, 5.0)
	print("[boss-test] 开场结束，进入战斗=%s 镜头距离目标 %.1f" % [b.state == BossArena.Boss.S.FIGHT, cam.lock_zoom])

	# 2. 一阶：看一会儿弹幕（主角不动挨打，确认判定生效）
	await _boss_watch("一阶 " + b.phase_title(), 4.0)
	await _boss_shot("02_phase1")
	var tgt: Array = player.caster._pick()
	print("[boss-test] 空战法术自动索敌到 Boss=%s" % [tgt[0] == b])
	# 2b. 真打：元婴空战法术三段连按 4 秒（不走作弊伤害），看 Boss 掉血、估算整场用时
	var hp0 := b.hp
	var tt := 0.0
	while tt < 4.0:
		player.caster.press_attack()
		await _wait(0.2)
		tt += 0.2
		arena.hp = maxf(arena.hp, 40.0)
	await _wait(0.8)
	var dps := (hp0 - b.hp) / 4.8
	print("[boss-test] 法术真打 4s：Boss 血量 %d -> %d（约 %d/s，三段连按满血打完约 %ds，不算转阶段）" % [
		int(hp0), int(b.hp), int(dps), int(b.max_hp / maxf(dps, 1.0))])

	# 3. 护体打空 → 败 → 送回入口 → 再走进来重开
	arena.hp = 5.0
	arena._iframe = 0.0
	arena._on_bullet_hit(player.center(), Vector3.FORWARD, 10.0)
	print("[boss-test] 护体打空：战况=%d Boss 状态=%d" % [arena.state, b.state])
	await _wait(3.2)
	print("[boss-test] 送回入口：离剑冢中心 %.1fm（赤线 %.0fm）战况=%d" % [
		Vector2(player.global_position.x - arena.center().x, player.global_position.z - arena.center().z).length(),
		BossArena.TRIGGER_R, arena.state])
	ok = await _boss_walk_in()
	print("[boss-test] 再次走进赤线重开=%s" % ok)
	await _wait_until(func() -> bool: return b.state == BossArena.Boss.S.FIGHT, 6.0)
	print("[boss-test] 再次开战不再题名=%s" % (not arena.ui._banner.visible))

	# 4. 打到 70%：转二阶
	var dir := Vector3.FORWARD
	b.take_hit(b.max_hp * 0.5, dir, Color.WHITE)
	print("[boss-test] 一刀打掉 50%%：血量 %.0f%%（阶段闸门 70%%），状态=%d" % [b.hp_ratio() * 100.0, b.state])
	await _wait(1.0)
	await _boss_shot("03_shift")
	await _wait_until(func() -> bool: return b.state == BossArena.Boss.S.FIGHT, 5.0)
	await _boss_watch("二阶 " + b.phase_title(), 5.0)
	await _boss_shot("04_phase2")

	# 5. 打到 35%：转三阶
	b.take_hit(b.max_hp * 0.4, dir, Color.WHITE)
	await _wait_until(func() -> bool: return b.state == BossArena.Boss.S.FIGHT and b.phase == 2, 6.0)
	await _boss_watch("三阶 " + b.phase_title(), 6.0)
	await _boss_shot("05_phase3")

	# 6. 每一招单独放一遍，确认都能跑
	for p: String in ["fan", "ring", "swords", "orbs", "spiral", "curve", "wall", "rose"]:
		var n0: int = arena.bullets.count()
		var dur: float = b._cast(p)
		await _boss_watch("招式 %s（时长 %.1fs，出手前 %d 颗）" % [p, dur, n0], minf(dur, 2.0))
		await _boss_shot("06_" + p)

	# 7. 击败：碎裂、伏诛、HUD 大字；之后重新凝聚
	b.take_hit(b.max_hp, dir, Color.WHITE)
	print("[boss-test] 致命一击：Boss 状态=%d 可索敌=%s 弹幕清屏中 %d" % [b.state, b.alive, arena.bullets.count()])
	await _wait(1.2)
	await _boss_shot("07_dying")
	await _wait_until(func() -> bool: return b.state == BossArena.Boss.S.DEAD, 6.0)
	await _boss_shot("08_shatter")
	print("[boss-test] 击败：Boss 状态=%d 战况=%d（3=胜）镜头锁定=%s" % [b.state, arena.state, cam.lock != null])
	await _wait(2.5)
	print("[boss-test] 击败 2.5s 后：镜头锁定=%s 弹数 %d" % [cam.lock != null, arena.bullets.count()])
	get_tree().quit()


# ---------- 打击特效对照截图（-- --hitfx-shot） ----------

func _run_hitfx_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	player.set_realm(4, false)
	cam.snap(0.0, -0.1, 5.0)
	await _wait(1.2)
	var c := Realm.line_color(player.realm)
	var r := cam.global_basis.x
	var f := -cam.global_basis.z
	f = Vector3(f.x, 0.0, f.z).normalized()
	var at := func(i: float) -> Vector3: return player.global_position + f * 2.0 + r * i * 1.6 + Vector3.UP * 1.2

	# 飞剑命中：三个不同方向
	Vfx.hit(at.call(-1.0), (f + r).normalized(), c)
	Vfx.hit(at.call(0.0), -r, c)
	Vfx.hit(at.call(1.0), (f - r + Vector3.UP * 0.5).normalized(), c)
	await _wait(0.06)
	await _shot(HITFX + "01_sword_hit_early")
	await _wait(0.16)
	await _shot(HITFX + "02_sword_hit_late")
	await _wait(0.8)

	# 近战分档：轻击 / 重击 / 下砸 / 处决
	var blade := Color(0.75, 0.88, 1.0)
	Vfx.impact(at.call(-1.5), r, blade, 0)
	Vfx.impact(at.call(-0.5), r, blade, 1)
	Vfx.impact(at.call(0.5), r, blade, 4)
	Vfx.impact(at.call(1.5), r, Color(0.95, 0.2, 0.15), 3)
	await _wait(0.08)
	await _shot(HITFX + "03_impact_early")
	await _wait(0.22)
	await _shot(HITFX + "04_impact_late")
	await _wait(0.8)

	# 弹反对刃
	Vfx.blade_clash(at.call(0.0), f, 1.0)
	await _wait(0.1)
	await _shot(HITFX + "05_parry_early")
	await _wait(0.3)
	await _shot(HITFX + "06_parry_late")
	await _wait(0.8)

	# 死亡：当场击碎（左）与倒地内爆（右，炸开对上 1.5s 时刻）
	Vfx.death_implode(at.call(1.0), Color(1.0, 0.22, 0.16))
	await _wait(0.6)
	await _shot(HITFX + "07_implode_gather")
	await _wait(Vfx.implode_lead() - 0.6)
	Vfx.death_burst(at.call(-1.0), c)
	await _wait(0.08)
	await _shot(HITFX + "08_death_pop")
	await _wait(0.3)
	await _shot(HITFX + "09_death_spread")
	await _wait(1.2)
	get_tree().quit()


# ---------- 择境门 / 木兰草原演示（-- --meadow-shot） ----------

const MEADOW := "meadow_"


func _meadow_shot(tag: String) -> void:
	if DisplayServer.get_name() != "headless":
		await _shot(MEADOW + tag)


func _meadow_print(tag: String) -> void:
	print("[meadow-shot] %s：%s" % [tag, level.stats_text().replace("\n", " | ")])


## 飞 sec 秒：前进（可开疾遁），按前方地面高度调镜头俯仰保持离地 alt 米（贴地高速飞是流式加载最吃力的情形）；
## 返回 [最低前方覆盖率, 脚下不是 LOD0 的帧数, 总帧数]
func _meadow_cruise(sec: float, alt: float, boost: bool, print_every := 1.0) -> Array:
	Input.action_press("move_forward")
	if boost:
		_shift(true)
	var t := 0.0
	var next := print_every
	var min_ahead := 1.0
	var bad := 0
	var frames := 0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
		frames += 1
		var p := player.global_position
		var v := player.velocity
		var ahead := p + Vector3(v.x, 0.0, v.z) * 1.2
		var g := maxf(level.terrain.height_at(p.x, p.z), level.terrain.height_at(ahead.x, ahead.z))
		cam.pitch = CameraRig.PITCH_DEFAULT + clampf((g + alt - p.y) * 0.012, -0.45, 0.6)
		var s := level.terrain.stats()
		if t > 1.0:
			min_ahead = minf(min_ahead, float(s["ahead"]))
		if int(s["under"]) != 0 and p.y - g < 60.0:
			bad += 1
		if t >= next:
			next += print_every
			_meadow_print("%.0fs 离地 %.0fm" % [t, p.y - level.terrain.height_at(p.x, p.z)])
	if boost:
		_shift(false)
	Input.action_release("move_forward")
	cam.pitch = CameraRig.PITCH_DEFAULT
	return [min_ahead, bad, frames]


func _run_meadow_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	swords.auto_attack = false
	# 1. 大厅里的择境门（门心里是草原）
	player.global_position = hall_portal.front(14.0) + Vector3(0, 0.1, 0)
	cam.snap(PI * 0.5 + 0.3, -0.1, 6.5)
	await _wait(2.5)
	await _meadow_shot("00_hall_portal")
	cam.snap(PI * 0.5, -0.06, 4.0)
	await _wait(0.5)
	await _meadow_shot("00b_hall_portal_close")
	# 2. 走进门 → 择境
	cam.snap(PI * 0.5, -0.12, 6.5)
	Input.action_press("move_forward")
	var opened: bool = await _wait_until(func() -> bool: return level_ui.is_open(), 8.0)
	Input.action_release("move_forward")
	print("[meadow-shot] 走进择境门弹出选关=%s 暂停=%s" % [opened, get_tree().paused])
	await _wait(0.3)
	await _meadow_shot("01_select")
	level_ui.pick(0)
	var t0 := Time.get_ticks_msec()
	var entered: bool = await _wait_until(func() -> bool: return level != null and not _switching, 25.0)
	print("[meadow-shot] 进入木兰草原=%s 用时 %dms 出生点 %s" % [entered, Time.get_ticks_msec() - t0, player.global_position])
	if not entered:
		get_tree().quit()
		return
	# 3. 出生点：正对远山 / 回头看回程门和石碑 / 草地近景
	await _wait(1.0)
	_meadow_print("出生点")
	await _meadow_shot("02_spawn")
	var yaw := level.spawn_yaw()
	cam.snap(yaw + PI * 0.8, -0.16, 10.0)
	await _wait(0.6)
	await _meadow_shot("03_exit_portal")
	cam.snap(yaw + 0.7, -0.04, 3.0)
	await _wait(0.4)
	await _meadow_shot("04_grass_close")
	# 4. 炼气走上坡：贴地、踩草
	cam.snap(yaw, CameraRig.PITCH_DEFAULT, 6.5)
	Input.action_press("move_forward")
	await _wait(5.0)
	Input.action_release("move_forward")
	var p := player.global_position
	print("[meadow-shot] 走 5s：位置 %s 地面 %.2f 脚下差 %.2f 着地=%s" % [p, level.terrain.height_at(p.x, p.z),
			p.y - level.terrain.height_at(p.x, p.z), player.is_on_floor()])
	await _meadow_shot("05_walk")
	# 5. 筑基御风：低空巡航（升限按地面起算）
	player.set_realm(1, false)
	player.toggle_flight()
	await _wait(0.8)
	var r: Array = await _meadow_cruise(4.0, 18.0, false, 2.0)
	await _meadow_shot("06_zhuji_low")
	await _side_shot(MEADOW + "06b_zhuji_low_side", 1.1)
	# 6. 大乘：爬高俯瞰
	player.force_ground()
	player.global_position.y = level.terrain.height_at(player.global_position.x, player.global_position.z) + 0.1
	player.set_realm(7, false)
	await _wait(0.3)
	player.toggle_flight()
	await _wait(1.0)
	r = await _meadow_cruise(4.0, 420.0, false, 2.0)
	cam.pitch = -0.55
	await _wait(0.3)
	await _meadow_shot("07_high_view")
	cam.pitch = CameraRig.PITCH_DEFAULT
	# 7. 大乘疾遁：高空直飞 8 秒（约 315 m/s）
	level.worst_frame_ms = 0.0
	r = await _meadow_cruise(8.0, 300.0, true, 1.0)
	print("[meadow-shot] 高空疾遁 8s：前方覆盖最低 %.0f%%，最长帧 %.1fms，%d 帧" % [float(r[0]) * 100.0, level.worst_frame_ms, r[2]])
	await _meadow_shot("08_high_speed")
	# 8. 大乘疾遁：贴地 40 米高速飞 10 秒（流式加载最吃力）
	level.worst_frame_ms = 0.0
	r = await _meadow_cruise(10.0, 40.0, true, 1.0)
	print("[meadow-shot] 贴地疾遁 10s：前方覆盖最低 %.0f%%，脚下没 LOD0 的帧 %d/%d，最长帧 %.1fms" % [
			float(r[0]) * 100.0, r[1], r[2], level.worst_frame_ms])
	await _meadow_shot("09_low_speed")
	await _side_shot(MEADOW + "09b_low_speed_side", 1.0)
	# 9. 遁光落地（砸在坡上）
	cam.pitch = -1.1
	player.toggle_flight()
	var landed: bool = await _wait_until(func() -> bool: return player.st == Player.St.GROUND, 6.0)
	cam.pitch = CameraRig.PITCH_DEFAULT
	p = player.global_position
	print("[meadow-shot] 落地=%s 高度差 %.2f" % [landed, p.y - level.terrain.height_at(p.x, p.z)])
	await _wait(1.0)
	await _meadow_shot("10_landed")
	# 10. 回出生点，走进回程门回大厅
	player.set_realm(0, false)
	player.force_ground()
	var door := level.exit_portal
	player.global_position = door.front(10.0) + Vector3.UP * 0.2
	var to := door.global_position - player.global_position
	cam.snap(atan2(-to.x, -to.z), CameraRig.PITCH_DEFAULT, 6.5)
	await _wait(1.5)
	await _meadow_shot("11_exit_portal_front")
	Input.action_press("move_forward")
	var back: bool = await _wait_until(func() -> bool: return level == null and not _switching, 15.0)
	Input.action_release("move_forward")
	print("[meadow-shot] 回大厅=%s 位置 %s 大厅可见=%s 敌人分组 %d" % [back, player.global_position, _hall_root.visible,
			get_tree().get_nodes_in_group("enemies").size()])
	await _wait(1.0)
	await _meadow_shot("12_back_in_hall")
	get_tree().quit()


# ---------- 空战斗法演示截图（-- --duel-shot） ----------

const DUEL := "duel_"


func _air_state() -> int:
	return int(player.air.state)


## 把主角摆到 e 的 +Z 方向 dist 米处（同高），侧视机位
func _duel_place(e: Node3D, dist: float, zoom := 7.0) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = e.global_position + Vector3(0.0, 0.0, dist)
	player.face_now(0.0)
	cam.snap(PI * 0.5, -0.06, zoom)


func _run_duel_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	var AM := Player.AirMelee
	var air := player.air
	cam.lock_turn = false
	foe.ai_enabled = false
	await _wait(1.0)
	player.set_realm(4, false)   # 化神期
	rival.ai_enabled = false

	# 0. R15 定妆：正面 / 侧面 / 跑动
	cam.snap(PI, -0.08, 3.6)
	await _wait(0.4)
	await _shot(DUEL + "00_model_front")
	cam.snap(PI * 0.5, -0.08, 3.6)
	await _wait(0.2)
	await _shot(DUEL + "00_model_side")
	cam.snap(PI * 0.5, -0.08, 4.5)
	cam.yaw = PI * 0.5
	Input.action_press("move_left")
	await _wait(0.45)
	await _shot(DUEL + "00_model_run")
	Input.action_release("move_left")
	await _wait(0.3)

	# 1. 腾空，凌空架势
	_home()
	await _wait(0.2)
	player.take_air()
	await _wait(0.8)
	_duel_place(sandbag, 6.0, 5.0)
	air._engage = 99.0
	air.target = sandbag
	await _wait(0.5)
	await _shot(DUEL + "01_air_stance")

	# 2. 五段追身连击
	var hp0 := sandbag.hp
	for i in 5:
		air.press_attack()
		await _wait_until(func() -> bool: return _air_state() == AM.A.ATTACK and air.step == i and air._hit_done, 2.0)
		await _wait(0.02)
		await _shot(DUEL + "02_combo_%d" % (i + 1))
		print("[duel] 连击 %d %s：间距 %.2f 连击数 %d 木人血 %d" % [i + 1, air.state_name(),
				player.center().distance_to(sandbag.center()), air.combo, int(sandbag.hp)])
		if i < 4:
			await _wait(0.12)
	await _wait(0.1)
	print("[duel] 五段打完：木人被击飞=%s 速度 %.1f 总伤害 %d" % [sandbag.is_launched(), sandbag.velocity().length(), int(hp0 - sandbag.hp)])
	cam.snap(PI * 0.5, -0.06, 14.0)
	await _wait(0.12)
	await _shot(DUEL + "03_launched")

	# 3. 瞬身追击：挑飞 → 陨落砸地
	var n := 0
	while n < 2 and sandbag.is_launched():
		air.press_attack()
		var ok: bool = await _wait_until(func() -> bool: return _air_state() == AM.A.SMASH and air._hit_done, 1.5)
		await _wait(0.02)
		await _shot(DUEL + "04_chase_%d" % (n + 1))
		print("[duel] 瞬身追击 %d：%s 命中=%s 木人速度 %s 灵力 %d" % [n + 1, air.state_name(), ok, sandbag.velocity(), int(player.mp)])
		n += 1
		await _wait(0.22)
	await _shot(DUEL + "05_meteor_cine")
	var crashed: bool = await _wait_until(func() -> bool: return sandbag.state == AirFoe.S.DOWN or sandbag.state == AirFoe.S.DEAD, 3.0)
	await _wait(0.06)
	await _shot(DUEL + "06_crash")
	print("[duel] 砸地=%s 木人状态 %s 血 %d 位置 %s 连击 %d" % [crashed, sandbag.state_name(), int(sandbag.hp), sandbag.global_position, air.combo])
	await _wait(1.2)

	# 4. 蓄力重击·崩拳（从 12 米外冲过去）
	sandbag.demo_reset(Vector3(-9.0, 7.0, -13.0))
	_duel_place(sandbag, 12.0, 9.0)
	air.target = sandbag
	await _wait(0.4)
	air.demo_heavy("fwd", 0.75)
	await _wait(0.55)
	await _shot(DUEL + "07_charge")
	await _wait_until(func() -> bool: return _air_state() == AM.A.SMASH, 1.0)
	await _wait(0.06)
	await _shot(DUEL + "08_smash_dash")
	await _wait_until(func() -> bool: return _air_state() == AM.A.SMASH and air._hit_done, 1.5)
	await _shot(DUEL + "09_smash_hit")
	await _wait(0.03)
	await _shot(DUEL + "09_smash_hit_b")
	print("[duel] 崩拳：木人击飞=%s 速度 %.1f 血 %d" % [sandbag.is_launched(), sandbag.velocity().length(), int(sandbag.hp)])
	await _wait(1.6)

	# 5. 追身突进（25 米外按攻击）
	sandbag.demo_reset(Vector3(-9.0, 7.0, -13.0))
	_duel_place(sandbag, 25.0, 12.0)
	air.target = sandbag
	await _wait(0.4)
	air.press_attack()
	await _wait(0.16)
	await _shot(DUEL + "10_rush")
	var arrived: bool = await _wait_until(func() -> bool: return _air_state() == AM.A.ATTACK, 1.5)
	print("[duel] 追身突进：到位出手=%s 间距 %.2f" % [arrived, player.center().distance_to(sandbag.center())])
	await _wait(1.0)

	# 6. 对手出手：瞬身 / 护体 / 挨打
	foe.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.6))
	air.target = foe
	cam.snap(PI * 0.5, -0.06, 6.0)
	await _wait(0.5)
	foe.force_attack(false)
	await _wait_until(func() -> bool: return foe.state == AirFoe.S.STRIKE, 2.0)
	air.press_guard()
	await _wait(0.12)
	await _shot(DUEL + "11_vanish")
	air.release_guard()
	print("[duel] 瞬身：对手状态 %s 主角位置在对手背后=%s 气血 %d" % [foe.state_name(),
			player.global_position.z < foe.global_position.z, int(player.melee.hp)])
	await _wait(1.5)
	foe.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.6))
	player.face_now(0.0)
	await _wait(0.4)
	air.press_guard()
	await _wait(0.4)
	foe.force_attack(false)
	await _wait_until(func() -> bool: return foe.state == AirFoe.S.STRIKE and foe._hit_done, 2.0)
	await _shot(DUEL + "12_guard")
	air.release_guard()
	print("[duel] 护体：气血 %d 灵力 %d" % [int(player.melee.hp), int(player.mp)])
	await _wait(1.2)
	foe.demo_reset(player.global_position + Vector3(0.0, 0.0, -2.6))
	await _wait(0.4)
	foe.force_attack(true)
	await _wait_until(func() -> bool: return foe.state == AirFoe.S.STRIKE and foe._hit_done, 2.5)
	await _wait(0.1)
	await _shot(DUEL + "13_blown")
	print("[duel] 挨重击：%s 气血 %d" % [air.state_name(), int(player.melee.hp)])
	await _wait(1.6)

	# 7. 飞剑点射 + 三式剑诀
	foe.demo_reset(player.global_position + Vector3(0.0, 0.0, -14.0))
	air.target = foe
	player.face_now(0.0)
	cam.snap(0.5, -0.1, 7.0)
	player.mp = player.mp_max()
	await _wait(0.5)
	var fhp := foe.hp
	for i in 3:
		air.press_shot()
		await _wait(0.18)
	await _shot(DUEL + "14_sword_shot")
	await _wait(0.5)
	print("[duel] 飞剑点射 ×3：对手血 %d -> %d 灵力 %d" % [int(fhp), int(foe.hp), int(player.mp)])
	for i in 3:
		fhp = foe.hp
		air.press_skill(i)
		await _wait(0.22)
		await _shot(DUEL + "15_skill_%d" % (i + 1))
		await _wait(1.3)
		print("[duel] 剑诀 %d「%s」：对手血 %d -> %d 灵力 %d 冷却 %.1f" % [i + 1, air.skill_name(i), int(fhp), int(foe.hp), int(player.mp), air.cds[i]])

	# 7a. 对波光柱打木人
	sandbag.demo_reset(Vector3(-9.0, 7.0, -13.0))
	_duel_place(sandbag, 16.0, 11.0)
	air.target = sandbag
	player.mp = player.mp_max()
	air.beam_cd = 0.0
	await _wait(0.4)
	var shp := sandbag.hp
	air.press_beam()
	await _wait(0.35)
	await _shot(DUEL + "17_beam_windup")
	await _wait(0.6)
	await _shot(DUEL + "18_beam_fire")
	await _wait(1.2)
	print("[duel] 光柱「%s」：木人血 %d -> %d 状态 %s 连击 %d" % [air.beam_name(), int(shp), int(sandbag.hp), sandbag.state_name(), air.combo])
	await _wait(1.5)

	# 7a2. 与真人陪练对波：它回一道光柱，相持后把它轰穿（自动连点）
	rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -24.0))
	rival.ai_enabled = true
	rival._beam_cd = 0.0
	rival._cd = 99.0
	air.target = rival
	player.face_now(0.0)
	player.mp = player.mp_max()
	air.beam_cd = 0.0
	air.demo_mash = 9.0
	cam.snap(PI * 0.5, -0.06, 14.0)
	await _wait(0.3)
	air.press_beam()
	if not rival.is_beaming():
		rival._start_beam(0.38)
	var clashed: bool = await _wait_until(func() -> bool: return air.in_clash(), 2.0)
	await _wait(0.5)
	await _shot(DUEL + "19_clash")
	await _wait(0.8)
	await _shot(DUEL + "19_clash_b")
	var rhp := rival.hp
	await _wait_until(func() -> bool: return not air.in_clash(), 8.0)
	await _wait(0.05)
	await _shot(DUEL + "20_clash_end")
	print("[duel] 对波：进入相持=%s 结束时交汇点 %.2f 陪练血 %d -> %d 被击飞=%s" % [clashed, air.clash_u(), int(rhp), int(rival.hp), rival.is_launched()])
	air.demo_mash = 0.0
	await _wait(2.5)

	# 7a3. 真人陪练进攻：连段 → 重击击飞 → 瞬身追击下砸 → 主角砸地成坑
	rival.demo_reset(player.global_position + Vector3(0.0, 0.0, -5.0))
	rival._beam_cd = 99.0
	rival._cd = 0.0
	player.melee.hp = 100.0
	cam.snap(PI * 0.5, -0.1, 9.0)
	var seen2 := {}
	var downed := false
	var t2 := 0.0
	while t2 < 9.0 and not downed:
		seen2[air.state_name()] = true
		if _air_state() == AM.A.DOWN:
			downed = true
		await _wait(0.03)
		t2 += 0.03
	await _wait(0.12)
	await _shot(DUEL + "21_player_ground_break")
	print("[duel] 陪练进攻：主角经历 %s 砸地=%s 气血 %d" % [seen2.keys(), downed, int(player.melee.hp)])
	rival.ai_enabled = false
	await _wait(1.5)

	# 7a4. 聚气 → 觉醒
	air.awaken = 96.0
	air.demo_gather = true
	await _wait(0.35)
	await _shot(DUEL + "22_gather")
	await _wait_until(func() -> bool: return air.awake_t > 0.0, 2.0)
	air.demo_gather = false
	await _wait(0.12)
	await _shot(DUEL + "23_awaken")
	print("[duel] 觉醒：剩余 %.1fs 伤害基数 %.0f" % [air.awake_t, air._base()])
	await _wait(1.0)

	# 7b. 对手自由进攻 10 秒：主角悬停不动，看它追上来连打 / 远处放剑气（中途按住护体 3 秒）
	foe.demo_reset(player.global_position + Vector3(0.0, 0.0, -20.0))
	foe.ai_enabled = true
	player.melee.hp = 100.0
	var seen := {}
	var tt := 0.0
	while tt < 10.0:
		seen[foe.state_name()] = true
		if tt > 5.0 and tt < 8.0 and not air.guard_held:
			air.press_guard()
		elif tt >= 8.0 and air.guard_held:
			air.release_guard()
		if absf(tt - 4.0) < 0.03:
			await _shot(DUEL + "16_foe_ai")
		await _wait(0.05)
		tt += 0.05
	foe.ai_enabled = false
	print("[duel] 对手自由进攻 10s：出现过的状态 %s 主角气血 %d 灵力 %d 间距 %.1f" % [seen.keys(), int(player.melee.hp),
			int(player.mp), player.center().distance_to(foe.center())])

	# 8. 落地
	cam.pitch = -1.1
	Input.action_press("move_forward")
	var landed: bool = await _wait_until(func() -> bool: return player.st == Player.St.GROUND, 4.0)
	Input.action_release("move_forward")
	print("[duel] 落地=%s 状态 %s" % [landed, player.state_text()])
	await _wait(0.3)
	get_tree().quit()


# ---------- 搜打撤自检截图（-- --raid-shot） ----------

const RAID := "raid_"
const RaidData := preload("res://scripts/raid_data.gd")


## 把主角放到 (x, z) 的地面上，等周围地块建好
func _raid_goto(p2: Vector2, yaw: float, up := 0.0) -> void:
	player.force_ground()
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p2.x, level.ground(p2.x, p2.y) + 0.2 + up, p2.y)
	cam.snap(yaw, -0.18, 9.0)
	await level.prewarm(8.0)


func _raid_fps(tag: String) -> void:
	level.worst_frame_ms = 0.0
	var n0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await _wait(2.0)
	var fps := float(Engine.get_frames_drawn() - n0) * 1000.0 / float(Time.get_ticks_msec() - t0)
	var rd = level.raid
	print("[raid] %s：区域 %s 帧率 %.0f 最长帧 %.0fms 小怪 %d 修士 %d 掉落 %d 绘制调用 %d 图元 %dk 地块 %d" % [tag,
			RaidData.REGIONS[int(rd.region)]["name"], fps, level.worst_frame_ms, rd._mobs.size(), rd._rivals.size(), rd._pickups.size(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), level.world.chunk_count()])


func _raid_census(tag: String) -> void:
	var rd = level.raid
	var lines: Array = []
	for f: Variant in rd._rivals:
		if is_instance_valid(f):
			lines.append("%s(%s%s %dm)" % [f.display_name, "红名" if f.hostile else "白名", " 打怪中" if f._prey != null else "",
					int(f.global_position.distance_to(player.global_position))])
	var elites := 0
	for m: Variant in rd._mobs:
		if is_instance_valid(m) and m.elite:
			elites += 1
	print("[raid] %s：局内 %ds 难度系数 %.2f 怪等级 %d 导演点数 %d 小怪 %d（精英 %d）修士 %d：%s" % [tag, int(rd.run_t), rd.coeff(),
			rd.enemy_level(int(rd.region)), int(rd._credits), rd._mobs.size(), elites, rd._rivals.size(), " ".join(lines)])


## 自检要一路跑完：主角气血见底就补满（挨打的数值照常打印）
func _raid_immortal() -> void:
	while level != null and level.raid != null and level.raid.running:
		if player.melee.hp < 30.0:
			player.melee.hp = 100.0
		await get_tree().create_timer(0.2).timeout


func _run_raid_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	await _wait(1.0)
	player.set_realm(4, false)
	await _enter_level("meadow")
	var rd = level.raid
	await _wait(1.0)
	await _shot(RAID + "00_spawn")
	await _raid_fps("出生点")
	rd._mob_root.visible = false
	await _raid_fps("出生点（藏起怪和修士，仅场景）")
	rd._mob_root.visible = true

	_raid_immortal()
	# 1. 什么都不做站 8 秒：怪和修士应该自己冒出来、打起来
	player.melee.hp = 100.0
	await _wait(8.0)
	_raid_census("原地等 8 秒后")
	await _shot(RAID + "01_alive")
	player.toggle_flight()
	await _wait(1.0)
	player.global_position.y += 22.0
	cam.snap(level.spawn_yaw() + 0.6, -0.45, 14.0)
	await _wait(1.0)
	await _shot(RAID + "02_wide")
	player.force_ground()

	# 2. 找最近的一只小怪：空战连击打它，看等级换算后的伤害，再清场捡掉落
	var mob: Variant = null
	for m: Variant in rd._mobs:
		if is_instance_valid(m) and not m.boss and (mob == null or m.global_position.distance_to(player.global_position) < mob.global_position.distance_to(player.global_position)):
			mob = m
	if mob != null and is_instance_valid(mob):
		var mp: Vector3 = mob.global_position
		await _raid_goto(Vector2(mp.x, mp.z + 6.0), 0.0)
		await _wait(0.6)
		await _shot(RAID + "03_mob")
		player.take_air()
		await _wait(0.7)
		var hp0: float = mob.hp if is_instance_valid(mob) else 0.0
		for i in 5:
			if not is_instance_valid(mob):
				break
			player.air.press_attack()
			await _wait(0.32)
		await _shot(RAID + "04_mob_fight")
		print("[raid] 空战连击打 %s：血 %d -> %s（主角 Lv.%d）" % [mob.display_name if is_instance_valid(mob) else "小怪", int(hp0),
				str(int(mob.hp)) if is_instance_valid(mob) else "已击杀", rd.lv])
	var lv0: int = rd.lv
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.receive_hit(player, {"dmg": 99999.0, "dir": Vector3.FORWARD})
	await _wait(0.4)
	print("[raid] 清怪后：击杀 %d 地面掉落 %d 修为 Lv.%d -> Lv.%d（%d%%）主角气血 %d" % [rd.kills, rd._pickups.size(), lv0, rd.lv,
			int(rd.exp_ratio() * 100.0), int(player.melee.hp)])
	for pk: Variant in rd._pickups.duplicate():
		if is_instance_valid(pk):
			player.force_ground()
			player.global_position = pk.global_position + Vector3(0.6, 0.1, 0.0)
			await _wait(1.4 if pk.is_chest() else 0.7)
	print("[raid] 拾取后：背包 %d 件 价值 %d" % [rd.bag.size(), rd.bag_value()])

	# 3. 四个区域各看一眼（风格、帧率、有没有怪和修士）
	for i in range(1, 5):
		var d: Vector2 = RaidData.REGIONS[i]["dir"]
		player.melee.hp = 100.0
		await _raid_goto(d.rotated(0.18) * 900.0, atan2(-d.x, -d.y))
		await _wait(6.0)
		_raid_census(str(RaidData.REGIONS[i]["name"]))
		await _shot(RAID + "1%d_region" % i)
		player.toggle_flight()
		await _wait(1.0)
		player.global_position.y += 16.0
		Input.action_press("move_forward")
		await _raid_fps("%s 飞行" % RaidData.REGIONS[i]["name"])
		Input.action_release("move_forward")
		await _shot(RAID + "1%d_region_fly" % i)
		player.force_ground()

	# 4. 巢穴 Boss：血色禁地的墨蛟
	player.melee.hp = 100.0
	var bpos: Vector3 = rd._bosses[2]["pos"]
	await _raid_goto(Vector2(bpos.x - 24.0, bpos.z), -PI * 0.5)
	await _wait(2.0)
	await _shot(RAID + "20_boss")
	var boss: Node3D = rd._bosses[2]["node"]
	print("[raid] 巢穴 Boss：%s 血 %d 状态 %s" % [("%s Lv.%d" % [boss.display_name, boss.lv]) if is_instance_valid(boss) else "未生成",
			int(boss.hp) if is_instance_valid(boss) else 0, boss.state_name() if is_instance_valid(boss) else ""])
	await _wait(3.0)
	await _shot(RAID + "21_boss_attack")
	print("[raid] 挨 Boss 打 3 秒后：主角气血 %d" % int(player.melee.hp))
	var c0: float = rd.coeff()
	if is_instance_valid(boss):
		boss.receive_hit(player, {"dmg": 9999999.0, "dir": Vector3.RIGHT})
	await _wait(0.6)
	await _shot(RAID + "22_boss_chest")
	print("[raid] 击败巢穴 Boss：难度系数 %.2f -> %.2f，主角 Lv.%d %s期" % [c0, rd.coeff(), rd.lv, player.realm["name"]])

	# 5. 天地异动：游荡 Boss 找上门
	player.melee.hp = 100.0
	var ev: Node3D = rd.boss_event()
	await _wait(2.5)
	await _shot(RAID + "23_boss_event")
	if is_instance_valid(ev):
		print("[raid] 游荡 Boss：%s Lv.%d 血 %d 距离 %dm" % [ev.display_name, ev.lv, int(ev.hp), int(ev.global_position.distance_to(player.global_position))])
		ev.receive_hit(player, {"dmg": 9999999.0, "dir": Vector3.RIGHT})
	await _wait(0.5)

	# 6. 其他修士：回草原，看他们自己刷怪；再击败一个开箱
	player.melee.hp = 100.0
	await _raid_goto(Vector2(120.0, 60.0), 0.0)
	await _wait(12.0)
	_raid_census("草原等 12 秒后")
	var rv: Variant = null
	for f: Variant in rd._rivals:
		if is_instance_valid(f) and (rv == null or (f._prey != null and rv._prey == null)):
			rv = f
	if rv != null and is_instance_valid(rv):
		var rp: Vector3 = rv.global_position
		player.melee.hp = 100.0
		await _raid_goto(Vector2(rp.x, rp.z + 11.0), 0.0)
		await _wait(0.8)
		await _shot(RAID + "30_rival")
		print("[raid] 修士 %s：%s 状态 %s 主角气血 %d" % [rv.display_name if is_instance_valid(rv) else "?", "打怪中" if is_instance_valid(rv) and rv._prey != null else "游荡",
				rv.state_name() if is_instance_valid(rv) else "", int(player.melee.hp)])
		if is_instance_valid(rv):
			var cp: Vector3 = rv.global_position
			rv.air_hit(player, {"dmg": 9999999.0, "dir": Vector3.FORWARD, "contact": rv.center()})
			await _wait(0.6)
			player.force_ground()
			player.global_position = Vector3(cp.x + 1.5, level.ground(cp.x, cp.z) + 0.1, cp.z)
			await _wait(0.6)
			await _shot(RAID + "31_rival_chest")
			await _wait(1.2)
	print("[raid] 开箱后：背包 %d 件 价值 %d" % [rd.bag.size(), rd.bag_value()])

	# 7. 背包：打开、服一颗丹药
	rd.hud.toggle_bag()
	await _wait(0.4)
	await _shot(RAID + "40_bag")
	var ex0: float = rd.exp_ratio()
	var l0: int = rd.lv
	for i in rd.bag.size():
		if rd.bag[i]["kind"] == "pill":
			rd.use_item(i)
			break
	await _wait(0.3)
	print("[raid] 服丹：Lv.%d %d%% -> Lv.%d %d%%（%s期）背包 %d 件" % [l0, int(ex0 * 100.0), rd.lv, int(rd.exp_ratio() * 100.0),
			player.realm["name"], rd.bag.size()])
	rd.hud.toggle_bag()

	# 8. 撤离：先看一座废阵，再去亮着的那座读条
	player.melee.hp = 100.0
	var dead_e: Dictionary = {}
	var live_e: Dictionary = {}
	for e: Dictionary in rd._extracts:
		if bool(e["active"]) and live_e.is_empty():
			live_e = e
		elif not bool(e["active"]) and dead_e.is_empty():
			dead_e = e
	var dp: Vector3 = dead_e["pos"]
	await _raid_goto(Vector2(dp.x, dp.z + 22.0), 0.0)
	await _wait(1.0)
	await _shot(RAID + "50_extract_dead")
	var lp: Vector3 = live_e["pos"]
	await _raid_goto(Vector2(lp.x, lp.z + 22.0), 0.0)
	await _wait(1.0)
	await _shot(RAID + "51_extract_live")
	rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(lp.x, level.ground(lp.x, lp.z) + 0.6, lp.z)
	await _wait(3.0)
	await _shot(RAID + "52_extracting")
	print("[raid] 撤离读条 %.0f%%" % (float(rd.extract_k) * 100.0))
	await _wait_until(func() -> bool: return not rd.running, 6.0)
	await _wait(0.8)
	await _shot(RAID + "53_result")
	await _wait_until(func() -> bool: return level == null, 10.0)
	await _wait(1.0)
	print("[raid] 回到大厅=%s" % (level == null))
	get_tree().quit()
