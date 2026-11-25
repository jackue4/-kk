extends Node
## 空战斗法（结丹起，空战状态下）：近身拳脚 + 飞剑随击 + 重击击飞 + 瞬身追击，飞剑 / 法术改成技能键。
##
## · 攻击（J / 左键）点按：五段追身连击 —— 冲拳 → 摆拳 → 蹬踢 → 回旋踢 → 掣剑横斩（把人斩飞）。
##   每一段出手都会吸附到目标身前；目标在 RUSH_R 内而不在身边时，先「追身突进」冲过去再打。
##   每一拳命中后，身后的飞剑紧跟着刺进同一个目标（剑随拳走），连击不断、灵力回涨。
## · 攻击长按：蓄力重击。松手时按方向决定去向 —— 默认「崩拳」向前击飞；按住空格「挑飞」向上；按住 S「陨落」向下砸。
## · 目标被击飞时再按攻击：「瞬身追击」—— 瞬移到它飞行路线的前头再补一记重击（最多 CHASE_MAX 次，每次耗一点灵力），
##   默认顺序 前 → 上 → 下，最后一记把人砸进地面；从高处砸下时镜头切到落点旁的低机位看它坠地。
## · 格挡（K / 右键）按住：护体罡气，正面受击只掉一点血、耗灵力；刚按下的 PERFECT 秒内被打中 = 「瞬身」闪到对手背后，
##   画面骤慢，对手露出破绽。
## · E 点按：飞剑点射（一柄追踪飞剑，耗少量灵力）；长按：万剑连发（air_caster.gd 的连发）。
## · Z / X / C：三式剑诀（即 air_caster.gd 里各境界的三段法术），各有灵力消耗和冷却；第三式出手时给一个特写镜头。
## · T：对波「剑罡」—— 蓄势后推出一道光柱，持续灼烧并在收束时把人轰飞。对手同时放光柱就进入「对波」相持：
##   连点攻击把交汇点往对面顶，顶到头就轰穿对手；被顶回来则自己被轰飞。镜头切到侧面看两道光柱相持。
## · V 按住：聚气 —— 快速回灵力、攒觉醒槽（拳脚命中 / 挨打也攒）。槽满后继续聚气 = 「觉醒」：气浪震开身边的对手，
##   十几秒内伤害提高、瞬身追击不耗灵力、飞剑对波顶得更狠。
## · 被重击打飞后砸到地面：砸出裂纹和碎石坑（Vfx.crater），倒地片刻再起身。
## · 被打：轻击硬直，重击被击飞翻滚（可以按 Shift 闪现受身）。气血用的是 PlayerMelee 的 hp。
##
##
## —— 高速格斗这一层（招式数据和攻防规则都在 air_moves.gd，对手 air_foe.gd 用的是同一份）——
## · 方向派生：连段里 摇杆方向 + 点按攻击 —— 前 = 挑月（向上打飞）· 后 = 坠星（向下砸）· 左右 = 绕身击（绕到背后，护体挡不住）。
## · 御风突进：有目标时按住「闪」（摇杆不往后拉）= 高速冲向锁定的目标，摇杆左右能绕着弧线切到侧面 / 背后，
##   到身前自动收住；途中点按攻击 = 冲刺攻击「破空蹬」。持续耗灵力。
## · 击飞追击两种：点按攻击 = 瞬身追击（瞬移到它飞行路线前头，耗灵力，每套最多 CHASE_MAX 次）；
##   按「闪」= 追身（高速飞过去，便宜一半，同样计次）。追上之后点按 = 空中连击三下，再接终结重击把人再打飞；
##   追上之后长按 = 直接终结重击。
## · 瞬身：对手的攻击判定前一瞬间（VANISH_WIN）按下「御」或「闪」= 闪到它侧后方、画面骤慢；随后点按攻击 = 瞬身反击。
##   耗灵力；短时间内连续瞬身，窗口越来越窄。所有瞬移落点都先过 _safe_spot（不进地形、不穿墙、不出界）。
## · 破防：蓄力过半的重击、瞬身反击护体挡不住，直接把对手的护体破开（长硬直）；一直压着打把护体值削光也会破。
##   自己护体时被对手的蓄力重击（红光）打中、或灵力见底还硬挡，同样被破防。
## · 挣脱：挨打硬直中按「御」，耗一格罡气把身边的人震开（罡气两格，慢慢回）。被打飞时按「闪」受身。
## · 连段越长伤害越低（air_moves.gd 的 dmg_scale）。
##
## 由 Player 在 _process 里调 tick()（在 PlayerMelee.tick 之后），用的是 PlayerMelee 的 rig 和手中剑。
## 故意不写 class_name：用 preload 引用。

const Rig := preload("res://scripts/fighter_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const Proj := preload("res://scripts/spell_projectile.gd")
const Moves := preload("res://scripts/air_moves.gd")
const ClashFx := preload("res://scripts/clash_fx.gd")
const AwakenFx := preload("res://scripts/awaken_fx.gd")
const AwakenCine := preload("res://scripts/awaken_cine.gd")

enum A { IDLE, RUSH, ATTACK, CHARGE, SMASH, GUARD, HURT, BLOWN, CLASH, GATHER, DOWN, DASH, CRUSH, DEAD, THROW, GRABBED, BRAWL, STOMP }

const HOLD_T := 0.24          # 攻击键按住超过这么久转入蓄力
const CHARGE_FULL := 0.7      # 蓄满用时
const CHARGE_MAX := 1.2       # 蓄满后最多再攒这么久就自动打出去
const BUFFER := 0.25
const RUSH_R := 36.0          # 这么远内按攻击会追身突进
const RUSH_SPD := 62.0
const STICK := 1.4            # 出手时与目标中心的间距（另加目标体型半径）
const GAP_BODY := 0.95        # 打有身体表面的怪：自己的中心离它表面这么远（一臂长）
const MAGNET := 4.5           # 这么近不必突进，出招时直接吸过去
const BODY_Y := 1.05          # 贴身时让自己的胸口对齐目标中心：脚底比目标中心低这么多
const CHASE_MAX := Moves.CHASE_MAX
const CHASE_MP := 8.0
const GUARD_MP := 6.0
const PERFECT := Moves.VANISH_WIN
const DASH_R := 90.0          # 御风突进：这么远内有目标才冲
const DASH_SPD := 78.0
const DASH_ACC := 0.16        # 这么久加到全速
const DASH_MP := 9.0          # 每秒耗的灵力
const DASH_MIN_MP := 4.0
const HOMING_SPD := 150.0     # 追身（追被打飞的目标）的速度
const REACH := 2.4            # 目标在身前这么近（另加出手间距）算「够得着」：空中连击不用再瞬移
const COMBO_KEEP := 2.0
const SHOT_MP := 3.0
const SHOT_CD := 0.16
const HIT_MP := 2.5           # 每一下拳脚命中回的灵力
const REGEN_WAIT := 6.0       # 这么久没挨打，气血开始缓慢回复
const REGEN := 6.0
const ENGAGE_KEEP := 5.0      # 最后一次出手 / 受击后多久还算在交战（保持架势和镜头锁定）
const CLASH_MIN_DIST := 1.0   # 贴着身也能对起来：开场会先把两个人拉开（_clash_place）
const CLASH_SAFE := 16.0      # 对波时两人至少隔这么远，近了开场先各自退开
const CLASH_ALT := 3.6        # ……脚底至少离地这么高（交汇点的光核、碰撞盘、剑流都有两三米大，贴着地会扎进地里）
const CLASH_SETUP := 0.4      # 退开 / 升起用这么久；这段时间交汇点不动、双方不耗灵力
const CLASH_BLAST_R := 14.0   # 相持时每隔一会儿把交汇点这么远内的旁人震开
const WARN_MS := 1000.0       # 对手起手飞剑时的预警窗口（真实时间，毫秒）：这段时间里点「剑」/「攻击」就接下来对波
const WARP_BASE := 0.008      # 交汇点的空间扭曲强度：基础 + 每高一个境界再加一点（结丹约 0.016，化神 0.024，大乘 0.036）
const WARP_STEP := 0.004
const BRAWL_MOVE_T := 0.11    # 拳劲对拼里换一次位冲多久（五六米的路，合每秒五十米上下）
const CLASH_MAX := 7.0        # 相持最久这么多秒，到点谁占优谁赢（输出怎么算见 air_moves.gd「飞剑对波」）
const GATHER_MP := 45.0       # 聚气每秒回的灵力
const AWAKE_DUR := 14.0
const AWAKE_DMG := 1.3
const SKILL_KEYS := ["Z", "X", "C"]
const SKILL_COST := [0.1, 0.18, 0.32]   # 占灵力上限的比例
## 三式共用一个冷却（2026-11-20，用户要求）：放了哪一式，三式一起转它那一档的冷却——一式 1.2 秒、二式 3.5 秒、三式 8 秒。
## 之前是各转各的，Z 连按三下能把三式一口气全放出来。
const SKILL_CD := [1.2, 3.5, 8.0]

## 招式表在 air_moves.gd（MOVES：轻击五段 l1~l5、方向派生 d_*、冲刺攻击 dash、空中连击 j1~j3、瞬身反击 ctr；SMASH：重击三式）。
## 这里的 ATK 是轻击五段的招式名，step 是打到第几段。
## 2026-11-24 英雄系统：ATK / SMASH / 空中连击 / 方向派生 / 瞬身反击 / 冲刺攻击都可以由英雄表（hero_defs.gd）换掉（apply_hero），
## 招式数据先查英雄表再查 air_moves.gd（_mv）—— air_moves.gd 的老条目不动，AI 修士（air_foe.gd）照旧读它们
var ATK: Array = Moves.CHAIN
var SMASH: Dictionary = Moves.SMASH
var JUG: Array = Moves.JUGGLE
var _hero_moves: Dictionary = {}
var _derive := {"up": "d_up", "down": "d_dn", "side": "d_fl"}
var _ctr_id := "ctr"
var _dash_id := "dash"
var _follow_k := 0.2          # 拳脚命中后跟上的飞剑每柄几个单位
var _hero_flair := -1         # 英雄档的花样档（-1 = 按境界）
## 2026-11-25 TSB 式重做（英雄表里的新字段，见 scripts/heroes/def_zhenyue.gd 文件头）
var _no_swords := false       # 拳脚命中后不带随击飞剑（纯拳脚的英雄）
var _rush_r := 0.0            # 点「攻」自动冲过去的最远距离（0 = 老规矩：RUSH_R 内都冲）
var _awake_dur := AWAKE_DUR   # 觉醒多久
var stat_armor := 0           # 自检用：霸体扛下了几下
var _last_contact := Vector3.ZERO
var _awk_full_was := false
var _wall_n := 0                # 这一次被打飞已经撞了几堵墙
var _chain_base: Array = Moves.CHAIN
var _chain_awake: Array = []
var skill_cd: Array = SKILL_CD   # 「诀」三式共用冷却的三档（英雄档下按英雄表）
## 招架（苍鸿的「回风」/ 觉醒「剑域」，kit_canghong.gd 起）：架势还剩多久（真实时间），剑域的半径（0 = 普通回风，只接近身），这一架已经接了几下
var parry_t := 0.0
var parry_r := 0.0
var parry_n := 0
var parry_max := 1
var _parry_dom := false        # 剑域还开着（没接满、没到时间）：反斩收招后回到架势、反斩途中也接（复核 combat-7）
var _die_forced := false
var _awake_was := false

var player: Player
var rig: Rig
var state := A.IDLE
var step := 0
var move_id := "l1"           # 正在出的招（air_moves.gd 里的招式名）
var burst := 1.0              # 罡气（挣脱用）：0 ~ BURST_MAX 格
var target: Node3D = null
var drive_vel := Vector3.ZERO
var has_face := false
var face_yaw := 0.0
var guard_held := false
var combo := 0                # 连击数（拳脚 + 飞剑都算）
var combo_dmg := 0.0
var cds: Array[float] = [0.0, 0.0, 0.0]      # 三式的冷却剩余（共用，三个数始终一样；留成数组是因为界面和自检按下标读）
var cd_full := 1.0            # 这一轮冷却一共多长（画进度用）

var _t := 0.0
var _clock := 0.0
var _drives := false
var _atk: Dictionary = Moves.MOVES["l1"]
var stat_hits: Array = []      # 自检用（hero_selftest.gd）：最近打出去的 [招式名, 原始伤害, 结果]
var _hit_done := false
var _queued := false
var _whiff := false
var _buf_at := -10.0
var _held := 0.0              # 攻击键已按住的时长
var _hold_used := false       # 这次按住已经放过一记重击：松手前不再蓄
var _last_step := -1
var _last_end := -10.0
var _charge := 0.0
var _auto_release := -1.0     # 演示用：蓄到这么久自动松手
var _smash_kind := "fwd"
var _smash_k := 0.0
var _sm_dash := false
var _chase := false           # 这一记重击是瞬身追击
var _chase_n := 0
var _launched: Node3D = null  # 刚被击飞、可以追击的目标
var _launch_kind := ""
var _guard_at := -10.0
var _push := Vector3.ZERO
var _dur := 0.0
var _tumble := 0.0
var _iframe := 0.0
# ---- 真人对打（2026-11-23，规则和数在 air_moves.gd 的「真人对打」）----
static var pvp_legacy := false   # 对照开关：true = 之前的规则（连段不断、起身没保护、近身不花灵力也没前摇）
var _pc_live := false         # 正被真人连着打（这一套还没断）
var _pc_n := 0                # 这一套里已经挨了几下
var _pc_launch := 0           # ……其中被打飞了几次
var _pc_t0 := -10.0           # 这一套从什么时候开始（真实时间）
var _pc_idle := 0.0           # 从硬直里出来多久了；超过 PVP_COMBO_GAP 这一套就算断了
var _pc_last := -10.0         # 上一次被真人打中的时刻
var _pc_beat := -10.0         # 上一拍是什么时候数的
var _open_end := 0.0          # 起手前摇按到什么时候（真实时间；攻方自己的顿帧不该把它拖长，对面是按真实时间看提示的）
var _pc_escape := -1.0        # 这一套到头了：再过这么久自动脱身
var _blown_launch := false    # 这次被打飞是真的击飞（不是重手打得一歪）
var _prot := 0.0              # 起身 / 受身 / 脱身后的保护还剩多久
var _opener := false          # 正从远处近身：下一招是「起手」，要补足前摇
var _open_at := -10.0         # 动身 / 现身的时刻（真实时间）
var _open_hold := 0.0         # 起手前摇还要按住多久
var _whiff_pen := 0.0         # 打在保护中的人身上：多罚这么久收招
var _rooted := false          # 这一招是够不着的原地挥空（没灵力近身 / 对方被打飞了又追不了）：出手时不往目标身上吸
var pvp_stat := {"combos": 0, "max_hits": 0, "escapes": 0, "protects": 0, "prot_whiffs": 0, "openers": 0, "no_mp": 0}   # 自检用
var _flash := 0.0
var _flash_on := false
var _combo_t := 0.0
var _shot_cd := 0.0
var _shot_held := 0.0
var _shot_n := 0
var _point_t := 0.0
var _engage := 0.0
var _ghost_t := 0.0
var _art_next := 0            # 「诀」下一次轮到第几式
const GUARD_GATHER_T := 0.7   # 护体按住这么久、又没人在打自己，就转入聚气
var _ground_frame := -1       # 这一帧是从地面按键升空进来的：同一个按键事件别再处理一遍
var _flurry_left := 0         # 乱舞还剩几下（合体 / 大乘的收尾）
var _flurry_cd := 0.0
var _flurry_n := 0
var _aura_t := 0.0
var _aura_p: CPUParticles3D   # 手机档：聚气 / 蓄力 / 觉醒时脚下上扬的细针（常驻一个发射器，见 Vfx.aura_stream）
var _aura_want := false       # 这一帧有没有人要它喷
var _aim_pitch := 0.0
var _lock_node: Node3D = null
var _cine_t := -1.0           # 演出镜头已过时间，-1 = 没有
var _cine_dur := 0.0
var _cine_out := 0.25
var _cine_follow: Node3D = null
var _cine_eye := Vector3.ZERO
var _cine_wait_crash := false
var _cine_in := 0.0           # 演出镜头切进来用多久（0 = 硬切）
var _cine_handed := false     # 这段演出已经把跟随机位转到它的朝向上了（交还前做一次）
var _stream := 0.0
var awaken := 0.0             # 觉醒槽 0~100
var awake_t := 0.0            # 觉醒剩余时间
var _awake_fx: AwakenFx       # 觉醒期间的描边 / 空间波动（awaken_fx.gd）
var demo_mash := 0.0          # 演示用：对波时每秒自动点这么多下
var demo_gather := false      # 演示用：当作按住了聚气
var _beam_dir := Vector3.FORWARD     # 对波时自己 → 对手的方向
var _warn_foe: Node3D = null      # 正朝自己起手 / 连发飞剑的对手（预警、接波用）
var _warn_until := 0.0            # 预警窗口到什么时候（Time.get_ticks_msec）
## 联机对波（对手是别的玩家的木偶）：各自累计自己顶了多少（_clash_my），对方的从网络来（木偶的 clash_their），
## 交汇点 = 0.5 + 我顶的 − 他顶的；_clash_auth = 由我这边判胜负（发起的一方），否则等对方发结果（_clash_forced：1 赢 / -1 输）
var _clash_my := 0.0
var _clash_auth := true
var _clash_forced := 0
var _clash_blast := 0.0
var _clash_arc := 0.0
var _clash_ring := 0.0
var _clash_foe: Node3D = null
var _clash_u := 0.5
var _clash_t := 0.0
var _clash_fx := 0.0
var _lie := 0.0
var _cine_look := Vector3.ZERO
var _cine_use_look := false
var _since_hurt := 99.0
var _queued_id := ""          # 缓冲的下一招（方向派生 / 终结重击 "fin"；空 = 顺着招式表的 next 走）
var _last_id := ""            # 上一招（收招后 LINK 秒内再按，接着它的 next 往下打）
var _string_n := 0            # 这套连段里拳脚命中了几下（伤害衰减用）
var _flank := 1.0             # 绕身击往哪边绕
var _dash_t := 0.0            # 御风突进已冲多久
var _dash_homing := false     # 这一段是追身（追被打飞的目标）
var _dash_atk := false        # 途中按过攻击：到位即出冲刺攻击
var _arrive := 0.0            # 刚冲到身前：这段时间里出手不用再突进
var _press_at := -10.0        # 最近一次按下「御」/「闪」的时刻（_clock）：瞬身看的是这一下离判定有多近
var _vanish_n := 0            # 短时间内连续瞬身了几次（窗口随之收窄）
var _vanish_last := -10.0
var _counter_until := -10.0   # 这之前点攻击 = 瞬身反击
var _probe: PhysicsShapeQueryParameters3D
var _brk_cued := false        # 这次蓄力已经闪过「够破防了」的金光
var _cfx: ClashFx             # 对波的画面（两束能量 + 交汇光核，见 clash_fx.gd）
var _clash_surge := 0.0       # 连点攒的发力（很快衰减）
var _clash_adv := 0.0         # 这一帧的优势 -1~1
var _clash_press := 0         # 1 压制着对手 / -1 被压制 / 0 相持
var _clash_shot := -1         # 对波镜头现在是第几个机位（见 _clash_cam）
var _clash_shot_t := 0.0
var _clash_want := -1          # 对波镜头想切去的机位（要稳住 CLASH_WANT_T 秒才真切，免得压制 / 被压制来回翻时镜头跟着来回切）
var _clash_want_t := 0.0
const CLASH_SHOT_MIN := 1.1    # 对波每个机位至少看这么久
const CLASH_WANT_T := 0.3
var _clash_side := Vector3.RIGHT
var _mash_acc := 0.0
var _throw_ph := 0            # 投技阶段：0 探手 / 1 抡 / 2 收招
var _throw_yaw := 0.0
var _spin_y := 0.0            # 抡人时整身自转的角度（叠在 spin_euler 上）
var _grab_by: Node3D = null   # 擒住自己的对手
var _downed: Node3D = null    # 刚被自己砸进地里的对手（坠地追击的对象）
var _otg_done := true         # 这一次坠地已经补过一发了（坠星踏 / 剑雨二选一）
var _stomp_ph := 0            # 坠星踏：0 俯冲 · 1 踩实之后的收招
var _stomp_from := Vector3.ZERO
var _stomp_to := Vector3.ZERO
var _rain_t := -1.0           # 剑雨灌顶已经下了多久；< 0 = 没在下
var _rain_tgt: Node3D = null
var _rain_pos := Vector3.ZERO
var _rain_dmg := 0.0
var _swat_t := 0.0            # 弹开气弹的那一下手势还要摆多久
var _swat_n := 0
var _grab_taps := 0
var _brawl_foe: Node3D = null # 拳劲对拼的对手
var _brawl_u := 0.5           # 优势条 0~1（1 = 自己赢）
var _brawl_t := 0.0
var _brawl_cd := 0.0
var _brawl_punch := 0.0
var _brawl_hop := 0.0
var _brawl_n := 0
var _brawl_c := Vector3.ZERO      # 现在在哪儿对打（两人中间）
var _brawl_home := Vector3.ZERO   # 开打的地方（闪来闪去不离它太远）
var _brawl_cam := Vector3.ZERO    # 镜头盯的点（缓缓跟，不跟着每一闪甩）
var _brawl_axis := Vector3.FORWARD
var _brawl_from := Vector3.ZERO   # 换位冲刺：从哪儿
var _brawl_to := Vector3.ZERO     # 　　　　　到哪儿
var _brawl_mv := -1.0             # 　　　　　已经冲了多久（秒）；< 0 = 没在换位
var _brawl_gh := 0.0              # 冲刺途中离下一道残影还有多久
var _clash_to := Vector3.INF  # 对波开场要退到的位置（脚底），INF = 不用动
var _clash_setup := 0.0       # 开场拉开还剩多久
var _whiff_lock := false      # 这一招有目标却打空了（被瞬身闪开 / 对方无敌 / 够不着）：不能接下一段，得等收招
var demo_dash := false        # 演示用：当作按住了「闪」（御风突进）
var _swap_at := -10.0         # 最近一次自己瞬移换位的时刻（_clock）：这之后一小会儿连段还在打，镜头就一直按住不转
## 护体受击滑退（2026-11-20）：护体挡下一击不再原地罚站 —— 被这一下的力道推着往后滑（重手滑得远，
## 连着挡下几下会被一下下推着退），接触点荡开一圈空气波动，滑退途中身后的空气被挤开一串小波纹，上身往后一仰再回来
const GSLIDE_LIGHT := 7.0     # 轻击推出去的初速（米 / 秒），再乘对方境界的击退档位（轻击吃三分之一、重手吃六成）
const GSLIDE_HEAVY := 13.0    # 　结丹挡一下轻击约滑 0.8 米、重手约 2 米；大乘的对手约 1 米 / 3.5 米
const GSLIDE_STACK := 0.6     # 这么久内连着挡下：一下比一下推得狠（每下多一成，最多三成）
var _gslide := Vector3.ZERO   # 护体滑退的速度
var _gs_rate := 8.0           # 滑退速度每秒衰减的比例（e 指数）
var _gs_wake := 0.0           # 离下一圈尾迹波纹还有多久
var _gs_rings := 0            # 这一次滑退已经放了几圈尾迹
var _g_lean := 0.0            # 受击后仰（弧度，叠在整身俯仰上）
var _g_hits := 0              # 连着挡下了几下
var _g_last := -10.0
var guard_slid := 0.0         # 自检用：最近一次护体滑退一共滑了多远（米）
## 远处的目标按下「攻」（2026-11-21）：先别冲 / 瞬身，看是点按还是长按 —— 松手（点按）才冲过去连打，按满 HOLD_T 就原地蓄力，
## 松手时高速飞过去一记重击（_start_smash 的冲刺段，远了飞得更快）。以前一按就冲 / 炼虚起一按就缩地瞬移，长按根本蓄不起来
var _pend_far := false
const SMASH_FLY_SPD := 150.0  # 蓄力重击飞过去的最高速度（米 / 秒）：近了 78，远了往上加，路上不超过 SMASH_FLY_T 秒
const SMASH_FLY_T := 0.32
var _sm_fly_max := 0.3        # 这一记冲刺段最多冲多久
var _sm_fly_far := false      # 这一记是远距离飞过去的（沿途残影更密、到位一圈气浪）
## 对波 / 拳劲对拼进行中（2026-11-21）：中途被别的操作打断（剑诀、开大、瞬身、转遁光、落地…）时 tick 里收干净、镜头交还
var _clash_live := false
## 拳劲对拼撞出的空间裂缝档位（2026-11-21，用户：「元婴以上修士对拳的时候需要一点空间裂缝的效果，等级越高效果越强」）：
## 元婴 1 … 大乘 5，结丹及以下 0 不裂；看对拼双方里境界高的那个。每隔 CRACK_EVERY[档] 拳裂一道，开打 / 换位对撞 / 分胜负各一道大的
const CRACK_EVERY := [0, 6, 4, 3, 3, 2]
var _brawl_ct := 0
var legacy_guard := false     # 自检对比用：true = 改之前的护体受击（速度加到身上、随即被平时的慢移吃掉）


func _ready() -> void:
	rig = player.melee.rig


## 2026-11-24 英雄系统：换上这位英雄的招式表（空表 = 回到老规矩：air_moves.gd 的那套）
func apply_hero(d: Dictionary) -> void:
	_hero_moves = d.get("moves", {})
	_chain_base = d.get("chain", Moves.CHAIN) if not d.is_empty() else Moves.CHAIN
	_chain_awake = d.get("chain_awake", [])
	ATK = _chain_awake if awake_t > 0.0 and not _chain_awake.is_empty() else _chain_base
	JUG = d.get("juggle", Moves.JUGGLE) if not d.is_empty() else Moves.JUGGLE
	var sm: Dictionary = d.get("smash", {})
	SMASH = sm if not sm.is_empty() else Moves.SMASH
	_derive = d.get("derive", {"up": "d_up", "down": "d_dn", "side": "d_fl"}) if not d.is_empty() else {"up": "d_up", "down": "d_dn", "side": "d_fl"}
	_ctr_id = str(d.get("counter", "ctr"))
	_dash_id = str(d.get("dash_move", "dash"))
	_follow_k = float(d.get("follow_k", 0.2))
	_no_swords = bool(d.get("no_swords", false))
	_rush_r = float(d.get("rush_r", 0.0))
	_awake_dur = float(d.get("awake_dur", AWAKE_DUR))
	_hero_flair = int(d.get("flair", -1)) if not d.is_empty() else -1
	var sc: Array = d.get("skill_cd", [])
	skill_cd = sc if sc.size() == 3 else SKILL_CD
	parry_t = 0.0
	_parry_dom = false
	if state == A.ATTACK or state == A.SMASH or state == A.RUSH or state == A.DASH or state == A.CHARGE:
		_to_idle()
	_last_id = ""


## 招式数据：英雄表里的优先（新增的招式、或者覆盖了老招式数值的），没有就是 air_moves.gd 的
func _mv(id: String) -> Dictionary:
	if _hero_moves.has(id):
		return _hero_moves[id]
	return Moves.MOVES.get(id, Moves.MOVES["l1"])


## 姿势名按英雄换（持剑的英雄：通用的空战待机 / 护体 / 蓄力换成拿剑的那套）
func _pose(name: String) -> String:
	return str(rig.remap.get(name, name))


## 有技能脚本、四个技能归它管的英雄（苍鸿）：「诀」那一格的名字 / 冷却 / 灵力问技能脚本
func _kit_z() -> Node:
	var k: Node = player.kit
	if k != null and is_instance_valid(k) and k.has_method("z_slot"):
		return k
	return null


# ---------- 查询 ----------

func busy() -> bool:
	return state != A.IDLE


## 由招式接管位移（Player._air 直接用 drive_vel）
func drives() -> bool:
	return _drives


func move_mul() -> float:
	return 0.35 if state == A.GUARD else 1.0


func guarding() -> bool:
	return state == A.GUARD


## 交战中：保持凌空架势、镜头锁定
func engaged() -> bool:
	return state != A.IDLE or _engage > 0.0


func charge_k() -> float:
	return clampf(_charge / CHARGE_FULL, 0.0, 1.0) if state == A.CHARGE else 0.0


## 正朝 e 冲过去（对手据此决定要不要护体）
func rushing_at(e: Node3D) -> bool:
	return target == e and (state == A.RUSH or state == A.DASH or (state == A.SMASH and _sm_dash))


func can_blink() -> bool:
	if state == A.GRABBED or state == A.BRAWL or (state == A.THROW and _throw_ph == 1) or (state == A.STOMP and _stomp_ph == 0):
		return false
	if _whiff_pen > 0.0 and (state == A.ATTACK or state == A.SMASH) and _whiff:
		return false      # 真人对打：打在保护中的人身上，这一下的收招取消不了
	return not (state == A.BLOWN and _t < _tech_t()) and state != A.CLASH and state != A.DOWN and state != A.CRUSH and state != A.DEAD


## 正在连点「攻击」较劲（对波 / 拳劲对拼 / 被擒住挣脱）：触屏的「攻」按钮据此换成「连点」
func mash_prompt() -> bool:
	return state == A.CLASH or state == A.BRAWL or state == A.GRABBED


func in_brawl() -> bool:
	return state == A.BRAWL


func brawl_u() -> float:
	return _brawl_u


## 正在蓄力、对着 e（对手据此决定抢攻 / 躲开）
func charging_at(e: Node3D) -> bool:
	return state == A.CHARGE and target == e


## 正朝 e 出招 / 冲过去 / 蓄力（对手据此决定这会儿要不要起手）
func attacking(e: Node3D) -> bool:
	return target == e and (state == A.ATTACK or state == A.SMASH or state == A.RUSH or state == A.DASH or state == A.CHARGE)


## 露着破绽（对手据此压上来）：被破防、聚气中、招式打空了正在收招
func is_open() -> bool:
	return state == A.CRUSH or state == A.GATHER or ((state == A.ATTACK or state == A.SMASH) and _whiff)


## 挨打硬直中、还有罡气：按「御」可以挣脱（触屏按钮据此换字）
func can_burst() -> bool:
	return state == A.HURT and burst >= 1.0 and player.st == Player.St.AIR


## 瞬身之后的反击窗口还开着
func counter_ready() -> bool:
	return _clock <= _counter_until and _alive(target) and (state == A.IDLE or state == A.GUARD)


## 这会儿按「攻」出的是投技：空手、摇杆后拉着、能擒的目标就在跟前（触屏按钮据此换字）
func throw_ready() -> bool:
	if state != A.IDLE and state != A.GUARD:
		return false
	if not _alive(target) or not target.has_method("grab_by") or _is_launched(target) or _stick_dir() != "down":
		return false
	return Proj.aim_of(target).distance_to(player.center()) - _gap(target) <= Moves.THROW_R


## 有被打飞的目标可以追（触屏按钮据此换字）
func chase_ready() -> bool:
	return _is_launched(_launched) and not _reach(_launched) and _can_chase() \
			and (state == A.IDLE or state == A.GUARD or ((state == A.ATTACK or state == A.SMASH) and _hit_done) or _threw())


## 刚把人甩出去、还在收招：这会儿可以直接接追击
func _threw() -> bool:
	return state == A.THROW and _throw_ph == 2 and not _whiff


## 此刻按下「御」/「闪」能瞬身：有对手的攻击马上就要打到自己（触屏按钮的提示圈）
func vanish_cue() -> bool:
	if player.st != Player.St.AIR or state == A.HURT or state == A.CRUSH or state == A.DOWN or state == A.CLASH:
		return false
	if player.mp < Moves.VANISH_MP:
		return false
	var win := Moves.vanish_window(_vanish_count())
	for n: Node in player.get_tree().get_nodes_in_group("air_foes"):
		if n.has_method("time_to_hit") and float(n.call("time_to_hit")) <= win:
			return true
	return false


func _vanish_count() -> int:
	return _vanish_n if _clock - _vanish_last <= Moves.VANISH_KEEP else 0


func is_blown() -> bool:
	return state == A.BLOWN


func in_clash() -> bool:
	return state == A.CLASH


func clash_u() -> float:
	return _clash_u


## 对波此刻的优势：-1 对手压着 ~ 1 自己压着（两边出剑的疏密看这个）
func clash_adv() -> float:
	return _clash_adv if state == A.CLASH else 0.0


func clash_point() -> Vector3:
	if is_instance_valid(_clash_foe):
		return _hand_point().lerp(_clash_foe.clash_origin(), _clash_u)
	return _hand_point()


## 倒地程度 0~1（Player 据此把身体放低贴到地面）
func lie_k() -> float:
	return _lie


## 对波时自己这一头（身前一点）
func _hand_point() -> Vector3:
	return player.center() + _beam_dir * 0.95 + Vector3.UP * 0.2


func state_name() -> String:
	match state:
		A.RUSH:
			return "追身突进"
		A.ATTACK:
			return _atk["name"]
		A.CHARGE:
			return "蓄力 %d%%" % int(charge_k() * 100.0)
		A.SMASH:
			return ("瞬身追击·" if _chase else "") + str(SMASH[_smash_kind]["name"])
		A.GUARD:
			return "护体罡气"
		A.HURT:
			return "受击"
		A.BLOWN:
			return "被击飞"
		A.CLASH:
			return "飞剑对波"
		A.GATHER:
			return "聚气"
		A.DOWN:
			return "坠地"
		A.DASH:
			return "追身" if _dash_homing else "御风突进"
		A.CRUSH:
			return "破防"
		A.DEAD:
			return "陨落"
		A.THROW:
			return "擒拿" if _throw_ph == 0 else ("抡摔" if _throw_ph == 1 else "收招")
		A.GRABBED:
			return "被擒"
		A.BRAWL:
			return "拳劲对拼"
		A.STOMP:
			return "坠星踏"
	return "觉醒" if awake_t > 0.0 else ""


func skill_name(i: int) -> String:
	var kz := _kit_z()
	if kz != null:
		return str(kz.call("z_slot", "name"))
	return (Realm.art_info(player.realm)["stages"] as Array)[i]


func skill_cost(i: int) -> float:
	var kz := _kit_z()
	if kz != null:
		return float(kz.call("z_slot", "mp"))
	return player.mp_max() * float(SKILL_COST[i])


func skill_ready(i: int) -> bool:
	var kz := _kit_z()
	if kz != null:
		return bool(kz.call("z_slot", "ready"))
	return cds[i] <= 0.0 and player.mp >= skill_cost(i)


## 整身姿态（Player 设到 spin 节点上）：招式里的俯仰 / 自转 / 侧滚 + 朝目标的仰俯 + 被击飞的翻滚
func spin_euler() -> Vector3:
	var p := rig.cur
	var w := rig.w_leg
	return Vector3((-float(p["bp"]) + _aim_pitch) * w - _tumble + 1.45 * _lie + _g_lean, float(p["by"]) * w + _spin_y, float(p["br"]) * w)


func _col() -> Color:
	return Realm.line_color(player.realm)


func _base() -> float:
	return float(player.realm["dmg"]) * (AWAKE_DMG if awake_t > 0.0 else 1.0)


static func _now() -> float:
	return Combat.now()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _fwd() -> Vector3:
	return Basis(Vector3.UP, face_yaw) * Vector3.FORWARD


## t 可能是已经释放的节点（搜打撤的怪死后即释放），所以不标类型、先验有效
func _alive(t: Variant) -> bool:
	return is_instance_valid(t) and Proj.alive(t)


## 对方是真人玩家（联机里别人在本机的木偶）：真人对打的规则只对他们生效
func _pvp(t: Variant) -> bool:
	return not pvp_legacy and is_instance_valid(t) and (t as Object).has_method("pvp_peer")


## 真人对打：有玩家正朝自己近身出手（remote_player.gd 收到起手预告时调）—— 算进入交战：
## 触屏按钮的提示（「御」的瞬身圈）只在交战中才画，开场第一下也得看得见；手上没目标就把他当目标（护体会朝着他）
func note_threat(src: Node3D) -> void:
	if player.st != Player.St.AIR or player.dead or state == A.DEAD:
		return
	_engage = ENGAGE_KEEP
	if not _alive(target):
		target = src


## 起身 / 受身 / 脱身后的保护还开着（谁也打不到；自己一出手就结束）
func protected() -> bool:
	return _prot > 0.0


## 被真人连着打、被打飞了，这会儿按「闪」就是受身（触屏按钮据此换字）
func tech_ready() -> bool:
	return _pc_live and state == A.BLOWN and _t >= _tech_t()


func _tech_t() -> float:
	return Moves.pvp_tech(_pc_launch) if _pc_live else 0.22


## 给联机状态包的几位（net.gd 拼进 flags）：位 3 = 正被打飞
func pvp_flags() -> int:
	var f := 8 if state == A.BLOWN and _blown_launch and not pvp_legacy else 0
	# 2026-11-24 英雄系统：位 4 = 重伤倒地（木偶趴下），位 5 = 觉醒中（苍鸿的木偶剑身发光）
	if player.is_downed():
		f |= 16
	if awake_t > 0.0:
		f |= 32
	return f


## 真人对打：近身的灵力（觉醒中不耗）。不够返回 false
func _pvp_pay(mp: float) -> bool:
	if awake_t > 0.0:
		return true
	if player.mp < mp:
		return false
	player.mp = maxf(player.mp - mp, 0.0)
	player.caster.hold_regen()
	return true


## 真人对打：从远处近身（动身 / 现身的那一刻记下来），下一招是「起手」
func _open_begin() -> void:
	_opener = true
	_open_at = _now()


## 真人对打：告诉对面「我这一下 lead 秒后判定」（他那边木偶立刻到位、拳上闪一下、「御」按钮亮圈）
func _pvp_notice(lead: float) -> void:
	player.melee.combat_event.emit("air_opener", {"to": target, "lead": lead, "pos": player.global_position})


## 真人对打：起手这一招开始了 —— 从动身 / 现身到判定不足 PVP_OPEN_T 的，差多少就先摆着架势按住多少。返回要按住多久
func _open_take(hit_t: float) -> float:
	if not _opener:
		return 0.0
	_opener = false
	if not _pvp(target):
		return 0.0
	var hold := maxf(Moves.PVP_OPEN_T - (_now() - _open_at) - hit_t, 0.0)
	_open_end = _now() + hold
	pvp_stat["openers"] = int(pvp_stat["openers"]) + 1
	_pvp_notice(hold + hit_t)
	return hold


## 真人对打：被打中一下，记进这一套连段。返回这一下的硬直倍率（挨得越多越短）；这一套到头了就定下自动脱身的时刻
func _pvp_took(src: Variant, launch: bool) -> float:
	_blown_launch = launch
	if not _pvp(src):
		return 1.0
	var now := _now()
	_pc_last = now
	if not _pc_live:
		_pc_live = true
		_pc_n = 0
		_pc_launch = 0
		_pc_t0 = now
		_pc_beat = -10.0
		_pc_escape = -1.0
		pvp_stat["combos"] = int(pvp_stat["combos"]) + 1
	_pc_idle = 0.0
	var k := Moves.pvp_stun(_pc_n)
	if now - _pc_beat >= Moves.PVP_BEAT:
		_pc_beat = now
		_pc_n += 1
	pvp_stat["max_hits"] = maxi(int(pvp_stat["max_hits"]), _pc_n)
	if launch:
		_pc_launch += 1
		k = Moves.pvp_fly(_pc_launch)
	if _pc_escape < 0.0 and (_pc_n >= Moves.PVP_COMBO_HITS or now - _pc_t0 >= Moves.PVP_COMBO_T or _pc_launch >= Moves.PVP_COMBO_LAUNCH):
		_pc_escape = Moves.PVP_ESCAPE_T
	return k


## 真人对打：这一套连段到头了（下数 / 时长 / 被打飞的次数），自动脱身 —— 稳住身形、身周一圈气浪，接着是一段保护
func _pvp_escape() -> void:
	pvp_stat["escapes"] = int(pvp_stat["escapes"]) + 1
	Combat.clear_hitstop()
	_push = Vector3.ZERO
	_tumble = 0.0
	var c := player.center()
	var col := _col()
	Vfx.shockwave(c, Vector3.UP, col, 1.6)
	Vfx.space_ring(c, 1.5, col, 0.32, 0.03)
	Sfx.play("perfect", -8.0, 1.25)
	_to_idle()
	if state == A.IDLE:
		rig.play("f_burst")
		_point_t = 0.3
	_protect(Moves.PVP_PROTECT)
	player.melee.combat_event.emit("air_tech", {})


## 真人对打：起身 / 受身 / 脱身 / 挣脱之后的保护 —— 这段时间谁也打不到自己，自己一出手就结束（tick 里）。
## 只在刚被真人打过时给（打怪 / AI 不变）；对面看得到（net.gd 转给 remote_player.gd 的 net_protect）
func _protect(sec: float) -> void:
	if pvp_legacy or _now() - _pc_last > Moves.PVP_RECENT:
		return
	_prot = maxf(_prot, sec)
	_pc_live = false
	_pc_escape = -1.0
	pvp_stat["protects"] = int(pvp_stat["protects"]) + 1
	player.melee.combat_event.emit("air_protect", {"t": _prot})


## 真人对打每帧的账：连段断没断、到头了没有、保护还剩多久（dt 真实秒）
func _tick_pvp(dt: float) -> void:
	if _pc_live:
		if state == A.HURT or state == A.BLOWN or state == A.DOWN or state == A.CRUSH or state == A.GRABBED:
			_pc_idle = 0.0
		else:
			_pc_idle += dt
			if _pc_idle > Moves.PVP_COMBO_GAP:
				_pc_live = false
	if _pc_escape >= 0.0:
		_pc_escape -= dt
		if _pc_escape <= 0.0:
			_pc_escape = -1.0
			if player.st == Player.St.AIR and (state == A.HURT or state == A.BLOWN or state == A.CRUSH):
				_pvp_escape()
			else:
				_pc_live = false      # 已经自己出来了 / 趴在坑里（起身时本来就有保护）
	if _prot > 0.0:
		_prot -= dt
		# 自己出手了：保护到此为止。拳脚是打出去（判定）的那一刻才结束（_resolve 里）—— 起身后的第一下是带着保护打出去的，
		# 对方还在闷头乱按就会被它打断；法术 / 投技 / 对波一动手就结束
		if state == A.THROW or state == A.STOMP or state == A.CLASH or state == A.BRAWL or player.caster.busy() or player.st != Player.St.AIR:
			_prot_end()
		elif _prot <= 0.0:
			_prot = 0.0


## 真人对打：保护提前结束（自己出手了），告诉对面
func _prot_end() -> void:
	if _prot > 0.0:
		_prot = 0.0
		player.melee.combat_event.emit("air_protect", {"t": 0.0})


## 2026-11-21：参数不标类型（同 _alive）——被打飞的怪死了会立刻释放，_launched 还指着它；标成 Node3D 时传进来就报错、整个 tick 中断，
## 空战连招 / 连发跟着全停（战斗数值实测 --pace-combat 里第一只木桩一释放就出现）
func _is_launched(t: Variant) -> bool:
	return _alive(t) and t.has_method("is_launched") and t.is_launched()


## 出手时自己的中心离目标中心多远。from = 自己打算站的那一侧（世界坐标；不给 = 现在站的地方）。
## 有身体表面的目标（大世界的怪，raid_mob.gd 的 body_reach）：站在表面外 GAP_BODY 米，拳脚刚好够着，身子不进模型；
## 其余（修士、木人、剑冢首领）照旧 = STICK + 体型半径
func _gap(t: Node3D, from := Vector3.INF) -> float:
	if t.has_method("body_reach"):
		return GAP_BODY + float(t.call("body_reach", player.center() if from == Vector3.INF else from))
	return STICK + Proj.body_r(t)


## 目标的身体表面离它的中心多远（命中特效落在表面上，不落在模型里面）
func _surf(t: Node3D, from: Vector3) -> float:
	if t.has_method("body_reach"):
		return float(t.call("body_reach", from))
	return 0.3 + Proj.body_r(t)


# ---------- 输入 ----------

## 境界档位（空战从结丹起）：0 结丹 · 1 元婴 · 2 化神 · 3 炼虚 · 4 合体 · 5 大乘。档位越高连段越花：
##   元婴 每一下出手都拖残影
##   化神 连段第四下前瞬步绕到对手背后；重手带一道剑气弧光和漫画冲击帧
##   炼虚 追身突进变成缩地（直接闪到身前）；第三、四下前都瞬步换位；重手时分出一道分身从另一侧补一击
##   合体 每一下都瞬步换位；两道分身；重手撕开一道空间裂隙；收尾前先来四下乱舞（绕着对手连闪连斩）
##   大乘 三道分身；乱舞七下；收尾把人打飞后天上落一圈剑雨追击
func flair() -> int:
	if _hero_flair >= 0:
		return _hero_flair      # 2026-11-24 英雄档：花样档由英雄表定（御剑 / 苍鸿都是 1：残影 + 重手一圈空间波动，没有分身乱舞）
	return clampi(player.realm_idx - 2, 0, 5)


## 这个境界的战斗表现档位（Realm.COMBAT）：命中特效多大、击飞多远、顿帧 / 震动多重、对波出多少剑
func _prof() -> Dictionary:
	return Realm.combat(player.realm_idx)


## 击退 / 击飞速度随境界的倍率：重手和击飞全吃，轻击只吃三分之一（轻击把人推太远，下一拳就够不着了）
func _kbm(full: bool) -> float:
	var k: float = _prof()["kb"]
	return k if full else lerpf(1.0, k, 0.34)


## 从地面按键直接升空进来（player_melee.gd 调）：attack = 攻击键，否则是格挡键
func press_from_ground(attack: bool) -> void:
	_ground_frame = Engine.get_process_frames()
	if attack:
		press_attack()
	else:
		press_guard()


func _unhandled_input(e: InputEvent) -> void:
	if player.dead:
		if e.is_action_released("guard"):
			guard_held = false
		return
	if player.st != Player.St.AIR:
		return
	if _ground_frame == Engine.get_process_frames() and (e.is_action_pressed("attack") or e.is_action_pressed("guard")):
		return  # 这个按键刚由地面那边转交过来处理过了
	if e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # 这一下是用来抓鼠标的
	if player.ult.active and not e.is_action_released("guard"):
		return
	if e.is_action_pressed("attack"):
		press_attack()
	elif e.is_action_pressed("guard"):
		press_guard()
	elif e.is_action_released("guard"):
		release_guard()
	elif e.is_action_pressed("gather") and player.hero_id != "" and press_awaken():
		pass              # 2026-11-25 英雄档：觉醒槽满了点一下 V / 「觉」就觉醒
	elif e.is_action_pressed("air_shot") and player.hero_id == "":
		press_shot()      # 英雄档下 E / Z 归技能脚本（player.gd 转给 kit）
	elif e.is_action_pressed("skill_next") and player.hero_id == "":
		press_art()


func press_attack() -> void:
	if player.st != Player.St.AIR or player.ult.active or player.dead:
		return
	if state == A.CLASH:
		_clash_tap()
		return
	if state == A.BRAWL:
		_brawl_tap()
		return
	if state == A.GRABBED:
		_grab_tap()
		return
	if warn_k() > 0.0 and _accept_clash():
		return
	if _try_swat():
		return                            # 气弹快打到身上了：这一下是反手抽回去
	_buf_at = _now()
	_hold_used = false
	if _consume():
		_buf_at = -10.0


func _consume() -> bool:
	if player.caster.channeling or player.is_dashing():
		return false
	match state:
		A.IDLE, A.GUARD:
			if counter_ready():
				_start_counter()          # 刚瞬身到对手背后：瞬身反击
			elif otg_ready():
				_start_stomp()            # 对手被砸进地里了：俯冲下去补一脚
			elif _is_launched(_launched) and _reach(_launched):
				_start_juggle()           # 被打飞的对手就在身前：空中连击
			elif _can_chase():
				_start_chase()            # 被打飞的对手在远处：瞬身追击
			else:
				_begin_combo()
			return true
		A.DASH:
			_dash_atk = true              # 御风突进途中：到位即出冲刺攻击
			return true
		A.RUSH:
			return true
		A.ATTACK:
			if otg_ready():
				_start_stomp()            # 打下去的人已经砸进地里了：直接俯冲补一脚
				return true
			if _hit_done and _atk.has("launch"):
				# 这一下把人打飞了：再按 = 瞬身追击
				if _can_chase():
					_start_chase()
					return true
				return false
			if _whiff_lock:
				return false      # 打空了：连不下去（按键留在缓冲里，收招后从头起手）
			if _t >= float(_atk["hit"]) - 0.04:
				var nid := _next_id()
				if nid != "":
					_queued = true
					_queued_id = nid
					return true
		A.SMASH:
			if otg_ready():
				_start_stomp()
				return true
			if _hit_done and _can_chase():
				_start_chase()
				return true
		A.THROW:
			if _threw() and _can_chase():
				_start_chase()        # 甩出去了：再按 = 瞬身追击
				return true
	return false


## 摇杆此刻推向哪边："" 没推 / up 前 / down 后 / side 左右
func _stick_dir() -> String:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if iv.length() < 0.5:
		return ""
	if absf(iv.x) > absf(iv.y):
		return "side"
	return "up" if iv.y < 0.0 else "down"


## 点按攻击接哪一招（"" = 接不了）。空中连击顺着 j1 → j2 → j3 → 终结重击（"fin"）；
## 轻击第二段起看摇杆方向出派生：前 = 挑月 · 后 = 坠星（贴地时改挑月）· 左右 = 绕身击
func _next_id() -> String:
	var nxt := str(_atk.get("next", ""))
	if JUG.has(move_id):
		return nxt if nxt != "" else "fin"
	if nxt == "" or move_id == ATK[0] or not _alive(target) or _is_launched(target) or bool(_atk.get("auto", false)):
		return nxt
	var d_up := str(_derive.get("up", "d_up"))
	var d_dn := str(_derive.get("down", "d_dn"))
	var d_fl := str(_derive.get("side", "d_fl"))
	match _stick_dir():
		"up":
			return d_up
		"down":
			return d_up if _near_floor(target) else d_dn
		"side":
			if move_id != d_fl and player.mp >= float(_mv(d_fl).get("mp", 0.0)):
				_flank = 1.0 if Input.get_axis("move_left", "move_right") >= 0.0 else -1.0
				return d_fl
	return nxt


func _floor_at(p: Vector3) -> float:
	var cam := player.cam
	return float(cam.floor_fn.call(p.x, p.z)) if cam.floor_fn.is_valid() else 0.0


func _near_floor(t: Node3D) -> bool:
	var c := Proj.aim_of(t)
	return c.y - _floor_at(c) < 3.0


func press_guard() -> void:
	guard_held = true
	if player.st != Player.St.AIR or player.is_dashing() or player.dead:
		return
	if state == A.HURT:
		if burst >= 1.0 and not player.ult.active:
			_burst()                      # 挨打硬直中：挣脱
		return
	if state == A.GRABBED:
		if burst >= 1.0:
			_grab_break(true)             # 被擒住：耗一格罡气直接震开
		return
	if state == A.BRAWL or state == A.THROW:
		return
	if try_vanish_press():
		return                            # 对手的攻击马上到：瞬身
	var ok := state == A.IDLE or state == A.RUSH or state == A.DASH
	if state == A.ATTACK:
		# 取消窗口：判定打完之后的后摇，或刚起手还没打出去的一瞬间
		ok = (_t >= float(_atk.get("cancel", 99.0)) or _t < Moves.CANCEL_HEAD) and not (_whiff and _whiff_pen > 0.0)
	if not ok or player.caster.busy():
		return
	_end_blade()
	state = A.GUARD
	_t = 0.0
	_guard_at = _clock
	_engage = ENGAGE_KEEP
	rig.play("f_guard")
	Vfx.cast_flash(player.center() + _fwd() * 0.5, _col(), 0.8)


func release_guard() -> void:
	guard_held = false
	if state == A.GUARD:
		_to_idle()


## 护体一直按着、最近 1.5 秒没人打过自己：可以顺势聚气（一挨打就回到护体）
func _guard_gather() -> bool:
	if not guard_held or player.st != Player.St.AIR:
		return false
	if state != A.GUARD and state != A.GATHER:
		return false
	if _clock - _guard_at < GUARD_GATHER_T:
		return false
	# 有对手正要出手、或者有气弹正朝自己飞过来：护体别自己松成聚气
	var pc := player.center()
	for n: Node in player.get_tree().get_nodes_in_group("air_foes"):
		if n.has_method("time_to_hit") and float(n.call("time_to_hit")) < 5.0:
			return false
		if n.has_method("bolt_eta") and float(n.call("bolt_eta", pc)) < 3.0:
			return false
	var now := Combat.now()
	for k: Variant in player.threat.keys():
		if now - float(player.threat[k]) < 1.5:
			return false
	return true


## E 点按：一柄追踪飞剑
func press_shot() -> void:
	if _accept_clash():
		return
	if counter_ready() and _counter_blast():
		return                            # 刚瞬身到对手背后：贴脸一轮飞剑
	if otg_ready() and _start_rain():
		return                            # 对手趴在坑里：往坑里灌一轮剑雨
	if player.st != Player.St.AIR or player.is_dashing() or player.caster.busy() or player.dead:
		return
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH or state == A.CRUSH:
		return
	if _shot_cd > 0.0 or player.mp < SHOT_MP:
		return
	_prot_end()
	player.mp -= SHOT_MP
	player.caster.hold_regen()
	_shot_cd = SHOT_CD
	_shot_n += 1
	_engage = ENGAGE_KEEP
	var aim := _aim()
	var tgt: Node3D = aim[0]
	var pt: Vector3 = aim[1]
	if state == A.IDLE:
		var d := pt - player.global_position
		if _flat(d).length() > 0.2:
			face_yaw = atan2(-d.x, -d.z)
			has_face = true
		rig.play("f_point")
		_point_t = 0.3
	var side := -1.0 if _shot_n % 2 == 0 else 1.0
	var from := player.global_position + Basis(Vector3.UP, face_yaw) * Vector3(0.85 * side, randf_range(1.7, 2.2), 0.7)
	var art := Realm.art(player.realm)
	Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
			{"dmg": _base() * 0.4, "color": _col(), "speed": 78.0, "hold": 0.05, "turn": 12.0,
			 "straight": tgt == null, "art": art, "tw": 0.1, "trauma": 0.02, "life": 1.4})
	Vfx.cast_flash(from, _col(), 0.6)
	player.cam.add_trauma(0.02)


## Z / X / C：三式剑诀
## 「诀」这一下会放第几式：从轮到的那一式起，按顺序找第一个冷却好、灵力够的；都不行就还是轮到的那一式
func next_skill() -> int:
	for k in 3:
		var i := (_art_next + k) % 3
		if skill_ready(i):
			return i
	return _art_next


## 「诀」（Z）：三式剑诀合成一个键，每按一次按顺序放下一式（一 → 二 → 三 → 一 …），轮到的那式还在冷却就顺延
func press_art() -> void:
	if counter_ready() and _counter_blast():
		return
	var i := next_skill()
	if press_skill(i):
		_art_next = (i + 1) % 3


## 「诀」按钮上显示的冷却比例（0 = 可用）。三式共用冷却，按这一轮的总长算
func art_cd() -> float:
	var kz := _kit_z()
	if kz != null:
		return float(kz.call("z_slot", "cd"))
	return clampf(cds[0] / maxf(cd_full, 0.01), 0.0, 1.0)


func press_skill(i: int) -> bool:
	if player.st != Player.St.AIR or player.is_dashing() or player.caster.busy() or player.dead:
		return false
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH or state == A.RUSH or state == A.DASH or state == A.CRUSH:
		return false
	if state == A.CLASH or state == A.BRAWL or state == A.GRABBED or state == A.THROW or state == A.DEAD:
		return false      # 对波 / 对拼 / 擒拿是较劲：靠连点分胜负，剑诀放不出来（以前会直接把对波打断，镜头还停在对波的机位上）
	if state == A.ATTACK and not _hit_done:
		return false
	if not skill_ready(i):
		Sfx.play("block", -12.0, 0.7)
		return false
	player.mp -= skill_cost(i)
	cd_full = float(skill_cd[i])
	for k in 3:
		cds[k] = cd_full
	_end_blade()
	state = A.IDLE
	_engage = ENGAGE_KEEP
	rig.play("f_idle")
	player.caster.cast_skill(i)
	player.melee.combat_event.emit("air_skill", {"idx": i, "name": skill_name(i)})
	# 第三式原来出手前会切一个侧前方低机位的特写、再带一下慢动作（_cine_skill）：2026-11-20 用户说效果不好，去掉了，
	# 镜头全程留在跟随机位上。
	return true


## 演示 / 自检：直接蓄一记重击（kind：fwd / up / down），hold 秒后自动打出
func demo_heavy(kind: String, hold := 0.5) -> void:
	_smash_kind = kind
	_start_charge()
	_auto_release = hold


# ---------- 目标 ----------

## [目标或 null, 瞄准点]：交战中的目标优先，否则取准星附近的
func _aim() -> Array:
	if _alive(target):
		return [target, Proj.aim_of(target)]
	return player.caster._pick()


func _pick_target() -> Node3D:
	var cam := player.cam
	if _alive(cam.lock) and Proj.aim_of(cam.lock).distance_to(player.center()) <= RUSH_R + Proj.body_r(cam.lock):
		return cam.lock
	# 统一索敌：先找正在打我的，再找最近的
	return Proj.pick_target(player, RUSH_R, target)


## 目标身前的出手位置（脚底坐标）：沿 from_dir（自己 → 目标的水平方向）退开 gap，高度对齐
func _stick_point(t: Node3D, dir: Vector3) -> Vector3:
	var tc := Proj.aim_of(t)
	var p := tc - dir * _gap(t, tc - dir * 10.0)
	p.y = maxf(p.y - BODY_Y, 0.0)
	return p


func _dir_to(t: Node3D) -> Vector3:
	var d := _flat(Proj.aim_of(t) - player.center())
	return d.normalized() if d.length_squared() > 0.01 else _fwd()


# ---------- 起手 ----------

func _begin_combo() -> void:
	target = _pick_target()
	_engage = ENGAGE_KEEP
	var id := _link_id()
	if target == null:
		face_yaw = player.cam.yaw
		has_face = true
		_start_move(id)
		return
	var dist := Proj.aim_of(target).distance_to(player.center()) - _gap(target)
	# 摇杆后拉 + 攻（空手起手、目标就在跟前）：投技「擒拿抡摔」，护体挡不住
	if dist <= Moves.THROW_R and _stick_dir() == "down" and target.has_method("grab_by") and not _is_launched(target):
		_start_throw()
		return
	if dist > MAGNET:
		if _pvp(target) and _is_launched(target):
			# 真人对打：被打飞的人只能用「追击」去接（耗灵力、一套最多 CHASE_MAX 次）；追不了就够不着，这一下原地挥空
			_start_move(id)
			_rooted = true
			return
		if Input.is_action_pressed("attack") and not _hold_used:
			# 远处的目标、键还按着：先面向它等一等 —— 松手 = 点按，冲过去（tick 里）；按满 HOLD_T = 转蓄力
			_pend_far = true
			_face_target()
			return
		_start_rush()
	else:
		_start_move(id)


## 连招窗口：上一招收招后 LINK 秒内再按，接着它的下一段打；否则从 M1 第一段起
## 2026-11-24 修（复核 combat-6）：看「下一招」在不在这张 M1 表里，而不是看上一招 —— 绕身击 → l5、破空蹬 → l3
## （苍鸿 绕身斩 → k4、破风刺 → k3）这些派生 / 冲刺招本身不在表里，但收招后补按照旧接回连段（和改之前一样）；
## 技能招的 next（瞬狱 / 断月 / 千刃……）、觉醒结束后残留的 ka3 → ka4 都不在表里，不会被接上
func _link_id() -> String:
	var id: String = ATK[0]
	if _clock - _last_end <= Moves.LINK and _last_id != "":
		var nx := str(_mv(_last_id).get("next", ""))
		if nx != "" and not JUG.has(nx) and ATK.has(nx):
			id = nx
	return id


## 还在飞的目标：按它的速度估出 lead 秒后的位置，自己保持现在相对它的方位贴上去（脚底坐标）。
## 不能像 _stick_point 那样只在水平面上找位置 —— 被挑飞的是竖着飞的，那样永远差一截
func _intercept_point(t: Node3D, lead: float) -> Vector3:
	var tv: Vector3 = t.velocity() if t.has_method("velocity") else Vector3.ZERO
	var tc := Proj.aim_of(t) + tv * (clampf(lead, 0.0, 0.2) + 0.03)
	var rel := tc - (player.global_position + Vector3(0.0, BODY_Y, 0.0))
	rel = rel.normalized() if rel.length_squared() > 0.01 else _fwd()
	var p := tc - rel * _gap(t, tc - rel * 10.0) - Vector3(0.0, BODY_Y, 0.0)
	p.y = maxf(p.y, 0.0)
	return p


## 目标在身前够得着的地方（空中连击不用再瞬移过去）
func _reach(t: Node3D) -> bool:
	return _alive(t) and Proj.aim_of(t).distance_to(player.center()) - _gap(t) <= REACH


func _juggled(t: Node3D) -> bool:
	return _alive(t) and t.has_method("is_juggled") and bool(t.call("is_juggled"))


## 空中连击：被打飞 / 浮空的对手就在身前
func _start_juggle() -> void:
	target = _launched
	var id: String = JUG[0]
	if _clock - _last_end <= Moves.LINK and JUG.has(_last_id):
		id = str(_mv(_last_id).get("next", ""))
		if id == "":
			_start_finisher()
			return
	_start_move(id)


## 终结重击：空中连击的收尾，把浮空的对手再打飞出去。摇杆定去向（不推就按 前 → 上 → 下 轮着来）；
## 追击次数用完的那一下固定往下砸
func _start_finisher() -> void:
	var kind: String = {"fwd": "up", "up": "down", "down": "fwd"}.get(_launch_kind, "fwd")
	kind = _read_kind(kind)
	if _chase_n >= CHASE_MAX and _alive(target) and not _near_floor(target):
		kind = "down"
	if kind == "down" and _alive(target) and _near_floor(target):
		kind = "up"       # 贴近地面就别再往下砸
	_chase = true
	Combat.clear_hitstop()
	_start_smash(kind, 0.6, false)


## 瞬身反击：瞬身闪到对手背后之后的那一击（破防、击飞）
func _start_counter() -> void:
	_counter_until = -10.0
	Combat.slowmo_release(0.12)
	if not _reach(target):
		_flash_step(PI)
	_start_move(_ctr_id)
	player.cam.fov_punch(6.0)
	player.melee.combat_event.emit("air_counter", {})


func _start_rush() -> void:
	if _rush_r > 0.0 and _alive(target) and Proj.aim_of(target).distance_to(player.center()) - _gap(target) > _rush_r:
		# 2026-11-25 英雄档：太远了不自动冲过去（要靠「闪」/ 技能近身）—— 朝着它原地出手
		_start_move(_link_id())
		_rooted = true
		return
	var step := flair() >= 3 and _alive(target)
	var pv := _pvp(target)
	if pv:
		# 真人对打：近身要花灵力（缩地更贵，不够就退成冲过去）；都不够就近不了身，这一下原地挥空
		if step and _pvp_pay(Moves.PVP_STEP_MP):
			pass
		elif _pvp_pay(Moves.PVP_RUSH_MP):
			step = false
		else:
			pvp_stat["no_mp"] = int(pvp_stat["no_mp"]) + 1
			_start_attack(0)
			_rooted = true
			return
	if step:
		# 炼虚起：缩地，直接闪到对手身前出手
		_end_blade()
		_flash_step(0.0)
		player.cam.fov_punch(-3.0)
		if pv:
			_open_begin()      # 现身的这一刻起算前摇
		_start_attack(0)
		return
	_end_blade()
	state = A.RUSH
	_t = 0.0
	_ghost_t = 0.0
	rig.play("f_rush")
	var d := Proj.aim_of(target) - player.center()
	if pv:
		_open_begin()
		_pvp_notice(maxf(Moves.PVP_OPEN_T, d.length() / RUSH_SPD + float(_mv(ATK[0])["hit"])))      # 先按路程估一个，到位出手时再报准的
	Vfx.dash_start(player.center(), d.normalized(), _col(), 0.6)
	Sfx.play("dodge", -5.0, 1.15)
	player.cam.fov_punch(7.0)
	player.cam.kick_rush(0.9)


## 空间扭曲的一下脉冲（main.gd 会很快把它退掉）：k = 相对强度，实际强度还随境界涨
func _warp(pos: Vector3, k: float) -> void:
	var v := (WARP_BASE + WARP_STEP * float(player.realm_idx)) * k
	if v > Vfx.warp_k:
		Vfx.warp_pos = pos
		Vfx.warp_k = v


## 瞬步：原地留一道残影，人闪到「对手 → 自己」方向转过 ang 弧度后的那一侧（0 = 就在身前）
func _flash_step(ang: float, lift := 0.0) -> void:
	if not _alive(target):
		return
	var from := player.global_position
	var dir := _dir_to(target).rotated(Vector3.UP, ang)
	var cam := player.cam
	# 落点先过合法性检查（不贴地、不进地形、不穿墙）；找不到合法落点这一下就不换位
	var to := safe_spot(Proj.aim_of(target), _stick_point(target, dir) + Vector3.UP * lift)
	if to == Vector3.INF:
		return
	dir = _flat(Proj.aim_of(target) - to)
	dir = dir.normalized() if dir.length_squared() > 1e-4 else _fwd()
	var col := _col()
	var h := Vector3.UP * BODY_Y
	Vfx.vanish(from + h, col)
	Vfx.body_ghost(player.visual, Color.WHITE.lerp(col, 0.6), 0.55, 0.28)
	player.global_position = to
	player.velocity = Vector3.ZERO
	drive_vel = Vector3.ZERO
	_note_swap()
	Vfx.warp_line(from + h, to + h, col)
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	Sfx.play("dodge", -10.0, 1.5)
	cam.kick_rush(0.35)
	_warp(to + h, 0.6)    # 破开空间钻出来的地方微微一扭


## 自己刚瞬移换了位：镜头按住不转（camera_rig.gd 的 DUEL_HOLD），换位连段打完之前一直按着（_upkeep）
func _note_swap() -> void:
	_swap_at = _clock
	player.cam.duel_hold(CameraRig.DUEL_HOLD)


## 瞬移落点合不合法（p 为脚底坐标）：不出界、不低于地面、身体不嵌进地形 / 建筑，
## 和 pivot（要贴上去的那个对手的中心）之间没有东西挡着
func _legal(p: Vector3, pivot: Vector3) -> bool:
	if absf(p.x) > player.bound or absf(p.z) > player.bound:
		return false
	if p.y < _floor_at(p) + 0.6:
		return false
	var space := player.get_world_3d().direct_space_state
	if _probe == null:
		_probe = PhysicsShapeQueryParameters3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.5
		_probe.shape = sp
		_probe.collision_mask = 1
		_probe.exclude = [player.get_rid()]
	var c := p + Vector3(0.0, BODY_Y, 0.0)
	_probe.transform = Transform3D(Basis.IDENTITY, c)
	if not space.intersect_shape(_probe, 1).is_empty():
		return false
	var q := PhysicsRayQueryParameters3D.create(pivot, c, 1)
	q.exclude = [player.get_rid()]
	if not space.intersect_ray(q).is_empty():
		return false
	# 2026-11-24（复核 combat-3）新图没有物理碰撞体：落点的脚 / 腰 / 头不在墙、楼板、箱子、地形里，不顶到洞顶 / 楼板 / 飞行上限，
	# 和对手之间没有墙隔着（回风 / 剑域闪到身后、一闪穿身、瞬身、追击都走这里）。不是新图时 ex_level() 为 null，照旧
	var lv := player.ex_level()
	if lv != null:
		if p.y > float(lv.call("y_cap", p)) + 0.05:
			return false
		for hy: float in [0.3, BODY_Y, 1.75]:
			if bool(lv.call("solid_at", p + Vector3(0.0, hy, 0.0))):
				return false
		if player.solid_hit(pivot, c, 0.4, 0.3, 0.0) != Vector3.INF:
			return false
	return true


## 给瞬移找一个合法落点（脚底坐标）：先试想去的位置，不行就绕着 pivot 换角度、再抬高了试；
## 都不行返回 Vector3.INF（这次不瞬移）。主角和空战对手的所有瞬移（瞬步 / 瞬身 / 追击 / 绕身）都走这里
func safe_spot(pivot: Vector3, want: Vector3) -> Vector3:
	var off := want + Vector3(0.0, BODY_Y, 0.0) - pivot
	for lift: float in [0.0, 1.4, 2.8]:
		for ang: float in [0.0, 0.7, -0.7, 1.4, -1.4, 2.2, -2.2, PI]:
			var p := pivot + off.rotated(Vector3.UP, ang) + Vector3(0.0, lift - BODY_Y, 0.0)
			p.y = maxf(p.y, _floor_at(p) + 0.7)
			if _legal(p, pivot):
				return p
	return Vector3.INF


func _start_attack(s: int, chained := false) -> void:
	_start_move(ATK[s], chained)


## 出一招（air_moves.gd 里的招式名）。chained = 从上一招的连招窗口接过来的
func _start_move(id: String, chained := false) -> void:
	state = A.ATTACK
	move_id = id
	_atk = _mv(id)
	var ci := ATK.find(id)
	if ci >= 0:
		step = ci
	var s := step
	_t = 0.0
	_hit_done = false
	_queued = false
	_queued_id = ""
	_whiff = false
	_whiff_lock = false
	_whiff_pen = 0.0
	# 2026-11-24 修（复核 combat-2）：放飞行道具的招（断月 / 天斩 / 万剑归宗，英雄表 proj 字段）原地出手，不往目标身上吸 ——
	# 以前它们走拳脚那套吸附，36 米外的目标也会被一路拖过去（断月一次拖 20 米，万剑归宗直接贴脸）。老招式表里没有 proj，老规矩不变
	_rooted = _atk.has("proj") or bool(_atk.get("root", false))
	_open_hold = 0.0 if chained else _open_take(float(_atk["hit"]))
	_opener = false
	_engage = ENGAGE_KEEP
	_flurry_left = 0
	var cost: float = _atk.get("mp", 0.0)
	if cost > 0.0:
		player.mp = maxf(player.mp - cost, 0.0)
		player.caster.hold_regen()
	var fl := flair()
	if fl >= 1:
		Vfx.body_ghost(player.visual, Color.WHITE.lerp(_col(), 0.6), 0.35, 0.2)
	if bool(_atk.get("rear", false)) and _alive(target) and not _is_launched(target):
		_flash_step(PI * 0.9 * _flank)    # 绕身击：闪到对手侧后方，从背后打（护体挡不住）
	elif ci >= 0 and chained and _alive(target) and not _is_launched(target):
		# 连段里瞬步换位：境界越高换得越勤
		var ang := 0.0
		match fl:
			2:
				ang = PI if s == 3 else 0.0
			3:
				ang = [0.0, 0.0, 1.9, -2.5, 0.0][s]
			4, 5:
				ang = [0.0, 2.1, -2.1, PI, 1.3][s]
		if ang != 0.0:
			_flash_step(ang)
		if s == ATK.size() - 1 and fl >= 4:
			# 合体 / 大乘：收尾前先来一轮乱舞
			_flurry_left = 4 if fl == 4 else 7
			_flurry_cd = 0.0
			_flurry_n = 0
			player.cam.impact(0.6)
	if _open_hold > 0.0:
		rig.play("f_chg")       # 起手前摇：先摆着蓄势的架子，按够了再打出去（_tick_attack）
		_end_blade()
	else:
		rig.play(_atk["seq"])
		var sw: bool = _atk["limb"] == "sw"
		if sw:
			_blade_on()
			Vfx.glint(rig.hand_pos(), Color.WHITE.lerp(_col(), 0.4), 0.9)
		else:
			_end_blade()
		if player.hero_id != "" and not sw:
			Sfx.play("whoosh_fist", -6.0 if int(_atk["tier"]) >= 1 else -9.0, (0.85 if int(_atk["tier"]) >= 1 else 1.1) + 0.05 * s)
		else:
			Sfx.play("swing_heavy" if int(_atk["tier"]) >= 1 else "swing", -7.0, 1.15 + 0.07 * s)
	if _alive(target):
		var d := _dir_to(target)
		face_yaw = atan2(-d.x, -d.z)
		has_face = true
	_kit_fx("start", {})


## from_chain：连段里按住转过来的 —— 直接从 CHAIN_HEAD 起蓄，一松手就是一记够分量的重击
func _start_charge(from_chain := false) -> void:
	_pend_far = false
	_end_blade()
	state = A.CHARGE
	_t = 0.0
	_charge = CHARGE_FULL * Moves.CHAIN_HEAD if from_chain else 0.0
	_brk_cued = false
	_aura_t = 0.0
	_auto_release = -1.0
	_engage = ENGAGE_KEEP
	if target == null or not _alive(target):
		target = _pick_target()
	rig.play("f_chg")
	Vfx.cast_charge(player.center(), _col(), CHARGE_FULL)
	Sfx.play("ascend", -12.0, 1.6)
	player.cam.fov_punch(-4.0)


## 松手时读方向（和连段里的方向派生同一套）：摇杆前 / 空格 = 挑飞，后 = 陨落，不推 = fallback
func _read_kind(fallback: String) -> String:
	if Input.is_action_pressed("jump"):
		return "up"
	match _stick_dir():
		"up":
			return "up"
		"down":
			return "down"
	return fallback


func _release_charge() -> void:
	var k := clampf(_charge / CHARGE_FULL, 0.0, 1.0)
	var kind := _smash_kind if _auto_release >= 0.0 else _read_kind("fwd")
	_hold_used = true
	_chase = false
	_start_smash(kind, k, true)


func _start_smash(kind: String, k: float, dash: bool) -> void:
	state = A.SMASH
	_t = 0.0
	_smash_kind = kind
	_smash_k = k
	_hit_done = false
	_whiff = false
	var gap_d := Proj.aim_of(target).distance_to(player.center()) - _gap(target) if _alive(target) else 0.0
	_sm_dash = dash and _alive(target) and gap_d > 0.8
	_whiff_pen = 0.0
	_open_hold = 0.0
	_opener = false
	if _sm_dash and gap_d > MAGNET and _pvp(target) and not _is_launched(target):
		# 真人对打：蓄力重击从远处飞过去也要花灵力，不够就原地打出去；飞过去的这一拳算「起手」
		if _pvp_pay(Moves.PVP_FLY_MP):
			_open_begin()
			_pvp_notice(maxf(Moves.PVP_OPEN_T, clampf(gap_d / SMASH_FLY_SPD, 0.0, SMASH_FLY_T) + 0.12 + float(SMASH[kind]["hit"])))
		else:
			pvp_stat["no_mp"] = int(pvp_stat["no_mp"]) + 1
			_sm_dash = false
	_ghost_t = 0.0
	_engage = ENGAGE_KEEP
	# 冲刺段多久：近处 0.3 秒、每秒 78 米；远处（长按蓄力打远处的对手）提速到最多 SMASH_FLY_SPD，路上不超过 SMASH_FLY_T 秒
	_sm_fly_max = clampf(gap_d / SMASH_FLY_SPD, 0.0, SMASH_FLY_T) + 0.12
	_sm_fly_far = gap_d > 10.0
	if _sm_dash:
		var d := (Proj.aim_of(target) - player.center()).normalized()
		Vfx.launch_ring(player.center(), d, _col(), 0.6 + k)
		Sfx.play("swing_heavy", -4.0, 0.8)
		player.cam.fov_punch(8.0 + 6.0 * k)
		player.cam.kick_rush(1.0)
		if _sm_fly_far:
			# 远距离：破空一声、原地一圈气浪，人化作一道残影直扑过去
			Vfx.dash_start(player.center(), d, _col(), 1.0 + k)
			Vfx.shockwave(player.center(), d, Color.WHITE.lerp(_col(), 0.4), 1.2 + 0.4 * k)
			Vfx.space_ring(player.center(), 1.4, _col(), 0.3, 0.03)
			Sfx.play("dodge", -4.0, 0.8)
	else:
		_smash_swing()


func _smash_swing() -> void:
	_sm_dash = false
	_t = 0.0
	var sm: Dictionary = SMASH[_smash_kind]
	_open_hold = _open_take(float(sm["hit"]))
	if _open_hold <= 0.0:
		rig.play(sm["seq"])
		Sfx.play("swing_heavy", -3.0, 0.9)
	if _alive(target):
		var d := _dir_to(target)
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


# ---------- 瞬身追击 ----------

func _can_chase() -> bool:
	return _is_launched(_launched) and _chase_n < CHASE_MAX and player.mp >= CHASE_MP


## 击飞方向（三维，已归一）：kind 对应 前 / 上 / 下，flat 为水平基准方向
static func _knock_dir(kind: String, flat: Vector3) -> Vector3:
	match kind:
		"up":
			return (flat * 0.22 + Vector3.UP).normalized()
		"down":
			return (flat * 0.3 + Vector3.DOWN).normalized()
	return (flat + Vector3.UP * 0.16).normalized()


## 追击计一次、扣灵力（觉醒中不耗）
func _pay_chase(mp: float) -> void:
	_chase_n += 1
	if awake_t <= 0.0:
		player.mp = maxf(player.mp - mp, 0.0)
		player.caster.hold_regen()


## 瞬身追击：瞬移到被打飞的对手飞行路线的前头，迎面一脚把它截停在半空（空中连击第一下），
## 之后点按 = 空中连击，长按 / 打满三下 = 终结重击再把它打飞
func _start_chase() -> void:
	var t := _launched
	_pay_chase(CHASE_MP)
	target = t
	var tv: Vector3 = t.velocity() if t.has_method("velocity") else Vector3.ZERO
	var tc := Proj.aim_of(t) + tv * 0.09
	var flat := _flat(tv)
	if flat.length() < 2.0:
		flat = _flat(tc - player.center())
	flat = flat.normalized() if flat.length_squared() > 1e-4 else _fwd()
	# 截在飞行路线的前头（竖着飞的就截在它上方 / 下方），让它迎面撞上来
	var ahead := tv.normalized() if tv.length() > 6.0 else flat
	var spot := safe_spot(tc, tc + ahead * (_gap(t, tc + ahead * 10.0) + 0.3) - Vector3(0.0, BODY_Y, 0.0))
	Vfx.vanish(player.center(), _col())
	_end_blade()
	if spot != Vector3.INF:
		var look := _flat(tc - spot)
		var yaw := atan2(-look.x, -look.z) if look.length_squared() > 0.01 else atan2(flat.x, flat.z)
		player.warp_to(spot, yaw)
		_note_swap()
		face_yaw = yaw
		has_face = true
		_warp(spot + Vector3(0.0, BODY_Y, 0.0), 0.8)
	_chase = true
	Combat.clear_hitstop()
	_start_move(JUG[0])
	player.cam.kick_rush(0.7)
	player.melee.combat_event.emit("air_chase", {"n": _chase_n, "kind": "vanish"})


## 追身：被打飞的对手还在飞，按「闪」高速飞过去（比瞬身追击省一半灵力，同样计次）。Player.blink 调，追上了返回 true
func try_homing() -> bool:
	if player.st != Player.St.AIR or player.ult.active or player.caster.busy():
		return false
	if state != A.IDLE and state != A.GUARD and not ((state == A.ATTACK or state == A.SMASH) and _hit_done) and not _threw():
		return false
	if not _is_launched(_launched) or _reach(_launched) or _chase_n >= CHASE_MAX or player.mp < CHASE_MP * 0.5:
		return false
	_pay_chase(CHASE_MP * 0.5)
	_chase = true
	_start_dash(_launched, true)
	player.melee.combat_event.emit("air_chase", {"n": _chase_n, "kind": "homing"})
	return true


# ---------- 御风突进 ----------

## 想冲：按住了「闪」（Player.sprinting），摇杆没往后拉、也不是纯横移（那是疾行躲剑流）
func _dash_wanted() -> bool:
	if demo_dash:
		return true
	if not player.sprinting() or player.mp < DASH_MIN_MP or player.caster.busy() or player.is_dashing():
		return false
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if iv.y > 0.35:
		return false
	return not (absf(iv.x) > 0.7 and iv.y > -0.3)


## 冲向谁：交战中的目标 / 镜头锁着的；都没有就取镜头前方 45 米内最近的
func _dash_target() -> Node3D:
	if _alive(target) and engaged():
		return target
	var cam := player.cam
	if _alive(cam.lock):
		return cam.lock
	var t := Proj.pick_target(player, 45.0, null)
	if t == null:
		return null
	var d := (Proj.aim_of(t) - player.center()).normalized()
	return t if d.dot(-cam.look_basis().z) > 0.6 else null


func _start_dash(t: Node3D, homing: bool) -> void:
	_end_blade()
	player.hero.set_glow(0.0, _col())
	target = t
	state = A.DASH
	_t = 0.0
	_dash_t = 0.0
	_dash_homing = homing
	_dash_atk = false
	_ghost_t = 0.0
	_queued = false
	_engage = ENGAGE_KEEP
	if not homing and _pvp(t):
		_open_begin()         # 真人对打：冲到位的那一脚算「起手」（冲得够久就不用再补前摇）
	Combat.clear_hitstop()
	rig.play("f_rush")
	var c := player.center()
	var d := Proj.aim_of(t) - c
	d = d.normalized() if d.length_squared() > 1e-4 else _fwd()
	Vfx.dash_start(c, d, _col(), 0.9)
	Vfx.launch_ring(c, d, _col(), 1.0 if homing else 0.8)
	Sfx.play("dodge", -4.0, 1.3 if homing else 0.9)
	Sfx.play("swing_heavy", -9.0, 0.6)
	var cam := player.cam
	cam.fov_punch(12.0)
	cam.kick_rush(1.0)
	cam.add_trauma(0.14)
	_warp(c, 0.7)


func _tick_dash(cdt: float) -> void:
	if not _alive(target):
		_dash_stop()
		return
	_drives = true
	_dash_t += cdt
	var dir := _dir_to(target)
	var to := _stick_point(target, dir) - player.global_position
	var dl := to.length()
	var mv := to.normalized() if dl > 1e-3 else dir
	if not _dash_homing and dl > 7.0:
		# 摇杆左右：绕着弧线切进去，到位时人在对手的侧面 / 背后
		var sx := Input.get_axis("move_left", "move_right")
		if absf(sx) > 0.3:
			var side := mv.cross(Vector3.UP)
			if side.length_squared() > 1e-4:
				mv = (mv + side.normalized() * sx * 0.95 * clampf((dl - 7.0) / 10.0, 0.0, 1.0)).normalized()
	var spd := (HOMING_SPD if _dash_homing else DASH_SPD) * clampf(_dash_t / DASH_ACC, 0.3, 1.0)
	drive_vel = mv * minf(spd, dl / maxf(cdt, 1e-3))
	if _flat(mv).length_squared() > 0.01:
		face_yaw = atan2(-mv.x, -mv.z)
		has_face = true
	_trail_ghosts(cdt, 0.03)
	var cam := player.cam
	cam.kick_rush(0.6)
	cam.fov_punch(9.0)
	if not _dash_homing:
		player.mp = maxf(player.mp - DASH_MP * cdt, 0.0)
		player.caster.hold_regen()
	if dl < 1.2:
		_dash_arrive()
	elif _dash_t > 3.0 or (not _dash_homing and not _dash_atk and (not _dash_wanted() or player.mp <= 0.0)):
		_dash_stop()


## 冲到身前：收住势头，平滑转入出手 —— 途中按过攻击就接冲刺攻击；追身追上了直接起空中连击；否则摆好架势等出手
func _dash_arrive() -> void:
	var cam := player.cam
	cam.fov_punch(-4.0)
	Vfx.shockwave(player.center(), _fwd(), _col(), 0.9)
	if _dash_atk:
		_start_move(_dash_id)
	elif _dash_homing and _is_launched(target):
		_launched = target
		_start_move(JUG[0])
	else:
		_to_idle()
		_face_target()


## 松开了 / 没灵力了：带着一点余速滑出去
func _dash_stop() -> void:
	var v := drive_vel
	_to_idle()
	player.velocity = v.limit_length(Player.AIR_SPEED * 1.6)


# ---------- 投技「擒拿抡摔」----------

func _start_throw() -> void:
	_end_blade()
	state = A.THROW
	_throw_ph = 0
	_t = 0.0
	_whiff = false
	_spin_y = 0.0
	_queued = false
	_engage = ENGAGE_KEEP
	var d := _dir_to(target)
	face_yaw = atan2(-d.x, -d.z)
	has_face = true
	rig.play("f_grab")
	Vfx.glint(rig.hand_pos(), Color(0.85, 0.6, 1.0), 1.1)
	Sfx.play("swing_heavy", -7.0, 1.3)


func _tick_throw(cdt: float) -> void:
	_drives = true
	var t := target
	match _throw_ph:
		0:
			# 探手：贴到身前去抓。对手正在出手 / 刚被摔过 / 闪开了都抓不住（grab_by 返回 false）= 抓空，收招很长
			var ok := _alive(t)
			if ok:
				var dir := _dir_to(t)
				face_yaw = atan2(-dir.x, -dir.z)
				var to := _stick_point(t, dir) - player.global_position
				drive_vel = (to / maxf(Moves.THROW_REACH - _t, 0.02)).limit_length(60.0)
			if _t < Moves.THROW_REACH and ok:
				return
			if ok and Proj.aim_of(t).distance_to(player.center()) <= _gap(t) + 1.6 and bool(t.call("grab_by", player)):
				_throw_ph = 1
				_t = 0.0
				_throw_yaw = face_yaw
				rig.play("f_hold")
				Combat.hitstop(0.06)
				Sfx.play("block", -4.0, 0.7)
				player.cam.add_trauma(0.2)
				player.melee.combat_event.emit("air_grab", {})
			else:
				_whiff = true
				_throw_ph = 2
				_t = 0.0
				_dur = Moves.THROW_END * 1.3
				player.melee.combat_event.emit("air_whiff", {})
		1:
			if not _alive(t) or not t.has_method("grab_hold"):
				_throw_abort()
				_throw_ph = 2
				_t = 0.0
				_dur = Moves.THROW_END
				return
			# 抡两圈（越抡越快）：整身自转，手里的人跟着甩
			var k := clampf(_t / Moves.THROW_SPIN, 0.0, 1.0)
			_spin_y = -TAU * 2.0 * k * k
			var hd := Basis(Vector3.UP, _throw_yaw + _spin_y) * Vector3.FORWARD
			t.call("grab_hold", player.center() + hd * 1.6 + Vector3.UP * 0.1)
			_trail_ghosts(cdt, 0.05)
			player.cam.kick_rush(0.3)
			if _t >= Moves.THROW_SPIN:
				_throw_release(t)
		2:
			if _t >= _dur:
				_spin_y = 0.0
				_last_id = ""
				_to_idle()


## 松手：摇杆不推 / 前 = 朝镜头前方甩出去，后 = 往地面砸，左右 = 往两侧甩
func _throw_release(t: Node3D) -> void:
	var dir := player.cam.flat_forward()
	var kind := "fwd"
	match _stick_dir():
		"down":
			if not _near_floor(t):
				kind = "down"
		"side":
			dir = dir.rotated(Vector3.UP, -PI * 0.5 * signf(Input.get_axis("move_left", "move_right")))
	var kd := _knock_dir(kind, dir)
	var dmg := _base() * Moves.THROW_DMG * Moves.dmg_scale(_string_n)
	_spin_y = 0.0
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	rig.play("f_sm")
	Sfx.play("swing_heavy", -3.0, 0.8)
	t.call("grab_throw", kd * Moves.THROW_SPD * _kbm(true), dmg)
	_string_n += 1
	_add_combo(dmg)
	_throw_ph = 2
	_t = 0.0
	_dur = Moves.THROW_END
	if _is_launched(t):
		_chase = false
		_on_launch(t, kind, Proj.aim_of(t), kd, 0.1)


## 抡到一半被打断（挨打、陨落、落地、闪现）：把手里的人放开
func _throw_abort() -> void:
	if state == A.THROW and _throw_ph == 1 and _alive(target) and target.has_method("grab_release"):
		target.call("grab_release")
	_spin_y = 0.0


# ---------- 被对手擒住 ----------

## 对手的擒拿抓到了自己（air_foe.gd 调）：护体挡不住；自己正在出手 / 冲刺 / 无敌 / 被打飞时抓不住。抓住了返回 true
func grabbed_by(src: Node3D) -> bool:
	if player.st != Player.St.AIR or player.is_dashing() or _iframe > 0.0 or player.ult.active or player.dun_active or player.dead:
		return false
	if state == A.ATTACK or state == A.SMASH or state == A.RUSH or state == A.DASH or state == A.THROW or state == A.BRAWL \
			or state == A.CLASH or state == A.BLOWN or state == A.DOWN or state == A.DEAD or state == A.GRABBED:
		return false
	_end_blade()
	player.hero.set_glow(0.0, _col())
	player.caster.cancel()
	player.note_attacker(src)
	state = A.GRABBED
	_t = 0.0
	_grab_by = src
	_grab_taps = 0
	_queued = false
	_buf_at = -10.0
	combo = 0
	combo_dmg = 0.0
	_string_n = 0
	_engage = ENGAGE_KEEP
	rig.play("f_hurt")
	Combat.hitstop(0.06)
	Sfx.play("block", -3.0, 0.6)
	player.cam.add_trauma(0.3)
	player.melee.combat_event.emit("air_grabbed", {})
	return true


## 被擒住时由对手每帧摆位置
func grab_hold(pos: Vector3) -> void:
	if state != A.GRABBED:
		return
	player.global_position = pos - Vector3(0.0, BODY_Y, 0.0)
	player.velocity = Vector3.ZERO


## 没挣开：被甩出去（对手调）
func thrown(src: Node3D, dir: Vector3, kb: float, dmg: float) -> void:
	if state != A.GRABBED:
		return
	_grab_by = null
	state = A.IDLE
	_hurt(src, {"dmg": dmg, "kb": kb, "contact": player.center()}, dir, true)


func _grab_tap() -> void:
	_grab_taps += 1
	player.cam.add_trauma(0.08)
	player.hit_shake(0.06)
	if _grab_taps >= Moves.GRAB_ESCAPE:
		_grab_break(false)


## 挣开擒拿：连点够了（by_burst = false），或耗一格罡气直接震开（true）
func _grab_break(by_burst: bool) -> void:
	var f := _grab_by
	_grab_by = null
	if by_burst:
		_burst()
	else:
		state = A.IDLE
		_t = 0.0
		_iframe = 0.5
		rig.play("f_burst")
		_point_t = 0.3
		Vfx.shockwave(player.center(), Vector3.UP, _col(), 1.6)
		Sfx.play("dodge", -4.0, 0.9)
		player.melee.combat_event.emit("air_grab_break", {})
	if is_instance_valid(f) and f.has_method("grab_broken"):
		f.call("grab_broken")


# ---------- 拳劲对拼（高速互殴）----------

func can_brawl() -> bool:
	return _brawl_cd <= 0.0 and state == A.ATTACK and player.st == Player.St.AIR


## 对手那边发现两边的拳头撞上了（air_foe.gd 的 air_hit 调）
func start_brawl(foe: Node3D) -> void:
	if can_brawl() and _alive(foe) and foe.has_method("brawl_begin"):
		_start_brawl(foe)


func _start_brawl(foe: Node3D) -> void:
	_end_blade()
	player.hero.set_glow(0.0, _col())
	state = A.BRAWL
	_t = 0.0
	_brawl_foe = foe
	_brawl_u = 0.5
	_brawl_t = 0.0
	_brawl_cd = Moves.BRAWL_CD
	_brawl_punch = 0.0
	_brawl_hop = 0.5
	_brawl_mv = -1.0
	_brawl_n = 0
	_clash_surge = 0.5
	_mash_acc = 0.0
	_queued = false
	_buf_at = -10.0
	target = foe
	_engage = ENGAGE_KEEP
	foe.call("brawl_begin")
	var a := player.center()
	var b := Proj.aim_of(foe)
	var ax := _flat(b - a)
	_brawl_axis = ax.normalized() if ax.length() > 0.2 else _fwd()
	_brawl_c = a.lerp(b, 0.5)
	_brawl_c.y = maxf(_brawl_c.y, _floor_at(_brawl_c) + 2.6)
	_brawl_home = _brawl_c
	_brawl_cam = _brawl_c
	var side := _brawl_axis.cross(Vector3.UP).normalized()
	if side.dot(player.cam.global_position - _brawl_c) < 0.0:
		side = -side
	_clash_side = side
	Combat.clear_hitstop()
	Combat.slowmo(0.35, 0.1, 0.25)
	# 侧面机位：0.28 秒混进去（以前是硬切，正常格斗里一撞拳镜头就跳一下）；对拼期间这一侧不变
	_start_cine(_brawl_c + side * 10.0 + Vector3.UP * 3.0, null, Moves.BRAWL_MAX + 2.0, 58.0, 0.25, 0.28)
	_cine_look = _brawl_c
	_cine_use_look = true
	_tick_cine(0.0)
	Vfx.shockwave(_brawl_c, _brawl_axis, Color.WHITE.lerp(_col(), 0.4), 2.0)
	Vfx.blade_clash(_brawl_c, side, 1.2)
	# 两股拳劲撞上的第一下：一圈空间波动荡开。2026-11-21 起对拼的波动圈 / 扭曲都减了一半上下 ——
	# 原来几圈色散叠在一起把两个人整个糊住，元婴起的空间裂缝也被盖得看不见
	Vfx.space_ring(_brawl_c, 3.2, _col(), 0.6, 0.05)
	_warp(_brawl_c, 1.6)
	_brawl_ct = _crack_tier(foe)
	_brawl_crack(_brawl_c, true, _col())
	Sfx.play("clash", -2.0, 1.2)
	player.cam.impact(0.5)
	player.melee.combat_event.emit("air_brawl", {"pos": _brawl_c})


func _brawl_tap() -> void:
	_clash_surge = minf(_clash_surge + Moves.CLASH_TAP, Moves.CLASH_SURGE_MAX)
	player.cam.add_trauma(0.04)


## 对拼已经不在 BRAWL 状态了、对手还挂着（被别的路径改了状态）：对手退出对拼，镜头 0.25 秒交还
func _brawl_drop() -> void:
	var f := _brawl_foe
	_brawl_foe = null
	if is_instance_valid(f) and f.has_method("brawl_end"):
		f.call("brawl_end", false)
	_cine_bail()


## 对波被别的操作打断（剑诀已经禁了；开大、瞬身、落地、转光遁、陨落…）：剑流和光核收掉、对手退出相持（当作平手收招），
## 镜头 0.25 秒混回跟随机位（开大时立刻交出去，大招有自己的镜头）。对手是真人、这边做主时告诉他按我输算
func _clash_abort() -> void:
	_clash_live = false
	if player.caster.clash_mode:
		player.caster.end_clash()
	_drop_cfx()
	var f := _clash_foe
	if _alive(f):
		if f.has_method("net_clash_end"):
			if _clash_auth:
				f.call("net_clash_end", false)
		elif f.has_method("clash_end"):
			f.call("clash_end", false)
	_cine_bail()


## 演出镜头提前收：开大 / 离开空战 / 陨落时立刻交出去；否则剩下的改成 0.25 秒混回跟随机位（先对齐朝向，见 _hand_cam）
func _cine_bail() -> void:
	if _cine_t < 0.0:
		return
	if player.ult.active or player.st != Player.St.AIR or player.dead:
		_end_cine()
		return
	_cine_follow = null
	if _cine_dur - _cine_t > 0.25:
		_cine_dur = _cine_t + 0.25
		_cine_out = 0.25


## 对拼被别的事打断：把对手放回去、镜头交还
func _brawl_abort() -> void:
	if state != A.BRAWL:
		return
	var f := _brawl_foe
	_brawl_foe = null
	if is_instance_valid(f) and f.has_method("brawl_end"):
		f.call("brawl_end", false)
	_end_cine()


func _tick_brawl(dt: float) -> void:
	_drives = true
	var foe := _brawl_foe
	if not _alive(foe) or not foe.has_method("brawl_output"):
		_brawl_foe = null
		_end_cine()
		_to_idle()
		return
	_brawl_t += dt
	if demo_mash > 0.0:
		_mash_acc += demo_mash * dt
		while _mash_acc >= 1.0:
			_mash_acc -= 1.0
			_brawl_tap()
	_clash_surge *= exp(-Moves.CLASH_SURGE_DECAY * dt)
	# 优势条：算法同对波（技能强度 × 连点发力），不耗灵力
	var mine := (1.0 + 0.06 * float(flair())) * (1.3 if awake_t > 0.0 else 1.0) * (1.0 + _clash_surge)
	var theirs: float = foe.call("brawl_output", _brawl_t)
	_brawl_u = clampf(_brawl_u + (mine - theirs) * Moves.BRAWL_BASE * (1.0 + 0.2 * _brawl_t) * dt, 0.0, 1.0)
	var col := _col()
	var fcol: Color = foe.get("qi") if foe.get("qi") != null else Color(1.0, 0.4, 0.35)
	# 换位冲刺：两个人裹在一起极快地冲到下一处（一路残影），到位那一下对撞
	var moving := _brawl_mv >= 0.0
	if moving:
		_brawl_mv += dt
		var e := clampf(_brawl_mv / BRAWL_MOVE_T, 0.0, 1.0)
		_brawl_c = _brawl_from.lerp(_brawl_to, e * (2.0 - e))
		_brawl_gh -= dt
		if _brawl_gh <= 0.0:
			_brawl_gh = 0.05 if Vfx.lite else 0.03
			Vfx.body_ghost(player.visual, Color.WHITE.lerp(col, 0.6), 0.5, 0.24)
			var fv: Variant = foe.get("visual")
			if fv is Node3D:
				Vfx.body_ghost(fv as Node3D, Color.WHITE.lerp(fcol, 0.6), 0.45, 0.24)
		player.cam.kick_rush(1.0)
		if e >= 1.0:
			_brawl_mv = -1.0
			moving = false
			_brawl_arrive(col, fcol)
	var c := _brawl_c
	var ax := _brawl_axis
	# 站位：两人贴在对打的中心两侧，面对面
	player.global_position = c - ax * 1.05 - Vector3(0.0, BODY_Y, 0.0)
	player.velocity = Vector3.ZERO
	face_yaw = atan2(-ax.x, -ax.z)
	has_face = true
	foe.call("brawl_place", c + ax * 1.05)
	# 快拳互殴：两边轮着出拳，拳头撞上的地方溅火星；每三拳一记硬碰，荡开一小圈空间波动
	_brawl_punch -= dt
	if _brawl_punch <= 0.0 and not moving:
		_brawl_punch = 0.085
		_brawl_n += 1
		rig.play(["f1", "f2", "f3", "f4"][_brawl_n % 4], 1.6)
		foe.call("brawl_punch", _brawl_n)
		var hp := c + Vector3(randf_range(-0.4, 0.4), randf_range(-0.5, 0.6), randf_range(-0.4, 0.4))
		var mine_turn := _brawl_n % 2 == 0
		Vfx.hit(hp, ax if mine_turn else -ax, Color.WHITE.lerp(col if mine_turn else fcol, 0.5), 0.9)
		if _brawl_n % 3 == 0:
			Vfx.blade_clash(hp, _clash_side, 0.8)
			Vfx.shockwave(hp, ax, Color.WHITE.lerp(col, 0.4), 0.9)
			Vfx.space_ring(hp, 1.5, col if mine_turn else fcol, 0.34, 0.035)
			_warp(hp, 1.2)
		if _brawl_ct > 0 and _brawl_n % (int(CRACK_EVERY[_brawl_ct]) * (2 if Vfx.lite else 1)) == 0:
			_brawl_crack(hp, false, col if mine_turn else fcol)
		Sfx.play("hit" if mine_turn else "block", -7.0, randf_range(0.95, 1.4))
		player.cam.add_trauma(0.07)
	# 每隔半秒一起冲到别处接着打
	_brawl_hop -= dt
	if _brawl_hop <= 0.0 and not moving:
		_brawl_hop = randf_range(0.44, 0.62)
		_brawl_jump(col, fcol)
	# 镜头：盯着对打的中心跟（比换位慢半拍，冲刺的拖线会从画面里划过去）
	_brawl_cam = _brawl_cam.lerp(_brawl_c, 1.0 - exp(-7.0 * dt))
	var eye := _brawl_cam + _clash_side * 10.5 + Vector3.UP * 3.0
	eye.y = maxf(eye.y, _floor_at(eye) + 0.6)
	_cine_eye = eye
	_cine_look = _brawl_cam
	# 对打的地方空间一直在抖（一阵强一阵弱）
	_warp(_brawl_c, 0.7 + 0.25 * sin(_brawl_t * 11.0))
	var win := _brawl_u >= 0.95 or (_brawl_t >= Moves.BRAWL_MAX and _brawl_u >= 0.5)
	var lose := _brawl_u <= 0.05 or (_brawl_t >= Moves.BRAWL_MAX and _brawl_u < 0.5)
	if not (win or lose):
		return
	# 分胜负：赢的一方一记重手把对面打飞
	_brawl_foe = null
	foe.call("brawl_end", win)
	_cine_dur = _cine_t + 0.35
	_cine_out = 0.35
	Combat.slowmo(0.25, 0.12, 0.3)
	var cam := player.cam
	cam.impact(0.8)
	cam.add_trauma(0.5)
	var kd := _knock_dir("fwd", ax)
	state = A.IDLE
	_t = 0.0
	player.melee.combat_event.emit("air_brawl_end", {"win": win, "pos": _brawl_c})
	Vfx.space_ring(_brawl_c, 3.8, col if win else fcol, 0.7, 0.06)      # 分胜负的那一记：最大的一圈
	_warp(_brawl_c, 2.0)
	_brawl_crack(_brawl_c, true, col if win else fcol, 1.5)
	if _brawl_ct >= 4:
		Vfx.rift_collapse(_brawl_c, col if win else fcol, 1.2 + 0.3 * float(_brawl_ct))   # 合体 / 大乘：撕开的空间往里一塌
	if win:
		rig.play("f_sm")
		_point_t = 0.35
		var dmg := _base() * 2.4
		foe.call("air_hit", player, {"dmg": dmg, "dir": kd, "kb": 40.0 * _kbm(true), "stun": 1.0, "launch": "fwd", "heavy": true,
				"burst": true, "contact": _brawl_c})
		_string_n += 1
		_add_combo(dmg)
		Vfx.impact(_brawl_c, _clash_side, col, 4)
		if _is_launched(foe):
			_chase = false
			_on_launch(foe, "fwd", _brawl_c, kd, 0.12)
	else:
		_hurt(foe, {"dmg": 14.0, "kb": 28.0, "contact": _brawl_c}, (-ax + Vector3.UP * 0.15).normalized(), true)


## 对拼中一起换位：围着开打的地方挑下一处（落点过合法性检查），两个人裹在一起极快地冲过去（BRAWL_MOVE_T 秒，
## 每秒五十米上下）：起步处一圈气浪，两道拖线从旧位置拉到新位置，途中留残影、镜头起速度线；到位见 _brawl_arrive
func _brawl_jump(col: Color, fcol: Color) -> void:
	var old := _brawl_c
	var ang := randf() * TAU
	var want := _brawl_home + Vector3(cos(ang), randf_range(-0.25, 0.45), sin(ang)) * randf_range(4.5, 7.0)
	want.y = maxf(want.y, _floor_at(want) + 2.6)
	var spot := safe_spot(old, want - Vector3(0.0, BODY_Y, 0.0))
	if spot == Vector3.INF:
		return
	var nc := spot + Vector3(0.0, BODY_Y, 0.0)
	if nc.distance_to(old) < 1.0:
		return
	var ax := _brawl_axis
	var dir := (nc - old).normalized()
	_brawl_from = old
	_brawl_to = nc
	_brawl_mv = 0.0
	_brawl_gh = 0.0
	Vfx.shockwave(old, dir, Color.WHITE.lerp(col, 0.3), 2.2)
	Vfx.dash_start(old - ax, dir, col, 0.9)
	Vfx.dash_start(old + ax, dir, fcol, 0.9)
	Vfx.warp_line(old - ax * 1.05, nc - ax * 1.05, Color.WHITE.lerp(col, 0.5))
	Vfx.warp_line(old + ax * 1.05, nc + ax * 1.05, Color.WHITE.lerp(fcol, 0.5))
	rig.play("f_rush")
	Sfx.play("dodge", -7.0, 1.5)
	Sfx.play("swing_heavy", -11.0, 1.5)
	var cam := player.cam
	cam.kick_rush(1.0)
	cam.add_trauma(0.12)


## 换位冲到了：两个人在新位置撞在一起——金铁交击的火花、一圈空间波动、画面碎一下、短短一顿，然后接着互殴
func _brawl_arrive(col: Color, fcol: Color) -> void:
	var c := _brawl_c
	var dir := (_brawl_to - _brawl_from).normalized()
	_brawl_axis = _brawl_axis.rotated(Vector3.UP, randf_range(-1.3, 1.3))
	_brawl_punch = 0.0
	Vfx.blade_clash(c, _clash_side, 1.4)
	Vfx.shockwave(c, dir, Color.WHITE.lerp(col, 0.4), 2.4)
	Vfx.shockwave(c, _clash_side, Color.WHITE.lerp(fcol, 0.4), 1.8)
	Vfx.space_ring(c, 2.6, col.lerp(fcol, 0.5), 0.5, 0.045)
	_warp(c, 1.5)
	_brawl_crack(c, true, col.lerp(fcol, 0.5))
	Combat.hitstop(0.045)
	Sfx.play("clash", -5.0, randf_range(1.05, 1.35))
	var cam := player.cam
	cam.impact(0.3)
	cam.add_trauma(0.22)


## 对拼双方里境界高的那个算档：元婴 1 … 大乘 5，结丹及以下 0
func _crack_tier(foe: Node3D) -> int:
	var r := player.realm_idx
	if is_instance_valid(foe) and foe.has_method("tier_realm"):
		r = maxi(r, int(foe.call("tier_realm")))
	return clampi(r - 2, 0, 5)


## 对拳撞出一道空间裂缝（Vfx.space_crack）：档位越高裂得越长、道数越多、越碎、留得越久、扭得越狠；
## 炼虚起缝中间再撕开一道竖缝（Vfx.rift）；大撞击时画面碎一下，档位越高碎得越狠（只在大撞击，别一拳一闪）。mul = 大小再乘多少
func _brawl_crack(pos: Vector3, big: bool, col: Color, mul := 1.0) -> void:
	var ct := _brawl_ct
	if ct <= 0:
		return
	var t := float(ct)
	var size := (0.7 + 0.28 * t) * (1.6 if big else 1.0) * mul
	var br := 2 + ct + (2 if big else 0)
	if Vfx.lite:
		br = maxi(2, br / 2)
	Vfx.space_crack(pos, col, size, br, 0.32 + 0.05 * t + (0.2 if big else 0.0), 0.12 * t)
	_warp(pos, 0.4 + 0.2 * t)
	if ct >= 3 and (big or randf() < 0.35):
		var cp := player.cam.cam.global_position
		Vfx.rift(pos, cp - pos, col, (0.5 + 0.18 * t) * (1.5 if big else 1.0), 0.4 + 0.05 * t)
	if big:
		player.cam.impact(0.2 + 0.05 * t)     # 大撞击时画面跟着碎一下，档位越高碎得越狠（元婴 0.25 … 大乘 0.45；原来各境界都是 0.3）


# ---------- 坠地追击：对手被砸进地里之后的收尾 ----------

## 被自己打下去的对手正趴在坑里、这一回还没补过：按「攻」= 坠星踏，按「剑」= 剑雨灌顶（触屏按钮据此换字）
func otg_ready() -> bool:
	if _otg_done or player.st != Player.St.AIR or player.caster.busy() or player.is_dashing():
		return false
	if not _alive(_downed) or not _downed.has_method("is_downed") or not bool(_downed.call("is_downed")):
		return false
	return state == A.IDLE or state == A.GUARD or ((state == A.ATTACK or state == A.SMASH) and _hit_done)


## 坠星踏：闪到它正上方（头顶有东西挡着就矮一点），整个人打直了砸下去，一脚踩进坑里
func _start_stomp() -> void:
	var t := _downed
	_otg_done = true
	_end_blade()
	Combat.clear_hitstop()
	player.hero.set_glow(0.0, _col())
	target = t
	_engage = ENGAGE_KEEP
	var tc := Proj.aim_of(t)
	var land := Vector3(tc.x, maxf(t.global_position.y, _floor_at(tc)) + 0.3, tc.z)      # 踩实时脚底的位置：它身上
	var h := Moves.OTG_DIVE_H
	var q := PhysicsRayQueryParameters3D.create(land + Vector3.UP, land + Vector3.UP * (h + 2.2), 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		h = maxf((hit["position"] as Vector3).y - land.y - 2.2, 1.2)
	var top := land + Vector3.UP * h
	if not _legal(top, tc + Vector3.UP * 0.4):
		top = land + Vector3.UP * 1.2
	var old := player.center()
	var col := _col()
	Vfx.vanish(old, col)
	player.warp_to(top, face_yaw)
	Vfx.warp_line(old, top + Vector3(0.0, BODY_Y, 0.0), Color.WHITE.lerp(col, 0.5))
	Vfx.dash_start(top + Vector3(0.0, BODY_Y, 0.0), Vector3.DOWN, col, 1.0)
	_stomp_from = top
	_stomp_to = land
	_stomp_ph = 0
	state = A.STOMP
	_t = 0.0
	_queued = false
	_buf_at = -10.0
	_iframe = maxf(_iframe, Moves.OTG_DIVE_T + 0.2)
	rig.play("f_dk")
	Sfx.play("dodge", -6.0, 1.3)
	Sfx.play("swing_heavy", -4.0, 0.75)
	var cam := player.cam
	cam.kick_rush(1.0)
	cam.fov_punch(8.0)
	player.melee.combat_event.emit("air_otg", {"kind": "stomp"})


func _tick_stomp(cdt: float) -> void:
	_drives = true
	if _stomp_ph == 0:
		var e := clampf(_t / Moves.OTG_DIVE_T, 0.0, 1.0)
		player.global_position = _stomp_from.lerp(_stomp_to, e * e)      # 越砸越快
		player.velocity = Vector3.ZERO
		_trail_ghosts(cdt, 0.05 if Vfx.lite else 0.03)
		player.cam.kick_rush(1.0)
		if e >= 1.0:
			_stomp_land()
		return
	# 踩完借力弹起来一点，悬在坑上方
	var k := clampf(1.0 - _t / Moves.OTG_END, 0.0, 1.0)
	drive_vel = Vector3.UP * 11.0 * k
	if _t >= Moves.OTG_END:
		_last_id = ""
		_to_idle()


func _stomp_land() -> void:
	_stomp_ph = 1
	_t = 0.0
	var t := target
	var ground := _stomp_to - Vector3(0.0, 0.3, 0.0)
	var col := _col()
	var dmg := _base() * Moves.OTG_DMG * Moves.dmg_scale(_string_n)
	if _alive(t) and Proj.aim_of(t).distance_to(ground) < 3.5:
		var res := _hit_target(t, {"dmg": dmg, "dir": Vector3.DOWN, "kb": 0.0, "stun": 0.6, "launch": "", "heavy": true, "otg": true,
				"burst": true, "contact": Proj.aim_of(t), "stop": 0.12, "pst": dmg * 0.6, "step": step, "air": true, "swing": Vector3.DOWN})
		if res == 0 or res == 2:
			_string_n += 1
			_add_combo(dmg)
			if t.has_method("chip_colors"):
				Vfx.debris(ground + Vector3.UP * 0.4, Vector3.UP, t.chip_colors(), 8 if Vfx.lite else 14, 7.0, 1.2)
	Vfx.dun_slam(ground, col, 1.25)
	Vfx.crater_hit(ground, 1.15)      # 踩在它刚砸出来的坑里：碎石再溅一轮，不重铺地裂
	Vfx.space_ring(ground + Vector3.UP * 0.6, 4.6, col, 0.6, 0.09)
	_warp(ground, 2.4)
	Combat.hitstop(0.12, 0.0)
	Sfx.play("slam", 0.0, 0.7)
	Sfx.play("thud", -1.0, 0.55)
	rig.play("f_dn")
	var cam := player.cam
	cam.impact(0.8)
	cam.add_trauma(0.7)
	cam.fov_punch(10.0)
	player.melee.combat_event.emit("air_otg", {"kind": "stomp_hit", "pos": ground})


## 剑雨灌顶：人不下去，抬手一指，一轮飞剑从坑的上空直插下去（插在坑里），最后一波落地炸开。
## 耗灵力；灵力不够返回 false（走平常的点射）
func _start_rain() -> bool:
	var cost := player.mp_max() * Moves.RAIN_MP
	if player.mp < cost:
		return false
	var t := _downed
	_otg_done = true
	player.mp -= cost
	player.caster.hold_regen()
	_end_blade()
	state = A.IDLE
	_t = 0.0
	_queued = false
	target = t
	_engage = ENGAGE_KEEP
	var c := Proj.aim_of(t)
	var d := _flat(c - player.center())
	if d.length_squared() > 0.04:
		face_yaw = atan2(-d.x, -d.z)
		has_face = true
	rig.play("f_point")
	_point_t = Moves.RAIN_T
	_rain_t = 0.0
	_rain_tgt = t
	_rain_pos = Vector3(c.x, maxf(t.global_position.y, _floor_at(c)), c.z)
	_rain_dmg = _base() * Moves.RAIN_DMG * Moves.dmg_scale(_string_n)
	var n := 9 if Vfx.lite else 14
	var cols := Realm.lines(player.realm)
	var art := Realm.art(player.realm)
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.25, 0.25)
		var r := randf_range(0.5, 2.6)
		var from := _rain_pos + Vector3(cos(a) * r * 1.3, randf_range(9.0, 12.5), sin(a) * r * 1.3)
		var aim := _rain_pos + Vector3(cos(a) * r * 0.5, -0.4, sin(a) * r * 0.5)
		Proj.launch(player, Proj.K.SWORD, from, null, aim, {"dmg": _base() * 0.06, "color": cols[i % cols.size()], "speed": 88.0,
				"hold": 0.06 + (Moves.RAIN_T - 0.3) * float(i) / float(n), "turn": 0.0, "straight": true, "art": art, "lite": true,
				"sfx": i % 4 == 0, "trauma": 0.0, "life": 1.0, "tw": 0.1, "scale": Proj.SWORD_SCALE * 1.25})
	Vfx.cast_flash(player.center() + Basis(Vector3.UP, face_yaw) * Vector3(0.0, 0.3, -0.7), _col(), 1.2)
	Vfx.space_ring(_rain_pos + Vector3.UP * 10.5, 3.4, _col(), 0.5, 0.05)      # 坑的上空：剑是从这儿破出来的
	Sfx.play("swing_heavy", -5.0, 1.2)
	player.cam.add_trauma(0.12)
	player.melee.combat_event.emit("air_otg", {"kind": "rain"})
	return true


func _tick_rain(dt: float) -> void:
	if _rain_t < 0.0:
		return
	_rain_t += dt
	if _rain_t < Moves.RAIN_T:
		return
	# 最后一波落地：坑里炸开
	_rain_t = -1.0
	var t := _rain_tgt
	_rain_tgt = null
	var pos := _rain_pos
	var col := _col()
	if _alive(t) and Proj.aim_of(t).distance_to(pos) < 4.0:
		var res := _hit_target(t, {"dmg": _rain_dmg, "dir": Vector3.DOWN, "kb": 0.0, "stun": 0.6, "launch": "", "heavy": true, "otg": true,
				"burst": true, "contact": Proj.aim_of(t), "stop": 0.08, "pst": _rain_dmg * 0.6, "step": step, "air": true, "swing": Vector3.DOWN})
		if res == 0 or res == 2:
			_string_n += 1
			_add_combo(_rain_dmg)
	var near := clampf(1.0 - pos.distance_to(player.center()) / 60.0, 0.3, 1.0)
	Vfx.crater_hit(pos, 0.95)
	Vfx.space_ring(pos + Vector3.UP * 0.6, 3.8, col, 0.55, 0.08)
	_warp(pos, 2.0 * near)
	Sfx.play("slam", -2.0, 0.85)
	var cam := player.cam
	cam.add_trauma(0.5 * near)
	cam.impact(0.5 * near)
	player.melee.combat_event.emit("air_otg", {"kind": "rain_hit", "pos": pos})


# ---------- 弹开气弹 ----------

## 有气弹马上要打到自己：现在按「攻」是把它抽回去（触屏按钮据此换字）
func swat_cue() -> bool:
	if (state != A.IDLE and state != A.GUARD) or player.st != Player.St.AIR or player.caster.busy() or player.is_dashing():
		return false
	var c := player.center()
	for f: Node in player.get_tree().get_nodes_in_group("air_foes"):
		if f.has_method("bolt_eta") and float(f.call("bolt_eta", c)) <= Moves.SWAT_WIN:
			return true
	return false


## 气弹快打到身上的那一下按「攻」：反手一抽，气弹掉头飞回去打放它的人。抽到了返回 true（这一下不再出拳）
func _try_swat() -> bool:
	if (state != A.IDLE and state != A.GUARD) or player.caster.busy() or player.is_dashing():
		return false
	var c := player.center()
	var col := _col()
	var n := 0
	var src: Node3D = null
	for f: Node in player.get_tree().get_nodes_in_group("air_foes"):
		if f.has_method("swat_bolts"):
			var k := int(f.call("swat_bolts", c, Moves.SWAT_WIN, _base() * Moves.SWAT_DMG, Color.WHITE.lerp(col, 0.6)))
			if k > 0:
				n += k
				src = f as Node3D
	if n <= 0:
		return false
	_engage = ENGAGE_KEEP
	if src != null:
		var d := _flat(Proj.aim_of(src) - c)
		if d.length_squared() > 0.04:
			face_yaw = atan2(-d.x, -d.z)
			has_face = true
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3.FORWARD
	rig.play("f_swat")
	_swat_t = 0.26
	_point_t = 0.0
	var at := c + fwd * 0.8 + Vector3.UP * 0.15
	Vfx.blade_clash(at, fwd, 1.1)
	Vfx.shockwave(at, fwd, Color.WHITE.lerp(col, 0.4), 1.1)
	Vfx.space_ring(at, 1.6, col, 0.3, 0.05)
	# 2026-11-21 强化：反手一抽带出一道月牙弧光，抽回去的方向一圈破空环（气弹在 air_foe.gd 里拖着更亮的尾光飞回去）
	Vfx.crescent(at, fwd, Color.WHITE.lerp(col, 0.3), 1.3)
	Vfx.launch_ring(at, fwd, col, 0.9)
	Vfx.line_sparks(at, fwd, Color.WHITE.lerp(col, 0.5), 8, 18.0, 40.0, 0.3)
	Combat.hitstop(0.05)
	Sfx.play("block", -1.0, 1.5)
	Sfx.play("swing", -6.0, 1.7)
	player.cam.add_trauma(0.14)
	player.melee.combat_event.emit("air_swat", {"back": true, "n": n})
	return true


## 护体中正面飞来的气弹 / 飞剑：单手一拨，斜着崩飞出去（不掉血，比硬挡省灵力）
func _swat(info: Dictionary, dir: Vector3) -> void:
	player.mp = maxf(player.mp - Moves.SWAT_MP, 0.0)
	player.caster.hold_regen()
	_swat_n += 1
	var c: Vector3 = info.get("contact", player.center())
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var out := (-dir * 0.3 + side * (1.0 if _swat_n % 2 == 0 else -1.0) + Vector3.UP * randf_range(0.15, 0.7)).normalized()
	if _swat_t <= 0.1:
		rig.play("f_swat")
	_swat_t = 0.22
	# 2026-11-21 强化「打走」：掌前一圈气劲 + 崩飞的长光 + 火星，桌面档再荡一小圈空气（剑流里的每柄剑另在 spell_projectile.gd 的 deflect 打着旋飞走）
	var col := _col()
	Vfx.blade_clash(c, -dir, 0.7)
	Vfx.ricochet(c, out, col, 4.6)
	Vfx.shockwave(c, -dir, Color.WHITE.lerp(col, 0.4), 0.6)
	Vfx.line_sparks(c, out, Color.WHITE.lerp(col, 0.5), 6, 16.0, 35.0, 0.3)
	if not Vfx.lite:
		Vfx.space_ring(c, 0.9, col, 0.24, 0.02)
	Combat.hitstop(0.025)
	Sfx.play("block", -5.0, randf_range(1.4, 1.8))
	player.cam.add_trauma(0.07)
	player.melee.combat_event.emit("air_swat", {"back": false})


# ---------- 瞬身剑诀 ----------

## 刚瞬身到对手背后（反击窗口里）按「剑」/「诀」：贴着后心九柄飞剑齐发，把人轰飞。耗一成灵力；灵力不够返回 false（走平常的点射）
func _counter_blast() -> bool:
	var cost := player.mp_max() * 0.1
	if player.mp < cost or not _alive(target):
		return false
	var t := target
	_counter_until = -10.0
	player.mp -= cost
	player.caster.hold_regen()
	Combat.slowmo_release(0.12)
	_end_blade()
	state = A.IDLE
	_engage = ENGAGE_KEEP
	var dir := _dir_to(t)
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	rig.play("f_beam")
	_point_t = 0.4
	var c := Proj.aim_of(t)
	var col := _col()
	var fb := Basis(Vector3.UP, face_yaw)
	var cols := Realm.lines(player.realm)
	for i in 9:
		var k := float(i) - 4.0
		var from := player.center() + fb * Vector3(k * 0.34, 0.25 + 0.1 * absf(k), 0.3)
		Proj.launch(player, Proj.K.SWORD, from, t, c, {"dmg": _base() * 0.16, "color": cols[i % cols.size()], "speed": 120.0,
				"hold": 0.02 + 0.012 * absf(k), "turn": 20.0, "light": true, "lite": true, "sfx": i % 3 == 0, "trauma": 0.01,
				"life": 0.8, "scale": Proj.SWORD_SCALE * 1.5, "tw": 0.14})
	# 剑气贯体：这一下结算伤害和击飞（破防）
	var kd := _knock_dir("fwd", dir)
	var dmg := _base() * 1.4 * Moves.dmg_scale(_string_n)
	var res := _hit_target(t, {"dmg": dmg, "dir": kd, "kb": 38.0 * _kbm(true), "stun": 1.0, "launch": "fwd", "heavy": true, "brk": true,
			"gd": 6.0, "contact": c, "stop": 0.12, "pst": dmg * 0.6, "step": step, "air": true, "swing": kd})
	if res == 0 or res == 2:
		_string_n += 1
		_add_combo(dmg)
		if _is_launched(t):
			_chase = false
			_on_launch(t, "fwd", c, kd, 0.12)
	Vfx.cast_flash(player.center() + dir * 0.6, col, 1.4)
	Vfx.crescent(c, kd, col, 3.2)
	Vfx.shockwave(c, kd, Color.WHITE.lerp(col, 0.4), 2.0)
	Combat.hitstop(0.1, 0.0)
	Sfx.play("slam", -3.0, 1.3)
	var cam := player.cam
	cam.fov_punch(9.0)
	cam.add_trauma(0.4)
	cam.impact(0.5)
	player.melee.combat_event.emit("air_counter", {"blast": true})
	return true


# ---------- 瞬身 / 挣脱 / 破防 ----------

## 按下「御」或「闪」的那一刻：有对手的攻击马上要打到自己（离判定不到瞬身窗口）→ 直接瞬身到它背后。
## 挨打硬直、被破防、倒地、对波中不行；被打飞的途中可以（反制对手的追击）。瞬身了返回 true
func try_vanish_press() -> bool:
	if player.st != Player.St.AIR or player.ult.active or player.mp < Moves.VANISH_MP or player.dead:
		return false
	if state == A.GRABBED or state == A.BRAWL or state == A.THROW:
		return false
	if state == A.HURT or state == A.CRUSH or state == A.DOWN or state == A.CLASH or (state == A.BLOWN and _t < 0.2):
		return false
	var best: Node3D = null
	var bt := Moves.vanish_window(_vanish_count())
	for n: Node in player.get_tree().get_nodes_in_group("air_foes"):
		if n.has_method("time_to_hit"):
			var tt := float(n.call("time_to_hit"))
			if tt <= bt:
				best = n as Node3D
				bt = tt
	if best == null:
		return false
	_vanish_counter(best, false)
	return true


## 挣脱：耗一格罡气把身边的人震开，自己从硬直里出来（短暂无敌）
func _burst() -> void:
	burst -= 1.0
	_iframe = 0.7
	_protect(Moves.PVP_PROTECT)
	Combat.clear_hitstop()
	var c := player.center()
	var col := _col()
	Vfx.shockwave(c, Vector3.UP, col, 2.6)
	Vfx.shockwave(c, _fwd(), Color.WHITE.lerp(col, 0.5), 2.0)
	Vfx.ribbon_burst(c, Vector3.UP, col, 14, 14.0, 180.0, 0.4, Vector3.ZERO)
	_warp(c, 1.4)
	Sfx.play("slam", -3.0, 1.5)
	Sfx.play("perfect", -5.0, 1.2)
	var cam := player.cam
	cam.impact(0.5)
	cam.fov_punch(8.0)
	cam.add_trauma(0.4)
	Combat.slowmo(0.3, 0.1, 0.25)
	for e in Proj.targets(player.get_tree()):
		var d := Proj.aim_of(e) - c
		if d.length() < Moves.BURST_R + Proj.body_r(e) and e.has_method("air_hit"):
			e.air_hit(player, {"dmg": _base() * 0.3, "dir": d.normalized() if d.length_squared() > 0.01 else _fwd(),
					"kb": 20.0, "stun": 0.8, "launch": "", "heavy": true, "burst": true, "contact": Proj.aim_of(e)})
	state = A.IDLE
	_t = 0.0
	_push = Vector3.ZERO
	_tumble = 0.0
	rig.play("f_burst")
	_point_t = 0.3
	player.melee.combat_event.emit("air_burst", {})


## 被对手的挣脱震开（air_foe.gd 调）：不掉血，连段断掉，人被推出去一小段
func receive_burst(src: Node3D) -> void:
	_repel(src, 17.0, 0.32, "air_repelled")


## 被对手的护体弹开（连着打在护体上两下以上时可能发生，air_foe.gd 调）：不掉血，这一串断掉、被震退半步
func receive_parry(src: Node3D) -> void:
	_repel(src, 8.0, 0.3, "air_parried")


func _repel(src: Node3D, spd: float, dur: float, ev: String) -> void:
	if player.st != Player.St.AIR or state == A.CLASH or state == A.DOWN or state == A.DEAD or player.ult.active:
		return
	var d := player.center() - Proj.aim_of(src)
	d = (d.normalized() + Vector3.UP * 0.15).normalized() if d.length_squared() > 0.01 else -_fwd()
	_end_blade()
	player.hero.set_glow(0.0, _col())
	combo = 0
	combo_dmg = 0.0
	_string_n = 0
	_queued = false
	_buf_at = -10.0
	_launched = null
	state = A.HURT
	_t = 0.0
	_dur = dur
	_push = d * spd
	rig.play("f_hurt")
	Combat.clear_hitstop()
	player.cam.add_trauma(0.3)
	player.melee.combat_event.emit(ev, {})


## 护体被破：吃下这一击的六成伤害，双臂被震开，一小段时间内挡不了、闪不了
func _crush(src: Node3D, info: Dictionary, dir: Vector3) -> void:
	var dmg := float(info.get("dmg", 8.0)) * 0.6
	var m := player.melee
	if m.hp - dmg <= 0.0:
		var i2 := info.duplicate()
		i2["dmg"] = dmg
		_hurt(src, i2, dir, true)
		return
	m.hp -= dmg
	_since_hurt = 0.0
	player.mp = maxf(player.mp - GUARD_MP * 2.0, 0.0)
	player.caster.hold_regen()
	_end_blade()
	var c: Vector3 = info.get("contact", player.center())
	var swing := dir.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	Vfx.blade_clash(c, -dir, 1.3)
	Vfx.shockwave(c, -dir, Color(1.0, 0.45, 0.3), 1.6)
	Vfx.impact(c, swing, Color(1.0, 0.5, 0.3), 4)
	Combat.hitstop(0.12)
	Sfx.play("slam", -2.0, 1.4)
	Sfx.play("block", 0.0, 0.6)
	_flash = 1.0
	_flash_on = true
	player.hit_shake(0.12)
	var cam := player.cam
	cam.add_trauma(0.45)
	cam.impact(0.5)
	combo = 0
	combo_dmg = 0.0
	_string_n = 0
	_queued = false
	_buf_at = -10.0
	state = A.CRUSH
	_t = 0.0
	_dur = Moves.CRUSH_T * 0.7      # 主角被破防的硬直比对手的短一些
	_push = dir * 7.0
	rig.play("f_crush")
	player.melee.combat_event.emit("air_crushed", {"pos": c})


# ---------- 每帧 ----------

func tick(dt: float) -> void:
	var cdt := Combat.cdt(dt)
	_clock += cdt
	if _aura_p != null:
		_aura_p.emitting = _aura_want and player.st == Player.St.AIR and not player.dead
	_aura_want = false
	_shot_cd -= dt
	_iframe -= dt
	_tick_pvp(dt)
	if parry_t > 0.0:
		parry_t -= dt
		if parry_t <= 0.0:
			parry_t = 0.0
			_parry_dom = false
			if state == A.GUARD and not guard_held:
				_to_idle()
	elif _parry_dom:
		_parry_dom = false
	var awk_full := awaken >= 100.0 and awake_t <= 0.0
	if awk_full and not _awk_full_was and player.hero_id != "" and not player.dead:
		Sfx.play("ult_ready", -2.0, 1.0)      # 2026-11-25 觉醒槽刚攒满：一声提示（触屏上「觉」键同时浮出来）
		player.melee.combat_event.emit("air_awaken_ready", {})
	_awk_full_was = awk_full
	var aw := awake_t > 0.0
	if aw != _awake_was:
		# 2026-11-24 英雄觉醒形态：M1 换觉醒那张表（苍鸿五段），技能脚本跟着变形 / 收回
		_awake_was = aw
		ATK = _chain_awake if aw and not _chain_awake.is_empty() else _chain_base
		if not aw and player.kit != null and player.kit.has_method("on_awake_end"):
			player.kit.call("on_awake_end")
	for i in 3:
		cds[i] = maxf(cds[i] - dt, 0.0)
	# 对波 / 对拼被别的事打断（开大、瞬身、落地、转光遁、陨落…）：这一场收干净（对手退出相持），镜头别留在演出机位上。
	# 放在最前面：落地 / 陨落那几条路径下面会提前 return
	if _clash_live and state != A.CLASH:
		_clash_abort()
	if _brawl_foe != null and state != A.BRAWL:
		_brawl_drop()
	if state != A.CLASH and player.caster.clash_mode:
		player.caster.end_clash()   # 相持被别的事打断（挨打、落地…）：剑流收掉
	if state != A.CLASH and _cfx != null:
		_drop_cfx()
	_lie = move_toward(_lie, 1.0 if state == A.DOWN else 0.0, dt * (14.0 if state == A.DOWN else 4.0))
	if not AwakenFx.primed and player.st == Player.St.AIR:
		# 描边 / 空间波动的着色器还没编过（载入时不到结丹）：一进空战就先编好。
		# 空间波动圈在拳劲对拼、坠星踏、弹回气弹里都会用到，等用到的那一下才编会卡在打得最紧的地方
		AwakenFx.prime(player)
	if awake_t > 0.0:
		awake_t -= dt
		_aura_t -= dt
		if state != A.CHARGE and state != A.GATHER and player.st == Player.St.AIR and not player.dun_active and not AwakenFx.debug_no_ribbon 				and _aura_rise(0.16, 9.0):
			Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.3, 0.0), Vector3.UP, _col(), 4, 9.0, 30.0, 0.35, Vector3.ZERO)
		if awake_t <= 0.0:
			player.hero.set_glow(0.0, _col())
	_tick_cine(dt)
	# 保护中：身上一层一明一暗的微光（对面的木偶上也有，remote_player.gd）
	var prot_glow := 0.2 + 0.14 * sin(_now() * 24.0) if _prot > 0.0 else 0.0
	if _flash > 0.0 or _flash_on or prot_glow > 0.0:
		_flash = maxf(_flash - dt * 7.0, 0.0)
		_flash_on = _flash > 0.0 or prot_glow > 0.0
		player.hero.set_flash(maxf(_flash, prot_glow))
	if combo > 0:
		_combo_t -= dt
		if _combo_t <= 0.0:
			combo = 0
			combo_dmg = 0.0
	if combo == 0:
		_string_n = 0      # 连段断了：伤害衰减、追击次数都重新算
		if not _is_launched(_launched):
			_chase_n = 0
	burst = minf(burst + dt / Moves.BURST_REGEN, Moves.BURST_MAX)
	_brawl_cd -= dt
	_drives = false
	drive_vel = Vector3.ZERO
	if state == A.DEAD:
		# 陨落：定在原地（身形已经溃散），什么都不处理；被复活 / 被送回地面了才出来
		if player.dead and player.st == Player.St.AIR:
			_drives = true
			rig.update(cdt)
			_upkeep_lock()
			return
		revive()
	if player.st != Player.St.AIR:
		if state != A.IDLE or _engage > 0.0:
			_leave()
		_stream = 0.0
		return
	_engage = maxf(_engage - dt, 0.0)
	_since_hurt += dt
	if _since_hurt > REGEN_WAIT and state != A.BLOWN:
		player.melee.hp = minf(player.melee.hp + REGEN * player.regen_k * dt, player.melee.HP_MAX)      # regen_k：新图里关卡设 0（只有法宝 / 药能回血）
	_t += cdt
	var holding := Input.is_action_pressed("attack") and not player.is_dashing() and not player.caster.demo_hold_attack
	_held = _held + dt if holding else 0.0
	if _held <= 0.0:
		_hold_used = false
	_tick_shot_hold(dt)
	# 2026-11-23：对波预警里「剑」本来就按着（自己也在连发，或者按住等起手）：直接接波，不用松开再点一下。
	# 预警时本机在时停，按住攒连发的时间走得极慢 —— 以前两边都按着「剑」要等一两秒才对得上
	if not pvp_legacy and warn_k() > 0.0 and Input.is_action_pressed("air_shot") and _pvp(_warn_foe):
		_accept_clash()
	_tick_rain(dt)
	# 远处的目标按下「攻」还没松：松手 = 点按 → 冲过去连打；按满 HOLD_T 由下面的长按分支转蓄力
	if _pend_far:
		if state != A.IDLE or not _alive(target):
			_pend_far = false
		elif _held <= 0.0:
			_pend_far = false
			_start_rush()
		else:
			_face_target()
	if _swat_t > 0.0:
		_swat_t -= dt
		if _swat_t <= 0.0 and (state == A.GUARD or state == A.IDLE):
			rig.play("f_guard" if state == A.GUARD else "f_idle")
	if target != null and not _alive(target):
		target = null
	if _launched != null and not _alive(_launched):
		_launched = null
	if player.ult.active or player.dun_active:
		if state != A.IDLE:
			_to_idle()
		_upkeep(dt, cdt)
		return

	if _buf_at > 0.0:
		if _now() - _buf_at > BUFFER:
			_buf_at = -10.0
		elif _consume():
			_buf_at = -10.0
	# 长按：空中连击里 = 直接出终结重击；空手悬停 / 突进途中 / 一拳打完之后 = 转蓄力（连段里转的直接从一截起蓄）
	if _held >= HOLD_T and not _hold_used and not player.caster.busy():
		if state == A.ATTACK and JUG.has(move_id) and _is_launched(target):
			if _hit_done:
				_hold_used = true
				_start_finisher()
		elif state == A.IDLE and _is_launched(_launched) and _reach(_launched):
			_hold_used = true
			target = _launched
			_start_finisher()
		elif state == A.IDLE or state == A.RUSH or state == A.DASH:
			_start_charge()
		elif state == A.ATTACK and _hit_done and str(_atk.get("next", "")) != "":
			_start_charge(true)

	# 御风突进：有目标时按住「闪」，高速冲到它身前
	if state == A.IDLE and _dash_wanted() and not player.dun_active:
		var dt_t := _dash_target()
		if dt_t != null and Proj.aim_of(dt_t).distance_to(player.center()) - _gap(dt_t) > 3.0:
			_start_dash(dt_t, false)

	# 聚气：长按护体（没人在打自己时）就转入聚气；键盘上 V 仍然可以直接聚
	var by_guard := _guard_gather()
	var gather := (Input.is_action_pressed("gather") or demo_gather or by_guard) and not player.is_dashing()
	if gather and (state == A.IDLE or (by_guard and state == A.GUARD)) and not player.caster.busy():
		state = A.GATHER
		_t = 0.0
		_aura_t = 0.0
		_engage = ENGAGE_KEEP
		rig.play("f_gather")
		Sfx.play("ascend", -12.0, 1.3)

	match state:
		A.CLASH:
			_tick_clash(dt)
		A.GATHER:
			_tick_gather(dt, gather)
		A.DOWN:
			_drives = true
			if _t >= _dur:
				_iframe = 0.6
				_to_idle()
				_protect(Moves.PVP_PROTECT)
				_drives = true
				drive_vel = Vector3.UP * 9.0   # 起身：这一帧仍由招式给速度，免得被判成落地
				Vfx.takeoff_burst(player.global_position, _col(), 0.5)
		A.IDLE:
			_tick_idle(dt)
		A.RUSH:
			_tick_rush(cdt)
		A.THROW:
			_tick_throw(cdt)
		A.BRAWL:
			_tick_brawl(dt)
		A.STOMP:
			_tick_stomp(cdt)
		A.GRABBED:
			# 被擒住：位置由对手摆（grab_hold），连点「攻」挣开；对手没了 / 太久没下文就自己松开
			_drives = true
			if not _alive(_grab_by) or _t > 2.0:
				_grab_by = null
				_to_idle()
		A.DASH:
			_tick_dash(cdt)
		A.ATTACK:
			_tick_attack(cdt)
		A.CHARGE:
			_tick_charge(dt)
		A.SMASH:
			_tick_smash(cdt)
		A.GUARD:
			_face_target()
			if not guard_held and parry_t <= 0.0:
				_to_idle()
		A.HURT, A.BLOWN, A.CRUSH:
			_drives = true
			drive_vel = _push
			_push = _push.move_toward(Vector3.ZERO, (14.0 if state == A.BLOWN else 30.0) * cdt)
			if state == A.BLOWN:
				_tumble += 11.0 * cdt
				_blown_wall()
				if _push.y < -5.0 and _push.length() > 12.0 and _on_floor():
					_crash_ground()
					_upkeep(dt, cdt)
					return
			if _t >= _dur:
				var settled := state == A.BLOWN and _blown_launch
				_to_idle()
				if settled:
					_protect(Moves.PVP_PROTECT)      # 真人对打：被打飞落定之后有一段保护
	if _gslide != Vector3.ZERO:
		if state == A.GUARD or state == A.IDLE:
			_tick_gslide(dt)
		else:
			_gslide = Vector3.ZERO      # 滑退途中出招 / 又挨了打：交给新的状态
	_upkeep(dt, cdt)


## 姿势权重、镜头锁定、整身翻滚回正、布料飘动
func _upkeep(dt: float, cdt: float) -> void:
	# 换位连段还在打（瞬步换位之后 1.6 秒内的出招 / 重击 / 突进 / 投技）：镜头一直按住，整串打完才平稳回正
	if _clock - _swap_at < 1.6 and (state == A.ATTACK or state == A.SMASH or state == A.RUSH or state == A.THROW or state == A.STOMP):
		player.cam.duel_hold(0.25)
	_g_lean = lerpf(_g_lean, 0.0, 1.0 - exp(-7.0 * cdt))
	var on := engaged() and not player.dun_active
	rig.w_up_target = 1.0 if on else 0.0
	rig.w_leg_target = 1.0 if on else 0.0
	rig.update(cdt)
	if state != A.BLOWN:
		_tumble = lerp_angle(_tumble, 0.0, 1.0 - exp(-14.0 * dt))
	# 朝目标的仰俯：突进 / 出手时身体对准斜上斜下的目标
	var want := 0.0
	if state == A.STOMP and _stomp_ph == 0:
		want = -1.35      # 坠星踏：脚朝下直着砸
	elif _alive(target) and (state == A.RUSH or state == A.DASH or state == A.ATTACK or state == A.SMASH):
		var d := Proj.aim_of(target) - (player.global_position + Vector3(0.0, BODY_Y, 0.0))
		want = clampf(atan2(d.y, maxf(_flat(d).length(), 0.5)), -1.2, 1.2)
	_aim_pitch = lerpf(_aim_pitch, want, 1.0 - exp(-12.0 * dt))
	var fast := clampf(player.velocity.length() / 24.0, 0.0, 1.0)
	_stream = lerpf(_stream, fast, 1.0 - exp(-6.0 * dt))
	player.hero.stream_add = _stream
	if awake_t > 0.0 and state != A.CHARGE and not player.dun_active:
		# 觉醒的身形现在主要靠描边（awaken_fx.gd）读出来：整身泛光收到很淡，衣服的本色还看得见
		player.hero.set_glow(0.04 + 0.012 * sin(Time.get_ticks_msec() * 0.02), _col())
	_upkeep_lock()


func _upkeep_lock() -> void:
	var cam := player.cam
	if cam.lock != null and cam.lock != _lock_node:
		_lock_node = null   # 别人（剑冢）在锁：不碰
		return
	var want: Node3D = null
	if engaged() and _alive(target) and Proj.aim_of(target).distance_to(player.center()) < 80.0:
		want = target
	if want != null:
		cam.lock = want
		_lock_node = want
		var sep := Proj.aim_of(want).distance_to(player.center())
		# 对手被打飞得再远，镜头也只比平时多拉开两米（跟着主角走，靠转向把对手留在画面里；拉远了看不清主角在哪）
		cam.lock_zoom = clampf(5.5 + sep * 0.05 + Proj.body_r(want) * 0.6, 6.0, 8.5)
		cam.duel = true
	elif _lock_node != null:
		cam.lock = null
		cam.duel = false
		_lock_node = null


func _tick_idle(dt: float) -> void:
	if _point_t > 0.0:
		_point_t -= dt
		if _point_t <= 0.0:
			rig.play("f_idle")
	if _alive(target) and engaged():
		_face_target()
	else:
		has_face = false


func _face_target() -> void:
	if not _alive(target):
		has_face = false
		return
	var d := _flat(Proj.aim_of(target) - player.center())
	if d.length_squared() > 0.04:
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


func _tick_rush(cdt: float) -> void:
	if not _alive(target):
		_to_idle()
		return
	_drives = true
	var dir := _dir_to(target)
	var spot := _stick_point(target, dir)
	var to := spot - player.global_position
	var dl := to.length()
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	drive_vel = to.normalized() * minf(RUSH_SPD, dl / maxf(cdt, 1e-3))
	_trail_ghosts(cdt, 0.04)
	if dl < 1.0 or _t > 1.1:
		player.cam.fov_punch(-3.0)
		_start_attack(0)


## 突进 / 重击冲刺沿途的残影
func _trail_ghosts(cdt: float, every: float) -> void:
	_ghost_t += cdt
	if _ghost_t >= every:
		_ghost_t = 0.0
		Vfx.body_ghost(player.visual, Color.WHITE.lerp(_col(), 0.6), 0.4, 0.22)


## 乱舞的一下：闪到对手另一侧（上下也错开），一道弧光斩过去
func _flurry_hit() -> void:
	var t := target
	_flurry_n += 1
	var sgn := -1.0 if _flurry_n % 2 == 0 else 1.0
	_flash_step(sgn * randf_range(1.7, 2.6), randf_range(-0.8, 1.4))
	rig.play(["f1", "f2", "f3", "f4"][_flurry_n % 4])
	var c := Proj.aim_of(t)
	var kd := _dir_to(t)
	var dmg := _base() * 0.22
	var res := _hit_target(t, {"dmg": dmg, "dir": kd, "kb": 1.0, "stun": 0.5, "launch": "", "heavy": false,
			"contact": c, "stop": 0.02, "pst": dmg * 0.5, "step": step, "air": true, "swing": kd})
	if res >= 0:
		_add_combo(dmg)
	Vfx.crescent(c, kd, _col(), 2.6)
	Vfx.hit(c, kd, _col(), 1.0)
	if t.has_method("chip_colors"):
		Vfx.debris(c, kd + Vector3.UP * 0.2, t.chip_colors(), 5, 6.0, 1.0)
	Combat.hitstop(0.025, 0.02)
	Sfx.play("hit", -3.0, 1.1 + 0.06 * float(_flurry_n))
	player.cam.add_trauma(0.14)


func _tick_attack(cdt: float) -> void:
	var a := _atk
	var hit_t: float = a["hit"]
	_drives = true
	if _open_hold > 0.0:
		# 真人对打的起手前摇：人已经到了身前、架势摆着，判定前这一小段对方看得见、来得及按「御」
		_open_hold = _open_end - _now()
		_t = 0.0
		drive_vel = Vector3.ZERO
		if _alive(target):
			var od := _dir_to(target)
			face_yaw = atan2(-od.x, -od.z)
			has_face = true
			drive_vel = ((_stick_point(target, od) - player.global_position) * 12.0).limit_length(40.0)
		if _open_hold <= 0.0:
			rig.play(a["seq"])
			if a["limb"] == "sw":
				_blade_on()
			Sfx.play("swing_heavy" if int(a["tier"]) >= 1 else "swing", -7.0, 1.15)
		return
	if _flurry_left > 0:
		# 乱舞进行中：正招的计时先按住
		_t = 0.0
		drive_vel = Vector3.ZERO
		if not _alive(target):
			_flurry_left = 0
		else:
			_flurry_cd -= cdt
			if _flurry_cd <= 0.0:
				_flurry_cd = 0.075
				_flurry_left -= 1
				_flurry_hit()
				if _flurry_left == 0:
					_flash_step(0.0)
					rig.play(a["seq"])
		return
	if not _alive(target) and not _hit_done and float(a.get("lunge_v", 0.0)) > 0.0 and _t >= float(a.get("dash_at", 0.0)) and not _rooted:
		drive_vel = _fwd() * float(a["lunge_v"])      # 2026-11-24 一闪这类突进招：没有目标就朝前冲出去斩
	if _alive(target) and not _rooted:
		var dir := _dir_to(target)
		face_yaw = atan2(-dir.x, -dir.z)
		var flying := _is_launched(target)
		var to := (_intercept_point(target, hit_t - _t) if flying and not _hit_done else _stick_point(target, dir)) - player.global_position
		if not _hit_done and _t < float(a.get("dash_at", 0.0)):
			drive_vel = Vector3.ZERO      # 2026-11-25 崩山这类：先原地蓄势，到 dash_at 才冲出去
		elif not _hit_done:
			# 出手前吸到身前：保证判定时刻刚好到位（追还在飞的对手、带着冲势的冲刺攻击要快得多）
			drive_vel = (to / maxf(hit_t - _t, 0.02)).limit_length(150.0 if flying or move_id == _dash_id or bool(a.get("lunge", false)) else 80.0)
			# 2026-11-24：一帧走的路不超过离出手位置的距离（长帧 —— 头一回放某个特效现编着色器、截图 —— 时一步冲过头，判定那一下就够不着了）
			drive_vel = drive_vel.limit_length(to.length() / maxf(player.get_process_delta_time(), 0.001))
		elif not flying or _juggled(target):
			drive_vel = (to * 8.0).limit_length(22.0)  # 打中后跟着对手被打退的势头贴住（浮空的也贴住）
	elif _alive(target) and a.has("proj"):
		# 放飞行道具的招：人留在原地，只转身朝着目标（剑气 / 飞剑由技能脚本朝目标放）
		var pd := _dir_to(target)
		face_yaw = atan2(-pd.x, -pd.z)
		has_face = true
	if not _hit_done and _t >= hit_t:
		_hit_done = true
		_resolve(a, _knock_dir(str(a.get("launch", "")), _fwd()) if a.has("launch") else _fwd(), 1.0)
		if state != A.ATTACK:
			return
	if a["limb"] == "sw" and _t > hit_t + 0.12:
		_end_blade()
	if bool(a.get("auto", false)) and _hit_done and not _queued and str(a.get("next", "")) != "":
		_queued = true      # 2026-11-24 千刃 / 瞬狱 / 断月这类连着出的技能：不用再按，到点自己接下一下
		_queued_id = ""
	# 连招窗口：缓冲着的下一招到点就接上（方向派生 / 终结重击记在 _queued_id 里）
	if _queued and _t >= float(a["chain"]) and not _whiff_lock:
		var nid := _queued_id if _queued_id != "" else str(a.get("next", ""))
		if nid == "fin":
			_start_finisher()
			return
		if nid != "":
			_start_move(nid, true)
			return
	var end_t: float = float(a["end"]) * (0.8 if _whiff else 1.0) + _whiff_pen
	if _t >= end_t:
		_last_id = move_id
		_last_step = step
		_last_end = _clock
		_to_idle()


func _tick_charge(dt: float) -> void:
	_drives = true
	_charge += dt
	_face_target()
	var k := charge_k()
	if k >= Moves.BRK_AT and not _brk_cued:
		# 蓄到破防线：拳头上金光一闪（这之后松手，对手护体挡不住）
		_brk_cued = true
		var gold := Color(1.0, 0.85, 0.4)
		Vfx.glint(rig.hand_pos(), gold, 1.6)
		Vfx.shockwave(player.center(), Vector3.UP, gold, 0.9)
		Sfx.play("perfect", -9.0, 1.6)
	_aura_t -= dt
	var tick_now := _aura_t <= 0.0
	if _aura_rise(0.11, 7.0 + 6.0 * k) or (Vfx.lite and tick_now):
		var c := _col()
		if not Vfx.lite:
			Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP, c, 3 + int(4.0 * k), 7.0 + 6.0 * k,
					35.0, 0.35, Vector3.ZERO)
		else:
			_aura_t = 0.11
		if k >= 1.0:
			Vfx.glint(rig.hand_pos(), Color.WHITE.lerp(c, 0.3), 1.0)
	player.cam.add_trauma(0.012 + 0.02 * k)
	player.hero.set_glow(0.16 * k, _col())
	var release := _held <= 0.0 if _auto_release < 0.0 else _charge >= _auto_release
	if release or _charge >= CHARGE_FULL + CHARGE_MAX:
		player.hero.set_glow(0.0, _col())
		_release_charge()


func _tick_smash(cdt: float) -> void:
	var sm: Dictionary = SMASH[_smash_kind]
	_drives = true
	var flat := _fwd()
	if _alive(target):
		flat = _dir_to(target)
	var kd := _knock_dir(_smash_kind, flat)
	if _sm_dash:
		# 冲刺段：贴到目标身前再挥拳
		if not _alive(target):
			_smash_swing()
			return
		var spot := _stick_point(target, flat)
		var to := spot - player.global_position
		var dl := to.length()
		face_yaw = atan2(-flat.x, -flat.z)
		has_face = true
		var spd := clampf(dl / 0.12, 78.0, SMASH_FLY_SPD) if _sm_fly_far else 78.0
		drive_vel = to.normalized() * minf(spd, dl / maxf(cdt, 1e-3))
		_trail_ghosts(cdt, 0.02 if _sm_fly_far else 0.03)
		if dl < 0.9 or _t > _sm_fly_max:
			if _sm_fly_far:
				Vfx.dash_end(player.center(), to.normalized(), _col(), 1.0)
			_smash_swing()
		return
	var hit_t: float = sm["hit"]
	if _open_hold > 0.0:
		# 真人对打的起手前摇（同 _tick_attack）：飞到了，拳头先收着，按够了再打出去
		_open_hold = _open_end - _now()
		_t = 0.0
		drive_vel = Vector3.ZERO
		if _alive(target):
			face_yaw = atan2(-flat.x, -flat.z)
			has_face = true
			drive_vel = ((_stick_point(target, flat) - player.global_position) * 12.0).limit_length(40.0)
		if _open_hold <= 0.0:
			rig.play(sm["seq"])
			Sfx.play("swing_heavy", -3.0, 0.9)
		return
	if _alive(target) and not _hit_done:
		# 追击时目标还在飞：按击飞方向的反侧贴住它
		var s_dir := kd if _chase else flat
		var spot := Proj.aim_of(target) - s_dir * _gap(target, Proj.aim_of(target) - s_dir * 10.0) - Vector3(0.0, BODY_Y, 0.0)
		spot.y = maxf(spot.y, 0.0)
		drive_vel = ((spot - player.global_position) / maxf(hit_t - _t, 0.02)).limit_length(140.0)
		face_yaw = atan2(-flat.x, -flat.z)
	if not _hit_done and _t >= hit_t:
		_hit_done = true
		var k := _smash_k
		# 蓄力过半（或追击的终结重击）即破防：对手护体挡不住
		var info := {"name": sm["name"], "dmg": 1.5 + 1.3 * k, "kb": float(sm["spd"]) * (0.85 + 0.3 * k), "stun": 1.0,
				"stop": 0.13 + 0.07 * k, "limb": sm["limb"], "tier": 1, "trauma": 0.45 + 0.2 * k, "push": 0.12 + 0.06 * k,
				"swords": 0, "launch": _smash_kind, "heavy": true, "gd": 3.0, "brk": k >= Moves.BRK_AT or _chase}
		_resolve(info, kd, 1.0)
		if state != A.SMASH:
			return
	if _t >= float(sm["end"]) * (0.75 if _whiff else 1.0) + _whiff_pen:
		_last_step = -1
		_last_id = ""
		_to_idle()


func _tick_shot_hold(dt: float) -> void:
	_shot_held = _shot_held + dt if Input.is_action_pressed("air_shot") and not player.is_dashing() else 0.0


## E 是否按住到了连发的时长（air_caster.gd 读）
func shot_hold() -> float:
	if not has_volley():
		return 0.0      # 2026-11-24 修（复核 combat-1）：苍鸿的 E 是一闪，按住不能转成万剑连发
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH or state == A.RUSH or state == A.DASH or state == A.CRUSH:
		return 0.0
	return _shot_held


## 这位英雄有没有万剑连发 / 飞剑对波（英雄表的 volley 字段，缺省有；英雄系统关着 = 老规矩，都有）。
## 苍鸿没有：按住 E 不连发、不接对波、不给对波预警（air_caster.tick / start_clash / foe_volley_started / clash_warn / can_accept_clash 都问它）
func has_volley() -> bool:
	return player.hero_id == "" or bool(player.hero_def.get("volley", true))


func _to_idle() -> void:
	_end_blade()
	player.hero.set_glow(0.0, _col())
	state = A.IDLE
	_t = 0.0
	_queued = false
	_opener = false
	_open_hold = 0.0
	_whiff_pen = 0.0
	if _parry_dom and parry_t > 0.0 and player.st == Player.St.AIR and not player.dun_active and not player.ult.active and not player.dead:
		# 剑域还开着：反斩收招后回到招架架势，接下一个来犯的（复核 combat-7）
		state = A.GUARD
		rig.play("ck_parry")
		return
	if guard_held and player.st == Player.St.AIR and not player.caster.busy():
		state = A.GUARD
		rig.play("f_guard")
		return
	rig.play("f_idle")


func _end_blade() -> void:
	player.melee.air_blade(false)
	if player.blade_always():
		player.melee.sword.visible = true      # 2026-11-24 苍鸿：剑一直在手上，收的只是刀光


## 亮剑出招（刀光拖起来）。剑一直在手的英雄：先当它收着，air_blade 才会把刀光打开
func _blade_on() -> void:
	if player.blade_always():
		player.melee.sword.visible = false
	player.melee.air_blade(true)


## 离开空战（落地 / 转光遁）：收招、放开镜头
func _leave() -> void:
	_throw_abort()
	_brawl_abort()
	_grab_by = null
	_end_blade()
	_parry_dom = false
	state = A.IDLE
	_opener = false
	_open_hold = 0.0
	_whiff_pen = 0.0
	_engage = 0.0
	_queued = false
	_buf_at = -10.0
	_tumble = 0.0
	_aim_pitch = 0.0
	has_face = false
	target = null
	_launched = null
	_counter_until = -10.0
	_last_id = ""
	_dash_atk = false
	rig.w_up_target = 0.0
	rig.w_leg_target = 0.0
	player.hero.stream_add = 0.0
	_upkeep_lock()
	_end_cine()


## 闪现打断（Player.blink 调）
func on_blink() -> void:
	_throw_abort()
	if state == A.CHARGE:
		player.hero.set_glow(0.0, _col())
	if state == A.BLOWN:
		# 受身：被打飞的途中稳住身形闪出去，不吃后面的追击
		Vfx.shockwave(player.center(), Vector3.UP, _col(), 1.0)
		player.melee.combat_event.emit("air_tech", {})
		_protect(Moves.PVP_PROTECT)          # 真人对打：受身之后有一段保护
	_end_blade()
	state = A.IDLE
	_t = 0.0
	_queued = false
	_buf_at = -10.0
	_tumble = 0.0
	_iframe = maxf(_iframe, 0.25)
	Combat.clear_hitstop()
	rig.play("f_idle")


# ---------- 出招结算 ----------

func _limb_pos(limb: String) -> Vector3:
	match limb:
		"lh":
			return rig.left_hand_pos()
		"rf":
			return rig.foot_pos(true)
		"lf":
			return rig.foot_pos(false)
		"sw":
			return rig.blade_point(0.7)
	return rig.hand_pos()


## a：招式参数；kd：击退 / 击飞方向；mul：伤害倍率
func _resolve(a: Dictionary, kd: Vector3, mul: float) -> void:
	_prot_end()         # 真人对打：这一下打出去了，起身保护到此为止
	var t := target
	var hit := false
	if a.has("proj"):
		# 2026-11-24 英雄技能：这一下不是拳脚判定，是放飞行道具（断月的剑气、万剑归宗的剑）—— 交给技能脚本
		if player.kit != null and player.kit.has_method("on_proj"):
			player.kit.call("on_proj", str(a["proj"]), move_id, t if _alive(t) else null)
		_kit_fx("hit", {"hit": false, "dir": kd})
		return
	if bool(a.get("show", false)):
		_kit_fx("hit", {"hit": false, "dir": kd})      # 2026-11-25 只摆姿势的招（觉醒起手）：没有判定
		return
	if a.has("aoe"):
		# 2026-11-25 范围招（震岳的一圈、碎星的一条线、千臂的一片）：圈 / 线里的都挨打，不只是锁着的那一个
		var any := _resolve_area(a, kd, mul)
		_kit_fx("hit", {"hit": any, "dir": kd, "pos": _last_contact})
		if not any:
			_whiff = true
			player.melee.combat_event.emit("air_whiff", {})
		return
	if bool(a.get("qi", false)):
		# 剑气：挥出去带一道新月弧光（觉醒的剑心通明、一闪、千刃）
		var qc := player.center() + _fwd() * (1.6 + float(a.get("reach", 0.0)))
		Vfx.crescent(qc, _fwd(), Color.WHITE.lerp(_col(), 0.55), 1.4 + 0.5 * float(a.get("reach", 0.0)))
	var reach := float(a.get("reach", 0.0))
	if _alive(t):
		var tc := Proj.aim_of(t)
		var from := player.global_position + Vector3(0.0, BODY_Y, 0.0)
		var d := tc - from
		# 还在飞的目标多给一点余量（按它一两帧能飞出去的距离）
		var slack := 0.0
		if _is_launched(t) and t.has_method("velocity"):
			slack = minf((t.velocity() as Vector3).length() * 0.06, 3.0)
		if d.length() <= _gap(t) + 1.7 + slack + reach and _seen(from, tc):
			var dn := d.normalized() if d.length_squared() > 1e-4 else _fwd()
			var contact := tc - dn * minf(_surf(t, from), d.length())
			_last_contact = contact
			var heavy: bool = a.get("heavy", int(a["tier"]) >= 1)
			var launch: String = a.get("launch", "")
			# 连段越长伤害越低（只数拳脚命中的下数）
			var dmg := _base() * float(a["dmg"]) * mul * Moves.dmg_scale(_string_n)
			var info := {"dmg": dmg, "dir": kd, "kb": float(a["kb"]) * _kbm(heavy or launch != ""), "stun": a["stun"], "launch": launch, "heavy": heavy,
					"contact": contact, "stop": a["stop"], "pst": dmg * 0.6, "step": step, "air": true, "swing": kd,
					"gd": a.get("gd", 1.0), "brk": a.get("brk", false), "pstun": a.get("pstun", 0.0), "freeze": a.get("freeze", 0.0)}
			var res := _hit_target(t, info)
			stat_hits.append([move_id, dmg, res])
			if stat_hits.size() > 96:
				stat_hits.pop_front()
			if res < 0 and _pvp(t) and bool(t.call("protected")):
				# 真人对打：对方在起身 / 受身 / 脱身后的保护里 —— 这一下白挥，收招更慢，还取消不了
				_whiff_pen = Moves.PVP_WHIFF_T
				pvp_stat["prot_whiffs"] = int(pvp_stat["prot_whiffs"]) + 1
			if res == 1:
				_fx_blocked(contact, dn)
				hit = true
			elif res >= 0:
				_string_n += 1
				_fx_hit(t, a, contact, kd, dmg, res == 2)
				hit = true
				if launch != "" and _is_launched(t):
					_on_launch(t, launch, contact, kd, float(a.get("stop", 0.1)))
				var n: int = a.get("swords", 0)
				if n > 0 and not _no_swords:
					_sword_follow(t, n)
	if bool(a.get("pass", false)) and _alive(t) and not _is_launched(t):
		_flash_step(PI)       # 一闪：判定之后整个人穿到对手身后（落点照样过 safe_spot）
	if not hit:
		# 打空。有目标却没打着（被瞬身闪开、对方无敌、够不着）的，这一招不能接下一段 —— 只能等收招，或用 护体 / 闪 取消；
		# 对着空气练招（没有目标）不受这个限制
		_whiff = true
		_whiff_lock = _alive(t)
		player.melee.combat_event.emit("air_whiff", {})
	_kit_fx("hit", {"hit": hit, "target": t if hit else null, "dir": kd, "pos": _last_contact if hit else player.center() + _fwd() * 1.6})


## 2026-11-25 这一招的画面交给技能脚本（英雄表里招式的 fx 标签）：phase = start 起手 / hit 判定那一刻（data.hit 打没打中、pos 接触点、dir 击退方向）
func _kit_fx(phase: String, data: Dictionary) -> void:
	if not _atk.has("fx"):
		return
	var k: Node = player.kit
	if k != null and is_instance_valid(k) and k.has_method("on_move_fx"):
		k.call("on_move_fx", str(_atk["fx"]), phase, move_id, data)


## 范围招朝哪打：锁着的目标（带俯仰），没有就朝人面对的方向
func aim_fwd() -> Vector3:
	if _alive(target):
		var d := Proj.aim_of(target) - (player.global_position + Vector3(0.0, BODY_Y, 0.0))
		if d.length_squared() > 0.01:
			return d.normalized()
	return _fwd()


## 2026-11-25 范围判定（英雄表招式的 aoe：圈；带 line 的是一条线，aoe 当粗细）。返回打没打到人（被护体挡下也算）
func _resolve_area(a: Dictionary, kd: Vector3, mul: float) -> bool:
	var from := player.global_position + Vector3(0.0, BODY_Y, 0.0)
	var line := float(a.get("line", 0.0))
	var fwd := aim_fwd() if line > 0.0 else _fwd()
	var c := from + fwd * float(a.get("aoe_fwd", 0.0))
	var rad := float(a["aoe"])
	var heavy: bool = a.get("heavy", int(a["tier"]) >= 1)
	var launch: String = a.get("launch", "")
	var dmg := _base() * float(a["dmg"]) * mul * Moves.dmg_scale(_string_n)
	var any := false
	var first := true
	_last_contact = c
	for e in Proj.targets(player.get_tree()):
		if not _alive(e):
			continue
		var ec := Proj.aim_of(e)
		var br := Proj.body_r(e)
		var dir := kd
		if line > 0.0:
			var along := (ec - from).dot(fwd)
			if along < -1.0 or along > line + br or ((ec - from) - fwd * along).length() > rad + br:
				continue
			dir = fwd
		else:
			var d := ec - c
			if d.length() > rad + br:
				continue
			if bool(a.get("radial", false)):
				dir = d.normalized() if d.length_squared() > 0.01 else Vector3.UP
				if launch == "up":
					dir = (dir * 0.5 + Vector3.UP).normalized()
		if not _seen(from, ec):
			continue
		var contact := ec - dir * minf(br, 0.8)
		var info := {"dmg": dmg, "dir": dir, "kb": float(a["kb"]) * _kbm(heavy or launch != ""), "stun": a["stun"], "launch": launch, "heavy": heavy,
				"contact": contact, "stop": a["stop"], "pst": dmg * 0.6, "step": step, "air": true, "swing": dir,
				"gd": a.get("gd", 1.0), "brk": a.get("brk", false), "pstun": a.get("pstun", 0.0), "freeze": a.get("freeze", 0.0)}
		var res := _hit_target(e, info)
		stat_hits.append([move_id, dmg, res])
		if stat_hits.size() > 96:
			stat_hits.pop_front()
		if res == 1:
			_fx_blocked(contact, dir)
			any = true
		elif res >= 0:
			any = true
			if first:
				first = false
				_last_contact = contact
				_string_n += 1
				_fx_hit(e, a, contact, dir, dmg, res == 2)       # 顿帧 / 镜头 / 连击数只算一次
				if launch != "" and _is_launched(e):
					_on_launch(e, launch, contact, dir, float(a.get("stop", 0.1)))
			else:
				Vfx.impact(contact, dir.cross(Vector3.UP), _col(), int(a["tier"]))
				if e.has_method("chip_colors") and not Vfx.lite:
					Vfx.debris(contact, dir + Vector3.UP * 0.2, e.chip_colors(), 6, 6.0, 1.0)
	return any


## 近身判定的视线（2026-11-24 复核 combat-3）：新图里隔着墙 / 楼板够得着也打不着（胸口一条线、再高 0.6 米一条线，有一条通就算看得见；
## 两头各留一点，贴墙站着、半个身子嵌在墙边的目标照样打得到）。不是新图恒为 true（老规矩不变）
func _seen(from: Vector3, tc: Vector3) -> bool:
	if player.ex_level() == null:
		return true
	var up := Vector3(0.0, 0.6, 0.0)
	return player.solid_hit(from, tc, 0.35, 0.3, 0.5) == Vector3.INF or player.solid_hit(from + up, tc + up, 0.35, 0.3, 0.5) == Vector3.INF


func _hit_target(t: Node3D, info: Dictionary) -> int:
	if t.has_method("air_hit"):
		var r: int = t.air_hit(player, info)
		return r
	var kd: Vector3 = info["dir"]
	return Proj.hurt(player, t, float(info["dmg"]), kd, _col(), bool(info["heavy"]))


## 命中反馈：顿帧 → 命中音 → 冲击特效 / 碎块 → 镜头 → 连击数 / 回灵力
func _fx_hit(t: Node3D, a: Dictionary, c: Vector3, kd: Vector3, dmg: float, broke: bool) -> void:
	var tier: int = a["tier"]
	var heavy: bool = a.get("heavy", false)
	var col := _col()
	# 同一招，境界越高打得越重：顿得更久、冲击圈更大、崩出来的碎块更多、镜头震得更狠（Realm.COMBAT，一档一档调的）
	var pf := _prof()
	var fxk: float = pf["fx"]
	var bk: float = pf["burst"]
	var shk: float = pf["shake"]
	Combat.hitstop(float(a["stop"]) * float(pf["stop"]), 0.0 if heavy else 0.03)
	if player.hero_id != "" and a["limb"] != "sw":
		# 2026-11-25 英雄档的拳脚：拳头砸在身上的闷响（老的命中声是刀刃切入的声音）
		Sfx.play("punch_heavy" if tier >= 1 else "punch", 0.0 if tier >= 1 else -1.0, 0.92 + 0.05 * float(step % 4))
	else:
		Sfx.play("hit_heavy" if tier >= 1 else "hit", 0.0 if tier >= 1 else -1.0, 0.9 + 0.05 * float(step % 5))
	var swing := kd.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	if a["limb"] == "sw":
		swing = Basis(Vector3.UP, face_yaw) * Vector3.RIGHT
	Vfx.impact(c, swing, col, 4 if heavy else tier, fxk)
	if t.has_method("chip_colors"):
		Vfx.debris(c, kd + Vector3.UP * 0.2, t.chip_colors(), int(round((16.0 if heavy else (10.0 if tier >= 1 else 6.0)) * bk)),
				(7.5 if heavy else 5.0) * lerpf(1.0, fxk, 0.5), (1.2 if heavy else 1.0) * lerpf(1.0, fxk, 0.5))
	if heavy or tier >= 1:
		Vfx.shockwave(c, kd, col, (1.5 if heavy else 0.8) * fxk)
	if heavy and flair() >= 1:
		# 元婴起：重手打实的地方荡开一圈空间波动（结丹没有），境界越高圈越大
		Vfx.space_ring(c, 1.3 + 0.45 * float(flair()), col, 0.4, 0.05 + 0.008 * float(flair()))
	if Realm.art(player.realm) == 3 and (heavy or tier >= 1):
		Vfx.fire_explode(c, kd, heavy)  # 化神·焚天：重手带火
	var fl := flair()
	if heavy or tier >= 1:
		_warp(c, 1.0 if heavy else 0.7)     # 重手：命中点的空间震一下
		if fl >= 2:
			# 化神起：重手带一道剑气弧光，命中点的空间碎一下
			Vfx.crescent(c, kd, col, 2.6 + 0.3 * float(fl))
			player.cam.impact(0.3 + 0.06 * float(fl))
		if fl >= 4:
			Vfx.rift(c, kd, col, 1.2, 0.3)   # 合体起：撕开一道空间裂隙
		if fl >= 3:
			_phantoms(t, fl - 2, dmg)        # 炼虚起：分身协击
	player.cam.add_trauma(float(a["trauma"]) * shk)
	player.cam.push_in(float(a["push"]) * shk)
	_add_combo(dmg)
	player.mp = minf(player.mp + HIT_MP * (2.0 if heavy else 1.0), player.mp_max())
	if broke:
		player.melee.combat_event.emit("air_break", {"pos": c})
	player.melee.combat_event.emit("air_hit", {"step": step, "heavy": heavy, "pos": c})


## 分身协击：n 道分身出现在对手四周，错开一点时间各补一击
func _phantoms(t: Node3D, n: int, dmg: float) -> void:
	var col := _col()
	var tc := Proj.aim_of(t)
	for i in n:
		var a := face_yaw + PI + TAU * (float(i) + 1.0) / float(n + 1) + randf_range(-0.25, 0.25)
		var dir := Vector3(-sin(a), randf_range(-0.2, 0.3), -cos(a)).normalized()   # 分身 → 对手
		var g := Vfx._ghost_node(player.visual, Color.WHITE.lerp(col, 0.45), 0.8, player.global_position)
		var pos := tc - dir * (_gap(t, tc - dir * 10.0) + 0.4) - Vector3(0.0, BODY_Y, 0.0)
		g.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z) - face_yaw), pos)
		Vfx.vanish(pos + Vector3.UP * BODY_Y, col)
		var tw := g.create_tween()
		tw.tween_interval(0.06 + 0.07 * float(i))
		tw.tween_callback(_phantom_hit.bind(t, dir, dmg * 0.25))
		tw.tween_property(g.get_meta("mat"), "albedo_color:a", 0.0, 0.28)
		tw.tween_callback(g.queue_free)


func _phantom_hit(t: Variant, dir: Vector3, dmg: float) -> void:
	if not _alive(t) or player.st != Player.St.AIR:
		return
	var c := Proj.aim_of(t)
	Vfx.crescent(c, dir, _col(), 2.2)
	Vfx.hit(c, dir, _col(), 0.9)
	var info := {"dmg": dmg, "dir": dir, "kb": 1.5, "stun": 0.3, "launch": "", "heavy": false,
			"contact": c, "stop": 0.0, "pst": dmg * 0.5, "step": step, "air": true, "swing": dir}
	# 对手已经被打飞：走飞剑那条受击（只扣血，不把击飞打断成硬直）
	var res: int = t.receive_hit(player, info) if _is_launched(t) and t.has_method("receive_hit") else _hit_target(t, info)
	if res >= 0:
		_add_combo(dmg)
	Sfx.play("hit", -6.0, 1.3)
	player.cam.add_trauma(0.08)


## 大乘：连段收尾把人打飞后，天上一圈金剑落下来追击
func _sword_rain(t: Node3D) -> void:
	var tc := Proj.aim_of(t)
	var cols := Realm.lines(player.realm)
	Vfx.sky_ring(tc + Vector3.UP * 9.0, _col(), 5.5, 0.9, 1.0)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var from := tc + Vector3(cos(a) * 5.5, 9.0 + randf_range(-0.6, 0.6), sin(a) * 5.5)
		Proj.launch(player, Proj.K.SWORD, from, t, tc, {"dmg": _base() * 0.18, "color": cols[i % cols.size()], "speed": 92.0,
				"hold": 0.12 + 0.03 * float(i), "turn": 14.0, "light": true, "lite": true, "scale": 2.3, "style": 4,
				"sfx": i % 4 == 0, "trauma": 0.012, "life": 1.6, "art": 6})


func _fx_blocked(c: Vector3, dn: Vector3) -> void:
	Vfx.blade_clash(c, -dn, 0.7)
	Combat.hitstop(0.05)
	Sfx.play("block", -3.0, 1.2)
	player.cam.add_trauma(0.12)
	player.melee.combat_event.emit("air_blocked", {"pos": c})


func _add_combo(dmg: float) -> void:
	combo += 1
	combo_dmg += dmg
	if awake_t <= 0.0:
		awaken = minf(awaken + 2.5, 100.0)
	_combo_t = COMBO_KEEP
	_engage = ENGAGE_KEEP


## 飞剑 / 法术命中（spell_projectile.gd 调）：计入连击
func on_spell_hit(dmg: float) -> void:
	if player.st == Player.St.AIR:
		_add_combo(dmg)


## 剑随拳走：n 柄飞剑从肩后亮出，紧跟着刺进同一个目标
func _sword_follow(t: Node3D, n: int) -> void:
	var fb := Basis(Vector3.UP, face_yaw)
	var art := Realm.art(player.realm)
	var cols := Realm.lines(player.realm)
	for k in n:
		var side := (-1.0 if (k + step) % 2 == 0 else 1.0) * (0.8 + 0.35 * float(k / 2))
		var from := player.global_position + fb * Vector3(side, 1.75 + 0.3 * float(k), 0.75)
		Proj.launch(player, Proj.K.SWORD, from, t, Proj.aim_of(t),
				{"dmg": _base() * _follow_k, "color": cols[k % cols.size()], "speed": 74.0, "hold": 0.04 + 0.05 * float(k),
				 "turn": 18.0, "art": art, "tw": 0.09, "lite": true, "sfx": k == 0, "trauma": 0.012, "life": 1.0})
		Vfx.glint(from, Color.WHITE.lerp(_col(), 0.4), 0.5)


## 把人打飞的那一下：冲击帧、破空环、镜头猛推再甩开
func _on_launch(t: Node3D, kind: String, c: Vector3, kd: Vector3, stop: float) -> void:
	_launched = t
	_launch_kind = kind
	var col := _col()
	var fxk: float = _prof()["fx"]
	Vfx.launch_ring(c, kd, col, 1.6 * fxk)
	Vfx.shockwave(c, kd, Color.WHITE.lerp(col, 0.4), 2.2 * fxk)
	Sfx.play("slam", -3.0, 1.25)
	var cam := player.cam
	cam.impact(1.0)
	cam.fov_punch(11.0)
	cam.kick_rush(1.0)
	_warp(c, 1.8)       # 把人打飞的那一下：空间碎裂的同时狠狠一扭
	Vfx.quake(c, 2.4 if player.hero_id != "" else 3.2)   # 贴着地面打飞的：劲力把脚下的地也掀掉一块（英雄档的新图里是真坑，收小一点：不然打几套地面全是坑）
	player.melee.combat_event.emit("air_launch", {"kind": kind, "pos": c, "chase": _chase})
	if flair() >= 5 and state == A.ATTACK:
		_sword_rain(t)
	if kind == "down" and c.y > 7.0:
		# 陨落：不再切到落点旁的固定机位（那样主角不在画面里，接着打别的也看不见），只放慢一拍，镜头照常跟着主角看他砸下去
		Combat.slowmo(0.3, 0.07, 0.25)
	elif not _chase and _smash_k >= 0.95 and state == A.SMASH:
		Combat.slowmo(0.25, 0.05, 0.3)


## 对手撞上场景（air_foe.gd / enemy_dummy.gd 调）
func on_crash(_who: Node3D, pos: Vector3, spd: float, ground: bool) -> void:
	var near := clampf(1.0 - pos.distance_to(player.center()) / 70.0, 0.25, 1.0)
	var cam := player.cam
	_warp(pos, 1.4 * near)   # 对手砸进场景：落点一圈波动
	cam.add_trauma(0.55 * near)
	cam.impact(0.7)
	_add_combo(0.0)
	if ground and is_instance_valid(_who) and _who.has_method("is_downed"):
		# 砸进地里了：趴着的这一秒可以补一发（坠地追击）
		_downed = _who
		_otg_done = false
	player.melee.combat_event.emit("air_crash", {"pos": pos, "ground": ground, "spd": spd})
	if _cine_wait_crash:
		_cine_wait_crash = false
		_cine_dur = _cine_t + 0.55


# ---------- 受到攻击（对手在判定时刻调用） ----------

## 返回 2 瞬身闪开 / 1 护体挡下 / 0 受击 / -1 无效（不在空战、闪现无敌中）
func receive_attack(src: Node3D, info: Dictionary) -> int:
	if player.st != Player.St.AIR or player.is_dashing() or _iframe > 0.0 or player.ult.active or player.dun_active:
		return -1
	if state == A.DEAD or player.dead:
		return -1   # 已经陨落：不再受击
	if state == A.CLASH:
		return -1   # 飞剑对波相持中：谁也打不进来（只有对波的结果能伤到自己）
	if state == A.BRAWL or state == A.GRABBED or (state == A.THROW and _throw_ph == 1):
		return -1   # 对拼 / 被擒 / 正抡着人：别的攻击打不进来
	if _prot > 0.0:
		return -1   # 真人对打：起身 / 受身 / 脱身后的保护
	if state == A.DOWN and _pvp(src):
		return -1   # 真人对打：砸进地里趴着的这一会儿打不到（起身后还有一段保护）
	if player.is_invuln():
		return -1   # 2026-11-24 出生无敌等（player.set_invuln）
	if not Combat.net_ext.is_empty():
		# 2026-11-25 真人打过来的这一下附带的东西（破防 / 硬直 / 冻结，net.gd 的 _hit 写的）并进来
		info = info.duplicate()
		info.merge(Combat.net_ext, true)
	player.note_attacker(src)
	if parry_t > 0.0 and (state == A.GUARD or (_parry_dom and state == A.ATTACK and move_id == _parry_pid() and not bool(info.get("ranged", false)))):
		# 2026-11-24 苍鸿「回风」/ 觉醒「剑域」：架势中被近身打中 → 闪到对方身后反斩（飞来的剑气在剑域里拨开）。
		# 剑域里正反斩着别人的这一下又有人近身来犯：照样接（复核 combat-7）
		var pr := _try_parry(src, info)
		if pr >= 0:
			return pr
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	var ranged: bool = info.get("ranged", false)
	_engage = ENGAGE_KEEP
	# 拳劲对拼：自己这一拳也正打向它、还没打出去 —— 两边的拳头撞在一起，进入高速互殴
	if state == A.ATTACK and not _hit_done and target == src and not ranged and not heavy and int(_atk["tier"]) == 0 \
			and _brawl_cd <= 0.0 and src.has_method("brawl_begin") and not bool(_atk.get("armor", false)) and not bool(_atk.get("auto", false)):
		_start_brawl(src)
		return -1
	var front := _fwd().dot(_flat(dir).normalized()) < 0.3
	# 瞬身（兜底）：刚按下护体的一瞬间被打中。空战对手的拳脚在按键那一刻就判了（try_vanish_press），
	# 这里接的是剑气、怪、别的玩家这些没法预判出手时刻的
	if state == A.GUARD and _clock - _guard_at <= Moves.vanish_window(_vanish_count()) and player.mp >= Moves.VANISH_MP:
		_vanish_counter(src, ranged)
		return 2
	if state == A.GUARD and front and ranged and not heavy and not bool(info.get("brk", false)) and player.mp >= Moves.SWAT_MP:
		_swat(info, dir)            # 气弹 / 飞剑：单手一拨就崩飞了，不掉血
		return 1
	if state == A.GUARD and front:
		var cost := GUARD_MP * (2.0 if heavy else 1.0)
		if bool(info.get("brk", false)) or player.mp < cost:
			_crush(src, info, dir)      # 蓄力重击（红光）护体挡不住；灵力见底也撑不住
			return 0
		player.mp = maxf(player.mp - cost, 0.0)
		player.caster.hold_regen()
		player.melee.hp = maxf(player.melee.hp - float(info.get("dmg", 8.0)) * 0.15, 1.0)
		var c: Vector3 = info.get("contact", player.center())
		if legacy_guard:
			Vfx.blade_clash(c, -dir, 1.0 if heavy else 0.65)
			Vfx.shockwave(c, -dir, _col(), 0.7)
			Combat.hitstop(0.07 if heavy else 0.04)
			Sfx.play("block", -1.0, 0.9 if heavy else 1.1)
			player.cam.add_trauma(0.25 if heavy else 0.12)
			_push = dir * (9.0 if heavy else 3.0)
			player.velocity += _push
		else:
			_guard_hit(src, c, dir, heavy)
		player.melee.combat_event.emit("air_guard", {"heavy": heavy, "contact": c})
		return 1
	if state == A.ATTACK and bool(_atk.get("armor", false)) and (not _hit_done or bool(_atk.get("auto", false))) \
			and player.melee.hp > float(info.get("dmg", 8.0)) * 0.5 + 0.5:
		# 2026-11-25 霸体（崩山 / 震岳的蓄势、觉醒的几招）：照样掉血（减半），但不硬直、不被打飞；这一下要是能打死就不扛了
		_armor_hit(info, dir, heavy)
		return 0
	_hurt(src, info, dir, heavy)
	return 0


func _armor_hit(info: Dictionary, dir: Vector3, heavy: bool) -> void:
	var m := player.melee
	m.hp = maxf(m.hp - float(info.get("dmg", 8.0)) * 0.5, 1.0)
	_since_hurt = 0.0
	stat_armor += 1
	if awake_t <= 0.0:
		awaken = minf(awaken + 5.0, 100.0)
	var c: Vector3 = info.get("contact", player.center())
	Vfx.blade_clash(c, -dir, 0.8 if heavy else 0.55)
	Vfx.shockwave(c, -dir, Color.WHITE.lerp(_col(), 0.5), 0.6)
	Sfx.play("block", -3.0, 0.75)
	Combat.hitstop(0.05 if heavy else 0.03)
	_flash = 0.6
	_flash_on = true
	player.cam.add_trauma(0.2 if heavy else 0.1)
	player.melee.combat_event.emit("air_armor", {"pos": c})


## 护体挡下一击的反馈（见 GSLIDE_LIGHT 那段说明）：顿一下 → 被推着往后滑、上身后仰、护体架势被打得一荡 →
## 接触点一圈空气波动（重手两圈）+ 屏幕那一点扭一下 → 滑退途中身后一串小波纹（_tick_gslide）。
## 力道看出手那一方的境界档位（Realm.COMBAT 的 kb / fx / stop / shake），连着挡下的一下比一下推得狠
func _guard_hit(src: Node3D, c: Vector3, dir: Vector3, heavy: bool) -> void:
	var tk: Dictionary = Realm.combat(int(src.call("tier_realm"))) if is_instance_valid(src) and src.has_method("tier_realm") else _prof()
	var col := _col()
	var kb := lerpf(1.0, float(tk["kb"]), 0.6 if heavy else 0.34)
	var fx := lerpf(1.0, minf(float(tk["fx"]), 1.6), 0.5)     # 波动圈只随境界放大一半：大了会把两个人整个糊住
	_g_hits = _g_hits + 1 if _clock - _g_last <= GSLIDE_STACK else 1
	_g_last = _clock
	var stack := 1.0 + 0.1 * float(mini(_g_hits - 1, 3))
	var pd := dir
	pd.y *= 0.35        # 挡下的力道主要是水平往后推，上下只带一点
	pd = pd.normalized() if pd.length_squared() > 1e-4 else -_fwd()
	_gslide = (_gslide * 0.4 + pd * (GSLIDE_HEAVY if heavy else GSLIDE_LIGHT) * kb * stack).limit_length(30.0)
	_gs_rate = 6.5 if heavy else 9.0
	_gs_wake = 0.0
	_gs_rings = 0
	guard_slid = 0.0
	_push = Vector3.ZERO
	_g_lean = clampf(_g_lean + (0.42 if heavy else 0.22) * minf(stack, 1.3), 0.0, 0.6)
	var gp := Poses.get_pose(_pose("f_guard"))
	rig.snap(Poses.lerp_pose(gp, Poses.get_pose("f_hurt"), 0.3 if heavy else 0.17), [[0.2 if heavy else 0.13, gp, 2]])
	Vfx.blade_clash(c, -dir, 1.0 if heavy else 0.65)
	Vfx.shockwave(c, -dir, col, (1.0 if heavy else 0.7) * fx)
	# 空气波动：桌面档真的把那一小块画面折一下，手机档不读屏幕、画一圈明暗波纹（aura_warp.gdshader）。
	# 圈要小、扭得要轻：2026-11-20 第一版半径四米多、幅度 0.08，重手那一下把两个人整个糊成一团色散，反而看不清
	Vfx.space_ring(c, (1.5 if heavy else 1.0) * fx, col, 0.36 if heavy else 0.3, 0.035 if heavy else 0.025)
	if heavy and not Vfx.lite:
		Vfx.space_ring(c - dir * 0.3, 2.6 * fx, Color.WHITE.lerp(col, 0.5), 0.5, 0.015)    # 重手：外面再荡开一圈很淡的压力波
	_warp(c, 0.6 if heavy else 0.3)
	Combat.hitstop((0.07 if heavy else 0.045) * float(tk["stop"]))
	Sfx.play("block", -1.0, 0.9 if heavy else 1.1)
	player.cam.add_trauma((0.25 if heavy else 0.13) * float(tk["shake"]))
	if heavy:
		player.cam.fov_punch(-3.0)


## 护体滑退：由招式给速度（顿帧时 Player 自己定住），衰减到很慢时把剩下的速度交还给平时的护体慢移。
## 衰减用的是和位移同一个 dt（Player 按这一帧的 dt 走 drive_vel）：用战斗时钟的话它单帧封顶 1/30 秒，帧率低时会滑得更远
func _tick_gslide(cdt: float) -> void:
	var sp := _gslide.length()
	if sp < 1.0:
		player.velocity = _gslide
		_gslide = Vector3.ZERO
		return
	_drives = true
	drive_vel = _gslide
	if Combat.frozen():
		return
	guard_slid += sp * cdt
	_gslide *= exp(-_gs_rate * cdt)
	# 尾迹：滑得快的时候，身后被挤开的空气一圈圈荡开（手机档稀一点、少一层火星）
	_gs_wake -= cdt
	if _gs_wake <= 0.0 and sp > 5.0 and _gs_rings < (2 if Vfx.lite else 3):
		_gs_wake = 0.12 if Vfx.lite else 0.08
		_gs_rings += 1
		var back := _gslide.normalized()
		# 身后（滑过去的那一边）被挤开的空气：放在身体外面一点，别罩在人身上
		Vfx.space_ring(player.center() + back * 1.2, 0.55 + sp * 0.02, _col(), 0.26, 0.018)
		if not Vfx.lite:
			Vfx.line_sparks(player.center() - back * 0.3, -back, Color.WHITE.lerp(_col(), 0.5), 3, sp * 0.6, 25.0, 0.22)


## 瞬身：闪到对手背后，画面骤慢，对手这一下打空
## 耗灵力；VANISH_KEEP 秒内连着瞬身，下一次的窗口更窄。落点过 safe_spot：背后不行就换到侧面 / 上方，都不行就原地闪过这一下。
## 之后 COUNTER_T 秒内点攻击 = 瞬身反击
func _vanish_counter(src: Node3D, ranged: bool) -> void:
	_vanish_n = _vanish_count() + 1
	_vanish_last = _clock
	player.mp = maxf(player.mp - Moves.VANISH_MP, 0.0)
	player.caster.hold_regen()
	if player.is_dashing():
		player.stop_dash()
	if state == A.CHARGE:
		player.hero.set_glow(0.0, _col())
	_end_blade()
	var sc := Proj.aim_of(src)
	var from_c := player.center()
	var away := _flat(sc - from_c)
	away = away.normalized() if away.length_squared() > 1e-4 else _fwd()
	var spot := Vector3.INF
	if ranged:
		# 远程剑气：就地侧闪一步
		spot = safe_spot(from_c, player.global_position + away.cross(Vector3.UP) * 3.0)
	else:
		spot = safe_spot(sc, sc + away * (_gap(src, sc + away * 10.0) + 0.3) - Vector3(0.0, BODY_Y, 0.0))
	Vfx.vanish(from_c, _col())
	Vfx.perfect_dodge(from_c, sc, _col())
	if spot != Vector3.INF:
		var look := _flat(sc - spot)
		var yaw := atan2(-look.x, -look.z) if look.length_squared() > 0.01 else face_yaw
		player.warp_to(spot, yaw)
		_note_swap()
		face_yaw = yaw
		has_face = true
		_warp(spot + Vector3(0.0, BODY_Y, 0.0), 0.9)
	target = src
	_gslide = Vector3.ZERO
	_iframe = 0.5
	if _pvp(src):
		player.melee.combat_event.emit("air_protect", {"t": 0.5})      # 真人对打：告诉对面这半秒打不到（他那边算打空）
	Combat.clear_hitstop()
	Combat.slowmo(0.14, 0.3, 0.4)
	Sfx.play("perfect", -2.0)
	player.cam.fov_punch(-7.0)
	if not ranged:
		_counter_until = _clock + Moves.COUNTER_T
		if src.has_method("on_vanished"):
			src.on_vanished()
	state = A.IDLE
	_t = 0.0
	_tumble = 0.0
	_push = Vector3.ZERO
	_queued = false
	rig.play("f_idle")
	player.melee.combat_event.emit("air_vanish", {"n": _vanish_n})


func _hurt(_src: Node3D, info: Dictionary, dir: Vector3, heavy: bool) -> void:
	_throw_abort()
	_parry_dom = false      # 剑域里被打中了（圈外来的 / 接满了）：这一架到此为止，挨完打不再回架势
	var m := player.melee
	m.hp = maxf(m.hp - float(info.get("dmg", 8.0)), 0.0)
	_since_hurt = 0.0
	if awake_t <= 0.0:
		awaken = minf(awaken + 8.0, 100.0)
	if state == A.CHARGE:
		player.hero.set_glow(0.0, _col())
	_end_blade()
	var c: Vector3 = info.get("contact", player.center())
	var swing := dir.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	Combat.hitstop(0.1 if heavy else 0.06)
	Sfx.play("hit_heavy" if heavy else "hit", 0.0, 0.85)
	_flash = 1.0
	_flash_on = true
	player.hit_shake(0.1)
	Vfx.impact(c, swing, Color(0.95, 0.25, 0.2), 1 if heavy else 0)
	Vfx.debris(c, dir + Vector3.UP * 0.2, player.hero.chip_colors(), 12 if heavy else 7, 5.0)
	player.cam.add_trauma(0.4 if heavy else 0.22)
	combo = 0
	combo_dmg = 0.0
	_string_n = 0
	_queued = false
	_buf_at = -10.0
	_counter_until = -10.0
	_opener = false
	_open_hold = 0.0
	_whiff_pen = 0.0
	burst = minf(burst + 0.08, Moves.BURST_MAX)    # 挨打也攒一点罡气
	if m.hp <= 0.0:
		_die(c, dir)       # 气血归零：这一下就陨落，后面的追击打不到了
		return
	var dead := false
	var sk := _pvp_took(_src, ["fwd", "up", "down"].has(str(info.get("launch", ""))))     # 真人对打：这一套里挨得越多硬直越短
	if heavy:
		state = A.BLOWN
		_wall_n = 0
		_dur = 0.75 * sk
		_push = dir * float(info.get("kb", 22.0))
		rig.play("f_blown")
		Vfx.shockwave(c, dir, Color(1.0, 0.5, 0.4), 1.2)
		player.cam.impact(0.6)
	else:
		state = A.HURT
		_dur = 0.34 * sk
		_push = dir * float(info.get("kb", 6.0))
		rig.play("f_hurt2" if randf() < 0.5 else "f_hurt")
		# 2026-11-25 英雄技能：这一下指定了真人的硬直（靠山撞开的踉跄）/ 冻结（定在原地，不被推走）
		var ps := float(info.get("pstun", 0.0))
		if ps > 0.0:
			_dur = maxf(_dur, clampf(ps, 0.2, 1.4) * sk)
		var fz := float(info.get("freeze", 0.0))
		if fz > 0.0:
			_dur = maxf(_dur, clampf(fz, 0.2, 2.5) * sk)
			_push = Vector3.ZERO
			player.melee.combat_event.emit("air_frozen", {"t": _dur})
			var hf: GDScript = load("res://scripts/hero_fx.gd")
			if hf != null and hf.has_method("frozen_self"):
				hf.call("frozen_self", player, _dur)
	_t = 0.0
	player.melee.combat_event.emit("air_hurt", {"heavy": heavy, "dead": dead})


## 陨落：气血归零的那一下立刻判死 —— 身形当场溃散，此后不再受击、不能操作，定在原地等复活
## （大厅里 main.gd 把人送回出生点；搜打撤走它自己的结算，结算完回大厅）。c 命中点，dir 这一击的方向
func _die(c: Vector3, dir: Vector3) -> void:
	if not _die_forced and player.absorb_lethal({"pos": c, "air": true}):
		# 2026-11-24 关卡接住了这一下（重伤倒地，player.set_downed）：不陨落，人掉回地面趴着
		_throw_abort()
		_brawl_abort()
		_grab_by = null
		_end_blade()
		_end_cine()
		state = A.IDLE
		_push = Vector3.ZERO
		_tumble = 0.0
		_queued = false
		_buf_at = -10.0
		_launched = null
		combo = 0
		player.melee.combat_event.emit("air_hurt", {"heavy": true, "dead": false, "downed": true})
		return
	_die_forced = false
	_throw_abort()
	_brawl_abort()
	_grab_by = null
	_end_blade()
	_end_cine()
	player.caster.cancel()
	if player.caster.clash_mode:
		player.caster.end_clash()
	player.hero.set_glow(0.0, _col())
	player.dead = true
	state = A.DEAD
	_t = 0.0
	_push = Vector3.ZERO
	_tumble = 0.0
	_lie = 0.0
	_queued = false
	_buf_at = -10.0
	_counter_until = -10.0
	_launched = null
	target = null
	_engage = 0.0
	combo = 0
	combo_dmg = 0.0
	player.velocity = Vector3.ZERO
	Combat.clear_hitstop()
	Combat.slowmo(0.2, 0.3, 0.5)
	var col := Color(1.0, 0.5, 0.4)
	Vfx.shatter(player.visual, c, dir, Color.WHITE.lerp(col, 0.5), 1.2)
	Vfx.shockwave(c, dir, col, 1.6)
	Sfx.play("execute", -4.0, 0.9)
	player.visual.visible = false
	var cam := player.cam
	cam.impact(0.7)
	cam.add_trauma(0.5)
	player.melee.combat_event.emit("air_hurt", {"heavy": true, "dead": true})
	player.melee.combat_event.emit("player_dead", {"pos": c, "air": true})


## 复活后空战这边复位（Player.revive 调；被送回地面时也会走到这里）
func revive() -> void:
	if state != A.DEAD:
		return
	state = A.IDLE
	_t = 0.0
	_iframe = 1.0
	_pc_live = false
	_pc_escape = -1.0
	_since_hurt = 99.0
	burst = maxf(burst, 1.0)
	rig.play("f_idle")


# ---------- 演出镜头 ----------

func _tick_cine(dt: float) -> void:
	if _cine_t < 0.0:
		return
	_cine_t += dt
	var cam := player.cam
	var look := player.center()
	if _cine_use_look:
		look = _cine_look
	elif is_instance_valid(_cine_follow):
		look = Proj.aim_of(_cine_follow) if _alive(_cine_follow) else _cine_follow.global_position
	var f := look - _cine_eye
	if f.length_squared() > 0.01:
		var up := Vector3.UP if absf(f.normalized().dot(Vector3.UP)) < 0.97 else Vector3.BACK
		cam.cine_xf = Transform3D(Basis.looking_at(f, up), _cine_eye)
	var left := _cine_dur - _cine_t
	if left <= _cine_out and not _cine_handed:
		_hand_cam()
	var kin := clampf(_cine_t / _cine_in, 0.0, 1.0) if _cine_in > 0.0 else 1.0
	cam.cine_k = clampf(minf(left / _cine_out, kin), 0.0, 1.0)
	if left <= 0.0 or player.st != Player.St.AIR:
		_end_cine()


## 演出镜头交还之前：先把跟随机位转到演出镜头的朝向上（俯仰收一点），混回去的那零点几秒就不会整个甩半圈；
## 随后近身斗法的镜头按住一会儿，再平稳绕回主角身后（camera_rig.gd 的 DUEL_HOLD 那段）
func _hand_cam() -> void:
	_cine_handed = true
	var cam := player.cam
	var f := -cam.cine_xf.basis.z
	var fh := Vector2(f.x, f.z).length()
	if fh < 0.05 or player.st != Player.St.AIR:
		return
	cam.yaw = atan2(-f.x, -f.z)
	cam.pitch = clampf(atan2(f.y, fh), -0.7, 0.35)
	cam.duel_hold(0.8)


func _end_cine() -> void:
	if _cine_t < 0.0:
		return
	if not _cine_handed and player.cam.cine_k > 0.5:
		_hand_cam()       # 被打断（对拼被别的事打断等）：至少交还到同一个朝向上
	_cine_t = -1.0
	_cine_wait_crash = false
	_cine_follow = null
	player.cam.cine_k = 0.0


func _start_cine(eye: Vector3, follow: Node3D, dur: float, fov: float, out := 0.25, fade_in := 0.0) -> void:
	if player.ult.active:
		return
	_cine_eye = eye
	_cine_use_look = false
	_cine_follow = follow
	_cine_t = 0.0
	_cine_dur = dur
	_cine_out = out
	_cine_in = fade_in
	_cine_handed = false
	player.cam.cine_fov = fov
	player.cam.cine_k = 0.0 if fade_in > 0.0 else 1.0
	_tick_cine(0.0)


## 第三式剑诀：出手前侧前方低机位特写，随后放回跟随机位看剑飞出去。
## 【不再使用】2026-11-20 用户反馈「放技能时播一个镜头，效果不好」，press_skill 里已经不调它了；留着是因为函数本身没问题、别处想用还能用。
func _cine_skill() -> void:
	var fb := Basis(Vector3.UP, player.cam.yaw)
	var eye := player.center() + fb * Vector3(1.9, -0.35, -2.6)
	_start_cine(eye, null, 0.5, 50.0, 0.22)
	Combat.slowmo(0.35, 0.12, 0.25)


# ---------- 飞剑对波 ----------
## 两个人同时朝对方连发飞剑（E 长按）时，两股剑流在中间迎头对撞、相持：
##   · 进入：自己在连发、对手也在连发（air_caster.gd 发现后调 start_clash），或对手的飞剑出手时自己正在连发（foe_volley_started）
##   · 相持：双方定在原地，各出一束能量（放大的飞剑在光束里一柄柄往前送）在半空迎头撞上，撞出一个能量交汇点。
##     交汇点往输出弱的那边移：输出 = 底劲 × 技能强度（境界 / 觉醒；对手看水平）× 灵力余量 × (1 + 连点「攻击」攒的发力)，
##     双方相持中都在持续掉灵力，见底的一方输出只剩四分之一（_clash_power；数值在 air_moves.gd「飞剑对波」）
##   · 表现（clash_fx.gd）：两束能量 + 交汇光核 + 碰撞盘，压制方的光束粗壮明亮、被压的发虚；火星、冲击环、电弧、空间扭曲；
##     镜头随局势切机位（_clash_cam）：起手近景 → 侧面全景 ⇄ 交汇点特写 → 压制 / 被压制时切到压制方侧后
##   · 分胜负：交汇点顶到对手身上 → 光束贯穿过去、在他身上炸开，把他轰飞；被顶到自己身上 → 自己被轰飞；
##     最久 CLASH_MAX 秒，到点看谁占优

##   · 预警：对手朝自己起手飞剑的一瞬间，画面一顿（短暂时停）、屏幕中间亮出「飞剑来袭」的提示和倒计时条，
##     这段时间里点「剑」或「攻击」就接下这一波、正式进入对波；没点到，剑流照常打过来。
##     对手已经在连发、自己正被打得僵直时点「剑」也能接（不用先摆脱僵直）。

## 对手朝自己起手飞剑（air_foe.gd 调）：时停一下、开预警窗口
func clash_warn(foe: Node3D) -> void:
	if player.st != Player.St.AIR or state == A.CLASH or state == A.BLOWN or state == A.DOWN or state == A.DEAD or player.ult.active:
		return
	if not has_volley():
		return      # 2026-11-24 苍鸿没有连发、接不了对波：不给预警（也就没有预警里飞剑不算伤害的那一下），靠护体拨 / 闪开
	_warn_foe = foe
	_warn_until = float(Time.get_ticks_msec()) + WARN_MS
	Combat.slowmo(0.05, WARN_MS * 0.00065, 0.2)
	player.cam.impact(0.35)
	Sfx.play("perfect", -4.0, 0.7)
	_engage = ENGAGE_KEEP
	player.melee.combat_event.emit("air_clash_warn", {"pos": Proj.aim_of(foe)})


## 对手的剑出手了：预警窗口关上（之后只要他还在连发，点「剑」仍然能接）
func clash_warn_fired(_foe: Node3D) -> void:
	_warn_until = 0.0


## 预警窗口里，n 正是那个朝自己起手的对手（联机：这段时间他的飞剑先不算伤害，给接波留出时间）
func warned_by(n: Variant) -> bool:
	return warn_k() > 0.0 and _warn_foe == n


## 预警窗口还剩多少（0~1，0 = 没在预警），HUD / 触屏按钮用
func warn_k() -> float:
	if _warn_until <= 0.0 or not _alive(_warn_foe):
		return 0.0
	return clampf((_warn_until - float(Time.get_ticks_msec())) / WARN_MS, 0.0, 1.0)


## 有没有对手正朝自己起手 / 连发飞剑、可以接下来对波
func can_accept_clash() -> bool:
	# 预警窗口里一定能接（联机时对方「正在连发」的状态会晚一两帧才同步到）；窗口过了就看他是不是还在连发
	if not has_volley():
		return false      # 2026-11-24 苍鸿：没有飞剑对波
	return state != A.CLASH and _alive(_warn_foe) and _warn_foe.has_method("volley_active") 			and (warn_k() > 0.0 or bool(_warn_foe.call("volley_active")))


## 接波：预警窗口里、或对手还在连发时点了「剑」。挨打僵直中也能接。进入了返回 true
func _accept_clash() -> bool:
	if not can_accept_clash() or player.st != Player.St.AIR or state == A.BLOWN or state == A.DOWN or state == A.DEAD or player.ult.active:
		return false
	var foe := _warn_foe
	if player.center().distance_to(foe.call("center")) < CLASH_MIN_DIST:
		return false
	_warn_until = 0.0
	Combat.slowmo_release(0.1)
	player.caster.cancel()
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe)
	return true


## 能不能进入对波（距离够、自己没在挨打 / 倒地）。进入了返回 true
func start_clash(foe: Node3D) -> bool:
	if not has_volley():
		return false      # 2026-11-24 修（复核 combat-1）：苍鸿没有飞剑对波
	if state == A.CLASH or state == A.HURT or state == A.BLOWN or state == A.DOWN or state == A.RUSH or state == A.SMASH or state == A.DASH or state == A.CRUSH or state == A.DEAD:
		return false
	if not _alive(foe) or not foe.has_method("clash_origin") or player.ult.active:
		return false
	if player.center().distance_to(foe.call("center")) < CLASH_MIN_DIST:
		return false
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe)
	return true


## 对手的飞剑出手了（air_foe.gd 调）。自己正在连发 → 进入对波，返回 true
func foe_volley_started(foe: Node3D) -> bool:
	if not has_volley() or not player.caster.channeling or player.caster.clash_mode:
		return false
	return start_clash(foe)


## 联机：对方那边进了对波，叫我也进（net.gd 调）。i_auth = 两边同时发起时由谁做主（编号小的）
func net_clash_begin(foe: Node3D, i_auth: bool) -> void:
	if state == A.CLASH:
		if _clash_foe == foe:
			_clash_auth = i_auth     # 两边同时发起：按编号定一个做主的
		return
	if player.st != Player.St.AIR or state == A.BLOWN or state == A.DOWN or state == A.DEAD or player.ult.active:
		foe.call("net_clash_end", false)   # 我这边进不了（没在空战 / 正被打飞）：算我输，对方直接收招
		return
	_warn_until = 0.0
	Combat.slowmo_release(0.1)
	player.caster.cancel()
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe, false)
	_clash_auth = false


## 联机：做主的那边判了胜负
func net_clash_result(won: bool) -> void:
	if state == A.CLASH:
		_clash_forced = 1 if won else -1


func _start_clash(foe: Node3D, notify := true) -> void:
	state = A.CLASH
	_clash_live = true
	_pend_far = false
	_clash_my = 0.0
	_clash_auth = true
	_clash_forced = 0
	if foe.get("clash_their") != null:
		foe.set("clash_their", 0.0)
	_t = 0.0
	_clash_foe = foe
	_clash_u = 0.5
	_clash_t = 0.0
	_clash_fx = 0.0
	_clash_blast = 0.4
	_clash_arc = 0.0
	_clash_ring = 0.0
	_clash_surge = 0.6          # 起手自带一口劲
	_clash_adv = 0.0
	_clash_press = 0
	_clash_shot = -1
	_clash_shot_t = 0.0
	_mash_acc = 0.0
	_engage = ENGAGE_KEEP
	target = foe
	player.caster.clash_mode = true
	if notify:
		foe.clash_begin()
	rig.play("f_point")
	_clash_place(foe)
	var a := player.center()
	var b: Vector3 = foe.clash_origin()
	_beam_dir = (b - a).normalized()
	var mid := a.lerp(b, 0.5)
	var side := _beam_dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	if side.dot(player.cam.global_position - mid) < 0.0:
		side = -side
	_clash_side = side
	# 画面：两束能量 + 交汇光核（clash_fx.gd）
	_drop_cfx()
	_cfx = ClashFx.new()
	_cfx.col_a = _col()
	if foe.get("qi") != null:
		_cfx.col_b = foe.get("qi") as Color
	# 交汇点多大看两边的境界档位（各占一半）：两个大乘对轰的光核是两个结丹的近两倍
	var foe_core: float = float(Realm.combat(int(foe.call("tier_realm")))["clash_core"]) if foe.has_method("tier_realm") else float(_prof()["clash_core"])
	_cfx.size_k = (float(_prof()["clash_core"]) + foe_core) * 0.5
	Vfx.root.add_child(_cfx)
	# 镜头：先给主角出手的近景，之后随局势切机位（_clash_cam）
	_start_cine(a, null, CLASH_MAX + 3.0, 56.0, 0.3)
	_cine_use_look = true
	_clash_cam(_hand_point(), b, mid)
	_tick_cine(0.0)       # 机位这一帧就摆到位（不等下一帧，免得闪一下上一次演出的机位）
	Combat.slowmo(0.3, 0.12, 0.3)
	player.cam.impact(0.8)
	Sfx.play("clash", 0.0, 0.7)
	player.melee.combat_event.emit("air_clash", {"pos": mid})


## 对波开场的站位：两个人离得太近（不到 CLASH_SAFE）就沿连线各自退开，贴着地的抬到离地 CLASH_ALT 以上，
## 用 CLASH_SETUP 秒滑过去再开始相持 —— 不然贴身触发时剑流、光核全穿在两个人身上，贴地时扎进地里。
## 落点过 safe_spot（不进地形、不穿墙、不出界）。对手是别的玩家的木偶时挪不动它，自己退满全程（他那边同样会退）。
func _clash_place(foe: Node3D) -> void:
	_clash_to = Vector3.INF
	_clash_setup = 0.0
	var pp := player.global_position
	var pc := player.center()
	var fc: Vector3 = foe.call("center") if foe.has_method("center") else Proj.aim_of(foe)
	var flat := _flat(fc - pc)
	var dir := flat.normalized() if flat.length() > 0.3 else _fwd()
	var can_move := foe.has_method("clash_place")
	var lack := maxf(CLASH_SAFE - pc.distance_to(fc), 0.0)
	var back := lack * (0.5 if can_move else 1.0)
	var mid := pc.lerp(fc, 0.5)
	var want := pp - dir * back
	want.y = maxf(pp.y, _floor_at(want) + CLASH_ALT)
	var moved := false
	if back > 0.2 or want.y > pp.y + 0.2:
		var spot := safe_spot(Vector3(mid.x, maxf(mid.y, want.y + BODY_Y), mid.z), want)
		if spot != Vector3.INF:
			_clash_to = spot
			moved = true
	if can_move:
		var fp := foe.global_position + dir * (lack - back)
		fp.y = maxf(fp.y, _floor_at(fp) + CLASH_ALT)
		if fp.distance_to(foe.global_position) > 0.2:
			var fs := safe_spot(Vector3(mid.x, maxf(mid.y, fp.y + BODY_Y), mid.z), fp)
			if fs != Vector3.INF:
				foe.call("clash_place", fs, CLASH_SETUP)
				moved = true
	if moved:
		_clash_setup = CLASH_SETUP
		# 一圈气浪把两个人震开
		Vfx.shockwave(mid, Vector3.UP, Color.WHITE.lerp(_col(), 0.4), 2.2)
		Vfx.shockwave(mid, dir, _col(), 1.6)
		Vfx.body_ghost(player.visual, Color.WHITE.lerp(_col(), 0.6), 0.5, 0.3)
		Sfx.play("dodge", -6.0, 0.8)


func _drop_cfx() -> void:
	if is_instance_valid(_cfx):
		_cfx.abort()
	_cfx = null


## 连点「攻击」：发力 +CLASH_TAP（很快衰减，所以要一直点），一道亮带顺着自己的光束推向交汇点
func _clash_tap() -> void:
	_clash_surge = minf(_clash_surge + Moves.CLASH_TAP, Moves.CLASH_SURGE_MAX)
	player.cam.add_trauma(0.05)
	if is_instance_valid(_cfx):
		_cfx.tap()
	Vfx.ribbon_burst(_hand_point(), _beam_dir, _col(), 3, 14.0, 25.0, 0.25, Vector3.ZERO)


## 对波的输出（每秒把交汇点往对面顶多少，全程为 1）= 底劲 × 技能强度（境界、觉醒）× 灵力余量 × (1 + 连点攒的发力)。
## 规则和数值见 air_moves.gd「飞剑对波」，对手那边是 air_foe.gd 的 clash_output
func _clash_power() -> float:
	var tech := (1.0 + 0.06 * float(flair())) * (1.3 if awake_t > 0.0 else 1.0)
	var src := lerpf(0.55, 1.0, player.mp / maxf(player.mp_max(), 1.0)) if player.mp > 0.0 else 0.25
	return Moves.CLASH_BASE * tech * src * (1.0 + _clash_surge)


## 对波的镜头：随局势切机位（硬切，机位自己缓缓在动）。a / b 两头的出手处，pt 交汇点
##   0 起手：主角出手的侧面近景                  1 全景：侧面，两束能量横贯画面，缓缓横移
##   2 交汇点特写：绕着交汇点缓缓转              3 压制对手：主角侧后上方，顺着光束看它把对手顶回去
##   4 被压制：对手侧后上方看过来，交汇点逼向主角
## 机位都离光束几米远：飞剑和它的拖尾就在光束里穿，贴着光束架机位会被糊一脸
func _clash_cam(a: Vector3, b: Vector3, pt: Vector3) -> void:
	var want := _clash_shot
	if _clash_t < 0.55:
		want = 0
	elif _clash_press > 0:
		want = 3
	elif _clash_press < 0:
		want = 4
	elif _clash_shot != 1 and _clash_shot != 2:
		want = 1
	elif _clash_shot_t > 2.2:
		want = 2 if _clash_shot == 1 else 1
	if want != _clash_shot:
		# 起手那一个机位到点就切；之后每个机位至少看 CLASH_SHOT_MIN 秒，想切去的机位还要稳住 CLASH_WANT_T 秒，
		# 压制 / 被压制一帧一翻的时候不会在两个机位之间来回跳
		if want != _clash_want:
			_clash_want = want
			_clash_want_t = 0.0
		if _clash_shot <= 0 or (_clash_shot_t >= CLASH_SHOT_MIN and _clash_want_t >= CLASH_WANT_T):
			_clash_shot = want
			_clash_shot_t = 0.0
	else:
		_clash_want = want
		_clash_want_t = 0.0
	var s := _clash_shot_t
	var side := _clash_side
	var mid := a.lerp(b, 0.5)
	var span := a.distance_to(b)
	var eye := mid
	var look := mid
	var fov := 58.0
	match _clash_shot:
		0:
			eye = a + side * (4.6 - 0.8 * s) + Vector3.UP * 0.5 - _beam_dir * 1.2
			look = a + _beam_dir * 2.2
			fov = 54.0
		1:
			eye = mid + side * (span * 0.5 + 8.0) + Vector3.UP * (2.0 + 0.5 * sin(s * 0.9)) + _beam_dir * (s * 1.4 - 1.6)
			look = mid.lerp(pt, 0.5)
			fov = 60.0
		2:
			var ang := s * 0.55 - 0.5
			eye = pt + (side * cos(ang) + _beam_dir * sin(ang) * 0.7).normalized() * (11.0 - 0.6 * s) + Vector3.UP * 2.4
			look = pt
			fov = 54.0
		3:
			eye = a - _beam_dir * (5.0 - minf(s, 1.2) * 0.8) + side * 3.6 + Vector3.UP * 2.6
			look = pt.lerp(b, 0.5)
			fov = 54.0
		4:
			eye = b + _beam_dir * (5.0 - minf(s, 1.2) * 0.8) + side * 3.6 + Vector3.UP * 2.6
			look = pt.lerp(a, 0.5)
			fov = 54.0
	eye.y = maxf(eye.y, _floor_at(eye) + 0.6)
	# 机位和它盯着的地方之间有东西挡着（柱子、台子）：把机位拉到挡住的东西前面
	var q := PhysicsRayQueryParameters3D.create(look, eye, 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		eye = hp + (look - hp).normalized() * 0.6 + (hit["normal"] as Vector3) * 0.3
	_cine_eye = eye
	_cine_look = look
	player.cam.cine_fov = fov


func _tick_clash(dt: float) -> void:
	_drives = true
	var foe := _clash_foe
	if not _alive(foe) or not foe.has_method("clash_power"):
		_clash_live = false
		player.caster.end_clash()
		_drop_cfx()
		_end_cine()
		_to_idle()
		return
	_face_target()
	_clash_t += dt
	_clash_shot_t += dt
	_clash_want_t += dt
	# 开场：先退到安全距离 / 抬到够高（_clash_place 定的位置），这段时间交汇点不动、不耗灵力
	var setup := _clash_setup > 0.0
	if setup:
		if _clash_to != Vector3.INF:
			var mv := _clash_to - player.global_position
			if mv.length() > 0.05:
				drive_vel = (mv / maxf(_clash_setup, dt)).limit_length(70.0)
		_clash_setup -= dt
	else:
		# 双方持续耗灵力（对手的在它的 clash_output 里扣）；灵力见底输出只剩四分之一
		player.mp = maxf(player.mp - Moves.CLASH_MP * dt, 0.0)
	player.caster.hold_regen()
	if demo_mash > 0.0:
		_mash_acc += demo_mash * dt
		while _mash_acc >= 1.0:
			_mash_acc -= 1.0
			_clash_tap()
	_clash_surge *= exp(-Moves.CLASH_SURGE_DECAY * dt)
	var mine := _clash_power()
	var netfoe := foe.has_method("net_clash_push")
	var adv := (_clash_u - 0.5) * 2.0
	if setup:
		adv = 0.0
	elif netfoe:
		# 对手是真人：各自累计自己顶了多少，交汇点两边对账
		_clash_my += mine * dt
		_clash_u = clampf(0.5 + _clash_my - float(foe.get("clash_their")), 0.0, 1.0)
		foe.call("net_clash_push", _clash_my)
		adv = (_clash_u - 0.5) * 2.0
	else:
		var theirs: float = foe.call("clash_output", _clash_t, dt) if foe.has_method("clash_output") else foe.clash_power()
		_clash_u = clampf(_clash_u + (mine - theirs) * (1.0 + 0.12 * _clash_t) * dt, 0.0, 1.0)
		adv = clampf((mine - theirs) / maxf(mine + theirs, 0.01) * 3.0 + (_clash_u - 0.5) * 1.4, -1.0, 1.0)
	_clash_adv = adv
	var a := _hand_point()
	var b: Vector3 = foe.clash_origin()
	_beam_dir = (b - a).normalized() if a.distance_squared_to(b) > 0.01 else _beam_dir
	var pt := a.lerp(b, _clash_u)
	# 压制：交汇点过了 CLASH_PRESS 这条线（退回到 0.62 以内才算解除），镜头切到压制方身后
	var press := _clash_press
	if _clash_u > Moves.CLASH_PRESS:
		press = 1
	elif _clash_u < 1.0 - Moves.CLASH_PRESS:
		press = -1
	elif _clash_u < 0.62 and _clash_u > 0.38:
		press = 0
	if press != _clash_press:
		_clash_press = press
		if press != 0:
			player.melee.combat_event.emit("air_clash_press", {"mine": press > 0, "pos": pt})
			Sfx.play("clash", -3.0, 1.3 if press > 0 else 0.7)
			player.cam.impact(0.4)
	_clash_cam(a, b, pt)
	var edge := maxf(absf(_clash_u - 0.5) * 2.0 - 0.5, 0.0)
	var heat := clampf(maxf(absf(_clash_u - 0.5) * 2.0, _clash_t / CLASH_MAX), 0.0, 1.0)
	if is_instance_valid(_cfx):
		_cfx.update(a, b, pt, adv, heat, dt)
	player.cam.add_trauma(0.045 + 0.03 * heat)
	# 空间扭曲：境界越高越强，带一点脉动；快分胜负时再涨
	Vfx.warp_pos = pt
	Vfx.warp_k = (WARP_BASE + WARP_STEP * float(player.realm_idx)) * (1.0 + 0.25 * sin(_clash_t * 9.0) + 0.8 * edge)
	var mine_c := Color.WHITE.lerp(_col(), 0.45)
	var theirs_c := Color.WHITE.lerp(foe.get("qi") as Color, 0.45) if foe.get("qi") != null else mine_c
	var side := _beam_dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	_clash_fx -= dt
	if _clash_fx <= 0.0:
		# 交汇点四溅的火星（两色交替）
		_clash_fx = 0.07
		var flip := randf() < 0.5
		Vfx.line_sparks(pt, (side if flip else -side) + Vector3.UP * randf_range(-0.6, 0.9), mine_c if flip else theirs_c, 7, 20.0, 150.0, 0.45)
	_clash_ring -= dt
	if _clash_ring <= 0.0:
		# 一圈圈冲击环沿着光束的垂面荡开，金铁交鸣
		_clash_ring = 0.22
		Vfx.shockwave(pt, _beam_dir if randf() < 0.6 else Vector3.UP, mine_c if randf() < 0.5 else theirs_c, 1.6 + edge)
		Vfx.blade_clash(pt, side if randf() < 0.5 else Vector3.UP, 1.0)
		Sfx.play("clash", -9.0, randf_range(0.9, 1.3))
	_clash_blast -= dt
	if _clash_blast <= 0.0:
		# 空间波动把凑过来的旁人震开（境界越高震得越远）
		_clash_blast = 0.5
		Vfx.quake(pt, 3.5)   # 贴着地面相持：交汇点底下的地一层层被削掉
		var spd := 16.0 + 2.5 * float(player.realm_idx)
		var any := false
		for e in Proj.targets(player.get_tree()):
			if e == foe or not e.has_method("blast_away"):
				continue
			if Proj.aim_of(e).distance_to(pt) < CLASH_BLAST_R or Proj.aim_of(e).distance_to(a) < CLASH_BLAST_R * 0.6:
				e.call("blast_away", pt, spd)
				any = true
		if any:
			Vfx.shockwave(pt, Vector3.UP, mine_c, 3.2)
			Sfx.play("slam", -8.0, 1.3)
	_clash_arc -= dt
	if _clash_arc <= 0.0:
		# 从交汇点甩出去的电弧
		_clash_arc = 0.11
		var od := (side * randf_range(-1.0, 1.0) + Vector3.UP * randf_range(-1.0, 1.0) + _beam_dir * randf_range(-0.3, 0.3)).normalized()
		Vfx.lightning(pt, pt + od * randf_range(2.5, 5.5), mine_c if randf() < 0.5 else theirs_c, 0.06, 0.12, 4)
	var win := _clash_u >= 0.97 or (_clash_t >= CLASH_MAX and _clash_u >= 0.5)
	var lose := _clash_u <= 0.03 or (_clash_t >= CLASH_MAX and _clash_u < 0.5)
	if netfoe:
		if _clash_auth:
			if win or lose:
				foe.call("net_clash_end", win)      # 我做主：把结果告诉对方
		else:
			win = _clash_forced == 1
			lose = _clash_forced == -1 or (not win and _clash_t > CLASH_MAX + 3.0)   # 一直等不到结果：按输收场
	if not (win or lose):
		return
	_clash_live = false
	foe.clash_end(win)
	player.caster.end_clash()
	Vfx.warp_pos = pt
	Vfx.warp_k = (WARP_BASE + WARP_STEP * float(player.realm_idx)) * 2.6    # 分胜负的一瞬间猛地一扭
	# 终爆：赢家的光束贯穿过去，在输家身上炸开（clash_fx.gd 的 finish）
	if is_instance_valid(_cfx):
		if win:
			_cfx.finish(a, Proj.aim_of(foe), true)
		else:
			_cfx.finish(b, player.center(), false)
	_cfx = null
	var cam := player.cam
	cam.impact(1.0)
	cam.add_trauma(0.7)
	Sfx.play("slam", 0.0, 0.9)
	if win:
		# 镜头跟着被轰飞的对手看半秒再交还（机位在侧后方，跟着它转，不是停在原地不动）
		_cine_eye = b - _beam_dir * 9.0 + _clash_side * 8.0 + Vector3.UP * 3.0
		_cine_eye.y = maxf(_cine_eye.y, _floor_at(_cine_eye) + 0.6)
		_cine_use_look = false
		_cine_follow = foe
		cam.cine_fov = 62.0
		_cine_dur = _cine_t + 0.5
		_cine_out = 0.22
		var dmg := _base() * 12.0     # 对波赢下来的这一轰抵得上一整套地面连段
		var dir := (_beam_dir + Vector3.UP * 0.12).normalized()
		if not netfoe:      # 对手是真人时，他那边会按「输」自己结算（挨一下、被轰飞），这里不重复打
			foe.air_hit(player, {"dmg": dmg, "dir": dir, "kb": 46.0, "stun": 1.0, "launch": "fwd", "heavy": true,
					"contact": Proj.aim_of(foe), "burst": true})
		_add_combo(dmg)
		Vfx.fire_explode(Proj.aim_of(foe), dir, true)
		# 破阵：剩下的剑流一拥而上（放大的剑，二十多柄）
		for i in 22:
			var fm: Array = player.caster._form(i, Proj.aim_of(foe))
			var off := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.9), randf_range(-1.0, 1.0))
			Proj.launch(player, Proj.K.SWORD, (fm[0] as Vector3) + off, foe, Proj.aim_of(foe), {"dmg": _base() * 0.12, "color": fm[1], "speed": 110.0,
					"hold": 0.012 * float(i), "turn": 18.0, "light": true, "lite": true, "sfx": i % 5 == 0, "trauma": 0.01, "life": 1.2,
					"scale": Proj.SWORD_SCALE * Moves.CLASH_SWORD, "tw": 0.15})
		if _is_launched(foe):
			_launched = foe
			_launch_kind = "fwd"
			_chase_n = 0
		cam.fov_punch(12.0)
		player.melee.combat_event.emit("air_clash_end", {"win": true, "pos": Proj.aim_of(foe)})
		_to_idle()
	else:
		# 输了：镜头马上交还，自己被轰飞
		_cine_dur = _cine_t + 0.15
		_cine_out = 0.15
		player.melee.combat_event.emit("air_clash_end", {"win": false, "pos": player.center()})
		if foe.has_method("clash_overrun"):
			foe.call("clash_overrun", player.center())     # 对手的剑流一拥而上
		Vfx.fire_explode(player.center(), -_beam_dir, true)
		_hurt(foe, {"dmg": 28.0, "kb": 30.0, "contact": player.center()}, (-_beam_dir + Vector3.UP * 0.1).normalized(), true)


# ---------- 聚气 / 觉醒 ----------

func _tick_gather(dt: float, held: bool) -> void:
	_drives = true
	_face_target()
	player.mp = minf(player.mp + GATHER_MP * dt, player.mp_max())
	if awake_t <= 0.0:
		awaken = minf(awaken + 7.0 * dt, 100.0)
	_aura_t -= dt
	if _aura_rise(0.1, 11.0):
		Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP, _col(), 6, 11.0, 28.0, 0.4, Vector3.ZERO)
	player.cam.add_trauma(0.015)
	player.hero.set_glow(0.14, _col())
	if awaken >= 100.0 and player.mp >= player.mp_max() * 0.6 and awake_t <= 0.0:
		_awaken()
	elif not held:
		_to_idle()


## 觉醒：气浪震开身边的对手，一段时间内伤害提高、追击不耗灵力、对波更有力
func _awaken() -> void:
	awaken = 0.0
	awake_t = _awake_dur
	_awake_fx_start()
	_to_idle()
	# 2026-11-25 英雄的觉醒演出（scripts/awaken_cine.gd：蓄势特写 → 黑白漫画冲击帧 → 放开）：只有本机主角、英雄表里有起手招（awake_move）时才演。
	# 演出期间无敌，气浪 / 震开挪到「放开」那一拍（_awaken_burst）；演出那一秒多不算在觉醒时长里
	var am := str(player.hero_def.get("awake_move", ""))
	var has_move := am != "" and _hero_moves.has(am) and state == A.IDLE
	var cine := has_move and AwakenCine.enabled and DisplayServer.get_name() != "headless"
	player.melee.combat_event.emit("air_awaken", {"cine": cine})
	if player.kit != null and player.kit.has_method("on_awaken"):
		player.kit.call("on_awaken")
	if has_move:
		_iframe = maxf(_iframe, (AwakenCine.TOTAL + 0.15) if cine else 0.7)
		_start_move(am)
		_rooted = true
	if not cine:
		_awaken_burst()
		return
	awake_t += AwakenCine.TOTAL
	Sfx.play("awaken", -2.0, 1.0)
	var ac: Node = AwakenCine.new()
	ac.set("player", player)
	ac.set("air", self)
	ac.set("title", str(_hero_moves[am].get("name", "觉醒")))
	ac.set("col", _col())
	ac.set("on_burst", Callable(self, "_awaken_burst").bind(true))
	player.add_child(ac)


## 觉醒的那一下气浪：震开身边的对手 + 镜头 / 特效 / 声音。没有演出时觉醒当场放；有演出时由演出在「放开」那一拍调（from_cine）
func _awaken_burst(from_cine := false) -> void:
	var c := player.center()
	var col := _col()
	if not from_cine:
		Combat.slowmo(0.2, 0.3, 0.45)
		Sfx.play("awaken" if player.hero_id != "" else "ascend", -2.0, 1.0 if player.hero_id != "" else 1.2)
	Vfx.breakthrough(player.global_position, col, 1.0)
	Vfx.shockwave(c, Vector3.UP, col, 3.2)
	Vfx.shockwave(c, Vector3.FORWARD, Color.WHITE.lerp(col, 0.4), 2.4)
	Sfx.play("slam", -4.0, 1.5)
	var cam := player.cam
	if not from_cine:
		cam.impact(0.8)        # 空间破碎：演出里已经有漫画帧了，不再叠
	cam.fov_punch(10.0)
	cam.add_trauma(0.5)
	if player.dead or player.st != Player.St.AIR:
		return
	for e in Proj.targets(player.get_tree()):
		var d := Proj.aim_of(e) - c
		if d.length() < 7.0 + Proj.body_r(e) and e.has_method("air_hit"):
			e.air_hit(player, {"dmg": _base() * 0.5, "dir": d.normalized() if d.length_squared() > 0.01 else _fwd(),
					"kb": 18.0, "stun": 0.8, "launch": "", "heavy": true, "contact": Proj.aim_of(e)})


## 2026-11-25 觉醒键（英雄档）：槽满了点一下「觉」/ V 就觉醒，不用再按住聚气攒到自动觉醒
func can_awaken() -> bool:
	if awaken < 100.0 or awake_t > 0.0 or player.st != Player.St.AIR or player.dead or player.ult.active or player.is_dashing():
		return false
	return state == A.IDLE or state == A.GUARD or state == A.GATHER or state == A.RUSH or state == A.DASH or (state == A.ATTACK and _hit_done)


func press_awaken() -> bool:
	if not can_awaken():
		return false
	parry_t = 0.0
	_awaken()
	return true


## 觉醒提前结束（终结技放完：大罡剑阵 / 万剑归宗）
func end_awaken() -> void:
	if awake_t > 0.0:
		awake_t = 0.001


## 立刻陨落（重伤流光流完 / 关卡判死，player.die_now）：不再问关卡要不要接住
func die_forced() -> void:
	_die_forced = true
	_die(player.center(), Vector3.UP)


# ---------- 2026-11-24 英雄技能用的接口（kit_*.gd 调） ----------

## 索敌（同点按「攻」）
func pick_target() -> Node3D:
	return _pick_target()


## 技能脚本出一招（hero_defs.gd 里的招式名）。t = 目标（null = 自己找）；opener = 远处突进的这一下在真人对打里算「起手」（补前摇）
func kit_move(id: String, t: Node3D = null, opener := false, pick := true) -> bool:
	if player.st != Player.St.AIR or player.dead or player.ult.active:
		return false
	if state == A.HURT or state == A.BLOWN or state == A.CRUSH or state == A.DOWN or state == A.CLASH or state == A.BRAWL \
			or state == A.GRABBED or state == A.THROW or state == A.DEAD or state == A.STOMP or state == A.CHARGE or state == A.SMASH:
		return false
	if state == A.ATTACK and not _hit_done:
		return false
	parry_t = 0.0
	_parry_dom = false
	_pend_far = false
	_end_blade()
	target = t if _alive(t) else (_pick_target() if pick else null)
	if target == null:
		face_yaw = player.cam.yaw      # 没有目标：朝镜头前方出手（一闪朝前冲出去）
		has_face = true
	_engage = ENGAGE_KEEP
	_queued = false
	_buf_at = -10.0
	if opener and _pvp(target) and Proj.aim_of(target).distance_to(player.center()) - _gap(target) > MAGNET:
		_open_begin()
	_start_move(id)
	return true


## 技能脚本起招架架势（回风 dur 秒，只接近身；radius > 0 = 剑域：这么大的圈里来犯者都接、飞来的剑气拨开，最多接 max_n 下）
func start_parry(dur: float, radius := 0.0, max_n := 1) -> bool:
	if player.st != Player.St.AIR or player.dead or player.ult.active:
		return false
	if state == A.HURT or state == A.BLOWN or state == A.CRUSH or state == A.DOWN or state == A.CLASH or state == A.BRAWL \
			or state == A.GRABBED or state == A.THROW or state == A.DEAD or state == A.STOMP or state == A.CHARGE or state == A.SMASH:
		return false
	if state == A.ATTACK and not _hit_done:
		return false
	_end_blade()
	_prot_end()
	state = A.GUARD
	_t = 0.0
	_guard_at = -10.0          # 招架不是护体刚按下：瞬身的兜底窗口不开
	_engage = ENGAGE_KEEP
	parry_t = dur
	parry_r = radius
	parry_n = 0
	parry_max = max_n
	_parry_dom = false
	rig.play("ck_parry")
	Vfx.glint(rig.tip_pos(), Color.WHITE.lerp(_col(), 0.4), 1.0)
	Sfx.play("swing", -8.0, 1.4)
	return true


## 招架成功后的那一斩（英雄表 parry_move，缺省 k_ctr）
func _parry_pid() -> String:
	return str(player.hero_def.get("parry_move", "k_ctr"))


## 招架判定（receive_attack 里）：-1 没接住（照常受击）· 1 拨开（剑域里飞来的剑气）· 2 招架成功（闪到身后反斩）
func _try_parry(src: Node3D, info: Dictionary) -> int:
	if parry_n >= parry_max or not is_instance_valid(src):
		return -1
	var ranged: bool = info.get("ranged", false)
	var sc := Proj.aim_of(src)
	if ranged:
		if parry_r <= 0.0:
			return -1      # 回风只接近身；飞来的东西按护体走（拨开 / 擦血）
		_swat(info, info.get("dir", -_fwd()) as Vector3)
		player.mp = minf(player.mp + Moves.SWAT_MP, player.mp_max())      # 剑域里拨剑气不花灵力
		return 1
	if parry_r > 0.0 and sc.distance_to(player.center()) > parry_r + Proj.body_r(src) + 1.5:
		return -1
	parry_n += 1
	_parry_counter(src, info)
	return 2


## 招架成功：剑上一声脆响 → 闪到对手身后 → 反斩（击倒）。对手：AI 这一下打空、露破绽；真人那边收到「你被招架了」自己硬直 0.5 秒（net.gd 的 _hit_res）
func _parry_counter(src: Node3D, info: Dictionary) -> void:
	var col := _col()
	var c: Vector3 = info.get("contact", player.center() + _fwd() * 0.6)
	Vfx.blade_clash(c, _fwd(), 1.4)
	Vfx.shockwave(c, _fwd(), Color.WHITE.lerp(col, 0.5), 1.2)
	Sfx.play("clash", 0.0, 1.15)
	Sfx.play("perfect", -4.0, 1.3)
	Combat.clear_hitstop()
	Combat.hitstop(0.08)
	player.cam.add_trauma(0.25)
	var sc := Proj.aim_of(src)
	var from_c := player.center()
	var away := _flat(sc - from_c)
	away = away.normalized() if away.length_squared() > 1e-4 else _fwd()
	var spot := safe_spot(sc, sc + away * (_gap(src, sc + away * 10.0) + 0.3) - Vector3(0.0, BODY_Y, 0.0))
	Vfx.vanish(from_c, col)
	if spot != Vector3.INF:
		var look := _flat(sc - spot)
		var yaw := atan2(-look.x, -look.z) if look.length_squared() > 0.01 else face_yaw
		player.warp_to(spot, yaw)
		_note_swap()
		face_yaw = yaw
		has_face = true
		_warp(spot + Vector3(0.0, BODY_Y, 0.0), 0.8)
	_iframe = maxf(_iframe, 0.35)
	_gslide = Vector3.ZERO
	if src.has_method("on_vanished"):
		src.on_vanished()          # AI：这一下打空，露出破绽
	if src.has_method("notify_parried"):
		src.notify_parried()       # 真人：告诉他被招架了（他那边自己硬直 0.5 秒）
	if parry_r <= 0.0 or parry_n >= parry_max:
		parry_t = 0.0              # 回风接一下就收；剑域接满 max_n 下或时间到（接满了剑域光环也跟着收，kit_canghong 看 parry_t）
	# 2026-11-24 修（复核 combat-7）：剑域还没接满、时间还没到 —— 这一斩收招后回到架势（_to_idle），反斩途中又有人近身也接（receive_attack）。
	# 以前反斩完就回了待机，剩下的一秒多剑域形同虚设（光环还亮着），最多接四下实际只接得到一下
	_parry_dom = parry_t > 0.0 and parry_r > 0.0
	player.melee.combat_event.emit("air_parry", {"pos": c})
	target = src
	state = A.IDLE
	_start_move(_parry_pid())
	if player.kit != null and player.kit.has_method("on_parried"):
		player.kit.call("on_parried", src)


## 真人对打：我这一下被对面招架了（net.gd 收到对方的 _hit_res 调）：刀被磕开，自己硬直 0.5 秒
func net_parried(src: Node3D) -> void:
	if player.st != Player.St.AIR or player.dead or state == A.DEAD:
		return
	var c := player.center() + _fwd() * 0.7
	Vfx.blade_clash(c, -_fwd(), 1.1)
	Sfx.play("clash", -2.0, 0.9)
	_repel(src, 6.0, 0.5, "air_parried")


## 脚下上扬的气丝（觉醒 / 蓄力 / 聚气，调用方每帧调，自己先把 _aura_t 减掉 dt）。
## 桌面档：每隔 gap 秒返回一次 true，调用方照旧放一把 ribbon_burst。
## 手机档：永远返回 false，改由一个常驻的 CPU 粒子发射器一直喷（不再反复新建 GPU 粒子，见 Vfx.aura_stream）
func _aura_rise(gap: float, speed: float) -> bool:
	if Vfx.lite:
		if _aura_p == null:
			_aura_p = Vfx.aura_stream(_col())
			_aura_p.position.y = 0.25
			player.add_child(_aura_p)
		_aura_p.color = _col()
		_aura_p.initial_velocity_max = speed
		_aura_p.initial_velocity_min = speed * 0.45
		_aura_want = true
		return false
	if _aura_t > 0.0:
		return false
	_aura_t = gap
	return true


## 觉醒期间常驻的表现：身体描边；元婴以上再加身周的空间波动。交给 awaken_fx.gd，它自己盯着 awake_t 收场
func _awake_fx_start() -> void:
	if _awake_fx == null:
		_awake_fx = AwakenFx.new()
		_awake_fx.hero = player.hero
		_awake_fx.body = player.hero
		_awake_fx.src = self
		_awake_fx.hidden_fn = func() -> bool: return player.dun_active or player.dead or not player.visual.visible
		player.add_child(_awake_fx)
	_awake_fx.start(awake_t, player.realm_idx, _col())


# ---------- 自己被打飞撞墙（2026-11-25，新图：实心盒子没有物理碰撞体，靠关卡的 solid_at 探）----------

## 被打飞的途中前面是墙 / 柱子 / 石头：场景破坏那边判撞不撞得穿（scripts/destruct.gd 的 body_crash）——
## 撞穿了：墙塌一块，人减速接着飞；没撞穿：贴墙一顿、弹下来。每次被打飞最多撞三回
func _blown_wall() -> void:
	var spd := _push.length()
	if spd < 16.0 or _wall_n >= 3 or player.ex_level() == null:
		return
	var dn := _push / spd
	if dn.y < -0.75:
		return      # 基本是朝下砸：交给坠地那一套
	var c := player.center()
	var hit := player.solid_hit(c, c + dn * (0.9 + spd * 0.05), 0.35)
	if hit == Vector3.INF:
		return
	_wall_n += 1
	var through := false
	if ResourceLoader.exists("res://scripts/destruct.gd"):
		var dx: GDScript = load("res://scripts/destruct.gd")
		through = dx != null and bool(dx.call("body_crash", hit, _push, 0.6))
	var m := player.melee
	m.hp = maxf(m.hp - (2.0 if through else 5.0), 1.0)
	var cam := player.cam
	Sfx.play("rock_break", -2.0, 1.0 if through else 0.85)
	if through:
		_push *= 0.7
		cam.add_trauma(0.4)
		player.melee.combat_event.emit("air_crash", {"pos": hit, "ground": false, "spd": spd, "through": true})
		return
	Vfx.wall_crash(hit, -dn, clampf(spd / 30.0, 0.8, 1.4))
	Sfx.play("punch_heavy", -2.0, 0.7)
	Combat.hitstop(0.08, 0.0)
	cam.add_trauma(0.55)
	_push = -dn * 3.5 + Vector3.DOWN * 2.0
	_dur = maxf(_dur, _t + 0.4)
	player.melee.combat_event.emit("air_crash", {"pos": hit, "ground": false, "spd": spd})


# ---------- 自己被砸到地面 ----------

func _on_floor() -> bool:
	if player.global_position.y <= 0.03:
		return true
	for i in player.get_slide_collision_count():
		if player.get_slide_collision(i).get_normal().y > 0.7:
			return true
	return false


func _crash_ground() -> void:
	var pos := player.global_position
	var power := clampf(_push.length() / 30.0, 0.8, 1.5)
	var m := player.melee
	m.hp = maxf(m.hp - 8.0, 0.0)
	Vfx.dun_slam(pos, Color(1.0, 0.85, 0.7), power)
	Vfx.crater(pos, power)
	if m.hp <= 0.0:
		# 砸地这一下把最后一点气血砸没了：当场陨落
		Sfx.play("slam", -1.0, 0.8)
		player.cam.add_trauma(0.65)
		_die(pos + Vector3(0.0, 0.6, 0.0), Vector3.UP)
		return
	Combat.hitstop(0.1, 0.0)
	Sfx.play("slam", -1.0, 0.8)
	Sfx.play("thud", -2.0, 0.6)
	var cam := player.cam
	cam.add_trauma(0.65)
	cam.impact(0.6)
	state = A.DOWN
	_t = 0.0
	_dur = 0.8
	_push = Vector3.ZERO
	_tumble = 0.0
	player.velocity = Vector3.ZERO
	player.melee.combat_event.emit("air_crash", {"pos": pos, "ground": true, "spd": 30.0})
