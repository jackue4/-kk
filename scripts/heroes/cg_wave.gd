extends Node3D
## 苍鸿 E「飞光」/ 觉醒「赤霄」放出去的那一道刀光（2026-11-25 第三轮）：一弯新月沿 dir 飞出去，身后拖一线光，
## 一路上每隔几米荡开一圈空间波动（Vfx.space_ring，就是对拳 / 觉醒用的那种）；撞上人 / 落地 / 飞到头炸开（cg_fx.wave_hit）。
## 判伤害的事不在这儿：on_hit 是技能脚本给的回调（打中了谁、在哪）；别人机器上放的（on_hit 没给）只画，碰到人自己炸掉。
## 平时一道只打一个人；觉醒的贯穿（pierce）：一路上的都打，飞到头才炸。
## 单独一个文件、不放 static var（见 kit_canghong2.gd 的说明）。故意不写 class_name。

const Proj := preload("res://scripts/spell_projectile.gd")
const CgFx := preload("res://scripts/heroes/cg_fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
const CLASH_PATH := "res://scripts/heroes/cg_clash.gd"      # 对冲（用 load：那边不反过来引用这里）
const CLASH_GROUP := "cg_cs_wave"
const CLASH_TOL := 0.2        # 两道的蓄力差不超过这么多才算「强度一样」

const SPEED := 48.0           # 每秒这么多米：34 米飞 0.7 秒，看得清它飞、也来得及躲
const RING_GAP := 4.5         # 每飞这么远荡开一圈空间波动（手机档翻倍）
const GROW := 0.07            # 出手后这么久长到全尺寸

var dir := Vector3.FORWARD
var swing := Vector3.RIGHT      # 这一刀是怎么挥的（新月沿它展开）
var radius := 2.2
var col := Color(0.45, 0.85, 1.0)
var aw := false
var big := false                # 收尾的那一道：炸得更大
var pierce := false
var quiet := false              # 交叉的第二道：只画，不判、不留痕、不响
var hit_r := 1.3
var on_hit := Callable()        # (目标, 接触点) → 无返回
var skip: Node3D = null         # 放它的人（别人机器上是 null：靠「离起点太近的不算」）
var floor_fn := Callable()      # (位置) → 地面高度
var speed := SPEED              # 一线天的大刀光飞得快一点
var reach := 44.0               # 飞多远（2026-11-25：34 → 44，用户嫌「一下就没了」；觉醒的 56，一线天的 70）
var ring_gap := RING_GAP
var ring_r := -1.0              # 沿途空间波动圈的半径（< 0 = 按刀光大小）
var ring_k := 0.06
var spray := false              # 沿途每一圈波动处再往两侧迸一把针（一线天）
var skim := false               # 贴着地飞不算落地（一线天：一路犁过去）
var grow_far := 1.0             # 飞到头时比出手时大多少倍（一线天越飞越大：从身后看过去不会缩成一个点）
var split := 0                  # 蓄力放的光刀 / 血刃：沿途不放朝镜头的波动圈，改成垂直于去向、立在世界里的破空圈（1 = 只有波动 · 2 = 血刃那套黑红气浪）
var smoke := false              # 血刃：刀光外面再裹一层暗红的、慢半拍散的影子
## 对冲（2026-11-25）：clash_k ≥ 0 = 这是蓄力放的光刀 / 血刃（值 = 蓄了几成），迎面撞上另一道这样的：
## 强度一样（都觉醒 / 都没觉醒，蓄力差不超过 CLASH_TOL）→ 两道顶在一起相持、炸碎（cg_clash.gd）；不一样 → 强的把弱的劈碎，自己接着飞
var clash_k := -1.0
var on_clash := Callable()      # (对冲节点)：本机主角放的那一道才给，技能脚本拿去接镜头
var held := false               # 相持中：定在原地，不走、不判
var _hold_pos := Vector3.ZERO
var _hold_t := 0.0
var hold_off := 0.0             # 相持中沿去向挪多少（cg_clash.gd 每帧给：退半步再撞上去）
var hold_grow := 0.0            # 相持中涨大了几成（0 ~ 1）
## 场景破坏（2026-11-25，用户：「周边如果有方块，直接破坏，做场景的物理破坏效果，表现可以很强」）：> 0 = 这道刀光一路把碰到的方块打碎
## （scripts/destruct.gd 的 blast，数值 = 力度）。只有放它的人那边真的炸（破坏自己会同步给别人），别人机器上只画的那道不炸
var wreck := 0.0
var wreck_rk := 1.0             # 炸多大（乘在刀光半径上）
var wreck_shallow := false      # 只炸浅坑（平时的光刀：用户嫌「地上干了太深的坑，破碎的方块整体也太大了，可以弱化一半」）
var wreck_path := true          # 一路炸过去（血刃）；false = 只在打中 / 飞到头的地方炸一下
var _wreck_at := 2.0

var _from := Vector3.ZERO
var _dist := 0.0
var _age := 0.0
var _ring_at := 1.5
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _done := false
var _hit: Array = []
var _smoke: MeshInstance3D


func _ready() -> void:
	_from = global_position
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var p := CgFx.pal(col, aw)
	_mat = CgFx.wave_mat(p, 0.7, 6.0)
	_mi = MeshInstance3D.new()
	_mi.mesh = CgFx.crescent(130, 1)
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_mi.global_transform = Transform3D(CgFx.arc_basis(dir, swing).scaled(Vector3.ONE * radius * 0.5), global_position)
	# 身后的一线光：两根拉长的针形面片（刀色的宽、白的细），每帧摆位
	_glow = Vfx.persistent_sprite(p[1], 2)
	_core = Vfx.persistent_sprite(p[0], 2)
	_glow.visible = false
	_core.visible = false
	if smoke:
		# 血刃外面那层暗红的影：大一圈、颜色压暗，跟着主刀光走
		var pd := [Color(0.75, 0.05, 0.05), Color(0.32, 0.0, 0.02), Color(0.06, 0.0, 0.01)]
		_smoke = MeshInstance3D.new()
		_smoke.mesh = CgFx.crescent(130, 1)
		_smoke.material_override = CgFx.wave_mat(pd, 0.9, 3.5)
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_smoke)
		_smoke.global_transform = _mi.global_transform
	if clash_k >= 0.0:
		add_to_group(CLASH_GROUP)
	if not quiet and split == 0:
		Vfx.space_ring(global_position, radius * 0.9, CgFx.main_col(col, aw), 0.4, 0.07)


func _exit_tree() -> void:
	for s: MeshInstance3D in [_glow, _core]:
		if is_instance_valid(s):
			s.queue_free()


func _process(dt: float) -> void:
	if _done:
		return
	_age += dt
	if held:
		# 相持：刃口顶着刃口，退半步再撞上去（挪多少由 cg_clash.gd 给，两道同一个节拍），越撞越大
		_hold_t += dt
		var at := _hold_pos + dir * hold_off
		var sc := radius * _far() * (1.0 + 0.3 * hold_grow)
		global_position = at
		_mi.global_transform = Transform3D(CgFx.arc_basis(dir, swing).scaled(Vector3.ONE * sc), at)
		if _smoke != null:
			_smoke.global_transform = Transform3D(CgFx.arc_basis(dir, swing).scaled(Vector3.ONE * sc * 1.22), at - dir * radius * 0.12)
		return
	var a := global_position
	var step := speed * dt
	var b := a + dir * step
	# 迎面有没有另一道蓄力刀光
	if clash_k >= 0.0:
		for o: Node in get_tree().get_nodes_in_group(CLASH_GROUP):
			if o == self or not is_instance_valid(o) or bool(o.get("_done")) or bool(o.get("held")):
				continue
			var od: Vector3 = o.get("dir")
			if od.dot(dir) > -0.5:
				continue
			var to: Vector3 = (o as Node3D).global_position - a
			var along := to.dot(dir)
			# 新月是朝前鼓出去的：刃口在节点前面一个半径处。两道的刃口碰上（而不是中心碰上）就算撞了
			var reach2 := radius * _far() + float(o.get("radius")) * float(o.call("_far"))
			if along < -2.0 or along > reach2 + step * 2.0 + 0.5:
				continue
			if (to - dir * along).length() > (radius * _far() + float(o.get("radius"))) * 0.6 + 1.0:
				continue
			_meet(o as Node3D)
			if _done or held:
				return
	# 一路上撞到谁
	var stop := false
	var stop_at := b
	if not quiet:
		for e: Variant in _candidates():
			var n := e as Node3D
			if n == null or not is_instance_valid(n) or n == skip or _hit.has(n):
				continue
			var ec := Proj.aim_of(n)
			var t := clampf((ec - a).dot(dir), 0.0, step)
			var cp := a + dir * t
			if cp.distance_to(ec) > hit_r * _far() + Proj.body_r(n):
				continue
			if skip == null and ec.distance_to(_from) < 2.6:
				continue        # 别人放的：起点边上的那个就是放它的人
			_hit.append(n)
			if on_hit.is_valid():
				on_hit.call(n, cp)
			if not pierce:
				stop = true
				stop_at = cp
				break
			CgFx.hit_fx(ec, swing, dir, col, aw, false)
	# 落地
	if not stop and not skim and floor_fn.is_valid():
		var fy := float(floor_fn.call(b))
		if b.y < fy + 0.15:
			stop = true
			stop_at = Vector3(b.x, fy + 0.2, b.z)
	_dist += stop_at.distance_to(a)
	global_position = stop_at
	var grow := clampf(_age / GROW, 0.0, 1.0)
	_mi.global_transform = Transform3D(CgFx.arc_basis(dir, swing).scaled(Vector3.ONE * radius * lerpf(0.5, 1.0, grow) * _far()), stop_at)
	if _smoke != null:
		_smoke.global_transform = Transform3D(CgFx.arc_basis(dir, swing).scaled(Vector3.ONE * radius * lerpf(0.5, 1.0, grow) * _far() * 1.22), stop_at - dir * radius * 0.12)
	# 拖在身后的光：最长拖 9 米
	var tail := minf(_dist, maxf(9.0, radius * 2.2))
	if tail > 0.6:
		var mid := stop_at - dir * (tail * 0.5 + radius * 0.2)
		Vfx.place_streak(_glow, mid, dir, tail * 1.25, 0.34 * radius / 2.2)
		Vfx.place_streak(_core, mid, dir, tail * 1.1, 0.11 * radius / 2.2)
		_glow.visible = true
		_core.visible = true
	# 一路上的空间波动
	if not quiet and _dist >= _ring_at:
		_ring_at += ring_gap * (2.0 if Vfx.lite else 1.0)
		if split > 0:
			CgFx.air_split(stop_at - dir * 0.6, dir, ring_r if ring_r > 0.0 else radius * 0.8, col, aw, split >= 2)
		else:
			Vfx.space_ring(stop_at - dir * 0.6, ring_r if ring_r > 0.0 else radius * 0.8, CgFx.main_col(col, aw), 0.42, ring_k)
		if wreck > 0.0 and wreck_path and skip != null and _dist >= _wreck_at:
			_wreck_at = _dist + 6.0
			_blast(stop_at, minf(radius * _far() * 0.85 * wreck_rk, 7.0), wreck)
		if spray:
			var sd := swing.normalized()
			CgFx.needles(stop_at + sd * radius * 0.7, (sd - dir * 0.6).normalized(), 3, col, aw, radius * 0.6, 0.4, 0.09, 12)
			CgFx.needles(stop_at - sd * radius * 0.7, (-sd - dir * 0.6).normalized(), 3, col, aw, radius * 0.6, 0.4, 0.09, 12)
			CgFx.needles(stop_at, Vector3.UP, 0, col, aw, radius * 0.5, 0.45, 0.08, 14)
		# 屏幕那一层的扭曲也跟着刀光走（强度和对拳一个量级：0.01 上下，见 air_melee 的 WARP_BASE）
		var wk := 0.02 if aw else 0.013
		if Vfx.warp_k < wk:
			Vfx.warp_pos = stop_at
			Vfx.warp_k = wk
	if stop or _dist >= reach:
		_end(stop)


func strength() -> float:
	return (2.0 if aw else 0.0) + clash_k


## 迎面撞上了另一道蓄力刀光
func _meet(o: Node3D) -> void:
	var mid := (global_position + o.global_position) * 0.5
	var equal: bool = aw == bool(o.get("aw")) and absf(clash_k - float(o.get("clash_k"))) <= CLASH_TOL
	if not equal:
		if strength() > float(o.call("strength")):
			o.call("break_small", mid)
		else:
			break_small(mid)
		return
	# 两道都退到「刃口正好在中点碰上」的位置（判到的时候可能已经互相扎进去一点了）
	var ra := radius * _far()
	var rb: float = float(o.get("radius")) * float(o.call("_far"))
	var lat := (o.global_position - global_position)
	lat -= dir * lat.dot(dir)
	mid = global_position + dir * (o.global_position - global_position).dot(dir) * 0.5 + lat * 0.5
	hold_at(mid - dir * ra * 0.96 - lat * 0.5)
	o.call("hold_at", mid + dir * rb * 0.96 + lat * 0.5)
	var cl: Node3D = (load(CLASH_PATH) as GDScript).new()
	cl.set("a", self)
	cl.set("b", o)
	cl.set("axis", dir)
	cl.set("col_a", col)
	cl.set("col_b", o.get("col"))
	cl.set("aw", aw)
	cl.set("size", maxf(radius, float(o.get("radius"))))
	cl.position = mid
	Vfx.root.add_child(cl)
	for w: Node3D in [self, o]:
		var cb: Callable = w.get("on_clash")
		if cb.is_valid():
			cb.call(cl)


func hold_at(p: Vector3) -> void:
	held = true
	_hold_pos = p
	_hold_t = 0.0
	global_position = p


## 被更强的一道劈碎：小小地炸一下就没了
func break_small(at: Vector3) -> void:
	if _done:
		return
	_done = true
	global_position = at
	CgFx.cut(at, swing, radius * 3.0, col, aw, 0.05, 1.2)
	CgFx.needles(at, -dir, 0, col, aw, radius * 1.6, 0.35, 0.08)
	CgFx.ring_warp(at, dir, radius * 1.6, CgFx.main_col(col, aw), 0.4, 0.07)
	Sfx.play("blade_cut", -4.0, 1.3)
	Sfx.play("shatter", -8.0, 1.4)
	CgFx.scar(_from, at, col, aw)
	_fade_out(0.12)


## 对冲炸开的那一下（cg_clash.gd 调）：这一道碎掉
func shatter() -> void:
	if _done:
		return
	_done = true
	held = false
	_fade_out(0.1)


func _fade_out(t: float) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_mat, "shader_parameter/age", 1.0, t)
	if _smoke != null:
		tw.tween_property(_smoke.material_override, "shader_parameter/age", 1.0, t)
	for s: MeshInstance3D in [_glow, _core]:
		tw.tween_property(s.material_override, "shader_parameter/alpha", 0.0, t)
	tw.chain().tween_callback(queue_free)


func _far() -> float:
	return lerpf(1.0, grow_far, clampf(_dist / maxf(reach, 1.0), 0.0, 1.0))


func _candidates() -> Array:
	var out: Array = []
	out.append_array(Proj.targets(get_tree()))
	if skip == null:
		out.append_array(get_tree().get_nodes_in_group("player"))
	return out


## 把这儿的方块打碎（没有破坏系统 / 这张图不支持时什么都不做）
func _blast(pos: Vector3, r: float, power: float) -> void:
	if not ResourceLoader.exists("res://scripts/destruct.gd"):
		return
	var ds: GDScript = load("res://scripts/destruct.gd")
	if ds != null and ds.has_method("blast"):
		ds.call("blast", pos, r, power, dir, {"depth_k": 0.3} if wreck_shallow else {})


func _end(struck: bool) -> void:
	_done = true
	var pos := global_position
	if wreck > 0.0 and skip != null and (struck or big):
		_blast(pos, minf(radius * 1.25 * wreck_rk, 8.0), wreck * 1.2)
	if not quiet:
		if struck or big:
			CgFx.wave_hit(pos, dir, swing, col, aw, big)
			Sfx.play("cut_burst" if big else "blade_cut", -3.0 if big else -5.0, randf_range(0.95, 1.2))
		else:
			CgFx.needles(pos, dir, 3, col, aw, 3.0, 0.3)
			Vfx.space_ring(pos, radius * 0.8, CgFx.main_col(col, aw), 0.4, 0.05)
		CgFx.scar(_from, pos, col, aw)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_mat, "shader_parameter/age", 1.0, 0.12)
	if _smoke != null:
		tw.tween_property(_smoke.material_override, "shader_parameter/age", 1.0, 0.22)
	for s: MeshInstance3D in [_glow, _core]:
		tw.tween_property(s.material_override, "shader_parameter/alpha", 0.0, 0.16)
	tw.chain().tween_callback(queue_free)
