extends SceneTree
## Theme song: starts with the splash, ducks under the intro video, plays at full level on the title.

func _initialize() -> void:
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	await process_frame
	await process_frame
	var fails := 0
	var m: AudioStreamPlayer = boot.music
	fails += _check("music stream loaded", m.stream != null)
	fails += _check("looping", m.stream is AudioStreamMP3 and (m.stream as AudioStreamMP3).loop)
	fails += _check("playing on splash", m.playing and boot.stage == boot.Stage.SPLASH)
	boot._enter_intro()
	await create_timer(0.8).timeout
	fails += _check("ducked under intro (%.1f dB)" % m.volume_db, m.volume_db < -10.0)
	boot._enter_title(true)
	await create_timer(1.5).timeout
	fails += _check("title level (%.1f dB)" % m.volume_db, m.volume_db > -6.0 and m.playing)
	print("music smoke: %s" % ("FAIL" if fails > 0 else "ok"))
	quit(1 if fails > 0 else 0)

func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["ok  " if ok else "FAIL", label])
	return 0 if ok else 1
