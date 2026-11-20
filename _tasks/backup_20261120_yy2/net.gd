extends Node
## 局域网联机（ENet）。一个房间 = 一局大世界，最多 40 人，随时可以中途加入。
## 结构：
##   · 房主既是服务器也是玩家；其他人按 IP 连进来。房主每秒在局域网里广播一次房间（UDP），选关界面据此列出能加入的房间。
##   · 每个人只模拟自己的主角，每秒 15 次把位置 / 朝向 / 状态 / 动作广播给所有人；别人在自己这边是一个「远程玩家」木偶（remote_player.gd）。
##   · 怪由刷出它的那个人模拟（它只追着刷出它的人打），每秒 10 次把自己名下的怪广播出去；别人那边是怪的木偶，
##     打在木偶上的伤害发回给主人结算。巢穴 Boss 谁先走近谁刷，别人看到了就不再刷自己的。
##   · 命中别的玩家：打在木偶上 → 把这一下发给对方 → 对方在自己那边按正常受击结算（能挡、能闪）。
##   · 分队：进图时选 1 / 2 / 4 人队，房主把人塞进同样人数、还有空位的队里，没有就新开一队。
##     队友之间打不到（木偶直接不吃伤害），也不会被索敌选中（队友的木偶不进索敌分组）。
##   · 表现同步：每放一柄飞剑 / 法术都发给别人，别人那边画一柄不伤人的（每人每秒最多发 40 柄，超出的不画）；
##     拳脚命中、击飞、砸地、瞬身、格挡这些打击特效按「战斗事件」转发；雷劫的劫云、化身、每道雷也转发给旁观的人。
##   · 怪会追最近的玩家（不管是不是刷出它的人）：打中别人时把伤害发给那个人结算。
##   · 掉落物全房间共享：谁掉的都广播出去，拾取要向房主申请，先到先得。
##   · 玩家之间的飞剑对波：两边各自累计自己顶了多少、互相发给对方，交汇点 = 0.5 + 我顶的 − 他顶的；由发起的一方判胜负。
## 没做的：地面飞剑阵（Q）和剑诀里除飞剑以外的附带特效不同步；房主退出则房间解散。
## 故意不写 class_name：用 preload 引用。

signal roster_changed
signal room_closed

const Remote := preload("res://scripts/remote_player.gd")

const PORT := 24680
const DISC_PORT := 24681
const MAX_PLAYERS := 40
const STATE_HZ := 15.0
const MOB_HZ := 10.0
const PROJ_PER_SEC := 40.0     # 每秒最多转发这么多柄飞剑 / 法术
const NICKS := ["青云", "玄真", "凌霄", "太虚", "紫阳", "无尘", "归元", "天枢", "明月", "长风", "若水", "惊鸿"]

var active := false
var is_host := false
var my_id := 1
var my_name := ""
var team_size := 1
var players := {}        # peer id -> {name, team, size, realm}
var remotes := {}        # peer id -> Remote 木偶（只在大世界里有）
var rooms := {}          # ip -> {name, count, t}（局域网里发现的房间）
var seed_v := 0          # 这一局的种子（哪两座传送阵亮着），房主定
var cleared: Array = []  # 已经被打掉的巢穴 Boss（区域下标），中途加入的人要知道
var host_run_t := 0.0    # 加入时房主那边的局内时间
var welcomed := false
var raid: Node3D = null  # 大世界的玩法管理器（raid_manager.gd）；不在大世界里为 null
var player: Player

var _peer: ENetMultiplayerPeer
var _udp_in: PacketPeerUDP
var _udp_out: PacketPeerUDP
var _cast_t := 0.0
var _state_t := 0.0
var _mob_t := 0.0
var _next_team := 1
var _proj_budget := 0.0
var _claimed := {}       # 房主：已经判给别人的掉落物
var stat := {"proj": 0, "fx": 0, "mobhit": 0}   # 自检用：收到了多少别人的飞剑 / 特效 / 被别人的怪打
var pending_dug := {}            # 中途加入：房主发来的、已经被破开的地形
var pending_drops: Array = []   # 中途加入：房主发来的、地上现有的掉落物（玩法管理器建好后取走）
const Proj := preload("res://scripts/spell_projectile.gd")
## 循环世界（raid_data.gd 的 LOOP）：每个人的坐标各涨各的，别人发来的位置一律先换成「离我最近的那个像」再用
const LoopData := preload("res://scripts/raid_data.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 选关界面暂停着游戏时也要能发现房间
	my_name = "%s%02d" % [NICKS[randi() % NICKS.size()], randi() % 100]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_gone)
	Proj.net_sink = _on_proj


# ---------- 局域网发现 ----------

func start_discovery() -> void:
	if _udp_in != null:
		return
	_udp_in = PacketPeerUDP.new()
	if _udp_in.bind(DISC_PORT) != OK:
		_udp_in = null   # 端口被占（同一台机器上开了两个）：只能手动填 IP


func stop_discovery() -> void:
	if _udp_in != null:
		_udp_in.close()
	_udp_in = null
	rooms.clear()


func _tick_discovery(dt: float) -> void:
	if is_host and active:
		_cast_t -= dt
		if _cast_t <= 0.0:
			_cast_t = 1.0
			if _udp_out == null:
				_udp_out = PacketPeerUDP.new()
				_udp_out.set_broadcast_enabled(true)
				_udp_out.set_dest_address("255.255.255.255", DISC_PORT)
			_udp_out.put_packet(("XIUXIAN|%s|%d" % [my_name, players.size()]).to_utf8_buffer())
	if _udp_in != null:
		while _udp_in.get_available_packet_count() > 0:
			var s := _udp_in.get_packet().get_string_from_utf8()
			var ip := _udp_in.get_packet_ip()
			var parts := s.split("|")
			if parts.size() >= 3 and parts[0] == "XIUXIAN":
				rooms[ip] = {"name": parts[1], "count": int(parts[2]), "t": 0.0}
		for ip: String in rooms.keys():
			rooms[ip]["t"] = float(rooms[ip]["t"]) + dt
			if float(rooms[ip]["t"]) > 3.5:
				rooms.erase(ip)


# ---------- 建房 / 加入 / 离开 ----------

func host(size: int) -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	my_id = 1
	team_size = size
	seed_v = randi() & 0x7fffffff
	cleared.clear()
	_claimed.clear()
	players.clear()
	_next_team = 1
	players[1] = {"name": my_name, "team": _assign_team(size), "size": size, "realm": player.realm_idx}
	welcomed = true
	roster_changed.emit()
	return true


## 连到 ip 上的房间；等房主回话（分队、种子）最多 timeout 秒。成功返回 true
func join(ip: String, size: int, timeout := 5.0) -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(ip, PORT) != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	team_size = size
	welcomed = false
	var t := 0.0
	while t < timeout and not welcomed:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and my_id == 1:
			my_id = multiplayer.get_unique_id()
			_hello.rpc_id(1, my_name, size, player.realm_idx)
	if not welcomed:
		leave()
	return welcomed


func leave() -> void:
	leave_world()
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null
	active = false
	is_host = false
	welcomed = false
	my_id = 1
	players.clear()
	roster_changed.emit()


## 房主：给新来的人分队。1 人队各自一队；2 / 4 人队先塞进同样人数、没满的队
func _assign_team(size: int) -> int:
	if size > 1:
		var counts := {}
		for id: int in players.keys():
			var p: Dictionary = players[id]
			if int(p["size"]) == size:
				counts[int(p["team"])] = int(counts.get(int(p["team"]), 0)) + 1
		for t: int in counts.keys():
			if int(counts[t]) < size:
				return t
	_next_team += 1
	return _next_team - 1


func my_team() -> int:
	return int(players[my_id]["team"]) if players.has(my_id) else 0


func is_mate(id: int) -> bool:
	return players.has(id) and players.has(my_id) and int(players[id]["team"]) == my_team()


func team_count() -> int:
	var n := 0
	for id: int in players.keys():
		if int(players[id]["team"]) == my_team():
			n += 1
	return n


func _on_peer_connected(_id: int) -> void:
	pass   # 等对方发 _hello 再登记


func _on_peer_disconnected(id: int) -> void:
	if is_host and players.has(id):
		players.erase(id)
		_roster.rpc(players)
	_drop_remote(id)


func _on_server_gone() -> void:
	leave()
	room_closed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _hello(nick: String, size: int, realm: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	size = 4 if size >= 4 else (2 if size >= 2 else 1)
	players[id] = {"name": nick.substr(0, 12), "team": _assign_team(size), "size": size, "realm": realm}
	_welcome.rpc_id(id, seed_v, cleared, raid.run_t if raid != null else 0.0, raid.net_drop_list() if raid != null else [],
			raid.level.world.dug_table() if raid != null else {})
	_roster.rpc(players)


@rpc("authority", "call_remote", "reliable")
func _welcome(seed_i: int, cleared_lairs: Array, run_t: float, drops: Array, dug: Dictionary) -> void:
	pending_drops = drops
	pending_dug = dug
	seed_v = seed_i
	cleared = cleared_lairs
	host_run_t = run_t
	welcomed = true


@rpc("authority", "call_local", "reliable")
func _roster(list: Dictionary) -> void:
	players = list
	for id: int in remotes.keys():
		if not players.has(id):
			_drop_remote(id)
		elif is_instance_valid(remotes[id]):
			(remotes[id] as Remote).set_info(players[id], is_mate(id))
	roster_changed.emit()


# ---------- 进出大世界 ----------

func enter_world(r: Node3D) -> void:
	raid = r
	if not player.melee.combat_event.is_connected(_on_combat_event):
		player.melee.combat_event.connect(_on_combat_event)


func leave_world() -> void:
	raid = null
	for id: int in remotes.keys():
		if is_instance_valid(remotes[id]):
			(remotes[id] as Node).queue_free()
	remotes.clear()


func _drop_remote(id: int) -> void:
	if remotes.has(id):
		if is_instance_valid(remotes[id]):
			(remotes[id] as Node).queue_free()
		remotes.erase(id)


func _remote(id: int) -> Remote:
	if remotes.has(id) and is_instance_valid(remotes[id]):
		return remotes[id]
	if raid == null or not players.has(id):
		return null
	var r := Remote.new()
	r.net = self
	r.peer_id = id
	r.player = player
	raid.add_child(r)
	r.set_info(players[id], is_mate(id))
	remotes[id] = r
	return r


# ---------- 每帧：发自己的状态、自己名下的怪 ----------

func _process(dt: float) -> void:
	_tick_discovery(dt)
	if not active or raid == null or player == null or get_tree().paused:
		return
	_state_t -= dt
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_HZ
		var rig := player.melee.rig
		var flags := (1 if player.caster.channeling else 0) | (2 if player.air.in_clash() else 0) | (4 if bool(raid.get("_in_trib")) else 0)
		_state.rpc(player.global_position, player.visual.rotation.y, int(player.st), player.realm_idx,
				player.melee.hp, rig.last_name, rig.play_n, int(raid.lv), player.velocity, flags)
	_proj_budget = minf(_proj_budget + PROJ_PER_SEC * dt, PROJ_PER_SEC * 0.5)
	_mob_t -= dt
	if _mob_t <= 0.0:
		_mob_t = 1.0 / MOB_HZ
		var batch: Array = raid.net_mob_batch()
		if not batch.is_empty():
			_mobs.rpc(batch)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, yaw: float, st: int, realm: int, hp: float, pose: String, pose_n: int, lv: int, vel: Vector3, flags: int) -> void:
	var r := _remote(multiplayer.get_remote_sender_id())
	if r != null:
		if raid != null and player != null:
			pos = LoopData.near(pos, player.global_position)
		r.push_state(pos, yaw, st, realm, hp, pose, pose_n, lv, vel, flags)


# ---------- 表现同步：飞剑 / 法术、打击特效 ----------

## 把一个目标节点写成能过网的引用：[0] 没有 · [1, 玩家编号] · [2, 怪的主人, 怪编号]
func ref_of(n: Variant) -> Array:
	if n == null or not is_instance_valid(n):
		return [0]
	if n is Remote:
		return [1, (n as Remote).peer_id]
	if n == player:
		return [1, my_id]
	if n.get("net_id") != null and n.get("puppet") != null:
		return [2, int(n.net_owner) if bool(n.puppet) else my_id, int(n.net_id)]
	return [0]


func node_of(ref: Array) -> Node3D:
	if ref.is_empty() or raid == null:
		return null
	match int(ref[0]):
		1:
			if int(ref[1]) == my_id:
				return player
			return remotes.get(int(ref[1])) as Node3D if is_instance_valid(remotes.get(int(ref[1]))) else null
		2:
			return raid.net_find_mob(int(ref[1]), int(ref[2]))
	return null


## 本机放了一柄飞剑 / 法术（spell_projectile.gd 的 launch 调过来）
func _on_proj(k: int, from: Vector3, tgt: Variant, aim: Vector3, opts: Dictionary) -> void:
	if not active or raid == null or players.size() < 2 or _proj_budget < 1.0:
		return
	_proj_budget -= 1.0
	var o := opts.duplicate()
	o.erase("dmg")
	_proj.rpc(k, from, ref_of(tgt), aim, o)


@rpc("any_peer", "call_remote", "unreliable")
func _proj(k: int, from: Vector3, tref: Array, aim: Vector3, opts: Dictionary) -> void:
	if raid == null or player == null:
		return
	var shift := LoopData.near(from, player.global_position) - from
	from += shift
	aim += shift
	if from.distance_to(player.global_position) > 260.0:
		return
	stat["proj"] = int(stat["proj"]) + 1
	opts["remote"] = true
	opts["ghost"] = true
	opts["dmg"] = 0.0
	opts["trauma"] = 0.0
	Proj.launch(player, k, from, node_of(tref), aim, opts)


const FX_KINDS := ["air_hit", "air_blocked", "air_launch", "air_crash", "air_vanish", "air_guard", "air_awaken", "air_skill",
		"parry", "block", "hit", "execute"]

## 本机的战斗事件（命中、击飞、砸地、瞬身、格挡…）：转发给别人画特效
func _on_combat_event(kind: String, info: Dictionary) -> void:
	if not active or raid == null or players.size() < 2 or not FX_KINDS.has(kind):
		return
	var pos: Vector3 = info.get("pos", info.get("contact", player.center()))
	_fx.rpc(FX_KINDS.find(kind), pos, 1 if bool(info.get("heavy", false)) or bool(info.get("ground", false)) else 0)


@rpc("any_peer", "call_remote", "unreliable")
func _fx(kind_i: int, pos: Vector3, heavy: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if raid == null or player == null:
		return
	pos = LoopData.near(pos, player.global_position)
	if pos.distance_to(player.global_position) > 200.0:
		return
	stat["fx"] = int(stat["fx"]) + 1
	var r: Variant = remotes.get(from)
	var col: Color = (r as Remote).qi if is_instance_valid(r) else Color.WHITE
	match str(FX_KINDS[clampi(kind_i, 0, FX_KINDS.size() - 1)]):
		"air_hit", "hit":
			Vfx.impact(pos, Vector3.RIGHT, col, 4 if heavy == 1 else 0)
			if heavy == 1:
				Vfx.shockwave(pos, Vector3.UP, col, 1.2)
		"air_blocked", "block", "parry", "air_guard":
			Vfx.blade_clash(pos, Vector3.UP, 0.8)
		"air_launch", "execute":
			Vfx.launch_ring(pos, Vector3.UP, col, 1.6)
			Vfx.shockwave(pos, Vector3.UP, Color.WHITE.lerp(col, 0.4), 2.0)
		"air_crash":
			Vfx.dun_slam(pos, col, 1.0)
			if heavy == 1:
				Vfx.ground_break(pos, 1.0, 5.0)
		"air_vanish":
			Vfx.vanish(pos, col)
		"air_awaken":
			Vfx.breakthrough(pos - Vector3.UP * 0.9, col, 1.0)
		"air_skill":
			Vfx.cast_flash(pos, col, 1.0)


# ---------- 地形破坏 ----------

## 我破开了一片地形：让别人那边也削掉
## bowl = true：斗法炸出来的碗形坑（半径 radius）；false：飞行破开的平底通道（削到 floor_y）
func send_dig(pos: Vector3, radius: float, floor_y: float, bowl := false) -> void:
	if active and _peer != null and players.size() > 1:
		_dig.rpc(pos, radius, floor_y, bowl)


@rpc("any_peer", "call_remote", "reliable")
func _dig(pos: Vector3, radius: float, floor_y: float, bowl: bool) -> void:
	if raid == null:
		return
	if bowl:
		raid.level.remote_blast(pos, clampf(radius, 1.0, 6.0))
	else:
		raid.level.world.dig(pos, clampf(radius, 0.5, 8.0), floor_y)


# ---------- 怪打别的玩家 ----------

## 我名下的怪打中了别的玩家：发给他本人结算
func send_mob_attack(to_id: int, nid: int, dmg: float, heavy: bool, dir: Vector3) -> void:
	if not active or _peer == null:
		return
	if players.has(to_id):
		_mob_attack.rpc_id(to_id, nid, dmg, heavy, dir)


@rpc("any_peer", "call_remote", "reliable")
func _mob_attack(nid: int, dmg: float, heavy: bool, dir: Vector3) -> void:
	if raid != null:
		stat["mobhit"] = int(stat["mobhit"]) + 1
		raid.net_mob_attack(multiplayer.get_remote_sender_id(), nid, dmg, heavy, dir)


# ---------- 飞剑对波（玩家之间） ----------

## op：0 我进对波了，你也进 · 1 我累计顶了 v · 2 我判了胜负（v = 1 我赢）· 3 我正朝你连发飞剑（亮预警）
func send_clash(to_id: int, op: int, v: float) -> void:
	if not active or _peer == null:
		return
	if not players.has(to_id):
		return
	if op == 1:
		_clash_push.rpc_id(to_id, v)
	else:
		_clash.rpc_id(to_id, op, v)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _clash_push(v: float) -> void:
	var r: Variant = remotes.get(multiplayer.get_remote_sender_id())
	if is_instance_valid(r):
		(r as Remote).clash_their = v


@rpc("any_peer", "call_remote", "reliable")
func _clash(op: int, v: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var r: Variant = remotes.get(from)
	if raid == null or not is_instance_valid(r) or is_mate(from):
		return
	match op:
		0:
			player.air.net_clash_begin(r, my_id < from)
		2:
			player.air.net_clash_result(v < 0.5)
		3:
			player.air.clash_warn(r)


# ---------- 雷劫（给旁观的人看） ----------

## ev：0 开始（a = 要突破到的境界）· 1 一道雷（a = 第几道，b = 位 0 挡下 / 位 1 完美 / 位 2 巨雷）· 2 结束（a = 1 成功）
func send_trib(ev: int, a: int, b: int) -> void:
	if active and players.size() > 1:
		_trib.rpc(ev, a, b)


@rpc("any_peer", "call_remote", "reliable")
func _trib(ev: int, a: int, b: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if raid != null:
		raid.net_trib(from, remotes.get(from), ev, a, b)


# ---------- 掉落物（全房间共享，拾取向房主申请） ----------

func send_drop(nid: String, pos: Vector3, item: Dictionary, items: Array, title: String) -> void:
	if active and players.size() > 1:
		_drop.rpc(nid, pos, item, items, title)


@rpc("any_peer", "call_remote", "reliable")
func _drop(nid: String, pos: Vector3, item: Dictionary, items: Array, title: String) -> void:
	if raid != null:
		raid.net_drop(nid, pos, item, items, title)


## 我想捡 nid：问房主
func send_claim(nid: String) -> void:
	if not active or _peer == null:
		return
	if is_host:
		_claim_on_host(nid, my_id)
	else:
		_claim.rpc_id(1, nid)


@rpc("any_peer", "call_remote", "reliable")
func _claim(nid: String) -> void:
	if is_host:
		_claim_on_host(nid, multiplayer.get_remote_sender_id())


func _claim_on_host(nid: String, by: int) -> void:
	if _claimed.has(nid):
		return      # 已经判给别人了
	_claimed[nid] = by
	_granted.rpc(nid, by)


@rpc("authority", "call_local", "reliable")
func _granted(nid: String, by: int) -> void:
	if raid != null:
		raid.net_granted(nid, by == my_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _mobs(batch: Array) -> void:
	if raid != null:
		raid.net_mob_apply(multiplayer.get_remote_sender_id(), batch)


# ---------- 命中 ----------

## 我打中了别的玩家（打在他的木偶上）：把这一下发给他，由他那边结算
func send_hit(to_id: int, info: Dictionary) -> void:
	if not active or _peer == null:
		return
	_hit.rpc_id(to_id, float(info.get("dmg", 0.0)), info.get("dir", Vector3.FORWARD) as Vector3, float(info.get("kb", 3.0)),
			bool(info.get("heavy", false)), str(info.get("launch", "")), bool(info.get("ranged", false)))


@rpc("any_peer", "call_remote", "reliable")
func _hit(dmg: float, dir: Vector3, kb: float, heavy: bool, launch: String, ranged: bool) -> void:
	var from := multiplayer.get_remote_sender_id()
	if raid == null or is_mate(from):
		return
	raid.net_take_hit(_remote(from), from, dmg, dir, kb, heavy, launch, ranged)


## 我打中了别人名下的怪：发给怪的主人结算
func send_mob_hit(owner_id: int, nid: int, dmg: float, dir: Vector3, heavy: bool, launch: String, kb: float) -> void:
	if not active or _peer == null:
		return
	_mob_hit.rpc_id(owner_id, nid, dmg, dir, heavy, launch, kb)


@rpc("any_peer", "call_remote", "reliable")
func _mob_hit(nid: int, dmg: float, dir: Vector3, heavy: bool, launch: String, kb: float) -> void:
	if raid != null:
		raid.net_mob_take(multiplayer.get_remote_sender_id(), nid, dmg, dir, heavy, launch, kb)


## 我名下的怪死了：告诉所有人（木偶播死亡、巢穴 Boss 记清、附近的队友 / 补刀的人分经验）
func send_mob_dead(nid: int, pos: Vector3, lv: int, xp_k: float, lair: int, last_hitter: int) -> void:
	if not active or _peer == null:
		return
	if lair >= 0 and is_host and not cleared.has(lair):
		cleared.append(lair)
	_mob_dead.rpc(nid, pos, lv, xp_k, lair, last_hitter)


@rpc("any_peer", "call_remote", "reliable")
func _mob_dead(nid: int, pos: Vector3, lv: int, xp_k: float, lair: int, last_hitter: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if lair >= 0 and is_host and not cleared.has(lair):
		cleared.append(lair)
	if raid != null:
		raid.net_mob_died(from, nid, pos, lv, xp_k, lair, last_hitter == my_id or is_mate(from))
