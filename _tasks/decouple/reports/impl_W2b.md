# impl_W2b：首领 / 怪定义 / 联机 / 预热（2026-11-25）

接口文档：`_tasks/decouple/W2b_api.md`（开工第一步写的，已按实现更新；W2a 的 raid_manager 已经照它接上了 pts_k / players / NET_BASE）。
备份：`_tasks/decouple/backup/{ex_boss,ex_mobs,ex_worm,net,warmup}.gd.W2b.txt`（ex_worm 没改）。

## 改了什么

### scripts/ex/ex_boss.gd（两条分支共用；不传新键时和搜打撤逐字一样）
- :109 `var pts_k := 1.0`；:127-128 `_hp_one` / `_hp_players`；:205-208 setup 读 `opts.pts_k / hp_one / players`。
- :259 `_late_setup`：给了 players 就 `_hp_one = mob.hp_max / players_k(players)`。
- :644 `_hp_for(n)`：有基数 → `_hp_one × players_k(n)`；没有（老调用）→ `ExMobs.boss_hp(boss_id, n)`（老算式原样调用，逐字相等）。
  :619（人数缩放）、:677（复位）、:1369（凌影夜形态）三处 `ExMobs.boss_hp` 都换成 `_hp_for`。
- :651 `_atk_pts()` = `ExMobs.atk_pts(boss_id)`；:1458 虫子破土、:1479 虫子身子由 `float(mob.atk)` 改成它（搜打撤那边 mob.atk 本来就等于 atk_pts）。
- `_hit`（:459-483）：`pts = min(点数 × dmg_k, 35)`，`raw = pts × pts_k`；本机 `min(atk_out(raw), 35)`；远程 `mob_hit(raw)`、嗜血 `dealt(pts)`。
- ExBoss 里不再有把绝对点数写进 mob.hp_max / mob.atk 的地方（双卫变身 `_base_atk × 1.3` 是相对的，保留）。头注释写了相对量。

### scripts/ex/ex_mobs.gd
- 首领 / 召唤物 / 毒尾蝎的 `"hp" / "atk"` 填老体系倍率（报告 B §3.4 X1）：凌幽 18/2.0、绛罗 20.3/1.4、沙渊巨虫 36/2.8、凌影 18/2.0、电鞭 11.3/2.0、冰僵 11.3/2.2、双卫各 22.5/2.0、22.5/1.8；wraith 0.8/1.1；毒尾蝎 1.2/1.2；其余小怪 1.0。
- :20 `const NET_BASE := 100`；:231 `atk_pts(id)`；:236 `by_net(i)`。`IDS` 顺序没动。搜打撤的 `setup()` 不读 hp / atk 两键，不受影响。头注释写了倍率的来历。
- 注：这一步我用了一个 python 小脚本按「每条首领那一行」替换数字（核对过只改了这 10 处），之后发现把 CRLF 写成了 LF，已经改回 CRLF；git diff 只有这 10 行 + 后面 Edit 加的几段。

### scripts/net.gd
- :311 / :416 `_ex_peer_gone` → `_ex_boss_peer_gone`（只放掉他名下的首领；天工师那半删了。没删干净是因为首领归属要靠它：主人掉线后不放掉，别人永远申请不到）。
- :1013-1027 `send_mob_dead` / `_mob_dead`：删 `_ex_log_camp` 两处和 `net_ex_mob_dead` 分支（一律走 `raid.net_mob_died`）。
- :1030-1162 原「搜打撤专用」整块只剩首领：`_ex_seed / _ex_bosses / _ex_boss_own`、`_ex_tab`、`_ex_boss_peer_gone`、`_ex_raid`、`ex_boss_dead / claim / release / fx` 及其 RPC，回调名照旧（`net_ex_boss_owner / _dead / _fx`）。
- 删了：`EX_BOX_CD / EX_CAMP_KEEP`、箱子（ex_box_claim / _ex_box_* ）、门（ex_door / ex_door_claim / _ex_door_*）、救人（ex_revive）、天工师（ex_doc_*）、中途加入（ex_sync_req / _ex_sync_req / _ex_sync / ex_local_sync）、`_ex_log_camp / _ex_camps_live`。
- 保留：map_id 分房、英雄名单、`_dx*` 场景破坏同步、kit_canghong 那条 load。
- 协议变了（删了 RPC），主干包和 extraction-pvp 包不能混房（同一张图会撞）。
- **没加空壳函数**：extract_manager.gd / ex_selftest.gd 调这些都是 `net.call("…")` 动态调用，编译不受影响；主干上它们不会被加载（W4 第二阶段删）。要是谁在主干上跑 extract_manager 并联机，会在运行时报「没有这个方法」。

### scripts/warmup.gd
- 删：`_cross_beam`、`_ex_mgr_fx`（撤离石柱 / 光柱、史诗掉落光柱、符珠、烟遁、箱子 MultiMesh、手机档掉落 LOD）、天工师模型、`CREATURE` 常量。
- run()（:385 起）：tag 是 "ex"，或 "raid" 且关卡带非空 map_id → 认成新图，统一记 "ex" 档（W3 那边 main 传 "ex" 或 "raid" 都行）。`xiu` = raid 有 `_drop_item` 和 `_spawn_mob`（raid_manager）。
- 新图在 xiu 下：着色器加神识 5 个（:463）；不刷老区域表的怪（新图不会出现那些怪）；raid_manager 的掉落物 / 储物袋那一批照做（:685，"ex" 档每会话一次，单机才做，同大世界）；本图怪那几批里第一只挂神识影子网格（:728）。
- 保留：边界幕、飘浮物、首领弹幕、苍鸿剑气 / 剑域、剑门（gates 参数照旧）、本图 ex_mobs 怪造型、mob_ring / creature_overlay。
- 顺手修：老「怪和掉落」那段算了 6 批进度但掉落那批没 tick，补上了。

## 测试
1. 单文件编译 `--check-only`：ex_boss / ex_mobs / net / warmup / ex_worm 全部无报错。
2. 整个工程 `--headless --path . --quit`：0 个 ERROR（跑的那一刻）。
3. `ex_boss_selftest`（老调用 = 搜打撤口径，验证「pts_k = 1 行为不变」）：main.gd 里 `--boss-test-ex` 探针已被 W3 删掉，我用临时启动脚本照原写法挂上
   （`C:/Users/CHENYA~1/AppData/Local/Temp/claude/31cb5b99151d1ce0/e85b2bf8-fad1-47ba-acd2-af87b9603715/scratchpad/boss_runner.gd`，窗口 960×540，不抓鼠标）：
   **失败 0 项，用时 150 秒**。七个首领的技能、人数缩放、夜形态 2240→4256、嗜血、区外无效、复位、拉回、联机重放全部通过，血量数字和改前一致（凌幽 2240 = 80000×0.04×0.7 等）。
   截图在 `_shots/preview/ex_boss_*.jpg`（没看）。跑的时候启动日志里有 raid_manager.gd 的 `_xb_*` 解析报错（W2a 当时正在改，不是我的文件），探针本身照常跑完。
4. 相对量单元检查（headless，`…/scratchpad/boss_rel_test.gd`）：**失败 0 项**。
   - 8 个首领的老调用：`_hp_for(1..4)` 和 `ExMobs.boss_hp` 逐字相等；`_atk_pts == mob.atk`；远程一下发 [9, 35]（点数、封顶）。
   - 相对量：players=2 时 `_hp_for(1) = 原始血 × 0.7`、`_hp_for(4) = 原始血`；点数 = atk_pts 时远程原始伤害 = mob.atk；封顶 35 × pts_k；mob.hp_max / atk 没被改写。
   - hp_one 直接给、虫子 atk_pts = 14、NET_BASE / by_net、IDS 顺序、首领倍率。
5. 没测：warmup 新图档真跑（要 `--warm` 进新图，main / ex_level 还在被 W2a / W3 改）；联机双开首领归属。

## 需要别人改
- **W2a raid_manager.gd**：别人名下首领打我（`net_mob_attack → net_take_hit → to_player_from`）时没有 35 点封顶。ExBoss 在木偶上也设了 meta `hit_cap`，照 extract_manager.gd:1295 在 to_player_from 里对结果 `minf(…, t.get_meta("hit_cap"))` 即可（本机那一下 ExBoss 已经包过 atk_out）。
- **W3 main.gd**：warmup 的 tag 新图传 "ex" 或 "raid" 都行（关卡有 map_id 就自动认）；`--boss-test-ex` 已删的话，ex_boss_selftest 只能用临时启动脚本跑（见上），要不要恢复这个探针由 W3 / W4 定（ex_boss_selftest 测的是搜打撤口径，留着可以当「老调用不变」的回归）。

## 遗留
- 中途加入的人看不到首领倒计时字，直到他走近首领、房主回了冷却时刻（删了 _ex_sync）。不影响归属。
- 主干包和 extraction-pvp 包混房会撞（同 map_id），建议握手加协议版本号（报告 F 已提）。
- ExBoss 的单下封顶 35 点在主干保留（报告 B 建议）；首领倍率是报告 B 的估算，数值专项再校。
