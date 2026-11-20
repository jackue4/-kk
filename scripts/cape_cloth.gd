extends MeshInstance3D
## 披风的布料模拟（voxel_hero.gd 每帧调 tick）。不是摆动画：一张 6×9 的质点网格在世界空间里算，
##   · 最上面一排钉在肩后，跟着上半身走；其余质点受重力、空气阻力和风（迎风的面被推开，所以飞起来整幅向后扬、带抖动）
##   · 相邻质点之间有定长约束（横、竖、两条对角），每个质点到肩上的钉点再加一道「拉不长」的限制，冲刺 / 被打飞也不会扯成面条
##   · 和身体碰撞：贴不进后背、盖不过臀，踢腿会把它顶起来（大腿、小腿各一个胶囊），站在地上时不穿地
##   · 主角走、跑是真实的惯性拖尾；飞得很快时超出的那部分速度换算成迎面风（否则一帧几米的位移会把布料甩飞）；瞬移直接整幅搬过去
## 离镜头远（SIM_RANGE 以外）或看不见时不算，整幅按静止垂落的样子贴在背后。
## 网格每帧重建：外面一层、里衬一层（法线相反、颜色发暗），颜色和镶边在 cape_cloth.gdshader 里画。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/cape_cloth.gdshader")
const LINE_SHADER := preload("res://shaders/cape_outline.gdshader")

const COLS := 6
const ROWS := 9
const N := COLS * ROWS
## 静止形状（上半身关节的本地空间，米）：从肩后垂到脚踝，上窄下宽
const TOP_Y := 0.43
const LEN := 1.12
const TOP_HALF := 0.38
const BOT_HALF := 0.47
const BACK_Z := 0.178
const BODY_Z := 0.165         # 后背的碰撞面
const LEG_R := 0.135          # 腿的胶囊半径
const GRAVITY := 9.8
const DRAG := 1.25            # 空气对布面的推力系数
const FOLLOW_SPD := 7.0       # 这个速度以内是真实惯性；超出的部分换成迎面风
const WIND_MAX := 30.0
const ITER := 3
const SIM_RANGE := 45.0

var upper: Node3D             # 上半身（钉点跟着它）
var lower: Node3D             # 下半身（臀部碰撞）
var legs: Array = []          # [[大腿, 小腿, 脚], [大腿, 小腿, 脚]]
var root: Node3D              # 角色根（脚底高度）
var grounded := true          # 站在地上（要不要挡地面）
var wind := Vector3(0.5, 0.0, 0.25)   # 环境风

var _rest := PackedVector3Array()     # 静止形状（upper 本地）
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _nrm := PackedVector3Array()
var _ca := PackedInt32Array()
var _cb := PackedInt32Array()
var _cl0 := PackedFloat32Array()      # 约束原长（未缩放）
var _cl := PackedFloat32Array()
var _tether0 := PackedFloat32Array()
var _tether := PackedFloat32Array()
var _ok := false
var _scale := 1.0
var _last := Vector3.ZERO
var _t := 0.0
var _skip := 0
var _was_far := false
var _mat: ShaderMaterial
var _line: ShaderMaterial     # 描边那一遍（set_outline 开着时挂在 _mat.next_pass 上）
var _amesh := ArrayMesh.new()
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()


func _init() -> void:
	top_level = true
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	mesh = _amesh
	_rest.resize(N)
	_pos.resize(N)
	_prev.resize(N)
	_nrm.resize(N)
	_tether0.resize(N)
	_tether.resize(N)
	_verts.resize(N * 2)
	_norms.resize(N * 2)
	_cols.resize(N * 2)
	_uvs.resize(N * 2)
	for j in ROWS:
		var v := float(j) / float(ROWS - 1)
		var half := lerpf(TOP_HALF, BOT_HALF, v)
		for i in COLS:
			var u := float(i) / float(COLS - 1) * 2.0 - 1.0
			var k := j * COLS + i
			# 肩上那一段略微包住肩头，往下离身体远一点
			_rest[k] = Vector3(u * half, TOP_Y - LEN * v, BACK_Z - 0.05 * u * u * (1.0 - v) + 0.035 * v)
			_nrm[k] = Vector3.BACK
			_uvs[k] = Vector2(u * 0.5 + 0.5, v)
			_uvs[N + k] = _uvs[k]
			_cols[k] = Color.WHITE
			_cols[N + k] = Color(0.55, 0.55, 0.58)
	for k in N:
		_tether0[k] = _rest[k].distance_to(_rest[k % COLS]) * 1.03
	# 约束：竖、横（钉住的第一排之间不用）、两条对角；a 总在 b 的上面 / 左边，所以只有 a 可能是钉点
	for j in ROWS:
		for i in COLS:
			var k := j * COLS + i
			if j < ROWS - 1:
				_link(k, k + COLS)
			if i < COLS - 1 and j > 0:
				_link(k, k + 1)
			if i < COLS - 1 and j < ROWS - 1:
				_link(k, k + COLS + 1)
				_link(k + 1, k + COLS)
	_cl.resize(_cl0.size())
	# 三角形：外面一层顺时针（从背后看），里衬反过来
	for j in ROWS - 1:
		for i in COLS - 1:
			var a := j * COLS + i
			var b := a + 1
			var c := a + COLS + 1
			var d := a + COLS
			_idx.append_array(PackedInt32Array([a, b, c, a, c, d, N + a, N + c, N + b, N + a, N + d, N + c]))


func _link(a: int, b: int) -> void:
	_ca.append(a)
	_cb.append(b)
	_cl0.append(_rest[a].distance_to(_rest[b]))


func set_colors(cape: Color, trim: Color) -> void:
	_mat.set_shader_parameter("cape_col", cape)
	_mat.set_shader_parameter("trim_col", trim)


func set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", v)


func set_glow(v: float, color: Color) -> void:
	_mat.set_shader_parameter("glow", v)
	_mat.set_shader_parameter("glow_color", color)


## 描边（和方块人的 set_outline 一起开关）：披风四周一道 color 色的亮线，见 cape_outline.gdshader
func set_outline(k: float, color: Color) -> void:
	if k <= 0.001:
		_mat.next_pass = null
		return
	if _line == null:
		_line = ShaderMaterial.new()
		_line.shader = LINE_SHADER
	_line.set_shader_parameter("power", k)
	_line.set_shader_parameter("line_color", color)
	if _mat.next_pass != _line:
		_mat.next_pass = _line


## 整幅摆回静止形状（刚出现、缩放变了、离远了）
func _settle(xf: Transform3D, sc: float) -> void:
	_scale = sc
	for k in N:
		_pos[k] = xf * _rest[k]
		_prev[k] = _pos[k]
	for c in _cl0.size():
		_cl[c] = _cl0[c] * sc
	for k in N:
		_tether[k] = _tether0[k] * sc
	_ok = true


func tick(dt: float) -> void:
	if upper == null or not is_inside_tree() or not upper.is_inside_tree():
		return
	if not is_visible_in_tree():
		_ok = false
		return
	var xf := upper.global_transform
	var sc := xf.basis.get_scale().y
	if sc < 0.05:
		_ok = false
		return
	var anchor := xf * Vector3(0.0, TOP_Y, BACK_Z)
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(anchor) > SIM_RANGE * SIM_RANGE
	if far:
		# 远处：不算布料，隔几帧按静止形状贴一次
		_skip += 1
		if _was_far and _skip % 4 != 0:
			return
		_settle(xf, sc)
		_ok = false
		_was_far = true
	else:
		_was_far = false
		if not _ok or absf(sc - _scale) > 0.01 * _scale:
			_settle(xf, sc)
			_last = anchor
		_simulate(minf(dt, 1.0 / 30.0), xf, anchor)
	_last = anchor
	_rebuild(anchor)


func _simulate(dt: float, xf: Transform3D, anchor: Vector3) -> void:
	if dt < 1e-5:
		return
	_t += dt
	# 根运动：瞬移整幅搬走；太快的部分换成迎面风
	var delta := anchor - _last
	var dl := delta.length()
	var shift := Vector3.ZERO
	var w := wind * (0.6 + 0.4 * sin(_t * 0.7))
	if dl > 2.5:
		shift = delta
	else:
		var sp := dl / dt
		if sp > FOLLOW_SPD:
			var f := 1.0 - FOLLOW_SPD / sp
			shift = delta * f
			w -= (delta / dt) * f
	w = w.limit_length(WIND_MAX)
	var wl := w.length()
	var keep := exp(-1.6 * dt)
	var g := Vector3(0.0, -GRAVITY * _scale * dt * dt, 0.0)
	var k2 := DRAG * dt * dt
	for k in range(COLS, N):
		var p := _pos[k] + shift
		var v := (p - _prev[k] - shift) * keep
		var n := _nrm[k]
		var rel := w - v / dt
		var push := n * (n.dot(rel) * 0.9) + rel * 0.12
		if wl > 2.0:
			push += n * (sin(_t * 13.0 + float(k) * 1.31) * wl * 0.16)
		_prev[k] = p
		_pos[k] = p + v + g + push * k2
	for i in COLS:
		_pos[i] = xf * _rest[i]
		_prev[i] = _pos[i]
	# 身体碰撞要用的东西
	var inv_u := xf.affine_inverse()
	var has_low := lower != null and lower.is_inside_tree()
	var inv_l := lower.global_transform.affine_inverse() if has_low else Transform3D.IDENTITY
	var xf_l := lower.global_transform if has_low else Transform3D.IDENTITY
	var segs: Array = []
	for leg: Array in legs:
		var a: Vector3 = (leg[0] as Node3D).global_position
		var b: Vector3 = (leg[1] as Node3D).global_position
		var c: Vector3 = (leg[2] as Node3D).global_position
		segs.append([a, b])
		segs.append([b, c])
	var leg_r := LEG_R * _scale
	var floor_y := root.global_position.y + 0.03 if grounded and root != null else -1.0e9
	var cn := _ca.size()
	for it in ITER:
		for c in cn:
			var a := _ca[c]
			var b := _cb[c]
			var d := _pos[b] - _pos[a]
			var l := d.length()
			if l < 1e-6:
				continue
			var corr := d * ((l - _cl[c]) / l)
			if a < COLS:
				_pos[b] -= corr
			else:
				_pos[a] += corr * 0.5
				_pos[b] -= corr * 0.5
		for k in range(COLS, N):
			var p := _pos[k]
			# 拉不长：到自己那一列钉点的距离有上限
			var d := p - _pos[k % COLS]
			var l := d.length()
			if l > _tether[k]:
				p = _pos[k % COLS] + d * (_tether[k] / l)
			# 后背
			var q := inv_u * p
			if q.z < BODY_Z and q.y > -0.12 and q.y < 0.5 and absf(q.x) < 0.37:
				q.z = BODY_Z
				p = xf * q
			elif has_low:
				# 臀
				q = inv_l * p
				if q.z < BODY_Z and q.y > -0.3 and q.y < 0.14 and absf(q.x) < 0.4:
					q.z = BODY_Z
					p = xf_l * q
			# 腿
			if k >= COLS * 3:
				for s: Array in segs:
					var cp := Geometry3D.get_closest_point_to_segment(p, s[0], s[1])
					var e := p - cp
					var el := e.length()
					if el < leg_r and el > 1e-5:
						p = cp + e * (leg_r / el)
			if p.y < floor_y:
				p.y = floor_y
			_pos[k] = p


## 按质点位置重建网格（节点放在肩后的钉点，顶点是相对它的偏移）
func _rebuild(origin: Vector3) -> void:
	global_transform = Transform3D(Basis.IDENTITY, origin)
	for j in ROWS:
		for i in COLS:
			var k := j * COLS + i
			var du := _pos[k + (1 if i < COLS - 1 else 0)] - _pos[k - (1 if i > 0 else 0)]
			var dv := _pos[k + (COLS if j < ROWS - 1 else 0)] - _pos[k - (COLS if j > 0 else 0)]
			var n := dv.cross(du)
			n = n.normalized() if n.length_squared() > 1e-10 else Vector3.BACK
			_nrm[k] = n
			var p := _pos[k] - origin
			_verts[k] = p
			_verts[N + k] = p
			_norms[k] = n
			_norms[N + k] = -n
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_NORMAL] = _norms
	arr[Mesh.ARRAY_COLOR] = _cols
	arr[Mesh.ARRAY_TEX_UV] = _uvs
	arr[Mesh.ARRAY_INDEX] = _idx
	_amesh.clear_surfaces()
	_amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _mat.next_pass != null:
		# 描边要知道披风的中心在哪（往四周放大用）：四个角取平均
		_line.set_shader_parameter("center", (_verts[0] + _verts[COLS - 1] + _verts[N - COLS] + _verts[N - 1]) * 0.25)
