class_name MathUtil
extends RefCounted

static func clamp(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))


static func fmt_money(n: int) -> String:
	var abs_n := absi(n)
	var s := str(abs_n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-$" if n < 0 else "$") + out


static func fmt_pct(ratio: float) -> String:
	return "%d%%" % int(round(ratio * 100.0))


static func uid() -> String:
	return "%08x" % (randi() & 0xFFFFFFFF)
