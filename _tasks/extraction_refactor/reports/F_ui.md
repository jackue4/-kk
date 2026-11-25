# F_ui 修复报告：界面 / 大厅 / 存档 / 主控小修（审查结果第二轮）

日期 2026-11-24。修复者 F_ui。没有 commit / push，没有部署，没有开窗口跑游戏（用户正在这台电脑上试玩），所有验证都是 `--headless` 跑的。
改动前的备份：`_tasks/extraction_refactor/backup/<文件名>.fix.txt`（ex_hud / ex_hud_selftest / ex_lobby_ui / ex_lobby_selftest / ex_item_view / ex_profile / hud / player_plate / level_select / main / warmup / ex_data_check）。

**注意：同一时间还有一个「界面专项」代理在改我名下的文件。** 它新建了 `scripts/ex/hero_select_ui.gd`（全屏英雄选择），并在 `hud.gd`（左上头像上的「换」按钮 `_hero_btn` / `_open_heroes`）、`ex_lobby_ui.gd`（「英雄」页签改开全屏界面 `_open_heroes` / `_hero_ui`）、`ex_lobby_selftest.gd`（英雄那几步）里接了线。我没有回退、也没有改它的部分；我的改动都是按段落定点插入的，两边现在共存（diff 核过）。

## 1. 每一项的结果

| id | 结果 | 改了什么（文件：函数） | 怎么验的 |
|---|---|---|---|
| rules-1 Backspace 回出生点 | 已修 | `main.gd:_unhandled_input`：新图里（`_ex_mode()`）正式游玩（非 test_mode）直接忽略 `reset`；自检 / 演示、主城、试剑台、木兰草原照旧 | 读代码；`--level-test=desert` 无头全过 |
| combat-4 木兰草原房间带着主城英雄 | 已修（一半跨文件） | `main.gd:_enter_level`：`_apply_combat_mode("ex"/"legacy")`（连同 `force_ground`）挪到建房 / 入房 / 匹配之前，`net.host` / `net.join` 记的 `_my_hero()`、境界就是这一局的；`join` 失败退回主城时切回 `"hub"`。旧位置的调用删掉 | 读代码（双开归回归代理） |
| net-6 匹配听到别的图的房间就停 | 已修 | `main.gd:_matchmake`：等待循环改成「听到同一张图、还有空位的房间才停」；新 `_room_for_map()` / `_any_room_for_map()`，下面挑房间用同一个判定 | 读代码（局域网双开归回归代理） |
| econ-4 存档写一半被杀 = 静悄悄新号 | 已修 | `ex_profile.gd`：`save()` 先整份写 `<档>.tmp` 再写正式文件，内容没变不写（`_last_txt`）；`_load()` 依次试 正式 → .tmp → .bak，恢复了写 notice；全坏时坏文件改名 `.corrupt` 留着、新号并写 notice；每次读成功另存 `.bak`；新 `_read()` / `_write()`（用 `JSON.new().parse`，坏档不刷错误） | 临时脚本 `scratchpad/F_ui/profile_save_test.gd`（测试档）：新号、读回、正式文件截半 → 从 .tmp 恢复且正式文件补好、正式 + .tmp 坏 → 从 .bak、全坏 → .corrupt + 新号 + 提示、内容不变不写，**8 / 8 PASS**（`logs/F_ui_profile_save.txt`） |
| econ-7 手机双击越过史诗确认 | 已修 | `ex_lobby_ui.gd`：`_arm()` 记进入「等确认」的时刻，`CONFIRM_GUARD_MS = 450` 内的确认点击不算（`_too_soon()`）；新冒出来的「确认卖出」按钮这段时间不接点击、淡一点（`_guard_btn()`，0.45 秒后恢复）。单卖（`_sell_acts`）和一键卖（`_build_trader`）两处。`_act()` 改成返回按钮 | `-- --lobby-test` 无头：新加两条「紧接着再点一下不算确认（防双击）」都过，0.5 秒后确认照常卖出 |
| econ-8 数据检查工具写正式存档 | 已修 | `tools/ex_data_check.gd:_init`：`ExProfile.test_mode()` 为假（没带 `-- --data-check`，或只带 `--keep-profile`）就报错、`quit(1)`，什么都不碰 | 不带参数跑：exit 1、打印「不碰正式存档」；带 `-- --data-check`：照常，坏条目 0 |
| econ-9 离线结算只在开洞府时说 | 已修 | `hud.gd:_ex_rank_banner`：主城画面亮着时（`_hall_clear()`：不在关卡、不暂停、不在切场景、没开选关、黑场褪了、没演出）取 `ExProfile.take_notice()`，排队用 `hub.say` 说（5 秒），洞府界面就不再重复。顺带：段位晋升「仙玉 +N」那句也这样说 | 读代码；`--lobby-test` 段位晋升那步走到了（无头看不到字） |
| uxperf-3 "ex" 预热一个会话只做一次 | 已修 | `warmup.gd:run`：分三层记——`"ex"`（着色器文件 / 特效 / 文字 / 兵刃法术弹，和图无关，一次）、`"ex:<图>:<英雄>"`（这张图的怪 / 首领 / 天工师、边界幕 / 飘浮物 / 首领弹幕 / 剑气 / 剑门、管理器材质、四周环视）、`"ex:hero:<英雄>"`（主角身上藏着的部件）。第二张图 / 换英雄只做后两层。进度条总数跟着算；日志第二次写成 `[warm] ex:lab:canghong：…` | `-- --level-test=lab --warm` 无头：`[warm] ex：预热 850 ms（着色器文件 9 个）… 新图 400（怪 7 种）`（一个进程只能进一张图，第二张图那条路只读代码核过：老 tag 的行为不变） |
| uxperf-5 卡片顺序一变整列重建、丢点击 | 已修 | `ex_hud.gd`：`_tick_cards` 重写成按 key 增量——只加新来的、拿掉没了的、物品签名变了的那一张重做（手指按着就等松手）；远近顺序变了用 `move_child` 挪，手指按着某张（`_card_held`）或正在上下滑（`scroll_started/ended`）时不挪；「T」字每张卡自带一个、只亮在最上面那张。新 `_make_card` / `_drop_card` / `_clear_cards` / `_card_busy`。`_card_sig` 仍是「key|kind|签名」串、显示顺序平时和 manager 一致（ex_selftest 的 `hud_click_card` 靠这个） | `ex_hud_selftest` 新增：顺序倒过来后还是原来那几个按钮、顺序和 manager 一致、T 在最上面；`--level-test=desert` 无头「卡片 + T 键开箱」「点卡片拾取」都过 |
| uxperf-11 回主城鼠标不抓回 | 已修 | `main.gd:_return_to_hall`：放回主城后 `cam.capture_mouse` 且没开选关、没暂停就 `MOUSE_MODE_CAPTURED`（照 `_enter_level`） | 读代码（桌面窗口归回归代理） |
| uxperf-12 每帧改字色 / 重量信息牌 | 已修 | `ex_hud.gd`：新 `_set_col()`（颜色没变不改）用在 `_time_lab` / `_time_cap` / `_doc_lab` / `_down_sec`；信息牌 `reset_size()` 只在四行字变了时做；卡片列 `reset_size()` 只在卡片 / 露出张数变了时做 | 自检全过 |
| uxperf-13 门 0 里头像还是英雄皮肤 | 已修 | `player_plate.gd:_apply_mode`：切回老模式时 `_rebuild_shot(HeroSkin.player_key())` | 读代码 |
| gap-portrait-blank 换英雄后头像空白 | 已修 | `player_plate.gd:_rebuild_shot` 换了小视口后 `_av.queue_redraw()`；`_set_look` 设 UPDATE_ONCE 时也重画 | 读代码（截图归回归代理） |
| uxperf-14 桌面写「上下滑动」 | 已修 | `ex_hud.gd:_tick_cards`：桌面写「共 N 件 · T 拾取最近的」，手机照旧「上下滑动」 | 自检新增一条，两档都过 |
| uxperf-15 大厅每点一下整页重建 | 部分 | `ex_lobby_ui.gd:_select`：只换选中（东西没动）时只改旧 / 新两格的描边 + 重做底栏（`_restyle` / `_tiles` 表 / `_sel_key`），找不到格子（英雄页之类）才整页刷新。`ex_item_view.gd`：格子 / 卡片的纸片样式改成全局共用一份（`_sb()` 缓存），新 `set_selected()`。**没做**：买 / 卖 / 挪这些真改了数据的操作仍整页重建（一次点击一次，不再是两次） | `--lobby-test` 无头 0 失败（`act()` 每步都先 `_select` 再点底栏，走的就是新路） |
| gap-quick-use 快捷栏 | 已修 | `ex_hud.gd`：新 `_build_quick` / `_tick_quick` / `_pick_quick` / `_quick_use`。桌面 **1 = 服药**（挑刚好补满缺口的最小一种，补不满挑回得最多的，一样多挑读条短的），**2 = 投符**（背包里第一张），都调 `mgr.ui_use(i)`；桌面右下技能栏下面两颗 58 小圆钮（左上写键位、右下纸签写数量）。手机：「药」圆心 (vs.x−600, vs.y−78)、「符」(vs.x−700, vs.y−78)，直径 76，有药才露药、有符才露符；背包 / 结算 / 重伤时收起。数字键在 main 里只在「自检且老模式」改境界，新图里空着，不冲突（hud.gd 只用 F1 / B，H 是主城的一键服丹） | 自检新增：按 1 / 2（手机点钮）= `ui_use(那一格)`；和触屏按钮 / 摇杆 / 卡片列 / 玩家牌都不重叠（桌面 1600×900、手机 1600×900 与 1701×900 三档） |
| gap-portrait-blank | 见上 | | |
| gap-skills-hidden-ground 技能框只在空中 | 已修（触屏键跨文件） | `hud.gd:_refresh_air`：英雄档在新图里（`_ground_skills()` = `main._ex_mode()`）落地也露桌面四格技能框和觉醒槽；地上连击数 / 对波 / 蓄力条照旧收着；觉醒满了在地上写「腾空后按住 V（手机：御）聚气觉醒」（聚气只在空中）。主城不变（`GROUND_SKILLS_IN_HUB = false`，要的话改一个常量） | 读代码 + 自检技能栏位置框不重叠 |
| gap-hero-pick-flow 出战流程里看不到英雄 | 已修 | `level_select.gd`：新图入境页多一排英雄按钮（`_hero_row` / `_sync_hero_btns` / `_pick_hero`：点了存档 + 主城主角当场换，「这次带什么」那行跟着变；洞府关掉回来也同步）；新号（一局没进过）上面一行朱字「第一次入境：先挑一位英雄（洞府「英雄」页能看每一招）」。`ex_lobby_ui.gd:summary()` 开头写英雄名 | `--lobby-test` 新增三条：有按钮且按下的是当前英雄、点另一位后存档 / 主角 / 那一行都换了、点回来 |
| gap-onboarding 没有新手引导 | 已修 | `hud.gd`：F1 说明在英雄档按 `player.hero_def` 现写（共用基本操作 + 禁地里 T / Tab·B / 1 / 2 / M + 这位英雄四个技能 + 觉醒），境界条在英雄档不显示；老模式原文不动（抽成 `LEGACY_HELP` / `LEGACY_CHELP` 常量）。新号第一次回到主城说三句（`INTRO_LINES`，`hub.say` 排队，一句 4.5 秒）：门 2 / 门 3 → 撤离读条 → 卖给商人 / 洞府备战换英雄。`ex_profile.gd`：新字段 `intro` + `intro_pending()` / `mark_intro()`；测试档不说（不盖 `--hub-shot` 截图），带 `--ex-intro` 时照说。没碰 hub_hall.gd | 读代码 |
| I_int §6-6 段位题字带进下一局 | 已修 | `hud.gd:_ex_rank_banner`：记 `_rank_fx_on`；一开始切场景（`_switching`）或进了关卡就把那条题字收掉；取 take_rank_up 也要画面亮着 | 读代码 |
| I_int §6-11 结算「灵石 0」不带号 | 已修 | `ex_hud.gd:_signed`：0 写「+0」 | 自检新增「仙玉 +0」 |
| I_int §6-8 全房横幅盖住卡片列 | 已修 | `ex_hud.gd`：新 `_broadcast_rect()`（隔 0.25 秒在 mgr 底下找 realm_broadcast，亮着时取它那条的矩形）/ `_loot_top_now()`：横幅压在卡片列上就把列顶挪到横幅底下 8 像素，露几张按新顶算 | 自检新增：真的建一条 realm_broadcast 播出来，卡片列让到横幅下（桌面 306 → 360、手机 270 → 380）、不压别的，横幅没了回原位 |
| I_int §6-7 / uxperf-3 预热缺管理器的材质 | 已修 | `warmup.gd`：新 `_ex_mgr_fx()` 照 extract_manager 的设置各摆一个：撤离点底座（顶点色受光）、撤离光柱（不受光 / 加法 / 双面 / 不吃雾）、掉落光柱（吃雾）、符珠（不受光实心球）、烟遁符的烟（CPU 粒子 + 粒子朝镜头的透明面片 + 顶点色）、箱子 MultiMesh（顶点色 + 粗糙 0.85，桌面投影 / 手机不投）；`EX_SHADERS` 把 mob_ring（地面阵 / 法阵光 / 火圈）和 creature_overlay（掉落泛光）放进第 1 步 | 同上 `[warm] ex` 行 |
| 自动拾取开关 | 已做 | `ex_hud.gd`：储物袋题头「自动拾取：开 / 关」切换钮（`_auto_btn` / `_has_auto` / `_sync_auto`），读写 `mgr.auto_pick`，manager 没这个字段时不露 | 自检：有字段时露、点了 mgr.auto_pick 跟着变；半截管理器不露 |

## 2. 测试（都在 `D:\GodotProjects\修仙游戏` 下、都是 `--headless`；日志在 `_tasks/extraction_refactor/logs/`）

| 命令 | 结果 |
|---|---|
| `--headless --path . --quit`；`--check-only` 我改的 12 个脚本 | 我的文件无报错。启动时有一条别人的：`net.gd:101 get_meta("net", null)` 在 4.7 里没这个 meta 会报错（见第 3 节） |
| `--script res://scripts/ex/ex_hud_selftest.gd`（桌面） | **PASS 78 FAIL 0**（`F_ui_hudself_desk.txt`） |
| 同上 `-- --touch` | **PASS 81 FAIL 0**（`F_ui_hudself_touch.txt`） |
| 同上 `-- --touch --web-fonts --win=1701x900` | **PASS 81 FAIL 0**（`F_ui_hudself_phone.txt`） |
| `-- --lobby-test` | **失败 0 项**（`F_ui_lobby.txt`） |
| `-- --level-test=desert` | **总计 失败 0 项（通过 77 项）**（`F_ui_desert_log.txt`） |
| `-- --level-test=lab --warm` | **总计 失败 0 项（通过 80 项）**；`[warm] ex：预热 850 ms（着色器文件 9 个）… 新图 400（怪 7 种）`，同一张图再进不再预热（`F_ui_lab_warm_log.txt`） |
| `--script tools/ex_data_check.gd`（不带参数 / 带 `-- --data-check`） | 不带：exit 1、不碰存档；带：坏条目 0 |
| 临时 `scratchpad/F_ui/profile_save_test.gd -- --profile-save-test --keep-profile` | **8 / 8 PASS** |
| `python -I _tasks/ui_kit/font_check.py`（只核对） | 我的文件不缺字 |

ex_hud_selftest 为了能无头跑，改了两处：无头时 `_shot` / `_zoom` 不截图；`-- --win=宽x高`（默认 1280x720）在无头下用 `content_scale_size`（高 900、宽按比例）+ KEEP 模拟真屏比例（无头窗口固定 1600×1600）。

**没跑的**（要开窗口，归回归代理）：`--raid-shot`、`--hub-shot`、`--hub-shot --arena-duel`（截图走 `frame_post_draw`，无头会卡）、两张图的整局截图、局域网双开（combat-4 / net-6）、桌面鼠标（uxperf-11）、头像（uxperf-13 / gap-portrait-blank）。

## 3. 要别的文件配合的（交给回归代理）

1. **net.gd（combat-4 后半）**：房间名单里的 `hero` 只在 host / join 那一刻记一次。主城里换了英雄（洞府 / 入境页 / 头像「换」），留着的房（`keep_room`，再入境回到这间房）里还是旧英雄。请在 `player.hero_changed` 时（`net.active`）重发一次名单信息（H 已知问题 4 同一件事）。
2. **net.gd:101（F_mgr 的 net-5）**：`player.get_meta("net", null)` 在 Godot 4.7 里默认值给 null 照样报「does not have any 'meta' values with the key 'net'」，开机就一条 ERROR。改成 `player.get_meta("net") if player.has_meta("net") else null`。
3. **touch_controls.gd（gap-skills-hidden-ground 的触屏一半）**：`_btn_on` 里英雄档四个技能键只在 `air` 时露。新图里（`main._ex_mode()`）请地上也露（御剑的「罡」照旧看 `btn_visible(3)`）。hud.gd 这边桌面技能框和觉醒槽已经地上也露了。
4. **extract_manager.gd（uxperf-5，可选）**：卡片按距离排序加 0.5 米左右的滞后，远近差不多的两件就不来回换位置（界面这边已经不重建、按着不挪了，这条只是让画面更稳）。
5. **ex_selftest.gd（提醒）**：`hud_click_card` 按 manager 的下标点 `_loot_box` 的第 i 个子节点。现在显示顺序平时和 manager 一致；只有手指正按着某张卡片 / 正在滑时会暂时不一致（自检直接 emit pressed，碰不到）。
6. hub_hall.gd：**没有要改的**（引导 / 离线结算都走它现有的 `say`）。

## 4. 新汉字

没有。新写的界面字（「自动拾取：开 / 关」「身上没有药 / 符」「T 拾取最近的」「第一次入境：先挑一位英雄……」三句引导、存档恢复 / 坏档提示、F1 英雄说明、「腾空后按住「御」聚气觉醒」）`font_check.py` 核过都在字库里；自检里原来用了个「捷」，已改成别的说法。

## 5. 和建议修法不一样的地方

- econ-4：没用「改名换文件」那套（网页版的 user:// 改名不会触发落盘同步，杀页面时反而可能丢最新一份），改成「先整份写 .tmp、再写正式文件」两次关文件（每次关文件网页版都会同步），再加开机时的 .bak。
- uxperf-5：没按「插入顺序不变」做，保留了「由近到远、最上面那张就是 T 拿的」，只是改成挪节点、按着 / 滑着不挪。
- econ-7：确认按钮的防抖用「不接点击 + 变淡」，没用 `disabled`（主按钮样式没有禁用态，会闪一下引擎默认的灰色）。
- gap-hero-pick-flow：入境页用一排切换按钮（英雄只有两位，一眼看全）；全屏英雄选择界面是另一个代理在做的（hero_select_ui.gd），我没去接它的接口，以免它还在改时被我拖坏。
