extends Node
## Headless test runner. Runs as a scene so autoloads exist:
##   godot --headless --path game tests/run_tests.tscn
## Optional filter: append `-- suite=test_f1` to run only matching suites.
## Exit code 0 = all passed, 1 = at least one failure.

const TESTS_DIR: String = "res://tests/"

var _failures: int = 0
var _passes: int = 0
var _failed_messages: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func record(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  " + message)
	else:
		_failures += 1
		_failed_messages.append(message)
		print("  FAIL  " + message)


func _run() -> void:
	var filter: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("suite="):
			filter = arg.substr(6)
	print("== REALM tests ==")
	for path: String in _suite_paths():
		if filter != "" and not path.get_file().contains(filter):
			continue
		var suite: TestSuite = load(path).new()
		suite.runner = self
		print("-- " + path.get_file())
		var names: PackedStringArray = PackedStringArray()
		for method: Dictionary in suite.get_method_list():
			var method_name: String = String(method["name"])
			if method_name.begins_with("test_") and not names.has(method_name):
				names.append(method_name)
		names.sort()
		for method_name: String in names:
			await suite.call(method_name)
	print("== %d passed, %d failed ==" % [_passes, _failures])
	for msg: String in _failed_messages:
		print("  failed: " + msg)
	get_tree().quit(1 if _failures > 0 else 0)


func _suite_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	for file_name: String in dir.get_files():
		var clean: String = file_name.replace(".remap", "")
		if clean.begins_with("test_") and clean.ends_with(".gd") and clean != "test_suite.gd":
			paths.append(TESTS_DIR + clean)
	paths.sort()
	return paths
