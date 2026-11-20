extends RefCounted
## AI 道友这一队的调度和联机同步（2026-11-20，raid_manager.gd 持有一个）。
## · attach：给新生成的 AI 道友挂上大脑（ally_brain.gd）。命令行带 `--ally-old` 时不挂（留着老的贴身跟随，自检做前后对比用）。
## · update：把同队的真人（本机主角 + 同队别人的木偶）轮着分给各个 AI 道友当「跟着谁行动」的 anchor——
##   队里有两个真人、两个 AI 时，一人身边各有一个 AI 在忙，而不是都围着算它们的那台机器的主人。
## · 联机：AI 道友只在「本队在场的真人里编号最小的那位」机器上算（is_owner）。原来是每个人各自在本机生成自己的 AI 道友、
##   互相看不见（同一支队伍里每个人看到的 AI 队友都不一样）；现在其余人 ally_want() 为 0，看到的是主人发来的木偶（ally_puppet.gd）。
##   batch：我名下的 AI 道友的状态，net.gd 每秒十次发出去；apply：收到别人的，建 / 更新木偶。
##   主人撤离 / 掉线后，编号次小的那位自动成为主人，重新生成（木偶三秒没消息自己消失）。
## 故意不写 class_name：用 preload 引用。

const Brain := preload("res://scripts/ally_brain.gd")
const Puppet := preload("res://scripts/ally_puppet.gd")
const Data := preload("res://scripts/raid_data.gd")

var puppets := {}          # 主人编号 × 10 + 第几个 → 木偶
var old_mode := OS.get_cmdline_user_args().has("--ally-old")
var sent := 0              # 发出过几批（自检看）
var got := 0               # 收到过几批


## 本队的 AI 道友归不归我算
func is_owner(rd: Variant) -> bool:
	var net: Variant = rd.net
	if net == null or not bool(net.active):
		return true
	var me := int(net.my_id)
	var team := int(net.my_team())
	for id: int in net.players.keys():
		var p: Dictionary = net.players[id]
		if id < me and int(p["team"]) == team and not bool(p.get("away", false)):
			return false
	return true


func attach(rd: Variant, f: Node3D) -> void:
	if old_mode:
		return
	var b := Brain.new()
	b.setup(rd, f, int(f.get("ally_slot")))
	f.set("brain", b)


## 同队在场的真人：本机主角在前，后面是同队别人的木偶（按编号排，各机器上顺序一致）
func humans(rd: Variant) -> Array:
	var out: Array = [rd.player]
	var net: Variant = rd.net
	if net != null and bool(net.active):
		var ids: Array = net.remotes.keys()
		ids.sort()
		for id: int in ids:
			var r: Variant = net.remotes[id]
			if is_instance_valid(r) and bool(r.mate) and bool(r.is_alive()) and r.visible:
				out.append(r)
	return out


func update(rd: Variant, _p: Vector3) -> void:
	for k: int in puppets.keys():
		if not is_instance_valid(puppets[k]):
			puppets.erase(k)
	var hs := humans(rd)
	for f: Variant in rd._allies:
		if is_instance_valid(f) and f.brain != null:
			f.brain.anchor = hs[int(f.ally_slot) % hs.size()]


## 我名下的 AI 道友（房间里只有我一个人时不用发）
func batch(rd: Variant) -> Array:
	var out: Array = []
	var net: Variant = rd.net
	if net == null or not bool(net.active) or int(net.players.size()) < 2:
		return out
	for f: Variant in rd._allies:
		if not is_instance_valid(f):
			continue
		var b: Variant = f.brain
		out.append([int(f.ally_slot), str(f.display_name), int(f.look_i), int(f.lv), f.qi, f.global_position, float(f._facing), f._vel,
				clampf(float(f.hp) / maxf(float(f.hp_max), 1.0), 0.0, 1.0), str(f.rig.last_name), int(f.rig.play_n),
				int(b.flags()) if b != null else 0, int(b.say_i) if b != null else -1, int(b.say_n) if b != null else 0])
	if not out.is_empty():
		sent += 1
	return out


## 别人发来他名下的 AI 道友：离我 240 米内的建木偶 / 更新木偶
func apply(rd: Variant, owner_id: int, list: Array) -> void:
	got += 1
	var pp: Vector3 = rd.player.global_position
	for e: Array in list:
		if e.size() < 14:
			continue
		var key := owner_id * 10 + int(e[0])
		var pos: Vector3 = Data.near(e[5], pp)      # 循环世界：换成离我最近的那个像
		var p: Variant = puppets.get(key)
		if p == null or not is_instance_valid(p):
			if pos.distance_to(pp) > 240.0:
				continue
			var n := Puppet.new()
			n.owner_id = owner_id
			n.slot = int(e[0])
			n.display_name = str(e[1]).substr(0, 12)
			n.look_i = clampi(int(e[2]), 0, Realm.count() - 1)
			n.lv = int(e[3])
			n.qi = e[4] if e[4] is Color else Color(0.5, 0.95, 0.8)
			n.mate = bool(rd.net.is_mate(owner_id))
			rd.add_child(n)
			puppets[key] = n
			p = n
		p.push(pos, float(e[6]), e[7] if e[7] is Vector3 else Vector3.ZERO, float(e[8]), str(e[9]), int(e[10]), int(e[11]), int(e[12]),
				int(e[13]), int(e[3]))
