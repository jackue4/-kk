extends Node
## 觉醒演出：分镜 + 黑白漫画冲击帧（2026-11-25）。
## 用户原话：「觉醒的时候没有镜头表现，也没有视觉冲击感很强的黑白漫画风画面，你详细调研一下TSB怎么做镜头跟视觉表现的」。
## TSB 的做法（调研结论，见记忆 tsb-pvp-rework）：觉醒 / 大招是一段锁镜头的演出（镜头被接管、演完交还第三人称，演出期间无敌）；
## 冲击帧 = 画面整屏去色 + 对比拉到头（纯白 / 纯黑），人物反色描出来，停零点一秒左右再整张反相，中间夹集中线；
## 手绘的冲击帧是在动作的一个停顿上把镜头钉住、整屏闪几张图。这里照这个结构做，全部用实时画面过一遍着色器（shaders/manga_frame.gdshader）。
##
## 三段（都按真实时间走）：
##   0 蓄势：镜头切到人正前方低机位的近景，慢慢推近；上下黑边压进来；本机的战斗时钟放慢一半，起手架势多摆一会儿。
##           起手招（英雄表 awake_move）到判定那一刻转下一段（最多等 BUILD_MAX 秒）
##   1 冲击帧：三张漫画帧连切 —— 侧面大特写（白纸黑线）→ 正面贴脸（整张反白）→ 仰拍 + 满屏集中线 + 题字（白纸黑线），
##           这零点几秒战斗时钟停住（姿势定格）
##   2 放开：颜色回来、气浪炸开（air_melee 的 _awaken_burst：震开身边的人）、镜头切到身后高处的远景再混回跟随机位
## 只有本机主角自己看得到镜头和漫画帧；别人那边看到的是他摆架势 + 气浪（觉醒本来就同步的那些）。演出期间无敌（air_melee 给 _iframe）。
## 黑白只在冲击帧那一段、整段两次明暗翻转（白 → 黑 → 白），不做连续闪烁。
## `--no-awk-cine` 关掉（回到没有演出的老流程，对照 / 排查用）。故意不写 class_name：用 preload 引用。

const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const UiStyle := preload("res://scripts/ink_style.gd")
const SHADER := preload("res://shaders/manga_frame.gdshader")

const BUILD_MAX := 0.9        # 蓄势最多这么久（等不到起手招的判定就自己往下走）
const BUILD_SLOW := 0.5       # 蓄势时本机战斗时钟放慢到多少
const FRAMES: Array = [0.11, 0.07, 0.13]     # 三张冲击帧各停多久
const RELEASE := 0.62
const BAR := 0.085            # 上下黑边各占屏高多少
## 整段大约多久（air_melee 按它给无敌、把觉醒时长补回来）：蓄势约 0.6 + 冲击帧 0.31 + 放开 0.62
const TOTAL := 1.55

static var enabled := not OS.get_cmdline_user_args().has("--no-awk-cine")
static var played := 0        # 自检用：演过几回
static var last_frames := 0   # 自检用：最近一回漫画帧画了几帧
static var dbg: Array = []     # 自检用：最近一回每换一次机位记一条 [段, 第几张, 机位收了几成（1 = 没收，0 = 没地方摆）, 镜头离人多远]

var player: Player
var air: Node                 # air_melee.gd
var title := ""
var col := Color(1.0, 0.8, 0.4)
var on_burst := Callable()    # 放开那一下（气浪 + 震开）

var _phase := 0
var _pt := 0.0
var _sub := -1
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _lab: Label
var _burst_done := false
var _bar := 0.0
var _n_manga := 0
## 剪影用的小视口：和主视口共用场景，镜头只看第 SIL_BIT 层 —— 演出开始时给主角身上的网格临时加上这一层（原来的层不动），演完撤掉
const SIL_BIT := 1 << 11
var _sv: SubViewport
var _scam: Camera3D
var _marked: Array = []
var _dbg_key := -1


func _ready() -> void:
	process_priority = 20      # 在 air_melee / 镜头的跟随算完之后写演出机位
	_fwd = air._fwd()
	_right = _fwd.cross(Vector3.UP).normalized()
	_layer = CanvasLayer.new()
	_layer.layer = 30          # 压在 HUD / 触屏键上面（它们也跟着进漫画帧），在换场幕布下面
	add_child(_layer)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_layer.add_child(_rect)
	_lab = Label.new()
	_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lab.visible = false
	_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lab.add_theme_font_override("font", UiStyle.brush())
	_layer.add_child(_lab)
	played += 1
	dbg.clear()
	_sil_setup()
	Combat.slowmo(BUILD_SLOW, 0.55, 0.1)
	_apply(0.0)


func _exit_tree() -> void:
	if is_instance_valid(player) and player.cam != null:
		player.cam.cine_k = 0.0
	for vi: Variant in _marked:
		if is_instance_valid(vi):
			(vi as VisualInstance3D).layers &= ~SIL_BIT
	_marked.clear()


## 小视口用的环境：照搬场景现在的环境，只把背景换成透明的纯色（天空照旧拿来当环境光 / 反射）——
## 这样主角的材质在小视口里用的是和主画面同一套着色器变体，不用为它另编一套（网页上现编一个要零点几秒到一秒）
static func _mask_env(world: World3D) -> Environment:
	var src: Environment = world.environment if world != null else null
	var env: Environment = (src.duplicate() as Environment) if src != null else Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	if src != null and src.sky != null:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.glow_enabled = false
	return env


## 载入时预热（warmup.gd 的「推演新招」那一批调）：把只画主角的小视口先开几帧，它要用的着色器变体在幕布后面编好，
## 不然第一次觉醒正好卡在切镜头那一下。小视口挂在预热的临时节点下面，跟着它一起撤；主角身上临时加的那一层同时撤掉
static func warm(player: Player, holder: Node) -> void:
	if not enabled or player == null or holder == null or DisplayServer.get_name() == "headless":
		return
	var body: Node = player.visual if player.visual != null else player
	var marked: Array = []
	for n: Node in body.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi is Light3D or (vi.layers & SIL_BIT) != 0:
			continue
		vi.layers |= SIL_BIT
		marked.append(vi)
	var sv := SubViewport.new()
	sv.size = Vector2i(96, 54)
	sv.transparent_bg = true
	sv.own_world_3d = false
	sv.world_3d = player.get_world_3d()
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.positional_shadow_atlas_size = 0
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(sv)
	var cam := Camera3D.new()
	cam.cull_mask = SIL_BIT
	cam.environment = _mask_env(player.get_world_3d())
	sv.add_child(cam)
	var c := player.center()
	cam.look_at_from_position(c + Vector3(0.0, 0.3, 3.0), c)
	cam.current = true
	holder.tree_exiting.connect(func() -> void:
		for m: Variant in marked:
			if is_instance_valid(m):
				(m as VisualInstance3D).layers &= ~SIL_BIT)


## 只画主角的小视口（半分辨率、背景透明）
func _sil_setup() -> void:
	var body: Node = player.visual if player.visual != null else player
	for n: Node in body.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi is Light3D or (vi.layers & SIL_BIT) != 0:
			continue
		vi.layers |= SIL_BIT
		_marked.append(vi)
	if _marked.is_empty():
		return
	var vs := get_viewport().get_visible_rect().size
	_sv = SubViewport.new()
	_sv.size = Vector2i(maxi(int(vs.x * 0.5), 64), maxi(int(vs.y * 0.5), 36))
	_sv.transparent_bg = true
	_sv.own_world_3d = false
	_sv.world_3d = player.get_world_3d()
	_sv.msaa_3d = Viewport.MSAA_DISABLED
	_sv.positional_shadow_atlas_size = 0
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_scam = Camera3D.new()
	_scam.cull_mask = SIL_BIT
	_scam.environment = _mask_env(player.get_world_3d())
	_sv.add_child(_scam)
	_scam.current = true
	_mat.set_shader_parameter("mask_tex", _sv.get_texture())


## 演出还能不能接着演（人没了 / 落地了 / 被别的演出接管了就收）
func _alive() -> bool:
	return is_instance_valid(player) and not player.dead and player.st == Player.St.AIR and not player.ult.active


func _process(dt: float) -> void:
	if not _alive():
		_finish()
		return
	_pt += dt
	match _phase:
		0:
			var hit: bool = bool(air.get("_hit_done")) or air.state != air.A.ATTACK
			if (hit and _pt > 0.25) or _pt >= BUILD_MAX:
				_phase = 1
				_pt = 0.0
				_sub = 0          # 这一帧就按第一张漫画帧摆（留着 -1 的话这一帧会落到第三张的机位上，闪一下）
				_frame_sfx(0)
				Combat.clear_hitstop()
				Combat.hitstop(float(FRAMES[0]) + float(FRAMES[1]) + float(FRAMES[2]), 0.0)
		1:
			var acc := 0.0
			var s := FRAMES.size()
			for i in FRAMES.size():
				acc += float(FRAMES[i])
				if _pt < acc:
					s = i
					break
			if s >= FRAMES.size():
				_phase = 2
				_pt = 0.0
				_burst()
			elif s != _sub:
				_sub = s
				_frame_sfx(s)
		2:
			if _pt >= RELEASE:
				_finish()
				return
	_apply(dt)


func _frame_sfx(s: int) -> void:
	match s:
		0:
			Sfx.play("punch_heavy", -1.0, 0.6)
			Sfx.play("perfect", -3.0, 1.2)
		1:
			Sfx.play("clash", -2.0, 0.75)
		2:
			Sfx.play("slam", -2.0, 1.25)
	player.cam.add_trauma(0.22)


func _burst() -> void:
	if _burst_done:
		return
	_burst_done = true
	if on_burst.is_valid():
		on_burst.call()


func _finish() -> void:
	_burst()       # 被打断也要把气浪放出来（觉醒已经生效了）
	last_frames = _n_manga
	queue_free()


static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)


## 机位：eye 看向 look，绕视线滚 roll 弧度
static func _xf(eye: Vector3, look: Vector3, roll: float) -> Transform3D:
	var f := look - eye
	if f.length_squared() < 1e-4:
		f = Vector3.FORWARD
	var up := Vector3.UP if absf(f.normalized().dot(Vector3.UP)) < 0.97 else Vector3.BACK
	return Transform3D(Basis.looking_at(f, up) * Basis(Vector3.BACK, roll), eye)


## 机位别进墙 / 进地：不行就往人身上收，再不行返回 false（这一拍不接管镜头）
func _fit(c: Vector3, eye: Vector3) -> Vector3:
	for sk: float in [1.0, 0.7, 0.45]:
		var e := c + (eye - c) * sk
		var fy := -1e9
		if player.cam.floor_fn.is_valid():
			fy = float(player.cam.floor_fn.call(e.x, e.z))
		e.y = maxf(e.y, fy + 0.3)
		if player.solid_hit(c, e, 0.4, 0.5, 0.0) == Vector3.INF:
			return e
	return Vector3.INF


func _apply(_dt: float) -> void:
	var cam := player.cam
	var c := player.center()
	var vs := get_viewport().get_visible_rect().size
	var eye := Vector3.ZERO
	var look := c
	var fov := 40.0
	var roll := 0.0
	var k := 0.0
	var inv := 0.0
	var lines := 0.0
	var sd := 0.0
	var ck := 1.0
	var show_title := false
	var sil := false
	match _phase:
		0:
			var u := _ease(_pt / 0.6)
			eye = c + _fwd * lerpf(3.4, 2.3, u) + _right * lerpf(1.2, 0.75, u) + Vector3.UP * lerpf(-0.1, -0.35, u)
			look = c + Vector3.UP * 0.28
			fov = lerpf(44.0, 34.0, u)
			roll = lerpf(0.0, 0.07, u)
			_bar = move_toward(_bar, BAR, get_process_delta_time() / 0.14 * BAR)
		1:
			k = 1.0
			match _sub:
				0:
					eye = c + _fwd * 2.4 + _right * 3.9 + Vector3.UP * 0.4      # 侧前方，整个人的剪影都在画面里（太近了只剩一团黑）
					look = c + Vector3.UP * 0.25
					fov = 36.0
					roll = 0.17
					lines = 0.55
					sd = 1.0
					sil = true
				1:
					eye = c + _fwd * 2.7 + _right * -0.25 + Vector3.UP * 0.15      # 正面半身
					look = c + Vector3.UP * 0.3
					fov = 32.0
					roll = -0.14
					inv = 1.0
					lines = 0.8
					sd = 2.0
					sil = true
				_:
					eye = c + _fwd * 2.5 + _right * -0.7 + Vector3.UP * -1.3
					look = c + Vector3.UP * 0.55
					fov = 52.0
					roll = 0.1
					lines = 1.0
					sd = 3.0
					show_title = true
			_n_manga += 1
		2:
			var u2 := _ease(_pt / RELEASE)
			var back := -cam.flat_forward()
			eye = c + back * lerpf(6.0, 7.6, u2) + Vector3.UP * lerpf(2.0, 2.8, u2)
			look = c + Vector3.UP * 0.5
			fov = lerpf(72.0, cam.BASE_FOV, u2)
			k = clampf(1.0 - _pt / 0.07, 0.0, 1.0)
			lines = k
			sd = 3.0
			_bar = move_toward(_bar, 0.0, get_process_delta_time() / 0.25 * BAR)
			ck = clampf((RELEASE - _pt) / 0.3, 0.0, 1.0)      # 后 0.3 秒混回跟随机位（两个都在身后，不甩）
			show_title = _pt < 0.42
	var fit := _fit(c, eye)
	var key := _phase * 10 + maxi(_sub, 0)
	if key != _dbg_key:
		_dbg_key = key
		dbg.append([_phase, _sub, 0.0 if fit == Vector3.INF else snappedf(fit.distance_to(c) / maxf(eye.distance_to(c), 0.01), 0.01),
				snappedf(cam.cam.global_position.distance_to(c), 0.1) if cam.cam != null else -1.0])
	if fit == Vector3.INF:
		cam.cine_k = 0.0
	else:
		cam.cine_xf = _xf(fit, look, roll)
		cam.cine_fov = fov
		cam.cine_k = ck
	# 集中线的焦点 = 人在屏幕上的位置（镜头这一帧才摆，用上一帧的投影也只差一点；切镜头那一帧按屏幕正中）
	var fc := Vector2(0.5, 0.5)
	if cam.cam != null and not cam.cam.is_position_behind(c):
		var sp := cam.cam.unproject_position(c + Vector3.UP * 0.25)
		fc = Vector2(clampf(sp.x / vs.x, 0.3, 0.7), clampf(sp.y / vs.y, 0.3, 0.7))
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("invert", inv)
	_mat.set_shader_parameter("lines", lines)
	_mat.set_shader_parameter("seed", sd)
	_mat.set_shader_parameter("center", fc)
	_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_mat.set_shader_parameter("bars", _bar)
	_mat.set_shader_parameter("sil", 1.0 if sil and _sv != null else 0.0)
	# 剪影帧：只画主角的小视口跟主镜头同一个机位（主镜头这一帧的位置 camera_rig 已经算好了：它排在这个节点前面），只在这几帧更新
	if _sv != null:
		_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if (sil or _phase == 0) else SubViewport.UPDATE_DISABLED
		if cam.cam != null:
			_scam.global_transform = cam.cam.global_transform
			_scam.fov = cam.cam.fov
	_rect.visible = k > 0.001 or _bar > 0.001
	_title_show(show_title, vs, inv > 0.5, k)


## 题字：竖着写在画面右侧，漫画帧里是墨黑字白边，颜色回来之后换成这位英雄的颜色、淡出
func _title_show(on: bool, vs: Vector2, inverted: bool, k: float) -> void:
	if not on or title == "":
		_lab.visible = false
		return
	var n := title.length()
	var fs := int(vs.y * minf(0.2, 0.74 / float(n)))
	if not _lab.visible:
		_lab.text = "\n".join(title.split(""))
		_lab.add_theme_font_size_override("font_size", fs)
		_lab.add_theme_constant_override("line_spacing", -int(float(fs) * 0.16))
		_lab.add_theme_constant_override("outline_size", maxi(int(float(fs) * 0.16), 6))
		_lab.size = Vector2(float(fs) * 1.6, vs.y)
		_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lab.visible = true
	# 桌面写在右侧；触屏右下是一簇按键（进了漫画帧是一片黑圆），题字挪到左侧
	var scene := get_tree().current_scene
	var touch_on := scene != null and scene.get("touch") != null
	_lab.position = Vector2(vs.x * (0.21 if touch_on else 0.76) - float(fs) * 0.8, 0.0)
	var ink := Color(0.04, 0.04, 0.05)
	var paper := Color(1.0, 1.0, 1.0)
	var a := 1.0
	if _phase == 2:
		a = clampf(1.0 - (_pt - 0.2) / 0.22, 0.0, 1.0)
	var fg := paper if inverted else ink
	var bg := ink if inverted else paper
	if k < 0.5:
		fg = Color.WHITE.lerp(col, 0.55)
		bg = ink
	_lab.add_theme_color_override("font_color", Color(fg, a))
	_lab.add_theme_color_override("font_outline_color", Color(bg, a))
