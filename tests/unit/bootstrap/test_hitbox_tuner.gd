## 判定盒微调器的纯逻辑：步进方向与上下限。
extends GdUnitTestSuite

func test_stepped_moves_by_configured_step() -> void:
	assert_float(HitboxTuner.stepped(&"range", 1.45, 1.0)).is_equal_approx(1.50, 0.001)
	assert_float(HitboxTuner.stepped(&"range", 1.45, -1.0)).is_equal_approx(1.40, 0.001)
	assert_float(HitboxTuner.stepped(&"margin", 0.06, 1.0)).is_equal_approx(0.07, 0.001)

func test_stepped_clamps_to_bounds() -> void:
	assert_float(HitboxTuner.stepped(&"range", 0.2, -5.0)).is_equal_approx(0.2, 0.001)
	assert_float(HitboxTuner.stepped(&"range", 6.0, 5.0)).is_equal_approx(6.0, 0.001)
	assert_float(HitboxTuner.stepped(&"margin", 0.0, -1.0)).is_equal_approx(0.0, 0.001)

func test_unknown_param_is_ignored() -> void:
	assert_float(HitboxTuner.stepped(&"nope", 1.0, 1.0)).is_equal_approx(1.0, 0.001)
