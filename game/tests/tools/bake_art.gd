extends Node
## Bakes the code-painted atlas into res://assets/art/ (run after changing a
## painter, units/buildings/resources data or player colours):
##   godot --headless --path game tests/tools/bake_art.tscn


func _ready() -> void:
	var err: Error = PlaceholderArt.bake(ProjectSettings.globalize_path("res://assets/art"))
	print("[REALM] bake art: %s fingerprint=%s" % ["ok" if err == OK else error_string(err), PlaceholderArt.fingerprint()])
	get_tree().quit(0 if err == OK else 1)
