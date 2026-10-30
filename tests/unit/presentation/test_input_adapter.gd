extends GdUnitTestSuite

func test_diagonal_move_is_normalized() -> void:
	var move: Vector2 = InputAdapter.normalize_move(Vector2(1.0, 1.0))
	assert_float(move.length()).is_equal_approx(1.0, 0.0001)
	assert_float(move.x).is_equal_approx(sqrt(0.5), 0.0001)

func test_move_inside_deadzone_becomes_zero() -> void:
	var move: Vector2 = InputAdapter.normalize_move(Vector2(0.1, 0.05))
	assert_vector(move).is_equal(Vector2.ZERO)

func test_analog_move_keeps_its_magnitude() -> void:
	var move: Vector2 = InputAdapter.normalize_move(Vector2(0.5, 0.0))
	assert_float(move.length()).is_equal_approx(0.5, 0.0001)

func test_frame_maps_buttons_and_skill_slots() -> void:
	var frame: LocoInputFrame = InputAdapter.build_frame(
		Vector2(1.0, 0.0), true, false, true, true, [true, false, false, true])
	assert_bool(frame.jump).is_true()
	assert_bool(frame.dash).is_false()
	assert_bool(frame.attack).is_true()
	assert_bool(frame.guard).is_true()
	assert_bool(frame.skills[0]).is_true()
	assert_bool(frame.skills[1]).is_false()
	assert_bool(frame.skills[3]).is_true()

func test_frame_clamps_extra_skill_entries() -> void:
	var frame: LocoInputFrame = InputAdapter.build_frame(
		Vector2.ZERO, false, false, false, false,
		[true, true, true, true, true, true])
	assert_int(frame.skills.size()).is_equal(LocoInputFrame.SKILL_SLOTS)

func test_required_actions_are_registered() -> void:
	var required: Array = [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"jump", &"dash", &"attack", &"guard",
		&"skill_1", &"skill_2", &"skill_3", &"skill_4",
	]
	for action: StringName in required:
		assert_bool(InputMap.has_action(action)).override_failure_message(
			"缺少输入动作 %s" % action).is_true()
		assert_float(float(InputMap.action_get_events(action).size())).override_failure_message(
			"输入动作 %s 没有绑定按键" % action).is_greater(0.0)

func test_poll_without_pressed_keys_returns_empty_frame() -> void:
	var frame: LocoInputFrame = InputAdapter.new().poll()
	assert_bool(frame.has_move()).is_false()
	assert_bool(frame.jump).is_false()
	assert_bool(frame.attack).is_false()
	assert_bool(frame.guard).is_false()
	assert_int(frame.skills.size()).is_equal(LocoInputFrame.SKILL_SLOTS)

func test_physical_a_key_maps_to_move_left() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_A
	event.pressed = true
	assert_bool(InputMap.event_is_action(event, &"move_left")).is_true()

func test_gamepad_dpad_maps_to_move_right() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_DPAD_RIGHT
	event.pressed = true
	assert_bool(InputMap.event_is_action(event, &"move_right")).is_true()

## 按下沿锁存：逻辑步可能一帧跑 0 次（高刷新率）或完全不跑（顿帧 time_scale=0），
## 在逻辑步里直接读 just_pressed 会漏键。锁存必须留到被消费为止。
func test_latched_press_survives_until_polled() -> void:
	var adapter := InputAdapter.new()
	adapter.latch_edges(false, false, true, [true, false, false, false])
	var first: LocoInputFrame = adapter.poll()
	assert_bool(first.attack).override_failure_message("锁存的攻击按下沿丢了").is_true()
	assert_bool(first.skills[0]).is_true()
	# 消费后不能重复触发，否则一次按键会变成两次攻击。
	var second: LocoInputFrame = adapter.poll()
	assert_bool(second.attack).is_false()
	assert_bool(second.skills[0]).is_false()

## 两次采样之间按下多个键：都要记住，不能被后一次覆盖。
func test_multiple_latches_before_a_tick_are_coalesced() -> void:
	var adapter := InputAdapter.new()
	adapter.latch_edges(false, false, true, [])
	adapter.latch_edges(true, false, false, [])
	var frame: LocoInputFrame = adapter.poll()
	assert_bool(frame.attack).is_true()
	assert_bool(frame.jump).is_true()

## 暂停/切场景时要丢掉没消费的按下，避免恢复后补放一个旧按键。
func test_clear_drops_unconsumed_presses() -> void:
	var adapter := InputAdapter.new()
	adapter.latch_edges(true, true, true, [false, true, false, false])
	adapter.clear()
	var frame: LocoInputFrame = adapter.poll()
	assert_bool(frame.jump).is_false()
	assert_bool(frame.dash).is_false()
	assert_bool(frame.attack).is_false()
	assert_bool(frame.skills[1]).is_false()
