# W2a 实现报告：新两关跑修仙局内循环（管理器这一侧）

2026-11-25。按 CONTRACT 第 3、4 节和第 6 节 W2a 名单做。只用 Edit 改了自己名下的文件（新文件用 Write），备份在 `_tasks/decouple/backup/*.W2a.txt`。没有 commit。

## 结构

- **geo 转接层**（两份同名方法，都没有 class_name，用 preload）
  - `scripts/raid_geo.gd`（新文件）：大世界这份，直接转调 Data / Prog（near / near2 / on_land / region_of / depth_of / where_name / gates_free=2 / zone_k 恒为 1）。`loop=true fixed=false own_atmo=false`。
  - `scripts/ex/ex_geo.gd`（新文件）：新图这份，数据来自 ex_level 和 map_def。
    - near 恒等，on_land 取 play 矩形。
    - region_of 取 (图, 层) 的 zone ri。
    - depth_of：到最近出生点（地下层另算光井）的距离 / depth_r，封顶 0.8；地下层再加 0.25；钥匙房和首领场地取 1.0。只看位置。
    - zone_k 返回 `{hp, atk, bonus, xp}`。
    - floor_y 用 floor_at；spot_near 用 find_spawn_near，找不到返回 INF。
    - mob_pool 取 CAMP_POOL 的统一编号；gates / lairs / boss_gate_at / rift_spot / camp_points 都取点表。
    - search_points：箱子转成老搜点：supply 转 jar、med 转 herb、weapon 转 grave。用固定种子洗牌、隔 22 米抽稀；每间钥匙房出一个 vault，每个首领场地边出一个 urn。搜点的 y 用点自己带的高度。
- `raid_manager.gd`
  - `_ready` 里按关卡建 geo：关卡有 `points()` 就用 ExGeo，否则用 RaidGeo。另加了 `var geo`、`var map_id`。
  - 凡是 `if geo.fixed:` 的分支都只给新图用。大世界的代码要么原样不动，要么换成结果完全一样的写法：`lid == region`；`_floor` 在大世界就是 `_ground`；`geo.near` 就是 `Data.near`；`gates_free` 等于 2。

## 改了什么（file:line 是改完之后的行号）

### scripts/raid_data.gd
- :213-227 加了 `EX_BASE := 100`（等于 W2b 的 ExMobs.NET_BASE）、`mob_def(i)`（i >= 100 时取 ExMobs.by_idx(i-100)）和 `ex_def(id)`。
- 联机协议没变：大世界编号还是 0..14，新图房间里编号都 >= 100。

### scripts/ex/map_def.gd（只加不删）
- :221 `_xiu()` 写入以下三项：
  - `min_realm = 3`
  - `zone[surface|cavern] = {ri, hp, atk, bonus, xp}`
  - `xiu = {depth_r, gates_free, sites}`
- 沙漠：地面 ri 2、洞窟 ri 3，倍率 ×1.2，加成 +0.3，depth_r 260，每轮 1 座免费阵 + 1 座灵石阵；搜点数 jar 10 / herb 6 / grave 8。
- 研究所：地面 ri 3、地下室 ri 4，倍率 ×1.35，加成 +0.5，depth_r 300，每轮 2 座免费阵 + 1 座灵石阵；搜点数 jar 12 / herb 6 / grave 10。

### scripts/raid_manager.gd
- `_ready`：
  - 新图跳过 pending_dug / pending_blasts（破坏走 Destruct 自己的同步）。
  - 刷怪点改成 `camps.use_points(geo.camp_points())`，并且 `camps.on` 恒为真。
  - 标题用图名，副标题写层名和这里的妖兽档。
  - 新图的区域按 `level.spawn_point()` 算：这时主角还没被挪到出生点。
- :354 加 `_floor(x,z,y)`：新图用 floor_at，大世界用 _ground。下列位置都改用它：掉落、搜得箱、储物袋、破界符、渡劫落地、settle_drops。
- :361 加 `_mob_def`；:366 加 `zone_k`；:371 加 `where_name()`（raid_hud 读）；:378 加 `_fixed_sub`。
- depth_of 和 level_at 改走 geo。
- net_mob_apply：
  - 木偶的 def 用 `_mob_def` 取，新图的木偶设 block_fn。
  - 巢穴匹配改成 lid。
  - 新图首领先 `_xb_saw` 判撞车（编号小的留），木偶挂 `ExBoss.attach_remote`。
  - 新图首领不受「一批最多新建 3 只」的限制。
- net_mob_batch 和 _my_mobs：新图把首领排在最前，双卫的两只都算进去。
- net_mob_take：新图首领加 `accept_hit` 判定，战斗区外打的不算。
- net_mob_died：新图走 `_xb_gone`；分心得时乘上心得倍率。
- `_lair_cleared` 和 `_light_boss_gate` 改按 lid 匹配（镇守阵记 `"lair"`）；大世界 `_bosses` 补了 `"lid": ri`。
- `_try_start_trib`：新图的洞窟和地下室里不起劫，提示「出洞之后再渡劫」，破境丹和灵石都不扣。
- `_process`：新图不调 `_blend_atmosphere`，改走 `_fixed_region_tick`（:1443：换层或换档时题字，重置压制提示和越档提示）；`_reimage` 只在 `geo.loop` 为真时做。
- :1522 `_setup_fixed_pois`：
  - 古传送阵取 points("extract")，名字是「沙海古墟·E1传送阵」这种。
  - 每个 points("boss") 建一座巢穴（不搭残柱和光柱，免得在洞窟里穿顶），旁边一座镇守阵。
  - 钥匙房的门在本地一进图就全打开。
- `_rotate_gates`：免费阵的座数取 `geo.gates_free()`。
- `_spawn_mob`：
  - 凝胶怪 elite_only 强制为精英。
  - 新图在老公式外面乘 hp / atk 倍率，设 `block_fn = level.blocked`；loot 为 false 的怪 xp_k 置 0。
- `_update_bosses`：新图走 `_xb_update`。
- 新图首领一节（:1860-2140，从 extract_manager 搬过来、数值换成老公式）：
  - `_xb_by_lair` / `_xb_alive` / `_xb_mine` / `_xb_adopt` / `_xb_saw` / `_xb_puppet` / `_players_in` / `_room_count`
  - `_xb_spawn`：
    - 等级 = Prog.boss_level(lair_tag(ri), 当地 + 2)。
    - 血量按老公式，再 × players_k(n) / players_k(1)。
    - 挂 `ExBoss.attach(..., pts_k = m.atk / atk_pts, players = n)`。
    - summon_fn 刷出来的召唤物打上 `summoned` 标记，不给心得、不掉东西。
  - `_xb_go` / `_xb_request`：联机时走 `net.ex_boss_claim`。
  - `net_ex_boss_owner` / `net_ex_boss_dead` / `net_ex_boss_fx` / `_send_boss_fx` / `_xb_event` / `_xb_gone`
  - `_xb_died`：双卫两只都倒了才掉。
    - 掉落：`_loot(ri, 5 或 6, 1.3 或 1.4 + 加成)` + 破境丹残片 + 霸主精魄（按 OVERLORD_P）。
    - 冷却：world_t + respawn，然后 `net.ex_boss_dead`，镇守阵亮起。
  - `_xb_update`：110 米内自动刷。
  - 巢穴编号：`lair = lid × 2 + 第几只`。大世界仍是 lid == region，联机包不变。
- 刷怪导演：新图没有「天地异动」游荡首领（首领都在巢穴里）。
- :2267 `_spawn_guards_fixed`：守卫取本图的怪池，落点问关卡。
- AI 修士和喂怪：新图落点走 `geo.spot_near`，找不到就跳过；区域走 geo。
- `_on_mob_died`：落脚用 `_floor`；新图乘心得倍率和掉落加成，召唤物不掉东西，巢穴首领转 `_xb_died`。
- site_loot、`_on_rival_died`、`_open_rift`（新图用 `geo.rift_spot`）、破界符（新图出了战区不让起阵）都改走 geo。

### scripts/raid_camps.gd
- :55 加 `list_mode`。
- :65 `use_points(pts, map_id)`：照 extract_manager.Camps 写。
  - 种子 = hash(图) + 7919·i + 104729。
  - defs 存统一编号，ri 取 `geo.region_of`，点里存 y。
- tick：点表模式遍历所有点，高差 40 米以上不建。状态机一行没改。
- near / near2 改走 `mgr.geo`。
- `_build`：点表模式下怪按点自带的 y 落脚（`mgr._floor`）。
- 精英提示的名字改用 `Data.mob_def`。

### scripts/raid_search.gd
- :59 `_place_points()`：从 `geo.search_points()` 建搜点（带 `fixed_y`）。
- tick：点表搜点不换像、不重新落地。原来那段抽成 `_reimage_site`（:180），逻辑不变。
- `_finish`：jar / grave / vault / urn 的 `Items.roll` 加上新图的掉落加成。

### scripts/raid_hud.gd
- :666 地名改问 `mgr.where_name()`（新图显示「沙海古墟·地下洞窟」）。

### scripts/minimap.gd
- :363 固定底图模式下，只画 `mgr._extracts` 里亮着、同一层的那几座，按种类着色，裂隙另有外圈；不再画常亮的点表撤离点。
- 没有 raid_manager 时照旧（extract_manager 的条目没有 `active` 字段，按亮着处理）。

### scripts/ex/ex_level.gd
- :28 `MANAGER_PATH` 改成 raid_manager.gd；不设 lethal / regen 钩子。
- :208-216 境界守卫：低于 min_realm 时提示「X凶险 · 元婴期方可入内（你现在是Y期）」，不建管理器（存档里的法宝和随身物都不动），2.5 秒后发 exit_requested（`_leave_soon`，:233）。另加 `realm_blocked`。
- `_clamp_mobs`：木偶也夹在洞顶下面。
- map_marks（大地图）：有 `raid._extracts` 时只画亮着的撤离点，不再标钥匙房。

### scripts/xiu_map_selftest.gd（新文件）
main 里 W3 已经接好：`-- --level-test desert|lab`。另有两个模式：
- `--level-test mulan [--camps]`：大世界回归。
- `--level-test desert --xiu-lan=host|join`：局域网双开，测试端口 +100，可以加 --headless。

## 测试（都是 headless，`D:/ugc-ai/tools/godot/Godot_v4.7.2-stable_win64_console.exe`）

- 改过的 11 个脚本单独 `--check-only`：全部通过。
- **`--level-test desert`：21/21 PASS，用时 38 秒**
  - 境界守卫：结丹被拦下，没建管理器，回到主城。
  - 进图：挂的是 raid_manager，geo 是新图那份；没有 lethal 钩子，regen_k 为 1。
  - 点表：刷怪点 34/34 进了点表模式；搜点 jar 10 / herb 6 / grave 8 / vault 2 / urn 3；古传送阵 4 座亮 2（灵石阵 1）；镇守阵 3；巢穴 3；钥匙房里的搜点深度为 1。
  - 帧耗（headless，进图后 4 秒）：平均 6.9 ms。
  - 地面刷怪点：档 2 ×1.2，沙漠狼 Lv.11（档内 10~14），血 534107 / 攻 132127，和老公式 × 倍率完全一致。
  - 杀怪心得：+4287，和 kill_exp × 1.2 吻合，刷怪点记死。
  - 洞窟刷怪点：档 3 ×1.2，毒尾蝎 Lv.16（13~17），吻合。
  - 神识一扫：揭示 4 个。
  - 搜陶罐：出了青竹蜂云剑（gear），拾进背包。
  - 首领：凌幽走近自动刷出，Lv.12，挂了 ExBoss，pts_k 2.3e4；打死后巢穴记空，遗藏 6 件含残片，镇守阵亮，600 秒后重生。
  - 撤离：E1 古传送阵读条 5.6 秒，背包 7 件进仓库 7 件，回到主城。
  - 陨落：仓库 7 件不变，法宝清空，储物戒 1 件保住，陨落次数 0 变 1，回到主城。
- **`--level-test lab`：21/21 PASS**
  - 刷怪点 36；vault 10、urn 4；古传送阵 8 座亮 3（灵石阵 1）。
  - 地面：尸傀 档 3 ×1.35 Lv.14；地下室：尸傀 档 4 Lv.19/20（16~24）。
  - 电鞭铁卫刷出后能打死，遗藏 7 件，500 秒后重生；撤离和陨落都通过。
- **局域网双开 desert**（两个 headless 进程，测试端口偏移 100，不碰用户正在玩的房间）：host / join 各 3/3 PASS。
  - 双方都看见了对方。
  - 凌幽只有一只：房主是真身（主人 1），加入方是木偶，名下首领 0 只。
  - 加入方站在房主建着的刷怪点边上：自己名下 0 只，看到 9 个别人名下的木偶。
- **大世界回归**
  - `--level-test mulan`：10/10 PASS。
    - geo 是 raid_geo，loop 为真。
    - 5 座巢穴的 lid 都等于区域。
    - 古传送阵 5 座亮 3（灵石阵 1），镇守阵 5。
    - 刷怪点是网格模式；测试模式下是老导演，和以前一样。
    - 搜点 96 个，地名「木兰草原」。
    - 狼王 Lv.3，血 90650 和公式吻合，lair 为 0，没有 block_fn；打空后镇守阵亮。
    - 怪都是老表的编号。
  - 加 `--camps` 再跑：10/10，网格刷怪点建了 22 只。
  - `-- --raid-shot`（run_hidden，Forward+）整局跑完，没有 SCRIPT ERROR：五区巡游、巢穴首领墨蛟、游荡首领、修士、开箱、服丹、撤离结算、回到大厅都正常。
  - `-- --raid-shot --raid-econ`：在 raid_selftest.gd:92 报错 `Nonexistent function '_select' in base 'Control (meta_ui.gd)'`。这是洞府界面那段（W3 把洞府换成了 meta_ui），出错时还没进大世界，和我的改动无关。

## 需要别人改
- **W3（或 raid_selftest 的维护者）**：raid_selftest.gd:92 还在调 abode 的 `_select`，现在 `open_abode` 打开的是 meta_ui，`--raid-econ` 因此报错。需要改成 meta_ui 的接口，或者按 CONTRACT 第 5 节随 W3 的界面测试一起改。
- **W2b（ex_mobs）**：首领的 `hp` / `atk` 还都是 1.0，现在凌幽的血是 70 × 1 × … 。报告 B §3.4 有各首领的倍率，填上就生效，我这边不用改。召唤物 wraith 我按 `loot == false` 处理：xp_k 置 0、不掉东西。
- **shen_shi.gd（不在任何人名下）**：`_sources` 里 `get_meta("beam", null)` 在 Godot 4.7 下，没有 beam 的搜点会刷 `ERROR: ... key 'beam'`。大世界一直就有，不影响功能。建议改成 `get_meta("beam") if has_meta("beam") else null`。
- **W3（main）**：新图的 warmup tag 按 W2b 那边定的走。我这边 `raid_manager.region` 和 `_spawn_mob(老编号…)` 在新图上照样能调（会乘倍率、带挡墙）。

## 已知问题 / 没做的
- 新图没有「天地异动」游荡首领（`_director` 里 `not geo.fixed`），首领都在巢穴里。夜袭怪潮、天工师、读条开门 / 开箱、救人按契约不做。
- 沙暴（ex_level `_env_hurt`）走兜底：不致死，最多扣到 1 点。raid_manager 没加 `env_damage`。
- AI 修士（air_foe）没有 block_fn，在研究所能穿墙。这是既有问题，extract_manager 也一样。
- 怪的 floor_fn 还是只认地形（和 extract_manager 一致），楼上没有刷怪点。掉落、搜点、撤离点、储物袋都已经按 floor_at 落脚。
- 新图的大地图里首领、洞口、地名的标记照旧，钥匙房的标记去掉了（门常开）。
- 双卫各自的血量还没减半（等 W2b 填倍率）；遗藏件数用 6 件、加成 1.4。
- 数值（首领 pts_k、搜点数量、depth_r）只按契约给了第一版，杀怪节奏和收益没有用 `--raid-pace` 实测过。帧耗只在 headless 下记了，渲染下和手机档都没量。
- 新加的汉字（提示文案）要负责人统一跑 font_check。
