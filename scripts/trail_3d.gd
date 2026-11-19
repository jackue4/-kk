class_name Trail3D
extends MeshInstance3D
## 面向相机的细带拖尾（世界空间）。按时间留存，速度越快拖尾越长。
## 宽度曲线：头部一点起锋、瞬间到满宽，然后一路收细到尾部成尖。
## min_px 给一个屏幕像素下限：镜头拉远时线不会细到消失，也就不需要靠加宽加亮来显形。
## 挂在不移动的节点下，用 point_fn 取每帧的头部位置。

var lifetime := 0.5
var width := 0.1
var min_px := 0.0
var taper := 1.0   # 收尖指数：越大越早变细
var emitting := false
var tint := Color.WHITE
var point_fn: Callable
var min_step := 0.04
var time_scale := 1.0  # 近战剑光随顿帧一起定格
var smooth := 0        # 相邻两个采样点之间再插几个 Catmull-Rom 点：高速追踪的弹道拖尾不再折成折线

var _pts := PackedVector3Array()
var _born := PackedFloat32Array()
var _im := ImmediateMesh.new()
var _time := 0.0
var _drawn := false


func _init() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_priority = 30  # 在角色/飞剑/相机之后更新


func clear() -> void:
	_pts.clear()
	_born.clear()


func _process(dt: float) -> void:
	_time += dt * time_scale
	var cut := 0
	while cut < _born.size() and _time - _born[cut] > lifetime:
		cut += 1
	if cut > 0:
		_pts = _pts.slice(cut)
		_born = _born.slice(cut)

	if emitting and point_fn.is_valid():
		var head: Vector3 = point_fn.call()
		var n0 := _pts.size()
		if n0 == 0 or _pts[n0 - 1].distance_squared_to(head) > min_step * min_step:
			_pts.append(head)
			_born.append(_time)

	var n := _pts.size()
	var cam := get_viewport().get_camera_3d()
	if n < 3 or cam == null:
		if _drawn:
			_im.clear_surfaces()
			_drawn = false
		return
	_im.clear_surfaces()
	_drawn = true
	var cpos := cam.global_position
	var cfwd := -cam.global_basis.z
	var px_k := 0.0
	if min_px > 0.0:
		var vh := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		px_k = min_px * 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / vh
	var pts := _pts
	var us := PackedFloat32Array()
	us.resize(n)
	for j in n:
		us[j] = clampf((_time - _born[j]) / lifetime, 0.0, 1.0)
	if smooth > 0:
		var sp := PackedVector3Array()
		var su := PackedFloat32Array()
		for j in n - 1:
			var a := _pts[maxi(j - 1, 0)]
			var b := _pts[j]
			var c := _pts[j + 1]
			var d := _pts[mini(j + 2, n - 1)]
			for s in smooth + 1:
				var f := float(s) / float(smooth + 1)
				sp.append(b.cubic_interpolate(c, a, d, f))
				su.append(lerpf(us[j], us[j + 1], f))
		sp.append(_pts[n - 1])
		su.append(us[n - 1])
		pts = sp
		us = su
		n = pts.size()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var j := n - 1 - i  # 从头(最新)到尾
		var p := pts[j]
		var u := us[j]
		var tg := pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)]
		var side := tg.cross(cpos - p)
		if side.length_squared() < 1e-10:
			side = Vector3.UP
		var full := maxf(width, px_k * maxf((p - cpos).dot(cfwd), 0.1))
		var w := full * 0.5 * smoothstep(0.0, 0.05, u + 0.004) * pow(1.0 - u, taper)
		side = side.normalized() * w
		_im.surface_set_color(tint)
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(p + side)
		_im.surface_set_color(tint)
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(p - side)
	_im.surface_end()
