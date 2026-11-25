extends SceneTree
## F_maps：minimap.gd 的 Painter 两种模式（direct = 老大世界原样 draw_* / 合批）每个方法都过一遍，看有没有运行时错误、顶点数和颜色数对不对得上
const Minimap := preload("res://scripts/minimap.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

class Probe extends Control:
	var direct := true
	var draws := 0
	var verts := 0
	var cols := 0
	var pt: RefCounted
	func _draw() -> void:
		if pt == null:
			pt = Minimap.Painter.new(self)
		pt.set("direct", direct)
		var f: Font = UiStyle.kai()
		pt.call("circle", Vector2(20, 20), 2.6, Color.RED)
		pt.call("circle", Vector2(40, 20), 14.5, Color(1, 0, 0, 0.3))
		pt.call("arc", Vector2(60, 20), 6.0, 0.0, TAU, 12, Color.ORANGE, 1.2)
		pt.call("arc", Vector2(60, 40), 77.0, 0.0, TAU, 64, Color.ORANGE, 2.2)
		pt.call("arc", Vector2(80, 20), 11.0, -PI * 0.5, -PI * 0.5 + TAU * 0.4, 28, Color.RED, 2.6)
		pt.call("rect", Rect2(10, 50, 9, 9), Color.WHITE)
		pt.call("rect", Rect2(10, 70, 40, 30), Color.BLACK, false, 2.0)
		pt.call("line", Vector2(0, 0), Vector2(10, 0), Color.GRAY, 2.0)
		pt.call("poly", PackedVector2Array([Vector2(0, 0), Vector2(5, 5), Vector2(-5, 5)]), Color.BLUE)
		pt.call("poly", PackedVector2Array([Vector2(0, -9), Vector2(6, 6), Vector2(0, 2), Vector2(-6, 6)]), Color.WHITE)
		var star := PackedVector2Array()
		for i in 8:
			star.append(Vector2(100, 100) + Vector2.from_angle(-PI * 0.5 + PI * 0.25 * float(i)) * (6.0 if i % 2 == 0 else 2.7))
		pt.call("poly", star, Color.PURPLE)
		pt.call("text", f, Vector2(0, 120), "北撤", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.RED)
		pt.call("text_outline", f, Vector2(0, 140), "撤离点 12m", HORIZONTAL_ALIGNMENT_CENTER, 178.0, 15, 5, Color.BLACK)
		if not direct:
			verts = (pt.get("_pts") as PackedVector2Array).size()
			cols = (pt.get("_cols") as PackedColorArray).size()
		pt.call("flush")
		draws += 1

func _init() -> void:
	var a := Probe.new()
	a.direct = true
	a.size = Vector2(200, 200)
	var b := Probe.new()
	b.direct = false
	b.size = Vector2(200, 200)
	root.add_child(a)
	root.add_child(b)
	for i in 4:
		await process_frame
		a.queue_redraw()
		b.queue_redraw()
	print("[pt] direct draws %d · batch draws %d verts %d cols %d (三角形 %d，整除 3 %s)" % [a.draws, b.draws, b.verts, b.cols, b.verts / 3, b.verts % 3 == 0])
	quit()
