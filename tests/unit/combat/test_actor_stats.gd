extends GdUnitTestSuite

func test_defaults_fill_missing_fields() -> void:
	var stats := CombatActorStats.new(7, {})
	assert_int(stats.actor_id).is_equal(7)
	assert_float(stats.max_hp()).is_equal_approx(100.0, 0.0001)
	assert_float(stats.current_hp).is_equal_approx(100.0, 0.0001)
	assert_float(stats.value(&"attack")).is_equal_approx(10.0, 0.0001)
	assert_float(stats.value(&"defense")).is_equal_approx(0.0, 0.0001)
	assert_float(stats.value(&"crit_rate")).is_equal_approx(0.0625, 0.0001)
	assert_float(stats.value(&"dodge")).is_equal_approx(0.0, 0.0001)

func test_battle_hp_alias_becomes_max_hp() -> void:
	# species.json 的战斗血量字段叫 battle_hp，原样传入也要能用
	var stats := CombatActorStats.new(1, {"battle_hp": 444.0, "hp": 400.0})
	assert_float(stats.max_hp()).is_equal_approx(444.0, 0.0001)

func test_flat_and_percent_formula() -> void:
	var stats := CombatActorStats.new(1, {"attack": 20.0})
	stats.add_modifier(CombatModifier.make(&"attack", 10.0, 0.5))
	# (20 + 10) * (1 + 0.5) = 45
	assert_float(stats.value(&"attack")).is_equal_approx(45.0, 0.0001)

func test_remove_modifier_restores_value() -> void:
	var stats := CombatActorStats.new(1, {"attack": 20.0})
	stats.add_modifier(CombatModifier.make(&"attack", 0.0, 1.0))
	assert_float(stats.value(&"attack")).is_equal_approx(40.0, 0.0001)
	stats.remove_modifier(&"attack")
	assert_float(stats.value(&"attack")).is_equal_approx(20.0, 0.0001)

func test_take_raw_damage_clamps_at_zero() -> void:
	var stats := CombatActorStats.new(1, {"max_hp": 20.0})
	var deducted := stats.take_raw_damage(50.0)
	assert_float(deducted).is_equal_approx(20.0, 0.0001)
	assert_float(stats.current_hp).is_equal_approx(0.0, 0.0001)
	assert_bool(stats.is_dead()).is_true()

func test_heal_capped_at_max_hp() -> void:
	var stats := CombatActorStats.new(1, {"max_hp": 100.0})
	stats.take_raw_damage(30.0)
	var healed := stats.heal(999.0)
	assert_float(healed).is_equal_approx(30.0, 0.0001)
	assert_float(stats.current_hp).is_equal_approx(100.0, 0.0001)

func test_max_hp_modifier_clamps_current_hp() -> void:
	var stats := CombatActorStats.new(1, {"max_hp": 100.0})
	stats.add_modifier(CombatModifier.make(&"max_hp", 0.0, -0.5))
	assert_float(stats.max_hp()).is_equal_approx(50.0, 0.0001)
	assert_float(stats.current_hp).is_equal_approx(50.0, 0.0001)
