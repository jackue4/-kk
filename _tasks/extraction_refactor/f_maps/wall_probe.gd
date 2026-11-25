extends SceneTree
## F_maps：天工楼北墙一线（x = -10，y = 52.9）的实心盒子 / 地形，看突进扫墙为什么没挡住
const GW := preload("res://scripts/ex/grid_world.gd")

func _init() -> void:
	var w: Node3D = GW.new()
	w.setup("lab")
	var y := 52.9
	for xi in [-10.0, -9.0, -11.0]:
		var line := ""
		var z := -10.0
		while z >= -30.0:
			var h: float = w.height(xi, z)
			var s: float = w.solid_h(xi, z, y + 2.05)
			var wall := (h - y > 2.25) or (s - y > 1.0)
			line += "%s" % ("#" if wall else ".")
			z -= 0.5
		print("[wp] x %.0f z -10 → -30 (0.5): %s" % [xi, line])
	print("[wp] solid_h(-10,-13.2)=%.2f solid_h(-10,-19.5)=%.2f solid_h(-10,-20.5)=%.2f h=%.2f" % [w.solid_h(-10.0, -13.2, y + 2.05), w.solid_h(-10.0, -19.5, y + 2.05), w.solid_h(-10.0, -20.5, y + 2.05), w.height(-10.0, -19.5)])
	w.free()
	quit()
