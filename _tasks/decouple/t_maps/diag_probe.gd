extends "res://scripts/xiu_map_selftest.gd"
## T_maps 诊断（不进包）：刷怪点的怪 / 搜点「在实心里」具体是哪种实心

func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	if not await enter(3):
		get_tree().quit(1)
		return
	keep = true
	var world: Node = level.get("world")
	var search: Node = mgr.get("search")
	for s: Dictionary in search.get("sites"):
		var sp: Vector3 = s["pos"]
		var col := ""
		for k in 9:
			var y := sp.y + 0.1 + 0.2 * k
			col += "1" if bool(world.call("solid_box_at", Vector3(sp.x, y, sp.z))) else "0"
		var fl := float(level.call("floor_at", sp.x, sp.z, sp.y + 0.5))
		if col.contains("1") or absf(fl - sp.y) > 0.6:
			say("搜点 %s#%d pos %s 地形 %.2f 洞顶 %.1f floor(y+0.5) %.2f floor(INF) %.2f 盒子(+0.1..+1.7) %s" % [str(s["kind"]), int(s["id"]), str(sp),
					float(world.call("height", sp.x, sp.z)), float(world.call("ceil_at", sp.x, sp.z)), fl, float(level.call("floor_at", sp.x, sp.z)), col])
	var camps: Variant = mgr.get("camps")
	for id: int in camps._list_ids:
		var c: Dictionary = camps._cache[id]
		if not (str(c["name"]) in ["c10", "c19", "c32"]):
			continue
		var b: Vector2 = c["base"]
		await put(level.call("find_spawn_near", Vector3(b.x, float(c["y"]), b.y), 42.0, 70.0, null))
		var tw := 0.0
		while _camp_mobs(id).size() < (c["defs"] as Array).size() and tw < 6.0:
			await wait(0.2)
			tw += 0.2
		await wait(1.0)
		for mb: Node3D in _camp_mobs(id):
			var p := mb.global_position
			var col2 := ""
			for k in 9:
				col2 += "1" if bool(world.call("solid_box_at", Vector3(p.x, p.y + 0.1 + 0.2 * k, p.z))) else "0"
			say("怪 %s/%s pos %s 地形 %.2f 洞顶 %.1f floor(y+0.5) %.2f floor(点y) %.2f 点y %.1f 盒子 %s" % [str(c["name"]), str(mb.get("display_name")), str(p.snapped(Vector3.ONE * 0.01)),
					float(world.call("height", p.x, p.z)), float(world.call("ceil_at", p.x, p.z)), float(level.call("floor_at", p.x, p.z, p.y + 0.5)),
					float(level.call("floor_at", p.x, p.z, float(c["y"]) + 0.5)), float(c["y"]), col2])
	get_tree().quit(0)
