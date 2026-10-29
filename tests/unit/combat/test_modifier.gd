extends GdUnitTestSuite

func test_stacks_capped_and_value_scales() -> void:
	var stats := CombatActorStats.new(1, {"attack": 10.0})
	var first := CombatModifier.make(&"attack", 5.0)
	first.max_stacks = 3
	stats.add_modifier(first)
	# 后续用默认构造刷新，不应把已有的 max_stacks=3 压低
	stats.add_modifier(CombatModifier.make(&"attack", 5.0))
	stats.add_modifier(CombatModifier.make(&"attack", 5.0))
	stats.add_modifier(CombatModifier.make(&"attack", 5.0))
	assert_float(stats.value(&"attack")).is_equal_approx(25.0, 0.0001)

func test_duration_expiry_ticks_down() -> void:
	var m := CombatModifier.make(&"speed", 0.0, 0.5, 1.0)
	assert_bool(m.tick(0.4)).is_false()
	assert_float(m.duration).is_equal_approx(0.6, 0.0001)
	assert_bool(m.tick(0.7)).is_true()
	assert_bool(m.is_expired()).is_true()

func test_permanent_modifier_never_expires() -> void:
	var m := CombatModifier.make(&"attack", 2.0)
	assert_bool(m.is_permanent()).is_true()
	assert_bool(m.tick(999.0)).is_false()
	assert_bool(m.is_expired()).is_false()

func test_expired_modifier_removed_from_stats() -> void:
	var stats := CombatActorStats.new(1, {"speed": 6.0})
	stats.add_modifier(CombatModifier.make(&"speed", 3.0, 0.0, 0.5))
	assert_float(stats.value(&"speed")).is_equal_approx(9.0, 0.0001)
	stats.tick(0.6)
	assert_float(stats.value(&"speed")).is_equal_approx(6.0, 0.0001)
