extends RefCounted
## 搜打撤三档改造的自检：`-- --raid-shot --raid-econ [--touch]`（要渲染：run_hidden 起，约 3 分钟；截图 _shots/preview/raid_e*.jpg）。
## 用的是自检专用存档（raid_profile.gd 的 TEST_PATH，每次开机清空），不碰玩家的档。按顺序：
##   1 坊市 / 储物 / 丹房的存档操作      2 洞府三页截图
##   2b 大厅底部一键服丹（吃仓库里的修为丹、逐颗飘字、修为存档）
##   3 进图：随身丹符进背包、法宝被动    4 搜点：灵药圃、禁制宝库（守卫、读条）、右侧拾取卡片、背包面板截图
##   5 瓶颈：没有破境丹卡住 → 捡到破境丹起雷劫（2026-11-20 起还要洞府灵石够布阵，起劫时扣；开头给了 20000，够筑基的 500）
##     → 渡劫成功服下、境界存档
##   6 时间线：空间裂隙、传送阵熄灭      7 破界符撤离 → 结算进仓库、法宝带回
##   8 再进图 → 禁地封闭困死 → 法宝丢失、储物戒保住
## 故意不写 class_name：用 preload 引用。

const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Prog := preload("res://scripts/progression.gd")


static func _find(list: Array, nm: String) -> int:
	for i in list.size():
		if str((list[i] as Dictionary).get("name", "")) == nm:
			return i
	return -1


static func _buy(nm: String) -> String:
	for g: Dictionary in Items.shop():
		if str(g["item"]["name"]) == nm:
			return Profile.buy(g)
	return "坊市里没有 " + nm


static func _names(list: Array) -> String:
	var out: Array = []
	for it: Dictionary in list:
		out.append(str(it["name"]))
	return "、".join(out)


static func run(m: Node) -> void:
	m.player.set_realm(0, false)
	print("[econ] 自检存档=%s 开局灵石 %d 境界 %d" % [Profile.test_mode(), Profile.lingshi(), Profile.realm()])
	# ---------- 1 存档操作 ----------
	Profile.data()["lingshi"] = 20000
	var errs: Array = []
	# 2026-11-20 数值框架：修为丹名字带品质（坊市卖的是下品）
	for nm: String in ["回春丹", "下品黄龙丹", "破界符", "寻宝符", "铁木剑", "青钢盾", "寻灵罗盘", "筑基丹", "温玉佩"]:
		var e := _buy(nm)
		if e != "":
			errs.append(nm + ":" + e)
	for nm: String in ["铁木剑", "青钢盾", "寻灵罗盘"]:
		var e2 := Profile.equip(_find(Profile.stash(), nm))
		if e2 != "":
			errs.append(e2)
	var e3 := Profile.equip(_find(Profile.stash(), "温玉佩"))
	print("[econ] 第四件法宝佩戴应被拒：%s" % e3)
	for nm: String in ["回春丹", "破界符", "寻宝符", "筑基丹"]:
		var e4 := Profile.pack(_find(Profile.stash(), nm))
		if e4 != "":
			errs.append(e4)
	print("[econ] 扩储物戒：%s → %d 格" % [Profile.upgrade_ring(), Profile.ring_cap()])
	Profile.to_ring(_find(Profile.stash(), "下品黄龙丹"))
	# 2026-11-20 数值框架：破境丹改成残片 × Prog.FRAG_N + 灵石合（筑基丹 3 片 + 100 灵石）
	for i in Prog.FRAG_N:
		Profile.stash().append(Items.frag(1))
	var ls_craft := Profile.lingshi()
	var rec: Dictionary = {}
	for r: Dictionary in Items.recipes():
		if str(r["out"]["name"]) == "筑基丹":
			rec = r
	var before := Profile.count("筑基丹")
	print("[econ] 炼筑基丹（残片合）：可炼=%s 结果「%s」筑基丹 %d → %d 残片剩 %d 灵石 %d → %d（应少 %d）" % [Profile.can_craft(rec), Profile.craft(rec),
			before, Profile.count("筑基丹"), Profile.count(str(Items.frag(1)["name"])), ls_craft, Profile.lingshi(), Prog.KEY_CRAFT_COST[1]])
	Profile.stash().append(Items.gear(0, 0))
	Profile.stash().append(Items.mat(1))
	var junk := Profile.sell_junk()
	print("[econ] 一键出售 %d 件得 %d 灵石；操作失败：%s" % [int(junk[0]), int(junk[1]), errs])
	print("[econ] 佩戴：%s　随身：%s　储物戒：%s　仓库 %d 件　灵石 %d" % [_names(Profile.gear()), _names(Profile.carry()),
			_names(Profile.ring()), Profile.stash().size(), Profile.lingshi()])
	# ---------- 2 洞府界面 ----------
	m.level_ui.open()
	await m._wait(0.3)
	m.level_ui.pick(0)
	await m._wait(0.6)
	await m._shot("raid_e00_entry")
	m.level_ui.open_abode()
	await m._wait(0.5)
	var ab: Variant = m.level_ui._abode
	for t in 3:
		ab._set_tab(t)
		if t == 0:
			ab._select("stash", 0)
		await m._wait(0.4)
		await m._shot("raid_e0%d_abode" % (t + 1))
	ab._close()
	await m._wait(0.3)
	m.level_ui.close()
	await m._wait(0.3)
	# ---------- 2b 大厅底部的一键服丹：吃仓库里的修为丹，每颗一个飘字，修为记进存档 ----------
	for i in 5:
		Profile.stash().append(Items.pill(0))
	var hp: Node = m.get_node_or_null("HallPills")
	var cu0 := Profile.cult(0)
	var n_pill: int = hp.count() if hp != null else -1
	await m._wait(0.3)
	await m._shot("raid_e04_hall_bar")
	if hp != null:
		hp.eat_all()
	m.cam.snap(m.cam.yaw, -0.12, 6.0)
	await m._wait(1.0)
	var fl := 0
	for c in m.player.get_parent().get_children():
		if c is Label3D and str((c as Label3D).text).begins_with("修为"):
			fl += 1
	await m._shot("raid_e05_hall_eat")
	await m._wait(1.6)
	var cu1 := Profile.cult(0)
	print("[econ] 大厅一键服丹：仓库修为丹 %d 颗　1 秒时头上飘着 %d 个数　修为 Lv.%d %.0f → Lv.%d %.0f　仓库还剩 %d 颗（到瓶颈会退回）" % [n_pill, fl,
			int(cu0[0]), float(cu0[1]), int(cu1[0]), float(cu1[1]), hp.count() if hp != null else -1])
	# ---------- 3 进图 ----------
	m.level_ui.team_size = 1
	await m._enter_level("meadow")
	var rd: Variant = m.level.raid
	var player: Node3D = m.player
	m._raid_immortal()
	await m._wait(1.0)
	print("[econ] 进图：背包 %s　佩戴 %s　储物戒 %s　被动 %s　剩余 %ds" % [_names(rd.bag), _names(rd.gear), _names(rd.ring), rd.fx, int(rd.time_left())])
	var kinds := {}
	for s: Dictionary in rd.search.sites:
		kinds[str(s["kind"])] = int(kinds.get(str(s["kind"]), 0)) + 1
	print("[econ] 搜点：%s，共 %d 个" % [kinds, rd.search.sites.size()])
	# ---------- 4 搜点 ----------
	for kind: String in ["herb", "jar", "vault"]:
		var best: Dictionary = {}
		var bd := INF
		for s: Dictionary in rd.search.sites:
			var b: Vector2 = s["base"]
			if str(s["kind"]) == kind and b.length() < bd:
				bd = b.length()
				best = s
		if best.is_empty():
			print("[econ] 没有 %s 搜点" % kind)
			continue
		var at: Vector2 = best["base"]
		rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED if kind != "vault" else Node.PROCESS_MODE_INHERIT
		await m._raid_goto(at + Vector2(3.0, 0.0), 0.0)
		player.global_position = Vector3(at.x + 1.2, m.level.ground(at.x, at.y) + 0.1, at.y)
		m.cam.snap(atan2(1.0, 0.0), -0.3, 8.0)
		var n0: int = rd.bag.size()
		await m._wait(0.9 if kind != "vault" else 3.0)
		await m._shot("raid_e1%d_%s" % [["herb", "jar", "vault"].find(kind), kind])
		if kind == "vault":
			# 守卫已经被惊动（截图里看得到）：清掉，看读条能不能走完
			print("[econ] 宝库破禁 3 秒：守卫 %d 只、小地图闪点 %d 个" % [rd._mobs.size(), rd.pings.size()])
			for mob: Variant in rd._mobs:
				if is_instance_valid(mob):
					mob.queue_free()
			rd._mobs.clear()
		var t0 := Time.get_ticks_msec()
		while not bool(best["done"]) and Time.get_ticks_msec() - t0 < 16000:
			player.global_position = Vector3(at.x + 1.2, m.level.ground(at.x, at.y) + 0.1, at.y)
			await m._wait(0.25)
		# 搜出来的东西放在旁边的「搜得」箱子里，不自动进背包：拾取面板出现，点拾取（箱子刚落地有 0.6 秒拿不了）
		await m._wait(1.0)
		var near_n: int = rd.near_loot.size()
		var auto_n: int = rd.bag.size()
		if kind == "herb":
			await m._shot("raid_e13_loot")
		elif kind == "vault":
			await m._shot("raid_e14_cards")
			print("[econ]   宝库搜得：卡片 %d 张（滚动容器最多露 4 张）" % rd.loot_entries().size())
		for pk: Variant in rd.near_loot.duplicate():
			rd.pick_up(pk, -1)
		await m._wait(0.2)
		print("[econ] 搜 %s（%s，离中心 %dm）：搜完=%s 用时 %.1fs 拾取面板 %d 项 没点拾取时背包 %d 件（应不变） 点了之后 %d → %d 件 / %d 格　怪 %d 只" % [
				kind, best["region"], int(bd), best["done"], float(Time.get_ticks_msec() - t0) / 1000.0, near_n, auto_n, n0, rd.bag.size(),
				rd.bag_used(), rd._mobs.size()])
	rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED
	for mob: Variant in rd._mobs:
		if is_instance_valid(mob):
			mob.queue_free()
	rd._mobs.clear()
	# 2026-11-20 数值框架（总控补的）：搜过的点过一阵重新可搜——把搜点的本机时钟拨快，看刚搜过的几个点回没回来
	var done0 := 0
	for s: Dictionary in rd.search.sites:
		if bool(s["done"]):
			done0 += 1
	rd.search.clock += 481.0
	await m._wait(0.6)
	var done1 := 0
	var vault_back := 0
	for s: Dictionary in rd.search.sites:
		if bool(s["done"]):
			done1 += 1
			if str(s["kind"]) == "vault":
				vault_back += 1
	rd.search.clock += 420.0
	await m._wait(0.6)
	var done2 := 0
	for s: Dictionary in rd.search.sites:
		if bool(s["done"]):
			done2 += 1
	print("[econ] 搜点刷新：已搜 %d 个 → 拨快 481 秒后 %d 个（宝库 %d，应为 1：要 900 秒）→ 再拨快 420 秒后 %d 个（应为 0）" % [done0, done1, vault_back, done2])
	await m._wait(0.5)
	rd.hud.toggle_bag()
	await m._wait(0.3)
	rd.hud._select("bag", 0)
	await m._wait(0.3)
	await m._shot("raid_e20_bag")
	rd.hud.toggle_bag()
	# ---------- 5 瓶颈 / 破境丹 ----------
	var keys_off: Array = []
	for list: Array in [rd.bag, rd.ring]:
		for i in range(list.size() - 1, -1, -1):
			if str(list[i]["kind"]) == "key":
				keys_off.append(list[i])
				list.remove_at(i)
	# 2026-11-20 数值框架：局内修为就是存档里的（add_exp 写存档、rd.lv / xp 照抄），所以从存档设到本境界最后一级
	Profile.set_cult(player.realm_idx * 3 + 3, 0.0)
	rd.add_exp(1.0e6)
	var ls0 := Profile.lingshi()
	print("[econ] 瓶颈（身上没丹）：缺丹=%d 起劫=%d（应为 1 / -1） Lv.%d 修为 %d%% 灵石 %d（布阵要 %d）" % [rd._need_key, rd._trib_to, rd.lv,
			int(rd.exp_ratio() * 100.0), ls0, Prog.break_cost(1)])
	await m._wait(0.5)
	await m._shot("raid_e21_bottleneck")
	rd._take(keys_off[0] if not keys_off.is_empty() else Items.key(1))
	print("[econ] 捡到破境丹之后：缺丹=%d 缺灵石=%d 起劫=%d（应为 -1 / -1 / 1）" % [rd._need_key, rd._need_ls, rd._trib_to])
	await m._wait_until(func() -> bool: return rd.trib_active(), 6.0)
	print("[econ] 起劫扣布阵灵石：%d → %d（应少 %d）" % [ls0, Profile.lingshi(), Prog.break_cost(1)])
	if rd.trib_active():
		rd._trib.demo_auto = 1.0
	var t1 := Time.get_ticks_msec()
	while (rd._in_trib or rd._trib_to >= 0) and Time.get_ticks_msec() - t1 < 90000:
		await m._wait(0.5)
	var kleft := 0
	for it: Dictionary in rd.bag + rd.ring:
		if str(it["kind"]) == "key":
			kleft += 1
	print("[econ] 渡劫后：境界 %d（存档 %d） 身上破境丹 %d 颗 Lv.%d" % [player.realm_idx, Profile.realm(), kleft, rd.lv])
	# ---------- 6 时间线 ----------
	# 2026-11-20 七点之三：裂隙、传送阵轮换按房间时间（单人 = rd._solo_t）走，不再按个人时间熄阵
	rd._solo_t = rd.RIFT_PHASE + 0.5
	await m._wait(1.0)
	var rift := 0
	for e: Dictionary in rd._extracts:
		if str(e.get("kind", "")) == "rift":
			rift += 1
	print("[econ] 房间时间 %d 秒：空间裂隙 %d 个（应为 1），亮着的阵 %d 座" % [int(rd.RIFT_PHASE), rift, rd._active_count()])
	await m._shot("raid_e30_rift")
	var lit0: Array = []
	for e: Dictionary in rd._extracts:
		if e.has("base") and bool(e["active"]):
			lit0.append(str(e["name"]))
	rd._solo_t = rd.RIFT_PHASE + rd.RIFT_LEN + rd.ROT_PERIOD + 0.5
	await m._wait(1.0)
	var lit1: Array = []
	for e: Dictionary in rd._extracts:
		if e.has("base") and bool(e["active"]):
			lit1.append(str(e["name"]))
	var rift2 := 0
	for e: Dictionary in rd._extracts:
		if str(e.get("kind", "")) == "rift":
			rift2 += 1
	print("[econ] 传送阵轮转：第 %d 轮 %s → 第 %d 轮 %s（各应 3 座）；裂隙合上后 %d 个（应为 0）；离下次轮转 %d 秒" % [
			int(floorf((rd.RIFT_PHASE + 0.5) / rd.ROT_PERIOD)), "、".join(lit0), rd._rot_k, "、".join(lit1), rift2, int(rd.rotation_left())])
	rd.run_t = 300.0
	rd._dim_n = 0
	rd._warned = {}
	# 2026-11-20 数值框架（总控补的）：巢穴打空后按个人局内时间 LAIR_BACK（600）秒来新的镇守
	var lair_ri := 2
	var lair_st := func() -> int:
		for b: Dictionary in rd._bosses:
			if int(b["region"]) == lair_ri:
				return int(b["state"])
		return -1
	rd._lair_cleared(lair_ri)
	var st0: int = lair_st.call()
	rd.run_t = 300.0 + float(rd.LAIR_BACK) - 2.0
	await m._wait(0.6)
	var st1: int = lair_st.call()
	rd.run_t = 300.0 + float(rd.LAIR_BACK) + 0.5
	await m._wait(0.6)
	print("[econ] 巢穴重生：打空后状态 %d（应为 2）→ 差 2 秒 %d（应为 2）→ 满 %d 秒 %d（应为 0）" % [st0, st1, int(rd.LAIR_BACK), int(lair_st.call())])
	rd.run_t = 300.0
	rd._dim_n = 0
	rd._warned = {}
	# ---------- 7 破界符撤离 ----------
	var ri: int = _find(rd.bag, "破界符")
	if ri < 0:
		rd.bag.append(Items.tool("rune"))
		ri = rd.bag.size() - 1
	var bag_n: int = rd.bag.size()
	var gear_n: int = rd.gear.size()
	var stash0 := Profile.stash().size()
	# 2026-11-20 数值框架：心得撤离成功才化为修为——塞一笔心得进去，看结算后存档里的修为涨没涨
	rd.insight = minf(float(rd.insight) + 300.0, float(rd.insight_cap()))
	var ins0: float = rd.insight
	var cu_a := Profile.cult(player.realm_idx)
	# 读条挨打就断：这一段把怪、修士都清掉、停住（只测撤离本身）
	rd._mob_root.process_mode = Node.PROCESS_MODE_DISABLED
	for mob: Variant in rd._mobs + rd._rivals:
		if is_instance_valid(mob):
			mob.queue_free()
	rd._mobs.clear()
	rd._rivals.clear()
	await m._raid_goto(Vector2(40.0, 40.0), 0.0)
	rd.use_item(ri, "use")
	await m._wait(1.0)
	await m._shot("raid_e40_rune")
	var t2 := Time.get_ticks_msec()
	var last := -1.0
	while rd.running and Time.get_ticks_msec() - t2 < 30000:
		await m._wait(0.3)
		if float(rd.extract_k) < last - 0.05:
			print("[econ]   读条被打断：%.2f → %.2f 气血 %.0f" % [last, rd.extract_k, m.player.melee.hp])
		last = rd.extract_k
	print("[econ] 破界符撤离：用时 %.1fs 结束=%s 仓库 %d → %d 件（背包 %d 件） 佩戴法宝 %d 件（应为 %d）" % [float(Time.get_ticks_msec() - t2) / 1000.0,
			not rd.running, stash0, Profile.stash().size(), bag_n - 1, Profile.gear().size(), gear_n])
	var cu_b := Profile.cult(player.realm_idx)
	print("[econ] 心得结算：本局心得 %.0f（上限 %.0f）→ 存档修为 Lv.%d %.0f → Lv.%d %.0f（应涨）" % [ins0, float(rd.insight_cap()),
			int(cu_a[0]), float(cu_a[1]), int(cu_b[0]), float(cu_b[1])])
	await m._wait(0.6)
	await m._shot("raid_e41_result")
	if rd.running:
		rd._finish(true)      # 没撤成（上面会打印原因）：手动结算，后面接着测
	await m._wait_until(func() -> bool: return m.level == null and not m._switching, 12.0)
	await m._wait(0.5)
	# ---------- 8 禁地封闭：困死 ----------
	await m._enter_level("meadow")
	rd = m.level.raid
	await m._wait(1.0)
	var ring_n: int = rd.ring.size()
	print("[econ] 再进图：佩戴 %s 储物戒 %s" % [_names(rd.gear), _names(rd.ring)])
	rd.run_t = RAID_END - 0.5
	var t3 := Time.get_ticks_msec()
	while rd.running and Time.get_ticks_msec() - t3 < 5000:
		await m._wait(0.2)
	await m._wait(0.6)
	await m._shot("raid_e50_dead")
	print("[econ] 禁地封闭：结束=%s 存档佩戴 %d 件（应为 0） 储物戒 %d 件（应为 %d） 陨落次数 %d" % [not rd.running, Profile.gear().size(),
			Profile.ring().size(), ring_n, int(Profile.data()["stats"]["dead"])])
	await m._wait(5.5)


const RAID_END := 1200.0
