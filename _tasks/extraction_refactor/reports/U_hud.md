# U_hud 交付报告：局内界面 ex_hud.gd（CONTRACT_P2 的 HUD 一侧）

日期 2026-11-24。实现者 U（界面）。没有 commit / push。只建了自己的两个文件，另外按契约 §6 重做了补字字体并在导入锁下 `--import`。

## 1. 做了什么

`scripts/ex/ex_hud.gd`（extends CanvasLayer，layer 12，和 raid_hud 一样），完全照 `CONTRACT_P2.md` 写：每帧从 `mgr` 拉字段，界面上的操作一律调 `mgr.ui_*`。字段缺了、类型不对、mgr 被释放，都按空的处理，不报错。

界面内容（宣纸面 + 细墨线 + 一点朱砂，全走 `ui_style.gd`；物品格子 / 卡片 / 说明走 `ExItemView`；大数走 `num_fmt.gd`）：

1. **右上信息牌**：小地图贴右上角，它左边一张小纸条。
   - 第一行：「时限 mm:ss」，后面跟着「击杀 N」。真人击杀不为 0 时写成「击杀 N（修士 M）」。剩余不到 60 秒，时限两个字和数字都变朱砂。
   - 第二行：「带出价值 X」，数值来自 `carry_value()`，用 num_fmt 格式化。
   - 带着天工师时多一行：随行中（石青）/ 跟不上了，走慢些（朱砂）/ 走失了（朱砂）。
   - 手机上，纸条下面右对齐放一颗 76 的小背包圆按钮，纸签上写「n/30」，背包满了字变朱砂。桌面上不放按钮：鼠标平时是抓着的，用 Tab / B 开背包。
2. **小地图**：HUD 自己建，和 raid_hud 一样。要等 mgr 有了 `player / cam / level` 才建，因为 minimap.gd 直接读这三个字段，缺了会报错。如果 manager 自己有 `minimap` 字段，就用它的，并拆掉 HUD 建的那个。
3. **右侧拾取卡片**：
   - 桌面：160×72，离右边缘 230，最多露 4 张。
   - 手机：196×88，在右下那簇战斗按钮的左边，最多露 3 张。
   - 屏幕矮的时候少露几张，底边要让开桌面的空战技能栏、手机的「月」键。多出来的卡片可以上下滑，底下写「共 N 件 · 上下滑动」。
   - `kind == "item"` 的卡片用 `ExItemView.card`。box / door / chest / doctor / revive 用一张纸片卡片：左边一方朱印（箱 / 门 / 遗 / 救 / 扶），右边是 title 和 hint。
   - 点卡片调 `mgr.ui_card(key)`；按 T 拿最上面那张，桌面上最上面那张卡片的右上角写「T」。
   - hint 每帧变的时候就地改字，不重建卡片。
4. **读条**：读的是 `mgr.channel`，位置在中下（屏高 64%），300 宽、石青色，上面一行「label　剩 x.x 秒」。重伤时挪到重伤纸条的正上方。
5. **储物袋面板**：
   - 打开方式：桌面 Tab / B，手机按钮；Esc 或点面板外的暗处关上。
   - 布局：
     - 题头：朱印「储」、「储物袋」、「n / 30 格　带出价值 X」和关闭按钮。
     - 装备栏一排：兵刃 1 格，法衣 4 格（空格写冠 / 衣 / 护腿 / 履），法宝 3 格（tile 自带耐久条）。
     - 背包 10 × 3 共 30 格。
     - 底部：选中物品的 `ExItemView.detail_text`，以及按钮：
       - 背包里的物品：使用（药 / 强心丹 / 符，`ExData.usable`）、穿戴（`ExData.wearable`）、丢弃。
       - 装备栏里的物品：卸下。
   - 按钮调用：`ui_use(i)` / `ui_wear(i)` / `ui_drop(i, -1)` / `ui_unequip(slot, idx)`。
   - 「使用」之后自动关背包，这样读条看得见。
   - 面板 1248×696 界面单位（桌面 1280×720 窗口 = 1600×900 单位，缩放 1.0）；放不下就整块缩小，不放大。
   - 背包开着时：
     - `bag_open()` 为真，main 的触屏层让位。
     - 桌面鼠标放出来，关上时照 raid_hud 的规矩：`cam.capture_mouse` 为真才抓回去。
     - 键盘输入全吞：WASD、J / K、技能键、Shift…，见第 4 节。
6. **重伤**：
   - 四周一圈暗红晕（径向渐变贴图，单独一层 CanvasLayer 9，压在玩家牌和触屏按钮下面），随流血从 0.55 慢慢浓到 0.9，不闪。
   - 中间偏下一张纸条：「重伤倒地」题字、剩余秒数（不到 6 秒变朱砂）、流血条（`downed_left / 20`）、一行说明，再加「自救」「自尽」两个按钮。
   - 「自救」只在 `can_self_revive` 时可点；自救读条中灰掉。两个按钮分别调 `ui_self_revive()` / `ui_suicide()`。
   - 重伤时卡片收起，背包开不了；要是背包开着会被关掉。
7. **结算**：`mgr.result` 非空时弹出，弹一次。
   - 题头大字：撤离成功配朱印「归」，身死道消配墨印「陨」。
   - 依次是：「地图 · 原因」；「存活 mm:ss　击杀 N（修士 M）　带出价值 X」；「灵石 ±X　仙玉 ±Y」（正数石青、负数朱砂）。
   - 营救天工师时多一行（+100万灵石、+20仙玉，从 ExData 取）。段位晋升时多一行朱印「升」加题字。
   - 物品格：成功时显示「带出」（new_items），失败时显示「失去」（lost）。按品质、价值排序，最多 8 格，多的写「…… 另有 N 件」。传奇（q≥4）以上右上角标「珍」，叠了的标「珍×N」；名字颜色就是品质墨色。
   - 「回主城」调 `ui_result_done()`。打开 4.5 秒后 HUD 自己调一次。HUD 这一侧整局最多调一次，之后按钮灰掉，写「正在返回主城…」。
8. **推送**：
   - `toast(text, col)`：屏中偏上（屏高 20%）一行小纸条，2 秒后用 0.5 秒淡出，最多同时 3 条。col 透明时用墨色；颜色浅的（亮度 > 0.5，给场景用的提示色）先压深再写到纸上。
   - `close_bag()`。
   - `flash_hit()`：四周一圈朱砂淡晕，0.06 秒淡入，0.45 秒退掉，最浓 0.42。只在边上，中间 62% 半径内全透明。
9. **契约之外留的**（照 raid_hud，manager 不用也行）：
   - `banner(text, sub, col)`：屏高 30% 的大字横幅，3.2 秒。
   - `hud.boss = 某个 Node3D`：要有 `hp_ratio()` / `display_name`。设了就在左上玩家牌和右上信息牌之间画首领血条，提示条自动让到它下面。

## 2. 文件清单

| 文件 | 新 / 改 | 说明 |
|---|---|---|
| `scripts/ex/ex_hud.gd` | 新 | 局内界面 |
| `scripts/ex/ex_hud_selftest.gd` | 新 | 独立 SceneTree 自检（假管理器 + 截图），不用 main 的探针 |
| `assets/fonts/SourceHanSansCN-Normal.patch.ttf` | 重新生成 | `font_check.py --patch` 生成，然后在导入锁下 `--import`。补字字体从 238 字变成 243 字，新增：我的「扶 治 珍」和 E 的「疗 闯」。备份在 `_tasks/extraction_refactor/backup/SourceHanSansCN-Normal.patch.ttf.p2.txt`（二进制）|

工程外的临时冒烟脚本（进真游戏用，不在工程里，跑完可删）：`C:\Users\CHENYA~1\AppData\Local\Temp\claude\31cb5b99151d1ce0\e85b2bf8-fad1-47ba-acd2-af87b9603715\scratchpad\exhud_game.gd`。

没有动 main.gd、extract_manager.gd、raid_hud.gd、hud.gd、touch_controls.gd，也没有动任何老文件。

## 3. 公开接口（照实现）

```
extends CanvasLayer        # layer = 12；没有 class_name：load("res://scripts/ex/ex_hud.gd").new()
# manager 在 add_child 前设：
var mgr: Node              # extract_manager（Node3D 才会建小地图）
var font: Font             # 空 = UiStyle.kai()
var mobile := false        # 手机 / 网页摆法（main._mobile）；var touch := false 同义，两个有一个为真就按手机摆
# 可选：
var boss: Node3D = null    # 首领血条（hp_ratio() / display_name）
var minimap: Control       # HUD 建的小地图（或者 adopt 的 mgr.minimap）
var calls: Array           # 自检用：HUD 调过的 ui_*（[方法名, 参数]）

func bag_open() -> bool              # 储物袋开着，或者结算页开着（见第 7 节偏差 1）
func toggle_bag() -> void            # 开 / 关储物袋（重伤 / 结算 / 关卡大地图开着时开不了）
func close_bag() -> void
func toast(text: String, col := Color(0, 0, 0, 0)) -> void   # _ready 之前调也行（先存着）
func flash_hit() -> void
func banner(text: String, sub := "", col := Color(1.0, 0.86, 0.62)) -> void
```

每帧从 mgr 读这些字段（契约 §1），类型不对就当缺：`time_left`（float）、`bag`（Array）、`equip`（Dictionary）、`carry_value()`（没有这个方法就用 `ExData.extract_value(bag)`）、`channel`、`cards`、`downed`、`downed_left`、`can_self_revive`、`kills`、`pk_kills`、`doctor_state`、`result`。另外还读 `cam.capture_mouse`（关背包时要不要抓回鼠标）、`map_id`（结算页上的地名兜底）、`level.big_map_open()`、`minimap`。小地图另外要 `player / cam / level`。

会调的 mgr 方法（契约 §2，没有这个方法就不调）：
- `ui_card(key)`
- `ui_use(i)`
- `ui_wear(i)`
- `ui_unequip(slot, idx)`
- `ui_drop(i, -1)`
- `ui_self_revive()`
- `ui_suicide()`
- `ui_result_done()`（整局最多一次）

## 4. 输入 / 鼠标

- **`_input`**：
  - Tab、B、或者 `bag` 动作：开关背包。结算时无效。
  - 背包开着时按 Esc：关背包。
  - 背包或结算开着时，所有键盘 / 手柄事件都被吞掉（`set_input_as_handled`），对应的动作当场 `Input.action_release`，这样轮询 `Input.get_vector` 的移动也读不到。
  - 鼠标键事件不吞，留给面板上的按钮和暗处，但会把它对应的动作状态清掉（桌面左键绑着 attack）。
- **刚打开的那一刻**：把所有按着的、非 `ui_*` 的动作发一个 `InputEventAction` 松开事件。这样按住的护体能收到「松开」，`player_melee` 不会卡在格挡里。
- **`_unhandled_input`**：`pickup`（T）拿最上面那张卡片。`pickup` 动作没有就加上，照 raid_hud。
- **鼠标**（只管桌面）：
  - 背包、结算、重伤时放出来（重伤要点「自救 / 自尽」）。
  - 都结束了，并且 `cam.capture_mouse` 为真，才抓回去。
  - HUD 从来不在自己没放出鼠标的情况下去抓。

## 5. 摆法和常量（界面单位；桌面 1280×720 窗口 = 1600×900，手机约 1701×900）

| 常量 | 值 | 说明 |
|---|---|---|
| `LOOT_RIGHT` / `LOOT_RIGHT_TOUCH` | 230 / 470 | 卡片列离右边缘（同 raid_hud；手机在英雄档「刃」-447、「诀」-446 的左边） |
| `LOOT_TOP_K` / `LOOT_TOP_DESK_MIN` / `LOOT_TOP_TOUCH` | 0.34 / 272 / 270 | 卡片列的顶。桌面至少在 hud._tgt 底边 262 以下 |
| `LOOT_BOTTOM_DESK` / `LOOT_BOTTOM_TOUCH` | 258 / 190 | 卡片列底边离屏幕底的最小距离：桌面让开空战技能栏（vs.y−250），手机让开「月」（顶在 −182） |
| `LOOT_SHOW` / `LOOT_SHOW_TOUCH` | 4 / 3 | 最多露几张；桌面最少 2 张，手机最少 1 张 |
| `CARD_DESK` / `CARD_TOUCH` | 160×72 / 196×88 | 卡片尺寸 |
| `BAG_CAP` / `BAG_COLS` / `SLOT` | 30 / 10 / 112×100 | 背包（名字 21 号字） |
| `BTN_H` / `BAG_BTN_TOUCH` | 62 / 76 | 按钮高 / 手机背包按钮 |
| `PANEL_PAD` | 24×18 | 面板离边缘的最小距离 |
| `DOWN_T` / `DOWN_W` / `CH_W` | 20 / 420 / 300 | 流血总时长 / 流血条宽 / 读条宽 |
| `RESULT_AUTO` / `RESULT_SHOW` / `RARE_Q` | 4.5 / 8 / 4 | 结算自动返回 / 最多几格 / 标「珍」的品质 |
| `TOAST_T` / `TOAST_FADE` / `TOAST_MAX` / `TOAST_Y` | 2.0 / 0.5 / 3 / 0.2 | 提示 |
| `LOW_TIME` | 60 | 时限变朱砂 |
| `HIT_T` / `HIT_IN` / `HIT_A` | 0.45 / 0.06 / 0.42 | 受击红晕 |
| `FX_LAYER` | 9 | 晕那一层（hud 10、触屏 20 都在它上面） |

各块的位置：

- **小地图**：(vs.x−14−178, 12)。
- **信息牌**：右边缘在小地图左边 12 处，y = 12。桌面约 167~233 宽 × 95~115 高；手机 + 随包字体约 243~344 × 104~136。
- **手机背包按钮**：信息牌下 8 像素、右对齐。
- **读条**：(vs.x/2 ± 150, 0.64·vs.y)。
- **重伤纸条**：居中，顶在 0.56·vs.y，约 452×191（随包字体下 452×213）。
- **提示**：居中，顶在 0.2·vs.y。

## 6. 自检

独立 SceneTree 脚本（不需要 main 的探针），在 `D:\GodotProjects\修仙游戏` 下跑：

```
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --path . --resolution 1280x720 --script res://scripts/ex/ex_hud_selftest.gd
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --path . --resolution 1280x720 --rendering-method gl_compatibility --script res://scripts/ex/ex_hud_selftest.gd -- --touch
隐藏窗口（我实际跑的）：
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/U_hud_desk --resolution 1280x720 -s res://scripts/ex/ex_hud_selftest.gd
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/U_hud_gl_touch --resolution 1280x720 --rendering-method gl_compatibility -s res://scripts/ex/ex_hud_selftest.gd -- --touch
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/U_hud_phone --resolution 1701x900 -s res://scripts/ex/ex_hud_selftest.gd -- --touch --web-fonts
```

参数：
- `--touch`：按手机摆。
- `--web-fonts`：强制用随包字体。兼容渲染器那一档会自动打开 `UiStyle.force_bundled`。

结果：每项打一行 `[exhud] PASS / FAIL`，最后一行是汇总；有 FAIL 时退出码为 1。

| 档 | 结果 | 日志 |
|---|---|---|
| 桌面 Forward+ 1280×720 | **PASS 59 FAIL 0**，stderr 为空 | `logs/U_hud_desk_out.txt` |
| 兼容渲染器 + 触屏 + 随包字体 1280×720 | **PASS 62 FAIL 0**，stderr 只有引擎对粒子拖尾的两条警告，和我无关 | `logs/U_hud_gl_touch_out.txt` |
| 手机比例 1701×900 + 触屏 + 随包字体 | **PASS 62 FAIL 0** | `logs/U_hud_phone_out.txt` |

测了这些：
- **假管理器**：契约 §1 §2 的字段 / 方法全有。ui_* 调用记日志，并按契约真改背包 / 装备：穿戴换下来的进背包、卸下、丢弃、使用扣数量。
- **基础显示**：
  - 建了小地图；`bag_open()` 存在且为假。
  - 时限显示 14:32，不到 60 秒变朱砂；带出价值用 num_fmt。
  - 5 张拾取卡片；读条。
  - T 键对应 `ui_card(最上面那张)`，点卡片对应 `ui_card(key)`。
  - 天工师那一行；两条提示 2 秒后淡掉。
- **背包**：
  - Tab 打开，鼠标可见，卡片收起。
  - **背包开着按 W 不走、按 J 不出招**。
  - 背包 30 格，装备栏 1 + 4 + 3，面板在画面里。
  - 选中药出「使用 / 丢弃」，说明来自 detail_text。
  - 选中兵刃出「穿戴 / 丢弃」，穿戴调 `ui_wear(i)`，装备栏换成新兵刃。
  - 选中法宝出「卸下」，调 `ui_unequip(chip,0)`；丢弃调 `ui_drop(i,-1)`；使用调 `ui_use(i)` 并关背包。
  - B 开关；手机按钮开、`close_bag()` 关。
- **重伤**：
  - 纸条和暗晕出现；有强心丹时「自救」可点。
  - 卡片收起，背包开不了。
  - 自救调 `ui_self_revive()`；读条在纸条正上方。
  - 没有强心丹时「自救」灰掉；自尽调 `ui_suicide()`。
  - 起身后纸条收起。
- **受击**：红晕淡入，只在四周（a = 0.27），0.6 秒后退掉。
- **结算（成功）**：
  - 页面出现，`bag_open()` 为真，页面在画面里，结算时 Tab 开不了背包。
  - 4.5 秒自动调一次 `ui_result_done`，再点按钮不会重复调。
- **结算（陨落）**：新建一个 HUD。点按钮调一次，4.5 秒后不再自动调。
- **半截管理器**：只有 `time_left`。界面照常跑，背包照开；管理器被释放后界面也不报错。
- **重叠检查**：按 `touch_controls.gd` 的 `BUTTONS` + 英雄档 `HERO_POS` 算圆，加上摇杆、空战目标面板（hud._tgt compact 位置）、桌面空战技能栏（英雄档四格）、左上玩家牌（手机 ×1.15）。信息牌（三行 / 四行）、小地图、卡片列、读条、背包按钮、提示、重伤纸条都不压它们。

**进真游戏冒烟**（工程外的临时脚本，见第 2 节；带 `-- --exhud-game`，所以走测试存档）：

```
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/U_hud_game --resolution 1280x720 -s "<scratchpad>/exhud_game.gd" -- --exhud-game
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/U_hud_game_gl --resolution 1280x720 --rendering-method gl_compatibility -s "<scratchpad>/exhud_game.gd" -- --exhud-game --touch
```

两档结果都一样：
- 进沙海古墟后，E 的 extract_manager 建出了 ex_hud，小地图也建了。
- 时限 894.99；背包 3 格（首登礼）。
- Tab 开背包、再按 Tab 关上都正常。
- 挪到箱子 b39 边上：出现 1 张卡片「物资箱 / 开启 1.5 息」。按 T 后 channel = 搜物资箱，读条显示出来；`[ex] 开箱 b39 → 2 件`。
- 回主城正常。
- stderr 里没有任何一条来自 ex_hud。

编译：`--headless --path . --quit` 无报错；两个文件 `--check-only` 都通过。

## 7. 和 SPEC / CONTRACT 不一样的地方（及原因）

1. **结算页开着时 `bag_open()` 也返回真。** main.gd 只拿它设 `touch.blocked`。结算页很大，触屏战斗按钮会压在「回主城」上，而 touch_controls 先认按钮、后认界面。这样处理后，结算时触屏层让位、不画按钮。E 要是拿 `bag_open()` 做别的判断，要知道这一点。
2. **小地图由 HUD 建**（契约没写，照 raid_hud）。E 的 manager 没有自己建，而且已经给掉落物写了 `tier()` / `is_chest()`、给 `_bosses` 写了 state / pos / node，正好喂给 minimap.gd。如果 E 以后在 manager 上加一个 `minimap` 字段，HUD 会改用它的、拆掉自己的。
3. **桌面不摆背包按钮**，只有手机上有（契约 §5 也是这么写的）。理由：桌面鼠标平时是抓着的，用 Tab / B。
4. **「使用」之后自动关背包**：读条在中下方，背包开着会挡住。穿戴 / 卸下 / 丢弃不关。
5. **天工师那一行写在信息牌里**（第四行），不另外摆一张纸条：手机上单独摆会压到空战目标面板（hud._tgt，y 150 起）。
6. **击杀和时限写在同一行**：网页 / 手机的随包字体行高大，三行竖排就碰到 hud._tgt 了。
7. **重伤时桌面放出鼠标**，好去点「自救 / 自尽」。点到 3D 画面会被 camera_rig 抓回去，这时要按 Esc 才能再点按钮。没有给「自救 / 自尽」做键盘快捷键（正式关卡不加键位提示）。
8. **大地图开着时开不了背包**（关卡大地图在层 30，背包会被它盖住）。
9. 契约之外多了 `banner()` / `boss`（见第 1 节第 9 条）。E 现在没用到。B_mobs 报告建议首领 frenzy / transform 走 `hud.banner`，可以直接调。

## 8. 截图（只看 jpg，都在 `_shots/preview/`）

| 内容 | 桌面 | 网页 + 触屏 | 手机比例 1701×900 |
|---|---|---|---|
| 平时（信息牌 / 卡片 / 读条） | `exhud_hud.jpg` | `exhud_gl_touch_hud.jpg` | `exhud_touch_hud.jpg` |
| 不到 1 分钟 + 天工师 + 提示 + 首领血条 + 救 / 扶卡片 | `exhud_low.jpg` | `exhud_gl_touch_low.jpg` | `exhud_touch_low.jpg` |
| 储物袋 / 选中一件 | `exhud_bag.jpg` / `exhud_bag_sel.jpg` | `exhud_gl_touch_bag.jpg` / `_bag_sel.jpg` | `exhud_touch_bag*.jpg` |
| 重伤 / 自救读条 / 没有强心丹 | `exhud_downed.jpg` / `_downed_channel.jpg` / `_downed_none.jpg` | `exhud_gl_touch_downed*.jpg` | `exhud_touch_downed*.jpg` |
| 受击红晕 | `exhud_hit.jpg` | `exhud_gl_touch_hit.jpg` | `exhud_touch_hit.jpg` |
| 结算 成功 / 已返回 / 陨落 | `exhud_result_ok.jpg` / `_result_ok_done.jpg` / `_result_dead.jpg` | `exhud_gl_touch_result_*.jpg` | `exhud_touch_result_*.jpg` |
| 原分辨率放大（看缺字） | `exhud_*_zoom.jpg` | `exhud_gl_touch_{low_top,low_cards,downed,result_ok,result_dead}_zoom.jpg` | `exhud_touch_*_zoom.jpg` |
| 真游戏（沙海古墟） | `exhud_game_desert_{spawn,bag,box,box_channel,box_open}.jpg` | `exhud_game_gl_touch_desert_*.jpg` | — |

网页档的放大图（随包字体）里，新加的字「救 扶 珍 治」和其余界面字都正常，没有方块。

## 9. 已知问题 / 没做的

- 真手机没测。手机比例只按 1701×900 小样和 1280×720 + `--touch` 验过。
- 提示条（屏中偏上）在空战有锁定目标时会和 hud._tgt 的左半边有一点交叠。提示 2.5 秒就消失，没再往下挪：再往下会压到人物。
- hud.gd 的连击数字（vs.x−330，0.36·vs.y，只在空战连段时出现）在桌面上可能压到卡片列。raid_hud 时就是这样，没有改 hud.gd，它不归我。
- 结算页最多摆 8 格。带出的东西多时只写「另有 N 件」，没有滚动列表。
- 背包里没有「整理」按钮（契约里没有 sort 方法），也没有「丢一个」：丢弃按整堆丢，`ui_drop(i, -1)`。
- 卡片的 hint 字段直接显示 manager 给的文字。E 用的是「开启 1.5 息」这种写法，界面不改写。

## 10. 给主控 / E 的话

- 自检是独立脚本，主控不用在 main 里接探针。
- E 可以设 `hud.boss = 首领节点`（要有 `hp_ratio()` / `display_name`）来显示首领血条，也可以调 `hud.banner(...)`。
- 新出现的字我已经补进字库（含 E 的「疗 闯」）。之后谁再改文字，照契约 §6，在导入锁下跑 `font_check.py --patch` 和 `--import`。现在唯一缺的是 shenshi_selftest.gd 里的 ✗（U+2717），以前就补不上。
