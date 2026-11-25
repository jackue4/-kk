extends "res://scripts/xiu_map_selftest.gd"
## T_maps 诊断（不进包）：点表里哪些点落在岩体里 / 实心里（地面 ≥ 洞顶 - 2，或脚下 0.1 米是实心盒子），以及新图所有搜点

func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	if not await enter(3):
		get_tree().quit(1)
		return
	var world: Node = level.get("world")
	var bad := 0
	for kind: String in ["spawn", "extract", "camp", "box"]:
		var i := 0
		for e: Dictionary in level.call("points", kind):
			var p: Vector3 = e["pos"]
			var ce := float(world.call("ceil_at", p.x, p.z))
			var emb := bool(world.call("solid_box_at", p + Vector3(0, 0.1, 0)))
			if p.y > ce - 2.0 or emb:
				bad += 1
				say("点 %s#%d(%s) %s 层 %s 洞顶 %.1f 地形 %.1f 盒子 %s" % [kind, i, str(e.get("id", "")), str(p), str(e.get("layer", "")), ce,
						float(world.call("height", p.x, p.z)), str(emb)])
			i += 1
	for e2: Dictionary in level.call("points", "boss"):
		var bp: Vector3 = e2["pos"]
		var ce2 := float(world.call("ceil_at", bp.x, bp.z))
		var fl := float(level.call("floor_at", bp.x, bp.z, bp.y + 0.5))
		if fl > ce2 - 2.0 or absf(fl - bp.y) > 1.0:
			bad += 1
			say("首领点 %s %s 地面 %.1f 洞顶 %.1f" % [str(e2["id"]), str(bp), fl, ce2])
	for s: Dictionary in (mgr.get("search") as Node).get("sites"):
		var sp: Vector3 = s["pos"]
		var ce3 := float(world.call("ceil_at", sp.x, sp.z))
		if sp.y > ce3 - 2.0 or bool(world.call("solid_box_at", sp + Vector3(0, 0.1, 0))):
			bad += 1
			say("搜点 %s#%d %s 洞顶 %.1f" % [str(s["kind"]), int(s["id"]), str(sp), ce3])
	say("总计 在岩体 / 实心里的点 %d 个" % bad)
	get_tree().quit(0)
