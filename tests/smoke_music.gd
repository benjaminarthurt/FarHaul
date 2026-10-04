extends SceneTree
## Theme song: silent on the splash and under the intro video (which has its own music), then fades in and
## loops on the title screen.

func _initialize() -> void:
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	await process_frame
	await process_frame
	var fails := 0
	var m: AudioStreamPlayer = boot.music
	fails += _check("music stream loaded", m.stream != null)
	fails += _check("looping", m.stream is AudioStreamMP3 and (m.stream as AudioStreamMP3).loop)
	fails += _check("silent on the splash", not m.playing and boot.stage == boot.Stage.SPLASH)
	boot._enter_intro()
	await create_timer(0.8).timeout
	fails += _check("silent under the intro video", not m.playing)
	boot._enter_title(true)
	await create_timer(0.2).timeout
	fails += _check("starts with the menu, quietly (%.1f dB)" % m.volume_db, m.playing and m.volume_db < -10.0)
	await create_timer(1.6).timeout
	fails += _check("faded up to the title level (%.1f dB)" % m.volume_db, m.volume_db > -6.0 and m.playing)
	print("music smoke: %s" % ("FAIL" if fails > 0 else "ok"))
	quit(1 if fails > 0 else 0)

func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["ok  " if ok else "FAIL", label])
	return 0 if ok else 1
