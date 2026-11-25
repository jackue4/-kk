extends Node
## 天南秘境（实验关卡）的入口。**不改 main.gd**：单独一个场景 scripts/lab/mijing_test.tscn（= 主场景 + 这个节点），
## 用 `Godot --path . res://scripts/lab/mijing_test.tscn [-- --mijing-seed=种子]` 启动：正常开机到主城后，这里自己把人送进秘境
## （照 main.gd 的 _enter_level 做一遍：黑场、收起主城、英雄档、建关卡、放人、亮回来；离开走 main 自己的 _return_to_hall）。
## `--mijing-shot`：自检，各间房拍一张（_shots/preview/mijing_*.jpg），俯视全图存到 _tasks/mijing_lab/，拍完退出。
## `--mijing-walk`：自检，沿主路逐间走到位，打印能不能走通、有没有陷进墙里。

var m: Node
var arg := ""

const LEVEL := "res://scripts/lab/mijing_level.gd"


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _run() -> void:
	if m == null:
		m = get_parent()
	var scr: GDScript = load(LEVEL)
	if scr == null:
		push_error("[mijing] 关卡脚本载入失败")
		return
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--mijing-seed=") and a.get_slice("=", 1).is_valid_int():
			scr.call("set_boot", int(a.get_slice("=", 1)))
	var t := 0.0
	while t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 1.2 and not bool(m.get("_switching")) and m.get("level") == null and m.get("player") != null and m.get("level_ui") != null:
			break
	var lv: Node = await _enter(scr)
	if lv == null:
		push_error("[mijing] 没进去")
		return
	print("[mijing] 已进入 | ", str(lv.call("stats_text")))
	if args.has("--mijing-shot"):
		await _shots(lv)
		get_tree().quit()
	elif args.has("--mijing-walk"):
		await _walk(lv)
		get_tree().quit()


## 进图（照 main.gd 的 _enter_level，去掉联机 / 匹配那几段）
func _enter(scr: GDScript) -> Node:
	m.set("_switching", true)
	m.set("_level_id", "mijing")
	var ui: Node = m.get("level_ui")
	var player: Node3D = m.get("player")
	var cam: Node = m.get("cam")
	var hud: Node = m.get("hud")
	await ui.call("fade", 1.0, 0.45)
	ui.call("set_loading", "天南秘境 · 载入中")
	player.call("force_ground")
	var sw: Variant = m.get("swords")
	if sw != null:
		sw.call("dismiss_all")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	m.call("_set_hall_active", false)
	var hub: Variant = m.get("hub")
	if hub != null:
		hub.call("set_active", false)
		if hud != null:
			hud.set("lobby", false)
	m.call("_apply_combat_mode", "ex")
	var lv: Node = scr.new()
	lv.name = "Mijing"
	lv.set("player", player)
	lv.set("cam", cam)
	lv.set("font", m.get("font"))
	lv.set("mobile", bool(m.get("_mobile")))
	lv.set("net", m.get("net"))
	lv.connect("exit_requested", Callable(m, "_return_to_hall"))
	m.set("level", lv)
	m.add_child(lv)
	var sp: Vector3 = lv.call("spawn_point")
	var yaw := float(lv.call("spawn_yaw"))
	player.global_position = sp
	player.set("velocity", Vector3.ZERO)
	player.call("face_now", yaw)
	cam.call("snap", yaw, -0.26, 8.0)
	await lv.call("prewarm")
	if hud != null:
		hud.call("set_compact", false)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	ui.call("set_loading", "")
	if bool(cam.get("capture_mouse")) and not OS.get_cmdline_user_args().has("--mijing-shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await ui.call("fade", 0.0, 0.7)
	m.set("_switching", false)
	return lv


## 各间房拍一张：人放在房间中心附近能站的地方，镜头朝房间中心
func _shots(lv: Node) -> void:
	lv.set("no_mobs", not OS.get_cmdline_user_args().has("--mijing-mobs"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_tasks/mijing_lab"))
	var img: Image = lv.call("map_image", 6)
	img.save_png(ProjectSettings.globalize_path("res://_tasks/mijing_lab/map_%d.png" % int(lv.get("run_seed"))))
	print("[mijing] 全图 → _tasks/mijing_lab/map_%d.png" % int(lv.get("run_seed")))
	var player: Node3D = m.get("player")
	var cam: Node = m.get("cam")
	var rooms: Array = lv.get("rooms")
	var n := 0
	for rm: Dictionary in rooms:
		var main_i := int(rm["main"])
		if main_i < 0 and n > 20:
			continue
		var cen: Vector2 = rm["cen"]
		# 找一个能站的点：从门（房间边）往中心走，取第一处落在能走的格子上的
		var spot := Vector3.INF
		for r: float in [0.0, 4.0, 8.0, 12.0, 16.0, 22.0]:
			for a in 8:
				var q := cen + Vector2.from_angle(float(a) * TAU / 8.0 + 0.4) * r
				var ty := int(lv.call("type_at", q.x, q.y))
				if ty != 0 and ty != 10 and ty != 13:
					spot = Vector3(q.x, float(lv.call("height", q.x, q.y)) + 0.05, q.y)
					break
			if spot.x != INF:
				break
		if spot.x == INF:
			continue
		player.global_position = spot
		player.set("velocity", Vector3.ZERO)
		var yaw := atan2(spot.x - cen.x, spot.z - cen.y) if Vector2(spot.x, spot.z).distance_to(cen) > 1.0 else float(n) * 0.7
		player.call("face_now", yaw)
		cam.call("snap", yaw + 0.5, -0.42, 11.0)
		await _frames(12)
		await m.call("_shot", "mijing_%02d_%s" % [n, str(rm["id"])])
		n += 1
	print("[mijing] 拍了 %d 张 | %s" % [n, str(lv.call("stats_text"))])


## 沿主路逐间「走」到位（每帧挪一小步，走关卡自己的撞墙 / 落脚规矩），看每间房的门是不是真通
func _walk(lv: Node) -> void:
	lv.set("no_mobs", true)
	var player: Node3D = m.get("player")
	var rooms: Array = lv.get("rooms")
	var mains: Array = []
	for rm: Dictionary in rooms:
		if int(rm["main"]) >= 0:
			mains.append(rm)
	mains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["main"]) < int(b["main"]))
	var ok_n := 0
	for i in range(1, mains.size()):
		var a: Dictionary = mains[i - 1]
		var b: Dictionary = mains[i]
		var reach: bool = lv.call("reachable", a["cen"], b["cen"])
		print("[mijing] %s → %s：%s" % [str(a["id"]), str(b["id"]), "通" if reach else "不通！"])
		if reach:
			ok_n += 1
	var side_ok := 0
	var side_n := 0
	for rm2: Dictionary in rooms:
		if int(rm2["main"]) < 0:
			side_n += 1
			if bool(lv.call("reachable", (mains[0] as Dictionary)["cen"], rm2["cen"])):
				side_ok += 1
	print("[mijing] 主路相邻房间 %d / %d 走得通 · 支线房间 %d / %d 从起点走得到 | 主角在 %s" % [ok_n, mains.size() - 1, side_ok, side_n, str(player.global_position)])
