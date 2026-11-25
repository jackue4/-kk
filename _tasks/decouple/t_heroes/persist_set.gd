extends SceneTree
## T_heroes：英雄选择存进 raid_profile、下次开机还在。只碰自检存档（xiuxian_profile_selftest.json）。
## 第一步：`Godot --headless --path . -s res://_tasks/decouple/t_heroes/persist_set.gd -- --t-persist --keep-profile <英雄id>`
## 第二步：`Godot --headless --path . -- --keep-profile --hero-test=realm` → 开机那行 hero_id 应 = 这里设的
const Profile := preload("res://scripts/raid_profile.gd")

func _init() -> void:
	var want := "shuanghua"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			want = a
	if not Profile.test_mode():
		print("[t] 不是自检存档，不动")
		quit(1)
		return
	Profile.data()["live"] = null      # 上一轮自检没结算的局（只在自检档里）
	var err := Profile.set_hero(want)
	# 直接读文件核对
	var f := FileAccess.open(Profile.TEST_PATH, FileAccess.READ)
	var v: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var on_disk := str((v as Dictionary).get("hero", "")) if v is Dictionary else ""
	print("[t] set_hero(%s) → \"%s\"；文件里 hero = %s" % [want, err, on_disk])
	quit(0 if err == "" and on_disk == want else 1)
