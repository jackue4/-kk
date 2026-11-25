extends "res://scripts/net.gd"
## 擂台对决的联机（2026-11-23，arena_duel.gd 建）：一场 1v1 = 一间只有两个人的小房间。
## 直接沿用大世界那套联机（net.gd：每秒 15 次的状态同步、对方在本机的木偶 remote_player.gd、命中转发、
## 飞剑 / 打击特效 / 飞剑对波的同步），所以对决里别人的样子、受击、对波和大世界里的 PvP 是同一套；这里只换三样：
##   · 自己单独一套 MultiplayerAPI（挂在自己这个节点的路径上）：不占大世界房间那条连接——房主回了主城、房间还开着的时候照样能上擂台
##   · 自己的端口和局域网发现：同一座擂台上排队的人互相看得见（广播「XXARENA|擂台|令牌|端口|名字|等级」），大世界的选关界面看不到这种房间；
##     同一台电脑上开两个窗口也能配上（发现端口、房间端口各试三个，广播同时发给本机）
##   · 「大世界」换成 arena_duel.gd（它照着 raid_manager.gd 给 net.gd 用的那几个接口写了一份：lv / net_take_hit / net_deal_hit……）
## 网页版没有 UDP / ENet：arena_duel.gd 在网页上根本不建这个节点（十秒后直接来 AI 陪练）。
## 故意不写 class_name：用 preload 引用。

const A_TAG := "XXARENA"
const A_DISC: Array[int] = [24691, 24692, 24693]     # 发现端口：同一台机器上第二个窗口绑下一个
const A_PORTS: Array[int] = [24695, 24696, 24697]    # 对决房间的端口
const A_CAST := 0.35          # 开着房间等人时多久广播一次
const A_STALE := 1.6          # 这么久没再听到的房间当它没了
## 自检 / 演示模式（命令行带了别的参数）端口整体 +A_TEST_OFF：自动化测试的窗口不会和正在玩的人配到一起
const A_TEST_OFF := 100
const AProfile := preload("res://scripts/raid_profile.gd")

var side := -1                # 在哪座擂台上排队（-1 = 没在排）
var token := 0                # 这次排队的令牌（区分是不是自己的广播；两个人同时开了房间时，令牌小的那个让）
var my_lv := 1
var game_port := 0
var found := {}               # 令牌 -> {ip, side, port, name, lv, t}

var _api: SceneMultiplayer
var _a_in: PacketPeerUDP
var _a_out: PacketPeerUDP
var _a_cast_t := 0.0
var _prev_sink := Callable()
var _a_off := 0


func _enter_tree() -> void:
	if _api == null:
		_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(_api, get_path())


func _exit_tree() -> void:
	queue_end()
	if Proj.net_sink == Callable(self, "_sink"):
		Proj.net_sink = _prev_sink
	get_tree().set_multiplayer(null, get_path())


func _ready() -> void:
	# 飞剑 / 法术的转发口只有一个（spell_projectile.gd 的 net_sink）：大世界那份联机先占着，这里接在它后面，两边各看各的房间
	_a_off = A_TEST_OFF if AProfile.test_mode() else 0
	var prev: Callable = Proj.net_sink
	super()
	_prev_sink = prev
	Proj.net_sink = _sink


func _sink(k: int, from: Vector3, tgt: Variant, aim: Vector3, opts: Dictionary) -> void:
	if _prev_sink.is_valid():
		_prev_sink.call(k, from, tgt, aim, opts)
	_on_proj(k, from, tgt, aim, opts)


# ---------- 排队：局域网里找同一座擂台上的人 ----------

func queue_begin(arena_side: int, lv: int) -> void:
	queue_end()
	side = arena_side
	my_lv = lv
	token = (randi() & 0x3fffffff) | 1
	found.clear()
	_a_in = PacketPeerUDP.new()
	var bound := false
	for port: int in A_DISC:
		if _a_in.bind(port + _a_off) == OK:
			bound = true
			break
	if not bound:
		_a_in = null
	_a_out = PacketPeerUDP.new()
	_a_out.set_broadcast_enabled(true)
	_a_cast_t = 0.0


func queue_end() -> void:
	side = -1
	found.clear()
	if _a_in != null:
		_a_in.close()
		_a_in = null
	if _a_out != null:
		_a_out.close()
		_a_out = null


## 同一座擂台上、别人开着等人的房间（没有返回空表）。两个人都开了房间时只认令牌比自己大的（小的让）
func pick_room() -> Dictionary:
	for k: int in found.keys():
		var e: Dictionary = found[k]
		if int(e["side"]) == side and (not (is_host and active) or k > token):
			return e
	return {}


## 覆盖 net.gd 的局域网发现（那边广播的是大世界房间）：只在排队时收发擂台的广播
func _tick_discovery(dt: float) -> void:
	if side < 0:
		return
	if is_host and active and players.size() < 2 and _a_out != null:
		_a_cast_t -= dt
		if _a_cast_t <= 0.0:
			_a_cast_t = A_CAST
			var msg := ("%s|%d|%d|%d|%s|%d" % [A_TAG, side, token, game_port, my_name, my_lv]).to_utf8_buffer()
			for addr: String in ["255.255.255.255", "127.0.0.1"]:
				for port: int in A_DISC:
					_a_out.set_dest_address(addr, port + _a_off)
					_a_out.put_packet(msg)
	if _a_in != null:
		while _a_in.get_available_packet_count() > 0:
			var s := _a_in.get_packet().get_string_from_utf8()
			var ip := _a_in.get_packet_ip()
			var parts := s.split("|")
			if parts.size() >= 6 and parts[0] == A_TAG and int(parts[2]) != token:
				found[int(parts[2])] = {"ip": ip, "side": int(parts[1]), "port": int(parts[3]), "name": str(parts[4]).substr(0, 12),
						"lv": int(parts[5]), "t": 0.0}
	for k: int in found.keys():
		var e: Dictionary = found[k]
		e["t"] = float(e["t"]) + dt
		if float(e["t"]) > A_STALE:
			found.erase(k)


# ---------- 开房 / 加入（net.gd 的 host / join 写死了大世界的端口，这里各写一份） ----------

## 开一间等人的房间（只收一个人）。端口都被占了返回 false
func open_room() -> bool:
	leave()
	game_port = 0
	for port: int in A_PORTS:
		var p := ENetMultiplayerPeer.new()
		if p.create_server(port + _a_off, 1) == OK:
			_peer = p
			game_port = port + _a_off
			break
	if game_port == 0:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	my_id = 1
	team_size = 1
	seed_v = 0
	cleared.clear()
	room_t = 0.0
	drop_n = 0
	_claimed.clear()
	players.clear()
	_next_team = 2
	players[1] = {"name": my_name, "team": 1, "size": 1, "realm": player.realm_idx, "hero": _my_hero()}
	welcomed = true
	roster_changed.emit()
	return true


## 连到别人开着的房间；等房主回话最多 timeout 秒。成功返回 true（这时名单上已经是两个人）
func join_room(ip: String, port: int, timeout := 3.0) -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(ip, port) != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	team_size = 1
	welcomed = false
	drop_n = 0
	var t := 0.0
	while t < timeout and not welcomed:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and my_id == 1:
			my_id = multiplayer.get_unique_id()
			_hello.rpc_id(1, my_name, 1, player.realm_idx, map_id, _my_hero())     # 2026-11-24 握手加了地图 / 英雄（net.gd）
	if not welcomed:
		leave()
	return welcomed


## 对手的编号（房间里除了我的那个；没有返回 0）
func rival_id() -> int:
	for id: int in players.keys():
		if id != my_id:
			return id
	return 0
