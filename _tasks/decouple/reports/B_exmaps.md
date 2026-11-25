# B · 两张新图（沙海古墟 desert / 天工秘所 lab）解耦报告

只读调研（2026-11-25）。目标：主干上两张新图保留，但跑**老修仙系统**（raid_manager + raid_camps + raid_search + shen_shi + raid_profile + Prog/CS 数值、陨落规则、局域网同图），元婴起能进；搜打撤分支（extraction-pvp）保持原样。

---

## 0. 结论先说

1. **地图层本身是干净的**：`map_def.gd`（纯数据，0 个 preload）、`grid_world.gd`（只 preload map_def，继承 block_world）、`ex_worm.gd`（只用 raid_data / creature_model）完全不碰 ExData / ExProfile / extract_manager。`ex_level.gd` 也**不 preload** ExData / ExProfile，只按路径 `MANAGER_PATH` 动态 load extract_manager（ex_level.gd:24, 203-215），其余对管理器全是鸭子类型 `raid.get(...)`，缺了都有兜底。
2. **经济耦合只在 extract_manager / ex_hud / ex_profile / ex_data**。map_def 里有几项是搜打撤专用的**字符串数据**（掉落表名、death_drop_stacks、box_quality、钥匙房 tables、doctor、horde），没有代码依赖，主干忽略即可——**建议不删**，两条分支共用同一份 map_def，以后改图能原样搬运。
3. **ex_mobs 的 def 字典和老 `raid_data.MOBS` 是同一个格式**（name / shape / hp / atk / spd / size / ranged / model / elite_model / elite_name / cols / boss），老 `raid_manager._spawn_mob` 那套「SHAPE_BASE × hp × HP_CONV × CS.mob_s_hp(ri, lv)」可以直接吃。数值从「点数」换成「区域境界档」只需要给每条填上老体系的 hp / atk 倍率 + 选一个借用的区域序号 ri。
4. **ex_boss 能在老体系下复用**，只要把它里面三处「绝对点数」改成「相对量」（技能伤害按 `pts_k` 换算成原始攻击、血量缩放按相对值、虫子身子用 atk_pts），搜打撤分支下 `pts_k = 1` 行为逐字不变。
5. **ex_doctor 整个是搜打撤专用**（营救天工师），主干不建；`day_sec()` 只给它用。
6. 老系统挂到新图上，真正要改的是**老系统里写死了大世界的几处**：`Data.region_at` / `Prog.depth_at`（区域按扇区角度）、`Data.pois()`（搜点 / 巢穴 / 传送阵位置）、raid_camps 的 32 米格布局、raid_search 的扇区撒点、裂隙的 160~1150 米环、`_blend_atmosphere` 会覆盖新图天色、怪的 `floor_fn` 只认地形且没有 `block_fn`。这些都可以用「关卡有这个方法就问关卡」的方式接，木兰草原不受影响。

---

## 1. 新图给老系统提供了什么（接口清单）

ex_level 的关卡契约（ex_level.gd:7-9 注释）和实现：

| 用途 | 接口 | 位置 | 说明 |
|---|---|---|---|
| 地形高 | `ground(x, z)` | ex_level.gd:95 | 只地形（GridWorld 查表），**不含**楼板 / 盒子 |
| 落脚高 | `floor_at(x, z, y := INF)` | ex_level.gd:100-103 | 地形 + 实心盒子顶面；**y 要给**（脚高 +0.5），不给 = 取最高顶面（会落到屋顶上） |
| 出生 | `spawn_point()` / `spawn_yaw()` / `_choose_spawn()` | :106-129 | 沙漠地面 4 + 洞窟 4，研究所 5；自检固定第一个 |
| 挡路 | `blocked(from, to)` | :282-295 | 0.5 米一步，两格以上是墙；怪 / AI / 天工师用 |
| 实心 | `solid_at(p)`、`y_cap(p)` | :273-308 | 洞顶 / 楼板 / 飞行上限 |
| 层 | `layer_of(p)` → MapDef.layer_at（x > 600 = cavern） | :268, map_def.gd:645 | 洞窟 / 地下室在同一坐标系的另一片 |
| 找落点 | `find_spawn_near(center, r_min, r_max, rng)` | :379-397 | 同层、在 play 矩形里、不在墙里、不在洞顶上 |
| 门 | `set_door(id, open)` / `door_open(id)` / `world.door_ids()` | :400-405, grid_world.gd:809-830 | 钥匙房的门（开 = 立刻不挡路，门板沉地） |
| 时钟 | `room_time()` / `day_phase()` / `is_night()` / `night_k()` | :411-442 | 联机走 net.room_t；昼夜 600+600 秒（map_def.gd:19-21） |
| 小地图 | `map_tex(p)` / `map_tex_layer(ln)` / `map_marks(ln)` / `open_big_map()` / `big_map_open()` | :1153-1223 | minimap.gd 的「固定底图模式」认 `map_tex` 就切过去（minimap.gd:170-184） |
| 点表 | `points(kind)` | :313-375 | 深拷贝，y 已摆到落脚处 |
| 破坏 | `Destruct.attach(self)`（:168）、`remote_blast`（:116） | destruct.gd:169-195 按 points() 划不可破坏区 |
| 其它 | `env` / `sun` / `world` / `motes` / `exit_requested` / `prewarm` / `stats_text` | | raid_manager._ready 读 `level.env` / `level.sun`（raid_manager.gd:225-226），都有 |

`points(kind)` 能给的（ex_level.gd:313-375，数据在 map_def）：

| kind | 内容 | 沙漠 | 研究所 | 老系统怎么用 |
|---|---|---|---|---|
| `spawn` | {id, pos, layer, yaw} | 4 地面 + 4 洞窟（map_def.gd:90-99） | 5（:380-385） | 出生点（ex_level 自己用） |
| `extract` | {id, pos, size, layer}（台面已建好：石柱+火盆 / 灯柱） | E1~E4（:101-106） | E1~E8（:387-394，E2/E5 高台 5 米） | **当「古传送阵」**，进 raid_manager._extracts 轮换 |
| `box` | {id, pos, kind=weapon/supply/med, layer, room, yaw} | 约 70 个 + 钥匙房 7（:325-363） | 约 100 个 + 钥匙房 30（:569-605） | **改造成 raid_search 搜点**（见 §4） |
| `camp` | {id, pos, kinds[ex_mobs id], n, r, layer, elite, set} | 约 33 处（:280-321） | 36 处（:545-565） | **raid_camps 的点表**（extract_manager.Camps 已经是这套，见 extract_manager.gd:481-560） |
| `boss` | {id, key, name, title, layer, pos, pos2, arena AABB, respawn, model, summon, altar, cages, drops, draws} | 凌幽 / 绛罗 / 沙渊巨虫（:155-166） | 凌影 / 电鞭 / 冰僵 / 铁穹双卫（:396-410） | **巢穴首领**（挂 ExBoss 大脑） |
| `altar` | 召唤祭台 | 巨虫 | 双卫 | 主干改成「走近自动刷」后可只当摆件 |
| `key_room` | {id, num, room AABB, door, dir, open_at, boxes[], tables} | k11 / k12（洞里） | K1~K10 | **当「禁制宝库」**：门一开始就打开，房里一个 vault 搜点 |
| `link` | 洞口 ↔ 光井 | 5 | 3 | ex_level 自己传送，老系统不用管 |
| `building` / `cavern` / `bound` / `poi` | 楼框 / 洞窟范围 / 边界 / 地名 | | | 地名可当信息牌；bound 给裂隙选点 |
| `horde` / `horde_point` | 夜里加刷参数 / 召唤柱 | 有 | 有 | 搜打撤专用，主干先不做（可选移植） |
| `doctor` | 天工师 | 空 | 1 | **主干不用** |

层 / 高度要点：沙漠地面 y≈20（金字塔顶 38，北峡谷底 8）、沙漠洞窟地板 11~18（洞顶 36）；研究所地面 50（二层楼板 55.5，下沉钥匙房 38~44，双子斗场 34），地下室地板 10（洞顶 28）。**多层楼 / 坑里的东西必须带自己的 y**（`floor_at` 要给 y 提示），这是老系统按 `level.ground` 摆东西最容易出错的地方。

---

## 2. ex_level 对 extract_manager / ExProfile / ExData 的依赖（逐条）

| 行 | 依赖 | 主干处理 |
|---|---|---|
| 22, 124 | `RaidProfile.test_mode()`（老存档模块，不是 ExProfile） | 不动 |
| 24, 203-215 | `MANAGER_PATH := ".../ex/extract_manager.gd"`，load 后 set level/player/cam/net/map_id/font/mobile | **改**：主干指向老 raid_manager（见 §6 E1） |
| 886-897 `_clamp_mobs` | `raid.get("_mobs")` | raid_manager 也有 `_mobs`（raid_manager.gd:158），不用改；可顺手把 `_puppets` 也夹 |
| 990-995 `_env_hurt` | `raid.env_damage(pts, "sand")`（extract_manager.gd:1374），没有就 `melee.hp - pts`（最低留 1） | raid_manager 没有 env_damage → 走兜底：沙暴每秒 3 点、不致死。要致死就在 raid_manager 补 `env_damage` |
| 1119-1128 `say` | `raid.hud.toast` | raid_hud 有 `toast`（raid_hud.gd:514），不用改 |
| 1166-1182 `map_marks` | 只读 map_def 的 extracts / key_rooms / bosses / links / pois | **改**：有 `raid._extracts` 时按它画（只画亮着且探明的传送阵 / 镇守阵 / 裂隙 / 符阵） |
| 1226-1238 `_map_blocked` | `raid.downed` / `raid.result` / `raid.hud.bag_open()`（都是 Variant 判断，缺了跳过） | raid_hud 有 `bag_open`（raid_hud.gd:342），其余缺省即可；可加 `raid.trib_active()`（渡劫中别开大地图） |
| 1270-1284 `mates` | `raid._allies`（raid_manager.gd:193 有） | 不用改 |
| 426-429 `day_sec` | 只给天工师用 | 留着无害 |
| 313-375 `points("doctor")` 等 | 数据 | 留着无害 |

**没有任何一行 ex_level 用到 ExData / ExProfile。** grid_world / map_def / ex_worm 同样没有。

---

## 3. 新图上的怪 / 首领数值：现在是什么、怎么换成老体系

### 3.1 现在（搜打撤）：扁平点数，不看境界

ex_mobs.gd:8-35：
- 主角打怪 = 招式单位 u × `HIT_PER_UNIT` 10 × 兵刃 PvE（extract_manager.gd:1275-1285 `player_dmg_vs`）
- 小怪血：沙漠 40、研究所 80；精英 ×3；巨汉（big）×2；攻：沙漠 5、研究所 12（打在 100 点条上），精英 ×1.5
- 首领血 = DarkArea 血量 × 0.04 × 人数系数 `0.6 + 0.4·min(n,4)/4`（ex_mobs.gd:185-191）：凌幽 80000→3200×k、绛罗 90000、巨虫 160000、凌影 80000（夜 ×1.9）、电鞭 / 冰僵 50000、双卫各 200000
- 首领单下封顶 35 点（`BOSS_HIT_CAP`，ex_boss.gd:30 / 248-251）
- `ExMobs.setup()`（ex_mobs.gd:225-239）把 `lv = 1`、`region = 0`、`xp_k = 0`、hp/atk 直接写点数
- ExBoss 技能表 `SKILLS`（ex_boss.gd:43-81）的 `dmg` 全是条上点数；血量缩放写死 `ExMobs.boss_hp(boss_id, n)`（:600, :646, :1338）；虫子身子 / 破土用 `float(mob.atk)`（:1427, :1448）

### 3.2 老体系（大世界）的公式

raid_manager.gd:1533-1560 `_spawn_mob`：
```
hp_max = (BOSS_HP 70 if boss else SHAPE_BASE[shape][0]) × d.hp × CS.HP_CONV × CS.mob_s_hp(ri, lv) × (ELITE_HP 2.5) × hp_k
atk    = (BOSS_DMG 10 if boss else SHAPE_BASE[shape][1]) × d.atk × MOB_DMG 0.8 × CS.ATK_CONV × CS.mob_s_atk(ri, lv) × (ELITE_DMG 1.5)
xp_k   = 14 (boss) / SHAPE_BASE[shape][3] × (3 精英)
dmg_in = player_dmg_vs.bind(m)   # CS.raid_hit（境界、等级、法宝攻、目标防量级）
atk_out = to_player_from.bind(m) # CS.to_bar（→ 100 点条，乘「守」）
```
量级 `CS.mob_scale(ri, lv, k)` 只看 `Prog.mob_tag(ri, lv)`（combat_stats.gd:78-81）；`mob_tag` 把 `realm_of(lv)` 夹进 `REGION_TAG_BAND[ri]`（progression.gd:143, 161-163）。联机木偶两边按同一个 (region, lv) 现算，天然一致。

`SHAPE_BASE`：beast [48, 12, 10, 1.0] / floater [36, 9, 9, 0.9] / brute [100, 16, 18, 2.4]（raid_data.gd:209）。大世界首领 d.hp 14~24、d.atk 1.8~2.3（raid_data.gd MOBS[10..14]）。

### 3.3 推荐：借用现有区域序号定档（Prog / CS 零改动）

| 图 / 层 | 借用 ri | 档（band） | 怪等级 = REGIONS[ri].lv + 深度×DEPTH_LV | 对应 |
|---|---|---|---|---|
| 沙海古墟 地面 | 2（血色禁地） | 元婴 [3,3] | 10 ~ 14 | 元婴入门 |
| 沙海古墟 洞窟 | 3（云梦山） | 化神 [4,4] | 13 ~ 17 | 元婴后期 / 化神 |
| 天工秘所 园区 | 3（云梦山） | 化神 [4,4] | 13 ~ 17 | 化神 |
| 天工秘所 地下室 | 4（坠魔谷） | 炼虚~大乘 [5,7] | 16 ~ 24 | 炼虚以上 |

好处：`Prog.mob_level / mob_tag / insight / pill_realm_at / suppress_gap / lair_tag / boss_level`、`CS.mob_s_*`、`Data.REGIONS[ri]` 的掉落 / 心得 / 天道压制 / 破境丹残片全部现成可用；联机一致性靠 (region, lv)，不用新字段。
代价：`REGIONS[ri]["name"]` 在提示文案里会写成「血色禁地」——文案处要换成关卡名（`level.map.name`）。

深度（0 边缘 → 1 最深）：建议在 map_def 每层加 `zone = {ri, c, r}`，`depth = clamp(1 − |p.xz − c| / r, 0, 1)`：
- 沙漠地面 c = 金字塔 (12, 82)、r = 330；沙漠洞窟 c = 沙虫竞技场 (1186, −184)、r = 420
- 研究所园区 c = 天工楼 (2, 4)、r = 390；地下室 c = 凌影场地 (901, −2)、r = 160

（备选：若想让大乘玩家进沙漠也有压力，可把 band 改成「随进图者境界抬档」，但那要在 Prog 加第 6 个区域档、改 `clampi(ri, 0, 4)` 一串地方，且各人境界不同时只能按「建怪的那个人」定档——不推荐先做。）

### 3.4 ex_mobs 每条要填的老体系倍率

搜打撤分支的 `ExMobs.setup` 直接写 hp_max / atk，**不读 def 里的 "hp" / "atk"**（现在全是 1.0）。所以这两个字段可以安全地填成老体系倍率，两条分支共用同一个文件：

- 小怪：保持 `hp 1.0 / atk 1.0`（体型基数已经拉开：沙灵守卫 / 尸傀 / 机关兵是 brute 100 血，蝎 / 狼 beast 48）；`big` 不再额外 ×2（brute 基数已含）。毒尾蝎可参照血线毒蝎给 1.2 / 1.2。
- 召唤物 wraith（幽冥泣，floater）：hp 0.8 / atk 1.1，`loot: false` 保留（老系统里不掉东西、不给心得：xp_k 置 0）。
- 首领：`hp = 18 × clamp(boss_hp / 80000, 0.6, 2.5)`、`atk = 2.0 × atk_pts / 10`：

| id | boss_hp | → hp | atk_pts | → atk |
|---|---|---|---|---|
| lingyou 凌幽 | 80000 | 18 | 10 | 2.0 |
| jiangluo 绛罗 | 90000 | 20.3 | 7 | 1.4 |
| sandworm 沙渊巨虫 | 160000 | 36 | 14 | 2.8 |
| lingying 凌影 | 80000（夜 ×1.9） | 18 | 10 | 2.0 |
| dianbian 电鞭铁卫 | 50000 | 11.3 | 10 | 2.0 |
| bingjiang 冰僵铁卫 | 50000 | 11.3 | 11 | 2.2 |
| duo_hunter / duo_welder | 200000 各 | 45 / 45（建议双卫各 ×0.5 → 22.5） | 10 / 9 | 2.0 / 1.8 |

（18 = 大世界血色禁地首领墨蛟的 hp 倍率，作为「8 万血 DarkArea 首领」的基准；数值专项再校。）

### 3.5 ex_boss 在老体系下的换算

- **技能伤害**：技能表的点数按 `pts_k = mob.atk / atk_pts` 换成原始攻击，再走 `mob.atk_out`（老体系 = CS.to_bar），最后照样封顶 35 点。搜打撤分支 `pts_k = 1`（因为那边 mob.atk == atk_pts、atk_out 返回点数），**行为逐字不变**。
- **血量缩放**：`_set_hp_max(ExMobs.boss_hp(boss_id, n) × night_k)` 改成 `_hp_one × ExMobs.players_k(n) × night_k`，`_hp_one = mob.hp_max / players_k(刷出时的人数)` 在 `_late_setup` 记下。搜打撤分支两式相等。
- **虫子身子 / 破土**（:1427, :1448）用 `float(mob.atk)` → 改 `_atk_pts()`（= def.atk_pts），统一经 `_hit` 换算，避免老体系下被换算两次。
- `dealt(d)` 嗜血按条上点数：远程分支（`t.mob_hit`）现在传原始值，老体系下原始值很大 → 传换算前的点数。
- `drop_table()` / `drop_draws()`（:318-326）是搜打撤掉落表，主干不调；首领死后走老 raid_manager 的 `_loot(ri, n, bonus, depth, pill_realm)` + 霸主精魄。
- `HIT_CAP 35`：建议主干保留（同档首领不至于一下秒人；大世界小怪没有这道封顶，首领有了更像「副本首领」）。

---

## 4. 搜点 / 刷怪点 / 撤离 / 首领：从新图点表喂老系统

### 4.1 刷怪点（raid_camps.gd）

- 老布局 `_layout`（raid_camps.gd:88-130）是 3456 米循环世界上 32 米一格、按 `Data.region_at` / `Data.land_r` / `Data.pois()` / `world._shaped` 算的，在新图上不可用。
- extract_manager.gd:481-560 的内部类 `Camps` 就是「raid_camps 状态机 + 换成关卡点表」：`_init(m, pts, map_id)` 按 `hash(map_id) + 7919·i + 104729` 定种子、每点 `defs / elite / offs`；比老版多一条「点和人高差 > 40 米不建」（:631）。
- **建议**：raid_camps.gd 加第二种构造（从 `level.points("camp")` 建 list，代码照搬 extract_manager 那段），`_layout` 在 list 非空时直接返回表里的点；`_build`（raid_camps.gd:484-487）里 `pos.y` 改问 `level.floor_at(x, z, c.y + 0.5)`，`mgr._spawn_mob(int(defs[slot]), ri, …)` 改成能收 ex_mobs 的 id（见 §5）。75 秒复活、联机交接、`code(id, slot) = id·8 + slot` 编码都不变。
- ri 按点所在层取 `level.zone_ri(pos)`，lv 按 `Prog.mob_level(ri, level.zone_depth(pos))`。

### 4.2 搜点（raid_search.gd）

- 老 `_place`（raid_search.gd:56-79）按扇区方向撒点、`_spot` 用 `Data.region_at` / `REGIONS[ri].water_h`；`_h` = `level.ground`（:125-126，只地形）。
- 新图的 `box` 点一图 70~130 个，比大世界（约 96 个铺在 6.6 平方公里）密得多，**要抽稀**。建议 map_def 加 `static func sites(m) -> Array`（按 box id 的 hash 固定抽，两人一致），种类映射：

| 新图 box | → 老搜点 kind | 说明 |
|---|---|---|
| supply 物资箱 | jar 藏物陶罐 | |
| med 医疗箱 | herb 灵药圃 | |
| weapon 武器箱 | grave 古修坟冢 | |
| 钥匙房（整间） | vault 禁制宝库 | 每间一个（取 slot 0 位置），9 秒破禁 + 引守卫，正好对上「锁着的房间」 |
| 每个首领战斗区边上 | urn 宗门宝罐 | 首领守着 |

建议数量：沙漠 ≈ jar 10 / herb 6 / grave 8 / vault 2 / urn 3（地面 2/3、洞窟 1/3）；研究所 ≈ jar 12 / herb 6 / grave 10 / vault 10 / urn 4。
- raid_search 要能收「带 y 的外部点表」：`sites` 里存 `pos.y`（points 已摆好落脚高），`tick` / `_build` 不再用 `_h` 重算 y；`_add` 里 `Prog.depth_at(ri, x, z)` 改问 `mgr.depth_of(ri, pos)`（再由 raid_manager 转问关卡）。
- 钥匙房的门：主干**进图就全部打开**（`for id in world.door_ids(): world.set_door(id, true)`），房间当宝库用；不需要钥匙道具。

### 4.3 撤离（raid_manager 的传送阵 / 镇守阵 / 裂隙 / 破界符）

- `_setup_pois`（raid_manager.gd:1373-1400）从 `Data.pois()` 取 "extract" / "boss"。新图：`points("extract")` 全部当「古传送阵」（名字「沙海古墟传送阵·E1」），`_rotate_gates`（:1421-1470）照样每 300 秒轮换「两座免费 + 一座灵石阵」；grid_world 已经在这些位置建了撤离台（石柱 + 火盆 grid_world.gd:1306-1314 / 灯柱 :2284-2289 / 台面 :1077-1081, :1739-1745），`_build_extract` 的光柱阵叠上去正好。沙漠只有 4 座，亮 3 座偏多——可以改成沙漠「一座免费 + 一座灵石阵」。
- 镇守阵：老做法是巢穴往世界中心挪 34 米（:1393-1399），新图要改成「首领战斗区朝 play 中心那一边的外沿」——建议 map_def 每个首领给 `lair_ex` 点，或 ex_level 加 `points("lair")`。
- 裂隙 `_open_rift`（:2778-2790）在离原点 160~1150 米的环上找 `_ground > 2` 的点 → 新图会落到边界外。改成问关卡：`level.rift_spot(seed)`（从 play 矩形里 `find_spawn_near` 抽，地面层优先）。
- 破界符 `_use_tool`（:2605）的「海上起不了阵」判断在新图恒为陆地，不用改。
- 20 分钟时间线 `_timeline`（:2744）照旧。

### 4.4 首领（巢穴）

- 老 `_update_bosses`（raid_manager.gd:1627-1660）：一个巢穴一只 `Data.REGIONS[ri]["boss"]`，走近 200 米刷，打掉 600 秒（LAIR_BACK）后再来，联机靠 meta `lair` + 编号小的留。
- 新图：每个 `points("boss")` 当一个巢穴；种类 = ex_mobs id（`BOSS_KEY` 映射 worm→sandworm、twin→duo_hunter+duo_welder，extract_manager.gd 常量）；等级 `Prog.boss_level(Prog.lair_tag(ri), lv + 2)`；刷出后 `ExBoss.attach(m, id, arena_rect, {home, y_range, net, fx_out, summon_fn, night_fn = level.is_night, room_n_fn, floor_fn, pts_k})`（照 extract_manager.gd:3405-3430）。
- 召唤型（巨虫 / 双卫）：主干**去掉祭台召唤**，和别的首领一样走近自动刷（ExMobs.SUMMON_MIN 本来就是 1）；祭台 / 笼子留作摆件，倒计时字可复用 `ExBoss.countdown_label`。
- 重生：用 ex_mobs 的 respawn（500~600 秒），和 LAIR_BACK 600 一个量级。
- 联机画面：ExBoss 的技能画面要 `fx_out` 广播、木偶那边 `attach_remote` + `play_remote`。net.gd 已有 `ex_boss_fx` / `_ex_boss_fx → raid.net_ex_boss_fx`（net.gd:1301-1312），以及房主仲裁首领归属的 `ex_boss_claim / _owner / _release / _dead`（:1215-1300）。**这几条 RPC 主干要留**（名字可以不改），raid_manager 补 `net_ex_boss_fx`（照 extract_manager 搬）；box / door / revive 那几条可以删。

### 4.5 神识（shen_shi.gd）

- 地形光波：`_world_mats`（shen_shi.gd:312-324）取 `level.world.mat`；GridWorld 继承 block_world、用同一个地块材质（ex_level._apply_atmo 也在写它，ex_level.gd:547-556），光波直接能用，楼 / 遗迹也并在地块网格里会一起被扫到。
- 目标收集 `_collect`（:171-253）读 `mgr.search.sites / _pickups / _mobs / _puppets / _rivals / net.remotes / _extracts`——全是 raid_manager 的字段，新图不用改。
- 光带高度用 `mgr._ground`（:704）：楼顶 / 洞窟会贴地形走，可接受。

### 4.6 陨落 / 局域网

- 陨落规则全在 raid_manager `_finish(false)`（:2869-2915，联机留储物袋）+ `Profile.end_raid`，地图无关；死亡掉落点建议用 `level.floor_at`（楼上死的别掉到一楼）。
- 局域网：net.gd 房间按 map_id 分（main.gd:884-892 已经 `net.set("map_id", _id)`）；raid_manager `net.enter_world(self)` 那一套（:244-260）和大世界一样。中途加入的地形破坏 `level.world.apply_dug / crater_changes`（:249-258）在 GridWorld 上是空实现，新图的破坏同步走 Destruct 自己的 RPC，没冲突。
- 循环世界换像 `Data.near(base, ref)`：新图所有坐标间距 < 1728 米（沙漠地面最西 −380 到洞窟最东 1292 = 1672 米；研究所 −401 ~ 1032），`near` 恒等于原值，**不用改**，但这是个靠数字凑出来的前提（见风险）。

---

## 5. 老系统侧需要的挂钩（不是我负责的文件，给对应代理）

raid_manager.gd（建议加一组「关卡有就问关卡」的小函数，木兰草原 `level` 没有这些方法 → 原样）：
- `_ri_at(p)`：`level.zone_ri(p)` 否则 `Data.region_at`。替换 :351, :867, :1679, :1815, :1912, :1962, :2029, :2041 处的 `Data.region_at`；`depth_of`（:340-342）转问 `level.zone_depth(p)`。
- `region` 每帧更新在 `_blend_atmosphere` 里（:1331），而它还会写 env / sun / world.mat / motes（:1117-1345），**会和 ex_level._apply_atmo 打架** → 新图跳过 `_blend_atmosphere`（:2925, :2943），只更新 `region = _ri_at(p)`、`at_sea = false`。
- `hud.title("木兰草原", …)`（:290）→ 用 `level.map.name / sub`。
- `_spawn_mob(def_idx, …)`（:1533）收 ex_mobs id：`d = ExMobs.def(id)`，其余公式不变；`floor_fn = _ground` 保持（ex_mobs 本来也只贴地形，extract_manager.gd:1129），**加 `m.block_fn = Callable(level, "blocked")`**（新图两张都加，extract_manager 现在只给 lab 加，沙漠遗迹 / 金字塔也该挡）；`set_meta("def_idx", EX_NET_BASE + ExMobs.idx(id))`。
- 联机怪种类编号：`net_mob_apply`（:684）、`spawn_wave / spawn_guards`（:1818-1853）用 `Data.MOBS[def_idx]` → 换成 `Data.mob_def(i)`：`i < MOBS.size()` 取老表，`i >= 100` 取 `ExMobs.by_idx(i − 100)`。全仓 `Data.MOBS[` 只有 12 处（raid_manager 6、raid_camps 3、两个自检 3）。
- `spawn_guards / spawn_wave` 的怪池 `Data.REGIONS[ri]["mobs"]` → 新图用 `ExMobs.CAMP_POOL[map_id]`（宝库守卫 / 游荡首领也该是本图的怪）。
- AI 修士 / 道友落点（`spawn_rival`、`_ally_spot`）→ 有 `level.find_spawn_near` 就用它（不刷进墙里 / 别的层）。
- 补 `env_damage(pts, kind)`（沙暴是否致死由数值定；不补就是不致死）。
- 入口：元婴（`Realm` 下标 3）以上才能进，门的判定在 main.gd:1116 `_on_hub_gate` / hub_hall；ex_level 自己再兜一道（§6 E9）。

minimap.gd:363-377：固定底图模式下撤离点只画关卡点表（`[] if _fixed else _arr("_extracts")`）→ 改成 mgr 有 `_extracts` 就用 mgr 的（亮 / 熄 / 探明 / 种类颜色），没有才画点表。或者由 ex_level.map_marks 代劳（§6 E5），二选一。

---

## 6. 要改的文件和具体改法（我这块）

### ex_level.gd（主干）
- **E1** :24 `MANAGER_PATH` → `"res://scripts/raid_manager.gd"`（或主干新写的 `zone_manager.gd extends raid_manager.gd`）；:203-215 的 set 不变（raid_manager 没有 `map_id` 字段，`set` 会被忽略；需要的话给它加 `var map_id := ""`）。
- **E2** 在 :405 后加区域接口：
  ```gdscript
  func zone_ri(p: Vector3) -> int:        # 借用的区域序号（map_def 的 zone 表）
      return int(((map["zone"] as Dictionary)[layer_of(p)] as Dictionary)["ri"])
  func zone_depth(p: Vector3) -> float:   # 0 边缘 → 1 最深
      var z: Dictionary = (map["zone"] as Dictionary)[layer_of(p)]
      return clampf(1.0 - Vector2(p.x, p.z).distance_to(z["c"]) / float(z["r"]), 0.0, 1.0)
  func min_realm() -> int:
      return int(map.get("min_realm", 3))
  func rift_spot(seed: int) -> Vector3:   # 裂隙落点：地面层 play 矩形里
  ```
  并给 `points()`（:313-375）加 `"site"`（= `MapDef.sites(map)`）和 `"lair"`（首领战斗区外沿的镇守阵位）。
- **E3** :165 `add_child(world)` 之后：主干把钥匙房门全打开 `for id: String in world.door_ids(): world.set_door(id, true)`（搜打撤分支不加）。
- **E4** :886-897 `_clamp_mobs` 顺手把 `raid._puppets` 也夹在洞顶下（老 raid_manager 有 `_puppets` 字典）。
- **E5** :1166-1182 `map_marks`：`raid` 有 `_extracts` 时，撤离点改从它出（只出 active 的，kind 带上），key 标记可留（门都开着 → "key_open"）或删。
- **E6** :1226-1238 `_map_blocked`：加 `raid.has_method("trib_active") and raid.trib_active()`。
- **E7** :990-995 `_env_hurt`：不用改；若 raid_manager 补了 env_damage 自动生效。
- **E8** :426-429 `day_sec`：留着（无害），或主干删。
- **E9** `_ready` 末尾：`player.realm_idx < min_realm()` 时 `say("境界不足，元婴方可入此秘境")` 并 deferred `exit_requested.emit()`（主城门是第一道，这里兜底，防自检 / 联机跟随进来）。

### map_def.gd（两条分支共用，只加不删）
- **M1** `_desert()` / `_lab()` 各加 `m["zone"]`：
  - desert：`{"surface": {"ri": 2, "c": Vector2(12, 82), "r": 330.0}, "cavern": {"ri": 3, "c": Vector2(1186, -184), "r": 420.0}}`
  - lab：`{"surface": {"ri": 3, "c": Vector2(2, 4), "r": 390.0}, "cavern": {"ri": 4, "c": Vector2(901, -2), "r": 160.0}}`
  - 两图 `m["min_realm"] = 3`
- **M2** 加 `static func sites(m: Dictionary) -> Array`：从 `m["boxes"]` 按 §4.2 的映射和数量固定抽（`hash(box id + map id)`），钥匙房一间一个 vault，首领战斗区外沿各一个 urn；返回 `[{id, kind, pos(带 y), layer}]`。
- **M3** 每个 boss 加 `"lair_ex"`（镇守阵位：arena 朝 layer center 那边外沿再外 10 米，y 由 ex_level.floor_at 摆）。
- **M4** 不删：`death_drop_stacks` / `box_quality`（:76, :370）、钥匙房 `tables`、boss `drops / draws / drops_night`、`doctor`（:395）、`horde`（:212, :517）——主干不读，保持两边同一份数据。

### grid_world.gd
- 不用改。撤离台、门、屋顶隐藏、整图底图、破坏都和管理器无关。（`door_ids()` :828 已有。）

### ex_mobs.gd（两条分支共用）
- **X1** MOBS 表（:37-102）首领条目的 `"hp" / "atk"` 按 §3.4 填老体系倍率；小怪按需微调（brute 不再叠 big）；wraith 填 floater 倍率。搜打撤分支的 `setup()` 不读这两个字段，不受影响。
- **X2** 加 `const NET_BASE := 100` 和 `static func setup_realm(m, id, elite, ri, lv, players := 1, hp_k := 1.0)`：照 raid_manager._spawn_mob 的公式写 def / region / lv / elite / hp_max（首领再 × `players_k(players)`）/ atk / xp_k（`loot == false` 的置 0）/ tag_text / meta `ex_id`、`def_idx = NET_BASE + idx(id)`、`loot`。raid_manager 和自检都调它，公式只有一份。（若数值代理更想全放在 raid_manager._spawn_mob 里，那就只加 NET_BASE。）
- `IDS` 顺序不要动（:105，联机编号）。

### ex_boss.gd（两条分支共用）
- **B1** 加 `var pts_k := 1.0`，`setup()`（:181-203）读 `opts.get("pts_k", 1.0)`。
- **B2** `_hit`（:440-464）：`var pts := minf(dmg * dmg_k, HIT_CAP)`；`var raw := pts * pts_k`；本机 `d = minf(atk_out.call(raw), HIT_CAP)`；远程 `t.mob_hit(raw, …)`，`dealt(pts)`。
- **B3** 加 `var _hp_one := 0.0`，`_late_setup`（:240-261）记 `_hp_one = mob.hp_max / ExMobs.players_k(_n_spawn)`（`_n_spawn` 由 opts 传，默认 1）；:600 / :646 / :1338 的 `ExMobs.boss_hp(boss_id, n)` 全换成 `_hp_one * ExMobs.players_k(n)`。
- **B4** :1427 / :1448 的 `float(mob.atk)` → `_atk_pts()`（`float(ExMobs.def(boss_id).get("atk_pts", 10.0))`）。双卫变身 :1349 / :1362 改 `mob.atk` 的保留（影响 raid_mob 自己的扑击，两边都对）。
- `drop_table / drop_draws` 留着，主干不调。

### ex_worm.gd
- 不用改。

### ex_doctor.gd
- 主干不引用（只有 extract_manager.gd:4023-4186 建它）。文件可留在主干不用，或删——建议留（两边同一份、体积小、不进逻辑）。

### extract_manager.gd / ex_hud.gd / ex_profile.gd / ex_data.gd
- 主干不再被 ex_level 加载（E1 之后）。是否从主干删除由经济代理定；注意 `ex_selftest.gd` / `ex_level_shot.gd`（main.gd:308 的 `--level-test / --level-shot` 钩子）直接依赖 extract_manager，主干要么一起删、要么让它们在没有 extract_manager 时跳过。

---

## 7. 保留 / 丢弃清单

保留（主干照用）：两张图的全部几何与碰撞（grid_world）、两层 + 洞口传送、昼夜和天色、沙暴 / 光幕 / 深谷边界、整图小地图 + 全屏大地图、场景破坏、出生点表、刷怪点表、首领 + ExBoss 技能大脑（含巨虫、凌影夜形态、双卫变身 / 焊愈）、撤离台位置（当传送阵）、钥匙房（当禁制宝库，门常开）、ex_mobs 的造型 / 名字 / 种类。

丢弃（只在搜打撤分支）：营救天工师（ex_doctor + extract_manager「天工师」一节 + net `_doc_*`）、钥匙 / 钥匙房开门读条与复原、箱子开箱读条 / 复原 / 掉落表（ExData 表名）、夜里尸潮加刷（可选以后移植成「夜里刷怪加密」）、重伤倒地 / 救人、900 秒个人限时与扁平点数数值、祭台召唤、死亡遗物箱堆数。

---

## 8. 风险 / 没验证的

1. **`Data.near` 恒等的前提**：新图最大坐标跨度 1672 米，离半圈 1728 只差 56 米。以后有人加第三层（比如 x + 2000）或扩洞窟，所有 `Data.near` 会把东西换到另一个「像」去——建议 raid_manager 在新图上干脆跳过换像（`_reimage`、net 收到的位置），或 ex_level 提供 `near()` 恒等实现。
2. **天色互相覆盖**：raid_manager `_blend_atmosphere` 不跳过的话会把新图的天、雾、日光、地块补光全改成大世界区域色。必须处理。
3. **多层楼的 y**：老系统处处 `level.ground`（只地形）。搜点、掉落、宝库守卫、死亡储物袋、AI 落点都要带 y 或问 `floor_at(x, z, y)`；`floor_at` 不给 y 会落到屋顶（ex_level.gd:100-103）。
4. **怪穿墙**：老 `_spawn_mob` 不设 `block_fn`；新图（尤其研究所的楼、院墙）必须设。沙漠现在也没设（extract_manager.gd:2977 只 lab），金字塔 / 方山 / 遗迹会被穿。
5. **首领联机**：ExBoss 画面同步依赖 net.gd 的 `ex_boss_fx` RPC；首领归属老系统用「meta lair + 编号小的留」，新系统用房主仲裁（`ex_boss_claim`）。两种不要混用，建议主干新图首领沿用房主仲裁（更稳），需要 raid_manager 补 `net_ex_boss_owner` 等回调。
6. **搜点密度 / 收益**：新图面积小、箱子密，直接照搬 box 点会远超大世界的搜点收益；§4.2 的抽稀数量是估的，要用 `--raid-econ` / pace 实测校。传送阵数量（沙漠 4 座）也要按轮换规则调。
7. **档位**：借用 ri 2/3/4 的做法让沙漠地面只到元婴档、研究所地下室到大乘档；大乘玩家在沙漠会被天道压制（心得打折）——这是老规则的自然结果，但和「高难区」的期待是否一致要用户确认。
8. **英雄模式战斗固定结丹档**（别的代理在改）：ExBoss 的 `_hit` 走 `p.melee / p.air.receive_attack`，不看英雄；但主角打首领的 `dmg_in` 如果英雄模式不走 CS.raid_hit，老体系的怪血会打不动——要和英雄代理对齐「英雄伤害 = 跟随境界」。
9. **自检**：`ex_selftest` / `ex_level_shot` / `ex_boss_selftest` 都按搜打撤管理器写的，主干要新写一份「新图 + 老系统」的冒烟自检（进图、刷点建怪、搜一个点、首领刷出、撤离、陨落、双开同图）。
10. 未实测：以上全部是读代码得出的，没有跑过；新图在老 raid_manager 下的帧耗（raid_search 节点 + 神识 + ExBoss 弹幕池）没量过，手机档要量。
