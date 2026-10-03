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
func trial(mult: float) -> Dictionary:
	LocalSpace.pay_override = mult
	var st: Dictionary = ctx.st
	var lv: Dictionary = ctx.level
	var units := float(SimShip.config()["fuel"]["units_per_tonne"])
	var fuel_price := float(Session.sim.p["fuel_cr_per_unit"]) * float(Session.sim.fuel_factor.get("new_houston", 1.0)) * float(lv.get("fuel_price_mult", 1.0))
	var fee := float(LocalSpace.config()["board"]["dock_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
	var unload := int(LocalSpace.config()["board"]["unload_hours"])
	var daily: float = ctx.daily
	var site: String = ctx.site
	var hour := 0
	var cash := 0.0
	var jobs := 0
	var idle := 0
	var taken: Array = []
	while hour < DAYS * 24:
		var best: Dictionary = {}
		var best_rate := 0.0
		var best_cost := 0.0
		for o in LocalSpace.board(site, hour / 24, st, lv, taken):
			var cost := LocalSpace.burn_t(float(st.wet) + float(o.offer), float(o.dv_kms)) * units * fuel_price + fee
			var hours := float(int(o.hours) + unload)
			var net := float(o.offer) * float(o.rate) - cost - hours / 24.0 * daily
			if net / hours > best_rate:
				best_rate = net / hours
				best = o
				best_cost = cost
		if best.is_empty():
			hour += 24
			cash -= daily
			idle += 1
			continue
		taken.append(String(best.id))
		var h: int = int(best.hours) + unload
		cash += float(best.offer) * float(best.rate) - best_cost - float(h) / 24.0 * daily
		hour += h
		site = String(best.destination_port_id)
		jobs += 1
	LocalSpace.pay_override = -1.0
	return {"net_per_day": cash / float(DAYS), "jobs": jobs, "idle_days": idle, "daily_cost": daily}

func _run() -> void:
	var probe := "probe" in OS.get_cmdline_user_args()
	var out := {}
	for level in ["easy", "normal", "hard"]:
		_context(level)
		var lo := 0.2
		var hi := 4.0
		if probe:
			for m in [0.2, 0.5, 1.0, 2.0]:
				var r := trial(m)
				print("%s mult %.2f -> net %.0f/day, %d jobs, %d idle days, running costs %.0f/day" % [level, m, r.net_per_day, r.jobs, r.idle_days, r.daily_cost])
			continue
		for i in 9:
			var mid := (lo + hi) * 0.5
			var r := trial(mid)
			if float(r.net_per_day) < float(TARGET[level]):
				lo = mid
			else:
				hi = mid
		var m := snappedf((lo + hi) * 0.5, 0.01)
		var r := trial(m)
		print("%s: local_pay_mult %.2f -> net %.0f/day (target %.0f), %d jobs, %d idle days" % [level, m, r.net_per_day, TARGET[level], r.jobs, r.idle_days])
		out[level] = m
	print("RESULT ", JSON.stringify(out))
	quit(0)
