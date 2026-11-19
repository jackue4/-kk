import os, re, shutil, sys
SRC = sys.argv[1]; SH = sys.argv[2]; DST = sys.argv[3]
os.makedirs(DST + "/materials", exist_ok=True)
os.makedirs(DST + "/shaders", exist_ok=True)
os.makedirs(DST + "/mesh", exist_ok=True)
def fix(t):
    t = t.replace("res://effects/fireball/fireball_core/", "res://fx/fireball/")
    t = t.replace("res://effects/fireball/fireball_impact/", "res://fx/fireball/")
    t = t.replace("res://effects/fireball/fireball_spawn/", "res://fx/fireball/")
    t = t.replace("res://effects/fireball/", "res://fx/fireball/")
    t = t.replace("res://shared/shaders/", "res://fx/fireball/shaders/")
    # 源工程的 uid 在本项目里无效：去掉，只按路径引用
    t = re.sub(r' uid="uid://[a-z0-9]+"', "", t)
    return t
copies = {
 "materials/fireball_core.gdshader": "materials/fireball_core.gdshader",
 "materials/fireball_shell.gdshader": "materials/fireball_shell.gdshader",
 "materials/fireball_particles.gdshader": "materials/fireball_particles.gdshader",
 "materials/fireball_impact_flash.gdshader": "materials/fireball_impact_flash.gdshader",
 "materials/fireball_impact_trail.gdshader": "materials/fireball_impact_trail.gdshader",
 "materials/fire_particles_gradient.tres": "materials/fire_particles_gradient.tres",
 "materials/fireball_mat.tres": "materials/fireball_mat.tres",
 "materials/fireball_fire_particles_mat.tres": "materials/fireball_fire_particles_mat.tres",
 "materials/fireball_firetrail_particles_process.tres": "materials/fireball_firetrail_particles_process.tres",
 "fireball_core/fireball.tscn": "fireball.tscn",
 "fireball_core/fireball.gd": "fireball.gd",
 "fireball_impact/fireball_impact.tscn": "fireball_impact.tscn",
 "fireball_impact/fireball_impact.gd": "fireball_impact.gd",
 "fireball_spawn/fireball_spawn.tscn": "fireball_spawn.tscn",
 "fireball_spawn/fireball_spawn.gd": "fireball_spawn.gd",
}
for s, d in copies.items():
    t = open(os.path.join(SRC, s), encoding="utf-8").read()
    open(os.path.join(DST, d), "w", encoding="utf-8", newline="\n").write(fix(t))
for f in ["fresnel.gdshaderinc", "rotate_x.gdshaderinc", "rotate_z.gdshaderinc"]:
    shutil.copy(os.path.join(SH, f), os.path.join(DST, "shaders", f))
# OBJ -> GDScript 网格数据（运行时用 SurfaceTool 拼，不依赖编辑器导入）
V=[];VT=[];VN=[];F=[]
for line in open(os.path.join(SRC, "mesh/fireball_shell_mesh.obj")):
    p=line.split()
    if not p: continue
    if p[0]=="v": V.append(tuple(map(float,p[1:4])))
    elif p[0]=="vt": VT.append(tuple(map(float,p[1:3])))
    elif p[0]=="vn": VN.append(tuple(map(float,p[1:4])))
    elif p[0]=="f": F.append([tuple(int(x) if x else 0 for x in c.split("/")) for c in p[1:]])
pos=[];uv=[];nrm=[]
for f in F:
    for i in range(1,len(f)-1):
        # 与 Godot OBJ 导入器一致：反转绕序（OBJ 逆时针为正面）、v 坐标翻转
        for c in (f[0], f[i+1], f[i]):
            pos.append(V[c[0]-1]); t=VT[c[1]-1]; uv.append((t[0],1.0-t[1])); nrm.append(VN[c[2]-1])
fmt=lambda a: ", ".join("%g" % x for t in a for x in t)
gd = '''extends RefCounted
## fireball_shell_mesh.obj（VFX-sketchbook effects/fireball/mesh）转成的数据：运行时用 SurfaceTool 拼出 ArrayMesh，
## 免得依赖编辑器导入 .obj。三角形已按 Godot OBJ 导入器的规则展开（绕序反转、UV 的 v 翻转）。
## 由 _tasks 里的转换脚本生成，别手改。

const POS := PackedFloat32Array([%s])
const UV := PackedFloat32Array([%s])
const NRM := PackedFloat32Array([%s])

static var _mesh: ArrayMesh


static func mesh() -> ArrayMesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in POS.size() / 3:
			st.set_normal(Vector3(NRM[i * 3], NRM[i * 3 + 1], NRM[i * 3 + 2]))
			st.set_uv(Vector2(UV[i * 2], UV[i * 2 + 1]))
			st.add_vertex(Vector3(POS[i * 3], POS[i * 3 + 1], POS[i * 3 + 2]))
		st.index()
		_mesh = st.commit()
	return _mesh
''' % (fmt(pos), fmt(uv), fmt(nrm))
open(os.path.join(DST, "mesh/fireball_shell_mesh.gd"), "w", encoding="utf-8", newline="\n").write(gd)
print(len(F), "faces ->", len(pos)//3, "tris")
