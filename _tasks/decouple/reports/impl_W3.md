# impl_W3：主城 + 元界面 + main（CONTRACT 第 5 节）

2026-11-25，W3。备份在 `_tasks/decouple/backup/*.W3.txt`（改前原样）。没有 commit / push，没有关任何游戏窗口。

## 改了什么

### main.gd
- :229 恢复大厅底部「一键服丹」（hall_pills.gd，cbb6ec9 删掉的 7 行原样加回）。
- :799 `_apply_combat_mode(_mode := "")` 只剩一条路：`set_realm(boot_realm)` → `set_hero(Profile.hero())`。
  **自检档（Profile.test_mode）里 boot_realm 恒为 0，这时保留主角当前境界**（不然自检先设元婴再进图会被打回炼气；W2a 的 xiu_map_selftest.set_realm 就是按这个写的）。mode 参数留着兼容 mijing_boot / hero_selftest。
- 删掉 `_ex_mode()`；`_unhandled_input` 的 GM 键改成只看 `test_mode()`（正式游玩不能自己改境界，和 cbb6ec9 之后一样）；Backspace 回出生点不再对新图特殊拦截。
- :318 探针表：`--level-test` → `res://scripts/xiu_map_selftest.gd`，支持 `--level-test=desert` 和 `--level-test desert` 两种写法；删掉 `--lobby-test` / `--boss-test-ex`；`--level-shot` / `--hero-test` / `--tsb-show` 照旧。
- :82 `HARD_MIN_REALM := 3`；:1135 新 `hard_level_lock(lid)`（不够返回「X凶险 · 元婴期方可入内（你现在是Y期）」）；`_on_hub_gate` 先过这一道，不够就 `hub.say` 并 return。
- `_enter_level` 里统一调 `_apply_combat_mode()`；warmup tag 仍传 "ex"（W2b_api.md 第 4 节：两种都认）。

### hub_hall.gd
- :71-75 门 0 sub「主线大世界」；门 2 / 3 sub「元婴可入」+ `"min_realm": 3`。
- :187 恢复 `_build_farm()`；:252 恢复开机离线闭关结算；:1576 恢复切回前台的离线结算；:1504 `_zone()` 恢复修炼场 "med"。
- :1081 `gate_lock_text(i)`、:1093 `_refresh_gate_locks()`：门心面片存进 `_gate_mis`，境界不到 → `transparency 0.45` + 着色器 `locked 0.5`（半透明压暗）；进主城（set_active）、渡劫成功后刷新。
- :1979 门触发：境界不到只节流 say 提示、不 emit。
- :1145 门 2 / 3 门心上方一行「元婴可入」（Label3D，字号 PLAQUE_FS 共用字库，无描边）。
- 自检：门那一段改成「炼气走四道门 → [0, 1]，存档设元婴再走门 2 / 3 → [2, 3]」，另打印透明度和 main 兜底拦截；多拍一张 `hub_2b_gate_locked`。

### hud.gd
- 删 `EX_PROFILE / EX_DATA / _rank_t / _rank_fx_on / _ex_rank_banner`；:242 新 `_hub_notes()`：主城里排队说 `Profile.notice` 和新号引导（标记存 `stats.intro`，自检档不说）。
- :218 INTRO_LINES 改修仙版（木兰草原搜宝撤离 / 备战坊市 / 修炼场渡劫、元婴开门 2 / 3）。
- :284 F1 英雄说明的局内键改成 raid_hud 的（T 拾取 / B 背包 / 搜点自动读条 / 点小地图神识 / 传送阵撤离）。
- :650 `_ground_skills()`：任何关卡里都露英雄技能框（原来问 main._ex_mode）。
- :806 dock 第三颗字「段位」→「境界」。

### level_select.gd
- LEVELS：desert / lab 去掉 `"ex"`，改 `"hard": true, "min_realm": 3`，tag / desc 改修仙口径。
- 删 EX_LOBBY / EX_PROFILE / `_ex_ctx`；加 `Profile` / `HeroDefs`。
- :163 `open_level` 境界不够不开；:178 `realm_lock(i)`；`pick(quick)` 也挡。
- :188 `_summary()` = 「出战 英雄名」+ `Abode.summary()`；:196 `_entry_err()` = in_raid → RAID_LOCK，否则境界门槛。
- 英雄那一排每张图都出（:340，读写 Profile.hero_ids / hero / set_hero）；hard 图 tip 加一行「元婴及以上方可入境；妖兽更凶，掉落更好」。
- :403 `_use_meta()`：默认开 meta_ui；带 `--old-abode` / `--abode-test*` / `--abode-open-test*` 时开老洞府 abode_ui。

### hall_pills.gd
- :225 新静态 `eat_stack(i0, max_n, meditating) -> {n, got, ups, lv, full, err}`：纯存档的吃丹逻辑；:203 原来的 `_eat_stack` 改成调它再飘字。备战页「服下」也调它（规矩只有一份）。

### abode_ui.gd
- 对过 492a1fc..cbb6ec9 的 diff：只是手机重排，丹房 / 坊市 / 储物都在，没改。

### scripts/ex/meta_*（不再引用 ExData / ExProfile / ExItemView）
- meta_kit：`q_col(tier)` = Data.TIER_COLORS；新 `item_col / icon(it)`（UiStyle.icon(Items.icon_name) 兜底种类图 / 储物袋）/ `kind_name` / `realm_col` / `draw_realm_crest(realm, step)`；`power(realm, lv, gear)` = CS.power；Tile 右上角写 ×N 或 `Items.tier_word`，耐久条删了。老的 `draw_crest(rank)` 留着没人用。
- meta_ui：钱只剩灵石；第二块换成境界小牌（小徽记 +「元婴期 · 2 层」）；通知读 `Profile.notice`；LEGACY 改成老洞府编号（0 备战·仓库 / 1 坊市 / 2 坊市·丹房 / 3 备战·储物戒 / 4 坊市·出售 / 5 英雄 / 6 境界）；页名认 prep / stash / ring / shop / alchemy / sell / rank / realm / hero。
- meta_prep（备战）：左 = 英雄小像 + 3 佩戴法宝 + 4 随身丹符，脚下「元婴期 · 第 N 层」+ 修为细条 + 战力（CS.power，佩戴 / 取下滚数 + 差值）；中 = 仓库（叠格，abode_ui._stacks）/ 储物戒 两页 + 七个筛选；底下 领散修行囊 / 扩储物戒；右 = 说明 + 佩戴 / 随身带上 / 服下 / 服下这一摞 / 收进储物戒 / 卖出 / 卖出这一摞 / 取下 / 放回仓库 / 取回仓库；古宝以上、破境丹卖前确认；瓶颈时左上角金字「带上X丹去修炼场渡劫」。
- meta_shop（坊市）：丹药 / 符箓 / 法宝 / 破境丹（Items.shop() 按种类分）｜丹房（Items.recipes() + Profile.craft，详情列配料有 / 要）/ 储物戒（扩格）/ 出售（仓库叠格，卖 1 / 全部，一键出售 = Profile.sell_junk 先确认件数总价）；买 1 / 买 10（法宝只有买 1）；只用灵石。
- meta_rank（境界）：境界徽记 + 层 + 本层修为条，瓶颈时转朱砂并写「需X丹 ×1（有 N）+ 灵石 Y，到修炼场渡劫」；六张战绩 入境 / 撤离 / 陨落 / 单局最高 / 擂台胜 / 身家 + 一行战力；底下八境路，元婴那格「开放沙海古墟 / 天工秘所」金字；自检接口 `info()`。
- ex_item_view.gd：**没改**。meta_* 已经不用它了，现在只剩 ex_hud / ex_lobby_ui（第二阶段删的）在用，W4 可以连它一起删。它整份就是画 ExData 物品的，去掉 ExData 等于掏空。

### _tasks/ui_kit
- meta_ui_test.gd：整段改成修仙版（自检档塞元婴期 + 各种老物品，45 项检查 + 23 张图）。
- meta_game_test.gd：ExProfile → Profile；备战页佩戴 / 取下法宝；查一键服丹条在；「段位」→「境界」；回退参数改 `--old-abode`。
- hero_select_test.gd / hero_select_game_test.gd：ExProfile → Profile；game_test 里「洞府的英雄按钮」改成看备战页小像，meta_ui 开着时 3D 本来就关着、关掉要等 0.12 秒淡出。
- abode_open_test.gd：必须带 `--abode-open-test`（以前不带参数开机会按玩家正式存档结算离线并存盘），带了开的是老洞府。
- select_test.gd：带 `--select-test` 多走一段：入境页英雄行、炼气开不了沙海古墟、元婴能开（拍 select_modes_desert.jpg）。

## 怎么测的、结果
- 单文件 `--check-only`：main / hud / level_select / hub_hall / hall_pills / meta_* / 各 ui_kit 测试全过；`--headless --quit-after 400 -- --w3-boot` 无报错。
- `meta_ui_test.gd`（桌面 1701×900 forward_plus）：**全部通过**（45 项检查）；手机档（1600×740、gl_compatibility、--touch --lite --web-fonts）：**全部通过**。图在 `_shots/preview/w3/metaui_d_*.jpg` / `metaui_m_*.jpg`，看过备战 / 坊市丹房 / 出售 / 境界（含瓶颈）桌面和手机两档，版式正常。
- `meta_game_test.gd --qa-metaui`：**全部通过**（四个入口、一键服丹条、备战佩戴 / 取下战力 37500 → 52500 → 回落、坊市 / 境界 / 英雄、仓库 / 商店建筑落页）。
- `hero_select_game_test.gd --qa-heroui`：改完后**全部通过**。
- `--hub-shot`：门（炼气 [0, 1]、元婴 [2, 3]、透明度 0.45 / 0、提示文字对）、仓库 / 商店页签 0 / 1、打坐、瓶颈、修炼场渡劫（筑基，Lv.4）、实心、掉岛、擂台、试剑台往返、木兰草原进出 —— 全部符合期望。
- `--hub-shot --farm-shot` / `--farm-plant`：农场恢复后能进、能种、能收、存档 cells 正常。
- `abode_test --abode-test`、`abode_open_test --abode-open-test`（老洞府打开 / 暂停 / 关掉恢复）正常。
- `select_test --select-test`：炼气开不了沙海古墟、元婴能开、英雄三个按钮。

## 需要别人改（不在我名下）
- **scripts/touch_controls.gd:145-148**：`_ground_skills` 问 `main._ex_mode()`，main 里这个函数已按契约删掉 → 触屏的英雄技能键落地永远不露。改成 `return m != null and m.get("level") != null`（和 hud.gd:650 一样：任何关卡里都露）。
- **scripts/ex/hero_select_ui.gd（W1）**：没问题，W1 已改成 Profile。
- **字体（负责人）**：新字要跑 font_check / 毛笔字子集：「境界」「元婴可入」「主线大世界」「丹房」「凶险」「方可入内」「瓶颈」「霸主」「散修行囊」「过期丹」「开放沙海古墟」「借天地元气」「五行遁术」「法相合一」「大罡剑阵」等；手机图里「寻宝符」的「寻」渲染成近似「手」，像是随包毛笔字缺字或字形问题。
- **W4**：ex_item_view.gd 现在只有 ex_hud / ex_lobby_ui 在用，可以一起删；meta_kit 的 `draw_crest(rank) / rank_tier / TIER_COL` 旧段位徽记也可以删（没人调了）。

## 没做 / 留意
- `_tasks/ui_kit/hero_select_test.gd` 里 6 条不通过是**老的**：它按两位英雄写的（一闪 → 瞬狱、最后一位往左划弹回、方向键换回御剑……），现在有镇岳 / 苍鸿 / 霜华三位，和解耦无关，没动断言（归英雄界面那边）。
- 「一键服丹」条和备战页「服下」两个入口共用 `HallPills.eat_stack`；一键服丹的整条 UI 没变。
- hud 的 `INTRO_LINES` 引导记在 `stats.intro`（不在 STAT_KEYS 里，raid_profile 的 add_stat 注释说照记、_fix_types 不会删）。
- warmup tag 仍传 "ex"（W2b 说两种都认）。
- 没启动游戏给用户、没部署（这一轮由负责人统一做）。
