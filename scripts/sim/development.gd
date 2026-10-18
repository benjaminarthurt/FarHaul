class_name Development
extends RefCounted
## Frontier growth: every site in known space has a size, and a size needs supplying. Once a day
## (EconomySim.step_hour at midnight, when `sim.dev` is on) each site is supplied by its system's NPC
## traffic and by whatever the player brought or carried away that day. Supplied better than it needs, it
## grows; worse, it shrinks, down to abandoned. Systems follow their sites and their supply health in the
## economy, slower, and a system's size scales what its works make and its exchange uses.
## Tuning: data/runtime/development.json. Docs: docs/runtime/development.md.
##
## State, in `sim.dev` (saved with the sim):
##   sites:   {site_id: {score, canon, anchor, luck, kind, system_id, hist: [score by day], npc, you, need,
##            abandoned, since}}
##   systems: {system_id: {score, canon, fill_base, fill, unmet, hist}}
##   today:   {site_id: tonnes the player moved there today}
##   events:  [{day, site, system_id, from, to}] stage changes, newest last
##   day:     the last day reviewed

const PATH := "res://data/runtime/development.json"
const TIER_SCORE := {"extreme_frontier": 1.0, "frontier": 2.0, "outer": 3.0, "developed": 4.0, "core": 5.0}

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


## Turn growth on for a sim (a game's, not the calibration tests'): every site and system at its canon
## size, the supply health they start with as the baseline.
static func enable(sim: EconomySim) -> void:
	if sim == null or not sim.dev.is_empty():
		return
	var sites := {}
	var systems := {}
	for sys in Worlds.system_ids():
		var canon_sys := float(TIER_SCORE.get(SystemStyle.canon_tier(sys), 2.0))
		var f := _fill_so_far(sim, sys)
		var ref := float(config().system.get("fill_ref", 0.92))
		systems[sys] = {"score": canon_sys, "canon": canon_sys, "fill_base": ref, "fill": ref,
				"unmet": float(f.unmet), "hist": []}
		for n in LocalSpace.nodes(sys):
			var id := String(n.id)
			var c := canon_score(id)
			sites[id] = {"score": c, "canon": c, "anchor": c, "luck": 0.0, "kind": String(n.kind), "system_id": sys,
					"hist": [], "npc": 1.0, "you": 0.0, "need": 0.0, "abandoned": false, "since": sim.day()}
	sim.dev = {"sites": sites, "systems": systems, "today": {}, "events": [], "day": sim.day()}


static func on(sim: EconomySim) -> bool:
	return sim != null and not sim.dev.is_empty()


## A site's canon size: its system's tier, a step or two down for the working sites.
static func canon_score(site_id: String) -> float:
	var n := LocalSpace.node(site_id)
	var sys := String(n.get("system_id", ""))
	var kind := String(n.get("kind", "port"))
	var down := int(config().get("canon_step_down", {}).get(kind, 0))
	return maxf(1.0, float(TIER_SCORE.get(SystemStyle.canon_tier(sys), 2.0)) - float(down))


# --- The daily review -----------------------------------------------------------------------------

## Once a day: review every system's supply, then every site, then the systems again from their sites.
static func day_turned(sim: EconomySim) -> void:
	if not on(sim):
		return
	var cfg := config()
	var d: Dictionary = sim.dev
	var today := sim.day()
	if int(d.get("day", -1)) >= today:
		return
	d["day"] = today
	var sc: Dictionary = cfg.system
	var keep := int(cfg.get("history_days", 60))
	# Each system's supply health: what share of the day's demand its shelves met, against the start.
	var health := {}
	for sys in d.systems:
		var s: Dictionary = d.systems[sys]
		var f := _fill_today(sim, sys, s)
		s["unmet"] = float(f.unmet)
		var a := 1.0 / maxf(1.0, float(sc.fill_days))
		s["fill"] = (1.0 - a) * float(s.fill) + a * float(f.fill)
		var nb := 1.0 / maxf(1.0, float(sc.get("normal_days", 180.0)))   # what's normal here, learned slowly
		s["fill_base"] = (1.0 - nb) * float(s.fill_base) + nb * float(f.fill)
		health[sys] = clampf(float(s.fill) / maxf(0.05, float(s.fill_base)), float(sc.health_min), float(sc.health_max))
	# Every site against what it needs.
	var g := float(cfg.growth_per_day)
	var k := float(cfg.outgrow_k)
	var fo: Dictionary = cfg.fortune
	var moved: Dictionary = d.today
	for id in d.sites:
		var s: Dictionary = d.sites[id]
		var sys := String(s.system_id)
		var luck := float(s.luck)   # good months and bad months: a slow random walk, the same every run
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%d" % [id, today])
		luck += -luck / float(fo.days) + float(fo.sigma) * rng.randfn()
		s["luck"] = luck
		var you := float(moved.get(id, 0.0))
		s["you"] = 0.9 * float(s.get("you", 0.0)) + 0.1 * you
		if bool(s.abandoned):
			s["need"] = 0.0
			s["npc"] = 0.0
			_resettle(sim, id, s, rng)
		else:
			var need := need_t(s)
			var npc := float(health.get(sys, 1.0)) * exp(luck) * exp(-k * (float(s.score) - float(s.anchor)))
			var r := npc + you / maxf(0.01, need)
			var inertia := minf(1.0, sqrt(float(cfg.get("inertia_need_t", 12.0)) / maxf(0.01, need)))   # big places turn slowly
			var step := clampf(g * inertia * (r - 1.0), -float(cfg.max_fall_per_day), float(cfg.max_rise_per_day))
			var before := stage(float(s.score))
			s["score"] = float(s.score) + step
			s["anchor"] = float(s.anchor) + (float(s.score) - float(s.anchor)) / float(cfg.anchor_days)
			s["need"] = need
			s["npc"] = npc
			if float(s.score) < float(cfg.abandon_below):
				s["abandoned"] = true
				s["since"] = today
			var after := stage(float(s.score)) if not bool(s.abandoned) else 0
			if after != before:
				_event(sim, id, s, before, after)
		(s.hist as Array).append(snappedf(float(s.score), 0.001))
		if (s.hist as Array).size() > keep:
			(s.hist as Array).pop_front()
	d["today"] = {}
	# Systems: toward canon plus half their sites' growth, and toward better or worse supply, over a month.
	var growth := {}
	var count := {}
	for id in d.sites:
		var s: Dictionary = d.sites[id]
		var sys := String(s.system_id)
		growth[sys] = float(growth.get(sys, 0.0)) + float(s.score) - float(s.canon)
		count[sys] = int(count.get(sys, 0)) + 1
	for sys in d.systems:
		var s: Dictionary = d.systems[sys]
		var target := float(s.canon) + float(sc.site_weight) * float(growth.get(sys, 0.0)) / maxf(1.0, float(count.get(sys, 1))) \
				+ float(sc.health_weight) * (float(health.get(sys, 1.0)) - 1.0)
		s["score"] = float(s.score) + (target - float(s.score)) / float(sc.days)
		(s.hist as Array).append(snappedf(float(s.score), 0.001))
		if (s.hist as Array).size() > keep:
			(s.hist as Array).pop_front()


## Tonnes a day a site needs at its size: doubles each stage.
static func need_t(s: Dictionary) -> float:
	var base := float(config().demand_t_per_day.get(String(s.kind), 3.0))
	return base * pow(2.0, float(s.score) - 2.0)


static func _resettle(sim: EconomySim, id: String, s: Dictionary, rng: RandomNumberGenerator) -> void:
	var rs: Dictionary = config().resettle
	var sys: Dictionary = sim.dev.systems.get(String(s.system_id), {})
	if sys.is_empty() or float(sys.score) - float(sys.canon) < float(rs.system_above_canon):
		return
	if rng.randf() < float(rs.chance_per_day):
		s["abandoned"] = false
		s["score"] = float(rs.score)
		s["anchor"] = float(rs.score)
		s["since"] = sim.day()
		_event(sim, id, s, 0, stage(float(rs.score)))


static func _event(sim: EconomySim, id: String, s: Dictionary, from: int, to: int) -> void:
	var ev: Array = sim.dev.events
	ev.append({"day": sim.day(), "site": id, "system_id": String(s.system_id), "from": from, "to": to})
	while ev.size() > int(config().get("events_kept", 40)):
		ev.pop_front()


## A system's supply over the whole run so far: the baseline growth is judged against.
static func _fill_so_far(sim: EconomySim, sys: String) -> Dictionary:
	var unmet := 0.0
	var want := 0.0
	for f in sim.facilities.values():
		if String(f.system_id) != sys:
			continue
		for com in f.items:
			var it: Dictionary = f.items[com]
			unmet += float(it.unmet)
			want += float(it.demand) * float(sim.hour) / 24.0
	return {"unmet": unmet, "fill": 1.0 if want <= 0.0 else clampf(1.0 - unmet / want, 0.0, 1.0)}


## A system's supply today: the share of its facilities' demand met since the last review.
static func _fill_today(sim: EconomySim, sys: String, s: Dictionary) -> Dictionary:
	var unmet := 0.0
	var want := 0.0
	var scale := demand_scale(sim, sys)
	for f in sim.facilities.values():
		if String(f.system_id) != sys:
			continue
		for com in f.items:
			var it: Dictionary = f.items[com]
			unmet += float(it.unmet)
			want += float(it.demand) * scale
	var fresh := unmet - float(s.get("unmet", unmet))
	return {"unmet": unmet, "fill": 1.0 if want <= 0.0 else clampf(1.0 - maxf(0.0, fresh) / want, 0.0, 1.0)}


# --- What the rest of the game asks -----------------------------------------------------------------

## The player moved `t` tonnes to (or, weighted down, from) a site.
static func moved(sim: EconomySim, site_id: String, t: float, carried_away := false) -> void:
	if not on(sim) or t <= 0.0 or not sim.dev.sites.has(site_id):
		return
	var w := float(config().get("carried_away_weight", 0.5)) if carried_away else 1.0
	sim.dev.today[site_id] = float(sim.dev.today.get(site_id, 0.0)) + t * w


## How much a system's works make and its exchange uses, against canon: doubles per stage of growth.
static func demand_scale(sim: EconomySim, sys: String) -> float:
	if sim == null or sim.dev.is_empty():
		return 1.0
	var s: Dictionary = sim.dev.systems.get(sys, {})
	return 1.0 if s.is_empty() else pow(2.0, float(s.score) - float(s.canon))


## Stage index from a score: 0 abandoned, 1 extreme frontier ... 5 core (and stays 5 past it).
static func stage(score: float) -> int:
	if score < float(config().get("abandon_below", 0.5)):
		return 0
	return clampi(int(floor(score + 0.5)), 1, 5)


static func stage_id(i: int) -> String:
	return String(config().stages[clampi(i, 0, 5)])


static func stage_name(i: int) -> String:
	return String(config().stage_names[stage_id(i)])


static func site(sim: EconomySim, site_id: String) -> Dictionary:
	if not on(sim):
		return {}
	return sim.dev.sites.get(site_id, {})


## A site's stage now (its canon stage when growth is off).
static func site_stage(sim: EconomySim, site_id: String) -> int:
	var s := site(sim, site_id)
	if s.is_empty():
		return stage(canon_score(site_id))
	return 0 if bool(s.abandoned) else stage(float(s.score))


static func system_stage(sim: EconomySim, sys: String) -> int:
	if not on(sim) or not sim.dev.systems.has(sys):
		return stage(float(TIER_SCORE.get(SystemStyle.canon_tier(sys), 2.0)))
	return stage(float(sim.dev.systems[sys].score))


static func abandoned(sim: EconomySim, site_id: String) -> bool:
	return site_stage(sim, site_id) == 0


## Whether a site has a service at its stage: freight, repairs, passengers, crew, yard.
static func has(sim: EconomySim, site_id: String, service: String) -> bool:
	var st := site_stage(sim, site_id)
	var sv: Dictionary = config().services
	if service == "yard":
		var kind := String(LocalSpace.node(site_id).get("kind", "port"))
		return st >= int(sv.yard_port if kind == "port" else sv.yard_site)
	return st >= int(sv.get(service, 1))


## Fuel and repairs here against the usual price: dearer out on the edge, cheaper as it grows.
static func price_mult(sim: EconomySim, site_id: String) -> float:
	var st := site_stage(sim, site_id)
	if st == 0:
		return float(config().get("abandoned_fuel_mult", 2.0))
	return 1.0 - float(config().get("price_step", 0.05)) * float(st - 3)


## The rough weight of freight a site draws (for the local board): its need against a frontier site's.
static func pull(sim: EconomySim, site_id: String) -> float:
	var s := site(sim, site_id)
	if s.is_empty():
		return pow(2.0, canon_score(site_id) - 2.0)
	if bool(s.abandoned):
		return 0.0
	return pow(2.0, float(s.score) - 2.0)


## Which way a site is going: its score now against a week ago (per week).
static func trend(s: Dictionary, days := 7) -> float:
	var h: Array = s.get("hist", [])
	if h.size() < 2:
		return 0.0
	var back := mini(days, h.size() - 1)
	return (float(h[h.size() - 1]) - float(h[h.size() - 1 - back])) * 7.0 / float(back)


## Stage changes in the last `days` days, newest first; only in `system_id` if given.
static func recent(sim: EconomySim, days := 14, system_id := "") -> Array:
	var out := []
	if not on(sim):
		return out
	for e in sim.dev.events:
		if sim.day() - int(e.day) <= days and (system_id == "" or String(e.system_id) == system_id):
			out.push_front(e)
	return out
