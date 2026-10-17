extends SceneTree
## The recorded bank itself (assets/audio/voice): every line the game can say has clips, every clip
## loads and has sound in it, and each species' callers find their own recordings.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	VoiceBank.root = "res://assets/audio/voice"
	VoiceBank.refresh()
	check(VoiceBank.available(), "the recorded bank loads")
	var ix := VoiceBank.index()
	var clips: Dictionary = ix.get("clips", {})
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/voice/lines.json")).lines
	var missing := []
	var unspoken := []
	for l in lines:
		if not clips.has(String(l.id)):
			missing.append(String(l.id))
			continue
		var sp := String(l.get("species", "human"))
		var by: Dictionary = clips[String(l.id)]
		var own := false
		for who in by:
			own = own or String(who).contains("_%s_" % sp) or not l.has("species")
		if not own:
			unspoken.append(String(l.id))
	check(missing.is_empty(), "all %d lines have recordings%s" % [lines.size(), "" if missing.is_empty() else ": missing " + ", ".join(missing.slice(0, 5))])
	check(unspoken.is_empty(), "each species' own lines are said by that species%s" % ("" if unspoken.is_empty() else ": " + ", ".join(unspoken.slice(0, 5))))

	var n := 0
	var bad := []
	for id in clips:
		for who in (clips[id] as Dictionary):
			for f in (clips[id][who] as Array):
				n += 1
				var path := "res://assets/audio/voice".path_join(String(f))
				var s = load(path) if ResourceLoader.exists(path) else null
				if not (s is AudioStream) or (s as AudioStream).get_length() < 0.3:
					bad.append(path.get_file())
	check(n >= 2300 and bad.is_empty(), "all %d clips load and have sound in them%s" % [n, "" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 5))])

	for sp in ["human", "kesh", "ilyan", "vey", "orun"]:
		var key := "comms:cleared" if sp == "human" else "comms:cleared@%s" % sp
		var got := VoiceBank.clips([{"key": key, "index": 0, "args": {"berth": "6"}}], sp, 99)
		check(got.size() == 1 and (sp == "human" or String(got[0].resource_path).contains("_%s_" % sp)), "%s stations clear you in their own voice" % sp.capitalize())
	print("%d failed" % fails if fails else "all passed")
	quit(1 if fails else 0)
