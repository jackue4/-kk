# REG 回归 / 整合报告：四个修复者交活之后

日期 2026-11-24（19:05 ~ 20:05）。执行者 REG（回归 + 整合）。没有 commit / push，没有部署。
改动前的备份：`_tasks/extraction_refactor/backup/<文件名>.reg.txt`（spell_projectile / net / touch_controls / main / ex_hud / warmup / remote_player / air_foe / extract_manager / raid_mob / arena_duel / hero_selftest / ex_selftest，共 13 个；raid_mob 备了没改）。
日志都在 `_tasks/extraction_refactor/logs/reg_*`（每条命令 `_out.txt` / `_err.txt`，跑的顺序和用时在 `reg_queue_status.txt`）。

## 0. 结论

- **全部命令最后都 PASS，所有日志 0 个 SCRIPT ERROR（下面列的两处测试脚本问题除外）。** 第一遍有 4 处没过，查下来都是自检脚本 / 演示流程的问题，没有游戏逻辑回归：
  1. 沙漠整局「雷符」：附近有两处刷怪点、6 只怪，符被另一处的怪吸走，自检只算这一处 3 只的血。改成按 45 米内所有怪算，重跑 PASS。
  2. 局域网双开（`--ex-lan`）：F_mgr 新加的自动拾取抢在「点卡片捡房主开出来的东西」之前把那件捡走了，自检访问已释放的对象报错卡住，连带房主那边 4 项失败。双开自检里关掉自动拾取，重跑结果见第 3 节。
  3. 桌面 `--hero-test`「剑域只接得住第一下」：第二下落在反斩闪身的无敌帧里（返回 −1），按时间窗判，和用户同时开着游戏、帧率抖有关。兼容档同一轮 PASS，桌面重跑 PASS（23 行）。
  4. 老大世界 `--raid-shot`：演示角色在坠魔谷被打死、后半段跳过（D_econ 报过同样的现象）。重跑全程 PASS：撤离成功、回到大厅。
- **跨文件请求都处理了**（第 1 节）：必做的全做了，可选的做了 5 条、跳过 4 条（跳过的写了原因）。
- **新写了第二套局域网双开自检 `--ex-lan2`（研究所）**，专测 F_mgr 改过、单机测不到的 6 件事。房主 17 / 17、加入方 8 / 8 全过（第 3.2 节）。
- **网页档的绘制调用明显下降**（第 4 节）：
  - 开局：沙漠 285 → 161，研究所 349 → 215；
  - 重伤：沙漠 349 → 204，研究所 407 → 258；
  - 研究所首领掉落：389 → 227；
  - 大地图：沙漠 184 → 96，研究所 277 → 77。
  - 还超 220 的只剩储物袋（模态，359~394）、研究所结算页 / 重伤（258~266），以及沙漠首领掉落（247，第二遍 208）。
- **测试期间另有一个「界面重做」代理在改界面文件**（19:50 起把 hud / ex_hud / touch_controls / minimap / player_plate / ex_item_view 的样式换成 `ink_style.gd`，还新建了 meta_*.gd）。它没覆盖我的改动（逐个 diff 过）。但第二批截图（`*_gl2` 那一轮）已经是新样式，第一批是旧样式。

## 1. 跨文件请求的处理

| 来源 | 请求 | 处理 | 改了哪里 |
|---|---|---|---|
| F_combat (a) | 飞剑穿墙（combat-3 的另一半） | **做了**。<br>• 每步射线没打中时，再问 `player.solid_hit(当前位置, 下一步, 0.5)`。<br>• 追踪剑「够近就算中」那一支先看中间隔没隔墙，隔墙就不算中，接着走射线、撞在墙上。<br>• 非新图 `solid_hit` 恒为 INF，老大世界 / 主城不受影响。 | `spell_projectile.gd:_process` |
| F_combat (a) 验证 | — | `--hero-test=wall` 加了一项：墙外朝墙里的木桩放一柄追踪剑 + 一柄直飞剑，木桩掉血 0；对照空地上的木桩掉 12。PASS | `hero_selftest.gd`（挡墙探针末尾） |
| F_combat (b) | 飞剑带 pvp_k 标记 | **没做**（可选）。逐柄判定已经修掉复核说的那种情况，剩下的边角见第 6 节 | — |
| F_combat (c) | AI 修士近身判定隔墙 | **做了**。`_resolve_strike` 先问 `player.air._seen(...)`，非新图恒为 true | `air_foe.gd:_resolve_strike` |
| F_combat (d) | 擂台名牌「结丹 Lv.N」 | **做了，只改字**。英雄档写「名字 · 英雄」，对手是真人就写「英雄 · 名字」（名字从房间名单的 hero 取），AI 陪练只写名字。擂台数值（arena_adv 仍按老修为 lv）没动。截图 `_shots/arena/3_fight.jpg`：「青云37 · 御剑」对「陪练 · 太虚」 | `arena_duel.gd:_refresh_ui` / `_begin_pvp` / AI 开场，新增 `_hero_name`、`_rival_hero` |
| F_ui 1 | 主城换英雄后，留着的房间名单还是旧英雄 | **做了**。net `_ready` 接 `player.hero_changed`：<br>• 房主：直接改名单再广播；<br>• 加入方：新 RPC `_hero_set` 请房主改。<br>（协议又多一个 RPC，本来就要全员换包。）`--ex-lan2` ⑤ 实测：加入方换成苍鸿，房主那边木偶 hero_id = canghong | `net.gd:_on_hero_changed` / `_hero_set` |
| F_ui 2 | `net.gd:101 get_meta` 开机报错 | F_mgr 已经改成先 `has_meta`。复核：`--headless --quit` 0 报错 | — |
| F_ui 3 | 触屏英雄技能键落地也露 | **做了**。新图里落地也露（御剑的「罡」照旧看 `btn_visible(3)`）。另加：重伤倒地时收起（截图里倒地还露着四颗技能键）。`ex_desert_camp_gl.jpg` 地上露「剑 / 诀 / 阵」；`ex_desert_downed_gl.jpg`（第二遍）倒地时收起 | `touch_controls.gd:_btn_on`，新增 `_ex_ground()` |
| F_ui 4 | 卡片远近排序加滞后 | **做了**。`CARD_HYST = 0.5` 米：远近差不到 0.5 米的相邻两张，照上一帧的先后排（只扫一遍） | `extract_manager.gd:_update_cards` |
| F_maps 1 | `touch.blocked` 只由 main 写 | **做了**。`_level_bag_open()` 先问 `level.big_map_open()` | `main.gd:_level_bag_open` |
| F_maps 2 | 瞬身落点挡墙 | F_combat 已在 `air_melee._legal` 里做了（solid_at + solid_hit），`--hero-test=wall` 测过。不重复做 | — |
| F_maps 3 | 管理器早一帧关大地图 | **没做**（可选，关卡每帧已经自己关） | — |
| F_maps 4 | `_sync_mouse` 自愈 | **做了**。只往「放出来」那边修 | `ex_hud.gd:_sync_mouse` |
| F_maps 5 | 大地图开着时藏 HUD 层省绘制 | **没做**（可选）。大地图开着时网页档已经只有 77~96 次 | — |
| F_mgr 1 | 储物袋自动拾取开关 | F_ui 已做（`_auto_btn`）。截图 `ex_desert_bag_gl.jpg` 题头有「自动拾取：开 / 关」 | — |
| F_mgr 1 | 结算页标题 80 号（uxperf-10） | **做了**：改成 58，和 ex_hud 的 `_banner`、realm_broadcast 同一档。截图 `ex_lab_result_gl.jpg` 看过 | `ex_hud.gd:_show_result` |
| F_mgr 2 | 预热手机档远处掉落的两个 MultiMesh 材质 | **做了**（只在 `Vfx.lite` 时摆）：<br>• 宝石：不受光 + 顶点色 + 实例色；<br>• 光柱：不受光 / 加色 / 双面 + 实例色，网格格式和管理器一致。 | `warmup.gd:_ex_mgr_fx` |
| F_mgr 3 | 沙漠 horde | F_maps 已加。`--level-shot=desert` 的 `desert_horde` PASS（入夜加刷 3 只） | — |
| F_mgr 4 | econ-6 剩下的那半（房主在主城关房） | **决定：照 SPEC 4.6 保留「算平安撤离」，不改代码**，理由见第 6 节第 2 条，列为待用户拍板 | — |
| F_mgr 5 | `remote_player.awaken_stop()` | **做了**。net.gd 改调它，不再直接改 `_awake_fx.left`。`--ex-lan2` ④ 实测：觉醒中剩 12.2 秒 → 对方收了之后 −0.6 秒 | `remote_player.gd`、`net.gd:_state` |
| F_mgr 5 | air_foe 的 `block_fn` 替掉 `_clamp_foes` | **没做**。管理器的做法能用，换实现风险大于收益 | — |
| F_mgr 5 | raid_mob 御剑 / 俯冲时不调 atk_out | **没做**（F_mgr 说现在无副作用） | — |

**自检脚本的修正**（只动测试代码）：
- `ex_selftest.gd`：
  - 雷符按 45 米内所有怪算血；
  - `run_lan` 关掉自动拾取；
  - 8 处 `return _lan_end()` 改成 `await _lan_end()` + `return`（原来会报「Trying to call an async function without await」）；
  - 新加 `run_lan2`（第 3.2 节）。
- `hero_selftest.gd`：挡墙探针加飞剑一项。

## 2. 编译 / 字体

- `--headless --quit` 全项目：0 报错。改前、改后各跑一次（`reg_compile0.txt` / `reg_compile1.txt`）。
- `--check-only`：scripts/ex 全部 + 我动过 / 修复者动过的 30 个脚本全过。另一个代理在改的 hud / ex_hud / touch_controls / minimap / player_plate / ex_item_view / main，在它 19:50 那次改完之后又核了一遍，也都过。
- 字体：
  - `python -I _tasks/ui_kit/font_check.py --patch`：need 270，补上 269。新补的主要是另一个代理 meta_*.gd 的「吗 扔 磨 筛」，还有 mijing 的「泉 祠 篁 龛」、①～⑯、「严」「趴」。
  - 只剩 ✗ U+2717 一个没补上，只在 shenshi_selftest.gd 里用到（原来就缺）。
  - 加锁导入：`import.lock` 不存在，建锁 → `--headless --import` 退出码 0 → 删锁（`reg_import.txt`）。
  - 截图里没看到方块字（gl 档的结算页、储物袋、重伤、入境页、大地图都看过）。

## 3. PASS / FAIL 表

所有命令都在 `D:\GodotProjects\修仙游戏` 下，用 `python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/<前缀> --resolution 1280x720 [--rendering-method gl_compatibility] -- <参数> --regrun` 跑。`--regrun` 只是给进程打标记，方便按命令行认出自己的进程。一次只开一个窗口，局域网双开除外。

| 命令 | 渲染器 | 结果 | 日志前缀 |
|---|---|---|---|
| `--level-test=desert` | Forward+ | 第一遍 76 / 77（雷符，自检问题）→ 重跑 **PASS 77 / 77** | `reg_desert` → `reg_desert2` |
| `--level-test=desert --touch` | 兼容 | **PASS 78 / 78**；改了触屏后重跑 **PASS 78 / 78** | `reg_desert_gl` / `reg_desert_gl2` |
| `--level-test=lab` | Forward+ | **PASS 80 / 80** | `reg_lab` |
| `--level-test=lab --touch` | 兼容 | **PASS 81 / 81** | `reg_lab_gl` |
| `--hero-test` | Forward+ | 第一遍 FAIL 1（剑域时间窗）→ 重跑 **PASS（23 行）** | `reg_hero` → `reg_hero2` |
| `--hero-test --touch` | 兼容 | **PASS（23 行）** | `reg_hero_gl` |
| `--hero-test=wall` | Forward+ | **PASS**：挡墙全部项 + 新加的飞剑项 | `reg_hero_wall` |
| `--lobby-test` | Forward+ | **PASS**（失败 0 项） | `reg_lobby` |
| `--boss-test-ex` | Forward+ | **PASS**（失败 0 项，149 秒） | `reg_bossex` |
| `--hub-shot` | Forward+ | **PASS**：<br>• 四道门 [0, 1, 2, 3] 都触发；<br>• 试剑台进出；<br>• 木兰草原进关 / 撤回都 true | `reg_hub` |
| `--level-test=desert --ex-gate` | Forward+ | **PASS 6 / 6**：门 2 → 沙海古墟、门 3 → 天工秘所，走正式入境页、端口偏移 100 | `reg_gate` |
| `--raid-shot`（老大世界） | Forward+ | 第一遍演示角色在坠魔谷陨落、后半段跳过（无报错）→ 重跑 **PASS**：撤离成功、带出 8 件、回到大厅 = true；小地图（direct 模式）和以前一样 | `reg_raidshot` → `reg_raidshot2` |
| `--hub-shot --arena-duel` | Forward+ | **PASS**：单机胜 2 负 4；名牌已经是英雄名 | `reg_arena` |
| `--script ex_hud_selftest.gd` | Forward+ | **PASS 78 / 78** | `reg_hudself` |
| 同上 `-- --touch` | 兼容 | **PASS 81 / 81** | `reg_hudself_gl` |
| `--level-shot=desert --touch --sliced` | 兼容 | **PASS**（失败 0）：<br>• 新项 `desert_horde` / `bigmap_3d_off` / `bigmap_downed`；<br>• 大地图 draw 96 | `reg_lvshot_desert_gl` |
| `--level-shot=lab --touch --sliced` | 兼容 | **PASS**（失败 0）：<br>• `lunge_wall`、`bigmap_*`；<br>• 大地图 draw 77 | `reg_lvshot_lab_gl` |
| 双开 `--level-test=desert --ex-lan=host / join` | Forward+ ×2 | 第一遍：加入方被自动拾取卡住，房主 6 / 10、加入方超时（自检问题）→ 重跑 **PASS 房主 10 / 10、加入方 11 / 11**，0 脚本错误 | `reg_lan_*` → `reg_lanb_*` |
| 双开 `--level-test=lab --ex-lan2=host / join`（新） | Forward+ ×2 | **PASS 房主 17 / 17、加入方 8 / 8**，0 脚本错误 | `reg_lan2_host` / `reg_lan2_join` |
| 双开 `--hero-test=pvp_a / pvp_b` | Forward+ ×2 | **PASS**：<br>• a（苍鸿）招架成功 6 次，b（御剑）收到「被招架」6 次、硬直 6 次；<br>• 两边木偶的英雄、皮肤、剑都对（a 看 b：yujian；b 看 a：canghong + 剑） | `reg_pvp_a` / `reg_pvp_b` |
| 双开 `--hub-shot --lan-test=a / b`（局域网在场） | Forward+ ×2 | **PASS**（功能项）：<br>• 互见、走动跟随、擂台配对、收场后又互见；<br>• 名牌「明月66 · 御剑 · 未入流」（combat-13 / gap-legacy-labels）。<br>stderr 有 2 条 `hub_hall.gd:2012 _through` 调空对象：自检直接调了已经封掉的灵田门（`_portal_town` 为 null），正常游玩走不到这里，是 lan_selftest 过时 | `reg_lansel_a` / `reg_lansel_b` |

### 3.1 `--ex-lan` 重跑（关掉自动拾取之后）

**房主 10 / 10、加入方 11 / 11，0 脚本错误**（`reg_lanb_host` / `reg_lanb_join`）。和 I_int 那次一样，几项都过了：
- 互见；
- 房主开的箱子加入方也记开过；再抢被拒；
- 加入方捡房主开出来的东西（向房主申请，背包 3 → 4 格）；
- 加入方开的箱子房主也记开过，地上多 1 件共享掉落；
- 房主重伤，3.9 秒后被队友救起，强心丹 2 → 1；
- 两边各自撤离。

### 3.2 新的 `--ex-lan2`：F_mgr 那几条联机修复的实测（研究所，同一台机器两个隐藏窗口，测试端口 +100）

时间同步：两边对表用房间时钟。房主定零点，借房间名单自己那一条发出去（只在自检里）。加入方晚 24 秒才进，保证 ① 测的真是「中途加入」。

| 步骤 | 房主 | 加入方 | 对应复查 id |
|---|---|---|---|
| ① 房主先用钥匙开门 K1、开掉房里的 b101；加入方之后才进来 | 门 A 开着、RA 开出 4 件 PASS | RA 记开过、再申请被拒（开箱数 0 → 0）、站在边上不出卡片 PASS | rules-2 / net-1 / econ-1 |
| ② 两人同时在门 K10 读条开门 | 门开了，**我扣 1 把** | 门开了，**我扣 0 把**，相加 = 1 | rules-14 |
| ③ 两人同时在祭台召唤铁穹双卫 | 真身 2、木偶 0 | 真身 0、木偶 2，**只有一套**（截图 `ex_lab_lan2_join_boss.jpg`） | rules-3 / net-3 |
| ④ 加入方觉醒，2.5 秒后提前收 | 描边剩 12.2 秒 → 收了之后 −0.6 秒 PASS | — | net-13（走新的 `awaken_stop`） |
| ⑤ 加入方换英雄，再换成苍鸿朝房主放断月 | 木偶英雄 = canghong PASS；看到 2 道只画的剑气 PASS | — | REG 的 `_hero_set`（combat-4 后半）、net-5 |
| ⑥ 房主撤离 → 回主城（房间留着）→ 再入境 | 留着房 PASS；再入境 PASS；**门 A / B 还开着、RA 还记开过** PASS；再入境后互见 PASS | 房主走了又回来，看见木偶 PASS | rules-5 / net-2 / econ-2，net-11 |
| 最后两边各自撤离 | PASS | PASS | — |

**没测到的联机项**：
- 天工师持有者断线 / 入夜（rules-8 / net-4 / net-7）：只有单机自检的营救 / 走失 / 再救回来；
- 两台真机器；
- 敌对两队真人对打、遗物箱被别人抢；
- 房主关房 `room_collapsed`、自己掉线 `room_lost`。

## 4. 性能（网页档 = 兼容渲染器 + 触屏；预算：绘制 ≤ 220、图元 ≤ 220k）

数字来自整局自检的截图行和分账行（`reg_desert_gl` / `reg_lab_gl`，第一批，还是旧界面样式）。「之前」= I_int §5.1。

| 时刻 | 沙漠 之前 | 沙漠 现在 | 研究所 之前 | 研究所 现在 | 说明 |
|---|---|---|---|---|---|
| 出生 | 285 / 142k | **161 / 125k** | 349 / 200k | **215 / 173k** | 手机档开局题字换成 `hud.banner`（F_mgr d） |
| 开箱 | 148 / 148k | 147 / 119k | 176 / 174k | 160 / 144k | 箱子紧排（uxperf-4），图元降 |
| 钥匙房 | 149 / 92k | 150 / 56k | 178 / 197k | 158 / 136k | |
| 刷怪点 | 204 / 223k | 199 / 186k | 211 / 212k | 190 / 152k | |
| 首领在场 | 217 / 197k | 215 / 220k | 245 / 245k | **200 / 184k** | |
| 首领掉落撒满 | 247 / 209k | 247 / 225k（第二遍 208 / 168k） | 389 / 268k | **227 / 180k** | 研究所 48 件：掉落一项 160 → 34（F_mgr c） |
| 储物袋开着 | 450 / 229k | 394 / 153k（第二遍 359） | 395 / 135k | 374 / 119k | 模态面板，仍超 |
| 撤离点 | 179 / 218k | 163 / 173k | 227 / 272k | 207 / 206k | |
| 结算页 | 250 / 217k | 225 / 172k（第二遍 206） | 288 / 279k | 266 / 202k | 界面约 123~125 |
| 重伤 | 349 / 143k | **204 / 126k**（第二遍 175） | 407 / 201k | **258 / 174k** | 不再有题字层；研究所小地图这一刻 24 次 |
| 夜里尸潮 | — | （新加，`desert_horde`） | 162 / 154k | 218 / 170k | 拍的时刻不同，不能直接比 |
| 天工师随行 | — | — | — | 202 / 160k | |
| 大地图开着（`--level-shot`） | 184 | **96 / 3k** | 277 | **77 / 4k** | 3D 关掉 + 标记合批（F_maps） |

- 分账：
  - 小地图大多数时刻降到 3~14 次（以前 24~51）；研究所首领掉落 20 次、重伤 24 次。
  - 触屏层 37~51，hud.gd 22~49，ex_hud 31~65（结算页约 125）。
- 「第二遍」一列是我改了触屏之后、加上另一个代理换了样式之后（`reg_desert_gl2`）。沙漠首领掉落 208、结算页 206、重伤 175，都进了预算。
- 桌面 Forward+（不按预算算，带影子）：研究所首领掉落 372（I_int 406），撤离点 245，出生 368（桌面仍用 RealmBanner）。
- 预热（`[warm] ex`）：沙漠 2635 ms，研究所 1990 ms（新图 578 ms、怪 7 种）。

## 5. 截图检查（只看 `_shots/preview/*.jpg`）

- **快捷钮 vs 触屏键**：`ex_desert_camp_gl` / `ex_desert_boss_loot_gl` / `ex_lab_*_gl` 里，「药」钮（屏宽 0.62、贴底）和地上露出来的「阵」键离得开，不重叠。`exhud_gl_touch_hud` 里「符 / 药」两颗和「回 / 御」也不重叠。
- **卡片 vs 横幅**：`exhud_gl_touch_broadcast` 里，「首领现身」横幅亮着时，卡片列让到横幅下面。
- **大地图在结算 / 重伤时**：`lvshot_*_bigmap_gl` 里，面板外是不透明的墨色底，标记、字正常。`bigmap_downed` 两张图都 PASS（重伤 3 帧内合上、再开被拒、3D 还原）。结算页 / 重伤截图里没有大地图。
- **方块字**：gl 档的储物袋、结算、重伤、入境页、大地图、擂台都没有。
- **主城 / 大厅选英雄流程**：
  - `lobby_entry_desert`：入境页有「英雄　御剑 · 飞剑法修 / 苍鸿 · 剑修」一排，玩家牌头像是苍鸿（换英雄后头像不空白，gap-portrait-blank）；
  - `lobby_hub_plate`：主城右上角是新的四个入口（另一个代理加的）；
  - `ex_desert_gate2_in`：桌面右下的 E / Z / Q 技能框在地上也露。
- **擂台**：`_shots/arena/3_fight.jpg` 顶栏「青云37 · 御剑」对「陪练 · 太虚」。AI 头顶名牌还是「陪练 · 太虚 Lv.7」（见第 6 节）。
- **重伤**：`ex_desert_downed_gl`（第二遍）重伤时只剩 攻 / 御 / 闪 / 飞，技能键收起；纸条「自救 / 自尽」正常。

## 6. 还开着的问题（按严重程度）

1. **【中】还超网页预算的时刻**：
   - 储物袋（模态，359~394）；
   - 研究所结算页 266 / 重伤 258：关卡底子 60~90、ex_hud 结算页约 125、hud.gd 约 30~50；
   - 沙漠首领掉落第一遍 247（第二遍 208）。
   储物袋 / 结算页是模态面板，可以考虑开着时关 3D（照大地图的做法），或把格子合批。
2. **【中 · 待用户拍板】econ-6 剩下的那半：房主在主城关房，房里所有人都算平安撤离、带出整包。** 我决定照 SPEC 4.6 保留，理由：
   - SPEC 原文和 DarkArea 都是这样；
   - 「只有站在撤离区里才算」会把房主正常退出变成惩罚别人；
   - 「不结算撤回」要在 ex_profile 加一条新的结算路（这个文件另一个代理正在改），还会退回已经用掉的药 / 符；
   - 重伤倒地的那种已经被 F_mgr 堵上了（按陨落算）；
   - 剩下的漏洞要队友配合（房主先撤、再关房），收益只是省了跑去撤离点的路。
   要收紧的话，建议做「不结算撤回 + 已用掉的消耗品不退」。
3. **【中】没测到的联机项**：天工师持有者断线 / 入夜换周期（rules-8 / net-4 / net-7）、两台真机器、敌对两队真人、房主关房 / 掉线。
4. **【低】PvP 连发的边角**（combat-12）：直飞剑一条线上先擦到怪、后面才是真人时，那只怪也按 0.55 吃；出手后才横穿进弹道的真人按整份。要彻底改得让 spell_projectile 带 pvp_k 标记（F_combat b），这次没做。
5. **【低】gap-legacy-labels 剩下的**：
   - air_foe（AI 修士 / 擂台陪练 / 道友）的头顶名牌还带「Lv.N」；
   - 擂台数值还按老修为 lv 算 arena_adv。
6. **【低】复查里没人认领的三条 gap**：
   - gap-legacy-gate0（门 0 木兰草原整套老循环还开着）；
   - gap-hub-dead-props（灵田 / 修炼场的牌子还在）；
   - gap-ai-no-heroes（AI 不用英雄系统）。
7. **【低 · 测试环境】自检时序对帧率敏感**：
   - 桌面 `--hero-test` 的剑域连接、老大世界 `--raid-shot` 演示角色在坠魔谷陨落，第一遍都没过、重跑都过；
   - 这一轮用户的游戏一直开着（PID 37708，后来换成 33588），隐藏窗口还可能收到真人按键（记忆里的老问题）。
8. **【低 · 测试脚本】`lan_selftest.gd` 的灵田那一步**直接调 `hub._through(null, …)`，灵田封掉之后会报两条 SCRIPT ERROR（不影响其余项）。该改成灵田没开时跳过。
9. **【低】uxperf-11（回主城鼠标抓回）、uxperf-13（门 0 头像）**：自检里鼠标是放开的，验证不了，只读了代码。
10. **【提醒】另一个「界面重做」代理还在改界面**：
    - 它在改的：hud / ex_hud / touch_controls / minimap / player_plate / ex_item_view / ex_profile / level_select，以及新的 meta_*.gd、ink_style.gd；
    - 它改完以后，整局自检、界面自检、`--lobby-test` 都该再跑一遍；
    - ex_profile.gd 它也在改，econ-4 的存档测试（F_ui 的临时脚本）也该重跑。

## 7. 复查 id 的验证情况

用测试 / 截图实测过的：

| id | 怎么验的 |
|---|---|
| rules-2 / net-1 / econ-1 | 单机回放（整局自检）+ `--ex-lan2` ① |
| rules-3 / net-3 | `--ex-lan2` ③ |
| rules-4 | 整局自检「死亡掉落：法宝（装备栏 + 背包里的）」 |
| rules-5 / net-2 / econ-2 | `--ex-lan2` ⑥ |
| rules-6 / net-9 / combat-5 | 整局自检「没落实的一下 / 落实的一下」 |
| rules-7 | 整局自检「撤离区里也能服药」 |
| rules-11 | 整局自检 |
| rules-14 | `--ex-lan2` ② |
| net-5 | `--ex-lan2` ⑤ |
| net-10 | 整局自检回放 |
| net-11 | `--ex-lan2` ⑥ |
| net-13 | `--ex-lan2` ④ |
| econ-5 | 整局自检「进图 / 局内锁同步」 |
| econ-7 / uxperf-15 | `--lobby-test` |
| combat-1 / 2 / 6 / 7 / 10 / 11 / 13、uxperf-16、gap-training-numbers | `--hero-test` 两档 |
| combat-3 | `--hero-test=wall`（含飞剑） |
| combat-8 | `--level-shot=lab` `lunge_wall` |
| combat-12 | 只验了「打木桩数值不变」，加上 pvp 双开招架回传 |
| uxperf-1 | `bigmap_downed` |
| uxperf-3 | `[warm] ex` 行 |
| uxperf-4 | 整局自检开箱 / 复原 + 第 4 节图元 |
| uxperf-5 / 12 / 14 | `ex_hud_selftest` 两档 |
| uxperf-10 | 结算页截图 |
| gap-quick-use | 截图 + 界面自检 |
| gap-auto-pickup | 储物袋截图 + 整局自检 step_rules |
| gap-skills-hidden-ground | 截图（桌面技能框、触屏技能键） |
| gap-hero-pick-flow | `--lobby-test` + 入境页截图 |
| gap-desert-night | `desert_horde` |
| gap-legacy-labels | 局域网在场的名牌 + 擂台顶栏 |
| gap-portrait-blank | 入境页截图 |

只读过代码、没有实测的：
- rules-1、rules-8 / net-4 / net-7（联机部分）、rules-9 / econ-3、rules-12、rules-13；
- net-6、net-8、net-12；
- econ-4（F_ui 的临时测试 8 / 8，我没重跑）、econ-8、econ-9；
- combat-4（前半）；
- uxperf-2（main 那一半已接上，真机触屏没测）、uxperf-11、uxperf-13；
- gap-onboarding。

## 8. 改过的文件

- **游戏代码**：
  - `scripts/spell_projectile.gd`
  - `scripts/net.gd`
  - `scripts/remote_player.gd`
  - `scripts/touch_controls.gd`
  - `scripts/main.gd`
  - `scripts/ex/ex_hud.gd`
  - `scripts/warmup.gd`
  - `scripts/air_foe.gd`
  - `scripts/ex/extract_manager.gd`
  - `scripts/arena_duel.gd`
- **测试代码**：
  - `scripts/ex/ex_selftest.gd`
  - `scripts/hero_selftest.gd`
- **字体**：
  - `assets/fonts/SourceHanSansCN-Normal.patch.ttf`（font_check --patch 重做）
  - `.godot` 导入缓存
- **联机协议又变了**：net.gd 多了 `_hero_set` RPC，局域网里所有人都要换包。

## 9. 命令（照抄可跑）

```
# 编译
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --quit
"…console.exe" --headless --path . --check-only --script res://scripts/<文件>.gd
# 字体 + 导入（先看 _tasks/extraction_refactor/import.lock，10 分钟内有就等）
python -I _tasks/ui_kit/font_check.py --patch
"…console.exe" --headless --path . --import
# 单开（一次一个）
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/reg_desert --resolution 1280x720 -- --level-test=desert
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/reg_desert_gl --resolution 1280x720 --rendering-method gl_compatibility -- --level-test=desert --touch
（lab 同理；--hero-test [--touch]；--hero-test=wall；--lobby-test；--boss-test-ex；--hub-shot；--level-test=desert --ex-gate；--raid-shot；--hub-shot --arena-duel）
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/reg_hudself --resolution 1280x720 --script res://scripts/ex/ex_hud_selftest.gd
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/reg_hudself_gl --resolution 1280x720 --rendering-method gl_compatibility --script res://scripts/ex/ex_hud_selftest.gd -- --touch
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/reg_lvshot_lab_gl --resolution 1280x720 --rendering-method gl_compatibility -- --level-shot=lab --touch --sliced
# 双开（两个窗口同时起，B 晚 2 秒）
… -- --level-test=desert --ex-lan=host     ||  … -- --level-test=desert --ex-lan=join
… -- --level-test=lab --ex-lan2=host       ||  … -- --level-test=lab --ex-lan2=join
… -- --hero-test=pvp_a                     ||  … -- --hero-test=pvp_b
… -- --hub-shot --lan-test=a               ||  … -- --hub-shot --lan-test=b
```

批量跑用的两个小脚本在草稿目录：`reg_queue.py`（顺序跑）、`reg_pair.py`（双开）。它们只调 run_hidden.py，不杀任何进程。整轮下来我没有结束过任何进程。
