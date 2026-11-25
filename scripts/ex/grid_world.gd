extends "res://scripts/block_world.gd"
## 搜打撤 PvP 新图的方块世界（2026-11-24，SPEC 第 5 节）：沙海古墟 / 天工秘所，数据来自 map_def.gd。
## 继承 block_world.gd：网格生成（_build / _mesh_row / _compose）、分块调度（细 / 粗地块 + 远景色块、单线程分帧、工作线程）、
## 实心盒子的查询（solid_h / solid_any）全部复用；这里只换掉「格子从哪来」和「长什么样」：
##   · 地形：载入时一次烘好每层一张 2 米格的高度 / 区域 / 地表表（setup()），_cell / height / _shaped / _region 都是查表
##     （比大世界的噪声取样快一个量级）。两层（地面 / 洞窟）放在同一张图的两片坐标（x > 600 的是洞窟 / 地下室，见 map_def.gd），
##     active_layer 决定排哪一层的块（_key_ok），另一层整个不建
##   · 建筑 / 遗迹 / 洞窟顶 / 灯火：载入时一次摆好，几何按 96 米的地块分组，地块生成时并进那一块的网格（_props，一块一次绘制调用）；
##     实心盒子全图静态登记一次（STATIC_KEY，不跟着细地块走），怪 / AI / 主角在哪都问得到
##   · 屋顶 / 二层楼板 / 钥匙房的盖板：每栋楼单独一个网格（_roofs），主角进了这栋楼的占地框就藏起来（update_roofs）
##   · 钥匙房的门：单独的网格 + 单独的实心盒子（_doors），set_door(id, open) 开关（门板沉进地里）
##   · 不破坏地形（dig / crater_changes 空实现），没有垫底的水面（_want_sea = false）
##   · 边界的样子：沙漠一圈沙暴幕、研究所墙头一圈禁制光幕（_build_boundary，透明的普通材质，不新加着色器）
## 小地图的整图底图：bake_map(layer)（ex_level.gd 载入时烘一次）。
## 故意不写 class_name：用 preload 引用。

const MapDef := preload("res://scripts/ex/map_def.gd")

const STATIC_KEY := Vector2i(999999, 999999)    # 全图静态实心盒子的登记名（不是任何地块，_plan 不会撤）
const DOOR_KEY0 := 800000                       # 门：Vector2i(DOOR_KEY0 + 序号, 0)

var map_id := "desert"
var map: Dictionary = {}
var active_layer := "surface"
var lab := false

## 地形表（每层一份，都放在成员变量里：Packed 数组是写时复制的，放进字典 / 闭包再改会整张拷一遍）
## _s_* = 地面层，_c_* = 洞窟层：h 高度、r 区域、k 地表（低 4 位 K_*，第 5 位 = 石板地）、c 洞顶（只有洞窟有）
var _s_x0 := 0
var _s_z0 := 0
var _s_w := 1
var _s_d := 1
var _c_x0 := 0
var _c_z0 := 0
var _c_w := 1
var _c_d := 1
var _s_h := PackedFloat32Array()
var _s_r := PackedByteArray()
var _s_k := PackedByteArray()
var _c_h := PackedFloat32Array()
var _c_r := PackedByteArray()
var _c_k := PackedByteArray()
var _c_c := PackedFloat32Array()
var _rects: Array[Rect2] = [Rect2(), Rect2()]
var _base_y := 20.0
## 静态几何：地块 → [顶点, 法线, 颜色, 索引]（细地块用 _sgeo，粗地块只并大件 _sshell）
var _sgeo := {}
var _sshell := {}
var _srec := PackedFloat32Array()      # 静态实心盒子（每 9 个数一条，格式同 block_world._box）
var _lmap := {}                         # 地块 → 灯火 [[位置, 区域, 种类], ...]
## 屋顶 / 楼板：[{id, rect（占地，外墙）, y0（底面）, geo, node, hidden}]
var _roofs: Array = []
var _tgt_roof := -1
## 门：id → {key, rec, node, open, t, y0, h}
var _doors := {}
var boundary: Node3D
var _rng := RandomNumberGenerator.new()
var gen_ms := 0.0                       # 载入时烘表 + 摆件用了多久（自检看）
var static_boxes := 0

# 配色（sRGB）
const SAND_ST := Color(0.84, 0.72, 0.52)
const SAND_D := Color(0.72, 0.58, 0.40)
const MUD := Color(0.80, 0.64, 0.44)
const GOLD := Color(0.95, 0.78, 0.38)
const TEAL := Color(0.22, 0.52, 0.52)
const RED := Color(0.62, 0.22, 0.16)
const DARK := Color(0.07, 0.055, 0.05)
const TIMBER := Color(0.40, 0.27, 0.17)
const FLAME := Color(1.0, 0.62, 0.25)
const CRYSTAL := Color(0.45, 0.85, 1.0)
const CONC := Color(0.75, 0.74, 0.71)
const CONC_D := Color(0.62, 0.61, 0.58)
const IRON := Color(0.36, 0.33, 0.31)
const RUST := Color(0.56, 0.34, 0.21)
const BRONZE := Color(0.72, 0.53, 0.28)
const BRONZE_D := Color(0.50, 0.36, 0.20)
const VERM := Color(0.68, 0.17, 0.12)
const WOOD := Color(0.42, 0.28, 0.18)
const TILE := Color(0.24, 0.26, 0.30)
const GLASS := Color(0.22, 0.32, 0.38)
const LAMP := Color(0.72, 0.95, 1.0)
const GREEN_GLOW := Color(0.45, 1.0, 0.6)

const STOREY := 5.5      # 研究所的层高（SPEC：≥ 4.5）
const WALL_T := 0.8
const DOOR_H := 4.6


# ---------- 初始化 ----------

## 父类 _init 会调这个：新图的内容要等 setup(map_id) 才知道，这里什么都不建（不建天南的路网 / 地标）
func _setup_content() -> void:
	pass


## 载入：烘地形表、摆建筑、登记实心盒子（add_child 之前调；ex_level.gd 在 _ready 里调）
func setup(id: String) -> void:
	var t0 := Time.get_ticks_usec()
	map_id = id
	lab = id == "lab"
	map = MapDef.map(id)
	_base_y = float(map["base_y"])
	_rng.seed = 1234 if lab else 4321
	_mid.seed = 311
	_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mid.frequency = 1.0 / 76.0
	_mid.fractal_octaves = 1
	_init_pal()
	_sun_dirs.clear()
	for i in 5:
		_sun_dirs.append(Vector3(0.45, 0.74, 0.5).normalized())
	var lays: Dictionary = map["layers"]
	_new_layer(0, (lays["surface"] as Dictionary)["grid"])
	_new_layer(1, (lays["cavern"] as Dictionary)["grid"])
	if lab:
		_gen_lab()
	else:
		_gen_desert()
	_sol_put(STATIC_KEY, _sol_pack(_srec), Vector3.ZERO)
	static_boxes = _srec.size() / SOL_REC
	gen_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _ready() -> void:
	super()
	_build_nodes()
	set_layer(active_layer)


func _want_sea() -> bool:
	return false


## 只排当前这一层（地面 / 洞窟）矩形里的块
func _key_ok(key: Vector2i) -> bool:
	var lay: Dictionary = (map["layers"] as Dictionary).get(active_layer, {})
	if lay.is_empty():
		return true
	var g: Rect2 = lay["grid"]
	var kr := Rect2(float(key.x) * CHUNK, float(key.y) * CHUNK, CHUNK, CHUNK)
	return kr.intersects(g)


## 换层（进出洞窟）：只排那一层的块；洞窟里看不远，粗地块少一圈、不铺色块
func set_layer(ln: String) -> void:
	active_layer = ln
	if not is_inside_tree():
		return
	var cav := ln == "cavern"
	if cav:
		view_r = 2
		far_r = 0
	else:
		view_r = 3 if _sliced else (4 if mobile else 6)
		far_r = 6 if (_sliced or mobile) else 8
	_replan = 0.0
	_last_key = Vector2i(1 << 20, 0)


func lod0_count() -> int:
	var n := 0
	for k: Vector2i in _chunks:
		if int((_chunks[k] as Dictionary)["lod"]) == 0:
			n += 1
	return n


# ---------- 地形表 ----------

func _new_layer(li: int, g: Rect2) -> void:
	var w := int(g.size.x / CELL)
	var d := int(g.size.y / CELL)
	var x0 := int(floorf(g.position.x / CELL))
	var z0 := int(floorf(g.position.y / CELL))
	_rects[li] = g
	if li == 0:
		_s_x0 = x0
		_s_z0 = z0
		_s_w = w
		_s_d = d
		_s_h.resize(w * d)
		_s_h.fill(_base_y)
		_s_r.resize(w * d)
		_s_r.fill(0)
		_s_k.resize(w * d)
		_s_k.fill(0)
	else:
		_c_x0 = x0
		_c_z0 = z0
		_c_w = w
		_c_d = d
		_c_h.resize(w * d)
		_c_h.fill(_base_y)
		_c_r.resize(w * d)
		_c_r.fill(0)
		_c_k.resize(w * d)
		_c_k.fill(0)
		_c_c.resize(w * d)
		_c_c.fill(0.0)


## 某个 2 米格在哪一层、表里第几项：Vector2i(层, 下标)。两层都不在（两层之间的空地，不会建块）：夹到最近那层的边上
func _idx(ix: int, iz: int) -> Vector2i:
	var lx := ix - _s_x0
	var lz := iz - _s_z0
	if lx >= 0 and lz >= 0 and lx < _s_w and lz < _s_d:
		return Vector2i(0, lz * _s_w + lx)
	var cx := ix - _c_x0
	var cz := iz - _c_z0
	if cx >= 0 and cz >= 0 and cx < _c_w and cz < _c_d:
		return Vector2i(1, cz * _c_w + cx)
	if absi(ix - clampi(ix, _c_x0, _c_x0 + _c_w - 1)) < absi(ix - clampi(ix, _s_x0, _s_x0 + _s_w - 1)):
		return Vector2i(1, clampi(cz, 0, _c_d - 1) * _c_w + clampi(cx, 0, _c_w - 1))
	return Vector2i(0, clampi(lz, 0, _s_d - 1) * _s_w + clampi(lx, 0, _s_w - 1))


func _hv(v: Vector2i) -> float:
	return _s_h[v.y] if v.x == 0 else _c_h[v.y]


func _rv(v: Vector2i) -> int:
	return _s_r[v.y] if v.x == 0 else _c_r[v.y]


func _kv(v: Vector2i) -> int:
	return _s_k[v.y] if v.x == 0 else _c_k[v.y]


func height(x: float, z: float) -> float:
	var hx := int(floorf(x / CELL))
	var hz := int(floorf(z / CELL))
	var hh := _hv(_idx(hx, hz))
	if not _dug.is_empty():
		# 2026-11-25 场景破坏：被炸开的格子（破坏表里记的是高度上限）
		var dv: Variant = _dug.get(Vector2i(hx, hz))
		if dv != null:
			hh = minf(hh, float(dv))
	return hh


## 2026-11-25：这两个在工作线程里也会被调（远景的烘焙日影 _sun_blocked），只查原始的表、不看破坏表
## （破坏表在主线程整表替换，工作线程不能直接读成员；height() 只在主线程用）
func _shaped(x: float, z: float) -> float:
	return _hv(_idx(int(floorf(x / CELL)), int(floorf(z / CELL))))


func _raw(x: float, z: float) -> float:
	return _hv(_idx(int(floorf(x / CELL)), int(floorf(z / CELL))))


func _region(x: float, z: float, _jit: float) -> int:
	return _rv(_idx(int(floorf(x / CELL)), int(floorf(z / CELL))))


func has_land(_key: Vector2i) -> bool:
	return true


## 洞顶高度（地面层没有：返回很大的数；洞窟里的岩体：岩顶）
func ceil_at(x: float, z: float) -> float:
	var v := _idx(int(floorf(x / CELL)), int(floorf(z / CELL)))
	if v.x == 0:
		return 1.0e9
	var c := _c_c[v.y]
	return c if c > 0.0 else _c_h[v.y]


func _cell(ix: int, iz: int, cs: float, dug_in: Dictionary) -> Array:
	if cs != CELL:
		ix = int(floorf((float(ix) + 0.5) * cs / CELL))
		iz = int(floorf((float(iz) + 0.5) * cs / CELL))
	var v := _idx(ix, iz)
	var k := _kv(v)
	if not dug_in.is_empty():
		# 2026-11-25 场景破坏：炸开的格子按破坏表压低，露出来的是生土（不再是石板 / 路面）
		var dv: Variant = dug_in.get(Vector2i(ix, iz))
		if dv != null and float(dv) < _hv(v) - 0.01:
			return [float(dv), _rv(v), false, false, 0]
	return [_hv(v), _rv(v), false, (k & 16) != 0, k & 15]


## 2026-11-25 场景破坏（destruct.gd）：斗法能炸坑了（crater_changes / apply_dug，见文件末尾「场景破坏」）；
## 飞行破开山体的平底通道（dig）新图里仍然不做（洞窟 / 楼里飞着把墙脚削平不像话）
func dig(_center: Vector3, _radius: float, _floor_y: float) -> int:
	return 0


func _wall_props(_a: Array, _hs: PackedFloat32Array, _rg: PackedInt32Array, _fl: PackedInt32Array, _m: int, _n: int, _bx: int, _bz: int) -> void:
	pass


func _falls(_a: Array, _hs: PackedFloat32Array, _rg: PackedInt32Array, _fl: PackedInt32Array, _m: int, _n: int, _bx: int, _bz: int, _cs: float) -> void:
	pass


func _lights(key: Vector2i, _dug: Dictionary) -> Array:
	return _lmap.get(key, [])


## 灯火烘到地上的颜色：火盆 / 火把（种类 2）暖橙；晶簇（种类 1）在洞里压暗一半（洞里底色暗，原样烘会把地面照成一片白）
func _light_col(ri: int, kind: int) -> Color:
	if kind == 2:
		return Color(1.0, 0.64, 0.28)
	var c: Color = _pal[ri][5]
	return c * 0.45 if (kind == 1 and (ri == 2 or ri == 4)) else c


## 地块生成时（工作线程）：把载入时摆好的这一块的建筑 / 遗迹 / 洞顶几何原样并进来（细地块全要，粗地块只要大件）
func _props(key: Vector2i, lod: int, a: Array, _dug: Dictionary) -> void:
	# 2026-11-25 场景破坏：摆件被打坏过的地块，摆件另起一张网格（_dx_split），地表这张不再带；主线程换表时上锁
	_geo_lock.lock()
	var src: Variant = null if _dx_split.has(key) else (_sgeo if lod == 0 else _sshell).get(key)
	_geo_lock.unlock()
	if src == null:
		return
	var g: Array = src
	var v: PackedVector3Array = a[0]
	var base := v.size()
	v.append_array(g[0])
	a[0] = v
	var nr: PackedVector3Array = a[1]
	nr.append_array(g[1])
	a[1] = nr
	var cl: PackedColorArray = a[2]
	cl.append_array(g[2])
	a[2] = cl
	var ix: PackedInt32Array = a[3]
	var gi: PackedInt32Array = g[3]
	var o := ix.size()
	ix.resize(o + gi.size())
	for q in gi.size():
		ix[o + q] = gi[q] + base
	a[3] = ix


# ---------- 实心盒子的查询（补 block_world 没有的：头顶、点在不在盒子里） ----------

## (x, z) 上方：底面不低于 above 的实心盒子里，最低的那个底面（头顶的天花板）。没有返回很大的数
func solid_ceil(x: float, z: float, above: float) -> float:
	var e: Variant = _scells.get(Vector2i(int(floorf(x / SOL_CELL)), int(floorf(z / SOL_CELL))))
	var best := 1.0e9
	if e == null:
		return best
	for s: PackedFloat32Array in (e as Dictionary).values():
		var i := 0
		var n := s.size()
		while i < n:
			var bot := s[i + 6]
			if bot >= above and bot < best:
				var dx := x - s[i]
				var dz := z - s[i + 1]
				if absf(dx * s[i + 2] + dz * s[i + 3]) <= 1.0 and absf(dx * s[i + 4] + dz * s[i + 5]) <= 1.0:
					best = bot
			i += 8
	return best


## p 在不在某个实心盒子里
func solid_box_at(p: Vector3) -> bool:
	var e: Variant = _scells.get(Vector2i(int(floorf(p.x / SOL_CELL)), int(floorf(p.z / SOL_CELL))))
	if e == null:
		return false
	for s: PackedFloat32Array in (e as Dictionary).values():
		var i := 0
		var n := s.size()
		while i < n:
			if p.y >= s[i + 6] and p.y <= s[i + 7]:
				var dx := p.x - s[i]
				var dz := p.z - s[i + 1]
				if absf(dx * s[i + 2] + dz * s[i + 3]) <= 1.0 and absf(dx * s[i + 4] + dz * s[i + 5]) <= 1.0:
					return true
			i += 8
	return false


# ---------- 配色 ----------

func _init_pal() -> void:
	_pal.clear()
	var rows: Array
	if lab:
		rows = [
			[Color(0.64, 0.63, 0.60), Color(0.70, 0.69, 0.66), Color(0.52, 0.47, 0.42), Color(0.60, 0.60, 0.58), Color(0.3, 0.5, 0.6), Color(0.62, 0.92, 1.0)],
			[Color(0.40, 0.48, 0.30), Color(0.48, 0.54, 0.32), Color(0.46, 0.40, 0.32), Color(0.56, 0.55, 0.52), Color(0.3, 0.5, 0.6), Color(0.62, 0.92, 1.0)],
			[Color(0.30, 0.34, 0.32), Color(0.36, 0.40, 0.36), Color(0.26, 0.28, 0.26), Color(0.34, 0.37, 0.35), Color(0.3, 0.5, 0.6), Color(0.50, 1.0, 0.70)],
			[Color(0.62, 0.50, 0.34), Color(0.70, 0.57, 0.38), Color(0.50, 0.40, 0.30), Color(0.66, 0.55, 0.40), Color(0.3, 0.5, 0.6), Color(1.0, 0.70, 0.35)],
			[Color(0.26, 0.26, 0.28), Color(0.30, 0.30, 0.32), Color(0.22, 0.22, 0.24), Color(0.30, 0.30, 0.32), Color(0.3, 0.5, 0.6), Color(0.50, 1.0, 0.70)],
		]
	else:
		rows = [
			[Color(0.86, 0.71, 0.47), Color(0.92, 0.79, 0.54), Color(0.74, 0.55, 0.34), Color(0.80, 0.66, 0.46), Color(0.3, 0.55, 0.6), Color(1.0, 0.70, 0.36)],
			[Color(0.72, 0.44, 0.30), Color(0.80, 0.52, 0.34), Color(0.62, 0.36, 0.24), Color(0.66, 0.40, 0.28), Color(0.3, 0.55, 0.6), Color(1.0, 0.62, 0.28)],
			[Color(0.40, 0.33, 0.28), Color(0.46, 0.38, 0.31), Color(0.32, 0.26, 0.22), Color(0.42, 0.36, 0.32), Color(0.3, 0.55, 0.6), Color(0.45, 0.85, 1.0)],
			[Color(0.86, 0.69, 0.38), Color(0.92, 0.77, 0.44), Color(0.76, 0.58, 0.30), Color(0.76, 0.61, 0.36), Color(0.3, 0.55, 0.6), Color(1.0, 0.78, 0.36)],
			[Color(0.30, 0.25, 0.24), Color(0.34, 0.28, 0.26), Color(0.26, 0.21, 0.20), Color(0.34, 0.28, 0.27), Color(0.3, 0.55, 0.6), Color(1.0, 0.62, 0.30)],
		]
	for r: Array in rows:
		_pal.append(r)


func _top_color(ri: int, kind: int, x0: float, z0: float, y: float, hi: float, hsh: float, _st: float) -> Color:
	var j := 0.9 + 0.2 * hsh
	if ri == 2 or ri == 4:
		j = 0.94 + 0.12 * hsh
	var pal: Array = _pal[ri]
	var pn := clampf(0.5 + _mid.get_noise_2d(x0 * 2.3 + 40.0, z0 * 2.3) * 1.4 + (hsh - 0.5) * 0.4, 0.0, 1.0)
	match kind:
		K_PATH:
			if lab:
				return Color(0.52, 0.42, 0.33).lerp(Color(0.46, 0.40, 0.34), pn) * j
			return (Color(0.48, 0.42, 0.34) if hsh > 0.82 else Color(0.64, 0.55, 0.43).lerp(Color(0.58, 0.50, 0.40), pn)) * j
		K_ROAD:
			return _masonry(ri, 0.0) * (0.94 + 0.1 * hsh)
		K_ROAD_EDGE:
			return (Color(0.70, 0.60, 0.40) if lab else _masonry(ri, 0.0) * 0.8) * (0.92 + 0.1 * hsh)
		K_RIM:
			return (pal[2] as Color) * j
	if lab:
		match ri:
			0:
				# 混凝土场地：8 米一块的分缝（暗一线）+ 零星的锈水渍
				var c0 := (pal[0] as Color).lerp(pal[1] as Color, pn * 0.6)
				if pn < 0.12:
					c0 = c0.lerp(Color(0.52, 0.44, 0.36), 0.4)
				var gx := int(floorf(x0 / CELL))
				var gz := int(floorf(z0 / CELL))
				if posmod(gx, 4) == 0 or posmod(gz, 4) == 0:
					c0 = c0 * 0.92
				return c0 * (0.95 + 0.1 * hsh)
			3:
				var tile := 1.06 if (int(floorf(x0 / CELL)) + int(floorf(z0 / CELL))) % 2 == 0 else 0.94
				return (pal[0] as Color).lerp(pal[1] as Color, hsh) * tile
		return (pal[0] as Color).lerp(pal[1] as Color, pn) * j
	match ri:
		0:
			# 沙丘：迎着日头的沙坡亮、背坡暗一点（按高度起伏抖一抖）
			# 沙丘：一道道风纹（斜着的明暗条）+ 按高度起伏抖一抖；低处的沙暗一点、偏红
			var dune := 0.95 + 0.07 * sin(y * 1.3 + x0 * 0.05) + 0.05 * sin((x0 * 0.8 + z0 * 0.45) * 0.55)
			var c0 := (pal[0] as Color).lerp(pal[1] as Color, pn)
			if y < _base_y - 0.5:
				c0 = c0.lerp(Color(0.78, 0.56, 0.38), 0.35)
			return c0 * j * dune
		1:
			if hi >= 4.0:
				return (pal[2] as Color) * j
			return (pal[0] as Color).lerp(pal[1] as Color, pn) * j
		3:
			return (pal[0] as Color).lerp(pal[1] as Color, hsh * 0.7 + pn * 0.3) * j
	return (pal[0] as Color).lerp(pal[1] as Color, pn) * j


func _wall_color(ri: int, ym: float, hsh: float, _st: float, _colh := 0.5) -> Color:
	var j := 0.9 + 0.2 * hsh
	if lab:
		match ri:
			0:
				var layer := int(floorf(ym / 4.0))
				if posmod(layer, 4) == 3:
					return IRON * j
				return (Color(0.72, 0.71, 0.68) if (layer & 1) == 0 else Color(0.66, 0.65, 0.62)) * j
			1:
				return Color(0.52, 0.48, 0.42) * j
			2:
				return Color(0.32, 0.34, 0.32) * j
			3:
				return (GOLD * 0.8 if posmod(int(floorf(ym)), 3) == 0 else Color(0.56, 0.44, 0.30)) * j
		var l4 := int(floorf(ym / 3.0))
		return (Color(0.28, 0.28, 0.30) if (l4 & 1) == 0 else Color(0.24, 0.24, 0.26)) * j
	match ri:
		0:
			var l0 := int(floorf(ym / 2.0))
			return (Color(0.82, 0.68, 0.46) if (l0 & 1) == 0 else Color(0.76, 0.62, 0.42)) * j
		1:
			var l1 := int(floorf(ym / 4.0))
			if posmod(l1, 5) == 2:
				return Color(0.80, 0.56, 0.38) * j
			return (Color(0.70, 0.38, 0.26) if (l1 & 1) == 0 else Color(0.60, 0.32, 0.22)) * j
		2:
			return Color(0.34, 0.28, 0.24) * j
		3:
			if posmod(int(floorf(ym)), 3) == 0:
				return Color(0.97, 0.82, 0.46) * j
			return Color(0.86, 0.68, 0.34) * j
	var l4b := int(floorf(ym / 3.0))
	if posmod(l4b, 6) == 4:
		return Color(0.34, 0.40, 0.48) * j      # 晶脉
	return (Color(0.31, 0.26, 0.25) if (l4b & 1) == 0 else Color(0.26, 0.22, 0.21)) * j


func _masonry(_ri: int, _st: float) -> Color:
	return Color(0.46, 0.45, 0.44) if lab else Color(0.86, 0.75, 0.56)


func _cloud_color(ri: int, _y: float, _hsh: float, _st: float) -> Color:
	return _pal[ri][4]


# ---------- 小地图的整图底图 ----------

## 烘一层的整图（正方形，按 px 米一像素取地形表）：{img, center, span}
func bake_map(ln: String, px: float) -> Dictionary:
	var lay: Dictionary = (map["layers"] as Dictionary)[ln]
	var g: Rect2 = lay["grid"]
	var span := maxf(g.size.x, g.size.y)
	var center := g.get_center()
	var n := int(span / px)
	var out := PackedByteArray()
	out.resize(n * n * 3)
	out.fill(26)
	var x0 := center.x - span * 0.5
	var z0 := center.y - span * 0.5
	var cav := ln == "cavern"
	var li := 1 if cav else 0
	var gx0 := _c_x0 if cav else _s_x0
	var gz0 := _c_z0 if cav else _s_z0
	var gw := _c_w if cav else _s_w
	var gd := _c_d if cav else _s_d
	var cols: Array = []
	for ri in 5:
		cols.append(_pal[ri][0])
	var road := _masonry(0, 0.0)
	var path := Color(0.62, 0.54, 0.42) if not lab else Color(0.52, 0.42, 0.33)
	var step := maxi(int(px / CELL), 1)
	for j in n:
		var lz := int(floorf((z0 + (float(j) + 0.5) * px) / CELL)) - gz0
		if lz < 0 or lz >= gd:
			continue
		for i in n:
			var lx := int(floorf((x0 + (float(i) + 0.5) * px) / CELL)) - gx0
			if lx < 0 or lx >= gw:
				continue
			var idx := lz * gw + lx
			var h: float = _c_h[idx] if cav else _s_h[idx]
			var ri: int = _c_r[idx] if cav else _s_r[idx]
			var k: int = _c_k[idx] if cav else _s_k[idx]
			var col: Color
			if cav:
				col = Color(0.09, 0.08, 0.08) if ri == 4 else Color(0.62, 0.55, 0.47) * clampf(0.8 + (h - 10.0) * 0.03, 0.6, 1.2)
			else:
				col = cols[ri]
				if (k & 15) == K_ROAD:
					col = road
				elif (k & 15) == K_PATH:
					col = path
				elif (k & 16) != 0:
					col = _pal[ri][3]
				var hn: float = _s_h[mini(lz + step, gd - 1) * gw + mini(lx + step, gw - 1)]
				col = col * clampf(0.9 + (h - _base_y) * 0.012 + (h - hn) * 0.05, 0.45, 1.4)
			var o := (j * n + i) * 3
			out[o] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			out[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			out[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
	# 楼的占地：深色屋顶 + 一圈墨线；钥匙房：朱红
	for b: Dictionary in map.get("buildings", []):
		var r: Rect2 = b["rect"]
		if MapDef.layer_at(Vector3(r.position.x, 0, r.position.y)) != ln:
			continue
		_bake_rect(out, n, x0, z0, px, r, Color(0.36, 0.37, 0.40), Color(0.10, 0.09, 0.08))
	for kr: Dictionary in map["key_rooms"]:
		if str(kr["layer"]) != ln:
			continue
		var rb: AABB = kr["room"]
		_bake_rect(out, n, x0, z0, px, Rect2(rb.position.x, rb.position.z, rb.size.x, rb.size.z), Color(0.66, 0.26, 0.18), Color(0.22, 0.06, 0.04))
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, out)
	return {"img": img, "center": center, "span": span}


func _bake_rect(out: PackedByteArray, n: int, x0: float, z0: float, px: float, r: Rect2, fill: Color, line: Color) -> void:
	var i0 := clampi(int(floorf((r.position.x - x0) / px)), 0, n - 1)
	var i1 := clampi(int(floorf((r.end.x - x0) / px)), 0, n - 1)
	var j0 := clampi(int(floorf((r.position.y - z0) / px)), 0, n - 1)
	var j1 := clampi(int(floorf((r.end.y - z0) / px)), 0, n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var c := line if (i == i0 or i == i1 or j == j0 or j == j1) else fill
			var o := (j * n + i) * 3
			out[o] = int(c.r * 255.0)
			out[o + 1] = int(c.g * 255.0)
			out[o + 2] = int(c.b * 255.0)


## 大世界小地图的老接口（固定底图模式不走这里；留着兜底）
func map_cells(center: Vector2, span: float, n: int, _shade: bool, c0: int, c1: int, out: PackedByteArray) -> void:
	var step := span / float(n)
	var x0 := center.x - span * 0.5
	var z0 := center.y - span * 0.5
	for ci in range(c0, mini(c1, n * n)):
		var k := ci * 3
		var z := z0 + (float(ci / n) + 0.5) * step
		var x := x0 + (float(ci % n) + 0.5) * step
		var ri := _region(x, z, 0.5)
		var col: Color = _pal[ri][0]
		col = col * clampf(0.9 + (_shaped(x, z) - _base_y) * 0.012, 0.45, 1.4)
		out[k] = int(clampf(col.r, 0.0, 1.0) * 255.0)
		out[k + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
		out[k + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)


# ---------- 写地形表的小工具 ----------

## 对 rect 覆盖到的每一格调 f(li, idx, x, z)（x z = 格子中心的世界坐标）
func _each(r: Rect2, f: Callable) -> void:
	for li in 2:
		var g: Rect2 = _rects[li]
		var rr := r.intersection(g)
		if rr.size.x <= 0.0 or rr.size.y <= 0.0:
			continue
		var gx0 := _s_x0 if li == 0 else _c_x0
		var gz0 := _s_z0 if li == 0 else _c_z0
		var w := _s_w if li == 0 else _c_w
		var d := _s_d if li == 0 else _c_d
		var ix0 := maxi(int(floorf(rr.position.x / CELL)) - gx0, 0)
		var ix1 := mini(int(ceilf(rr.end.x / CELL)) - gx0, w)
		var iz0 := maxi(int(floorf(rr.position.y / CELL)) - gz0, 0)
		var iz1 := mini(int(ceilf(rr.end.y / CELL)) - gz0, d)
		for lz in range(iz0, iz1):
			var z := (float(lz + gz0) + 0.5) * CELL
			for lx in range(ix0, ix1):
				var x := (float(lx + gx0) + 0.5) * CELL
				f.call(li, lz * w + lx, x, z)


func _put(li: int, i: int, h: float, ri: int, kind: int) -> void:
	if li == 0:
		_s_h[i] = h
		_s_r[i] = ri
		_s_k[i] = kind
	else:
		_c_h[i] = h
		_c_r[i] = ri
		_c_k[i] = kind


func _set_ri(li: int, i: int, ri: int) -> void:
	if li == 0:
		_s_r[i] = ri
	else:
		_c_r[i] = ri


## 一块矩形区域整个设成同一高度 / 区域 / 地表
func _rect(r: Rect2, h: float, ri: int, kind: int) -> void:
	_each(r, func(li: int, i: int, _x: float, _z: float) -> void: _put(li, i, h, ri, kind))


func _disc(c: Vector2, rad: float, h: float, ri: int, kind: int) -> void:
	_each(Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), func(li: int, i: int, x: float, z: float) -> void:
		if Vector2(x, z).distance_to(c) <= rad:
			_put(li, i, h, ri, kind))


## 点到折线的最近距离和那里沿线插出来的地板高度
static func _poly_d(p: Vector2, pts: Array, fl: Array) -> Vector2:
	var best := 1.0e9
	var bh := 0.0
	for s in pts.size() - 1:
		var a: Vector2 = pts[s]
		var b: Vector2 = pts[s + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			bh = lerpf(float(fl[s]), float(fl[s + 1]), t)
	return Vector2(best, bh)


static func _poly_rect(pts: Array, pad: float) -> Rect2:
	var r := Rect2(pts[0] as Vector2, Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r.grow(pad)


# ---------- 静态几何的小工具 ----------

func _geo(d: Dictionary, key: Vector2i) -> Array:
	var g: Variant = d.get(key)
	if g == null:
		g = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
		d[key] = g
	return g


## 摆一个方块：几何进它所在地块（或当前的屋顶组），够大的同时进粗地块；solid = 登记实心盒子（全图静态）
func _sb(size: Vector3, xf: Transform3D, c: Color, em := 0.0, solid := true, shade := 0.72) -> void:
	# 2026-11-25 场景破坏：每个方块记一条（在哪张网格的第几个顶点起、多大、什么颜色），打坏时按这条把它抹掉 / 切开（_bx_add）
	var kx := DX_ROOF
	var kz := _tgt_roof
	var v0 := 0
	var s0 := -1
	if _tgt_roof >= 0:
		var rg: Array = (_roofs[_tgt_roof] as Dictionary)["geo"]
		v0 = (rg[0] as PackedVector3Array).size()
		_box(rg, size, xf, c, em, shade)
	else:
		var key := key_of(xf.origin)
		var fg := _geo(_sgeo, key)
		v0 = (fg[0] as PackedVector3Array).size()
		_box(fg, size, xf, c, em, shade)
		if maxf(size.x, maxf(size.y, size.z)) >= 2.5:
			var sg := _geo(_sshell, key)
			s0 = (sg[0] as PackedVector3Array).size()
			_box(sg, size, xf, c, em, shade)
		kx = key.x
		kz = key.y
	var rec_n := _srec.size()
	if solid:
		_rec_box(_srec, size, xf)
	_bx_add(kx, kz, v0, s0, size, xf, c, em, shade, _srec.size() > rec_n)


## 实心盒子的一条记录（规矩同 block_world._box）。整面墙 / 楼板这种又大又正的都记
static func _rec_box(rec: PackedFloat32Array, size: Vector3, xf: Transform3D) -> void:
	if size.y < 0.12 or minf(size.x, size.z) < 0.3 or maxf(size.x, maxf(size.y, size.z)) < 0.6 or absf(xf.basis.y.y) <= 0.85:
		return
	var h := size * 0.5
	var ax := xf.basis.x * h.x
	var bz := xf.basis.z * h.z
	var hy := absf(xf.basis.y.y) * h.y + absf(xf.basis.x.y) * h.x + absf(xf.basis.z.y) * h.z
	rec.append_array([xf.origin.x, xf.origin.z, ax.x, ax.z, bz.x, bz.z, xf.origin.y - hy, xf.origin.y + hy, 0.0])


## 竖着的方块：底面在 y0、顶面在 y1
func _col(x: float, z: float, y0: float, y1: float, w: float, d: float, c: Color, yaw := 0.0, em := 0.0, solid := true) -> void:
	_sb(Vector3(w, y1 - y0, d), _xf(Vector3(x, (y0 + y1) * 0.5, z), yaw), c, em, solid)


## 一段墙：从 a 到 b（水平），厚 t，底 y0 顶 y1
func _wall(a: Vector2, b: Vector2, y0: float, y1: float, t: float, c: Color, solid := true, em := 0.0) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.05 or y1 - y0 < 0.05:
		return
	var m := (a + b) * 0.5
	_sb(Vector3(t, y1 - y0, ln), _xf(Vector3(m.x, (y0 + y1) * 0.5, m.y), atan2(d.x, d.y)), c, em, solid)


## 一个灯火点（地块生成时烘成地上的一圈光，见 block_world._lights）
func _light(p: Vector3, ri: int, kind: int) -> void:
	var key := key_of(p)
	if not _lmap.has(key):
		_lmap[key] = []
	(_lmap[key] as Array).append([p, ri, kind])


func _begin_roof(id: String, r: Rect2, y0: float) -> void:
	_roofs.append({"id": id, "rect": r, "y0": y0, "geo": [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()],
			"node": null, "hidden": false})
	_tgt_roof = _roofs.size() - 1


func _end_roof() -> void:
	_tgt_roof = -1


## 借 block_world 的成组构件（_roof 等）：先拼进一个带实心记录的临时数组，再并到当前目标
func _with_tmp(f: Callable, solid: bool) -> void:
	var tmp := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array(), PackedFloat32Array()]
	f.call(tmp)
	var v: PackedVector3Array = tmp[0]
	if v.is_empty():
		return
	var tgt: Array
	if _tgt_roof >= 0:
		tgt = (_roofs[_tgt_roof] as Dictionary)["geo"]
	else:
		tgt = _geo(_sgeo, key_of(v[0]))
	var tv: PackedVector3Array = tgt[0]
	var base := tv.size()
	tv.append_array(v)
	tgt[0] = tv
	var tn: PackedVector3Array = tgt[1]
	tn.append_array(tmp[1])
	tgt[1] = tn
	var tc: PackedColorArray = tgt[2]
	tc.append_array(tmp[2])
	tgt[2] = tc
	var ti: PackedInt32Array = tgt[3]
	for q: int in (tmp[3] as PackedInt32Array):
		ti.append(q + base)
	tgt[3] = ti
	if solid:
		var r: PackedFloat32Array = tmp[4]
		_srec.append_array(r)


# ---------- 门 ----------

## 钥匙房的门：单独的网格 + 单独登记的实心盒子。center = 门洞底边中点，yaw = 门洞朝外的方向
func _door(id: String, center: Vector3, yaw: float, w: float, h: float) -> void:
	var a := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	var xf := _xf(Vector3(0, h * 0.5, 0))
	_box(a, Vector3(w - 0.1, h - 0.06, 0.5), xf, Color(0.30, 0.24, 0.20), 0.0, 0.8)
	# 铜钉 + 横带 + 中间一枚朱红的禁制印
	for yy: float in [h * 0.25, h * 0.75]:
		_box(a, Vector3(w - 0.3, 0.3, 0.62), _xf(Vector3(0, yy, 0)), BRONZE_D, 0.0, 0.9)
	_box(a, Vector3(1.1, 1.1, 0.68), _xf(Vector3(0, h * 0.5, 0), 0.0, Vector3(0, 0, PI * 0.25)), VERM, 0.5, 1.0)
	var rec := PackedFloat32Array()
	_rec_box(rec, Vector3(w, h, 0.9), _xf(center + Vector3(0, h * 0.5, 0), yaw))
	var k := Vector2i(DOOR_KEY0 + _doors.size(), 0)
	_doors[id] = {"key": k, "cells": _sol_pack(rec), "geo": a, "node": null, "open": false, "t": 0.0,
			"pos": center, "yaw": yaw, "h": h, "w": w}
	_sol_put(k, _doors[id]["cells"], Vector3.ZERO)


## 开 / 关钥匙房的门（extract_manager.gd 调；联机由它同步）。开：立刻不挡路，门板 0.6 秒沉进地里；关：立刻挡路、门板升起来
func set_door(id: String, open: bool) -> void:
	var d: Variant = _doors.get(id)
	if d == null:
		return
	var dd: Dictionary = d
	if bool(dd["open"]) == open:
		return
	dd["open"] = open
	if open:
		_sol_drop(dd["key"])
	else:
		_sol_put(dd["key"], dd["cells"], Vector3.ZERO)


func door_open(id: String) -> bool:
	var d: Variant = _doors.get(id)
	return d != null and bool((d as Dictionary)["open"])


func door_ids() -> Array:
	return _doors.keys()


func _process(dt: float) -> void:
	super(dt)
	_dx_tick()
	for id: String in _doors:
		var d: Dictionary = _doors[id]
		var goal := 1.0 if bool(d["open"]) else 0.0
		var t: float = d["t"]
		if absf(t - goal) > 0.001:
			t = move_toward(t, goal, dt / 0.6)
			d["t"] = t
			var n: Node3D = d["node"]
			if n != null:
				n.position.y = (d["pos"] as Vector3).y - float(d["h"]) * t * t * (3.0 - 2.0 * t)
				n.visible = t < 0.999


# ---------- 屋顶：主角进了楼就藏 ----------

## 主角在 p：在哪栋楼的占地框里、又低于那块屋顶 / 楼板的底面，就把它藏起来（镜头不被挡、看得见人）
func update_roofs(p: Vector3) -> void:
	var q := Vector2(p.x, p.z)
	for r: Dictionary in _roofs:
		var hide: bool = (r["rect"] as Rect2).grow(0.3).has_point(q) and p.y < float(r["y0"]) - 0.2
		if hide != bool(r["hidden"]):
			r["hidden"] = hide
			var n: Node3D = r["node"]
			if n != null:
				n.visible = not hide


## 现在藏着的屋顶有几块（自检看）
func roofs_hidden() -> int:
	var n := 0
	for r: Dictionary in _roofs:
		if bool(r["hidden"]):
			n += 1
	return n


## 主角在不在某栋楼里（占地框里、楼板底下），在就返回这栋楼的占地框，否则返回空框
func building_at(p: Vector3) -> Rect2:
	var q := Vector2(p.x, p.z)
	for b: Dictionary in map.get("buildings", []):
		var r: Rect2 = b["rect"]
		if r.has_point(q) and p.y < _base_y + float(int(b.get("storeys", 1))) * STOREY + 0.6:
			return r
	return Rect2()


func _build_nodes() -> void:
	for r: Dictionary in _roofs:
		var g: Array = r["geo"]
		if (g[0] as PackedVector3Array).is_empty():
			continue
		var mi := _mesh_node(g, "Roof_" + str(r["id"]))
		mi.visibility_range_end = 520.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		r["node"] = mi
	for id: String in _doors:
		var d: Dictionary = _doors[id]
		var mi2 := _mesh_node(d["geo"], "Door_" + id)
		mi2.position = d["pos"]
		mi2.rotation.y = float(d["yaw"])
		mi2.visibility_range_end = 260.0
		d["node"] = mi2
	boundary = Node3D.new()
	boundary.name = "Boundary"
	add_child(boundary)
	_build_boundary()


func _mesh_node(g: Array, nm: String) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g[0]
	arrays[Mesh.ARRAY_NORMAL] = g[1]
	arrays[Mesh.ARRAY_COLOR] = g[2]
	arrays[Mesh.ARRAY_INDEX] = g[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


# ---------- 边界的样子 ----------

## 沙漠：play 矩形外一圈两层「沙暴幕」（越往上越淡）；研究所：围墙顶上一圈「禁制光幕」（竖条纹）。都是透明的普通材质
func _build_boundary() -> void:
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.vertex_color_use_as_albedo = true
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	if lab:
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var wl: Dictionary = map["wall"]
		var e := float(wl["barrier"]) + 1.0
		_curtain(g, e, float(wl["top"]) - 0.5, float(wl["top"]) + 34.0, Color(0.55, 0.85, 1.0), 0.30, 8.0)
	else:
		sm.fog_enabled = true
		var pl: Rect2 = (map["layers"]["surface"] as Dictionary)["play"]
		for k: Array in [[62.0, 0.5], [92.0, 0.75]]:
			_curtain_rect(g, pl.grow(float(k[0])), _base_y - 2.0, _base_y + 150.0, Color(0.88, 0.70, 0.46), float(k[1]), 40.0)
	var mi := MeshInstance3D.new()
	mi.name = "Curtain"
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g[0]
	arrays[Mesh.ARRAY_NORMAL] = g[1]
	arrays[Mesh.ARRAY_COLOR] = g[2]
	arrays[Mesh.ARRAY_INDEX] = g[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boundary.add_child(mi)


## 研究所：以原点为中心、半边 e 的方框上立一圈光幕，每 seg 米一条竖带（亮暗相间）
func _curtain(g: Array, e: float, y0: float, y1: float, c: Color, a: float, seg: float) -> void:
	_curtain_rect(g, Rect2(-e, -e, e * 2.0, e * 2.0), y0, y1, c, a, seg, true)


func _curtain_rect(g: Array, r: Rect2, y0: float, y1: float, c: Color, a: float, seg: float, stripes := false) -> void:
	var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for s in 4:
		var p0: Vector2 = cs[s]
		var p1: Vector2 = cs[(s + 1) % 4]
		var n := maxi(int(p0.distance_to(p1) / seg), 1)
		for i in n:
			var a0 := p0.lerp(p1, float(i) / float(n))
			var a1 := p0.lerp(p1, float(i + 1) / float(n))
			var k := a * (1.0 if not stripes or i % 2 == 0 else 0.45)
			var v: PackedVector3Array = g[0]
			var nr: PackedVector3Array = g[1]
			var cl: PackedColorArray = g[2]
			var ix: PackedInt32Array = g[3]
			var b := v.size()
			# 三段：底下浓、中间渐淡、顶上全透
			var ys := [y0, lerpf(y0, y1, 0.35), y1]
			var al := [k, k * 0.6, 0.0]
			for t in 3:
				v.append(Vector3(a0.x, float(ys[t]), a0.y))
				v.append(Vector3(a1.x, float(ys[t]), a1.y))
				var cc := MeshLib.vcol(c)
				cl.append(Color(cc.r, cc.g, cc.b, float(al[t])))
				cl.append(Color(cc.r, cc.g, cc.b, float(al[t])))
				nr.append(Vector3.UP)
				nr.append(Vector3.UP)
			for t in 2:
				var q := b + t * 2
				ix.append_array([q, q + 1, q + 3, q, q + 3, q + 2])
			g[0] = v
			g[1] = nr
			g[2] = cl
			g[3] = ix


# =====================================================================
# 沙海古墟
# =====================================================================

func _gen_desert() -> void:
	var n1 := FastNoiseLite.new()
	n1.seed = 1201
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 1.0 / 110.0
	n1.fractal_octaves = 2
	var n2 := FastNoiseLite.new()
	n2.seed = 77
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 1.0 / 36.0
	var n3 := FastNoiseLite.new()
	n3.seed = 904
	n3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n3.frequency = 1.0 / 180.0
	var lays: Dictionary = map["layers"]
	var pl: Rect2 = (lays["surface"] as Dictionary)["play"]
	var cf: Dictionary = map["cliff"]
	var c_in: float = cf["inner"]
	var c_out: float = cf["outer"]
	var gaps: Array = cf["gaps"]
	var hx := pl.size.x * 0.5
	var hz := pl.size.y * 0.5
	var pc := pl.get_center()
	# 1 地面：沙丘 + 戈壁 + 外圈赤岩台崖 + 崖外的沙暴带
	var w := _s_w
	for lz in _s_d:
		var z := (float(lz + _s_z0) + 0.5) * CELL
		for lx in w:
			var x := (float(lx + _s_x0) + 0.5) * CELL
			var i := lz * w + lx
			var d1 := n1.get_noise_2d(x, z)
			var d2 := n2.get_noise_2d(x, z)
			var dune := d1 * 4.6 + d2 * 1.5
			var h := _base_y + roundf(dune)
			var ri := 0
			var kind := 0
			if n3.get_noise_2d(x, z) > 0.28:
				kind = K_PATH          # 戈壁：砾石地，平一些
				h = _base_y + roundf(dune * 0.35)
			var ex := absf(x - pc.x) - hx
			var ez := absf(z - pc.y) - hz
			var e := maxf(ex, ez)
			if e > c_in and e < c_out:
				var side := ("e" if x > pc.x else "w") if ex > ez else ("s" if z > pc.y else "n")
				var along := z if ex > ez else x
				var gap := false
				for gp: Array in gaps:
					if str(gp[0]) == side and absf(along - float(gp[1])) < float(gp[2]):
						gap = true
						break
				if not gap:
					# 台崖：两三层退台，越往外越高
					var ch: float = lerpf(float(cf["h_min"]), float(cf["h_max"]), clampf(0.5 + d1 * 0.8, 0.0, 1.0))
					var tier := clampf((e - c_in) / (c_out - c_in) * 1.6, 0.0, 1.0)
					h = _base_y + floorf(ch * (0.55 + 0.45 * floorf(tier * 3.0) / 2.0) / 4.0) * 4.0 + roundf(d2 * 2.0)
					ri = 1
					kind = 0
				else:
					ri = 0
			elif e >= c_out:
				h = _base_y + roundf(d1 * 3.2 + d2 * 1.0)
				kind = 0
			_s_h[i] = h
			_s_r[i] = ri
			_s_k[i] = kind
	# 2 戈壁方山
	for ms: Array in map["mesas"]:
		var c: Vector2 = ms[0]
		var r: float = ms[1]
		var mh: float = ms[2]
		_disc(c, r + 4.0, _base_y + floorf(mh * 0.45), 1, 0)
		_each(Rect2(c - Vector2(r, r) * 1.2, Vector2(r, r) * 2.4), func(li: int, i: int, x: float, z: float) -> void:
			var rr := r + n2.get_noise_2d(x * 1.7, z * 1.7) * 3.0
			if Vector2(x, z).distance_to(c) < rr:
				_put(li, i, _base_y + mh, 1, 0))
	# 3 撤离台、出生点、遗迹脚下压平
	for e2: Dictionary in map["extracts"]:
		var ep: Vector3 = e2["pos"]
		var es: Vector3 = e2["size"]
		_disc(Vector2(ep.x, ep.z), 24.0, _base_y, 0, 0)
		_rect(Rect2(ep.x - es.x * 0.5, ep.z - es.z * 0.5, es.x, es.z), _base_y + 1.0, 0, 16)
	for s: Dictionary in map["spawns"]:
		if str(s["layer"]) == "surface":
			var sp: Vector3 = s["pos"]
			_disc(Vector2(sp.x, sp.z), 10.0, _base_y, 0, 0)
	for ru: Dictionary in map["ruins"]:
		var rc: Vector2 = ru["c"]
		_disc(rc, 9.0 if int(ru["type"]) != 6 else 7.0, _base_y, 0, K_PATH if int(ru["type"]) % 2 == 0 else 0)
	# 4 北峡：一道下行的峡谷（谷底砾石，两壁赤岩）
	var cy: Dictionary = map["canyon"]
	var cpts: Array = cy["pts"]
	var cfl: Array = cy["floor"]
	var cw: float = cy["w"]
	_each(_poly_rect(cpts, cw), func(li: int, i: int, x: float, z: float) -> void:
		var pd := _poly_d(Vector2(x, z), cpts, cfl)
		var hw := cw * 0.5 + n2.get_noise_2d(x * 2.0, z * 2.0) * 1.5
		if pd.x < hw:
			_put(li, i, floorf(pd.y), 1, K_PATH)
		elif pd.x < hw + 7.0:
			_set_ri(li, i, 1))
	# 5 金字塔「黄金神塔」：六层退台 + 四面石阶，塔顶是 Boss 台（石板地）
	var py: Dictionary = map["pyramid"]
	var pcc: Vector2 = py["c"]
	var top: Vector2 = py["top"]
	var top_y: float = py["top_y"]
	var tiers: int = py["tiers"]
	var th: float = py["tier_h"]
	var tin: float = py["tier_in"]
	var sw: float = py["stair_w"]
	var base := top + Vector2(tin, tin) * float(tiers)
	_each(Rect2(pcc - base, base * 2.0), func(li: int, i: int, x: float, z: float) -> void:
		var dx := absf(x - pcc.x)
		var dz := absf(z - pcc.y)
		var m := maxf(dx - top.x, dz - top.y)
		var kk := int(ceilf(m / tin)) if m > 0.0 else 0
		if kk > tiers:
			return
		var h := top_y - th * float(kk)
		var kind := 16 if kk == 0 else 0
		# 石阶：四面正中各一道，一米一级、两米一步
		if dz <= sw and dx > top.x:
			h = top_y - ceilf((dx - top.x) / 2.0)
			kind = K_ROAD
		elif dx <= sw and dz > top.y:
			h = top_y - ceilf((dz - top.y) / 2.0)
			kind = K_ROAD
		if h < _base_y:
			return
		_put(li, i, h, 3, kind))
	# 6 洞口坑（U1 ~ U4）：坡道下到坑底，坑底那面崖壁上是洞口
	for pt: Dictionary in map["pits"]:
		var c3: Vector2 = pt["c"]
		var dd: Vector3 = pt["d"]
		var u := Vector2(dd.x, dd.z)
		var v := Vector2(-u.y, u.x)
		_each(Rect2(c3 - Vector2(16, 16), Vector2(32, 32)), func(li: int, i: int, x: float, z: float) -> void:
			var q := Vector2(x, z) - c3
			var a := q.dot(u)
			var b := absf(q.dot(v))
			if a >= -10.0 and a <= 12.0 and b <= 7.0:
				var h := _base_y - 7.0 if a < -2.0 else _base_y - 7.0 + floorf((a + 2.0) * 0.5)
				_put(li, i, minf(h, _base_y), 1, K_PATH)
			elif a >= -14.0 and a <= 14.0 and b <= 11.0:
				_put(li, i, _base_y + (2.0 if a < -10.0 else 0.0), 1, 0))
	# 7 洞窟
	_gen_cave(map["cave"], 4, 2)
	# ---- 摆件 ----
	_desert_structures()


## 洞窟 / 地下室：先整片岩体，再挖隧道、洞厅，留石柱。rock_ri / floor_ri = 岩体 / 地面的区域号
func _gen_cave(cv: Dictionary, rock_ri: int, floor_ri: int) -> void:
	var li := 1
	var rock_y: float = cv["rock_y"]
	var ceil_y: float = cv["ceil"]
	_c_h.fill(rock_y)
	_c_r.fill(rock_ri)
	_c_k.fill(0)
	_c_c.fill(0.0)
	var n2 := FastNoiseLite.new()
	n2.seed = 515
	n2.frequency = 1.0 / 14.0
	for t: Array in cv["tunnels"]:
		var pts: Array = t[0]
		var fl: Array = t[1]
		var tw: float = t[2]
		_each(_poly_rect(pts, tw), func(l2: int, i: int, x: float, z: float) -> void:
			if l2 != li:
				return
			var pd := _poly_d(Vector2(x, z), pts, fl)
			if pd.x < tw * 0.5 + n2.get_noise_2d(x, z) * 1.6:
				_put(li, i, floorf(pd.y + n2.get_noise_2d(x * 0.7 + 30.0, z * 0.7) * 0.9), floor_ri, K_PATH if n2.get_noise_2d(z, x) > 0.4 else 0)
				_c_c[i] = ceil_y)
	for hl: Array in cv["halls"]:
		if str(hl[0]) == "disc":
			var c: Vector2 = hl[1]
			var rad: float = hl[2]
			var f: float = hl[3]
			_each(Rect2(c - Vector2(rad + 3.0, rad + 3.0), Vector2(rad + 3.0, rad + 3.0) * 2.0), func(l2: int, i: int, x: float, z: float) -> void:
				if l2 == li and Vector2(x, z).distance_to(c) < rad + n2.get_noise_2d(x, z) * 2.0:
					_put(li, i, f, floor_ri, 0)
					_c_c[i] = ceil_y)
		else:
			var r: Rect2 = hl[1]
			var f2: float = hl[2]
			var c2: float = hl[3]
			_each(r, func(l2: int, i: int, _x: float, _z: float) -> void:
				if l2 == li:
					_put(li, i, f2, floor_ri, 0)
					_c_c[i] = c2)
	for pl: Array in cv["pillars"]:
		var pc: Vector2 = pl[0]
		var pr: float = pl[1]
		_each(Rect2(pc - Vector2(pr, pr), Vector2(pr, pr) * 2.0), func(l2: int, i: int, x: float, z: float) -> void:
			if l2 == li and Vector2(x, z).distance_to(pc) <= pr:
				_put(li, i, rock_y, rock_ri, 0)
				_c_c[i] = 0.0)
	_cave_ceiling()


## 洞顶：每一行连着的、洞顶一样高的格子拼成一条朝下的面（按地块切开）；洞顶高低不一处补一段竖面
func _cave_ceiling() -> void:
	var w := _c_w
	var d := _c_d
	var cl := _c_c
	var x0 := _c_x0
	var z0 := _c_z0
	var dark := Color(0.17, 0.14, 0.14) if not lab else Color(0.15, 0.17, 0.16)
	for lz in d:
		var lx := 0
		while lx < w:
			var c := cl[lz * w + lx]
			if c <= 0.0:
				lx += 1
				continue
			var s := lx
			var key0 := key_of(Vector3((float(x0 + lx) + 0.5) * CELL, 0, (float(z0 + lz) + 0.5) * CELL))
			while lx < w and absf(cl[lz * w + lx] - c) < 0.01 and key_of(Vector3((float(x0 + lx) + 0.5) * CELL, 0, (float(z0 + lz) + 0.5) * CELL)) == key0:
				lx += 1
			var xa := float(x0 + s) * CELL
			var xb := float(x0 + lx) * CELL
			var za := float(z0 + lz) * CELL
			var zb := za + CELL
			var hsh := _hash(s * 7 + lz, lz * 3 - s)
			var col := dark * (0.9 + 0.2 * hsh)
			var g := _geo(_sgeo, key0)
			_quad(g, Vector3(xa, c, za), Vector3(xb, c, za), Vector3(xb, c, zb), Vector3(xa, c, zb), Vector3.DOWN, col)
			_quad(_geo(_sshell, key0), Vector3(xa, c, za), Vector3(xb, c, za), Vector3(xb, c, zb), Vector3(xa, c, zb), Vector3.DOWN, col)
		# 洞顶的台阶（36 → 40）：低的那格朝高的那格补一段竖面
		for lx2 in w:
			var c0 := cl[lz * w + lx2]
			if c0 <= 0.0:
				continue
			for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := lx2 + dv.x
				var nz := lz + dv.y
				if nx < 0 or nz < 0 or nx >= w or nz >= d:
					continue
				var c1 := cl[nz * w + nx]
				if c1 > c0 + 0.01:
					var cx := (float(x0 + lx2) + 0.5) * CELL
					var cz := (float(z0 + lz) + 0.5) * CELL
					var ex := cx + float(dv.x) * CELL * 0.5
					var ez := cz + float(dv.y) * CELL * 0.5
					var t := Vector3(float(-dv.y), 0, float(dv.x)) * CELL * 0.5
					var k2 := key_of(Vector3(cx, 0, cz))
					_quad(_geo(_sgeo, k2), Vector3(ex, c0, ez) - t, Vector3(ex, c0, ez) + t, Vector3(ex, c1, ez) + t, Vector3(ex, c1, ez) - t,
							Vector3(float(-dv.x), 0, float(-dv.y)), dark * 0.85)


## 一个四边形（两面都画：洞顶从上面看不到也不要紧，省得算朝向）
func _quad(g: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	var v: PackedVector3Array = g[0]
	var nr: PackedVector3Array = g[1]
	var cl: PackedColorArray = g[2]
	var ix: PackedInt32Array = g[3]
	var o := v.size()
	v.append_array([a, b, c, d])
	for _q in 4:
		nr.append(n)
		cl.append(Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 0.0))
	ix.append_array([o, o + 1, o + 2, o, o + 2, o + 3, o, o + 2, o + 1, o, o + 3, o + 2])
	g[0] = v
	g[1] = nr
	g[2] = cl
	g[3] = ix


func _desert_structures() -> void:
	var rng := RandomNumberGenerator.new()
	# 遗迹群
	for ru: Dictionary in map["ruins"]:
		rng.seed = int(ru["seed"])
		var c: Vector2 = ru["c"]
		var yaw: float = ru["yaw"]
		var y := height(c.x, c.y)
		_ruin(int(ru["type"]), Vector3(c.x, y, c.y), yaw, rng)
	# 金字塔塔顶：四角方尖碑 + 火盆、正中一圈金色符文
	var py: Dictionary = map["pyramid"]
	var pc: Vector2 = py["c"]
	var top: Vector2 = py["top"]
	var ty: float = py["top_y"]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(pc.x + sx * (top.x - 2.4), ty, pc.y + sz * (top.y - 2.4))
			_col(p.x, p.z, ty, ty + 1.15, 3.2, 3.2, SAND_D)
			_col(p.x, p.z, ty + 1.15, ty + 9.35, 1.8, 1.8, GOLD)
			_col(p.x, p.z, ty + 9.35, ty + 10.55, 1.0, 1.0, FLAME, 0.0, 0.9, false)
			_light(p + Vector3(0, 10.0, 0), 3, 2)
			var bp := Vector3(pc.x + sx * (top.x - 9.0), ty, pc.y + sz * (top.y - 2.4))
			_brazier_at(bp)
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var rp := Vector3(pc.x + cos(ang) * 9.0, ty, pc.y + sin(ang) * 9.0)
		_sb(Vector3(1.6, 0.12, 0.8), _xf(rp + Vector3(0, 0.08, 0), -ang), GOLD, 0.35, false)
	# 石阶下的守门兽（方块狮）
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var bx := top.x + float(py["tier_in"]) * float(py["tiers"])
		var bz := top.y + float(py["tier_in"]) * float(py["tiers"])
		var at := pc + Vector2(d.x * (bx + 3.0), d.y * (bz + 3.0))
		var side := Vector2(-d.y, d.x)
		for sg: float in [-1.0, 1.0]:
			var q := at + side * sg * 8.0
			_beast(Vector3(q.x, height(q.x, q.y), q.y), atan2(-d.x, -d.y))
	# 撤离台：四角石柱 + 灯
	for e: Dictionary in map["extracts"]:
		var ep: Vector3 = e["pos"]
		var es: Vector3 = e["size"]
		for sx2: float in [-1.0, 1.0]:
			for sz2: float in [-1.0, 1.0]:
				var q2 := Vector3(ep.x + sx2 * (es.x * 0.5 - 0.8), ep.y, ep.z + sz2 * (es.z * 0.5 - 0.8))
				_col(q2.x, q2.z, ep.y, ep.y + 3.15, 1.1, 1.1, SAND_ST)
				_col(q2.x, q2.z, ep.y + 3.15, ep.y + 3.85, 0.8, 0.8, FLAME, 0.0, 0.85, false)
				_light(q2 + Vector3(0, 3.5, 0), 0, 0)
	# 洞口：坑底崖壁上的门框（深色的洞 + 木柱 + 横梁 + 两支火把）
	for pt: Dictionary in map["pits"]:
		var c3: Vector2 = pt["c"]
		var dd: Vector3 = pt["d"]
		var mouth := Vector3(c3.x, _base_y - 7.0, c3.y) - dd * 10.0
		_mouth(mouth, MapDef.yaw_of(dd), 7.0)
	var cy: Dictionary = map["canyon"]
	var cpts: Array = cy["pts"]
	var cend: Vector2 = cpts[cpts.size() - 1]
	var cprev: Vector2 = cpts[cpts.size() - 2]
	var cb := Vector3(cprev.x - cend.x, 0, cprev.y - cend.y).normalized()
	_mouth(Vector3(cend.x, 8.0, cend.y) - cb * 8.6, MapDef.yaw_of(cb), 9.0)
	for b: Vector2 in [Vector2(-50, -84), Vector2(-20, -96), Vector2(-4, -92)]:
		_boulder(Vector3(b.x, height(b.x, b.y), b.y), 1.4 + absf(b.x) * 0.02, rng)
	# 散落的石块 / 兽骨（只在细地块里，不挡路）
	rng.seed = 99
	var pl: Rect2 = (map["layers"]["surface"] as Dictionary)["play"]
	for i in 260:
		var p2 := Vector2(rng.randf_range(pl.position.x, pl.end.x), rng.randf_range(pl.position.y, pl.end.y))
		var y2 := height(p2.x, p2.y)
		if _region(p2.x, p2.y, 0.5) != 0 or y2 > _base_y + 6.0:
			continue
		if i % 5 == 0:
			_bones_at(Vector3(p2.x, y2, p2.y), rng.randf() * TAU)
		elif i % 5 == 1:
			_cactus(Vector3(p2.x, y2, p2.y), rng)
		elif i % 5 == 2:
			_shrub(Vector3(p2.x, y2, p2.y), rng)
		else:
			var s := rng.randf_range(0.5, 1.3)
			_sb(Vector3(s * 1.4, s * 0.7 + 0.03, s), _xf(Vector3(p2.x, y2 + s * 0.3, p2.y), rng.randf() * TAU), SAND_D * rng.randf_range(0.85, 1.05), 0.0, false)
	_cave_structures()


## 遗迹的几种样子
func _ruin(t: int, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var bs := Basis(Vector3.UP, yaw)
	match t:
		0:
			# 石柱圈：六根，有的断了半截，顶上压着残梁
			var n := 6
			for i in n:
				var ang := yaw + TAU * float(i) / float(n)
				var q := p + Vector3(cos(ang), 0, sin(ang)) * 7.0
				var hh := 7.35 if i % 3 != 1 else rng.randf_range(1.6, 4.2) + 0.15
				_col(q.x, q.z, p.y - 0.2, p.y + 0.85, 2.2, 2.2, SAND_D, ang)
				_col(q.x, q.z, p.y + 0.85, p.y + hh, 1.5, 1.5, SAND_ST * rng.randf_range(0.92, 1.05), ang)
				if hh > 7.0:
					_col(q.x, q.z, p.y + hh, p.y + hh + 0.7, 2.0, 2.0, SAND_D, ang)
			var b0 := p + Vector3(cos(yaw), 0, sin(yaw)) * 7.0
			var b1 := p + Vector3(cos(yaw + TAU / 6.0), 0, sin(yaw + TAU / 6.0)) * 7.0
			_wall(Vector2(b0.x, b0.z), Vector2(b1.x, b1.z), p.y + 8.05, p.y + 8.95, 1.6, SAND_ST)
		1:
			# 断墙：一段 L 形泥砖墙，墙头参差
			for k in 2:
				var dir := bs * (Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1))
				var s0 := p - dir * 6.0 + bs * Vector3(-4, 0, -4) * float(k)
				for seg in 5:
					var q2 := s0 + dir * (float(seg) * 2.6)
					var hh2 := rng.randf_range(1.7, 4.6) + 0.15
					if rng.randf() < 0.18:
						continue
					_sb(Vector3(2.7, hh2, 1.2), _xf(q2 + Vector3(0, hh2 * 0.5 - 0.2, 0), atan2(dir.x, dir.z) + PI * 0.5), MUD * rng.randf_range(0.9, 1.05))
		2:
			# 图腾柱 + 断像
			var q3 := p + bs * Vector3(-3, 0, 0)
			var yy := p.y - 0.2
			var cols := [SAND_ST, RED, SAND_ST, TEAL, GOLD, SAND_ST]
			for i in 6:
				var hh3 := 1.45 if i < 5 else 1.95
				_col(q3.x, q3.z, yy, yy + hh3, 1.6 - float(i) * 0.06, 1.6 - float(i) * 0.06, cols[i], yaw + float(i) * 0.08)
				yy += hh3
			_col(q3.x, q3.z, yy, yy + 0.5, 3.4, 0.6, GOLD, yaw)
			_statue_at(p + bs * Vector3(4, 0, 1), yaw + PI, rng)
		3:
			# 石拱门
			for sx: float in [-1.0, 1.0]:
				var q4 := p + bs * Vector3(sx * 4.0, 0, 0)
				_col(q4.x, q4.z, p.y - 0.2, p.y + 1.05, 2.6, 2.6, SAND_D, yaw)
				_col(q4.x, q4.z, p.y + 1.05, p.y + 8.15, 1.9, 1.9, SAND_ST, yaw)
			_sb(Vector3(10.6, 1.4, 2.4), _xf(p + Vector3(0, 8.85, 0), yaw), SAND_ST)
			_sb(Vector3(6.2, 0.9, 2.6), _xf(p + Vector3(0, 9.95, 0), yaw), GOLD * 0.9)
			for i in 3:
				var rq := p + bs * Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(2, 6))
				_boulder(Vector3(rq.x, p.y, rq.z), rng.randf_range(0.8, 1.6), rng)
		4:
			# 倒伏的巨像：一颗半埋的大头 + 几截断臂
			var hp := p + bs * Vector3(0, 0, -2)
			_sb(Vector3(5.6, 4.95, 5.2), _xf(hp + Vector3(0, 1.9, 0), yaw, Vector3(0.0, 0.0, 0.32)), SAND_ST)
			_sb(Vector3(6.4, 1.45, 3.4), _xf(hp + Vector3(0, 4.6, 0.4), yaw, Vector3(0.0, 0.0, 0.32)), GOLD * 0.85, 0.0, false)
			_sb(Vector3(1.0, 0.9, 0.5), _xf(hp + bs * Vector3(-1.2, 2.6, -2.7), yaw), DARK, 0.0, false)
			_sb(Vector3(1.0, 0.9, 0.5), _xf(hp + bs * Vector3(1.2, 2.6, -2.7), yaw), DARK, 0.0, false)
			for i in 2:
				var aq := p + bs * Vector3(-6.0 + float(i) * 12.0, 0, 3.0)
				_sb(Vector3(2.2, 2.15, 7.0), _xf(aq + Vector3(0, 0.85, 0), yaw + 0.4 * float(i * 2 - 1)), SAND_ST * 0.95)
		5:
			# 小神龛：三面墙 + 平顶，正面敞着（里面一般有箱子）
			var hw := 4.0
			for k2 in 3:
				var dir2: Vector3 = bs * ([Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)][k2] as Vector3)
				var side2 := Vector3(-dir2.z, 0, dir2.x)
				var wc: Vector3 = p + dir2 * hw
				_wall(Vector2(wc.x - side2.x * hw, wc.z - side2.z * hw), Vector2(wc.x + side2.x * hw, wc.z + side2.z * hw), p.y - 0.2, p.y + 5.15, 1.0, MUD)
			_sb(Vector3(hw * 2.0 + 1.6, 0.75, hw * 2.0 + 1.6), _xf(p + Vector3(0, 5.5, 0), yaw), SAND_ST)
			_sb(Vector3(hw * 2.0 + 2.2, 0.4, 0.7), _xf(p + bs * Vector3(0, 6.05, hw + 0.75), yaw), TEAL)
		6:
			# 神道石柱：两排四根
			for row: float in [-1.0, 1.0]:
				for i in 4:
					var q5 := p + bs * Vector3(row * 7.0, 0, -9.0 + float(i) * 6.0)
					var hh5 := 6.15 if (i + int(row)) % 3 != 0 else 3.15
					var y5 := height(q5.x, q5.z)
					_col(q5.x, q5.z, y5 - 0.2, y5 + 0.75, 1.9, 1.9, SAND_D, yaw)
					_col(q5.x, q5.z, y5 + 0.75, y5 + hh5, 1.3, 1.3, SAND_ST, yaw)
					if hh5 > 5.0:
						_col(q5.x, q5.z, y5 + hh5, y5 + hh5 + 0.9, 1.0, 1.0, GOLD, yaw + 0.785, 0.0, false)


func _statue_at(p: Vector3, yaw: float, _rng: RandomNumberGenerator) -> void:
	var bs := Basis(Vector3.UP, yaw)
	_sb(Vector3(3.0, 1.15, 3.0), _xf(p + Vector3(0, 0.38, 0), yaw), SAND_D)
	_sb(Vector3(2.0, 2.35, 1.6), _xf(p + Vector3(0, 2.1, 0), yaw), SAND_ST)
	_sb(Vector3(1.4, 1.35, 1.4), _xf(p + Vector3(0, 3.95, 0), yaw), SAND_ST)
	_sb(Vector3(1.9, 0.45, 1.7), _xf(p + Vector3(0, 4.75, 0), yaw), GOLD, 0.0, false)
	_sb(Vector3(0.9, 0.4, 0.3), _xf(p + bs * Vector3(0, 4.1, -0.78), yaw), TEAL, 0.0, false)


## 守门兽：方块狮子，蹲在石阶两侧
func _beast(p: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	_sb(Vector3(3.2, 1.45, 4.6), _xf(p + Vector3(0, 0.6, 0), yaw), SAND_D)
	_sb(Vector3(2.4, 2.25, 3.2), _xf(p + bs * Vector3(0, 2.4, 0.4), yaw), GOLD * 0.92)
	_sb(Vector3(2.2, 2.05, 2.0), _xf(p + bs * Vector3(0, 4.3, -0.9), yaw), GOLD)
	_sb(Vector3(1.6, 0.7, 0.4), _xf(p + bs * Vector3(0, 4.0, -2.02), yaw), DARK, 0.0, false)


func _brazier_at(p: Vector3) -> void:
	_col(p.x, p.z, p.y, p.y + 1.25, 1.1, 1.1, SAND_D)
	_col(p.x, p.z, p.y + 1.25, p.y + 1.75, 1.6, 1.6, BRONZE)
	_col(p.x, p.z, p.y + 1.75, p.y + 2.35, 1.1, 1.1, FLAME, 0.0, 0.95, false)
	_light(p + Vector3(0, 2.0, 0), 3 if not lab else 0, 2)


## 洞口：在 p（洞口那面崖壁的墙脚中点）朝 yaw 开一个门框：深色的洞、两根木柱、横梁、两支火把
func _mouth(p: Vector3, yaw: float, hgt: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var fw := Vector3(-sin(yaw), 0, -cos(yaw))
	_sb(Vector3(6.0, hgt - 0.6, 0.4), _xf(p - fw * 0.1 + Vector3(0, (hgt - 0.6) * 0.5, 0), yaw), DARK, 0.0, false, 1.0)
	for sx: float in [-1.0, 1.0]:
		var q := p + bs * Vector3(sx * 3.4, 0, 0) + fw * 0.4
		_col(q.x, q.z, p.y, p.y + hgt + 0.15, 0.8, 0.8, TIMBER, yaw)
		var tq := q + fw * 0.6 + Vector3(0, 3.0, 0)
		_sb(Vector3(0.3, 0.7, 0.3), _xf(tq, yaw), TIMBER, 0.0, false)
		_sb(Vector3(0.42, 0.5, 0.42), _xf(tq + Vector3(0, 0.6, 0), yaw), FLAME, 0.95, false)
		_light(tq + Vector3(0, 0.6, 0) + fw * 1.0, 1 if not lab else 2, 2)
	_sb(Vector3(8.4, 0.85, 1.0), _xf(p + fw * 0.4 + Vector3(0, hgt + 0.55, 0), yaw), TIMBER)


func _boulder(p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	_sb(Vector3(s * 2.2, s * 1.6 + 0.05, s * 1.9), _xf(p + Vector3(0, s * 0.6, 0), rng.randf() * TAU, Vector3(0.08, 0, 0.06)), SAND_D * rng.randf_range(0.8, 1.0))


## 方块仙人掌（资源库只有贴图，没有模型：拼几块绿方块）
func _cactus(p: Vector3, rng: RandomNumberGenerator) -> void:
	var g := Color(0.36, 0.56, 0.28) * rng.randf_range(0.9, 1.08)
	var h := rng.randf_range(2.2, 3.6) + 0.15
	var yaw := rng.randf() * TAU
	var bs := Basis(Vector3.UP, yaw)
	_col(p.x, p.z, p.y - 0.1, p.y + h, 0.7, 0.7, g, yaw)
	for sx: float in [-1.0, 1.0]:
		if rng.randf() < 0.75:
			var ah := rng.randf_range(0.9, 1.5)
			var ay := p.y + rng.randf_range(0.9, h - 1.0)
			_sb(Vector3(0.9, 0.5, 0.5), _xf(p + bs * Vector3(sx * 0.75, ay - p.y, 0), yaw), g * 0.95, 0.0, false)
			_sb(Vector3(0.58, ah, 0.58), _xf(p + bs * Vector3(sx * 1.05, ay - p.y + ah * 0.5, 0), yaw), g * 1.04, 0.0, false)
	_sb(Vector3(0.36, 0.3, 0.36), _xf(p + Vector3(0, h + 0.12, 0), yaw), Color(0.95, 0.45, 0.55), 0.0, false)


## 枯灌木：几根歪着的细枝 + 一团干草色
func _shrub(p: Vector3, rng: RandomNumberGenerator) -> void:
	var c := Color(0.62, 0.50, 0.32) * rng.randf_range(0.85, 1.05)
	for i in 4:
		_sb(Vector3(0.14, rng.randf_range(0.7, 1.3), 0.14), _xf(p + Vector3(rng.randf_range(-0.5, 0.5), 0.45, rng.randf_range(-0.5, 0.5)), rng.randf() * TAU,
				Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))), c * 0.8, 0.0, false)
	_sb(Vector3(1.4, 0.55, 1.2), _xf(p + Vector3(0, 0.3, 0), rng.randf() * TAU), c, 0.0, false)


func _bones_at(p: Vector3, yaw: float) -> void:
	var bone := Color(0.92, 0.88, 0.78)
	var bs := Basis(Vector3.UP, yaw)
	_sb(Vector3(0.5, 0.35, 3.2), _xf(p + Vector3(0, 0.15, 0), yaw), bone, 0.0, false)
	for i in 4:
		_sb(Vector3(1.8, 0.22, 0.28), _xf(p + bs * Vector3(0, 0.35 + 0.05 * float(i % 2), -1.2 + float(i) * 0.8), yaw, Vector3(0, 0, 0.5)), bone * 0.95, 0.0, false)


## 洞窟里的东西：火把、晶簇、矿道木架、光井、钥匙房的门墙、沙虫祭台和牢笼、绛罗场地的立石
func _cave_structures() -> void:
	var cv: Dictionary = map["cave"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var fl_ri := 2
	for t: Array in cv["tunnels"]:
		var pts: Array = t[0]
		var fls: Array = t[1]
		var tw: float = t[2]
		var acc := 0.0
		for s in pts.size() - 1:
			var a: Vector2 = pts[s]
			var b: Vector2 = pts[s + 1]
			var ln := a.distance_to(b)
			var dir := (b - a) / maxf(ln, 0.01)
			var side := Vector2(-dir.y, dir.x)
			var u := 10.0 - fmod(acc, 26.0)
			while u < ln:
				var c := a + dir * u
				var sg := 1.0 if int((acc + u) / 26.0) % 2 == 0 else -1.0
				var wp := c + side * sg * (tw * 0.5 - 1.6)
				var fy := height(wp.x, wp.y)
				if absf(fy - lerpf(float(fls[s]), float(fls[s + 1]), u / ln)) < 3.0:
					_torch(Vector3(wp.x, fy, wp.y), atan2(side.x * sg, side.y * sg))
				# 矿道木架（隔一支火把一个）
				if int((acc + u) / 26.0) % 3 == 0:
					var p0 := c + side * (tw * 0.5 - 1.2)
					var p1 := c - side * (tw * 0.5 - 1.2)
					var y0 := height(p0.x, p0.y)
					var y1 := height(p1.x, p1.y)
					var top := float(cv["ceil"]) - 4.0
					if y0 < top - 4.0 and y1 < top - 4.0:
						_col(p0.x, p0.y, y0 - 0.2, top, 0.9, 0.9, TIMBER)
						_col(p1.x, p1.y, y1 - 0.2, top, 0.9, 0.9, TIMBER)
						_wall(p0, p1, top, top + 0.85, 0.9, TIMBER * 0.9, false)
				u += 26.0
			acc += ln
	# 晶簇（洞厅边上，发光、不挡路）
	for hl: Array in cv["halls"]:
		var c2: Vector2
		var rad := 10.0
		if str(hl[0]) == "disc":
			c2 = hl[1]
			rad = float(hl[2]) - 2.5
		else:
			c2 = (hl[1] as Rect2).get_center()
			rad = minf((hl[1] as Rect2).size.x, (hl[1] as Rect2).size.y) * 0.5 - 3.0
		var ncry := 1
		if str(hl[0]) == "rect":
			var hr: Rect2 = hl[1]
			ncry = 2 if hr.get_area() > 2000.0 else 0
			for kr0: Dictionary in map["key_rooms"]:
				var rm: AABB = kr0["room"]
				if Rect2(rm.position.x, rm.position.z, rm.size.x, rm.size.z).intersects(hr.grow(-1.0)):
					ncry = 0
		for i in ncry:
			var ang := rng.randf() * TAU
			var q := c2 + Vector2(cos(ang), sin(ang)) * rad
			var y := height(q.x, q.y)
			if y > 30.0:
				continue
			_crystal(Vector3(q.x, y, q.y), rng, CRYSTAL if not lab else GREEN_GLOW)
	# 光井（进出洞窟的地方）：一束从顶上照下来的光
	for lk: Dictionary in map["links"]:
		var b2: Vector3 = lk["b"]
		var by := height(b2.x, b2.z)
		var top2 := ceil_at(b2.x, b2.z)
		_sb(Vector3(3.2, top2 - by - 0.4, 3.2), _xf(Vector3(b2.x, (by + top2) * 0.5, b2.z), 0.4), Color(0.80, 0.92, 1.0), 0.55, false, 1.0)
		for i in 8:
			var ang2 := TAU * float(i) / 8.0
			var rp := Vector3(b2.x + cos(ang2) * 3.4, by, b2.z + sin(ang2) * 3.4)
			_sb(Vector3(0.9, 0.45, 0.9), _xf(rp + Vector3(0, 0.2, 0), ang2), Color(0.55, 0.50, 0.46), 0.0, false)
		_light(Vector3(b2.x, by + 1.0, b2.z), fl_ri, 1)
	# 钥匙房的门墙（直通洞顶）+ 门
	for kr: Dictionary in map["key_rooms"]:
		if str(kr["layer"]) == "cavern":
			_key_wall(kr)
	# Boss 场地
	for bo: Dictionary in map["bosses"]:
		if str(bo["layer"]) != "cavern":
			continue
		var ar: AABB = bo["arena"]
		var cc := Vector3(ar.get_center().x, ar.position.y, ar.get_center().z)
		if str(bo["key"]) == "worm":
			var alt: Vector3 = bo["altar"]
			var ay := height(alt.x, alt.z)
			_col(alt.x, alt.z, ay, ay + 1.35, 4.2, 4.2, Color(0.42, 0.36, 0.32))
			_col(alt.x, alt.z, ay + 1.35, ay + 1.95, 3.0, 3.0, GOLD * 0.8)
			_sb(Vector3(1.4, 1.4, 1.4), _xf(Vector3(alt.x, ay + 2.9, alt.z), 0.0, Vector3(0.6, 0.6, 0)), Color(1.0, 0.55, 0.25), 0.9, false)
			_light(Vector3(alt.x, ay + 2.0, alt.z), 1, 2)
			for cg: Vector3 in bo["cages"]:
				_cage(Vector3(cg.x, height(cg.x, cg.z), cg.z))
		else:
			for i in 8:
				var ang3 := TAU * float(i) / 8.0 + 0.2
				var sp := Vector3(cc.x + cos(ang3) * 27.0, 0, cc.z + sin(ang3) * 27.0)
				var sy := height(sp.x, sp.z)
				_col(sp.x, sp.z, sy - 0.2, sy + 4.15 + float(i % 3), 1.8, 1.2, Color(0.40, 0.36, 0.40), ang3)
				_sb(Vector3(0.5, 0.9, 0.3), _xf(Vector3(sp.x, sy + 2.6, sp.z) - Vector3(cos(ang3), 0, sin(ang3)) * 0.68, ang3 + PI * 0.5), Color(0.75, 0.45, 1.0), 0.8, false)
			_light(cc + Vector3(0, 1.0, 0), fl_ri, 1)


func _torch(p: Vector3, yaw: float) -> void:
	var fw := Vector3(-sin(yaw), 0, -cos(yaw))
	_col(p.x, p.z, p.y, p.y + 2.45, 0.35, 0.35, TIMBER, yaw, 0.0, false)
	_sb(Vector3(0.6, 0.6, 0.6), _xf(p + Vector3(0, 2.75, 0), yaw + 0.785), FLAME, 0.95, false)
	_light(p + Vector3(0, 2.5, 0) + fw * 0.5, 4 if not lab else 2, 2)


func _crystal(p: Vector3, rng: RandomNumberGenerator, c: Color) -> void:
	for i in 4:
		var s := rng.randf_range(0.5, 1.1)
		var h := rng.randf_range(1.6, 4.2)
		_sb(Vector3(s, h, s), _xf(p + Vector3(rng.randf_range(-1.2, 1.2), h * 0.4, rng.randf_range(-1.2, 1.2)), rng.randf() * TAU,
				Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))), c * rng.randf_range(0.8, 1.0), 0.75, false)
	_light(p + Vector3(0, 1.5, 0), 2, 1)


func _cage(p: Vector3) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_col(p.x + sx * 2.4, p.z + sz * 2.4, p.y, p.y + 5.15, 0.4, 0.4, IRON, 0.0, 0.0, false)
	for i in 5:
		var o := -2.0 + float(i)
		_col(p.x + o, p.z - 2.4, p.y, p.y + 5.15, 0.16, 0.16, IRON * 0.9, 0.0, 0.0, false)
		_col(p.x + o, p.z + 2.4, p.y, p.y + 5.15, 0.16, 0.16, IRON * 0.9, 0.0, 0.0, false)
	_sb(Vector3(5.4, 0.4, 5.4), _xf(p + Vector3(0, 5.35, 0)), IRON, 0.0, false)


## 钥匙房朝门那一面的墙（开着门洞）+ 门本身。洞窟 / 坑里：墙顶到 wall_top（洞顶 / 盖板）
func _key_wall(kr: Dictionary) -> void:
	var room: AABB = kr["room"]
	var d: Vector3 = kr["dir"]
	var door: Vector3 = kr["door"]
	var w: float = kr["door_w"]
	var dh: float = kr["door_h"]
	var y0 := room.position.y
	var y1: float = kr["wall_top"]
	var col := Color(0.42, 0.36, 0.32) if not lab else CONC_D
	var a: Vector2
	var b: Vector2
	if absf(d.x) > 0.5:
		var x := door.x
		a = Vector2(x, room.position.z)
		b = Vector2(x, room.end.z)
	else:
		var z := door.z
		a = Vector2(room.position.x, z)
		b = Vector2(room.end.x, z)
	var along := (b - a).normalized()
	var dc := Vector2(door.x, door.z)
	var t0 := (dc - a).dot(along) - w * 0.5
	var t1 := (dc - a).dot(along) + w * 0.5
	var ln := a.distance_to(b)
	_wall(a, a + along * t0, y0 - 0.1, y1, WALL_T + 0.2, col)
	_wall(a + along * t1, b, y0 - 0.1, y1, WALL_T + 0.2, col)
	_wall(a + along * t0, a + along * t1, y0 + dh, y1, WALL_T + 0.2, col)
	# 门框：两根朱红柱 + 一道铜梁 + 门楣上一块牌
	var fw := Vector2(d.x, d.z)
	for t: float in [t0 - 0.3, t1 + 0.3]:
		var q := a + along * t + fw * 0.12
		_col(q.x, q.y, y0, y0 + dh + 0.65, 0.8 if absf(along.x) > 0.5 else 1.4, 1.4 if absf(along.x) > 0.5 else 0.8, VERM)
	var bq := a + along * ((t0 + t1) * 0.5) + fw * 0.16
	_wall(a + along * (t0 - 0.8) + fw * 0.16, a + along * (t1 + 0.8) + fw * 0.16, y0 + dh + 0.05, y0 + dh + 0.75, 1.0, BRONZE)
	_sb(Vector3(2.4, 1.0, 0.24), _xf(Vector3(bq.x, y0 + dh + 1.45, bq.y) + Vector3(fw.x, 0, fw.y) * 0.6, MapDef.yaw_of(d)), VERM * 0.9, 0.25, false)
	_door(kr["id"], Vector3(door.x, y0, door.z), MapDef.yaw_of(d), w, dh)
	if ln < 0.1:
		return


# =====================================================================
# 天工秘所
# =====================================================================

func _gen_lab() -> void:
	var n1 := FastNoiseLite.new()
	n1.seed = 3301
	n1.frequency = 1.0 / 70.0
	n1.fractal_octaves = 2
	var wl: Dictionary = map["wall"]
	var w_in: float = wl["in"]
	var w_out: float = wl["out"]
	var w_top: float = wl["top"]
	var chasm: float = wl["chasm"]
	var w := _s_w
	for lz in _s_d:
		var z := (float(lz + _s_z0) + 0.5) * CELL
		for lx in w:
			var x := (float(lx + _s_x0) + 0.5) * CELL
			var i := lz * w + lx
			var e := maxf(absf(x), absf(z))
			var h := _base_y
			var ri := 0
			var kind := 0
			if e < w_in:
				if n1.get_noise_2d(x, z) > 0.32:
					ri = 1                  # 荒草
				elif n1.get_noise_2d(x * 2.0 + 40.0, z * 2.0) < -0.68:
					kind = K_PATH           # 锈土
			elif e < w_out:
				h = w_top
				# 垛口：外沿一圈每四米高一级
				if e > w_out - 2.0 and posmod(int(floorf((x + z) / 4.0)), 2) == 0:
					h = w_top + 2.0
			elif e < chasm:
				h = float(wl["chasm_y"]) + roundf(n1.get_noise_2d(x, z) * 2.0)
				ri = 4
			else:
				h = float(wl["rim_y"]) + roundf(n1.get_noise_2d(x * 0.5, z * 0.5) * 6.0)
				ri = 4
			_s_h[i] = h
			_s_r[i] = ri
			_s_k[i] = kind
	# 路：石板路 + 铜边
	for rd: Array in map["roads"]:
		var a: Vector2 = rd[0]
		var b: Vector2 = rd[1]
		var rw: float = rd[2]
		_each(_poly_rect([a, b], rw), func(li: int, i: int, x: float, z: float) -> void:
			if li != 0:
				return
			var dd := Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b).distance_to(Vector2(x, z))
			if dd < rw * 0.5:
				_put(li, i, _base_y, 0, K_ROAD_EDGE if dd > rw * 0.5 - 1.6 else K_ROAD))
	# 楼里铺石板（地块网格里的棋盘格）
	for bl: Dictionary in map["buildings"]:
		_rect(bl["rect"], _base_y, 0, 16)
	# 撤离台：高出 1 米的台子（E2 / E5 高 6 米，朝园区里一侧一道台阶）
	for e2: Dictionary in map["extracts"]:
		var ep: Vector3 = e2["pos"]
		var es: Vector3 = e2["size"]
		var raised: float = e2["raised"]
		var r := Rect2(ep.x - es.x * 0.5, ep.z - es.z * 0.5, es.x, es.z)
		_rect(r.grow(4.0), _base_y, 0, 0)
		_rect(r, ep.y, 0, 16)
		if raised > 0.0:
			var inward := Vector2(-signf(ep.x), 0.0) if absf(ep.x) > absf(ep.z) else Vector2(0.0, -signf(ep.z))
			var steps := int(raised + 1.0)
			for s in steps:
				var off := (es.z * 0.5 if inward.x == 0.0 else es.x * 0.5) + float(s) * 2.0 + 1.0
				var c := Vector2(ep.x, ep.z) + inward * off
				var sz := Vector2(8, 2) if inward.x == 0.0 else Vector2(2, 8)
				_rect(Rect2(c - sz * 0.5, sz), ep.y - float(s + 1), 0, K_ROAD)
	# 双子斗场：下沉的圆形斗场 + 一圈台阶看台 + 东西两道坡道
	var bw: Dictionary = map["bowl"]
	var bc: Vector2 = bw["c"]
	var br: float = bw["r"]
	var bf: float = bw["floor"]
	var bo: float = bw["outer"]
	_each(Rect2(bc - Vector2(bo, bo), Vector2(bo, bo) * 2.0), func(li: int, i: int, x: float, z: float) -> void:
		var dd := Vector2(x, z).distance_to(bc)
		if dd < br:
			_put(li, i, bf, 3, 0)
		elif dd < bo:
			var h := minf(bf + 2.0 * ceilf((dd - br) / 2.25), _base_y)
			# 坡道（东西两侧）：一米一级、两米一步
			if absf(z - bc.y) < 4.0:
				h = minf(bf + ceilf((dd - br) / 1.125), _base_y)
			_put(li, i, h, 3 if dd < br + 2.0 else 0, K_ROAD if absf(z - bc.y) < 4.0 else 0))
	# 高台（镇尸营 / 百炼坊的 Boss 台）
	for pf: Dictionary in map["platforms"]:
		var r2: Rect2 = pf["rect"]
		var top: float = pf["top"]
		_rect(r2, top, 3, 0)
		var sd: String = pf["stairs"]
		var nst := int(top - _base_y)
		for s2 in nst:
			var c2: Vector2
			var sz2: Vector2
			if sd == "e":
				c2 = Vector2(r2.end.x + 1.0 + float(s2) * 2.0, r2.get_center().y)
				sz2 = Vector2(2, 10)
			else:
				c2 = Vector2(r2.get_center().x, r2.position.y - 1.0 - float(s2) * 2.0)
				sz2 = Vector2(10, 2)
			_rect(Rect2(c2 - sz2 * 0.5, sz2), top - float(s2 + 1), 3, K_ROAD)
	# 钥匙房：坑 / 台下 / 小屋
	for kr: Dictionary in map["key_rooms"]:
		var room: AABB = kr["room"]
		var rr := Rect2(room.position.x, room.position.z, room.size.x, room.size.z)
		match str(kr["kind"]):
			"pit":
				var fy := room.position.y
				var d: Vector3 = kr["dir"]
				var dv := Vector2(d.x, d.z)
				var depth := _base_y - fy
				_rect(rr, fy, 0, 16)
				# 门前的空场（8 米）+ 坡道（一米一级、两米一步）
				var apron: Rect2
				if absf(d.x) > 0.5:
					apron = Rect2(rr.position.x - 8.0 if d.x < 0.0 else rr.end.x, rr.position.y, 8.0, rr.size.y)
				else:
					apron = Rect2(rr.position.x, rr.position.y - 8.0 if d.z < 0.0 else rr.end.y, rr.size.x, 8.0)
				_rect(apron, fy, 0, K_PATH)
				var door: Vector3 = kr["door"]
				var start := Vector2(door.x, door.z) + dv * 8.0
				var side := Vector2(-dv.y, dv.x)
				for s3 in int(depth):
					var c3 := start + dv * (float(s3) * 2.0 + 1.0)
					var sz3 := (Vector2(2, 8) if absf(dv.x) > 0.5 else Vector2(8, 2))
					_rect(Rect2(c3 - sz3 * 0.5, sz3), fy + float(s3 + 1), 0, K_ROAD)
				# 坑边一圈铁栏（摆件里做）
			"deck":
				_rect(rr, _base_y, 0, 16)
			"hut":
				_rect(rr, _base_y, 0, 16)
	# 梯亭里的井（楼梯往下 5 米，井底传到地下室）
	for lk: Dictionary in map["links"]:
		var cc: Vector3 = lk["center"]
		var f: Vector3 = lk["f"]
		var fv := Vector2(f.x, f.z)
		var sv := Vector2(-fv.y, fv.x)
		_each(Rect2(Vector2(cc.x, cc.z) - Vector2(7, 7), Vector2(14, 14)), func(li: int, i: int, x: float, z: float) -> void:
			var q := Vector2(x - cc.x, z - cc.z)
			var al := q.dot(fv)
			var lat := absf(q.dot(sv))
			if al <= 0.5 and al >= -6.0 and lat <= 3.0:
				_put(li, i, _base_y - clampf(floorf((0.5 - al) / 1.2), 0.0, 5.0), 0, K_ROAD))
	_gen_cave(map["cave"], 4, 2)
	_lab_structures()


func _lab_structures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for b: Dictionary in map["buildings"]:
		_building(b, rng)
	_compound()
	for kr: Dictionary in map["key_rooms"]:
		_lab_key_room(kr)
	_lab_platform_decor()
	_lab_lamps()
	_lab_props(rng)
	# 尸傀召唤柱（夜里尸潮的地标）
	for hp: Vector3 in map["horde_points"]:
		var y := height(hp.x, hp.z)
		_col(hp.x, hp.z, y, y + 1.15, 3.0, 3.0, IRON)
		_col(hp.x, hp.z, y + 1.15, y + 6.35, 1.4, 1.4, Color(0.20, 0.22, 0.20), 0.3)
		_sb(Vector3(1.2, 1.2, 1.2), _xf(Vector3(hp.x, y + 7.2, hp.z), 0.0, Vector3(0.6, 0.0, 0.6)), GREEN_GLOW, 0.85, false)
		_light(Vector3(hp.x, y + 2.0, hp.z), 2, 1)
	# 天工塔：院子西北角的五层机关塔（全图的地标，飞着老远就看得见）
	_pagoda(Vector3(-82, _base_y, -30))
	# 架空的铜管廊：从北边匠坊一路架到南边（管子在头顶上、不挡路，支架挡路）
	_pipeline(Vector2(132, -150), Vector2(132, 110), 7.5)
	_pipeline(Vector2(-200, 230), Vector2(-60, 230), 6.5)
	# 围墙内侧四角 + 四边中间的望楼
	for c: Vector2 in [Vector2(-384, -384), Vector2(384, -384), Vector2(-384, 384), Vector2(384, 384),
			Vector2(0, -386), Vector2(0, 386), Vector2(-386, 0), Vector2(386, 0)]:
		_watchtower(Vector3(c.x, _base_y, c.y))
	# 双子斗场：召唤台 + 两尊铜卫像
	var bw: Dictionary = map["bowl"]
	var bc: Vector2 = bw["c"]
	for bo: Dictionary in map["bosses"]:
		if str(bo["key"]) == "twin":
			var alt: Vector3 = bo["altar"]
			_col(alt.x, alt.z, alt.y, alt.y + 1.15, 4.4, 4.4, CONC_D)
			_col(alt.x, alt.z, alt.y + 1.15, alt.y + 1.75, 3.2, 3.2, BRONZE)
			_sb(Vector3(1.5, 1.5, 1.5), _xf(Vector3(alt.x, alt.y + 2.8, alt.z), 0.0, Vector3(0.6, 0.6, 0)), VERM, 0.8, false)
			_light(Vector3(alt.x, alt.y + 2.0, alt.z), 3, 2)
	for sx: float in [-1.0, 1.0]:
		var sp := Vector3(bc.x, _base_y, bc.y + sx * 47.0)
		_col(sp.x, sp.z, sp.y, sp.y + 1.45, 4.0, 4.0, CONC_D)
		_col(sp.x, sp.z, sp.y + 1.45, sp.y + 7.35, 2.4, 1.8, BRONZE)
		_col(sp.x, sp.z, sp.y + 7.35, sp.y + 9.15, 1.8, 1.8, BRONZE_D)
		_sb(Vector3(1.2, 0.5, 0.3), _xf(Vector3(sp.x, sp.y + 8.4, sp.z - sx * 0.98)), Color(1.0, 0.5, 0.3), 0.9, false)
	_cave_structures()


## 一栋能进的楼：四面墙（留门洞、门楣）、门框（朱红柱 + 铜梁）、窗、柱子、二层平台 + 楼梯、屋顶（单独一个网格）
func _building(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2 = b["rect"]
	var st: String = b["style"]
	var storeys := int(b.get("storeys", 1))
	var y0 := _base_y
	var hgt := float(storeys) * STOREY + 0.6
	var wall_c := CONC
	var trim := VERM
	match st:
		"shed":
			wall_c = RUST
			trim = IRON
		"store":
			wall_c = CONC_D
			trim = IRON
		"dorm":
			wall_c = Color(0.82, 0.78, 0.70)
			trim = WOOD
		"hut":
			wall_c = CONC_D
			trim = VERM
		"kiosk":
			wall_c = Color(0.80, 0.76, 0.68)
			trim = VERM
			hgt = 5.1
		"hall":
			wall_c = Color(0.86, 0.85, 0.82)
		"factory":
			wall_c = CONC_D
			trim = RUST
	if b.has("key_room"):
		hgt = 6.6
	# 门洞表：side → [[沿墙的中心坐标, 宽]]
	var doors := {"n": [], "s": [], "w": [], "e": []}
	for dr: Array in b.get("doors", []):
		var sd: String = dr[0]
		var off: float = dr[1]
		var dw: float = dr[2]
		var c := (r.get_center().x if sd == "n" or sd == "s" else r.get_center().y) + off
		(doors[sd] as Array).append([c, dw])
	if b.has("key_room"):
		for kr: Dictionary in map["key_rooms"]:
			if kr["id"] == b["key_room"]:
				var kd: Vector3 = kr["door"]
				(doors["w"] as Array).append([kd.z, float(kr["door_w"])])
	var t := WALL_T
	var sides := {"n": [Vector2(r.position.x, r.position.y + t * 0.5), Vector2(r.end.x, r.position.y + t * 0.5)],
			"s": [Vector2(r.position.x, r.end.y - t * 0.5), Vector2(r.end.x, r.end.y - t * 0.5)],
			"w": [Vector2(r.position.x + t * 0.5, r.position.y + t), Vector2(r.position.x + t * 0.5, r.end.y - t)],
			"e": [Vector2(r.end.x - t * 0.5, r.position.y + t), Vector2(r.end.x - t * 0.5, r.end.y - t)]}
	var outn := {"n": Vector2(0, -1), "s": Vector2(0, 1), "w": Vector2(-1, 0), "e": Vector2(1, 0)}
	for sd: String in sides:
		var a: Vector2 = sides[sd][0]
		var bb: Vector2 = sides[sd][1]
		var horiz := sd == "n" or sd == "s"
		var ds: Array = doors[sd]
		ds.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		var cur := a.x if horiz else a.y
		var endc := bb.x if horiz else bb.y
		var pt := func(v: float) -> Vector2: return Vector2(v, a.y) if horiz else Vector2(a.x, v)
		var on: Vector2 = outn[sd]
		# 先排出实墙段（门洞之间），每段一面墙；主楼 / 工坊的墙脚再压一道深色勒脚（比墙两面各鼓出 8 厘米，门柱旁断开，
		# 转角处多伸出 8 厘米盖住侧墙的墙面）
		var skirt := st == "hall" or st == "factory"
		var start := a.x if horiz else a.y
		var spans: Array = []
		for dd: Array in ds:
			var d0 := float(dd[0]) - float(dd[1]) * 0.5
			var d1 := float(dd[0]) + float(dd[1]) * 0.5
			if d0 > cur:
				spans.append([cur, d0])
			_wall(pt.call(d0), pt.call(d1), y0 + DOOR_H, y0 + hgt, t, wall_c)
			# 门框：两根柱子 + 一道梁（朱红 / 铁），柱子比墙厚出 15 厘米、往门洞里探出 10 厘米
			for e: float in [d0 - 0.25, d1 + 0.25]:
				var q: Vector2 = pt.call(e)
				_col(q.x, q.y, y0, y0 + DOOR_H + 0.55, 0.7 if horiz else t + 0.3, t + 0.3 if horiz else 0.7, trim)
			var lq: Vector2 = pt.call((d0 + d1) * 0.5) + on * 0.3
			_sb(Vector3(float(dd[1]) + 1.6 if horiz else 0.64, 0.6, 0.64 if horiz else float(dd[1]) + 1.6), _xf(Vector3(lq.x, y0 + DOOR_H + 0.3, lq.y)), BRONZE if trim == VERM else trim * 1.1, 0.0, false)
			cur = d1
		if endc > cur:
			spans.append([cur, endc])
		for sp: Array in spans:
			var c0: float = sp[0]
			var c1: float = sp[1]
			_wall(pt.call(c0), pt.call(c1), y0 - 0.1, y0 + hgt, t, wall_c)
			if skirt:
				var s0 := c0 - 0.08 if (horiz and absf(c0 - start) < 0.01) else (c0 + 0.6 if absf(c0 - start) >= 0.01 else c0 + 0.1)
				var s1 := c1 + 0.08 if (horiz and absf(c1 - endc) < 0.01) else (c1 - 0.6 if absf(c1 - endc) >= 0.01 else c1 - 0.1)
				if s1 - s0 > 0.1:
					_wall(pt.call(s0), pt.call(s1), y0 - 0.1, y0 + 0.62, t + 0.16, IRON, false)
		# 窗：外墙面上一排深色玻璃（鼓出 8 厘米），夜里透一点冷光
		if st != "shed" and st != "kiosk":
			var span := absf(endc - (a.x if horiz else a.y))
			var nwin := int(span / 6.0)
			for s in storeys:
				var wy := y0 + float(s) * STOREY + 2.9
				for k in nwin:
					var wc := (a.x if horiz else a.y) + (float(k) + 0.5) * span / float(nwin)
					var blocked := false
					for dd2: Array in ds:
						if absf(wc - float(dd2[0])) < float(dd2[1]) * 0.5 + 1.6:
							blocked = true
					if blocked and s == 0:
						continue
					var wq: Vector2 = pt.call(wc) + on * (t * 0.5 + 0.08 - 0.15)
					_sb(Vector3(1.8 if horiz else 0.3, 1.5, 0.3 if horiz else 1.8), _xf(Vector3(wq.x, wy, wq.y)), GLASS, 0.12, false, 1.0)
		# 墙脚一道深色的勒脚（鼓出 6 厘米，比地面高 0.62 米）
	# 柱子（大楼）
	if r.size.x > 40.0 and r.size.y > 30.0:
		var nx := int(r.size.x / 14.0)
		var nz := int(r.size.y / 14.0)
		for ix in range(1, nx):
			for iz in range(1, nz):
				var cx := r.position.x + r.size.x * float(ix) / float(nx)
				var cz := r.position.y + r.size.y * float(iz) / float(nz)
				var st2: Array = b.get("stairs", [])
				if not st2.is_empty() and Vector2(cx, cz).distance_to(st2[0] as Vector2) < 7.0:
					continue
				_col(cx, cz, y0, y0 + hgt - 0.02, 0.9, 0.9, VERM if st == "hall" else IRON)
	# 二层平台 + 楼梯 + 栏杆（平台单独一个网格：在楼下时藏起来）
	if b.has("upper"):
		var up: Rect2 = b["upper"]
		var stp: Array = b["stairs"]
		var s0: Vector2 = stp[0]
		var sdir: Vector2 = stp[1]
		var sw: float = stp[2]
		var top_y := y0 + STOREY
		# 楼梯：十级、每级 0.55 米，一级一米（实心的，底下不空）
		for k in 10:
			var c := s0 + sdir * (float(k) + 0.5)
			var hy := 0.55 * float(k + 1)
			_sb(Vector3(sw if sdir.y != 0.0 else 1.0, hy, 1.0 if sdir.y != 0.0 else sw), _xf(Vector3(c.x, y0 + hy * 0.5 - 0.02, c.y)), CONC_D * (1.0 if k % 2 == 0 else 0.96))
		_begin_roof(str(b["id"]) + "_up", r, top_y - 0.5)
		_sb(Vector3(up.size.x, 0.5, up.size.y), _xf(Vector3(up.get_center().x, top_y - 0.25, up.get_center().y)), Color(0.58, 0.56, 0.53))
		# 平台沿口：铜边 + 栏杆（不挡路）
		var lip := up.end.y if up.end.y < r.end.y - 1.0 else up.end.x
		if up.end.y < r.end.y - 1.0:
			_wall(Vector2(up.position.x + t, lip - 0.15), Vector2(up.end.x - t, lip - 0.15), top_y - 0.62, top_y - 0.04, 0.34, BRONZE, false)
			_wall(Vector2(up.position.x + t, lip - 0.3), Vector2(up.end.x - t, lip - 0.3), top_y, top_y + 1.05, 0.12, IRON, false)
		else:
			_wall(Vector2(lip - 0.15, up.position.y + t), Vector2(lip - 0.15, up.end.y - t), top_y - 0.62, top_y - 0.04, 0.34, BRONZE, false)
			_wall(Vector2(lip - 0.3, up.position.y + t), Vector2(lip - 0.3, up.end.y - t), top_y, top_y + 1.05, 0.12, IRON, false)
		# 楼上 K4 这类房间的墙也算在平台这一组里
		for kr2: Dictionary in map["key_rooms"]:
			if str(kr2["kind"]) == "floor" and r.has_point(Vector2((kr2["door"] as Vector3).x, (kr2["door"] as Vector3).z)):
				_upper_room(kr2)
		_end_roof()
	# 屋顶：楼板 + 女儿墙 + 朱红檐梁 + 楼顶的铜机关件；主楼 / 梯亭上面再加一层中式屋顶
	var ry := y0 + hgt
	_begin_roof(str(b["id"]), r, ry)
	_sb(Vector3(r.size.x + 0.5, 0.45, r.size.y + 0.5), _xf(Vector3(r.get_center().x, ry + 0.225, r.get_center().y)), Color(0.50, 0.50, 0.50))
	var par := r.grow(0.25)
	for e2: Array in [[Vector2(par.position.x, par.position.y + 0.3), Vector2(par.end.x, par.position.y + 0.3)], [Vector2(par.position.x, par.end.y - 0.3), Vector2(par.end.x, par.end.y - 0.3)],
			[Vector2(par.position.x + 0.3, par.position.y + 0.6), Vector2(par.position.x + 0.3, par.end.y - 0.6)], [Vector2(par.end.x - 0.3, par.position.y + 0.6), Vector2(par.end.x - 0.3, par.end.y - 0.6)]]:
		_wall(e2[0], e2[1], ry + 0.45, ry + 1.27, 0.6, wall_c * 0.94)
	# 檐梁：比墙面鼓出 8 厘米
	for e3: Array in [[Vector2(r.position.x - 0.1, r.position.y - 0.2), Vector2(r.end.x + 0.1, r.position.y - 0.2)], [Vector2(r.position.x - 0.1, r.end.y + 0.2), Vector2(r.end.x + 0.1, r.end.y + 0.2)]]:
		_wall(e3[0], e3[1], ry - 0.72, ry - 0.02, 0.24, trim, false)
	if st == "hall" or st == "kiosk":
		var rw := r.size.x * (0.62 if st == "hall" else 0.8)
		var rdd := r.size.y * (0.62 if st == "hall" else 0.8)
		var rc := Vector3(r.get_center().x, ry + 0.45, r.get_center().y)
		var mk := func(a: Array) -> void:
			_box(a, Vector3(rw, 2.55, rdd), _xf(rc + Vector3(0, 1.275, 0)), Color(0.86, 0.85, 0.82), 0.0, 0.85)
			_roof(a, rc + Vector3(0, 2.55, 0), rw, rdd, 0.0, TILE)
		_with_tmp(mk, true)
	else:
		# 楼顶机关件：一只大铜齿轮（两块错开 45° 的方块）+ 水柜
		var gq := Vector3(r.position.x + r.size.x * 0.3, ry + 0.45, r.position.y + r.size.y * 0.35)
		_sb(Vector3(3.0, 0.55, 3.0), _xf(gq + Vector3(0, 0.3, 0)), BRONZE, 0.0, false)
		_sb(Vector3(3.0, 0.55, 3.0), _xf(gq + Vector3(0, 0.42, 0), PI * 0.25), BRONZE_D, 0.0, false)
		var tq := Vector3(r.position.x + r.size.x * 0.7, ry + 0.45, r.position.y + r.size.y * 0.6)
		_col(tq.x, tq.z, tq.y, tq.y + 2.35, 2.6, 2.6, RUST)
		if st == "factory":
			for i in 3:
				var cq := Vector3(r.position.x + 12.0 + float(i) * 9.0, ry + 0.45, r.end.y - 6.0)
				_col(cq.x, cq.z, cq.y, cq.y + 9.15, 2.2, 2.2, IRON)
				_col(cq.x, cq.z, cq.y + 9.15, cq.y + 9.75, 2.8, 2.8, RUST)
	_end_roof()
	# 屋里的东西：沿墙的货架 / 木箱 / 工作台（梯亭里是井、钥匙房小屋里放箱子，都不摆）
	var inner2 := r.grow(-t - 0.9)
	var nprop := 0 if (st == "kiosk" or b.has("key_room")) else int(r.get_area() / 120.0) + 1
	for i in nprop:
		var side := i % 4
		var q2: Vector2
		match side:
			0:
				q2 = Vector2(rng.randf_range(inner2.position.x + 2.0, inner2.end.x - 2.0), inner2.position.y + 0.4)
			1:
				q2 = Vector2(rng.randf_range(inner2.position.x + 2.0, inner2.end.x - 2.0), inner2.end.y - 0.4)
			2:
				q2 = Vector2(inner2.position.x + 0.4, rng.randf_range(inner2.position.y + 2.0, inner2.end.y - 2.0))
			_:
				q2 = Vector2(inner2.end.x - 0.4, rng.randf_range(inner2.position.y + 2.0, inner2.end.y - 2.0))
		if _near_door(q2, b, 3.5):
			continue
		var st3: Array = b.get("stairs", [])
		if not st3.is_empty() and q2.distance_to(st3[0] as Vector2) < 12.0:
			continue
		var kind := rng.randi() % 3
		if kind == 0:
			_crate(Vector3(q2.x, y0, q2.y), rng)
		elif kind == 1:
			_sb(Vector3(3.2 if side < 2 else 0.9, 2.45, 0.9 if side < 2 else 3.2), _xf(Vector3(q2.x, y0 + 1.22, q2.y)), WOOD)
			_sb(Vector3(3.0 if side < 2 else 0.6, 0.1, 0.6 if side < 2 else 3.0), _xf(Vector3(q2.x, y0 + 1.6, q2.y)), BRONZE_D, 0.0, false)
		else:
			_sb(Vector3(2.4, 1.05, 1.4), _xf(Vector3(q2.x, y0 + 0.52, q2.y), 0.0 if side < 2 else PI * 0.5), IRON)
			_sb(Vector3(0.8, 0.45, 0.6), _xf(Vector3(q2.x, y0 + 1.27, q2.y), 0.3), BRONZE, 0.0, false)
	# 灯：每栋楼门口一盏
	for dr2: Array in b.get("doors", []):
		var sd2: String = dr2[0]
		var on2: Vector2 = outn[sd2]
		var cpos := Vector2(r.get_center().x + float(dr2[1]), r.position.y if sd2 == "n" else r.end.y) if (sd2 == "n" or sd2 == "s") \
				else Vector2(r.position.x if sd2 == "w" else r.end.x, r.get_center().y + float(dr2[1]))
		_light(Vector3(cpos.x + on2.x * 3.0, y0 + 3.5, cpos.y + on2.y * 3.0), 0, 1)


func _near_door(q: Vector2, b: Dictionary, rad: float) -> bool:
	var r: Rect2 = b["rect"]
	for dr: Array in b.get("doors", []):
		var sd: String = dr[0]
		var c := Vector2(r.get_center().x + float(dr[1]), r.position.y if sd == "n" else r.end.y) if (sd == "n" or sd == "s") \
				else Vector2(r.position.x if sd == "w" else r.end.x, r.get_center().y + float(dr[1]))
		if c.distance_to(q) < float(dr[2]) * 0.5 + rad:
			return true
	return false


func _crate(p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(1.2, 1.7)
	var yaw := rng.randf_range(-0.3, 0.3)
	_sb(Vector3(s, s - 0.03, s), _xf(p + Vector3(0, (s - 0.03) * 0.5, 0), yaw), WOOD * rng.randf_range(0.9, 1.1))
	_sb(Vector3(s + 0.16, 0.2, s + 0.16), _xf(p + Vector3(0, s * 0.62, 0), yaw), IRON, 0.0, false)
	if rng.randf() < 0.45:
		var s2 := s * 0.7
		_sb(Vector3(s2, s2 - 0.03, s2), _xf(p + Vector3(0, s + (s2 - 0.03) * 0.5, 0), yaw + 0.5), WOOD * 1.08)


## 二层上的钥匙房（K4）：三面墙 + 开门的那面
func _upper_room(kr: Dictionary) -> void:
	var room: AABB = kr["room"]
	var y0 := room.position.y
	var y1 := y0 + STOREY + 0.12
	var r := Rect2(room.position.x, room.position.z, room.size.x, room.size.z)
	var d: Vector3 = kr["dir"]
	var t := WALL_T
	if d.x <= 0.5:
		_wall(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), y0, y1, t, CONC)
	if d.x >= -0.5:
		_wall(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), y0, y1, t, CONC)
	_wall(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), y0, y1, t, CONC)
	_wall(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), y0, y1, t, CONC)
	var prev := _tgt_roof
	_tgt_roof = -1
	_key_wall(kr)
	_tgt_roof = prev


## 主楼院墙：四面带院门，院门上一座朱红牌坊
func _compound() -> void:
	var cp: Dictionary = map["compound"]
	var r: Rect2 = cp["rect"]
	var h: float = cp["h"]
	var gates: Array = cp["gates"]
	var y0 := _base_y
	for sd: String in ["n", "s", "w", "e"]:
		var horiz := sd == "n" or sd == "s"
		var fixed := (r.position.y if sd == "n" else r.end.y) if horiz else (r.position.x if sd == "w" else r.end.x)
		var a := r.position.x if horiz else r.position.y + 0.6
		var b := r.end.x if horiz else r.end.y - 0.6
		var cuts: Array = []
		for g: Array in gates:
			if str(g[0]) == sd:
				var c := (r.get_center().x if horiz else r.get_center().y) + float(g[1])
				cuts.append([c - float(g[2]) * 0.5, c + float(g[2]) * 0.5])
		cuts.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		var cur := a
		var pt := func(v: float) -> Vector2: return Vector2(v, fixed) if horiz else Vector2(fixed, v)
		for ct: Array in cuts:
			_wall(pt.call(cur), pt.call(float(ct[0])), y0 - 0.1, y0 + h, 1.2, CONC_D)
			_paifang_at(pt.call((float(ct[0]) + float(ct[1])) * 0.5), 0.0 if horiz else PI * 0.5, float(ct[1]) - float(ct[0]))
			cur = float(ct[1])
		_wall(pt.call(cur), pt.call(b), y0 - 0.1, y0 + h, 1.2, CONC_D)
		# 墙头一道铁皮压顶（鼓出 6 厘米）
		_wall(pt.call(a), pt.call(b), y0 + h, y0 + h + 0.32, 1.34, IRON, false)


## 院门牌坊（机关坊样式：朱红立柱、铜横梁、墨瓦小檐）
func _paifang_at(c: Vector2, yaw: float, w: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var y0 := _base_y
	for sx: float in [-1.0, 1.0]:
		var q := Vector3(c.x, y0, c.y) + bs * Vector3(sx * (w * 0.5 + 0.6), 0, 0)
		_col(q.x, q.z, y0, y0 + 1.05, 1.7, 1.7, CONC_D, yaw)
		_col(q.x, q.z, y0 + 1.05, y0 + 8.35, 1.0, 1.0, VERM, yaw)
	_sb(Vector3(w + 2.6, 0.85, 1.1), _xf(Vector3(c.x, y0 + 7.4, c.y), yaw), BRONZE)
	_sb(Vector3(w * 0.6, 1.25, 0.5), _xf(Vector3(c.x, y0 + 8.45, c.y), yaw), VERM * 0.9)
	_with_tmp(func(a: Array) -> void: _roof(a, Vector3(c.x, y0 + 9.1, c.y), w + 1.6, 1.0, yaw, TILE), true)
	_light(Vector3(c.x, y0 + 4.0, c.y), 0, 1)


## 研究所的钥匙房：坑里的（门墙 + 盖板）、高台下的（门墙 + 顶板）、小屋（楼的那套已经建了墙，这里只补门）
func _lab_key_room(kr: Dictionary) -> void:
	var room: AABB = kr["room"]
	var r := Rect2(room.position.x, room.position.z, room.size.x, room.size.z)
	match str(kr["kind"]):
		"pit":
			_key_wall(kr)
			# 盖板（和地面齐平、高出 0.35 米），单独一个网格：人在房里时藏起来
			_begin_roof(str(kr["id"]), r, _base_y)
			_sb(Vector3(r.size.x + 0.4, 0.37, r.size.y + 0.4), _xf(Vector3(r.get_center().x, _base_y + 0.165, r.get_center().y)), Color(0.52, 0.50, 0.47))
			for i in int(r.size.x / 6.0):
				var lx := r.position.x + 3.0 + float(i) * 6.0
				_sb(Vector3(0.35, 0.12, r.size.y - 0.6), _xf(Vector3(lx, _base_y + 0.41, r.get_center().y)), BRONZE_D, 0.0, false)
			var sq := r.get_center()
			_sb(Vector3(2.2, 0.16, 2.2), _xf(Vector3(sq.x, _base_y + 0.43, sq.y), PI * 0.25), VERM, 0.3, false)
			_end_roof()
			# 坑沿铁栏（除了坡道口）
			_pit_rail(kr)
		"deck":
			_key_wall(kr)
			_begin_roof(str(kr["id"]), r, room.end.y)
			_sb(Vector3(r.size.x + 0.4, 0.42, r.size.y + 0.4), _xf(Vector3(r.get_center().x, room.end.y + 0.19, r.get_center().y)), Color(0.60, 0.50, 0.36))
			_end_roof()
		"hut":
			_door(kr["id"], kr["door"], MapDef.yaw_of(kr["dir"]), float(kr["door_w"]), float(kr["door_h"]))
			var dv: Vector3 = kr["dir"]
			var dq: Vector3 = kr["door"]
			for e: float in [-1.0, 1.0]:
				var q := dq + Vector3(-dv.z, 0, dv.x) * e * (float(kr["door_w"]) * 0.5 + 0.35) + dv * 0.12
				_col(q.x, q.z, dq.y, dq.y + float(kr["door_h"]) + 0.55, 0.7, 1.1, VERM)


## 坑沿一圈铁栏（细栏杆不挡路、不碍事；看着是一个坑，不会一脚踩空）
func _pit_rail(kr: Dictionary) -> void:
	var room: AABB = kr["room"]
	var r := Rect2(room.position.x, room.position.z, room.size.x, room.size.z)
	var d: Vector3 = kr["dir"]
	var pit := r
	if absf(d.x) > 0.5:
		pit = pit.expand(Vector2(r.position.x - 8.0 if d.x < 0.0 else r.end.x + 8.0, r.position.y))
	else:
		pit = pit.expand(Vector2(r.position.x, r.position.y - 8.0 if d.z < 0.0 else r.end.y + 8.0))
	var y := _base_y
	var door: Vector3 = kr["door"]
	var ramp_c := Vector2(door.x, door.z)
	var edges := [[pit.position, Vector2(pit.end.x, pit.position.y)], [Vector2(pit.position.x, pit.end.y), pit.end],
			[pit.position, Vector2(pit.position.x, pit.end.y)], [Vector2(pit.end.x, pit.position.y), pit.end]]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := int(a.distance_to(b) / 3.0)
		for i in n:
			var q := a.lerp(b, (float(i) + 0.5) / float(n))
			# 坡道口和盖板那一段不放
			if r.grow(-0.5).has_point(q) or (absf(d.x) > 0.5 and absf(q.y - ramp_c.y) < 5.0 and absf(q.x - r.get_center().x) > r.size.x * 0.5) \
					or (absf(d.z) > 0.5 and absf(q.x - ramp_c.x) < 5.0 and absf(q.y - r.get_center().y) > r.size.y * 0.5):
				continue
			if r.grow(0.6).has_point(q):
				continue
			_col(q.x, q.y, y, y + 1.15, 0.16, 0.16, IRON, 0.0, 0.0, false)
		_wall(a, b, y + 0.95, y + 1.12, 0.3, IRON, false)


## 高台 / 斗场的摆件：栏杆、铜柱、冰晶（镇尸营）、电柱（百炼坊）
func _lab_platform_decor() -> void:
	for pf: Dictionary in map["platforms"]:
		var r: Rect2 = pf["rect"]
		var top: float = pf["top"]
		var cold := top > 58.0
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var q := Vector2(r.get_center().x + sx * (r.size.x * 0.5 - 2.0), r.get_center().y + sz * (r.size.y * 0.5 - 2.0))
				_col(q.x, q.y, top, top + 1.05, 2.4, 2.4, CONC_D)
				_col(q.x, q.y, top + 1.05, top + 7.15, 1.2, 1.2, BRONZE if not cold else Color(0.62, 0.78, 0.86))
				_sb(Vector3(1.0, 1.0, 1.0), _xf(Vector3(q.x, top + 7.8, q.y), 0.0, Vector3(0.6, 0.6, 0)), Color(0.6, 0.9, 1.0) if cold else Color(0.75, 0.85, 1.0), 0.9, false)
				_light(Vector3(q.x, top + 1.5, q.y), 0, 1)
		if cold:
			var rng := RandomNumberGenerator.new()
			rng.seed = 66
			for i in 10:
				var q2 := Vector2(rng.randf_range(r.position.x + 4.0, r.end.x - 4.0), rng.randf_range(r.position.y + 4.0, r.end.y - 30.0))
				var hh := rng.randf_range(1.2, 3.0)
				_sb(Vector3(0.8, hh, 0.8), _xf(Vector3(q2.x, top + hh * 0.4, q2.y), rng.randf() * TAU, Vector3(0.3, 0, 0.2)), Color(0.75, 0.9, 1.0), 0.35, false)


## 冷光灯：沿路每 36 米一盏（铁杆 + 发光灯头），撤离台四角各一盏
func _lab_lamps() -> void:
	for rd: Array in map["roads"]:
		var a: Vector2 = rd[0]
		var b: Vector2 = rd[1]
		var rw: float = rd[2]
		var ln := a.distance_to(b)
		var dir := (b - a) / ln
		var side := Vector2(-dir.y, dir.x)
		var n := int(ln / 36.0)
		for i in n:
			var c := a + dir * (18.0 + float(i) * 36.0) + side * (rw * 0.5 + 1.2) * (1.0 if i % 2 == 0 else -1.0)
			if absf(c.x) > 390.0 or absf(c.y) > 390.0:
				continue
			var y := height(c.x, c.y)
			if absf(y - _base_y) > 0.5 or solid_h(c.x, c.y, y + 5.0) > y + 0.1 or _in_any_building(c, 2.0):
				continue
			_lamp_post(Vector3(c.x, y, c.y))
	for e: Dictionary in map["extracts"]:
		var ep: Vector3 = e["pos"]
		var es: Vector3 = e["size"]
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_lamp_post(Vector3(ep.x + sx * (es.x * 0.5 - 0.6), ep.y, ep.z + sz * (es.z * 0.5 - 0.6)))


func _in_any_building(q: Vector2, pad: float) -> bool:
	for b: Dictionary in map["buildings"]:
		if (b["rect"] as Rect2).grow(pad).has_point(q):
			return true
	for kr: Dictionary in map["key_rooms"]:
		var rm: AABB = kr["room"]
		if Rect2(rm.position.x, rm.position.z, rm.size.x, rm.size.z).grow(pad + 10.0).has_point(q):
			return true
	return false


func _lamp_post(p: Vector3) -> void:
	_col(p.x, p.z, p.y, p.y + 0.45, 0.9, 0.9, CONC_D)
	_col(p.x, p.z, p.y + 0.45, p.y + 4.65, 0.32, 0.32, IRON, 0.0, 0.0, false)
	_sb(Vector3(0.9, 0.75, 0.9), _xf(p + Vector3(0, 5.02, 0)), LAMP, 0.9, false)
	_sb(Vector3(1.2, 0.2, 1.2), _xf(p + Vector3(0, 5.5, 0)), IRON, 0.0, false)
	_light(p + Vector3(0, 4.0, 0), 0, 1)


## 园区里的杂物：货堆、铁桶、管道、铜机关件、推车（避开楼、路中间、要紧的点）
func _lab_props(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 150 and tries < 3000:
		tries += 1
		var q := Vector2(rng.randf_range(-380, 380), rng.randf_range(-380, 380))
		var y := height(q.x, q.y)
		if absf(y - _base_y) > 0.2 or _in_any_building(q, 3.0) or not _lab_clear(q, 14.0):
			continue
		var c := _cell(int(floorf(q.x / CELL)), int(floorf(q.y / CELL)), CELL, {})
		if int(c[4]) == K_ROAD:
			continue
		var p := Vector3(q.x, y, q.y)
		match placed % 5:
			0, 1:
				for i in 3:
					_crate(p + Vector3(rng.randf_range(-2.2, 2.2), 0, rng.randf_range(-2.2, 2.2)), rng)
			2:
				for i in 4:
					var bq := p + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
					_col(bq.x, bq.z, y, y + 1.27 + 0.09 * float(i), 0.95, 0.95, RUST if i % 2 == 0 else IRON, rng.randf() * TAU)
			3:
				# 一截地上的铜管 + 法兰
				var yaw := float(rng.randi() % 2) * PI * 0.5
				_sb(Vector3(1.1, 1.1, 9.0), _xf(p + Vector3(0, 0.75, 0), yaw), BRONZE_D)
				for e: float in [-4.0, 0.0, 4.0]:
					_sb(Vector3(1.5, 1.5, 0.4), _xf(p + Basis(Vector3.UP, yaw) * Vector3(0, 0.75, e), yaw), BRONZE, 0.0, false)
			4:
				# 机关件：大齿轮立着 + 底座
				_col(p.x, p.z, y, y + 0.85, 3.2, 1.6, IRON)
				_sb(Vector3(0.5, 3.6, 3.6), _xf(p + Vector3(0, 2.6, 0)), BRONZE, 0.0, false)
				_sb(Vector3(0.66, 3.6, 3.6), _xf(p + Vector3(0, 2.6, 0), 0.0, Vector3(PI * 0.25, 0, 0)), BRONZE_D, 0.0, false)
		placed += 1


func _lab_clear(q: Vector2, r: float) -> bool:
	for s: Dictionary in map["spawns"]:
		var sp: Vector3 = s["pos"]
		if Vector2(sp.x, sp.z).distance_to(q) < r + 8.0:
			return false
	for e: Dictionary in map["extracts"]:
		var ep: Vector3 = e["pos"]
		if Vector2(ep.x, ep.z).distance_to(q) < r + 18.0:
			return false
	for bo: Dictionary in map["bosses"]:
		var ar: AABB = bo["arena"]
		if Rect2(ar.position.x, ar.position.z, ar.size.x, ar.size.z).grow(r).has_point(q):
			return false
	for pf: Dictionary in map["platforms"]:
		if (pf["rect"] as Rect2).grow(r + 20.0).has_point(q):
			return false
	var bw: Dictionary = map["bowl"]
	if (bw["c"] as Vector2).distance_to(q) < float(bw["outer"]) + r:
		return false
	var cp: Rect2 = (map["compound"] as Dictionary)["rect"]
	if cp.grow(4.0).has_point(q) and not cp.grow(-6.0).has_point(q):
		return false
	for b: Dictionary in map["boxes"]:
		var bp: Vector3 = b["pos"]
		if Vector2(bp.x, bp.z).distance_to(q) < 4.0:
			return false
	return true


## 天工塔：五层，每层一圈朱红柱 + 白墙 + 中式出檐，顶上一枚铜葫芦（实心，不能进）
func _pagoda(p: Vector3) -> void:
	var y := p.y
	_col(p.x, p.z, y - 0.1, y + 1.25, 16.0, 16.0, CONC_D)
	y += 1.25
	for i in 5:
		var w := 11.0 - float(i) * 1.6
		var hh := 5.2 - float(i) * 0.4
		_col(p.x, p.z, y, y + hh, w, w, Color(0.86, 0.85, 0.82) if i % 2 == 0 else Color(0.80, 0.78, 0.74))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_col(p.x + sx * (w * 0.5 + 0.1), p.z + sz * (w * 0.5 + 0.1), y, y + hh + 0.07, 0.8, 0.8, VERM)
		var rp := Vector3(p.x, y + hh, p.z)
		var ww := w
		var mk := func(a: Array) -> void: _roof(a, rp, ww, ww, 0.0, TILE)
		_with_tmp(mk, true)
		y += hh + 1.2
	_col(p.x, p.z, y + 0.2, y + 1.6, 1.4, 1.4, BRONZE)
	_sb(Vector3(1.0, 1.0, 1.0), _xf(Vector3(p.x, y + 2.2, p.z), 0.0, Vector3(0.6, 0.6, 0)), GOLD, 0.6, false)
	_light(Vector3(p.x, p.y + 2.0, p.z), 0, 1)


## 架空管廊：两根铜管（不挡路）架在一排铁支架上（支架挡路），每 12 米一副
func _pipeline(a: Vector2, b: Vector2, h: float) -> void:
	var d := b - a
	var ln := d.length()
	var dir := d / ln
	var side := Vector2(-dir.y, dir.x)
	var n := int(ln / 12.0)
	for i in n + 1:
		var c := a + dir * (float(i) * ln / float(n))
		var y := height(c.x, c.y)
		if absf(y - _base_y) > 0.5 or _in_any_building(c, 1.5):
			continue
		for sg: float in [-1.0, 1.0]:
			var q := c + side * sg * 1.6
			_col(q.x, q.y, y, y + h + 0.05, 0.5, 0.5, IRON)
		_wall(c - side * 2.1, c + side * 2.1, y + h - 0.45, y + h + 0.05, 0.6, IRON, false)
	# 管子按 24 米一段切开（每段归它中点所在的地块，远处的粗地块也带着）
	var ns := maxi(int(ln / 24.0), 1)
	for k in ns:
		var q0 := a + d * (float(k) / float(ns))
		var q1 := a + d * (float(k + 1) / float(ns))
		for sg2: float in [-0.7, 0.7]:
			_wall(q0 + side * sg2, q1 + side * sg2, _base_y + h + 0.05, _base_y + h + 0.95 + 0.1 * sg2, 0.9, BRONZE_D if sg2 < 0.0 else BRONZE, false)


func _watchtower(p: Vector3) -> void:
	var y := height(p.x, p.z)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_col(p.x + sx * 2.2, p.z + sz * 2.2, y, y + 12.05, 0.7, 0.7, IRON)
	_sb(Vector3(6.4, 0.45, 6.4), _xf(Vector3(p.x, y + 12.27, p.z)), WOOD)
	for e: Array in [[Vector2(-3, -3), Vector2(3, -3)], [Vector2(-3, 3), Vector2(3, 3)], [Vector2(-3, -3), Vector2(-3, 3)], [Vector2(3, -3), Vector2(3, 3)]]:
		_wall(Vector2(p.x, p.z) + e[0], Vector2(p.x, p.z) + e[1], y + 12.5, y + 13.55, 0.25, VERM, false)
	_with_tmp(func(a: Array) -> void: _roof(a, Vector3(p.x, y + 15.0, p.z), 5.6, 5.6, 0.0, TILE), false)
	for sx2: float in [-1.0, 1.0]:
		_col(p.x + sx2 * 2.6, p.z, y + 12.5, y + 15.0, 0.3, 0.3, VERM, 0.0, 0.0, false)
	_light(Vector3(p.x, y + 13.0, p.z), 0, 1)


# ---------- 2026-11-25 场景破坏（scripts/destruct.gd 调；总说明见那个文件头） ----------
## 两样东西能坏：
##   · 地形：碗形坑（crater_changes → apply_dug，用的是父类的破坏表 _dug + 分块重排那一套）。只降不升，每格最多比原地形低 DX_MAX_DIG 米；
##     崖壁 / 洞窟岩体（顶面比爆点高出一截的格子）不动——高度表挖不出横洞；出了活动范围的不动
##   · _sb 摆的方块（墙、柱、遗迹、巨石、楼板……）：小的整个打碎，大的按爆点切开（剩下的几块重新登记，还能接着打）；
##     脚下的地被炸低了的、坐在被打掉的方块上面的小件跟着塌。dx_zones 里的（出生 / 撤离 / 箱子 / 钥匙房 / 首领场地 / 洞口 / 门）不坏
## 摆件被打坏过的地块，摆件从地表那张网格里拆出来单独一张（_dx_split）：之后再打坏只重传这一张，地表不用跟着重排。
## 没走 _sb 的几样（洞顶的面片、借 block_world 拼的瓦顶、门）打不坏。
const DX_ROOF := 1 << 20          # _bx_i 里「地块 x」填这个 = 这个方块在屋顶组里（地块 z = 第几块屋顶）
const DX_NOCELL := Vector2i(-99999999, -99999999)    # 只为重排摆件而标脏的地块：填一个不在任何地块里的格子
const DX_MAX_DIG := 5.0
const DX_GRID := 8.0
var dx_on := true
var dx_zones: Array[Rect2] = []   # 不可破坏的范围（xz 矩形；destruct.gd 进图时按点表填）
var dx_stat := {"boxes": 0, "cuts": 0, "cells": 0, "falls": 0, "apply_ms": 0.0, "apply_n": 0, "split_ms": 0.0, "split_n": 0}   # apply / split：被打坏的地块落地、摆件网格重传各自最慢的一次（主线程，毫秒）
var _bx_i := PackedInt32Array()   # 每个方块 5 个：地块 x、地块 z、细网格里第一个顶点、粗网格里第一个顶点（-1 没有）、标志（1 还在 2 记了实心）
var _bx_f := PackedFloat32Array() # 每个方块 20 个：中心 3、三条轴 9、尺寸 3、颜色 3、自发光、底角压暗
var _bx_grid := {}                # Vector2i(8 米格) → PackedInt32Array（方块号）
var _geo_lock := Mutex.new()
var _dx_split := {}               # 地块 → 摆件那张网格的节点（null = 这块现在没排）
var _dx_split_dirty := {}
var _dx_roof_dirty := {}
var _dx_play: Array[Rect2] = []


func _bx_add(kx: int, kz: int, v0: int, s0: int, size: Vector3, xf: Transform3D, c: Color, em: float, shade: float, rec: bool) -> int:
	var id := _bx_i.size() / 5
	_bx_i.append_array([kx, kz, v0, s0, 1 | (2 if rec else 0)])
	var b := xf.basis
	var o := xf.origin
	_bx_f.append_array([o.x, o.y, o.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, size.x, size.y, size.z, c.r, c.g, c.b, em, shade])
	var h := size * 0.5
	var ex := absf(b.x.x) * h.x + absf(b.y.x) * h.y + absf(b.z.x) * h.z
	var ez := absf(b.x.z) * h.x + absf(b.y.z) * h.y + absf(b.z.z) * h.z
	for gz in range(int(floorf((o.z - ez) / DX_GRID)), int(floorf((o.z + ez) / DX_GRID)) + 1):
		for gx in range(int(floorf((o.x - ex) / DX_GRID)), int(floorf((o.x + ex) / DX_GRID)) + 1):
			var k := Vector2i(gx, gz)
			var arr: PackedInt32Array = _bx_grid.get(k, PackedInt32Array())
			arr.append(id)
			_bx_grid[k] = arr
	return id


func _bx_xf(id: int) -> Transform3D:
	var o := id * 20
	return Transform3D(Basis(Vector3(_bx_f[o + 3], _bx_f[o + 4], _bx_f[o + 5]), Vector3(_bx_f[o + 6], _bx_f[o + 7], _bx_f[o + 8]),
			Vector3(_bx_f[o + 9], _bx_f[o + 10], _bx_f[o + 11])), Vector3(_bx_f[o], _bx_f[o + 1], _bx_f[o + 2]))


func _bx_size(id: int) -> Vector3:
	var o := id * 20
	return Vector3(_bx_f[o + 12], _bx_f[o + 13], _bx_f[o + 14])


func _bx_col(id: int) -> Color:
	var o := id * 20
	return Color(_bx_f[o + 15], _bx_f[o + 16], _bx_f[o + 17])


## 登记着多少个方块 / 还在的有几个（自检看）
func dx_box_count() -> Vector2i:
	var n := _bx_i.size() / 5
	var alive := 0
	for i in n:
		if (_bx_i[i * 5 + 4] & 1) != 0:
			alive += 1
	return Vector2i(n, alive)


func dx_dug_count() -> int:
	return _dug.size()


## 没被炸过时这一点的地面高度（坑的深浅按它定：同一处再炸多少遍、几条操作先后怎么排，结果都一样）
func dx_orig(x: float, z: float) -> float:
	return _hv(_idx(int(floorf(x / CELL)), int(floorf(z / CELL))))


## 联机不发整张破坏表（握手包里那份）：新图的破坏按「操作记录」重放（net.gd 的 _dx_log），地形和方块一起补
func dug_table() -> Dictionary:
	return {}


## 某个 2 米格在哪一层、表里第几项；两层都不在 = (-1, 0)（_idx 会夹到边上，这里不夹）
func _dx_idx(ix: int, iz: int) -> Vector2i:
	var lx := ix - _s_x0
	var lz := iz - _s_z0
	if lx >= 0 and lz >= 0 and lx < _s_w and lz < _s_d:
		return Vector2i(0, lz * _s_w + lx)
	var cx := ix - _c_x0
	var cz := iz - _c_z0
	if cx >= 0 and cz >= 0 and cx < _c_w and cz < _c_d:
		return Vector2i(1, cz * _c_w + cx)
	return Vector2i(-1, 0)


func _dx_zones_near(x: float, z: float, r: float) -> Array[Rect2]:
	var q := Rect2(x - r, z - r, r * 2.0, r * 2.0)
	var out: Array[Rect2] = []
	for zr: Rect2 in dx_zones:
		if zr.intersects(q):
			out.append(zr)
	return out


## (x, z) 在不在不可破坏的范围里
func dx_protected(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	for zr: Rect2 in dx_zones:
		if zr.has_point(q):
			return true
	return false


## 炸坑：以 center 为中心、半径 radius 的碗形坑，中心最深 depth 米。只算出要改的格子（into：格子 → 高度上限），调用方攒成一批交给 apply_dug
func crater_changes(center: Vector3, radius: float, depth: float, into: Dictionary) -> int:
	if not dx_on or radius <= 0.1:
		return 0
	if _dx_play.is_empty():
		for ln: String in ["surface", "cavern"]:
			_dx_play.append((((map["layers"] as Dictionary)[ln] as Dictionary)["play"] as Rect2).grow(6.0))
	var zs := _dx_zones_near(center.x, center.z, radius + CELL)
	var n := int(ceilf(radius / CELL))
	var cx := int(floorf(center.x / CELL))
	var cz := int(floorf(center.z / CELL))
	var r2 := radius * radius
	var got := 0
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var ix := cx + dx
			var iz := cz + dz
			var px := (float(ix) + 0.5) * CELL
			var pz := (float(iz) + 0.5) * CELL
			var d2 := (px - center.x) * (px - center.x) + (pz - center.z) * (pz - center.z)
			if d2 > r2:
				continue
			var v := _dx_idx(ix, iz)
			if v.x < 0 or not _dx_play[v.x].has_point(Vector2(px, pz)):
				continue
			var orig := _hv(v)
			var k := Vector2i(ix, iz)
			var cur := orig
			var dv: Variant = _dug.get(k)
			if dv != null:
				cur = minf(cur, float(dv))
			if into.has(k):
				cur = minf(cur, float(into[k]))
			if cur - center.y > radius * 0.6 + 0.5:
				continue          # 崖壁 / 洞窟岩体：顶面比爆点高出一截，不动
			var cap := floorf((center.y - depth * sqrt(1.0 - d2 / r2)) / STEP) * STEP
			cap = maxf(cap, orig - DX_MAX_DIG)
			if cap >= cur - 0.01:
				continue
			var prot := false
			for zr: Rect2 in zs:
				if zr.has_point(Vector2(px, pz)):
					prot = true
					break
			if prot:
				continue
			into[k] = cap
			got += 1
	return got


## 一次爆破（单发；连着几发攒一批的见 destruct.gd 的 trench）：返回 {cells 改了几格, boxes 打碎 / 切开了几个, pieces 打掉的体块 [[中心, 尺寸, 颜色], ...]}
func dx_blast(center: Vector3, radius: float, depth: float) -> Dictionary:
	var pieces: Array = []
	var out := {"cells": 0, "boxes": 0, "pieces": pieces}
	if not dx_on:
		return out
	var changes := {}
	if depth > 0.0:
		out["cells"] = crater_changes(center, radius, depth, changes)
	out["boxes"] = dx_break(center, radius, changes, pieces)
	if not changes.is_empty():
		apply_dug(changes)
		dx_stat["cells"] = int(dx_stat["cells"]) + changes.size()
	return out


## 把 center 周围 radius 米内的方块打碎 / 切开（changes = 这一批要炸低的格子：立在上面的小件跟着塌）。返回动了几个
func dx_break(center: Vector3, radius: float, changes: Dictionary, pieces: Array) -> int:
	if not dx_on:
		return 0
	var rr := radius + 2.0
	var seen := {}
	var cand: Array[int] = []
	for gz in range(int(floorf((center.z - rr) / DX_GRID)), int(floorf((center.z + rr) / DX_GRID)) + 1):
		for gx in range(int(floorf((center.x - rr) / DX_GRID)), int(floorf((center.x + rr) / DX_GRID)) + 1):
			var e: Variant = _bx_grid.get(Vector2i(gx, gz))
			if e == null:
				continue
			for id: int in (e as PackedInt32Array):
				if (_bx_i[id * 5 + 4] & 1) != 0 and not seen.has(id):
					seen[id] = true
					cand.append(id)
	if cand.is_empty():
		return 0
	var zs := _dx_zones_near(center.x, center.z, radius + 6.0)
	var edits := {}        # 这一次动到的网格：Vector3i(0 细 / 1 粗 / 2 屋顶, 地块 x / 屋顶号, 地块 z) → 工作副本
	var gone: Array = []   # 打掉的体块：[xz 矩形, 底, 顶]
	var n := 0
	for id: int in cand:
		var o := id * 20
		var org := Vector3(_bx_f[o], _bx_f[o + 1], _bx_f[o + 2])
		var bx := Vector3(_bx_f[o + 3], _bx_f[o + 4], _bx_f[o + 5])
		var by := Vector3(_bx_f[o + 6], _bx_f[o + 7], _bx_f[o + 8])
		var bz := Vector3(_bx_f[o + 9], _bx_f[o + 10], _bx_f[o + 11])
		var h := Vector3(_bx_f[o + 12], _bx_f[o + 13], _bx_f[o + 14]) * 0.5
		var rel := center - org
		var p := Vector3(rel.dot(bx), rel.dot(by), rel.dot(bz))
		var hit := p.distance_to(p.clamp(-h, h)) <= radius
		var fall := false
		if not hit:
			# 脚下的地被炸低了：立在上面的小件跟着塌
			if changes.is_empty() or maxf(h.x, h.z) > 2.5:
				continue
			var ck := Vector2i(int(floorf(org.x / CELL)), int(floorf(org.z / CELL)))
			if not changes.has(ck):
				continue
			var bot := org.y - (absf(by.y) * h.y + absf(bx.y) * h.x + absf(bz.y) * h.z)
			if bot > _hv(_idx(ck.x, ck.y)) + 0.7:
				continue
			fall = true
		if _dx_box_prot(org, bx, by, bz, h, zs):
			continue
		if fall or maxf(h.x, maxf(h.y, h.z)) <= radius * 1.2:
			_dx_kill(id, edits)
			_dx_gone(gone, pieces, Transform3D(Basis(bx, by, bz), org), -h, h, _bx_col(id))
			if fall:
				dx_stat["falls"] = int(dx_stat["falls"]) + 1
		else:
			_dx_cut(id, p, radius, edits, gone, pieces)
		n += 1
	# 坐在打掉的方块上面的小件跟着塌（最多连带四轮：柱础 → 柱身 → 柱头 → 灯）
	for _pass in 4:
		if gone.is_empty():
			break
		var more := 0
		for id: int in cand:
			if (_bx_i[id * 5 + 4] & 1) == 0:
				continue
			var o2 := id * 20
			var h2 := Vector3(_bx_f[o2 + 12], _bx_f[o2 + 13], _bx_f[o2 + 14]) * 0.5
			if maxf(h2.x, maxf(h2.y, h2.z)) > 3.0:
				continue
			var org2 := Vector3(_bx_f[o2], _bx_f[o2 + 1], _bx_f[o2 + 2])
			var bx2 := Vector3(_bx_f[o2 + 3], _bx_f[o2 + 4], _bx_f[o2 + 5])
			var by2 := Vector3(_bx_f[o2 + 6], _bx_f[o2 + 7], _bx_f[o2 + 8])
			var bz2 := Vector3(_bx_f[o2 + 9], _bx_f[o2 + 10], _bx_f[o2 + 11])
			var bot2 := org2.y - (absf(by2.y) * h2.y + absf(bx2.y) * h2.x + absf(bz2.y) * h2.z)
			var q := Vector2(org2.x, org2.z)
			var on := false
			for g: Array in gone:
				if bot2 >= float(g[1]) - 0.05 and bot2 <= float(g[2]) + 0.35 and (g[0] as Rect2).has_point(q):
					on = true
					break
			if not on or _dx_box_prot(org2, bx2, by2, bz2, h2, zs):
				continue
			_dx_kill(id, edits)
			_dx_gone(gone, pieces, Transform3D(Basis(bx2, by2, bz2), org2), -h2, h2, _bx_col(id))
			dx_stat["falls"] = int(dx_stat["falls"]) + 1
			more += 1
			n += 1
		if more == 0:
			break
	_dx_publish(edits)
	return n


## 方块的水平占地碰没碰到不可破坏的范围
func _dx_box_prot(org: Vector3, bx: Vector3, by: Vector3, bz: Vector3, h: Vector3, zs: Array[Rect2]) -> bool:
	if zs.is_empty():
		return false
	var ex := absf(bx.x) * h.x + absf(by.x) * h.y + absf(bz.x) * h.z
	var ez := absf(bx.z) * h.x + absf(by.z) * h.y + absf(bz.z) * h.z
	var r := Rect2(org.x - ex, org.z - ez, ex * 2.0, ez * 2.0)
	for zr: Rect2 in zs:
		if zr.intersects(r):
			return true
	return false


## 记一块「打掉的体块」（方块本地系里 lo ~ hi 那一段）：连带坍塌用（gone）+ 给特效撒碎块用（pieces）
func _dx_gone(gone: Array, pieces: Array, xf: Transform3D, lo: Vector3, hi: Vector3, col: Color) -> void:
	var c := xf * ((lo + hi) * 0.5)
	var h := (hi - lo) * 0.5
	var b := xf.basis
	var ex := absf(b.x.x) * h.x + absf(b.y.x) * h.y + absf(b.z.x) * h.z
	var ey := absf(b.x.y) * h.x + absf(b.y.y) * h.y + absf(b.z.y) * h.z
	var ez := absf(b.x.z) * h.x + absf(b.y.z) * h.y + absf(b.z.z) * h.z
	gone.append([Rect2(c.x - ex - 0.1, c.z - ez - 0.1, ex * 2.0 + 0.2, ez * 2.0 + 0.2), c.y - ey, c.y + ey])
	pieces.append([c, hi - lo, col])


## 这一次要改的那张网格的工作副本（[顶点, 法线, 顶点色, 索引]；Packed 数组写时复制，原来那份工作线程照旧能读）
func _dx_edit(edits: Dictionary, tab: int, kx: int, kz: int) -> Array:
	var ek := Vector3i(tab, kx, kz)
	var g: Variant = edits.get(ek)
	if g == null:
		var src: Array
		if tab == 2:
			src = (_roofs[kx] as Dictionary)["geo"]
		else:
			_geo_lock.lock()
			src = _geo(_sgeo if tab == 0 else _sshell, Vector2i(kx, kz))
			_geo_lock.unlock()
		g = [src[0], src[1], src[2], src[3]]
		edits[ek] = g
	return g


## 把一个方块的 20 个顶点收成一个点（退化三角形，不画）
func _dx_flat(g: Array, v0: int, at: Vector3) -> void:
	var v: PackedVector3Array = g[0]
	g[0] = null          # 先松手：副本只有 v 一个持有者时就地改，不然每改一个方块整张数组都要抄一遍
	for j in 20:
		v[v0 + j] = at
	g[0] = v


## 打掉一个方块：网格里抹掉、实心盒子撤掉
func _dx_kill(id: int, edits: Dictionary) -> void:
	var i5 := id * 5
	var fl := _bx_i[i5 + 4]
	if (fl & 1) == 0:
		return
	_bx_i[i5 + 4] = fl & 6
	var kx := _bx_i[i5]
	var kz := _bx_i[i5 + 1]
	var o := id * 20
	var org := Vector3(_bx_f[o], _bx_f[o + 1], _bx_f[o + 2])
	if kx == DX_ROOF:
		_dx_flat(_dx_edit(edits, 2, kz, 0), _bx_i[i5 + 2], org)
	else:
		_dx_flat(_dx_edit(edits, 0, kx, kz), _bx_i[i5 + 2], org)
		if _bx_i[i5 + 3] >= 0:
			_dx_flat(_dx_edit(edits, 1, kx, kz), _bx_i[i5 + 3], org)
	if (fl & 2) != 0:
		_dx_sol(_bx_size(id), _bx_xf(id), false)
	dx_stat["boxes"] = int(dx_stat["boxes"]) + 1


## 大方块按爆点切开：切口是方块本地系里以 p 为心、边长约两倍半径的一块；切口两侧 / 下面剩下的各成一个新方块，
## 切口上面那段两侧有东西架着才留（墙上打个洞，门楣还在）；柱子拦腰打断，上半截跟着没
func _dx_cut(id: int, p: Vector3, radius: float, edits: Dictionary, gone: Array, pieces: Array) -> void:
	var xf := _bx_xf(id)
	var h := _bx_size(id) * 0.5
	var col := _bx_col(id)
	var o := id * 20
	var em := _bx_f[o + 18]
	var shade := _bx_f[o + 19]
	var kx := _bx_i[id * 5]
	var kz := _bx_i[id * 5 + 1]
	var solid := (_bx_i[id * 5 + 4] & 2) != 0
	var e := radius * 0.9
	var lo := Vector3(maxf(-h.x, p.x - e), maxf(-h.y, p.y - e), maxf(-h.z, p.z - e))
	var hi := Vector3(minf(h.x, p.x + e), minf(h.y, p.y + e), minf(h.z, p.z + e))
	for a in 3:
		# 剩得太薄的（不到半米）一起带走
		if lo[a] + h[a] < 0.5:
			lo[a] = -h[a]
		if h[a] - hi[a] < 0.5:
			hi[a] = h[a]
	_dx_kill(id, edits)
	var parts: Array = []
	var side := false
	if lo.x > -h.x:
		parts.append([Vector3(-h.x, -h.y, -h.z), Vector3(lo.x, h.y, h.z)])
		side = true
	if hi.x < h.x:
		parts.append([Vector3(hi.x, -h.y, -h.z), Vector3(h.x, h.y, h.z)])
		side = true
	if lo.z > -h.z:
		parts.append([Vector3(lo.x, -h.y, -h.z), Vector3(hi.x, h.y, lo.z)])
		side = true
	if hi.z < h.z:
		parts.append([Vector3(lo.x, -h.y, hi.z), Vector3(hi.x, h.y, h.z)])
		side = true
	if lo.y > -h.y:
		parts.append([Vector3(lo.x, -h.y, lo.z), Vector3(hi.x, lo.y, hi.z)])
	var top := h.y
	if hi.y < h.y and side:
		parts.append([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, h.y, hi.z)])
		top = hi.y
	for pr: Array in parts:
		var a0: Vector3 = pr[0]
		var a1: Vector3 = pr[1]
		_dx_spawn(kx, kz, a1 - a0, Transform3D(xf.basis, xf * ((a0 + a1) * 0.5)), col, em, shade, solid, edits)
	_dx_gone(gone, pieces, xf, lo, Vector3(hi.x, top, hi.z), col)
	dx_stat["cuts"] = int(dx_stat["cuts"]) + 1


## 把一个新方块接到工作副本后面，返回它第一个顶点的下标
func _dx_append(g: Array, size: Vector3, xf: Transform3D, col: Color, em: float, shade: float) -> int:
	var t := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	_box(t, size, xf, col, em, shade)
	var v: PackedVector3Array = g[0]
	var nr: PackedVector3Array = g[1]
	var cl: PackedColorArray = g[2]
	var ix: PackedInt32Array = g[3]
	g[0] = null
	g[1] = null
	g[2] = null
	g[3] = null
	var base := v.size()
	v.append_array(t[0])
	nr.append_array(t[1])
	cl.append_array(t[2])
	for q: int in (t[3] as PackedInt32Array):
		ix.append(q + base)
	g[0] = v
	g[1] = nr
	g[2] = cl
	g[3] = ix
	return base


## 切剩下的一块：进网格、登记（之后还能接着打）、够大够正的记实心盒子
func _dx_spawn(kx: int, kz: int, size: Vector3, xf: Transform3D, col: Color, em: float, shade: float, solid: bool, edits: Dictionary) -> void:
	var v0 := 0
	var s0 := -1
	if kx == DX_ROOF:
		v0 = _dx_append(_dx_edit(edits, 2, kz, 0), size, xf, col, em, shade)
	else:
		v0 = _dx_append(_dx_edit(edits, 0, kx, kz), size, xf, col, em, shade)
		if maxf(size.x, maxf(size.y, size.z)) >= 2.5:
			s0 = _dx_append(_dx_edit(edits, 1, kx, kz), size, xf, col, em, shade)
	_bx_add(kx, kz, v0, s0, size, xf, col, em, shade, solid and _dx_sol(size, xf, true))


## 全图静态那一份实心盒子里添 / 撤一条（规矩和 _rec_box + _sol_pack 一样）。返回这个方块算不算实心
func _dx_sol(size: Vector3, xf: Transform3D, add: bool) -> bool:
	var rec := PackedFloat32Array()
	_rec_box(rec, size, xf)
	if rec.is_empty():
		return false
	var ax := Vector2(rec[2], rec[3])
	var bz := Vector2(rec[4], rec[5])
	var la := ax.length_squared()
	var lb := bz.length_squared()
	if la <= 1.0e-4 or lb <= 1.0e-4:
		return false
	var cx := rec[0]
	var cz := rec[1]
	var ex := absf(ax.x) + absf(bz.x)
	var ez := absf(ax.y) + absf(bz.y)
	var u := ax / la
	var w := bz / lb
	for gz in range(int(floorf((cz - ez) / SOL_CELL)), int(floorf((cz + ez) / SOL_CELL)) + 1):
		for gx in range(int(floorf((cx - ex) / SOL_CELL)), int(floorf((cx + ex) / SOL_CELL)) + 1):
			var k := Vector2i(gx, gz)
			if add:
				if not _scells.has(k):
					_scells[k] = {}
				var cell: Dictionary = _scells[k]
				var arr: PackedFloat32Array = cell.get(STATIC_KEY, PackedFloat32Array())
				cell[STATIC_KEY] = null
				arr.append_array([cx, cz, u.x, u.y, w.x, w.y, rec[6], rec[7]])
				cell[STATIC_KEY] = arr
				if _sowner.has(STATIC_KEY) and not (_sowner[STATIC_KEY] as Array).has(k):
					(_sowner[STATIC_KEY] as Array).append(k)
			else:
				var ce: Variant = _scells.get(k)
				if ce == null or not (ce as Dictionary).has(STATIC_KEY):
					continue
				var a2: PackedFloat32Array = (ce as Dictionary)[STATIC_KEY]
				(ce as Dictionary)[STATIC_KEY] = null
				var i := 0
				var m := a2.size()
				while i < m:
					if absf(a2[i] - cx) < 0.01 and absf(a2[i + 1] - cz) < 0.01 and absf(a2[i + 6] - rec[6]) < 0.01 and absf(a2[i + 7] - rec[7]) < 0.01 \
							and absf(a2[i + 2] - u.x) < 0.01 and absf(a2[i + 3] - u.y) < 0.01:
						for q in 8:
							a2[i + q] = a2[m - 8 + q]
						a2.resize(m - 8)
						break
					i += 8
				(ce as Dictionary)[STATIC_KEY] = a2
	return true


## 工作副本落地：换表（上锁，工作线程那边 _props 在读）、标记要重传的网格
func _dx_publish(edits: Dictionary) -> void:
	for ek: Vector3i in edits:
		var g: Array = edits[ek]
		if ek.x == 2:
			(_roofs[ek.y] as Dictionary)["geo"] = g
			_dx_roof_dirty[ek.y] = true
			continue
		var key := Vector2i(ek.y, ek.z)
		_geo_lock.lock()
		(_sgeo if ek.x == 0 else _sshell)[key] = g
		var first := not _dx_split.has(key)
		if first:
			_dx_split[key] = null
		_geo_lock.unlock()
		if first and _chunks.has(key) and not _dirty.has(key):
			_dirty[key] = [DX_NOCELL]      # 地表那张网格重排一次（这回不带摆件了）
		_dx_split_dirty[key] = true


static func _dx_mesh(g: Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g[0]
	arrays[Mesh.ARRAY_NORMAL] = g[1]
	arrays[Mesh.ARRAY_COLOR] = g[2]
	arrays[Mesh.ARRAY_INDEX] = g[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 拆出来的摆件网格跟上：这块现在是细的用细的那份、粗的用大件那份；这块撤了就跟着撤
func _dx_refresh_split(key: Vector2i) -> void:
	var c: Variant = _chunks.get(key)
	var node: MeshInstance3D = _dx_split.get(key)
	var g: Variant = null
	var lod := 0
	if c != null:
		lod = int((c as Dictionary)["lod"])
		g = (_sgeo if lod == 0 else _sshell).get(key)
	if g == null or ((g as Array)[0] as PackedVector3Array).is_empty():
		if node != null:
			node.queue_free()
			_geo_lock.lock()
			_dx_split[key] = null
			_geo_lock.unlock()
		return
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Props_%d_%d" % [key.x, key.y]
		node.material_override = mat
		add_child(node)
		_geo_lock.lock()
		_dx_split[key] = node
		_geo_lock.unlock()
	node.mesh = _dx_mesh(g)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _dx_tick() -> void:
	if not _dx_roof_dirty.is_empty():
		var ri: int = _dx_roof_dirty.keys()[0]
		_dx_roof_dirty.erase(ri)
		var r: Dictionary = _roofs[ri]
		var rn: MeshInstance3D = r["node"]
		if rn != null:
			rn.mesh = _dx_mesh(r["geo"])
	if not _dx_split_dirty.is_empty():
		var key: Vector2i = _dx_split_dirty.keys()[0]
		_dx_split_dirty.erase(key)
		var t0 := Time.get_ticks_usec()
		_dx_refresh_split(key)
		dx_stat["split_ms"] = maxf(float(dx_stat["split_ms"]), float(Time.get_ticks_usec() - t0) / 1000.0)
		dx_stat["split_n"] = int(dx_stat["split_n"]) + 1


func _apply(key: Vector2i, lod: int, r: Dictionary) -> void:
	var dx := not _dug.is_empty() or not _dx_split.is_empty()
	var t0 := Time.get_ticks_usec()
	super(key, lod, r)
	if dx and lod == 0:
		dx_stat["apply_ms"] = maxf(float(dx_stat["apply_ms"]), float(Time.get_ticks_usec() - t0) / 1000.0)
		dx_stat["apply_n"] = int(dx_stat["apply_n"]) + 1
	if _dx_split.has(key):
		_dx_split_dirty[key] = true


func _plan(k: Vector2i) -> void:
	super(k)
	for key: Vector2i in _dx_split:
		if _dx_split[key] != null and not _chunks.has(key):
			_dx_split_dirty[key] = true


## p 落在哪个还在的方块里（-1 = 没有）；r > 0 = p 周围 r 米内碰到的也算
func dx_box_at(p: Vector3, r := 0.0) -> int:
	var e: Variant = _bx_grid.get(Vector2i(int(floorf(p.x / DX_GRID)), int(floorf(p.z / DX_GRID))))
	if e == null:
		return -1
	for id: int in (e as PackedInt32Array):
		if (_bx_i[id * 5 + 4] & 1) == 0:
			continue
		var o := id * 20
		var rel := p - Vector3(_bx_f[o], _bx_f[o + 1], _bx_f[o + 2])
		var h := Vector3(_bx_f[o + 12], _bx_f[o + 13], _bx_f[o + 14]) * 0.5
		var q := Vector3(rel.dot(Vector3(_bx_f[o + 3], _bx_f[o + 4], _bx_f[o + 5])), rel.dot(Vector3(_bx_f[o + 6], _bx_f[o + 7], _bx_f[o + 8])),
				rel.dot(Vector3(_bx_f[o + 9], _bx_f[o + 10], _bx_f[o + 11])))
		if q.distance_to(q.clamp(-h, h)) <= r:
			return id
	return -1


## 这个方块打不打得坏（不在不可破坏的范围里）
func dx_box_breakable(id: int) -> bool:
	if id < 0 or (_bx_i[id * 5 + 4] & 1) == 0:
		return false
	var o := id * 20
	var org := Vector3(_bx_f[o], _bx_f[o + 1], _bx_f[o + 2])
	return not _dx_box_prot(org, Vector3(_bx_f[o + 3], _bx_f[o + 4], _bx_f[o + 5]), Vector3(_bx_f[o + 6], _bx_f[o + 7], _bx_f[o + 8]),
			Vector3(_bx_f[o + 9], _bx_f[o + 10], _bx_f[o + 11]), Vector3(_bx_f[o + 12], _bx_f[o + 13], _bx_f[o + 14]) * 0.5,
			_dx_zones_near(org.x, org.z, 40.0))


## 碎块 / 扬尘用的地面颜色（这个区域的地表、土、石）
func dx_ground_colors(x: float, z: float) -> Array:
	var pal: Array = _pal[_region(x, z, 0.5)]
	return [pal[0], pal[2], pal[3], pal[2]]
