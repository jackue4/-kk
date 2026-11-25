extends SceneTree
## W_maps 的离线小检查：两张图烘表 / 摆件的耗时、静态实心盒子数、每块的静态几何顶点数、几个点的高度
const GW := preload("res://scripts/ex/grid_world.gd")
const MapDef := preload("res://scripts/ex/map_def.gd")

func _init() -> void:
	for id: String in ["desert", "lab"]:
		var w: Node3D = GW.new()
		w.setup(id)
		var m: Dictionary = MapDef.map(id)
		var maxv := 0
		var tot := 0
		var maxk := Vector2i.ZERO
		for k: Vector2i in w._sgeo:
			var n: int = (w._sgeo[k][0] as PackedVector3Array).size()
			tot += n
			if n > maxv:
				maxv = n
				maxk = k
		var roofv := 0
		for r: Dictionary in w._roofs:
			roofv += ((r["geo"] as Array)[0] as PackedVector3Array).size()
		print("[gw] %s gen %.0f ms static_boxes %d chunks_with_geo %d static_verts %d max_chunk %d at %s roofs %d roof_verts %d doors %d lights %d" % [
			id, w.gen_ms, w.static_boxes, w._sgeo.size(), tot, maxv, maxk, w._roofs.size(), roofv, w._doors.size(), w._lmap.size()])
		print("[gw] %s spawns %d extracts %d boxes %d camps %d keyrooms %d bosses %d links %d" % [id, m["spawns"].size(), m["extracts"].size(), m["boxes"].size(), m["camps"].size(), m["key_rooms"].size(), m["bosses"].size(), m["links"].size()])
		for s: Dictionary in m["spawns"]:
			var p: Vector3 = s["pos"]
			print("  spawn %s %s h=%.1f" % [s["id"], p, w.height(p.x, p.z)])
		for l: Dictionary in m["links"]:
			var a: Vector3 = l["a"]
			var b: Vector3 = l["b"]
			print("  link %s a=%s h=%.1f  b=%s h=%.1f ceil=%.1f" % [l["id"], a, w.height(a.x, a.z), b, w.height(b.x, b.z), w.ceil_at(b.x, b.z)])
		var t0 := Time.get_ticks_usec()
		var acc := 0.0
		for i in 20000:
			acc += w.height(float(i % 700) - 350.0, float(i / 700) * 3.0 - 300.0)
		print("  height() %.2f us" % (float(Time.get_ticks_usec() - t0) / 20000.0))
		t0 = Time.get_ticks_usec()
		var bm: Dictionary = w.bake_map("surface", 3.0)
		print("  bake surface %.0f ms size %d" % [float(Time.get_ticks_usec() - t0) / 1000.0, (bm["img"] as Image).get_width()])
		t0 = Time.get_ticks_usec()
		var r0: Dictionary = await w._build(Vector2i(0, 0), 0)
		print("  build lod0 (0,0) %.0f ms verts %d" % [float(Time.get_ticks_usec() - t0) / 1000.0, (r0["v"] as PackedVector3Array).size()])
		w.free()
	quit()
