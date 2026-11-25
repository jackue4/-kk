# D 主城界面（meta UI）解耦调研 —— 只读报告

范围：scripts/ex/meta_ui.gd、meta_prep.gd（备战）、meta_shop.gd（坊市）、meta_rank.gd（段位）、meta_kit.gd、hero_select_ui.gd、hero_doll.gd、ex_lobby_ui.gd，
以及 trunk 侧的 player_plate.gd、level_select.gd、hub_hall.gd、hud.gd、ink_style.gd；对照旧主干 492a1fc（重构前）和 raid_profile.gd / abode_ui.gd / hall_pills.gd / raid_items.gd。
本报告没有改任何项目文件。

---

## 1. 各文件读写 ExProfile / ExData 的清单

| 文件 | ExProfile | ExData / 其它 ex |
|---|---|---|
| meta_ui.gd（壳） | `lingshi()` `xianyu()`（refresh_money :326-328）、`take_notice()`（:116） | 只 preload（:16-17）。**壳本身几乎不碰经济** |
| meta_prep.gd（备战） | hero / bag / stash / equipment / stash_cap / BAG_CAP / wh_level / vouchers / upgrade_warehouse / unequip / equip / move / repair / sell / sort_list / in_raid / entry_check / LOCK | wearable / slot_of / value_of / unit_value / repair_cost / can_sell / sell_confirm / q_name / kind_name / desc / KIND_NAMES / wh_next_cost；ExItemView.icon |
| meta_shop.gd（坊市） | bag / stash / lingshi / xianyu / vouchers / buy(id,n) / buy_black / sell / sellable_sum / sell_all_sellables / BAG_CAP | shop(cat) / BLACK / make / count_id / stacks / value_of / unit_value / is_sellable / can_sell / sell_confirm / q_name / kind_name / desc |
| meta_rank.gd（段位） | rank / extract_total / data().stats（:89） | rank_name / RANK_NEED / RANK_NAMES / rank_next_need / XIANYU_RANK（:97） |
| meta_kit.gd | — | `power()`（:130-136：ExData.atk_mult / armor_dr / chip_fx）、`q_col()`（:118-121）、Tile._draw（:613-614 wearable/q_name，:580 ExItemView.icon，:625 法宝耐久 dur） |
| hero_select_ui.gd | `hero_ids()`（:196）、`hero()`（:201）、`set_hero()`（:1135） | HeroDefs（trunk 通用）、MetaKit（:32） |
| hero_doll.gd | — | 只用 HeroDefs.def_of / DEFAULT / TIER（:141-143, :190）。**零经济依赖** |
| ex_lobby_ui.gd（老纸面板大厅） | 111 处，全部是 ex 经济 | 全部 ex。trunk 上没有保留价值（除了 `hero_def()` :715 被 level_select 借用） |

trunk 上其它文件对 ex 的引用（UI 子系统要改的）：

- hud.gd:216-217 EX_PROFILE/EX_DATA；:246-287 `_ex_rank_banner()`（take_rank_up / take_notice / intro_pending / mark_intro），:518 每帧调用；:225-229 INTRO_LINES（搜打撤话术）；:768 HERO_UI；:805 META_KIT。
- level_select.gd:15-24 LEVELS 里 desert/lab 带 `"ex": true`；:25-27 EX_META/EX_LOBBY/EX_PROFILE；:176-200 `_ex_ctx()/_summary()/_entry_err()`；:280-282 新图才出英雄行；:298-301 新图 tip（售卖物 / 命牌）；:302-307 entry_check；:324-386 `_hero_row/_sync_hero_btns/_pick_hero` 读写 ExProfile；:397-436 `_use_meta()/open_abode()`（主城里永远走 meta_ui）。
- player_plate.gd:11-13、26-28、63-71、353-367 `_ex_mode()`（**主城里 level==null 就当新经济**）、370-380 `_apply_mode()`、410-430 `_refresh_ex()`（rank / lingshi / ex_data.rank_name）。
- lan_presence.gd:22, 64-67, 159, 275-276：广播段位（ExProfile.rank / rank_name）。
- main.gd:791-806 `_apply_combat_mode()` 从 ExProfile.hero() 取英雄；:225 一键服丹被去掉。

---

## 2. 可复用的外壳（布局 / 动画 / 部件）

全部可留，经济无关部分直接复用：

- **meta_ui.gd 壳**：虚化场景背景（_capture_bg :174 起，拍屏后关 3D）、顶栏（返回圆钮 + 货币 chip）、进出场动画（:107-112, :443-454）、换页淡出（:416-441）、toast / ok / warn（:494-525）、二次确认 confirm（:527-580）、图标飞行 fly（:587）、音效 sfx/click（:615-626）、`open(host,key)` 自管暂停（:78-84）、`_set_tab()` 老编号 + 页名映射（:355-409）、Esc 关闭。唯一经济耦合：refresh_money 的两个数 + take_notice。
- **meta_kit.gd**：配色常量、glass/box/grad、label/outlined/para/art/divider/rule、button/tab/tag/money/round_button、tween/press_fx/pop/slide_in/fade_in/cascade/roll、徽记 draw_crest（:435 起，按 0..13 档画，TIER_COL :31 只有 6 色）、Tile（:521-637）。耦合点只有 `power()`、`q_col()`、Tile 里的 `ExItemView.icon / ExData.wearable / q_name / chip 耐久条`。
- **meta_prep.gd**：三栏布局（layout :190-258：左人 + 两列装备栏 + 脚下战力；中 两个页签 + 筛选 + 5 列格子 + 底部按钮；右 详情 + 动作列）、战力滚数 + 差值飘字（_rebuild_status :397 起）、穿脱飞图标（_do_equip :690 起）、格子级联动画、自检接口 goto/set_filter/select/press_action/action_texts/detail_name/power_shown。
- **meta_shop.gd**：左分类轨 + 货架 + 详情、买 1 / 买 10、飞进「背包」小牌、一键卖出、史诗以上卖前确认；自检接口 goto/select/press_action/action_texts/press_bulk/cat_key/find_id。
- **meta_rank.gd**：大徽记 + 星盘慢转、进度条从零涨、六张战绩小牌、底部横向可划的档位路、进场滑到当前档。
- **hero_select_ui.gd / hero_doll.gd**：完全通用，只是存档换个地方（见 §5）。英雄页面上没有任何强弱数值展示（只有冷却 / 灵力 / 招式说明，:939-949），符合「只有技能 / 外观 / 打法差异」。ExProfile.set_hero（ex_profile.gd:669-681）本来就「英雄都不要钱，表里有就给」——trunk 照搬为免费解锁即可。
- **ink_style.gd**：放在 scripts/ 下，只 preload ui_style.gd，**没有任何 ex 依赖**（只是注释里提到 ExData.q_ink），trunk 原样保留。

---

## 3. 旧主干（492a1fc）怎么露出这些功能

- **右上角一颗「洞府」圆钮**（旧 hud.gd:91-94 `UiStyle.round_icon_button("pouch")`，B 键同）→ `level_select.open_abode()`（旧 :271-279 永远 `Abode.new()`）→ **abode_ui.gd 三页：储物 / 坊市 / 丹房**。
  - 储物：仓库 60 格（叠格 _stacks :279）+ 佩戴法宝 3（陨落即失）+ 随身丹符 4（进图进背包）+ 储物戒（陨落保住，可扩格）+ 散修行囊。
  - 坊市：Items.shop()（raid_items.gd:333-352：回春丹 60、炼气/筑基下品本境丹、寻宝符 / 破界符、凡品 / 灵器法宝、Prog.SHOP_KEY 的破境丹）、点仓库物品卖、一键出售 sell_junk、扩储物戒。
  - 丹房：Items.recipes()（:360-380：灵草→本境丹、残片×FRAG_N→破境丹、灵田中品丹方）。
- **主城走近 仓库 / 商店** → hub_hall.open_abode(0/1)（:1495-1506，走 hud._open_abode）。
- **入境页「洞府 · 备战」** + 一行 `Abode.summary()`（abode_ui.gd:576-581）。
- **底部「一键服丹」条**（hall_pills.gd，旧 main.gd:224-231 建，H 键）：吃仓库里能服的修为丹，瓶颈提示去修炼场。
- **修炼场阵台**：闭关打坐 / 渡劫突破（旧 hub_hall `_zone()` 有 "med" 分支，旧 :1253-1254）、开机 / 切回前台结算离线闭关（旧 :198 `_settle_offline(Profile.take_boot_seen())`、旧 :1321-1324）。
- **左上玩家牌**：境界 + 战力 + 修为弧 + 修为等级朱印（player_plate 非 ex 分支，战力 = CS.power(realm, lv, Items.fx_total(gear))）。
- 局内：raid_hud.gd 背包。

raid_profile.gd 已有、可直接给新界面用的接口（成功返回 "" / 失败返回原因）：
`lingshi() realm() cult(r) stash() gear() carry() ring() ring_cap() stash_slots() stash_fits() stacks() stack_key() wealth()`、
`equip(i) unequip(i) pack(i) unpack(i) to_ring(i) from_ring(i) sell(i)->int sell_junk()->[n,v] buy(good) ring_next_price() upgrade_ring()`、
`count(name) can_craft(r) craft(r) kit_ok() take_kit() in_raid() RAID_LOCK notice data()["stats"]{raids,out,dead,best}`。
缺的：英雄字段、击杀 / 擂台战绩、新手引导标记（见 §6）。

---

## 4. 修仙版三页的内容建议（全部由 raid_profile 驱动）

### 4.1 备战（meta_prep 修仙版）
- 左：HeroDoll（`Profile.hero()`）；左列 3 格 = **佩戴法宝**（Profile.gear，GEAR_SLOTS=3，陨落即失）；右列 4 格 = **随身丹符**（Profile.carry，CARRY_SLOTS=4，进图直接放背包）。空格水墨影：法宝用 meta_slot_chip / meta_slot_weapon，随身用丹 / 符图标淡影。
- 脚下大数 **战力** = `CS.power(Profile.realm(), int(Profile.cult(r)[0]), Items.fx_total(Profile.gear()))`（与 player_plate / hall_pills:180 同一口径），佩戴 / 取下法宝时滚数 + 「+N/-N」。上面一行小字「元婴期 · 第 N 层」+ 一道修为细条（Prog）；`_entry` 红字只用于 `Profile.in_raid()` 时显示 RAID_LOCK，或「修为已至瓶颈，去修炼场渡劫」这种金字提示。
- 中：页签 **仓库**（stash，标题「仓库 used/60 格」，显示按 abode_ui._stacks 叠格）/ **储物戒**（ring，「储物戒 used/cap」，Items.slots_used）。筛选：全部 / 法宝(gear) / 丹药(pill) / 破境(key+frag) / 灵草(herb) / 灵材(mat) / 符箓(tool)。底部按钮：仓库页 = 「领散修行囊」（仅 Profile.kit_ok() 时）、储物戒页 = 「扩到 N 格 · 价」（Profile.upgrade_ring）。「整理」按钮去掉（raid_profile 没有 sort；或按 stack_key 排序后新增 `Profile.sort_stash()`）。
- 右详情：Items.desc(it) / badge / lock_text / tier_word，颜色 Data.TIER_COLORS[tier]；值多少 `value`。动作：
  - 仓库里：法宝「佩戴」→ equip(i)；丹/破境丹/符「随身带上」→ pack(i)；能服的修为丹「服下」/「服下这一摞」（复用 hall_pills 的 `_eat_stack` 逻辑：Prog.pill_use_err、Prog.eat_pill、Profile.set_cult——建议把 hall_pills 的吃丹抽成静态函数共用）；「收进储物戒」→ to_ring(i)；「卖出 / 卖出这一摞」→ sell(i) 循环（同 stack_key 的逐件卖）。
  - 法宝栏：「取下」→ unequip(i)；随身栏：「放回仓库」→ unpack(i)；储物戒：「取回仓库」→ from_ring(i)。
  - 通往下一境的破境丹在瓶颈时多一行「去修炼场渡劫」提示（逻辑见 hub_hall._break_to/_break_missing :1715-1742）。
- 底部（或战力下面）保留「一键服丹 ×N」按钮＝把 hall_pills 搬进来；hall_pills 本体也要在 main.gd:225 恢复（另一个子系统决定，二选一，避免两个入口）。

### 4.2 坊市（meta_shop 修仙版）
- 左轨分类（[键, 名, 图标]）：丹药 `pill_heal` / 符箓 `tool` / 法宝 `gear` / 破境丹 `key_1` / 丹房 `pill_0` / 储物戒 `ring` / 出售 `lingshi`。删掉 兵刃 / 法衣 / 黑市（仙玉）。
- 货源：`Items.shop()` 按 kind 分到前四栏（顺序固定，买时传整条 good 给 `Profile.buy(good)`）；买 1 / 买 10 = 循环 buy，任一次失败就停并 warn。买到的东西进**仓库**，左下小牌从「背包 x/y」改成「仓库 Profile.stash_slots()/STASH_CAP」。
- 丹房栏：`Items.recipes()` 每条一格，详情列配料「百年灵参 3/1」（Profile.count），按钮「炼制 · N 灵石」→ Profile.craft(r)；不够时按钮灰。
- 储物戒栏：一格展示当前戒，按钮「扩到 N 格（price）」。
- 出售栏：仓库里 value>0 的叠格；底部一键 = 「一键出售凡品法宝 / 灵材 / 服不了的本境丹」→ Profile.sell_junk()（先 confirm 显示件数与总价）。高阶（tier>=3 或破境丹）卖前 confirm。
- 货币只剩灵石（`_can_pay` 只看 Profile.lingshi()）。

### 4.3 段位 → 「境界」（meta_rank 修仙版）
- 修仙主干没有「带出灵石累计」的段位，建议这页改成 **境界 / 道行**：大徽记 = 当前境界（8 档：Realm.LIST 炼气…大乘，MetaKit.TIER_COL 扩到 8 色，draw_crest 增一个按境界画的入口），大字「元婴期」，副行「第 N 层 / 上限 Prog.top_lv(r)」，进度条 = 本层修为 Profile.cult(r)[1] / Prog 本层需求，瓶颈时进度条转朱砂 + 「需 X丹 ×1 + 灵石 Prog.break_cost(to)，到修炼场渡劫」。
- 六张战绩小牌：入境 raids / 撤离 out / 陨落 dead / 单局最高 best（灵石）/ 擂台胜场（新 stats.arena_w）/ 身家 Profile.wealth()。（击杀需要 raid_manager.kills :90 结算时写进 stats.kills。）
- 底部路：8 个境界节点，节点下面写这一境开放什么（筑基：坊市破境丹；**元婴：沙海古墟 / 天工秘所**；…），当前境一圈金线、自动滑到当前。
- 入口名：右上角那颗圆片保留 meta_icon_rank 图标，字改「境界」（hud.gd:830）。如果用户坚持「段位」二字，就把擂台战绩做成段位（目前 arena_duel.gd:59-61 的 wins/streak 不存档，要另加存档字段），不推荐。

### 4.4 主城入口 / 门
- 右上角四颗：英雄 / 备战 / 坊市 / 境界（hud._build_dock :817-825、_layout_dock :829-841），备战 = `_bag_btn`（:103-108），B 键照旧。
- 仓库（STORE_POS）→ open_abode(0) → meta 备战·仓库；商店（SHOP_POS）→ open_abode(1) → meta 坊市；修炼场 med 分支恢复。
- **门 0 木兰草原**：GATES[0].sub「旧版大世界」→「主线大世界」；`_on_hub_gate(0)` 直接 `open_level("mulan")`（选关卡片页只剩一张，可省一步，可选）。
- **门 2 / 3**：GATES 加 `"min_realm": 3`（元婴 = Realm.LIST 下标 3），sub 改「元婴可入」。低于元婴：门洞 shader `locked` = 0.62（变灰），走到门前 `say("沙海古墟凶险 · 元婴期方可入内（你现在是筑基期）", 2.4)`，不发 gate_entered。渡劫成功（_on_break_done）和 set_active(true) 时刷新门的 locked。

---

## 5. 英雄存档挪回 raid_profile

- raid_profile `_fresh()`（:55-59）加 `"hero": "yujian"`（HeroDefs.DEFAULT）；`_fix_types()` 补缺省。
- 新增静态函数（同 ex_profile.gd:650-681 的语义，全免费）：
  - `hero() -> String`、`hero_ids() -> Array`（= HeroDefs.ids()）、`set_hero(id) -> String`（in_raid → RAID_LOCK；不在表里 →「还没有这位英雄」；否则写入 + save）。
- 调用方换源：hero_select_ui.gd:23/196/201/1135、meta_prep（:90/364/704）、level_select `_hero_row/_sync_hero_btns/_pick_hero`（:324-386）、main._apply_combat_mode（:798-801）、player_plate._hero_info（:400-412 的 `_ep.call("hero")`）。
- hero_doll.gd:190 / hero_select_ui.gd:479 的 `HeroDefs.TIER`（固定结丹装束）→ 主干改传 `Profile.realm()`，让展台的装束跟境界走（数值跟境界这件事在 player / combat 子系统，不在这里）。

---

## 6. 精确改动清单（trunk）

**A. 文件去留 / 位置**
1. 删除（trunk）：scripts/ex/ex_lobby_ui.gd、ex_lobby_selftest.gd、ex_item_view.gd（只被 ex UI 用）以及 ex 经济 / 关卡文件（别的子系统）。
2. 保留并改造：meta_ui.gd / meta_kit.gd / meta_prep.gd / meta_shop.gd / meta_rank.gd / hero_select_ui.gd / hero_doll.gd。建议 `git mv` 到 `scripts/meta/`（去掉「ex = 搜打撤」的误导）；同步改引用：hud.gd:768、:805；level_select.gd:25；meta_ui.gd:15/22-24；各页 preload；_tasks/ui_kit/meta_ui_test.gd、meta_game_test.gd、hero_select_test.gd、hero_select_game_test.gd。若想让 extraction-pvp 分支日后好合并，壳和 hero_select_ui / hero_doll 两边保持同一路径和同一份代码，页面脚本各分支各写一份。
3. meta_kit 去 ExData：`power()` 删掉或改成 `power_of(realm, lv, gear)` → CS.power；`q_col(q)` 改按 tier 取 Data.TIER_COLORS；Tile._draw 里 `ExItemView.icon` → `UiStyle.icon(Items.icon_name(it))`（没有就退回 `UiStyle.icon(kind)` / pouch，照 item_view.gd 的做法）、右上角写 `Items.tier_word(it)`（法宝）或叠数、法宝耐久条去掉（旧法宝没有 dur）。想两边共用的话，给 Tile 加 `static var item_api`（icon/col/corner 三个函数），每个分支设自己的。

**B. meta_ui.gd**
4. :16-17 换成 `Profile := preload("res://scripts/raid_profile.gd")`；:116-119 `ExProfile.take_notice()` → 读 `Profile.notice` 后清空。
5. :326-341 refresh_money：只有灵石（`Profile.lingshi()`）；第二个 chip（:278-281 `money("ex_jade")`）改成境界小牌（`Realm.LIST[Profile.realm()].name + "期"`）或直接删。
6. :24 PAGES 换成修仙版三页；:27-31 TITLES 照空；:33 LEGACY 改成旧洞府编号：0 → [prep, stash]、1 → [shop, ""]、2 → [shop, "alchemy"]（旧 abode 的丹房），其余页名映射（:368-392）去掉 black / trader，加 "alchemy"/"丹房"、"realm"/"境界" → rank。

**C. 三张页**：按 §4 重写数据层，壳 / 布局 / 动画 / 自检接口名不变（goto / set_filter / select / press_action / action_texts / detail_name / power_shown / press_bulk）。

**D. hero_select_ui.gd / hero_doll.gd**：:23 ExProfile → raid_profile；:196-201、:1135 换成 Profile.hero_ids/hero/set_hero；:479 和 hero_doll.gd:190 的 HeroDefs.TIER → Profile.realm()。

**E. level_select.gd**
7. :11-24 LEVELS：desert / lab 的 `"ex": true` 换成 `"min_realm": 3, "hard": true`；tag 改「元婴及以上 · 高危禁地」，desc 改旧规矩（采药 / 杀怪夺宝 / 限时找阵撤离 / 可局域网组队，同木兰草原；具体分钟数等关卡子系统定）。
8. 删 :25-27 EX_*、:176-200 `_ex_ctx/_entry_err`；`_summary()` 恒用修仙版（Abode.summary() 或新 meta_prep 的 static summary，前面加出战英雄名）。
9. :132-134 卡片页照旧跳过 hard 图（走门 2 / 3）。`open_level(id)` / `pick(i)` 开头加境界检查：`Profile.realm() < min_realm` → 不进入境页，返回原因（主城门那里已经挡了，这里是给自检 / 其它入口兜底）。
10. :280-282 英雄行对所有图都出（读 Profile）；:298-301 hard 图 tip 改成旧规矩那句（:296 原文）+「元婴及以上方可入境」；:302-307 entry check 删。
11. :397-436 `_use_meta()` 改成认 `--old-abode`（退回 abode_ui.gd 的老三页，保留给 abode_test / abode_open_test 自检），`open_abode()` 默认开 meta_ui 修仙版；按钮字（:290）「备战」。

**F. hub_hall.gd**
12. :70-76 GATES：门 0 sub「主线大世界」；门 2 / 3 加 `"min_realm": 3`、sub「元婴可入」。
13. :1058-1072 `_build_gates()` 把每道门的 ShaderMaterial 存进 `_gate_mats`，新函数 `_refresh_gate_locks()`：`locked = 0.62 if (not open or Profile.realm() < min_realm) else 0.0`；在 set_active(true)（:238 附近）和 `_on_break_done`（:1793）成功后调。
14. :1935-1945 门触发：`not open` 分支之后加 `elif Profile.realm() < int(GATES[at].get("min_realm", 0))` → 节流 say「%s凶险 · 元婴期方可入内（你现在是%s期）」，不 emit。
15. :186 恢复 `_build_farm()`；:249-251 恢复 `_settle_offline(Profile.take_boot_seen())`；:1461-1467 `_zone()` 恢复 med 分支（旧 :1253-1254）；:1532 恢复 RESUMED 结算（旧 :1321-1324）。
16. 自检 :2099 期望值改成「[0, 1]（测试档炼气，门 2 / 3 锁着）」，再补一条把测试档 realm 设 3 后重走门 2 / 3 应触发 [2, 3]。

**G. hud.gd**
17. 删 :214-217 EX 常量、:246-287 `_ex_rank_banner()` 和 :518 调用；保留 `_hub_q` 排队机制，改成说 `Profile.notice`（中途退出还回法宝之类）和新手引导。
18. :225-229 INTRO_LINES 改修仙版，比如：「门 0 木兰草原：采药杀怪夺宝，限时找到亮着的阵撤离」「仓库 / 右上角「备战」佩戴法宝、带丹符；「坊市」买丹卖货、炼丹」「修炼场打坐、渡劫；元婴之后门 2 / 3 的高危禁地才开」；标记存在 raid_profile（新增 `intro` 字段 + `intro_pending()/mark_intro()`）。
19. :817-825 dock 第三颗字「段位」→「境界」，回调 `_open_meta.bind("rank")` 不变。
20. F1 英雄说明（:296-300）里「禁地里：T 拾取 / Tab B 储物袋 / 1 服药 / 2 投符 / M 大地图」是 ex_hud 的键，改成 raid_hud 的键（找局内 HUD 子系统核对）。

**H. player_plate.gd**
21. 删 `_ex_mode()`（:353-367）/ `_refresh_ex()`（:415-430）/ EX 常量（:26-28）/ `_rank_l`；主城和所有图都走旧的 境界 + 战力 + 修为弧。保留按英雄换皮肤重拍头像（`_hero_info` + `_rebuild_shot`），但 :377-380 回老模式时不要强制退回 `HeroSkin.player_key()`，按 `p.hero_def.skin` 拍。

**I. lan_presence.gd**：:22、:64-67、:159、:275-276 的段位广播改成境界（Profile.realm()，名字 Realm.LIST），字段名不变就不用改协议（别的子系统确认）。

**J. raid_profile.gd（与存档子系统协调）**：加 `hero`、`intro`、`stats.kills`、`stats.arena_w/arena_l`；`hero()/hero_ids()/set_hero()/intro_pending()/mark_intro()`；可选 `sort_stash()`。

---

## 7. 风险 / 未决

- **英雄与「本相」**：主干以前的主角是蒙皮「阿拉灯」（hero_id == ""，HeroSkin.player_key）。现在英雄表只有镇岳 / 苍鸿 / 霜华 + DEFAULT yujian；要不要在英雄选择里保留一个「本相（旧主角）」选项，需要和战斗子系统 / 用户确认。
- **英雄数值跟境界**：hero_doll / hero_select 只管外观；HeroDefs.TIER/BASE（结丹固定）在 player 里，归战斗子系统改；界面不显示任何英雄强弱，已符合。
- **吃丹入口重复**：hall_pills 恢复 + 备战页「服下」两条路要共用一份吃丹逻辑，不然丹毒 / 结转规则会分叉。
- **两份界面并存**：abode_ui.gd 留作 `--old-abode` 回退；它的自检（_tasks/ui_kit/abode_test.gd、abode_open_test.gd）和 meta_ui_test / meta_game_test / hero_select_test 都要跟着改；hub 自检 :2099、:2108-2110 读 `_tab` 的地方要和新 LEGACY 编号对上（store → 0、shop → 1）。
- **memory 规矩**：主城牌匾只用 PLAQUE_FS（hub_hall.gd:1081）——给门加「元婴可入」副字时别另起字号；手机上 meta 页的贴图 / 字库内存（web-memory-budget）；毛笔字体网页用随包 Ma Shan Zheng，新出现的字（「境界」「元婴可入」「丹房」等）要确认在补字子集里（_tasks/ui_kit/font_brush_subset.py）。
- **门 2 / 3 的关卡本身**（跑旧系统、同图联机、死亡规则）归关卡 / 联机子系统；界面这边只负责「门锁 + 入境页文案 + 英雄行」。
- **mijing_level.gd:16、minimap.gd:25、destruct.gd:27、warmup.gd:42** 也引用 scripts/ex/（ex_mobs / map_def / grid_world），若 ex 目录整体挪 / 删，要先和关卡子系统对齐，别误删 grid_world / map_def（两张新图要用）。
- 并发写入：项目里可能有别的代理在改 hud.gd / level_select.gd / hub_hall.gd（concurrent-writers-check），落改前先查工作区。
