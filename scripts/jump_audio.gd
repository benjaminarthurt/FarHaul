class_name JumpAudio
extends Node
## The sound of a jump, mixed live from the jump timeline: a hum, a rising whine and a rush of noise
## whose volume and pitch follow how far the stars have stretched, a boom at the flash (everything
## ducks under it) and short engage and settle cues. flight.gd calls `mix` every frame and `cue` at
## the moments. Files come from tools/gen_jump_audio.py; swap any of them for a recording and nothing
## else changes. Levels live in data/runtime/jump_audio.json.

const DIR := "res://assets/audio/jump/"
const CFG := "res://data/runtime/jump_audio.json"

var cfg: Dictionary = {}
var hum: AudioStreamPlayer
var whine: AudioStreamPlayer
var rush: AudioStreamPlayer
var cues: Dictionary = {}          # name -> AudioStreamPlayer
var events: Array[String] = []     # cues played, in order (tests read this)
var last_mix: Dictionary = {}      # last values handed to mix (tests read this)
var active := false


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	hum = _loop("hum.wav")
	whine = _loop("whine.wav")
	rush = _loop("rush.wav")
	for n in ["boom", "engage", "settle"]:
		cues[n] = _player(n + ".wav", false)


func _player(file: String, looped: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s = load(DIR + file) if ResourceLoader.exists(DIR + file) else null
	if s is AudioStreamWAV and looped:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)   # in samples (the bytes are compressed, so not data.size())
	p.stream = s
	p.bus = GameSettings.bus("Effects")
	p.volume_db = -80.0
	add_child(p)
	return p


func _loop(file: String) -> AudioStreamPlayer:
	return _player(file, true)


func _lv(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


## Start the loops (silent until mixed).
func begin() -> void:
	active = true
	for p in [hum, whine, rush]:
		if p.stream != null and not p.playing:
			p.play()


func end() -> void:
	active = false
	for p in [hum, whine, rush]:
		p.stop()
		p.volume_db = -80.0


func cue(name: String) -> void:
	events.append(name)
	var p: AudioStreamPlayer = cues.get(name)
	if p != null and p.stream != null:
		p.volume_db = _lv(name + "_db", 0.0)
		p.play()


## `level` 0..1 overall intensity, `streak` 0..1 how stretched the stars are, `duck` 0..1 (1 = normal,
## 0 = dropped out under the boom).
func mix(level: float, streak: float, duck: float) -> void:
	last_mix = {"level": level, "streak": streak, "duck": duck}
	if not active:
		return
	var duck_db := lerpf(-60.0, 0.0, clampf(duck, 0.0, 1.0))
	hum.volume_db = lerpf(_lv("hum_min_db", -30.0), _lv("hum_max_db", -6.0), level) + duck_db
	hum.pitch_scale = lerpf(0.8, 1.15, level)
	whine.volume_db = lerpf(-60.0, _lv("whine_max_db", -12.0), pow(clampf(streak + level * 0.25, 0.0, 1.0), 0.8)) + duck_db
	whine.pitch_scale = lerpf(0.5, _lv("whine_max_pitch", 2.8), streak)
	rush.volume_db = lerpf(-60.0, _lv("rush_max_db", -5.0), streak * streak) + duck_db
	rush.pitch_scale = lerpf(0.9, 1.2, streak)
