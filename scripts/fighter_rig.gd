extends RefCounted
## 近战姿势驱动：把 combat_poses.gd 的关键帧时间轴插值后叠加到 VoxelHero 上，并管理手中兵器。
## 与原有走路动画混合：w_up 控制上身/双臂/兵器，w_leg 控制双腿/重心。
## 战斗中边走边戒备 = 腿用走路动画 + 上身用战斗姿势；出招时两者都交给关键帧。

const Poses := preload("res://scripts/combat_poses.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")

const LEG := VoxelHero.LEG              # 髋到脚底（方块人的；下面几个同）
const THIGH := VoxelHero.THIGH
const SHANK := VoxelHero.SHANK
const SHOULDER := VoxelHero.SHOULDER    # 右肩（角色本地系，站直时）
const REACH := VoxelHero.ARM            # 肩到掌心

var hero: VoxelHero
## 这副骨架自己的尺寸：方块人 = 上面的常量；主角换了皮肤模型（hero_skin.gd）后是模型的比例，从 hero 上读
var leg := LEG
var thigh := THIGH
var shank := SHANK
var shoulder := SHOULDER
var reach := REACH
var palm := VoxelHero.PALM
var holder: Node3D   # 手心挂点（右臂子节点），兵器挂在它下面
var weapon: Node3D
var tip_len := 0.9   # 手心到刃尖
var cur: Dictionary
var last_name := ""   # 最近一次 play 的动作名和次数：联机时发给别人，别人那边的木偶照着播
var play_n := 0
var w_up := 0.0
var w_leg := 0.0
var w_up_target := 0.0
var w_leg_target := 0.0
## 2026-11-24 英雄系统：通用姿势名 → 这位英雄自己的（hero_defs.gd 的 pose_map；空 = 不换）。联机发出去的是换过之后的名字
var remap: Dictionary = {}

var _keys: Array = []
var _t := 0.0


## grip: 兵器模型里握把中心的本地 y；tip: 兵器模型里刃尖的本地 y（都是缩放前）
func _init(h: VoxelHero, weapon_node: Node3D, weapon_scale: float, grip: float, tip: float) -> void:
	hero = h
	leg = h.leg_len
	thigh = h.thigh_len
	shank = h.shank_len
	shoulder = h.shoulder
	reach = h.arm_len
	palm = h.palm
	holder = Node3D.new()
	holder.position = palm
	hero.hand_r.add_child(holder)
	weapon = weapon_node
	weapon.scale = Vector3.ONE * weapon_scale
	weapon.position = Vector3(0.0, -grip * weapon_scale, 0.0)
	holder.add_child(weapon)
	tip_len = (tip - grip) * weapon_scale
	cur = Poses.get_pose("stance")
	_keys = [[0.0, cur, 0]]


## 2026-11-24 英雄系统：身上换了皮肤模型（VoxelHero.set_skin）之后，四肢尺寸、掌心挂点按新模型重读
func refit() -> void:
	leg = hero.leg_len
	thigh = hero.thigh_len
	shank = hero.shank_len
	shoulder = hero.shoulder
	reach = hero.arm_len
	palm = hero.palm
	holder.position = palm


## 2026-11-24 英雄系统：换手里的兵器（联机木偶知道了对方是持剑的英雄）。参数同 _init
func set_weapon(weapon_node: Node3D, weapon_scale: float, grip: float, tip: float) -> void:
	if weapon != null and is_instance_valid(weapon) and weapon != weapon_node:
		holder.remove_child(weapon)
		weapon.queue_free()
	weapon = weapon_node
	weapon.scale = Vector3.ONE * weapon_scale
	weapon.position = Vector3(0.0, -grip * weapon_scale, 0.0)
	if weapon.get_parent() == null:
		holder.add_child(weapon)
	tip_len = (tip - grip) * weapon_scale


func play(name: String, speed := 1.0) -> void:
	if remap.has(name):
		name = str(remap[name])      # 英雄自己的姿势（持剑的英雄：空战待机 / 护体 / 蓄力换成拿着剑的那套）
	last_name = name
	play_n += 1
	var keys: Array = []
	for k: Array in Poses.seq(name):
		keys.append([float(k[0]) / speed, k[1], k[2]])
	play_keys(keys)


func play_keys(keys: Array) -> void:
	# 整身自转（by / bp）可能停在整圈上：折回 ±π 内，下一招不会倒着转回去
	cur = cur.duplicate()
	cur["by"] = wrapf(float(cur["by"]), -PI, PI)
	cur["bp"] = wrapf(float(cur["bp"]), -PI, PI)
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

	# 屈肘：前臂绕肘向前收
	hero.fore_r.rotation.x = lerpf(hero.fore_r.rotation.x, float(p["er"]), u)
	hero.fore_l.rotation.x = lerpf(hero.fore_l.rotation.x, float(p["el"]), u)

	var ll: float = p["ll"]
	var lr: float = p["lr"]
	var lz: float = p["lz"]
	hero.leg_l.rotation.x = lerpf(hero.leg_l.rotation.x, ll, lg)
	hero.leg_r.rotation.x = lerpf(hero.leg_r.rotation.x, lr, lg)
	hero.leg_l.rotation.z = -lz * lg
	hero.leg_r.rotation.z = lz * lg
	# 两腿张开时髋部随之下沉：摆得更开的那条腿伸直踩地，另一条腿屈膝把脚也落到地面（一维 IK）；
	# ak = 0 的姿势（空战）直接用给定的屈膝 kl / kr
	var amax := maxf(absf(ll), absf(lr))
	var drop := leg * (1.0 - cos(amax)) + leg * (1.0 - cos(lz))
	var ak: float = p["ak"]
	var kl := lerpf(float(p["kl"]), _knee(ll, leg * cos(amax)), ak)
	var kr := lerpf(float(p["kr"]), _knee(lr, leg * cos(amax)), ak)
	hero.shin_l.rotation.x = lerpf(hero.shin_l.rotation.x, -kl, lg)
	hero.shin_r.rotation.x = lerpf(hero.shin_r.rotation.x, -kr, lg)
	hero.foot_l.rotation.x = lerpf(hero.foot_l.rotation.x, (kl - ll) * ak - float(p["ft"]), lg)
	hero.foot_r.rotation.x = lerpf(hero.foot_r.rotation.x, (kr - lr) * ak - float(p["ft"]), lg)
	hero.position = Vector3(0.0, (float(p["hop"]) - drop * ak) * lg, 0.0)
	hero.skirt.rotation.y = float(p["tw"]) * 0.3 * lg

	holder.global_basis = hero.global_basis * Basis(p["bl"] as Quaternion)


## 大腿前摆 a 时，要让脚底落在髋下 h 处需要屈膝多少（够不着就伸直）
func _knee(a: float, h: float) -> float:
	var c := (h - thigh * cos(a)) / shank
	if c >= 1.0:
		return 0.0
	var q := acos(clampf(c, -1.0, 1.0))
	var k := a - q
	return k if k >= 0.0 else a + q


## 左手掌心（空战出拳的命中点）
func left_hand_pos() -> Vector3:
	return hero.hand_l.global_transform * palm


func foot_pos(right: bool) -> Vector3:
	var f := hero.foot_r if right else hero.foot_l
	return f.global_transform * Vector3(0.0, -0.1, -0.1)


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
	var ad := hand - shoulder
	if ad.length() > reach:
		hand = shoulder + ad.normalized() * reach
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
