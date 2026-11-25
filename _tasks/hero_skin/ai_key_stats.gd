extends SceneTree
## AI 样式分配的分布（hero_skin.gd 的 ai_key）：把游戏里 AI 会用到的名字都过一遍，看四种样式各占多少、几个固定名字各是什么样。
## 用法：Godot --headless --path . -s res://_tasks/hero_skin/ai_key_stats.gd

const HeroSkin := preload("res://scripts/hero_skin.gd")
const Data := preload("res://scripts/raid_data.gd")


func _init() -> void:
	var nicks: Array = (load("res://scripts/net.gd") as GDScript).get_script_constant_map().get("NICKS", [])
	var groups := {"其他修士（raid_data 的 AI_NAMES）": Data.AI_NAMES, "擂台陪练（陪练·昵称）": [], "AI 道友（昵称 + 两位数）": []}
	for n: String in nicks:
		(groups["擂台陪练（陪练·昵称）"] as Array).append("陪练·" + n)
		for i in 100:
			(groups["AI 道友（昵称 + 两位数）"] as Array).append("%s%02d" % [n, i])
	for g: String in groups:
		var cnt := {}
		for n: String in groups[g]:
			var k := HeroSkin.ai_key(n)
			cnt[k if k != "" else "方块小人"] = int(cnt.get(k if k != "" else "方块小人", 0)) + 1
		print("%s：%d 个名字 → %s" % [g, (groups[g] as Array).size(), cnt])
	var fixed: Array = ["魔修·厉无咎", "陪练·青禾", "陪练木人"]
	var spar: Variant = load("res://scripts/spar_zone.gd")
	if spar != null and (spar as GDScript).get_script_constant_map().has("TIERS"):
		for t: Variant in (spar as GDScript).get_script_constant_map()["TIERS"]:
			if t is Dictionary and (t as Dictionary).has("title"):
				fixed.append(str(t["title"]))
			elif t is Array and (t as Array).size() > 0 and (t as Array)[0] is String:
				fixed.append(str((t as Array)[0]))
	for n: String in fixed:
		var k := HeroSkin.ai_key(n)
		print("  %s → %s" % [n, k if k != "" else "方块小人"])
	quit()
