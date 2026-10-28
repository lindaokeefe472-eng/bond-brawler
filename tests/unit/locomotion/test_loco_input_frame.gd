extends GdUnitTestSuite

func test_empty_frame_has_zero_move_and_four_skill_slots() -> void:
    var f := LocoInputFrame.empty()
    assert_vector(f.move).is_equal(Vector2.ZERO)
    assert_bool(f.jump).is_false()
    assert_bool(f.dash).is_false()
    assert_bool(f.attack).is_false()
    assert_bool(f.guard).is_false()
    assert_int(f.skills.size()).is_equal(LocoInputFrame.SKILL_SLOTS)
    assert_array(f.skills).is_equal([false, false, false, false])

func test_clamped_move_limits_components() -> void:
    var f := LocoInputFrame.empty()
    f.move = Vector2(3.0, -4.0)
    var clamped := f.clamped_move()
    # Vector2 分量是 32 位浮点，用 almost_eq 比较
    assert_float(clamped.x).is_equal_approx(LocoInputFrame.MOVE_MAX, 0.0001)
    assert_float(clamped.y).is_equal_approx(LocoInputFrame.MOVE_MIN, 0.0001)

func test_has_move_detects_depth_input() -> void:
    var f := LocoInputFrame.empty()
    f.move = Vector2(0.0, 1.0)
    assert_bool(f.has_move()).override_failure_message("纵深方向也算移动，否则侧向走位会播待机").is_true()

func test_has_move_false_for_deadzone_noise() -> void:
    var f := LocoInputFrame.empty()
    f.move = Vector2(0.001, 0.0)
    assert_bool(f.has_move()).override_failure_message("摇杆漂移不应把 IDLE 顶成 RUN").is_false()
