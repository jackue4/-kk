extends Node3D
## 沙渊巨虫的身体（SPEC 第 8 节）：程序拼的体节方块虫 —— 一个头 + segs 节身子（默认 10 节，砂岩配色，往尾巴渐细），
## 钻地进出：头按动作走，身子沿着头走过的轨迹一节节跟上（轨迹在地下的那一截就埋着，被地面挡住看不见）。
##
## 两种用法：
##   A. 首领的身体（ex_boss.gd 在用）：raid_mob 的 def.model = "-"（不建模型），ex_boss 把 ExWorm 建成自己的子节点（top_level），
##      按技能节奏下命令（travel / rise / hold / arc），每帧把 mob 摆到「离本机主角最近的露出地面的那一节」上 ——
##      受击 / 贴身 / 锁定都打在那一节（每节都是判定框，只是同一时刻对一个人只认最近的那节）；全埋着的时候沉到地下打不到。
##   B. 独立节点：ExWorm.new()，设 floor_fn（或 floor_y）后加进场景，自己下命令；或者设 auto_area（XZ 矩形）让它自己在里面钻来钻去（演出 / 远景）。
## 命令都可以带起点重放（command()），联机时木偶那边照主人发来的同一串命令播，看到的是同一条虫。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Models := preload("res://scripts/creature_model.gd")

enum M { IDLE, TRAVEL, RISE, HOLD, ARC }

## 砂岩配色：[主色, 甲片, 腹, 牙 / 骨, 口, 眼]
const COLS := [Color(0.82, 0.64, 0.4), Color(0.6, 0.42, 0.24), Color(0.9, 0.78, 0.56), Color(0.94, 0.9, 0.78),
		Color(0.32, 0.08, 0.06), Color(1.0, 0.62, 0.15)]

var segs := 10
var seg_len := 2.3
var head_r := 1.7
var tail_r := 0.8
var depth := 7.0                 # 钻在地下时头的深度（米）
var floor_fn := Callable()       # func(x, z) -> 地面高度；没有就用 floor_y
var floor_y := 0.0
var flash := 0.0                 # 受击闪白（外部每帧写，0~1）
var glow := 0.0                  # 常亮的自发光强度（嗜血时泛红光，ex_boss 写）
var glow_col := Color(1.0, 0.35, 0.15)
var auto_area := Rect2()         # 用法 B：非空就自己在这个 XZ 矩形里钻来钻去
var dust := true                 # 破土 / 钻地 / 地下潜行时扬沙

var head := Vector3.ZERO
var head_dir := Vector3.FORWARD
var mode := M.IDLE

var _trail: Array[Vector3] = []          # 头走过的点（新的在前）
var _nodes: Array[MeshInstance3D] = []   # 0 = 头
var _pos := PackedVector3Array()         # 各节中心
var _rad := PackedFloat32Array()
var _mat: StandardMaterial3D
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _c := Vector3.ZERO                   # 弧线的控制点
var _h := 0.0
var _t := 0.0
var _dur := 1.0
var _look := Vector3.INF
var _above := false
var _dust_t := 0.0
var _auto_step := 0

static var _mesh_body: ArrayMesh
static var _mesh_head: ArrayMesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.92
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.9, 0.7)
	_mat.emission_energy_multiplier = 0.0
	_build_meshes()
	_pos.resize(segs + 1)
	_rad.resize(segs + 1)
	for i in segs + 1:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_head if i == 0 else _mesh_body
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Models.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2.0
		add_child(mi)
		_nodes.append(mi)
		var k := float(i) / float(maxi(segs, 1))
		_rad[i] = head_r if i == 0 else lerpf(head_r * 0.92, tail_r, pow(k, 1.3))
	if _trail.is_empty():
		place(head if head != Vector3.ZERO else Vector3.ZERO)


## 地面高度
func ground(x: float, z: float) -> float:
	return float(floor_fn.call(x, z)) if floor_fn.is_valid() else floor_y


func under(p: Vector3) -> Vector3:
	return Vector3(p.x, ground(p.x, p.z) - depth, p.z)


## 整条虫藏到 p 底下（轨迹往 -dir 方向在地下铺好，身子跟着埋着）
func place(p: Vector3, dir := Vector3.FORWARD) -> void:
	head = under(p)
	dir = Vector3(dir.x, 0.0, dir.z)
	head_dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
	_trail.clear()
	var n := int(ceil(float(segs) * seg_len / 0.5)) + 4
	for i in n:
		_trail.append(head - head_dir * 0.5 * float(i))
	mode = M.IDLE
	_above = false
	if not _nodes.is_empty():
		_layout()


# ---------- 命令 ----------

## 地下潜行到 to 底下（dur 秒）
func travel(to: Vector3, dur: float) -> void:
	_start(M.TRAVEL, head, under(to), 0.0, dur)


## 在 at 破土而出，头升到离地 h 米（dur 秒）
func rise(at: Vector3, h: float, dur: float) -> void:
	_start(M.RISE, head, Vector3(at.x, ground(at.x, at.z) + h, at.z), h, dur)


## 立着摇头晃脑 dur 秒，头朝着 look（Vector3.INF = 不管朝向）
func hold(dur: float, look := Vector3.INF) -> void:
	_look = look
	_start(M.HOLD, head, head, 0.0, dur)


## 从现在的位置画一道弧钻进 to（最高离地 h 米，dur 秒）
func arc(to: Vector3, h: float, dur: float) -> void:
	_start(M.ARC, head, under(to), h, dur)


## 联机 / 重放：带起点的命令（kind 是 M 的值；a 起点，b 终点，h 高度，dur 时长）
func command(kind: int, a: Vector3, b: Vector3, h: float, dur: float) -> void:
	if a.distance_to(head) > 0.05:
		head = a
	match kind:
		M.TRAVEL:
			_start(M.TRAVEL, a, b, 0.0, dur)
		M.RISE:
			_start(M.RISE, a, b, h, dur)
		M.HOLD:
			_look = b
			_start(M.HOLD, a, a, 0.0, dur)
		M.ARC:
			_start(M.ARC, a, b, h, dur)


## 这一段命令的参数（给 ex_boss 广播用）：[kind, a, b, h, dur]
func last_command() -> Array:
	return [int(mode), _a, _look if mode == M.HOLD else _b, _h, _dur]


func busy() -> bool:
	return mode != M.IDLE and _t < _dur


func phase() -> float:
	return clampf(_t / maxf(_dur, 0.01), 0.0, 1.0)


func _start(m: M, a: Vector3, b: Vector3, h: float, dur: float) -> void:
	mode = m
	_a = a
	_b = b
	_h = h
	_t = 0.0
	_dur = maxf(dur, 0.05)
	if m == M.ARC:
		var gy := ground((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var mid := (a + b) * 0.5
		# 二次贝塞尔：最高点（s = 0.5）离地 h 米
		_c = Vector3(mid.x, (4.0 * (gy + h) - a.y - b.y) * 0.5, mid.z)


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	if auto_area.has_area() and not busy():
		_auto_next()
	var prev := head
	_t += dt
	var s := phase()
	match mode:
		M.TRAVEL:
			head = _a.lerp(_b, s)
			if dust:
				_dust_t -= dt
				if _dust_t <= 0.0:
					_dust_t = 0.22
					var g := ground(head.x, head.z)
					Vfx.dust(Vector3(head.x, g + 0.1, head.z), 4, 2.5, 1.1)
		M.RISE:
			# 先在地下对准（前三成）再笔直往上冲
			var k := clampf(s / 0.3, 0.0, 1.0)
			var bottom := Vector3(_b.x, minf(_a.y, ground(_b.x, _b.z) - depth * 0.6), _b.z)
			if s < 0.3:
				head = _a.lerp(bottom, k)
			else:
				var u := (s - 0.3) / 0.7
				head = bottom.lerp(_b, 1.0 - (1.0 - u) * (1.0 - u))
		M.HOLD:
			var w := _t
			head = _a + Vector3(sin(w * 1.3) * 0.45, sin(w * 2.1) * 0.25, cos(w * 1.1) * 0.4)
		M.ARC:
			var o := 1.0 - s
			head = _a * o * o + _c * 2.0 * o * s + _b * s * s
	if mode == M.HOLD:
		if _look.is_finite():
			var to := _look - head
			if to.length_squared() > 0.01:
				head_dir = head_dir.slerp(to.normalized(), 1.0 - exp(-4.0 * dt)).normalized()
	else:
		var mv := head - prev
		if mv.length_squared() > 1e-6:
			head_dir = head_dir.slerp(mv.normalized(), 1.0 - exp(-12.0 * dt)).normalized()
		# 轨迹：头走出 0.25 米记一个点（立着摇头的时候不记，脖子那节就不跟着乱扭）
		if _trail.is_empty() or head.distance_to(_trail[0]) > 0.25:
			_trail.push_front(head)
			_trim_trail()
	if _t >= _dur and mode != M.IDLE:
		mode = M.IDLE
	_layout()
	var g0 := ground(head.x, head.z)
	var up := head.y > g0 - head_r * 0.3
	if up != _above:
		_above = up
		if dust:
			var at := Vector3(head.x, g0 + 0.15, head.z)
			Vfx.dust(at, 18, 6.5, 1.8)
			Vfx.debris(at, Vector3.UP, [COLS[0], COLS[1], COLS[2]], 12, 8.0, 1.6)
	_mat.emission_energy_multiplier = flash * 1.3 + glow
	_mat.emission = Color(1.0, 0.95, 0.85) if flash > 0.05 else glow_col


func _trim_trail() -> void:
	var need := float(segs) * seg_len + 4.0
	var acc := 0.0
	for i in range(1, _trail.size()):
		acc += _trail[i].distance_to(_trail[i - 1])
		if acc > need:
			_trail.resize(i + 1)
			return


## 摆各节：第 k 节在轨迹上离头 k × seg_len 的地方，朝向前一节
func _layout() -> void:
	_pos[0] = head
	var want := seg_len
	var k := 1
	var last := head
	var acc := 0.0
	for i in _trail.size():
		var p: Vector3 = _trail[i]
		var d := p.distance_to(last)
		while k <= segs and acc + d >= want and d > 1e-5:
			_pos[k] = last.lerp(p, (want - acc) / d)
			k += 1
			want += seg_len
		acc += d
		last = p
		if k > segs:
			break
	# 轨迹不够长（刚开始）：沿最后一段的方向往下延
	var tail_dir := Vector3.DOWN
	if _trail.size() >= 2:
		tail_dir = (_trail[_trail.size() - 1] - _trail[_trail.size() - 2]).normalized()
	while k <= segs:
		_pos[k] = last + tail_dir * (want - acc)
		k += 1
		want += seg_len
	for i in segs + 1:
		var fwd: Vector3 = head_dir if i == 0 else (_pos[i - 1] - _pos[i])
		if fwd.length_squared() < 1e-6:
			fwd = head_dir
		fwd = fwd.normalized()
		var upv := Vector3.UP if absf(fwd.y) < 0.97 else Vector3.BACK
		var bs := Basis.looking_at(fwd, upv)
		var r: float = _rad[i]
		var sc := Vector3(r, r, r) if i == 0 else Vector3(r, r, seg_len * 0.98)
		var mi := _nodes[i]
		mi.global_transform = Transform3D(bs.scaled_local(sc), _pos[i])
		# 埋得深的整节不画（地面本来就挡着，省得白画）
		mi.visible = _pos[i].y > ground(_pos[i].x, _pos[i].z) - r * 1.6


# ---------- 查询（ex_boss 用） ----------

## 露出地面的各节中心（含头）
func exposed_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in segs + 1:
		var p := _pos[i]
		if p.y > ground(p.x, p.z) - _rad[i] * 0.5:
			out.append(p)
	return out


func is_exposed() -> bool:
	for i in segs + 1:
		var p := _pos[i]
		if p.y > ground(p.x, p.z) - _rad[i] * 0.5:
			return true
	return false


## 离 p 最近的露出地面的那一节：[中心, 半径]；全埋着返回 []
func nearest_exposed(p: Vector3) -> Array:
	var best := -1
	var bd := INF
	for i in segs + 1:
		var c := _pos[i]
		if c.y <= ground(c.x, c.z) - _rad[i] * 0.5:
			continue
		var d := c.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return []
	return [_pos[best], float(_rad[best])]


## p 是不是贴在哪一节露出地面的身子上（extra = 额外的判定余量，米）
func touches(p: Vector3, extra := 0.6) -> bool:
	for i in segs + 1:
		var c := _pos[i]
		if c.y <= ground(c.x, c.z) - _rad[i] * 0.5:
			continue
		var r := _rad[i] + extra
		if c.distance_squared_to(p) < r * r:
			return true
	return false


func head_radius() -> float:
	return head_r


# ---------- 用法 B：自己钻来钻去 ----------

func _auto_next() -> void:
	var r := auto_area
	var pick := Vector2(randf_range(r.position.x + 6.0, r.end.x - 6.0), randf_range(r.position.y + 6.0, r.end.y - 6.0))
	var p := Vector3(pick.x, 0.0, pick.y)
	match _auto_step % 4:
		0:
			travel(p, clampf(Vector2(head.x - p.x, head.z - p.z).length() / 12.0, 0.8, 2.6))
		1:
			rise(Vector3(head.x, 0.0, head.z), 7.5, 1.3)
		2:
			hold(2.5)
		3:
			arc(p, 6.0, 1.9)
	_auto_step += 1


# ---------- 造型 ----------

## 身子一节：本地 -Z 朝头，单位半径 1、长 1（实例按 (r, r, 节长) 缩放）；头：单位半径 1（实例按 r 等比缩放）
static func _build_meshes() -> void:
	if _mesh_body != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Data.add_box(st, Vector3(2.0, 2.0, 1.0), _xf(Vector3.ZERO), COLS[0])
	Data.add_box(st, Vector3(2.2, 0.4, 0.72), _xf(Vector3(0, 0.92, 0.02)), COLS[1])      # 背甲
	Data.add_box(st, Vector3(0.45, 0.4, 0.5), _xf(Vector3(0, 1.22, 0.0)), COLS[1])      # 背棘
	Data.add_box(st, Vector3(0.36, 1.4, 0.66), _xf(Vector3(1.04, 0.05, 0.02)), COLS[1])  # 侧甲
	Data.add_box(st, Vector3(0.36, 1.4, 0.66), _xf(Vector3(-1.04, 0.05, 0.02)), COLS[1])
	Data.add_box(st, Vector3(1.5, 0.3, 0.8), _xf(Vector3(0, -0.96, 0.0)), COLS[2])      # 腹
	_mesh_body = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Data.add_box(st, Vector3(2.3, 2.1, 1.8), _xf(Vector3(0, 0, 0.1)), COLS[0])          # 头壳
	Data.add_box(st, Vector3(2.5, 0.45, 1.5), _xf(Vector3(0, 1.08, 0.2)), COLS[1])     # 头冠
	Data.add_box(st, Vector3(0.6, 0.7, 1.2), _xf(Vector3(0, 1.45, 0.3)), COLS[1])
	Data.add_box(st, Vector3(1.5, 1.3, 0.22), _xf(Vector3(0, -0.05, -0.82)), COLS[4])  # 口
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			# 四根口器（往外张一点）
			var xf := Transform3D(Basis.from_euler(Vector3(sy * 0.35, -sx * 0.35, 0.0)), Vector3(sx * 0.78, sy * 0.68, -1.25))
			Data.add_box(st, Vector3(0.34, 0.34, 1.15), xf, COLS[3])
		Data.add_box(st, Vector3(0.36, 0.26, 0.12), _xf(Vector3(sx * 0.66, 0.62, -0.95)), COLS[5])   # 眼
	Data.add_box(st, Vector3(1.6, 0.3, 1.5), _xf(Vector3(0, -1.02, 0.1)), COLS[2])
	_mesh_head = st.commit()


static func _xf(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)
