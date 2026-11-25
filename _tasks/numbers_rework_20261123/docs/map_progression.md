# 数值重构 · 成长 / 经济 / 丹药 区域地图

读的是隔离快照 `D:/GodotProjects/修仙游戏_iso_numbers`（下文路径都相对它）。行号是快照里的行号。Hammer 对照读的是 `H:/Hammer/Project`。
所有数是按代码算的（脚本在 scratchpad 的 `calc/prog.py`、`calc/hammer_shape.py`），基准节奏取 `_tasks/numbers_sim/life_result.json`（runs=40，real=0.7）。

---

## 0. 先说结论（实现者最该知道的 12 件事）

1. **修为的单位只有一种**：存档 `lv`（全局等级 1..99，不是境界内序号）+ `xp`（这一级已攒的数，float，不是累计）。心得、丹药、打坐、离线、渡劫奖励最后都走 `Prog.add_xp` / `Prog.profile_add_xp`。曲线整体放大 ×S，只要**所有来源一起 ×S**，节奏完全不变（见 §11.1 的不变量）。
2. **节奏基准**（normal，life_result.json）：筑基 0.27 h → 结丹 0.93 → 元婴 1.96 → 化神 3.45 → 炼虚 5.94 → 合体 9.60 → **大乘 15.89 h（第 62 局 / 第 16 天）**；来源 心得 36.4% / 丹 43.7% / 洞府打坐 0.5% / 离线 19.4%。casual 16.77 h，hardcore 14.81 h。
3. **丹药是第一大来源，而且全靠背包 12 格限量**：按 life_sim 反推，normal 每局实际服 ~10–13 颗，每境界 2 / 21 / 47 / 77 / 120 / 150 / 229 颗。单颗平均药力占本境界总量：炼气 11.9%、筑基 3.2%、结丹 0.78%、元婴 0.60%、化神 0.47%、炼虚 0.29%、合体 0.19%、大乘 0.08%（Hammer 精魄是 3.9% → 0.0003%，衰减快得多——**不能照搬 Hammer 普通精魄的绝对比例，否则丹药占比从 44% 掉到几乎 0，节奏崩**）。
4. **现在的丹"品阶"不是境界**：品阶由 `Data.roll_tier(区域序号, 运气)` 掷，草原 80% 是 t0、坠魔谷 30–52% 是 t4；品阶只决定药力表 `PILL_EXP[t]`。改成 Hammer 精魄式必须新增一个 **`realm` 字段**（掉落处决定），`tier` 只留作颜色 / 图标 / 排序。
5. **掉落处 → 丹的境界，有一个现成的、和 life_sim 完全吻合的映射**：取 `Prog.mob_level(ri, depth)`，找 `REALM_MOB_LV` 里最接近的那个境界。normal 玩家在自己常刷的深度上，8 个境界全部对上（§11.3）。
6. **Hammer 普通精魄在瓶颈处不浪费**：Hammer 到 maxLevel 后经验**继续累积**（`HammerPlayerGameAttr.lua:567-598`），突破时 `curExp - need` 带进下一境界（`:766-775`）。我们 `add_xp` 到瓶颈就截断（`progression.gd:69-74`）、剩下的心得散掉。**"只能本境界服" + "到瓶颈截断" 一起上，卡瓶颈时攒的丹突破后全成废丹**——现在 hall_pills 的 `_pick`（"大丹留给下个境界"）和 life_sim 的 `_eat`（瓶颈时丹留着、突破后再吃，筑基 68% 修为来自丹，大半是炼气剩下的）都依赖"丹能跨境界吃"。必须二选一：照 Hammer 做溢出修为（推荐），或接受变慢后重调。
7. **天道压制的"掉落品质打折"没有实现**：`SUPPRESS_GAIN` 注释说"心得 / 掉落品质按 SUPPRESS_GAIN 打折"（`progression.gd:250`），实际只有 `kill_exp` 用了它（`raid_manager.gd:361-362`），`Items.roll` / `_loot` / `site_loot` 都没碰 `sup_gap`。境界锁的丹天然就是"掉落压制"（高境界捡到的低境界丹吃不了）。
8. **伤害压制只有一个入口**：`raid_manager.gd:343-352` 的 `sup_dmg_k()` → `player_dmg()`；去掉它要同步改两处提示文案（`raid_manager.gd:338`、`raid_hud.gd:659-660`）。
9. **存档读取只认 `_fresh()` 里有的键**（`raid_profile.gd:79-81`）：新加任何存档字段（溢出修为、丹的新字段不算，丹在 item 里）必须先写进 `_fresh()`，否则读档就丢。item 里新增的整数字段（`realm`、`min_realm`）必须加进 `_fix_item` 的列表（`raid_profile.gd:135`），否则 JSON 读回来是 float，`==` 比较会出错。
10. **大乘没有等级上限（MAX_LV 99）**：现在 `xp_need(99)` = 4.2×10¹⁷，Hammer 形状（每级 ×2.5）下是 2×10⁴²。`short_num` 只有 万 / 亿（`progression.gd:347-353`），会显示成"41838633559亿"。大乘 lv 25+ 还直接喂给战斗公式（`CS.atk(lv)` / `CS.hp(lv)`），指数化以后会爆。
11. **`farm_data.gd` 按 `Items.PILLS.size()` 循环、同时索引只有 5 项的 `HERBS` / `FRUIT_OF` / `MID_COST`**（`farm_data.gd:117-123`、`:101-112`）：把 PILLS 扩成 8 行会越界崩。`Items.recipes()` 写死 `for t in 5`（`raid_items.gd:284-285`）。图标只有 `icon_pill_0..4`。
12. **自检里有按小数写死的断言**：`main.gd:6355 rd.add_exp(1.0e9)`、`raid_selftest.gd:219 add_exp(1.0e6)`、`hub_hall.gd:2065-2066 gain(5) 应为 0`、`hub_hall.gd:2097 应为 Lv.4`、`audio_director.gd:470-471`、`arena_selftest.gd:224/263 lv = ri*3+2 / 22`、`farm_selftest.gd:178 grade 1 tier 0`、`life_sim.gd:114 16.5 × 1.14^(lv-1)`。曲线放大 / 丹的字段改了都要过一遍（§9）。

---

## 1. 数值单位总览

| 量 | 存在哪 | 单位 / 类型 | 谁写 | 谁读 |
|---|---|---|---|---|
| 境界 `realm` | `Profile.data()["realm"]` int 0..7 | 档位 | `end_raid` L331（取 max）、渡劫成功 `raid_manager.gd:931`、`hub_hall.gd:1748` | 全局；`_fix_types` 夹 0..7（L98） |
| 等级 `lv` | `data()["lv"]` int | **全局** 1..99（境界 r 占 3r+1..3r+3，大乘到 99） | `Prog.profile_add_xp`（`progression.gd:266`）、`Profile.set_cult` | `Profile.cult(realm)`、raid 的 `lv`（`_sync_cult`）、战斗 `CS.atk/hp(lv)`、玩家牌、联机 `lan_presence.gd:150` |
| 修为 `xp` | `data()["xp"]` float | 这一级已攒的修为（非累计） | 同上 | `exp_ratio`、hall 条、修炼场牌子 |
| 心得 `insight` | `raid_manager.insight` float（**不存档**） | 修为同单位 | `add_insight` | 撤离时 `profile_add_xp(insight)`（`raid_manager.gd:2673-2680`） |
| 丹毒 `tox` / `tox_t` | `data()["tox"]` float、`["tox_t"]` unix 秒 | 颗数（每服一颗 +1） | `Prog._set_tox` | `Prog.tox()`（按时间自然消退） |
| 最后在线 `seen` | `data()["seen"]` unix 秒 | — | `Profile.save()` 每次都写（L192） | `take_boot_seen` → `settle_offline` |
| 灵石 `lingshi` | `data()["lingshi"]` int | 灵石 | buy/sell/spend/end_raid | 突破价、坊市 |
| 物品 | `stash/gear/carry/ring/live` 里的 dict | `{kind,name,tier,value,...}`；丹另有 `grade`、`exp`（只做显示）、`heal` | `raid_items.gd` 造 | 各界面 |

---

## 2. `scripts/progression.gd` 逐项

文件头 L1-12：声称"数都和 sim2.js 一一对应"（L4-5），但 L9-11 又说 sim2.js 已过时、以 life_sim.gd 校准。重构后把 L4-8 的旧说明删掉 / 改掉。依赖：只 preload `raid_data.gd`（L14），`raid_profile.gd` 运行时 load（L19-20，防 preload 成环；raid_profile → raid_items → progression）。

### 2.1 修为曲线 L22-86

```gdscript
const LV_PER_REALM := 3
const REALMS := 8
const MAX_LV := 99                 # 大乘以后没有瓶颈，一路涨到 99
const XP_BASE := 2000.0
const XP_GROWTH := 1.4
const REALM_XP_MULT: Array[float] = [0.3, 0.75, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
```

- `realm_of(lv)` L32-33：`(lv-1)/3` 夹 0..7。另有一份重复的 `raid_manager._realm_of`（L407-408，用 `Data.LV_PER_REALM`）和 `Data.LV_PER_REALM := 3`（`raid_data.gd:130`）——**三处 3 要同步**。
- `_raw_total(lv)` L36-37：几何级数累计。
- `xp_need(lv)` L41-42：`floor((raw(lv+1)-raw(lv)) × REALM_XP_MULT[realm_of(lv)])`。`raid_data.gd:177-178` 有一个转发 `Data.xp_need`（`audio_director.gd:470` 在用）；`Data.xp_reward` L182-183 没人用了。
- `realm_total(r)` L46-50：三级相加。现值：

| 境界 | 炼气 | 筑基 | 结丹 | 元婴 | 化神 | 炼虚 | 合体 | 大乘 |
|---|---|---|---|---|---|---|---|---|
| 总修为 | 2614 | 1.79万 | 6.57万 | 18.0万 | 49.4万 | 135.7万 | 372.2万 | 1021万 |
| ×上一档 | — | 6.86 | 3.66 | 2.74 | 2.74 | 2.74 | 2.74 | 2.74 |

  每级：lv1 599 / lv3 1175 / lv4 4116 / lv7 15059 / lv13 11.3万 / lv22 234万 / lv24 459万 / lv25 643万 / lv40 10亿 / lv99 4.2×10¹⁷。
  Hammer：境界内每级 ×1.30，跨档 ×1.47 起，每境界 ×15.6（`hammer_cfg.md` §2.2）。三级一境界要 ×15.6 就是每级 ×2.5（2.5³=15.6）。
- `top_lv(r)` L54-55：大乘返回 99。`at_cap` L58-59：`lv >= top and xp >= xp_need(lv) - 0.01`，大乘永远 false。
- `add_xp(lv, xp, realm, v)` L63-86，返回 `[lv, xp, used, ups]`：**到 top 那一级只收 `need - xp`，多出来的丢掉**（L69-74）。这是和 Hammer 的最大差别（见 §0-6、§11.5）。另：如果存档里 `xp > need`（曲线缩小后读老档），非顶级分支 `t2 = need - xp` 为负，`left -= t2` 反而把超出部分加回去、`used` 记少——能跑，但统计不准；迁移时应先把 xp 按比例折算。

**改曲线要连带改的**：`REALM_MOB_LV`（心得上限 / 心得基准）、`MED_RATE`、`PILL_EXP`、`KILL_BASE/KILL_G`、渡劫奖励（按 `xp_need` 比例，自动跟）、存档迁移、`short_num` 单位、自检里写死的 `add_exp` 数、大乘 lv 上限。

### 2.2 区域与深度 L89-117

```gdscript
const DEPTH_LV: Array[int] = [4, 4, 4, 4, 8]
const REGION_REALM_MAX: Array[int] = [1, 2, 3, 4, 7]
const LAIR_R := 1020.0
const MEADOW_DEPTH_R := 380.0
const DEPTH_VALUE := 0.8
const DEPTH_LUCK := 1.0
```

- `depth_at(ri,x,z)` L97-102（草原从出生点、四扇区从 R0=420 到 1020 米）。
- `mob_level(ri, depth)` L106-108 = `REGIONS[ri].lv + round(depth × DEPTH_LV[ri])`，`REGIONS.lv` = 1 / 7 / 10 / 13 / 16（`raid_data.gd:49,60,68,76,84`）。各区怪等级：草原 1–5、黄枫谷 7–11、血色 10–14、云梦 13–17、坠魔谷 16–24。巢穴首领 +2（`raid_manager.gd:1484`）、游荡首领 +1（L1515）、AI 修士同级（L1795）。
- `value_mult(depth)` L116-117 = 1 + 0.8·depth，乘在每件掉落的 `value` 上（`raid_manager.gd:1727-1730`、`:1736-1739`），**只改灵石价值，不改药力**。
- `DEPTH_LUCK` 加在 `roll_tier` 的运气上（`raid_items.gd:148`）。
- 调用者：`raid_manager.coeff()` L302-303（兼容）、`enemy_level` L307-308、`depth_of` L312-313、`_level_in` L317-318、`_update_here` L327-340；`life_sim.gd:188-189`。

### 2.3 心得 L120-140

```gdscript
const KILL_BASE := 8.4
const KILL_G := 1.19
const KILL_CAP_N := 480.0
const REALM_MOB_LV: Array[int] = [2, 4, 8, 11, 14, 19, 22, 24]
const DEATH_KEEP := 0.0
static func insight(mob_lv, k) = KILL_BASE * pow(KILL_G, clampi(mob_lv,1,MAX_LV)-1) * k
static func insight_cap(realm) = insight(REALM_MOB_LV[realm], 1.0) * KILL_CAP_N
```

| 境界 | 常打怪 lv | 每只心得 | 本局上限 | 上限 / 境界总量 | 填满一境界要杀 |
|---|---|---|---|---|---|
| 炼气 | 2 | 10.0 | 4798 | 1.84 | 262 |
| 筑基 | 4 | 14.2 | 6795 | 0.38 | 1268 |
| 结丹 | 8 | 28.4 | 1.36万 | 0.21 | 2313 |
| 元婴 | 11 | 47.8 | 2.30万 | 0.13 | 3766 |
| 化神 | 14 | 80.6 | 3.87万 | 0.08 | 6133 |
| 炼虚 | 19 | 192 | 9.23万 | 0.07 | 7052 |
| 合体 | 22 | 324 | 15.6万 | 0.04 | 1.15万 |
| 大乘 | 24 | 459 | 22.0万 | 0.02 | 2.23万 |

- `k`（经验系数）来源：`raid_manager.gd:1385` `m.xp_k = 14.0 if is_boss else float(base[3]) * (3.0 if elite else 1.0)`，`base[3]` 来自 `Data.SHAPE_BASE`（`raid_data.gd:209`：兽 1.0 / 浮空 0.9 / 巨汉 2.4）；AI 修士写死 5.0（`raid_manager.gd:1984`）；联机分享时按 `xp_k` 反推光点种类（`raid_manager.gd:754`：`>=10` 首领、`>=2.6` 精英）——**如果改 k 的量级，L754 的阈值也要改**。
- 心得到修为是 1:1（撤离成功全数 `profile_add_xp`，瓶颈截断）。
- `REALM_MOB_LV` 的 realm_of 值是 [0,1,2,3,4,**6,7,7**]（lv19 按 3 级一档算是合体）——它不是"该境界的等级"，而是"该境界常打的怪等级"，别拿 `realm_of` 反推。
- **Hammer 形状的副作用**：若修为每境界 ×15.6，按不变量 KILL_G 要变成 ≈2.0（每高一级心得翻倍）。那么同区域边缘到巢穴（DEPTH_LV 4 级）心得差 16 倍，大乘回草原（怪 lv2 vs 24）心得是 2⁻²² ≈ 0——"心得压制"会自然发生，`SUPPRESS_GAIN` 基本可以退休或保留为兜底。

### 2.4 修为丹 L143-171

```gdscript
const PILL_EXP: Array[float] = [66.0, 168.0, 432.0, 1116.0, 2868.0]
const GRADE_NAMES: Array[String] = ["下品", "中品", "上品", "极品"]
const GRADE_MULT: Array[float] = [1.0, 2.0, 4.0, 8.0]
const GRADE_W: Array[float] = [1.0, 0.35, 0.1, 0.02]
const GRADE_DEPTH := 4.0
static func pill_exp(tier, grade) = PILL_EXP[tier] * GRADE_MULT[grade]
static func roll_grade(depth, rng)   # 权重 GRADE_W[g] × (1 + 4·depth)^g
```

品质分布（按代码算）：深度 0 → 68 / 24 / 7 / 1%，平均倍数 1.54；深度 0.35 → 37 / 31 / 21 / 10%，2.67；深度 1 → 13 / 23 / 32 / 32%，4.45。

现在的 5 阶丹各占各境界总量（下品）：

| 品阶 | 名字 | 下品 | 极品 | 占炼气 | 筑基 | 结丹 | 元婴 | 化神 | 炼虚 | 合体 | 大乘 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| t0 | 黄龙丹 | 66 | 528 | 2.5% | 0.37% | 0.10% | 0.04% | 0.013% | — | — | — |
| t1 | 聚灵丹 | 168 | 1344 | 6.4% | 0.94% | 0.26% | 0.09% | 0.03% | 0.012% | — | — |
| t2 | 养元丹 | 432 | 3456 | 16.5% | 2.4% | 0.66% | 0.24% | 0.09% | 0.03% | 0.012% | — |
| t3 | 凝魂丹 | 1116 | 8928 | 42.7% | 6.2% | 1.7% | 0.62% | 0.23% | 0.08% | 0.03% | 0.011% |
| t4 | 培婴丹 | 2868 | 22944 | 110% | 16% | 4.4% | 1.6% | 0.58% | 0.21% | 0.08% | 0.028% |

各区品阶分布（`roll_tier`，深度 0.35，无箱子加成）：草原 77/18/4/1/0%，黄枫谷 63/24/9/3/1%，血色 43/26/16/10/5%，云梦 22/21/20/20/18%，坠魔谷 7/11/17/26/38%。

调用者：`raid_items.gd:85,106-109`、`raid_pace_test.gd:1304`、`life_sim.gd:371`（反推卖价）。

### 2.5 丹毒 L174-181、服丹 L298-310

```gdscript
const TOX_K := 0.05      # 药效 = 1 / (1 + 0.05 × 丹毒)
const TOX_DECAY := 0.25  # 每分钟自然消
const TOX_MED := 3.0     # 打坐时消得快 3 倍
const MED_PILL := 1.3    # 修炼场打坐时服 ×1.3
static func eat_pill(base_exp, meditating := false) -> Dictionary  # {used, ups, lv, eff, gain}
```

- `tox()` L282-289 按 `tox_t` 到现在的分钟数线性消退；`_set_tox` L292-295 记下当前值和时间。
- `eat_pill`：`eff = pill_eff(tox) × (1.3 if meditating)`，`gain = base × eff` → `profile_add_xp(gain)`，丹毒 +1。**到瓶颈时 `used` 可能是 0，但丹毒照加、丹已被调用方拿走**——调用方都先查 `at_cap`（raid `use_item` L2226、hall `_process` L224）。
- 一次连服 12 颗：丹毒 0→12，最后一颗药效 0.625，平均约 0.75；打坐中服 ×1.3。
- Hammer **没有丹毒**（全工程 grep 不到 丹毒 / toxic），也没有"打坐时服加成"。
- 是否保留丹毒需要拍板：保留 = 我们自己的限速阀（建议保留，和 Hammer 的经验丹规则不冲突，只是多一层）；去掉 = 丹药占比上升约 1/0.75，药力表整体 ×0.75 左右再用 life_sim 校。

### 2.6 打坐 / 离线 L184-193、L313-343

```gdscript
const MED_RATE: Array[float] = [0.43, 0.71, 1.14, 1.84, 2.98, 4.8, 7.75, 12.52]  # 每秒
const OFFLINE_RATE := 0.5
const OFFLINE_CAP_H := 8.0
const OFFLINE_MIN_S := 120.0
```

| 境界 | 每小时 | 只靠打坐填满一境界 | 离线 8 h（×0.5）占境界 |
|---|---|---|---|
| 炼气 | 1548 | 1.7 h | 237% |
| 筑基 | 2556 | 7.0 h | 57% |
| 结丹 | 4104 | 16 h | 25% |
| 元婴 | 6624 | 27 h | 14.7% |
| 化神 | 1.07万 | 46 h | 8.7% |
| 炼虚 | 1.73万 | 79 h | 5.1% |
| 合体 | 2.79万 | 133 h | 3.0% |
| 大乘 | 4.51万 | 227 h | 1.8% |

- 每境界 ×1.6 左右（比修为 ×2.74 慢），所以离线占比 casual 45% → hardcore 7%。
- `meditate_tick(dt)` L314-318：涨 `med_rate(Profile.realm()) × dt`，额外消丹毒 `(TOX_MED-1)` 倍。调用：`hub_hall.gd:1628`（dt 夹 0.25 秒，L1622）。
- `settle_offline(since)` L329-343：最多 8 h × 0.5，到瓶颈为止，丹毒按闭关速度消，**内部调 `_prof().save()`**。调用：`hub_hall.gd:247`（开机，`take_boot_seen`）、`:1519`（手机切回前台）。
- 显示：`hub_hall.gd:1567 "每息修为 +%.1f"`、`:1655 "每息 +%.1f　这次 +%s"`、`:1659 "丹毒 %.1f　药效 %d%%"`——**`%.1f` 在大数下会印出 "123456.0"**，改成 `_num1` / `short_num`。`_num1` L1534-1535：<100 用一位小数，否则 short_num。`_settle_offline` L1760-1772 `got < 0.5` 不提示。

### 2.7 突破 L196-206

```gdscript
const BREAK_COST: Array[int] = [0, 500, 2500, 12000, 50000, 160000, 330000, 720000]
const KEY_CRAFT_COST: Array[int] = [0, 100, 400, 1500, 5000, 14000, 36000, 90000]
const FRAG_N := 3
const SHOP_KEY := {1: 300, 2: 1200}
```

相邻倍数 5 / 4.8 / 4.17 / 3.2 / 2.06 / 2.18（手填，前快后慢）。life_sim normal 每境界带出灵石 / 突破价：7.7 / 4.3 / 2.6 / 2.9 / 2.8 / 2.45 / 1.9。
渡劫流程见 §5.3；破境丹不在本次范围（"其它类型的丹先不做"），但灵石若整体放大，这几张表要同倍数。

### 2.8 破境丹掉落 L209-246

`KEY_P 0.006`、`KEY_PB 0.006`、`VAULT_KEY 0.15`、`REGION_KEYS`、`roll_key_to`、`frag_to`。本次不动。注意 `REGION_KEYS` 是"按区域给哪一阶"的现成模板，霸主丹的 `min_realm` 可以照 `frag_to(ri)` 的写法另起一张表。

### 2.9 天道压制 L249-256

```gdscript
const SUPPRESS_DMG := 0.55     # 每高一个境界伤害 ×0.55（pow）
const SUPPRESS_GAIN := 0.25    # 心得 ×0.25（固定，不随档数）
static func suppress_gap(realm, ri) = max(realm - REGION_REALM_MAX[ri], 0)
```

全部使用点（grep 全工程）：

| 位置 | 内容 | 重构动作 |
|---|---|---|
| `raid_manager.gd:128-129` | `var sup_gap`、`_sup_told` | 保留 |
| `raid_manager.gd:329-340` `_update_here` | 算 `sup_gap`；提示 `"天道压制：境界高出此地，出手威力 ×%d%%，心得 ×%d%%"` | 去掉"出手威力"半句 |
| `raid_manager.gd:343-344` `sup_dmg_k()` | `pow(SUPPRESS_DMG, gap)` | 返回 1 或删掉 |
| `raid_manager.gd:350-352` `player_dmg(d, pvp)` | `k = 1 if pvp else sup_dmg_k()` | 去掉乘子（PvP 本来就不压） |
| `raid_manager.gd:361-362` `kill_exp` | `insight × (SUPPRESS_GAIN if sup_gap > 0)` | 保留（可考虑改成按档 pow） |
| `raid_manager.gd:1173` | 换区域时 `_sup_told = 0` | 保留 |
| `raid_hud.gd:659-660` | `"　天道压制 ×%d%%" % sup_dmg_k()*100` | 改成显示心得倍率 |
| `main.gd:6379`、`raid_pace_test.gd:1201` | 只打印 `sup_gap` | 不用动 |

**"掉落品质打折"代码里不存在**。若要"保留掉落压制"有三条路：(a) 靠境界锁的丹自然实现（推荐，零代码）；(b) 在 `_loot` / `site_loot` 里按 `sup_gap` 降 `value` 或运气——但掉落箱是**击杀者本机生成、全房间共享**（`net.send_drop`，`net.gd:740-746`），按本机境界改会连累队友；(c) 只压本机的心得（现状）。

### 2.10 存档接口 L259-343

- `profile_add_xp(v)` L261-268：读 `Profile.realm()` 和 `Profile.cult(realm)`，写 `d["lv"]`、`d["xp"]`，**不存盘**（调用方负责 save）。返回 `{used, ups, lv}`。
- `profile_at_cap()` L271-274。
- 所有修为写入都经过这里，**境界看存档、不看主角身上的 `realm_idx`**（GM 换境界时两者不同；hall_pills L103-105 特意注释了）。

### 2.11 `short_num` L346-353

```gdscript
if a >= 1.0e8: return "%.1f亿" % (v / 1.0e8)
if a >= 1.0e4: return ("%.0f万" if a >= 1.0e5 else "%.1f万") % (v / 1.0e4)
return str(int(roundf(v)))
```

只有 万 / 亿。数值做大以后要加 万亿（1e12）/ 兆（Hammer `HammerUtils.lua` `FormatNumberText` 用 万 亿 兆 京 垓…）。调用点 30 处左右：`raid_items.gd:206,211,214,234`、`raid_hud.gd:551,553,569,571,620,657`、`insight_fx.gd:330`、`hall_pills.gd:172`、`hub_hall.gd:1535,1661,1700,1769,1834`、`raid_manager.gd:453,457,893,897,2303`、`life_sim.gd:74,483-484`、`raid_pace_test.gd:215-256`。

---

## 3. `scripts/raid_profile.gd` 存档格式与迁移

文件 `user://xiuxian_profile.json`（自检 `xiuxian_profile_selftest.json`，带非 PLAY_ARGS 的参数就是自检，每次开机清空，除非 `--keep-profile`，L16-17、L34、L41-45、L68-71）。`VER := 2`（L19）。

`_fresh()` L52-56：

```gdscript
{"ver": VER, "lingshi": START_LINGSHI, "realm": 0, "lv": 1, "xp": 0.0, "stash": [], "gear": [], "carry": [], "ring": [],
 "ring_cap": RING_START, "live": null, "stats": {...}, "tox": 0.0, "tox_t": 0.0, "seen": 0.0, "farm": {}}
```

读档 `_load` L65-92：
- **只拷 `_fresh()` 里有的键**（L79-81）——新字段必须先进 `_fresh()`。
- `_fix_types` L96-117：`lingshi` int、`realm` 夹 0..7、`lv` int、`xp` float；每件物品 `_fix_item`。
- `_fix_item` L134-137：`["tier","value","amt","to","region","heal","grade"]` 转 int——**新加的 `realm` / `min_realm` 必须加进来**。`exp` 不在列表里（float，没关系）。
- `if old_ver < 2: _migrate_v2()` L86-87——只有这一条分支。
- `_migrate_v2` L126-131：上次曲线变 10 倍时的做法是 **xp 清零、lv 夹回当前境界**。
- `_recover_live` L141-160：上局没结算就还回 gear/carry。
- `_migrate_old` L164-186：更老的仓库，`Items.pill(t)` 按品阶造新丹（改 `pill()` 签名要顺手改这里）。

修为读写：
- `cult(realm_idx)` L221-226：**`lv` 不在 `[realm*3+1, top_lv(realm)]` 里就返回 `[lo, 0.0]`**（不改存档，但所有读者都当成境界起点）。如果改了大乘的 `top_lv`（比如不再到 99），现存 lv>新上限的大乘档会被静默当成 lv22、xp 0；下一次 `profile_add_xp` 就把它写进存档。**必须显式迁移**。
- `set_cult(lv, xp)` L229-232：写并 save。
- `end_raid(..., lv := -1, xp := 0.0)` L327-358：境界取 max；`lv <= 0` 不碰修为（raid 现在都传 -1）。

**曲线变了老存档会怎样**：
- 曲线放大：`xp` 原样保留 → 进度条变短（不崩）。曲线缩小：`xp > need` → 顶级直接 at_cap，非顶级下次加修为时把超出部分带过去（`add_xp` 负 t2，见 §2.1）。
- 推荐 VER 3 迁移：`frac = xp / old_xp_need(lv)`（迁移代码里留一份旧曲线公式）→ `xp = frac × new_xp_need(lv)`；lv / realm 不动；大乘 lv 夹到新上限；`tox` 保留。
- 老丹（没有 `realm` / `min_realm`）：在 `stash / carry / ring / live.carry` 里逐件处理，见 §11.7。
- JSON：`JSON.stringify` 默认 14 位有效数字（Godot 4 `json.cpp`），每级 xp 在 1e13 以内不丢精度；Hammer 形状下 lv24 每级 2.84 万亿，够用。

仓库格子：`STASH_CAP 60`（L20）；只有 `kind == "herb"` 叠格（`stacks` L245-246，`STACK_MAX 99`）；**丹一件一格**。境界锁以后玩家会屯"以后境界用的丹"，建议丹也叠格（`stacks()` 加 `pill`；`stack_key` L250-251 按 `kind|name|tier|fx|amt`，丹名里带了品质和丹名就够区分，但要保证 8 个境界的丹名互不相同）。`abode_ui.gd:267-270` 有一份同样的 `_stack_key`，要一起改。

其他经济常数：`START_LINGSHI 300`（L30）、`KIT_LINE 200`（L31）、`RING_PRICE [0,0,500,2000,6000]`（L29）、`take_kit` 给两颗回春丹（L579-583）。`pack` 允许带 `pill/key/tool`（L415）。`sell_junk` 不卖丹（L481）。

---

## 4. `scripts/raid_items.gd` 丹药物品

```gdscript
const PILLS := [["黄龙丹", 2, 25], ["聚灵丹", 5, 25], ["养元丹", 9, 30], ["凝魂丹", 13, 30], ["培婴丹", 17, 35]]  # [名, 旧基准(不用), 气血]
const HEAL_PILL := "回春丹"
```

- `pill(tier, grade := 0)` L81-86：

```gdscript
return {"kind": "pill", "name": Prog.GRADE_NAMES[g] + str(p[0]), "tier": t, "grade": g, "exp": Prog.pill_exp(t, g), "heal": int(p[2]),
		"value": int(float(tier_value(t)) * 0.4 * Prog.GRADE_MULT[g])}
```

  卖价下品 12 / 48 / 192 / 720 / 3000（× 品质 × 掉落处 `value_mult`）。`exp` 字段只做显示 / 兼容——**但 `life_sim.gd:276` 和 `pill_table.gd:21` 直接读 `it["exp"]`**。
- `heal_pill()` L89-90：`{"kind":"pill","name":"回春丹","tier":0,"exp":0.0,"heal":60,"value":24}`（气血条百分制）。
- `is_xp_pill(it)` L94-95：`kind == "pill" and name != "回春丹"`（按名字判断，因为旧档的丹没有 grade）。
- `tier_word` L99-102：带 grade 的修为丹返回 ""。
- `pill_exp_now(it)` L106-109：`Prog.pill_exp(tier, grade)` 现算——**服丹唯一的药力入口**（raid `_eat_one` L2299、hall `_pick` L143 / `_eat_one` L168）。新药力只要改这一个函数就全线生效。
- `roll(level, n, rng, bonus, depth)` L143-167：每件 `k`：`< key_p` 破境丹；`< key_p+0.07` 符；`< 0.34` 丹（30% 回春丹，否则 `pill(Data.roll_tier(level, rng, luck), Prog.roll_grade(dep, rng))`，L159-160）；`< 0.66` 法宝；`< 0.84` 灵材；否则灵草。修为丹约占掉落 18.5%。
- `desc` L198-223：`"服用：修为 +%s、气血 +%d；连服会积丹毒，药效递减"`（L206）。`badge` L227-237：`"修为 +%s"`（L234）。境界锁要在这里加"筑基期可服 / 化神期及以上可服"。
- `icon_name` L243-253：`"pill_%d" % clampi(tier, 0, PILLS.size()-1)`；资源只有 `assets/ui/icon_pill_0..4.png`（另有 `icon_pill.png` 兜底，`item_view.gd` 缺图时退回）。
- `shop()` L259-276：回春丹 60、`pill(0)` 120、`pill(1)` 380、寻宝符 160、破界符 520、凡品法宝 180、灵器 900、筑基丹 300、降尘丹 1200。注释"顺序固定（abode_ui 按下标取货）"（L271）——货架条数改了没问题，但**不能依赖玩家境界动态变货架后再按旧下标取货**（`abode_ui.gd:519-520` 每次重取 `Items.shop()[i]`，同一帧内一致就行）。
- `recipes()` L280-296：回春丹（百年灵参 ×1 + 10）；**`for t in 5: pill(t, 0)` 需 `HERBS[t]` ×1 + `[20,60,160,400,900][t]` 灵石**（L284-285）；破境丹残片 ×3 + `KEY_CRAFT_COST`；末尾接 `farm_data.recipes()`（L293-295，运行时 load）。

`scripts/farm_data.gd`：
- `recipes()` L117-123：`for t in Items.PILLS.size(): need HERBS[t] + FRUIT_OF[t]; out Items.pill(t, 1); cost MID_COST[t]`，`MID_COST := [40,120,320,800,1800]`（L43）。
- `use_line()` L101-112：`Items.PILLS[t][0]`、`FRUIT_OF.size()`。
- **PILLS 扩到 8 行会越界**。`farm_selftest.gd:178` 断言存在 `grade 1, tier 0` 的丹方。

`scripts/raid_data.gd`：`make_pill(tier, grade)` L333-334 转发；`TIER_VALUE [30,120,480,1800,7500]` L268；`TIER_NAMES` / `TIER_COLORS` L265-267（按 `tier` 下标取色，丹的 `tier` 必须保持 0..4）；`roll_tier` L342-356（`TIER_W [1,.2,.04,.008,.0015]` × 件数 × 1.6^(运气×阶)）。

---

## 5. `scripts/raid_manager.gd` 调用链

### 5.1 心得

| 函数 | 行 | 做什么 |
|---|---|---|
| 变量 | 117-123、166-167 | `lv`、`xp`（照抄存档）、`insight`、`_insight_full`、`insight_shown` |
| `_ready` | 213-216 | `_sync_cult()`，心得清零 |
| `kill_exp(mob_lv, k)` | 361-362 | `Prog.insight × (SUPPRESS_GAIN if sup_gap>0)`；`main.gd:6378` 自检在用 |
| `insight_cap()` | 366-367 | `Prog.insight_cap(player.realm_idx)`（局内渡劫后跟着涨） |
| `add_insight(mob_lv, k, from, kind)` | 372-390 | `got = min(kill_exp, cap - insight)`，放光点（`insight_fx.gd`），满了提示一次 |
| `_on_mob_died` | 1690-1721 | `add_insight(m.lv, m.xp_k, …)`（L1703）；联机 100 米外不算（L1701） |
| `net_mob_died` | 742-755 | 别人名下的怪：`share` 且 100 米内才分（L752-754） |
| `_on_rival_died` | 1981-1989 | AI 修士 `add_insight(f.lv, 5.0, …)` |
| `room_lost` | 2614-2635 | 心得 × `DEATH_KEEP`（0） |
| `_finish(success)` | 2655-2701 | 撤离：`profile_add_xp(insight)` → `ins_gain / ins_ups`；陨落 × 0；结果页 `ins / ins_gain / ins_lost` |

### 5.2 修为 / 服丹

| 函数 | 行 | 要点 |
|---|---|---|
| `_sync_cult` | 411-414 | `Profile.cult(player.realm_idx)` → `lv, xp` |
| `add_exp(v)` | 419-423 | GM / 自检直接加修为（`main.gd:6355` 1e9、`raid_selftest.gd:219` 1e6、`audio_director.gd:470-471` `xp_need × 0.6`） |
| `_cult_changed(lv0)` | 427-436 | 到瓶颈 → `_bottleneck`；升级 → 提示、`hp + 20`（百分制气血条） |
| `use_item(i, "use")` | 2216-2233 | **xp 丹 + `_at_cap()` → 拒绝**（L2226-2228）；否则 `bag.remove_at` → `_eat_one` |
| `_at_cap` | 2258-2259 | `Prog.at_cap(lv, xp, player.realm_idx)` |
| `eat_count` / `eat_all` | 2263-2289 | 按 `is_xp_pill` 挑、按 tier 升序排队；**全工程没有界面调用 `eat_all`**（局内一键服丹入口已经没了，只剩背包里点一颗） |
| `_eat_one(it)` | 2293-2312 | `_consume_live(it)`；`Prog.eat_pill(Items.pill_exp_now(it), false)`；飘 `"修为 +%s"`、`eff < 0.8` 时加"丹毒 药效"；`hp + heal`（默认 25） |
| `_process` 出队 | 2727-2737 | 每 0.3 秒一颗，到瓶颈把剩下的放回背包 |
| `_finish` | 2660-2661 | 没服完的队列放回背包 |
| `_consume_live` | 492-501 | 吃掉带进来的随身丹时从 `live.carry` 划掉（防强退刷丹） |
| `_take` / `_swap_out` | 2084-2104 | 背包满了"以贵换贱"按 `value`——境界锁以后吃不了的丹只按卖价算，合理 |

### 5.3 突破

| 函数 | 行 | 要点 |
|---|---|---|
| `_bottleneck(to)` | 440-457 | 缺丹 / 缺灵石提示；够了设 `_trib_to` |
| `_find_key` / `_eat_key` / `_trim_saved_keys` | 461-489 | 背包 / 储物戒找破境丹；成功服下并修正存档 |
| `gm_tribulation` | 868-877 | GM 免费 |
| `_try_start_trib` | 880-913 | `Profile.spend(break_cost)`（失败不退） |
| `_on_trib_done(ok, perfect, total)` | 916-940 | 成功：`lv = max(lv+1, to*3+1)`；`xp = xp_need(lv) × 0.3 × perfect/total`；存档境界、`set_cult`。失败：`xp = xp_need(lv) × 0.5`、`hp` 至少 30 |
| `exp_ratio` | 951-952 | `xp / xp_need(lv)` 夹 0..1 |

**溢出修为要改的地方**：`_on_trib_done` 成功分支把 `xp` 直接覆盖成奖励值（L926），失败分支覆盖成一半（L936）——都会抹掉溢出；`hub_hall._on_break_done` 同样（L1741/1749/1754）；`life_sim._break` L355-362 同样。

### 5.4 掉落

- `_loot(ri, n, bonus, depth)` L1725-1730：`Data.roll_loot` + `value × value_mult(depth)`。
- 巢穴首领 L1708-1716：`_loot(ri, 5, 1.3, dep)` + `Items.frag(Prog.frag_to(lair_ri))`——**霸主丹的落点**。游荡首领 `_loot(ri, 3, 0.8, dep)`。精英 `_loot(ri, 2, 0.5)`。小怪 `KILL_DROP 0.2`（L135）掉 1 件。AI 修士 3–4 件（L1988）。
- `site_loot` L1735-1747：搜点（`raid_search.gd:225-250`；灵草点 20% 出一颗丹 L238-241，自己调 `Items.pill(roll_tier, roll_grade)`）。
- 联机：掉落整件 dict 走 RPC（`net.gd:740-746`），新字段自动同步。

---

## 6. 局外界面：服丹 / 修炼 / 洞府

### 6.1 `scripts/hall_pills.gd`（大厅底部一键服丹，唯一的批量服丹入口）

- `count()` L95-100：仓库里 `is_xp_pill` 的件数 → 按钮 `"一键服丹 ×%d"`（L257）。**境界锁后要只数能服的**。
- `_realm()` L104-105：用 `Profile.realm()`。
- `_meditating()` L114-116：在修炼场打坐时 ×1.3。
- `_room()` L120-127：离瓶颈还差多少（到 `top_lv` 为止）。
- `_pick()` L131-150：**"先挑放得进剩余修为的最大一颗；都放不进就服最小的那颗补满，大丹留给下个境界"**——境界锁下"留给下个境界"不成立；溢出修为下 room 无限，直接按大到小吃。
- `eat_all()` L153-163：`count()==0` 提示"坊市 / 丹房 / 禁地里找"；`profile_at_cap()` 提示去渡劫。
- `_eat_one(it)` L167-179：`Prog.eat_pill(pill_exp_now(it), _meditating())` + `Profile.save()`，飘 `"修为 +%s"`。
- `_process` L215-262：每 0.3 秒挑一颗、从仓库拿走、服下；`"%s期 · 修为 Lv.%d"`、`"药效 %d%%"`；修为条宽 180 px。
- 自检：`raid_selftest.gd:99-111` 往仓库塞 5 颗 `Items.pill(0)`，在炼气调 `hp.eat_all()`——境界锁下 `pill(0)` 必须仍是炼气丹（或改测试）。

### 6.2 `scripts/hub_hall.gd`（修炼场 / 渡劫 / 离线）

- `at_cap` L1529-1530、`_num1` L1534-1535。
- `start_meditate` L1538-1567：瓶颈时 `"修为已至瓶颈，打坐只化丹毒"`；否则 `"闭关打坐 · 每息修为 +%.1f"`（**`%.1f`**）。
- `stop_meditate` L1570-1584：`"出关 · 这次打坐修为 +%s"`。
- `gain(n: int)` L1589-1595：兼容老调用（自检用），`profile_add_xp`。
- `_tick_meditate` L1621-1666：`meditate_tick(min(dt, 0.25))`；每秒飘一次；牌子 `"闭关中 · %s期　修为 Lv.%d　%s / %s"`、`"每息 +%.1f"`、`"丹毒 %.1f　药效 %d%%"`。
- `_break_to` L1675-1680、`_find_key` L1683-1691（仓库 → 随身 → 储物戒）、`_break_missing` L1694-1701、`_start_break` L1705-1732（扣灵石起劫）、`_on_break_done` L1735-1757（同 raid 的公式：成功 `xp_need × 0.3 × perfect/total`，失败 `xp_need × 0.5`，丹不在身边按失败）。
- `_settle_offline` L1760-1772。
- 自检 L2043-2107（`--hub-shot`）：`set_cult(1, 0)`；坐 6.6 秒打印 `med_rate(0) × 6.6`；`set_cult(3, xp_need(3))` 后 `gain(5)` **应为 0**；渡劫后 **"应为 Lv.4"**、灵石"应少 break_cost(1)"。

### 6.3 `scripts/abode_ui.gd`（洞府：储物 / 坊市 / 丹房，**不服丹**）

- 页签 L25 `["储物", "坊市", "丹房"]`；提示文案 L215-222（`"灵草加灵石炼修为丹（出下品）…"`）。
- 储物页叠格显示 `_stack_key` L267-270、`_stacks` L275-288、tile L310-316。
- 坊市 `_build_shop` L381-424：`Items.shop()`、`"%d 灵石"` 价签（L394）、一键出售、扩储物戒。
- 丹房 `_build_alchemy` L428-477：`Items.recipes()` 一行一个，`"灵石 %d"`（L462），`Profile.can_craft / craft`。
- 选中操作 `_build_detail` L482-527：仓库的丹只能"随身带上 / 收进储物戒 / 卖出"（L505-512）。**境界锁后可以在这里加"服用"按钮或"非本境界"提示，但目前不需要**。
- 大数显示：`"%d 灵石"` 一类整数格式在 L199、368、394、407、416、462、510、512、524、526、576；`item_view.gd:74,221`；`raid_hud.gd:548,557,562,566,583,725,785`；`farm_data.gd:107,112`；`farm_plots.gd:1042-1043,1212`。灵石若整体放大要改成短写。

### 6.4 其他显示

- `item_view.gd:217-222` `detail_text`：`"%s · %s%s　%s　值 %d 灵石"`。
- `raid_hud.gd:544-583` 结算页（心得 → 修为、瓶颈散去、陨落散去）；`:620` 心得飘字；`:636-663` 右上信息牌（`"心得 %s / %s"`、天道压制）；`:665` 红字条件 `REGIONS lv > mgr.lv + 2`（lv 单位耦合）。`raid_manager.gd:1180` 同样的 `lv + 2` 危险判断。
- `insight_fx.gd:330`：<1 万写整数，否则 short_num。
- `player_plate.gd:268-294`：局内 `raid.lv / exp_ratio / power`，大厅每 0.5 秒读 `Profile.cult`；`power()` L57-58 → `CS.power(realm, lv, fx)`（`combat_stats.gd:185-188`：`(atk(lv)×(1+攻)×10 + hp(lv)/(1-守)×(1+0.2养)) × 1.1^境界 × (1+0.05识)`）。
- `lan_presence.gd:150,242-244`：联机广播 `lv`、显示 `"Lv.%d"`。

---

## 7. 坊市 / 价格表（灵石）

| 项 | 位置 | 值 |
|---|---|---|
| 品阶价值 | `raid_data.gd:268` | 30 / 120 / 480 / 1800 / 7500 |
| 修为丹卖价 | `raid_items.gd:86` | 品阶价值 × 0.4 × 品质倍数 × 掉落处 (1+0.8·深度) |
| 回春丹 | `raid_items.gd:90` | 值 24，坊市 60 |
| 坊市修为丹 | `raid_items.gd:262-263` | 下品黄龙丹 120、下品聚灵丹 380 |
| 符 | `raid_items.gd:46`、`:264-265` | 值 70 / 220，卖价 160 / 520 |
| 法宝 | `raid_items.gd:266-269` | 凡品 180、灵器 900 |
| 破境丹 | `raid_items.gd:114`、`progression.gd:202` | 值 160×2.1^(r−1)；坊市筑基丹 300、降尘丹 1200 |
| 残片 | `raid_items.gd:118-121` | 破境丹价值 / 4 |
| 灵草 / 灵材 | `raid_items.gd:124-131` | 品阶价值 × 0.35 / × 0.6 |
| 丹房炼丹费 | `raid_items.gd:285` | 20 / 60 / 160 / 400 / 900（出下品） |
| 灵田中品丹费 | `farm_data.gd:43` | 40 / 120 / 320 / 800 / 1800 |
| 合破境丹费 | `progression.gd:200` | 100 / 400 / 1500 / 5000 / 1.4万 / 3.6万 / 9万 |
| 突破布阵 | `progression.gd:199` | 500 / 2500 / 1.2万 / 5万 / 16万 / 33万 / 72万 |
| 储物戒 | `raid_profile.gd:29` | 500 / 2000 / 6000 |
| 起始 / 救济线 | `raid_profile.gd:30-31` | 300 / 200 |

Hammer 卖价 = 品质 × 5 灵石（线性，`hammer_cfg.md` L178），灵石主要靠白送和挂机——参考意义不大。灵石若要"做大"，以上全部同乘一个倍数即可（life_sim 的 `ls` 只跟 `value`、`break_cost`、`KEY_CRAFT_COST`、`SHOP_KEY` 有关）。

---

## 8. `_tasks/numbers_sim/life_sim.gd`（节奏校准器）

**跑法**（L5-9）：

```
godot --headless --path . -s res://_tasks/numbers_sim/life_sim.gd -- [--runs=60] [--prof=casual,normal,hardcore] [--real=0.7]
      [--o=ins:1.2,kb:..,kg:..,capn:..,pill:1.0,pillg:1.0,drop:0.3,med:1.0,medg:1.0,brk:1.0] [--pace=res://...json] [--json=res://_tasks/numbers_sim/life_result.json]
```

几秒到几十秒。它 preload 真代码：`progression.gd`、`raid_items.gd`、`raid_data.gd`、`raid_manager.gd`（取 `KILL_DROP`、`MOB_CAP`，所以 raid_manager 必须能在 headless 下编译通过）。目标看输出里 normal 的 `大乘：实际在玩 X 小时`（现 15.9）和 `修为来源` 一行。

**输入 `pace*.json`**（`_load_pace` L94-119）：每区一条，life_sim 只用 `region / mob / elite / boss / minutes / kpm / mob_lv / avg_k`（老探针没有 `avg_k` 时按写死的 `16.5 × 1.14^(lv-1)` 反推，L114）。现有 `pace.json`（= `pace_combat.json`，2026-11-21 00:26）、`pace_before.json`、`pace_mobile.json`。由 `raid_pace_test.gd`（`-- --raid-shot --raid-pace [--pace-min=5] [--pace-regions=..] [--pace-depth=0.35]`，L3）在真大世界里量。**kpm 取决于攻击 / 怪血（战斗重构会改），所以战斗数值改完必须重量 pace.json 再跑 life_sim，否则 15.9 h 的结论无效**。

**模型**：
- 玩家画像 L29-33（每天局数、局长、洞府分钟、陨落率、搜点数、巢穴率、平均深度、首领胜率、杀怪倍率）。
- `_raid` L185-280：区域 = `ENTRY_REALM [0,2,3,4,5]` 里不超过境界的最后一个（L148-153）；深度 = `P.depth + 0.45×(境界−入口境界) ± 0.15`；杀怪数 Poisson(kpm × kill_k × 0.7 × T)；心得 = 杀数 × avg_k × `_ins(mob_lv)`；小怪掉落 `drop`、精英 2 件、首领 3 件、巢穴 +心得 `_ins(lv+2, 14)` + 5 件 + 残片 + 3 件宝罐；搜点按 `COUNTS / SITE`；心得截到 `_ins(REALM_MOB_LV[realm]) × capn`；陨落：只保破境丹，丹全丢；撤离：背包 12 格，破境丹 / 残片不占格，其余按 `_worth`（丹 × `PILL_PREF 3`）挑，**丹存成一个 float：`it["exp"] × O.pill × O.pillg^tier`（L276）**，其余按价值折灵石。
- `_hub` L300-307：边坐边服（×1.3），打坐，突破，再服。
- `_eat` L310-322：**丹从大到小排，到瓶颈的留着（下个境界再吃）**，每颗丹毒 +1。
- `_break` L325-363：缺丹先用残片合 / 坊市买；缺灵石先卖丹（`_pill_value` L367-373 **按药力反查 `pill_exp(t,g)` 求卖价**）；`TRIB_OK 0.85`；成功 `xp = 0`（**不模拟完美加成**，比游戏略慢）；失败 `xp_need × 0.5`。
- `_life` L376-394：每天 per_day 局 + 洞府；下线离线 `min(8, 24−在线)` 小时 × 0.5；丹毒清零；再服、再突破。
- 不模拟：丹房炼丹（灵草全卖）、坊市买修为丹、仓库 60 格上限、渡劫完美加成、打坐中服丹以外的洞府时间。

**境界锁 / 霸主丹要改 life_sim 的地方**：
1. `S["pills"]` 从 float 改成 `[{realm|min_realm, grade, value}]`，药力服时用 `Items.pill_exp_now(it)` 现算（别读 `it["exp"]`）。
2. `_raid` 挑背包（L262-280）：只把"现在能服或以后能服"的丹当丹挑，其余按卖价；巢穴（L214-218）按 `OVERLORD_P` 加一颗霸主丹。
3. `_eat`：按 `Prog.pill_use_err(it, realm) == ""` 过滤；突破后不能服的旧丹在 `_break` 卖掉（直接用 `it["value"]`，删掉 `_pill_value` 反查）。
4. 若做溢出修为：`_add` 走新的 `Prog.add_xp`（自动），`_break` 成功分支 L357-359 改成带溢出（照游戏里的写法），失败分支 L362 同步。
5. `json_out["params"]`（L80-81）加新常数（`PILL_BASE`、`OVERLORD_PCT`、`OVERLORD_P` 等）。
6. `--o` 加 `ovl:`（霸主倍率）方便试数。

`_tasks/numbers_sim/pill_table.gd`：读 `it["exp"]`、按 tier 统计（L20-22），改成按 realm 统计、用 `pill_exp_now`。
`scripts/raid_pace_test.gd:1302-1304`：`Prog.pill_exp(tier, grade)` 记 `pill_exp_pm`（life_sim 不用这个字段，只打印），改成 `Items.pill_exp_now(it)`。

---

## 9. 自检 / 测试里写死的数（改完逐个过）

| 位置 | 写死的东西 | 风险 |
|---|---|---|
| `main.gd:6346-6380`（`--raid-trib`） | `rd.add_exp(1.0e9)` 假定一次灌满到瓶颈；打印 `kill_exp(1, 1.0)` | 曲线放大到当前境界顶级 >1e9 时起不了劫 |
| `raid_selftest.gd:218-221` | `set_cult(realm*3+3, 0)` + `add_exp(1.0e6)`，"缺丹=1 起劫=-1" | 同上（炼气 lv3 现在 1175） |
| `raid_selftest.gd:99-111` | 仓库塞 5 颗 `Items.pill(0)`，炼气里一键服丹 | `pill(0)` 必须仍是炼气可服 |
| `raid_selftest.gd:295-319` | `insight + 300.0` → 修为"应涨" | 放大后仍成立 |
| `hub_hall.gd:2045-2066` | `med_rate(0) × 6.6`；`set_cult(3, xp_need(3))` 后 `gain(5)` 应为 0 | 溢出修为后 `gain(5)` 会变成 5 → 断言要改 |
| `hub_hall.gd:2071-2101` | `break_cost(1)`；渡劫后"应为 Lv.4" | LV_PER_REALM 不变就成立 |
| `audio_director.gd:470-471` | `add_exp(xp_need(lv) × 0.6)` ×2 触发升级音效 | 成立 |
| `arena_selftest.gd:224,249,263,267,356` | 直接写 `Profile.data()["lv"] = ri*3+2 / 1 / 22` | 成立；大乘上限改了要看 |
| `farm_selftest.gd:70,135,178` | `realm = 0 / 4`；丹方里有 `grade 1、tier 0` 的丹 | 丹方改按境界后要改 |
| `raid_pace_test.gd:153-370` | 心得光点自检 `+1 / +5`、`insight = insight_cap()` | 只测表现，不受影响 |
| `life_sim.gd:114` | 老探针兜底 `16.5 × 1.14^(lv-1)` | 只影响没有 `avg_k` 的老 pace 文件 |
| `warmup.gd:428-430`、`shenshi_selftest.gd:111`、`main.gd:6033,6041` | `make_pill(t)` / `make_pill(1)` / `make_pill(2)` 造展示丹 | 签名改了要跟 |

百分制气血条（不是成长单位，但在本区代码里写死）：升级 +20（`raid_manager.gd:435`）、渡劫失败至少 30（`:938`）、修为丹回血 25/25/30/30/35（`raid_items.gd:35`）、回春丹 60（`:90`）、`_eat_one` 默认 25（`raid_manager.gd:2295`）。`combat_stats.gd` 头注释说条一直是 0..100，不动就没事。

---

## 10. 大乘 lv 25..99 的问题

- `MAX_LV 99`、`top_lv(7) = 99`（`progression.gd:26,54-55`）；`cult()` 的上限也用它（`raid_profile.gd:224`）。
- 现曲线 lv40 每级 10 亿、lv99 4.2×10¹⁷；Hammer 形状（每级 ×2.5）lv40 6.6×10¹⁸、lv99 2×10⁴²。
- lv 直接进 `CS.atk(lv)`、`CS.hp(lv)`、`CS.power`、PvP（`arena_duel.gd:227`）。属性指数化（每级 ×1.1 之类）后大乘练到几十级会爆。
- 建议：大乘也给一个封顶（比如 24 + 若干级，或 lv>24 走"小幅线性加成"），或者大乘以后的等级不进战斗公式；同时 VER 3 迁移夹住现存大乘档的 lv。life_sim 只跑到"到达大乘"，不覆盖大乘以后。

---

## 11. Hammer 式经验丹在我们代码里怎么落地

### 11.1 不变量（保证 15.9 h 不变）

每个境界 r 的停留时间不变 ⇔ 每条来源在境界 r 的"每小时产出 / realm_total(r)"不变。令 `F(r) = 新 realm_total(r) / 旧 realm_total(r)`：
- `MED_RATE'[r] = MED_RATE[r] × F(r)`（离线自动跟）；
- 丹：境界 r 的丹药力 ×F(r)；
- 心得：`insight'(REALM_MOB_LV[r]) ≈ insight(REALM_MOB_LV[r]) × F(r)`，按对数线性拟合出 `KILL_BASE' / KILL_G'`；
- 渡劫奖励、心得上限按 `xp_need` / `insight` 算，自动跟；
- 灵石与修为无关，不用动。

例子（按代码算）：
- **整体 ×100**（`XP_BASE 20 万`，形状不变）：大乘总量 10.2 亿；`KILL_BASE 840`、`KILL_G 1.19`、`MED_RATE ×100`、丹 ×100。最省事，节奏零变化。
- **Hammer 形状**（`XP_GROWTH 2.5`，保留炼气 / 筑基折扣）：总量 5850 / 22.9万 / 476万 / 7439万 / 11.6亿 / 182亿 / 2838亿 / 4.43万亿；`F` = 2.24 / 12.7 / 72.5 / 413 / 2350 / 1.34万 / 7.62万 / 43.4万；拟合 `KILL_G' ≈ 2.0`、`KILL_BASE' ≈ 16.5`；`MED_RATE'` ≈ 0.96 / 9.0 / 83 / 760 / 7010 / 6.4万 / 59万 / 543万。注意 `KILL_G 2.0` 的副作用（§2.3）和 lv99 的天文数字（§10）。

### 11.2 物品结构

Hammer 两种（`ItemConfig.csv` 第 4-13 行 / 第 282-291 行；`HammerItemUseMgr.lua:48-58,129-166`）：
- 普通精魄 `{"exp":125,"realmLimit":1}`：**境界必须正好相等**，否则 `"处于"..境界名.."时才可使用"`（L136）；可交易。
- 霸主精魄 `{"exp":10000000,"minRealm":5}`：**境界 ≥ minRealm**，否则 `"达到"..境界名.."后才可使用"`（L141-152）；不可交易；药力固定 = minRealm 那一境界总量的 5.2% / 6.6% / 7.1% / 7.5%…
- 都是"按数量直接加经验"（`UseAddExpItem` L156-166），没有丹毒、没有打坐加成。

我们的 dict（建议，保留 `tier` 给颜色 / 图标 / 排序，药力不烤死，继续走 `pill_exp_now` 现算）：

```gdscript
# 修为丹（精魄式）：只有正处在 realm 才能服
{"kind": "pill", "name": "中品聚灵丹", "tier": REALM_TIER[realm], "grade": 1, "realm": 1, "heal": 25, "value": ...}
# 霸主丹：境界 >= min_realm 能服，药力固定
{"kind": "pill", "name": "化神霸主丹", "tier": REALM_TIER[min_realm], "min_realm": 4, "heal": 35, "value": ...}
```

`REALM_TIER = [0, 0, 1, 2, 3, 4, 4, 4]`（境界 → 0..4 品阶，配 `TIER_COLORS` / `icon_pill_0..4`，这样不用补图）。8 个境界要 8 个丹名（现在只有 5 个：黄龙 / 聚灵 / 养元 / 凝魂 / 培婴），**名字待定，需要用户拍板**；名字必须互不相同（叠格、丹房按名字数件数都靠它）。

### 11.3 现在的品阶对应到哪个境界 / 掉落处怎么定丹的境界

现在品阶 ≈ "掉落运气"，不是境界：t0 黄龙丹在前三个区都占一半以上。改造后：**丹的境界由掉落地点决定**，建议：

```gdscript
## progression.gd：掉落处（区域 ri、深度 depth）出的修为丹是哪个境界的——取当地怪等级最接近的那个境界的「常打怪等级」，夹在本区收的境界里
static func pill_realm_at(ri: int, depth: float) -> int:
	var ml := mob_level(ri, depth)
	var lo := int(Data.REGIONS[clampi(ri, 0, 4)]["realm"])
	var hi := REGION_REALM_MAX[clampi(ri, 0, 4)]
	var best := lo
	for r in range(lo, hi + 1):
		if absi(REALM_MOB_LV[r] - ml) < absi(REALM_MOB_LV[best] - ml):
			best = r
	return best
```

按 life_sim 的 normal 深度模型核对，8 个境界全部对上：

| 玩家境界 | 区域 | 深度 | 当地怪 lv | 出的丹 | 现在每颗平均药力 | 占境界总量 | 折成下品基准（÷品质均值） |
|---|---|---|---|---|---|---|---|
| 炼气 | 草原 | 0.35 | 2 | 炼气 | 311 | 11.9% | 116（4.4%） |
| 筑基 | 草原 | 0.80 | 4 | 筑基 | 568 | 3.2% | 142（0.79%） |
| 结丹 | 黄枫谷 | 0.35 | 8 | 结丹 | 513 | 0.78% | 192（0.29%） |
| 元婴 | 血色 | 0.35 | 11 | 元婴 | 1073 | 0.60% | 402（0.22%） |
| 化神 | 云梦 | 0.35 | 14 | 化神 | 2304 | 0.47% | 862（0.17%） |
| 炼虚 | 坠魔谷 | 0.35 | 19 | 炼虚 | 3983 | 0.29% | 1490（0.11%） |
| 合体 | 坠魔谷 | 0.80 | 22 | 合体 | 7001 | 0.19% | 1751（0.047%） |
| 大乘 | 坠魔谷 | 1.00 | 24 | 大乘 | 8251 | 0.08% | 1854（0.018%） |

所以第一版 `PILL_BASE`（下品，现单位）≈ **[116, 142, 192, 402, 862, 1490, 1751, 1854]**，品质照旧 ×1/2/4/8、仍按深度掷品质——单颗期望和现在一样；再乘曲线的 `F(r)`。对照 Hammer 普通精魄占比 3.9% / 2.4% / 0.63% / 0.16% / 0.05% / 0.011% / 0.0035% / 0.0003%——我们后期高 10~60 倍，这是有意的（丹是我们 44% 的来源，Hammer 精魄几乎不算来源）。

### 11.4 霸主丹

- 落点：巢穴首领遗藏（`raid_manager.gd:1708-1716`，`lair_ri >= 0` 分支），可选游荡首领小概率。
- `min_realm`：建议按巢穴所在区域的上限境界，`OVERLORD_MIN = [1, 2, 3, 4, 5]`（草原筑基、黄枫谷结丹、血色元婴、云梦化神、坠魔谷炼虚）；也可以像 `frag_to` 那样单独一张表。坠魔谷要不要按魔渊深度给合体 / 大乘版，待定。
- 药力：`overlord_exp(min_realm) = realm_total(min_realm) × OVERLORD_PCT[min_realm]`，`OVERLORD_PCT` 照 Hammer 取 5%~7.5%（如 `[0.05, 0.05, 0.055, 0.06, 0.065, 0.07, 0.072, 0.075]`）；高于 min_realm 的人服，占比自然下降（坠魔谷霸主丹 6% 炼虚 → 合体只占 2.2%，大乘 0.8%）。
- **预算**：normal 每境界巢穴击杀约 0.5 / 0.8 / 1.5 / 2.2 / 3.2 / 5.5 / 8.3 次（局数 × 0.35）。100% 掉、6% 一颗的话炼虚能多出 33%、合体（服坠魔谷炼虚丹）18%——太多。要么掉率 `OVERLORD_P` 0.25~0.35，要么把普通丹 `PILL_BASE` 相应压低，总丹药占比留在 ~44%。必须用 life_sim 校。
- 联机：遗藏箱"谁先开归谁"，霸主丹也一样（Hammer 不可交易，我们没有交易系统，不用管）。

### 11.5 服用规则（最关键的一处取舍）

```gdscript
## progression.gd：能不能服；"" = 能
static func pill_use_err(it: Dictionary, realm: int) -> String:
	if it.has("min_realm"):
		var mr := int(it["min_realm"])
		return "" if realm >= mr else "达到%s期后才可服用" % Realm.LIST[mr]["name"]
	if it.has("realm"):
		var r := int(it["realm"])
		return "" if realm == r else "处于%s期时才可服用" % Realm.LIST[r]["name"]
	return ""      # 旧丹（迁移前）：照旧哪个境界都能服
```

瓶颈处理两种方案：

**A（推荐，照 Hammer）——溢出修为**：
- `Prog.add_xp` 顶级分支 L69-74 改成全收（可加上限，比如不超过下一境界总量，防一次屯几个境界）；`at_cap` 不变（`xp >= need`）。
- 渡劫成功（`raid_manager.gd:925-926`、`hub_hall.gd:1747-1749`、`life_sim.gd:357-359`）：`余 = xp - xp_need(top)`，新境界起点再 `add_xp(余 + 完美奖励)`；失败分支（`raid_manager.gd:936`、`hub_hall.gd:1741,1754`、`life_sim.gd:362`）决定是否保留溢出（建议失败只扣溢出的一半，别抹掉）。
- 去掉"瓶颈不许服丹"的拦截：`raid_manager.gd:2226-2228`、`:2275-2277`、`:2732-2735`、`hall_pills.gd:159-161`、`:224-226`；改提示"修为已满，突破后保留"。
- `hall_pills._room/_pick` 改成"大的先吃"；结算页 `raid_hud.gd:552-553`"余下心得散去"那行可以删（心得也溢出）。
- 存档：溢出就存在 `xp` 里（不需要新字段）；`exp_ratio` 已夹到 1。
- 副作用：现在"卡瓶颈浪费"会消失（life_sim 打印在 `修为来源` 那行的"卡瓶颈浪费 = 总修为的 X%"），节奏会变快，用 `--o=pill:` / `ins:` 往回压。

**B——保持截断**：瓶颈时屯的本境界丹突破后作废（只能卖），玩家体验差、节奏变慢；hall `_pick` 的"大丹留给下个境界"必须删掉；life_sim 要按此模拟。

入口改动（两种方案都要）：
- `raid_items.gd`：`pill_exp_now`（L106-109）按 `min_realm` / `realm` / 旧丹分派；`desc`（L206）/ `badge`（L234）加"X期可服 / X期及以上"；`icon_name` 不用动（靠 tier）。
- `raid_manager.use_item`（L2224-2230）：先 `pill_use_err(it, player.realm_idx)`，不行就 toast 返回（别 `remove_at`）。
- `raid_manager.eat_count / eat_all`（L2263-2289）：过滤能服的（目前无界面入口，但保持一致）。
- `hall_pills.count / _pick / eat_all / _process`（L95-100、131-163、215-262）：用 `Profile.realm()` 过滤；按钮写能服的颗数，必要时补"另有 N 颗非本境界"。
- 丹毒、打坐 ×1.3 保持不变（是否去掉见 §2.5）。

### 11.6 掉落 / 坊市 / 丹房改动点

| 位置 | 现在 | 改成 |
|---|---|---|
| `raid_items.gd:159-160` `roll` | `pill(roll_tier(level), roll_grade(dep))` | `rpill(Prog.pill_realm_at(ri, dep), roll_grade(dep))`（`roll` 已经拿到 `level`=区域和 `depth`） |
| `raid_search.gd:240-241` 灵草点 | 同上 | 同上（`ri`、`depth` 都在手边） |
| `life_sim.gd:175` | 同上 | 同上 |
| `raid_manager.gd:1713-1714` 巢穴首领 | `+ frag` | `+ frag`，按 `OVERLORD_P` 加 `Items.overlord(OVERLORD_MIN[lair_ri])` |
| `raid_items.gd:262-263` 坊市 | `pill(0)` 120、`pill(1)` 380 | 炼气丹、筑基丹（新人用），价格按新药力 / 新价值表 |
| `raid_items.gd:284-285` 丹房 | `for t in 5: pill(t,0)` + `HERBS[t]` | 按境界 `for r in 8: rpill(r, 0)` + 该境界所在区域的灵草（`HERBS[REALM_REGION[r]]`，`REALM_REGION = [0,0,1,2,3,4,4,4]`）；或只列"本境界"一条（`recipes()` 每次刷新都重算，可以读 `Profile.realm()`） |
| `farm_data.gd:117-123`、`:101-112` | 按 `PILLS.size()` 循环 | 改成固定 5 区循环或按境界循环，`HERBS/FRUIT_OF/MID_COST` 同步扩 |
| `raid_items.gd:86` 卖价 | 品阶价值 × 0.4 × 品质 | 按境界的价值表 × 品质（例：`tier_value(REALM_TIER[r]) × 0.4 × (1 + 0.5 × (r − 区内最低境界))`），life_sim 卖丹换灵石靠它 |
| 调用 `pill(t, g)` 的其他地方 | `raid_profile.gd:180`、`raid_selftest.gd:100`、`main.gd:6033,6041`、`warmup.gd:428-430`、`shenshi_selftest.gd:111`、`raid_data.gd:333` | 建议保留 `pill(tier, grade)` 签名并把 tier 当境界的近似（`TIER_REALM = [0,2,3,4,5]`），新增 `rpill(realm, grade)` / `overlord(min_realm)`，旧调用不炸 |

### 11.7 存档迁移（VER 3）

```
_load: if old_ver < 2: _migrate_v2()；if old_ver < 3: _migrate_v3()
_migrate_v3:
  1. 修为：xp 按 旧 xp_need(lv) → 新 xp_need(lv) 等比折算（迁移函数里留旧曲线公式）；大乘 lv 夹到新上限
  2. 丹：stash / carry / ring / live.carry 里 is_xp_pill 且没有 realm / min_realm 的
       → 改成当前存档境界、同品质的新丹（最友好），或按 TIER_REALM 映射（会给高境界玩家一堆废丹）
       → 删掉旧的 exp 字段或按新药力重写（只做显示）
  3. ver = 3、save()
_fix_item：列表加 "realm"、"min_realm"
_fresh：如果加了新顶层字段（例如单独存溢出修为、战力缓存），先写进来
```

`test_mode` 存档每次开机清空，不用迁移。

### 11.8 战力（第 6 点，和本区相关的部分）

- 现有 `CS.power(realm, lv, fx)`（`combat_stats.gd:185-188`），显示在玩家牌（`player_plate.gd:57-58,279,289`），没有任何门槛逻辑。
- Hammer 用战力卡突破：`RealmCfg.needBattleValue` 40 万 / 300 万 / 2500 万 / 1.5 亿 / 10 亿 / 60 亿 / 400 亿 / 3000 亿（`HammerConfig.lua:549-570`；校验 `HammerPlayerGameAttr.lua:656,758-762`）。我们装备陨落即失，若照搬会把"法宝丢了"变成"突破卡死"；既有报告（`hammer_logic.md` L200、`hammer_cfg.md` L240）也建议不做。若要做，只能算不含法宝的战力；接入点是 `raid_manager._bottleneck`（L440）和 `hub_hall._break_missing`（L1694），life_sim 也要加对应模型。

---

## 12. 需要拍板的事

1. 修为曲线：整体放大（零风险）还是换成 Hammer 每境界 ×15.6（要连带 KILL_G≈2、大乘上限、显示单位）。
2. 瓶颈：照 Hammer 做溢出修为（推荐）还是保持截断。
3. 丹毒、打坐 ×1.3 留不留（Hammer 都没有）。
4. 8 个境界的丹名；霸主丹的名字、`min_realm` 表、掉率。
5. 老存档里的丹折成什么。
6. 大乘 lv 25..99 怎么处理。
7. 灵石要不要一起做大（只是整体乘倍数，但要改约 25 处 `%d 灵石` 文案）。
