extends GutTest
## Phase 0 smoke test — proves the GUT suite runs green before any real code
## exists. Replaced/augmented by the rules-engine tests in Phase 1 (PLAN.md §4).


func test_suite_runs() -> void:
	assert_true(true, "GUT suite is wired up and runnable")


func test_engine_version_is_4_x() -> void:
	var info := Engine.get_version_info()
	assert_eq(info["major"], 4, "Project targets the Godot 4.x series")
