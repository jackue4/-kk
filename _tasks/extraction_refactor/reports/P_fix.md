# P_fix 交付报告：第一批留下的五个收尾项

2026-11-24。源码没提交、没部署。改动前的备份都在 `_tasks/extraction_refactor/backup/<文件名>.p2.txt`（`hud.gd.p2.txt`、`arena_net.gd.p2.txt`、`warmup.gd.p2.txt`、`kit_yujian.gd.p2.txt`、`main.gd.p2.txt`，外加排查时临时动过的 `gate_array.gd.p2.txt`、`hero_selftest.gd.p2.txt`）。

## 一、结论（一句话一项）

1. **hud.gd 桌面技能框**：英雄档（`player.hero_id != ""`）显示 E / Z / Q / R 四格，每格读 `player.kit.skill_info(i)`；御剑的 R 只在 `kit.btn_visible(3)`（觉醒中）露出来；苍鸿觉醒后四格换成 瞬狱 / 剑域 / 天斩 / 万剑归宗（名字转朱色）。老模式（`hero_id == ""`）一个像素没变（截图核过）。
2. **arena_net.gd**：`open_room` 里 `players[1]` 加了 `"hero": _my_hero()`，只改这一行。
3. **warmup.gd 的 "ex" 档**：首领弹幕（boss_bullet，按弹幕池同样的 MultiMesh 摆）、边界幕（沙暴幕 / 禁制光幕，直接用关卡里那一份材质）、飘浮物、苍鸿剑气 / 天斩 / 剑域、御剑的大罡剑阵剑门 + 金剑 + 四字题字、这张图的全部怪 / 精英 / 首领模型（沙漠 10 种、研究所 7 种 + 天工师）。两档渲染器的 `[warm] ex` 行都打出来了。另外修了一个隐患：原来 "ex" 档会走老大世界的第 5 步（`raid.region` / `raid._spawn_mob`），E 的管理器一接上就会报错。
4. **御剑大罡剑阵网页档「没打中木桩」**：不是判定的问题，是**自检的量法**——大罡剑阵的时间轴按游戏时间走，自检的窗口按真实时间等 6.2 秒；兼容渲染器第一次画剑门 / 金剑现编着色器时有好几秒的长帧，而 Godot 一帧最多只推进 8 个物理步（≈0.133 秒），演出在墙钟上被拉长，窗口关上时剑还没射出（量到 0），随后自检收尾的 `force_ground()` 把演出 abort 掉。人为注入长帧在桌面档也能 100% 复现。修法：自检改成等演出放完再量（hero_selftest.gd 两行）；游戏这边把剑门 / 金剑 / 题字放进 "ex" 档预热，网页上第一次放不再卡几秒。kit_yujian.gd 最终**没有改动**（和备份逐字节相同）。
5. **老大世界 `-- --raid-shot` 卡死**：在 main.gd 的 `_raid_fps`（原 4771 行）、`_raid_census`（紧挨着、同一个毛病）和 `_run_raid_demo` 的「巢穴 Boss」那一步（原 6635 行）加了 `is_instance_valid` 兜底。正常跑 2 遍都跑完（撤离成功、回到大厅=true、0 个脚本错误）；人为让演示角色在第 70 秒陨落（复现 D 的情形）也跑完了，0 个脚本错误。主城 / 擂台见第六节。

## 二、文件清单

| 文件 | 改了什么 |
|---|---|
| `scripts/hud.gd` | 新增 `_sk_key`、`LEGACY_KEYS`、`HERO_KEYS`、`_ink_key()`、`_refresh_hero_skills()`；`_refresh_air` 里按 `hero_ui` 分两路（老路的代码原样，只多一行把键字 / 字色写回老值） |
| `scripts/arena_net.gd` | 第 159 行 `players[1]` 加 `"hero": _my_hero()` |
| `scripts/warmup.gd` | 新常量 `EX_MOBS / RAID_MOB / CREATURE / KIT_CANGHONG / BOSS_BULLET / SPACE_GATE / EX_PER_BATCH`；新函数 `_ex_mob_list()`、`_spawn_ex_mob()`、`_ex_fx()`；`run()` 里 `legacy_mobs` / `hero_fx` / `ex_list` 和「5b 新图」一段 |
| `scripts/main.gd` | 只动了三处兜底：`_raid_fps` 开头和等待之后、`_raid_census` 开头、`_run_raid_demo` 第 4 步之前（都带 `2026-11-24 P_fix` 注释） |
| `scripts/hero_selftest.gd`（H 的，本期没人归属） | 第 4 项的最小修复：`_one_skill` 里御剑 R 截图后 `wait_until(not player.ult.active, 30)`；`settle` 6.2 → 1.2 |
| `scripts/kit_yujian.gd` | 排查时加过临时日志，已全部撤掉，最终和备份相同 |
| `scripts/gate_array.gd`（H 的） | 排查时加过三行临时日志（abort 时打印），已撤掉，最终和备份相同 |

## 三、接口 / 规则（照实现写）

### 3.1 hud.gd

```
var _sk_key: Array[Label]                      # 四格的键字
const LEGACY_KEYS := ["E", "Z", "X", "C"]      # 老模式（只露 E、Z 两格，和原来一样）
const HERO_KEYS := ["E", "Z", "Q", "R"]
func _ink_key(i: int, key: String, name_col: Color)   # 键字 / 名字颜色只在变了的时候改
func _refresh_hero_skills(p: Player, kit: Node, x0: float, y0: float, lc: Color)
```
- 判定：`kit = p.kit if p.hero_id != "" else null`；kit 有效且有 `skill_info` 才走英雄档，否则走老路（老路的分支和原来逐行一样）。
- 每格：`info = kit.skill_info(i)`；第一行 `info.name`（苍鸿觉醒时 kit 已经换成 awake_name），第二行「灵力 N」（N = `CS.mp_shown(realm_idx, info.mp)` 取整，和玩家牌同一口径）；冷却条 = `info.cd_ratio` × 46 像素从上往下盖、颜色 = 境界线色 α0.45；`info.ready == false` 时整格灰（0.82, 0.82, 0.84, 0.7），同老框。
- 御剑 Z：照老框写「下一式」的名字和灵力（`air.next_skill()` → `air.skill_name / skill_cost`，三式轮放）。御剑 Q 开着时（`kit.touch_text(2) == "收"`）第二行写「再按收起」。
- 可见：`not touch and kit.btn_visible(i)`（御剑 R 只在觉醒中；苍鸿四格常驻）。位置：四格 `x0 = 屏宽 − 4×124 − 18`、`y0 = 屏高 − 250`，每格 118×46、间距 124（老模式两格 `x0 = 屏宽 − 2×124 − 18`，不变）。
- 觉醒时有 `awake_name` 或 `awake_only` 的格子名字转朱色（`UiStyle.CINNABAR`），其余墨色。
- 没有新汉字：`python -I _tasks/ui_kit/font_check.py`（只核对）结果里我的文件不缺字（载入条上的「推演新招」、技能框的「再按收起」都在字体里）；仍缺的两个是别人的：「✗」（shenshi_selftest.gd）、「增」（E 的 ex_selftest.gd），所以没跑 `--patch` / `--import`。

### 3.2 warmup.gd（"ex" 档）

`run()` 里：
- `legacy_mobs = tag != "ex" and raid != null and not raid.net_on()` —— 老大世界第 5 步（这一区的怪和掉落）只在非 ex 档走（原条件是 `raid != null and not raid.net_on()`，"ex" 档传进来的 raid 是 extract_manager，没有 `region / _spawn_mob`）。
- `hero_fx = tag == "ex" or player.hero_id != ""`：多一批「推演新招」（`_batch` phases 2）。
- `ex_list = _ex_mob_list(level.map_id)`（只在 ex 档），每 `EX_PER_BATCH = 5` 只一批（phases 2）。
- 进度条总数相应加上这几批。日志 `[warm] ex：… 新图 N ms（怪 K 种）`；主城档多一段 `英雄招式 N`。

```
static func _ex_mob_list(map_id) -> Array            # [[ex_mobs id, 精英?], …]：MOBS 里 map == 这张图、model != "-"，按实际模型去重
static func _spawn_ex_mob(player, holder, id, elite, q)   # raid_mob.new() + ExMobs.setup + floor_fn + 受击闪光层（同老档 _set_overlay）
static func _ex_fx(host, holder, at, right, up, fwd, col, hero_only: bool, gates: bool)
```
`_ex_fx` 摆的东西（都照原处的写法）：

| 东西 | 来源 / 做法 | 什么时候摆 |
|---|---|---|
| 首领弹幕 ×2（圆弹 / 针弹） | `boss_bullet.gdshader` 的 ShaderMaterial + `MultiMesh(TRANSFORM_3D, use_colors, use_custom_data)` + QuadMesh，3 个实例（同 ex_boss.gd `_ready` 的弹幕池；只套一张面片编不出 MultiMesh 那个变体，所以不放进 SWEEP） | ex 档 |
| 边界幕 | 关卡里 `world.boundary/Curtain` 的那一份材质，套在一块同顶点格式（位置 / 法线 / 颜色 / 索引）的小 ArrayMesh 上；拿不到就照 grid_world `_build_boundary` 现做（不受光 + 透明 + 双面 + 顶点色 + 不写深度；沙漠开雾、研究所加法） | ex 档 |
| 飘浮物 | `level.motes.duplicate(0)`（共用网格和材质），发射盒缩到 0.6；拿不到照 `_build_motes` 现做 | ex 档 |
| 苍鸿新月剑气 / 天斩 | `kit_canghong.remote_wave(…, giant=false/true, …)`（只画不判） | ex 档 + 英雄档主城 |
| 苍鸿剑域光环 | TorusMesh + 不受光 / 透明 / 加法 / 双面（同 `_domain_fx`） | ex 档 + 英雄档主城 |
| 大罡剑阵 | `space_gate.open(…)` 一扇门（直接 `_apply(0.6)` 摆成张开到最大）、两柄金剑（剑光样式 4，一柄直飞、一柄带 emerge + hold，参数同 gate_array `_launch`）、`Calligraphy.show_text("大罡剑阵", …, 1.35, 0.35)` | 只在 ex 档且自己是御剑（别人的剑阵本机不画剑门） |
| 怪 | 沙漠：scorpion / crystal_scorpion / wolf_sand / wolf_void / sand_guard / stone_giant / sand_raider / eye_small（幽冥泣）/ sand_lord / void_apostle（10 种）；研究所：zombie / mech_claw / mech_gunner / gel_mutant / mech_hunter / stone_giant / mech_welder（7 种）+ 天工师 `creature_model.place("doctor")` | ex 档（沙渊巨虫是程序拼的体节，不建） |

所有东西都由 `_batch` 定住、画完清掉（新图的怪挂在 holder 下面，不进管理器的 `_mobs`）。新图脚本一律运行时 `load()`（不 preload，免得它们哪天编不过把 warmup / main 一起拖下水）。

### 3.3 main.gd（只这几行）

```
func _raid_fps(tag):    开头 / 等 2 秒之后：level 或 level.raid 已释放 → 打印「[raid] <tag>：这一局已结算，不测帧率」并返回
func _raid_census(tag): 开头同上 → 「[raid] <tag>：这一局已结算，不点名」
_run_raid_demo 第 4 步（巢穴 Boss）之前：rd 已释放 → 打印「[raid] 演示角色陨落、局已结算：后半段（Boss / 修士 / 背包 / 撤离）跳过」，
    等回到大厅（最多 10 秒）→ 打印「[raid] 回到大厅=…」→ quit
```
`_raid_census` 不在派给我的两个行号里，但它和 `_raid_fps` 是同一个毛病（陨落发生在去下一区的路上时会先在这里报错，见第五节），所以一并加了。

## 四、第 4 项的排查过程（证据）

1. 先照 H 的命令在兼容渲染器 + 触屏跑了 3 遍（`logs/P_hero_touch1/2/3`），加了临时的逐帧日志（kit_yujian.tick 里打印 gate_array 的 `_t / _ev / _pool / _tgt`、飞剑个数、木桩血量）：
   - 第 1 遍复现了「花了 50 灵力、打掉 0」：日志显示**量的那一刻演出才走到 t = 0.66 秒**（剑要 2.05 秒才射出），之后在 t = 1.95 被 abort；20 帧里有两帧 dt = 0.133 / 0.142（Godot 的单帧上限：8 个物理步）。
   - 第 2、3 遍没复现（6.51 / 6.59 单位），全程 dt 正常、`Engine.time_scale` = 1。
   - 选中的目标、目标点、目标池、出剑数都正常——判定没有问题。
2. 加了真实时间戳 + 在演出第 10、20 帧人为 `OS.delay_msec(2500)`（模拟现编着色器的长帧），**桌面档**也 100% 复现（`logs/P_hero_hitchA`：觉醒 R 打掉 0.0、`ult.abort at t=1.95`；时间戳显示 2.5 秒的长帧下一帧 dt 只有 0.135~0.144）。abort 来自自检收尾的 `player.force_ground()`。
3. 改自检（等 `player.ult.active` 落下再量）后，同样注入长帧：`logs/P_hero_hitchB` 觉醒 R 打掉 127.3 = 7.07 单位。
4. 为什么只在网页档出现：兼容渲染器第一次画剑门（space_gate：门口 / 旋涡（读屏幕纹理）/ 光锥 / 光环 / 两种 GPU 粒子）和金剑现编着色器，没命中着色器缓存时一帧好几秒；Forward+ 基本不卡。真机网页上就是「放大罡剑阵卡几秒」——所以把这几样放进了 "ex" 档预热（第 3.2 节）。主城开机预热没加：网页上大约要多七八个着色器（按实测一秒上下一个），开机多等七八秒不划算；擂台上第一次放仍可能卡一下，见第七节。
5. 临时日志全部撤掉（kit_yujian.gd、gate_array.gd 都和备份逐字节相同），`--pfix-dbg / --pfix-hitch / --pfix-kill` 这几个开关已不存在。

## 五、自检命令和结果（都在 `D:\GodotProjects\修仙游戏` 下；日志在 `_tasks/extraction_refactor/logs/`）

| 命令 | 结果 |
|---|---|
| `"<godot>" --headless --path . --quit`；`--check-only --script res://scripts/{hud,warmup,arena_net,kit_yujian,hero_selftest,gate_array}.gd` | 无报错 |
| `python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/P_hero_final --resolution 1280x720 -- --hero-test` | **结论 PASS（21 行）**，0 个脚本错误；觉醒 R 大罡剑阵 128.7 = 7.15 单位 |
| `python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/P_hero_final_gl --resolution 1280x720 --rendering-method gl_compatibility -- --hero-test --touch` | **结论 PASS（21 行）**，0 个脚本错误；觉醒 R 大罡剑阵 114.3 = 6.35 单位（打中了） |
| `… P_warm_desert --resolution 1280x720 -- --level-shot=desert --warm` | `[warm] ex：预热 4080 ms（着色器文件 7 个）｜… 新图 2018（怪 10 种）…`；这一遍的 3 个脚本错误是 E 当时还在写的 extract_manager.gd（`ex_doctor.gd` 不存在）编不过，不是我的 |
| `… P_warm_lab --resolution 1280x720 -- --level-shot=lab --warm` | `[warm] ex：预热 3894 ms ｜… 新图 1667（怪 7 种）…`，0 个脚本错误（这时 E 的管理器已经能用：`[ex] 开局：lab …`） |
| `… P_warm_desert_gl --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=desert --touch` | `[warm] ex：预热 1961 ms ｜… 新图 788（怪 10 种）…`，0 个脚本错误 |
| `… P_warm_lab_gl --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=lab --touch` | `[warm] ex：预热 1799 ms ｜… 新图 638（怪 7 种）…`；9 个脚本错误全是 `ex_level.gd:842 _clamp_mobs`（W 的文件：`m is Node3D` 写在 `is_instance_valid(m)` 前面，E 的 `_mobs` 里有已释放的怪时就报），和预热无关（预热摆的怪不进 `_mobs`） |
| 主城档（上面几遍里的 `[warm] hall` 行） | 多了「英雄招式 136~573 ms」一段（苍鸿剑气 / 剑域） |
| `… P_raidshot1 / P_raidshot2 --resolution 1280x720 -- --raid-shot`（1 是改 main 前、2 是改后） | 两遍演示角色都没死，都跑完：`[raid] 结算：撤离成功 …`、`[raid] 回到大厅=true`，0 个脚本错误 |
| 复现 D 的情形：临时在 hud 里加开关让演示角色第 70 秒 `die_now()`（`P_raidshot_kill`、`P_raidshot_kill2`，开关已撤） | 第一遍：`坠魔谷 飞行：这一局已结算，不测帧率` → `演示角色陨落、局已结算：后半段…跳过` → `回到大厅=true`，只剩 1 个 `_raid_census` 的报错 → 给 `_raid_census` 加兜底后第二遍 0 个脚本错误、正常退出 |
| `… P_hub --resolution 1280x720 -- --hub-shot` | 跑完，0 个脚本错误：定妆图 8 张（绘制调用 91、图元 462k）；四道门 [0, 1, 2, 3] 都触发；试剑台进出、木兰草原进关 / 撤回都 true。日志里「修炼场渡劫：起劫=false …（应少 500）」那行是老自检的期望值没跟上 SPEC（修炼场不再渡劫），不是回归 |
| `… P_arena --resolution 1280x720 -- --hub-shot --arena-duel` | 跑完，0 个脚本错误：单机自检完「胜 2 负 4」（同 H 那一遍），中途收场正常 |
| 第 2 项双开（擂台联机，自检端口 +100）：`… P_pvp_a --resolution 640x360 -- --hero-test=pvp_a` 和 `… P_pvp_b … -- --hero-test=pvp_b` | 加入的一方 b 现在看房主：「对手木偶的英雄 **canghong（皮肤 canghong、手里有剑 true）**」（H 那一遍是「英雄 （空）皮肤 aladeng、没剑」）；招架回传 2 次、硬直 2 次；两边 0 个脚本错误 |

## 六、最终回归汇总

- 两档 `--hero-test`：都 PASS（21 行），大罡剑阵两档都打中。
- 两张新图两档 `--level-shot`：`[warm] ex` 四遍都打出来（沙漠 10 种怪、研究所 7 种 + 天工师）。
- `--raid-shot`：正常两遍跑完；陨落路径（人为）跑完、0 个脚本错误。
- `--hub-shot`、`--hub-shot --arena-duel`：跑完、0 个脚本错误。
- 擂台双开：加入方看得到房主的英雄。
- 没有拉起游戏窗口给用户试玩、没部署：本轮是并行实现中的一个收尾任务，按 SPEC 由主控整合后统一拉起 / 部署。

## 七、截图（只看 jpg）

- 英雄档技能框：`_shots/preview/hero_yujian_1.jpg`（御剑：飞剑 / 掌心雷（冷却中）/ 飞剑阵，R 不显示）、`hero_yujian_aw_2.jpg`（御剑觉醒：四格，R「大罡剑阵 灵力 50」朱字，Q「飞剑阵 再按收起」）、`hero_canghong_aw_1.jpg`（苍鸿觉醒：瞬狱 / 剑域（冷却中）/ 天斩 / 万剑归宗，朱字）。
- 老模式技能框没变：`_shots/preview/raid_04_mob_fight.jpg`（E「飞剑点射 长按连发 / 对波」、Z「焚天剑轮 灵力 16」两格，同原来）。
- 新图载入（预热之后）：`_shots/preview/lvshot_desert_*.jpg`、`lvshot_lab_*.jpg`（兼容档加 `_gl`）——W 的探针截的。

## 八、已知问题 / 没做的

1. **ex_level.gd:842 `_clamp_mobs`**（W）：`if m is Node3D and is_instance_valid(m)` 顺序反了，管理器的 `_mobs` 里有已释放的怪时每帧报错（兼容档研究所那一遍 9 条）。改成先 `is_instance_valid(m)` 即可；另外 E 的管理器怪死后最好及时从 `_mobs` 里摘掉。
2. 主城（擂台）开机预热没加剑门：英雄档在擂台里第一次放大罡剑阵，网页上仍可能卡一下。要加的话把 `_ex_fx` 的 `gates` 参数在 hall 档也给 `player.hero_id == "yujian"`，代价是网页开机多等几秒。
3. "ex" 档每个会话只做一次（`_envs` 按 tag 记）：第一次进新图时是苍鸿、之后换成御剑再进图，剑门不会再预热。
4. 剑门 / 金剑预热摆的是张开到最大的一帧；门的张开 / 收拢动画用的是同一套着色器，不会再编；GPU 粒子的处理着色器在定住期间照样会被 RenderingServer 跑一遍。没有在网页真机上量卡顿（只看了 `[warm]` 的分段时间）。
5. 老大世界演示角色偶发陨落（D 那一遍）本身没查原因：本轮正常跑了两遍都没死；`_raid_immortal` 每 0.2 秒把低于 30 的气血补满，一下吃满 70 以上（20 级坠魔谷的怪 / 红名修士）还是会死。现在死了也能收尾退出，只是后半段（Boss / 修士 / 背包 / 撤离）这一遍测不到，日志里会写明「后半段跳过」。
6. hero_selftest.gd 不是我的文件，按派工「本期没人归属的文件可做最小修复」改了两行，已在第二节记下。

## 九、和 SPEC / 派工的出入

- 第 4 项的根因不在 kit_yujian.gd，也不在 sword_manager / air_*：判定没问题，是自检用真实时间量一个按游戏时间走的演出。最小修复放在 hero_selftest.gd，游戏侧的改进放在 warmup.gd（本来就是我的）。
- 第 5 项多加了一处 `_raid_census` 的兜底（同一个毛病，见第三、五节）。
- 第 3 项顺带把 "ex" 档原来会走的老大世界第 5 步关掉了（E 的管理器接上后那一步必报错）。
