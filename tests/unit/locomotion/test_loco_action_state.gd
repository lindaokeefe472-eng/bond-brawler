extends GdUnitTestSuite

func test_names_cover_all_states() -> void:
	var states: Array[int] = [
		LocoActionState.IDLE,
		LocoActionState.RUN,
		LocoActionState.JUMP,
		LocoActionState.FALL,
		LocoActionState.LAND,
		LocoActionState.DASH,
		LocoActionState.ATTACK,
		LocoActionState.SKILL,
		LocoActionState.HURT,
		LocoActionState.DEAD,
	]
	for state: int in states:
		assert_bool(LocoActionState.is_valid(state)).override_failure_message(
			"状态 %d 缺少名字" % state).is_true()
		assert_str(LocoActionState.name_of(state)).is_not_equal(&"unknown")
	assert_int(LocoActionState.NAMES.size()).is_equal(states.size())

func test_name_of_returns_readable_names() -> void:
	assert_str(LocoActionState.name_of(LocoActionState.IDLE)).is_equal(&"idle")
	assert_str(LocoActionState.name_of(LocoActionState.DASH)).is_equal(&"dash")
	assert_str(LocoActionState.name_of(LocoActionState.DEAD)).is_equal(&"dead")

func test_from_name_round_trips() -> void:
	for state: int in LocoActionState.NAMES.keys():
		assert_int(LocoActionState.from_name(LocoActionState.name_of(state))).is_equal(state)

func test_unknown_state_and_name_are_safe() -> void:
	assert_str(LocoActionState.name_of(999)).is_equal(&"unknown")
	assert_int(LocoActionState.from_name(&"nope")).is_equal(-1)
	assert_bool(LocoActionState.is_valid(999)).is_false()
