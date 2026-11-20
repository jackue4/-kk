extends Node3D
## 剑冢 Boss 空战总控：血河剑冢（TestHall.BOSS_ARENA）里的 Boss、弹幕池、玩家护体、镜头锁定与 Boss HUD。
## · 玩家踏进赤线（BOSS_R）：自动切进法术空战（低于结丹的先压境到元婴——同阶一战）、镜头拉远并锁定 Boss，
##   法术索敌直接认 Boss；Boss 睁眼升空、魔啸，开打。
## · 战斗中玩家用独立的"护体真元"（100）：中弹扣血、短暂无敌、被打退；Shift 闪现全程无敌（穿弹）；
##   大罡剑阵演出中也不吃弹；4 秒没中弹开始缓慢回复。落到地上会被自动托回空中。
## · 护体打空 = 败：清屏、Boss 收手回去沉睡，玩家被送回赤线外的入口；跑出 LEAVE_R 算脱战，同样重置。
## · 击败：Boss 碎裂伏诛，十几秒后在原处重新凝聚（沉睡），离开赤线再进来可以再打。
## 故意不写 class_name：用 preload 引用。

const Boss := preload("res://scripts/boss_demon.gd")
const Bullets := preload("res://scripts/boss_bullets.gd")
const BossHud := preload("res://scripts/boss_hud.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Combat := preload("res://scripts/combat.gd")
const CombatWord := preload("res://scripts/combat_word.gd")
const CS := preload("res://scripts/combat_stats.gd")      # 战斗数值中枢（2026-11-20 夜）

const TRIGGER_R := TestHall.BOSS_R
const LEAVE_R := TestHall.BOSS_R + 70.0
const HP_MAX := 100.0
const IFRAME := 1.1        # 中弹后无敌
const REGEN_WAIT := 4.0
const REGEN := 4.0         # 每秒回复
const LOCK_ZOOM := 14.0    # 锁定时镜头至少拉到这么远
const MIN_REALM := 3       # 低于结丹（没有法术空战）的压境到元婴
const KNOCK := 9.0
const LOST_HOLD := 2.2     # 倒下后多久送回入口
const RESPAWN := 14.0      # 击败后多久重新凝聚

enum F { IDLE, ON, LOST, WON }

var player: Player
var _orig_realm := -1      # 2026-11-20 夜：开打前把低境界临时拔到元婴，打完（落地）要还回去；以前一直没还，可能被大世界结算存进档
var cam: CameraRig
var hud: Hud
var font: Font
var boss: Boss
var bullets: Bullets
var ui: BossHud
var state := F.IDLE
var hp := HP_MAX
var hits := 0              # 本场中弹次数（演示 / 自检打印用）

var _iframe := 0.0
var _since_hit := 99.0
var _armed := true         # 离开过赤线才能再触发
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	bullets = Bullets.new()
	bullets.name = "BossBullets"
	bullets.target = player
	bullets.on_hit = _on_bullet_hit
	bullets.can_hit = _can_hit
	add_child(bullets)
	boss = Boss.new()
	boss.name = "Boss"
	boss.player = player
	boss.bullets = bullets
	boss.center = TestHall.BOSS_ARENA
	boss.position = TestHall.BOSS_ARENA + Vector3(0.0, Boss.DORMANT_H, 0.0)
	add_child(boss)
	boss.face_rest(entrance())
	boss.defeated.connect(_on_won)
	ui = BossHud.new()
	ui.font = font
	ui.arena = self
	ui.main_hud = hud
	add_child(ui)
	boss.phase_changed.connect(func(_i: int) -> void: ui.phase_flash())
	boss.roared.connect(func() -> void: ui.reveal_name())


func center() -> Vector3:
	return TestHall.BOSS_ARENA


## 入口：赤线外、正对出生点来的方向
func entrance() -> Vector3:
	var d := center() - Vector3(40.0, 0.0, 6.0)
	d.y = 0.0
	return center() - d.normalized() * (TRIGGER_R + 10.0) + Vector3(0.0, 0.1, 0.0)


func hp_ratio() -> float:
	return hp / HP_MAX


func active() -> bool:
	return state == F.ON


func _flat_dist() -> float:
	var p := player.global_position
	return Vector2(p.x - center().x, p.z - center().z).length()


func _process(dt: float) -> void:
	_t += dt
	# 打完了（输 / 赢 / 跑出去）就把临时拔上去的境界还回去（兜底：各收尾处已经还过）
	if _orig_realm >= 0 and state != F.ON:
		_restore_realm()
	var flat := _flat_dist()
	match state:
		F.IDLE:
			if flat > TRIGGER_R + 3.0:
				_armed = true
			if _armed and flat < TRIGGER_R and boss.state == Boss.S.DORMANT:
				start()
		F.ON:
			_iframe -= dt
			_since_hit += dt
			if _since_hit > REGEN_WAIT:
				hp = minf(hp + REGEN * dt, HP_MAX)
			if player.st == Player.St.GROUND:
				player.enter_air_combat()  # 落地了就再托回空中：剑冢里只打空战
			if flat > LEAVE_R:
				_flee()
		F.LOST:
			if _t >= LOST_HOLD and _t - dt < LOST_HOLD:
				player.force_ground()
				player.global_position = entrance()
				cam.lock = null
				hp = HP_MAX
			if _t >= LOST_HOLD + 0.5:
				state = F.IDLE
		F.WON:
			if _t >= 3.0 and _t - dt < 3.0:
				cam.lock = null
			if _t >= RESPAWN:
				boss.reset_dormant()
				Vfx.sky_ring(boss.aim_point(), Color(1.0, 0.2, 0.25), 10.0, 1.2)
				state = F.IDLE
				ui.hide_boss()
	# 中弹闪白：空战里近战不再每帧写闪白，这里接管（地面上交还近战）
	_flash = maxf(_flash - dt * 6.0, 0.0)
	if player.st != Player.St.GROUND and (_flash > 0.0 or state == F.ON):
		player.hero.set_flash(_flash)
	# 受击无敌：人形一明一暗
	if state == F.ON and _iframe > 0.0 and not player.dun_active:
		player.visual.visible = fmod(_iframe, 0.12) > 0.05
	elif player.morph_k() < 1.0 and not (player.dead and player.st == Player.St.AIR):
		player.visual.visible = true      # （空战里陨落、身形已经溃散的不算）


func start() -> void:
	state = F.ON
	_armed = false
	hp = HP_MAX
	hits = 0
	_iframe = 0.0
	_since_hit = 99.0
	if player.realm_idx < MIN_REALM and not player.is_light_mode():
		if _orig_realm < 0:
			_orig_realm = player.realm_idx
		player.set_realm(MIN_REALM, false)
		CombatWord.pop("压境元婴", player.center() + Vector3.UP * 1.6, Realm.line_color(player.realm), 1.0)
	# 2026-11-20 夜：首领血量按境界的出手（base × 技能成长）配，和元婴比（以前固定 12000，合体 / 大乘不到一管灵力就打完）
	boss.max_hp = Boss.HP_MAX * CS.boss_k(player.realm_idx)
	boss.hp = boss.max_hp
	player.enter_air_combat()
	cam.lock = boss
	cam.lock_zoom = LOCK_ZOOM
	boss.begin()
	ui.show_boss()
	Sfx.play("ascend", -8.0, 0.6)


func _can_hit() -> bool:
	return state == F.ON and _iframe <= 0.0 and not player.is_dashing() and not player.ult.active


func _on_bullet_hit(pos: Vector3, dir: Vector3, dmg: float) -> void:
	if not _can_hit():
		return
	if player.air.guarding():
		dmg *= 0.3  # 护体罡气：弹幕只擦掉三成
	hp = maxf(hp - dmg, 0.0)
	hits += 1
	_iframe = IFRAME
	_since_hit = 0.0
	_flash = 1.0
	var swing := dir.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	Vfx.impact(pos, swing, Color(1.0, 0.25, 0.2), 1)
	Vfx.debris(pos, dir + Vector3.UP * 0.3, player.hero.chip_colors(), 8, 5.0)
	player.hit_shake(0.12)
	player.velocity += dir * KNOCK
	cam.add_trauma(0.35)
	cam.fov_punch(-3.0)
	Sfx.play("hit_heavy", -1.0, 0.85)
	Combat.hitstop(0.05)
	ui.player_hit()
	if hp <= 0.0:
		_lose()


## 护体打空：清屏、慢动作、"败"，Boss 收手回去沉睡，稍后把玩家送回入口
## 还回临时拔上去的境界：只在主角还是被拔上去的元婴时才改（中途别的途径换了境界——突破、GM 键——就只清记号，不往回改）
func _restore_realm() -> void:
	if _orig_realm < 0:
		return
	var orig := _orig_realm
	_orig_realm = -1
	if player.realm_idx == MIN_REALM:
		player.set_realm(orig, false)


## 试剑台被关掉（回主城、进大世界）时也还回去
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_EXIT_TREE:
		if player != null and is_instance_valid(player) and player.is_inside_tree():
			_restore_realm()


func _lose() -> void:
	state = F.LOST
	_t = 0.0
	Combat.slowmo(0.15, 0.6, 0.8)
	CombatWord.pop("败", player.center() + Vector3.UP * 1.8, Color(1.0, 0.25, 0.22), 1.6)
	Vfx.death_burst(player.center(), Color(1.0, 0.3, 0.25))
	boss.reset_dormant()
	ui.show_result(false)


## 跑出剑冢：脱战，Boss 回去沉睡（满血）
func _flee() -> void:
	state = F.IDLE
	_restore_realm()
	cam.lock = null
	boss.reset_dormant()
	ui.hide_boss()
	CombatWord.pop("脱战", player.center() + Vector3.UP * 1.6, Color(0.8, 0.85, 1.0), 0.9)


func _on_won() -> void:
	state = F.WON
	_t = 0.0
	_restore_realm()
	player.mp = player.mp_max()
	ui.show_result(true)
