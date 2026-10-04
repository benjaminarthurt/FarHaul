class_name People
## People with work: captains, crews and shippers who ask in person instead of posting on the board.
## They are at the concourse bar, at the hab's dispatch desk and at the camp foreman's. Three kinds:
##
## - **rush:** a small load that has to be there by a set hour. Wait a day and it is late: half pay and a
##   knock to your standing. It is due sooner than the usual trip, so you fly it yourself (a hand-flown
##   run is a hard burn) or pay for a hard burn on autopilot.
## - **passenger:** people riding along, one spare berth each. Pays a flat fare; a hard landing on the
##   way halves it.
## - **sealed:** a crate you do not open, for captains with some standing. Pays well; if the hull takes
##   damage on the way the seal breaks and most of the pay goes with it.
##
## Delivering any freight builds standing (`profile.rep`), and standing raises what people offer.
## Tuning: data/runtime/people.json. See docs/runtime/people.md.

const PATH := "res://data/runtime/people.json"
const KINDS := ["rush", "passenger", "sealed"]

static var _cfg: Dictionary = {}

const FIRST := ["Ade", "Bea", "Cass", "Dov", "Esk", "Fen", "Gale", "Hiro", "Ines", "Jory", "Kit", "Lio", "Mags", "Nell",
		"Oto", "Pia", "Quill", "Rhee", "Sol", "Tam", "Uma", "Vic", "Wren", "Yan", "Zed"]
const LAST := ["Okafor", "Brandt", "Szabo", "Reyes", "Tanaka", "Moreau", "Kowal", "Haddad", "Lindqvist", "Osei", "Varga",
		"Castell", "Ibsen", "Nakamura", "Duarte", "Pell", "Achebe", "Rourke"]
const LINES := {
	"rush": ["The line at %s is down until this arrives. Can you go now?", "I promised %s this by tonight. I'll pay for speed.",
			"%s needs these yesterday. Today will have to do."],
	"passenger": ["We need passage to %s. We'll keep out of the way.", "Shift change at %s and the shuttle's broken. Room for us?",
			"Going to %s. I hear you fly steady."],
	"sealed": ["Sealed crate for %s. Don't open it, don't ask, land it gently.", "This goes to %s as it is. The seal stays on.",
			"A private consignment for %s. Good pay for a smooth ride."],
}


## Rush hours: the share of the usual trip time a hard burn takes, and how much more fuel it burns.
static func hard_burn() -> Dictionary:
	var k: Dictionary = config().get("rush", {})
	return {"time": float(k.get("hard_burn_time", 0.6)), "fuel": float(k.get("hard_burn_fuel", 1.5))}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_cfg = d
	return _cfg


## The name of a standing ("Unknown", "Known", "Trusted", "Respected").
static func standing(rep: int) -> String:
	var name := "Unknown"
	for s in config().get("standings", []):
		if rep >= int(s[0]):
			name = String(s[1])
	return name


## The standing you need for the next tier, or -1 at the top.
static func next_standing(rep: int) -> int:
	for s in config().get("standings", []):
		if rep < int(s[0]):
			return int(s[0])
	return -1


## The extra pay standing earns on people's work (0.0 to 0.15).
static func rep_bonus(rep: int) -> float:
	return clampf(float(rep) * float(config().get("rep_pay_bonus_per_point", 0.003)), 0.0, float(config().get("rep_pay_bonus_max", 0.15)))


## Spare berths: what passengers can use.
static func seats(stats: Dictionary) -> int:
	return maxi(0, int(stats.get("berths", 0)) - int(stats.get("crew_needed", 0)))


## Who is asking at `node_id` today. Each job is a local run with `person` (their name), `person_kind`,
## `line` (what they say) and, for sealed work you lack the standing for, `locked`.
## `trip_cost` (cargo_t, dv_kms) -> credits is what the hop costs this ship: people pay a multiple of it,
## so their work always covers the fuel when done right.
static func posted(node_id: String, day: int, stats: Dictionary, level: Dictionary, taken: Array, rep: int, trip_cost: Callable) -> Array[Dictionary]:
	var cfg := config()
	var out: Array[Dictionary] = []
	var base := LocalSpace.board(node_id, day, stats, level, taken, "people", int(cfg.get("refresh_days", 1)), int(cfg.get("per_site", 3)))
	var bonus := 1.0 + rep_bonus(rep)
	for j in base:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(j.id))
		var kind: String = KINDS[rng.randi() % KINDS.size()]
		if kind == "rush":   # only if the tank can take the hard burn with the load
			var rk: Dictionary = cfg.get("rush", {})
			var t := maxf(1.0, snappedf(float(j.offer) * float(rk.tonnes_frac[0]), 0.5))
			if LocalSpace.burn_t(float(stats.get("wet", 0.0)) + t, float(j.dv_kms)) * float(rk.get("hard_burn_fuel", 1.3)) > float(stats.get("fuel", 0.0)):
				kind = "passenger" if rng.randf() < 0.5 else "sealed"
		var k: Dictionary = cfg.get(kind, {})
		var dest := String(LocalSpace.node(String(j.destination_port_id)).get("name", "there"))
		j["person"] = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
		j["person_kind"] = kind
		j["line"] = String(LINES[kind][rng.randi() % LINES[kind].size()]) % dest
		match kind:
			"rush":
				var frac := rng.randf_range(float(k.tonnes_frac[0]), float(k.tonnes_frac[1]))
				j["offer"] = maxf(1.0, snappedf(float(j.offer) * frac, 0.5))
				while j.offer > 1.0 and LocalSpace.burn_t(float(stats.get("wet", 0.0)) + float(j.offer), float(j.dv_kms)) * float(k.hard_burn_fuel) > float(stats.get("fuel", 0.0)):
					j["offer"] = maxf(1.0, float(j.offer) - 0.5)
				j["rate"] = roundi(maxf(float(j.rate) * float(k.rate_mult), float(trip_cost.call(float(j.offer), float(j.dv_kms))) * float(k.pays_trip_cost_x) / float(j.offer)) * bonus)
				j["due_in_hours"] = maxi(1, roundi(float(j.hours) * float(k.due_frac)))
				j["title"] = "Rush: %s" % String(j.title)
				j["blurb"] = "Due in %d h, sooner than the usual %d h: fly it yourself or pay for a hard burn. Late: half pay." % [int(j.due_in_hours), int(j.hours)]
			"passenger":
				var n := rng.randi_range(int(k.seats[0]), int(k.seats[1]))
				j["seats"] = n
				j["offer"] = 0.0
				j["fare"] = roundi(float(trip_cost.call(0.0, float(j.dv_kms))) * (float(k.pays_trip_cost_x[0]) + float(k.pays_trip_cost_x[1]) * n) * bonus)
				j["rate"] = 0
				j["title"] = "%d passenger%s to %s" % [n, "" if n == 1 else "s", dest]
				j["blurb"] = "Needs %d spare berth%s. A hard landing halves the fare." % [n, "" if n == 1 else "s"]
			"sealed":
				var frac := rng.randf_range(float(k.tonnes_frac[0]), float(k.tonnes_frac[1]))
				j["offer"] = maxf(1.0, snappedf(float(j.offer) * frac, 0.5))
				j["rate"] = roundi(maxf(float(j.rate) * float(k.rate_mult), float(trip_cost.call(float(j.offer), float(j.dv_kms))) * float(k.pays_trip_cost_x) / float(j.offer)) * bonus)
				j["title"] = "Sealed crate to %s" % dest
				j["blurb"] = "Any hull damage on the way breaks the seal: most of the pay is lost."
				if rep < int(k.min_rep):
					j["locked"] = "Needs %s standing (%d)" % [standing(int(k.min_rep)), int(k.min_rep)]
		out.append(j)
	return out


## What a finished people's job pays and does to your standing. `c` is the accepted job;
## `now_hour` the sim hour on delivery and `damage` the hull damage now.
static func settle(c: Dictionary, payment: int, now_hour: int, damage: float) -> Dictionary:
	var cfg := config()
	var kind := String(c.get("person_kind", ""))
	var k: Dictionary = cfg.get(kind, {})
	var hurt := damage > float(c.get("hull_at_accept", 0.0)) + 0.001
	match kind:
		"rush":
			if now_hour > int(c.get("due_hour", 1 << 30)):
				return {"payment": roundi(payment * float(k.late_pay)), "rep": int(k.rep_late), "note": "late: %s paid half" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_on_time), "note": "on time for %s" % String(c.person)}
		"passenger":
			if hurt:
				return {"payment": roundi(payment * float(k.rough_pay)), "rep": int(k.rep_rough), "note": "a rough ride: %s paid half the fare" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_ok), "note": "a smooth ride for %s" % String(c.person)}
		"sealed":
			if hurt:
				return {"payment": roundi(payment * float(k.broken_pay)), "rep": int(k.rep_broken), "note": "the seal broke in the knocks: %s paid a fraction" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_ok), "note": "seal intact"}
	return {"payment": payment, "rep": int(cfg.get("rep_freight", 1)), "note": ""}
