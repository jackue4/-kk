# 战斗伤害链路地图（PvE / PvP）—— 数值重构用

快照：`D:/GodotProjects/修仙游戏_iso_numbers`（只读调研，行号都是这个快照里的）。下文 `CS` = `scripts/combat_stats.gd`，`RM` = `scripts/raid_manager.gd`，`Data` = `scripts/raid_data.gd`，`Prog` = `scripts/progression.gd`。

---

## 0. 先说结论（实现者最需要知道的 10 条）

1. **现在有三层数值单位**，所有伤害都在这三层之间换算：
   - **招式原始伤害（raw）** = 招式倍率 × `Realm.LIST[境界].dmg`（8/12/18/26/38/52/75/110，`CS.base()`），空中拳脚再 ×觉醒 1.3。**所有出招代码只产生这一层**（air_melee / air_caster / flying_sword / gate_array / player_melee）。
   - **大世界实伤（怪的血量单位）** = raw ÷ base(境界) × `CS.atk(lv)` ×(1+法宝攻，封顶 0.8) × 天道压制。只在一个地方换算：`RM.player_dmg()`（`RM:350-352`）→ `CS.raid_hit()`（`CS:47-48`）。
   - **主角气血条（0~100 点）** = 怪的原始攻击 ×100 ÷ `CS.hp(lv)` ×(1−守，封顶 0.6)。只在 `RM.to_player()`（`RM:356-357`）→ `CS.to_bar()`（`CS:42-43`）。
   **建议：不动 `Realm.LIST` 的 `dmg`、不动 0~100 的气血条**，只改 `CS.atk / CS.hp / CS.raid_hit / CS.to_bar` 和怪的生成公式（`RM._spawn_mob`），大数只活在「大世界实伤 / 怪血」和显示层。改 `Realm.LIST.dmg` 会连带打乱大厅、剑冢首领、斗法台、擂台 AI、飞剑阵 / 连发折算（见第 9 节）。
2. **主角的气血条是 0~100 的百分比，几十处写死 100**（联机同步、AI、自检、音效、回血、丹药、渡劫），保持不动最省事；玩家牌显示的「气血实数」= 条 × `CS.hp(lv)`/100。
3. **等级不止 24**：`Prog.MAX_LV = 99`（`progression.gd:26`，大乘后一路涨到 99）。照搬 Hammer「每境界 ×5」做成每级几何增长的话，lv 99 ≈ 5^(98/3) ≈ 6e22，**超过 int64（9.2e18）**——`Vfx.damage_number` 的 `int(round())`、`CS.power()` 返回 int、`player_plate.hp_cap()` 返回 int 全会溢出。大乘 24 级以后必须换成线性或很缓的增长。怪的等级最高约 26（坠魔谷深处 24 + 巢穴首领 +2）。
4. **天道压制的伤害折扣只有一个入口**：`RM.sup_dmg_k()`（`RM:343-344`，`Prog.SUPPRESS_DMG = 0.55`/档），被 `player_dmg` 用（PvP 本来就不压）；另有两处文字（`RM:338` 提示、`raid_hud.gd:659-660`）。心得折扣在 `RM.kill_exp()`（`RM:361-362`）。注释说「掉落品质也按 SUPPRESS_GAIN 打折」，**代码里没有**（`raid_items.gd` / `RM._loot` 都没读 sup_gap）。
5. **PvP 伤害是两台机器各算一半**：打人的一方在 `RM.net_deal_hit` 按**自己的** atk(lv)/法宝攻换算并显示伤害数字，RPC `_hit(dmg,…)` 只带一个数；挨打的一方在 `RM.net_take_hit` 按**自己的** hp(lv)/法宝守折成条、再 `_pvp_clamp` 封顶。PvP 专用公式要在这两处接（擂台在 `arena_duel.gd:680 / 695`）。**有旁路不走这两处**：飞剑对波输了的一方本地直接扣 28 点条（`air_melee.gd:4222`），不经 to_player、不经 PvP 封顶（擂台也不经 arena_clamp）。
6. **网络协议没有版本号**（net.gd / arena_net.gd 里找不到 proto/version），改 `_hit` 里 dmg 的含义（例如从「实伤」改成「条上点数」）后，新旧版本混在一个局域网房间里会互相错算。
7. **AI 修士 / AI 道友各有一套手写的数**（`RM:1798-1799, 1825, 1933-1934, 1962`，`ally_brain.gd:35,38,333`），没走 CS，怪改成几何增长后它们会立刻失衡（打怪打不动、被怪秒）。
8. **显示层全是小数字写法**：伤害飘字 `str(int(round(value)))`（`vfx.gd:366`）、连击伤害 `"伤害 %d"`（`hud.gd:495`，而且显示的是 raw 不是实伤）、玩家牌 `"%d/%d"` 和 `str(pw)`（`player_plate.gd:257,261`）、服丹 `"气血 +%d"`（`RM:2309`，单位是条上的点不是实数）。`Prog.short_num()`（`progression.gd:347`）已有 万/亿 写法可复用。
9. **自检里有会被大数打穿的「打不死」血量**：`raid_pace_test.gd:418-419, 606-607` 把木桩怪设成 `1.0e7`；怪按 ×8/境界涨以后大乘一刀可能就上千万。`_tasks/numbers_sim/combat_table.gd` 有一批区间断言（几下打死 1.5~9、怪一下掉条 4~14% 等，第 12 节），是重构的验收线。
10. **进度节奏依赖实测杀怪速度**：`life_sim.gd` 读 `pace.json` 里各区「每分钟杀几只」（`life_sim.gd:26,110-119,196`），那是旧数值下在大世界里量的。重构后同区同级「几下打死一只」只要变了，就得重跑 `raid_pace_test.gd --raid-pace` 更新 pace.json，否则 15.9 小时到大乘的结论不成立。

---

## 1. `scripts/combat_stats.gd` 全表（188 行，全读过）

| 行 | 名字 | 现在的式子 / 值 | 谁在用（file:line） | 重构时怎么办 |
|---|---|---|---|---|
| 19 | `MAX_REALM` | 7 | 本文件各处 clamp | 不动 |
| 22-25 | `ATK_BASE 12` `ATK_G 0.2` `HP_BASE 110` `HP_G 0.3` | 线性每级 +20% / +30% | `atk()` `hp()` | **换成新曲线的核心**。注意 lv 最高 99（见 0.3） |
| 26 | `GEAR_ATK_CAP` | 0.8 | `raid_hit` `power`；另在 `raid_items.gd:180` 硬写了一份 0.8 | 两处要一起改；PvP 封顶另设 |
| 29-30 | `base(realm)` | `Realm.LIST[r].dmg` | `raid_hit`、`ground_k`、`boss_k`、`arena_hit`、`arena_ai_hp`；外部 `lan_selftest.gd:156`、`arena_selftest.gd:84-136,234,287`、`combat_table.gd:79-160` | 保持「招式单位」的分母，不建议改 |
| 33-34 | `atk(lv)` | `12×(1+0.2(lv−1))` | `raid_hit`、`power`；`raid_pace_test.gd:448`（定义「单位 = 伤害 ÷ 攻击力」）、`arena_selftest.gd:86-87`、`combat_table.gd:98` | 新的主角攻击曲线 |
| 37-38 | `hp(lv)` | `110×(1+0.3(lv−1))` | `to_bar`、`power`、`player_plate.gd:62`（显示上限）、`raid_pace_test.gd:463`、`combat_table.gd:67` | 新的主角气血曲线 |
| 42-43 | `to_bar(raw, lv, guard)` | `raw×100/hp(lv)×(1−clamp(guard,0,0.6))` | `RM:357`（所有怪 / 别人的怪 / **PvP 收到的伤害**都走这里）、`raid_pace_test.gd:609`、`arena_selftest.gd:86-87`、`combat_table.gd:100-145` | 换成 Hammer 式时要引入主角防御：`atk²/(atk+3.5·def)` 先算实伤，再 ×100/hp(lv) 折条 |
| 47-48 | `raid_hit(d, realm, lv, gear_atk)` | `d/base(realm)×atk(lv)×(1+min(gear,0.8))` | 只有 `RM:352`（player_dmg）和 `combat_table.gd:134-145` | 主角打怪的唯一换算；Hammer 公式要知道**目标的防御**，见第 4.2 节怎么把目标传进来 |
| 52-68 | `MP_UNITS` `MP_REGEN_PER100` `mp_max` `mp_regen_k` `mp_shown` | 灵力 | `player.gd:210`、`air_caster.gd:214`、`hud.gd:475`、`player_plate.gd:259` | 不在本区域，伤害重构不必动 |
| 73-74 | `skill_g(realm)` | `1.1^(r−2)` | `volley_k`、`boss_k`、`combat_table`、`raid_pace_test.gd:542` | 招式单位里自带的「每境界 +10%」；新曲线下要么保留（技能比普攻多涨一点），要么并入 atk |
| 79-84 | `VOLLEY_DPS 6` `volley_k()` | 连发每柄 = 6×skill_g/出剑速率 | `air_caster.gd:466` | 招式层，不动 |
| 88-93 | `Q_DPS 1.8` `q_k()` | 飞剑阵每柄 | `flying_sword.gd:560,569` | 招式层，不动 |
| 98-110 | `SKILL_TARGET` `SKILL_K` `skill_k()` | 剑诀 Z/X/C 实测校准倍率 | `air_caster.gd:557,602,658,707,775,827` | 招式层，不动 |
| 114-118 | `GROUND_REF 8` `ground_k()` | base(r)/8 | `player_melee.gd:853` | 招式层，不动 |
| 121 | `BLOCK_CHIP` | 0.15（条上点的比例） | `player_melee.gd:1011`、`raid_pace_test.gd:652` | 条不变就不动 |
| 125 | `CALM_REGEN` | 4 点条 / 秒 | `RM:2752-2756` | 条不变就不动 |
| 129-135 | `BOSS_REF_REALM 3` `boss_k()` | 剑冢首领血量倍数（大厅） | `boss_arena.gd:162`、`combat_table.gd:158` | 大厅链路，不建议动 |
| 138-140 | `PVP_HIT_CAP 22` `PVP_BURST 30` `PVP_SUSTAIN 25` | 条上点数 | `RM:796-805`（`_pvp_clamp`）、`combat_table.gd:124-149` | 用户要保留；新 PvP 平衡数值另加在这一节 |
| 152-179 | 擂台一组 `ARENA_UNIT 2.4` `ARENA_ADV_LV 0.012` `ARENA_ADV_CAP 0.12` `ARENA_HIT_CAP 14` `ARENA_BURST 26` `ARENA_SUSTAIN 13` `ARENA_AI_HP 42` `ARENA_AI_DMG 1.0`；`arena_adv` `arena_hit` `arena_clamp` `arena_ai_hp` | 擂台已经是「独立的平衡数值」：只看招式单位，每高一级 +1.2%、封顶 ±12% | `arena_duel.gd:342-343,470-471,683-684,700`、`arena_selftest.gd:79-324` | **大世界 PvP 的新公式可以照这套写**；用户要的「每高一境界 +15~25%」可以把 `arena_adv` 的按级改成按境界 |
| 185-188 | `power(realm, lv, fx)` | `(atk(lv)×(1+攻)×10 + hp(lv)/max(1−守,0.4)×(1+0.2养)) × 1.1^境界 × (1+0.05识)`，返回 **int** | `player_plate.gd:58`（局内 `:279`、大厅 `:289`）、`combat_table.gd:69` | 战力重做的入口；大数时注意 int 溢出 |

文件头注释（`CS:1-17`）写着「招式倍率 / 攻击力 / 气血条」三种单位的定义，改完要一起改。

---

## 2. 出手端：招式原始伤害在哪里产生

都只产生「raw = 倍率 × 境界 dmg」，送进目标的 `receive_hit(attacker, info)` 或 `air_hit(attacker, info)`，`info["dmg"]` 就是 raw。

| 来源 | file:line | 式子 |
|---|---|---|
| 地面连招（炼气 / 筑基） | `player_melee.gd:50-76`（ATK 表 dmg 9/11/17/8/9）、`:848-857` `_hit_info` | `a.dmg × (1.6 若 _bonus) × CS.ground_k(realm)` |
| 空中拳脚 | `air_moves.gd:36-71`（每招 dmg 0.4~1.6）、`air_melee.gd:3148-3166` `_resolve` | `_base() × a.dmg × mul × Moves.dmg_scale(连段)`；`_base()` = `realm.dmg × (AWAKE_DMG 1.3 若觉醒)`（`air_melee.gd:89-90, 519-520`） |
| 蓄力重击 | `air_melee.gd:3040` | info.dmg = `1.5+1.3k`，再进 `_resolve` 乘 `_base()` |
| 拳劲对拼赢 | `air_melee.gd:2027-2028` | `_base()×2.4` |
| 擒拿甩出 | `air_melee.gd:1705`，`air_moves.gd:127 THROW_DMG 1.5` | `_base()×1.5×dmg_scale` |
| 坠星踏 / 剑雨 | `air_melee.gd:2198, 2248`，`air_moves.gd:147,151` | `_base()×2.2` / `×1.9` |
| 抽回气弹 | `air_melee.gd:2320`，`air_moves.gd:159` | `_base()×0.6` |
| 乱舞 / 幻影 / 追剑 | `air_melee.gd:2405, 2411, 2479, 2876, 3273, 3291, 3328` | `_base()×0.12~0.3` |
| 觉醒震开 | `air_melee.gd:4245-4266` | `_base()×0.5` |
| 对波赢 | `air_melee.gd:4192-4204` | `_base()×12`（对手是真人时不打，见 5.3）+ 22 柄 `_base()×0.12` |
| 连发（长按 E） | `air_caster.gd:462-470` | `realm.dmg × CS.volley_k`；巨剑点缀 `:304` `realm.dmg×0.3` |
| 剑诀 Z/X/C | `air_caster.gd:557-880` | `realm.dmg × CS.skill_k(r,i) × 0.35~3.2` |
| 飞剑阵（Q） | `flying_sword.gd:560-561, 569, 583-592` | `realm.dmg × CS.q_k × (0.85~1.15)`；大乘溅射 ×0.6 |
| 大罡剑阵（R） | `gate_array.gd:315, 329` | `realm.dmg × 0.32 / 3.0` |
| 法术弹统一入口 | `spell_projectile.gd:203-215` `Proj.hurt`、`:219-229` `hurt_area`；目标分组 `:192-198`（enemies / swordsmen / air_foes——**联机别人的木偶也在 air_foes / swordsmen 里**，`remote_player.gd:112-116`） | 原样转 `receive_hit`；顺带 `p.air.on_spell_hit(amount)` 记连击（raw） |

**觉醒**：只有 `air_melee._base()` 乘 1.3；剑诀 / 连发 / 飞剑阵 / R 都不吃觉醒（air_caster 里没有 awake）。觉醒倍数在 raw 层，`player_dmg` 除 base 后照样保留，PvP 也保留（`awaken_fx` 只是表现）。

**远端木偶的投射物没有伤害**：`net.gd:526-531` 发投射物时 `o.erase("dmg")`，收到的一方 `:547` 设 `dmg = 0.0 / ghost = true`。**命中判定在出手的那台机器**，结算在挨打的那台。

---

## 3. 大世界 PvE：主角打怪

### 3.1 链路

```
招式 raw ──► mob.receive_hit / air_hit（raid_mob.gd:758 / 779）
           └► _take(dmg) （:743-745）: dmg_in.call(dmg)  ← RM._spawn_mob 里 m.dmg_in = player_dmg（RM:1386）
               └► RM.player_dmg(d, pvp=false)（RM:350-352）
                     k = sup_dmg_k()（天道压制）
                     CS.raid_hit(d, player.realm_idx, lv, fx.atk) × k
           └► _take_raw(实伤)（:748-755）: hp -= 实伤；Vfx.damage_number(实伤)；hp<=0 → _die
```

- 别人名下的怪（木偶，`m.puppet`）：`receive_hit/air_hit` 改调 `net_hit` = `RM._on_puppet_hit`（`RM:595-600`）：**在我这边**按我的 `player_dmg`（含天道压制）换成实伤、飘字，再 `net.send_mob_hit` 发给主人（`net.gd:815-826`）→ 主人 `RM.net_mob_take`（`RM:645-650`）→ `mob.net_damage`（`raid_mob.gd:641-657`）直接 `_take_raw`。所以怪的血永远在主人那边按「实伤」扣，主人不再换算。
- 木偶本地的 `hp_max = 100.0`（`RM:576`），只用 `net_push` 的血量比例（`raid_mob.gd:618-623`）。**怪的血量大小不过网络**，只过比例（`RM:545`）。
- AI（修士 / 道友）打怪：`mob.sim_damage(dmg)`（`raid_mob.gd:722-740`）**不换算**直接 `_take_raw`；打别人的怪木偶时带 `raw: true`（`:728`），`_on_puppet_hit` 见 raw 不再换算（`RM:596`）。
- 怪被打飞落地：`_take_raw(hp_max × 0.12)`（`raid_mob.gd:1009`）——按比例，不受大数影响。

### 3.2 Hammer 公式要知道目标的防御：怎么接

`dmg_in` 现在是 `Callable(dmg) -> float`，**拿不到是哪只怪**。Hammer 的 `atk²/(atk+3.5·def)` 需要目标 def，三个接法：
- 生成时绑定：`m.dmg_in = player_dmg_vs.bind(m)`（`RM:1386`）；AI 修士同理（`RM:1804`）。
- 或者改 `raid_mob._take` 把自身（`self.lv / self.def_v`）一起传进 `dmg_in`。
- `RM._on_puppet_hit(m, info)` 手里本来就有木偶 `m`（有 `lv / def / elite`，`RM:572-575`），可以直接按木偶的等级算 def。

注意：这个公式一次齐次（双方同乘 k 伤害乘 k），但**不再是「倍率 × 攻击力」**——同一招打不同防御的怪，倍率不再线性。`raid_pace_test.gd` 的 `--pace-combat` 把「单位」定义成 `伤害 ÷ CS.atk(lv)`（`raid_pace_test.gd:386, 448`），SKILL_K 的校准也基于这个（`CS:96-106`），用了防御公式后这个定义要改成「对零防御目标」或改成直接量「几下打死」。

### 3.3 怪的数值从哪来（大世界唯一的生成入口）

`RM._spawn_mob(def_idx, ri, pos, elite, lvl, hp_k)`（`RM:1371-1395`）：

```gdscript
var hp0 := (Data.BOSS_HP if is_boss else float(base[0])) * float(d["hp"])
var at0 := (Data.BOSS_DMG if is_boss else float(base[1])) * float(d["atk"])
m.hp_max = Data.stat(hp0, Data.MOB_HP_G, m.lv) * (Data.ELITE_HP if elite else 1.0) * hp_k
m.atk = Data.stat(at0, 0.2, m.lv) * (Data.ELITE_DMG if elite else 1.0) * Data.MOB_DMG
m.xp_k = 14.0 if is_boss else float(base[3]) * (3.0 if elite else 1.0)
m.dmg_in = player_dmg
m.atk_out = to_player
```

- `Data.stat(base, k, lv) = base + base×k×(lv−1)`（`raid_data.gd:158-159`）：**线性**。怪 ×8/境界要改这里（或换一个 `Data.mob_hp(lv)` / `mob_atk(lv)`）。`Data.stat` 还被 AI 修士 / 道友拿去算（第 6 节），别直接改它的含义，另起函数更安全。
- `Data.SHAPE_BASE`（`raid_data.gd:209`）：`beast [48,12,10,1.0]`、`floater [36,9,9,0.9]`、`brute [100,16,18,2.4]` = [1 级生命, 1 级伤害, 导演点数, 经验系数]。注释「主角 1 级一下 100% 伤害的招式打 12」——怪血是按 `CS.ATK_BASE 12` 配的。
- `MOB_HP_G 0.25`（`:212`）、怪攻每级 0.2（写死在 `RM:1384`）、`BOSS_HP 70`（`:213`）、`BOSS_DMG 10`（`:214`）、`ELITE_HP 2.5` `ELITE_DMG 1.5`（`:132-133`）、`MOB_DMG 0.8`（`:135`，所有怪包括首领再乘）。
- `Data.MOBS`（`raid_data.gd:215-262`）：10 种小怪 hp 0.6~1.3 / atk 0.7~1.4；5 个首领 hp 14/16/18/20/24、atk 1.8/1.9/2.0/2.1/2.3。
- **死常量**：`PLAYER_HP 110`（`:128`，没人用）、`REALM_DMG`（`:280`，没人用，和 Realm.LIST 重复）、`ELITE_COST 6`（`:131`）。`PLAYER_DMG 12` 还在用（第 6 节）。
- **注释过时**：`raid_mob.gd:50` 写「精英生命 ×4、伤害 ×2」，实际是 2.5 / 1.5；`raid_data.gd:125` 也写「精英 = 点数 ×6、生命 ×4、伤害 ×2」。

所有调 `_spawn_mob` 的地方（都只给等级 / 精英 / hp_k，不自己设血攻，所以改 `_spawn_mob` 就全覆盖）：
- 巢穴首领 `RM:1484`（等级 = 巢穴处 +2）；天地异动游荡首领 `RM:1515`（+1，`hp_k 0.6`）；守宝怪 `RM:1629`；导演刷怪 `RM:1666, 1683`；给 AI 修士喂的怪 `RM:1861`；刷怪点 `raid_camps.gd:487`（交接时按比例回血 `:475, 496`）。
- 自检 / 预热：`main.gd:4889, 5056, 5479, 5609, 5758, 5871, 5918, 6071`（带 hp_k 50 / 30 / 400 / 4 之类的倍数，是相对值，大数下照样成立）、`raid_pace_test.gd:416, 604, 1154`、`shenshi_selftest.gd:102-103`、`warmup.gd:408`。

怪的等级：`Prog.mob_level(ri, depth) = REGIONS[ri].lv + round(depth × DEPTH_LV[ri])`（`progression.gd:106-109`；区域基础等级 1/7/10/13/16，`DEPTH_LV [4,4,4,4,8]` `:91`）→ 1~24，首领 +1/+2 → 最高 26。**怪的等级和境界边界对不齐**（黄枫谷 7~11 横跨结丹 7-9 和元婴 10-12），所以「怪每境界 ×8」只能落成「每级 ×8^(1/3) ≈ 2」。

---

## 4. 大世界 PvE：怪打主角 / 主角的气血条

### 4.1 链路

```
raid_mob._hit_player(dmg, heavy, dir, ranged)（raid_mob.gd:822-833）
  ├ 被 AI 引走（decoy 有效）：decoy.mob_hit(raw)  ← 不换算（远端玩家 / AI 修士 / AI 道友，见下）
  ├ dmg = atk_out.call(dmg)  = RM.to_player = CS.to_bar(raw, lv, fx.guard)   → 条上点数
  ├ 地面：player.melee.receive_attack(self, {dmg 条点, block_pst 14, hit_pst 10})
  └ 空中：player.air.receive_attack(self, {dmg 条点, kb 22/6, ranged})
```

怪出手的倍数：近战 `atk × (1.5 若首领)`（`raid_mob.gd:970`）、首领震地 `atk × 2.0`（`:987`）、远程弹 `atk × 0.7`（`:862`）、首领一次 5 发（`:958`）。

**别人名下的怪打我**：主人那边 `_hit_player` → decoy 是我的木偶 → `remote_player.mob_hit(raw)`（`remote_player.gd:240-243`）→ `net.send_mob_attack`（`net.gd:673-684`）→ 我这边 `RM.net_mob_attack`（`RM:653-654`）→ `net_take_hit(src, from=0, raw…)`（`RM:768`）→ `to_player(raw)` 用**我的** lv / 守。所以怪的攻击在网络上传的是**怪的原始攻击（怪的单位）**，接收方换算——这条在新体系下天然正确，不用改协议。

### 4.2 气血条（0~100）的结算点

| 位置 | file:line | 内容 / 写死的数 |
|---|---|---|
| 条上限 | `player_melee.gd:24` | `const HP_MAX := 100.0` |
| 地面受击 | `player_melee.gd:990-1016` `receive_attack` | 弹反 0 伤；格挡 `hp - dmg × CS.BLOCK_CHIP`、不低于 `min(hp,1)`（`:1011`）；`_on_hurt` `hp -= dmg`（`:1090`），≤0 陨落（`:1106-1114`） |
| 空中受击 | `air_melee.gd:3379-3430` `receive_attack` | 瞬身 / 拨开 0 伤；护体 `hp - dmg×0.15` 不低于 1（`:3418`）；破防 `_crush` 吃六成（`:2524-2535`）；`_hurt` `hp -= dmg`（`:3555-3558`）、觉醒槽 +8 |
| 空中回血 | `air_melee.gd:75-76, 2635-2636` | 6 秒没挨打后每秒 +6 点 |
| 地面脱战回血 | `RM:2744-2758` | 5 秒后每秒 `CS.CALM_REGEN 4` + 养法宝 `4×vital×1.5` |
| 升级 | `RM:435` | `hp + 20` 点 |
| 服丹回血 | `RM:2293-2313` | `heal` 是物品里存的整数（修为丹 25/25/30/30/35，`raid_items.gd:34,85`；回春丹 60，`:90`），**直接加条上点数**；飘字 `"气血 +%d" % heal`（`RM:2309`）——玩家牌显示实数，这里显示的却是条上点数 |
| 渡劫 | `RM:924`（成功回满）、`RM:938`（失败至少 30 点）、`tribulation.gd:252`（每道没挡住 `-14` 点、不低于 5） |
| 进局 / 结算 | `RM:270, 2635, 2700`（回满） |
| 其他直接扣条 | `RM:787-793`（net_take_hit 御剑 / 遁光中被打）、`arena_duel.gd:711-716` |
| 陨落判定 | `RM:2744`（`hp <= 0 → _finish(false)`）、`player.gd:220` |

读条做判断的地方（都按 100 写）：`ally_brain.gd:112-115`（`hp/100`）、`arena_duel.gd:464-465, 474, 602`、`audio_director.gd:273-276`（回血 >12 点放音效）、`net.gd:474`（同步的就是条上的点）、`lan_presence.gd:152`、`remote_player.gd:183, 357`（`hp/100`）、`player_plate.gd:294`（`hp_ratio()`）。自检：`pvp_rules_selftest.gd:157-163`（<60 补到 60）、`ally_selftest.gd:35-234`、`main.gd`（59 处）、`raid_pace_test.gd`（15 处，如 `:622` <40 回满）。

**结论**：条保持 0~100，大数只出现在 `CS.hp(lv)`（显示用的实数上限）和 `to_bar` 的分母里。

### 4.3 法宝（守 / 攻 / 养 / 识）

- 汇总：`raid_items.gd:173-181` `fx_total()`：`atk / guard / seek / vital` 都是**比例**（物品里的 `amt` ÷ 100），守封顶 0.6、攻封顶 0.8（`:179-180`）。各品阶的百分数 `FX_AMT`（`raid_items.gd:23`）：攻 `[6,12,20,30,45]`、守 `[6,11,17,24,32]`——相邻品阶比 2.0/1.67/1.5/1.5，不是 Hammer 的 ×1.65 固定比。
- 用到的地方：攻 → `CS.raid_hit`（`RM:352`）；守 → `CS.to_bar`（`RM:357`）、AI 修士的 `dmg_mul ×(1−守)`（`RM:1825`）；养 → `RM:2756`；识 → 搜点（`RM:2743`）、战力。
- **存档里存的是烤好的 `amt` 整数**（`raid_items.gd:70`；`raid_profile.gd:135` `_fix_item` 把 amt / heal 转 int；`raid_profile.gd:251` `stack_key` 带 amt）。改 `FX_AMT` 不会影响已有存档里的法宝；如果改成「平加攻击」或换数，需要 `raid_profile.gd` 的 VER 升一档 + 迁移（按 `FX_AMT[fx][tier]` 重算 amt），否则旧法宝数值不变、堆叠键对不上。
- 进局时加载：`RM:240-246`（`Profile.begin_raid()` → `gear` → `_recalc_fx`）。

---

## 5. PvP：所有「玩家打玩家」的路径

### 5.1 大世界（raid_manager 是 net.gd 的 world）

```
[出手方 A 的机器]
招式 raw ──► remote_player.air_hit / receive_hit（remote_player.gd:397-406；receive_hit 加 ranged=true）
           └► _send(info)（:376-392）: 队友 / 已死 / 在保护里 → -1；非 fwd/up/down 的 launch 清掉
               └► RM.net_deal_hit(puppet, peer, info)（RM:759-765）
                     d = player_dmg(raw, pvp=true)      ← A 的 atk(lv)、A 的法宝攻（≤0.8），不吃天道压制
                     Vfx.damage_number(d)               ← A 看到的是「打怪的实伤」，不是对方真掉的
                     net.send_hit(peer, info{dmg=d})    （net.gd:799-805）
[受击方 B 的机器]
net._hit(dmg, dir, kb, heavy, launch, ranged)（net.gd:808-811）: 队友直接丢
  └► RM.net_take_hit(src=A的木偶, from=A, dmg…)（RM:768-793）
        对波预警窗口里的飞剑不算（:771-772）
        d = to_player(dmg)                    ← B 的 hp(lv)、B 的法宝守（≤0.6）
        if from > 0: d = _pvp_clamp(from, d)  ← 单下 ≤22、同一人余量 30、之后每秒 25（RM:797-805）
        地面 → melee.receive_attack（能弹反 / 格挡擦一成五）
        空中 → air.receive_attack（能瞬身 / 护体擦一成五 / 拨开）
        其他 → 直接扣条，≤0 走陨落
```

- 现在的效果：跨境界的差距 = 攻击力比 × 气血比（24 级打 1 级：5.6×7.9 ≈ 44 倍），全靠 22/30/25 的封顶兜（`combat_table.md` PvP 表：大乘打炼气不封顶 1348 点）。照搬 Hammer ×5/境界后，A 端 `player_dmg` 和 B 端 `to_player` 的比值会到 5^7 级别，**低境界打高境界会几乎不掉血**（现在是 1.7 点），所以 PvP 必须两端都换掉，不能只改封顶。
- **接入点**（二选一，推荐 a，和擂台一致）：
  - a) **出手方折成「条上点数」**：`RM.net_deal_hit` 里把 `player_dmg(raw, true)` 换成 `CS.pvp_hit(raw, my_realm, lv, puppet.realm_idx, puppet.lv, min(fx.atk, PvP攻封顶))`（木偶有 `realm_idx / lv`，来自状态包 `net.gd:473-474` → `remote_player.gd:128-141`）；受击方 `RM.net_take_hit` 在 `from > 0` 时**跳过 `to_player`**，只乘自己的守（PvP 守封顶）再 `_pvp_clamp`。
  - b) 受击方算：出手方只发 raw/base（招式单位），受击方用 `_remote(from)` 的 `realm_idx / lv` 算。缺点是出手方的法宝攻要么也得同步过去，要么在出手方先乘。
  - 法宝：**攻在出手方、守在受击方**，对方的法宝不同步（状态包里没有）。「PvP 法宝加成封顶」两端各封一次。
  - 飘字：A 端 `RM:764` 显示的数要换成 PvP 口径（例如「条上点 × 对方显示气血 / 100」的估计值），否则大数时 A 看到上亿、B 只掉 22 点。
  - `_hit` RPC 的 dmg 含义变了要考虑**新旧版本混房**（没有协议版本号）。
- 别人名下的怪打我也走 `net_take_hit`，但 `from = 0`（`RM:654`），不进 PvP 分支；改的时候要保留「from > 0 才是真人」这个判断（`RM:774-775`）。

### 5.2 主城擂台（arena_duel 是 net.gd 的 world，`arena_duel.gd:389`）

```
[出手方] remote_player._send → net.raid = arena_duel → arena_duel.net_deal_hit（arena_duel.gd:680-691）
          want = CS.arena_hit(raw, my_realm, lv, puppet.lv)   = raw/base × 2.4 × arena_adv(级差)
          d = CS.arena_clamp(want, _heat_out); _heat_out += d   ← 出手方先封一次
          send_hit(dmg = 条上点数)；飘字 d
[受击方] arena_duel.net_take_hit（:695-716）: d = arena_clamp(dmg, _heat)（再封一次），然后地面 / 空中 receive_attack
_heat / _heat_out 每秒回 ARENA_SUSTAIN（:470-471）
```

- 擂台已经是「独立平衡数值」，**不读 atk/hp/法宝**；用户的「每境界 +15~25%」可以直接把 `CS.arena_adv(my_lv, their_lv)`（`CS:163-164`，按级差 ×1.2%、封顶 ±12%）改成按境界差，并让大世界 PvP 复用同一个函数。
- AI 陪练：`foe.hp_max = CS.arena_ai_hp(realm) = 42 × base(realm)`（raw 口径，主城里主角打 AI 不换算）、`foe.dmg_mul = 1.0`（`arena_duel.gd:342-343`）——AI 的招式伤害（air_foe 写死的 5/7/15/6/3.5）直接落在 100 点的条上。
- 擂台的等级：`arena_duel.lv = Profile.cult(...)[0]`（`:227`），对手 `int(puppet.get("lv"))`（`:683`），状态包里的 level 是 `int(raid.lv)`（`net.gd:474`）。

### 5.3 不走上面两处的 PvP 旁路（要单独处理）

| 旁路 | file:line | 现状 |
|---|---|---|
| **飞剑对波输了** | `air_melee.gd:4219-4222` | 本地 `_hurt(foe, {"dmg": 28.0})`：写死 28 点条，不经 to_player、不经 `_pvp_clamp` / `arena_clamp`。赢的一方对真人不打那一下（`:4195` `if not netfoe`），只放 22 柄 `_base()×0.12` 的追剑（这些照常走 `_send` → 封顶）。胜负由 `net_clash_end` 对账（`:4159-4165`） |
| 对波输（对 AI） | 同上 | 对 AI 修士也是平 28 点，不乘 `dmg_mul`、不看等级 |
| 拳劲对拼输 | `air_melee.gd:2037` | 平 14 点；对真人不会发生（`remote_player` 没有 `brawl_begin`），只对 AI |
| 被擒甩出 | `air_melee.gd:1769-1774`、`air_foe.gd:1468` | `16 × dmg_mul`；对真人不会发生（没有 `grab_throw`） |
| 真人对打的保护 / 起手预告 | `air_moves.gd:162-182`、`remote_player.gd:416-451`、`net.gd:557-558, 611`（`air_protect / air_opener`） | 只管能不能打到、硬直，不带伤害 |

### 5.4 AI 修士 = 「假 PvP」

大世界的 AI 修士（`air_foe.gd`，`RM:1785-1813`）走 PvE 链路（`f.dmg_in = player_dmg`，**吃天道压制**），见第 6 节。房间里有真人时 AI 修士全部退场（`RM:1833-1840`）。

---

## 6. AI 修士 / AI 道友 / 它们和怪之间

| 量 | file:line | 现在 | 新体系下的问题 |
|---|---|---|---|
| AI 修士气血 | `RM:1798` | `Data.stat(RIVAL_HP 260, 0.3, f.lv)`（怪血单位，线性） | 主角伤害几何增长后一刀秒；要跟新的「主角同级气血」曲线 |
| AI 修士打怪 | `RM:1799`，`air_foe.gd:1593` | `prey_dmg = Data.stat(PLAYER_DMG 12, 0.2, lv) × 0.6` → `mob.sim_damage`（不换算） | 怪血 ×2/级后它们打不动怪；应改成 `CS.atk(lv) × 系数` |
| AI 修士打主角 | `RM:1825`，`air_foe.gd:382-386` | `dmg_mul = RIVAL_DMG 0.42 × stat(1,0.2,f.lv)/stat(1,0.3,lv) × (1−守)`——**手写了一遍 to_bar 的「攻 0.2 / 血 0.3」比值**；乘到写死的招式数上：近战 15/5/7（`air_foe.gd:1847`）、连发 3.5（`:1050`）、气弹 6（`:1975`）、甩出 16（`:1468`），**结果直接是条上点数** | 换曲线后必须改成新曲线的比值（或走 `CS.to_bar(假想原始攻击, lv, 守)`） |
| 主角打 AI 修士 | `air_foe.gd:625-638` `_take` | `dmg ×(1−armor)` → `dmg_in`（= player_dmg，含天道压制）→ 扣血、飘字 | 和怪同一条 |
| AI 修士撞地伤 | `air_foe.gd:1127` | `26 × power × (1 + 0.012 × player.realm["dmg"])` → `_take` → `dmg_in` | 怪异地把 realm dmg 揉进了 raw；不改 Realm.LIST 就没事 |
| AI 修士被怪打 | `air_foe.gd:613-622` | `hp - dmg×0.25`，不低于 20% | 比例保底，问题不大 |
| AI 道友气血 | `RM:1933` | `Data.stat(380, 0.3, lv)` | 同上，被 ×2/级的怪秒 |
| AI 道友打怪 | `RM:1934, 1962`，`ally_brain.gd:38, 328-330, 390, 414, 446` | `prey_dmg = stat(12,0.2,lv)×0.6`，大脑再 `× DMG_K 0.3`（×0.9/1.0/1.6/1.8 各招） | 同上；DMG_K 是按「别让道友把升级速度翻倍」实测出来的（`ally_brain.gd:36-38`），换曲线后要按同样的「每 95 秒杀几只」重测 |
| AI 道友打 AI 修士 | `ally_brain.gd:331-333` | `receive_hit({dmg: Data.PLAYER_DMG × 0.5/0.8})` → 修士的 `dmg_in` = **主角的** player_dmg → `6/base(主角境界)×atk(主角lv)`：主角境界越高，这一下越小（现有的小 bug） | 顺手改成 `sim_damage` 式的直接实伤 |
| AI 道友挨怪打 | `ally_brain.gd:35, 614-620` | `hp -= 怪原始攻击 × HURT_K 0.55` | 道友气血曲线要和怪攻曲线一起改 |
| AI 道友撤退 | `ally_brain.gd:34, 227` | 按比例 | 不受影响 |

---

## 7. 天道压制

- 数据：`Prog.SUPPRESS_DMG 0.55`、`SUPPRESS_GAIN 0.25`、`suppress_gap(realm, ri) = max(realm − REGION_REALM_MAX[ri], 0)`，`REGION_REALM_MAX [1,2,3,4,7]`（`progression.gd:92, 249-256`）。
- 运行时：`RM.sup_gap`（`RM:127-129`），每 0.4 秒在 `_update_here`（`RM:327-340`）更新；进区提示一次。
- 伤害：`RM.sup_dmg_k()`（`RM:343-344`）→ 只在 `player_dmg` 里乘（`RM:351`），`pvp=true` 时不乘。受影响的：打自己的怪、打别人的怪木偶（`RM:596`）、打 AI 修士。
- 心得：`RM.kill_exp()`（`RM:361-362`）→ `add_insight`（`RM:372-391`）、`net_mob_died` 分心得（`RM:754`）。
- 文字：`RM:338` `"天道压制：境界高出此地，出手威力 ×%d%%，心得 ×%d%%"`、`raid_hud.gd:659-660` `"天道压制 ×%d%%"`（读 `sup_dmg_k()`，**去掉伤害压制后这里会一直显示 ×100%**，要改成显示心得折扣）、自检打印 `main.gd:6377-6379`、`raid_pace_test.gd:1201`。
- 去掉伤害压制：`sup_dmg_k()` 返回 1（或删掉 `RM:351` 的 k），改两处文字；`kill_exp` 保留。注意 `RM:19, 127` 的注释。

---

## 8. 首领 / 精英细节

- 精英：生命 ×2.5、伤害 ×1.5、心得 ×3（`RM:1383-1385`）；刷怪点一成是精英（`raid_camps.gd:131`），精英复活时间 ×2（`:163`）。
- 首领：生命 `70 × MOBS.hp`（14~24 → 980~1680 起，再按等级 ×(1+0.25(lv−1))）、攻 `10 × MOBS.atk × 0.8`，出手 ×1.5 / 震地 ×2，心得系数 14；巢穴首领等级 +2（`RM:1484`），游荡首领 +1 且血 ×0.6（`RM:1515`）。
- 首领只吃伤害和短硬直（`raid_mob.gd:649, 792-795`），不被击飞（`:608`）。
- **心得按 xp_k 认种类**：`RM:754` `2 if xp_k >= 10.0 else (1 if xp_k >= 2.6 else 0)`——精英 = 体型系数 ×3 要 ≥2.6、首领 14 要 ≥10，改 xp_k 时别越过这两条线。
- 首领血条 / 名牌只用比例（`raid_hud.gd:717`，`raid_mob.gd:235-243`）。

---

## 9. 大厅 / 试剑台 / 斗法台 / 剑冢首领（raw 链路，和大世界无关）

大厅里没有 `dmg_in`：主角打出的 raw 直接扣对手的血，对手的血也按 base 配，所以**各境界一样耐打**。只要不改 `Realm.LIST.dmg`，这一块完全不用动。

| 对手 | file:line | 血 | 打主角 |
|---|---|---|---|
| 斗法台陪练（air_foe） | `spar_zone.gd:26-33, 194-232` | `hpk(50/105/220) × player.realm["dmg"]`，换境界 `rescale_hp` | 招式数 × `tough.dmg`（1/1.1/1.3），直接是条上点 |
| 试剑台刀客 | `swordsman.gd:20, 39-48, 474-477` | `HP_MAX 120`（固定，**不随境界**） | 16/18/28/15 直接是条上点；它吃 `pst` 削架势（`:435, 478`，pst = dmg×0.6） |
| 剑冢首领 | `boss_demon.gd:35`、`boss_arena.gd:21, 162` | `12000 × CS.boss_k(realm)` | 弹幕打的是 `boss_arena.hp`（另一条 100 点的条，`boss_arena.gd:42`） |
| 木桩 | `enemy_dummy.gd:7` | 400 | — |
| 擂台 AI | `arena_duel.gd:342` | `42 × base(realm)` | 见 5.2 |

**如果有人想把 Realm.LIST.dmg 也放大**：会连带改动 `CS.base / ground_k / boss_k / arena_ai_hp`、`spar_zone` 的血、`air_foe.gd:1127` 的撞地伤、试剑台刀客（120 血固定会被秒）、`pst` 架势、`hud.gd:495` 连击伤害、`main.gd:1717` 自检，代价很大，不推荐。

---

## 10. 显示层（大数要改格式的地方）

| 位置 | file:line | 现状 | 改法 |
|---|---|---|---|
| 伤害飘字 | `vfx.gd:362-366` | `l.text = str(int(round(value)))` | 换 `Prog.short_num`（或 Vfx 里自带一份，Vfx 不 preload progression）；**int 溢出**见 0.3 |
| 飘字调用 | `raid_mob.gd:752`、`air_foe.gd:638`、`RM:598, 764`、`arena_duel.gd:691`、`boss_demon.gd:642`、`enemy_dummy.gd:123`、`swordsman.gd:477`、`main.gd:5145` | 传进来的就是实伤（大世界）或 raw（大厅） | PvP 两处（`RM:764`、`arena_duel.gd:691`）要显示 PvP 口径 |
| 飘字预热 | `warmup.gd:304-305` | 预热 `1234567890.0` 和 `88.0` 的字形 | 加上「万」「亿」「.」的字形；网页 / 手机用的是裁剪过的随包字体（`ui_style.gd:36-39`），新出现的汉字要确认字体里有（「万」「亿」已被 `short_num` 用在心得上，应该在） |
| 连击伤害 | `hud.gd:495`，来源 `air_melee.gd:3304-3306`（`combo_dmg += dmg`）、`:3313-3316`、`spell_projectile.gd:204-205` | `"伤害 %d" % int(a.combo_dmg)`，累加的是 **raw**（大厅口径），大世界里和飘字的实伤对不上 | 在 `_add_combo` 处换成实伤（大世界经 `mgr.player_dmg`），格式用 short_num |
| 玩家牌气血 | `player_plate.gd:61-62, 257` | `hp_cap(lv) = int(round(CS.hp(lv)))`；`"%d/%d" % [ceil(hp_k×hp_max), hp_max]` | short_num；int 溢出 |
| 玩家牌战力 | `player_plate.gd:57-58, 261, 279, 289` | `str(pw)` | short_num；`CS.power` 返回 int |
| 服丹回血 | `RM:2309` | `"气血 +%d" % heal`（条上点） | 显示 `heal × CS.hp(lv)/100` 的实数 |
| 升级提示 | `RM:432` | 「气血、伤害提升」 | 可以带上新战力 |
| 天道压制 | `RM:338`、`raid_hud.gd:660` | 见第 7 节 | — |
| 灵力（不在本区域） | `hud.gd:475`、`player_plate.gd:259` | 按 60~300 显示 | 不动 |

---

## 11. 存档 / 网络里带的战斗数

- 存档（`raid_profile.gd`）：境界、lv（1~99）、xp、法宝（`fx` + 烤好的 `amt`）、丹（`heal` 烤好的整数、`grade`、`exp`——服丹按 `pill_exp_now` 现算，不读 exp）。**没有存攻击 / 气血 / 战力**，换曲线不用迁移；换法宝数值要迁移 amt（第 4.3 节）。现有迁移框架 `raid_profile.gd:87-91, 126-137`。
- 网络：状态包 `[pos, yaw, st, realm_idx, 条上的 hp, pose, pose_n, lv, vel, flags]`（`net.gd:473-474`）；怪的批量包带 `hp/hp_max` 比例（`RM:544-545`）；`_hit(dmg…)` 带出手方换算后的实伤（`net.gd:802`）；`_mob_hit(dmg…)` 带出手方换算后的实伤（`net.gd:815-826`）；`_mob_attack(dmg…)` 带怪的原始攻击（`net.gd:673-684`）；`send_mob_dead(…, lv, xp_k, …)`（`RM:1695`）。**没有协议版本号**。

---

## 12. 自检 / 测试里的数值断言

| 文件 | 行 | 断言 / 假设 | 新体系下 |
|---|---|---|---|
| `_tasks/numbers_sim/combat_table.gd` | 29-37 | 自己复刻了 `_spawn_mob` 的怪血 / 怪攻公式 | 改 `_spawn_mob` 时**同步改这里**（最好让两边调同一个 Data 函数） |
| 同上 | 70 | 灵力回满 6.25 秒 | 不受影响 |
| 同上 | 72-77 | 连发 / 飞剑阵每秒伤害随境界不降、不超过 1.7× / 2× | 招式层，不受影响 |
| 同上 | 81 | 炼气 / 筑基地面起手倍率相等 | 不受影响 |
| 同上 | 118-121 | **几下打死一只 1.5~9（巨汉 ≤12）、两种怪平均 2.5~9、怪一下掉条 4~14%、首领一下 ≤36% / 震地 ≤48%**（按 `lv = 3r+2` 对 `REALM_MOB_LV[r]` 级的怪） | **这是重构的验收线**：要保持节奏，同级「怪血 ÷ 主角一刀」「怪攻 ÷ 主角血」两个比值要落在同样的区间里。用 Hammer 的「主角 ×5 / 怪 ×8 每境界」直接套，几下打死会每境界 ×1.6，到大乘 ×27，全部不通过 |
| 同上 | 124-149 | PvP 表（用 `raid_hit` + `to_bar` 算）、`ttk >= 2.5` 秒 | PvP 换独立公式后整段要重写 |
| 同上 | 154-165 | 剑冢首领各境界时长差 <1.6 倍 | 大厅链路，不改 Realm.LIST 就不受影响 |
| `combat_table.md` | — | 上一次跑出来的基线表（第 13 节引用） | 重跑对照 |
| `scripts/raid_pace_test.gd` | 383-656（`--pace-combat`） | 「单位 = 伤害 ÷ CS.atk(lv)」（`:448`）、怪打主角掉条和 `CS.to_bar(mob.atk, lv)` 对比（`:609`）、格挡 ≈ ×0.15（`:652`） | 用防御公式后「单位」的定义要改 |
| 同上 | 418-419、606-607 | 木桩怪 `hp_max = 1.0e7` 当「打不死」 | **大数下可能被打穿**，改成 `INF` 级（如 1e30）或按实伤 ×1000 |
| 同上 | `--raid-pace`（`:1154` 附近） | 量每分钟杀几只，写 `pace.json` | 改完必须重量，`life_sim.gd` 读它（`life_sim.gd:110-119`） |
| `scripts/arena_selftest.gd` | 76-87, 136, 234, 287-324 | 打印擂台 vs 大世界对比，调 `CS.arena_hit / to_bar / atk / base / arena_adv / ARENA_*` | 只打印，但**函数签名改了会编译失败** |
| `scripts/lan_selftest.gd` | 156 | `receive_hit(dmg = CS.base(realm) × 6)` | 招式层，不受影响 |
| `scripts/pvp_rules_selftest.gd` | 127-163 | 条 <60 补到 60 | 条不变就不受影响 |
| `scripts/ally_selftest.gd` | 35-234 | 设条 100 / 28 | 同上；道友 DMG_K 的「95 秒杀几只」要重测 |
| `scripts/main.gd` | 2444-4554 | 大量 `hp_max = 99999 / 9e6` 的沙包、`air_hit({dmg: 5/38/50/300})` | 都是大厅 raw 链路（spark / duel 自检），不改 Realm.LIST 就不受影响 |

---

## 13. 隐含假设 / 坑（逐条）

1. `Prog.MAX_LV = 99`，`CS.atk/hp` 现在是线性所以 lv 99 也只有 247 / 3344；几何曲线必须在 24 级后换线性（int64 溢出）。`combat_table.gd:54, 139` 也会算 40 级 / 99 级。
2. 怪的等级 1~26，和境界三级一档对不齐；「怪每境界 ×8」只能写成每级 ×2。
3. `Data.stat()` 是线性的、被怪 / AI 修士 / AI 道友共用，别直接改它的含义。
4. AI 修士打主角的 `dmg_mul`（`RM:1825`）手写了 `0.2/0.3` 两个成长率，和 `CS.ATK_G / HP_G` 是同一个东西但没引用——改曲线时最容易漏。
5. 怪的攻击每级 0.2 写死在 `RM:1384`（不是常量）。
6. `CS.to_bar` 和 `raid_items.fx_total` 各封了一次守 0.6；`CS.GEAR_ATK_CAP` 和 `raid_items.gd:180` 各写了一次 0.8。
7. 天道压制注释说掉落品质也打折，代码没有。
8. 觉醒 ×1.3 只作用于空中拳脚；剑诀 / 连发 / 飞剑阵 / R 不吃。
9. 对波输平 28 点、拳劲对拼输平 14 点，不看对手等级，PvP 不封顶。
10. 连击「伤害」累加的是 raw，大世界里和飘字对不上。
11. 服丹「气血 +25」是条上的点。
12. 法宝 `amt`、丹 `heal` 烤在存档里。
13. PvP 的伤害飘字在出手方，显示的是打怪口径、未封顶的数。
14. 网络协议没有版本号。
15. `raid_mob.gd:50`、`raid_data.gd:125` 的精英倍数注释过时（实际 2.5 / 1.5）。
16. `REALM_DMG`、`PLAYER_HP` 是死常量。
17. AI 道友打 AI 修士走主角的 `player_dmg`（`ally_brain.gd:333`），主角境界越高这一下越小。
18. `life_sim` 的 15.9 小时依赖旧数值下实测的杀怪速度（`pace.json`）。
19. 远端投射物 dmg = 0，命中在出手方判定；所以 PvP 的「出手方换算」是现成的、可靠的接入点。

---

## 14. 改造接入点清单（按改动顺序）

1. `CS`：新增 / 替换 `atk(lv)`、`hp(lv)`（24 级后线性）、主角 `def(lv)`；`raid_hit` 改成带目标防御的版本（`atk²/(atk+3.5·def)` × 招式单位 × 法宝攻）；`to_bar` 改成先按主角防御算实伤再 ×100/hp；新增 `mob_hp(lv) / mob_atk(lv) / mob_def(lv)`（或放 Data）；新增 PvP 一组（`pvp_hit`、境界差加成、法宝攻 / 守的 PvP 封顶），沿用 `PVP_HIT_CAP/BURST/SUSTAIN`；`power()` 重做（注意 int）。
2. `RM._spawn_mob`（`RM:1381-1387`）：怪血 / 怪攻改新曲线；`dmg_in` 绑定目标（`.bind(m)`）。`combat_table.gd:29-37` 同步。
3. `RM.player_dmg / to_player / sup_dmg_k`（`RM:343-357`）：去掉伤害压制；`_on_puppet_hit`（`RM:595-600`）按木偶的等级算防御。
4. PvP：`RM.net_deal_hit`（`RM:759-765`）出手方换算 + 飘字；`RM.net_take_hit`（`RM:768-793`）`from > 0` 时跳过 `to_player`；`_pvp_clamp` 保留；擂台 `arena_duel.gd:680-716` + `CS.arena_adv` 改按境界；对波输的 28 点（`air_melee.gd:4222`）在 PvP 时走封顶。
5. AI 修士 / 道友：`RM:1798-1799, 1825, 1933-1934, 1962`、`ally_brain.gd:333`，改成引用 CS 的新曲线。
6. 显示：`vfx.gd:366`、`warmup.gd:304`、`hud.gd:495`（+ `air_melee._add_combo` 喂实伤）、`player_plate.gd:257, 261`、`RM:2309, 338`、`raid_hud.gd:660`。
7. 法宝数值若改：`raid_items.gd:23, 173-181` + `raid_profile.gd` 升 VER 迁移 amt。
8. 验收：`combat_table.gd`（改 PvP 段、保留第二段的区间）→ `raid_pace_test.gd --pace-combat`（先把 1e7 木桩改大）→ `--raid-pace` 重量 `pace.json` → `life_sim.gd` 确认普通玩家约 15.9 小时到大乘。
