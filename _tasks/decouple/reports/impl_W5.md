# impl_W5：测试员报上来的问题，逐条处理（2026-11-25）

按 CONTRACT 第 0 节执行：
- 只用 Edit 改文件，改之前都备份成 `_tasks/decouple/backup/<文件名>.W5.txt`。备份了 arena_selftest、lan_presence、map_def、meta_kit、ex_mobs；ex_mobs 最后没改。
- 没有 commit / push / 切分支，也没跑 `--import`。
- 用户的游戏进程 15364 一直开着，我没碰；没读 `_shots/*.png`。
- 我自己的探针放在 `_tasks/decouple/w5/`，不进包。日志在工程外的 `D:/GodotProjects/_w5_logs/`。
- 为了对照基线，临时建了一个 detached worktree `D:/GodotProjects/_w5_base`（5c25796），在里面单独 import，用完已经 `git worktree remove --force` 加 `prune`，临时 APPDATA 也删了。

## 改了什么

| 文件:行 | 改动 |
|---|---|
| `scripts/lan_presence.gd:47-50`（新变量 `quiet`）、`:66-70`、`:144`、`:337` | 自检 / 演示模式（`Profile.test_mode()`）默认静默：不广播自己，也不飘「道友 X 上线了」，但照样绑 +100 端口、照样收包（hero_selftest 会往自己端口塞包测木偶）。命令行带 `--lan-test…` 时不静默，在场双开自检照常互相看见。 |
| `scripts/ex/map_def.gd:331-332` | 沙漠洞窟刷怪点 c32：(790,-60,16) 改成 (804,-60,15)。 |
| `scripts/ex/map_def.gd:373-376` | 洞窟箱子 b57：(830,-116) 改成 (825,-119)；原来正好压在石柱 (830,-116) r2.5 上，又在岩体里。b58：(1256,-60) 改成 (1252,-62)。b69：(1020,-92) 改成 (1015,-95)。坐标取自 ex_geo 兜底最后一版挪到的位置。 |
| `scripts/ex/meta_kit.gd:193-195` `para()` | `AUTOWRAP_ARBITRARY` 改成 `AUTOWRAP_WORD_SMART`。中文仍然可以逐字断行；数字、百分号、英文不会再被拆开。level_select:496 和 farm_plots 早就这样用，网页包上没问题。 |
| `scripts/arena_selftest.gd:412-417`、`:438-442`（`--qa-arena` 的 drive） | 开打前关掉界面输入（`gui_disable_input`）、不抓鼠标；每帧把鼠标设回 VISIBLE。入境页万一被打开了，就关掉并打一行警告。这个驱动本身不点任何界面。 |

改过的 4 个脚本都单独跑了 `--check-only`，0 错误。`w4/check_all.gd` 结果：165 个脚本，0 个载不进。

## 逐条结论

1. **铁穹双卫血量（ex_mobs 22.5 对 11.3）→ 不减半（not-a-bug，数值没动）**
   - 22.5 已经减过一半了。按 B 报告 §3.4 的算式，DarkArea 原版是双卫各 200000、电鞭 / 冰僵 50000，也就是单只 4 倍、一对 8 倍；套 `18 × clamp(200000/80000, …)` 得 45，再按报告「各 × 0.5」才是 22.5。ex_mobs.gd 头注释写的也是这条。
   - 一对合计 45，是本图最强的常规首领凌影（18）的 2.5 倍。沙漠那边的召唤型首领沙渊巨虫（36）是凌幽（18）的 2 倍，量级相当。
   - 双卫另有两只都倒了才掉、互相焊愈的机制。所以拿电鞭（本图最弱的首领）比出来的「四倍」不算 bug。
   - 数值会话要是想拉齐：可以改成各 18（一对 36 = 凌影的 2 倍，和巨虫对凌幽一个比例），改 ex_mobs.gd:103 / :107 两个 `"hp"` 就行。
2. **元婴刚够门槛，进去会被地下室（档 4）的怪、洞窟首领秒（deferred，交数值会话）**
   - 这是契约第 3 节的设计结果，跟大世界一样：元婴走进坠魔谷也是一下死。
   - 首领单下已经有 `hit_cap` 35（ex_boss.gd:265），所以一下打满血只会来自同一帧连中多下。
   - 进层时题字已经会写「凶险 · 此地妖兽X期」（raid_manager `_fixed_sub`）。
   - 要不要收（比如地下室要化神、首领一帧只结算一下）由数值会话定，progression.gd 和 CS 的表我都没动。
3. **map_def 里 4 个点在岩体里 → 已修（fixed）**
   - 修完重跑 `rock_probe`（desert）：洞窟里的 c32 / b57 / b58 / b69 都不在了，「在岩体 / 实心里的点」从 13 个降到 7 个。剩下 7 个是地面叠盒子的原始点，ex_geo `_site` 本来就会处理，搜点不报。
   - 进图时不再打 `[ex_geo] … 挪到` 这一行。
   - extraction-pvp 分支的 map_def 是同一份数据，**那边没改**，要搬就搬这两处坐标。那边 extract_manager 的 `_mob_floor` 也只认地形（T_maps 报过），这次没动。
4. **raid_manager.gd 写到一半落盘，`_mob_floor_fn` not found → 现在不是问题（not-a-bug）**
   - 现在 `_mob_floor_fn` 在 :362，check_all 0 失败，main.gd 能编译。
   - 「落盘的脚本任何时刻都要能编译」这条，记忆 concurrent-writers-check 里本来就有，这里再提醒一次。
5. **自检进程广播局域网在场、主城飘真同事「上线了」→ 已修（fixed）**
   - 那几个名字其实是别的代理的自检进程（都在 +100 端口），不是真同事。现在自检档默认不发、也不飘。
   - 实测（`w5/lan_quiet_probe.gd`，headless）：
     - `--qa-w5lan`：enabled true、quiet true、端口 24801、发出 0 个包；
     - 加 `--lan-test=probe`：quiet false，照常发包。
6. **手机上「寻宝符」看着像「手宝符」→ 字形没错（not-a-bug，留给负责人）**
   - MaShanZheng 子集里有 U+5BFB（uni5BFB）。拿同一份字体用 PIL 画出来，和游戏截图逐笔对过，是同一个字形：毛笔体的「寻」在 16px 格子里，下面的「寸」读起来像「手」。
   - 不缺字、也不是映射错。要改就是让格子里 20px 以下的物品名不用毛笔体（换成 Noto），这属于字体 / 界面负责人的事，我没动。
7. **`para()` 把「+30%」拆成「+3 / 0%」→ 已修（fixed）**
   - 手机档 meta_ui_test（1600x740、gl_compatibility、`--touch --lite --web-fonts`）**全部通过**，截图在 `_shots/preview/w5/metauim_*.jpg`。
   - 备战页现在是「服用：修为 +4.731万、气血」换行接「+30%」，整段不再拆开。坊市、丹房、出售、境界页的版式看过，没有变化。
   - **网页包没实测**。依据是同样用 WORD_SMART 的 level_select 卡片在线上包里是正常的。
8. **测试模式下副本房间端口要隔离 → 早就隔离了（not-a-bug），误入匹配做了缓解（fixed）**
   - net.gd:92 早就有 `port_off = TEST_PORT_OFF if NetProfile.test_mode()`，host / join 和发现包都是 +100。那次 `--qa-arena` 开的房间实际在 24780，不是 24680，碰不到正在玩的人。T_regress 那条「写死 24680」是读错了。
   - 「误进匹配」的路径是：开机 0 秒后 → 主角走进门 0 → 卡片页 → 入境页「开始匹配」。卡片页和入境页的按钮都 `grab_focus` 了，两下 ui_accept 就能点进去，最可能的来源是漏进隐藏窗口的真人空格 / 回车（记忆 xiuxian-godot-workflow）。
   - 已在 `--qa-arena` 驱动里关掉界面输入，并加了入境页兜底关闭。重跑 `--qa-arena --no-lan`：win，各段帧数正常，0 个 SCRIPT ERROR。
9. **大世界英雄档的真实输入自检 → 加了探针；「空中 M1 打 0」是测法问题（not-a-bug）；炼气期英雄输出偏低（deferred）**
   - 新探针 `_tasks/decouple/w5/hero_mob_probe.gd`。用法：`Godot --headless --path . -s res://_tasks/decouple/w5/hero_mob_probe.gd -- --qa-w5hero --probe-realm=N --no-lan`，headless 可跑，约 2 分钟。
   - 流程：主城开机 → 单人进木兰草原 → 御剑、老角色、苍鸿、霜华轮流各两遍：地面贴身按「攻」3 秒、空中按「攻」3 秒。只有离怪超过 9 米才把主角挪回去，并把 40 米内**所有**小怪的掉血都算上。
   - **掉血 0 的原因**：连段会自己挑最近的目标，经常打在旁边另一只怪身上。T_regress 的探针（和我第一版）只记一只怪，所以记成 0。改成全算以后，每一段都有伤害，老角色同样会出现「这只 0、别的怪掉了一大截」。
   - **元婴（3）三秒伤害**（地面 / 空中，两遍）：
     - 御剑 139万 / 72万、61万 / 53万
     - 老角色 46万 / 56万、144万 / 38万
     - 苍鸿 43万 / 6.5万、38万 / 25万
     - 霜华 54万 / 15万、57万 / 35万
     - 同一个量级，波动很大。
   - **炼气（0）**：老角色在地面拳脚，0~1.5万；英雄一按就升空（LIGHT），御剑 0.07万~0.46万，苍鸿 / 霜华约 0.07万~0.11万。炼气期英雄打地面小怪大约只有老角色的三分之一。
     - 这是英雄空战 M1 和 `Realm.COMBAT` 低档的手感 / 数值问题，归「格斗专项」（scripts/heroes/*、air_melee.gd）。我没动那些文件。
10. **坠魔谷（4 区）`--raid-pace` 杀怪慢 → 不是回归（not-a-bug）**
    - 代码层面：逐段核过 raid_manager / raid_camps / player / combat_stats 的 diff。大世界这条路上，凡是改动都是 `geo.fixed` 分支，或者是行为等价的转调。`spawn_wave`、`_level_in`、`_spawn_mob` 的公式一字没变；导演用 `_rng.randomize()`，本来就没有固定种子可以对照。
    - 实测：基线 worktree 和现在的工作区**轮流**跑（不并发，避免 GPU 争用），一共 11 对 `--raid-shot --raid-pace --pace-min=1 --pace-regions=4 --no-lan`。挂了一个旁听探针 `_tasks/decouple/w5/pace_lv_probe.gd`，记下每只刷出来的怪的等级。

      | | 基线 5c25796 | 现在 |
      |---|---|---|
      | 刷出的怪按等级 | Lv.17: 4 / 18: 44 / 19: 141 / 20: 87 / 21: 2 | 17: 1 / 18: 57 / 19: 143 / 20: 44 / 21: 5 |
      | 杀怪 / 分（不算 0.3 分钟内就陨落的） | 3.0 / 3.1 / 7.0 / 3.0 / 3.0 / 4.0 / 4.0 / 3.0 / 4.1 / 4.0，平均约 3.8 | 2.2 / 4.0 / 3.0 / 5.0 / 4.0 / 3.0 / 5.0 / 2.2 / 3.0，平均约 3.5 |

    - 等级分布没有往高处偏，现在这版 Lv.18 反而多一点。杀怪速度在噪声范围内一致。
    - T_regress 那组基线平均 8.8，是少数几次刷到大量 Lv.18 造成的。4 区 Lv.18 → 19 的断崖（2.5 下对 21.6 下）把方差放得很大；单局只有 1 分钟，假主角在这个循环里也不回血，常常提前陨落，这些都会放大波动。
11. **T_regress：`--qa-arena` 偶发误进匹配** → 同第 8 条。
12. **T_regress：大世界英雄档没有回归覆盖** → 同第 9 条（加了探针）。
13. **T_regress：4 区节奏** → 同第 10 条。
14. **T_regress：局域网双开（`--net=*`、`--lan-test`、`--level-test --xiu-lan`）没跑 → 没跑（deferred）**
    - 副本房间端口在自检档下本来就隔离（第 8 条），所以可以跑；只是这次我也没跑。在场双开 `--lan-test` 不受这次静默改动影响。
15. **T_regress：手机 / 网页覆盖少** → 这次补了手机档 meta_ui_test（gl_compatibility、--touch），网页包还是没测（deferred，留给部署那一步）。
16. **T_regress：`D:/GodotProjects/_wt_logs` 可以删** → 不是我建的，留给负责人决定。我自己的日志在 `D:/GodotProjects/_w5_logs`（约 1 MB），同样可以删。

## 跑了什么

| 命令 | 结果 |
|---|---|
| `--check-only`：lan_presence / arena_selftest / ex/map_def / ex/meta_kit | 4 个都是 0 错误 |
| `-s res://_tasks/decouple/w4/check_all.gd` | 165 个脚本，载不进 0 个 |
| `-- --level-test desert --no-lan`（headless） | **21/21 PASS**，不再打 `[ex_geo] 挪到` |
| `-s …/t_maps/maps_run.gd -- --qa-maps=desert --qa-probe=rock_probe` | 洞窟里的 4 个点没了，总数 13 → 7（剩下的是地面叠盒子的原始点） |
| `-s …/w5/lan_quiet_probe.gd -- --qa-w5lan [--lan-test=probe]` | 静默：发出 0 个包；带 --lan-test：照常发 |
| run_hidden `meta_ui_test.gd --meta-ui-test --touch --lite --web-fonts`（1600x740，gl_compatibility） | **结论：全部通过**，0 个 SCRIPT ERROR |
| run_hidden `-- --qa-arena --no-lan` | win，0 个 SCRIPT ERROR，没进匹配 |
| `-s …/w5/hero_mob_probe.gd --probe-realm=3`、`=0`（headless） | 见第 9 条 |
| 基线 / 现在轮流 11 对 `--raid-pace --pace-regions=4` + pace_lv_probe | 见第 10 条 |

## 需要别人改 / 留意
- **格斗专项**：炼气 / 筑基期英雄（LIGHT 空战）打地面小怪的输出，大约是老角色地面拳脚的三分之一（第 9 条）。复现：`hero_mob_probe.gd --probe-realm=0`。
- **数值会话**：
  - 双卫要不要从 22.5 拉到 18（第 1 条）；
  - 元婴进地下室 / 洞窟首领被秒，要不要收（第 2 条）。
- **字体 / 界面负责人**：物品格子里 16px 的毛笔体「寻」读着像「手」，可以考虑小字号的物品名不用毛笔体（第 6 条）。
- **extraction-pvp 分支**：map_def 的 4 个坐标同样要改，extract_manager 的 `_mob_floor` 同样只认地形（第 3 条）。
- 每轮惯例「启动游戏窗口给用户试玩、部署网页版」：没做，留给负责人。
