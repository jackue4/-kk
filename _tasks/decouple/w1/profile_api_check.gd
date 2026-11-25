extends SceneTree
## W1 自检：raid_profile 新接口 + 名牌文字。`Godot --headless --path . --script res://_tasks/decouple/w1/profile_api_check.gd -- --w1-check`
## 带了 --w1-check（非 PLAY_ARGS）→ 走自检存档，不碰玩家的档。
const Profile := preload("res://scripts/raid_profile.gd")
const HeroDefs := preload("res://scripts/hero_defs.gd")
const Remote := preload("res://scripts/remote_player.gd")

var fails := 0

func ck(ok: bool, what: String) -> void:
	print("[w1] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _init() -> void:
	ck(Profile.test_mode(), "自检存档")
	ck(Profile.hero() == HeroDefs.DEFAULT, "默认英雄 %s" % Profile.hero())
	ck(Profile.hero_ids() == HeroDefs.ids() and Profile.hero_ids().size() == 3, "hero_ids 全部 %s" % str(Profile.hero_ids()))
	ck(Profile.set_hero("canghong") == "" and Profile.hero() == "canghong", "set_hero canghong")
	ck(Profile.set_hero("nobody") == "未知英雄" and Profile.hero() == "canghong", "未知英雄")
	Profile.data()["live"] = {"gear": [], "carry": []}
	ck(Profile.set_hero("shuanghua") == Profile.RAID_LOCK and Profile.hero() == "canghong", "局内锁")
	Profile.data()["live"] = null
	var st := Profile.stats()
	ck(st.has("kills") and st.has("pk_kills") and st.has("arena_wins"), "stats 新键 %s" % str(st))
	Profile.add_stat("kills")
	Profile.add_stat("pk_kills", 3)
	ck(int(Profile.stats()["kills"]) == 1 and int(Profile.stats()["pk_kills"]) == 3, "add_stat")
	var ls := Profile.lingshi()
	Profile.add_lingshi(50)
	ck(Profile.lingshi() == ls + 50, "add_lingshi +50")
	Profile.add_lingshi(-99999)
	ck(Profile.lingshi() == 0, "add_lingshi 不低于 0")
	# 坏数据回落：读一份 hero 不认识、stats 缺键的档
	Profile.data()["hero"] = "xx"
	(Profile.data()["stats"] as Dictionary).erase("arena_wins")
	Profile._fix_types()
	ck(Profile.data()["hero"] == HeroDefs.DEFAULT and int(Profile.stats()["arena_wins"]) == 0, "_fix_types 回落 / 补键")
	ck(Remote.realm_tag(3, 11) == "元婴期 第2层", "名牌 " + Remote.realm_tag(3, 11))
	ck(Remote.realm_tag(0, 1) == "炼气期 第1层", "名牌 " + Remote.realm_tag(0, 1))
	print("[w1] 结论 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit()
