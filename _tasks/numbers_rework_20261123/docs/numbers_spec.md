# 数值 / 战力重构规格（2026-11-23，对标 Hammer）

隔离副本：`D:/GodotProjects/修仙游戏_iso_numbers`（只在这里改）。正式工作区 `D:/GodotProjects/修仙游戏` 有别的会话正在改（格斗专项：raid_manager / net / air_melee / air_moves / arena_duel / remote_player / touch_controls），**别去碰正式工作区**。
用户拍板（原话要点）：① 照搬 Hammer 的「曲线形状」，不照搬 309 级 / 16 品质；② 装备陨落会丢 → 主角自身成长要跟上怪，装备只是加成；③ PvP 用另一套平衡数值：每高一个境界多一点优势（+15~25%）、装备加成封顶、原有单下 / 连击封顶保留；④ 天道压制重构：去掉伤害压制（高境界回低区割草），保留收益打折；⑤ 修为丹的数值、吃法照 Hammer 的经验丹（精魄 / 霸主精魄）做，其它丹先不做；⑥ 战力对标 Hammer。节奏不变：life_sim 普通玩家约 15.9 小时到大乘。

背景调研（必读，按需看）：草稿目录 `C:/Users/CHENYA~1/AppData/Local/Temp/claude/31cb5b99151d1ce0/56892b15-dc20-4b69-bb00-518bf08dbf71/scratchpad/` 下 `map_combat.md`（战斗链路，行号）、`map_progression.md`（成长 / 丹 / 存档）、`map_display.md`（显示 / 字体）、`map_tests.md`（自检）、`map_hammer.md`（Hammer 公式）、`map_gaps.md`（漏项）。

---

## 1. 等级量级曲线 G(L)（主角和怪共用）

```
g = 1.374；J = 2.0；TAIL = 1.04
r(L) = clamp(floor((L-1)/3), 0, 7)
G(L) = g^(L-1) × J^r(L)            （L ≤ 24；每个境界 ×5.187，境内每级 ×1.374，突破那一级 ×2.75）
G(L) = G(24) × TAIL^(L-24)          （L > 24：大乘尾巴放缓，99 级 G ≈ 3.6e6，不会溢出 int64）
```
放在 `combat_stats.gd`：`static func G(lv: int) -> float`。

## 2. 主角属性（光身，Hammer 5:2:1）

```
CS.atk(lv) = ATK_K × G(lv)   ATK_K = 1000
CS.hp(lv)  = HP_K  × G(lv)   HP_K  = 2500
CS.def(lv) = DEF_K × G(lv)   DEF_K = 500
```
炼气1：血 2500 / 攻 1000 / 防 500；结丹1：6.73万 / 2.69万；化神1：181万 / 72.4万；大乘3（24 级）：4.77亿 / 1.91亿。
法宝「攻」「守」仍是百分比（攻封顶 +80% `GEAR_ATK_CAP`，守封顶 60%），**乘在公式外面**。主角的气血条仍是 0~100（几十处写死 100，不动）；玩家牌显示 `条 × CS.hp(lv) / 100` 的实数。

## 3. 怪的量级：同一条 G，按「区域境界档」打标签（Hammer 一块区域一个等级）

```
REGION_TAG_BAND = [[0,1], [2,2], [3,3], [4,4], [5,7]]   # 草原 炼气~筑基，黄枫谷 结丹，血色 元婴，云梦 化神，坠魔谷 炼虚~大乘
Prog.mob_tag(ri, lv) = clamp(realm_of(lv), band_lo, band_hi)
L0 = 3 × tag + 1
CS.mob_scale(ri, lv, k) = G(L0) × (1 + k·(lv−1)) / (1 + k·(L0−1))   # 档内按深度照旧线性；k = 0.25（血 / 防）或 0.2（攻）
```
lv > 24（坠魔谷巢穴首领 26 级）：L0 仍 = 3×tag+1、tag ≤ 7，线性那段照算即可（不会爆）。
- 怪血 = `hp0 × HP_CONV × mob_scale(ri, lv, 0.25) × 精英 2.5 × hp_k`，`HP_CONV = 2960 / 48 = 61.667`（hp0 = SHAPE_BASE 血 × 物种 hp，或首领 `BOSS_HP × 物种 hp`，同现在）。
- 怪攻（原始） = `at0 × MOB_DMG 0.8 × ATK_CONV × mob_scale(ri, lv, 0.2) × 精英 1.5`，`ATK_CONV = 736 / 9.6 = 76.667`。
- 怪防 = `MOB_DEF_K 100 × mob_scale(ri, lv, 0.2)`。
- 物种倍率、精英、首领出手 ×1.5 / 震地 ×2 / 远程 ×0.7 全在公式外面（线性）。
- 怪身上记 `m.scale_hp / m.scale_atk`（或一个 `m.scale` + `m.tag`），伤害公式要用。

## 4. 伤害公式（Hammer：dmg = 攻² / (攻 + 3.5·防)，倍率放公式外 → 等价于乘一个「防御系数」）

- **主角打怪**（PvE）：
  `dmg = 招式单位 × CS.atk(lv) × (1 + min(法宝攻, 0.8)) / (1 + 3.5 × MOB_DEF_K × S_m / CS.atk(lv))`
  = `单位 × 1000·G_p × (1+攻) / (1 + 0.35 · S_m / G_p)`，其中 `招式单位 = raw / CS.base(realm)`（`Realm.LIST.dmg` 不动）。
  同级 1 单位 = 740.7；同级兽（2960）4 下死（今天也是 4 下）。
- **怪打主角**：
  `实伤 = raw / (1 + 3.5 × CS.def(lv) / (A_NOM × S_m_atk))`，`A_NOM = 736`；`条上点 = 实伤 × 100 / CS.hp(lv) × (1 − min(守, 0.6))`。
  同级兽一下 8.7%（今天也是 8.7%）。
- 怪的防御系数**只能是 (区域, 等级, 精英, 首领) 的纯函数**：联机里打别人的怪木偶，出手方要能自己算出来（木偶有 region / lv / elite）。
- 手感（算过）：同境内主角每升一级打怪快约 1.35 倍；高一境打低一境 0.6 下、挨一下 0.4%；**低一境进高一境的区 43 下、一下掉 100%+**（Hammer 式的区域门槛）。

接入点：`raid_manager._spawn_mob`（血攻防）、`player_dmg`（改成知道目标：`m.dmg_in = player_dmg_vs.bind(m)`，签名 `func player_dmg_vs(d: float, m: Node) -> float`）、`to_player`（同理 `m.atk_out = to_player_from.bind(m)`）、`_on_puppet_hit`（木偶用自己的 region/lv 算 S_m）。`player_dmg(d, pvp)` / `to_player(d)` 旧签名保留给没有目标的老调用（按同级处理）。

## 5. 天道压制

- 删伤害压制：`sup_dmg_k()` 恒返回 1.0（或删掉乘子），`Prog.SUPPRESS_DMG` 注释标「已停用」。
- 保留心得打折 `SUPPRESS_GAIN 0.25`（`kill_exp`）。提示文案改：「天道压制：境界高出此地，心得 ×25%」；`raid_hud.gd` 右上那行改成显示心得倍率。
- 联机「带人」闸（map_gaps C1）：`net_mob_died` 分心得时，如果出手者（last_hitter 或主人）的境界高出该怪所在区域上限（`REGION_REALM_MAX`），分到的心得 × `SUPPRESS_GAIN`。

## 6. PvP（大世界真人互殴；擂台保持它自己那套 ARENA_*，不改）

```
PVP_UNIT = 9.0            # 一个招式单位打掉对方多少点气血条（同境界时，接近今天中段等级的实测）
PVP_REALM_ADV = 1.1       # 出手方每高一个境界 ×1.1（低则 ÷1.1）；双方对打的相对优势 ≈ +21%/境
PVP_REALM_CLAMP = 4       # 境界差最多按 4 档算
PVP_GEAR_ATK_CAP = 0.3    # PvP 里法宝「攻」最多 +30%（PvE 是 80%）
PVP_GUARD_CAP = 0.3       # PvP 里法宝「守」最多 30%（PvE 是 60%）
CS.pvp_hit(raw, my_realm, their_realm, gear_atk) = raw / base(my_realm) × PVP_UNIT × PVP_REALM_ADV^clamp(my−their, ±4) × (1 + min(gear_atk, 0.3))   # 条上点数
```
- 出手方 `RM.net_deal_hit`：算 `pvp_hit`（对方境界取木偶的 `realm_idx`），发出去的 dmg 改成**条上点数**；飘字显示 `点数 × CS.hp(对方 lv) / 100`（对方牌子上的实数口径）。
- 受击方 `RM.net_take_hit`：`from > 0`（真人）时**不再走 `to_player`**，只 `× (1 − min(守, 0.3))`，再 `_pvp_clamp`（22 / 30 / 25 照旧）。`from == 0`（别人的怪打我）照旧走 `to_player`（传的是怪的原始攻击，按我这边算；需要怪的量级 → 用 `src` 木偶的 region/lv）。
- 对波输 28 点、砸地 8 点等旁路（air_melee.gd）**本次不动**（那个文件格斗专项正在改），在报告里写明。

## 7. 战力（对标 Hammer `CalcCombatPower`）

```
CS.power(realm, lv, fx) -> float
  = ceil( (hp×10 + atk×25 + def×50) × (0.5 + 攻 + 守 + 0.2×养 + 0.05×识) )    # hp/atk/def 用光身 CS.hp/atk/def(lv)，不再乘 1.1^境界
```
炼气1 光身 3.75万；筑基1 19.4万；结丹1 101万；化神1 2716万；炼虚1 1.41亿；大乘3 71.6亿；满装 ×3.8。返回 float，显示用统一格式。

## 8. 修为（单位按 Hammer 的境界总量放大，节奏不变）

```
XP_SCALE = [1.227, 2.855, 12.146, 69.167, 392.71, 3345.6, 38097.8, 649363.4]   # 新总量 = Hammer 各境总量
xp_need(lv) = 旧公式 × XP_SCALE[realm_of(lv)]
```
新境界总量：炼气 3208 / 筑基 5.11万 / 结丹 79.8万 / 元婴 1245万 / 化神 1.94亿 / 炼虚 45.4亿 / 合体 1418亿 / 大乘 6.63万亿（= Hammer）。
所有修为来源按「来源所属的境界档」同乘 XP_SCALE：
- 心得：`Prog.insight(mob_lv, k, tag) = KILL_BASE × KILL_G^(lv−1) × k × XP_SCALE[tag]`（tag = 怪的区域境界档）。调用方都要给 tag：自己的怪 `m.tag`；`net_mob_died` 用 `Data.region_at(pos)` + `mob_tag`；AI 修士用它的区域；life_sim 用它算出的区域。心得上限 `insight_cap(realm) = insight(REALM_MOB_LV[realm], 1, realm) × KILL_CAP_N`。
- `REALM_MOB_LV = [2, 4, 8, 11, 14, 17, 20, 23]`（原 19 / 22 / 24 在新曲线下是跨境怪）。
- 打坐：`med_rate(realm) = MED_RATE[realm] × XP_SCALE[realm]`（离线自动跟）。
- 渡劫奖励按 `xp_need` 比例，自动跟。
- 大乘 24 级以后 `xp_need` 照旧公式（×1.4/级）× XP_SCALE[7]，都是 float，不会溢出；显示要到 万亿 / 兆。
- 草原深度：`MEADOW_DEPTH_R 380 → 480`（让炼气的出生圈 110~300 米里全是炼气档的怪：lv4 筑基档从 300 米起）。

## 9. 瓶颈：照 Hammer 溢出结转

- `Prog.add_xp`：到本境界顶级后**照收**，最多存到 `xp_need(top) + realm_total(realm+1)`（多出一整个下一境界为止，防一次屯几境）。`at_cap` 不变（`xp >= xp_need(top)`）。大乘照旧无瓶颈。
- 渡劫成功：`余 = xp − xp_need(top)` → 新境界起点 `add_xp(余 + 完美奖励)`（raid_manager `_on_trib_done`、hub_hall `_on_break_done`、life_sim `_break`）。失败：`xp −= xp_need(top) × 0.5`（不再直接覆盖成一半；不低于 0）。
- 去掉「瓶颈不许服丹」的拦截；提示改「修为已满，突破后结转」。心得撤离结算同样不截断（结算页「余下心得散去」那行删掉或改成「结转」）。

## 10. 修为丹（照 Hammer 精魄 / 霸主精魄）

**本境丹**（≈ 普通精魄）：每个境界一种，**只有正处在该境界才能服**（提示「处于X期时才可服用」）。
```
PILL_NAMES  = ["黄龙丹", "聚灵丹", "养元丹", "凝魂丹", "培婴丹", "玄元丹", "合道丹", "太清丹"]   # 炼气 … 大乘（名字不能和破境丹 / 灵草 / 灵材 / 灵果撞名）
PILL_BASE   = [120, 160, 200, 400, 860, 1500, 2100, 2700]   # 下品，旧单位（第一版，life_sim 再校）
pill_exp(realm, grade) = PILL_BASE[realm] × XP_SCALE[realm] × GRADE_MULT[grade]   # 品质 下 / 中 / 上 / 极 ×1/2/4/8 照旧，按深度掷
REALM_TIER  = [0, 0, 1, 2, 3, 4, 4, 4]   # 境界 → 颜色 / 图标品阶（icon_pill_0..4 够用）
```
- 掉落出哪个境界的丹 = 掉落处的怪的境界档：`Prog.pill_realm_at(ri, depth) = mob_tag(ri, mob_level(ri, depth))`（小怪、精英、首领遗藏、搜点、宝库都按掉落点）。
- 物品字典：`{"kind":"pill","name":品质+丹名,"tier":REALM_TIER[r],"grade":g,"realm":r,"exp":(显示用),"heal":25~35,"value":...}`；`Items.rpill(realm, grade)` 新增；旧的 `Items.pill(tier, grade)` 保留签名、把 tier 映射到境界 `[0,2,3,4,5]` 后转 `rpill`（防旧调用炸）。
- 卖价按境界：`value = round(tier_value(REALM_TIER[r]) × 0.4 × (1 + 0.5 × (r − 该档区域的最低境界)) × GRADE_MULT[g])`（大意：同品阶里高境界的丹贵一点）。
- `Items.pill_exp_now(it)`：有 `min_realm` → 霸主值；有 `realm` → `pill_exp(realm, grade)`；都没有（迁移前的老丹）→ 当成当前境界的本境丹。

**霸主丹**（≈ 霸主精魄）：巢穴首领遗藏里按 `OVERLORD_P`（第一版 0.35）多掉一颗；**境界 ≥ min_realm 能服**（「达到X期后才可服用」）；`min_realm` = 巢穴首领所在位置的境界档；药力 = `realm_total(min_realm) × OVERLORD_PCT[min_realm]`，`OVERLORD_PCT = [0.05, 0.05, 0.055, 0.06, 0.065, 0.07, 0.072, 0.075]`。名字 `X期霸主精魄`（如「筑基霸主精魄」），tier = REALM_TIER[min_realm]、grade 3（金色）。

**吃法（照 Hammer）**：没有丹毒、没有打坐服丹加成（`TOX_*`、`MED_PILL` 停用，存档字段留着不读）；一键服丹 = 把仓库里所有**能服**的修为丹（本境界的 + 霸主丹）从大到小一摞吃完（可以保留很短的连吃动画），瓶颈时照样能吃（溢出结转）；局内背包里不能服的丹不给「服用」按钮（或灰掉加说明）。
**丹房 / 灵田**：丹房的修为丹方改成按境界出（`for r in 8` 或只列本境界附近的几条；灵草用该境界所在区域的 `HERBS`，`REALM_REGION = [0,0,1,2,3,4,4,4]`，炼制费按境界递增）；`farm_data.recipes()` 不再按 `Items.PILLS.size()` 循环（固定 5 种灵植 tier t → 出 `rpill(t, 1)`，t = 0..4 = 炼气..化神）。坊市卖 `rpill(0,0)`、`rpill(1,0)`（价格照旧 120 / 380）。

**老存档（raid_profile VER 3 迁移）**：`xp × XP_SCALE[realm_of(lv)]`（每级需求等比放大，进度比例不变）；仓库 / 随身 / 储物戒 / 未结算局里的老修为丹（没有 `realm`）→ 换成**当前存档境界**、同品质的本境丹；`_fix_item` 整数字段加 `realm`、`min_realm`；`stats.best` 不动。

## 11. 显示（大数）

- 新建 `scripts/num_fmt.gd`（无 class_name）：`static func fmt(v: float) -> String`：< 1 万整数；否则 4 位有效数字 + 万 / 亿 / 万亿（不用「兆」：随包字体里没有）；负数带负号；不出现「10000万」这种进位错误。`Prog.short_num` 改成转调它。
- 伤害飘字 `vfx.gd` 的 `damage_number`、连击伤害（`hud.gd`，且改成累加实伤）、玩家牌气血 / 战力（`player_plate.gd`，气血文本框 76 px 放不下「12.3万/12.3万」→ 只显示当前值或缩字号 / 加宽）、服丹回血「气血 +N」显示实数、心得 / 修为 / 打坐每息的 `%.1f` 都换成 fmt。`warmup.gd` 预热的字形加上「万亿.」。
- 字体：新字（丹名、「霸主精魄」等）跑 `python -I _tasks/ui_kit/font_check.py` 看缺不缺；缺的话在隔离副本里 `--patch`，部署时一起带上补字字体。

## 12. AI 修士 / AI 道友（手写的数要换到新曲线）

- AI 修士：当成同区同级的「怪」：`S = mob_scale(ri, f.lv, …)`；气血 `260 × HP_CONV × S_hp`；打怪 `prey_dmg = 0.6 × 740.7 × S_atk`（≈ 同级主角一招单位伤害的六成）；打主角的 `dmg_mul = RIVAL_DMG 0.42 × k_rel × (1−守)`，`k_rel = (S/G_p) × (1 + 2.378) / (1 + 2.378 × G_p / S)`（同级 = 1）；它的心得 `add_insight(f.lv, 5.0, …, tag)`；外观档位 `look_i` 按区域档（`tag`）给。
- AI 道友：气血 `ALLY_HP_UNITS 39.6 × A_NOM × G(lv)`（同级被兽打 72 下倒，同今天），`set_level` 时按比例更新 `hp_max / hp`；打怪 `prey_dmg = 0.6 × 740.7 × G(lv)`（大脑再 × DMG_K）。

## 13. 自检 / 校准工具

- `_tasks/numbers_sim/combat_table.gd` 换成新公式、调同一套 CS 函数（别自己复刻）；PvP 段重写。
- `raid_pace_test.gd`：木桩「打不死」血量 1e7 → 1e30；`--pace-combat` 的「单位」定义改成「对同级、零防御口径」或直接量几下打死；新增 `--pace-realms=0,1,..,7`：每个境界在自己的区域、自己档的深度（怪 ≈ `REALM_MOB_LV[r]`）、lv = 3r+2 量杀怪速度，输出 `[pace-json]` 带 `realm` 字段；假主角只打 `mob_tag ≤ 自己境界` 的怪。
- `life_sim.gd`：按境界读杀怪速度（有 `realm` 字段时按境界，没有按区域）；怪等级按 `REALM_MOB_LV` ± 档内小浮动；丹改成带 realm / min_realm 的列表、服丹按境界锁、霸主丹；溢出结转；去掉丹毒；`--o=` 加 `ovl:`（霸主掉率）、`ovp:`（霸主比例）。目标：普通玩家约 15.9 小时到大乘，休闲 ~16.8、肝帝 ~14.8；来源占比大致 心得 36% / 丹 44% / 打坐+离线 20%。
- 写死小数的自检逐个过（map_tests.md / map_progression.md §9）：`add_exp(1e9)`、`add_exp(1e6)`、`gain(5) 应为 0`（溢出后会变）、`pill(0)` 一键服丹等。

---

# v2 修订（三路评审之后；和上文冲突时以这里为准）

评审原文：草稿目录 `critic_math.md`、`critic_code.md`、`critic_ux.md`。

## A. 首领的境界档 / 等级（评审一致指出：+N 级会跨档 ×5）
- 首领一律「先定档、再夹等级」，档、等级都只由 (区域, 当地等级, 是不是巢穴) 决定（纯函数）：
  - **巢穴首领**：`t = Prog.lair_tag(ri) = Prog.frag_to(ri) - 1` → 草原 0（炼气）/ 黄枫谷 2 / 血色 3 / 云梦 4 / 坠魔谷 5（炼虚）。等级 `Prog.boss_level(t, 当地等级 + 2) = clampi(当地等级 + 2, 3t + 1, 3t + 3)`（草原 3 级、坠魔谷 18 级）。坠魔谷巢穴四周 110 米没有刷怪点，炼虚飞进去打得到。巢穴碎片 `frag_to` 不变（正好是打得动它的人要的那颗）。霸主精魄 `min_realm = t`。
  - **天地异动 / 游荡首领**：`t = mob_tag(ri, 当地等级)`，等级 `clampi(当地等级 + 1, 3t+1, 3t+3)`。
  - 这样任何怪（含首领）的档都 = `Prog.mob_tag(ri, m.lv)`：等级已经夹在档里了，木偶两边算出来一样。
- `combat_table.gd` 的首领检查按真实巢穴位置算等级。

## B. 心得：必须带区域，不留默认值
- `Prog.insight(mob_lv: int, k: float, ri: int)`：函数里自己 `mob_tag(ri, mob_lv)`。`RM.kill_exp(mob_lv, k, ri)`、`RM.add_insight(mob_lv, k, from, kind, ri)`（ri 必填，放在最后但所有调用都显式传；没有现成区域的用 `here_ri` / 当前区域）。`net_mob_died` 用木偶的 `region`（erase 之前取），没有木偶时 `Data.region_at(pos.x, pos.z)`。life_sim 的 `_ins` 直接调 `Prog.insight`（只叠 kb / kg 覆盖）。

## C. 瓶颈结转按「境界单位」换算（不然跨境要亏 57%~94%）
- `Prog.carry_k(realm) = XP_SCALE[realm + 1] / XP_SCALE[realm]`。
- 上限：`overflow_cap(r) = xp_need(top) + realm_total(r + 1) / carry_k(r)`（存的是本境界单位）。
- 渡劫成功：`余 = (xp − xp_need(top)) × carry_k(r)` → 新境界起点 `add_xp(余 + 完美奖励)`；成功后要再调一次 `_cult_changed`（结转可能直接把新境界也灌满）。
- 渡劫失败：`xp = maxf(xp − xp_need(top) × 0.5, 0)`；raid 里失败后 60 秒内不自动再起劫（`_trib_hold` 计时），hub 照旧要玩家点。
- 溢出存满（`add_xp` 的 used == 0）时：服丹不扣丹，提示「修为已满，先去渡劫」。一键服丹 / 局内连服都要查。
- 显示：修为条满格时写「已满 · 结转 +X」（不用「溢」字，字体里没有）。

## D. PvP（评审：封顶把境界优势吃掉）
- `PVP_REALM_ADV = 1.08`（已改）；`_pvp_clamp` 的三道封顶（22 / 30 / 25 每秒）都 × `CS.pvp_cap_k(对方境界, 我的境界)`；「守」在封顶**之后**乘（`CS.pvp_guard`）。对方境界取 `_remote(from).realm_idx`。
- 出手方飘字 `CS.pvp_shown(pts, 我的 lv)`（按我打同级怪的口径）；擂台不动（另一个会话的文件，且它本来就是独立平衡）。
- 协议没有版本号：本次不改 net.gd（格斗专项正在改），报告里写明「新旧版本别混在一个局域网房间」。

## E. 丹药（评审）
- `pill_exp_now(it, realm := -1)`：有 `legacy_exp` → 它；有 `min_realm` → `overlord_exp`；有 `realm` → `pill_exp(realm, grade)`；都没有 → 当成 `realm` 参数（调用方传 Profile / 主角境界）的本境丹。
- 霸主精魄药力 `overlord_exp(r) = maxf(realm_total(r) × OVERLORD_PCT[r], pill_exp(r, 3) × 1.5)`；掉率按档 `OVERLORD_P = [1.0, 1.0, 1.0, 0.6, 0.4, 0.3, 0.25, 0.25]`（life_sim 再校）。价值（卖价）设成和极品本境丹同级（别被 `_swap_out` 当便宜货丢掉）。
- **老存档的丹保值**：VER 3 迁移把没有 `realm` 的老修为丹改成 `{"legacy_exp": PILL_EXP[t] × GRADE_MULT[g] × XP_SCALE[当前境界], "min_realm": 当前境界}`，名字前加「旧·」（不和新丹撞名），图标 / 颜色照旧。修为迁移用比例：`frac = xp / xp_need_v2(lv)`，`frac >= 1 − 1e-9` 时 `xp = xp_need(lv)`，否则 `frac × xp_need(lv)`。
- `Prog.tox()` 恒返回 0；所有「丹毒 / 药效」文案删掉（`raid_items.gd` desc、`hub_hall.gd` 打坐牌子、`hall_pills.gd`、`raid_manager.gd` 服丹飘字）。
- **丹房 / 灵田统一**：灵草 tier t（= 区域 t）炼出的修为丹境界 = `clampi(玩家当前境界, REGION_TAG_BAND[t])`（recipes() 每次刷新重算，读 `Profile.realm()`）；丹房、`farm_data.recipes()`、`farm_data.use_line()` 用同一张表（`Prog.herb_pill_realm(t, realm)`）。`farm_data` 不再按 `Items.PILLS.size()` 循环。
- 坊市：照旧卖炼气 / 筑基下品（新人解卡）。
- 仓库里修为丹叠格（`raid_profile.stacks()` 和 `abode_ui._stack_key` 加 pill，键含 name / realm / min_realm / grade）；一键出售也卖 `realm < 当前境界` 且没有 min_realm 的丹；背包满了 `_swap_out` 比价时能服的丹按 ×3 价值比。
- 一键服丹扫 仓库（照旧）；渡劫前（`_bottleneck`、hub `_break_missing`）如果仓库 / 随身还有本境界的丹，提示「还有 N 颗X期丹，突破后不能再服」。
- `PILL_BASE` 第一版保留，由 life_sim 校（评审给的方向：炼虚 / 合体按新的浅深度品质均值要大约 ×1.39 / ×1.27，再整体按普通玩家 ~15.9 小时收）。

## F. 草原 / 危险提示（新手）
- `meadow_level.gd` `_raid_spawn` 半径 `110 ~ 300` → `110 ~ 250`。
- 危险判断改成按档：`RM` 维护 `here_tag = Prog.mob_tag(here 区域, here 当地等级)`；区域题字「凶险」（`raid_manager.gd:~1180`）和信息牌朱砂色（`raid_hud.gd:~665`）条件改成 `here_tag > player.realm_idx`；`here_tag` 变高且高过自己时 toast 一次「此地妖兽已是X期，境界不足，一击即倒」（字都在字体里：妖 兽 已 是 期 境 界 不 足 一 击 即 倒——实现时 font_check 核一下）；换区重置。信息牌把「怪物 Lv.N」改成「妖兽 X期」。
- 新文案别用 易 / 毙 / 荐 / 溢 / 宁 / 兆 / 京（随包字体没有）。

## G. 显示补充
- 玩家牌：气血 ≥ 1 万时只写当前值（`NumFmt.fmt`），< 1 万照旧「当前/上限」；战力那一行数字用题字字体、单位（万 / 亿 / 万亿）拆成第二个 Label 用正文字体（题字字体没有「亿」）；`set_values` 的 pw 改 float。
- 战力变化反馈（Hammer）：升级、渡劫成功、换法宝时 toast「战力 7.08万 → 19.45万」（局内 `hud.toast`，主城用现有飘字）。
- 伤害飘字最少写 1（`maxf(v, 1)`），用 `NumFmt.fmt`；主城（木人 / 刀客 / 剑冢首领 / 斗法台陪练）的飘字**只改显示**：`dmg / CS.base(realm) × CS.unit_same(lv)`，扣血逻辑不动。擂台不动。
- 连击伤害：`RM` 里存 `dmg_ratio`（最近一次 `player_dmg_vs` 的 实伤 / raw），`hud.gd` 显示 `combo_dmg × dmg_ratio`（不改 air_melee.gd）。
- `warmup.gd` 预热的字形改成 `"0123456789.万亿+-"`。
- 物品说明的「气血 +25」写成「气血 +25%」（条上点数）；丹的角标「X期 +1.234万」。
- num_fmt：≥ 1e16 用科学计数（已改）。

## H. AI 修士 / 道友
- AI 修士（AirFoe，`region` 记在 meta 里）：所有「目标量级」都用一个 helper `RM._target_scale(t, k)`：Mob 读 `t.region` / `t.lv`，AirFoe 读 `t.get_meta("region", here_ri)` / `t.lv`，每次现算不缓存。主角打修士走 `player_dmg_vs.bind(f)`。外观档位 `look_i = mob_tag(ri, f.lv)`。
- AI 道友：`set_level` 加一个气血参数（按比例更新 `hp_max / hp`）；打 AI 修士别再借主角的 `dmg_in`（改成直接 `sim_damage` 式的实伤，量级同 prey_dmg）。

## I. 带人闸（简化版）
- 怪身上记 `meta "hi_realm"` = 打过它的远端玩家里最高的境界（`net_mob_take` 里用 `_remote(from).realm_idx` 更新）。我自己的怪死了（`_on_mob_died`）：如果 `hi_realm > REGION_REALM_MAX[怪的区域]` 且 `hi_realm > 我的境界` → 我的心得 × SUPPRESS_GAIN。别人的怪死了（`net_mob_died`）：用主人 `_remote(owner).realm_idx` 做同样判断。被打折时给一次 toast「同行道友境界高出此地，心得 ×25%」。

## J. 工具
- 自检木桩「打不死」血量用 `1.0e13`（不是 1e30：float 精度会吃掉小伤害）。
- 新探针开关叫 `--pace-byrealm`（`--pace-realms` 已被 `--pace-combat` 占用）：每个境界的第 1 / 2 / 3 级各量一次（`--pace-min` 默认 3），区域 = 该境界的区域（`[0,0,1,2,3,4,4,4]`），深度 = `(REALM_MOB_LV[r] − REGIONS[ri].lv) / DEPTH_LV[ri]`，假主角只打 `mob_tag ≤ 自己境界` 的怪、只打离起点 200 米内的；`[pace-json]` 带 `"by": "realm", "realm", "lv"`。
- life_sim：有 `by == "realm"` 的行就按 (境界, 境内第几级) 取杀怪速度（境内三级按各级修为占比加权或按当前级取），否则按区域（老文件）；深度按 `REALM_MOB_LV` 反推（同上公式 ± 0.06）并 assert `mob_tag == realm`；巢穴 / 游荡首领只在 `lair_tag(ri) <= realm`（打得动）时算；丹是 dict 列表（带 realm / min_realm / grade / value），服丹按 `pill_use_err` 过滤、溢出结转（C 节）；无丹毒；`params` 里保留 `PILL_EXP` 键（pace.html 读它）。

## K. 接口清单（各实现者照这个名字写，别各起各的）
- `combat_stats.gd`（已写好，别改签名）：`G, atk, hp, def, mob_scale, mob_s_hp, mob_s_atk, guard_factor, hit_factor, to_bar(raw, lv, guard, s_atk), to_real, raid_hit(d, realm, lv, gear_atk, s_def), unit_same, rel_bar_k, pvp_hit, pvp_guard, pvp_cap_k, pvp_shown, power(realm, lv, fx) -> float`，常量 `HP_CONV, ATK_CONV, MOB_DEF_K, A_NOM, PVP_*`。
- `progression.gd`（G2 负责补完）：`XP_SCALE, xp_need, xp_need_v2, realm_total, mob_tag, lair_tag, boss_level, pill_realm_at, herb_pill_realm, insight(mob_lv, k, ri), insight_cap, carry_k, overflow_cap, overflow_of, add_xp, at_cap, pill_exp(realm, grade), overlord_exp, pill_use_err, OVERLORD_P, OVERLORD_PCT, PILL_BASE, REALM_TIER, med_rate, tox() → 0, eat_pill, short_num`。
- `raid_items.gd`（G2）：`PILL_NAMES, rpill(realm, grade), overlord(min_realm), pill(tier, grade)（兼容包装）, pill_exp_now(it, realm := -1), is_xp_pill`。
- `raid_manager.gd`（G1）：`player_dmg_vs(d, t), to_player_from(d, t), _target_scale(t, k), here_tag, here_ri, dmg_ratio, kill_exp(mob_lv, k, ri), add_insight(mob_lv, k, from, kind, ri)`；`player_dmg(d, pvp)`、`to_player(d)` 旧签名保留（按同级）。
