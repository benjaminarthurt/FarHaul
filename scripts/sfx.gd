class_name Sfx
extends RefCounted
## Tiny synthesised sound effects, generated in code so there are no audio files to manage.
## Placeholder feel: thumps, ticks, a chime. Real sound design comes later.

const RATE := 22050

static var _cache: Dictionary = {}


static func stream(name: StringName) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var data: PackedFloat32Array
	match name:
		&"place":
			data = _thunk()
		&"remove":
			data = _tick_down()
		&"error":
			data = _buzz()
		&"cash":
			data = _chime()
		&"select":
			data = _blip()
		&"launch":
			data = _whoosh()
		_:
			data = _blip()
	var s := _to_stream(data)
	_cache[name] = s
	return s


static func _to_stream(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(int(data[i] * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


static func _thunk() -> PackedFloat32Array:
	var out := _buffer(0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (45.0 + 80.0 * exp(-t * 9.0)) / RATE
		out[i] = sin(phase) * exp(-t * 20.0) * 0.85 + rng.randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.35
	return out


static func _tick_down() -> PackedFloat32Array:
	var out := _buffer(0.14)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (800.0 * exp(-t * 14.0) + 160.0) / RATE
		out[i] = sin(phase) * exp(-t * 26.0) * 0.5
	return out


static func _buzz() -> PackedFloat32Array:
	var out := _buffer(0.24)
	for i in out.size():
		var t := float(i) / RATE
		var gate := 1.0 if fmod(t, 0.12) < 0.07 else 0.0
		out[i] = (1.0 if fmod(t * 150.0, 1.0) < 0.5 else -1.0) * gate * 0.22
	return out


static func _chime() -> PackedFloat32Array:
	var out := _buffer(0.6)
	for i in out.size():
		var t := float(i) / RATE
		var v := sin(TAU * 880.0 * t) * exp(-t * 8.0)
		if t > 0.09:
			v += sin(TAU * 1320.0 * (t - 0.09)) * exp(-(t - 0.09) * 8.0)
		out[i] = v * 0.3
	return out


static func _blip() -> PackedFloat32Array:
	var out := _buffer(0.04)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * 1500.0 * t) * exp(-t * 110.0) * 0.28
	return out


static func _whoosh() -> PackedFloat32Array:
	var out := _buffer(2.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var env := minf(t / 0.6, 1.0) * exp(-maxf(t - 1.4, 0.0) * 3.5)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.03 + 0.2 * minf(t / 1.8, 1.0))
		out[i] = (lp * 1.6 + sin(TAU * 55.0 * t) * 0.35) * env * 0.5
	return out
