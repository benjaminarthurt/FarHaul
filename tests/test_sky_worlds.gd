extends SceneTree
## Worlds in the sky (data/world/sky_worlds.json): Sol's real ones from the right sites (Earth from the
## port, Luna from the moon station, Mars from the belt works, Venus, Jupiter and Saturn from their own
## stations), every other system with a world of its own, every map present, and Sol's landing body
## is Luna. Sol's outer stations are real sites with hops both ways, too far for the starter's tank.
## Run: godot --headless --path . --script res://tests/test_sky_worlds.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	check(SkyWorlds.for_site("sol", "port") == ["earth", "luna"], "Earth in view from Sol's main port, Luna beyond")
	check(SkyWorlds.for_site("sol", "moon") == ["luna", "earth"], "Luna up close from the moon station, Earth beyond")
	check(SkyWorlds.for_site("sol", "belt")[0] == "mars", "Mars from the belt works")
	check(SkyWorlds.for_site("sol", "jovian")[0] == "jupiter" and SkyWorlds.for_site("sol", "saturn")[0] == "saturn"
			and SkyWorlds.for_site("sol", "venus")[0] == "venus", "Venus, Jupiter and Saturn from their own stations")
	check(not SkyWorlds.world("saturn").get("rings", {}).is_empty(), "Saturn has rings")
	var b := LocalSpace.body("sol")
	check(String(b.id) == "moon" and String(b.name) == "Luna", "Sol's landing body is Luna, the grey moon (%s, %s)" % [b.id, b.get("name", "")])
	# Every system has a world of its own, and every world's maps are there.
	var missing := []
	var shared := {}
	for sid in Worlds.system_ids():
		var w := SkyWorlds.for_site(sid, "port")
		if w.is_empty():
			missing.append(sid)
		else:
			shared[w[0]] = shared.get(w[0], []) + [sid]
	check(missing.is_empty(), "every system has a world in its sky (missing: %s)" % [missing])
	var dupes := shared.keys().filter(func(k): return (shared[k] as Array).size() > 1)
	check(dupes.is_empty(), "no two systems share a world (%s)" % [dupes])
	var bad := []
	for id in SkyWorlds.data().worlds:
		var w := SkyWorlds.world(id)
		var map := SkyWorlds.MAP_DIR + String(w.get("map", id))
		if not ResourceLoader.exists(map + ".jpg") or (bool(w.get("mask", false)) and not ResourceLoader.exists(map + "_mask.jpg")):
			bad.append(id)
	check(bad.is_empty(), "every world's map (and mask) is there (missing: %s)" % [bad])
	for id in ["earth", "luna", "saturn", "veyara_prime"]:
		var w := SkyWorlds.build(id, 100.0, Vector3(0, 0, 1))
		check((w.get_node_or_null("Air") != null) == (float(SkyWorlds.world(id).get("atmo", 0.0)) > 0.0), "%s has air only if it should" % id)
		check((w.get_node_or_null("Rings") != null) == SkyWorlds.world(id).has("rings"), "%s has rings only if it should" % id)
		w.free()
	# The face: the longitude named in "face" looks at the viewer.
	var e := SkyWorlds.build("earth", 100.0, Vector3(0, 0, 1), Vector3(1, 0, 0))
	e.rotation_degrees.z = 0.0
	var face := float(SkyWorlds.world("earth").face)
	var a := deg_to_rad(face + 180.0)
	check((e.basis * Vector3(sin(a), 0, cos(a))).dot(Vector3(1, 0, 0)) > 0.99, "Earth turns longitude %d toward the viewer" % int(face))
	e.free()
	# Sol's outer stations: real sites, hops both ways, beyond the starter's tank.
	var kinds := LocalSpace.nodes("sol").map(func(n): return String(n.kind))
	check("venus" in kinds and "jovian" in kinds and "saturn" in kinds, "Sol lists its outer stations (%s)" % [kinds])
	check(not "jovian" in LocalSpace.nodes("keshar").map(func(n): return String(n.kind)), "other systems don't")
	var all_kinds: Array = LocalSpace.KINDS + LocalSpace.EXTRA
	var holes := []
	for x in all_kinds:
		for y in all_kinds:
			if x != y and (LocalSpace.hop(x, y).is_empty() or LocalSpace.hop(x, y) != LocalSpace.hop(y, x)):
				holes.append("%s|%s" % [x, y])
	check(holes.is_empty(), "every pair of sites has one hop, the same both ways (%s)" % [holes.slice(0, 4)])
	check(LocalSpace.node("sol__saturn").get("name", "") == "Sol Saturn ring yards", "the ring yards have a name")
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER)
	var st := ShipStats.compute(ship, 0.0, null)
	check(LocalSpace.max_cargo_t(st.wet, st.fuel, float(LocalSpace.hop("port", "saturn").dv_kms)) < 0.0, "the starter's tank can't reach Saturn")
	check(LocalSpace.max_cargo_t(st.wet + 2.0, st.fuel + 20.0, float(LocalSpace.hop("port", "saturn").dv_kms)) > 8.0, "two more tanks and it can, with a load")
	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
