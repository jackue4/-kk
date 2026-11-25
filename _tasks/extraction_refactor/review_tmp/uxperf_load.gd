extends SceneTree
## review（uxperf）：量 grid_world.setup / bake_map 的耗时和地形表大小（只读，不改工程）

func _init() -> void:
	var GW: GDScript = load("res://scripts/ex/grid_world.gd")
	for id: String in ["desert", "lab"]:
		var w: Node3D = GW.new()
		w.mobile = true
		var t0 := Time.get_ticks_usec()
		w.call("setup", id)
		var t1 := Time.get_ticks_usec()
		var b0: Dictionary = w.call("bake_map", "surface", 4.0)
		var b1: Dictionary = w.call("bake_map", "cavern", 4.0)
		var t2 := Time.get_ticks_usec()
		var sh: PackedFloat32Array = w.get("_s_h")
		var ch: PackedFloat32Array = w.get("_c_h")
		var sgeo: Dictionary = w.get("_sgeo")
		var vb := 0
		for k: Variant in sgeo.keys():
			var a: Array = sgeo[k]
			for e: Variant in a:
				if e is PackedVector3Array:
					vb += (e as PackedVector3Array).size() * 12
				elif e is PackedColorArray:
					vb += (e as PackedColorArray).size() * 16
				elif e is PackedInt32Array:
					vb += (e as PackedInt32Array).size() * 4
		print("[uxperf] %s setup %.0f ms  bake2 %.0f ms  cells surface %d cavern %d  static boxes %d  _sgeo chunks %d ~%.1f MB  map img %s / %s" % [
			id, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, sh.size(), ch.size(), int(w.get("static_boxes")), sgeo.size(), vb / 1048576.0,
			str((b0["img"] as Image).get_size()), str((b1["img"] as Image).get_size())])
		w.free()
	var MD: GDScript = load("res://scripts/ex/map_def.gd")
	for id: String in ["desert", "lab"]:
		var m: Dictionary = MD.call("map", id)
		var boxes := 0
		for p: Variant in (m.get("boxes", []) as Array):
			boxes += 1
		print("[uxperf] %s boxes %d  extracts %d" % [id, boxes, (m.get("extracts", []) as Array).size()])
	quit()
