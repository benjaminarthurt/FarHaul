class_name PlanetScenery
extends Node3D
## Everything on a planet with air for the flight scene: the ground (a coarse 40 km mesh and a fine one
## that follows the ship), the sea, the sky and its haze by height and hour, the downport's pad with its
## lights, tower and sheds, the landing field, and the city on the skyline a few km off, lit at night.
## It only builds and keeps the view up to date (`follow`); the flight scene decides what happens.
## Can be built without the scene, for tests and captures.

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 hole = vec4(0.0);     // x0, z0, x1, z1: the fine mesh's square, cut out of the coarse one
uniform bool cut = false;
uniform float grain = 1.0;
varying vec3 wpos;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (cut && wpos.x > hole.x && wpos.x < hole.z && wpos.z > hole.y && wpos.z < hole.w) { discard; }
	float d = 0.75 + 0.18 * vn(wpos.xz * 0.05) + 0.07 * vn(wpos.xz * 0.6) * grain + 0.05 * vn(wpos.xz * 3.0) * grain;
	ALBEDO = COLOR.rgb * COLOR.rgb * d;   // the vertex colours are sRGB: square them to about linear
	ROUGHNESS = 0.95;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 water : source_color = vec3(0.1, 0.25, 0.3);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.4;
	vec2 w = vec2(sin(wpos.x * 0.021 + t) + sin(wpos.z * 0.017 - t * 0.8), cos(wpos.x * 0.013 - t * 0.6) + sin(wpos.z * 0.029 + t * 1.3));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(w.x * 0.04, 0.0, w.y * 0.04, 0.0)).xyz);
	ALBEDO = water;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""

## Lit windows on the city's towers, by night; glass and stone by day.
const BUILDING_SHADER := """
shader_type spatial;
uniform vec3 wall : source_color = vec3(0.6, 0.6, 0.62);
uniform vec3 glass : source_color = vec3(0.25, 0.3, 0.36);
uniform vec3 lamp : source_color = vec3(1.0, 0.82, 0.55);
uniform float night = 0.0;
uniform float lit_share = 0.45;
varying vec3 wpos;
varying vec3 nrm;
varying float seed;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	seed = float(INSTANCE_ID);
}
void fragment() {
	vec3 n = normalize(nrm);
	float side = 1.0 - abs(n.y);
	vec2 f = abs(n.x) > abs(n.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
	vec2 cell = floor(f / vec2(4.0, 4.2));
	vec2 in_c = fract(f / vec2(4.0, 4.2));
	float win = step(0.18, in_c.x) * step(in_c.x, 0.82) * step(0.25, in_c.y) * step(in_c.y, 0.8) * step(2.0, wpos.y);
	float on = step(1.0 - lit_share, h21(cell + vec2(seed * 3.1, seed * 7.7)));
	vec3 col = mix(wall, glass, win * side * 0.85);
	ALBEDO = col * (1.0 - night * 0.65);
	ROUGHNESS = mix(0.85, 0.25, win * side);
	float far = clamp(length(VERTEX) / 3000.0, 0.0, 1.0);   // far off, the windows blur into a glow
	float b = 0.55 + 0.9 * fract(sin(seed * 12.9898) * 43758.5453);   // some blocks brighter than others
	EMISSION = lamp * night * side * mix(win * on * 2.6, lit_share * 0.8 * b, far);
}
"""

const STYLES := {
	"old": {"h": [8.0, 28.0], "tall": [60.0, 170.0], "tall_share": 0.05, "w": [10.0, 26.0], "wall": [0.62, 0.52, 0.44], "glass": [0.28, 0.3, 0.34], "round": 0.05},
	"towers": {"h": [20.0, 70.0], "tall": [110.0, 330.0], "tall_share": 0.14, "w": [16.0, 34.0], "wall": [0.6, 0.64, 0.68], "glass": [0.24, 0.32, 0.42], "round": 0.1},
	"kesh": {"h": [14.0, 34.0], "tall": [60.0, 120.0], "tall_share": 0.06, "w": [26.0, 50.0], "wall": [0.66, 0.52, 0.36], "glass": [0.32, 0.26, 0.2], "round": 0.0},
	"spires": {"h": [30.0, 110.0], "tall": [220.0, 460.0], "tall_share": 0.12, "w": [7.0, 14.0], "wall": [0.7, 0.68, 0.82], "glass": [0.3, 0.3, 0.46], "round": 0.5},
	"vey": {"h": [6.0, 20.0], "tall": [30.0, 60.0], "tall_share": 0.04, "w": [14.0, 30.0], "wall": [0.86, 0.88, 0.86], "glass": [0.3, 0.42, 0.46], "round": 0.6},
	"orun": {"h": [5.0, 16.0], "tall": [24.0, 50.0], "tall_share": 0.05, "w": [18.0, 40.0], "wall": [0.58, 0.44, 0.32], "glass": [0.3, 0.22, 0.16], "round": 0.4, "domes": 0.3},
	"industrial": {"h": [10.0, 36.0], "tall": [60.0, 120.0], "tall_share": 0.05, "w": [24.0, 60.0], "wall": [0.5, 0.5, 0.5], "glass": [0.28, 0.3, 0.3], "round": 0.15, "stacks": 0.08},
	"agri": {"h": [6.0, 16.0], "tall": [40.0, 80.0], "tall_share": 0.04, "w": [20.0, 50.0], "wall": [0.72, 0.68, 0.58], "glass": [0.3, 0.32, 0.3], "round": 0.3},
	"research": {"h": [12.0, 48.0], "tall": [70.0, 140.0], "tall_share": 0.05, "w": [16.0, 36.0], "wall": [0.84, 0.84, 0.82], "glass": [0.3, 0.36, 0.42], "round": 0.2, "domes": 0.12},
	"floating": {"h": [8.0, 30.0], "tall": [50.0, 90.0], "tall_share": 0.05, "w": [14.0, 30.0], "wall": [0.8, 0.78, 0.7], "glass": [0.3, 0.4, 0.46], "round": 0.35, "water": true},
	"rigs": {"h": [14.0, 30.0], "tall": [50.0, 90.0], "tall_share": 0.2, "w": [20.0, 40.0], "wall": [0.5, 0.48, 0.44], "glass": [0.3, 0.3, 0.3], "round": 0.2, "water": true, "stacks": 0.15},
	"vents": {"h": [5.0, 14.0], "tall": [40.0, 90.0], "tall_share": 0.06, "w": [20.0, 44.0], "wall": [0.36, 0.32, 0.3], "glass": [0.5, 0.26, 0.12], "round": 0.2, "stacks": 0.18},
	"boomtown": {"h": [4.0, 11.0], "tall": [18.0, 30.0], "tall_share": 0.04, "w": [10.0, 24.0], "wall": [0.6, 0.56, 0.5], "glass": [0.3, 0.28, 0.26], "round": 0.1},
	"frontier": {"h": [3.0, 7.0], "tall": [12.0, 20.0], "tall_share": 0.04, "w": [8.0, 16.0], "wall": [0.62, 0.6, 0.56], "glass": [0.3, 0.3, 0.3], "round": 0.2},
	"domes": {"h": [5.0, 12.0], "tall": [20.0, 40.0], "tall_share": 0.04, "w": [14.0, 30.0], "wall": [0.8, 0.78, 0.74], "glass": [0.3, 0.3, 0.32], "round": 0.1, "domes": 0.5},
}

var system_id := ""
var kind := "world"
var terrain: PlanetTerrain
var planet: Dictionary = {}
var far_mesh: MeshInstance3D
var near_mesh: MeshInstance3D
var near_centre := Vector2.INF
var near_size := 3200.0
var near_cells := 200
var _near_task := -1
var _near_next: ArrayMesh
var _near_next_centre := Vector2.ZERO
var _far_mat: ShaderMaterial
var _near_mat: ShaderMaterial
var city: Node3D
var _building_mats: Array[ShaderMaterial] = []
var _lamps: Array[StandardMaterial3D] = []
var pad_label: Label3D
var field_label: Label3D
var city_label: Label3D
var city_buildings := 0
var sea: MeshInstance3D


## Build it all. `far` is a prebuilt far ground mesh (from a worker thread), or null to build one here.
func build(sys: String, kind_: String, t: PlanetTerrain, far: ArrayMesh = null, stage := 3) -> void:
	system_id = sys
	kind = "world" if kind_ == "field" else kind_
	terrain = t
	planet = Planets.planet(sys, kind)
	var tc: Dictionary = Planets.config().terrain
	near_size = float(tc.near_size_m)
	near_cells = int(tc.near_cells)
	var gs := Shader.new()
	gs.code = GROUND_SHADER
	_far_mat = ShaderMaterial.new()
	_far_mat.shader = gs
	_far_mat.set_shader_parameter("cut", true)
	_far_mat.set_shader_parameter("grain", 0.4)
	_near_mat = ShaderMaterial.new()
	_near_mat.shader = gs
	far_mesh = MeshInstance3D.new()
	far_mesh.name = "FarGround"
	far_mesh.mesh = far if far != null else t.planet_mesh(Vector2.ZERO, float(tc.size_m), int(tc.far_cells), planet, true)
	far_mesh.material_override = _far_mat
	far_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mesh)
	near_mesh = MeshInstance3D.new()
	near_mesh.name = "NearGround"
	near_mesh.material_override = _near_mat
	near_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(near_mesh)
	_set_near(t.planet_mesh(Vector2.ZERO, near_size, near_cells, planet), Vector2.ZERO)
	_build_skirt()
	if terrain.sea_on:
		_build_sea()
	_build_port()
	if kind == "world" and planet.has("field"):
		_build_field()
	_build_city(stage)


func _set_near(m: ArrayMesh, centre: Vector2) -> void:
	near_mesh.mesh = m
	near_centre = centre
	var h := near_size * 0.5 - 2.0
	_far_mat.set_shader_parameter("hole", Vector4(centre.x - h, centre.y - h, centre.x + h, centre.y + h))


## Past the 40 km of map: the land at its average, out to the horizon, under the haze.
func _build_skirt() -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900000, 900000)
	var mat := StandardMaterial3D.new()
	var c: Array = planet.get("ground", [0.4, 0.4, 0.3])
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2])) * 0.9
	mat.roughness = 1.0
	pm.material = mat
	m.mesh = pm
	m.position = Vector3(0, minf(terrain._avg, 0.0 if terrain.sea_on else terrain._avg) - 6.0, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.name = "Skirt"
	add_child(m)


func _build_sea() -> void:
	sea = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900000, 900000)
	pm.subdivide_width = 0
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var w: Array = planet.get("water", [0.1, 0.25, 0.3])
	mat.set_shader_parameter("water", Color(float(w[0]), float(w[1]), float(w[2])))
	pm.material = mat
	sea.mesh = pm
	sea.position = Vector3(0, 0.0, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.name = "Sea"
	add_child(sea)


func _lamp_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.set_meta("base", energy)
	_lamps.append(m)
	return m


func _box(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = at + Vector3(0, size.y * 0.5, 0)
	add_child(mi)
	return mi


## The downport: a big lit pad, the terminal, a control tower, hangars, fuel tanks, a beacon. On an ocean
## world it all stands on a platform over the water.
func _build_port() -> void:
	var y := terrain.port_h
	var pad_r := 32.0
	if terrain.platform:
		var deck := _box(Vector3(0, y - 6.0, 0), Vector3(240, 6.0, 240), Interiors.flat(Color(0.32, 0.32, 0.34), 0.9))
		deck.name = "Platform"
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var cy := CylinderMesh.new()
				cy.top_radius = 5.0
				cy.bottom_radius = 6.0
				cy.height = y + 40.0
				cy.material = Interiors.flat(Color(0.3, 0.3, 0.3), 0.9)
				leg.mesh = cy
				leg.position = Vector3(sx * 100.0, (y - 40.0) * 0.5 - 6.0, sz * 100.0)
				add_child(leg)
	if not terrain.platform:   # the concrete apron round the pad, the terminal and the sheds
		var apron := _box(Vector3(0, y - 0.6, -30.0), Vector3(320, 0.65, 260), Interiors.flat(Color(0.36, 0.36, 0.37), 0.95))
		apron.name = "Apron"
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = pad_r
	disc.bottom_radius = pad_r + 1.5
	disc.height = 0.5
	disc.material = Interiors.flat(Color(0.34, 0.35, 0.37), 0.9)
	pad.mesh = disc
	pad.position = Vector3(0, y + 0.05, 0)
	add_child(pad)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = pad_r - 2.0
	tor.outer_radius = pad_r - 0.9
	tor.material = SurfaceTextures.hazard_material()
	ring.mesh = tor
	ring.position = Vector3(0, y + 0.32, 0)
	ring.scale = Vector3(1, 0.05, 1)
	add_child(ring)
	for k in 16:   # edge lights
		var lamp := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.8, 0.5, 0.8)
		b.material = _lamp_mat(Color(1.0, 0.75, 0.3) if k % 2 == 0 else Color(0.4, 0.9, 1.0), 2.0)
		lamp.mesh = b
		var ang := k * TAU / 16.0
		lamp.position = Vector3(cos(ang), 0, sin(ang)) * (pad_r + 2.0) + Vector3(0, y + 0.4, 0)
		add_child(lamp)
	var concrete := Interiors.flat(Color(0.62, 0.62, 0.6), 0.9)
	var dark := Interiors.flat(Color(0.24, 0.25, 0.27), 0.8)
	# The terminal, long and low, with a lit glass front facing the pad.
	var term := _box(Vector3(0, y, -95.0), Vector3(120, 14, 26), concrete)
	term.name = "Terminal"
	_box(Vector3(0, y + 4.0, -81.9), Vector3(110, 6, 0.3), _lamp_mat(Color(0.75, 0.85, 1.0), 0.8))
	# Control tower.
	_box(Vector3(70, y, -90), Vector3(8, 34, 8), concrete)
	_box(Vector3(70, y + 34, -90), Vector3(14, 6, 14), _lamp_mat(Color(0.5, 0.8, 1.0), 0.7))
	var beacon := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.2
	sp.height = 2.4
	sp.material = _lamp_mat(Color(1.0, 0.25, 0.2), 4.0)
	beacon.mesh = sp
	beacon.position = Vector3(70, y + 42, -90)
	add_child(beacon)
	# Hangars and fuel tanks round the apron.
	for i in 3:
		var hg := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 16.0
		cy.bottom_radius = 16.0
		cy.height = 40.0
		cy.radial_segments = 20
		cy.material = dark
		hg.mesh = cy
		hg.rotation_degrees = Vector3(0, 0, 90)
		hg.position = Vector3(-130.0 + i * 0.0, y, -30.0 + i * 46.0)
		hg.scale = Vector3(1, 1, 0.9)
		add_child(hg)
	for i in 4:
		var tk := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 7.0
		cy.bottom_radius = 7.0
		cy.height = 16.0
		cy.material = Interiors.flat(Color(0.82, 0.82, 0.78), 0.6)
		tk.mesh = cy
		tk.position = Vector3(120.0 + (i % 2) * 18.0, y + 8.0, 30.0 + (i / 2) * 18.0)
		add_child(tk)
	pad_label = _label("%s  PAD 1" % String(planet.get("port", "Downport")).to_upper(), Vector3(0, y + 18, 0), Color(1.0, 0.8, 0.4))


func _label(text: String, at: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = col
	l.outline_size = 8
	l.position = at
	add_child(l)
	return l


## The landing field: rough ground graded flat, flares at the corners, a shed and a windsock, no beacon.
func _build_field() -> void:
	var f := terrain.field_xz
	var y := terrain.field_h
	var base := Vector3(f.x, y, f.y)
	if terrain.platform:
		_box(base + Vector3(0, -5, 0), Vector3(110, 5, 110), Interiors.flat(Color(0.3, 0.3, 0.3), 0.9))
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 26.0
	disc.bottom_radius = 27.0
	disc.height = 0.3
	disc.material = Interiors.flat(Color(0.42, 0.4, 0.36), 1.0)
	pad.mesh = disc
	pad.position = base + Vector3(0, 0.02, 0)
	add_child(pad)
	for k in 4:
		var flare := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.5
		sp.height = 1.0
		sp.material = _lamp_mat(Color(1.0, 0.4, 0.15), 3.0)
		flare.mesh = sp
		var a := k * TAU / 4.0 + 0.4
		flare.position = base + Vector3(cos(a) * 30.0, 0.6, sin(a) * 30.0)
		add_child(flare)
	_box(base + Vector3(45, 0, -20), Vector3(16, 6, 10), Interiors.flat(Color(0.55, 0.5, 0.42), 0.9))
	_box(base + Vector3(45, 6, -20), Vector3(17, 0.4, 11), Interiors.flat(Color(0.35, 0.32, 0.3), 0.9))
	_box(base + Vector3(30, 0, 34), Vector3(0.2, 7, 0.2), Interiors.flat(Color(0.7, 0.7, 0.7), 0.6))
	_box(base + Vector3(30.8, 6.2, 34), Vector3(1.8, 0.5, 0.5), _lamp_mat(Color(1.0, 0.5, 0.15), 1.0))   # the windsock
	field_label = _label(String(planet.get("field", {}).get("name", "Landing field")).to_upper(), base + Vector3(0, 16, 0), Color(1.0, 0.6, 0.3))


## How many buildings a city of `population` shows at a growth stage, and how far it spreads (m).
static func city_size(population: float, stage: int, canon_stage: int) -> Dictionary:
	var lp := log(maxf(population, 2000.0) / 2000.0) / log(10.0)   # 0 for a hamlet, ~3.7 for ten million
	var base := clampi(int(40.0 + 560.0 * lp), 40, 2400)
	var n := clampi(int(float(base) * pow(1.6, float(stage - canon_stage))), 0, 3200)
	if stage == 0:
		n = n / 6
	var r := clampf(250.0 + 420.0 * lp, 250.0, 1900.0) * sqrt(maxf(float(n), 1.0) / float(base))
	return {"count": n, "radius": r, "lift": 1.0 + 0.45 * lp}


## The city: buildings packed toward the middle, tallest there, in the world's own style, lit at night.
func _build_city(stage: int) -> void:
	city = Node3D.new()
	city.name = "City"
	add_child(city)
	var c := terrain.city_xz
	var st: Dictionary = STYLES.get(String(planet.get("city_style", "towers")), STYLES.towers)
	var canon := Development.stage(Development.canon_score(system_id + LocalSpace.SEP + kind))
	var cs := city_size(float(planet.get("population", 100000)), stage, canon)
	var n := int(cs.count)
	var r := float(cs.radius)
	city_buildings = n
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("city|" + system_id + "|" + kind)
	var shader := Shader.new()
	shader.code = BUILDING_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("wall", PlanetTerrain._c(st.wall))
	mat.set_shader_parameter("glass", PlanetTerrain._c(st.glass))
	mat.set_shader_parameter("lit_share", 0.2 if stage == 0 else 0.45)
	_building_mats.append(mat)
	var shapes := {"box": [], "round": [], "dome": [], "stack": []}
	var on_water := bool(st.get("water", false))
	for i in n:
		var a := rng.randf() * TAU
		var d := r * pow(rng.randf(), 0.75)
		var p := c + Vector2(cos(a), sin(a)) * d
		var g := terrain.ground(p.x, p.y)
		var wet := terrain.sea_on and g < 1.0
		if wet and not on_water:
			continue
		var centre_k := 1.0 - d / r
		var tall := rng.randf() < float(st.tall_share) * (0.4 + 2.4 * centre_k * centre_k) * float(cs.lift)
		var hr: Array = st.tall if tall else st.h
		var h := rng.randf_range(float(hr[0]), float(hr[1])) * (0.55 + 0.75 * centre_k) * (float(cs.lift) if tall else sqrt(float(cs.lift)))
		var w := rng.randf_range(float(st.w[0]), float(st.w[1])) * 1.25
		var base_y := maxf(g, 0.0) if not wet else 2.0
		var shape := "box"
		var roll := rng.randf()
		if roll < float(st.get("domes", 0.0)):
			shape = "dome"
		elif roll < float(st.get("domes", 0.0)) + float(st.get("stacks", 0.0)):
			shape = "stack"
		elif rng.randf() < float(st.get("round", 0.1)):
			shape = "round"
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w * rng.randf_range(0.6, 1.4))), Vector3(p.x, base_y, p.y))
		if shape == "dome":
			xf = Transform3D(Basis.IDENTITY.scaled(Vector3(w, w * 0.6, w)), Vector3(p.x, base_y, p.y))
		elif shape == "stack":
			xf = Transform3D(Basis.IDENTITY.scaled(Vector3(3.5, rng.randf_range(40.0, 110.0), 3.5)), Vector3(p.x, base_y, p.y))
		(shapes[shape] as Array).append(xf)
		if wet:   # stilts under it
			(shapes["stack"] as Array).append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 22.0, 2.0)), Vector3(p.x, -20.0, p.y)))
	var meshes := {}
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	meshes["box"] = bm
	var rm := CylinderMesh.new()
	rm.top_radius = 0.5
	rm.bottom_radius = 0.5
	rm.height = 1.0
	rm.radial_segments = 12
	rm.rings = 1
	meshes["round"] = rm
	var dm := SphereMesh.new()
	dm.radius = 0.5
	dm.height = 1.0
	dm.is_hemisphere = true
	dm.radial_segments = 16
	dm.rings = 6
	meshes["dome"] = dm
	var sm := CylinderMesh.new()
	sm.top_radius = 0.4
	sm.bottom_radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 1
	meshes["stack"] = sm
	for key in shapes:
		var list: Array = shapes[key]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key]
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[i]
			if key != "dome":   # the unit meshes are centred: lift each so it stands on the ground
				xf.origin += xf.basis.y * 0.5
			mm.set_instance_transform(i, xf)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "City_" + String(key)
		city.add_child(mi)
	_build_street_lights(c, r, n, rng, on_water)
	_build_glow_dome(c, r, float(cs.lift))
	city_label = _label(String(planet.get("city", "City")).to_upper(), Vector3(c.x, terrain.city_h + 260.0, c.y), Color(0.85, 0.9, 1.0))
	city_label.font_size = 36


## Street lights: a scatter of small warm lamps through the city, the thing you see of it at night from
## the air. Dim by day.
func _build_street_lights(c: Vector2, r: float, n: int, rng: RandomNumberGenerator, on_water: bool) -> void:
	var count := clampi(n * 3, 60, 4000)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := SphereMesh.new()
	q.radius = 1.0
	q.height = 2.0
	q.radial_segments = 4
	q.rings = 2
	mm.mesh = q
	var xs: Array[Transform3D] = []
	for i in count:
		var a := rng.randf() * TAU
		var d := r * 1.15 * sqrt(rng.randf())
		var p := c + Vector2(cos(a), sin(a)) * d
		var g := terrain.ground(p.x, p.y)
		if terrain.sea_on and g < 0.5 and not on_water:
			continue
		xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(1.6, 3.2)), Vector3(p.x, maxf(g, 0.5) + 5.0, p.y)))
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _lamp_mat(Color(1.0, 0.72, 0.38), 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "StreetLights"
	city.add_child(mi)
	_street = mi


var _street: MultiMeshInstance3D
var _dome_mat: ShaderMaterial
var _dome_k := 1.0

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.62, 0.32);
uniform float strength = 0.0;
varying float up;
void vertex() { up = clamp(VERTEX.y / 0.5, 0.0, 1.0); }
void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float low = (1.0 - up) * (1.0 - up);
	ALBEDO = tint * strength * low * face * face;
}
"""


## The glow a city throws up into the air at night: what you see of it from far off, before the lights.
func _build_glow_dome(c: Vector2, r: float, lift: float) -> void:
	var dome := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.is_hemisphere = true
	sp.radial_segments = 32
	sp.rings = 8
	var sh := Shader.new()
	sh.code = DOME_SHADER
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = sh
	sp.material = _dome_mat
	dome.mesh = sp
	dome.scale = Vector3(r * 3.2, r * 0.9, r * 3.2)
	dome.position = Vector3(c.x, maxf(terrain.city_h, 0.0), c.y)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.name = "CityGlow"
	city.add_child(dome)
	_dome_k = clampf(lift / 2.6, 0.25, 1.0)


## Keep the view up to date as the ship moves: the fine ground follows it (rebuilt on a worker thread),
## and the night lights come up as the sun goes down. `night` is 0 by day, 1 at night.
func follow(pos: Vector3, night: float) -> void:
	if _near_task >= 0 and WorkerThreadPool.is_task_completed(_near_task):
		WorkerThreadPool.wait_for_task_completion(_near_task)
		_near_task = -1
		if _near_next != null:
			_set_near(_near_next, _near_next_centre)
			_near_next = null
	var here := Vector2(pos.x, pos.z)
	var alt := pos.y - terrain.height(pos.x, pos.z)
	if _near_task < 0 and alt < 12000.0 and here.distance_to(near_centre) > near_size * 0.22:
		var step := near_size / float(near_cells)
		_near_next_centre = Vector2(snappedf(here.x, step * 4.0), snappedf(here.y, step * 4.0))
		_near_task = WorkerThreadPool.add_task(_build_near, false, "planet near ground")
	for m in _building_mats:
		m.set_shader_parameter("night", night)
	for l in _lamps:
		l.emission_energy_multiplier = float(l.get_meta("base", 1.0)) * (0.4 + 0.9 * night)
	if _street != null:
		_street.visible = night > 0.15
	if _dome_mat != null:
		_dome_mat.set_shader_parameter("strength", night * 0.22 * _dome_k)
	var high := pos.y - terrain.port_h > 14000.0   # names on the ground only once they mean something
	if city_label != null:
		city_label.visible = not high
	if field_label != null:
		field_label.visible = not high and Vector2(pos.x - terrain.field_xz.x, pos.z - terrain.field_xz.y).length() < 20000.0


## Rain, snow or blown dust round the camera, when the weather has any (`kind` from Planets.weather).
var _precip: GPUParticles3D
var _precip_kind := ""


func set_weather(kind: String, wind: Vector3) -> void:
	if kind == _precip_kind:
		if _precip != null:
			(_precip.process_material as ParticleProcessMaterial).gravity = _fall(kind) + wind
		return
	_precip_kind = kind
	if _precip != null:
		_precip.queue_free()
		_precip = null
	if not kind in ["rain", "snow", "dust"]:
		return
	_precip = GPUParticles3D.new()
	_precip.name = "Weather"
	_precip.amount = {"rain": 3000, "snow": 2000, "dust": 1600}[kind]
	_precip.lifetime = {"rain": 1.4, "snow": 6.0, "dust": 3.0}[kind]
	_precip.preprocess = _precip.lifetime
	_precip.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(60, 30, 60)
	pm.gravity = _fall(kind) + wind
	pm.direction = Vector3.DOWN
	pm.spread = 5.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 1.0
	_precip.process_material = pm
	var q := QuadMesh.new()
	q.size = {"rain": Vector2(0.03, 0.9), "snow": Vector2(0.12, 0.12), "dust": Vector2(0.14, 0.14)}[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if kind == "rain" else BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = {"rain": Color(0.75, 0.8, 0.9, 0.35), "snow": Color(1, 1, 1, 0.85), "dust": PlanetTerrain._c(planet.get("ground", [0.5, 0.4, 0.3])).lightened(0.2) * Color(1, 1, 1, 0.5)}[kind]
	q.material = m
	_precip.draw_pass_1 = q
	add_child(_precip)


static func _fall(kind: String) -> Vector3:
	return Vector3.DOWN * {"rain": 60.0, "snow": 1.2, "dust": 0.4}.get(kind, 0.0)


## Keep the weather round the camera.
func weather_at(cam_pos: Vector3) -> void:
	if _precip != null:
		_precip.global_position = cam_pos + Vector3(0, 10, 0)


func _build_near() -> void:
	_near_next = terrain.planet_mesh(_near_next_centre, near_size, near_cells, planet)


func _exit_tree() -> void:
	if _near_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_near_task)
		_near_task = -1


# --- Sky and light ----------------------------------------------------------------------------------

## How dark it is at an hour of the planet's day: 0 at noon, 1 in the middle of the night.
static func night_at(hour_of_day: float) -> float:
	var sun_up := sin((hour_of_day - 6.0) / 24.0 * TAU)   # 1 at noon, -1 at midnight
	return clampf(0.5 - sun_up * 2.0, 0.0, 1.0)


## The planet's hour of day at a calendar hour (each world turns at its own phase).
static func local_hour(system_id_: String, hour: int, minutes := 0.0) -> float:
	var off := float(absi(hash(system_id_ + "|day")) % 24)
	return fmod(float(hour) + off + minutes / 60.0, 24.0)


## A sky for the planet: its colour by day, darkening toward space with height and toward night.
static func make_sky(planet_: Dictionary) -> Sky:
	var mat := ProceduralSkyMaterial.new()
	var c := PlanetTerrain._c(planet_.get("sky", [0.45, 0.65, 0.95]))
	mat.sky_top_color = c.darkened(0.25)
	mat.sky_horizon_color = c.lightened(0.35)
	mat.ground_horizon_color = c.lightened(0.2)
	mat.ground_bottom_color = PlanetTerrain._c(planet_.get("ground", [0.3, 0.3, 0.3]))
	mat.sun_angle_max = 30.0
	mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = mat
	return sky


## Update the sky, sun, ambient and haze for the ship's height and the hour. `air_k` is the air's
## density there against sea level (1 on the ground, toward 0 in space); `weather_fog` thickens it.
static func update_sky(env: Environment, sun: DirectionalLight3D, planet_: Dictionary, hour_of_day: float, air_k: float, weather_fog: float) -> void:
	var mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	var night := night_at(hour_of_day)
	var c := PlanetTerrain._c(planet_.get("sky", [0.45, 0.65, 0.95]))
	var thin := clampf(1.0 - sqrt(clampf(air_k, 0.0, 1.0)), 0.0, 1.0)   # 0 down low, 1 up at the edge of space
	var day_k := (1.0 - night) * (1.0 - thin * 0.85)
	if mat != null:
		mat.sky_top_color = c.darkened(0.25).lerp(Color(0.01, 0.01, 0.03), 1.0 - day_k)
		mat.sky_horizon_color = c.lightened(0.35).lerp(Color(0.04, 0.04, 0.07), clampf(night * 0.95, 0.0, 1.0)).lerp(c.darkened(0.5), thin * (1.0 - night))
		mat.ground_horizon_color = mat.sky_horizon_color
		mat.sky_energy_multiplier = 0.3 + 0.7 * (1.0 - night)
	var elev := sin((hour_of_day - 6.0) / 24.0 * TAU)
	sun.rotation_degrees = Vector3(-clampf(rad_to_deg(asin(clampf(elev, -1.0, 1.0))), -8.0, 75.0) - 4.0, fmod(hour_of_day * 15.0, 360.0), 0)
	sun.light_energy = clampf(elev * 3.0 + 0.2, 0.0, 1.0) * 0.95
	sun.light_color = Color(1.0, 0.86, 0.7).lerp(Color(1.0, 0.97, 0.92), clampf(elev * 2.0, 0.0, 1.0))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.15 + 0.3 * (1.0 - night)
	env.fog_enabled = true
	env.fog_light_color = c.lightened(0.3).lerp(Color(0.05, 0.05, 0.08), night * 0.9)
	env.fog_light_energy = 0.65
	env.fog_sun_scatter = 0.15
	var haze := float(planet_.get("haze", 0.5))
	env.fog_density = (0.000012 + 0.00004 * haze + 0.0005 * weather_fog) * clampf(air_k, 0.02, 1.0)
	env.fog_sky_affect = 0.15 + 0.5 * weather_fog
