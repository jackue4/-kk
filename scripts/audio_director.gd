extends Node
## 背景音乐和「事件音效」的调度（2026-11-20。用户要求：用生成服务为整个游戏生成并接入打斗、升级、技能等音效，以及背景音乐）。
## 音频文件是 image-gen MCP 生成的（assets/audio/，来历和提示词见 _tasks/audio_gen/prompts.md）。分两块：
## 1. 打斗音效：原来全游戏一百多处 Sfx.play("swing" / "hit_heavy" / …) 的调用点都不动，sfx.gd 里把同名的占位合成音换成生成的文件。
## 2. 这里管的：
##    · 背景音乐三首（hub 主城 / explore 大世界游历 / battle 交战），两路播放器交叉淡入淡出：
##        不在关卡里 → hub；进了大世界 → explore；渡劫、首领逼近、飞剑对波、身边三只以上的怪在追着打（或一只精英）持续一秒多 → battle，
##        清静七秒后回 explore。自检 / 演示（命令行带自检参数）默认不放音乐（隐藏窗口里跑自检不该出声），加 `--bgm` 强开；`--no-bgm` 强关。
##    · 没有现成调用点的事件音效，靠每 0.1 秒看一眼游戏状态的「边沿」来放（不用去改别的会话正在动的玩法脚本）：
##        升级 levelup（局内等级涨了）、突破 realm_up（境界升了）、剑诀 skill_sword（Z 三式进冷却的那一下）、飞剑阵 sword_array（Q 开阵）、
##        大招 ult（R）、雷劫落雷 thunder、拾取 pickup（背包多了东西）、搜完一处 chest、开始读条撤离 portal、入境 horn、回主城 portal、
##        首领逼近 boss_roar、回血 heal（气血一下涨了一截）、陨落 defeat、界面按钮 ui_click（所有 Button，触屏战斗键除外）。
## fired 记每种事件放过几次、switches 记换曲的时刻，自检（`-- --audio-test`，见 selftest）看这两样。
## 手机档：音乐同一时刻最多两路（只在换曲的一两秒里），音效还是 sfx.gd 那 16 路；这里每 0.1 秒的轮询只读十来个属性。
## 故意不写 class_name。

const Sfx := preload("res://scripts/sfx.gd")
const Profile := preload("res://scripts/raid_profile.gd")

const TRACKS := {"hub": "res://assets/audio/bgm/hub.mp3", "explore": "res://assets/audio/bgm/explore.mp3", "battle": "res://assets/audio/bgm/battle.mp3"}
const BGM_DB := {"hub": -15.0, "explore": -16.0, "battle": -14.0}
const FADE := 1.6            # 换曲的淡入淡出（秒）
const SILENT := -60.0
const BUS := "Music"

var main: Node
var enabled := true
var track := ""              # 现在放的是哪首
var fired := {}              # 事件名 → 放过几次
var switches: Array = []     # [秒, 曲名]
var _streams := {}
var _bgm_stream := true      # 背景音乐走流式播放（见 _ready）
var _pl: Array[AudioStreamPlayer] = []
var _cur := 0
var _hot_t := 0.0
var _calm_t := 99.0
var _in_battle := false
var _poll := 0.0
var _time := 0.0
var _crowd_t := 0.0
var _crowd := false
# 事件边沿
var _sig := false
var _raid_id := 0
var _lv := -1
var _bag := -1
var _dead := false
var _ult := false
var _q := false
var _cd := 0.0
var _trib_n := -1
var _boss := false
var _boss_cd := 0.0
var _ex := false
var _sk := 0.0
var _hp := -1.0
var _heal_cd := 0.0
var _pick_cd := 0.0
var _was_level := false
var _click_cd := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	enabled = (not Profile.test_mode() or args.has("--bgm")) and not args.has("--no-bgm")
	# 「音乐」这条总线写在 res://default_bus_layout.tres 里，开机就有。**不要在运行时 AudioServer.add_bus()**（2026-11-21 查到的手机没声音的根因）：
	# 网页版（Godot 4.7 的「采样播放」）运行时加总线，浏览器那边会把新总线插到主总线前面，接着设「发送到 Master」时把主总线接到了新总线上，
	# 主总线和音乐总线互相接成一个圈、再也不连扬声器 —— 网页版里所有声音（音效、音乐）全都没了；桌面版走另一套混音，不受影响，所以自检一直正常。
	# 万一布局文件没带上，就退回主总线放音乐，宁可少一条总线也别把整个网页版弄哑。
	var bus := BUS if AudioServer.get_bus_index(BUS) >= 0 else "Master"
	# 背景音乐走「流式播放」（边放边解码），不走网页版默认的「采样播放」。2026-11-24 查手机上玩着玩着被浏览器杀掉、回到加载页：
	# 采样播放要把整首曲子解成浮点波形交给浏览器——70 秒的立体声一首 25.6 MB，三首开机就占 80 MB；而且引擎每放一次、每循环一次
	# 都会把整段波形再复制一份（engine.js 的 _duplicateAudioBuffer），一首曲子每 70 秒多冒 25.6 MB，要等浏览器回收。
	# 流式播放只占压缩后的一兆多；代价是声音由主线程喂，卡顿帧时音乐可能断一下（音效仍是采样播放，不受影响）。
	# `--bgm-sample` 是改之前的做法，留着在浏览器里做对比（_tasks/web_probe/mem_probe.py）。
	_bgm_stream = not args.has("--bgm-sample")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = SILENT
		if _bgm_stream:
			p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_pl.append(p)
	if enabled:
		for k: String in TRACKS.keys():
			_load(k)
	get_tree().node_added.connect(_on_node)
	if OS.has_feature("web"):
		_preregister.call_deferred()


## 网页版：音效要先整段解码、交给浏览器（「采样」）才能放，Godot 是在第一次 play() 时现做的，开机时（还在载入幕布后面）一次做完。
## 只注册音效（29 条加起来约 20 MB 波形）。背景音乐不注册：三首要 80 MB，改成流式播放了（见 _ready）。
func _preregister() -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var list: Array = []
	Sfx.ensure()
	list.append_array(Sfx.all_streams())
	for st: Variant in list:
		if st is AudioStream and not AudioServer.is_stream_registered_as_sample(st):
			AudioServer.register_stream_as_sample(st)
			n += 1
	print("[audio] 网页端预先注册音效采样 %d 个，用时 %d ms；背景音乐 %s、%s" % [n, Time.get_ticks_msec() - t0, "开" if enabled else "关",
			"流式播放" if _bgm_stream else "采样播放（对比用）"])


func _load(k: String) -> AudioStream:
	if _streams.has(k):
		return _streams[k]
	var path: String = TRACKS[k]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	_streams[k] = s
	return s


## 界面按钮的点击声：所有 Button 进树时挂一下（触屏战斗键那一层不挂，免得每次出招都响）
func _on_node(n: Node) -> void:
	if not (n is BaseButton):
		return
	var p := n.get_parent()
	while p != null:
		var sc: Variant = p.get_script()
		if sc != null and str(sc.resource_path).ends_with("touch_controls.gd"):
			return
		p = p.get_parent()
	(n as BaseButton).pressed.connect(_click)


func _click() -> void:
	if _click_cd <= 0.0:
		_click_cd = 0.06
		emit("ui_click", -11.0)


## 放一个事件音效，并记数
func emit(name: String, db := 0.0, pitch := 1.0) -> void:
	fired[name] = int(fired.get(name, 0)) + 1
	Sfx.play(name, db, pitch)


# ---------- 背景音乐 ----------

## 换到 k 这首（"" = 静下来）
func play_track(k: String) -> void:
	if k == track:
		return
	track = k
	switches.append([snappedf(_time, 0.1), k if k != "" else "（静）"])
	if k == "" or not enabled:
		return
	var s := _load(k)
	if s == null:
		return
	_cur = 1 - _cur
	var p := _pl[_cur]
	p.stream = s
	p.volume_db = SILENT
	p.play()


func _tick_music(dt: float) -> void:
	for i in 2:
		var p := _pl[i]
		var want := float(BGM_DB.get(track, -15.0)) if (i == _cur and track != "" and enabled) else SILENT
		if p.volume_db < want:
			# 淡入走线性分贝太慢，前半段快一点
			p.volume_db = minf(p.volume_db + (60.0 if p.volume_db < -30.0 else 22.0) * dt / FADE * 1.6, want)
		elif p.volume_db > want:
			p.volume_db = maxf(p.volume_db - 30.0 * dt / FADE, want)
			if p.volume_db <= SILENT + 0.5 and p.playing:
				p.stop()


func _want_track(level: Variant, rd: Variant, player: Variant, dt: float) -> String:
	if level == null:
		_in_battle = false
		_hot_t = 0.0
		return "hub"
	var hot := false
	if rd != null:
		hot = bool(rd.get("_in_trib")) or _crowd
		var b: Variant = rd.get("_boss_near")
		if b != null and is_instance_valid(b) and bool(b.call("is_hostile")):
			hot = true
	if player != null and player.air != null and bool(player.air.in_clash()):
		hot = true
	if hot:
		_hot_t += dt
		_calm_t = 0.0
		if _hot_t > 1.2:
			_in_battle = true
	else:
		_hot_t = 0.0
		_calm_t += dt
		if _calm_t > 7.0:
			_in_battle = false
	return "battle" if _in_battle else "explore"


## 身边有没有「一群」在追着打的怪：22 米内三只以上，或 30 米内一只精英（半秒数一次）
func _count_crowd(rd: Variant, player: Variant) -> void:
	var n := 0
	var elite := false
	var pp: Vector3 = player.global_position
	for m: Variant in rd.get("_mobs"):
		if not is_instance_valid(m) or not bool(m.is_hostile()):
			continue
		var d: float = pp.distance_to(m.global_position)
		if d < 22.0:
			n += 1
		if d < 30.0 and bool(m.elite):
			elite = true
	_crowd = n >= 3 or elite


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	dt = dt / maxf(Engine.time_scale, 0.01)      # 顿帧 / 慢动作不拖慢音乐的淡入淡出
	_time += dt
	_click_cd -= dt
	_tick_music(dt)
	_poll -= dt
	if _poll > 0.0 or main == null:
		return
	var step := 0.1 - _poll
	_poll = 0.1
	var player: Variant = main.get("player")
	if player == null or not is_instance_valid(player):
		return
	if not _sig:
		_sig = true
		player.realm_ascended.connect(func(_i: int) -> void: emit("realm_up", -3.0))
	var level: Variant = main.get("level")
	if level != null and not is_instance_valid(level):
		level = null
	var rd: Variant = level.get("raid") if level != null else null
	if rd != null and not is_instance_valid(rd):
		rd = null
	_boss_cd -= step
	_heal_cd -= step
	_pick_cd -= step
	_crowd_t -= step
	if rd != null and _crowd_t <= 0.0:
		_crowd_t = 0.5
		_count_crowd(rd, player)
	elif rd == null:
		_crowd = false
	play_track(_want_track(level, rd, player, step))
	# 进 / 出关卡
	var in_level := level != null
	if in_level != _was_level:
		_was_level = in_level
		emit("horn" if in_level else "portal", -9.0)
	_edges(rd, player)


func _edges(rd: Variant, player: Variant) -> void:
	# 陨落、大招、飞剑阵、剑诀、回血：主角身上的
	var dead := bool(player.dead)
	if dead and not _dead:
		emit("defeat", -4.0)
	_dead = dead
	var ult := player.ult != null and bool(player.ult.active)
	if ult and not _ult:
		emit("ult", -5.0)
	_ult = ult
	var q := bool(player.mp_busy)
	if q and not _q:
		emit("sword_array", -8.0)
	_q = q
	var cd := float(player.air.cds[0]) if player.air != null else 0.0
	if cd > _cd + 0.5:
		emit("skill_sword", -7.0)
	_cd = cd
	var hp := float(player.melee.hp)
	if _hp >= 0.0 and hp > _hp + 12.0 and _hp > 0.5 and not dead and _heal_cd <= 0.0:
		_heal_cd = 1.5
		emit("heal", -10.0)
	_hp = hp
	if rd == null:
		_raid_id = 0
		_trib_n = -1
		_boss = false
		_ex = false
		_sk = 0.0
		return
	# 换了一局：基准重新记，不把「刚进图」当成升级 / 拾取
	if rd.get_instance_id() != _raid_id:
		_raid_id = rd.get_instance_id()
		_lv = int(rd.lv)
		_bag = (rd.bag as Array).size()
		_trib_n = -1
		return
	if int(rd.lv) > _lv:
		emit("levelup", -5.0)
	_lv = int(rd.lv)
	var bag := (rd.bag as Array).size()
	if bag > _bag and _pick_cd <= 0.0:
		_pick_cd = 0.15
		emit("pickup", -9.0)
	_bag = bag
	# 雷劫：每落一道雷
	var tb: Variant = rd.get("_trib") if bool(rd.get("_in_trib")) else null
	if tb != null and is_instance_valid(tb):
		var n := int(tb.get("_done"))
		if _trib_n >= 0 and n > _trib_n:
			emit("thunder", -6.0, randf_range(0.92, 1.08))
		_trib_n = n
	else:
		_trib_n = -1
	# 首领逼近
	var b: Variant = rd.get("_boss_near")
	var boss := b != null and is_instance_valid(b)
	if boss and not _boss and _boss_cd <= 0.0:
		_boss_cd = 25.0
		emit("boss_roar", -6.0)
	_boss = boss
	# 撤离读条开始、搜完一处
	var ex := float(rd.extract_k) > 0.02
	if ex and not _ex:
		emit("portal", -9.0)
	_ex = ex
	var sk := float(rd.search_k)
	if _sk > 0.9 and sk < 0.05:
		emit("chest", -8.0)
	_sk = sk


# ---------- 自检 ----------

## 一段时间里某条音频总线的峰值（分贝）
func _peak(bus: String, secs: float) -> float:
	var idx := AudioServer.get_bus_index(bus)
	var best := -200.0
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		best = maxf(best, maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0)))
	return best


## 不经过声卡、把一条音频整段解出来量：[真峰值 dB, 最响的 50 毫秒的均方根 dB, 有声的时长（秒，高于 -40 dB 的部分）]
## （音量表按帧读、短促的声音会漏掉，所以音量校正按这里量的「最响 50 毫秒」对齐）
static func measure(st: AudioStream) -> Array:
	var pb: AudioStreamPlayback = st.instantiate_playback()
	if pb == null:
		return [-200.0, -200.0, 0.0]
	pb.start(0.0)
	var rate := AudioServer.get_mix_rate()
	var total := int(minf(st.get_length(), 6.0) * rate)
	var peak := 0.0
	var best := 0.0
	var win := int(rate * 0.05)
	var acc := 0.0
	var n := 0
	var loud := 0
	var done := 0
	while done < total:
		var chunk: PackedVector2Array = pb.mix_audio(1.0, mini(4096, total - done))
		if chunk.is_empty():
			break
		done += chunk.size()
		for v: Vector2 in chunk:
			var a := maxf(absf(v.x), absf(v.y))
			peak = maxf(peak, a)
			if a > 0.01:
				loud += 1
			acc += (v.x * v.x + v.y * v.y) * 0.5
			n += 1
			if n >= win:
				best = maxf(best, acc / float(n))
				acc = 0.0
				n = 0
	pb.stop()
	return [linear_to_db(maxf(peak, 1e-9)), linear_to_db(maxf(sqrt(best), 1e-9)), float(loud) / rate]


## `-- --audio-test [--bgm]`（main.gd 开机后调）：
##   1. 每个音效文件：能不能载入、多长、单独放一遍量峰值（同名的占位合成音也量一遍，算出音量校正值）
##   2. 三首背景音乐：载入、时长、循环；按真实条件换曲（主城 → 进大世界 → 身边刷怪 → 清掉 → 渡劫 → 回主城），量音乐总线出没出声
##   3. 事件音效：升级、突破、剑诀、飞剑阵、拾取、雷劫……各触发一次，看 fired 里记没记上
func selftest() -> void:
	var tree := get_tree()
	var wait := func(sec: float) -> void:
		await tree.create_timer(sec).timeout
	await wait.call(1.0)
	print("[audio] 音频驱动 %s，混音采样率 %d；背景音乐开=%s" % [AudioServer.get_driver_name(), int(AudioServer.get_mix_rate()), enabled])
	# 1. 音效：整段解出来量（不经过声卡）
	Sfx.ensure()
	var missing: Array = []
	var total := 0
	var ref: Array = []
	for name: String in Sfx.GEN:
		var pr0: AudioStream = Sfx.proc_stream(name)
		if pr0 != null:
			ref.append(float(measure(pr0)[1]))
	ref.sort()
	var ref_db: float = ref[ref.size() / 2] if not ref.is_empty() else -14.0
	print("[audio] 占位合成音「最响 50 毫秒」的中位数 %.1f dB（没有占位音的新名字按它对齐）" % ref_db)
	for name: String in Sfx.GEN:
		var g: AudioStream = Sfx.gen_stream(name)
		if g == null:
			missing.append(name)
			continue
		total += 1
		var gm := measure(g)
		var line := "[audio] %-12s 生成 %.2f 秒（有声 %.2f 秒）峰值 %6.1f dB 最响处 %6.1f dB" % [name, g.get_length(), float(gm[2]), float(gm[0]), float(gm[1])]
		var want := ref_db
		var pr: AudioStream = Sfx.proc_stream(name)
		if pr != null:
			var pm := measure(pr)
			want = float(pm[1])
			line += "｜占位音 %.2f 秒 最响处 %6.1f dB" % [pr.get_length(), float(pm[1])]
		else:
			line += "｜新名字"
		line += " → 对齐要 %+.1f dB｜现在的校正 %+.1f dB" % [want - float(gm[1]), float(Sfx.GAIN.get(name, 0.0))]
		print(line)
	print("[audio] 音效文件 %d / %d 个可用%s" % [total, Sfx.GEN.size(), "" if missing.is_empty() else "，缺：" + "、".join(missing)])
	for k: String in TRACKS.keys():
		var bs := _load(k)
		if bs != null:
			var bm := measure(bs)
			print("[audio] 背景音乐 %-8s 前 6 秒：峰值 %.1f dB、最响处 %.1f dB（播放时再压 %.0f dB）" % [k, float(bm[0]), float(bm[1]), float(BGM_DB[k])])
	# 2. 背景音乐
	for k: String in TRACKS.keys():
		var s := _load(k)
		print("[audio] 背景音乐 %-8s：%s" % [k, "载入失败" if s == null else "%.1f 秒，循环=%s" % [s.get_length(), (s as AudioStreamMP3).loop if s is AudioStreamMP3 else false]])
	var hub: Variant = main.get("hub")
	await wait.call(2.5)
	var p0: float = await _peak(BUS, 1.0)
	print("[audio] 开机 3.5 秒：在放 %s（主城=%s），音乐总线峰值 %.1f dB" % [track, hub != null and bool(hub.get("active")), p0])
	main.call("_enter_level", "meadow")
	var t0 := Time.get_ticks_msec()
	while (main.get("level") == null or bool(main.get("_switching"))) and Time.get_ticks_msec() - t0 < 90000:
		await wait.call(0.2)
	var rd: Variant = main.level.raid
	var player: Variant = main.player
	await wait.call(3.0)
	var p1: float = await _peak(BUS, 1.0)
	print("[audio] 进大世界 3 秒后：在放 %s，音乐总线峰值 %.1f dB；入境号角放了 %d 次" % [track, p1, int(fired.get("horn", 0))])
	# 身边刷四只追着打的怪
	for m: Variant in rd._mobs.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	rd._mobs.clear()
	rd._wave_t = 999.0
	rd.spawn_guards(player.global_position, int(rd.region), 4, false, true)
	var tb0 := _time
	while track != "battle" and _time - tb0 < 6.0:
		player.melee.hp = 100.0
		await tree.process_frame
	var p2: float = await _peak(BUS, 2.5)
	print("[audio] 身边刷四只扑过来的怪：%.1f 秒后换到 %s，音乐总线峰值 %.1f dB" % [_time - tb0, track, p2])
	var purge := [true]
	var purger := func() -> void:
		# 后面几步不要怪来打岔：刷出来一只清一只
		while purge[0] and is_instance_valid(rd):
			for m: Variant in rd._mobs.duplicate():
				if is_instance_valid(m):
					m.queue_free()
			rd._mobs.clear()
			player.melee.hp = 100.0
			await tree.process_frame
	purger.call()
	var tc0 := _time
	while track != "explore" and _time - tc0 < 14.0:
		await tree.process_frame
	print("[audio] 怪清掉后（之后刷出来的也一直清）：%.1f 秒回到 %s（设定是清静 7 秒）" % [_time - tc0, track])
	# 3. 事件音效
	var before := fired.duplicate()
	rd.add_exp(float(preload("res://scripts/raid_data.gd").xp_need(int(rd.lv))) * 0.6)
	rd.add_exp(float(preload("res://scripts/raid_data.gd").xp_need(int(rd.lv))) * 0.6)
	await wait.call(0.5)
	rd.bag.append(preload("res://scripts/raid_data.gd").make_gear(1, RandomNumberGenerator.new()))      # 直接往背包里放一件（= 拾到了）
	await wait.call(0.6)
	var tmp_btn := Button.new()
	add_child(tmp_btn)
	tmp_btn.pressed.emit()
	tmp_btn.queue_free()
	player.set_realm(2, false)
	player.take_air()
	await wait.call(1.2)
	player.mp = player.mp_max()
	player.air.press_skill(0)
	await wait.call(1.0)
	for on: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "summon"
		ev.pressed = on
		Input.parse_input_event(ev)
		await wait.call(0.1)
	await wait.call(0.8)
	main.swords.dismiss_all()
	player.force_ground()
	await wait.call(0.5)
	player.set_realm(3)
	await wait.call(1.0)
	purge[0] = false
	rd.gm_tribulation(4)
	var tt0 := Time.get_ticks_msec()
	while not bool(rd.trib_active()) and Time.get_ticks_msec() - tt0 < 4000:
		await wait.call(0.1)
	if bool(rd.trib_active()):
		rd._trib.demo_auto = 0.9
	var tw0 := _time
	while track != "battle" and _time - tw0 < 6.0:
		await tree.process_frame
	print("[audio] 渡劫开始：%.1f 秒后换到 %s" % [_time - tw0, track])
	while bool(rd.get("_in_trib")) and _time - tw0 < 45.0:
		await wait.call(0.3)
	var parts: Array = []
	for k: String in ["levelup", "pickup", "skill_sword", "sword_array", "realm_up", "thunder", "heal", "ui_click", "boss_roar", "ult", "defeat", "chest", "portal", "horn"]:
		parts.append("%s +%d" % [k, int(fired.get(k, 0)) - int(before.get(k, 0))])
	print("[audio] 事件音效（经验涨两级、背包进一件、点一个按钮、放一式剑诀、按一次飞剑阵、突破一次、渡一场雷劫）：%s" % "、".join(parts))
	main.call("_return_to_hall")
	var t9 := Time.get_ticks_msec()
	while (main.get("level") != null or bool(main.get("_switching"))) and Time.get_ticks_msec() - t9 < 30000:
		await wait.call(0.2)
	await wait.call(2.5)
	var p9: float = await _peak(BUS, 1.0)
	print("[audio] 回主城 2.5 秒后：在放 %s，音乐总线峰值 %.1f dB" % [track, p9])
	print("[audio] 换曲记录：%s" % str(switches))
	var top: Array = []
	for k: String in Sfx.counts.keys():
		top.append([int(Sfx.counts[k]), k])
	top.sort()
	top.reverse()
	print("[audio] 这一趟各音效放了几次：%s" % "、".join(top.map(func(e: Array) -> String: return "%s %d" % [e[1], e[0]])))
