extends SceneTree
## 天南秘境（实验）的生成自检：不经主程序，直接建关卡节点（没有主角 / 镜头），多个种子各拼一局，
## 查主路相邻房间通不通、支线从起点到不到得了，前几局的俯视全图存到 _tasks/mijing_lab/。
## 用法：Godot --headless --path . -s res://_tasks/mijing_lab/gen_test.gd [-- 局数]

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var scr: GDScript = load("res://scripts/lab/mijing_level.gd")
	var n := 12
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and ua[0].is_valid_int():
		n = int(ua[0])
	var bad := 0
	for sd in range(1, n + 1):
		var lv: Node = scr.new()
		lv.set("seed_n", sd * 101)
		lv.set("no_mobs", true)
		root.add_child(lv)
		await process_frame
		var rooms: Array = lv.get("rooms")
		var mains: Array = []
		for rm: Dictionary in rooms:
			if int(rm["main"]) >= 0:
				mains.append(rm)
		mains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["main"]) < int(b["main"]))
		var ok := 0
		for i in range(1, mains.size()):
			if bool(lv.call("reachable", (mains[i - 1] as Dictionary)["cen"], (mains[i] as Dictionary)["cen"])):
				ok += 1
			else:
				print("   不通：", (mains[i - 1] as Dictionary)["id"], " → ", (mains[i] as Dictionary)["id"])
		var side_ok := 0
		var side_n := 0
		for rm2: Dictionary in rooms:
			if int(rm2["main"]) < 0:
				side_n += 1
				if bool(lv.call("reachable", (mains[0] as Dictionary)["cen"], rm2["cen"])):
					side_ok += 1
				else:
					print("   支线到不了：", rm2["id"])
		if mains.size() < 14 or ok < mains.size() - 1 or side_ok < side_n:
			bad += 1
		print("[gen] 种子 %d：主路 %d 间，相邻通 %d / %d，支线通 %d / %d | %s" % [sd * 101, mains.size(), ok, mains.size() - 1, side_ok, side_n, str(lv.call("stats_text"))])
		if sd <= 4:
			var img: Image = lv.call("map_image", 5)
			img.save_png(ProjectSettings.globalize_path("res://_tasks/mijing_lab/map_%d.png" % (sd * 101)))
		lv.free()
	print("[gen] %d 局里有问题的 %d 局" % [n, bad])
	quit()
