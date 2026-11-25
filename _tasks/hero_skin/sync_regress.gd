extends SceneTree
## hero_skin.gd 改了摆骨骼的写法（省算 / 加皮肤）之后，主角的模型姿势变没变：同一套动作序列，两个阿拉灯同时跑 ——
## 一个用现在的 hero_skin.gd，一个用旧版脚本（文本文件，运行时编译），逐帧比整副骨骼每根的位置 / 旋转，应该完全一样。
## 无窗口、不吃输入、结果确定。动作序列同 native_ab.gd（跑 / 站 / 持剑戒备着跑 / 出招 / 腾空 / 御空 / 再跑）。
## 用法：Godot --headless --path . -s res://_tasks/hero_skin/sync_regress.gd -- --old=<旧版 hero_skin.gd 的文本文件，绝对路径>

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--old="):
			old_path = a.substr(6)
	var old_gd := GDScript.new()
	old_gd.source_code = FileAccess.get_file_as_string(old_path)
	if old_gd.source_code == "" or old_gd.reload() != OK:
		print("[regress] 读不了旧版脚本：", old_path)
		quit()
		return
	var heroes: Array = []
	for kind in 2:
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position.x = 3.0 * float(kind)
		var h: VoxelHero = VoxelHero.new({}, true, false, 1, HeroSkin.PLAYER_SKIN)
		holder.add_child(h)
		var skin: Node3D = h.skin
		if kind == 1:
			# 第二个换成旧版脚本的皮肤节点（voxel_hero 里的 skin 置空，mark() 由这里代调）
			h.remove_child(h.skin)
			h.skin.free()
			h.skin = null
			skin = old_gd.new() as Node3D
			h.add_child(skin)
			skin.call("attach", h, HeroSkin.PLAYER_SKIN)
		var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
		var rig := Rig.new(h, sword, 1.0, -0.375, 0.72)
		heroes.append([h, rig, skin, skin.find_children("*", "Skeleton3D", true, false)[0]])
	var phase := 0.0
	var dt := 1.0 / 60.0
	var worst_p := 0.0
	var worst_r := 0.0
	var bad := 0
	var nat := 0
	var frames := 330
	var per_bone := {}      # 骨骼下标 → 这根骨骼旋转的最大差（排查用）
	for f in frames:
		var move := 1.0
		var air := false
		var fly := false
		for e: Array in heroes:
			var rig: Rig = e[1]
			if f >= 80 and f < 120:
				move = 0.0
			elif f >= 120 and f < 160:
				rig.w_up_target = 1.0
				if f == 120:
					rig.snap(Poses.get_pose("stance"))
			elif f >= 160 and f < 200:
				if f == 160:
					rig.play("a1")
				rig.w_up_target = 1.0
				rig.w_leg_target = 1.0
				move = 0.0
			elif f >= 200 and f < 240:
				rig.w_up_target = 0.0
				rig.w_leg_target = 0.0
				air = true
				move = 0.0
			elif f >= 240 and f < 270:
				fly = true
				move = 0.0
		phase += dt * 7.0 * move * 1.6
		for e: Array in heroes:
			var h: VoxelHero = e[0]
			h.stream_add = 0.6 if fly else 0.0
			h.animate(dt, phase, move, air, fly)
			if h.skin == null:
				(e[2] as Node3D).call("mark")
			(e[1] as Rig).update(dt)
			(e[1] as Rig).apply(dt)
		await process_frame
		var sa: Skeleton3D = heroes[0][3]
		var sb: Skeleton3D = heroes[1][3]
		var frame_bad := false
		for b in sa.get_bone_count():
			var dp := sa.get_bone_pose_position(b).distance_to(sb.get_bone_pose_position(b))
			# 旋转按四元数分量比（q 和 -q 是同一个旋转）。别用 angle_to：两个一样的旋转求夹角，acos 在 1 附近的浮点误差会给出约 0.001 弧度的假差值
			var qa := sa.get_bone_pose_rotation(b)
			var qb := sb.get_bone_pose_rotation(b)
			if qa.dot(qb) < 0.0:
				qb = -qb
			var dr := maxf(maxf(absf(qa.x - qb.x), absf(qa.y - qb.y)), maxf(absf(qa.z - qb.z), absf(qa.w - qb.w)))
			worst_p = maxf(worst_p, dp)
			worst_r = maxf(worst_r, dr)
			if dr > float(per_bone.get(b, 0.0)):
				per_bone[b] = dr
			if dp > 1e-4 or dr > 1e-5:
				frame_bad = true
		if frame_bad:
			bad += 1
		if float((heroes[0][2] as Node3D).get("_w_up")) > 0.5:
			nat += 1
	print("[regress] %d 帧 × %d 根骨骼：姿势不同的帧 %d；位置最大差 %.6f（模型单位）、旋转（四元数分量）最大差 %.6f；其中原生动画占上身过半的帧 %d" % [frames,
			(heroes[0][3] as Skeleton3D).get_bone_count(), bad, worst_p, worst_r, nat])
	var names: Array = []
	for b: int in per_bone:
		if float(per_bone[b]) > 1e-5:
			names.append("%s %.5f" % [(heroes[0][3] as Skeleton3D).get_bone_name(b), float(per_bone[b])])
	if not names.is_empty():
		print("[regress] 旋转对不上的骨骼：", ", ".join(names))
	print("[regress] 结论：", "通过" if bad == 0 and nat > 0 else "不通过")
	quit()
