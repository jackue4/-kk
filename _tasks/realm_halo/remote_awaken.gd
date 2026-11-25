extends SceneTree
## 别的玩家觉醒时的光环（remote_player.gd 的 awaken_fx → awaken_fx.gd → realm_halo.gd）离线自检：不连网、不开房间，
## 直接建一个联机木偶让它觉醒，转它的朝向，看光环是不是立在它背后、跟着转、觉醒结束收掉、换了境界换一套。
## 用法：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1280x720 [--rendering-method gl_compatibility]
##        -s res://_tasks/realm_halo/remote_awaken.gd
## 截图 _tasks/realm_halo/shots/remote_<n>.jpg；最后一行 [remote-halo] 通过 N / M。

const RemotePlayer := preload("res://scripts/remote_player.gd")
const RealmHalo := preload("res://scripts/realm_halo.gd")

var _cam: Camera3D
var _ok := 0
var _all := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, pass_: bool, note := "") -> void:
	_all += 1
	if pass_:
		_ok += 1
	print("[remote-halo] %s %s %s" % ["通过" if pass_ else "没过", name, note])


func _wait(secs: float) -> void:
	await create_timer(secs).timeout


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.position = Vector3(5.0, 3.0, 7.0)
	_cam.look_at(Vector3(0.0, 1.6, 0.0))
	_cam.make_current()
	var rp: Node3D = RemotePlayer.new()
	rp.set("realm_idx", 3)
	rp.set("qi", Color(0.7, 0.5, 1.0))
	world.add_child(rp)
	rp.set_process(false)             # 不让它等网络状态；觉醒表现是它身上另一个节点自己跑的
	rp.set_physics_process(false)
	rp.visible = true
	rp.position = Vector3(0.0, 1.0, 0.0)
	await _wait(0.3)
	var visual: Node3D = rp.get("visual")
	# 1 觉醒：光环建出来、看得见、立在背后
	rp.call("awaken_fx", 4.0)
	await _wait(1.3)
	var fx: Node3D = rp.get("_awake_fx")
	var halo: Node3D = fx.get("_halo") if fx != null else null
	_check("觉醒后建出光环", halo != null and halo.visible, "档位 %s" % (str(halo.get("tier")) if halo != null else "-"))
	if halo == null:
		print("[remote-halo] 通过 %d / %d" % [_ok, _all])
		quit()
		return
	var pl: Dictionary = RealmHalo.place(3)
	var want := rp.global_position + Vector3.UP * float(pl["cy"]) + visual.global_basis.z.normalized() * float(pl["dist"])
	_check("立在背后（离身后 %.2f 米、高 %.2f 米）" % [float(pl["dist"]), float(pl["cy"])], halo.global_position.distance_to(want) < 0.12,
			"差 %.2f 米" % halo.global_position.distance_to(want))
	await _shot(1)
	# 2 转身 130 度：光环跟到新的背后
	visual.rotation.y += deg_to_rad(130.0)
	await _wait(0.12)
	var mid := rp.global_position + Vector3.UP * float(pl["cy"]) + visual.global_basis.z.normalized() * float(pl["dist"])
	var lag := halo.global_position.distance_to(mid)
	await _wait(1.0)
	_check("转身后跟到背后", halo.global_position.distance_to(mid) < 0.12, "刚转完差 %.2f 米（有一点拖尾），一秒后差 %.2f 米" % [lag, halo.global_position.distance_to(mid)])
	await _shot(2)
	# 3 觉醒结束：收掉
	await _wait(2.6)
	_check("觉醒结束后收掉", not halo.visible)
	# 4 换了境界再觉醒：换成那一档
	rp.set("realm_idx", 7)
	rp.call("awaken_fx", 3.0)
	await _wait(1.3)
	var halo2: Node3D = fx.get("_halo")
	_check("换境界后换一套", halo2 != null and halo2 != halo and int(halo2.get("tier")) == 7 and halo2.visible, "档位 %s" % str(halo2.get("tier")))
	await _shot(3)
	# 5 人不在场（隐藏）：马上淡掉
	rp.visible = false
	await _wait(0.5)
	_check("人不在场时收掉", not halo2.visible)
	print("[remote-halo] 通过 %d / %d" % [_ok, _all])
	quit()


func _shot(n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(800, int(800.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_tasks/realm_halo/shots"))
	img.save_jpg("res://_tasks/realm_halo/shots/remote_%d.jpg" % n, 0.88)
