extends Node3D
## 暴气觉醒期间挂在修士身上的两样东西（air_melee.gd 的 _awaken 起；联机里别人觉醒由 remote_player.gd 起）：
##   1 描边：沿身体外轮廓一圈境界色的亮线（VoxelHero.set_outline）—— 所有境界都有
##   2 空间波动：元婴及以上，身周一圈圈往外荡的扭曲（aura_warp.gdshader）；境界越高范围越大、荡得越凶、越频繁地迸一道更强的波前
## 自己每帧看觉醒还剩多久；人化作遁光 / 陨落时两样都收起来；觉醒结束淡出后停掉 _process，下次觉醒 start() 再接着用。
## 开销：描边 = 身体那二十来件多画一遍背面；波动 = 一张面片（桌面档读屏幕做折射，手机档不读屏幕、只画淡淡的波纹线）。
## 故意不写 class_name：用 preload 引用。

const WARP := preload("res://shaders/aura_warp.gdshader")
const LINE_A := preload("res://shaders/block_outline.gdshader")
const LINE_B := preload("res://shaders/cape_outline.gdshader")
const TRAIL := preload("res://shaders/trail.gdshader")      # 空战对手被打飞时的拖尾：和上面三个一起预编（见 warmup.gd 的 AWAKE）
const FADE_IN := 0.35
const FADE_OUT := 0.6
const WARP_REALM := 3          # 元婴
const CENTER_Y := 0.95

var hero: Node3D               # VoxelHero（要有 set_outline）
var body: Node3D               # 身体根：取位置和朝向
var src: Object                # 有 awake_t 的那位（本机主角的 air_melee）；没有就按 left 自己倒数
var hidden_fn := Callable()    # 返回 true = 这会儿人不在（化作遁光 / 陨落）
var left := 0.0
var realm_idx := 2
var color := Color(0.5, 0.9, 1.0)

## 这三个着色器在当前环境里编过了没有（warmup.gd 载入时预热过就置 true）。手机 / 网页那套渲染是第一次画到才现编，
## 没编过就等到觉醒那一下才编，正好卡在最要紧的地方
static var primed := false
## 性能对照用的开关（main.gd 的 --spark-perf）：单独关掉描边 / 空间波动，量各自的开销
static var debug_no_line := false
static var debug_no_warp := false
static var debug_no_ribbon := false     # 觉醒时脚下一阵阵上扬的丝带（air_melee.gd 里放的）

var _k := 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _pulse := 1.0
var _pulse_cd := 0.5


func _init() -> void:
	set_process(false)


## 还没预热过的话（载入时不到结丹）：一进空战（air_melee.gd 的 tick）就在镜头前各摆一粒看不见大小的面片，把着色器先编好
static func prime(host: Node3D) -> void:
	if primed or not host.is_inside_tree():
		return
	var cam := host.get_viewport().get_camera_3d()
	if cam == null:
		return
	primed = true
	var holder := Node3D.new()
	host.add_child(holder)
	var quad := QuadMesh.new()
	var shaders: Array = [WARP, LINE_A, LINE_B, TRAIL]
	for i in shaders.size():
		var m := ShaderMaterial.new()
		m.shader = shaders[i]
		m.set_shader_parameter("power", 0.02)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		holder.add_child(mi)
		mi.global_transform = Transform3D(cam.global_basis.orthonormalized().scaled(Vector3.ONE * 0.01),
				cam.global_position - cam.global_basis.z * 2.0 - cam.global_basis.y * 1.2 + cam.global_basis.x * (-2.0 + float(i) * 0.05))     # 画面左下角，一厘米大
	host.get_tree().create_timer(0.25).timeout.connect(holder.queue_free)


## 觉醒了（secs：还剩多久；有 src 的以它的 awake_t 为准）
func start(secs: float, realm_i: int, col: Color) -> void:
	left = secs
	realm_idx = realm_i
	color = col
	_pulse = 0.0          # 觉醒那一下先迸一道
	_pulse_cd = _period()
	set_process(true)


func strength() -> float:
	return _k


func warp_on() -> bool:
	return _quad != null and _quad.visible


func _tier() -> int:
	return clampi(realm_idx - WARP_REALM, 0, 4)


func _period() -> float:
	return 2.6 - 0.3 * float(_tier())


func _process(dt: float) -> void:
	if src != null:
		left = float(src.get("awake_t"))
	else:
		left -= dt
	var gone := hidden_fn.is_valid() and bool(hidden_fn.call())
	var want := 1.0 if left > 0.0 and not gone else 0.0
	var rate := FADE_IN if want > _k else (0.12 if gone else FADE_OUT)
	_k = move_toward(_k, want, dt / rate)
	if is_instance_valid(hero):
		hero.call("set_outline", 0.0 if debug_no_line else _k, color)
	_tick_warp(dt)
	if _k <= 0.0 and left <= 0.0:
		set_process(false)


func _tick_warp(dt: float) -> void:
	if realm_idx < WARP_REALM or _k <= 0.01 or not is_instance_valid(body) or debug_no_warp:
		if _quad != null:
			_quad.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _quad == null:
		_build_quad()
	_pulse_cd -= dt
	if _pulse_cd <= 0.0:
		_pulse_cd = _period()
		_pulse = 0.0
	_pulse = minf(_pulse + dt / 0.85, 1.0)
	var tier := float(_tier())
	var radius := 2.0 + 0.25 * tier
	var cb := cam.global_basis.orthonormalized()
	_quad.visible = true
	_quad.global_transform = Transform3D(cb.scaled(Vector3.ONE * radius * 2.0), body.global_position + body.global_basis.y.normalized() * CENTER_Y)
	# 身体在屏幕上的朝向（面片的 UV：x 向右、y 向下）
	var up := body.global_basis.y
	var ax := Vector2(up.dot(cb.x), -up.dot(cb.y))
	_mat.set_shader_parameter("axis", ax.normalized() if ax.length_squared() > 0.01 else Vector2(0.0, 1.0))
	_mat.set_shader_parameter("power", _k)
	_mat.set_shader_parameter("strength", 0.018 + 0.005 * tier)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("tint", color)


func _build_quad() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = WARP
	_mat.render_priority = -100      # 抢在别的半透明特效之前画：它们叠在扭曲过的画面上面，不会被盖掉
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.top_level = true
	_quad.extra_cull_margin = 2.0
	add_child(_quad)
