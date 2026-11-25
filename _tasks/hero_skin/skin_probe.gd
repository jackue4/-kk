extends SceneTree
## 皮肤模型导进来之后长什么样：节点树、骨骼在角色空间里的位置（核对朝向 / 左右 / 各段长度）。
## 用法：Godot --headless --path . -s res://_tasks/hero_skin/skin_probe.gd [-- 模型路径]


func _init() -> void:
	var path := "res://assets/hero/aladeng.glb"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	var ps := load(path) as PackedScene
	var root := ps.instantiate() as Node3D
	get_root().add_child(root)
	_tree(root, 0)
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var xf := Transform3D.IDENTITY
	var n: Node3D = sk
	while n != null and n != root.get_parent():
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	print("skeleton → root: ", xf)
	for b in sk.get_bone_count():
		var g := xf * sk.get_bone_global_rest(b)
		var par := sk.get_bone_parent(b)
		print("%2d %-20s parent=%-18s pos=(%.3f, %.3f, %.3f)  x=%s y=%s z=%s" % [b, sk.get_bone_name(b),
				sk.get_bone_name(par) if par >= 0 else "-", g.origin.x, g.origin.y, g.origin.z,
				_v(g.basis.x.normalized()), _v(g.basis.y.normalized()), _v(g.basis.z.normalized())])
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var bb := mi.get_aabb()
		print("mesh ", mi.name, " parent=", mi.get_parent().name, " xform=", mi.transform, " aabb=", bb, " surfaces=", mi.mesh.get_surface_count(),
				" skin=", mi.skin != null, " skeleton=", mi.skeleton)
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			print("    surf ", s, " mat=", m, " ", m.resource_name if m != null else "", " fmt=", (mi.mesh as ArrayMesh).surface_get_format(s))
	quit()


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _tree(n: Node, d: int) -> void:
	var extra := ""
	if n is Node3D:
		var t := (n as Node3D).transform
		extra = " pos=%s scale=%s" % [t.origin, t.basis.get_scale()]
	print("  ".repeat(d), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_tree(c, d + 1)
