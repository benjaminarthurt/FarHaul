class_name SkyWorlds
extends RefCounted
## The worlds in the sky, system by system (data/world/sky_worlds.json): Sol's real ones (Earth, Luna,
## Mars, Venus, Jupiter, Saturn and its rings, Europa, Titan) and a lived-on world or two for every
## other system, drawn from its canon. Maps are in assets/planets (tools/make_planet_maps.py).
##
## Each world is a lit sphere: a lit and a night side, drifting clouds tinted by its air, shining seas,
## city lights on the night side and lava that glows, a haze toward the limb and a shell for the glow
## of the air on the sunlit edge. Gas giants skip the clouds and seas; ringed ones get their rings.
## Which world fills the view at a site, and which hangs small and far off, is in the data's "systems".

const PATH := "res://data/world/sky_worlds.json"
const MAP_DIR := "res://assets/planets/"

const SURFACE_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D surface : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;   // water, city lights, lava
uniform bool has_mask = false;
uniform float ocean = 0.0;       // how much the water shines
uniform float clouds = 0.0;      // cloud cover, about 0..1.2
uniform vec3 cloud_tint : source_color = vec3(0.93, 0.94, 0.96);
uniform vec3 atmosphere : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmo = 0.0;        // haze toward the limb
uniform float lights = 0.0;      // city lights on the night side
uniform float lava = 0.0;        // lava glow
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);   // toward the sun, world space
uniform float seed = 0.0;

varying vec3 obj;
varying vec3 world_n;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3) + seed);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	obj = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = texture(surface, UV).rgb;
	vec3 m = has_mask ? texture(mask, UV).rgb : vec3(smoothstep(0.04, 0.12, col.b - max(col.r, col.g)), 0.0, 0.0);
	float water = m.r;
	float cover = 0.0;
	if (clouds > 0.0) {
		// Weather: bands of cloud stretched east-west that drift slowly, thicker toward the poles.
		float lat = abs(obj.y);
		vec3 q = obj * vec3(5.0, 8.0, 5.0) + vec3(TIME * 0.003, 0.0, TIME * 0.002);
		float warp = fbm(q * 1.7);
		float c = fbm(q + vec3(warp * 1.6, 0.0, warp));
		float belt = 0.56 + 0.2 * smoothstep(0.35, 0.7, lat) - 0.12 * smoothstep(0.15, 0.35, lat) * (1.0 - smoothstep(0.35, 0.5, lat));
		belt -= (clouds - 0.9) * 0.25;   // heavier cover pulls the threshold down
		cover = min(clouds, 1.0) * smoothstep(belt - 0.05, belt + 0.12, c);
		col = mix(col, cloud_tint, cover);
	}
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, atmosphere, pow(1.0 - facing, 2.5) * atmo);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.28, water * ocean * (1.0 - cover));
	SPECULAR = mix(0.25, 0.75, water * ocean * (1.0 - cover));
	// The night side: city lights, dimmed by cloud, and lava, which glows day and night.
	float day = dot(normalize(world_n), normalize(sun_dir));
	float night = smoothstep(0.08, -0.18, day);
	vec3 glow = vec3(1.0, 0.78, 0.45) * m.g * lights * night * (1.0 - cover * 0.8) * 1.2;
	glow += vec3(1.0, 0.32, 0.08) * m.b * lava * (0.15 + 0.7 * night) * (1.0 - cover * 0.6);
	EMISSION = glow;
}
"""

## The glow of the air at the planet's edge, on the sunlit side only.
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 atmosphere : source_color = vec3(0.4, 0.6, 1.0);
uniform float strength = 1.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);   // toward the sun, world space

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(1.0 - facing, 3.0) * smoothstep(0.0, 0.25, facing);
	float lit = smoothstep(-0.25, 0.45, dot(wn, normalize(sun_dir)));
	ALBEDO = atmosphere * limb * lit * strength;
}
"""

## Rings: many fine bands and a few gaps, brighter on the sunlit face, see-through toward the edges.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec3 colour : source_color = vec3(0.86, 0.8, 0.68);
uniform float opacity = 0.9;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_centre = vec3(0.0);
uniform float planet_radius = 1.0;
varying vec3 world_pos;

float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = UV.x;   // 0 at the inner edge, 1 at the outer
	float bands = 0.55 + 0.25 * n1(r * 60.0) + 0.2 * n1(r * 230.0);
	float gap = smoothstep(0.012, 0.0, abs(r - 0.63)) * 0.9 + smoothstep(0.01, 0.0, abs(r - 0.9)) * 0.5;   // a Cassini-like division
	float a = opacity * bands * (1.0 - gap) * smoothstep(0.0, 0.05, r) * smoothstep(1.0, 0.92, r);
	// The planet's shadow falls across the rings on the night side.
	vec3 to_sun = normalize(sun_dir);
	vec3 rel = world_pos - planet_centre;
	float along = dot(rel, to_sun);
	float off = length(rel - to_sun * along);
	float shadow = (along < 0.0 && off < planet_radius) ? 0.25 : 1.0;
	ALBEDO = colour * (0.55 + 0.45 * bands) * shadow;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _data: Dictionary = {}
static var _surface_shader: Shader
static var _halo_shader: Shader
static var _ring_shader: Shader


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"worlds": {}, "systems": {}}
	return _data


static func world(id: String) -> Dictionary:
	return data().get("worlds", {}).get(id, {})


## The worlds to show at a site: [main, distant] ids ("" for none), or [] for the generic look.
static func for_site(system_id: String, site_kind: String) -> Array:
	var sys: Dictionary = data().get("systems", {}).get(system_id, {})
	return sys.get(site_kind, sys.get("*", sys.get("port", [])))


## The landing body for a system whose moon is a real one (see LocalSpace.body): {body, name} or {}.
static func moon_body(system_id: String) -> Dictionary:
	return data().get("moon_body", {}).get(system_id, {})


## How big a world is drawn, relative to the usual sphere.
static func size(id: String) -> float:
	return float(world(id).get("size", 1.0))


static func _colour(v, fallback: Color) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() >= 3 else fallback


## A world `id` as a sphere of `radius` m, its north pole tilted, lit by the sun toward `sun_dir`, and
## turned so the longitude in its "face" looks along `view` (from the world toward the viewer).
static func build(id: String, radius: float, sun_dir: Vector3, view := Vector3(0, 0, 1)) -> MeshInstance3D:
	var w := world(id)
	var mi := MeshInstance3D.new()
	mi.name = id.capitalize()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 96
	sph.rings = 48
	if _surface_shader == null:
		_surface_shader = Shader.new()
		_surface_shader.code = SURFACE_SHADER
		_halo_shader = Shader.new()
		_halo_shader.code = HALO_SHADER
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	var gas := bool(w.get("gas", false))
	var air := _colour(w.get("atmosphere", null), Color(0, 0, 0))
	var atmo := float(w.get("atmo", 0.0))
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	var map := String(w.get("map", id))
	m.set_shader_parameter("surface", load(MAP_DIR + map + ".jpg"))
	if bool(w.get("mask", false)):
		m.set_shader_parameter("mask", load(MAP_DIR + map + "_mask.jpg"))
		m.set_shader_parameter("has_mask", true)
	m.set_shader_parameter("ocean", 0.0 if gas else float(w.get("ocean", 0.0)))
	m.set_shader_parameter("clouds", 0.0 if gas else float(w.get("clouds", 0.0)))
	m.set_shader_parameter("cloud_tint", _colour(w.get("cloud_tint", null), Color(0.93, 0.94, 0.96)))
	m.set_shader_parameter("atmosphere", air)
	m.set_shader_parameter("atmo", atmo * 0.6)
	m.set_shader_parameter("lights", float(w.get("lights", 0.0)))
	m.set_shader_parameter("lava", float(w.get("lava", 0.0)))
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("seed", float(absi(hash(id)) % 97) * 0.01)
	sph.material = m
	mi.mesh = sph
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The sphere's map wraps so that longitude L sits at angle (L + 180) round Y from +Z.
	var toward := rad_to_deg(atan2(view.x, view.z))
	mi.rotation_degrees = Vector3(0, toward - (float(w.get("face", 0.0)) + 180.0), float(w.get("tilt", 0.0)))
	if atmo > 0.0:
		var shell := SphereMesh.new()
		shell.radius = radius * 1.035
		shell.height = radius * 2.07
		shell.radial_segments = 96
		shell.rings = 48
		var hm := ShaderMaterial.new()
		hm.shader = _halo_shader
		hm.set_shader_parameter("atmosphere", air)
		hm.set_shader_parameter("strength", atmo * 2.2)
		hm.set_shader_parameter("sun_dir", sun_dir)
		shell.material = hm
		var halo := MeshInstance3D.new()
		halo.name = "Air"
		halo.mesh = shell
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(halo)
	var rings: Dictionary = w.get("rings", {})
	if not rings.is_empty():
		mi.add_child(_rings(radius, rings, sun_dir))
	return mi


## A flat ring round the equator, from inner to outer (in planet radii). UV.x runs inner to outer.
static func _rings(radius: float, cfg: Dictionary, sun_dir: Vector3) -> MeshInstance3D:
	var r0 := radius * float(cfg.get("inner", 1.3))
	var r1 := radius * float(cfg.get("outer", 2.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 160
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var pts := [Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a0) * r1, 0, sin(a0) * r1),
				Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a1) * r0, 0, sin(a1) * r0)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[j])
			st.add_vertex(pts[j])
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	mat.set_shader_parameter("colour", _colour(cfg.get("colour", null), Color(0.86, 0.8, 0.68)))
	mat.set_shader_parameter("opacity", float(cfg.get("opacity", 0.9)))
	mat.set_shader_parameter("sun_dir", sun_dir)
	mat.set_shader_parameter("planet_radius", radius)
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Tell a world's rings where the planet is now (for the shadow across them). Call after placing it.
static func settle(planet: Node3D) -> void:
	var r := planet.get_node_or_null("Rings") as MeshInstance3D
	if r != null and r.mesh != null:
		var mat := r.mesh.surface_get_material(0) as ShaderMaterial
		mat.set_shader_parameter("planet_centre", planet.global_position)
