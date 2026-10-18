class_name ResourceColors
extends RefCounted
## Colour per resource id, read from rules.json "resource_colors" (HUD chips,
## carried-resource markers, minimap).

static func color(resource: String) -> Color:
	var table: Dictionary = DataLoader.get_table("rules").get("resource_colors", {})
	return Color.html(String(table.get(resource, "#ffffff")))
