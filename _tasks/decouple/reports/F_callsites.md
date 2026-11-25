# F：搜打撤栈在 scripts/ex 之外的调用点（主干解耦用）

只读勘查，2026-11-25，分支 raid-block-world @ 5c25796。没有改任何项目文件。
标记：**DEL** 删掉 / **KEEP** 原样留 / **RP** 改接 raid_profile.gd（Profile）/ **RM** 改接 raid_manager.gd（老大世界管理器）/ **EDIT** 留着但要改逻辑。

前置事实：
- project.godot 里**没有 autoload**；scenes/ 只有 main.tscn，不引用 scripts/ex。所有接入都是 `preload` / 运行时 `load("res://scripts/ex/...")`，而且大多数地方先查 `ResourceLoader.exists`，所以删文件不会让解析出错，只会静默走老分支。但 **preload 的硬依赖会在文件删掉后导致解析失败**：destruct.gd:27（grid_world）、minimap.gd:25（map_def），还有 scripts/ex 内部的 preload。
- raid_profile.gd 里**没有 hero 字段**（`grep hero` 为空）。英雄选择现在只存在 ex_profile.hero()。
- 元婴 = `Realm.LIST[3]`（realm.gd:43），所以门槛是 `Profile.realm() >= 3`。
- 英雄档现在会把数值钉死在结丹：hero_defs.gd:36-37 `BASE := 18.0`、`TIER := 2`；player.gd:475 `realm_idx = HeroDefs.TIER`；combat_stats.gd:228 `heroes_on` 会把 PvP 的境界差抹平。

---

## 1. main.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 75-76 | 注释：门 2/3 走 ex_level.gd | EDIT 注释 |
| 80 `EX_LEVEL_IDS := ["desert","lab"]` | 认新图 | KEEP（改个名更好，比如 `HARD_LEVEL_IDS`）；它决定建哪一种关卡节点 |
| 81 `LEVEL_TITLES` | 标题 | KEEP |
| 225 | 注释：「一键服丹」hall_pills.gd 被删了（cbb6ec9 删掉的是 `var hall_pills := preload("res://scripts/hall_pills.gd").new()`，再设 main/player/font/touch，最后 add_child） | **恢复**：把那 7 行加回来（scripts/hall_pills.gd 还在）|
| 237 `hub.connect("gate_entered", _on_hub_gate)` | 门 | KEEP |
| 255 `player.set_realm(Profile.boot_realm())` | 存档境界 | KEEP |
| 256-260 `_apply_combat_mode("hub")` | 主城进英雄档，数值钉死结丹 | EDIT：见下面 `_apply_combat_mode` |
| 307-326 探针表 | `--level-test`→ex_selftest、`--level-shot`→ex_level_shot、`--lobby-test`→ex_lobby_selftest、`--boss-test-ex`→ex_boss_selftest、`--hero-test`→hero_selftest、`--tsb-show`→tsb_show | 删掉 `--level-test`、`--lobby-test`、`--boss-test-ex` 三项；`--level-shot` 只有在把 ex_level_shot 改成纯截图（不碰 extract_manager）时才留；KEEP `--hero-test`、`--tsb-show` |
| 535 `player.hero_id != ""` 招名小一号 | 英雄画面 | KEEP |
| 653-655 `var gm := test_mode() and not _ex_mode()` | 正式游玩禁掉 GM 改境界键 | EDIT：去掉 `_ex_mode()`。cbb6ec9 之前这些键**一直**能用；要么恢复成一直能用，要么保持只在 test_mode 下能用（需要定一下）|
| 663-666 | 新图里正式游玩禁 Backspace 回出生点 | EDIT：去掉。规则跟大世界一样，木兰草原允许 |
| 772-781 `_open_level_select(id)` | 门 2/3 → `level_ui.open_level(id)` | KEEP（入境页照用）|
| 784-786 `_ex_mode()` | 只给 655/665 用 | 那两处改完后 **DEL** |
| 789-806 `_apply_combat_mode(mode)` | "legacy" → `set_hero("")` 加存档境界；其他（hub/ex）→ 从 **ex_profile.hero()** 读英雄，`set_hero(hid)`（钉死结丹）| **RP + EDIT**：改成只有一条路：`player.set_realm(Profile.boot_realm(), false)`，然后 `player.set_hero(Profile.hero())`。英雄只换招式 / 外观 / 打法，境界数值跟存档走（player.set_hero 那边也要改，见第 4 节）。mode 参数可以留着兼容 mijing_boot / hero_selftest，但三种 mode 行为一样 |
| 809-819 `_level_bag_open` | 大地图开着时让出触屏（`level.big_map_open`）| KEEP（ex_level 的大地图留着的话）；raid 分支走 raid_hud.bag_open |
| 878-976 `_enter_level` | 884 `is_ex`；899-902 建房前 `_apply_combat_mode("ex"/"legacy")`；927-931 入房失败 `_apply_combat_mode("hub")`；946-950 `load("res://scripts/ex/ex_level.gd").new()` + 设 `map_id`；952-958 鸭子类型设 player/cam/font/mobile/net；969 `Warm.run(tag "ex"…)`；975 打日志 | 899-902 / 930：KEEP 这个时机，但只调统一的 `_apply_combat_mode()`。946-950：KEEP 建 ex_level（它是地图几何），**ex_level 内部要建 raid_manager，不建 extract_manager**（ex_level.gd:24 `MANAGER_PATH`、201-215 的建法）。969：tag 改成 `"raid"`（传 raid_manager 进去，让老的预热路线摆怪 / 掉落），另外要一个只管地图的标签给边界幕 / 飘浮物用（见第 8 节）。还要加：**元婴门槛**（见 1117 行）|
| 1047-1078 `_return_to_hall` | 1072 `_apply_combat_mode("hub")` | KEEP（统一模式）|
| 1117-1127 `_on_hub_gate(i)` | 门 → `hub.gate_level(i)` → 开选关 | **EDIT：元婴门槛放这里**：`if lid in EX_LEVEL_IDS and Profile.realm() < 3: hub.say("元婴以上方可踏入%s" % 标题); return`。入境页的「开始匹配」也要再挡一次（level_select.gd:323）|
| 1222 `touch.blocked = Tribulation.running or _level_bag_open()` | | KEEP |

## 2. hud.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 40-41 | 主城里按 B → `_open_abode` | KEEP |
| 103-120 | `_bag_btn = _dock_button("meta_icon_prep","备战")`；`_hero_btn` 头像能点；`_build_dock()` | KEEP（壳子留着；meta_kit.round_button 只画图标）|
| 190-212 `_open_abode` → `level_ui.open_abode()` | | KEEP（实际开哪个界面由 level_select 决定）|
| 214-217 `EX_PROFILE` / `EX_DATA` 常量 | | DEL |
| 218-228 `_rank_t`、`_rank_fx_on`、`_hub_q`、`INTRO_LINES`（讲搜打撤规则的「门 2 沙海古墟… 15 分钟撤离… 售卖物到坊市换灵石」）| 新号引导 | DEL 段位部分；排队说话的 `_hub_q` 留着也行；INTRO_LINES 改成修仙口径，或者删掉 |
| 246-299 `_ex_rank_banner()` | 每 0.5 秒：`ep.take_rank_up()` 播段位题字，`ep.take_notice()`（中途离线的陨落结算），`ep.intro_pending/mark_intro` | **DEL**（或改成 `Profile` 的通知，前提是 raid_profile 有类似接口。它没有 take_notice，所以就是删）|
| 518 `_ex_rank_banner()` 调用 | | DEL |
| 527 `_hero_btn.visible = … p.hero_id != "" and exists(HERO_UI)` | | KEEP（主干上英雄一直开着，按钮一直在）|
| 636+ 英雄档技能框 | | KEEP |
| 768 `HERO_UI := "res://scripts/ex/hero_select_ui.gd"` | | KEEP（文件挪出 ex/ 的话改路径）|
| 788-797 `_open_heroes` → `hero_select_ui.open(ui, true)` | | KEEP（hero_select_ui 内部改走 RP，见第 10 节）|
| 805-858 `META_KIT`、`_dock_button`、`_build_dock`、`_layout_dock`、`_open_meta(key)` → `_abode._set_tab("shop"/"rank"/"prep")` | 四颗入口 | KEEP 壳子；meta_ui 要认 tab key（prep/shop/rank）|

## 3. level_select.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 11-24 `LEVELS` | mulan 那张卡写着「最多 40 人」；desert/lab 带 `"ex": true`，标签 / 说明是「15 分钟、开箱 / 钥匙房 / 天工师」| EDIT：`ex` 改成 `"hard": true, "min_realm": 3`；说明改成修仙口径（「元婴以上 · 高危禁地 · 规则同木兰草原」）|
| 25 `EX_META`（meta_ui.gd）| 新元界面 | KEEP（meta_ui 改接 RP）|
| 26 `EX_LOBBY`（ex_lobby_ui.gd）| 旧纸面板大厅 | **DEL**，连同 `_use_meta` 里的 `--old-lobby` / `--lobby-test` 分支（410-418）|
| 27 `EX_PROFILE` | | DEL → 改用 `Profile` |
| 134-136 卡片页跳过 `ex` 的图 | 门 2/3 不在门 0 的卡片里出现 | KEEP（键名改成 `hard`）|
| 177-181 `_ex_ctx()` | 没开选关或新图入境页 → 新经济界面 | EDIT：主城里开 meta_ui，入境页（任何一张图）照旧开 abode_ui / 或 meta_ui 的备战页——两边都是 Profile 数据了 |
| 184-189 `_summary()` → `ex_lobby_ui.summary()` | 「这次带什么」| RP：一律 `Abode.summary()` |
| 193-198 `_entry_err()` → `ex_profile.entry_check()`（不能带售卖物）| | EDIT：改成境界门槛 `Profile.realm() < int(LEVELS[_lv].get("min_realm",0))` → "元婴以上方可踏入" |
| 293-294 新图入境页才显示 `_hero_row` | | EDIT：英雄行给**所有**图都显示（或者干脆删掉，靠主城的英雄入口），因为英雄现在到处都用 |
| 315-317 新图专用提示（「售卖物不能带入… 陨落扣灵石、掉命牌…」）| | DEL（用 312 行那句老提示）|
| 318-323 go 按钮 → `_entry_err()` | | KEEP 接线，内容按上面改 |
| 336-372 `_hero_row` | 用 `ep.hero_ids()`、`ep.data().stats.raids`、`lob.hero_def(id)` | RP：`Profile.hero_ids()`（= HeroDefs 里的全部 id，全部免费）、`HeroDefs.def_of(id)`；「第一次入境」改看 Profile 自己的局数，没有就删 |
| 375-382 `_sync_hero_btns` → `ep.hero()` | | RP |
| 385-399 `_pick_hero` → `ep.set_hero(id)`，主城里再 `player.set_hero(id)` | | RP：`Profile.set_hero(id)` |
| 409-436 `_use_meta` / `open_abode` | | 把 EX_LOBBY 分支去掉（见上）|

## 4. player.gd（英雄这层，和 ex 存档无关，但决定「不做强弱」）

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 37 `HeroDefs` preload | | KEEP |
| 107-119 `regen_k` / `lethal_fn` / `_invuln_until` | 关卡钩子（extract_manager 设：重伤倒地、不回血）| KEEP（默认值就是老行为）；raid_manager 不设它们 → 和大世界一样直接陨落 |
| 445-500 `set_hero(id)` | 475 `realm_idx = HeroDefs.TIER`；476-480 用结丹那一档的 `Realm.LIST` 打底再叠 hero_def 的 realm；477 `mp = mp_max()`；464 `CS.heroes_on = id != ""` | **EDIT（英雄子系统负责）**：不再钉 TIER。用 `Realm.LIST[realm_idx]` 打底，只叠招式 / 外观那几项（art / 皮肤 / 兵器 / pose_map / kit）。遁速 / 闪现要么按境界走、要么按英雄乘一个系数；`set_realm` 也要再叠一遍 hero_def。`CS.heroes_on` 别再关掉 PvP 的境界差（或者主干上恒为 false）。要想清楚：set_hero 发 `realm_changed(realm_idx)`，main._on_realm_changed 会重建飞剑 |
| 505-506 `hero_base()` → `HeroDefs.BASE` 18 | 招式伤害基数 | EDIT：`CS.base(realm_idx)` |
| 546-600 `ex_level()` / `solid_at` / `solid_hit` | 没有物理碰撞的图（ex_level 的 solid_at/blocked/y_cap 那套契约）挡墙用 | KEEP（地图几何留着就要它；改个名更好，比如 `solid_level()`）|

combat_stats.gd:226-249 `heroes_on`（pvp_hit / pvp_cap_k 里抹平境界差）：EDIT，主干上 PvP 照老规矩看境界差 → `heroes_on` 不再由 set_hero 打开。awaken_fx.gd:153/197 也读它（觉醒配色）——那里得换成看 `player.hero_id`，免得改了 heroes_on 让觉醒配色跟着变。

## 5. remote_player.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 15、32、65-76、132-133、143-161 | 按对方的英雄建模型和兵器 | KEEP |
| 163-165、228-235 `hero_downed()`（flags 第 4 位 = 16）| 搜打撤的重伤倒地 | KEEP 无害（raid_manager 不置这一位）；以后想清理可以 DEL |
| 174-181 `_refresh` 名牌：英雄档写「名字 · 英雄」，**不写境界 / 等级** | | EDIT：境界又算数了 → 写「名字 · 英雄 · 境界 Lv.N」|

## 6. net.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 56-57、154、189、217、324-333 `map_id`：发现包 / 握手带地图，图不对就拒（`_deny`「这间房在别的禁地」）| 按地图分房 | **KEEP**：新图要做局域网同图，就靠它 |
| 105-107、349-376、484 英雄：`hero_changed` → `_hero_set`、名单里的 `hero`、`_my_hero()` | | KEEP |
| 311、416 `_ex_peer_gone(id)` | 放掉首领主人 / 天工师持有者 | DEL（连同 1080 的函数）|
| 565-568 状态包 flags | | KEEP |
| 907-960 `send_hit_res` / `_hero_fx`（英雄技能画面）| | KEEP |
| 1013-1034 `send_mob_dead` / `_mob_dead`：`lair <= -2` → `_ex_log_camp`；`raid.has_method("net_ex_mob_dead")` 分支 | raid_manager.gd:1862 本来就按 `-2 - cd` 编刷怪点；`_ex_log_camp` 只是给 `_ex_sync` 用 | DEL 1018-1019、1028-1029 的 `_ex_log_camp` 和 1031-1033 的 `net_ex_mob_dead` 分支（raid_manager 没有这个方法，本来就走 `net_mob_died`）|
| 1038-1435 「搜打撤（extract_manager）专用」整块：`EX_BOX_CD`、`EX_CAMP_KEEP`、`_ex_*` 表、`_ex_tab`、`_ex_raid`、箱子 / 门 / 首领 / 首领画面 / 救人 / 天工师 / 同步那一批 RPC（`_ex_box_claim`、`_ex_box`、`_ex_door*`、`_ex_boss_*`、`_ex_revive`、`_ex_doc_*`、`_ex_sync_req`、`_ex_sync`）、`ex_local_sync` | 只有 extract_manager 调（那边有 19 处 `net.ex_*`）| **DEL** 整块。注意：删 RPC 会改联机协议 → 局域网所有人都要换包（主干本来就要换）|
| 1436-1506 `_dx*`（场景破坏同步，destruct.gd）| 新图 + 擂台的破坏 | KEEP |

## 7. lan_presence.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 22、54、64-67 `EX_PROFILE` → `_exp`（取段位）| | DEL |
| 157-161 包尾多两项 `hero_id, rank` | | KEEP 包格式（rank 位固定发 -1，兼容别人的包），别再读 _exp |
| 268-277 `_label`：有英雄就写「名字 · 英雄 · 段位」，不写境界 | | EDIT：「名字 · 英雄 · 境界 Lv.N」（境界 / 等级本来就在包里）|

## 8. warmup.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 40-51 `EX_MOBS`（ex_mobs.gd）、`EX_PER_BATCH`、`EX_SHADERS` | | 看新图的怪最后用哪张表：raid_manager 刷 raid_data 的怪 → DEL `_ex_mob_list` / `_spawn_ex_mob`；还用 ex_mobs 的模型 → KEEP |
| 190-235 `_ex_mob_list` / `_spawn_ex_mob` | 新图的怪 | 同上 |
| 237-372 `_ex_fx`：首领弹幕（ex_boss）、边界幕（grid_world._build_boundary）、飘浮物（ex_level._build_motes）、苍鸿剑气 / 剑域 | | KEEP 边界幕 / 飘浮物 / 苍鸿（地图和英雄的）；ex_boss 不留的话就 DEL 首领弹幕那一块 |
| 373-505 `_cross_beam`、`_ex_mgr_fx`：撤离光柱、史诗掉落光柱、符珠、烟遁、三种箱子的 MultiMesh | 全是 extract_manager 现做的材质 | **DEL** |
| 288 `level.map_id == "lab"` 时边界幕用加法混合 | | KEEP |
| 511-535 tag "ex" 分层键 `ex:<图>:<英雄>` / `ex:hero:<英雄>` | | EDIT：新图走 `"raid"` 那条（第 5 步老的刷怪 / 掉落预热要 `raid.region/_spawn_mob` 这些 raid_manager 成员）+ 一个地图键 `map:<id>` 给 `_ex_fx` 的边界 / 飘浮物用 |
| 602-614 `legacy_mobs = not is_ex and raid != null and not raid.net_on()` | | 新图改走 raid_manager 后，这一条自然成立 |
| 836-860 管理器材质一批 + 新图的怪 + 天工师模型 | | DEL 管理器那批和天工师；怪看上面 |

## 9. minimap.gd

| 行 | 现在做什么 | 处理 |
|---|---|---|
| 17-19 注释 | | EDIT |
| 25 `const MapDef := preload("res://scripts/ex/map_def.gd")`（**硬 preload**）| `MapDef.layer_at(p3)` | KEEP map_def.gd，否则这里解析不过 |
| 129-130 点小地图 → `mgr.level.open_big_map()` | 新图的大地图 | KEEP（raid_manager 的 `level` 是 ex_level 时照样能用；没有这个方法的时候照旧只切范围）|
| 170-183 `mgr.level.map_tex(p3)` 固定底图模式 | | KEEP |
| 363-375 固定模式只画关卡点表里的 `"extract"` 撤离点（「随时开放、位置公开，照 DarkArea」）| | **EDIT**：新图跑 raid_manager 时，撤离要走老的那套（`mgr._extracts`，有探明 / 激活）。要么把 `if _fixed:` 那一支删掉、固定模式也走下面 `_extracts` 的老路，要么 ex_level 的 `map_marks` 别再给 "extract" |
| 385 `mgr.ex_col(kind)` | raid_manager 本来就有 `ex_col`（raid_manager.gd:2688）| KEEP |
| 412 `ss.map_marks()`（神识）| | KEEP |
| 501-640 `BigMap`（level.map_tex_layer / map_marks）| | KEEP |

## 10. scripts/ex 以外但依赖 ex 文件的其他地方

| 文件:行 | 现在做什么 | 处理 |
|---|---|---|
| player_plate.gd:11、26-27 `EX_PROFILE`、`EX_MAPS` | | DEL |
| player_plate.gd:64-71 `_ep`、`_ex_ok`、`_ex` | | DEL |
| player_plate.gd:294-310 ex 模式下藏修为弧，徽记写段位 | | 跟着 `_ex` 一起 DEL |
| player_plate.gd:353-366 `_ex_mode()`：主城或新图里为真 | | **DEL** → 一律走老的「战力 / 境界 / 修为」显示（RP）|
| player_plate.gd:369-381 `_apply_mode`：不是 ex 时 `_rebuild_shot(HeroSkin.player_key())` | 回门 0 换回默认皮肤 | **EDIT**：主干上英雄一直开着 → 头像一律按 `player.hero_def.skin` 拍（`_hero_info` 那段，404-412，拿来照用）|
| player_plate.gd:415-450 `_refresh_ex`：段位、灵石、`ex_data.rank_name` | | DEL（头像换皮那一小段挪进老的 refresh）|
| player_plate.gd:457-466 `refresh` 里的 ex 分支 | | DEL |
| destruct.gd:15、23、27 `preload grid_world`、40、97、288、384、408（`w is GridWorld`）| 新图真破坏 | **KEEP grid_world.gd**（硬 preload）|
| air_melee.gd:1409-1410、3570、4962；heroes/kit_shuanghua.gd:393 `player.ex_level()` | 挡墙 / 撞墙 | KEEP |
| air_melee.gd:4046 `lethal_fn` 接住致命伤 → 重伤 | | KEEP（raid_manager 不设它）|
| lab/mijing_level.gd:5-6、16 `EXMOBS_PATH`、1197-1200 | 秘境实验关借 ex_mobs 的怪表 | KEEP ex_mobs.gd（或者删 mijing 实验关）|
| lab/mijing_boot.gd:74 `_apply_combat_mode("ex")` | | KEEP（mode 统一后无所谓）|
| block_world.gd:199-200、318 | 给 grid_world 留的钩子 `_setup_content()` | KEEP |
| ink_style.gd:4-11 | 注释（提到 ex_hud / ExData.q_ink）| 注释，KEEP |
| hero_defs.gd:6、35-37 `TIER` / `BASE` | 英雄档钉死结丹 | EDIT（英雄子系统）|
| kit_base.gd:9、kit_yujian.gd:8 | 注释（set_hero 建 kit）| KEEP |
| arena_net.gd:186、arena_duel.gd:26/917/933 | 擂台握手带地图 / 英雄 | KEEP |
| hub_hall.gd:69-76 `GATES` | 门 0 sub「旧版大世界」；门 2/3 `"open": true, "level": "desert"/"lab"`，sub「搜 · 打 · 撤」| EDIT：门 0 sub 改回「搜 · 打 · 撤」/「主线」；门 2/3 sub 改成「元婴以上」；open 留 true（门槛在 main._on_hub_gate 判）。也可以加个 `"min_realm": 3` 字段，1929 行没到境界就 say 一句 |
| hub_hall.gd:185-186 `# _build_farm()` | 农场被关掉 | **恢复**：取消注释 |
| hub_hall.gd:249-251 | 离线闭关不再结算（删掉的是 `_settle_offline(Profile.take_boot_seen())`）| **恢复** |
| hub_hall.gd:1461 `_zone()` | 去掉了 `if 离 MED_POS 的距离 < MED_R: return "med"` | **恢复** |
| hub_hall.gd:1532 | 去掉了回到前台时的 `if _paused_at > 0.0 and active: _settle_offline(_paused_at)` | **恢复** |
| hub_hall.gd:1929-1935 门触发 | | KEEP（或者在这里判 min_realm）|

## 11. 自检

| 文件 | 依赖 | 处理 |
|---|---|---|
| scripts/ex/ex_selftest.gd（2278 行，`--level-test`）| extract_manager / ex_profile / ex_hud 一整套 | DEL（完整版留在 extraction-pvp 分支）。新写一个小的 `--hard-zone` 自检：没到元婴进不去、元婴能进、raid_manager 在跑、有刷怪点 / 搜点 / 神识、陨落回主城、两开同图 |
| scripts/ex/ex_hud_selftest.gd（独立的 `--script`）| ex_hud | DEL |
| scripts/ex/ex_lobby_selftest.gd（`--lobby-test`）| ex_lobby_ui / ex_profile | DEL |
| scripts/ex/ex_boss_selftest.gd（`--boss-test-ex`）| ex_boss / ex_mobs | 不留 ex_boss 就 DEL |
| scripts/ex/ex_level_shot.gd（`--level-shot`）| 有 2 处 `lethal_fn`（取景时防死）；看一眼它碰不碰 extract_manager | 改成只截地图的话 KEEP，不然 DEL |
| hero_selftest.gd | 129/627/655/755 `set_hero`；**137 `check(player.realm_idx == 2 and hero_base()==18)`**（结丹钉死）；488-518 挡墙测试要 `_enter_level("lab")`；654-657 拿 18.0 当伤害基数；671-707 重伤倒地（lethal_fn）| EDIT：137 和 654-657 改成跟存档境界走；进 lab 之前要先把境界设到 ≥3（test_mode 下可以 `player.set_realm(3)` / 改 Profile），不然会被元婴门槛挡住（门槛要是放在 `_on_hub_gate` 或 level_select，直接调 `_enter_level` 会绕过去，正好不受影响）|
| pvp_rules_selftest.gd:76 `p.set_hero(--pvp-hero-<role>=…)`（arena_selftest.gd:33-34 调用）| | KEEP；如果它数过「同境界封顶」，heroes_on 改了以后数字会变 |
| tsb_show.gd:96、105-106 `--tsb-level=<id>` → `_enter_level`；125 `set_hero` | | KEEP（截新图时同上，要先设境界）|

---

## 12. scripts/ex 里的文件：主干上的去留

| 文件 | 行数 | 结论 | 原因 |
|---|---|---|---|
| ex_profile.gd | 789 | **DEL** | 新存档 xiuxian_ex_profile.json；英雄选择挪进 raid_profile（`hero()` / `set_hero()` / `hero_ids()`）|
| ex_data.gd | 1668 | **DEL**（得先把 meta_kit / ex_item_view / meta_* 里对它的调用改掉）| 售卖物 / 段位 / 价格 / 掉落表 |
| extract_manager.gd | 4248 | **DEL** | 局内玩法换成 raid_manager |
| ex_hud.gd | 1653 | **DEL** | 局内 HUD 换成 raid_hud |
| ex_lobby_ui.gd | 1106 | **DEL** | 旧纸面板大厅，已经被 meta_ui 取代 |
| ex_item_view.gd | 336 | DEL，或者改接 RP | 全靠 ExData（q_color / value_of…）；meta_* 改成显示老物品（item_view.gd）的话就删 |
| ex_doctor.gd | 214 | **DEL** | 天工师营救，搜打撤专属 |
| ex_boss.gd / ex_worm.gd | 1798 / 389 | 先留着、待定 | 只有 extract_manager 用；raid_manager 有自己的巢穴首领。要留地图特色首领就得在 raid_camps / raid_manager 里接，否则 DEL |
| ex_mobs.gd | 272 | **KEEP** | mijing_level 和 warmup 在用；新图的怪模型表也可以从这里来 |
| ex_level.gd | 1284 | **KEEP + EDIT** | 地图几何、挡墙契约、大地图、Destruct.attach。24 / 201-215 改成建 raid_manager；992 `raid.env_damage`、1120、1229-1240 `raid.downed / result / hud` 要和 raid_manager 的成员对上 |
| grid_world.gd | 3047 | **KEEP** | destruct.gd 硬 preload；地形 / 边界 |
| map_def.gd | 646 | **KEEP** | minimap.gd、grid_world、ex_level 都硬 preload |
| ex_level_shot.gd | 563 | 待定 | 见第 11 节 |
| hero_select_ui.gd | 1257 | **KEEP + RP** | 只调了 ExProfile 的 `hero()` / `hero_ids()` / `set_hero()` 三个 → 换成 Profile；全部免费 |
| hero_doll.gd | 299 | **KEEP** | 不依赖 ex 存档 |
| meta_kit.gd | 648 | **KEEP + EDIT** | 用到 ExData 的 wearable / q_name / q_color / chip_fx / atk_mult / armor_dr 和 ExItemView → 换成老物品的品质色 / 名字 |
| meta_ui.gd | 626 | **KEEP + RP** | 只调了 ExProfile 的 `xianyu()` / `lingshi()` / `take_notice()`，还有 ExData；顶栏改成灵石（Profile）|
| meta_prep.gd | 805 | **KEEP 壳子 + RP**（工作量最大）| 用到 ExProfile 的 stash / bag / equipment / equip / unequip / move / sell / repair / wh_level / upgrade_warehouse / entry_check / in_raid，和 ExData 的 repair_cost / unit_value / … → 改接 abode_ui 用的 Profile 储物 / 佩戴 / 储物戒接口 |
| meta_shop.gd | 506 | **KEEP 壳子 + RP** | ExProfile 的 buy / buy_black / sell / sell_all_sellables / lingshi / xianyu，ExData 的 shop / make → 改接老坊市（abode_ui 坊市页 / Profile 的买卖）|
| meta_rank.gd | 248 | **KEEP 壳子 + RP** | 段位 → 改成「境界 / 修为」页（Profile.realm / cult / 战力；Prog）|
| ex_selftest / ex_hud_selftest / ex_lobby_selftest | — | **DEL** | |
| ex_boss_selftest | 639 | 跟着 ex_boss 走 | |

建议：留下来的文件挪出 `scripts/ex/`（比如 `scripts/maps/`：ex_level / grid_world / map_def / ex_mobs；`scripts/meta/`：meta_* / hero_select_ui / hero_doll），这样主干上 `scripts/ex/` 可以整个删掉。挪之前得把所有 `res://scripts/ex/...` 字面路径和 `.uid` 都对上（hud.gd:768/805、level_select.gd:25、minimap.gd:25、destruct.gd:27、warmup.gd:42、mijing_level.gd:16，还有 meta_* / hero_select_ui 里的 `SELF_PATH` / `PAGES` / `HERO_UI` 常量）。

## 13. raid_profile 要新加的接口（给 RP 的那些调用点用）

- `static func hero() -> String`（默认 `HeroDefs.DEFAULT`）、`set_hero(id) -> String`（错误原因，空 = 成功；全部免费，不检查解锁）、`hero_ids() -> Array`（HeroDefs 的全部 id）。存在 `data()["hero"]` 里，老存档没有这个键就当默认值。
- 用到的地方：main.gd:798-801、level_select.gd:336-399、hero_select_ui.gd（3 处调用）、player_plate.gd:404-412（`_hero_info` 的回退）。

## 14. 风险 / 没定的事

1. **英雄跟着境界走**是英雄子系统的事（player.set_hero:475-486、hero_base:505、HeroDefs.TIER/BASE、CS.heroes_on）。不改的话，主干上英雄在所有图里都钉在结丹，和用户说的「不做强弱、数值跟境界」冲突。set_realm 也得在英雄开着的时候把 hero_def 的覆盖项叠回去，不然渡劫升阶会把遁速 / 招式档冲回老表。
2. raid_manager 对英雄 kit 一无所知（raid_manager / raid_hud / meadow_level 里 `grep hero_id` 为空）。门 0 木兰草原以前走 `set_hero("")`，现在一律开英雄：需要验 raid_hud 的技能栏 / 触屏键（touch_controls.gd:153 英雄档用的是 kit 的四键）、飞剑阵（player.realm 的 swords 数在英雄覆盖里）、渡劫 / 结婴演出和英雄一起时有没有问题。
3. ex_level 上跑 raid_manager：raid_manager 默认关卡是 MeadowLevel + block_world（3456 米循环、`near()`、region、raid_search 固定搜点、raid_camps 刷怪点、神识扫的是地形 include）。新图是有边界的 GridWorld，**这一块的适配归地图 / 管理器子系统**；我这边只能指出接口：ex_level.gd:24/201-215 建管理器的地方，ex_level 要给出 raid_manager 读的那些成员（`world`、`spawn_point`、地区 / 点表、`exit_requested`）。
4. 删掉 net.gd 的 `_ex_*` RPC 会改协议，主干的包和 extraction-pvp 分支的包在局域网里不能混着连（发现包 / 握手按 map_id 分房，至少不会进错房；但同是 mulan 的房间两个版本会撞上）。建议握手时加一个协议版本号。
5. GM 改境界键（main.gd:655）：cbb6ec9 之前正式游玩也能用；现在只在 test_mode 下能用。要恢复哪一种，需要用户定。
6. hub_hall 的修炼场打坐 / 离线闭关 / 一键服丹（hall_pills）是在 cbb6ec9 里跟着「砍吃丹挂机」一起删的，不在 scripts/ex 里，很容易漏。主干既然回到吃丹修仙，**要一并恢复**（第 1、10 节已列出）。abode_ui.gd 在 cbb6ec9 里改了 292 行，看起来是另一个会话做的手机重排，不是砍功能，但最好对着 492a1fc 核一遍丹房 / 坊市页还在不在。
7. 元婴门槛如果只放在 `_on_hub_gate`，自检直接调 `_enter_level("lab")` 会绕过去（自检反而方便）；但入境页 `open_level` 也能从别处进，所以 level_select 的 go 按钮也要挡一次。联机时房主到了元婴、加入的人没到：匹配只按 map_id 进房，所以门槛必须在本机入境前判，不能靠房主。
8. minimap.gd:363-375 固定底图模式会画「随时开放」的撤离点：新图换成老规则后，不改这里会画出不存在的撤离点。
