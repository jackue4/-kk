extends SceneTree
## QA 观察脚本（只读）：以 `-- --net=ally_mate` 跑 AI 道友联机自检的队友端，进图后每 0.1 秒记一次主角状态（找「连点两下跳没起飞」的原因）。

var m: Node
var _t0 := -1.0
var _next := 0.0
var _jp := 0


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
	if m == null or m.get("level") == null:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _t0 < 0.0:
		_t0 = now
	var t := now - _t0
	if Input.is_action_just_pressed("jump"):
		_jp += 1
		print("[obs] t=%.2f jump just_pressed #%d" % [t, _jp])
	if t < 8.0 or t > 14.0 or now < _next:
		return
	_next = now + 0.1
	var p: Node = m.get("player")
	var me: Node = p.get("melee")
	var th: Dictionary = p.get("threat")
	var who: Array = []
	for k: Variant in th.keys():
		if is_instance_valid(k):
			var kn := k as Node
			who.append("%s(%s puppet=%s 距%.1f)" % [kn.name, kn.get_script().resource_path.get_file() if kn.get_script() != null else kn.get_class(), kn.get("puppet"),
					(kn as Node3D).global_position.distance_to((p as Node3D).global_position)])
	print("[obs]   威胁：" + ", ".join(who))
	print("[obs] t=%.2f st=%d melee=%d busy=%s on_floor=%s dead=%s hp=%.0f vy=%.2f y=%.2f process=%d jump_pressed=%s" % [t, int(p.get("st")), int(me.get("state")),
			me.call("busy"), (p as CharacterBody3D).is_on_floor(), p.get("dead"), float(me.get("hp")), (p as CharacterBody3D).velocity.y,
			(p as Node3D).global_position.y, int(p.process_mode), Input.is_action_pressed("jump")])
