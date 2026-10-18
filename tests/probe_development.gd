extends SceneTree
## Frontier growth, run out: 180 days of the known-space world with nobody playing, and again with a
## captain hauling to one moon station. Prints every site's stage at the start and end and the stage
## changes. Tuning aid for data/runtime/development.json; tests/test_development.gd is the test.
## FARHAUL_DEV_DAYS, FARHAUL_DEV_SITE (default sol__moon), FARHAUL_DEV_T (tonnes a day, default 10).

func _initialize() -> void:
	var days := int(OS.get_environment("FARHAUL_DEV_DAYS")) if OS.get_environment("FARHAUL_DEV_DAYS") != "" else 180
	var site := OS.get_environment("FARHAUL_DEV_SITE") if OS.get_environment("FARHAUL_DEV_SITE") != "" else "sol__moon"
	var per_day := float(OS.get_environment("FARHAUL_DEV_T")) if OS.get_environment("FARHAUL_DEV_T") != "" else 10.0
	for hauling in [false, true]:
		var sim := SimWorld.warmed()
		Development.enable(sim)
		var start := {}
		for id in sim.dev.sites:
			start[id] = Development.site_stage(sim, id)
		var t0 := Time.get_ticks_msec()
		for d in days:
			if hauling:
				Development.moved(sim, site, per_day)
			sim.run_days(1)
			if hauling and d % 15 == 14:
				var s: Dictionary = sim.dev.sites[site]
				print("  day %3d  %s score %.2f stage %s  need %.1f t/day  npc %.2f" % [d + 1, site, float(s.score), Development.stage_name(Development.site_stage(sim, site)), float(s.need), float(s.npc)])
		print("%s: %d days in %.0f s" % ["hauling %.0f t/day to %s" % [per_day, site] if hauling else "nobody playing", days, (Time.get_ticks_msec() - t0) / 1000.0])
		var changed := 0
		var gone := 0
		var hist := {}
		for id in sim.dev.sites:
			var a := int(start[id])
			var b := Development.site_stage(sim, id)
			var key := b - a
			hist[key] = int(hist.get(key, 0)) + 1
			if a != b:
				changed += 1
			if b == 0:
				gone += 1
		print("  sites %d, changed stage %d, abandoned %d, change histogram %s" % [sim.dev.sites.size(), changed, gone, str(hist)])
		var sys_line := []
		for sys in sim.dev.systems:
			var s: Dictionary = sim.dev.systems[sys]
			if absf(float(s.score) - float(s.canon)) > 0.15:
				sys_line.append("%s %+.2f" % [sys, float(s.score) - float(s.canon)])
		print("  systems moved: %s" % ", ".join(sys_line))
		var lows := []
		for id in sim.dev.sites:
			var s: Dictionary = sim.dev.sites[id]
			if float(s.score) - float(s.canon) < -0.6 or float(s.score) - float(s.canon) > 0.6:
				lows.append("%s %.1f>%.1f" % [id, float(s.canon), float(s.score)])
		print("  big movers: %s" % ", ".join(lows.slice(0, 20)))
		print("  events: %d" % sim.dev.events.size())
	quit(0)
