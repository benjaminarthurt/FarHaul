class_name People
## People with work: captains, crews and shippers who ask in person instead of posting on the board.
## They are at the concourse bar, at the hab's dispatch desk and at the camp foreman's. Three kinds:
##
## - **rush:** a small load that has to be there by a set hour. Wait a day and it is late: half pay and a
##   knock to your standing. It is due sooner than the usual trip, so you fly it yourself (a hand-flown
##   run is a hard burn) or pay for a hard burn on autopilot.
## - **passenger:** people riding along to another site (Passengers: a booking, not a contract, so they
##   ride with freight). A bed each; cabins pay more. A hard landing on the way halves the fare.
## - **sealed:** a crate you do not open, for captains Known here. Pays well; if the hull takes
##   damage on the way the seal breaks and most of the pay goes with it.
## - **private:** a private contract, offered only to captains Respected here. Pays best; same seal.
##
## Your standing at the place (Reputation) sets what they offer: Doubtful, fewer of them ask; Unwelcome
## or worse, nobody does. Pay moves with it (Reputation.pay_mult).
## Tuning: data/runtime/people.json. See docs/runtime/people.md.

const PATH := "res://data/runtime/people.json"
const KINDS := ["rush", "passenger", "sealed"]
const LOCKED := {"sealed": "Known", "private": "Respected"}   ## the standing a kind needs here

static var _cfg: Dictionary = {}

const FIRST := ["Ade", "Bea", "Cass", "Dov", "Esk", "Fen", "Gale", "Hiro", "Ines", "Jory", "Kit", "Lio", "Mags", "Nell",
		"Oto", "Pia", "Quill", "Rhee", "Sol", "Tam", "Uma", "Vic", "Wren", "Yan", "Zed"]
const LAST := ["Okafor", "Brandt", "Szabo", "Reyes", "Tanaka", "Moreau", "Kowal", "Haddad", "Lindqvist", "Osei", "Varga",
		"Castell", "Ibsen", "Nakamura", "Duarte", "Pell", "Achebe", "Rourke"]
const LINES := {
	"rush": ["The line at %s is down until this arrives. Every hour costs. Can you go now?", "I promised %s this by tonight. I'll pay for speed, not excuses.",
			"%s needs these yesterday. Today will have to do."],
	"passenger": ["We need passage to %s. We'll keep off the controls.", "Shift change at %s and the shuttle's broken again. Room for us?",
			"Going to %s. I hear you fly steady."],
	"sealed": ["Sealed crate for %s. Don't open it, don't ask, land it gently.", "This goes to %s as it is. Seal on. Ignore the humming.",
			"A private consignment for %s. Good pay for a smooth ride."],
	"private": ["I only use captains people speak well of. A private contract to %s; my name stays off the manifest.",
			"Word is you're careful. This goes to %s, privately, and pays like it.", "A quiet run to %s for someone who doesn't like quiet runs going wrong."],
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


## The name of a standing (Reputation.tier: Barred to Respected).
static func standing(rep: float) -> String:
	return Reputation.tier(rep)


## What standing does to people's pay, as a share over the usual (-0.3 Barred to +0.25 Respected).
static func rep_bonus(rep: float) -> float:
	return Reputation.pay_mult(rep) - 1.0


## Spare berths: what passengers can use.
static func seats(stats: Dictionary) -> int:
	return maxi(0, int(stats.get("berths", 0)) - maxi(int(stats.get("crew_needed", 0)), int(stats.get("crew_aboard", 0))) - int(stats.get("rescued", 0)))


## Who is asking at `node_id` today. Each job is a local run with `person` (their name), `person_kind`,
## `line` (what they say) and, for sealed work you lack the standing for, `locked`.
## `trip_cost` (cargo_t, dv_kms) -> credits is what the hop costs this ship: people pay a multiple of it,
## so their work always covers the fuel when done right.
static func posted(node_id: String, day: int, stats: Dictionary, level: Dictionary, taken: Array, rep: float, trip_cost: Callable) -> Array[Dictionary]:
	var cfg := config()
	var out: Array[Dictionary] = []
	if not Reputation.at_least(rep, "Doubtful"):
		return out   # Unwelcome or worse: nobody here asks you for anything
	var per := int(cfg.get("per_site", 3))
	if not Reputation.at_least(rep, "Unknown"):
		per = int(Reputation.cfg().get("doubtful_people_per_site", 2))
	var base := LocalSpace.board(node_id, day, stats, level, taken, "people", int(cfg.get("refresh_days", 1)), per)
	var bonus := Reputation.pay_mult(rep)
	var respected := Reputation.at_least(rep, String(LOCKED.private))
	for j in base:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(j.id))
		var kind: String = KINDS[rng.randi() % KINDS.size()]
		if respected and kind == "sealed" and rng.randf() < 0.6:
			kind = "private"   # people who only deal with captains everyone speaks well of
		if kind == "rush":   # only if the tank can take the hard burn with the load
			var rk: Dictionary = cfg.get("rush", {})
			var t := maxf(1.0, snappedf(float(j.offer) * float(rk.tonnes_frac[0]), 0.5))
			if LocalSpace.burn_t(float(stats.get("wet", 0.0)) + t, float(j.dv_kms)) * float(rk.get("hard_burn_fuel", 1.3)) > float(stats.get("fuel", 0.0)):
				kind = "passenger" if rng.randf() < 0.5 else ("private" if respected else "sealed")
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
				j["blurb"] = "Due in %d h, sooner than the usual %d h: fly it yourself or pay for a hard burn. Late: half pay, and a long face." % [int(j.due_in_hours), int(j.hours)]
			"passenger":
				var n := rng.randi_range(int(k.seats[0]), int(k.seats[1]))
				j["seats"] = n
				j["offer"] = 0.0
				j["fare"] = roundi(float(trip_cost.call(0.0, float(j.dv_kms))) * (float(k.pays_trip_cost_x[0]) + float(k.pays_trip_cost_x[1]) * n) * bonus)
				j["per_seat"] = roundi(float(j.fare) / float(n) / 10.0) * 10   # in a spare bunk; cabins pay more (Passengers)
				var pk: Dictionary = Passengers.cfg().get("local", {})
				j["wants"] = 1 if rng.randf() < float(pk.get("wants_cabin", 0.2)) else 0
				j["dest_name"] = dest
				j["due_days"] = int(pk.get("due_days", 2))
				j["rate"] = 0
				j["title"] = "%d passenger%s to %s" % [n, "" if n == 1 else "s", dest]
				j["blurb"] = "%s. They ride along with whatever else you're doing. A hard landing halves the fare. They notice." % ("Wants a cabin" if int(j.wants) > 0 else "Any bed will do")
			"sealed", "private":
				var frac := rng.randf_range(float(k.tonnes_frac[0]), float(k.tonnes_frac[1]))
				j["offer"] = maxf(1.0, snappedf(float(j.offer) * frac, 0.5))
				j["rate"] = roundi(maxf(float(j.rate) * float(k.rate_mult), float(trip_cost.call(float(j.offer), float(j.dv_kms))) * float(k.pays_trip_cost_x) / float(j.offer)) * bonus)
				j["title"] = ("Sealed crate to %s" if kind == "sealed" else "Private contract to %s") % dest
				j["blurb"] = "Any hull damage on the way breaks the seal, and most of the pay goes with it." if kind == "sealed" \
						else "A private client: any hull damage breaks the seal, half the pay goes, and so does their good opinion."
				var need := String(k.get("min_tier", LOCKED[kind]))
				if not Reputation.at_least(rep, need):
					j["locked"] = "Needs %s standing here" % need
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
				return {"payment": roundi(payment * float(k.late_pay)), "rep": int(k.rep_late), "note": "late: %s paid half, with a look" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_on_time), "note": "on time for %s, who almost smiled" % String(c.person)}
		"passenger":
			if hurt:
				return {"payment": roundi(payment * float(k.rough_pay)), "rep": int(k.rep_rough), "note": "a rough ride: %s paid half the fare, shakily" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_ok), "note": "a smooth ride for %s" % String(c.person)}
		"sealed", "private":
			if hurt:
				return {"payment": roundi(payment * float(k.broken_pay)), "rep": int(k.rep_broken), "note": "the seal broke in the knocks: %s paid a fraction" % String(c.person)}
			return {"payment": payment, "rep": int(k.rep_ok), "note": "seal intact"}
	return {"payment": payment, "rep": int(cfg.get("rep_freight", 1)), "note": ""}
