# F_combat 复核修复报告（战斗 / 英雄 / 木偶 / 局域网在场）

2026-11-24。源码没提交、没部署。动手前的备份：`_tasks/extraction_refactor/backup/<文件名>.fix.txt`（air_melee / air_caster / air_moves / player / remote_player / kit_canghong / kit_yujian / hero_defs / combat_poses / lan_presence / enemy_dummy / hero_selftest，全部 12 个归我的文件都备了；实际改了其中 10 个，air_moves / combat_poses / kit_yujian 没动）。
全部验证都是 `--headless` 跑的（用户在这台电脑上试玩，没开有窗口 / 隐藏窗口的游戏，也没做双开）。日志在 `_tasks/extraction_refactor/review_tmp/F_combat/`。

## 一、逐条结果

| id | 结果 | 改了什么（文件:函数） | 怎么验的 |
|---|---|---|---|
| combat-1 苍鸿按住 E 转成万剑连发 / 进飞剑对波 | **已修** | `hero_defs.gd`：新字段 `volley`（御剑 true、苍鸿 false，缺省 true，表头注释写了）。`air_melee.gd`：新 `has_volley()`（英雄系统关着 = 老规矩恒 true）；`shot_hold()` 没有连发的英雄恒 0；`start_clash` / `foe_volley_started` 先问它；原来写死 `blade_always()` 的 `clash_warn` / `can_accept_clash` 改问它。`air_caster.gd:tick`：转连发前再问一次（兜底） | `--hero-test`：苍鸿一闪后一直按着 E 0.9 秒 → 转成连发 / 对波 = false（以前 0.28 秒起就连发）。御剑 E 点射 + 按住连发 5.40 单位，和改之前一字不差 |
| combat-2 断月 / 天斩 / 万剑归宗把人往目标身上拖 | **已修** | `air_melee.gd:_start_move`：`_rooted = _atk.has("proj")`（放飞行道具的招原地出手；断月第二道是连段自动接的，也走这里）；`_tick_attack`：这类招只转身朝目标、不给 drive_vel。老招式表没有 proj，老规矩不变 | `--hero-test` 新加一项：25 米外放断月，人最多挪 0.0 米、剑气照样打中 1.40 单位（以前一次拖 20 米左右）。木桩前 4 米那几项（断月 1.40 / 天斩 2.86 / 万剑归宗 4.76）和改之前相同 |
| combat-3 新图没有碰撞体：剑气 / 瞬移 / 近身判定穿墙 | **部分修**（我这几个文件里的都修了；飞剑在 spell_projectile.gd，提了跨文件请求） | `player.gd`：新 `ex_level()`（镜头 floor_fn 的对象同时有 `solid_at / blocked / y_cap` 才算新图；老大世界 / 主城 / 灵田返回 null）、`solid_at(p)`、`solid_hit(a, b, step, skip_a, skip_b)`（第一个实心点或 INF）。`air_melee.gd:_legal`：新图里落点的脚 / 腰 / 头不在实心里、不高过 `y_cap`、和对手之间 `solid_hit` 通畅（回风 / 剑域闪身后、一闪穿身、瞬身、追击、对波站位，以及 AI 修士借用的 safe_spot 都走这里）；`_resolve` 的近身判定加 `_seen()` 视线（胸口一条线、再高 0.6 米一条线，通一条就算；两头各留一点，贴墙 / 半嵌在墙边的目标照样打得到）。`kit_canghong.gd:Wave`：每帧那一段先问 `solid_hit`，撞上就碎（只扫到撞墙点为止），弧边扫到但人在墙后的不算；别人那边只画的剑气按本机关卡也停在墙上。都用 `ex_level()` 把关：非新图一行不多走 | 新探针 `-- --hero-test=wall`（单人进天工秘所，无头可跑，`logs` 见 `review_tmp/F_combat/wall_out.txt`）：主城 / 木兰草原 `ex_level()` = null；天工楼西墙外 → 墙里：隔墙落点不合法、墙外空地落点合法、隔墙近身看不见、空地看得见；剑气 0.07 秒撞墙碎掉、墙里木桩掉血 0、空地对照木桩掉血 12。结论 PASS |
| combat-6 绕身击 / 破空蹬收招后补按从第一段起 | **已修**（还原老行为） | `air_melee.gd`：连段窗口抽成 `_link_id()`，判断从「上一招在不在 M1 表」改成「下一招在不在 M1 表」。老规矩下和备份逐条等价（air_moves 里非空 next 只有 l2~l5 / l5 / l3 / j2 / j3，前几个都在 CHAIN、后两个被 JUGGLE 挡掉）；苍鸿 kd_fl → k4、k_dash → k3 接得上，k_dy1 / ka3（觉醒结束后）这种技能 / 残留 next 照样不接 | `--hero-test`：老规矩 d_fl→l5、dash→l3、l2→l3、j1→l1、ctr→l1；苍鸿 kd_fl→k4、k_dash→k3、k_dy1→k1、ka3→k1 |
| combat-7 剑域只接得住第一下、光环却一直亮着 | **已修** | `air_melee.gd`：新 `_parry_dom`（剑域没接满、没到时间）。`_parry_counter`：接满 max_n 下也把 parry_t 清零（光环跟着收），否则记下 `_parry_dom`；`_to_idle`：剑域还开着就回到招架架势（`ck_parry`）；`receive_attack`：剑域里正在反斩（k_ctr）时又有人近身来犯也接（只接近身，飞来的留给护体 / 无敌帧）；挨了打 / 落地 / 出别的技能 / 换英雄 / 时间到都清掉。`_parry_pid()` 抽出来 | `--hero-test`：剑域第一下 2、第二下（反斩途中）2、第三下（回到架势后，状态 5 = GUARD）2，已接 3 / 4 下；剑域结束后再挨打 = 0（正常挨打）。回风（单下）照旧接一下就收 |
| combat-10 所有木偶的跳跃抬高 / 跨步下沉被覆盖 | **已修**（还原老行为） | `remote_player.gd:_process`：重伤趴下那段只在 `_down_k > 0` 时做，而且 `hero.position.y += …`（叠在 rig.apply 摆好的上面）；刚起身把转角归零一次，之后不再碰 hero 的变换 —— 不倒地时和改之前完全一样 | `--hero-test` 新加一项：木偶播「跃起下劈 a3」最高抬起 0.30 米（以前 0）、不倒地时前倾 0；状态包位 4 → 趴下转角 -1.42，起身后 0 |
| combat-11 地面重伤放「复活」的光 + 陨落慢动作 | **已修** | `player.gd:_on_own_event`：不再调 `melee.revive()`（它在 DOWN 状态会 `Vfx.reappear`），只做它其余几件事（气血 1、架势条清零、`_to_ready` 回到待命），再 `Combat.slowmo_release(0.1)` 把陨落那下起的慢动作收掉。只在关卡设了 lethal_fn（新图）时走，老规矩不变 | `--hero-test` 新加一项：地面 3 点气血挨 40 → 受击 0、dead=false、downed=true、地面状态不是倒地、0.35 秒后时速 1.00（以前慢动作要拖 0.8 秒）。「复活那团光」没法从日志里看见，按代码确认那一行不再走 |
| combat-12 连发打真人的减免看准星，不看实际打中谁 | **已修**（出手时逐柄判定） | `air_caster.gd`：新 `_sword_pvp(tgt, from, aim, extra)`，每柄出手前定 `_vol_pvp`：追踪剑看它追的是不是真人（追踪剑只会打中它追的那个）；没目标直飞的，看它这一路（from → aim 延长 130 米）会不会擦到别队真人（半径 = Proj 直飞扫掠 0.9 + 体型 + 1.2 走位余量，螺旋再加 0.8）。去掉了每帧按准星设的那一行。老规矩 / 打怪不压 | 代码核对 + `--hero-test` 御剑 E（打木桩）5.40 单位不变。双开没跑（规定不跑），留给回归。**剩下的边角**：直飞的剑同一条线上先擦到怪、后面才是真人时，那只怪也按 0.55 吃；出手之后才横穿进弹道的真人照旧按整份（都受 PVP_SUSTAIN 25/秒封顶）。要做到「按实际打中谁」得 spell_projectile.gd 把标记带进命中包（见第二节 (b)，可选） |
| combat-13 主城局域网在场的木偶不认英雄 | **已修** | `lan_presence.gd`：在场包末尾多带两项（英雄 id、搜打撤段位），只往后加 —— 老版本收到 17 项的包照旧只读前 15 项，这边收到老版本的 15 项短包当没英雄。木偶建出来时 `set_info({name, hero})`，对方换了英雄再 set_info 一次（换模型 / 剑） | `--hero-test` 开头新加一项（在主城里往本机自检端口发两包，自检档端口 +100，碰不到正在玩的人）：老版本包 → 皮肤 aladeng、没剑、名牌「旧版道友  结丹 Lv.7」；新版本包 → 皮肤 canghong、有剑、名牌「新版道友 · 苍鸿 · 筑基三阶」 |
| uxperf-16 每道剑气现拼新月网格 | **已修** | `kit_canghong.gd:Wave`：静态缓存 `_mesh_cache`，键 = 普通 / 巨大 × 剑气色（`color.to_html()`），最多 16 项（满了清空重来）。材质照旧每道一份（透明度要逐道淡出） | `--hero-test` 断月 / 天斩伤害、剑气数照旧；同色第二道起不再调 `_crescent` |
| gap-training-numbers 主城 / 试剑台木桩飘字按老修为（万） | **已修** | `enemy_dummy.gd:shown_dmg`：主角在英雄档时 = 原始伤害 ÷ `hero_base()`（18）× 10（= ex_mobs.gd 的 HIT_PER_UNIT，新图主角一个单位打怪 10 点）；英雄系统关着照旧按修为。hud 的 `_combo_ratio`、刀客 / 剑冢首领的飘字都调这个函数，一起变 | `--hero-test`：原始 18 → 老规矩 19936.4（旧口径）/ 英雄档 10.0 |
| gap-legacy-labels（lan_presence 那一半） | **已修** | `lan_presence.gd`：新 `_label()` —— 新版本的包 = 「名字 · 英雄 · 段位（· 状态）」，老版本的包照旧「名字  境界 Lv.N」。另外顺手在 `remote_player.gd:_refresh`：木偶有英雄（新图 / 主城擂台的真人木偶）时名牌写「名字 · 英雄」不写 Lv（新图里恒 Lv.1）；老规矩房间（没英雄）照旧 | 同 combat-13 那一项；擂台 HUD 上的「结丹 Lv.N」（arena_duel.gd）不归我，没动 |

另外 `hero_selftest.gd`：上面那些新检查（23 行，原来 21 行）+ `--hero-test=wall` 探针；苍鸿那几项放在套路最后（不打断原来觉醒 M1 / 瞬狱接着千刃连段量的单位，和 H 报告里的数可比）。25 米断月那项按「摆木桩时的朝向」往回退（前面换位后镜头转了向，按镜头退会退到试剑台的柱子后面、剑气被物理挡掉）。

## 二、跨文件请求（给回归代理）

(a) **spell_projectile.gd（combat-3 剩下的一半：飞剑穿墙）** —— 新图里御剑的点射 / 连发 / 剑诀 / 飞剑阵、苍鸿万剑归宗的剑都是 Proj，现在只做物理射线，新图里什么都碰不到。`player.gd` 已经有现成的查询，非新图恒返回 `Vector3.INF`，所以改了对老大世界 / 主城没影响：
1. `_process` 里每步的那条射线之后：
   ```
   var hit := get_world_3d().direct_space_state.intersect_ray(q)
   if hit.is_empty() and not ghost and player != null and is_instance_valid(player):
       var wp: Vector3 = player.solid_hit(global_position, nxt, 0.5)
       if wp != Vector3.INF:
           hit = {"position": wp, "normal": -(nxt - global_position).normalized()}
   ```
   （之后原有的 `_sweep(global_position, seg_end)` / `_impact(hit["normal"])` 不用改：直飞剑只扫到墙为止，撞墙就插在墙上。）
2. 追踪剑「离目标够近 → `_impact()`」那一支（`if d <= _spd() * dt + 0.3 + br:`）前面加一句：`player.solid_hit(global_position, point, 0.4, 0.0, 0.5) != Vector3.INF` 时不算打中，接着往下走射线那一步（会撞在墙上）。
3. 可选：`hurt_area`（大罡剑阵的巨剑 / 剑河）不管墙，影响小，可以不动。
验证：`-- --hero-test=wall` 可以照我的剑气那段再加一柄 `Proj.launch(player, Proj.K.SWORD, 墙外, 墙里木桩, …)`，看木桩掉不掉血。

(b) **可选，spell_projectile.gd + remote_player.gd（combat-12 的「按实际打中谁」版）**：`launch` 时把 `opts.get("pvp_k", 1.0)` 记在剑上，`hurt()` 多一个可选参数把它放进 info，`_impact_sword` 打中时带上；`remote_player.receive_hit` 我这边再乘 `info.pvp_k`（到时候 air_caster 的 `_sword_pvp` 就可以换成只打标记）。现在的逐柄判定已经修掉了复核里说的那种情况，这条不做也行。

(c) **可选，air_foe.gd**：AI 修士自己的近身判定、追踪也没有新图的视线检查（它的瞬移落点走 `player.air.safe_spot`，那部分已经挡墙了）。要的话照 `air_melee._seen()` 用 `player.solid_hit(...)` 加一句。

(d) **gap-legacy-labels 的另一半**（不归我）：arena_duel.gd 的「结丹 Lv.N」、air_foe / 道友名牌的 Lv。注意我已经把 remote_player 的名牌在有英雄时改成「名字 · 英雄」（见上表），别再改回去。

## 三、协议 / 兼容

- 局域网在场包（lan_presence，UDP 广播）15 项 → 17 项，两个方向都兼容（老版本收长包只读前 15 项；新版本收老短包当没英雄）。不用全员换包，但看到英雄要两边都是新包。
- 联机房间协议（net.gd）没动。

## 四、新字

没有新字：名牌里的「·」、英雄名、段位名（炼气三阶 … 化神）都已经在随包字体 / 补字字体里（大厅段位页、局域网那一行早就在用）。自检打印的字只进控制台。

## 五、自检命令和结果（都在 `D:\GodotProjects\修仙游戏` 下，无头）

```
"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --quit                          # 无报错
… --headless --path . --check-only --script res://scripts/<12 个文件>.gd                                           # 全过
… --headless --path . -- --hero-test           → [hero] 结论 PASS（23 行）    review_tmp/F_combat/hero_fix4_out.txt
… --headless --path . -- --hero-test --touch   → [hero] 结论 PASS（23 行）    review_tmp/F_combat/hero_touch_out.txt
… --headless --path . -- --hero-test=wall      → [hero] 结论 PASS（挡墙）      review_tmp/F_combat/wall_out.txt
… --headless --path . -- --level-test=lab      → [ex] 总计 失败 0 项（通过 80 项）review_tmp/F_combat/level_lab_out.txt
```
改之前的基线：`review_tmp/F_combat/hero_base_out.txt`（PASS 21 行）。对比：御剑 / 苍鸿各招的单位除了飞剑阵 / 大罡剑阵（随机落点，几次跑本来就在 4.0~4.4 / 5.4~6.9 之间晃）以外一字不差。

**没跑、留给回归代理的（有窗口 / 双开）**：`--hero-test`（桌面 + 兼容渲染器 `--touch`，看截图）、`--hero-test=pvp_a / pvp_b`（招架回传，剑域现在一架能接多下）、`lan_selftest` 双开（在场包多了两项）、老大世界 `-- --raid-shot`、主城 `-- --hub-shot`、擂台 `-- --hub-shot --arena-duel`（木偶名牌现在写英雄）。
