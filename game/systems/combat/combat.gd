class_name Combat
extends RefCounted
## Pure combat rules (no nodes), all numbers from JSON.
##
## Damage = max(1, sum over damage types of max(0, damage[t] - armor[t])
##                 + sum of bonus[c] for every class c the target has)
## Typed damage (hack / pierce / crush) with per-type armor, plus flat
## bonuses against classes (the counter system). Never immunity: minimum 1.

const DAMAGE_TYPES: PackedStringArray = ["hack", "pierce", "crush"]


## Computes one hit. `attack` is a unit's "combat" block; modifiers are the
## attacker owner's tech bonuses (F7) already folded into `extra_damage`.
static func damage(attack: Dictionary, target_classes: Array, target_armor: Dictionary, extra_damage: int = 0) -> int:
	var total: int = 0
	var dmg: Dictionary = attack.get("damage", {})
	var extra_left: int = extra_damage
	for t: String in DAMAGE_TYPES:
		if dmg.has(t):
			# Tech bonuses add to the unit's first (main) damage type.
			total += maxi(0, int(dmg[t]) + extra_left - int(target_armor.get(t, 0)))
			extra_left = 0
	var bonus: Dictionary = attack.get("bonus", {})
	for c: Variant in target_classes:
		total += int(bonus.get(String(c), 0))
	return maxi(1, total)


## Classes of a unit or building (data "classes", falling back to "class").
static func classes_of(data: Dictionary) -> Array:
	if data.has("classes"):
		return data["classes"]
	return [String(data.get("class", ""))]


## Armor of a unit or building including flat tech bonuses for its owner.
static func armor_of(target: Object) -> Dictionary:
	var data: Dictionary = target.get("data")
	var armor: Dictionary = Dictionary(data.get("armor", {})).duplicate()
	var owner: int = int(target.get("owner_id"))
	if owner >= 0:
		for t: String in DAMAGE_TYPES:
			for c: Variant in classes_of(data):
				armor[t] = int(armor.get(t, 0)) + int(GameState.modifier_add(owner, "armor.%s.%s" % [t, String(c)]))
	return armor


## Flat attack bonus from techs for a unit (e.g. "attack.infantry": +1).
static func attack_bonus_of(unit: Unit) -> int:
	if unit.owner_id < 0:
		return 0
	var extra: int = 0
	for c: Variant in classes_of(unit.data):
		extra += int(GameState.modifier_add(unit.owner_id, "attack." + String(c)))
	return extra


## Full hit from `attacker` (a Unit) to `target` (Unit or Building).
static func hit_damage(attacker: Unit, target: Object) -> int:
	var attack: Dictionary = attacker.data.get("combat", {})
	var tdata: Dictionary = target.get("data")
	return damage(attack, classes_of(tdata), armor_of(target), attack_bonus_of(attacker))


## Edge-to-edge distance from a unit to a target (unit or building).
static func gap(unit: Unit, target: Object) -> float:
	if target is Building:
		return World.distance_to_rect(unit.position, (target as Building).rect()) - unit.radius
	var other: Unit = target as Unit
	return unit.position.distance_to(other.position) - unit.radius - other.radius


## Accepts any value: targets may be freed (destroyed buildings) while
## tasks and arrows still hold a reference to them.
static func target_alive(target: Variant) -> bool:
	if not is_instance_valid(target):
		return false
	if target is Unit:
		return not (target as Unit).is_dead and (target as Unit).is_inside_tree()
	if target is Building:
		return (target as Building).hp > 0 and (target as Building).is_inside_tree()
	return false
