class_name PixelFx
extends RefCounted
## pixelfx 像素特效库（MIT，源码在 H:\gdoot特效文件\pixelfx）。
## 精灵表在 res://addons/pixelfx/sheets/。按目录名调用，例如 "ice/frost-nova"。
##
## 三维：
##   var fx := PixelFx.play_3d(self, "fire/torch", global_position)
## 二维：
##   var fx := PixelFx.play_2d(self, "ui/confetti", position)
## 查找：
##   PixelFx.find("frost")

const ROOT := "res://addons/pixelfx/sheets/"

static var _index: Array = []
static var _index_ready := false
static var _frames: Dictionary = {}


static func list_ids() -> PackedStringArray:
	_ensure_index()
	var ids := PackedStringArray()
	for entry: Dictionary in _index:
		ids.append(str(entry.get("id", "")))
	return ids


## 按 id、英文名、简介或标签做不区分大小写的包含匹配。
static func find(query: String) -> Array:
	_ensure_index()
	var q := query.to_lower()
	var hits: Array = []
	for entry: Dictionary in _index:
		var tags := ""
		for tag in entry.get("tags", []):
			tags += " " + str(tag)
		var blob := "%s %s %s %s" % [
			str(entry.get("id", "")),
			str(entry.get("name", "")),
			str(entry.get("desc", "")),
			tags,
		]
		if blob.to_lower().contains(q):
			hits.append(entry)
	return hits


static func has(id: String) -> bool:
	return FileAccess.file_exists(ROOT + id + ".json") and FileAccess.file_exists(ROOT + id + ".png")


## 在 Node3D 下播放。pixel_size 是每个像素对应的世界米数。循环特效需要调用方自己 queue_free。
static func play_3d(parent: Node3D, id: String, at: Vector3 = Vector3.INF, pixel_size: float = 0.03, flip_h: bool = false) -> AnimatedSprite3D:
	var built := _build(id)
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = built.frames
	sprite.animation = &"play"
	sprite.centered = true
	sprite.offset = built.offset
	sprite.flip_h = flip_h
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparent = true
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.modulate = Color.WHITE
	parent.add_child(sprite)
	if at != Vector3.INF:
		sprite.global_position = at
	sprite.play(&"play")
	if not built.loop:
		sprite.animation_finished.connect(sprite.queue_free)
	return sprite


## 在 Node2D 下播放。scale 是像素放大倍数，用最近邻保持像素边缘。
static func play_2d(parent: Node2D, id: String, at: Vector2 = Vector2.INF, scale: float = 2.0, flip_h: bool = false) -> AnimatedSprite2D:
	var built := _build(id)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = built.frames
	sprite.animation = &"play"
	sprite.centered = true
	sprite.offset = built.offset
	sprite.flip_h = flip_h
	sprite.scale = Vector2(scale, scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)
	if at != Vector2.INF:
		sprite.global_position = at
	sprite.play(&"play")
	if not built.loop:
		sprite.animation_finished.connect(sprite.queue_free)
	return sprite


static func _ensure_index() -> void:
	if _index_ready:
		return
	_index_ready = true
	var path := ROOT + "index.json"
	if not FileAccess.file_exists(path):
		push_error("PixelFx 目录缺失：%s" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		_index = parsed


static func _build(id: String) -> Dictionary:
	if _frames.has(id):
		return _frames[id]
	var json_path := ROOT + id + ".json"
	var png_path := ROOT + id + ".png"
	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(png_path):
		push_error("PixelFx 没有这个特效：%s" % id)
		var empty := SpriteFrames.new()
		empty.add_animation(&"play")
		return {"frames": empty, "offset": Vector2.ZERO, "loop": false}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var meta: Dictionary = data.get("meta", {})
	var px: Dictionary = meta.get("pixelfx", {})
	var tex: Texture2D = load(png_path)
	if tex == null:
		push_error("PixelFx 贴图还没导入：%s" % png_path)
		var missing := SpriteFrames.new()
		missing.add_animation(&"play")
		return {"frames": missing, "offset": Vector2.ZERO, "loop": false}
	var frames := SpriteFrames.new()
	frames.add_animation(&"play")
	var fps := float(px.get("fps", 12.0))
	if fps <= 0.0:
		fps = 12.0
	frames.set_animation_speed(&"play", fps)
	var loop := bool(px.get("loop", false))
	frames.set_animation_loop(&"play", loop)
	var frame_size: Array = px.get("frameSize", [0, 0])
	for item: Variant in data.get("frames", []):
		if item is not Dictionary:
			continue
		var rect: Dictionary = item.get("frame", {})
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(rect.get("x", 0)), float(rect.get("y", 0)), float(rect.get("w", 1)), float(rect.get("h", 1)))
		if frame_size[0] == 0:
			frame_size = [rect.get("w", 1), rect.get("h", 1)]
		frames.add_frame(&"play", atlas, 1.0)
	var pivot: Array = px.get("pivot", [float(frame_size[0]) * 0.5, float(frame_size[1]) * 0.5])
	var offset := Vector2(
		float(frame_size[0]) * 0.5 - float(pivot[0]),
		float(frame_size[1]) * 0.5 - float(pivot[1])
	)
	var built := {"frames": frames, "offset": offset, "loop": loop}
	_frames[id] = built
	return built
