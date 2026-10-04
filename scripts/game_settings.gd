class_name GameSettings
extends RefCounted
## The player's settings: graphics quality, display, audio and controls. Kept in settings.cfg beside the
## saves (so a portable copy carries its settings too) and applied to every scene as it opens.

const QUALITIES := ["low", "medium", "high"]
const DEFAULTS := {
	"quality": "medium",
	"fullscreen": false,
	"vsync": true,
	"ui_scale": 1.0,
	"master": 0.8,
	"music": 0.7,
	"effects": 0.8,
	"mouse": 1.0,
}

static var values: Dictionary = {}
static var _loaded := false


static func path() -> String:
	return SaveSlots.dir.path_join("settings.cfg")


static func get_value(key: String) -> Variant:
	_ensure()
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, v: Variant) -> void:
	_ensure()
	values[key] = v
	save()
	apply()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path()) == OK:
		for k in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
	if not (String(values.quality) in QUALITIES):
		values.quality = "medium"


static func save() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	cfg.save(path())


static func reload() -> void:
	_loaded = false
	_ensure()


## Window, audio and interface settings. Graphics quality is applied per scene (apply_scene).
static func apply() -> void:
	_ensure()
	_ensure_buses()
	_bus_volume("Master", float(values.master))
	_bus_volume("Music", float(values.music))
	_bus_volume("Effects", float(values.effects))
	if DisplayServer.get_name() == "headless":
		return
	var full := bool(values.fullscreen)
	var mode := DisplayServer.window_get_mode()
	if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.vsync) else DisplayServer.VSYNC_DISABLED)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.content_scale_factor = clampf(float(values.ui_scale), 0.75, 1.75)
		_apply_viewport(tree.root)


static func _ensure_buses() -> void:
	for name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")


static func _bus_volume(name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


## The audio bus a player should use: "Music" or "Effects" (created on first use).
static func bus(name: String) -> String:
	_ensure_buses()
	return name


static func quality() -> String:
	return String(get_value("quality"))


static func mouse_sensitivity() -> float:
	return clampf(float(get_value("mouse")), 0.2, 3.0)


static func _apply_viewport(vp: Viewport) -> void:
	match quality():
		"low":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"medium":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X if quality() == "low" else Viewport.ANISOTROPY_16X


## Graphics quality for a scene: sun shadows, ambient occlusion and glow on its WorldEnvironment and
## lights. `shadow_m` is how far the sun's shadows should reach in this scene.
static func apply_scene(scene: Node, shadow_m: float = 120.0) -> void:
	_ensure()
	var q := quality()
	var tree := scene.get_tree()
	if tree != null:
		_apply_viewport(tree.root)
	var size: int = {"low": 1024, "medium": 2048, "high": 4096}[q]
	RenderingServer.directional_shadow_atlas_set_size(size, true)
	_walk(scene, q, shadow_m)


static func _walk(node: Node, q: String, shadow_m: float) -> void:
	if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
		var env := (node as WorldEnvironment).environment
		env.ssao_enabled = q == "high"
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.glow_enabled = true
	elif node is DirectionalLight3D:
		var l := node as DirectionalLight3D
		if not l.has_meta("no_shadow") and l.light_energy >= 1.0:   # the key light; fills stay shadowless
			l.shadow_enabled = q != "low"
			l.directional_shadow_max_distance = shadow_m
			l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			l.shadow_blur = 1.5 if q == "high" else 1.0
			l.shadow_bias = 0.05
			l.shadow_normal_bias = 1.5
	elif node is OmniLight3D and node.has_meta("interior_light"):
		(node as OmniLight3D).visible = true
	for c in node.get_children():
		_walk(c, q, shadow_m)
