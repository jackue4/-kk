# B_mobs 交付报告：新图的怪物 / 首领底座（SPEC 第 4.5、8 节）

日期 2026-11-24。代号 B_mobs。只建 / 改了自己归属的文件；没有 commit / push。

## 1. 做了什么

- **怪物表 `scripts/ex/ex_mobs.gd`**：两张图的小怪、精英、首领、首领召唤物，每一项都是 raid_mob.gd 直接吃的 `def` 字典（外加新图字段），数值是扁平点数（不看境界），给了生成辅助 `setup()`、首领血量缩放、掉落表 / 重生 / 召唤条件查询、刷怪点抽样 `roll_camp()`、联机种类编号 `IDS`。
- **首领大脑 `scripts/ex/ex_boss.gd`**：挂在 raid_mob 首领上的技能大脑。8 个首领（凌幽 / 绛罗 / 沙渊巨虫 / 凌影 / 电鞭铁卫 / 冰僵铁卫 / 铁穹猎杀卫 + 焊愈卫）全部按 SPEC 第 8 节实现，每个首领 ≥2 个技能；通用规矩（跑出区拉回、区内 5 秒没人回满血、区外打无效、单下封顶 35 点、按区内真人数缩放血量）都在大脑里；视觉事件全部走 `fx_out` 广播 + `play_remote` 重放；伤害打本机走 `atk_out` 换算进 receive_attack、打远程走 `remote_player.mob_hit`。
- **体节虫 `scripts/ex/ex_worm.gd`**：程序拼的沙渊巨虫（头 + 10 节、砂岩配色、往尾巴渐细），钻地进出（潜行 / 破土立起 / 摇头 / 弧线扑入），身子沿头的轨迹走；每节都是判定框（见第 5.6 节）。既能当首领的身体，也能单独当节点用。
- **raid_mob.gd 加了几个默认关的挂点**（block_fn 挡墙、brain 大脑、model_key / size_k / tag_text 造型覆盖、三个大脑回调）；老大世界 `-- --raid-shot` 跑完全程无报错。
- **11 个新生物模型**拷进 `assets/creatures/`（精简动画、修掉退化缩放、博士 / 沙原领主 / 沙匪 / 远古巨人去掉全 0 的透明通道），导入、两档渲染器定妆过。
- **自检探针 `scripts/ex/ex_boss_selftest.gd`**：`-- --boss-test-ex[=id,…]`。主控已经在 main.gd 的探针表里接好了这个参数（我没改 main.gd），直接能跑。47 项两档渲染器全过。

## 2. 文件清单

| 文件 | 状态 | 说明 |
|---|---|---|
| `scripts/ex/ex_mobs.gd` | 新建 | 怪物表 + 生成辅助 |
| `scripts/ex/ex_boss.gd` | 新建 | 首领技能大脑 |
| `scripts/ex/ex_worm.gd` | 新建 | 体节虫身体 |
| `scripts/ex/ex_boss_selftest.gd` | 新建 | `--boss-test-ex` 自检 |
| `scripts/raid_mob.gd` | 改（只加挂点） | 备份 `_tasks/extraction_refactor/backup/raid_mob.gd.txt`（备份时就带着别的会话 11-23 的「身体表面」改动，那部分没动） |
| `assets/creatures/{zombie,mech_hunter,mech_welder,mech_claw,mech_gunner,gel_mutant,doctor,sand_lord,sand_raider,crystal_scorpion,stone_giant}.glb` | 新拷 | 连同导入时解出的贴图 png（同名前缀） |
| `_tasks/extraction_refactor/tools/strip_creature.py` | 新建 | 生物 GLB 精简工具（见第 8 节） |
| `_tasks/extraction_refactor/tools/locked_import.sh` | 新建 | 带 import.lock 的 `--import` |
| `_tasks/extraction_refactor/tools/stripped/*.glb` | 新建 | 精简后的原件（和 assets 里的一样，留作对照） |

## 3. raid_mob.gd 的改动（全部默认关；不设就和原来逐字节同样的行为）

```gdscript
var block_fn := Callable()   # func(from: Vector3, to: Vector3) -> bool（脚底位置，true = 走不过去）
var brain: Object = null     # 技能大脑；每帧先调 brain.mob_tick(self, cdt) -> int
var model_key := ""          # 非空就代替 def.model / elite_model；"-" = 什么都不建（身体外挂，巨虫用）
var size_k := 1.0            # 体型再乘一下
var tag_text := ""           # 非空就当名牌（不带 Lv.）
```
- `_process`：`brain.mob_tick()` 返回 0 = 照常跑状态机；1 = 跳过状态机（照常按 `_vel` 移动 / 挡墙 / 贴地 / 转身 / 动画）；2 = 连位置都不管（只剩闪光 / 动画 / 血条）。实现方式是 `match (state if bmode == 0 else -1)`，没改动原来的分支。
- 移动：设了 `block_fn` 才走新函数 `_unblocked(mv)`：整步 → 只走 X → 只走 Z → 停（竖直分量照走），闲逛撞墙早点换方向；`_keep_apart` 里小怪被主角顶开那一步也问 `block_fn`。
- 大脑回调（大脑有这个方法才调）：`_take()` 主角打它前问 `accept_hit(主角位置)`；`_take_raw()` 扣血前 `filter_damage(dmg)`（<=0 不扣）；`_hit_player()` 打中后 `dealt(点数)`（嗜血回血）。`_hit_player` 的返回值和原来一样。
- 回归：`-- --raid-shot` 全程跑完、26 张图、stderr 0 个 SCRIPT ERROR（日志 `_tasks/extraction_refactor/logs/raidshot_bmobs_*`，`raid_04_mob_fight.jpg` / `raid_21_boss_attack.jpg` 看过，名牌照旧「墨蛟 Lv.12」）。

## 4. 公共接口（照实现原样）

### 4.1 `ex_mobs.gd`（`const ExMobs := preload("res://scripts/ex/ex_mobs.gd")`，全是静态）

常量：`HIT_PER_UNIT = 10`、`HP_DESERT = 40`、`HP_LAB = 80`、`ELITE_HP = 3`、`BRUTE_HP = 2`、`ATK_DESERT = 5`、`ATK_LAB = 12`、`ELITE_ATK = 1.5`、`BOSS_HP_K = 0.04`、`BOSS_HIT_CAP = 35`、`SUMMON_MIN = 1`、`CAMP_MIN = 3`、`CAMP_MAX = 5`、`CAMP_ELITE_P = 0.12`；`MOBS`（id → def）、`IDS`（联机种类编号顺序，**只往后加**）、`CAMP_POOL`、`MAP_BOSSES`。

```gdscript
has(id) -> bool;  def(id) -> Dictionary;  idx(id) -> int;  by_idx(i) -> Dictionary;  id_of(i) -> String
is_boss(id) -> bool;  boss_name(id) -> String;  display_name(id, elite := false) -> String
hp_of(id, elite := false) -> float          # 小怪 / 精英 / 召唤物（点）
atk_of(id, elite := false) -> float         # 打在条上的点数（法衣减伤前）
players_k(players) -> float                 # 0.6 + 0.4·min(n,4)/4
boss_hp(id, players := 1) -> float          # DarkArea 血 × 0.04 × players_k
boss_drop(id) -> String;  boss_draws(id) -> int;  boss_respawn(id) -> float（召唤型 = 召唤冷却）
is_summoned(id) -> bool;  can_summon(id, players_in_arena) -> bool;  drops_loot(id) -> bool
setup(m, id, elite := false, players := 1)  # 给 new() 出来、还没进树的 raid_mob 填 def / elite / hp_max / atk / tag_text / meta(ex_id, def_idx)
roll_camp(map_id, rng) -> Array             # [[id, elite], …] 3~5 只；12% 是「精英 + 两只随从」（研究所精英一半是凝胶怪）
```

### 4.2 `ex_boss.gd`（`const ExBoss := preload("res://scripts/ex/ex_boss.gd")`）

```gdscript
static func attach(m, id: String, area: Rect2, opts := {}) -> Node3D          # 主人：挂大脑（设 m.brain、加成 m 的子节点 "ExBoss"）
static func attach_remote(puppet, id, area: Rect2, opts := {}) -> Node3D      # 木偶：只播画面（不设 puppet.brain）
static func link_duo(a_brain, b_brain)                                         # 铁穹双卫互认
static func countdown_label(parent: Node3D, pos: Vector3, font: Font = null) -> Label3D   # 出生点 3D 倒计时字
static func set_countdown(l: Label3D, title: String, secs: float)
func play_remote(kind: String, p: Dictionary)      # 管理器收到广播后调
func in_arena(p: Vector3, pad := 0.0) -> bool
func accept_hit(p: Vector3) -> bool                # 站在区外（> 2 米）打它无效；管理器处理「别人打我名下首领」时也要问
func players_in_arena() -> int
func drop_table() -> String                        # 凌影夜形态自动换 yanjiuBossDrops2
func drop_draws() -> int
func drop_points(n: int) -> Array                  # 战斗区里均匀撒 n 个贴地落点
signal event(kind: String, info: Dictionary)       # "frenzy" / "transform" / "reset" / "leash" / "summoned"
# raid_mob 调的：mob_tick(m, dt) -> int、filter_damage(d) -> float、dealt(d)
# 可读字段：boss_id, arena, home, transformed, frenzy, worm, dmg_k；自检用 casts / hits_dealt / fx_sent
```
`area` 是战斗区的 XZ 矩形（`Rect2(x 最小, z 最小, 宽, 深)`）。`opts` 键：`home`（出生点，默认 mob 位置）、`y_range`（`Vector2(最低, 最高)`，塔顶 / 洞窟要给，默认不限高）、`fx_out`（`func(kind, params)`）、`summon_fn`（`func(id: String, pos: Vector3, elite: bool) -> Node3D`）、`targets_fn`（可选，`func() -> Array` 返回所有能挨打的人；默认 = 本机主角 + `net.remotes`）、`net`、`night_fn`（`func() -> bool`）、`room_n_fn`（`func() -> int` 房间真人数）、`floor_fn`（默认用 `mob.floor_fn`）。

### 4.3 `ex_worm.gd`（`const ExWorm := preload("res://scripts/ex/ex_worm.gd")`，extends Node3D，top_level）

```gdscript
var segs := 10, seg_len := 2.3, head_r := 1.7, tail_r := 0.8, depth := 7.0
var floor_fn := Callable()  /  floor_y := 0.0      # 地面
var flash := 0.0, glow := 0.0, glow_col            # 受击闪白 / 常亮红光（嗜血）
var auto_area := Rect2()                           # 非空 = 自己在这个矩形里钻来钻去（独立节点用法）
var head: Vector3, head_dir: Vector3, mode: int（M.IDLE / TRAVEL / RISE / HOLD / ARC）
place(p, dir := FORWARD)            # 整条藏到 p 底下
travel(to, dur)  rise(at, h, dur)  hold(dur, look := INF)  arc(to, h, dur)
command(kind, a, b, h, dur)         # 带起点的命令（联机重放）；last_command() -> [kind, a, b, h, dur]
busy() -> bool;  phase() -> float
exposed_points() -> Array[Vector3];  is_exposed() -> bool
nearest_exposed(p) -> Array          # [中心, 半径]，全埋着返回 []
touches(p, extra := 0.6) -> bool;  head_radius() -> float;  ground(x, z) -> float
```

## 5. 给 extraction-manager 实现者的配方

### 5.1 刷一只小怪 / 精英（刷怪点、夜间尸潮、首领召唤都一样）

```gdscript
const Mob := preload("res://scripts/raid_mob.gd")
const ExMobs := preload("res://scripts/ex/ex_mobs.gd")

func _spawn_ex(id: String, pos: Vector3, elite := false) -> Mob:
	var m: Mob = Mob.new()
	m.player = player
	ExMobs.setup(m, id, elite)            # def / elite / hp_max / atk / tag_text / meta("ex_id", "def_idx")
	m.floor_fn = level.ground             # 必须（不给就贴在 y=0）
	if map_id == "lab":
		m.block_fn = level.blocked        # 研究所必须：不穿楼（沙漠可不给）
	m.dmg_in = player_dmg_vs.bind(m)      # 见下
	m.atk_out = to_player_from.bind(m)
	m.position = pos
	m.anchor = camp_center                # 刷怪点的怪（追丢走回点上）；其他的不设
	_nid += 1
	m.net_id = _nid
	m.died.connect(_on_mob_died)
	_mob_root.add_child(m)
	_mobs.append(m)
	return m

func player_dmg_vs(d: float, _t: Object) -> float:    # SPEC 4.5
	return d / player.hero_base() * ExMobs.HIT_PER_UNIT * weapon_pve * (1.0 + chip_pve)
func to_player_from(d: float, _t: Object) -> float:   # d 已经是条上点数
	return d * (1.0 - armor_pve_dr)
```
- 种类：沙漠 `scorpion / wolf_sand / sand_guard / sand_raider`，研究所 `zombie / mech_claw / mech_gunner`（凝胶怪 `gel_mutant` 只以精英出现，`setup` 会强制精英）。一处点刷什么用 `ExMobs.roll_camp(map_id, rng)`（固定种子就每局一样）。夜间尸潮直接刷 `zombie`。
- 掉落：小怪 25% 抽一次 `ExData.mob_table(map_id)`、精英必抽 1 次（SPEC 3.6）；`ExMobs.drops_loot(id) == false`（幽冥泣，以及首领召唤出来的东西 —— 建议召唤物一律不掉，用 `m.set_meta("summoned", true)` 自己记）不掉。
- 联机木偶（`net_mob_apply`）：`def_idx` 就是 `ExMobs.idx(id)`，反查 `ExMobs.id_of(int(e[1]))`；木偶照样 `ExMobs.setup(p, id, bool(e[4]))`，再 `p.hp_max = 100.0`（只用比例）、`floor_fn` / `block_fn`，`puppet = true` 等照 raid_manager。

### 5.2 刷首领

```gdscript
const ExBoss := preload("res://scripts/ex/ex_boss.gd")

func _spawn_boss(id: String, spawn: Vector3, arena: Rect2, y_lo: float, y_hi: float) -> Mob:
	var n := maxi(_players_in(arena), 1)
	var m: Mob = Mob.new()
	m.player = player
	ExMobs.setup(m, id, false, n)          # 血 = DarkArea × 0.04 × (0.6 + 0.4·min(n,4)/4)
	m.floor_fn = level.ground
	m.dmg_in = player_dmg_vs.bind(m)
	m.atk_out = to_player_from.bind(m)     # 大脑会再包一层「封顶 35」
	m.position = spawn
	_nid += 1
	m.net_id = _nid
	m.set_meta("boss_id", id)
	m.died.connect(_on_boss_died)
	_mob_root.add_child(m)
	var b := ExBoss.attach(m, id, arena, {
		"home": spawn, "y_range": Vector2(y_lo, y_hi), "net": net,
		"fx_out": func(kind: String, p: Dictionary) -> void: _send_boss_fx(m.net_id, kind, p),
		"summon_fn": func(sid: String, pos: Vector3, elite: bool) -> Node3D:
			var a := _spawn_ex(sid, pos, elite)
			a.set_meta("summoned", true)
			a.alert()
			return a,
		"night_fn": level.is_night,
		"room_n_fn": func() -> int: return net.players.size() if net.active else 1})
	b.event.connect(_on_boss_event.bind(m))
	return m
```
- 铁穹双卫：在召唤台 `ExMobs.can_summon("duo_hunter", 区内人数)` 为真时刷 `duo_hunter` + `duo_welder` 两只（同一个 arena），然后 `ExBoss.link_duo(b_hunter, b_welder)`。掉落 `lvBuDiaoChanBossDrop × 48` **两只都死了才掉一次**（第二只死的时候掉）。
- 沙渊巨虫：祭台 `ExMobs.can_summon("sandworm", n)`；def 里 `model = "-"`，大脑自己建 ExWorm，管理器什么都不用多做。召唤冷却 `ExMobs.boss_respawn("sandworm")` = 600。
- 其余（凌幽 / 绛罗 / 凌影 / 电鞭 / 冰僵）：死后 `ExMobs.boss_respawn(id)` 秒（600 / 500 / 600 / 500 / 500）原地重生；倒计时字 `ExBoss.countdown_label(_mob_root, spawn)` + 每秒 `ExBoss.set_countdown(lbl, ExMobs.boss_name(id), 剩余秒)`。
- 首领也要放进 `_my_mobs()` / `net_mob_batch()`（和 raid_manager 的巢穴首领一样），这样 `net_find_mob` 找得到、木偶有位置 / 血量。
- 血量缩放：生成时按区内人数；之后有更多人进区，大脑每秒检查一次、只往上调（保持血量比例）；区里空 5 秒复位时回到 1 人档。管理器不用管。
- **远程玩家打我名下的首领**：`net_mob_take(from, …)` 里先 `var br = m.brain; if br != null and not br.accept_hit(_remote(from).global_position): return`，再 `m.net_damage(...)`（本机主角打的 raid_mob 自己会问）。
- 首领单下伤害：大脑技能自己封顶 35；默认 AI 的扑击 / 震地（atk × 1.5 / × 2）在表里的 atk 下都不超过 35（变身后 ×1.3 也不超）。

### 5.3 首领死亡 / 掉落 / 播报

```gdscript
func _on_boss_died(m: Node3D) -> void:      # died 信号发出时大脑还在（之后才 queue_free）
	var b: Node3D = m.get_node_or_null("ExBoss")
	var table: String = b.drop_table() if b != null else ExMobs.boss_drop(String(m.get_meta("boss_id")))
	var items: Array = ExData.roll(table, rng, b.drop_draws() if b != null else -1)
	var pts: Array = b.drop_points(items.size())
	for i in items.size():
		_drop_item(pts[i], items[i], 1.0)       # 逐件撒满战斗区（SPEC 8）
	# 仙玉 +5、全房播报（带击杀者名）、记重生时刻
```
- `event` 信号：`frenzy`（巨虫半血嗜血，info.name）、`transform`（info.kind = "night"（凌影狂潮霸主）/ "duo"（双卫另一只变身），info.name）、`reset`（区内没人复位）、`leash`（跑出区被拉回）、`summoned`（info.id / info.node）。建议 frenzy / transform 走 `hud.banner`。

### 5.4 联机：视觉事件广播

- 主人：`fx_out(kind, params)` 里把 `[mob.net_id, kind, params]` 发给房里其他人。params 只含 Vector3 / Color / Array / Dictionary / float / int / bool / String。
  通道二选一：主控在 net.gd 加一条可靠 RPC（建议 `send_boss_fx(nid, kind, params)` → `raid.net_boss_fx(from, nid, kind, params)`）；或者借小消息 `net_send("§b", var_to_str([nid, kind, params]))`，收方 `str_to_var`（局域网、只解出基础类型）。
- 收方：`var pm := net_find_mob(owner, nid)` → `var br := pm.get_node_or_null("ExBoss")` → `br.play_remote(kind, params)`。
- 收方建首领木偶时：`ExMobs.setup(p, id, false)` 后 `ExBoss.attach_remote(p, id, arena, {"home": spawn, "net": net, "night_fn": level.is_night})`（巨虫木偶的身子、画面上的弹幕 / 沙卷风 / 预警 / 锁链都靠它）。
- 「作用在人身上」的效果：锁链拉人（`chain`）和双卫出圈拉回（`pull`）的参数里带了目标的 `peer`，收方大脑看到是自己就把本机主角拉过去；伤害由主人发 `mob_hit`（走现有 `send_mob_attack`），收方按自己的法衣换算。
- 事件种类：`shot spiral bomb tornado lob summon whip storm charge chain pull heal transform frenzy worm cast reset`。

### 5.5 每个首领做什么（数值都是打在条上的点数，法衣减伤前；单下封顶 35）

| 首领 | id | 模型 | 血（1 人 / 4 人） | 走位 | 技能 |
|---|---|---|---|---|---|
| 凌幽（金塔守灵） | `lingyou` | sand_lord | 2240 / 3200 | 不动、转身 | 追踪弹：每 2 秒给区内每人一发（9 点，速度 15、转向 1.6 rad/s）；螺旋弹幕：每 5 秒，三条旋臂 1.4 秒吐完，发数 = clamp(floor(50 − 血/(最大血/40)), 10, 50)，每颗 5 点 |
| 绛罗 | `jiangluo` | void_apostle（浮空） | 2520 / 3600 | 风筝：最近的人进 8 米就背着他逃 10 米（落点夹在区里） | 召唤幽冥泣（`wraith`，180 血 / 7 攻，浮空远程，不掉东西）每 14 秒 2 只、最多 4 只；慢速追踪弹 7 点 / 3 秒 |
| 沙渊巨虫 | `sandworm` | 程序体节虫 | 4480 / 6400 | 钻地循环：地下潜到某人身边 → 破土立起（落点 3.4 米内 17 点）→ 摇头 4.5 秒（嗜血 3.5）→ 弧线扑向某人钻回 → … 身子碰人 14 点（同一人 1 秒一次）；埋着时打不到 | 定点爆炸：每 3 秒锁 1 人（嗜血 2 人），脚下 + ±4 米共 6 个落点（嗜血 9），预警 1.5 秒，半径 2.2，18 点（嗜血 26），同一人一轮只吃一次；沙卷风：每 7 秒 3 个（嗜血 4），起点在某人 2 米外朝着他，预警 2 秒 → 原地 2 秒 → 5 秒（嗜血 3.5）直线推 55 米（裁到区边），半径 3（嗜血 5），每 0.4 秒 4 点；≤50% 嗜血：打中的点数 × 最大血 × 0.12% 回血，累计封顶 30% |
| 凌影 | `lingying` | gel_mutant 放大 | 2240 / 3200（夜 ×1.9） | raid_mob 原来的追击扑击震地 | 白天：投掷尸傀（每 6 秒抛一只翻滚的尸傀到某人身边，预警圈 1.1 秒，落地 2.5 米 8 点并变成一只 `zombie`）、召唤 3 只（16 秒），场上召唤物上限 10；夜里（`night_fn` 真且房间人数 ≥ SUMMON_MIN）变「狂潮霸主·凌影」：血 ×1.9（保比例）、紫色、体型 ×1.15、掉落换表；尸潮：场上不足 7 只就每秒补 2 只（每 4 只一只精英） |
| 电鞭铁卫 | `dianbian` | mech_hunter 蓝色改色 | 1400 / 2000 | 不动、转身 | 雷电普攻：每 1.8 秒给区内每人一发快速电针（8 点）；五连鞭：每 7 秒朝最近的人扇形 5 道（80°、18 米），预警 0.9 秒后依次劈下，14 点；雷暴：每 12 秒区里随机 6 道 + 每人脚下一道，预警 1.2 秒，半径 2.6，16 点 |
| 冰僵铁卫 | `bingjiang` | stone_giant 冰蓝改色 | 1400 / 2000 | 原来的追击 | 冲锋：每 9 秒，5~28 米内最近的人，蓄势 0.8 秒（地上一条预警）→ 0.6 秒冲 20 米（不出区），路上 18 点；锁链：每 11 秒锁区里最远（≥8 米）的人，0.6 秒后拉到身前 + 8 点 |
| 铁穹猎杀卫 | `duo_hunter` | mech_hunter | 5600 / 8000 | 原来的追击 | 出圈拉回：打着的时候有人出圈（25 米内）拉回圈里 + 20 点；冲锋（同冰僵，15 点）；焊愈卫半血以下时变身（体型 ×1.2、伤害 ×1.3） |
| 铁穹焊愈卫 | `duo_welder` | mech_welder | 5600 / 8000 | 和最近的人保持 10 米 | 焊愈：活着每秒给猎杀卫回最大血 0.5%（绿色电弧）；追踪弹 8 点 / 2.2 秒；猎杀卫半血以下时变身 |

所有首领：跑出战斗区 4 米传回出生点；区内（含 2 米余量、`y_range`）5 秒没人 → 回满血、撤掉嗜血 / 双卫变身 / 场上沙卷风和弹幕、血量回 1 人档、技能冷却重来；站在区外打它无效。召唤型首领的召唤条件 `ExMobs.SUMMON_MIN = 1`（DarkArea 4）。

### 5.6 沙渊巨虫（ex_worm）怎么当首领用

- 管理器只管按 5.2 刷 `sandworm`（`def.model = "-"` → raid_mob 不建模型），`ExBoss` 在 `_ready` 里自己 `ExWorm.new()`、设 `floor_fn`、`place(home)`，挂成自己的子节点（top_level，世界坐标）。
- 判定：raid_mob 本身只有一个位置。大脑每帧（巨虫先动 `process_priority = -1`，大脑后摆）把 mob 摆到「离本机主角最近的露出地面的那一节」的中心、`_half_x/_half_z` = 那节半径 —— 主角的近战 / 飞剑 / 锁定、`_keep_apart` 顶人都打在 / 顶在那一节上；全埋着时 mob 沉到出生点地下 30 米，`filter_damage` 也返回 0。木偶那边的大脑做同样的事（按它自己的本机主角），所以每个人都能打离自己最近的那节。
- AI 修士 / 道友打它用的是 mob 的位置（= 离房主主角最近的那节），差一点不影响。
- 独立用：`var w := ExWorm.new(); w.floor_fn = level.ground; add_child(w); w.place(p); w.auto_area = Rect2(...)`（自己钻），或者手动 `travel / rise / hold / arc`。

## 6. 自检

命令（项目根目录）：
```
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/bossx --resolution 1280x720 -- --boss-test-ex
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/bossx_gl --resolution 1280x720 --rendering-method gl_compatibility -- --boss-test-ex --touch
# 只测几个：-- --boss-test-ex=sandworm,duo（id：lingyou jiangluo sandworm lingying dianbian bingjiang duo）
```
不依赖关卡 / 管理器：主城停用后在 (700, 40, −700) 搭一块平地沙盘（自己的天空 / 日光 / 地面碰撞），测完放回主城、退出。打印 `[bossx]`。主角不出手、站着挨打（每帧回满血，记下挨了多少）。

结果（日志 `_tasks/extraction_refactor/logs/`：Forward+ `bossx4`、`bossx6`，兼容 + 触屏 `bossx5_gl`）：**47 项全部通过，0 个 SCRIPT ERROR**，一遍约 150 秒；铁穹两只修过退化缩放后 `bossx7`（`=dianbian,duo`）stderr 0 行。要点：
- 新怪：14 种小怪 / 精英 + 幽冥泣的血 / 攻 / 名牌打印正确（沙漠 40 / 5，研究所 80 / 12，精英 ×3 / ×1.5，沙灵守卫巨汉 ×2）；`roll_camp` 60 次抽样都在 3~5 只、种类属于本图。
- `block_fn`：一堵墙，带挡墙的尸傀 6 秒没过墙，不带的直接穿过去。
- 凌幽：11 秒追踪弹 5 次、螺旋 2 次，原地不动，主角挨 45 点；一成血时螺旋 46 发；联机重放的木偶大脑最多同时画 22 颗弹、命中 0。
- 绛罗：贴脸 6.8 → 2 秒后 17.5 米；召唤 2 只幽冥泣。
- 巨虫：埋地免伤、露头能打；判定点 57/57 帧都在离主角最近的那节上；16 秒定点爆炸 4~5 次、沙卷风 2 次、钻地命令 14~16 条；半血嗜血、打中 20 点回 107.5（2.4%）。
- 凌影：白天投掷 / 召唤；入夜 2240 → 4256（×1.9，比例不变）、尸潮补到 7~8 只、掉落表换成 yanjiuBossDrops2。
- 电鞭：14 秒普攻 6~7、五连鞭 2、雷暴 1。冰僵：冲锋 2、锁链 1，锁链前 8.7 米、拉完 4.9 米。
- 双卫：焊愈 2240 → 2296（2.2 秒）、另一只变身（伤害 ×1.3）、出圈 4 米被拉回 + 20 点。
- 每个首领：区外打无效（区内一下 30、区外 0）、区内没人约 5.1 秒回满、跑出区拉回出生点。
- 站着不动挨的伤害（最坏情况，法衣减伤 0）：凌幽 4 点/秒、电鞭 7、冰僵 8、巨虫 10（嗜血后 8~12）。
- 沙盘里打首领时最高绘制调用：凌幽 164、绛罗 193、电鞭 197、巨虫 282（Forward+；沙盘地面网格线和柱子本身约 60）。

模型定妆：`-s res://_tasks/creature_gallery.gd -- zombie mech_hunter mech_welder mech_claw mech_gunner gel_mutant doctor sand_lord sand_raider crystal_scorpion stone_giant`，两档渲染器都正常（博士不透明、看得见）。

## 7. 截图（只看 jpg）

- 定妆：`_shots/preview/bmobs/gal_fwd_0.jpg`、`gal_fwd_1.jpg`（Forward+）、`gal_gl_0.jpg`、`gal_gl_1.jpg`（兼容），以及铁穹两只修过退化缩放后的复查 `gal_mech_fwd.jpg` / `gal_mech_gl.jpg`。
- 自检：`_shots/preview/bmobs/fwd/ex_boss_*.jpg`（Forward+）、`_shots/preview/bmobs/gl/ex_boss_*.jpg`（兼容 + 触屏）。值得看的：`ex_boss_lineup`（新怪排一排）、`ex_boss_sandworm_5 / _9 / _13 / _frenzy`（虫子立起 / 沙卷风 / 爆炸预警）、`ex_boss_dianbian_a / _b`（五连鞭扇形预警、雷暴圈）、`ex_boss_lingying_a / _night`（抛尸傀、狂潮霸主 + 尸潮）、`ex_boss_lingyou_a / _b`（弹幕）、`ex_boss_bingjiang_a`、`ex_boss_duo_a / _b`、`ex_boss_blockfn`。
- 老大世界回归：`_shots/preview/raid_04_mob_fight.jpg`、`raid_21_boss_attack.jpg`。

## 8. 模型

| 文件 | 来源 | 源 → 进包 | 动画（ROLES 用到的） |
|---|---|---|---|
| zombie | 06 待核名实体_100001 | 1.49 → 0.70 MB | 待机 / 走 / 跑 / 攻 / 受击 / 死亡 |
| mech_hunter | 05 铁穹猎杀卫_100131 | 1.41 → 1.13 | 5 段（跑 = 走） |
| mech_welder | 05 铁穹焊愈卫_100132 | 1.91 → 1.23 | 6 段 |
| mech_claw / mech_gunner | 05 铁穹钳击兵 / 炮击兵 | 0.92 → 0.87 / 1.05 → 1.00 | 5 段 |
| gel_mutant | 05 凝胶怪_100243 | 3.27 → 1.35 | 6 段（材质 MASK，透明度 174~255，看得见） |
| doctor | 05 虚空博士_310101 | 2.16 → 1.19 | 6 段 + 100102 躺（`原始序列_100102`，营救前被困可以播）；**贴图透明通道去掉、材质强制不透明** |
| sand_lord | 05 沙原领主_100075 | 4.12 → 1.53 | 5 段；贴图去透明 |
| sand_raider | 05 海盗掠夺者_130042 | 3.95 → 0.81 | 6 段；贴图去透明 |
| crystal_scorpion | 05 天蝎0级_110186 | 3.96 → 3.11 | 5 段（攻击 = 100108）；贴图 512 本身带透明（MASK），没动 |
| stone_giant | 05 远古巨人_100054 | 4.66 → 1.78 | 5 段；贴图去透明 |

- 工具 `python -I _tasks/extraction_refactor/tools/strip_creature.py <源> <出> [--max 512] [--opaque] [--extra 100102] [--info]`：不动网格 / 骨骼 / 蒙皮，只删 ROLES 用不到的动画（留下的保留全部轨道，含缩放）、贴图限 512、`--opaque` 去透明、修退化缩放（铁穹两只的 `700/701` 节点缩放是 7.9e16 / 0 这种垃圾值，导入和播动画时刷「Basis must be normalized」，改成 0.001 后导入 0 条报错）、重新打包。和 hero_skin 的 strip_glb.py 不同，它不需要点名网格。
- 生物合计进包约 14.7 MB GLB（解出的贴图另算）。凝胶怪 / 晶甲天蝎的贴图是 512 的 RGBA。

## 9. 已知问题 / 注意

1. **首领血量很厚**（按 SPEC：DarkArea × 0.04）：单人双卫合计 11200 点，按主角每秒 15~25 点算要 7~12 分钟，900 秒一局里很吃紧；巨虫单人 4480 约 3~5 分钟。数都在 ex_mobs 顶部，主控要调就改 `BOSS_HP_K` 或单个首领的 `boss_hp`。
2. 站着不动挨打的伤害偏高（见第 6 节），首领本来是给多人设计的；技能伤害都在 ex_boss.gd 顶部 `SKILLS` 表里，调起来一行一个数。
3. 锁链 / 出圈拉回是直接平移本机主角的位置（0.3 秒，不做碰撞），战斗区里有柱子的话可能被拉进柱子里一下（主角自己的物理随后会推出来）。研究所的场地若有障碍物，建议把那两块场地清空。
4. 巨虫的判定点「离本机主角最近的那节」：AI 修士 / 道友打它时用的是房主那边的位置，差几米。
5. raid_mob 原有的首领死亡 `Combat.slowmo(0.25, 0.25, 0.4)`（击杀首领那一下慢动作）照旧保留，没动（SPEC 只禁普通技能的慢动作）。
6. 弹幕用的是现有的 `shaders/boss_bullet.gdshader`（试剑台剑冢首领那套），**它不在 warmup.gd 的预热名单里**：网页版第一次看到首领弹幕可能卡一下。请主控在 warmup 的 "ex" 那一档加上它。预警圈 / 冲击环用的是已经预热过的 `mob_ring.gdshader`，沙卷风 / 虫子是普通的顶点色材质（走 `MeshLib.vcol` 的 `Data.add_box`）。
7. 新出现的汉字（怪名 / 精英名 / 首领名 / 称号）在别的代理跑 `font_check.py --patch` 时已经补进补字字体（`font_check.py` 核对：我的文件里没有「没补上」的字），补字字体的导入比它新，没再跑一遍。
8. 双卫木偶这边没有 `partner`（木偶大脑只播画面，不用）；变身的体型变化靠 `transform` 广播在木偶那边也做一遍。
9. 召唤物 / 尸潮的上限按单个首领算（凌影 10 只、尸潮补到 7）；和管理器的全图 `mob_cap` 不冲突时没问题，冲突的话 `summon_fn` 里返回 null 就行（大脑会跳过）。
10. 自检的沙盘没有真实地形 / 楼宇，首领在真实场地（塔顶台阶、洞窟、楼间）的表现要等关卡和管理器接上后在 `--level-test` 里再看一遍；特别是凌幽在塔顶时 `y_range` 要给对（台面高度 −2 ~ +12 米左右），否则从塔下飞剑也能打到它。

## 10. 需要主控做的

- `--boss-test-ex` 已经在 main.gd 的探针表里（我看到的版本已经有），不用再加。
- warmup.gd 的 "ex" 档预热 `res://shaders/boss_bullet.gdshader`（第 9.6 条）。
- net.gd：给首领视觉事件一条通道（第 5.4 节，二选一）。
