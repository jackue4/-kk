extends Node3D
## 暴气觉醒期间挂在修士身上的两样东西（air_melee.gd 的 _awaken 起；联机里别人觉醒由 remote_player.gd 起）：
##   1 描边：沿身体外轮廓一圈境界色的亮线（VoxelHero.set_outline）—— 所有境界都有
##   2 空间波动：元婴及以上，身周一圈圈往外荡的扭曲（aura_warp.gdshader）；境界越高范围越大、荡得越凶、越频繁地迸一道更强的波前
##   3 境界光环（2026-11-23）：背后展开一轮这个境界的法相光环（realm_halo.gd，纯特效，每个境界一套）。立在人背后一米多、
##     跟着人的朝向转（朝向取身体最外面那层只管偏航的节点，空翻 / 俯冲时不跟着翻）；觉醒开始时展开，结束 / 人不在时淡掉。
## 自己每帧看觉醒还剩多久；人化作遁光 / 陨落时两样都收起来；觉醒结束淡出后停掉 _process，下次觉醒 start() 再接着用。
## 开销：描边 = 身体那二十来件多画一遍背面；波动 = 一张面片（桌面档读屏幕做折射，手机档不读屏幕、只画淡淡的波纹线）。
## 故意不写 class_name：用 preload 引用。

const WARP := preload("res://shaders/aura_warp.gdshader")
const LINE_A := preload("res://shaders/block_outline.gdshader")
const LINE_B := preload("res://shaders/cape_outline.gdshader")
const LINE_C := preload("res://shaders/hero_skin_outline.gdshader")      # 主角皮肤模型（hero_skin.gd）的描边
const TRAIL := preload("res://shaders/trail.gdshader")      # 空战对手被打飞时的拖尾：和上面三个一起预编（见 warmup.gd 的 AWAKE）
const RealmHalo := preload("res://scripts/realm_halo.gd")
const FADE_IN := 0.35
const FADE_OUT := 0.6
const WARP_REALM := 3          # 元婴
const CENTER_Y := 0.95

var hero: Node3D               # VoxelHero（要有 set_outline）
var body: Node3D               # 身体根：取位置和朝向
var src: Object                # 有 awake_t 的那位（本机主角的 air_melee）；没有就按 left 自己倒数
var hidden_fn := Callable()    # 返回 true = 这会儿人不在（化作遁光 / 陨落）
var left := 0.0
var realm_idx := 2
var color := Color(0.5, 0.9, 1.0)

## 这三个着色器在当前环境里编过了没有（warmup.gd 载入时预热过就置 true）。手机 / 网页那套渲染是第一次画到才现编，
## 没编过就等到觉醒那一下才编，正好卡在最要紧的地方
static var primed := false
static var _base_primed := false        # prime() 里描边 / 波动 / 拖尾那五个摆过了没有（光环那三个另算，见 prime）
## 性能对照用的开关（main.gd 的 --spark-perf）：单独关掉描边 / 空间波动，量各自的开销
static var debug_no_line := false
static var debug_no_warp := false
static var debug_no_ribbon := false     # 觉醒时脚下一阵阵上扬的丝带（air_melee.gd 里放的）
static var debug_no_halo := false       # 背后的境界光环
## 2026-11-25 背后的境界光环默认不要了（用户：「觉醒后，不要现在的光圈特效，太丑了，改为灵气爆开」）：觉醒那一下改成灵气往外爆
## （air_melee._awaken_burst / remote_player.awaken_fx → qi_fx.burst），觉醒期间隔一会儿往外荡一小圈气。要看老光环加 --realm-halo
static var halo_on := OS.get_cmdline_user_args().has("--realm-halo")

var _k := 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _pulse := 1.0
var _pulse_cd := 0.5
var _halo: Node3D              # 背后的境界光环（realm_halo.gd），按境界建，换了境界重建
var _halo_tier := -1
var _halo_hue := -1.0
var _halo_yaw := 0.0
var _yaw_node: Node3D          # 身体最外面那层（只有偏航）：光环跟它的朝向


func _init() -> void:
	set_process(false)


## 还没预热过的话（载入时不到结丹）：一进空战（air_melee.gd 的 tick）就在镜头前各摆一粒看不见大小的面片，把着色器先编好。
## 面片挂在镜头底下、按镜头自己的坐标摆（2026-11-23 改的）：原先按「这一刻镜头在哪」摆成世界坐标，镜头同一帧里一跳
## （开场、切机位）它们就不在画面里了，等于白摆 —— 网页版里量到过：预编那一帧一个着色器都没编，全拖到第一次觉醒那一下才编。
## 光环的三个着色器只在用得上时才编：本机主角到了结丹（炼气 / 筑基不能觉醒），或者场上来了别的玩家（他们可能觉醒）。
## 不到结丹的单人局先只编前五个（省得新手头一回起飞多卡一秒），primed 留着 false，air_melee 每帧还会来问，到了结丹再补上。
static func prime(host: Node3D) -> void:
	if primed or not host.is_inside_tree():
		return
	var ri: Variant = host.get("realm_idx")
	var want_halo: bool = halo_on and RealmHalo.enabled and (host.has_method("awaken_fx") or ri == null or int(ri) >= 2)
	if _base_primed and not want_halo:
		if not halo_on:
			primed = true
		return
	var cam := host.get_viewport().get_camera_3d()
	if cam == null:
		return
	var holder := Node3D.new()
	cam.add_child(holder)
	if not _base_primed:
		_base_primed = true
		var quad := QuadMesh.new()
		var shaders: Array = [WARP, LINE_A, LINE_B, LINE_C, TRAIL]
		for i in shaders.size():
			var m := ShaderMaterial.new()
			m.shader = shaders[i]
			m.set_shader_parameter("power", 0.02)
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
			mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.01), Vector3(-0.5 + float(i) * 0.05, -0.7, -2.0))     # 镜头前两米、画面中间偏下，一厘米大
	if want_halo:
		# 摆一个一厘米大的真光环（元婴那档三种图元都有；片是 MultiMesh，要的是带实例化的那个变体）
		var halo: Node3D = RealmHalo.make(3)
		if halo != null:
			holder.add_child(halo)
			halo.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.004), Vector3(-0.2, -0.7, -2.0))
			halo.call("set_power", 0.02)
	primed = want_halo or not RealmHalo.enabled or not halo_on
	host.get_tree().create_timer(0.25).timeout.connect(holder.queue_free)


## 觉醒了（secs：还剩多久；有 src 的以它的 awake_t 为准）
func start(secs: float, realm_i: int, col: Color) -> void:
	left = secs
	realm_idx = realm_i
	color = col
	_pulse = 0.0          # 觉醒那一下先迸一道
	_pulse_cd = _period()
	_halo_start()
	set_process(true)


func strength() -> float:
	return _k


func warp_on() -> bool:
	return _quad != null and _quad.visible


func _tier() -> int:
	return clampi(realm_idx - WARP_REALM, 0, 4)


func _period() -> float:
	return 2.6 - 0.3 * float(_tier())


func _process(dt: float) -> void:
	if src != null:
		left = float(src.get("awake_t"))
	else:
		left -= dt
	var gone := hidden_fn.is_valid() and bool(hidden_fn.call())
	var want := 1.0 if left > 0.0 and not gone else 0.0
	var rate := FADE_IN if want > _k else (0.12 if gone else FADE_OUT)
	_k = move_toward(_k, want, dt / rate)
	if is_instance_valid(hero):
		hero.call("set_outline", 0.0 if debug_no_line else _k, color)
	_tick_warp(dt)
	_tick_halo(dt)
	if _k <= 0.0 and left <= 0.0:
		set_process(false)


## 觉醒那一下：建好（或换成）这个境界的光环，从头展开
func _halo_start() -> void:
	if debug_no_halo or not halo_on:
		return
	# 2026-11-25 英雄档：光环跟这位英雄的颜色走（镇岳本来就是金的不换；苍鸿的青、霜华的冰蓝才换）。老规矩（按境界）不动
	var tint := Color(0, 0, 0, 0)
	if (load("res://scripts/combat_stats.gd") as GDScript).get("heroes_on") and color.s > 0.25 and absf(angle_difference(color.h * TAU, 0.115 * TAU)) > 0.5:
		tint = color
	var hue := tint.h if tint.a > 0.0 else -1.0
	if _halo == null or _halo_tier != realm_idx or not is_equal_approx(hue, _halo_hue):
		if _halo != null:
			_halo.queue_free()
		_halo = RealmHalo.make(realm_idx, tint)
		_halo_tier = realm_idx
		_halo_hue = hue
		if _halo == null:
			return
		_halo.top_level = true
		add_child(_halo)
	# 朝向跟谁：从身体往上找到挂在角色根下面的那一层（主角 / 别的玩家的 visual，只转偏航）
	_yaw_node = null
	var n: Node = body
	while n != null and n.get_parent() != get_parent():
		n = n.get_parent()
	_yaw_node = n as Node3D
	if _yaw_node != null:
		var f := -_yaw_node.global_basis.z
		_halo_yaw = atan2(-f.x, -f.z)
	_halo.call("play_in")


func _tick_halo(dt: float) -> void:
	if _halo == null:
		return
	_halo.call("set_power", 0.0 if debug_no_halo else _k)
	if _k <= 0.005 or not is_instance_valid(_yaw_node):
		return
	var f := -_yaw_node.global_basis.z
	f.y = 0.0
	if f.length_squared() > 0.01:
		_halo_yaw = lerp_angle(_halo_yaw, atan2(-f.x, -f.z), 1.0 - exp(-9.0 * dt))      # 稍微拖一点，转身时光环跟着甩过来
	var pl: Dictionary = RealmHalo.place(realm_idx)
	var b := Basis(Vector3.UP, _halo_yaw)
	var grow := 0.72 + 0.28 * ease(_k, 0.4)       # 展开时由小到大
	_halo.global_transform = Transform3D(b.scaled(Vector3.ONE * grow),
			(get_parent() as Node3D).global_position + Vector3.UP * float(pl["cy"]) + b.z * float(pl["dist"]))


func _tick_warp(dt: float) -> void:
	# 英雄档不看境界（真人对打都压在结丹）：觉醒了身周就有往外荡的波动
	var heroes: bool = (load("res://scripts/combat_stats.gd") as GDScript).get("heroes_on")
	if (realm_idx < WARP_REALM and not heroes) or _k <= 0.01 or not is_instance_valid(body) or debug_no_warp:
		if _quad != null:
			_quad.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _quad == null:
		_build_quad()
	_pulse_cd -= dt
	if _pulse_cd <= 0.0:
		_pulse_cd = _period()
		_pulse = 0.0
	_pulse = minf(_pulse + dt / 0.85, 1.0)
	var tier := float(_tier())
	var radius := 2.0 + 0.25 * tier
	var cb := cam.global_basis.orthonormalized()
	_quad.visible = true
	_quad.global_transform = Transform3D(cb.scaled(Vector3.ONE * radius * 2.0), body.global_position + body.global_basis.y.normalized() * CENTER_Y)
	# 身体在屏幕上的朝向（面片的 UV：x 向右、y 向下）
	var up := body.global_basis.y
	var ax := Vector2(up.dot(cb.x), -up.dot(cb.y))
	_mat.set_shader_parameter("axis", ax.normalized() if ax.length_squared() > 0.01 else Vector2(0.0, 1.0))
	_mat.set_shader_parameter("power", _k)
	_mat.set_shader_parameter("strength", 0.018 + 0.005 * tier)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("tint", color)


func _build_quad() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = WARP
	_mat.render_priority = -100      # 抢在别的半透明特效之前画：它们叠在扭曲过的画面上面，不会被盖掉
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.top_level = true
	_quad.extra_cull_margin = 2.0
	add_child(_quad)
