class_name SimNetwork
extends RefCounted
## Star-route graph for the economy simulation: systems, direct routes and
## ports, loaded from data/world. Pathing is by distance (light years).

var adj: Dictionary = {}          # system -> {neighbour: distance_ly}
var routes: Dictionary = {}       # "a|b" (sorted) -> route dict
var ports: Dictionary = {}        # port_id -> port dict
var ports_by_system: Dictionary = {}
var _path_cache: Dictionary = {}

static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SimNetwork: cannot open %s" % path)
		return null
	return JSON.parse_string(f.get_as_text())

static func pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

func load_from(world_dir: String) -> void:
	_path_cache.clear(); adj.clear(); routes.clear(); ports.clear(); ports_by_system.clear()
	var rd: Dictionary = read_json(world_dir + "routes.json")
	for r in rd.get("routes", []):
		var a: String = r["a"]
		var b: String = r["b"]
		var k := pair_key(a, b)
		if routes.has(k):
			continue  # duplicate pair (data lists bradbury/concord twice)
		routes[k] = r
		if not adj.has(a): adj[a] = {}
		if not adj.has(b): adj[b] = {}
		adj[a][b] = float(r["distance_ly"])
		adj[b][a] = float(r["distance_ly"])
	var pd: Dictionary = read_json(world_dir + "ports.json")
	for p in pd.get("ports", []):
		ports[p["id"]] = p
		var s: String = p["system_id"]
		if not ports_by_system.has(s): ports_by_system[s] = []
		ports_by_system[s].append(p["id"])

func route(a: String, b: String) -> Dictionary:
	return routes.get(pair_key(a, b), {})

## Shortest path (by distance) as an array of system ids, endpoints included.
func path(from_sys: String, to_sys: String) -> Array:
	var ck := from_sys + ">" + to_sys               # the graph never changes after load, so remember answers
	if _path_cache.has(ck):
		return (_path_cache[ck] as Array).duplicate()
	var res := _path(from_sys, to_sys)
	_path_cache[ck] = res
	return res.duplicate()

func _path(from_sys: String, to_sys: String) -> Array:
	if from_sys == to_sys:
		return [from_sys]
	var dist := {from_sys: 0.0}
	var prev := {}
	var open: Array = [from_sys]
	var done := {}
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]]:
				best = i
		var u: String = open[best]
		open.remove_at(best)
		if done.has(u):
			continue
		done[u] = true
		if u == to_sys:
			break
		for v in adj.get(u, {}):
			var nd: float = dist[u] + adj[u][v]
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	if not dist.has(to_sys):
		return []
	var out: Array = [to_sys]
	while out[0] != from_sys:
		out.push_front(prev[out[0]])
	return out

func path_ly(p: Array) -> float:
	var t := 0.0
	for i in range(p.size() - 1):
		t += adj[p[i]][p[i + 1]]
	return t

func primary_port(system_id: String) -> String:
	var l: Array = ports_by_system.get(system_id, [])
	return l[0] if not l.is_empty() else ""
