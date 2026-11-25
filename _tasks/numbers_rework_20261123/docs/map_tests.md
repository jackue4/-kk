# 数值重构影响图 · 自检 / 探针 / 模拟器（map_tests）

范围：`D:/GodotProjects/修仙游戏_iso_numbers` 快照里，所有会**断言或打印数值**、数值体系一改就会失败 / 要重新定基线的自检、探针和模拟器；再列出能拿来校准新曲线的现成工具和现在的基线数。
本文只读调查，没有运行 Godot。行号都是快照里的行号。主仓库（`D:/GodotProjects/修仙游戏`）里才有的东西单独标出「主仓库」。

---

## 0. 先看这几条（风险最高）

1. **两个自检脚本是被 main.gd `preload` 的：它们一编译失败，main.gd 就加载不了，整个游戏都起不来，网页包也一样。**
   - `scripts/main.gd:6112` `await preload("res://scripts/raid_selftest.gd").run(self)`
   - `scripts/main.gd:6260` `await preload("res://scripts/raid_pace_test.gd").run(self)`
   - 这两个文件按名字引用了 `CS.atk / CS.to_bar / CS.SKILL_TARGET / CS.skill_g / CS.volley_k / CS.q_k / CS.BLOCK_CHIP / CS.mp_shown / Prog.pill_exp / Prog.LV_PER_REALM / Prog.KEY_CRAFT_COST / Prog.FRAG_N / Prog.break_cost / Prog.mob_level / Prog.MEADOW_DEPTH_R / Prog.LAIR_R / Items.is_xp_pill / Items.pill / Items.frag / Items.key`，以及 `rd.sup_gap / rd.insight_cap() / rd.kill_exp()`。
     **改名或删掉其中任何一个，要么同时改这两个脚本，要么把 main.gd 里这两处改成 `load()`**（其他自检都已经是 `load()`，见 main.gd:2205/2209/2592/2597/2602/6241/6246/6251，hub_hall.gd:1979/1983/2444）。
   - 项目把 GDScript 警告当错误处理，类型推断失败也会编译不过。
2. **`player.melee.hp` 是 0 ~ 100 的气血条，这个约定被几十处自检写死。** 按 `grep` 粗数：main.gd 59 处、raid_pace_test 15、arena_selftest 12、pvp_rules_selftest 9、ally_selftest 7、melee_clip 4、fight_cam 3、hub_hall 3，还有其他文件。
   比如 `player.melee.hp = 100.0`、`if h < 40.0`、`if hp < 60.0: p.melee.hp = 60.0`、`player.melee.hp < 35.0`、`= 3.0 / 4.0 / 10.0 / 28.0 / 90.0`。
   联机同步（net.gd:474/489 `push_state(... hp ...)`）和木偶（pvp_outline_selftest.gd:72 `"hp": 100.0`）也按条走。
   **建议：大数（万 / 亿）只在显示层和 `CS.to_bar` 的折算里出现，HP_MAX 仍是 100**（combat_stats.gd:9 的注释就是这么定的）。否则这几十处全要重写。
3. **校准用的「单位」默认伤害和攻击力成正比。** `raid_pace_test.gd:425 _units()` 用 `掉的血 ÷ CS.atk(lv)` 反推单位，`combat_table.gd:98-99` 用 `怪血 / CS.atk(lv)` 算几下打死。
   换成 `攻² / (攻 + 3.5 × 防)` 以后，这个比值会跟着怪的防御走，不再等于招式倍率。**两处都要改成除以「这一个单位打这只怪实际掉多少」**（例如新加一个 `CS.unit_vs(atk, def)`）。
   能保住「单位 = 招式倍率」这层意思的话，`SKILL_K / volley_k / q_k` 这些按单位实测折出来的倍率就不用重测。
4. **有几处把公式又抄了一份，不会跟着新曲线变。**
   - `combat_table.gd:29-37 _mob()` 照抄了 `raid_manager._spawn_mob`（raid_manager.gd:1381-1384），但漏了 `hp_k`。
   - AI 道友 / 修士的出手 `prey_dmg = Data.stat(Data.PLAYER_DMG, 0.2, lv) * 0.6`（raid_manager.gd:1799/1934/1962）是旧的 12 × (1 + 0.2(lv−1))；
     `ally_brain.gd:330` 用 `sim_damage(dmg * DMG_K)` 直接扣怪血（raid_mob.gd:722-732 → `_take_raw`，不过 `player_dmg`）。
     怪血按每境界 ×8 涨以后，AI 道友会打不动怪，`--raid-ally` 的「前四段共击杀」会塌。
   - `life_sim.gd:284 _ins()` 照抄了 `Prog.insight`；`life_sim.gd:367-373 _pill_value()` 照抄了 `raid_items.pill()` 的价值，靠「品阶 × 品质」反推。
5. **天道压制取消伤害压制这件事，现有的探针一项都量不到。**
   - `raid_pace_test.gd:1185` 一律把主角设成 `ENTRY_REALM[ri]`，也就是该区的入门境界，所以 `sup_gap` 永远是 0。
   - life_sim 也只按 `ENTRY_REALM` 选图（life_sim.gd:148-153）。
   - 要验「高境界回低区割草」，得给探针新加一个境界覆盖参数（例如 `--pace-realm=7 --pace-regions=0`），再在 combat_table 里加一节「高境界打低区怪：几下一只（应 ≤ 1）」。

---

## 1. 测试里流动的几种数（单位速查）

| 数 | 现在的口径 | 定义处 | 哪些自检直接读 / 写 |
|---|---|---|---|
| 招式单位 | 招式倍率 = 原始伤害 ÷ base(境界)；base = Realm.LIST dmg 8 / 12 / 18 / 26 / 38 / 52 / 75 / 110 | combat_stats.gd:29-30，realm.gd:24-80 | pace-combat 的 `_units`、arena_selftest 的 `unit := CS.base(...)`、lan_selftest:156 |
| 大厅原始伤害 | 单位 × base(境界)（试剑台、斗法台、剑冢、擂台） | air_melee.gd:520，air_caster.gd:466/557…，player_melee.gd:853 | spark-tiers、spark-duel、boss-test、fight_* 自检的木桩血量 |
| 大世界伤害（扣怪血） | 单位 × atk(lv) × (1 + 攻法宝，≤ 0.8) × 天道压制 0.55^差 | combat_stats.gd:47-48，raid_manager.gd:350-352 | raid-pace（hits_per_kill）、pace-combat、raid-shot 的清怪 |
| 主角气血条 | 0 ~ 100；怪的伤害按 `to_bar = raw × 100 / hp(lv) × (1 − 守)` 折 | combat_stats.gd:42-43，raid_manager.gd:356-357 | pace-combat 的 mob_bar / block_bar，到处的 `hp = 100` |
| 显示气血 | hp(lv) = 110 × (1 + 0.3(lv−1)) | combat_stats.gd:37-38 | combat_table 表一、plate_test（主仓库） |
| 灵力 | 单位池 90 ~ 130，显示 60 ~ 300（`mp_shown`） | combat_stats.gd:52-68 | pace-combat 一（回满约 6.25 秒）、combat_table:70 |
| 心得 | 8.4 × 1.19^(怪级−1) × 系数；本局上限 = 常打的怪 × 480 只；天道压制时 × 0.25 | progression.gd:127-140，raid_manager.gd:361-367 | pace-insight、raid-pace、raid-econ:295、raid-trib:6378、life_sim |
| 修为 | 每级要的修为 = 2000 × 1.4^…，炼气 ×0.3、筑基 ×0.75；各境界合计 2615 / 1.79 万 / 6.57 万 / 18.0 万 / 49.4 万 / 136 万 / 372 万 / 1021 万 | progression.gd:24-50 | hub-shot、raid-econ、raid-trib、life_sim |
| 修为丹 | 药力 = PILL_EXP[66, 168, 432, 1116, 2868] × 品质[1, 2, 4, 8]；丹毒 1 / (1 + 0.05 × 丹毒)；打坐时服 ×1.3 | progression.gd:146-181/299-310，raid_items.gd:81-86 | raid-econ 2b、raid-pace 的统计、life_sim、pill_table |
| 打坐 | MED_RATE[0.43 … 12.52] 每秒；离线按一半，最多 8 小时 | progression.gd:186-193 | hub-shot 打坐那一项、life_sim |
| 战力 | `CS.power` = (攻击力 × 10 × 攻法宝 + 气血 ÷ 守 × 养) × 1.1^境界 × 识 | combat_stats.gd:185-188，player_plate.gd:57-58 | combat_table 表一最后一列；主仓库 ui_kit 的 plate_test / raid_hud_test |
| 灵石 | 突破价 0 / 500 / 2500 / 1.2 万 / 5 万 / 16 万 / 33 万 / 72 万 | progression.gd:199 | raid-econ、hub-shot、raid-trib、farm_selftest、life_sim |

---

## 2. 能拿来校准的现成工具（命令 + 现在的基线）

Godot：`D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64.exe`；`run_hidden.py` 用的是同目录下的 `_console.exe`。项目路径换成快照时把 `--path` / 第一个参数改成 `D:/GodotProjects/修仙游戏_iso_numbers`。
要渲染的自检走 `python _tasks/trailer/run_hidden.py <项目目录> <日志前缀> --resolution 1280x720 -- <参数>`：输出在 `<前缀>_out.txt` / `_err.txt`，20 分钟超时，进程按 PID 杀。
手机档再加 `--resolution 1701x900 --rendering-method gl_compatibility … --touch`。跑之前先查有没有别的 Godot 进程，免得拖慢帧率；隐藏窗口会收到用户的真实按键，结果里出现脚本没让做的动作时先怀疑这个。

| 工具 | 命令 | 输出 / 判定 | 现在的基线 |
|---|---|---|---|
| **规则表 combat_table** | `godot --headless --path . -s res://_tasks/numbers_sim/combat_table.gd -- --md=_tasks/numbers_sim/combat_table.md` | markdown 表，末行 `[combat-table] PASS / FAIL …`，**退出码 1 = 不合格** | `_tasks/numbers_sim/combat_table.md`（全部通过；数字抄在第 6 节） |
| **一辈子模拟 life_sim** | `godot --headless --path . -s res://_tasks/numbers_sim/life_sim.gd -- [--runs=40] [--prof=casual,normal,hardcore] [--real=0.7] [--pace=res://_tasks/numbers_sim/pace.json] [--json=res://_tasks/numbers_sim/life_result.json] [--o=ins:1,kb:8.4,kg:1.19,capn:480,pill:1,pillg:1,drop:0.2,med:1,medg:1,brk:1]` | `[life]` 各境界到达小时 / 局 / 天、来源占比、卡在哪；`--json` 存给 pace.html 用 | `life_result.json`（**runs=40**，默认是 60，要对照得带 `--runs=40`）：普通 0.3 / 0.9 / 2.0 / 3.4 / 5.9 / 9.6 / **15.9 小时**（第 62 局、第 16 天），来源 心得 36% / 丹 44% / 打坐 1% / 离线 19%；休闲 16.8，肝 14.8 |
| 丹药分布 pill_table | `godot --headless --path . -s res://_tasks/numbers_sim/pill_table.gd` | `[pill]` 各区各深度：每件掉落是修为丹的比例、平均药力、品阶分布 | 没存基线，改之前先跑一遍留底 |
| **节奏探针 --raid-pace** | `run_hidden … -- --raid-shot --raid-pace [--pace-min=5] [--pace-speed=6] [--pace-depth=0.35] [--pace-hit=1.5] [--pace-regions=0,1,2,3,4] [--pace-face] [--pace-home=200] [--camps \| --spawn-old] [--pace-cap=N] [--touch]` | 每分钟 `[pace]`，每区一行 `[pace-json] {...}`。**要手工把这几行拼成 JSON 数组**（去掉前缀、外面套 `[ ]`）存成 pace*.json 给 life_sim | 快照的 `pace.json`（老导演，每分钟杀 19.2 / 17.4 / 17.2 / 19.8 / 13.8，几下一只 2.9 / 4.0 / 4.7 / 3.3 / 6.0）；主仓库 `_tasks/spawn_density_20261121/pace_camp4.json`（**现在的固定刷怪点**，每分钟杀 15.9 / 17.9 / 13.8 / 20.3 / 14.1，几下一只 2.7 / 3.9 / 5.6 / 3.7 / 6.8 → 普通 15.7 小时）；`pace_mobile.json`（手机档） |
| **战斗实测 --pace-combat** | `run_hidden … -- --raid-shot --raid-pace --pace-combat [--pace-realms=0,1,2,4,7] [--pace-shots] [--touch]`（每个境界约 40 秒，QA 批跑 264 秒） | `[combat]` 和每个境界一行 `[combat-json]`：mp_refill / ground_ups / chain_ups / skills / volley_ups / q_ups / mob_bar / mob_bar_want / block_bar | 主仓库 `_tasks/qa_20261121/logs/pace_combat_out.txt`。例：结丹 atk 28.8、chain 3.58、skills [1.67, 3.0, 5.19]、volley 3.75、q 2.27、mob_bar 9.91 |
| 心得光点 --pace-insight | `run_hidden … -- --raid-shot --raid-pace --pace-insight [--touch]`（约 50 秒） | `[insight] 小结：PASS / FAIL` | 主仓库 `spawn_density_20261121/logs/reg_insight_*_out.txt` |
| 搜打撤经济 --raid-econ | `run_hidden … -- --raid-shot --raid-econ`（约 82 秒） | `[econ]` 一串「应为 / 应少 / 应涨」，没有 PASS / FAIL，要人看 | 主仓库 `qa_20261121/logs/econ_out.txt`、`spawn_density_20261121/logs/reg_econ_out.txt` |
| 主城 --hub-shot | `run_hidden … -- --hub-shot [--touch]`（约 56 秒） | `[hub]` 打坐 / 瓶颈 / 渡劫的「应为」 | 主仓库 qa_20261121 的 hub_out.txt |
| 擂台 / PvP | 单机 `-- --hub-shot --arena-duel`；双开 `--arena-net=a` + `--arena-net=b`；规则 `… --arena-net=a\|b --pvp-rules=mash\|defend\|clash [--pvp-realm=5] [--pvp-secs=22] [--pvp-legacy]`（主仓库 `python -I _tasks/pvp_rules/run_pair.py <标签> …`，**PROJ 写死成主仓库**） | `[arena]`、`[pvp] RESULT` | — |
| AI 道友 | `run_hidden … -- --raid-shot --raid-ally [--ally-old]`（约 129 秒）；双开 `--net=ally_host` + `--net=ally_mate`，再 `python -I _tasks/ally_net/compare.py`（主仓库） | 「前四段共击杀 N 只」 | 记忆里的基线：老逻辑 95 秒 7 只；新大脑按 DMG_K 折到差不多（快照里 DMG_K = 0.3） |
| 雷劫 | `-- --raid-shot --raid-trib`（约 31 秒） | 「布阵灵石应少 X」、渡劫后破境丹「应为 0」 | — |
| 各境界打击表现 | `-- --duel-shot --spark --spark-tiers [--tiers=2,7] [--touch]`（约 104 秒） | `[tier]` 各境界冲拳 / 崩拳伤害、击退、顿帧 | 主仓库 QA 日志 |
| 剑冢首领 | `-- --boss-test`（headless 可跑，约 71 秒） | `[boss-test]` 每秒伤害、满血多少秒打完 | — |
| 报告页 | `python _tasks/numbers_sim/serve.py 8770` → `pace.html`（读 life_result.json / pace_before.json / pace.json） | 局域网看结果 | **别用 8765 / 8766**（网页预览在用） |
| 整套回归模板 | 主仓库 `_tasks/qa_20261121/logs/_batch_summary.txt`：每一项的完整参数和耗时 | — | — |

---

## 3. 逐个自检：编码了什么期望、新体系下会怎样

标注：**自动** = 期望值是从代码常数现算的，改了公式会自己跟着变；**重定** = 要重新跑、存一份新基线；**改写** = 脚本本身要改；**不受影响** = 只要保住第 0 节的几个约定。

### 3.1 `_tasks/numbers_sim/combat_table.gd`（headless，退出码判定）

| 行 | 检查（不合格就让退出码 = 1） | 新体系下 |
|---|---|---|
| 14 | `MOB_CYCLE := 2.65` 小怪出招周期 | 不受影响 |
| 29-37 | `_mob()`：`Data.stat(hp0, Data.MOB_HP_G, lv) * ELITE_HP`、`Data.stat(at0, 0.2, lv) * ELITE_DMG * MOB_DMG` | **改写**：改成调游戏里同一个造怪函数（比如把 `_spawn_mob` 里的数值部分提成 `Data.mob_stats(idx, lv, elite)`），不然新曲线进不了表；现在已经漏了 `hp_k` |
| 59, 70 | `refill = mp_max / (AirCaster.MP_REGEN × mp_regen_k)`，`absf(refill - 6.25) < 0.01` | 灵力不动就是自动；要改灵力就重定 |
| 71-78 | 连发每秒（单位）逐境界不降、≤ `VOLLEY_DPS × 1.7`；飞剑阵单体每秒不降、≤ 3.6 | 单位口径保住就不受影响 |
| 79-81 | 地面起手在炼气 / 筑基的倍率要一样 | 不受影响 |
| 98-99 | `hit := CS.atk(lv)`；`htk := 怪血 / hit` | **改写**：除数改成新公式下一个单位对这只怪的伤害（要带上怪的防御） |
| 100-101 | `bar := CS.to_bar(怪攻, lv)`；`htd := 100 / bar` | 条保持 100 就是自动；改成新的受击公式就要改写 |
| 102, 107 | 连发几秒 = 怪血 ÷ (攻 × volley_k × volley) | 同 98 行 |
| 103-106 | 巢穴首领 = `Prog.mob_level(ri, 0.9) + 2`；普攻 ×1.5、震地 ×2.0 | 首领倍率不动就自动 |
| 118 | **每种怪 1.5 ~ 9 下（巨汉 12 下）**：`_check(hj >= 1.5 and hj <= (12.0 if brute else 9.0), …)` | **这是「主角成长跟得上怪」（第 2 条决定）最直接的护栏**：玩家 ×5、怪 ×8 的话，必须靠境界内每级的成长把差距补回来，表才能过 |
| 119 | 区域两种怪平均 2.5 ~ 9 下 | 同上 |
| 120 | 常见怪一下掉 4% ~ 14% 气血条 | 同上（受击那半边） |
| 121 | 巢穴首领一下 ≤ 36%、震地 ≤ 48% | 同上 |
| 89 | `regions := [0, 0, 1, 2, 3, 4, 4, 4]`（境界 → 常去的区域），`Prog.REALM_MOB_LV` | 不动就不受影响 |
| 124-149 | PvP 表：`CS.raid_hit(base(a), a, a×3+2)` → `to_bar(…, d×3+2)` → `min(…, PVP_HIT_CAP)`；`ttk = (100 − PVP_BURST) / PVP_SUSTAIN ≥ 2.5` | **改写**：第 3 条决定换成单独的 PvP 数值以后，表要调新函数，再加两条检查：同境界对角线差不多一样；高一个境界 ×1.15 ~ 1.25；法宝加成封顶。ttk 那条在封顶常数不变时自动通过（现在 2.8 秒） |
| 139-141 | 「大乘 99 级打炼气 1 级、一下 6 倍的剑诀」 | 要是把大乘的上限从 99 收成 24（等级 1 ~ 24），这里要改成 24 |
| 53-54, 69 | 每个境界取中间那级 `r * 3 + 2`，另列 `[7, 40]`；最后一列 `CS.power(r, lv, {})` | 战力重做以后这一列全部重定；建议加检查：逐境界、逐级单调递增；法宝只占小头 |
| 157-165 | 剑冢首领混着打的时长，各境界最多差 1.6 倍（`12000 × CS.boss_k`，混着打按每秒 3.8 单位 × base 算） | 大厅的 base 不动就不受影响 |

**要新加的检查**（对应几条决定）：
- 高境界进低区：高 1 ~ 5 个境界打草原怪几下一只（应 ≤ 1，割草），心得 × SUPPRESS_GAIN。
- 法宝：每升一阶 ×1.65，总加成占比有上限（死了会丢，所以只是锦上添花）。
- 战力：单调递增；同境界里法宝的影响有上限。

### 3.2 `_tasks/numbers_sim/life_sim.gd`（headless）

| 行 | 期望 / 假设 | 新体系下 |
|---|---|---|
| 12-15 | preload `progression.gd / raid_items.gd / raid_data.gd / raid_manager.gd` | 常数改名就编译不过（不连累游戏，`-s` 单独跑） |
| 16 | `PILL_PREF := 3.0`：挑背包时修为丹按卖价的 3 倍算 | 丹改成按境界锁定以后要重想（锁在别的境界的丹在这个人眼里不值钱） |
| 18, 148-153 | `ENTRY_REALM := [0, 2, 3, 4, 5]`：永远去自己入门的那个区，**不模拟回低区割草** | 想量「割草」对节奏的影响，要加一种玩家画像 |
| 24 | `TRIB_OK := 0.85` 渡劫成功率 | 不受影响 |
| 26 | `PACE_DEFAULT` 每分钟 4 只（量不到时的兜底） | 不受影响 |
| 29-33 | 三种玩家画像（每天几局、陨落率、深度、kill_k） | 不受影响 |
| 45 | 默认读 `res://_tasks/numbers_sim/pace.json`（老导演那份） | **重定**：数值改了以后几下一只会变，要重跑 `--raid-pace` 生成新的 pace.json；现在正式游玩用的是固定刷怪点，应该对照 `--camps --pace-face --pace-home=200` 量的（主仓库 pace_camp4.json → 15.7 小时） |
| 80-81 | `json_out["params"]` 直接读 `Prog.KILL_BASE / KILL_G / KILL_CAP_N / PILL_EXP / MED_RATE / BREAK_COST`、`RM.KILL_DROP / MOB_CAP / MOB_CAP_MOBILE` | 改名或删掉就编译失败（特别是 `PILL_EXP`） |
| 113-114, 119 | 老探针没有 avg_k 时，按旧公式 `16.5 × 1.14^(等级−1)` 反推 | 新的 pace.json 都带 avg_k，这条可以删 |
| 196-202 | 心得 = 杀怪数 × avg_k × `_ins(mob_lv, 1)`；kpm × kill_k × 0.7 | 自动（`_ins` 和 `Prog.insight` 要保持一致） |
| 215 | 巢穴首领心得 `_ins(mob_lv + 2, 14.0)` | 要和 raid_manager 里 `xp_k = 14.0` 对得上 |
| 233-237 | 本局上限 `_ins(Prog.REALM_MOB_LV[realm], 1) × capn` | 自动 |
| 262, 275-276 | 修为丹只记一个浮点药力：`S["pills"].append(it["exp"] × pill × pillg^tier)` | **改写**：按境界锁定的精魄要记「是哪个境界的」「霸主精魄的最低境界」；吃的时候按规则过滤 |
| 310-322 | `_eat`：按药力从大到小一直吃到瓶颈，丹毒 +1，打坐时 ×MED_PILL | **改写**：只吃当前境界能用的；锁在低境界的丹要卖掉或作废 |
| 344-363 | 突破：灵石不够先卖修为丹；成功 `lv = max(lv + 1, to × 3 + 1)`、xp 清零；失败 `xp = xp_need × 0.5` | 自动（要和游戏里渡劫失败的规矩一致） |
| 367-373 | `_pill_value`：按 `Prog.pill_exp(t, g)` 和 `GRADE_MULT` 反推卖价（`tier_value × 0.4 × 品质`） | **改写**：丹的结构变了，这里会对不上（对不上就退到 `e0 × 0.3`，悄悄算错） |
| 386-389 | 离线 `min(8 小时, 24 − 在线时长) × 0.5` | 自动 |
| 输出 | 「大乘：实际在玩 X 小时」 | **目标：普通玩家约 15.9 小时**（life_result.json，runs = 40；换成固定刷怪点的 pace 是 15.7） |

`--o` 的语义：`kb / kg / capn / drop` 是**直接替换**，其余（`ins / pill / pillg / med / medg / brk`）是**乘数**；试好了要写回 progression.gd，再不带 `--o` 跑一遍确认。

### 3.3 `_tasks/numbers_sim/pill_table.gd`

- 19-23：`Items.roll(ri, 1, rng, 0.0, depth)` → `Items.is_xp_pill(it)` → `it["exp"]`、`it["tier"]`，按 5 个品阶统计。
- 丹改成 8 个境界的精魄 + 霸主精魄以后，**改写**统计口径：改成按「哪个境界能吃」分列，加上「一颗占本境界总量的百分比」（Hammer 霸主精魄是 5% ~ 7.5%）。

### 3.4 `scripts/raid_pace_test.gd`（**main.gd 用 preload 载入，见第 0 节第 1 条**）

**--raid-pace（`_one`，1175-1339）**
- 1185-1190：主角 = `ENTRY_REALM[ri]`，等级 `realm * Prog.LV_PER_REALM + 2`，所以 `sup_gap` 永远是 0（1200-1201 打印「天道压制 %d 档」）。
- 1219 / 1220：`var v := 10.0 if realm < 2 else 18.0`（飞行速度）；**`var dmg := float(player.realm["dmg"]) * hit_k`**——出手按「单位 × base」，靠 `player_dmg` 的 `d / base` 换回单位。
  **新的 player_dmg 必须继续接受「原始伤害 = 单位 × base(境界)」这个入口**，不然探针（还有所有 `{"dmg": …}` 的自检）都得改。
- 1278-1280：每 0.4 秒一下 `best.receive_hit(player, {"dmg": dmg, …})`，也就是每秒 3.75 单位。
- 1290-1291：心得每帧收走，不封顶（量原始产出）。
- 1302-1304：修为丹统计 `Prog.pill_exp(int(it.get("tier", 0)), int(it.get("grade", 0)))` → 丹改了这里要改写。
- 1322-1332 `[pace-json]` 字段：region / realm / lv / depth / mob_lv / minutes / **kpm** / mob / elite / boss / **avg_k** / **hits_per_kill** / alive / near / idle / insight_pm / insight_cap / pill_pm / pill_exp_pm / coin_pm / items_pm / key / frag / heal / gear。
  life_sim 只用 region、mob、elite、boss、minutes、kpm、mob_lv、avg_k。快照 pace.json 里的 `insight_cap 5484` 是 KILL_BASE = 9.6 时量的（9.6 × 1.19 × 480），已经过时，但没人读。
- **新体系下：重定**。几下一只（hits_per_kill）要尽量回到 2.7 ~ 6.8 这一档，kpm 才不变，life_sim 的节奏才保得住。
- **要新加**：`--pace-realm=N`（覆盖 ENTRY_REALM），用来量「高境界回低区」的 kpm 和心得。

**--pace-combat（`_combat_one`，433-655）**

| 行 | 期望 | 新体系下 |
|---|---|---|
| 418-419、606-607 | 木桩和打主角的那只怪 `hp_max = hp = 1.0e7`（「血极厚」） | **改写**：怪血涨到几百万到几亿（Hammer 化神那档 640 万、大乘那档 32.8 亿）以后，3 秒连段 / 4 秒飞剑阵可能打穿 1e7，`_units` 会量少。改成 `1.0e15` 或按新攻击力算 |
| 425-431、448 | `_units = 掉血 / CS.atk(lv)` | **改写**（第 0 节第 3 条） |
| 441 | `Profile.set_cult(r * 3 + 2, 0.0)` | 一境三级不变就不受影响 |
| 459-466 | 存档图 `raid_cb_%d`（玩家牌：气血按 CS.hp、灵力按 mp_shown） | 大数显示的回归图，重拍 |
| 467-468 | 「从 0 回满 %.2f 秒（应约 6.25 秒）」 | 灵力不动就自动 |
| 490 | 文字「表里起手 / 二段 / 三段 = 1.125 / 1.375 / 2.125」（写死的） | 地面连招表不动就不受影响 |
| 541-542 | 剑诀全中，目标 `CS.SKILL_TARGET[i] * CS.skill_g(r)` | 自动；`[combat-json].skills` 是 SKILL_K 的校准来源 |
| 570-571 | 连发每秒对照 `CS.volley_k(r) * volley` | 自动 |
| 590 | 飞剑阵每秒对照 `CS.q_k(r) / atk_cd` | 自动 |
| 609 | `want := CS.to_bar(float(mob.atk), lv)`（没带「守」，所以前面先 `rd.gear.clear()`） | 受击公式改了就跟着改 |
| 621-623 | `if h < 40.0: player.melee.hp = 100.0` | 依赖 100 的条 |
| 652 | 格挡「应约 want × CS.BLOCK_CHIP」 | 自动 |

**--pace-insight（160-380，有 PASS / FAIL）**
- 期望：五只小怪光点 5 颗、精英 3 颗、满了 0 颗、追平 ≤ 1.6 秒、超时 0 颗、飘字行数在 1 ~ 4 之间。
- 塞进去的数很小：273 行 `rd.insight + 5.0`，`fx.launch(far, 5.0, 0)`；440 行附近 `+ 1.0`。
- 1163-1164 `_kill()`：`m.hp = 0.5` 再打一下 `{"dmg": 8.0}`。新公式下这一下的实际伤害必须 ≥ 0.5（`攻² / (攻 + 3.5 防)` 恒为正，只要量级不是零点几就行）。
- **基本不受影响**（只看个数和时间）；trace 用 `Prog.short_num` 打印。

**--pace-spawn（659-1120）**
- 681 `Profile.set_cult(14, 0.0)`；1094-1095 同一个 `hp = 0.5` + 8 伤害的杀法。
- 量的是刷怪的可见性，不受数值影响。

**--pace-perf**：只量帧耗时，不受影响。

### 3.5 `scripts/raid_selftest.gd`（`--raid-econ`；**main.gd 用 preload 载入**）

| 行 | 期望 | 新体系下 |
|---|---|---|
| 43 | `Profile.data()["lingshi"] = 20000`（够买下面那一串） | 灵石不改价就不受影响 |
| 46 | 要买 `"下品黄龙丹"`（坊市卖 `pill(0)`，名字 = GRADE_NAMES + PILLS 名，raid_items.gd:85、262） | **丹改名 / 去掉品质就会失败**：`_buy` 记一条错，61 行 `Profile.to_ring(_find(…, "下品黄龙丹"))` 会拿到 −1。改成按 `Items.pill(0)["name"]` 取 |
| 71-72 | 炼筑基丹：灵石「应少 `Prog.KEY_CRAFT_COST[1]`」 | 自动 |
| 99-118 | 大厅一键服丹：仓库塞 5 颗 `Items.pill(0)`，吃完打印 Lv 和 xp 的变化（「到瓶颈会退回」） | 精魄锁境界的话，`pill(0)` 要是炼气能吃的那种；否则改写 |
| 218-219 | `Profile.set_cult(realm × 3 + 3, 0.0)` + **`rd.add_exp(1.0e6)`**，期望到瓶颈（「缺丹 = 1 / 起劫 = −1」） | 炼气那一级要的修为 ≤ 1e6 才成立（现在是 1176）。**改成 `Prog.xp_need(lv) × 2`** 之类现算的数 |
| 221-228 | 布阵「应少 `Prog.break_cost(1)`」 | 自动 |
| 295 | `rd.insight = min(insight + 300.0, cap)`；319 行「存档修为…（应涨）」 | 心得变大以后 300 微不足道，但「应涨」照样成立；建议改成 `cap × 0.1` |

### 3.6 `scripts/main.gd` 里的各段自检

| 段 | 行 | 期望 / 写死的数 | 新体系下 |
|---|---|---|---|
| `_run_raid_demo` 开头 | 6107-6109 | `player.set_realm(4, false)`（默认化神） | — |
| `--raid-trib` | 6345-6380 | 6351 灵石 = `break_cost(to) + 1000`；**6355 `rd.add_exp(1.0e9)`**，期望小级连升、卡在瓶颈；6359「应少 break_cost」；6377-6379「破境丹应为 0」、打印 `rd.kill_exp(1, 1.0)` 和 `sup_gap` | 化神这一境界的总修为要 < 1e9（现在 49 万；Hammer 的化神是 1.94 亿，照搬量级时要留意）。**改成按 `Prog.realm_total` 现算**；kill_exp 的打印只是信息 |
| `--raid-shot` 全流程 | 6460-6606 | `player.melee.hp = 100.0`（多处）；6496 清怪 `{"dmg": 99999.0}`；6545 / 6557 首领 `9999999.0`；6579 修士 `air_hit 9999999.0`；6093 `9999999.0`；`int(hp)` 的打印 | 99999 原始伤害 ÷ base(化神 38) ≈ 2631 单位 × 攻击力，新曲线下一般还是秒杀；不放心就改成 `m.hp_max × 10` 再走受击入口。都是打印，没有断言 |
| `_raid_immortal` | 5326-5329 | `if player.melee.hp < 30.0: = 100.0` | 依赖 100 的条 |
| `--raid-ally` | 6249-6252 → ally_selftest | 见 3.9 | — |
| `--raid-q` | 5790-5808 | 「没翻脸的修士掉血 %.0f（应为 0）」 | 不受影响 |
| `--raid-z` | 5493-5516 | 冷却 / 灵力 | 灵力不动就不受影响 |
| `--raid-ai` | 5520-5590 | 数量 / 距离 / 主动对波次数（应为 0） | 不受影响 |
| `--raid-match` | 6115-6130 | `f.air_hit(player, {"dmg": 50.0})` 返回 −1 的个数 | 不受影响 |
| 大厅对手 | 705-709 | 陪练木人 1500、魔修 900、青禾 1600（大厅原始伤害口径） | **只要大厅的 base(境界) 不动就不受影响**；要是大厅也换成大数，这些和下面这些全要放大 |
| `--spark` 对打 | 4074, 4115-4118, 2901 | `e.hp_max = 1600`，`player.melee.hp < 35 → 100`，`e.hp < 25% → 回满`，`foe.hp_max = 900` | 同上 |
| `--spark-tiers` | 3433 | `foe.hp_max = 9.0e6`；打印各境界冲拳 / 崩拳伤害 `int(hp1 - foe.hp)` | 大厅不动就不受影响；`[tier]` 里的伤害列要重定 |
| `--spark-perf` | 3658 | `foe.hp_max = 999999.0` | 同上 |
| `--spark-dead` | 4002-4036 | `player.melee.hp = 4.0 / 3.0`，`{"dmg": 10.0}` 一下打死 | 依赖 100 的条 |
| 其他 spark | 2444-2445、2561、2675、2858、3020、3110-3111、3309 | 木桩 `hp_max = 99999.0`；`air_hit {"dmg": 5.0 / 6.0 / 50.0}` | 大厅不动就不受影响 |
| `--air-shot`（老演示） | 1716-1717 | 「预期约 −`realm.dmg × (0.6 × 3 + 1.5 + 2.6 + 0.5 × 6)`」写死的公式 | 老招式表，不动就不受影响 |
| `--boss-test` | 1863-1935 | 1855 / 1901 `arena.hp = max(arena.hp, 40)`；1903-1905 每秒伤害、满血多少秒打完（只打印）；1923 / 1932 按 `max_hp` 的比例 | `boss_k` 用 base，大厅不动就不受影响 |
| `--net=host/mate/foe` | 2202-2345 | 2272 `air_hit {"dmg": 38.0}` 返回值；2316 `hp = 100` | 不受影响 |

### 3.7 `scripts/hub_hall.gd`（`--hub-shot`）

| 行 | 期望 | 新体系下 |
|---|---|---|
| 2044-2045 | `player.set_realm(0)`，`Profile.set_cult(1, 0.0)` | — |
| 2061-2063 | 打坐 6.6 秒：「这次 +%.1f，应为 `Prog.med_rate(0) × 6.6` 上下：每息 +%.2f」 | **自动**。2061 行的注释「（2026-11-20 晚起 0.36），坐 6.6 秒约 +2.4」已经过时（现在是 0.43 / 约 2.8），顺手改掉 |
| 2065-2066 | `Profile.set_cult(3, Prog.xp_need(3))`；`gain(5)`「应为 0」 | 自动 |
| 2071-2076 | 按钮文字；灵石补到 `Prog.break_cost(1)` | 自动 |
| 2097 | 「灵石应少 break_cost(1)」「存档境界应为 1」「**修为 Lv.%d（应为 Lv.4）**」 | 写死 4 = 1 × 3 + 1；一境三级不变就成立 |
| 1533-1535 | `_num1`：小于 100 打 `%.1f`，大了走 `short_num` | 不受影响 |
| 1567, 1655 | 「每息修为 +%.1f」直接 `%.1f` 打 `Prog.med_rate` | 打坐速度变大以后会显示「12345.6」这种，**要改成 `_num1` / `short_num`**（显示问题，定妆图里看得见） |
| 1661 | 牌子上「Lv.%d %s / %s」（已经走 `_num1` / `short_num`） | 不受影响 |

### 3.8 擂台 / PvP

**`scripts/arena_selftest.gd`**（`-- --hub-shot --arena-duel`，用 load 载入）

| 行 | 期望 | 新体系下 |
|---|---|---|
| 75-90 `_table()` | 打印 Lv 对 `[1,1] [4,1] [7,4] [13,1] [22,1] [24,22] [99,22] [22,99]`：擂台 `CS.arena_hit` 对比「大世界那套」`CS.to_bar(CS.atk(a), b)` | **改写**：「大世界那套」改成新的 PvP 函数；大乘上限要是收到 24，99 的两组也改掉 |
| 92-93 | `_realm(lv) = floor((lv − 1) / 3.0)` 写死每境界 3 级 | 一境三级不变就成立 |
| 134-136 | 陪练气血对照 `CS.ARENA_AI_HP × CS.base(realm)` | 自动 |
| 172、215、457 | `receive_hit {"dmg": foe.hp_max × 0.2 / 0.3 / 1.0}` | 自动 |
| 216, 245, 369 | `p.melee.hp = 90 / 10` | 依赖 100 的条 |
| 224, 249, 263, 267, 356 | `Profile.data()["lv"] = ri * 3 + 2 / 1 / 22` | 一境三级 |
| 287-327 | 「应掉 `2 × ARENA_UNIT × arena_adv(22, 1)`」（自动）；**305 行文字「应只掉四十点上下」是写死的**（= ARENA_BURST 26 + 每秒 13） | 第 3 条决定要是把擂台也换成每境界 +15% ~ 25%，`arena_adv` 从按等级（±1.2% 封顶 ±12%）改成按境界：自动的那几处会跟着变，305 行的文字和 combat_stats.gd:148 的「最多 1.27 倍」注释要改 |

**`scripts/pvp_rules_selftest.gd`**（双开，经 arena_selftest.gd:33-34 用 load 载入）
- 75 `Profile.data()["lv"] = 3 * realm + 1`；161-162 `if hp < 60.0: p.melee.hp = 60.0`（按 100 的条）。
- 232 `[pvp] RESULT … 掉血 %.0f（%d 次）…`：掉血是条上的点数。
- 两边同一个境界，只量规则（硬直 / 自由时间），**不受数值影响**；要是想量跨境界的差距，用 `--pvp-realm` 两边各给不同的境界（现在两边共用一个，要改脚本）。

**`scripts/lan_selftest.gd`** 156：`receive_hit {"dmg": CS.base(realm) × 6.0}` 打擂台木偶。不受影响。

**大世界 PvP**（raid_manager.gd:760-803，`_pvp_clamp` 用 `CS.PVP_HIT_CAP / BURST / SUSTAIN`）**没有专门的自检**，只有 combat_table 那张表，还有 `--net=host/mate/foe` 里的对波流程（不看伤害）。建议新加一段双开：境界差 0 / 1 / 3 时一招掉多少、多少秒打死。

### 3.9 其他自检

| 脚本 | 写死的数 / 期望 | 新体系下 |
|---|---|---|
| `ally_selftest.gd`（`--raid-shot --raid-ally`） | 86 / 131 / 159「前四段共击杀 %d 只」（基线约 7 只 / 95 秒，靠 `ally_brain.gd:38 DMG_K := 0.3` 对齐）；115 / 141 / 158 `player.melee.hp = 100 / 28`；164 `a0.hp = hp_max × 0.15`；178 `on_hit(hp_max × 4)` | **重定**：AI 道友的伤害 `prey_dmg`（raid_manager.gd:1799/1934/1962）是旧的 12 × (1 + 0.2(lv−1)) × 0.6，直接扣怪血（`sim_damage → _take_raw`）。怪血涨了它就打不动，要把 prey_dmg 改成走新的攻击力，再按击杀数把 DMG_K 调回来 |
| `camp_net_selftest.gd`（`--net=camp_host` + `--net=camp_mate`，PASS / FAIL） | 103 `{"dmg": 1.0e7, "raw": true}` 打死；113 压到 `hp_max × 0.5`；174-175「接手后血量应约 0.5」（按比例） | 怪的同步是按比例（raid_manager.gd:545 `m.hp / m.hp_max`），不受影响；1e7 原始伤害在新曲线下照样秒杀 |
| `fight_feat_selftest.gd` | 65 / 156 / 208 / 266 木桩 `hp_max = 99999.0`；打印掉血 | 大厅不动就不受影响 |
| `fight_cam_selftest.gd` | 276 / 306 `hp_max = 99999.0`；290 / 320 / 391 `hp = 100`；397 `receive_attack {"dmg": 6.0}` | 同上 |
| `melee_clip_selftest.gd` | 30-34 在试剑台里摆 raid_mob：`lv = 1`、`hp_max = 9.0e6`、`atk = 0.5`、`xp_k = 0`；163 打印掉血；179-185 `hp = 100` | 没接 `dmg_in`，吃的是大厅原始伤害，不受影响 |
| `pvp_outline_selftest.gd` | 72 / 216 / 224 木偶 `"hp": 100.0 / 0.0` | 依赖 100 的条 |
| `move_selftest.gd`、`solid_selftest.gd`、`shenshi_selftest.gd` | 只有 `hp = 100` 保命和位移 / 范围的「应」 | 不受影响 |
| `farm_selftest.gd` | 72 `lingshi = 60000`，「扣灵石应 16 × price」 | 灵石不动就不受影响 |
| `hitch_probe.gd`、`--pace-perf`、`--spark-perf`、`--raid-fight` | 只量帧耗时 | 不受影响 |

### 3.10 只在主仓库里的（快照里没有，回归时要一起看）

- `_tasks/ui_kit/plate_test.gd`
  - 25 行的玩家牌样例：`[境界, 气血比, 灵力, 灵力上限, 等级, 修为比]` = `[0, 1.0, 90, 90, 1, 0]` / `[4, 0.62, 33.6, 112, 13, 0.55]` / `[7, 0.22, 104, 130, 24, 0.9]`。
  - 31-32 / 39 行 `Plate.hp_cap(lv)`、`Plate.power(...)`。
  - 大数（万 / 亿）放不放得下，就靠这张图看。
- `_tasks/ui_kit/raid_hud_test.gd`
  - 141 行 `_plate.set_values(3, 1.0, 407, 106.0, 106.0, 10, 0.4, 989)`：407 是气血上限，989 是战力，**写死的小数**，要换成新的量级再拍。
- `_tasks/ui_kit/mock_raid.gd`（给 raid_hud_test 用的假管理器）
  - 22-23 `insight = insight_shown = 137.0`，42-43 `insight_cap() = 72000.0`，25 / 27 `here_lv 4 / lv 10`，51 `187.0`，117 `200`。
  - 心得 / 等级量级变了要跟着改。
- `_tasks/qa_20261121/qa_combat.gd`、`qa_nethit.gd`：按 100 的条量掉血（`set("hp", 100.0 / 3.0 / 1.0)`）。不受影响。

---

## 4. 横跨各个自检的隐藏假设（实现时逐条对照）

1. **气血条 = 100**：见第 0 节第 2 条。热修气血、回城、补满都按条写；回春丹 `heal 60`（raid_items.gd:90）、修为丹 `heal 25 ~ 35`（raid_items.gd:35）也是条上的点数。
2. **每个境界 3 级**：写死的有
   - `r * 3 + 2`：raid_pace_test:441、combat_table:53/71/75/90/134、arena_selftest:224/356
   - `/ 3.0`：arena_selftest:93
   - `3 * realm + 1`：pvp_rules:75
   - `realm_idx * 3 + 3`：raid_selftest:218
   - 「应为 Lv.4」：hub_hall:2097
   - `LV_PER_REALM := 3`：raid_data.gd:130，progression.gd:24
   这次的方案是 8 个境界 × 3 级，不变，这些都成立。
3. **大乘等级到 99**：`Prog.MAX_LV := 99`（progression.gd:26）、`top_lv`（:54-55）、存档 VER 2 的说明（raid_profile.gd:10）、combat_table:54 `[7, 40]` 和 139-141 的 `99`、arena_selftest:81 的 `[99, 22]` / `[22, 99]`、combat_stats.gd:148 的注释。
   新方案说的是「lv 1..24」。**要先定下来大乘后面还涨不涨**，不涨的话这些一起改。
4. **木桩「打不死」的血量是写死的**：`1.0e7`（pace-combat，在大世界里，**新曲线下最可能被打穿**）、`9.0e6`（spark-tiers、melee-clip）、`999999`（spark-perf）、`99999`（各处大厅木桩）、`1500 / 900 / 1600`（大厅陪练）。
5. **「一下打死」的伤害是写死的**：`99999`、`9999999`、`1.0e7`（camp_net）、`1.0e9`（main.gd:4903/4930 的 `_take_raw`，直接扣血，不过公式）；还有 `hp = 0.5` 加一下 `{"dmg": 8.0}`（raid_pace_test:1094/1163）。
   这些都要求新的 `player_dmg` 对「原始伤害」**单调、没有上限**。要是新公式加了每一下的封顶，或者「× 单位」放在开方之类的位置，就得复查。
6. **灌修为的量是写死的**：`add_exp(1.0e6)`（raid_selftest:219）、`add_exp(1.0e9)`（main.gd:6355）。改成 `Prog.realm_total(realm) × 2` 之类现算的数。
7. **灌心得的量是写死的**：`+300`（raid_selftest:295）、`+5` / `+1`（pace-insight）。只会显得微不足道，不会失败。
8. **灵石是写死的**：20000（econ:43）、60000（farm:72）、`break_cost + 1000`（main:6351）。突破价要是一起放大，econ 的 20000 可能不够买齐，要复查。
9. **丹的名字和结构**：`"下品黄龙丹"`（econ:46/61），`Items.pill(tier, grade)` 的 `"exp" / "tier" / "grade"` 字段（life_sim、pill_table、raid_pace_test:1304、hall_pills.gd:168），`Prog.GRADE_MULT / GRADE_NAMES / PILL_EXP / pill_exp`。
   新的精魄规则（按境界锁定 + 霸主精魄最低境界）一上，这些调用点全要跟着改；**`Items.is_xp_pill` 是按名字判断的**（≠ 回春丹，raid_items.gd:94-95），新丹名不影响它。
10. **天道压制**：数值在 progression.gd:251-256；
    - 伤害压制入口 raid_manager.gd:343-352（`sup_dmg_k` / `player_dmg`）
    - 心得压制入口 :361-362
    - 进区提示 :336-339「出手威力 ×%d%%，心得 ×%d%%」
    - HUD raid_hud.gd:659-660「天道压制 ×%d%%」**用的是 `sup_dmg_k`**
    取消伤害压制以后，提示和 HUD 都要改成显示心得 / 掉落的打折，不然会一直显示「×100%」。现在没有任何自检覆盖这一块（见第 0 节第 5 条）。
11. **存档单位**：`xiuxian_profile.json` 的 `lv` / `xp`（float）/ `tox` / `lingshi`。
    曲线换了要像上次 VER 1 → 2 那样升 VER（raid_profile.gd:19、125-130：xp 清零、lv 夹回境界）。
    **自检永远用 `xiuxian_profile_selftest.json`、每次清空**（raid_profile.gd:17、41-49、69），所以迁移这一步没有任何自检覆盖。要单独做一次「放一份老存档 → `--keep-profile` 开机 → 看 lv / xp / 丹」的检查。
    老存档里的修为丹（PILLS 5 阶 × 品质）怎么换成新的精魄也要定。
12. **数字格式**：
    - `Prog.short_num` 只有「万」「亿」两档（progression.gd:346-353），1e12 以上会显示成「10000.0亿」。Hammer 大乘的修为在万亿以上，照搬量级要加「万亿 / 兆」。
    - 飘血 `Vfx.damage_number` 是 `str(int(round(value)))`（vfx.gd:366），打出来是一长串整数。
    - 预热的字形里写死了「心得 +0123456789.万亿」（insight_fx.gd:354、raid_hud.gd:609）。加新单位字要同步，不然网页上第一次出现会卡一下或显示方块字。
13. **校准倍率是按「单位」实测的**：`SKILL_K`（combat_stats.gd:102-106）、`VOLLEY_DPS 6.0`、`Q_DPS 1.8`、地面 `GROUND_REF 8`。保住单位口径就不用重测；否则要用 pace-combat 重量一遍、重折。
14. **pace.json 是手工拼的**：探针只往标准输出打 `[pace-json]` 行，没有现成的转换脚本。快照里的 pace.json 是老导演量的；正式游玩用的是固定刷怪点（`camps.on`，raid_manager.gd:264；自检模式默认老导演，要加 `--camps`）。
15. **life_result.json 是 runs = 40 跑的**，life_sim 默认 runs = 60。对照前后的时候用同一个 runs。
16. **AI 修士 / 道友的数值也是另一套抄的公式**：`RIVAL_HP 260 × (1 + 0.3(lv−1))`、`dmg_mul = RIVAL_DMG × stat(1, 0.2, f.lv) / stat(1, 0.3, lv)`（raid_manager.gd:1798-1825）、`Data.stat(380.0, 0.3, lv)`（:1933）。新曲线要一起换，不然 `--raid-ally` / `--raid-ai` / 心得（修士 k = 5）的节奏都会偏。

---

## 5. 建议的重新定基线顺序

1. **改之前先留底**（同一台机器、同一个快照）：
   - combat_table → 存 md；life_sim `--runs=40`（默认 pace.json，再加一份 `--pace=` 固定刷怪点的）；pill_table。
   - `--raid-pace --camps --pace-face --pace-home=200`（拼成 pace_before_numbers.json）、`--pace-combat`、`--raid-ally`、`--raid-econ`、`--hub-shot`、`--hub-shot --arena-duel`、`--spark-tiers`。
2. 先把第 0 节的几处改掉：main.gd 的两处 preload 改成 load、`_units` 和 combat_table 的除数、`_mob` 改成调同一个函数、各处木桩血量和灌修为量、pace 探针加 `--pace-realm`。
3. 改数值：combat_stats / progression / raid_data / raid_items。**每改一步都跑 combat_table**（几秒出结果、退出码判定）；第 3.1 节那几条范围就是「主角成长跟得上怪」的护栏，再加上新写的 PvP、法宝、战力、割草检查。
4. 跑 `--pace-combat` 确认单位口径没变（skills / volley_ups / q_ups 和老基线差不多），mob_bar 等于 mob_bar_want。
5. 跑 `--raid-pace --camps …` 重新生成 pace.json；看几下一只回到 2.7 ~ 6.8，kpm 没明显变。
6. life_sim：普通玩家到大乘约 15.9 小时（换成固定刷怪点的 pace 是 15.7），各境界来源占比别失衡；精魄的规则写进 life_sim 以后，用 `--o=pill:…` 试数，再写回去。
7. 回归：`--raid-econ`、`--raid-trib`、`--hub-shot`、`--hub-shot --arena-duel`（+ 双开）、`--raid-ally`（击杀数对齐）、`--pace-insight`（PASS）、`--net=camp_host / camp_mate`（PASS）、`--raid-shot`（两档渲染），再加主仓库 ui_kit 的 plate_test / raid_hud_test（大数显示放不放得下）。
8. 存档迁移单独测：拿一份 VER 2 存档，按正常游玩的方式开机，看读进来的 lv / xp / 丹对不对。

---

## 6. 现在的基线数（对照用）

- combat_table（`combat_table.md`）
  - 常见怪普攻几下：炼气 4.2、筑基 3.9、结丹 9.5、元婴 5.6、化神 6.1、炼虚 6.5、合体 6.5、大乘 6.2。
  - 怪一下掉条：8.1% / 6.3% / 9.9% / 7.9% / 8.3% / 9.7% / 9.5% / 9.0%。
  - 站着挨几下死：13 / 16 / 11 / 13 / 12 / 11 / 11 / 12。
  - 战力（无法宝）：287 / 504 / 761 / 1065 / 1422 / 1839 / 2326 / 2892；大乘 40 级 4780。
  - PvP 同境界一招掉条：10.1 → 7.8；最快 2.8 秒打死。
  - 剑冢首领混着打：54 ~ 66 秒。
- pace（几下一只，探针每 0.4 秒打 1.5 单位）
  - 老导演：2.9 / 4.0 / 4.7 / 3.3 / 6.0。
  - 固定刷怪点：2.7 / 3.9 / 5.6 / 3.7 / 6.8。
  - 每分钟杀：老导演 19.2 / 17.4 / 17.2 / 19.8 / 13.8；固定刷怪点 15.9 / 17.9 / 13.8 / 20.3 / 14.1。
- pace-combat（主仓库 qa 日志）
  - 灵力回满约 6.22 ~ 6.24 秒。
  - 炼气地面每下 1.54 单位、每秒 3.08；炼气 mob_bar 8.06、block_bar 1.21。
  - 结丹：chain 3.58、volley 3.75、q 2.27、skills [1.67, 3.0, 5.19]。
  - 化神：chain 3.65、volley 4.2、q 2.38、skills [2.41, 3.64, 3.62]。
  - 大乘：chain 4.91、volley 4.63、q 2.79、skills [3.22, 3.46, 8.37]。
- life_sim（life_result.json，runs = 40）
  - 普通玩家到各境界：筑基 0.3、结丹 0.9、元婴 2.0、化神 3.4、炼虚 5.9、合体 9.6、**大乘 15.9 小时**（第 62 局 / 第 16 天）。
  - 休闲 16.8 小时（第 40 天），肝帝 14.8 小时（第 4 天）。
  - 来源（普通）：心得 36% / 丹 44% / 打坐 1% / 离线 19%。
- 修为曲线：各境界合计 2615 / 17946 / 65658 / 180164 / 494371 / 1356554 / 3722383 / 10214221（相邻境界约 ×2.75）。
- 打坐每秒：0.43 / 0.71 / 1.14 / 1.84 / 2.98 / 4.8 / 7.75 / 12.52；修为丹 66 / 168 / 432 / 1116 / 2868 × 品质 1 / 2 / 4 / 8。
