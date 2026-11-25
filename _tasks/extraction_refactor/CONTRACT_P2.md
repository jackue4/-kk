# 第二批契约：extract_manager ↔ ex_hud（E 和 U 同时开工，按这份对齐；有出入以这份为准，改动写进各自报告）

## 0. 谁建谁
- `ex_level._ready` 末尾建 manager（W 已写好：`raid = load("res://scripts/ex/extract_manager.gd").new()`，设 `level / player / cam / net / map_id / font / mobile` 后 `add_child`）。
- manager `_ready` 里建 HUD：`hud = load("res://scripts/ex/ex_hud.gd").new()`；先设 `hud.mgr = self; hud.font = font; hud.mobile = mobile`，再 `add_child(hud)`（ex_hud extends CanvasLayer，layer 与 raid_hud 相同）。
- main.gd 已经在读 `level.raid.hud.bag_open()`（触屏让位）——**ex_hud 必须有 `bag_open() -> bool`**。
- manager 退出（`_exit_tree`）时 HUD 跟着释放；HUD 里所有对 `mgr` 的访问先 `is_instance_valid(mgr)`。

## 1. HUD 每帧从 manager 拉的字段（manager 必须都有，类型照写）
| 字段 | 类型 | 含义 |
|---|---|---|
| `time_left` | float | 本局剩余秒（900 起倒数；≤0 后不再变） |
| `bag` | Array | 局内背包，ExData 物品字典（30 格） |
| `equip` | Dictionary | `ExData.empty_equip()` 形状：`{weapon:{}, armor:[{}×4], chip:[{}×3]}` |
| `carry_value()` | func → int | `ExData.extract_value(bag)`（右上信息牌「带出价值」） |
| `channel` | Dictionary | 读条：`{}` 没有；否则 `{label:String, t:float 已读, total:float}` |
| `cards` | Array | 身边可交互的东西，按距离排好：`[{key:String, kind:String, title:String, item:Dictionary, hint:String}]`；kind ∈ `item`（地上单件，item 有值）/ `box` / `door` / `chest`（遗物箱 / 储物袋）/ `doctor` / `revive`（救队友）；最多给 8 个 |
| `downed` | bool | 本机重伤中 |
| `downed_left` | float | 重伤剩余秒（20 → 0） |
| `can_self_revive` | bool | 背包里有强心丹 |
| `kills` | int | 本局击杀（怪 + 真人） |
| `pk_kills` | int | 本局击杀真人数 |
| `doctor_state` | String | `""` 没有 / `"follow"` 跟着我 / `"far"` 10~15 米警告 / `"lost"` 刚丢了 |
| `result` | Dictionary | 没结算 `{}`；结算后见第 3 节（HUD 看到非空就弹结算页） |

## 2. HUD 调 manager 的方法（manager 必须实现；参数非法就忽略）
- `ui_card(key: String)`：点了拾取卡 / T 键拿最上面那张（item → 拾取；box / door / chest / doctor / revive → 开始对应读条或动作）
- `ui_use(i: int)`：用背包第 i 格（药 / 强心丹 / 符）
- `ui_wear(i: int)`：穿背包第 i 格的装备（换下的进背包；背包满就不换，toast 提示）
- `ui_unequip(slot: String, idx: int)`：`"weapon"|"armor"|"chip"` 卸到背包
- `ui_drop(i: int, n: int = -1)`：丢到脚下（变成地上单件，别人能捡；进图前 5 秒不让丢）
- `ui_self_revive()` / `ui_suicide()`：重伤界面两个按钮
- `ui_result_done()`：结算页「回主城」（或 HUD 自己 4.5 秒后调一次；manager 只认第一次）

## 3. `result` 字典（manager 在 end_raid 之后填）
```
{ok: bool, cause: "extract"|"dead"|"timeout"|"room_lost"|"room_collapsed", map_id, alive_sec: float,
 kills: int, pk_kills: int, value: int 带出价值, lingshi_delta: int, xianyu_delta: int,
 new_items: Array 带出的物品（撤离成功时 = 背包），lost: Array 丢掉的物品（死亡时 = 掉落堆 + 法宝），
 rank_up: String 晋升到的段位名（没有为 ""）, doctor: bool 营救成功}
```

## 4. HUD 推送（manager 调 HUD）
- `hud.toast(text: String, col: Color = Color(0,0,0,0))`：屏中偏上一行字，2 秒淡出；col 透明 = 墨色
- `hud.close_bag()`：重伤 / 结算时 manager 调
- `hud.flash_hit()` 可选（受击边缘红晕，**不许全屏闪**，见记忆 no-flashing-screen-filters）
- 开局题名走 main 现有的 `realm_banner`（manager 调 `main.call("realm_banner", 图名, "限时 15 分钟")` 或照 raid_manager 的写法），HUD 不管。

## 5. 输入（HUD 管）
- 桌面：`T` 拿最上面那张卡；`Tab` 或 `B` 开关背包；背包开着时鼠标可见（照 raid_hud 的做法）。
- 手机：右侧拾取卡可点；**一个**背包按钮（小、靠右上信息牌下面）；重伤时两个按钮（自救 / 自尽）；不要满屏按钮（记忆 mobile-first-block-style）。
- 背包开着时 `bag_open()` 为真，主角不吃移动 / 攻击输入（main 的 touch.blocked 已接；桌面键鼠由 HUD 吞掉 `_unhandled_input` 或 manager 设 `player.input_locked`，照 raid_hud 现有写法）。

## 6. 样式
纸面仙侠：一律走 `ui_style.gd` 的纸片样式（宣纸面 + 细墨线 + 一点朱砂），格子 / 卡片用 `ExItemView.tile / card`，物品说明 `ExItemView.detail_text`，品质色 `ExData.q_ink`（纸面）/ `q_color`（场景）。新写的汉字最后要跑 `python -I _tasks/ui_kit/font_check.py --patch` 再 `--import`（谁最后改字谁跑，跑前取 `_tasks/extraction_refactor/import.lock`）。
