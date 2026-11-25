extends Node3D
## 主城大厅（2026-11-20，用户给了一张方块风浮岛主城的参考图，要求照着做）：所有玩家开游戏先到这里。
## 一座浮在云海上的岛，布局照参考图：
##   正中 中心广场：八角铺地，中间是地标——灵泉台上悬着一枚缓缓转动的紫晶，绕着符环和小晶片
##   北面 关卡入口：三米高的石台上一道带瓦顶的石墙，墙上四道拱门——木兰草原（现有的关卡）、试剑台（原来的灰色测试大厅）、
##        两道还没开的（灰着，走过去提示尚未开启）；台前两段石阶
##   西面 商店：一座木楼加两个带布棚的摊位（走近点「坊市」开洞府的坊市页）
##   东面 仓库：敞口的库房、成垛的木箱、板车、告示牌（走近点「仓库」开洞府的储物页，就是玩家现在的仓库）
##   东南 修炼场：竹篱围着的草地、牌坊、石阵台和四块符石、木人桩、竹丛——站到阵台上点「闭关打坐」，
##        盘腿坐下，每秒修为 +1（存进 raid_profile.gd 的修为，和服丹、大世界打怪是同一条经验；到大境界瓶颈就停）
##        2026-11-20 数值框架：打坐速度按境界（Prog.meditate_tick，顺带消丹毒）；开机 / 手机切回前台结算离线闭关（Prog.settle_offline）；
##        修为到瓶颈、仓库 / 随身 / 储物戒里有通往下一境界的破境丹、灵石够 Prog.break_cost 时，阵台上的按钮变成「渡劫突破」：
##        起劫扣灵石（失败不退），渡过了才服下破境丹、升境界；缺什么站上阵台时提示
##   西南 莲池、拱桥、落到岛外的瀑布；正南是进城的石道，玩家出生在这里
##   到处是粉樱、绿树、花圃、石灯、长凳、旗幡；岛外是云团和几座挂着瀑布的小浮岛
## 画风和大世界一样：地面是 2 米一格的方块（顶面 + 侧面，颜色烘在顶点色里），建筑 / 树 / 灯用 block_world.gd 现成的构件拼，
## 材质也是 block_world.gdshader。整座城是两张静态网格（地面一张、建筑点缀一张）+ 地标的几个会动的小件 + 一张站着的路人网格。
## 主角怎么站：和大世界一样不建碰撞体，脚下垫一块跟着走的地板，高度问 ground()；建筑、围墙、石栏是「实心格」，走不进去（飞得比它高可以落在上面）；
##   走出岛外掉进云海 → 送回入口。
## 和 main.gd 的关系：主城和原来的测试大厅（test_hall.gd）不会同时开着——set_active() 开关自己，main.gd 负责关另一边。
##   拱门触发发 gate_entered(i)，由 main.gd 决定去哪。
## 自检：`-- --hub-shot [--touch]`（见 selftest）。
## 2026-11-21 场景美术专项：
##   · 天空换成一张全景天空盒（shaders/pano_sky.gdshader + assets/sky/hub_pano.jpg，粉紫云海落日，_tasks/scene_art/make_sky.py 做的无缝 / 两极处理），农场共用
##   · 东边（仓库和修炼场之间）一道牌坊门通「灵田农场」（hub_farm.gd）：从中心广场往东一条石路过去，门洞里是农场的实时画面（hub_portal.gd），
##     走进门洞就到了农场南门里头；农场南门再走出来回到这道门前。主城 / 农场是同一个「主城」（active 不变），area 说明人在哪边，
##     ground / _solid_at / spawn_point 按 area 问对应的那张表。自检 `-- --hub-shot --farm-shot [--touch]`（farm_selftest）。
## 故意不写 class_name：用 preload 引用。

signal gate_entered(i: int)

const BlockWorld := preload("res://scripts/block_world.gd")
const Data := preload("res://scripts/raid_data.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Prog := preload("res://scripts/progression.gd")
const Items := preload("res://scripts/raid_items.gd")
const Tribulation := preload("res://scripts/tribulation.gd")
const YuanCine := preload("res://scripts/yuanying_cine.gd")
const Abode := preload("res://scripts/abode_ui.gd")
const UiStyle := preload("res://scripts/ink_style.gd")      # 2026-11-24 界面重做：换成墨玉样式（接口同 ui_style.gd，见那个文件头）
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Sfx := preload("res://scripts/sfx.gd")
const WORLD_SHADER := preload("res://shaders/block_world.gdshader")
const GATE_SHADER := preload("res://shaders/hub_gate.gdshader")
const NOISE := preload("res://fx/cine/cine_noise.png")
const Farm := preload("res://scripts/hub_farm.gd")
const Portal := preload("res://scripts/hub_portal.gd")
const PANO_SHADER := preload("res://shaders/pano_sky.gdshader")
const PANO_PATH := "res://assets/sky/hub_pano.jpg"
const Arena := preload("res://scripts/hub_arena.gd")      # 2026-11-23 两侧的擂台
const Look := preload("res://scripts/look.gd")            # 2026-11-23 画面专项：调色表 / 花瓣
const ArenaDuel := preload("res://scripts/arena_duel.gd")   # 2026-11-23 擂台对决：站上擂台匹配 1v1（真人 / AI 陪练）
const LanPresence := preload("res://scripts/lan_presence.gd")   # 2026-11-23 局域网在场：主城里看得见局域网里的其他玩家
const NumFmt := preload("res://scripts/num_fmt.gd")       # 2026-11-23 数值重构：修为 / 打坐每息上了万、亿，统一短写
const CS := preload("res://scripts/combat_stats.gd")      # 2026-11-23 渡劫成功后飘「战力 A → B」

const CELL := 2.0
const N := 180                 # 一边多少格（360 米见方；2026-11-23 两侧加了擂台，原来 92 格；同日擂台放大到 80 米，152 → 180）
const HN := 90
const VOID := -999.0
const STEP_UP := 1.1           # 这么高以内直接迈上去（石阶半米一级）
const T_GRASS := 1
const T_PAVE := 2
const T_PLAZA := 3
const T_WATER := 4
const T_STONE := 5             # 石台 / 阵台
const T_BED := 6               # 花圃的土

## 四道拱门（x 是门心的位置，都在北面石墙上）。open = false 的是还没开的关卡
const GATES := [
	{"x": -25.5, "name": "木兰草原", "sub": "旧版大世界", "a": Color(0.30, 0.85, 0.45), "b": Color(0.90, 1.0, 0.75), "frame": Color(0.32, 0.55, 0.26), "open": true, "level": "mulan"},
	{"x": -8.5, "name": "试剑台", "sub": "测试关", "a": Color(0.35, 0.70, 1.0), "b": Color(0.88, 0.97, 1.0), "frame": Color(0.62, 0.82, 0.96), "open": true, "level": ""},
	# 2026-11-24 搜打撤 PvP 重构：门 2 / 3 开成两张新图（对标 DarkArea 的沙漠行动 / 研究所，scripts/ex/）
	{"x": 8.5, "name": "沙海古墟", "sub": "搜 · 打 · 撤", "a": Color(1.0, 0.45, 0.18), "b": Color(1.0, 0.9, 0.6), "frame": Color(0.36, 0.22, 0.2), "open": true, "level": "desert"},
	{"x": 25.5, "name": "天工秘所", "sub": "搜 · 打 · 撤", "a": Color(0.68, 0.45, 1.0), "b": Color(0.95, 0.88, 1.0), "frame": Color(0.5, 0.4, 0.66), "open": true, "level": "lab"},
]
const TERRACE_H := 3.0
const WALL_Z := -58.0          # 石墙中线
const WALL_H := 15.0           # 石墙高（从石台面算）
const GATE_W := 10.0           # 门洞宽 / 高
const GATE_H := 12.5
const SPAWN := Vector3(0.0, 0.0, 78.0)
const SHOP_POS := Vector3(-41.0, 0.0, -14.0)      # 商店门口：站到这附近出「商店」
const STORE_POS := Vector3(41.0, 0.0, -14.0)      # 仓库门口：「仓库」
const MED_POS := Vector3(46.0, 0.5, 42.0)         # 修炼场的阵台
const USE_R := 7.5
const MED_R := 4.6
const SAVE_EVERY := 10.0       # 打坐时每隔这么久存一次档
## 通灵田农场的牌坊门（2026-11-21）：门洞底边中点；门朝西（对着中心广场），往东走进门
const FARM_GATE := Vector3(58.0, 0.0, 16.0)
const SKY_YAW := 2.37          # 全景天空盒的落日朝哪（0 = 正北，往东为正）：东南，和主城日光（block_world.make_sun）照过来的方向一致，影子对得上

var player: Player
var cam: CameraRig
var font: Font
var mobile := false
var main: Node = null          # main.gd（开洞府界面要用它的 hud / level_ui）
var active := false

var _h := PackedFloat32Array()
var _t := PackedByteArray()
var _solid := PackedFloat32Array()      # 实心格的顶面高度（0 = 不是）
var _bw: BlockWorld                     # 只借它的构件函数和配色，不进场景树
var _a: Array = []                      # 建筑点缀：[顶点, 法线, 顶点色, 索引]
var _g: Array = []                      # 地面
var _root: Node3D                       # 所有看得见的东西（开关时整体显隐）
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _floor: StaticBody3D
var _last_xz := Vector2.ZERO
var _crystal: Node3D
var _shards: Array[Node3D] = []
var _rings: Array[Node3D] = []
var _time := 0.0
var _gate_armed := true
var _toast_cd := 0.0
# 界面
var _ui: CanvasLayer
var _use_btn: Button
var _use_what := ""
var _panel: PanelContainer              # 打坐时顶上的牌子
var _panel_lab: Label
var _toast: Label
# 打坐
var meditating := false
var med_gain := 0.0                     # 这次打坐一共涨了多少（2026-11-20 数值框架：每息不是整数了）
var _med_t := 0.0
var _med_acc := 0.0
var _med_save := 0.0
var _med_sec := 0.0                     # 这一秒里涨了多少（每满一秒飘一次）
var _hero_y := 0.0
# 2026-11-20 数值框架：离线闭关、修炼场渡劫
var _boot_settled := false              # 开机后第一次进主城时结算过离线了
var _paused_at := -1.0                  # 手机切到后台的那一刻（unix 秒）
var _later_txt := ""                    # 等演出 / 开机黑幕过去再飘的一行字
var _later_hold := 1.6
var _later_t := 0.0
var _zone_was := ""
# 2026-11-21 灵田农场
var farm: Farm
var area := "town"                      # town 主城 / farm 农场
var _portal_town: Portal                # 主城这道门（门里是农场）
var _portal_farm: Portal                # 农场南门（门里是主城）
var _prev_p := Vector3.ZERO
var _veil: ColorRect
var _primed := false
var duel: ArenaDuel                      # 擂台对决（arena_duel.gd）
var presence: LanPresence               # 局域网在场（lan_presence.gd）


func _ready() -> void:
	_bw = BlockWorld.new()
	_h.resize(N * N)
	_t.resize(N * N)
	_solid.resize(N * N)
	_h.fill(VOID)
	_a = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	_g = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	_root = Node3D.new()
	add_child(_root)
	_layout()
	_mesh_ground()
	_build_structures()
	_build_scenery()
	_build_signs()
	_commit(_g, true)
	_commit(_a, true)
	_build_landmark()
	_build_gates()
	_build_people()
	_build_env()
	_build_ui()
	_floor = StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(8.0, 2.0, 8.0)
	fcs.shape = fsh
	_floor.add_child(fcs)
	add_child(_floor)
	if not InputMap.has_action("hub_use"):
		InputMap.add_action("hub_use")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event("hub_use", ev)
	# 2026-11-24 搜打撤 PvP 重构：灵田农场不再建（门还在，走过去不传送；farm 恒为 null，各处都有判空）
	# _build_farm()
	# 2026-11-23 擂台对决：站上两侧擂台的台面就开始匹配（arena_duel.gd）
	duel = ArenaDuel.new()
	duel.name = "ArenaDuel"
	duel.hub = self
	duel.main = main
	duel.player = player
	duel.cam = cam
	duel.font = font
	duel.mobile = mobile
	add_child(duel)
	# 2026-11-23 局域网在场：开着游戏就在局域网里互相看得见（主城里显示别人、入境页列出都有谁，lan_presence.gd）
	presence = LanPresence.new()
	presence.name = "LanPresence"
	presence.hub = self
	presence.main = main
	presence.player = player
	add_child(presence)
	set_active(false)


func _exit_tree() -> void:
	if _bw != null:
		_bw.free()
		_bw = null
	if _env != null and _env.get_parent() == null:
		_env.free()
	if _sun != null and _sun.get_parent() == null:
		_sun.free()


# ---------- 开关 ----------

## 开 / 关主城（main.gd 调：开机、从关卡回来 → 开；进关卡、去测试大厅 → 关）
func set_active(on: bool) -> void:
	if not on and meditating:
		stop_meditate()
	if not on and duel != null:
		duel.abort()          # 离开主城：排着的队 / 打着的对决立刻收掉
	active = on
	area = "town"                 # 开 / 关主城都回到主城这边（进关卡、从关卡回来都是在主城）
	_root.visible = on
	_apply_area()
	_ui.visible = on
	set_process(on)
	set_physics_process(on)
	_floor.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	(_floor.get_child(0) as CollisionShape3D).disabled = not on
	# 天空和日光：同一时刻场景里只能有一套（测试大厅、关卡各有各的）
	if on:
		if _env.get_parent() == null:
			add_child(_env)
		if _sun.get_parent() == null:
			add_child(_sun)
		if cam != null:
			cam.floor_fn = ground
			cam.set("occl_fn", _cam_block_h)     # 2026-11-21 QA BUG-02：镜头遮挡要算上楼 / 墙 / 石栏的实心格
			cam.focus = null
		if player != null:
			player.ground_ref = 0.0
			_last_xz = Vector2(player.global_position.x, player.global_position.z)
		_gate_armed = false       # 刚到（可能就站在门口）：先走开再回来才算进门
		# 2026-11-20 数值框架：开机后第一次进主城，结算上次关游戏以来的离线闭关
		# 2026-11-24 搜打撤 PvP 重构：离线闭关不再结算（吃丹 / 挂机修为整体去掉）
		if not _boot_settled:
			_boot_settled = true
	else:
		if _env.get_parent() == self:
			remove_child(_env)
		if _sun.get_parent() == self:
			remove_child(_sun)
		if cam != null and cam.floor_fn == Callable(self, "ground"):
			cam.floor_fn = Callable()
		if cam != null and cam.get("occl_fn") == Callable(self, "_cam_block_h"):
			cam.set("occl_fn", Callable())


## 擂台对决进行中（入场 / 对决 / 结算）：这时主角陨落归 arena_duel.gd 管（main.gd 的 _on_player_dead 问这个，不再把人送回出生点）
func duel_busy() -> bool:
	return duel != null and duel.busy()


func spawn_point() -> Vector3:
	if area == "farm" and farm != null:
		return farm.spawn_point()
	return SPAWN + Vector3(0.0, 0.1, 0.0)


## 第 i 道门通往哪张图（main._on_hub_gate 用）：mulan 木兰草原（旧版）/ desert 沙海古墟 / lab 天工秘所；试剑台是 ""
func gate_level(i: int) -> String:
	return String(GATES[clampi(i, 0, GATES.size() - 1)].get("level", ""))


## 从第 i 道门里出来（关卡撤离 / 从试剑台回来）站哪：那道门前的石台上，背对着门
func return_point(i: int) -> Vector3:
	return Vector3(float(GATES[clampi(i, 0, GATES.size() - 1)]["x"]), TERRACE_H + 0.1, WALL_Z + 10.0)


# ---------- 布局 ----------

func _ci(x: float) -> int:
	return int(floorf(x / CELL)) + HN


func _in(i: int, j: int) -> bool:
	return i >= 0 and i < N and j >= 0 and j < N


func _put(i: int, j: int, type: int, h: float) -> void:
	if _in(i, j):
		_h[j * N + i] = h
		_t[j * N + i] = type


func _rect(x0: float, z0: float, x1: float, z1: float, type: int, h: float, only_land := true) -> void:
	for j in range(_ci(z0), _ci(z1 - 0.01) + 1):
		for i in range(_ci(x0), _ci(x1 - 0.01) + 1):
			if _in(i, j) and (not only_land or _h[j * N + i] > VOID + 1.0):
				_put(i, j, type, h)


func _disc(cx: float, cz: float, rx: float, rz: float, type: int, h: float) -> void:
	for j in range(_ci(cz - rz), _ci(cz + rz) + 1):
		for i in range(_ci(cx - rx), _ci(cx + rx) + 1):
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			var dx := (x - cx) / rx
			var dz := (z - cz) / rz
			if dx * dx + dz * dz <= 1.0 and _in(i, j) and _h[j * N + i] > VOID + 1.0:
				_put(i, j, type, h)


func _block(x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	for j in range(_ci(z0), _ci(z1 - 0.01) + 1):
		for i in range(_ci(x0), _ci(x1 - 0.01) + 1):
			if _in(i, j):
				_solid[j * N + i] = maxf(_solid[j * N + i], top)


## 比两米一格细的实心盒子（2026-11-23：门柱这种细东西按格子登记，一根 1.8 米的柱子会占掉 4 米见方，
## 八米宽的门洞只剩中间不到四米能走——用户：「两侧的柱子碰撞有问题，老容易挡着玩家」）。按真实大小记，_solid_at 里一并查
var _fine := PackedFloat32Array()       # 每五个数一个盒子：x0, z0, x1, z1, 顶

func _block_fine(x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	_fine.append_array([x0, z0, x1, z1, top])


static func _hash(i: int, j: int) -> float:
	var n := (i * 374761393 + j * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


func _oct(r: float, type: int, h: float) -> void:
	for j in range(_ci(-r), _ci(r) + 1):
		for i in range(_ci(-r), _ci(r) + 1):
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			if maxf(maxf(absf(x), absf(z)), (absf(x) + absf(z)) * 0.7071) <= r and _in(i, j) and _h[j * N + i] > VOID + 1.0:
				_put(i, j, type, h)


func _layout() -> void:
	# 岛：一块圆角的方（超椭圆），边沿按格子参差一点；正南伸出一条进城的石道
	for j in N:
		for i in N:
			var x := (float(i - HN) + 0.5) * CELL
			var z := (float(j - HN) + 0.5) * CELL
			var k := pow(absf(x) / 72.0, 4.0) + pow(absf(z + 4.0) / 68.0, 4.0)
			if k < 0.96 + (_hash(i, j) - 0.5) * 0.06:
				_put(i, j, T_GRASS, 0.0)
	_rect(-7.0, 58.0, 7.0, 86.0, T_PAVE, 0.0, false)
	# 八角广场和几条路；商店、仓库门前各一片铺地
	_oct(30.0, T_PLAZA, 0.0)
	_rect(-5.0, 28.0, 5.0, 62.0, T_PAVE, 0.0)
	_rect(-24.0, -38.0, 24.0, -26.0, T_PAVE, 0.0)
	_rect(-46.0, -22.0, -28.0, 6.0, T_PAVE, 0.0)
	_rect(28.0, -22.0, 46.0, 6.0, T_PAVE, 0.0)
	_rect(18.0, 18.0, 30.0, 30.0, T_PAVE, 0.0)
	_rect(-30.0, 20.0, -20.0, 30.0, T_PAVE, 0.0)
	# 北面的石台（关卡入口）和两段石阶：半米一级、一级两米深
	_rect(-56.0, -68.0, 56.0, -38.0, T_STONE, TERRACE_H)
	for k in 5:
		var z0 := -38.0 + 2.0 * float(k)
		for sx: float in [-1.0, 1.0]:
			_rect(sx * 15.0 - 5.0, z0, sx * 15.0 + 5.0, z0 + 2.0, T_STONE, TERRACE_H - 0.5 * float(k + 1))
	# 莲池和流到岛边的小溪
	_disc(-40.0, 44.0, 15.0, 10.0, T_WATER, -0.6)
	_rect(-58.0, 48.0, -50.0, 70.0, T_WATER, -0.6)
	# 修炼场：阵台
	_disc(MED_POS.x, MED_POS.z, 5.4, 5.4, T_STONE, 0.5)
	# 花圃：广场四角外各一块
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_rect(sx * 27.0 - 3.0, sz * 27.0 - 3.0, sx * 27.0 + 3.0, sz * 27.0 + 3.0, T_BED, 0.4)
	# 实心格：石墙、两座楼、灵泉台
	_block(-44.0, WALL_Z - 2.0, 44.0, WALL_Z + 2.0, TERRACE_H + WALL_H + 4.0)
	_block(-58.9, -23.9, -45.1, -4.1, 10.0)       # 商店主楼
	_block(45.6, -24.9, 60.4, -3.1, 9.0)          # 仓库
	_block(-9.4, -9.4, 9.4, 9.4, 1.0)             # 灵泉台
	# 2026-11-21 通灵田农场的牌坊门：从广场东沿往东一条石路、门前门后一片石铺地；两根门柱、两面幡是实心
	_rect(28.0, 13.0, 56.0, 19.0, T_PAVE, 0.0)
	_rect(52.0, 8.0, 62.0, 24.0, T_PAVE, 0.0)
	for sz: float in [-1.0, 1.0]:
		# 2026-11-23：门柱按石墩的真实大小（1.8 米见方）挡人；红幡挂在三米以上、人从底下过，不登记
		var gz := FARM_GATE.z + sz * (Farm.GATE_W * 0.5 + 0.5)
		_block_fine(FARM_GATE.x - 0.9, gz - 0.9, FARM_GATE.x + 0.9, gz + 0.9, Farm.GATE_H + 6.0)
	# 2026-11-23 两侧的擂台：主岛往东、西各伸出一块，上面一座八角石台（hub_arena.gd）
	Arena.layout(self)


# ---------- 地面网格 ----------

func _quad(a: Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, em := 0.0, top := true) -> void:
	var v: PackedVector3Array = a[0]
	var nr: PackedVector3Array = a[1]
	var cl: PackedColorArray = a[2]
	var ix: PackedInt32Array = a[3]
	var b := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	var cc := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), em)
	for _k in 4:
		nr.append(n)
		cl.append(cc)
	if top:
		ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		ix.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	a[0] = v
	a[1] = nr
	a[2] = cl
	a[3] = ix


## 2026-11-23 画面专项：地面的烘焙暗角（方块世界那种「墙根 / 夹角发暗」）。一格顶面的四个角各看挨着它的三格（两个邻边 + 一个对角）
## 有几格比自己高（石台、台阶、楼 / 墙的实心格）：0 / 1 / 2 / 3 格 → 亮度 1 / 0.84 / 0.72 / 0.62。烘在顶点色里，不花运行时的钱
func _ao(i: int, j: int, dx: int, dz: int, h: float) -> float:
	var n := 0
	for o: Array in [[dx, 0], [0, dz], [dx, dz]]:
		var ni: int = i + int(o[0])
		var nj: int = j + int(o[1])
		if _in(ni, nj) and _h[nj * N + ni] > VOID + 1.0 and maxf(_h[nj * N + ni], _solid[nj * N + ni]) > h + 0.4:
			n += 1
	return [1.0, 0.84, 0.72, 0.62][n]


## 顶面的方片，四个角各乘一个暗角系数；对角线挑暗角更对称的那条切（不然明暗沿对角线折一道）
func _quad_ao(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color, em: float, ao: Array) -> void:
	var v: PackedVector3Array = _g[0]
	var nr: PackedVector3Array = _g[1]
	var cl: PackedColorArray = _g[2]
	var ix: PackedInt32Array = _g[3]
	var b := v.size()
	v.append_array(PackedVector3Array([p0, p1, p2, p3]))
	for k in 4:
		var a := float(ao[k])
		nr.append(Vector3.UP)
		# 暗角往冷紫偏一点（红绿压得比蓝多），不是纯压黑
		cl.append(Color(minf(c.r * a, 1.0), minf(c.g * lerpf(a, 1.0, 0.06), 1.0), minf(c.b * lerpf(a, 1.0, 0.22), 1.0), em))
	if absf(float(ao[0]) - float(ao[2])) <= absf(float(ao[1]) - float(ao[3])):
		ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		ix.append_array([b, b + 1, b + 3, b + 1, b + 2, b + 3])
	_g[0] = v
	_g[1] = nr
	_g[2] = cl
	_g[3] = ix


func _top_col(type: int, i: int, j: int, x: float, z: float) -> Color:
	var hs := _hash(i * 3 + 1, j * 5 + 2)
	if type >= Arena.T_ARENA:
		return Arena.top_col(type, i, j, x, z, hs)
	match type:
		T_GRASS:
			# 2026-11-23 画面专项：草略深、略偏冷一点（原来在暖日光下发荧光黄绿）；铺地 / 石台从近白的灰换成暖色的石（奶杏 / 浅赭）
			var c := Color(0.36, 0.63, 0.29).lerp(Color(0.49, 0.73, 0.33), hs)
			return c if hs > 0.12 else Color(0.31, 0.56, 0.27)
		T_PAVE:
			return (Color(0.85, 0.78, 0.68) if (i + j) % 2 == 0 else Color(0.78, 0.71, 0.64)) * (0.96 + 0.08 * hs)
		T_PLAZA:
			# 八角广场的铺地：一圈圈石带（隔一圈换一种石色、圈缝一道深线），八个方向各一道放射的青石条，最外一圈镶边
			var d := maxf(maxf(absf(x), absf(z)), (absf(x) + absf(z)) * 0.7071)
			var ring := int(d / 6.0)
			var c2 := Color(0.90, 0.82, 0.71) if ring % 2 == 0 else Color(0.82, 0.75, 0.69)
			var off := absf(fposmod(atan2(z, x) + PI / 8.0, PI / 4.0) - PI / 8.0) * sqrt(x * x + z * z)
			if d > 11.0 and off < 1.3:
				c2 = Color(0.60, 0.65, 0.80)
			elif (d > 11.0 and fmod(d, 6.0) < 2.0) or d > 28.0:
				c2 = Color(0.66, 0.59, 0.68)
			return c2 * (0.96 + 0.08 * hs)
		T_WATER:
			return Color(0.36, 0.80, 0.86).lerp(Color(0.30, 0.70, 0.84), hs)
		T_STONE:
			return (Color(0.81, 0.74, 0.69) if (i + j) % 2 == 0 else Color(0.74, 0.68, 0.66)) * (0.96 + 0.08 * hs)
		T_BED:
			return Color(0.50, 0.36, 0.24)
	return Color(0.6, 0.6, 0.6)


## 侧壁的颜色（按离顶面多深分层）：草地往下是一道橙土、再往下灰石；石头的格子从上到下都是灰石
func _side_col(type: int, depth: float, hs: float) -> Color:
	if type >= Arena.T_ARENA:
		return Arena.side_col(type, depth, hs)
	if type == T_GRASS or type == T_BED:
		if depth < 0.7:
			return Color(0.40, 0.62, 0.27)
		if depth < 3.6:
			return Color(0.76, 0.50, 0.27) * (0.94 + 0.1 * hs)
	if type == T_WATER and depth < 1.0:
		return Color(0.44, 0.74, 0.80)
	return Color(0.66, 0.65, 0.68).lerp(Color(0.50, 0.50, 0.56), clampf(depth / 16.0, 0.0, 1.0)) * (0.94 + 0.1 * hs)


func _side(p0: Vector3, p1: Vector3, n: Vector3, ytop: float, ybot: float, type: int, hs: float) -> void:
	# 按颜色分层切成几段（草边 0.7、土 2、往下每 4 米一段）
	var y := ytop
	var cuts := [0.7, 3.6, 7.0, 11.0, 15.0, 19.0, 30.0]
	for cut: float in cuts:
		var yb := maxf(ytop - cut, ybot)
		if yb >= y - 0.01:
			continue
		_quad(_g, Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Vector3(p1.x, yb, p1.z), Vector3(p0.x, yb, p0.z), n,
				_side_col(type, ytop - (y + yb) * 0.5, hs), 0.0, false)
		y = yb
		if y <= ybot + 0.01:
			break


func _mesh_ground() -> void:
	for j in N:
		for i in N:
			var h := _h[j * N + i]
			if h < VOID + 1.0:
				continue
			var type := int(_t[j * N + i])
			var x0 := float(i - HN) * CELL
			var z0 := float(j - HN) * CELL
			var c := _top_col(type, i, j, x0 + 1.0, z0 + 1.0)
			_quad_ao(Vector3(x0, h, z0), Vector3(x0 + CELL, h, z0), Vector3(x0 + CELL, h, z0 + CELL), Vector3(x0, h, z0 + CELL), c,
					0.35 if type == T_WATER else 0.0, [_ao(i, j, -1, -1, h), _ao(i, j, 1, -1, h), _ao(i, j, 1, 1, h), _ao(i, j, -1, 1, h)])
			var hs := _hash(i * 7 + 3, j * 11 + 5)
			# 四邻比自己低就补一面侧壁；岛外（没有地）垂 18 米的崖壁
			var nb := [[-1, 0], [1, 0], [0, -1], [0, 1]]
			for k in 4:
				var ni: int = i + int(nb[k][0])
				var nj: int = j + int(nb[k][1])
				var nh := h - 18.0
				if _in(ni, nj) and _h[nj * N + ni] > VOID + 1.0:
					nh = _h[nj * N + ni]
				if nh >= h - 0.01:
					continue
				match k:
					0:
						_side(Vector3(x0, 0, z0 + CELL), Vector3(x0, 0, z0), Vector3.LEFT, h, nh, type, hs)
					1:
						_side(Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3.RIGHT, h, nh, type, hs)
					2:
						_side(Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3.FORWARD, h, nh, type, hs)
					3:
						_side(Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL), Vector3.BACK, h, nh, type, hs)
	# 岛底：往下收小的几层石头（从云里露出来的岛根）
	for k in 5:
		var s := 118.0 - 24.0 * float(k)
		BlockWorld._box(_g, Vector3(s, 9.0, s * 0.9), Transform3D(Basis(Vector3.UP, 0.3 * float(k)), Vector3(0.0, -22.0 - 8.0 * float(k), -2.0)),
				Color(0.50, 0.49, 0.56) * (1.0 - 0.07 * float(k)), 0.0, 0.8)


func _commit(a: Array, shadow: bool) -> void:
	if (a[0] as PackedVector3Array).is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)


# ---------- 建筑和点缀 ----------

func _b(size: Vector3, pos: Vector3, c: Color, yaw := 0.0, em := 0.0, shade := 0.72) -> void:
	BlockWorld._box(_a, size, Transform3D(Basis(Vector3.UP, yaw), pos), c, em, shade)


func _lamp(x: float, z: float, y := 0.0) -> void:
	# 石灯柱：灰石柱顶一块暖黄的灯
	_b(Vector3(0.9, 0.4, 0.9), Vector3(x, y + 0.2, z), Color(0.62, 0.61, 0.62))
	_b(Vector3(0.5, 2.2, 0.5), Vector3(x, y + 1.5, z), Color(0.55, 0.54, 0.56))
	_b(Vector3(0.9, 0.9, 0.9), Vector3(x, y + 3.0, z), Color(1.0, 0.80, 0.40), 0.0, 0.6, 0.95)
	_b(Vector3(1.3, 0.3, 1.3), Vector3(x, y + 3.6, z), Color(0.36, 0.34, 0.38))


func _bench(x: float, z: float, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	_b(Vector3(3.2, 0.3, 1.0), Vector3(x, 0.75, z), Color(0.56, 0.36, 0.22), yaw)
	_b(Vector3(3.2, 0.9, 0.24), Vector3(x, 1.3, z) + bs * Vector3(0.0, 0.0, 0.5), Color(0.50, 0.31, 0.19), yaw)
	for sx: float in [-1.3, 1.3]:
		_b(Vector3(0.3, 0.7, 0.9), Vector3(x, 0.35, z) + bs * Vector3(sx, 0.0, 0.0), Color(0.42, 0.26, 0.17), yaw)


func _flowers(x: float, z: float, y: float, rng: RandomNumberGenerator, n := 7, spread := 2.4) -> void:
	var cols := [Color(1.0, 0.72, 0.84), Color(1.0, 0.96, 0.9), Color(1.0, 0.86, 0.5), Color(0.86, 0.72, 1.0)]
	for i in n:
		var p := Vector3(x + rng.randf_range(-spread, spread), y, z + rng.randf_range(-spread, spread))
		# 2026-11-23 每朵高矮错开 4.5 厘米：挨在一起的两朵花顶面不再同高（同高 + 不同色 = 闪面）
		var fh := 0.045 * float(i)
		_b(Vector3(0.22, 0.6 + fh, 0.22), p + Vector3(0, 0.3 + fh * 0.5, 0), Color(0.36, 0.6, 0.28))
		_b(Vector3(0.6, 0.4, 0.6), p + Vector3(0, 0.75 + fh, 0), cols[rng.randi() % cols.size()], rng.randf() * 0.8, 0.0, 0.95)


func _flag(x: float, z: float, y: float, yaw: float) -> void:
	# 旗幡：石座、木杆、一面靛紫的幡（中间一块浅色的纹）
	var bs := Basis(Vector3.UP, yaw)
	_b(Vector3(1.0, 0.5, 1.0), Vector3(x, y + 0.25, z), Color(0.62, 0.61, 0.62))
	_b(Vector3(0.3, 6.4, 0.3), Vector3(x, y + 3.6, z), Color(0.36, 0.24, 0.17))
	_b(Vector3(2.0, 0.3, 0.3), Vector3(x, y + 6.5, z) + bs * Vector3(0.8, 0.0, 0.0), Color(0.36, 0.24, 0.17), yaw)
	_b(Vector3(1.7, 3.6, 0.14), Vector3(x, y + 4.5, z) + bs * Vector3(1.0, 0.0, 0.0), Color(0.42, 0.44, 0.78), yaw, 0.0, 0.95)
	_b(Vector3(0.9, 0.9, 0.26), Vector3(x, y + 4.7, z) + bs * Vector3(1.0, 0.0, 0.0), Color(0.86, 0.88, 1.0), yaw, 0.0, 1.0)


func _crate(x: float, z: float, y: float, s: float, yaw := 0.0) -> void:
	_b(Vector3(s, s, s), Vector3(x, y + s * 0.5, z), Color(0.72, 0.52, 0.3), yaw)
	_b(Vector3(s + 0.08, s * 0.16, s + 0.08), Vector3(x, y + s * 0.5, z), Color(0.52, 0.36, 0.2), yaw)


func _parapet(x0: float, z0: float, x1: float, z1: float, y := 0.0) -> void:
	# 一段石栏（矮墙 + 隔一段一个墩子），顺便记成实心
	var a := Vector3(x0, 0, z0)
	var b := Vector3(x1, 0, z1)
	var d := b - a
	var yaw := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	_b(Vector3(0.8, 1.1, d.length()), mid + Vector3(0, y + 0.55, 0), Color(0.74, 0.73, 0.72), yaw)
	_b(Vector3(1.0, 0.25, d.length() + 0.2), mid + Vector3(0, y + 1.2, 0), Color(0.82, 0.81, 0.80), yaw)
	var n := maxi(int(d.length() / 6.0), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_b(Vector3(1.1, 1.7, 1.1), p + Vector3(0, y + 0.85, 0), Color(0.68, 0.67, 0.68), yaw)
	_block(minf(x0, x1) - 0.4, minf(z0, z1) - 0.4, maxf(x0, x1) + 0.4, maxf(z0, z1) + 0.4, y + 1.3)


func _build_structures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var st := Color(0.78, 0.73, 0.70)          # 2026-11-23 石墙：暖一点的灰（原来 0.74 / 0.66 的中性灰）
	var st2 := Color(0.70, 0.66, 0.66)
	var tile := Color(0.27, 0.26, 0.33)        # 黛瓦
	var wood := Color(0.48, 0.30, 0.19)
	var wall_y := TERRACE_H
	# ---- 关卡入口：石墙（四个门洞之间是墙垛，门洞上面补到墙顶），墙顶两重瓦顶（中间一段抬高成门楼），两头各一座角楼 ----
	var half := GATE_W * 0.5 + 0.6
	var edges: Array = [-44.0]
	for gd: Dictionary in GATES:
		edges.append(float(gd["x"]) - half)
		edges.append(float(gd["x"]) + half)
	edges.append(44.0)
	for k in range(0, edges.size(), 2):
		var x0 := float(edges[k])
		var x1 := float(edges[k + 1])
		_b(Vector3(x1 - x0, WALL_H, 4.0), Vector3((x0 + x1) * 0.5, wall_y + WALL_H * 0.5, WALL_Z), st if k % 4 == 0 else st2)
		# 墙脚一道深色的基石，墙面几块不同深浅的砖
		_b(Vector3(x1 - x0 + 0.3, 1.2, 4.3), Vector3((x0 + x1) * 0.5, wall_y + 0.6, WALL_Z), Color(0.56, 0.55, 0.58))
		for q in 4:
			_b(Vector3(1.6, 0.9, 0.2 + 0.07 * float(q)), Vector3(lerpf(x0 + 1.0, x1 - 1.0, rng.randf()), wall_y + rng.randf_range(2.5, WALL_H - 2.0), WALL_Z + 2.05), Color(0.63, 0.60, 0.61))     # 2026-11-23 每块砖鼓出来的多少不一样（两块叠着时正面不共面）
	_b(Vector3(89.6, 0.5, 5.6), Vector3(0.0, wall_y + WALL_H + 0.25, WALL_Z), Color(0.52, 0.2, 0.16))
	_b(Vector3(89.0, 1.2, 5.0), Vector3(0.0, wall_y + WALL_H + 1.1, WALL_Z), Color(0.70, 0.69, 0.70))
	_bw._roof(_a, Vector3(0.0, wall_y + WALL_H + 1.7, WALL_Z), 88.0, 8.0, 0.0, tile)
	_b(Vector3(38.0, 2.6, 4.4), Vector3(0.0, wall_y + WALL_H + 4.2, WALL_Z), Color(0.76, 0.75, 0.75))
	_bw._roof(_a, Vector3(0.0, wall_y + WALL_H + 5.5, WALL_Z), 38.0, 6.0, 0.0, tile)
	for sx: float in [-1.0, 1.0]:
		_bw._hall(_a, Vector3(sx * 48.5, wall_y, WALL_Z), 8.0, 8.0, 12.0, 0.0, 6, 2)
		_block(sx * 48.5 - 4.9, WALL_Z - 4.9, sx * 48.5 + 4.9, WALL_Z + 4.9, wall_y + 22.0)
	# 每道门：门洞后面一堵暗墙（门心是一张拱形的面片），一圈有颜色的门框（两根门柱 + 沿拱顶一级级收上去的拱石），各自的小装饰；
	# 没开的门：门心暗着，交叉拴两道铁链、挂一把铜锁
	for gi in GATES.size():
		var gd: Dictionary = GATES[gi]
		var gx := float(gd["x"])
		var fc: Color = gd["frame"]
		var open := bool(gd["open"])
		var zf := WALL_Z + 2.25
		var aw := GATE_W * 0.5
		var ah := GATE_H * 0.32
		var y0 := wall_y + GATE_H * 0.68
		_b(Vector3(GATE_W + 1.2, WALL_H, 0.8), Vector3(gx, wall_y + WALL_H * 0.5, WALL_Z - 1.4), Color(0.13, 0.12, 0.17))
		_b(Vector3(GATE_W + 1.2, WALL_H - GATE_H + 0.1, 4.0), Vector3(gx, wall_y + (WALL_H + GATE_H) * 0.5 - 0.05, WALL_Z), st)
		for sx: float in [-1.0, 1.0]:
			_b(Vector3(1.4, GATE_H * 0.68, 1.0), Vector3(gx + sx * (aw + 0.3), wall_y + GATE_H * 0.34, zf), fc)
			_b(Vector3(1.9, 0.9, 1.3), Vector3(gx + sx * (aw + 0.3), wall_y + 0.45, zf), fc * 0.8)
			for k in 4:
				var xe := aw * sqrt(maxf(1.0 - pow((float(k) + 0.5) / 4.0, 2.0), 0.0))
				var yk := y0 + ah * (float(k) + 0.5) / 4.0
				_b(Vector3(aw + 0.6 - xe, ah / 4.0 + 0.02, 1.4), Vector3(gx + sx * (xe + (aw + 0.6 - xe) * 0.5), yk, WALL_Z + 1.27), st)
				_b(Vector3(1.5, ah / 4.0 + 0.1, 1.12 + 0.12 * float(k % 2)), Vector3(gx + sx * (xe + 0.45), yk, zf), fc * (1.08 if k % 2 == 0 else 0.96))     # 2026-11-23 相邻拱石一块鼓出 6 厘米、一块 12 厘米：正面不共面
		_b(Vector3(aw * 0.9, 1.1, 1.0), Vector3(gx, wall_y + GATE_H + 0.35, zf), fc * 1.1)
		match gi:
			0:      # 草木：门框上爬着几团叶子
				for q in 12:
					_b(Vector3(1.4, 1.1, 0.8), Vector3(gx + (-1.0 if q % 2 == 0 else 1.0) * rng.randf_range(3.8, 6.0), wall_y + rng.randf_range(1.0, GATE_H - 0.5), zf + 0.4),
							Color(0.3, 0.62, 0.26) * rng.randf_range(0.85, 1.15), rng.randf() * 0.4, 0.0, 0.9)
			1:      # 冰：门脚几簇淡蓝的冰晶
				for q in 8:
					_b(Vector3(0.8, rng.randf_range(1.4, 3.4), 0.8), Vector3(gx + (-1.0 if q % 2 == 0 else 1.0) * rng.randf_range(4.6, 6.6), wall_y + 1.2, zf + 0.5),
							Color(0.72, 0.9, 1.0), rng.randf() * 0.8, 0.4, 0.95)
			2:      # 火：门柱上几道发亮的熔岩缝
				for q in 8:
					_b(Vector3(0.5, rng.randf_range(0.9, 2.0), 0.3), Vector3(gx + (-1.0 if q % 2 == 0 else 1.0) * (aw + 0.3), wall_y + rng.randf_range(1.2, GATE_H * 0.62), zf + 0.58),
							Color(1.0, 0.55, 0.15), 0.0, 0.35)
			_:      # 云纹：门脚几团淡紫的云
				for q in 7:
					_b(Vector3(1.8, 1.0, 1.0), Vector3(gx + (-1.0 if q % 2 == 0 else 1.0) * rng.randf_range(3.6, 6.4), wall_y + rng.randf_range(0.6, 2.2), zf + 0.5),
							Color(0.80, 0.72, 0.95), 0.0, 0.0, 0.95)
		if not open:
			for sg: float in [-1.0, 1.0]:
				BlockWorld._box(_a, Vector3(13.2, 0.5, 0.4), Transform3D(Basis(Vector3.BACK, sg * 0.74), Vector3(gx, wall_y + GATE_H * 0.42, zf + 0.1)), Color(0.22, 0.21, 0.25))
			_b(Vector3(2.0, 2.2, 0.7), Vector3(gx, wall_y + GATE_H * 0.42, zf + 0.3), Color(0.80, 0.62, 0.24))
			_b(Vector3(0.5, 0.9, 0.84), Vector3(gx, wall_y + GATE_H * 0.42 - 0.2, zf + 0.3), Color(0.2, 0.16, 0.12))
		_lamp(gx - 8.5, WALL_Z + 4.4, wall_y)
	_lamp(float(GATES[3]["x"]) + 8.5, WALL_Z + 4.4, wall_y)
	# 石台前沿的石栏（石阶口空着）和两面幡
	_parapet(-45.0, -38.6, -20.6, -38.6, TERRACE_H)
	_parapet(-9.4, -38.6, 9.4, -38.6, TERRACE_H)
	_parapet(20.6, -38.6, 45.0, -38.6, TERRACE_H)
	_flag(-23.0, -30.0, 0.0, 0.0)
	_flag(23.0, -30.0, 0.0, PI)
	# 两段石阶中间：一个花坛、一株樱
	_b(Vector3(8.0, 1.0, 5.0), Vector3(0.0, 0.5, -35.0), Color(0.70, 0.69, 0.70))
	_b(Vector3(7.0, 0.3, 4.0), Vector3(0.0, 1.05, -35.0), Color(0.48, 0.66, 0.30))
	_bw._blossom(_a, Vector3(0.0, 1.1, -35.0), 1.0, rng, 1)
	_block(-4.0, -37.5, 4.0, -32.5, 1.2)

	# ---- 商店（西面）：两层木楼（门朝广场），门口一道条纹布檐、柜台、酒坛，旁边两个带布棚的摊位 ----
	_bw._hall(_a, Vector3(-52.0, 0.0, -14.0), 18.0, 12.0, 5.4, -PI * 0.5, 4, 2)
	for q in 7:
		_b(Vector3(2.8, 0.26, 1.72), Vector3(-44.5, 4.5 - 0.0, -19.16 + 1.72 * float(q)), Color(0.62, 0.42, 0.74) if q % 2 == 0 else Color(0.97, 0.94, 0.86), 0.0, 0.0, 0.95)
	for pz: float in [-19.9, -8.1]:
		_b(Vector3(0.3, 4.4, 0.3), Vector3(-43.4, 2.2, pz), wood)
	_b(Vector3(1.3, 1.1, 4.4), Vector3(-44.3, 0.55, -18.8), wood)                      # 柜台
	for q in 5:
		_b(Vector3(0.5, 0.6, 0.5), Vector3(-44.3, 1.4, -20.4 + 0.8 * float(q)), [Color(0.5, 0.85, 1.0), Color(1.0, 0.75, 0.4), Color(0.75, 0.6, 1.0)][q % 3], 0.0, 0.3, 0.95)
	for bz: Array in [[-10.0, 1.3], [-8.6, 1.1], [-9.4, 1.0]]:                           # 酒坛
		var bx := -44.2 if bz[1] != 1.0 else -43.0
		_b(Vector3(float(bz[1]), float(bz[1]) * 1.15, float(bz[1])), Vector3(bx, float(bz[1]) * 0.58, float(bz[0])), Color(0.52, 0.34, 0.2))
		_b(Vector3(float(bz[1]) + 0.08, 0.16, float(bz[1]) + 0.08), Vector3(bx, float(bz[1]) * 0.85, float(bz[0])), Color(0.3, 0.2, 0.14))
	for hz: float in [-17.0, -11.0]:                                                    # 檐下两盏红灯笼
		_b(Vector3(0.8, 1.0, 0.8), Vector3(-43.6, 3.6, hz), Color(0.95, 0.32, 0.22), 0.0, 0.55, 0.95)
	_block(-45.0, -21.2, -43.6, -16.4, 1.2)
	for s: Array in [[-42.0, 13.0, Color(0.62, 0.42, 0.74)], [-52.0, 19.0, Color(0.93, 0.60, 0.42)]]:
		var sx2 := float(s[0])
		var sz2 := float(s[1])
		for cx: float in [-2.6, 2.6]:
			for cz: float in [-1.8, 1.8]:
				_b(Vector3(0.3, 3.2, 0.3), Vector3(sx2 + cx, 1.6, sz2 + cz), wood)
		# 条纹布棚：四条布、两种颜色
		for q in 4:
			_b(Vector3(1.5, 0.3, 4.6), Vector3(sx2 - 2.25 + 1.5 * float(q), 3.5 - 0.12 * absf(float(q) - 1.5), sz2),
					(s[2] as Color) if q % 2 == 0 else Color(0.97, 0.94, 0.86), 0.0, 0.0, 0.95)
		_b(Vector3(4.6, 1.0, 1.6), Vector3(sx2, 0.5, sz2), wood)
		for q in 4:
			_b(Vector3(0.6, 0.5, 0.6), Vector3(sx2 - 1.6 + 1.1 * float(q), 1.25, sz2), [Color(0.9, 0.4, 0.35), Color(0.45, 0.8, 0.5), Color(1.0, 0.85, 0.45), Color(0.55, 0.7, 1.0)][q], 0.0, 0.0, 0.95)
		_block(sx2 - 2.6, sz2 - 1.2, sx2 + 2.6, sz2 + 1.2, 1.1)

	# ---- 仓库（东面）：一座大库房（两扇钉着铁条的木门）、门口成垛的箱子和麻袋、板车、告示牌 ----
	_bw._hall(_a, Vector3(53.0, 0.0, -14.0), 20.0, 13.0, 6.2, PI * 0.5, 0, 1)
	for dz: float in [-1.0, 1.0]:
		_b(Vector3(0.4, 4.6, 2.9), Vector3(46.3, 3.0, -14.0 + dz * 1.5), Color(0.50, 0.33, 0.2))
		for hy: float in [1.6, 4.2]:
			_b(Vector3(0.52, 0.3, 2.78), Vector3(46.28, hy, -14.0 + dz * 1.5), Color(0.26, 0.24, 0.26))
	_b(Vector3(0.5, 5.0, 0.3), Vector3(46.3, 3.1, -14.0), Color(0.3, 0.2, 0.14))
	for c: Array in [[43.6, -20.0, 0.0, 1.8], [43.8, -18.0, 0.0, 1.4], [43.6, -20.0, 1.8, 1.3], [44.0, -8.4, 0.0, 1.7], [43.8, -6.6, 0.0, 1.3], [44.2, -8.2, 1.7, 1.1],
			[38.0, 3.6, 0.0, 1.5], [36.4, 4.6, 0.0, 1.2]]:
		_crate(float(c[0]), float(c[1]), float(c[2]), float(c[3]), rng.randf() * 0.3)
	for q in 4:                                                                         # 麻袋
		_b(Vector3(1.3, 0.7 + 0.06 * float(q % 2), 0.9), Vector3(42.0, 0.35 + 0.03 * float(q % 2) + 0.62 * float(q / 2), -9.6 + 1.1 * float(q % 2)), Color(0.80, 0.70, 0.5) * (0.92 + 0.08 * float(q % 2)), 0.3 * float(q))
	_block(42.4, -21.2, 45.0, -16.8, 1.8)
	_block(42.8, -9.6, 45.0, -5.6, 1.7)
	_block(35.6, 2.6, 39.0, 5.4, 1.5)
	# 板车
	_b(Vector3(3.2, 0.4, 2.0), Vector3(37.0, 1.0, -2.0), Color(0.56, 0.38, 0.22), 0.3)
	for sx3: float in [-1.0, 1.0]:
		_b(Vector3(0.3, 1.4, 1.4), Vector3(37.0, 0.7, -2.0) + Basis(Vector3.UP, 0.3) * Vector3(0.0, 0.0, sx3 * 1.2), Color(0.36, 0.24, 0.16), 0.3)
	_crate(36.6, -2.2, 1.2, 1.1, 0.3)
	_crate(37.8, -1.7, 1.2, 0.9, 0.5)
	_block(35.2, -3.4, 38.8, -0.6, 1.4)
	# 告示牌：两根柱、一块板、一顶小檐
	for sx4: float in [-1.0, 1.0]:
		_b(Vector3(0.4, 3.6, 0.4), Vector3(30.0 + sx4 * 2.0, 1.8, 9.0), wood)
	_b(Vector3(4.3, 2.2, 0.3), Vector3(30.0, 2.4, 9.0), Color(0.90, 0.84, 0.68))
	for q in 4:
		_b(Vector3(1.4, 0.16, 0.42), Vector3(29.0 + 2.0 * float(q % 2), 2.9 - 0.5 * float(q / 2), 9.0), Color(0.3, 0.26, 0.24))
	_bw._roof(_a, Vector3(30.0, 3.7, 9.0), 4.6, 0.6, 0.0, tile)
	_block(27.6, 8.4, 32.4, 9.6, 3.0)
	# 池边一座小亭
	_bw._hall(_a, Vector3(-60.0, 0.0, 30.0), 6.0, 6.0, 3.8, PI * 0.5, 6, 1)
	_block(-63.6, 26.4, -56.4, 33.6, 6.0)

	# ---- 修炼场（东南）：竹篱、牌坊、阵台上的符纹和四块符石、木人桩、竹丛 ----
	_bw._paifang(_a, Vector3(28.0, 0.0, 30.0), PI * 0.25, 6)
	for seg: Array in [[32.0, 24.0, 64.0, 24.0], [64.0, 24.0, 64.0, 58.0], [26.0, 36.0, 26.0, 58.0]]:
		var pa := Vector3(float(seg[0]), 0, float(seg[1]))
		var pb := Vector3(float(seg[2]), 0, float(seg[3]))
		var dd := pb - pa
		var yaw2 := atan2(dd.x, dd.z)
		for hy: float in [0.6, 1.2]:
			_b(Vector3(0.2, 0.2, dd.length()), (pa + pb) * 0.5 + Vector3(0, hy, 0), Color(0.56, 0.4, 0.24), yaw2)
		for q in int(dd.length() / 3.0) + 1:
			_b(Vector3(0.3, 1.5, 0.3), pa + dd.normalized() * 3.0 * float(q) + Vector3(0, 0.75, 0), Color(0.48, 0.33, 0.2))
		_block(minf(pa.x, pb.x) - 0.3, minf(pa.z, pb.z) - 0.3, maxf(pa.x, pb.x) + 0.3, maxf(pa.z, pb.z) + 0.3, 1.3)
	# 阵台：两圈符纹（发青光）、正中一块蒲团
	for q in 16:
		var ang := TAU * float(q) / 16.0
		_b(Vector3(1.3, 0.12, 0.5), MED_POS + Vector3(cos(ang) * 4.0, 0.08, sin(ang) * 4.0), Color(0.55, 0.92, 1.0), -ang, 0.8)
	for q in 8:
		var ang2 := TAU * (float(q) + 0.5) / 8.0
		_b(Vector3(0.9, 0.12, 0.4), MED_POS + Vector3(cos(ang2) * 2.3, 0.08, sin(ang2) * 2.3), Color(0.75, 0.82, 1.0), -ang2, 0.6)
	_b(Vector3(1.6, 0.24, 1.6), MED_POS + Vector3(0.0, 0.12, 0.0), Color(0.62, 0.46, 0.76), PI * 0.25)
	for q in 4:
		var ang3 := TAU * (float(q) + 0.5) / 4.0
		var rp := MED_POS + Vector3(cos(ang3) * 7.6, -0.5, sin(ang3) * 7.6)
		_b(Vector3(1.6, 0.5, 1.6), rp + Vector3(0, 0.25, 0), Color(0.66, 0.65, 0.68))
		_b(Vector3(1.3, 3.2, 0.8), rp + Vector3(0, 2.1, 0), Color(0.58, 0.58, 0.64), -ang3 + PI * 0.5)
		_b(Vector3(0.5, 2.0, 0.9), rp + Vector3(0, 2.3, 0), Color(0.50, 0.90, 1.0), -ang3 + PI * 0.5, 0.7, 1.0)
		_b(Vector3(0.6, 0.6, 0.6), rp + Vector3(0, 4.3, 0), Color(0.66, 0.92, 1.0), -ang3 + PI * 0.5 + 0.6, 0.8, 0.95)
		_block(rp.x - 0.8, rp.z - 0.8, rp.x + 0.8, rp.z + 0.8, 3.6)
	for dm: Array in [[33.0, 50.0], [37.0, 54.0]]:
		_b(Vector3(0.4, 2.4, 0.4), Vector3(float(dm[0]), 1.2, float(dm[1])), wood)
		_b(Vector3(2.0, 0.4, 0.4), Vector3(float(dm[0]), 1.7, float(dm[1])), wood, 0.4)
		_b(Vector3(0.7, 0.7, 0.7), Vector3(float(dm[0]), 2.6, float(dm[1])), Color(0.60, 0.42, 0.26))
	for q in 26:
		var bx := rng.randf_range(54.0, 63.0)
		var bz := rng.randf_range(25.5, 37.0)
		var bh := rng.randf_range(5.0, 9.0)
		_b(Vector3(0.36, bh, 0.36), Vector3(bx, bh * 0.5, bz), Color(0.42, 0.62, 0.26) * rng.randf_range(0.85, 1.15))
		_b(Vector3(1.5, 0.7, 1.5), Vector3(bx, bh * rng.randf_range(0.7, 1.0), bz), Color(0.36, 0.60, 0.24), rng.randf(), 0.0, 0.8)
	# 石灯笼（修炼场角上）
	_lamp(60.0, 54.0)
	_lamp(30.0, 54.0)

	# ---- 灵泉台（地标的基座，会动的晶体另外建）：三层八角石台（每层是两个错开 45° 的方台），两圈发光的泉水，八根顶着灵珠的石柱 ----
	for k in 2:
		var yw := PI * 0.25 * float(k)
		_b(Vector3(19.0, 0.8, 19.0), Vector3(0.0, 0.4, 0.0), Color(0.70, 0.69, 0.72), yw)
		_b(Vector3(17.2, 0.3, 17.2), Vector3(0.0, 0.72, 0.0), Color(0.40, 0.86, 0.95), yw, 0.55, 1.0)
		_b(Vector3(11.4, 1.3, 11.4), Vector3(0.0, 1.35, 0.0), Color(0.80, 0.79, 0.81), yw)
		_b(Vector3(9.8, 0.3, 9.8), Vector3(0.0, 1.92, 0.0), Color(0.52, 0.90, 0.98), yw, 0.65, 1.0)
		_b(Vector3(5.2, 1.7, 5.2), Vector3(0.0, 2.8, 0.0), Color(0.72, 0.71, 0.75), yw)
		_b(Vector3(3.4, 0.9, 3.4), Vector3(0.0, 4.0, 0.0), Color(0.66, 0.56, 0.92), yw, 0.5, 0.95)
	for q in 8:
		var ang4 := TAU * (float(q) + 0.5) / 8.0
		var pp := Vector3(cos(ang4) * 11.4, 0.0, sin(ang4) * 11.4)
		_b(Vector3(1.5, 0.5, 1.5), pp + Vector3(0, 0.25, 0), Color(0.60, 0.59, 0.63), -ang4)
		_b(Vector3(1.0, 2.4, 1.0), pp + Vector3(0, 1.7, 0), Color(0.68, 0.67, 0.70), -ang4)
		_b(Vector3(0.8, 0.8, 0.8), pp + Vector3(0, 3.4, 0), Color(0.60, 0.92, 1.0), -ang4 + 0.6, 0.8, 0.95)
		_block(pp.x - 0.8, pp.z - 0.8, pp.x + 0.8, pp.z + 0.8, 2.9)
		# 第二层往下淌的四道小水帘
		if q % 2 == 0:
			_b(Vector3(1.6, 1.2, 0.3), Vector3(cos(ang4) * 6.2, 1.35, sin(ang4) * 6.2), Color(0.70, 0.94, 1.0), -ang4 + PI * 0.5, 0.6, 1.0)

	# ---- 莲池上的拱桥、池里的荷叶荷花、池边的小亭灯 ----
	for k in 7:
		var u := (float(k) - 3.0) / 3.0
		var bp := Vector3(-25.0, 0.0, 39.0).lerp(Vector3(-33.0, 0.0, 30.0), float(k) / 6.0)
		_b(Vector3(4.4, 0.4, 1.7), bp + Vector3(0, 1.5 - 1.2 * u * u, 0), Color(0.60, 0.40, 0.25), PI * 0.23)
		for sx5: float in [-1.0, 1.0]:
			_b(Vector3(0.3, 1.0, 1.58), bp + Basis(Vector3.UP, PI * 0.23) * Vector3(sx5 * 2.1, 2.1 - 1.2 * u * u, 0), Color(0.5, 0.3, 0.2), PI * 0.23)
	for q in 12:
		var lx := rng.randf_range(-52.0, -29.0)
		var lz := rng.randf_range(37.0, 51.0)
		if _type_at(lx, lz) != T_WATER:
			continue
		_b(Vector3(1.5, 0.12, 1.5), Vector3(lx, -0.52, lz), Color(0.40, 0.70, 0.36), rng.randf(), 0.0, 1.0)
		if q % 3 == 0:
			_b(Vector3(0.7, 0.5, 0.7), Vector3(lx, -0.2, lz), Color(1.0, 0.66, 0.82), rng.randf(), 0.0, 1.0)
	_lamp(-22.0, 34.0)
	# 落到岛外的瀑布：小溪尽头一道水帘（发亮的浅蓝），再加西南崖上一道
	var wz := 48.0
	while _type_at(-54.0, wz + CELL) == T_WATER:
		wz += CELL
	var edge := float(_ci(wz) - HN + 1) * CELL
	_b(Vector3(7.6, 17.0, 0.7), Vector3(-54.0, -9.22, edge + 0.3), Color(0.70, 0.92, 1.0), 0.0, 0.5, 1.0)       # 2026-11-23 水帘顶比水面低 12 厘米（原来同高，闪面）
	_b(Vector3(9.0, 2.4, 3.0), Vector3(-54.0, -17.0, edge + 1.4), Color(1.0, 0.98, 1.0), 0.0, 0.4, 1.0)

	# ---- 进城的石道：两根灯柱、两边的木栏，岛南沿的石栏 ----
	for sx6: float in [-1.0, 1.0]:
		_b(Vector3(1.4, 4.2, 1.4), Vector3(sx6 * 7.6, 2.1, 62.0), Color(0.72, 0.71, 0.72))
		_b(Vector3(1.9, 0.4, 1.9), Vector3(sx6 * 7.6, 4.4, 62.0), Color(0.34, 0.32, 0.38))
		_b(Vector3(1.2, 1.2, 1.2), Vector3(sx6 * 7.6, 5.2, 62.0), Color(1.0, 0.86, 0.45), 0.0, 1.0)
		_bw._roof(_a, Vector3(sx6 * 7.6, 5.8, 62.0), 1.6, 1.6, 0.0, tile)
		_block(sx6 * 7.6 - 0.8, 61.2, sx6 * 7.6 + 0.8, 62.8, 5.0)
		for q in 6:
			_b(Vector3(0.3, 1.3, 0.3), Vector3(sx6 * 7.2, 0.65, 66.0 + 3.6 * float(q)), wood)
		_b(Vector3(0.2, 0.2, 20.0), Vector3(sx6 * 7.2, 1.1, 75.0), wood)
		_block(sx6 * 7.2 - 0.4, 64.0, sx6 * 7.2 + 0.4, 86.0, 1.3)
		_parapet(sx6 * 9.0, 60.6, sx6 * 42.0, 60.6)
	# 广场四周：一圈石灯和长凳
	for q in 8:
		var ang5 := TAU * (float(q) + 0.5) / 8.0
		_lamp(cos(ang5) * 31.5, sin(ang5) * 31.5)
	for q in 4:
		var ang6 := TAU * float(q) / 4.0 + PI * 0.25
		_bench(cos(ang6) * 19.0, sin(ang6) * 19.0, -ang6 + PI * 0.5)
	for lp: Array in [[-5.6, 40.0], [5.6, 40.0], [-5.6, 52.0], [5.6, 52.0], [-36.0, 6.4], [36.0, 6.4], [-36.0, -6.4], [36.0, -6.4], [-24.6, -27.0], [24.6, -27.0]]:
		_lamp(float(lp[0]), float(lp[1]), maxf(ground(float(lp[0]), float(lp[1])), 0.0))     # 2026-11-23 立在花圃的土面上（原来灯座顶和土面同高）
	# 2026-11-21 通灵田农场的牌坊门（和农场南门一个样子，hub_farm.gd 的 build_gate）、石路两边的石灯
	Farm.build_gate(_bw, _a, Transform3D(Basis(Vector3.UP, -PI * 0.5), FARM_GATE), -PI * 0.5)
	for lx: float in [36.0, 46.0]:
		_lamp(lx, 12.2)
		_lamp(lx, 19.8)
	for sz2: float in [-1.0, 1.0]:
		_lamp(FARM_GATE.x - 3.0, FARM_GATE.z + sz2 * 8.6)
	# 2026-11-23 两侧的擂台（石栏、灯柱、金纹、石阶、牌坊、红幡）
	Arena.build(self)


func _type_at(x: float, z: float) -> int:
	var i := _ci(x)
	var j := _ci(z)
	if not _in(i, j) or _h[j * N + i] < VOID + 1.0:
		return 0
	return int(_t[j * N + i])


func _free_spot(x: float, z: float) -> bool:
	var i := _ci(x)
	var j := _ci(z)
	return _in(i, j) and _h[j * N + i] > VOID + 1.0 and int(_t[j * N + i]) == T_GRASS and _solid[j * N + i] <= 0.0


## 花树、绿树、灌木、花圃里的花；岛外的云团和小浮岛
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	# 樱（粉）和绿树：照参考图摆在各处的草地上
	var blossoms := [[-34.0, -30.0], [34.0, -30.0], [-62.0, -30.0], [62.0, -34.0], [-30.0, 14.0], [-58.0, 28.0], [-14.0, 44.0], [-62.0, 4.0],
			[62.0, 10.0], [16.0, 46.0], [58.0, 44.0], [-20.0, 54.0], [36.0, 16.0], [-66.0, -12.0], [66.0, -16.0], [12.0, 62.0]]
	for p: Array in blossoms:
		if _free_spot(float(p[0]), float(p[1])):
			_bw._blossom(_a, Vector3(float(p[0]), 0.0, float(p[1])), rng.randf_range(0.9, 1.25), rng, 1)
			_block(float(p[0]) - 0.6, float(p[1]) - 0.6, float(p[0]) + 0.6, float(p[1]) + 0.6, 3.0)
	var greens := [[-44.0, 24.0], [44.0, 14.0], [-22.0, -44.0], [22.0, -44.0], [-66.0, 18.0], [20.0, 36.0], [-10.0, 56.0], [66.0, 30.0], [-48.0, -34.0], [48.0, -36.0], [-36.0, 58.0]]
	for p2: Array in greens:
		if _free_spot(float(p2[0]), float(p2[1])):
			_bw._blossom(_a, Vector3(float(p2[0]), 0.0, float(p2[1])), rng.randf_range(0.85, 1.1), rng, 2)
			_block(float(p2[0]) - 0.6, float(p2[1]) - 0.6, float(p2[0]) + 0.6, float(p2[1]) + 0.6, 3.0)
	_bw._blossom(_a, Vector3(-66.0, 0.0, 34.0), 1.2, rng, 0)       # 池边一株紫藤
	for fp: Array in [[64.0, 5.0, 1], [65.0, 23.0, 1], [50.0, 25.0, 2]]:      # 2026-11-21 农场门两边的樱
		if _free_spot(float(fp[0]), float(fp[1])):
			_bw._blossom(_a, Vector3(float(fp[0]), 0.0, float(fp[1])), 1.15, rng, int(fp[2]))
			_block(float(fp[0]) - 0.6, float(fp[1]) - 0.6, float(fp[0]) + 0.6, float(fp[1]) + 0.6, 3.0)
	for q in 22:
		var bx := rng.randf_range(-68.0, 68.0)
		var bz := rng.randf_range(-36.0, 58.0)
		if _free_spot(bx, bz) and Vector2(bx, bz).length() > 34.0:
			_bw._bush(_a, Vector3(bx, 0.0, bz), rng.randf_range(0.7, 1.1), Color(0.34, 0.60, 0.26) * rng.randf_range(0.9, 1.15), rng)
	# 花圃里的花，路边零星的花
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_flowers(sx * 27.0, sz * 27.0, 0.4, rng, 10, 2.5)
	for q in 16:
		var fx := rng.randf_range(-66.0, 66.0)
		var fz := rng.randf_range(-34.0, 58.0)
		if _free_spot(fx, fz):
			_flowers(fx, fz, 0.0, rng, 4, 1.6)
	# 云团：岛的四周、比岛面低一点的地方一圈白云（方块堆的），远处再一圈
	for q in (26 if mobile else 44):
		var ang := TAU * float(q) / (26.0 if mobile else 44.0) + rng.randf_range(-0.1, 0.1)
		var rad := rng.randf_range(92.0, 190.0)
		var cp := Vector3(cos(ang) * rad, rng.randf_range(-20.0, -7.0), sin(ang) * rad)
		for k in 3:
			var s := rng.randf_range(12.0, 26.0)
			var csz := Vector3(s, s * 0.34, s * rng.randf_range(0.6, 1.0))
			var cpos := cp + Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-2.0, 3.0), rng.randf_range(-9.0, 9.0))
			var ccol := Color(1.0, 0.94, 0.93).lerp(Color(0.97, 0.85, 0.93), rng.randf())
			var cyaw := rng.randf() * 0.6
			if not Arena.over(cpos.x, cpos.z):       # 2026-11-23 两侧擂台那两块岛的上空不摆云
				BlockWorld._box(_a, csz, Transform3D(Basis(Vector3.UP, cyaw) * Basis.from_euler(BlockWorld._wob(cpos)), cpos), ccol, 0.0, 0.76)     # 云底压暗一点（有体积）；歪一两度（叠着的两团顶面不共面）
	# 小浮岛：草顶、往下收的石根、一株树或一座小亭、一道瀑布
	var isles := [[-150.0, 18.0, -170.0, 26.0], [140.0, 30.0, -190.0, 30.0], [-210.0, 44.0, -60.0, 22.0], [220.0, 22.0, -40.0, 24.0], [60.0, 52.0, -260.0, 34.0],
			[-70.0, 60.0, -250.0, 28.0], [190.0, 12.0, 90.0, 20.0], [-190.0, 8.0, 110.0, 18.0]]
	for q in isles.size():
		var e: Array = isles[q]
		var ip := Vector3(float(e[0]), float(e[1]), float(e[2]))
		var s2 := float(e[3])
		_b(Vector3(s2, 2.0, s2 * 0.8), ip, Color(0.52, 0.72, 0.32), 0.3 * float(q))
		_b(Vector3(s2 * 0.96, 1.6, s2 * 0.76), ip - Vector3(0, 1.8, 0), Color(0.86, 0.55, 0.26), 0.3 * float(q))
		for k in 3:
			var sk := s2 * (0.8 - 0.22 * float(k))
			_b(Vector3(sk, 5.0, sk * 0.8), ip - Vector3(0, 5.0 + 4.6 * float(k), 0), Color(0.60, 0.59, 0.64) * (1.0 - 0.08 * float(k)), 0.3 * float(q) + 0.2 * float(k))
		if q % 2 == 0:
			_bw._blossom(_a, ip + Vector3(-s2 * 0.2, 1.0, 0.0), 1.5, rng, 1)
		else:
			_bw._hall(_a, ip + Vector3(0.0, 1.0, 0.0), 7.0, 7.0, 5.0, 0.0, 6, 2)
		_b(Vector3(3.0, 26.0, 0.6), ip + Vector3(s2 * 0.3, -13.0, s2 * 0.41), Color(0.72, 0.92, 1.0), 0.3 * float(q), 0.45, 1.0)


# ---------- 地标：灵泉台上的紫晶 ----------

static func _gem_mesh(r: float, up: float, down: float) -> ArrayMesh:
	# 八面体：上尖长、下尖短
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []
	for i in 4:
		var a := TAU * float(i) / 4.0
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in 4:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 4]
		for tip: Vector3 in [Vector3(0, up, 0), Vector3(0, -down, 0)]:
			var tri := [p0, tip, p1] if tip.y > 0.0 else [p0, p1, tip]
			var n := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
			for v: Vector3 in tri:
				st.set_normal(-n)
				st.add_vertex(v)
	return st.commit()


func _build_landmark() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled, fog_disabled, cull_disabled;\n" \
			+ "uniform vec3 deep = vec3(0.50, 0.36, 0.95);\nuniform vec3 lit = vec3(0.92, 0.86, 1.0);\n" \
			+ "void fragment() {\n\tfloat f = abs(dot(normalize(NORMAL), normalize(VIEW)));\n\tfloat k = 0.5 + 0.5 * sin(TIME * 1.3);\n" \
			+ "\tvec3 c = mix(lit, deep, f * (0.7 + 0.2 * k));\n#if CURRENT_RENDERER == RENDERER_COMPATIBILITY\n\tALBEDO = c;\n#else\n\tALBEDO = pow(c, vec3(2.2));\n#endif\n}\n"
	var gm := ShaderMaterial.new()
	gm.shader = sh
	_crystal = Node3D.new()
	_crystal.position = Vector3(0.0, 13.0, 0.0)
	_root.add_child(_crystal)
	var big := MeshInstance3D.new()
	big.mesh = _gem_mesh(3.0, 7.6, 4.8)
	big.material_override = gm
	big.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crystal.add_child(big)
	for i in 4:
		var s := MeshInstance3D.new()
		s.mesh = _gem_mesh(0.95, 2.4, 1.5)
		s.material_override = gm
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(s)
		_shards.append(s)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.62, 0.95, 1.0)
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 6.2 + 2.0 * float(i)
		tm.outer_radius = tm.inner_radius + 0.22
		tm.rings = 40
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0.0, 9.6 + 3.0 * float(i), 0.0)
		_root.add_child(ring)
		_rings.append(ring)


# ---------- 拱门的门心 ----------

func _build_gates() -> void:
	for gd: Dictionary in GATES:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(GATE_W, GATE_H)
		mi.mesh = qm
		var m := ShaderMaterial.new()
		m.shader = GATE_SHADER
		m.set_shader_parameter("noise_tex", NOISE)
		m.set_shader_parameter("col_a", gd["a"])
		m.set_shader_parameter("col_b", gd["b"])
		m.set_shader_parameter("locked", 0.0 if bool(gd["open"]) else 0.62)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(float(gd["x"]), TERRACE_H + GATE_H * 0.5, WALL_Z + 1.4)
		_root.add_child(mi)


# ---------- 牌匾 ----------

## 牌匾上的字统一用这一个字号出字（2026-11-24 手机内存）：字号 ≥ 65 的字，每种字号各占一套 1024×1024 的字库贴图
## （显存一份、引擎里再留一份，一套约 4 MB）。原来牌匾 96 / 100 / 110 / 120 四种字号 = 四套；统一成一种就共用一套。
## 牌子上字有多大由 pixel_size 定，和这个数无关——以后加牌匾别再另起字号（hub_arena.gd 的擂台匾也用它）。
const PLAQUE_FS := 96

## 一块挂牌：米色的板、深木边框（并进建筑那张静态网格），上面的字是一个 Label3D。yaw = 0 时朝 +Z（朝着进城的方向）
## size = 当初定的字号，现在只当「字占牌子多高」的旧参数留着，不再影响出字（见 PLAQUE_FS）
func _plaque(text: String, pos: Vector3, w: float, h: float, _size := 110, yaw := 0.0) -> void:
	var bs := Basis(Vector3.UP, yaw)
	_b(Vector3(w + 0.5, h + 0.5, 0.3), pos, Color(0.42, 0.27, 0.16), yaw)
	_b(Vector3(w, h, 0.2), pos + bs * Vector3(0.0, 0.0, 0.11), Color(0.95, 0.89, 0.70), yaw, 0.0, 1.0)     # 2026-11-23 只从正面鼓出 6 厘米（原来背面也鼓出 1 厘米，立着的牌子背面会闪）
	if font == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = PLAQUE_FS
	l.pixel_size = h * 0.62 / float(PLAQUE_FS)
	l.modulate = Color(0.20, 0.13, 0.09)
	l.outline_size = 0
	l.double_sided = false
	l.position = pos + bs * Vector3(0.0, 0.0, 0.26)
	l.rotation.y = yaw
	_root.add_child(l)


func _build_signs() -> void:
	_plaque("关卡入口", Vector3(0.0, TERRACE_H + WALL_H + 4.2, WALL_Z + 2.62), 12.0, 2.6, 120)
	_plaque("商 店", Vector3(-47.1, 9.3, -14.0), 6.0, 2.4, 110, PI * 0.5)
	_plaque("仓 库", Vector3(46.0, 6.2, -14.0), 5.6, 1.5, 96, -PI * 0.5)
	_plaque("中心广场", Vector3(-9.0, 2.6, 27.0), 6.4, 1.9, 100)
	_plaque("修炼场", Vector3(33.0, 5.6, 26.6), 6.0, 2.2, 110)
	for gd: Dictionary in GATES:
		_plaque(str(gd["name"]), Vector3(float(gd["x"]), TERRACE_H + GATE_H + 1.65, WALL_Z + 2.72), 5.6, 1.4, 96)
	if font != null:
		# 农场门匾上的字（匾本身是门的一部分）：朝西那面「灵田农场」
		var l := Label3D.new()
		l.text = "灵田农场"
		l.font = font
		l.font_size = PLAQUE_FS
		l.pixel_size = 0.95 * 0.62 / float(PLAQUE_FS)
		l.modulate = Color(0.24, 0.14, 0.08)
		l.outline_size = 0
		l.double_sided = false
		l.position = FARM_GATE + Vector3(-0.33, Farm.GATE_H + 1.45, 0.0)
		l.rotation.y = -PI * 0.5
		_root.add_child(l)
	# 立在地上的两块（中心广场、修炼场）的柱子
	for p: Vector3 in [Vector3(-11.9, 0.9, 27.0), Vector3(-6.1, 0.9, 27.0), Vector3(30.4, 2.2, 26.6), Vector3(35.6, 2.2, 26.6)]:
		_b(Vector3(0.36, p.y * 2.0, 0.36), p, Color(0.42, 0.27, 0.16))


# ---------- 路人（摆着不动的方块人，整批并成一张网格） ----------

func _build_people() -> void:
	# [x, z, 朝向, 装束, 是不是盘腿坐着]
	var folks := [[-14.0, 14.0, 0.6, 1, false], [-12.2, 15.6, -2.4, 0, false], [14.0, -15.0, 2.2, 2, false], [15.8, -13.6, -0.9, 0, false],
			[-15.0, -13.0, 1.2, 4, false], [-13.2, -14.2, -1.9, 1, false], [-45.6, -18.8, -PI * 0.5, 2, false], [42.6, -12.0, PI * 0.5, 0, false],
			[31.5, 12.0, PI, 1, false], [37.6, 42.0, -PI * 0.5, 4, true], [-18.0, 22.0, 2.8, 0, false], [-41.0, 15.6, 0.0, 1, false]]
	var st := SurfaceTool.new()
	var mat: Material = null
	for f: Array in folks:
		var hero := VoxelHero.new({}, false, false, int(f[3]))
		for i in 8:
			hero.animate(0.1, 0.0, 0.0, false, false)
		if bool(f[4]):
			_sit(hero)
		var base := Transform3D(Basis(Vector3.UP, float(f[2])), Vector3(float(f[0]), ground(float(f[0]), float(f[1])) - (0.42 if bool(f[4]) else 0.0), float(f[1])))
		for c in hero.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == hero.cloth or mi.mesh == null or not mi.visible:
				continue
			var xf := mi.transform
			var p := mi.get_parent()
			while p != null and p != hero:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for si in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, si, base * xf)
			if mat == null:
				mat = mi.get_active_material(0)
		hero.free()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	_root.add_child(node)


## 把一个方块人摆成盘腿打坐：大腿平伸外张、小腿收回来，双手垂在膝上
static func _sit(hero: Node3D) -> void:
	for side: Array in [["leg_l", "shin_l", -1.0], ["leg_r", "shin_r", 1.0]]:
		var leg := hero.get(str(side[0])) as Node3D
		var shin := hero.get(str(side[1])) as Node3D
		if leg != null:
			leg.rotation = Vector3(1.45, 0.0, float(side[2]) * 0.62)
		if shin != null:
			shin.rotation = Vector3(-2.25, 0.0, 0.0)
	for side2: Array in [["arm_l", "fore_l", -1.0], ["arm_r", "fore_r", 1.0]]:
		var arm := hero.get(str(side2[0])) as Node3D
		var fore := hero.get(str(side2[1])) as Node3D
		if arm != null:
			arm.rotation = Vector3(0.55, 0.0, float(side2[2]) * 0.22)
		if fore != null:
			fore.rotation = Vector3(0.75, 0.0, 0.0)


# ---------- 天空和日光 ----------

func _build_env() -> void:
	_env = WorldEnvironment.new()
	var env := BlockWorld.make_environment()
	# 参考图的天：粉紫的晨霞，云多；雾很淡（整座城要看得清清楚楚）
	var sm := env.sky.sky_material as ShaderMaterial
	sm.set_shader_parameter("top_col", Color(0.52, 0.60, 0.94))
	sm.set_shader_parameter("hor_col", Color(1.0, 0.80, 0.88))
	sm.set_shader_parameter("low_col", Color(0.97, 0.84, 0.93))
	sm.set_shader_parameter("glow_col", Color(1.0, 0.92, 0.86))
	sm.set_shader_parameter("clouds", 0.62)
	# 2026-11-21 场景美术专项：换成全景天空盒（读不到图就留着上面这套程序天空）
	var pano := _load_pano()
	if pano != null:
		var pm := ShaderMaterial.new()
		pm.shader = PANO_SHADER
		pm.set_shader_parameter("pano", pano)
		pm.set_shader_parameter("yaw", SKY_YAW)
		env.sky.sky_material = pm
	env.fog_light_color = Color(0.98, 0.84, 0.90)
	env.fog_density = 0.00055
	env.fog_aerial_perspective = 0.6
	env.fog_height = -14.0
	env.fog_height_density = 0.05
	# 2026-11-23 画面专项：环境光从「近白、和日光差不多强」改成淡紫蓝、弱一档，日光更暖 —— 受光面是暖的、影子里是冷紫的，明暗拉得开；
	# 整体曝光收一点（铺地不再发白），饱和度交给调色表按「越灰补得越多」去补（look.gd），这里的全局饱和度降回 1.06
	env.ambient_light_color = Color(0.74, 0.72, 0.96)
	env.ambient_light_energy = 0.5
	env.tonemap_exposure = 0.98
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.08
	_env.environment = env
	_sun = BlockWorld.make_sun()
	_sun.light_color = Color(1.0, 0.90, 0.76)
	_sun.shadow_blur = 2.0
	_root.add_child(Look.petals(36 if mobile else 80))      # 飘的花瓣（只在主城这边）
	_sun.directional_shadow_max_distance = 150.0 if mobile else 280.0
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# 兼容渲染器（网页 / 手机）里带影子的主光是另一套叠法：能量和影子浓度要换算（和 raid_manager.gd 的 COMPAT_SUN_K 同一个数）
		_sun.light_energy *= 0.11
		_sun.shadow_opacity = 1.0 - minf(1.46 * pow(1.0 - 0.86, 2.18), 1.0)


## 全景天空盒的贴图：导入过的走 load；刚拷进来还没导入（命令行跑、没开过编辑器）就直接读图片文件
static func _load_pano() -> Texture2D:
	if ResourceLoader.exists(PANO_PATH):
		var t := load(PANO_PATH) as Texture2D
		if t != null:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(PANO_PATH))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


# ---------- 地面高度和脚下的地板 ----------

## (x, z) 的地面高度（镜头、主角、路人都问它；不算楼和墙这些实心格）。岛外返回很低的数（掉进云海）；水里是池底
func ground(x: float, z: float) -> float:
	if area == "farm" and farm != null:
		return farm.ground(x, z)
	var i := _ci(x)
	var j := _ci(z)
	if not _in(i, j):
		return -60.0
	var h := _h[j * N + i]
	if h < VOID + 1.0:
		return -60.0
	return h - (0.5 if int(_t[j * N + i]) == T_WATER else 0.0)


func _solid_at(x: float, z: float) -> float:
	if area == "farm" and farm != null:
		return farm.solid_at(x, z)
	var i := _ci(x)
	var j := _ci(z)
	var top := _solid[j * N + i] if _in(i, j) else 0.0
	var k := 0
	while k < _fine.size():
		if x >= _fine[k] and x <= _fine[k + 2] and z >= _fine[k + 1] and z <= _fine[k + 3]:
			top = maxf(top, _fine[k + 4])
		k += 5
	return top


## 镜头遮挡用（camera_rig.gd 的 occl_fn，2026-11-21 QA BUG-02）：这一格挡镜头的最高处 = 地面和实心格（楼、墙、石栏）里高的那个
func _cam_block_h(x: float, z: float) -> float:
	return maxf(ground(x, z), _solid_at(x, z))


func _floor_h(x: float, z: float) -> float:
	return ground(x, z)


## 带台阶缓坡的行走高度（和关卡里 meadow_level.gd 的 _walk_h 同一个做法）：邻格比这一格高、又迈得上去的，靠近那条边的最后一段按平滑曲线抬上去
func _walk_h(x: float, z: float, h0: float) -> float:
	var fx := fposmod(x, CELL)
	var fz := fposmod(z, CELL)
	var best := h0
	var ex: Array = [[fx, -1.0], [CELL - fx, 1.0]]
	var ez: Array = [[fz, -1.0], [CELL - fz, 1.0]]
	for a: Array in ex:
		if float(a[0]) < 1.2:
			best = maxf(best, _ramp(x + float(a[1]) * (float(a[0]) + 0.05), z, float(a[0]), h0))
	for b: Array in ez:
		if float(b[0]) < 1.2:
			best = maxf(best, _ramp(x, z + float(b[1]) * (float(b[0]) + 0.05), float(b[0]), h0))
	for a: Array in ex:
		for b: Array in ez:
			var d := Vector2(float(a[0]), float(b[0])).length()
			if d < 1.2:
				best = maxf(best, _ramp(x + float(a[1]) * (float(a[0]) + 0.05), z + float(b[1]) * (float(b[0]) + 0.05), d, h0))
	return best


func _ramp(nx: float, nz: float, d: float, h0: float) -> float:
	if _solid_at(nx, nz) > 0.0:
		return h0
	var up := _floor_h(nx, nz) - h0
	if up < 0.05 or up > STEP_UP:
		return h0
	var w := clampf(0.55 + 0.4 * up, 0.55, 1.2)
	if d >= w:
		return h0
	var t := 1.0 - d / w
	return h0 + up * t * t * (3.0 - 2.0 * t)


func _physics_process(_dt: float) -> void:
	if player == null or not active:
		return
	if meditating:
		_floor.global_position = Vector3(MED_POS.x, MED_POS.y - 1.0, MED_POS.z)
		return
	if Tribulation.running:
		# 渡劫时主角由 tribulation.gd 托在半空：不贴地、不挡，脚下的地板跟着它（落回来时接得住）
		var q := player.global_position
		_floor.global_position = Vector3(q.x, ground(q.x, q.z) - 1.0, q.z)
		_last_xz = Vector2(q.x, q.z)
		return
	var p := player.global_position
	# 实心格（楼、墙、石栏、箱子）：人比它矮就进不去，退回上一步的位置；飞得比它高可以落在顶上
	var sh := _solid_at(p.x, p.z)
	var h := _floor_h(p.x, p.z)
	if sh > 0.0:
		if p.y < sh - 0.35:
			player.global_position.x = _last_xz.x
			player.global_position.z = _last_xz.y
			p = player.global_position
			h = _floor_h(p.x, p.z)
			var sh2 := _solid_at(p.x, p.z)
			if sh2 > 0.0 and p.y >= sh2 - 0.35:
				h = maxf(h, sh2)
		else:
			h = maxf(h, sh)
	elif player.st == Player.St.GROUND and h > -50.0:
		h = _walk_h(p.x, p.z, h)
	if player.st == Player.St.GROUND:
		var rise := h - p.y
		if rise > STEP_UP:
			# 比一步高的坎（石台的侧壁）：走不上去，退回
			player.global_position.x = _last_xz.x
			player.global_position.z = _last_xz.y
			p = player.global_position
			h = maxf(_floor_h(p.x, p.z), p.y - 0.01) if _floor_h(p.x, p.z) - p.y > STEP_UP else _floor_h(p.x, p.z)
		elif rise > 0.02:
			player.global_position.y = h
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
		elif rise < -0.02 and rise >= -STEP_UP and player.velocity.y <= 0.01 and (player.is_on_floor() or rise > -0.6):
			player.global_position.y = h
	p = player.global_position
	_last_xz = Vector2(p.x, p.z)
	_floor.global_position = Vector3(p.x, h - 1.0, p.z)
	if p.y < h - 0.05 and h > -50.0:
		player.global_position.y = h
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	# 掉出岛外：送回入口
	if p.y < -26.0:
		player.force_ground()
		player.global_position = spawn_point()
		player.velocity = Vector3.ZERO
		_last_xz = Vector2(player.global_position.x, player.global_position.z)
		_prev_p = player.global_position
		say("一脚踏空，被云气送回了城门" if area == "town" else "一脚踏空，被云气送回了农场南门")


# ---------- 界面 ----------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 20
	# 底部正中的操作按钮：走到仓库 / 商店 / 阵台跟前才出现
	_use_btn = Button.new()
	_use_btn.theme = th
	_use_btn.custom_minimum_size = Vector2(250, 64)
	_use_btn.focus_mode = Control.FOCUS_NONE
	_use_btn.add_theme_font_size_override("font_size", 24)
	UiStyle.style_primary(_use_btn)
	_use_btn.anchor_left = 0.5
	_use_btn.anchor_right = 0.5
	_use_btn.anchor_top = 1.0
	_use_btn.anchor_bottom = 1.0
	_use_btn.offset_left = -125.0
	_use_btn.offset_right = 125.0
	_use_btn.offset_top = -176.0
	_use_btn.offset_bottom = -112.0
	_use_btn.visible = false
	_use_btn.pressed.connect(use)
	_ui.add_child(_use_btn)
	# 打坐时顶上的一块牌子
	_panel = PanelContainer.new()
	_panel.theme = th
	_panel.add_theme_stylebox_override("panel", UiStyle.plaque(0.96, 1, 12.0))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.offset_top = 86.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_ui.add_child(_panel)
	_panel_lab = Label.new()
	_panel_lab.add_theme_color_override("font_color", UiStyle.TEXT_INK)
	_panel_lab.add_theme_font_size_override("font_size", 22)
	_panel_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_panel_lab)
	# 一行提示（没开的门、掉下去了）
	_toast = Label.new()
	_toast.theme = th
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", UiStyle.TEXT)
	_toast.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.1))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.3
	_toast.anchor_bottom = 0.3
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_ui.add_child(_toast)
	# 穿过农场门的那一下：一层很淡的粉色薄纱，零点几秒散掉（不是黑白闪屏）
	_veil = ColorRect.new()
	_veil.color = Color(1.0, 0.88, 0.95, 0.0)
	_veil.anchor_right = 1.0
	_veil.anchor_bottom = 1.0
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_veil)


## 屏幕中间偏上飘一行字（hold：停多久再淡出）
func say(text: String, hold := 1.6) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## 2026-11-20 数值框架：等雷劫 / 结婴演出、开机黑幕都过去了再飘（演出时主城界面是藏着的，直接 say 看不到）
func _later(text: String, hold := 1.6) -> void:
	_later_txt = text
	_later_hold = hold
	_later_t = 0.9


## 现在站的地方能做什么："" / store（仓库）/ shop（商店，暂时接洞府的坊市页）/ med（修炼场的阵台）
func _zone() -> String:
	if player == null:
		return ""
	var p := player.global_position
	# 2026-11-24 搜打撤 PvP 重构：修炼场不再能打坐 / 渡劫（不返回 "med"，按钮和打坐逻辑都走不到）
	if Vector2(p.x - STORE_POS.x, p.z - STORE_POS.z).length() < USE_R:
		return "store"
	if Vector2(p.x - SHOP_POS.x, p.z - SHOP_POS.z).length() < USE_R:
		return "shop"
	return ""


## 按下操作按钮（或键盘 T）
func use() -> void:
	if not active or _abode_open() or _busy():
		return
	if meditating:
		stop_meditate()
		return
	if area == "farm":
		farm.use(player.global_position)
		return
	match _zone():
		"store":
			open_abode(0)
		"shop":
			open_abode(1)
		"med":
			# 2026-11-20 数值框架：瓶颈 + 破境丹 + 灵石都齐了，阵台上的按钮是「渡劫突破」
			var to := _break_to()
			if to >= 0 and _break_missing(to) == "":
				_start_break()
			else:
				start_meditate()


## 打开洞府界面（abode_ui.gd）：0 储物（仓库）/ 1 坊市 / 2 丹房。
## 走 hud.gd 右上角洞府按钮的同一条路（level_select.gd 的 open_abode：开着的时候游戏暂停，关掉恢复），只是直接翻到指定的那一页
func open_abode(tab: int) -> void:
	if main == null or _abode_open() or _busy():
		return
	var hud: Variant = main.get("hud")
	if not is_instance_valid(hud):
		return
	Input.action_release("move_forward")
	hud.call("_open_abode")
	var ab: Variant = _abode_node()
	if is_instance_valid(ab):
		ab.call("_set_tab", tab)
		_use_btn.visible = false


func _abode_node() -> Variant:
	var ui: Variant = main.get("level_ui") if main != null else null
	return ui.get("_abode") if is_instance_valid(ui) else null


func _abode_open() -> bool:
	return is_instance_valid(_abode_node())


func _unhandled_input(e: InputEvent) -> void:
	if active and not _busy() and e.is_action_pressed("hub_use") and not e.is_echo():
		use()


## 2026-11-20 数值框架：手机切后台 / 切回前台（离开的这段按离线闭关结算），关窗口时记一下最后在线。
## 只在主城里做：局内不存档（局内的东西在结算时才写），也不给离线收益
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_at = Time.get_unix_time_from_system()
			if active:
				Profile.save()        # save 会记下 seen：后台里被系统杀掉，下次开机也按这一刻算
		NOTIFICATION_APPLICATION_RESUMED:
			_paused_at = -1.0      # 2026-11-24：切回前台不再结算离线闭关
		NOTIFICATION_WM_CLOSE_REQUEST:
			if active:
				Profile.save()


# ---------- 打坐 ----------

## 修为到了大境界的瓶颈（这一境界的最后一级、经验已满）——2026-11-20 数值框架：统一看 Prog（按存档里的境界；大乘没有瓶颈）
func at_cap() -> bool:
	return Prog.profile_at_cap()


## 一位小数的修为数（打坐每息不到 1 点）；大了就用「1.234万」那种短写（2026-11-23 起转调 num_fmt.gd 的 fmt1）
func _num1(v: float) -> String:
	return NumFmt.fmt1(v)


## 2026-11-23 照 Hammer：瓶颈时修为照收（突破时结转），存到结转上限（瓶颈那一级 + 一整个下一境界）才真的满了
func _xp_full() -> bool:
	var r := Profile.realm()
	if r >= Prog.REALMS - 1:
		return false
	var cu := Profile.cult(r)
	return int(cu[0]) >= Prog.top_lv(r) and float(cu[1]) >= Prog.overflow_cap(r) - 0.5


## 瓶颈时已经结转了多少（本境界的单位）
func _overflow() -> float:
	var r := Profile.realm()
	var cu := Profile.cult(r)
	return Prog.carry_over(int(cu[0]), float(cu[1]), r)      # 按下一境界的单位（和渡劫成功时的「结转修为 +X」一致）


## 主城里算战力（存档里的境界 / 等级 + 佩戴的法宝）
func _power_now() -> float:
	var r := Profile.realm()
	return CS.power(r, int(Profile.cult(r)[0]), Items.fx_total(Profile.gear()))


func start_meditate() -> void:
	if meditating or player == null:
		return
	meditating = true
	med_gain = 0.0
	_med_t = 0.0
	_med_acc = 0.0
	_med_save = 0.0
	_med_sec = 0.0
	player.force_ground()
	player.velocity = Vector3.ZERO
	player.global_position = MED_POS + Vector3(0.0, 0.26, 0.0)
	player.face_now(PI)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var hero: Node3D = player.hero
	if hero != null:
		hero.call("animate", 0.1, 0.0, 0.0, false, false)
		_hero_y = hero.position.y
		hero.position.y = _hero_y - 0.42
		_sit(hero)
		var cloth: Variant = hero.get("cloth")
		if is_instance_valid(cloth):
			cloth.visible = false
	Sfx.play("ascend", -12.0, 0.8)
	if Prog.profile_at_cap():
		# 2026-11-23：瓶颈时打坐照涨（突破时结转）；没有丹毒了
		var to := _break_to()
		var miss := _break_missing(to) if to >= 0 else ""
		say(("修为已满，先去渡劫" if _xp_full() else "修为已至瓶颈 · 打坐的修为突破后结转") + ("" if miss == "" else " · " + miss))
	else:
		say("闭关打坐 · 每息修为 +%s" % NumFmt.fmt1(Prog.med_rate(Profile.realm())))


func stop_meditate() -> void:
	if not meditating:
		return
	meditating = false
	Profile.save()
	var hero: Node3D = player.hero
	if hero != null:
		hero.position.y = _hero_y
		hero.call("animate", 0.1, 0.0, 0.0, false, false)
		var cloth: Variant = hero.get("cloth")
		if is_instance_valid(cloth):
			cloth.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	_panel.visible = false
	say("出关 · 这次打坐修为 +%s" % _num1(med_gain))


## 修为 +n（兼容旧调用，自检在用）：2026-11-20 数值框架起走 Prog.profile_add_xp——小等级满了自动升；
## 2026-11-23 起到大境界的瓶颈照收（结转），存到结转上限才卡住。存档里的数直接改，不立刻落盘（升了小等级才存）。返回实际涨了多少（取整）
func gain(n: int) -> int:
	var r: Dictionary = Prog.profile_add_xp(float(n))
	if int(r["ups"]) > 0:
		_float_text("修为精进 Lv.%d" % int(r["lv"]), Color(1.0, 0.86, 0.45), 0.7)
		Sfx.play("ascend", -10.0, 1.3)
		Profile.save()
	return roundi(float(r["used"]))


func _float_text(text: String, col: Color, up := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 56
	l.pixel_size = 0.0062
	l.outline_size = 6
	l.modulate = col
	l.outline_modulate = Color(0.06, 0.06, 0.08, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	_root.add_child(l)
	l.global_position = player.global_position + Vector3(randf_range(-0.3, 0.3), 1.45 + up, 0.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.5, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)


## 2026-11-20 数值框架：每帧 Prog.meditate_tick（按境界的速度涨修为、额外消丹毒），每满一秒飘一次这一秒实际涨的数。
## dt 夹在 0.25 秒内：切后台 / 卡顿回来的那一大帧不一次补发（离开得久的交给有上限的离线结算）
func _tick_meditate(dt: float) -> void:
	var d := minf(dt, 0.25)
	_med_t += d
	_med_acc += d
	_med_save += d
	var r := Profile.realm()
	var lv0 := int(Profile.cult(r)[0])
	var got := Prog.meditate_tick(d)
	med_gain += got
	_med_sec += got
	var cu := Profile.cult(r)
	var lv := int(cu[0])
	if lv > lv0:
		_float_text("修为精进 Lv.%d" % lv, Color(1.0, 0.86, 0.45), 0.7)
		# 2026-11-23 照 Hammer 的战力变化反馈：升一级战力 ×1.37（突破那一级 ×2.75）
		var fx := Items.fx_total(Profile.gear())
		_float_text("战力 %s → %s" % [Prog.short_num(CS.power(r, lv0, fx)), Prog.short_num(CS.power(r, lv, fx))], Color(1.0, 0.62, 0.45), 1.3)
		Sfx.play("levelup", -6.0, 1.0)
		Profile.save()
	if _med_acc >= 1.0:
		_med_acc = fmod(_med_acc, 1.0)
		if _med_sec > 0.0:
			_float_text("修为 +%s" % _num1(_med_sec), Color(0.55, 1.0, 0.8))
		_med_sec = 0.0
	if _med_save >= SAVE_EVERY:
		_med_save = 0.0
		Profile.save()
	var hero: Node3D = player.hero
	if hero != null:
		hero.position.y = _hero_y - 0.42 + sin(_med_t * 1.3) * 0.012
	# 顶上的牌子：境界和修为 / 每息多少、这次涨了多少（到瓶颈改成「已满 · 结转 +X」+ 渡劫还缺什么）/ 已坐多久
	# 2026-11-23：没有丹毒 / 药效了；瓶颈时修为照收，第一行写到满格为止，多出的写在第二行
	var line2 := ""
	var need := Prog.xp_need(lv)
	if Prog.profile_at_cap():
		var to := _break_to()
		var miss := _break_missing(to) if to >= 0 else ""
		var warn := _break_pill_warn()
		var ov := _overflow()
		line2 = ("修为已满，先去渡劫" if _xp_full() else (("已满 · 结转 +%s" % Prog.short_num(ov)) if ov >= 0.5 else "修为已至瓶颈")) + " · " \
				+ ("出关后点「渡劫突破」" if miss == "" else miss) + ("" if warn == "" else "\n" + warn)
	else:
		line2 = "每息 +%s　这次 +%s" % [NumFmt.fmt1(Prog.med_rate(r)), _num1(med_gain)]
	var line3 := "已坐 %02d:%02d" % [floori(_med_t / 60.0), int(_med_t) % 60]
	_panel.visible = true
	_panel_lab.text = "闭关中 · %s期　修为 Lv.%d　%s / %s\n%s\n%s" % [Realm.LIST[r]["name"], lv, _num1(minf(float(cu[1]), need)), Prog.short_num(need), line2, line3]
	# 推摇杆 / 按方向键就起身
	if not _busy() and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5:
		stop_meditate()


# ---------- 渡劫突破（2026-11-20 数值框架：修炼场是突破的主要途径） ----------

## 有雷劫 / 结婴演出在播：主城的按钮、牌子、提示都让开，也不接操作
func _busy() -> bool:
	return Tribulation.running or YuanCine.playing != null


## 修为到了瓶颈时要去的境界；不在瓶颈 / 已是大乘返回 -1
func _break_to() -> int:
	var r := Profile.realm()
	if r >= Prog.REALMS - 1 or not Prog.profile_at_cap():
		return -1
	return r + 1


## 存档里（仓库 → 随身 → 储物戒）通往 to 的那颗破境丹：{"key": 哪个列表, "i": 下标}；没有返回 {}
func _find_key(to: int) -> Dictionary:
	for k: String in ["stash", "carry", "ring"]:
		var list: Array = Profile.data()[k]
		for i in list.size():
			var it: Dictionary = list[i]
			if str(it.get("kind", "")) == "key" and int(it.get("to", 0)) == to:
				return {"key": k, "i": i}
	return {}


## 渡劫还缺什么：缺【X丹】/ 灵石不足 N；都齐了返回 ""
func _break_missing(to: int) -> String:
	var miss: Array[String] = []
	if _find_key(to).is_empty():
		miss.append("缺【%s】" % str(Items.KEYS[clampi(to, 0, Items.KEYS.size() - 1)]))
	var cost := Prog.break_cost(to)
	if Profile.lingshi() < cost:
		miss.append("灵石不足 %s" % Prog.short_num(float(cost)))      # 大数短写，和局内提示一致
	return " · ".join(miss)


## 2026-11-23 照 Hammer：本境丹只有正处在那一境界才能服——渡劫前提醒一下仓库 / 随身 / 储物戒里还剩几颗（霸主精魄突破后照样能服，不算）。
## 只是提醒、不拦渡劫（_break_missing 才是拦的）。没有返回 ""
func _break_pill_warn() -> String:
	var r := Profile.realm()
	if r >= Prog.REALMS - 1:
		return ""
	var n := 0
	for k: String in ["stash", "carry", "ring"]:
		for it: Dictionary in (Profile.data().get(k, []) as Array):
			if Items.is_xp_pill(it) and it.has("realm") and not it.has("min_realm") and int(it["realm"]) == r:
				n += 1
	if n <= 0:
		return ""
	return "还有 %d 颗%s期丹，突破后不能再服" % [n, Realm.LIST[r]["name"]]


## 起劫（和 main.gd 的 _gm_breakthrough 大厅那支一样起 tribulation.gd）：先出关、站到阵台正中，扣灵石（失败不退）
func _start_break() -> void:
	var to := _break_to()
	if to < 0 or _busy() or player == null:
		return
	var miss := _break_missing(to)
	if miss != "":
		say(miss)
		return
	if meditating:
		stop_meditate()
	if not Profile.spend(Prog.break_cost(to)):
		return
	player.force_ground()
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(MED_POS.x, ground(MED_POS.x, MED_POS.z) + 0.05, MED_POS.z)
	_last_xz = Vector2(MED_POS.x, MED_POS.z)
	_use_btn.visible = false
	var tb := Tribulation.new()
	tb.player = player
	tb.cam = cam
	tb.realm_to = to
	tb.finished.connect(func(ok: bool, perfect: int, total: int) -> void: _on_break_done(ok, perfect, total, to))
	if main != null:
		main.add_child(tb)
	else:
		add_child(tb)


## 雷劫结束：成功 → 服下破境丹（从它所在的列表拿走）、境界只升不降、等级跳到新境界起点（完美挡下的越多起步修为越多）、
## 换境界、气血回满、存档；失败 → 修为扣掉瓶颈那一级的一半（不低于 0），破境丹留着（灵石起劫时已扣，不退）
## 2026-11-23 照 Hammer：成功时瓶颈那一级之外结转的修为按 Prog.carry_over 换成新境界的单位带过去（和完美奖励一起 add_xp，
## 结转多的可能直接把新境界也灌满 → 提示可以接着渡劫）；失败不再把修为直接改成一半（结转的那部分不白丢）；成功后飘「战力 A → B」
func _on_break_done(ok: bool, perfect: int, total: int, to: int) -> void:
	var r0 := Profile.realm()
	var cu0 := Profile.cult(r0)
	var lv := int(cu0[0])
	var xp0 := float(cu0[1])
	## 2026-11-20 修：成功时才服丹，渡劫中途要是丹没了（开洞府卖掉 / 挪走）就按失败算，不白送一个境界
	var f: Dictionary = _find_key(to) if ok else {}
	if ok and f.is_empty():
		Profile.set_cult(lv, maxf(xp0 - Prog.xp_need(lv) * 0.5, 0.0))
		player.melee.hp = player.melee.HP_MAX
		_later("渡劫失败 · 渡劫时破境丹不在身边，修为退回半级", 2.6)
		return
	if ok:
		var pw0 := _power_now()
		var carry := Prog.carry_over(lv, xp0, r0)      # 按旧境界算、换成新境界的单位
		(Profile.data()[str(f["key"])] as Array).remove_at(int(f["i"]))
		lv = maxi(lv + 1, to * Prog.LV_PER_REALM + 1)
		Profile.data()["realm"] = maxi(r0, to)
		Profile.set_cult(lv, 0.0)
		var bonus := Prog.xp_need(lv) * 0.3 * float(perfect) / maxf(float(total), 1.0)
		Prog.profile_add_xp(carry + bonus)
		Profile.save()
		player.set_realm(to)
		player.melee.hp = player.melee.HP_MAX
		var txt := "渡劫成功 · %s期　完美 %d / %d" % [Realm.LIST[to]["name"], perfect, total]
		if carry >= 0.5:
			txt += "　结转修为 +%s" % Prog.short_num(carry)
		var pw1 := _power_now()
		if pw1 > pw0 + 0.5:
			txt += "\n战力 %s → %s" % [Prog.short_num(pw0), Prog.short_num(pw1)]
		if Prog.profile_at_cap():
			txt += "\n结转的修为已灌满%s期，可以接着渡劫" % Realm.LIST[Profile.realm()]["name"]
		_later(txt, 3.2)
	else:
		Profile.set_cult(lv, maxf(xp0 - Prog.xp_need(lv) * 0.5, 0.0))
		player.melee.hp = player.melee.HP_MAX
		_later("渡劫失败 · 修为退回半级，破境丹还在", 2.6)


## 离线闭关结算（Prog.settle_offline：最多 8 小时、打坐速度的一半、到瓶颈为止，丹毒照闭关的速度消），有收益就飘一行
func _settle_offline(since: float) -> void:
	var res: Dictionary = Prog.settle_offline(since)
	var secs := float(res["secs"])
	var got := float(res["gain"])
	if secs <= 0.0 or got < 0.5:
		return
	var h := floori(secs / 3600.0)
	var mi := floori(fmod(secs, 3600.0) / 60.0)
	var t := ("离线闭关 %d 小时 %d 分" % [h, mi]) if h > 0 else ("离线闭关 %d 分" % mi)
	t += " · 修为 +" + Prog.short_num(got)
	if bool(res["capped"]):
		t += " · 已至瓶颈"
	_later(t, 3.2)


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	_time += dt
	# 地标：紫晶缓缓转、上下浮；小晶片绕着它转；两道符环各转各的
	_crystal.rotation.y = _time * 0.5
	_crystal.position.y = 13.0 + sin(_time * 0.9) * 0.45
	for i in _shards.size():
		var a := _time * 0.8 + TAU * float(i) / float(_shards.size())
		_shards[i].position = Vector3(cos(a) * 5.6, 10.6 + sin(_time * 1.3 + float(i) * 1.7) * 0.9, sin(a) * 5.6)
		_shards[i].rotation.y = -a * 1.5
	for i in _rings.size():
		_rings[i].rotation = Vector3(0.22 * sin(_time * 0.5 + float(i) * 2.0), _time * (0.6 if i == 0 else -0.45), 0.2 * cos(_time * 0.4 + float(i)))
	if player == null:
		return
	if farm != null and area == "farm":
		farm.tick(dt)
	_check_portals()
	if area == "farm":
		# 2026-11-23 灵田：农场里的种植按钮是「整 备」/「播 种」/「收 获」（farm_plots.gd 定）。触屏写在右下的「攻」上，这个底部按钮只给没有触屏按钮的（桌面）
		var fb := _busy() or _abode_open()
		farm.plots.blocked = fb
		var ft := "" if fb else farm.use_text(player.global_position)
		_use_btn.visible = ft != "" and (main == null or main.get("touch") == null)
		if ft != "":
			_use_btn.text = ft
		_ui.visible = not _busy()
		return
	if meditating:
		_tick_meditate(dt)
	# 2026-11-20 数值框架：渡劫 / 结婴演出时整层主城界面藏起来；攒着的一行字等演出、开机黑幕（主角停着处理）过去再飘
	var busy := _busy()
	_ui.visible = not busy
	if _later_txt != "" and not busy and (meditating or player.process_mode != Node.PROCESS_MODE_DISABLED):
		_later_t -= dt
		if _later_t <= 0.0:
			say(_later_txt, _later_hold)
			_later_txt = ""
	# 操作按钮
	var z := "" if busy else _zone()
	var txt := ""
	if meditating:
		txt = "出 关"
	else:
		match z:
			"store":
				txt = "仓 库"
			"shop":
				txt = "商 店"
			"med":
				# 2026-11-20 数值框架：到瓶颈且破境丹、灵石都齐 → 「渡劫突破」；缺东西还是「闭关打坐」，刚站上来时提示缺什么
				txt = "闭关打坐"
				var to := _break_to()
				if to >= 0:
					var miss := _break_missing(to)
					if miss == "":
						txt = "渡劫突破"
					if _zone_was != "med":
						var warn := _break_pill_warn()      # 2026-11-23：本境丹突破后不能再服，提醒一下（不拦）
						if miss == "":
							say("修为已至瓶颈 · 渡%s要扣灵石 %s，失败不退" % [str(Tribulation.NAMES[to]), Prog.short_num(float(Prog.break_cost(to)))]
									+ ("" if warn == "" else "\n" + warn), 2.4)
						else:
							say("修为已至瓶颈 · " + miss + ("" if warn == "" else "\n" + warn), 2.4)
	_zone_was = z
	_use_what = txt
	_use_btn.visible = txt != ""
	if txt != "":
		_use_btn.text = txt
	# 拱门：走到门洞跟前（石台上、贴着墙）触发；触发过一次要先走开
	_toast_cd -= dt
	var p := player.global_position
	var at := -1
	if p.z < WALL_Z + 5.2 and p.z > WALL_Z + 0.5 and p.y > TERRACE_H - 0.6 and p.y < TERRACE_H + GATE_H:
		for gi in GATES.size():
			if absf(p.x - float(GATES[gi]["x"])) < GATE_W * 0.5 - 0.6:
				at = gi
	if at < 0:
		if p.z > WALL_Z + 7.5 or p.y < TERRACE_H - 1.0:
			_gate_armed = true
	elif not meditating and not busy:
		if not bool(GATES[at]["open"]):
			if _toast_cd <= 0.0:
				_toast_cd = 2.5
				say("此门尚未开启")
		elif _gate_armed:
			_gate_armed = false
			gate_entered.emit(at)


# ---------- 灵田农场（2026-11-21 场景美术专项） ----------

## 建农场和两道透视门（_ready 里、主城自己建完以后调）
func _build_farm() -> void:
	farm = Farm.new()
	farm.name = "Farm"
	farm.bw = _bw
	farm.font = font
	farm.mobile = mobile
	add_child(farm)
	farm.plots.say = say
	farm.plots.main = main
	var attrs: CameraAttributes = cam.cam.attributes if cam != null else null
	var k := 0.45 if mobile else 0.55
	# 门里的日光不投影子：兼容渲染器（网页 / 手机）里带影子的主光亮度被乘了 0.11（见 _build_env），不带影子的要用原来的亮度
	var se := _sun.light_energy / 0.11 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else _sun.light_energy
	_portal_town = Portal.new()
	_portal_town.name = "FarmGatePortal"
	_portal_town.frame = Transform3D(Basis(Vector3.UP, -PI * 0.5), FARM_GATE)
	_portal_town.dest = Farm.gate_in()
	_portal_town.width = Farm.GATE_W
	_portal_town.height = Farm.GATE_H
	_portal_town.scale_k = k
	_portal_town.sun_energy = se
	add_child(_portal_town)
	_portal_town.build([farm.root], _env.environment, _sun, attrs)
	_portal_farm = Portal.new()
	_portal_farm.name = "FarmBackPortal"
	_portal_farm.frame = Transform3D(Basis(Vector3.UP, PI), Farm.gate_in().origin)
	_portal_farm.dest = Transform3D(Basis(Vector3.UP, PI * 0.5), FARM_GATE)
	_portal_farm.width = Farm.GATE_W
	_portal_farm.height = Farm.GATE_H
	_portal_farm.scale_k = k
	_portal_farm.sun_energy = se
	_portal_farm.col_a = Color(0.78, 0.70, 1.0)
	_portal_farm.col_b = Color(1.0, 0.86, 0.66)
	add_child(_portal_farm)
	_portal_farm.build([_root], _env.environment, _sun, attrs)


## 按 area 开关两边看得见的东西和两道门
func _apply_area() -> void:
	if farm == null:
		return
	var in_farm := active and area == "farm"
	if farm.plots != null and farm.plots.on != in_farm:
		farm.plots.set_on(in_farm)
	_root.visible = active and not in_farm
	farm.root.visible = in_farm
	_portal_town.on = active and not in_farm
	_portal_farm.on = in_farm
	if active and not _primed:
		# 第一次开主城：两道门都先用固定机位画几帧（载入幕布后面把门里那套不带影子的光照、农场和主城副本的着色器编掉）
		_primed = true
		_portal_town.prime(4)
		_portal_farm.prime(4)


## 每帧：主角从门的正面穿过门洞 → 搬到对面
func _check_portals() -> void:
	if farm == null or not active:
		return
	var pp := player.global_position
	var moved := pp.distance_to(_prev_p)
	if moved < 12.0 and not meditating and not _busy() and not _abode_open() and not player.dead:
		if area == "town" and _portal_town.crossed(_prev_p, pp):
			_through(_portal_town, "farm")
		elif area == "farm" and _portal_farm.crossed(_prev_p, pp):
			_through(_portal_farm, "town")
	_prev_p = player.global_position


## 穿门：主角（位置、速度、朝向）和镜头（朝向）整体按门对门的变换搬过去 —— 门里画的就是搬过去以后看到的，所以接得上
func _through(p: Portal, to: String) -> void:
	var t := p.xfer()
	var dy := p.xfer_yaw()
	player.global_position = t * player.global_position
	player.velocity = t.basis * player.velocity
	player.face_now(float(player.get("_facing")) + dy)
	if cam != null:
		cam.snap(cam.yaw + dy, cam.pitch, cam.zoom)
	var q := player.global_position
	_last_xz = Vector2(q.x, q.z)
	_prev_p = q
	if main != null:
		var sw: Variant = main.get("swords")
		if is_instance_valid(sw):
			sw.call("dismiss_all")
	area = to
	_apply_area()
	_floor.global_position = Vector3(q.x, ground(q.x, q.z) - 1.0, q.z)
	_veil.color.a = 0.42
	var tw := _veil.create_tween()
	tw.tween_property(_veil, "color:a", 0.0, 0.55).set_ease(Tween.EASE_OUT)
	Sfx.play("ascend", -14.0, 1.25)
	if to == "farm":
		var rc := farm.plots.ripe_count() if farm.plots != null else 0
		say("灵田农场 · 左边灵宠区（预留），右边种植区" + ("　灵田里有 %d 株可以收了" % rc if rc > 0 else ""), 2.4)
	else:
		say("回到主城", 1.4)


# ---------- 自检 ----------

## `-- --hub-shot [--touch]`（main.gd 开机后调）：拍几张定妆图（_shots/hub_*.png），再把几样功能走一遍：
##   四道门（开着的两道各触发一次、没开的只提示）、仓库 / 坊市按钮、打坐 6 秒涨了多少修为、走进实心的楼会不会被挡住。
func selftest() -> void:
	if OS.get_cmdline_user_args().has("--farm-shot"):
		await farm_selftest()
		return
	if OS.get_cmdline_user_args().has("--farm-plant"):
		await farm_plant_selftest()
		return
	for la: String in OS.get_cmdline_user_args():
		if la.begins_with("--lan-test="):
			# 局域网在场的双开自检（lan_selftest.gd）
			await (load("res://scripts/lan_selftest.gd") as GDScript).call("run", self, la.get_slice("=", 1))
			return
	if OS.get_cmdline_user_args().has("--arena-duel"):
		# 擂台对决的自检（arena_selftest.gd；用 load：写坏了不连累主城）
		await (load("res://scripts/arena_selftest.gd") as GDScript).call("run", self)
		return
	var tree := get_tree()
	var shot := func(tag: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/hub_%s.png" % tag))
	var wait := func(sec: float) -> void:
		await tree.create_timer(sec).timeout
	await wait.call(1.5)
	# 定妆：照参考图的机位（从南面高处俯瞰全城），再各处近景
	var views := [["0_overview", Vector3(0.0, 88.0, 132.0), Vector3(0.0, 0.0, -6.0), 52.0], ["1_plaza", Vector3(10.0, 12.0, 46.0), Vector3(0.0, 8.0, -10.0), 62.0],
			["2_gates", Vector3(0.0, 12.0, -14.0), Vector3(0.0, 11.0, -58.0), 80.0], ["3_shop", Vector3(-18.0, 8.0, 6.0), Vector3(-48.0, 4.0, -13.0), 60.0],
			["4_store", Vector3(20.0, 8.0, 8.0), Vector3(48.0, 4.0, -13.0), 60.0], ["5_yard", Vector3(26.0, 10.0, 62.0), Vector3(46.0, 2.0, 40.0), 60.0],
			["6_pond", Vector3(-12.0, 9.0, 62.0), Vector3(-40.0, 0.0, 42.0), 60.0], ["7_spawn", Vector3(0.0, 4.0, 90.0), Vector3(0.0, 6.0, 0.0), 62.0]]
	var shots_n := 0
	for v: Array in views:
		cam.cine_xf = Transform3D(Basis.looking_at((v[2] as Vector3) - (v[1] as Vector3), Vector3.UP), v[1])
		cam.cine_fov = float(v[3])
		cam.cine_k = 1.0
		await wait.call(0.5)
		await shot.call(str(v[0]))
		shots_n += 1
	cam.cine_k = 0.0
	print("[hub] 定妆图 %d 张；绘制调用 %d，图元 %dk；地面顶点 %d，建筑点缀顶点 %d" % [shots_n, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), (_g[0] as PackedVector3Array).size(), (_a[0] as PackedVector3Array).size()])
	# 门
	var fired: Array = []
	var on_gate := func(i: int) -> void:
		fired.append(i)
	var held: Array = gate_entered.get_connections()      # main.gd 接的那个先摘掉（不然真的开了选关界面）
	for c: Dictionary in held:
		gate_entered.disconnect(c["callable"])
	gate_entered.connect(on_gate)
	for gi in GATES.size():
		player.global_position = Vector3(float(GATES[gi]["x"]), TERRACE_H + 0.1, WALL_Z + 12.0)
		await wait.call(0.3)
		player.global_position = Vector3(float(GATES[gi]["x"]), TERRACE_H + 0.1, WALL_Z + 3.0)
		await wait.call(0.5)
	gate_entered.disconnect(on_gate)
	for c: Dictionary in held:
		gate_entered.connect(c["callable"])
	print("[hub] 四道门挨个走到门洞前：触发了 %s（应为 [0, 1, 2, 3]：2026-11-24 起门 2 / 3 开成新图）" % str(fired))
	# 仓库 / 坊市
	var res: Array = []
	for z: Array in [[STORE_POS, "仓 库"], [SHOP_POS, "商 店"]]:
		player.global_position = (z[0] as Vector3) + Vector3(0.0, 0.1, 2.0)
		await wait.call(0.4)
		var seen := _use_btn.visible and _use_btn.text == str(z[1])
		use()
		await wait.call(0.5)
		var ab: Variant = _abode_node()
		var opened := is_instance_valid(ab)
		var tab := int(ab.get("_tab")) if opened else -1
		var paused := tree.paused
		await shot.call("8_store_ui" if z[1] == "仓 库" else "8_shop_ui")
		if opened:
			ab.call("_close")
		await wait.call(0.4)
		res.append("%s：按钮出现=%s 打开=%s 页签 %d 开着时暂停=%s 关掉后恢复=%s" % [z[1], seen, opened, tab, paused, not tree.paused])
	print("[hub] " + "；".join(res))
	# 打坐
	player.set_realm(0, false)
	Profile.set_cult(1, 0.0)
	player.global_position = MED_POS + Vector3(1.0, 0.3, 1.0)
	await wait.call(0.4)
	var b_seen := _use_btn.visible and _use_btn.text == "闭关打坐"
	use()
	await wait.call(1.0)
	cam.cine_xf = Transform3D(Basis.looking_at(MED_POS + Vector3(0, 0.9, 0) - (MED_POS + Vector3(-1.6, 2.2, 5.0)), Vector3.UP), MED_POS + Vector3(-1.6, 2.2, 5.0))
	cam.cine_fov = 55.0
	cam.cine_k = 1.0
	await wait.call(5.6)
	await shot.call("9_meditate")
	cam.cine_k = 0.0
	var cu := Profile.cult(0)
	var sitting := meditating
	use()
	await wait.call(0.3)
	# 2026-11-20 数值框架：每息 +Prog.med_rate(炼气)（2026-11-20 晚起 0.36），坐 6.6 秒约 +2.4
	print("[hub] 打坐：按钮出现=%s 坐下=%s 6.6 秒后修为 Lv.%d %.1f / %.0f（这次 +%.1f，应为 %.1f 上下：每息 +%.2f）；出关后主角恢复=%s" % [b_seen, sitting, int(cu[0]),
			float(cu[1]), Prog.xp_need(int(cu[0])), med_gain, Prog.med_rate(0) * 6.6, Prog.med_rate(0), player.process_mode == Node.PROCESS_MODE_INHERIT and not meditating])
	# 瓶颈：2026-11-23 照 Hammer 修为照收（突破时结转），存到结转上限（瓶颈那一级 + 一整个筑基）才不再涨
	Profile.set_cult(3, Prog.xp_need(3))
	var g_cap := gain(5)
	Profile.set_cult(3, Prog.overflow_cap(0))
	var g_full := gain(5)
	Profile.set_cult(3, Prog.xp_need(3))
	print("[hub] 瓶颈时再涨 5 点：实际涨了 %d（应为 5：照收、突破后结转）；存到结转上限后再涨 5 点：%d（应为 0）" % [g_cap, g_full])
	# 瓶颈时站上阵台：缺破境丹 → 按钮还是「闭关打坐」；仓库里放一颗筑基丹、灵石补够 → 「渡劫突破」（只看按钮，不真的起劫）
	player.global_position = MED_POS + Vector3(1.0, 0.3, 1.0)
	await wait.call(0.3)
	var t_miss := _use_btn.text
	var ls0 := Profile.lingshi()
	Profile.stash().append(Items.key(1))
	Profile.data()["lingshi"] = maxi(ls0, Prog.break_cost(1))
	await wait.call(0.3)
	var t_ok := _use_btn.text
	print("[hub] 瓶颈时站上阵台：没有筑基丹时按钮「%s」（应为 闭关打坐）；有筑基丹、灵石 %d 时「%s」（应为 渡劫突破）" % [t_miss, Prog.break_cost(1), t_ok])
	# 2026-11-20 数值框架（总控补的）：真的起一次劫（自动点满），看扣灵石、服破境丹、境界存档、等级跳到筑基起点
	var ls1 := Profile.lingshi()
	var keys0 := Profile.count("筑基丹")
	use()
	await wait.call(0.5)
	var tb: Node = null
	var tb_host: Node = main if main != null else self
	for c: Node in tb_host.get_children():
		if c is Tribulation:
			tb = c
	var ls2 := Profile.lingshi()
	var tb_on := tb != null       # 结束后节点会被释放，先记下
	if tb_on:
		tb.set("demo_auto", 1.0)
	var tt := 0.0
	while Tribulation.running and tt < 40.0:
		await wait.call(0.5)
		tt += 0.5
	await wait.call(1.2)
	var cu_b := Profile.cult(Profile.realm())
	print("[hub] 修炼场渡劫：起劫=%s 灵石 %d → %d（应少 %d）用时 %.1fs 存档境界 %d（应为 1）主角境界 %d 筑基丹 %d → %d 颗 修为 Lv.%d %.0f（应为 Lv.4）界面恢复=%s" % [
			tb_on, ls1, ls2, Prog.break_cost(1), tt, Profile.realm(), int(player.realm_idx), keys0, Profile.count("筑基丹"), int(cu_b[0]), float(cu_b[1]),
			_ui.visible])
	# 还原：境界回炼气、灵石和破境丹还原，后面的测试照旧
	for i in range(Profile.stash().size() - 1, -1, -1):
		if str(Profile.stash()[i].get("kind", "")) == "key":
			Profile.stash().remove_at(i)
	Profile.data()["lingshi"] = ls0
	Profile.data()["realm"] = 0
	player.set_realm(0, false)
	Profile.set_cult(1, 0.0)
	# 实心：从广场往商店主楼里走 3 秒
	player.global_position = Vector3(-38.0, 0.1, -12.0)
	cam.snap(PI * 0.5, -0.2, 6.5)
	await wait.call(0.3)
	Input.action_press("move_forward")
	await wait.call(3.0)
	Input.action_release("move_forward")
	print("[hub] 朝商店主楼里走 3 秒：停在 x=%.1f（楼的墙在 -45，应该进不去）" % player.global_position.x)
	# 掉出岛外
	player.global_position = Vector3(0.0, 5.0, 112.0)      # 2026-11-23 原来放在 (100, 5, 0)：现在那里是东擂台，改到进城石道南头外面
	await wait.call(4.0)
	print("[hub] 走出岛外 4 秒后：位置 %s（应该被送回入口 %s）" % [str(player.global_position.round()), str(SPAWN)])
	# 2026-11-23 两侧的擂台：从石路走上红毯石阶到台面；台面上往北走被石栏挡住；台面中心的归属
	player.global_position = Vector3(-(Arena.CX - Arena.R - 2.0 * float(Arena.STEPS)) + 4.0, 0.1, Arena.CZ)
	cam.snap(PI * 0.5, -0.2, 6.5)
	await wait.call(0.3)
	Input.action_press("move_forward")
	await wait.call(4.0)
	Input.action_release("move_forward")
	var up_p := player.global_position
	player.global_position = Vector3(-Arena.CX, Arena.H + 0.1, Arena.CZ - 20.0)
	cam.snap(0.0, -0.2, 6.5)
	await wait.call(0.3)
	Input.action_press("move_forward")
	await wait.call(3.0)
	Input.action_release("move_forward")
	print("[hub] 擂台：从石路往西走 4 秒 → (%.1f, %.2f)（应该上了台：x < %.0f、高 %.1f）；台面上往北走 3 秒停在 z=%.1f（石栏在 %.1f 一带，应该出不去）；中心算哪座 %d / %d（应为 0 / 1）；台面对边 %.0f 米" % [
			up_p.x, up_p.y, -Arena.CX + Arena.R, Arena.H, player.global_position.z, Arena.CZ - Arena.RP, Arena.arena_at(-Arena.CX, Arena.CZ), Arena.arena_at(Arena.CX, Arena.CZ), Arena.R * 2.0])
	await shot.call("a_arena")
	# 真实的进出流程（main.gd 接的那几个）：试剑台往返 → 木兰草原那道门开选关界面 → 进关卡再撤回来
	var m: Node = main
	var hold := func(cond: Callable, sec: float) -> bool:
		var t := 0.0
		while t < sec:
			if bool(cond.call()):
				return true
			await tree.create_timer(0.1).timeout
			t += 0.1
		return bool(cond.call())
	player.global_position = Vector3(float(GATES[1]["x"]), TERRACE_H + 0.1, WALL_Z + 12.0)
	await wait.call(0.4)
	player.global_position = Vector3(float(GATES[1]["x"]), TERRACE_H + 0.1, WALL_Z + 3.0)
	await wait.call(1.8)
	var hall_on := not active and bool((m.get("_hall_root") as Node3D).visible)
	var hp: Node3D = m.get("hall_portal")
	var back := false
	if hall_on and hp != null:
		await shot.call("10_test_hall")
		player.global_position = Vector3(hp.global_position.x, 0.1, hp.global_position.z)
		await wait.call(1.8)
		back = active and player.global_position.distance_to(return_point(1)) < 3.0
	print("[hub] 走进「试剑台」的门：到了老大厅=%s；再走进老大厅那扇「回主城」的门：回到主城=%s（落在试剑台门前）" % [hall_on, back])
	player.global_position = Vector3(float(GATES[0]["x"]), TERRACE_H + 0.1, WALL_Z + 12.0)
	await wait.call(0.4)
	player.global_position = Vector3(float(GATES[0]["x"]), TERRACE_H + 0.1, WALL_Z + 3.0)
	await wait.call(0.8)
	var ui: Variant = m.get("level_ui")
	var sel := bool(ui.is_open())
	await shot.call("11_level_select")
	ui.close()
	await wait.call(0.4)
	m.call("_enter_level", "meadow")
	var entered: bool = await hold.call(func() -> bool: return m.get("level") != null and not bool(m.get("_switching")), 90.0)
	var hub_off := not active and not _root.visible
	await wait.call(1.0)
	m.call("_return_to_hall")
	var home: bool = await hold.call(func() -> bool: return m.get("level") == null and not bool(m.get("_switching")), 30.0)
	await wait.call(0.6)
	print("[hub] 走进「木兰草原」的门：选关界面打开=%s；进关卡=%s（进去后主城关着=%s）；撤回来=%s 主城开着=%s 落点离木兰草原门前 %.1f 米" % [sel, entered, hub_off, home, active,
			player.global_position.distance_to(return_point(0))])
	await shot.call("12_back_home")


## `-- --hub-shot --farm-shot [--touch]`（2026-11-21 场景美术专项）：天空盒各方向 / 接缝、农场门和门里的画面（和真走过去拍的对比）、
## 穿门进出、农场里各处定妆和碰撞通行（石阶、殿、篱笆、木桥、草坪、莲池、掉出岛）、帧耗时。截图存 _shots/farm_*.png（手机档加 m_ 前缀）
func farm_selftest() -> void:
	var tree := get_tree()
	var tag := "m_" if mobile else ""
	var shot := func(nm: String) -> Image:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://_shots/farm_%s%s.png" % [tag, nm]))
		return img
	var wait := func(sec: float) -> void:
		await tree.create_timer(sec).timeout
	var view := func(eye: Vector3, at: Vector3, fov: float) -> void:
		cam.cine_xf = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
		cam.cine_fov = fov
		cam.cine_k = 1.0
	var go := func(pos: Vector3, yaw: float) -> void:
		player.force_ground()
		player.global_position = pos
		player.velocity = Vector3.ZERO
		player.face_now(yaw)
		cam.cine_k = 0.0
		cam.snap(yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
		_last_xz = Vector2(pos.x, pos.z)
		_prev_p = pos
	var walk := func(sec: float, until: Callable) -> float:
		Input.action_press("move_forward")
		var t := 0.0
		while t < sec:
			await tree.process_frame
			t += get_process_delta_time()
			if until.is_valid() and bool(until.call()):
				break
		Input.action_release("move_forward")
		return t
	var O := Farm.ORIGIN
	await wait.call(1.5)
	print("[farm] 农场：地面 / 建筑 / 水面网格已建；门里副本 主城门 %d 个节点、农场南门 %d 个节点；灵宠区草坪上立着的杂物顶点 %d（应为 0）、岛沿花树伸到草坪上空的树冠顶点 %d" % [
			_portal_town.copies(), _portal_farm.copies(), int(farm.pet_clutter()[0]), int(farm.pet_clutter()[1])])
	# ---- 1 天空盒：主城里平视四方、接缝方向平视 / 仰视、天顶 ----
	var seam := PI - SKY_YAW
	var eye := Vector3(0.0, 14.0, 30.0)
	for d: Array in [["sky_n", 0.0, 0.08], ["sky_e", -PI * 0.5, 0.08], ["sky_s", PI, 0.08], ["sky_w", PI * 0.5, 0.08], ["sky_seam", seam, 0.08],
			["sky_seam_up", seam, 0.6], ["sky_zenith", seam + 0.4, 1.45], ["sky_sun", -SKY_YAW, 0.04]]:
		var bs := Basis(Vector3.UP, float(d[1])) * Basis(Vector3.RIGHT, float(d[2]))
		view.call(eye, eye + bs * Vector3.FORWARD * 10.0, 70.0)
		await wait.call(0.35)
		await shot.call(str(d[0]))
	# ---- 2 主城全景、农场门（远 / 近 / 斜）----
	view.call(Vector3(0.0, 88.0, 132.0), Vector3(0.0, 0.0, -6.0), 52.0)
	await wait.call(0.5)
	await shot.call("hub_overview")
	var gate_views := [["gate_far", Vector3(6.0, 11.0, 34.0), Vector3(58.0, 4.0, 16.0), 62.0], ["gate_near", Vector3(36.0, 5.5, 16.5), Vector3(58.0, 3.6, 16.0), 62.0],
			["gate_oblique", Vector3(44.0, 4.0, 3.0), Vector3(58.0, 3.6, 16.0), 62.0]]
	var diffs: Array = []
	for g: Array in gate_views:
		view.call(g[1], g[2], float(g[3]))
		await wait.call(0.6)
		var img_a: Image = await shot.call(str(g[0]))
		# 量门里的画面：先拍一张不带门外特效的（花瓣 / 溢光不算）、再拍一张连门面片也藏起来的 —— 两张不一样的地方就是门洞
		_portal_town.set_fx_visible(false)
		await wait.call(0.15)
		var img_p: Image = await shot.call(str(g[0]) + "_nofx")
		_portal_town.set_view_visible(false)
		await wait.call(0.15)
		var img_c: Image = await shot.call(str(g[0]) + "_hole")
		_portal_town.set_view_visible(true)
		_portal_town.set_fx_visible(true)
		# 门里画面对不对：同一个镜头按门对门的变换搬到农场那边（真走过去），拍一张比门洞里那块
		var cxf: Transform3D = cam.cam.global_transform
		var t := _portal_town.xfer()
		player.process_mode = Node.PROCESS_MODE_DISABLED       # 主角还站在主城：先定住，别按农场的地面往下掉
		area = "farm"
		_apply_area()
		cam.cine_xf = t * cam.cine_xf
		await wait.call(0.5)
		var img_b: Image = await shot.call(str(g[0]) + "_truth")
		area = "town"
		_apply_area()
		player.process_mode = Node.PROCESS_MODE_INHERIT
		cam.cine_xf = Transform3D(Basis.looking_at((g[2] as Vector3) - (g[1] as Vector3), Vector3.UP), g[1])
		await wait.call(0.3)
		var md: Array = _masked_diff(img_p, img_c, img_b)
		diffs.append("%s 门洞 %d 个采样点、平均色差 %.1f / 255（门洞里画的 vs 主城原本门后那块：%.1f）" % [g[0], int(md[0]), float(md[1]), float(md[2])])
		if cxf.origin.distance_to(cam.cam.global_transform.origin) > 0.5:
			diffs.append("（镜头没回原位）")
	print("[farm] 门里的画面 vs 真走过去拍的：" + "；".join(diffs))
	# ---- 3 穿门：从门前往门里走 ----
	go.call(_portal_town.front(7.0), -PI * 0.5)
	await wait.call(0.8)
	await shot.call("walk_0_before")
	var draws0 := int(_portal_town.drawn())
	var tw: float = await walk.call(4.0, func() -> bool: return area == "farm")
	var arrived := area == "farm"
	await wait.call(0.15)
	await shot.call("walk_1_just_in")
	await wait.call(0.9)
	await shot.call("walk_2_arrived")
	var lp := Farm.gate_in().affine_inverse() * player.global_position
	print("[farm] 穿门进农场：用时 %.1fs 进了=%s 落点在南门里 %.1f 米（横偏 %.1f）脚下高 %.2f 镜头朝向 %.2f（应约 0 = 朝北）门里画面画过 %d 帧" % [
			tw, arrived, -lp.z, lp.x, player.global_position.y - O.y, wrapf(cam.yaw, -PI, PI), int(_portal_town.drawn()) - draws0])
	# ---- 4 农场定妆 ----
	var farm_views := [["overview", Vector3(0.0, 70.0, 94.0), Vector3(0.0, -2.0, -6.0), 50.0], ["overview2", Vector3(0.0, 46.0, 84.0), Vector3(0.0, 0.0, -14.0), 62.0],
			["pet_lawn", Vector3(-30.0, 18.0, 52.0), Vector3(-33.0, 0.0, 6.0), 62.0], ["fields", Vector3(10.0, 13.0, 44.0), Vector3(36.0, 0.0, 2.0), 62.0],
			["hall", Vector3(0.0, 9.0, 2.0), Vector3(0.0, 6.0, -44.0), 60.0], ["wheel", Vector3(34.0, 6.0, -8.0), Vector3(47.0, 2.0, -22.0), 58.0],
			["back_gate", Vector3(0.0, 5.0, 22.0), Vector3(0.0, 4.0, 40.0), 62.0], ["plaza", Vector3(12.0, 7.0, 6.0), Vector3(0.0, 0.0, -12.0), 62.0]]
	for v: Array in farm_views:
		view.call(O + (v[1] as Vector3), O + (v[2] as Vector3), float(v[3]))
		await wait.call(0.55)
		await shot.call("f_" + str(v[0]))
	cam.cine_k = 0.0
	# ---- 5 农场里走一走：石阶、殿、篱笆、木桥、草坪、莲池、掉出岛 ----
	var res: Array = []
	go.call(O + Vector3(0.0, 0.1, -14.0), 0.0)
	await wait.call(0.3)
	await walk.call(3.2, Callable())
	var on_top := player.global_position.y - O.y
	res.append("走上石阶：高 %.2f（石台 %.1f）z=%.1f" % [on_top, Farm.TERRACE_H, player.global_position.z - O.z])
	await walk.call(3.0, Callable())
	res.append("接着往殿里走：停在 z=%.1f（殿前沿约 -40，应进不去）" % (player.global_position.z - O.z))
	go.call(O + Vector3(6.6, 0.1, 20.0), -PI * 0.5)
	await wait.call(0.3)
	await walk.call(2.0, Callable())
	res.append("朝篱笆走：停在 x=%.1f（篱笆在 9，应过不去）" % (player.global_position.x - O.x))
	go.call(O + Vector3(6.6, 0.1, 1.0), -PI * 0.5)
	await wait.call(0.3)
	await walk.call(2.4, Callable())
	res.append("从篱笆口过木桥进菜地：到 x=%.1f 高 %.2f（应 > 13、站在桥 / 地上）" % [player.global_position.x - O.x, player.global_position.y - O.y])
	go.call(O + Vector3(-10.0, 0.1, 10.0), PI * 0.5)
	await wait.call(0.3)
	var x0 := player.global_position.x
	await walk.call(3.5, Callable())
	res.append("草坪上往西走 3.5 秒：走了 %.1f 米、所在分区 %s（一路没被挡）" % [x0 - player.global_position.x, farm.zone_of(player.global_position)])
	go.call(O + Vector3(-12.0, 0.1, -18.0), 0.0)
	await wait.call(0.3)
	await walk.call(1.6, Callable())
	res.append("走进莲池：脚下高 %.2f（水里应约 -1.1）" % (player.global_position.y - O.y))
	go.call(O + Vector3(-90.0, 5.0, 0.0), 0.0)
	await wait.call(4.0)
	res.append("走出岛外 4 秒后：离农场出生点 %.1f 米（应送回）" % player.global_position.distance_to(farm.spawn_point()))
	print("[farm] " + "；".join(res))
	# ---- 6 帧耗时：主城看着门 / 背对门、农场里 ----
	var perf := []
	go.call(_portal_town.front(14.0), -PI * 0.5)
	area = "town"
	_apply_area()
	go.call(_portal_town.front(14.0), -PI * 0.5)
	await wait.call(1.0)
	perf.append("主城看着门 " + await _perf_probe(2.0))
	await shot.call("perf_town_gate")
	# 同一个机位、同一个进程里交替开 / 关门里的画面，量它自己的开销（这台机器的显卡常被别的窗口占着，跨进程比不准）
	var ab: Array = []
	for k in 4:
		_portal_town.on = k % 2 == 1
		await wait.call(0.4)
		ab.append(("开" if k % 2 == 1 else "关") + " " + await _perf_probe(1.5))
	_portal_town.on = true
	perf.append("同机位门里画面 关 / 开 交替：" + " | ".join(ab))
	go.call(_portal_town.front(14.0), PI * 0.5)
	await wait.call(1.0)
	perf.append("主城背对门 " + await _perf_probe(2.0))
	go.call(O + Vector3(0.0, 0.1, 30.0), 0.0)
	area = "farm"
	_apply_area()
	go.call(O + Vector3(0.0, 0.1, 30.0), 0.0)
	await wait.call(1.0)
	perf.append("农场里朝北 " + await _perf_probe(2.0))
	go.call(O + Vector3(0.0, 0.1, 22.0), PI)
	await wait.call(1.0)
	perf.append("农场里看着南门（门里画主城）" + await _perf_probe(2.0))
	await shot.call("perf_farm_gate")
	print("[farm] 帧耗时：" + "；".join(perf))
	# ---- 7 从南门走回主城 ----
	go.call(O + Vector3(0.0, 0.1, 33.0), PI)
	await wait.call(0.5)
	var tb: float = await walk.call(4.0, func() -> bool: return area == "town")
	await wait.call(0.8)
	await shot.call("back_in_town")
	print("[farm] 从南门走回主城：用时 %.1fs 回到主城=%s 离主城农场门 %.1f 米、在门的西面=%s 镜头朝向 %.2f（应约 1.57 = 朝西）" % [tb, area == "town",
			Vector2(player.global_position.x - FARM_GATE.x, player.global_position.z - FARM_GATE.z).length(), player.global_position.x < FARM_GATE.x, wrapf(cam.yaw, -PI, PI)])


## 门里画面对不对：mask = 门面片藏起来前后不一样的像素（就是门洞），往里收几个像素（避开四周的流光）；
## 返回 [采样点数, 门洞里 a 和 truth 的平均色差, 门洞里 a 和 hole（门后原本的主城）的平均色差 —— 对照：不对的话大概这么大]
static func _masked_diff(a: Image, hole: Image, truth: Image) -> Array:
	var w := a.get_width()
	var h := a.get_height()
	var m := 12
	var n := 0
	var s_t := 0.0
	var s_h := 0.0
	for y in range(m, h - m, 3):
		for x in range(m, w - m, 3):
			var ok := true
			for o: Vector2i in [Vector2i(0, 0), Vector2i(m, 0), Vector2i(-m, 0), Vector2i(0, m), Vector2i(0, -m)]:
				var c1 := a.get_pixel(x + o.x, y + o.y)
				var c2 := hole.get_pixel(x + o.x, y + o.y)
				if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) < 0.08:
					ok = false
					break
			if not ok:
				continue
			var ca := a.get_pixel(x, y)
			var cb := truth.get_pixel(x, y)
			var ch := hole.get_pixel(x, y)
			s_t += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			s_h += (absf(ca.r - ch.r) + absf(ca.g - ch.g) + absf(ca.b - ch.b)) / 3.0
			n += 1
	return [n, s_t / maxf(float(n), 1.0) * 255.0, s_h / maxf(float(n), 1.0) * 255.0]


## 门洞在屏幕上的矩形（缩进一圈，避开四周的流光），用来比两张图
func _portal_rect(p: Portal) -> Rect2i:
	var c := cam.cam
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v: Vector3 in [Vector3(-p.width * 0.5, 0.0, 0.0), Vector3(p.width * 0.5, 0.0, 0.0), Vector3(-p.width * 0.5, p.height, 0.0), Vector3(p.width * 0.5, p.height, 0.0)]:
		var s := c.unproject_position(p.frame * v)
		mn = mn.min(s)
		mx = mx.max(s)
	var sz := mx - mn
	var vs := get_viewport().get_visible_rect().size
	var img_k := Vector2(get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()) / vs
	var r := Rect2(mn + sz * Vector2(0.3, 0.28), sz * Vector2(0.4, 0.45))
	return Rect2i(Vector2i(r.position * img_k), Vector2i(r.size * img_k))


static func _img_diff(a: Image, b: Image, r: Rect2i) -> float:
	var x0 := clampi(r.position.x, 0, a.get_width() - 1)
	var y0 := clampi(r.position.y, 0, a.get_height() - 1)
	var x1 := clampi(r.end.x, x0 + 1, a.get_width())
	var y1 := clampi(r.end.y, y0 + 1, a.get_height())
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return sum / maxf(float(n), 1.0) * 255.0


## 量 sec 秒的帧耗时：中位 / 最长（毫秒）、绘制调用、图元
func _perf_probe(sec: float) -> String:
	var tree := get_tree()
	var ts: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	while acc < sec:
		await tree.process_frame
		var t1 := Time.get_ticks_usec()
		var d := float(t1 - t0) / 1000.0
		t0 = t1
		ts.append(d)
		acc += d / 1000.0
	ts.sort()
	return "中位 %.1f ms 最长 %.1f ms 绘制调用 %d 图元 %dk" % [ts[ts.size() / 2], ts[ts.size() - 1], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]


## `-- --hub-shot --farm-plant [--touch]`（2026-11-23 灵田种植）：自检在 farm_selftest.gd（同日下午灵田改成 4×4 格、按钮改成 整备 / 播种 / 收获 时挪过去的）
func farm_plant_selftest() -> void:
	await load("res://scripts/farm_selftest.gd").call("run", self)
