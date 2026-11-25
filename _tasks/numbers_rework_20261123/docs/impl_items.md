Everything in my file list is done. All six of my scripts in that list pass `--check-only`. meadow_level.gd doesn't compile yet, but the errors come from G1's unfinished raid_manager.gd, not from my change. Their dependents (abode_ui, farm_plots, farm_selftest, hall_pills, item_view, `_tasks/numbers_sim/pill_table`) also pass. A short headless script checked names, values, potency, lock text, how drops pick a realm, recipes per realm, save migration, stacking and auto-sell. Its output is at `C:/Users/CHENYA~1/AppData/Local/Temp/claude/31cb5b99151d1ce0/56892b15-dc20-4b69-bb00-518bf08dbf71/scratchpad/g2_check.txt`, and the script itself is `g2_check.gd` in the same folder. Files are still LF, and none of the 7 edited files contains any of 易毙荐溢宁兆京 (new strings included). Originals are backed up in `.../scratchpad/g2_orig/`.

**Changed files** (all under `D:/GodotProjects/修仙游戏_iso_numbers/scripts/`)
- **raid_items.gd**
  - New tables: `PILL_NAMES` (8 names, none collide with KEYS, HERBS, MATS or fruit names), `PILL_HEAL`, `TIER_REALM [0,2,3,4,5]`, `PILL_CRAFT_COST [20,40,60,160,400,900,1600,2800]`, `LEGACY_PREFIX "旧·"`. `PILLS` is now 8 rows in the same format.
  - `rpill(realm, grade)`: carries a `realm` field, `tier = REALM_TIER`, value formula from the spec.
  - `overlord(min_realm)`: "X期霸主精魄", grade 3, sell value 1.5 × the 极品 pill of that realm.
  - `pill(tier, grade)` is now a wrapper; it warns once in debug builds. `tier_pill()` does the same without the warning.
  - `pill_exp_now(it, realm := -1)` checks legacy_exp, then min_realm, then realm; with no realm it falls back to the passed realm or the save's realm.
  - Other helpers: `profile_realm()` (loads raid_profile at runtime), `lock_text(it)`, `craft_cost(r)`.
  - Texts: no more 丹毒; 气血 shown as +N%; lock text "处于X期时可服" / "X期及以上可服"; badge "X期 +1.234万". Icons clamp to 0..4.
  - `roll(..., pill_realm := -1)` falls back to `pill_realm_at(ri, depth)`. Shop still sells `rpill(0,0)` at 120 and `rpill(1,0)` at 380. `recipes()` gives one row per herb, realm from `herb_pill_realm(t, save realm)`, cost by realm.
- **raid_data.gd:** `roll_loot(..., pill_realm := -1)` passes it through. `make_pill` uses `tier_pill` (no warning). New `make_rpill(realm, grade)`.
- **raid_search.gd:** herb sites, vaults and urns all pick the pill realm with `Prog.pill_realm_at(site region, site depth)`.
- **farm_data.gd:**
  - New `herb_realm(t)` uses `Prog.herb_pill_realm`, so the farm and the 丹房 share one table.
  - `recipes()` loops over the 5 herbs, giving `rpill(r, 1)` at cost `craft_cost(r) × 2`.
  - `use_line()` builds pill names from `PILL_NAMES`.
  - Nothing indexes by `PILLS.size()` any more; `MID_COST` is kept but unused.
- **raid_profile.gd**
  - Save version is now 3, and `_migrate_v3` runs before `_recover_live`. It converts xp by the ratio rule: ≥ 1 − 1e-9 counts as at cap. Checked: a 炼气 save stuck at lv3 becomes 1442/1442 and is still at cap.
  - Old pills in stash, carry, ring and `live.carry` get `legacy_exp`, `min_realm = current realm`, and the "旧·" prefix. A notice tells the player.
  - `_fix_item` also converts `realm` and `min_realm` to int. `_migrate_old` uses `rpill(0, g)`.
  - `stacks()` now includes all pills, and `stack_key` adds realm / min_realm / grade.
  - `sell_junk` also sells pills whose realm is below the save's realm and that have no min_realm.
  - New `realm_pills(r)` counts the pills that stop being usable after a breakthrough.
  - I checked count / can_craft / craft: recipe inputs are only herbs, fruits and 残片, so no pill name can be eaten as an ingredient.
- **meadow_level.gd:** spawn radius is now 110~250 m.
- **progression.gd:** every name in section K was already there and behaves as spec v2 C says (once overflow is full, `add_xp` returns used = 0). I added `room_left(lv, xp, realm)`, `profile_room()` and `profile_carry()`; these are not in K.

**needs_from_others**
- **raid_manager.gd (G1)**
  - It doesn't compile right now: `add_insight` gets 4 arguments at lines 847, 1796 and 2077.
  - `_loot` should pass `pill_realm = Prog.mob_tag(ri, m.lv)` to `Data.roll_loot`.
  - The lair drop should add `Items.overlord(Prog.lair_tag(ri))` at chance `OVERLORD_P[t]`.
  - `use_item`, `bag_actions`, `eat_all` and the eat queue should filter with `Prog.pill_use_err`, and check `Prog.room_left` or `profile_room() > 0` before taking the pill.
  - `_swap_out` should count pills the player can eat at ×3 value; `_bottleneck` can use `Profile.realm_pills`.
- **abode_ui.gd:** `_stack_key` should call `Profile.stack_key` (its own key has no realm or grade).
- **hall_pills.gd:** filter with `pill_use_err(it, Profile.realm())`, pass the realm to `pill_exp_now`, and gate on `profile_room()`.
- **life_sim.gd:175:** still calls `Items.pill(roll_tier)`; it should be `Items.rpill(Prog.pill_realm_at(ri, depth), g)`.

**Risks**
- `Items.recipes()` and `FarmData.use_line()` read the save at runtime, so a headless tool that calls them will create the self-test save file.
- At higher realms, low-tier herbs make pills the player can no longer eat. That follows the spec's clamp rule.
- `roll()` no longer spends a random roll on tier for pills, so seeded test outputs will shift.
- `room_left` returns INF for 大乘 below level 99; don't pass it straight to the number formatter.
- The title font lacks 魄, · and 养. The body font plus its patch font cover every new string.
- The craft costs and the overlord value are my first-pass numbers.