extends SceneTree
## QA 观察脚本（只读测试，不改产品代码）：以 `-- --net=mate` 跑 main 自带的联机自检（队友乙），
## 在房主丢下共享掉落、它出现在我脚边时，替玩家「点一下拾取卡片」（raid_manager.pick_up，和 raid_hud 拾取卡片的按钮同一个入口），
## 看：申请发给房主 → 批下来进我的背包 → 三边地上都消失。另两个实例照常跑 `--net=host`、`--net=foe`。

var m: Node
var _done := false
var _t := 0.0


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m


func _on_frame() -> void:
	if _done or m == null or m.get("level") == null:
		return
	var lv: Node = m.get("level")
	if not is_instance_valid(lv):
		return
	var rd: Node = lv.get("raid")
	if rd == null:
		return
	var drops: Dictionary = rd.get("_drops")
	for nid: String in drops.keys():
		var pk: Variant = drops[nid]
		if not nid.begins_with("1:") or not is_instance_valid(pk):
			continue
		if float((pk as Node).get("grace")) > 0.0:
			continue
		_done = true
		var me: Node3D = m.get("player") as Node3D
		var bag0: int = (rd.get("bag") as Array).size()
		var dist := (pk as Node3D).global_position.distance_to(me.global_position)
		var near: Array = rd.get("near_loot")
		print("[qpick] 看到房主的共享掉落 %s，离我 %.1f 米，在拾取卡片列表里=%s；替玩家点拾取（raid_manager.pick_up）" % [nid, dist, near.has(pk)])
		rd.call("pick_up", pk)
		_after(rd, nid, bag0)
		return


func _after(rd: Node, nid: String, bag0: int) -> void:
	await create_timer(1.0).timeout
	var drops: Dictionary = rd.get("_drops")
	print("[qpick] 点拾取 1 秒后：我的背包 %d -> %d；我这边地上还有这件=%s" % [bag0, (rd.get("bag") as Array).size(), drops.has(nid)])
