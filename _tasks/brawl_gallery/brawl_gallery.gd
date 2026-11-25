extends RefCounted
## 拳劲对拼各境界、各阶段的实机截图（2026-11-21，只截图、不改玩法）。
## 跑法：`-- --duel-shot --spark --spark-feat --brawl-gallery [--touch]`（借 fight_feat_selftest.gd 的入口分流过来），建议配 `--fixed-fps 30`
## （截图存盘那一帧很长；固定步长时游戏时间每帧只走 1/30 秒，各阶段不会被长帧跳过去）。
## 每个境界：主角和陪练（陪练的境界跟主角走）摆在同一处、同一个机位，同一个随机种子，直接开一场拳劲对拼（每秒连点 9 下，主角赢），按实际机制截六张：
##   1 起手撞拳   开打后 0.15 秒：慢放、冲击波 + 金铁火花 + 空间波动；元婴起第一道大裂缝；镜头 0.28 秒混到侧面机位
##   2 连续互殴   开打 0.8 秒后、不在换位途中：每 0.085 秒一拳，每三拳一圈波动；元婴起每 6 / 4 / 3 / 3 / 2 拳裂一道小缝（有裂缝的境界等新裂的那一道出来再截）
##   3 换位冲刺   两人裹在一起冲到下一处的半路（残影 + 两道连线）
##   4 换位对撞   冲到位撞在一起的下一帧：火花、冲击波、空间波动；元婴起大裂缝，炼虚起撕开竖缝，画面碎一下（档位越高越狠）
##   5 分胜负     对拼结束的下一帧：赢的一方一记重手把对面打飞，最大的一圈波动；元婴起最大的裂缝，合体起裂隙往里一塌
##   6 分开       分胜负 0.45 秒后：对面被打飞出去，镜头从侧面机位混回跟随
## 炼气 / 筑基正式游玩里没有空战、触发不到拳劲对拼：这里用测试手段强行把人放到空中开打，只作对照，文件名和日志都标「强制」。
## 原图（PNG）存 _shots/brawl_gallery/<desktop|mobile>/，日志行以 [bgal] 开头，总览由同目录的 make_sheets.py 拼。

const Combat := preload("res://scripts/combat.gd")
const AirFoe := preload("res://scripts/air_foe.gd")

const STAGES := ["起手撞拳", "连续互殴", "换位冲刺", "换位对撞", "分胜负", "分开"]
const SPOT := Vector3(0.0, 12.0, -6.0)     # 陪练站的地方（主角在它 +Z 方向 2.8 米）


static func _grab(main: Node, dir: String, name: String) -> void:
	Combat.hold = true
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + name + ".png")
	Combat.hold = false


static func run(main: Node) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var rival: AirFoe = main.rival
	var tier := "mobile" if OS.get_cmdline_user_args().has("--touch") else "desktop"
	var dir := ProjectSettings.globalize_path("res://_shots/brawl_gallery/" + tier)
	DirAccess.make_dir_recursive_absolute(dir)
	# 魔修、陪练木人挪到远处并把「家」也设在那儿（只挪位置的话它们会飘回原处，挡在镜头前）
	main.foe.ai_enabled = false
	main.foe.demo_reset(SPOT + Vector3(90.0, 0.0, -90.0))
	main.sandbag.ai_enabled = false
	main.sandbag.demo_reset(SPOT + Vector3(-90.0, 0.0, -90.0))
	var vs := main.get_viewport().get_visible_rect().size
	print("[bgal] 开始 %s 画面 %dx%d 渲染 %s" % [tier, int(vs.x), int(vs.y), RenderingServer.get_current_rendering_method()])
	for r in Realm.count():
		await _one(main, r, dir)
	print("[bgal] 完")


static func _one(main: Node, r: int, dir: String) -> void:
	var player: Player = main.player
	var cam: CameraRig = main.cam
	var air := player.air
	var rival: AirFoe = main.rival
	var tree: SceneTree = main.get_tree()
	# 先落地、换境界，再上天（炼气 / 筑基 take_air 不让上：直接把状态切成空战，只作对照）
	player.force_ground()
	player.global_position = Vector3(0.0, 0.1, 0.0)
	player.set_realm(r, false)
	await main._wait(0.3)
	var forced := false
	if not player.take_air():
		# 先挪到半空再切状态（站在地上切过去，下一帧就被判落地了）
		forced = true
		player.global_position = SPOT + Vector3(0.0, 0.0, 2.8)
		player.velocity = Vector3.ZERO
		player.st = Player.St.AIR
		player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	await main._wait(0.9)
	player.melee.hp = 100.0
	player.mp = player.mp_max()
	rival.hp_max = 99999.0
	rival.demo_reset(SPOT)
	rival.ai_enabled = true
	rival._cd = 99.0
	rival._vanish_cd = 99.0
	rival._volley_cd = 99.0
	rival._shoot_cd = 99.0
	rival._dash_cd = 99.0
	rival.no_react = true
	main._spark_setup(rival, 2.8, 8.0)
	cam.lock_turn = true
	air._brawl_cd = 0.0
	await main._wait(0.8)
	var rn: String = player.realm["name"]
	var tag := "%02d_%s%s" % [r + 1, rn, "（强制）" if forced else ""]
	var ct := clampi(maxi(player.realm_idx, rival.tier_realm()) - 2, 0, 5)
	print("[bgal] %s 境界 %d「%s」%s 裂缝档位 %d（陪练跟着主角的境界：%d）" % [tag, r, rn, "正式游玩触发不到、测试强制进入空战" if forced else "", ct, rival.tier_realm()])
	seed(20261121)
	var c0 := Vfx.crack_n
	air.demo_mash = 9.0
	air.call("_start_brawl", rival)
	var done := {}
	var prev_mv := -1.0
	var prev_cn := Vfx.crack_n
	var end_at := -1.0
	var tt := 0.0
	while tt < 8.0 and done.size() < STAGES.size():
		await tree.process_frame
		tt += main.get_process_delta_time()
		var bt: float = air.get("_brawl_t")
		var mv: float = air.get("_brawl_mv")
		var live := air.in_brawl()
		var cn := Vfx.crack_n
		var want := -1
		if live:
			if not done.has(0) and bt >= 0.15:
				want = 0
			elif done.has(0) and not done.has(1) and bt >= 0.8 and mv < 0.0 and (ct == 0 or cn > prev_cn):
				want = 1
			elif done.has(1) and not done.has(2) and mv >= 0.04 and mv <= 0.09:
				want = 2
			elif done.has(2) and not done.has(3) and prev_mv >= 0.0 and mv < 0.0:
				want = 3
		elif end_at < 0.0:
			end_at = tt
			if not done.has(4):
				want = 4
		elif not done.has(5) and tt - end_at >= 0.45:
			want = 5
		prev_mv = mv
		prev_cn = cn
		if want < 0:
			continue
		done[want] = true
		var name := "%s_%d_%s" % [tag, want + 1, STAGES[want]]
		await _grab(main, dir, name)
		print("[bgal]   %d %s：对拼 %.2fs 已裂 %d 道 镜头接管 %.2f 慢放 %.2f 优势条 %.2f 对拼中=%s → %s.png" % [want + 1, STAGES[want], bt,
				Vfx.crack_n - c0, cam.cine_k, Engine.time_scale, air.brawl_u(), live, name])
	air.demo_mash = 0.0
	var miss: Array = []
	for i in STAGES.size():
		if not done.has(i):
			miss.append(STAGES[i])
	print("[bgal] %s 结束：这一场裂了 %d 道；没截到的阶段 %s" % [tag, Vfx.crack_n - c0, miss])
	rival.ai_enabled = false
	rival.no_react = false
	await main._wait(1.2)
