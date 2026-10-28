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
