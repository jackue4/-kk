extends StyleBox
## 「纸片」样式：一张宣纸底纹平铺当底，上面压一圈细墨线（九宫格），底下可以带一圈柔和的投影，
## 大面板底边还能铺一抹淡墨远山。面板 / 按钮 / 背包格 / 血条框全用它，由 ui_style.gd 配好再发出去。
## 为什么不用 StyleBoxTexture：底纹要平铺（拉伸会把纸纤维抹糊），线框要拉伸，两样叠在一个样式里只能自己画；
## 这样所有界面共用一张 384 的底纹，线框贴图只有几十像素。
## 贴图都是「白 + 透明度」的，颜色在这里给（同一张线框能当墨线也能当朱砂线）。
## 注意：画线框时临时改了画布的变换、画完恢复成单位变换 —— 在 draw_set_transform 之后别用 draw_style_box 画这种样式。
## 故意不写 class_name：用 preload 引用。

const TILE := 300.0          # 底纹一格画多大（界面单位）
const FRAME_PX := 2.0        # 线框贴图每个界面单位几个像素（见 _tasks/ui_kit/make_ui.py 的 S）
const SHADOW_M := 24.0       # 投影贴图的边距

var paper: Texture2D
var paper_col := Color.WHITE       # 底纹的染色；透明度 0 = 不画底
var paper_inset := 0.0             # 底纹比外框往里收多少（条框：纸只铺在线里面）
var grow := 0.0                    # 整体往外扩多少（条框：线画在填充条的外面）
var frame: Texture2D
var frame_m := Vector2.ZERO        # 线框九宫格的边距（界面单位；x = 左右，y = 上下）
var frame_col := Color.WHITE
var shadow: Texture2D
var shadow_a := 0.0
var mountain: Texture2D            # 底边的远山（宽度铺满线框内侧）
var mountain_col := Color(0, 0, 0, 0)
var mountain_inset := 15.0


func _draw(ci: RID, rect: Rect2) -> void:
	var r := rect.grow(grow)
	if shadow != null and shadow_a > 0.0:
		RenderingServer.canvas_item_add_nine_patch(ci, r.grow(SHADOW_M), Rect2(Vector2.ZERO, shadow.get_size()), shadow.get_rid(),
				Vector2(SHADOW_M, SHADOW_M), Vector2(SHADOW_M, SHADOW_M),
				RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, false, Color(1, 1, 1, shadow_a))
	if paper != null and paper_col.a > 0.0:
		var pr := r.grow(-paper_inset)
		var ts := paper.get_size()
		var y := 0.0
		while y < pr.size.y - 0.01:
			var h := minf(TILE, pr.size.y - y)
			var x := 0.0
			while x < pr.size.x - 0.01:
				var w := minf(TILE, pr.size.x - x)
				RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(pr.position + Vector2(x, y), Vector2(w, h)), paper.get_rid(),
						Rect2(Vector2.ZERO, ts * Vector2(w, h) / TILE), paper_col)
				x += TILE
			y += TILE
	if mountain != null and mountain_col.a > 0.0:
		var ms := mountain.get_size()
		var mw := r.size.x - mountain_inset * 2.0
		var mh := minf(mw * ms.y / ms.x, r.size.y * 0.4)
		if mw > 8.0:
			RenderingServer.canvas_item_add_texture_rect(ci, Rect2(r.position.x + mountain_inset, r.end.y - mountain_inset - mh, mw, mh),
					mountain.get_rid(), false, mountain_col)
	if frame != null and frame_col.a > 0.0:
		var m := frame_m * FRAME_PX
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D(0.0, Vector2.ONE / FRAME_PX, 0.0, Vector2.ZERO))
		RenderingServer.canvas_item_add_nine_patch(ci, Rect2(r.position * FRAME_PX, r.size * FRAME_PX), Rect2(Vector2.ZERO, frame.get_size()),
				frame.get_rid(), m, m, RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, frame_col)
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
