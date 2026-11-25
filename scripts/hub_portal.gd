extends Node3D
## 透视门（2026-11-21 场景美术专项）：主城东侧通灵田农场的那道牌坊门、农场南门回主城的那道，各是一个这个节点。
## 门洞里是另一边的实时画面：
##   · 一个自己有 World3D 的 SubViewport，里面摆着对面场景的「副本」——同一份网格 / 材质（不多占显存），外加同一套天空 / 日光
##   · 副本相机 = 门对门的变换（xfer）× 主镜头：主镜头透过这道门看出去的方向，在对面就是从那边的门往里看 —— 走过去会看到的就是门里画的
##   · 门洞那张面片（farm_portal.gdshader）按屏幕坐标取这张画面，四周加一圈流光；门前一张叠加的面片画溢光、飘出来的花瓣和光点，门脚一摊柔光
##   · 只在门在画面里、离得不远时才画（SubViewport 其余时候停着），分辨率是主画面的 scale_k 倍
## 那边的画面出图时不做色调映射 / 调色 / 辉光（给它一份关掉这些的环境副本），由门面片还原成线性色、交给主画面统一做一次，颜色才和真走过去一致。
## 穿门（crossed）由 hub_hall.gd 每帧问：主角从门的正面穿过门洞平面就算，然后按 xfer 把主角、镜头整体搬到对面（镜头看到的和门里画的接得上）。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/farm_portal.gdshader")
const FX_SHADER := preload("res://shaders/farm_portal_fx.gdshader")
const NOISE := preload("res://fx/cine/cine_noise.png")

var frame := Transform3D.IDENTITY       # 这道门（世界）：原点 = 门洞底边中点，-Z = 往门里走的方向（+Z 是站着看门的那一面）
var dest := Transform3D.IDENTITY        # 对面「走出来」的坐标系：原点 = 那边门洞底边中点，-Z = 出来以后继续往前走的方向
var width := 8.0
var height := 7.0
var scale_k := 0.55                     # 门里画面的分辨率（主画面的倍数）
var max_dist := 130.0
var sun_energy := -1.0                  # 门里那盏日光的亮度（>= 0 时用它）：门里的日光不投影子，兼容渲染器下要换回「不带影子」那套光照的亮度
var on := false                         # 门所在的场景开着时才画（hub_hall.gd 开关）
var col_a := Color(1.0, 0.64, 0.86)
var col_b := Color(1.0, 0.88, 0.58)

var _vp: SubViewport
var _pc: Camera3D
var _holder: Node3D
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _fx: Array[MeshInstance3D] = []
var _sync: Array = []                   # [源节点, 副本]：会动的东西（水车、主城的紫晶）每帧对一下
var _drawn := 0                         # 门里画过几帧（自检用）
var _prime := 0                         # >0：不管看不看得见都先画这么多帧（载入幕布后面把那边的着色器编掉）


func _init() -> void:
	process_priority = 50                # 在镜头（CameraRig 是 20）之后：用这一帧镜头最终的位置


## 建门：sources = 对面场景里要复制进门里世界的节点（递归找网格 / 文字）；env、sun = 对面的天空和日光；attrs = 主镜头的相机属性
func build(sources: Array, env: Environment, sun: DirectionalLight3D, attrs: CameraAttributes) -> void:
	_vp = SubViewport.new()
	_vp.name = "PortalView"
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.audio_listener_enable_3d = false
	add_child(_vp)
	var we := WorldEnvironment.new()
	we.environment = _view_env(env)
	_vp.add_child(we)
	if sun != null:
		var s := sun.duplicate() as DirectionalLight3D
		_vp.add_child(s)
		s.transform = sun.transform        # 主城节点在原点、不转，日光的本地变换就是世界变换（建门时日光不一定挂在场景树上）
		# 门里不画影子：整座岛是一两张大网格，影子的四级级联每级都要把整张网格再画一遍（实测门里画面的图元八成是影子），
		# 关掉以后门里只画一遍颜色。这盏灯用的着色器变体在载入时由 prime() 先画几帧编掉
		s.shadow_enabled = false
		if sun_energy >= 0.0:
			s.light_energy = sun_energy
	_pc = Camera3D.new()
	_pc.attributes = attrs
	_vp.add_child(_pc)
	_pc.current = true
	_holder = Node3D.new()
	_vp.add_child(_holder)
	for n: Variant in sources:
		if n is Node:
			_copy(n as Node)
	# 门洞面片：QuadMesh 朝 +Z，摆在门洞正中
	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	_quad.mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("view", _vp.get_texture())
	_mat.set_shader_parameter("noise_tex", NOISE)
	_mat.set_shader_parameter("size", Vector2(width, height))
	_mat.set_shader_parameter("rim_a", Vector3(col_a.r, col_a.g, col_a.b))
	_mat.set_shader_parameter("rim_b", Vector3(col_b.r, col_b.g, col_b.b))
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_quad.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0))
	# 门前的溢光 / 花瓣（竖着，贴在门柱正面前一点）、门脚的柔光（平铺在门外的地上）
	var fx_w := width + 6.0
	var fx_h := height + 4.0
	_fx.append(_fx_quad(Vector2(fx_w, fx_h), 0.0, frame * Transform3D(Basis.IDENTITY, Vector3(0.0, fx_h * 0.5, 0.62))))
	var gd := 7.0
	_fx.append(_fx_quad(Vector2(width + 4.0, gd), 1.0, frame * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.06, gd * 0.5))))


func _fx_quad(sz: Vector2, mode: float, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = sz
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = FX_SHADER
	m.set_shader_parameter("noise_tex", NOISE)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("size", sz)
	m.set_shader_parameter("hole", Vector2(width, height))
	m.set_shader_parameter("col_a", Vector3(col_a.r, col_a.g, col_a.b))
	m.set_shader_parameter("col_b", Vector3(col_b.r, col_b.g, col_b.b))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = xf
	return mi


## 门里世界用的环境：天空、雾照旧；色调映射改成线性、不调色、不加辉光（这些留给主画面对门面片统一做）
static func _view_env(env: Environment) -> Environment:
	var e := env.duplicate() as Environment
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.adjustment_enabled = false
	e.glow_enabled = false
	return e


func _copy(n: Node) -> void:
	if n.has_meta("no_portal_copy"):
		return
	if n is MeshInstance3D:
		var src := n as MeshInstance3D
		if src.mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.cast_shadow = src.cast_shadow
			_holder.add_child(mi)
			mi.global_transform = src.global_transform
			if src.has_meta("portal_sync"):
				_sync.append([src, mi])
	elif n is Label3D:
		var l := (n as Label3D).duplicate() as Label3D
		_holder.add_child(l)
		l.global_transform = (n as Label3D).global_transform
	for c in n.get_children():
		_copy(c)


## 门对门的变换：这边的一点 / 一个朝向，搬到对面去
func xfer() -> Transform3D:
	return dest * frame.affine_inverse()


## 绕竖轴转了多少（主角 / 镜头的朝向加上它）
func xfer_yaw() -> float:
	var f := xfer().basis * Vector3.FORWARD
	return atan2(-f.x, -f.z)


## 主角从 a 走到 b：是不是从门的正面穿过了门洞
func crossed(a: Vector3, b: Vector3) -> bool:
	var inv := frame.affine_inverse()
	var la := inv * a
	var lb := inv * b
	if la.z <= 0.0 or lb.z > 0.0:
		return false
	var t := la.z / maxf(la.z - lb.z, 0.0001)
	var hit := la.lerp(lb, t)
	return absf(hit.x) < width * 0.5 - 0.2 and hit.y > -1.5 and hit.y < height


## 门前（正面）几米、面朝门外的那个位置（从对面过来的人站这里）
func front(d: float) -> Vector3:
	return frame * Vector3(0.0, 0.1, d)


## 载入时先画几帧（不管看不看得见、门所在的场景开没开），把门里那边的着色器在幕布后面编掉：
## 这几帧不跟主镜头，用一个固定机位 —— 站在对面那道门后面几米、朝门里看（看得到那边的大部分东西）
func prime(frames := 3) -> void:
	_prime = maxi(_prime, frames)


func drawn() -> int:
	return _drawn


## 自检用：藏起门前的特效（花瓣 / 溢光 / 门脚的光）、藏起门面片
func set_fx_visible(v: bool) -> void:
	for f in _fx:
		f.set_meta("hold", not v)
		f.visible = v and on


func set_view_visible(v: bool) -> void:
	_quad.set_meta("hold", not v)
	_quad.visible = v and on


## 门里世界摆了多少个副本（自检用）
func copies() -> int:
	return _holder.get_child_count() if _holder != null else 0


func _seen(c: Camera3D) -> bool:
	var cp := c.global_position
	var lc := frame.affine_inverse() * cp
	if lc.z <= 0.02:
		return false                    # 镜头在门背面：门面片是单面的，看不到
	if cp.distance_to(frame.origin) > max_dist:
		return false
	if lc.length() < 4.0:
		return true
	var pts := [Vector3(0.0, height * 0.5, 0.0), Vector3(-width * 0.5, 0.0, 0.0), Vector3(width * 0.5, 0.0, 0.0),
			Vector3(-width * 0.5, height, 0.0), Vector3(width * 0.5, height, 0.0)]
	for p: Vector3 in pts:
		if c.is_position_in_frustum(frame * p):
			return true
	return false


func _process(_dt: float) -> void:
	if _vp == null:
		return
	var c := get_viewport().get_camera_3d()
	_quad.visible = on and not bool(_quad.get_meta("hold", false))
	for f in _fx:
		f.visible = on and not bool(f.get_meta("hold", false))
	if _prime > 0 and c != null and not (on and _seen(c)):
		_prime -= 1
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if _vp.size.x < 256:
			_vp.size = Vector2i(320, 180)
		_pc.fov = 70.0
		_pc.near = c.near
		_pc.far = c.far
		_pc.global_transform = dest * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0.0, 5.0, 7.0))
		_drawn += 1
		return
	var show := on and c != null and _seen(c)
	if not show:
		if _vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _prime > 0:
		_prime -= 1
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var vs := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(int(vs.x * scale_k), 64), maxi(int(vs.y * scale_k), 64))
	if _vp.size != want:
		_vp.size = want
	_pc.fov = c.fov
	_pc.near = c.near
	_pc.far = c.far
	_pc.keep_aspect = c.keep_aspect
	_pc.h_offset = c.h_offset
	_pc.v_offset = c.v_offset
	_pc.global_transform = xfer() * c.global_transform
	for s: Array in _sync:
		var src: Node3D = s[0]
		var dst: Node3D = s[1]
		if is_instance_valid(src):
			dst.global_transform = src.global_transform
	_drawn += 1
