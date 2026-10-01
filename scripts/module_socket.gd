class_name ModuleSocket
extends Resource
## A connection point on a module: which cell it sits on, which face it points out of,
## and what kind of connector it is.
##
## Two sockets mate when they face each other across a cell boundary and have the same kind.
## One extra rule: a MOUNT socket also mates with any bare hull face of a pressurised module
## (a face that doesn't have a door), so tanks, engines and radiators can bolt straight onto hulls.

const DOOR := &"door"  ## walkable connection between pressurised modules
const MOUNT := &"mount"  ## structural bolt-on point for external parts

@export var cell := Vector3i.ZERO  ## cell of the module (module-local coordinates)
@export var dir := Vector3i(0, 0, -1)  ## outward face: one of the six axis directions
@export var kind: StringName = DOOR


static func make(c: Vector3i, d: Vector3i, k: StringName = DOOR) -> ModuleSocket:
	var s := ModuleSocket.new()
	s.cell = c
	s.dir = d
	s.kind = k
	return s
