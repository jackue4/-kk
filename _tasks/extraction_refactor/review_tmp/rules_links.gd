extends SceneTree
const MapDef := preload("res://scripts/ex/map_def.gd")
func _init() -> void:
	for id in ["desert", "lab"]:
		var m: Dictionary = MapDef.map(id)
		var links: Array = m["links"]
		print("== ", id, " links ", links.size(), " keys ", (links[0] as Dictionary).keys() if links.size() > 0 else [])
		for b: Dictionary in m["bosses"]:
			var bp: Vector3 = b["pos"]
			var best := INF
			var bl := ""
			for l: Dictionary in links:
				for k in l.keys():
					var v = l[k]
					if v is Vector3:
						var d := Vector2(v.x - bp.x, v.z - bp.z).length()
						if d < best:
							best = d
							bl = "%s.%s" % [str(l.get("id", "?")), k]
			var sp_best := INF
			for s: Dictionary in m["spawns"]:
				var sv: Vector3 = s["pos"]
				sp_best = minf(sp_best, sv.distance_to(bp))
			print("boss ", b["key"], " summon=", b.get("summon", false), " nearest link pt ", bl, " %.1f m" % best, "  nearest spawn %.1f m" % sp_best)
	quit()
