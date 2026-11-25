# E · 旧经济 / 数值子系统摸底（主干解耦用）

只读调研，未改任何项目文件。行号以 2026-11-25 工作区（raid-block-world，提交 5c25796）为准。

---

## 0. 结论先说

1. 主干要的「修仙版」经济已经完整存在于 `raid_profile.gd`（存档 / 仓库 / 法宝 / 随身 / 储物戒 / 坊市 / 丹房 / 一局进出）+ `raid_items.gd`（物品、掉落、坊市货单、丹方）+ `progression.gd`（修为曲线、区域境界档、丹药、破境丹、心得）+ `combat_stats.gd`（怪 / 主角的量级和伤害公式）。新图、备战 / 坊市 / 段位只要**调这几份**，不需要 ex_profile / ex_data 的任何东西。
2. **元婴 = 境界下标 3**（`realm.gd:43` `Realm.LIST[3].name == "元婴"`）。「元婴及以上」= `Profile.realm() >= 3`（存档境界，`raid_profile.gd:268`）。
3. 新的两张图建议各给一个**新的区域下标**：沙海古墟 ri 5（元婴~化神档，较易），天工秘所 ri 6（化神~合体档，较难）。所有按区域查的表扩到 7 项、`clampi(ri, 0, 4)` 改成 `REGION_N - 1`，再加一张「掉落借哪个老区域的灵草 / 灵材 / 品阶运气」的映射表。这样怪的数值、心得、天道压制、联机木偶（只按 region + lv 现算）全部原样可用。
4. 英雄不改数值：kit 出手已经是「招式单位 × `player.realm["dmg"]`」（`kit_base.gd:258` → `air_melee.gd:614`），大世界 `CS.raid_hit` 会除掉 `base(realm)`。所以只要 **set_hero 不再把 realm_idx 钉成 HeroDefs.TIER（2）、CS.heroes_on 在主干不再置 true**，英雄就自动按玩家境界走数。

---

## 1. 存档 `scripts/raid_profile.gd`（user://xiuxian_profile.json，VER 3）

字段（`_fresh`，`raid_profile.gd:55-59`）：`lingshi`（起始 300，`:33`）、`realm`、`lv`、`xp`、`stash`（仓库，60 格，`:22`，灵草 / 丹叠 99 一格）、`gear`（佩戴法宝 ≤3，`:28`）、`carry`（随身丹符 ≤4，`:29`）、`ring`（储物戒 1~4 格，`:30-32`，死了也保住）、`ring_cap`、`live`（局中带进去的东西，崩溃恢复）、`stats {raids, out, dead, best}`、`tox/tox_t/seen`、`farm`。
`_load` 只拷 `_fresh` 里有的键（`:82-84`），**新加字段只要写进 `_fresh` 就行，不用升 VER**。

### 读
| 函数 | 行 | 用途 |
|---|---|---|
| `data()` | :62 | 整份字典 |
| `lingshi()` | :264 | 灵石 |
| `realm()` | :268 | 存档境界（0 炼气…7 大乘） |
| `cult(realm)` → `[lv, xp]` | :276 | 修为 |
| `boot_realm()` | :291 | 开机境界（自检一律 0！） |
| `stash() / gear() / carry() / ring() / ring_cap()` | :295/345/349/353/357 | 各列表 |
| `stash_slots(list?)` / `stash_fits(it, extra, list?)` | :314 / :331 | 仓库格数 / 放不放得下 |
| `stacks(it)` / `stack_key(it)` | :300 / :306 | 叠放规则（和 abode_ui 的 _stack_key 一致） |
| `wealth()` | :361 | 灵石 + 所有物品价值 |
| `count(name)` | :601 | 仓库里某物几件（丹方用） |
| `realm_pills(realm)` | :588 | 只能在该境界服的本境丹还剩几颗（渡劫前提醒） |
| `in_raid()` | :433 | 一局没结束：洞府锁死（QA BUG-01） |
| `test_mode()` | :44 | 带非游玩参数 = 自检档 |

### 写（成功返回 ""，失败返回原因；局中一律返回 `RAID_LOCK`）
| 函数 | 行 | 说明 |
|---|---|---|
| `equip(i)` / `unequip(i)` | :445 / :457 | 仓库 ↔ 佩戴法宝（只收 kind=gear） |
| `pack(i)` / `unpack(i)` | :468 / :482 | 仓库 ↔ 随身（只收 pill / key / tool） |
| `to_ring(i)` / `from_ring(i)` | :493 / :505 | 仓库 ↔ 储物戒（灵材占 2 格，`Items.size_of`） |
| `sell(i)` → 灵石数 | :516 | 卖仓库第 i 件，价 = it.value |
| `sell_junk()` → [件数, 灵石] | :531 | 一键卖凡品法宝 + 灵材 + 服不了的本境丹 |
| `buy(good)` | :553 | good = `Items.shop()` 的一项 `{item, price}` |
| `ring_next_price()` / `upgrade_ring()` | :567 / :572 | 储物戒扩格（500 / 2000 / 6000） |
| `can_craft(r)` / `craft(r)` | :609 / :619 | r = `Items.recipes()` 的一项 |
| `kit_ok()` / `take_kit()` | :641 / :650 | 散修行囊（穷到没法宝时白送凡品两件 + 回春丹两颗） |
| `spend(n)` | :421 | 扣灵石（**局中也允许**：渡劫布阵、献灵石撤离） |
| `set_cult(lv, xp)` | :284 | 直接写修为 |
| `save()` | :244 | 落盘 |

### 一局
* `begin_raid()` → `{gear, carry, ring}`（`:372`）：随身丹符从存档拿走、进背包；`live` 记下带进去的；`stats.raids+1`。调用处 `raid_manager.gd:265-271`（carry 直接 append 进 bag，`_recalc_fx()` 用 `Items.fx_total(gear)`）。
* `end_raid(ok, bag, ring_items, gear_items, realm_idx, -1, 0.0)`（`:386`）：撤出 → 背包进仓库（满了按价折灵石）、法宝回身上、`stats.out/best`；陨落 → 背包 + 法宝全丢、`stats.dead+1`；储物戒两种都保；境界取 max（陨落不掉境界）。调用处 `raid_manager.gd:2898`。
* 心得先由管理器 `Prog.profile_add_xp(keep)` 写进修为（`raid_manager.gd:2889-2894`，陨落 keep = 心得 × `Prog.DEATH_KEEP` = 0，`progression.gd:209`），再调 end_raid。
* 联机陨落：背包 + 法宝变一只「储物袋」箱子留原地（`raid_manager.gd:2876-2879`）。断线没收到关房：`Profile._recover_live()`（`:194`）还回带进去的、不算陨落（`raid_manager.gd:2828-2850`）。

**这就是「死了跟大世界一样」的全部规则——新图直接走 raid_manager 的 `_finish(success)`（`raid_manager.gd:2866`）即可。**

### 缺的小接口（建议补，主干 UI 外壳要用）
* `add_lingshi(n)`：目前只能 `data()["lingshi"] += …`（hub_hall.gd:2152 这么干的）。
* `add_items(list) -> Array(放不下的)`：灵田收获现在是 farm_plots.gd:267-282 手写 `stash_fits + append`，备战 / 段位奖励也会用。
* `hero()` / `set_hero(id)`：`_fresh` 里加 `"hero": "yujian"`（或 HeroDefs.DEFAULT），三个英雄全部视为已解锁（不存解锁表）。替代 `ex_profile.gd:650-685`。
* `stats.kills`：段位页要「击杀」卡片（meta_rank.gd:93 读 `kills`），end_raid 加一个可选参数 `kills := -1` 累加；`_fix_types` 的兜底（`:115-116`）同步加上。

---

## 2. 物品 / 掉落 `scripts/raid_items.gd`

物品 = 可直接存 JSON 的字典（`:3-13`）：`gear 法宝{fx,amt}` / `pill 丹{grade, realm | min_realm, exp, heal}` / `key 破境丹{to}` / `frag 残片{to}` / `herb 灵草{region}` / `mat 灵材{region}(占 2 格)` / `tool 符箓{use: rune|reveal}`。

### 造物品
| 函数 | 行 | 备注 |
|---|---|---|
| `gear(tier, idx, value?)` / `rand_gear(tier, rng)` | :78 / :86 | 5 品阶 × 4 件（攻 / 守 / 识 / 养），数值 `FX_AMT` :25 |
| `rpill(realm, grade)` | :95 | 本境丹（只有正处在该境界能服）；价按 `REGION_TAG_BAND` 算 |
| `overlord(min_realm)` | :107 | 霸主精魄（境界 ≥ min_realm 可服），金色 |
| `heal_pill()` | :128 | 回春丹（气血 60） |
| `key(to)` / `frag(to)` | :177 / :183 | 破境丹 / 残片（3 片合 1，`Prog.FRAG_N`） |
| `herb(region)` / `mat(region)` | :189 / :194 | **region 夹在 0..4**（`:190`, `:195`） |
| `tool("rune"/"reveal")` | :199 | 破界符 / 寻宝符 |
| `roll(level, n, rng, bonus, depth, pill_realm)` | :210 | 一次掉落：破境丹 0.6%+0.6%×bonus → 符 7% → 丹 ~27%（三成回春丹）→ 法宝 32% → 灵材 18% → 灵草 16%。**`ri = clampi(level, 0, 4)`（`:212`）** |
| `fx_total(gear_list)` | :240 | 法宝被动合计（守 ≤60%、攻 ≤80%） |
| `pill_exp_now(it, realm?)` / `lock_text(it)` / `is_xp_pill(it)` | :164 / :144 / :133 | 服丹药力 / 境界锁文字 |
| `desc / badge / icon_name / tier_word` | :265 / :296 / :317 / :155 | 界面文字 / 图标名 |

### 坊市 / 丹房
* `shop()`（`:333`）：回春丹 60、炼气 / 筑基下品本境丹 120 / 380、寻宝符 160、破界符 520、凡品法宝 ×4 各 180、灵器法宝 ×4 各 900、筑基丹 300 / 降尘丹 1200（`Prog.SHOP_KEY`，`progression.gd:329`）。**顺序固定，abode_ui 按下标取货**——修仙版坊市也应按下标或直接把 good 字典传给 `Profile.buy`。
* 卖价 = 物品自己的 `value`（`Profile.sell` 原价，没有折扣）。
* `recipes()`（`:360`）：回春丹（灵参 + 10）、五味灵草各炼一种下品本境丹（境界 = `Prog.herb_pill_realm(t, 存档境界)`，费用 `PILL_CRAFT_COST` :46）、破境丹（3 残片 + `KEY_CRAFT_COST`）、灵田中品丹方（`farm_data.gd:129`，灵草 + 灵果 + 2 倍费用）。
* 服丹：`Prog.pill_use_err(it, realm)`（`progression.gd:259`）→ `Prog.profile_room()`（`:406`，≤0 别扣丹）→ `Prog.eat_pill(Items.pill_exp_now(it))`（`:448`）。大厅一键服丹在 `hall_pills.gd:183 eat_all`。

### 灵田（hub_hall.gd:186 `_build_farm` 被注释掉，恢复即可，经济侧不用改）
* `FarmData.harvest_items(plant, rng)`（`farm_data.gd:88`）→ 五味灵草 = `Items.herb(tier)`，灵果 = `fruit(name)`（kind herb，带 `fruit: true`）。
* 收获进仓库：`farm_plots.gd:267-282`（`Profile.stash_fits` + `stash().append` + `Profile.save()`），存档 `data()["farm"]`。
* 种子按境界解锁（`PLANTS[*].realm`，`farm_data.gd:21-38`），田块数 `FIELD_REALM`（`:47`）。

---

## 3. 数值中枢 `scripts/progression.gd`（Prog）

* 修为：`LV_PER_REALM 3`、`REALMS 8`、`xp_need(lv)`（`:45`）、`top_lv(realm)`（`:64`）、`at_cap`（`:68`）、`add_xp`（`:110`）、瓶颈结转 `carry_over / overflow_cap`（`:79-94`）、`profile_add_xp(v)`（`:389`）、`profile_at_cap()`（`:399`）。
* **区域境界档**（Hammer「一块区域一个等级」）：
  * `DEPTH_LV = [4,4,4,4,8]`（`:138`）、`REGION_REALM_MAX = [1,2,3,4,7]`（`:139`）、`REGION_TAG_BAND = [[0,1],[2,2],[3,3],[4,4],[5,7]]`（`:143`）、各区基础等级 `Data.REGIONS[ri]["lv"]` = 1 / 7 / 10 / 13 / 16（`raid_data.gd:49-84`）。
  * `depth_at(ri, x, z)`（`:146`，草原按出生点半径 480，四扇区按 R0→巢穴 1020 米）
  * `mob_level(ri, depth)`（`:155`）= 区域 lv + round(depth × DEPTH_LV)
  * `mob_tag(ri, lv)`（`:161`）= realm_of(lv) 夹进该区的档
  * `lair_tag(ri)`（`:167`）= `frag_to(ri) - 1`；`boss_level(t, want)`（`:172`）夹在档 t 的三级
  * `pill_realm_at(ri, depth)`（`:183`）= 当地怪的档 → 掉的本境丹境界
  * `herb_pill_realm(t, realm)`（`:177`）丹房 / 灵田
  * `value_mult(depth)` = 1 + 0.8·depth（`:192`）；`DEPTH_LUCK 1.0`（`:189`）
* 心得：`insight(mob_lv, k, ri)`（`:213`，`KILL_BASE 9.07 × 1.19^(lv-1) × k × XP_SCALE[档]`）、`insight_cap(realm)`（`:222`，800 只）。
* 丹：`pill_exp(realm, grade)`（`:247`）、`overlord_exp`（`:254`）、`GRADE_TABLE` 按深度插值（`:242`，`roll_grade` `:289`）、`OVERLORD_P = [1,1,1,0.6,0.4,0.3,0.25,0.25]`（`:236`）。
* 突破：`BREAK_COST`（`:326`）、`break_cost(to)`（`:332`）、`KEY_CRAFT_COST`（`:327`）、`FRAG_N 3`、渡劫在 `hub_hall.gd:1715-1820`（洞府阵台）和 `raid_manager.gd:531-640`（局内）。
* 破境丹掉落：`KEY_P 0.006 / KEY_PB 0.006 / VAULT_KEY 0.15`（`:338-340`）、`REGION_KEYS`（`:342`）、`roll_key_to`（`:345`）、`frag_to`（`:365`）。
* 天道压制：只剩心得 ×0.25（`SUPPRESS_GAIN` `:380`，`suppress_gap` `:383`）；带人闸 `raid_manager.gd:435-443`。

## 4. 战斗数值 `scripts/combat_stats.gd`（CS）

* 量级曲线 `G(lv)`（`:36`）；主角光身 `atk/hp/def = 1000/2500/500 × G`（`:54-63`）。
* 怪：`mob_scale(ri, lv, k)`（`:78`）、`mob_s_hp`（`:84`）、`mob_s_atk`（`:88`）——**只看 (区域, 等级)**，联机木偶两边现算，一致。
* 生怪公式 `raid_manager.gd:1533-1559 _spawn_mob(def_idx, ri, pos, elite, lvl, hp_k)`：
  `hp_max = (BOSS_HP 70 | SHAPE_BASE血) × def.hp × HP_CONV × mob_s_hp(ri, lv) × (精英 2.5) × hp_k`；
  `atk = (BOSS_DMG 10 | SHAPE_BASE攻) × def.atk × MOB_DMG 0.8 × ATK_CONV × mob_s_atk(ri, lv) × (精英 1.5)`；
  `xp_k = 首领 14 | 体型系数 × (精英 3)`。`def_idx` 是 `Data.MOBS` 的下标（联机按它建木偶，`raid_manager.gd:656`）。
* 主角出手 `CS.raid_hit(d, realm, lv, gear_atk, s_def)`（`:115`）= d / base(realm) × atk(lv) × 法宝攻 × 防御系数；挨打 `CS.to_bar`（`:105`）。
* PvP：`pvp_hit / pvp_guard / pvp_cap_k`（`:232-248`），封顶 22 / 30 / 25（`:256-258`）。`heroes_on`（`:228`）为 true 时**抹掉境界差**——主干要关掉（见第 7 节）。
* 战力 `CS.power(realm, lv, Items.fx_total(gear))`（`:303`）——修仙版备战页的「战力值」用它，替代 `meta_kit.gd` 的 ex 战力。

---

## 5. 新图的区域档怎么定（建议）

### 5.1 方案：新开 ri 5 / ri 6（推荐）

| | 沙海古墟 desert（ri 5，较易） | 天工秘所 lab（ri 6，较难） |
|---|---|---|
| 进入门槛 | 存档境界 ≥ 3（元婴） | 存档境界 ≥ 3（元婴），门上写「建议化神」 |
| `Data.REGIONS[ri]["lv"]` | 10 | 13 |
| `DEPTH_LV` | 5（lv 10 → 15） | 8（lv 13 → 21） |
| `REGION_TAG_BAND` | [3, 4]（元婴~化神） | [4, 6]（化神~合体） |
| `REGION_REALM_MAX` | 4 | 6 |
| `REGION_KEYS` | {4: 0.7, 5: 0.3} → frag_to 4（化神丹残片），lair_tag 3 | {5: 0.65, 6: 0.35} → frag_to 5（炼虚丹残片），lair_tag 4 |
| 掉落借的老区域 `LOOT_REGION` | 3（天山雪莲 / 阴冥石 / 品阶运气 3） | 4（幽冥彼岸花 / 古魔残骨 / 运气 4） |
| 难度加成 `ZONE_HP_K / ZONE_ATK_K` | 1.25 / 1.2 | 1.45 / 1.35 |
| 回报加成 `ZONE_LOOT_BONUS / ZONE_VALUE_K / ZONE_GAIN` | +0.3 / ×1.25 / 心得 ×1.2 | +0.5 / ×1.4 / 心得 ×1.35 |

理由：大世界里元婴去血色禁地（档 [3,3]）、化神去云梦山（[4,4]）、炼虚+去坠魔谷（[5,7]）。两张新图各覆盖「刚进门的境界 + 下一个境界」，深处 / 地下 / 首领是高一档，比同档的大世界区域更硬（加成）、回报也更好；天工秘所比沙海高一档。门槛同为元婴（用户原话），但元婴进天工秘所会遇到化神档的怪（新曲线高一档「一击即倒」，`raid_manager.gd:372-374` 的越档提示照旧会弹）——等于天然的「难的那张」。加成数是第一版，必须用 `_tasks/numbers_sim/life_sim.gd` 和 `--raid-pace` 再校。

**门槛检查**：`Profile.realm() >= ZONE_MIN_REALM`（3）。放在 `main.gd:1116 _on_hub_gate`（`gate_level(i)` 为 desert / lab 时先判，不够就 toast「需元婴期方可入境」并 return），hub_hall.gd:70-75 门的 `sub` 改成「元婴可入」。注意 `boot_realm()` 在自检里恒为 0（`raid_profile.gd:291`），自检要先 `Profile.data()["realm"] = 3`。

### 5.2 要改的地方（全部是一两行）
* progression.gd：加 `const REGION_N := 7`；`DEPTH_LV` `:138`、`REGION_REALM_MAX` `:139`、`REGION_TAG_BAND` `:143`、`REGION_KEYS` `:342` 各补两项；`clampi(…, 0, 4)` 改 `REGION_N - 1`：`:156`、`:162`、`:346`、`:366`、`:384`（`:178` 是灵草品阶，保持 0..4）。加 `LOOT_REGION := [0,1,2,3,4,3,4]` 和 `static func loot_region(ri)`；`depth_at`（`:146`）对 ri ≥ 5 走新图的深度函数（见 5.3）。
* raid_items.gd `roll`（`:210-234`）：`ri` 夹到 `REGION_N - 1`（`:212`），**`Data.roll_tier` / `mat` / `herb` 改用 `Prog.loot_region(ri)`**（否则 ri 5 的品阶运气 = 5，比坠魔谷还肥；herb/mat 会被夹成坠魔谷的）；丹的境界、破境丹照旧用 ri。
* raid_data.gd：`REGIONS` 补 [5] [6]（name / sub / realm / lv / mobs / boss + 视觉字段，raid_hud.gd:666 会读 `Data.REGIONS[mgr.region]`）、`LOOK` 补两项；`MOBS` 末尾追加新图的怪（见 5.4），**别插在中间**（老下标 0..14 是联机协议的一部分）。`region_weights`（`:286`）只返回 5 项不动——大世界永远落不进 5 / 6。
* raid_manager.gd：`:336`、`:341`、`:346`、`:436` 的 `clampi(ri, 0, 4)` 改上限；新图里 `region` / `here_ri` 要由关卡钉死（不能 `Data.region_at(pos)`，新图坐标在 0 附近会算成草原）；`_spawn_mob` 乘上 `ZONE_HP_K / ZONE_ATK_K`（hp 已有 `hp_k` 参数，atk 要加一个），**木偶那边要用同一个倍数**（按 region 查表，别从本地状态读）。
* raid_search.gd：`_build` 里 `Items.HERB_MODELS[ri]`（`:363`）、`URN_MODELS`、`_finish` 的 `Items.herb(ri …)`（`:240`）改用 `loot_region(ri)`；`COUNTS`（`:36`）/ `_place`（`:56`）新图不用，另加一个 `place_from(boxes, ri)` 按 map_def 的箱子位置摆点。
* raid_camps.gd：`P` / `RESPAWN`（`:25-26`）按 ri 取，新图走 map_def 自己的刷怪点（camps 子系统的事），复活时间用 75 秒同大世界。

（退路方案：不加 ri，沙海直接借 ri 2、天工借 ri 3，表一行不改，只加 ZONE 倍数。代价：两张图只有一个档、炼虚往上进去全被天道压制、首领残片和血色 / 云梦重复。不推荐。）

### 5.3 新图的「深度」
大世界的深度是离中心 / 巢穴的半径。新图建议在 map_def.gd 里加一个纯函数 `depth(id, pos)`，由 `Prog.depth_at` 对 ri ≥ 5 运行时 load 调用（位置决定，联机两边一致）：
* 地面：离最近出生点的距离 / 参考半径（沙海 260 米、天工 300 米），夹 0 ~ 0.8；
* 地下层（`map_def.layer_at(p) == "cavern"`，`map_def.gd:645`）：+0.25；
* 钥匙房、首领场地（`map_def` 的 key_rooms / areas kind=boss）：1.0；
* 天工秘所夜里（尸潮）：+0.15（只影响品质 / 价值，不影响怪等级的话就别加进 mob_level，避免昼夜切换时同一只怪两边等级不同）。

### 5.4 新图的怪（追加进 Data.MOBS，老规格）
`ex_mobs.gd:41-` 的 def 已经是 raid_mob 吃的形状（name / shape / spd / size / ranged / model / elite_model / cols），只要把 `hp / atk` 换成老倍率、去掉 ex 的点数字段（`HP_DESERT` 等，`ex_mobs.gd:15-27` 不再用）：

| ex id | shape | 建议 hp / atk 倍率 | 备注 |
|---|---|---|---|
| wolf_sand 沙漠狼 | beast | 1.0 / 1.1 | |
| scorpion 毒尾蝎 | beast | 1.2 / 1.2 | 同血线毒蝎 |
| sand_guard 沙灵守卫 | brute | 1.0 / 1.1 | ex 的 big ×2 不要（brute 底血已是 100） |
| sand_raider 沙匪 | brute, ranged | 0.9 / 1.1 | |
| zombie 尸傀 | brute | 1.0 / 1.1 | |
| mech_claw 钳击兵 | brute | 1.0 / 1.2 | |
| mech_gunner 炮击兵 | brute, ranged | 0.9 / 1.2 | |
| gel_mutant 凝胶怪 | beast, 只做精英 | 1.3 / 1.3 | |

首领（`boss: true`，hp 倍率 × `BOSS_HP 70`，同大世界 14~24 的量级）：凌幽 22 / 绛罗 20 / 沙渊巨虫 28（祭台召唤）；凌影 24（夜里 hp_k 1.9）/ 电鞭铁卫 18 / 冰僵铁卫 18 / 铁穹双卫各 14。`REGIONS[5]["boss"]` = 凌幽、`REGIONS[6]["boss"]` = 凌影（各图的「巢穴首领」），其余当「固定点的游荡首领」。

### 5.5 首领掉落（老规则，`raid_manager.gd:1875-1897`）
* 巢穴首领（凌幽 / 凌影）：`_loot(ri, 5, 1.3, dep, tag)` + `Items.frag(Prog.frag_to(ri))`（沙海 = 化神丹残片、天工 = 炼虚丹残片）+ 按 `OVERLORD_P[lair_tag]` 掉 `Items.overlord(lair_tag)`（沙海 元婴期霸主精魄 60%、天工 化神期 40%）；十分钟后重新镇守（同大世界 `back`）。
* 其他首领：`_loot(ri, 3, 0.8, dep, tag)`（同游荡首领）；召唤型 / 双首领各 4 件、bonus 1.1，双首领只在第二只倒下时多给一片残片。
* 精英：`_loot(ri, 2, 0.5, dep, tag)`；小怪 `KILL_DROP` 概率 1 件。
* ex 的 `BOSS_TABLES / DA_BOSSES / XIANYU_BOSS / KEY_P_BOSS`（`ex_data.gd:89, 108, 119, 907`）全部不用。

---

## 6. 新图的搜点该出什么（老表）

map_def 的箱子 kind（`map_def.gd:325-366`、`:569-606`、钥匙房 `:530-543` / `:610-616`）对到 raid_search 的老 KINDS（`raid_search.gd:28-34`）：

| map_def 箱子 | 老搜点 | 读条 / 件数 / bonus | 出什么（`raid_search._finish`，`:225-252`） |
|---|---|---|---|
| supply 物资箱（~50%） | jar 藏物陶罐 | 1.4 s / 1~2 / 0 | `Items.roll(ri, n, rng, 0, depth, pr)` |
| weapon 武器箱（~30%） | grave 古修坟冢 | 3.0 s / 2~3 / 0.5 | 同上（可选：法宝权重翻倍，加一个 `Items.roll` 的 kind 偏好参数） |
| med 医疗箱（~20%） | herb 灵药圃 | 2.4 s / 2~3 / 0 | 当地灵草（`loot_region`，12% 高一阶）+ 20% 一颗本境丹 |
| 钥匙房里的箱子 | vault 禁制宝库 | 9 s / 4~5 / 1.4 | `Items.roll` + `VAULT_KEY` 15% 送破境丹；破禁亮光柱、引一拨守卫（`_vault_alarm` `:214`）——**代替「禁室玉钥」开门**（老经济里没有钥匙物品） |
| 金字塔各层转角、斗场看台、首领场地边 | urn 宗门宝罐 | 4.5 s / 3~4 / 1.0 | `Items.roll`，深度按 1.0 |

* 丹的境界 = `Prog.pill_realm_at(ri, depth)`：沙海浅处元婴丹、深处 / 地下化神丹；天工浅处化神丹、深处炼虚~合体丹。
* 价值 × `Prog.value_mult(depth)`（`raid_manager.gd:1911 site_loot`）再 × ZONE_VALUE_K。
* 刷新：jar / herb / grave 480 s，vault / urn 900 s（`raid_search.gd:41`，替代 ex 的 `BOX_CD 180 / KEY_ROOM_T 900`）。
* 天工师营救（ex_doctor）：ex 给 100 万灵石 + 仙玉，主干没有这个量级。建议改成一只 urn 级的「天工遗藏」（3 件 bonus 1.0）或干脆不做。
* ex 的售卖物 / 命牌 / 护宝符 / 强心丹 / 仓库凭证 / 仙玉 / 兵刃 / 法衣 / 耐久修理在主干上全部没有对应物，不保留。

---

## 7. 英雄的数值（和 C_heroes 报告对齐）

* `player.gd:440-500 set_hero(id)`：现在 `realm_idx = HeroDefs.TIER`（`hero_defs.gd:37`，=2 结丹）、`CS.heroes_on = id != ""`（`player.gd:464`）。主干改成：保留玩家自己的 `realm_idx`（Profile.realm / 大厅里切的境界），只用 hero_def 覆盖外观类字段（lines / col_a / col_b / style / motes / boost / rise / swords、art、fly_speed、blink）；**不覆盖 `dmg` / `mp`**（三个 def 的 `realm` 覆盖里现在本来就没有 dmg，`def_*.gd:132/158/198`）；`CS.heroes_on` 恒 false（或整个删掉，`combat_stats.gd:228-248`，`awaken_fx.gd:153/197` 也读它，要换成看 `player.hero_id != ""`）。
* kit 出手 = `units(u) = player.air._base() × u`（`kit_base.gd:257-258`）→ `realm["dmg"]`（`air_melee.gd:614-615`）→ 大世界 `CS.raid_hit` 除掉 `base(realm)` 再乘 `atk(lv)`；PvP 走 `CS.pvp_hit` 按境界差。所以**数值自动跟境界走**，不用改 kit。
* 「不做强弱」= 三个 kit 的每秒招式单位要对齐（技能倍率之间的平衡是英雄子系统的活）；可以用 `--pace-combat` 量三位英雄在同境界的 DPS。
* 风险：英雄档原来「空战一开局就有」靠的是钉成结丹；按真实境界后，炼气 / 筑基的英雄能不能用空战技能要另定（terrain-movement-rules：炼气也能飞，但 Realm.COMBAT / air 招式表按境界分档）。

---

## 8. 修仙版 备战 / 坊市 / 段位 的后端对照

这三页现在全走 ExProfile / ExData（meta_prep.gd:16-19、meta_shop.gd:11-13、meta_rank.gd:10-11）。建议写一层 `scripts/xiu_meta_api.gd`（纯 static，转调 Profile / Items / Prog / CS），三页只换数据源、保留外壳和动画：

**备战（meta_prep）**
* 左边装备栏：左列「兵刃 + 三个法宝」→ 兵刃格只显示英雄自带兵器（不可换），三格 = `Profile.gear()`（`GEAR_SLOTS 3`）；右列四格（冠 / 衣 / 护腿 / 履）→ 改成随身四格 `Profile.carry()`（`CARRY_SLOTS 4`）。储物戒另起一条（`ring() / ring_cap() / upgrade_ring()`）。
* 中间「背包 / 仓库」两段 → 「仓库 / 储物戒」（局外没有背包）；筛选改成 全部 / 法宝 / 丹药 / 破境丹 / 灵草灵材 / 符箓（`Items.KIND_NAMES` `:20`）。
* 动作：穿戴 `equip(i)`、卸下 `unequip(i)`、带上 `pack(i)`、放回 `unpack(i)`、入戒 `to_ring(i)` / `from_ring(i)`、卖出 `sell(i)`、一键卖 `sell_junk()`、服丹（`Prog.pill_use_err` + `Prog.eat_pill`，同 hall_pills）、领行囊 `take_kit()`。
* 战力：`CS.power(Profile.realm(), Profile.cult(realm)[0], Items.fx_total(Profile.gear()))`。
* 入境检查：`Profile.in_raid()` → `RAID_LOCK`；不再有「售卖物不能带入」。

**坊市（meta_shop）**
* 货架 = `Items.shop()`（分类：丹药 / 符箓 / 法宝 / 破境丹），买 `Profile.buy(good)`；黑市（仙玉）删掉；「出售」栏 = 仓库里所有东西，单卖 `Profile.sell(i)`、一键 `sell_junk()`。
* 丹房可以作为坊市里的一个分类：`Items.recipes()` + `Profile.can_craft / craft`。
* 价格单位全是灵石，量级几十到几千（不是 ex 的百万级），NumFmt 照用。

**段位（meta_rank）**
* 段位 = 境界 + 小等级：徽记按 `Profile.realm()`（8 档，配色 `Realm.LIST[r].col_b`），几粒 = 境界内第几级（`(lv-1) % 3 + 1`）；进度条 = 当前级 xp / `Prog.xp_need(lv)`，瓶颈时写「已满 · 结转 +X」（`Prog.profile_carry()`）+ 缺什么（破境丹 / `Prog.break_cost`）。
* 底下那条路 = 8 个境界（或 24 级），替代 `ExData.RANK_NAMES / RANK_NEED`（`ex_data.gd:933-934`）。
* 战绩卡：`data().stats` 的 raids / out / dead / best（+ 建议补的 kills），再加一张「战力」。晋升奖励一句删掉（没有仙玉）。

---

## 9. 主干要删 / 不再读的 ex 经济
`scripts/ex/ex_profile.gd`（user://xiuxian_ex_profile.json）、`ex_data.gd` 的经济部分（品质 / 兵刃 / 法衣 / 耐久 / 售卖物 / 仙玉 / 仓库凭证 / 段位表 / 掉落表 TABLES / POOLS）、extract_manager 的结算。`main.gd:798-799` 在开机时 load ex_profile，要去掉。`combat_stats.gd:226-248` 的英雄档开关。extraction-pvp 分支保留完整版。

## 10. 风险 / 待定
1. **两张图的档位和加成是第一版**，没跑 life_sim / `--raid-pace`，元婴进天工秘所可能完全打不动（这是有意的「难」，但要用户点头）。
2. 加 ri 5 / 6 会改联机里 `m.region` 的取值范围：老版本客户端收到 region 5 会越界——联机协议变了，要换包（pvp-fight-rules 记过同样的坑）。
3. `Data.MOBS` 只能追加；`_spawn_mob` 加 ZONE 倍数时木偶端必须同算，否则两边血量不一致。
4. 新图深度函数必须只看位置（不能看昼夜 / 人数），否则同一只怪两边等级 / 档不同。
5. ex 首领的特殊机制（巨虫祭台召唤、双首领、夜里狂潮）是关卡 / AI 层的事；经济侧只给掉落规则。召唤门槛 `SUMMON_MIN` 等是 ex 点数制，换成老数值后首领血量要按人数缩放（ex 有 `0.6 + 0.4·min(人数,4)/4`，老系统没有，联机多人打首领会偏快）。
6. 英雄按真实境界后，炼气 / 筑基能否用英雄的空战技能要定；`awaken_fx.gd:153/197` 读 `heroes_on`，关掉后觉醒配色逻辑会变。
7. 自检存档每次清空、境界 0：所有新图自检都要先把存档境界设到 3 以上。
