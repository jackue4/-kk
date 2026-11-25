# W_maps 交付报告：两张新图（沙海古墟 / 天工秘所）

代号 W（地图），负责 SPEC 第 5 节和第 1.3 节「关卡契约」。2026-11-24。

## 0. 一句话

两张图都能从主城门 2 / 门 3 进去、走完一整圈：地面 + 洞窟（地下室）、进出洞口要黑场 0.4 秒、楼里撞墙撞顶、屋顶进楼就藏、钥匙房的门能开关、沙暴推回 + 掉血、禁制光幕弹回、昼夜按房间时钟、小地图固定底图 + 全屏大地图。
`--level-shot=desert|lab` 两档渲染器各跑一遍，自检 0 项失败；网页档（兼容渲染器 + 触屏 + 单线程分帧）每张截图都在预算里；老大世界 `--raid-shot` 跑完。
`extract_manager.gd` 还没有（E 在写），所以现在 `raid = null`，关卡照样能走；有了这个脚本就自动建。

## 1. 文件清单

| 文件 | 新 / 改 | 内容 |
|---|---|---|
| `scripts/ex/map_def.gd` | 新 | 两张图的布局数据：DarkArea 全部点位按 SPEC 5.1 换算 + 补的箱子点 / 刷怪点 / 楼 / 遗迹 / 洞窟网 / 边界 / 夜里尸潮。`MapDef.map(id)` 生成一次后缓存 |
| `scripts/ex/grid_world.gd` | 新 | 继承 `block_world.gd` 的数据驱动方块世界：载入时烘地形表 + 摆建筑 + 全图静态登记实心盒子；屋顶 / 楼板 / 盖板单独网格；钥匙房的门；边界幕；整图小地图底图 |
| `scripts/ex/ex_level.gd` | 新 | 关卡节点（关卡契约）：环境 / 太阳 / 昼夜、落脚与挡路、镜头、进出洞窟、边界、点表、大地图 |
| `scripts/ex/ex_level_shot.gd` | 新 | `--level-shot=desert|lab` 探针 |
| `scripts/block_world.gd` | 改（只加钩子） | `_init` 的内容挪进可覆盖的 `_setup_content()`；`_want_sea()`、`_key_ok(key)` 两个钩子（`_plan` / `_plan_far` / `ready_near` 问它）。默认值 = 原行为 |
| `scripts/minimap.gd` | 改（加模式） | 固定底图模式（关卡有 `map_tex()` 就用）、点一下开大地图、mgr 的字段缺了就跳过；文件末尾加内部类 `BigMap`（全屏大地图） |
| `_tasks/extraction_refactor/w_maps/gw_test.gd` | 新（自检工具） | `-s` 跑的离线检查：两张图烘表耗时、静态盒子数、每块几何量、点的高度、一块细地块的生成耗时 |

备份：`_tasks/extraction_refactor/backup/block_world.gd.txt`、`minimap.gd.txt`（动手前的样子，含别的会话还没提交的改动）。

为什么继承 block_world 而不是自写网格：block_world 的细 / 粗地块 + 远景色块调度、网页单线程分帧、工作线程、四角假 AO + 岩层分色的 `_mesh_row`、实心盒子查询这些都能原样用；它跟区域绑死的地方（`_pal[ri]`、`SHADE[ri]`、`dim = ri == 2 or 4`）只要新图的区域号也在 0..4 里就天然对得上。要改的只有三个钩子。实测老大世界 `--raid-shot` 跑完、行为不变。

## 2. 两张图怎么搭的

### 2.1 坐标换算（SPEC 5.1，`map_def.gd` 顶上的 `ds / dc / ls / lb`）

| 层 | x' | z' | y' |
|---|---|---|---|
| 沙漠地面 | (x−231)×2 | (499−z)×2 | y−50（DarkArea 地面 70 → 20） |
| 沙漠洞窟 | 同上 **+1000** | 同上 | y+7（地下 3..27 → 10..34） |
| 研究所园区 | (x+1022)×1.5 | (528−z)×1.5 | y−40（地面 90 → 50） |
| 研究所地下室 | 同上 **+900** | 同上 | y−21（凌影 31 → 10；不能低于 0） |

两层在同一张图的两片坐标里（x > 600 的是洞窟 / 地下室，`MapDef.layer_at(p)`）。方块世界一次只排主角所在那一层的块（`grid_world._key_ok`），另一层不建；进出洞窟时换层（`set_layer`）。

### 2.2 沙海古墟（desert）

- 地形表：地面 864×1024 米（2 米一格），洞窟 576×576 米。
- 地面：沙丘（噪声，1 米一级）+ 戈壁（砾石地）+ 12 座赤岩方山 + 30 处遗迹（石柱圈 / 断墙 / 图腾 + 断像 / 石拱门 / 倒伏巨像 / 小神龛，种子固定）+ 金字塔四面神道石柱 + 散落的仙人掌 / 枯灌木 / 兽骨 / 碎石。
- 黄金神塔：中心 (12, 82)，六层三米退台 + 四面一米一级的石阶，塔顶 48×44 的石板台 = 凌幽的战斗区（台面 38，DarkArea X225..249 Z447..469）。四角方尖碑 + 火盆、正中一圈金色符文、石阶脚下八尊守门兽。
- 北峡 C：一道从 (−74,−78) 一路下到 (12,−100)（谷底 8 米）的峡谷，尽头崖壁上的洞口通洞窟 C 点。
- 洞口 U1..U4：一个下沉 7 米的坑（坡道下去），坑底崖壁上开门框（木柱 + 横梁 + 两支火把）。
- 外圈边界：play 矩形（DarkArea 战区）外 8~48 米一圈 30~60 米高的三层赤岩台崖，每边两个缺口；崖外是沙暴带（离 play 外沿 30 米起刮、100 米最浓）；硬夹钳在外沿 110 米（x ±380、z ±456）。全图飞行上限 65（地面 + 45）。沙暴带外侧立两圈半透明的「沙暴幕」。
- 洞窟：一整片岩体（顶 41）里挖 12 条隧道（宽 14~16 米）+ 洞厅，连成一个环：西洞（U2 → 钥匙房 11 前厅、绛罗场地 64×64、出生 s5）—南隧道（U3 → s8 → s7）—东洞（U4 → 钥匙房 12 → s6 → 沙虫竞技场 88×88 + 祭台 + 四角铁笼）—北隧道（U1 / C → s5）。洞顶 36（两个 Boss 场地 40），洞顶是一张朝下的暗色网格；隧道两壁每 26 米一支火把（烘成地上的光池）、隔一支一副矿道木架；洞厅里有晶簇；进出口是一束从顶上照下来的「光井」。
- 钥匙房 11 / 12：房间的三面是岩壁，朝前厅那面是一堵直通洞顶的墙 + 朱红门框 + 门（门可开关）。

### 2.3 天工秘所（lab）

- 地形表：园区 928×928 米，地下室 256×272 米。园区地面 50，混凝土（8 米分缝）+ 荒草 + 锈土 + 石板路网（铜边）。
- 外圈边界：离中心 396~404 米一圈 16 米高的围墙（带垛口）→ 墙外 40 米宽、谷底 6 米的深谷 → 远处 60 米的崖壁；墙头往上一圈青色竖条的「禁制光幕」（398 米处）。地上走被墙挡；飞过墙头被光幕弹回（提示「禁制光幕：此路不通」）；万一掉进深谷，送回最近的墙内。硬夹钳 ±401。飞行上限 85（地面 + 35）。
- 天工楼院：210×120 的院墙（四道院门，门上朱红牌坊）；正中「天工楼」64×48、两层（层高 5.5），一层四个门，二层平台（天工师的房间在上面，`doctor` 点 (1.5, 55.5, 3)）+ 楼梯；平顶 + 中式出檐屋顶。院子西北角一座五层「天工塔」（全图地标）。院里三间下沉钥匙房 K1 / K2 / K3。
- 楼梯口 u3 / u4 / u5：院外三座「梯亭」（能进，里面一口往下 5 米的梯井），井底传到地下室「尸傀密窟」（凌影的 63×63 场地 + 三条隧道）。
- 百炼坊（南）：108×58 两层厂房，西半边二层平台上是钥匙房 K4；屋顶三根烟囱；南面 4 米高的台子 = 电鞭铁卫的场地。
- 镇尸营（北）：10 米高的台子 = 冰僵铁卫的场地（四根冰晶铜柱 + 冰棱），台子南边台下嵌着钥匙房 K7（顶板就是场地的一部分）；营房两座；K6 在营地东边的坑里。
- 双子斗场（东）：下沉 16 米的圆形斗场（半径 26 的场地 + 八级台阶看台 + 东西两道坡道），召唤台在场地北沿，看台外两尊铜卫像。
- K5：东侧的大下沉实验仓；K8 / K9：西区两个浅坑；K10：东区孤立小屋（门就是钥匙房的门）。
- 其他能进的楼 24 栋（工坊 / 库房 / 营房 / 棚屋 / 匠舍，五种样式：混凝土 + 朱红门框 / 锈铁棚 / 铁门库房 / 白墙木构）；楼里沿墙有货架、木箱、工作台。
- 园区杂物：150 处（货堆、铁桶、地上铜管、立着的大齿轮）、两条架空铜管廊、八座望楼、六根夜里发绿光的「尸傀召唤柱」（`horde_point`）、沿路每 36 米一盏冷光灯。
- 风格：灰白混凝土 + 锈铁 + 青铜机关 + 朱漆木构（门框、檐梁、牌坊、天工塔），夜里窗户 / 灯头 / 召唤柱发冷光。

### 2.4 和 DarkArea 不一样的地方（都有理由，需要的话可以改 map_def）

- 钥匙房：DarkArea 的「区域盒」只是复原箱子的判定框，本作在框里摆一间实际的房间，门放在离原门最近的那面墙上（偏差 ≤ 6 米，原值在 `da_door / da_box`）。
- 下沉钥匙房的坑深：DarkArea 是地面下 17~33 米，本作统一 6~12 米（坑底 38~44，都在 SPEC 的 17~47 之间），坑里是「门前空场 + 一米一级的坡道」。
- 出生点的 y 一律落在地面（DarkArea 原值差 1~3 格的高低）。
- 沙漠的 U1..U4 / C 在 DarkArea 只是图标，这里做成「坑 / 峡谷 + 洞口传送」；研究所 u1 / u2 / u6 只是图标（没做传送），u3 / u4 / u5 是梯亭 → 地下室。
- 研究所撤离 E2 / E5 原图在高台上（y96 / 95），这里是 5 米高的撤离台 + 朝园内一侧的台阶。
- 双子斗场的场地大小 DarkArea 没有（编辑器里填的区域 ID），按「半径 26 + 看台」自定。

## 3. 关卡契约 + 给 E 的接口（`scripts/ex/ex_level.gd`，原样照实现写）

main.gd / net.gd 要的（SPEC 1.3）：

```
signal exit_requested
signal layer_changed(layer: String)          # 主角进出洞窟之后（新层名 "surface" / "cavern"）
signal hazard(kind: String, k: float)        # 边界："sand" 沙暴（k = 浓度 0..1，每物理帧）/ "barrier" 光幕弹回 / "chasm" 掉谷送回
var player: Player; var cam: CameraRig; var font: Font; var mobile := false; var net: Node; var map_id := "desert"
var raid: Node            # extract_manager.gd 实例；没有这个脚本时为 null
var env: Environment; var sun: DirectionalLight3D; var world: GridWorld; var motes: CPUParticles3D
var map: Dictionary       # = MapDef.map(map_id)（只读）
var layer := "surface"    # 本机主角现在在哪一层
var teleport_links: Array # = map["links"]
func spawn_point() -> Vector3        # 进图时随机挑好（沙漠 8 个：地面 4 + 洞窟 4；研究所 5 个），自检固定第一个；y 贴地
func spawn_yaw() -> float            # 面朝这一层的中心
func prewarm(timeout := 10.0) -> float   # await；等脚下 3×3 细地块；网页单线程时一帧给 45 毫秒、最多等 45 秒
func stats_text() -> String
func ground(x: float, z: float) -> float  # 地形高度（不算建筑）
func remote_blast(p: Vector3, r: float) -> void   # 空实现（不破坏地形）
world.dug_table() -> {}   world.dig(p, r, f) -> 0   world.crater_changes(...) -> 0   world.apply_dug(...) 空   world.map_colors / map_cells 有（兜底用）
```

`_exit_tree` 还原：`Vfx.terrain_hook`（进图时换成恒 false）、`cam.floor_fn / occl_fn`、`cam.cam.far`、景深三项、`player.ground_ref`、`player.bound = Player.BOUND`、`CreatureModels.shadows`，关掉大地图。

给 E（extract_manager）用的：

```
func floor_at(x: float, z: float, y := INF) -> float
    # 脚在 y 的人 / 怪 / 掉落物在 (x, z) 踩在多高：地形 + 底面低于 y+1.6 的实心盒子的顶面（楼板、台基、箱顶）。y 省略 = 最高的顶面
func solid_at(p: Vector3) -> bool            # p 在地形下面 / 实心盒子里 / 洞顶上面
func blocked(from: Vector3, to: Vector3) -> bool
    # 从 from 走到 to（脚在 from.y）有没有墙：每 0.5 米探一下，比当前脚面高出 2.25 米以上的地形 / 实心盒子就是墙（走上台阶后按新脚面接着探）。给 raid_mob 的 block_fn
func layer_of(p: Vector3) -> String          # "surface" / "cavern"
func y_cap(p: Vector3) -> float              # 脚的绝对高度上限：飞行上限 / 洞顶 − 2.1 / 头顶楼板 − 2.1，取最低
func points(kind: String) -> Array           # 见第 4 节
func find_spawn_near(center: Vector3, r_min: float, r_max: float, rng: RandomNumberGenerator = null) -> Vector3
    # 环上找一处能站的地方（同一层、play 矩形内、不在墙里、地面和 center 差 6 米以内、不贴洞顶）；24 次找不到返回 center。夜里尸潮 / 带着天工师时刷怪用
func set_door(id: String, open: bool) -> void   # 钥匙房的门：开 = 立刻不挡路、门板 0.6 秒沉进地里；关 = 立刻挡路、门板升起。id = "k11" "k12" / "K1".."K10"
func door_open(id: String) -> bool
func room_time() -> float     # 房间时钟：联机 net.room_t，单机关卡自己的时钟（+ clock_off）
func day_phase() -> float     # 一个昼夜周期里的第几秒：0..600 白天、600..1200 黑夜
func is_night() -> bool       # day_phase() >= 600
func day_sec() -> float       # 白天第几秒（夜里 -1）：营救天工师「白天第 180~300 秒」
func night_k() -> float       # 天色有多「夜」0..1（白天最后 6 秒入夜、夜里最后 6 秒天亮）
func say(text: String, col := Color(1.0, 0.86, 0.62)) -> void   # 一行提示：有 raid.hud.toast 就走它，没有用关卡自己的
func map_tex(p: Vector3) -> Dictionary        # 小地图固定底图：{tex, center: Vector2, span: float, layer}
func map_tex_layer(ln: String) -> Dictionary
func map_marks(ln: String) -> Array           # [[世界坐标, 种类, 名字]]：extract / key / key_open / boss / link / poi
func open_big_map() -> void; func close_big_map() -> void; func big_map_open() -> bool   # 全屏大地图（也可以按 M）
func mates() -> Array                         # 队友位置（raid._allies + net.remotes 里 mate 的）
```

关卡会调 manager 的（鸭子类型，没有就跳过）：
- `raid.env_damage(points: float, kind: String)`：沙暴每秒 3 点（kind = "sand"）。**没有这个方法时关卡直接扣 `player.melee.hp`（最低留 1 点）**——E 接上之后请走自己的受伤 / 重伤流程。
- `raid.hud.toast(text, color)`：边界提示。
- `raid._mobs`（Array）：洞窟里每物理帧把怪夹在洞顶 − 3 米以下。

## 4. `points(kind)` 的字典形状（深拷贝；带 y 的点都已贴到实际落脚处）

| kind | 每项 | 数量 |
|---|---|---|
| `spawn` | `{id: "S1"/"s5", pos: Vector3, layer, yaw: float, da: Vector3}` | 沙漠 8（地面 4 + 洞窟 4）/ 研究所 5 |
| `extract` | `{id: "E1", pos: Vector3（撤离台台面中心）, size: Vector3（整个盒子：沙漠 24×6×24；研究所 30×7×18 或 18×7×30）, layer: "surface", da: Vector3, raised?: float（研究所，E2 / E5 = 5）}` | 4 / 8 |
| `box` | `{id: "b12", pos: Vector3, kind: "weapon"/"supply"/"med", layer, room: ""/"k11"/"K3"（钥匙房里的写房间 id）, yaw: float, bld?: 楼 id}` | 沙漠 78（钥匙房 7）/ 研究所 131（钥匙房 30） |
| `camp` | `{id: "c3", pos, kinds: Array[String], set: String（= kinds[0]）, n: int（3~5，精英 2~3）, r: float（散开半径）, layer, elite: bool}` | 沙漠 34（地面 25 + 洞窟 9）/ 研究所 26（地下室 3） |
| `key_room` | `{id, num, kind: "cave"/"pit"/"floor"/"deck"/"hut", layer, room: AABB（房间内部）, door: Vector3（门洞底边中点）, dir: Vector3（门朝外）, door_yaw, door_w, door_h, door_id（= id）, open_at: Vector3（站这儿开门）, wall_top, tables: {supply: "desertLockedSupplyBox"/"labLockedSupplyBox", weapon: "...LockedSWeaponBox"}, boxes: Array[String]（房里的箱子 id）, slots, da_door, da_box: AABB, open: bool（现在开着没有）}` | 2 / 10 |
| `boss` | `{id, key, name, title, layer, pos: Vector3（出生）, pos2?: Vector3（双卫的第二只）, arena: AABB, respawn: float, model: String, model2?, drops: String, drops_night?（凌影夜晚形态）, draws: int, summon: bool, cooldown?: float, altar: Vector3 或 null, cages?: Array[Vector3]（沙虫四角牢笼）, da}` | 沙漠 3（凌幽 lingyou / 绛罗 jiangluo / 沙渊巨虫 worm）/ 研究所 4（凌影 lingying / 电鞭铁卫 dianbian / 冰僵铁卫 bingjiang / 铁穹双卫 twin） |
| `altar` | `{id: "altar_W", boss: "W", pos, layer}` | 沙虫 1 / 双卫 1 |
| `doctor` | `{pos: Vector3(1.5, 55.5, 3)（天工楼二层）, layer: "surface", da}` | 研究所 1，沙漠空 |
| `link` | `{id, a: Vector3（地面一侧的触发点）, a_out（从洞里上来落在哪）, a_yaw, b（洞里的光井）, b_out, b_yaw, r: 触发半径（2.6~2.8）, center?/f?/da?（研究所梯亭）}` | 沙漠 5（U1~U4、C）/ 研究所 3（u3~u5） |
| `building` | `{id, name, rect: Rect2（外墙占地）, floor, top（墙顶）, enterable: true, storeys, layer, upper?: Rect2, upper_y?}` | 沙漠 0 / 研究所 30 |
| `cavern` | `{id: "cavern", layer: "cavern", rect: Rect2, ceil, floor_min, fly_cap}` | 1 / 1 |
| `horde` | `{interval: 90, r_min: 20, r_max: 40, n_min: 3, n_max: 5, kinds: ["zombie"], cap: 15}` | 研究所 1 |
| `horde_point` | `{pos, layer}`（尸傀召唤柱，夜里尸潮的地标，可选用） | 研究所 6 |
| `poi` | `{id, name, pos, kind: "boss"/"area"/"cave", layer}` | 4 / 5 |
| `bound` | `{layer, rect（硬夹钳）, play（DarkArea 战区换算）, fly_cap, ceil}` | 每层一项 |

`level.map` 里另有 `death_drop_stacks: 2`、`box_quality: "senior"/"lab"`、`name`、`sub`。刷怪点的 `kinds` 用的模型名：沙漠 `scorpion / wolf_sand / sand_guard / sand_raider`，研究所 `zombie / mech_claw / mech_gunner / gel_mutant`。

## 5. `grid_world.gd`（`level.world`）

```
func setup(id: String) -> void          # 烘表 + 摆件 + 登记（ex_level 在 add_child 之前调）
func set_layer(ln: String) -> void      # 只排这一层的块；洞窟里 view_r 2、不铺色块
func height(x, z) -> float              # 查表（2~3 微秒）
func ceil_at(x, z) -> float             # 洞顶（地面层返回 1e9；洞窟的岩体返回岩顶）
func solid_h(x, z, below, top_max := 1e9) -> float   # 父类：实心盒子的顶面
func solid_any(x, z, r) -> bool                      # 父类
func solid_ceil(x, z, above) -> float   # 新：头顶最近的盒子底面
func solid_box_at(p) -> bool            # 新：点在不在盒子里
func set_door(id, open) / door_open(id) -> bool / door_ids() -> Array
func update_roofs(p)                    # ex_level 每帧调：p 在楼的占地框里、又低于屋顶 / 楼板 / 盖板底面，就藏那一块
func roofs_hidden() -> int; func building_at(p) -> Rect2; func lod0_count() -> int
func bake_map(ln, px) -> {img, center, span}
var static_boxes: int; var gen_ms: float; var active_layer: String
```

- 实心盒子全图静态登记一次（登记名 `STATIC_KEY`，不跟着细地块撤），门单独登记（`Vector2i(800000 + 序号, 0)`）。沙漠 514 条、研究所 1678 条。
- 屋顶组：研究所 40 块（每栋楼一块屋顶、两栋二层楼各多一块楼板、下沉钥匙房的盖板、K7 的顶板），每块单独一个网格（`visibility_range_end 520`）。
- 不破坏地形，不建垫底水面。

## 6. 主角落脚与挡路（`ex_level._constrain` 渲染帧 + `_physics_process` 物理帧）

- 主角在 `_process` 里移动，关卡 `process_priority = 10`（主角 0 之后、镜头 20 之前）当帧摆正，镜头跟的是摆正后的位置。
- 地上走：同 meadow_level（两格以内的台阶走缓坡、实心盒子的边也走缓坡、高墙沿墙滑、跳起来够得着沿的翻上去）。
- **空中撞墙**（新）：飞着 / 空战时，比脚面高出 1 米以上的实心盒子、高出 2.25 米以上的地形都是墙，挡住、沿墙滑；按身前 0.42 米的点判，一帧位移按 0.3 米一步扫过去（闪现 / 突进不会穿薄墙）；一帧挪了 6 米以上当传送不管。
- **撞顶**（新）：头顶最近的盒子底面 − 2.1、洞顶 − 2.1、飞行上限，取最低，夹住、竖直速度清零。
- **矩形边界**：`player.bound` 设成 1e9（它只能夹正方形），在 `_clamp_bound` 里按这一层的 `bound` 矩形夹。
- **被直接挪到另一层**（Backspace 回出生点、玩法管理器拉人）：下一帧发现主角所在层变了就跟着换层（方块世界换排块、天色一下到位），所以 E 直接改 `player.global_position` 到洞窟里也没问题，只是没有黑场。
- 镜头：`floor_fn` = 地形；`occl_fn` = 地形 + 底面低于主角头顶（y + 2.2）的实心盒子——自己那栋楼的屋顶 / 楼板底面都在头顶以上，不挡镜头。洞窟里镜头之后再夹一次（`_Late` 子节点，priority 30），不钻到洞顶上面。

## 7. 小地图 / 大地图（`minimap.gd`）

- 固定底图：关卡载入时每层烘一张整图（桌面 3 米一像素、手机 / 网页 4 米；沙漠地面 341² / 256²，研究所地面 309² / 232²），楼的占地压成深色 + 墨线、钥匙房朱红；按主角在哪一层换图；平移 / 旋转照旧在着色器里。
- 小地图上撤离点直接画关卡点表的（随时开放、位置公开）；下面写「撤离点 N m」。点一下 = 开大地图；长按照旧切近景 / 远景。
- mgr 的老字段（`_pickups / _mobs / _puppets / _bosses / _rivals / _allies / pings / _extracts / net_on / ex_col`）有就画、没有就跳过；**老大世界行为不变**。E 只要给 mgr 上 `player / cam / level` 三个字段就能用。
- 大地图 `BigMap`：宣纸面板占满短边、北朝上；撤离点（青圈 + 撤）、钥匙房（朱印 + 号，开着是青框）、Boss（红菱 + 名）、洞口 / 光井（金角）、地名、队友（青点）、自己（白箭头）、图例；有洞窟的图左上角「看洞窟 / 看地表」；点面板外或「合上」关掉。不暂停。

## 8. 自检

命令（在 `D:\GodotProjects\修仙游戏` 下）：

```
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/W_desert2 --resolution 1280x720 -- --level-shot=desert
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/W_lab2 --resolution 1280x720 -- --level-shot=lab
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/W_desert_gl3 --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=desert --touch --sliced
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/W_lab_gl3 --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=lab --touch --sliced
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/W_raidshot --resolution 1280x720 -- --raid-shot
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s res://_tasks/extraction_refactor/w_maps/gw_test.gd
python -I _tasks/look_20261123/zfight.py _shots/lvshot/geo_lab_main.bin --box -110,-60,120,90
```

注意：`--rendering-method gl_compatibility` 要放在 `--` **前面**（是引擎参数），放在后面是没切渲染器的（我第一轮就放错了，那两份日志 `W_*_gl*_out.txt` 里 gl2 / gl 的是 Forward+ 手机档的数）。

### 8.1 走位 / 规则自检（两档渲染器都 0 项失败）

| 项 | 沙漠 | 研究所 |
|---|---|---|
| 走上金字塔石阶 | 7 秒到 y 36.8（塔顶 38） | — |
| 退台（3 米一级）走不上去 | y 留在 20 | — |
| 进洞口 → 洞窟 / 光井 → 地面 | U1 两头都通 | u3 梯井两头都通 |
| 洞窟里起飞撞顶 | 最高 33.9（洞顶 36） | 地下室最高 25.9（洞顶 28） |
| 门关着撞门 | 停在门外 0.8 米 | — |
| 楼里朝墙走 / 飞 | — | 停在墙里侧 0.42 米（x −28.78 / z −18.78，墙面 −29.2 / −19.2） |
| 二层楼板底下起飞撞顶 | — | 最高 52.90（楼板底 55 − 2.1） |
| 楼梯上二层 | — | 4 秒到 55.5 |
| 进楼 / 进钥匙房藏屋顶 | — | 天工楼 2 块、K1 盖板 1 块 |
| 边界 | 冲进沙暴 9 秒停在 z ≈ 392（硬边界 456），掉血 12~15；飞着冲也推回 | 地上走停在墙前 395.6；飞过墙头被光幕弹回（x ≤ 397） |
| 夜景 | `is_night` 拨钟后为真 | 同 |

### 8.2 性能（每张截图那一秒的最后一帧；预算：绘制 ≤ 220、图元 ≤ 220k、细地块 ≤ 60k 顶点）

网页档 = 兼容渲染器 + `--touch`（手机画质档）+ `--sliced`（单线程分帧，和网页一样），日志 `W_desert_gl3_out.txt` / `W_lab_gl3_out.txt`：

| 截图 | 沙漠 绘制 / 图元 | 研究所 绘制 / 图元 |
|---|---|---|
| 出生点 | 122 / 107k | 177 / 150k |
| 全图俯瞰 | 160 / 161k | 179 / 114k |
| 金字塔 / 天工楼门前 | 137 / 171k | 161 / 135k |
| 塔顶 / 楼里一层 | 124 / 152k | 154 / 135k |
| — / 二层 | — | 154 / 132k |
| 钥匙房 | 85 / 79k（洞里 k11） | 171 / 176k（K1 坑里） |
| 洞窟 / 地下室 | 71 / 37k | 69 / 35k |
| 沙虫竞技场 | 69 / 43k | — |
| 沙暴 / 光幕边 | 98 / 121k | 102 / 93k |
| 夜景 | 130 / 136k | 166 / 120k |
| 大地图开着 | 184 / 137k | 277 / 122k（超：2D 叠加） |

细地块最大 17k 顶点（预算 60k）；帧率都是 60（桌面机 GTX 1050 Ti 上的兼容渲染器，真手机没测）。

桌面档（Forward+、view_r 6）：沙漠绘制 43~144、图元 33k~291k（金字塔 / 夜景俯看全图 288k / 274k）；研究所绘制 44~196、图元 34k~295k；细地块最大 17k 顶点。网页预算是按网页档定的，桌面档的图元高过 220k 的几张是全图远景（老大世界桌面档是 346k~357k）。

大地图开着时 2D 多 ~100 次绘制（3D 照常在后面画），研究所网页档 264。

载入：烘表 + 摆件 沙漠 0.43~0.55 秒、研究所 0.22~0.34 秒（桌面）；`[ex] 载入` 进图到脚下地块好 0.6~0.9 秒。细地块生成一块 38~57 毫秒（桌面工作线程）。

### 8.3 z-fighting

`zfight.py` 查研究所天工楼院一带（2.3 万三角形，`--box -110,-60,120,90`）：改之前「完全共面且两边颜色不同」86 m²（门柱和墙端共面、钥匙房门框、楼顶 / 地上两层错开 45° 的齿轮、几只铁桶同高、木箱铁箍只鼓出 4 厘米、勒脚和侧墙、门楣铜梁外沿和门柱外沿），改完 **0 m²**；「贴得太近」剩 0.9 m²，全是同色的坑沿铁栏（栏杆和横杆，同色可以共面）。沙漠金字塔一带 2 万三角形：只有仙人掌臂 0.1 m²（已改）。

### 8.4 老大世界回归

`-- --raid-shot` 跑完：26 张截图、`[raid] 回到大厅=true`、无脚本错误（`_tasks/extraction_refactor/logs/W_raidshot_out.txt`）。

## 9. 截图（只看 preview 的 jpg）

`_shots/preview/` 下：

- 沙漠：`lvshot_desert_spawn.jpg` `_overview` `_pyramid` `_pyramid_top` `_cavern` `_keyroom` `_worm_arena` `_storm` `_night` `_bigmap`（`.jpg`，桌面档；兼容渲染器的同名加 `_gl`）
- 研究所：`lvshot_lab_spawn.jpg` `_overview` `_hall` `_inside` `_upstairs` `_keyroom` `_cavern` `_barrier` `_night` `_bigmap`（同上）
- 网格导出（给 zfight.py）：`_shots/lvshot/geo_desert_main.bin`、`geo_lab_main.bin`

## 10. 已知问题 / 没做的

1. 沙暴没扣血走 E：没有 `raid.env_damage` 时直接扣 `player.melee.hp`（最低 1 点），E 接上自己的受伤流程后这个兜底就不走了。
2. 门关上时有人正站在门洞里：不推人，人会被当成「已经在墙里」放出去（`_clip` 对起点在墙里的不卡）。E 关门前最好查一下门洞里有没有人。
3. 下沉钥匙房的坑比 DarkArea 浅（6~12 米），房间比 DarkArea 的区域盒小（第 2.4 节）。
4. 洞窟里只有烘焙的光池（火把 / 晶簇 / 光井），没有实时灯；洞里没有太阳影子。
5. 沙漠烘表在网页上估计要 1.5~2 秒（桌面 0.5 秒 × 网页大约 3 倍），都在进图黑屏里；需要的话可以把沙丘噪声换成 `FastNoiseLite.get_image` 原生取样。
6. 研究所 24 栋普通楼的样子只有五种样式，室内摆设简单（沿墙货架 / 箱子 / 工作台）；楼顶上能站人但没有上屋顶的楼梯（SPEC「楼梯上屋顶」只做了两座二层楼的楼梯）。
7. 大地图开着时绘制调用超预算（2D 叠在 3D 上）；要压可以在大地图开着时把 3D 视口降帧或隐藏世界。
8. 怪的高度夹钳只管洞窟、只管 `raid._mobs`；地面上的楼里怪会不会钻上屋顶由 E 的 `block_fn` + `floor_fn` 决定（建议 floor_fn 用 `level.ground`，即只认地形）。
9. 研究所 u1 / u2 / u6 只做了图标（map_def 里没有），没有传送。

## 11. 给 extraction-manager（E）的话

- 建法：`ex_level._ready` 末尾（世界、地图、环境都好了之后）`raid = load(extract_manager.gd).new()`，设 `level / player / cam / net / map_id / font / mobile`，`add_child`。所以 manager 的 `_ready` 里可以直接问 `level.points(...)`、`level.world`。
- 点位全从 `level.points(kind)` 读（第 4 节）；坐标已经是本作坐标、y 已贴地。
- 怪：`floor_fn = level.ground`（只认地形）或 `func(x, z): return level.floor_at(x, z, 怪的 y)`；`block_fn = level.blocked`（研究所必须接）；洞窟里的怪用 `level.y_cap(p)` 夹高度（关卡也会夹 `raid._mobs`）。
- 夜里尸潮 / 带天工师刷怪：`level.find_spawn_near(玩家位置, 20, 40, rng)`；尸潮参数 `points("horde")`。
- 天工师：`points("doctor")[0].pos`（天工楼二层平台）；刷新窗口用 `level.day_sec()`（180~300），入夜用 `level.is_night()`。
- 钥匙房：`points("key_room")` 给门 / 房间 AABB / 开门站位 `open_at` / 房里箱子 id；开关门 `level.set_door(id, open)`（联机同步由你发）；「房里有没有人」用 `room.has_point(p)`。
- 撤离点外观（光柱 + 地面阵）由你建，位置 `points("extract")[i].pos`（台面中心）、范围 `size`。
- Boss：`points("boss")` 的 `arena` 是 AABB（出圈判定）；`altar` 是召唤台位置（沙虫 / 双卫）；沙虫的四角牢笼位置在 `cages`。
- 小地图：`minimap.gd` 的 `mgr` 给你的 manager 就行（要有 `player / cam / level`）；固定底图、撤离点、点开大地图都是自动的。大地图想加东西（遗物箱、ping）可以在 `ex_level.map_marks` 里加，或者告诉我。
- 边界：沙暴掉血请实现 `env_damage(points, kind)`；提示走 `hud.toast(text, color)`。
- 进出洞窟是本机自己传（黑场 0.4 秒），`level.layer_changed` 信号可以用来切 HUD / 音乐。联机别人的木偶照收到的坐标摆，不受影响。

## 12. 给主控的话

- 预热：新图用到的新材质只有两种普通透明材质——沙漠「沙暴幕」（StandardMaterial3D：unshaded + alpha + 不写深度 + 雾）、研究所「禁制光幕」（同上，加法混合），加上和木兰草原同款的飘浮物材质。方块世界着色器和老大世界同一个。需要的话进 `warmup.gd` 的 "ex" 那一档。
- 没有加新的命令行参数进 `PLAY_ARGS`（`--level-shot=` 是自检参数）。
- 字库：`font_check.py` 核对，地图 / 大地图 / 提示里的字都已经在随包字体或补字字体里（见第 13 节）。

## 13. 字库

`python -I _tasks/ui_kit/font_check.py`：需要补的 239 个字里补字字体已经有 238 个，唯一缺的 U+2717「✗」在 `shenshi_selftest.gd`（不是我的）。地图名、Boss 名、地名、大地图上的按钮和图例（合上 / 看洞窟 / 看地表 / 撤 / 青圈 撤离点 …）、边界提示（风沙太烈，寸步难行 / 禁制光幕：此路不通 / 跌入深谷，被禁制送回园中）、小地图的「撤离点 N m / 此层无撤离点」都不缺字，所以这轮没有重做补字字体、没跑 `--import`。网页档截图（`*_gl.jpg`）里大地图的字都正常。

## 14. 下一步（本轮没做）

- 楼顶的上楼梯、更多楼内布置；研究所 u1 / u2 / u6 的通道。
- 洞窟的局部实时灯（只在主角附近开两三盏）。
- 沙丘噪声换原生取样，压网页载入时间。
- 大地图上的「已探明」（现在钥匙房 / 撤离点全公开，照 DarkArea 地图）。
