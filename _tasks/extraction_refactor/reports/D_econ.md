# D_econ 交付报告：局外经济（SPEC 第 3 节 + 3.9 界面）

日期 2026-11-24。实现者 D（经济）。没有 commit / push。

## 1. 做了什么

1. **数值表 `scripts/ex/ex_data.gd`**：DarkArea 的 `darkarea_data/*.json` 全搬（灵石 = 金币、仙玉 = 钻石）。常量表由可重跑的 Python 工具生成（只改写文件里 `# ==== GENERATED BEGIN/END ====` 之间那段），逻辑和本作新增的数值是手写的。
   - 售卖物 98 件：Trader Type=1 的 94 件去掉身份牌（→ 命牌 `tag`）= 93 件 `s01..s93`，另有 5 件表外首领专属 `sx1..sx5`（沙虫巨牙 / 钳角等。DarkArea 里卖不掉，本作按描述价能卖，沙渊巨虫的掉落才有意义）。每件都起了仙侠名（按价值档），原名留在 `da_name`；价值、品质、所在池、标签（古墓专属 / BOSS专属 / 箱子专属）都保留。DarkArea 商场首领表里写错的两个 id 已改成正确的（蝴蝶结 / 公主裙）。
   - 兵刃 7 家族 × 7 档（`w_<家族>_<品质>`），另有 17 件独特兵刃 `w_u_*`：9 件近战武器 + 越王勾剑、毁灭射线、粒子炮、加特林、喷火器、黄金匕首、黄金战锤。独特兵刃的名字和外观家族是新起的，数值和同档兵刃一样。坊市价取 DarkArea 同档枪族商店价的中位数（8000 / 2.4万 / 7.2万 / 21.6万 / 64.8万），回收价取同档 Trader 价的中位数。
   - 法衣 4 部位 × 7 档（`a_<部位>_<品质>`），名字是「套名 + 部位」（麻布 / 青衫 / 云纹 / 流云 / 紫霄 / 赤霞 / 太虚 + 冠 / 衣 / 护腿 / 履），价格照 DarkArea 护甲。
   - 法宝 3 类 × 5 档（`c_<regen|shell|pierce>_<4..8>`）：回元佩 / 玄龟镜 / 破军印，基础价、耐久照扩展芯片，数值照 SPEC 3.4。
   - 消耗品：8 种药（治疗量按 ×0.5 折）、强心丹、4 种符、禁室玉钥、护宝符、仓库凭证。
   - **炼器材料 `mat`（本作新增的种类）**：DarkArea 首领表里约 34% 的抽数落在「枪械升级 / 赋能材料」池上，SPEC 没说这些材料换成什么。我照搬成 `mat`，共 31 种：升级材料 7 种、赋能材料 7 种、永恒晶石 6 种、天启配方 11 种。本轮没有兵刃升级，材料只能按 DarkArea 的回收价（25..1600）卖给商人；天启配方的回收价是 0，卖不掉。材料不算售卖物：可以带入禁地，也不计入带出价值。这样首领的掉落比例和 DarkArea 一致，下一轮做兵刃升级时可以直接用。
   - 53 个物品池、21 张箱子表、25 张怪 / 首领掉落表全搬，抽数、权重、组都不变，抽法照 DarkArea：`rand = random(1, 总权重)`，组内等概率，有放回。枪池换成 `"@w<品质>"`，表示同档随机家族的兵刃；护甲池换成同档同部位的法衣。
   - 禁室玉钥：照 SPEC 3.5，箱子表 / 首领表另外独立掷一次。初级 / 中级物资箱 0.5%，沙漠 / 研究所物资箱 1.5%，首领表 30% 掉 1 把。
   - 仓库 14 级、段位 13 档（按 SPEC 改名）、货币起始值、各种奖励和惩罚常量、坊市 / 黑市货单。
   - 数值助手：`weapon_mult / armor_dr / chip_fx / atk_mult / wear_chips / repair_cost / death_drops`，PvP 按 1.25 / 22% 封顶。
2. **存档 `scripts/ex/ex_profile.gd`**：`user://xiuxian_ex_profile.json`。测试模式借用 `raid_profile.test_mode()`，测试档是 `..._selftest.json`，每次开机清空。新号自带首登礼。有局内锁 live（中途关游戏，下次开机按陨落结算，写 notice）。段位晋升加仙玉，并在主城播一次题字。所有 SPEC 3.8 的接口都已实现。
3. **物品视图 `scripts/ex/ex_item_view.gd`**：
   - 方格四周画品质色描边：永恒是轮换的七彩（名字跟着一起轮换），天启是金白双线。
   - 右上角自动写「×N」或装备的品质，法宝底下有一道耐久条。
   - 另有拾取小卡片、底栏说明文字。
   - 图标是用生图服务新出的 12 张类别图（玉、金器、古卷、灵晶、兽骨、丹鼎、剑、法衣、符、铜镜、命牌、明珠，白底已转透明），加上老图标。
4. **大厅界面 `scripts/ex/ex_lobby_ui.gd`**：
   - 七个页签：备战 / 仓库 / 商人 / 坊市 / 黑市 / 英雄 / 段位。
   - 外壳照 abode_ui，手机优先：按钮高 62，放不下整块缩小。
   - 史诗以上的东西卖之前要再点一次确认，一键卖也一样。
   - 换英雄时主城里的主角立刻换：有 `player.set_hero` 就调用它。
5. **玩家牌 `scripts/player_plate.gd`**：主城和新图（`level == null` 或 `level.map_id ∈ {desert, lab}`）显示：
   - 英雄名，后面跟段位小字；
   - 右边写「灵石 242.3万」；
   - 不画修为弧，头像小朱印写段位的头一个字（炼 / 筑 / 结 / 元 / 化）；
   - 换了英雄，头像按英雄皮肤重拍（`HeroSkin.hero_key`）。

   老大世界的显示照旧，`--raid-shot` 回归见第 4 节。
6. **`scripts/hud.gd`**：在主城里，撤离结算后段位晋升了，右侧播一次段位题字（realm_banner，印上写「升」）。洞府按钮本身不用改：level_select 已经让它开新界面。
7. **自检 `scripts/ex/ex_lobby_selftest.gd`**（`-- --lobby-test`）+ 离线数据检查 `_tasks/extraction_refactor/tools/ex_data_check.gd`。

## 2. 文件清单

新建：
- `scripts/ex/ex_data.gd`（约 1660 行，其中生成段约 800 行）
- `scripts/ex/ex_profile.gd`
- `scripts/ex/ex_item_view.gd`
- `scripts/ex/ex_lobby_ui.gd`
- `scripts/ex/ex_lobby_selftest.gd`
- `assets/ui/icon_ex_{jade,gold,scroll,crystal,bone,bronze,sword,robe,talisman,mirror,tag,pearl}.png`（已在导入锁下 `--import`）
- `_tasks/extraction_refactor/tools/gen_ex_data.py`：生成 ex_data 的常量表。重跑：`python -I _tasks/extraction_refactor/tools/gen_ex_data.py`。起名 / 类别表在这个脚本里。
- `_tasks/extraction_refactor/tools/make_ex_icons.py`：加工图标，提示词也记在里面。
- `_tasks/extraction_refactor/tools/ex_data_check.gd`：离线检查。
- `_tasks/extraction_refactor/icons_raw/`：12 张原图，有 `.gdignore`。

修改：
- `scripts/player_plate.gd`：备份在 `backup/player_plate.gd.txt`。
- `scripts/hud.gd`：只加了 `_ex_rank_banner()` 和一处调用；备份在 `backup/hud.gd.txt`。
- **`_tasks/ui_kit/font_check.py`（这个文件不在我的归属里，请主控确认）**：原来只扫 `scripts/*.gd`，不扫 `scripts/ex/` 子目录，大家在 `scripts/ex/` 里写的汉字都补不进字库。我只改了一行，`glob` 改成 `rglob`，备份在 `backup/font_check.py.txt`。之后跑了 `--patch` 和 `--import`：补字字体从 82 字变成 238 字（14.9 KB → 56.8 KB），只剩一个 ✗（U+2717，在 shenshi_selftest 里，以前就补不上）。
- `assets/fonts/SourceHanSansCN-Normal.patch.ttf`：由 font_check 重新生成。

## 3. 公开接口（照实现写）

### 3.1 物品字典

```
{id, kind, name, q 1..8, value 单价（回收价，灵石）, n 堆叠数, …}
kind = sell | tag | weapon | armor | chip | med | revive | throw | key | ward | mat | voucher（voucher 只在黑市页显示，存档里记的是张数）
weapon: fam, pve, pvp（出手倍率）[, unique: true, da_name]
armor : slot 0 冠 / 1 衣 / 2 护腿 / 3 履, dr_pve, dr_pvp（这一件的减伤 0..1）
chip  : fx regen|shell|pierce, pve, pvp, dur, dur_max, base
med   : heal 立即回（条上点）, hot 每秒回, dur 持续秒, use_t 读条秒
revive: use_t；throw: fx blast|smoke|fire, dmg, r, t, dps
sell  : da_name, cat 图标类别, label 古墓专属/BOSS专属/箱子专属/无来源
tag   : owner
```

- 读档时 `fix_item` 会按表重算数值字段，所以改平衡不用迁移存档。只有法宝耐久 `dur`、命牌 `owner` 和堆叠数 `n` 跟着每一件走。
- id 写法：
  - 售卖物：`s01..s93`、`sx1..sx5`
  - 命牌：`tag`
  - 兵刃：`w_qingfeng_5`；独特兵刃 `w_u_goujian`
  - 法衣：`a_2_4`
  - 法宝：`c_pierce_6`
  - 药：`med_zhixue / med_lingguo / med_xiao / med_jinchuang / med_zhong / med_jiuzhuan / med_da / med_xuming`
  - 强心丹：`revive`
  - 符：`thr_lei / thr_tianlei / thr_yan / thr_huo`
  - 其他：`key / ward / voucher / m_*`

### 3.2 `ExData`（`const ExData := preload("res://scripts/ex/ex_data.gd")`）

```
# SPEC 3.6 要求的
roll(table: String, rng: RandomNumberGenerator, draws := -1) -> Array[Dictionary]   # 一件一件（n=1），含钥匙另掷
make(id: String, n := 1) -> Dictionary        # 认不出 → {}；"@w5" = 史诗随机家族兵刃
value_of(it) -> int        # ⚠ 这一格的合计（单价 × n；法宝按耐久折）。单件用 unit_value(it)
is_sellable(it) -> bool    # sell 或 tag：禁带入、计入带出价值
box_table(map_id, box_kind "weapon"|"supply"|"med", locked := false) -> String
    # desert → senior*/desertLocked*；lab → lab*/labLocked*；其他 → junior*；钥匙房的医疗箱用本图普通医疗表
mob_table(map_id) -> String                  # desertmonsterDrops / yanjiumonsterDrops / monsterDrops
boss_table(boss_id) -> String                # 认 BOSS_TABLES 的拼音 / 中文名，或者直接给表名；认不出 → superBossDrops
    # lingyou/凌幽 superBossDrops；jiangluo/绛罗 superBossDrops1；sandworm/沙渊巨虫 sandWormBossDrop；
    # lingying/凌影 yanjiuBossDrops1；lingying_night/凌影·狂潮/狂潮霸主 yanjiuBossDrops2；
    # dianbian/电鞭铁卫 yanjiuBossputong1；bingjiang/冰僵铁卫 yanjiuBossputong2；
    # tiequiong/twins/铁穹双卫 lvBuDiaoChanBossDrop

# 名字 / 颜色
Q_NAMES, Q_COLORS（场景上用）, Q_INK（纸面上用）, q_name(q), q_color(q, t := -1)（永恒轮换）, q_ink(q, t := -1), kind_name(it), desc(it)

# 价值 / 卖
unit_value(it), can_sell(it)（有回收价且 q<8）, sell_confirm(it)（q≥5）, extract_value(list) -> int, repair_cost(it)

# 堆叠 / 格子
STACK=20, STACK_SELL=10, BAG_CAP=30, stacks(it), stack_max(it), same_stack(a,b)
room_for(list, it, cap) -> int
add_to(list, it, cap) -> int 剩下没放下的个数（放进去的是拷贝）
count_id(list, id), take_id(list, id, n := 1) -> 实际拿掉几个, merge(list)

# 装备栏 / 战斗
empty_equip() -> {weapon:{}, armor:[{}×4], chip:[{}×3]}, fix_equip(v), equip_items(equip)
weapon_mult(it, pvp), armor_dr(equip, pvp)（PvP 夹 0.22）
chip_fx(equip, pvp) -> {regen 每秒点, shell 护体点, pierce 0..1}（耐久 0 的不算）
atk_mult(equip, pvp) = 兵刃 × (1+破军)，PvP 夹 1.25
wear_chips(equip, bar_dmg) -> 这次耗尽的法宝名   # 每 1 点真人伤害扣 10 耐久
death_drops(bag, equip, rng, stacks := 2) -> {drop, sell, chips, ward: bool}   # 直接改 bag / equip
usable(it)（med / revive / throw）, wearable(it), slot_of(it) -> ["weapon",0] / ["armor",部位] / ["chip",-1] / []
make_tag(owner) -> 命牌（名字「X的命牌」）

# 坊市 / 黑市 / 仓库 / 段位
SHOP_CATS, SHOP_CAT_NAMES, shop(cat) -> [{id, price}], shop_price(id), BLACK, black_price(id)
WAREHOUSE, wh_cap(level), wh_next_cost(level) -> [灵石, 凭证] / []
RANK_NAMES, RANK_NEED, rank_of(total), rank_name(i), rank_next_need(i)

# 常量
START_LINGSHI 1000000, START_XIANYU 300, XIANYU_BOSS 5, XIANYU_RANK 50, XIANYU_DOCTOR 20, DOCTOR_LINGSHI 1000000,
DEATH_LINGSHI 5000, DEATH_DROP_STACKS 2, WARD_KEEP 2, MOB_DROP_P 0.25, PVP_ATK_CAP 1.25, PVP_DR_CAP 0.22, CHIP_WEAR 10,
RAID_TIME 900, INVULN_T 10, NO_DROP_T 5, BOX_CD 180, KEY_ROOM_T 900, EXTRACT_T 5, KEY_P{…}, KEY_P_BOSS 0.3
原始表：SELL, UNIQUE, MATS, POOLS, TABLES, DA_BOSSES（DarkArea 首领血量 / 重生 / 表 / 抽数）, MED_DA, THROW_DA,
WEAPON_SHOP/VALUE, ARMOR_SHOP/VALUE, CHIP_BASE/DUR, WEAPON_PVE/PVP, ARMOR_SET_PVE/PVP, CHIP_REGEN/SHELL/PIERCE_PVE/PVP
```

### 3.3 `ExProfile`（`const ExProfile := preload("res://scripts/ex/ex_profile.gd")`）

操作类函数成功返回 `""`，失败返回原因文字。每次操作都立即存盘。局内（live 锁）时仓库操作一律返回 `LOCK`。

```
load_if_needed(); save(); data() -> Dictionary; test_mode() -> bool
lingshi(); xianyu(); add_lingshi(v); add_xianyu(v); spend(v) -> bool; spend_xianyu(v) -> bool; vouchers()
stash() -> Array; bag() -> Array; equipment() -> Dictionary; stash_cap(); wh_level(); in_raid()
upgrade_warehouse() -> String
move(src "stash"|"bag", i, dst, n := -1) -> String     # 部分放下也返回提示
equip(src, i) -> String（换下的放回原格）; unequip(slot "weapon"|"armor"|"chip", idx := 0) -> String（先背包后仓库）
sell(src, i, n := -1) -> String（得的灵石在 ExProfile.last_gain）; sell_all_sellables(src "stash"|"bag"|"all") -> int
sellable_sum(src) -> [堆数, 价值, 品质≥5 的堆数]
buy(shop_id, n := 1) -> String（先背包后仓库，放不下不买）; buy_black(id "key"|"ward"|"voucher") -> String
repair(src_or_slot "stash"|"bag"|"chip", i) -> String; sort_list(src) -> String
hero() -> String; heroes(); hero_ids()（hero_defs.ids()，没有就默认两位）; set_hero(id) -> String
entry_check() -> String   # 背包里有售卖物 → SELL_BLOCK 那句话
begin_raid(map_id) -> {bag, equip, hero}（深拷贝），写 live、stats.raids++
sync_live(bag, equip)      # 可选：局内隔一会儿把身上的东西记进锁（中途关游戏按这一份结算）
death_tag_ok() -> bool     # 灵石 ≥ 5000 才在死亡点掉命牌
end_raid(res)              # 见下
rank(); extract_total(); rank_of(total); rank_name(i); take_notice() -> String; take_rank_up() -> int（hud 用）
常量：PATH, TEST_PATH, VER=1, BAG_CAP=30, LOCK, SELL_BLOCK, HEROES_DEFAULT
```

`end_raid(res)` 的 res：

```
{ok, bag, equip, lost_chips, extract_value, kills, map_id, cause, 可选 lingshi_gain, xianyu_gain}
```

- 撤离成功：背包回到存档背包（不自动进仓库）。背包放不下的进仓库，仓库也满了就折成灵石。`extract_total += extract_value`（没给就按背包算），判定段位晋升：每升一档 +50 仙玉，写 notice 和 `_rank_up`。
- 不成功：扣 `min(5000, 灵石)`，stats.dead++。`lost_chips = true` 时清空法宝槽。
- 两种情况最后都把 live 置空。

### 3.4 `ExItemView`

```
icon_name(it) -> String; icon(it) -> Texture2D; ink(it) -> Color; badge(it) -> String
tile(it, size, selected := false, corner := "", note := "", empty_text := "") -> Button
card(it, size, key := "") -> Button          # 拾取卡片，照 item_view.card 的排法（高 ≥80 走大号）
detail_text(it) -> String
```

### 3.5 `ex_lobby_ui.gd`（extends Control）

```
signal closed; var font: Font
_set_tab(t)      # int 老编号：0 仓库 / 1 坊市 / 2 商人 / 3 备战 / 4 黑市 / 5 英雄 / 6 段位（hub_hall 只用 0 / 1）；
                 # String：prep / stash / trader / shop / black / hero / rank，或中文页名
var _tab: int（老编号）; tab_key() -> String; _close()
static func open(host: Node, tab := "prep") -> Control   # 别的入口用：挂上、暂停树、放鼠标，关掉时恢复
static func summary() -> String                          # 入境页那一行
static func hero_ids(); static func hero_def(id)         # 先试 HeroDefs.def_of(id)，再读 HEROES 常量，最后用内置的御剑 / 苍鸿
press_action(prefix) / press_body(prefix) / action_texts() / detail_line()   # 给自检用
```

## 4. 自检

| 命令 | 结果 |
|---|---|
| `"<godot>" --headless --path . --script res://_tasks/extraction_refactor/tools/ex_data_check.gd -- --data-check` | 每个池 / 表的 id 都造得出来（坏条目 0）。每张表抽 2000 次统计见日志 `logs/data_check.txt`，例如沙漠物资箱平均 36.7 万 / 次、研究所物资箱 53.6 万、钥匙房物资箱约 200 万、沙漠小怪 3.7 万、凌幽 8.1 万（其中售卖物 2.8 万，其余是兵刃 / 法衣 / 材料）。沙漠物资箱开出钥匙的比例是 1.65%，首领约 30%。满配永恒：打怪 ×2.34 / 减伤 40%，对人 ×1.242（封顶 1.25）/ 15%。买 / 卖 / 挪 / 扩容 / 黑市 / 撤离晋升 / 陨落掉落（护宝符保住两堆）/ 中途离线恢复（加 `--keep-profile` 再跑一次）都通过 |
| `python -I _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/D_lobby1 --resolution 1280x720 -- --lobby-test` | **全部通过（失败 0 项）**，日志 `logs/D_lobby1_out.txt` |
| `python -I _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/D_lobby_web --resolution 1280x720 --rendering-method gl_compatibility -- --lobby-test --touch` | **全部通过**。这一档的自检会强制用随包字体（`UiStyle.force_bundled`），截图里没有缺字方块 |
| `"<godot>" --headless --path . --quit` | 没有报错 |
| `python -I _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/D_raidshot --resolution 1280x720 -- --raid-shot`（老大世界回归，改过 player_plate） | **没跑完**。前半段正常：台阶、走、清怪、拾取、四个区域各一张截图，玩家牌照旧显示「化神期 / 战力 2716万 / 等级印 13」（`_shots/preview/raid_14_region.jpg`）。到坠魔谷那张截图时演示角色被打死，局结算掉了，`main.gd` 演示脚本接着访问已释放的 raid_manager 报错（`main.gd:4771` 的 `_raid_fps`、`main.gd:6635` 的 `rd._bosses`），之后卡住，我把自己这个进程结束了。这段不经过 player_plate / hud；是演示流程本身的问题，可能和别的模块改战斗数值有关。请主控 / H 在整合时再跑一次 |

`--lobby-test` 依次测了这些：
- 新号首登礼；
- 主城玩家牌显示「御剑 未入流 灵石 100万」；
- 洞府按钮（hud._open_abode）打开的是新界面，打开时暂停；
- 七个页签各截一张；
- 坊市买药 ×10 和买史诗破军锤；
- 穿戴，并确认换下的那件回到背包；
- 卸下 / 穿回法衣，存进仓库 / 从仓库带上；
- 售卖物进了背包时入场检查拦下，单卖一个；
- 史诗售卖物卖之前要二次确认，一键卖神话售卖物也要二次确认；
- 仓库扩容（5 万）；
- 黑市买钥匙 + 凭证（160 仙玉）；
- 买法宝、穿上、被真人打掉 40 点耐久、修理（1 万）；
- 换英雄苍鸿，`player.hero_id` 也变成 canghong；
- 模拟一次撤离：段位升到炼气一阶，+150 仙玉，主城题字；
- 老接口 `_set_tab(0/1)`；
- 门 2 入境页：「开始匹配」被拦下，「备战」开的是新界面，在里面卖掉售卖物后可以进。

## 5. 截图（只看 jpg）

`_shots/preview/` 下，桌面档以 `lobby_` 开头，网页档以 `lobby_web_` 开头。主要几张：

| 内容 | 文件 |
|---|---|
| 七个页签 | `lobby_tab_{prep,stash,trader,shop,black,hero,rank}.jpg` |
| 坊市兵刃 | `lobby_shop_weapon.jpg` |
| 备战被入场检查拦下 | `lobby_prep_blocked.jpg` |
| 法宝耐久条 | `lobby_prep_chip_worn.jpg` |
| 商人二次确认 | `lobby_trader_confirm.jpg` |
| 英雄页 | `lobby_hero_canghong.jpg` |
| 段位晋升后 | `lobby_tab_rank_after.jpg` |
| 主城玩家牌 | `lobby_hub_plate.jpg` |
| 段位题字 | `lobby_hub_rank_banner.jpg` |
| 入境页：拦下 / 备战 | `lobby_entry_blocked.jpg`、`lobby_entry_prep.jpg` |
| 图标小样 | `_tasks/extraction_refactor/logs/icons_sheet.jpg` |

## 6. 对 SPEC 的解读和自己定的东西

- **法衣减伤**：SPEC 3.4 给了 8 个数（0, 4 … 40%）。我按「0 档 = 没穿，1..7 档 = 普通..永恒」读，所以普通全套就有 4%。每件 = 全套 / 4。
- **天启装备**：法宝有天启档（q8）。兵刃 / 法衣的天启是 DarkArea 的配方系统，本轮不做。
- **炼器材料**：新增 kind `mat`，原因见第 1 节。E 的局内背包把它当普通物件就行：能捡、能丢、能卖，不能用也不能穿。
- **命牌**：`kind = tag`，价值 5000。算售卖物：禁止带入、计入带出价值、可以卖。名字用 `make_tag(owner)` 生成，例如「X的命牌」。
- **护宝符**：死亡时，只有掉落池里确实有售卖物才会消耗。≤2 堆时全保，同样消耗一张。
- **掉命牌的条件**：照 SPEC 写「够 5000」，用的是 `灵石 ≥ 5000`。DarkArea 原文是「>5000 才掉」。
- **仓库凭证**：存档里记的是张数 `vouchers`，不是背包里的物品。黑市页上显示成一件「仓库凭证」。
- **卖东西**：商人收所有回收价 > 0 且不是天启的东西（兵刃 / 法衣按 DarkArea 的象征价，法宝按耐久折），售卖物在「商人」页集中卖。不能卖的：钥匙、护宝符、天雷符、天启配方。
- **买东西**：坊市买的东西先进背包，满了进仓库，两边都放不下就不扣钱。
- **英雄**：全部免费。`set_hero` 接受英雄表里的任何 id。
- **存档 notice**：读档恢复和段位晋升写的提示会拼接起来，大厅界面打开时显示一次。

## 7. 已知问题 / 没做的

- 老大世界回归 `-- --raid-shot` 没跑完（第 4 节表格最后一行）：演示角色在坠魔谷被打死，之后演示脚本访问已释放的管理器报错卡住。玩家牌在老大世界走老逻辑（`_ex_mode()` 为假），截图上显示正常。
- 英雄页没有立绘或模型预览，只有文字卡。
- 坊市兵刃全是剑图标，只有镇岳印换成丹鼎；家族之间只靠名字区分。
- 在 Windows 桌面上，网页那一档要强制用随包字体才能看到真实字形。自检会自动打开；平时预览要自己设 `UiStyle.force_bundled`。
- 补字字体是按「所有 scripts 下的字符串」生成的。别的代理以后改了文字，要再跑一次 `font_check.py --patch` 和 `--import`（现在会扫 `scripts/ex/` 了）。

## 8. 给 E（extract_manager）的说明

1. **开局**：
   - `_ready` 里先 `ExProfile.entry_check()` 兜底，不为空就提示并退回大厅。
   - 再 `var r := ExProfile.begin_raid(level.map_id)`，`r.bag` / `r.equip` 就是局内背包和装备栏（深拷贝，随便改）。
   - `r.hero` 是英雄 id，主控已经在 main 里调过 `set_hero`。
2. **箱子**：`ExData.roll(ExData.box_table(map_id, kind, locked), rng)` 返回一件一件的物品，直接逐件喷到地上。禁室玉钥已经包含在结果里。
3. **怪**：
   - 小怪：`if rng.randf() < ExData.MOB_DROP_P: ExData.roll(ExData.mob_table(map_id), rng)`。
   - 精英：必抽一次。
   - 首领：`ExData.roll(ExData.boss_table(id), rng)`，抽数照表（凌幽 16、铁穹双卫 48 …），击杀者另外 +`XIANYU_BOSS` 仙玉。仙玉放进 `end_raid` 的 `xianyu_gain`，或者直接 `ExProfile.add_xianyu`。
   - AI 修士的储物袋：`ExData.roll(ExData.box_table(map_id, "supply"), rng, 2)`。
4. **伤害**：
   - 出手倍率：`ExData.atk_mult(equip, pvp)`，PvP 已经夹在 1.25 以内。
   - 受击减伤：`(1 - ExData.armor_dr(equip, pvp))`，PvP 已经夹在 22% 以内。
   - 法宝效果：`ExData.chip_fx(equip, pvp)` 返回 `{regen 每秒回血点, shell 进图护体点, pierce}`。
   - 挨了真人伤害：调 `ExData.wear_chips(equip, 条上点数)`。
5. **背包**：
   - 放东西：`ExData.add_to(bag, it, ExData.BAG_CAP)`，返回值大于 0 就是放不下。
   - 用钥匙：`ExData.count_id(bag, "key")` 看有没有，`ExData.take_id(bag, "key", 1)` 扣一把。
   - 判断能做什么：`ExData.usable / wearable / slot_of`。
   - 药的字段：`heal`（立即回）/ `hot`（每秒回）/ `dur` / `use_t`。符的字段：`fx`（blast / smoke / fire）、`dmg`、`r`、`t`、`dps`。
   - 界面：拾取卡片用 `ExItemView.card(it, Vector2(160, h), "T")`，格子用 `ExItemView.tile`，说明用 `ExItemView.detail_text`。
   - 带出价值：`ExData.extract_value(bag)`。
6. **死亡**：
   1. 先问 `ExProfile.death_tag_ok()`，再调 `var d := ExData.death_drops(bag, equip, rng)`（它会把掉的东西从 bag / equip 里拿走，护宝符也会自动生效）。
   2. 遗物箱装 `d.drop`，加上 `ExData.make_tag(名字)`（灵石够的话）。
   3. 调 `ExProfile.end_raid({ok = false, bag, equip, lost_chips = true, extract_value = 0, kills, map_id, cause})`。5000 灵石由 end_raid 扣，E 不用再扣。
7. **撤离**：调 `ExProfile.end_raid({ok = true, bag, equip, extract_value = ExData.extract_value(bag), kills, map_id, cause = "extract", lingshi_gain, xianyu_gain})`。营救天工师的奖励：`lingshi_gain += ExData.DOCTOR_LINGSHI`，`xianyu_gain += ExData.XIANYU_DOCTOR`。
8. **中途离线**：不用 E 管。想让离线结算更准，可以每隔 10~20 秒（或捡到东西时）调一次 `ExProfile.sync_live(bag, equip)`。
9. **玩家牌**：在新图里不读 `plate.raid` 的 lv / fx，E 设不设都可以。
