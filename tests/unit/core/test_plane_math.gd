extends GdUnitTestSuite

func test_aligned_within_tolerance() -> void:
	assert_bool(PlaneMath.is_aligned(Vector2(0, 0), Vector2(1, 0.5))).is_true()
	assert_bool(PlaneMath.is_aligned(Vector2(0, 0), Vector2(1, 2.0))).is_false()

func test_cone_rejects_behind() -> void:
	var a := Vector2(0, 0)
	assert_bool(PlaneMath.in_cone(a, 1, Vector2(-2, 0), 3.0)).is_false()
	assert_bool(PlaneMath.in_cone(a, 1, Vector2(2, 0), 3.0)).is_true()
	assert_bool(PlaneMath.in_cone(a, -1, Vector2(-2, 0), 3.0)).is_true()

func test_cone_rejects_off_lane() -> void:
	var a := Vector2(0, 0)
	assert_bool(PlaneMath.in_cone(a, 1, Vector2(1.5, 2.5), 3.0)).is_false()

func test_lane_clamp() -> void:
	var p := PlaneMath.clamp_lane(Vector2(0, 99))
	# Vector2 分量是 32 位浮点，不能用 == 比较 64 位常量
	assert_float(p.y).is_equal_approx(GameConstants.LANE_MAX, 0.001)

func test_world_roundtrip() -> void:
	var p := Vector2(3.5, -1.25)
	var w := PlaneMath.to_world(p, 1.8)
	assert_that(w).is_equal(Vector3(3.5, 1.8, -1.25))
	assert_that(PlaneMath.from_world(w)).is_equal(p)
