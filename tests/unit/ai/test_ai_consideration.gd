extends GdUnitTestSuite

func _bb() -> AiBlackboard:
    return AiBlackboard.new()

func test_linear_uses_raw_score() -> void:
    var c := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 0.25, 2.0)
    assert_float(c.score(_bb())).is_equal_approx(0.25, 0.0001)
    assert_float(c.weighted_score(_bb())).override_failure_message("权重应乘在整形后的分上").is_equal_approx(0.5, 0.0001)

func test_inverse_curve_flips() -> void:
    var c := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 0.25, 1.0,
            AiConsideration.ScoreCurve.INVERSE)
    assert_float(c.score(_bb())).is_equal_approx(0.75, 0.0001)

func test_threshold_curve_gates() -> void:
    var high := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 0.8, 1.0,
            AiConsideration.ScoreCurve.THRESHOLD, 0.5)
    var low := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 0.2, 1.0,
            AiConsideration.ScoreCurve.THRESHOLD, 0.5)
    assert_float(high.score(_bb())).is_equal_approx(1.0, 0.0001)
    assert_float(low.score(_bb())).is_equal_approx(0.0, 0.0001)

func test_threshold_inverted_gates_below() -> void:
    var c := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 0.2, 1.0,
            AiConsideration.ScoreCurve.THRESHOLD, 0.5, true)
    assert_float(c.score(_bb())).is_equal_approx(1.0, 0.0001)

func test_raw_score_clamped_to_unit_range() -> void:
    var c := AiConsideration.make(func(_bb_in: AiBlackboard) -> float: return 4.0, 1.0)
    assert_float(c.score(_bb())).is_equal_approx(1.0, 0.0001)

func test_invalid_callable_scores_zero() -> void:
    var c := AiConsideration.make(Callable(), 1.0)
    assert_float(c.score(_bb())).is_equal_approx(0.0, 0.0001)
