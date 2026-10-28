extends GdUnitTestSuite

func test_derives_distance_and_alignment() -> void:
    var bb := AiPerception.observe(1, Vector2(0, 0), 0.5, 2, Vector2(3, 0.5), 0.8, true,
            [true, false], 1.5, 0.4)
    assert_float(bb.distance).is_equal_approx(PlaneMath.distance(Vector2(0, 0), Vector2(3, 0.5)), 0.0001)
    assert_bool(bb.aligned).is_true()
    assert_float(bb.self_hp_ratio).is_equal_approx(0.5, 0.0001)
    assert_float(bb.target_hp_ratio).is_equal_approx(0.8, 0.0001)
    assert_bool(bb.target_guarding).is_true()
    assert_float(bb.threat).is_equal_approx(0.4, 0.0001)
    assert_float(bb.time).is_equal_approx(1.5, 0.0001)
    assert_int(bb.skill_ready.size()).is_equal(2)

func test_not_aligned_when_lane_gap_exceeds_tolerance() -> void:
    var bb := AiPerception.observe(1, Vector2(0, 0), 1.0, 2, Vector2(3, 2.0), 1.0, false, [], 0.0)
    assert_bool(bb.aligned).is_false()

func test_hp_ratios_are_clamped() -> void:
    var bb := AiPerception.observe(1, Vector2.ZERO, 1.5, 2, Vector2(1, 0), -0.2, false, [], 0.0)
    assert_float(bb.self_hp_ratio).is_equal_approx(1.0, 0.0001)
    assert_float(bb.target_hp_ratio).is_equal_approx(0.0, 0.0001)

func test_first_ready_slot_returns_first_true() -> void:
    var bb := AiPerception.observe(1, Vector2.ZERO, 1.0, 2, Vector2(1, 0), 1.0, false,
            [false, true, true], 0.0)
    assert_int(AiPerception.first_ready_slot(bb)).is_equal(1)

func test_first_ready_slot_none() -> void:
    var bb := AiPerception.observe(1, Vector2.ZERO, 1.0, 2, Vector2(1, 0), 1.0, false, [], 0.0)
    assert_int(AiPerception.first_ready_slot(bb)).is_equal(-1)

func test_from_observation_accepts_facing_key() -> void:
    var bb := AiPerception.from_observation({
        "self_id": 7,
        "self_pos": Vector2(0, 0),
        "self_hp_ratio": 0.6,
        "self_facing": -1,
        "target_id": 9,
        "target_pos": Vector2(2, 1.0),
        "target_hp_ratio": 0.4,
        "target_guarding": true,
        "skill_ready": [true, false],
        "threat": 0.2,
        "time": 3.0,
    })
    assert_int(bb.self_id).is_equal(7)
    assert_int(bb.target_id).is_equal(9)
    assert_int(bb.skill_ready.size()).is_equal(2)
    assert_float(bb.distance).is_equal_approx(PlaneMath.distance(Vector2(0, 0), Vector2(2, 1.0)), 0.0001)
    assert_bool(bb.aligned).is_false()
