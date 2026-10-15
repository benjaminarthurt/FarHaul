class_name RadioVoice
extends RefCounted
## Radio voices, made in code: made-up syllables from a buzzing source through three vowel formants,
## shaped like speech, then through a cheap transmitter (band-passed 320 to 2900 Hz, overdriven, a little
## grit) with hiss under it that gets worse with distance and a fade in and out when it's far. Each
## species has its own pitch, pace and timbre (comms.json voices); each speaker its own seed, so the same
## ship sounds the same every time. Subtitles carry the words. Also the hail chime, the squelch and the
## SOS beacon. Everything is a mono AudioStreamWAV at RATE.

const RATE := 11025
const VOWELS := [[730.0, 1090.0, 2440.0], [530.0, 1840.0, 2480.0], [300.0, 2200.0, 2900.0], [570.0, 840.0, 2410.0], [440.0, 1020.0, 2240.0]]

static var _cache := {}


## A speaker's voice: {f0, rate, scale, breath} for `species`, varied by `seed_v`.
static func voice(species: String, seed_v: int) -> Dictionary:
	var vs: Dictionary = Comms.cfg().get("voices", {})
	var v: Dictionary = vs.get(species, vs.get("human", {"f0": [120, 180], "rate": 1.0, "scale": 1.0, "breath": 0.0}))
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var f0: Array = v.get("f0", [120, 180])
	return {"f0": r.randf_range(float(f0[0]), float(f0[1])), "rate": float(v.get("rate", 1.0)) * r.randf_range(0.93, 1.07),
			"scale": float(v.get("scale", 1.0)) * r.randf_range(0.96, 1.04), "breath": float(v.get("breath", 0.0)), "seed": seed_v}


## How long `text` takes to say in `v`, in seconds (before the squelch).
static func duration(text: String, v: Dictionary) -> float:
	return float(_syllables(text)) * 0.17 / float(v.get("rate", 1.0))


static func _syllables(text: String) -> int:
	return clampi(roundi(float(text.length()) / 4.2), 3, 44)


## `text` said in voice `v` over the radio, `dist` 0 (alongside) to 1 (barely there): squelch open, the
## words, squelch close and the roger beep.
static func speech(text: String, v: Dictionary, dist := 0.2) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = int(v.get("seed", 1)) ^ hash(text)
	var out := PackedFloat32Array()
	out.append_array(_squelch(r, true))
	var words := _babble(text, v, r)
	out.append_array(_radio(words, dist, r))
	out.append_array(_squelch(r, false))
	return _wav(out)


## The two-tone chime of an incoming call.
static func chime() -> AudioStreamWAV:
	if not _cache.has("chime"):
		var a := PackedFloat32Array()
		a.append_array(_tone(880.0, 0.12, 0.35))
		a.append_array(_silence(0.03))
		a.append_array(_tone(1320.0, 0.18, 0.35))
		_cache["chime"] = _wav(a)
	return _cache["chime"]


## A distress beacon: SOS in Morse at 1 kHz, through the radio, far off.
static func sos() -> AudioStreamWAV:
	if not _cache.has("sos"):
		var a := PackedFloat32Array()
		for sym in "...---...":
			a.append_array(_tone(1000.0, 0.08 if sym == "." else 0.24, 0.3))
			a.append_array(_silence(0.08))
		var r := RandomNumberGenerator.new()
		r.seed = 99
		_cache["sos"] = _wav(_radio(a, 0.7, r))
	return _cache["sos"]


## Just the squelch: a channel opening or closing with nobody saying anything.
static func click(closing := false) -> AudioStreamWAV:
	var key := "click_close" if closing else "click_open"
	if not _cache.has(key):
		var r := RandomNumberGenerator.new()
		r.seed = 7
		_cache[key] = _wav(_squelch(r, not closing))
	return _cache[key]


# --- Synthesis ------------------------------------------------------------------------------------

static func _babble(text: String, v: Dictionary, r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := _syllables(text)
	var rate := float(v.get("rate", 1.0))
	var f0 := float(v.get("f0", 150.0))
	var scale := float(v.get("scale", 1.0))
	var breath := float(v.get("breath", 0.0))
	var left := n
	while left > 0:
		var in_word := mini(left, r.randi_range(1, 3))
		for s in in_word:
			out.append_array(_syllable(f0 * r.randf_range(0.92, 1.1), r.randf_range(0.09, 0.19) / rate, VOWELS[r.randi() % VOWELS.size()], scale, breath, r))
		left -= in_word
		out.append_array(_silence(r.randf_range(0.04, 0.12) / rate))
	var peak := 0.0001
	for x in out:
		peak = maxf(peak, absf(x))
	for i in out.size():
		out[i] = out[i] / peak * 0.8
	return out


static func _syllable(f0: float, dur: float, vowel: Array, scale: float, breath: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var wob := r.randf_range(1.0, 3.0)
	var bend := r.randf_range(-0.06, 0.06)
	var ph := 0.0
	var coef := []
	for k in 3:   # the three formants: two-pole resonators
		var f := float(vowel[k]) * scale
		var bw := 90.0 + 40.0 * k
		var rr := exp(-PI * bw / RATE)
		coef.append([1.0 - rr, 2.0 * rr * cos(TAU * f / RATE), -rr * rr, 1.0 / (k + 1.0)])
	var y1 := [0.0, 0.0, 0.0]
	var y2 := [0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		ph += f0 * (1.0 + 0.08 * sin(TAU * wob * t) + bend) / RATE
		var src := 2.0 * fposmod(ph, 1.0) - 1.0
		if breath > 0.0:
			src += breath * r.randfn()
		var s := 0.0
		for k in 3:
			var c: Array = coef[k]
			var y := float(c[0]) * src + float(c[1]) * float(y1[k]) + float(c[2]) * float(y2[k])
			y2[k] = y1[k]
			y1[k] = y
			s += y * float(c[3])
		out[i] = s * minf(1.0, t / 0.02) * minf(1.0, (dur - t) / 0.04)
	if r.randf() < 0.6:   # a consonant: a short burst of noise at the start
		var c := mini(int(0.035 * RATE), n)
		var hp := 0.0
		for i in c:
			var w := r.randfn()
			hp = w - hp * 0.6
			out[i] += hp * 0.25 * (1.0 - float(i) / c)
	return out


## Through the transmitter: band-passed, overdriven, gritty, with hiss; far away, it fades in and out.
static func _radio(x: PackedFloat32Array, dist: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var y := _biquad(_biquad(x, _hp(320.0)), _hp(320.0))
	y = _biquad(_biquad(y, _lp(2900.0)), _lp(2900.0))
	var noise := PackedFloat32Array()
	noise.resize(y.size())
	for i in noise.size():
		noise[i] = r.randfn()
	noise = _biquad(_biquad(noise, _hp(1500.0)), _lp(4800.0))
	var hiss := 0.05 * (1.0 + clampf(dist, 0.0, 1.0) * 3.0)
	var drive := 3.0
	var norm := tanh(drive)
	for i in y.size():
		var v := tanh(y[i] * drive * 2.2) / norm
		v = round(v * 48.0) / 48.0
		if dist > 0.2:
			v *= 0.75 + 0.25 * sin(TAU * 0.7 * float(i) / RATE)
		y[i] = v * 0.7 + noise[i] * hiss
	return y


static func _squelch(r: RandomNumberGenerator, opening: bool) -> PackedFloat32Array:
	var n := int(0.16 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = r.randfn() * 0.35 * pow(1.0 - float(i) / n, 2.0)
	out = _biquad(_biquad(out, _hp(800.0)), _lp(4800.0))
	for i in 30:
		out[i] += sin(PI * i / 30.0) * (0.9 if opening else -0.9)
	if not opening:   # the roger beep
		var beep := _tone(1450.0, 0.09, 0.3)
		var cut := int(0.05 * RATE)
		var joined := out.slice(0, cut)
		joined.append_array(beep)
		joined.append_array(out.slice(cut))
		return joined
	return out


static func _tone(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = amp * sin(TAU * f * t) * minf(1.0, t / 0.01) * minf(1.0, (dur - t) / 0.03)
	return out


static func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


# RBJ biquads: [b0, b1, b2, a1, a2], normalised.
static func _lp(f: float, q := 0.707) -> Array:
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var cw := cos(w)
	var a0 := 1.0 + al
	return [(1.0 - cw) / 2.0 / a0, (1.0 - cw) / a0, (1.0 - cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - al) / a0]


static func _hp(f: float, q := 0.707) -> Array:
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var cw := cos(w)
	var a0 := 1.0 + al
	return [(1.0 + cw) / 2.0 / a0, -(1.0 + cw) / a0, (1.0 + cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - al) / a0]


static func _biquad(x: PackedFloat32Array, c: Array) -> PackedFloat32Array:
	var b0 := float(c[0])
	var b1 := float(c[1])
	var b2 := float(c[2])
	var a1 := float(c[3])
	var a2 := float(c[4])
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var v := b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = v
		y[i] = v
	return y


static func _wav(x: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(x.size() * 2)
	for i in x.size():
		bytes.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
