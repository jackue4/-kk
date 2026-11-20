extends Node3D
## raid_hud_test.gd 用的假「搜打撤管理器」：只有 raid_hud.gd 每帧会读的那些字段 / 方法，数是写死的。

const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")


class Pk:
	extends Node
	var items: Array = []
	var item: Dictionary = {}


var running := true
var region := 0
var at_sea := false
var extract_k := 0.0
var extract_kind := ""
var search_k := 0.0
var search: Variant = null
var near_loot: Array = []
var insight := 137.0
var here_depth := 0.72
var here_lv := 4
var sup_gap := 0
var lv := 10
var player: Variant = null
var cam: Variant = null
var level: Variant = null
var bag: Array = []
var gear: Array = []
var ring: Array = []
var _loot: Array = []
var _need_key := -1


func time_left() -> float:
	return 18.0 * 60.0 + 7.0


func insight_cap() -> float:
	return 72000.0


func sup_dmg_k() -> float:
	return 0.3


func rotation_left() -> float:
	return 187.0


func net_on() -> bool:
	return false


func exp_ratio() -> float:
	return 0.4


func _shared(_pk: Variant) -> bool:
	return false


func set_loot(items: Array) -> void:
	var pk := Pk.new()
	pk.items = items
	add_child(pk)
	near_loot = [pk]
	_loot = items


func loot_entries() -> Array:
	var out: Array = []
	for j in _loot.size():
		out.append([near_loot[0], j, _loot[j]])
	return out


func pick_up(_pk: Variant, _idx := -1) -> void:
	pass


func pick_nearest() -> void:
	pass


func bag_used() -> int:
	return Items.slots_used(bag)


func bag_value() -> int:
	var v := 0
	for it: Dictionary in bag:
		v += int(it.get("value", 0))
	return v


func bag_actions(i: int) -> Array:
	var out: Array = []
	var k := str(bag[i]["kind"])
	if k == "pill" or k == "tool":
		out.append("use")
	elif k == "gear":
		out.append("equip")
	out.append("ring")
	out.append("drop")
	return out


func sort_bag() -> void:
	pass


func paid_cost() -> int:
	return 200
