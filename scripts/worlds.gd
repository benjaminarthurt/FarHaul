class_name Worlds
extends RefCounted
## Starting choices for a new game. All names and numbers are placeholders.
## The starting world decides which shipyard you begin at; the builder only opens at a yard.

const WORLDS := [
	{
		"id": "calder", "name": "Calder Station", "yard_name": "Calder Yard", "yard_type": "Space dock",
		"blurb": "A crowded trade hub in orbit round a gas giant. Plenty of freight and plenty of competition.",
	},
	{
		"id": "ketterick", "name": "Port Ketterick", "yard_name": "Ketterick Slipways", "yard_type": "Planetside shipyard",
		"blurb": "A dry colony world with an open-air yard. Quiet, cheap to live on, a long way from anywhere.",
	},
	{
		"id": "marrow", "name": "Marrow Belt", "yard_name": "Marrow Dock", "yard_type": "Space dock",
		"blurb": "A mining settlement among the rocks. Rough work, rough neighbours, and ore that always needs moving.",
	},
	{
		"id": "lowmoor", "name": "Lowmoor", "yard_name": "Lowmoor Cradle", "yard_type": "Moonbase yard",
		"blurb": "A small base dug into a cold moon. Few people, few questions, and a very long way from the main routes.",
	},
]

const RACES := [
	{"id": "terran", "name": "Terran", "blurb": "Born on an old, crowded homeworld. Adaptable and used to queues."},
	{"id": "belter", "name": "Belter", "blurb": "Raised in the rocks. Tall, thrifty, and comfortable with no gravity."},
	{"id": "martian", "name": "Martian", "blurb": "From the dome cities. Stubborn, practical, and good with machines."},
	{"id": "spacer", "name": "Spacer", "blurb": "Born aboard a ship and never lived anywhere else."},
]

const DIFFICULTIES := [
	{"id": "easy", "name": "Easy", "funds": 220000, "blurb": "Start with 220,000 credits."},
	{"id": "normal", "name": "Normal", "funds": 150000, "blurb": "Start with 150,000 credits."},
	{"id": "hard", "name": "Hard", "funds": 110000, "blurb": "Start with 110,000 credits. The starter ship leaves you very little."},
]


static func _find(list: Array, id: String) -> Dictionary:
	for e in list:
		if e.id == id:
			return e
	return list[0]


static func world(id: String) -> Dictionary:
	return _find(WORLDS, id)


static func race(id: String) -> Dictionary:
	return _find(RACES, id)


static func difficulty(id: String) -> Dictionary:
	return _find(DIFFICULTIES, id if id != "" else "normal")
