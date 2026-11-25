# 主干解耦契约（2026-11-25，「搜打撤玩法」会话定）

背景：完整的搜打撤版本已经存到 `extraction-pvp` 分支（5c25796，已推送）。主干 `raid-block-world` 回到**纯吃丹修仙增量挂机**，同时带一部分搜打撤内容。
用户原话要点：
- 新的两关（沙海古墟 / 天工秘所）保留，**元婴以上才能去**，是难度更高的区域。
- 新两关里跑吃丹修仙那套：资源分发、刷怪、神识、撤离；有局域网同图；**死了跟大世界一样**。
- 英雄之间只有技能、外观、战斗方式的差异，不分强弱；**主干全部免费解锁**；数值跟着境界走。
- 主城「备战 / 坊市 / 段位」复用界面外壳，改成修仙版入口。
- 搜打撤那套数值、存档、玩法从主干删掉。
- 主角、空战、英雄技能、联机、方块世界这些通用能力，两边以后互相搬。

调研报告在 `_tasks/decouple/reports/`：A_raidloop / B_exmaps / C_heroes / D_metaui / E_economy / F_callsites。动手前先读和自己相关的那几份，行号以报告为准，但动手前要重新核对。

## 0. 总规矩（每个代理都遵守）
- **只改分到自己名下的文件**（见第 6 节）。要改别人的文件，写进报告的「需要别人改」，不要自己动手。
- **文件路径一律不挪**（scripts/ex/ 下要保留的文件留在原地），这样两条分支以后搬修补时路径一致。
- 改文件只用 Edit；**不要用 Write 覆盖已有文件**，别的会话可能也在改。新文件可以用 Write。
- 第一次改某个文件之前，先备份到 `_tasks/decouple/backup/<文件名>.<你的代号>.txt`（不要用 .gd 后缀，否则 Godot 会当成脚本去解析）。
- 编译检查：
  - 单个文件用 `Godot --headless --path . --check-only --script res://scripts/xxx.gd`。
  - 整个工程用 `--headless --path . --quit`，或者跑自检。这两种可以几个代理同时跑。
  - **只有 `--import` 要先拿锁**（新加了带 class_name 的脚本、或者改了 class_name，都要 import 一次才会更新类缓存）：`mkdir _tasks/decouple/godot.lock`，成功才算拿到锁，失败就等 20 秒再试；用完 `rmdir`。
  - Godot 路径：`D:/ugc-ai/tools/godot/Godot_v4.7.2-stable_win64_console.exe`
- **不要关、不要杀**任何正在跑的游戏窗口或服务器（用户可能正在玩）。截图只看 `_shots/preview` 下的 JPG，不要读 `_shots` 下的 PNG。
- 不要 git commit / push / 切分支。
- 新写的汉字不用你们管字体，最后由负责人统一跑 font_check / 毛笔字子集。

## 1. 战斗数值：英雄跟着境界走（W1）
- `player.set_hero(id)` 不再把 `realm_idx` 锁成 `HeroDefs.TIER`。`realm = Realm.LIST[realm_idx].duplicate()`，上面只叠英雄的**外观键**：`lines, col_a, col_b, style, motes, width, swords`，再加 `art`（取英雄 def 里的）和 `mode = LIGHT`。也就是说，英雄从炼气起就能用空战技能。
  - 炼气本来就能飞，见记忆 terrain-movement-rules。
- 移动：`speed / blink / blink_spd / boost / rise` 跟境界走，速度下限是 `max(realm.speed, 28)`，三个英雄都一样。
- `set_realm()` 在英雄模式下也要生效（重新叠外观键）。`hero_base()` 返回 `float(realm["dmg"])`。
- 删掉 `combat_stats.gd` 里 `heroes_on` 抹平 PvP 境界差的两段。PvP 回到老规矩：每差一档 ×1.08，上限照旧。
  - `CS.heroes_on` 可以继续留着，只给画面判断用。
- 删掉 `enemy_dummy.gd` 里 `HERO_PVE_UNIT` 那条英雄专用的飘字路径。
- 删掉 `hero_defs.gd` 里的 `BASE`。`TIER` 只剩「展台上穿哪档衣服」这一个用途，注释改一下；展台也可以改成按玩家境界穿。
- 三个英雄之间不加任何强弱倍率。
- 保留 `set_hero("")` 老角色路径，代码里能用，但界面上不露出来。

## 2. 存档：raid_profile 新增接口（W1 实现，W3 / W2 照着调）
`scripts/raid_profile.gd`（`user://xiuxian_profile.json`）里：
- `_fresh` 加 `"hero": HeroDefs.DEFAULT`，`_fix_types` 里校验这个键，不认识的 id 回落到 DEFAULT。
- `static func hero() -> String`
- `static func hero_ids() -> Array`：等于 `HeroDefs.ids()`，全部免费。
- `static func set_hero(id: String) -> String`：成功返回 ""；局内返回 `RAID_LOCK`；不认识的 id 返回 "未知英雄"。成功要存盘。
- `static func add_lingshi(n: int) -> void`：n 可以是负数，结果不低于 0，存盘。
- `stats` 字典加 `kills`、`pk_kills`、`arena_wins` 三个键（缺了就补 0），再加 `static func add_stat(key: String, n: int = 1) -> void`。
- 不升 VER。`_load` 只认 `_fresh` 里有的键，所以新键加进 `_fresh` 就够了。
- 已有接口不改签名：`realm() / lingshi() / equip / unequip / pack / unpack / to_ring / from_ring / sell / sell_junk / buy / upgrade_ring / craft / can_craft / kit_ok / take_kit / stash_slots / wealth / stats / notice / in_raid / begin_raid / end_raid / boot_realm`。
- 主角进任何关卡、主城时：**先** `set_realm(Profile.boot_realm())`（照老写法），**再** `set_hero(Profile.hero())`。main 里 `_apply_combat_mode` 只剩这一条路（W3 改 main）。

## 3. 新两关的分档（W2）
在 map_def 里给每张图加 `"zone"` 数据。区域档复用老的 0..4，**Prog 和 CS 的表一律不改**（progression.gd 归「数值体系设计」会话）：

| 图 / 层 | 借用区域档 ri | 难度倍率 hp / atk | 掉落加成 bonus | 心得倍率 |
|---|---|---|---|---|
| 沙海古墟 地面 | 2（元婴） | ×1.2 | +0.3 | ×1.2 |
| 沙海古墟 地下洞窟 | 3（化神） | ×1.2 | +0.3 | ×1.2 |
| 天工秘所 地面 / 院子 | 3（化神） | ×1.35 | +0.5 | ×1.35 |
| 天工秘所 地下室 | 4（炼虚~大乘） | ×1.35 | +0.5 | ×1.35 |

- `min_realm = 3`，就是元婴（realm.gd:43）。
- 深度只按位置算：地面离最近出生点越远越深，封顶 0.8；地下层 +0.25；钥匙房 / 首领场地算 1.0。**不看昼夜、不看人数**，这样联机两边算出来一样。
- 倍率只按 (map_id, 层) 决定，联机木偶那边也用同一个公式。

## 4. 新两关里的玩法（W2）
**撑起来的方式**
- `ex_level` 挂 `raid_manager.gd`，不再挂 extract_manager。几何差异做成一层转接（报告 A 第 2 节的 geo）：大世界那份直接透传 Data / Prog，行为一字不变；新图那份由 ex_level / map_def 提供数据。
- 循环世界的换像（`_reimage`）只在 `geo.loop` 为真时做。

**刷怪点 / 搜点 / 撤离**
- 刷怪点：`raid_camps` 加一种「点表模式」，用 `points("camp")`，照 extract_manager 里 `Camps` 内部类的写法；y 用 `floor_at`。75 秒复活、联机谁建，都跟大世界一样。
- 搜点：箱子按种类换成老的搜点。

  | 新图的箱子 | 老搜点 |
  |---|---|
  | supply | 藏物陶罐 |
  | weapon | 古修坟冢 |
  | med | 灵药圃 |
  | 钥匙房里的箱子 | 禁制宝库（门常开） |
  | 首领场地边 | 宗门宝罐 |

  用固定种子抽稀。y 用点自己带的高度，**不要再贴地**，否则楼上的箱子会沉下去。
- 撤离：`points("extract")` 当古传送阵，每 300 秒轮换一次。沙漠 4 座里亮「1 免费 + 1 灵石阵」，研究所 8 座里亮「2 免费 + 1 灵石阵」。裂隙、破界符照旧，个人限时 1200 秒照旧。

**首领**
- 每个 `points("boss")` 当一个巢穴，走近自动刷出，不用祭台召唤。
- 刷出来后挂 ExBoss 技能大脑，让 ExBoss 支持「相对量」：老分支 `pts_k = 1`，行为不变。
- 掉落用老巢穴首领那套：`_loot` + 破境丹残片 + 霸主精魄（按 OVERLORD_P 概率）。
- 首领归属走房主仲裁，保留 net.gd 里 `ex_boss_*` 那几条 RPC。
- 巢穴编号用 lid，不能再等于 region：沙漠洞窟里两个首领共用一个区域档。

**怪**
- 怪的定义追加到 `Data.MOBS` 后面，或者用 `_mob_def(i)` 统一取。编号只能往后加，不能插队，因为编号是联机协议的一部分。
- 数值走老公式：`SHAPE_BASE × def.hp × HP_CONV × CS.mob_s_hp(ri, lv)`，再乘第 3 节的难度倍率。
- 两张图都给怪设 `block_fn = level.blocked`，不让怪穿墙。

**死亡和结算**
- 跟大世界完全一样：没有重伤 / 自救 / 医生；陨落丢背包和法宝，储物戒保留；联机时原地留一个储物袋。
- ex_level **不要**设 lethal / regen_k 那些钩子。
- 新图不做：天工师营救、夜袭怪潮、读条开箱 / 开门、救队友。昼夜画面保留。

**其他接线**
- 气氛：新图不调 `_blend_atmosphere`，ex_level 自己管天色。标题、地名用图名。
- 小地图：固定底图模式下画 `raid_manager._extracts` 里亮着的那几座，不再画常亮撤离点。`raid_hud` 的地名取自 geo。
- 境界守卫：ex_level 进图时如果境界不到元婴，提示后直接退出。主城门口另外有一道拦截，W3 做。
- net.gd：删掉 `_ex_*` 里箱子、门、救人、医生、同步那几块，以及 `_ex_peer_gone` / `_ex_log_camp` / `net_ex_mob_dead` 分支；保留 `ex_boss_*`、map_id 分房、英雄名单、`_dx*` 场景破坏同步。
- warmup.gd：删掉搜打撤管理器专用的那几样（撤离光柱、箱子、符、医生）；边界幕、尘雾、苍鸿特效、新图怪保留。

**自检**
- 新写 `scripts/xiu_map_selftest.gd`。main 里的 `--level-test` 由 W3 改成加载它，参数是 `--level-test desert|lab`。
- 要测的内容：境界设为 3 进图；刷怪点建出了怪，怪的血量、攻击、等级和第 3 节对得上；搜一个点能出老物品；首领刷出并且能被打死；撤离成功后背包进仓库；陨落时丢背包；进图记录的帧耗。
- 有余力再测双开同图（两个进程，端口要和用户正在玩的隔开，不能抢鼠标，见记忆 lan-presence）。

## 5. 主城和界面（W3）
**主城大厅 hub_hall**
- 门 0 木兰草原恢复成主线（副标题写「主线大世界」）。
- 门 2 / 门 3 标「元婴可入」，境界不到时门半透明；走进去提示「X凶险 · 元婴期方可入内（你现在是Y期）」，并且不放行。main 里的 `_on_hub_gate` 也加同一道拦截。
- 恢复：`_build_farm()`、离线结算 `_settle_offline`（两处）、打坐区 "med"。
- 对比 `492a1fc..cbb6ec9` 的 diff，把因为转搜打撤砍掉的修仙挂机功能找回来（main.gd 里的 hall_pills 一键服丹、hub_hall、hud、level_select 等）。分到你名下的文件你自己恢复；在别人文件里的，写进报告。

**四个入口**（外壳、动画、布局都复用）
- 英雄：hero_select_ui 改用 `Profile.hero_ids / hero / set_hero`。
- 备战：
  - 左边是英雄、3 个佩戴法宝格（陨落即失）、4 个随身丹符格，下面是战力（`CS.power(realm, lv, Items.fx_total(gear))`）和境界 / 层 / 修为条。
  - 中间是仓库（60 格，可叠放）和储物戒两页，筛选：全部 / 法宝 / 丹药 / 破境 / 灵草 / 灵材 / 符箓。
  - 物品操作：佩戴、随身带上、收进储物戒、服下、卖出、取下 / 放回 / 取回。「服下」和 hall_pills 用同一份吃丹逻辑。
- 坊市：
  - 商品来自 `Items.shop()`，用 `Profile.buy` 买；可以买 1 个或 10 个。
  - 丹房用 `Items.recipes()` + `Profile.craft`；能升级储物戒。
  - 出售：点一下卖一件，另有确认后的 `sell_junk`。
  - 只用灵石，去掉仙玉和黑市。
- 段位 → **境界**：
  - 八境徽记，显示层和进度、瓶颈要求（破境丹 + `Prog.break_cost`）。
  - 战绩卡：入境 / 撤离 / 陨落 / 单局最高 / 擂台胜 / 身家。
  - 一条境界路径，元婴那一格写「开放沙海古墟 / 天工秘所」。
  - dock 上的字改成「境界」。
- meta_ui 外壳：钱用 `Profile.lingshi()`，通知用 `Profile.notice`；仙玉那块换成境界徽记。`LEGACY` 编号改成老洞府那套。
- meta_kit：
  - 战力改用 `CS.power`。
  - 品质色用 `Data.TIER_COLORS`，图标用 `UiStyle.icon(Items.icon_name(it))`，角字用 `Items.tier_word`，去掉耐久条。
  - 不再引用 ExData。
- 入境页 level_select：
  - LEVELS 里 `"ex": true` 改成 `min_realm: 3, hard: true`，文案改成修仙规则。
  - 删掉 EX_* 和 `_ex_ctx`；`_entry_err` 改成境界拦截。
  - 每张图都显示英雄那一排。
  - `open_abode` 默认打开修仙版 meta_ui。
- hud：
  - 删掉 `_ex_rank_banner` 和 EX 常量。
  - INTRO_LINES 改成修仙版。
  - F1 帮助改用 raid_hud 的键位。
- main：
  - `_apply_combat_mode` 按第 2 节改。
  - 删掉 `_ex_mode` 和它对 GM 键、退格重置的拦截。
  - 删掉 `--lobby-test` / `--boss-test-ex` 探针。
  - `--level-test` 改成加载 `res://scripts/xiu_map_selftest.gd`，见第 4 节。
  - 新图 warmup 用的 tag 跟着 W2 的做法走。
- 界面测试：`_tasks/ui_kit` 下 meta_ui_test / meta_game_test / abode 等测试，以及 hub 自检的预期值，跟着改。

## 6. 文件归属
**W1（英雄 + 存档）**
- player.gd：只动 set_hero / set_realm / hero_base 一带。
- combat_stats.gd、hero_defs.gd、enemy_dummy.gd、raid_profile.gd
- scripts/ex/hero_select_ui.gd、scripts/ex/hero_doll.gd
- player_plate.gd：删掉 ex 模式，恢复老的战力 / 境界 / 修为显示，头像跟着英雄皮肤。
- remote_player.gd：名牌带上境界和层。
- lan_presence.gd：广播境界，不再广播段位。
- arena_duel.gd：只有确实需要时才动。
- hero_selftest.gd、pvp_rules_selftest.gd

**W2a（新图跑修仙玩法：管理器这一侧）**
- raid_manager.gd、raid_camps.gd、raid_search.gd、raid_data.gd、raid_hud.gd、minimap.gd
- 新文件 scripts/raid_geo.gd、scripts/ex/ex_geo.gd（名字可以按需要调整）
- scripts/ex/ex_level.gd、scripts/ex/map_def.gd
- 新文件 scripts/xiu_map_selftest.gd

**W2b（首领 / 怪定义 / 联机 / 预热）**
- scripts/ex/ex_boss.gd、scripts/ex/ex_worm.gd、scripts/ex/ex_mobs.gd、net.gd、warmup.gd
- W2b 给 W2a 的接口（照这个写，两边同时开工）：
  - `ExBoss.attach(mob, boss_id, arena, opts)`：opts 和 extract_manager 现在传的一样，另加 `pts_k: float`，默认 1.0，表示「技能点数 → 原始伤害」的换算：原始伤害 = 点数 × pts_k。主干 raid_manager 传 `pts_k = mob.atk / max(1, ExMobs.def(id).atk_pts)`，也就是技能点数等于 atk_pts 时，和普通一击一样重。
  - 血量缩放改成相对量：刷出时记 `_hp_one`，以后按 `_hp_one × ExMobs.players_k(n)` 缩放。搜打撤分支下 pts_k = 1、算式相等，行为不变。
  - ExBoss 里会写到 mob 血量 / 攻击的地方都不能再用绝对点数。
  - ex_mobs 的 def 补上老体系用的 `hp` / `atk` 倍率（报告 B 第 X1 条）。`IDS` 顺序不动。
  - 首领的联机画面：保留并整理 net.gd 的 `ex_boss_fx / ex_boss_claim / _owner / _release / _dead`，回调名照旧（`raid.net_ex_boss_fx` 等），W2a 在 raid_manager 里实现这些回调，照 extract_manager 搬。
  - 在 `_tasks/decouple/W2b_api.md` 里写清楚最终接口，W2a 动首领那块之前先读它；读不到就照上面这几条写。

**W3（主城和界面）**
- main.gd、hud.gd、level_select.gd、hub_hall.gd
- scripts/ex/meta_ui.gd、meta_prep.gd、meta_shop.gd、meta_rank.gd、meta_kit.gd、ex_item_view.gd
- hall_pills.gd、abode_ui.gd
- _tasks/ui_kit 下的测试

**谁都不碰**
- scripts/heroes/*、air_melee.gd（归「格斗专项」和「修仙空战系统重构」会话）
- progression.gd（归「数值体系设计」会话）
- 字体文件
- extract_manager.gd / ex_hud.gd / ex_profile.gd / ex_data.gd 等待删文件：第二阶段统一删。

## 7. 第二阶段统一删除（W4）
- 删：ex_profile、ex_data、extract_manager、ex_hud、ex_lobby_ui、ex_doctor、ex_selftest、ex_hud_selftest、ex_lobby_selftest（连同 .uid）。
- ex_item_view、ex_boss_selftest、ex_level_shot：看第一阶段改完以后还有没有人用，再决定删不删。
- 保留：grid_world、map_def、ex_level、ex_mobs、ex_boss、ex_worm、hero_doll、hero_select_ui、meta_*，以及老的 scripts/kit_canghong.gd（还有地方 load 它）。
- 删完以后全仓 grep：`ExProfile|ExData|ex_profile|ex_data|extract_manager|ex_hud|ex_lobby|ex_doctor`，残留要清零（注释除外）。
