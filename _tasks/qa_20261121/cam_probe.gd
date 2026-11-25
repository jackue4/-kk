extends SceneTree
## QA 探针（只观察、不改游戏）：跑 main 的 `--duel-shot --spark --spark-ai`（真人陪练对打 40 秒 + 魔修 25 秒），
## 开场把主角改成大乘（和镜头自检 D 段一样）；逐帧看镜头位置跳变（扣掉主角自身速度）和偏航角速度，
## 超过阈值就把当时双方状态、镜头内部量打出来，定位「单帧镜头跳 20~30 米」是哪种情形。
## 跑法：python run_hidden.py . <log> --resolution 1280x720 -s res://_tasks/qa_20261121/cam_probe.gd -- --duel-shot --spark --spark-ai [--touch]

var m: Node
var _prev_pos := Vector3.INF
var _prev_yaw := 99.0
var _prev_pl := Vector3.INF
var _prev_foe := Vector3.INF
var _prev_cine := 0.0
var _t := 0.0
var _set_realm := false
var _hits := 0
var _last_us := 0


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
	var now := Time.get_ticks_usec()
	var real := float(now - _last_us) * 1e-6 if _last_us > 0 else 0.016
	_last_us = now
	var rig: Node3D = m.get("cam") as Node3D
	var p: Node3D = m.get("player") as Node3D
	if rig == null or p == null:
		return
	_t += real
	if not _set_realm and _t > 1.6:
		_set_realm = true
		p.call("set_realm", 7, false)
		print("[cprobe] t=%.2f 主角改大乘" % _t)
	var air: Node = p.get("air")
	var foe: Node3D = air.get("target") as Node3D if air != null else null
	var c3d: Camera3D = rig.get("cam") as Camera3D
	var pos := c3d.global_position
	var yaw := float(rig.get("yaw"))
	var pl := p.global_position
	var fp := foe.global_position if is_instance_valid(foe) else Vector3.ZERO
	var cine := float(rig.get("cine_k"))
	if _prev_pos != Vector3.INF:
		var v := (p as CharacterBody3D).velocity.length()
		var jmp := pos.distance_to(_prev_pos) - v * real
		var dy := absf(wrapf(c3d.global_rotation.y - _prev_yaw, -PI, PI))
		var w := rad_to_deg(dy) / maxf(real, 0.004)
		if (jmp > 3.0 or (w > 900.0 and real < 0.1)) and _hits < 80:
			_hits += 1
			print("[cprobe] t=%.2f 镜头跳 %.1fm 转速 %.0f°/s｜主角移动 %.1fm（速度 %.0f）对手移动 %.1fm｜主角「%s」对手「%s」两人相距 %.1fm｜cine_k %.2f→%.2f hold %.2f duel=%s lock=%s 镜头-主角 %.1fm｜帧 %.1fms" % [
					_t, jmp, w, pl.distance_to(_prev_pl), v, fp.distance_to(_prev_foe) if _prev_foe != Vector3.INF else 0.0,
					str(air.call("state_name")) if air != null else "?", str(foe.call("state_name")) if is_instance_valid(foe) and foe.has_method("state_name") else "无",
					pl.distance_to(fp), _prev_cine, cine, float(rig.get("_hold")), rig.get("duel"), rig.get("lock") != null, pos.distance_to(pl), real * 1000.0])
	_prev_pos = pos
	_prev_yaw = c3d.global_rotation.y
	_prev_pl = pl
	_prev_foe = fp
	_prev_cine = cine
