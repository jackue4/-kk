extends Node
## 苍鸿重构的调试小工具（只在命令行带 --cg-test 时由 kit_canghong2.gd 挂上）：
##   · 每次归剑（kit._gj_on 由假变真）连拍一组：定格 → 引爆 → 炸完，存 _shots/preview/tsb_cg_gj<N>_<i>.jpg
##   · 每次起招架（听风 / 剑域）0.15 秒后替木桩朝主角「打」一下（剑域再补一下），打印招架结果
## 配合 `-- --tsb-show=canghong --tsb-only=z,az,... --cg-test` 用。
var kit: Node
var player: Player
var _gj_prev := false
var _n := 0
var _parry_prev := false


func _process(_dt: float) -> void:
	if kit == null or not is_instance_valid(kit) or player == null:
		return
	var gj := bool(kit.get("_gj_on"))
	if gj and not _gj_prev:
		_n += 1
		_burst("gj%d" % _n, [0.0, 0.14, 0.28, 0.4, 0.5, 0.6, 0.72, 0.95])
	_gj_prev = gj
	var pt: bool = player.air.parry_t > 0.0
	if pt and not _parry_prev:
		_sim_attack()
	_parry_prev = pt


func _burst(tag: String, times: Array) -> void:
	var t0 := Time.get_ticks_msec()
	var snaps: Array = []
	var k := 0
	while k < times.size():
		if (Time.get_ticks_msec() - t0) * 0.001 >= float(times[k]):
			k += 1
			await RenderingServer.frame_post_draw
			snaps.append(get_viewport().get_texture().get_image())
		else:
			await get_tree().process_frame
	for i in snaps.size():
		var img: Image = snaps[i]
		img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.save_jpg("res://_shots/preview/tsb_cg_%s_%d.jpg" % [tag, i], 0.86)
	print("[cgtest] 连拍 %s：%d 张，剑痕累计 %d，已引爆 %d 道，引爆伤害 %.1f" % [tag, snaps.size(), int(kit.stat["marks"]), int(kit.stat["det"]), float(kit.stat["det_dmg"])])


func _foe() -> Node3D:
	var t: Node3D = player.air.target
	if t != null and is_instance_valid(t):
		return t
	var best: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if e != null and (best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = e
	return best


func _sim_attack() -> void:
	await get_tree().create_timer(0.15, true, false, true).timeout
	var f := _foe()
	if f == null:
		return
	var dom: bool = player.air.parry_r > 0.0
	var p0 := player.global_position
	var r: int = player.air.receive_attack(f, {"dmg": 9.0, "dir": (player.center() - f.global_position).normalized(), "heavy": false,
			"contact": player.center(), "kb": 5.0})
	print("[cgtest] 招架（%s）第一下：结果 %d（2 = 招架反斩）" % ["剑域" if dom else "听风", r])
	await get_tree().create_timer(0.1, true, false, true).timeout
	print("[cgtest] 闪到 %.1f 米外，招 %s" % [player.global_position.distance_to(p0), player.air.move_id])
	if dom:
		await get_tree().create_timer(0.55, true, false, true).timeout
		var r2: int = player.air.receive_attack(f, {"dmg": 9.0, "dir": Vector3.FORWARD, "heavy": false, "contact": player.center(), "kb": 5.0})
		print("[cgtest] 剑域第二下：结果 %d，已接 %d 下，剩 %.2f 秒" % [r2, player.air.parry_n, player.air.parry_t])
