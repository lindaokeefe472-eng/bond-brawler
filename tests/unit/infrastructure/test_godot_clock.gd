extends GdUnitTestSuite

func test_delta_defaults_to_tick_delta_before_first_sample() -> void:
	var clock := GodotClock.new()
	assert_float(clock.delta()).is_equal_approx(GameConstants.TICK_DELTA, 0.0001)

func test_now_is_non_negative_and_monotonic() -> void:
	var clock := GodotClock.new()
	var first: float = clock.now()
	assert_bool(first >= 0.0).override_failure_message("会话起点应为 0").is_true()
	OS.delay_msec(20)
	var second: float = clock.now()
	assert_bool(second > first).override_failure_message("时间必须单调递增").is_true()

func test_now_measures_elapsed_real_time() -> void:
	var clock := GodotClock.new()
	clock.now()
	OS.delay_msec(20)
	var elapsed: float = clock.now()
	assert_bool(elapsed >= 0.015).override_failure_message("20ms 延迟后 now() 至少前进 15ms").is_true()

func test_delta_reflects_interval_between_samples() -> void:
	var clock := GodotClock.new()
	clock.now()
	OS.delay_msec(20)
	clock.now()
	assert_bool(clock.delta() >= 0.015).override_failure_message("delta 应反映两次采样间隔").is_true()

func test_two_clocks_start_near_zero_independently() -> void:
	var a := GodotClock.new()
	var b := GodotClock.new()
	assert_float(a.now()).is_less(0.5)
	assert_float(b.now()).is_less(0.5)
