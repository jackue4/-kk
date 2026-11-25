extends RefCounted
## 天南秘境（实验关卡，2026-11-24）：原创的「房间零件」。
## 做法：一关 = 一串「段」，每段从一个小池子里抽一间房；房间之间门对门拼起来（全关统一门宽），大小交替、
## 可走面积不到一半、每间房自带刷怪区。房间内容全部是这里自己画的（天南题材：接引阵台 / 幽篁径 / 断云台 / 藏经残殿 / 镇剑坪 / 剑冢 …）。
## 一格 = 2 米（同方块世界的 CELL），高度单位是米、相对房间自己的基准面。
## 故意不写 class_name：用 preload 引用。只被 scripts/lab/mijing_level.gd 用，不进正式流程。

const DW := 4                # 门宽（格）= 8 米
const WALL := 11.0           # 墙顶比房间基准面高多少
const VOID_H := -7.0         # 云渊（掉下去送回上一个落脚点）

const T_ROCK := 0            # 山体（墙）
const T_STONE := 1           # 铺地石
const T_PATH := 2            # 路面青石
const T_GRASS := 3
const T_MOSS := 4
const T_WATER := 5
const T_JADE := 6            # 青玉镶边
const T_RED := 7             # 朱砂红毯
const T_DARK := 8            # 殿内深色石板
const T_SOIL := 9            # 药圃的土
const T_VOID := 10           # 云渊
const T_WOOD := 11           # 栈桥木板
const T_GOLD := 12           # 阵纹（发光）
const T_PILLAR := 13         # 石柱 / 碑（实心，挡路）

## 房间表：w / l（格）、门 [边, 沿边起点, 高差, 是不是「备用门」（主路不优先走，留给支线 / 封死）]、cap（飞行上限比基准面高多少）
const DEFS := {
	"start": {"name": "接引阵台", "w": 22, "l": 22, "doors": [["E", 9, 0.0, false]], "kind": "start"},
	"lane_a": {"name": "石径", "w": 8, "l": 16, "doors": [["N", 2, 0.0, false], ["S", 2, 0.0, false]], "kind": "lane"},
	"lane_turn": {"name": "回折径", "w": 14, "l": 14, "doors": [["W", 5, 0.0, false], ["S", 5, 0.0, false]], "kind": "lane"},
	"lane_stairs": {"name": "登云阶", "w": 8, "l": 20, "doors": [["S", 2, 0.0, false], ["N", 2, 5.0, false]], "kind": "lane", "wall": 16.0, "cap": 12.0},
	"cross": {"name": "四象路口", "w": 14, "l": 14, "doors": [["N", 5, 0.0, false], ["E", 5, 0.0, false], ["S", 5, 0.0, false], ["W", 5, 0.0, false]], "kind": "small"},
	"bamboo": {"name": "幽篁径", "w": 26, "l": 22, "doors": [["W", 4, 0.0, false], ["E", 14, 0.0, false], ["S", 16, 0.0, true]], "kind": "medium"},
	"vista": {"name": "断云台", "w": 48, "l": 40, "doors": [["W", 18, 0.0, false], ["S", 35, 0.0, false], ["N", 30, 3.0, true], ["E", 18, 0.0, true]], "kind": "large", "cap": 9.0},
	"hall": {"name": "藏经残殿", "w": 30, "l": 24, "doors": [["S", 13, 0.0, false], ["E", 10, 0.0, false], ["N", 13, 0.0, true]], "kind": "medium"},
	"garden": {"name": "灵药圃", "w": 26, "l": 26, "doors": [["N", 11, 0.0, false], ["E", 11, 0.0, false], ["S", 11, 0.0, false], ["W", 11, 0.0, false]], "kind": "hub"},
	"den": {"name": "剑傀阵", "w": 30, "l": 30, "doors": [["S", 13, 0.0, false], ["E", 13, 0.0, false]], "kind": "medium"},
	"gate": {"name": "禁制关", "w": 12, "l": 14, "doors": [["S", 4, 0.0, false], ["N", 4, 0.0, false]], "kind": "small"},
	"plaza": {"name": "镇剑坪", "w": 56, "l": 48, "doors": [["W", 22, 0.0, false], ["N", 26, 0.0, false], ["S", 26, 0.0, true], ["E", 22, 0.0, true]], "kind": "large", "cap": 9.0},
	"steles": {"name": "碑林", "w": 24, "l": 28, "doors": [["W", 4, 0.0, false], ["E", 20, 0.0, false], ["S", 10, 0.0, true]], "kind": "medium"},
	"spring": {"name": "悬泉", "w": 22, "l": 26, "doors": [["S", 9, 0.0, false], ["W", 16, 0.0, false], ["N", 9, 0.0, true]], "kind": "medium"},
	"arena": {"name": "剑冢", "w": 44, "l": 44, "doors": [["S", 20, 0.0, false]], "kind": "final", "cap": 9.0},
	"grove": {"name": "枫林", "w": 18, "l": 18, "doors": [["S", 7, 0.0, false], ["N", 7, 0.0, false]], "kind": "side"},
	"nook_chest": {"name": "藏宝龛", "w": 10, "l": 10, "doors": [["S", 3, 0.0, false]], "kind": "cap"},
	"nook_shrine": {"name": "残祠", "w": 12, "l": 12, "doors": [["S", 4, 0.0, false]], "kind": "cap"},
	"nook_pool": {"name": "灵眼", "w": 10, "l": 12, "doors": [["S", 3, 0.0, false]], "kind": "cap"},
}

## 一关的段落：每段一个池子，按顺序各抽一间（已经用过的排后面）。节奏：固定开场 → 小 → 中 → 小 → 大景 → 小 → 中 → 歇脚 → 小头目 → 卡口 → 大目标 → 中 → 小 → 终点
const SEQ := [["start"], ["lane_a", "lane_turn"], ["bamboo", "steles"], ["cross"], ["vista"], ["lane_stairs"], ["hall"], ["garden"],
		["den"], ["gate"], ["plaza"], ["spring", "steles", "bamboo"], ["lane_turn", "lane_a"], ["arena"]]
const SIDE := ["grove"]
const CAPS := ["nook_chest", "nook_shrine", "nook_pool"]


class Room:
	var id := ""
	var title := ""
	var w := 0
	var l := 0
	var wall := 11.0
	var cap := 7.0
	var doors: Array = []
	var open: Array = []
	var h := PackedFloat32Array()
	var t := PackedByteArray()
	var props: Array = []          # [kind, x, z, yaw, arg]（x / z 是格坐标，可带小数）
	var zones: Array = []          # [x, z, r, n, elite]

	func setup(rid: String, d: Dictionary, op: Array) -> void:
		id = rid
		title = str(d["name"])
		w = int(d["w"])
		l = int(d["l"])
		wall = float(d.get("wall", 11.0))
		cap = float(d.get("cap", 7.0))
		doors = d["doors"]
		open = op
		h.resize(w * l)
		h.fill(wall)
		t.resize(w * l)
		t.fill(0)

	func is_open(i: int) -> bool:
		return i < open.size() and bool(open[i])

	func put(i: int, j: int, ty: int, hh: float) -> void:
		if i < 0 or j < 0 or i >= w or j >= l:
			return
		h[j * w + i] = hh
		t[j * w + i] = ty

	func hat(i: int, j: int) -> float:
		if i < 0 or j < 0 or i >= w or j >= l:
			return wall
		return h[j * w + i]

	func tat(i: int, j: int) -> int:
		if i < 0 or j < 0 or i >= w or j >= l:
			return 0
		return t[j * w + i]

	func rect(x0: int, z0: int, x1: int, z1: int, ty: int, hh := 0.0) -> void:
		for j in range(z0, z1):
			for i in range(x0, x1):
				put(i, j, ty, hh)

	## 把一块填回山体
	func rock(x0: int, z0: int, x1: int, z1: int) -> void:
		rect(x0, z0, x1, z1, 0, wall)

	func ell(cx: float, cz: float, rx: float, rz: float, ty: int, hh := 0.0) -> void:
		for j in range(int(floorf(cz - rz)), int(ceilf(cz + rz)) + 1):
			for i in range(int(floorf(cx - rx)), int(ceilf(cx + rx)) + 1):
				var dx := (float(i) + 0.5 - cx) / rx
				var dz := (float(j) + 0.5 - cz) / rz
				if dx * dx + dz * dz <= 1.0:
					put(i, j, ty, hh)

	func disc(cx: float, cz: float, r: float, ty: int, hh := 0.0) -> void:
		ell(cx, cz, r, r, ty, hh)

	func ring(cx: float, cz: float, r0: float, r1: float, ty: int, hh := 0.0) -> void:
		for j in range(int(floorf(cz - r1)), int(ceilf(cz + r1)) + 1):
			for i in range(int(floorf(cx - r1)), int(ceilf(cx + r1)) + 1):
				var d := Vector2(float(i) + 0.5 - cx, float(j) + 0.5 - cz).length()
				if d >= r0 and d <= r1:
					put(i, j, ty, hh)

	## 边缘起伏的一团（林间空地这类不规则的形状）
	func blob(cx: float, cz: float, r: float, ty: int, hh := 0.0, sd := 0.0) -> void:
		for j in range(int(floorf(cz - r * 1.3)), int(ceilf(cz + r * 1.3)) + 1):
			for i in range(int(floorf(cx - r * 1.3)), int(ceilf(cx + r * 1.3)) + 1):
				var dx := float(i) + 0.5 - cx
				var dz := float(j) + 0.5 - cz
				var a := atan2(dz, dx)
				var rr := r * (1.0 + 0.16 * sin(a * 3.0 + sd) + 0.09 * sin(a * 5.0 + sd * 2.3))
				if dx * dx + dz * dz <= rr * rr:
					put(i, j, ty, hh)

	## 一条有宽度的路（a → b），高度从 ha 渐变到 hb（按半米取整，走起来是缓坡）
	func line(ax: float, az: float, bx: float, bz: float, wd: float, ty: int, ha := 0.0, hb := 0.0) -> void:
		var a := Vector2(ax, az)
		var b := Vector2(bx, bz)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.0001)
		var hw := wd * 0.5
		for j in range(int(floorf(minf(az, bz) - hw)), int(ceilf(maxf(az, bz) + hw)) + 1):
			for i in range(int(floorf(minf(ax, bx) - hw)), int(ceilf(maxf(ax, bx) + hw)) + 1):
				var p := Vector2(float(i) + 0.5, float(j) + 0.5)
				var k := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				if p.distance_to(a + ab * k) <= hw:
					put(i, j, ty, roundf(lerpf(ha, hb, k) * 2.0) * 0.5)

	## 实心柱 / 碑：这一格比现在的地面再高 up 米（走不过去）
	func pillar(i: int, j: int, up: float) -> void:
		if i < 0 or j < 0 or i >= w or j >= l or t[j * w + i] == 0:
			return
		h[j * w + i] = h[j * w + i] + up
		t[j * w + i] = 13

	## 从第 di 道门往里挖一段门洞（没开的门不挖 —— 那面墙就是实的）
	func throat(di: int, depth: int, ty := 2) -> void:
		if not is_open(di):
			return
		var d: Array = doors[di]
		var off := int(d[1])
		var hh := float(d[2])
		match str(d[0]):
			"N":
				rect(off, 0, off + 4, depth, ty, hh)
			"S":
				rect(off, l - depth, off + 4, l, ty, hh)
			"W":
				rect(0, off, depth, off + 4, ty, hh)
			"E":
				rect(w - depth, off, w, off + 4, ty, hh)

	func prop(kind: String, x: float, z: float, yaw := 0.0, arg := 1.0) -> void:
		props.append([kind, x, z, yaw, arg])

	func zone(x: float, z: float, r: float, n: int, elite := false) -> void:
		zones.append([x, z, r, n, elite])


## 画一间房。open[i] = 第 i 道门这局有没有接上别的房间
static func make(id: String, open: Array) -> Room:
	var r := Room.new()
	r.setup(id, DEFS[id], open)
	match id:
		"start":
			_start(r)
		"lane_a":
			_lane_a(r)
		"lane_turn":
			_lane_turn(r)
		"lane_stairs":
			_lane_stairs(r)
		"cross":
			_cross(r)
		"bamboo":
			_bamboo(r)
		"vista":
			_vista(r)
		"hall":
			_hall(r)
		"garden":
			_garden(r)
		"den":
			_den(r)
		"gate":
			_gate(r)
		"plaza":
			_plaza(r)
		"steles":
			_steles(r)
		"spring":
			_spring(r)
		"arena":
			_arena(r)
		"grove":
			_grove(r)
		"nook_chest":
			_nook_chest(r)
		"nook_shrine":
			_nook_shrine(r)
		"nook_pool":
			_nook_pool(r)
	return r


# ---------- 各间房 ----------

## 接引阵台：圆台 + 青玉环 + 中心接引阵（出生点）
static func _start(r: Room) -> void:
	r.disc(11, 11, 8.2, T_STONE)
	r.ring(11, 11, 4.3, 5.5, T_JADE)
	r.disc(11, 11, 3.2, T_GOLD)
	r.throat(0, 7)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		r.prop("lamp", 11.0 + s.x * 5.4, 11.0 + s.y * 5.4)
	r.prop("stele", 4.4, 11.0, PI * 0.5)
	r.prop("crystal", 11.0, 3.5, 0.0, 1.3)
	r.prop("crystal", 11.0, 18.5, 2.0, 1.1)
	r.prop("pine", 5.6, 5.6)
	r.prop("pine", 5.6, 16.4)
	r.prop("banner", 15.6, 8.3)
	r.prop("banner", 15.6, 13.7)


## 石径：一条直路，两侧石灯
static func _lane_a(r: Room) -> void:
	r.rect(2, 2, 6, 14, T_PATH)
	r.throat(0, 2)
	r.throat(1, 2)
	r.prop("lamp", 2.4, 4.5)
	r.prop("lamp", 5.6, 11.5)
	r.prop("rock", 5.5, 5.0, 0.7, 0.8)
	r.prop("bamboo", 2.5, 10.5)


## 回折径：拐一个直角，拐角处一小片草地
static func _lane_turn(r: Room) -> void:
	r.blob(7.0, 7.0, 3.6, T_GRASS, 0.0, 1.1)
	r.rect(2, 5, 9, 9, T_PATH)
	r.rect(5, 5, 9, 12, T_PATH)
	r.throat(0, 2)
	r.throat(1, 2)
	r.prop("maple", 9.3, 5.2)
	r.prop("lamp", 8.5, 8.6)
	r.prop("rock", 4.6, 9.6, 1.2, 0.9)


## 登云阶：一段上行的石阶（升 5 米）
static func _lane_stairs(r: Room) -> void:
	r.rect(2, 15, 6, 18, T_PATH, 0.0)
	for j in range(5, 15):
		r.rect(2, j, 6, j + 1, T_STONE, float(15 - j) * 0.5)
	r.rect(2, 2, 6, 5, T_PATH, 5.0)
	r.throat(0, 2)
	r.throat(1, 2)
	r.prop("lamp", 2.4, 15.6)
	r.prop("lamp", 5.6, 15.6)
	r.prop("lamp", 2.4, 4.4)
	r.prop("lamp", 5.6, 4.4)
	r.prop("banner", 2.3, 10.0)
	r.prop("banner", 5.7, 10.0)


## 四象路口：小圆台，四面都可能有路
static func _cross(r: Room) -> void:
	r.disc(7, 7, 4.7, T_STONE)
	r.ring(7, 7, 2.5, 3.4, T_JADE)
	for i in 4:
		r.throat(i, 3)
	r.prop("censer", 7.0, 7.0)
	r.prop("lamp", 3.9, 3.9)
	r.prop("lamp", 10.1, 10.1)
	r.zone(7.0, 7.0, 2.6, 2)


## 幽篁径：竹林里一条弯路，两处空地；南边一道备用门
static func _bamboo(r: Room) -> void:
	r.blob(8.0, 6.0, 4.6, T_GRASS, 0.0, 1.3)
	r.blob(19.0, 15.5, 5.0, T_GRASS, 0.0, 2.1)
	r.blob(13.0, 11.0, 3.4, T_MOSS, 0.0, 4.0)
	r.line(0, 6, 8, 6, 4.0, T_PATH)
	r.line(8, 6, 13, 12, 4.0, T_PATH)
	r.line(13, 12, 20, 16, 4.0, T_PATH)
	r.line(20, 16, 26, 16, 4.0, T_PATH)
	if r.is_open(2):
		r.line(18, 17, 18, 22, 4.0, T_PATH)
	r.throat(0, 2)
	r.throat(1, 2)
	r.throat(2, 2)
	for q: Vector2 in [Vector2(5.0, 3.2), Vector2(10.6, 3.4), Vector2(4.6, 9.0), Vector2(11.6, 8.0), Vector2(15.6, 9.6), Vector2(10.6, 13.4),
			Vector2(16.0, 18.6), Vector2(22.6, 12.6), Vector2(22.4, 19.0), Vector2(15.4, 14.6)]:
		r.prop("bamboo", q.x, q.y, q.x * 1.7)
	r.prop("lamp", 7.0, 8.2)
	r.prop("lamp", 20.5, 13.6)
	r.prop("chest", 8.0, 2.8)
	r.prop("rock", 17.5, 11.5, 0.4, 1.2)
	r.zone(13.0, 12.0, 3.0, 3)


## 断云台：云渊上的几座石台，栈桥相连。西门进、东南岛的南门出：正路走桥过中岛，也可以贴着南崖绕远；东北小岛上有东西；北、东各一道备用门
static func _vista(r: Room) -> void:
	r.ell(24, 20, 20.0, 15.5, T_VOID, VOID_H)
	r.disc(7, 20, 5.5, T_STONE)
	r.disc(24, 20, 7.5, T_STONE, 2.0)
	r.ring(24, 20, 4.6, 5.5, T_JADE, 2.0)
	r.disc(36.5, 9.5, 4.6, T_GRASS, 3.0)
	r.disc(37, 30, 5.0, T_GRASS)
	r.disc(42, 20, 4.6, T_STONE)
	r.line(11, 20, 18, 20, 2.2, T_WOOD, 0.0, 2.0)
	r.line(30, 20, 38.5, 20, 2.2, T_WOOD, 2.0, 0.0)
	r.line(27.5, 15.5, 34, 11.5, 2.2, T_WOOD, 2.0, 3.0)
	r.line(7, 24, 12, 33, 3.2, T_PATH)
	r.line(12, 33, 32, 34, 3.2, T_PATH)
	r.line(32, 34, 37, 31, 3.2, T_PATH)
	r.line(39.5, 26.5, 42, 23, 2.6, T_PATH)
	if r.is_open(2):
		r.line(32, 0, 32, 5, 4.0, T_PATH, 3.0, 3.0)
		r.line(32, 5, 35, 8, 3.2, T_PATH, 3.0, 3.0)
	r.throat(0, 3)
	r.throat(1, 6)
	r.throat(2, 2)
	r.throat(3, 3)
	r.prop("pavilion", 24.0, 20.0, 0.0, 1.25)
	r.prop("chest", 37.4, 8.4)
	r.prop("crystal", 34.6, 7.6, 1.0, 1.2)
	r.prop("pine", 35.0, 28.2)
	r.prop("pine", 39.6, 31.4)
	r.prop("pine", 5.0, 16.8)
	r.prop("lamp", 11.0, 18.6)
	r.prop("lamp", 11.0, 21.4)
	r.prop("lamp", 38.6, 18.6)
	r.prop("lamp", 38.6, 21.4)
	r.prop("stele", 43.6, 17.6, 0.6)
	r.prop("rock", 20.0, 34.4, 0.3, 1.1)
	r.zone(24.0, 22.5, 3.0, 4)
	r.zone(37.0, 30.0, 3.0, 3)
	r.zone(42.0, 20.0, 2.5, 2)


## 藏经残殿：殿内两排石柱、中间红毯、北侧高台。南门进、东门出（主路在殿里拐弯）；北门备用
static func _hall(r: Room) -> void:
	r.rect(3, 3, 27, 21, T_DARK)
	r.rect(9, 3, 21, 7, T_STONE, 1.0)
	r.rect(13, 3, 17, 21, T_RED)
	r.rect(13, 3, 17, 7, T_RED, 1.0)
	for px: int in [7, 11, 18, 22]:
		for pz: int in [9, 13, 17]:
			r.pillar(px, pz, 9.0)
	r.throat(0, 3)
	r.throat(1, 3)
	r.throat(2, 3)
	for pz2: int in [9, 13, 17]:
		r.prop("beam", 15.0, float(pz2) + 0.5, 0.0, 16.0)
	for z: float in [8.0, 11.0, 14.0, 17.0, 20.0]:
		r.prop("shelf", 3.7, z, PI * 0.5)
		if not r.is_open(1) or z < 9.0 or z > 15.0:
			r.prop("shelf", 26.3, z, -PI * 0.5)
	r.prop("chest", 10.4, 4.4)
	r.prop("chest", 19.6, 4.4)
	r.prop("brazier", 12.0, 19.2)
	r.prop("brazier", 18.0, 19.2)
	r.prop("altar", 15.0, 4.2)
	r.zone(15.0, 14.0, 4.0, 4)
	r.zone(22.0, 6.0, 2.4, 2)


## 灵药圃：歇脚的地方。四块药圃、十字路、中间水榭
static func _garden(r: Room) -> void:
	r.blob(13, 13, 10.2, T_GRASS, 0.0, 0.4)
	r.rect(11, 3, 15, 23, T_PATH)
	r.rect(3, 11, 23, 15, T_PATH)
	for q: Vector2i in [Vector2i(5, 5), Vector2i(17, 5), Vector2i(5, 17), Vector2i(17, 17)]:
		r.rect(q.x, q.y, q.x + 4, q.y + 4, T_SOIL, 0.5)
		for k in 4:
			r.prop("herb", float(q.x) + 1.0 + float(k % 2) * 2.0, float(q.y) + 1.0 + float(k >> 1) * 2.0, float(k), 1.0 + 0.2 * float(k % 3))
	r.ring(13, 13, 2.4, 4.6, T_STONE)
	r.disc(13, 13, 2.5, T_WATER, -1.0)
	for i in 4:
		r.throat(i, 3)
	r.prop("pavilion", 13.0, 13.0, 0.0, 1.1)
	r.prop("maple", 6.0, 11.0)
	r.prop("maple", 20.6, 15.6)
	r.prop("maple", 15.6, 6.0)
	r.prop("maple", 10.6, 20.4)
	r.prop("lamp", 10.6, 10.6)
	r.prop("lamp", 15.4, 15.4)
	r.prop("crystal", 20.4, 9.8, 0.5, 0.9)


## 剑傀阵：下沉的圆形斗场，一圈剑碑（实心），正中阵眼
static func _den(r: Room) -> void:
	r.disc(15, 15, 12.4, T_STONE)
	r.disc(15, 15, 10.4, T_DARK, -1.0)
	r.disc(15, 15, 8.6, T_DARK, -2.0)
	r.ring(15, 15, 5.6, 6.5, T_JADE, -2.0)
	r.disc(15, 15, 2.6, T_GOLD, -2.0)
	for k in 8:
		var a := (float(k) + 0.5) * TAU / 8.0
		r.pillar(int(floorf(15.0 + cos(a) * 9.5)), int(floorf(15.0 + sin(a) * 9.5)), 6.0)
	r.throat(0, 4)
	r.throat(1, 4)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		r.prop("brazier", 15.0 + s.x * 8.2, 15.0 + s.y * 8.2)
	r.prop("gsword", 26.2, 11.2, 0.3, 0.7)
	r.prop("gsword", 26.2, 18.8, -0.3, 0.7)
	r.zone(15.0, 15.0, 4.0, 5, true)


## 禁制关：两头小前厅，中间一道窄门（卡口）
static func _gate(r: Room) -> void:
	r.rect(2, 2, 10, 5, T_STONE)
	r.rect(2, 9, 10, 12, T_STONE)
	r.rect(4, 2, 8, 12, T_PATH)
	r.rect(4, 6, 8, 8, T_JADE)
	r.throat(0, 2)
	r.throat(1, 2)
	r.prop("sealgate", 6.0, 7.0)
	r.prop("brazier", 2.9, 3.4)
	r.prop("brazier", 9.1, 3.4)
	r.prop("brazier", 2.9, 10.6)
	r.prop("brazier", 9.1, 10.6)


## 镇剑坪：全关最大的一间。中央三层台 + 巨剑，东西向红毯，四角草坪和亭子，两排剑碑。西门进、北门出；南、东各一道备用门
static func _plaza(r: Room) -> void:
	r.rect(4, 4, 52, 44, T_STONE)
	for c: Vector2i in [Vector2i(4, 4), Vector2i(47, 4), Vector2i(4, 39), Vector2i(47, 39)]:
		r.rock(c.x, c.y, c.x + 5, c.y + 5)
	r.rect(10, 7, 22, 15, T_GRASS)
	r.rect(34, 7, 46, 15, T_GRASS)
	r.rect(10, 33, 22, 41, T_GRASS)
	r.rect(34, 33, 46, 41, T_GRASS)
	r.rect(26, 4, 30, 44, T_PATH)
	r.rect(4, 22, 52, 26, T_RED)
	r.rect(20, 16, 36, 32, T_STONE, 1.0)
	r.rect(22, 18, 34, 30, T_DARK, 2.0)
	r.rect(24, 20, 32, 28, T_JADE, 3.0)
	r.rect(27, 23, 29, 25, T_GOLD, 3.0)
	for px: int in [10, 14, 18, 38, 42, 46]:
		r.pillar(px, 20, 5.0)
		r.pillar(px, 27, 5.0)
	r.throat(0, 4, T_RED)
	r.throat(1, 4)
	r.throat(2, 4)
	r.throat(3, 4, T_RED)
	r.prop("gsword", 28.0, 24.0, 0.0, 1.9)
	for q: Vector2 in [Vector2(16, 11), Vector2(40, 11), Vector2(16, 37), Vector2(40, 37)]:
		r.prop("pavilion", q.x, q.y)
	for x: float in [8.0, 12.5, 16.5, 40.5, 44.5, 48.5]:
		r.prop("lamp", x, 21.4)
		r.prop("lamp", x, 26.6)
	r.prop("chest", 24.8, 20.8)
	r.prop("chest", 31.2, 27.2)
	r.prop("chest", 16.0, 9.0)
	r.prop("maple", 11.6, 8.4)
	r.prop("maple", 44.4, 8.4)
	r.prop("maple", 11.6, 39.6)
	r.prop("maple", 44.4, 39.6)
	r.prop("banner", 21.0, 16.6)
	r.prop("banner", 35.0, 16.6)
	r.prop("banner", 21.0, 31.4)
	r.prop("banner", 35.0, 31.4)
	r.zone(12.0, 24.0, 3.2, 3)
	r.zone(44.0, 24.0, 3.2, 3)
	r.zone(28.0, 10.0, 3.2, 3)
	r.zone(28.0, 38.0, 3.2, 3)
	r.zone(28.0, 21.5, 2.0, 1, true)


## 碑林：错开排的石碑（实心），穿行其间；南边一道备用门
static func _steles(r: Room) -> void:
	r.rect(2, 2, 22, 26, T_MOSS)
	r.blob(8, 10, 4.0, T_GRASS, 0.0, 0.9)
	r.blob(16, 19, 5.0, T_GRASS, 0.0, 2.7)
	for row in 5:
		var z := 5 + row * 4
		var x := 5 if row % 2 == 0 else 7
		while x < 21:
			r.pillar(x, z, 4.0 + float((x * 7 + z * 3) % 3))
			x += 4
	r.throat(0, 2)
	r.throat(1, 2)
	r.throat(2, 2)
	r.prop("chest", 20.4, 3.2)
	r.prop("lamp", 3.0, 9.4)
	r.prop("lamp", 21.0, 18.6)
	r.prop("crystal", 3.2, 24.6, 0.8, 1.0)
	r.zone(12.0, 15.0, 4.0, 4)


## 悬泉：西壁一道飞瀑落进水潭，潭里几块踏脚石。南门进、西门出，路贴着水潭南岸；北门备用
static func _spring(r: Room) -> void:
	r.blob(11, 13, 9.0, T_GRASS, 0.0, 3.3)
	r.line(11, 26, 16, 18, 3.6, T_PATH)
	r.line(16, 18, 16, 8, 3.6, T_PATH)
	if r.is_open(2):
		r.line(16, 8, 11, 0, 3.6, T_PATH)
	r.disc(9.5, 12.5, 5.0, T_WATER, -1.0)
	r.disc(9.5, 12.5, 1.3, T_STONE)
	r.disc(6.5, 10.0, 1.0, T_STONE)
	r.disc(12.5, 15.0, 1.0, T_STONE)
	if r.is_open(1):
		r.line(0, 18, 6, 18, 3.6, T_PATH)
		r.line(6, 18, 14, 19, 3.6, T_PATH)
	r.throat(0, 4)
	r.throat(1, 2)
	r.throat(2, 4)
	r.prop("waterfall", 3.3, 11.0, PI * 0.5)
	r.prop("crystal", 5.4, 16.4, 0.3, 1.2)
	r.prop("crystal", 12.6, 8.6, 1.9, 0.9)
	r.prop("pine", 18.6, 5.0)
	r.prop("pine", 18.4, 21.4)
	r.prop("lamp", 14.2, 19.6)
	r.prop("chest", 9.5, 12.5)
	r.zone(15.5, 13.0, 3.0, 3)


## 剑冢：终点。圆形斗场、外圈高一级的走道、一圈插在地上的巨剑、正中祭台；北侧走道上是撤离阵
static func _arena(r: Room) -> void:
	r.disc(22, 22, 19.6, T_STONE, 1.0)
	r.disc(22, 22, 17.4, T_DARK)
	r.ring(22, 22, 11.6, 12.5, T_JADE)
	r.disc(22, 22, 4.4, T_STONE, 1.0)
	r.disc(22, 22, 2.4, T_GOLD, 1.0)
	r.disc(22, 4.6, 2.4, T_GOLD, 1.0)
	r.throat(0, 4)
	for k in 12:
		if k == 3 or k == 9:
			continue
		var a := float(k) * TAU / 12.0
		r.prop("gsword", 22.0 + cos(a) * 18.6, 22.0 + sin(a) * 18.6, a, 1.0 + 0.25 * float(k % 3))
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		r.prop("brazier", 22.0 + s.x * 9.0, 22.0 + s.y * 9.0)
	r.prop("extract", 22.0, 4.6)
	r.prop("banner", 19.4, 40.6)
	r.prop("banner", 24.6, 40.6)
	r.zone(22.0, 22.0, 3.0, 1, true)
	r.zone(13.0, 22.0, 3.0, 3)
	r.zone(31.0, 22.0, 3.0, 3)


## 枫林（支线）：一片枫树下的空地
static func _grove(r: Room) -> void:
	r.blob(9, 9, 6.8, T_GRASS, 0.0, 6.0)
	r.rect(7, 4, 11, 14, T_PATH)
	r.throat(0, 4)
	r.throat(1, 4)
	for q: Vector2 in [Vector2(4.6, 6.0), Vector2(13.4, 6.4), Vector2(4.4, 12.0), Vector2(13.6, 12.4), Vector2(6.0, 3.8), Vector2(12.6, 14.6)]:
		r.prop("maple", q.x, q.y, q.x)
	r.prop("rock", 12.4, 9.0, 0.9, 1.0)
	r.zone(9.0, 9.0, 3.4, 3)


## 藏宝龛（死胡同）：一只灵匣
static func _nook_chest(r: Room) -> void:
	r.disc(5, 4.6, 3.4, T_STONE)
	r.ring(5, 4.6, 2.2, 3.0, T_JADE)
	r.throat(0, 3)
	r.prop("chest", 5.0, 3.6)
	r.prop("lamp", 2.8, 3.4)
	r.prop("lamp", 7.2, 3.4)
	r.prop("crystal", 5.0, 1.7, 0.2, 0.9)


## 残祠（死胡同）：小祭台，有守着的
static func _nook_shrine(r: Room) -> void:
	r.rect(2, 2, 10, 9, T_DARK)
	r.rect(4, 2, 8, 4, T_STONE, 1.0)
	r.throat(0, 3)
	r.prop("altar", 6.0, 3.0)
	r.prop("chest", 8.8, 6.6)
	r.prop("brazier", 3.0, 3.0)
	r.prop("brazier", 9.0, 3.0)
	r.zone(6.0, 6.5, 2.0, 2)


## 灵眼（死胡同）：一汪发光的灵泉
static func _nook_pool(r: Room) -> void:
	r.blob(5, 5.4, 3.6, T_GRASS, 0.0, 5.0)
	r.disc(5, 4.8, 1.7, T_JADE)
	r.throat(0, 3)
	r.prop("crystal", 3.0, 3.4, 0.4, 1.3)
	r.prop("crystal", 7.0, 3.6, 2.2, 1.1)
	r.prop("herb", 4.0, 7.0, 0.0, 1.3)
	r.prop("herb", 6.2, 7.2, 1.0, 1.2)
	r.prop("chest", 5.0, 4.8)
