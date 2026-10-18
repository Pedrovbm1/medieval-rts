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


## Sum of flat tech bonuses "<prefix>.<class>" over an entity's classes.
static func class_add(owner: int, data: Dictionary, prefix: String) -> float:
	if owner < 0:
		return 0.0
	var total: float = 0.0
	for c: Variant in classes_of(data):
		total += GameState.modifier_add(owner, prefix + "." + String(c))
	return total


## Product of tech multipliers "<prefix>.<class>" over an entity's classes.
static func class_mult(owner: int, data: Dictionary, prefix: String) -> float:
	if owner < 0:
		return 1.0
	var total: float = 1.0
	for c: Variant in classes_of(data):
		total *= GameState.modifier(owner, prefix + "." + String(c))
	return total


## Flat attack bonus from techs (e.g. "attack.infantry": +1). Units or towers.
static func attack_bonus_of(attacker: Variant) -> int:
	return int(class_add(int(attacker.get("owner_id")), attacker.get("data"), "attack"))


## Full hit from `attacker` (a Unit or an armed Building) to `target`.
static func hit_damage(attacker: Variant, target: Variant) -> int:
	var adata: Dictionary = attacker.get("data")
	var attack: Dictionary = adata.get("combat", {})
	var tdata: Dictionary = target.get("data")
	return damage(attack, classes_of(tdata), armor_of(target), attack_bonus_of(attacker))


## Attack range including tech bonuses ("range.archer").
static func range_of(attacker: Variant) -> float:
	var adata: Dictionary = attacker.get("data")
	var base: float = float(Dictionary(adata.get("combat", {})).get("range_px", 0.0))
	if base <= 0.0:
		return float(DataLoader.rule("combat", "melee_reach_px", 10))
	return base + class_add(int(attacker.get("owner_id")), adata, "range")


## Seconds between attacks including tech bonuses ("repeat.archer" x0.9).
static func repeat_of(attacker: Variant) -> float:
	var adata: Dictionary = attacker.get("data")
	return float(Dictionary(adata.get("combat", {})).get("repeat_s", 1.5)) * class_mult(int(attacker.get("owner_id")), adata, "repeat")


## Sight radius including tech bonuses ("sight.building").
static func sight_of(entity: Variant, fallback: float) -> float:
	var data: Dictionary = entity.get("data")
	return float(data.get("sight_px", fallback)) * class_mult(int(entity.get("owner_id")), data, "sight")


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
