extends RefCounted
## 场景破坏（2026-11-25，TSB 式 PvP 重做）：打斗真的把场景打坏 —— 砸地成坑、把人打进墙里墙就塌、大招犁出一道沟、碎块满天飞、残骸留在地上。
## 全是 static，任何关卡里调都安全；关卡不支持真破坏时退成「只叠表现」（翻起一圈石板 + 碎块），什么都没接上时静默不做。
##
## 接口（战斗脚本只调这几个）：
##   Destruct.blast(pos, radius, power, dir, opts) -> bool   球形爆破：地形削出碗形坑、半径内能坏的方块打碎 / 切开、碎块顺着 dir 飞、扬尘、留残骸。
##                                                            返回有没有真的打坏东西。opts：remote（别人那边同步来的，不再广播）、quiet（只改场景不放表现）、
##                                                            depth_k（坑深的系数，默认 1；撞墙那种只想打墙的给小一点）、hook（Vfx.quake 进来的：表现减半）
##   Destruct.trench(from, to, width, power)                 沿线犁一道沟（觉醒大招的拳劲 / 剑气）：沿途的方块打碎。分帧做，沟是一路犁过去的
##   Destruct.body_crash(pos, vel, body_r) -> bool           有人被打飞撞上墙 / 地面：按速度砸出洞或坑。true = 撞穿了（调用方让人接着飞），
##                                                            false = 没穿（按原来的撞墙 / 坠地处理）
## 另外 Vfx.terrain_hook（vfx.gd 的 quake()：现有的砸地 / 击飞 / 坠地追击都会调）在新图里接到 blast 上，那些招式不用改就有真坑。
##
## 三种关卡：
##   1 新图（沙海古墟 / 天工秘所，scripts/ex/grid_world.gd）：真破坏。地形 = 破坏表 + 分块重排；方块 = 小的整个打碎、大的按爆点切开，
##     打坏过的地块摆件另起一张网格。出生 / 撤离 / 箱子 / 钥匙房 / 首领场地 / 祭坛 / 洞口 / 门周围不坏（zones_of）
##   2 老大世界（meadow_level.gd）：还是它自己那套炸坑（terrain_blast），这里只是转过去、补一把碎块
##   3 别的（主城 / 试剑台 / 剑冢）：地面是整张静态网格，挖不了 —— 只叠表现（destruct_fx.gd 的 rim）。
##     例外：主城两侧的擂台台面能真碎（scripts/arena_floor.gd：把那一格的顶面收掉、底下露出现拼的坑，30 秒后自己复原），
##     Vfx.quake 在擂台上也接过来了；真人对打时走擂台自己的联机节点（arena_net.gd）同步
## 联机（新图）：谁打坏的谁广播一条操作（net.gd 末尾的 dx_send / _dx），各机照同一套规则各自算；房主记着这间房的操作，
##   中途加入的人进图后要一次、按顺序重放（_dx_sync）。同一处连着炸的结果是幂等的（坑按「爆点 + 半径」定深，不累加）。
## 关卡这边：进图时 Destruct.attach(level)、退图时 Destruct.detach(level)（ex_level.gd / meadow_level.gd 已接）。
## 故意不写 class_name：用 preload 引用。

const Fx := preload("res://scripts/destruct_fx.gd")
const GridWorld := preload("res://scripts/ex/grid_world.gd")

const R_MAX := 8.0              # 一次爆破最大半径（各机一样大：手机档只少放碎块，坑不能比别人小，否则联机两边对不上）
const MERGE_T := 0.2            # 这么短的时间里同一处再炸：并掉
const CRASH_MIN := 10.0         # 撞上去不到这个速度：不算
const PIERCE_SPD := 20.0        # 撞墙超过这个速度：撞穿
const TRENCH_MAX := 64.0
const SHALLOW := 0.3            # 「浅坑」那一档的坑深系数

static var on := not OS.get_cmdline_user_args().has("--no-destruct")     # 总开关（对照 / 排查用：命令行加 --no-destruct = 回到「不破坏场景」）
static var stat := {"blasts": 0, "trenches": 0, "crashes": 0, "pierced": 0, "merged": 0, "remote": 0, "cells": 0, "boxes": 0, "last_ms": 0.0, "max_ms": 0.0}
static var _stack: Array = []   # [[关卡, opts], ...]：后接的在上面，撤掉以后回到前一个
static var _lv: Node = null
static var _world: GridWorld = null
static var _net: Node = null
static var _mode := 3
static var _fx: Fx = null
static var _floor := Callable()
static var _tiles: Node = null  # 模式 3 下：有「能碎的台面」的关卡（arena_floor.gd，dx_tiles(pos, r) -> {cells, y, cols}）
static var _hooked := false
static var _recent: Array = []  # [位置, 半径, 毫秒, 结果]
## 自检用：log_on 开着时把本机做的每一条操作记进 ops（[kind, a, b, r, power]，和联机广播的一样），replay_on 拿去在另一个世界上重放
static var log_on := false
static var ops: Array = []


# ---------- 接关卡 ----------

## 进图：这一关接上。opts：net（联机节点，缺省取 level.net）、floor（只叠表现的关卡给：func(x, z, y) -> 脚下多高）
static func attach(level: Node, opts := {}) -> void:
	if level == null:
		return
	for e: Array in _stack:
		if is_instance_valid(e[0]) and e[0] == level:
			return
	_stack.append([level, opts])
	_use(level, opts)
	_sync_in()


static func detach(level: Node) -> void:
	for i in range(_stack.size() - 1, -1, -1):
		var l: Variant = (_stack[i] as Array)[0]
		if not is_instance_valid(l) or l == level:
			_stack.remove_at(i)
	if _lv == null or not is_instance_valid(_lv) or _lv == level:
		if _stack.is_empty():
			_use(null, {})
		else:
			var top: Array = _stack.back()
			_use(top[0], top[1])


static func _use(level: Node, opts: Dictionary) -> void:
	if _hooked:
		Vfx.terrain_hook = Callable()
		_hooked = false
	_lv = level
	_world = null
	_tiles = null
	_net = null
	_floor = Callable()
	_mode = 3
	_recent.clear()
	var wm: Material = null
	if level != null:
		fx()          # 进图就把碎块那张网格建好（材质头一回用要现编，赶在载入黑场里）
		var nv: Variant = opts.get("net", level.get("net"))
		_net = nv as Node if nv != null and is_instance_valid(nv) else null
		var w: Variant = level.get("world")
		if w != null and is_instance_valid(w) and w is GridWorld:
			_mode = 1
			_world = w
			_world.dx_zones = zones_of(level)
			_floor = Callable(level, "floor_at")
			wm = _world.mat
			Vfx.terrain_hook = func(p: Vector3, r: float) -> bool: return blast(p, r, 1.0, Vector3.ZERO, {"hook": true})
			_hooked = true
		elif level.has_method("terrain_blast"):
			_mode = 2
			if w != null and is_instance_valid(w):
				var wn: Node = w
				_floor = func(x: float, z: float, _y: float) -> float: return float(wn.call("height", x, z)) if is_instance_valid(wn) else 0.0
				wm = wn.get("mat") as Material
		else:
			_floor = opts.get("floor", Callable())
			if level.has_method("dx_tiles"):
				_tiles = level
				Vfx.terrain_hook = func(p: Vector3, r: float) -> bool: return blast(p, r, 1.0, Vector3.ZERO, {"hook": true})
				_hooked = true
	if _fx != null and is_instance_valid(_fx):
		_fx.clear()
		_fx.floor_fn = _floor if _floor.is_valid() else Callable(_auto_floor)
		_fx.set_material(wm)


## 现在是哪一种：1 真破坏（新图）/ 2 老大世界 / 3 只叠表现
static func mode() -> int:
	return _mode if _lv != null and is_instance_valid(_lv) else 3


static func fx() -> Fx:
	if _fx != null and is_instance_valid(_fx):
		return _fx
	if Vfx.root == null or not is_instance_valid(Vfx.root) or not Vfx.root.is_inside_tree():
		return null
	_fx = Fx.new()
	_fx.floor_fn = _floor if _floor.is_valid() else Callable(_auto_floor)
	_fx.world_mat = _world.mat if _mode == 1 and is_instance_valid(_world) else null
	Vfx.root.add_child(_fx)
	return _fx


static var _rig: Node = null

## 没接关卡的地方问地面：镜头那边的 floor_fn（主城 / 试剑台都给了）；问不到就当在原地那么高
static func _auto_floor(x: float, z: float, y: float) -> float:
	if _rig == null or not is_instance_valid(_rig):
		_rig = null
		if Vfx.root != null and is_instance_valid(Vfx.root) and Vfx.root.is_inside_tree():
			var c3 := Vfx.root.get_viewport().get_camera_3d()
			if c3 != null and c3.get_parent() is CameraRig:
				_rig = c3.get_parent()
	if _rig != null:
		var ff: Callable = (_rig as CameraRig).floor_fn
		if ff.is_valid():
			return float(ff.call(x, z))
	return y - 0.5 if y < 1.0e8 else 0.0


static func _ground(pos: Vector3) -> float:
	if _mode == 1 and is_instance_valid(_world):
		return _world.height(pos.x, pos.z)
	if _floor.is_valid():
		return float(_floor.call(pos.x, pos.z, pos.y + 1.0))
	var f := _auto_floor(pos.x, pos.z, 1.0e9)
	return f if _rig != null else pos.y


## 不可破坏的范围（xz 矩形）：出生点、撤离台、箱子、钥匙房（连墙）、门、首领场地、祭坛、天工师、进出洞窟的点
static func zones_of(level: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not level.has_method("points"):
		return out
	var sq := func(p: Vector3, r: float) -> Rect2: return Rect2(p.x - r, p.z - r, r * 2.0, r * 2.0)
	for e: Dictionary in level.call("points", "spawn"):
		out.append(sq.call(e["pos"], 6.0))
	for e: Dictionary in level.call("points", "extract"):
		var sz: Vector3 = e.get("size", Vector3(24, 6, 24))
		var p: Vector3 = e["pos"]
		out.append(Rect2(p.x - sz.x * 0.5 - 3.0, p.z - sz.z * 0.5 - 3.0, sz.x + 6.0, sz.z + 6.0))
	for e: Dictionary in level.call("points", "box"):
		out.append(sq.call(e["pos"], 2.5))
	for e: Dictionary in level.call("points", "key_room"):
		var rm: AABB = e["room"]
		out.append(Rect2(rm.position.x, rm.position.z, rm.size.x, rm.size.z).grow(3.0))
		out.append(sq.call(e["door"], 5.0))
	for e: Dictionary in level.call("points", "boss"):
		if e.has("arena"):
			var ar: AABB = e["arena"]
			out.append(Rect2(ar.position.x, ar.position.z, ar.size.x, ar.size.z).grow(2.0))
		else:
			out.append(sq.call(e["pos"], 16.0))
	for e: Dictionary in level.call("points", "altar"):
		out.append(sq.call(e["pos"], 5.0))
	for e: Dictionary in level.call("points", "doctor"):
		if e.has("pos"):
			out.append(sq.call(e["pos"], 5.0))
	for e: Dictionary in level.call("points", "link"):
		for k: String in ["a", "a_out", "b", "b_out"]:
			if e.has(k):
				out.append(sq.call(e[k], 7.0))
	return out


# ---------- 三个接口 ----------

## 球形爆破。见文件头
static func blast(pos: Vector3, radius: float, power := 1.0, dir := Vector3.ZERO, opts := {}) -> bool:
	if not on:
		return false
	var f := fx()
	if f == null:
		return false
	var remote: bool = opts.get("remote", false)
	var quiet: bool = opts.get("quiet", false)
	var hook: bool = opts.get("hook", false)
	var r := clampf(radius, 1.0, R_MAX)
	power = clampf(power, 0.3, 2.5)
	var now := Time.get_ticks_msec()
	if not remote:
		# 同一处连着炸（一招多段、Vfx.crater 和技能脚本各调一次）：并掉
		for i in range(_recent.size() - 1, -1, -1):
			var e: Array = _recent[i]
			if now - int(e[2]) > int(MERGE_T * 1000.0):
				_recent.remove_at(i)
			elif (e[0] as Vector3).distance_to(pos) < maxf(1.2, r * 0.35) and r <= float(e[1]) * 1.15:
				stat["merged"] = int(stat["merged"]) + 1
				return bool(e[3])
	var t0 := Time.get_ticks_usec()
	var did := false
	var m := mode()
	# 坑深只有两档（联机只传一个「浅坑」标记）：正常 1.0 / 浅 SHALLOW（撞墙那种主要打墙的）
	var shallow := float(opts.get("depth_k", 1.0)) < 0.99
	var dk := SHALLOW if shallow else 1.0
	if m == 1:
		did = _blast_grid(_world, f, pos, r, power, dir, dk, quiet, hook)
	elif m == 2:
		# 老大世界：它自己攒批、自己同步（meadow_level.gd 的 _queue_blast / send_dig）
		if remote:
			_lv.call("remote_blast", pos, r)
		else:
			did = bool(_lv.call("terrain_blast", pos, r))
		if did and not quiet and not hook:
			var gy := _ground(pos)
			f.burst(Vector3(pos.x, gy, pos.z), dir, _plain_cols(), int((6.0 if Vfx.lite else 12.0) * power), 6.0 + r, 0.5 + r * 0.06, r * 0.4)
	else:
		# 擂台台面：能真碎（arena_floor.gd）
		if _tiles != null and is_instance_valid(_tiles):
			var tr: Dictionary = _tiles.call("dx_tiles", pos, r)
			var tn := int(tr.get("cells", 0))
			if tn > 0:
				did = true
				stat["cells"] = int(stat["cells"]) + tn
				if not quiet:
					var tp := Vector3(pos.x, float(tr["y"]), pos.z)
					f.burst(tp, dir, tr["cols"], int(clampf(float(tn) * 2.2, 5.0, 24.0) * (0.5 if Vfx.lite else 1.0) * (0.6 if hook else 1.0)),
							6.0 + r, clampf(0.4 + r * 0.08, 0.45, 0.95), r * 0.4)
					if not hook:
						Vfx.dust(tp + Vector3(0.0, 0.1, 0.0), 6 if Vfx.lite else 12, 4.0 + r * 0.5, 1.2 + r * 0.12)
		# 挖不了的地面：只叠表现。Vfx.quake 进来的不管（返回 false，vfx.gd 照旧贴它那圈地裂）
		if not did and not hook and not quiet:
			var gy2 := _ground(pos)
			if pos.y - gy2 <= r * 0.75 + 0.8:
				var gp := Vector3(pos.x, gy2, pos.z)
				f.rim(gp, r * 0.8, opts.get("colors", _plain_cols()), power)
				Vfx.dust(gp + Vector3(0.0, 0.1, 0.0), 6 if Vfx.lite else 12, 4.0 + r * 0.5, 1.2 + r * 0.12)
	if m != 2 and not remote and (did or not hook_only_fx(m, hook)):
		_send(2 if shallow else 0, pos, dir, r, power)
		if log_on:
			ops.append([2 if shallow else 0, pos, dir, r, power])
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	stat["blasts"] = int(stat["blasts"]) + 1
	stat["last_ms"] = ms
	stat["max_ms"] = maxf(float(stat["max_ms"]), ms)
	if remote:
		stat["remote"] = int(stat["remote"]) + 1
	else:
		_recent.append([pos, r, now, did])
	return did


## 只叠表现的关卡里 Vfx.quake 进来的那种什么都没做，不用广播
static func hook_only_fx(m: int, hook: bool) -> bool:
	return m == 3 and hook


static func _plain_cols() -> Array:
	return [Color(0.56, 0.53, 0.5), Color(0.44, 0.42, 0.4), Color(0.66, 0.62, 0.57), Color(0.36, 0.34, 0.33)]


static func _blast_grid(w: GridWorld, f: Fx, pos: Vector3, r: float, power: float, dir: Vector3, depth_k: float, quiet: bool, hook: bool) -> bool:
	var gy := w.height(pos.x, pos.z)
	# 坑按「没被炸过时的地面」定深浅（同一处再炸不会越炸越深，几条操作谁先谁后结果都一样：联机各机才对得上）
	var og := w.dx_orig(pos.x, pos.z)
	# 离地太高的够不着地：只打方块
	var reach := pos.y - og <= r * 0.75 + 0.5
	var changes := {}
	var pieces: Array = []
	var cells := 0
	if reach and depth_k > 0.0:
		var cc := Vector3(pos.x, clampf(pos.y, og - 1.0, og + 0.5), pos.z)
		cells = w.crater_changes(cc, r, r * 0.5 * clampf(power, 0.6, 1.5) * depth_k, changes)
	var boxes := w.dx_break(pos, r, changes, pieces)
	if not changes.is_empty():
		w.apply_dug(changes)
	stat["cells"] = int(stat["cells"]) + cells
	stat["boxes"] = int(stat["boxes"]) + boxes
	if not quiet:
		var lite := Vfx.lite
		if cells > 0:
			var gp := Vector3(pos.x, gy, pos.z)
			var n := int(lerpf(8.0, 26.0, clampf(r / R_MAX, 0.0, 1.0)) * (0.5 if lite else 1.0) * (0.5 if hook else 1.0))
			f.burst(gp, dir, w.dx_ground_colors(pos.x, pos.z), n, 6.0 + r * 1.1, clampf(0.35 + r * 0.09, 0.4, 1.0), r * 0.5)
			if not hook:
				Vfx.dust(gp + Vector3(0.0, 0.1, 0.0), 6 if lite else 12, 4.0 + r * 0.6, 1.3 + r * 0.15)
		if not pieces.is_empty():
			f.pieces(pieces, pos, dir, power, 22 if lite else 54, gy)
	return cells > 0 or boxes > 0


## 沿线犁一道沟。opts：remote / quiet（同 blast）
static func trench(from: Vector3, to: Vector3, width: float, power := 1.0, opts := {}) -> void:
	if not on:
		return
	var f := fx()
	if f == null:
		return
	var remote: bool = opts.get("remote", false)
	var quiet: bool = opts.get("quiet", false)
	var d := to - from
	var ln := d.length()
	if ln < 0.5:
		blast(from, width * 0.5, power, Vector3.ZERO, opts)
		return
	var pl := _trench_plan(from, to, width)
	to = pl[0]
	ln = from.distance_to(to)
	var dn := (to - from) / ln
	var r: float = pl[1]
	power = clampf(power, 0.3, 2.5)
	stat["trenches"] = int(stat["trenches"]) + 1
	var m := mode()
	if m != 2 and not remote:
		_send(1, from, to, width, power)
		if log_on:
			ops.append([1, from, to, width, power])
	var n: int = pl[2]
	if m == 1:
		var w := _world
		var fxe := maxi(n / (4 if Vfx.lite else 7), 1)
		var job := func(i: int) -> void:
			if not is_instance_valid(w):
				return
			var p := from.lerp(to, float(i) / float(n - 1))
			var gy := w.height(p.x, p.z)
			var pieces: Array = []
			var cells := _trench_step(w, p, r, power, pieces)
			if quiet or not is_instance_valid(f):
				return
			if cells > 0 and i % fxe == 0:
				var gp := Vector3(p.x, gy, p.z)
				f.burst(gp, dn + Vector3.UP * 0.3, w.dx_ground_colors(p.x, p.z), 4 if Vfx.lite else 8, 7.0 + r, clampf(0.35 + r * 0.1, 0.4, 0.9), r * 0.5)
				Vfx.dust(gp + Vector3(0.0, 0.1, 0.0), 4 if Vfx.lite else 8, 4.0 + r * 0.5, 1.2 + r * 0.15)
			if not pieces.is_empty():
				f.pieces(pieces, p - dn * 1.5, dn, power, 6 if Vfx.lite else 14, gy)
		f.add_job(job, n)
		if quiet:
			f.flush_jobs()
	elif m == 2:
		# 老大世界：沿线几个炸坑（它那边一批最多六个）
		for i in mini(n, 6):
			var p2 := from.lerp(to, float(i) / float(maxi(mini(n, 6) - 1, 1)))
			if remote:
				_lv.call("remote_blast", p2, r)
			else:
				_lv.call("terrain_blast", p2, r)
	elif not quiet:
		var k := clampi(n / 2, 2, 5 if Vfx.lite else 9)
		for i in k:
			var p3 := from.lerp(to, float(i) / float(k - 1))
			var gy3 := _ground(p3)
			if p3.y - gy3 <= r * 0.75 + 1.0:
				f.rim(Vector3(p3.x, gy3, p3.z), r * 0.7, _plain_cols(), power * 0.7)


## 犁沟的一步：p 处一个半径 r 的坑 + 打碎方块。返回炸低了几格
static func _trench_step(w: GridWorld, p: Vector3, r: float, power: float, pieces: Array) -> int:
	var og := w.dx_orig(p.x, p.z)
	var changes := {}
	var cells := 0
	if p.y - og <= r * 0.75 + 0.8:
		cells = w.crater_changes(Vector3(p.x, clampf(p.y, og - 1.0, og + 0.4), p.z), r, r * 0.55 * clampf(power, 0.6, 1.5), changes)
	var boxes := w.dx_break(p, r, changes, pieces)
	if not changes.is_empty():
		w.apply_dug(changes)
	stat["cells"] = int(stat["cells"]) + cells
	stat["boxes"] = int(stat["boxes"]) + boxes
	return cells


## 沟分成几段、每段多大（本机做的和重放的要算出同一组）：返回 [终点, 半径, 段数]
static func _trench_plan(from: Vector3, to: Vector3, width: float) -> Array:
	var d := to - from
	var ln := minf(d.length(), TRENCH_MAX)
	var end := from + d.normalized() * ln
	var r := clampf(width * 0.5, 1.2, 4.0)
	return [end, r, clampi(int(ceilf(ln / maxf(r * 1.1, 1.6))) + 1, 2, 36)]


## 在另一个世界上把一串操作重放一遍（自检：验「中途加入的人重放出来的和打的人那边一样」）。不放表现
static func replay_on(w: GridWorld, list: Array) -> void:
	for e: Variant in list:
		var a: Array = e
		var r := clampf(float(a[3]), 1.0, R_MAX)
		var power := clampf(float(a[4]), 0.3, 2.5)
		if int(a[0]) != 1:
			_blast_grid(w, null, a[1], r, power, a[2], SHALLOW if int(a[0]) == 2 else 1.0, true, false)
		else:
			var pl := _trench_plan(a[1], a[2], float(a[3]))
			var n := int(pl[2])
			var junk: Array = []
			for i in n:
				_trench_step(w, (a[1] as Vector3).lerp(pl[0], float(i) / float(n - 1)), float(pl[1]), power, junk)


## 有人被打飞撞上墙 / 地面。见文件头
static func body_crash(pos: Vector3, vel: Vector3, body_r := 0.6) -> bool:
	if not on:
		return false
	var spd := vel.length()
	if spd < CRASH_MIN or fx() == null:
		return false
	var dn := vel / spd
	var m := mode()
	stat["crashes"] = int(stat["crashes"]) + 1
	if m == 1:
		var w := _world
		var probe := pos + dn * (body_r + 0.5)
		var id := w.dx_box_at(probe, 0.35)
		if id < 0:
			id = w.dx_box_at(pos, body_r + 0.25)
		if id >= 0:
			if not w.dx_box_breakable(id):
				return false
			var hit := blast(probe, clampf(1.3 + spd / 28.0, 1.6, 3.2), clampf(spd / 30.0, 0.6, 1.5), dn, {"depth_k": SHALLOW})
			if hit and spd >= PIERCE_SPD:
				stat["pierced"] = int(stat["pierced"]) + 1
				return true
			return false
	var gy := _ground(pos)
	if pos.y - gy <= body_r + 0.8 and dn.y < -0.2:
		blast(Vector3(pos.x, gy + 0.2, pos.z), clampf(1.6 + spd / 22.0, 2.0, 4.5), clampf(spd / 30.0, 0.6, 1.4), Vector3(dn.x, 0.0, dn.z) * 0.5)
	return false


# ---------- 联机 ----------

static func _send(kind: int, a: Vector3, b: Vector3, r: float, power: float) -> void:
	var nn := _net
	if (nn == null or not is_instance_valid(nn)) and _lv != null and is_instance_valid(_lv) and _lv.has_method("dx_net"):
		nn = _lv.call("dx_net")       # 擂台：对决自己的联机节点，打起来才有
	if nn != null and is_instance_valid(nn) and nn.has_method("dx_send"):
		nn.call("dx_send", kind, a, b, r, power)


## net.gd 收到别人那边的一条操作（kind 0 爆破：a 位置 b 去向；2 爆破（浅坑）；1 犁沟：a 起点 b 终点 r 宽）
static func net_apply(kind: int, a: Vector3, b: Vector3, r: float, power: float, quiet := false) -> void:
	if kind == 1:
		trench(a, b, r, power, {"remote": true, "quiet": quiet})
	elif kind == 0 or kind == 2:
		blast(a, r, power, b, {"remote": true, "quiet": quiet, "depth_k": SHALLOW if kind == 2 else 1.0})


## 中途加入 / 房主回到自己留着的房间：把这间房已有的操作按顺序重放（不放表现）
static func net_replay(list: Array) -> int:
	var n := 0
	for e: Variant in list:
		var a: Array = e
		if a.size() >= 5:
			net_apply(int(a[0]), a[1], a[2], float(a[3]), float(a[4]), true)
			n += 1
	return n


static func _sync_in() -> void:
	if _mode != 1 or _net == null or not is_instance_valid(_net) or not bool(_net.get("active")):
		return
	if bool(_net.get("is_host")):
		if _net.has_method("dx_local_log"):
			net_replay(_net.call("dx_local_log"))
	elif _net.has_method("dx_sync_req"):
		_net.call("dx_sync_req")
