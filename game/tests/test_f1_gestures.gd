extends TestSuite
## F1: gesture classification rules, fed with synthetic touches and explicit times.


func _new() -> GestureClassifier:
	var g: GestureClassifier = GestureClassifier.new()
	g.configure(DataLoader.get_table("rules").get("input", {}))
	return g


func _types(events: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in events:
		out.append(String(e["type"]))
	return out


## Runs a script of [op, index, x, y, t_ms] steps and returns every emitted gesture type.
func _play(g: GestureClassifier, steps: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for s: Array in steps:
		var op: String = s[0]
		var pos: Vector2 = Vector2(s[2], s[3])
		var t: int = s[4]
		var ev: Array[Dictionary] = []
		match op:
			"down": ev = g.press(s[1], pos, t)
			"move": ev = g.move(s[1], pos, t)
			"up": ev = g.release(s[1], pos, t)
			"tick": ev = g.update(t)
		out.append_array(_types(ev))
	return out


func test_quick_tap() -> void:
	var out: PackedStringArray = _play(_new(), [["down", 0, 100, 100, 0], ["up", 0, 100, 100, 120]])
	check(out == PackedStringArray(["tap"]), "quick tap -> tap, got " + str(out))


func test_jitter_is_still_a_tap() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["move", 0, 115, 108, 60], ["move", 0, 120, 112, 90], ["up", 0, 120, 112, 150]])
	check(out == PackedStringArray(["tap"]), "finger jitter under 30 px -> tap, got " + str(out))


func test_double_tap() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["up", 0, 100, 100, 80],
		["down", 0, 110, 104, 200], ["up", 0, 110, 104, 270]])
	check(out == PackedStringArray(["tap", "double_tap"]), "two quick taps -> tap, double_tap, got " + str(out))


func test_slow_taps_are_two_taps() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["up", 0, 100, 100, 80],
		["down", 0, 100, 100, 900], ["up", 0, 100, 100, 960]])
	check(out == PackedStringArray(["tap", "tap"]), "taps 900 ms apart -> two taps, got " + str(out))


func test_far_taps_are_two_taps() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["up", 0, 100, 100, 80],
		["down", 0, 400, 300, 150], ["up", 0, 400, 300, 200]])
	check(out == PackedStringArray(["tap", "tap"]), "quick taps far apart -> two taps, got " + str(out))


func test_quick_drag_pans() -> void:
	var g: GestureClassifier = _new()
	var first: Array[Dictionary] = g.press(0, Vector2(100, 100), 0)
	var moved: Array[Dictionary] = g.move(0, Vector2(160, 100), 80)
	check(_types(moved) == PackedStringArray(["pan"]), "drag past 30 px -> pan")
	check(Vector2(moved[0]["delta"]) == Vector2(60, 0), "first pan delta includes the threshold distance (no lag)")
	var rest: PackedStringArray = _types(g.move(0, Vector2(200, 120), 120))
	rest.append_array(_types(g.release(0, Vector2(200, 120), 200)))
	check(rest == PackedStringArray(["pan", "pan_end"]) and first.is_empty(), "pan continues and ends without a tap, got " + str(rest))


func test_hold_then_drag_boxes() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["tick", 0, 0, 0, 200], ["tick", 0, 0, 0, 360],
		["move", 0, 220, 180, 420], ["up", 0, 220, 180, 500]])
	check(out == PackedStringArray(["box_armed", "box_update", "box_end"]), "hold 350 ms then drag -> box, got " + str(out))


func test_hold_without_drag_is_not_a_tap() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["tick", 0, 0, 0, 400], ["up", 0, 102, 101, 600]])
	check(out == PackedStringArray(["box_armed", "long_press"]), "long press without drag never issues a tap/order, got " + str(out))


func test_slow_release_without_tick_is_long_press() -> void:
	# The frame tick may not run between press and release (slow device): release must still respect the hold rule.
	var out: PackedStringArray = _play(_new(), [["down", 0, 100, 100, 0], ["up", 0, 100, 100, 500]])
	check(out == PackedStringArray(["box_armed", "long_press"]), "500 ms press without ticks -> long press, got " + str(out))


func test_second_finger_cancels_tap() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["down", 1, 300, 100, 40],
		["up", 1, 300, 100, 100], ["up", 0, 100, 100, 120]])
	check(not out.has("tap") and not out.has("double_tap"), "two fingers never produce a tap, got " + str(out))
	check(out.has("pinch_start") and out.has("pinch_end"), "two fingers -> pinch_start/pinch_end")


func test_second_finger_cancels_box() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["tick", 0, 0, 0, 400], ["move", 0, 180, 160, 450],
		["down", 1, 400, 300, 500], ["up", 1, 400, 300, 600], ["up", 0, 180, 160, 650]])
	check(out.has("box_cancel") and not out.has("box_end"), "a second finger cancels an armed box, got " + str(out))


func test_pinch_ratio_and_pan() -> void:
	var g: GestureClassifier = _new()
	g.press(0, Vector2(100, 100), 0)
	g.press(1, Vector2(200, 100), 10)
	var ev: Array[Dictionary] = g.move(1, Vector2(300, 100), 50)
	check(ev.size() == 1 and String(ev[0]["type"]) == "pinch", "moving a pinch finger -> pinch")
	check(is_equal_approx(float(ev[0]["ratio"]), 2.0), "fingers 100 -> 200 px apart gives ratio 2.0, got %s" % str(ev[0]["ratio"]))
	check(Vector2(ev[0]["pan"]) == Vector2(50, 0), "pinch midpoint moved 50 px -> pan (50,0)")


func test_finger_left_after_pinch_pans_not_taps() -> void:
	var out: PackedStringArray = _play(_new(), [
		["down", 0, 100, 100, 0], ["down", 1, 300, 100, 20], ["up", 1, 300, 100, 200],
		["move", 0, 140, 100, 250], ["up", 0, 140, 100, 300]])
	check(out.has("pan") and not out.has("tap"), "remaining finger after pinch pans and never taps, got " + str(out))


func test_cancel_all_resets() -> void:
	var g: GestureClassifier = _new()
	g.press(0, Vector2(10, 10), 0)
	g.update(400)
	var out: PackedStringArray = _types(g.cancel_all())
	check(out == PackedStringArray(["box_cancel"]) and g.pointer_count() == 0, "cancel_all clears an armed box")


func test_hundred_random_taps_never_misfire() -> void:
	# Property check: short presses with jitter under the threshold always classify as tap/double_tap.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1234
	var g: GestureClassifier = _new()
	var t: int = 0
	var bad: int = 0
	for i: int in 100:
		t += 1000
		var p: Vector2 = Vector2(rng.randf_range(50, 1200), rng.randf_range(50, 650))
		var ev: PackedStringArray = PackedStringArray()
		ev.append_array(_types(g.press(0, p, t)))
		var jitter: Vector2 = Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
		ev.append_array(_types(g.move(0, p + jitter, t + 60)))
		ev.append_array(_types(g.release(0, p + jitter, t + rng.randi_range(70, 260))))
		if ev != PackedStringArray(["tap"]):
			bad += 1
	check(bad == 0, "100 jittery taps -> 100 taps (%d misfires)" % bad)
