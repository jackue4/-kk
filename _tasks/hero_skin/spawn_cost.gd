extends SceneTree
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
func _init() -> void:
	for k: String in ["", "moyan", "bage", "evelyn", "aladeng"]:
		HeroSkin.profile(k)
	for rnd in 2:
		for k: String in ["", "moyan", "bage", "evelyn", "aladeng"]:
			var t0 := Time.get_ticks_usec()
			var h: VoxelHero = VoxelHero.new({}, true, false, 2, k)
			var t1 := Time.get_ticks_usec()
			get_root().add_child(h)
			var t2 := Time.get_ticks_usec()
			var n := 200
			if h.skin != null:
				for i in n:
					h.skin.sync()
			var t3 := Time.get_ticks_usec()
			print("%-8s 第 %d 次：建角色 %.1f ms，进树 %.1f ms，摆一次骨骼 %.1f 微秒（骨骼 %s 根）" % [k if k != "" else "方块小人", rnd + 1, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0,
					float(t3 - t2) / float(n), str(h.skin.get("_nb")) if h.skin != null else "-"])
			h.queue_free()
	quit()
