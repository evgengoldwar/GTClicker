class_name NumFormat
extends RefCounted
## Форматирование чисел (раздел 3 дизайн-документа): 4 режима, 3 значащие цифры.

enum Mode { SI, SHORT, SCIENTIFIC, FULL }

const SI_SUFFIXES: Array[String] = ["", "k", "M", "G", "T", "P", "E", "Z", "Y", "R", "Q"]
const SHORT_SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd"]
## Выше этого «полный» режим переходит на научную запись (граница int64).
const FULL_LIMIT := 9.0e18

static var mode: Mode = Mode.SI


static func format(value: float, m: int = -1) -> String:
	var use_mode: int = mode if m < 0 else m
	if is_nan(value):
		return "NaN"
	if is_inf(value):
		return "∞" if value > 0 else "-∞"
	var sign_str := "-" if value < 0.0 else ""
	var v := absf(value)
	if v < 1000.0:
		return sign_str + _small(v)
	match use_mode:
		Mode.SI:
			return sign_str + _suffixed(v, SI_SUFFIXES)
		Mode.SHORT:
			return sign_str + _suffixed(v, SHORT_SUFFIXES)
		Mode.SCIENTIFIC:
			return sign_str + _scientific(v)
		_:
			if v >= FULL_LIMIT:
				return sign_str + _scientific(v)
			return sign_str + group_digits(int(roundf(v)))


## Точное число с разделителями разрядов — для тултипов.
static func full(value: int) -> String:
	if value < 0:
		return "-" + group_digits(-value)
	return group_digits(value)


static func group_digits(value: int) -> String:
	var s := str(value)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


## Скорость в секунду: «+1.23k/с».
static func rate(per_sec: float) -> String:
	var prefix := "+" if per_sec > 0.0 else ""
	return prefix + format(per_sec) + TranslationServer.translate("UNIT_PER_SEC")


## «6 ч 12 мин», «45 с».
static func duration(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	var h := floori(s / 3600.0)
	var mins := floori((s % 3600) / 60.0)
	var sec := s % 60
	var tr_h := TranslationServer.translate("UNIT_HOURS")
	var tr_m := TranslationServer.translate("UNIT_MINUTES")
	var tr_s := TranslationServer.translate("UNIT_SECONDS")
	if h > 0:
		return "%d %s %d %s" % [h, tr_h, mins, tr_m]
	if mins > 0:
		return "%d %s %d %s" % [mins, tr_m, sec, tr_s]
	return "%d %s" % [sec, tr_s]


static func _small(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	if v >= 100.0:
		return "%.0f" % v
	if v >= 10.0:
		return "%.1f" % v
	if v >= 1.0:
		return "%.2f" % v
	if v >= 0.001:
		return "%.3f" % v
	return "0"


static func _suffixed(v: float, suffixes: Array[String]) -> String:
	var group := int(floor(log(v) / log(1000.0) + 1e-9))
	var scaled := v / pow(1000.0, group)
	# 999.6k должно стать 1.00M, а не 1000k.
	if _round3(scaled) >= 1000.0:
		group += 1
		scaled = v / pow(1000.0, group)
	if group >= suffixes.size():
		return _scientific(v)
	return _three_digits(scaled) + suffixes[group]


static func _scientific(v: float) -> String:
	var e := int(floor(log(v) / log(10.0) + 1e-9))
	var mant := v / pow(10.0, e)
	if mant >= 9.995:
		mant /= 10.0
		e += 1
	return "%.2fe%d" % [mant, e]


static func _round3(scaled: float) -> float:
	if scaled < 10.0:
		return roundf(scaled * 100.0) / 100.0
	if scaled < 100.0:
		return roundf(scaled * 10.0) / 10.0
	return roundf(scaled)


static func _three_digits(scaled: float) -> String:
	var r := _round3(scaled)
	if r < 10.0:
		return "%.2f" % r
	if r < 100.0:
		return "%.1f" % r
	return "%.0f" % r
