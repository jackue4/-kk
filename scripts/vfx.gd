class_name Vfx
extends RefCounted
## 一次性特效：命中、起飞、破空环、闪现、突破、伤害数字。
## 统一用"线条"语言：细线环、针形剑芒、细十字星、带拖尾的细丝粒子；
## 不再有实心光斑、光柱和大范围加色叠加，点光也只留一点点染色。
## 命中 / 弹反 / 死亡 / 火球另叠一层像素序列帧（pixel()，pixelfx 素材），方像素和体素小人同一种质感。

const SPRITE_SHADER := preload("res://shaders/vfx_sprite.gdshader")
const HALO_SHADER := preload("res://shaders/halo.gdshader")
const DEBRIS := preload("res://scripts/voxel_debris.gd")
const AURA_WARP := preload("res://shaders/aura_warp.gdshader")
const PIXEL := preload("res://scripts/pixel_sheet.gd")
const SHATTER := preload("res://scripts/voxel_shatter.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")    # 2026-11-23 伤害飘字上了万 / 亿：统一短写
## 细丝粒子用 GPUParticles3D 的 Trails + RibbonTrailMesh；改成 false 则退回 CPU 针形粒子
const USE_GPU_TRAILS := true

static var root: Node3D
static var font: Font
## 空间扭曲（飞剑对波的交汇点）：谁要扭曲就每帧写这两个值，main.gd 投到屏幕上交给后处理（speed_blur.gdshader），不写就自己退掉
static var warp_pos := Vector3.ZERO
## 地形破坏的入口（方块大世界里由 meadow_level.gd 接上；大厅 / 老关卡是空的）：func(位置, 半径) -> 接没接
static var terrain_hook := Callable()
static var warp_k := 0.0
## 动态点光（命中的闪光、飞剑 / 火球身上的灯）。手机档关掉：Compatibility 渲染里一盏点光就让它照到的整块地表每个像素多算一遍光照
static var lights := true
## 手机档：命中特效减层（少一道刀光、少一簇火星、放射线减半）；同一帧里的第三个命中起只留最简的一层。
## 一个命中特效是十来个节点（面片 + 材质 + 补间），桌面上零点几毫秒，手机上一刀砍中一群怪就是一个看得见的小卡顿
static var lite := false
static var mute := 0             # 排查用（战斗探针的 --fp-mute=N）：1 = 不放命中特效，2 = 连碎块和伤害数字也不放
static var _hit_frame := -1
static var _hit_n := 0
static var crack_n := 0         # 自检用：一共裂过几道空间裂缝（space_crack）


## 这一帧里第几个命中特效（从 0 数）
static func _hit_rank() -> int:
	var f := Engine.get_process_frames()
	if f != _hit_frame:
		_hit_frame = f
		_hit_n = 0
	_hit_n += 1
	return _hit_n - 1
static var _quad: QuadMesh
static var _halo_quad: QuadMesh
static var _streak_mesh: ArrayMesh
static var _ribbons: Dictionary = {}
static var _fade_ramp: GradientTexture1D
static var _shrink: Curve


static func shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink


static func _line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m


## CPU 针形粒子的网格：沿 +Y 的细长镖形，十字交叉两片，任何角度都看得到一条线
static func streak_mesh() -> ArrayMesh:
	if _streak_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w := 0.03
		var tip := Vector3(0, 0.5, 0)
		var tail := Vector3(0, -0.5, 0)
		for side: Vector3 in [Vector3(w, 0.28, 0), Vector3(0, 0.28, w)]:
			st.add_vertex(tip); st.add_vertex(side); st.add_vertex(tail)
			st.add_vertex(tip); st.add_vertex(tail); st.add_vertex(-side + Vector3(0, 0.56, 0))
		_streak_mesh = st.commit()
		_streak_mesh.surface_set_material(0, _line_material())
	return _streak_mesh


## GPU 粒子拖尾用的细丝带：两头尖，宽度即 width（米）
static func ribbon_mesh(width: float) -> RibbonTrailMesh:
	var key := int(round(width * 1000.0))
	if not _ribbons.has(key):
		var m := _line_material()
		m.use_particle_trails = true
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.0))
		c.add_point(Vector2(0.25, 1.0))
		c.add_point(Vector2(1.0, 0.0))
		var rm := RibbonTrailMesh.new()
		rm.shape = RibbonTrailMesh.SHAPE_FLAT
		rm.size = width
		rm.sections = 8
		rm.section_length = 0.1
		rm.section_segments = 2
		rm.curve = c
		rm.material = m
		_ribbons[key] = rm
	return _ribbons[key]


static func fade_ramp() -> GradientTexture1D:
	if _fade_ramp == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 1))
		_fade_ramp = GradientTexture1D.new()
		_fade_ramp.gradient = g
	return _fade_ramp


## pos 处一个屏幕像素对应的世界长度（用于给细线/小剑影设像素下限）
static func px_size(pos: Vector3) -> float:
	var vp := root.get_viewport()
	var cam := vp.get_camera_3d()
	if cam == null:
		return 0.01
	var depth := maxf((pos - cam.global_position).dot(-cam.global_basis.z), 0.1)
	return 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / maxf(vp.get_visible_rect().size.y, 1.0)


static func _sprite(pos: Vector3, color: Color, mode: int, size: float, billboard := true) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := ShaderMaterial.new()
	m.shader = SPRITE_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("alpha", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size
	return mi


## 常驻面片（遁光头部剑芒、伴飞剑影）：由调用方每帧 place_streak 摆位，自己负责释放
static func persistent_sprite(color: Color, mode: int) -> MeshInstance3D:
	return _sprite(Vector3.ZERO, color, mode, 1.0, false)


## 缩放到 to_scale 并淡出后销毁
static func _fade(mi: MeshInstance3D, to_scale: Vector3, dur: float, delay := 0.0) -> void:
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", to_scale, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi.material_override, "shader_parameter/alpha", 0.0, dur).set_delay(delay).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## 把面片摆成"沿 dir 方向、正对相机"的条带：本地 +X = dir
static func place_streak(mi: Node3D, pos: Vector3, dir: Vector3, length: float, width: float) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var to_cam := Vector3.UP
	if cam != null:
		to_cam = (cam.global_position - pos).normalized()
	var x := dir.normalized()
	var y := to_cam.cross(x)
	if y.length_squared() < 1e-6:
		y = Vector3.UP.cross(x)
	if y.length_squared() < 1e-6:
		y = Vector3.RIGHT
	y = y.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * length, y * width, z), pos)


## 沿 dir 方向、朝向相机的针形剑芒
static func _streak(pos: Vector3, dir: Vector3, color: Color, length: float, width: float) -> MeshInstance3D:
	var mi := _sprite(pos, color, 2, 1.0, false)
	place_streak(mi, pos, dir, length, width)
	return mi


## 针形剑芒：拉长、收细、淡出
static func _slash(pos: Vector3, dir: Vector3, color: Color, length: float, width: float, dur: float) -> void:
	var s := _streak(pos, dir, color, length, width)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3(length * 1.5, width * 0.15, 1.0), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(s.material_override, "shader_parameter/alpha", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)


## CPU 针形火星：便宜，给高频的命中用
static func line_sparks(pos: Vector3, dir: Vector3, color: Color, amount: int, speed: float, spread := 40.0, life := 0.35) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.2
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.75
	p.scale_amount_curve = shrink_curve()
	p.mesh = streak_mesh()
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


## 常驻的上扬细针（手机档用）：一个 CPU 粒子发射器，沿 +Y 往上喷，默认不发射，调用方自己挂、自己开关。
## 聚气 / 蓄力 / 觉醒这类要连着喷好几秒的，手机档别每隔零点一秒 ribbon_burst 一次 —— 那样每次都新建一套 GPU 粒子，
## 网页版实测觉醒期间每帧因此多出约 8 毫秒（2026-11-20，见 main.gd 的 --spark-perf）
static func aura_stream(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 16
	p.lifetime = 0.42
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3.ZERO
	p.damping_min = 6.0
	p.damping_max = 10.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	p.scale_amount_curve = shrink_curve()
	p.mesh = streak_mesh()
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 带 Trails 的 GPU 粒子：每个粒子拖一条细丝带（RibbonTrailMesh），丝带朝向相机、沿速度方向
static func _ribbon_particles(color: Color, amount: int, life: float, trail_life: float, width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.trail_enabled = true
	p.trail_lifetime = trail_life
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.draw_pass_1 = ribbon_mesh(width)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3.ONE * -40.0, Vector3.ONE * 80.0)
	var pm := ParticleProcessMaterial.new()
	pm.color = color
	pm.color_ramp = fade_ramp()
	p.process_material = pm
	return p


## 一次性细丝迸射（起飞、破空、突破、瞬移、击破）
static func ribbon_burst(pos: Vector3, dir: Vector3, color: Color, amount: int, speed: float,
		spread := 30.0, life := 0.45, gravity := Vector3(0, -6.0, 0)) -> void:
	if not USE_GPU_TRAILS:
		line_sparks(pos, dir, color, amount, speed, spread, life)
		return
	var p := _ribbon_particles(color, amount, life, 0.16, 0.035)
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = gravity
	pm.damping_min = speed * 0.8
	pm.damping_max = speed * 1.3
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## 持续细丝流（遁光轨迹旁零星剥落的剑光）。沿节点本地 +Z 喷出，默认不发射；不支持时返回 null
static func ribbon_stream(color: Color, amount: int) -> GPUParticles3D:
	if not USE_GPU_TRAILS:
		return null
	var p := _ribbon_particles(color, amount, 0.42, 0.14, 0.03)
	p.emitting = false
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 36.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	return p


## 筑基御风的风丝：身周一圈极细、半透明的短丝向后掠过（沿节点本地 +Z），不做柔光团。
## 不支持 GPU Trails 时返回 null
static func wind_stream(color: Color) -> GPUParticles3D:
	if not USE_GPU_TRAILS:
		return null
	var p := _ribbon_particles(color, 22, 0.5, 0.12, 0.024)
	p.emitting = false
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 10.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 0.75
	pm.emission_ring_inner_radius = 0.35
	pm.emission_ring_height = 0.6
	return p


static func flash_light(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	if not lights:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


## 像素序列帧特效（见 pixel_sheet.gd 的 SHEETS / play 参数）
static func pixel(id: String, pos: Vector3, opts := {}) -> Node3D:
	return PIXEL.play(root, id, pos, opts)


## 飞剑命中：一道沿出剑方向的细斩痕 + 按境界染色的像素迸溅 + 几根针形火星
static func hit(pos: Vector3, dir: Vector3, color: Color, power := 1.0) -> void:
	_slash(pos, dir, color, 2.6 * power, 0.24, 0.16)
	if lite and _hit_rank() >= 3:
		return
	pixel("hit_spark", pos, {"px": 0.03 * power, "tint": color, "recolor": 0.85, "dir": dir})
	line_sparks(pos, dir, color, 4, 12.0, 38.0, 0.3)
	flash_light(pos, color, 0.8, 4.0, 0.12)


static func damage_number(pos: Vector3, value: float, color: Color) -> void:
	# 2026-11-23：大数短写（1.234万 / 5.6亿）；最少写 1（低境界进高区打怪每下不到 1，别满屏写 0）
	damage_text(pos, NumFmt.fmt(maxf(value, 1.0)), color)


## 飘一串字（和伤害数字同一种字号 / 描边；warmup.gd 拿它预热「0123456789.万亿+-」这些字形）
static func damage_text(pos: Vector3, text: String, color: Color) -> void:
	if mute >= 2:
		return
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 56
	l.pixel_size = 0.008
	l.outline_size = 14
	l.modulate = Color.WHITE.lerp(color, 0.5)
	l.outline_modulate = Color(0.08, 0.08, 0.1, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	root.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0.6, randf_range(-0.4, 0.4))
	l.scale = Vector3.ONE * 0.4
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y + 1.4, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.3).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


## 起飞：贴地一圈细线环 + 几缕向上的细丝（不再有光柱）
static func takeoff_burst(pos: Vector3, color: Color, power: float) -> void:
	var ring := _sprite(pos + Vector3(0, 0.06, 0), color, 1, 0.6, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * (3.0 + 2.2 * power), 0.45)
	ribbon_burst(pos + Vector3(0, 0.15, 0), Vector3.UP, color, int(5 + 5 * power), 9.0 + 7.0 * power, 24.0, 0.5)
	flash_light(pos + Vector3(0, 1, 0), color, 0.7 + 0.3 * power, 6.0, 0.3)


## 破空环：垂直于飞行方向的两圈细线环 + 向后甩出的几缕细丝
static func launch_ring(pos: Vector3, dir: Vector3, color: Color, power: float) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var k := sqrt(maxf(power, 0.1))
	for i in 2:
		var at := pos + dir * (1.2 * i)
		var ring := _sprite(at, color, 1, 0.5, false)
		ring.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3.ONE * 0.5), at)
		_fade(ring, Vector3.ONE * (2.4 + 1.6 * i) * k, 0.35 + 0.1 * i, 0.05 * i)
	ribbon_burst(pos, -dir, color, int(4 + 3 * power), 10.0 + 6.0 * power, 28.0, 0.4, Vector3.ZERO)
	flash_light(pos, color, 0.9, 8.0, 0.25)


## 音爆（起飞后的三段冲刺，见 Player._surge_fire）：垂直于飞行方向的几圈汽环一前一后炸开——越靠后的越大，像音爆云的锥面——
## 起点一闪，再向四周迸一圈细汽线。fx = 境界的效果系数（0~1），stage = 第几段（0~2）：
## 境界越高、段数越靠后，环越多越大、线越多越长。都是现成的面片（不带新着色器），手机档环和线各减一些。
## follow：挂在谁身上跟着走（主角）。遁光一秒飞出去上百米，留在原地的环一眨眼就落到镜头后面去了，所以整组特效跟着人走，
## 只是慢慢往身后漂一点
static func sonic_boom(pos: Vector3, dir: Vector3, color: Color, fx: float, stage: int, follow: Node3D = null) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var holder := Node3D.new()
	if follow != null and follow.is_inside_tree():
		follow.add_child(holder)
	else:
		root.add_child(holder)
	holder.global_transform = Transform3D(Basis.looking_at(d, up), pos)     # 本地 -Z = 飞行方向，+Z = 身后
	var k := (0.5 + 0.95 * fx) * (1.0 + 0.3 * float(stage))
	var white := Color.WHITE.lerp(color, 0.22)
	var rings := 2 + (1 if fx >= 0.45 else 0) + (1 if fx >= 0.8 and stage == 2 else 0)
	if lite:
		rings = mini(rings, 2 + (1 if stage == 2 and fx >= 0.6 else 0))
	var life := 0.0
	for i in rings:
		var ring := _sprite_in(holder, white if i % 2 == 0 else color, 1, false)
		ring.position = Vector3(0.0, 0.0, 0.85 * float(i) * k)
		ring.scale = Vector3.ONE * 0.45 * k
		var dur := 0.28 + 0.07 * float(i)
		var delay := 0.035 * float(i)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "scale", Vector3.ONE * (3.4 + 2.5 * float(i)) * k, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "position:z", ring.position.z + (1.6 + 1.2 * float(i)) * k, dur).set_delay(delay).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring.material_override, "shader_parameter/alpha", 0.0, dur).set_delay(delay).set_ease(Tween.EASE_IN)
		life = maxf(life, dur + delay)
	var f := _sprite_in(holder, Color.WHITE.lerp(color, 0.4), 0, true)
	f.scale = Vector3.ONE * 0.5 * k
	var tf := f.create_tween()
	tf.set_parallel(true)
	tf.tween_property(f, "scale", Vector3.ONE * 2.2 * k, 0.15).set_ease(Tween.EASE_OUT)
	tf.tween_property(f.material_override, "shader_parameter/alpha", 0.0, 0.15).set_ease(Tween.EASE_IN)
	# 一圈向外迸的细汽线（在垂直于飞行方向的平面里，正对着身后的镜头）
	var n := int(4.0 + 8.0 * fx) + stage
	if lite:
		n = (n + 1) / 2
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + randf_range(-0.15, 0.15)
		var out := Vector3(cos(a), sin(a), 0.0)
		var length := (0.9 + 1.5 * fx) * randf_range(0.7, 1.1) * (1.0 + 0.2 * float(stage))
		var ray := _sprite_in(holder, white, 2, false)
		ray.transform = Transform3D(Basis(out * length, out.cross(Vector3.BACK) * 0.06, Vector3.BACK), out * (0.5 * k + length * 0.5))
		var tr := ray.create_tween()
		tr.set_parallel(true)
		tr.tween_property(ray, "position", out * (0.5 * k + length * 0.5 + (1.6 + 3.2 * fx) * k * 0.5) + Vector3(0.0, 0.0, 1.2 * k), 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tr.tween_property(ray.material_override, "shader_parameter/alpha", 0.0, 0.24).set_ease(Tween.EASE_IN)
	root.get_tree().create_timer(maxf(life, 0.26) + 0.05).timeout.connect(holder.queue_free)


## 和 _sprite 一样的面片，但挂在指定节点下、用本地坐标摆（调用方自己设位置 / 缩放）
static func _sprite_in(parent: Node3D, color: Color, mode: int, billboard: bool) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := ShaderMaterial.new()
	m.shader = SPRITE_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("alpha", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 化作光剑的一瞬：剑心一点细十字星
static func sword_form(pos: Vector3, color: Color) -> void:
	glint(pos, Color.WHITE.lerp(color, 0.4), 1.3)


## 闪现起点：垂直于冲刺方向的一圈细环 + 细星 + 向后甩出的细丝
static func dash_start(pos: Vector3, dir: Vector3, color: Color, power: float) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var ring := _sprite(pos, color, 1, 0.4, false)
	ring.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3.ONE * 0.4), pos)
	_fade(ring, Vector3.ONE * (1.8 + 1.2 * power), 0.3)
	var f := _sprite(pos, color, 0, 0.8)
	_fade(f, Vector3.ONE * 1.8, 0.18)
	ribbon_burst(pos, -dir, color, int(5 + 4 * power), 8.0 + 6.0 * power, 30.0, 0.35, Vector3.ZERO)
	flash_light(pos, color, 0.8, 5.0, 0.18)


## 闪现终点：剑尖前一圈收拢的细环 + 顺冲刺方向散开的少量细丝
static func dash_end(pos: Vector3, dir: Vector3, color: Color, power: float) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var ring := _sprite(pos, color, 1, 1.6 + power, false)
	ring.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3.ONE * (1.6 + power)), pos)
	_fade(ring, Vector3.ONE * 0.3, 0.22)
	ribbon_burst(pos, dir, color, int(4 + 3 * power), 6.0 + 4.0 * power, 50.0, 0.3, Vector3.ZERO)
	flash_light(pos, color, 0.7, 5.0, 0.2)


## 境界切换：贴地细环 + 胸口细星 + 上扬细丝
static func breakthrough(pos: Vector3, color: Color, power: float) -> void:
	var ring := _sprite(pos + Vector3(0, 0.08, 0), color, 1, 0.5, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * (4.0 + 5.0 * power), 0.6)
	var f := _sprite(pos + Vector3(0, 1.0, 0), color, 0, 1.0)
	_fade(f, Vector3.ONE * (2.0 + 1.5 * power), 0.35)
	ribbon_burst(pos + Vector3(0, 0.6, 0), Vector3.UP, color, int(8 + 10 * power), 7.0 + 3.0 * power, 75.0, 0.6, Vector3(0, -5.0, 0))
	flash_light(pos + Vector3(0, 1.2, 0), color, 1.0, 7.0, 0.35)


## 收起遁光、现出身形时的一圈细环
static func reappear(pos: Vector3, color: Color) -> void:
	var r := _sprite(pos, color, 1, 0.3)
	_fade(r, Vector3.ONE * 1.8, 0.22)


## ---------- 近战 ----------

## 刀砍在实处：沿挥刀方向的一道细锐刀光 + 小十字星 + 少量针形火星（不做白团）
static func blade_hit(pos: Vector3, swing_dir: Vector3, color: Color, power := 1.0) -> void:
	var d := swing_dir if swing_dir.length_squared() > 1e-6 else Vector3.RIGHT
	_slash(pos, d, Color.WHITE.lerp(color, 0.35), 1.5 * power, 0.12, 0.14)
	if not lite:
		_slash(pos - d * 0.1, d.rotated(Vector3.UP, 0.35), color, 0.9 * power, 0.06, 0.12)
	var f := _sprite(pos, Color.WHITE.lerp(color, 0.5), 0, 0.36 * power)
	_fade(f, Vector3.ONE * 0.8 * power, 0.12)
	line_sparks(pos, d, Color(1.0, 0.84, 0.6), int(5 + 4 * power), 8.0 + 3.0 * power, 50.0, 0.28)
	if not lite:
		line_sparks(pos, -d, Color(0.9, 0.25, 0.2), int(2 + 2 * power), 5.0, 70.0, 0.3)
	flash_light(pos, color, 0.5 + 0.3 * power, 3.0, 0.1)


## 刀刃相撞：极小的亮点 + 交叉短芒 + 一圈细环 + 向外迸出的金色针形火星
static func blade_clash(pos: Vector3, normal: Vector3, power := 1.0) -> void:
	var gold := Color(1.0, 0.76, 0.36)
	var n := normal if normal.length_squared() > 1e-6 else Vector3.BACK
	var f := _sprite(pos, Color(1.0, 0.92, 0.75), 0, 0.5 * power)
	_fade(f, Vector3.ONE * 1.0 * power, 0.16)
	var side := n.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	_slash(pos, side + Vector3.UP * 0.9, gold, 0.8 * power, 0.07, 0.13)
	_slash(pos, side - Vector3.UP * 0.9, gold, 0.8 * power, 0.07, 0.13)
	var r := _sprite(pos, gold, 1, 0.16)
	_fade(r, Vector3.ONE * 0.85 * power, 0.2)
	line_sparks(pos, n + Vector3.UP * 0.4, gold, int(9 + 6 * power), 10.0 * power, 70.0, 0.42)
	if not lite:
		line_sparks(pos, -n + Vector3.UP * 0.3, gold, int(3 + 3 * power), 6.0 * power, 60.0, 0.32)
	if power >= 0.9:
		# 弹反级别的对刃：再炸一朵金色像素格挡花（素材本色就是金）；跳过开头两帧实心星，从细十字芒 + 光环起
		pixel("parry", pos, {"px": 0.026 * power, "dir": n, "from": 2})
	flash_light(pos, gold, 1.0 * power, 4.0, 0.12)


## 重劈落地：贴地细环 + 几根向上弹起的细火星
static func ground_slam(pos: Vector3, color: Color) -> void:
	var ring := _sprite(pos + Vector3(0, 0.05, 0), color, 1, 0.3, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 2.6, 0.32)
	line_sparks(pos + Vector3(0, 0.08, 0), Vector3.UP, Color(0.95, 0.9, 0.82), 7, 5.0, 65.0, 0.32)


## 出招前的刃光（敌人读招用）：在刃尖一闪而过的细十字星
static func glint(pos: Vector3, color: Color, size := 0.75) -> void:
	var f := _sprite(pos, color, 0, 0.05)
	var tw := f.create_tween()
	tw.tween_property(f, "scale", Vector3.ONE * size, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector3.ONE * size * 0.7, 0.12)
	tw.parallel().tween_property(f.material_override, "shader_parameter/alpha", 0.0, 0.16).set_delay(0.04)
	tw.tween_callback(f.queue_free)


## 脚下一圈细环（踏步突进）
static func step_ring(pos: Vector3, color: Color) -> void:
	var ring := _sprite(pos + Vector3(0, 0.04, 0), color, 1, 0.2, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 1.3, 0.25)


## 处决：一道贯穿的长细芒 + 暗红针形火星 + 细环
static func deathblow(pos: Vector3, dir: Vector3) -> void:
	var red := Color(0.95, 0.18, 0.15)
	_slash(pos, dir, Color(1.0, 0.85, 0.8), 3.0, 0.14, 0.22)
	_slash(pos + Vector3.UP * 0.05, dir.rotated(Vector3.UP, 1.3) + Vector3.UP * 0.5, red, 1.6, 0.08, 0.2)
	var r := _sprite(pos, red, 1, 0.3)
	_fade(r, Vector3.ONE * 1.8, 0.35)
	line_sparks(pos, dir, red, 14, 12.0, 45.0, 0.45)
	line_sparks(pos, Vector3.UP, Color(1.0, 0.8, 0.6), 6, 7.0, 80.0, 0.35)
	flash_light(pos, red, 1.2, 5.0, 0.2)


## ---------- 打击感（分档命中、碎块、尘土、下砸、残影） ----------

## 从 pos 沿 dir 射出的一根短针：边飞边收细淡出（冲击线）
static func _ray(pos: Vector3, dir: Vector3, color: Color, length: float, width: float, travel: float, dur: float) -> void:
	var d := dir.normalized()
	var s := _streak(pos + d * length * 0.5, d, color, length, width)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "global_position", pos + d * (length * 0.5 + travel), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3(length * 0.45, width * 0.25, 1.0), dur).set_ease(Tween.EASE_IN)
	tw.tween_property(s.material_override, "shader_parameter/alpha", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)


## 屏幕平面内放射的一圈冲击线
static func _burst_lines(pos: Vector3, n: int, color: Color, length: float, width: float, travel: float, dur: float) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var rx := Vector3.RIGHT
	var uy := Vector3.UP
	if cam != null:
		rx = cam.global_basis.x
		uy = cam.global_basis.y
	var a0 := randf() * TAU
	if lite:
		n = maxi((n + 1) / 2, 2)
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var d := rx * cos(a) + uy * sin(a)
		var k := randf_range(0.7, 1.15)
		_ray(pos + d * 0.1, d, color, length * k, width, travel * k, dur)


## 命中冲击，分档：0 轻击 1 重击 2 弹反 3 处决 4 下砸
## 叠层：刀光斩痕 + 小星 + 针形火星（blade_hit）→ 像素迸溅（轻击小火花，重击/下砸/处决大爆击）
## → 一圈快速扩开的细冲击环 → 少量放射冲击线。线条都在 0.1~0.3s 内收掉，像素帧再多留一点余烬
static func impact(pos: Vector3, swing_dir: Vector3, color: Color, tier: int, scale := 1.0) -> void:
	if mute >= 1:
		return
	# scale：出手那位的境界档位（Realm.combat 的 fx），同一招境界越高冲击圈和刀光越大
	var k: float = [1.0, 1.35, 1.2, 1.6, 1.5][clampi(tier, 0, 4)] * scale
	var edge := Color.WHITE.lerp(color, 0.3)
	if lite and _hit_rank() >= 2:
		# 一刀砍中一群：第三个起只留一道刀光 + 像素迸溅
		var d0 := swing_dir if swing_dir.length_squared() > 1e-6 else Vector3.RIGHT
		_slash(pos, d0, Color.WHITE.lerp(color, 0.35), 1.5 * k, 0.12, 0.14)
		pixel("hit_spark" if tier == 0 else "crit_hit", pos, {"px": 0.024 if tier == 0 else 0.016 * k, "tint": color, "recolor": 0.6,
				"dir": swing_dir, "from": 0 if tier == 0 else 2})
		return
	blade_hit(pos, swing_dir, color, k)
	if tier == 0:
		pixel("hit_spark", pos, {"px": 0.024, "tint": color, "recolor": 0.6, "dir": swing_dir})
	else:
		# 跳过开头两帧的实心白星，直接从带十字芒和光环的第 2 帧起
		pixel("crit_hit", pos, {"px": 0.016 * k, "tint": color, "recolor": 0.55 if tier != 3 else 0.8,
			"dir": swing_dir, "from": 2})
	var r := _sprite(pos, edge, 1, 0.1 * k)
	_fade(r, Vector3.ONE * (0.7 + 0.28 * float(tier)) * k, 0.15 + 0.03 * float(tier))
	_burst_lines(pos, 3 + tier, edge, 0.32 * k, 0.05, 0.42 * k, 0.12 + 0.02 * float(tier))


## 受击碎块：命中点喷出一把小方块（颜色贴近被打中的角色），落地轻弹后消失
static func debris(pos: Vector3, dir: Vector3, colors: Array, amount := 8, speed := 5.0, size := 1.0) -> void:
	if colors.is_empty() or mute >= 2:
		return
	var d := DEBRIS.new()
	root.add_child(d)
	d.burst(pos, dir, colors, amount, speed, size)


## 方块尘土：贴地向四周滚开的灰色小方块
static func dust(pos: Vector3, amount := 12, speed := 4.0, size := 1.0) -> void:
	var d := DEBRIS.new()
	root.add_child(d)
	d.dust(pos, amount, speed, size)


## 上挑击飞：受击者身边几根向上射出的细线 + 脚下一圈小环
static func launch_lines(pos: Vector3, color: Color) -> void:
	var edge := Color.WHITE.lerp(color, 0.35)
	for i in 4:
		var off := Vector3(randf_range(-0.35, 0.35), randf_range(-0.3, 0.2), randf_range(-0.35, 0.35))
		_ray(pos + off, Vector3.UP, edge, randf_range(0.6, 1.0), 0.05, randf_range(0.9, 1.4), 0.22)
	var ring := _sprite(Vector3(pos.x, 0.05, pos.z), color, 1, 0.2, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 1.6, 0.25)


## 下砸落地：两圈贴地细环 + 贴地放射的冲击线 + 方块尘土 + 少量向上弹的火星
static func slam_impact(pos: Vector3, color: Color, power := 1.0) -> void:
	var g := Vector3(pos.x, 0.05, pos.z)
	var edge := Color.WHITE.lerp(color, 0.3)
	var ring := _sprite(g, edge, 1, 0.3, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 3.4 * power, 0.32)
	var ring2 := _sprite(g + Vector3(0, 0.02, 0), color, 1, 0.2, false)
	ring2.rotation.x = -PI * 0.5
	_fade(ring2, Vector3.ONE * 2.0 * power, 0.42, 0.04)
	var a0 := randf() * TAU
	for i in 9:
		var a := a0 + TAU * float(i) / 9.0
		var d := Vector3(cos(a), 0.0, sin(a))
		_ray(g + d * 0.35 + Vector3(0, 0.06, 0), d, edge, 0.6 * power, 0.06, 1.3 * power, 0.2)
	dust(g, int(16 * power), 4.5 * power, 1.1)
	line_sparks(g + Vector3(0, 0.1, 0), Vector3.UP, Color(1.0, 0.86, 0.62), 8, 7.0, 55.0, 0.32)
	flash_light(g + Vector3(0, 0.6, 0), color, 0.7, 4.0, 0.14)


## 剑身残影：在挥砍途中留下一道很淡的剑形，0.1s 内淡掉
## 遁光砸地：光剑竖直贯地那一下——一道竖直剑芒 + 三圈贴地细环由快到慢扩开 + 贴地放射冲击线
## + 屏幕平面放射线 + 向上迸的细丝 / 火星 + 一圈方块尘土。按 pos 的实际高度（平台上也贴着台面）
static func dun_slam(pos: Vector3, color: Color, power := 1.0) -> void:
	var g := pos + Vector3(0, 0.05, 0)
	var edge := Color.WHITE.lerp(color, 0.3)
	_slash(g + Vector3.UP * 1.8 * power, Vector3.UP, edge, 4.2 * power, 0.32 * power, 0.16)
	for i in 3:
		var ring := _sprite(g + Vector3(0, 0.02 * i, 0), edge if i == 0 else color, 1, 0.3, false)
		ring.rotation.x = -PI * 0.5
		_fade(ring, Vector3.ONE * (3.2 + 2.4 * i) * power, 0.24 + 0.1 * i, 0.03 * i)
	var a0 := randf() * TAU
	for i in 12:
		var a := a0 + TAU * float(i) / 12.0
		var d := Vector3(cos(a), 0.0, sin(a))
		_ray(g + d * 0.4 + Vector3(0, 0.06, 0), d, edge, 0.9 * power, 0.07, 2.2 * power, 0.22)
	_burst_lines(pos + Vector3.UP * 0.9, 8, edge, 0.7 * power, 0.06, 1.4 * power, 0.2)
	ribbon_burst(g + Vector3.UP * 0.2, Vector3.UP, color, int(10 + 8 * power), 10.0 * power, 70.0, 0.5, Vector3(0, -9.0, 0))
	line_sparks(g + Vector3(0, 0.1, 0), Vector3.UP, Color(1.0, 0.9, 0.7), 10, 8.0 * power, 60.0, 0.35)
	var dbr := DEBRIS.new()
	dbr.floor_y = pos.y
	root.add_child(dbr)
	dbr.dust(g, int(22 * power), 6.0 * power, 1.2)
	flash_light(g + Vector3(0, 0.8, 0), color, 1.6 * power, 8.0, 0.22)


static func blade_ghost(xf: Transform3D, mesh: Mesh, color: Color, alpha := 0.38, dur := 0.11) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_transform = xf
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 常驻的朝相机面片（破绽标记等），调用方负责摆位与释放
static func marker_sprite(color: Color, mode: int, size: float) -> MeshInstance3D:
	return _sprite(Vector3.ZERO, color, mode, size, true)


## 当场击碎：直接从像素内爆的"炸开"那一帧播起 + 细环 + 四散的细丝
static func death_burst(pos: Vector3, color: Color) -> void:
	pixel("implosion", pos, {"px": 0.024, "tint": color, "recolor": 0.85, "from": PIXEL.IMPLOSION_POP})
	var r := _sprite(pos, color, 1, 0.5)
	_fade(r, Vector3.ONE * 3.2, 0.4)
	ribbon_burst(pos, Vector3.UP, color, 12, 9.0, 180.0, 0.5)


## 死亡碎裂：src 下的体素网格按当前姿势拆成方块（voxels=false 时把 meshes 里的基本体按体积采样），
## 从 hit 向外扫一道裂纹光，崩开落地后逐块消融。edge 为消融亮边颜色；extra 为额外方块 [Transform3D, 边长, 颜色]
static func shatter(src: Node3D, hit: Vector3, dir: Vector3, edge: Color, power := 1.0,
		meshes: Array = [], cell := 0.11, extra: Array = []) -> void:
	var s := SHATTER.new()
	s.edge = edge
	s.floor_y = 0.0
	root.add_child(s)
	if meshes.is_empty():
		s.collect_voxels(src, 2 if SHATTER.active() < 4 else 3)
	else:
		var c := cell * (1.5 if SHATTER.active() >= 6 else 1.0)
		for e: Array in meshes:
			s.collect_volume(e[0] as MeshInstance3D, e[1] as Color, c)
	for e: Array in extra:
		s.add_cube(e[0] as Transform3D, float(e[1]), e[2] as Color)
	s.start(hit, dir, power)
	# 碎开那一下：命中点一圈细环 + 向外的冲击线 + 方块尘土
	var r := _sprite(hit, Color.WHITE.lerp(edge, 0.4), 1, 0.2)
	_fade(r, Vector3.ONE * 2.4 * power, 0.3)
	_burst_lines(hit, 6, Color.WHITE.lerp(edge, 0.3), 0.5, 0.06, 0.9, 0.18)
	flash_light(hit, edge, 1.2, 5.0, 0.25)


## 倒地后消散：完整播内爆（先向内收拢约 1.1s 再炸开），走战斗时间，调用方让"炸开"对上身体消失的那一刻
static func death_implode(pos: Vector3, color: Color) -> void:
	pixel("implosion", pos, {"px": 0.024, "tint": color, "recolor": 0.85, "combat_clock": true})


## 内爆从开始到炸开的秒数
static func implode_lead() -> float:
	return float(PIXEL.IMPLOSION_POP) / float(PIXEL.SHEETS["implosion"]["fps"])


## ---------- 身法 · 法术 ----------

## 角色残影：把 src 下所有可见的体素网格按当前姿势拍一份，染成 color 的半透明剪影，dur 内淡掉
static func body_ghost(src: Node3D, color: Color, alpha := 0.5, dur := 0.28) -> void:
	var g := _ghost_node(src, color, alpha, src.global_position)
	var tw := g.create_tween()
	tw.tween_property(g.get_meta("mat"), "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)


## 残影节点：原点在 pivot，挪动/缩放这个节点就能带着整个剪影走（材质存在 meta "mat"）；调用方负责释放
static func _ghost_node(src: Node3D, color: Color, alpha: float, pivot: Vector3) -> Node3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	var g := Node3D.new()
	g.set_meta("mat", m)
	root.add_child(g)
	g.global_position = pivot
	for n in src.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.has_meta("shenshi_ghost"):
			continue
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		if mi.skin != null and DisplayServer.get_name() != "headless":
			# 带骨骼的网格（主角的皮肤模型，hero_skin.gd）：照搬网格只会得到没摆姿势的原型，按当前骨骼姿势烘一份
			var baked := mi.bake_mesh_from_current_skeleton_pose()
			if baked != null and baked.get_surface_count() > 0:
				c.mesh = baked
		c.material_override = m
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(c)
		c.global_transform = mi.global_transform
	return g


## ---------- 境界突破（升阶） ----------

const FIVE_ELEM: Array[Color] = [
	Color(1.0, 0.86, 0.4), Color(0.25, 1.0, 0.45), Color(0.25, 0.55, 1.0),
	Color(1.0, 0.28, 0.15), Color(0.85, 0.62, 0.3),
]


## 升阶突破。body：主角的 visual（脚底为原点）；colors：该境界的丝线色（第 0 条为主色）；power：境界 fx 系数。
## 0 ~ 0.45s 聚气：三层贴身细环向身体收拢、四周细线向胸口汇聚；
## 0.45s 破境：胸口细星、贴地细环一圈圈扩开（境界越高圈越多）、向上射出的细线与细丝；
## 再叠各境界专属的一层——炼气 灵气上涌 · 筑基 御风卷起 · 结丹 金丹凝于丹田 · 元婴 见 yuanying_cine.gd（这里只留演示用的离体小影）·
## 化神 剑影环身向外飞射 · 炼虚 五行五色射线 · 合体 两道分身归位 · 大乘 以上合一并在头顶开一圈天环
static func realm_ascend(body: Node3D, idx: int, colors: Array, power: float) -> void:
	var pos := body.global_position
	var chest := pos + Vector3(0.0, 1.0, 0.0)
	var n := colors.size()
	for i in 3:
		var h: float = [0.15, 0.95, 1.75][i]
		var r := _sprite(pos + Vector3(0.0, h, 0.0), Color.WHITE.lerp(colors[i % n] as Color, 0.4), 1, 3.0 + 0.4 * i, false)
		r.rotation.x = -PI * 0.5
		_fade(r, Vector3.ONE * 0.35, 0.45, 0.03 * i)
	for i in 14:
		var a := TAU * float(i) / 14.0 + randf_range(-0.15, 0.15)
		var d := Vector3(cos(a), randf_range(-0.35, 0.6), sin(a)).normalized()
		var from := chest + d * randf_range(2.6, 3.4)
		_ray(from, -d, Color.WHITE.lerp(colors[i % n] as Color, 0.3), 0.7, 0.05, from.distance_to(chest) - 0.9, 0.42)
	glint(chest, Color.WHITE.lerp(colors[0] as Color, 0.5), 0.6)
	var bw: WeakRef = weakref(body)      # 2026-11-21 QA BUG-07：弱引用，body 先被释放时不报「Lambda capture was freed」
	root.get_tree().create_timer(0.45).timeout.connect(func() -> void:
		var b := bw.get_ref() as Node3D
		if b != null:
			_ascend_burst(b, idx, colors, power))


static func _ascend_burst(body: Node3D, idx: int, colors: Array, power: float) -> void:
	var pos := body.global_position
	var chest := pos + Vector3(0.0, 1.0, 0.0)
	var n := colors.size()
	var c0: Color = colors[0]
	var edge := Color.WHITE.lerp(c0, 0.3)
	glint(chest, edge, 1.8 + power)
	var f := _sprite(chest, edge, 0, 0.8)
	_fade(f, Vector3.ONE * (2.6 + 1.5 * power), 0.3)
	# 贴地细环：境界越高圈越多、扩得越远
	var rings := 2 + idx / 2
	for i in rings:
		var ring := _sprite(pos + Vector3(0.0, 0.05 + 0.01 * i, 0.0), colors[i % n], 1, 0.4, false)
		ring.rotation.x = -PI * 0.5
		_fade(ring, Vector3.ONE * (3.6 + 1.7 * i) * (1.0 + 0.5 * power), 0.55 + 0.06 * i, 0.07 * i)
	# 向上射出的细线
	for i in 8 + idx * 2:
		var a := randf() * TAU
		var off := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.25, 0.85) + Vector3.UP * randf_range(0.1, 1.3)
		_ray(pos + off, Vector3.UP, Color.WHITE.lerp(colors[i % n] as Color, 0.35), randf_range(0.8, 1.6), 0.05,
				randf_range(3.0, 4.5) + idx * 0.5, randf_range(0.38, 0.55))
	ribbon_burst(chest, Vector3.UP, c0, 10 + idx * 3, 8.0 + 3.0 * power, 70.0, 0.7, Vector3(0.0, -4.0, 0.0))
	flash_light(chest, c0, 1.5 + power, 8.0, 0.45)
	match idx:
		0:
			# 炼气：灵气自脚下上涌
			ribbon_burst(pos + Vector3(0.0, 0.2, 0.0), Vector3.UP, Color.WHITE.lerp(c0, 0.5), 10, 6.0, 25.0, 0.8, Vector3(0.0, 2.0, 0.0))
			dust(pos, 10, 3.0)
		1:
			# 筑基：一圈风卷开 + 方块尘土四散
			ribbon_burst(pos + Vector3(0.0, 0.5, 0.0), Vector3.UP, Color.WHITE.lerp(c0, 0.6), 18, 12.0, 88.0, 0.6, Vector3.ZERO)
			dust(pos, 18, 6.0)
		2:
			_core(pos + Vector3(0.0, 0.85, 0.0))
		3:
			_soul_rise(body, Color.WHITE.lerp(c0, 0.45))
		4:
			_sword_ring(chest, colors, 10)
		5:
			_five_rays(pos)
		6:
			_merge_ghosts(body, colors)
		_:
			_sword_ring(chest, colors, 14)
			_soul_rise(body, Color.WHITE.lerp(c0, 0.5))
			_five_rays(pos)
			# 头顶天环：高处一圈缓缓扩开的细环，细线从天环落向主角
			var sky := pos + Vector3(0.0, 7.0, 0.0)
			for i in 2:
				var r := _sprite(sky + Vector3.UP * 0.6 * i, colors[i % n], 1, 1.0, false)
				r.rotation.x = -PI * 0.5
				_fade(r, Vector3.ONE * (12.0 + 5.0 * i), 1.1, 0.1 * i)
			for i in 10:
				var a := TAU * float(i) / 10.0
				var top := sky + Vector3(cos(a), 0.0, sin(a)) * 2.5
				var d := (chest - top).normalized()
				_ray(top, d, Color.WHITE.lerp(colors[i % n] as Color, 0.4), 1.2, 0.05, top.distance_to(chest) - 1.4, 0.4)


## 结丹：丹田处细环一圈圈收拢成一点金光，稍后再亮一次
static func _core(p: Vector3) -> void:
	var gold := Color(1.0, 0.82, 0.4)
	for i in 3:
		var r := _sprite(p, gold, 1, 1.4 - 0.25 * i)
		_fade(r, Vector3.ONE * 0.12, 0.3, 0.09 * i)
	glint(p, gold, 1.3)
	root.get_tree().create_timer(0.45).timeout.connect(func() -> void:
		glint(p, Color(1.0, 0.95, 0.75), 1.0)
		var r := _sprite(p, gold, 1, 0.15)
		_fade(r, Vector3.ONE * 1.6, 0.35))


## 元婴：一个缩小的发光身形从胸口离体，向上升起后淡去
static func _soul_rise(body: Node3D, color: Color) -> void:
	var chest := body.global_position + Vector3(0.0, 1.0, 0.0)
	var g := _ghost_node(body, color, 0.75, chest)
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 0.42, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "global_position", chest + Vector3.UP * 2.6, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(g.get_meta("mat"), "albedo_color:a", 0.0, 0.5).set_delay(0.55)
	tw.chain().tween_callback(g.queue_free)
	glint(chest + Vector3.UP * 2.6, Color.WHITE.lerp(color, 0.3), 1.0)


## 化神：一圈剑影环身摆开，剑尖朝外向四周飞射
static func _sword_ring(c: Vector3, colors: Array, count: int) -> void:
	for i in count:
		var a := TAU * float(i) / float(count)
		var d := Vector3(cos(a), 0.12, sin(a)).normalized()
		var s := _sprite(c, colors[i % colors.size()], 3, 1.0, false)
		place_streak(s, c + d * 0.7, d, 0.9, 0.24)
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "global_position", c + d * 6.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(s.material_override, "shader_parameter/alpha", 0.0, 0.25).set_delay(0.32)
		tw.chain().tween_callback(s.queue_free)


## 炼虚：五行五色——五个方位各射出一组彩线，贴地五圈彩环
static func _five_rays(pos: Vector3) -> void:
	var a0 := randf() * TAU
	for i in 5:
		var col := FIVE_ELEM[i]
		var a := a0 + TAU * float(i) / 5.0
		for j in 3:
			var d := Vector3(cos(a + (j - 1) * 0.12), 0.25 + 0.15 * j, sin(a + (j - 1) * 0.12)).normalized()
			_ray(pos + Vector3(0.0, 1.0, 0.0) + d * 0.4, d, col, 1.1, 0.06, 4.0, 0.45)
		var r := _sprite(pos + Vector3(0.0, 0.07 + 0.01 * i, 0.0), col, 1, 0.3, false)
		r.rotation.x = -PI * 0.5
		_fade(r, Vector3.ONE * (2.4 + 0.9 * i), 0.5, 0.05 * i)


## 合体：左右两道分身从两侧滑回本体，合一的一刻一闪
static func _merge_ghosts(body: Node3D, colors: Array) -> void:
	var pos := body.global_position
	var side := body.global_basis.x
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var g := _ghost_node(body, Color.WHITE.lerp(colors[(i + 1) % colors.size()] as Color, 0.3), 0.6, pos)
		g.global_position = pos + side * s * 1.8
		var tw := g.create_tween()
		tw.tween_property(g, "global_position", pos, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(g.get_meta("mat"), "albedo_color:a", 0.0, 0.12)
		tw.tween_callback(g.queue_free)
	root.get_tree().create_timer(0.32).timeout.connect(func() -> void:
		glint(pos + Vector3(0.0, 1.0, 0.0), Color.WHITE, 1.6)
		var r := _sprite(pos + Vector3(0.0, 1.0, 0.0), colors[0], 1, 0.3)
		_fade(r, Vector3.ONE * 3.0, 0.3))


## 完美闪避：身边一圈先收后放的细环 + 细星，敌人刃口处再一闪（"躲开的就是这一刀"）
static func perfect_dodge(pos: Vector3, enemy_pos: Vector3, color: Color) -> void:
	var c := Color.WHITE.lerp(color, 0.3)
	var r := _sprite(pos, c, 1, 2.6)
	_fade(r, Vector3.ONE * 0.4, 0.35)
	var r2 := _sprite(pos, color, 1, 0.3)
	_fade(r2, Vector3.ONE * 3.4, 0.55, 0.08)
	glint(pos, c, 1.6)
	glint(enemy_pos, Color(1.0, 0.85, 0.6), 1.1)
	_burst_lines(pos, 8, c, 0.55, 0.05, 1.1, 0.3)
	flash_light(pos, color, 1.2, 6.0, 0.4)


## 瞬移斩的轨迹：起点到落点一道细长光芒 + 沿线零星细丝 + 落点一圈收拢的细环
static func warp_line(from: Vector3, to: Vector3, color: Color) -> void:
	var d := to - from
	var l := d.length()
	if l < 0.05:
		return
	var c := Color.WHITE.lerp(color, 0.35)
	_slash(from + d * 0.5, d, c, l * 1.05, 0.22, 0.2)
	_slash(from + d * 0.5 + Vector3.UP * 0.12, d, color, l * 0.9, 0.08, 0.26)
	ribbon_burst(to, -d / l, color, 6, 7.0, 35.0, 0.3, Vector3.ZERO)
	var ring := _sprite(to, c, 1, 1.6)
	_fade(ring, Vector3.ONE * 0.25, 0.18)
	flash_light(to, color, 0.9, 5.0, 0.18)


## 低境界闪现起点：脚下一圈细环 + 向后甩出的几根细丝（人形不化光，沿途留残影）
static func blink_start(pos: Vector3, dir: Vector3, color: Color) -> void:
	var ring := _sprite(pos + Vector3(0, 0.05, 0), color, 1, 0.25, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 1.6, 0.25)
	ribbon_burst(pos + Vector3(0, 0.9, 0), -dir, color, 5, 7.0, 35.0, 0.3, Vector3.ZERO)


## 施法手势：掌心 / 剑指处一点细十字星 + 一圈收拢的细环
static func cast_flash(pos: Vector3, color: Color, power := 1.0) -> void:
	glint(pos, Color.WHITE.lerp(color, 0.4), 0.8 * power)
	var r := _sprite(pos, color, 1, 0.9 * power)
	_fade(r, Vector3.ONE * 0.15, 0.16)


## 三段蓄势：身前两圈先后收拢的细环
static func cast_charge(pos: Vector3, color: Color, dur: float) -> void:
	var r := _sprite(pos, color, 1, 1.8)
	_fade(r, Vector3.ONE * 0.2, dur)
	var r2 := _sprite(pos, Color.WHITE.lerp(color, 0.4), 1, 1.2)
	_fade(r2, Vector3.ONE * 0.1, dur * 0.8, dur * 0.15)


## 火球爆炸：像素火爆（锚点在爆心正下方，往下挪一点让火团中心对准命中点）+ 细冲击环 + 火星 + 暖色点光。
## big：三段终结——火爆放大，叠一圈染成火色的像素冲击波，外加放射冲击线
## FIRE_K：火爆的画面尺寸整体打个折（2026-11-20：原来偏大，盖住了人和招式）。只管看到的大小，伤害范围在弹体那边另算，不受影响
const FIRE_K := 0.74
static func fire_explode(pos: Vector3, dir: Vector3, big := false) -> void:
	var px := (0.03 if big else 0.02) * FIRE_K
	var fire := Color(1.0, 0.5, 0.15)
	pixel("fire_burst", pos - Vector3.UP * px * 55.0, {"px": px, "lum_cut": 0.5})
	var r := _sprite(pos, Color(1.0, 0.75, 0.4), 1, 0.3 * FIRE_K)
	_fade(r, Vector3.ONE * (4.2 if big else 2.4) * FIRE_K, 0.25)
	line_sparks(pos, -dir, Color(1.0, 0.7, 0.3), 10 if big else 6, 9.0 * FIRE_K, 80.0, 0.4)
	flash_light(pos, fire, 2.0 if big else 1.2, (9.0 if big else 6.0) * FIRE_K, 0.3 if big else 0.2)
	if big:
		pixel("plasma", pos, {"px": 0.034 * FIRE_K, "tint": fire, "recolor": 0.9, "to": 24})
		_burst_lines(pos, 10, Color(1.0, 0.8, 0.5), 0.6 * FIRE_K, 0.07, 1.2 * FIRE_K, 0.2)


## ---------- 高阶法相：结丹 ~ 大乘各档的弹道 / 命中特效 ----------

## 一根沿 a→b 的针形细芒，hold 秒后 fade 秒淡掉（电弧、五芒星、新月斩的笔画）
static func _stroke(a: Vector3, b: Vector3, color: Color, width: float, hold: float, fade: float, flicker := false) -> void:
	var seg := b - a
	var l := seg.length()
	if l < 1e-3:
		return
	var s := _streak((a + b) * 0.5, seg, color, l * 1.2, width)
	var m := s.material_override
	var tw := s.create_tween()
	if flicker:
		tw.tween_property(m, "shader_parameter/alpha", 0.2, hold * 0.4)
		tw.tween_property(m, "shader_parameter/alpha", 1.0, hold * 0.2)
		tw.tween_interval(hold * 0.4)
	else:
		tw.tween_interval(hold)
	tw.tween_property(m, "shader_parameter/alpha", 0.0, fade).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)


## 锯齿电弧：from → to 折成 segs 段，中段抖得最厉害；外层主色、内层白芯，明灭一下再淡掉
static func lightning(from: Vector3, to: Vector3, color: Color, width := 0.14, dur := 0.22, segs := 6) -> void:
	var d := to - from
	var l := d.length()
	if l < 0.05:
		return
	var cam := root.get_viewport().get_camera_3d()
	var view := Vector3.BACK
	if cam != null:
		view = cam.global_position - from
	var side := d.cross(view)
	if side.length_squared() < 1e-6:
		side = d.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d / l)
	var pts: Array[Vector3] = [from]
	for i in range(1, segs):
		var t := float(i) / float(segs)
		var jit := l * 0.14 * sin(t * PI)
		pts.append(from + d * t + side * randf_range(-1.0, 1.0) * jit + up * randf_range(-0.4, 0.4) * jit)
	pts.append(to)
	var core := Color.WHITE.lerp(color, 0.2)
	for i in pts.size() - 1:
		_stroke(pts[i], pts[i + 1], color, width, dur * 0.45, dur * 0.55, true)
		_stroke(pts[i], pts[i + 1], core, width * 0.38, dur * 0.45, dur * 0.4, true)


## 天雷劈落（元婴）：高空两道电弧劈到 pos，落点细环 + 放射冲击线 + 电火花
static func thunder(pos: Vector3, color: Color, power := 1.0) -> void:
	var top := pos + Vector3(randf_range(-1.5, 1.5), 9.0 + 3.0 * power, randf_range(-1.5, 1.5))
	lightning(top, pos, color, 0.22 * power, 0.32, 9)
	lightning(top + Vector3(randf_range(-2.0, 2.0), 1.0, randf_range(-2.0, 2.0)), pos, Color.WHITE.lerp(color, 0.5), 0.09 * power, 0.26, 7)
	var edge := Color.WHITE.lerp(color, 0.3)
	var r := _sprite(pos, edge, 1, 0.2)
	_fade(r, Vector3.ONE * 2.8 * power, 0.26)
	var g := _sprite(pos + Vector3(0, -0.9, 0), color, 1, 0.3, false)
	g.rotation.x = -PI * 0.5
	_fade(g, Vector3.ONE * 3.6 * power, 0.35)
	_burst_lines(pos, 7, edge, 0.6 * power, 0.06, 1.3 * power, 0.18)
	line_sparks(pos, Vector3.UP, Color.WHITE.lerp(color, 0.5), 9, 11.0, 85.0, 0.3)
	flash_light(pos + Vector3.UP, color, 2.2 * power, 9.0, 0.22)


## 空间裂隙（合体）：面朝 facing 张开的一道竖直细缝 + 外围一圈压扁的细环，先张后合，dur 内收掉
static func rift(pos: Vector3, facing: Vector3, color: Color, size := 1.0, dur := 0.35) -> void:
	var f := facing.normalized() if facing.length_squared() > 1e-6 else Vector3.FORWARD
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var slit := _streak(pos, up, Color.WHITE.lerp(color, 0.35), 1.5 * size, 0.02)
	var tw := slit.create_tween()
	tw.tween_property(slit, "scale", Vector3(1.7 * size, 0.42 * size, 1.0), dur * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(slit, "scale", Vector3(2.0 * size, 0.02, 1.0), dur * 0.7).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(slit.material_override, "shader_parameter/alpha", 0.0, dur * 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(slit.queue_free)
	var ring := _sprite(pos, color, 1, 1.0, false)
	ring.global_transform = Transform3D(Basis.looking_at(f, up) * Basis.from_scale(Vector3(0.05, 0.2, 1.0) * size), pos)
	var tr := ring.create_tween()
	tr.tween_property(ring, "scale", Vector3(0.55, 1.5, 1.0) * size, dur * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tr.tween_property(ring, "scale", Vector3(0.04, 1.7, 1.0) * size, dur * 0.7).set_ease(Tween.EASE_IN)
	tr.parallel().tween_property(ring.material_override, "shader_parameter/alpha", 0.0, dur * 0.7).set_ease(Tween.EASE_IN)
	tr.tween_callback(ring.queue_free)


## 空间裂缝（2026-11-21，元婴以上拳劲对撞）：pos 处朝着镜头的平面上，几道锯齿裂缝从撞击点往外裂开 ——
## 幽暗的虚空缝（混合叠加，真的是一道黑缝）里透出一线境界色的微光，停一会儿再合上。
## size = 裂缝长度（米），branches = 几道主裂缝；fork 每道末段再分一个小叉的概率（境界高的裂得碎）。
## 每段两笔（虚空 + 微光），节点数 = branches × 3 × 2（+ 分叉），手机档调用方自己少给几道
static func space_crack(pos: Vector3, color: Color, size: float, branches: int, dur := 0.45, fork := 0.0) -> void:
	if mute >= 1 or root == null or not root.is_inside_tree():
		return
	crack_n += 1
	var cam := root.get_viewport().get_camera_3d()
	var rx := cam.global_basis.x if cam != null else Vector3.RIGHT
	var uy := cam.global_basis.y if cam != null else Vector3.UP
	var c := pos
	if cam != null:
		c += (cam.global_position - pos).normalized() * 0.35     # 往镜头挪一点：别被撞在一起的两个身子挡住
	var void_c := Color(0.025, 0.015, 0.06)
	var glow := Color.WHITE.lerp(color, 0.5)
	var a0 := randf() * TAU
	for i in branches:
		var a := a0 + TAU * float(i) / float(maxi(branches, 1)) + randf_range(-0.4, 0.4)
		var dir := rx * cos(a) + uy * sin(a)
		var perp := rx * -sin(a) + uy * cos(a)
		var p := c
		var total := size * randf_range(0.6, 1.15)
		for k in 3:
			var q := p + (dir + perp * randf_range(-0.55, 0.55)).normalized() * total / 3.0 * randf_range(0.8, 1.2)
			var w := lerpf(0.2, 0.06, float(k) / 2.0) * clampf(size, 0.7, 2.2)
			_stroke(p, q, void_c, w, dur * 0.6, dur * 0.4)
			_stroke(p, q, void_c, w * 0.6, dur * 0.6, dur * 0.4)        # 叠一层：缝心更黑
			_stroke(p, q, glow, w * 0.22, dur * 0.5, dur * 0.4, true)
			if k == 2 and randf() < fork:
				var fq := q + (dir + perp * randf_range(-1.2, 1.2)).normalized() * total * 0.3
				_stroke(q, fq, void_c, w * 0.7, dur * 0.5, dur * 0.4)
				_stroke(q, fq, glow, w * 0.22, dur * 0.4, dur * 0.4, true)
			p = q
	glint(c, glow, 0.5 + 0.25 * size)
	# 撞击点一圈幽暗的环往外一荡：空间在这儿被打穿了一下
	var hole := _sprite(c, void_c, 1, 0.3 * size, true)
	_fade(hole, Vector3.ONE * 1.1 * size, dur * 0.7)


## 裂隙坍缩（合体·空间裂隙命中）：内爆像素从收拢段播起 + 一圈向内收的细环 + 向内汇聚的冲击线
static func rift_collapse(pos: Vector3, color: Color, radius: float) -> void:
	pixel("implosion", pos, {"px": 0.03, "tint": color, "recolor": 0.9, "from": 16})
	for i in 2:
		var r := _sprite(pos, Color.WHITE.lerp(color, 0.3 * i), 1, radius * (2.2 - 0.6 * i))
		_fade(r, Vector3.ONE * 0.2, 0.5, 0.08 * i)
	var cam := root.get_viewport().get_camera_3d()
	var rx := cam.global_basis.x if cam != null else Vector3.RIGHT
	var uy := cam.global_basis.y if cam != null else Vector3.UP
	for i in 10:
		var a := TAU * float(i) / 10.0 + randf_range(-0.2, 0.2)
		var d := rx * cos(a) + uy * sin(a)
		_ray(pos + d * radius, -d, color, 0.9, 0.06, radius - 0.4, 0.4)
	flash_light(pos, color, 1.4, 7.0, 0.5)


## 五芒星（炼虚）：以 c 为心、法线 n 的平面上连出五角星，五根笔画各取五行一色，外加一圈细环
static func pentagram(c: Vector3, n: Vector3, radius: float, dur := 0.55) -> void:
	var nn := n.normalized() if n.length_squared() > 1e-6 else Vector3.UP
	var ref := Vector3.FORWARD if absf(nn.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var u := nn.cross(ref).normalized()
	var v := nn.cross(u)
	var a0 := randf() * TAU
	var pts: Array[Vector3] = []
	for i in 5:
		var a := a0 + TAU * float(i) / 5.0
		pts.append(c + (u * cos(a) + v * sin(a)) * radius)
	for i in 5:
		_stroke(pts[i], pts[(i + 2) % 5], FIVE_ELEM[i], 0.07 + 0.025 * radius, dur * 0.5, dur * 0.5)
		glint(pts[i], FIVE_ELEM[i], 0.35 + 0.15 * radius)
	var ring := _sprite(c, Color.WHITE.lerp(FIVE_ELEM[0], 0.4), 1, 1.0, false)
	ring.global_transform = Transform3D(Basis.looking_at(nn, ref) * Basis.from_scale(Vector3.ONE * radius * 2.15), c)
	_fade(ring, Vector3.ONE * radius * 2.4, dur)


## 三昧火莲（化神）：爆心一朵大火爆，八瓣火线贴着平面向外绽开，瓣尖错开一点再各炸一小团火
static func fire_lotus(pos: Vector3, power := 1.0) -> void:
	fire_explode(pos, Vector3.DOWN, true)
	var a0 := randf() * TAU
	for i in 8:
		var a := a0 + TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0.15, sin(a)).normalized()
		_ray(pos + d * 0.3, d, Color(1.0, 0.62, 0.22), 1.5 * power, 0.13, 3.4 * power, 0.38)
		if i % 2 == 0:
			# 瓣尖的小火团也小一号；位置不动（那一圈对应的是伤害范围）
			pixel("fire_burst", pos + d * 3.6 * power - Vector3.UP * 0.015 * 55.0,
					{"px": 0.015, "lum_cut": 0.5, "delay": 0.1 + 0.03 * i})
	var ring := _sprite(pos, Color(1.0, 0.7, 0.3), 1, 0.4, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 8.0 * power, 0.45)


## 法相光环面片（halo.gdshader：主环 + 刻度环 + 三段弧 + 符文环 + 放射细辐，多层反向旋转）。
## 主环半径 = 节点缩放（米），open 从 0 起；调用方负责摆位（orient_disc）、推进 spin / open / alpha、释放
static func halo_disc(color: Color, radius: float, rainbow := 0.0) -> MeshInstance3D:
	if _halo_quad == null:
		_halo_quad = QuadMesh.new()
		_halo_quad.size = Vector2.ONE * (2.0 / 0.93)  # 主环（shader 里 r = 0.93）落在半径 1 上
	var mi := MeshInstance3D.new()
	mi.mesh = _halo_quad
	var m := ShaderMaterial.new()
	m.shader = HALO_SHADER
	m.set_shader_parameter("color_a", Color.WHITE.lerp(color, 0.25))
	m.set_shader_parameter("color_b", color)
	m.set_shader_parameter("rainbow", rainbow)
	m.set_shader_parameter("open", 0.0)
	m.set_shader_parameter("spin", randf() * 10.0)
	# 一定要显式写入：没写过的 shader_parameter 读出来是 null，tween 它会失败，
	# _halo_once 随之中断、queue_free 挂不上——光环就永远留在天上
	m.set_shader_parameter("alpha", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.scale = Vector3.ONE * radius
	return mi


## 把光环摆到 pos、盘面法线对准 facing、主环半径 radius
static func orient_disc(mi: Node3D, pos: Vector3, facing: Vector3, radius: float) -> void:
	var f := facing.normalized() if facing.length_squared() > 1e-6 else Vector3.FORWARD
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(-f, up) * Basis.from_scale(Vector3.ONE * radius), pos)


## 一次性光环：由内向外展开、略微放大、各层转一点，随后淡出
static func _halo_once(pos: Vector3, facing: Vector3, color: Color, radius: float, dur: float, rainbow: float) -> void:
	var mi := halo_disc(color, radius, rainbow)
	orient_disc(mi, pos, facing, radius * 0.82)
	var m := mi.material_override as ShaderMaterial
	var s0: float = m.get_shader_parameter("spin")
	# 兜底：无论 tween 是否走完（被打断 / 出错），dur 之后都把光环清掉
	# 用弱引用：tween 正常走完时 mi 已被释放，直接捕获节点会在计时器触发时报"Lambda capture was freed"
	var ref: WeakRef = weakref(mi)
	mi.get_tree().create_timer(dur + 0.25, false).timeout.connect(func() -> void:
		var n := ref.get_ref() as Node
		if n != null:
			n.queue_free())
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "shader_parameter/open", 1.0, dur * 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 1.04, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/spin", s0 + 1.2, dur)
	tw.tween_property(m, "shader_parameter/alpha", 0.0, dur * 0.5).set_delay(dur * 0.5).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## 天环（大乘 / 炼虚天降 / 金乌）：高处一面水平法相光环由内向外展开，外沿再扩开一圈细环（radius 为主环半径）
static func sky_ring(pos: Vector3, color: Color, radius: float, dur := 0.8, rainbow := 0.0) -> void:
	_halo_once(pos, Vector3.UP, color, radius, dur, rainbow)
	var r := _sprite(pos + Vector3.UP * 0.05, Color.WHITE.lerp(color, 0.3), 1, radius * 2.0, false)
	r.rotation.x = -PI * 0.5
	_fade(r, Vector3.ONE * radius * 2.9, dur * 0.6)
	glint(pos, Color.WHITE.lerp(color, 0.4), 1.2)


## 身后法相光环（化神剑轮 / 大乘万剑归宗）：面朝 facing 的竖直光环，一次性展开后淡出。
## 长按连发用的是常驻版（AirCaster 里用 halo_disc 每帧摆位）
static func halo(pos: Vector3, facing: Vector3, color: Color, radius: float, dur := 0.3, rainbow := 0.0) -> void:
	_halo_once(pos, facing, color, radius, maxf(dur, 0.35), rainbow)


## 新月斩（合体·乾坤挪移斩）：以 pos 为心、垂直于 dir 的平面上一道巨大的弧形斩痕，由十几根针形笔画连成
static func crescent(pos: Vector3, dir: Vector3, color: Color, radius := 4.0) -> void:
	var f := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var side := f.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var up := side.cross(f)
	var tilt := randf_range(-0.6, 0.6)
	var ax := side * cos(tilt) + up * sin(tilt)
	var ay := up * cos(tilt) - side * sin(tilt)
	var n := 14
	var prev := Vector3.ZERO
	var edge := Color.WHITE.lerp(color, 0.25)
	for i in n + 1:
		var t := float(i) / float(n)
		var a := lerpf(-1.25, 1.25, t)
		var p := pos + (ax * sin(a) + ay * cos(a)) * radius - f * cos(a) * 0.8
		if i > 0:
			var w := 0.06 + 0.32 * sin(t * PI)
			_stroke(prev, p, color, w, 0.08 + 0.012 * i, 0.22)
			_stroke(prev, p, edge, w * 0.35, 0.08 + 0.012 * i, 0.18)
		prev = p
	_burst_lines(pos, 8, edge, 0.8, 0.06, 1.6, 0.22)
	flash_light(pos, color, 2.0, 9.0, 0.3)


## 天剑落地（大乘）：三圈细环一圈圈扩开 + 一道竖直光芒 + 放射冲击线 + 上扬细丝 + 方块尘土
static func heaven_strike(pos: Vector3, colors: Array, power := 1.0) -> void:
	var n := colors.size()
	var c0: Color = colors[0]
	var edge := Color.WHITE.lerp(c0, 0.3)
	for i in 3:
		var ring := _sprite(pos + Vector3(0, 0.05 + 0.02 * i, 0), colors[i % n], 1, 0.3, false)
		ring.rotation.x = -PI * 0.5
		_fade(ring, Vector3.ONE * (3.0 + 2.4 * i) * power, 0.35 + 0.08 * i, 0.05 * i)
	_slash(pos + Vector3.UP * 3.0 * power, Vector3.UP, edge, 7.0 * power, 0.45 * power, 0.28)
	_burst_lines(pos, 10, edge, 0.8 * power, 0.07, 1.8 * power, 0.24)
	ribbon_burst(pos, Vector3.UP, c0, int(8 + 8 * power), 12.0, 70.0, 0.55, Vector3(0, -6.0, 0))
	dust(Vector3(pos.x, maxf(pos.y - 1.1, 0.05), pos.z), int(10 * power), 5.0 * power, 1.1)
	flash_light(pos + Vector3.UP, c0, 2.4 * power, 10.0, 0.35)


## 高阶法相的飞剑命中：底层是通用命中（lite 时只留一道斩痕 + 小星，给高频连发用），再按档位叠一层：
## 1 结丹 金丹贯穿芒  2 元婴 电弧迸散  3 化神 火环  4 炼虚 五色环 + 小五芒星  5 合体 裂隙  6 大乘 天剑冲击
static func art_hit(pos: Vector3, dir: Vector3, color: Color, art: int, lite := false) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	if lite:
		_slash(pos, d, color, 1.8, 0.18, 0.12)
		glint(pos, Color.WHITE.lerp(color, 0.4), 0.5)
	else:
		hit(pos, d, color, 1.0)
	match art:
		1:
			glint(pos, Color(1.0, 0.86, 0.45), 0.5 if lite else 1.0)
			if not lite:
				_slash(pos + d * 1.6, d, Color.WHITE.lerp(color, 0.4), 3.8, 0.1, 0.2)
		2:
			for k in (1 if lite else 3):
				var j := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0), randf_range(-1.0, 1.0)).normalized()
				lightning(pos, pos + j * randf_range(1.2, 2.2), color, 0.06, 0.16, 3)
		3:
			var r := _sprite(pos, Color(1.0, 0.62, 0.22), 1, 0.2)
			_fade(r, Vector3.ONE * (1.3 if lite else 2.4), 0.24)
			if not lite:
				pixel("fire_burst", pos - Vector3.UP * 0.012 * 55.0, {"px": 0.012, "lum_cut": 0.5})
				line_sparks(pos, -d, Color(1.0, 0.7, 0.3), 6, 8.0, 80.0, 0.35)
		4:
			var r := _sprite(pos, color, 1, 0.2)
			_fade(r, Vector3.ONE * (1.2 if lite else 2.2), 0.26)
			if not lite:
				pentagram(pos, -d, 1.0, 0.4)
		5:
			rift(pos, d, color, 0.55 if lite else 1.0, 0.22 if lite else 0.32)
		6:
			if lite:
				var r := _sprite(pos, Color.WHITE.lerp(color, 0.3), 1, 0.2)
				_fade(r, Vector3.ONE * 1.6, 0.22)
			else:
				heaven_strike(pos, [color], 0.6)


## ---------- 空战斗法（air_melee.gd / air_foe.gd） ----------

## 拳劲冲击波：垂直于出拳方向的两三圈细环一前一后炸开 + 屏幕平面的放射线
static func shockwave(pos: Vector3, dir: Vector3, color: Color, power := 1.0) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var edge := Color.WHITE.lerp(color, 0.3)
	var n := 2 if power < 1.4 else 3
	if lite:
		n -= 1
	for i in n:
		var at := pos + d * (0.5 * float(i))
		var ring := _sprite(at, edge if i == 0 else color, 1, 0.3, false)
		ring.global_transform = Transform3D(Basis.looking_at(d, up) * Basis.from_scale(Vector3.ONE * 0.3), at)
		_fade(ring, Vector3.ONE * (2.2 + 1.3 * float(i)) * power, 0.2 + 0.07 * float(i), 0.03 * float(i))
	_burst_lines(pos, 5 + int(3.0 * power), edge, 0.5 * power, 0.055, 1.0 * power, 0.16)
	flash_light(pos, color, 0.9 * power, 6.0, 0.14)


## 被弹开的气弹 / 飞剑：从 pos 沿 dir 崩飞出去的一道短光 + 接触点一粒星
static func ricochet(pos: Vector3, dir: Vector3, color: Color, length := 3.2) -> void:
	if mute >= 1:
		return
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP
	_slash(pos + d * length * 0.55, d, Color.WHITE.lerp(color, 0.5), length, 0.1, 0.16)
	glint(pos, Color.WHITE.lerp(color, 0.3), 0.7)


## 空间波动的一圈：pos 处一道朝着镜头的波前由里往外荡开（拳劲对撞、换位落点这种地方用）。
## 和觉醒时身周的波动是同一个着色器（aura_warp.gdshader）：桌面档真的把那一块画面折一下，手机档不读屏幕、画一圈明暗波纹
static func space_ring(pos: Vector3, radius: float, color: Color, dur := 0.5, strength := 0.05) -> void:
	if mute >= 1 or root == null or not root.is_inside_tree():
		return
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		return
	if _quad == null:
		_quad = QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = AURA_WARP
	m.render_priority = -90          # 抢在别的半透明特效之前画，不盖住它们
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("power", 1.0)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("gap", 0.0)
	m.set_shader_parameter("calm", 0.3)
	m.set_shader_parameter("pulse", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_transform = Transform3D(cam.global_basis.orthonormalized().scaled(Vector3.ONE * radius * 2.0), pos)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "shader_parameter/pulse", 1.0, dur)
	tw.tween_property(m, "shader_parameter/power", 0.0, dur * 0.4).set_delay(dur * 0.6)
	tw.chain().tween_callback(mi.queue_free)


## 瞬身：原地一圈收拢的细环 + 几根向内收的短线（人已经不在这儿了）
static func vanish(pos: Vector3, color: Color) -> void:
	var c := Color.WHITE.lerp(color, 0.4)
	var r := _sprite(pos, c, 1, 1.9)
	_fade(r, Vector3.ONE * 0.15, 0.16)
	glint(pos, c, 0.9)
	_burst_lines(pos, 5, c, 0.4, 0.045, 0.5, 0.14)


## 这里炸了一下：能破坏地形的关卡里在地上留一个真的坑（够不着地、境界不够、太远时不留）。返回留没留。
static func quake(pos: Vector3, radius: float) -> bool:
	return terrain_hook.is_valid() and bool(terrain_hook.call(pos, radius))


## 砸地成坑：一圈翻起的碎石方块 + 贴地的灰环；叠在 dun_slam 上用
static func crater(pos: Vector3, power := 1.0) -> void:
	var rock: Array = [Color(0.42, 0.43, 0.47), Color(0.32, 0.33, 0.37), Color(0.55, 0.55, 0.58), Color(0.25, 0.26, 0.3)]
	debris(pos + Vector3(0.0, 0.3, 0.0), Vector3.UP, rock, int(26.0 * power), 9.0 * power, 1.9)
	var a0 := randf() * TAU
	for i in 6:
		var a := a0 + TAU * float(i) / 6.0
		var o := Vector3(cos(a), 0.0, sin(a)) * 1.6 * power
		debris(pos + o + Vector3(0.0, 0.2, 0.0), o.normalized() + Vector3.UP * 1.6, rock, 4, 6.0 * power, 1.5)
	var ring := _sprite(pos + Vector3(0.0, 0.07, 0.0), Color(1.0, 0.97, 0.9), 1, 0.5, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 6.5 * power, 0.55)
	line_sparks(pos + Vector3(0.0, 0.2, 0.0), Vector3.UP, Color(0.9, 0.88, 0.8), 16, 13.0 * power, 50.0, 0.5)
	# 地形真的被砸出坑时，不再贴假的裂纹和半埋的石块（会悬在坑上面）
	if not quake(pos, 2.6 + 1.8 * power):
		ground_break(pos, power)


## 已经有坑的地方再砸一下（坠星踏 / 剑雨落进对手刚砸出来的坑里）：碎石再溅一轮、一圈灰环；能破坏地形的关卡里坑再深一点。
## 不像 crater 那样重铺一圈地裂和翻起的石块 —— 一秒前那一圈还在，再铺一遍只是多二十来个节点
static func crater_hit(pos: Vector3, power := 1.0) -> void:
	var rock: Array = [Color(0.42, 0.43, 0.47), Color(0.32, 0.33, 0.37), Color(0.55, 0.55, 0.58), Color(0.25, 0.26, 0.3)]
	var d := DEBRIS.new()
	d.floor_y = pos.y
	root.add_child(d)
	d.burst(pos + Vector3(0.0, 0.3, 0.0), Vector3.UP, rock, int((10.0 if lite else 20.0) * power), 9.0 * power, 1.9)
	var ring := _sprite(pos + Vector3(0.0, 0.07, 0.0), Color(1.0, 0.97, 0.9), 1, 0.5, false)
	ring.rotation.x = -PI * 0.5
	_fade(ring, Vector3.ONE * 6.0 * power, 0.5)
	dust(pos, int((8.0 if lite else 14.0) * power), 6.0 * power, 1.5)
	quake(pos, 2.2 + 1.4 * power)


## 撞墙：墙面上一圈贴着法线的细环 + 顺法线崩出的碎石
static func wall_crash(pos: Vector3, normal: Vector3, power := 1.0) -> void:
	var n := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.BACK
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var ring := _sprite(pos + n * 0.06, Color(0.85, 0.86, 0.9), 1, 0.4, false)
	ring.global_transform = Transform3D(Basis.looking_at(n, up) * Basis.from_scale(Vector3.ONE * 0.4), pos + n * 0.06)
	_fade(ring, Vector3.ONE * 5.0 * power, 0.4)
	var rock: Array = [Color(0.42, 0.43, 0.47), Color(0.32, 0.33, 0.37), Color(0.55, 0.55, 0.58)]
	debris(pos + n * 0.3, n + Vector3.UP * 0.4, rock, int(18.0 * power), 8.0 * power, 1.6)
	line_sparks(pos + n * 0.2, n, Color(0.9, 0.88, 0.8), 12, 11.0 * power, 60.0, 0.4)
	flash_light(pos + n * 0.5, Color(1.0, 0.95, 0.85), 1.2, 6.0, 0.18)


## 场景破坏：砸地处留下一片放射状的黑色裂纹 + 一圈翻起来的大石块（半埋在地里、东倒西歪），
## 停留 hold 秒后石块沉回地面、裂纹淡掉。pos 为地面上的点（按水平地面处理）
static func ground_break(pos: Vector3, power := 1.0, hold := 7.0) -> void:
	var host := Node3D.new()
	root.add_child(host)
	host.global_position = pos
	# 裂纹：从中心向外的几条折线，越往外越细，中途分叉
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rays := 7 + int(2.0 * power)
	var a0 := randf() * TAU
	for i in rays:
		var ang := a0 + TAU * float(i) / float(rays) + randf_range(-0.25, 0.25)
		_crack(st, Vector3.ZERO, ang, randf_range(2.6, 4.8) * power, 0.2 * power, 2)
	# 中心一块碎裂的暗斑
	for i in 10:
		var a := TAU * float(i) / 10.0
		var b := TAU * float(i + 1) / 10.0
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(b), 0.0, sin(b)) * randf_range(0.5, 0.9) * power)
		st.add_vertex(Vector3(cos(a), 0.0, sin(a)) * randf_range(0.5, 0.9) * power)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.albedo_color = Color(0.03, 0.03, 0.05, 0.92)
	var cracks := MeshInstance3D.new()
	cracks.mesh = st.commit()
	cracks.material_override = cm
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cracks.position.y = 0.035
	host.add_child(cracks)
	cracks.scale = Vector3(0.2, 1.0, 0.2)
	var ct := cracks.create_tween()
	ct.tween_property(cracks, "scale", Vector3.ONE, 0.09).set_ease(Tween.EASE_OUT)
	ct.tween_interval(hold)
	ct.tween_property(cm, "albedo_color:a", 0.0, 1.4)
	# 石块：内圈大而斜，外圈小而散
	var rock_cols: Array[Color] = [Color(0.5, 0.46, 0.41), Color(0.4, 0.37, 0.34), Color(0.6, 0.56, 0.5), Color(0.33, 0.31, 0.3)]
	var n := int(13.0 * power) + 5
	for i in n:
		var ring := float(i) / float(n)
		var ang := randf() * TAU
		var rad := (0.9 + 2.6 * ring + randf_range(-0.3, 0.3)) * power
		var sz := lerpf(0.95, 0.3, ring) * randf_range(0.7, 1.2) * power
		var bm := BoxMesh.new()
		bm.size = Vector3(sz * randf_range(0.8, 1.4), sz * randf_range(0.5, 0.9), sz * randf_range(0.8, 1.3))
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = MeshLib.std_mat(rock_cols[randi() % rock_cols.size()], 0.95)
		host.add_child(mi)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var rest := out * rad + Vector3(0.0, sz * randf_range(0.05, 0.3), 0.0)
		mi.rotation = Vector3(randf_range(-0.7, 0.7), randf() * TAU, randf_range(-0.7, 0.7))
		mi.position = out * rad * 0.5 + Vector3(0.0, -sz, 0.0)
		mi.scale = Vector3.ONE * 0.3
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "position", rest + Vector3(0.0, sz * 0.6, 0.0), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE, 0.1)
		tw.chain().tween_property(mi, "position", rest, 0.14).set_ease(Tween.EASE_IN)
		tw.chain().tween_interval(hold + randf_range(-0.6, 0.6))
		tw.chain().tween_property(mi, "position", rest - Vector3(0.0, sz * 1.6, 0.0), 0.9).set_ease(Tween.EASE_IN)
	dust(pos, int(20.0 * power), 6.5 * power, 1.6)
	root.get_tree().create_timer(hold + 3.0).timeout.connect(host.queue_free)


## 一条裂纹：从 from 沿 ang 走 length，分成几段左右摆动，宽度线性收尖；depth > 0 时中途分叉
static func _crack(st: SurfaceTool, from: Vector3, ang: float, length: float, width: float, depth: int) -> void:
	var segs := 4
	var p := from
	var a := ang
	for i in segs:
		var w0 := width * (1.0 - float(i) / float(segs))
		var w1 := width * (1.0 - float(i + 1) / float(segs))
		a += randf_range(-0.5, 0.5)
		var d := Vector3(cos(a), 0.0, sin(a))
		var q := p + d * length / float(segs)
		var s := Vector3(-d.z, 0.0, d.x)
		st.add_vertex(p - s * w0 * 0.5)
		st.add_vertex(p + s * w0 * 0.5)
		st.add_vertex(q + s * w1 * 0.5)
		st.add_vertex(p - s * w0 * 0.5)
		st.add_vertex(q + s * w1 * 0.5)
		st.add_vertex(q - s * w1 * 0.5)
		if depth > 0 and i == 1:
			_crack(st, q, a + randf_range(0.5, 0.9) * (1.0 if randf() < 0.5 else -1.0), length * 0.5, w1 * 0.8, depth - 1)
		p = q
