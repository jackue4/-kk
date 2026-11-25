# impl_T_heroes：英雄 / 存档 测试（2026-11-25）

按 CONTRACT 第 0 节：只改 W1 名下的文件（只改了 scripts/hero_selftest.gd），改前备份 `_tasks/decouple/backup/hero_selftest.gd.T_heroes.txt`；
新文件 `_tasks/decouple/t_heroes/persist_set.gd`（只碰自检存档）。没 commit / push / 切分支，没动任何正在跑的游戏窗口，没读 _shots 下的 PNG，没跑 --import。

## 结论
没找到 W1 文件里的 bug。要求核的几项全部通过：三位英雄全部免费、选择存进 raid_profile 并在下次开机生效、伤害基数跟境界走（八境全量）、三位英雄之间数值表一致、PvP 每档 ×1.08、主城玩家牌显示境界 / 战力 / 修为、头像跟英雄。

## 改了什么（scripts/hero_selftest.gd，只加强 `--hero-test=realm` 自检，不动游戏逻辑）
- `:629-635` 开机先核「主城开机的主角英雄 = Profile.hero()」（main._apply_combat_mode 那条路），再跑新的 `_plate_check()`。
- `:643-671` 境界表从抽 4 档（0/2/5/7）改成八境全量 `range(Realm.LIST.size())`；新增「不分强弱」核对：同一境界下三位英雄的 player.realm 表（去掉 HERO_LOOK_KEYS 和 art）+ mp_max 完全一致。
- `:749-776` 新增 `_plate_check()`：主城玩家牌（group player_plate）在炼气 / 元婴 / 大乘下 `_realm` = 「X期」、战力非空、修为等级 ≥ 1；依次换三位英雄后 `_skin_hero` 跟着换；最后还原境界和存档英雄。

## 怎么测的、结果（全用自检存档）
| 命令 | 结果 |
|---|---|
| `--headless -- --hero-test=realm`（改前） | PASS |
| `--headless -s res://_tasks/decouple/w1/profile_api_check.gd -- --w1-check` | PASS 13/13 |
| `--headless -s res://_tasks/decouple/t_heroes/persist_set.gd -- --t-persist --keep-profile shuanghua`，再 `--headless -- --keep-profile --hero-test=realm` | 文件里 hero = shuanghua；下次开机「主城开机：主角英雄 shuanghua / 存档英雄 shuanghua」；结论 PASS |
| 同上 realm 表 | 炼气 8 / 筑基 12 / 结丹 18 / 元婴 26 / 化神 38 / 炼虚 52 / 合体 75 / 大乘 110，三位英雄 = 老角色；三位数值表逐境一致 |
| 同上 实打木桩 | 三位 炼虚 ÷ 炼气 = 6.500（应 6.500）；镇岳 / 霜华 0.5 单位、苍鸿 0.45 单位（招式设计差，见报告 C 1.4） |
| 同上 PvP | 炼虚打元婴 = 炼虚打炼虚 ×1.1664（= 1.08²），封顶倍数 1.1664 |
| 同上 玩家牌 | 炼气期 战力 4.65万 Lv.1 / 元婴期 1226万 Lv.12 / 大乘期 47.03亿 Lv.22；头像跟英雄 |
| `--headless -- --tsb-show=yujian / canghong / shuanghua` | 三位都跑完 exit 0，基数 8（炼气），四技能 + 觉醒四招都打出单位，无报错 |
| `run_pair.py --pvp-rules=hero --pvp-realm=3`（苍鸿 vs 霜华） | 两边元婴、灵力上限 106；b 掉血 49；两边报错 0 |
| `run_pair.py --pvp-rules=hero --pvp-realm=0`（镇岳 vs 苍鸿） | 炼气也在空战、能放技能（air_skill 16、觉醒 2）；b 掉血 71；报错 0 |
| `run_hidden -- --hub-shot --arena-duel` | 单机全流程跑完：匹配 / 取消 / AI 入场 / 胜 / 负 / 出界 / 时辰到 / 结丹 化神 大乘档；胜 2 负 4；SCRIPT ERROR 0 |
| `run_hidden -- --qa-arena` | 结果 win，SCRIPT ERROR 0（帧耗是隐藏窗口下的数，不作结论） |
| `run_hidden -s res://_tasks/ui_kit/hero_select_test.gd -- <目录> --hero-ui-test` | 全部通过；出战后存档 = shuanghua；界面副标题「英雄只换招式，气血、灵力和装备都一样」，没有价格 / 解锁 |
| `run_hidden -- --raid-shot` | 「空战连击打 小怪：血 2960 -> 已击杀（主角 Lv.13）」：英雄在大世界打怪正常；整局跑完到「回到大厅=true」，exit 0，SCRIPT ERROR 0。W4 报告第 5 节第 3 条的「1331 -> 1331」这次没复现 |
| `-s res://_tasks/decouple/w4/check_all.gd -- res://scripts res://_tasks/decouple` | 172 个脚本，载不进来 0 个 |

## 遗留 / 注意
- **自检存档是所有代理共用的**（user://xiuxian_profile_selftest.json）。别的测试同时在跑时，会改到存档里的 hero / lv：第一次跑「存下 → 开机」时，读到的是别人写的 canghong。单独再跑一次就对上了。以后要做并发测试，最好给每个测试单独一个存档路径。
- 擂台的 `arena_wins` 统计只核了代码（arena_duel.gd:563）。跑完以后存档已经被别的进程重置了，读不到真实的数。
- `remote_player.realm_tag`：大乘档的层数 = lv − 21，会显示到「大乘期 第78层」（大乘以后没有瓶颈，等级一路涨到 99）。不是 bug，要不要封顶由负责人决定。
- 报告 C 的 R1 / R2（air_melee 的 kb / flair 按真实境界作用在英雄身上）照旧没动，归格斗专项。
