extends SceneTree
## 场景破坏联机那一段的逻辑自检（不起连接、不占端口）：房主记操作的去重、换房清空、收到一条时的夹取、三个 RPC 都登记上了。
## 真正两台机器之间的收发没法在这里验（副本房间是固定端口，局域网里可能有人在玩）。
##   Godot --headless --path . -s res://_tasks/destruct/net_logic_test.gd
func _init() -> void:
	var fails := 0
	for path: String in ["res://scripts/net.gd", "res://scripts/arena_net.gd"]:
		var n: Node = (load(path) as GDScript).new()
		n.set("is_host", true)
		n.set("seed_v", 77)
		n.call("_dx_note", 0, Vector3(1, 2, 3), Vector3.ZERO, 4.0, 1.0)
		n.call("_dx_note", 0, Vector3(1.2, 2, 3), Vector3.UP, 4.1, 1.0)        # 同一处、差不多大：不记
		n.call("_dx_note", 2, Vector3(1, 2, 3), Vector3.ZERO, 4.0, 1.0)          # 浅坑是另一种
		n.call("_dx_note", 0, Vector3(1, 2, 3), Vector3.ZERO, 7.0, 1.0)          # 大得多：记
		n.call("_dx_note", 1, Vector3(1, 2, 3), Vector3(30, 2, 3), 5.0, 1.0)
		n.call("_dx_note", 1, Vector3(1, 2, 3), Vector3(30, 2, 3.2), 5.0, 1.0)   # 同一道沟：不记
		n.call("_dx_note", 1, Vector3(1, 2, 3), Vector3(30, 2, 9), 5.0, 1.0)     # 终点不同：记
		var a := (n.call("dx_local_log") as Array).size()
		n.call("_dx", 0, Vector3(50, 0, 50), Vector3.ZERO, 99.0, 9.0)             # 不在图里（raid 为空）：只记不做；半径 / 力度夹住
		var lg: Array = n.call("dx_local_log")
		var last: Array = lg.back()
		n.set("seed_v", 78)
		var b := (n.call("dx_local_log") as Array).size()
		n.set("is_host", false)
		n.call("_dx_note", 0, Vector3(1, 2, 3), Vector3.ZERO, 4.0, 1.0)
		var c := (n.get("_dx_log") as Array).size()
		var cfg: Variant = (n.get_script() as Script).get_rpc_config()
		var seen := {}
		var p: Script = n.get_script()
		while p != null:
			var d: Variant = p.get_rpc_config()
			if d is Dictionary:
				for k: Variant in (d as Dictionary).keys():
					if str(k) in ["_dx", "_dx_sync_req", "_dx_sync"]:
						seen[str(k)] = true
			p = p.get_base_script()
		var have := seen.size()
		var ok := a == 5 and lg.size() == 6 and float(last[3]) == 16.0 and float(last[4]) == 3.0 and b == 0 and c == 0 and have == 3
		print("[dxnet] %s %s · 去重后 %d 条（应 5）· 收到一条后 %d 条、半径夹到 %.0f 力度 %.0f · 换房后 %d 条 · 不是房主不记 %d · RPC 登记 %d / 3" % [path,
				"PASS" if ok else "FAIL", a, lg.size(), float(last[3]), float(last[4]), b, c, have])
		if not ok:
			fails += 1
		if cfg == null:
			pass
		n.free()
	quit(1 if fails > 0 else 0)
