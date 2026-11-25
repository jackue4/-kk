# W2b → W2a 接口（ExBoss / ExMobs / net.gd 首领 RPC / warmup）

状态：**已实现**（2026-11-25，W2b）。和初稿的差别见文末「变更记录」。

## 1. ExBoss（scripts/ex/ex_boss.gd，preload 引用，没有 class_name）

```gdscript
const ExBoss := preload("res://scripts/ex/ex_boss.gd")
var br: Node3D = ExBoss.attach(m, boss_id, arena_rect, opts)      # 主人：m 已经 ExMobs/raid_manager 填好数值；进树前后都行
ExBoss.attach_remote(puppet, boss_id, arena_rect, opts)          # 木偶：只播画面
ExBoss.link_duo(br0, br1)                                       # 铁穹双卫两只互认（duo_hunter + duo_welder）
br.play_remote(kind, params)                                    # 收到 net 的 ex_boss_fx 后调
br.accept_hit(pos) -> bool                                      # 别人打首领木偶时可以拿那个人的位置问一下（区外打无效）
br.drop_points(n) -> Array[Vector3]                             # 战斗区里 n 个贴地落点（掉落撒开用，可选）
ExBoss.countdown_label(parent, pos, font) / ExBoss.set_countdown(l, title, secs)   # 重生倒计时字（可选）
signal event(kind, info)   # "frenzy" / "transform" / "reset" / "leash"（管理器拿来 toast）
```

### opts（照 extract_manager._spawn_boss 传的那套，另加三个相对量键）
| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| home | Vector3 | mob 位置 | 出生点（拉回用） |
| y_range | Vector2 | (-INF, INF) | 战斗区高度范围 |
| net | Node | null | net.gd |
| fx_out | Callable(kind, params) | — | 广播画面：主干里调 `net.ex_boss_fx(nid, kind, p)`（players.size() > 1 时） |
| summon_fn | Callable(id: String, pos: Vector3, elite: bool) -> Node3D | — | 刷召唤物（管理器建、登记、联机），返回 null = 不刷 |
| targets_fn | Callable() -> Array | 自己找（mob.player + net.remotes） | 可选 |
| night_fn | Callable() -> bool | — | `Callable(level, "is_night")` |
| room_n_fn | Callable() -> int | 1 | 房间真人数 |
| floor_fn | Callable(x, z) -> float | mob.floor_fn | 地面高 |
| **pts_k** | float | **1.0** | 技能点数 → 原始伤害：`原始 = 点数 × pts_k`。主干传 `mob.atk / maxf(1.0, ExMobs.atk_pts(id))` |
| **players** | int | — | 刷出时 mob.hp_max 是按几个人算的（主干一般 = 战斗区真人数；不缩放就传 1） |
| **hp_one** | float | — | 可选，直接给「1 人时的最大血量」；给了就不看 players |

### 相对量规则（W2b 实现）
- 伤害：每一下 `pts = min(技能点数 × dmg_k, HIT_CAP)`，`raw = pts × pts_k`；
  - 本机主角：`d = min(mob.atk_out(raw), HIT_CAP)`，进 melee / air.receive_attack；嗜血 `dealt(d)`。
  - 远程玩家：`remote_player.mob_hit(raw, …)` → 对方 `net_mob_attack` 按自己的法衣 / 境界换算；嗜血 `dealt(pts)`。
    注意：对方 raid_manager.net_take_hit 不会自动封顶 35，想封就查木偶的 `get_meta("hit_cap")`（ExBoss 在主人那边设，木偶那边 attach_remote 后也会设）。
  - 虫子身子 / 破土：用 `ExMobs.atk_pts(boss_id)`（点数）经 `_hit` 换算，不再读 `mob.atk`。
- 血量缩放：`_hp_one × ExMobs.players_k(n) × 夜形态系数`。
  - `_hp_one` 取法：opts 有 hp_one → 用它；有 players → 第一帧 `mob.hp_max / players_k(players)`；都没有（搜打撤老调用）→ `ExMobs.boss_hp(boss_id, 1)`（老算式，逐字不变）。
  - 所以**主干必须传 players（或 hp_one）**，否则首领血量会被改回 DarkArea 点数。
- ExBoss 不再在任何地方把绝对点数写进 mob.hp_max / mob.atk（双卫变身 `mob.atk = 原值 × 1.3` 是相对的，保留）。
- 首领单下封顶 HIT_CAP = 35（打在 100 点条上），主干保留。
- `drop_table()` / `drop_draws()` 是搜打撤掉落表，主干别调，首领死后走 raid_manager 的 `_loot` + 残片 + 霸主精魄。

### 主干 raid_manager 刷首领的写法（照 extract_manager._spawn_boss 改）
```gdscript
var n := _players_in(arena)                       # 战斗区真人数，至少 1
var m: Mob = Mob.new()
# … 按老公式填 def / region / lv / hp_max（× ExMobs.players_k(n)）/ atk / xp_k，set_meta("def_idx", ExMobs.NET_BASE + ExMobs.idx(id))
m.block_fn = Callable(level, "blocked")
_mob_root.add_child(m)
var nid := m.net_id
var br := ExBoss.attach(m, id, arena, {
	"home": spawn, "y_range": yr, "net": net,
	"fx_out": func(kind: String, p: Dictionary) -> void: _send_boss_fx(nid, kind, p),
	"summon_fn": …, "night_fn": Callable(level, "is_night"), "room_n_fn": _room_count,
	"pts_k": m.atk / maxf(1.0, ExMobs.atk_pts(id)), "players": n})
```
木偶：`ExBoss.attach_remote(m, id, arena, {"home": …, "net": net, "night_fn": …, "y_range": …})`（不用 pts_k / players）。

## 2. ExMobs（scripts/ex/ex_mobs.gd）
- `IDS` 顺序不动（联机编号）。新增 `const NET_BASE := 100`：主干联机 def_idx = `NET_BASE + ExMobs.idx(id)`（W2a 的 `Data.mob_def(i)` 用 `i >= NET_BASE → ExMobs.by_idx(i - NET_BASE)`）。
- 每条 def 的 `"hp"` / `"atk"` = 老体系倍率（报告 B §3.4），老公式：
  `hp_max = (BOSS_HP 70 若 boss 否则 SHAPE_BASE[shape][0]) × d.hp × CS.HP_CONV × CS.mob_s_hp(ri, lv) × …`，atk 同理。搜打撤 `ExMobs.setup()` 不读这两个键。
- 新增 `static func atk_pts(id) -> float`（技能点数基准，= def.atk_pts，默认 10）、`static func by_net(i) -> Dictionary`（i = NET_BASE + idx，越界返回 {}）。召唤物 wraith 用已有的 `drops_loot(id) == false` 判断（xp_k 置 0、不掉东西）。
- `big` 键：老体系不用再 ×2（brute 底血已含），主干忽略。
- 已有：`def / has / idx / by_idx / id_of / is_boss / display_name / players_k / boss_respawn / is_summoned / drops_loot / roll_camp / CAMP_POOL / MAP_BOSSES / SUMMON_MIN`。

## 3. net.gd 首领 RPC（保留，名字 / 回调照旧）
主干 raid_manager 实现这些回调（照 extract_manager 搬）：
| net 方法（调） | → raid 回调（实现） |
|---|---|
| `net.ex_boss_fx(nid, kind, params)` | `raid.net_ex_boss_fx(from, nid, kind, params)` |
| `net.ex_boss_claim(idx, respawn)` | `raid.net_ex_boss_owner(idx, owner, dead_t)` |
| `net.ex_boss_release(idx)` | （房主那边清主人，之后可能再发 owner） |
| `net.ex_boss_dead(idx, t, killer)` | `raid.net_ex_boss_dead(from, idx, t, killer)` |
| 主人掉线 | 房主自动释放该人名下的首领（net 内部处理，然后广播 owner = 0） |
| 中途加入 | 房主在 `_welcome` 之后补发首领状态（net 内部 `_ex_boss_tab` → `net_ex_boss_dead` / owner） |
具体签名以实现完成后本文件「变更记录」为准。

## 4. warmup.gd
- main 传 tag `"ex"`（现在的写法）或 `"raid"` 都行：关卡（host.level）带非空 `map_id` 就认成新图，内部统一记成 `"ex"` 档。木兰草原关卡没有 map_id → 照旧 `"raid"`。
- 新图分层：`"ex"`（每会话一次：着色器文件 + 神识 5 个 + mob_ring / creature_overlay、特效、文字、raid_manager 的掉落物 / 储物袋）；
  `"ex:<图>:<英雄>"`（本图 ex_mobs 的怪 / 精英 / 首领造型 + 神识影子网格挂在第一只上、边界幕 / 飘浮物 / 首领弹幕 / 苍鸿剑气 / 剑域、四周环视）；`"ex:hero:<英雄>"`（主角藏着的部件）。
- 新图**不刷**老区域表（`Data.REGIONS[raid.region]["mobs"]`）的怪：那些怪不会在新图出现。掉落物那一批要求 raid 有 `_drop_item / _spawn_mob / net_on`、单机（同大世界）。
- 删掉了搜打撤管理器专用的预热（撤离石柱 + 光柱、史诗掉落光柱、符珠、烟遁、箱子 MultiMesh、手机档掉落 LOD、天工师模型）。

## 变更记录
- `hp_one` 的意思定为「1 个人时的最大血量」（内部基数 = hp_one / players_k(1)）。主干 raid_manager 传 `players` 就够了。
- ExMobs 实际加的是 `NET_BASE`、`atk_pts(id)`、`by_net(i)`；初稿里的 `xp_ok` 没加（直接用 `drops_loot(id)`：false → xp_k 置 0、不掉东西）。
- 木偶那边也会设 meta `hit_cap = 35`（ExBoss._process 第一帧 _late_setup）。**raid_manager 的 net_take_hit / to_player_from 目前不看它**：别人名下首领打我的那一下（原始伤害 × 我的换算）不封顶，要封就在 to_player_from 里 `minf(结果, t.get_meta("hit_cap"))`（照 extract_manager.gd:1295）。
- net.gd：`_ex_peer_gone` 改名 `_ex_boss_peer_gone`，只剩「放掉他名下的首领」（天工师那半删了）；中途加入不再有 `_ex_sync`，首领状态靠申请时房主回的「有主 / 冷却到几时」。
