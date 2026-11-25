extends "res://scripts/xiu_map_selftest.gd"
## T_maps 诊断（不进包）：洞窟 c32 的怪怎么跑进岩体里的（逐帧看 y / 状态 / 位置）

func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	if not await enter(3):
		get_tree().quit(1)
		return
	keep = true
	for b: Dictionary in mgr.get("_bosses"):
		b["state"] = 2
		b["back"] = 1.0e9
	var world: Node = level.get("world")
	var camps: Variant = mgr.get("camps")
	for id: int in camps._list_ids:
		var c: Dictionary = camps._cache[id]
		if str(c["name"]) != "c32":
			continue
		say("c32 base %s y %.1f offs %s" % [str(c["base"]), float(c["y"]), str(c["offs"])])
		var b2: Vector2 = c["base"]
		await put(level.call("find_spawn_near", Vector3(b2.x, float(c["y"]), b2.y), 42.0, 70.0, null))
		var seen := {}
		var t := 0.0
		while t < 10.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			for mb: Node3D in _camp_mobs(id):
				var k := mb.get_instance_id()
				var p := mb.global_position
				if not seen.has(k):
					seen[k] = p
					say("t %.2f 建 %s pos %s 地形 %.1f 洞顶 %.1f" % [t, str(mb.get("display_name")), str(p.snapped(Vector3.ONE * 0.01)),
							float(world.call("height", p.x, p.z)), float(world.call("ceil_at", p.x, p.z))])
				elif absf(p.y - (seen[k] as Vector3).y) > 1.0:
					say("t %.2f 跳 %s %s → %s 状态 %d 地形 %.1f 洞顶 %.1f" % [t, str(mb.get("display_name")), str((seen[k] as Vector3).snapped(Vector3.ONE * 0.01)),
							str(p.snapped(Vector3.ONE * 0.01)), int(mb.get("state")), float(world.call("height", p.x, p.z)), float(world.call("ceil_at", p.x, p.z))])
					seen[k] = p
	get_tree().quit(0)
