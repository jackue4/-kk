extends Node3D
## 搜打撤玩法管理器（挂在关卡 meadow_level.gd 下，场景是方块世界 block_world.gd）。核心循环：
##   进图 → 探索各区域、打小怪 / 精英 / Boss / 其他修士（AI）→ 捡装备、丹药、材料塞进背包（有格数上限）
##   → 杀怪、吃丹药涨等级、突破境界，去更危险的区域搜更值钱的东西 → 找到「还亮着」的传送阵读条撤离，带走背包里的东西；
##   中途陨落则背包清空。带出去的东西记进 user://xiuxian_stash.json。
## 区域（raid_data.gd）：草原在中间，北 黄枫谷 / 东 血色禁地 / 南 阴冥之地 / 西 坠魔谷，越往后区域等级越高。
## 数值按《雨中冒险2》那套来（公式在 raid_data.gd）：
##   · 局内等级：主角每级生命 +30%、伤害 +20%；升级经验按 1.55 的幂涨；每 3 级突破一个大境界
##   · 难度系数随局内时间涨、每击败一头区域 Boss 再乘 1.15；怪的等级 = 区域基础等级 + 环境等级，拖得越久越凶，箱子也越值钱
##   · 刷怪导演：每秒攒点数（随难度系数加快），隔几秒在主角周围按点数买一拨怪；点数够多时买精英（点数 ×6、生命 ×4、伤害 ×2）
##   · 每隔两三分钟来一次「天地异动」：一头游荡 Boss 找上门；各区域巢穴里另有镇守的 Boss（远处看得见光柱）
## 其他修士（AI，air_foe.gd）：主角周围常驻五六个，自己到处飞、找怪打；红名的见人就动手（同时最多两个围上来），
##   白名的各刷各的，被打了才翻脸。击败后掉储物袋。
## 手机端开销：怪是三次绘制调用的方块、没有骨架和碰撞体；拾取 / 撤离 / 生成都是按距离的简单判断，分摊到 0.4 秒一次。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Mob := preload("res://scripts/raid_mob.gd")
const Pickup := preload("res://scripts/raid_pickup.gd")
const AirFoe := preload("res://scripts/air_foe.gd")
const RaidHud := preload("res://scripts/raid_hud.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Combat := preload("res://scripts/combat.gd")

const EXTRACT_T := 6.0
const EXTRACT_R := 6.0
const CHEST_T := 1.2
const STASH := "user://xiuxian_stash.json"

var level: Node3D            # MeadowLevel
var player: Player
var cam: CameraRig
var font: Font
var mobile := false
var hud: RaidHud
var bag: Array = []
var kills := 0
var running := true
var region := 0
var extract_k := 0.0          # 撤离读条 0~1
var stash_total := 0
var lv := 1                   # 局内等级
var xp := 0.0                 # 当前等级已攒的经验
var run_t := 0.0              # 局内时间（秒）
var clears := 0               # 已击败的区域 Boss 数

var _rng := RandomNumberGenerator.new()
var _mobs: Array = []            # 里面可能有刚被销毁的，遍历时一律先 is_instance_valid
var _pickups: Array[Node3D] = []
var _bosses: Array = []       # {region, pos, node, state: 0 未生成 / 1 在场 / 2 已击败, mark}
var _rivals: Array = []
var _extracts: Array = []     # {pos, active, known, name}
var _tick := 0.0
var _last_hp := 100.0
var _calm_t := 0.0
var _calm_hp := 100.0
var _full_t := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _mob_root: Node3D
var _boss_near: Node3D = null
var _credits := 70.0
var _wave_t := 2.5
var _event_t := 120.0
var _rival_t := 1.0
var _feed_t := 4.0
var _names: Array = []
var _sky_top := Color(0.04, 0.13, 0.24)
var _sky_hor := Color(0.98, 0.52, 0.22)
var _mote := Color(1.0, 0.8, 0.35)


func _ready() -> void:
	_rng.randomize()
	_env = level.env
	_sun = level.sun
	_mob_root = Node3D.new()
	add_child(_mob_root)
	_names = Data.AI_NAMES.duplicate()
	_names.shuffle()
	lv = player.realm_idx * Data.LV_PER_REALM + 1
	_event_t = _rng.randf_range(110.0, 150.0)
	_setup_pois()
	_load_stash()
	hud = RaidHud.new()
	hud.font = font
	hud.mgr = self
	hud.touch = mobile
	add_child(hud)
	player.melee.hp = player.melee.HP_MAX
	_last_hp = player.melee.hp
	hud.banner("木兰草原", "搜 · 打 · 撤　找到亮着的传送阵才能带走东西", Color(0.7, 1.0, 0.6))


func _ground(x: float, z: float) -> float:
	return level.ground(x, z)


func _on_ground(p: Vector2) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.y), p.y)


# ---------- 数值 ----------

func coeff() -> float:
	return Data.coeff(run_t, clears)


## region 区域里现在刷出来的怪是几级
func enemy_level(ri: int) -> int:
	return int(Data.REGIONS[ri]["lv"]) + int(Data.ambient_level(run_t, clears)) - 1


## 主角打出的伤害 → 怪实际扣的血：招式倍率（伤害 / 当前境界基准）× 局内等级的伤害
func player_dmg(d: float) -> float:
	return d / float(Data.REALM_DMG[player.realm_idx]) * Data.stat(Data.PLAYER_DMG, 0.2, lv)


## 怪的伤害 → 打在主角 100 点血条上的值（主角生命随等级涨，折算成掉得少）
func to_player(d: float) -> float:
	return d * 100.0 / Data.stat(Data.PLAYER_HP, 0.3, lv)


func add_exp(v: float) -> void:
	xp += v
	var up := false
	while xp >= Data.xp_need(lv) and lv < 99:
		xp -= Data.xp_need(lv)
		lv += 1
		up = true
	if not up:
		return
	var ri := mini(int(floorf(float(lv - 1) / float(Data.LV_PER_REALM))), Realm.count() - 1)
	if ri > player.realm_idx:
		player.set_realm(ri)
		hud.banner("突破 · %s期" % player.realm["name"], "修为 Lv.%d　可以去更凶险的地方了" % lv, Realm.line_color(player.realm))
	else:
		hud.toast("修为精进 Lv.%d　气血、伤害提升" % lv, Color(0.6, 1.0, 0.8))
		Vfx.breakthrough(player.global_position, Color(0.6, 1.0, 0.8), 0.35)
		Sfx.play("ascend", -9.0, 1.4)
	player.melee.hp = minf(player.melee.hp + 20.0, player.melee.HP_MAX)


func exp_ratio() -> float:
	return clampf(xp / Data.xp_need(lv), 0.0, 1.0)


# ---------- 区域氛围 ----------

## 雾、环境光、主光、天空、空中飘浮物按主角所在位置的区域权重渐变
func _blend_atmosphere(dt: float) -> void:
	var p := player.global_position
	var w := Data.region_weights(p.x, p.z)
	var fog := Color(0, 0, 0)
	var amb := Color(0, 0, 0)
	var sun := Color(0, 0, 0)
	var top := Color(0, 0, 0)
	var hor := Color(0, 0, 0)
	var mote := Color(0, 0, 0)
	var fd := 0.0
	var ae := 0.0
	var se := 0.0
	var best := 0
	for i in 5:
		var r: Dictionary = Data.REGIONS[i]
		var k := w[i]
		fog += (r["fog"] as Color) * k
		amb += (r["amb"] as Color) * k
		sun += (r["sun"] as Color) * k
		top += (r["sky_top"] as Color) * k
		hor += (r["sky_hor"] as Color) * k
		mote += (r["mote"] as Color) * k
		fd += float(r["fog_d"]) * k
		ae += float(r["amb_e"]) * k
		se += float(r["sun_e"]) * k
		if k > w[best]:
			best = i
	var a := 1.0 - exp(-2.2 * dt)
	_env.fog_light_color = _env.fog_light_color.lerp(fog, a)
	_env.fog_density = lerpf(_env.fog_density, fd * (1.25 if mobile else 1.0), a)
	_env.ambient_light_color = _env.ambient_light_color.lerp(amb, a)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, ae, a)
	_sun.light_color = _sun.light_color.lerp(sun, a)
	_sun.light_energy = lerpf(_sun.light_energy, se, a)
	_sky_top = _sky_top.lerp(top, a)
	_sky_hor = _sky_hor.lerp(hor, a)
	_mote = _mote.lerp(mote, a)
	var sm := _env.sky.sky_material as ShaderMaterial
	if sm != null:
		sm.set_shader_parameter("top_col", _sky_top)
		sm.set_shader_parameter("hor_col", _sky_hor)
		sm.set_shader_parameter("glow_col", _sun.light_color)
		sm.set_shader_parameter("stars", clampf(1.0 - (_sky_top.r + _sky_top.g + _sky_top.b) * 1.6, 0.0, 1.0))
	if level.motes != null:
		level.motes.color = _mote
	if best != region:
		region = best
		var r: Dictionary = Data.REGIONS[best]
		var danger := int(r["lv"]) > lv + 2
		hud.banner(r["name"], "%s　区域等级 Lv.%d%s" % [r["sub"], enemy_level(best), "　※ 凶险" if danger else ""],
				Color(1.0, 0.4, 0.3) if danger else Color(1.0, 0.92, 0.7))
		Sfx.play("ascend", -10.0, 0.8 if danger else 1.2)


# ---------- 地标：Boss 巢穴 / 传送阵 ----------

func _beam(parent: Node3D, col: Color, height: float, width: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	for i in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(width, height)
		q.mesh = qm
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lm.albedo_color = Color(col.r, col.g, col.b, 0.5)
		lm.disable_fog = true
		q.material_override = lm
		q.position.y = height * 0.5
		q.rotation.y = PI * 0.5 * float(i)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
	return root


func _setup_pois() -> void:
	var ex: Array = []
	for p: Dictionary in Data.pois():
		var pos := _on_ground(p["pos"])
		var ri: int = p["region"]
		match str(p["kind"]):
			"boss":
				var mark := Node3D.new()
				add_child(mark)
				mark.global_position = pos
				_build_lair(mark, Data.REGIONS[ri]["light"])
				_bosses.append({"region": ri, "pos": pos, "node": null, "state": 0, "mark": mark})
			"extract":
				ex.append(["%s传送阵" % Data.REGIONS[ri]["name"], pos])
	# 每一局只有两座阵还亮着
	var order := range(ex.size())
	order.shuffle()
	for k in ex.size():
		var active: bool = order.find(k) < 2
		_extracts.append({"pos": ex[k][1], "active": active, "known": false, "name": ex[k][0]})
		_build_extract(ex[k][1], active)


## Boss 巢穴：一圈残柱，柱顶燃着区域色的火，中间一道冲天光柱（Boss 被击败后熄灭）
func _build_lair(root: Node3D, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fire := SurfaceTool.new()
	fire.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var o := Vector3(cos(a), 0.0, sin(a)) * 22.0
		var h := 9.0 if i % 2 == 0 else 5.5
		Data.add_box(st, Vector3(3.2, 1.0, 3.2), Transform3D(Basis(Vector3.UP, -a), o + Vector3(0, 0.5, 0)), Color(0.2, 0.2, 0.24))
		Data.add_box(st, Vector3(2.2, h, 2.2), Transform3D(Basis(Vector3.UP, -a), o + Vector3(0, h * 0.5 + 1.0, 0)), Color(0.26, 0.26, 0.3))
		Data.add_box(fire, Vector3(1.4, 1.4, 1.4), Transform3D(Basis(Vector3.UP, -a + 0.6), o + Vector3(0, h + 1.9, 0)), col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	root.add_child(mi)
	var fi := MeshInstance3D.new()
	fi.mesh = fire.commit()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(col.r * 1.7, col.g * 1.7, col.b * 1.7)
	fi.material_override = fm
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fi)
	_beam(root, Color(1.0, 0.22, 0.16), 160.0, 2.6)


func _spawn_mob(def_idx: int, ri: int, pos: Vector3, elite := false, lvl := -1, hp_k := 1.0) -> Node3D:
	var d: Dictionary = Data.MOBS[def_idx]
	var is_boss: bool = d.get("boss", false)
	var base: Array = Data.SHAPE_BASE[str(d["shape"])]
	var m := Mob.new()
	m.player = player
	m.def = d
	m.region = ri
	m.lv = lvl if lvl > 0 else enemy_level(ri)
	m.elite = elite
	var hp0 := (Data.BOSS_HP if is_boss else float(base[0])) * float(d["hp"])
	var at0 := (Data.BOSS_DMG if is_boss else float(base[1])) * float(d["atk"])
	m.hp_max = Data.stat(hp0, 0.3, m.lv) * (Data.ELITE_HP if elite else 1.0) * hp_k
	m.atk = Data.stat(at0, 0.2, m.lv) * (Data.ELITE_DMG if elite else 1.0)
	m.xp_k = 14.0 if is_boss else float(base[3]) * (3.0 if elite else 1.0)
	m.dmg_in = player_dmg
	m.atk_out = to_player
	m.floor_fn = _ground
	m.position = pos
	m.died.connect(_on_mob_died)
	_mob_root.add_child(m)
	return m


func _announce_boss(m: Node3D, sub: String) -> void:
	hud.banner("%s  Lv.%d" % [m.display_name, m.lv], sub, Color(1.0, 0.35, 0.25))
	Sfx.play("ascend", -4.0, 0.55)
	cam.add_trauma(0.35)


func _update_bosses(p: Vector3) -> void:
	_boss_near = null
	for b: Dictionary in _bosses:
		var pos: Vector3 = b["pos"]
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if int(b["state"]) == 0 and d < 230.0:
			var ri: int = b["region"]
			var m := _spawn_mob(int(Data.REGIONS[ri]["boss"]), ri, pos, false, enemy_level(ri) + 2)
			b["node"] = m
			b["state"] = 1
			_announce_boss(m, "%s 的霸主镇守于此" % Data.REGIONS[ri]["name"])
		elif int(b["state"]) == 1:
			var n: Node3D = b["node"]
			if is_instance_valid(n) and n.global_position.distance_to(p) < 150.0:
				_boss_near = n
	# 游荡 Boss
	for m: Variant in _mobs:
		if is_instance_valid(m) and m.boss and m.global_position.distance_to(p) < 150.0:
			_boss_near = m


## 天地异动：一头游荡 Boss 在主角附近现身（生命只有巢穴 Boss 的六成）
func boss_event() -> Node3D:
	var p := player.global_position
	var ri := Data.region_at(p.x, p.z)
	var a := _rng.randf() * TAU
	var pos := p + Vector3(cos(a), 0.0, sin(a)) * 42.0
	pos.y = _ground(pos.x, pos.z)
	var m := _spawn_mob(int(Data.REGIONS[ri]["boss"]), ri, pos, false, enemy_level(ri) + 1, 0.6)
	m.roaming = true
	m.set_meta("event", true)
	_mobs.append(m)
	m.alert()
	Vfx.dun_slam(pos, (m.def["cols"] as Array)[2], 1.6)
	_announce_boss(m, "天地异动 · 大妖循着灵气找上门来")
	return m


# ---------- 刷怪导演 ----------

func mob_cap() -> int:
	return 9 if mobile else 13


func _director(p: Vector3) -> void:
	var cap := mob_cap()
	var i := _mobs.size() - 1
	while i >= 0:
		var m: Variant = _mobs[i]
		if not is_instance_valid(m):
			_mobs.remove_at(i)
		elif m.global_position.distance_to(p) > (260.0 if m.boss else 150.0) and (m.state == Mob.S.IDLE or m.state == Mob.S.CHASE):
			m.queue_free()
			_mobs.remove_at(i)
		i -= 1
	_credits = minf(_credits + 2.2 * (1.0 + 0.4 * coeff()) * 0.4, 280.0)
	_wave_t -= 0.4
	if _mobs.size() <= 1:
		_wave_t = minf(_wave_t, 1.2)      # 周围空了（清完了 / 飞远了）：马上补一拨
	_event_t -= 0.4
	if _event_t <= 0.0 and _boss_near == null:
		_event_t = _rng.randf_range(150.0, 230.0)
		boss_event()
	if _wave_t > 0.0 or _mobs.size() >= cap or Vector2(p.x, p.z).length() > Data.PLAY_R:
		return
	_wave_t = _rng.randf_range(3.5, 7.0)
	spawn_wave(p)


## 花点数在 p 周围买一拨怪；返回买了几只
func spawn_wave(p: Vector3) -> int:
	var ri := Data.region_at(p.x, p.z)
	var pool: Array = Data.REGIONS[ri]["mobs"]
	var idx: int = pool[_rng.randi() % pool.size()]
	var cost: float = Data.SHAPE_BASE[str(Data.MOBS[idx]["shape"])][2]
	var elite := _credits >= cost * Data.ELITE_COST and _rng.randf() < 0.4
	if elite:
		cost *= Data.ELITE_COST
	var a := _rng.randf() * TAU
	var n := 0
	while _credits >= cost and _mobs.size() < mob_cap() and n < (1 if elite else 4):
		var aa := a + _rng.randf_range(-0.5, 0.5)
		var pos := p + Vector3(cos(aa), 0.0, sin(aa)) * _rng.randf_range(24.0, 46.0)
		pos.y = _ground(pos.x, pos.z)
		var m := _spawn_mob(idx, ri, pos, elite)
		_mobs.append(m)
		_credits -= cost
		n += 1
		Vfx.takeoff_burst(pos, (m.def["cols"] as Array)[2], 0.7 if not elite else 1.3)
		if elite or _rng.randf() < 0.6:
			m.alert()
	if elite and n > 0:
		hud.toast("精英 %s 出现了" % Data.MOBS[idx]["name"], Color(1.0, 0.7, 0.3))
	return n


func _on_mob_died(m: Node3D) -> void:
	var ri: int = m.region
	var pos: Vector3 = m.global_position
	pos.y = _ground(pos.x, pos.z)
	var by_rival: bool = m.slain_by_rival
	if not by_rival:
		kills += 1
		add_exp(Data.xp_reward(m.lv, m.xp_k))
	if m.boss:
		var lair := false
		for b: Dictionary in _bosses:
			if b["node"] == m:
				b["state"] = 2
				(b["mark"] as Node3D).queue_free()
				lair = true
		if lair:
			clears += 1
		_drop_chest(pos, _loot(ri, 5 if lair else 3, 1.3 if lair else 0.8), "%s 的遗藏" % m.display_name)
		hud.banner("击败 %s" % m.display_name, "遗藏已现，速取" + ("　※ 天地灵气翻涌，妖兽更凶了" if lair else ""), Color(1.0, 0.85, 0.4))
	elif m.elite:
		_drop_chest(pos, _loot(ri, 2, 0.5), "精英的遗物")
	elif _rng.randf() < (0.2 if by_rival else 0.55):
		for it: Dictionary in _loot(ri, 1, 0.0):
			_drop_item(pos + Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8)), it, 0.5)


## 掉落：价值按难度系数的 1.25 次方涨（拖得越久越值钱）
func _loot(ri: int, n: int, bonus: float) -> Array:
	var items := Data.roll_loot(ri, n, _rng, bonus)
	var c := coeff()
	for it: Dictionary in items:
		it["value"] = Data.scaled_value(float(it["value"]), c)
	return items


# ---------- 其他修士（AI） ----------

func rival_cap() -> int:
	return 5 if mobile else 6


func _engaged() -> int:
	var n := 0
	for f: Variant in _rivals:
		if is_instance_valid(f) and f.state != AirFoe.S.IDLE and f.state != AirFoe.S.DEAD:
			n += 1
	return n


func _engage_ok(_f: Node3D) -> bool:
	return run_t > 12.0 and _engaged() < 2


## 给修士找一只附近的怪（没被别的修士盯上的小怪优先）
func _prey_for(f: Node3D) -> Node3D:
	var best: Node3D = null
	var bd := 48.0
	for m: Variant in _mobs:
		if not is_instance_valid(m) or not m.is_alive() or m.boss:
			continue
		if m.decoy != null and is_instance_valid(m.decoy) and m.decoy != f:
			continue
		var d: float = m.global_position.distance_to(f.global_position)
		if d < bd:
			bd = d
			best = m
	return best


func spawn_rival(pos: Vector3, hostile: bool) -> Node3D:
	var ri := Data.region_at(pos.x, pos.z)
	var f := AirFoe.new()
	f.player = player
	f.display_name = _names[0]
	_names.append(_names.pop_front())
	f.raid = true
	f.pro = true
	f.roam = true
	f.hostile = hostile
	f.lv = enemy_level(ri)
	f.style = 2 if _rng.randf() < 0.5 else 0
	f.qi = [Color(0.3, 0.95, 0.85), Color(0.95, 0.3, 0.4), Color(1.0, 0.8, 0.3), Color(0.6, 0.5, 1.0)][_rng.randi() % 4]
	f.hp_max = Data.stat(380.0, 0.3, f.lv)
	f.prey_dmg = Data.stat(Data.PLAYER_DMG, 0.2, f.lv) * 0.6
	f.dmg_in = player_dmg
	f.prey_fn = _prey_for
	f.engage_ok = _engage_ok
	f.floor_fn = _ground
	f.position = pos
	f.set_meta("region", ri)
	f.died.connect(_on_rival_died)
	_mob_root.add_child(f)
	_rivals.append(f)
	return f


func _update_rivals(p: Vector3) -> void:
	var i := _rivals.size() - 1
	var idle_far: Node3D = null
	while i >= 0:
		var f: Variant = _rivals[i]
		if not is_instance_valid(f) or f.state == AirFoe.S.DEAD:
			_rivals.remove_at(i)
		else:
			# 伤害随双方等级折算
			f.dmg_mul = 0.6 * Data.stat(1.0, 0.2, f.lv) / Data.stat(1.0, 0.3, lv)
			var d: float = f.global_position.distance_to(p)
			if d > 240.0 and f.state == AirFoe.S.IDLE:
				f.queue_free()
				_rivals.remove_at(i)
			elif f.state == AirFoe.S.IDLE and f._prey == null and d < 110.0 and d > 30.0:
				idle_far = f
		i -= 1
	_rival_t -= 0.4
	if _rivals.size() < 3:
		_rival_t = minf(_rival_t, 2.0)
	if _rivals.size() < rival_cap() and _rival_t <= 0.0 and Vector2(p.x, p.z).length() < Data.PLAY_R:
		_rival_t = _rng.randf_range(1.5, 3.0) if run_t < 25.0 or _rivals.size() < 3 else _rng.randf_range(8.0, 16.0)
		var a := _rng.randf() * TAU
		var pos := p + Vector3(cos(a), 0.0, sin(a)) * (_rng.randf_range(40.0, 75.0) if run_t < 25.0 or _rivals.size() < 3 else _rng.randf_range(80.0, 130.0))
		pos.y = _ground(pos.x, pos.z) + 1.4
		spawn_rival(pos, _rng.randf() < 0.4)
	# 给闲着的修士身边放只怪，让远处也看得到有人在打怪（不花导演点数）
	_feed_t -= 0.4
	if idle_far != null and _feed_t <= 0.0 and _mobs.size() < mob_cap():
		_feed_t = 5.0
		var fp := idle_far.global_position
		var a2 := _rng.randf() * TAU
		var mp := fp + Vector3(cos(a2), 0.0, sin(a2)) * 12.0
		mp.y = _ground(mp.x, mp.z)
		var ri := Data.region_at(mp.x, mp.z)
		var pool: Array = Data.REGIONS[ri]["mobs"]
		var m := _spawn_mob(int(pool[_rng.randi() % pool.size()]), ri, mp)
		m.decoy = idle_far
		_mobs.append(m)


func _on_rival_died(f: Node3D) -> void:
	var ri: int = f.get_meta("region")
	kills += 1
	add_exp(Data.xp_reward(f.lv, 5.0))
	var pos := f.global_position
	pos.y = _ground(pos.x, pos.z)
	_drop_chest(pos, _loot(ri, _rng.randi_range(3, 4), 0.9), "%s 的储物袋" % f.display_name)
	hud.toast("击败 %s，掉落储物袋" % f.display_name, Color(1.0, 0.85, 0.4))


# ---------- 掉落 / 背包 / 修为 ----------

func _drop_item(pos: Vector3, it: Dictionary, grace: float) -> void:
	var pk := Pickup.new()
	pk.item = it
	pk.grace = grace
	add_child(pk)
	pk.global_position = pos
	_pickups.append(pk)


func _drop_chest(pos: Vector3, items: Array, title: String) -> void:
	var pk := Pickup.new()
	pk.items = items
	pk.title = title
	pk.grace = 0.6
	add_child(pk)
	pk.global_position = pos
	_pickups.append(pk)
	Vfx.takeoff_burst(pos, Data.TIER_COLORS[pk.tier()], 0.8)


func bag_value() -> int:
	var v := 0
	for it: Dictionary in bag:
		v += int(it["value"])
	return v


func _take(it: Dictionary) -> bool:
	if bag.size() >= Data.BAG_SIZE:
		return false
	bag.append(it)
	var col: Color = Data.TIER_COLORS[int(it["tier"])]
	hud.toast("拾取 %s · %s（%d 灵石）" % [it["name"], Data.TIER_NAMES[int(it["tier"])], int(it["value"])], col)
	Sfx.play("perfect", -12.0, 1.3 + 0.1 * float(it["tier"]))
	return true


func _update_pickups(dt: float) -> void:
	var p := player.global_position
	var chest_k := 0.0
	var i := _pickups.size() - 1
	while i >= 0:
		var pk := _pickups[i]
		var d := pk.global_position.distance_to(p)
		var gone := false
		if pk.is_chest():
			if d < 3.4 and pk.grace <= 0.0:
				pk.open_t += dt
				chest_k = maxf(chest_k, pk.open_t / CHEST_T)
				if pk.open_t >= CHEST_T:
					var rest: Array = []
					for it: Dictionary in pk.items:
						if not _take(it):
							rest.append(it)
					if rest.is_empty():
						gone = true
					else:
						# 装不下的留在地上散成单件
						for it: Dictionary in rest:
							_drop_item(pk.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5)), it, 4.0)
						gone = true
						hud.toast("背包已满，剩下的散在地上", Color(1.0, 0.5, 0.4))
			else:
				pk.open_t = 0.0
		elif pk.grace <= 0.0:
			if d < 7.0 and bag.size() < Data.BAG_SIZE:
				pk.global_position = pk.global_position.move_toward(p + Vector3.UP * 0.6, 14.0 * dt)   # 靠近了自己飞过来
			if d < 2.2:
				if _take(pk.item):
					gone = true
				elif _full_t <= 0.0:
					_full_t = 2.5
					hud.toast("背包已满（打开背包丢弃或服用）", Color(1.0, 0.5, 0.4))
		if d > 600.0:
			gone = true
		if gone:
			pk.queue_free()
			_pickups.remove_at(i)
		i -= 1
	hud.chest_k = chest_k


## 背包里第 i 件：丹药服用，其余丢在脚边
func use_item(i: int) -> void:
	if i < 0 or i >= bag.size() or not running:
		return
	var it: Dictionary = bag[i]
	bag.remove_at(i)
	if it["kind"] == "pill":
		hud.toast("服下 %s，修为 +%d、气血 +25" % [it["name"], int(it["exp"])], Data.TIER_COLORS[int(it["tier"])])
		add_exp(float(it["exp"]))
		player.melee.hp = minf(player.melee.hp + 25.0, player.melee.HP_MAX)
		Vfx.breakthrough(player.global_position, Data.TIER_COLORS[int(it["tier"])], 0.4)
		Sfx.play("ascend", -8.0, 1.5)
	else:
		_drop_item(player.global_position + Vector3(0.0, 0.2, 0.0), it, 4.0)
		hud.toast("丢下 %s" % it["name"], Color(0.8, 0.8, 0.85))


# ---------- 撤离点 ----------

func _build_extract(pos: Vector3, active: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var stone := MeshLib.std_mat(Color(0.6, 0.62, 0.66), 0.9)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = EXTRACT_R
	cm.bottom_radius = EXTRACT_R + 0.6
	cm.height = 0.5
	cm.radial_segments = 16
	base.mesh = cm
	base.material_override = stone
	base.position.y = 0.1
	root.add_child(base)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var broken := not active and i % 2 == 0
		var pm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 1.6 if broken else 5.0, 0.9)
		pm.mesh = bm
		pm.material_override = stone
		pm.position = Vector3(cos(a), 0.0, sin(a)) * (EXTRACT_R - 0.6) + Vector3(0.0, bm.size.y * 0.5, 0.0)
		pm.rotation = Vector3(0.0, -a, 0.25 if broken else 0.0)
		root.add_child(pm)
	if active:
		_beam(root, Color(0.3, 0.95, 1.0), 220.0, 3.0)
		var glow := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = EXTRACT_R - 1.2
		gm.bottom_radius = EXTRACT_R - 1.2
		gm.height = 0.08
		gm.radial_segments = 16
		glow.mesh = gm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.2, 0.62, 0.68)
		glow.material_override = m
		glow.position.y = 0.4
		root.add_child(glow)


## 最近的撤离点：{pos, active, known, name, dist}
func nearest_extract() -> Dictionary:
	var p := player.global_position
	var best := {}
	var bd := INF
	for e: Dictionary in _extracts:
		var d := Vector2(p.x - (e["pos"] as Vector3).x, p.z - (e["pos"] as Vector3).z).length()
		# 已经探明是废阵的不再指
		if bool(e["known"]) and not bool(e["active"]):
			continue
		if d < bd:
			bd = d
			best = e
	if not best.is_empty():
		best["dist"] = bd
	return best


func _update_extract(dt: float) -> void:
	var p := player.global_position
	var hurt := player.melee.hp < _last_hp - 0.01
	_last_hp = player.melee.hp
	var inside := false
	for e: Dictionary in _extracts:
		var pos: Vector3 = e["pos"]
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < 170.0 and not bool(e["known"]):
			e["known"] = true
			if bool(e["active"]):
				hud.toast("%s：阵法完好，可以撤离" % e["name"], Color(0.4, 1.0, 1.0))
			else:
				hud.toast("%s：阵法已毁，另寻他处" % e["name"], Color(1.0, 0.5, 0.4))
		if bool(e["active"]) and d < EXTRACT_R and absf(p.y - pos.y) < 8.0:
			inside = true
	if inside and not hurt:
		extract_k += dt / EXTRACT_T
		if extract_k >= 1.0:
			_finish(true)
	else:
		extract_k = 0.0


# ---------- 结算 ----------

func _load_stash() -> void:
	if FileAccess.file_exists(STASH):
		var f := FileAccess.open(STASH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				stash_total = int((d as Dictionary).get("total", 0))


func _save_stash(items: Array) -> void:
	var all: Array = []
	if FileAccess.file_exists(STASH):
		var f0 := FileAccess.open(STASH, FileAccess.READ)
		if f0 != null:
			var d: Variant = JSON.parse_string(f0.get_as_text())
			if d is Dictionary:
				all = (d as Dictionary).get("items", [])
	for it: Dictionary in items:
		all.append({"name": it["name"], "tier": it["tier"], "value": it["value"], "kind": it["kind"]})
	var f := FileAccess.open(STASH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"total": stash_total, "items": all}))


func _finish(success: bool) -> void:
	if not running:
		return
	running = false
	_mob_root.process_mode = Node.PROCESS_MODE_DISABLED
	var value := bag_value()
	var items := bag.duplicate()
	if success:
		stash_total += value
		_save_stash(items)
		Vfx.breakthrough(player.global_position, Color(0.4, 1.0, 1.0), 1.0)
		Sfx.play("ascend", -2.0, 1.0)
	else:
		bag.clear()
		Combat.slowmo(0.15, 0.6, 0.8)
		Vfx.death_burst(player.center(), Color(1.0, 0.3, 0.25))
	hud.show_result(success, items, value, kills, stash_total)
	print("[raid] 结算：%s 带出 %d 件 价值 %d 击杀 %d 仓库累计 %d" % ["撤离成功" if success else "陨落", items.size() if success else 0,
			value if success else 0, kills, stash_total])
	await get_tree().create_timer(4.5, true, false, true).timeout
	player.melee.hp = player.melee.HP_MAX
	level.exit_requested.emit()


func _process(dt: float) -> void:
	if not running:
		return
	run_t += dt
	_full_t -= dt
	_blend_atmosphere(dt)
	_update_pickups(dt)
	_update_extract(dt)
	if player.melee.hp <= 0.0:
		_finish(false)
		return
	# 脱战 5 秒后缓慢回血
	if player.melee.hp < _calm_hp - 0.01:
		_calm_t = 5.0
	_calm_hp = player.melee.hp
	_calm_t -= dt
	if _calm_t <= 0.0 and player.melee.hp < player.melee.HP_MAX:
		player.melee.hp = minf(player.melee.hp + 1.5 * dt, player.melee.HP_MAX)
		_calm_hp = player.melee.hp
		_last_hp = maxf(_last_hp, player.melee.hp)
	_tick -= dt
	if _tick <= 0.0:
		_tick = 0.4
		var p := player.global_position
		_update_bosses(p)
		_director(p)
		_update_rivals(p)
	hud.boss = _boss_near if is_instance_valid(_boss_near) else null
