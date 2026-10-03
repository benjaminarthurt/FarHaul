class_name JumpFx
extends Node3D
## The look of an FTL jump: a shell of stars around the ship that stretches into streaks as the drive
## builds, flows past faster and faster, and collapses again when the ship drops out. Pure visuals:
## flight.gd drives `streak` (0 dots .. 1 full streaks) and the flow speed from its jump timeline.
## Place this node at the ship with the ship's basis, so streaks run along the ship's heading.

const COUNT := 700
const DEPTH := 1800.0
const MIN_R := 25.0
const MAX_R := 520.0

var streak := 0.0          # 0 = round dots, 1 = long streaks
var flow := 0.0            # metres the field has slid past the ship, for the eye only
var _mm: MultiMesh
var _base: PackedVector3Array = PackedVector3Array()   # lateral x, y and starting depth


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in COUNT:
		var r := lerpf(MIN_R, MAX_R, sqrt(rng.randf()))
		var a := rng.randf() * TAU
		_base.append(Vector3(cos(a) * r, sin(a) * r, rng.randf() * DEPTH))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.7, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.93, 1.0)
	box.material = mat
	_mm.mesh = box
	_mm.instance_count = COUNT
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mm
	inst.extra_cull_margin = 4000.0
	add_child(inst)
	set_process(false)
	_layout()


## Move the field on by `speed` metres/second for `dt` and lay the stars out for the current streak.
func advance(dt: float, speed: float) -> void:
	flow += speed * dt
	_layout()


func _layout() -> void:
	if _mm == null:
		return
	var length := 1.0 + streak * 90.0 + streak * streak * 160.0
	for i in COUNT:
		var b := _base[i]
		var z := fposmod(b.z - flow, DEPTH) - DEPTH * 0.5     # stars slide from ahead (-Z) to behind
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, length)), Vector3(b.x, b.y, -z))
		_mm.set_instance_transform(i, t)
