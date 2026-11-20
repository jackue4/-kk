extends RefCounted
## 局外存档（2026-11-20 搜打撤三档改造）：境界、灵石、仓库、随身法宝 / 丹符、储物戒，存在 user://xiuxian_profile.json。
## 一局的流程：
##   进图 begin_raid()：随身法宝跟着进去（死了就没了），随身丹符直接放进背包，储物戒原样带着
##   结算 end_raid()：撤出来 → 背包进仓库（仓库满了多出来的按价折成灵石）、法宝回到身上；陨落 → 背包和法宝都丢，储物戒里的保住
##   境界在结算时记下（陨落也不掉境界）；下次开游戏从存下的境界开始（main.gd 开机时读 boot_realm）
## 进图后中途关了游戏（没走到结算）：下次读档时把带进去的法宝、丹符还回来（不算陨落）。
## 自检 / 演示（命令行带 --raid-shot 之类的参数）用另一个存档文件、每次开机清空，不碰玩家的档；加 --keep-profile 保留。
## 故意不写 class_name：用 preload 引用。

const Items := preload("res://scripts/raid_items.gd")

const PATH := "user://xiuxian_profile.json"
const TEST_PATH := "user://xiuxian_profile_selftest.json"
const OLD_STASH := "user://xiuxian_stash.json"     # 改造前的仓库（只记了带出来的东西和总价）
const VER := 1
const STASH_CAP := 60
const GEAR_SLOTS := 3
const CARRY_SLOTS := 4
const RING_START := 1
const RING_MAX := 4
const RING_PRICE := [0, 0, 500, 2000, 6000]       # 储物戒扩到 n 格的价钱
const START_LINGSHI := 300
const KIT_LINE := 200            # 灵石低于这个、身上和仓库里都没有法宝时，可以领一份散修行囊
## 正常游玩时允许出现的命令行参数（其余的都算自检 / 演示）
const PLAY_ARGS := ["--touch", "--warm", "--sliced", "--keep-profile"]

static var _d: Dictionary = {}
static var notice := ""          # 读档时要告诉玩家的话（洞府界面顶上显示一次）


static func test_mode() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and not PLAY_ARGS.has(a) and not a.begins_with("--scale3d"):
			return true
	return false


static func _path() -> String:
	return TEST_PATH if test_mode() else PATH


static func _fresh() -> Dictionary:
	return {"ver": VER, "lingshi": START_LINGSHI, "realm": 0, "stash": [], "gear": [], "carry": [], "ring": [],
			"ring_cap": RING_START, "live": null, "stats": {"raids": 0, "out": 0, "dead": 0, "best": 0}}


static func data() -> Dictionary:
	if _d.is_empty():
		_load()
	return _d


static func _load() -> void:
	_d = _fresh()
	var path := _path()
	var keep := OS.get_cmdline_user_args().has("--keep-profile")
	if test_mode() and not keep:
		save()
		return
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				var src: Dictionary = v
				for k: String in _d.keys():
					if src.has(k):
						_d[k] = src[k]
		_fix_types()
		_recover_live()
		return
	if not test_mode() and FileAccess.file_exists(OLD_STASH):
		_migrate_old()
	save()


## JSON 读回来的数字都是 float：几个要当整数用的字段转回来
static func _fix_types() -> void:
	_d["lingshi"] = int(_d.get("lingshi", 0))
	_d["realm"] = clampi(int(_d.get("realm", 0)), 0, 7)
	_d["ring_cap"] = clampi(int(_d.get("ring_cap", RING_START)), RING_START, RING_MAX)
	for k: String in ["stash", "gear", "carry", "ring"]:
		if not (_d.get(k) is Array):
			_d[k] = []
		var list: Array = _d[k]
		for it: Variant in list:
			if it is Dictionary:
				_fix_item(it)
		_d[k] = list.filter(func(x: Variant) -> bool: return x is Dictionary)
	if not (_d.get("stats") is Dictionary):
		_d["stats"] = {"raids": 0, "out": 0, "dead": 0, "best": 0}


static func _fix_item(it: Dictionary) -> void:
	for k: String in ["tier", "value", "amt", "to", "region", "heal"]:
		if it.has(k):
			it[k] = int(it[k])


## 上次进图没走到结算（关了游戏 / 崩了）：带进去的东西还回来
static func _recover_live() -> void:
	var live: Variant = _d.get("live")
	if not (live is Dictionary):
		_d["live"] = null
		return
	var l: Dictionary = live
	var back := 0
	if l.get("gear") is Array:
		_d["gear"] = l["gear"]
		back += (l["gear"] as Array).size()
	if l.get("carry") is Array:
		for it: Variant in l["carry"]:
			if it is Dictionary:
				_fix_item(it)
				(_d["stash"] as Array).append(it)
				back += 1
	_d["live"] = null
	if back > 0:
		notice = "上次入境没有正常结束，随身的 %d 件已归还" % back
	save()


## 改造前的仓库：东西按品阶换成新物品，累计价值折一成灵石
static func _migrate_old() -> void:
	var f := FileAccess.open(OLD_STASH, FileAccess.READ)
	if f == null:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	if not (v is Dictionary):
		return
	var od: Dictionary = v
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var n := 0
	for it: Variant in od.get("items", []):
		if not (it is Dictionary) or (_d["stash"] as Array).size() >= STASH_CAP:
			continue
		var t := int((it as Dictionary).get("tier", 0))
		var k := str((it as Dictionary).get("kind", ""))
		var ni := Items.pill(t) if k == "pill" else (Items.mat(t) if k == "mat" else Items.rand_gear(t, rng))
		ni["value"] = int((it as Dictionary).get("value", ni["value"]))
		(_d["stash"] as Array).append(ni)
		n += 1
	_d["lingshi"] = START_LINGSHI + int(int(od.get("total", 0)) * 0.1)
	if n > 0:
		notice = "旧仓库的 %d 件已搬进洞府" % n


static func save() -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_d))


# ---------- 读 ----------

static func lingshi() -> int:
	return int(data()["lingshi"])


static func realm() -> int:
	return int(data()["realm"])


## 开机时主角的境界：自检 / 演示一律从炼气开始（它们自己会设）
static func boot_realm() -> int:
	return 0 if test_mode() else realm()


static func stash() -> Array:
	return data()["stash"]


static func gear() -> Array:
	return data()["gear"]


static func carry() -> Array:
	return data()["carry"]


static func ring() -> Array:
	return data()["ring"]


static func ring_cap() -> int:
	return int(data()["ring_cap"])


static func wealth() -> int:
	var v := lingshi()
	for k: String in ["stash", "gear", "carry", "ring"]:
		for it: Dictionary in data()[k]:
			v += int(it.get("value", 0))
	return v


# ---------- 一局 ----------

## 进图：返回 {gear, carry, ring}（都是拷贝）；随身丹符从存档里拿走（进了背包）
static func begin_raid() -> Dictionary:
	var d := data()
	var out := {"gear": (d["gear"] as Array).duplicate(true), "carry": (d["carry"] as Array).duplicate(true),
			"ring": (d["ring"] as Array).duplicate(true)}
	d["live"] = {"gear": out["gear"], "carry": out["carry"]}
	d["carry"] = []
	(d["stats"] as Dictionary)["raids"] = int((d["stats"] as Dictionary).get("raids", 0)) + 1
	save()
	return out


## 结算。返回 {stashed: 进仓库几件, sold: 仓库满了折成灵石几件, sold_value, lost_gear: 丢了几件法宝}
static func end_raid(ok: bool, bag: Array, ring_items: Array, gear_items: Array, realm_idx: int) -> Dictionary:
	var d := data()
	var res := {"stashed": 0, "sold": 0, "sold_value": 0, "lost_gear": 0}
	d["ring"] = ring_items.duplicate(true)
	d["realm"] = clampi(realm_idx, 0, 7)
	var st: Dictionary = d["stats"]
	if ok:
		d["gear"] = gear_items.duplicate(true)
		var s: Array = d["stash"]
		for it: Dictionary in bag:
			if s.size() < STASH_CAP:
				s.append(it.duplicate(true))
				res["stashed"] = int(res["stashed"]) + 1
			else:
				d["lingshi"] = int(d["lingshi"]) + int(it.get("value", 0))
				res["sold"] = int(res["sold"]) + 1
				res["sold_value"] = int(res["sold_value"]) + int(it.get("value", 0))
		st["out"] = int(st.get("out", 0)) + 1
		var v := 0
		for it: Dictionary in bag:
			v += int(it.get("value", 0))
		st["best"] = maxi(int(st.get("best", 0)), v)
	else:
		res["lost_gear"] = gear_items.size()
		d["gear"] = []
		st["dead"] = int(st.get("dead", 0)) + 1
	d["live"] = null
	save()
	return res


## 局内花灵石（灵石阵）：够就扣、返回 true
static func spend(n: int) -> bool:
	if lingshi() < n:
		return false
	data()["lingshi"] = lingshi() - n
	save()
	return true


# ---------- 洞府里的操作（成功返回 ""，失败返回原因）----------

static func _move(from_key: String, i: int, to_key: String) -> void:
	var src: Array = data()[from_key]
	var it: Dictionary = src[i]
	src.remove_at(i)
	(data()[to_key] as Array).append(it)
	save()


static func equip(i: int) -> String:
	var s := stash()
	if i < 0 or i >= s.size() or str(s[i].get("kind", "")) != "gear":
		return "只有法宝能佩戴"
	if gear().size() >= GEAR_SLOTS:
		return "最多佩戴 %d 件法宝" % GEAR_SLOTS
	_move("stash", i, "gear")
	return ""


static func unequip(i: int) -> String:
	if i < 0 or i >= gear().size():
		return "没有这件"
	if stash().size() >= STASH_CAP:
		return "仓库满了"
	_move("gear", i, "stash")
	return ""


static func pack(i: int) -> String:
	var s := stash()
	if i < 0 or i >= s.size():
		return "没有这件"
	if not ["pill", "key", "tool"].has(str(s[i].get("kind", ""))):
		return "随身只带丹药、破境丹和符箓"
	if carry().size() >= CARRY_SLOTS:
		return "随身最多带 %d 件" % CARRY_SLOTS
	_move("stash", i, "carry")
	return ""


static func unpack(i: int) -> String:
	if i < 0 or i >= carry().size():
		return "没有这件"
	if stash().size() >= STASH_CAP:
		return "仓库满了"
	_move("carry", i, "stash")
	return ""


static func to_ring(i: int) -> String:
	var s := stash()
	if i < 0 or i >= s.size():
		return "没有这件"
	if Items.slots_used(ring()) + Items.size_of(s[i]) > ring_cap():
		return "储物戒放不下（%d 格）" % ring_cap()
	_move("stash", i, "ring")
	return ""


static func from_ring(i: int) -> String:
	if i < 0 or i >= ring().size():
		return "没有这件"
	if stash().size() >= STASH_CAP:
		return "仓库满了"
	_move("ring", i, "stash")
	return ""


static func sell(i: int) -> int:
	var s := stash()
	if i < 0 or i >= s.size():
		return 0
	var v := int(s[i].get("value", 0))
	s.remove_at(i)
	data()["lingshi"] = lingshi() + v
	save()
	return v


## 一键出售：凡品法宝和所有灵材（炼丹要用的灵草不卖）。返回 [件数, 灵石]
static func sell_junk() -> Array:
	var s := stash()
	var n := 0
	var v := 0
	var i := s.size() - 1
	while i >= 0:
		var it: Dictionary = s[i]
		var k := str(it.get("kind", ""))
		if (k == "gear" and int(it.get("tier", 0)) == 0) or k == "mat":
			v += int(it.get("value", 0))
			n += 1
			s.remove_at(i)
		i -= 1
	data()["lingshi"] = lingshi() + v
	save()
	return [n, v]


static func buy(good: Dictionary) -> String:
	var price := int(good["price"])
	if lingshi() < price:
		return "灵石不够（要 %d）" % price
	if stash().size() >= STASH_CAP:
		return "仓库满了"
	data()["lingshi"] = lingshi() - price
	stash().append((good["item"] as Dictionary).duplicate(true))
	save()
	return ""


static func ring_next_price() -> int:
	var c := ring_cap()
	return RING_PRICE[c + 1] if c < RING_MAX else -1


static func upgrade_ring() -> String:
	var p := ring_next_price()
	if p < 0:
		return "储物戒已经最大"
	if lingshi() < p:
		return "灵石不够（要 %d）" % p
	data()["lingshi"] = lingshi() - p
	data()["ring_cap"] = ring_cap() + 1
	save()
	return ""


## 仓库里某样东西有几件（按名字，炼丹配料用）
static func count(item_name: String) -> int:
	var n := 0
	for it: Dictionary in stash():
		if str(it.get("name", "")) == item_name:
			n += 1
	return n


static func can_craft(r: Dictionary) -> bool:
	if lingshi() < int(r["cost"]) or stash().size() >= STASH_CAP + 1:
		return false
	var need: Dictionary = r["need"]
	for nm: String in need.keys():
		if count(nm) < int(need[nm]):
			return false
	return true


static func craft(r: Dictionary) -> String:
	if not can_craft(r):
		return "材料或灵石不够"
	var need: Dictionary = r["need"]
	var s := stash()
	for nm: String in need.keys():
		var left := int(need[nm])
		var i := s.size() - 1
		while i >= 0 and left > 0:
			if str(s[i].get("name", "")) == nm:
				s.remove_at(i)
				left -= 1
			i -= 1
	data()["lingshi"] = lingshi() - int(r["cost"])
	s.append((r["out"] as Dictionary).duplicate(true))
	save()
	return ""


## 散修行囊：穷到身上、仓库都没有法宝、灵石也见底时，白给一份凡品家当，免得一直空手
static func kit_ok() -> bool:
	if lingshi() >= KIT_LINE or not gear().is_empty():
		return false
	for it: Dictionary in stash():
		if str(it.get("kind", "")) == "gear":
			return false
	return true


static func take_kit() -> String:
	if not kit_ok():
		return "家底还够，不必领"
	gear().append(Items.gear(0, 0))
	gear().append(Items.gear(0, 1))
	carry().append(Items.heal_pill())
	carry().append(Items.heal_pill())
	save()
	return ""
