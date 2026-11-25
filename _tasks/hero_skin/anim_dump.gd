extends SceneTree
## 看导进来的动画：每段的长度、轨道数、根骨骼位移的范围（判断是不是原地动画）。
## 用法：Godot --headless --path . -s res://_tasks/hero_skin/anim_dump.gd


func _init() -> void:
	var root := (load("res://assets/hero/aladeng.glb") as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var aps: Array = root.find_children("*", "AnimationPlayer", true, false)
	print("AnimationPlayer: ", aps.size())
	for ap: AnimationPlayer in aps:
		print(" root_node=", ap.root_node, " libs=", ap.get_animation_library_list(), " list=", ap.get_animation_list())
		for nm in ap.get_animation_list():
			var a := ap.get_animation(nm)
			var kinds := {}
			var sample := []
			for t in a.get_track_count():
				var k := a.track_get_type(t)
				kinds[k] = int(kinds.get(k, 0)) + 1
				var path := str(a.track_get_path(t))
				if sample.size() < 3:
					sample.append(path)
				if path.ends_with(":Bip01") and k == Animation.TYPE_POSITION_3D:
					var lo := Vector3.INF
					var hi := -Vector3.INF
					for i in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, i)
						lo = lo.min(v)
						hi = hi.max(v)
					print("   Bip01 位移范围 ", lo, " ~ ", hi, " 键 ", a.track_get_key_count(t))
			print("  ", nm, " 长 ", a.length, " 循环 ", a.loop_mode, " 轨道 ", a.get_track_count(), " 种类 ", kinds, " 例 ", sample)
	quit()
