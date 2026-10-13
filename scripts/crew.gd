class_name Crew
extends RefCounted
## The captain's crew: the people hired at a bar who work the ship (data/runtime/crew.json).
##
## A crew member is a Dictionary kept in the save (profile.crew):
##   {id, name, species, role, skill 1..5, wage (cr/day, fixed at hire at that port's rates), line, hired_day}
## The captain is not in the list: they are aboard anyway, on the owner's draw.
##
## What each role is worth (best skill aboard for that role counts; two of a kind don't stack):
## - engineer: every part wears slower; services worn parts in flight and between trips, and brings a
##   failed one back with a spares kit (the same rules as the wrench on a space walk).
## - deck_tech: goes out and fixes hull marks while the engines are quiet, and between trips: plating
##   free, holes with a patch kit, never past 50% (the same rules as a space walk).
## - pilot: autopilot trips burn less fuel and take less time; takes the helm when the captain gets up
##   (brakes at the brake point) and cuts the engines when anyone goes outside.
## - loadmaster: knocks spoil less of the load; unloading is quicker; at the camp the crew unload it
##   themselves, so the camp's own crew doesn't take its share.
## - steward: passengers pay more, and a happy passenger is worth standing.
##
## Candidates at a port are the same all day (seeded by port and day), so the bar doesn't reshuffle
## every time you look.

const PATH := "res://data/runtime/crew.json"
const ROLES := ["engineer", "deck_tech", "pilot", "loadmaster", "steward"]

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


static func role(id: String) -> Dictionary:
	return (cfg().get("roles", {}) as Dictionary).get(id, {})


static func role_name(id: String) -> String:
	return String(role(id).get("name", id.capitalize()))


## Daily pay for a role at a skill level, before the port's rates.
static func base_wage(role_id: String, skill: int) -> float:
	var sw: Dictionary = cfg().get("skill_wage", {})
	return float(role(role_id).get("wage", 300)) * (float(sw.get("base", 0.8)) + float(sw.get("per_skill", 0.1)) * float(skill))


## A name in the style of `species`, from the name pools.
static func make_name(species: String, rng: RandomNumberGenerator) -> String:
	var pools: Dictionary = (cfg().get("names", {}) as Dictionary).get(species, {})
	var pick := func(key: String) -> String:
		var list: Array = pools.get(key, [""])
		return String(list[rng.randi() % list.size()]) if not list.is_empty() else ""
	match species:
		"kesh":
			return "%s%s %s" % [pick.call("first"), pick.call("end"), pick.call("lineage")]
		"ilyan":
			return "%s%s %s" % [pick.call("first"), pick.call("end"), pick.call("second")]
		"vey":
			var own: String = pick.call("first") + pick.call("end")
			return own if rng.randf() < 0.3 else "%s %s" % [own, pick.call("waters")]   # offworld, mostly the two-part form
		"orun":
			return "%s of %s" % [pick.call("first"), pick.call("junction")]
	return "%s %s" % [pick.call("given"), pick.call("family")]


static func _species(rng: RandomNumberGenerator) -> String:
	var w: Dictionary = cfg().get("species_weight", {"human": 1.0})
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return "human"


## Mostly middling, a few good, the odd one who's seen everything (crew.json skill_odds, 1..5).
static func _skill(rng: RandomNumberGenerator) -> int:
	var odds: Array = cfg().get("skill_odds", [0.25, 0.35, 0.25, 0.11, 0.04])
	var r := rng.randf()
	for i in odds.size():
		r -= float(odds[i])
		if r <= 0.0:
			return i + 1
	return odds.size()


## Who is looking for work at `port_id` on `day`: [{id, name, species, role, skill, wage, line}].
## `wage_index` is the port's pay level (SimShip.wage_index); `skip` is ids already hired or let go.
static func candidates(port_id: String, day: int, wage_index: float, skip: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|crew|%d" % [port_id, day])
	var out: Array[Dictionary] = []
	var n := int(cfg().get("candidates_per_day", 4))
	var start := rng.randi() % ROLES.size()
	for k in n:
		var r: String = ROLES[(start + k * 2) % ROLES.size()]   # a spread of roles, not four pilots
		var skill := _skill(rng)
		var sp := _species(rng)
		var lines: Array = (cfg().get("lines", {}) as Dictionary).get(r, [""])
		var p := {
			"id": "%d-%d-%d" % [absi(hash(port_id)) % 100000, day, k],
			"name": make_name(sp, rng),
			"species": sp,
			"role": r,
			"skill": skill,
			"wage": roundi(base_wage(r, skill) * wage_index),
			"line": String(lines[rng.randi() % lines.size()]) if not lines.is_empty() else "",
		}
		if String(p.id) in skip:
			continue
		out.append(p)
	return out


## The best skill aboard for `role_id` (0 if nobody does it).
static func skill(roster: Array, role_id: String) -> int:
	var best := 0
	for p in roster:
		if String(p.get("role", "")) == role_id:
			best = maxi(best, int(p.get("skill", 0)))
	return best


static func who(roster: Array, role_id: String) -> Dictionary:
	var best := {}
	for p in roster:
		if String(p.get("role", "")) == role_id and int(p.get("skill", 0)) > int(best.get("skill", 0)):
			best = p
	return best


## First name, or the personal name: what the cockpit calls them.
static func short(p: Dictionary) -> String:
	return String(p.get("name", "Crew")).get_slice(" ", 0)


static func _cut(roster: Array, role_id: String, key: String, floor_v := 0.2) -> float:
	return maxf(floor_v, 1.0 - float(role(role_id).get(key, 0.0)) * float(skill(roster, role_id)))


## Multipliers the crew bring (1.0 with nobody in the role).
static func wear_mult(roster: Array) -> float:
	return _cut(roster, "engineer", "wear_cut_per_skill")


static func fuel_mult(roster: Array) -> float:
	return _cut(roster, "pilot", "fuel_cut_per_skill")


static func time_mult(roster: Array) -> float:
	return _cut(roster, "pilot", "time_cut_per_skill")


static func cargo_hurt_mult(roster: Array) -> float:
	return _cut(roster, "loadmaster", "cargo_hurt_cut_per_skill")


static func unload_mult(roster: Array) -> float:
	return _cut(roster, "loadmaster", "unload_cut_per_skill")


static func fare_mult(roster: Array) -> float:
	return 1.0 + float(role("steward").get("fare_per_skill", 0.0)) * float(skill(roster, "steward"))


## Seconds between jobs in flight for a role ("service_every_s" / "fix_every_s"), or INF with nobody.
static func every_s(roster: Array, role_id: String, key: String) -> float:
	var s := skill(roster, role_id)
	return INF if s <= 0 else float(role(role_id).get(key, 240.0)) / float(s)


## How many jobs a role gets through in `hours` between trips (autopilot, waiting in port).
static func jobs_in(roster: Array, role_id: String, key: String, hours: float) -> int:
	return int(floor(hours * float(role(role_id).get(key, 0.0)) * float(skill(roster, role_id)) + 0.5))


# --- The work itself, the same rules as the captain's own space walk ------------------------------

## The engineer sees to the worst part that can be helped: a worn one is serviced (never better than the
## space-walk floor), a failed one brought back if there's a spares kit. Changes `wear` (and `kits`, a
## one-element Array with the spares count). Returns {name, key, failed, condition} or {} if there was
## nothing to do.
static func service_one(ship: ShipData, wear: Dictionary, kits: Array) -> Dictionary:
	var floor_w := float(Wear.cfg().get("eva_floor", 0.5))
	var best := {}
	for p in Wear.parts(ship, wear):
		var w := float(p.wear)
		if w >= 1.0 and int(kits[0]) <= 0:
			continue
		if w <= floor_w + 0.001:
			continue
		if best.is_empty() or w > float(best.wear):
			best = p
	if best.is_empty():
		return {}
	var failed := float(best.wear) >= 1.0
	if failed:
		kits[0] = int(kits[0]) - 1
	wear[String(best.key)] = Wear.eva_fixed(float(best.wear))
	return {"name": String(best.name), "key": String(best.key), "failed": failed, "condition": Wear.condition(float(wear[String(best.key)]))}


## The hull marks showing at `damage` with `patched` spots already done, the way ShipDamage shows them.
static func marks(damage: float, patched: Array, sites := ShipDamage.MAX_SCORCH) -> Array[int]:
	var out: Array[int] = []
	var n := roundi(clampf(damage, 0.0, 1.0) * float(ShipDamage.MAX_SCORCH))
	for i in mini(sites, ShipDamage.MAX_SCORCH):
		if out.size() >= n:
			break
		if not patched.has(i):
			out.append(i)
	return out


## The deck tech picks a mark to fix among `shown`: loose plating first (free), then a hole if there's a
## kit. Returns the index, or -1 (nothing they can do: the hull is at the cap, or only holes and no kits).
static func pick_mark(shown: Array, hull: float, kits: int) -> int:
	for i in shown:
		if SpaceWalk.blocked(int(i), hull, kits) == "" and not ShipDamage.needs_kit(int(i)):
			return int(i)
	for i in shown:
		if SpaceWalk.blocked(int(i), hull, kits) == "":
			return int(i)
	return -1


## Between trips: the deck tech fixes up to `n` marks on the profile's hull (hull_damage, hull_patches,
## patch_kits), and the engineer services up to `m` parts (wear, spares_kits). Returns what was done:
## {fixed, kits_used, serviced, revived}.
static func work_between(profile: Dictionary, ship: ShipData, n: int, m: int) -> Dictionary:
	var out := {"fixed": 0, "kits_used": 0, "serviced": 0, "revived": 0}
	var patched: Array = (profile.get("hull_patches", []) as Array).duplicate()
	var dmg := float(profile.get("hull_damage", 0.0))
	var kits := int(profile.get("patch_kits", 0))
	var sites := ShipDamage.skin_sites(ship).size() if ship != null else ShipDamage.MAX_SCORCH
	for k in n:
		var i := pick_mark(marks(dmg, patched, sites), 1.0 - dmg, kits)
		if i < 0:
			break
		if ShipDamage.needs_kit(i):
			kits -= 1
			out.kits_used = int(out.kits_used) + 1
		dmg = SpaceWalk.repaired(dmg)
		patched.append(i)
		out.fixed = int(out.fixed) + 1
	if int(out.fixed) > 0:
		profile["hull_damage"] = dmg
		profile["hull_patches"] = patched
		profile["patch_kits"] = kits
	if ship != null and m > 0:
		var wear: Dictionary = (profile.get("wear", {}) as Dictionary).duplicate()
		var spares := [int(profile.get("spares_kits", 0))]
		for k in m:
			var r := service_one(ship, wear, spares)
			if r.is_empty():
				break
			out[("revived" if bool(r.failed) else "serviced")] = int(out["revived" if bool(r.failed) else "serviced"]) + 1
		profile["wear"] = wear
		profile["spares_kits"] = int(spares[0])
	return out


## One line for a trip's message, or "".
static func work_note(roster: Array, done: Dictionary) -> String:
	var bits := PackedStringArray()
	if int(done.get("fixed", 0)) > 0:
		bits.append("%s fixed %d hull mark%s%s" % [short(who(roster, "deck_tech")), int(done.fixed), "" if int(done.fixed) == 1 else "s",
				" (%d patch kit%s)" % [int(done.kits_used), "" if int(done.kits_used) == 1 else "s"] if int(done.get("kits_used", 0)) > 0 else ""])
	var sv := int(done.get("serviced", 0)) + int(done.get("revived", 0))
	if sv > 0:
		bits.append("%s serviced %d part%s%s" % [short(who(roster, "engineer")), sv, "" if sv == 1 else "s",
				", %d back from failed with a spares kit" % int(done.revived) if int(done.get("revived", 0)) > 0 else ""])
	return (" On the way, " + " and ".join(bits) + ".") if not bits.is_empty() else ""
