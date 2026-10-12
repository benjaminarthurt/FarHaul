class_name EngineParts
extends RefCounted
## Rocket engine pieces: an open bell nozzle (a surface of revolution with an inside and an outside,
## a rolled lip at the mouth and a hot throat deep inside, not a capped cone) and an exhaust plume
## drawn by a shader: a pale, hot core with faint shock diamonds inside a wide, fading outer plume
## that spreads as it leaves the bell, the way exhaust does in vacuum. ShipView scales the plume
## with the throttle through the `power` instance parameter.

const PLUME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 hot : source_color = vec3(0.80, 0.88, 1.0);
uniform vec3 cool : source_color = vec3(0.45, 0.35, 0.95);
uniform float brightness = 1.0;
uniform float fade = 2.5;           // how fast it fades along its length
uniform float diamonds = 0.0;       // shock-diamond strength
uniform float near_top = 0.0;       // 1: the nozzle end is the mesh's top (UV.y = 0), else its bottom
instance uniform float power = 1.0; // throttle, 0..1

void fragment() {
	float t = mix(1.0 - UV.y, UV.y, near_top);          // 0 at the nozzle, 1 at the far end
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, 2.6);                       // soft edges: it reads as a glowing volume
	float along = exp(-t * fade) * (1.0 - smoothstep(0.45, 1.0, t)) * smoothstep(0.0, 0.04, t);   // no hard ends
	float flicker = 0.92 + 0.08 * sin(TIME * 57.0 + t * 31.0) * sin(TIME * 23.0);
	float shock = diamonds * pow(max(0.0, sin(t * 26.0 - 1.2)), 10.0) * exp(-t * 3.5);
	vec3 col = mix(cool, hot, exp(-t * 2.2));
	ALBEDO = col * (along * flicker + shock) * body * brightness * power;
}
"""

## Seen end-on, the plume's sides face away and it all but vanishes. A soft glow at the mouth, facing
## the camera, fills in what you would see looking up the exhaust; it fades out as you move round
## to the side, where the plume itself shows.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.75, 0.82, 1.0);
uniform float brightness = 1.0;
instance uniform float power = 1.0;
varying float end_on;

void vertex() {
	vec3 axis = normalize((VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz);
	end_on = abs(axis.z);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float glow = exp(-r2 * 5.0) + 0.6 * exp(-r2 * 30.0);
	float edge = 1.0 - smoothstep(0.7, 1.0, sqrt(r2));
	ALBEDO = tint * glow * edge * brightness * power * smoothstep(0.75, 0.98, end_on);
}
"""

static var _shader: Shader
static var _glow_shader: Shader
static var _mats := {}


## A plume material: `hot` near the nozzle fading to `cool`.
static func plume_material(hot: Color, cool: Color, brightness: float, fade: float, diamonds: float, near_top := false) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s|%s" % [hot.to_html(), cool.to_html(), brightness, fade, diamonds, near_top]
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PLUME_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("hot", hot)
	m.set_shader_parameter("cool", cool)
	m.set_shader_parameter("brightness", brightness)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("diamonds", diamonds)
	m.set_shader_parameter("near_top", 1.0 if near_top else 0.0)
	_mats[key] = m
	return m


## A bell nozzle along +Z from `throat_z` (radius `r_throat`) to `exit_z` (radius `r_exit`), flaring
## fast past the throat and straightening toward the mouth. Outside in `outer`, inside in `inner`,
## with a rolled lip at the mouth and a glowing throat deep inside (tagged "throat").
static func bell(root: Node3D, throat_z: float, exit_z: float, r_throat: float, r_exit: float, outer: Material, inner: Material, lip: Material, throat_glow: Material, wall := 0.06) -> void:
	var profile: Array[Vector2] = []   # (radius, z)
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var r := r_throat + (r_exit - r_throat) * pow(t, 0.55)
		profile.append(Vector2(r, lerpf(throat_z, exit_z, t)))
	var outer_mi := MeshInstance3D.new()
	outer_mi.mesh = _lathe(profile, wall, false, outer)
	root.add_child(outer_mi)
	var inner_mi := MeshInstance3D.new()
	inner_mi.mesh = _lathe(profile, 0.0, true, inner)
	root.add_child(inner_mi)
	var ring := TorusMesh.new()   # the rolled lip round the mouth
	ring.inner_radius = r_exit - wall * 0.2
	ring.outer_radius = r_exit + wall * 1.6
	ring.rings = 48
	ring.ring_segments = 8
	ring.material = lip
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.rotation_degrees.x = 90.0
	ri.position = Vector3(0, 0, exit_z)
	root.add_child(ri)
	var disc := CylinderMesh.new()   # the throat, glowing deep inside the bell
	disc.top_radius = r_throat * 0.98
	disc.bottom_radius = r_throat * 0.98
	disc.height = 0.02
	disc.material = throat_glow
	var di := MeshInstance3D.new()
	di.mesh = disc
	di.rotation_degrees.x = 90.0
	di.position = Vector3(0, 0, throat_z + 0.02)
	di.set_meta("throat", true)
	root.add_child(di)


## A surface of revolution round Z through `profile` (radius, z). `offset` pushes it outward (the
## outside of a wall); `inside` turns the normals and winding inward.
static func _lathe(profile: Array[Vector2], offset: float, inside: bool, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var slope := Vector2(b.x - a.x, b.y - a.y).normalized()   # along the profile in (r, z)
		var n_rz := Vector2(slope.y, -slope.x)                     # outward in (r, z)
		if inside:
			n_rz = -n_rz
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var quad := []
			for pt in [[a, t0], [b, t0], [b, t1], [a, t1]]:
				var p: Vector2 = pt[0]
				var ang: float = pt[1]
				var r := p.x + offset
				quad.append([Vector3(cos(ang) * r, sin(ang) * r, p.y), Vector3(cos(ang) * n_rz.x, sin(ang) * n_rz.x, n_rz.y).normalized(), Vector2(float(k) / seg, float(i) / (profile.size() - 1))])
			var order := [0, 1, 2, 0, 2, 3] if inside else [0, 2, 1, 0, 3, 2]
			for j in order:
				st.set_normal(quad[j][1])
				st.set_uv(quad[j][2])
				st.add_vertex(quad[j][0])
	st.set_material(mat)
	return st.commit()


## The exhaust, on a pivot at the bell's mouth (`exit_z`, radius `r_exit`) heading along +Z: a wide,
## faint outer plume spreading as it goes and a bright core with shock diamonds. The pivot's local +Y
## runs down the plume, so scaling it along Y stretches the flame from the mouth (ShipView does, with
## the throttle). The pivot carries `tag` ("flame" or "lift_flame") and starts hidden.
static func plume(root: Node3D, exit_z: float, r_exit: float, length: float, tag := "flame") -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, exit_z)
	pivot.rotation_degrees.x = 90.0   # local +Y turns to +Z: out of the bell
	pivot.visible = false
	pivot.set_meta(tag, true)
	root.add_child(pivot)
	var outer := CylinderMesh.new()
	outer.bottom_radius = r_exit * 0.95          # at the mouth
	outer.top_radius = r_exit * 2.6              # spreading far behind
	outer.height = length
	outer.radial_segments = 24
	outer.rings = 6
	outer.cap_top = false
	outer.cap_bottom = false
	outer.material = plume_material(Color(0.7, 0.8, 1.0), Color(0.3, 0.25, 0.8), 0.9, 1.5, 0.0)
	var core := CylinderMesh.new()
	core.bottom_radius = r_exit * 0.55
	core.top_radius = r_exit * 0.25
	core.height = length * 0.45
	core.radial_segments = 20
	core.rings = 8
	core.cap_top = false
	core.cap_bottom = false
	core.material = plume_material(Color(0.95, 0.97, 1.0), Color(0.55, 0.6, 1.0), 2.6, 2.2, 1.0)
	for m in [outer, core]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(0, (m as CylinderMesh).height * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
	var quad := QuadMesh.new()   # the end-on glow, just out of the mouth
	quad.size = Vector2.ONE * r_exit * 3.8
	quad.material = _glow_material()
	var gi := MeshInstance3D.new()
	gi.mesh = quad
	gi.position = Vector3(0, r_exit * 0.3, 0)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(gi)
	return pivot


static func _glow_material() -> ShaderMaterial:
	if _mats.has("glow"):
		return _mats["glow"]
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	_mats["glow"] = m
	return m
