extends CanvasLayer
## Boss HUD（剑冢空战，见 boss_arena.gd）：
## · 登场题名：只在本局第一次踏进剑冢开战、魔啸那一刻出现一次，和境界突破题字同一套演出（RealmBanner）：
##   屏幕右侧竖排写出"厉沧溟"、左侧小字"血河剑魔"、钤"元婴初期"朱印 → 停留 → 上飘淡出、飞墨四散，不常驻；
## · 顶部居中：Boss 血条（滞后条 + 70% / 35% 两道阶段刻度），左上写当前阶段名，转阶段时中间闪出新阶段名；
## · 底部居中：玩家"护体"条（中弹闪红）和一行操作提示；
## · 胜负：屏幕中央一行大字"厉沧溟 伏诛" / "护体崩散"。
## 时间按真实时间走（慢动作里照常写字）。字体沿用境界题字的行楷（RealmBanner._load_font）。
## 故意不写 class_name：用 preload 引用。

const RealmBanner := preload("res://scripts/realm_banner.gd")
const Boss := preload("res://scripts/boss_demon.gd")
const INK := Color(0.03, 0.02, 0.03)

## 登场题名本次运行里写过没有（静态：剑冢重建 / 再次进场都不再写）
static var name_shown := false

var font: Font
var arena                    # boss_arena.gd
var main_hud: Hud

var _brush: Font
var _c: Control
var _banner: RealmBanner
var _on := false
var _alpha := 0.0
var _roared := false         # 本场魔啸过了：血条开始灌满
var _fill := 0.0
var _lag := 1.0
var _p_lag := 1.0
var _hit_t := 0.0
var _phase_t := -1.0
var _result_t := -1.0
var _won := false


func _ready() -> void:
	layer = 11
	_brush = RealmBanner._load_font()
	_c = Control.new()
	_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw)
	add_child(_c)
	_c.visible = false
	_banner = RealmBanner.new()
	add_child(_banner)


func show_boss() -> void:
	_on = true
	_roared = false
	_fill = 0.0
	_lag = 1.0
	_p_lag = 1.0
	_result_t = -1.0
	_phase_t = -1.0
	_c.visible = true


func hide_boss() -> void:
	_on = false


## 魔啸：血条开始灌满；本次运行第一次开战时题名（转阶段的魔啸、之后再进场都不再写）
func reveal_name() -> void:
	if _roared:
		return
	_roared = true
	if name_shown:
		return
	name_shown = true
	_banner.show_realm(Boss.NAME, _col(), Boss.TITLE, Boss.RANK)


func phase_flash() -> void:
	_phase_t = 0.0


func player_hit() -> void:
	_hit_t = 1.0


func show_result(won: bool) -> void:
	_won = won
	_result_t = 0.0
	if not won:
		_on = false


func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 0.05)
	_alpha = move_toward(_alpha, 1.0 if _on else 0.0, dt * (2.5 if _on else 1.2))
	if _phase_t >= 0.0:
		_phase_t += dt
		if _phase_t > 2.6:
			_phase_t = -1.0
	if _result_t >= 0.0:
		_result_t += dt
		if _result_t > 4.5:
			_result_t = -1.0
			if _won:
				_on = false
	_hit_t = maxf(_hit_t - dt * 3.0, 0.0)
	var b: Boss = arena.boss
	if b.state == Boss.S.INTRO or b.state == Boss.S.DORMANT:
		_fill = move_toward(_fill, 1.0 if _roared else 0.0, dt / 1.4)
	else:
		_fill = 1.0
	var hr := b.hp_ratio() * _fill
	_lag = lerpf(_lag, hr, 1.0 - exp(-2.0 * dt)) if _lag > hr else hr
	var pr: float = arena.hp_ratio()
	_p_lag = lerpf(_p_lag, pr, 1.0 - exp(-2.0 * dt)) if _p_lag > pr else pr
	if main_hud != null:
		main_hud._speed.visible = not _on  # 底部速度读数会压在护体条上：开打时先藏起来
	_c.visible = _alpha > 0.001 or _result_t >= 0.0
	if _c.visible:
		_c.queue_redraw()


static func _ease_out(x: float) -> float:
	var u := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - u * u * u


func _col() -> Color:
	var b: Boss = arena.boss
	return (Boss.PAL[b.phase] as Array)[0]


func _draw() -> void:
	var vs := _c.size
	var k := vs.y / 900.0
	_draw_bar(vs, k)
	_draw_player(vs, k)
	_draw_phase(vs, k)
	_draw_result(vs, k)


## 顶部 Boss 血条
func _draw_bar(vs: Vector2, k: float) -> void:
	var a := _alpha
	if a <= 0.0:
		return
	var b: Boss = arena.boss
	var col := _col()
	var w := 640.0 * k
	var h := 12.0 * k
	var x := (vs.x - w) * 0.5
	var y := 86.0 * k
	_c.draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, h + 6.0), Color(0.03, 0.02, 0.03, 0.7 * a))
	_c.draw_rect(Rect2(x, y, w * _lag, h), Color(1.0, 0.92, 0.85, 0.8 * a))
	var hr := b.hp_ratio() * _fill
	_c.draw_rect(Rect2(x, y, w * hr, h), Color(col.darkened(0.15), a))
	_c.draw_rect(Rect2(x, y, w * hr, h * 0.35), Color(Color.WHITE.lerp(col, 0.4), 0.6 * a))
	for t: float in Boss.PHASE_AT:
		_c.draw_rect(Rect2(x + w * t - 1.5 * k, y - 5.0 * k, 3.0 * k, h + 10.0 * k), Color(1, 1, 1, 0.7 * a))
	var fs := int(20 * k)
	var label := "%s　%s" % [Boss.NAME, b.phase_title()]
	if b.state == Boss.S.SHIFT:
		label += "　护体"
	_c.draw_string_outline(font, Vector2(x, y - 10.0 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5 * k), Color(0.05, 0.03, 0.04, 0.85 * a))
	_c.draw_string(font, Vector2(x, y - 10.0 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.92, a))
	var pct := "%d%%" % int(ceil(b.hp_ratio() * 100.0))
	_c.draw_string_outline(font, Vector2(x, y - 10.0 * k), pct, HORIZONTAL_ALIGNMENT_RIGHT, w, fs, int(5 * k), Color(0.05, 0.03, 0.04, 0.85 * a))
	_c.draw_string(font, Vector2(x, y - 10.0 * k), pct, HORIZONTAL_ALIGNMENT_RIGHT, w, fs, Color(1.0, 0.95, 0.92, a))


## 底部玩家护体条
func _draw_player(vs: Vector2, k: float) -> void:
	var a := _alpha
	if a <= 0.0:
		return
	var w := 420.0 * k
	var h := 10.0 * k
	var x := (vs.x - w) * 0.5
	var y := vs.y - 160.0 * k
	var pr: float = arena.hp_ratio()
	var fill := Color(0.95, 0.78, 0.4).lerp(Color(1.0, 0.25, 0.2), clampf(1.0 - pr * 1.6, 0.0, 1.0))
	fill = fill.lerp(Color.WHITE, _hit_t * 0.7)
	_c.draw_rect(Rect2(x - 2.0, y - 2.0, w + 4.0, h + 4.0), Color(0.03, 0.03, 0.05, 0.65 * a))
	_c.draw_rect(Rect2(x, y, w * _p_lag, h), Color(1.0, 0.92, 0.85, 0.7 * a))
	_c.draw_rect(Rect2(x, y, w * pr, h), Color(fill, a))
	var fs := int(16 * k)
	var txt := "护体 %d" % int(ceil(pr * 100.0))
	_c.draw_string_outline(font, Vector2(x - 92.0 * k, y + h), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * k), Color(0.05, 0.05, 0.08, 0.85 * a))
	_c.draw_string(font, Vector2(x - 92.0 * k, y + h), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	var tip := "镜头自动锁定 · 左键法术自动索敌 · Shift 闪现全程无敌可穿弹 · 往外飞出剑冢即脱战"
	# 提示写在护体条上方：条下面是主 HUD 的操作说明
	var hs := int(14 * k)
	var ty := y - 12.0 * k
	_c.draw_string_outline(font, Vector2(x - 200.0 * k, ty), tip, HORIZONTAL_ALIGNMENT_CENTER, w + 400.0 * k, hs, int(4 * k), Color(0.05, 0.05, 0.08, 0.7 * a))
	_c.draw_string(font, Vector2(x - 200.0 * k, ty), tip, HORIZONTAL_ALIGNMENT_CENTER, w + 400.0 * k, hs, Color(1.0, 0.9, 0.75, 0.85 * a))


## 转阶段：血条下方闪出新阶段名
func _draw_phase(vs: Vector2, k: float) -> void:
	if _phase_t < 0.0:
		return
	var b: Boss = arena.boss
	var a := clampf(_phase_t / 0.2, 0.0, 1.0) * (1.0 - smoothstep(1.9, 2.6, _phase_t))
	var col := _col()
	var fs := int(54 * k)
	var sc := lerpf(1.35, 1.0, _ease_out(_phase_t / 0.3))
	var txt: String = b.phase_title()
	_c.draw_set_transform(Vector2(vs.x * 0.5, 170.0 * k), 0.0, Vector2(sc, sc))
	_c.draw_string_outline(_brush, Vector2(-vs.x * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, int(22 * k), Color(col, 0.25 * a))
	_c.draw_string_outline(_brush, Vector2(-vs.x * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, int(8 * k), Color(INK, 0.8 * a))
	_c.draw_string(_brush, Vector2(-vs.x * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, Color(Color.WHITE.lerp(col, 0.2), a))
	_c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 胜负大字
func _draw_result(vs: Vector2, k: float) -> void:
	if _result_t < 0.0:
		return
	var a := clampf(_result_t / 0.3, 0.0, 1.0) * (1.0 - smoothstep(3.6, 4.5, _result_t))
	var col := Color(1.0, 0.82, 0.4) if _won else Color(1.0, 0.25, 0.22)
	var txt := "%s　伏诛" % Boss.NAME if _won else "护体崩散　退出剑冢"
	var fs := int(78 * k)
	var y := vs.y * 0.42
	_c.draw_rect(Rect2(0, y - fs * 0.95, vs.x, fs * 1.35), Color(INK, 0.45 * a))
	_c.draw_string_outline(_brush, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, int(26 * k), Color(col, 0.25 * a))
	_c.draw_string_outline(_brush, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, int(8 * k), Color(INK, 0.85 * a))
	_c.draw_string(_brush, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, Color(Color.WHITE.lerp(col, 0.25), a))
	if _won:
		var sub := "元婴初期 · 血河剑魔　已斩"
		var ss := int(24 * k)
		_c.draw_string(font, Vector2(0, y + 42.0 * k), sub, HORIZONTAL_ALIGNMENT_CENTER, vs.x, ss, Color(1.0, 0.92, 0.8, 0.9 * a))
