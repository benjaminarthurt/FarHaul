extends SceneTree
## Solves each level's local_pay_mult: a stand-in captain with the sublight starter works local runs
## for a stretch of days and the net income per day is bisected to the level's target.
## Run: godot --headless --path . --script res://tests/solve_local.gd [-- probe]
## Targets are net credits per day after fuel, fees, wages and ownership.

const DAYS := 120
const TARGET := {"easy": 300.0, "normal": 200.0, "hard": 120.0}

func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_solve_local"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)

## Constants the trial needs from a real new game, read once per level.
var ctx := {}

func _context(difficulty: String) -> void:
	for f in DirAccess.get_files_at(SaveSlots.dir):
		DirAccess.remove_absolute(SaveSlots.dir + "/" + f)
	Session.begin_new(0, "Solver", "human", difficulty, "roosevelt_independent_yards")
	var loaded := Session._load_ship(SaveSlots.read(0))
	var st := Session.ship_stats(loaded.ship)
	ctx = {"st": st, "daily": SimWorld.daily_cost(Session.sim), "site": String(Session.profile.port_id)}
	ctx["level"] = SimShip.level(difficulty)

## Net credits per day for a captain who always takes the best-paying run available. Same rules as
## Session (board, fuel from the rocket equation, berth fee, unloading hours, running costs) without
## the save-file round trips, so a trial takes a moment.
func trial(mult: float, start_day: int = 0) -> Dictionary:
	LocalSpace.pay_override = mult
	var st: Dictionary = ctx.st
	var lv: Dictionary = ctx.level
	var units := float(SimShip.config()["fuel"]["units_per_tonne"])
	var fuel_price := float(Session.sim.p["fuel_cr_per_unit"]) * float(Session.sim.fuel_factor.get("new_houston", 1.0)) * float(lv.get("fuel_price_mult", 1.0))
	var fee := float(LocalSpace.config()["board"]["dock_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
	var unload := int(LocalSpace.config()["board"]["unload_hours"])
	var daily: float = ctx.daily
	var site: String = ctx.site
	var hour := start_day * 24
	var end_hour := hour + DAYS * 24
	var cash := 0.0
	var jobs := 0
	var idle := 0
	var hops := 0
	var taken: Array = []
	while hour < end_hour:
		var here := _best(site, hour, st, lv, taken, units, fuel_price, fee, unload, daily)
		var go_to := ""
		var go_hours := 0
		var go_cost := 0.0
		var best_rate := float(here.rate)
		var node := LocalSpace.node(site)
		for n in LocalSpace.nodes(String(node.system_id)):
			if String(n.id) == site:
				continue
			var h := LocalSpace.hop(String(node.kind), String(n.kind))
			if LocalSpace.max_cargo_t(float(st.wet), float(st.fuel), float(h.dv_kms)) < 0.0:
				continue
			var cost := LocalSpace.burn_t(float(st.wet), float(h.dv_kms)) * units * fuel_price + fee
			var there := _best(String(n.id), hour + int(h.hours), st, lv, taken, units, fuel_price, fee, unload, daily)
			if there.job.is_empty():
				continue
			var job_hours := float(int(there.job.hours) + unload)
			var total := float(there.net) - cost - float(h.hours) / 24.0 * daily
			var rate := total / (float(h.hours) + job_hours)
			if rate > best_rate:
				best_rate = rate
				go_to = String(n.id)
				go_hours = int(h.hours)
				go_cost = cost
		if go_to != "":
			cash -= go_cost + float(go_hours) / 24.0 * daily
			hour += go_hours
			site = go_to
			hops += 1
			continue
		if here.job.is_empty():
			hour += 24
			cash -= daily
			idle += 1
			continue
		taken.append(String(here.job.id))
		var h2: int = int(here.job.hours) + unload
		cash += float(here.net) - float(h2) / 24.0 * daily
		hour += h2
		site = String(here.job.destination_port_id)
		jobs += 1
	LocalSpace.pay_override = -1.0
	return {"net_per_day": cash / float(DAYS), "jobs": jobs, "idle_days": idle, "hops": hops, "daily_cost": daily}

## The job at `site` that pays best per hour after fuel and running costs: {job, net (before running
## costs of the trip's time are charged by the caller), rate (net per hour after them)}.
func _best(site: String, hour: int, st: Dictionary, lv: Dictionary, taken: Array, units: float, fuel_price: float, fee: float, unload: int, daily: float) -> Dictionary:
	var best := {}
	var best_net := 0.0
	var best_rate := 0.0
	for o in LocalSpace.board(site, hour / 24, st, lv, taken):
		var cost := LocalSpace.burn_t(float(st.wet) + float(o.offer), float(o.dv_kms)) * units * fuel_price + fee
		var hours := float(int(o.hours) + unload)
		var net := float(o.offer) * float(o.rate) - cost
		var rate := (net - hours / 24.0 * daily) / hours
		if rate > best_rate:
			best_rate = rate
			best = o
			best_net = net
	return {"job": best, "net": best_net, "rate": best_rate}

## Mean over several start days, which smooths the lumpiness of any one run of boards.
func average(mult: float) -> Dictionary:
	var sum := 0.0
	var jobs := 0.0
	var idle := 0.0
	var hops := 0.0
	var starts := [0, 37, 74, 111]
	for d in starts:
		var r := trial(mult, d)
		sum += float(r.net_per_day)
		jobs += float(r.jobs)
		idle += float(r.idle_days)
		hops += float(r.hops)
	var n := float(starts.size())
	return {"net_per_day": sum / n, "jobs": jobs / n, "idle_days": idle / n, "hops": hops / n, "daily_cost": ctx.daily}

func _run() -> void:
	var probe := "probe" in OS.get_cmdline_user_args()
	var out := {}
	for level in ["easy", "normal", "hard"]:
		_context(level)
		var lo := 0.2
		var hi := 4.0
		if probe:
			for m in [0.2, 0.5, 1.0, 2.0]:
				var r := average(m)
				print("%s mult %.2f -> net %.0f/day, %.0f jobs, %.0f hops, %.0f idle days, running costs %.0f/day" % [level, m, r.net_per_day, r.jobs, r.hops, r.idle_days, r.daily_cost])
			continue
		for i in 12:
			var mid := (lo + hi) * 0.5
			var r := average(mid)
			if float(r.net_per_day) < float(TARGET[level]):
				lo = mid
			else:
				hi = mid
		var m := snappedf((lo + hi) * 0.5, 0.005)
		var r := average(m)
		print("%s: local_pay_mult %.2f -> net %.0f/day (target %.0f), %.0f jobs, %.0f hops, %.0f idle days" % [level, m, r.net_per_day, TARGET[level], r.jobs, r.hops, r.idle_days])
		out[level] = m
	print("RESULT ", JSON.stringify(out))
	quit(0)
