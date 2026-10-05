class_name WorldAudio
extends Node
## The everyday sounds: room tone for ports, the hab and the ship, the engine and lift jets, the suit's
## breathing, footsteps, and short cues for desks, jobs done, crates and low air. Files come from
## tools/gen_world_audio.py and can be swapped for recordings. Everything plays on the Effects bus.
##
## Loops: `loop(name)` starts one (silent until `level` sets its volume); `level(name, 0..1)` fades it.
## One-shots: `play(name)`; footsteps: `step(surface)` picks one of three at random.

const DIR := "res://assets/audio/world/"
## Loudest level of each sound, in dB at level 1.
const DB := {
	"port_hum": -16.0, "hab_hum": -15.0, "ship_hum": -17.0, "engine": -8.0, "lift": -9.0, "breath": -14.0,
	"step_metal": -15.0, "step_dust": -13.0, "low_air": -8.0, "ui": -12.0, "done": -9.0, "thud": -8.0,
}

var loops := {}        # name -> AudioStreamPlayer
var shots := {}        # name -> AudioStreamPlayer
var played: Array[String] = []   # one-shots played, in order (tests read this)
var _levels := {}
var _rng := RandomNumberGenerator.new()


func _stream(file: String, looped: bool) -> AudioStream:
	var path := DIR + file + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStreamWAV and looped:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _player(file: String, looped: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(file, looped)
	p.bus = GameSettings.bus("Effects")
	add_child(p)
	return p


## Start a loop (silent until levelled).
func loop(name: String) -> void:
	if loops.has(name):
		return
	var p := _player(name, true)
	p.volume_db = -80.0
	loops[name] = p
	_levels[name] = 0.0
	if p.stream != null:
		p.play()


## Set a loop's loudness, 0 (silent) to 1 (full); it glides there. `pitch` bends it (engines).
func level(name: String, v: float, pitch := 1.0) -> void:
	if not loops.has(name):
		loop(name)
	_levels[name] = clampf(v, 0.0, 1.0)
	(loops[name] as AudioStreamPlayer).pitch_scale = clampf(pitch, 0.5, 2.0)


func play(name: String, pitch := 1.0) -> void:
	played.append(name)
	if not shots.has(name):
		shots[name] = _player(name, false)
	var p: AudioStreamPlayer = shots[name]
	p.volume_db = float(DB.get(name.rstrip("_012"), DB.get(name, -10.0)))
	p.pitch_scale = pitch
	if p.stream != null:
		p.play()


## A footstep on "metal" (decks and port floors) or "dust" (a moon).
func step(surface: String) -> void:
	var name := "step_%s_%d" % [surface, _rng.randi() % 3]
	if not shots.has(name):
		shots[name] = _player(name, false)
	played.append(name)
	var p: AudioStreamPlayer = shots[name]
	p.volume_db = float(DB.get("step_" + surface, -14.0)) + _rng.randf_range(-2.0, 1.0)
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	if p.stream != null:
		p.play()


func _process(delta: float) -> void:
	for name in loops:
		var p: AudioStreamPlayer = loops[name]
		var want := float(_levels.get(name, 0.0))
		var target := -80.0 if want <= 0.001 else float(DB.get(name, -12.0)) + linear_to_db(want)
		p.volume_db = move_toward(p.volume_db, target, delta * 60.0)
