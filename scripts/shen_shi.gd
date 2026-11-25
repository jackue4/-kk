extends Node3D
## 神识（2026-11-23，用户定的方向：神识扫描资源和其他玩家；点小地图主动一扫；境界越高扫得越远、表现越强）。挂在 raid_manager.gd 下（mgr.shenshi）。
##
## 两种用法：
##   · 被动神识：一直开着，半径内的搜点自动探明、标上小地图（raid_search.gd 的 tick 读 passive_r()；原来是写死的 70 米）
##   · 主动「神识一扫」：点小地图（键盘 C）。一道光波从脚下贴着地形扫出去（地表 / 水面着色器里画，见 shaders/shenshi_wave.gdshaderinc），
##     身周荡开几道七彩光环 + 空间波动（shenshi_ring），几条光带顺着山势往外窜（shenshi_ribbon），几缕气丝绕身盘旋。
##     波前扫到哪，哪里的东西就被「揭示」：
##       - 有模型的目标挂一份「影子网格」（同网格、同骨架，跟着动画走）：头几秒透视（隔山可见，shenshi_xray），之后留一道描边（shenshi_line）
##       - 重点目标脚下立一道细光柱、头上一颗菱形光点（shenshi_mark，不做深度测试）：远处、还没建出模型的也知道大致方位
##       - 小地图上按品阶 / 种类的颜色一圈圈闪（minimap.gd 读 map_marks()）
## 扫得到什么：搜点（没搜过的）、地上的掉落和箱子、精英 / 首领、其他修士（AI）、别队的真人、亮着的传送阵（顺带探明）。
##   修士和真人只看得到境界不比自己高出一档以上的（神识压不过的探不到，结束时提示「有 N 位修士神识在你之上」）。
## 境界档位见 TIERS：半径、冷却、透视 / 标记时长之外，光环圈数、光带条数、电弧、七彩、颜色逐档拉开（不是整体乘一个数，见 [[realm-tier-differentiation]]）。
## 手机档（lite）：光带 / 气丝减半，影子网格限量更紧；光环不读屏幕（着色器里分支）。地形光波只是地表着色器里多一段、不扫时整段跳过。
## 自检：`-- --raid-shot --shenshi [--touch]`（scripts/shenshi_selftest.gd）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Search := preload("res://scripts/raid_search.gd")
const Sfx := preload("res://scripts/sfx.gd")
const RING_SH := preload("res://shaders/shenshi_ring.gdshader")
const RIBBON_SH := preload("res://shaders/shenshi_ribbon.gdshader")
const XRAY_SH := preload("res://shaders/shenshi_xray.gdshader")
const LINE_SH := preload("res://shaders/shenshi_line.gdshader")
const MARK_SH := preload("res://shaders/shenshi_mark.gdshader")

## 各境界的神识（下标 = 境界：炼气 … 大乘）
## r 一扫半径（米） | see 被动探明搜点的半径 | cd 冷却（秒） | hold 标记留多久 | xray 透视几秒
## band 地形光波的波带半宽 | jit 电弧抖动 | irid 七彩 | glow 亮度 | rings 身周光环圈数 | ribbons 地面光带条数 | wisps 身周气丝
## aura 第一道光环的半径（米） | warp 空间扭曲（桌面档读屏幕） | a / b 主色 / 副色
const TIERS: Array = [
	{"r": 80.0, "see": 70.0, "cd": 30.0, "hold": 12.0, "xray": 3.0, "band": 3.0, "jit": 0.0, "irid": 0.15, "glow": 0.62,
	 "rings": 1, "ribbons": 0, "wisps": 2, "aura": 3.2, "warp": 0.03, "a": Color(0.84, 0.94, 1.0), "b": Color(0.6, 0.82, 1.0)},       # 炼气：素白微蓝，一道光环
	{"r": 110.0, "see": 80.0, "cd": 28.0, "hold": 13.0, "xray": 3.2, "band": 3.5, "jit": 0.15, "irid": 0.25, "glow": 0.7,
	 "rings": 1, "ribbons": 2, "wisps": 3, "aura": 3.8, "warp": 0.035, "a": Color(0.78, 1.0, 0.92), "b": Color(0.42, 0.92, 0.78)},     # 筑基：青玉
	{"r": 150.0, "see": 90.0, "cd": 26.0, "hold": 14.0, "xray": 3.5, "band": 4.2, "jit": 0.3, "irid": 0.4, "glow": 0.78,
	 "rings": 2, "ribbons": 3, "wisps": 3, "aura": 4.5, "warp": 0.04, "a": Color(0.82, 0.96, 1.0), "b": Color(1.0, 0.84, 0.5)},       # 结丹：青金
	{"r": 190.0, "see": 100.0, "cd": 24.0, "hold": 15.0, "xray": 3.8, "band": 5.0, "jit": 0.45, "irid": 0.6, "glow": 0.86,
	 "rings": 2, "ribbons": 4, "wisps": 4, "aura": 5.2, "warp": 0.05, "a": Color(0.72, 0.88, 1.0), "b": Color(0.98, 0.82, 0.45)},      # 元婴：青金蓝紫
	{"r": 230.0, "see": 110.0, "cd": 22.0, "hold": 16.0, "xray": 4.1, "band": 5.8, "jit": 0.6, "irid": 0.72, "glow": 0.94,
	 "rings": 3, "ribbons": 5, "wisps": 5, "aura": 6.0, "warp": 0.055, "a": Color(0.78, 0.84, 1.0), "b": Color(0.82, 0.6, 1.0)},       # 化神：蓝紫
	{"r": 270.0, "see": 120.0, "cd": 20.0, "hold": 17.0, "xray": 4.4, "band": 6.6, "jit": 0.72, "irid": 0.82, "glow": 1.0,
	 "rings": 3, "ribbons": 6, "wisps": 5, "aura": 6.8, "warp": 0.06, "a": Color(0.88, 0.82, 1.0), "b": Color(1.0, 0.76, 0.56)},       # 炼虚：紫金
	{"r": 310.0, "see": 130.0, "cd": 18.0, "hold": 18.0, "xray": 4.7, "band": 7.4, "jit": 0.86, "irid": 0.92, "glow": 1.07,
	 "rings": 4, "ribbons": 7, "wisps": 6, "aura": 7.6, "warp": 0.07, "a": Color(1.0, 0.93, 0.78), "b": Color(0.7, 0.8, 1.0)},         # 合体：金白
	{"r": 360.0, "see": 140.0, "cd": 16.0, "hold": 20.0, "xray": 5.0, "band": 8.2, "jit": 1.0, "irid": 1.0, "glow": 1.15,
	 "rings": 4, "ribbons": 8, "wisps": 7, "aura": 8.5, "warp": 0.08, "a": Color(1.0, 0.96, 0.88), "b": Color(0.86, 0.76, 1.0)},       # 大乘：满七彩
]
## 搜点的轻重（决定谁先分到描边 / 光柱）
const SITE_PRIO := {"vault": 7.5, "urn": 6.5, "grave": 4.0, "herb": 3.0, "jar": 2.0}
const GHOST_CAP := 26             # 最多几个目标挂影子网格（手机档 14）
const GHOST_CAP_LITE := 14
const MESH_CAP := 320             # 影子网格总数上限（一个方块人二十来件 × 2）
const MESH_CAP_LITE := 160
const BEAM_CAP := 16              # 最多几道光柱（手机档 10）
const BEAM_CAP_LITE := 10
const COL_ELITE := Color(1.0, 0.62, 0.22)
const COL_BOSS := Color(1.0, 0.3, 0.22)
const COL_FOE := Color(1.0, 0.32, 0.26)
const COL_WHITE := Color(0.86, 0.9, 1.0)

var mgr: Node3D                   # raid_manager.gd
var lite := false

var cd_left := 0.0                # 冷却还剩几秒
var cd_total := 30.0
var wave_on := false              # 地形光波还在扫（含收尾淡出）
var wave_t := 0.0
var wave_dur := 1.5
var wave_r := 0.0                 # 当前波前半径
var wave_max := 80.0
var center := Vector3.ZERO
var cur: Dictionary = TIERS[0]    # 这一扫的档位
var cur_realm := 0
var scans := 0                    # 一共扫了几次（自检看）
var found := {}                   # 这一扫揭示了什么：种类 → 个数
var hidden := 0                   # 这一扫有几位修士神识在我之上（探不到）
var marks: Array = []             # 已揭示的目标（见 _collect 里的字段）
var _queue: Array = []            # 等着波前扫到的目标（按距离从近到远）
var _by_key := {}
var _fx: Array = []               # 光环 / 光带 / 气丝：{node, mat, t, life, type: 0 光环 / 1 光带 / 2 气丝, ...}
var _fade := 0.0
var _tick := 0.0
var _mesh_n := 0                  # 现在挂着的影子网格数
var _quad: QuadMesh


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	lite = Vfx.lite or (mgr != null and bool(mgr.get("mobile")))


func _exit_tree() -> void:
	_set_world(0.0)


func tier_of(realm: int) -> Dictionary:
	return TIERS[clampi(realm, 0, TIERS.size() - 1)]


## 被动神识的半径（raid_search.gd 用来自动探明搜点；法宝「识」在那边另乘）
func passive_r() -> float:
	if mgr == null or mgr.player == null:
		return 70.0
	return float(tier_of(int(mgr.player.realm_idx))["see"])


## 现在点一下能扫多远（法宝「识」加三成到五成，封顶）
func scan_r() -> float:
	var realm := 0 if mgr == null or mgr.player == null else int(mgr.player.realm_idx)
	var seek := 0.0
	if mgr != null and mgr.get("fx") != null:
		seek = minf(float(mgr.fx.get("seek", 0.0)), 1.0)
	return float(tier_of(realm)["r"]) * (1.0 + 0.5 * seek)


func is_ready() -> bool:
	return cd_left <= 0.0


## 冷却进度：1 = 好了
func ready_k() -> float:
	return 1.0 - clampf(cd_left / maxf(cd_total, 0.01), 0.0, 1.0)


# ---------- 发动 ----------

## 主动一扫（小地图点按 / 键盘 C）。扫不了返回 false（冷却中会提示）
func scan() -> bool:
	if mgr == null or mgr.player == null or not bool(mgr.running):
		return false
	if mgr.trib_active() or not mgr.player.is_alive():
		return false
	if cd_left > 0.0:
		if mgr.hud != null:
			mgr.hud.toast("神识尚未复原（%d 秒）" % ceili(cd_left), Color(0.78, 0.8, 0.86))
		return false
	cur_realm = clampi(int(mgr.player.realm_idx), 0, TIERS.size() - 1)
	cur = TIERS[cur_realm]
	wave_max = scan_r()
	wave_dur = 1.1 + wave_max / 260.0
	cd_total = float(cur["cd"])
	cd_left = cd_total
	center = mgr.player.global_position
	wave_on = true
	wave_t = 0.0
	wave_r = 0.0
	_fade = 0.0
	scans += 1
	found = {}
	hidden = 0
	_collect()
	_world_colors()
	_spawn_aura()
	_spawn_ribbons()
	_spawn_wisps()
	Sfx.play("perfect", -7.0, 0.7 + 0.03 * float(cur_realm))
	return true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).physical_keycode == KEY_C:
		scan()


# ---------- 找目标 ----------

## 这一扫半径里的东西：按轻重分好谁挂影子网格、谁立光柱，再按距离排队等波前
func _collect() -> void:
	_queue.clear()
	var c2 := Vector2(center.x, center.z)
	var list: Array = []
	var my := cur_realm
	# 搜点（没搜过的；位置 raid_search.tick 每 0.4 秒换到离主角最近的像）
	var se: Variant = mgr.get("search")
	if se != null and is_instance_valid(se):
		for s: Dictionary in se.sites:
			if bool(s["done"]) or not bool(s["live"]):
				continue
			var sp: Vector3 = s["pos"]
			var sd := c2.distance_to(Vector2(sp.x, sp.z))
			if sd > wave_max:
				continue
			var kind := str(s["kind"])
			var info: Dictionary = Search.KINDS[kind]
			list.append({"key": "s%d" % int(s["id"]), "type": "site", "kind": kind, "site": s, "node": s["node"], "pos": sp, "d": sd,
					"col": info["col"], "prio": float(SITE_PRIO.get(kind, 2.0)), "lift": 4.2 if kind == "vault" else 2.8})
	# 地上的掉落 / 箱子
	for pk: Variant in mgr._pickups:
		if not is_instance_valid(pk):
			continue
		var pp: Vector3 = (pk as Node3D).global_position
		var pd := c2.distance_to(Vector2(pp.x, pp.z))
		if pd > wave_max:
			continue
		var t := clampi(int(pk.tier()), 0, Data.TIER_COLORS.size() - 1)
		var chest: bool = pk.is_chest()
		list.append({"key": "p%d" % (pk as Node).get_instance_id(), "type": "drop", "kind": "chest" if chest else "item", "node": pk, "pos": pp, "d": pd,
				"col": Data.TIER_COLORS[t], "prio": (4.5 + float(t)) if chest else (1.0 + float(t)), "lift": 2.2 if chest else 1.4})
	# 精英 / 首领（自己名下的 + 别人名下的木偶）
	var mobs: Array = mgr._mobs + (mgr._puppets as Dictionary).values()
	for m: Variant in mobs:
		if not is_instance_valid(m) or not m.is_alive() or not (bool(m.elite) or bool(m.boss)):
			continue
		var mp: Vector3 = (m as Node3D).global_position
		var md := c2.distance_to(Vector2(mp.x, mp.z))
		if md > wave_max:
			continue
		var boss := bool(m.boss)
		list.append({"key": "m%d" % (m as Node).get_instance_id(), "type": "mob", "kind": "boss" if boss else "elite", "node": m, "pos": mp, "d": md,
				"col": COL_BOSS if boss else COL_ELITE, "prio": 8.0 if boss else 4.5, "lift": 6.0 if boss else 3.4})
	# 其他修士（AI）
	for f: Variant in mgr._rivals:
		if not is_instance_valid(f) or not f.is_alive():
			continue
		var fp: Vector3 = (f as Node3D).global_position
		var fd := c2.distance_to(Vector2(fp.x, fp.z))
		if fd > wave_max:
			continue
		if int(f.tier_realm()) > my + 1:
			hidden += 1
			continue
		var hostile := bool(f.hostile)
		list.append({"key": "f%d" % (f as Node).get_instance_id(), "type": "rival", "kind": "foe" if hostile else "white", "node": f, "pos": fp, "d": fd,
				"col": COL_FOE if hostile else COL_WHITE, "prio": 7.0 if hostile else 5.0, "lift": 2.8})
	# 别队的真人
	if mgr.net_on():
		for id: Variant in (mgr.net.remotes as Dictionary).keys():
			var r: Variant = mgr.net.remotes[id]
			if not is_instance_valid(r) or not r.is_alive() or bool(r.mate):
				continue
			var rp: Vector3 = (r as Node3D).global_position
			var rd := c2.distance_to(Vector2(rp.x, rp.z))
			if rd > wave_max:
				continue
			if int(r.realm_idx) > my + 1:
				hidden += 1
				continue
			list.append({"key": "r%d" % int(id), "type": "player", "kind": "player", "node": r, "pos": rp, "d": rd,
					"col": COL_FOE, "prio": 9.0, "lift": 2.8})
	# 亮着的传送阵（顺带探明）
	for i in (mgr._extracts as Array).size():
		var e: Dictionary = mgr._extracts[i]
		if not bool(e["active"]):
			continue
		var ep: Vector3 = e["pos"]
		var ed := c2.distance_to(Vector2(ep.x, ep.z))
		if ed > wave_max:
			continue
		list.append({"key": "e%d" % i, "type": "gate", "kind": str(e.get("kind", "gate")), "ex": e, "node": null, "pos": ep, "d": ed,
				"col": mgr.ex_col(str(e.get("kind", "gate"))), "prio": 6.0, "lift": 3.0})
	# 按轻重：前几名挂影子网格、立光柱
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["prio"]) > float(b["prio"]))
	var gcap := GHOST_CAP_LITE if lite else GHOST_CAP
	var bcap := BEAM_CAP_LITE if lite else BEAM_CAP
	var gn := 0
	var bn := 0
	for t: Dictionary in list:
		t["ghost"] = false
		t["beam"] = false
		if str(t["type"]) != "gate" and gn < gcap:
			t["ghost"] = true
			gn += 1
		# 光柱给要紧的（搜点里的陶罐 / 灵药圃、凡品单件不立，免得满地是柱子）
		if bn < bcap and float(t["prio"]) >= 3.5:
			t["beam"] = true
			bn += 1
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	_queue = list


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	if mgr == null:
		return
	cd_left = maxf(cd_left - dt, 0.0)
	if wave_on:
		_step_wave(dt)
	if not _fx.is_empty():
		_step_fx(dt)
	if not marks.is_empty():
		_step_marks(dt)


func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 1.7)


func _step_wave(dt: float) -> void:
	wave_t += dt
	var k := clampf(wave_t / wave_dur, 0.0, 1.0)
	wave_r = wave_max * _ease(k)
	while not _queue.is_empty() and float((_queue[0] as Dictionary)["d"]) <= wave_r + 2.0:
		_reveal(_queue.pop_front())
	var amp := 1.0
	if k >= 1.0:
		_fade += dt
		amp = 1.0 - clampf(_fade / 0.8, 0.0, 1.0)
	else:
		amp = clampf(wave_t / 0.15, 0.0, 1.0)
	_set_world(amp)
	if k >= 1.0 and _fade >= 0.8:
		wave_on = false
		_set_world(0.0)
		_report()


## 地表 / 水面材质的光波参数（两种材质各设一遍；材质是所有地块共用的一份）
func _world_mats() -> Array:
	var out: Array = []
	var lv: Variant = mgr.get("level")
	if lv == null or not is_instance_valid(lv):
		return out
	var w: Variant = lv.get("world")
	if w == null or not is_instance_valid(w):
		return out
	for key: String in ["mat", "_sea_mat"]:
		var m: Variant = w.get(key)
		if m is ShaderMaterial:
			out.append(m)
	return out


func _world_colors() -> void:
	var a: Color = cur["a"]
	var b: Color = cur["b"]
	for m: ShaderMaterial in _world_mats():
		m.set_shader_parameter("ss_col_a", Vector3(a.r, a.g, a.b))
		m.set_shader_parameter("ss_col_b", Vector3(b.r, b.g, b.b))
		m.set_shader_parameter("ss_max", wave_max)


func _set_world(amp: float) -> void:
	if mgr == null:
		return
	for m: ShaderMaterial in _world_mats():
		m.set_shader_parameter("ss_wave", Vector4(center.x, center.y, center.z, wave_r))
		m.set_shader_parameter("ss_look", Vector4(amp * float(cur["glow"]), float(cur["band"]), float(cur["jit"]), float(cur["irid"])))


## 扫完：一行提示扫到了什么
func _report() -> void:
	if mgr == null or mgr.hud == null:
		return
	var parts: Array = []
	var names := [["site", "搜点"], ["drop", "宝物"], ["mob", "妖王精英"], ["rival", "修士"], ["player", "道友"], ["gate", "传送阵"]]
	for nm: Array in names:
		var n := int(found.get(nm[0], 0))
		if n > 0:
			parts.append("%s %d" % [nm[1], n])
	var line := ("神识扫过 %d 米：" % int(wave_max)) + ("、".join(parts) if not parts.is_empty() else "四下空空")
	if hidden > 0:
		line += "（另有 %d 位修士神识在你之上，探不透）" % hidden
	mgr.hud.toast(line, (cur["a"] as Color).lerp(Color.WHITE, 0.2))


# ---------- 揭示 ----------

func _reveal(t: Dictionary) -> void:
	var key := str(t["key"])
	var typ := str(t["type"])
	found[typ] = int(found.get(typ, 0)) + 1
	if typ == "site":
		(t["site"] as Dictionary)["known"] = true
	elif typ == "gate":
		(t["ex"] as Dictionary)["known"] = true
	if _by_key.has(key):
		# 上一扫的标记还在：重新计时、再透视一次
		var old: Dictionary = _by_key[key]
		old["age"] = 0.0
		old["hold"] = float(cur["hold"])
		old["xray"] = float(cur["xray"])
		if bool(t["ghost"]) and not bool(old.get("ghost", false)):
			old["ghost"] = true
		if bool(t["beam"]) and not is_instance_valid(old.get("beam_node")):
			old["beam"] = true
			_make_beam(old)
		_show_xray(old, true)
		return
	t["age"] = 0.0
	t["hold"] = float(cur["hold"])
	t["xray"] = float(cur["xray"])
	t["ghosts"] = []
	t["xghosts"] = []
	t["attached"] = false
	if bool(t["ghost"]):
		_attach(t)
	if bool(t["beam"]):
		_make_beam(t)
	marks.append(t)
	_by_key[key] = t


## 目标身上要描的那些网格
func _sources(t: Dictionary) -> Array:
	var node: Variant = t["node"]
	var out: Array = []
	if node == null or not is_instance_valid(node):
		return out
	var roots: Array = []
	match str(t["type"]):
		"site":
			# 2026-11-25 W4：get_meta(键, null) 在 4.7 下缺键会报 ERROR（null 不算默认值），先 has_meta
			var ring: Variant = (node as Node).get_meta("ring") if (node as Node).has_meta("ring") else null
			var beam: Variant = (node as Node).get_meta("beam") if (node as Node).has_meta("beam") else null
			for c: Node in (node as Node).get_children():
				if c is Label3D or c == ring or c == beam or not (c is Node3D):
					continue
				if not (c as Node3D).visible:
					continue
				roots.append(c)
		"drop":
			var bx: Variant = node.get("_box")
			roots.append(bx if bx != null and is_instance_valid(bx) else node)
		"mob":
			var body: Variant = node.get("_body")
			roots.append(body if body != null and is_instance_valid(body) else node)
		"rival", "player":
			var hero: Variant = node.get("hero")
			if hero != null and is_instance_valid(hero):
				roots.append(hero)
	for r: Node in roots:
		if r is MeshInstance3D:
			out.append(r)
		for n: Node in r.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or mi.get_script() != null or mi.has_meta("shenshi_ghost"):
				continue
			out.append(mi)
	return out


func _attach(t: Dictionary) -> void:
	var srcs := _sources(t)
	if srcs.is_empty():
		return
	var cap := MESH_CAP_LITE if lite else MESH_CAP
	if _mesh_n + srcs.size() * 2 > cap:
		return
	var col: Color = t["col"]
	var xm := ShaderMaterial.new()
	xm.shader = XRAY_SH
	xm.render_priority = 20
	xm.set_shader_parameter("tint", col)
	xm.set_shader_parameter("power", 0.0)
	var lm := ShaderMaterial.new()
	lm.shader = LINE_SH
	lm.set_shader_parameter("tint", col)
	lm.set_shader_parameter("power", 0.0)
	var corner := str(t["type"]) in ["rival", "player"]
	if corner:
		# 换了皮肤模型的主角（hero_skin.gd）是带骨骼的网格，没有方块角的方向可用：和资源库模型一样沿磨平的法线撑
		for src: MeshInstance3D in srcs:
			if src.skin != null:
				corner = false
				break
	lm.set_shader_parameter("corner", 1.0 if corner else 0.0)
	lm.set_shader_parameter("width", 0.04 if str(t["type"]) in ["rival", "player"] else 0.06)
	var gs: Array = t["ghosts"]
	var xs: Array = t["xghosts"]
	for src: MeshInstance3D in srcs:
		xs.append(_ghost(src, xm))
		# 描边那一份：资源库模型是低多边形、每个面各自一套法线，直接沿法线撑会裂成一片片浮壳 → 用法线磨平的副本（按模型缓存）
		gs.append(_ghost(src, lm, null if corner else smooth_mesh(src.mesh)))
	_mesh_n += srcs.size() * 2
	t["xm"] = xm
	t["lm"] = lm
	t["attached"] = true


## 法线磨平的网格副本：同一位置上的几个顶点（面与面的接缝）法线取平均，撑出去的描边壳是连着的。骨骼 / 权重原样带着，照样跟动画。
## 按原网格缓存（同种怪 / 同种罐子共用一份），第一次见到某个模型时算一遍（几千个顶点，几毫秒；载入预热里先算了本区的怪）
static var _smooth := {}


static func smooth_mesh(src: Mesh) -> Mesh:
	if src == null:
		return src
	var id := src.get_instance_id()
	if _smooth.has(id):
		return _smooth[id]
	var am := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv: Variant = arr[Mesh.ARRAY_NORMAL]
		if nv is PackedVector3Array and (nv as PackedVector3Array).size() == verts.size():
			var norms: PackedVector3Array = nv
			var acc := {}
			for i in verts.size():
				acc[verts[i]] = (acc.get(verts[i], Vector3.ZERO) as Vector3) + norms[i]
			for i in verts.size():
				var n: Vector3 = acc[verts[i]]
				if n.length_squared() > 1e-8:
					norms[i] = n.normalized()
			arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TANGENT] = null
		var prim := Mesh.PRIMITIVE_TRIANGLES
		var flags := 0
		if src is ArrayMesh:
			prim = (src as ArrayMesh).surface_get_primitive_type(si)
			flags = (src as ArrayMesh).surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		am.add_surface_from_arrays(prim, arr, [], {}, flags)
	_smooth[id] = am
	return am


## 影子网格：挂在原网格下面（变换一样，跟着它动）；有骨架的接同一副骨架，跟着动画走
func _ghost(src: MeshInstance3D, mat: Material, mesh: Mesh = null) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	g.mesh = mesh if mesh != null else src.mesh
	g.material_override = mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.extra_cull_margin = maxf(src.extra_cull_margin, 2.0)
	g.set_meta("shenshi_ghost", true)
	src.add_child(g)
	if src.skin != null:
		g.skin = src.skin
		var sk := src.get_node_or_null(src.skeleton)
		if sk != null:
			g.skeleton = g.get_path_to(sk)
	else:
		g.skeleton = NodePath("")
	return g


func _show_xray(t: Dictionary, on: bool) -> void:
	for g: Variant in t["xghosts"]:
		if is_instance_valid(g):
			(g as Node3D).visible = on


## 光柱 + 菱形光点（挂在自己下面，每帧跟着目标走）
func _make_beam(t: Dictionary) -> void:
	var h := Node3D.new()
	add_child(h)
	h.global_position = t["pos"]
	var col: Color = t["col"]
	var big := float(t["prio"]) >= 6.0
	var mats: Array = []
	for g in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		var m := ShaderMaterial.new()
		m.shader = MARK_SH
		m.render_priority = 21
		m.set_shader_parameter("tint", col)
		m.set_shader_parameter("power", 0.0)
		m.set_shader_parameter("glyph", float(g))
		m.set_shader_parameter("height", 40.0 if big else 24.0)
		m.set_shader_parameter("lift", float(t["lift"]))
		m.set_shader_parameter("px", 0.009 if g == 0 else 0.0095)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-4000.0, -200.0, -4000.0), Vector3(8000.0, 600.0, 8000.0))
		h.add_child(mi)
		mats.append(m)
	t["beam_node"] = h
	t["beam_mats"] = mats


func _alive(t: Dictionary) -> bool:
	match str(t["type"]):
		"site":
			return not bool((t["site"] as Dictionary)["done"])
		"gate":
			return bool((t["ex"] as Dictionary)["active"])
		"drop":
			return is_instance_valid(t["node"])
	var n: Variant = t["node"]
	return n != null and is_instance_valid(n) and bool(n.is_alive())


## 目标现在在哪（搜点 / 传送阵在循环世界里会换像，按字典里的位置；活物按节点）
func pos_of(t: Dictionary) -> Vector3:
	match str(t["type"]):
		"site":
			return (t["site"] as Dictionary)["pos"]
		"gate":
			return (t["ex"] as Dictionary)["pos"]
	var n: Variant = t["node"]
	if n != null and is_instance_valid(n):
		return (n as Node3D).global_position
	return t["pos"]


func _step_marks(dt: float) -> void:
	_tick -= dt
	var slow := _tick <= 0.0
	if slow:
		_tick = 0.4
	for i in range(marks.size() - 1, -1, -1):
		var t: Dictionary = marks[i]
		var age := float(t["age"]) + dt
		t["age"] = age
		var hold := float(t["hold"])
		if age >= hold or not _alive(t):
			_drop(i)
			continue
		var xr := float(t["xray"])
		var fin := clampf(age / 0.25, 0.0, 1.0)
		var xk := fin * (1.0 - clampf((age - (xr - 0.7)) / 0.7, 0.0, 1.0)) * (1.0 + 0.8 * exp(-age * 5.0))     # 扫到那一下先亮一闪
		var lk := fin * (1.0 - clampf((age - (hold - 1.5)) / 1.5, 0.0, 1.0))
		if slow and bool(t["ghost"]) and not bool(t["attached"]):
			# 揭示时模型还没建（搜点在 190 米外不建节点）：走近了建出来再挂上
			if str(t["type"]) == "site":
				t["node"] = (t["site"] as Dictionary)["node"]
			_attach(t)
		if bool(t["attached"]):
			(t["xm"] as ShaderMaterial).set_shader_parameter("power", xk)
			(t["lm"] as ShaderMaterial).set_shader_parameter("power", lk)
			if xk <= 0.0 and age > xr and bool(t.get("x_on", true)):
				t["x_on"] = false
				_show_xray(t, false)
			elif xk > 0.0 and not bool(t.get("x_on", true)):
				t["x_on"] = true
				_show_xray(t, true)
		var bn: Variant = t.get("beam_node")
		if bn != null and is_instance_valid(bn):
			(bn as Node3D).global_position = pos_of(t)
			for m: ShaderMaterial in t["beam_mats"]:
				m.set_shader_parameter("power", lk)
				m.set_shader_parameter("xray", clampf(xk, 0.0, 1.0))


func _drop(i: int) -> void:
	var t: Dictionary = marks[i]
	for g: Variant in (t["ghosts"] as Array) + (t["xghosts"] as Array):
		if is_instance_valid(g):
			(g as Node).queue_free()
			_mesh_n -= 1
	var bn: Variant = t.get("beam_node")
	if bn != null and is_instance_valid(bn):
		(bn as Node).queue_free()
	_by_key.erase(str(t["key"]))
	marks.remove_at(i)
	_mesh_n = maxi(_mesh_n, 0)


## 清掉所有标记（自检切境界时用）
func clear_marks() -> void:
	for i in range(marks.size() - 1, -1, -1):
		_drop(i)
	_queue.clear()


# ---------- 身周光环 / 地面光带 / 气丝 ----------

func _spawn_aura() -> void:
	var r := float(cur["aura"])
	var half := r / 0.24
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = RING_SH
	m.render_priority = -20         # 桌面档读屏幕：放在别的半透明特效之前画，身边的剑光、火花不会被它盖掉
	var life := 2.6 + 0.15 * float(cur_realm)
	m.set_shader_parameter("life", life)
	m.set_shader_parameter("power", float(cur["glow"]) * 1.15)
	m.set_shader_parameter("rings", float(cur["rings"]))
	m.set_shader_parameter("jit", float(cur["jit"]))
	m.set_shader_parameter("irid", float(cur["irid"]))
	m.set_shader_parameter("col_a", cur["a"])
	m.set_shader_parameter("col_b", cur["b"])
	m.set_shader_parameter("warp", float(cur["warp"]))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = _feet()
	_fx.append({"node": mi, "mat": m, "t": 0.0, "life": life, "type": 0})


func _feet() -> Vector3:
	return mgr.player.global_position + Vector3(0.0, 0.22, 0.0)


func _spawn_ribbons() -> void:
	var n := int(cur["ribbons"])
	if lite:
		n = (n + 1) / 2
	if n <= 0:
		return
	var c2 := Vector2(center.x, center.z)
	for i in n:
		var ang := TAU * float(i) / float(n) + randf_range(-0.35, 0.35)
		var length := wave_max * randf_range(0.7, 0.98)
		var step := 5.0 if not lite else 7.0
		var cnt := int(length / step) + 1
		var bend := randf_range(-0.7, 0.7)
		var lat_a := randf_range(5.0, 14.0)
		var hoff := randf_range(2.0, 4.5)
		var ph := randf() * TAU
		var pts := PackedVector3Array()
		for j in cnt:
			var s := float(j) * step
			var a := ang + bend * s / length
			var dv := Vector2(cos(a), sin(a))
			var lat := sin(s / 26.0 + ph) * lat_a * clampf(s / 30.0, 0.0, 1.0)
			var p2 := c2 + dv * s + Vector2(-dv.y, dv.x) * lat
			var y := float(mgr._ground(p2.x, p2.y)) + hoff + sin(s / 17.0 + ph) * 1.2
			if s < 8.0:
				y = lerpf(center.y + 0.6, y, s / 8.0)
			pts.append(Vector3(p2.x, y, p2.y))
		var w := randf_range(2.4, 4.4) * (0.85 + 0.06 * float(cur_realm))
		var mi := MeshInstance3D.new()
		mi.mesh = _strip(pts, w, randf() * 10.0)
		var m := _ribbon_mat(0.0, randf() * 10.0)
		m.set_shader_parameter("tail", 0.8)      # 拖得长：从脚下到波前一路都看得见，越往后越淡
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_fx.append({"node": mi, "mat": m, "t": 0.0, "life": wave_dur + 2.2, "type": 1, "len": length, "pw": float(m.get_shader_parameter("power"))})


func _spawn_wisps() -> void:
	var n := int(cur["wisps"])
	if lite:
		n = maxi((n + 1) / 2, 1)
	var r := float(cur["aura"])
	for i in n:
		var a0 := TAU * float(i) / float(n) + randf_range(-0.4, 0.4)
		var sweep := randf_range(2.2, 3.6) * (1.0 if i % 2 == 0 else -1.0)
		var r0 := r * randf_range(0.5, 0.9)
		var r1 := r * randf_range(1.2, 1.9)
		var h1 := randf_range(1.6, 3.4)
		var ph := randf() * TAU
		var pts := PackedVector3Array()
		var cnt := 26 if not lite else 18
		for j in cnt:
			var k := float(j) / float(cnt - 1)
			var a := a0 + sweep * k
			var rr := lerpf(r0, r1, k) + sin(k * 9.0 + ph) * 0.35
			pts.append(Vector3(cos(a) * rr, 0.25 + h1 * k * k + sin(k * 7.0 + ph) * 0.3, sin(a) * rr))
		var mi := MeshInstance3D.new()
		mi.mesh = _strip(pts, randf_range(0.7, 1.4), randf() * 10.0, true)
		var m := _ribbon_mat(1.0, randf() * 10.0)
		m.set_shader_parameter("tail", 0.55)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = mgr.player.global_position
		_fx.append({"node": mi, "mat": m, "t": -0.06 * float(i), "life": 1.9, "type": 2})


func _ribbon_mat(soft: float, seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RIBBON_SH
	m.set_shader_parameter("power", float(cur["glow"]) * (1.25 if soft < 0.5 else 0.9))
	m.set_shader_parameter("irid", float(cur["irid"]))
	m.set_shader_parameter("jit", float(cur["jit"]) * (1.0 - soft))
	m.set_shader_parameter("soft", soft)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("col_a", cur["a"])
	m.set_shader_parameter("col_b", cur["b"])
	m.set_shader_parameter("head", 0.0)
	return m


## 一条带子：沿 pts 铺开，横向是水平的（再慢慢扭一点）；UV.x 沿路径 0 → 1，UV.y 横跨
## local = true：气丝（点是相对主角的，横向改成朝上偏一点，看着像绕身盘旋）
func _strip(pts: PackedVector3Array, width: float, seed: float, local := false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := pts.size()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for j in n:
		var p := pts[j]
		var tan := (pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)])
		if tan.length() < 1e-4:
			tan = Vector3.FORWARD
		tan = tan.normalized()
		var side := tan.cross(Vector3.UP)
		if side.length() < 1e-3:
			side = Vector3.RIGHT
		side = side.normalized()
		var tw := sin(float(j) * 0.21 + seed) * (0.9 if local else 0.45)
		side = side.rotated(tan, tw)
		var k := float(j) / float(maxi(n - 1, 1))
		var ww := width * (0.35 + 0.65 * sin(PI * clampf(k * 1.15, 0.0, 1.0))) if local else width
		verts.append(p - side * ww * 0.5)
		verts.append(p + side * ww * 0.5)
		uvs.append(Vector2(k, 0.0))
		uvs.append(Vector2(k, 1.0))
		lo = lo.min(p)
		hi = hi.max(p)
		if j < n - 1:
			var b := j * 2
			for q: int in [b, b + 1, b + 2, b + 1, b + 3, b + 2]:
				idx.append(q)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(lo - Vector3.ONE * 4.0, hi - lo + Vector3.ONE * 8.0)
	return am


func _step_fx(dt: float) -> void:
	var speed := wave_max / maxf(wave_dur, 0.1)
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var t := float(f["t"]) + dt
		f["t"] = t
		var node: Variant = f["node"]
		if t >= float(f["life"]) or not is_instance_valid(node):
			if is_instance_valid(node):
				(node as Node).queue_free()
			_fx.remove_at(i)
			continue
		var m: ShaderMaterial = f["mat"]
		match int(f["type"]):
			0:
				(node as Node3D).global_position = _feet()
				m.set_shader_parameter("t", maxf(t, 0.0))
			1:
				# 地面光带：头部跟着地形光波的波前；波停了以后照原速度再窜出去一截
				var rr := wave_max * _ease(t / wave_dur) if t <= wave_dur else wave_max + (t - wave_dur) * speed * 0.6
				m.set_shader_parameter("head", rr / float(f["len"]))
				var life := float(f["life"])
				m.set_shader_parameter("power", float(f["pw"]) * (1.0 - clampf((t - (life - 1.0)) / 1.0, 0.0, 1.0)))
			2:
				(node as Node3D).global_position = mgr.player.global_position
				m.set_shader_parameter("head", clampf(t, 0.0, 9.0) / 1.2 * 1.55)


# ---------- 给小地图 / 自检 ----------

## 小地图上的光波圈：[中心, 半径, 不透明度]；没在扫时返回空
func map_wave() -> Array:
	if not wave_on:
		return []
	return [center, wave_r, 1.0 - clampf(_fade / 0.8, 0.0, 1.0)]


## 小地图上要闪的标记：[位置, 颜色, 已过秒数, 总秒数, 种类, 轻重]
func map_marks() -> Array:
	var out: Array = []
	for t: Dictionary in marks:
		out.append([pos_of(t), t["col"], float(t["age"]), float(t["hold"]), str(t["type"]), float(t["prio"])])
	return out


## 这一扫的颜色（小地图画光波圈用）
func wave_color() -> Color:
	return cur["a"]


## 现在挂着影子网格 / 光柱的标记各有几个（自检）
func stats() -> Dictionary:
	var g := 0
	var b := 0
	for t: Dictionary in marks:
		if bool(t["attached"]):
			g += 1
		if is_instance_valid(t.get("beam_node")):
			b += 1
	return {"marks": marks.size(), "ghost_targets": g, "beams": b, "meshes": _mesh_n, "fx": _fx.size(), "queue": _queue.size()}


## 载入预热（warmup.gd）：在一个目标上挂一遍影子网格（带骨架的模型那种），着色器先编好；node 被清掉时影子跟着走
func warm_on(node: Node3D, typ: String) -> void:
	var t := {"key": "warm%d" % node.get_instance_id(), "type": typ, "node": node, "col": Color(0.6, 0.9, 1.0), "ghosts": [], "xghosts": []}
	var cap := _mesh_n
	_attach(t)
	if bool(t.get("attached", false)):
		(t["xm"] as ShaderMaterial).set_shader_parameter("power", 0.5)
		(t["lm"] as ShaderMaterial).set_shader_parameter("power", 0.5)
	_mesh_n = cap      # 预热用的不占名额（跟着节点一起被清掉）
