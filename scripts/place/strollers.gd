class_name Strollers
extends RefCounted
## People walking loops of waypoints in a place. Each stroller is {fig: Figure, path: [Vector3],
## i: next waypoint, wait: seconds to stand, speed: m/s}. Plain logic on the figures' positions, so a
## test can walk them without a scene.


## One stroller walking `path`, starting at waypoint `start`.
static func make(fig: Figure, path: Array, start: int, speed: float, wait := 0.0) -> Dictionary:
	fig.position = path[start % path.size()]
	return {"fig": fig, "path": path, "i": (start + 1) % path.size(), "wait": wait, "speed": speed}


## Walk them all on by `delta` seconds: toward the next waypoint, turning smoothly; stop short of
## `player` (feet, x and z) when they are in the way; pause a few seconds at every other waypoint.
static func step(list: Array[Dictionary], delta: float, player: Vector3) -> void:
	for st in list:
		var f: Figure = st.fig
		if float(st.wait) > 0.0:
			st.wait = float(st.wait) - delta
			f.stride = 0.0
			continue
		var target: Vector3 = st.path[int(st.i)]
		var to := target - f.position
		to.y = 0.0
		var d := to.length()
		if d < 0.15:
			st.i = (int(st.i) + 1) % (st.path as Array).size()
			st.wait = 0.0 if (int(st.i) % 2) == 1 else 2.5 + float(hash(st.i) % 30) / 10.0
			continue
		var dir := to / d
		var ahead := Vector3(player.x, 0, player.z) - f.position
		ahead.y = 0.0
		if ahead.length() < 1.3 and ahead.normalized().dot(dir) > 0.3:
			f.stride = 0.0   # someone in the way: wait for them to pass
			continue
		var speed := float(st.speed)
		f.position += dir * minf(speed * delta, d)
		f.rotation.y = lerp_angle(f.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 6.0))
		f.stride = speed


## Push `pos` (the player's feet) out of any stroller it overlaps, so you bump into people.
static func push_out(list: Array[Dictionary], pos: Vector3, radius := 0.55) -> Vector3:
	for st in list:
		var q: Vector3 = (st.fig as Figure).position
		var off := Vector2(pos.x - q.x, pos.z - q.z)
		if off.length() < radius and off.length() > 0.001:
			var out := off.normalized() * radius
			pos.x = q.x + out.x
			pos.z = q.z + out.y
	return pos
