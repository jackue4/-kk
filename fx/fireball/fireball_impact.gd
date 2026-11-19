extends Node3D
## VFX-sketchbook effects/fireball/fireball_impact 原版命中（爆闪 + 火星拖尾 + 烟 + 火团）。
## 本项目改动：爆闪的随机大小改成乘在已有缩放上（SpellProjectile._fx_scaled 会先把它放大到场景尺度）。

@onready var animation_player = %AnimationPlayer
@onready var flash = %Flash

func _ready():
	flash.scale *= randfn(1.0, 0.1)
	animation_player.play("default")
	var queue_timer = get_tree().create_timer(4.0)
	queue_timer.connect("timeout", queue_free)
