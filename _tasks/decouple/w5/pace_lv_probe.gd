extends SceneTree
## W5 探针（不进包）：跑 main 自带的 `--raid-shot --raid-pace` 的同时，旁听 level.raid._mobs——
## 每只新出现的怪记一次（等级 / 种类 / 精英 / 离主角多远刷出来），每只倒下的怪记它的等级，最后打印分布。
## 用法：Godot [--headless] --path <工程> -s <本文件> -- --raid-shot --raid-pace --pace-min=1 --pace-regions=4 --no-lan
## 只读工程的成员（鸭子类型），老 / 新两份工程都能跑。
var m: Node
var seen := {}
var spawned := {}     # lv -> 只数
var killed := {}      # lv -> 只数
var near_sp := {}     # lv -> 刷出时离主角 < 60 米的只数
var pace_on := false
var t_dump := 0.0


func _initialize() -> void:
	m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(m)
	(func() -> void: current_scene = m).call_deferred()


func _process(dt: float) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	var lvl: Variant = m.get("level")
	if lvl == null or not is_instance_valid(lvl):
		return false
	var rd: Variant = lvl.get("raid")
	if rd == null or not is_instance_valid(rd):
		return false
	if not pace_on:
		if Engine.time_scale > 1.5:
			pace_on = true      # 节奏段开始（pace 把 time_scale 设成 6）：之前刷的（出生点那些）不算
			for mb: Variant in rd.get("_mobs"):
				if is_instance_valid(mb):
					seen[mb.get_instance_id()] = true
		return false
	var p: Vector3 = m.player.global_position
	for mb: Variant in rd.get("_mobs"):
		if not is_instance_valid(mb) or seen.has(mb.get_instance_id()):
			continue
		seen[mb.get_instance_id()] = true
		var lv := int(mb.lv)
		spawned[lv] = int(spawned.get(lv, 0)) + 1
		if mb.global_position.distance_to(p) < 60.0:
			near_sp[lv] = int(near_sp.get(lv, 0)) + 1
		mb.died.connect(func(_x: Node3D) -> void:
			killed[lv] = int(killed.get(lv, 0)) + 1)
	t_dump += dt
	if t_dump > 2.0:
		t_dump = 0.0
		print("[lvp] 刷出 %s 近处刷出 %s 倒下 %s" % [str(spawned), str(near_sp), str(killed)])
	return false
