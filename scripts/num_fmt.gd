extends RefCounted
## 大数的短写（2026-11-23 数值重构：伤害 / 气血 / 战力 / 修为都上了万、亿、万亿）。照 Hammer 的 FormatNumberText：
## 一万以下写整数；往上取 4 位有效数字 + 单位（万 / 亿 / 万亿）。不用「兆」：网页 / 手机的随包字体里没有这个字。
## 故意不写 class_name：用 preload 引用（vfx.gd、player_plate.gd、progression.gd 等）。

const UNITS: Array = [[1.0e12, "万亿"], [1.0e8, "亿"], [1.0e4, "万"]]


## 4 位有效数字（去掉末尾的 0 和小数点）
static func _sig4(x: float) -> String:
	var a := absf(x)
	var dec := 0
	if a < 10.0:
		dec = 3
	elif a < 100.0:
		dec = 2
	elif a < 1000.0:
		dec = 1
	var s := ("%." + str(dec) + "f") % x
	if dec > 0:
		while s.ends_with("0"):
			s = s.left(s.length() - 1)
		if s.ends_with("."):
			s = s.left(s.length() - 1)
	return s


static func fmt(v: float) -> String:
	var a := absf(v)
	if a < 9999.5:
		return str(int(roundf(v)))
	if a >= 9.9995e15:
		# 只有大乘练到 48 级以上的修为（GM / 自检）才到这里：科学计数，免得「9580万亿」后面再拖一串
		var e := int(floorf(log(a) / log(10.0)))
		var m := _sig4(v / pow(10.0, float(e)))
		if absf(float(m)) >= 10.0:
			e += 1
			m = _sig4(v / pow(10.0, float(e)))
		return "%se%d" % [m, e]
	for u: Array in UNITS:
		var base: float = u[0]
		if a >= base * 0.99995:
			var x := v / base
			# 9999.5 万这种进位：四舍五入以后到了 10000 就进到下一个单位
			if absf(float(_sig4(x))) >= 10000.0 and base < 1.0e12:
				continue
			return _sig4(x) + str(u[1])
	return str(int(roundf(v)))


## 带一位小数的小数（打坐每息这种可能小于 1 的数）：< 100 一位小数，往上同 fmt
static func fmt1(v: float) -> String:
	if absf(v) < 100.0:
		var s := "%.1f" % v
		return s.trim_suffix(".0")
	return fmt(v)
