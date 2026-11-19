extends Node3D
## 旋涡门（只给 R 大罡剑阵用，见 gate_array.gd；暴雨梨花、点按法术、Q 飞剑阵都不开门）。
## 原样使用 tornado_portal（VFX-sketchbook/effects/tornado_portal，已复制到 res://fx/tornado_portal/）
## portal_preview.tscn 的整套节点、材质和 default 动画，只是整体竖起来悬在半空、门口朝向目标：
##   Rim        门口的"地面"：preview 里 GroundMesh 的着色器（portal_rim.gdshader，深紫近黑）。原版的洞是在地面上抠的，
##              悬空没有地面，靠它遮住门后的光锥，光锥只从 Hole 的旋涡里透出来；飞剑剑尖从门心探出时剑身也被它挡住
##   Hole       旋涡面：portal_effect.gdshader 原样（swirl + 极坐标 voronoi 视差深度，屏幕纹理透出门后光锥）
##   HoleBody   门后漏斗光锥：portal_light_mat 原样
##   HaloLight  门口一圈向外飘的光雾：halo_light_mat 原样
##   TrailsParticles / SmallParticles  门里涌出的拖尾细丝 + 小光点：trail_particles_mat / small_particles_mat 原样
##   Attractor  收门前把粒子吸回门里：GPUParticlesAttractorSphere3D，同原版
## 时间轴：原版 default 动画（4s）的关键帧照抄在 K_* 里。0~0.7s 的张开（opening 0→1，Hole 放大到 1.2 再回 1）按原速播，
## 0.7~3.0s 的保持段按本门寿命 life 等比拉伸，3.0~3.4s 的收拢段原速播，播完自己释放。
## 悬空的改动只有：门整体缩放 = 半径 / 2（原版门半径 2 米）；光锥深度压到 DEPTH 倍、随 opening 张开（悬空时侧面没有地面挡着）；
## 粒子的重力从"世界向上"改成"沿门口朝外"。
## 故意不写 class_name：用 preload 引用。

const RIM_SHADER := preload("res://fx/tornado_portal/portal_rim.gdshader")
const HOLE_MAT := preload("res://fx/tornado_portal/materials/portal_effect_mat.tres")
const LIGHT_MAT := preload("res://fx/tornado_portal/materials/portal_light_mat.tres")
const HALO_MAT := preload("res://fx/tornado_portal/materials/halo_light_mat.tres")
const TRAIL_MAT := preload("res://fx/tornado_portal/materials/trail_particles_mat.tres")
const SMALL_SHADER := preload("res://fx/tornado_portal/materials/small_particles.gdshader")
const SMALL_PROCESS := preload("res://fx/tornado_portal/materials/small_particles_mat.tres")

## 原版 default 动画的关键帧：[时刻, 值, 过渡]（过渡同 Animation 的 transition，即 ease(x, c)）
const K_OPENING := [[0.0, 0.0, 1.0], [0.5, 1.0, 0.5], [3.0, 1.0, -2.0], [3.4, 0.0, 2.0]]
const K_HOLE_S := [[0.0, 1.0, 2.0], [0.5, 1.2, -2.0], [0.7, 1.0, -2.0], [3.0, 1.0, -2.0], [3.4, 0.0, -2.0]]
const K_HALO_S := [[0.0, 0.0, -2.0], [0.5, 1.0, -2.0], [3.0, 1.0, -2.0], [3.4, 0.0, -2.0]]
const K_HALO_A := [[0.2, 0.0, 1.0], [0.5, 1.0, 1.0], [3.0, 1.0, 1.0], [3.2, 0.0, 1.0]]
const K_PULL := [[2.3, 0.0, 1.0], [2.7, 40.0, 1.0]]
const K_SPIN := [[-1.5, 0.0, 4.0], [4.0, 8.0, 0.5]]   # Hole 的 time_offset：旋涡越转越快
const EMIT_END := 2.5      # 原版粒子停发时刻
const OPEN_T := 0.7        # 原版张开 + 回弹段（原速播）
const HOLD_END := 3.0      # 原版保持段结束、开始收拢
const END_T := 3.45        # 收拢播完（原版 3.4）后释放
const MAX_LIFE := 14.0     # 兜底：无论如何这么久后一定释放
const DEPTH := 0.6         # 门后光锥深度（相对原版 4 米的比例）
const LIGHT_I := 3.5       # portal_light_mat 的 intensity
const ATTRACT_LAYER := 1 << 19  # 吸引球只吸本类门的粒子，不碰飞剑拖尾等其它粒子

static var _quad: QuadMesh
static var _cone: CylinderMesh
static var _band: CylinderMesh
static var _rim_plane: PlaneMesh
static var _rim_mat: ShaderMaterial
static var _ribbon: RibbonTrailMesh
static var _dot_mesh: QuadMesh
static var _dot_mat: ShaderMaterial
static var _trail_proc: ParticleProcessMaterial

var radius := 1.0
var life := 2.0
var _k := 0.5              # 整体缩放 = 半径 / 2
var _t := 0.0
var _flare := 0.0
var _pending: Array[Vector2] = []  # 待亮的时刻 / 强度
var _vis: Node3D
var _rim: MeshInstance3D
var _hole: MeshInstance3D
var _hole_mat: ShaderMaterial
var _body: MeshInstance3D
var _body_mat: ShaderMaterial
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _trails: GPUParticles3D
var _sparks: GPUParticles3D
var _attr: GPUParticlesAttractorSphere3D


## 在 pos 处张开一扇门口朝 facing、半径 rad 米的门，life_s 秒后开始收拢（从现在算，至少张开完）
static func open(pos: Vector3, facing: Vector3, rad: float, life_s: float) -> Node3D:
	if Vfx.root == null:
		return null
	var g := new()
	g.radius = rad
	g.life = maxf(life_s, OPEN_T + 0.05)
	g._k = rad * 0.5
	Vfx.root.add_child(g)
	g.global_transform = Transform3D(_basis_y(facing), pos)
	g._build()
	return g


## 本地 +Y 对准 f 的正交基
static func _basis_y(f: Vector3) -> Basis:
	var y := f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## 网格尺寸、粒子参数都照抄 portal_preview.tscn 里的 sub_resource
static func _init_shared() -> void:
	if _quad != null:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2(4.0, 4.0)
	_cone = CylinderMesh.new()
	_cone.flip_faces = true
	_cone.top_radius = 2.0
	_cone.bottom_radius = 0.0
	_cone.height = 4.0
	_cone.cap_top = false
	_cone.cap_bottom = false
	_band = CylinderMesh.new()
	_band.top_radius = 1.8
	_band.bottom_radius = 1.4
	_band.height = 1.4
	_band.rings = 2
	_band.cap_top = false
	_band.cap_bottom = false
	_rim_plane = PlaneMesh.new()
	_rim_plane.size = Vector2(8.0, 8.0)
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = RIM_SHADER
	_rim_mat.render_priority = -128
	# TrailsParticles 的拖尾丝带（preview 里的 RibbonTrailMesh_ppf3r）
	var rc := Curve.new()
	rc.add_point(Vector2(0.0, 0.0))
	rc.add_point(Vector2(0.5, 1.0))
	rc.add_point(Vector2(1.0, 0.0))
	_ribbon = RibbonTrailMesh.new()
	_ribbon.shape = RibbonTrailMesh.SHAPE_FLAT
	_ribbon.size = 0.04
	_ribbon.curve = rc
	# TrailsParticles 的 ParticleProcessMaterial（preview 里的 ParticleProcessMaterial_0egtw）
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.0))
	sc.add_point(Vector2(0.2, 1.0))
	sc.add_point(Vector2(0.8, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var grt := GradientTexture1D.new()
	grt.gradient = gr
	_trail_proc = ParticleProcessMaterial.new()
	_trail_proc.lifetime_randomness = 0.2
	_trail_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_trail_proc.emission_sphere_radius = 1.0
	_trail_proc.direction = Vector3(0, 1, 0)
	_trail_proc.initial_velocity_min = 1.0
	_trail_proc.initial_velocity_max = 4.0
	_trail_proc.gravity = Vector3(0, 8, 0)
	_trail_proc.scale_min = 0.4
	_trail_proc.scale_curve = sct
	_trail_proc.color_ramp = grt
	_trail_proc.turbulence_enabled = true
	_trail_proc.turbulence_noise_scale = 3.0
	_trail_proc.turbulence_noise_speed_random = 0.0
	_trail_proc.turbulence_influence_max = 0.2
	# SmallParticles 的绘制：0.1 米小面片 + small_particles 着色器（preview 里的 ShaderMaterial_sdv0b）
	_dot_mesh = QuadMesh.new()
	_dot_mesh.size = Vector2(0.1, 0.1)
	_dot_mat = ShaderMaterial.new()
	_dot_mat.shader = SMALL_SHADER
	_dot_mat.set_shader_parameter("color", Color(0.619608, 0.4, 1.0))
	_dot_mat.set_shader_parameter("intensity", 8.0)


## 原版的重力朝世界上方（门口朝上）；门竖起来以后改成沿门口朝外，速度 / 范围按门的缩放
static func _scaled_proc(src: ParticleProcessMaterial, out: Vector3, k: float) -> ParticleProcessMaterial:
	var p := src.duplicate() as ParticleProcessMaterial
	p.gravity = out * src.gravity.length() * k
	p.initial_velocity_min = src.initial_velocity_min * k
	p.initial_velocity_max = src.initial_velocity_max * k
	p.emission_sphere_radius = src.emission_sphere_radius * k
	return p


func _build() -> void:
	_init_shared()
	var big := radius >= 2.5
	var out := global_basis.y.normalized()
	# 网格部分整体缩放（原版门半径 2 米），粒子不缩放（速度 / 发射范围单独按 _k 缩）
	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * _k
	add_child(_vis)

	_rim = MeshInstance3D.new()
	_rim.mesh = _rim_plane
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(_rim)
	_rim.set_instance_shader_parameter("alpha", 0.0)

	_hole_mat = HOLE_MAT.duplicate() as ShaderMaterial
	_hole = MeshInstance3D.new()
	_hole.mesh = _quad
	_hole.material_override = _hole_mat
	_hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole.rotation.x = -PI * 0.5
	_hole.position.y = 0.02
	_vis.add_child(_hole)

	_body_mat = LIGHT_MAT.duplicate() as ShaderMaterial
	_body = MeshInstance3D.new()
	_body.mesh = _cone
	_body.material_override = _body_mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(_body)

	_halo_mat = HALO_MAT.duplicate() as ShaderMaterial
	_halo = MeshInstance3D.new()
	_halo.mesh = _band
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = 0.7
	_vis.add_child(_halo)

	var aabb := AABB(Vector3.ONE * -8.0 * maxf(_k, 1.0), Vector3.ONE * 16.0 * maxf(_k, 1.0))
	_trails = GPUParticles3D.new()
	_trails.amount = 64 if big else 20
	_trails.lifetime = 2.0
	_trails.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_trails.trail_enabled = true
	_trails.process_material = _scaled_proc(_trail_proc, out, _k)
	_trails.draw_pass_1 = _ribbon
	_trails.material_override = TRAIL_MAT
	_trails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trails.visibility_aabb = aabb
	_trails.layers = 1 | ATTRACT_LAYER
	_trails.position.y = -0.5 * _k
	add_child(_trails)
	_trails.emitting = true

	_sparks = GPUParticles3D.new()
	_sparks.amount = 1024 if big else 240
	_sparks.lifetime = 2.0
	_sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_sparks.process_material = _scaled_proc(SMALL_PROCESS, out, _k)
	_sparks.draw_pass_1 = _dot_mesh
	_sparks.material_override = _dot_mat
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.visibility_aabb = aabb
	_sparks.layers = 1 | ATTRACT_LAYER
	_sparks.position.y = -0.5 * _k
	add_child(_sparks)
	_sparks.emitting = true

	_attr = GPUParticlesAttractorSphere3D.new()
	_attr.strength = 0.0
	_attr.attenuation = 0.5
	_attr.directionality = 0.1
	_attr.radius = 6.0 * _k
	_attr.cull_mask = ATTRACT_LAYER
	_attr.position.y = -1.0 * _k
	add_child(_attr)
	_apply(0.0)


## 门开着的时间延长到从现在起 sec 秒后（不会缩短）
func hold_for(sec: float) -> void:
	life = maxf(life, _t + sec)


## sec 秒后开始收拢（只会提前）
func close_in(sec: float) -> void:
	life = minf(life, maxf(_t + sec, OPEN_T))


## 吐剑：旋涡一跳、门后光锥一亮
func flare(power := 1.0) -> void:
	_flare = maxf(_flare, power)


## delay 秒后吐剑那一刻再亮（剑悬停结束时）；门自己计时，门先收掉也不会有悬空的回调
func flare_in(delay: float, power := 1.0) -> void:
	_pending.append(Vector2(_t + delay, power))


## 按原版关键帧求值
static func _track(keys: Array, t: float) -> float:
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t < float(b[0]):
			var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), ease(u, float(a[2])))
	return float(keys[keys.size() - 1][1])


## 本门时间 → 原版动画时间：张开 / 收拢原速，保持段按 life 拉伸
func _anim_t() -> float:
	if _t < OPEN_T:
		return _t
	if _t < life:
		return OPEN_T + (_t - OPEN_T) * (HOLD_END - OPEN_T) / maxf(life - OPEN_T, 0.01)
	return HOLD_END + (_t - life)


func _apply(a: float) -> void:
	var op := _track(K_OPENING, a)
	var hole_s := _track(K_HOLE_S, a) * (1.0 + 0.12 * _flare)
	var halo_s := maxf(_track(K_HALO_S, a), 0.001)
	_hole_mat.set_shader_parameter("opening", op)
	_hole_mat.set_shader_parameter("time_offset", _track(K_SPIN, a))
	_hole.scale = Vector3(maxf(hole_s, 0.001), maxf(hole_s, 0.001), 1.0)
	# 地面跟光雾一起由一点张开、一起收掉
	_rim.scale = Vector3(halo_s, 1.0, halo_s)
	_rim.set_instance_shader_parameter("alpha", clampf(op * 2.0, 0.0, 1.0))
	var bs := maxf(op * hole_s, 0.001)
	var depth := DEPTH * maxf(op, 0.05)
	_body.scale = Vector3(bs, depth, bs)
	_body.position.y = -2.0 * depth - 0.025
	_body_mat.set_shader_parameter("intensity", LIGHT_I * (1.0 + 1.2 * _flare))
	_halo.scale = Vector3(halo_s, 1.0, halo_s)
	_halo_mat.set_shader_parameter("alpha", _track(K_HALO_A, a))
	var emit := a < EMIT_END
	if _trails.emitting != emit:
		_trails.emitting = emit
		_sparks.emitting = emit
	_attr.strength = _track(K_PULL, a)


func _process(dt: float) -> void:
	_t += dt
	_flare = move_toward(_flare, 0.0, dt * 5.0)
	for i in range(_pending.size() - 1, -1, -1):
		if _t >= _pending[i].x:
			flare(_pending[i].y)
			_pending.remove_at(i)
	var a := _anim_t()
	if a >= END_T or _t >= MAX_LIFE:
		queue_free()
		return
	_apply(a)
