class_name TestSuite
extends RefCounted
## Base class for test suites. Every method whose name starts with "test_"
## runs in order. Methods may `await` (e.g. to let a scene tick).

var runner: Node


func check(condition: bool, message: String) -> void:
	runner.record(condition, message)


## Adds a node to the running tree (for scene-level tests).
func add_to_tree(node: Node) -> void:
	runner.add_child(node)


func frames(count: int) -> void:
	for i: int in count:
		await runner.get_tree().process_frame


func physics_frames(count: int) -> void:
	for i: int in count:
		await runner.get_tree().physics_frame
