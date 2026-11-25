# F_maps 修复报告：地图 / 小地图 / 大地图这一组复查问题

代号 F_maps，2026-11-24。只改了自己名下的文件：`scripts/ex/ex_level.gd`、`scripts/ex/map_def.gd`、`scripts/ex/ex_level_shot.gd`、`scripts/minimap.gd`（`grid_world.gd`、`block_world.gd` 没动）。
备份（动手前）：`_tasks/extraction_refactor/backup/ex_level.gd.fix.txt`、`map_def.gd.fix.txt`、`ex_level_shot.gd.fix.txt`、`minimap.gd.fix.txt`。
没提交、没推送；用户在玩，全程只跑了 `--headless`，没开窗口、没跑双开联机。

## 1. 结果一览

| id | 结果 | 改了什么（文件：函数） | 怎么验的 |
|---|---|---|---|
| uxperf-1 大地图盖住结算页 / 重伤纸条（桌面上还会把鼠标抓回去） | **已修** | `ex_level.gd`：新 `_map_blocked()`（主角重伤 / 陨落、manager 的 `downed` / `result` 非空 / `hud.bag_open()`）；`open_big_map()` 遇到这几种直接不开；`_process` → 新 `_tick_big_map()` 大地图开着时每帧查一次，进了这几种当帧关掉；`close_big_map(recapture := true)` 这几种状态下不抓鼠标；`_exit_tree` 改调 `close_big_map(false)`（退图不再抓鼠标） | 无头 `--level-shot=lab/desert` 新增 `bigmap_downed`：开着大地图 `player.set_downed(true)` → 3 帧内合上、重伤时再开被拒、起身后 3D 还原，两张图都 PASS |
| uxperf-2 手机上点大地图会按到底下的摇杆 / 转镜头 / 技能键 | **已修**（本文件内的做法 + 请 main.gd 收个尾，见第 3 节） | `ex_level.gd`：新 `_block_touch()`，`open_big_map()` 和 `_tick_big_map()` 里把 `main.touch.blocked` 设成 true（关卡 process_priority 10，在 main 每帧重写它之后）。触屏层见到 blocked 就松开所有按着的、不再接管触摸；大地图照样收得到系统模拟的鼠标点击（和储物袋开着时一样），点地图外面合上时也不会出招 | 代码对照：`touch_controls._input` 开头 `if blocked: _release_all(); return`，事件不吃掉，GUI 照常收；无头没有触屏，真机 / `--touch` 窗口跑留给回归 |
| combat-8 掉帧时突进穿过研究所楼墙 | **已修**（两个原因都修了） | `ex_level.gd`：① 新 `_is_warp(mv, dt)` 换掉「一帧 6 米以上就当传送」：6 米以上还要看主角自己的速度，位移方向和「速度 × 帧长」对得上、长度不超过它 1.35 倍 + 1.5 米的，算招式 / 移动，照样扫墙；对不上的（速度清零的瞬身换位、回出生点、管理器拉人、洞口传送）才是传送。速度取挪之前和挪之后两个（新的 `_early` 节点 priority -100 在主角之前记 `_v_pre`），因为突进最后一帧招式会清零速度、第一帧挪之前还是零。`_constrain()` 改成 `_constrain(dt)`。② **复查里没写到的第二个原因**：`_clip` 撞墙后的「沿墙滑」只看滑到的终点在不在墙里——正面撞上薄墙时「只留 z 方向」的终点就在墙那头、是空的，整段位移原样放行。拆出 `_sweep()`，沿墙滑的两段也按 0.3 米一步扫，取滑得远的那段。平常走 / 飞一帧挪不到墙厚，行为不变 | 新增 `lunge_wall`：天工楼里离北墙 6 米，一帧 0.08 秒往北挪 14 米、穿过北墙。突进（速度对得上）停在 z −18.77（墙里侧 −19.2），传送（速度零）照样到 −27.2：PASS。第一版只修了 ①，测下来还是穿墙，才查到 ②（`_tasks/extraction_refactor/f_maps/wall_probe.gd` 量了这段墙：z −19.5 ~ −20.0，0.8 米厚）。原有的走 / 飞撞墙、台阶、楼梯、门、边界各项都还 PASS |
| gap-desert-night 沙漠夜里不加刷怪 | **已修** | `map_def.gd`：`_desert()` 的 `m["horde"]` 从 `{}` 改成和研究所同样形状的 `{interval 90, r_min 20, r_max 40, n_min 2, n_max 3, kinds [scorpion, wolf_sand], cap 10}`。管理器（F_mgr 已经改成不分图）直接照点表刷，提示字按种类取名（「夜色里毒尾蝎成群涌来」）。人在洞窟里也照刷（按人所在那一层找落点；DarkArea 的地下也算战区） | 新增 `desert_horde`：沙漠拨到夜里、把 `_horde_t` 拨到马上 → `[ex] 夜里尸潮（desert）：3 只 scorpion,wolf_sand` → PASS（3 只：scorpion ×2 + wolf_sand ×1），测完把这几只清掉 |
| I_int §5 小地图在网页上 24~51 次绘制调用 | **已修**（代码层面；网页上实际次数要回归用渲染器量） | `minimap.gd`：新内部类 `Painter`。合批模式下所有图形（圆 / 整圈的弧 / 方块 / 线 / 多边形）的三角形带逐点颜色攒进一个顶点数组，最后一次 `RenderingServer.canvas_item_add_triangle_array` 画完（= 1 次调用；三角形按调用顺序叠，半透明照旧）。圆和整圈的弧用缓存的单位圆 / 圆环模板乘一个 `Transform2D` 生成（逐点的 GDScript 很少），段数跟原来的 `draw_arc` 点数一样。字分两遍画在最上面：先全部描边、再全部填字，同描边同字号的挨着画（同一张字形贴图连成一批）。新图（固定底图）的小地图用合批；**老大世界用 direct 模式：每个调用原样转给 `draw_*`，参数和顺序和以前一条不差**（和 `backup/minimap.gd.txt` 比过：W 加的部分以外只是 `draw_x(` → `pt.x(`） | `_tasks/extraction_refactor/f_maps/painter_probe.gd`（无头）：两种模式的每个方法都画了 4 帧、没报错，合批 813 个顶点 = 813 个颜色、能被 3 整除。估算新图小地图：着色器底 1 + 墨圆 1 + 图形 1 + 字 2~3 ≈ 6 次 |
| I_int §6 大地图开着时网页档 264~277 次 | **已修** | `minimap.gd` `BigMap`：标记全走 `Painter`（合批）；新 `cover`：面板外的暗底 0.15 秒内由六成压到不透明（`COVER_T`）；宣纸面板的 StyleBox 只建一次。`ex_level.gd` `_tick_big_map()`：`cover` 到 1 之后 `get_viewport().disable_3d = true`（地图外面是不透明墨色底，3D 画了也看不见），`close_big_map()` 还原成开图前的值 | 新增 `bigmap_3d_off`：开图 0.4 秒后 `disable_3d == true`，两张图都 PASS；关图后 / 重伤自动关后还原（`bigmap_downed` 里一起查了）。估算大地图本身从约 100 次降到 15~18 次，另外省掉整个 3D 画面（网页档 100~170 次） |

另外顺手修的（我的文件里，跟复查项相邻）：
- `ex_level.gd` `mates()`：`a is Node3D and is_instance_valid(a)` 改成先 `is_instance_valid` 再 `is`（AI 道友死后还留在 `_allies` 里时，`is` 碰到已释放的对象会报错）。远程玩家那行同样处理。
- `ex_level_shot.gd` `shot()`：`--headless` 下不截图（`frame_post_draw` 不会来，原来整条探针卡死在第一张图），走位 / 规则自检照跑，绘制数打印出来是 0。这样 `--level-shot` 可以无头跑。

## 2. 验证

命令（都在 `D:\GodotProjects\修仙游戏` 下，`--headless`）：

```
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --quit                       # 整个工程载入：无报错
... --headless --path . --check-only --script res://scripts/minimap.gd（以及 ex_level / map_def / ex_level_shot） # 无报错
... --headless --path . -- --level-shot=lab      → logs/F_maps_lab.txt     15 项 PASS，失败 0，回到主城
... --headless --path . -- --level-shot=desert   → logs/F_maps_desert.txt  12 项 PASS，失败 0，回到主城
... --headless --path . -s res://_tasks/extraction_refactor/f_maps/painter_probe.gd   # Painter 两种模式
... --headless --path . -s res://_tasks/extraction_refactor/f_maps/wall_probe.gd      # 天工楼北墙一线的实心盒子
```

新加的自检项：`lunge_wall`（研究所）、`desert_horde`（沙漠）、`bigmap_3d_off`、`bigmap_downed`（两张图）。原有项都还 PASS：楼里走 / 飞撞墙、撞顶、楼梯、屋顶藏起来、洞口上下、洞顶、门挡路、退台、金字塔石阶、沙暴推回、光幕弹回、夜景。

**没法在无头里做、留给回归（要开窗口 / 渲染器）：**
1. 网页档绘制调用实测：`python _tasks/trailer/run_hidden.py . <日志> --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=desert --touch --sliced`（研究所同理）。每张图的 `[lvshot] <名> ... draw N` 就是那一帧的总数；`bigmap` 那张应该比 W 报的 184 / 277 低很多，其余各张里小地图那一份应该从 24~51 降到 6 左右。
2. 看 `_shots/preview/lvshot_*_bigmap*.jpg`：面板外现在是不透明的墨色底（见第 4 节第 1 条）；标记、字和以前一样。
3. 老大世界 `-- --raid-shot`：小地图应该和以前一模一样（direct 模式）；主城 `--hub-shot`、擂台 `--hub-shot --arena-duel` 我没碰到。
4. 手机 / `--touch`：大地图开着时点地图右下角（英雄 Q 键的位置）不出招，点地图外面合上不出招；摇杆 / 按钮在大地图开着时整体藏起来（同储物袋）。
5. 桌面：开着大地图重伤 → 地图自己合上、鼠标是放出来的，能点「自救」。

## 3. 交叉文件请求（不归我改的）

1. **`scripts/main.gd` `_level_bag_open()`**（建议做）：最后加一条
   `if level.has_method("big_map_open") and bool(level.call("big_map_open")): return true`
   这样 `touch.blocked` 只有 main 一个人写。我在 `ex_level._block_touch()` 里补写 true 是为了现在就生效；main 加上之后它多余但不冲突，可以留着。**不要**把大地图并进 `ex_hud.bag_open()`：那样 `ex_hud._input` 会吞掉 M，M 就合不上地图了（复查原文也这么说）。
2. `scripts/ex/extract_manager.gd`（可选，不做也行）：`player_downed` / `_extract_done` / `_die` 里不用再关大地图，关卡每帧自己查、当帧就关。想更早一帧的话可以加 `if level != null and level.has_method("close_big_map"): level.close_big_map()`。
3. `scripts/ex/ex_hud.gd` `_sync_mouse()`（可选）：现在大地图不会再在重伤 / 结算 / 储物袋时把鼠标抓回去，这条路已经堵上了；复查建议的「想放出来时每帧自愈」可以当保险加：`if want and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`（只往放出来的方向修，别每帧抓）。
4. `scripts/air_melee.gd` `_legal()` / `safe_spot()`（建议，跟 combat-8 相邻、复查没单列）：瞬身换位 / 瞬步的落点只查物理碰撞体，新图的墙是方块世界的实心盒子（没有物理体），所以落点可能在楼墙里或墙那头。这类位移速度是零，关卡照「传送」放行，不扫墙。建议 `_legal` 鸭子类型地再问一下关卡：`var lv = player.get_parent().get("level")`，有 `solid_at` / `blocked` 就加上 `lv.solid_at(p + Vector3.UP)` 为真或 `lv.blocked(pivot 脚下, p)` 为真时返回 false。
5. `ex_hud.gd` / `hud.gd`（可选，省绘制调用）：大地图开着时它们还在不透明底下面画（网页档几十次）。想再省可以在 `level.big_map_open()` 时把各自的 CanvasLayer 藏起来、关图再显示。

## 4. 行为上的变化（请主控 / 用户知道）

1. **大地图的底变成不透明了**：原来面板外是六成透明的暗底、能看见两侧的 3D 画面；现在 0.15 秒内压到不透明的墨色，然后 3D 渲染关掉（I_int §6 要的「看不见就别画」）。照样不暂停，挨打照样掉血。要恢复「两侧看得见」，把 `ex_level._tick_big_map()` 里关 3D 的那段去掉、`BigMap._draw` 的暗底颜色改回 `Color(0.02, 0.02, 0.03, 0.6)` 就行，那样只剩合批省下的那部分。
2. 关 3D 期间 GPU 粒子不会推进（引擎只模拟看得见的），关图后接着播；CPU 粒子、动画、玩法都照常。
3. 大地图上的字现在统一画在所有图形上面（原来每个标记的字跟着自己的图形画，后画的图形会压住先画的字）；小地图（新图）上「北」字、撤离点距离同理。看上去只是字更不容易被挡。老大世界小地图不受影响。
4. `_clip` 沿墙滑：两种滑法都扫一遍、取滑得远的那种（原来是 x 方向能滑就滑 x）。贴着墙斜着走时更顺着主方向，平常感觉不出来。
5. 沙漠夜里每 90 秒在人身边加刷 2~3 只毒尾蝎 / 沙漠狼（同时最多 10 只夜怪），掉落照普通小怪。SPEC 4.9 原写「沙漠只有光照变化」，这里按复查（照 DarkArea）补上了；人在洞窟里也刷。

## 5. 新字

没有新的界面文字（新加的只有自检打印和注释），不用补字。

## 6. 文件

- 改：`scripts/ex/ex_level.gd`、`scripts/ex/map_def.gd`、`scripts/ex/ex_level_shot.gd`、`scripts/minimap.gd`（`minimap.gd` 原来混着 CRLF / LF，现在统一成 LF，和 git 里的一致，`core.autocrlf=true` 下没有多余的差异）
- 新（自检小工具）：`_tasks/extraction_refactor/f_maps/painter_probe.gd`、`_tasks/extraction_refactor/f_maps/wall_probe.gd`
- 日志：`_tasks/extraction_refactor/logs/F_maps_lab.txt`、`F_maps_desert.txt`
