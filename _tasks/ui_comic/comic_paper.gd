extends Control
## 稿纸底：米白纸 + 淡淡的制图线（方格、罗盘刻度、斜向辅助线、四角裁切标记）+ 一条主色的斜带 + 角上的网点。
## 全是 _draw 画的线和多边形，不用贴图；主色 / 罗盘圆心变了调 queue_redraw()。

const Kit := preload("res://_tasks/ui_comic/comic_kit.gd")

var accent := Color(0.945, 0.545, 0.1)
var focus := Vector2(700.0, 470.0)          # 罗盘圆心（人物色块的中心）


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Kit.PAPER)
	var line := Color(Kit.BLUE, 0.15)
	var faint := Color(Kit.BLUE, 0.07)
	# 一条主色的斜带（从左下刷到右上），很淡
	var band := Color(accent.lerp(Kit.PAPER_HI, 0.35), 0.12)
	var bx := focus.x - 520.0
	draw_colored_polygon(PackedVector2Array([Vector2(bx + 420.0, 0.0), Vector2(bx + 860.0, 0.0), Vector2(bx + 440.0, vs.y), Vector2(bx, vs.y)]), band)
	draw_colored_polygon(PackedVector2Array([Vector2(bx + 930.0, 0.0), Vector2(bx + 990.0, 0.0), Vector2(bx + 570.0, vs.y), Vector2(bx + 510.0, vs.y)]), band)
	# 方格
	var step := 100.0
	var x := fmod(focus.x, step)
	while x < vs.x:
		draw_line(Vector2(x, 0.0), Vector2(x, vs.y), faint, 1.0)
		x += step
	var y := fmod(focus.y, step)
	while y < vs.y:
		draw_line(Vector2(0.0, y), Vector2(vs.x, y), faint, 1.0)
		y += step
	# 罗盘：两道圆 + 刻度 + 十字线
	for r: float in [318.0, 452.0, 462.0]:
		draw_arc(focus, r, 0.0, TAU, 96, line, 1.5, true)
	for i in 72:
		var a := TAU * float(i) / 72.0
		var d := Vector2(cos(a), sin(a))
		var long := i % 6 == 0
		draw_line(focus + d * 462.0, focus + d * (486.0 if long else 472.0), line, 2.0 if long else 1.2, true)
	draw_line(Vector2(focus.x, 0.0), Vector2(focus.x, vs.y), line, 1.2)
	draw_line(Vector2(0.0, focus.y), Vector2(vs.x, focus.y), line, 1.2)
	# 八个方位上的小方块（阵眼）
	for i in 8:
		var a2 := TAU * float(i) / 8.0 + TAU / 16.0
		var c := focus + Vector2(cos(a2), sin(a2)) * 390.0
		draw_rect(Rect2(c - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), line, false, 1.5)
	# 斜向辅助线（和色块的斜度一致）
	for k: float in [-760.0, -700.0, 640.0, 700.0]:
		draw_line(Vector2(focus.x + k + vs.y * Kit.SKEW * 0.5, 0.0), Vector2(focus.x + k - vs.y * Kit.SKEW * 0.5, vs.y), line, 1.2, true)
	# 上下边的标尺刻度
	var tx := 40.0
	var n := 0
	while tx < vs.x - 40.0:
		var h := 14.0 if n % 5 == 0 else 7.0
		draw_line(Vector2(tx, 14.0), Vector2(tx, 14.0 + h), line, 1.2)
		draw_line(Vector2(tx, vs.y - 14.0), Vector2(tx, vs.y - 14.0 - h), line, 1.2)
		tx += 20.0
		n += 1
	# 四角裁切标记
	var ink := Color(Kit.INK, 0.55)
	for c2: Vector2 in [Vector2(22.0, 22.0), Vector2(vs.x - 22.0, 22.0), Vector2(22.0, vs.y - 22.0), Vector2(vs.x - 22.0, vs.y - 22.0)]:
		draw_line(c2 - Vector2(12.0, 0.0), c2 + Vector2(12.0, 0.0), ink, 2.0)
		draw_line(c2 - Vector2(0.0, 12.0), c2 + Vector2(0.0, 12.0), ink, 2.0)
		draw_arc(c2, 6.0, 0.0, TAU, 20, ink, 1.5, true)
	# 右上、左下两片网点（越靠角越大）
	_dots(Vector2(vs.x, 0.0), Vector2(-1.0, 1.0), Color(accent, 0.3))
	_dots(Vector2(0.0, vs.y), Vector2(1.0, -1.0), Color(Kit.BLUE, 0.16))


func _dots(corner: Vector2, dir: Vector2, col: Color) -> void:
	var cell := 22.0
	for i in 14:
		for j in 9:
			var k := 1.0 - (float(i) / 14.0 + float(j) / 9.0)
			if k <= 0.05:
				continue
			var off := Vector2((float(i) + (0.5 if j % 2 == 1 else 0.0)) * cell, float(j) * cell * 0.86)
			draw_circle(corner + Vector2(off.x * dir.x, off.y * dir.y), 8.0 * k, col)
