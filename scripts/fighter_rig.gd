extends RefCounted
## 近战姿势驱动：把 combat_poses.gd 的关键帧时间轴插值后叠加到 VoxelHero 上，并管理手中兵器。
## 与原有走路动画混合：w_up 控制上身/双臂/兵器，w_leg 控制双腿/重心。
## 战斗中边走边戒备 = 腿用走路动画 + 上身用战斗姿势；出招时两者都交给关键帧。

const Poses := preload("res://scripts/combat_poses.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")

const LEG := 0.45                       # 髋到脚底
const SHOULDER := Vector3(0.225, 0.95, 0.0)  # 右肩（角色本地系，站直时）

var hero: VoxelHero
var holder: Node3D   # 手心挂点（右臂子节点），兵器挂在它下面
var weapon: Node3D
var tip_len := 0.9   # 手心到刃尖
var cur: Dictionary
var w_up := 0.0
var w_leg := 0.0
var w_up_target := 0.0
var w_leg_target := 0.0

var _keys: Array = []
var _t := 0.0


## grip: 兵器模型里握把中心的本地 y；tip: 兵器模型里刃尖的本地 y（都是缩放前）
func _init(h: VoxelHero, weapon_node: Node3D, weapon_scale: float, grip: float, tip: float) -> void:
	hero = h
	holder = Node3D.new()
	holder.position = Vector3(0.025, -0.36, 0.0)
	hero.arm_r.add_child(holder)
	weapon = weapon_node
	weapon.scale = Vector3.ONE * weapon_scale
	weapon.position = Vector3(0.0, -grip * weapon_scale, 0.0)
	holder.add_child(weapon)
	tip_len = (tip - grip) * weapon_scale
	cur = Poses.get_pose("stance")
	_keys = [[0.0, cur, 0]]


func play(name: String, speed := 1.0) -> void:
	var keys: Array = []
	for k: Array in Poses.seq(name):
		keys.append([float(k[0]) / speed, k[1], k[2]])
	play_keys(keys)


func play_keys(keys: Array) -> void:
	_keys = [[0.0, cur, 0]]
	_keys.append_array(keys)
	_t = 0.0


## 立即定格到某个姿势（对刃时用：顿帧期间时间几乎不走，必须当帧就摆到位）
func snap(p: Dictionary, keys: Array = []) -> void:
	cur = p
	_keys = [[0.0, p, 0]]
	_keys.append_array(keys)
	_t = 0.0


func time() -> float:
	return _t


func update(dt: float) -> void:
	_t += dt
	var n := _keys.size()
	if _t >= float(_keys[n - 1][0]):
		cur = _keys[n - 1][1]
		return
	for i in range(1, n):
		var t1 := float(_keys[i][0])
		if _t < t1:
			var t0 := float(_keys[i - 1][0])
			var u := clampf((_t - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0)
			cur = Poses.lerp_pose(_keys[i - 1][1], _keys[i][1], _ease(u, int(_keys[i][2])))
			return


static func _ease(u: float, kind: int) -> float:
	match kind:
		1:
			return 1.0 - pow(1.0 - u, 3.0)
		2:
			return u * u * (3.0 - 2.0 * u)
		3:
			return u * u
	return u


## 在 hero.animate() 之后调用
func apply(dt: float) -> void:
	var k := 1.0 - exp(-18.0 * dt)
	w_up = lerpf(w_up, w_up_target, k)
	w_leg = lerpf(w_leg, w_leg_target, k)
	if w_up < 0.002 and w_leg < 0.002:
		hero.position = Vector3.ZERO
		return
	var p := cur
	var u := w_up
	var lg := w_leg
	var upr := Vector3(-float(p["ln"]), float(p["tw"]), float(p["tl"]))
	hero.upper.rotation = Vector3(0.0, hero.upper.rotation.y, 0.0).lerp(upr, u)
	var inv := hero.upper.basis.inverse()
	var qr := (inv * Basis(p["ar"] as Quaternion)).get_rotation_quaternion()
	var ql := (inv * Basis(p["al"] as Quaternion)).get_rotation_quaternion()
	hero.arm_r.quaternion = hero.arm_r.quaternion.slerp(qr, u)
	hero.arm_l.quaternion = hero.arm_l.quaternion.slerp(ql, u)
	# 头始终看向前方：抵消上身扭转与前倾
	hero.head.rotation.y = lerpf(hero.head.rotation.y, -float(p["tw"]) * 0.75 + float(p["hd"]), u)
	hero.head.rotation.x = lerpf(hero.head.rotation.x, float(p["ln"]) * 0.45, u)

	var ll: float = p["ll"]
	var lr: float = p["lr"]
	var lz: float = p["lz"]
	hero.leg_l.rotation.x = lerpf(hero.leg_l.rotation.x, ll, lg)
	hero.leg_r.rotation.x = lerpf(hero.leg_r.rotation.x, lr, lg)
	hero.leg_l.rotation.z = -lz * lg
	hero.leg_r.rotation.z = lz * lg
	# 两腿张开时髋部随之下沉，脚底尽量贴地
	var drop := LEG * (1.0 - cos(maxf(absf(ll), absf(lr)))) + LEG * (1.0 - cos(lz))
	hero.position = Vector3(0.0, (float(p["hop"]) - drop) * lg, 0.0)
	hero.skirt.rotation.y = float(p["tw"]) * 0.3 * lg

	holder.global_basis = hero.global_basis * Basis(p["bl"] as Quaternion)


func hand_pos() -> Vector3:
	return holder.global_position


func tip_pos() -> Vector3:
	return holder.global_transform * Vector3(0.0, tip_len, 0.0)


func blade_point(f: float) -> Vector3:
	return holder.global_transform * Vector3(0.0, tip_len * f, 0.0)


## 以 base 为底，把剑摆到能磕住世界坐标 contact 的位置（手在接触点右下方偏近，剑身斜立）
func aim_pose(base: Dictionary, contact: Vector3) -> Dictionary:
	var p := base.duplicate()
	var c := hero.global_transform.affine_inverse() * contact
	var hand := c + Vector3(0.12, -0.38, 0.24)
	var ad := hand - SHOULDER
	if ad.length() > 0.36:
		hand = SHOULDER + ad.normalized() * 0.36
	if ad.length_squared() < 1e-4:
		ad = Vector3(0.2, -0.3, -0.9)
	var ar := ad.normalized()
	var bl := c - hand
	if bl.length_squared() < 1e-4:
		bl = Vector3(-0.4, 0.8, -0.4)
	bl = bl.normalized()
	p["ar"] = Poses.arm_quat(ar, bl)
	p["bl"] = Poses.blade_quat(bl, ar)
	p["tw"] = 0.15
	return p
