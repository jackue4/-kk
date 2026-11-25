extends RefCounted
## 主城两侧的擂台（2026-11-23，用户给的参考图：主岛左右各伸出一块，上面一座抬高的八角擂台）。
## 西「白虎擂」、东「青龙擂」，各自：
##   · 主岛往外伸出的一块草地（和主岛连成一片，南边留一道海湾）
##   · 三米高的八角石台，对边 80 米（主城中心广场是 60 米；2026-11-23 第二轮用户要求「擂台区域再大一点」，原来 60 米）——
##     1v1 切磋就在台面上打（arena_duel.gd）
##   · 台面：暖粉色石板 + 外圈镶边；金色的纹（八角线、两道圆环、八道辐条、莲心）是抬高十厘米左右的薄方块，不是贴在台面上的面片
##   · 一圈石栏，八个角各一根顶着灯笼的石柱；朝中心广场一道铺红毯的石阶（接一条石路到北面石阶前），朝南一道石阶下到草地
##   · 背对广场那一侧立一座大牌坊，两边各两面红幡；石阶脚下一对火盆
## 只管样子和站位（高度表、实心格）；匹配和对决在 arena_duel.gd。全部并进主城的两张静态网格（hub_hall.gd 的 _g / _a），不多一次绘制调用。
## 不闪面（z-fighting）的规矩，照着写的：
##   · 不同颜色的两个面不共面：叠在别的面上的东西至少高出 6 厘米（手机 / 网页的深度只有 24 位，隔几毫米在几十米外就分不开）
##   · 同色的可以共面（看不出）；方块的底面本来就不画
##   · 台面的花纹宁可用薄方块垫高，也不在同一高度上叠面片
## hub_hall.gd 里的接法：_layout 末尾 layout()、_top_col 开头 top_col()、_side_col 开头 side_col()、_build_structures 末尾 build()、云团避开 over()。
## 故意不 preload hub_hall.gd（它 preload 这个文件，互相引用会编不过）：hub 参数不标类型，直接调它的 _rect / _b / _block 这些。

const CX := 122.0              # 擂台中心离主城中线多远（西 -CX，东 +CX）；石阶脚下落在主岛东 / 西沿（x = ±72）
const CZ := -28.0
const R := 40.0                # 八角台的边心距（对边 80 米）
const H := 3.0                 # 台面高
const RP := 38.9               # 石栏中线的边心距
const RO := 32.0               # 台面上那道金色八角线
const T_GRASS := 1
const T_PAVE := 2
const T_STONE := 5
const T_ARENA := 7             # 台面
const T_CARPET := 8            # 石阶上的红毯
const STAIR_HALF := 6.0        # 石阶半宽（两边各 2 米是石栏那一列，中间 8 米红毯）
const CARPET_HALF := 4.0
const STEPS := 5               # 半米一级、一级两米深（和北面石阶一样）
const LOBE_RX := 50.0
const LOBE_RZ := 54.0
const RING_OUT := 21.0         # 台面上外圈那道金环的半径（内圈 RING_IN）
const RING_IN := 11.0
const GOLD := Color(0.95, 0.74, 0.36)
const ArenaFloor := preload("res://scripts/arena_floor.gd")     # 2026-11-25 场景破坏：台面能真碎
const R_BREAK := R - 6.0       # 离台心这么远以内的台面格子能碎（台沿一圈：石栏、石阶口不碎）
const NAMES := ["白虎擂", "青龙擂"]


static func oct_d(lx: float, lz: float) -> float:
	return maxf(maxf(absf(lx), absf(lz)), (absf(lx) + absf(lz)) * 0.70710678)


## (x, z) 在不在擂台那块岛的上空（云团别摆进来）。margin = 往外再让多少米
static func over(x: float, z: float, margin := 22.0) -> bool:
	return pow(absf(absf(x) - CX) / (LOBE_RX + margin), 4.0) + pow(absf(z - CZ) / (LOBE_RZ + margin), 4.0) < 1.0


## 第 side 座（0 西 / 1 东）台面中心
static func center(side: int) -> Vector3:
	return Vector3(-CX if side == 0 else CX, H, CZ)


## 站在台面上吗（以后接玩法用）：返回 -1 / 0 西 / 1 东
static func arena_at(x: float, z: float) -> int:
	if oct_d(absf(x) - CX, z - CZ) > R - 2.0:
		return -1
	return 0 if x < 0.0 else 1


# ---------- 高度表 ----------

static func layout(hub) -> void:
	var n: int = hub.N
	var hn: int = hub.HN
	for s: float in [-1.0, 1.0]:
		var cx := s * CX
		for j in n:
			for i in n:
				var x := (float(i - hn) + 0.5) * 2.0
				var z := (float(j - hn) + 0.5) * 2.0
				var lx := x - cx
				var lz := z - CZ
				if float(hub._h[j * n + i]) < -900.0:
					# 伸出去的那块地（超椭圆，边沿参差一点）+ 和主岛之间的一段
					var k := pow(absf(lx) / LOBE_RX, 4.0) + pow(absf(lz) / LOBE_RZ, 4.0)
					var neck := x * s > 60.0 and x * s < CX - R + 4.0 and z > -58.0 and z < 8.0
					if k < 0.96 + (float(hub._hash(i, j)) - 0.5) * 0.06 or neck:
						hub._put(i, j, T_GRASS, 0.0)
				if oct_d(lx, lz) <= R:
					hub._put(i, j, T_ARENA, H)
		for k in STEPS:
			var hk := H - 0.5 * float(k + 1)
			# 朝中心广场那道
			var xa := cx - s * (R + 2.0 * float(k))
			var xb := xa - s * 2.0
			var x0 := minf(xa, xb)
			var x1 := maxf(xa, xb)
			hub._rect(x0, CZ - STAIR_HALF, x1, CZ + STAIR_HALF, T_STONE, hk, false)
			hub._rect(x0, CZ - CARPET_HALF, x1, CZ + CARPET_HALF, T_CARPET, hk, false)
			# 朝南那道
			var za := CZ + R + 2.0 * float(k)
			hub._rect(cx - STAIR_HALF, za, cx + STAIR_HALF, za + 2.0, T_STONE, hk, false)
			hub._rect(cx - CARPET_HALF, za, cx + CARPET_HALF, za + 2.0, T_CARPET, hk, false)
			# 石阶两边那一列上是一级级落下去的石栏：实心
			for sg: float in [-1.0, 1.0]:
				hub._block(x0 + 0.1, CZ + sg * (STAIR_HALF - 1.0) - 0.9, x1 - 0.1, CZ + sg * (STAIR_HALF - 1.0) + 0.9, hk + 1.4)
				hub._block(cx + sg * (STAIR_HALF - 1.0) - 0.9, za + 0.1, cx + sg * (STAIR_HALF - 1.0) + 0.9, za + 1.9, hk + 1.4)
		# 石路：从石阶脚下往广场走，接到北面石阶前那条横路；南面石阶脚下一小片铺地
		var foot := cx - s * (R + 2.0 * float(STEPS))
		hub._rect(minf(foot, s * 24.0), CZ - 4.0, maxf(foot, s * 24.0), CZ + 4.0, T_PAVE, 0.0)
		hub._rect(cx - 8.0, CZ + R + 2.0 * float(STEPS), cx + 8.0, CZ + R + 2.0 * float(STEPS) + 4.0, T_PAVE, 0.0)


# ---------- 颜色 ----------

static func top_col(type: int, i: int, j: int, x: float, z: float, hs: float) -> Color:
	var s := 1.0 if x > 0.0 else -1.0
	var lx := x - s * CX
	var lz := z - CZ
	if type == T_CARPET:
		# 红毯：一级深一级浅
		var step := int(floorf((maxf(absf(lx), absf(lz)) - R) * 0.5))
		return (Color(0.76, 0.19, 0.16) if step % 2 == 0 else Color(0.69, 0.16, 0.15)) * (0.97 + 0.06 * hs)
	var d := oct_d(lx, lz)
	var r := sqrt(lx * lx + lz * lz)
	var chk := (i + j) % 2 == 0
	var c := Color(0.93, 0.84, 0.75) if chk else Color(0.88, 0.78, 0.71)
	if d > R - 4.0:
		c = Color(0.74, 0.67, 0.72) if chk else Color(0.67, 0.61, 0.68)      # 外圈镶边：灰紫的石
	elif r < RING_IN + 1.0:
		c = Color(0.97, 0.89, 0.79) if chk else Color(0.94, 0.85, 0.77)      # 莲心那一圈亮一点
	elif r > RING_OUT + 0.6 and d < RO:
		c = Color(0.91, 0.79, 0.73) if chk else Color(0.86, 0.73, 0.70)      # 圆环和八角线之间：偏玫瑰色
	return c * (0.97 + 0.06 * hs)


## 侧壁：红毯的竖面也是红的；台子的侧壁上沿一道镶边石、往下是暖灰的砌石
static func side_col(type: int, depth: float, hs: float) -> Color:
	if type == T_CARPET:
		return Color(0.58, 0.14, 0.13) * (0.95 + 0.08 * hs)
	if depth < 0.7:
		return Color(0.70, 0.64, 0.70)
	return Color(0.72, 0.68, 0.68).lerp(Color(0.52, 0.50, 0.58), clampf(depth / 16.0, 0.0, 1.0)) * (0.94 + 0.1 * hs)


# ---------- 建筑和点缀 ----------

static func build(hub) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	var inlay_rg: Array = []       # 金纹方块在点缀网格里占的那几段顶点（台面碎的时候跟着收掉，见 arena_floor.gd）
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var c := Vector3(s * CX, H, CZ)
		_fence(hub, c, s)
		var in0 := (hub._a[0] as PackedVector3Array).size()
		_inlay(hub, c)
		inlay_rg.append([in0, (hub._a[0] as PackedVector3Array).size()])
		_stairs(hub, c, s)
		_gate(hub, c, s, side)
		_scenery(hub, c, s, rng)
		# 岛根：往下收小的几层石头
		for k in 4:
			var w := 92.0 - 19.0 * float(k)
			hub._b(Vector3(w, 9.0, w * 1.08), Vector3(c.x, -22.0 - 8.0 * float(k), CZ), Color(0.50, 0.49, 0.56) * (1.0 - 0.07 * float(k)), 0.3 * float(k) + 0.4 * s, 0.0, 0.8)
	# 2026-11-25 场景破坏：台面能真碎。这时地面的网格数组已经拼好（_mesh_ground 在前）、还没交给显卡：记下每一格顶面在哪
	var fl: Node3D = ArenaFloor.new()
	fl.call("setup", hub, H, CX, CZ, R_BREAK, inlay_rg,
			func(i: int, j: int, x: float, z: float) -> Color: return top_col(T_ARENA, i, j, x, z, float(hub._hash(i * 3 + 1, j * 5 + 2))))
	(hub._root as Node).add_child(fl)


## 八角形第 m 条边（外法线朝 m × 45°，0 = +x，2 = +z 朝南）的两个端点，边心距 ap
static func _side_pts(c: Vector3, m: int, ap: float) -> Array:
	var rv := ap / cos(PI / 8.0)
	var a0 := PI / 4.0 * float(m) - PI / 8.0
	var a1 := a0 + PI / 4.0
	return [c + Vector3(cos(a0) * rv, 0.0, sin(a0) * rv), c + Vector3(cos(a1) * rv, 0.0, sin(a1) * rv)]


## 一段石栏（矮墙 + 压顶 + 墩子），两头各缩 0.6 米（接在角柱里）；沿线登记实心格
static func _rail(hub, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len0 := d.length()
	if len0 < 1.6:
		return
	var dir := d / len0
	a += dir * 0.6
	b -= dir * 0.6
	var length := len0 - 1.2
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5
	hub._b(Vector3(0.8, 1.1, length), mid + Vector3(0.0, 0.55, 0.0), Color(0.80, 0.76, 0.75), yaw)
	hub._b(Vector3(1.04, 0.26, length), mid + Vector3(0.0, 1.2, 0.0), Color(0.90, 0.86, 0.83), yaw)
	var n := maxi(int(roundf(length / 4.0)), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		hub._b(Vector3(1.16, 1.75, 1.16), p + Vector3(0.0, 0.875, 0.0), Color(0.72, 0.68, 0.70), yaw)
		hub._b(Vector3(0.7, 0.3, 0.7), p + Vector3(0.0, 1.9, 0.0), Color(0.62, 0.24, 0.18), yaw)
	var steps := int(ceilf(len0))
	for i in steps + 1:
		var q := (a - dir * 0.6).lerp(b + dir * 0.6, float(i) / float(steps))
		hub._block(q.x - 0.05, q.z - 0.05, q.x + 0.05, q.z + 0.05, a.y + 1.4)


static func _fence(hub, c: Vector3, s: float) -> void:
	var tile := Color(0.27, 0.26, 0.33)
	var inner := 4 if s > 0.0 else 0        # 朝中心广场的那条边
	for m in 8:
		var e: Array = _side_pts(c, m, RP)
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		if m == inner or m == 2:
			# 石阶口：中间空出 2 × STAIR_HALF
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_rail(hub, a, mid - dir * (STAIR_HALF - 0.2))
			_rail(hub, mid + dir * (STAIR_HALF - 0.2), b)
		else:
			_rail(hub, a, b)
		# 角上的灯柱：石柱、深色的檐、一盏灯、一顶小瓦顶
		hub._b(Vector3(1.6, 3.6, 1.6), b + Vector3(0.0, 1.8, 0.0), Color(0.76, 0.72, 0.72))
		hub._b(Vector3(2.0, 0.5, 2.0), b + Vector3(0.0, 0.25, 0.0), Color(0.62, 0.58, 0.62))
		hub._b(Vector3(2.1, 0.4, 2.1), b + Vector3(0.0, 3.8, 0.0), Color(0.34, 0.32, 0.38))
		hub._b(Vector3(1.2, 1.2, 1.2), b + Vector3(0.0, 4.6, 0.0), Color(1.0, 0.84, 0.48), 0.0, 0.75, 0.96)
		hub._bw._roof(hub._a, b + Vector3(0.0, 5.2, 0.0), 1.6, 1.6, 0.0, tile)
		hub._block(b.x - 0.8, b.z - 0.8, b.x + 0.8, b.z + 0.8, c.y + 5.0)


## 台面上的金纹：都是薄方块（垫高 10 厘米上下），同色的才互相叠
static func _inlay(hub, c: Vector3) -> void:
	var em := 0.14
	# 八角线
	for m in 8:
		var e: Array = _side_pts(c, m, RO)
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var d := b - a
		hub._b(Vector3(0.6, 0.10, d.length() + 0.5), (a + b) * 0.5 + Vector3(0.0, 0.05, 0.0), GOLD, atan2(d.x, d.z), em, 1.0)
	# 两道圆环
	for ring: Array in [[RING_OUT, 26], [RING_IN, 16]]:
		var rr := float(ring[0])
		var seg := int(ring[1])
		for i in seg:
			var ang := TAU * (float(i) + 0.5) / float(seg)
			hub._b(Vector3(0.5, 0.10, 2.0 * rr * sin(PI / float(seg)) + 0.3), c + Vector3(cos(ang) * rr, 0.05, sin(ang) * rr), GOLD, -ang, em, 1.0)
	# 八道辐条：从外圆环指向八角线的八个角（两头都不搭到环上）
	for m in 8:
		var ang := PI / 4.0 * float(m) + PI / 8.0
		var r0 := RING_OUT + 0.8
		var r1 := RO / cos(PI / 8.0) - 0.9
		hub._b(Vector3(0.5, 0.10, r1 - r0), c + Vector3(cos(ang), 0.0, sin(ang)) * ((r0 + r1) * 0.5) + Vector3(0.0, 0.05, 0.0), GOLD, atan2(cos(ang), sin(ang)), em, 1.0)
	# 莲心：八瓣（粉的菱形，上面一块小一号的金菱形），正中两层贴地的八角薄片
	# （原来是半米高的小台，只是摆设、没登记高度，人站上去脚会陷进去；现在台面上要打架，压成十几厘米）
	for m in 8:
		var ang := PI / 4.0 * float(m)
		var p := c + Vector3(cos(ang), 0.0, sin(ang)) * 6.2
		var yaw := atan2(cos(ang), sin(ang)) + PI * 0.25
		hub._b(Vector3(2.9, 0.16, 2.9), p + Vector3(0.0, 0.08, 0.0), Color(1.0, 0.72, 0.66), yaw, 0.12, 1.0)
		hub._b(Vector3(1.5, 0.26, 1.5), p + Vector3(0.0, 0.13, 0.0), GOLD, yaw, em, 1.0)
	for k in 2:
		hub._b(Vector3(5.2, 0.12, 5.2), c + Vector3(0.0, 0.06, 0.0), Color(0.86, 0.80, 0.80), PI * 0.25 * float(k), 0.0, 1.0)
		hub._b(Vector3(3.1, 0.2, 3.1), c + Vector3(0.0, 0.1, 0.0), GOLD, PI * 0.25 * float(k), em, 1.0)


static func _stairs(hub, c: Vector3, s: float) -> void:
	var st := Color(0.78, 0.74, 0.73)
	var cap := Color(0.90, 0.86, 0.83)
	for k in STEPS:
		var hk := H - 0.5 * float(k + 1)
		var xm := c.x - s * (R + 2.0 * float(k) + 1.0)
		var zm := CZ + R + 2.0 * float(k) + 1.0
		for sg: float in [-1.0, 1.0]:
			# 一级级落下去的石栏（石阶两边那一列的外半边），红毯两边各一道金边
			hub._b(Vector3(2.0, 1.2, 0.9), Vector3(xm, hk + 0.6, CZ + sg * (STAIR_HALF - 0.5)), st)
			hub._b(Vector3(2.0, 0.22, 1.1), Vector3(xm, hk + 1.31, CZ + sg * (STAIR_HALF - 0.5)), cap)
			hub._b(Vector3(2.0, 0.08, 0.34), Vector3(xm, hk + 0.04, CZ + sg * (CARPET_HALF - 0.17)), GOLD, 0.0, 0.14, 1.0)
			hub._b(Vector3(0.9, 1.2, 2.0), Vector3(c.x + sg * (STAIR_HALF - 0.5), hk + 0.6, zm), st)
			hub._b(Vector3(1.1, 0.22, 2.0), Vector3(c.x + sg * (STAIR_HALF - 0.5), hk + 1.31, zm), cap)
			hub._b(Vector3(0.34, 0.08, 2.0), Vector3(c.x + sg * (CARPET_HALF - 0.17), hk + 0.04, zm), GOLD, 0.0, 0.14, 1.0)
	# 石阶脚下：一对火盆（站在石阶口两侧的草地上）
	var fx := c.x - s * (R + 2.0 * float(STEPS) + 1.6)
	var fz := CZ + R + 2.0 * float(STEPS) + 1.6
	for sg: float in [-1.0, 1.0]:
		for p: Vector3 in [Vector3(fx, 0.0, CZ + sg * (STAIR_HALF + 1.6)), Vector3(c.x + sg * (STAIR_HALF + 1.6), 0.0, fz)]:
			hub._bw._brazier(hub._a, p, Color(0.66, 0.63, 0.66))
			hub._block(p.x - 1.0, p.z - 1.0, p.x + 1.0, p.z + 1.0, 2.6)


## 背对广场那一侧：一座放大的牌坊（两面写着擂台的名字），两边各两面红幡
static func _gate(hub, c: Vector3, s: float, side: int) -> void:
	var base := c + Vector3(s * (R - 5.0), 0.0, 0.0)
	var start: int = (hub._a[0] as PackedVector3Array).size()
	hub._bw._paifang(hub._a, base, PI * 0.5, 6)
	hub._bw._scale_from(hub._a, start, base, 1.5)
	for sg: float in [-1.0, 1.0]:
		hub._block(base.x - 1.3, base.z + sg * 5.55 - 1.3, base.x + 1.3, base.z + sg * 5.55 + 1.3, H + 13.0)
		for q in 2:
			var bp := base + Vector3(0.0, 0.0, sg * (10.5 + 5.0 * float(q)))
			hub._b(Vector3(1.3, 0.6, 1.3), bp + Vector3(0.0, 0.3, 0.0), Color(0.62, 0.58, 0.62))
			hub._bw._banner(hub._a, bp + Vector3(0.0, 0.5, 0.0), 1.25, PI * 0.5 if sg < 0.0 else -PI * 0.5, Color(0.78, 0.18, 0.15))
			# 幡上的金纹：比幡面厚，两面各鼓出 6 厘米
			hub._b(Vector3(0.26, 1.0, 1.0), bp + Vector3(0.0, 0.5 + 8.75 - 2.0, sg * 1.375), GOLD, 0.0, 0.18, 1.0)
			hub._block(bp.x - 0.6, bp.z - 0.6, bp.x + 0.6, bp.z + 0.6, H + 2.0)
	var font: Font = hub.font
	if font != null:
		for face: float in [-1.0, 1.0]:
			var l := Label3D.new()
			l.text = NAMES[side]
			l.font = font
			l.font_size = hub.PLAQUE_FS          # 2026-11-24 和主城牌匾共用一套字库贴图（原来 120 号单独占一套 1024²，见 hub_hall.gd 的 PLAQUE_FS）
			l.pixel_size = 1.95 * 0.62 / float(hub.PLAQUE_FS)
			l.modulate = Color(0.24, 0.14, 0.08)
			l.outline_size = 0
			l.double_sided = false
			l.position = base + Vector3(face * 0.42, 8.05 * 1.5, 0.0)
			l.rotation.y = PI * 0.5 * face
			hub._root.add_child(l)


## 那块草地上的树、花、石灯；石路两边的灯
static func _scenery(hub, c: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	for t: Array in [[-35.0, 38.0, 1], [36.0, 37.0, 1], [-36.0, -39.0, 2], [35.0, -40.0, 1], [-46.0, 11.0, 2], [46.0, -9.0, 1], [15.0, 48.5, 2], [-14.0, 49.0, 1],
			[-45.5, -13.0, 1], [45.0, 14.0, 2]]:
		var x := c.x + float(t[0])
		var z := CZ + float(t[1])
		if bool(hub._free_spot(x, z)):
			hub._bw._blossom(hub._a, Vector3(x, 0.0, z), rng.randf_range(1.05, 1.35), rng, int(t[2]))
			hub._block(x - 0.6, z - 0.6, x + 0.6, z + 0.6, 3.0)
	for q in 12:
		var ang := rng.randf() * TAU
		var x2 := c.x + cos(ang) * rng.randf_range(44.0, 48.0)
		var z2 := CZ + sin(ang) * rng.randf_range(45.0, 51.0)
		if bool(hub._free_spot(x2, z2)):
			if q % 3 == 0:
				hub._bw._bush(hub._a, Vector3(x2, 0.0, z2), rng.randf_range(0.8, 1.2), Color(0.34, 0.60, 0.26) * rng.randf_range(0.9, 1.15), rng)
			else:
				hub._flowers(x2, z2, 0.0, rng, 5, 1.8)
	# 石路两边的石灯（北边一排整的；南边贴着商店 / 仓库的那一段不摆）
	for lx: float in [32.0, 44.0, 56.0, 68.0]:
		hub._lamp(s * lx, CZ - 5.0)
	for lx: float in [32.0, 40.0, 68.0]:
		hub._lamp(s * lx, CZ + 5.0)
	for sg: float in [-1.0, 1.0]:
		hub._lamp(c.x + sg * 9.0, CZ + R + 2.0 * float(STEPS) + 5.0)
