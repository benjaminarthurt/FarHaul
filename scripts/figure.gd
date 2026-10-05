class_name Figure
extends Node3D
## A person, low-poly: boots, legs, a jacket in the colour of their job, arms, hands and a head with
## hair or a cap. They breathe, shift their weight, glance about, and turn their head toward you when
## you come near. `look_at_point` is set by the scene each frame (Vector3.INF for no one near).

var look_at_point := Vector3.INF
var _t := 0.0
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _rng := RandomNumberGenerator.new()
var _glance := 0.0
var _glance_t := 0.0
var _gesture := 0.0


## `jacket`: the job colour. `seed_v` picks the skin, hair and build.
static func make(jacket: Color, seed_v: int, seated := false) -> Figure:
	var f := Figure.new()
	f._build(jacket, seed_v, seated)
	return f


func _mat(col: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build(jacket: Color, seed_v: int, seated: bool) -> void:
	_rng.seed = seed_v
	_t = _rng.randf() * 10.0
	var skins := [Color(0.95, 0.78, 0.65), Color(0.82, 0.62, 0.48), Color(0.62, 0.43, 0.3), Color(0.42, 0.28, 0.2), Color(0.88, 0.7, 0.55), Color(0.7, 0.75, 0.82)]
	var hairs := [Color(0.1, 0.08, 0.07), Color(0.35, 0.22, 0.12), Color(0.75, 0.6, 0.35), Color(0.55, 0.55, 0.55), Color(0.6, 0.2, 0.1)]
	var skin := _mat(skins[_rng.randi() % skins.size()])
	var hair := _mat(hairs[_rng.randi() % hairs.size()])
	var cloth := _mat(jacket)
	var trousers := _mat(Color(0.18, 0.2, 0.24).lerp(jacket.darkened(0.6), 0.3))
	var boots := _mat(Color(0.1, 0.1, 0.11))
	var build := _rng.randf_range(0.92, 1.08)
	var height := _rng.randf_range(0.94, 1.06)
	scale = Vector3(build, height, build)
	var hip := 0.5 if seated else 0.92
	# Legs and boots.
	for side in [-1.0, 1.0]:
		if seated:
			_box(self, Vector3(0.16, 0.16, 0.48), Vector3(side * 0.11, hip, -0.18), trousers)
			_box(self, Vector3(0.15, 0.46, 0.16), Vector3(side * 0.11, 0.23, -0.4), trousers)
			_box(self, Vector3(0.16, 0.1, 0.28), Vector3(side * 0.11, 0.05, -0.46), boots)
		else:
			_box(self, Vector3(0.16, 0.84, 0.18), Vector3(side * 0.11, 0.48, 0), trousers)
			_box(self, Vector3(0.17, 0.12, 0.3), Vector3(side * 0.11, 0.06, -0.05), boots)
	# Torso (pivot at the hips so breathing and leaning look right).
	_torso = Node3D.new()
	_torso.position = Vector3(0, hip, 0)
	add_child(_torso)
	_box(_torso, Vector3(0.42, 0.62, 0.24), Vector3(0, 0.33, 0), cloth)
	_box(_torso, Vector3(0.36, 0.1, 0.22), Vector3(0, 0.0, 0), _mat(Color(0.12, 0.12, 0.13)))   # belt
	_box(_torso, Vector3(0.1, 0.12, 0.02), Vector3(0.12, 0.5, -0.125), _mat(jacket.lightened(0.45)))   # badge
	# Arms.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.28, 0.6, 0)
		_torso.add_child(arm)
		_box(arm, Vector3(0.12, 0.56, 0.14), Vector3(0, -0.27, 0), cloth)
		_box(arm, Vector3(0.1, 0.1, 0.11), Vector3(0, -0.6, 0), skin)
		if side < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm
	# Head.
	_head = Node3D.new()
	_head.position = Vector3(0, 0.7, 0)
	_torso.add_child(_head)
	_box(_head, Vector3(0.1, 0.08, 0.1), Vector3(0, 0.03, 0), skin)   # neck
	_box(_head, Vector3(0.22, 0.26, 0.24), Vector3(0, 0.2, 0), skin)
	_box(_head, Vector3(0.04, 0.03, 0.01), Vector3(-0.05, 0.23, -0.121), _mat(Color(0.08, 0.08, 0.1)))   # eyes
	_box(_head, Vector3(0.04, 0.03, 0.01), Vector3(0.05, 0.23, -0.121), _mat(Color(0.08, 0.08, 0.1)))
	if _rng.randf() < 0.35:   # a cap in the job colour
		_box(_head, Vector3(0.25, 0.08, 0.27), Vector3(0, 0.35, 0.0), cloth)
		_box(_head, Vector3(0.22, 0.03, 0.12), Vector3(0, 0.32, -0.18), cloth)
	else:
		_box(_head, Vector3(0.24, 0.07, 0.26), Vector3(0, 0.35, 0.01), hair)
		_box(_head, Vector3(0.24, 0.16, 0.06), Vector3(0, 0.27, 0.12), hair)


func _process(delta: float) -> void:
	_t += delta
	# Breathing and weight shifts.
	_torso.scale = Vector3(1.0, 1.0 + sin(_t * 1.6) * 0.012, 1.0 + sin(_t * 1.6) * 0.02)
	_torso.rotation.z = sin(_t * 0.31) * 0.03
	# Glances, or looking at you.
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_t = _rng.randf_range(2.0, 5.0)
		_glance = _rng.randf_range(-0.7, 0.7) if _rng.randf() < 0.6 else 0.0
		if _rng.randf() < 0.15:
			_gesture = 1.6
	var want := _glance
	if look_at_point != Vector3.INF:
		var to := global_transform.affine_inverse() * look_at_point
		want = clampf(atan2(-to.x, -to.z), -1.1, 1.1)
	_head.rotation.y = lerpf(_head.rotation.y, want, minf(1.0, delta * 3.0))
	# An occasional gesture with the right arm.
	_gesture = maxf(0.0, _gesture - delta)
	var lift := sin(clampf(_gesture / 1.6, 0.0, 1.0) * PI) * 0.9
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -lift, minf(1.0, delta * 6.0))
	_arm_l.rotation.x = sin(_t * 0.7) * 0.04
