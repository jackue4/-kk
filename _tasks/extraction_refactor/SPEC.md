# 搜打撤 PvP 重构规格（v1 核心框架）

负责人：主会话（下称「主控」）。日期 2026-11-24。本文件是所有实现代理的唯一依据；有冲突以本文件为准，本文件没写到的由实现者按「对标 DarkArea + TSB 手感 + 现有项目规矩」自行决定，并在交付报告里写明。

参考资料（都在 `_tasks/extraction_refactor/`）：
- `recon/xx_flow.md` 主流程 / 大厅 / 选关 / 自检机制；`recon/xx_raid.md` 现有搜打撤可复用组件和联机契约；`recon/xx_combat.md` 战斗系统和英雄抽象方案；`recon/xx_econ.md` 存档 / 物品 / 修仙功能拆法；`recon/xx_world.md` 方块世界做有边界地图；`recon/assets.md` 素材清单。
- `recon/da_tables.md` + `darkarea_data/{sellables,gear,consumables,loot_tables,economy}.json`：DarkArea 的完整数值表（每条带出处）。
- `recon/da_levels.md` + `darkarea_data/levels.json`：DarkArea 沙漠行动 / 研究所两张图的全部坐标和规则。

---

## 0. 目标与本轮范围

把游戏核心改成「搜打撤 PvP」，对标 DarkArea：资源产出、核心循环、货币数值、玩法规则照搬；射击换成 TSB 式英雄格斗（保留现有空战底盘）。本轮交付**核心框架**，并在两张新图里跑通一整局：

1. **英雄**：英雄表 + 两个英雄——老角色「御剑」（现有阿拉灯 + 拳脚飞剑那套，机制按扁平数值调整）和新英雄「苍鸿」（TSB 式近战剑修）。战斗数值不再随境界变化。
2. **局外经济**（新存档）：灵石 / 仙玉、仓库（12→90 格）、商人回收、坊市（买装备 / 药 / 符 / 法宝）、黑市（仙玉）、装备栏（兵刃 + 四件法衣 + 三个法宝）、背包备战、段位（按累计带出价值）、英雄选择。
3. **局内规则**：禁带售卖物入场、出生无敌、900 秒限时、撤离点读条、搜箱（武器 / 物资 / 医疗箱，180 秒复原）、钥匙房、小怪、Boss、重伤倒地 + 强心丹、死亡惩罚（扣灵石 + 命牌 + 随机 2 堆售卖物 + 法宝全掉）、护宝符、昼夜、研究所营救天工师。
4. **两张新图**：「沙海古墟」（对标沙漠行动，地面 + 地下洞窟）和「天工秘所」（对标研究所），从大厅门 2 / 门 3 进入，局域网联机可用。
5. **剔除**：大厅一键服丹、修炼场打坐 / 渡劫、离线闭关、灵田农场入口、GM 改境界键（非自检）、结婴演出触发。

**不在本轮**（写进交付报告的「下一步」）：枪械升级 / 赋能对应的兵刃升级、天赋、称号 / 图鉴、悬赏令、抽奖、签到、黄金古墓 / 市中心、木兰草原老大世界改成新经济（本轮门 0 保持旧版原样可玩）、真服务器。

---

## 1. 架构与文件归属

### 1.1 新文件（全部 `extends`，不写 `class_name`，互相用 `const X := preload(...)`；被主流程调用前，别的脚本只能用 `load()` 引用）

| 文件 | 归属 | 内容 |
|---|---|---|
| `scripts/ex/ex_data.gd` | D 经济 | 全部数值表 + 物品构造 + 掉落抽取（第 3 节） |
| `scripts/ex/ex_profile.gd` | D 经济 | 新存档 `user://xiuxian_ex_profile.json`（第 3.8 节） |
| `scripts/ex/ex_item_view.gd` | D 经济 | 新物品的格子 / 拾取卡片 / 详情文字（照 `item_view.gd` 的样子） |
| `scripts/ex/ex_lobby_ui.gd` | D 经济 | 大厅界面：备战 / 仓库 / 商人 / 坊市 / 黑市 / 英雄 / 段位 页签 |
| `scripts/ex/map_def.gd` | W 地图 | 两张图的布局数据（第 5 节） |
| `scripts/ex/grid_world.gd` | W 地图 | 数据驱动的方块世界（继承 block_world.gd 或自写分块网格，W 决定） |
| `scripts/ex/ex_level.gd` | W 地图 | 关卡节点：环境 / 太阳 / 世界 / 主角落脚与挡路 / 洞窟进出 / 边界 / 小地图底图 / 昼夜光照；实现第 1.3 节的「关卡契约」 |
| `scripts/ex/extract_manager.gd` | E 规则 | 局内玩法管理器（第 4 节），实现 net.gd 的鸭子类型契约 |
| `scripts/ex/ex_hud.gd` | E 规则 | 局内界面：倒计时、拾取卡、背包、读条、重伤、结算、播报（可借 raid_hud 的部件） |
| `scripts/ex/ex_boss.gd` | E 规则 | Boss 技能大脑（挂在 raid_mob 首领上），第 8 节 |
| `scripts/ex/ex_doctor.gd` | E 规则 | 营救天工师 NPC |
| `scripts/ex/ex_selftest.gd` | E 规则 | `--level-test=desert|lab` 整局自检 |
| `scripts/hero_defs.gd` | H 英雄 | 英雄表 |
| `scripts/kit_yujian.gd` / `scripts/kit_canghong.gd` | H 英雄 | 两个英雄的技能脚本 |
| `scripts/hero_selftest.gd` | H 英雄 | `--hero-test` 自检 |

### 1.2 改动的老文件（一个文件只有一个归属者；别人只读）

| 文件 | 归属 | 允许的改动 |
|---|---|---|
| `main.gd`、`hub_hall.gd`、`level_select.gd`、`net.gd`（地图编号 / 握手部分） | 主控 | 第 7 节；**已在派工前改好** |
| `player.gd`、`air_melee.gd`、`air_moves.gd`、`air_caster.gd`、`combat_stats.gd`、`remote_player.gd`、`touch_controls.gd`、`combat_poses.gd`、`hero_skin.gd`、`voxel_hero.gd`、`fighter_rig.gd`、`awaken_fx.gd`、`gate_array.gd`、`sword_manager.gd`、`net.gd`（只加英雄 / 招架相关 RPC） | H 英雄 | 第 6 节 |
| `block_world.gd`、`minimap.gd` | W 地图 | 只加可覆盖的钩子 / 固定底图模式，不改现有行为（老大世界必须照旧） |
| `raid_mob.gd` | E 规则 | 只加可选的挡墙回调 `block_fn`、可选的技能大脑挂点；默认行为不变 |
| `player_plate.gd`、`hud.gd`（大厅里的货币 / 段位显示、洞府按钮改开新界面） | D 经济 | 第 3.9 节 |

**并发规矩**：工作区里有别的会话未提交的改动。动一个老文件前先 `git diff` 看一眼它现在的状态；只改自己归属的文件；别的代理正在改的文件导致 Godot 跑不起来时，等几分钟再跑，别去修别人的文件，实在卡住就在报告里写明。**不要 git commit / push**。备份放 `_tasks/extraction_refactor/backup/<文件名>.txt`（别用 .gd 后缀，Godot 会扫描）。

### 1.3 关卡契约（ex_level.gd 必须提供；main.gd 和 net.gd 鸭子类型调用）

- `signal exit_requested`；属性 `player / cam / font / mobile / net / map_id`；`raid`（= extract_manager 实例，可为 null）；`env / sun`；`world`。
- `spawn_point() -> Vector3`、`spawn_yaw() -> float`、`prewarm() -> float`（可 await）、`stats_text() -> String`、`ground(x, z) -> float`。
- `world` 要有：`dug_table() -> Dictionary`（可恒为空）、`dig(p, r, f)`（空实现）、`map_colors / map_cells`（若小地图走固定底图可给空实现，但要和 minimap.gd 对上）；`level.remote_blast(p, r)`（空实现）。
- `_exit_tree` 还原：`Vfx.terrain_hook`、`cam.floor_fn / occl_fn`、`cam.cam.far`、景深、`player.ground_ref`、`player.bound = Player.BOUND`，以及自己改过的任何 static。
- 另给 E 用：`solid_at(p: Vector3) -> bool`、`blocked(from: Vector3, to: Vector3) -> bool`（怪挡墙）、`layer_of(p) -> String`（"surface" / "cavern"）、`teleport_links`、`points(kind) -> Array`（读 map_def 的点表）、`is_night() -> bool`、`day_phase() -> float`。

### 1.4 主角战斗档位（所有新模式通用）

- 进新图 / 在大厅：`player.set_hero(hero_id)`（H 实现），数值档固定在境界 2（结丹：COMBAT / skill_g / MP_UNITS 全是 1.0 基准），招式档 `art` 等由英雄表给。
- 进门 0 木兰草原（旧版）：照旧 `player.set_realm(Profile.boot_realm())`，英雄 = 御剑、不覆盖任何东西（主控在 main.gd 里切换）。

---

## 2. 公共约定（每个代理必须遵守）

- Godot 4.7.2，GDScript；`:=` 不能推断 Variant（`var x := dict["k"]` 编译失败，写成 `var x: float = ...`）；无 autoload；static var 当单例，改了要在退出时还原。
- 运行：`python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1280x720 -- <参数>`（隐藏真窗口，可截图；日志 `<前缀>_out.txt / _err.txt`）；网页那套渲染加 `--rendering-method gl_compatibility`，手机档再加 `--touch`。只编译检查：`Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit` 看报错（可执行文件位置见 run_hidden.py）。新拷进 GLB / PNG 后先 `--headless --import`。
- 截图：用 `main._shot(tag)`（存 `_shots/<tag>.png` 和 `_shots/preview/<tag>.jpg`）。**只看 `_shots/preview/*.jpg`，绝不打开 `_shots/*.png`**。
- 自检参数会让 `Profile.test_mode()` 生效（测试存档、每次清空）；新存档 `ex_profile.gd` 同样要有 test_mode 隔离（测试档 `user://xiuxian_ex_profile_selftest.json`）。正式游玩会带的参数要进 `PLAY_ARGS`。
- 界面：宣纸面 + 细墨线 + 一点朱砂，一律用 `ui_style.gd` 的样式（`scroll / plaque / slot / style_button / style_primary / seal`），手机优先（触屏大按钮、正式关卡里别满屏按钮和键位提示），字体走 `UiStyle.kai()`。**新出现的汉字**（按钮 / 界面 / 物品名）跑 `python -I _tasks/ui_kit/font_check.py --patch` 再 `--import` 补进随包字体，否则网页上显示方框。
- 画面：冲击别用全屏闪屏 / 黑白滤镜；空间破碎只碎冲击点周围；普通技能出手不切特写、不加慢动作；网页端兼容渲染器顶点色要过 `MeshLib.vcol()`，并进方块网格的颜色不用转；铺满屏的着色器查烘好的噪声贴图；新着色器进 `warmup.gd` 预热（找主控加，不要自己改 warmup）。
- 大数显示用 `scripts/num_fmt.gd`（万 / 亿 / 万亿，不用「兆」）。
- 联机：只有局域网（ENet，net.gd）。网页版没有真人联机，单机必须完整可玩。
- 每个代理交付：一份报告 `_tasks/extraction_refactor/reports/<代号>.md`（做了什么、文件清单、接口、自检命令和结果、截图 jpg 路径、已知问题、给下一步的建议）。

---

## 3. 局外经济（D：ex_data.gd / ex_profile.gd / ex_item_view.gd / ex_lobby_ui.gd）

数值照 `darkarea_data/*.json` 搬，单位「金币」→「灵石」，「钻石」→「仙玉」。下表只写要点和改动，原始数在 JSON 里。

### 3.1 品质 8 档

`Q = [普通, 精致, 卓越, 传奇, 史诗, 神话, 永恒, 天启]`，下标 1..8（0 不用），颜色白 / 绿 / 蓝 / 紫 / 橙 / 红 / 彩（七彩流光，界面里用渐变或轮换色）/ 天启（金白）。`ex_data.Q_NAMES / Q_COLORS`。

### 3.2 物品字典（能直接写 JSON）

```
{ "id": String（表里的键）, "kind": "sell"|"weapon"|"armor"|"chip"|"med"|"revive"|"throw"|"key"|"tag"|"ward",
  "name": String, "q": int 1..8, "value": int（回收价，灵石）, "n": int（堆叠数，默认 1）,
  …按 kind 的字段（见下）, "dur": int（法宝当前耐久）, "dur_max": int }
```
- 堆叠：`sell / med / revive / throw / key / ward` 同 id 叠一格，上限照 DarkArea（售卖物按格子算；药 10 一组的照商店组数，简单起见统一 `STACK = 20`，售卖物 `STACK_SELL = 10`）；`weapon / armor / chip / tag` 一件一格。
- 每格占 1 格（不做 2 格物品）。

### 3.3 售卖物（kind=sell）

- 94 件 Type=1 全搬（`sellables.json`），**改成仙侠名**（古玉、金器、古卷、灵晶、兽骨、丹炉、星砂、龙骨、天书……按原价值档起名，原名留 `da_name` 字段），价值、品质、所在掉落池不变。古墓专属 / Boss 专属 / 箱子专属标签保留。
- 命牌（身份牌）：`kind=tag`，价值 5000，只在死亡时生成，可卖。
- 卖给商人：`value × n`（暂无称号加成）；品质 ≥5 二次确认；品质 8 不可卖。
- 图标：先用 `assets/ui` 现有图标按类别挑（宝石类 → `icon_mat`，草药类 → `icon_herb`，器物 → `icon_gear`……）+ 品质色描边；有余力可以用生图服务出 8~12 张类别图标（白底转透明，见记忆 image-gen-mcp），不强求。

### 3.4 装备（不掉落，见第 4.6 节）

DarkArea 的枪 / 甲战力差很大，本作要求「不太影响 PvP」，所以**每件装备有两套数：PvE（打怪 / Boss）和 PvP（打真人）**。

- **兵刃**（kind=weapon，1 个槽）：7 档（普通..永恒）。家族只是外观和名字（青锋剑 / 玄铁重剑 / 流光细剑 / 斩马刀 / 盘龙枪 / 破军锤 / 镇岳印，至少 5 族），任何英雄都能装。
  - PvE 伤害倍率 `1.00, 1.10, 1.20, 1.32, 1.45, 1.60, 1.80`；PvP 倍率 `1.00, 1.02, 1.04, 1.06, 1.09, 1.12, 1.15`。
  - 商店卖 普通..史诗，价格照 `darkArea_Shop.csv` 对应档枪族的价位（同档取中位数）；回收价照 trader 表（象征性）。
- **法衣**（kind=armor，4 个槽：冠 / 衣 / 护腿 / 履）：7 档。
  - 每件给减伤 `dr`：PvE 全套（4 件同档）合计 `0, 4, 8, 13, 18, 24, 32, 40%`（按 1..7 档，平均分到 4 件）；PvP 全套合计封顶 `0, 2, 4, 6, 8, 10, 12, 15%`。
  - 价格照 DarkArea 护甲（`gear.json` armor）。
- **法宝**（kind=chip，3 个槽，对应扩展芯片）：3 类 × 5 档（传奇..天启），照 `extension_chips` 的价格 / 耐久：
  - 回元佩（再生）：每秒回气血 `0.4, 0.6, 0.8, 1.0, 1.2` 点（条上点数，PvE / PvP 一样）。
  - 玄龟镜（能量 / 生命上限）：进图时加一层护体值（吃伤害先扣它）`4, 6, 8, 10, 12` 点。
  - 破军印（穿甲）：PvE 伤害 `+5, 10, 15, 22, 30%`；PvP `+2, 3, 4, 6, 8%`。
  - 耐久：受到真人伤害时，每 1 点条上伤害扣 10 耐久；耐久 0 失效；回收价 = 基础价 × 当前耐久 / 上限；坊市修理 = 基础价 × 缺损比例 × 0.5。**死亡必掉**。
- 总封顶（E 在算伤害时再夹一次）：PvP 出手倍率合计 ≤ ×1.25，PvP 减伤合计 ≤ 22%。

### 3.5 消耗品

- **药**（kind=med，`heal`、`hot`（每秒）、`dur`（持续秒）、`use_t`（读条秒））：8 种照 DarkArea，**治疗量 ×0.5**（DarkArea 典型血量约 200，本作条是 100）：止血草（绷带）、灵果（能量罐头）、小回春散、金疮药（医疗包）、中回春散、九转丹（急救箱）、大回春散、续命丹（肾上腺素）。价格照商店（10 个一组的价 ÷10 = 单价）。读条中移动 / 挨打打断。
- **强心丹**（kind=revive，强心针）：倒地自救读条 3 秒；队友手里有也能救人（读条 3 秒）。商店不卖，只从医疗箱 / Boss 出（照 DarkArea），回收 1 万。
- **符**（kind=throw）：雷符（手雷，条上 22 点 / 半径 4 米）、天雷符（超级手雷 40 点）、烟遁符（烟雾，挡神识和视线 8 秒）、火符（燃烧，半径 3 米 10 秒每秒 3 点）。价格照商店。投掷用 E 来定（建议背包里点「投出」或快捷栏一键）。
- **钥匙**（kind=key）：禁室玉钥（密室钥匙，开钥匙房 1..12）。来源：物资箱小概率（DarkArea 漏了来源，本作补：初级物资箱 0.5%、沙漠 / 研究所物资箱 1.5%、Boss 必掉 0~1 把 30%）、黑市 60 仙玉。不可卖。
- **护宝符**（kind=ward）：DarkArea「掉落保护」改成按次数：身上带一张，死亡时保住价值最高的 2 堆售卖物并消耗这张符。黑市 30 仙玉。

### 3.6 掉落表

`loot_tables.json` 的 pools / boxes / monster_and_boss_drops 全搬（抽数、权重、组内等概率、有放回）。物品池里的枪 → 同档兵刃（随机家族）、护甲 → 同档同部位法衣、芯片 → 法宝、药 / 针 / 雷 → 对应消耗品、售卖物 → 改名后的售卖物。表名保留（`seniorSupplyBox`、`labWeaponBox`、`desertLockedSupplyBox`、`yanjiuBossDrops1`…），API：

```
ExData.roll(table: String, rng: RandomNumberGenerator, draws := -1) -> Array[Dictionary]   # draws<0 用表里的抽数
ExData.make(id: String, n := 1) -> Dictionary
ExData.value_of(it) -> int        ExData.is_sellable(it) -> bool
ExData.box_table(map_id: String, box_kind: String, locked := false) -> String   # "weapon"|"supply"|"med"
ExData.mob_table(map_id) -> String     ExData.boss_table(boss_id) -> String
```
**小怪掉率**：本作刷怪比 DarkArea 密（固定刷怪点），小怪每只按 25% 概率抽一次它的表；精英必抽 1 次；Boss 按表抽数。

### 3.7 货币 / 仓库 / 段位 / 商店 / 黑市 / 起始

- 灵石起始 1,000,000；仙玉起始 300。仙玉来源（本作补）：击杀 Boss +5、段位晋升 +50、营救天工师 +20。
- 仓库：12 格起，2..10 级灵石升级（5 万起逐级翻倍到 1280 万，每级 +6 格），11..14 级要「仓库凭证」2/4/6/8 张（黑市 100 仙玉一张）。满级 90 格。
- 背包（备战 / 局内）：30 格（DarkArea 主包 30）；装备栏单独算格。
- 段位：按「成功撤离时 带出售卖物价值 − 入场时售卖物价值（入场恒 0）」累计（`economy.json rank_by_extract_value`），13 档改名：
  `炼气三阶 1万 / 炼气二阶 10万 / 炼气一阶 100万 / 筑基三阶 500万 / 筑基二阶 5000万 / 筑基一阶 1亿 / 结丹三阶 5亿 / 结丹二阶 10亿 / 结丹一阶 50亿 / 元婴三阶 100亿 / 元婴二阶 500亿 / 元婴一阶 1000亿 / 化神 1万亿`。晋升时大厅播一次题字（`realm_banner`）。
- 商店（坊市，灵石）：兵刃普通..史诗、法衣普通..史诗、8 种药（不含强心丹）、4 种符、法宝 15 个（价 = 基础价 ×2，照 DarkArea）。
- 黑市（仙玉）：禁室玉钥 60、护宝符 30、仓库凭证 100。
- 新号赠送（照 DarkArea 首登礼）：史诗兵刃 1 把（青锋剑）+ 传奇法衣 4 件 + 止血草 10 + 金疮药 3 + 强心丹 1，直接穿在身上 / 放进背包。

### 3.8 存档 `ex_profile.gd`

- 文件 `user://xiuxian_ex_profile.json`，测试档 `user://xiuxian_ex_profile_selftest.json`（判定照搬 `raid_profile.test_mode()`，可以直接调它）。版本 `VER = 1`。读档按 `_fresh()` 键合并、类型修正（JSON 里 int 会变 float）。
- 字段：`lingshi, xianyu, wh_level, stash[], bag[], equip{weapon, armor:[4], chip:[3]}, hero, heroes[], extract_total, rank, stats{raids, out, dead, kills, best}, live`（局内锁：进图时把带进去的东西记下，中途关游戏下次开机按**死亡惩罚**结算并写 `notice`，照 DarkArea「中途离线 = 死亡」）。
- API（成功返回 ""，失败返回原因文字）：
```
load_if_needed(); save(); data() -> Dictionary; test_mode() -> bool
lingshi() / xianyu() / add_lingshi(v) / spend(v) -> bool / spend_xianyu(v) -> bool
stash_cap() / upgrade_warehouse() -> String
move(src: "stash"|"bag", i: int, dst) -> String      # 售卖物可以进背包，但开局检查会拦
equip(src, i) -> String; unequip(slot: String, idx) -> String     # slot: "weapon"|"armor"|"chip"
sell(src, i, n := -1) -> String; sell_all_sellables(src) -> int
buy(shop_id: String, n := 1) -> String; buy_black(id) -> String; repair(src_or_slot, i) -> String
set_hero(id) -> String
entry_check() -> String          # 背包里有售卖物 → "售卖物不能带入禁地：先存进仓库或卖给商人"
begin_raid(map_id) -> Dictionary # {bag, equip, hero}（深拷贝），写 live
end_raid(res: Dictionary)        # res = {ok: bool, bag: Array, equip: Dictionary, lost_chips: bool,
                                 #        extract_value: int, kills: int, map_id, cause: "extract"|"dead"|"timeout"|"quit"}
                                 # ok：背包回存档背包（不自动进仓库，玩家自己整理；背包放不下的照 DarkArea 掉进仓库，仓库满了折灵石），
                                 #     extract_total += extract_value，判段位晋升；不 ok：E 已经把掉落扣掉，剩下的照样回背包。
rank_of(total) -> int; rank_name(i) -> String; take_notice() -> String
```

### 3.9 大厅界面 `ex_lobby_ui.gd`

- 外壳照 `abode_ui.gd`（遮罩 → 宣纸面板 → 题头（朱印、页签、灵石 / 仙玉）→ 正文 → 底栏说明 + 按钮；选中一件 → 底栏出按钮；手机缩放）。打开时暂停树、放鼠标（照 `hud._open_abode`）。
- 页签：**备战**（左：装备栏 兵刃 / 四件法衣 / 三法宝，右：背包 30 格；点仓库物品「带上」、背包物品「存仓 / 卖 / 穿戴」；顶部提示入场检查结果）、**仓库**（格子 + 扩容按钮）、**商人**（背包 + 仓库里的售卖物，单卖 / 一键卖售卖物，显示总价）、**坊市**（分类：兵刃 / 法衣 / 药 / 符 / 法宝，买 1 / 买 10）、**黑市**、**英雄**（左：英雄卡，右：介绍 / 四个技能 + 觉醒说明 / 「选用」）、**段位**（当前段位、累计带出价值、下一档、全部档位表）。
- 接入：大厅仓库口 / 商店口 / 右上洞府按钮改开这个界面（主控在 hub_hall / hud 里接，D 提供 `static func open(host: Node, tab: String) -> Node` 之类的入口，并在报告里写清楚）；选关入境页的「备战」也开它。
- 玩家牌（`player_plate.gd`）：大厅和新图里显示 英雄名 / 段位 / 灵石，不再显示修为弧；老大世界里照旧（看 `main.level` 的类型或 `level.get("map_id")`）。

---

## 4. 局内规则（E：extract_manager.gd 等）

新写管理器，照 `arena_duel.gd` 的先例实现 net.gd 契约（`recon/xx_raid.md` 第 2.2 节列的字段 / 函数 / 生命周期一个不能少），raid_manager 里不带修仙的函数近乎逐字搬（第 3.3 节清单），修仙的一律不搬。地图点位全部从 `level.points(kind)` / `MapDef` 读。

### 4.1 进场

- 选关入境页点「开始」时先 `ExProfile.entry_check()`，不通过就提示、不进图（主控在 level_select 里调；E 在 manager `_ready` 里再查一次兜底）。
- `begin_raid(map_id)` 拿装备 / 背包 / 英雄；出生点从 `level.spawn_point()`（W 按 map_def 随机挑：沙漠地面 4 + 地下 4，研究所 5）；**出生 10 秒无敌**（可以复用护体 / 起身保护的无敌标志，H 提供 `player.set_invuln(t)`），前 5 秒不能丢东西。
- 开局题名（`realm_banner`）：图名 + 「限时 15 分钟」。

### 4.2 计时与撤离

- 个人 900 秒倒计时（从进图算），5 / 3 / 1 分钟、30 秒提示；到点仍在图里 = 死亡（cause "timeout"）。
- 撤离点：沙漠 4 个、研究所 8 个（map_def）。**随时开放、无条件、无人数上限**；站进撤离区读条 5 秒，离开 / 挨打 / 倒地取消（照 DarkArea）；读条中每 2 秒广播 `§x` 位置（小地图 ping）。外观借 raid_manager `_build_extract`（光柱 + 地面阵）。
- 撤离成功：结算带出价值（背包售卖物 value×n 之和），`end_raid(ok)`，结算界面（成功 / 存活时长 / 击杀 / 带出价值 / 新得物品，稀有高亮），4.5 秒后 `level.exit_requested`。

### 4.3 搜箱

- 三类箱：兵器匣（武器箱）、物资箱、医疗箱；外观用 `assets/creatures` 现有箱子 / 罐子模型或新拷的（见 assets.md 5.1），三类一眼能分。
- 位置由 map_def 给（W 按区域密度摆：沙漠约 60、研究所约 90；钥匙房里另算）。
- 开箱：走近 → 拾取卡上出「开启」（或站旁边读条 1.5 秒，读条中定身），读满后按表抽物，**东西喷到地上**（`raid_pickup` 单件，走拾取卡片），箱子变「已开」外观，**180 秒后复原**（按房间时钟）。
- 品质表：沙漠用 `senior*`（照 DarkArea：沙漠矩形内），研究所用 `lab*`；地下 / 半地下照 DarkArea 也用本图的表。
- 联机：开箱向房主申请（照掉落的 `_claim` 流程，新消息或借 `§` 小消息），房主判先到先得，结果广播；箱子开 / 复原状态全房一致（复原时刻按 `net.room_t`）；中途加入的人从房主拿箱子状态。

### 4.4 钥匙房

- 沙漠 2 间（地下）、研究所 10 间（map_def 给门位置、房间盒子、房内箱子 2~4 个）。门是实心盒子（挡人挡怪），走到门前出「开启（需禁室玉钥）」：背包有钥匙 → 读条 2 秒 → 扣 1 把、门开、房内箱子复原；**开门后 900 秒内谁都能进**，到时若房里没人就关门。房内箱子用 `desertLocked*` / `labLocked*` 表（物资 4 抽 / 武器 1 抽）。
- 联机：开门广播（门 id + 房间时钟时刻），所有人同步开 / 关。

### 4.5 怪

- 固定刷怪点（照 `raid_camps.gd` 的状态机：复活 75 秒、一个点只由一人建、联机交接），点表由 map_def 给；小怪每处 3~5 只。密度别学 DarkArea 的稀（用户两次嫌怪稀），也别围着人刷。
- 沙漠：毒尾蝎（`scorpion`）、沙漠狼（`wolf_sand`）、沙灵守卫（`sand_guard`）、沙匪（新拷 `sand_raider`，可选）；研究所：尸傀（新拷 `zombie`）、机关钳击兵 / 炮击兵（`mech_claw / mech_gunner`）、凝胶怪（`gel_mutant`，精英）。模型拷贝 / 精简由 E 负责（照 assets.md 第 8 节，先查同名文件），没来得及拷的先用现有模型顶上。
- 数值（扁平，不看境界）：伤害单位 `u = 招式原始伤害 / player.hero_base()`（H 提供，恒为结丹档 18）。主角打怪 = `u × HIT_PER_UNIT(10) × 兵刃PvE × (1+破军PvE)`；怪的血写成点数：沙漠小怪 40、研究所小怪 80、精英 ×3、巨汉 ×2。怪打主角 = 条上点数 × (1 − 法衣PvE减伤)：沙漠小怪 5、研究所小怪 12（照 DarkArea 10 / 35 按 ÷2 再压一点）、精英 ×1.5。数都放 manager 顶部常量，报告里写清。
- 研究所夜里（昼夜见 4.9）每 90 秒在每个真人 20~40 米外刷一小波尸傀（3~5 只，上限照 mob_cap）。
- 研究所怪必须挡墙（`block_fn` → `level.blocked(from, to)`），别穿楼。

### 4.6 死亡 / 重伤 / 惩罚

- **重伤倒地**（两张图都有，照 DarkArea 二级战场）：受到致命伤 → 不死，进入重伤（H 提供 `player.set_downed(on)`：不能出招 / 用物品，移速 ×0.35，趴地姿势，联机木偶也趴下）。重伤条 20 秒流光（每秒 −5%），期间再受致命伤即死。
  - 自救：背包有强心丹 → 重伤界面「自救」读条 3 秒（挨打打断），起来回满血、扣一颗。
  - 队友救：队友背包有强心丹，走到 3 米内读条 3 秒（扣救人者的一颗）。
  - 「自尽」按钮：直接死。
  - 联机：重伤 / 起身 / 救人借小消息同步（`§d` / `§v` 或新 RPC，E 定）。
- **死亡**（cause dead / timeout）：
  1. 扣 5000 灵石；够 5000 时在死亡点掉命牌（价值 5000）。
  2. 售卖物：从背包里**随机掉 2 堆**（两张图都是 DarkArea 的「初级战场」；按地图配置 `death_drop_stacks`，以后的高级图可以设 "all"）。带护宝符：先把价值最高的 2 堆剔出掉落池（≤2 堆则不掉），并消耗护宝符。
  3. 法宝全掉（带当前耐久）。
  4. 兵刃 / 法衣 / 药 / 符 / 钥匙：不掉（照 DarkArea Type=2 和消耗品规则）。
  5. 掉的东西 + 命牌变成一只共享「X 的遗物」箱留在死亡点（`_drop_chest`，联机全房可抢）。剩下的背包照样回存档（`end_raid(ok=false)`）。
  6. 结算界面写明丢了什么。
- **中途关游戏 / 掉线**：下次开机按死亡处理（ex_profile 的 live 锁），但没有遗物箱（东西直接销毁）。房主关房（`room_collapsed`）照撤离成功算；自己掉线（`room_lost`）照死亡算（照 DarkArea）。
- 战斗中没有自然回血（H 给 `player.regen_k = 0` 开关，新图里设 0）；回元佩 / 药是唯一回血手段。

### 4.7 PvP

- 真人伤害走 `CS.pvp_hit`（H 改成不看境界差），出手倍率乘「兵刃PvP × (1+破军PvP)」并夹到 ×1.25；受击方 `_pvp_clamp`（单下 / 余量 / 每秒封顶，照现有）后乘「1 − 法衣PvP减伤」（夹到 22%），再扣玄龟镜护体值。
- 队友不伤（net.gd 现有规则）。击杀真人：击杀者记击杀数（结算显示），死者照 4.6 处理。
- AI 修士（`air_foe` 当对手）：只在房里只有一个真人时出现（沿用现有规则），每张图 2~3 个，会找怪打、会搜箱（简化成：走到最近的箱子边停 2 秒，箱子记开过）、红名的会打人；死了掉「X 的储物袋」：从本图物资箱表抽 2 次。

### 4.8 局内背包

- 背包 30 格；装备栏随身（兵刃 / 法衣 / 法宝），局内可以从背包穿上捡到的更好装备（换下的进背包）。
- 背包操作：使用（药 / 符）、穿戴、丢弃；满了不自动换。
- 拾取：走近掉落物 → 屏幕右侧拾取卡片（照现在的 160 宽卡片 + 滚动最多 4 张，`LOOT_RIGHT` 等写法照 raid_hud），点卡片拾取，T 键拿最上面那张。
- 局内「带出价值」实时显示在右上信息牌（照 DarkArea 的 HUD 价值）。

### 4.9 昼夜（全房一致）

- 按房间时钟：白天 600 秒 / 黑夜 600 秒，过渡 6 秒（W 做光照 / 天色 / 雾的切换，`level.is_night()`）。
- 夜里：研究所刷尸潮（4.5）、凌影换「狂潮」形态（第 8 节）、天工师消失。沙漠只有光照变化。

### 4.10 营救天工师（研究所，对标营救博士）

- 刷新点：map_def `doctor`（主楼楼上）。条件：白天第 180~300 秒（照 DarkArea），场上没有天工师；**房间人数 ≥ `DOCTOR_MIN`**（DarkArea 4；本作默认 1，可配）。入夜消失。
- 走近点「营救」→ 归属给你：天工师跟着走（保持 3 米，超过 10 米停下、移速 ×0.8；10~15 米警告；超过 15 米持续 5 秒失去归属），全图小地图可见；带着时每 5 秒在你附近刷 1 只尸傀。
- 你和天工师都在撤离区里才开始读条；撤离成功额外 +100 万灵石、+20 仙玉。持有者死了失去归属，天工师原地等人。
- 模型 `doctor.glb`（虚空博士，**贴图 alpha 全 0，材质强制不透明**）。
- 联机：持有者模拟位置，小消息 2~4 Hz 同步。

---

## 5. 地图（W：map_def.gd / grid_world.gd / ex_level.gd）

### 5.1 坐标换算（DarkArea 1 格 = 1 米）

- **沙海古墟（desert）**：横向 ×2，竖向 1:1。`x' = (x − 231) × 2`，`z' = (499 − z) × 2`（DarkArea +Z 是北；本作 −Z 是北，主城约定 yaw 0 朝北），地面基准 `y' = y − 70 + 20`。主图约 540 × 692 米。
- **地下洞窟**（desert 的地下层 y3..27）：放到同一张图的**另一片坐标**（建议 `x' + 1000`，W 可调），洞窟地板 `y'' = y + 7`；地面上的 4 个洞口（U1..U4）和北峡谷 C 都是下行入口：走进洞口 → 黑场 0.4 秒 → 传到洞窟里对应的出口（反之亦然）。洞窟四周是高岩壁，头顶一块暗色岩顶网格（`visibility_range` 只在洞窟附近可见），主角 / 怪在洞窟里有绝对高度上限（W 每帧夹）。洞窟里关太阳、换暗环境 + 火把 / 晶体自发光。
- **天工秘所（lab）**：横向 ×1.5。`x' = (x + 1022) × 1.5`，`z' = (528 − z) × 1.5`，园区地面 `y' = y − 40`（≈50 米，半地下的钥匙房下沉坑在 17~47 米之间，不能低于 0：block_world 里 0 以下是水 / 云海填充）。主图约 777 × 777 米。凌影的地下室（y31..40）同样做成另一片坐标的洞窟（`x' + 900`），由主楼里的楼梯口 u3 / u4 / u5 传送下去。
- W 把 `levels.json` 里所有点（出生 / 撤离 / 钥匙房门与房间盒 / Boss 出生与战斗区 / 召唤台 / 洞口 / 天工师点 / 图标点）按上式换算进 `map_def.gd`，并补上 DarkArea 没有的：箱子点、刷怪点、建筑清单、边界。

### 5.2 两张图的结构（照 `da_levels.md` 的复原）

**沙海古墟**
- 地面：开阔沙丘 + 戈壁 + 遗迹散件（沙石柱、图腾、断像），正中一座阶梯金字塔「黄金神塔」，塔顶是凌幽的 Boss 台（比地面高 18~30 米，战斗区 24×12×22 ×2）。四面各约 230 米（原 115 ×2）一个撤离台；四角是地面出生点。
- 北部峡谷 C 和洞口 U1 是主下行通道；旧飞机舱不做。
- 地下洞窟：西洞（U2 下去）有钥匙房 k11 和绛罗场地（32×32 ×2）；东洞（U4 / U1 下去）有钥匙房 k12、地下出生 s6 / s7，东北角是 44×44（×2）的沙虫竞技场 + 召唤祭台（四角牢笼位置留着，牢笼本轮可不做）。地下没有撤离点，必须回地面。
- 边界：外圈 30~60 米赤岩台崖 + 崖外 80~120 米沙暴带（雾随离边距离加浓、飘浮物换沙色加密、越往里推力越大 + 每秒掉 3 点，提示「风沙太烈，寸步难行」），硬夹钳藏在沙暴最浓处；全图飞行绝对上限 = 地面 + 45 米（塔顶以上留一截）。
**天工秘所**
- 被尸傀占领的机关坊园区：西缘是出生带（5 个出生点），越往东越深；主楼「天工楼」（原主楼 X-1090..-950、Z480..560 ×1.5），K1 / K2 / K3 贴着它，楼上是天工师房间，楼下由楼梯口进地下室「尸傀密窟」（凌影）；南面「百炼坊」（糖果工厂：多层厂房，电鞭铁卫在 y90..100 的台上，K4 在楼上）；北面「镇尸营」（收捕队营地：高台，冰僵铁卫，K6 / K7 在台下）；东面「双子斗场」（吕布擂台：比路面低 16 米的下沉斗场 + 召唤台）；K5 是东侧 50×57 的下沉实验仓；K8 / K9 西区小密室，K10 东区孤立小屋。8 个撤离区绕外圈。
- 楼：能进的楼只做**地面层 + 屋顶**（楼梯上屋顶），K4 这种「楼上」的房间做成二层平台；层高 ≥ 4.5 米、门宽 ≥ 3.5 米（粗壮方块人 + TSB 横向打法）。人进楼后藏这栋楼的屋顶（每栋楼的屋顶单独一个网格，主角在楼的占地框里就藏），镜头遮挡别把屋顶算进去。
- 主角在楼里飞行 / 跳跃要**撞墙撞顶**（ex_level 的落脚 / 挡路里做；照 meadow_level 的 `_walk_h / _clip_move`，加空中挡墙和头顶夹钳）。研究所里关掉地形破坏。
- 边界：外圈 15~20 米高围墙 / 断崖 + 墙外深谷（掉下去送回最近的边）+ 墙顶一圈看得见的禁制光幕；飞行绝对上限 = 园区地面 + 35 米。
- 风格：灰白混凝土 + 锈铁 + 青铜机关 + 朱漆木构（仙侠里的机关坊，不要现代科幻），夜里有冷光灯。

### 5.3 世界实现要点

- 推荐 `grid_world.gd` 继承 `block_world.gd`、覆盖 `_cell / _shaped / _raw / _region / 配色 / 摆件`（见 xx_world.md 2.2）；block_world 只加钩子（`_setup_content()` 可覆盖、区域标志表、`bounded` 不排图外的块、`_update_sea` 可关），**老大世界行为不能变**（改完跑一次 `-- --raid-shot` 截图对比）。若评估后觉得继承风险太大，可以自写分块网格（每 96 米一块一个网格、只在近处细、远处粗），但要满足性能预算。
- 楼宇 / 遗迹的实心盒子要**全图静态登记**（不跟着 lod0 走），怪 / AI / 主角都能问。
- 小地图：载入时一次烘整张图（地面一张、洞窟一张，按主角在哪层换），`minimap.gd` 加固定底图模式；楼的轮廓、门、钥匙房、撤离点烘进底图或走标记。另做一个全屏大地图（点小地图打开）：撤离点、已知钥匙房、Boss 区、队友、自己。
- 性能预算（网页档同探针）：绘制调用 ≤ 220、图元 ≤ 220k、细地块 ≤ 60k 顶点；手机阴影只管 80 米；网页单线程分帧。两档渲染器都截图验收。
- 昼夜：`day_phase()` 按房间时钟（`net.room_t`，单机用本地时钟），白天 14 点、夜里 4 点的光照 / 天色 / 雾，6 秒过渡；夜里研究所开冷光灯。

---

## 6. 英雄（H：hero_defs.gd / kit_*.gd + 战斗文件改动）

### 6.1 英雄表 `hero_defs.gd`

```
HEROES := {
  "yujian":   {"name": "御剑", "title": "飞剑法修", "skin": "aladeng", "kit": "res://scripts/kit_yujian.gd", ...},
  "canghong": {"name": "苍鸿", "title": "剑修",     "skin": "canghong", "kit": "res://scripts/kit_canghong.gd", ...},
}
```
每项至少：`name / title / desc / skin / blade（"fist"|"sword"）/ art（招式档，给 Realm.art 用）/ flair（花样档）/ chain（M1 表）/ moves（新增或覆盖的招式）/ skills[4]（{key, name, desc, cd, mp}）/ awaken（觉醒形态说明）/ touch（四个技能按钮的字）/ fly_speed / blink`。API：`HeroDefs.get(id) -> Dictionary`、`HeroDefs.ids() -> Array`、`player.set_hero(id)`、`player.hero_id`、`player.hero_def`、`player.hero_base() -> float`（恒 18）。

### 6.2 共用底盘（TSB 基础套，两个英雄一样）

- 气血条 100、灵力 100（结丹档基准），**所有英雄同一套数值档**；战斗数值不随境界变化（`is_light_mode()` 在新模式恒真，空战一开局就有）。
- 键位（键盘 / 触屏）：攻 J / 左键（M1 连段）、御 K / 右键（护体 / 格挡，按住）、闪 Shift（闪现 / 御风突进）、Space 跳 / 升、**E / Z / Q / R = 技能 1~4**（触屏四个技能键的字按英雄换）、V 按住聚气（觉醒条满时继续聚 = 觉醒）、F 光遁赶路。
- 基础套复用现有：M1 连段 + 方向派生（挑月 / 坠星 / 绕身）、蓄力重击、御风突进、闪现、护体（擦血 15%、破防）、瞬身反击、挣脱（罡气 2 格）、受身、真人对打规则（连段上限 / 起身保护 / 近身耗灵力）、觉醒（命中 / 挨打 / 聚气攒条，觉醒 14 秒：伤害 ×1.3 等）。
- 新模式里关掉自然回血（`player.regen_k = 0`），给 `player.set_invuln(t)`（出生无敌）、`player.set_downed(on)`（第 4.6 节）。
- 飞行：新模式里飞行速度按英雄 `fly_speed`（建议 28 m/s，原结丹 45 太快，地图会被飞穿）；地图另有绝对高度上限（W 做）。

### 6.3 老角色「御剑」（兼容 + 调整）

- 招式照旧（拳脚五连 + 飞剑随击、E 点射 / 按住万剑连发 + 对波、Z 三式剑诀、Q 飞剑阵、R 大罡剑阵），但：
  - 数值档固定结丹；`flair` 固定 1（残影，没有分身乱舞，否则对新英雄不公平）；剑诀法相档 / 连发队形固定一档（建议元婴「紫霄雷法」那档的外观，数值按结丹基准）。
  - R 大罡剑阵改成**觉醒中才能放**（觉醒的终结技），平时 R 是「飞剑阵」以外的另一个技能或灰掉，H 定。
  - PvP 里连发每柄伤害再压一档（连发是「乱按秒人」的主要来源）；剑气 / 点射只给轻硬直。
- 四个技能槽：E 飞剑（点射 / 连发）、Z 剑诀、Q 飞剑阵、R 大罡剑阵（觉醒）。

### 6.4 新英雄「苍鸿」（TSB 式近战剑修，H 自由发挥，下面是基线）

- 模型：`assets/hero/canghong.glb` ← 资源库 `01_主角动画皮肤\苍鸿_140199`，用 `_tasks/hero_skin/strip_glb.py` 精简（只留 100100 待机 / 100111 跑；13 把剑另存或剔除；贴图 ≤512），`hero_skin.gd` 的 `SKINS` 加 `"canghong"`；**手里常驻一把实体长剑**（`blade_always`，命中点走剑身）。
- 定位：纯近战、中短距离压制、靠招架反击和位移；不放飞剑随击（`swords: 0`），灵力只给技能用。
- M1 四连斩：斩一 / 斩二 / 回身斩 / 挑斩（第 4 下击飞），单位约 0.55 / 0.55 / 0.7 / 1.2，reach +0.4；连段中摇杆前 = 挑空（击飞 up）、后 = 下劈（down）。
- 技能（参考 TSB：一个突进、一个反击、一个远程、一个连段）：
  1. **E 一闪**：拔剑突进斩，向前 14 米穿过 / 冲到目标身边一斩（1.2 单位、短硬直），冷却 7 秒、12 灵力。
  2. **Z 回风**：剑架 0.8 秒；架势中被近战打中 → 闪到对方身后反击（1.6 单位、击倒），冷却 12 秒。**对真人生效需要回传命中结果**：加一个可靠 RPC「你这一下被我招架了」（攻方收到 → 自己硬直 0.5 秒），联机协议变更要在报告里写明。
  3. **Q 断月**：连斩两道新月剑气（飞行道具，每道 0.7 单位、轻硬直，护体能拨），冷却 9 秒、10 灵力。
  4. **R 千刃**：原地乱舞 6 段后挑飞（合计 2.4 单位），可接空中追击，冷却 14 秒、15 灵力。
  - **觉醒「剑心通明」**：剑身发光、M1 变 5 段带剑气延伸（reach +1.5）；四个技能变形：一闪 → 瞬狱（连续三次突进斩）、回风 → 剑域（以自身为圆心 6 米的招架圈）、断月 → 天斩（一道巨大剑气）、千刃 → 终式「万剑归宗」（13 柄剑环身后齐落，用苍鸿模型的剑件或现有飞剑外观）。
- 平衡目标：两英雄 M1 整套 ≈ 3.0 单位；技能 1.0~2.5 单位、冷却 6~15 秒；同等操作下互有胜负（御剑强在远程压制 / 对波，苍鸿强在近身和反击）。
- 新姿势进 `combat_poses.gd`（联机木偶才播得出来）；木偶按对方英雄建皮肤和兵器（英雄 id 进 `net._hello` / `players[id]`）。
- 触屏：四个技能键的字（一闪→「闪」会和闪避撞字，建议「瞬 / 回 / 月 / 刃」），补字库。

### 6.5 必须保住的

- 老大世界（门 0）照旧可玩：进门 0 时 `set_realm(Profile.boot_realm())`、英雄 = 御剑且不覆盖档位（主控切换，H 保证 `set_hero` 能被「关掉」）。
- 主城擂台 1v1（arena_duel）照常能打（用当前所选英雄）。
- AI 修士 / 道友（air_foe）照常能用（它们直接读 `Moves.MOVES / Moves.CHAIN`，**别改老条目**，新招式放英雄表）。

---

## 7. 大厅 / 选关 / 联机（主控，派工前完成）

- `hub_hall.gd` GATES：门 2「沙海古墟」→ `level: "desert"`，门 3「天工秘所」→ `level: "lab"`，开门；门 0 加 `level: "mulan"`（旧版）；修炼场不再出「闭关打坐 / 渡劫」；不结算离线闭关；不建灵田农场（牌坊门封住、改题「灵田 · 暂闭」）。
- `main.gd`：`var level: Node3D`；`LEVEL_TYPES = {"mulan": MeadowLevel, "meadow": MeadowLevel, "desert": "res://scripts/ex/ex_level.gd", "lab": 同}`（新图运行时 load，设 `level.map_id`）；`_on_hub_gate` 记住 `_gate_from`、门 2 / 3 → `level_ui.open_level(id)`；`_return_to_hall` 回到进来的那道门；载入字用关卡名；删大厅一键服丹；GM 境界键只在 `Profile.test_mode()` 时有效；新图 / 大厅里 `player.set_hero(ExProfile.hero())`，门 0 切回旧档。
- `level_select.gd`：`LEVELS` 加两张卡；`open_level(id)` 直接进入境页；新图的入境页「备战」开 `ex_lobby_ui`、「开始」前调 `ExProfile.entry_check()`。
- `net.gd`：发现包加第 4 段地图 id、`rooms[ip].map`；`_matchmake` 只挑同图的房；`_hello` 带地图 id，不同图拒绝；`players[id]` 加 `map`（英雄 id 由 H 加）。
- 自检入口：`main.gd` 在 `--qa-solid` 那一段旁边加 `--level-test=<id>`（`load("res://scripts/ex/ex_selftest.gd")`）、`--hero-test`（`load("res://scripts/hero_selftest.gd")`）、`--lobby-test`（`load("res://scripts/ex/ex_lobby_selftest.gd")`）、`--level-shot=<id>`（`load("res://scripts/ex/ex_level_shot.gd")`）。脚本由各归属者写；探针拿到的 `m` 就是 main，自检流程照 `solid_selftest.gd`：关抓鼠标 → `m.level_ui.mode = "solo"` → `await m._enter_level(id)` → … → `m._return_to_hall()` → 等 `m.level == null` → `get_tree().quit()`。

---

## 8. Boss（E：ex_boss.gd）

挂在 `raid_mob` 首领实例上的技能大脑（`raid_mob` 加挂点），技能由表配置；首领由「主人」模拟（联机照怪的协议），技能的视觉事件用小消息广播给别人画（伤害只在主人那边按命中算，打远程玩家走 `decoy.mob_hit` 现有路径）。血量 = DarkArea 血量 × 0.04（点数），按场内真人数缩放 `×(0.6 + 0.4·min(人数,4)/4)`（单机打得动）；单下伤害封顶 35 点。重生 / 召唤冷却照 DarkArea。所有 Boss：出生点 3D 倒计时字、重生 / 击杀全房播报（`realm_broadcast` 横幅或 `hud.banner`，带击杀者名）、跑出战斗区拉回 + 场内没人 5 秒回满血、站在区外打它无效、掉落撒满战斗区（`_drop_item` 逐件撒）。

| Boss | 图 | 模型 | 技能（照 DarkArea 简化） | 掉落表 / 抽数 |
|---|---|---|---|---|
| 凌幽（金塔守灵） | 沙漠塔顶 | `sand_lord`（沙原领主） | 不移动；每 2 秒给区内每人一发追踪弹；每 5 秒一圈螺旋弹幕，发数 10→50 随失血涨 | superBossDrops 16 |
| 绛罗 | 沙漠地下西洞 | 现有或新拷人形 / 幽魂 | 风筝型：背离最近的人逃 10 米、召唤幽冥泣（小怪） | superBossDrops1 16 |
| 沙渊巨虫 | 沙漠地下东北竞技场 | 程序拼的体节方块虫（头 + 8~12 节，砂岩配色，钻地进出） | **召唤**：祭台，场内真人 ≥ `SUMMON_MIN`（默认 1，DarkArea 4）；定点爆炸（锁 1 人、±4 米 6 个落点、预警 1.5 秒）；沙卷风（预警 2 秒 → 停 2 秒 → 5 秒直线推 55 米，半径 3 米每 0.4 秒 4 点，同时 3 个，夹在竞技场内）；≤50% 血嗜血（伤害回血、上限 30% 血量） | sandWormBossDrop 16，召唤冷却 600 秒 |
| 凌影 | 研究所地下密窟 | `gel_mutant` 放大（白天）/ 加紫光（夜晚「狂潮霸主」） | 白天：投掷尸傀（落地变小怪）、召唤；夜里（且房间人数 ≥ `SUMMON_MIN`）：换形态、血量 ×1.9、尸潮（场内不足 7 只就补，含精英） | yanjiuBossDrops1 / 2 各 16 |
| 电鞭铁卫 | 研究所百炼坊台上 | `mech_hunter` 改色 | 不移动；雷电普攻、五连鞭（扇形）、雷暴（区内随机落雷 6 道） | yanjiuBossputong1 16 |
| 冰僵铁卫 | 研究所镇尸营高台 | `mech_colossus` 或 `stone_giant` | 冲锋、锁链（拉近最远的人） | yanjiuBossputong2 16 |
| 铁穹双卫（对标吕布貂蝉） | 研究所双子斗场 | `mech_hunter`（近战）+ `mech_welder`（远程 + 给同伴回血） | **召唤**：召唤台，场内 ≥ `SUMMON_MIN`；出圈拉回 + 吃 20 点；一方血量 <50% 另一方变身（体型 ×1.2、伤害 ×1.3）；焊愈卫活着时每秒给猎杀卫回 0.5% | lvBuDiaoChanBossDrop 48 撒满场地，召唤冷却 600 秒 |

本轮允许简化：牢笼、魅惑传染可以不做；每个 Boss 至少 2 个技能 + 正确的掉落 / 播报 / 重生。

---

## 9. 自检与验收

- **E**：`--level-test=desert` / `--level-test=lab` 一整局：进图 → 无敌 10 秒 → 走到箱子开箱拾取 → 用钥匙开钥匙房开箱 → 打一处刷怪点 → 召唤 / 打一个 Boss（自检里可以给主角加伤害倍率加速）→ 穿捡到的装备 → 撤离成功 → 回大厅，存档里售卖物增加、段位累计；第二遍走「死亡」分支（掉 2 堆 + 法宝 + 命牌、遗物箱出现）。每步打 `[ex]` 行，关键处截图（`ex_<map>_*.jpg`）。研究所再测营救天工师撤离（+100 万）。两档渲染器各跑一次（第二次加 `--rendering-method gl_compatibility --touch`）。
- **W**：`--level-shot=desert|lab`：地面 / 洞窟 / 楼内 / 边界 / 夜景各一张，打印绘制调用 / 图元 / 块数；走进洞口能传下去、能传回来；研究所楼里撞墙撞顶；边界推不出去。老大世界回归：`-- --raid-shot` 能跑完。
- **H**：`--hero-test`：两个英雄各把 M1 / 四技能 / 觉醒 / 觉醒技打在木桩上，打印每招单位、冷却、灵力；切英雄能换模型和按钮字；`--arena-duel` 擂台还能打；`--raid-shot`（老大世界）不报错。有条件就用 `_tasks/pvp_rules/run_pair.py` 双开测一次招架回传。
- **D**：`--lobby-test`：开大厅界面每个页签截图；买 / 卖 / 穿戴 / 存取 / 扩容 / 黑市 / 换英雄 / 入场检查各一遍，打印存档前后对比；网页档截图看字有没有方框。
- **主控**：大厅 `-- --hub-shot`（门 2 / 3 能进、旧门 0 能进）、最后整合跑全部、部署网页版、拉起游戏窗口。

---

## 10. 本轮之后（写进报告的「下一步」）

兵刃升级 / 赋能、天赋树、称号 / 图鉴、悬赏令、黄金古墓（人数 >12 开放、全掉）、市中心枢纽图 + 战场开放时钟（300 / 600）、木兰草原老大世界换成新经济、牢笼 / 魅惑等 Boss 机制补全、真服务器。
