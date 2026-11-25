Display & hub UI group: everything on my file list is done and all 13 changed files pass `--check-only`. I did not run any self-tests or screenshots.

**Changed files** (all in `D:/GodotProjects/修仙游戏_iso_numbers/scripts/`, LF kept, dated 2026-11-23 notes added)
- `vfx.gd`: preloads `num_fmt.gd`. `damage_number` now writes `NumFmt.fmt(maxf(value, 1))`. New `static func damage_text(pos, text, color)` uses the same font size and outline, so warmup can prewarm a fixed string.
- `hud.gd`: combo line is `"伤害 %s" % NumFmt.fmt(combo_dmg * _combo_ratio())`. `_combo_ratio()` reads `plate.raid` and then `get("dmg_ratio")` safely; it returns 1.0 in the hub or when the value is missing.
- `player_plate.gd`
  - `power()` and the `pw` parameter of `set_values` are now float.
  - The 气血 text shows only `NumFmt.fmt(current)` once `hp_max >= 10000`, otherwise "当前/上限" as before.
  - 战力 is split into two Labels: the number in the brush font (25) and the unit (`_power_u`, body font 18) next to it. They are split by a new `static split_unit(s)`.
- `warmup.gd`: prewarms with `Vfx.damage_text(at, "0123456789.万亿+-", col)`.
- `raid_hud.gd`
  - Info line is "妖兽 X期". The tag comes from `mgr.get("here_tag")`, falling back to `Prog.mob_tag(region, here_lv)`.
  - The danger colour now triggers when the tag is above the player's realm (or less than 180 s left).
  - Suppression line reads "天道压制 心得×25%".
  - Settlement: "结转已存满，余下 X 心得散去" only when `ins_lost > 0`. Otherwise, if there is overflow, it shows "已结转 +X，突破后带进下一境界" (from `Prog.overflow_of` on the saved profile).
  - 灵石 numbers and the 心得 chip use `short_num`.
  - Extra: pills that `Prog.pill_use_err` rejects get no 服用 button, and the reason is put in front of the detail text. The bag panel also rebuilds when the realm changes.
- `insight_fx.gd`, `item_view.gd`: numbers go through `Prog.short_num` (`item_view` now preloads Prog).
- `hall_pills.gd`
  - Counts and eats only edible pills, biggest first, one whole stack per 0.16 s tick (key: name, realm, min_realm, grade).
  - Keeps eating at the bottleneck. When `used == 0` it stops without consuming that pill and shows "修为已满，先去渡劫".
  - Shows how many pills are locked by realm. All 丹毒/药效 text is gone. The label shows "已满 · 结转 +X".
  - Shows a merged "战力 A → B" float 0.6 s after the last level-up.
- `hub_hall.gd`
  - Meditation texts use `NumFmt.fmt1`, with no 丹毒. The panel shows "已满 · 结转 +X" or "修为已满，先去渡劫".
  - Breakthrough success: `Prog.carry_over` plus the perfect bonus go into `profile_add_xp`. The toast adds "结转修为 +X", "战力 A → B", and a notice if the carry already fills the new realm.
  - Breakthrough failure: `xp = max(xp - need*0.5, 0)`, reworded to "修为退回半级" because 损 is missing from the fonts.
  - A meditation level-up also floats a 战力 change.
  - `--hub-shot` expectation is now "gain(5) at the bottleneck = 5; gain(5) at `overflow_cap` = 0".
- `abode_ui.gd`: `_stack_key` adds `|realm|min_realm|grade` for pills, written exactly like `raid_profile.stack_key`.
- `enemy_dummy.gd`: new `static func shown_dmg(n, dmg)` returns `dmg / CS.base(realm) * CS.unit_same(lv)`, with realm from the `player` group and lv from `Profile.cult`. Hub damage numbers use it; hp logic is unchanged.
- `swordsman.gd`, `boss_demon.gd`: their damage numbers call `shown_dmg`.
- `num_fmt.gd`: not touched.

**Deviation:** the warning about remaining current-realm pills ("还有 N 颗X期丹，突破后不能再服") is a separate `_break_pill_warn()`, not part of `_break_missing`. `_break_missing` decides whether the breakthrough is allowed, so putting the warning there would block it. The warning shows on the step-on toast and the meditation panel.

**needs_from_others**
- `main.gd:6378` currently fails to compile ("Too few arguments for kill_exp(), expected 3") after the G1 `kill_exp` signature change. Whoever owns `main.gd` needs to pass the region.
- G1 `raid_manager`:
  - Provide `dmg_ratio`; until it does, combo damage shows the raw number.
  - Provide `here_tag` (I fall back if it is absent).
  - Make `use_item` / `eat_count` check `pill_use_err`; `bag_actions` still offers "use" for pills, and I only hide the button.
  - Add the raid-side 战力 toasts on level-up, breakthrough and gear change; I did not touch those.
- G2 `raid_items`: `desc` / `badge` texts ("气血 +25%", "X期 +1.234万").

**Risks**
- Plate number/unit alignment and the 76 px 气血 box are not checked on screen. Run `plate_test` / `raid_hud_test` (main tree) with `--web-fonts` at 1701x900.
- `mock_raid.gd` in the main tree lacks `here_tag` / `dmg_ratio`; the fallbacks cover it.
- All new string glyphs were checked against the body and patch fonts; none are missing, and none of 易毙荐溢宁兆京 are used.