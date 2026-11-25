# F_mgr 交付报告：管理器 / 联机 / 数据层的审查修复

日期 2026-11-24。修复者 F_mgr。没有 commit / push，没有部署，没有跑 `--import`。
改动前的备份：`_tasks/extraction_refactor/backup/<文件名>.fix.txt`（extract_manager / ex_boss / ex_data / ex_doctor / ex_mobs / ex_worm / ex_selftest / net，共 8 个）。
实际改了的：`scripts/ex/extract_manager.gd`、`scripts/net.gd`、`scripts/ex/ex_data.gd`、`scripts/ex/ex_boss.gd`、`scripts/ex/ex_selftest.gd`。
ex_doctor / ex_mobs / ex_worm 这轮没有要改的地方。

**联机协议又变了，局域网里所有人都要换包。** 新旧混连会对不上。

## 1. 每个 id 的处理结果

同一个根因的几条合在一起修，表里按根因分组。

| id | 结果 | 改了什么（文件:函数） | 怎么验的 |
|---|---|---|---|
| **rules-2 / net-1 / econ-1**：钥匙房箱子被同步 / 重进 / 续门刷新 | 已修 | **manager**：<br>• `_door_apply(id, open, t, refill := false)`：只有用钥匙开门那一下复原箱子。<br>• 新增 `_door_open_key`、`_refill_boxes`。<br>• `net_ex_door`：别人开门只复原他发来的箱子号；「我还在房里」重开门、续时间都不复原。<br>• `net_ex_sync`：先摆门（不复原），再摆箱子。<br>• `_box_read`：申请时带上「钥匙房」标记。<br>**net**：<br>• `ex_box_claim(idx, room)`，新表 `_ex_room_boxes`（申请标记 + 开门复原名单两处登记）。<br>• `_ex_box_judge`：钥匙房的箱子开过就不批，不管过了多久。<br>• `_ex_sync_req`：开箱记录全发，不再按 180 秒筛。 | 自检新增「回放：钥匙房的箱子不被同步 / 续门复原」PASS：同步后仍开过、续门后仍开过、带箱子号的真开门才复原 |
| **rules-5 / net-2 / econ-2**：房主回到留着的房间是空白局面 | 已修 | **net**：新增 `ex_local_sync()`，把房主自己那几张表（箱子 / 门 / 首领冷却 / 天工师 / 刷怪点）套给新管理器。<br>**manager**：`_ready` 里房主调用它。<br>天工师那一半见 rules-8：表里带周期号，同一周期救走过的房主判不批。 | 代码走查。这条要双开才能实测，交给回归。新开的房间表是空的，单机自检全过 |
| **rules-3 / net-3**：首领重复刷、木偶顶掉真身 | 已修 | **net**：<br>• 新增 `ex_boss_claim` / `_ex_boss_judge` / `_ex_boss_owner` / `ex_boss_release`，表 `_ex_boss_own`。<br>• 有主（主人还在房里）不批；冷却中不批；倒下、主人断线、房主回主城都划掉主人。<br>**manager**：<br>• 走近刷、按祭台召唤都先申请（`_boss_request`），批给我才刷（`net_ex_boss_owner`）；不刷就 release。<br>• 兜底：`_saw_boss` / `_adopt_boss` 撞车时一律编号小的留（不管打没打起来）。编号大的那边收掉真身、不掉东西；编号小的那边不建对方的木偶。<br>• `_my_mobs` 首领排最前；`net_mob_apply` 首领木偶不受「一批 3 个」限制。<br>• `_mob_gone` 不再把我自己的真首领清掉。 | 单机自检首领现身 / 召唤 / 击杀 PASS。联机仲裁要双开，交给回归 |
| **rules-4**：背包里的法宝死了不掉 | 已修 | **ex_data**：`death_drops` 背包里 kind == chip 的也挪进掉落。中途关游戏结算 `_recover_live` 用的是同一个函数，自动跟着改了 | 自检「死亡掉落：…法宝（装备栏 + 背包里的）」PASS：法宝 2 = 1 + 1；「存档：end_raid(false)」装备栏和背包都没有法宝 |
| **rules-6 / net-9 / combat-5**：挡下 / 闪开 / 招架的也扣护体、磨法宝、打断读条 | 已修 | **manager**：<br>• `to_player_from` 只算法衣减伤和首领封顶（meta `hit_cap`），不扣护体、不记挨打。<br>• 新增 `_settle_hits`：每帧开头按「上一帧以来实际掉的血」扣护体并补回气血、判挨打。格挡只掉一成半就只扣一成半，没掉血的不扣也不打断。顺带 AI 修士的出手也吃护体了（E 报告 8.4）。<br>• 「整下落实就致命」的那一下先预扣刚好保命的护体（`_pre_absorb`），没落实下一帧还回去。<br>• `net_take_hit` 真人这一下先过受击结算，再按实掉的血扣护体、磨法宝（每点实伤 10 耐久）、记击杀者、记挨打；没落实的部分还回连击余量（`_pvp_refund`）。<br>**ex_boss**：<br>• `_late_setup` 写 meta `hit_cap`。<br>• `_hit` 在御剑 / 俯冲中直接不结算（不先过换算）。 | 自检新增 PASS：<br>• 「没落实的一下：不扣护体、不断读条」：护体 10 → 10，读条还在。<br>• 「落实的一下」：挨 9.8，护体 10 → 0.2，气血不变，读条断。<br>原有的「真人伤害：封顶 / 法衣 / 护体 / 耐久」仍 PASS（15.1 / 500 → 347），「挨打打断读条」也 PASS |
| **rules-7**：撤离区里不能服药 / 救人 | 已修 | **manager**：新增 `_yield_extract`。服药、开箱（b）、开门（k）、救人（r）前先收掉撤离读条，用完再接着撤离。已经有别的读条时服药会给提示 | 自检新增「撤离区里也能服药」PASS：撤离读条 → 服药读条，气血 50 → 100，人还在局里 |
| **rules-8 / net-4 / net-7**：天工师归属卡死 | 已修 | **net**：<br>• 天工师的申请 / 状态 / 判决都带昼夜周期号（`ex_doc_claim(pos, cyc)`、`ex_doc_state(…, cyc)`、`_ex_doc_owner(…, cyc)`）。<br>• 房主只拿同一周期的记录挡人；被拒的人收到「谁带着」或「已救走」。<br>• 持有者断线：`_ex_peer_gone` 改成没人带着，并广播出去。<br>**manager**：<br>• 入夜消失时，持有者先发「放手」。<br>• `net_ex_doc_owner(…, cyc)` 不认别的周期的记录；持有者不在房里就当没人带着。<br>• `_tick_doctor` 发现持有者不在名单上就本机放手，营救卡片回来。 | 单机自检天工师营救 / 跟随 / 失散 / 再救回来全 PASS（研究所）。联机交给回归 |
| **rules-9 / econ-3**：丢给队友后立刻关游戏，东西翻倍 | 已修 | **manager**：<br>• `ui_drop` 先 `_sync_now()`（马上写局内锁）再落地。<br>• 新增 `_notification`：关窗口 / 手机返回键时写一次局内锁。 | 代码走查；自检「局内锁同步」PASS |
| **rules-11**：被队友救起后自救读条继续，白扣强心丹 | 已修 | **manager**：`_rise` 收掉自救读条；`_channel_done` 的自救分支先看还倒着没有 | 自检新增「队友救起后自救读条收掉、强心丹不白扣」PASS（3 → 3） |
| **rules-12**：批下来时已结算，东西凭空没了 | 已修 | **manager**：`net_granted` 里是我的、但人已经撤离 / 陨落，就在原地重新掉一份共享的（箱子还是箱子） | 代码走查（要双开） |
| **rules-13**：自己的符 / 道友在首领战斗区外也能打 | 已修 | **manager**：<br>• `_area_damage`（火符的每秒伤害也走这里）对我名下的首领先问 `accept_hit(我的位置)`。<br>• `_ally_prey`：站在区外的道友不去打首领 | 代码走查 |
| **rules-14**：两人同时开门各扣一把钥匙 | 已修 | **net**：新增 `ex_door_claim` / `_ex_door_judge` / `_ex_door_res`，房主先占上「开着」。<br>**manager**：`_door_read` 联机时先申请，批了 `net_ex_door_res` 才扣钥匙开门；批了却开不成就撤掉 | 单机自检钥匙房开门 PASS（钥匙 1 → 0）。联机交给回归 |
| **net-5**：苍鸿剑气画面在新图里别人看不见 | 已修 | **net**：<br>• `_ready` 里 meta "net" 只在没有（或已失效）时设，先建的大世界联机占着。<br>• `enter_world` 接过去（`_meta_take`），`leave_world` / 退出场景树还回去（`_meta_back`）。<br>• 擂台进世界时临时归擂台那份。 | 全项目 `--headless --quit` 无报错。实际画面交给回归双开 |
| **net-8**：中途加入时看见已被捡走的「鬼」掉落 | 已修 | **net**：<br>• `_claim_on_host`：已判过的再来申请，只回给他 `_granted(nid, -1)`，他那边收掉。老大世界走同一条路，只影响这种鬼掉落，正常拾取不变。<br>• `_ex_sync` 带上房主现有的掉落，补上载入那几秒漏掉的。<br>**manager**：3 秒没回话，卡片放回来 | 代码走查 |
| **net-10**：击杀数虚高 / 首领记两次 | 已修 | **net**：`_mob_dead` 如果 raid 有 `net_ex_mob_dead` 就把最后出手人传过去；老大世界照旧调 `net_mob_died`。<br>**manager**：新增 `net_ex_mob_dead` / `_mob_gone`，只有最后一下是我打的才 +1；首领只由 `ex_boss_dead` 记一次 | 自检新增「回放：别人打死的怪不记我的击杀」PASS；「首领木偶 / 画面 / 斩杀」加了「击杀 +1（只记一次）」PASS |
| **net-11**：房主重进留着的房间，英雄 / 境界没更新 | 已修 | **net**：`enter_world` 重新入队时一并写 hero / realm | 代码走查 |
| **net-12**：中途加入的人那边刷怪点提前复活 | 已修 | **net**：<br>• 房主记刷怪点死亡时刻（`_ex_log_camp`，`send_mob_dead` / `_mob_dead` 里 lair ≤ −2 的），留 160 秒。<br>• 随 `_ex_sync` 的 extra 发出去，`ex_local_sync` 也带。<br>**manager**：`net_ex_sync` 里调 `camps.on_dead(…, 房间时刻)` | 代码走查 |
| **net-13**：觉醒提前结束，别人那边描边还亮 14 秒 | 已修 | **net**：`_state` 记每个人状态包的位 5（觉醒中）。看到从有到无，就把那个木偶的 `_awake_fx.left` 设成 0，按原来的渐隐收掉 | 代码走查。没改 remote_player / awaken_fx |
| **econ-5**：载入中崩了按陨落结算 | 已修 | **manager**：`_ready` 只拷一份存档背包 / 装备，不写局内锁；开局那一帧（`_start`）才 `begin_raid` + `sync_live`。开局前房间散了 / 断了走 `_abort_load`：什么都不结算，直接回主城（`_exit_level` 在主控还在切场景时会等它切完） | 自检「进图」「局内锁同步」PASS。没改 ex_profile.gd |
| **econ-6**：房主关房成了救命按钮 | 部分 | **manager**：`room_collapsed` 时如果重伤倒地，按陨落结算（cause dead，房间都没了，不留遗物箱）。<br>「房主在主城关房，任何人都算平安撤离」照 SPEC 4.6 保留，要不要改请主控 / 策划定（见第 2 节） | 自检「结算只认一次」PASS：结算后再调 room_collapsed / room_lost / _die / _extract_done，存档不动 |
| **uxperf-4**：箱子 MultiMesh 每份都装全图 | 已修 | **manager**：<br>• `_setup_boxes`：按类分，每类开 / 关两份各自紧排（`visible_instance_count`），每只箱子只画一次；不再挪到地下 5000 米。<br>• 换状态只记脏，帧末统一重排（`_flush_boxes`）。<br>• `_box_mesh` 加 `st.index()`。 | 自检开箱 / 钥匙房 / 180 秒复原全 PASS。估算见第 4 节 |
| **uxperf-10**：新的大字号字形缓存 | 部分 | **ex_boss**：`countdown_label` 改成 96 / 描边 14 / 像素 0.009，和择境门、试剑台同一档，世界尺寸不变。<br>结算页标题 brush 80 在 ex_hud.gd，不归我，见第 2 节 | 代码走查 |

### 1.1 另外交代的几项（I_int §6 / E_core）

| 项 | 结果 | 改了什么 |
|---|---|---|
| (a) AI 修士 / 道友飞穿楼 | 已修 | **manager** 新增 `_clamp_foes` / `_foe_clip` / `_foe_wall`：<br>• 每帧照主角撞实心盒子的规矩把 AI 修士、AI 道友推回墙外、沿墙滑。<br>• 托住屋顶 / 楼板、夹住天花板。<br>• 只看实心盒子（楼 / 断墙），不管地形崖壁。<br>• 它们设 `process_priority = -1` 先走，管理器同一帧就能推回来，不会先画一帧穿在墙里。<br>• 卡墙超过 2.5 秒的 AI 修士换一只箱子去搜。 |
| (b) AI 修士「搜箱」只记本机 | 已修 | **manager** `_rival_search`：联机时也走 `net.ex_box_claim`（记 `_rival_claims`）。房主批下来只记开过、不出东西（`_rival_searched`）；玩家正在申请的箱子不抢 |
| (c) 首领一地掉落网页档约 160 次绘制 | 已修（手机档） | **manager**：<br>• `Drop` 同品质的法阵 / 光柱 / 轮廓材质和网格全场共用（`_cached`）。<br>• 手机档（`mobile` 或 `Vfx.lite`）每 0.25 秒（`_update_drop_lod`）：离主角最近的 8 件（18 米内）照常画；其余的藏起模型 / 法阵 / 光柱，换成两个 MultiMesh（宝石 60 米内、史诗以上的光柱 220 米内），各 1 次绘制。<br>• 掉落还是逐件、各自能捡（SPEC）；箱子 / 遗物 / 储物袋不换。<br>• 桌面档不变。 |
| (d) 手机档开局题字约 130 次绘制 | 已修 | **manager**：手机档不建 RealmBanner，开局改调 `hud.banner(图名, "限时 15 分钟")`。桌面档照旧 |
| (e) 自动拾取（gap-auto-pickup） | 已修（管理器这半） | **manager**：<br>• 新字段 `auto_pick: bool = true`，筛选 `auto_filter`：售卖物品质 ≥ 4；药 / 符 / 强心丹 / 钥匙 / 护宝符 / 法宝。<br>• 每 0.15 秒捡脚边 1.5 米内、背包放得下、合筛选的单件（`_auto_pick_tick`）。<br>• 走 `pick_up`，联机照样向房主申请。<br>• 自己丢的打 meta `no_auto`，不捡回来。<br>储物袋里的开关由 UI 修复者加（写 `mgr.auto_pick`）。 |
| (f) 沙漠夜里尸潮（gap-desert-night） | 已修（管理器这半） | **manager** `_horde`：本来就按「点表里有没有 horde」跑，不认图；这次把提示字改成按种类取名（「夜色里毒尾蝎成群涌来」），日志带上图名和种类。沙漠的 horde 条目由地图修复者往 map_def 里加，加上就生效 |

## 2. 要别的文件配合的（给回归 / 对应修复者）

1. **ex_hud.gd（UI）**：
   - **自动拾取开关**：储物袋里加一个开关，写 `mgr.auto_pick`（bool，默认 true）。筛选在 `mgr.auto_filter`（`{"sell_q": 4, "kinds": [...]}`），想做细分开关可以直接改它。
   - **结算页标题字号（uxperf-10）**：`brush()` 80 号另占一套 1024² 字形缓存。请改成和 realm_broadcast 同一档：`int(58 * k)`，或者提一个共用常量。
   - **手机开局题名**：现在调的是 `banner(title, "限时 15 分钟", 金色)`，显示 3.2 秒。U 想换样式请直接改 banner()。
2. **warmup.gd（"ex" 档预热）**：手机档新加了两个 MultiMesh 材质，第一次出现在首领掉落时，请加进预热：
   - 远处掉落的宝石：不受光 + 顶点色 + 实例色；
   - 远处掉落的光柱：不受光、加色、双面、顶点色 + 实例色。

   做法同 `_build_drop_lod`，摆一个 1 份实例的就行。
3. **main.gd / 策划（econ-6 剩下的那半）**：房主回了主城后关房（单人进门、关窗口），房里所有人都「平安送出」、带出整包。这条照 SPEC 4.6 没动。如果要收紧，有两种做法：
   - 只有站在撤离区里才算撤离成功；
   - 房主主动关房算「不结算撤回」：带进去的原样回来，新捡的和段位都不算。
4. **map_def.gd（地图）**：沙漠的 `m["horde"]` 条目照研究所的格式写（interval / r_min / r_max / n_min / n_max / kinds / cap），管理器不用再改。
5. **可选，更干净的做法**：
   - air_foe.gd 加一个 `block_fn`，替掉管理器的 `_clamp_foes`；
   - raid_mob.gd 的 `_hit_player` 在御剑 / 俯冲时别调 `atk_out`。现在调了也没有副作用，只多记一行 `_last_hit`；
   - remote_player.gd 加一个正式的 `awaken_stop()`，现在是 net.gd 直接把 `_awake_fx.left` 设成 0。

## 3. 新的汉字

没有。

`python -I _tasks/ui_kit/font_check.py`（只核对）结果：我这几个文件不缺字。自检里原来用的「筛」字已经改了措辞。仍缺的都是别人文件里原来就有的，比如 mijing_level 的①～⑯、shenshi_selftest 的 ✗、ex_level_shot 的「严」。

## 4. 验证

- **编译**：
  - `--headless --quit` 全项目无报错。
  - 5 个改过的文件，加上 arena_net / ex_level / main，`--check-only` 都过。
  - 第一次 `--quit` 报过一条 `get_meta("net", null)` 的 meta 不存在：Godot 4 的默认值是 null 时也会报，已改成先 `has_meta`。
- **整局自检（--headless）**，日志里都没有 SCRIPT ERROR：

  | 命令 | 结果 | 用时 |
  |---|---|---|
  | `-- --level-test=desert` | **失败 0 项，通过 77 项** | 94 秒 |
  | `-- --level-test=lab` | **失败 0 项，通过 80 项** | 102 秒 |
  | `-- --level-test=desert --touch`（手机画质档） | **失败 0 项，通过 78 项** | 95 秒 |

  - 新加的 11 项都过了（见第 1 节「怎么验的」）。
  - 手机档另加了一项「远处的掉落换成合批」：凌幽 17 件掉落里，7 件照常画，10 件改由 MultiMesh 画（宝石实例 9 份）。
  - 日志里唯一的 ERROR 是 grid_world.gd:910 的老材质属性警告（fog_enabled），本来就有，不是这次改出来的。
  - `shot()` 在 `--headless` 下直接跳过截图：`frame_post_draw` 不会来，原来会卡死在第一张截图上。窗口模式照旧截。
  - 整局自检进图后先关掉自动拾取（它会改件数核对），另有一步专门测。
- **没跑的**：
  - 窗口 / 双开联机：照派工交给回归。
  - `--raid-shot` / `--hub-shot` / `--arena-duel` / `--boss-test-ex`：都要截图，headless 会卡在 `frame_post_draw`。
- **老大世界 / 主城 / 擂台**：
  - net.gd 老函数只有这几处改动：`_ready` 的 meta、`enter_world` / `leave_world`、`_on_peer_disconnected` / `keep_room` 多调一个只碰 `_ex_*` 表的函数、`_state` 收觉醒描边、`_claim_on_host` 回鬼掉落、`_mob_dead` 分流（老大世界照旧走 `net_mob_died`）。
  - 老大世界的行为不变，但还是请回归跑一下上面三个命令。
- **绘制 / 图元（headless 读不到真数，按结构算）**：
  - 首领掉落 48 件，手机档：原来约 160 次（I_int 实测），每件模型 1~2 + 轮廓 + 法阵 + 光柱。现在是最近 8 件 × 约 3.3 = 约 27，加 2 个 MultiMesh，**约 29 次**。16 件（凌幽）的从约 50 降到约 29。
  - 手机开局：题字层约 130 次 → banner 2 个 Label，约 2~4 次。
  - 箱子：
    - 绘制次数不变（≤ 6 个 MultiMesh），图元大降。
    - 研究所原来常驻约 3.6 万三角形，开过三类各一只后约 7.2 万。
    - 现在每只箱子只画一次（约 95 个三角形 × 131 只 ≈ 1.2 万），顶点再少三分之一（36 → 24）。

## 5. 给回归的提醒

- **双开要测的**（单机自检测不到）：
  - 两人同时走近首领 / 同时按祭台，只出一只；
  - 房主撤离后重进留着的房间：首领冷却、门、箱子、天工师都对得上；
  - 钥匙房开着时有人中途加入，房里开过的箱子开不了；
  - 两人同时开同一扇门，只扣一把钥匙；
  - 天工师的持有者断线 / 入夜后第二天再救；
  - 苍鸿的剑气别人看得见；
  - 觉醒提前结束，别人那边描边跟着收。
- **自检 / 演示时注意测试存档会互相覆盖**：这一轮跑的时候，别的修复者也在同时跑 `--level-test=desert`（PID 12148，不是我的，没动它）。两个进程会互相覆盖测试存档 `user://xiuxian_ex_profile_selftest.json`。自检里的存档检查都是按差值算的，这次没受影响；回归最好别同时跑两个整局自检。
- **我只结束过自己起的那一个进程**：第一次跑整局自检时卡在截图上，结束的是 PID 29332 / 10540。别的 Godot 进程都没动。
