extends Node3D
## 方块人修士 —— R15 骨架（十五件），Roblox 式的造型：每一件都是一整块光面方块（棱边带小圆角），
## 不再是一格格的像素体素。约 1.8m，面朝 -Z。尺寸单位 U = 5cm，下面的方块坐标都以 U 计、可以是小数。
## 十五件：
##   lower 下躯干（髋）· upper 上躯干 · head 头
##   arm_l/r 上臂 · fore_l/r 前臂 · hand_l/r 手
##   leg_l/r 大腿 · shin_l/r 小腿 · foot_l/r 脚
## 另挂几件随动的饰物：前后衣摆（skirt_f / skirt_b）、马尾（tail）、两条发带（ribbons），不算骨架。
## 每件由少数几个方块拼成：主体一块，外加腰带 / 护腕 / 衣领 / 五官 / 头发这些稍微鼓出来一点的薄块。
## 关节约定（都是绕本地 X 轴）：
##   大腿 leg.rotation.x  + 向前踢    小腿 shin.rotation.x  - 屈膝（脚向后收）
##   上臂 arm 由四元数摆向   前臂 fore.rotation.x  + 屈肘（手向前收）   脚 foot.rotation.x  - 绷脚尖
## animate() 负责走路 / 腾空 / 御剑 / 悬停的基础动作；近战和空战招式由 fighter_rig.gd 叠在上面。
## 文件名沿用 voxel_hero.gd（各处 preload 的路径不变）；死亡碎裂仍按 5cm 小格拆块（见 _part 里的 vox_cells）。

const SHADER := preload("res://shaders/block.gdshader")

const U := 0.05
const BEVEL := 0.28   # 棱边圆角（U）；薄块自动收小

const W := Color(0.95, 0.96, 0.98)    # 白衣
const W2 := Color(0.81, 0.85, 0.92)   # 裤
const W3 := Color(0.7, 0.78, 0.88)    # 内衬
const T := Color(0.15, 0.48, 0.57)    # 青色滚边 / 护腕 / 腰带
const T2 := Color(0.38, 0.76, 0.8)
const S := Color(0.99, 0.85, 0.75)    # 肤
const S2 := Color(0.97, 0.66, 0.62)   # 腮红
const M := Color(0.84, 0.4, 0.4)      # 唇
const H := Color(0.12, 0.12, 0.16)    # 发
const H2 := Color(0.26, 0.27, 0.36)   # 发丝高光
const E := Color(0.07, 0.08, 0.12)    # 瞳
const EI := Color(0.17, 0.42, 0.56)   # 虹膜
const G := Color(0.94, 0.75, 0.32)    # 金（发冠/带扣）
const J := Color(0.5, 0.9, 0.76)      # 玉（簪/佩）
const R := Color(0.8, 0.2, 0.22)      # 红绳流苏
const K := Color(0.15, 0.16, 0.2)     # 靴
const K2 := Color(0.86, 0.87, 0.9)    # 靴底

## 关节位置（U）。比例参考 Roblox 对战类游戏里的方块人：头大、躯干宽、四肢粗（一条胳膊 = 半个躯干宽）
const HIP := Vector3(0.0, 15.0, 0.0)
const WAIST := Vector3(0.0, 17.0, 0.0)
const NECK := Vector3(0.0, 26.0, 0.0)
const SHOULDER_V := Vector3(7.5, 24.5, 0.0)
const ELBOW_V := Vector3(7.5, 19.5, 0.0)
const WRIST_V := Vector3(7.5, 15.0, 0.0)
const HIPJ_V := Vector3(2.5, 15.0, 0.0)
const KNEE_V := Vector3(2.5, 8.0, 0.0)
const ANKLE_V := Vector3(2.5, 2.5, 0.0)

## 给 fighter_rig.gd 用的尺寸（米）
const LEG := 0.75            # 髋到脚底
const THIGH := 0.35          # 髋到膝
const SHANK := 0.4           # 膝到脚底
const ARM := 0.54            # 肩到掌心
const PALM := Vector3(0.0, -0.065, 0.0)          # 掌心相对手腕
const SHOULDER := Vector3(0.375, 1.225, 0.0)     # 右肩（角色本地系，站直时）
const CHEST_Y := 1.1

static var _shared: ShaderMaterial

var lower: Node3D
var upper: Node3D
var head: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var fore_l: MeshInstance3D
var fore_r: MeshInstance3D
var hand_l: MeshInstance3D
var hand_r: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var shin_l: MeshInstance3D
var shin_r: MeshInstance3D
var foot_l: MeshInstance3D
var foot_r: MeshInstance3D
var skirt: Node3D            # 前后衣摆的公共父节点（兼容旧接口：整体可绕 Y 拧一点）
var skirt_f: MeshInstance3D
var skirt_b: MeshInstance3D
var tail: MeshInstance3D
var ribbons: Array[MeshInstance3D] = []
## 外部（空战）给的额外飘动：0~1，衣摆 / 马尾 / 发带向后扬得更厉害
var stream_add := 0.0

var _t := 0.0
var _move := 0.0
var _air := 0.0
var _ride := 0.0
var _stream := 0.0
var _palette: Dictionary = {}
var _mat: ShaderMaterial
var _own := false


## palette: 颜色替换表（敌人换装用）；own_material: 用独立材质（可单独闪白）；hat: 戴斗笠
func _init(palette: Dictionary = {}, own_material := false, hat := false) -> void:
	_palette = palette
	_own = own_material
	if _shared == null:
		_shared = ShaderMaterial.new()
		_shared.shader = SHADER
	_mat = (_shared.duplicate() as ShaderMaterial) if own_material else _shared

	# 下躯干（根）→ 双腿三节
	lower = _part(_lower_boxes(), HIP, self)
	var hl := _mx(HIPJ_V)
	var kl := _mx(KNEE_V)
	var al := _mx(ANKLE_V)
	leg_r = _part(_thigh_boxes(), HIPJ_V, lower, HIP)
	shin_r = _part(_shin_boxes(), KNEE_V, leg_r, HIPJ_V)
	foot_r = _part(_foot_boxes(), ANKLE_V, shin_r, KNEE_V)
	leg_l = _part(_flip(_thigh_boxes()), hl, lower, HIP)
	shin_l = _part(_flip(_shin_boxes()), kl, leg_l, hl)
	foot_l = _part(_flip(_foot_boxes()), al, shin_l, kl)

	# 前后衣摆
	skirt = Node3D.new()
	lower.add_child(skirt)
	skirt_f = _part(_skirt_front_boxes(), Vector3(0.0, 15.0, -2.6), skirt, HIP)
	skirt_b = _part(_skirt_back_boxes(), Vector3(0.0, 15.0, 2.6), skirt, HIP)

	# 上躯干 → 双臂三节、头
	upper = _part(_torso_boxes(), WAIST, lower, HIP)
	var sl := _mx(SHOULDER_V)
	var el := _mx(ELBOW_V)
	var wl := _mx(WRIST_V)
	arm_r = _part(_arm_boxes(), SHOULDER_V, upper, WAIST)
	fore_r = _part(_fore_boxes(), ELBOW_V, arm_r, SHOULDER_V)
	hand_r = _part(_hand_boxes(), WRIST_V, fore_r, ELBOW_V)
	arm_l = _part(_flip(_arm_boxes()), sl, upper, WAIST)
	fore_l = _part(_flip(_fore_boxes()), el, arm_l, sl)
	hand_l = _part(_flip(_hand_boxes()), wl, fore_l, el)
	head = _part(_head_boxes(), NECK, upper, WAIST)
	tail = _part(_tail_boxes(), Vector3(0.0, 34.0, 5.0), head, NECK)
	ribbons.append(_part(_ribbon_boxes(-2.8, 25.0), Vector3(-2.8, 35.0, 5.0), head, NECK))
	ribbons.append(_part(_ribbon_boxes(2.8, 27.0), Vector3(2.8, 35.0, 5.0), head, NECK))
	if hat:
		_part(_hat_boxes(), NECK, head, NECK)


## 独立材质时的受击闪白（0~1）
func set_flash(v: float) -> void:
	if _own:
		_mat.set_shader_parameter("flash", v)


## 独立材质时的化光（0~1）：整身染成 color 并自发光
func set_glow(v: float, color: Color) -> void:
	if _own:
		_mat.set_shader_parameter("glow", v)
		_mat.set_shader_parameter("glow_color", color)


## 受击碎块用的颜色：按外观占比取衣、裤、滚边、肤、发（敌人换装后取替换色）
func chip_colors() -> Array:
	var out: Array = []
	for c: Color in [W, W, W, W2, W2, T, S, H]:
		out.append(_palette.get(c, c))
	return out


# ---------- 方块 → 网格 ----------

static func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## 左右镜像一组方块（右侧件 → 左侧件）
static func _flip(boxes: Array) -> Array:
	var out: Array = []
	for b: Array in boxes:
		out.append([-float(b[3]), b[1], b[2], -float(b[0]), b[4], b[5], b[6]])
	return out


## boxes: [[x0, y0, z0, x1, y1, z1, 颜色], ...]（U）；pivot: 这一件的关节位置（U）
func _part(boxes: Array, pivot: Vector3, parent: Node3D, parent_pivot := Vector3.ZERO) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var cells := {}
	for b: Array in boxes:
		var col: Color = b[6]
		col = _palette.get(col, col)
		var c0 := Vector3(float(b[0]), float(b[1]), float(b[2]))
		var c1 := Vector3(float(b[3]), float(b[4]), float(b[5]))
		_add_box(verts, norms, cols, idx, c0 - pivot, c1 - pivot, col)
		# 死亡碎裂（voxel_shatter.gd）用：把方块按 1U 小格记下来
		for x in range(int(floor(c0.x + 0.25)), maxi(int(ceil(c1.x - 0.25)), int(floor(c0.x + 0.25)) + 1)):
			for y in range(int(floor(c0.y + 0.25)), maxi(int(ceil(c1.y - 0.25)), int(floor(c0.y + 0.25)) + 1)):
				for z in range(int(floor(c0.z + 0.25)), maxi(int(ceil(c1.z - 0.25)), int(floor(c0.z + 0.25)) + 1)):
					cells[Vector3i(x, y, z)] = col
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = (pivot - parent_pivot) * U
	mi.set_meta("vox_cells", cells)
	mi.set_meta("vox_unit", U)
	mi.set_meta("vox_pivot", pivot)
	parent.add_child(mi)
	return mi


## 一个带圆角棱边的方块：每个角 3 个顶点（各属一个面、沿另两轴内收），6 个面 + 12 条棱的斜面 + 8 个角的小三角；
## 棱和角上的法线在相邻面之间插值，看起来就是圆角
static func _add_box(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		c0: Vector3, c1: Vector3, col: Color) -> void:
	var size := c1 - c0
	var bev := minf(BEVEL, minf(size.x, minf(size.y, size.z)) * 0.3)
	var lin := col.srgb_to_linear()
	var base := verts.size()
	for k in 8:
		var sg := Vector3(1.0 if k & 4 else -1.0, 1.0 if k & 2 else -1.0, 1.0 if k & 1 else -1.0)
		var p := Vector3(c1.x if k & 4 else c0.x, c1.y if k & 2 else c0.y, c1.z if k & 1 else c0.z)
		for a in 3:
			var inset := sg * bev
			inset[a] = 0.0
			var n := Vector3.ZERO
			n[a] = sg[a]
			verts.append((p - inset) * U)
			norms.append(n)
			cols.append(lin)
	var bit := [4, 2, 1]
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		# 面：a 轴两侧各一个
		for s in 2:
			var k0: int = int(bit[a]) * s
			var q := [k0, k0 + int(bit[b]), k0 + int(bit[b]) + int(bit[c]), k0 + int(bit[c])]
			_quad(verts, norms, idx, base + q[0] * 3 + a, base + q[1] * 3 + a, base + q[2] * 3 + a, base + q[3] * 3 + a)
		# 棱：沿 a 轴的四条
		for s in 4:
			var k0: int = (int(bit[b]) if s & 1 else 0) + (int(bit[c]) if s & 2 else 0)
			var k1: int = k0 + int(bit[a])
			_quad(verts, norms, idx, base + k0 * 3 + b, base + k1 * 3 + b, base + k1 * 3 + c, base + k0 * 3 + c)
	for k in 8:
		_tri(verts, norms, idx, base + k * 3, base + k * 3 + 1, base + k * 3 + 2)


static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, i0: int, i1: int, i2: int, i3: int) -> void:
	_tri(verts, norms, idx, i0, i1, i2)
	_tri(verts, norms, idx, i0, i2, i3)


## Godot 正面为顺时针：按实际叉积和外法线决定索引顺序
static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, i0: int, i1: int, i2: int) -> void:
	var n := norms[i0] + norms[i1] + norms[i2]
	if (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]).dot(n) > 0.0:
		idx.append_array(PackedInt32Array([i0, i2, i1]))
	else:
		idx.append_array(PackedInt32Array([i0, i1, i2]))


# ---------- 各部件（右侧件建模，左侧取镜像）：每件一大块，只留很少的点缀 ----------

## 下躯干：髋 + 腰带
func _lower_boxes() -> Array:
	return [
		[-5.0, 13.0, -2.5, 5.0, 15.4, 2.5, W2],
		[-5.15, 15.0, -2.65, 5.15, 17.0, 2.65, T],
		[-1.0, 15.3, -2.9, 1.0, 16.7, -2.6, G],
	]


## 右大腿
func _thigh_boxes() -> Array:
	return [[0.0, 7.8, -2.5, 5.0, 15.0, 2.5, W2]]


## 右小腿：下半截是靴
func _shin_boxes() -> Array:
	return [
		[0.0, 5.2, -2.5, 5.0, 8.2, 2.5, W2],
		[-0.08, 2.3, -2.58, 5.08, 5.6, 2.58, K],
	]


## 右脚
func _foot_boxes() -> Array:
	return [
		[-0.08, 0.5, -3.6, 5.08, 2.5, 2.58, K],
		[-0.12, 0.0, -3.7, 5.12, 0.6, 2.65, K2],
	]


## 前衣摆：短短一片
func _skirt_front_boxes() -> Array:
	return [
		[-3.2, 8.5, -2.9, 3.2, 15.0, -2.5, W],
		[-3.3, 8.5, -3.0, 3.3, 9.4, -2.45, T],
	]


## 后衣摆
func _skirt_back_boxes() -> Array:
	return [
		[-4.6, 7.0, 2.5, 4.6, 15.0, 2.9, W],
		[-4.7, 7.0, 2.45, 4.7, 7.9, 3.0, T],
	]


## 上躯干：一整块 + 一道交领 + 颈
func _torso_boxes() -> Array:
	return [
		[-5.0, 16.8, -2.5, 5.0, 26.0, 2.5, W],
		[0.4, 17.0, -2.66, 1.6, 25.2, -2.4, T],          # 右衽衣襟
		[-2.4, 25.2, -2.66, 2.4, 26.08, 2.66, T],        # 领口
		[-1.4, 26.0, -1.4, 1.4, 27.0, 1.4, S],           # 颈
	]


## 右上臂（袖）
func _arm_boxes() -> Array:
	return [[5.0, 19.2, -2.5, 10.0, 26.0, 2.5, W]]


## 右前臂：露出小臂，腕上一圈护腕
func _fore_boxes() -> Array:
	return [
		[5.0, 14.8, -2.5, 10.0, 19.8, 2.5, S],
		[4.9, 14.8, -2.6, 10.1, 16.8, 2.6, T],
	]


## 右手
func _hand_boxes() -> Array:
	return [[5.3, 12.4, -2.2, 9.7, 15.1, 2.2, S]]


## 头：一整块大方头 + 点眼 + 一道嘴 + 几大块头发 + 发冠发髻
func _head_boxes() -> Array:
	return [
		[-4.75, 26.6, -4.5, 4.75, 35.0, 4.5, S],
		# 五官：两个小方点眼、一道短嘴
		[-2.5, 30.6, -4.62, -1.4, 32.1, -4.4, E],
		[1.4, 30.6, -4.62, 2.5, 32.1, -4.4, E],
		[-1.3, 28.7, -4.6, 1.3, 29.2, -4.4, M],
		# 头发：顶、后脑、两侧、刘海
		[-5.05, 33.6, -4.8, 5.05, 35.6, 4.8, H],
		[-5.05, 27.6, 3.2, 5.05, 34.0, 5.0, H],
		[-5.1, 30.4, -1.0, -4.5, 34.0, 4.8, H],
		[4.5, 30.4, -1.0, 5.1, 34.0, 4.8, H],
		[-5.05, 32.6, -4.95, 5.05, 34.0, -4.3, H],
		[-5.08, 29.6, -4.9, -3.9, 32.8, -3.8, H],
		[3.9, 29.6, -4.9, 5.08, 32.8, -3.8, H],
		# 发冠 + 发髻 + 玉簪
		[-1.9, 35.6, -1.9, 1.9, 36.4, 1.9, G],
		[-1.4, 36.4, -1.4, 1.4, 38.4, 1.4, H],
		[-3.4, 37.0, -0.4, 3.4, 37.7, 0.4, J],
	]


## 马尾：从后脑垂到背后，随速度向后扬
func _tail_boxes() -> Array:
	return [
		[-1.4, 28.0, 4.8, 1.4, 34.0, 6.3, H],
		[-1.0, 21.5, 5.1, 1.0, 28.5, 6.2, H],
		[-1.55, 30.4, 4.7, 1.55, 31.6, 6.45, T],
	]


## 斗笠：几层收小的方台
func _hat_boxes() -> Array:
	var straw := Color(0.74, 0.62, 0.4)
	var straw2 := Color(0.6, 0.48, 0.3)
	var band := Color(0.5, 0.13, 0.13)
	return [
		[-8.6, 33.4, -8.6, 8.6, 34.2, 8.6, straw2],
		[-6.8, 34.2, -6.8, 6.8, 35.2, 6.8, straw],
		[-5.2, 35.2, -5.2, 5.2, 36.4, 5.2, straw],
		[-3.7, 36.4, -3.7, 3.7, 37.4, 3.7, band],
		[-2.4, 37.4, -2.4, 2.4, 38.8, 2.4, straw],
		[-1.0, 38.8, -1.0, 1.0, 39.8, 1.0, straw2],
	]


## 发带：从发冠后沿垂到背后
func _ribbon_boxes(x: float, y_end: float) -> Array:
	return [
		[x - 0.6, y_end + 2.0, 5.0, x + 0.6, 35.4, 5.35, T],
		[x - 0.6, y_end, 5.0, x + 0.6, y_end + 2.0, 5.35, T2],
	]


# ---------- 动作 ----------

## phase: 步态相位；move: 0~1 地面移动强度；airborne: 跳起/下落；floating: 御剑或凌空
func animate(dt: float, phase: float, move: float, airborne: bool, floating: bool) -> void:
	_t += dt
	var k := 1.0 - exp(-12.0 * dt)
	_move = lerpf(_move, move, k)
	_air = lerpf(_air, 1.0 if airborne else 0.0, k)
	_ride = lerpf(_ride, 1.0 if floating else 0.0, k)
	var g := (1.0 - _air) * (1.0 - _ride)
	var sw := sin(phase) * _move * g
	var cw := cos(phase) * _move * g
	var breath := sin(_t * 1.8)
	var hover := sin(_t * 1.3)

	# 腿：走路前后摆 + 回摆时提膝；腾空一前一后收腿；悬停一腿微提（凌空站姿）
	leg_l.rotation = Vector3(sw * 0.62 + _air * 0.55 + _ride * (0.42 + hover * 0.03), 0.0, 0.0)
	leg_r.rotation = Vector3(-sw * 0.62 - _air * 0.2 + _ride * 0.06, 0.0, 0.0)
	shin_l.rotation.x = -(maxf(-cw, 0.0) * 0.9 + maxf(sw, 0.0) * 0.25 + _air * 0.9 + _ride * (0.8 + hover * 0.04))
	shin_r.rotation.x = -(maxf(cw, 0.0) * 0.9 + maxf(-sw, 0.0) * 0.25 + _air * 0.5 + _ride * 0.22)
	foot_l.rotation.x = -(_air * 0.4 + _ride * 0.5)
	foot_r.rotation.x = -(_air * 0.3 + _ride * 0.4)

	# 臂：走路对侧摆臂带屈肘；悬停时双臂微张垂在身侧
	var spread := 0.07 + breath * 0.012 + _air * 0.4 + _ride * 0.16
	arm_l.rotation = Vector3(-sw * 0.55 + _air * 0.2 - _ride * 0.12, 0.0, -spread)
	arm_r.rotation = Vector3(sw * 0.55 + _air * 0.2 - _ride * 0.12, 0.0, spread)
	fore_l.rotation.x = 0.18 + maxf(-sw, 0.0) * 0.7 + _move * g * 0.25 + _air * 0.5 + _ride * 0.3
	fore_r.rotation.x = 0.18 + maxf(sw, 0.0) * 0.7 + _move * g * 0.25 + _air * 0.5 + _ride * 0.3
	hand_l.rotation = Vector3.ZERO
	hand_r.rotation = Vector3.ZERO

	lower.position.y = HIP.y * U + breath * 0.003 - absf(cw) * 0.012
	lower.rotation = Vector3.ZERO
	upper.rotation = Vector3(0.0, sw * 0.1, 0.0)
	head.rotation = Vector3(-_air * 0.1 - _ride * 0.06, -sw * 0.07, 0.0)
	skirt.rotation = Vector3.ZERO


## 布料 / 头发的随动放在自己的 _process 里：子节点晚于角色脚本处理，此时四肢姿势（含招式叠加）已经定了
func _process(dt: float) -> void:
	var want := clampf(_move * 0.5 + _ride * 0.55 + _air * 0.4 + stream_add, 0.0, 1.3)
	_stream = lerpf(_stream, want, 1.0 - exp(-8.0 * dt))
	var s := _stream
	# 前摆被抬起的腿顶起来，后摆被向后踢的腿带起来；飞行时整体向后扬
	var fwd := maxf(maxf(leg_l.rotation.x, leg_r.rotation.x), 0.0)
	var back := maxf(maxf(-leg_l.rotation.x, -leg_r.rotation.x), 0.0)
	skirt_f.rotation.x = fwd * 0.85 - s * 0.25 + sin(_t * 6.0) * 0.04 * s
	skirt_b.rotation.x = -(back * 0.8 + s * 0.75) + sin(_t * 5.0 + 1.0) * (0.02 + 0.07 * s)
	tail.rotation.x = -(0.05 + s * 0.95) + sin(_t * 4.2) * (0.03 + 0.08 * s)
	tail.rotation.z = sin(_t * 2.7) * 0.05 * (0.3 + s)
	for i in ribbons.size():
		var r := ribbons[i]
		r.rotation.x = -(0.04 + s * 1.0) + sin(_t * (5.0 + i * 1.3) + i * 2.0) * (0.03 + 0.1 * s)
		r.rotation.z = sin(_t * 3.1 + i * 1.7) * 0.05 * (0.3 + s)
