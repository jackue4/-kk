# impl_W1：英雄 + 存档（2026-11-25）

按 CONTRACT 第 1、2 节和第 6 节 W1 的文件做完。备份都在 `_tasks/decouple/backup/<文件名>.W1.txt`。没有 commit / push / 切分支，没动 scripts/heroes/* 和 air_melee.gd。

## 改了什么

### 战斗数值：英雄跟着境界走
- **scripts/player.gd**
  - `:107-110` 注释改成「数值跟境界走，英雄只叠外观键 + art + LIGHT」；删掉 `_realm_req`。
  - `:390-394` `set_realm()`：不再在英雄档下早退；`realm = _hero_realm() if hero_id != "" else Realm.LIST[realm_idx]`，其余（灵力回满、_realm_fx、结婴演出、realm_changed）照旧。
  - `:439-441` `set_hero()` 注释；`:472` 英雄分支删掉 `realm_idx = HeroDefs.TIER` 和那段整表覆盖 / speed / blink，改成 `realm = _hero_realm()`。`CS.heroes_on = id != ""` 保留（只给画面用）。`set_hero("")` 老路径没动。
  - `:492-494` `hero_base()` 改成 `return float(realm["dmg"])`（= CS.base(realm_idx)，英雄和老角色同一口径）。
  - `:497-511` 新增 `HERO_LOOK_KEYS = [lines, col_a, col_b, style, motes, width, swords]`、`HERO_SPEED_MIN = 28.0`、`_hero_realm()`：底子是 `Realm.LIST[realm_idx].duplicate()`，叠英雄 def.realm 里的外观键，`art` 取 def，`mode = LIGHT`，`speed = max(境界遁速, 28)`；blink / blink_spd / boost / rise / ceiling / dmg / mp 都跟境界。
- **scripts/combat_stats.gd** `:226-245`：删掉 `pvp_hit` 和 `pvp_cap_k` 里 `if heroes_on` 的两段，PvP 回到每档 ×1.08；`heroes_on` 留着，注释改成「只给画面判断用」。
- **scripts/enemy_dummy.gd** `:120-130`：删掉 `HERO_PVE_UNIT` 和英雄专用的飘字分支，英雄 / 老角色都按修为折（`CS.unit_same`）。
- **scripts/hero_defs.gd**：头注释、`fly_speed / realm` 字段说明改掉；删 `BASE`；`TIER := 2` 留着（`:38`），注释写明只管展台方块人穿哪档衣服（_tasks/tsb/canghong/pose_gallery.gd、_tasks/ui_comic/comic_figure.gd 还在用）。
- 三位英雄之间没加任何倍率。

### 存档：raid_profile 新接口（scripts/raid_profile.gd）
- `:17-18` preload hero_defs（hero_defs 只 preload heroes/def_*，def_* 不 preload 任何东西，不成环）。
- `_fresh` `:56-62`：stats 改用 `_fresh_stats()`，加 `"hero": HeroDefs.DEFAULT`。
- `:65-71` `STAT_KEYS = [raids, out, dead, best, kills, pk_kills, arena_wins]`、`_fresh_stats()`。
- `_fix_types`：stats 缺的键补 0、float 转 int；`hero` 不是字符串或 HeroDefs 不认识 → DEFAULT。
- 新函数（`:308-348`）：`stats()`、`add_stat(key, n := 1)`（存盘）、`add_lingshi(n)`（可负、不低于 0、存盘）、`hero()`、`hero_ids()`（= HeroDefs.ids()，全部免费）、`set_hero(id)`（成功 ""，局内 RAID_LOCK，不认识的 id 返回「未知英雄」，成功存盘）。
- 没升 VER，已有接口签名一个没动。

### 界面 / 联机
- **scripts/ex/hero_select_ui.gd**：`ExProfile` 换成 `Profile := preload(raid_profile)`（`:23`），`hero_ids / hero / set_hero` 三处（`:196 / :201 / :1135`）照换；展台方块人装束改用 `Profile.realm()`（`:479`）。
- **scripts/ex/hero_doll.gd**：加 `Profile` preload（`:10`），小像装束用 `Profile.realm()`（`:191`）。本来就不碰 ExProfile。
- **scripts/player_plate.gd**：删掉 ex 模式整套（EX_PROFILE / EX_MAPS / HERO_NAMES、`_ex*`、`_ep`、`_rank_l`、`_pw_l`、`_badge`、`_ex_mode()`、`_apply_mode()`、`_hero_info()`、`_refresh_ex()`），主城和所有图一律走老的境界 + 战力 + 修为弧 + 修为等级朱印。新增 `_sync_skin(p)`（`:349`）：`player.hero_id` 变了才按 `hero_def.skin` 重拍头像（英雄系统关着 = 默认皮肤），`refresh()` 第一行调它。cbb6ec9 在这个文件里别的改动（墨玉样式、战力万 / 亿短写、受击闪白、高光）都是界面重做，不是砍功能，所以保留。
- **scripts/remote_player.gd**：新增 `static func realm_tag(realm, lv)` →「元婴期 第2层」（`:175`，层 = lv − 境界×3）；名牌 `_refresh()` 一律写「【队友】名字 · 英雄 · 元婴期 第N层」（没英雄就不写英雄名）。
- **scripts/lan_presence.gd**：删掉 EX_PROFILE / `_exp`；包格式不变，段位那一位固定发 -1（`:154`），境界 / 等级本来就在包里；`_label()`（`:264`）改成「名字 · 英雄 · 元婴期 第N层 · 状态」，不再读段位。
- **scripts/arena_duel.gd**：只加了一行，`_finish` 赢了时 `Profile.add_stat("arena_wins")`（战绩卡要用）。

### 自检
- **scripts/hero_selftest.gd**：新增 `--hero-test=realm`（`_realm_test()`，`:629` 起，无头可跑）；老套件（`--hero-test=old`）里「数值档结丹」改成「base 跟境界」，木人桩飘字改成「英雄 = 老规矩」。
- **scripts/pvp_rules_selftest.gd**：`scen == "hero"` 时也照样 `set_realm(--pvp-realm)`（以前被吞掉、两边实际都是结丹），注释提醒两个窗口要给同一个 `--pvp-realm`。文件里没有写死的期望数，不用改。
- 新文件 **_tasks/decouple/w1/profile_api_check.gd**（SceneTree 小脚本）：核对 raid_profile 新接口和名牌文字，走自检存档、不碰玩家的档。

## 怎么测的、结果
1. 12 个改过的脚本逐个 `--check-only`：全部没报错（arena_duel 也过了）。
2. `Godot --headless --path . -- --hero-test=realm` → **结论 PASS**：
   - 表：炼气 / 结丹 / 炼虚 / 大乘 下三位英雄的 base 分别是 [8,8,8] / [18,18,18] / [52,52,52] / [110,110,110]，和老角色一样；air._base、灵力上限 = CS.mp_max、遁速 = max(境界, 28)、闪现距离跟境界、恒为光遁、丝线是英雄配色，全部对上。
   - 实打试剑台木桩，M1 头一招：镇岳 炼气 4.00 → 炼虚 26.00；苍鸿 3.60 → 23.40；霜华 4.00 → 26.00。三位炼虚 ÷ 炼气都是 **6.500**（= 52 / 8），「伤害 ÷ base」各自等于自己的招式单位（0.5 / 0.45 / 0.5），和境界无关。
   - PvP（heroes_on = true）：炼虚打元婴是炼虚打炼虚的 ×1.1664（= 1.08²），封顶倍数也是 1.1664。
   - 木人桩飘字：英雄档 = 老规矩（元婴、原始 26 → 都是 103427.7）。
3. `--headless --script res://_tasks/decouple/w1/profile_api_check.gd -- --w1-check` → **PASS 13/13**（默认英雄、全部三位、set_hero 成功 / 未知英雄 / 局内锁、stats 新键、add_stat、add_lingshi ± 和下限 0、_fix_types 回落 / 补键、名牌「元婴期 第2层」「炼气期 第1层」）。
4. `--tsb-show=yujian / canghong / shuanghua`（无头）：三位都跑完，各招单位和改之前一样（单位口径跟境界无关，自检存档开机是炼气，四技能照样能放）。
5. 双开 `--pvp-rules=hero --pvp-realm=3`（苍鸿 vs 霜华，自检端口 +100）：两边都在元婴（灵力上限 106），a 那边 air_hit 18 次，b 掉血 52 点，PvP 伤害正常流通。
6. 玩家牌小样 `_tasks/ui_kit/plate_test.gd` 截图 `_shots/preview/plate_w1.jpg`：老的境界 / 战力 / 修为弧 / 朱印显示正常。

## 遗留 / 风险
- **mash 剧本打不到人**：双开 `--pvp-rules=mash` 时 a 一直在 26 米外原地出拳（结丹、元婴一样，改之前也是结丹），所以掉血 0。原因是这个剧本是给老御剑的长距离吸附写的，镇岳的 M1 不会扑 26 米；跟这次改动无关，要量还得先让 a 贴上去（剧本归格斗专项）。
- 跑自检的时候别的代理正在改 warmup.gd / raid_manager.gd，日志里有他们文件的 Parse Error（`_ex_mgr_fx`、`CREATURE`、`_fixed_layer`、`_xb_*` 之类），不是 W1 的文件。等他们改完，最好再跑一遍 `--hero-test=realm`。
- **玩家牌在真游戏里换英雄后重拍头像**这一步只核了代码，没在窗口里截图（main / hud 正在被 W3 改）。
- 报告 C 的 R1 / R2 照旧：Realm.COMBAT 的击退档、flair 现在会按真境界作用到英雄身上（炼气 kb 0.8 → 大乘 1.72）；要不要压归格斗专项（air_melee），这次没动。
- 联机协议没改，但对方的伤害现在按对方真境界发过来：局域网里两边要一起换新包。
