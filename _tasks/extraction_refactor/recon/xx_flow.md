# 侦察报告：顶层流程与新关卡接入点（xx_flow）

> 只读调研，2026-11-24，基于工作区当前文件（含其他会话未提交的改动）。所有路径相对 `D:\GodotProjects\修仙游戏\scripts\`。

## 0 结论速览

- **没有 autoload**（`project.godot` 只有 `[application] / [display] / [rendering]` 三节）。全局状态靠两样东西：① 少数 `class_name`：`Player`、`CameraRig`、`Hud`、`TestHall`、`SwordManager`、`Vfx`、`Realm`、`MeshLib`、`EnemyDummy`、`FlyingSword`、`Trail3D`（如 `player.gd:1`、`hud.gd:1`、`test_hall.gd:1`）；② 各脚本的 `static var`，相当于单例（见第 5 节）。
- `main.gd` 是唯一的编排者：持久对象在 `_ready` 里一次建好；关卡只有一个槽 `var level: MeadowLevel`（`main.gd:75`，**类型写死**），`_enter_level(_id)` **不管传进来的 id**，永远 `MeadowLevel.new()`（`main.gd:806,853`）。
- 主城四道门由 `hub_hall.gd:70-75` 的 `GATES` 表定义，门 2、3 是 `"open": false`。主城只发信号 `gate_entered(i)`，去哪由 `main._on_hub_gate` 决定（`main.gd:987-993`）。要让门 2、3 接上新关卡，改动最少的路线是：**GATES 开门 + `_on_hub_gate` 分支 + LEVELS 加卡 + `_enter_level(id)` 按 id 选关卡类 + 记住从哪道门进的 + level 槽改成 Node3D + 新关卡实现一份「关卡契约」**（第 2 节）。
- 联机房间的广播里**没有地图 id**（`net.gd:131,138`），一键匹配会把在不同地图的人拼进同一间房，必须补上。

---

## 1 开机 → 主城 → 门 → 选关 → 进图 → 结算 → 回主城

### 1.1 开机 `main._ready`（`main.gd:99-315`）
1. 读命令行 `OS.get_cmdline_user_args()`，设一串布尔开关（`_autotest / _combat_demo / … / _raid_demo`，`main.gd:100-111`）；`_touch = --touch 或触屏`、`_mobile = _touch 或网页`（`:112-113`）；手机档 `_apply_mobile_tier()`（`:114-115, 408-417`）；`_warm` 预热开关（`:117-118`）；`_setup_input()` 运行时注册所有按键动作（`:119, 582-613`）。
2. 建 `AudioDirector`（`:122-125`）；字体：Windows 用 SystemFont（楷体），其他平台用随包字体 `UiStyle.kai()`（`:126-134`）。
3. 持久对象（只建一次）：`HallRoot` + `TestHall`（老灰色大厅，`:136-141`）、`Vfx` 根节点（`:143-146`）、`CameraRig`（`:148-153`）、`Player`（`:155-160`）、`SwordManager`（`:165-167`）。
4. `legacy`（任一老演示 / `--raid-shot` / `--duel-shot` / `--net=`）时才在老大厅里放木人桩、刀客、空战对手（`:171-180`）；正常游玩放斗法台 `SparZone`（`:181-186`）。
5. 后处理层（`:187, 1052-1072`）、`Hud`（`:189-193`）、触屏层 `TouchControls`（只在 `_touch` 时建，`:194-202`）、`BossArena`（`:205-210`）、`LevelSelect`（`level_ui`，`:213-215`）、`Net`（`:216-223`，连 `room_closed → _on_room_closed`，`level_ui.picked → _enter_level`，`level_ui.closed → _on_menu_closed`）。
6. 一键服丹 `HallPills`（`:224-231`）。
7. 主城 `hub_hall.gd`：`(not legacy 或 --hub-shot) 且没有 --old-hall` 才建（`:234-243`），连 `gate_entered → _on_hub_gate`。
8. 老大厅里的宇宙之门 `hall_portal`（`:244-255`，有主城时题字「回主城」）。
9. 信号：`realm_changed → _on_realm_changed`、`realm_ascended → hud.realm_up`、`melee.combat_event → _on_combat_event`（`:257-260`）。境界从存档读 `Profile.boot_realm()`（`:262`）。有主城就 `_place_in_hub(hub.spawn_point(), 0)`（`:263-264`）。
10. 分派自检 / 演示（`:265-302`，见第 4 节）；正常游玩若 `_warm` 走 `_boot_warm()`（`:301-302, 430-439`：黑幕后 `Warm.run(…"hall"…)`）。

### 1.2 持久对象 与 每局对象

| 持久（main 一次建，整局复用） | 每局（进图时建，`level.queue_free()` 一并销毁） |
|---|---|
| Player、CameraRig、SwordManager、Hud、TouchControls、LevelSelect（含黑场 / 载入字）、Net、AudioDirector、HallPills、Hub（含 Farm、ArenaDuel、LanPresence）、TestHall/BossArena/SparZone/HallPortal、后处理层 | `MeadowLevel`（`main.gd:853-862`）→ 搜打撤模式 `_ready_block`（`meadow_level.gd:218-274`）：WorldEnvironment、太阳、`BlockWorld`、脚下跟随地板 `_floor`、飘浮物 `motes`、题名石碑、F3 统计标签、`RaidManager`（`:266-274`）→ `_mob_root`、`InsightFx`、`Search`、`ShenShi`、`Camps`、`RaidHud`（`raid_manager.gd:223-301`；小地图在 RaidHud 里建，`raid_hud.gd:125`）、AI 道友（`AllyTeam`）、联机木偶（`net.enter_world`，`raid_manager.gd:244-245`，`net.gd:401-421`） |

注意：**Hud（主界面）不随关卡重建**，`hud.refresh(player, swords)` 每帧由 `main._process` 调（`main.gd:1087`），它硬依赖 `Player` 和 `SwordManager`。

### 1.3 主城 → 门 → 选关
- 主城每帧 `_process` 判门（`hub_hall.gd:1913-1931`）：人在石台上、贴着墙（`WALL_Z+0.5 < z < WALL_Z+5.2`）且 `|x - gate.x| < GATE_W/2-0.6` → `at`；`open == false` 只飘「此门尚未开启」（`:1925-1928`）；开着且 `_gate_armed` → `gate_entered.emit(at)`（`:1929-1931`）。`_gate_armed` 在离开门 7.5 米后重置（`:1921-1923`），`set_active(true)` 时先设成 false（`:245`）。
- `main._on_hub_gate(i)`（`main.gd:987-993`）：`i==0 → _open_level_select()`，`i==1 → _goto_test_hall()`；其他 i 什么都不做。
- `_open_level_select()`（`:744-748`）→ `level_ui.open()`（`level_select.gd:72-126`，**暂停整棵树**、放出鼠标、画 `LEVELS` 卡片）→ 点卡 `pick(i)`（`:144-152`）→ 入境页 `_show_modes()`（`:186-264`，选 1/2/4 人、洞府备战、「开始匹配」把 `mode="match"`）→ `_go()`（`:155-165`）取消暂停并 `picked.emit(LEVELS[_lv]["id"])`。`LEVELS` 现在只有一条 `id="mulan"`（`:11-15`）。

### 1.4 进图 `main._enter_level(_id)`（`main.gd:806-881`）
状态守卫 `_switching or level != null → return`；`_switching = true`。
1. 黑场 `level_ui.fade(1.0)`、载入字（字面写死「木兰草原」，`:812, 844, 870`，`_matchmake` 里也有 `:892, 920`）。
2. 联机：按 `level_ui.mode`（match / host / join / solo）处理房间；自己开的房还有人就回原房（`:816-824`）；`_matchmake()`（`:887-921`，网页版直接单人 `:890-893`）。
3. `player.force_ground()`、`swords.dismiss_all()`、主角停处理（`:846-848`）；`_set_hall_active(false)`（`:849, 769-787`：隐藏 / 停处理 / 关碰撞 / 敌人移出索敌分组）；`hub.set_active(false)`、`hud.lobby=false`（`:850-852`）。
4. `level = MeadowLevel.new()`，赋 `player / cam / font / raid_enabled / mobile / net`，连 `exit_requested → _return_to_hall`，`add_child`（`:853-862`）。
5. 放出生点：`level.spawn_point()`、`level.spawn_yaw()`、`cam.snap(...)`（`:863-866`）；`await level.prewarm()`（`:867`）；`_warm` 时 `Warm.run(…, "raid" if level.raid != null else "meadow", …, level.raid, [swords])`（`:868-870`）。
6. `hud.set_compact(level.raid != null)`、`touch.compact = …`（`:872-874`）；打印 `level.stats_text()`（`:875`）；恢复主角处理、淡入、`_switching=false`（`:876-881`）。

### 1.5 局内结束
- 撤离 / 陨落 / 困死：`raid_manager._finish(success)`（`raid_manager.gd:2869-2915`）：停怪、结算心得、`Profile.end_raid(...)`、`hud.show_result(...)`，**等 4.5 秒** → `level.exit_requested.emit()`。
- 房主关房：`net.room_closed(by_host)` → `main._on_room_closed`（`main.gd:754-760`）→ `raid.room_collapsed()`（按撤离成功结算，`raid_manager.gd:2817-2823`）或 `raid.room_lost()`（不算撤离，`:2828-2850`），两者最后都 emit `exit_requested`。
- 陨落：`_on_combat_event("player_dead")` → `_on_player_dead()`（`main.gd:538-541, 547-563`）。若 `level.raid.running` 就**不插手**（`:552-553`），交给 raid_manager；主城擂台对决中交给 arena_duel（`:550-551`）；其他关卡 1.3 秒后 `_return_to_hall()`（`:555-559`）；大厅里原地复活 `_respawn_in_hall()`（`:567-577`）。

### 1.6 回主城 / 拆关卡 `main._return_to_hall()`（`main.gd:924-962`）
守卫 `_switching or level == null`。黑场 → `force_ground`、死了就 `revive()` → `swords.dismiss_all()` → 主角停处理 → **`level.queue_free(); level = null`**（`:934-935`）→ 房主且房里还有人 `net.keep_room()`（`net.gd:339-356`，这一帧 raid 还活着，借它把地形 / 掉落记下来），否则 `net.leave()` → `hud.set_compact(false)`、`touch.compact=false` → 等一帧 → 有主城 `_place_in_hub(hub.return_point(0), PI)`（**门下标写死 0**，`:948`），否则回老大厅门前（`:949-957`）→ 恢复处理、淡入、`_switching=false`；房没散时 `hub.say(...)`（`:961-962`）。
- 关卡自己的收尾：`meadow_level._exit_tree()`（`meadow_level.gd:312-322`）还原 `Vfx.terrain_hook`、`cam.floor_fn`、`cam.cam.far`、景深参数、`player.ground_ref`、`player.bound = Player.BOUND`；`raid_manager._exit_tree()` 调 `net.leave_world()`（`raid_manager.gd:641-643`）。
- `_place_in_hub(pos, yaw)`（`main.gd:972-983`）：关老大厅、`hub.set_active(true)`（`hub_hall.gd:218-258`：挂回主城的环境 / 太阳、`cam.floor_fn = ground`、`cam.occl_fn = _cam_block_h`、首次进城结算离线闭关）、放人、`hud.lobby = true`、`hud.set_compact(true)`、`touch.compact = true`。
- 试剑台支线：`_goto_test_hall()`（`:1004-1024`）/ `_goto_hub()`（`:1027-1035`，落在 `return_point(1)`）。

关键状态变量：`_switching`（所有切换的互斥锁）、`_dying`、`level`、`hub.active`、`hub.area`、`hud.lobby / compact`、`touch.compact / blocked`、`level_ui.mode / team_size`。

---

## 2 主城的门怎么定义、门 2 / 3 怎么接新关卡

### 2.1 现状
- `GATES`（`hub_hall.gd:70-75`）：每项 `{x, name, sub, a, b, frame, open}`。`x` 是门心（-25.5 / -8.5 / 8.5 / 25.5）。`open` 影响：锁链和铜锁的几何（`_build_structures` `:703-707`）、门心着色器的 `locked`（`_build_gates` `:1062`）、门匾字 `name`（`_build_signs` `:1103-1104`）、触发逻辑（`:1925-1931`）。各门装饰按下标 `match gi`（`:686-702`，2 = 火 / 熔岩缝，3 = 云纹），开门后照样有。
- `return_point(i)`（`:273-274`）：门 i 前石台上的落点。
- 主城自检写死了期望：四道门只有 `[0, 1]` 触发（`:2095`），并且实走门 0 进出木兰草原（`:2235-2252`）。

### 2.2 建议的接法（每一处都只动几行）
1. **开门**：`GATES[2]`、`GATES[3]` 改 `"open": true`，`name/sub` 换成两张新地图名，并加一个字段 `"level": "desert"` / `"level": "lab"`（门 0 加 `"level": "mulan"`）。主城另加一个小函数 `gate_level(i) -> String`（hub_hall 不写 class_name，main 只能 `hub.call(...)` 拿常量，比 `hub.get_script().GATES` 清楚）。
2. **记住从哪道门进**：main 加 `var _gate_from := 0`；`_on_hub_gate(i)` 改成 `i == 1 → _goto_test_hall()`，否则 `_gate_from = i; _open_level_select(hub.call("gate_level", i))`。
3. **选关界面只显示这道门的那张图**：`LEVELS` 加两行（`id/title/tag/desc/art/sky/land`）；`level_select` 加 `open_level(id)`：`open()` 后直接 `pick(LEVELS 里的下标)` 进入境页（`raid_selftest.gd:81-83` 就是这么用 `open() + pick(0)` 的，可行）。`_go()` 已经 emit 正确的 id。
4. **`_enter_level(id)` 改成按 id 建关卡**：`main.gd:75` 的 `var level: MeadowLevel` 改成 `var level: Node3D`（否则赋别的脚本实例运行时报类型错）；加 `const LEVEL_TYPES := {"mulan": MeadowLevel, "meadow": MeadowLevel, "desert": preload(...), "lab": preload(...)}`（自检里叫 `"meadow"`，`main.gd:6119,6162,6167`）。`level.raid_enabled` 只对 MeadowLevel 设；载入字的「木兰草原」换成 `LEVELS` 的 title（`:812, 844, 870, 892, 920`）。
5. **回到对应的门**：`_return_to_hall` 里 `hub.call("return_point", 0)` 改成 `_gate_from`（`:948`）。
6. **联机按地图分房**（必须）：广播 `"XIUXIAN|名字|人数"`（`net.gd:131`）加第 4 段地图 id，解析处（`:136-138`）存进 `rooms[ip]`；`_matchmake` 选房时只挑同地图（`main.gd:903-907`）；`_enter_level` 里「回到自己开的房」（`:816-824`）要比对地图，不同就 `close_room()`；`_hello`（`net.gd:298-311`）可顺带校验地图，防直连 IP 加错。`net.seed_v` 等房间状态天然按房间走，没问题。
7. **新关卡要实现的「关卡契约」**（main 和其他脚本鸭子类型调用的全部东西）：
   - 信号 `exit_requested`；属性 `player / cam / font / mobile / net`、`raid`（玩法管理器，可为 null）。
   - 方法 `spawn_point() -> Vector3`、`spawn_yaw() -> float`、`prewarm() -> float`（await）、`stats_text() -> String`、`ground(x, z) -> float`（`main.gd:639, 863-875`；`raid_search.gd:126`；`raid_pace_test.gd`、`hitch_probe.gd:71` 也调）。
   - `raid` 上被外部读的：`running`（`main.gd:552`）、`hud.bag_open()`（`:1089`）、`gm_tribulation(to)`（`:657-658`）、`room_collapsed() / room_lost()`（`:756-758`）、`_in_trib / _boss_near / _mobs`（`audio_director.gd:186-189, _count_crowd`）、`net_on()`（`warmup.gd:245`）。
   - 若复用 `RaidManager`：它还要 `level.env / level.sun`（`raid_manager.gd:225-226`）、`level.world` 的 `apply_dug / crater_changes`（`:249-258`）、`world.mat`（`:1284`）、`level.motes`（`:1323`），开局题名写死「木兰草原」（`:290`），POI / 区域全来自静态的 `raid_data.gd`（`Data.pois()/REGIONS`，`:1373-1398`，raid_manager 里 24 处）。联机 `net.gd` 直接调 `raid.level.world.dug_table()`（`:308, 345`）、`raid.level.remote_blast()`、`raid.level.world.dig()`（`:665-667`）；小地图调 `mgr.level.world.map_cells(...)`（`minimap.gd:143-191`）；刷怪点 `raid_camps.gd:110`。所以要么新地图也给一个实现这些方法的 `world`（可以是空实现），要么把 raid_manager 的数据源（raid_data）参数化成「每张地图一份」。
   - `_exit_tree` 必须照 `meadow_level.gd:312-322` 还原镜头 / 主角 / `Vfx.terrain_hook`。
   - 世界不是循环的话，`player.bound` 设成地图半径（MeadowLevel 设 `1.0e9` 是因为循环世界，`meadow_level.gd:264`）。

### 2.3 为什么复用 `main.level` 这个槽
很多脚本把「`main.level != null`」当成「在关卡里」：洞府按钮隐藏（`hud.gd:170, 387`）、一键服丹隐藏（`hall_pills.gd:97`）、擂台不匹配（`arena_duel.gd:198`）、局域网在场显示「在禁地」（`lan_presence.gd:103`）、背景音乐切 explore/battle（`audio_director.gd:239-260`）。新关卡放进同一个槽，这些都自动生效；另开一个槽就得逐个改。

---

## 3 主城里和修炼 / 挂机相关的功能，以及怎么干净地关掉

| 功能 | 在哪 | 最干净的关法 |
|---|---|---|
| 修炼场打坐 + 渡劫突破 | 常量 `MED_POS/MED_R/SAVE_EVERY`（`hub_hall.gd:84-87`）；状态 `meditating…`（`:124-130`）；`_zone()` 返回 `"med"`（`:1454-1455`）；`use()` 的 med 分支（`:1478-1484`）；按钮字「闭关打坐 / 渡劫突破」（`:1893-1907`）；`start/stop/_tick_meditate`（`:1568-1700`）；`_start_break / _on_break_done`（`:1757-1825`，起 `Tribulation`、`player.set_realm(to)`）；物理里打坐时锁地板（`:1308-1310`） | 删掉 `_zone()` 里那两行 `"med"`，按钮就不会出现、`use()` 走不到打坐 / 渡劫；`set_active` 里的 `stop_meditate` 保护（`:219-220`）留着无害。场景件：阵台地块 `:368-369`、竹篱 / 符石 / 木人桩 `:787-829`、牌匾「修炼场」`:1102`、柱子 `:1119`、盘腿坐的路人（`:1129` 最后一项 `true`），想要地方就一起删，改名做别的功能点也行 |
| 离线闭关结算 | `set_active` 首次进城 `_settle_offline(Profile.take_boot_seen())`（`:246-249`）；手机切回前台（`:1525-1528`）；`_settle_offline`（`:1829-1841`，调 `Prog.settle_offline`） | 删 `:246-249` 和 `:1525-1528` 的结算调用；`NOTIFICATION_APPLICATION_PAUSED / WM_CLOSE_REQUEST` 里的 `Profile.save()` 留着（存档仍要落盘） |
| 一键服丹 `hall_pills.gd` | `main.gd:224-231` 建；自己注册 H 键 `eat_all`（`hall_pills.gd:89-93`）；没有别的脚本引用它（只有注释） | 删 `main.gd:224-231` 整块即可 |
| 灵田农场 | `_ready` 里 `_build_farm()`（`hub_hall.gd:184`，`:1937-1971` 建农场和两道透视门 `hub_portal.gd`）；用到它的地方都有 `farm == null` / `area == "farm"` 保护：`spawn_point :267`、`ground :1236`、`_solid_at :1249`、`use :1470`、`_process :1859-1871`、`_apply_area :1976`、`_check_portals :1994` | 注释掉 `:184` 一行（area 永远是 town，所有分支都走不到）。剩下的静态件：门前石路和门柱实心格 `:380-385`、牌坊门和石灯 `Farm.build_gate(...)` `:894-900`、门匾字 `:1105-1117`，不删会是一道「通向哪也不去」的门。存档里 `farm` 键（`raid_profile.gd:59`）留着无害；农场自检 `--farm-shot/--farm-plant`（`:2041-2046`）跟着失效 |
| 两侧擂台 1v1 | `hub_arena.gd` 只管形状（`Arena.layout/top_col/side_col/build/over`，接在 `hub_hall.gd:387, 453, 484, 902, 965`）；对决 `ArenaDuel`（`:186-194`，离城 `abort` `:221-222`，`duel_busy` `:262-263`，main 陨落让路 `main.gd:550-551`） | 这是 PvP，和搜打撤不冲突，**建议保留**当英雄试招台 |
| 升阶题字 | `realm_ascended → hud.realm_up`（`main.gd:258`，`hud.gd:199-200` → `realm_banner.gd`） | 去掉境界成长后这条自然不再触发；也可直接断掉 `main.gd:258` |
| GM 改境界 | `main._unhandled_input` 的 `[` `]` 和 1-8 数字键（`main.gd:633-649`）、`_gm_breakthrough`（`:654-667`，起 `Tribulation`）；触屏「境- / 境+」（`touch_controls.gd:44-45`，compact 时藏 `:150-151`；主城和关卡里都是 compact，只在试剑台露出来） | 正式 PvP 必须关：给 `_unhandled_input` 里这三支加 `if Profile.test_mode()` 或整段删 |
| 结婴演出 | `player._ascend_start()`：升到 `realm_idx == 3` 且有镜头时 `_start_yuan_cine()`（`player.gd:404-412, 433-454`）；开关 `_yuan_cine_ok()`（`:422-430`）。主城里的触发源：修炼场渡劫成功 `player.set_realm(to)`（`hub_hall.gd:1811`）、GM 渡劫（`main.gd:664-666`）；局内触发源在 raid_manager（`gm_tribulation :1008`，结婴播报 `:963` 起） | 一处关全部：`_yuan_cine_ok()` 开头直接 `return false`。`YuanCine.playing` 的检查（`hud.gd:187`、`hall_pills.gd:143`、`hub_hall.gd:1707`）不用改，恒为 null 即可 |
| 境界光环 | 觉醒特效里 `RealmHalo.enabled and …`（`awaken_fx.gd:64`），开关 `realm_halo.gd:42`（`--no-halo`） | 不是主城专属，是觉醒表现；TSB 的觉醒槽可以直接借用（每个英雄换一套光环）。不想要就把 `RealmHalo.enabled` 默认改成 false |
| 开机境界 | `main.gd:262` `player.set_realm(Profile.boot_realm(), false)` | 境界还驱动战斗档位（Realm.COMBAT），不能直接删；改成「英雄定档」时这里换成读英雄配置 |
| 洞府「丹房」页 | `abode_ui.gd:26` `TABS := ["储物", "坊市", "丹房"]`；主城 `open_abode(tab)`（`hub_hall.gd:1489-1500`）只开 0 / 1 | 从 `TABS` 去掉「丹房」（细节不在本报告范围，交给 abode / 经济那份报告） |

---

## 4 命令行自检开关的机制

- **怎么读**：一律 `OS.get_cmdline_user_args()`（`--` 后面的参数），`args.has("--x")` 或 `begins_with("--x=")` 再 `get_slice("=", 1)`（例：`main.gd:423-425`、`hub_hall.gd:2047-2051`）。全项目 32 个脚本各自读，没有统一的解析器。
- **怎么分派**（`main._ready`）：
  - 顶层开关（`:101-111`）决定 `legacy`（`:171-172`）；`legacy` 时**不建主城**（`:234`），直接从老大厅开始，所以 `--raid-shot` 自检是 `_run_raid_demo()` → `await _enter_level("meadow")` 直接进图（`:6106-6167`）。
  - `if / elif` 链（`:265-302`）：`--shot / --combat-shot / … / --net= / --duel-shot(+--trib / --touch-test) / --raid-shot / --trailer / --hub-shot / --audio-test / 正常预热`。
  - 子开关在各演示函数里再判：`_run_raid_demo` 里有 `--raid-econ / --raid-match / --raid-hitch / --raid-zoo / … / --raid-trib` 一长串（`:6110-6387`）；主城自检 `hub.selftest()` 里判 `--farm-shot / --farm-plant / --lan-test= / --arena-duel`（`hub_hall.gd:2041-2055`）。
  - 链外的「正常开机再挂探针」：`--hitch-probe`（`:303-305`）、`--qa-solid`（`:306-310`，`load("res://scripts/solid_selftest.gd").new()`，设 `m = self` 后 `add_child`）、`--hall-count`（`:311-315`）；`--qa-arena` 在 `arena_duel.gd:126` 里自己判。
  - 惯例：外置的自检脚本用 `load()` 不用 `preload`，写坏了不连累主流程（`main.gd:6241, 6246, 6251`，`hub_hall.gd:2050, 2054`）。
- **还要同步的几张「排除表」**：截图模式不抓鼠标（`main.gd:150`）、不预热（`:117-118`）、不放结婴过场（`player.gd:426-427`）。新开关如果走 `legacy` 路线，这三处都要加。
- **`Profile.test_mode()`**（`raid_profile.gd:44-48`）：只要有一个 `--` 参数不在 `PLAY_ARGS = ["--touch", "--warm", "--sliced", "--keep-profile"]`（`:36`）里，就算自检：存档改用 `user://xiuxian_profile_selftest.json`（`:19, 51-52`），每次开机清空（加 `--keep-profile` 保留）；`boot_realm()` 一律 0（`:291-292`）；搜打撤出生点固定在原点（`meadow_level.gd:142-143`）；固定刷怪点默认关、要 `--camps`（`raid_manager.gd:282`）。**以后加「正式游玩也会带」的参数，必须写进 PLAY_ARGS**，不然玩家的档会被换成测试档。
- **截图**：`main._shot(tag)`（`main.gd:1147-1156`）存 `res://_shots/<tag>.png` 和 800 宽的 `res://_shots/preview/<tag>.jpg`（只看 preview），存盘时 `Combat.hold = true` 冻结战斗时钟。
- **run_hidden**：`python _tasks/trailer/run_hidden.py <项目目录> <日志前缀> --resolution 1280x720 -- <参数>`（`_tasks/trailer/run_hidden.py:1-49`）：用 `Godot_v4.7.2-stable_win64_console.exe` 起一个真窗口，但隐藏、移到屏幕外（headless 只有 dummy 渲染器拍不到图），输出写 `<前缀>_out.txt / _err.txt`，20 分钟超时自动杀。要看手机网页那套渲染就再加 `--rendering-method gl_compatibility`。
- **给新关卡加自检的建议**：照 `--qa-solid` 的路子，不碰 `legacy` 和 if 链，只在 `main.gd:306` 附近加一段：见到 `--level-test=desert|lab` 就 `load("res://scripts/level_selftest.gd").new()`、设 `m`、`add_child`。探针自己：关 `cam.capture_mouse`（照 `solid_selftest.gd:26-29`）→ `level_ui.mode = "solo"` → `await m._enter_level(id)` → 跑检查 / 截图 → `m._return_to_hall()` → 等 `m.level == null` → `get_tree().quit()`。这样开机流程和正式游玩一样（主城会建），`test_mode` 自动生效；主城门的实走测试补进 `hub.selftest()`，同时把 `:2095` 的期望改成 `[0, 1, 2, 3]`。

---

## 5 坑

1. **伪单例（static var）**：`Vfx.root / font / terrain_hook / lights / lite`（`vfx.gd:18-29`；`terrain_hook` 由关卡设、`_exit_tree` 清，`meadow_level.gd:242, 313`）、`Sfx.root`（`sfx.gd:25`，`main.gd:120`）、`Combat` 的时钟 / 顿帧 / 慢动作（`combat.gd:11-25`，`main.gd:1084` 每帧 `Combat.tick`）、`Tribulation.running`（`tribulation.gd:31`）、`YuanCine.playing`（`yuanying_cine.gd:24`）、`Proj.net_sink`（`spell_projectile.gd:49`，`net.gd:86` 设）、存档 `Profile._d`（`raid_profile.gd:39`）、`CreatureModels.shadows`（关卡设，`meadow_level.gd:241`）、`MeadowLevel.solid_off / step_old`、`RealmHalo.enabled`、`Warm._envs / done`（`warmup.gd:40, 180`：每个 tag 只预热一次）。新关卡改了这些，退出时要还原。
2. **主角、镜头是两边共用的**：`cam.floor_fn / occl_fn` 主城 `set_active` 设 / 清（`hub_hall.gd:238-241, 255-258`），关卡自己设（`meadow_level.gd:263`）；`cam.cam.far`、景深（`:254-262`）；`player.bound`（默认 `Player.BOUND = 1150`，`player.gd:55, 96`；农场就是因为这个放在 `-760`，`hub_farm.gd:25`）、`player.ground_ref`。同一时刻只能有一套 WorldEnvironment / 太阳：主城关掉时摘掉自己的（`hub_hall.gd:251-254`），老大厅 `hall.set_env_active`（`main.gd:785`），关卡自己带（`meadow_level.gd:219-224`）。
3. **main 里对关卡的硬假设**：`level` 的类型（`:75`）；`_enter_level` 只建 MeadowLevel、读 `raid_enabled / prewarm / stats_text`（`:853-875`）；`level.raid.running`（`:552`）、`level.raid.hud.bag_open()`（`:1089`，raid 不为 null 就假定有 `hud`）、`level.raid.gm_tribulation`（`:657-658`）；`_return_to_hall` 的门下标 0（`:948`）；载入字「木兰草原」；Backspace 回 `level.spawn_point()`（`:639`）。
4. **raid_manager 和 MeadowLevel / BlockWorld 绑得很紧**（见 2.2 第 7 条）；联机 `net.keep_room()` 也假定 `raid.level.world.dug_table()`（`net.gd:345`）。
5. **网页 / 手机分支**：`_mobile = 触屏 或 网页`（`main.gd:113`）；手机档 3D 按 720 线出、无 MSAA、阴影降档、`Vfx.lights = false`、`Vfx.lite = true`（`:408-417`）；后处理手机拆两层（`:1057-1066, 1117-1122`）；网页是兼容渲染器（`project.godot` 里 `renderer/rendering_method.web="gl_compatibility"`），带影子的主光要乘 0.11（`hub_hall.gd:1216, 1949`；`raid_manager.gd:219, 1259`），顶点色走 `MeshLib.vcol`（`mesh_lib.gd:18`）；网页没有局域网（`main.gd:890-893`、`lan_presence.gd:56`、`arena_duel.gd:132`）；网页单线程，地块要切片、黑屏载入时放开算（`meadow_level.gd:328-332`）；手机 / 网页默认开预热（`main.gd:117`），新地图要给 `Warm.run` 一个自己的 tag 或复用 `"raid"`；兼容渲染器每个 2D 画布占合批缓冲，已压到 2048 项（`project.godot` 的 `gl_compatibility/item_buffer_size`），牌匾统一字号 `PLAQUE_FS`（`hub_hall.gd:1071-1074`）。
6. **暂停**：选关和洞府界面会 `get_tree().paused = true`（`level_select.gd:75`、`hud.gd:176`）；黑场 / 载入层 `PROCESS_MODE_ALWAYS`（`level_select.gd:38`）、`net`（`net.gd:81`）、触屏层（`touch_controls.gd:102`）也是。新界面 / 新管理器要想清楚暂停时跑不跑。
7. **输入动作是运行时注册的**：`main._setup_input()`（`:582-613`），主城另加 T（`hub_hall.gd:179-183`），服丹加 H（`hall_pills.gd:89-93`）。新英雄的按键加在 `_setup_input`；触屏按钮表在 `touch_controls.gd:35-46`（一行一个按钮，按场合显示 `_btn_on` `:137-161`）。
8. **所有切换都要守 `_switching`**，并用 `level_ui.fade()` 黑场；`_on_player_dead` 也看 `_switching`（`:548`）。
9. **主城的门要「先走开再回来」才再触发**（`_gate_armed`）；从关卡回来正好落在门前（`return_point`），不会立刻又进门。
10. **GM 境界键在关卡里也有效**（`main.gd:633-649`），PvP 版必须收掉。
11. 主城 `hub_hall.gd` 和 `hub_arena.gd` 互相不能 preload（`hub_arena.gd:16` 注释），新增主城子模块照擂台的写法：`static func` + 不标类型的 `hub` 参数。
