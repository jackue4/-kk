extends Node3D
## 像素方块搭的微缩白衣修士：约 1.75m、大头手办比例，面朝 -Z。
## 每格 5cm。分件：双腿 / 袍摆 / 上身（躯干 + 双臂 + 头 + 两条发带），
## animate() 负责行走摆臂迈步、腾空、御剑负手、发带飘动。
## 坐标约定：体素格 i 占据 [i, i+1]，x 以 0 为左右对称面，y=0 是脚底。

const VoxelModel := preload("res://scripts/voxel_model.gd")

const U := 0.05

const W := Color(0.95, 0.96, 0.98)    # 白袍
const W2 := Color(0.81, 0.85, 0.92)   # 衣褶
const W3 := Color(0.7, 0.78, 0.88)    # 内衬
const T := Color(0.15, 0.48, 0.57)    # 青色滚边
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

const WAIST := Vector3(0.0, 12.0, 0.0)
const NECK := Vector3(0.0, 20.5, 0.0)

var upper: Node3D
var head: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var skirt: MeshInstance3D
var ribbons: Array[MeshInstance3D] = []

var _t := 0.0
var _move := 0.0
var _air := 0.0
var _ride := 0.0
var _palette: Dictionary = {}
var _mat: ShaderMaterial


## palette: 颜色替换表（敌人换装用）；own_material: 用独立材质（可单独闪白）；hat: 戴斗笠
func _init(palette: Dictionary = {}, own_material := false, hat := false) -> void:
	_palette = palette
	if own_material:
		_mat = VoxelModel.material().duplicate() as ShaderMaterial
	else:
		_mat = VoxelModel.material()
	var leg := _leg_model()
	var leg_m := leg.flipped() as VoxelModel  # 先镜像再换色，避免同一格被换色两次
	leg_l = _part(leg, Vector3(-1.5, 9.0, 0.0), self)
	leg_r = _part(leg_m, Vector3(1.5, 9.0, 0.0), self)
	skirt = _part(_skirt_model(), WAIST, self)

	upper = Node3D.new()
	upper.position = WAIST * U
	add_child(upper)
	_part(_torso_model(), WAIST, upper, WAIST)
	var arm := _arm_model()
	var arm_m := arm.flipped() as VoxelModel
	arm_r = _part(arm, Vector3(4.5, 19.0, 0.0), upper, WAIST)
	arm_l = _part(arm_m, Vector3(-4.5, 19.0, 0.0), upper, WAIST)
	head = _part(_head_model(), NECK, upper, WAIST)
	ribbons.append(_part(_ribbon_model(-2, 21), Vector3(-1.5, 31.0, 2.5), head, NECK))
	ribbons.append(_part(_ribbon_model(1, 23), Vector3(1.5, 31.0, 2.5), head, NECK))
	if hat:
		_part(_hat_model(), NECK, head, NECK)


## 独立材质时的受击闪白（0~1）
func set_flash(v: float) -> void:
	if _mat != VoxelModel.material():
		_mat.set_shader_parameter("flash", v)


## 独立材质时的化光（0~1）：整身染成 color 并自发光
func set_glow(v: float, color: Color) -> void:
	if _mat != VoxelModel.material():
		_mat.set_shader_parameter("glow", v)
		_mat.set_shader_parameter("glow_color", color)


## 受击碎块用的颜色：按外观占比取袍、褶、滚边、肤、发（敌人换装后取替换色）
func chip_colors() -> Array:
	var out: Array = []
	for c: Color in [W, W, W, W2, W2, T, S, H]:
		out.append(_palette.get(c, c))
	return out


func _part(m: VoxelModel, pivot: Vector3, parent: Node3D, parent_pivot := Vector3.ZERO) -> MeshInstance3D:
	if not _palette.is_empty():
		for k: Vector3i in m.cells:
			var c: Color = m.cells[k]
			if _palette.has(c):
				m.cells[k] = _palette[c]
	var mi := MeshInstance3D.new()
	mi.mesh = m.build(U, pivot)
	mi.material_override = _mat
	mi.position = (pivot - parent_pivot) * U
	# 死亡碎裂（voxel_shatter.gd）按体素格拆块
	mi.set_meta("vox_cells", m.cells)
	mi.set_meta("vox_unit", U)
	mi.set_meta("vox_pivot", pivot)
	parent.add_child(mi)
	return mi


# ---------- 各部件 ----------

## 左腿（x<0）；右腿取镜像
func _leg_model() -> VoxelModel:
	var m := VoxelModel.new()
	m.box(-3, 4, -2, -1, 8, 1, W2)    # 裤腿
	m.box(-3, 2, -3, -1, 3, 0, K)     # 靴筒
	m.paint(-3, 3, -3, -1, 3, 0, T)   # 靴口滚边
	m.box(-3, 1, -5, -1, 1, 0, K)     # 鞋面
	m.box(-3, 2, -5, -1, 2, -5, K)    # 翘头
	m.box(-3, 0, -5, -1, 0, 0, K2)    # 白底
	return m


func _skirt_model() -> VoxelModel:
	var m := VoxelModel.new()
	m.box(-4, 9, -3, 3, 11, 2, W)
	m.box(-5, 6, -3, 4, 8, 2, W)
	m.box(-5, 2, -4, 4, 5, 3, W)
	m.sym_cut(-5, 2, -4, -5, 5, -4)   # 下摆四角削圆
	m.sym_cut(-5, 2, 3, -5, 5, 3)
	m.paint(-5, 2, -4, 4, 2, 3, T)    # 下摆滚边
	# 衣褶：前、后、两侧各两道
	m.sym_paint(-3, 3, -4, -3, 5, -4, W2)
	m.sym_paint(-3, 6, -3, -3, 8, -3, W2)
	m.sym_paint(-3, 3, 3, -3, 5, 3, W2)
	m.sym_paint(-3, 6, 2, -3, 10, 2, W2)
	m.sym_paint(-5, 3, -2, -5, 8, -2, W2)
	m.sym_paint(-5, 3, 1, -5, 8, 1, W2)
	# 腰带垂绦
	m.box(-1, 6, -4, 0, 11, -4, T)
	m.box(-1, 4, -5, 0, 5, -5, T)
	m.box(-1, 3, -5, 0, 3, -5, G)
	# 右胯玉佩：红绳 + 玉 + 流苏
	m.put(2, 10, -4, R)
	m.box(2, 8, -4, 2, 9, -4, J)
	m.box(2, 6, -4, 2, 7, -4, R)
	return m


func _torso_model() -> VoxelModel:
	var m := VoxelModel.new()
	m.box(-4, 12, -3, 3, 13, 2, T)     # 腰带
	m.box(-1, 12, -4, 0, 13, -4, G)    # 带扣
	m.box(-4, 14, -3, 3, 19, 2, W)
	m.paint(-2, 19, -2, 1, 19, 1, T)   # 领口一圈
	# 交领：右衽，一道从左肩斜到右腰，一道短的从右肩搭上来
	for c: Vector2i in [Vector2i(-2, 19), Vector2i(-1, 18), Vector2i(0, 17), Vector2i(1, 16),
			Vector2i(2, 15), Vector2i(3, 14), Vector2i(1, 19), Vector2i(0, 18)]:
		m.put(c.x, c.y, -3, T)
	m.put(-1, 19, -3, W3)
	m.put(0, 19, -3, W3)
	m.sym_paint(-2, 14, 2, -2, 17, 2, W2)  # 背后衣褶
	m.box(-1, 20, -1, 0, 20, 0, S)     # 颈
	return m


## 右臂（x>0）；左臂取镜像。广袖 + 袖口滚边，手从袖里露出一点
func _arm_model() -> VoxelModel:
	var m := VoxelModel.new()
	m.box(4, 17, -2, 6, 19, 1, W)
	m.box(4, 14, -3, 6, 16, 2, W)
	m.box(4, 13, -3, 6, 13, 2, T)
	m.box(4, 11, -1, 5, 12, 0, S)
	m.paint(5, 14, -3, 5, 16, -3, W2)
	m.paint(5, 14, 2, 5, 16, 2, W2)
	m.paint(6, 15, -1, 6, 18, -1, W2)
	return m


func _head_model() -> VoxelModel:
	var m := VoxelModel.new()
	m.box(-4, 32, 0, 3, 32, 0, J)      # 玉簪：先放，中段会被发髻盖住
	m.put(3, 32, 0, G)
	m.box(-5, 21, -4, 4, 29, 3, S)     # 头
	# 发：顶、两侧（上半盖到脸侧，下半收到耳后）、后脑
	m.box(-5, 30, -4, 4, 30, 3, H)
	m.sym_cut(-5, 30, -4, -5, 30, -4)
	m.sym_cut(-5, 30, 3, -5, 30, 3)
	m.sym(-6, 26, -4, -6, 29, 3, H)
	m.sym(-6, 21, 0, -6, 25, 3, H)
	m.box(-5, 21, 4, 4, 29, 4, H)
	# 刘海、齿状发梢、两鬓
	m.box(-5, 28, -5, 4, 29, -5, H)
	m.sym(-4, 27, -5, -3, 27, -5, H)
	m.put(-1, 27, -5, H)
	m.sym(-5, 22, -5, -5, 27, -5, H)
	m.paint(-3, 29, -5, 0, 29, -5, H2)
	m.paint(-3, 30, -4, 0, 30, -4, H2)
	# 五官：2x2 的眼（上深下带虹膜）、腮红、小嘴
	m.sym(-3, 25, -4, -2, 25, -4, E)
	m.sym(-3, 24, -4, -3, 24, -4, E)
	m.sym(-2, 24, -4, -2, 24, -4, EI)
	m.sym(-4, 23, -4, -4, 23, -4, S2)
	m.box(-1, 22, -4, 0, 22, -4, M)
	# 发冠 + 发髻
	m.box(-2, 31, -2, 1, 31, 1, G)
	m.box(-2, 32, -2, 1, 33, 1, H)
	m.box(-1, 34, -1, 0, 34, 0, H)
	# 披在背后的长发
	m.box(-4, 17, 4, 3, 20, 4, H)
	m.box(-3, 15, 4, 2, 16, 4, H)
	m.box(-2, 14, 4, 1, 14, 4, H)
	return m


## 斗笠：一圈圈收小的圆台，帽檐压低到眉上，帽顶一个小尖
func _hat_model() -> VoxelModel:
	var m := VoxelModel.new()
	var straw := Color(0.74, 0.62, 0.4)
	var straw2 := Color(0.6, 0.48, 0.3)
	var band := Color(0.5, 0.13, 0.13)
	var tiers := [[29, 8.2, straw2], [30, 7.4, straw], [31, 6.2, straw], [32, 5.2, band], [33, 4.2, straw],
			[34, 3.0, straw], [35, 1.8, straw2]]
	for tr: Array in tiers:
		var y: int = tr[0]
		var r: float = tr[1]
		var ri := int(ceil(r))
		for x in range(-ri, ri):
			for z in range(-ri, ri):
				var dx := float(x) + 0.5
				var dz := float(z) + 0.5
				if dx * dx + dz * dz <= r * r:
					m.put(x, y, z, tr[2])
	return m


## 发带：从发冠后沿搭过后脑，垂到背后
func _ribbon_model(x: int, y_end: int) -> VoxelModel:
	var m := VoxelModel.new()
	m.box(x, 31, 2, x, 31, 3, T)
	m.put(x, 30, 4, T)
	m.box(x, y_end + 2, 5, x, 29, 5, T)
	m.box(x, y_end, 5, x, y_end + 1, 5, T2)
	return m


# ---------- 动作 ----------

## phase: 步态相位；move: 0~1 地面移动强度；airborne: 跳起/下落；floating: 御剑或凌空
func animate(dt: float, phase: float, move: float, airborne: bool, floating: bool) -> void:
	_t += dt
	var k := 1.0 - exp(-12.0 * dt)
	_move = lerpf(_move, move, k)
	_air = lerpf(_air, 1.0 if airborne else 0.0, k)
	_ride = lerpf(_ride, 1.0 if floating else 0.0, k)
	var sw := sin(phase) * _move * (1.0 - _air) * (1.0 - _ride)
	var breath := sin(_t * 1.8)

	leg_l.rotation.x = sw * 0.55 + _air * 0.4 + _ride * 0.12
	leg_r.rotation.x = -sw * 0.55 - _air * 0.25 - _ride * 0.12
	arm_l.rotation.x = -sw * 0.5 + _air * 0.2 - _ride * 0.4
	arm_r.rotation.x = sw * 0.5 + _air * 0.2 - _ride * 0.4
	var spread := 0.07 + breath * 0.012 + _air * 0.45 + _ride * 0.1
	arm_l.rotation.z = -spread
	arm_r.rotation.z = spread

	upper.position.y = WAIST.y * U + breath * 0.004
	upper.rotation.y = sw * 0.08
	head.rotation.y = -sw * 0.06
	head.rotation.x = -_air * 0.1 - _ride * 0.06
	skirt.rotation.x = cos(phase * 2.0) * 0.03 * _move

	var stream := clampf(_move * 0.5 + _ride * 0.9 + _air * 0.4, 0.0, 1.1)
	for i in ribbons.size():
		var r := ribbons[i]
		r.rotation.x = -(0.04 + stream * 0.9) + sin(_t * (5.0 + i * 1.3) + i * 2.0) * (0.03 + 0.1 * stream)
		r.rotation.z = sin(_t * 3.1 + i * 1.7) * 0.05 * (0.3 + stream)
