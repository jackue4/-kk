# E_core 交付报告：局内玩法管理器 / 天工师 / 整局自检（SPEC 第 4 节、第 8 节首领接入、4.10、第 9 节 E）

日期 2026-11-24。实现者 E_core。没有 commit / push。

## 0. 一句话

两张新图的整局搜打撤都跑通了：进图 → 出生无敌 → 搜箱 → 钥匙房 → 刷怪点 → 首领 → 换装 →（研究所救天工师）→ 撤离回主城；陨落分支包括重伤、自救、遗物箱和 end_raid(false)；沙漠另测了 900 秒到点陨落。
`--level-test=desert|lab` 在两档渲染器下都是 **0 项失败**：沙漠 55 项，研究所 59 项。
老大世界 `--raid-shot`、主城 `--hub-shot`、擂台 `--hub-shot --arena-duel` 都跑完了，没有新的脚本错误。

## 1. 文件清单

| 文件 | 新 / 改 | 内容 |
|---|---|---|
| `scripts/ex/extract_manager.gd` | 新（约 3500 行） | 局内玩法管理器。照 arena_duel 的先例实现 net.gd 的鸭子类型契约，并实现 CONTRACT_P2 第 1~4 节。内部类 `Drop`（地上掉落，照 raid_pickup）和 `Camps`（固定刷怪点，照 raid_camps 的状态机） |
| `scripts/ex/ex_doctor.gd` | 新 | 天工师本体：模型（强制不透明）、跟随走位、联机插值、头顶字 |
| `scripts/ex/ex_selftest.gd` | 新 | `-- --level-test=desert|lab` 整局自检 |
| `scripts/net.gd` | 改（只在末尾加一段） | 「# ---- 搜打撤（extract_manager）专用 ----」：新 RPC，见第 4 节。上面的老函数一个字没动。备份在 `_tasks/extraction_refactor/backup/net.gd.p2.txt` |

没有改别人的文件。没有新的汉字要补字库：`font_check.py` 核对后，只剩 `shenshi_selftest.gd` 里原来就有的 ✗。自检里唯一缺的「增」字我改了措辞，所以这轮没跑 `--patch` / `--import`。

## 2. 规则怎么落地（每条都对应 SPEC 第 4 节）

可调的数都是 `extract_manager.gd` 顶部的常量，见第 3 节的表。

### 2.1 进场（4.1）

- `_ready`：
  - 先调 `ExProfile.entry_check()` 兜底：不通过就 toast，2.5 秒后退回主城，不写局内锁。
  - 再调 `ExProfile.begin_raid(map_id)`，拿到局内的背包和装备栏。
  - 设 `player.regen_k = 0`、`player.lethal_fn = _lethal`，气血回满。
  - 按点表建撤离点、箱子、门、刷怪点、首领。
  - 联机时 `net.enter_world(self)`，取走 `pending_drops`；中途加入的人发 `ex_sync_req()` 向房主要局面。
  - 建 HUD：`load` 前先查 `ResourceLoader.exists`，有才建。
- **开局那一帧**：载入黑场结束、主角能动的第一帧（`player.can_process()` 且 main 不在切换中），才做下面这些。这样载入那几秒不会吃掉无敌时间。
  - `run_t` 从 0 起算。
  - `player.set_invuln(10)`。
  - 再设一次 `regen_k` / `lethal_fn`。
  - 题字：自建一个 `realm_banner.gd`（照 raid_hud 的 title 写法），写「图名 / 限时 15 分钟 / 印：禁」。
  - toast 一行装备概况。
- `NO_DROP_T`：前 5 秒 `ui_drop` 一律拒绝。

### 2.2 计时与撤离（4.2）

- **计时**：
  - 个人计时 `run_t` 按**墙上时钟**走（`Time.get_ticks_usec`，每帧最多 0.25 秒）。受击顿帧会把 `time_scale` 压到 0，用 `dt / time_scale` 算不回来，第一版读条因此被拖长过。
  - `time_left = 900 − run_t`。剩 300 / 180 / 60 / 30 秒各 toast 一次。到 0 时 `_die("timeout")`。
- **撤离点**：
  - 位置取 `level.points("extract")`，范围是点表里的 `size` 盒子。
  - 外观照 raid_manager 的 `_build_extract`：8 根石柱 + 柱间地砖（并成 1 个网格）、带辐条的法阵光（`mob_ring` 着色器）、冲天光柱（十字两片并成 1 个网格）。每座 3 次绘制，底座和法阵 320 米外不画。
  - 随时开放、没有条件、没有人数上限。
- **撤离读条**：
  - 站进撤离区自动读条 5 秒。离开、挨打、倒地、或正在别的读条，都会取消；人还在区里就从头再读。
  - 读条中每 2 秒发一次 `§x`，别人的小地图上闪一下。
  - 带着天工师时，天工师也要在撤离区里才开始读条，否则每 3 秒提示一次「天工师还没进撤离区」。
- **撤离成功** `_extract_done`：
  - 调 `ExProfile.end_raid({ok:true, bag, equip, lost_chips:false, extract_value: ExData.extract_value(bag), kills, map_id, cause:"extract", lingshi_gain, xianyu_gain})`。带着天工师时 lingshi_gain / xianyu_gain 加上 +100 万 / +20。
  - 填 `result`（见第 3.2 节），关背包。
  - 4.5 秒后发 `level.exit_requested`；界面的 `ui_result_done()` 更早，两者只认第一次。

### 2.3 箱子（4.3）

- **点表**：`level.points("box")`，沙漠 78 只（钥匙房 7），研究所 131 只（钥匙房 30）。
- **外观**：程序拼的方块箱，三类一眼能分。
  - 兵器匣：长条朱漆匣 + 三道金箍 + 金锁。
  - 物资箱：木箱 + 木条 + 四角铁护角。
  - 医疗箱：青白玉匣 + 青边 + 正面和盖上的朱红十字纹。
  - 开过的：盖子掀开、内里发暗、整体压暗。
  - 合批：按 3 类 × 开 / 关 = **6 个 MultiMesh**，全图的箱子都在里面；换状态只改那只箱子的变换，不显示的那份挪到地下 5000 米。网页档 3 次绘制；桌面档带影子 10~15 次。
  - 素材库里的箱子模型一只就是好几次绘制，几百只顶不住预算，所以没用。
- **读条**：
  - 走到 2.8 米内出「开启」卡片，点了读条 1.5 秒，挪开 1 米或挨打就断。
  - 读满后：单机直接开；联机发 `net.ex_box_claim(号)` 向房主申请。房主按自己记的开箱时刻判，先到先得，结果广播给全房。
  - 批给谁，谁就在自己那边按 `ExData.roll(ExData.box_table(map_id, kind, 钥匙房里?), rng)` 抽，每件东西从箱口蹦到周围 1.2~2.4 米的地上。落点撞墙就落近一点。
  - 掉落物走共享（`send_drop`）。
- **复原**：开箱时刻记成房间时钟，野外的箱子 180 秒后自动复原，全房按同一个钟算。钥匙房里的箱子只在**开门时**复原，否则门开着的 900 秒里能一直刷。
- **中途加入**：从房主那里拿开箱时刻。

### 2.4 钥匙房（4.4）

- **点表**：`points("key_room")`。
- **开门**：
  - 站在 `open_at` 3.4 米内出卡片。没有禁室玉钥就提示来源。
  - 读条 2 秒，读满扣 1 把钥匙，调 `level.set_door(id, true)`，房里的箱子全部复原。
  - 广播 `net.ex_door(id, true, 房间时刻, 复原的箱子号)`，房主那份开箱记录同步划掉。
- **关门**：每 0.4 秒查一次。开着满 900 秒（房间时钟），并且房间 AABB 和门洞 2.2 米内都没人（本机 + 所有木偶），就关门并广播。
  - 收到别人发来的「关门」时，如果我还在房里：立刻重新开门，按现在的时刻续上，再广播一次。不会把人关在里面。

### 2.5 怪（4.5）

- **刷怪点**：内部类 `Camps`，raid_camps.gd 的状态机近乎逐字搬过来。
  - 复活 75 秒（房间时钟），精英 ×2；被 AI 修士杀的 12 秒复活。
  - 100 米内才建，150 米外怪都闲着就收；急飞（光遁）时不建。
  - 一个点只由一个人建：编号小、离得近、没在急飞的那个人建；撞车时刚建、还没打起来的那份让出去；交接时接着用木偶的位置和血量。
  - 点上的怪死了，用 `send_mob_dead` 的 lair 字段编码成 `-2-code` 广播出去。
  - 布局取 `points("camp")`：每个点「几只、什么怪、偏移多少」用 `hash(map_id) + 7919·i` 当种子固定下来，所有人、每一局都一样。
  - 精英点：第一只是精英，其余是随从。凝胶怪由 `ExMobs.setup` 强制成精英。
  - 每个点 3~5 只（点表的 n）。同屏上限桌面 22、手机 / 网页 15；名额整片地方共用，别人名下的木偶也算进去。
- **数值**：
  - 刷怪照 B_mobs 5.1 的配方：`ExMobs.setup`、`floor_fn = level.ground`。研究所设 `block_fn = level.blocked`，木偶也设。
  - 血 / 攻是 ex_mobs 的扁平点数（沙漠 40 / 5，研究所 80 / 12，精英血 ×3、攻 ×1.5，巨汉血 ×2）。
- **掉落**：
  - 小怪 25% 抽一次 `ExData.mob_table(map_id)`，精英必抽一次。
  - 首领召唤的怪、尸潮、天工师引来的尸傀记了 `summoned`，不掉东西。尸潮按小怪掉。
- **研究所夜里**（`level.is_night()`）：
  - 每 90 秒（参数取 `points("horde")`）在本机主角 20~40 米外（`level.find_spawn_near`）刷 3~5 只尸傀，一出来就扑。
  - 尸潮上限 15，另外不超过同屏上限 + 4。
  - 每台机器只给自己的主角刷，所以「每个真人身边都有一波」。

### 2.6 首领（第 8 节，照 B_mobs 5.2~5.6）

- **点表**：`points("boss")`。
  - map_def 的 key 换算：worm → sandworm，twin → duo_hunter + duo_welder（pair）。
  - 战斗区：AABB 换成 Rect2；高度范围取 AABB 的 y 下限 −2 到上限 +4，交给 ExBoss。
- **刷出**：
  - 普通首领：本机主角走到出生点 110 米内、首领不在场，就由我刷，当主人。
  - 召唤型（沙渊巨虫 / 铁穹双卫）：站在祭台 5 米内出「召唤祭台」卡片。战斗区里的真人数要满足 `ExMobs.can_summon`，且不在冷却，才能召唤。
  - 每次刷出都发一条全房横幅「X 现身」（realm_broadcast）。
  - 血量按战斗区里的真人数缩放。双卫用 `ExBoss.link_duo` 互认。
  - 技能画面通过 `fx_out → net.ex_boss_fx` 广播出去。
- **联机**：
  - 首领木偶的批量消息里，lair = `首领号×2 + 第几只`。收方建木偶时挂 `ExBoss.attach_remote` 并认作「在场」。
  - 两人同时刷了同一只：我那份还没打起来（满血、3 秒内）而对方编号更小，我就让出去。
  - 远程玩家打我名下的首领，先问 `brain.accept_hit(他的位置)`。
- **死亡**（`_on_boss_died`，双卫要两只都死）：
  - 按 `ExBoss.drop_table / drop_draws` 抽（凌影夜里换表），用 `drop_points` 逐件撒满战斗区。
  - 击杀者 = 最后一下的出手人（我打的记在 meta `hitter`）。是我就 `ExProfile.add_xianyu(5)`；是别人，就由 `ex_boss_dead` 告诉他。
  - 全房横幅「斩 X · 谁斩杀了 X · 遗宝散落战场（N 件）」。
  - 冷却 = `ExMobs.boss_respawn`（召唤冷却 600 秒）。出生点 / 祭台上立一个 3D 倒计时字（`ExBoss.countdown_label / set_countdown`）。
- `_boss_near`：150 米内活着的首领，给音乐和界面用。

### 2.7 伤害（4.5 / 4.7）

- **主角打怪**：`player_dmg_vs(d, t) = d / player.hero_base() × 10 × ExData.atk_mult(equip, false) × dmg_k`，绑定成 `m.dmg_in`。顺手记 `dmg_ratio`，以及目标的 `hitter / hit_t`。`dmg_k` 恒为 1，只有自检能改。
- **怪打主角**：`to_player_from(d) = d × (1 − armor_dr(equip, false))`，算完先扣玄龟镜护体值，绑定成 `m.atk_out`。无敌时原样返回，不扣护体。首领在外面再包一层 35 点封顶（ExBoss 做）。
- **PvP 出手**：`net_deal_hit` 发的是 `CS.pvp_hit(raw, 境界, 境界, 0) × ExData.atk_mult(equip, true)`。英雄档下不看境界差，atk_mult 已经夹在 1.25 以内。
- **PvP 受击**（`net_take_hit`，from > 0），依次：
  1. `_pvp_clamp`：单下 22 / 余量 30 / 每秒 25，照 raid_manager。
  2. × (1 − armor_dr(equip, true))，已夹到 22%。
  3. 扣玄龟镜护体值。
  4. `ExData.wear_chips(equip, d)`：法宝耗尽就 toast 并重算加成。
  5. 记下击杀者。
  6. 照 raid_manager 走地面 / 空战的受击结算，**src 传对方的木偶**，苍鸿的招架回传要靠它。
- **别人名下的怪打我**（from = 0）：走 `to_player_from`。
- **不经过受击结算的伤害**（沙暴、火符、站在自己雷符里）：走 `_hurt_direct`。不过法衣（自己的雷符过 PvE 法衣），先扣护体；致命时先把气血清零再 `player.absorb_lethal` 转重伤；本来就在重伤里就 `die_now`。
- **回血**：没有自然回血，只有两个来源。
  - 回元佩：每秒回 `chip_fx.regen`。
  - 药：立即回 `heal`，持续回 `hot × dur`。
  - 重伤中不回。

### 2.8 背包 / 消耗品（4.8、3.5）

- 背包 30 格（`ExData.BAG_CAP`）。拾取用 `ExData.add_to`，能叠的叠上去，放不下的留在地上 / 箱里。
- 每 15 秒，以及捡到或用掉东西之后（至少隔 2 秒），调一次 `ExProfile.sync_live(bag, equip)`。
- **药**：读条 `use_t`。挪动或挨打会打断；满血且没有持续回血的不让用。
- **强心丹**：只在重伤时能用，作用同「自救」。
- **符**：投掷落点规则如下。
  - 落点：身前 14 米内、朝向夹角约 70° 以内最近的敌人；没有就丢到身前 7 米。飞 0.55 秒的弧线。
  - 雷符 / 天雷符：半径 r 内给怪 / AI 修士 / 别的真人各打 dmg 点。打别的真人走 `send_hit`，对方那边再过 PvP 封顶。自己站在里面也挨。
  - 烟遁符：8 秒的烟，只有画面。
  - 火符：半径 3 米烧 10 秒，每秒 3 点。
  - 别人那边用 `§t` 小消息画出同样的画面，不判伤害。

### 2.9 重伤 / 陨落（4.6）

- **重伤**：
  - `lethal_fn`：第一次致命伤返回 true，player 自己转重伤；重伤中再挨致命伤返回 false，照常陨落。
  - 收到 `player_downed`：`downed = true`，`downed_left = 20`（真实秒），收掉读条和背包，toast。流光流完调 `player.die_now()`。
  - 自救：`ui_self_revive` 读条 3 秒，只怕挨打。倒地时人会被击退滑一段，所以不按挪动打断。读满扣一颗强心丹，起身、气血回满。
  - 救队友：别人的木偶 `hero_downed()` 为真、是队友、在 3 米内，就出「救起 X」卡片。读条 3 秒，挪开 1 米或对方离开 4 米就断。读满扣我的一颗，发 `net.ex_revive(对方)`，对方起身回满。
  - 自尽：`ui_suicide` 直接调 `player.die_now()`。
  - 收到 `player_dead` 时**先看 `player.dead`**（H 第八节）。
- **陨落** `_die(cause)`：
  1. 灵石够（`ExProfile.death_tag_ok`，≥ 5000）就掉命牌（`ExData.make_tag(名字)`）。
  2. `ExData.death_drops(bag, equip, rng, map.death_drop_stacks)`：随机掉 2 堆售卖物（护宝符先保住价值最高的 2 堆），法宝全掉。
  3. 掉的东西 + 命牌变成一只共享的「X 的遗物」箱，留在死亡点的地面上，联机全房可抢。
  4. 如果是被真人打死的（12 秒内挨过他的打），用 `§k` 告诉他，他那边记一次真人击杀。
  5. 调 `end_raid({ok:false, …, lost_chips:true, cause: dead / timeout})`。5000 灵石由 end_raid 扣。
  6. `result.lost` = 掉落堆 + 法宝 + 命牌。
- **房主关房**（`room_collapsed`）：照撤离成功算，cause 写 `room_collapsed`。
- **自己掉线**（`room_lost`）：照陨落算，**没有遗物箱**，cause 写 `room_lost`。

### 2.10 AI 修士 / AI 道友（4.7）

- **AI 修士**（`air_foe`）：
  - 只在房里只有一个真人时出现（`net.in_world_count() ≤ 1`）。
  - 一局最多 3 个，其中 1 个红名，开局 4 秒后起，每隔 6~14 秒在 90~150 米外刷一个，死了不补。
  - 照 raid_manager 的 `spawn_rival` 写，数值换成扁平点数。
  - 会找怪打（`_prey_for`）。也会「搜箱」：闲着时把它的 `_roam_to` 指向 70 米内最近没开过的野外箱子，到了停 2 秒，箱子记成开过，不出东西。
  - 红名的开局 30 秒后才可能动手，同时最多 2 个围上来。
  - 死了掉「X 的储物袋」 = `ExData.roll(box_table(map,"supply"), rng, 2)`。
- **AI 道友**：组队人数比真人多时补位，照 raid_manager 的 ally_team 那套，气血 / 打怪伤害改成常量，联机木偶照旧。

### 2.11 昼夜、边界、小地图

- **昼夜**：读 `level.is_night()`。凌影夜里换形态由 ExBoss 自己做（传了 `night_fn` / `room_n_fn`）。天工师入夜消失。
- **边界**：实现了 `env_damage(points, kind)`，沙暴每秒 3 点，走 `_hurt_direct`（不过法衣、先扣护体、致命转重伤）。
- **小地图**：U 的 HUD 自己建 minimap，把 mgr 交给它。我这边给它读的字段：
  - `_pickups`：Drop 有 `tier()` 0..4 和 `is_chest()`，遗物箱 / 储物袋显示成带白边的方块。
  - `_mobs / _puppets / _bosses`：`{state 0 未刷 / 1 在场 / 2 冷却, pos, node}`。
  - `_rivals / _allies / pings`：`§x` 撤离用种类 0；天工师每 0.45 秒刷一个种类 2（紫色），出了范围贴边指方向，所以「全图可见」。
  - `net_on() / ex_col()`。

### 2.12 天工师（4.10，`ex_doctor.gd` + 管理器「天工师」一节）

- **出现条件**：
  - 白天第 180~300 秒里的某一刻。具体是哪一刻，用房间种子和昼夜周期号在窗口里挑，全房一样。
  - 房间真人数 ≥ `DOCTOR_MIN`（1）。
  - 这一个周期里还没刷过、没被救走。
  - 位置是 `points("doctor")`（天工楼二层）。
  - 入夜消失；持有者那边会失去归属。
- **营救**：走到 4 米内出卡片。单机直接归我；联机发 `ex_doc_claim` 由房主判，先到先得。
- **跟随**（ExDoctor）：
  - 保持 3 米，离持有者超过 10 米就停下。
  - 移速 5.8 米/秒 = 主角地面跑速 7.2 × 0.8。
  - 每一步问 `level.blocked`，撞墙就只走 X 或只走 Z；高度贴 `level.floor_at`，能跟着上下楼梯。
- **距离规则**（管理器判）：
  - 10~15 米：`doctor_state = "far"`，toast 警告。
  - 超过 15 米持续 5 秒：失去归属，天工师原地等人，`doctor_state = "lost"`（3 秒后清空）。
  - 持有者陨落也失去归属。
- **带着时**：每 5 秒在持有者 14~24 米外刷一只尸傀（不掉东西）。
- **撤离**：两人都在区里才读条。成功时 +100 万灵石、+20 仙玉（end_raid 的 lingshi_gain / xianyu_gain），并广播「已救走」，全房这一周期不再出现。
- **模型**：`doctor.glb`。所有材质换成不透明的副本：`transparency = DISABLED`、alpha 设 1。模型缺失时退回白大褂方块人。
- **联机**：持有者那台机器模拟位置，每秒 3 次 `ex_doc_pos`（不可靠）；别人那边插值。

## 3. 公开接口（照实现写）

### 3.1 字段

| 用途 | 字段 |
|---|---|
| net.gd 契约 | `lv := 1`、`_in_trib := false`、`_trib = null`、`level`、`running` |
| CONTRACT 第 1 节 | `time_left: float`、`bag: Array`、`equip: Dictionary`、`channel: Dictionary`（`{}` 或 `{label, t, total}`）、`cards: Array`、`downed`、`downed_left`、`can_self_revive`、`kills`、`pk_kills`、`doctor_state`、`result` |
| 音乐 / 道友大脑 / 预热 / 小地图 | `extract_k`、`extract_kind`、`search_k`（开箱读条比例）、`region := 0`、`at_sea := false`、`dmg_ratio`、`pings`、`_mobs`、`_pickups`、`_puppets`、`_bosses`、`_rivals`、`_allies`、`_boss_near`、`ally_team`、`hud`、`player`、`cam`、`net`、`font`、`mobile`、`map_id` |
| 自检用 | `stat`（boxes / doors / camp_kills / boss_kills / horde / doc_zombies / pvp_out / pvp_in）、`camps`、`doctor`、`dmg_k`、`cap_override`、`run_t` |

### 3.2 CONTRACT 第 2~4 节

- **方法**（全部实现）：
  - `ui_card(key)`：只认身边现在列出来的那几张卡（调用时先刷新一次）。
  - `ui_use(i)`、`ui_wear(i)`、`ui_unequip(slot, idx)`、`ui_drop(i, n := -1)`、`ui_self_revive()`、`ui_suicide()`、`ui_result_done()`、`carry_value()`。
- **卡片**：每张 `{key, kind, title, item, hint}`，kind 与 key 的对应：

  | kind | key | 说明 |
  |---|---|---|
  | item | `d:<实例号>` | 地上单件 |
  | chest | `d:<实例号>` | 箱子整个拿；`item` = 箱里品质最高的那件，`title` = 「X 的遗物（N 件）」 |
  | box | `b:<箱子号>` | 开箱 |
  | box（召唤祭台） | `a:<首领号>` | 契约里没有「祭台」这一种，借用 box，标题「召唤祭台 · X」 |
  | door | `k:<门号>` | 开钥匙房的门 |
  | doctor | `doc` | 营救天工师 |
  | revive | `r:<玩家号>` | 救队友 |

- **result**：
  ```
  {ok, cause: extract | dead | timeout | room_lost | room_collapsed, map_id, alive_sec, kills, pk_kills, value,
   lingshi_delta, xianyu_delta, new_items, lost, rank_up, doctor}
  ```
  - lingshi_delta / xianyu_delta = 结算后存档里的数 − 进图时的数，含击杀首领的仙玉。
  - 陨落时多一个 `ward: bool`（护宝符生效了没有）。
- **推送**：`hud.toast(text, col)` / `hud.close_bag()` / `hud.flash_hit()`，每个都先问 `has_method`。

### 3.3 其他公开方法

- 箱子 / 门 / 撤离：`box_open(idx)`、`door_is_open(id)`、`extract_at(p)`、`nearest_extract()`
- 时钟 / 身份：`world_t()`（= `level.room_time()`）、`net_on()`、`my_name()`
- 伤害：`env_damage(points, kind)`、`player_dmg_vs(d, t)`、`to_player_from(d, t)`、`shell_left()`
- 其他：`mob_cap()`、`ping(pos, kind, secs)`、`pick_up(pk)`、`pick_nearest()`、`spawn_rival(pos, hostile)`、`doctor_warp()`（自检用）
- 给 warmup.gd 的兼容：`_spawn_mob(老种类编号, …)` 把编号换成本图的种类；`_drop_item / _drop_chest` 认老物品的 `tier`。

### 3.4 net.gd 契约（照 raid_manager / arena_duel）

- 怪：`net_mob_batch`、`net_mob_apply`、`net_find_mob`、`net_mob_take`、`net_mob_attack`、`net_mob_died`
- 掉落：`net_drop`、`net_drop_list`、`net_granted`
- 真人受击：`net_take_hit`、`net_deal_hit`
- 其他：`net_announce`、`net_trib`（空）、`net_ally_batch`、`net_ally_apply`、`room_collapsed`、`room_lost`
- 怪的批量消息每条 11 项：`[编号, ExMobs.idx 种类, 0, 1, 精英, 位置, 朝向, 血量比例, 状态, 首领 lair（号×2+第几只）/-1, 刷怪点 code/-1]`

### 3.5 ex_doctor.gd

- 常量：`FOLLOW_KEEP 3`、`STOP_R 10`、`SPEED 5.8`、`HEIGHT 1.9`
- 字段：`floor_fn`、`block_fn`、`font`、`remote`、`target`、`mode_i`（0 等人 / 1 跟着 / 2 太远停下）、`moved`
- 方法：`follow(n)`、`push(pos, yaw, mode)`、`vanish()`、`snap_floor()`、`center()`

## 4. 联机协议（net.gd 末尾那一段）

每条 RPC 收到后都先问 `raid.has_method`，所以老大世界的 raid_manager 和擂台的 arena_duel 收到了也什么都不做。
房主那几张表按 `seed_v` 识别是哪一间房，换房就清空。房主回了主城、房间还开着时，也能从这几张表回中途加入的人。

| 发送函数 | RPC | 方向 / 可靠性 | 收方转给 |
|---|---|---|---|
| `ex_box_claim(号)` | `_ex_box_claim` → 房主判 → `_ex_box(号, 谁, 时刻)` | 申请发房主；结果全房，含房主；被拒的只回申请人（谁 = 0）；可靠 | `net_ex_box(idx, by, t)` |
| `ex_door(门号, 开?, 时刻, 复原箱子号)` | `_ex_door` | 全房，可靠；房主记一份 | `net_ex_door(from, id, open, t, refill)` |
| `ex_boss_dead(首领号, 时刻, 击杀者)` | `_ex_boss_dead` | 全房，可靠；房主记一份 | `net_ex_boss_dead(from, idx, t, killer)` |
| `ex_boss_fx(怪编号, 种类, 参数)` | `_ex_boss_fx` | 全房，可靠（B_mobs 5.4） | `net_ex_boss_fx(from, nid, kind, params)` |
| `ex_revive(对方)` | `_ex_revive` | 点对点，可靠 | `net_ex_revive(from)` |
| `ex_doc_claim(位置)` | → 房主判 → `_ex_doc_owner(谁, 2, 位置)` | 申请发房主；结果全房 | `net_ex_doc_owner(holder, state, pos)` |
| `ex_doc_state(谁, 状态, 位置)` | `_ex_doc_state` | 全房，可靠；状态 1 等人 / 2 跟着 / 3 已救走 | `net_ex_doc_owner` |
| `ex_doc_pos(位置, 朝向, 模式)` | `_ex_doc_pos` | 全房，不可靠、有序，每秒 3 次 | `net_ex_doc_pos(from, …)` |
| `ex_sync_req()` | → 房主 `_ex_sync(箱子, 门, 首领, 天工师)` | 中途加入 | `net_ex_sync(boxes, doors, bosses, doc)` |

- 撤离 ping `§x`、真人击杀告知 `§k`、符的画面 `§t` 借现有的 `send_announce` 小消息，没有新加 RPC。
- 遗物箱 / 储物袋 / 首领掉落走现有的 `send_drop` + `_claim` 拾取申请。
- `EX_BOX_CD = 180` 在 net.gd 里另写了一份，必须和 `BOX_CD` 保持一致。
- **协议变了，局域网里所有人都要换包。**

## 5. 自检

命令（在 `D:\GodotProjects\修仙游戏` 下）：

```
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/E_desert8 --resolution 1280x720 -- --level-test=desert
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/E_desert_gl5 --resolution 1280x720 --rendering-method gl_compatibility -- --level-test=desert --touch
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/E_lab4 --resolution 1280x720 -- --level-test=lab
python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/E_lab_gl5 --resolution 1280x720 --rendering-method gl_compatibility -- --level-test=lab --touch
```

### 5.1 结果

| 配置 | 结果 | 用时 | 脚本错误 |
|---|---|---|---|
| 沙漠 · Forward+ | 55 / 55 通过 | 77 秒 | 0 |
| 沙漠 · 兼容 + 触屏 | 55 / 55 通过 | 80 秒 | 0 |
| 研究所 · Forward+ | 59 / 59 通过 | 89 秒 | 0 |
| 研究所 · 兼容 + 触屏 | 59 / 59 通过 | 88 秒 | 0 |

stderr 里只有原来就有的兼容渲染器 / Godot 3 材质警告。兼容 + 触屏这一档会自动开 warmup，所以 warmup 走我的 `_spawn_mob` / `_drop_item` 兼容路径也一起验过了。

### 5.2 测了什么（每步一行 `[ex] 名字 PASS/FAIL · 细节`，最后 `[ex] 总计 失败 N 项`）

**第一遍：撤离**

- 进图、HUD 在：两个都 true。
- 出生无敌：剩 9.8 秒；挨 40 点之后气血仍 100。
- 前 5 秒不能丢。
- `regen_k = 0`，`lethal_fn` 已设。
- 绘制调用分账（见 5.3）。
- 开箱：兵器匣 / 物资箱 / 医疗箱各开一只，每件捡起来；保证背包里有捡来的装备和售卖物。
- 钥匙房：给一枚禁室玉钥 → 读条 2 秒开门 → 钥匙 1 → 0、门开了 → 开房里的箱子、捡东西（钥匙房的表） → 门开着时不再出卡片。
  - 沙漠用洞窟里的 k11，研究所用 K1 坑。
- 刷怪点：
  - 怪建出来（3 只，0.4 秒）。
  - 雷符命中：怪的总血 240 → 174。
  - 逐只打死：击杀 +3，点上记死 3。
  - 开箱读条挨一下被打断。
  - 服药：止血草读条 2 秒，回血，剩 9 颗。
- 联机消息回放（单进程里直接喂处理函数，见 5.4）。
- AI 修士：在场 3 个（含 1 个红名）→ 打倒 → 掉「X 的储物袋」2 件 → 整个拿走。
- 沙暴伤害走管理器：100 → 97。
- 箱子 180 秒复原：把房间时钟拨 181 秒后可再开。
- 局内锁同步：存档锁里的格数 = 局内背包格数。
- 首领：
  - 沙漠：凌幽，走近就现身。
  - 研究所：从祭台召唤铁穹双卫（猎杀卫 + 焊愈卫各 5600 血），技能在放。
  - 站在战斗区里打死；状态变成冷却。
  - 掉落：凌幽 16 件（superBossDrops），双卫 48 件（lvBuDiaoChanBossDrop）。
  - 仙玉 +5。
- 穿上捡到的兵刃：出手 ×1.20~1.45。
- 研究所营救天工师：
  - 拨钟到刷新时刻 → 现身。
  - 营救后归属给我，状态 follow。
  - 走开 7 米，他跟着走了 4 米、停在离我 3 米处。
  - 走开 26 米：1 秒时 far，6 秒时 lost，归属清空。
  - 再救回来。
- 撤离：读条进行中（截图），撤离成功。研究所的结果：营救天工师撤离，灵石 +1,000,000、仙玉 +175（+5 首领、+20 天工师、+150 段位晋升三档）。
- 回主城：存档背包里有售卖物，累计带出价值 = 原来 + 本局，段位晋升（沙漠到炼气三阶，研究所到炼气一阶）。

**第二遍：陨落**

- 入场检查拦下售卖物（第一遍带回来的）→ 存进仓库后再进。
- 塞 3 堆售卖物 + 回元佩 + 强心丹。
- 真人伤害：挨 30 → 封顶 22 × (1 − 8%) − 护体 5 = 15.2，实掉 15.1；回元佩耐久 500 → 347。
- 致命伤（走受击结算）转重伤：剩 19.6 秒，气血 1。
- 强心丹自救：起身，气血 100，强心丹 3 → 2。
- 研究所：入夜，尸潮刷了 5 只。
- 再次重伤 → 沙漠：重伤中再挨一下；研究所：自尽 → 陨落。
- 掉 4 件：售卖物 2 + 法宝 1 + 命牌 1。遗物箱 4 件。
- 存档：陨落 +1，灵石 −5000，法宝槽清空，剩下的 1 堆售卖物回到背包。

**第三遍（沙漠）：到点没撤**

- 剩 31 秒时已提示 3 次 → 到点陨落，cause timeout，掉 2 件（1 堆售卖物 + 命牌）。

### 5.3 绘制调用 / 性能（预算：绘制 ≤ 220、图元 ≤ 220k，网页档）

出生点分账：逐样东西藏起来，看少了多少次绘制。

| 项 | 沙漠 · 兼容 + 触屏 | 研究所 · 兼容 + 触屏 | 桌面档 |
|---|---|---|---|
| 总计 | 225 | 278 | 230~281 |
| 关卡 / 主角 / 触屏层 / 其他 | 98 | 141 | — |
| **箱子** | **3** | **3** | 11~15（带影子） |
| **撤离点** | **6** | **6** | — |
| 怪 | 1 | 3 | — |
| 界面（ex_hud，U 的） | 49 | 57 | — |
| 开局题字（RealmBanner，前 5 秒） | 68 | 68 | — |

- 我这边常驻的只有箱子 3 次 + 撤离点 6 次，其余是怪和掉落。
- 超预算的主要是界面（49~57）和开局题字（约 68，只在开局 5 秒左右）。
- 掉落一多就贵：双卫的 48 件撒满场地时，网页档 423 次绘制。已经压过一轮——
  - 轮廓泛光那一遍只给史诗以上；
  - 法阵光只给传奇以上；
  - 光柱只给史诗以上；
  - 模型 50 米外、法阵光 60 米外不画。

  凌幽 16 件时是 246 次。

网页档每张截图（绘制 / 图元）：

| 图 | 出生 | 开箱 | 钥匙房 | 刷怪点 | 首领 | 首领掉落 | 天工师 | 撤离 | 结算页 | 重伤 | 尸潮 | 遗物 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 沙漠 | 234 / 146k | 142 / 135k | 153 / 96k | 224 / 215k | 209 / 193k | 246 / 205k | — | 167 / 162k | 238 / 162k | 370 / 143k | — | 222 / 136k |
| 研究所 | 287 / 202k | 305 / 177k | 178 / 197k | 211 / 212k | 241 / 245k | 423 / 258k | 282 / 193k | 341 / 287k | 410 / 284k | 425 / 200k | 213 / 197k | 250 / 199k |

结算页、重伤这两张高，是界面的全屏面板和主城的段位题字叠在一起。

### 5.4 联机

**没有做真的双开联机测试。** 原因：net.gd 的端口和发现端口是写死的（24680 / 24681），没有自检用的端口隔离；开房后会在局域网里广播房间，可能被正在玩的同事匹配进来（记忆：自动化联机测试别打扰正在玩的人）。另外按派工，我不能改 net.gd 的老函数。

改成「协议回放」：在单进程里直接调新 RPC 转过来的那些处理函数，第一遍里 7 项全过。

| 回放的消息 | 验证了什么 |
|---|---|
| 别人开了箱子 | 我这边记开过、不出东西 |
| 共享掉落出现 → 房主判给别人 | 地上出现，随后收掉 |
| 别人名下的小怪木偶 | 半血木偶建出来；他那边死了，木偶收掉、我补的刀记击杀 |
| 首领木偶 + 技能画面 + 斩杀告知（我是击杀者） | 木偶挂上 ExBoss、认作在场；倒下后状态 2，仙玉 +5 |
| 别人开门 / 关门 | 门跟着开、关 |
| 中途加入同步 | 箱子按房主给的时刻记开过 |
| `§k` 真人击杀告知 | pk_kills +1 |

**建议主控**整合时用两台机器（或给 net.gd 加一个自检端口偏移），实测四件事：开箱抢同一只箱子、开钥匙房、救队友、营救天工师的归属交接。

### 5.5 老功能回归

| 命令 | 结果 |
|---|---|
| `-- --hub-shot`（日志 `E_hub_*`） | 跑完，0 个脚本错误；门 / 擂台 / 试剑台 / 木兰草原进出都正常 |
| `-- --hub-shot --arena-duel`（日志 `E_arena_*`） | 跑完，6 场 AI 陪练 胜 2 负 4，0 个脚本错误 |
| `-- --raid-shot`（日志 `E_raidshot_*`） | 跑完：26 张截图，撤离成功，回到大厅 = true，0 个脚本错误 |
| `--headless --quit` | 只有退出时主城背景音乐流的引用泄漏（audio_director，不是我的） |
| `--check-only` 三个新文件 + net.gd | 全过 |

## 6. 截图（只看 preview 的 jpg）

`_shots/preview/` 下，桌面档无后缀，兼容 + 触屏加 `_gl`：

- 沙漠：`ex_desert_{spawn, box, keyroom, camp, boss, boss_loot, extract, result, downed, relic}[_gl].jpg`
- 研究所：`ex_lab_{spawn, box, keyroom, camp, boss, boss_loot, doctor, extract, result, downed, horde, relic}[_gl].jpg`

值得看的几张：
- `ex_desert_box_gl`：开过的兵器匣。
- `ex_lab_extract_gl`：撤离点的石柱 + 法阵 + 光柱，天工师跟在身边。
- `ex_lab_doctor_gl`：天工师模型不透明、头顶「随行」。
- `ex_lab_boss_loot_gl`：斩铁穹双卫的全房横幅，掉落撒满斗场。
- `ex_desert_relic_gl`：结算页「身死道消」，丢失 4 件。
- `ex_desert_downed_gl`：重伤面板（自救 / 自尽）。

## 7. 和 SPEC / CONTRACT 不一样的地方，以及原因

1. **箱子用程序拼的方块，没用素材库模型**：一只模型就是好几次绘制，研究所 131 只顶不住 220 的预算。合批成 6 个 MultiMesh 之后，网页档一共 3 次绘制。三类箱子的颜色和造型差别很大（见 2.3）。
2. **钥匙房里的箱子只在开门时复原**（不按 180 秒）：否则门开着的 900 秒里，同一间房能一直刷。SPEC 只写了「开门 → 房内箱子复原」。
3. **召唤祭台的卡片 kind 用 "box"**：CONTRACT 的 kind 列表里没有「祭台」。key 是 `a:<首领号>`，标题写「召唤祭台 · X」。
4. **遗物箱 / 储物袋整个拿**（kind "chest"）：拿不下的留在箱里。联机时共享掉落本来就要整箱向房主申请（照 raid_manager）。
5. **读条和个人计时按墙上时钟**：受击顿帧会把 `time_scale` 压到 0，按游戏时间算读条会被拖长（实测自救 3 秒读成 2.9 / 3.0 就被判没读满）。
6. **自救读条只怕挨打、不怕挪动**：倒地时人会被击退滑一段。SPEC 原文只写了「挨打打断」。
7. **手机 / 网页的同屏怪上限是 15**（老大世界是 20）：记忆 raid-ai-tuning 里写的是 22 / 15；研究所网页档的预算本来就紧。
8. **AI 修士一局总数 3 个、红名 1 个、死了不补**：SPEC 写的是「每张图 2~3 个」。另外：气血 220 点、打主角 ×0.8 ×(1 − 法衣 PvP)、打怪一下 7 点。
9. **天工师在窗口里的哪一刻出现**：由房间种子 + 周期号决定，全房一致、不用发消息。移速取 5.8（主角地面跑速 7.2 × 0.8）。
10. **首领现身也发全房横幅**：SPEC 写「重生 / 击杀全房播报」。第一个人走近时刷出，横幅比较大，嫌吵可以改成 toast。
11. **玄龟镜护体只在进图时给**：SPEC 写「进图时加一层护体值」。局内新穿上的玄龟镜不加护体，回元佩 / 破军印照常生效。
12. **result 多了一个 `ward` 字段**（陨落时护宝符生效了没有），界面可以不读。
13. **room_collapsed 的 cause 写 "room_collapsed"**，但 end_raid 里记 "extract"；room_lost 记 "dead"。end_raid 只认这几种 cause。

## 8. 已知问题 / 没做的

1. **没有实测真双开联机**：原因和替代测法见 5.4。
2. **绘制调用**：
   - 研究所出生点网页档 278（界面 57 + 开局题字 68 + 关卡 141）。
   - 双卫掉落撒满斗场时 423。
   - 我这边常驻的只有 9 次；要压，主要看界面和题字。也可以把首领掉落合成几堆再撒，但 SPEC 写的是逐件撒。
3. **AI 修士在研究所会飞穿楼**：air_foe 没有 block_fn。
4. **护体只挡我这条伤害路径上的伤害**：怪、首领、真人、沙暴、符都先扣玄龟镜；AI 修士的出手直接进 receive_attack，不经过我，不扣护体。
5. **首领单下 35 点封顶的顺序**：ExBoss 在我的 `to_player_from` 外面封顶，所以护体按封顶前的值扣（差很少）。
6. **烟遁符只有画面**：不挡索敌，也不挡神识。
7. **到点陨落时主角不倒下**：怪定住、结算页亮出来，4.5 秒后回主城。如果调 die_now，main 会抢着 1.3 秒就回主城，和结算页冲突。
8. **hud.gd（D）的段位题字会带进新图**：撤离回主城时如果段位晋升了，紧接着再进图，主城那条「段位晋升」题字会在新图里亮出来，见 `ex_desert_downed_gl.jpg` 右侧。是 `_ex_rank_banner` 的时机问题，请 D / 主控看一下。
9. **还没进 warmup 预热的材质**（请主控在 warmup 的 "ex" 那一档加）：
   - 撤离点光柱：加色、不受光、双面、关雾；
   - 投出去的符：不受光；
   - 烟遁符的粒子：透明、粒子朝向镜头；
   - 箱子：顶点色、MultiMesh。

   法阵光（mob_ring）、轮廓泛光（creature_overlay）已经预热过。
10. **自检用的钩子**：
    - `dmg_k`、`cap_override`；
    - 关卡的 `clock_off`；
    - 直接改 `run_t` / `_horde_t` / `_shell`；
    - 开箱 / 开门 / 服药时临时 `set_invuln`，免得路过的怪打断读条（打断规则另有一步测）；
    - 陨落那一遍把刷怪点关掉。

    正式游玩时这些都不碰。

## 9. 给主控的话

- `ex_level` 已经会自动建管理器，main.gd 里 `--level-test` 的探针也已经接好，不用再改。
- 联机协议变了（见第 4 节），所有人都要换包。
- 预热名单见第 8 节第 9 条。
- 建议整合时用两台机器跑一次联机：开箱抢同一只箱子、开钥匙房、救队友、营救天工师的归属交接。
- 下一步可做：
  - 首领掉落合堆，压绘制调用；
  - AI 修士的楼宇挡墙；
  - 局内新穿的玄龟镜是否加护体（看策划）；
  - 烟遁符挡索敌。
