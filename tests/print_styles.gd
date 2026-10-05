extends SceneTree
## Prints each system's derived style (architecture, tier, role, port type, bar name).
func _initialize() -> void:
	for s in Worlds._load("systems.json").get("systems", []):
		var st := SystemStyle.for_system(String(s.id))
		print("%-22s %-10s %-17s %-17s %-22s %s | %s" % [s.id, st.architecture, st.tier, st.role, st.port_type, st.bar_name, String(st.landmark.get("name", "-"))])
	quit(0)
