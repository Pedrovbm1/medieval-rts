class_name TradeTask
extends UnitTask
## A caravan trades: it walks from its market to the neutral trade post in
## the middle of the map and back, and every time it comes home it pays
## gold worth the distance (units.json trade.gold_per_px). A civil unit that
## wanders across the map: easy prey for raids, so escorting it matters.

enum Step { TO_POST, TO_MARKET }

const REACH_SLACK: float = 32.0
const MAX_MOVE_ATTEMPTS: int = 8

var market: Building = null
var post: Building = null
var step: Step = Step.TO_POST
var _attempts: int = 0
## Gold earned so far (tests, panel).
var earned: int = 0


func _init(p_unit: Unit, p_world: World, p_market: Building = null, p_post: Building = null) -> void:
	super(p_unit, p_world)
	kind = "trade"
	market = p_market
	post = p_post


## Gold for one round trip between two buildings.
static func trip_gold(unit: Unit, a: Building, b: Building) -> int:
	var cfg: Dictionary = unit.data.get("trade", {})
	var d: float = a.position.distance_to(b.position)
	if d < float(cfg.get("min_px", 0.0)):
		return 0
	return maxi(1, int(round(d * float(cfg.get("gold_per_px", 0.03)) * GameState.modifier(unit.owner_id, "trade"))))


func tick(_delta: float) -> void:
	if market == null or not is_instance_valid(market) or not world.buildings.has(market) or not market.is_complete():
		market = world.nearest_market(unit.owner_id, unit.position)
	if post == null or not is_instance_valid(post) or not world.buildings.has(post):
		post = world.nearest_trade_post(unit.position)
	if market == null or post == null:
		finish()
		return
	var goal: Building = post if step == Step.TO_POST else market
	var rect: Rect2 = goal.rect()
	if World.distance_to_rect(unit.position, rect) > unit.radius + REACH_SLACK:
		if not unit.is_moving():
			if _attempts >= MAX_MOVE_ATTEMPTS:
				finish()
				return
			_attempts += 1
			go_to(world.approach_point(rect, unit.position))
		return
	_attempts = 0
	if step == Step.TO_POST:
		step = Step.TO_MARKET
		unit.carry_type = "gold"
		unit.carry_amount = float(trip_gold(unit, market, post))
		unit.queue_redraw()
	else:
		var gold: int = trip_gold(unit, market, post)
		GameState.add_resource(unit.owner_id, "gold", gold)
		GameState.record_gathered(unit.owner_id, "gold", gold)
		earned += gold
		unit.carry_type = ""
		unit.carry_amount = 0.0
		unit.queue_redraw()
		Sfx.play_at("deposit", market.position)
		step = Step.TO_POST
