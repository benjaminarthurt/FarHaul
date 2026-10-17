extends SceneTree
## VoiceBank (scripts/comms/voice_bank.gd): recorded lines found by id, a speaker of the caller's species
## kept per caller, takes that don't repeat, two lines said together, the babble when there's no
## recording or the setting is off, and the radio playing a recorded line with its squelch and hiss.
## Uses the small fixture bank in tests/fixtures/voice (tones, not voices).
## Run: godot --headless --path . --script res://tests/test_voice_bank.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_voice_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("the bank")
	VoiceBank.root = "res://tests/fixtures/voice"
	VoiceBank.refresh()
	check(VoiceBank.available(), "the fixture bank loads")
	check(VoiceBank.line_id("comms:cleared", 0, {"berth": "6", "you": "Second Thoughts"}) == "comms:cleared|0|berth=6", "a line's id from what the game filled in, names left out")
	check(VoiceBank.line_id("comms:cleared", 2, {"berth": "6"}) == "", "a line that isn't recorded has no id")
	check(VoiceBank._value("fine", {"fine": "1,300 cr"}) == "1300" and VoiceBank._value("rescue_t", {"t": "4"}) == "4" and VoiceBank._value("t", {"t": "3.0"}) == "3", "numbers are read the way the game writes them (\"1,300 cr\", \"3.0\")")
	var probs: Array = Comms.cfg().distress.problems
	check(VoiceBank._value("problem", {"problem": String(probs[2])}) == "2" and VoiceBank._value("species", {"species": "Kesh"}) == "kesh", "a distress call's problem and species map to their recorded variants")

	var ref := {"key": "comms:cleared", "index": 0, "args": {"berth": "6"}}
	var kesh := VoiceBank.clips([ref], "kesh", 12345)
	check(kesh.size() == 1 and String(kesh[0].resource_path).contains("control_kesh_1"), "a Kesh station gets the Kesh controller")
	var vey := VoiceBank.clips([ref], "vey", 12345)
	check(vey.size() == 1, "a species with no recording of its own still gets a voice from the role")
	var same := true
	for i in 6:
		var a := VoiceBank.clips([ref], "vey", 777)
		var b := VoiceBank.clips([ref], "vey", 777)
		same = same and String(a[0].resource_path).get_base_dir() == String(b[0].resource_path).get_base_dir()
	check(same, "the same caller keeps the same speaker")
	var first := String(VoiceBank.clips([ref], "kesh", 1)[0].resource_path)
	var second := String(VoiceBank.clips([ref], "kesh", 1)[0].resource_path)
	check(first != second, "two takes come round in turn, not the same one twice: %s, %s" % [first.get_file(), second.get_file()])
	check(VoiceBank.clips([{"key": "comms:cleared", "index": 0, "args": {"berth": "13"}}], "kesh", 1).is_empty(), "no recording for berth 13 in this bank: nothing (the radio babbles)")

	var two := VoiceBank.clips([{"key": "comms:fuel_offer", "index": 0, "args": {"t": "3", "price": "1,200"}}, {"key": "comms:fuel_coming", "index": 1, "args": {}}], "human", 5)
	check(two.size() == 2, "two lines said together come from one speaker")
	var j := VoiceBank.joined(two)
	check(j is AudioStreamPlaylist and absf(VoiceBank.length(two) - 0.8) < 0.1, "and play back to back (%.2f s)" % VoiceBank.length(two))

	print("every recorded line, as the game says it")
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/voice/lines.json")).lines
	var all := {}
	for l in lines:
		all[String(l.id)] = {}
	var tmp := "user://voice_ids_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp))
	var fa := FileAccess.open(tmp.path_join("index.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify({"speakers": {}, "clips": all}))
	fa.close()
	VoiceBank.root = tmp
	VoiceBank.refresh()
	var names := {"human": "Human", "kesh": "Kesh", "ilyan": "Ilyan", "vey": "Vey", "orun": "Orun"}
	var missed := []
	for l in lines:
		var args := {"you": "Second Thoughts"}
		for n in (l.values as Dictionary):
			var v := String(l.values[n])
			match String(n):
				"fine", "camp_fine": args["fine"] = "%s cr" % ShipStats.commas(int(v))
				"rescue_t", "t": args["t"] = "%.0f" % float(v)
				"species": args["species"] = String(Worlds.species(v).get("name", names[v]))
				"problem": args["problem"] = String(probs[int(v)])
				_: args[String(n)] = v
		if VoiceBank.line_id(String(l.key), int(l.index), args) != String(l.id):
			missed.append(String(l.id))
	check(missed.is_empty(), "all %d recorded lines are found from what the game fills in%s" % [lines.size(), "" if missed.is_empty() else ": missed " + ", ".join(missed.slice(0, 5))])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp.path_join("index.json")))
	VoiceBank.root = "res://tests/fixtures/voice"
	VoiceBank.refresh()

	print("on the radio")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.profile["ship_name"] = "Second Thoughts"
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var c: Comms = f.comms_c
	check(AudioServer.get_bus_index("Radio") >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index("Radio")) == "Effects", "the Radio bus is there, into Effects")

	c._pending = [{"text": "A", "key": "comms:news_tight", "index": 0, "args": {}}, {"text": "Bee sees", "key": "comms:news_wreck", "index": 1, "args": {}}]
	var picked := c._refs_for("Bee sees")
	check(picked.size() == 1 and String(picked[0].key) == "comms:news_wreck", "a news item picked from several is known by its own line")
	c._pending = [{"text": "One.", "key": "comms:fuel_offer", "index": 0, "args": {}}, {"text": "Two.", "key": "comms:fuel_coming", "index": 1, "args": {}}]
	check(c._refs_for("One. Two.").size() == 2, "two lines said together are both known")
	c._pending = [{"text": "One.", "key": "comms:fuel_offer", "index": 0, "args": {}}]
	check(c._refs_for("One. And something else.").is_empty(), "a line with words added isn't taken for the recording")

	GameSettings.set_value("recorded_voices", true)
	c._pending = [{"text": "Freighter, cleared to berth six.", "key": "comms:cleared", "index": 0, "args": {"berth": "6"}}]
	c._say("Traffic control", "Freighter, cleared to berth six.", RadioVoice.voice("human", 9), 0.3)
	c.step(0.0, 0.0)
	check(c.current.has("rec") and c._task < 0, "a recorded line plays the recording, no babble made")
	check(c.shown() == "" or c.shown().length() < 6, "its subtitle types out as it's said")
	c.step(0.0, 0.2)
	check(bool(c.current.rec.on) and c.voice_player.stream != null and c.voice_player.bus == "Radio", "after the squelch, the words, on the Radio bus")
	c.step(0.0, 1.0)
	check(bool(c.current.rec.off), "then the squelch closes")
	for i in 10:
		c.step(0.0, 0.5)
	check(c.current.is_empty() and String(c.log[c.log.size() - 1].text) == "Freighter, cleared to berth six.", "and it's in the log")

	print("in their own words")
	var base := "Freighter, cleared to berth six."
	c._pending = [{"text": base, "key": "comms:cleared", "index": 0, "args": {"berth": "6", "you": "Freighter"}}]
	c._say("Traffic control", base, RadioVoice.voice("kesh", 21), 0.3)
	var said: Dictionary = c.queue[c.queue.size() - 1]
	var kesh_lines: Array = Comms.cfg().species_lines.kesh.cleared
	check(String(said.text) != base and String(said.refs[0].key) == "comms:cleared@kesh", "a Kesh controller says it the Kesh way: \"%s\"" % String(said.text))
	check(kesh_lines.any(func(e): return String(e[0] if e is Array else e).format({"berth": "6"}) == String(said.text)), "word for word one of the Kesh lines, berth filled in")
	c.queue.clear()
	c._pending = [{"text": base, "key": "comms:cleared", "index": 0, "args": {"berth": "6"}}]
	c._say("Traffic control", base, RadioVoice.voice("human", 21), 0.3)
	check(String(c.queue[c.queue.size() - 1].text) == base, "a human one keeps the base line")
	c.queue.clear()

	print("the translator")
	c._heard.clear()
	c._pending = [{"text": base, "key": "comms:cleared", "index": 0, "args": {"berth": "6"}}]
	c.rng.seed = 3
	c._say("Traffic control", base, RadioVoice.voice("kesh", 33), 0.3)
	var ref0: Dictionary = c.queue[0].refs[0]
	ref0.index = 0   # the fixture bank has only the first Kesh line recorded
	c.queue[0].text = String(Comms.cfg().species_lines.kesh.cleared[0]).format({"berth": "6"})
	c.step(0.0, 0.0)
	check(c.current.has("rec") and float(c.current.rec.lead) > 0.5, "a Kesh caller starts in Kesh: %.1f s of it before the translator" % float(c.current.get("rec", {}).get("lead", 0.0)))
	check(c.current.rec.stream is AudioStreamPlaylist and (c.current.rec.stream as AudioStreamPlaylist).stream_count == 3, "their language, the translator's chirp, then the words")
	c.step(0.0, 0.2)
	check(c.voice_player.bus.begins_with("Voice_kesh") and c.layer_players.size() == 1 and c.layer_players[0].bus.contains("layer0"), "on the Kesh bus, with the octave-down voice under it: %s" % c.voice_player.bus)
	var kb := AudioServer.get_bus_index(c.voice_player.bus)
	check(AudioServer.get_bus_send(kb) == "Radio" and AudioServer.get_bus_effect(AudioServer.get_bus_index(c.layer_players[0].bus), 0) is AudioEffectPitchShift, "then through the radio")
	for i in 12:
		c.step(0.0, 0.5)
	c._pending = [{"text": base, "key": "comms:cleared", "index": 0, "args": {"berth": "6"}}]
	c._say("Traffic control", base, RadioVoice.voice("kesh", 33), 0.3)
	c.queue[0].refs[0].index = 0
	c.step(0.0, 0.0)
	check(c.current.has("rec") and float(c.current.rec.lead) < 0.5, "the same caller again: the translator's quicker (%.1f s)" % float(c.current.get("rec", {}).get("lead", 0.0)))
	for i in 12:
		c.step(0.0, 0.5)
	for sp in ["ilyan", "vey", "orun"]:
		var bus := VoiceBank.species_bus(sp)
		check(AudioServer.get_bus_index(bus) >= 0 and AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus)) > 0, "%s have their own sound: %s" % [sp.capitalize(), bus])

	GameSettings.set_value("recorded_voices", false)
	c._pending = [{"text": "Freighter, cleared to berth six.", "key": "comms:cleared", "index": 0, "args": {"berth": "6"}}]
	c._say("Traffic control", "Freighter, cleared to berth six.", RadioVoice.voice("kesh", 9), 0.3)
	c.step(0.0, 0.0)
	check(not c.current.has("rec") and c._task >= 0, "with recorded voices off, the babble as before")
	for i in 200:
		c.step(0.0, 0.5)
		if c.queue.is_empty() and c.current.is_empty() and c._task < 0:
			break
		await process_frame
	GameSettings.set_value("recorded_voices", true)

	c._pending = []
	c._say("Traffic control", "Something nobody recorded.", RadioVoice.voice("kesh", 9), 0.3)
	c.step(0.0, 0.0)
	check(not c.current.has("rec") and c._task >= 0, "a line with no recording is babbled")
	for i in 200:
		c.step(0.0, 0.5)
		if c.queue.is_empty() and c.current.is_empty() and c._task < 0:
			break
		await process_frame

	print("aboard")
	var b := {"id": "bk1", "person": "Mags Osei", "dest_name": "Concord", "due_day": 1 << 30, "species": "human"}
	var r := PassengersAboard.line_ref(b, 1, 0)
	var pax: Array = Passengers.cfg().aboard.cabin
	check(String(r.key) == "aboard:cabin" and PassengersAboard.line_for(b, 1, 0).contains(String(pax[int(r.index)])), "a passenger's line and its recording's id agree: %s|%d" % [String(r.key), int(r.index)])
	b.species = "orun"
	r = PassengersAboard.line_ref(b, 1, 0)
	var orun: Array = Passengers.cfg().aboard_by_species.orun.cabin
	check(String(r.key) == "aboard:cabin@orun" and PassengersAboard.line_for(b, 1, 0).contains(String(orun[int(r.index)])), "an Orun passenger has an Orun opinion: \"%s\"" % String(orun[int(r.index)]))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.path()))
	print("\n%s (%d failed)" % ["ALL PASSED" if fails == 0 else "SOME FAILED", fails])
	quit(fails)
