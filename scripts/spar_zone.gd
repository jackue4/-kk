extends Node3D
## 斗法台：大厅里专门练空战的一块场地（出生点西南约一百米，位置 / 半径在 test_hall.gd 的 SPAR_POS / SPAR_R），
## 大厅里只有这儿有对手 —— 一位 AI 陪练（air_foe.gd，高速格斗那套 AI，规则见 air_moves.gd），三档水平可选。
## · 场地：青色网格圆台 + 两圈界线 + 外圈八根石柱（有碰撞：把人打飞撞上去会砸出裂痕）+ 台子上空一行大字；
##   出生点那边地上有一行指路的字和一串地标。
## · 陪练悬在台心上空。主角腾空（结丹起；按「攻」会自动腾空）靠近到三十米内就开打，飞远了它自己回去。
## · 三档：入门 / 进阶 / 高手（TIERS）。台子朝出生点的那一侧立着三块择阶碑，人走到哪块跟前（STELE_R 内、贴近地面）就换成哪一档；
##   打赢了自动升一档。换档时陪练回满、回到台心。
## · 主角陨落后被送回出生点（main.gd），陪练收手回满（air_foe.gd 的 stand_down）。
## 故意不写 class_name：用 preload 引用。

const AirFoe := preload("res://scripts/air_foe.gd")
const Sfx := preload("res://scripts/sfx.gd")
const CombatWord := preload("res://scripts/combat_word.gd")

const CENTER := TestHall.SPAR_POS
const R := TestHall.SPAR_R
const HOVER := 9.0            # 陪练悬停的高度
const STELE_R := 4.0          # 离择阶碑这么近算选中
const QI := Color(0.3, 0.95, 0.85)

## name 名字 | tag 档位 | skill 水平（见 air_foe.gd）| pro 会不会飞剑连发 / 对波（三档都会：对波的力道看 skill，
## 同境界下大致每秒点 3 / 5 / 8 下能顶赢）| col 气劲和名牌的颜色
## hpk 气血 = hpk × 主角当前境界的伤害基数（境界表的 dmg）—— 主角境界再高，陪练也一样耐打：
##   结丹打一整套（五连 + 三轮追击）约是基数的 17 倍，所以 入门 ≈ 3 套、进阶 ≈ 6 套、高手 ≈ 13 套（还没算它护体、挣脱、减伤）
## tough 耐打程度（见 air_foe.gd 的 set_tough）：guard 护体值上限 | bursts 罡气格数 | burst_cd 多久回一格 | armor 减伤 |
##   regen 五秒没挨打后每秒回的气血比例 | dmg 它出手的伤害倍率
const TIERS := [
	{"name": "陪练·青芽", "tag": "入门", "skill": 0.3, "hpk": 50.0, "pro": true, "col": Color(0.6, 0.95, 0.7), "tough": {}},
	{"name": "陪练·青禾", "tag": "进阶", "skill": 0.6, "hpk": 105.0, "pro": true, "col": Color(0.3, 0.95, 0.85),
		"tough": {"guard": 7.0, "armor": 0.08, "regen": 0.006, "dmg": 1.1}},
	{"name": "陪练·青锋", "tag": "高手", "skill": 0.92, "hpk": 220.0, "pro": true, "col": Color(1.0, 0.82, 0.4),
		"tough": {"guard": 9.0, "bursts": 3.0, "burst_cd": 9.0, "armor": 0.18, "regen": 0.012, "dmg": 1.3}},
]

var player: Player
var font: Font
var partner: AirFoe
var tier := 0
var wins := 0                 # 打赢陪练的次数

var _steles: Array[Vector3] = []
var _caps: Array[MeshInstance3D] = []
var _switch_cd := 0.0
var _hp_base := -1.0          # 上次按哪个伤害基数定的气血（主角换境界了就重定）


func _ready() -> void:
	_build()
	_spawn_partner()


static func title_of(t: Dictionary) -> String:
	return "%s〔%s〕" % [t["name"], t["tag"]]


## 出生点 → 斗法台的水平方向
static func way() -> Vector3:
	return Vector3(CENTER.x, 0.0, CENTER.z).normalized()


## 台子朝出生点那一侧、界线外 back 米的地面（走过来 / 自检落脚用）
static func entrance(back := 8.0) -> Vector3:
	return CENTER - way() * (R + back)


func stele_pos(i: int) -> Vector3:
	return _steles[i]


func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.45)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := _mesh(bm, mat, pos)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _text(s: String, pos: Vector3, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = font
	l.font_size = 96
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 14
	l.outline_modulate = Color(0.04, 0.09, 0.1)
	l.position = pos
	add_child(l)
	return l


func _build() -> void:
	var c := CENTER
	var d := way()
	var glow := _glow(QI, 1.3)
	var block := TestHall._grid_mat(Color(0.7, 0.71, 0.73), Color(0.42, 0.44, 0.48), 0.55)
	# 圆台 + 界线
	var disc := CylinderMesh.new()
	disc.top_radius = R
	disc.bottom_radius = R
	disc.height = 0.04
	disc.radial_segments = 96
	_mesh(disc, TestHall._grid_mat(Color(0.2, 0.26, 0.27), Color(0.35, 0.72, 0.7), 0.6), c + Vector3(0.0, 0.02, 0.0))
	for rr: Vector2 in [Vector2(R - 0.6, R), Vector2(12.0, 12.4)]:
		var tm := TorusMesh.new()
		tm.inner_radius = rr.x
		tm.outer_radius = rr.y
		tm.rings = 96
		tm.ring_segments = 6
		var ring := _mesh(tm, glow, c + Vector3(0.0, 0.05, 0.0))
		ring.scale = Vector3(1.0, 0.2, 1.0)
	# 外圈石柱（有碰撞）+ 柱顶青灯
	var a0 := atan2(-d.z, -d.x) + PI / 8.0     # 朝出生点的那个方向正好落在两根柱子中间（入口不被柱子挡住）
	for i in 8:
		var a := TAU * float(i) / 8.0 + a0
		var h := 14.0 + 8.0 * absf(sin(float(i) * 1.9))
		var p := c + Vector3(cos(a), 0.0, sin(a)) * (R + 3.0)
		_box(p + Vector3(0.0, h * 0.5, 0.0), Vector3(3.0, h, 3.0), block, true)
		_box(p + Vector3(0.0, h + 0.9, 0.0), Vector3(1.7, 1.8, 1.7), glow, false)
	# 台子上空的大字（从出生点就看得见）和地上的说明（字头朝台心，走过来时正着读）
	var big := _text("斗 法 台", c + Vector3(0.0, 48.0, 0.0), 0.08, Color.WHITE.lerp(QI, 0.55))
	big.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var yaw := atan2(-d.x, -d.z)
	var tip := _text("腾空靠近陪练即开战（结丹起）\n走到石碑前换档 · 打赢自动升一档", entrance(4.0) + Vector3(0.0, 0.05, 0.0), 0.008,
			Color.WHITE.lerp(QI, 0.5))
	tip.rotation = Vector3(-PI * 0.5, yaw, 0.0)
	# 择阶碑：朝出生点那一侧一字排开，碑顶的灯亮着的是当前这一档
	var side := d.cross(Vector3.UP).normalized()
	for i in TIERS.size():
		var t: Dictionary = TIERS[i]
		var p := entrance(12.0) + side * (float(i) - 1.0) * 9.0
		_steles.append(p)
		var stone := _box(p + Vector3(0.0, 1.3, 0.0), Vector3(1.8, 2.6, 0.7), block, true)
		stone.rotation.y = yaw
		_caps.append(_box(p + Vector3(0.0, 2.9, 0.0), Vector3(1.2, 0.5, 0.9), glow, false))
		var lab := _text(str(t["tag"]), p + Vector3(0.0, 4.3, 0.0), 0.016, Color.WHITE.lerp(t["col"] as Color, 0.6))
		lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_light_caps()
	# 指路：出生点旁一行地面字（面朝台子走过来时正着读，箭头朝前）+ 一串地标
	var guide := _text("↑ 斗法台 · AI 陪练 ↑", d * 30.0 + Vector3(0.0, 0.05, 0.0), 0.012, Color(0.15, 0.36, 0.36))
	guide.outline_size = 0
	guide.rotation = Vector3(-PI * 0.5, yaw, 0.0)
	var dash := BoxMesh.new()
	dash.size = Vector3(3.0, 0.04, 0.7)
	var t0 := 41.0
	while t0 < c.length() - R - 14.0:
		var mark := _mesh(dash, glow, d * t0 + Vector3(0.0, 0.03, 0.0))
		mark.rotation.y = atan2(-d.z, d.x)
		t0 += 4.0


func _light_caps() -> void:
	for k in _caps.size():
		var col: Color = (TIERS[k] as Dictionary)["col"]
		_caps[k].material_override = _glow(col, 2.2) if k == tier else _glow(Color(0.35, 0.4, 0.42), 0.15)


func _spawn_partner() -> void:
	var t: Dictionary = TIERS[tier]
	partner = AirFoe.new()
	partner.player = player
	partner.display_name = title_of(t)
	partner.ai_enabled = true
	partner.style = 2
	partner.skill = float(t["skill"])
	partner.pro = bool(t["pro"])
	partner.qi = t["col"] as Color
	partner.hp_max = hp_of(t)
	partner.set_tough(t["tough"] as Dictionary)
	partner.position = CENTER + Vector3(0.0, HOVER, 0.0)
	partner.died.connect(_on_died)
	add_child(partner)


## 这一档的气血：hpk × 主角当前境界的伤害基数
func hp_of(t: Dictionary) -> float:
	_hp_base = float(player.realm["dmg"]) if player != null else 18.0
	return float(t["hpk"]) * _hp_base


## 换档：陪练换名字 / 水平 / 气血，回满、回到台心
func set_tier(i: int, announce := true) -> void:
	tier = clampi(i, 0, TIERS.size() - 1)
	_switch_cd = 1.0
	var t: Dictionary = TIERS[tier]
	partner.retune(title_of(t), float(t["skill"]), hp_of(t), bool(t["pro"]), t["col"] as Color, t["tough"] as Dictionary)
	_light_caps()
	if announce:
		Sfx.play("perfect", -6.0, 1.0 + 0.15 * float(tier))
		CombatWord.pop(str(t["tag"]), _steles[tier] + Vector3.UP * 5.6, t["col"] as Color, 1.2)


## 打赢了：升一档（它重新凝聚出来时就是下一档；已经是最高档就还是最高档）
func _on_died(_f: Node3D) -> void:
	wins += 1
	if tier < TIERS.size() - 1:
		set_tier(tier + 1, false)


func _process(dt: float) -> void:
	_switch_cd -= dt
	if player == null or partner == null:
		return
	# 主角换了境界：陪练的气血按新的伤害基数重定（保持现在的血量比例）
	if absf(float(player.realm["dmg"]) - _hp_base) > 0.01:
		partner.rescale_hp(hp_of(TIERS[tier] as Dictionary))
	if _switch_cd > 0.0 or player.dead:
		return
	var p := player.global_position
	if p.y > 5.0:
		return      # 在天上飞过不算：得落到碑前
	for i in _steles.size():
		if i != tier and Vector2(p.x - _steles[i].x, p.z - _steles[i].z).length() < STELE_R:
			set_tier(i)
			break
