extends SceneTree
## 两张新图里 _sb 摆了多少方块、各是什么形状（挑自检目标、估开销用）：Godot --headless --path . -s res://_tasks/destruct/box_stats.gd
const GridWorld := preload("res://scripts/ex/grid_world.gd")
func _init() -> void:
	for id: String in ["desert", "lab"]:
		var w := GridWorld.new()
		w.setup(id)
		var n := w.dx_box_count().x
		var bi: PackedInt32Array = w.get("_bx_i")
		var cls := {"小件(<=3.5)": 0, "柱(高>=2.5 细)": 0, "墙(长>=9 薄)": 0, "墙(长4~9 薄)": 0, "板(扁平>=4)": 0, "大块": 0, "屋顶组": 0, "实心": 0, "歪的": 0}
		var maxv := 0
		var per := {}
		for i in n:
			var sz: Vector3 = w.call("_bx_size", i)
			var xf: Transform3D = w.call("_bx_xf", i)
			if bi[i * 5] == GridWorld.DX_ROOF:
				cls["屋顶组"] += 1
			else:
				var k := Vector2i(bi[i * 5], bi[i * 5 + 1])
				per[k] = int(per.get(k, 0)) + 1
			if (bi[i * 5 + 4] & 2) != 0:
				cls["实心"] += 1
			if xf.basis.y.y <= 0.95:
				cls["歪的"] += 1
			var mx := maxf(sz.x, maxf(sz.y, sz.z))
			var hl := maxf(sz.x, sz.z)
			var th := minf(sz.x, sz.z)
			if sz.y >= 3.5 and hl >= 9.0 and th <= 1.6:
				cls["墙(长>=9 薄)"] += 1
			elif sz.y >= 3.0 and hl >= 4.0 and th <= 1.6:
				cls["墙(长4~9 薄)"] += 1
			elif sz.y >= 2.5 and hl <= 3.5:
				cls["柱(高>=2.5 细)"] += 1
			elif sz.y <= 1.2 and hl >= 4.0:
				cls["板(扁平>=4)"] += 1
			elif mx <= 3.5:
				cls["小件(<=3.5)"] += 1
			else:
				cls["大块"] += 1
		for k: Vector2i in per:
			maxv = maxi(maxv, int(per[k]))
		var sg: Dictionary = w.get("_sgeo")
		var vmax := 0
		for k: Vector2i in sg:
			vmax = maxi(vmax, ((sg[k] as Array)[0] as PackedVector3Array).size())
		print("[boxes] %s 共 %d · %s · 一块地最多 %d 个方块 / 摆件顶点最多 %d · 载入 %.0f ms" % [id, n, cls, maxv, vmax, w.gen_ms])
		w.free()
	quit(0)
