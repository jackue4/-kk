extends Node3D
## VFX-sketchbook effects/fireball/fireball_core 原版火球（外壳 + 内核 + FireTrail 火团拖尾 + FireSmoke 烟）。
## 本项目改动：外壳网格用 mesh/fireball_shell_mesh.gd 在运行时拼（不导入 .obj）；out() 之后自己释放。
## 朝向：+Z 为飞行方向（原版 look_at(..., use_model_front = true)）。

const SHELL_MESH := preload("res://fx/fireball/mesh/fireball_shell_mesh.gd")

@onready var fireball_shell_mesh = %FireballShellMesh
@onready var fire_trail = %FireTrail
@onready var fire_smoke = %FireSmoke

signal is_out

var angular_vel : Vector3 = Vector3(0.0, 0.0, 0.0)
var last_direction : Vector3

func _ready():
	fireball_shell_mesh.mesh = SHELL_MESH.mesh()
	fireball_shell_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta):
	var direction = global_transform.basis.y
	angular_vel = angular_vel.move_toward((direction - last_direction), 0.1 * delta)
	last_direction = direction
	# angular_vel = angular_vel.move_toward(Vector3.ZERO, 0.1 * delta)

	fireball_shell_mesh.material_override.set_shader_parameter("def_x", -angular_vel.x * 4.0)
	fireball_shell_mesh.material_override.set_shader_parameter("def_z", angular_vel.z * 4.0)


## 熄灭：外壳隐藏、拖尾和烟停发，等已经飘出去的火团散完再释放（原版等 4s 发 is_out）
func out(linger := 1.2):
	fireball_shell_mesh.hide()
	fire_trail.emitting = false
	fire_smoke.emitting = false
	await get_tree().create_timer(linger).timeout
	is_out.emit()
	queue_free()
