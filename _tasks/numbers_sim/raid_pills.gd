extends "res://_tasks/numbers_sim/life_sim.gd"
## 按局统计修为丹（2026-11-24）：一局掉几颗修为丹、带出来几颗、回洞府吃了几颗、吃下去顶本级几成、升了几级。
## 用法：godot --headless --path . -s res://_tasks/numbers_sim/raid_pills.gd -- --runs=40 --prof=normal --pace=res://_tasks/numbers_sim/pace_realm.json
## 只统计没陨落的局；按「出发时的境界」分组；最后一次 _life 结束后打印累计（runs 从命令行读）

var _st := {}      # realm -> {n, seen, kept, eaten, exp_need, lv_up, cap_end, exp_lv}
var _done := 0
var _want := 60


func _life(P: Dictionary, seed_v: int) -> Dictionary:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			_want = int(a.get_slice("=", 1))
	rng.seed = seed_v
	var S := _new_state()
	var per_day := int(P["per_day"])
	while int(S["realm"]) < 7 and int(S["day"]) < 400:
		for i in per_day:
			if int(S["realm"]) >= 7:
				break
			var r0 := int(S["realm"])
			var lv0 := int(S["lv"])
			var need0 := Prog.xp_need(lv0)
			var seen0 := int(S.get("xp_seen", 0))
			var kept0 := (S["pills"] as Array).size()
			var eat0 := int(S["eat_in"][r0])
			var fails0 := int(S["fails_in"][r0])
			S["pill_exp_now"] = 0.0
			var raids0 := int(S["raids"])
			_raid(S, P)
			var seen := int(S.get("xp_seen", 0)) - seen0
			var kept := (S["pills"] as Array).size() - kept0
			_hub(S, P, float(P["hub_min"]) * 60.0)
			var died := seen == 0 and kept == 0 and int(S["raids"]) > raids0 and false
			if not _st.has(r0):
				_st[r0] = {"n": 0, "seen": 0, "kept": 0, "eaten": 0, "exp_lv": 0.0, "lv_up": 0, "cap": 0, "max_eat": 0, "max_lv": 0}
			var t: Dictionary = _st[r0]
			var eaten := int(S["eat_in"][r0]) - eat0 if int(S["realm"]) == r0 else -1
			if eaten < 0:
				eaten = int(S["eat_in"][r0]) - eat0
			t["n"] = int(t["n"]) + 1
			t["seen"] = int(t["seen"]) + seen
			t["kept"] = int(t["kept"]) + kept
			t["eaten"] = int(t["eaten"]) + eaten
			t["exp_lv"] = float(t["exp_lv"]) + float(S["pill_exp_now"]) / need0
			var up := int(S["lv"]) - lv0
			t["lv_up"] = int(t["lv_up"]) + up
			t["max_eat"] = maxi(int(t["max_eat"]), eaten)
			t["max_lv"] = maxi(int(t["max_lv"]), up)
			if int(S["realm"]) == r0 and _cap(S):
				t["cap"] = int(t["cap"]) + 1
		var session_h := float(per_day) * (float(P["raid_min"]) + float(P["hub_min"])) / 60.0
		var off_h := minf(Prog.OFFLINE_CAP_H, 24.0 - session_h)
		S["pill_exp_now"] = 0.0
		_add(S, _med(int(S["realm"])) * 3600.0 * off_h * Prog.OFFLINE_RATE, "off")
		_eat(S)
		_break(S)
		S["day"] = int(S["day"]) + 1
	_done += 1
	if _done % _want == 0:
		print("[pills] ==== %s（%d 次模拟，每局 = 一局大世界 + 回洞府一键服丹）====" % [str(P["name"]), _want])
		for r in 7:
			if not _st.has(r):
				continue
			var t: Dictionary = _st[r]
			var n := float(t["n"])
			print("[pills] %s|%d|%.1f|%.1f|%.1f|%.0f%%|%.2f|%d|%d|%.0f%%" % [NAMES[r], int(t["n"]), float(t["seen"]) / n, float(t["kept"]) / n, float(t["eaten"]) / n,
					100.0 * float(t["exp_lv"]) / n, float(t["lv_up"]) / n, int(t["max_eat"]), int(t["max_lv"]), 100.0 * float(t["cap"]) / n])
		_st.clear()
	return S
