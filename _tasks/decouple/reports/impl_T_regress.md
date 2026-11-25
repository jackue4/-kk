# T_regress 报告：老回归套件 基线 5c25796 vs 现在的工作区（2026-11-25）

我没有改任何项目文件（只读）。没有 commit / push / 切分支。没关过用户的游戏窗口（PID 15364），只按 PID 停过我自己起的测试实例。没读 _shots 下的 PNG。

## 怎么测的
- **基线**：`git worktree add --detach D:/GodotProjects/_wt_base 5c25796`，复制了一份 `.godot` 导入缓存，再 `--headless --import`（在 worktree 里跑，不碰工程的锁）。跑完已经 `git worktree remove --force` + `prune`，临时目录都删了。
- **隔离**：基线和现在各用一套独立的 APPDATA（`D:/GodotProjects/_wt_{base,cur}_appdata`，已删），这样测试存档、着色器缓存都不串，也不碰玩家自己的存档。大世界类自检全部加了 `--no-lan`。
- **跑法**：每项都用 `python -I _tasks/trailer/run_hidden.py <工程> <日志> --resolution 1280x720 --audio-driver Dummy -- <参数>`，基线和现在同时起一对，一项接一项跑。帧耗类的数字后来又单独、轮流各跑了一遍（见第 3 节）。
- **日志**：在工程外面的 `D:/GodotProjects/_wt_logs/`，`<项>_{base,cur}_out.txt / _err.txt`，总表是 `summary.txt`。脚本是 `run_pair.sh / queue.sh / queue2.sh`，另有三个探针：`qa_arena_probe.gd`、`hero_fight_probe.gd`、`pace_mob_probe.gd`。
- **机器很挤**：用户的游戏开着，别的代理也在同时跑自检，显卡是 GTX 1050 Ti。第一轮一次起了 4 个实例，报了 `VK_ERROR_OUT_OF_HOST_MEMORY`，我按 PID 停掉重跑了，下面的数据都不是那一轮的。

## 1. 结果总表（所有项 SCRIPT ERROR / SHADER ERROR / Parse Error 都是 0，只有基线的 farm 一项例外）

| 命令（`-- ` 之后的参数，都加了 `--no-lan`） | 基线 | 现在 | 结论 |
|---|---|---|---|
| `--raid-shot --raid-econ` | 26 行 [econ]，「一键服丹」那项是 -1（服丹已删） | 26 行全对得上「应为」；一键服丹 5 颗，Lv.1 → Lv.2 529 | 通过，服丹恢复了 |
| `--raid-shot --raid-move` | 1~7 段都对 | 1~7 段都对（单帧最大竖直位移更小：0.25 比 1.00） | 通过 |
| `--raid-shot --raid-pace --pace-combat` | 见 json | 各境界灵力 / 地面连招 / 剑诀 / 怪打主角的条数一样；空中普攻、连发有随机波动（化神连发 6.7 比 15.3） | 通过（噪声） |
| `--raid-shot --raid-pace --pace-insight` | 小结 PASS | 小结 PASS，数字几乎一样 | 通过 |
| `--raid-shot --raid-pace --pace-min=1`（五区） | 杀怪/分 19 / 22 / 20 / 25 / 1 | 26 / 26 / 20 / 27 / 1.7（坠魔谷 0.6 分钟时陨落） | 0~3 区通过；4 区见第 2 节第 3 条 |
| `--duel-shot --spark --spark-tiers` | 全部正常 | 第一遍（两个实例一起跑）：结丹重劈 0、空战结丹 0、对波没进去，帧耗 49 比 16.6 ms。**单独重跑：和基线逐项一样**（伤害 9/17、11/50 … 71/539，帧耗都是 16.6） | 通过（第一遍是机器太挤） |
| `--duel-shot --spark --spark-feat` | 正常 | 第一遍炼虚长按木人掉血 0、帧耗 82 ms（太挤）；gl 档那一遍和基线一致 | 通过 |
| `--duel-shot --spark --spark-feat --touch`，加 `--rendering-method gl_compatibility` | 正常 | 和基线一致 | 通过 |
| `--duel-shot --spark --spark-cam --cam-quick` | 正常 | 新镜头的指标同样好，或者更好 | 通过 |
| `--duel-shot --spark --spark-clip --clip-quick` | 结丹五连最深 +2.18 m | +0.68 m，其余持平 | 通过（噪声） |
| `--duel-shot --spark --spark-moves` | 正常 | 只有随机差异 | 通过 |
| `--duel-shot --spark --spark-otg` | 正常 | 一样 | 通过 |
| `--duel-shot --spark --spark-feat --pvp-outline` | 不通过 0 项 / 13 项通过 | 不通过 0 项 / 13 项通过 | 通过 |
| `--raid-shot --shenshi` | 19 个 ✓ | 19 个 ✓；单独重跑帧耗 16.7 比 16.7 ms，影子网格件数也一样 | 通过 |
| `--qa-solid` | 天南城 / 坠魔谷 / 血色禁地全对 | 全对 | 通过 |
| `--hub-shot --farm-plant` | **SCRIPT ERROR**：farm_selftest.gd:20，农场没建 | 14 行 [plant] 全对，「done」 | 通过，恢复了 |
| `--hub-shot`（主城自检） | 打坐 / 修炼场渡劫都失败（已删）；门 [0,1,2,3] | 门：炼气 [0,1]、元婴 [2,3]，有拦截提示和半透明；打坐 +3.5；渡劫扣 500 灵石，境界 0 → 1 | 通过，恢复了 |
| `--hub-shot --arena-duel`（加 `--touch` + gl 档也跑了） | 陪练结丹 Lv.7 | 陪练炼气 Lv.1，流程每一步都对；大世界 PvP 表现在有境界差（1.2× / 1.9×） | 通过（差异是契约第 1 节要的） |
| `--qa-arena` | win | **第一次：走进了大世界匹配、开了真房间，然后卡住**；重跑两次都是 win | 见第 2 节第 1 条 |
| `--raid-shot`（完整一局） | 演示角色在云梦山陨落，后半段跳过 | 一局跑完：Boss / 修士 / 开箱 / 撤离结算都有 | 通过 |
| `--hero-test` | 只打印「已由 --tsb-show 接替」 | 同左 | — |
| `--hero-test=realm`（只有现在有） | — | 结论 PASS | 通过 |
| `--level-test desert` / `lab` / `mulan`（渲染下） | —（基线是另一套自检） | 21/21、21/21、10/10 PASS | 通过 |

## 2. 可能的回归和覆盖缺口

1. **`--qa-arena` 偶发：没上擂台，而是去了木兰草原匹配，还开了一个没隔离端口的真房间**（PLAUSIBLE，没能复现）
   - 现象：现在这版第一次跑，先打印了 `[arena] qa 开机完成…上台`，紧接着是 `[match] 组队人数 1 联机=true 房主=true`，然后 `[meadow] 载入`，`[raid] 结算：陨落…`，之后一直卡着。我在第 9 分钟按 PID 停掉了。
   - 这条路 `level_ui.picked` → `main._enter_level` → `_matchmake()` → `net.host`，用的是写死的 24680 端口，测试模式下**不偏移**。用户这时候正开着游戏。
   - 重跑两次（一次加了探针、一次原样）都正常 win。
   - 推测：要么是隐藏窗口收到了用户的真实按键（记忆 xiuxian-godot-workflow 里有记录），要么是开机时某个界面的焦点按钮被 ui_accept 触发了。
   - 风险：自检一旦误进匹配，就会在局域网里挂一个真房间。这是老问题（记忆 lan-presence 写过，副本房间那套没隔离），但这次真的撞上了。建议 main.gd 在 `Profile.test_mode()` 下给 net 的房间端口也加 +100，或者测试模式下 `_matchmake` 直接走单人。
2. **大世界的正式玩法现在是英雄档，老回归套件一项都没覆盖到**（CONFIRMED，是覆盖缺口，不是数字回归）
   - 基线：从主城进木兰草原走 `_apply_combat_mode("legacy")` → `set_hero("")`。现在：一律 `set_hero(Profile.hero())`（契约第 2 节）。
   - 所有老自检（`--raid-shot`、`--duel-shot` 这些）都是 legacy 开机，不建主城，所以 `hero_id` 一直是空的，测的仍然是老角色。`--level-test mulan` 也没有真按键打怪（`_kill` 走的是 `net_damage`）。
   - 我写了 `hero_fight_probe.gd`：从主城单人进 mulan，对最近的一只地面小怪各打 3 秒，然后只留一只、站着挨打 4 秒。

     | 项目 | 基线（老角色，炼气） | 现在（镇岳，炼气） |
     |---|---|---|
     | 地面普攻 3 秒，草原妖狼掉血 | 2685 / 3426 | 1482 / 741 |
     | 空中普攻 3 秒 | 6852 / 6852 | 2148 / 0 / 0（三次） |
     | Z 技能 | 无 | 0 / 385 / 6401（元婴） |
     | 挨打，每下掉多少 | 8.72 | 8.72（一样） |

   - E 会把怪打飞，落地触发 raid_mob 的 `hp_max × 0.12` 砸地伤害。这是老机制：我把 hp_max 设成了 1e15，所以显示成 1.2e14。
   - 结论：英雄在大世界能打出伤害、没有脚本错误，受击换算也没变；但打怪输出明显比老角色低，而且空中 M1 打地面小怪经常是 0。
   - 这组数是我手摆的位置（每 0.75 秒把主角瞬移到怪的 +Z 方向 2.2 米），不是正式数值，但值得「格斗专项」或者 W1 用真实输入再量一次（`--raid-pace` 的假主角是直接调 receive_hit，测不出这个）。
3. **坠魔谷（4 区）的杀怪节奏偏慢**（PLAUSIBLE，没找到原因）
   - 命令：`--raid-shot --raid-pace --pace-min=1 --pace-regions=4`。基线和现在各跑了 8 次（5 次同时跑，3 次单独轮流跑）：

     | | 基线 | 现在 |
     |---|---|---|
     | 杀怪 / 分钟（不含第一轮全区） | 11.0 / 8.7 / 3.0 / 5.4 / 11.0 / 6.3 / 16.0，平均约 8.8 | 4.0 / 3.9 / 1.0 / 0.0 / 7.0 / 4.0 / 4.0，平均约 3.4 |
     | 平均几下打死一只 | 6~37 | 16~132 |
     | 第一轮全区那次 | 每分钟 1.0 | 每分钟 1.7 |

     0~3 区持平或者更快，只有 4 区慢。
   - 用 `pace_mob_probe.gd` 核过：同一种怪、同一等级，两边的 hp_max 和「一下扣多少」**完全一样**。比如裂风兽 Lv.19：72134477 / 3336244，古魔傀影 Lv.20：125688861 / 3255666。
   - 4 区有一道等级断崖：Lv.18 一只要 2.5 下，Lv.19 要 21.6 下。所以杀得快慢主要看刷出来的怪是 18 级还是 19~20 级。
   - 最后一次采样里现在这版反而更快（6 比 2~3），所以样本还不够下结论。
   - 怀疑方向：raid_camps / 导演在 4 区刷怪的等级分布，也就是 depth_of 改走 geo 之后，落点或深度有没有偏移。建议 W2a 拿 `--raid-pace --pace-spawn` 或 `--pace-home=200` 做同种子的老 / 新对照。
4. **`--raid-shot` 里「空战连击打 噬金虫：血 1331 -> 1331」**（W4 报告的第 5 节第 3 条）：**不是这次的回归**。历史日志（`_shots/*.txt`、`_tasks/*/logs`）里同样有「噬金虫 21 -> 21」「精英·噬金虫王 3329 -> 3329」「草原妖狼 2960 -> 2960」。是演示脚本挑「最近一只怪」挑到浮空怪时 5 下空中普攻打不着，跟着随机走，老问题。
5. 帧耗：第一遍同时跑时，现在这版有几项慢 3~4 倍（tiers / feat / shenshi）。单独轮流重跑后完全一样（悬停 16.6 比 16.6、神识 16.7 比 16.7）。**没有性能回归**，是 GPU 争用。
   - 主城多了 20 个绘制调用（120 → 140，图元 465k → 499k），是恢复的灵田 / 打坐区带来的，预期之内。

## 3. 符合契约的预期差异（不算回归）
- 主城里的英雄跟着存档境界走：擂台从「结丹 Lv.7 / 陪练 756 血」变成「炼气 Lv.1 / 336 血」；大世界 PvP 表重新看境界差。
- 主城的门：2 / 3 要元婴才能进；一键服丹、打坐、修炼场渡劫、灵田都恢复了（基线这几项是失败或报错）。

## 4. 需要别人改（只是建议，我没动）
- **main.gd / net.gd（W3 / W2b）**：测试模式（`Profile.test_mode()`）下，`_matchmake` / `net.host` 的房间端口也要隔离，跟在场 / 擂台一样 +100；或者测试模式下直接走单人。复现：`run_hidden … -- --qa-arena --no-lan`，偶发，第一次跑出现过；出现时日志里有 `[match] 组队人数 1 联机=true 房主=true`。
- **W1 / 格斗专项**：给「英雄档在大世界打 raid_mob」加一个真实输入的自检。复现：`run_hidden … -s D:/GodotProjects/_wt_logs/hero_fight_probe.gd -- --qa-herofight --probe-realm=0 --no-lan`，看 `[hf] air` 那一行，3 秒掉血 0。
- **W2a**：用同种子老 / 新对照，查坠魔谷刷怪等级的分布。复现：`run_hidden … -- --raid-shot --raid-pace --pace-min=1 --pace-regions=4 --no-lan`，跟 5c25796 交替跑几次比 kpm。

## 5. 没做的
- 局域网双开（`--net=host/mate/foe`、`--lan-test`）没跑：用户正开着游戏，副本房间那套端口没隔离（见第 2 节第 1 条）。
- 网页包、手机档（`--touch`）只跑了 feat_gl 和 arena_gl 两项。
