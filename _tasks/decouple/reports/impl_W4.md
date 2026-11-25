# W4（集成）报告 · 2026-11-25

按 CONTRACT 第 0 节：只用 Edit 改已有文件；第一次改某个文件之前，先备份到 `_tasks/decouple/backup/<文件名>.W4.txt`。没有 git commit / push / 切分支，没关任何游戏窗口，也没读 _shots 下的 PNG。`--import` 拿了 `godot.lock`，用完已经 rmdir。

## 1. 第一阶段的跨文件请求

| 请求 | 处理 | 位置 |
|---|---|---|
| W1 / W3：touch_controls 地上的英雄技能键原来要问 `main._ex_mode()`（这个函数已删） | `_ex_ground()` 改成 `m != null and m.get("level") != null`：任何关卡里地上都露，主城不露，规则同 hud.gd:650 `_ground_skills` | scripts/touch_controls.gd:145-148、:170（注释） |
| W1：境界页的战绩卡要有数据 | ① `_finish` 里 `Profile.add_stat("kills", kills)`，在 end_raid 之前调；kills = 本局杀的怪 + AI 修士。② 真人 PvP 击杀：联机里陨落、而且死前 10 秒内被真人打过（`_killer` / `_killer_t`，原来记了没用），就借现有的「§」小消息通道发 `§k <killer id>`；收到的人如果是自己，就 `Profile.add_stat("pk_kills")`。协议没变：老版本 `_net_small` 不认 §k，直接忽略 | scripts/raid_manager.gd:3407-3410（`_finish`）、:1082-1084（`_net_small`） |
| W1：零散的灵石奖励改走 `Profile.add_lingshi` | raid_manager 里没有直接加灵石的地方（只有扣灵石，走 Profile 原有接口），不用改 | — |
| W1：meta_prep / hero_select_game_test 里的 ExProfile.hero()；level_select 的英雄那一排 | 核对过，W3 已经改成 Profile，全仓 grep 不到 | — |
| W2a：raid_selftest.gd:92 调了 abode 的 `_select`，`--raid-econ` 报错 | 改成：meta_ui 的 `page` 有 `select` 就调 `page.select("stash", 0)`；老洞府（`--old-abode`）还是调 `_select` | scripts/raid_selftest.gd:91-97 |
| W2a：shen_shi.gd 里 `get_meta("beam", null)` 缺键时报 ERROR | ring / beam 两处都改成先 `has_meta` 再取 | scripts/shen_shi.gd:406-408 |
| W2a：ex_mobs 首领的 hp / atk 倍率 | W2b 已经填了，自检里凌幽血 15021758，跟老公式对得上 | — |
| W2b：别人名下的首领打到我身上时，单下没封顶 | `to_player_from` 里，来源带 meta `hit_cap` 的，结果再和它取 min（照 extract_manager:1295 的写法） | scripts/raid_manager.gd:479-485 |
| W2b：新图 warmup 用哪个 tag | main 那边不用改（W2b 已说明） | — |
| W2b：`--boss-test-ex` / ex_boss_selftest 留不留 | **删掉**（理由见第 2 节） | — |
| W3：ex_item_view.gd 删掉 | 删了（见第 2 节） | — |
| W3：meta_kit 里老段位徽记的几个函数（draw_crest / rank_tier / tier_col / TIER_COL）已经没人调 | **没删**。纯死代码，不影响编译；extraction-pvp 分支还在用，留着以后两边搬修补时 diff 小 | scripts/ex/meta_kit.gd:33、:441-526 |
| W3：hero_select_test 的断言还按两位英雄写 | 改成三位英雄：① 「一闪带瞬狱」改成「苍鸿 E 带『觉醒后 → 』」（第三轮的 E 是飞光）；② 先一路往左划到最后一位（`ui._ids` 的最后一个），再划一下看能不能弹回来（转盘位置应为 ids.size()-1）；③ 出战、方向键左、点右侧、真点圆片这几步，预期都换成最后一位 / 前一位 | _tasks/ui_kit/hero_select_test.gd:253-268、:276、:283、:290、:298 |
| W1：air_melee 里的 kb / flair 按真实境界走 | 没动（air_melee 归格斗专项） | 见第 5 节 |
| W3：font_check / 毛笔字子集 | 字体文件不归我。只跑了只读核对，结果见第 5 节 | — |

**额外修的一个 bug（自检里抓到的）**：scripts/ex/ex_level.gd:232-243 `_leave_soon`。
- 现象：境界不够时，ex_level 等 2.5 秒后发 `exit_requested`。如果 main 那边进图的几步（黑场 + 预热）还没走完，`_switching` 还是 true，`_return_to_hall` 第一行就 return 了，结果人卡在图里出不来，也没有管理器。
- 触发条件：沙漠的黑场大约 2.07 秒，再加上预热就会撞上。第一轮 `--level-test desert` 的 3 项 FAIL 就是这个原因（境界守卫没回到主城，后面再进图也建不出管理器）。
- 改法：等 2.5 秒之后，再等 main 的 `_switching` 变成 false（最多 30 秒）才发信号。

## 2. 第二阶段删除（CONTRACT 第 7 节）

删了以下 11 个脚本，连同各自的 .uid（都在 scripts/ex/ 下）：
- 契约列出的 9 个：ex_profile、ex_data、extract_manager、ex_hud、ex_lobby_ui、ex_doctor、ex_selftest、ex_hud_selftest、ex_lobby_selftest。
- 待定的两个，决定删：
  - ex_item_view：只剩 ex_hud / ex_lobby_ui 两个用户，都已删。
  - ex_boss_selftest：main 里的探针 W3 已经按契约删了，主干上没有入口；它测的是 ExBoss 在 pts_k=1 时（搜打撤）的老行为，这条在 extraction-pvp 分支上照样能跑；主干这边的首领由 xiu_map_selftest 的「首领走近自动刷出 / 能被打死」两项覆盖。

待定的第三个 ex_level_shot.gd **留着**：它只 preload map_def / minimap，不碰 extract_manager；main 里的 `--level-shot` 探针还在用它，能正常载入。

全仓 grep `ExProfile|ExData|ex_profile|ex_data|extract_manager|ex_hud|ex_lobby|ex_doctor`：
- 范围：scripts/、scenes/、project.godot、export_presets.cfg。
- 结果：**非注释的命中是 0**。唯一一条 `arena_floor.gd:126 "vertex_data"` 是子串误命中。剩下的都是注释，比如 ex_level / map_def / grid_world / raid_camps / raid_manager / net / warmup / ink_style / main:318、811。
- project.godot 里没有 autoload；scenes/ 和 export_presets 都不引用这些文件。
- _tasks 下还有引用、但**不进包**的：
  - `_tasks/extraction_refactor/tools/ex_data_check.gd`、`_tasks/extraction_refactor/review_tmp/rules_chips.gd`：搜打撤会话的工具，只在 extraction-pvp 分支上有用。
  - `_tasks/tsb/check_load.gd`：列表里有 `ex/ex_hud`，文件不存在时它会打印「没有」然后跳过，不会报错。

## 3. 编译检查

1. 先拿锁，再跑 `--headless --path . --import`：exit 0，没有 ERROR，类缓存已经更新。
2. `--headless --path . --quit`：exit 0，没有 SCRIPT ERROR / Parse Error。
3. 新写了 `_tasks/decouple/w4/check_all.gd`。它把 scripts/ 下所有 .gd 挨个 load 一遍，再检查 can_instantiate；参数可以加别的目录：
   - scripts/：**165 个脚本，载不进来 0 个**，日志里没有 ERROR。
   - _tasks/ui_kit、_tasks/decouple/w1、_tasks/tsb：**21 个脚本，0 个失败**。
   - 用法：`Godot --headless --path . -s res://_tasks/decouple/w4/check_all.gd [-- res://目录 ...]`
4. 改过 ex_level.gd 之后单独 `--check-only`：没有报错。

## 4. 自检（用的是测试存档，不碰玩家的档）

| 命令 | 结果 |
|---|---|
| `--headless -- --level-test desert`（第一轮） | 3 FAIL（就是上面 `_leave_soon` 那个竞态） |
| `--headless -- --level-test desert`（修了之后） | **21/21 PASS**，38 秒 |
| `--headless -- --level-test lab` | **21/21 PASS**，38 秒 |
| `--headless -- --level-test mulan`（大世界回归） | **10/10 PASS** |
| `--headless -- --hero-test=realm` | **结论 PASS**（英雄数值跟着境界走） |
| `run_hidden -- --raid-shot --raid-econ` | **整局跑完，SCRIPT ERROR 0 条**。洞府界面那一段（raid_selftest:92）不再报错；佩戴上限、扩储物戒、炼丹、一键出售、大厅一键服丹、搜点、宝库、瓶颈 / 起劫扣灵石、渡劫、传送阵轮转、巢穴重生、破界符撤离、心得结算、禁地封闭陨落，这些项的数都和「应为」对得上 |
| `run_hidden -s res://_tasks/ui_kit/hero_select_test.gd -- <目录> --hero-ui-test` | **结论：全部通过**（三位英雄 yujian / canghong / shuanghua；划到霜华后能弹回来，转盘位置 2.000；出战存档是 shuanghua） |

改完 ex_level 之后又跑了一遍 check_all，结果还是 165 个脚本全过。`--quit` 连跑三次，只有一次在退出时出现引擎的 `1 resources still in use at exit`，属于关机清理的噪声，不是脚本错误。

## 5. 还没解决的问题（交给负责人 / 别的会话）

1. **字体**：只读跑了 `python -I _tasks/ui_kit/font_check.py`（输出 `_shots/font_check.txt`），随包正文字体里有 2 个字没补上：
   - 「宇」，在 level_select.gd 里；
   - 「摞」，在 meta_prep.gd 的「服下这一摞」里。

   负责人需要跑 `font_check.py --patch`，再 `--import` 一遍，然后做毛笔字子集；W3 列的新字，以及「寻」在毛笔字体里显示成「手」的问题，也要一起核。
2. air_melee 里的 kb / flair 现在按英雄的真实境界走（炼气 kb 0.8，大乘 1.72）。要不要给英雄的 kb 封顶，由格斗专项会话决定（报告 C 的 R1 / R2）。
3. W2a 报告说大世界 `--raid-shot` 里有一行「空战连击打 噬金虫：血 1331 -> 1331」（打了没掉血），可能跟 W1 的英雄改动有关，没人追查。
4. pvp_rules_selftest 的 mash 场景还是一下都没打中（W1 报告里说过，是老问题）。
5. 联机协议变了：W2b 删掉了一批 RPC，W1 改成按真实境界算伤害。主干的包和 extraction-pvp 的包不能在同一个局域网房间里混着连，建议在握手里加一个协议版本号。§k 是借现有通道发的，不影响兼容。
6. 新加的 PvP 击杀统计只在**联机里陨落**时才会发（单机里没有真人）。双开实测没做。
7. 每轮做完要启动游戏给用户试玩、部署网页版，这两件留给负责人。
