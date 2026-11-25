extends Node3D
## 灵田农场（2026-11-21 场景美术专项）：主城东侧那道牌坊门通过来的一座方块浮岛。照用户给的参考图（_tasks/scene_art/ref2_farm.jpg）的氛围和空间关系搭：
##   北面 三米高的石台上一座殿（中间两层、两侧耳房，门里透着暖光，两面红幡），台前石阶，石阶两边各一池莲花，
##        台子两角各一座长着苔的山石、各挂一道瀑布落进莲池；殿后樱花、绿树、竹丛，东北角一株紫藤
##   中轴 南门（牌坊）→ 一条两侧立着灯柱的石路 → 中间一块铺着莲花纹的圆形广场 → 石阶
##   西面 灵宠区（预留）：按用户要求只有一整片平整的草坪（剪草的明暗条纹），不放宠物、房子、栏杆和任何装饰
##   东面 种植区（2026-11-23 起四畦菜地换成六块灵田、每块 4×4 格，能种灵草，见 farm_plots.gd / farm_data.gd）：一圈木篱笆（挂着小灯）、北边「种植区」牌坊；一道南北向的主水渠 + 几道横渠把地分成五块：
##        麦田、白菜、胡萝卜、西瓜（架着瓜棚）、番茄（插着竹竿）；东北角山石上的泉水经木水槽冲着一架会转的水车；
##        一座敞棚（农具、箱子、麻袋），南边一排装满瓜果的木箱和一个小摊；东沿一排竹子；两个戴斗笠的农人
##   四周 岛沿是灰石崖壁，西南、东南各一道瀑布落进云海；岛外是方块云团和几座挂瀑布的小浮岛；天空和主城共用一张全景天空盒
## 怎么接：hub_hall.gd 建它、管开关（主城和农场同一时刻只开一个，见 hub_hall.gd 的 set_area）。整座岛建在 ORIGIN（离主城很远的地方），
##   顶点按岛的本地坐标、外面套一个 _root 挪过去。地面高度表 / 实心格和主城同一套做法（2 米一格），主角站地、走台阶、
##   撞楼都由 hub_hall.gd 的 _physics_process 照常处理（在农场时它问的 ground / solid_at 是这里的）。
## 南门同时是回主城的门：hub_portal.gd 在门洞里画主城那边的实时画面，走进去就回到主城那道门前。
## 不做宠物 / 种植的玩法（用户说本轮先完成场景和入口）。
## 故意不写 class_name：用 preload 引用。

const BlockWorld := preload("res://scripts/block_world.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const WORLD_SHADER := preload("res://shaders/block_world.gdshader")
const WATER_SHADER := preload("res://shaders/flow_water.gdshader")
const NOISE := preload("res://fx/cine/cine_noise.png")
const FarmPlots := preload("res://scripts/farm_plots.gd")

const ORIGIN := Vector3(0.0, 0.0, -760.0)    # 整座岛的位置：2 的整数倍（和主城同一套 2 米格子对齐）；要在 Player.BOUND（1150）以内，主角每帧被夹在这个范围里
const CELL := 2.0
const N := 84                  # 一边多少格（168 米见方）
const HN := 42
const VOID := -999.0
const T_GRASS := 1
const T_PAVE := 2
const T_PLAZA := 3
const T_WATER := 4
const T_STONE := 5
const T_BED := 6               # 菜地的土垄
const T_WOOD := 7              # 渠上的木板桥
const T_LAWN := 8              # 灵宠区的草坪
const T_ROCK := 9              # 山石
const T_DIRT := 10             # 敞棚 / 摊位前的土地

## 牌坊门（主城那道和这边的南门同一个样子）：门洞宽 / 高
const GATE_W := 8.0
const GATE_H := 7.0
const GATE_Z := 40.0           # 南门在岛上的 z（本地）
const TERRACE_H := 3.0
const SPAWN_L := Vector3(0.0, 0.1, 36.0)
## 两块分区（本地坐标）：灵宠区（只有草坪）、种植区
const PET_X0 := -58.0
const PET_X1 := -8.0
const PET_Z0 := -22.0
const PET_Z1 := 38.0
const HALL_Z := -46.0

## 两个农人：[x, z, 朝向, 拿什么]（麦田边扶锄头的、胡萝卜地边挎篮子的）
const FARMER_A := [22.0, -9.0, PI * 0.85, 0]
const FARMER_B := [50.5, 9.4, PI * 0.75, 1]
const WOOD := Color(0.55, 0.35, 0.21)
const WOOD_D := Color(0.42, 0.26, 0.16)
const ROOF := Color(0.33, 0.31, 0.43)        # 黛紫的瓦（参考图的屋顶偏紫）
const GOLD := Color(1.0, 0.80, 0.36)
const LAMP := Color(1.0, 0.84, 0.46)
const BANNER := Color(0.82, 0.19, 0.16)
const STONE := Color(0.76, 0.75, 0.76)

var bw: BlockWorld              # 借 hub_hall.gd 的那个（只用它的构件函数）
var font: Font
var mobile := false
var root: Node3D                # 看得见的东西都在这下面（开关时整体显隐；透视门复制的也是它下面的网格）

var _h := PackedFloat32Array()
var _t := PackedByteArray()
var _solid := PackedFloat32Array()
var _a: Array = []              # 建筑 / 点缀 / 作物（block_world 着色器）
var _g: Array = []              # 地面
var _w: Array = []              # 水面和瀑布（flow_water 着色器）
var _wheel: Node3D
var _time := 0.0
var plots: FarmPlots            # 灵田（2026-11-23 种植系统）


func _ready() -> void:
	_h.resize(N * N)
	_t.resize(N * N)
	_solid.resize(N * N)
	_h.fill(VOID)
	_a = _arr()
	_g = _arr()
	_w = _arr()
	root = Node3D.new()
	root.name = "FarmRoot"
	root.position = ORIGIN
	add_child(root)
	_layout()
	_mesh_ground()
	_build_hall()
	_build_axis()
	_build_fields()
	_build_scenery()
	_build_people()
	_commit(_g, WORLD_SHADER, true)
	_commit(_a, WORLD_SHADER, true)
	_commit(_w, WATER_SHADER, false)
	_build_wheel()
	_build_signs()
	plots = FarmPlots.new()
	plots.name = "Plots"
	plots.font = font
	plots.mobile = mobile
	root.add_child(plots)
	root.visible = false


static func _arr() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]


## 主角进农场站哪（世界坐标）：南门里头，面朝北
func spawn_point() -> Vector3:
	return ORIGIN + SPAWN_L


## 南门的坐标系（世界）：原点 = 门洞底边中点；yaw 0（-Z = 往北、往农场里走）
static func gate_in() -> Transform3D:
	return Transform3D(Basis.IDENTITY, ORIGIN + Vector3(0.0, 0.0, GATE_Z))


func tick(dt: float) -> void:
	_time += dt
	if plots != null:
		plots.tick(dt)
	if _wheel != null:
		_wheel.rotation.z = -_time * 0.9


# ---------- 牌坊门（主城那道也用这个） ----------

## 在网格数组 a 里搭一座牌坊门：xf = 门的坐标系（原点 = 门洞底边中点，本地 X 横跨门洞，-Z / +Z 是门的两面），yaw = xf 绕竖轴的角度。
## 两根木柱立在石墩上、两道横梁夹一块匾（匾上的字另外挂 Label3D）、一顶黛紫瓦的屋檐和金色的脊饰；两根柱子外侧各垂一面红幡。
static func build_gate(b: BlockWorld, a: Array, xf: Transform3D, yaw: float) -> void:
	var hw := GATE_W * 0.5
	var col_h := GATE_H + 2.4
	for sx: float in [-1.0, 1.0]:
		var px := sx * (hw + 0.5)
		BlockWorld._box(a, Vector3(1.8, 1.0, 1.8), xf * Transform3D(Basis.IDENTITY, Vector3(px, 0.5, 0.0)), STONE * 0.92)
		BlockWorld._box(a, Vector3(1.0, col_h, 1.0), xf * Transform3D(Basis.IDENTITY, Vector3(px, col_h * 0.5, 0.0)), WOOD)
		BlockWorld._box(a, Vector3(1.25, 0.35, 1.25), xf * Transform3D(Basis.IDENTITY, Vector3(px, 1.15, 0.0)), GOLD * 0.9, 0.0, 0.95)
		# 红幡：挂在横梁外伸出去的那一截下面
		var fx := sx * (hw + 1.75)
		BlockWorld._box(a, Vector3(1.1, 3.8, 0.16), xf * Transform3D(Basis.IDENTITY, Vector3(fx, GATE_H - 1.9 + 0.2, 0.0)), BANNER, 0.0, 0.95)
		BlockWorld._box(a, Vector3(0.62, 0.62, 0.22), xf * Transform3D(Basis.IDENTITY, Vector3(fx, GATE_H - 0.75, 0.0)), GOLD, 0.15, 1.0)
		BlockWorld._box(a, Vector3(1.1, 0.4, 0.2), xf * Transform3D(Basis.IDENTITY, Vector3(fx, GATE_H - 3.9, 0.0)), BANNER * 0.7, 0.0, 0.95)
		BlockWorld._box(a, Vector3(0.3, 0.5, 0.3), xf * Transform3D(Basis.IDENTITY, Vector3(fx, GATE_H - 4.35, 0.0)), GOLD * 0.85)
	BlockWorld._box(a, Vector3(GATE_W + 4.6, 0.8, 1.2), xf * Transform3D(Basis.IDENTITY, Vector3(0.0, GATE_H + 0.4, 0.0)), WOOD_D)
	BlockWorld._box(a, Vector3(3.6, 1.3, 0.5), xf * Transform3D(Basis.IDENTITY, Vector3(0.0, GATE_H + 1.45, 0.0)), WOOD_D)
	BlockWorld._box(a, Vector3(3.1, 0.95, 0.62), xf * Transform3D(Basis.IDENTITY, Vector3(0.0, GATE_H + 1.45, 0.0)), Color(0.96, 0.88, 0.62), 0.0, 1.0)
	BlockWorld._box(a, Vector3(GATE_W + 5.6, 0.5, 1.1), xf * Transform3D(Basis.IDENTITY, Vector3(0.0, GATE_H + 2.35, 0.0)), WOOD)
	b._roof(a, xf * Vector3(0.0, GATE_H + 2.55, 0.0), GATE_W + 4.4, 1.4, yaw, ROOF)
	for sx: float in [-1.0, 1.0]:
		BlockWorld._box(a, Vector3(0.5, 0.9, 0.5), xf * Transform3D(Basis.IDENTITY, Vector3(sx * (GATE_W + 4.4) * 0.25, GATE_H + 4.85, 0.0)), GOLD, 0.2, 1.0)
	BlockWorld._box(a, Vector3(0.8, 0.8, 0.8), xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, GATE_H + 4.85, 0.0)), GOLD, 0.25, 1.0)


# ---------- 布局 ----------

func _ci(x: float) -> int:
	return int(floorf(x / CELL)) + HN


func _in(i: int, j: int) -> bool:
	return i >= 0 and i < N and j >= 0 and j < N


func _land(i: int, j: int) -> bool:
	return _in(i, j) and _h[j * N + i] > VOID + 1.0


func _put(i: int, j: int, type: int, h: float) -> void:
	if _in(i, j):
		_h[j * N + i] = h
		_t[j * N + i] = type


func _rect(x0: float, z0: float, x1: float, z1: float, type: int, h: float, only_land := true) -> void:
	for j in range(_ci(z0), _ci(z1 - 0.01) + 1):
		for i in range(_ci(x0), _ci(x1 - 0.01) + 1):
			if _in(i, j) and (not only_land or _h[j * N + i] > VOID + 1.0):
				_put(i, j, type, h)


func _disc(cx: float, cz: float, r: float, type: int, h: float) -> void:
	for j in range(_ci(cz - r), _ci(cz + r) + 1):
		for i in range(_ci(cx - r), _ci(cx + r) + 1):
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			if Vector2(x - cx, z - cz).length() <= r and _land(i, j):
				_put(i, j, type, h)


func _block(x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	for j in range(_ci(z0), _ci(z1 - 0.01) + 1):
		for i in range(_ci(x0), _ci(x1 - 0.01) + 1):
			if _in(i, j):
				_solid[j * N + i] = maxf(_solid[j * N + i], top)


## 比两米一格细的实心盒子（2026-11-23，和 hub_hall.gd 的 _block_fine 一样）：门柱按真实大小挡人，不再一根柱子占四米见方。岛的本地坐标
var _fine := PackedFloat32Array()       # 每五个数一个盒子：x0, z0, x1, z1, 顶

func _block_fine(x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	_fine.append_array([x0, z0, x1, z1, top])


static func _hash(i: int, j: int) -> float:
	var n := (i * 374761393 + j * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## 山石在 x 这一列上靠南的那一面（从台沿 z = -30 往北找第一格山石，返回那一格的南边界）
func _rock_face(x: float) -> float:
	var z := -31.0
	while z > -46.0:
		if _type_at(x, z) == T_ROCK:
			return floorf(z / CELL) * CELL + CELL
		z -= CELL
	return -32.0


func _type_at(x: float, z: float) -> int:
	var i := _ci(x)
	var j := _ci(z)
	return int(_t[j * N + i]) if _land(i, j) else 0


func _h_at(x: float, z: float) -> float:
	var i := _ci(x)
	var j := _ci(z)
	return _h[j * N + i] if _land(i, j) else VOID


## 一块山石：一团高低错落的石格（中间高、边上低），顶上长苔
func _rock(cx: float, cz: float, rx: float, rz: float, top: float, seed_i: int) -> void:
	for j in range(_ci(cz - rz), _ci(cz + rz) + 1):
		for i in range(_ci(cx - rx), _ci(cx + rx) + 1):
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			var d := Vector2((x - cx) / rx, (z - cz) / rz).length()
			if d > 1.0 + (_hash(i + seed_i, j) - 0.5) * 0.3 or not _land(i, j):
				continue
			var hh := TERRACE_H * 0.0 + top * (1.0 - d * d * 0.75) * (0.8 + 0.4 * _hash(i * 3 + seed_i, j * 7))
			_put(i, j, T_ROCK, maxf(roundf(hh * 2.0) * 0.5, _h[j * N + i] + 1.0))


func _layout() -> void:
	# 岛：一块圆角的方（超椭圆），边沿按格子参差一点
	for j in N:
		for i in N:
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			var k := pow(absf(x) / 68.0, 3.0) + pow(absf(z + 4.0) / 54.0, 3.0)
			if k < 0.95 + (_hash(i, j) - 0.5) * 0.07:
				_put(i, j, T_GRASS, 0.0)
	# 北面的石台、石阶（半米一级），石阶两边的莲池
	_rect(-26.0, -58.0, 26.0, -30.0, T_STONE, TERRACE_H)
	for k in 5:
		_rect(-5.0, -30.0 + 2.0 * float(k), 5.0, -28.0 + 2.0 * float(k), T_STONE, TERRACE_H - 0.5 * float(k + 1))
	_rect(-24.0, -30.0, -7.0, -22.0, T_WATER, -0.6)
	_rect(7.0, -30.0, 24.0, -22.0, T_WATER, -0.6)
	# 台子两角的山石（瀑布从它们南面落进莲池）；东北角一块（泉水接水车）
	_rock(-28.5, -38.0, 7.0, 8.0, 18.0, 11)
	_rock(28.5, -38.0, 7.0, 8.0, 17.0, 23)
	_rock(56.0, -27.0, 6.5, 6.0, 7.5, 37)
	# 中轴：石路（中间 9 米铺大石板、两边各一道深色的边石带，灯柱立在边石带上），一直通到岛南沿外面一截
	_rect(-6.0, -20.0, 6.0, 52.0, T_PAVE, 0.0)
	_rect(-4.0, 44.0, 4.0, 56.0, T_PAVE, 0.0, false)
	_disc(0.0, -10.0, 8.5, T_PLAZA, 0.0)
	# 灵宠区：一整片草坪
	_rect(PET_X0, PET_Z0, PET_X1, PET_Z1, T_LAWN, 0.0)
	# 种植区：水渠、地块、木桥
	for c: Array in [[10.0, -24.0, 12.0, 32.0], [12.0, -24.0, 48.0, -22.0], [12.0, -6.0, 60.0, -4.0], [12.0, 10.0, 60.0, 12.0],
			[36.0, -4.0, 38.0, 28.0], [58.0, 12.0, 60.0, 50.0]]:
		_rect(float(c[0]), float(c[1]), float(c[2]), float(c[3]), T_WATER, -0.6)
	# 2026-11-23 菜畦按灵田收齐（一块灵田 10 米见方，见 farm_plots.gd 的 FIELDS）：西边两畦各并排两块，东边两畦各一块（原来 40~56 宽 16 米）；南边两畦原来深 12 米，收成 10 米
	for p: Array in [[14.0, -20.0, 34.0, -8.0], [14.0, -2.0, 34.0, 8.0], [42.0, -2.0, 52.0, 8.0], [14.0, 14.0, 34.0, 24.0], [42.0, 14.0, 52.0, 24.0]]:
		_rect(float(p[0]), float(p[1]), float(p[2]), float(p[3]), T_BED, 0.3)
	_rect(46.0, -18.0, 60.0, -8.0, T_DIRT, 0.0)
	_rect(38.0, 28.0, 58.0, 36.0, T_DIRT, 0.0)
	for br: Array in [[10.0, 0.0, 12.0, 4.0], [10.0, -16.0, 12.0, -12.0], [22.0, -24.0, 26.0, -22.0], [22.0, -6.0, 26.0, -4.0],
			[22.0, 10.0, 26.0, 12.0], [46.0, 10.0, 50.0, 12.0], [36.0, 18.0, 38.0, 22.0], [46.0, -6.0, 50.0, -4.0]]:
		_rect(float(br[0]), float(br[1]), float(br[2]), float(br[3]), T_WOOD, 0.15)
	# 西南角岛沿的一眼泉（灵宠区外面）：落成西南那道瀑布
	_rect(-50.0, 42.0, -42.0, 50.0, T_WATER, -0.6)
	# 实心格：殿、山石（地面格本身高，走不上去）、篱笆在 _build_fields 里登记
	_block(-20.6, -52.6, 20.6, -39.6, TERRACE_H + 18.0)


# ---------- 地面网格 ----------

func _quad(a: Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, em := 0.0, top := true) -> void:
	var v: PackedVector3Array = a[0]
	var nr: PackedVector3Array = a[1]
	var cl: PackedColorArray = a[2]
	var ix: PackedInt32Array = a[3]
	var b := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	var cc := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), em)
	for _k in 4:
		nr.append(n)
		cl.append(cc)
	if top:
		ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		ix.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	a[0] = v
	a[1] = nr
	a[2] = cl
	a[3] = ix


func _top_col(type: int, i: int, j: int, x: float, z: float) -> Color:
	var hs := _hash(i * 3 + 1, j * 5 + 2)
	match type:
		T_GRASS:
			var c := Color(0.50, 0.76, 0.30).lerp(Color(0.60, 0.84, 0.36), hs)
			return c if hs > 0.1 else Color(0.45, 0.70, 0.28)
		T_LAWN:
			# 剪过的草坪：一行深一行浅的条纹
			return (Color(0.57, 0.83, 0.34) if j % 2 == 0 else Color(0.51, 0.77, 0.31)) * (0.98 + 0.04 * hs)
		T_PAVE:
			if absf(x) > 4.6:
				return Color(0.66, 0.65, 0.68) * (0.96 + 0.08 * hs)
			return (Color(0.86, 0.85, 0.83) if (i + j) % 2 == 0 else Color(0.79, 0.78, 0.77)) * (0.97 + 0.06 * hs)
		T_PLAZA:
			var d := Vector2(x, z + 10.0).length()
			if d > 7.0:
				return Color(0.62, 0.61, 0.66) * (0.96 + 0.08 * hs)
			return (Color(0.90, 0.88, 0.84) if (i + j) % 2 == 0 else Color(0.85, 0.83, 0.80)) * (0.97 + 0.06 * hs)
		T_WATER:
			return Color(0.44, 0.82, 0.92).lerp(Color(0.36, 0.74, 0.90), hs)
		T_STONE:
			return (Color(0.80, 0.79, 0.79) if (i + j) % 2 == 0 else Color(0.74, 0.73, 0.74)) * (0.96 + 0.08 * hs)
		T_BED:
			return (Color(0.55, 0.38, 0.24) if j % 2 == 0 else Color(0.47, 0.32, 0.20)) * (0.96 + 0.08 * hs)
		T_WOOD:
			return Color(0.66, 0.46, 0.28) * (0.94 + 0.1 * hs)
		T_ROCK:
			return Color(0.48, 0.68, 0.32) if hs > 0.35 else Color(0.66, 0.66, 0.70)
		T_DIRT:
			return Color(0.74, 0.62, 0.44) * (0.95 + 0.1 * hs)
	return Color(0.6, 0.6, 0.6)


func _side_col(type: int, depth: float, hs: float) -> Color:
	if type == T_GRASS or type == T_LAWN or type == T_DIRT:
		if depth < 0.6:
			return Color(0.46, 0.70, 0.29)
		if depth < 3.4:
			return Color(0.76, 0.52, 0.29) * (0.94 + 0.1 * hs)
	if type == T_BED:
		return Color(0.46, 0.32, 0.20) * (0.94 + 0.1 * hs)
	if type == T_WOOD:
		return Color(0.48, 0.32, 0.20)
	if type == T_ROCK and depth < 0.5:
		return Color(0.46, 0.64, 0.30)
	return Color(0.70, 0.69, 0.72).lerp(Color(0.50, 0.50, 0.57), clampf(depth / 16.0, 0.0, 1.0)) * (0.93 + 0.12 * hs)


func _side(a: Array, p0: Vector3, p1: Vector3, n: Vector3, ytop: float, ybot: float, type: int, hs: float) -> void:
	var y := ytop
	for cut: float in [0.6, 3.4, 6.5, 10.0, 14.0, 18.0, 30.0]:
		var yb := maxf(ytop - cut, ybot)
		if yb >= y - 0.01:
			continue
		_quad(a, Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Vector3(p1.x, yb, p1.z), Vector3(p0.x, yb, p0.z), n,
				_side_col(type, ytop - (y + yb) * 0.5, hs), 0.0, false)
		y = yb
		if y <= ybot + 0.01:
			break


func _mesh_ground() -> void:
	var nb := [[-1, 0], [1, 0], [0, -1], [0, 1]]
	for j in N:
		for i in N:
			var h := _h[j * N + i]
			if h < VOID + 1.0:
				continue
			var type := int(_t[j * N + i])
			var x0 := float(i - HN) * CELL
			var z0 := float(j - HN) * CELL
			var c := _top_col(type, i, j, x0 + 1.0, z0 + 1.0)
			var water := type == T_WATER
			_quad(_w if water else _g, Vector3(x0, h, z0), Vector3(x0 + CELL, h, z0), Vector3(x0 + CELL, h, z0 + CELL), Vector3(x0, h, z0 + CELL), Vector3.UP, c,
					0.5 if water else 0.0)
			var hs := _hash(i * 7 + 3, j * 11 + 5)
			for k in 4:
				var ni: int = i + int(nb[k][0])
				var nj: int = j + int(nb[k][1])
				var edge := not _land(ni, nj)
				var nh := h - (26.0 if water else 18.0)
				if not edge:
					nh = _h[nj * N + ni]
				if nh >= h - 0.01:
					continue
				var tgt: Array = _g
				var ty := type
				if water:
					if edge:
						tgt = _w      # 水渠 / 泉眼流到岛边：这一面就是一道瀑布
					else:
						ty = T_STONE
				var pts: Array = [[Vector3(x0, 0, z0 + CELL), Vector3(x0, 0, z0), Vector3.LEFT], [Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3.RIGHT],
						[Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3.FORWARD], [Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL), Vector3.BACK]]
				var e: Array = pts[k]
				if tgt == _w:
					var p0: Vector3 = e[0]
					var p1: Vector3 = e[1]
					var dn: Vector3 = e[2]
					_quad(_w, Vector3(p0.x, h, p0.z) + dn * 0.05, Vector3(p1.x, h, p1.z) + dn * 0.05, Vector3(p1.x, nh, p1.z) + dn * 0.05, Vector3(p0.x, nh, p0.z) + dn * 0.05, dn,
							Color(0.78, 0.94, 1.0), 0.6, false)
					_side(_g, e[0] as Vector3, e[1] as Vector3, e[2] as Vector3, h - 0.05, h - 18.0, T_STONE, hs)
				else:
					_side(tgt, e[0] as Vector3, e[1] as Vector3, e[2] as Vector3, h, nh, ty, hs)
	# 岛底：往下收小的几层石头
	for k in 5:
		var s := 132.0 - 25.0 * float(k)
		BlockWorld._box(_g, Vector3(s, 9.0, s * 0.78), Transform3D(Basis(Vector3.UP, 0.25 * float(k) + 0.1), Vector3(0.0, -22.0 - 8.0 * float(k), -4.0)),
				Color(0.52, 0.51, 0.58) * (1.0 - 0.07 * float(k)), 0.0, 0.8)


func _commit(a: Array, shader: Shader, shadow: bool) -> MeshInstance3D:
	if (a[0] as PackedVector3Array).is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = shader
	if shader == WATER_SHADER:
		m.set_shader_parameter("noise_tex", NOISE)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# ---------- 构件 ----------

func _b(size: Vector3, pos: Vector3, c: Color, yaw := 0.0, em := 0.0, shade := 0.72) -> void:
	BlockWorld._box(_a, size, Transform3D(Basis(Vector3.UP, yaw), pos), c, em, shade)


func _bt(size: Vector3, pos: Vector3, c: Color, basis: Basis, em := 0.0, shade := 0.72) -> void:
	BlockWorld._box(_a, size, Transform3D(basis, pos), c, em, shade)


## 路边的灯柱：木柱顶着一盏暖黄的方灯、灯上一顶小檐
func _post_lamp(x: float, z: float, y := 0.0) -> void:
	_b(Vector3(0.8, 0.35, 0.8), Vector3(x, y + 0.17, z), STONE * 0.85)
	_b(Vector3(0.36, 3.0, 0.36), Vector3(x, y + 1.7, z), WOOD_D)
	_b(Vector3(0.8, 0.95, 0.8), Vector3(x, y + 3.55, z), LAMP, 0.0, 0.75, 0.95)
	_b(Vector3(0.92, 0.12, 0.92), Vector3(x, y + 3.05, z), WOOD_D)
	_b(Vector3(1.25, 0.25, 1.25), Vector3(x, y + 4.15, z), ROOF)
	_b(Vector3(0.5, 0.25, 0.5), Vector3(x, y + 4.38, z), ROOF * 0.85)


## 石灯笼：石座、石柱、灯室（亮）、石顶
func _toro(x: float, z: float, y := 0.0, s := 1.0) -> void:
	_b(Vector3(1.4, 0.4, 1.4) * s, Vector3(x, y + 0.2 * s, z), STONE * 0.9)
	_b(Vector3(0.6, 1.4, 0.6) * s, Vector3(x, y + 1.1 * s, z), STONE)
	_b(Vector3(1.2, 0.3, 1.2) * s, Vector3(x, y + 1.95 * s, z), STONE * 0.92)
	_b(Vector3(0.9, 0.85, 0.9) * s, Vector3(x, y + 2.5 * s, z), LAMP, 0.0, 0.7, 0.95)
	_b(Vector3(1.6, 0.35, 1.6) * s, Vector3(x, y + 3.1 * s, z), STONE * 0.86, PI * 0.25)
	_b(Vector3(0.45, 0.45, 0.45) * s, Vector3(x, y + 3.5 * s, z), STONE * 0.86)
	_block(x - 0.7 * s, z - 0.7 * s, x + 0.7 * s, z + 0.7 * s, y + 3.4 * s)


## 一段木篱笆（立柱 + 两道横杆），登记成实心；lamp_every > 0 时每隔几根柱子挂一盏小灯
func _fence(x0: float, z0: float, x1: float, z1: float, lamp_every := 0) -> void:
	var a := Vector3(x0, 0, z0)
	var b := Vector3(x1, 0, z1)
	var d := b - a
	var yaw := atan2(d.x, d.z)
	var n := maxi(int(d.length() / 2.4), 1)
	for hy: float in [0.55, 1.05]:
		_b(Vector3(0.14, 0.16, d.length()), (a + b) * 0.5 + Vector3(0, hy, 0), WOOD, yaw)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_b(Vector3(0.26, 1.35, 0.26), p + Vector3(0, 0.67, 0), WOOD_D)
		if lamp_every > 0 and i % lamp_every == 0:
			_b(Vector3(0.42, 0.5, 0.42), p + Vector3(0, 1.6, 0), LAMP, 0.0, 0.7, 0.95)
			_b(Vector3(0.6, 0.12, 0.6), p + Vector3(0, 1.92, 0), ROOF)
	_block(minf(x0, x1) - 0.3, minf(z0, z1) - 0.3, maxf(x0, x1) + 0.3, maxf(z0, z1) + 0.3, 1.3)


func _crate(x: float, z: float, y: float, s: float, yaw := 0.0, fill := Color(0, 0, 0, 0)) -> void:
	_b(Vector3(s, s * 0.8, s), Vector3(x, y + s * 0.4, z), Color(0.74, 0.54, 0.32), yaw)
	_b(Vector3(s + 0.06, s * 0.12, s + 0.06), Vector3(x, y + s * 0.62, z), Color(0.55, 0.38, 0.22), yaw)
	if fill.a > 0.0:
		# 箱口堆着的瓜果：一层圆鼓鼓的小方块
		var bs := Basis(Vector3.UP, yaw)
		for q in 4:
			var o := Vector3((float(q % 2) - 0.5) * s * 0.42, 0.0, (float(q / 2) - 0.5) * s * 0.42)
			_b(Vector3(s * 0.4, s * 0.3, s * 0.4), Vector3(x, y + s * 0.85, z) + bs * o, Color(fill.r, fill.g, fill.b) * (0.92 + 0.1 * float(q % 3)), yaw + 0.3 * float(q), 0.0, 0.9)


func _bamboo(cx: float, cz: float, n: int, spread: float, rng: RandomNumberGenerator, y := 0.0) -> void:
	for q in n:
		var x := cx + rng.randf_range(-spread, spread)
		var z := cz + rng.randf_range(-spread, spread)
		var hh := rng.randf_range(5.5, 9.5)
		var g := Color(0.42, 0.66, 0.28) * rng.randf_range(0.88, 1.12)
		_b(Vector3(0.34, hh, 0.34), Vector3(x, y + hh * 0.5, z), g)
		for k in 3:
			_b(Vector3(0.42, 0.14, 0.42), Vector3(x, y + hh * (0.3 + 0.25 * float(k)), z), g * 0.8)
		_b(Vector3(1.6, 0.8, 1.6), Vector3(x, y + hh * rng.randf_range(0.78, 0.98), z), Color(0.38, 0.64, 0.26) * rng.randf_range(0.9, 1.1), rng.randf(), 0.0, 0.8)
		_b(Vector3(1.1, 0.6, 1.1), Vector3(x + 0.6, y + hh * 0.7, z - 0.4), Color(0.44, 0.70, 0.30), rng.randf(), 0.0, 0.8)
	_block(cx - spread - 0.3, cz - spread - 0.3, cx + spread + 0.3, cz + spread + 0.3, 6.0)


func _tree(x: float, z: float, s: float, style: int, rng: RandomNumberGenerator, y := 0.0) -> void:
	bw._blossom(_a, Vector3(x, y, z), s, rng, style)
	_block(x - 0.6, z - 0.6, x + 0.6, z + 0.6, y + 3.0)


func _flowers(x: float, z: float, y: float, rng: RandomNumberGenerator, n := 6, spread := 2.0) -> void:
	var cols := [Color(1.0, 0.72, 0.84), Color(1.0, 0.96, 0.9), Color(1.0, 0.86, 0.5), Color(0.86, 0.72, 1.0)]
	for i in n:
		var p := Vector3(x + rng.randf_range(-spread, spread), y, z + rng.randf_range(-spread, spread))
		_b(Vector3(0.2, 0.5, 0.2), p + Vector3(0, 0.25, 0), Color(0.36, 0.6, 0.28))
		_b(Vector3(0.5, 0.34, 0.5), p + Vector3(0, 0.62, 0), cols[rng.randi() % cols.size()], rng.randf() * 0.8, 0.0, 0.95)


## 瀑布：一道竖着的水帘（流水着色器），底下一团水花
func _fall(x: float, z: float, top: float, bottom: float, w: float, yaw: float) -> void:
	var hh := top - bottom
	BlockWorld._box(_w, Vector3(w, hh, 0.5), Transform3D(Basis(Vector3.UP, yaw), Vector3(x, bottom + hh * 0.5, z)), Color(0.74, 0.93, 1.0), 0.6, 1.0)
	_b(Vector3(w + 1.4, 0.7, 1.8), Vector3(x, bottom + 0.2, z) + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.6), Color(0.97, 0.99, 1.0), yaw, 0.35, 1.0)


# ---------- 北面：石台上的殿、石阶、莲池、山石瀑布 ----------

func _build_hall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026112101
	var y := TERRACE_H
	# 殿：中间两层，两侧各一间耳房（门都朝南）
	bw._hall(_a, Vector3(0.0, y, HALL_Z), 20.0, 12.0, 7.2, PI, 0, 2)
	for sx: float in [-1.0, 1.0]:
		bw._hall(_a, Vector3(sx * 15.5, y, HALL_Z + 0.5), 9.0, 9.5, 5.2, PI, 0, 1)
	# 正门透着暖光（门框 + 发光的门 + 门上一枚金色的圆徽）；耳房两扇亮窗
	var fz := HALL_Z + 6.1
	_b(Vector3(4.4, 4.6, 0.3), Vector3(0.0, y + 0.7 + 2.3, fz), WOOD_D)
	_b(Vector3(3.4, 3.9, 0.36), Vector3(0.0, y + 0.7 + 1.95, fz + 0.05), Color(1.0, 0.78, 0.40), 0.0, 0.85, 1.0)
	_b(Vector3(0.16, 3.9, 0.4), Vector3(0.0, y + 0.7 + 1.95, fz + 0.08), Color(0.70, 0.42, 0.20), 0.0, 0.2)
	_b(Vector3(1.5, 1.5, 0.4), Vector3(0.0, y + 6.2, fz + 0.06), GOLD, PI * 0.25, 0.6, 1.0)
	for sx: float in [-1.0, 1.0]:
		for wx: float in [-2.0, 2.0]:
			_b(Vector3(1.5, 1.7, 0.3), Vector3(sx * 15.5 + wx, y + 3.2, HALL_Z + 0.5 + 4.85), LAMP, 0.0, 0.7, 0.95)
		_b(Vector3(1.3, 1.6, 0.3), Vector3(sx * 5.6, y + 3.5, fz + 0.02), LAMP, 0.0, 0.65, 0.95)
		# 门两边的红幡
		_b(Vector3(1.2, 3.8, 0.14), Vector3(sx * 7.8, y + 3.9, fz + 0.5), BANNER, 0.0, 0.0, 0.95)
		_b(Vector3(0.66, 0.66, 0.2), Vector3(sx * 7.8, y + 4.9, fz + 0.6), GOLD, 0.0, 0.2, 1.0)
		_b(Vector3(0.24, 5.4, 0.24), Vector3(sx * 7.8, y + 2.7, fz + 0.3), WOOD_D)
	# 台前的石栏（石阶口空着、山石那段不用）、石阶两侧的矮墙、台上两盏灯柱
	for seg: Array in [[-20.0, -5.6], [5.6, 20.0]]:
		var x0 := float(seg[0])
		var x1 := float(seg[1])
		_b(Vector3(x1 - x0, 1.0, 0.7), Vector3((x0 + x1) * 0.5, y + 0.5, -30.4), Color(0.80, 0.79, 0.79))
		_b(Vector3(x1 - x0 + 0.2, 0.22, 0.9), Vector3((x0 + x1) * 0.5, y + 1.1, -30.4), Color(0.86, 0.85, 0.85))
		for q in 4:
			_b(Vector3(0.9, 1.4, 0.9), Vector3(lerpf(x0 + 0.4, x1 - 0.4, float(q) / 3.0), y + 0.7, -30.4), Color(0.74, 0.73, 0.74))
		_block(x0, -31.0, x1, -29.8, y + 1.2)
	for sx: float in [-1.0, 1.0]:
		for k in 5:
			var hh := TERRACE_H - 0.5 * float(k + 1) + 0.9
			_b(Vector3(0.9, hh, 2.0), Vector3(sx * 5.45, hh * 0.5, -29.0 + 2.0 * float(k)), Color(0.74, 0.73, 0.74))
		_block(sx * 5.45 - 0.45, -30.0, sx * 5.45 + 0.45, -20.0, 1.5)
		_post_lamp(sx * 6.4, -33.0, y)
	# 殿前庭院：两株矮松、两只石灯笼
	for sx: float in [-1.0, 1.0]:
		_toro(sx * 9.5, -36.0, y, 0.9)
		bw._bush(_a, Vector3(sx * 13.0, y, -37.0), 1.2, Color(0.30, 0.56, 0.26), rng)
	# 莲池：荷叶、荷花
	for q in 34:
		var lx := rng.randf_range(-23.5, 23.5)
		var lz := rng.randf_range(-29.5, -22.5)
		if _type_at(lx, lz) != T_WATER:
			continue
		_b(Vector3(1.3, 0.1, 1.3), Vector3(lx, -0.52, lz), Color(0.40, 0.70, 0.34), rng.randf(), 0.0, 1.0)
		if q % 3 == 0:
			_b(Vector3(0.55, 0.45, 0.55), Vector3(lx, -0.25, lz), Color(1.0, 0.68, 0.84), rng.randf(), 0.08, 1.0)
	# 山石上的瀑布（从山石南面落进莲池），石缝里冒的几丛灌木
	for r: Array in [[-22.5, -28.0], [22.5, 28.0]]:
		var fx := float(r[0])
		var face := _rock_face(fx)
		var top := _h_at(fx, face - 1.0)
		if top > TERRACE_H + 1.0:
			# 山石南面落到石台上，顺着台面淌到台沿，再落进莲池
			_fall(fx, face + 0.3, top - 0.3, TERRACE_H, 3.2, 0.0)
			if face < -30.2:
				BlockWorld._box(_w, Vector3(3.2, 0.08, -30.0 - face), Transform3D(Basis.IDENTITY, Vector3(fx, TERRACE_H + 0.05, (face - 30.0) * 0.5)), Color(0.62, 0.88, 0.98), 0.45, 1.0)
		_fall(fx, -29.7, TERRACE_H + 0.05, -0.6, 3.2, 0.0)
		for q in 3:
			var bx := float(r[1]) + rng.randf_range(-4.0, 4.0)
			var bz := -36.0 + rng.randf_range(-3.0, 3.0)
			bw._bush(_a, Vector3(bx, maxf(_h_at(bx, bz), 0.0), bz), 0.9, Color(0.36, 0.60, 0.28), rng)
	# 殿后：樱、绿树、竹丛；东北角紫藤
	for t: Array in [[-22.0, -53.0, 1.5, 1], [-10.0, -54.5, 1.2, 2], [11.0, -54.5, 1.3, 1], [22.0, -53.0, 1.2, 2], [-34.0, -42.0, 1.3, 1],
			[34.0, -44.0, 1.45, 0], [0.0, -55.5, 1.3, 1]]:
		var tx := float(t[0])
		var tz := float(t[1])
		var gy := maxf(_h_at(tx, tz), 0.0)
		_tree(tx, tz, float(t[2]), int(t[3]), rng, gy)
	_bamboo(-30.0, -52.0, 9, 2.6, rng, 0.0)
	_bamboo(31.0, -52.0, 8, 2.4, rng, 0.0)
	# 山石顶上长一株樱 / 一株绿树，石缝里两盏石灯
	for rk: Array in [[-28.0, -39.0, 1], [-25.0, -42.0, 2], [28.0, -39.0, 1], [25.5, -42.0, 2], [56.0, -28.0, 1]]:
		var rx := float(rk[0])
		var rz := float(rk[1])
		_tree(rx, rz, 1.05, int(rk[2]), rng, maxf(_h_at(rx, rz), 0.0))


# ---------- 中轴：南门、石路、灯柱、莲花广场 ----------

func _build_axis() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026112102
	# 南门：门洞里是回主城的透视门（hub_portal.gd）；本地 yaw 0 搭，两面一样
	var gx := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, GATE_Z))
	build_gate(bw, _a, gx, 0.0)
	for sx: float in [-1.0, 1.0]:
		# 2026-11-23：门柱按石墩的真实大小（1.8 米见方）挡人（原来按两米格登记，八米的门洞只剩中间不到四米能走）；红幡在三米以上，不登记
		_block_fine(sx * (GATE_W * 0.5 + 0.5) - 0.9, GATE_Z - 0.9, sx * (GATE_W * 0.5 + 0.5) + 0.9, GATE_Z + 0.9, GATE_H + 6.0)
		_toro(sx * 9.0, GATE_Z + 2.5)
	# 2026-11-23 用户：「农场里面两侧的灯，可以都去掉，减少无用碰撞，阻挡玩家的路」——石路两边的七对灯柱、广场外圈的四盏、
	# 门里和殿前石阶脚下贴着路的两对石灯笼都撤了（每盏按两米格登记，实际挡掉两到四格）。门外的一对石灯笼、殿前台上的灯不在路上，留着
	# 莲花广场：地上一朵莲花纹（贴地的薄片，比 2 米一格细）、外圈四盏灯柱
	var c := Vector3(0.0, 0.0, -10.0)
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var bs := Basis(Vector3.UP, ang)
		_bt(Vector3(2.6, 0.06, 5.8), c + bs * Vector3(0.0, 0.03, -3.9), Color(1.0, 0.93, 0.82), bs, 0.08, 1.0)
		_bt(Vector3(1.6, 0.07, 3.8), c + bs * Vector3(0.0, 0.035, -3.7), Color(1.0, 0.80, 0.86), bs, 0.1, 1.0)
		var bs2 := Basis(Vector3.UP, ang + PI / 8.0)
		_bt(Vector3(1.7, 0.065, 3.4), c + bs2 * Vector3(0.0, 0.032, -2.6), Color(0.99, 0.95, 0.86), bs2, 0.05, 1.0)
	_bt(Vector3(2.4, 0.08, 2.4), c + Vector3(0.0, 0.04, 0.0), GOLD, Basis(Vector3.UP, PI * 0.25), 0.25, 1.0)
	_bt(Vector3(1.4, 0.09, 1.4), c + Vector3(0.0, 0.045, 0.0), Color(1.0, 0.92, 0.6), Basis.IDENTITY, 0.35, 1.0)
	# 南门外：两株樱（参考图门两边各一株）、岛南沿的一道石栏
	_tree(-15.0, 46.0, 1.3, 1, rng)
	_tree(16.0, 45.0, 1.25, 1, rng)
	_tree(-26.0, 44.0, 1.0, 3, rng)
	_tree(27.0, 43.0, 1.0, 2, rng)
	_flowers(-11.0, 43.0, 0.0, rng, 6, 1.6)
	_flowers(11.0, 43.0, 0.0, rng, 6, 1.6)


# ---------- 东面：种植区 ----------

func _build_fields() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026112103
	# 篱笆：沿石路那一边（留两个口子对着木桥）、南边、北边（牌坊那里空着）；路边那段挂小灯
	# 缺口两头各让出 1 米：实心格按 2 米一格算，缺口正好空出木桥那两格
	_fence(9.0, -24.0, 9.0, -17.0, 2)
	_fence(9.0, -11.0, 9.0, -1.0, 2)
	_fence(9.0, 5.0, 9.0, 36.0, 2)
	_fence(9.0, 36.0, 36.0, 36.0, 3)
	_fence(9.0, -25.5, 20.0, -25.5, 3)
	_fence(28.0, -25.5, 46.0, -25.5, 3)
	# 「种植区」牌坊（字另外挂）
	var sg := Vector3(24.0, 0.0, -27.0)
	for sx: float in [-1.0, 1.0]:
		_b(Vector3(1.2, 0.6, 1.2), sg + Vector3(sx * 3.6, 0.3, 0.0), STONE * 0.9)
		_b(Vector3(0.7, 5.6, 0.7), sg + Vector3(sx * 3.6, 2.8, 0.0), WOOD)
		_b(Vector3(0.9, 1.0, 0.24), sg + Vector3(sx * 3.6, 3.6, 0.42), LAMP, 0.0, 0.6, 0.95)
		_block(sg.x + sx * 3.6 - 0.6, sg.z - 0.6, sg.x + sx * 3.6 + 0.6, sg.z + 0.6, 6.0)
	_b(Vector3(9.4, 0.6, 0.9), sg + Vector3(0.0, 5.3, 0.0), WOOD_D)
	_b(Vector3(5.0, 1.5, 0.3), sg + Vector3(0.0, 4.3, 0.18), WOOD_D)
	_b(Vector3(4.5, 1.15, 0.36), sg + Vector3(0.0, 4.3, 0.2), Color(0.96, 0.88, 0.62), 0.0, 0.0, 1.0)
	bw._roof(_a, sg + Vector3(0.0, 5.6, 0.0), 9.0, 0.9, 0.0, ROOF)
	# 木桥：两道扶栏
	for br: Array in [[11.0, 2.0, 0], [11.0, -14.0, 0], [24.0, -23.0, 1], [24.0, -5.0, 1], [24.0, 11.0, 1], [48.0, 11.0, 1], [37.0, 20.0, 0], [48.0, -5.0, 1]]:
		var bx := float(br[0])
		var bz := float(br[1])
		var along_x := int(br[2]) == 0          # 0 = 桥沿 X 走（跨南北向的渠）
		for sd: float in [-1.0, 1.0]:
			var off := Vector3(0.0, 0.0, sd * 1.8) if along_x else Vector3(sd * 1.8, 0.0, 0.0)
			_b(Vector3(2.4 if along_x else 0.16, 0.16, 0.16 if along_x else 2.4), Vector3(bx, 0.95, bz) + off, WOOD_D)
			for e: float in [-1.0, 1.0]:
				var pe := Vector3(e * 1.1, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, e * 1.1)
				_b(Vector3(0.22, 0.95, 0.22), Vector3(bx, 0.55, bz) + off + pe, WOOD_D)
	# 麦田：一垄垄金黄的麦穗（一簇一个方块：麦秆 + 麦穗）
	for z in range(-19, -8):
		for xi in range(0, 26):
			var x := 14.6 + float(xi) * 0.75 + (0.25 if z % 2 == 0 else 0.0)
			if x > 33.6:
				continue
			var hh := rng.randf_range(1.0, 1.45)
			var zz := float(z) + 0.5 + rng.randf_range(-0.15, 0.15)
			if Vector2(x - float(FARMER_A[0]), zz - float(FARMER_A[1])).length() < 1.0:
				continue
			_b(Vector3(0.5, hh, 0.5), Vector3(x, 0.3 + hh * 0.5, zz), Color(0.90, 0.72, 0.30) * rng.randf_range(0.92, 1.06), rng.randf() * 0.4)
			_b(Vector3(0.58, 0.42, 0.58), Vector3(x, 0.3 + hh + 0.12, zz), Color(1.0, 0.84, 0.38) * rng.randf_range(0.94, 1.06), rng.randf() * 0.4, 0.05, 0.9)
	# 灵田（2026-11-23 种植系统；同日下午按用户要求改成每块 4×4 格）：原来白菜、胡萝卜、西瓜、番茄四畦的地方开六块灵田（farm_plots.gd 管种什么、长到哪）。
	# 这里只画不变的部分：一整块翻过的深色底土、十六格隆起的土垄（一格一株）、一圈矮木框
	for fi in FarmPlots.FIELDS.size():
		var c: Vector3 = FarmPlots.FIELDS[fi]
		var hs := FarmPlots.FIELD_W * 0.5
		_b(Vector3(FarmPlots.FIELD_W, 0.1, FarmPlots.FIELD_W), c + Vector3(0.0, 0.05, 0.0), Color(0.33, 0.22, 0.14), 0.0, 0.0, 1.0)
		for k in FarmPlots.GRID * FarmPlots.GRID:
			var cp := FarmPlots.cell_local(fi * FarmPlots.GRID * FarmPlots.GRID + k)
			_b(Vector3(FarmPlots.MOUND, 0.12, FarmPlots.MOUND), cp + Vector3(0.0, 0.16, 0.0), Color(0.47, 0.32, 0.20) * rng.randf_range(0.95, 1.04), 0.0, 0.0, 1.0)
		for sd: float in [-1.0, 1.0]:
			_b(Vector3(FarmPlots.FIELD_W + 0.3, 0.26, 0.16), c + Vector3(0.0, 0.13, sd * (hs + 0.08)), WOOD_D)
			_b(Vector3(0.16, 0.26, FarmPlots.FIELD_W + 0.3), c + Vector3(sd * (hs + 0.08), 0.13, 0.0), WOOD_D)
	# 敞棚：四角木柱、一顶黛紫瓦的棚顶；棚下工作台、农具、麻袋、木箱、木桶
	var sc := Vector3(53.0, 0.0, -13.0)
	for cx: float in [-5.6, 0.0, 5.6]:
		for cz: float in [-4.2, 4.2]:
			_b(Vector3(0.45, 4.2, 0.45), sc + Vector3(cx, 2.1, cz), WOOD)
			_block(sc.x + cx - 0.3, sc.z + cz - 0.3, sc.x + cx + 0.3, sc.z + cz + 0.3, 4.2)
	_b(Vector3(12.0, 0.4, 9.2), sc + Vector3(0.0, 4.3, 0.0), WOOD_D)
	bw._roof(_a, sc + Vector3(0.0, 4.5, 0.0), 11.6, 8.8, 0.0, ROOF)
	_b(Vector3(3.6, 0.3, 1.4), sc + Vector3(-2.0, 1.1, -2.6), WOOD)
	for lx: float in [-3.5, -0.5]:
		_b(Vector3(0.25, 1.0, 0.25), sc + Vector3(lx, 0.5, -2.6), WOOD_D)
	_block(sc.x - 3.9, sc.z - 3.4, sc.x - 0.1, sc.z - 1.8, 1.3)
	for tl: Array in [[3.6, -3.6, 0.2], [4.2, -3.4, -0.2], [4.8, -3.7, 0.1]]:      # 靠在棚柱上的锄头、耙子
		var tb := Basis(Vector3.RIGHT, -0.25) * Basis(Vector3.FORWARD, float(tl[2]))
		_bt(Vector3(0.12, 2.6, 0.12), sc + Vector3(float(tl[0]), 1.3, float(tl[1])), Color(0.64, 0.48, 0.3), tb)
		_bt(Vector3(0.7, 0.14, 0.3), sc + Vector3(float(tl[0]), 2.55, float(tl[1]) - 0.3), Color(0.55, 0.56, 0.6), tb)
	for q in 4:
		_b(Vector3(1.1, 0.7, 0.8), sc + Vector3(-4.0 + 1.0 * float(q % 2), 0.35 + 0.6 * float(q / 2), 2.4), Color(0.86, 0.76, 0.54), 0.3 * float(q))
	_crate(sc.x + 1.5, sc.z + 2.6, 0.0, 1.3, 0.2, Color(0.98, 0.84, 0.36))
	_crate(sc.x + 3.2, sc.z + 2.4, 0.0, 1.2, -0.1, Color(0.42, 0.72, 0.30))
	_b(Vector3(1.0, 1.3, 1.0), sc + Vector3(4.6, 0.65, 0.0), Color(0.58, 0.38, 0.22))
	_b(Vector3(1.06, 0.12, 1.06), sc + Vector3(4.6, 0.9, 0.0), Color(0.3, 0.26, 0.24))
	_block(sc.x - 4.6, sc.z + 1.6, sc.x + 5.2, sc.z + 3.3, 1.4)
	# 东北角的山石泉眼 → 架在木腿上的引水槽 → 冲着水车（水车本身另建一个会转的节点）
	var trough_y := 4.6
	_b(Vector3(6.4, 0.5, 1.2), Vector3(50.6, trough_y, -23.0), WOOD_D)
	for sd: float in [-1.0, 1.0]:
		_b(Vector3(6.4, 0.5, 0.2), Vector3(50.6, trough_y + 0.4, -23.0 + sd * 0.55), WOOD)
	for lx2: float in [48.4, 52.0]:
		_b(Vector3(0.3, trough_y, 0.3), Vector3(lx2, trough_y * 0.5, -22.2), WOOD_D)
		_b(Vector3(0.3, trough_y, 0.3), Vector3(lx2, trough_y * 0.5, -23.8), WOOD_D)
	BlockWorld._box(_w, Vector3(6.2, 0.12, 0.9), Transform3D(Basis.IDENTITY, Vector3(50.6, trough_y + 0.3, -23.0)), Color(0.56, 0.86, 0.96), 0.4, 1.0)
	_fall(47.3, -23.0, trough_y + 0.3, 1.8, 0.9, PI * 0.5)
	_block(46.0, -24.6, 53.8, -21.4, trough_y + 0.6)
	# 南边：一排装着瓜果的木箱、木桶、一个带棚顶的小摊
	var fills := [Color(0.95, 0.26, 0.18), Color(0.50, 0.78, 0.30), Color(0.98, 0.82, 0.30), Color(0.98, 0.58, 0.18), Color(0.30, 0.56, 0.24)]
	for q in 7:
		_crate(40.6 + float(q) * 2.0, 31.0 + (0.4 if q % 2 == 0 else -0.2), 0.0, 1.5, rng.randf_range(-0.15, 0.15), fills[q % fills.size()])
	for q in 3:
		_crate(41.6 + float(q) * 3.0, 33.4, 0.0, 1.3, rng.randf_range(-0.2, 0.2), fills[(q + 2) % fills.size()])
	_block(39.6, 29.8, 54.6, 34.4, 1.6)
	_b(Vector3(1.1, 1.4, 1.1), Vector3(56.4, 0.7, 32.6), Color(0.58, 0.38, 0.22))
	_b(Vector3(1.16, 0.14, 1.16), Vector3(56.4, 1.0, 32.6), Color(0.3, 0.26, 0.24))
	var st := Vector3(55.0, 0.0, 29.0)
	for cx2: float in [-2.2, 2.2]:
		for cz2: float in [-1.4, 1.4]:
			_b(Vector3(0.3, 3.0, 0.3), st + Vector3(cx2, 1.5, cz2), WOOD)
	_b(Vector3(4.6, 1.0, 1.4), st + Vector3(0.0, 0.5, 0.6), WOOD)
	for q in 4:
		_b(Vector3(0.7, 0.5, 0.7), st + Vector3(-1.6 + 1.05 * float(q), 1.25, 0.6), fills[q], 0.0, 0.0, 0.92)
	bw._roof(_a, st + Vector3(0.0, 3.0, 0.0), 4.4, 2.8, 0.0, ROOF)
	_b(Vector3(0.9, 1.8, 0.1), st + Vector3(2.6, 2.0, 1.5), BANNER, 0.0, 0.0, 0.95)
	_block(st.x - 2.4, st.z - 1.6, st.x + 2.4, st.z + 1.6, 3.0)
	# 东沿一排竹子、几丛花
	for bz: float in [-8.0, 2.0, 12.0, 22.0]:
		_bamboo(62.5, bz, 6, 1.8, rng)
	_flowers(60.0, 34.0, 0.0, rng, 5, 1.4)
	_flowers(30.0, 32.0, 0.0, rng, 5, 1.4)


## 水车：轮辋（一圈木块）、八根辐条、一圈叶板、中间的轴；整个节点绕 Z 轴转（tick 里转）。木架、轴座并在静态网格里
func _build_wheel() -> void:
	var a := _arr()
	var r := 2.5
	for k in 16:
		var ang := TAU * float(k) / 16.0
		var p := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		BlockWorld._box(a, Vector3(1.05, 0.3, 0.9), Transform3D(Basis(Vector3.BACK, ang + PI * 0.5), p), WOOD, 0.0, 0.9)
		BlockWorld._box(a, Vector3(0.12, 0.7, 1.1), Transform3D(Basis(Vector3.BACK, ang), p * 1.08), WOOD_D, 0.0, 0.9)
	for k in 4:
		var ang2 := PI * float(k) / 4.0
		BlockWorld._box(a, Vector3(r * 2.0, 0.22, 0.22), Transform3D(Basis(Vector3.BACK, ang2), Vector3(0.0, 0.0, 0.3)), WOOD_D, 0.0, 0.9)
		BlockWorld._box(a, Vector3(r * 2.0, 0.22, 0.22), Transform3D(Basis(Vector3.BACK, ang2), Vector3(0.0, 0.0, -0.3)), WOOD_D, 0.0, 0.9)
	BlockWorld._box(a, Vector3(0.7, 0.7, 1.4), Transform3D.IDENTITY, Color(0.36, 0.34, 0.36))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_wheel = Node3D.new()
	_wheel.position = Vector3(45.0, 2.1, -23.0)
	root.add_child(_wheel)
	var mi := MeshInstance3D.new()
	mi.set_meta("portal_sync", true)      # 透视门里的副本每帧跟着转
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	mi.material_override = m
	_wheel.add_child(mi)
	# 轴座（静态网格那张已经提交了，这两根柱子单独并一张小网格）
	var s := _arr()
	for sd: float in [-1.0, 1.0]:
		BlockWorld._box(s, Vector3(0.4, 2.5, 0.4), Transform3D(Basis.IDENTITY, Vector3(45.0, 0.65, -23.0 + sd * 1.0)), WOOD_D)
	var keep := _a
	_a = s
	_commit(_a, WORLD_SHADER, true)
	_a = keep
	_block(43.6, -24.0, 46.4, -22.0, 4.8)


# ---------- 四周：岛沿的树、泉、云、远处的小浮岛 ----------

func _free(x: float, z: float) -> bool:
	var i := _ci(x)
	var j := _ci(z)
	if not _land(i, j) or _solid[j * N + i] > 0.0:
		return false
	var t := int(_t[j * N + i])
	return t == T_GRASS


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026112104
	# 岛沿（灵宠区外面）一圈樱和绿树、灌木
	# 参考图里岛沿一圈都是花树：西沿、西南、东南、东北各几株（灵宠区的草坪上一棵不种）
	for t: Array in [[-63.5, -14.0, 1.3, 1], [-63.5, 4.0, 1.2, 1], [-62.5, 22.0, 1.15, 1], [-58.0, 36.0, 1.0, 2], [-40.0, 41.0, 1.3, 1], [-32.0, 44.0, 1.1, 1],
			[-24.0, 45.5, 0.95, 2], [-60.0, -28.0, 1.2, 1], [-48.0, -30.0, 1.1, 2], [-38.0, -28.0, 1.3, 1], [-28.0, -52.0, 1.2, 1], [-44.0, -44.0, 1.4, 1],
			[-54.0, -38.0, 1.1, 2], [26.0, 43.0, 1.0, 1], [36.0, 41.0, 1.15, 1], [46.0, 38.0, 0.95, 2], [61.0, -20.0, 1.2, 1], [44.0, -44.0, 1.1, 2],
			[50.0, -38.0, 1.25, 1], [40.0, -34.0, 1.0, 1], [28.0, -50.0, 1.1, 1]]:
		if _free(float(t[0]), float(t[1])):
			_tree(float(t[0]), float(t[1]), float(t[2]), int(t[3]), rng)
	_bamboo(-35.0, -48.0, 6, 2.0, rng)
	_bamboo(52.0, -44.0, 6, 2.0, rng)
	_bamboo(-61.0, -4.0, 4, 1.4, rng)
	for q in 18:
		var bx := rng.randf_range(-72.0, 72.0)
		var bz := rng.randf_range(-50.0, 50.0)
		var inside_pet := bx > PET_X0 - 2.0 and bx < PET_X1 + 2.0 and bz > PET_Z0 - 2.0 and bz < PET_Z1 + 2.0
		if _free(bx, bz) and not inside_pet and absf(bx) > 9.0:
			bw._bush(_a, Vector3(bx, 0.0, bz), rng.randf_range(0.8, 1.1), Color(0.36, 0.62, 0.26) * rng.randf_range(0.9, 1.12), rng)
	for f: Array in [[-20.0, 46.0], [22.0, 48.0], [-46.0, -40.0], [44.0, -44.0], [-8.0, -40.0]]:
		_flowers(float(f[0]), float(f[1]), maxf(_h_at(float(f[0]), float(f[1])), 0.0), rng, 5, 1.5)
	# 西南角的泉眼：一圈石头围着，水从岛边落下去（那一面就是瀑布，见 _mesh_ground）
	for q in 6:
		var ang := TAU * float(q) / 6.0
		_b(Vector3(1.6, 0.9, 1.4), Vector3(-46.0 + cos(ang) * 4.6, 0.3, 46.0 + sin(ang) * 3.6), Color(0.66, 0.66, 0.70), ang, 0.0, 0.8)
	# 岛外的云团（方块堆的）
	# 岛外的云团：压低、压扁，颜色往天空盒那片粉紫的云海上靠（远处的云海交给天空盒）
	for q in (18 if mobile else 28):
		var ang2 := TAU * float(q) / (18.0 if mobile else 28.0) + rng.randf_range(-0.1, 0.1)
		var rad := rng.randf_range(100.0, 200.0)
		var cp := Vector3(cos(ang2) * rad, rng.randf_range(-34.0, -16.0), sin(ang2) * rad)
		for k in 3:
			var s := rng.randf_range(14.0, 28.0)
			_b(Vector3(s, s * 0.24, s * rng.randf_range(0.6, 1.0)), cp + Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-2.0, 3.0), rng.randf_range(-9.0, 9.0)),
					Color(0.99, 0.88, 0.95).lerp(Color(0.92, 0.84, 0.97), rng.randf()), rng.randf() * 0.6, 0.0, 0.94)
	# 小浮岛：草顶、往下收的石根、一株樱或一座小亭、一道瀑布
	var isles := [[-150.0, 20.0, -150.0, 24.0], [150.0, 26.0, -170.0, 28.0], [-210.0, 40.0, -20.0, 22.0], [210.0, 16.0, 20.0, 22.0], [40.0, 50.0, -250.0, 30.0],
			[-90.0, 56.0, -240.0, 26.0], [170.0, 8.0, 140.0, 18.0], [-170.0, 4.0, 150.0, 18.0]]
	for q in isles.size():
		var e: Array = isles[q]
		var ip := Vector3(float(e[0]), float(e[1]), float(e[2]))
		var s2 := float(e[3])
		_b(Vector3(s2, 2.0, s2 * 0.8), ip, Color(0.54, 0.76, 0.32), 0.3 * float(q))
		_b(Vector3(s2 * 0.96, 1.6, s2 * 0.76), ip - Vector3(0, 1.8, 0), Color(0.86, 0.56, 0.28), 0.3 * float(q))
		for k in 3:
			var sk := s2 * (0.8 - 0.22 * float(k))
			_b(Vector3(sk, 5.0, sk * 0.8), ip - Vector3(0, 5.0 + 4.6 * float(k), 0), Color(0.62, 0.61, 0.66) * (1.0 - 0.08 * float(k)), 0.3 * float(q) + 0.2 * float(k))
		if q % 2 == 0:
			bw._blossom(_a, ip + Vector3(-s2 * 0.2, 1.0, 0.0), 1.5, rng, 1)
		else:
			bw._hall(_a, ip + Vector3(0.0, 1.0, 0.0), 7.0, 7.0, 5.0, 0.0, 0, 2)
		BlockWorld._box(_w, Vector3(3.0, 26.0, 0.6), Transform3D(Basis(Vector3.UP, 0.3 * float(q)), ip + Vector3(s2 * 0.3, -13.0, s2 * 0.41)), Color(0.74, 0.93, 1.0), 0.5, 1.0)


# ---------- 农人（摆着不动的方块人，并成一张网格） ----------

func _build_people() -> void:
	# [x, z, 朝向, 拿什么]：一个在麦田里扶着锄头，一个在胡萝卜地边挎着篮子（参考图右边那两位）
	var folks := [FARMER_A, FARMER_B]
	var st := SurfaceTool.new()
	var mat: Material = null
	for f: Array in folks:
		var hero := VoxelHero.new({}, false, true, -1)
		for i in 8:
			hero.animate(0.1, 0.0, 0.0, false, false)
		var gy := maxf(_h_at(float(f[0]), float(f[1])), 0.0)
		var base := Transform3D(Basis(Vector3.UP, float(f[2])), Vector3(float(f[0]), gy, float(f[1])))
		for c in hero.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == hero.cloth or mi.mesh == null or not mi.visible:
				continue
			var xf := mi.transform
			var p := mi.get_parent()
			while p != null and p != hero:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for si in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, si, base * xf)
			if mat == null:
				mat = mi.get_active_material(0)
		hero.free()
		var bs := Basis(Vector3.UP, float(f[2]))
		var at := Vector3(float(f[0]), gy, float(f[1]))
		if int(f[3]) == 0:
			# 锄头：斜着拄在身前
			var hb := bs * Basis(Vector3.RIGHT, -0.5)
			_bt(Vector3(0.12, 2.2, 0.12), at + bs * Vector3(0.45, 1.05, -0.55), Color(0.64, 0.48, 0.30), hb)
			_bt(Vector3(0.55, 0.12, 0.34), at + bs * Vector3(0.45, 0.12, -1.05), Color(0.56, 0.57, 0.62), bs)
		else:
			# 竹篮：挎在身侧，篮里几个红番茄
			_bt(Vector3(0.8, 0.5, 0.6), at + bs * Vector3(0.62, 0.95, 0.0), Color(0.80, 0.64, 0.36), bs)
			_bt(Vector3(0.1, 0.6, 0.1), at + bs * Vector3(0.62, 1.35, 0.0), Color(0.70, 0.54, 0.30), bs)
			for q in 3:
				_bt(Vector3(0.24, 0.24, 0.24), at + bs * Vector3(0.45 + 0.17 * float(q), 1.25, 0.05 * float(q)), Color(0.95, 0.26, 0.18), bs, 0.04)
		_block(at.x - 0.5, at.z - 0.5, at.x + 0.5, at.z + 0.5, gy + 1.9)
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	root.add_child(node)


# ---------- 牌匾上的字 ----------

func _label(text: String, pos: Vector3, h: float, size := 110, yaw := 0.0) -> void:
	if font == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = h * 0.62 / float(size)
	l.modulate = Color(0.24, 0.14, 0.08)
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	root.add_child(l)


func _build_signs() -> void:
	_label("种植区", Vector3(24.0, 4.3, -26.6), 1.15, 110)
	# 南门的匾：朝岛里那面「回主城」，朝外那面「灵田农场」
	_label("回 主 城", Vector3(0.0, GATE_H + 1.45, GATE_Z - 0.33), 0.95, 100, PI)
	_label("灵田农场", Vector3(0.0, GATE_H + 1.45, GATE_Z + 0.33), 0.95, 100)


# ---------- 地面高度（世界坐标；hub_hall.gd 在农场时问这里） ----------

func ground(x: float, z: float) -> float:
	var i := _ci(x - ORIGIN.x)
	var j := _ci(z - ORIGIN.z)
	if not _land(i, j):
		return -60.0
	var h := _h[j * N + i]
	return h - (0.5 if int(_t[j * N + i]) == T_WATER else 0.0)


func solid_at(x: float, z: float) -> float:
	var i := _ci(x - ORIGIN.x)
	var j := _ci(z - ORIGIN.z)
	var top := _solid[j * N + i] if _in(i, j) else 0.0
	var lx := x - ORIGIN.x
	var lz := z - ORIGIN.z
	var k := 0
	while k < _fine.size():
		if lx >= _fine[k] and lx <= _fine[k + 2] and lz >= _fine[k + 1] and lz <= _fine[k + 3]:
			top = maxf(top, _fine[k + 4])
		k += 5
	return top


## 世界坐标在不在灵宠区 / 种植区（自检和提示用）
func zone_of(p: Vector3) -> String:
	var x := p.x - ORIGIN.x
	var z := p.z - ORIGIN.z
	if x > PET_X0 and x < PET_X1 and z > PET_Z0 and z < PET_Z1:
		return "pet"
	if x > 8.0 and x < 64.0 and z > -24.0 and z < 36.0:
		return "field"
	return ""


## 灵宠区里有没有地面以外的东西（自检：草坪要干净）：[立在草坪上的建筑 / 点缀顶点数（2.5 米以下）, 岛沿花树伸到草坪上空的树冠顶点数]
func pet_clutter() -> Array:
	var n := 0
	var over := 0
	var v: PackedVector3Array = _a[0]
	for p in v:
		if p.x > PET_X0 + 0.5 and p.x < PET_X1 - 0.5 and p.z > PET_Z0 + 0.5 and p.z < PET_Z1 - 0.5 and p.y > 0.02 and p.y < 40.0:
			if p.y < 2.5:
				n += 1
			else:
				over += 1
	return [n, over]


# ---------- 灵田（hub_hall.gd 在农场时转问这里） ----------

func use_text(world_pos: Vector3) -> String:
	return plots.use_text(world_pos) if plots != null else ""


func use(world_pos: Vector3) -> void:
	if plots != null:
		plots.use(world_pos)
