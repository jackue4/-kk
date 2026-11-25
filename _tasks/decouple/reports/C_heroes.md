# C · 英雄与战斗数值 解耦报告（只读调查，未改任何项目文件）

目标（用户拍板）：主干上英雄只差技能 / 外观 / 战斗方式，不做强弱、全部免费；数值跟玩家境界走，和原来的默认角色一模一样；去掉「英雄档固定结丹」。

---

## 1. 现状：英雄档到底改了哪些数

### 1.1 开关与固定档
- `scripts/player.gd:445-502` `set_hero(id)`：
  - `:464` `CS.heroes_on = id != ""`（全局静态开关）
  - `:475` `realm_idx = HeroDefs.TIER`（恒 2 = 结丹）
  - `:476-484` `realm = Realm.LIST[2].duplicate()`，再盖 `hero_def.realm`（`lines/col_a/col_b/style/motes/boost/rise/swords`），再盖 `art`、`speed = fly_speed(28)`、`blink(8)`、`blink_spd(60)`
  - `:488` `mp = mp_max()`（= `CS.mp_max(2)` = 100）
- `scripts/player.gd:390-394` `set_realm()`：英雄档下**直接 return**，只记 `_realm_req`（`:122`）。这就是「境界不生效」的根。
- `scripts/player.gd:505-506` `hero_base()`：英雄档恒返回 `HeroDefs.BASE`(18)。
- `scripts/hero_defs.gd:36-37` `const BASE := 18.0` / `const TIER := 2`；头注释 `:4-5`、`:34` 写明「数值档固定结丹」。

### 1.2 伤害真正从哪来
- 所有英雄技能 / M1 的原始伤害都走 `air_melee._base()`（`scripts/air_melee.gd:614-615`）：`float(player.realm["dmg"]) * (AWAKE_DMG if awake_t>0 else 1)`。
  - 技能脚本统一用 `kit_base.units(u)`（`scripts/kit_base.gd:258-259` = `player.air._base() * u`）；`heroes/kit_canghong2.gd`、`kit_shuanghua.gd`、`kit_zhenyue.gd` 全部走 `units()` / `air._base()`，**没有任何地方写死 18**（`kit_canghong2.gd:1100` 的 18.0 是特效长度，不是伤害）。
  - `hero_def.realm` 覆盖项里**没有 dmg / mp / volley**，所以只要 `realm` 字典的底子换成 `Realm.LIST[realm_idx]`，英雄的伤害就自动 = 招式单位 × 当前境界 base，和老角色一个口径。
- 下游换算全部按 `player.realm_idx` 除回 base，链路自洽：
  - 大世界打怪 `raid_manager.gd:403-413` `CS.raid_hit(d, player.realm_idx, lv, …)`（d / base(realm) × atk(lv)）
  - 大世界 PvP `raid_manager.gd:889` `CS.pvp_hit(raw, player.realm_idx, their, gear)`、`:908` `CS.pvp_cap_k(their, player.realm_idx)`
  - 擂台 `arena_duel.gd:687` `CS.arena_hit(dmg, player.realm_idx, lv, their_lv)`；`:229` `lv = Profile.cult(player.realm_idx)[0]`（英雄档下现在拿的是结丹的 lv，本身就是个 bug）
  - 主城木人 / 刀客 / 剑冢：原始伤害对原始血（血也按 base(境界) 配，`CS.boss_k(realm)`、`arena_ai_hp(realm)`）
- `raid_manager.gd` 完全不认识英雄（grep 无 hero_id），所以英雄进大世界后什么都不用改，只要 realm_idx 是真境界。

### 1.3 英雄档对数值的其余改动
- `scripts/combat_stats.gd:226-248`：`static var heroes_on`；`pvp_hit` `:233-234` 英雄档下忽略境界差；`pvp_cap_k` `:246-247` 英雄档下封顶不随境界差。→ 主干要恢复老规矩（每境 ×1.08），**删这两个分支**。
- `scripts/enemy_dummy.gd:120-136` `shown_dmg()`：英雄档飘字按 `HERO_PVE_UNIT=10`（= ex_mobs 的口径）；→ 删英雄分支回到按修为（`CS.unit_same(lv)`）。
- `scripts/awaken_fx.gd:153 / :197` 读 `CS.heroes_on` —— 纯画面（觉醒配色），保留这个开关即可。
- `player.gd:1116-1119` 英雄档空战闪现吃 `dash_n` 次数 —— 规则，三位英雄一样，保留。
- `air_melee.gd:91-92` `AWAKE_DUR 14 / AWAKE_DMG 1.3`；英雄表 `awake_dur` 三位都是 16 —— 一样，保留。

### 1.4 三位英雄之间有没有强弱（核对结果：数值面没有）
三个 def（`scripts/heroes/def_zhenyue.gd` / `def_canghong.gd` / `def_shuanghua.gd`）**都没有** hp / atk / def / 受伤倍率 / hero_base 之类字段：
| 项 | 镇岳 yujian | 苍鸿 canghong | 霜华 shuanghua |
|---|---|---|---|
| fly_speed / blink / blink_spd | 28 / 8 / 60（:157） | 28 / 8 / 60（:197） | 28 / 8 / 60（:131） |
| realm 覆盖 boost / rise / swords | 1.4 / 7 / 0（:158-159） | 1.4 / 7 / 0（:198-199） | 1.4 / 7 / 0（:132-133） |
| art / flair | 2 / 1（:18） | 1 / 1（:20） | 1 / 1（:22） |
| awake_dur | 16 | 16 | 16 |
| 技能 mp | 全 0 | 全 0 | 全 0 |
| 技能 cd E/Z/Q/R | 7/11/9/14 | 8/11/9/14 | 5/10/9/14 |
| M1 四下单位 | 0.5+0.6+0.7+1.2=3.0 | 0.45+0.45+0.55+0.55=2.0（另有剑痕引爆） | 0.5+0.55+0.75+1.2=3.0 |
差别只在招式设计（单位、霸体 armor、冷却、剑痕机制），属于「战斗方式」。art 只影响 Realm.ARTS 的剑诀名 / 队形（老 caster 用），英雄不走 caster，影响不到数值。结论：**不需要给英雄加平衡系数**；如要量 DPS 一致性，用现成 `--tsb-show=<id>`（`tsb_show.gd:141/:208` 打印每招单位，口径 `hero_base()` 自动跟随境界）。

---

## 2. 推荐改法（最小、隔离；scripts/heroes 与 air_melee 不动）

### 2.1 player.gd（核心，约 30 行）
1. 新增 helper（放在 `_realm_fx` 后）：
```gdscript
## 英雄的境界表 = 当前境界的 Realm.LIST（数值 / 遁速 / 升限都随境界）+ 英雄的「外观」覆盖
const HERO_LOOK_KEYS := ["lines", "col_a", "col_b", "style", "motes", "width", "swords"]
func _hero_realm() -> Dictionary:
	var r: Dictionary = (Realm.LIST[realm_idx] as Dictionary).duplicate()
	var over: Dictionary = hero_def.get("realm", {})
	for k: String in HERO_LOOK_KEYS:
		if over.has(k):
			r[k] = over[k]
	r["art"] = int(hero_def.get("art", 1))
	r["mode"] = Realm.Mode.LIGHT      # 决策点 D1：英雄的四技能都在空战里，炼气 / 筑基也要能空战
	return r
```
2. `set_realm()` `:391-394`：删掉早退，改成照常走；把 `:397` `realm = Realm.LIST[realm_idx]` 换成
   `realm = _hero_realm() if hero_id != "" else Realm.LIST[realm_idx]`。其余（升阶灵力回满、`_realm_fx()`、结婴演出、`realm_changed`）原样。删 `_realm_req`（`:122`）。
   注意 `:402` 「空战中跌回非光遁就退出空战」在英雄档下因为 mode 恒 LIGHT 不会触发，符合预期。
3. `set_hero()` `:475-488`：删 `realm_idx = HeroDefs.TIER` 和那段 duplicate/覆盖/speed/blink，换成 `realm = _hero_realm()`；`mp = mp_max()` 保留（现在是 `CS.mp_max(realm_idx)`）。`:464` `CS.heroes_on = id != ""` 保留（只剩画面用途）。`:466-473` 关掉英雄的分支 `realm = Realm.LIST[realm_idx]` 已是对的。
   `:447-453` 复位 `regen_k / lethal_fn / _invuln_until / downed` 保留无害（这些是 ex_level / extract_manager 设的重伤倒地钩子；主干新图走老死亡规则就不会再设，见风险 R5）。
4. `hero_base()` `:505-506` 改成 `return float(realm["dmg"])`（= `CS.base(realm_idx)`，英雄 / 老角色同一口径）。
5. 注释 `:108-109`、`:441-444` 改掉「固定结丹」说法。

### 2.2 combat_stats.gd
- 删 `:233-234`（pvp_hit 里 `if heroes_on: their_realm = my_realm`）和 `:246-247`（pvp_cap_k 里 `if heroes_on: return 1.0`）。
- `:226-228` 注释改成「heroes_on 只给画面（awaken_fx）用，不碰数值」。保留 `static var heroes_on`。

### 2.3 hero_defs.gd
- 删 `const BASE := 18.0`（`:36`）——唯一引用是 player.gd:506 和注释（`enemy_dummy.gd:124` 注释）。
- `const TIER := 2`（`:37`）：数值上不再用；还被 `ex/hero_doll.gd:190`、`ex/hero_select_ui.gd:479` 当展台 VoxelHero 的装束档。两种处理：保留并改注释为「大厅展台装束档（只管看）」，或这两处改传 `Profile.realm()`。推荐保留常量改注释（最小）。
- 头注释 `:4-5`、`:34`（realm 字段说明）改成「数值随玩家境界；realm 覆盖只取外观键」。
- `ids()` `:46-50` 已经三位全露（shuanghua enabled=true）。

### 2.4 enemy_dummy.gd
- `:120-126` 删 `HERO_PVE_UNIT` 和英雄说明；`:132-133` 删 `if p.has_method("hero_on") … return dmg / hero_base * HERO_PVE_UNIT` 分支。剩下的按 `p.realm_idx` + `Profile.cult` 的老逻辑正好对英雄也对。

### 2.5 main.gd `_apply_combat_mode`（`:789-806`）
主干上主城 / 木兰草原 / 两张新图全是英雄档，境界由开机 `:255 set_realm(boot_realm)` 和局内渡劫维护，不必每次重设：
```gdscript
func _apply_combat_mode(_mode: String) -> void:
	player.set_hero(Profile.hero())        # Profile = raid_profile.gd
```
- 不要在这里再 `set_realm(boot_realm())`：`boot_realm()` 在自检模式恒 0，回主城会把自检里设好的境界清掉（老 legacy 分支只在进门 0 时这么做，是为了从「固定结丹」还原）。
- 调用点 `:259`（开机主城）、`:902`（进图前，`"ex" if is_ex else "legacy"`）、`:930`（入房失败回主城）、`:1072`（回主城）、`scripts/lab/mijing_boot.gd:74` 都可不动（参数被忽略）。`:902` 必须仍在 `net.host/join` 之前（握手要带 `_my_hero()`，见 `:896-899` 注释），现状已满足。
- 老演示（`--old-hall`、`_combat_demo`、`_realm_demo`、trailer、hub == null）从不调 set_hero，保持 legacy（hero_id ""），不受影响。
- `:535` `air_skill` 飘字按 hero_id 分支——画面，保留。

### 2.6 英雄归属 / 选择挪进 raid_profile.gd（全免费）
现状：`ex/ex_profile.gd:49`（`hero`/`heroes`）、`:204-213`（校验）、`:650-679`（`hero()/heroes()/hero_ids()/set_hero()`，`set_hero` 里「英雄表里有的直接给」，即已等同免费）；`:700/:702` 把 hero 记进 live 锁（主干不需要）。
在 `scripts/raid_profile.gd` 加：
- `_fresh()` `:55-58` 加 `"hero": "yujian"`（id 不改名：存档 / 联机握手里用的就是 yujian = 镇岳）。
- `_fix_types()` `:101-124` 加：`hero` 不是 String 或不在 `hero_ids()` 里 → `"yujian"`。不需要 `heroes[]` 拥有列表（全免费，`hero_ids()` 即全集）。
- 新函数（hero_defs 用运行时 `load`，避免 preload 链变长；hero_defs 只 preload heroes/def_*，def_* 无 preload，不成环，preload 也行）：
```gdscript
const HERO_DEFS := "res://scripts/hero_defs.gd"
static func hero_ids() -> Array:
	return (load(HERO_DEFS) as GDScript).call("ids")
static func hero() -> String:
	return str(data().get("hero", "yujian"))
static func set_hero(id: String) -> String:
	if in_raid():
		return RAID_LOCK
	if not hero_ids().has(id):
		return "还没有这位英雄"
	data()["hero"] = id
	save()
	return ""
```
- 可选一次性迁移：`_load()` 里没有 `hero` 键且 `user://xiuxian_ex_profile.json` 存在时读它的 `hero` 带过来（只读，不删那个文件；extraction-pvp 分支还要用）。
- 不升 VER（新增键有缺省，老档 `_fix_types` 补上即可）。

### 2.7 要改的 ExProfile 调用点（英雄相关，换成 raid_profile）
| 文件:行 | 现在 | 改成 |
|---|---|---|
| `main.gd:796-801` | load ex_profile.hero() | `Profile.hero()` |
| `ex/hero_select_ui.gd:23` | `const ExProfile := preload(ex_profile)` | preload raid_profile |
| `ex/hero_select_ui.gd:196-201` | `ExProfile.hero_ids()/hero()` | `Profile.hero_ids()/hero()` |
| `ex/hero_select_ui.gd:1135` | `ExProfile.set_hero` | `Profile.set_hero` |
| `ex/meta_prep.gd:19, :90, :364, :700` | `ExProfile.hero()` | `Profile.hero()`（meta_prep 其余装备栏归 B/D 报告） |
| `level_select.gd:341-396` | 入境页英雄行 `ep.hero_ids/data().stats/hero/set_hero` | 换 raid_profile（`stats.raids` 在 raid_profile 里也有：`_fresh :57`）；或主干直接删这行（英雄只在主城「英雄」入口选） |
| `player_plate.gd:397-410` `_hero_info` | 先 `player.hero_id`，没有再 `_ep.hero()` | 主干上 player.hero_id 恒非空，可直接删 `_ep` 兜底；`:416-424` 段位 / 灵石归 meta 报告 |
| `ex/ex_lobby_ui.gd:522/712/738/820/1104` | — | 主干若删 ex_lobby_ui 则无需改；若保留，同上替换 |
| `lan_presence.gd:22,64-67` | 只读 rank | 不归本报告；英雄名走 `HeroDefs`（`:196/:273`）已与存档无关 |
`hero_select_ui.apply_to_player`（`:1153-1162`）、`level_select._pick_hero` 里的 `p.set_hero(id)` 保持——它们只在主城里（level == null）换人，进图前 `_apply_combat_mode` 再按存档设一次。

### 2.8 自检要跟着改
- `hero_selftest.gd:137` `check(player.realm_idx == 2 and hero_base()==18)` → 改成 `is_equal_approx(player.hero_base(), CS.base(player.realm_idx))`，再加一条：`set_realm(5)` 后 `hero_base()==52`、`mp_max()==CS.mp_max(5)`、`hero_id` 不变、`realm["lines"]` 仍是英雄配色。
- `hero_selftest.gd:100-101 / :633-642` 打印 / 断言 `heroes_on` 可保留。`:650-660` 对照 legacy / hero 的 `shown_dmg`：删英雄分支后两者应相等，改断言。
- `pvp_rules_selftest.gd:76-78`：先 `set_hero` 后 `set_realm(realm)`；以前 set_realm 被吞掉（双方实际都结丹），改后真生效 → 两开时要给 a / b 同一个 `--pvp-realm`，否则数会多出 ×1.08^差。基线数要重量。
- `tsb_show.gd:141/:208` 用 `hero_base()`，自动正确，不用改。
- `ex/ex_selftest.gd` / `ex_lobby_selftest.gd` 随 ex 栈留在 extraction-pvp 分支。

---

## 3. 风险 / 待定

- **D1 炼气 / 筑基能不能用英雄**：`kit_base._air()`（`kit_base.gd:36-39`）→ `player.enter_air_combat()`（`player.gd:1030-1033`）要求 `is_light_mode()`。若英雄境界表照抄 `LIST[0/1].mode`（SWORD / WIND），炼气 / 筑基英雄**四个技能全被拒**、只能打地面老连段。推荐 `_hero_realm()` 强制 `mode = LIGHT`（升限 `ceiling` 仍按境界：炼气 25 米、筑基 80 米，`player.gd:1517/:1550` 空战里也生效，不会飞飞上天）。这对三位英雄一样，不构成强弱；但英雄在炼气就能空战，和老默认角色（结丹起）不同——需要主控确认。
- **D2 遁速 / 闪现**：推荐跟境界（12→210 m/s；3456 米循环大世界靠它）。若想保留英雄手感可 `speed = maxf(realm.speed, fly_speed)`，三位都是 28，不产生强弱。boost/rise 同理（英雄 1.4/7 vs 境界 1.3~1.5 / 2~18），推荐跟境界，所以没放进 HERO_LOOK_KEYS。
- **R1 Realm.COMBAT 档位会开始作用于英雄**：`air_melee._prof()`（`:842-843`）按 `player.realm_idx`，`kb` 炼气 0.8 → 大乘 1.72。英雄的连段 / 浮空追击是按结丹 1.0 调的，大乘击退 ×1.72 可能接不上连环 / 追斩，炼气 ×0.8 可能打不出空间。这是 realm-tier-differentiation 的既定效果（各境界拉开），但需格斗专项验证；如要压，在 air_melee 里英雄档 `kb` 封 1.0、其余（fx/burst/stop/shake/clash）照境界——air_melee 归其他会话，建议提给他们，不在本次解耦里动。
- **R2 flair 固定 1**：`air_melee.flair()`（`:836-838`）英雄档用表里的 1，老角色按境界 0~5（化神起瞬步、炼虚起分身补刀、合体乱舞、大乘剑雨）。英雄到高境界不会有这些「境界花样」，三位一样无强弱；是否改成 `max(hero flair, realm-2)` 由格斗专项定。
- **R3 大罡剑阵 / 剑诀 / 连发 / 飞剑阵**：英雄档 R 交给 kit（`gate_array.gd:100-102`、`player.gd:860-863`），老角色的大乘专属 R、Z/X/C 剑诀（`air_melee.gd:882-884`）、长按连发对波（`air_melee.gd:3309`、`air_foe.gd:1745`）英雄都没有。若主干想保留老默认角色作为第四个可选项（id ""，「御剑」原版），`set_hero("")` 分支（`player.gd:466-473`）已完整可用；Profile.hero() 允许存 "" 并在选择界面加一张卡即可。需主控决定。
- **R4 PvP 恢复境界差**：删 heroes_on 分支后，联机 PvP / 大世界互殴回到每境 ×1.08（`CS.PVP_REALM_ADV`），擂台回到 `arena_adv` 按等级 ±12%（这条英雄档下本来就生效，只是 lv 拿错了）。这是老主干规矩，符合「数值跟境界走」。
- **R5 死亡规则**：`set_hero` 每次复位 `regen_k=1 / lethal_fn / 无敌`；重伤倒地（`set_downed`）和 `regen_k=0` 是 ex_level / extract_manager 设的。新图改跑老系统后别再设这些（地图报告负责），英雄侧不用改。
- **R6 联机兼容**：英雄 id 仍在握手里（`net.gd:189/217/324/373-376`、`arena_net.gd:159/186`、`remote_player.gd:32/71/144`、`lan_presence.gd:162/196`），协议不变；但对方的伤害现在按对方真境界 base 发过来，两端都要是新包（老包会以结丹 18 发、以 realm_idx 2 报境界），换包要一起换。
- **R7 远端木偶**：`net.players[id]["realm"]` 以前英雄档恒报 2，`raid_manager` 的 PvP 境界差、`arena_duel.gd:453` 的 `_rival_realm` 都读它——改后报真境界，正是想要的。
- **R8 hero_doll / hero_select_ui 展台**：用 `HeroDefs.TIER` 选装束（只在 `--block-hero` 方块人模式下可见差别），保留常量即可。
- **R9 kit_yujian.gd / kit_canghong.gd（scripts/ 根目录老版）**：HEROES 已不引用（用 heroes/kit_*），但 `hero_selftest.gd:14`、`net.gd:952`、`warmup.gd:45` 还 load `kit_canghong.gd`。不影响本次，别顺手删。
- **R10 存档测试模式**：raid_profile `test_mode()` 用另一个存档文件，自检里 `Profile.hero()` 恒默认 yujian；自检若要别的英雄用 `--pvp-hero-*`/`--tsb-show=` 直接 `set_hero`，不经存档。
