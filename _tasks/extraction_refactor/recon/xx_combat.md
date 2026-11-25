# 战斗系统摸底 & 英雄抽象方案（xx_combat）

只读调研，2026-11-24，按工作区现状（含别的会话未提交的改动）。行号都对应现在的文件。

---

## 0. 结构总览（谁管什么）

- `scripts/player.gd`（**有 `class_name Player`**，是项目里少数例外）：移动 + 状态机 `enum St { GROUND, TAKEOFF, FLY, AIR, DIVE }`（:24）。`_ready` 里建四个战斗子节点（:180-191）：`melee`（PlayerMelee，地面刀剑 + **气血容器**）、`caster`（AirCaster，剑诀 / 连发 / 灵力回复）、`air`（AirMelee，空战拳脚全部规则）、`ult`（GateArray，R 大罡剑阵）。每帧顺序 `melee.tick → caster.tick → air.tick → ult.tick`（:980-983），然后按 st 分派 `_ground/_takeoff/_fly/_air/_dive`（:989-999）。
- `scripts/air_moves.gd`：空战招式表 `MOVES / CHAIN / JUGGLE / SMASH` + 攻防常数 + 真人对打规则，**主角和 AI（air_foe.gd）共用**（:1-27 注释、:35-79）。
- `scripts/air_melee.gd`（4371 行）：空战状态机 `enum A { IDLE, RUSH, ATTACK, CHARGE, SMASH, GUARD, HURT, BLOWN, CLASH, GATHER, DOWN, DASH, CRUSH, DEAD, THROW, GRABBED, BRAWL, STOMP }`（:48）。
- `scripts/player_melee.gd`：地面三段连招 / 弹反 / 格挡 / 架势 / 处决（只狼式），`enum M`（:22），`hp`（`HP_MAX := 100.0`，:24）——**所有模式的主角气血都存在 `player.melee.hp`**（外部脚本引用 `player.melee.hp` 93 处）。
- `scripts/combat_stats.gd`（CS）：数值中枢；`scripts/realm.gd`：境界表 `LIST`、法相 `ARTS`、表现档 `COMBAT`。
- 动画：`voxel_hero.gd`（15 关节骨架）+ `fighter_rig.gd`（播 `combat_poses.gd` 的关键帧时间轴，`play(name)` 记 `last_name / play_n` 供联机，:59-65）+ `hero_skin.gd`（把 GLB 骨骼贴到关节上，招式不播模型动画）。

---

## 1. 现有角色的完整招式清单

键位在 `main.gd:_setup_input`（:582-613）注册：WASD 移动、Space `jump`、Shift `sprint`、F `fly`、J/左键 `attack`、K/右键 `guard`、E `air_shot`（同时也是 `burst`）、Z `skill_next`、V `gather`、Q `summon`、R `ult`、G `toggle_auto`、B `bag`；T `pickup` 在 `raid_hud.gd:158`。触屏按钮表 `touch_controls.gd:BUTTONS`（:37-48）：攻=attack、御=guard、闪=sprint、剑=air_shot、诀=skill_next、罡=ult、飞=fly（低境界地面上发 jump，:257-259）、阵=summon、境±=调试。触屏按钮会按场合换字（:462-512：追/反/踏/弹/擒/脱/瞬/雨/连点/对波/聚），**按钮字体是按用到的字裁剪的子集**，新字要补字库。

### 1.1 地面（只有炼气 / 筑基真正用到，`player_melee.gd`）
关键前提：结丹起（`Realm.Mode.LIGHT`）在地上按「攻」/「御」会直接腾空进空战（`_to_air_combat` :338-341 → `player.enter_air_combat()` → `air.press_from_ground`），**地面刀剑只对炼气 / 筑基生效**。

| 输入 | 招式 | 数值 | 实现 |
|---|---|---|---|
| J 连按 | 起手斜斩 → 回身横斩 → 跃斩下劈 | dmg 9 / 11 / 17 × `CS.ground_k`（= base(境界)/8），削架势 10/14/24，判定 0.14/0.125/0.385 秒 | `ATK` :50-76，`_start_attack` :552，`_resolve_hit` :860，`_hit_info` :848 |
| 跳起后 J | 空中横斩 / 回旋斩（每次离地最多 2 段） | 8 / 9 | `AIR_FIRST`/`AIR_SLASH_MAX` :36,49 |
| K 点按 | 弹反（窗口 0.2 秒，空中 0.24，0.35 秒内连按缩到 0.1） | 对方削架势 | `press_guard` :449，`receive_attack` :990-1015 |
| K 按住 | 格挡（擦 15% 血 `CS.BLOCK_CHIP`，自己涨架势） | — | :1009-1013 |
| Shift 短按 | 闪避 3 米 / 30 m/s，全程无敌 +0.08 秒，冷却 = 0.1+0.12 | 完美闪避窗口 0.3 秒 → 下一刀瞬移到侧后 ×1.6 伤害、不可挡 | `player.blink` :803，`DODGE_*` :47-53，`perfect_dodge` :870，`_try_warp` :392 |
| 对破防敌人 J | 处决（只对 swordsman 的 `is_broken()`） | — | `_try_execute` :973 |
| E（剑阵召出后） | 万剑齐发 | 飞剑伤害 realm dmg × `CS.q_k` | `sword_manager.gd:383-389`、`flying_sword.gd:560` |
| Q | 飞剑阵（剑数 = 境界 swords 3~24，起手 12% 灵力、每秒 3.5%，持续 20 秒） | — | `sword_manager.gd:17-21` |

### 1.2 空战（结丹起，`air_melee.gd` + `air_moves.gd` + `air_caster.gd`）
伤害一律 = `_base()` × 招式单位，`_base() = realm["dmg"] × (1.3 觉醒)`（:522-523）。灵力单位池 90~130（`CS.MP_UNITS` :132）。

| 输入 | 招式 | 单位 / 消耗 / 冷却 | 实现 |
|---|---|---|---|
| J 点按（近） | 五段：冲拳 l1 0.45 → 摆拳 l2 0.45 → 蹬踢 l3 0.6 → 回旋踢 l4 0.8 → 掣剑横斩 l5 1.3（击飞 fwd）；每下跟 1~3 柄飞剑（每柄 ×0.2） | 每中一下回灵力 2.5（重手 ×2）；连段第 9 下起伤害每下 −4.5% | `Moves.MOVES` :37-47，`_begin_combo` :1090，`_start_move` :1306，`_tick_attack` :2921，`_resolve` :3180，`_sword_follow` :3353 |
| J 点按（远，≤36 m） | 追身突进 RUSH 62 m/s；炼虚起变缩地 | PvP 近身耗 5 / 缩地 10 | `_start_rush` :1183 |
| 连段中 摇杆+J | 前=挑月 d_up 0.9 击飞 up；后=坠星 d_dn 1.0 击飞 down；左右=绕身击 d_fl 0.85（绕背，耗 4） | | `_next_id` :873 |
| J 长按 ≥0.24 秒 | 蓄力重击（0.7 秒蓄满，过半破防）：松手 不推=崩拳 / 前或 Space=挑飞 / 后=陨落；单位 1.5+1.3k；远处长按 = 原地蓄力后 150 m/s 飞过去 | PvP 飞过去耗 6 | `_start_charge` :1372，`_start_smash` :1410，`_tick_smash` :3022（伤害 :3072） |
| 对手被打飞后 J | 瞬身追击（截在飞行路线前头接 j1），一套最多 3 次，每次 8 灵力（觉醒免费）；身前则空中连击 j1/j2/j3 0.4/0.4/0.6 → 终结重击 | | `_start_chase` :1491，`_start_juggle` :1147，`_start_finisher` :1160 |
| 对手被打飞后 Shift | 追身（150 m/s 飞过去，半价 4） | | `try_homing` :1522 |
| 摇杆后拉+J（贴身） | 擒拿抡摔，护体挡不住，THROW_DMG 1.5 | | `_start_throw` :1653，伤害 :1733 |
| 对手砸进地里时 J / E | 坠星踏 2.2 / 剑雨灌顶 1.9（耗 12%） | | `_start_stomp` :2159，`_start_rain` :2252 |
| 气弹将至时 J | 反手抽回（×0.6，耗 2） | | `_try_swat` :2339 |
| K 按住 | 护体：正面挡下擦 15% 血、耗 6 灵力（重手 12）；蓄力过半 / brk / 灵力不足 → 破防 CRUSH（吃 60%，1.35×0.7 秒） | 护体滑退 GSLIDE | `press_guard` :901，`receive_attack` :3412-3469，`_guard_hit` :3472，`_crush` :2552 |
| K/Shift 卡在对手判定前 0.22 秒 | 瞬身到对手背后（耗 8，连续窗口 ×0.78 缩，最低 0.1），之后 0.9 秒内 J = 瞬身反击 ctr 1.6（破防击飞）、E/Z = 贴脸九剑（耗 10%，1.4） | | `try_vanish_press` :2464，`_vanish_counter` :3536，`_start_counter` :1173，`_counter_blast` :2409 |
| 硬直中 K | 挣脱：耗 1 格罡气（上限 2，14 秒回一格），震开 6.5 m 内的人 | | `_burst` :2486 |
| 被打飞中 Shift | 受身 | | `on_blink` :3144 |
| Shift 短按 | 闪现（realm blink 8 m，速度 60~110） | 冷却 +0.18 | `player.blink` :803 |
| Shift 按住 + 有目标 | 御风突进 DASH 78 m/s（耗 9/秒），途中 J = 破空蹬 dash 1.1 | | `_dash_wanted` :1539，`_start_dash` :1564，`_dash_arrive` :1630 |
| E 点按 | 飞剑点射 0.4（耗 3，冷却 0.16） | | `press_shot` :961 |
| E 按住 ≥0.28 秒 | 万剑连发：每秒 realm volley 6~100 柄，每柄 `CS.volley_k`（≈每秒 6 单位 × 1.1^(境界−2)），耗 30/秒；对着也在连发的对手 → 飞剑对波（CLASH，连点 J 顶交汇点，输方吃固定 28） | | `air_caster._tick_channel` :244，`air_melee._tick_clash` :4076（:4255） |
| Z | 「诀」三式剑诀轮放（式名按 `Realm.ARTS.stages`），耗 10/18/32% 灵力，三式共用冷却 1.2/3.5/8 秒；目标伤害 2/3/6 × `skill_g` × `SKILL_K` | | `press_art` :1011，`press_skill` :1024，`air_caster._do_cast` :539（按法相档位分派 `_cast_core/_thunder/_fire/_five/_rift/_heaven`） |
| V 按住 / K 按住 0.7 秒无人打 | 聚气：回 45 灵力/秒、觉醒槽 +7/秒；槽满且灵力 ≥60% 继续聚 = 觉醒 14 秒（伤害 ×1.3、追击/近身免灵力、对波 ×1.3，震开 7 m 内对手 0.5） | 槽来源：命中 +2.5、挨打 +8 | `_tick_gather` :4260，`_awaken` :4278，`AWAKE_*` :89-90 |
| 两边轻拳同时 | 拳劲对拼 BRAWL（连点 J，输方吃 14） | | `receive_attack` :3430-3434，`_start_brawl` :1844 |
| R | 大罡剑阵（仅大乘 art 6，耗 50%） | | `gate_array.gd:97-108` |
| F | 转光遁赶路 | | `player._air_to_fly` :753 |

### 1.3 境界怎么改变这些招式
- **能不能空战**：`is_light_mode()`（`player.gd:238`）= 结丹起；`take_air` :709、`enter_air_combat` :726、`_fly` 里空格切空战 :1168 都看它。
- **伤害**：`_base()` 取 `Realm.LIST.dmg` 8/12/18/26/38/52/75/110（`realm.gd:24-80`）；地面 `CS.ground_k`；剑诀 `CS.skill_k`；连发 `volley_k`；飞剑阵 `q_k`。
- **招式花样（flair = 境界−2，:737）**：元婴每下拖残影；化神第 4 下瞬步绕背 + 剑气弧；炼虚追身变缩地 + 1 道分身；合体每下瞬步 + 2 分身 + 空间裂隙 + 乱舞 4 下；大乘 3 分身 + 乱舞 7 下 + 收尾剑雨（`_start_move` :1340-1356，`_fx_hit` :3236-3275，`_phantoms` :3283，`_sword_rain`）。
- **表现档** `Realm.COMBAT`（`realm.gd:119-136`）：fx/burst/kb/stop/shake/对波出剑数，经 `_prof()` :742、`_kbm()` :747 乘到击飞速度、顿帧、震屏。
- **剑诀 / 连发队形**整套随法相档 `Realm.ARTS`（`realm.gd:87-102`）。对波技巧 +6%/flair（`_clash_power` :3999）。
- **移动**：地面速度 6+0.6r（:1076）、跳 8.5+1.2r（:1127）、飞行速度 / 升限 / 起飞高度 / 闪现距离都来自 `Realm.LIST`。
- **灵力池** `CS.mp_max(realm)` 90~130；**PvP** 每高一境出手 ×1.08（`CS.pvp_hit` :227）。
- 外观 `hero.set_look(realm_idx)`（`player.gd:365`，皮肤模型下只影响方块人模式）。

---

## 2. 地面 ↔ 空中状态机（Player.St）

- `GROUND`（:1073 `_ground`）：WASD 走，Space：结丹起 → `take_air()` 进 `AIR`（向上托起 `AIR_RISE_V 15`，:718）；低境界 → `jump()`，空中再按 Space → `toggle_flight()`（:1105-1109，即「炼气也能飞」）。F → `TAKEOFF`。
- `TAKEOFF`（:1137）：0.5~0.55 秒线性上冲 `realm.rise` 米 → `FLY`；结丹起到顶自动放三段冲刺第一段（`_surge_fire` :761）。
- `FLY`（:1167）：方向全跟镜头（含俯仰），速度 `realm.speed`，炼气/筑基有升限 25/80 米（`ceiling`）；结丹起 Space → `_fly_to_air()`（:746）进 `AIR`；F → 结丹起高于 1.2 米走 `DIVE` 砸地，否则直接回 `GROUND`（:618-624）。**FLY 中按攻击**：结丹起 → `enter_air_combat`；低境界什么都不出（`player_melee.press_attack` :348）。
- `AIR`（:1213）：招式接管位移时用 `air.drive_vel`；否则悬停飞行 `AIR_SPEED 11`（Shift 按住 ×1.8）；**往下碰到地面 / 平台顶面（vy≤0.5 且不在起升段）→ `_land()` 回 `GROUND`**（:1243-1244, :787）；F → `_air_to_fly()`。
- `DIVE`（:658）：光剑急坠 → `_slam()` 回 `GROUND`（蹲伏 0.26 秒锁移动）。
- 结论：结丹起的主角**在地上只有移动**，一按攻 / 御就进 `AIR`；`AIR` 里贴着地打和空中打是同一套。受击路由：`raid_mob.gd:831-833`、`air_foe.gd:392-393`、`raid_manager.net_take_hit` :919-932 都按 `player.st` 分 `melee.receive_attack`（GROUND）/ `air.receive_attack`（AIR）/ 直接扣血（TAKEOFF/FLY/DIVE）。

---

## 3. 气血 / 伤害模型 / PvP

- **气血条恒为 0~100**（`player_melee.HP_MAX` :24；CS 注释 :9-10 说明联机同步和几十处自检都按 100 写，别改）。真实「气血数」只在显示层（`CS.hp(lv)`、`to_bar`）。空战脱战 6 秒后每秒回 6（:2663-2664）；大世界地面脱战回 `CS.CALM_REGEN 4`。
- **灵力** `player.mp`，内部单位，回复 `MP_REGEN 16 × mp_regen_k`（满池 6.25 秒，`air_caster._tick_mana` :205-214），用过后延迟 0.8 秒；界面显示要过 `CS.mp_shown`。
- **对怪**：招式原始伤害（单位 × base）进 `raid_mob.air_hit` → `dmg_in` = `raid_manager.player_dmg_vs` → `CS.raid_hit`（:115：先除 base(境界)、再 × atk(lv) × 法宝攻 × 防御系数）。怪打主角 `CS.to_bar`。
- **PvP（大世界）**：攻方 `raid_manager.net_deal_hit`（:886-894）`CS.pvp_hit = 原始/base(我) × PVP_UNIT 9 × 1.08^境界差 × (1+攻≤30%)` → 发「对方条上的点数」；受方 `net_take_hit`（:897-932）过 `_pvp_clamp`（单下 22 / 余量 30 / 之后每秒 25，`CS.PVP_*` :247-249，乘 `pvp_cap_k`）→ `pvp_guard`（守≤30%）→ 按 st 走正常受击（能挡、能瞬身）。擂台另一套 `arena_duel.gd:680-718` + `CS.ARENA_*`（单位 2.4，封顶 14/26/13）。
- **真人对打规则**（只对 `_pvp(t)` = 对方有 `pvp_peer()` 的木偶生效，`air_melee.gd:544`；数在 `air_moves.gd:161-199`）：
  - 连段上限：受方自己数拍（0.15 秒一拍），前 5 拍硬直不衰减、之后 −12%（≥0.4）；击飞时长按第几次被打飞 ×1/0.8/0.6；12 拍 / 3.2 秒 / 第 3 次被打飞 → 0.22 秒后自动脱身（`_pvp_took` :614，`_pvp_escape` :643）。
  - 起身保护 `_prot` 1 秒（被打飞落定 / 受身 / 起身 / 挣脱 / 脱身后，4 秒内被真人打过才给，`_protect` :663）；拳脚判定那一刻才结束（`_resolve` :3181 `_prot_end`）；打在保护上算打空，罚收招 0.35 秒（:3204-3207）。
  - 近身代价：冲 5 / 缩地 10 / 蓄力飞 6 灵力，不够就原地挥空（`_rooted`）；起手前摇不足 0.3 秒的用 `f_chg` 架势补足（`_open_take` :600，`_tick_attack` :2925-2940）；对面木偶 `time_to_hit()` 让瞬身对真人生效。
  - 对照开关 `AirMelee.pvp_legacy`（:145）/ `RemotePlayer.pvp_rules`。
- 硬直：轻击 0.34 秒、重击击飞 0.75 秒 × 衰减（`_hurt` :3623-3634）；对 AI 用 `Moves.stun_scale` / `dmg_scale`。
- **按境界缩放的**：base 伤害、灵力池、flair 花样、COMBAT 表现档、PvP 1.08^差、对波技巧、移动/飞行/闪现、剑诀/连发形态、Q 剑数、R 是否可用。**不随境界的**：气血条 100、招式单位表、所有固定灵力消耗（按 100 单位配，各境界同百分比）、PvP 封顶。

---

## 4. 联机同步（net.gd + remote_player.gd）

- **状态包** `_state`（unreliable_ordered，15 Hz，`net.gd:466-474, 488-497`）：位置、朝向、`int(player.st)`、realm、`melee.hp`、**`rig.last_name` + `rig.play_n`**（最近播的姿势名和次数）、等级、速度、flags（位0 连发中 / 位1 对波中 / 位2 渡劫 / 位3 正被打飞 `air.pvp_flags()`）。
- **木偶** `remote_player.gd`：`push_state`（:128-154）插值位置，`pose_n` 变了且 `Poses.SEQ.has(pose)` 才 `rig.play(pose)` —— **动画同步 = 姿势名同步**，收方必须有同名时间轴。模型写死 `HeroSkin.player_key()`（:61），兵器是空 `Node3D`（:63）——**木偶手里没有剑**。`st` 只用来判 grounded/flying（:167-168）。
- **命中**：本机打到木偶 → `air_hit / receive_hit`（:403-411，后者加 `ranged`）→ `_send`（:382-399：队友 / 保护中返回 -1；launch 只认 fwd/up/down）→ `raid.net_deal_hit` → `net.send_hit` → 可靠 RPC `_hit(dmg, dir, kb, heavy, launch, ranged)`（:799-812）→ 对方 `raid.net_take_hit` 按他自己的状态结算。**只传这 6 个字段**：stun、brk、gd、rear、unblockable、招式名都丢了；**结果不回传**（被挡 / 被瞬身攻方看不到，木偶永远返回 0 = 打中）。
- **飞剑 / 法术**：`spell_projectile.launch` 末尾 `net_sink`（:164-165，`net.gd:86` 挂 `_on_proj`）→ `_proj` 不带 dmg（:526-550），别人那边只画不结算；伤害由攻方命中木偶时走上面那条。每秒上限 40 柄。
- **战斗事件** `player.melee.combat_event`（信号在 `player_melee.gd:13`，空战也借它 emit）→ `net._on_combat_event`（:556-563）：`FX_KINDS` 12 种转成 `_fx(kind, pos, heavy)` 让别人画特效（:567-605；`air_awaken` 会让木偶起觉醒描边 14 秒）；`air_protect / air_opener` 走可靠 RPC `_pvp(op, v, pos)`（:608-637）。
- **对波**：`send_clash` op 0 开始 / 1 推力（unreliable 0.08 秒）/ 2 结果 / 3 预警（:690-723），木偶侧 `clash_begin / net_clash_push / net_clash_end / on_volley_incoming`（`remote_player.gd:248-298`）。
- **握手** `_hello(nick, size, realm)`（`net.gd:299-304`）→ `players[id] = {name, team, size, realm}` → `_roster`。**没有协议版本号**，新旧包混连会乱（pvp-fight-rules 记录）。
- 木偶缺的接口：没有 `brawl_begin / grab_by`（对真人不触发拳劲对拼、擒拿），`is_broken` 恒 false。

---

## 5. 英雄抽象：最小扰动的落地方案

### 5.1 原则
1. **AirMelee 对象不能换掉**：air_foe.gd 直接调 `player.air.*` 二十多个方法（`start_brawl` :691、`receive_parry` :769、`safe_spot` :922、`clash_warn` :971、`grab_hold/thrown` :1487-1491、`charging_at/rushing_at/is_open/attacking` :1454-1793 …），HUD / 触屏 / 木偶也读它。英雄差异做成「AirMelee 里的一张表 + 一个技能脚本」，状态机和攻防规则（护体、瞬身、挣脱、受身、真人对打）作为 TSB 的**通用底盘**共用。
2. **不加新的 `A` 状态**，新英雄的招式全部落在已有的 ATTACK / SMASH / DASH / GUARD / CHARGE 上（这些状态被几十处 `state == A.X` 判定引用，加状态要逐个补）。
3. 新姿势名一律进 `combat_poses.gd` 的 `DEF/SEQ`（:15、:318），联机木偶才播得出来。

### 5.2 HeroDef 放在哪
新建 `scripts/hero_defs.gd`（`extends RefCounted`，无 class_name，`const HEROES := {...}`），每项：
```
"xiuxian": {"name":"…", "skin":"aladeng", "base":18.0, "mp":100.0, "hp":100.0,
            "blink":8.0, "blink_spd":60.0, "fly_speed":45.0, "air_ok":true,
            "tier":2 (固定的 Realm.COMBAT/ARTS 档), "flair":0,
            "chain":["l1".."l5"], "moves":{} (覆盖/新增的 MOVES), "smash":{}, 
            "kit":"res://scripts/kit_xiuxian.gd", "blade":"fist"|"sword",
            "touch":{"s1":"剑","s2":"诀",...}}
```
注入点（按调用顺序）：
- `player.gd`：新增 `var hero_id / hero_def`；`_build_body` 的 `VoxelHero.new(..., HeroSkin.player_key())`（:311）改读 `hero_def.skin`；`mp_max()`（:209）、`is_light_mode()`（:238）、`blink()` 里的 `realm["blink"]`（:804, :824）、`_ground` 速度（:1076）、`jump`（:1127）、`_fly` 的 `realm.speed/ceiling`（:1176-1205）改读 hero_def；`set_realm` 不再被战斗调用（或只保留视觉）。
- `air_melee.gd`：`const ATK := Moves.CHAIN`（:99）改 `var ATK: Array`；新增 `func _mv(id) -> Dictionary`（hero.moves 优先、退回 `Moves.MOVES`），替换 `_start_move` :1309、`_begin_combo` :1096、`_next_id` :885、`_start_juggle` :1151、`_start_rush` :1214 里对 `Moves.MOVES[...]` 的直接索引；`_base()`（:522）改 `hero.base × 觉醒`；`flair()`（:737）改 `hero.flair`；`_prof()`（:742）改 `Realm.combat(hero.tier)`；`skill_name/skill_cost`（:499-505）走 kit。
- `air_caster.gd`：`_art()`（:83）、`realm["dmg"]`（:466, :557…）、`realm["volley"]`（:264）改读固定档，老角色剑诀固定成一个法相（建议结丹「金丹剑气」或元婴「紫霄雷法」）。
- `combat_stats.gd`：`base(realm)`（:50）改返回英雄常数，`raid_hit/pvp_hit` 的「除以 base」自然对齐；`pvp_hit` 的境界差项传同一值或删掉 `PVP_REALM_ADV`；`mp_max` 改英雄值；`ground_k` 返回 1。
- `remote_player.gd`：`_ready` 的皮肤（:61）和 `Rig` 兵器（:63）按对方 hero_id 建（剑修木偶要真剑模型 + `tip`）；hero_id 从 `players[id]`（`net._hello` 加第 4 个参数）读，**不必进 15 Hz 状态包**。
- `touch_controls.gd`：`BUTTONS` 的 shot/art 改为通用 `s1/s2/s3/s4`，字从 `player.hero_def.touch` 取；`hud.gd:498-524` 的技能框同理。

### 5.3 共享底盘（TSB 基础套）↔ 现有实现
| TSB | 现有可直接复用 |
|---|---|
| M1 连段 | `_begin_combo/_start_move/_tick_attack/_resolve` + `ATK` 表（改成英雄自带的 4 段） |
| Dash（前 / 侧） | 御风突进 DASH（摇杆左右切弧线，:1606-1612）+ 闪现 `player.blink` |
| Block | 护体 GUARD（`receive_attack` :3445-3468，滑退 `_guard_hit`） |
| Evasive / 解连 | 挣脱 `_burst`（罡气 2 格）+ 受身 `on_blink` + PvP 自动脱身 |
| 觉醒条 | `awaken/awake_t/_awaken/AwakenFx`（命中、挨打、聚气攒） |
| 下砸 / 上挑派生 | `_next_id` 的 d_up/d_dn/d_fl |

英雄独有的只剩「4 个技能槽 + 觉醒形态 + M1 表 + 模型/兵器」，由 kit 脚本实现。

### 5.4 硬编码了老角色招式的地方（要么搬进 kit_xiuxian，要么按 hero 开关）
- `air_melee.gd`：`press_shot`（:961，E 点射）、`press_art/press_skill`（:1011-1050 → `caster.cast_skill`）、`_counter_blast`（九柄飞剑，:2409）、`_sword_follow`（拳后飞剑，:3353；由招式 `swords` 字段驱动，新英雄填 0 即关）、`_start_rain`、`_sword_rain`、`_phantoms`、`_try_swat`、`_start_counter` 固定出 `ctr`、`_dash_arrive` 固定出 `dash`（:1635）、`_start_move` 里按 flair 的瞬步角度表（:1342-1356）、`_limb_pos`（:3166，"sw" 走剑身点）、`_end_blade` / `air_blade`（拳脚英雄只在 l5 亮剑）。
- `_unhandled_input`（:761-783）：`air_shot`→`press_shot`、`skill_next`→`press_art` 写死。
- `air_caster.gd` 全部：剑诀和连发按法相档分派，连发是对波的入口（`_tick_channel` :244-265 里 `start_clash`）。
- `player_melee.gd`：地面三段刀 + 处决；`player.gd` 的 R 大罡剑阵（:558-559、`can_ult` :256）。
- `touch_controls.gd` 的换字逻辑（:462-512）。

### 5.5 剑修第二英雄怎么拼（复用为主）
- **M1 四连**：新招 `k1~k4`（`limb:"sw"`、reach 稍长、`swords:0`），k4 `launch:"fwd"`；姿势可从地面刀招 `a1/a2/a3` 和空战 `f5` 改出 `fk1~fk4` 加进 `combat_poses`。剑全程在手：kit 加 `blade_always`，让 `_end_blade`（:3111）对它不收剑、`_tick_attack` :2972 的收剑跳过。命中点自动走 `rig.blade_point(0.7)`。
- **突进斩（Dash-slash）**：技能槽调用 `_start_dash(target,false)` 并预置 `_dash_atk = true`，`_dash_arrive` 出 `hero.dash_move`（新招 `k_dash`）；或近距离直接 `_flash_step(0)` + `_start_move("k_dash")`（记得 `_note_swap()`，并在 PvP 走 `_pvp_pay` + `_open_begin`）。
- **格挡反击（Parry/Counter）**：复用「GUARD 刚按下的窗口」判定（`receive_attack` :3438 的 `_clock - _guard_at <= vanish_window`）——剑修把 `_vanish_counter` 换成「原地弹刀」：调对方 `receive_parry`/硬直、自己开 `_counter_until`，下一下 J 出 `k_ctr`。**对真人无效**：攻方看不到结果（见 §6），要新加一个 RPC「你被我弹开了」。
- **剑气波（Sword-wave）**：`Proj.launch(player, Proj.K.SWORD, …, {"scale":3, "light":true, "straight":true, "dmg":base×单位})`，或加 `Proj.K` 新种类 + `Vfx.crescent` 外观；走 `receive_hit` 自动带 `ranged=true`，护体能拨（`_swat`），不会触发对波（只有连发置 flags 位0）。
- **觉醒形态**：沿用 `_awaken`；kit 的 `on_awaken()` 换一张觉醒 M1 表（`ATK = hero.chain_awake`）、加长 reach / 剑身发光，`awake_t` 结束换回。

### 5.6 让境界不再缩放战斗（扁平数值），保留空战
1. `is_light_mode()` 恒 true（或 `hero.air_ok`）：所有英雄一开局就有空战、光遁、闪现 8 米；地面刀剑（player_melee 的出招部分）实际不再触发，只保留它的 `hp`、`receive_attack`（站地上挨打的路由）和 `combat_event` 信号。
2. 固定一个表现档：`_prof()` 用 `Realm.COMBAT[2]`（结丹 = 1.0 基准，用户认可过的观感下限），`flair()` 返回 hero 值（老角色建议 1~2，保留残影 / 绕背但不要分身乱舞，否则对新英雄不公平）。
3. `_base()`、`CS.base`、`mp_max`、`volley`、`SKILL_K` 全部按英雄常数；`CS.pvp_hit` 去掉境界差（`PVP_REALM_ADV` 设 1 或差恒 0）。PvP 封顶 22/30/25 可保留。
4. `net._state` 里的 realm 字段可以留着发固定值（木偶 `qi` 颜色和觉醒描边用 realm 取色，`remote_player.gd:137-141, 105`），避免改协议签名。
5. 平衡建议：老角色 = 「拳脚 + 飞剑法修」，强在远程（连发 / 剑诀 / 对波）、近战单位偏低；剑修 = 纯近战，M1 单位更高（如 0.55/0.55/0.7/1.2）、reach +0.4、无飞剑随击、灵力只给技能用。老角色在 PvP 里把连发每柄伤害再压一档（连发是大世界 PvP 被吐槽最狠的「乱按秒人」来源之一），剑气波 / 点射都只给轻硬直。

---

## 6. 风险

1. **巨型文件 + 多会话并改**：air_melee 4371 行、air_foe 2044 行、main.gd 6000+ 行；工作区有大量他人未提交改动（git status 60+ 个 M）。改前先查是否有人在动（memory: concurrent-writers-check）。
2. **攻守都挂在 player 子节点上**：`player.melee.hp` 外部 93 处、`player.melee.combat_event` 是全局战斗事件总线（net、HUD、自检都监听），不能拆走；`Player` 有 class_name、大量 `var player: Player` 类型标注。
3. **AI 共用招式表**：air_foe 直接读 `Moves.MOVES / Moves.CHAIN`（:1842）和全局常数；改 `air_moves.gd` 会同时改 AI 手感。新英雄的招式放 hero 表，不要改 `MOVES` 里的老条目。
4. **木偶假设**：一律阿拉灯皮肤、无兵器（`remote_player.gd:61-63`）；动画只靠姿势名（新姿势名缺失就静默不播）；命中包只有 6 个字段、无结果回传（弹反 / 招架 / 破防 / 擒拿 / 对拼对真人不生效，这是 pvp-fight-rules 记的「第 4 项没做」）；`is_launched` 靠 0.3 秒本机预测。剑修的「招架反击」在 PvP 下必须补协议（建议在 `_hit` 后回一个 `_hit_ack(result)`），**改协议 = 局域网所有人换包**。
5. **飞剑 / 剑气走 net_sink 只同步画面**，伤害只在攻方命中木偶时结算，受方本机的飞剑不判伤害：剑气波若要「受方躲开」的手感，需接受攻方判定。
6. **境界耦合面广**：`is_light_mode` 26 处、`realm_idx/realm[...]` 在 player/air_caster/air_melee 里六七十处，`Realm.art` 驱动剑诀 / 剑阵 / 大招 / 皮肤以外的装束；大量自检（fight_cam / fight_feat / spark-tiers / arena_selftest）靠 `set_realm(r)` 切档，扁平化后这些自检要重写或失效。
7. **镜头 / 演出规矩**：新瞬移招必须 `_note_swap()`（`duel_hold`）；普通技能不切镜头不慢动作（no-skill-camera-cuts）；冲击别用全屏闪屏。
8. **触屏**：按钮字体是子集字库，新技能名要补字；按钮位置是手机优先的固定偏移，第 4 个技能槽要重新排。
9. **顿帧 / 战斗时钟各机各的**（`Combat.cdt`），高频连段在真人身上本来就有缝；新英雄 M1 若更快，PvP 拍数规则（0.15 秒一拍）要复核。
10. **地面挨打的路由**：站在地上（st=GROUND）挨打走 `player_melee.receive_attack`（只狼式弹反 / 架势），和空中的护体 / 瞬身是两套规则；扁平化后「站地上 = 只能闪」，要么统一路由到 air 规则，要么接受这一点。
