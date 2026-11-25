extends Node3D
## 苍鸿的「剑痕」：目标身上悬着的那几道细白青色的痕（一个目标一个这样的节点，kit_canghong2.gd 建 / 管）。
## 跟着目标走，各是一根朝着镜头的细针形光；burst() = 一道一道炸亮然后收掉。只管画，伤害在技能脚本里。
## 单独一个文件（不做成技能脚本的内部类）：内部类 + 静态变量的脚本在退出时会留下一串「资源没释放」的报错。
## 故意不写 class_name。

var who: Node3D
var n := 0
var life := 6.0
var col := Color(0.45, 0.85, 1.0)
var _sp: Array = []
var _dir: Array = []
var _off: Array = []
var _len: Array = []
var _age: Array = []
var _t := 0.0
var _bursting := false

func center() -> Vector3:
	if not is_instance_valid(who):
		return global_position
	if who is EnemyDummy:
		return (who as EnemyDummy).aim_point()
	if who.has_method("center"):
		return who.call("center")
	return who.global_position + Vector3(0.0, 1.0, 0.0)

func set_n(k: int) -> void:
	while _sp.size() < k:
		var i := _sp.size()
		# 一道一个朝向：斜着交叉，不全平行
		var a := (0.6 + 0.75 * float(i)) * (1.0 if i % 2 == 0 else -1.0) + randf_range(-0.15, 0.15)
		var d := Vector3(cos(a), sin(a), randf_range(-0.35, 0.35)).normalized()
		_dir.append(d)
		_off.append(Vector3(randf_range(-0.28, 0.28), randf_range(-0.3, 0.45), randf_range(-0.2, 0.2)))
		_len.append(randf_range(2.1, 2.7))
		_age.append(0.0)
		_sp.append(Vfx.persistent_sprite(Color.WHITE.lerp(col, 0.45), 2))
	while _sp.size() > k:
		var s: MeshInstance3D = _sp.pop_back()
		if is_instance_valid(s):
			s.queue_free()
		_dir.pop_back()
		_off.pop_back()
		_len.pop_back()
		_age.pop_back()
	n = k

func _process(dt: float) -> void:
	_t += dt
	if _bursting:
		return
	life -= dt
	var gone := not is_instance_valid(who) or life <= 0.0
	if not gone and who is EnemyDummy:
		gone = not (who as EnemyDummy).alive
	elif not gone and who.has_method("is_alive") and not bool(who.call("is_alive")):
		gone = true
	if gone:
		drop()
		return
	var c := center()
	global_position = c
	var fade := clampf(life / 1.0, 0.0, 1.0)
	for i in _sp.size():
		var s: MeshInstance3D = _sp[i]
		if not is_instance_valid(s):
			continue
		_age[i] = float(_age[i]) + dt
		# 刚划上去的那一下又长又亮，随后收成一道细痕挂着，微微明灭
		var pop := clampf(1.0 - float(_age[i]) / 0.16, 0.0, 1.0)
		var l := float(_len[i]) * (1.0 + 0.9 * pop)
		var w := 0.1 + 0.14 * pop + 0.015 * sin(_t * 9.0 + float(i) * 1.7)
		Vfx.place_streak(s, c + (_off[i] as Vector3), _dir[i], l, w)
		(s.material_override as ShaderMaterial).set_shader_parameter("alpha", (0.82 + 0.18 * sin(_t * 13.0 + float(i))) * fade)

## 一道一道炸亮（gap 秒一道），炸完自己收掉
func burst(gap: float) -> void:
	if _bursting:
		return
	_bursting = true
	var k := _sp.size()
	var tw := create_tween()
	for i in k:
		tw.tween_callback(_flash.bind(i))
		tw.tween_interval(gap)
	tw.tween_callback(drop)

func _flash(i: int) -> void:
	if i >= _sp.size():
		return
	var c := center() + (_off[i] as Vector3)
	var d: Vector3 = _dir[i]
	var l := float(_len[i])
	Vfx._stroke(c - d * l * 1.3, c + d * l * 1.3, Color.WHITE, 0.22, 0.03, 0.14)
	Vfx._stroke(c - d * l * 1.05, c + d * l * 1.05, Color.WHITE.lerp(col, 0.6), 0.5, 0.02, 0.18)
	Vfx.glint(c, Color.WHITE.lerp(col, 0.3), 0.7)
	var s: MeshInstance3D = _sp[i]
	if is_instance_valid(s):
		s.visible = false

func drop() -> void:
	for s: Variant in _sp:
		if is_instance_valid(s):
			(s as Node).queue_free()
	_sp.clear()
	n = 0
	queue_free()
