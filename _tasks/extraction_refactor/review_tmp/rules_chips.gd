extends SceneTree
const ExData := preload("res://scripts/ex/ex_data.gd")
func _init() -> void:
	var ids: Array = []
	for k in ExData.TABLES.keys():
		pass
	# find a chip id and a sell id from the shop / pools
	var chip := {}
	var sell := {}
	for id in ["chip_regen_8", "chip_shell_8", "chip_pierce_8"]:
		var it := ExData.make(id)
		if not it.is_empty():
			chip = it
			break
	if chip.is_empty():
		for c in ExData.shop("chip"):
			var it2: Dictionary = ExData.make(str(c.get("id", c)) if c is Dictionary else str(c))
			if not it2.is_empty():
				chip = it2
				break
	print("chip: ", chip.get("id"), " kind=", chip.get("kind"), " value=", ExData.value_of(chip), " can_sell=", ExData.can_sell(chip))
	var bag: Array = [chip.duplicate(true)]
	var eq := ExData.empty_equip()
	eq["chip"][0] = chip.duplicate(true)
	var rng := RandomNumberGenerator.new()
	var d := ExData.death_drops(bag, eq, rng)
	print("dropped chips=", (d["chips"] as Array).size(), " bag after death: ", bag.map(func(x): return x.get("id")), " equip chips: ", eq["chip"])
	quit()
