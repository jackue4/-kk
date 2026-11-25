extends SceneTree
## W5 探针（不进包）：自检档下局域网在场是否静默（不广播、不飘上线），带 --lan-test 时照常广播。
## 用法：Godot --headless --path . -s res://_tasks/decouple/w5/lan_quiet_probe.gd -- --qa-w5lan [--lan-test=probe]
var m: Node


func _initialize() -> void:
	m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(m)
	(func() -> void: current_scene = m).call_deferred()
	_run.call_deferred()


func _run() -> void:
	var t := 0.0
	while t < 60.0:
		var hub: Variant = m.get("hub")
		if hub != null and bool(hub.get("active")):
			break
		await process_frame
		t += 0.016
	await create_timer(4.0, true, false, true).timeout
	var pres: Variant = m.get("hub").get("presence")
	print("[w5lan] enabled %s quiet %s port %d sent %d got %d known %d" % [str(pres.get("enabled")), str(pres.get("quiet")), int(pres.get("_port")),
			int(pres.get("sent")), int(pres.get("got")), (pres.get("_known") as Dictionary).size()])
	quit(0)
