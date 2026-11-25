extends Node3D
## 灵田（2026-11-23）：灵田农场种植区里的六块灵田，每块 4×4 = 16 格、一格种一株。挂在 hub_farm.gd 的 root 下面（跟着农场一起显隐），坐标是农场的本地坐标。
## 操作（2026-11-23 下午用户定的）：右下角的「攻」在农场里换成种植按钮（触屏是 touch_controls.gd 的 attack_text；桌面是底部按钮 + J / 鼠标左键 / T）：
##   整备 → 不在灵田上、手里没拿灵种、或者这块地没空格时：右侧打开灵种背包（图标 + 成熟时间），点一种再点「选择」= 手里拿着这种灵种
##   播种 → 拿着灵种站到有空格的灵田上：点一下种离自己最近的一格（灵石当场扣），按住不放就一格格接着种
##   收获 → 站的这块灵田里有熟了的：一下把这块地熟了的全收进仓库，头顶飘一张小条「+N」（仓库满了收到哪算哪，余下的留在地里）
##   农场里不打架：「攻」被这里接走，御 / 剑 / 诀 / 罡 / 阵 收起来（touch_controls.gd 的 peace），键盘上的这几个键也不出招
## 生长按真实时间（下线也长）；模型按进度换阶段（嫩芽 → 小株 → 大株 → 成熟），每段里慢慢长大；熟了的那格土垄描一圈金边；每块地头顶一行字写长势
## 没开垦（境界不够）的地：长着荒草、插一块牌子写几时能开垦
## 存档：Profile.data()["farm"] = {"cells": [{"id": 灵植, "t0": 种下的 unix 秒} / {} …共 96 格], "seed": 手里拿着的灵种}
##   上午那版是十二块单格的地（"plots"），读到老存档时把里面种着的挪进前几格（种下的时刻照旧），再删掉 "plots"
## 九十多株同屏：同一个模型的所有株合成一个 MultiMesh（一株一个节点在手机网页上太费）
## 灵植表、数值、产出、丹方在 farm_data.gd。故意不写 class_name：用 preload 引用。

const FarmData := preload("res://scripts/farm_data.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const BlockWorld := preload("res://scripts/block_world.gd")
const WORLD_SHADER := preload("res://shaders/block_world.gdshader")
const Sfx := preload("res://scripts/sfx.gd")
const Data := preload("res://scripts/raid_data.gd")

## 六块灵田的中心（农场本地坐标）：种植区原来的四畦菜地，西边两畦（20 米宽）各并排两块、东边两畦各一块；
## 一块 10 米见方，正好铺满它那一块菜畦（hub_farm.gd 的 _layout 按这个收齐了畦的大小，2026-11-23 用户：「4*4 的地没有跟原始的体块铺满」）
const FIELDS: Array[Vector3] = [
	Vector3(19.0, 0.3, 3.0), Vector3(29.0, 0.3, 3.0),
	Vector3(19.0, 0.3, 19.0), Vector3(29.0, 0.3, 19.0),
	Vector3(47.0, 0.3, 3.0), Vector3(47.0, 0.3, 19.0),
]
const GRID := 4                 # 和 FarmData.GRID 一样
const PITCH := 2.4              # 一格多宽（米）
const FIELD_W := 9.68           # 底土的边长（外面一圈 0.16 的木框，框外沿正好 10 米）
const MOUND := 2.04             # 一格土垄的边长
const MIN_SEEN := 1.35          # 生长中的一株最大边长至少这么多（米）：嫩芽模型本身很小，照比例缩出来在 2.4 米的格子里几乎看不见
const BASE_Y := 0.22            # 土垄顶面比畦面高这么多（hub_farm.gd 画的底土 0.1 + 垄 0.12）
const NEAR := 0.8               # 站在地框外这么远以内也算在这块地上（西边并排的两块挨着，站在交界上算离得近的那块）
const GLOW_FLOOR := 0.2         # 模型自带的一点底光（和 creature_model.gd 一样）
const HOLD_FIRST := 0.32        # 按住「播种」：第一格种下以后隔这么久开始连种
const HOLD_EVERY := 0.13        # 连种时一格隔多久
const QUIET_ACTIONS := ["guard", "summon", "ult", "air_shot", "skill_next"]   # 农场里不出招
const BAG_W := 770.0
const DET_W := 380.0

## 自检用：把「现在」往后拨多少秒
static var time_offset := 0.0
static var _scenes := {}        # 模型键 → PackedScene（或 null）
static var _boxes := {}         # 模型键 → 模型本身的包围盒（模型根的本地坐标）
static var _cs_ref: Array = []  # 校验过的那份 cells（同一个数组就不再逐格查类型）

var font: Font
var mobile := false
var say: Callable               # hub_hall.gd 的 say（屏幕中间飘一行字）
var main: Node                  # main.gd（找触屏按钮层 main.touch）
var blocked := false            # 主城在演出 / 洞府开着（hub_hall.gd 每帧设）
var on := false                 # 现在在农场里（hub_hall.gd 的 _apply_area 设）
var cur_field := -1             # 主角站在哪块灵田上（-1 = 不在）
var _was_field := -2
var _pos := Vector3.ZERO        # 主角位置（农场本地）
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _label_t := 0.0
var _save_t := -1.0             # >0：这么多秒后存档（连种时不每格都写一次）
var _hold_sow := false
var _hold_t := 0.0
var _fields: Array = []         # 每块地：{root, label, lock, ripe(MeshInstance3D), ripe_sig, ripe_n}
var _groups := {}               # 模型键 → {mmis: [MultiMeshInstance3D], parts: [Transform3D], cells: [格]}
var _cell_xf: Array = []        # 每格：这一株的摆放（不含模型里各部件自己的变换）；空格 = null
var _cell_grp: Array = []       # 每格：[模型键, 在那一组里的序号]；空格 = null
var _cell_st: Array = []        # 每格：这次刷新时的 status（_refresh_field 复用，不再算一遍）
var _written := {}              # "模型键:序号" → 上次写进 MultiMesh 的摆放（没变就不重写；手机网页上省一截）
var _pop := {}                  # 格 → 刚种下多久（冒出来的那一下）
var _leaving: Array = []        # 收走的那几株：{node, t, delay, y0, k0}
var _gains: Array = []          # 头顶的收获小条：{root, box, at, t}
var _cursor: MeshInstance3D     # 播种时下一格的位置
var _ui: CanvasLayer
var _th: Theme
var _shade: ColorRect           # 灵种背包（整屏一层，点暗处关）
var _tab := 0                   # 0 灵草 / 1 灵果
var _pick := ""                 # 背包里点中的那一种（点「选择」才拿到手上）
var _chip: Button               # 手里拿着的灵种（点它也能打开背包）
var _chip_id := "?"
var _touch_blocked := false     # 背包开着时是我把触屏层挡住的
var _mouse_was_captured := false


static func now() -> float:
	return Time.get_unix_time_from_system() + time_offset


func _ready() -> void:
	set_meta("no_portal_copy", true)      # 透视门里不复制灵田（会变的东西，门里那份是开机时的快照）
	_rng.randomize()
	_cell_xf.resize(cell_count())
	_cell_grp.resize(cell_count())
	_cell_st.resize(cell_count())
	for f in FIELDS.size():
		_fields.append(_make_field(f))
	_cursor = _make_cursor()
	add_child(_cursor)
	_cursor.visible = false
	refresh_all()


# ---------- 存档 ----------

static func cell_count() -> int:
	return FIELDS.size() * GRID * GRID


static func field_of(c: int) -> int:
	return c / (GRID * GRID)


## 一格的中心（农场本地坐标，畦面高度）
static func cell_local(c: int) -> Vector3:
	var k := c % (GRID * GRID)
	var col := k % GRID
	var row := k / GRID
	var h := float(GRID - 1) * 0.5
	return FIELDS[field_of(c)] + Vector3((float(col) - h) * PITCH, 0.0, (float(row) - h) * PITCH)


static func data() -> Dictionary:
	var d := Profile.data()
	if not (d.get("farm") is Dictionary):
		d["farm"] = {}
	var f: Dictionary = d["farm"]
	if not (f.get("cells") is Array):
		f["cells"] = []
	var cs: Array = f["cells"]
	if not is_same(cs, _cs_ref) or cs.size() != cell_count():
		while cs.size() < cell_count():
			cs.append({})
		for i in cs.size():
			if not (cs[i] is Dictionary):
				cs[i] = {}
		_cs_ref = cs
	# 老存档（上午那版十二块单格的地）：种着的挪进前几格
	if f.has("plots"):
		var olds: Variant = f["plots"]
		f.erase("plots")
		if olds is Array:
			var k := 0
			for st: Variant in olds:
				if st is Dictionary and not (st as Dictionary).is_empty():
					while k < cs.size() and not (cs[k] as Dictionary).is_empty():
						k += 1
					if k < cs.size():
						cs[k] = (st as Dictionary).duplicate()
	return f


static func cells() -> Array:
	return data()["cells"]


static func cell_state(c: int) -> Dictionary:
	return cells()[c]


## 手里拿着的灵种（id；"" = 没拿）
static func seed_id() -> String:
	return str(data().get("seed", ""))


static func field_unlocked(f: int) -> bool:
	return Profile.realm() >= int(FarmData.FIELD_REALM[f])


static func lock_text(f: int) -> String:
	return "这块灵田要到%s期才能开垦" % str(Realm.LIST[int(FarmData.FIELD_REALM[f])]["name"])


## 有几株熟了可以收（进农场时提示）
static func ripe_count() -> int:
	var n := 0
	for c in cell_count():
		if field_unlocked(field_of(c)):
			var s := status(c)
			if not s.is_empty() and float(s["p"]) >= 1.0:
				n += 1
	return n


## 这一格：{plant, p 进度 0~1, left 剩余秒}；空格返回 {}
static func status(c: int) -> Dictionary:
	var st := cell_state(c)
	if st.is_empty():
		return {}
	var p := FarmData.plant(str(st.get("id", "")))
	if p.is_empty():
		return {}
	var dur := float(p["grow"])
	var el := now() - float(st.get("t0", now()))
	return {"plant": p, "p": clampf(el / dur, 0.0, 1.0), "left": maxf(dur - el, 0.0)}


# ---------- 种 / 收 ----------

## 种下一格（灵石当场扣）：返回 "" 或者为什么种不了
func sow(c: int, id: String, free := false) -> String:
	var p := FarmData.plant(id)
	if p.is_empty() or c < 0 or c >= cell_count():
		return "没有这种灵种"
	if not field_unlocked(field_of(c)):
		return lock_text(field_of(c))
	if not cell_state(c).is_empty():
		return "这一格已经种着东西"
	if Profile.realm() < int(p["realm"]):
		return "%s要%s期才种得活" % [p["name"], str(Realm.LIST[int(p["realm"])]["name"])]
	if not free:
		if Profile.lingshi() < int(p["price"]):
			return "灵石不够（%s的灵种一颗 %d）" % [p["name"], int(p["price"])]
		Profile.data()["lingshi"] = Profile.lingshi() - int(p["price"])
	cells()[c] = {"id": str(p["id"]), "t0": now()}
	_pop[c] = 0.0
	_save_t = 0.8 if _hold_sow else 0.05
	refresh_all()
	return ""


## 这块地里离主角最近的空格（-1 = 没有）
func next_empty(f: int) -> int:
	var best := -1
	var bd := INF
	var cs := cells()
	for k in GRID * GRID:
		var c := f * GRID * GRID + k
		if (cs[c] as Dictionary).is_empty():
			var d := Vector2(cell_local(c).x - _pos.x, cell_local(c).z - _pos.z).length_squared()
			if d < bd:
				bd = d
				best = c
	return best


func _sow_next() -> bool:
	if cur_field < 0:
		return false
	var c := next_empty(cur_field)
	if c < 0:
		return false
	var err := sow(c, seed_id())
	if err != "":
		_say(err)
		return false
	Sfx.play("ui_click", -10.0, 0.9 + _rng.randf() * 0.25)
	return true


## 收：这块地熟了的全收进仓库。返回 {got: {物品名: 个数}, cells: 收了几株, left: 熟了但仓库放不下、留在地里的几株}
func harvest_field(f: int) -> Dictionary:
	var out := {"got": {}, "cells": 0, "left": 0}
	if f < 0 or not field_unlocked(f):
		return out
	var ripe: Array = []
	for k in GRID * GRID:
		var c := f * GRID * GRID + k
		var s := status(c)
		if not s.is_empty() and float(s["p"]) >= 1.0:
			ripe.append(c)
	ripe.sort_custom(func(a: int, b: int) -> bool:
		return Vector2(cell_local(a).x - _pos.x, cell_local(a).z - _pos.z).length_squared() < Vector2(cell_local(b).x - _pos.x, cell_local(b).z - _pos.z).length_squared())
	var got: Dictionary = out["got"]
	var gone: Array = []
	for c: int in ripe:
		var items := FarmData.harvest_items(status(c)["plant"], _rng)
		if not Profile.stash_fits(items[0], items.size()):       # 灵草 / 灵果在仓库里叠成一格（raid_profile.gd 的 stash_slots）
			out["left"] = int(out["left"]) + 1
			continue
		for it: Dictionary in items:
			Profile.stash().append(it)
			got[str(it["name"])] = int(got.get(str(it["name"]), 0)) + 1
		gone.append([c, str(_cell_grp[c][0]) if _cell_grp[c] != null else "", _cell_xf[c]])
		cells()[c] = {}
		_pop.erase(c)
	out["cells"] = gone.size()
	if gone.is_empty():
		if int(out["left"]) > 0:
			_say("仓库满了（%d/%d 格），先去仓库腾点地方再来收" % [Profile.stash_slots(), Profile.STASH_CAP], 2.4)
		return out
	Profile.save()
	refresh_all()
	for i in gone.size():
		_leave(int(gone[i][0]), str(gone[i][1]), gone[i][2], float(i) * 0.035)
	Sfx.play("pickup", -6.0, 1.1)
	_show_gain(got, int(out["left"]))
	return out


# ---------- 按钮 ----------

## 现在按下去做什么：harvest / sow / prep（整备 = 打开灵种背包）
func mode() -> String:
	if cur_field < 0 or not field_unlocked(cur_field):
		return "prep"
	if int(_fields[cur_field]["ripe_n"]) > 0:
		return "harvest"
	if seed_id() != "" and next_empty(cur_field) >= 0:
		return "sow"
	return "prep"


## hub_hall.gd 每帧问（在农场里、不在演出时）：主角在哪，底部按钮写什么（桌面用；触屏的字在 tick 里写到「攻」上）
func use_text(world_pos: Vector3) -> String:
	_pos = to_local(world_pos)
	cur_field = _field_at(_pos)
	if cur_field != _was_field:
		_was_field = cur_field
		if cur_field >= 0 and not field_unlocked(cur_field):
			_say(lock_text(cur_field))
	match mode():
		"harvest":
			return "收 获"
		"sow":
			return "播 种"
	return "整 备"


func _field_at(lp: Vector3) -> int:
	var best := -1
	var bd := INF
	for f in FIELDS.size():
		var dx := absf(lp.x - FIELDS[f].x) - FIELD_W * 0.5
		var dz := absf(lp.z - FIELDS[f].z) - FIELD_W * 0.5
		if dx < NEAR and dz < NEAR and absf(lp.y - FIELDS[f].y) < 2.5:
			var d := maxf(dx, dz)
			if d < bd:
				bd = d
				best = f
	return best


## 按下种植按钮（触屏「攻」、J、鼠标左键、T、桌面底部按钮）
func press(can_hold := true) -> void:
	if blocked or bag_open():
		return
	match mode():
		"harvest":
			harvest_field(cur_field)
		"sow":
			if _sow_next():
				_hold_sow = can_hold
				_hold_t = HOLD_FIRST
		_:
			open_bag()


## hub_farm.gd → hub_hall.gd 的老接口（底部按钮 / T）
func use(world_pos: Vector3) -> void:
	use_text(world_pos)
	press()


## 农场里接走「攻」（触屏按钮发的是同一个动作），御 / 阵 / 罡 这些吞掉不出招
func _input(e: InputEvent) -> void:
	if not on or blocked or bag_open():
		return
	if e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return      # 桌面：鼠标没抓住时这一下是点界面 / 抓鼠标用的
	if e.is_action("attack"):
		if e.is_pressed() and not e.is_echo():
			press()
		get_viewport().set_input_as_handled()
		return
	for a: String in QUIET_ACTIONS:
		if e.is_action(a):
			get_viewport().set_input_as_handled()
			return


## 进 / 出农场
func set_on(v: bool) -> void:
	on = v
	_hold_sow = false
	_was_field = -2
	var t := _touch()
	if t != null:
		t.set("attack_text", "")
		t.set("peace", v)
	if not v:
		close_bag()
		_cursor.visible = false
		if _chip != null:
			_chip.visible = false
		if _save_t > 0.0:
			_save_t = -1.0
			Profile.save()
	else:
		refresh_all()


func _touch() -> Node:
	if main == null or not is_instance_valid(main):
		return null
	var t: Variant = main.get("touch")
	return t as Node if is_instance_valid(t) else null


func _say(text: String, hold := 1.8) -> void:
	if say.is_valid():
		say.call(text, hold)


# ---------- 每帧 ----------

func tick(dt: float) -> void:
	_time += dt
	_label_t -= dt
	if _label_t <= 0.0:
		_label_t = 0.5
		refresh_all()
	if _save_t > 0.0:
		_save_t -= dt
		if _save_t <= 0.0:
			_save_t = -1.0
			Profile.save()
	# 按住「播种」连种
	if _hold_sow:
		var held := Input.is_action_pressed("attack") or Input.is_action_pressed("hub_use")
		if not held or blocked or bag_open():
			_hold_sow = false
			_save_t = 0.05 if _save_t > 0.0 else _save_t
		else:
			_hold_t -= dt
			if _hold_t <= 0.0:
				_hold_t = HOLD_EVERY
				if mode() != "sow" or not _sow_next():
					_hold_sow = false
	var m := "" if (blocked or not on) else mode()
	# 触屏：「攻」上写 整备 / 播种 / 收获
	var t := _touch()
	if t != null and on:
		t.set("attack_text", "" if m == "" else {"harvest": "收获", "sow": "播种"}.get(m, "整备"))
	# 下一格种在哪
	var nx := next_empty(cur_field) if m == "sow" else -1
	_cursor.visible = nx >= 0
	if nx >= 0:
		_cursor.position = cell_local(nx) + Vector3(0.0, BASE_Y + 0.02, 0.0)
		var s := 1.0 + 0.05 * sin(_time * 6.0)
		_cursor.scale = Vector3(s, 1.0, s)
	# 刚种下的冒出来
	if not _pop.is_empty():
		for c: int in _pop.keys():
			var a := float(_pop[c]) + dt
			if a >= 0.32:
				_pop.erase(c)
			else:
				_pop[c] = a
			_put_cell(c)
	# 收走的那几株：往上一跳、缩没
	var i := _leaving.size() - 1
	while i >= 0:
		var L: Dictionary = _leaving[i]
		L["t"] = float(L["t"]) + dt
		var u := (float(L["t"]) - float(L["delay"])) / 0.42
		var n := L["node"] as Node3D
		if u >= 1.0:
			n.queue_free()
			_leaving.remove_at(i)
		elif u > 0.0:
			n.visible = true
			var k := float(L["k0"]) * (1.0 + 0.25 * sin(u * PI)) * (1.0 - u * u)
			n.scale = Vector3.ONE * maxf(k, 0.001)
			n.position.y = float(L["y0"]) + 1.2 * u
		i -= 1
	_tick_gains(dt)
	_tick_chip()


## 把每格的样子对上存档：开没开垦、种的什么、长到第几段（换模型）、这一段里长到多大；每块地头顶的字、熟了的金边
func refresh_all() -> void:
	if _fields.is_empty():
		return
	var want := {}          # 模型键 → [格]
	for c in cell_count():
		var f := field_of(c)
		var s := status(c) if field_unlocked(f) else {}
		_cell_st[c] = s
		if s.is_empty():
			_cell_xf[c] = null
			continue
		var p: Dictionary = s["plant"]
		var st: Array = p["stages"]
		var prog := float(s["p"])
		var key := ""
		var sc := 1.0
		var grow_k := 1.0       # 段内长大的那一截（0.82~1.0；按 1% 一档取整，长得慢的几小时才变一档，不用每次重写）
		if prog >= 1.0:
			key = str(p["ripe"][0])
			sc = float(p["ripe"][1])
		else:
			var n := st.size()
			var k := mini(int(prog * float(n)), n - 1)
			key = str(st[k][0])
			grow_k = snappedf(0.82 + 0.18 * (prog * float(n) - float(k)), 0.01)
			sc = float(st[k][1]) * grow_k
		var base := float(p["size"]) / _max_extent(str(p["ripe"][0]))
		var kk := base * sc
		if prog < 1.0:
			kk = maxf(kk, MIN_SEEN / _max_extent(key) * grow_k)
		var b: AABB = _box(key)
		var yaw := float((c * 7 + c / 5) % 4) * PI * 0.5
		var rb := Basis(Vector3.UP, yaw)
		var off := -Vector3(b.get_center().x, b.position.y, b.get_center().z) * kk
		_cell_xf[c] = Transform3D(rb.scaled(Vector3.ONE * kk), cell_local(c) + Vector3(0.0, BASE_Y, 0.0) + rb * off)
		if not want.has(key):
			want[key] = []
		(want[key] as Array).append(c)
	for c in cell_count():
		_cell_grp[c] = null
	for key: String in _groups.keys():
		if not want.has(key):
			_fill_group(key, [])
	for key: String in want.keys():
		_fill_group(key, want[key])
	for f in _fields.size():
		_refresh_field(f)


func _fill_group(key: String, list: Array) -> void:
	var g := _group(key)
	g["cells"] = list
	var mmis: Array = g["mmis"]
	var old := (mmis[0] as MultiMeshInstance3D).multimesh.instance_count if not mmis.is_empty() else 0
	if old != list.size():
		for j in maxi(old, list.size()):
			_written.erase("%s:%d" % [key, j])        # 改了个数，原来写进去的全清了，都要重写
	for mmi: MultiMeshInstance3D in mmis:
		if mmi.multimesh.instance_count != list.size():
			mmi.multimesh.instance_count = list.size()
		mmi.visible = not list.is_empty()
	for j in list.size():
		var c := int(list[j])
		_cell_grp[c] = [key, j]
		var wk := "%s:%d" % [key, j]
		if _pop.has(c) or not _written.has(wk) or _written[wk] != _cell_xf[c]:
			_put_cell(c)
			_written[wk] = _cell_xf[c]


## 一格的那一株写进它那组 MultiMesh（刚种下的按冒出来的进度缩放）
func _put_cell(c: int) -> void:
	if _cell_grp[c] == null or _cell_xf[c] == null:
		return
	var g: Dictionary = _groups[str(_cell_grp[c][0])]
	var j := int(_cell_grp[c][1])
	var xf: Transform3D = _cell_xf[c]
	if _pop.has(c):
		var u := clampf(float(_pop[c]) / 0.32, 0.0, 1.0)
		var s := maxf(0.001, 1.0 + 0.5 * (u - 1.0) * (u - 1.0) * -2.0 + 0.18 * sin(u * PI))      # 0 → 稍大一点 → 1
		var ground := cell_local(c) + Vector3(0.0, BASE_Y, 0.0)
		xf = Transform3D(xf.basis.scaled(Vector3.ONE * s), ground + (xf.origin - ground) * s)
	var parts: Array = g["parts"]
	var mmis: Array = g["mmis"]
	for pi in mmis.size():
		var mm := (mmis[pi] as MultiMeshInstance3D).multimesh
		if j < mm.instance_count:
			mm.set_instance_transform(j, xf * (parts[pi] as Transform3D))


## 每块地：头顶一行字、熟了的那几格描金边、没开垦的荒草木牌
func _refresh_field(f: int) -> void:
	var F: Dictionary = _fields[f]
	var open := field_unlocked(f)
	(F["lock"] as Node3D).visible = not open
	var ripe: Array = []
	var grow := 0
	var soon := INF
	if open:
		for k in GRID * GRID:
			var c := f * GRID * GRID + k
			var s: Dictionary = _cell_st[c] if _cell_st[c] != null else {}
			if s.is_empty():
				continue
			if float(s["p"]) >= 1.0:
				ripe.append(c)
			else:
				grow += 1
				soon = minf(soon, float(s["left"]))
	F["ripe_n"] = ripe.size()
	var sig := str(ripe)
	if sig != str(F["ripe_sig"]):
		F["ripe_sig"] = sig
		var mi := F["ripe"] as MeshInstance3D
		if ripe.is_empty():
			mi.visible = false
		else:
			var a := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
			var gold := Color(1.0, 0.82, 0.38)
			for c: int in ripe:
				var cp := cell_local(c) - FIELDS[f]
				for q in 4:
					var bs := Basis(Vector3.UP, PI * 0.5 * float(q))
					BlockWorld._box(a, Vector3(MOUND + 0.08, 0.05, 0.09), Transform3D(bs, cp + bs * Vector3(0.0, BASE_Y + 0.02, MOUND * 0.5)), gold, 0.9, 1.0)
			mi.mesh = _array_mesh(a)
			mi.visible = true
	var lab := F["label"] as Label3D
	if not open or (ripe.is_empty() and grow == 0):
		lab.visible = false
	else:
		lab.visible = true
		if not ripe.is_empty():
			lab.text = "可收获 %d 株" % ripe.size() + ("　另 %d 株生长中" % grow if grow > 0 else "")
			lab.modulate = Color(1.0, 0.88, 0.45)
		else:
			lab.text = "生长中 %d 株 · %s后可收" % [grow, FarmData.dur_text(soon)]
			lab.modulate = Color(0.95, 0.97, 0.92)


# ---------- 模型 ----------

static func _path(key: String) -> String:
	return "res://assets/%s.glb" % key


static func _scene(key: String) -> PackedScene:
	if _scenes.has(key):
		return _scenes[key]
	var ps: PackedScene = null
	var path := _path(key)
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_scenes[key] = ps
	return ps


## 摆一个模型到 parent 下：导入过的走 PackedScene；没导入（命令行刚拷进来）就运行时读 GLB 文件。顺带记下模型的包围盒
func _instance(key: String, parent: Node3D) -> Node3D:
	var node: Node3D = null
	var ps := _scene(key)
	if ps != null:
		node = ps.instantiate() as Node3D
	else:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(_path(key)), st) == OK:
			node = doc.generate_scene(st) as Node3D
	if node == null:
		return null
	parent.add_child(node)
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	for c in meshes:
		var mi := c as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m != null and not m.has_meta("farm_ready"):
				m.set_meta("farm_ready", true)
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				m.metallic = 0.0
				m.roughness = maxf(m.roughness, 0.8)
				if m.albedo_texture != null and not m.emission_enabled:
					m.emission_enabled = true
					m.emission_texture = m.albedo_texture
					m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					m.emission = Color.WHITE
					m.emission_energy_multiplier = GLOW_FLOOR
	if not _boxes.has(key):
		var box := AABB()
		var first := true
		for c in meshes:
			var mi2 := c as MeshInstance3D
			if mi2.mesh == null:
				continue
			var bb := _rel_xf(mi2, node) * mi2.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		_boxes[key] = box if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return node


## n 相对模型根的变换（不含模型根自己的）
static func _rel_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var q: Node = n
	while q != null and q != root:
		if q is Node3D:
			xf = (q as Node3D).transform * xf
		q = q.get_parent()
	return xf


## 一个模型的所有株合成的那一组 MultiMesh（模型里每个网格一个）
func _group(key: String) -> Dictionary:
	if _groups.has(key):
		return _groups[key]
	var g := {"mmis": [], "parts": [], "cells": []}
	var tmp := Node3D.new()
	add_child(tmp)
	var node := _instance(key, tmp)
	if node != null:
		for c in node.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi.mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if mi.material_override != null:
				mmi.material_override = mi.material_override
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)
			(g["mmis"] as Array).append(mmi)
			(g["parts"] as Array).append(_rel_xf(mi, node))
	tmp.queue_free()
	_groups[key] = g
	return g


func _box(key: String) -> AABB:
	if not _boxes.has(key):
		_group(key)
	return _boxes.get(key, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE))


## 一个模型的最大边长（同一株灵植按成熟模型的这个数统一缩放：嫩芽比成熟小多少，就显得小多少）
func _max_extent(key: String) -> float:
	var b := _box(key)
	return maxf(maxf(b.size.x, b.size.z), maxf(b.size.y, 0.05))


## 收走的一株：用一个普通节点摆在原处，往上一跳缩没（tick 里动）
func _leave(c: int, key: String, xf: Variant, delay: float) -> void:
	if key == "" or xf == null:
		return
	var holder := Node3D.new()
	add_child(holder)
	var n := _instance(key, holder)
	if n == null:
		holder.queue_free()
		return
	var t: Transform3D = xf
	var k0 := t.basis.get_scale().x
	n.transform = Transform3D(t.basis.orthonormalized(), Vector3.ZERO)
	n.scale = Vector3.ONE * k0
	var ground := cell_local(c) + Vector3(0.0, BASE_Y, 0.0)
	n.position = t.origin - ground
	holder.position = ground
	holder.visible = delay <= 0.0
	_leaving.append({"node": holder, "t": 0.0, "delay": delay, "y0": ground.y, "k0": 1.0})


# ---------- 场景里的几样 ----------

func _make_field(f: int) -> Dictionary:
	var r := Node3D.new()
	r.position = FIELDS[f]
	add_child(r)
	var ripe := MeshInstance3D.new()
	ripe.visible = false
	var rm := ShaderMaterial.new()
	rm.shader = WORLD_SHADER
	ripe.material_override = rm
	ripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(ripe)
	# 没开垦：一地荒草、南边一块木牌
	var la := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + f
	var hw := FIELD_W * 0.5 - 0.5
	for q in 44:
		var p := Vector3(rng.randf_range(-hw, hw), 0.0, rng.randf_range(-hw, hw))
		var h := rng.randf_range(0.35, 0.85)
		BlockWorld._box(la, Vector3(0.5, h, 0.5), Transform3D(Basis(Vector3.UP, rng.randf()), p + Vector3(0.0, h * 0.5, 0.0)),
				Color(0.50, 0.62, 0.30) * rng.randf_range(0.85, 1.1), 0.0, 0.8)
	var sz := FIELD_W * 0.5 + 0.45
	BlockWorld._box(la, Vector3(0.16, 1.3, 0.16), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, sz)), Color(0.42, 0.27, 0.16))
	BlockWorld._box(la, Vector3(1.6, 0.6, 0.1), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.15, sz + 0.07)), Color(0.86, 0.76, 0.56), 0.0, 1.0)
	var lock := Node3D.new()
	lock.add_child(_mesh(la, not mobile))
	r.add_child(lock)
	var ll := Label3D.new()
	ll.font = font
	ll.font_size = 52
	ll.pixel_size = 0.0042
	ll.modulate = Color(0.22, 0.14, 0.08)
	ll.outline_size = 0
	ll.double_sided = false
	ll.text = "%s期开垦" % str(Realm.LIST[int(FarmData.FIELD_REALM[f])]["name"])
	ll.position = Vector3(0.0, 1.15, sz + 0.13)
	lock.add_child(ll)
	# 头顶一行字（长势）
	var lab := Label3D.new()
	lab.font = font
	lab.font_size = 44
	lab.pixel_size = 0.0078
	lab.outline_size = 12
	lab.outline_modulate = Color(0.08, 0.07, 0.09, 0.85)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0.0, 3.5, 0.0)
	lab.visible = false
	r.add_child(lab)
	return {"root": r, "label": lab, "lock": lock, "ripe": ripe, "ripe_sig": "", "ripe_n": 0}


## 播种时下一格的提示框：一圈发白光的细边
func _make_cursor() -> MeshInstance3D:
	var a := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	for q in 4:
		var bs := Basis(Vector3.UP, PI * 0.5 * float(q))
		BlockWorld._box(a, Vector3(MOUND + 0.16, 0.06, 0.1), Transform3D(bs, bs * Vector3(0.0, 0.03, MOUND * 0.5 + 0.06)), Color(0.96, 0.95, 0.86), 0.8, 1.0)
	return _mesh(a, false)


static func _array_mesh(a: Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh(a: Array, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _array_mesh(a)
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------- 界面：灵种背包 ----------

func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 40                  # 盖过触屏按钮（20）；洞府 / 选关界面在 60
	add_child(_ui)
	_th = Theme.new()
	_th.default_font = font
	_th.default_font_size = 20


func bag_open() -> bool:
	return _shade != null


## 老名字（hub_hall.gd 在用）
func panel_open() -> bool:
	return bag_open()


func close_panel() -> void:
	close_bag()


func open_bag() -> void:
	if bag_open():
		return
	_ensure_ui()
	_pick = seed_id()
	if FarmData.plant(_pick).is_empty():
		_pick = str(FarmData.PLANTS[0]["id"])
	_tab = 0 if str(FarmData.plant(_pick)["out"]) == "herb" else 1
	_shade = ColorRect.new()
	_shade.color = Color(0.05, 0.04, 0.06, 0.28)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.add_to_group("touch_ui")
	_shade.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			close_bag.call_deferred())
	_ui.add_child(_shade)
	var t := _touch()
	if t != null and not bool(t.get("blocked")):
		t.set("blocked", true)          # 背包开着时触屏层不接管（摇杆、按钮都让给背包）
		_touch_blocked = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_was_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_bag()
	Sfx.play("ui_click", -6.0)


func close_bag() -> void:
	if _shade == null:
		return
	_shade.queue_free()
	_shade = null
	if _touch_blocked:
		_touch_blocked = false
		var t := _touch()
		if t != null:
			t.set("blocked", false)
	if _mouse_was_captured:
		_mouse_was_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 点「选择」：手里拿上背包里点中的那一种
func choose(id: String) -> String:
	var p := FarmData.plant(id)
	if p.is_empty():
		return "没有这种灵种"
	if Profile.realm() < int(p["realm"]):
		return "%s要%s期才种得活" % [p["name"], str(Realm.LIST[int(p["realm"])]["name"])]
	data()["seed"] = id
	_save_t = 0.05
	close_bag()
	_say("手里拿着 %s 的灵种 · 走到空灵田上按「播种」（按住一格格接着种）" % p["name"], 2.6)
	return ""


## 背包里点一种（还没拿到手上）
func pick(id: String) -> void:
	_pick = id
	if bag_open():
		_build_bag()


func set_tab(t: int) -> void:
	_tab = t
	if (str(FarmData.plant(_pick).get("out", "")) == "herb") != (t == 0):
		for p: Dictionary in FarmData.PLANTS:
			if (str(p["out"]) == "herb") == (t == 0):
				_pick = str(p["id"])
				break
	if bag_open():
		_build_bag()


func _build_bag() -> void:
	for ch in _shade.get_children():
		ch.queue_free()
	var mine := Profile.realm()
	var sel := FarmData.plant(_pick)
	# 右边：灵种背包
	var bag := PanelContainer.new()
	bag.theme = _th
	bag.add_theme_stylebox_override("panel", UiStyle.scroll(10.0, false))
	bag.mouse_filter = Control.MOUSE_FILTER_STOP
	bag.add_to_group("touch_ui")
	bag.anchor_left = 1.0
	bag.anchor_right = 1.0
	bag.anchor_bottom = 1.0
	bag.offset_left = -BAG_W - 24.0
	bag.offset_right = -24.0
	bag.offset_top = 56.0
	bag.offset_bottom = -26.0
	_shade.add_child(bag)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	bag.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	for ti in 2:
		var tb := _button(["灵 草", "灵 果"][ti], 140.0, ti == _tab)
		var tv := ti
		tb.pressed.connect(func() -> void: set_tab(tv))
		head.add_child(tb)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_icon_rect(UiStyle.icon("lingshi"), 34.0))
	head.add_child(_lbl(str(Profile.lingshi()), 24, UiStyle.TEXT_INK))
	var close := _button("关 闭", 116.0, false)
	close.pressed.connect(close_bag)
	head.add_child(close)
	box.add_child(UiStyle.rule(BAG_W - 70.0, 9.0))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for p: Dictionary in FarmData.PLANTS:
		if (str(p["out"]) == "herb") == (_tab == 0):
			grid.add_child(_card(p, str(p["id"]) == _pick, mine < int(p["realm"])))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var hint := _lbl("选好以后到空灵田上按「播种」，按住不放一格格接着种；熟了按「收获」一下收一整块", 18, UiStyle.TEXT_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var locked := not sel.is_empty() and mine < int(sel["realm"])
	var go := _button(("需%s期" % str(Realm.LIST[int(sel["realm"])]["name"])) if locked else "选 择", 210.0, not locked)
	go.custom_minimum_size.y = 66.0
	go.disabled = locked or sel.is_empty()
	go.pressed.connect(func() -> void:
		var err := choose(_pick)
		if err != "":
			_say(err))
	foot.add_child(go)
	# 左边：点中那一种的详情
	if sel.is_empty():
		return
	var det := PanelContainer.new()
	det.theme = _th
	det.add_theme_stylebox_override("panel", UiStyle.plaque(0.98, 1, 16.0))
	det.mouse_filter = Control.MOUSE_FILTER_STOP
	det.add_to_group("touch_ui")
	det.anchor_left = 1.0
	det.anchor_right = 1.0
	det.offset_left = -BAG_W - 24.0 - 18.0 - DET_W
	det.offset_right = -BAG_W - 24.0 - 18.0
	det.offset_top = 96.0
	_shade.add_child(det)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	det.add_child(dv)
	var t := int(sel["tier"])
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_child(th)
	var tag := _lbl(str(Data.TIER_NAMES[t]), 18, UiStyle.PAPER)
	var tagbox := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.on_paper(Data.TIER_COLORS[t]).darkened(0.15)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	tagbox.add_theme_stylebox_override("panel", sb)
	tagbox.add_child(tag)
	tagbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(tagbox)
	th.add_child(_lbl(str(sel["name"]), 30, UiStyle.TEXT_INK))
	var pic := PanelContainer.new()
	pic.add_theme_stylebox_override("panel", UiStyle.slot(false, false))
	dv.add_child(pic)
	var big := _icon_rect(FarmData.icon(sel), 200.0)
	big.custom_minimum_size = Vector2(DET_W - 60.0, 200.0)
	pic.add_child(big)
	var n: Array = sel["n"]
	var ns := ("%d" % int(n[0])) if int(n[0]) == int(n[1]) else ("%d~%d" % [int(n[0]), int(n[1])])
	var val := int(Items_value(sel))
	var rows := [["灵种", "%d 灵石 / 株" % int(sel["price"])], ["收获", "%s ×%s / 株" % [FarmData.out_name(sel), ns]],
			["卖出", "每个 %d 灵石" % val], ["周期", FarmData.dur_text(float(sel["grow"]))],
			["境界", ("%s期起可种" % str(Realm.LIST[int(sel["realm"])]["name"])) if not locked else ("要%s期才种得活" % str(Realm.LIST[int(sel["realm"])]["name"]))]]
	for r: Array in rows:
		var rh := HBoxContainer.new()
		var rb := PanelContainer.new()
		rb.add_theme_stylebox_override("panel", UiStyle.slot(true, false))
		rb.add_child(rh)
		dv.add_child(rb)
		var kl := _lbl(str(r[0]), 19, UiStyle.TEXT_SOFT)
		kl.custom_minimum_size.x = 70.0
		rh.add_child(kl)
		var vl := _lbl(str(r[1]), 21, UiStyle.CINNABAR if (str(r[0]) == "境界" and locked) else UiStyle.TEXT_INK)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rh.add_child(vl)
	var use := _lbl(FarmData.use_line(sel).split("；")[0], 18, UiStyle.TEXT_SOFT)
	use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	use.custom_minimum_size.x = DET_W - 40.0
	dv.add_child(use)


static func Items_value(p: Dictionary) -> int:
	if str(p["out"]) == "herb":
		return int(FarmData.Items.herb(int(p["tier"]))["value"])
	return int(FarmData.fruit(str(p["out"]))["value"])


## 背包里的一张灵种卡：品阶、价钱、图标、名字、成熟时间
func _card(p: Dictionary, selected: bool, locked: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(172, 214)
	b.focus_mode = Control.FOCUS_NONE
	b.add_to_group("touch_ui")
	b.add_theme_stylebox_override("normal", UiStyle.slot(false, selected))
	b.add_theme_stylebox_override("hover", UiStyle.slot(false, true))
	b.add_theme_stylebox_override("pressed", UiStyle.slot(false, true))
	var pid := str(p["id"])
	b.pressed.connect(func() -> void:
		Sfx.play("ui_click", -8.0)
		pick(pid))
	var t := int(p["tier"])
	var tag := _lbl(str(Data.TIER_NAMES[t]), 15, UiStyle.on_paper(Data.TIER_COLORS[t]).darkened(0.25))
	tag.position = Vector2(10, 6)
	b.add_child(tag)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(_icon_rect(UiStyle.icon("lingshi"), 20.0))
	pr.add_child(_lbl(str(int(p["price"])), 16, UiStyle.TEXT_SOFT))
	pr.position = Vector2(118, 4)
	b.add_child(pr)
	var ic := _icon_rect(FarmData.icon(p), 128.0)
	ic.position = Vector2(22, 24)
	ic.size = Vector2(128, 128)
	if locked:
		ic.modulate = Color(1, 1, 1, 0.32)
	b.add_child(ic)
	var nm := _lbl(str(p["name"]), 19, UiStyle.TEXT_SOFT if locked else UiStyle.TEXT_INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(0, 150)
	nm.size = Vector2(172, 26)
	b.add_child(nm)
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(UiStyle.CINNABAR, 0.12) if locked else Color(UiStyle.LINE, 0.08)
	ps.set_corner_radius_all(14)
	ps.content_margin_left = 10.0
	ps.content_margin_right = 10.0
	pill.add_theme_stylebox_override("panel", ps)
	pill.position = Vector2(18, 178)
	pill.custom_minimum_size = Vector2(136, 28)
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.add_theme_constant_override("separation", 6)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(ph)
	if locked:
		ph.add_child(_lbl("需%s期" % str(Realm.LIST[int(p["realm"])]["name"]), 16, UiStyle.CINNABAR))
	else:
		ph.add_child(_clock(18.0, UiStyle.TEXT_SOFT))
		ph.add_child(_lbl(FarmData.dur_text(float(p["grow"])), 16, UiStyle.TEXT_INK))
	b.add_child(pill)
	return b


func _clock(sz: float, col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(sz, sz)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var r := sz * 0.5 - 1.5
		var o := Vector2(sz * 0.5, sz * 0.5)
		c.draw_arc(o, r, 0.0, TAU, 24, col, 1.8, true)
		c.draw_line(o, o + Vector2(0.0, -r * 0.62), col, 1.8, true)
		c.draw_line(o, o + Vector2(r * 0.5, 0.0), col, 1.8, true))
	return c


func _icon_rect(tex: Texture2D, sz: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(sz, sz)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, w: float, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 23)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_to_group("touch_ui")
	if primary:
		UiStyle.style_primary(b)
	else:
		UiStyle.style_button(b, true)
	return b


# ---------- 界面：手里的灵种、收获小条 ----------

## 手里拿着的灵种：触屏放在「攻」左边（农场里「御」收起来了，那块空着），桌面放在底部按钮上面；点它也能打开背包
func _tick_chip() -> void:
	var p := FarmData.plant(seed_id())
	var show := on and not blocked and not bag_open() and not p.is_empty()
	if not show:
		if _chip != null:
			_chip.visible = false
		return
	_ensure_ui()
	if _chip == null or _chip_id != str(p["id"]):
		if _chip != null:
			_chip.queue_free()
		_chip_id = str(p["id"])
		_chip = Button.new()
		_chip.theme = _th
		_chip.focus_mode = Control.FOCUS_NONE
		_chip.add_to_group("touch_ui")
		for k: String in ["normal", "hover", "pressed"]:
			_chip.add_theme_stylebox_override(k, UiStyle.plaque(0.94 if k == "normal" else 1.0, 1, 8.0))
		_chip.pressed.connect(open_bag)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.position = Vector2(10, 6)
		_chip.add_child(h)
		h.add_child(_icon_rect(FarmData.icon(p), 52.0))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		v.add_child(_lbl("灵种 · %s" % p["name"], 19, UiStyle.TEXT_INK))
		v.add_child(_lbl("%d 灵石 / 株 · %s" % [int(p["price"]), FarmData.dur_text(float(p["grow"]))], 15, UiStyle.TEXT_SOFT))
		_ui.add_child(_chip)
		_chip.custom_minimum_size = Vector2(250, 66)
		_chip.set_meta("row", h)
	_chip.visible = true
	var vs := get_viewport().get_visible_rect().size
	var row := _chip.get_meta("row") as Control
	var sz := Vector2(maxf(row.size.x + 22.0, 250.0), 66.0)
	_chip.size = sz
	if _touch() != null:
		_chip.position = Vector2(vs.x - 272.0 - sz.x, vs.y - 92.0 - sz.y)
	else:
		_chip.position = Vector2((vs.x - sz.x) * 0.5, vs.y - 192.0 - sz.y)


## 收获以后头顶飘一张小条：每样东西一行「图标 +N 名字」，底下一行仓库还剩多少
func _show_gain(got: Dictionary, left: int) -> void:
	_ensure_ui()
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _th
	_ui.add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var head := _lbl("灵田收获", 24, UiStyle.TEXT)
	head.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 0.9))
	head.add_theme_constant_override("outline_size", 8)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for nm: String in got.keys():
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", UiStyle.plaque(0.96, 1, 8.0))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(pill)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(h)
		var pp := FarmData.plant_of_out(nm)
		h.add_child(_icon_rect(FarmData.icon(pp) if not pp.is_empty() else UiStyle.icon("herb"), 54.0))
		h.add_child(_lbl("+%d" % int(got[nm]), 36, UiStyle.CINNABAR))
		h.add_child(_lbl(nm, 20, UiStyle.TEXT_INK))
	var foot := _lbl(("仓库满了，还有 %d 株留在地里" % left) if left > 0 else ("已入仓库 · 占 %d/%d 格" % [Profile.stash_slots(), Profile.STASH_CAP]), 18, UiStyle.TEXT)
	foot.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 0.9))
	foot.add_theme_constant_override("outline_size", 6)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)
	var vs := get_viewport().get_visible_rect().size
	var at := Vector2(vs.x * 0.5, vs.y * 0.36)
	var cam := get_viewport().get_camera_3d()
	var head_w := to_global(_pos + Vector3(0.0, 3.0, 0.0))
	if cam != null and not cam.is_position_behind(head_w):
		at = cam.unproject_position(head_w)
		at.y = clampf(at.y, 150.0, vs.y - 260.0)
	root.position = at
	root.scale = Vector2.ONE * 0.7
	_gains.append({"root": root, "box": box, "t": 0.0})


func _tick_gains(dt: float) -> void:
	var i := _gains.size() - 1
	while i >= 0:
		var G: Dictionary = _gains[i]
		G["t"] = float(G["t"]) + dt
		var t := float(G["t"])
		var root := G["root"] as Control
		var box := G["box"] as Control
		if t >= 2.4 or not on:
			root.queue_free()
			_gains.remove_at(i)
		else:
			box.size = box.get_combined_minimum_size()
			box.position = Vector2(-box.size.x * 0.5, -box.size.y - 70.0 * minf(t / 2.4, 1.0))
			root.pivot_offset = Vector2.ZERO
			var pop := minf(t / 0.16, 1.0)
			root.scale = Vector2.ONE * (0.7 + 0.3 * pop + 0.08 * sin(pop * PI))
			root.modulate.a = 1.0 if t < 1.8 else 1.0 - (t - 1.8) / 0.6
		i -= 1
