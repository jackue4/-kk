extends SceneTree
## 语法 / 类型自检：把这次改到的脚本挨个载入一遍（警告当错误的工程里，载不进来就是有错）。
## 用法：Godot --headless --path . -s res://_tasks/tsb/check_load.gd [-- 额外脚本路径 ...]
func _init() -> void:
	var bad := 0
	var list: Array = ["combat_poses", "hero_defs", "hero_fx", "kit_base", "air_moves", "air_melee", "player", "remote_player", "ally_puppet",
		"net", "touch_controls", "hud", "heroes/poses_zhenyue", "heroes/poses_canghong", "heroes/poses_shuanghua",
		"heroes/def_zhenyue", "heroes/def_canghong", "heroes/def_shuanghua", "heroes/kit_zhenyue", "heroes/kit_canghong2", "heroes/cg_mark_view", "heroes/kit_shuanghua",
		"kit_canghong", "ex/hero_doll", "ex/hero_select_ui", "ex/ex_hud", "main", "air_foe", "destruct", "destruct_fx"]
	for a: String in OS.get_cmdline_user_args():
		list.append(a)
	for f: String in list:
		var p := "res://scripts/%s.gd" % f
		if not FileAccess.file_exists(p):
			print("[check] 没有 ", p)
			continue
		var s: Variant = load(p)
		var ok: bool = s != null and (s as GDScript).can_instantiate()
		print("[check] ", f, " ", "ok" if ok else "FAILED")
		if not ok:
			bad += 1
	# 姿势包：每条时间轴用到的姿势都得有
	var poses: GDScript = load("res://scripts/combat_poses.gd")
	if poses != null:
		for pk: Variant in poses.get("PACKS"):
			for sn: String in (pk.SEQ as Dictionary).keys():
				for k: Array in pk.SEQ[sn]:
					if not bool(poses.call("has_def", str(k[1]))):
						print("[check] 时间轴 ", sn, " 用了不存在的姿势 ", k[1])
						bad += 1
	# 英雄表：招式的 seq / next 都得存在
	var hd: GDScript = load("res://scripts/hero_defs.gd")
	var mv: GDScript = load("res://scripts/air_moves.gd")
	if hd != null and poses != null and mv != null:
		for id: String in hd.call("ids"):
			var d: Dictionary = hd.call("def_of", id)
			var moves: Dictionary = d.get("moves", {})
			var base: Dictionary = mv.get("MOVES")
			for m: String in moves.keys():
				var a: Dictionary = moves[m]
				if not bool(poses.call("has_seq", str(a["seq"]))):
					print("[check] ", id, " 招式 ", m, " 的时间轴不存在：", a["seq"])
					bad += 1
				var nx := str(a.get("next", ""))
				if nx != "" and not moves.has(nx) and not base.has(nx):
					print("[check] ", id, " 招式 ", m, " 的 next 不存在：", nx)
					bad += 1
			for m2: String in (d.get("chain", []) as Array) + (d.get("chain_awake", []) as Array):
				if not moves.has(m2) and not base.has(m2):
					print("[check] ", id, " 连段表里的招式不存在：", m2)
					bad += 1
			print("[check] 英雄 ", id, " ", d.get("name", "?"), "：招式 ", moves.size(), " 个，M1 ", hd.call("m1_units", id, false), " 单位")
	print("[check] bad=", bad)
	quit(1 if bad > 0 else 0)
