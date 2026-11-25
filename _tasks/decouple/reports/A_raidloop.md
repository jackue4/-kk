# A · 老局内循环（raid_manager / raid_camps / raid_search / shen_shi / raid_hud）搬上两张新图的调研

只读调研，没改任何项目文件。行号按 2026-11-25 主干（raid-block-world，5c25796）。

---

## 0. 一句话结论

老循环对「关卡 / 世界」的依赖面其实很窄：`level` 只用到 `env / sun / world / motes / ground() / exit_requested`，
真正的耦合点是 **raid_data.gd（Data）里那几个「大世界几何」静态函数**（`near / near2 / land_r / region_at / region_weights / pois / PLAY_R`）
和 **progression.gd 的 `depth_at`**，再加上若干处 `Data.REGIONS[ri][...]` 取怪池 / 名字 / 光色。
extract_manager.gd 已经做过一遍「raid_mob + 刷怪点状态机搬到点表」的移植（内部类 `Camps`，extract_manager.gd:481-860；
`_mob_floor` / `block_fn` 配方 2971-2985），可以直接照抄。
**建议：加一个「世界几何适配器」对象 `geo`（大世界一份、新图一份），raid_manager / raid_camps / raid_search 把上述调用全部改成问 `geo`；
ex_level.gd 在主干上改为挂 raid_manager.gd。** 数值 / 存档 / 死亡 / 撤离时间线 / 联机协议一个字不用改。

---

## 1. 老循环需要关卡 / 世界提供什么（精确接口）

### 1.1 关卡节点（meadow_level.gd，raid_manager 里写作 `level`）

| 成员 | 用处（raid_manager.gd 行号） | ex_level.gd 有没有 |
|---|---|---|
| `env: Environment` | `_ready` 225；`_blend_atmosphere` 改雾 / 天色 | 有（ex_level.gd:33，自己 `_apply_atmo` 479 在管） |
| `sun: DirectionalLight3D` | 226；atmosphere 改光色 / 方向 | 有（:34） |
| `world` | `apply_dug` 249/258、`crater_changes` 256、`world.mat` 1284（调色 _lk_*）；raid_camps.gd:93 `w._shaped`；shen_shi.gd:312-324 取 `mat / _sea_mat` 设光波 | 有（GridWorld 继承 block_world，`mat` 在 block_world.gd:286 的 `_ready` 建，grid_world.gd:126 `super()` 会走到；`_sea_mat` 新图没有 → shen_shi 自动跳过） |
| `motes: CPUParticles3D` | 1323 改颜色 | 有（:36） |
| `ground(x, z) -> float` | `_ground` 319-320，全文件 26 处间接用；raid_search.gd:130 `_h` | 有（:95，= world.height，**只有地形，不含楼板 / 实心盒子**） |
| `exit_requested` 信号 | `room_lost` 2850、`_finish` 2915 | 有（:12） |
| （meadow_level 设给 raid 的）`player / cam / font / mobile / net` | meadow_level.gd:268-276 | ex_level.gd:206-215 用 `raid.set(...)` 设，另多设一个 `map_id`（raid_manager 没这个变量，set 会静默失败） |

raid_manager 自己不碰 `spawn_point / spawn_yaw / prewarm / stats_text`（main.gd 调，ex_level 都有）。

### 1.2 世界几何（raid_data.gd 静态函数，循环世界专用）

* `LOOP = 3456 / HALF = 1728`（raid_data.gd:17-18）；`near(base, ref)` 取离 ref 最近的像（:27）、`near2`（:31）。
  用处：raid_manager 672/703/777/994/1000/1312/1574/1586/1868/2787；raid_camps 238/263/307/450/474/479；raid_search 143；
  ally_team.gd:94；net.gd:597（`_state` 收别人位置）。
  **新图上 near() 天然是恒等**：两张图的坐标都在 x∈[-464, 1296]、z∈[-512, 512]，任意两点水平差 < 1728，`roundf(diff/LOOP)=0`。所以
  不改也不会错，但为了清楚和防将来扩图，建议走 `geo.near`。
* `land_r(x,z)` + `PLAY_R = 1450`（:10/:36）：「在不在陆地上 / 外海」。用处：raid_manager 1327（出海题字）、1773（游荡首领）、1780/1814（老导演）、
  2023（AI 修士）、2605（破界符）；raid_camps 90（布局）、247（tick 里海上不建）。
  新图坐标恰好全在 1450 以内（沙漠洞窟最远 ≈1335），所以也「碰巧能跑」，但语义是错的，应走 `geo.on_land`。
* `region_at / region_weights`（:286/:308）：按方位扇区定区域 0~4。用处：raid_manager 351/867/1119（天色权重）/1679/1815/1912/1962/2029/2041；
  raid_camps 92；raid_search 103。**新图上这个是错的**（沙漠洞窟 x≈1000 会被算成东边的血色禁地）——必须分支。
* `pois()`（:192）：出生点 / 5 座巢穴 / 5 座传送阵的固定位置。用处：raid_manager 1375（`_setup_pois`）；raid_camps 96-102（布局避让）；
  raid_search 60/84（避让、宗门宝罐放巢穴边）；meadow_level.gd:150（出生点避让）。**新图必须换成点表**。
* `Data.REGIONS[ri]`：`mobs`（怪池，1791/1816/1842/2042，raid_camps 108）、`boss`（巢穴 / 游荡首领的怪，1649/1682）、`name / sub / light`（290/957/1339/1383/1398/1615/1653）、
  `water_h`（raid_search 117）、`dir`（raid_search 98，pois）、天色那一整套（1145-1176）。
* progression.gd `depth_at(ri, x, z)`（:146-151）：草原按到中心距离 / 480，其它区按 `(land_r - R0) / (LAIR_R - R0)`。**纯大世界几何，必须分支**。
  `mob_level / mob_tag / pill_realm_at / value_mult / suppress_gap / lair_tag / frag_to` 都只吃 `(ri, depth)`，不碰坐标，新图照用。

### 1.3 区域境界档（数值都在 Prog，只认 ri∈0..4）

* `REGION_TAG_BAND`（progression.gd:143）：0 草原 炼气~筑基 / 1 黄枫谷 结丹 / 2 血色 元婴 / 3 云梦 化神 / 4 坠魔谷 炼虚~大乘。
* `REGION_REALM_MAX`（:139）天道压制线、`DEPTH_LV`（:138）、`REGION_KEYS`（:342）、`Data.REGIONS[ri]["lv"]`、`CS.mob_scale(ri, lv)`，
  `Items.mat(ri)` / `Items.herb(ri)` / `HERB_MODELS[ri]` / `URN_MODELS[ri]`、`raid_camps.P / RESPAWN[ri]`、`raid_search.COUNTS[ri]` —— **全是长度 5 的表，到处 `clampi(ri,0,4)`**。
* 结论：新图**不要新开区域下标 5/6**（要动十几张表 + 校准），而是让新图的每个点映射到一个**已有的 ri（2/3/4）+ 一个深度**（「虚拟区域」）。
  这样怪的档、心得、掉落、破境丹残片、压制全部自动成立。

### 1.4 地标：巢穴 / 撤离点 / 刷怪点 / 搜点

* 巢穴 `_bosses`（raid_manager.gd:160、建于 `_setup_pois` 1373-1403）：`{region, pos, node, state 0/1/2, mark, back}`；
  **巢穴编号 = 区域下标**：`m.set_meta("lair", ri)`（1650）、`_lair_cleared(ri)`（843）、`_light_boss_gate(ri)`（1482）、`_lair_puppet(ri)`（1620）、
  `net_mob_apply` 里 `b["region"] == lair`（697-700）、`_on_mob_died` 里 `lair_ri`（1876-1880）、镇守阵 `e["region"]`（1398/1484）。
  走到 `LAIR_SPAWN_R = 200` 米内刷（1640），打空 `LAIR_BACK = 600` 秒（个人 run_t）后再来（1632-1638）。
* 撤离点 `_extracts`（:162）：`{pos, active, known, name, base?, kind, region?, node}`。
  - 古传送阵：pois 里的 5 座，按房间时钟每 `ROT_PERIOD=300` 秒轮换（`_rotate_gates` 1421-1469：种子 `_room_seed()+7919*k` 洗牌，前 2 座 gate、第 3 座 paid 灵石阵、其余熄）。
  - 镇守阵：每个巢穴旁 34 米（1393-1399），首领倒了才亮。
  - 空间裂隙：房间时钟每 600 秒在 420~540 秒开（`_timeline` 2760-2766、`_open_rift` 2778-2793 在 160~1150 米环上随机找 `_ground>2` 的点）。
  - 破界符阵：`_use_tool` "rune"（2604-2620）原地起阵 14 秒。
  - 判定：水平 `EXTRACT_R=6` 米、`|Δy|<8`（2710）；挨打清零；读条秒数 `EX_KINDS[kind].t / (1+养*0.5)`（2731）。
* 刷怪点（raid_camps.gd）：32 米网格 × 108（= LOOP/32，首尾接上）哈希布局 `_layout`（87-131）：按 `Data.region_at` 定区域、按 `P[ri]` 概率、
  避开 pois / 搜点 30 米 / 水 / 断崖（用 `world._shaped`）；每点 `{id, base: Vector2, ri, defs: [Data.MOBS 下标], elite, offs}`。
  建怪 `_build`（396-456）：`pos.y = mgr._ground()`、`mgr._spawn_mob(defs[slot], ri, pos, el)`、`home/anchor = 点中心`、`set_meta("camp", code)`。
* 搜点（raid_search.gd）：固定种子 20261120，按 `COUNTS[ri]` 在扇区里找平地（`_spot` 91-127，用 `Data.REGIONS[ri].dir / water_h`、`R0 / PLAY_R`），
  宗门宝罐放每个巢穴边（80-87）；`tick`（135-169）每 0.4 秒把位置换到最近的像并 **`pos.y = _h()`（level.ground）重新落地**；
  `_finish`（224-251）按 `(region, depth)` 出货 → `mgr.site_loot`；联机 `§s` 小消息同步已搜（251 / raid_manager 986-990）。

### 1.5 出生点

meadow_level.gd:138-158 `_raid_spawn`（草原外圈 110~250 米随机，避开 pois）。ex_level 自己有 `_choose_spawn`（ex_level.gd:121，从 `map.spawns` 随机，含洞窟出生点）——
**新图上直接用 ex_level 的**，raid_manager 不管出生点。

---

## 2. 死亡规则 / 撤离时间线

* 个人局内时间 `run_t`（2940），`RAID_LEN = 1200` 秒（72）；300/180/60 秒警告（2747-2752），到 0 `_finish(false)`「困死」（2767-2769）。
* 房间时钟 `world_t()`（1406：联机 `net.room_t`，单机 `_solo_t`）只管传送阵轮换和裂隙，全房一致不用发消息。
* 陨落判定：`_process` 里 `player.melee.hp <= 0` → `_finish(false)`（2968-2970）。**没有重伤倒地 / 救援**（那是 extract_manager 的 downed 机制，主干不要）。
* `_finish(success)`（2869-2915）：
  - 心得：成功全数 `Prog.profile_add_xp`；失败 `× Prog.DEATH_KEEP`（progression.gd:209，**= 0**，全丢）。
  - `Profile.end_raid(ok, bag, ring, gear, realm)`（raid_profile.gd:386）：成功 → 背包进仓库（放不下折灵石）、法宝回洞府；失败 → 法宝清空、背包丢；**储物戒 ring 两种都保住**。
  - 联机陨落：背包 + 法宝变一只「XX 的储物袋」掉在原地（2880-2883，走共享掉落，谁先捡归谁）。
  - 4.5 秒后 `level.exit_requested`。
* `room_collapsed`（2817）：房主关房 → 当撤离成功结算。`room_lost`（2828）：断线 → 心得 ×DEATH_KEEP、本局所得留不住、带进来的法宝随身物 `_recover_live` 还回洞府。
* 进图：`Profile.begin_raid()`（raid_profile.gd:372）把洞府佩戴的法宝 / 随身丹符拿出来、写 `live` 防崩溃丢失（263-268）。
* 渡劫 / 结婴演出可在局内发生（`_try_start_trib` 1020，`Tribulation` 用 `cam.floor_fn` 取地面，tribulation.gd:136/265/403）。

以上**全部和地图无关**，新图照搬即可满足「死了跟大世界一样」。

---

## 3. 老循环用到的联机路径（net.gd）

raid_manager 被 net 鸭子调用的方法（net.gd 行号 → raid_manager 行号）：

| net.gd | 方向 | raid_manager |
|---|---|---|
| `enter_world(r)` 468 / `leave_world()` 493 | raid → net（_ready 245 / _exit_tree 641） | — |
| `_hello` 324-342 | 房主发 `_welcome(seed, cleared, room_t, drops, dug, blasts)`；`dug` 取 `raid.level.world.dug_table()`（337） | `pending_dug / pending_drops / pending_blasts` 在 `_ready` 246-262 取走 |
| `_process` 549-579 | 15 Hz `_state`（读 `raid._in_trib`、`raid.lv`），10 Hz `_mobs`（`raid.net_mob_batch()` 647）、`_allies`（`net_ally_batch` 2165） | |
| `_state` 583 | 收：`LoopData.near(pos, player)` 597 | |
| `_mobs` 896 | 收 → `net_mob_apply` 662（建木偶：`Data.MOBS[int(e[1])]` 684、`Data.near` 672/703、camps.saw 668、巢穴认领 693-700） | |
| `_mob_hit` 1007 | → `net_mob_take` 757 | 我打别人的木偶 `_on_puppet_hit` 707 → `send_mob_hit` |
| `_mob_attack` 785 | → `net_mob_attack` 769 | |
| `_mob_dead` 1024 | 有 `net_ex_mob_dead` 就走新图那条，否则 `net_mob_died` 858（lair≥0 巢穴记空；lair≤-2 刷怪点 `-2-code`） | 发：`_on_mob_died` 1862 `send_mob_dead(..., lair if cd<0 else -2-cd, hitter)` |
| `_hit` 981 | → `net_take_hit` 897（PvP 走 `CS.pvp_hit / pvp_cap_k / _pvp_clamp`） | 发：`net_deal_hit` 886 |
| `_drop` 850 / `_claim` 868 / `_granted` 888 | 共享掉落：`net_drop` 774、`net_granted` 795、`net_drop_list` 785 | `_reg_drop` 2186 |
| `_announce` 750 | → `net_announce` 974；`§s` 搜点已搜、`§x` 有人在撤离 → `_net_small` 986 | `net_send` 981 |
| `_trib` 836 | → `net_trib` 815（旁观雷劫） | `send_trib` |
| `_dig` 763 | bowl → `raid.level.remote_blast`；否则 `raid.level.world.dig` | |
| `_clock` 396 | 房主每 10 秒校房间时钟 | `world_t()` |
| `node_of / ref_of` 601-623 | 飞剑目标引用 → `raid.net_find_mob` 724 | |

ex 专用的 `_ex_*` RPC（net.gd:1043-1503）在主干上没人调就是死代码；`_mob_dead` 只要 raid 没有 `net_ex_mob_dead` 方法就自动走老路（1031-1035）；
`send_mob_dead` 里房主给 lair≤-2 记 `_ex_log_camp`（1019-1020 / 1029-1030）无害。
**新图跑老循环不需要任何新的 RPC**；分房按 `net.map_id`（main.gd:887-892 已有）。
地形破坏：新图的 `GridWorld.dug_table()` 恒返回 `{}`（grid_world.gd:2516），破坏走 Destruct 的 `dx_*` 操作记录（net.gd:1448-1503，ex_level.gd:184 `Destruct.attach`）——
raid_manager `_ready` 里 `pending_dug / pending_blasts` 那两段（246-260）在新图上要跳过（`pending_blasts` 走 `world.crater_changes + apply_dug` 会绕开 Destruct 的记录）。

---

## 4. 适配器设计：同一套 raid_manager + raid_camps + raid_search + shen_shi 跑新图

### 4.1 总体

1. **ex_level.gd 在主干上挂 raid_manager.gd**：把 ex_level.gd:24 `MANAGER_PATH` 改成 `res://scripts/raid_manager.gd`，
   203-215 照 meadow_level.gd:268-276 设 `level / player / cam / font / mobile / net`，另设 `raid.geo = ExGeo.new(self)`（或 raid_manager 自己按 `level.has_method("points")` 判断后建）。
   main.gd:946-954 的建关分支不用动（`is_ex` 时还是建 ex_level）。
2. **新建两个小脚本**（不 class_name，preload）：
   * `scripts/raid_geo.gd`（大世界版，原样转调 Data / Prog，行为零变化）
   * `scripts/ex/ex_geo.gd`（新图版，问 ex_level + map_def）
   接口（两份同名方法）：

```
var loop: bool                              # 大世界 true / 新图 false
func near(base: Vector3, ref: Vector3) -> Vector3       # 新图：return base
func near2(base: Vector2, ref: Vector2) -> Vector2
func on_land(x, z) -> bool                  # 大世界：Data.land_r < PLAY_R；新图：points("bound") 里 play 矩形（按 layer_of）内
func region_of(p: Vector3) -> int           # 大世界：Data.region_at(p.x, p.z)；新图：虚拟区域（见 4.3）
func depth_of(ri: int, p: Vector3) -> float # 大世界：Prog.depth_at；新图：见 4.3
func floor_y(x, z, y := INF) -> float       # 大世界：level.ground；新图：level.floor_at(x, z, y)
func lairs() -> Array      # [{lid, ri, pos: Vector3, def: int, name, light: Color}]
func gates() -> Array      # [{name, pos: Vector3}]       古传送阵（参与轮换）
func boss_gate_at(lair: Dictionary) -> Vector3            # 镇守阵位置
func mob_pool(ri: int, p: Vector3) -> Array               # 怪的 def 下标（见 4.4）
func roam_boss(ri: int, p: Vector3) -> int                # 游荡首领的 def 下标；-1 = 这里不来
func rift_spot(rng) -> Vector3                            # 空间裂隙落点（房间种子 rng，所有人一样）
func spot_near(c: Vector3, r_min, r_max, rng) -> Vector3  # 守卫 / AI 修士 / 喂怪的落点（新图 = level.find_spawn_near，自动同层、不进墙）
func camp_points() -> Array                               # 刷怪点表（新图 = level.points("camp")；大世界 = [] 走网格）
func search_points() -> Array                             # 搜点表（新图 = 由 points("box") 转换；大世界 = [] 走 _place）
func where_name(ri, p) -> String / title(ri, p) -> [主, 副, 色]
var own_atmo: bool                                        # 新图 true：raid_manager 不调 _blend_atmosphere
```

### 4.2 必须分支的每一处（改成问 geo）

**raid_manager.gd**

| 行 | 现在 | 改成 |
|---|---|---|
| 246-260 | 中途加入应用 `pending_dug / pending_blasts` | `if geo.loop:` 才做（新图由 Destruct 同步） |
| 290 | `hud.title("木兰草原", …)` | `geo.title(...)`（沙海古墟 / 天工秘所） |
| 319-324 `_ground / _on_ground` | `level.ground` | 保留（怪 / 修士 floor_fn 照 extract_manager 用地形高）；另加 `_floor(x,z,y)` = `geo.floor_y`，给掉落 / 搜点 / 撤离点 / 守卫落点用 |
| 340-351 `depth_of / level_at` | `Prog.depth_at`、`Data.region_at` | `geo.depth_of / geo.region_of` |
| 672 / 703 / 777 / 994 / 1000 / 1574 / 1586 / 1868 / 2787 | `Data.near` | `geo.near` |
| 684 | 木偶 `m.def = Data.MOBS[int(e[1])]` | `m.def = _mob_def(int(e[1]))`（见 4.4）；`m.floor_fn = _ground`，新图 lab 另设 `m.block_fn = Callable(level, "blocked")`（照 extract_manager.gd:2976-2977） |
| 867 | 远处死的怪按 `Data.region_at` 定区 | `geo.region_of(pos)` |
| 957 `_watch_cine` | `Data.REGIONS[region].name` | `geo.where_name` |
| 1117-1348 `_blend_atmosphere` | 天色 / 雾 / 光 / world.mat 调色 / 区域题字 / 出海 | `_process` 2925 / 2943 两处：`if not geo.own_atmo: _blend_atmosphere(dt)`；新图另写 5 行 `_ex_region_tick(p)`：`region = geo.region_of(p)`、`at_sea = false`、换区时 `hud.title` + 重置 `_sup_told / _tag_told`（照 1328-1347 的危险判断） |
| 1373-1403 `_setup_pois` | `Data.pois()`、镇守阵「朝世界中心 34 米」 | 循环 `geo.lairs()` / `geo.gates()`；镇守阵 `geo.boss_gate_at(b)`；撤离点 y 用 `_floor`（lab E2/E5 在 5 米高台上） |
| 1383 / 1398 / 1615 / 1653 | `Data.REGIONS[ri].light / name` | lair 字典里的 `light / name` |
| 1502-1530 `_build_lair` | 一圈残柱 + 光柱 | 新图可保留（标记巢穴）；Boss 场地在洞窟里（洞顶 36 / 40）时光柱高度会穿顶，新图把光柱高度夹到 `world.ceil_at - y` |
| **巢穴编号** 1650 / 843-855 / 1482-1490 / 1620-1624 / 693-700 / 1876-1880 / 1398 | `lair = region` | 改成 `lair = b["lid"]`（巢穴在 `_bosses` 里的序号）；`b["region"]` 只当数值区域用。大世界 lid == region（0..4），**联机包不变**。新图沙漠洞窟有两座巢穴同在一个虚拟区（绛罗 / 沙渊巨虫），不改会互相顶掉 |
| 1640-1653 `_update_bosses` 刷首领 | `Data.REGIONS[ri].boss`、`Prog.lair_tag(ri)` | `b["def"]`；档照 `Prog.boss_level(Prog.lair_tag(ri), …)` 不变；`pos` 用 lair 表里的（凌幽在金字塔顶 y38，是地形表里的，level.ground 就对） |
| 1673-1700 `boss_event` | 主角 42 米外刷、`Data.region_at`、`REGIONS[ri].boss` | 落点 `geo.spot_near(p, 36, 48)`；`geo.roam_boss(ri, p)`，返回 -1 就跳过；`_director` 1773 的 `land_r` → `geo.on_land` |
| 1780 / 1814 / 1815 / 1842 老导演 spawn_wave | `land_r / region_at / REGIONS.mobs` | 新图 `camps.on` 恒开，老导演不会走到；保险起见同样换 geo |
| 1788-1803 `spawn_guards` | 8~14 米环、`REGIONS[ri].mobs`、`_ground` | `geo.spot_near(pos, 8, 14)`、`geo.mob_pool(ri, pos)` |
| 1912 `site_loot` | `Data.region_at(pos)` 求深度 | 直接用搜点带的 `region / depth`（raid_search `_finish` 传进来），或 `geo.region_of`；箱子落点 `_floor(at.x, at.z, pos.y+0.5)` |
| 1962 / 2023 / 2029 / 2041 AI 修士 | `region_at / land_r`、p + 80~140 米随机 | `geo.region_of / geo.on_land`；落点 `geo.spot_near(p, 80, 140)` + 1.4；喂怪池 `geo.mob_pool` |
| 2209-2232 `_drop_item / _drop_chest / settle_drops` | 调用方传进来的 pos.y 多半是 `_ground` | 1865 `_on_mob_died`、999 `net_loot`、2882 陨落储物袋 都改 `_floor(x, z, 原 y + 0.5)`（lab 二层楼上死的怪 / 人，东西别掉到楼下地形里） |
| 2605 破界符 | `land_r > PLAY_R`「海上起不了阵」 | `not geo.on_land`；`pos.y = _floor(...)` |
| 2778-2793 `_open_rift` | 160~1150 米环上找陆地、`Data.near` | `geo.rift_spot(r)`（种子同 2780，大家一样） |
| 2992 `_reimage(p)` | 把巢穴 / 撤离点挪到最近的像 | `if geo.loop:` |
| 新增 | — | `var geo`、`var map_id := ""`（ex_level.gd:212 那个 set 才有落点）、`_mob_def(i)`、`_floor(x,z,y)` |

**raid_camps.gd**（照 extract_manager.gd:481-541 的内部类 `Camps._init` 加一个「点表模式」，状态机一行不改）

| 行 | 改 |
|---|---|
| `_init(m)` 46 | 加 `func use_points(pts: Array, seed_key: String)`：把 `level.points("camp")` 的每项 `{pos, kinds[], n, r, layer, elite}` 按固定种子（`hash(map_id)+7919*i+104729`，同 extract_manager.gd:513）摊成 `{id, base: Vector2, y, ri, defs, elite, offs}` 写进 `_cache[id]`，`list_mode = true`。`defs` 存 4.4 的统一 def 下标（ExMobs 种类 + 偏移） |
| 87-131 `_layout` | 点表模式不调 |
| 221-293 `tick` 的「建」段 | 网格循环 259-278 在点表模式下换成遍历 `_cache.values()`，其余（`_hold`、`_owned_by_other`、`_lower_peer_near`、名额、`_queue`）原样 |
| 238 / 263 / 307 / 450 / 474 / 479 | `Data.near2 / near` → `mgr.geo.near2 / near` |
| 247 | `Data.land_r > PLAY_R` → `not mgr.geo.on_land(p.x, p.z)` |
| 396-428 `_build` 的 `pos.y` / `centre.y` | 点表模式用 `mgr._floor(x, z, c.y + 0.5)`（洞窟 / 楼里的点要按层落脚）；`ri` 取点自带的 |
| 427 `mgr._spawn_mob(defs[slot], ri, pos, el)` | 不变（_spawn_mob 吃统一 def 下标） |
| `code(id, slot) = id*8+slot` 181 | 不变；点表里 `n` 夹到 ≤7（extract_manager.gd:519 已夹） |
| `P / RESPAWN[ri]` 29-30 | 点表模式不用 P；RESPAWN 用 ri 下标照样对 |

**raid_search.gd**

| 行 | 改 |
|---|---|
| 53-87 `_place` | `if not mgr.geo.search_points().is_empty():` 用点表，否则原逻辑。点表由 ex_geo 从 `level.points("box")` 转：`supply→jar`、`med→herb`、`weapon→grave`、钥匙房里的（`room != ""`）→ `vault`；每个巢穴边一只 `urn`（`geo.spot_near(lair.pos, 10, 18)`）。每项带 `pos(含 y) / region / depth`。顺序 = 点表顺序（所有人一样，`§s` 用下标同步） |
| 91-127 `_spot` | 点表模式不调 |
| 135-150 `tick` 换像 + `pos.y = _h()` | 点表模式：`img = pos`，**不重新落地**（保留点表 y：lab 二层 55.5、金字塔各层、洞窟） |
| 165-169 守卫 | `mgr.spawn_guards` 已改走 geo |
| 185 `step` 里 `absf(p.y-pos.y) < 5` | 不变（正好防止楼下的人读楼上的箱子） |
| 235-246 `_finish` 出货 | 不变（按 `s.region / s.depth`）；`Items.herb(ri)` 按虚拟 ri 出那一区的灵草 |
| 钥匙房 | 主干没有钥匙：ex_geo 建好后对每个 `map.key_rooms` 调一次 `level.set_door(id, true)`（本地、各人都开，不用联网），里面的箱子当禁制宝库 |

**shen_shi.gd**：基本不用改。`_world_mats` 312-324 拿 `world.mat`（GridWorld 继承来的同一个 block_world 着色器，带 shenshi_wave，光波能画）、`_sea_mat` 新图为 null 自动跳过；
`_collect` 读 `mgr.search.sites / _pickups / _mobs / _puppets / _rivals / net.remotes / _extracts` 全是 raid_manager 的字段。
704 光带贴 `mgr._ground` 走：洞窟里 level.ground = 洞底，楼里会贴地形走，纯表现，可接受。**需要实机确认 grid_world 的地块确实用 `mat`（没换成自己的材质）。**

**raid_hud.gd**：666 `Data.REGIONS[int(mgr.region)]` —— 虚拟 ri 合法，不崩，但名字是「血色禁地」。改成 `mgr.geo.where_name(...)`。其余（背包格数 `Data.BAG_SIZE`、品阶色）通用。

**minimap.gd**：
* 170-180：关卡有 `map_tex` 就走固定底图（`_fixed`），新图已支持。
* **363-377：`_fixed` 时只画 `level.map_marks()` 里的 "extract"（4/8 个全亮的玉色圈），`_arr("_extracts")` 整段跳过** → 老循环的轮换 / 灵石阵 / 镇守阵 / 裂隙 / 破界符都看不到。
  改成：`mgr` 有 `_extracts`（raid_manager）就走 377 那段画 mgr 的，不画 map_marks 的 extract；ex_level.map_marks（1166）同理别再给 extract，或 minimap 过滤掉。
* 大地图（ex_level `open_big_map`，map_marks 画撤离点 / 钥匙房 / Boss / 洞口）：撤离点同样要换成 mgr._extracts，钥匙房标记去掉。

**ally_team.gd:94**：`Data.near` → `rd.geo.near`（或不改，新图上恒等）。

**net.gd:597**：`LoopData.near` —— 新图恒等，可不改；想干净就 `raid.geo.near`（raid 为空时不调）。

**ex_level.gd**（主干版）：
* 24 / 203-215：挂 raid_manager（见 4.1）。
* 992-993 `_env_hurt`：raid_manager 没有 `env_damage` → 走 995 的 `hp -= pts（不低于 1）`，沙暴不致死，可接受；想让沙暴能致死就给 raid_manager 加 `env_damage(pts, kind)`。
* 886-901 `_clamp_mobs` 读 `raid._mobs`（有），1229-1238 `_map_blocked` 读 `raid.downed / result`（raid_manager 没有，`get` 返回 null，不影响）。
* 「夜里尸潮」（map.horde，extract_manager `_horde`）老循环里没有，主干先不做（或以后挂在 `_director` 上）。

**main.gd**：`_apply_combat_mode("ex" if is_ex else "legacy")`（890-893 附近 / 808-）——**主干上新图也必须走 legacy（存档境界）**，
英雄只换外观 / 技能（C 报告的事）。raid_manager 全程读 `player.realm_idx`，固定结丹档会把数值全打乱。
入口限制「元婴及以上」：门 2 / 3 的入境页（level_select.gd:165 `open_level`）检查 `RaidProfile.realm() >= 3`（0 炼气 1 筑基 2 结丹 3 元婴）。

### 4.3 新图要提供的数据（建议放 map_def.gd 每张图一个 `"xiu"` 块，ex_geo 读）

```
"xiu": {
  "ri":    {"surface": 2, "cavern": 3},      # 沙漠：地面 = 血色禁地档（元婴），洞窟 = 云梦档（化神）
                                             # 研究所建议 {"surface": 3, "cavern": 4}（化神 / 炼虚~大乘）
  "depth": {"surface": [中心 Vector2, 半径], "cavern": [中心, 半径]},   # depth = 1 - dist/半径，夹 0..1；
                                             # 沙漠地面中心 = 金字塔 (12, 82)、半径 ≈ 330；洞窟按两个 Boss 场地取 max
  "pools": {2: ["scorpion","wolf_sand","sand_guard","sand_raider"], 3: [...]},   # ExMobs 种类（刷怪点自带 kinds，pools 给守卫 / 游荡 / 喂怪用）
  "roam":  {"surface": "sand_guard", "cavern": ""},                   # 游荡首领用哪只（精英化身），"" = 不来
  "boss_def": {"lingyou": "lingyou", "jiangluo": "jiangluo", "worm": "sandworm", "twin": "duo_hunter", ...},   # map.bosses[].key → ExMobs 种类
  "boss_gate": [Vector3, …],                  # 每座巢穴的镇守阵位置（可选，缺省 spot_near(Boss 位置, 20, 34)）
  "rift": [Vector3, …],                       # 空间裂隙候选点（可选，缺省从 camps / boxes 里按种子挑一个 floor_at 落地）
}
```

另：点表 `camps / boxes / bosses / extracts` 已有（map_def.gd:199-200 / 514-515 / 155 / 396 / 106 / 394），`points()` 已把 y 摆到落脚处（ex_level.gd:313-327）。

**区域境界档的取舍（要和数值负责人定）**：用户要「元婴以上才进的高难度区」。按 Prog 的档表，元婴进化神档（ri 3）的怪会「一击即倒」（每高一档 ×5，numbers-rework-hammer）。
所以建议 **沙漠地面 = ri 2（元婴）作为入门，沙漠洞窟 / 研究所地面 = ri 3（化神），研究所地下室 = ri 4**；
「高难度」体现在深度偏高（depth 默认 0.5 起 → 怪的等级在档内偏高、掉落 `value_mult` 偏高）和刷怪点更密，而不是另开数值。

### 4.4 怪的种类表（统一 def 下标）

`_spawn_mob(def_idx, ri, pos, …)`（1533）和木偶 684 都用 `Data.MOBS[i]`。新图的怪在 `ExMobs.MOBS`（ex_mobs.gd:38-）、按 `ExMobs.IDS` 下标（:105，`idx / by_idx / id_of` 128-136）。
ExMobs 的 def 字段（shape / hp / atk 倍数 = 1.0 / spd / size / ranged / model / elite_model / cols / boss）和 raid_mob 吃的完全一样，
**所以老数值公式（`SHAPE_BASE[shape] × hp × CS.HP_CONV × CS.mob_s_hp(ri, lv)`，1543-1548）可以直接套在新怪身上**，只换外观。
建议：`const EX_DEF0 := 1000`；`_mob_def(i) = ExMobs.by_idx(i - 1000) if i >= 1000 else Data.MOBS[i]`；
1534 / 684 / raid_camps 455 / raid_search 无（不直接建怪）都走 `_mob_def`。网络包第 2 个字段本来就是 int，**协议不变**（新图房间里大家都 ≥1000）。
别调 `ExMobs.setup`（它把 hp/atk 写成「点数」、lv=1、region=0、xp_k=0，是搜打撤那套）。`big` / `elite_only` 字段老公式不认，可忽略或把 big 映射成 `hp_k`。
Boss 机制（ex_boss.gd 的阶段 / 召唤 / 祭台）先不接：巢穴首领就是 raid_mob（`boss: true`），以后想要再挂 ExBoss 大脑。

---

## 5. 开放风险 / 待确认

1. **区域档位映射**（4.3）是设计决定，不是代码问题：拍板前先用 `--raid-pace` 类似的探针在新图上量一下杀怪节奏、心得 / 小时。
2. **lab 多层**：怪 / AI 修士的 `floor_fn` 用地形高（与 extract_manager 一致），楼上没有怪；掉落 / 搜点 / 撤离点改用 `floor_at` 后没问题。
   AI 修士（air_foe）没有 `block_fn`，在 lab 会穿墙（extract_manager 也一样，属既有问题）。
3. **洞窟顶**：雷劫（tribulation.gd 劫云在头顶）、元婴演出、巢穴光柱、破界符光柱在洞窟里会穿顶。建议洞窟里禁止起劫（`_try_start_trib` 前 `level.layer == "cavern"` 时提示「洞中不可引劫」并缓到出洞）。
4. **巢穴编号改成 lid**：要把 7 处 `region == lair` 一起换，漏一处就会出现「打掉凌幽、亮的是绛罗的镇守阵」。大世界 lid == region，联机包兼容。
5. **minimap / 大地图**：`_fixed` 分支现在完全不画 mgr._extracts（minimap.gd:377），不改就看不到老循环的任何撤离点。
6. **pending_blasts**（raid_manager 252-260）在新图要跳过，否则会绕过 Destruct 的破坏记录、中途加入的人地形对不上。
7. grid_world 地块是否真的用继承来的 `mat`（神识地形光波靠它）——实机 `--shenshi` 量一下。
8. 搜打撤专属的东西在主干上不再有人调用：net.gd 的 `_ex_*` RPC、extract_manager 的 downed / 天工师 / 钥匙 / 尸潮。删不删由总负责人定（不删也无害，`has_method` 守着）。
9. `ex_level.gd:206` `raid.set("map_id", …)` 在 raid_manager 上会静默失败——要么加 `var map_id`，要么去掉这行。
10. 自检：`--raid-pace / --pace-spawn / --shenshi / camp_net_selftest.gd` 都按大世界坐标写；新图需要新加一个 `--xiu-ex` 冒烟（进沙漠、刷怪点建出来、搜一个箱子、站进亮着的阵读条撤离、死一次看储物袋 / 结算），双开测联机同图。
