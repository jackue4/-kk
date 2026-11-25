extends Control
## 斜切色块：平行四边形（上边往右偏）+ 墨线边 + 硬投影（没有模糊、没有圆角）。改了属性后调 queue_redraw()。
## 故意不写 class_name：const Slab := preload("res://_tasks/ui_comic/comic_slab.gd")。

var fill := Color.WHITE
var edge := Color(0.09, 0.078, 0.102)
var edge_w := 4.0
var skew := 0.21
var drop := Vector2.ZERO
var drop_col := Color(0.09, 0.078, 0.102)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func quad(off := Vector2.ZERO, grow := 0.0) -> PackedVector2Array:
	var s := size.y * skew
	return PackedVector2Array([Vector2(s - grow, -grow) + off, Vector2(size.x + grow, -grow) + off,
			Vector2(size.x - s + grow, size.y + grow) + off, Vector2(-grow, size.y + grow) + off])


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	if drop != Vector2.ZERO and drop_col.a > 0.0:
		draw_colored_polygon(quad(drop, edge_w * 0.5), drop_col)
	if fill.a > 0.0:
		draw_colored_polygon(quad(), fill)
	if edge_w > 0.0 and edge.a > 0.0:
		var p := quad()
		p.append(p[0])
		p.append(p[1])
		draw_polyline(p, edge, edge_w, true)
