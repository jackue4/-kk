All my files are edited and compile cleanly with `--check-only`. `combat_table` passes under the new rules. `--pace-byrealm` has not been run yet, and the calibration below still uses the old `pace.json`, so don't write any constants back from it yet.

**Changed files**
- `D:/GodotProjects/修仙游戏_iso_numbers/_tasks/numbers_sim/combat_table.gd`
  - Uses `CS.raid_hit` / `CS.to_bar` with the mob's own scale. Mob stats come from `CS.HP_CONV` / `ATK_CONV` / `mob_s_hp` / `mob_s_atk`. The lair boss level comes from the real lair position (`lair_tag`, `boss_level`).
  - The table now has one row per level in each realm. Power shows as float (bare and fully geared), with a check that it rises every row.
  - New cross-realm table: one realm higher kills lower-region mobs in at most 1 hit and takes at most 1%; one realm lower needs at least 9 hits.
  - PvP section rewritten: `CS.pvp_hit`, caps scaled by `pvp_cap_k`, guard applied after the caps. Time-to-kill: 2.80 s same realm, 1 realm apart 2.57 / 3.12 s (ratio 1.21), gear "攻" capped at ×1.30.
  - Guard rails, after reading critic_math #5:
    - Level 1: hits ≤ 9 (≤ 12 for brutes), bar ≤ 15%, lair boss ≤ 36% / 48% per hit. These pass (34% / 46% at 炼气 1).
    - Level 2: floor ≥ 1.5 hits, average 2.5–9 hits, bar 4–14%. 筑基 is relaxed to 1.0 / 1.5.
    - Level 3: only ≥ 0.8 hits and bar ≥ 2.5%.
  - I did not put the strict "≥ 1.5 at level 3" check in. Under the new curve it fails for 炼气, 结丹 and 化神 too (1.08, 1.09, 1.20 hits), not just 筑基.
  - I also overwrote `_tasks/numbers_sim/combat_table.md` with the new table. The old baseline is still in the official tree.
- `D:/GodotProjects/修仙游戏_iso_numbers/_tasks/numbers_sim/life_sim.gd`, implemented as spec v2 J:
  - Pace rows with `"by":"realm"` are keyed by realm and level-in-realm; for those rows `avg_k` is back-solved from the measured `insight_pm`. Old per-region files still load.
  - Depth is derived from `REALM_MOB_LV` ± 0.06, and the sim warns if a mob's tag isn't the player's realm.
  - Insight calls `Prog.insight(lv, k, ri)`, with the kb/kg overrides applied as a ratio.
  - Pills are a list of dicts. Eating goes biggest first, filtered by `pill_use_err`, and stops without consuming the pill once overflow is full.
  - `Prog.carry_over` runs on breakthrough. A failed breakthrough subtracts half the requirement. Pills locked to a past realm are sold.
  - No 丹毒. Lair and wandering bosses only count when `lair_tag(ri) <= realm`. Overlord pills drop at `OVERLORD_P` × `ovl`.
  - New `--o` keys `ovl:` and `ovp:` work alongside `pill:`. `params.PILL_EXP` stays in the JSON.
  - Source shares are now summed in pre-rework units, so they compare with the old baseline.
  - Extra: `--o=pdep:N` (default 0, i.e. as specced) puts each profile's depth preference back, kept inside the player's own tag.
- `D:/GodotProjects/修仙游戏_iso_numbers/_tasks/numbers_sim/pill_table.gd`: rewritten per realm using `pill_exp_now`: share of drops you can eat, average exp as % of the realm total, grade mix, overlord value. Also a region × depth table showing which realm's pills drop.
- `D:/GodotProjects/修仙游戏_iso_numbers/scripts/raid_pace_test.gd` (CRLF preserved):
  - `DUMMY_HP = 1.0e13`.
  - `--pace-combat` units are damage ÷ `CS.raid_hit(base, r, lv, 0, rd._target_scale(dummy, CS.ATK_K_MOB))`, and the expected-damage line passes the mob's scale.
  - New `--pace-byrealm[=0,1,...]`: levels 3r+1 to 3r+3, 3 minutes each by default, region `REALM_REGION[r]` at the `REALM_MOB_LV` depth. The bot only hits mobs with `mob_tag <= realm` within 200 m of home. Output rows carry `"by":"realm"` plus `realm`, `lv`, `pill_ok_pm`, `pill_ok_exp_pm` and `tag_skip_pm`.
  - Pill tally uses `pill_exp_now`.
- `D:/GodotProjects/修仙游戏_iso_numbers/scripts/main.gd`, `--raid-trib` only (CRLF preserved): `add_exp(1e9)` becomes the sum of `Prog.xp_need` up to the bottleneck, plus 1. `kill_exp(1, 1.0, rd.here_ri)`.
- `D:/GodotProjects/修仙游戏_iso_numbers/scripts/raid_selftest.gd`: shop pill name from `Items.rpill(0,0)`, the eat-all test uses `rpill(0,0)`, `add_exp(xp_need(top)+1)`, and the insight injection is now 10% of the cap.
- `D:/GodotProjects/修仙游戏_iso_numbers/scripts/arena_selftest.gd`: the "大世界那套" comparison line now uses `CS.pvp_hit` instead of `to_bar(atk)`. I made this edit even though the brief said "only if needed"; the old line still compiled but now printed a formula PvP no longer uses.
- Every other `*selftest*.gd` and `hitch_probe.gd` compiles without changes.

**life_sim results with the old `pace.json` (runs=40)**

| Profile | Hours to 大乘 | Target |
|---|---|---|
| Normal | 19.1 h (心得 31% / 丹 44% / 离线 24%) | 15.9 h |
| Casual | 17.3 h | 16.8 h |
| Hardcore | 19.5 h | 14.8 h |

- With `pdep:1`: casual 18.7 h, normal 19.1 h, hardcore 17.0 h.
- With `--o=pill:1.5,ovp:1.5`, normal reaches 15.9 h, but pills rise to 54% of the total.
- These are not ready to write back: the old pace file doesn't capture faster kills within a realm. `--pace-byrealm` needs a real windowed run first, roughly 15–20 minutes of GPU.

**needs_from_others**: nothing blocking. Callers outside my files:
- `Data.make_pill(t)` in main.gd's zoo demo (about line 6033 and 6041), `warmup.gd:428-430` and `shenshi_selftest.gd:111`. These are display-only and go through `tier_pill` without warnings, so I left them as they are.
- Every other caller of the changed APIs has already been updated by its owner.

**Risks**
- Search sites near the 坠魔谷 lair and deep in 坠魔谷 use `pill_realm_at`, so they drop 大乘-locked pills (depth 1 counts as level 24, tag 7). The lair boss's own loot correctly uses the boss's tag; life_sim models both the same way the game does.
- The new pace modes and the units change are compiled but not exercised at runtime, since I didn't run any windowed self-tests.
- Since my edits, `main.gd` has grown to 6639 lines and `raid_pace_test.gd` to 1398, both still all-CRLF (the working-tree format; git autocrlf stores LF in the index).