Review of `numbers_spec.md` for integration risk. All paths below are relative to `D:/GodotProjects/修仙游戏_iso_numbers/`. While I was reading, the snapshot was being edited: `combat_stats.gd` (18:50), `progression.gd` and the new `num_fmt.gd` already hold partial implementations. Where a finding touches that in-progress code, I say so. Numbers come from python scripts in the scratchpad `calc/` folder (`rv_ct.py`, `rv_mig.py`).

## Prioritized problems

### 1. Lair bosses fall in the top tag of the two multi-realm bands, so their drops reach the wrong realm
- **What is wrong:** a lair boss's level is its spot's level +2, and `mob_tag` clamps to the band's top. In the two bands that span more than one realm (草原 [0,1] and 坠魔谷 [5,7]), the boss lands one or two realms above the realm that needs its drop. The realm that can kill it doesn't need it.
- **草原 lair:** it sits at (-210,170), about 270 m out. With `MEADOW_DEPTH_R` = 480 that is depth 0.5625, so the boss is lv 5, tag 1. A 炼气 player at lv 3 takes 115% bar per melee hit and needs about 395 units to kill it (the old numbers were 24.5% and 131). Its fragment, `frag_to(0)` = 筑基丹残片, is only reachable by 筑基 players, who no longer need it.
- **坠魔谷 lair:** the boss is lv 26, tag 7. A 炼虚 player at lv 17 takes 1668% per hit and needs 19,653 hits. A 合体 player at lv 20 takes 228% per hit and needs 1,084 hits. Both its fragment `frag_to(4)` = 合体丹残片 and the spec's "min_realm = 所在位置的境界档" (7)霸主精魄 are usable only by 大乘.
- **combat_table fails:** `combat_table.gd` will FAIL the `bmelee ≤ 36` check for 炼气, 炼虚 and 合体. Separately, 筑基 vs 噬金虫 comes out at 1.22 hits, below the 1.5 floor.
- **Fix:** in `mob_scale` (or `_spawn_mob`), when the mob is a lair boss (`lair ≥ 0`), force `tag = Prog.frag_to(ri) − 1`, which gives [0,2,3,4,5].
  - It stays a pure function, because puppets get `lair` from batch field e[9] (`raid_manager.gd:545,585`).
  - Use the same table for the 霸主 `min_realm`.
  - Check: 炼气 lv3 vs that boss gives 18% per hit and 85 units; 炼虚 lv17 vs the 坠魔谷 boss gives 29% per hit and 159 units.
  - In `combat_table`, compute the boss level from the real lair position (`depth_at` of the POI, plus 2), not `mob_level(ri, 0.9) + 2` (which is 7 for 草原; the real boss is lv 5).

### 2. Insight tag defaults and copies silently use the wrong scale
- **In-progress code:** `progression.gd` now has `insight(mob_lv, k, tag := -1)`, and the default falls back to `realm_of(lv)`, not the band tag.
- **Callers left unchanged would overpay:** `raid_manager.gd:362` `kill_exp`, which feeds `add_insight` at `:754`, `:1703` and `:1984`, plus `main.gd:6378`.
  - 黄枫谷 lv 10–11 would get XP_SCALE[3]/[2] = 5.7×.
  - 血色 lv 13–14 would get 5.7×.
  - 云梦 lv 16–17 would get 8.5×.
- **life_sim has its own copy:** `life_sim.gd:284` `_ins()` reimplements the formula with no XP_SCALE at all, so kill insight comes out divided by 1.23 up to 649,363. It is used at `:201`, `:214` and `:233`.
- **Fix:**
  - Change the signature to `insight(mob_lv, k, ri)` and compute `mob_tag(ri, lv)` inside, so a caller cannot pass a wrong tag.
  - Make `kill_exp` and `add_insight` take `ri`.
  - Make `_ins` call `Prog.insight` and apply only the `kb` / `kg` overrides.

### 3. Old pill units leak through the `Items.pill(tier)` wrapper and the reverse lookups
- **The wrapper:** it maps tier to realm as [0,2,3,4,5]. Any roll site left unchanged now produces pills of a random realm instead of failing. For example, at `raid_search.gd:240-241` and `life_sim.gd:175`, about 18% of 草原 herb-site pills roll t1 and become 结丹 pills.
- **`Prog.pill_exp(tier, g)` is now realm-indexed:** in-progress code changed its meaning, but `raid_pace_test.gd:1304` still passes `tier`.
- **`life_sim.gd:367-373` `_pill_value`:** it tries t 0..4, finds no match, and falls back to `e0 × 0.3`. A 下品 炼虚 pill (5.0e6 exp) then sells for 1.5e6 灵石, which is more than `break_cost(6)` = 330,000, so `stuck_ls` disappears.
- **Fix:**
  - Have the wrapper `push_error` in debug builds.
  - Switch every roll site to `rpill(Prog.pill_realm_at(ri, depth), g)`.
  - Use `pill_exp_now` at `raid_pace_test.gd:1304`.
  - Make life_sim's `S["pills"]` a list of dicts, sell at `it["value"]`, and change `pills.sort()` at `:312` and `:346` to `sort_custom` (dicts cannot be compared).

### 4. life_sim puts 炼虚 and 合体 into the next band up, and misreads the existing pace.json
- **Depth model:** `life_sim.gd:188` uses `depth = P.depth + 0.45 × (realm − ENTRY)`.
  - 炼虚 lands at depth 0.35, which is lv 19, tag 6: insight 11.4× too high and only 合体 pills drop.
  - 合体 lands at depth 0.8, which is lv 22, tag 7: 17× too high and only 大乘 pills drop.
- **Lair branch:** `:214` calls `_ins(mob_lv+2, 14)` without checking whether the player can actually kill that boss.
- **pace.json:** the existing file already has a `realm` field, holding 0,2,3,4,5. The spec's rule "有 realm 字段时按境界" would then leave 筑基, 合体 and 大乘 on the default 4 kills/min, against 13.8–19.8 measured.
- **Fix:**
  - Set `depth = clamp((REALM_MOB_LV[r] − REGIONS[ri].lv + u) / DEPTH_LV[ri], 0, 1)` with u in ±0.45, and assert `mob_tag == r`.
  - Feed the same depth into `Items.roll` and `value_mult`.
  - Gate lair and 游荡首领 on `mob_tag(ri, boss_lv) ≤ realm`.
  - Mark the new probe's rows with an explicit `"by": "realm"` key and keep reading old files by region.

### 5. Raising the pace-combat dummy to 1e30 breaks the measurement
- **What is wrong:** `_units` (`raid_pace_test.gd:425`) measures `(hp0 − hp) / atk`. At 1e30 the smallest step a float can represent is 1.4e14, so every hit below about 7e13 subtracts nothing (a 大乘 hit is about 2e9). Units would all read 0.
- **Fix the dummy:** use `hp = 1e13`. That step size is 0.002, and a 40 s run deals at most about 4e11.
- **Fix the unit definition:** the spec says mob defense is a pure function of (region, lv), so a "zero-defense dummy" cannot exist. Divide by `CS.raid_hit(base(r), r, lv, 0, s_def(dummy))` instead.
- **Fix the expected-damage line:** `:609` `CS.to_bar(mob.atk, lv)` must pass the mob's `S_atk`.

### 6. Binding the damage callables to targets that aren't plain owned mobs
- **AI rivals:** AirFoe has no `region` property; `spawn_rival` stores it as meta (`raid_manager.gd:1808`). If `f.dmg_in = player_dmg_vs.bind(f)` reads `m.region`, the first hit raises a runtime error.
- **If rivals keep the old `player_dmg`:** it uses the same-level factor 0.741. A 化神 lv14 player hitting a 黄枫谷 lv9 rival should get 0.989; a low-realm player hitting a high-band rival gets about 2700× too much.
- **Puppets:** they are built in `net_mob_apply` (`:568-576`) and never pass through `_spawn_mob`, so any cached `m.scale_*` field keeps its default and silently means "same level".
- **Name clash:** `raid_mob.gd:39` already has `var def: Dictionary` (the species dict, used by `def["cols"]` and `def.get("boss")`). Calling the new defense field `def` would clobber it.
- **Fix:** one helper, `CS.target_scale(t)`, that reads `t.region` for a Mob or `t.get_meta("region")` for an AirFoe, plus `t.lv` (and `lair`), computed on every call and never cached. Name the fields `s_def` / `s_atk`.

### 7. Network fallbacks and the PvP protocol
- **Missing puppet:** `net_mob_attack` → `net_find_mob` returns null when the puppet hasn't been built yet: more than 220 m away, or skipped by the `camps.traveling` / `fresh ≥ 3` throttle (`:563`). `to_player` then falls back to same level. Example: a 炼气 lv3 player hit by a lv4 筑基-band mob gets factor 0.296 instead of 0.536, so 45% less damage.
  - **Fix:** fall back to `(region, here_lv)`.
- **PvP protocol:** `_hit` carries no version (`net.gd:807`).
  - Old attacker, new receiver: the old side sends real damage (29+), which is read as bar points, so every hit lands at the 22 cap.
  - New attacker, old receiver: 9 bar points go through the old `to_bar`, giving about 2.6.
  - **Fix:** add a `PROTO` value to the state packet and ignore PvP hits from peers whose `PROTO` differs.

### 8. Overflow carry-over edge cases
- **No "overflow full" stop:** at `xp ≥ xp_need(top) + realm_total(r+1)` (52,542 for 炼气), these loops keep eating pills for 0 gain:
  - `hall_pills.gd:224` and its `_process`
  - `raid_manager.gd:2732` (`_eat_q`)
  - `use_item` at `:2226`
  - life_sim `_eat`
  - **Fix:** add `Prog.room_left()` and gate on it.
- **Automatic re-tribulation in the raid:** a failure now does `xp −= 0.5 × need`. One raid's insight at the 炼气 bottleneck caps at 5,888, about 4× `need(3)` = 1,442, so the player stays at cap. The next pill runs `_cult_changed` → `_bottleneck` → `_try_start_trib` and spends `break_cost` again with no confirmation.
  - **Fix:** add a `_trib_fail_realm` latch.
- **No prompt after carry-over:** the success branch of `_on_trib_done` (`:920-933`) never calls `_cult_changed`. If the carry-over fills the new realm, no bottleneck prompt appears.
  - **Fix:** call it after `_end_trib`.
- **Settlement text:** keep the `raid_hud.gd:552-553` "散去" line, shown only when `ins_gain < ins`. The overflow cap still truncates.

### 9. VER 3 save migration rounding
- **炼气 bottleneck:** `xp × XP_SCALE` gives 1175 × 1.2272 = 1441.96. That is below `xp_need(3) − 0.01` = 1441.99, so a 炼气 save stuck at the bottleneck is no longer `at_cap` after migration. (Realms 1–6 happen to survive.)
  - **Fix:** `frac = xp / xp_need_v2(lv)`, then `xp = xp_need(lv)` if `frac ≥ 1 − 1e-9`, else `frac × xp_need(lv)`.
- **`_migrate_old`:** `raid_profile.gd:180` calls `Items.pill(t)`, which through the wrapper hands a fresh 炼气 profile 结丹-or-higher pills. Use `rpill(0, g)`.

### 10. The anti-carry gate (带人闸) has a hole, and the spec's call won't compile
- **The hole:** the gate is only in `net_mob_died`. A low-realm player's own kill path `_on_mob_died` (`:1703`) pays full insight even when a high-realm remote did the killing. Camps are built by whoever is nearest, so the carried player owns most camp mobs.
- **Lost information:**
  - The `hitter` meta is only set at `:648` and never reset when the owner hits.
  - `net.gd:844` passes only a `share` bool, so `last_hitter` is lost.
- **The spec's call:** `Data.region_at(pos)` takes `(x, z)`. Written as specced, the arity error breaks compilation of `raid_manager.gd`, and life_sim preloads it. Also, the region at the death position is not necessarily the spawn region.
- **Fix:**
  - Pass `last_hitter` through to `net_mob_died`.
  - Use `p.region` before `_puppets.erase`.
  - On `net_mob_take`, record the highest remote hitter realm in a meta field and apply the gate in both kill paths.

## Things the spec forgot that an implementer will hit
- **Danger indicator:** `raid_manager.gd:1180` and `raid_hud.gd:665` use `REGIONS.lv > lv + 2`. They should use `mob_tag(region, here_lv) > realm_idx`. As written, the deadly 300–480 m ring of 草原 never turns red for 炼气.
- **Combo damage:** making it "累加实伤" requires editing `air_melee.gd:3306` (`combo_dmg += dmg`, reset at 7 places), which the spec puts off-limits. Instead, store a real/raw ratio on RM inside `player_dmg_vs` and have `hud.gd:495` display `combo_dmg × ratio`.
- **Farm and 丹房 disagree:**
  - `farm_data.gd:104,111` (`use_line`) also indexes `Items.PILLS[t][0]`.
  - 赤阳芝 makes a 结丹 pill in 丹房 (`HERBS[REALM_REGION[2]]`) but a 筑基 pill in the farm recipe (`rpill(1,1)`).
  - Use one herb→realm table for both.
- **Overlord pill value is unspecified:** `_swap_out` (`raid_manager.gd:2084`) drops the cheapest item when the bag is full, so a low-value 霸主精魄 would be auto-dropped.
- **Realm lock in the raid:**
  - `bag_actions` (`:2193`) and `use_item` (`:2226`) both need the `pill_use_err` check. The `main.gd:6595` path calls `use_item(i)` with no action.
  - `eat_all` (`:2272`) needs the same filter.
- **`pill_exp_now` for pre-migration pills:** treating them as "当前境界" cannot read `Profile` from inside `raid_items` (that would be a preload cycle, since raid_profile → raid_items). Pass `realm` in explicitly.
- **AI allies:**
  - Ally HP is set once (`raid_manager.gd:1933`). `set_level(n, dmg)` (`air_foe.gd:604`, called at `:1962`) needs an HP parameter.
  - An ally hitting a rival still goes through the player's `dmg_in` (`ally_brain.gd:333`).
- **Preload rules:**
  - `raid_data.gd` must not preload `combat_stats.gd` (that would close a cycle Data→CS→Prog→Data), so put mob-stat helpers in CS, not in Data.
  - `main.gd:6112,6260` preload `raid_selftest.gd` and `raid_pace_test.gd`. Renaming any `CS`, `Prog` or `Items` symbol they use stops the whole game from loading.
- **Name collision:** `--pace-realms` already exists for `--pace-combat` (`raid_pace_test.gd:383,393`).
- **life_sim output:** keep the `params.PILL_EXP` key, which `pace.html:143-147` reads with `.join()`. `pill_table.gd:20-22` still reads `it["exp"]` per tier.
- **Leftover 丹毒 text:** `raid_items.gd:206` ("连服会积丹毒"), and `hub_hall.gd:1567` and `:1659` (dan-poison and efficacy text).
- **Merge risk:** the spec edits `raid_manager.gd` in at least 15 places, plus `net.gd`, and the 格斗专项 session is editing both in the main workspace. Plan a 3-way merge against `numbers_base_md5.txt`, or put the new logic in a separate helper script and keep the hooks in those two files one line each.