extends GdUnitTestSuite

func test_consume_returns_true_within_window() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_ATTACK)
    buf.advance(0.05)
    assert_bool(buf.consume(InputBuffer.ACTION_ATTACK, 0.12)).is_true()

func test_consume_returns_false_after_window() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_ATTACK)
    buf.advance(0.13)
    assert_bool(buf.consume(InputBuffer.ACTION_ATTACK, 0.12)).is_false()

func test_consume_clears_the_press() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_JUMP)
    assert_bool(buf.consume(InputBuffer.ACTION_JUMP, 0.12)).is_true()
    assert_bool(buf.consume(InputBuffer.ACTION_JUMP, 0.12)).override_failure_message(
        "同一次按下只能被消费一次").is_false()

func test_press_overwrites_previous_timestamp() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_DASH)
    buf.advance(0.20)
    buf.press(InputBuffer.ACTION_DASH)
    # 旧记录已过期，但新按下应该让缓冲重新生效
    assert_bool(buf.is_buffered(InputBuffer.ACTION_DASH, 0.12)).is_true()

func test_last_action_tracks_most_recent_press() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_JUMP)
    buf.advance(0.01)
    buf.press(InputBuffer.ACTION_ATTACK)
    assert_str(buf.last_action).is_equal(InputBuffer.ACTION_ATTACK)
    assert_float(buf.last_time).is_equal_approx(0.01, 0.0001)

func test_clear_removes_everything() -> void:
    var buf := InputBuffer.new()
    buf.press(InputBuffer.ACTION_ATTACK)
    buf.clear()
    assert_bool(buf.is_buffered(InputBuffer.ACTION_ATTACK, 1.0)).is_false()
    assert_str(buf.last_action).is_equal(&"")
