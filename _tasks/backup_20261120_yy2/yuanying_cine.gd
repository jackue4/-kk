extends Node3D
## 结婴演出：突破到元婴时的一段过场（player.gd 的 _start_yuan_cine 调起；走雷劫的话等雷劫收尾、人落地之后再播。约 17 秒，镜头、天色都由这里接管）。
## 分镜照着用户给的六张参考图（_refs/yuanying_advance）排：
##   一 天地异象（0 → 2.4s）   主角身后低机位：人缓缓腾空十五米（悬在树梢以上，后面的机位都跟着抬高，不会被树挡住），镜头仰起来，天色压暗、褐金色的乌云翻涌、云里闷雷
##   二 剑气冲天（2.4 → 3.4s）  四十多米外的低机位：一道圆弧顶的巨大青色刀光从主角身上拔空而起、越飞越快，拖着摇曳的光柱，所过之处空间扭曲、荡开一圈圈气浪
##   三 光柱入云（3.4 → 6.0s）  切到远景：刀光扎进云层（4.0s），云被撕开一个洞，洞沿发亮，通天的青色光柱留在原地
##   四 破云见日（6.0 → 8.2s）  换一个远景机位：云洞越撕越大，洞里是白昼的蓝天，一束金色天光泻下来，把剩下的云照成金色；元婴在光里自下而上显形
##   五 正面特写（8.2 → 10.8s） 切到元婴面前，长焦慢推：双目亮起，脑后光轮张开、放出光芒，背景压成深青星空
##   六 拉远见全身（10.8 → 13.2s）镜头从面前退开、绕到侧前方的低机位，看到完整的法相
##   七 全景（13.2 → 16.8s）    主角身后的广角：人在前景、元婴顶天立地，身后炸开金色背光；这一刻真正突破（发 revealed）；最后元婴化光收回主角体内，人落回地面
## 东西都是自己建的，不依赖场景：天幕（罩在镜头外的大球，cine_sky.gdshader）、刀光 / 光柱 / 天光（sword_qi.gdshader）、气浪环（space_ripple.gdshader）、
## 元婴（一个放大二十六倍的方块人套上灵体材质 spirit_body.gdshader）、光轮（spirit_halo.gdshader）、上下两条电影黑边。
## 大世界里的环境光 / 雾由 raid_manager.gd 读 dark / gold 跟着变。点一下屏幕 / 按攻击键可以跳到结尾。
## 故意不写 class_name：用 preload 引用。

signal revealed      # 元婴现形：调用方在这一刻真正突破（换装、题字）
signal done

## 正在播的那场（raid_manager 读它的 dark / gold 去压天色）。没有就是 null
static var playing = null

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Sfx := preload("res://scripts/sfx.gd")
const SKY := preload("res://shaders/cine_sky.gdshader")
const QI := preload("res://shaders/sword_qi.gdshader")
const BODY := preload("res://shaders/spirit_body.gdshader")
const HALO := preload("res://shaders/spirit_halo.gdshader")
const RIPPLE := preload("res://shaders/space_ripple.gdshader")
## 烘好的噪声（_tasks/cine_noise/bake.py 生成）：网页 / 手机档的天幕、光带、光轮查它，不在每个像素上现算分形噪声
const NOISE := preload("res://fx/cine/cine_noise.png")

const T_LAUNCH := 2.4
const T_WIDE := 3.4
const T_PIERCE := 4.0
const T_BREAK := 6.0
const T_SPIRIT := 6.8
const T_FACE := 8.2
const T_EYES := 9.1
const T_PULL := 10.8
const T_FAR := 13.2
const T_REVEAL := 13.5
const T_OUT := 15.4
const T_END := 16.8
const T_UI := T_END - 0.55    # 黑边收起时界面才回来（题字例外：现形那一刻就要落在全景上）

const SPIRIT_H := 52.0        # 元婴有多高（米）
const SPIRIT_D := 30.0        # 元婴站在主角前面多远
const LIFT := 15.0            # 主角腾空多高
const CLOUD_H := 240.0        # 云层有多高：剑气在这里穿云
const DOME_R := 600.0
const TEAL := Color(0.3, 0.95, 0.84)

var player: Player
var cam: CameraRig
var base := Vector3.ZERO      # 主角脚下的地面
var yaw0 := 0.0               # 演出开始时镜头的朝向（各机位都相对它摆）
var dark := 0.0               # 天色压多暗（0~1，大世界的氛围读）
var gold := 0.0               # 破云后的金色天光（0~1）
var tear_k := 0.0             # 云层被撕开的程度（0~1，大世界天空读）

var _t := 0.0
var _f := Vector3.FORWARD     # 镜头原来看的方向
var _b := Vector3.BACK
var _s := Vector3.RIGHT
var _g := Vector3.ZERO        # 元婴脚下
var _top := Vector3.ZERO      # 主角腾空后悬停的位置（机位相对它摆）
var _lift := 0.0              # 这一帧主角离地多高
var _ripples: Array = []      # 剑气拖尾的气浪环：[面片, 已过时间, 寿命]
var _once := {}
var _amb := 0.3
var _flash := 0.0
var _dome: MeshInstance3D
var _dome_mat: ShaderMaterial
var _blade: MeshInstance3D
var _pillar: MeshInstance3D
var _shaft: MeshInstance3D
var _spirit: Node3D
var _shero: VoxelHero
var _body_mat: ShaderMaterial
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _eyes: Array[MeshInstance3D] = []
var _bars: Array[ColorRect] = []
var _ring_y := 14.0
var _veiled: Array = []          # 演出期间藏起来的界面层
var _banner_layers: Array = []   # 其中带境界题字的层：现形时先放回来，但只露题字
var _kids: Array = []            # 这些层里除题字之外暂时按住不显示的东西
var _dof_was := false            # 演出前镜头的远景虚化开没开（演出里关掉，放完还原）
## 排查流畅度用（命令行 `--yy-perf`）：记下每一帧的真实耗时，播完按分镜打印中位 / 95% / 最长和所有长帧的时间点；
## `--yy-hide=sky,strips,halo,body` 不画其中几样（天幕 / 三条光带 / 光轮 / 元婴），对比着看各自占多少。
var _perf := false
var _perf_last := 0
var _perf_log := PackedVector2Array()   # [过场时间, 这一帧花了多少毫秒]
var _perf_cpu := PackedVector2Array()   # 同一帧的 [脚本和引擎逻辑花的毫秒, 绘制调用数]
var _hide := ""
## 开场先把后面才出场的几种材质各画一小片（看不见）：兼容渲染器是「第一次画到才现编着色器」，
## 不这样做的话剑气拔起、元婴现形那两下正好各卡一拍。进图预热编过的（warmup.gd 的 CINE）这里不花时间。
var _primer: Node3D
var _primer_n := 0
var _veil_next := 0.0           # 下一次扫场景树找界面层的时间（不每帧扫）


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--yy-perf":
			_perf = true
		elif a.begins_with("--yy-hide="):
			_hide = a.get_slice("=", 1)
	playing = self
	top_level = true
	global_transform = Transform3D.IDENTITY
	_f = Basis(Vector3.UP, yaw0) * Vector3.FORWARD
	_b = -_f
	_s = Basis(Vector3.UP, yaw0) * Vector3.RIGHT
	_top = base + Vector3.UP * LIFT
	_g = base + _f * SPIRIT_D
	if cam.floor_fn.is_valid():
		# 元婴脚踩在它那儿的地面上（前面是悬崖 / 云海时不往下掉太多）
		_g.y = clampf(float(cam.floor_fn.call(_g.x, _g.z)), base.y - 10.0, base.y)
	_g.y -= 3.0
	# 天幕
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_dome.mesh = sm
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = SKY
	_dome_mat.render_priority = -100       # 先画：后面的剑气、光轮都叠在它上面
	_dome_mat.set_shader_parameter("noise_tex", NOISE)
	_dome.material_override = _dome_mat
	_dome.scale = Vector3.ONE * DOME_R
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)
	# 剑气、拖在后面的光柱、破云后的天光
	_blade = _strip(1.0, 0.0, 9.0)
	_pillar = _strip(0.0, 0.0, 6.0)
	(_pillar.material_override as ShaderMaterial).set_shader_parameter("wave", 1.0)
	_shaft = _strip(0.0, 1.0, 1.6)
	var shm := _shaft.material_override as ShaderMaterial
	shm.set_shader_parameter("core", Color(1.0, 0.9, 0.62))
	shm.set_shader_parameter("edge_col", Color(1.0, 0.6, 0.2))
	# 元婴
	_spirit = Node3D.new()
	add_child(_spirit)
	_spirit.position = _g
	_spirit.rotation.y = yaw0 + PI           # 面朝镜头原来的位置（也就是面朝主角）
	_spirit.scale = Vector3.ONE * (SPIRIT_H / 2.0)
	_shero = VoxelHero.new({}, true, false, 3)
	_spirit.add_child(_shero)
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY
	_body_mat.set_shader_parameter("base_y", _g.y)
	_body_mat.set_shader_parameter("height", SPIRIT_H)
	_body_mat.set_shader_parameter("reveal", 0.0)
	for mi: MeshInstance3D in _shero.find_children("*", "MeshInstance3D", true, false):
		if mi == _shero.cloth:
			mi.visible = false
			continue
		mi.material_override = _body_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 双目：两块亮的小方块，前面各一团光
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.1, 1.5, 1.4)
	for sx: float in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.075, 0.04, 0.02)
		e.mesh = bm
		e.material_override = em
		e.position = Vector3(sx * 0.1, 0.258, -0.236)
		e.visible = false
		_shero.head.add_child(e)
		_eyes.append(e)
		var gl := _quad(HALO)
		var gm := gl.material_override as ShaderMaterial
		gm.set_shader_parameter("ring", 0.0)
		gm.set_shader_parameter("rays", 0.5)
		gm.set_shader_parameter("power", 0.8)
		gl.scale = Vector3.ONE * 0.2
		gl.position = Vector3(0.0, 0.0, -0.02)
		gl.rotation.y = PI
		e.add_child(gl)
	_spirit.visible = false
	# 光轮
	_halo = _quad(HALO)
	_halo_mat = _halo.material_override as ShaderMaterial
	_halo_mat.set_shader_parameter("power", 0.0)
	_halo_mat.set_shader_parameter("radius", 0.21)
	add_child(_halo)
	_halo.rotation.y = yaw0
	_halo.scale = Vector3.ONE * 60.0
	_halo.visible = false
	# 电影黑边
	var cl := CanvasLayer.new()
	cl.layer = 36
	add_child(cl)
	for i in 2:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(r)
		_bars.append(r)
	player.hero.set_glow(0.3, TEAL)
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		_dof_was = attr.dof_blur_far_enabled
		attr.dof_blur_far_enabled = false
	Sfx.play("ascend", -4.0, 0.45)
	_primer = Node3D.new()
	add_child(_primer)
	for sh: Shader in [QI, HALO, RIPPLE, BODY]:
		var pm := _quad(sh)
		(pm.material_override as ShaderMaterial).set_shader_parameter("alpha" if sh == BODY else "power", 0.0)
		pm.extra_cull_margin = 0.0
		pm.scale = Vector3.ONE * 0.05
		_primer.add_child(pm)


func _exit_tree() -> void:
	if playing == self:
		playing = null
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.velocity = Vector3.ZERO
		if _lift > 0.01:
			player.global_position = base
		if player.hero != null:
			player.hero.set_glow(0.0, TEAL)
	if is_instance_valid(cam):
		cam.cine_k = 0.0
		var attr := cam.cam.attributes as CameraAttributesPractical
		if attr != null:
			attr.dof_blur_far_enabled = _dof_was
	_restore_ui()


func _quad(shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = shader
	if shader == QI or shader == HALO:
		m.set_shader_parameter("noise_tex", NOISE)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	return mi


## 一条竖着的光带（剑气 / 光柱 / 天光）
func _strip(tip: float, taper: float, flow: float) -> MeshInstance3D:
	var mi := _quad(QI)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("tip", tip)
	m.set_shader_parameter("taper", taper)
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("power", 0.0)
	mi.visible = false
	add_child(mi)
	return mi


## 把一条光带摆成：底在 from、顶在 from 正上方 length 米、宽 width，面朝镜头（只绕竖轴转）
func _place(mi: MeshInstance3D, from: Vector3, length: float, width: float, eye: Vector3, power: float) -> void:
	mi.visible = power > 0.005 and length > 0.5
	if not mi.visible:
		return
	mi.position = from + Vector3.UP * length * 0.5
	mi.scale = Vector3(width, length, 1.0)
	mi.rotation.y = atan2(eye.x - from.x, eye.z - from.z)
	(mi.material_override as ShaderMaterial).set_shader_parameter("power", power)


func _first(key: String) -> bool:
	if _once.has(key):
		return false
	_once[key] = true
	return true


static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _input(e: InputEvent) -> void:
	if _t < 1.5 or _t > T_OUT - 0.3:
		return
	var hit := (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) \
			or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) \
			or ((e.is_action_pressed("attack") or e.is_action_pressed("jump")) and not e.is_echo())
	if hit:
		get_viewport().set_input_as_handled()
		_t = T_OUT - 0.3       # 跳到结尾：中间没放的事件下一帧一起补上


func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(cam):
		queue_free()
		return
	# 演出期间人钉在原地，不吃移动（雷劫收尾会把处理模式交还，这里每帧再按住）
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.05)
	if _perf:
		var now := Time.get_ticks_usec()
		if _perf_last > 0:
			_perf_log.append(Vector2(_t, float(now - _perf_last) * 0.001))
			_perf_cpu.append(Vector2(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_perf_last = now
	_t += dt
	var t := _t
	# 腾空：开头缓缓升起，收功时落回地面
	_lift = LIFT * _ease((t - 0.2) / 1.5) * (1.0 - _ease((t - T_OUT) / (T_END - T_OUT - 0.25)))
	player.global_position = base + Vector3.UP * _lift
	if player.hero != null and player.hero.has_method("animate"):
		player.hero.animate(dt, 0.0, 0.0, false, true)
	var pc := player.global_position + Vector3(0.0, 0.95, 0.0)
	var pierce := Vector3(pc.x, base.y + CLOUD_H, pc.z)
	var shot := _camera(t, pc)
	var eye: Vector3 = shot[0]
	eye.y = maxf(eye.y, base.y + 0.45)       # 低机位别钻到地面以下
	if cam.floor_fn.is_valid():
		eye.y = maxf(eye.y, float(cam.floor_fn.call(eye.x, eye.z)) + 0.8)
	var look: Vector3 = shot[1]
	cam.cine_xf = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	cam.cine_fov = float(shot[2])
	cam.cine_k = 1.0 - smoothstep(T_END - 0.5, T_END, t)
	if _primer != null:
		# 摆在镜头正前方（镜头这一帧才切过去，两个位置都放得进视野：跟着真实镜头走）
		var cx := cam.cam.global_transform
		_primer.global_transform = Transform3D(cx.basis, cx.origin - cx.basis.z * 3.0)
		_primer_n += 1
		if _primer_n > 4:
			_primer.queue_free()
			_primer = null

	# ---- 天色 ----
	# 分两步亮：破云时先亮一半（洞口已是白昼、远处的云还压着，金色天光才显得出来），特写过后才是大白天
	var day := 0.55 * smoothstep(T_BREAK + 0.1, T_BREAK + 1.9, t) + 0.45 * smoothstep(T_FACE + 0.6, T_PULL + 0.5, t)
	dark = smoothstep(0.0, 1.6, t) * (1.0 - day)
	gold = day * (1.0 - smoothstep(T_OUT, T_END, t))
	tear_k = 0.0
	if t > T_PIERCE:
		tear_k = 0.3 * (1.0 - pow(1.0 - clampf((t - T_PIERCE) / 0.6, 0.0, 1.0), 3.0)) + 0.08 * smoothstep(T_PIERCE, T_BREAK, t) \
				+ 0.42 * smoothstep(T_BREAK, T_BREAK + 2.0, t)
	var backdrop := 0.0
	if t >= T_FACE:
		backdrop = 1.0 - smoothstep(T_PULL, T_PULL + 1.3, t)
	_flash = maxf(_flash - dt * 6.0, 0.0)
	_dome.position = eye
	_dome_mat.set_shader_parameter("fade", smoothstep(0.0, 1.2, t) * (1.0 - smoothstep(T_OUT + 0.3, T_END, t)))
	_dome_mat.set_shader_parameter("day", day)
	_dome_mat.set_shader_parameter("tear", tear_k)
	_dome_mat.set_shader_parameter("tear_dir", (pierce - eye).normalized())
	_dome_mat.set_shader_parameter("backdrop", backdrop)
	_dome_mat.set_shader_parameter("flash", _flash)
	# 云里的闷雷（破云之前）
	_amb -= dt
	if _amb <= 0.0 and t > 0.5 and t < T_BREAK:
		_amb = randf_range(0.18, 0.5)
		var a := randf() * TAU
		var p0 := pc + Vector3(cos(a) * randf_range(30.0, 110.0), randf_range(90.0, 150.0), sin(a) * randf_range(30.0, 110.0))
		Vfx.lightning(p0, p0 + Vector3(randf_range(-30.0, 30.0), randf_range(-40.0, -12.0), randf_range(-30.0, 30.0)), Color(0.7, 1.0, 0.9), 0.5, 0.18, 7)
		_flash = maxf(_flash, 0.3)

	# ---- 剑气 ----
	if t >= T_LAUNCH:
		if _first("launch"):
			Vfx.takeoff_burst(pc, TEAL, 2.2)
			Vfx.shockwave(pc, Vector3.UP, Color.WHITE.lerp(TEAL, 0.4), 4.0)
			Vfx.line_sparks(pc, Vector3.UP, Color(1.0, 0.88, 0.5), 40, 30.0, 60.0, 0.7)
			Sfx.play("swing_heavy", 0.0, 0.55)
			Sfx.play("slam", -1.0, 0.7)
			cam.add_trauma(0.8)
			cam.impact(0.6)
		# 拔地而起：先慢后快（越飞越快），穿云之后接着往上
		var u := (t - T_LAUNCH) / (T_PIERCE - T_LAUNCH)
		var tip := 8.0 + (CLOUD_H + 22.0) * pow(clampf(u, 0.0, 1.0), 2.2) + maxf(u - 1.0, 0.0) * 420.0
		var blen := minf(120.0, tip)
		var qp := 1.0 - smoothstep(T_PIERCE + 0.2, T_PIERCE + 1.2, t)
		_place(_blade, Vector3(pc.x, pc.y + tip - blen, pc.z), blen, minf(72.0, blen * 0.6 + 10.0), eye, 1.0 * qp)
		# 光柱：先是青的，破云之后转金、变宽、淡掉
		var pm := _pillar.material_override as ShaderMaterial
		pm.set_shader_parameter("core", Color(0.86, 1.0, 0.97).lerp(Color(1.0, 0.95, 0.78), day))
		pm.set_shader_parameter("edge_col", Color(0.16, 0.86, 0.78).lerp(Color(1.0, 0.72, 0.32), day))
		_place(_pillar, pc, minf(tip - blen * 0.3, CLOUD_H + 40.0), lerpf(40.0, 52.0, day), eye,
				(0.62 + 0.14 * sin(t * 9.0)) * (1.0 - smoothstep(T_BREAK + 0.6, T_BREAK + 2.2, t)))
		# 拖尾的空间波动：扭曲跟着剑尾走，沿途荡开一圈圈环
		if qp > 0.02:
			Vfx.warp_pos = Vector3(pc.x, pc.y + clampf(tip - blen * 0.5, 4.0, 90.0), pc.z)
			Vfx.warp_k = maxf(Vfx.warp_k, 0.035 * qp)
		# 沿途荡开的气浪
		while tip > _ring_y and _ring_y < CLOUD_H - 20.0:
			_ripple(Vector3(pc.x, pc.y + _ring_y, pc.z), 44.0 + _ring_y * 0.22)
			_ring_y += 20.0 + _ring_y * 0.16
		if t >= T_PIERCE and _first("pierce"):
			_ripple(pierce - Vector3.UP * 6.0, 170.0)
			Sfx.play("slam", 0.0, 0.45)
			Sfx.play("ascend", -2.0, 0.7)
			cam.add_trauma(0.9)
			cam.impact(1.0)
			_flash = 1.0
	# 破云后的天光：从云洞泻到地上
	_place(_shaft, _g, CLOUD_H, 84.0, eye, 0.85 * smoothstep(T_BREAK + 0.15, T_BREAK + 1.1, t) * (1.0 - 0.75 * backdrop) * (1.0 - smoothstep(T_PULL, T_PULL + 1.6, t)))
	for i in range(_ripples.size() - 1, -1, -1):
		var rp: Array = _ripples[i]
		rp[1] = float(rp[1]) + dt
		var age := float(rp[1]) / float(rp[2])
		var rmi: MeshInstance3D = rp[0]
		if age >= 1.0:
			rmi.queue_free()
			_ripples.remove_at(i)
		else:
			(rmi.material_override as ShaderMaterial).set_shader_parameter("age", age)
	if t >= T_BREAK + 0.3 and _first("day"):
		Sfx.play("ascend", -1.0, 1.1)

	# ---- 元婴 ----
	if t >= T_SPIRIT:
		if _first("spirit"):
			_spirit.visible = true
			_halo.visible = true
			Sfx.play("ascend", 0.0, 0.6)
		var out := smoothstep(T_OUT, T_END - 0.3, t)
		_shero.animate(dt, 0.0, 0.0, false, false)
		_shero.arm_l.rotation.z -= 0.24
		_shero.arm_r.rotation.z += 0.24
		_shero.head.rotation.x = -0.1
		# 收功：缩小、落回主角体内
		var sc := lerpf(SPIRIT_H / 2.0, 0.6, out * out)
		_spirit.scale = Vector3.ONE * sc
		_spirit.position = (_g + Vector3.UP * sin(t * 0.8) * 0.35).lerp(player.global_position, out * out)
		_body_mat.set_shader_parameter("reveal", smoothstep(T_SPIRIT, T_FACE + 0.75, t))
		_body_mat.set_shader_parameter("alpha", 0.96 * (1.0 - smoothstep(0.5, 1.0, out)))
		_body_mat.set_shader_parameter("boost", 1.0 + 1.0 * out)
		_body_mat.set_shader_parameter("base_y", _spirit.position.y)
		_body_mat.set_shader_parameter("height", sc * 2.0)
		var head := _spirit.position + Vector3.UP * (sc * 1.556)
		_halo.position = head + _f * (sc * 0.22)
		_halo.scale = Vector3.ONE * (sc * 5.0)
		var lit := smoothstep(T_EYES, T_EYES + 0.5, t)
		_halo_mat.set_shader_parameter("open", 1.0 - pow(1.0 - clampf((t - T_EYES) / 0.7, 0.0, 1.0), 3.0))
		_halo_mat.set_shader_parameter("power", lit * (1.0 - out))
		_halo_mat.set_shader_parameter("burst", smoothstep(T_FAR - 0.2, T_FAR + 0.9, t))
		if t >= T_EYES and _first("eyes"):
			for e: MeshInstance3D in _eyes:
				e.visible = true
				Vfx.glint(e.global_position + _b * 0.6, Color(0.8, 1.0, 0.95), 7.0)
			Sfx.play("perfect", 0.0, 0.7)
			cam.add_trauma(0.35)
			Vfx.warp_pos = head
			Vfx.warp_k = maxf(Vfx.warp_k, 0.03)
		if t >= T_REVEAL and _first("revealed"):
			_show_banner_only()
			revealed.emit()
		if out > 0.0 and _first("absorb"):
			Sfx.play("ascend", 0.0, 1.3)
		if out >= 0.98 and _first("absorbed"):
			Vfx.shockwave(player.global_position + Vector3.UP, Vector3.UP, TEAL, 2.0)
			Vfx.glint(player.global_position + Vector3.UP, Color(0.85, 1.0, 0.95), 3.0)

	# ---- 界面：整段过场都收着（手机上的按键也收），黑边收起时才回来；只有境界题字在元婴现形那一刻就露出来 ----
	if t < T_UI:
		# 头一秒里隔一会儿扫一次（界面层可能晚一两帧才建出来），之后只在一层都没按住时再找；原来是头一秒每帧都把整棵场景树扫一遍
		if t >= _veil_next and (t < 1.0 or _veiled.is_empty()):
			_veil_next = t + 0.25
			_veil_ui()
		for n in _veiled:
			if is_instance_valid(n) and _banner_layers.find(n) < 0:
				n.visible = false
		for c in _kids:
			if is_instance_valid(c):
				c.visible = false
	elif _first("ui_back"):
		_restore_ui()

	# ---- 黑边 ----
	var vs := get_viewport().get_visible_rect().size
	var bh := vs.y * 0.105 * smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(T_END - 0.6, T_END, t))
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(vs.x, bh)
	_bars[1].position = Vector2(0.0, vs.y - bh)
	_bars[1].size = Vector2(vs.x, bh)

	if _hide != "":
		if _hide.contains("sky"):
			_dome.visible = false
		if _hide.contains("strips"):
			_blade.visible = false
			_pillar.visible = false
			_shaft.visible = false
		if _hide.contains("halo"):
			_halo.visible = false
		if _hide.contains("body"):
			_spirit.visible = false

	if t >= T_END:
		if _first("revealed"):
			_restore_ui()
			revealed.emit()
		if _perf:
			_perf_report()
		done.emit()
		queue_free()


## `--yy-perf` 的小结：每个分镜的帧数、中位 / 95% / 最长帧耗时、超过 33 毫秒的帧数；再列出所有明显的长帧（时间点 + 毫秒）
func _perf_report() -> void:
	var names := ["一 天地异象", "二 剑气冲天", "三 光柱入云", "四 破云见日", "五 正面特写", "六 拉远", "七 全景"]
	var cuts := [0.0, T_LAUNCH, T_WIDE, T_BREAK, T_FACE, T_PULL, T_FAR, T_END + 1.0]
	var all: Array = []
	for v: Vector2 in _perf_log:
		all.append(v.y)
	all.sort()
	var med_all: float = all[all.size() / 2] if not all.is_empty() else 0.0
	print("[yyperf] 不画=%s 共 %d 帧，整段中位 %.1fms（%.0f 帧/秒）" % [_hide if _hide != "" else "无", all.size(), med_all, 1000.0 / maxf(med_all, 0.01)])
	for i in names.size():
		var ms: Array = []
		var cpu: Array = []
		var draws: Array = []
		for j in _perf_log.size():
			var v: Vector2 = _perf_log[j]
			if v.x >= float(cuts[i]) and v.x < float(cuts[i + 1]):
				ms.append(v.y)
				cpu.append(_perf_cpu[j].x)
				draws.append(_perf_cpu[j].y)
		if ms.is_empty():
			continue
		ms.sort()
		cpu.sort()
		draws.sort()
		var over := 0
		for m: float in ms:
			if m > 33.0:
				over += 1
		print("[yyperf]   %s：%d 帧 中位 %.1fms 95%% %.1fms 最长 %.0fms 超 33ms 的 %d 帧｜其中逻辑 %.1fms，绘制调用 %d" % [names[i], ms.size(), ms[ms.size() / 2],
				ms[int(float(ms.size() - 1) * 0.95)], ms[ms.size() - 1], over, cpu[cpu.size() / 2], int(draws[draws.size() / 2])])
	var long_txt := ""
	for v: Vector2 in _perf_log:
		if v.y > maxf(med_all * 2.5, 14.0):
			long_txt += " %.2fs:%.0f" % [v.x, v.y]
	print("[yyperf]   长帧（过场时间:毫秒）%s" % (long_txt if long_txt != "" else " 无"))


func _veil_ui() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for n in scene.find_children("*", "CanvasLayer", true, false):
		if n.get_parent() == self or not n.visible:
			continue
		var scr = n.get_script()
		var path := "" if scr == null else str(scr.resource_path)
		if not (n is Hud) and not path.ends_with("raid_hud.gd") and not path.ends_with("boss_hud.gd") and not path.ends_with("touch_controls.gd"):
			continue
		n.visible = false
		if _veiled.find(n) < 0:
			_veiled.append(n)


static func _is_banner(n: Node) -> bool:
	var scr = n.get_script()
	return scr != null and str(scr.resource_path).ends_with("realm_banner.gd")


## 元婴现形：带境界题字的那几层先放回来，但层里别的东西（血条、按钮、说明）继续按着，画面上只多出题字
func _show_banner_only() -> void:
	for n in _veiled:
		if not is_instance_valid(n) or _banner_layers.find(n) >= 0:
			continue
		var has := false
		for c in n.get_children():
			has = has or _is_banner(c)
		if not has:
			continue
		_banner_layers.append(n)
		n.visible = true
		for c in n.get_children():
			if c is CanvasItem and not _is_banner(c) and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				_kids.append(c)


func _restore_ui() -> void:
	for c in _kids:
		if is_instance_valid(c):
			c.visible = true
	_kids.clear()
	_banner_layers.clear()
	for n in _veiled:
		if is_instance_valid(n):
			n.visible = true
	_veiled.clear()


## 剑气冲过的地方荡开一圈气浪（平放的环，往外扩着淡掉）
func _ripple(at: Vector3, radius: float) -> void:
	var mi := _quad(RIPPLE)
	add_child(mi)
	mi.position = at
	mi.rotation.x = -PI * 0.5
	mi.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
	_ripples.append([mi, 0.0, 1.0 + radius * 0.005])


## 各分镜的机位：[镜头位置, 看向哪里, 视野]。分镜之间是硬切，分镜里面是缓动的推、摇、拉
func _camera(t: float, pc: Vector3) -> Array:
	var up := Vector3.UP
	var pf := _g + up * (SPIRIT_H * 0.778)        # 元婴的眉眼
	if t < T_LAUNCH:
		# 贴在主角身后跟着升起来，慢慢仰头看天
		var e := _ease(t / T_LAUNCH)
		# 先平视着人离地，再越来越快地仰上去
		return [pc + _b * lerpf(6.0, 9.0, e) + _s * 2.6 + up * lerpf(0.4, -0.9, e), pc + _f * 10.0 + up * lerpf(1.5, 24.0, e * e * e), lerpf(50.0, 64.0, e)]
	if t < T_WIDE:
		var u := (t - T_LAUNCH) / (T_WIDE - T_LAUNCH)
		return [_top + _b * lerpf(46.0, 40.0, u) - _s * 16.0 + up * 0.5, pc + up * lerpf(12.0, 58.0, u * u), 76.0 - 4.0 * u]
	if t < T_BREAK:
		var u2 := (t - T_WIDE) / (T_BREAK - T_WIDE)
		return [_top + _b * lerpf(112.0, 96.0, u2) + _s * 46.0 + up * 3.0, _top + up * lerpf(58.0, 100.0, _ease(u2 * 1.8)), 52.0]
	if t < T_FACE:
		# 从云洞摇下来，落到正在显形的元婴身上
		var u3 := (t - T_BREAK) / (T_FACE - T_BREAK)
		return [_top + _b * lerpf(76.0, 66.0, u3) - _s * 34.0 + up * 2.0, _top + _f * 20.0 + up * lerpf(120.0, 30.0, _ease(u3)), 60.0]
	if t < T_PULL:
		# 特写：略低于眉眼、微微仰拍，背景里只有天
		var u4 := (t - T_FACE) / (T_PULL - T_FACE)
		return [pf + _b * lerpf(56.0, 47.0, u4) + _s * lerpf(3.0, 0.0, u4) - up * 14.0, pf - up * 0.4, lerpf(37.0, 34.0, u4)]
	if t < T_FAR:
		var e5 := _ease((t - T_PULL) / (T_FAR - T_PULL))
		var ang := lerpf(0.0, 0.62, e5)
		var rad := lerpf(47.0, 96.0, e5)
		var h := lerpf(pf.y - 14.0, _top.y + 2.0, e5)
		return [Vector3(_g.x, h, _g.z) + (_b * cos(ang) + _s * sin(ang)) * rad, (pf - up * 0.4).lerp(_g + up * SPIRIT_H * 0.56, e5), lerpf(34.0, 58.0, e5)]
	# 全景：主角在前景，元婴顶天立地；收功时机位留在高处（不跟着落进树丛里），低头看元婴缩回主角体内、人落回地面
	var u6 := clampf((t - T_FAR) / (T_OUT - T_FAR), 0.0, 1.0)
	var out := _ease((t - T_OUT) / (T_END - T_OUT - 0.25))
	return [_top + _b * lerpf(15.0, 20.0, u6) - _s * 5.0 + up * 1.2, (_g + up * SPIRIT_H * lerpf(0.6, 0.56, u6)).lerp(pc + up * 0.4, out), lerpf(72.0, 60.0, out)]
