Changes in my four files are done, and each one passes `--check-only` with no errors. But my change breaks one other file: `scripts/main.gd` (the main scene script) no longer parses, so the game won't load until line 6378 is updated.

**needs_from_others (blocking first)**
- **`scripts/main.gd:6378` (blocking):** it calls `rd.kill_exp(1, 1.0)` with two arguments. The spec makes `ri` required, so this is now a parse error: "Too few arguments for kill_exp()". The one-line fix is `rd.kill_exp(1, 1.0, rd.here_ri)`. I left `ri` required as the spec says; if nobody owns main.gd, the fallback is to give `ri` a default of -1 meaning `here_ri`.
- **`scripts/raid_hud.gd`:**
  - Line ~660 still shows `sup_dmg_k()` as the 天道压制 multiplier, which is now always ×100%. It should show the 心得 ×25% factor instead.
  - Line ~665 sets the 朱砂 danger color with `r.lv > mgr.lv + 2`. It should be `mgr.here_tag > player.realm_idx`.
  - The info line still says 「怪物 Lv.N」 and should become 「妖兽 X期」, using `mgr.here_tag`.
- **Display group:** the other 主城 damage numbers (enemy_dummy, swordsman, boss_demon) need the same display-only scaling I added for air_foe. Damage numbers still need the minimum of 1.
- **Main-tree raid_mob consumers:** `_tasks/ui_kit/mock_raid.gd` in the main tree has its own `sup_dmg_k()`. It still exists here, so no break.

**`scripts/raid_manager.gd`**
- **Mob stats (`_spawn_mob`):** HP and attack use the spec formula (`HP_CONV` / `ATK_CONV` × `CS.mob_s_hp` / `mob_s_atk` × elite). `dmg_in` and `atk_out` are bound to the target via `player_dmg_vs.bind(m)` and `to_player_from.bind(m)`.
  - Lair bosses use `Prog.boss_level(Prog.lair_tag(ri), local + 2)`.
  - Wandering bosses use `Prog.boss_level(Prog.mob_tag(ri, local), local + 1)`.
  - Guards, rival-feed mobs and camps already go through `_spawn_mob`, so they follow automatically.
- **Damage functions:**
  - New `_target_scale(t, k)` reads `region` and `lv` from a mob, or the `region` meta and `lv` from an AI rival. If there's no target it uses `here_ri` / `here_lv`. Nothing is cached.
  - New `player_dmg_vs` (also records `dmg_ratio`) and `to_player_from`. The old `player_dmg(d, _pvp)` and `to_player(d)` stay as same-level fallbacks.
  - `sup_dmg_k()` now always returns 1.0, and its toast text was updated.
- **Puppets and network mobs:** `_on_puppet_hit` uses the puppet's own region and level. For a mob attack with no puppet built yet, `net_take_hit` falls back to the player's current spot.
- **Insight:** signatures are now `kill_exp(mob_lv, k, ri)` and `add_insight(mob_lv, k, from, kind, ri)`, with all arguments required, and every call site passes `ri`. 天道压制 is now judged by the mob's region.
- **`net_mob_died`:** it reads the region from the puppet before erasing it, falling back to `Data.region_at`.
- **Anti-carry gate (spec I):**
  - `net_mob_take` records a `hi_realm` meta (the highest-realm remote player who hit the mob).
  - `_carry_k` applies the ×0.25 in both kill paths, and not again if the player is already suppressed. A one-time toast explains it.
- **PvP:**
  - `net_deal_hit` sends `CS.pvp_hit` bar points and shows `CS.pvp_shown`.
  - For hits from real players, `net_take_hit` skips `to_player`. It runs `_pvp_clamp` with all three caps scaled by `CS.pvp_cap_k`, then applies `CS.pvp_guard`.
- **AI rivals:** use the spec HP and `prey_dmg` formulas, `dmg_mul` via `CS.rel_bar_k`, and `look_i = mob_tag`. They are bound to `player_dmg_vs`, and their insight and loot use the region and tag.
- **AI allies:** use the spec HP and `prey_dmg` formulas, and `set_level` now also updates HP.
- **Danger warnings (spec F):** `here_ri` and `here_tag` are updated in `_update_here`. The region title and a once-per-tier toast now use `tag > realm`, and the toast resets on region change. All new strings use only characters present in the bundled fonts.
- **Pills in the raid:**
  - Pills the player can't take get no 「服用」 button.
  - `use_item` enforces `pill_use_err`.
  - `eat_count`, `eat_all` and the eat queue only take edible pills. Pills still eat at the bottleneck (the extra carries over). Nothing is consumed once the overflow is full (「修为已满，先去渡劫」). One-click eating goes largest first.
  - `Items.pill_exp_now(it, player.realm_idx)` is used throughout; all 丹毒 text is removed.
  - The heal float text shows real HP (`heal × CS.hp(lv) / 100`, formatted with `NumFmt`).
- **Tribulation:**
  - On success, overflow carries into the new realm via `Prog.carry_over` plus the perfect bonus, and `_cult_changed` re-runs after `_end_trib`.
  - On failure, xp becomes `max(xp − need × 0.5, 0)` and a 60 s `_trib_hold` starts; it auto-retries afterwards if still at the bottleneck. GM tribulations skip the hold.
  - `_bottleneck` warns 「还有 N 颗X期丹，突破后不能再服」 and, if the player can still eat, holds the tribulation 8 s. The tribulation also waits for a running one-click queue to finish.
- **Loot:**
  - The lair chest adds `Items.overlord(lair_tag)` with probability `OVERLORD_P[tag]`.
  - Mob loot passes `pill_realm = mob_tag(ri, m.lv)` through the new optional `_loot(..., pill_realm)`.
  - `_swap_out` values edible pills ×3.
- **Power toasts:** level-up, breakthrough and equipping or unequipping a 法宝 now show 「战力 A → B」.

**`scripts/air_foe.gd`**
- `set_level(n, dmg, hp_v := -1.0)` now scales HP proportionally.
- `_take` and `receive_hit` accept `info.real` to skip `dmg_in`.
- Damage numbers on 主城 opponents (`raid == false`) are display-only scaled to `dmg / CS.base(realm) × CS.unit_same(hub lv)`. HP loss, the 擂台 and in-raid rivals are unchanged.
- The `region` meta needed no code in air_foe itself; `RM._target_scale` reads it. It's documented next to `lv`.

**`scripts/ally_brain.gd`:** an ally hitting an AI rival now deals direct real damage (`dmg × DMG_K`, the same scale as `prey_dmg`) instead of going through the player's `dmg_in`.

**`scripts/raid_mob.gd`:** comments only (correct elite multipliers, what `dmg_in` / `atk_out` are bound to, and a note not to name a field `def`).

**Risks**
- The network protocol has no version, so old and new builds in the same LAN room will mis-score PvP hits. I did not touch `net.gd`.
- The PvP side paths in `air_melee.gd` (28-point clash loss, 8-point ground slam) are unchanged.
- Rivals now wear realm outfits by region tier (`look_i`) instead of the player's realm.
- After a failed tribulation with a large overflow, the auto-retry 60 s later spends the 布阵 lingshi again without asking.
- `ally_brain` keeps an unused `Data` preload.
- Nothing was run beyond `--check-only`; I did no playtest or self-test runs.