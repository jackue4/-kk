extends RefCounted
## 程序合成的占位音效：启动时用噪声/正弦即时合成，不依赖任何外部素材（无版权问题）。
## swing 挥砍  swing_heavy 重挥  hit 命中  hit_heavy 重击命中  block 格挡  clash 弹反对刃  execute 处决
## slam 下砸落地  thud 落地闷响  chip 碎块落地
## dodge 闪避  warp 瞬移斩  perfect 完美闪避  shatter 死亡碎裂  ascend 境界突破
## 故意不写 class_name：用 preload 引用。

const RATE := 22050

static var root: Node
static var _bank: Dictionary = {}
static var _pool: Array[AudioStreamPlayer] = []
static var _next := 0


static func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if root == null or not root.is_inside_tree():
		return
	if _bank.is_empty():
		_build()
	if not _bank.has(name):
		return
	if _pool.is_empty():
		for i in 16:
			var p := AudioStreamPlayer.new()
			root.add_child(p)
			_pool.append(p)
	var pl := _pool[_next]
	_next = (_next + 1) % _pool.size()
	pl.stream = _bank[name]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch * randf_range(0.95, 1.05)
	pl.play()


static func _build() -> void:
	_bank["swing"] = _wav(_swing(0.2, 0.55, 3))
	_bank["swing_heavy"] = _wav(_swing(0.32, 0.35, 5))
	# 命中 = 闷响 + 刀刃切入的短促撕裂，比挥空的风声"实"得多
	_bank["hit"] = _wav(_mix(_hit(0.24, 160.0, 55.0, 0.8), _slice(0.24, 11), 0.55))
	_bank["hit_heavy"] = _wav(_mix(_hit(0.42, 125.0, 36.0, 1.1), _slice(0.42, 13), 0.5))
	_bank["slam"] = _wav(_mix(_hit(0.7, 95.0, 28.0, 1.6), _rumble(0.7, 17), 0.7))
	_bank["thud"] = _wav(_hit(0.2, 110.0, 45.0, 0.6))
	_bank["chip"] = _wav(_metal(0.09, [2350.0, 3420.0, 4980.0], [60.0, 75.0, 90.0], 0.9))
	_bank["block"] = _wav(_metal(0.26, [640.0, 1050.0, 1690.0, 2450.0], [18.0, 22.0, 28.0, 34.0], 0.6))
	_bank["clash"] = _wav(_metal(0.55, [1320.0, 2210.0, 2970.0, 3830.0, 5120.0], [8.0, 10.0, 13.0, 17.0, 22.0], 1.0))
	var ex := _hit(0.6, 100.0, 32.0, 1.0)
	var ring := _metal(0.6, [880.0, 1460.0, 2330.0], [7.0, 9.0, 12.0], 0.4)
	for i in ex.size():
		ex[i] = ex[i] * 0.85 + ring[i] * 0.4
	_bank["execute"] = _wav(_norm(ex))
	# 闪避 / 瞬移：更短更亮的风声；完美闪避：一声拉长的清鸣 + 低沉风声
	_bank["dodge"] = _wav(_swing(0.15, 0.75, 21))
	_bank["warp"] = _wav(_mix(_swing(0.16, 0.95, 23), _metal(0.16, [3100.0, 4650.0], [30.0, 40.0], 0.2), 0.35))
	_bank["perfect"] = _wav(_mix(_metal(1.1, [1980.0, 2970.0, 3960.0, 5940.0], [3.0, 3.6, 4.4, 6.0], 0.25),
			_swing(1.1, 0.25, 29), 0.6))
	_bank["shatter"] = _wav(_mix(_crumble(0.75, 31), _hit(0.75, 120.0, 40.0, 0.9), 0.45))
	_bank["ascend"] = _wav(_rise(1.6))


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _norm(s: PackedFloat32Array, peak := 0.85) -> PackedFloat32Array:
	var m := 1e-6
	for v in s:
		m = maxf(m, absf(v))
	for i in s.size():
		s[i] = s[i] * peak / m
	return s


## 挥砍：带通噪声，截止频率随挥速扫上去再落下，快起慢收
static func _swing(dur: float, bright: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := pow(sin(PI * pow(t, 0.55)), 2.0)
		var c1 := lerpf(0.06, bright, sin(PI * pow(t, 0.7)))
		lp1 += (rng.randf_range(-1.0, 1.0) - lp1) * c1
		lp2 += (lp1 - lp2) * 0.05
		s[i] = (lp1 - lp2) * env
	return _norm(s, 0.7)


## 命中：下滑的低频闷响 + 一小段噪声撕裂
static func _hit(dur: float, f0: float, f1: float, body: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f1, f0, exp(-t * 22.0))
		ph += TAU * f / RATE
		var thump := sin(ph) * exp(-t * (14.0 / body))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var crack := lp * exp(-t * 55.0) * 0.9
		var hiss := rng.randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.35
		s[i] = thump + crack + hiss
	return _norm(s)


## 两段等长叠加（b 截到 a 的长度）
static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, kb: float) -> PackedFloat32Array:
	for i in mini(a.size(), b.size()):
		a[i] += b[i] * kb
	return _norm(a)


## 刀刃切入：高通噪声的极短爆裂，带一点下滑的"嘶"
static func _slice(dur: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.25
		s[i] = (x - lp) * (exp(-t * 70.0) + 0.25 * exp(-t * 18.0))
	return _norm(s, 0.8)


## 砸地的低频隆隆 + 碎石沙沙
static func _rumble(dur: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.04
		var grit := rng.randf_range(-1.0, 1.0) * (0.15 + 0.85 * float(rng.randf() < 0.04)) * exp(-t * 9.0)
		s[i] = lp * 4.0 * exp(-t * 5.0) + grit * 0.5
	return _norm(s, 0.8)


## 碎裂：一串密集、逐渐稀疏的细碎"喀啦"（随机时刻的短促高频脉冲）
static func _crumble(dur: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in 70:
		var t0 := pow(rng.randf(), 2.2) * dur * 0.85
		var f := rng.randf_range(1800.0, 5200.0)
		var a := rng.randf_range(0.3, 1.0) * (1.0 - t0 / dur)
		var i0 := int(t0 * RATE)
		for j in int(0.025 * RATE):
			if i0 + j >= n:
				break
			var t := float(j) / RATE
			s[i0 + j] += sin(TAU * f * t) * exp(-t * 260.0) * a + rng.randf_range(-1.0, 1.0) * exp(-t * 600.0) * a * 0.5
	return _norm(s)


## 突破：几条五度/八度叠起来的正弦，音高缓缓上扬，像一声长长的清鸣
static func _rise(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := [0.0, 0.0, 0.0, 0.0]
	var base := [330.0, 495.0, 660.0, 990.0]
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var env := minf(t / 0.05, 1.0) * pow(1.0 - u, 1.6)
		var v := 0.0
		for k in 4:
			var f: float = base[k] * (1.0 + 0.5 * smoothstep(0.0, 0.5, u))
			ph[k] += TAU * f / RATE
			v += sin(ph[k]) / (1.0 + k * 0.7)
		s[i] = v * env * (1.0 + 0.15 * sin(TAU * 6.0 * t))
	return _norm(s, 0.7)


## 金属：几条不成谐波的衰减正弦 + 起手的一下"嗒"
static func _metal(dur: float, freqs: Array, decays: Array, click: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var a := 1.0 / (1.0 + 0.45 * k)
			v += sin(TAU * float(freqs[k]) * t + k * 1.3) * a * exp(-t * float(decays[k]))
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 260.0) * click * 1.6
		v += sin(TAU * 170.0 * t) * exp(-t * 40.0) * 0.5
		s[i] = v
	return _norm(s)
