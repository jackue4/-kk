extends SceneTree
## 大厅右上角「洞府」按钮的自检：起正常的主场景，等大厅好了之后调 hud 的 _open_abode，看洞府开没开、游戏停没停；
## 再关掉，看恢复没恢复。存两张图（大厅主界面 / 洞府开着）。
## 用法：python _tasks/trailer/run_hidden.py . _shots/abode_open --resolution 1600x900 -s res://_tasks/ui_kit/abode_open_test.gd -- <输出目录> --abode-open-test [--touch]
## 2026-11-25 主干解耦：必须带 --abode-open-test —— 存档走自检档（以前不带参数，开机会按玩家自己的档结算离线闭关并存盘）；
## 带了这个参数 level_select.open_abode 开的是老洞府 abode_ui.gd（主城默认开 meta_ui.gd，那边的自检是 meta_game_test.gd）

var _n := 0
var _main: Node
var _dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--abode-open-test"):
		push_error("要带 --abode-open-test（否则会读写玩家自己的存档）")
		quit(1)
		return
	_dir = args[0] if args.size() > 0 and not args[0].begins_with("--") else ProjectSettings.globalize_path("res://_shots/preview")
	_main = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	root.add_child(_main)


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(_dir.path_join(name + ".jpg"), 0.9)
	print("[abode] saved ", name)


func _process(_dt: float) -> bool:
	_n += 1
	var hud: Variant = _main.get("hud")
	if _n == 90:
		_save("ui_main_hall")
		print("[abode] 按钮可见=%s 位置=%s" % [hud._bag_btn.visible, hud._bag_btn.position])
		hud._open_abode()
		var ui: Variant = _main.get("level_ui")
		print("[abode] 打开后：洞府在=%s 暂停=%s 是老洞府=%s" % [is_instance_valid(ui._abode), paused,
				is_instance_valid(ui._abode) and (ui._abode.get_script() as Script).resource_path.ends_with("abode_ui.gd")])
	elif _n == 110:
		_save("ui_main_hall_abode")
		var ui2: Variant = _main.get("level_ui")
		if is_instance_valid(ui2._abode):
			ui2._abode._close()
	elif _n == 116:
		var ui3: Variant = _main.get("level_ui")
		print("[abode] 关掉后：洞府在=%s 暂停=%s" % [is_instance_valid(ui3._abode), paused])
		return true
	return false
