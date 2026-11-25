# 侦察：局外经济 + 要剔除的修仙 / 挂机功能（xx_econ）

只读调研，2026-11-24，按工作区现状（含别的会话未提交的改动）。行号都是 `scripts/` 下的文件。

## 0 结论速览

- **存档**是单个 JSON 文件（VER 3），键表完全由 `raid_profile.gd:_fresh()` 决定：读档时只抄 `_fresh` 里有的键（`raid_profile.gd:82-84`），文件里多的键会被丢掉。加字段 / 删字段 / 迁移都从这里下手。
- **物品**就是一个能直接写进 JSON 的字典，共 7 种 kind。`pill`（修为丹）、`key`（破境丹）、`frag`（残片）是修仙专用；`gear`（法宝被动）、`tool`（破界符 / 寻宝符）、`herb` / `mat`（卖钱的物资）、回春丹可以直接改名接着用。
- **UI 分三层**：`ui_style.gd` 不依赖任何玩法脚本，整个拿来用；`item_view.gd` 依赖 Items / Data / `Prog.short_num`；`abode_ui.gd` 是"页签外壳 + 选中一件 → 底部出按钮"的写法，适合拿来做仓库、商人、英雄选择的模板。
- **修仙功能能进来的地方很少**：`hall_pills` 只在 `main.gd:225` 建了一次；雷劫 / 结婴只能从主城修炼场、局内瓶颈、GM 键进来。麻烦在两个静态变量：`Tribulation.running` 和 `YuanCine.playing` 被 6 个脚本拿来判断"演出中"，先把这些 preload 清掉才能删文件。
- **`realm_idx` 管的不只是修仙数值，它就是现有角色的技能档位**：空战从结丹起才开（`player.gd:709`）、R 大罡剑阵只在大乘的 art 6 档才有（`gate_array.gd:98`）、另外还管灵力池、技能倍率、对波剑数、神识、外观。**中性默认建议用 2（结丹）**：这一档的 COMBAT、skill_g、MP_UNITS 全是基准 1.0，也能空战。但"招式档 art"要从境界里拆出来交给英雄配置，不然老角色会丢掉元婴以上的招式和 R 大招（见第 4 节）。

---

## 1 存档结构（raid_profile.gd）

### 1.1 文件与模式
| 项 | 值 | 位置 |
|---|---|---|
| 正式档 | `user://xiuxian_profile.json` | :18 |
| 自检档 | `user://xiuxian_profile_selftest.json` | :19 |
| 改造前的老仓库 | `user://xiuxian_stash.json`（只在没有正式档时迁移一次） | :20, :95-96, :218-241 |
| 版本 | `VER := 3` | :21 |
| 自检判定 | `test_mode()`：命令行里只要有一个 `--xxx` 不在 `PLAY_ARGS = [--touch, --warm, --sliced, --keep-profile]` 里、也不以 `--scale3d` 开头，就算自检 | :37, :44-48 |
| 自检清档 | 自检模式下每次开机都 `_fresh()` 再存盘，加 `--keep-profile` 才保留 | :71-74 |

其他脚本也借 `test_mode()` 做隔离：`audio_director.gd:66`、`arena_net.gd:50`、`lan_presence.gd:60`、`meadow_level.gd:142`、`raid_manager.gd:283`。重构后这个函数要保留。

### 1.2 字段（`_fresh()` :55-59）
| 键 | 类型 | 含义 | 去留 |
|---|---|---|---|
| `ver` | int | 版本 | 留，改 4 |
| `lingshi` | int | 灵石（局外货币），起始 `START_LINGSHI=300` (:33) | 留（改名或换成新货币） |
| `realm` | int 0~7 | 境界，只升不降（`end_raid` :390） | 删 / 冻结 |
| `lv`, `xp` | int / float | 修为小等级和本级经验 | 删 / 冻结 |
| `stash` | Array[item] | 仓库，`STASH_CAP=60` 格（按格数算），herb / pill 同类叠成一格，每格最多 `STACK_MAX=99` | 留 |
| `gear` | Array[item] | 佩戴的法宝，`GEAR_SLOTS=3`，死了全丢 | 留（换成装备栏） |
| `carry` | Array[item] | 随身丹符，`CARRY_SLOTS=4`，进图后直接放进背包 | 留（换成随身消耗品） |
| `ring` | Array[item] | 储物戒，死了也保得住；`ring_cap` 从 `RING_START=1` 到 `RING_MAX=4`，扩容价 `RING_PRICE` (:30-32) | 留（相当于 DarkArea 的安全箱） |
| `live` | null / {gear, carry} | 局内锁：一局没结算前存着带进去的东西 | 留 |
| `stats` | {raids, out, dead, best} | 战绩 | 留 |
| `tox`, `tox_t` | float | 丹毒（已经停用，`Prog.tox()` 恒为 0，`progression.gd:424`） | 删 |
| `seen` | float unix 秒 | 最后在线时间，每次 `save()` 都写（:247），只用来算离线闭关 | 删 |
| `farm` | Dictionary | 灵田 `{cells:[{id,t0}/{}…], seed}`，由 `farm_plots.gd` 读写 | 删 |

### 1.3 读档流程 `_load()` :68-97
`_fresh()` → 按键合并文件内容 → `_fix_types()`（:101-122，把 JSON 读回来的 float 转回 int；还会把 `realm` 夹到 0..7）→ 老版本 `<2` 时跑 `_migrate_v2`（:131）、`<3` 时跑 `_migrate_v3`（:144，会调 Prog 的 `xp_need_v2 / XP_SCALE / PILL_EXP / GRADE_MULT` 和 `Items.is_xp_pill / LEGACY_PREFIX`）→ `_recover_live()`（:194，上局没结算就把带进去的东西还回来，并写进 `notice`）。
`notice`（:40）由洞府界面显示一次（`abode_ui.gd:134-136`）。`_fix_item`（:186-190）会把 `tier / value / amt / to / region / heal / grade / realm / min_realm` 都转成 int。

**加 VER 4 的办法**：在 `_fresh` 里加新键（比如 `heroes`、`hero_sel`、`rank`、新货币），在 `_load` 里加一段 `if old_ver < 4: _migrate_v4()`，把旧丹、破境丹、残片折成货币后删掉，再删 `lv / xp / tox / seen / farm`。`_migrate_v2 / _migrate_v3` 依赖的 Prog 常量要么一起删，要么在 v4 里改成直接跳过（老 v1/v2 档直接清空修为字段就行）。

### 1.4 一局的接口
- `begin_raid()` :372-380：返回 `{gear, carry, ring}` 的深拷贝；把 `live` 写进存档、清空 `carry`、`stats.raids++`。
- `end_raid(ok, bag, ring_items, gear_items, realm_idx, lv=-1, xp=0)` :386-417：写回储物戒，境界取较大值（:390）。撤离成功：`bag` 放进仓库，放不下的按 `value` 折成灵石，记 `out / best`；陨落：清空 `gear`、记 `dead`。最后 `live = null`。重构时可以把 `realm_idx / lv / xp` 这几个参数删掉（调用点只有 `raid_manager.gd:2898`，另外 `raid_selftest` 也调）。
- `in_raid()` :433，配合 `RAID_LOCK` (:35)：局内洞府的东西一律不让动（QA BUG-01）；局内唯一能做的存档操作是 `spend()` (:421)。

### 1.5 洞府操作（成功返回 ""，失败返回原因）
`equip / unequip / pack / unpack / to_ring / from_ring / sell / sell_junk / buy / upgrade_ring / craft / take_kit`（:445-660）。`pack` 只收 `pill / key / tool` 三种 kind (:474)。`sell_junk` 卖的是凡品法宝、灵材和过了境界的本境丹 (:531-550)。`kit_ok / take_kit` 是散修行囊：灵石少于 `KIT_LINE=200`、身上和仓库里都没法宝时，白给 2 件凡品法宝和 2 颗回春丹（:641-660），对应 DarkArea 的"免费装备"。和修仙相关的读取接口有 `realm() / cult() / set_cult() / boot_realm() / realm_pills() / take_boot_seen()`。

---

## 2 物品结构和可复用的 UI 积木

### 2.1 物品字典（raid_items.gd）
通用字段 `{kind, name, tier(0..4), value(灵石)}`，`KIND_NAMES` 在 :20。各 kind 另有：
| kind | 额外字段 | 造法 | 搜打撤里怎么用 |
|---|---|---|---|
| gear 法宝 | `fx ∈ {atk, guard, seek, vital}`, `amt`(%) | `gear(tier, idx, value)` :78、`rand_gear` :86；表 `GEAR` :27、`FX_AMT` :25 | **留**：被动加成 = 护甲 / 配件。`fx_total` :240 封顶 守 0.6、攻 0.8 |
| pill 修为丹 | `grade, realm / min_realm, exp, heal, legacy_exp` | `rpill` :95、`overlord` :108、`pill/tier_pill` :116-126 | **删** |
| pill 回春丹 | `heal=60` | `heal_pill()` :128 | **留**（治疗针） |
| key / frag | `to` | `key()` :177、`frag()` :183 | **删** |
| herb / mat | `region`；mat 占 2 格 (`size_of` :61) | `herb()` :189、`mat()` :194 | **留**（纯卖钱的物资） |
| tool | `use ∈ {rune, reveal}` | `tool()` :199、`TOOLS` :58 | **留**（原地撤离 / 寻宝） |

掉落 `roll(level, n, rng, bonus, depth, pill_realm)` :210-234，概率分段：破境丹 `Prog.KEY_P+KEY_PB·bonus` → 符箓 0.07 → <0.34 丹（三成回春丹，七成 rpill）→ <0.66 法宝 → <0.84 灵材 → 灵草。品阶、价值、颜色查 `raid_data.gd:265-268`（`TIER_NAMES / TIER_COLORS / TIER_VALUE`）。坊市货架 `shop()` :333，`abode_ui` 按下标取货，所以顺序要固定。丹方 `recipes()` :360，会在运行时 load `farm_data.gd`（:377-379，有 null 判断）。
给界面用的函数：`desc` :265、`badge` :296、`icon_name` :317（图片在 `assets/ui/icon_*.png`，有 gear / guard / seek / vital / herb / mat / tool / pill_* / key_* / lingshi / pouch / ring）、`tier_word` :155。其中 `desc / badge / lock_text` 对丹和钥匙用了 `Realm.LIST`、`Prog.*`，删丹的时候这几个分支要一起删。

**引用环（preload 规矩）**：`progression` 只 preload `raid_data`；`raid_items` preload `raid_data` 和 `progression`；`raid_profile` preload `raid_items` 和 `progression`；`raid_data` 在运行时 load `progression`（:164）和 `raid_items`（:325）；`progression` 在运行时 load `raid_profile`（:21）；`raid_items.profile_realm` 在运行时 load `raid_profile`（:139）。新写的经济脚本要照这个方向走，别绕成环。

### 2.2 item_view.gd（格子 / 卡片）
- `tile(it, size, selected, corner, note, empty_text) -> Button` :92：上面大图标、下面一行名字（按品阶着色），右上角写 corner（"×12"），名字下面写 note（价钱）；选中描朱砂边；`it` 为空就是灰掉的空格子。背包和洞府都在用。
- `card(it, size, key)` :156：大世界里的拾取小卡片。
- `slot(...)` :25：老的横条格子，没人用了。
- `detail_text(it)` :219：底部那一行说明。
- 依赖：`Items.icon_name / tier_word / badge / size_of / KIND_NAMES / desc`、`Data.TIER_COLORS`、`Prog.short_num`（:11）。**删 progression.gd 之前，先把 `short_num` 换成 `num_fmt.gd` 的 `NumFmt.fmt`**（`progression.gd:490` 本来就是转调它）。

### 2.3 ui_style.gd（宣纸风，零玩法依赖，只 preload `ui_paper_box.gd`）
- 颜色 :11-30（INK / PAPER / CINNABAR / QING / INDIGO / TEXT_INK / TEXT_SOFT / LINE / TINT_*）。
- 字体 `kai()` :74 / `brush()` :88（网页 / 手机走随包字体 + 补字链 `bundled()` :55）。
- 贴图 `tex()` :104 / `icon(kind)` :122。
- 样式盒：`plaque` :145、`scroll` :151（大面板）、`bar_frame` :160、`slot(empty, hot)` :168、`outline` :176。
- 按钮：`style_button(b, on_paper)` :190、`style_primary` :207、`round_icon_button(icon, d)` :220（带 `badge` meta 小纸签）、`corner_pos` :232。
- 装饰：`deco` :267、`rule` :280、`seal(text)` :285、`on_paper(c)` :303。
新做的仓库、商人、英雄选择一律从这里取样式（记忆 paper-xianxia-ui）。

### 2.4 abode_ui.gd（页签面板模板）
- `signal closed` :17；`TABS := ["储物", "坊市", "丹房"]` :26；手机尺寸常量 `BODY / GRID_W / TILE / SHOP_TILE / GEAR_TILE / CARRY_TILE` :28-33。
- `_ready` :49-137 搭好：遮罩 → `PanelContainer(UiStyle.scroll)` → 题头（朱印、题字、页签按钮、灵石图标和数、境界、返回）→ 正文 `_body` → 底栏（`_detail` 说明加 `_acts` 按钮）。
- `_process` :187：放不下就整块缩小再居中。`_refresh` :198：按 `_tab` 重建。
- 选中写法：`_sel = {src, i}`（:37）。`_build_detail` :485 按 src 出按钮；`_act_btn(text, fn, primary)` :533 里 `fn` 返回错误字符串，处理完自动接着选同一叠。
- 叠格：`_stack_key` :268 和 `_stacks` :279（要和 `Profile.stack_key` :306 写法一致）。
- 页面：`_build_store` :302、`_build_shop` :385、`_build_alchemy` :430（删）。
- `summary()` :576 是静态函数，入境页 `level_select.gd:238,286` 在用。
- 打开它的地方：`hud._open_abode` (`hud.gd:160-182`，暂停游戏、放开鼠标)、`level_select.open_abode` (:276)、主城 `hub_hall.open_abode(tab)` (:1489，站在 store / shop 区域时开)。
- **改造建议**：`TABS` 改成 `["仓库", "商人", "英雄"]`，删掉 `_build_alchemy` 和 `_head_realm`（:200 读 `Realm.LIST[Profile.realm()]`）；`_hint` 里提到破境丹的文案（:221-222）和 `_shop_keys` (:226) 一起删；英雄页照 `_build_shop` 的写法，左边一格一个英雄，右边放详情和"选用"按钮。

---

## 3 修仙 / 挂机功能依赖图和拆法

### 3.0 编译安全规矩（Godot 一处 preload 或符号缺了，整个脚本都编不过）
1. **先改调用方，再删文件**：一个 `.gd` 只要还有人 `preload("res://scripts/x.gd")`，就不能删（下面各节列了 preload 点）。
2. 用 `load()` 在运行时取的，文件没了会返回 null，但后面接着 `.call` / 读属性就会在运行时报错。没有判 null 的有：`player.gd:436`（`cine_scr.playing`）、`warmup.gd:258,279`、`main.gd:4207`、`raid_data.gd:164,325`、`air_foe.gd:658`。有判 null 的有：`player.gd:409-410`、`raid_items.gd:139,377`。
3. 从 Prog / Items / Profile 里删常量或函数之前，先查 `Prog.X` 的使用者。实测调用最多的几个：`short_num`（8 个文件）、`xp_need`（7 个）、`pill_use_err / pill_realm_at / mob_tag / carry_over / break_cost / REALMS`（各 4 个）。`raid_search.gd` 用了 `depth_at / pill_realm_at / roll_grade / roll_key_to / VAULT_KEY`（:84, :234-246）；`combat_stats.gd` 用了 `mob_tag`（怪的量级）。
4. **分两步走**：第一步留着文件、把功能断开（函数改成空壳返回中性值），能编过、能跑；第二步删引用、删文件。

### 3.1 修为等级 lv / xp（Prog 的修为曲线）
- 定义在 `progression.gd:25-133`：`LV_PER_REALM=3`、`REALMS=8`、`xp_need`、`add_xp`、`at_cap`、`top_lv`、`overflow_cap`、`carry_over`、`room_left`；存档入口是 `profile_add_xp / profile_at_cap / profile_room / profile_carry`（:389-416）。
- **战斗数值也依赖 lv**：`CS.atk(lv) / hp(lv) / def(lv)` (`combat_stats.gd:54-62`) 经过 `raid_hit` :115 和 `to_bar` :105 决定打怪的伤害和挨打掉多少血；`CS.power` :294 是战力。这个 lv 来自 `raid_manager._sync_cult()` :502，它读的是 `Profile.cult`。`arena_duel.gd:227`、`air_foe.gd:658-661`、`enemy_dummy.gd:124-131`、`lan_presence.gd:150` 也直接读 `Profile.cult`。
- **拆法**：`Profile.cult(r)` 改成恒定返回 `[r*3+1, 0.0]`，`set_cult` 改成空操作；`Prog.profile_add_xp` 返回 `{used:0, ups:0, lv:…}`。这样所有读 lv 的地方都拿到"本境界第一级"，数值稳定（realm 2 时 lv=7）。
- 只有显示用到的：`player_plate.gd:299-318` 的修为弧和 lv 印，`hud` F1 调试条。

### 3.2 修为丹（本境丹 / 霸主精魄 / 旧丹 / 丹毒）
- **数据**：`raid_items.gd:36-47, 95-175`；`progression.gd:227-307`（`PILL_BASE / GRADE_* / pill_exp / overlord_exp / pill_use_err / roll_grade / TOX_* / pill_eff`）和 :444-461（`eat_pill`、`meditate_tick`）。
- **调用点**：
  - 大厅一键服丹 `hall_pills.gd`（整个文件），实例化在 `main.gd:224-231`（inline preload），按键 H 在 :89-93。
  - 局内：`raid_manager.bag_actions` :2386、`use_item` :2411、`eat_all` :2484、`_eat_one` :2507、`_eat_q` 在 `_process` :2948-2961 出队、`_finish` :2874 把没服完的退回背包、`_realm_pills_left` :561、`_bottleneck` 里的缓起劫 :552-558。
  - 局内背包 `raid_hud.gd:478-485`（`Prog.pill_use_err`）。
  - 掉落：`Items.roll` :223-227、`raid_search.gd:234,242`、`raid_manager.gd:1875-1890`（掉的丹按怪的境界档，另外掉霸主精魄 `OVERLORD_P`）。
  - 存档：`_migrate_v3 / _legacy_pills / realm_pills / sell_junk.dead_pill`。洞府丹房 `_build_alchemy`。展示用 `raid_data.make_pill` :334。
- **拆法**：删 `main.gd:224-231` 那一段（`hall_pills.gd` 就没人引用了，可以删）；`bag_actions` 只给 `heal_pill` 出"使用"；`roll` 和 `raid_search` 的丹分支换成回春丹或新的消耗品；`_eat_one` 只留回血那一支；Items 里 `is_xp_pill` 先留着，改成恒返回 false，等调用都清干净再删。
- **视觉能留**：`_float_text` 飘字、`Vfx.breakthrough` 小光圈，可以改成"使用消耗品"的反馈。

### 3.3 破境丹 / 残片 / 渡劫花费
- **数据**：`Items.key / frag / KEYS`；`Prog.BREAK_COST / KEY_CRAFT_COST / FRAG_N / SHOP_KEY / KEY_P / KEY_PB / VAULT_KEY / REGION_KEYS / roll_key_to / frag_to / lair_tag`（`progression.gd:323-373`）。
- **调用点**：
  - 局内：`raid_manager._bottleneck` :533、`_find_key` :572、`_eat_key` :583、`_trim_saved_keys` :593、`_need_key / _need_ls` (:108, :149)，拾取时会再检查一次 (:2292)，巢穴首领掉残片 (:1885)。
  - 宝库送钥匙 `raid_search.gd:245`。
  - 主城：`hub_hall._find_key / _break_missing / _break_pill_warn` (:1717-1754)。
  - 洞府：坊市的破境丹 `Items.shop` :346-350，丹方 :370-375。
  - **`player_plate.gd:309` 读 `raid._need_key / raid._need_ls`**：这两个变量要留着（恒为 -1），或者把 plate 一起改掉。
- **拆法**：`raid_manager._at_cap()` (:2459) 改成恒返回 false，`_bottleneck` 就不会再被触发；然后把上面这些函数删掉。
- **能复用**：首领掉"一片残片"的保底写法，可以改成首领必掉的高价值物资。

### 3.4 心得 insight（局内攒，撤出才结算）
- **数据**：`Prog.insight / insight_cap / KILL_* / DEATH_KEEP / SUPPRESS_*` (`progression.gd:196-225, 376-385`)。
- **调用点**：
  - `raid_manager`：变量 `insight / insight_shown / _insight_full` (:130, :185)；初始化 :233-240；`kill_exp` :429、`_carry_k` :435、`insight_cap` :456、`add_insight` :463、`insight_arrived` :485、`_sync_shown` :490；击杀时调用 :877-878, :1873, :2176；结算 :2883-2897，断线 :2836-2842。
  - `raid_hud`：心得小条 :628-660、信息牌 :675-699、结算页 :557-584。
- **拆法**：`kill_exp` 改成返回 0，结算时不调 `profile_add_xp`，信息牌那行改成显示击杀数或带出价值。
- **能复用**：`insight_fx.gd` 只依赖 `Prog.short_num` 和 `mgr.insight_arrived()`（:130），光点飞到身上、合并飘字的效果完整，可以直接改成"击杀得分 / 赏金飞到身上"。

### 3.5 打坐 / 离线闭关
- **数据**：`Prog.MED_RATE / med_rate / meditate_tick / OFFLINE_* / settle_offline / touch_seen` (`progression.gd:310-321, 456-486`)；`Profile.take_boot_seen` :255、`_boot_seen` :41、`seen` 字段。
- **调用点**：
  - `hub_hall`：`meditating` (:124)、`start_meditate` :1568、`stop_meditate` :1601、`_tick_meditate` :1652（调用在 :1872-1873）、`gain` :1619、`_settle_offline` :1829（调用在 :249 开机、:1527 切回前台）、`_notification` :1520-1533、"med" 区域 `_zone` :1450-1455 和 `use()` :1478-1484、按钮文案 :1893-1906。
  - `hall_pills._meditating` :147 也读 `hub.meditating`（服丹那段删了就没了）。
- **拆法**：`_zone()` 不再返回 "med"；删掉 :249 和 :1527 两处结算；`meditating` 变量留着恒为 false（`set_active` :219、`use` :1467、`_physics_process` :1998 都会读）。
- **能复用**：修炼场的场景（石阵台、符石）可以改成"英雄选择台"或"训练场"。

### 3.6 雷劫 tribulation.gd（能独立编译：只依赖 UiStyle、Sfx、全局类 Player / CameraRig / Vfx）
- **对外接口**：`signal finished(success, perfect, total)`；`static var running`；`player / cam / realm_to / net_cb / spectate / subject / demo_auto / storm`；`NAMES / COLS`；`remote_bolt / remote_finish / _end`。
- **preload 它的**：`hall_pills:26`、`hub_hall:37`、`hud:11`、`main:45`、`raid_manager:37`；运行时 load 的：`player.gd:409`。
- **读 `running` 的**：`hud._cine_busy` :187、`hall_pills._busy`、`hub_hall._busy` :1707、`main.gd:644,655`（GM）、`main.gd:1089`（触屏让出触摸）。
- **局内**：`_trib` / `_in_trib` / `_trib_to` (:180-182)、`gm_tribulation` :1008、`trib_active` :1015、`_try_start_trib` :1020、`_on_trib_done` :1056、`_end_trib` :1095、`_abort_trib` :2855、旁观 `net_trib` :815、天色 `_blend_atmosphere` :1214-1226。
- **联机**：`net.send_trib / _trib` (`net.gd:726-735`)，状态位 bit4 `_in_trib` (`net.gd:471`)。
- **其他读 `trib_active()` 的**：`shen_shi.gd:134`、`audio_director.gd:508-510`、`main.gd` 自检、`raid_selftest:231`。
- **拆法**：第一步不删文件、不建实例。`trib_active()` 恒返回 false；删掉 GM 键（`main.gd:632-666`）和触屏"境-/境+"按钮（`touch_controls.gd:44-45`）；去掉 hub_hall 的 `_start_break / _on_break_done`。
- **能复用**：三段式演出（托空 → 天雷 + 在圆钮上点"挡" → 收尾）和联机旁观机制都完整，可以改成**段位晋升演出**，或者局内"天劫"地图事件（雷劫 QTE 改成格挡判定练习）。`COLS / NAMES` 本身就是按档分色的。

### 3.7 结婴演出 yuanying_cine.gd（只有视觉）
- **对外接口**：`static var playing`；信号 `revealed / done`；`player / cam / base / yaw0 / dark / gold / tear_k`；`static prebake(lite)`。
- **触发**：只有 `player._ascend_start()`，在 `realm_idx == 3` 时 (`player.gd:404-451`)。
- **preload 它的**：`hall_pills:27`、`hub_hall:38`、`hud:12`、`raid_manager:38`；运行时 load 的：`player:436`、`warmup:258`、`main:4207`。
- **读 `playing` 的**：上面那几处的 `_busy`、`raid_manager._watch_cine` :952、`_process` :2927、`_blend_atmosphere` :1231。
- **拆法**：只要境界不再往上升，它就不会被触发；保险起见在 `_ascend_start` 里把 :406 那一支删掉；`warmup.gd:244` 的 `cine_on` 设成 false（省掉加载时的预热）。
- **能复用**：整段 18 秒、七个分镜的过场（剑气冲天、破云、法相现身、围观者）可以改成**英雄觉醒终结技**或**赛季段位晋升**的大演出。

### 3.8 全屏播报 realm_broadcast.gd（通用组件）
- 用法：`make(host, title, line, seal, y)` 先建好、透明预光栅化，之后 `play()` (:25, :100)。
- 调用点：`raid_manager._watch_cine` :959 和 `net_announce` :978。
- **注意**：`net.send_announce / _announce` (`net.gd:640-648`) 还顺带传 `§s`（搜点）、`§x`（撤离）这类小消息 (`raid_manager.gd:974-1000`)，这条通道要留着。
- **能复用**：直接用来播"××撤离成功 / 首杀 / 空投降临"。

### 3.9 题字 realm_banner.gd（通用组件）
- 用法：`show_realm(text, col, sub, seal)` :86；静态 `_load_font()` :61。
- 调用点：境界突破 `hud.realm_up` :199，由 `player.realm_ascended` 信号接过来 (`main.gd:258`)。
- 其他用户：区域题名 `raid_hud.gd:194,212`、`boss_hud`，`combat_word / skill_calligraphy / trailer` 借它的字体。**必须留**。
- **能复用**：段位晋升、英雄登场、关卡题名。

### 3.10 境界光环 realm_halo.gd（只有视觉）
- 接口：`make(idx)` :56、`place(idx)` :64、`set_power` / `play_in`。
- 调用点：只有 `awaken_fx.gd:16,148,176`（觉醒时用；`start(secs, realm_i, col)` :97）、`warmup.gd:279`、`awaken_fx.prime` :63-90。觉醒入口：`air_melee._awake_fx_start` :4324-4332、`remote_player.gd:105`。
- **能复用**：8 档光环直接当**英雄觉醒外观或段位装饰**，把 `start()` 的 `realm_i` 参数换成英雄 / 段位的档号就行。觉醒计量条（TSB 的 awakening）可以接到 `air_melee.awake_t / AWAKE_DUR=14` (:89, :193) 上。

### 3.11 神识 shen_shi.gd（按境界分档）
- 档位表 `TIERS[8]` :32-48，每档有 r / see / cd / hold / xray 和各种外观参数。
- 读境界的地方：`tier_of` :99、`passive_r` :103-107、`scan_r` :111-116、`scan` 里 :140；用 `realm_idx > 我的境界 + 1` 隐藏 AI 修士和别队真人 (:222, :238)；还会调 `mgr.trib_active()` (:134)。
- 境界定在 2 时：扫描半径 150 米、被动 90 米、冷却 26 秒；大家境界都一样，就不会有人被藏起来。
- **建议**：神识档改成英雄被动或可携带道具（"识"法宝本来就加 `scan_r`，:113-116），读 `realm_idx` 的地方换成一个 `tier` 参数。

### 3.12 灵田农场（hub_farm / farm_plots / farm_data）
- **入口**：只在 `hub_hall`：`const Farm` :46、`_build_farm` :1937-1972、`_apply_area` :1975-1989、牌坊门 :384-385, :894-895, :1115、传送 :1998-2002、`use()` :1469-1471、`_physics_process` :1858-1869。
- **外部依赖**：
  - `touch_controls.gd:59-62`（`attack_text / peace`，farm_plots 每帧写）。
  - `raid_items.recipes` :377（运行时 load，有 null 判断）。
  - `farm_plots` 读写 `Profile.data()["farm"]`，开垦看 `Profile.realm()` (:166-171)。
  - 自检 `farm_selftest.gd`，以及 `hub_hall` 自检 :2291-2426。
- **拆法**：hub_hall 不再调 `_build_farm`，牌坊门改成实心或封住。注意 `farm.plots`（:1979）、`_portal_farm`（:1984）没判空，要么连同 `area=="farm"` 的分支一起删，要么给它们加判空。删 `raid_items.gd:376-379`。三个 farm 脚本和 `farm_selftest` 一起删。

### 3.13 其他看境界的数值（不算修仙，但跟着 realm 走）
- **天道压制和区域境界档**：`Prog.suppress_gap / REGION_REALM_MAX / REGION_TAG_BAND / mob_tag / mob_level / depth_at`；`raid_manager._update_here` :361-375 会提示"境界不足"；`raid_hud` :693-699 显示危险色。新关卡如果还要"区域越深怪越强"，就留 `mob_level / mob_tag / depth_at / value_mult`（`CS.mob_scale` 依赖它们），删掉压制。
- **战力** `CS.power`：会飘"战力 A → B"（`raid_manager._power_toast` :312、`hall_pills`、`hub_hall`），玩家牌也显示。可以改成装备评分（DarkArea 的"装备价值"）。

---

## 4 依赖 `player.realm_idx` 的系统和中性默认

| 系统 | 读什么 | 在 realm 2（结丹）时 |
|---|---|---|
| 移动 / 飞行 `player.gd` | `realm` 字典的 speed / boost / rise / ceiling / blink / blink_spd / mode / fx / lines（:362-395, :647, :767, :804, :824）；`Realm.Mode.LIGHT` 决定能不能空战（`is_light_mode` :238，`take_air` :709、`enter_air_combat` :726、`set_realm` 里 :368 会降级） | 遁光 45 m/s，**能空战** |
| 灵力 | `CS.mp_max(realm)` 来自 `MP_UNITS` (`combat_stats.gd:132-137`)，回复 `mp_regen_k`（`air_caster.gd:214`），显示 `mp_shown` | 100 单位（各种消耗都是按 100 配的） |
| 招式档 art | `Realm.LIST[i].art` → `air_caster._art` :83、`air_melee` :500/:992、`sword_manager.apply_realm` :48、`main._on_realm_changed` :442-445（剑诀名）；**R 大罡剑阵只在 art 6** (`gate_array.gd:98`、`touch_controls.gd:143`) | art 1（平卧剑轮），**没有 R 大招** |
| 伤害 | `CS.base(realm)=Realm dmg`；`skill_k(realm,i)` (`air_caster.gd:557…827`)、`volley_k` :466、`q_k`（`flying_sword.gd:560`）、`ground_k`（`player_melee.gd:853`）、`skill_g` | base 18，skill_g = 1.0（基准） |
| 打击感 | `Realm.combat(i)`（`realm.gd:119-145`；`air_melee._prof` :743、`player_melee` :854/922/942、`air_caster` :439）；`flair()` (`air_melee.gd:738`) 和 `_crack_tier` :2121 用 `realm-2` | 全部 1.0；没有分身、瞬步这些花样 |
| 觉醒 | `awaken_fx`：光环档、空间扭曲要 ≥3 (:22, :117, :184)；`warmup.gd:232` 要 ≥2 才预编 | 有描边和光环，没有扭曲 |
| PvP | `CS.pvp_hit / pvp_cap_k` 按境界差算 (`combat_stats.gd:227-241`)；`raid_manager.gd:887-908` | 大家一样 → 公平 |
| 擂台 | `arena_duel.gd:227,331-358`（`volley_init` 要 ≥2）、`CS.arena_ai_hp` | 正常 |
| 神识 | `shen_shi.TIERS` | 150 米 / 26 秒 |
| 地形破坏 | `meadow_level.terrain_blast` 要 ≥2 (:495) | 能破坏 |
| 剑冢首领 | `boss_arena.gd:156-162` 低于 3 时把人拉到元婴 | 会被拉到 3 |
| 联机 | `net.gd:166,193,304,473`、`remote_player.push_state` :137-141（会 `set_look`）、`lan_presence.gd:150,233`、`arena_net.gd:159,186` | 原样同步 |
| 外观 / UI | `hero.set_look(realm_idx)`（`player.gd:365`，`voxel_hero.LOOKS` :70）、`player_plate.gd:283-284`、`hud.gd:365,499` | 结丹装束 |
| 怪 / AI | `air_foe.gd:989`（没主角时兜底按 2）、`raid_manager.gd:2112`（AI 外观跟主角的境界走） | — |

**建议**：
1. 开机时 `player.set_realm(2, false)`，替换 `main.gd:262` 的 `boot_realm()`；`Profile.cult` 固定返回 `[7, 0.0]`。
2. 老角色（剑仙）想留住元婴以上的招式和 R 大罡剑阵，就要把 art 从 realm 里拆出来。做法是让英雄配置给出一个合并后的字典 `player.realm = Realm.LIST[2].merged({"art": hero.art, "swords": …})`：数值档固定在 2，招式档由英雄自己定。这样 `Realm.art(player.realm)` 的十几处调用都不用改。这件事要和战斗侦察那份报告一起定。
3. 联机的 `realm` 字段继续传，但意思改成"英雄档 / 段位"；`remote_player.set_look` 跟着英雄走。

---

## 5 建议的拆除顺序（每一步都能编过）
1. 存档升 VER 4（加英雄 / 段位，删修为、丹毒、离线、农场字段；旧丹、钥匙、残片按价值折成货币）。`Profile.cult / set_cult / realm` 改成固定值的空壳。
2. 删 `main.gd:224-231`（hall_pills）、`main.gd:632-666`（GM 境界键）、`touch_controls.gd:44-45`；删 `hall_pills.gd`。
3. hub_hall：删"med"区域、打坐、离线、渡劫、农场（:249、:1527、:1450-1455、:1478-1484、:1568-1854、:1937-1989 和相关的 :1858-1869、:1998-2002）；去掉 `Tribulation / YuanCine / Farm` 的 preload，`_busy()` 改成恒 false 或只看擂台。
4. raid_manager：`_at_cap / trib_active` 恒 false；删丹、钥匙、心得的分支；`_watch_cine` 和 `Broadcast` 改成播撤离 / 击杀的播报；去掉 `Tribulation / YuanyingCine / InsightFx` 的 preload（InsightFx 改造后留下）；`net_trib` 和 `net.send_trib` 一起删。
5. hud / player：`_cine_busy` 改成恒 false；`player._ascend_start` 删掉元婴分支；删 `player.gd:409/436` 的运行时 load。
6. Items、Prog 瘦身：删丹、钥匙、残片和修为曲线；`short_num` 换成 NumFmt；Prog 只留区域、深度、怪的等级和价值倍率；`raid_search / raid_data.make_pill / item_view` 跟着改。
7. 删 `tribulation.gd / yuanying_cine.gd / farm_*.gd / hub_farm.gd`，或者改成段位演出留下；自检脚本 `raid_selftest / raid_pace_test / farm_selftest / arena_selftest / lan_selftest / camp_net_selftest` 和 `main.gd` 里 `--raid-trib / --yuanying / --raid-yuanying / --raid-econ` 这几支要一起改。
8. 保留下来改作他用的：`realm_banner`（段位 / 题名）、`realm_broadcast`（全服播报）、`realm_halo`（觉醒 / 段位外观）、`insight_fx`（得分光点）、`ui_style / item_view / abode_ui` 外壳、储物戒（安全箱）、散修行囊（免费装备）、坊市（商人）。
