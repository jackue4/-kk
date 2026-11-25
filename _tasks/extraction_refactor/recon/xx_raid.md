# 搜打撤现状摸底：raid_manager 一套能给两张新图用多少（xx_raid）

只读调研，读的是工作区当前版本（含别的会话没提交的改动）。行号均指 `scripts/` 下文件。

---

## 0. 一句话结论

- `raid_manager.gd`（3004 行）是「循环大世界 + 修仙养成 + 搜打撤」三层揉在一起的单体；纯搜打撤的部分大约一半，但几乎每个函数都夹着 `Prog` / 境界 / 心得 / `Data.near` / 区域下标 0~4。
- 真正干净、可以原样搬走的是**外围组件**：`raid_mob.gd`（怪，数值全靠注入）、`raid_pickup.gd`（地上掉落）、`ally_team.gd` / `ally_brain.gd` / `ally_puppet.gd`（AI 道友）、`air_foe.gd`（AI 修士）、`raid_hud.gd` 的背包 / 拾取卡 / 读条 / 结算部分、`net.gd` 的整套怪 / 掉落 / 命中协议。
- **建议新写一个 `extract_manager.gd`**，照 `arena_duel.gd` 的先例实现 net.gd 认的那组鸭子类型接口，把 raid_manager 里不带养成的函数近乎逐字搬过去，修仙相关的全部不搬；`raid_camps.gd` / `raid_search.gd` 留状态机、换掉布局和出货（薄适配）。理由见第 3 节。
- **最大的坑**：怪（`raid_mob.gd`）没有任何墙体碰撞，只靠 `floor_fn(x,z)` 单值高度贴地（raid_mob.gd:1018-1032）。DarkArea 的研究所是室内多层建筑，怪会穿墙、上不了楼——新关卡必须给怪补移动约束（导航 / 按格子挡路），这是复用怪 AI 前要先解决的。

---

## 1. 组件清单

每项写：在哪（文件:函数）、输入、和修仙的耦合、和循环大世界的耦合。

### 1.1 刷怪：固定刷怪点 + 老导演

- **固定刷怪点** `raid_camps.gd`（RefCounted，`Camps.new(self)`，raid_manager.gd:281-282）
  - 布局 `_layout(cxw,czw,id)`（raid_camps.gd:88-149）：32 米一格、`N=108 = LOOP/CELL`，按哈希 `_h` 抖点；区域概率 `P[ri]`；避开 `Data.pois()`、`mgr.search.sites`；地面校验调 `mgr.level.world._shaped()`（block_world 私有函数）。出货：`Data.REGIONS[ri]["mobs"]`，小怪 3~5 只、巨汉 1~2 只、一成精英带两只随从。
  - 状态（这部分通用）：`_dead{id:{slot:死亡时刻}}`，复活 `RESPAWN=75s`（按 `mgr.world_t()` 房间时钟），`alive()` / `on_dead()`（:159-185）；加载 / 回收 `tick(p, blocked)`（:221-299，MAT_R=100、FREE_R=150、急飞不建）；每帧建 `frame()`（:432-446，手机一帧 1 只）；`_build()`（:449-509）调 `mgr._spawn_mob()`，记 `meta camp = id*8+slot`。
  - 联机：一个点只由一人建——`_owned_by_other` / `_lower_peer_near`（编号小的建，:363-379）；撞车 `saw()` 让出刚建的（:193-201）；交接时接木偶的血量位置（:455-482）。死亡广播借 `send_mob_dead` 的 `lair` 字段编码成 `-2-code`（raid_manager.gd:1862 / 870-871）。
  - 修仙耦合：无。循环世界耦合：重——格子数 = LOOP/CELL、`_wrapi`、`Data.near2`、`Data.land_r/PLAY_R`、`Data.region_at`。
- **老导演**（`--spawn-old`，camps.on=false 时才走）`_director()` 后半 + `spawn_wave()`（raid_manager.gd:1748-1854）：点数 `_credits` 随 `here_depth` 涨，围着主角 28~90 米刷。新图不需要。
- **上限** `mob_cap()`（:1711-1715）：`MOB_CAP=22 / MOB_CAP_MOBILE=20`，身边 160 米内有 n 个真人就 ÷(n+1)；`_trim_far` / `_count_near_mates`（:1721-1745）。通用。
- **搜点守卫** `spawn_guards(pos, ri, n, elite, alert)`（:1788-1804）：从 `REGIONS[ri]["mobs"]` 抽，超上限 3 只以内。通用，但种类表要换。
- **游荡首领** `boss_event()`（:1673-1689，`_director` 里 240~360 秒一次，:1772-1775）：等级走 `Prog.boss_level/mob_tag`。

### 1.2 怪 AI 和数值 `raid_mob.gd`

- 状态机 `enum S {IDLE, CHASE, WIND, STRIKE, RECOVER, STUN, BLOWN, SLAM, DEAD}`（:24），`_process`（:879-1055）：闲逛 → 26 米内发现（`AGGRO`，首领 ×1.6）→ 蓄势 0.55 秒 → 扑 / 吐弹 → 喘息；首领有震地 `SLAM`（:942-948 / 980-990）；拴绳 `LEASH=70`，刷怪点的怪追丢回 `anchor`。
- 输入（全靠生成方注入，raid_manager.gd:1533-1559）：`def`（物种表 `Data.MOBS[i]`）、`region`、`lv`、`elite`、`hp_max`、`atk`、`xp_k`、`dmg_in: Callable`（主角打它时换算）、`atk_out: Callable`（它打主角时换算）、`floor_fn`、`player`。
- 受击入口三套都接好了：`receive_hit`（地面近战 / 飞剑，:760）、`air_hit`（空战拳脚，可打飞，:781）、`sim_damage`（AI 修士 / 道友，实伤，:724）、`net_damage`（联机别人打的，实伤，:643）。分组 `swordsmen` + `air_foes`（:114-115）。
- 打主角 `_hit_player()`（:824-835）：有 `decoy` 就 `decoy.mob_hit(...)`（远程玩家木偶会转发给本人），否则 `atk_out` 换算后走 `player.melee.receive_attack`（地面，能格挡弹反）或 `player.air.receive_attack`（空战）。远程弹 `_fire` / `_tick_bolts`（:838-874，伤害 `atk×0.7`）；扑击 `atk×1.0`（首领 ×1.5），震地 `atk×2.0`。
- 联机木偶：`puppet=true` 时不跑 AI，`net_push / net_die / _tick_puppet`（:620-680），1.5 秒没消息自毁；挨打时 `net_hit.call(self, info)` 发给主人。
- 修仙耦合：**无**（只 preload Combat / Sfx / Data / Models，Data 只用 `add_box`）。循环世界耦合：无。**缺陷：没有墙体碰撞**（见第 0 节）。

### 1.3 掉落：怎么摇、地上的箱子

- 摇货 `_loot(ri, n, bonus, depth, pill_realm)`（raid_manager.gd:1901-1906）→ `Data.roll_loot` → `Items.roll()`（raid_items.gd:210-237）：按区域 ri（0~4）+ 深度定品阶运气；结果里有破境丹（`key`）、符箓（`tool`）、修为丹 / 回春丹（`pill`）、法宝（`gear`）、灵材（`mat`）、灵草（`herb`）。价值 × `Prog.value_mult(depth)`。**修仙耦合重**：修为丹、破境丹、`Prog.pill_realm_at / roll_grade / roll_key_to`。
- 掉什么 `_on_mob_died(m)`（:1857-1896）：首领 → 箱子（巢穴首领 5 件 + 破境残片 `Items.frag` + 霸主精魄 `Items.overlord`）、精英 → 2 件箱子、小怪 20%（`KILL_DROP`，:153）掉 1 件；AI 修士 → 3~4 件储物袋（`_on_rival_died`，:2173-2180）；搜点 → `site_loot()`（:1911-1922）在搜点旁边放一只「搜得」箱。
- 地面物体 `raid_pickup.gd`：`item`（单件）或 `items`（箱子）+ `title` + `grace`；造型按 `kind` / `title` 后缀（「储物袋」「搜得」「精英的遗物」）挑模型（:44-62）；只用 `Data.TIER_COLORS`。修仙耦合：无（kind 名字是修仙的，但只影响外观）。
- 生成 / 登记 `_drop_item` / `_drop_chest`（raid_manager.gd:2209-2229）→ `_reg_drop`（:2186-2195，联机时编号 `"我的id:net.drop_n"` 并 `net.send_drop` 广播）。

### 1.4 拾取卡片 UI

- 管理器：`_update_pickups()`（:2299-2320）每帧挑 `PICK_R=3.6` 米（箱子 +0.6）内、`grace<=0`、没在申请中的最近 5 个进 `near_loot`；`loot_entries()`（:2324-2335）拆成 `[pk, idx, item]`；`pick_up(pk, idx)`（:2339-2368）——联机共享的走 `_claim` 整箱向房主申请；`pick_nearest()`（T 键，:2379）。
- 进背包 `_take(it, quiet)`（:2277-2294）：`_fits` 按格数（`Data.BAG_SIZE=12`，灵材 2 格，`Items.size_of`）；满了 `_swap_out` 自动换掉每格价值更低的法宝 / 灵材 / 灵草（:2256-2273，里面 `_edible` 是修为丹判断）；末尾有 `_need_key` 破境丹钩子（:2292）。
- 界面：`raid_hud.gd` 的 `_rebuild_loot()`（:365）+ `_process` 拾取段（:793-812），读 `mgr.near_loot / loot_entries() / _shared()`。通用。

### 1.5 搜点（站着读条） `raid_search.gd`

- 种类 `KINDS`（:26-32）：jar 1.4 秒 / herb 2.4 / grave 3.0 / vault 9.0（开始读条就引一拨守卫 `_vault_alarm`，:214-223）/ urn 4.5；刷新 `REFRESH` 480 / 900 秒（按本机 `clock`）。
- 摆位置 `_place()`（:56-78）：固定种子 `SEED`，按 `Data.pois()`、`REGIONS[ri]["dir"]`、`Data.R0/PLAY_R`、`COUNTS[ri]` 摆。**循环世界 / 五区域耦合重**。
- 读条 `step(dt, p, hurt, speed)`（:170-204，raid_manager.gd:2967 每帧调）：站在 `r` 内自动读，挨打退 1.5 秒，走开慢慢回落；法宝「识」加速。**通用**。
- 出货 `_finish(s)`（:225-251）：`Items.roll / Items.herb / Items.rpill / Items.key`，`Prog.pill_realm_at`——**修仙耦合**；然后 `mgr.site_loot(...)`、`mgr.net_send("§s", id)`。
- 探明 `tick()`（:131-166）：半径来自 `shen_shi.passive_r()`（按境界），`Data.near2` 换像，190 米建 / 240 米拆，走近灵药圃 / 坟冢掷守卫。
- 小地图 `marks()`（:439-447）、联机 `mark_done(id)`（:255-266）。

### 1.6 撤离点 / 种类 / 时间线

- 种类 `EX_KINDS`（raid_manager.gd:60-66）：gate 古传送阵 6 秒 / paid 灵石阵 6 秒（`paid_cost()=150×(境界+1)` 灵石，:2692-2693，从洞府扣 `Profile.spend`）/ boss 镇守阵 5 秒（打掉巢穴首领才亮，`_light_boss_gate`，:1482-1490）/ rift 空间裂隙 4 秒 / rune 破界符阵 14 秒（`_use_tool` 原地起阵，:2605-2619）。数据结构 `_extracts: [{pos, active, known, name, kind, node, base?, region?}]`（:162）。
- 建：`_setup_pois()`（:1373-1400）从 `Data.pois()` 取 extract 点 + 每个巢穴旁边一座镇守阵；外观 `_build_extract()`（:2624-2665，通用）。
- 读条 `_update_extract(dt)`（:2696-2739）：170 米内探明并提示；站进 `EXTRACT_R=6` 米、高差 < 8 米读条；**掉血就清零**（:2715）；开始读条每 5 秒广播 `§x` 位置（:2729-2732）；时长 ÷(1+养×0.5)；读满 `_finish(true)`。
- 时间线：两个钟——个人 `run_t`（`RAID_LEN=1200` 秒倒计时、5/3/1 分钟提示、到点困死 `_finish(false)`，`_timeline()` :2744-2769）；房间 `world_t()`（:1406-1407，联机 = `net.room_t`）——传送阵每 `ROT_PERIOD=300` 秒按 `(seed_v + 7919×轮次)` 洗牌，亮 2 座 gate + 1 座 paid（`_rotate_gates`，:1421-1468，各机器自己算、不发消息）；裂隙每 600 秒在 420 秒处开 120 秒（`_open_rift` :2778-2793，位置用房间种子在 160~1150 米圈里找陆地——**大世界写死**）。
- 修仙耦合：paid 的价格按境界、货币是灵石；其余无。循环世界耦合：`_reimage()`（:1571-1591）每 0.4 秒把地标挪到最近的像；`_open_rift` 半径常数。

### 1.7 死亡与结算 `_finish(success)`（:2869-2915）

1. `running=false`、停怪；没服完的丹放回背包。
2. 联机陨落：背包 + 佩戴法宝变一只共享「X 的储物袋」留在原地（:2879-2882），谁先申请归谁。`_killer`（:178、910-911）只是记了一下，**没有用**（注释说「背包归他」，实际是共享箱）；`net_loot()`（:999）没有任何调用者，是死代码。
3. 心得结算 → `Prog.profile_add_xp`（修仙，:2883-2897）。
4. `Profile.end_raid(success, bag, ring, gear, realm, -1, 0.0)`（:2898；raid_profile.gd:386-417）：成功 → 背包进仓库（满了折灵石）、法宝保留；失败 → 法宝清空；储物戒总保留；`live` 清掉。
5. `hud.show_result(success, items, value, kills, stash, extra)`（raid_hud.gd:527-599，extra 里的 `ins*` 键缺省为 0，不传也能用）。
6. 4.5 秒后 `level.exit_requested.emit()`（:2913-2915）→ main.gd `_return_to_hall`。
- 另两条路：`room_collapsed()`（:2817，房主关房 → 按撤离成功）/ `room_lost()`（:2828，自己掉线 → 带进来的东西按 `Profile._recover_live` 还回）。由 main.gd:754-758 通过 `level.get("raid")` 调。
- 进图 `Profile.begin_raid()`（raid_profile.gd:372-379）：拷贝 gear / carry / ring，写 `live`（中途强退可恢复）。

### 1.8 背包 / 储物戒 / 法宝

- `bag`（12 格）、`ring`（死了保住，容量 `Profile.ring_cap()` 1~4）、`gear`（`GEAR_SLOTS=3`，死了全丢）；被动 `fx={atk,guard,seek,vital}` = `Items.fx_total(gear)`（`_recalc_fx`，:305-309）。
- 操作：`bag_actions(i)`（:2386-2402）、`use_item(i, act)`（:2411-2455：use / equip / ring / drop）、`unequip`（:2558）、`from_ring`（:2571）、`sort_bag`（:2583）、`_use_tool`（寻宝符 60 秒 / 破界符，:2594-2619）。
- 修仙耦合：`use_item` 的 pill 分支（境界锁、`_xp_full`、`_eat_one`）、`eat_all` 一键服丹（:2484-2527）、`_consume_live`（:604-613，其实是「消耗品从 live.carry 划掉」，对回血药 / 符箓同样需要，搬时保留通用版）。

### 1.9 AI 修士（air_foe 当对手）

- `spawn_rival(pos, hostile)`（raid_manager.gd:1961-1992）：`raid/pro/roam=true`，名字轮 `Data.AI_NAMES`，`lv=_level_in(区域,位置)`、`look_i=Prog.mob_tag`（外观按境界档）、`hp_max = RIVAL_HP(260)×HP_CONV×CS.mob_s_hp`、`prey_dmg`、`dmg_in=player_dmg_vs.bind(f)`、`prey_fn=_prey_for`（找附近的怪打）、`engage_ok=_engage_ok`（开局 40 秒后、同时最多 2 个围攻）、`volley_init=false`。
- 敌意：`hostile` 两成红名主动打人；白名被打就翻脸（air_foe.gd:640-642）；打主角 `_hit_player` 伤害 × `dmg_mul`（air_foe.gd:389-393），`dmg_mul` 每 0.4 秒按量级比现算（raid_manager.gd:2004）。
- 刷新 `_update_rivals()`（:1995-2045）：上限 `rival_cap()=3`，**房间里有第二个真人就是 0、全部退场**（:1927-1930）——AI 修士**完全不联机同步**。只在主角所在档以内刷（`Prog.mob_tag` 闸，:2031）。
- 掉落 `_on_rival_died`：心得 + 3~4 件储物袋。

### 1.10 AI 道友（只看接口）

- 生成 `_spawn_ally(p)`（:2097-2126）：一个 `AirFoe`，`ally=true`、`ally_slot`、`hp_max=_ally_hp(lv)=39.6×CS.A_NOM×CS.G(lv)`、`prey_dmg=0.6×CS.unit_same(lv)`、`prey_fn=_ally_prey`；`ally_team.attach(self, f)` 挂大脑。
- 数量 `ally_want()`（:2051-2057）= 队伍人数 − 本队真人，只在本队编号最小的真人机器上算（`AllyTeam.is_owner`，ally_team.gd:21-31）；`_update_allies`（:2137-2161）每 0.4 秒 `set_level(lv,…)` 跟着主角等级涨（修仙耦合点）。
- 大脑 `ally_brain.gd` 读管理器的字段：`rd.player / rd.hud / rd._mobs / rd._puppets / rd._boss_nodes() / rd._rivals / rd._allies / rd.get("_in_trib") / rd.get("extract_k") / rd.get("search")`（:211、219、493）；打怪 `sim_damage(dmg×DMG_K 0.3)`（:330），挨打 `hp -= dmg×HURT_K 0.55`（:620）。
- 联机：`net_ally_batch()/net_ally_apply()`（:2165-2170）→ `AllyTeam.batch/apply`（ally_team.gd:66-111，14 元组，`Data.near` 换像，240 米内建 `ally_puppet`）。

### 1.11 首领 / 巢穴 / 播报

- 巢穴表 `_bosses: [{region, pos, node, state 0未刷/1在场/2打空, mark, back}]`（:160），来自 `Data.pois()` 的 boss 点，`_build_lair` 柱阵 + 光柱（:1502-1529，纯外观）。
- `_update_bosses(p)`（:1627-1669）：200 米内（`LAIR_SPAWN_R`）刷，附近已有别人名下首领的木偶就认它（`_lair_puppet/_adopt_lair`）；打空后 `LAIR_BACK=600` 秒（个人时钟）重来；150 米内的首领交给 HUD 血条（`hud.boss`）。等级 `Prog.boss_level(Prog.lair_tag(ri), …)`——修仙耦合。
- `_lair_cleared(ri, remote)`（:843-854）：记空 + 亮镇守阵。
- 播报：`_announce_boss` → `hud.banner`（:1562-1565）；全屏横幅 `Broadcast.make(...)`（realm_broadcast.gd，用于结婴，:959 / 978）——横幅组件本身通用。
- **剑冢 Boss**（`boss_demon.gd` + `boss_arena.gd` + `boss_hud.gd`）是**主城试剑台里的单机弹幕首领**，不在 raid 里：位置写死 `TestHall.BOSS_ARENA`（boss_arena.gd:63-64）、开打把低境界临时拔到元婴（`MIN_REALM=3`，:156-160）、血量 `Boss.HP_MAX × CS.boss_k(realm)`（:162）、独立护体 100（`HP_MAX`）、无联机。可以借它的弹幕池（`boss_bullets.gd`）和三阶段时间表做新图首领，但要去掉压境 / 境界缩放和 TestHall 常量。

### 1.12 小地图标记 `minimap.gd`

- 底图要 `mgr.level.world.map_colors(center, span, n, shade)`（工作线程）/ `map_cells(...)`（网页分帧）（minimap.gd:138-191，block_world.gd:795 / 803）——新关卡的 level.world 必须提供这两个（或给小地图一张烘好的平面图）。
- 标记直接读管理器字段（minimap.gd:198-330）：`_pickups`、`_mobs + _puppets.values()`、`_bosses`（`state/pos/node`）、`_rivals`、`_allies`、`net.remotes`、`search.marks()`、`pings [pos, kind, 剩余秒]`、`_extracts`（`known/active/pos/kind`）、`ex_col(kind)`、`cam.yaw`。点一下调 `shenshi.scan()`，没有神识就切近 / 远景（:120-127）。

### 1.13 HUD `raid_hud.gd`

- 通用：`banner / toast`（:507-523）、Boss 血条（读 `boss.hp_ratio()`、`display_name`、`lv`）、读条条（`extract_k/extract_kind/search_k/search.verb()/chest_k`，:758-791）、拾取卡、背包面板（`bag/gear/ring/bag_used/bag_value/bag_actions/use_item/unequip/from_ring/sort_bag`）、结算 `show_result`。
- 修仙 / 大世界：右上纸条 `_info`（:666-704）读 `Data.REGIONS[mgr.region]`、`insight_cap / insight_shown`、`_here_tag()`（Prog.mob_tag）、`here_depth`、`sup_gap`、`Realm.LIST`、`at_sea`；心得小字 `_tick_ins_chip`；背包详情 `Prog.pill_use_err`（:480 附近）；结算 `_carry_now`。`_ready` 把 mgr 交给左上玩家牌（raid_hud.gd:121-124），而 `player_plate.gd:304-308` 读 `raid.lv / exp_ratio() / fx / _need_key / _need_ls`——新管理器要么给这些字段 / 函数桩，要么改玩家牌。`hud.gd:468` 读 `mgr.dmg_ratio`（连击伤害显示）。

### 1.14 只属于修仙的模块（新图不要）

心得 `insight_fx.gd` + `add_insight`（:463）；神识 `shen_shi.gd`（按境界 TIERS，但读的都是 `_extracts/_pickups/_mobs/_puppets/_rivals`——想留「雷达」可以去境界化后复用）；雷劫 `tribulation.gd` + `_try_start_trib/_on_trib_done/_end_trib/_abort_trib`（:1020-1107、2855）；结婴演出 `_watch_cine/_on_yuanying`；天道压制 `_update_here`（:355-375）；区域氛围 `_blend_atmosphere`（:1117-1345，**`region`/`at_sea` 也是在这里面顺手设的**，:1330-1331）。

---

## 2. 联机同步：哪些消息带了什么，新图要调什么

### 2.1 消息清单（net.gd）

| 内容 | 发送 | 接收 → 管理器 | 备注 |
|---|---|---|---|
| 玩家状态 15 Hz | `_state.rpc(pos,yaw,st,realm,hp,pose,pose_n,lv,vel,flags)`（:473-474） | `remote_player.push_state`（`LoopData.near` 换像，:493） | 读 `raid.lv`、`raid.get("_in_trib")`；realm / lv 两个 int 字段可以改装成英雄编号 / 等级而不改协议 |
| 我名下的怪 10 Hz | `raid.net_mob_batch()` → `_mobs.rpc`（:479-481） | `net_mob_apply(owner, batch)`（raid_manager.gd:662） | 每条 11 项：`[nid, def_idx, region, lv, elite, pos, yaw, hp比, state, lair, camp]`；220 米内建木偶，一批最多新建 3 只 |
| 打别人的怪 | `_on_puppet_hit` → `send_mob_hit(owner,nid,dmg,…)`（:707-711 / net.gd:815） | `net_mob_take` → `m.net_damage`（实伤） | 伤害在**攻击方**本地换算好 |
| 别人的怪打我 | 怪 `decoy.mob_hit` → `remote_player.mob_hit` → `send_mob_attack`（remote_player.gd:240-243） | `net_mob_attack` → `net_take_hit(src,0,…)` → `to_player_from` | 发的是**原始攻击**，在**受击方**换算 |
| 怪死 | `send_mob_dead(nid,pos,lv,xp_k,lair,last_hitter)`（:1862） | `net_mob_died(…, share)`（:858） | `lair>=0` 巢穴、`<=-2` 刷怪点编码；share = 补过刀或主人是队友（只用来分心得） |
| 掉落 | `send_drop(nid,pos,item,items,title)`（_reg_drop） | `net_drop` | nid = `"id:net.drop_n"` |
| 拾取 | `send_claim(nid)` → 房主 `_claim_on_host`（先到先得，`_claimed`） | `_granted.rpc` → `net_granted(nid, mine)` | 只有房主判；整箱拿 |
| 中途加入 | `_hello` → 房主 `_welcome(seed, cleared, room_t, drops, dug, blasts)`（:299-323） | `pending_drops/dug/blasts`，管理器 `_ready` 取走（raid_manager.gd:248-263） | 房主要 `raid.net_drop_list()` 和 `raid.level.world.dug_table()` |
| 房间时钟 | 房主 10 秒 `_clock.rpc(room_t)` | `room_t` | 传送阵轮换 / 裂隙 / 刷怪点复活都按它 |
| PvP 命中 | `remote_player` 被打 → `raid.net_deal_hit(puppet, peer, info)`（remote_player.gd:398）→ `send_hit` | `_hit` → `net_take_hit(src, from, …)`（队友直接丢弃，net.gd:809） | 发的是对方条上的点数 |
| AI 道友 10 Hz | `net_ally_batch` → `_allies.rpc` | `net_ally_apply` | 每批 ≤3 条 |
| 飞剑 / 法术表现 | `_proj.rpc(k, from, ref_of(tgt), aim, opts)` | `node_of(ref)` → 怪要 `raid.net_find_mob(owner,nid)` | |
| 小消息（借播报通道） | `net_send("§s", 搜点id)` / `net_send("§x","x,z")` → `send_announce` | `net_announce` → `_net_small`（:974-996） | §s 别人搜完了 → `search.mark_done`；§x 有人在撤离 → 小地图 ping |
| 地形破坏 | `send_dig` | `raid.level.remote_blast` / `raid.level.world.dig`（:665-667） | 新图不可破坏就给空实现 |
| 雷劫旁观 | `send_trib` | `net_trib` | 新图给空实现 |

### 2.2 新管理器要做到「联机正确」必须满足的契约

net.gd 把 `net.raid` 当鸭子类型用（`arena_duel.gd:656-765` 就是照这个写的空实现先例）：

1. **字段**：`lv: int`、`_in_trib: bool`、`level`（要有 `world.dug_table()`、`world.dig(p,r,f)`、`remote_blast(p,r)`）、`running`（main.gd:757）。
2. **函数**：`net_mob_batch / net_mob_apply / net_find_mob / net_mob_take / net_mob_attack / net_mob_died / net_drop / net_drop_list / net_granted / net_take_hit / net_deal_hit / net_announce / net_trib / net_ally_batch / net_ally_apply`，以及 main.gd 用的 `room_collapsed / room_lost`。
3. **生命周期**：`_ready` 里 `net.enter_world(self)`（远程玩家木偶会 `add_child` 到它下面，net.gd:447），把 `net.pending_*` 取走；`_exit_tree` 里 `net.leave_world()`。
4. **规矩**：怪由建它的人模拟、10 Hz 发批；打木偶时在本地换算成实伤再发；怪打远程玩家发原始攻击；掉落一律 `_reg_drop` 登记 + 拾取走 `_claim`；撤离 / 搜点用 §x / §s；需要全房间一致的随机（轮换、裂隙）用 `net.seed_v` + `net.room_t` 现算，不发消息。

### 2.3 现有空洞（新图上会暴露）

- **房间没有关卡编号**：发现包是 `"XIUXIAN|房名|人数"`（net.gd:131），`_welcome` 也不带关卡；main.gd `_enter_level(_id)` 忽略 id、永远建 `MeadowLevel`（main.gd:806、853）。两张新图必须把关卡 id 加进发现包、`_hello/_welcome` 和匹配筛选，否则沙漠的人会连进研究所的房间。
- **搜点没有锁**：两人同时读同一个点，先读满的发 §s，另一人只要在消息到之前读满也照样出货（raid_search.gd:200-251）——一个点出两份。宝库守卫也是读条人本地刷。要改成「读满时向房主申请」，可以照抄掉落的 `_claim` 流程。
- **AI 修士不同步**：有第二个真人就全部消失（raid_manager.gd:1927-1930）。若新图要 AI 对手（DarkArea 的人机），得新写同步或让它们也走「主人模拟 + 木偶」那套（可以复用 `ally_team.batch/apply` 的结构）。
- **撤离只在本地判**，别人只看到 ping；击杀归属 `_killer` 未使用。
- 循环世界换像 `Data.near`（net.gd:493、raid_manager.gd:672/703/777、ally_team.gd:93）：新图半径远小于 `HALF=1728` 米时 `near` 原样返回，**不用改也不出错**。

---

## 3. 建议：新写管理器，复用组件

### 3.1 为什么不参数化 raid_manager

- 修仙不是一层皮，而是穿在主流程里：`_finish` 里结算心得，`_take` 里有破境丹钩子，`_spawn_mob` 的血攻是 `CS.mob_s_hp(ri,lv)` 境界档量级，`_on_mob_died` 掉残片 / 精魄，`_process` 一开头就是雷劫 / 服丹队列（:2921-2961），`_update_here` 天道压制，`player_plate` 读 `_need_key`。参数化等于每个函数都加分支。
- 大世界假设同样到处都是：`Data.pois()`、区域下标 0~4（`REGIONS[ri]`、`Prog.*(ri)` 都 `clampi(ri,0,4)`）、`_reimage`、`at_sea / PLAY_R / land_r`、`region` 在氛围函数里设、`_open_rift` 的 160~1150 米圈。
- 用户要「剔除跟搜打撤不相干的玩法」，raid_manager 迟早要被剥掉修仙；新图上从干净的管理器起步，老大世界照常跑、不互相拖累，自检（raid_selftest / raid_pace_test 大量读 raid_manager 内部）也不会被打断。
- 已有先例：`arena_duel.gd` 就是「另写一个、实现 net 契约」，跑通了联机。

### 3.2 原样复用（不改或只改调用方）

- `raid_mob.gd` 全文件（数值全靠注入；只需新图提供 `floor_fn`，并**补墙体约束**）。
- `raid_pickup.gd` 全文件。
- `ally_team.gd`、`ally_brain.gd`、`ally_puppet.gd`（新管理器提供第 1.10 节列的字段即可）。
- `air_foe.gd`（作 AI 对手 / 道友；`look_i` 现在是境界外观下标，以后可改成英雄外观）。
- `remote_player.gd`、`net.gd`（只加关卡 id；协议没有版本号，raid_manager.gd:885 的注释提醒新旧包别混房）。
- `raid_hud.gd` 的 banner / toast / Boss 血条 / 读条 / 拾取卡 / 背包面板 / `show_result`；`minimap.gd` 的标记绘制；`realm_broadcast.gd` 的横幅；`raid_profile.gd` 的 `begin_raid / end_raid(…, -1, 0.0) / spend / _recover_live`；`raid_items.gd` 的 `size_of / slots_used / fx_total / gear / rand_gear / tool / heal_pill / desc / badge / icon_name`。

### 3.3 从 raid_manager 近乎逐字搬进新管理器（不含修仙，删一两行即可）

联机：`net_on / _exit_tree / net_mob_batch / net_mob_apply / _on_puppet_hit / _my_mobs / net_find_mob / _retarget_mobs / net_mob_take`（删 `hi_realm`）/ `net_mob_attack / net_drop / net_drop_list / net_granted / net_announce / net_send / _net_small / _pvp_clamp / room_collapsed / room_lost`（删心得）。
掉落 / 背包：`_reg_drop / _shared / _claim / _drop_item / _drop_chest / settle_drops / bag_value / bag_used / _fits / _swap_out`（删 `_edible`）/ `_take`（删 `_need_key`）/ `_update_pickups / loot_entries / pick_up / _remove_pickup / pick_nearest / bag_actions / ring_free / use_item`（删修为丹分支）/ `unequip / from_ring / sort_bag / _use_tool / _consume_live / _float_text`。
撤离：`EX_KINDS / _build_extract / _beam / nearest_extract / ex_col / _update_extract / world_t / _room_seed / rotation_left / _rotate_gates / _set_extract_active / _light_boss_gate / _active_count / _timeline / _close_rift / ping / time_left / _finish`（删心得）。
怪 / 首领：`mob_cap / _count_near_mates / _trim_far / spawn_guards / _lair_cleared / _adopt_lair / _lair_alive / _lair_mark / _lair_puppet / _update_bosses / _boss_nodes / _announce_boss / _build_lair`。
AI：`_engaged / _engage_ok / _prey_for / spawn_rival / _update_rivals / ally_want / ally_count / _ally_prey / _ally_spot / _spawn_ally / _update_allies / net_ally_batch / net_ally_apply / _on_rival_died`。

### 3.4 需要薄适配

- `_spawn_mob`：换数值公式（见第 4 节），物种表换成新图自己的。
- `_on_mob_died / _loot / site_loot`：换掉 `Items.roll` 的修仙出货，改成新图的掉落表（DarkArea 的物资 / 货币）；保留「首领箱 / 精英箱 / 小怪概率单件」三档结构。
- `raid_camps.gd`：保留状态机（`alive / on_dead / saw / _owned_by_other / _lower_peer_near / tick / frame / _build / _unload`），把 `camp()/_layout()` 的循环格子换成「关卡数据里的固定点表」（id 取下标，`code = id*8+slot` 不变），`_wrapi / near2` 去掉。
- `raid_search.gd`：保留 `step / verb / mark_done / _refresh_site / _dress_*`，`_place` 改读关卡点表，`_finish` 的出货改回调，`tick` 的探明半径别读神识；顺手加「读满向房主申请」。
- `_open_rift`：候选点改成关卡给的列表。`paid_cost` 改成新货币、不按境界。
- 新关卡节点要照 `meadow_level.gd` 提供：`signal exit_requested`、`ground(x,z)`、`spawn_point()`、`spawn_yaw()`、`prewarm()`、`stats_text()`、`env/sun`、`raid`、`world`（`dug_table/dig/map_colors/map_cells` 或空实现）；main.gd `_enter_level` 按 id 分支建关卡。
- HUD 右上纸条、玩家牌：新管理器提供 `region / at_sea / here_depth / here_lv / here_tag / sup_gap / insight_* / exp_ratio() / _need_key / _need_ls / fx / dmg_ratio` 的桩，或者把这两处改成读一个 `info_text()`，更干净。

### 3.5 只属于修仙（新管理器不要）

`coeff / enemy_level / depth_of / _level_in / level_at / _update_here / sup_dmg_k / kill_exp / _carry_k / insight_cap / add_insight / insight_arrived / _sync_shown / _realm_of / _sync_cult / add_exp / _cult_changed / _bottleneck / _realm_pills_left / _find_key / _eat_key / _trim_saved_keys / _count_keys / _trim_keys / net_trib`（留空实现）/ `_watch_cine / _on_yuanying / gm_tribulation / trib_active / _try_start_trib / _on_trib_done / _end_trib / _abort_trib / exp_ratio / _at_cap / _xp_full / _edible / eat_count / eat_all / _eat_one`（回血分支留）/ `_recalc_fx / _power_toast` 的战力部分 / `boss_event` 的 Prog 定级 / `_blend_atmosphere / _reimage`；文件 `insight_fx.gd / tribulation.gd / yuanying_cine.gd / shen_shi.gd`（除非去境界化当雷达）/ `progression.gd` 全部。

---

## 4. 现在的伤害怎么算，新图怎么换成不看境界的数值

### 4.1 现状

- **招式原始伤害 d**：所有出手都是 `CS.base(境界) × 招式倍率`，`base` = `Realm.LIST[境界].dmg` 8 / 12 / 18 / 26 / 38 / 52 / 75 / 110（combat_stats.gd:6、50-51）；地面连招 `ground_k = base/8`、剑诀 `skill_k`、连发 `volley_k`、飞剑阵 `q_k` 都是在这上面折的（:153-198）。**招式单位 = d / base(境界)**。
- **主角打怪** `player_dmg_vs(d, t)`（raid_manager.gd:403-407）→ `CS.raid_hit(d, 境界, lv, fx.atk, s)`（combat_stats.gd:115-116）：
  `d / base(境界) × atk(lv) × (1 + min(法宝攻, 0.8)) × hit_factor(lv, s)`，
  `atk(lv) = 1000 × G(lv)`，`G` 境内每级 ×1.374、每境 ×2（:36-40），`hit_factor = 1 / (1 + 3.5 × 100 × s / atk(lv))`（:99-101），s 来自 `_target_scale`：按目标的 (region, lv) 现算 `CS.mob_scale`（raid_manager.gd:386-398）。生成时绑定 `m.dmg_in = player_dmg_vs.bind(m)`（:1550），怪在 `_take` 里调（raid_mob.gd:745-747）。
- **怪的血攻**（raid_manager.gd:1543-1548）：
  `hp = 体型血(兽48/浮空36/巨汉100 或 首领70) × 物种hp × HP_CONV(61.67) × mob_s_hp(区, lv) × 精英2.5 × hp_k`；
  `atk = 体型攻(12/9/16 或 首领10) × 物种atk × MOB_DMG 0.8 × ATK_CONV(76.67) × mob_s_atk(区, lv) × 精英1.5`。
  出手：扑击 ×1（首领 ×1.5）、弹 ×0.7、震地 ×2（raid_mob.gd:864、972、989）。
- **怪打主角** `to_player_from(d, t)`（raid_manager.gd:418-419）→ `CS.to_bar(d, lv, fx.guard, s)`（combat_stats.gd:105-106）：
  `d × guard_factor × 100 / hp(lv) × (1 − min(法宝守, 0.6))`，`hp(lv)=2500×G(lv)`，`guard_factor = 1/(1 + 3.5×500G/(736×s))`。结果落在主角 **0~100 的气血条**上（`player.melee.hp / HP_MAX`），再进 `melee.receive_attack`（格挡擦 15%，`BLOCK_CHIP`）或 `air.receive_attack`。绑定 `m.atk_out = to_player_from.bind(m)`（:1551）。别人名下的怪打我：同一个函数，s 按木偶的 region/lv（:913-917）。
- **AI 修士 → 主角**：招式原始数 × `dmg_mul = RIVAL_DMG 0.42 × CS.rel_bar_k(s, lv) × (1−守)` 直接落条（raid_manager.gd:2004，air_foe.gd:390）。**AI → 怪**：`prey_dmg`（实伤，`AI_PREY_K 0.6 × CS.unit_same(lv) × 量级`），道友再 × `DMG_K 0.3`，走 `sim_damage` 不过换算。
- **PvP** `net_deal_hit`（raid_manager.gd:886-893）→ `CS.pvp_hit = d/base(我) × 9 × 1.08^(境界差) × (1+min(攻,0.3))`；受击方 `_pvp_clamp`（单下 22、余量 30、每秒 25，×`pvp_cap_k`）后 `pvp_guard`（守封顶 30%）（:897-911、940-945）。
- **已有的平数值先例**：擂台 `CS.arena_hit(d, 境界, my_lv, their_lv) = d/base(境界) × 2.4 × arena_adv`，封顶 `arena_clamp`（14 / 26 / 每秒 13），AI 陪练 `hp = 42 × base(境界)`（combat_stats.gd:261-288）——就是「只看招式单位」的平模型。

### 4.2 新图的平模型（不改 raid_mob，只换两个绑定的函数）

- 统一单位：`u = d / CS.base(出手方当前境界)`（或者新英雄的招式直接按 base=1 出数，那就是 u=d）。
- 主角打怪：`player_dmg_vs(d, t) = u × HIT_PER_UNIT × 英雄 / 装备系数`；怪的 `hp_max` 直接写成「要几个单位」（比如小怪 4 单位、精英 10、首领 60），不再乘 `mob_s_hp`。照旧写 `dmg_ratio` 给 hud。
- 怪打主角：`to_player_from(d, t) = d × (1 − 护甲)`，怪的 `atk` 直接写成「打掉条上几个点」（比如 8.7 点 ≈ 现在同级兽一下），不再乘 `ATK_CONV / mob_s_atk / guard_factor`；联机里木偶两边的数自然一致（不依赖 region/lv）。
- AI：`f.dmg_mul` 写常数、`f.hp_max` 写单位数、`prey_dmg` 写单位数 × HIT_PER_UNIT；道友 `set_level` 改成不随修为涨。
- PvP：沿用 `CS.pvp_hit` 但把境界差置 0（或直接用 `arena_hit + arena_clamp`），`_pvp_clamp` 保留防秒杀；`_state` 里的 realm 字段不再影响数值。
- 注意：境界目前还决定招式本身（剑数、连发速率、能不能飞，`Realm.LIST`），这些在 d 里已经被 `/base` 抹平了一半，英雄体系落地前新图应把主角境界固定在一档，免得剑数不同带来的 DPS 差。
