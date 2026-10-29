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

## 远程角色量的是弹体射程，不能把近战那一行（纵深容差）照抄过去。
func test_ranged_characters_show_projectile_range() -> void:
	var text: String = TrainingView.format_state(_state({
		"ranged": true,
		"projectile_range": 9.0,
	}))
	assert_str(text).contains("9.00 m（弹体）")
	assert_bool(text.contains("纵深容差")).is_false()
