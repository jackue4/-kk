# H 英雄（H_heroes）交付报告

2026-11-24，SPEC 第 6 节。源码没提交、没部署。改老文件前的备份都在 `_tasks/extraction_refactor/backup/<文件名>.gd.txt`（net.gd 是 `net.gd.H.txt`，主控那份 `net.gd.txt` 没动）。

## 一、做了什么

1. **英雄表 `scripts/hero_defs.gd`**：御剑 / 苍鸿两位，字段照 SPEC 6.1（name / title / desc / skin / blade / art / flair / chain / chain_awake / juggle / derive / counter / dash_move / smash / pose_map / moves / follow_k / skill_cd / skills[4] / awaken / touch[4] / fly_speed / blink / realm / kit）。
2. **英雄档开关 `player.set_hero(id)`**：`""` = 关（门 0 木兰草原 / 老演示，按境界的老规矩一点不变）；`yujian` / `canghong` = 数值档固定结丹（`realm_idx` 恒 2：base 18、灵力 100、`Realm.COMBAT[2]` 1.0 基准、一开局就能空战），招式档 / 花样 / M1 / 技能 / 觉醒 / 模型 / 剑 / 遁速（28 m/s）由英雄表给。英雄档下别处调 `set_realm` 只记下不生效（剑冢首领、GM 键等不会把档位改走）。
3. **共用底盘不动**：拳脚 / 方向派生 / 蓄力重击 / 御风突进 / 闪现 / 护体 / 瞬身反击 / 挣脱 / 受身 / 真人对打规则 / 觉醒全是 air_melee.gd 原来那套；英雄差异做成「air_melee 里的一张表（apply_hero）+ 技能脚本（kit）」。`air_moves.gd` 一个字没改（AI 照旧读它）。
4. **御剑（老角色）调整**：花样档固定 1（残影 + 重手一圈空间波动，没有分身乱舞）；招式档固定元婴「紫霄雷法」外观（art 2，数值按结丹）；M1 整套压到 3.0 单位（拳 2.4 + 6 柄 × 0.1）；「诀」三式共用冷却拉到 2.5 / 6 / 10 秒；Q 飞剑阵 10 秒自动散、散后冷却 12 秒；R 大罡剑阵只有觉醒中能放、放完觉醒结束、英雄档伤害 ×0.25（整套约 5 单位，原来按大乘配的约 22）；PvP 连发每柄 ×0.55；飞剑 / 剑气 / 点射打真人只给轻硬直。
5. **苍鸿（新英雄）**：模型 `assets/hero/canghong.glb`（资源库 苍鸿_140199，strip_glb.py 精简：脸 / 身体 / 背后金环剑翼，只留 100100 待机、100111 跑步；腰上那把绑在躯干上的长剑和 13 柄零缩放飞剑没带；16.1 MB → 1.19 MB，贴图都是 256 以下）；手里常驻一把深青蓝剑（player_melee 的那把剑换色，命中点走剑身 `blade_point`）。M1 四连斩 + 方向派生、E 一闪 / Z 回风（招架反击，联机回传）/ Q 断月（新月剑气飞行道具）/ R 千刃，觉醒「剑心通明」四式全变 + 终式万剑归宗。新姿势（28 个关键姿势 + 15 条时间轴，含重伤趴地 `hd_down`）进 `combat_poses.gd`（联机木偶播得出来）。
6. **重伤倒地 / 无敌 / 回血开关**：`player.set_downed / is_downed / set_invuln / regen_k / lethal_fn / die_now`，空中、地面两条陨落路都能被接住。
7. **联机**：木偶按对方英雄建模型和剑；新增可靠 RPC `_hit_res`（招架回传）和 `_hero_fx`（苍鸿剑气画面）；状态包 flags 多两位（重伤、觉醒）。**协议变了，局域网所有人都要换包。**
8. **触屏**：剑 / 诀 / 阵 / 罡 四个键就是 E / Z / Q / R，字按英雄换（御剑 剑诀阵罡，苍鸿 瞬回月刃，苍鸿觉醒 狱域天归）；腾空才露出来；「阵」「罡」挪进攻击键那一簇（不再在右上角）；御剑的「罡」只在觉醒中出现。新字都已在补字字体里（font_check 核过：没有缺字）。

## 二、文件清单

新建：
- `scripts/hero_defs.gd` 英雄表
- `scripts/kit_yujian.gd` 御剑技能脚本
- `scripts/kit_canghong.gd` 苍鸿技能脚本（含新月剑气 `Wave` 内部类）
- `scripts/hero_selftest.gd` `--hero-test` 自检（含双开招架回传）
- `assets/hero/canghong.glb`（+ `canghong_face.png` / `canghong_male.png` / `canghong_male1.png` 和 .import，已 --import）

改动（只动了归 H 的）：
- `scripts/player.gd`：英雄档、无敌、重伤、致命伤钩子、E/Z/Q/R 转给 kit、持剑显示、倒地画面、英雄档下 set_realm 不生效
- `scripts/air_melee.gd`：ATK / SMASH / JUG 变成可换的表、`_mv()` 先查英雄表、方向派生 / 瞬身反击 / 冲刺攻击 / 随击飞剑倍率 / 「诀」冷却按英雄、招式新字段（reach / lunge / lunge_v / pass / auto / proj / qi）、招架（回风 / 剑域）、`kit_move` / `start_parry` / `net_parried` / `end_awaken` / `die_forced`、觉醒换 M1 表、`pvp_flags` 加两位、回血乘 `regen_k`、无敌、致命伤先问 `lethal_fn`、苍鸿不接对波。另修一个通用问题：出招吸附在长帧（截图、头一回放特效现编着色器）里会一步冲过目标导致判定落空，现在一帧走的路不超过到出手位置的距离。
- `scripts/air_caster.gd`：PvP 连发每柄 ×0.55（英雄档、瞄着真人时）
- `scripts/combat_stats.gd`：`static var heroes_on`，英雄档下 `pvp_hit` / `pvp_cap_k` 不看境界差
- `scripts/remote_player.gd`：按英雄建模型 / 剑、`notify_parried()`、`hero_downed()`、重伤趴下、觉醒剑身发光、英雄档下飞剑打真人只给轻硬直
- `scripts/touch_controls.gd`：英雄档的四个技能键（字 / 冷却 / 位置）
- `scripts/combat_poses.gd`：苍鸿 28 个关键姿势 / 14 条时间轴 + 重伤 `hd_down`
- `scripts/hero_skin.gd`：SKINS 加 `canghong`、`hero_key()`、预热也读苍鸿
- `scripts/voxel_hero.gd`：`set_skin()` 运行时换皮肤、`skin_key()`
- `scripts/fighter_rig.gd`：`refit()`、`set_weapon()`、姿势重映射 `remap`
- `scripts/gate_array.gd`：英雄档下问 kit 能不能放（觉醒中）、伤害 ×0.25
- `scripts/sword_manager.gd`：把自己挂到 `player.sword_mgr`；英雄档下 Q 不直接开阵（交给 kit）、E 的万剑齐发只在阵开着时
- `scripts/net.gd`：只加英雄 / 招架相关（见第四节）；`_ready` 里 `player.set_meta("net", self)`
- `awaken_fx.gd`、`air_moves.gd`：没改

## 三、公共接口（照实现写）

`HeroDefs`（`const HeroDefs := preload("res://scripts/hero_defs.gd")`）：
```
HeroDefs.DEFAULT == "yujian"；HeroDefs.BASE == 18.0；HeroDefs.TIER == 2
HeroDefs.HEROES                     # 整张表（const Dictionary）
HeroDefs.ids() -> Array             # ["yujian", "canghong"]
HeroDefs.has(id) -> bool
HeroDefs.def_of(id) -> Dictionary   # 注意：SPEC 写的 HeroDefs.get(id) 实现不了 —— 和 Object.get 撞名，Godot 直接编译不过（实测）。D 的 ex_lobby_ui 已经先试 def_of
HeroDefs.hero_name(id) -> String
HeroDefs.skill(id, i) -> Dictionary # i: 0 E · 1 Z · 2 Q · 3 R；{key, name, desc, cd, mp, awake?, awake_name?, awake_only?}
HeroDefs.move_of(id, move_id) -> Dictionary
HeroDefs.m1_units(id, awake := false) -> float
```

`Player`（player.gd）：
```
signal hero_changed(id: String)
var hero_id := ""                 # "" = 英雄系统关
var hero_def: Dictionary
var kit: Node                     # 技能脚本实例（子节点 HeroKit）
var sword_mgr: Node               # 飞剑阵（sword_manager 自己挂）
var regen_k := 1.0                # 空战脱战回血倍率；新图关卡设 0
var lethal_fn := Callable()       # func(info: Dictionary) -> bool；true = 接住致命伤（转重伤）
func set_hero(id: String) -> void # 每次调用都先复位 regen_k = 1、lethal_fn 清空、无敌清掉、重伤起身（关卡 _ready 里再设）
func hero_base() -> float         # 英雄档恒 18；关着按境界
func hero_on() -> bool
func blade_always() -> bool       # 苍鸿
func set_blade_glow(k: float)
func set_invuln(t: float)         # t 秒（真实时间）无敌；<=0 取消。空中 receive_attack 返回 -1、地面 dodge_iframes() 为真
func is_invuln() -> bool;  func invuln_left() -> float
func set_downed(on: bool)         # 重伤倒地：不能出招 / 技能 / 起飞 / 闪现，移速 ×0.35，趴着；发 combat_event "player_downed" / "player_rise"
func is_downed() -> bool
func absorb_lethal(info: Dictionary) -> bool   # 内部用：问 lethal_fn，接住了就 hp = max(hp, 1) + set_downed(true)
func die_now()                    # 直接陨落（重伤流光流完 / 自尽），不问 lethal_fn；发 player_dead {forced: true}
```

`AirMelee`（player.air）新增：
```
func apply_hero(d: Dictionary)
func pick_target() -> Node3D
func kit_move(id: String, t: Node3D = null, opener := false, pick := true) -> bool
func start_parry(dur: float, radius := 0.0, max_n := 1) -> bool
func net_parried(src: Node3D)     # 我这一下被对面招架了：自己硬直 0.5 秒
func end_awaken()                 # 觉醒提前结束（终结技）
func die_forced()
var parry_t / parry_r / parry_n / parry_max；var stat_hits: Array  # [招式名, 原始伤害, 结果]（自检用）
func pvp_flags() -> int           # 位 3 被打飞（原有）· 位 4 (16) 重伤倒地 · 位 5 (32) 觉醒中
```
`skill_name / skill_cost / skill_ready / art_cd`：苍鸿时转去问 kit 的 Z（回风），所以 hud.gd 的「诀」那一格显示是对的。

技能脚本（kit_yujian.gd / kit_canghong.gd 同一套鸭子接口）：
```
func press(i: int); func release(i: int); func tick(dt: float)
func skill_name(i) -> String;  func cd_ratio(i) -> float（0 = 可用）;  func skill_ready(i) -> bool
func btn_visible(i) -> bool;   func touch_text(i) -> String;  func skill_info(i) -> Dictionary（技能表那一项 + name / cd_ratio / ready）
苍鸿另有：var cds: Array[float]；var stat {parries, waves, wave_hits, wj}；func z_slot(field)；on_awaken / on_awake_end / on_parried / on_proj
御剑另有：func ult_ok() -> bool（gate_array 问）
```

`RemotePlayer`（remote_player.gd）新增：`var hero_id`、`func hero_downed() -> bool`（对方英雄档的重伤，状态包位 4；和原来的 `is_downed()`「空战里被砸进地里」不是一回事）、`func notify_parried()`。

`CS`（combat_stats.gd）：`static var heroes_on`（set_hero 开关）。

## 四、联机协议变更（**局域网所有人都要换包**）

- `net._hit_res(res: int, pos: Vector3)`（any_peer, reliable）：挨打的一方告诉出手的一方这一下的结果。现在只发 `res = 3`（`HIT_RES_PARRIED`，被苍鸿「回风 / 剑域」招架）；出手方收到 → `player.air.net_parried(木偶)` → 自己硬直 0.5 秒。招架是挨打的一方按自己那边的状态判的（同别的受击），反斩照常走 `_hit` 打过去。1 / 2（护体挡下 / 被瞬身闪开）预留，现在不发。发送入口 `net.send_hit_res(to_id, res, pos)`，由 `remote_player.notify_parried()` 调。
- `net._hero_fx(kind, pos, dir, roll)`（any_peer, unreliable）：苍鸿的新月剑气（1）/ 天斩（2）在别人那边只画不判伤害。发送 `net.send_hero_fx(...)`。
- `FX_KINDS` 末尾加了 `"air_parry"`（只往后加，下标过网）。
- 状态包不改签名：flags 多了位 4（16，重伤倒地）、位 5（32，觉醒中），都在 `air.pvp_flags()` 里拼。
- 握手里的英雄 id 是主控加的（`players[id]["hero"]`）。木偶建出来时读 `net.players[对方]["hero"]`，之后 `set_info` 时再换。

## 五、实测数值（`--hero-test`，木人桩，原始伤害 ÷ 18 = 单位；觉醒那几行已含 ×1.3）

| 英雄 | 招 | 单位 | 冷却 | 灵力 |
|---|---|---|---|---|
| 御剑 | M1 整套（5 段 + 6 柄随击） | 3.00 | — | 0 |
| 御剑 | E 点射 + 按住连发 1 秒 | 5.40（点射 0.4，连发约 5/秒） | 0.16 | 点射 3、连发 30/秒 |
| 御剑 | Z 剑诀（一式） | 2.16 | 三式共用 2.5 / 6 / 10 | 10 / 18 / 32 |
| 御剑 | Q 飞剑阵（开 3 秒） | 3.63 | 散后 12 | 起手 12、每秒 3.5 |
| 御剑 | R 大罡剑阵（觉醒中） | 6.67（= 5.1 × 1.3） | 觉醒才有 | 50 |
| 御剑 | 觉醒 M1 | 3.90 | | |
| 苍鸿 | M1 四连斩 | 3.00 | — | 0 |
| 苍鸿 | E 一闪 | 1.20 | 7 | 12 |
| 苍鸿 | Z 回风（招架成功的反斩） | 1.60 | 12 | 8 |
| 苍鸿 | Q 断月（两道剑气） | 1.40 | 9 | 10 |
| 苍鸿 | R 千刃（6 斩 + 挑飞） | 2.40 | 14 | 15 |
| 苍鸿 | 觉醒 M1（五段，剑气延伸） | 4.36（连段衰减后；表算 3.6 × 1.3 = 4.68） | | |
| 苍鸿 | 觉醒 E 瞬狱（3 次突进斩） | 2.42（连段衰减后） | 7 | 12 |
| 苍鸿 | 觉醒 Z 剑域 | 招架圈 6 米 1.6 秒，最多反斩 4 下、剑气拨开 | 12 | 8 |
| 苍鸿 | 觉醒 Q 天斩 | 2.86（= 2.2 × 1.3） | 9 | 10 |
| 苍鸿 | 觉醒 R 万剑归宗 | 4.76（13 × 0.22 + 落地 0.8，× 1.3） | 14 | 15 |

平衡：两位 M1 都是 3.0；苍鸿技能 1.2 ~ 2.4、冷却 7 ~ 14 秒（目标 1.0 ~ 2.5 / 6 ~ 15）。御剑的远程压制（连发约 5 单位 / 秒，灵力 3 秒见底）在打怪里明显更强；PvP 里连发每柄 ×0.55，再加上原有的单下 22 / 余量 30 / 每秒 25 封顶，大致拉平。两位终结技 5 ~ 6.7 单位。

## 六、自检命令和结果

- 编译：`Godot…console.exe --headless --path . --quit` 无报错；新脚本 `--check-only` 都过。
- `python _tasks/trailer/run_hidden.py . _tasks/extraction_refactor/logs/H_hero_final --resolution 1280x720 -- --hero-test` → `[hero] 结论 PASS（21 行）`，stderr 0 个 SCRIPT ERROR（约 2 分钟）。打印两位的 M1 / 四技能 / 觉醒 / 觉醒四技能（含终结技）的单位、冷却、灵力，逐帧掉血；苍鸿回风招架（受击结果 2、自己不掉血、闪到 5.4 米外、反斩 1.60 单位）、架势外照常挨打（0）、剑域拨剑气（1）/ 近身反斩（2）；来回换英雄（皮肤 aladeng ↔ canghong、剑、触屏字、关掉后 heroes_on=false）；出生无敌（空中 -1、地面 dodge_iframes 真）；重伤（致命伤被 lethal_fn 接住：dead=false downed=true 气血 1 flags=16；重伤中按技能 / 起飞都没反应）。
- 手机档：`… H_hero_touch --resolution 1280x720 --rendering-method gl_compatibility -- --hero-test --touch` → PASS，0 个 SCRIPT ERROR。这一遍御剑觉醒 R（大罡剑阵）放出来了（扣了 50 灵力）但没打中木桩（桌面档打中 6.67），演出里剑雨的落点看帧率，没细查。
- 双开招架回传（擂台联机，自检档端口自动 +100，不会配到别人）：
  `run_hidden … H_pvp_a --resolution 640x360 -- --hero-test=pvp_a` 和 `… pvp_b`（a 苍鸿每秒起一次回风，b 御剑一直点「攻」）：a 招架成功 6 次、反斩全中；b 收到「被招架」6 次、硬直 6 次。对调（`pvp_ax` / `pvp_bx`）：b 苍鸿招架 6 次，a 收到 5 次（最后一次落在 a 统计结束之后）、硬直 5 次。房主那边别人的苍鸿木偶：皮肤 canghong、手里有剑。两边 0 个 SCRIPT ERROR。
  （`_tasks/pvp_rules/run_pair.py` 写死了 `--arena-duel` 走 arena_selftest / pvp_rules_selftest，那两个不归我，所以招架回传另写在 hero_selftest 里，用法同上。）
- 主城擂台：`-- --hub-shot --arena-duel` 跑完（6 场 AI 陪练 胜 2 负 4，中途收场正常），0 个 SCRIPT ERROR。
- 老大世界：`-- --raid-shot` 跑完（撤离成功、回到大厅=true），0 个 SCRIPT ERROR。

截图（只看 preview）：
- 桌面：`_shots/preview/hero_yujian_m1.jpg`、`hero_yujian_0~3.jpg`、`hero_yujian_awaken.jpg`、`hero_yujian_aw_0~3.jpg`（aw_3 = 大罡剑阵）、`hero_canghong_m1.jpg`、`hero_canghong_0~3.jpg`、`hero_canghong_awaken.jpg`、`hero_canghong_m1_aw.jpg`、`hero_canghong_aw_0~3.jpg`（aw_3 = 万剑归宗）、`hero_canghong_parry.jpg`、`hero_canghong_domain.jpg`、`hero_downed.jpg`
- 手机档（触屏按钮字）：`_shots/preview/hero_touch_*.jpg`（`hero_touch_canghong_aw_2.jpg` 看得到 狱 / 域 / 天 / 归；`hero_touch_switch_canghong.jpg` / `hero_touch_switch_yujian.jpg` 换英雄后的按钮）
- 联机：`_shots/preview/hero_pvp_a.jpg`、`hero_pvp_ax.jpg`、`hero_pvp_bx.jpg`
- 苍鸿模型原生动画：`_tasks/extraction_refactor/H_shots/anim_canghong_100100_*.jpg`、`anim_canghong_100111_*.jpg`

## 七、已知问题 / 没做的

1. **arena_net.gd（主控的）`open_room` 里 `players[1]` 没带 `"hero"`**（net.gd 的 host 带了）：擂台对决里，加入的一方看房主的木偶永远是默认的阿拉灯、手里没剑（双开实测如此）。加一行 `"hero": _my_hero()` 即可。
2. **hud.gd（D / 主控）桌面技能框**：E 那格写死「飞剑点射 / 长按连发 / 对波」，苍鸿也这么写；只有两格（E / Z）。英雄档建议改成四格，每格读 `player.kit.call("skill_info", i)`（name / cd_ratio / ready / mp），御剑 R 只在 `kit.call("btn_visible", 3)` 时亮。「诀」那一格现在对苍鸿已经显示回风（air_melee 转过去了）。
3. 新材质（新月剑气 / 剑域光环：StandardMaterial3D 不受光 + 叠加 + 顶点色）没进 warmup 预热：手机 / 网页第一次放会现编一下。warmup 归主控，建议在「温养法器」那步摆一个 `kit_canghong.gd` 的 `Wave`（`remote_wave` 静态函数能直接放一道只画不判的）。
4. 换英雄后（大厅里在房间时）`players[id]["hero"]` 不会更新，房间里别人看到的还是握手时的英雄；本轮新图是进图前选英雄，影响不大。
5. 地面站着挨打仍走 player_melee 的只狼式格挡 / 弹反（不归我改，SPEC 也没要求统一）；英雄在地上按攻 / 御 / 技能都会先腾空进空战，所以实战里大多在空战规则下。
6. 地面那条陨落（player_melee._on_hurt）没法在它发 `player_dead` 之前拦：我在 player.gd 里最先接 combat_event，别人收到 `player_dead` 时 `player.dead` 已经是 false、`is_downed()` 是 true。**收到 `player_dead` 先看 `player.dead`**；或者只听 `player_downed`。
7. 御剑 PvE 的连发很强（约 5 单位 / 秒）；SPEC 只要求 PvP 压，我没动 PvE。
8. 苍鸿招架只认「近身」判定（info 里没有 ranged）；对 AI 的剑气 / 弹幕回风按护体走（拨开 / 擦血），剑域才拨。
9. 苍鸿没有飞剑对波：不给对波预警、按「剑」也接不了波；被御剑连发只能护体拨 / 闪。
10. 手机档里大罡剑阵那一遍没打中木桩（见第六节），没细查；桌面档正常。

## 八、给 E（extract_manager）的说明

- 主控在进新图前已经 `player.set_hero(ExProfile.hero())`；`set_hero` 每次都会把 `regen_k` 复位成 1、`lethal_fn` 清空、无敌清掉、重伤起身 —— **在你的 manager `_ready` 里设**：
  ```
  player.regen_k = 0.0                       # 新图没有自然回血
  player.set_invuln(10.0)                    # 出生 10 秒无敌（空中 / 地面 / 真人都打不到）
  player.lethal_fn = func(info: Dictionary) -> bool:
      return not player.is_downed()          # 第一次致命伤 → 重伤；重伤中再挨致命伤 → 返回 false = 照常陨落
  ```
  接住时 player 自己会 `melee.hp = max(hp, 1)` + `set_downed(true)`，并发 combat_event `"player_downed"`（起身发 `"player_rise"`）。重伤条（20 秒流光）、自救 / 被救、自尽都在你那边：流光流完 / 自尽 → `player.die_now()`（发 `player_dead {forced: true}`，不再问 lethal_fn）；自救成功 → `player.set_downed(false)` + `player.melee.hp = 100`。退出新图时把 `lethal_fn = Callable()`、`regen_k = 1` 还原（回主城 set_hero 也会复位）。
- 重伤中 `player.is_downed()` 为真：E 键物品 / 读条那些你自己拦。重伤会把飞剑阵收掉、空中掉回地面。
- 收到 `player_dead`：**先看 `player.dead`**（地面那条路发完事件后会被我撤回成重伤，见第七节 6）。
- 打怪伤害：`u = 原始伤害 / player.hero_base()`（恒 18；觉醒的 ×1.3 已经在原始伤害里，觉醒时 u 会是 1.3 倍）。
- PvP：`CS.pvp_hit` 在英雄档下不看境界差（`CS.heroes_on`）；你那边 `net_deal_hit` 照 raid_manager 写就行。`net_take_hit` 里路由**一定要把木偶（`_remote(from)`）当 src 传给 `player.air.receive_attack`**（照 raid_manager / arena_duel），苍鸿的招架回传靠它（`src.notify_parried()`）。
- 队友救人：别人的重伤看木偶的 `hero_downed()`（状态包位 4）。
- `net` 契约里 `raid.lv`、`raid.get("_in_trib")` 照旧要有（状态包拼 flags 用）。
- AI 修士（air_foe）照旧用 `Moves.MOVES`，没受英雄表影响；它们的档位按 `player.realm_idx`（英雄档恒 2 = 结丹基准）。
