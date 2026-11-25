extends MeshInstance3D
## pixelfx 像素特效序列帧的播放（素材来自 pixelfx，MIT，见 res://fx/pixelfx/LICENSE.txt）。
## 帧参数照抄各精灵表 JSON 的 meta.pixelfx，直接写成常量表：导出 Web 时不依赖 JSON 文件。
## 默认用真实时间推进（同 voxel_debris）：顿帧那一下特效照样炸开，不会被冻住；
## 要和战斗时间轴对齐的（如刀客倒地后的内爆对上消失时刻）传 combat_clock。
## 一次性特效播完自动释放；loop 的（飞行中的火球）由调用方释放。
## 故意不写 class_name：用 preload 引用（Vfx.pixel）。

const SHADER := preload("res://shaders/pixel_sheet.gdshader")
const Combat := preload("res://scripts/combat.gd")
## size 单帧像素 | cols 列数 | frames 帧数 | fps | pivot 锚点（命中点 / 中心 / 弹头，帧内像素坐标）
const SHEETS := {
	"hit_spark": {"tex": preload("res://fx/pixelfx/hit_spark.png"),
		"size": Vector2(136, 80), "cols": 4, "frames": 16, "fps": 30.0, "pivot": Vector2(44, 64)},
	"crit_hit": {"tex": preload("res://fx/pixelfx/crit_hit.png"),
		"size": Vector2(216, 136), "cols": 5, "frames": 28, "fps": 30.0, "pivot": Vector2(84, 106)},
	"parry": {"tex": preload("res://fx/pixelfx/parry.png"),
		"size": Vector2(200, 112), "cols": 5, "frames": 31, "fps": 30.0, "pivot": Vector2(100, 96)},
	"implosion": {"tex": preload("res://fx/pixelfx/implosion.png"),
		"size": Vector2(208, 184), "cols": 7, "frames": 51, "fps": 30.0, "pivot": Vector2(104, 92)},
	# 火球：朝右飞、锚点在弹头，循环
	"fireball": {"tex": preload("res://fx/pixelfx/fireball.png"),
		"size": Vector2(136, 56), "cols": 4, "frames": 36, "fps": 30.0, "pivot": Vector2(112, 28)},
	# 火爆：原 small-explosion 只截前 36 帧的火光（后面是灰烟柱），锚点在爆心正下方的地面
	"fire_burst": {"tex": preload("res://fx/pixelfx/fire_burst.png"),
		"size": Vector2(300, 240), "cols": 12, "frames": 36, "fps": 30.0, "pivot": Vector2(150, 196)},
	"plasma": {"tex": preload("res://fx/pixelfx/plasma_explosion.png"),
		"size": Vector2(224, 200), "cols": 7, "frames": 52, "fps": 30.0, "pivot": Vector2(112, 100)},
}
const IMPLOSION_POP := 33  # 内爆：前 33 帧收缩，这一帧开始炸开

static var _quad: QuadMesh

var _fps := 30.0
var _end := 1.0
var _f := 0.0
var _speed := 1.0
var _combat := false
var _loop := false
var _free_roll := false
var _mat: ShaderMaterial


## opts: px 像素尺寸(米) | tint + recolor 换色 | dir 特效朝向（世界方向，按屏幕投影决定镜像与小角度倾斜）
##       from 起始帧 | to 截止帧（不含） | loop 循环 | speed 播放倍速 | intensity 亮度 | outline 描边不透明度
##       lum_cut 亮度阈值（暗于此的像素剔掉） | free_roll 朝向不限角度（飞行弹） | delay 延迟秒数
##       combat_clock 跟随战斗时间（顿帧 / 慢放时一起变慢）
static func play(parent: Node, id: String, pos: Vector3, opts := {}) -> Node3D:
	var sh: Dictionary = SHEETS[id]
	if _quad == null:
		_quad = QuadMesh.new()
	var n := new()
	n.mesh = _quad
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = 16.0
	var tex: Texture2D = sh["tex"]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("sheet", tex)
	m.set_shader_parameter("sheet_px", Vector2(tex.get_width(), tex.get_height()))
	m.set_shader_parameter("frame_px", sh["size"])
	m.set_shader_parameter("pivot_px", sh["pivot"])
	m.set_shader_parameter("cols", float(sh["cols"]))
	m.set_shader_parameter("px_size", float(opts.get("px", 0.03)))
	m.set_shader_parameter("tint", opts.get("tint", Color.WHITE))
	m.set_shader_parameter("recolor", float(opts.get("recolor", 0.0)))
	m.set_shader_parameter("intensity", float(opts.get("intensity", 1.0)))
	m.set_shader_parameter("outline", float(opts.get("outline", 0.8)))
	if opts.has("lum_cut"):
		m.set_shader_parameter("lum_cut", float(opts["lum_cut"]))
	n.material_override = m
	n._mat = m
	n._fps = float(sh["fps"])
	n._end = minf(float(opts.get("to", sh["frames"])), float(sh["frames"]))
	n._f = float(opts.get("from", 0))
	n._speed = float(opts.get("speed", 1.0))
	n._combat = bool(opts.get("combat_clock", false))
	n._loop = bool(opts.get("loop", false))
	n._free_roll = bool(opts.get("free_roll", false))
	m.set_shader_parameter("frame", n._f)
	parent.add_child(n)
	n.global_position = pos
	if opts.has("dir"):
		n.aim(opts["dir"])
	var delay := float(opts.get("delay", 0.0))
	if delay > 0.0:
		n.visible = false
		n.set_process(false)
		n.get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(n):
				n.visible = true
				n.set_process(true))
	return n


## 精灵表里的特效都朝右：按世界方向在屏幕上的投影决定是否镜像，再加一个倾斜角。
## 一次性特效的倾斜限制在 ±0.5 弧度——火星会"落地弹跳"，转太多地面就歪了；飞行弹（free_roll）不限
func aim(dir: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var x := dir.dot(cam.global_basis.x)
	var y := dir.dot(cam.global_basis.y)
	if absf(x) + absf(y) < 1e-3:
		return
	var flip := x < 0.0
	var r := atan2(y, absf(x))
	if not _free_roll:
		r = clampf(r, -0.5, 0.5)
	_mat.set_shader_parameter("flip", flip)
	_mat.set_shader_parameter("roll", -r if flip else r)


func set_alpha(a: float) -> void:
	_mat.set_shader_parameter("alpha", a)


func _process(dt: float) -> void:
	_f += (Combat.cdt(dt) if _combat else minf(dt, 1.0 / 20.0)) * _fps * _speed
	if _f >= _end:
		if _loop:
			_f = fmod(_f, _end)
		else:
			queue_free()
			return
	_mat.set_shader_parameter("frame", minf(_f, _end - 1.0))
