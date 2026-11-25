extends Control
## 英雄选择界面（全屏）。2026-11-24 用户原话：「重构一下英雄选择界面的交互，我希望中间能看到3D英雄的模型，背景是虚化的场景，
## 左右滑动可以选择不同的英雄，底部有英雄的技能描述，基于这个底座，你去优化这套英雄选择界面」。
##
## 画面从下到上：
##   · 虚化的场景：开界面那一下用一个小离屏视口把当前场景拍一张（镜头挪到主角头顶前面，不拍自己的背影），缩小再放大糊成一张静态图；
##     拍完把主视口的 3D 关掉（disable_3d），界面开着的时候只画展台上这几个人 —— 手机上划起来才顺。关界面时恢复
##   · 英雄色的一层薄染、上下左右的暗角、人背后一团光、一幅很淡的大字（英雄名）
##   · 3D 展台（自己的 World3D）：英雄表里每位一个石台，沿 X 排开；镜头跟着手指平移，正中的往前、两侧的退后半步朝中间站
##   · 界面：左上返回 + 题头，左边一幅竖着写名字的立轴，右边一张简介纸条，底下一排技能圆片（和战斗里触屏键上的字一样）+
##     选中那一招的说明 + 「出战」
## 交互：
##   · 左右划（鼠标拖也一样）/ 点两侧的人 / 点两边的箭头 / 方向键 / 滚轮 → 换人，松手吸到最近的一位
##   · 点技能圆片 → 底下换成那一招的说明，展台上的人把那一招比划一遍（combat_poses.gd 的姿势，不出特效）
##   · 点「出战」→ 存档换英雄（ex_profile.set_hero），主城里的主角当场换（player.set_hero），盖一方朱印
## 英雄的数据全读 hero_defs.gd（名字 / 称号 / 介绍 / 四技能 / 觉醒 / 触屏键字 / 配色 / 模型 / 兵器），新加的英雄不用改这里；
## 只有「比划哪几个姿势」「三个关键词」是这里的 SHOW 表（表里没有的英雄就不比划、不出关键词）。
## 打开：open(host)（自己暂停树、放鼠标，关掉时恢复）；盖在已经暂停的界面上（大厅界面的「英雄」页签）用 open(host, false)。
## 自检 / 小样：_tasks/ui_kit/hero_select_test.gd。故意不写 class_name：用 load / preload 引用。

signal closed

const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const HeroDefs := preload("res://scripts/hero_defs.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const AirMoves := preload("res://scripts/air_moves.gd")
const Sfx := preload("res://scripts/sfx.gd")
const MetaKit := preload("res://scripts/ex/meta_kit.gd")      # 返回那颗圆片和备战 / 坊市 / 段位三张页同一个样子

const SELF_PATH := "res://scripts/ex/hero_select_ui.gd"

# ---- 展台 ----
const SPACING := 1.75                        # 相邻两位隔多远（米）
const DEPTH := 3.2                           # 不在正中的往后退多少
const CAM_FOV := 30.0
const CAM_POS := Vector3(0.0, 1.5, 7.0)
const CAM_LOOK := Vector3(0.0, 0.85, 0.0)
const FACE_YAW := 0.3                        # 正中那位侧一点身
const LIFT := 0.3                            # 比划招式时离地多高（招式都是御空的姿势）
const STAGE_H := 900                         # 展台最多画多高（像素）；手机档 720
const STAGE_H_LITE := 720
const BG_PITCH := 7.0                        # 拍场景那一张时镜头往上抬多少度
const BG_H := 216                            # 场景那一张拍多高（像素），之后再缩到四分之一糊开

# ---- 手感 ----
const DRAG_SPAN := 0.26                      # 手指划过画面宽度的这么多 = 换一位
const TAP_PX := 14.0                         # 按下到松开挪得比这少算「点」
const SNAP := 11.0                           # 松手后吸过去的快慢（每秒）

# ---- 版面（界面单位，画面高 900 时）----
const MARGIN := 28.0
const CHIP := Vector2(100.0, 124.0)          # 一颗技能圆片占的格子（圆片 + 底下一行名字）
const CHIP_D := 88.0
const DESC_H := 176.0                        # 说明纸条至少这么高（换技能时不跳）
const PICK := Vector2(230.0, 88.0)
const ARROW := Vector2(190.0, 60.0)           # 「‹ 名字」那块能点的地方
const INFO_W := 344.0
const INK_BASE := Color(0.07, 0.065, 0.06)

## 展示用的小表（英雄表里没有的东西）：tags 三个关键词（都出自 hero_defs.gd 那句介绍），
## enter 转到正中时摆的一下，demo 六颗圆片各比划哪几个姿势（连段 / E / Z / Q / R / 觉醒；名字是 combat_poses.gd 的 SEQ）
const SHOW := {
	"yujian": {"tags": ["重拳连段", "霸体破防", "开山裂地"], "enter": ["zy_awk"],
		"demo": [["zy1", "zy2", "zy3", "zy4"], ["zy_bs"], ["zy_j1", "zy_j2", "zy_j1", "zy_j2", "zy_palm"], ["zy_kao"], ["zy_quake"], ["zy_awk"]]},
	"shuanghua": {"tags": ["中距控场", "寒意冻结", "碎冰爆发"], "enter": ["sh_awk"],
		"demo": [["sh1", "sh2", "sh3", "sh4"], ["sh_cast"], ["sh_nova"], ["sh_q"], ["sh_r"], ["sh_awk"]]},
	"canghong": {"tags": ["藏锋拔剑", "剑痕引爆", "招架反斩"], "enter": ["cg_gj"],
		"demo": [["cg1", "cg2", "cg3", "cg4"], ["cg_jh"], ["cg_parry", "cg_f2", "cg_gj"], ["cg_lk"], ["cg_f1", "cg_f2", "cg_f1", "cg_f2", "cg_f1", "cg_gj"], ["cg_awk"]]},
}


## 展台上的一位
class Slot:
	var id := ""
	var def := {}
	var col := Color.WHITE
	var root: Node3D            # 石台 + 人（沿 X 排开，不在正中时往后退）
	var turn: Node3D            # 转身
	var lift: Node3D            # 比划招式时离地
	var hero: VoxelHero
	var rig: Rig
	var blade := false          # 手里一直拿着剑
	var ring: StandardMaterial3D
	var queue: Array = []       # 还没比划的姿势
	var demo := false
	var demo_t := 0.0
	var lift_k := 0.0
	var pulse := 0.0            # 转到正中 / 出战时石台上那一圈亮一下


var font: Font
var use_scene_bg := true         # 拍当前场景当背景（小样页没有场景时关掉）
var wheel := true                # 滚轮换人（自检关掉：隐藏窗口也会收到真鼠标的滚轮）
var manage_pause := true         # 自己暂停树、放鼠标（盖在已经暂停的界面上时不管）

var _ids: Array = []
var _slots: Array[Slot] = []
var _cur := ""                   # 存档里出战的那位
var _index := 0                  # 正中是谁
var _offset := 0.0               # 转盘位置（0 = 第一位在正中，可以是小数）
var _target := 0
var _settled := -1               # 上一次停稳在谁身上
var _skill := 1                  # 底下选中的圆片：0 连段 · 1~4 四个技能 · 5 觉醒
var _t := 0.0
var _fade := 0.0
var _lite := false
var _touch := false
var _closing := false

var _drag := false
var _drag_x0 := 0.0
var _drag_off0 := 0.0
var _drag_i0 := 0
var _drag_far := 0.0
var _drag_last_x := 0.0
var _drag_last_t := 0
var _vel := 0.0

var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _hid_3d := false
var _bg_ready := false

var _vp: SubViewport
var _cam: Camera3D
var _rim: DirectionalLight3D
var _rest_q := Quaternion.IDENTITY
var _col_now := Color(0.7, 0.8, 1.0)

var _bg: TextureRect
var _tint: ColorRect
var _glow: TextureRect
var _mark: Label
var _stage: TextureRect
var _fx: Control
var _ui: Control
var _back: Button
var _head: Control
var _pager: Control
var _banner: PanelContainer
var _name_v: Label
var _title_v: Label
var _use_seal: Control
var _info: PanelContainer
var _tags: HBoxContainer
var _desc: Label
var _arrow_l: Button
var _arrow_r: Button
var _chips: Array[Button] = []
var _chip_box: Control
var _sk_panel: PanelContainer
var _sk_name: Label
var _sk_meta: HBoxContainer
var _sk_desc: Label
var _sk_awake: Label
var _pick: Button
var _toast: Label
var _toast_t := 0.0
var _stamp_t := -1.0             # 「出战」那一下朱印盖下来的进度（秒；负 = 没在盖）
var _motes: Array[Vector4] = []
var _relayout := 0
var _snd: AudioStreamPlayer


## 打开。host = 挂在谁下面（一般是 level_select.gd 那一层，压在主界面和触屏键上面）。pause = 自己暂停树、放鼠标，关掉时恢复
static func open(host: Node, pause := true) -> Control:
	var scr: GDScript = load(SELF_PATH)
	var ui: Control = scr.new()
	ui.set("manage_pause", pause)
	host.add_child(ui)
	return ui


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	if font == null:
		font = UiStyle.kai()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 22
	theme = th
	_lite = Vfx.lite
	_touch = OS.get_cmdline_user_args().has("--touch") or DisplayServer.is_touchscreen_available()
	if manage_pause:
		_was_paused = get_tree().paused
		_was_mouse = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for id: Variant in ExProfile.hero_ids():
		if HeroDefs.has(str(id)):
			_ids.append(str(id))
	if _ids.is_empty():
		_ids = HeroDefs.ids()
	_cur = ExProfile.hero()
	_index = maxi(_ids.find(_cur), 0)
	_target = _index
	_offset = float(_index)
	_rest_q = Poses.blade_quat(Vector3(0.3, -0.9, -0.32).normalized(), Vector3(0.1, -1.0, 0.0).normalized())
	_build_back()
	_build_stage()
	_build_ui()
	_show_hero()
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	_capture_bg()


func _exit_tree() -> void:
	_restore()


## 关界面 / 被人直接拆掉时都走这里：主视口的 3D 打开、暂停和鼠标恢复原样
func _restore() -> void:
	if _hid_3d:
		_hid_3d = false
		var rv := get_viewport()
		if rv != null:
			rv.disable_3d = false
	if manage_pause:
		manage_pause = false
		var tree := get_tree()
		if tree != null:
			tree.paused = _was_paused
		Input.mouse_mode = _was_mouse


func close() -> void:
	if _closing:
		return
	_closing = true
	_restore()
	closed.emit()
	queue_free()


# ====================================================================
# 背景
# ====================================================================

static func _grad(stops: Array, from: Vector2, to: Vector2, radial := false) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	t.fill_from = from
	t.fill_to = to
	return t


func _cover(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _build_back() -> void:
	var base := ColorRect.new()
	base.color = INK_BASE
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	# 没拍到场景（小样页 / 拍之前那一两帧）时的底：一片由暗到亮的天色
	_bg = _cover(_grad([[0.0, Color(0.16, 0.17, 0.24)], [0.62, Color(0.36, 0.34, 0.42)], [1.0, Color(0.2, 0.19, 0.2)]], Vector2(0.5, 0.0), Vector2(0.5, 1.0)))
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tint = ColorRect.new()
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	# 上下压暗（题头 / 底下那排字压得住）；两侧的暗角压在展台上面（见 _build_stage）
	var ink := Color(0.04, 0.035, 0.035)
	var v := _cover(_grad([[0.0, Color(ink, 0.5)], [0.22, Color(ink, 0.0)], [0.62, Color(ink, 0.0)], [0.82, Color(ink, 0.55)], [1.0, Color(ink, 0.88)]],
			Vector2(0.5, 0.0), Vector2(0.5, 1.0)))
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow = _cover(_grad([[0.0, Color(1, 1, 1, 0.55)], [0.45, Color(1, 1, 1, 0.16)], [1.0, Color(1, 1, 1, 0.0)]], Vector2(0.5, 0.5), Vector2(1.0, 0.5), true))
	_mark = Label.new()
	_mark.add_theme_font_override("font", UiStyle.brush())
	_mark.add_theme_color_override("font_color", Color.WHITE)
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)


## 拍一张当前场景、糊开，换到背景上；拍完把主视口的 3D 关掉
func _capture_bg() -> void:
	var rv := get_viewport()
	var cam := rv.get_camera_3d() if rv != null and use_scene_bg else null
	if cam == null:
		_bg_ready = true
		return
	var vs := size
	var w := clampi(int(roundf(float(BG_H) * vs.x / maxf(vs.y, 1.0))), 64, 1024)
	var sv := SubViewport.new()
	sv.size = Vector2i(w, BG_H)
	sv.world_3d = rv.find_world_3d()
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var c := Camera3D.new()
	c.fov = cam.fov
	c.near = cam.near
	c.far = cam.far
	c.environment = cam.environment
	c.attributes = cam.attributes
	c.cull_mask = cam.cull_mask
	sv.add_child(c)
	var xf := cam.global_transform
	# 主镜头在主角身后、往下看：照原样拍，正中是一团自己的背影，大半张都是地面。
	# 只留它的朝向（左右），改成平视略仰；有主角就挪到主角头顶偏前 —— 拍到的是远处的楼和天
	var fwd := -xf.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.FORWARD
	xf.basis = Basis(Vector3.UP, atan2(-flat.x, -flat.z)) * Basis(Vector3.RIGHT, deg_to_rad(BG_PITCH))
	var scene := get_tree().current_scene
	var pv: Variant = scene.get("player") if scene != null else null
	if is_instance_valid(pv) and pv is Node3D:
		xf.origin = (pv as Node3D).global_position + Vector3(0.0, 3.2, 0.0) + flat * 1.2
	c.global_transform = xf
	c.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(sv) or _closing or not is_inside_tree():
		return
	var img := sv.get_texture().get_image()
	sv.queue_free()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		img.shrink_x2()
		img.shrink_x2()
		img.resize(w, BG_H, Image.INTERPOLATE_CUBIC)
		_bg.texture = ImageTexture.create_from_image(img)
	_bg_ready = true
	if rv != null and not rv.disable_3d:
		rv.disable_3d = true
		_hid_3d = true


# ====================================================================
# 展台
# ====================================================================

func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED if _lite else Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(16, 16)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.98, 0.96)
	env.ambient_light_energy = 0.62
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(0.5, -0.72, -1.0).normalized(), Vector3.UP)      # 从镜头左上方打到脸上
	key.light_energy = 0.95
	key.shadow_enabled = false
	_vp.add_child(key)
	_rim = DirectionalLight3D.new()
	_rim.basis = Basis.looking_at(Vector3(-0.7, -0.25, 1.0).normalized(), Vector3.UP)      # 从背后右侧来的一道英雄色的边光
	_rim.light_energy = 0.9
	_rim.shadow_enabled = false
	_vp.add_child(_rim)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.2
	_cam.far = 60.0
	_vp.add_child(_cam)
	_cam.transform = Transform3D(Basis.looking_at(CAM_LOOK - CAM_POS, Vector3.UP), CAM_POS)
	_cam.current = true
	for i in _ids.size():
		_slots.append(_make_slot(str(_ids[i]), i))
	_stage = _cover(_vp.get_texture())
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 压在展台上面的一层：两侧的人退到暗处，正中那位亮着
	var ink := Color(0.04, 0.035, 0.035)
	var side := _cover(_grad([[0.0, Color(ink, 0.66)], [0.3, Color(ink, 0.5)], [0.405, Color(ink, 0.0)], [0.595, Color(ink, 0.0)], [0.7, Color(ink, 0.5)],
			[1.0, Color(ink, 0.66)]], Vector2(0.0, 0.5), Vector2(1.0, 0.5)))
	side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261124
	for _i in 22:
		_motes.append(Vector4(rng.randf_range(-1.0, 1.0), rng.randf(), rng.randf_range(0.05, 0.13), rng.randf_range(1.6, 3.6)))
	_tick_stage(0.0)


static func hero_color(def: Dictionary) -> Color:
	var rl: Variant = def.get("realm", {})
	if rl is Dictionary:
		var lines: Variant = (rl as Dictionary).get("lines", [])
		if lines is Array and not (lines as Array).is_empty() and (lines as Array)[0] is Color:
			return (lines as Array)[0]
	return Color(0.55, 0.8, 1.0)


func _flat(col: Color, tex: Texture2D, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.albedo_texture = tex
	m.render_priority = prio
	return m


func _make_slot(id: String, i: int) -> Slot:
	var s := Slot.new()
	s.id = id
	s.def = HeroDefs.def_of(id)
	s.col = hero_color(s.def)
	s.root = Node3D.new()
	s.root.position = Vector3(float(i) * SPACING, 0.0, 0.0)
	_vp.add_child(s.root)
	# 石台：一块墨色的圆台，台面上一笔英雄色的墨圆，脚下一团影子
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.12
	cm.height = 0.16
	cm.radial_segments = 40
	cm.rings = 1
	base.mesh = cm
	base.position.y = -0.08
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.17, 0.16, 0.17)
	bm.roughness = 0.9
	base.material_override = bm
	s.root.add_child(base)
	var ring := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(2.24, 2.24)
	ring.mesh = rp
	ring.position.y = 0.006
	ring.rotation.y = float(i) * 1.9
	s.ring = _flat(Color(s.col, 0.8), UiStyle.tex("enso"), 0)
	ring.material_override = s.ring
	s.root.add_child(ring)
	var blob := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(1.5, 1.5)
	blob.mesh = bp
	blob.position.y = 0.012
	blob.material_override = _flat(Color.WHITE, _grad([[0.0, Color(0, 0, 0, 0.6)], [0.6, Color(0, 0, 0, 0.22)], [1.0, Color(0, 0, 0, 0.0)]],
			Vector2(0.5, 0.5), Vector2(1.0, 0.5), true), 1)
	s.root.add_child(blob)
	s.turn = Node3D.new()
	s.root.add_child(s.turn)
	s.lift = Node3D.new()
	s.turn.add_child(s.lift)
	s.hero = VoxelHero.new({}, true, false, HeroDefs.TIER, HeroSkin.hero_key(str(s.def.get("skin", ""))))
	s.lift.add_child(s.hero)
	# 兵器：一直拿着剑的（苍鸿）手里一把它那个颜色的剑，其余空手（方块骨架要一个挂点，给个空节点）
	s.blade = bool(s.def.get("blade_always", false))
	var weapon: Node3D
	if s.blade:
		weapon = MeshLib.make_sword(s.def.get("sword_glow", s.col) as Color)
		var bmat := weapon.get_meta("blade_mat") as StandardMaterial3D
		if bmat != null:
			bmat.albedo_color = s.def.get("sword_col", Color(0.86, 0.9, 0.95)) as Color
			bmat.emission_energy_multiplier = 0.9
	else:
		weapon = Node3D.new()
	s.rig = Rig.new(s.hero, weapon, 1.0, -0.375, 0.72)
	var pm: Variant = s.def.get("pose_map", {})
	if pm is Dictionary:
		s.rig.remap = pm
	var idle := str(s.rig.remap.get("f_idle", "f_idle"))
	if Poses.has_def(idle):
		s.rig.snap(Poses.get_pose(idle))
	return s


## 这位把 names 里的姿势挨个比划一遍（没有的名字跳过）
func _demo(s: Slot, names: Array) -> void:
	var q: Array = []
	for n: Variant in names:
		if Poses.has_seq(str(n)):
			q.append(str(n))
	if q.is_empty():
		return
	s.queue = q
	s.demo = true
	_next_pose(s)


func _next_pose(s: Slot) -> void:
	var n := str(s.queue.pop_front())
	s.rig.play(n)
	var keys: Array = Poses.raw_seq(n)
	var last := float((keys[keys.size() - 1] as Array)[0])
	s.demo_t = maxf(last + 0.14, 0.3) + (0.55 if s.queue.is_empty() else 0.0)


func _tick_stage(dt: float) -> void:
	_cam.position.x = CAM_POS.x + _offset * SPACING
	for i in _slots.size():
		var s := _slots[i]
		var d := float(i) - _offset
		var ad := absf(d)
		var near := 1.0 - smoothstep(0.0, 1.0, ad)
		s.root.position = Vector3(float(i) * SPACING, 0.0, -DEPTH * smoothstep(0.0, 1.0, ad) - 0.8 * clampf(ad - 1.0, 0.0, 1.0))
		# 正中的微微侧身、慢慢晃；两边的朝中间转
		s.turn.rotation.y = PI + FACE_YAW * near - clampf(d, -1.5, 1.5) * 0.5 + sin(_t * 0.7 + float(i) * 1.7) * 0.05 * near
		if s.demo:
			s.demo_t -= dt
			if s.demo_t <= 0.0:
				if s.queue.is_empty():
					s.demo = false
				else:
					_next_pose(s)
		s.hero.animate(dt, 0.0, 0.0, false, s.demo)
		s.rig.w_up_target = 1.0 if s.demo else 0.0
		s.rig.w_leg_target = 1.0 if s.demo else 0.0
		s.rig.update(dt)
		s.rig.apply(dt)
		s.lift_k = lerpf(s.lift_k, 1.0 if s.demo else 0.0, 1.0 - exp(-7.0 * dt))
		s.lift.position.y = LIFT * s.lift_k + sin(_t * 2.1) * 0.03 * s.lift_k
		if s.blade:
			# 没在比划时剑垂在身侧（招式姿势让出多少，就往「垂着」靠多少）
			var want := (s.hero.global_basis.orthonormalized() * Basis(_rest_q)).get_rotation_quaternion()
			var now := s.rig.holder.global_basis.orthonormalized().get_rotation_quaternion()
			s.rig.holder.global_basis = Basis(now.slerp(want, clampf(1.0 - s.rig.w_up * 1.5, 0.0, 1.0)))
		s.pulse = maxf(s.pulse - dt * 1.6, 0.0)
		s.ring.albedo_color = Color(s.col.lerp(Color.WHITE, s.pulse * 0.6), (0.3 + 0.5 * near + 0.08 * sin(_t * 2.4)) * (1.0 + s.pulse * 0.4))
	_rim.light_color = _col_now.lerp(Color.WHITE, 0.25)


## 展台画多大：跟着窗口的比例，高度封顶（手机上窗口是两三千像素宽，不用照原样画）
func _fit_stage() -> void:
	var win := Vector2(get_window().size) if get_window() != null else size
	var cap := float(STAGE_H_LITE if _lite else STAGE_H)
	var h := clampf(win.y, 240.0, cap)
	var w := h * size.x / maxf(size.y, 1.0)
	var want := Vector2i(maxi(int(roundf(w)), 16), int(roundf(h)))
	if _vp.size != want:
		_vp.size = want


## 飘上去的几点光
func _draw_fx() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.725)
	var top := size.y * 0.2
	var spread := size.y * 0.3
	var a := clampf(1.0 - absf(_offset - roundf(_offset)) * 2.4, 0.0, 1.0)
	for i in _motes.size():
		var m := _motes[i]
		var ph := fposmod(m.y + _t * m.z, 1.0)
		var p := Vector2(c.x + m.x * spread + sin(_t * 0.9 + float(i)) * 9.0, lerpf(c.y, top, ph))
		var k := sin(ph * PI) * a
		_fx.draw_circle(p, m.w * 2.4, Color(_col_now, 0.07 * k), true, -1.0, true)
		_fx.draw_circle(p, m.w, Color(_col_now.lerp(Color.WHITE, 0.55), 0.55 * k), true, -1.0, true)


# ====================================================================
# 界面
# ====================================================================

func _lab(text: String, fs: int, col := UiStyle.TEXT_INK, on_scene := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if on_scene:
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _paper(margin := 16.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.plaque(0.94, 1, margin))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	# ---- 顶上：返回、题头、第几位 ----
	_back = MetaKit.round_button("meta_icon_back", 68.0)
	_back.pressed.connect(func() -> void:
		_click()
		close())
	_ui.add_child(_back)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 12)
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_head)
	var seal := UiStyle.seal("英", 46.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(seal)
	var tl := _lab("择英雄", 42, UiStyle.TEXT, true)
	tl.add_theme_font_override("font", UiStyle.brush())
	_head.add_child(tl)
	var sub := _lab("英雄只换招式，气血、灵力和装备都一样", 21, Color(UiStyle.TEXT, 0.82), true)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(sub)
	_pager = Control.new()
	_pager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pager.draw.connect(_draw_pager)
	_ui.add_child(_pager)

	# ---- 左边：竖着写名字的立轴 ----
	_banner = _paper(20.0)
	_ui.add_child(_banner)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(bh)
	_title_v = _lab("", 24, UiStyle.CINNABAR)
	_title_v.add_theme_constant_override("line_spacing", -2)
	_title_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_v.size_flags_vertical = Control.SIZE_SHRINK_END
	bh.add_child(_title_v)
	_name_v = _lab("", 92)
	_name_v.add_theme_font_override("font", UiStyle.brush())
	_name_v.add_theme_constant_override("line_spacing", -16)
	_name_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_child(_name_v)
	_use_seal = UiStyle.seal("战", 58.0)
	_use_seal.rotation = -0.12
	_use_seal.pivot_offset = Vector2(29.0, 29.0)
	_use_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_use_seal)

	# ---- 右边：简介纸条 ----
	_info = _paper(20.0)
	_ui.add_child(_info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 12)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(iv)
	_tags = HBoxContainer.new()
	_tags.add_theme_constant_override("separation", 8)
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(_tags)
	iv.add_child(UiStyle.rule(INFO_W - 40.0, 7.0, Color(UiStyle.LINE, 0.7)))
	_desc = _lab("", 23)
	_desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_desc.custom_minimum_size = Vector2(INFO_W - 40.0, 0)
	_desc.add_theme_constant_override("line_spacing", 4)
	iv.add_child(_desc)

	# ---- 两边的箭头 ----
	_arrow_l = _arrow(-1)
	_arrow_r = _arrow(1)

	# ---- 底下：技能圆片、说明、出战 ----
	_chip_box = Control.new()
	_chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_chip_box)
	for i in 6:
		var b := Button.new()
		b.custom_minimum_size = CHIP
		b.size = CHIP
		b.position = Vector2(float(i) * CHIP.x, 0.0)
		b.focus_mode = Control.FOCUS_NONE
		for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
		b.draw.connect(_draw_chip.bind(b, i))
		b.pressed.connect(_pick_skill.bind(i, true))
		_chip_box.add_child(b)
		_chips.append(b)
	_sk_panel = _paper(18.0)
	_ui.add_child(_sk_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sk_panel.add_child(sv)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 14)
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(sr)
	_sk_name = _lab("", 32)
	_sk_name.add_theme_font_override("font", UiStyle.brush())
	sr.add_child(_sk_name)
	_sk_meta = HBoxContainer.new()
	_sk_meta.add_theme_constant_override("separation", 8)
	_sk_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sk_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sr.add_child(_sk_meta)
	_sk_desc = _lab("", 22)
	_sk_desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	sv.add_child(_sk_desc)
	_sk_awake = _lab("", 21, UiStyle.QING)
	_sk_awake.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	sv.add_child(_sk_awake)
	_pick = Button.new()
	_pick.custom_minimum_size = PICK
	_pick.size = PICK
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.add_theme_font_size_override("font_size", 38)
	_pick.pressed.connect(pick)
	_ui.add_child(_pick)

	# ---- 提示、朱印、音效 ----
	_toast = _lab("", 26, UiStyle.TEXT, true)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_ui.add_child(_toast)
	_snd = AudioStreamPlayer.new()
	add_child(_snd)


## 旁边那位的名字 + 一个尖角（dir = -1 左边那位 / 1 右边那位），摆在他脚边；点它 = 换过去
func _arrow(dir: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = ARROW
	b.size = ARROW
	b.focus_mode = Control.FOCUS_NONE
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.draw.connect(func() -> void:
		var j := _index + dir
		if j < 0 or j >= _slots.size():
			return
		var mode := b.get_draw_mode()
		var hot := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var col := UiStyle.CINNABAR.lightened(0.3) if hot else UiStyle.TEXT
		var dark := Color(0.05, 0.04, 0.04, 0.85)
		var bf := UiStyle.brush()
		var nm := str(_slots[j].def.get("name", _slots[j].id))
		var fs := 32
		var ts := bf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var w := ts.x + 34.0
		var x0 := (b.size.x - w) * 0.5
		var cy := b.size.y * 0.5
		var sway := sin(_t * 3.0) * 3.0 * float(dir)
		var ax := (x0 + 9.0 if dir < 0 else x0 + w - 9.0) + sway
		var pts := PackedVector2Array([Vector2(ax - 8.0 * dir, cy - 15.0), Vector2(ax + 8.0 * dir, cy), Vector2(ax - 8.0 * dir, cy + 15.0)])
		b.draw_polyline(pts, dark, 9.0, true)
		b.draw_polyline(pts, col, 4.5, true)
		var tp := Vector2(x0 + 34.0 if dir < 0 else x0, cy + bf.get_ascent(fs) - bf.get_height(fs) * 0.5)
		b.draw_string_outline(bf, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, dark)
		b.draw_string(bf, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col))
	b.pressed.connect(go.bind(dir))
	_ui.add_child(b)
	return b


func _tag(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.outline(Color(col, 0.75))
	sb.set_content_margin_all(5.0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_lab(text, 21, col))
	return p


## 六颗圆片各是什么：[键字, 名字]
func _chip_info(i: int) -> Array:
	var d: Dictionary = _slots[_index].def
	if i == 0:
		return ["攻", "连段"]
	if i == 5:
		return ["觉", "觉醒"]
	var sk := HeroDefs.skill(_slots[_index].id, i - 1)
	var touch: Variant = d.get("touch", [])
	var g := str(sk.get("key", ""))
	if touch is Array and (touch as Array).size() >= i:
		g = str((touch as Array)[i - 1])
	return [g, str(sk.get("name", ""))]


func _draw_chip(b: Button, i: int) -> void:
	var info := _chip_info(i)
	var sel := i == _skill
	var mode := b.get_draw_mode()
	var down := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var hot := mode == BaseButton.DRAW_HOVER
	var c := Vector2(CHIP.x * 0.5, CHIP_D * 0.5 + 2.0)
	var er := CHIP_D * 0.5 * (1.0 if sel else 0.92)
	var r := er / 1.19
	b.draw_circle(c, r * 0.97, Color(UiStyle.CINNABAR, 0.95) if sel or down else Color(UiStyle.PAPER, 0.97 if hot else 0.9), true, -1.0, true)
	var enso := UiStyle.tex("enso")
	if enso != null:
		b.draw_set_transform(c, float(i) * 1.1, Vector2.ONE)
		b.draw_texture_rect(enso, Rect2(-er, -er, er * 2.0, er * 2.0), false, Color(UiStyle.PAPER if sel else UiStyle.LINE, 0.95))
		b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		b.draw_arc(c, r, 0.0, TAU, 48, UiStyle.LINE, 3.0, true)
	var bf := UiStyle.brush()
	var fs := 38 if sel else 34
	var g := str(info[0])
	var ts := bf.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	b.draw_string(bf, Vector2(c.x - ts.x * 0.5, c.y + bf.get_ascent(fs) - bf.get_height(fs) * 0.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UiStyle.PAPER if sel or down else UiStyle.TEXT_INK)
	var nm := str(info[1])
	var ns := 21
	var nsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns)
	var np := Vector2(c.x - nsz.x * 0.5, CHIP_D + 6.0 + font.get_ascent(ns))
	b.draw_string_outline(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 6, Color(0.05, 0.04, 0.04, 0.9))
	b.draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, UiStyle.TEXT if sel else Color(UiStyle.TEXT, 0.78))
	# 键盘上是哪个键：只在不是触屏时写一个小字
	if not _touch and i >= 1 and i <= 4:
		var kt := str(HeroDefs.skill(_slots[_index].id, i - 1).get("key", ""))
		if kt != "":
			var kc := c + Vector2(r * 0.86, -r * 0.86)
			b.draw_circle(kc, 12.0, UiStyle.PAPER, true, -1.0, true)
			b.draw_arc(kc, 12.0, 0.0, TAU, 24, Color(UiStyle.LINE, 0.8), 1.5, true)
			var ks := font.get_string_size(kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			b.draw_string(font, kc + Vector2(-ks.x * 0.5, font.get_ascent(15) - font.get_height(15) * 0.5), kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiStyle.TEXT_INK)


func _draw_pager() -> void:
	var n := _ids.size()
	var gap := 26.0
	var x0 := _pager.size.x - float(n - 1) * gap - 12.0
	var y := _pager.size.y * 0.5
	for i in n:
		var k := clampf(1.0 - absf(float(i) - _offset), 0.0, 1.0)
		var p := Vector2(x0 + float(i) * gap, y)
		_pager.draw_circle(p, 9.0, Color(0.05, 0.04, 0.04, 0.55), true, -1.0, true)
		_pager.draw_circle(p, lerpf(5.0, 7.5, k), Color(UiStyle.TEXT, 0.55).lerp(UiStyle.CINNABAR.lightened(0.15), k), true, -1.0, true)


static func _vertical(text: String) -> String:
	var out := ""
	for i in text.length():
		out += ("\n" if i > 0 else "") + text[i]
	return out


## 招式名：英雄自己的表里有就用它，否则是通用表（air_moves.gd）
func _move_name(id: String, mv: String) -> String:
	var m := HeroDefs.move_of(id, mv)
	if m.is_empty():
		var g: Variant = AirMoves.MOVES.get(mv, {})
		m = g if g is Dictionary else {}
	return str(m.get("name", mv))


func _chain_text(id: String, chain: Array) -> String:
	var names: Array = []
	for mv: Variant in chain:
		var n := _move_name(id, str(mv))
		if names.is_empty() or str(names[names.size() - 1]) != n:
			names.append(n)
	return " → ".join(names)


## 把正中这一位的名字 / 简介 / 圆片换上
func _show_hero() -> void:
	var s := _slots[_index]
	var d := s.def
	_name_v.text = _vertical(str(d.get("name", s.id)))
	_title_v.text = _vertical(str(d.get("title", "")))
	_mark.text = str(d.get("name", s.id))
	_desc.text = str(d.get("desc", ""))
	for c in _tags.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	var show: Dictionary = SHOW.get(s.id, {})
	for t: Variant in show.get("tags", []):
		_tags.add_child(_tag(str(t), UiStyle.CINNABAR))
	_tags.visible = _tags.get_child_count() > 0
	_refresh_pick()
	_pick_skill(_skill, false)
	_relayout = 2


func _refresh_pick() -> void:
	var s := _slots[_index]
	var using := s.id == _cur
	_pick.text = "出战中" if using else "出战"
	_pick.disabled = using
	if using:
		UiStyle.style_button(_pick)
		_pick.add_theme_font_override("font", UiStyle.brush())
		_pick.add_theme_stylebox_override("disabled", UiStyle._btn_box(UiStyle.TINT_BTN, Color(UiStyle.CINNABAR, 0.75), 0.2))
		_pick.add_theme_color_override("font_disabled_color", UiStyle.CINNABAR)
	else:
		UiStyle.style_primary(_pick)
	_use_seal.visible = using


## 选中第 i 颗圆片：底下换说明；play = 展台上的人比划一遍
func _pick_skill(i: int, play: bool) -> void:
	_skill = clampi(i, 0, 5)
	var s := _slots[_index]
	var d := s.def
	for c in _sk_meta.get_children():
		(c as CanvasItem).visible = false
		c.queue_free()
	var name_t := ""
	var desc_t := ""
	var awake_t := ""
	if _skill == 0:
		name_t = "连段"
		desc_t = "连点「攻」：" + _chain_text(s.id, d.get("chain", []))
		var dv: Dictionary = d.get("derive", {})
		if not dv.is_empty():
			desc_t += "\n连到一半推摇杆变招：前 %s · 后 %s · 左右 %s" % [_move_name(s.id, str(dv.get("up", ""))), _move_name(s.id, str(dv.get("down", ""))),
					_move_name(s.id, str(dv.get("side", "")))]
		var ca: Array = d.get("chain_awake", [])
		if not ca.is_empty():
			awake_t = "觉醒后：" + _chain_text(s.id, ca)
	elif _skill == 5:
		name_t = "觉醒"
		var aw: Variant = d.get("awaken", "")
		desc_t = str((aw as Dictionary).get("desc", "")) if aw is Dictionary else str(aw)
	else:
		var sk := HeroDefs.skill(s.id, _skill - 1)
		name_t = str(sk.get("name", ""))
		desc_t = str(sk.get("desc", ""))
		if float(sk.get("cd", 0.0)) >= 1.0:
			_sk_meta.add_child(_tag("冷却 %s 秒" % _num(float(sk.get("cd", 0.0))), UiStyle.TEXT_SOFT))
		if float(sk.get("mp", 0.0)) > 0.0:
			_sk_meta.add_child(_tag("灵力 %s" % _num(float(sk.get("mp", 0.0))), UiStyle.INDIGO))
		if bool(sk.get("awake_only", false)):
			_sk_meta.add_child(_tag("觉醒中才能放", UiStyle.QING))
		if str(sk.get("awake", "")) != "":
			awake_t = "觉醒后 → " + str(sk.get("awake", ""))
	_sk_name.text = name_t
	_sk_desc.text = desc_t
	_sk_awake.text = awake_t
	_sk_awake.visible = awake_t != ""
	for b in _chips:
		b.queue_redraw()
	if play:
		_click()
		var show: Dictionary = SHOW.get(s.id, {})
		var demos: Array = show.get("demo", [])
		if _skill < demos.size():
			_demo(s, demos[_skill])
	_relayout = 2


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.1))


## 摆位置。画面比 1600×900 大就两边 / 上下多留空，不放大；窄了（宽不到 1400）整块界面缩一点
func _layout() -> void:
	var vs := size
	if vs.x < 10.0 or vs.y < 10.0:
		return
	_fit_stage()
	# 背景略放大一圈（左右留出视差的余量），人背后的光、淡淡的大字
	_tint.position = Vector2.ZERO
	_tint.size = vs
	var gs := vs.y * 1.05
	_glow.size = Vector2(gs, gs)
	_glow.position = Vector2(vs.x * 0.5 - gs * 0.5, vs.y * 0.46 - gs * 0.5)
	_mark.add_theme_font_size_override("font_size", int(vs.y * 0.4))
	_mark.size = Vector2(vs.x, vs.y * 0.6)
	_mark.position = Vector2(0.0, vs.y * 0.14)
	var k := minf(1.0, vs.x / 1500.0)
	_ui.scale = Vector2(k, k)
	var us := vs / k                     # 界面自己的坐标里画面多大
	var cx := us.x * 0.5
	_back.position = Vector2(MARGIN, 14.0)
	_head.size = _head.get_combined_minimum_size()
	_head.position = Vector2(MARGIN + 68.0 + 20.0, 14.0 + (68.0 - _head.size.y) * 0.5)
	_pager.size = Vector2(240.0, 62.0)
	_pager.position = Vector2(us.x - MARGIN - 240.0, 18.0)
	# 底下一排：圆片靠左，出战靠右，说明夹在中间；整排最宽 1560，再宽就居中
	var row_w := minf(us.x - MARGIN * 2.0, 1560.0)
	var x0 := cx - row_w * 0.5
	var chips_w := CHIP.x * 6.0
	var desc_w := row_w - chips_w - PICK.x - 36.0
	_sk_desc.custom_minimum_size = Vector2(desc_w - 44.0, 0)
	_sk_awake.custom_minimum_size = Vector2(desc_w - 44.0, 0)
	var ph := maxf(_sk_panel.get_combined_minimum_size().y, DESC_H)
	var bottom := us.y - 18.0
	_sk_panel.size = Vector2(desc_w, ph)
	_sk_panel.position = Vector2(x0 + chips_w + 18.0, bottom - ph)
	_chip_box.size = Vector2(chips_w, CHIP.y)
	_chip_box.position = Vector2(x0, bottom - ph * 0.5 - CHIP.y * 0.5)
	_pick.position = Vector2(x0 + row_w - PICK.x, bottom - ph * 0.5 - PICK.y * 0.5)
	# 左右两张纸：竖直方向以人的腰为准，底边不压到底下那排
	var mid := (86.0 + bottom - ph - 16.0) * 0.5
	_banner.size = _banner.get_combined_minimum_size()
	_banner.position = Vector2(maxf(MARGIN + 28.0, cx - 716.0), mid - _banner.size.y * 0.5)
	_use_seal.position = _banner.position + Vector2(_banner.size.x - 40.0, _banner.size.y - 44.0)
	_info.size = Vector2(INFO_W, _info.get_combined_minimum_size().y)
	_info.position = Vector2(minf(us.x - MARGIN - INFO_W, cx + 716.0 - INFO_W + 28.0), mid - _info.size.y * 0.5)
	# 「‹ 名字」摆在两侧那位的脚边（按展台镜头算他在画面上的位置）
	var nx := SPACING / (CAM_POS.z + DEPTH) / tan(deg_to_rad(CAM_FOV) * 0.5) * vs.y * 0.5 / k
	_arrow_l.position = Vector2(cx - nx - ARROW.x * 0.5, us.y * 0.715 - ARROW.y * 0.5)
	_arrow_r.position = Vector2(cx + nx - ARROW.x * 0.5, us.y * 0.715 - ARROW.y * 0.5)
	_toast.size = Vector2(us.x, 40.0)
	_toast.position = Vector2(0.0, bottom - ph - 60.0)


# ====================================================================
# 每帧
# ====================================================================

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	_t += dt
	_fade = minf(_fade + dt * 6.0, 1.0)
	modulate.a = _fade
	var n := _slots.size()
	if not _drag:
		_offset = lerpf(_offset, float(_target), 1.0 - exp(-SNAP * dt))
		if absf(_offset - float(_target)) < 0.002:
			_offset = float(_target)
	var ni := clampi(roundi(_offset), 0, n - 1)
	if ni != _index:
		_index = ni
		_show_hero()
	if not _drag and absf(_offset - float(_target)) < 0.04 and _settled != _index:
		var first := _settled < 0
		_settled = _index
		_on_settle(first)
	_tick_stage(dt)
	# 换人换到一半时，字先淡出去、换好再淡回来；整块跟着手指挪一点
	var frac := _offset - roundf(_offset)
	var a := clampf(1.0 - absf(frac) * 2.6, 0.0, 1.0)
	var shift := -frac * 70.0
	for c: Control in [_banner, _info, _sk_panel, _chip_box, _pick, _use_seal]:
		c.modulate.a = a
	_banner.position.x += shift - float(_banner.get_meta("sx", 0.0))
	_banner.set_meta("sx", shift)
	_info.position.x += shift - float(_info.get_meta("sx", 0.0))
	_info.set_meta("sx", shift)
	_use_seal.position.x = _banner.position.x + _banner.size.x - 40.0
	_col_now = _col_now.lerp(_slots[_index].col, 1.0 - exp(-8.0 * dt))
	_tint.color = Color(_col_now, 0.1)
	_glow.modulate = Color(_col_now.lerp(Color.WHITE, 0.5), 0.5 * a + 0.2)
	_mark.modulate = Color(_col_now.lerp(UiStyle.PAPER, 0.6), 0.2 * a)
	_mark.position.x = -frac * 160.0
	# 背景：略放大，跟着转盘慢慢平移一点（视差）
	var vs := size
	var zoom := 1.1 + 0.012 * sin(_t * 0.35)
	_bg.size = vs * zoom
	_bg.position = Vector2(-(zoom - 1.0) * 0.5 * vs.x - (_offset - float(n - 1) * 0.5) * vs.x * 0.02, -(zoom - 1.0) * 0.5 * vs.y)
	_arrow_l.visible = _index > 0
	_arrow_r.visible = _index < n - 1
	_arrow_l.queue_redraw()
	_arrow_r.queue_redraw()
	_pager.queue_redraw()
	_fx.queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	if _stamp_t >= 0.0:
		_stamp_t += dt
		var u := clampf(_stamp_t / 0.18, 0.0, 1.0)
		var sc := lerpf(2.6, 1.0, 1.0 - pow(1.0 - u, 3.0))
		_use_seal.scale = Vector2(sc, sc)
		_use_seal.modulate.a = a * u
		if _stamp_t > 0.3:
			_stamp_t = -1.0
			_use_seal.scale = Vector2.ONE
	if _relayout > 0:
		_relayout -= 1
		_layout()
		_banner.set_meta("sx", 0.0)
		_info.set_meta("sx", 0.0)


## 停稳在一位身上：石台亮一下，摆个亮相的姿势（刚打开界面那一下不摆，只亮）
func _on_settle(first: bool) -> void:
	var s := _slots[_index]
	s.pulse = 1.0
	if first:
		return
	var show: Dictionary = SHOW.get(s.id, {})
	_demo(s, show.get("enter", []))


# ====================================================================
# 操作
# ====================================================================

## 往左 / 右换一位
func go(dir: int) -> void:
	var t := clampi(_target + dir, 0, _slots.size() - 1)
	if t != _target:
		_target = t
		_click(1.15)


## 直接转到某位（自检 / 别的界面指定打开时停在谁身上）。now = 不滑过去，直接到位
func goto_id(id: String, now := false) -> bool:
	var i := _ids.find(id)
	if i < 0:
		return false
	_target = i
	if now:
		_offset = float(i)
	return true


## 正中是谁
func current_id() -> String:
	return _slots[_index].id


## 点「出战」：存档换英雄，主城里的主角当场换。返回成没成
func pick() -> bool:
	var s := _slots[_index]
	if s.id == _cur:
		return false
	var err := ExProfile.set_hero(s.id)
	if err != "":
		_say(err, UiStyle.CINNABAR.lightened(0.35))
		return false
	_cur = s.id
	apply_to_player(get_tree(), s.id)
	_refresh_pick()
	s.pulse = 1.0
	var show: Dictionary = SHOW.get(s.id, {})
	_demo(s, show.get("enter", []))
	_stamp_t = 0.0
	_say("%s 出战" % str(s.def.get("name", s.id)), UiStyle.TEXT)
	_click(0.8, "pickup")
	return true


## 主城里换了英雄：主角立刻换（新图 / 主城以外不动，下次入境读存档）
static func apply_to_player(tree: SceneTree, id: String) -> void:
	if tree == null:
		return
	var m := tree.current_scene
	if m == null or m.get("level") != null:
		return
	var p: Variant = m.get("player")
	if p != null and is_instance_valid(p) and (p as Object).has_method("set_hero"):
		p.call("set_hero", id)


func _say(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast_t = 1.8
	_toast.visible = true


## 界面开着时树是暂停的，音效池（sfx.gd）里的播放器不走：用自己这一个
func _click(pitch := 1.0, snd := "ui_click") -> void:
	var st := Sfx.gen_stream(snd)
	if st == null or _snd == null:
		return
	_snd.stream = st
	_snd.volume_db = -8.0 + float(Sfx.GAIN.get(snd, 0.0))
	_snd.pitch_scale = pitch
	_snd.play()


func _rubber(x: float) -> float:
	var hi := float(_slots.size() - 1)
	if x < 0.0:
		return x * 0.3
	if x > hi:
		return hi + (x - hi) * 0.3
	return x


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_x0 = mb.position.x
				_drag_off0 = _offset
				_drag_i0 = _target
				_drag_far = 0.0
				_drag_last_x = mb.position.x
				_drag_last_t = Time.get_ticks_msec()
				_vel = 0.0
			elif _drag:
				_drag = false
				_release(mb.position.x)
			accept_event()
		elif wheel and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP):
			go(1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		var dx := mm.position.x - _drag_x0
		_drag_far = maxf(_drag_far, absf(dx))
		_offset = _rubber(_drag_off0 - dx / maxf(size.x * DRAG_SPAN, 1.0))
		var now := Time.get_ticks_msec()
		var el := float(now - _drag_last_t) * 0.001
		if el > 0.004:
			var v := -(mm.position.x - _drag_last_x) / maxf(size.x * DRAG_SPAN, 1.0) / el
			_vel = lerpf(_vel, v, 0.6)
			_drag_last_x = mm.position.x
			_drag_last_t = now
		accept_event()


## 松手：挪得很少算「点」（点两侧 = 换到那边那位，点正中 = 让他再亮个相）；划了就吸到最近的一位，甩得快多带一位
func _release(x: float) -> void:
	var n := _slots.size()
	if _drag_far < TAP_PX:
		_offset = _drag_off0
		var u := x / maxf(size.x, 1.0)
		if u < 0.4:
			go(-1)
		elif u > 0.6:
			go(1)
		else:
			_on_settle(false)
		return
	if float(Time.get_ticks_msec() - _drag_last_t) > 120.0:
		_vel = 0.0          # 停住再松手的不算甩
	var t := roundi(_offset + clampf(_vel * 0.14, -0.6, 0.6))
	_target = clampi(clampi(t, _drag_i0 - 1, _drag_i0 + 1), 0, n - 1)
	if _target != _drag_i0:
		_click(1.15)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		close()
	elif e.is_action_pressed("ui_left"):
		go(-1)
	elif e.is_action_pressed("ui_right"):
		go(1)
	elif e.is_action_pressed("ui_accept"):
		pick()
	else:
		return
	get_viewport().set_input_as_handled()
