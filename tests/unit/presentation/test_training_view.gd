## 训练场面板的文本格式化是纯函数，不需要起场景就能测。
extends GdUnitTestSuite

func _state(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"player_character": "knight",
		"dummy_character": "orc",
		"player_index": 0,
		"player_count": 20,
		"dummy_index": 1,
		"dummy_count": 20,
		"distance": 2.35,
		"lane_delta": 0.0,
		"reach": 2.04,
		"lane_tolerance": 0.85,
		"ranged": false,
		"projectile_range": 0.0,
		"attacks": [{"step": 1, "kind": "melee", "range": 2.04}],
		"would_hit": true,
		"last_hit_distance": -1.0,
		"total_damage": 0.0,
		"hit_count": 0,
	}
	for key: Variant in overrides.keys():
		base[key] = overrides[key]
	return base

func test_format_shows_characters_distance_and_reach() -> void:
	var text: String = TrainingView.format_state(_state())
	assert_str(text).contains("knight")
	assert_str(text).contains("orc")
	assert_str(text).contains("2.35 m")
	assert_str(text).contains("2.04 m")
	# 序号对玩家是一基的：0 -> 1/20
	assert_str(text).contains("1/20")
	assert_str(text).contains("2/20")

func test_verdict_follows_the_same_predicate_as_narrow_phase() -> void:
	assert_str(TrainingView.format_state(_state({"would_hit": true}))).contains("打得到")
	assert_str(TrainingView.format_state(_state({"would_hit": false}))).contains("打不到")

func test_missing_measurements_render_as_placeholder() -> void:
	var text: String = TrainingView.format_state(_state({"distance": -1.0, "last_hit_distance": -1.0}))
	assert_str(text).contains("—")
	assert_bool(text.contains("nan")).is_false()

func test_hit_stats_are_rounded_for_display() -> void:
	var text: String = TrainingView.format_state(_state({
		"last_hit_distance": 1.98,
		"total_damage": 128.6,
		"hit_count": 5,
	}))
	assert_str(text).contains("1.98 m")
	assert_str(text).contains("129")
	assert_str(text).contains("5 次")

## 三段普攻要分别标出形态：近战 / 范围 / 远程，各自的射程也要对。
func test_attack_steps_are_listed_with_their_kind() -> void:
	var text: String = TrainingView.format_state(_state({
		"attacks": [
			{"step": 1, "kind": "melee", "range": 2.04},
			{"step": 2, "kind": "melee", "range": 2.70},
			{"step": 3, "kind": "aoe", "range": 1.80},
		],
	}))
	assert_str(text).contains("1 近战 2.04 m")
	assert_str(text).contains("2 近战 2.70 m")
	assert_str(text).contains("3 范围 1.80 m")

func test_ranged_step_is_labelled_as_ranged() -> void:
	var text: String = TrainingView.format_state(_state({
		"attacks": [{"step": 1, "kind": "ranged", "range": 9.0}],
	}))
	assert_str(text).contains("1 远程 9.00 m")
