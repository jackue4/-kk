extends RefCounted
## 木兰草原的地形与植被数据：噪声高度函数 + 地块网格 / 远景网格 / 草叶 / 花 / 树 / 灌木 / 白石的实例数据，
## 以及村子的位置、土路折线、房子布局。
## 只读噪声、纯计算，在 WorkerThreadPool 里并行调用（见 meadow_terrain.gd / meadow_grass.gd），不碰场景树。
## 故意不写 class_name：用 preload 引用（新加的全局类名不进编辑器生成的类缓存，命令行直接跑会找不到）。
##
## 高度（吉卜力式的开阔草原：大片缓坡，远处才有圆润的高地）：
##   缓坡（大尺度 fbm，约 ±34 米）+ 中尺度波纹（±4.5 米）；平川区（mask 低）压得更平；
##   高地（mask 高、离出生点 0.9 公里外）叠圆润的 fbm 丘陵（最高 +170 米）；外圈 8.6~11.6 公里升起群山当世界边界；
##   出生点 60 米内、村子 44 米内各自压平。最低 3 米（主角各处的 y >= 0 兜底不受影响）。
## 村子：出生点外 VILLAGE_DIST 米一圈里挑最平、和出生点高差最小的方向（出生点就面朝村子）；
##   土路从出生点前几米蜿蜒到村中空地，再从另一侧出村往远处去；房子两排围着空地，门朝空地。

const CHUNK := 256.0
const WORLD_HALF := 12288.0          # 世界半边长 = 48 个地块
const GRID := 96                     # 地块编号 -48..47（远景遮罩一格一块）
const BORDER_R0 := 8600.0
const BORDER_R1 := 11600.0
const SPAWN_R := 60.0
const SPAWN_BLEND := 170.0
const SEED := 20261112
## 各精度：每块格数 / 裙边下垂（米，盖住相邻不同精度地块之间的裂缝）
const CELLS: Array[int] = [64, 32, 16, 8]
const SKIRT: Array[float] = [6.0, 14.0, 30.0, 60.0]
const ROCK_LOD := 2                  # 这个精度及更细的地块才放石头、树
const BUSH_LOD := 1                  # 灌木
const TREE_VARIANTS := 4
const BUSH_VARIANTS := 3
## 村子 / 土路
const VILLAGE_DIST := 260.0
const VILLAGE_R := 44.0
const VILLAGE_BLEND := 60.0
const PLAZA_R := 9.5
const PATH_HW := 1.3
## 草地块
const TILE := 32.0
const BLADE_W := 0.3                 # 草丛网格（4 片 WindGrass 原版草叶，见 meadow_grass.gd）整体缩放
const BLADE_H := 0.3
## 花色：waving_mesh 着色器拿 COLOR.x 在颜色表里取花瓣色（表见 meadow_grass.gd 的 flower_mat）
const PETALS: Array[float] = [0.10, 0.28, 0.45, 0.61, 0.77, 0.90]   # 红、珊瑚、粉、白、淡紫、蓝
const PETAL_W: Array[float] = [0.24, 0.10, 0.10, 0.22, 0.20, 0.14]
const FLOWER_SCALE := 1.35
const PATCH_P := 0.12                # 每块草地出一丛原版 flower_field 的概率
const PATCH_SCALE := 1.5

var hills := FastNoiseLite.new()
var mid := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var mask := FastNoiseLite.new()
var petal := FastNoiseLite.new()     # flower_field.gd 原版的 noise（植株大小起伏）
var grove := FastNoiseLite.new()     # 树林疏密
var bloom := FastNoiseLite.new()     # 花的疏密
var spawn_h := 30.0

var village := Vector3.ZERO          # 村中心（y = 压平后的地面高度）
var village_dir := Vector3.FORWARD   # 出生点 → 村子
var village_side := Vector3.RIGHT
var path := PackedVector4Array()     # 土路折线：x, z, 半宽, 从起点算的累计长度
var plaza_s := 0.0                   # 村中心在土路上的累计长度
var plaza := Vector3.ZERO            # 村中空地：x, z, 半径
var houses: Array[Dictionary] = []   # {x, z, yaw, w, d, floors, roof, timber, ivy, seed}
var mill := Vector4.ZERO             # 风车：x, y, z, 朝向
var big_trees: Array[Vector4] = []   # 村里和出生点旁的大树：x, y, z, 缩放
var _path_box := Rect2()


func _init() -> void:
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.seed = SEED
	hills.frequency = 1.0 / 1400.0
	hills.fractal_octaves = 4
	hills.fractal_gain = 0.42
	mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mid.seed = SEED + 1
	mid.frequency = 1.0 / 240.0
	mid.fractal_octaves = 3
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.seed = SEED + 2
	ridge.frequency = 1.0 / 1300.0
	ridge.fractal_octaves = 4
	mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mask.seed = SEED + 3
	mask.frequency = 1.0 / 3600.0
	mask.fractal_octaves = 2
	petal.seed = SEED + 4
	petal.fractal_gain = 0.8
	petal.fractal_weighted_strength = 0.2
	grove.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grove.seed = SEED + 5
	grove.frequency = 1.0 / 420.0
	grove.fractal_octaves = 2
	bloom.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bloom.seed = SEED + 6
	bloom.frequency = 1.0 / 90.0
	bloom.fractal_octaves = 2
	spawn_h = maxf(_base(0.0, 0.0), 18.0)
	_pick_village()
	_make_path()
	_layout_village()


static func ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


## 原始地形（不含出生点 / 村子压平）
func _base(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var hl := hills.get_noise_2d(x, z)
	var md := mid.get_noise_2d(x, z)
	var mk := mask.get_noise_2d(x, z)
	var h := 44.0 + hl * 34.0 + md * 4.5
	var flat := ss(-0.05, -0.4, mk)
	if flat > 0.0:
		h = lerpf(h, 38.0 + hl * 10.0 + md * 1.6, flat)
	var mtn := ss(0.15, 0.55, mk) * ss(900.0, 2400.0, r)
	if mtn > 0.0:
		var rg := ridge.get_noise_2d(x, z) * 0.5 + 0.5
		h += mtn * rg * rg * 170.0
	var b := ss(BORDER_R0, BORDER_R1, r)
	if b > 0.0:
		var rg2 := ridge.get_noise_2d(x * 0.55 + 913.0, z * 0.55 - 377.0) * 0.5 + 0.5
		h += b * (260.0 + rg2 * rg2 * 420.0)
	return maxf(h, 3.0)


## 地形真实高度（噪声原值；画出来的网格在格点之间是线性插值，见 sample_grid）
func height(x: float, z: float) -> float:
	var h := _base(x, z)
	var lim := SPAWN_R + SPAWN_BLEND
	var r2 := x * x + z * z
	if r2 < lim * lim:
		h = lerpf(h, spawn_h + mid.get_noise_2d(x, z) * 0.5, ss(lim, SPAWN_R, sqrt(r2)))
	var vl := VILLAGE_R + VILLAGE_BLEND
	var dx := x - village.x
	var dz := z - village.z
	var v2 := dx * dx + dz * dz
	if v2 < vl * vl:
		h = lerpf(h, village.y + mid.get_noise_2d(x, z) * 0.35, ss(vl, VILLAGE_R, sqrt(v2)))
	return h


# ---------- 村子 / 土路 ----------

func _pick_village() -> void:
	var best := INF
	for i in 24:
		var a := TAU * i / 24.0
		var d := Vector3(sin(a), 0.0, cos(a))
		var c := d * VILLAGE_DIST
		var hc := _base(c.x, c.z)
		var rough := 0.0
		for k in 8:
			var b := TAU * k / 8.0
			rough += absf(_base(c.x + cos(b) * 55.0, c.z + sin(b) * 55.0) - hc)
		var mid_h := _base(c.x * 0.5, c.z * 0.5)
		var score := rough + absf(hc - spawn_h) * 0.6 + absf(mid_h - (hc + spawn_h) * 0.5) * 0.5
		if score < best:
			best = score
			village_dir = d
			village = Vector3(c.x, lerpf(hc, spawn_h, 0.35), c.z)
	village_side = village_dir.cross(Vector3.UP).normalized()


func _make_path() -> void:
	var vd2 := Vector2(village_dir.x, village_dir.z)
	var s2 := Vector2(village_side.x, village_side.z)
	var vc := Vector2(village.x, village.z)
	var a := vd2 * 6.0
	var b := vc - vd2 * (PLAZA_R + 2.0)
	var pts: Array[Vector2] = []
	var hws: Array[float] = []
	for i in 16:
		var t := i / 15.0
		var off := (sin(t * PI * 2.1 + 0.4) * 12.0 + sin(t * PI * 4.6 + 1.3) * 3.0) * sin(t * PI)
		pts.append(a.lerp(b, t) + s2 * off)
		hws.append(PATH_HW)
	pts.append(vc)
	hws.append(PATH_HW + 0.3)
	var ex := vd2.rotated(0.35)
	var e0 := vc + ex * (PLAZA_R + 2.0)
	var e1 := vc + ex * 190.0
	var px := ex.orthogonal()
	for i in 10:
		var t := i / 9.0
		pts.append(e0.lerp(e1, t) + px * sin(t * PI * 1.7 + 2.0) * 10.0 * t)
		hws.append(PATH_HW * lerpf(1.0, 0.75, t))
	var acc := 0.0
	_path_box = Rect2(pts[0], Vector2.ZERO)
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		path.append(Vector4(pts[i].x, pts[i].y, hws[i], acc))
		_path_box = _path_box.expand(pts[i])
		if i == 16:
			plaza_s = acc
	_path_box = _path_box.grow(30.0)
	plaza = Vector3(village.x, village.z, PLAZA_R + 1.5)


## 到土路的距离和该处路半宽：Vector2(距离, 半宽)；离路 30 米外直接返回很大的距离
func path_info(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	if not _path_box.has_point(p):
		return Vector2(1e9, PATH_HW)
	var best := 1e9
	var hw := PATH_HW
	for i in path.size() - 1:
		var a := Vector2(path[i].x, path[i].y)
		var ab := Vector2(path[i + 1].x, path[i + 1].y) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			hw = lerpf(path[i].z, path[i + 1].z, t)
	return Vector2(best, hw)


## 沿土路走 s 米处：Vector4(x, z, 方向 x, 方向 z)
func path_at(s: float) -> Vector4:
	for i in path.size() - 1:
		if s <= path[i + 1].w or i == path.size() - 2:
			var a := Vector2(path[i].x, path[i].y)
			var b := Vector2(path[i + 1].x, path[i + 1].y)
			var t := clampf((s - path[i].w) / maxf(path[i + 1].w - path[i].w, 1e-4), 0.0, 1.0)
			var q := a.lerp(b, t)
			var d := (b - a).normalized()
			return Vector4(q.x, q.y, d.x, d.y)
	return Vector4.ZERO


## 着色器用：PackedVector4Array（x, z, 半宽, 0），补齐到 32 个
func path_uniform() -> PackedVector4Array:
	var out := PackedVector4Array()
	for v in path:
		out.append(Vector4(v.x, v.y, v.z, 0.0))
	while out.size() < 32:
		out.append(Vector4.ZERO)
	return out


func _layout_village() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 11
	var vd2 := Vector2(village_dir.x, village_dir.z)
	var vc := Vector2(village.x, village.z)
	# 相对"进村方向"的角度（出村那条路在 +0.35，进村在 ±PI），两侧各一排
	var specs := [[0.95, 25.0], [1.5, 27.0], [2.05, 24.5], [2.62, 28.0], [-0.85, 25.0], [-1.45, 27.5], [-2.05, 24.0]]
	for k in specs.size():
		var phi: float = specs[k][0]
		var r: float = specs[k][1]
		var dir := vd2.rotated(phi)
		var p := vc + dir * r
		houses.append({
			"x": p.x, "z": p.y, "yaw": atan2(-dir.x, -dir.y),
			"w": rng.randf_range(7.0, 9.5), "d": rng.randf_range(5.5, 6.8),
			"floors": 2 if rng.randf() < 0.75 else 1, "roof": k % 2, "timber": rng.randf() < 0.6,
			"ivy": rng.randf() < 0.7, "seed": rng.randi(),
		})
	var md := vd2.rotated(-2.65)
	var mp := vc + md * 46.0
	mill = Vector4(mp.x, height(mp.x, mp.y), mp.y, atan2(-vd2.x, -vd2.y))
	for t: Array in [[1.75, 37.0, 1.25], [-1.75, 36.0, 1.15], [2.98, 39.0, 1.35], [0.2, 40.0, 1.1]]:
		var q := vc + vd2.rotated(float(t[0])) * float(t[1])
		big_trees.append(Vector4(q.x, height(q.x, q.y), q.y, float(t[2])))
	# 出生点左前方一棵（参考图里路边那棵歪脖子树）
	var hp := Vector2(village_dir.x, village_dir.z) * 16.0 - Vector2(village_side.x, village_side.z) * 10.5
	big_trees.append(Vector4(hp.x, height(hp.x, hp.y), hp.y, 1.15))


## 点在房子（含前廊）占地里
func in_house(x: float, z: float, margin := 0.6) -> bool:
	if Vector2(x - village.x, z - village.z).length() > VILLAGE_R:
		return false
	for h: Dictionary in houses:
		var yaw: float = h["yaw"]
		var dx := x - float(h["x"])
		var dz := z - float(h["z"])
		var lx := dx * cos(yaw) - dz * sin(yaw)
		var lz := dx * sin(yaw) + dz * cos(yaw)
		var hw := float(h["w"]) * 0.5 + margin + 0.3
		var front := float(h["d"]) * 0.5 + margin + (2.0 if h["timber"] else 0.3)
		if absf(lx) < hw and lz < front and lz > -float(h["d"]) * 0.5 - margin - 0.3:
			return true
	return false


## 树 / 灌木 / 石头不放的地方：出生点、村子、土路边
func excluded(x: float, z: float, margin: float) -> bool:
	if x * x + z * z < 28.0 * 28.0:
		return true
	if Vector2(x - village.x, z - village.z).length() < VILLAGE_R + 8.0:
		return true
	var pi := path_info(x, z)
	return pi.x < pi.y + margin


## 在 n×n 高度网格上取 (x, z) 处的高度，三角剖分和地块网格一致（每格沿 (0,0)-(1,1) 对角线切两半），
## 所以取到的就是画出来 / 碰撞用的那张面上的高度
static func sample_grid(grid: PackedFloat32Array, n: int, sp: float, x0: float, z0: float, x: float, z: float) -> float:
	var fx := (x - x0) / sp
	var fz := (z - z0) / sp
	var i := clampi(floori(fx), 0, n - 2)
	var j := clampi(floori(fz), 0, n - 2)
	var u := clampf(fx - i, 0.0, 1.0)
	var v := clampf(fz - j, 0.0, 1.0)
	var a := j * n + i
	var h00 := grid[a]
	var h11 := grid[a + n + 1]
	if u >= v:
		var h10 := grid[a + 1]
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	var h01 := grid[a + n]
	return h00 + (h11 - h01) * u + (h01 - h00) * v


# ---------- 地块网格 ----------

## 四条边上的格点下标：上（j=0）、右（i=n-1）、下（j=n-1）、左（i=0）
static func edge_indices(n: int) -> Array[PackedInt32Array]:
	var top := PackedInt32Array()
	var right := PackedInt32Array()
	var bottom := PackedInt32Array()
	var left := PackedInt32Array()
	for t in n:
		top.append(t)
		right.append(t * n + n - 1)
		bottom.append((n - 1) * n + t)
		left.append(t * n)
	return [top, right, bottom, left]


## 一个精度的地块索引（所有同精度地块共用）：网格 + 四条双面裙边
static func make_indices(cells: int) -> PackedInt32Array:
	var n := cells + 1
	var idx := PackedInt32Array()
	idx.resize(cells * cells * 6 + 4 * cells * 12)
	var k := 0
	for j in cells:
		for i in cells:
			var a := j * n + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + n + 1
			idx[k + 3] = a
			idx[k + 4] = a + n + 1
			idx[k + 5] = a + n
			k += 6
	var edges := edge_indices(n)
	var base := n * n
	for e in 4:
		var ed := edges[e]
		for t in cells:
			var g0 := ed[t]
			var g1 := ed[t + 1]
			var s0 := base + e * n + t
			var s1 := s0 + 1
			for v: int in [g0, g1, s1, g0, s1, s0, g0, s1, g1, g0, s0, s1]:
				idx[k] = v
				k += 1
	return idx


## 地块数据（工作线程）：顶点 / 法线（局部坐标，原点在地块西北角）、n×n 高度网格；
## LOD0 另给碰撞三角面；ROCK_LOD 及更细给白石 / 树（含碰撞球 / 树干），BUSH_LOD 及更细给灌木
func build_chunk(key: Vector2i, lod: int) -> Dictionary:
	var cells: int = CELLS[lod]
	var n := cells + 1
	var sp := CHUNK / cells
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var m := n + 2
	var hb := PackedFloat32Array()
	hb.resize(m * m)
	for j in m:
		var z := oz + (j - 1) * sp
		for i in m:
			hb[j * m + i] = height(ox + (i - 1) * sp, z)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n + 4 * n)
	norms.resize(n * n + 4 * n)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			var c := (j + 1) * m + (i + 1)
			var h := hb[c]
			heights[j * n + i] = h
			verts[j * n + i] = Vector3(i * sp, h, j * sp)
			norms[j * n + i] = Vector3(hb[c - 1] - hb[c + 1], 2.0 * sp, hb[c - m] - hb[c + m]).normalized()
	var drop := Vector3(0.0, SKIRT[lod], 0.0)
	var k := n * n
	for ed in edge_indices(n):
		for t in n:
			verts[k] = verts[ed[t]] - drop
			norms[k] = norms[ed[t]]
			k += 1
	var out := {"verts": verts, "norms": norms, "heights": heights, "n": n}
	if lod == 0:
		var faces := PackedVector3Array()
		faces.resize(cells * cells * 6)
		var f := 0
		for j in cells:
			for i in cells:
				var a := j * n + i
				faces[f] = verts[a]
				faces[f + 1] = verts[a + 1]
				faces[f + 2] = verts[a + n + 1]
				faces[f + 3] = verts[a]
				faces[f + 4] = verts[a + n + 1]
				faces[f + 5] = verts[a + n]
				f += 6
		out["faces"] = faces
	if lod <= ROCK_LOD:
		_rocks(key, out)
		_flora(key, lod, out)
	return out


static func _push_xf(buf: PackedFloat32Array, b: Basis, o: Vector3) -> void:
	buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]))


## 坡度（两个方向各走 2 米的高差的较大者）
func _steep(x: float, z: float, h: float) -> float:
	return maxf(absf(height(x + 2.0, z) - h), absf(height(x, z + 2.0) - h)) * 0.5


## 白石（Europa 草原上那种圆润的米白石头）：每块散落几颗半埋的小石头，偶尔一堆大的；高地多一些。
## 位置只由地块编号决定，换精度不会挪
func _rocks(key: Vector2i, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ SEED
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var mk := mask.get_noise_2d(ox + CHUNK * 0.5, oz + CHUNK * 0.5)
	var xf := PackedFloat32Array()
	var balls := PackedVector4Array()
	var singles := rng.randi_range(4, 12)
	var clusters := rng.randi_range(0, 1) + (rng.randi_range(1, 3) if mk > 0.15 else 0)
	var items: Array = []
	for _i in singles:
		items.append([rng.randf_range(4.0, CHUNK - 4.0), rng.randf_range(4.0, CHUNK - 4.0), 0.25 + pow(rng.randf(), 2.5) * 1.2])
	for _c in clusters:
		var px := rng.randf_range(12.0, CHUNK - 12.0)
		var pz := rng.randf_range(12.0, CHUNK - 12.0)
		for r in rng.randi_range(3, 6):
			var s := rng.randf_range(0.6, 1.6) * (rng.randf_range(1.8, 3.0) if r == 0 else 1.0)
			items.append([px + rng.randf_range(-5.0, 5.0), pz + rng.randf_range(-5.0, 5.0), s])
	for it: Array in items:
		var x: float = it[0]
		var z: float = it[1]
		var s: float = it[2]
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(-0.25, 0.25)
		var sx := rng.randf_range(1.0, 1.4)
		var sy := rng.randf_range(0.6, 0.9)
		var sz := rng.randf_range(0.9, 1.3)
		if excluded(ox + x, oz + z, 1.5 + s):
			continue
		var y := height(ox + x, oz + z) - s * 0.3
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3(s * sx, s * sy, s * sz))
		_push_xf(xf, b, Vector3(x, y, z))
		if s > 0.6:
			balls.append(Vector4(x, y + s * 0.2, z, s * 0.75))
	out["rocks"] = xf
	out["balls"] = balls


## 伞形树和灌木：grove 噪声定疏密（成片的小树林 + 零星孤树），陡坡 / 出生点 / 村子 / 土路边不长。
## out["trees"] / out["bushes"]：每个变体一份 MultiMesh 变换缓冲（坐标相对地块原点）；out["trunks"]：树干碰撞 (x, y, z, 半径)
func _flora(key: Vector2i, lod: int, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ (SEED * 3)
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var trees: Array = []
	for _v in TREE_VARIANTS:
		trees.append(PackedFloat32Array())
	var bushes: Array = []
	for _v in BUSH_VARIANTS:
		bushes.append(PackedFloat32Array())
	var trunks := PackedVector4Array()
	for _i in 16:
		var x := rng.randf_range(4.0, CHUNK - 4.0)
		var z := rng.randf_range(4.0, CHUNK - 4.0)
		var v := rng.randi() % TREE_VARIANTS
		var s := rng.randf_range(0.8, 1.3)
		var yaw := rng.randf() * TAU
		var roll := rng.randf()
		var g := grove.get_noise_2d(ox + x, oz + z)
		if roll > 0.04 + ss(0.05, 0.5, g) * 0.7:
			continue
		if excluded(ox + x, oz + z, 6.0):
			continue
		var h := height(ox + x, oz + z)
		if h > 260.0 or _steep(ox + x, oz + z, h) > 0.45:
			continue
		var buf: PackedFloat32Array = trees[v]
		_push_xf(buf, Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, h - 0.15, z))
		trees[v] = buf
		trunks.append(Vector4(x, h, z, 0.42 * s))
	if lod <= BUSH_LOD:
		for _i in 26:
			var x := rng.randf_range(2.0, CHUNK - 2.0)
			var z := rng.randf_range(2.0, CHUNK - 2.0)
			var v := rng.randi() % BUSH_VARIANTS
			var s := rng.randf_range(0.7, 1.4)
			var yaw := rng.randf() * TAU
			var roll := rng.randf()
			var g := grove.get_noise_2d(ox + x, oz + z)
			if roll > 0.12 + ss(-0.1, 0.5, g) * 0.55:
				continue
			if excluded(ox + x, oz + z, 2.5):
				continue
			var h := height(ox + x, oz + z)
			if h > 280.0 or _steep(ox + x, oz + z, h) > 0.6:
				continue
			var buf: PackedFloat32Array = bushes[v]
			_push_xf(buf, Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s)), Vector3(x, h - 0.1, z))
			bushes[v] = buf
	out["trees"] = trees
	out["bushes"] = bushes
	out["trunks"] = trunks


## 远景整张网格（世界坐标，覆盖整个 24 公里见方的世界），没加载细地块的地方由它顶着
func build_horizon(cells: int) -> Dictionary:
	var n := cells + 1
	var sp := WORLD_HALF * 2.0 / cells
	var o := -WORLD_HALF
	var m := n + 2
	var hb := PackedFloat32Array()
	hb.resize(m * m)
	for j in m:
		for i in m:
			hb[j * m + i] = height(o + (i - 1) * sp, o + (j - 1) * sp)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var c := (j + 1) * m + (i + 1)
			verts[j * n + i] = Vector3(o + i * sp, hb[c], o + j * sp)
			norms[j * n + i] = Vector3(hb[c - 1] - hb[c + 1], 2.0 * sp, hb[c - m] - hb[c + m]).normalized()
	var idx := PackedInt32Array()
	idx.resize(cells * cells * 6)
	var k := 0
	for j in cells:
		for i in cells:
			var a := j * n + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + n + 1
			idx[k + 3] = a
			idx[k + 4] = a + n + 1
			idx[k + 5] = a + n
			k += 6
	return {"verts": verts, "norms": norms, "idx": idx}


## 采一张规则高度网格（预览世界 / 出生点附近没有地块数据时给草地用）
func sample_rect(x0: float, z0: float, n: int, sp: float) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(n * n)
	for j in n:
		for i in n:
			g[j * n + i] = height(x0 + i * sp, z0 + j * sp)
	return g


# ---------- 草地 ----------

## 草丛摆放模板：TILE 见方里 count 丛草的 [x, z, 3×3 基]（随机朝向同 GrassMesh.gd 的 ±90°、随机高矮）。
## 所有草地块共用几份模板，只按地面高度换 y
static func make_pattern(count: int, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := PackedFloat32Array()
	out.resize(count * 11)
	for k in count:
		var s := rng.randf_range(0.85, 1.15)
		var b := Basis(Vector3.UP, rng.randf_range(-PI / 2.0, PI / 2.0))
		b = b * Basis.from_scale(Vector3(BLADE_W * s, BLADE_H * s * rng.randf_range(0.8, 1.2), BLADE_W * s))
		var o := k * 11
		out[o] = rng.randf() * TILE
		out[o + 1] = rng.randf() * TILE
		out[o + 2] = b.x.x
		out[o + 3] = b.y.x
		out[o + 4] = b.z.x
		out[o + 5] = b.x.y
		out[o + 6] = b.y.y
		out[o + 7] = b.z.y
		out[o + 8] = b.x.z
		out[o + 9] = b.y.z
		out[o + 10] = b.z.z
	return out


## 这块草地要不要逐株让路 / 让房子（大部分草地块离路和村子很远，直接跳过检查）
func _tile_near(tile: Vector2i) -> Vector2:
	var cx := (tile.x + 0.5) * TILE
	var cz := (tile.y + 0.5) * TILE
	var near_path := path_info(cx, cz).x < TILE + 6.0
	var near_village := Vector2(cx - village.x, cz - village.z).length() < VILLAGE_R + TILE
	return Vector2(1.0 if near_path else 0.0, 1.0 if near_village else 0.0)


## 植株在 (x, z) 处的保留比例：土路 / 村中空地 / 房子里是 0，路边逐渐长高
func _keep(x: float, z: float, near: Vector2) -> float:
	var k := 1.0
	if near.x > 0.0:
		var pi := path_info(x, z)
		k = ss(pi.y - 0.3, pi.y + 1.1, pi.x)
	if near.y > 0.0:
		var dp := Vector2(x - plaza.x, z - plaza.y).length()
		k = minf(k, ss(plaza.z - 0.5, plaza.z + 1.2, dp))
		if k > 0.0 and in_house(x, z, 0.2):
			k = 0.0
	return k


## 一块草地（工作线程）：tile 的世界原点 (tx, tz)，高度取自网格 grid（n×n、间距 sp、原点 (gx, gz)）。
## 返回 grass（MultiMesh 3D 变换缓冲，坐标相对草地块原点；y 是世界高度）、tall / flowers（flower_field 的两种植株，
## 带颜色：缓冲 16 浮点一株）、patches（花丛中心，给蝴蝶用）。陡坡（地面着色器那里会变岩壁）上不长草，土路上不长草
func build_tile(tile: Vector2i, grid: PackedFloat32Array, n: int, sp: float, gx: float, gz: float,
		pattern: PackedFloat32Array) -> Dictionary:
	var tx := tile.x * TILE
	var tz := tile.y * TILE
	var near := _tile_near(tile)
	var check := near.x > 0.0 or near.y > 0.0
	var count := int(pattern.size() / 11.0)
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	var w := 0
	for k in count:
		var o := k * 11
		var lx := pattern[o]
		var lz := pattern[o + 1]
		var x := tx + lx
		var z := tz + lz
		var y := sample_grid(grid, n, sp, gx, gz, x, z)
		var gxd := sample_grid(grid, n, sp, gx, gz, x + 1.0, z) - y
		var gzd := sample_grid(grid, n, sp, gx, gz, x, z + 1.0) - y
		if gxd * gxd + gzd * gzd > 0.85:
			continue  # 坡度超过约 43°
		var f := 1.0
		if check:
			f = _keep(x, z, near)
			if f < 0.2:
				continue
		buf[w] = pattern[o + 2] * f
		buf[w + 1] = pattern[o + 3] * f
		buf[w + 2] = pattern[o + 4] * f
		buf[w + 3] = lx
		buf[w + 4] = pattern[o + 5] * f
		buf[w + 5] = pattern[o + 6] * f
		buf[w + 6] = pattern[o + 7] * f
		buf[w + 7] = y - 0.04
		buf[w + 8] = pattern[o + 8] * f
		buf[w + 9] = pattern[o + 9] * f
		buf[w + 10] = pattern[o + 10] * f
		buf[w + 11] = lz
		w += 12
	buf.resize(w)
	var out := {"grass": buf}
	_flowers(tile, grid, n, sp, gx, gz, near, out)
	return out


static func _plant(arr: PackedFloat32Array, s: float, x: float, y: float, z: float, c: float) -> void:
	arr.append_array(PackedFloat32Array([s, 0.0, 0.0, x, 0.0, s, 0.0, y, 0.0, 0.0, s, z, c, 0.0, 0.0, 1.0]))


func _petal(rng: RandomNumberGenerator) -> float:
	var r := rng.randf()
	for i in PETALS.size():
		r -= PETAL_W[i]
		if r <= 0.0:
			return PETALS[i]
	return PETALS[0]


## 花和草簇（Europa 那种：一小撮一小撮同色的花点缀在草里）：
## · 每块草地按 bloom 噪声出 1~7 撮花，一撮 3~10 朵同色（红 / 白 / 淡紫 / 蓝 / 粉 / 珊瑚），flower_field 的 flower_1 模型；
## · 几丛深一点的长草簇（flower_field 的 tall_grass_group）；
## · 偶尔一整丛原版 flower_field（generate() 的算法原样搬过来）。
## 植株的 COLOR.x 交给 waving_mesh 着色器：转朝向 + 在颜色表里取花瓣色（茎叶取表的前半段绿色）
func _flowers(tile: Vector2i, grid: PackedFloat32Array, n: int, sp: float, gx: float, gz: float, near: Vector2,
		out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tile) ^ (SEED * 7)
	var check := near.x > 0.0 or near.y > 0.0
	var tx := tile.x * TILE
	var tz := tile.y * TILE
	var tall := PackedFloat32Array()
	var flowers := PackedFloat32Array()
	var centers := PackedVector3Array()
	var bl := bloom.get_noise_2d(tx + TILE * 0.5, tz + TILE * 0.5)
	var groups := 1 + int(ss(-0.4, 0.6, bl) * 6.0)
	for _g in groups:
		var cx := tx + rng.randf_range(2.0, TILE - 2.0)
		var cz := tz + rng.randf_range(2.0, TILE - 2.0)
		var c := _petal(rng)
		var cnt := rng.randi_range(3, 10)
		var rad := rng.randf_range(0.6, 2.2)
		var placed := 0
		for _i in cnt:
			var v := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * rad
			var s := rng.randf_range(0.8, 1.15) * FLOWER_SCALE
			var cj := c + rng.randf_range(-0.025, 0.025)
			var x := cx + v.x
			var z := cz + v.y
			if check and _keep(x, z, near) < 0.9:
				continue
			_plant(flowers, s, x - tx, sample_grid(grid, n, sp, gx, gz, x, z) - 0.03, z - tz, cj)
			placed += 1
		if placed > 3:
			centers.append(Vector3(cx, sample_grid(grid, n, sp, gx, gz, cx, cz), cz))
	for _t in rng.randi_range(3, 9):
		var x := tx + rng.randf_range(0.5, TILE - 0.5)
		var z := tz + rng.randf_range(0.5, TILE - 0.5)
		var s := rng.randf_range(0.7, 1.05)
		var c := rng.randf()
		if check and _keep(x, z, near) < 0.9:
			continue
		_plant(tall, s, x - tx, sample_grid(grid, n, sp, gx, gz, x, z) - 0.03, z - tz, c)
	if rng.randf() < PATCH_P:
		_flower_patch(tile, grid, n, sp, gx, gz, near, rng, tall, flowers, centers)
	out["tall"] = tall
	out["flowers"] = flowers
	out["patches"] = centers


## flower_field.gd 的 generate() 搬过来：size 米见方、每米 3 格抖动采样，圆盘内保留，越靠中心越大，
## noise 起伏控制大小；96% 长草丛 tall_grass_group（base_scale 0.6）、4% 小花 flower_1（0.8），每株随机 COLOR.x。
## 这里只是把整丛挪到草地块里的随机位置，按地面高度落地
func _flower_patch(tile: Vector2i, grid: PackedFloat32Array, n: int, sp: float, gx: float, gz: float, near: Vector2,
		rng: RandomNumberGenerator, tall: PackedFloat32Array, flowers: PackedFloat32Array, centers: PackedVector3Array) -> void:
	var check := near.x > 0.0 or near.y > 0.0
	var size := rng.randf_range(7.0, 11.0)
	var cx := tile.x * TILE + rng.randf_range(size * 0.5, TILE - size * 0.5)
	var cz := tile.y * TILE + rng.randf_range(size * 0.5, TILE - size * 0.5)
	var res := int(size * 3.0)
	var total := res * res
	for i in total:
		var v := Vector2.from_angle(rng.randf() * TAU) / float(res) * rng.randf() * 0.5
		v.x += (i % res) / float(res)
		v.y += floorf(i / float(res)) / float(res)
		v -= Vector2(0.5, 0.5)
		var dist := 1.0 - v.length()
		if dist < 0.5:
			continue
		v *= size
		var nz := petal.get_noise_2d(v.x * 40.0, v.y * 40.0)
		var scale_factor := remap(nz, -1.0, 1.0, 0.5, 1.5) * 0.5
		var is_flower := rng.randf() < 0.04
		var s := (0.8 if is_flower else 0.6) * scale_factor * dist * 2.0 * PATCH_SCALE
		var x := cx + v.x
		var z := cz + v.y
		var c := rng.randf()
		if check and _keep(x, z, near) < 0.9:
			continue
		var y := sample_grid(grid, n, sp, gx, gz, x, z) - 0.03
		_plant(flowers if is_flower else tall, s, x - tile.x * TILE, y, z - tile.y * TILE, c)
	centers.append(Vector3(cx, sample_grid(grid, n, sp, gx, gz, cx, cz), cz))
