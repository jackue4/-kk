extends Node3D
## 大厅择境门门心里的预览世界（LevelPortal 的 SubViewport 里）：就是现在大世界的出生点那一带——
## 同一套方块地形、暮色天空和灯火（block_world.gd），只铺门口前方几圈地块，不带怪。
## 故意不写 class_name：用 preload 引用。

const BlockWorld := preload("res://scripts/block_world.gd")
const LevelPortal := preload("res://scripts/level_portal.gd")

var world: BlockWorld


## 预览世界里「那一头的门」：出生点往南退一点，朝北看过去（黄枫谷方向，地平线上是暮色）
static func eye() -> Transform3D:
	var w := BlockWorld.new()
	var p := Vector3(6.0, 0.0, 26.0)
	p.y = w.height(p.x, p.z) + LevelPortal.LIFT
	w.free()
	return Transform3D(Basis.looking_at(Vector3(-0.2, 0.0, -1.0).normalized(), Vector3.UP), p)


func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = BlockWorld.make_environment()
	add_child(we)
	var sun := BlockWorld.make_sun()
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var anchor := Node3D.new()
	add_child(anchor)
	world = BlockWorld.new()
	world.target = anchor
	world.mobile = true     # 预览只要近处几圈
	add_child(world)
