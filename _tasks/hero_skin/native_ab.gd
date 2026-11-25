extends SceneTree
## 原生动画开 / 关对照（无窗口、不吃输入、结果确定）：同一套动作序列跑两遍 —— 一遍地面移动用模型自带动画，一遍关掉 ——
## 逐帧记下十五个关节的全局变换和 fighter_rig 给出的手 / 剑尖 / 左手 / 双脚位置（招式、命中点、兵器挂点读的就是这些），两遍必须一模一样；
## 同时记模型手臂骨骼的姿势，两遍应该不一样（证明原生动画确实在起作用）。
## 用法：Godot --headless --path . -s res://_tasks/hero_skin/native_ab.gd

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")


func _initialize() -> void:
	_run.call_deferred()


func _record(native: bool) -> Array:
	HeroSkin.native_on = native
	var holder := Node3D.new()
	root.add_child(holder)
	var h: VoxelHero = VoxelHero.new({}, true, false, 1, HeroSkin.PLAYER_SKIN)
	holder.add_child(h)
	var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
	var rig := Rig.new(h, sword, 1.0, -0.375, 0.72)
	var joints: Array = [h.lower, h.upper, h.head, h.arm_l, h.arm_r, h.fore_l, h.fore_r, h.hand_l, h.hand_r,
			h.leg_l, h.leg_r, h.shin_l, h.shin_r, h.foot_l, h.foot_r]
	var sk := h.skin.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var arm_bone := sk.find_bone("Bip01 L UpperArm")
	var log: Array = []
	var bones: Array = []
	var weights: Array = []
	var phase := 0.0
	var dt := 1.0 / 60.0
	for f in 300:
		var move := 1.0
		var air := false
		var fly := false
		if f >= 80 and f < 120:
			move = 0.0                     # 站着
		elif f >= 120 and f < 160:
			rig.w_up_target = 1.0          # 持剑戒备着跑（上身招式）
			if f == 120:
				rig.snap(Poses.get_pose("stance"))
		elif f >= 160 and f < 200:
			if f == 160:
				rig.play("a1")              # 一整招（上身 + 腿都交给招式）
			rig.w_up_target = 1.0
			rig.w_leg_target = 1.0
			move = 0.0
		elif f >= 200 and f < 240:
			rig.w_up_target = 0.0
			rig.w_leg_target = 0.0
			air = true                     # 腾空
			move = 0.0
		elif f >= 240 and f < 270:
			fly = true                     # 御空
			move = 0.0
		phase += dt * 7.0 * move * 1.6
		h.animate(dt, phase, move, air, fly)
		rig.update(dt)
		rig.apply(dt)
		await process_frame
		var row: Array = []
		for j: Node3D in joints:
			row.append(j.global_transform)
		row.append_array([rig.hand_pos(), rig.tip_pos(), rig.left_hand_pos(), rig.foot_pos(true), rig.foot_pos(false)])
		log.append(row)
		bones.append(sk.get_bone_pose_rotation(arm_bone))
		weights.append([float(h.skin.get("_w_up")), float(h.skin.get("_w_leg"))])
	holder.queue_free()
	await process_frame
	return [log, bones, weights]


func _run() -> void:
	var a: Array = await _record(true)
	var b: Array = await _record(false)
	var same := 0
	var diff := 0
	var first_bad := -1
	for f in (a[0] as Array).size():
		var ra: Array = a[0][f]
		var rb: Array = b[0][f]
		var ok := true
		for i in ra.size():
			if ra[i] != rb[i]:
				ok = false
		if ok:
			same += 1
		else:
			diff += 1
			if first_bad < 0:
				first_bad = f
	var bone_diff := 0
	for f in (a[1] as Array).size():
		if not (a[1][f] as Quaternion).is_equal_approx(b[1][f] as Quaternion):
			bone_diff += 1
	print("[ab] 关节和手 / 剑尖 / 脚的位置：%d 帧里 %d 帧完全一致、%d 帧不同%s" % [same + diff, same, diff,
			"" if diff == 0 else "（第一处在第 %d 帧）" % first_bad])
	print("[ab] 模型手臂骨骼的姿势：%d 帧不同（原生动画起作用的帧；应 > 0）" % bone_diff)
	for f: int in [40, 100, 140, 180, 220, 255, 290]:
		print("[ab]   第 %3d 帧 原生份额 上身 %.2f 腿 %.2f（关掉的那遍 %.2f / %.2f）" % [f, float(a[2][f][0]), float(a[2][f][1]), float(b[2][f][0]), float(b[2][f][1])])
	print("[ab] 结论：", "通过" if diff == 0 and bone_diff > 0 else "不通过")
	HeroSkin.native_on = true
	quit()
