class_name VoiceBank
extends RefCounted
## Recorded voices (assets/audio/voice, made by tools/voice/generate.py): finds the clips for a line the
## game is about to say, so it's heard spoken instead of babbled.
##
## A line is found by the same id tools/voice/build_lines.py gives it: "<source>:<key>|<index>" plus
## "|<name>=<value>" for each value the spoken line fills in from a small set (the berth, the fine, the
## tonnes, the species...), sorted by name: "comms:cleared|0|berth=6". Names the game fills in (ships,
## stations, places, prices) are never spoken, so a line with one is still found; the subtitle shows them.
##
## Who says it: a speaker recorded for that line, of the caller's species if there is one, chosen by a hash
## of who's calling, so a station or a ship keeps its voice. Each line has one or more takes; the last few
## played are skipped so the same clip doesn't come round twice in a row.
##
## Off (GameSettings "recorded_voices"), missing the index, or no recording for a line: the caller falls
## back to RadioVoice's babble.

const SETS_NUMERIC := ["berth", "fine", "camp_fine", "t", "rescue_t", "crew"]
const ALIAS := {"rescue_t": "t", "camp_fine": "fine"}   ## a spoken set name -> the game's own argument name
const RECENT := 4

static var root := "res://assets/audio/voice"
static var _index := {}
static var _loaded := false
static var _shapes := {}     ## "<key>|<index>" -> the value names its ids carry
static var _recent: Array = []


static func index() -> Dictionary:
	if not _loaded:
		_loaded = true
		_index = {}
		_shapes = {}
		var p := root.path_join("index.json")
		if FileAccess.file_exists(p):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(parsed) == TYPE_DICTIONARY:
				_index = parsed
		for id in (_index.get("clips", {}) as Dictionary):
			var bits := String(id).split("|")
			var names := []
			for k in range(2, bits.size()):
				names.append(bits[k].get_slice("=", 0))
			_shapes[bits[0] + "|" + bits[1]] = names
	return _index


## Forget the loaded index (after a change of `root`, in tests).
static func refresh() -> void:
	_loaded = false
	_recent.clear()
	index()


static func available() -> bool:
	return not (index().get("clips", {}) as Dictionary).is_empty()


static func enabled() -> bool:
	return bool(GameSettings.get_value("recorded_voices")) and available()


## The recorded id for a line: `key` "comms:cleared", `i` which of its lines, `args` what the game filled
## in. "" when the line isn't recorded in that shape.
static func line_id(key: String, i: int, args: Dictionary) -> String:
	index()
	var shape = _shapes.get("%s|%d" % [key, i])
	if shape == null:
		return ""
	var id := "%s|%d" % [key, i]
	for name in shape:
		var v := _value(String(name), args)
		if v == "":
			return ""
		id += "|%s=%s" % [name, v]
	return id


static func _value(name: String, args: Dictionary) -> String:
	var raw := String(args.get(ALIAS.get(name, name), args.get(name, "")))
	if name in SETS_NUMERIC:
		var digits := ""
		for c in raw:
			if c >= "0" and c <= "9":
				digits += c
			elif c == ".":
				break
		return str(int(digits)) if digits != "" else ""
	if name == "species":
		return raw.to_lower()
	if name == "problem":   # the problem's place in comms.json's list
		var probs: Array = (Comms.cfg().get("distress", {}) as Dictionary).get("problems", [])
		var k := probs.find(raw)
		return str(k) if k >= 0 else ""
	return raw


## Clips for a run of lines said together by one speaker: `refs` [{key, index, args}], `species` the
## caller's, `who` a stable hash of the caller. Empty unless every line has a recording by the same speaker.
static func clips(refs: Array, species: String, who: int) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	if refs.is_empty():
		return out
	var clips_by_id: Dictionary = index().get("clips", {})
	var ids := []
	for r in refs:
		var id := line_id(String(r.key), int(r.index), r.get("args", {}))
		if id == "" or not clips_by_id.has(id):
			return out
		ids.append(id)
	var who_said := []   # speakers who said every one of them
	for sp in (clips_by_id[ids[0]] as Dictionary):
		var all := true
		for id in ids:
			if not (clips_by_id[id] as Dictionary).has(sp):
				all = false
		if all:
			who_said.append(sp)
	if who_said.is_empty():
		return out
	who_said.sort()
	var speakers: Dictionary = index().get("speakers", {})
	var mine := who_said.filter(func(sp) -> bool: return String((speakers.get(sp, {}) as Dictionary).get("species", "")) == species)
	var pool: Array = mine if not mine.is_empty() else who_said
	var speaker := String(pool[absi(who) % pool.size()])
	for id in ids:
		var takes: Array = (clips_by_id[id] as Dictionary)[speaker]
		var fresh := takes.filter(func(f) -> bool: return not (f in _recent))
		var f := ""
		if not fresh.is_empty():
			f = String(fresh.pick_random())
		else:   # all heard lately: the one heard longest ago
			var best := 1 << 30
			for t in takes:
				var at := _recent.rfind(t)
				if at < best:
					best = at
					f = String(t)
			_recent.erase(f)
		var s := _load(f)
		if s == null:
			out.clear()
			return out
		_recent.append(f)
		if _recent.size() > RECENT:
			_recent.pop_front()
		out.append(s)
	return out


static func _load(rel: String) -> AudioStream:
	var p := root.path_join(rel)
	if ResourceLoader.exists(p):
		return load(p) as AudioStream
	if FileAccess.file_exists(p):   # not imported yet (a fresh recording, run from source)
		return AudioStreamOggVorbis.load_from_file(p)
	return null


## One stream that plays `parts` back to back with a short breath between.
static func joined(parts: Array[AudioStream]) -> AudioStream:
	if parts.size() == 1:
		return parts[0]
	var pl := AudioStreamPlaylist.new()
	pl.loop = false
	pl.fade_time = 0.08
	pl.stream_count = parts.size()
	for k in parts.size():
		pl.set_list_stream(k, parts[k])
	return pl


static func length(parts: Array[AudioStream]) -> float:
	var t := 0.0
	for s in parts:
		t += s.get_length()
	return t


# --- How each species sounds ------------------------------------------------------------------------

static func sound(species: String) -> Dictionary:
	return (Comms.cfg().get("species_sound", {}) as Dictionary).get(species, {})


static func translator() -> Dictionary:
	return (Comms.cfg().get("species_sound", {}) as Dictionary).get("translator", {})


## The bus a species' voice plays on: its own effects (comms.json species_sound), then the radio
## (`radio`) or straight into Effects (a passenger in the room). Humans go straight there.
static func species_bus(species: String, radio := true) -> String:
	var to := radio_bus() if radio else GameSettings.bus("Effects")
	var cfg := sound(species)
	if species == "human" or cfg.is_empty() or (not cfg.has("reverb") and not cfg.has("phaser") and not cfg.has("chorus_wet")):
		return to
	var name := "Voice_%s_%s" % [species, "radio" if radio else "room"]
	if AudioServer.get_bus_index(name) >= 0:
		return name
	var i := _add_bus(name, to)
	if cfg.has("phaser"):
		var ph := AudioEffectPhaser.new()
		var c: Dictionary = cfg.phaser
		ph.rate_hz = float(c.get("rate", 0.5))
		ph.depth = float(c.get("depth", 0.8))
		ph.feedback = float(c.get("feedback", 0.5))
		ph.range_min_hz = float(c.get("min_hz", 400.0))
		ph.range_max_hz = float(c.get("max_hz", 1600.0))
		AudioServer.add_bus_effect(i, ph)
	if cfg.has("chorus_wet"):
		var ch := AudioEffectChorus.new()
		ch.voice_count = int(cfg.get("chorus_voices", 2))
		ch.wet = float(cfg.chorus_wet)
		ch.dry = 1.0
		for k in ch.voice_count:   # several of them, a beat apart and a shade apart
			ch.set_voice_delay_ms(k, 14.0 + 9.0 * k)
			ch.set_voice_rate_hz(k, 0.4 + 0.25 * k)
			ch.set_voice_depth_ms(k, 1.5 + 0.5 * k)
			ch.set_voice_pan(k, -0.3 + 0.3 * k)
		AudioServer.add_bus_effect(i, ch)
	if cfg.has("reverb"):
		var rv := AudioEffectReverb.new()
		var c: Dictionary = cfg.reverb
		rv.room_size = float(c.get("room", 0.4))
		rv.damping = float(c.get("damping", 0.5))
		rv.wet = float(c.get("wet", 0.1))
		rv.dry = 1.0
		AudioServer.add_bus_effect(i, rv)
	return name


## Buses for a species' extra voices (comms.json species_sound "layers": a Kesh voice an octave down
## under its own, an Ilyan's faint octave up), each into the species bus. One player per bus plays the
## same stream alongside the voice.
static func layer_buses(species: String, radio := true) -> Array:
	var out := []
	var layers: Array = sound(species).get("layers", [])
	for k in layers.size():
		var name := "Voice_%s_%s_layer%d" % [species, "radio" if radio else "room", k]
		if AudioServer.get_bus_index(name) < 0:
			var i := _add_bus(name, species_bus(species, radio))
			var ps := AudioEffectPitchShift.new()
			ps.pitch_scale = float(layers[k].get("pitch", 0.5))
			AudioServer.add_bus_effect(i, ps)
			AudioServer.set_bus_volume_db(i, float(layers[k].get("db", -10.0)))
		out.append(name)
	return out


static func _add_bus(name: String, send: String) -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


## The streams for a line in a species' voice, with its own language first: `lead_s` seconds of it, the
## translator's chirp, then the words. `lead_s` 0 for no translator.
static func with_lead(parts: Array[AudioStream], v: Dictionary, lead_s: float) -> Array[AudioStream]:
	if lead_s <= 0.01:
		return parts
	var out: Array[AudioStream] = [RadioVoice.native(v, lead_s, int(v.get("seed", 1))), RadioVoice.translator_chirp(float(translator().get("chirp_s", 0.16)))]
	out.append_array(parts)
	return out


# --- The radio sound ----------------------------------------------------------------------------------

## The "Radio" bus: recorded lines are clean, so the transmitter happens here. Band-passed like the babble
## (RadioVoice._radio), overdriven a little and squashed; sends to Effects. `dist` 0 alongside to 1 far:
## further away is thinner and grittier (`dist` below 0 leaves it as it is).
static func radio_bus(dist := -1.0) -> String:
	GameSettings.bus("Effects")
	var i := AudioServer.get_bus_index("Radio")
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Radio")
		AudioServer.set_bus_send(i, "Effects")
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 320.0
		hp.db = AudioEffectFilter.FILTER_24DB
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 2900.0
		lp.db = AudioEffectFilter.FILTER_24DB
		var drive := AudioEffectDistortion.new()
		drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 4.0
		for e in [hp, lp, drive, comp]:
			AudioServer.add_bus_effect(i, e)
	if dist < 0.0:   # just make sure it's there
		return "Radio"
	var d := clampf(dist, 0.0, 1.0)
	(AudioServer.get_bus_effect(i, 0) as AudioEffectHighPassFilter).cutoff_hz = lerpf(320.0, 480.0, d)
	(AudioServer.get_bus_effect(i, 1) as AudioEffectLowPassFilter).cutoff_hz = lerpf(2900.0, 2300.0, d)
	var dr := AudioServer.get_bus_effect(i, 2) as AudioEffectDistortion
	dr.drive = lerpf(0.25, 0.5, d)
	dr.pre_gain = 4.0
	dr.post_gain = -4.0
	return "Radio"
