extends RefCounted
## 搜打撤 PvP 重构（2026-11-24）的局外存档（SPEC 3.8）：user://xiuxian_ex_profile.json。和老存档 raid_profile.gd 分开：
## 门 0 木兰草原（旧版）照旧用老存档；主城 / 门 2 沙海古墟 / 门 3 天工秘所走这一份。
## 字段：lingshi 灵石 / xianyu 仙玉 / wh_level 仓库等级 1..14 / vouchers 仓库凭证张数 / stash[] 仓库 / bag[] 背包（30 格）/
##       equip{weapon, armor[4], chip[3]} / hero 当前英雄 / heroes[] 有的英雄 / extract_total 累计带出价值 / rank 段位 /
##       stats{raids, out, dead, kills, best} / live 局内锁
## 物品字典见 ex_data.gd。stash / bag 里每一格是一堆（n = 个数，售卖物一格 ≤10、药符 ≤20，兵刃 / 法衣 / 法宝一件一格）。
## 一局的流程（E 的 extract_manager 调）：
##   入境前 entry_check()（背包里有售卖物就不让进）→ begin_raid(map_id) 拿 {bag, equip, hero} 深拷贝、写 live 锁 →
##   （可选）局内隔一会儿 sync_live(bag, equip) 把现在身上的东西记进锁 → 结算 end_raid(res)
##   中途关游戏 / 掉线没走到结算：下次读档时按陨落处理 live 里记的东西（扣灵石、随机掉 2 堆售卖物、法宝全没），写 notice（照 DarkArea「中途离线 = 死亡」）
## 自检参数（raid_profile.test_mode() 为真）用测试档 user://xiuxian_ex_profile_selftest.json，每次开机清空成新号；加 --keep-profile 保留。
## 操作函数成功返回 ""，失败返回原因（界面直接显示）。每次操作立即存盘。
## 故意不写 class_name：const ExProfile := preload("res://scripts/ex/ex_profile.gd")。

const ExData := preload("res://scripts/ex/ex_data.gd")
const RaidProfile := preload("res://scripts/raid_profile.gd")     # 只借它的 test_mode()

const PATH := "user://xiuxian_ex_profile.json"
const TEST_PATH := "user://xiuxian_ex_profile_selftest.json"
const VER := 1
const BAG_CAP := 30
const HEROES_DEFAULT := ["yujian", "canghong", "shuanghua"]
const HERO_DEFS := "res://scripts/hero_defs.gd"
const LOCK := "禁地之中，仓库里的东西动不了"
const SELL_BLOCK := "售卖物不能带入禁地：先存进仓库或卖给商人"
## 新号赠送（照 DarkArea 首登礼，SPEC 3.7）：直接穿在身上 / 放进背包
const STARTER_WEAPON := "w_qingfeng_5"
const STARTER_ARMOR_Q := 4
const STARTER_BAG := [["med_zhixue", 10], ["med_jinchuang", 3], ["revive", 1]]

static var _d: Dictionary = {}
static var notice := ""          # 读档 / 结算时要告诉玩家的话（大厅界面打开时显示一次，take_notice 取走）
static var last_gain := 0        # 上一次 sell / sell_all 得了多少灵石（界面写结果用）
static var _rank_up := -1        # 刚晋升到的段位（大厅播一次题字后 take_rank_up 取走）
static var _last_txt := ""       # 2026-11-24 F_ui：上一次写进文件的内容（一字不差就不再写，局内 sync_live 常常没变）


static func test_mode() -> bool:
	return RaidProfile.test_mode()


static func _path() -> String:
	return TEST_PATH if test_mode() else PATH


static func _fresh() -> Dictionary:
	return {"ver": VER, "lingshi": ExData.START_LINGSHI, "xianyu": ExData.START_XIANYU, "wh_level": 1, "vouchers": 0,
			"stash": [], "bag": [], "equip": ExData.empty_equip(), "hero": "yujian", "heroes": HEROES_DEFAULT.duplicate(),
			"extract_total": 0, "rank": 0, "stats": {"raids": 0, "out": 0, "dead": 0, "kills": 0, "best": 0}, "live": null,
			"intro": false}


## 新号：_fresh + 首登礼
static func _new_save() -> Dictionary:
	var d := _fresh()
	var eq: Dictionary = d["equip"]
	eq["weapon"] = ExData.make(STARTER_WEAPON)
	var ar: Array = eq["armor"]
	for s in 4:
		ar[s] = ExData.make("a_%d_%d" % [s, STARTER_ARMOR_Q])
	var bag: Array = d["bag"]
	for e: Array in STARTER_BAG:
		var it := ExData.make(str(e[0]))
		it["n"] = int(e[1])
		ExData.add_to(bag, it, BAG_CAP)
	return d


static func load_if_needed() -> void:
	if _d.is_empty():
		_load()


static func data() -> Dictionary:
	load_if_needed()
	return _d


## 2026-11-24 F_ui（econ-4）：存档怎么防坏 ——
##   写：先把整份写进 <档>.tmp、关上，再写正式文件。正式文件写到一半被杀掉（任务管理器 / 断电 / 手机浏览器杀页面），.tmp 还是整份的；
##       .tmp 写到一半被杀，正式文件还是上一份整的。每次开机读成功后另存一份 <档>.bak（上一次开机时的样子）。
##   读：正式文件读不出来就依次试 .tmp、.bak，恢复了告诉玩家一声；全都读不出来：坏文件改名成 <档>.corrupt 留着，新开一个号并告诉玩家
##       （以前是静悄悄地当新号、下一次随便点一下就把坏档盖掉）
static func _load() -> void:
	var path := _path()
	var keep := OS.get_cmdline_user_args().has("--keep-profile")
	_last_txt = ""      # 重新读盘：文件里现在是什么以读到的为准（从备份恢复的要把正式文件补写回去）
	if test_mode() and not keep:
		_d = _new_save()
		save()
		return
	var got: Array = _read(path)
	var from := path
	if got.is_empty():
		for alt: String in [path + ".tmp", path + ".bak"]:
			got = _read(alt)
			if not got.is_empty():
				from = alt
				break
	if got.is_empty():
		var bad := FileAccess.file_exists(path)
		_d = _new_save()
		if bad:
			var err := DirAccess.rename_absolute(path, path + ".corrupt")
			notice = "存档文件坏了、读不出来（%s），只好新开一个号" % (("已另存为 " + path.get_file() + ".corrupt") if err == OK else "也没能另存")
			push_warning("[ExProfile] " + notice)
		save()
		return
	var src: Dictionary = got[0]
	_d = _fresh()
	for k: String in _d.keys():
		if src.has(k):
			_d[k] = src[k]
	_fix_types()
	if from == path:
		_write(path + ".bak", str(got[1]))      # 这次开机读到的样子留一份
		_last_txt = str(got[1])
	else:
		notice = "存档上次没写完，已从备份恢复"
		push_warning("[ExProfile] 存档 %s 读不出来，从 %s 恢复" % [path, from])
	_recover_live()
	save()      # 从备份恢复的：把正式文件补好（和上次写进去的一样就不写）


## 读一个存档文件：[字典, 原文]；没有 / 读不出 / 不是字典 → []
static func _read(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if txt.strip_edges() == "" or j.parse(txt) != OK or not (j.data is Dictionary) or (j.data as Dictionary).is_empty():
		return []
	return [j.data, txt]


static func _write(path: String, txt: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[ExProfile] 存档写不进去：%s" % path)
		return false
	f.store_string(txt)
	var ok := f.get_error() == OK
	f.close()
	return ok


static func save() -> void:
	if _d.is_empty():
		return
	var txt := JSON.stringify(_d)
	if txt == _last_txt:
		return
	var path := _path()
	if not _write(path + ".tmp", txt):
		return
	if _write(path, txt):
		_last_txt = txt


## 2026-11-24 F_ui（gap-onboarding）：新号第一次回到主城要不要说那三句引导（hud.gd 说完调 mark_intro）。
## 自检 / 演示（测试档每次都是新号）不说，免得盖住主城截图；带 --ex-intro 时照样说（看效果用）
static func intro_pending() -> bool:
	if test_mode() and not OS.get_cmdline_user_args().has("--ex-intro"):
		return false
	return not bool(data().get("intro", false))


static func mark_intro() -> void:
	data()["intro"] = true
	save()


## 数字字段的兜底读法：不是数（null、字符串）就当 dflt
static func _num(v: Variant, dflt := 0.0) -> float:
	return float(v) if (v is float or v is int) else dflt


static func _fix_list(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x: Variant in v:
			if x is Dictionary and not (x as Dictionary).is_empty():
				var it := ExData.fix_item(x)
				if not it.is_empty():
					out.append(it)
	return out


## JSON 读回来的数字都是 float：转回 int；物品按表重算；结构补齐
static func _fix_types() -> void:
	_d["ver"] = VER
	_d["lingshi"] = maxi(int(_num(_d.get("lingshi"))), 0)
	_d["xianyu"] = maxi(int(_num(_d.get("xianyu"))), 0)
	_d["wh_level"] = clampi(int(_num(_d.get("wh_level"), 1.0)), 1, ExData.WAREHOUSE.size())
	_d["vouchers"] = maxi(int(_num(_d.get("vouchers"))), 0)
	_d["stash"] = _fix_list(_d.get("stash"))
	_d["bag"] = _fix_list(_d.get("bag"))
	_d["equip"] = ExData.fix_equip(_d.get("equip"))
	_d["hero"] = str(_d.get("hero", "yujian")) if _d.get("hero") is String and str(_d.get("hero")) != "" else "yujian"
	var hs: Array = []
	if _d.get("heroes") is Array:
		for h: Variant in _d["heroes"]:
			if h is String and not hs.has(h):
				hs.append(h)
	for h: String in HEROES_DEFAULT:
		if not hs.has(h):
			hs.append(h)
	_d["heroes"] = hs
	_d["extract_total"] = maxi(int(_num(_d.get("extract_total"))), 0)
	_d["rank"] = clampi(int(_num(_d.get("rank"))), 0, ExData.RANK_NAMES.size() - 1)
	var st: Dictionary = {"raids": 0, "out": 0, "dead": 0, "kills": 0, "best": 0}
	if _d.get("stats") is Dictionary:
		for k: String in st.keys():
			st[k] = maxi(int(_num((_d["stats"] as Dictionary).get(k))), 0)
	_d["stats"] = st
	if not (_d.get("live") is Dictionary):
		_d["live"] = null
	_d["intro"] = bool(_d.get("intro")) if _d.get("intro") is bool else false
	# 背包超了 30 格（老数据 / 手改）：多出来的挪进仓库
	var bag: Array = _d["bag"]
	while bag.size() > BAG_CAP:
		var it: Dictionary = bag.pop_back()
		_stash_or_coin(it)


## 上局没结算（中途关了游戏 / 掉线）：按陨落处理 live 里记的东西，东西直接销毁（没有遗物箱）
static func _recover_live() -> void:
	if not (_d.get("live") is Dictionary):
		return
	var live: Dictionary = _d["live"]
	var bag := _fix_list(live.get("bag", _d["bag"]))
	var equip := ExData.fix_equip(live.get("equip", _d["equip"]))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res := ExData.death_drops(bag, equip, rng)
	var fee := mini(ExData.DEATH_LINGSHI, int(_d["lingshi"]))
	_d["lingshi"] = int(_d["lingshi"]) - fee
	_d["bag"] = []
	for it: Dictionary in bag:
		var left := ExData.add_to(_d["bag"], it, BAG_CAP)
		if left > 0:
			var rest := it.duplicate(true)
			rest["n"] = left
			_stash_or_coin(rest)
	_d["equip"] = equip
	var st: Dictionary = _d["stats"]
	st["dead"] = int(st["dead"]) + 1
	_d["live"] = null
	var lost: Array = []
	for it: Dictionary in res["drop"]:
		lost.append(str(it.get("name", "")) + ("×%d" % int(it.get("n", 1)) if int(it.get("n", 1)) > 1 else ""))
	notice = "上次在禁地里中途离开，按陨落结算：扣 %d 灵石%s" % [fee, ("，失去 " + "、".join(lost)) if not lost.is_empty() else ""]
	save()


# ======================================================================
# 货币
# ======================================================================

static func lingshi() -> int:
	return int(data()["lingshi"])


static func xianyu() -> int:
	return int(data()["xianyu"])


static func add_lingshi(v: int) -> void:
	data()["lingshi"] = maxi(lingshi() + v, 0)
	save()


static func add_xianyu(v: int) -> void:
	data()["xianyu"] = maxi(xianyu() + v, 0)
	save()


## 花灵石：够就扣、存盘、返回 true
static func spend(v: int) -> bool:
	if v < 0 or lingshi() < v:
		return false
	data()["lingshi"] = lingshi() - v
	save()
	return true


static func spend_xianyu(v: int) -> bool:
	if v < 0 or xianyu() < v:
		return false
	data()["xianyu"] = xianyu() - v
	save()
	return true


static func vouchers() -> int:
	return int(data()["vouchers"])


# ======================================================================
# 仓库 / 背包 / 装备栏
# ======================================================================

static func stash() -> Array:
	return data()["stash"]


static func bag() -> Array:
	return data()["bag"]


static func equipment() -> Dictionary:
	return data()["equip"]


static func stash_cap() -> int:
	return ExData.wh_cap(int(data()["wh_level"]))


static func wh_level() -> int:
	return int(data()["wh_level"])


static func in_raid() -> bool:
	return data().get("live") is Dictionary


static func _list(src: String) -> Variant:
	match src:
		"stash":
			return stash()
		"bag":
			return bag()
	return null


static func _cap(src: String) -> int:
	return stash_cap() if src == "stash" else BAG_CAP


static func _where(src: String) -> String:
	return "仓库" if src == "stash" else "背包"


## 放不进仓库的按回收价折成灵石（结算时背包 / 仓库都满了，照 DarkArea）
static func _stash_or_coin(it: Dictionary) -> void:
	var left := ExData.add_to(stash(), it, stash_cap())
	if left > 0:
		_d["lingshi"] = int(_d["lingshi"]) + ExData.unit_value(it) * left


## 把 src[i] 这一堆（n < 0 = 整堆）挪到 dst（"stash" / "bag"）。售卖物可以进背包（开局检查会拦）。
## 放不下的留在原处：一个都没放下返回原因；只放下一部分也返回提示（已挪的不退）
static func move(src: String, i: int, dst: String, n := -1) -> String:
	if in_raid():
		return LOCK
	var a: Variant = _list(src)
	var b: Variant = _list(dst)
	if a == null or b == null or src == dst:
		return "挪不过去"
	var la: Array = a
	if i < 0 or i >= la.size():
		return "没有这件东西"
	var it: Dictionary = la[i]
	var have := maxi(int(it.get("n", 1)), 1)
	var cnt := have if n < 0 else clampi(n, 1, have)
	var mv := it.duplicate(true)
	mv["n"] = cnt
	var left := ExData.add_to(b, mv, _cap(dst))
	var moved := cnt - left
	if moved <= 0:
		return "%s满了" % _where(dst)
	if moved >= have:
		la.remove_at(i)
	else:
		it["n"] = have - moved
	save()
	return "" if left == 0 else "只放下了 %d 个：%s满了" % [moved, _where(dst)]


## 穿戴 src[i]（兵刃 / 法衣 / 法宝）。换下来的那件放回原来那一格
static func equip(src: String, i: int) -> String:
	if in_raid():
		return LOCK
	var a: Variant = _list(src)
	if a == null:
		return "穿不上"
	var la: Array = a
	if i < 0 or i >= la.size():
		return "没有这件东西"
	var it: Dictionary = la[i]
	var s := ExData.slot_of(it)
	if s.is_empty():
		return "这件东西穿不上"
	var eq := equipment()
	var old: Dictionary = {}
	match str(s[0]):
		"weapon":
			old = eq["weapon"]
			eq["weapon"] = it
		"armor":
			var ar: Array = eq["armor"]
			old = ar[int(s[1])]
			ar[int(s[1])] = it
		"chip":
			var ch: Array = eq["chip"]
			var k := -1
			for j in ch.size():
				if (ch[j] as Dictionary).is_empty():
					k = j
					break
			if k < 0:
				return "三个法宝位都满了：先卸下一件"
			ch[k] = it
	la.remove_at(i)
	if not old.is_empty():
		la.insert(mini(i, la.size()), old)
	save()
	return ""


## 卸下装备栏 slot（"weapon" / "armor" / "chip"）第 idx 件：先进背包，背包满了进仓库
static func unequip(slot: String, idx := 0) -> String:
	if in_raid():
		return LOCK
	var eq := equipment()
	var it: Dictionary = {}
	match slot:
		"weapon":
			it = eq["weapon"]
		"armor", "chip":
			var arr: Array = eq[slot]
			if idx >= 0 and idx < arr.size():
				it = arr[idx]
	if it.is_empty():
		return "这里没有东西"
	if bag().size() < BAG_CAP:
		bag().append(it)
	elif stash().size() < stash_cap():
		stash().append(it)
	else:
		return "背包和仓库都满了"
	match slot:
		"weapon":
			eq["weapon"] = {}
		_:
			(eq[slot] as Array)[idx] = {}
	save()
	return ""


## 卖给商人 src[i]（n < 0 = 整堆）。品质 8 不可卖、钥匙 / 护宝符这类没有回收价的不收。得的灵石记在 last_gain
static func sell(src: String, i: int, n := -1) -> String:
	if in_raid():
		return LOCK
	last_gain = 0
	var a: Variant = _list(src)
	if a == null:
		return "卖不了"
	var la: Array = a
	if i < 0 or i >= la.size():
		return "没有这件东西"
	var it: Dictionary = la[i]
	if int(it.get("q", 1)) >= ExData.NO_SELL_Q:
		return "天启之物，商人不敢收"
	if not ExData.can_sell(it):
		return "商人不收这个"
	var have := maxi(int(it.get("n", 1)), 1)
	var cnt := have if n < 0 else clampi(n, 1, have)
	last_gain = ExData.unit_value(it) * cnt
	_d["lingshi"] = int(_d["lingshi"]) + last_gain
	if cnt >= have:
		la.remove_at(i)
	else:
		it["n"] = have - cnt
	save()
	return ""


## 一键卖掉 src（"stash" / "bag" / "all"）里的全部售卖物（含命牌；天启不卖），返回得了多少灵石
static func sell_all_sellables(src: String) -> int:
	if in_raid():
		return 0
	var gain := 0
	for s: String in (["stash", "bag"] if src == "all" else [src]):
		var la: Variant = _list(s)
		if la == null:
			continue
		var arr: Array = la
		var i := arr.size() - 1
		while i >= 0:
			var it: Dictionary = arr[i]
			if ExData.is_sellable(it) and ExData.can_sell(it):
				gain += ExData.value_of(it)
				arr.remove_at(i)
			i -= 1
	_d["lingshi"] = int(_d["lingshi"]) + gain
	last_gain = gain
	save()
	return gain


## src 里售卖物的 [堆数, 价值合计, 品质 ≥5 的堆数]（商人页显示 / 一键卖之前确认）
static func sellable_sum(src: String) -> Array:
	var cnt := 0
	var val := 0
	var hi := 0
	for s: String in (["stash", "bag"] if src == "all" else [src]):
		var la: Variant = _list(s)
		if la == null:
			continue
		for it: Dictionary in la:
			if ExData.is_sellable(it) and ExData.can_sell(it):
				cnt += 1
				val += ExData.value_of(it)
				if ExData.sell_confirm(it):
					hi += 1
	return [cnt, val, hi]


## 坊市买 n 个 shop_id（ExData.shop 里的 id）：先进背包，背包满了进仓库；两边都放不下就不买
static func buy(shop_id: String, n := 1) -> String:
	if in_raid():
		return LOCK
	var price := ExData.shop_price(shop_id)
	if price <= 0:
		return "坊市不卖这个"
	n = maxi(n, 1)
	var cost := price * n
	if lingshi() < cost:
		return "灵石不够：要 %d" % cost
	var it := ExData.make(shop_id)
	if it.is_empty():
		return "坊市不卖这个"
	it["n"] = n
	var room := ExData.room_for(bag(), it, BAG_CAP) + ExData.room_for(stash(), it, stash_cap())
	if room < n:
		return "背包和仓库都放不下了"
	var left := ExData.add_to(bag(), it, BAG_CAP)
	if left > 0:
		var rest := it.duplicate(true)
		rest["n"] = left
		ExData.add_to(stash(), rest, stash_cap())
	_d["lingshi"] = lingshi() - cost
	save()
	return ""


## 黑市（仙玉）：key 禁室玉钥 / ward 护宝符（进背包或仓库）/ voucher 仓库凭证（记数）
static func buy_black(id: String) -> String:
	if in_raid():
		return LOCK
	var price := ExData.black_price(id)
	if price <= 0:
		return "黑市不卖这个"
	if xianyu() < price:
		return "仙玉不够：要 %d" % price
	if id == "voucher":
		_d["vouchers"] = vouchers() + 1
	else:
		var it := ExData.make(id)
		if ExData.room_for(bag(), it, BAG_CAP) + ExData.room_for(stash(), it, stash_cap()) < 1:
			return "背包和仓库都放不下了"
		if ExData.add_to(bag(), it, BAG_CAP) > 0:
			ExData.add_to(stash(), it, stash_cap())
	_d["xianyu"] = xianyu() - price
	save()
	return ""


## 修法宝：src_or_slot = "stash" / "bag"（第 i 格）或 "chip"（装备栏第 i 个）。费用 = 基础价 × 缺损比例 × 0.5
static func repair(src_or_slot: String, i: int) -> String:
	if in_raid():
		return LOCK
	var it: Dictionary = {}
	if src_or_slot == "chip":
		var ch: Array = equipment()["chip"]
		if i >= 0 and i < ch.size():
			it = ch[i]
	else:
		var la: Variant = _list(src_or_slot)
		if la != null and i >= 0 and i < (la as Array).size():
			it = (la as Array)[i]
	if it.is_empty() or str(it.get("kind", "")) != "chip":
		return "只有法宝要修"
	var cost := ExData.repair_cost(it)
	if cost <= 0:
		return "完好无损，不用修"
	if lingshi() < cost:
		return "灵石不够：修理要 %d" % cost
	_d["lingshi"] = lingshi() - cost
	it["dur"] = int(it.get("dur_max", 0))
	save()
	return ""


## 仓库扩容：2..10 级花灵石，11..14 级用仓库凭证
static func upgrade_warehouse() -> String:
	if in_raid():
		return LOCK
	var cost := ExData.wh_next_cost(wh_level())
	if cost.is_empty():
		return "仓库已是最大（%d 格）" % stash_cap()
	if int(cost[0]) > 0:
		if lingshi() < int(cost[0]):
			return "灵石不够：扩容要 %d" % int(cost[0])
		_d["lingshi"] = lingshi() - int(cost[0])
	elif int(cost[1]) > 0:
		if vouchers() < int(cost[1]):
			return "仓库凭证不够：要 %d 张、有 %d 张（黑市 %d 仙玉一张）" % [int(cost[1]), vouchers(), ExData.black_price("voucher")]
		_d["vouchers"] = vouchers() - int(cost[1])
	_d["wh_level"] = wh_level() + 1
	save()
	return ""


## 整理 src：按种类（兵刃 / 法衣 / 法宝 / 药 / 符 / 钥匙 / 售卖物 …）、品质高的在前、同 id 合并
static func sort_list(src: String) -> String:
	if in_raid():
		return LOCK
	var la: Variant = _list(src)
	if la == null:
		return ""
	var order := ["weapon", "armor", "chip", "med", "revive", "throw", "key", "ward", "tag", "sell", "mat"]
	var merged := ExData.merge(la)
	merged.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var kx := order.find(str(x.get("kind", "")))
		var ky := order.find(str(y.get("kind", "")))
		if kx != ky:
			return kx < ky
		if int(x.get("q", 0)) != int(y.get("q", 0)):
			return int(x.get("q", 0)) > int(y.get("q", 0))
		return ExData.unit_value(x) > ExData.unit_value(y))
	var arr: Array = la
	arr.clear()
	for it: Dictionary in merged:
		ExData.add_to(arr, it, 99999)
	save()
	return ""


# ======================================================================
# 英雄
# ======================================================================

static func hero() -> String:
	return str(data().get("hero", "yujian"))


static func heroes() -> Array:
	return data()["heroes"]


## 英雄表（hero_defs.gd，另一个模块写；还没有时退回两个默认英雄）里的全部 id
static func hero_ids() -> Array:
	if ResourceLoader.exists(HERO_DEFS):
		var scr: GDScript = load(HERO_DEFS)
		if scr != null and scr.has_method("ids"):
			var v: Variant = scr.call("ids")
			if v is Array and not (v as Array).is_empty():
				return v
	return HEROES_DEFAULT.duplicate()


static func set_hero(id: String) -> String:
	if in_raid():
		return LOCK
	if not heroes().has(id):
		if hero_ids().has(id):
			heroes().append(id)       # 本轮英雄都不要钱：英雄表里有的直接给
		else:
			return "还没有这位英雄"
	data()["hero"] = id
	save()
	return ""


# ======================================================================
# 一局
# ======================================================================

## 入场检查（选关「开始」前、manager 开局时各调一次）：空 = 能进
static func entry_check() -> String:
	for it: Dictionary in bag():
		if ExData.is_sellable(it):
			return SELL_BLOCK
	return ""


## 进图：返回 {bag, equip, hero} 深拷贝，把它记进 live 锁（中途关游戏下次开机按陨落结算）
static func begin_raid(map_id: String) -> Dictionary:
	load_if_needed()
	var st: Dictionary = _d["stats"]
	st["raids"] = int(st["raids"]) + 1
	_d["live"] = {"map": map_id, "t": int(Time.get_unix_time_from_system()), "bag": bag().duplicate(true),
			"equip": equipment().duplicate(true), "hero": hero()}
	save()
	return {"bag": bag().duplicate(true), "equip": equipment().duplicate(true), "hero": hero()}


## 局内（可选）：把现在身上的东西记进 live 锁（中途关游戏时按这一份结算）。不在局内时什么都不做
static func sync_live(cur_bag: Array, cur_equip: Dictionary) -> void:
	if not in_raid():
		return
	var live: Dictionary = _d["live"]
	live["bag"] = cur_bag.duplicate(true)
	live["equip"] = cur_equip.duplicate(true)
	save()


## 陨落时掉不掉命牌（灵石够扣 DEATH_LINGSHI 才掉，照 DarkArea）。E 在 end_raid 之前问
static func death_tag_ok() -> bool:
	return lingshi() >= ExData.DEATH_LINGSHI


## 结算（SPEC 3.8）。res = {ok, bag, equip, lost_chips, extract_value, kills, map_id, cause: extract / dead / timeout / quit,
##   可选 lingshi_gain / xianyu_gain（营救天工师、击杀首领的奖励）}
## ok：背包回存档背包（不自动进仓库；背包放不下的掉进仓库，仓库满了折灵石），累计带出价值、判段位晋升
## 不 ok：E 已经把掉落从 bag / equip 里扣掉了，剩下的照样回背包；这里扣 DEATH_LINGSHI 灵石、记陨落
static func end_raid(res: Dictionary) -> void:
	load_if_needed()
	var ok := bool(res.get("ok", false))
	var equip := ExData.fix_equip(res.get("equip", equipment()))
	if bool(res.get("lost_chips", false)):
		equip["chip"] = [{}, {}, {}]
	_d["equip"] = equip
	var got := _fix_list(res.get("bag", []))
	_d["bag"] = []
	for it: Dictionary in got:
		var left := ExData.add_to(_d["bag"], it, BAG_CAP)
		if left > 0:
			var rest := it.duplicate(true)
			rest["n"] = left
			_stash_or_coin(rest)
	var st: Dictionary = _d["stats"]
	st["kills"] = int(st["kills"]) + maxi(int(res.get("kills", 0)), 0)
	_d["lingshi"] = maxi(lingshi() + int(res.get("lingshi_gain", 0)), 0)
	_d["xianyu"] = maxi(xianyu() + int(res.get("xianyu_gain", 0)), 0)
	if ok:
		st["out"] = int(st["out"]) + 1
		var ev := maxi(int(res.get("extract_value", ExData.extract_value(got))), 0)
		st["best"] = maxi(int(st["best"]), ev)
		_d["extract_total"] = int(_d["extract_total"]) + ev
		var nr := ExData.rank_of(int(_d["extract_total"]))
		if nr > int(_d["rank"]):
			var gain := ExData.XIANYU_RANK * (nr - int(_d["rank"]))
			_d["xianyu"] = xianyu() + gain
			_d["rank"] = nr
			_rank_up = nr
			notice = ("%s；" % notice if notice != "" else "") + "段位晋升：%s（仙玉 +%d）" % [ExData.rank_name(nr), gain]
	else:
		st["dead"] = int(st["dead"]) + 1
		_d["lingshi"] = lingshi() - mini(ExData.DEATH_LINGSHI, lingshi())
	_d["live"] = null
	save()


static func rank() -> int:
	return int(data()["rank"])


static func extract_total() -> int:
	return int(data()["extract_total"])


static func rank_of(total: int) -> int:
	return ExData.rank_of(total)


static func rank_name(i: int) -> String:
	return ExData.rank_name(i)


## 取走要告诉玩家的话（读档恢复 / 段位晋升）
static func take_notice() -> String:
	var s := notice
	notice = ""
	return s


## 取走「刚晋升到的段位」（-1 = 没有）：大厅里播一次题字
static func take_rank_up() -> int:
	var r := _rank_up
	_rank_up = -1
	return r
