extends GdUnitTestSuite

func test_default_output_is_idle_and_safe() -> void:
    var out := LocoActionOutput.new()
    assert_int(out.state).is_equal(LocoActionState.IDLE)
    assert_vector(out.plane_pos).is_equal(Vector2.ZERO)
    assert_vector(out.velocity).is_equal(Vector2.ZERO)
    assert_float(out.height).is_equal_approx(0.0, 0.0001)
    assert_float(out.vertical_velocity).is_equal_approx(0.0, 0.0001)
    assert_int(out.facing).is_equal(1)
    assert_bool(out.super_armor).is_false()
    assert_bool(out.invulnerable).is_false()
    assert_bool(out.can_be_interrupted).is_true()

func test_output_can_be_filled_by_machine() -> void:
    var m := LocoActionMachine.new()
    var out := m.tick(0.016, LocoInputFrame.empty(), true)
    assert_int(out.state).is_equal(LocoActionState.IDLE)
    assert_bool(out.can_be_interrupted).is_true()
