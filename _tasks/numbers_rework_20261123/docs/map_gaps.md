# 数值重构 · 完整性复查（map_gaps）

读的是隔离快照 `D:/GodotProjects/修仙游戏_iso_numbers`，行号都是快照里的。只读，没跑 Godot。
做法：先通读五份地图（map_combat / map_progression / map_display / map_tests / map_hammer），统计每个脚本被提到几次，再把**一次都没提到**的 46 个脚本和只提到一两次的脚本逐个 grep（伤害、气血、法宝被动、等级、境界、价格、联机包、存档字段）。下面只列五份地图**没写到**、或写到了但漏了关键后果的地方；已经写过的不重复。

---

## 0. 结论速览（按要紧程度）

1. **组队「带人」没有闸了**：联机分心得按**接收者自己**的 `kill_exp` 全额给（`raid_manager.gd:752-754`），旧体系里天道压制的伤害打折（0.55^差距）顺带压住了高境界队友在低区的清怪速度。去掉伤害压制、高境界一刀一片之后，低境界队友白拿全额心得，唯一的闸是 `insight_cap`。life_sim 只模拟单人，量不到。
2. **灵田是 life_sim 没有的第五个修为来源**（下线照长），粗算化神期一轮 8 小时能出约一半境界总量的修为；而且灵植的境界表（tier = realm，0..4）和修为丹改成按境界锁定之后的映射对不上，炼虚以后没有对应的灵植。
3. **丹房按名字数料、扣料，不看 kind**（`raid_profile.gd:525-529, 543-556`）：新的 8 个本境丹如果和破境丹（`筑基丹`…`大乘丹`，`raid_items.gd:38`）撞名，丹房会把修为丹当破境丹配料吞掉。
4. **法宝的「识 / 养」还有 5 个非战斗消费者**（神识扫描半径、被动探明半径、搜点读条、撤离读条、脱战回血），而且「识 / 养」没有封顶。如果按「每阶 ×1.65」把 `FX_AMT` 整体重配，这几处会一起变。
5. **两处 PvP 旁路**：被打飞砸地扣 8 点（`air_melee.gd:4317`）不过 `_pvp_clamp`；飞剑对波的胜负几乎不看境界（每高一境只多 6%，`air_melee.gd:714, 3966-3969`），和「每高一境 +15~25%」的 PvP 方案不一致。
6. **局内背包对所有丹都给「服用」按钮**（`raid_manager.gd:2193-2205`），境界锁定以后要按能不能服来出按钮。
7. **大厅的局域网广播包里又写死了一次 0~100 的气血条**（`lan_presence.gd:187`），想在名单或头顶显示战力的话，这个包和擂台的匹配包都得加字段，而且没有版本号。
8. **AI 修士的境界档位跟着主角走，等级跟着区域走**（`air_foe.gd:82, 963-966`）。「高境界回低区」以后会出现「看着是大乘、名牌写 Lv.2、血按 Lv.2 算」的修士。AI 道友的气血只在生成时算一次，升级以后不再更新。
9. `pace.html` 直接读 `life_result.json` 里的 `PILL_EXP` 等字段，life_sim 改了字段名页面就报错；`framework.html`、`growth.html` 和几个 `.js` 模拟器都是旧框架。
10. 五份地图之间有 **6 处结论互相矛盾**，需要先拍板（第 2 节）。

---

## 1. 新发现的漏项（逐条）

### A. 伤害 / 气血条的旁路

| # | 位置 | 现在 | 为什么要管 | 建议 |
|---|---|---|---|---|
| A1 | `air_melee.gd:4313-4317` `_crash_ground()`；触发在 `:2750-2753`（处于 BLOWN 状态、往下的推力 >12、碰到地面） | `m.hp = maxf(m.hp - 8.0, 0.0)`：固定扣 8 点气血条，归零当场陨落（`:4318-4324`） | 真人对打时，被对方往下砸飞（launch `down` 会经 `remote_player._send` 发过来）落地额外扣 8 点，**不过 `_pvp_clamp`，也不过 `arena_clamp`**。map_combat 5.3 列了对波 28 点、拳劲 14 点和甩出 16 点这几条旁路，漏了这一条 | PvP 的封顶要把它算进去，或者在 `from > 0` 的受击之后标记一下，砸地这一下走同一个封顶 |
| A2 | `air_melee.gd:3966-3969` `_clash_power()`；`:713-714` `flair() = clampi(realm_idx - 2, 0, 5)`；`air_foe.gd:406-413` `clash_output()`；`remote_player.gd:266-267` `clash_power()` 返回 0 | 对波的输出 = `CLASH_BASE × (1 + 0.06 × flair) × 觉醒 1.3 × 灵力余量 × (1 + 发力)`。境界只通过 `flair` 进来：结丹以下没有差别，往上每档 +6%，最多 +30%。AI 修士只看 `skill`，完全不看境界 | ① PvP 方案是每高一境 +15~25%，对波这条路上的境界优势只有 6% 左右；② 对波输的一方固定扣 28 点（已经报过）。也就是说，**对波的胜负和伤害都不跟数值体系走**。PvE 打 AI 修士时，赢下的那一轰 `_base() × 12`（`:4193`）照常走 `dmg_in`，会跟着变大 | 定下来对波要不要并进 PvP 那套：比如 `_clash_power` 乘上 `CS.pvp_adv(我, 对方)`，28 点改成按 PvP 公式算再走封顶 |
| A3 | `air_foe.gd:82` `var look_i := -1`；`:963-966` `tier_realm()`：`look_i < 0` 时返回 `player.realm_idx`；`raid_manager.gd:1785-1813` `spawn_rival` 不设 `look_i`，`f.lv = _level_in(ri, pos)`（`:1795`） | 大世界 AI 修士的「境界档位」（打击手感 `Realm.COMBAT`、对波出多少剑、外观）= **主角的境界**，等级 / 气血 / 伤害 = **区域等级** | ① 去掉伤害压制以后鼓励「回低区割草」：大乘在草原遇到的修士，外观和对波规模是大乘档，名牌是 Lv.2，血是 `Data.stat(260, 0.3, 2)`。② `shen_shi.gd:222` 用 `tier_realm() > my + 1` 隐藏高境界修士，对大世界修士永远不成立。③ 以后要是按 `tier_realm` 算战力、危险色或 PvP 境界差，都会算错 | 生成时按区域给 `look_i`（例如 `Data.REGIONS[ri]["realm"]` 加深度），或者明确规定「修士的境界 = realm_of(f.lv)」 |
| A4 | `raid_manager.gd:1933` 道友 `f.hp_max = Data.stat(380.0, 0.3, lv)` 只在 `_spawn_ally` 里算一次；`air_foe.gd:604-609` `set_level()` 只改 `prey_dmg` 和名牌 | 每帧 `f.set_level(lv, …)`（`raid_manager.gd:1962`）跟着主角的等级，**气血不跟** | 现在是线性增长，差得不多；换成几何曲线（每级 ×1.37~2）以后，一局里升两三级、渡一次劫，道友的血就落后好几倍，挨怪一下就倒（`ally_brain.gd:614-620` 挨打 `× HURT_K`） | `set_level` 里按比例重算 `hp_max` / `hp` |
| A5 | `boss_bullets.gd:103` `_dmg.append(float(opts.get("dmg", 10.0)))`，`:176` 分裂弹 `dmg × 0.6`，`:226-229` `on_hit.call(cp, dir, dmg)` → `boss_arena.gd:181` `hp = maxf(hp - dmg, 0.0)`（另一条 100 点的条，`boss_arena.gd:21-24`：`HP_MAX 100`、`REGEN 4`） | 剑冢首领的弹幕打的是剑冢自己的那条护体条，不是 `player.melee.hp` | 属于大厅链路：只要不动 `Realm.LIST.dmg` 就不用改。列在这里，是为了别在改「气血条」时误改；`boss_arena.gd:26` 的 `MIN_REALM 3`（低于结丹的按元婴算）也是大厅专用 | 不动 |

### B. 法宝「识 / 养」的非战斗消费者（法宝改成平加属性或按每阶 ×1.65 重配时）

map_combat 4.3 只写了「养 → `RM:2756`」「识 → 搜点（`RM:2743`）、战力」。完整清单如下：

| 消费者 | file:line | 式子 | 封顶 |
|---|---|---|---|
| 神识主动扫描半径 | `shen_shi.gd:111-116` `scan_r()` | `TIERS[realm]["r"] × (1 + 0.5 × min(识, 1.0))` | 识 ≤ 1.0 |
| 被动探明搜点的半径 | `raid_search.gd:131-137` `tick(p, seek)`，调用方是 `raid_manager.gd:2772` | `passive_r() × (1 + 识)` | **无** |
| 搜点读条速度 | `raid_manager.gd:2743` `search.step(dt, …, 1.0 + 识)` → `raid_search.gd:170` | `× (1 + 识)` | **无** |
| 撤离读条时间 | `raid_manager.gd:2519` | `EX_KINDS[kind]["t"] / (1 + 养 × 0.5)` | **无** |
| 脱战回血 | `raid_manager.gd:2756` | `CALM_REGEN × 养 × 1.5` | **无** |
| 战力 | `combat_stats.gd:187-188` | 养 `× (1 + 0.2 养)`，识 `× (1 + 0.05 识)` | — |

- `raid_items.gd:173-181` 的 `fx_total` 只封了守（0.6）和攻（0.8），**识 / 养不封顶**。`FX_AMT` 的识 / 养是 25 / 40 / 60 / 85 / 120（`raid_items.gd:23`），戴三件 120% 的识，搜点就是 4.6 倍速。
- 结论：法宝重做时，攻 / 守进新的战斗公式（或者 PvP 封顶），**识 / 养要单独保留百分比的含义**，不要跟着 ×1.65 走。
- 散修行囊（`raid_profile.gd:574-583`）送的是 `Items.gear(0, 0)` 和 `Items.gear(0, 1)`（凡品的攻和守各一件），法宝换数以后新手开局的强度也会跟着变。

### C. 联机 / 网络

| # | 位置 | 现在 | 为什么要管 |
|---|---|---|---|
| C1 | `raid_manager.gd:742-755` `net_mob_died`；`:752` `if share and pos.distance_to(player.global_position) < 100.0:` → `add_insight(mob_lv, xp_k, …)` | 别人名下的怪死了：只要「我补过刀，或者它的主人是我的队友」，并且在 100 米内，就按**我自己**的 `kill_exp`（`:361-362`，只按**我自己**的 `sup_gap` 打折）给心得 | **带人**：大乘队友在草原 / 黄枫谷一刀一只，kpm 远高于单人，炼气 / 筑基的队友躺着拿满心得，只受 `insight_cap` 限制（炼气的上限 = 1.84 × 整个境界的修为，筑基 0.38 ×，结丹 0.21 ×，见 map_progression 2.3）。旧体系里 `sup_dmg_k = 0.55^差距` 把高境界在低区的输出压到百分之几，等于顺带压住了带人。**去掉伤害压制，这条副作用就没了**。life_sim（`ENTRY_REALM`，单人）和所有探针都量不到这个 |
| C2 | `raid_mob.gd:731` `slain_by_rival = not bool(from.get("ally"))` | AI 道友打死的怪算主角这一队的（照常给心得和掉落） | 道友的 `prey_dmg` 跟着主角的等级走（`raid_manager.gd:1962`），去掉伤害压制以后，道友在低区也会割草；`ally_brain.gd:38 DMG_K 0.3` 是按「别让道友把升级速度翻倍」实测的，要在「高境界回低区」这种场景下也复测一次 |
| C3 | `net.gd:740-746` 掉落箱 / 掉落物整件同步，谁先拿归谁 | — | 和 C1 叠在一起：高境界在低区刷出来的低境界本境丹，被带的人能直接捡来吃。境界锁定反而让带人更划算 |
| C4 | `raid_manager.gd:544-545` 怪的批量包是 `[net_id, def_idx, region, lv, elite, pos, rot, hp/hp_max, state, lair, camp]`；木偶在 `:568-576` 只有 `def / region / lv / elite`，`hp_max = 100` | 怪的血量大小不过网，只过比例（已经报过）；**`hp_k`（游荡首领 0.6、各自检的倍数）也不过网** | 换成 `atk²/(atk + 3.5·def)` 以后，出手方算木偶的伤害要知道它的防御。**防御只能是 `(def_idx, lv, elite, boss)` 的纯函数**，不能依赖 `hp_k` 或主人本机上的状态，否则两台机器算出来的不一样 |
| C5 | `lan_presence.gd:150-152` 大厅 UDP 广播 `[…, realm_idx, Profile.cult()[0], …, player.melee.hp, room]`；`:187` 收到以后 `"hp": clampf(float(a[13]), 0.0, 100.0)`；`:185` 等级夹在 1..999；`:244` 名单写成 `"%s  %s Lv.%d%s"` | 又一处写死 0~100 的气血条（map_combat 4.2 只列了 `lan_presence.gd:152`） | 气血条保持 100 就没事。想在大厅名单或头顶显示战力的话，要往这个 `var_to_bytes` 数组的**末尾**加字段，读的时候用 `a.size()` 判断——没有版本号，新旧版本会混在同一个局域网里 |
| C6 | `arena_net.gd:112` 擂台匹配广播 `"%s|%d|%d|%d|%s|%d" % [A_TAG, side, token, port, name, my_lv]`，`:124` 解析 `lv`；`:159, 186` 进房以后 `players[]` 里才有 `realm` | 匹配阶段只知道等级 | PvP 的加成要是从「按等级差」（`CS.arena_adv`，`combat_stats.gd:163-164`）改成「按境界差」，`arena_duel.gd:448` 的 `_rival_lv` 能用 `realm_of(lv)` 反推；要显示对手的战力，就得改这个用竖线分隔的串 |
| C7 | 全项目搜不到任何「按境界差决定能不能打 / 打多重」的 PvP 规则（`remote_player.gd`、`net.gd`、`raid_manager.gd`、`spell_projectile.gd` 里没有境界比较，唯一和境界差有关的是 A2 的 `flair`） | — | PvP「每高一境 +15~25%」是**全新的接入点**，不是改现有的数；擂台已有的 `arena_adv` 是最接近的模板 |

### D. 丹药 / 灵田 / 丹房（经验丹改造的漏项）

| # | 位置 | 现在 | 为什么要管 |
|---|---|---|---|
| D1 | `farm_data.gd:19-38` `PLANTS`（灵参 6 分钟、灵莓 12 分钟 … 彼岸花 6 小时、冰魄灵果 8 小时；种子 4 / 6 / 16 / 64 / 80 / 240 / 300 / 1000 / 1200 灵石；一株收 1~2 个）；`:43` `MID_COST [40, 120, 320, 800, 1800]`；`:47` `FIELD_REALM [0, 1, 2, 3, 4, 4]`（化神期 6 块田 × 16 格 = 96 格）；`:116-123` `recipes()` 出 `Items.pill(t, 1)`（中品，药力 ×2）；生长按真实时间算，下线也长 | **life_sim 不模拟灵田和丹房**（map_progression 第 8 节只写了「不模拟：丹房炼丹（灵草全卖）」） | 粗算（按代码里的数，不算丹毒）：化神期 96 格，一半彼岸花、一半冰魄果，8 小时约 48 颗中品培婴丹 × 5736 ≈ **27.5 万修为，约占化神整个境界（49.4 万）的 56%**，成本约 3667 灵石一颗（种子 667 + 1200，加炼制费 1800）。炼气期 16 格灵参 + 灵莓，每颗中品黄龙丹 132 修为（约占炼气的 5%），成本约 50 灵石。这对 15.9 小时的节奏是一个**没有校准过的变量**；而且改成 Hammer 那样「本境丹只有本境界能服」以后，灵田出的丹**算哪个境界**没人定过 |
| D2 | 灵植的境界：`farm_data.gd` 里每株的 `"tier": t, "realm": t`（0..4 一一对应）；`farm_plots.gd:209-210, 906-907` 种植按 `p["realm"]`，`:167, 171` 开垦按 `FIELD_REALM` | 灵植的 tier = 境界 0..4 | 和 map_progression 11.2 建议的 `REALM_TIER = [0, 0, 1, 2, 3, 4, 4, 4]`（境界 → 图标品阶），以及 11.6 的 `TIER_REALM = [0, 2, 3, 4, 5]`（旧的 `pill(t)` 兼容）**是三套不同的映射**。炼虚 / 合体 / 大乘没有对应的灵植 → 境界锁定以后，灵田对后期要么完全没用，要么得补表 |
| D3 | `farm_data.gd:112` 文案 `"丹房辅药：配灵草炼中品%s（药力翻倍）"`；`:104, 111` 用 `Items.PILLS[t][0]` 拼丹名 | 「翻倍」是写死的，等于 `GRADE_MULT[1] = 2` | 品质倍数一改，文案就不对了；`PILLS` 扩到 8 行时这里也会越界（越界那一条 map_progression 已经报过） |
| D4 | `raid_profile.gd:525-529` `count(item_name)`、`:532-540` `can_craft`、`:543-556` `craft`：**按 `name` 数料、扣料，不看 `kind`** | — | 新的本境丹 / 霸主丹的名字必须和破境丹 `KEYS`（`raid_items.gd:38`：筑基丹 / 降尘丹 / 定灵丹 / 化神丹 / 炼虚丹 / 合体丹 / 大乘丹）、灵草 `HERBS`、灵材 `MATS`、灵果的名字都不一样，否则合破境丹时可能把修为丹扣掉。`raid_selftest.gd:68` 也是按 `r["out"]["name"] == "筑基丹"` 找破境丹方的，撞名以后会拿到错的那条。map_hammer 4.8 提过「筑基丹」撞名，没写出这个后果 |
| D5 | `raid_manager.gd:2193-2205` `bag_actions()`：`"pill": out.append("use")`；`raid_hud.gd:464, 479-481` 照这个列表出按钮 | 所有丹都有「服用」按钮；`use_item`（`raid_manager.gd:2224-2229`）只拦截「修为丹 + 瓶颈」 | 境界锁定以后，`bag_actions` 要按 `pill_use_err` 不给「服用」（或者给一个灰掉的按钮加说明），`use_item` 里也要再查一次（map_progression 只写了 `use_item`） |
| D6 | `raid_manager.gd:2084-2093` `_take()` → `_swap_out()`：背包满了按 `value`「以贵换贱」，提示 `"背包满了：丢下 %s（%d），换 %s（%d）"` | — | 境界锁定以后，会为了一颗**吃不了**但更贵的丹，自动丢掉一颗能吃的。是否把「本境界能服」也算进比较，需要定 |
| D7 | `main.gd:6595-6600`（`--raid-shot` 第 7 步）：默认化神（`:6107-6109`），从开出来的箱子里找第一颗 `kind == "pill"` 调 `rd.use_item(i)`（没给 act → `raid_manager.gd:2222` 当成服用） | 打印「服丹：Lv.x y% → …」 | 境界锁定以后，箱子里多半是别的境界的丹 → 被拒，打印的数不变。只是打印，不算断言失败，但回归时会让人以为服丹坏了 |

### E. 经济 / 存档里还有几处和数值挂钩的量

| # | 位置 | 内容 | 说明 |
|---|---|---|---|
| E1 | `raid_manager.gd:2478-2479` `paid_cost() = 150 × (realm_idx + 1)` | 「献灵石撤离」的价钱 | 不在 map_progression 第 7 节的价格表里；灵石整体放大的话要一起改；提示文字在 `:1296, 2496`（`%d`） |
| E2 | `raid_profile.gd:54` `stats {raids, out, dead, best}`；`:348-351` `best = max(best, 这局带出的物品 value 之和)`；`abode_ui.gd:367-369` `"最多带出 %d 灵石"` | 存档里的灵石单位 | 灵石或物品价值换了单位以后，老存档的 `best` 和新的不可比；VER 3 迁移时一起折算，或者干脆清零 |
| E3 | `Data.TIER_VALUE`（`raid_data.gd:268`）同时决定灵草 / 灵果的价值（`farm_data.gd:81` 是 `tier_value × 0.4`）和灵田的收益显示（`farm_plots.gd:1066`） | — | 动 `TIER_VALUE`（比如丹的价值改成按境界算的时候顺手改了它）会连带改灵田的经济 |
| E4 | `raid_profile.gd:302-307` `wealth()` | 灵石加全部物品的价值 | 全项目**没有调用方**（死代码）；`kit_ok`（`:565-571`）只看灵石和有没有法宝，不看它 |

### F. 报告页 / 旧模拟器（不影响游戏，但会误导、会报错）

- `_tasks/numbers_sim/pace.html:143-147` 直接读 `life_result.json` 的 `params.KILL_BASE / KILL_G / KILL_CAP_N / PILL_EXP / MED_RATE / BREAK_COST`（`pr.PILL_EXP.join(" / ")`）。`life_sim.gd:80-81` 写这些字段；`PILL_EXP` 改名或删掉以后，页面的 JS 会直接报错（`undefined.join`）。
- `framework.html:100-126`：按 5 阶 `PILL_EXP × GRADE_MULT` 画丹药表，`const PN = ["黄龙丹", …]` 5 个名字、`realmMax = [1, 2, 3, 4, 7]`、等级列写死 `r === 7 ? 99`，读的是 `sim2.js / fit.js` 那套旧框架。
- `growth.html`、`sim.js`、`sim2.js`、`run2.js`、`try.js`、`fit.js`：老框架（`growth.html:251` 还在讲 `xp_reward` 和 `ambient_level`），数值重构以后要么删掉，要么在页头标「已过时」。

### G. 死代码 / 只剩兼容的数（别误以为它们在起作用）

- `raid_data.gd:144-155` `coeff()` / `ambient_level()`（上限 99）/ `diff_tier()`，`:186-187` `scaled_value()`：老的「难度系数」，只剩 `raid_manager.coeff()` 兼容和自检打印（`main.gd:4698, 6543-6548`）；**怪的等级不是它定的**（是 `Prog.mob_level`）。
- `raid_data.gd:168-173` `xp_total(lv)`（逐级累加的循环）、`:182-183` `xp_reward`：没有调用方。
- `raid_data.gd:127` `DIFF_S`、`:139-141` `DIFF_NAMES / DIFF_COLORS`：只和上面那套一起用。

---

## 2. 五份地图之间互相矛盾 / 必须先拍板的地方

| 话题 | 一方 | 另一方 | 为什么必须先定 |
|---|---|---|---|
| 瓶颈处多出来的修为 | map_progression 11.5：**推荐方案 A，照 Hammer 结转**（`add_xp` 顶级分支全收，突破时带进下一境界） | map_hammer 0-8 / 4.8 第 3 条：**建议保留截断**（瓶颈不让服、溢出丢弃，理由是 life_sim 是按它校准的） | 本境丹只能在本境界服，再加上截断，瓶颈期攒下的本境丹突破以后全部作废；`hall_pills._pick` 的「大丹留给下个境界」（`hall_pills.gd:131-150`）和 life_sim 的 `_eat`（`life_sim.gd:310-322`）都依赖「丹能跨境界吃」。两种做法要改的文件差别很大（渡劫成功 / 失败的三处分支、`hub_hall` 的三处、life_sim 的两处） |
| 怪的曲线 | 用户方案：怪每境 ×8 | map_hammer 4.1：人和怪用同一条 G(L)（每境 ×5.187）；map_combat 0-13 / map_tests 3.1：人 ×5、怪 ×8 的话 `combat_table.gd:118-121` 全部不过（到大乘打几下要 ×27） | 这决定 `_spawn_mob`、`combat_table` 的护栏、`DEPTH_LV / REALM_MOB_LV` 要不要重配 |
| 境界 ↔ 丹的品阶 | map_progression 11.2：`REALM_TIER = [0, 0, 1, 2, 3, 4, 4, 4]` | map_progression 11.6：`TIER_REALM = [0, 2, 3, 4, 5]`（旧的 `pill(t)`）；`farm_data` 灵植：tier = realm（0..4） | 三套映射同时存在，丹房、灵田、坊市、迁移、图标各用一套，玩家会看到「同一个丹名在不同地方能不能吃不一样」 |
| 老存档里的丹 | map_progression 11.7：折成当前境界、同品质的新丹 | map_hammer 4.8：当「通用丹」，药力 = 当前这一级所需修为 × 百分比，任何境界都能吃（Hammer 的 `expPct` 型） | 决定 `_migrate_v3` 怎么写，以及 `pill_exp_now` 要不要保留一个「旧丹」分支 |
| 修为曲线的量级 | map_hammer 4.8：修为曲线不照抄（Hammer 每境 ×15.6 会打乱按怪等级给的心得） | map_progression 11.1：给了两种（整体 ×100，或 Hammer 形状加 `KILL_G ≈ 2`） | 定下来才能算 `PILL_BASE`、霸主丹的药力、`MED_RATE`，改自检里写死的 `add_exp(1e6 / 1e9)` |
| 大乘 25~99 级 | 五份都指出几何曲线会让 int64 溢出（`CS.power` 和 `hp_cap` 返回 int、`Vfx.damage_number` 里的 `int(round())`） | 没有一份给出定案 | `Prog.MAX_LV`、`top_lv(7)`、存档的 `cult()` 夹取、`combat_table` 的 40 / 99 级行、`arena_selftest` 的 `[99, 22]` 都等它 |

---

## 3. 我核过、确认**没有**漏点的地方（免得再查一遍）

- **陷阱 / 环境伤害**：没有。搜「陷阱 / 毒 / 瘴 / 岩浆 / poison / lava」都是空的；「禁制合拢」（`raid_manager.gd:2532-2555`）是时间到了困死在里面，不是伤害。
- **坠落**：主角只有 A1 那一处（空战被打飞砸地）；俯冲砸地 `player.gd:675-690` 没有伤害；怪被打飞落地 `raid_mob.gd:1009` 扣 12% 是按比例算的（已经报过）。
- **雷劫**：`tribulation.gd:252` 每道没挡住扣 14 点、保底 5 点（已经报过）；**成败只看失误次数** `_missed > _allow`（`:250-256`），不看气血，也不看战力。
- **`Realm.COMBAT`**（`realm.gd:105-138`）：只管打击表现（特效 / 击退 / 顿帧 / 对波出剑数），注释写明「不改伤害」。
- **觉醒槽**：按次数涨（`air_melee.gd:3308` 每下 +2.5，`:3561` 挨打 +8，`:4232` 聚气每秒 +7），不按伤害多少，数变大不影响。
- **按伤害绝对值放大的特效 / 音效 / 顿帧 / 镜头**：没有。全项目里拿 `dmg` 和常数比较的只有 `air_melee.gd:2527` 那一处保命判断。
- **场景 / 数据文件**：`scenes/main.tscn` 里没有覆盖数值属性；项目里没有 json / csv 数据表，所有的数都写在 `.gd` 里。
- **网络收包**：`net.gd` 只夹爆炸半径（`:364-369, 665-667`）和保护时长（`:631-634`），伤害不夹，数变大照样能传；RPC 里的 float 是 64 位。
- **心得光点**：`insight_fx.gd:79-104` 每次出几颗按种类定（1 / 3 / 5），不按心得多少，`KILL_G` 变大不会刷屏。
- **怪的行为**：`raid_mob.gd`、`raid_camps.gd` 里没有任何和主角境界 / 等级的比较；AI 修士什么时候翻脸（`_engage_ok`，`raid_manager.gd:1765-1766`）只看时间和人数。
- **区域门槛**：`level_select.gd` 没有境界限制，哪个区都能进。几何曲线下，低境界进高区几乎一碰就死——这是设计上要决定的事，不是代码里的漏点。
- **其他「0 次提到」的脚本**（`hub_farm`、`hub_arena`、`hub_portal`、`level_portal`、`space_gate`、`test_hall`、`yuanying_cine`、`realm_broadcast`、`raid_pickup`、`sword_manager`、`clash_fx`、`awaken_fx`、`combat`、`sfx`、`block_world`、`meadow_*`、`voxel_*`、`camera_rig` 等）：搜过伤害 / 气血 / 价格 / 等级，没有和数值体系相关的接触点（`sword_manager.gd:51-425` 只读 `Realm.LIST` 的剑数 / 范围 / 连斩 / 出剑间隔，不读 `dmg`）。
