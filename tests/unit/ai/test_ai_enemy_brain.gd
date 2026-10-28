extends GdUnitTestSuite

## 测试统一关掉粘滞（stickiness=0），保证每个用例的第一次 tick 就是干净决策；
## 粘滞本身由专门的用例打开验证。
const BASE_PROFILE: Dictionary = {
    "aggression": 0.6,
    "caution": 0.3,
    "range_preference": 1.6,
    "skill_range": 3.0,
    "stickiness": 0.0,
    "sticky_margin": 0.08,
    "jitter": 0.02,
}

func _brain(overrides: Dictionary = {}) -> AiEnemyBrain:
    var profile: Dictionary = BASE_PROFILE.duplicate()
    for key: Variant in overrides:
        profile[key] = overrides[key]
    return AiEnemyBrain.new(profile, DeterministicRng.new(20261028))

func _bb(self_pos: Vector2, target_pos: Vector2, hp: float = 1.0,
        ready: Array = [], threat: float = 0.0) -> AiBlackboard:
    return AiPerception.observe(1, self_pos, hp, 2, target_pos, 1.0, false, ready, 0.0, threat)

func test_far_target_approaches() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA, _bb(Vector2(0, 0), Vector2(6, 0.2)))
    assert_str(intent.kind).override_failure_message("远距离应推进").is_equal(AiIntent.APPROACH)
    assert_float(intent.desired_pos.x).is_equal_approx(6.0 - AiEnemyBrain.APPROACH_DISTANCE, 0.001)
    assert_float(intent.desired_pos.y).override_failure_message("推进目标应纵深对齐").is_equal_approx(0.2, 0.001)

func test_far_target_approach_stops_on_self_side() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA, _bb(Vector2(8, 0), Vector2(2, 0)))
    assert_str(intent.kind).is_equal(AiIntent.APPROACH)
    assert_float(intent.desired_pos.x).override_failure_message("应从自己所在的一侧靠近").is_equal_approx(
            2.0 + AiEnemyBrain.APPROACH_DISTANCE, 0.001)

func test_low_hp_retreats() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(1.0, 0), 0.1, [true, true, true, true]))
    assert_str(intent.kind).override_failure_message("血量低于 caution 必须撤退").is_equal(AiIntent.RETREAT)

func test_retreat_moves_away_from_target() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(2, 0), Vector2(1, 0), 0.1))
    assert_str(intent.kind).is_equal(AiIntent.RETREAT)
    assert_float(intent.desired_pos.x).override_failure_message("撤退目标应远离目标").is_greater(2.0)

func test_skill_ready_in_range_casts() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(2.0, 0.3), 1.0, [false, true, false, false]))
    assert_str(intent.kind).is_equal(AiIntent.SKILL)
    assert_int(intent.skill_slot).override_failure_message("应选第一个就绪槽位").is_equal(1)

func test_skill_uses_first_ready_slot() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(2.0, 0), 1.0, [false, false, true, true]))
    assert_str(intent.kind).is_equal(AiIntent.SKILL)
    assert_int(intent.skill_slot).is_equal(2)

func test_skill_out_of_range_approaches() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(5.0, 0), 1.0, [true, true, true, true]))
    assert_str(intent.kind).override_failure_message("技能够不到时应先接近").is_equal(AiIntent.APPROACH)

func test_misaligned_target_repositions() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(1.0, 1.5)))
    assert_str(intent.kind).override_failure_message("纵深不对齐应重新走位").is_equal(AiIntent.REPOSITION)
    assert_float(intent.desired_pos.y).override_failure_message("走位目标应对齐目标纵深").is_equal_approx(1.5, 0.001)

func test_misaligned_blocks_skill() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(1.0, 1.5), 1.0, [true, false, false, false]))
    assert_str(intent.kind).override_failure_message("纵深不对齐时技能打不中，先走位").is_equal(AiIntent.REPOSITION)

func test_in_attack_range_aligned_attacks() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(1.0, 0.4)))
    assert_str(intent.kind).is_equal(AiIntent.ATTACK)

func test_guard_when_threat_is_high() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(1.0, 0), 1.0, [], 1.0))
    assert_str(intent.kind).override_failure_message("高威胁时应防御").is_equal(AiIntent.GUARD)

func test_no_target_idles() -> void:
    var brain := _brain()
    var bb := AiPerception.observe(1, Vector2.ZERO, 1.0, -1, Vector2(5, 0), 1.0, false, [], 0.0)
    var intent := brain.tick(GameConstants.TICK_DELTA, bb)
    assert_str(intent.kind).is_equal(AiIntent.IDLE)
    assert_int(intent.target_id).is_equal(-1)

func test_approach_desired_pos_clamped_to_lane() -> void:
    var brain := _brain()
    var intent := brain.tick(GameConstants.TICK_DELTA,
            _bb(Vector2(0, 0), Vector2(5, 99)))
    assert_str(intent.kind).is_equal(AiIntent.APPROACH)
    assert_float(intent.desired_pos.y).is_equal_approx(GameConstants.LANE_MAX, 0.001)

func test_stickiness_holds_current_intent() -> void:
    var brain := _brain({"stickiness": 1.0, "sticky_margin": 1.0})
    var attack_bb := _bb(Vector2(0, 0), Vector2(1.0, 0))
    var first := brain.tick(0.1, attack_bb)
    assert_str(first.kind).is_equal(AiIntent.ATTACK)
    var skill_bb := _bb(Vector2(0, 0), Vector2(1.0, 0), 1.0, [true, false, false, false])
    var held := brain.tick(0.1, skill_bb)
    assert_str(held.kind).override_failure_message("粘滞窗口内不应被略高的分数替换").is_equal(AiIntent.ATTACK)
    var after := brain.tick(1.2, skill_bb)
    assert_str(after.kind).override_failure_message("粘滞过期后应重新决策").is_equal(AiIntent.SKILL)

func test_same_seed_same_decisions() -> void:
    var profile: Dictionary = BASE_PROFILE.duplicate()
    var a := AiEnemyBrain.new(profile, DeterministicRng.new(777))
    var b := AiEnemyBrain.new(profile, DeterministicRng.new(777))
    var states: Array = [
        _bb(Vector2(0, 0), Vector2(6, 0.2)),
        _bb(Vector2(0, 0), Vector2(1.0, 0.4)),
        _bb(Vector2(0, 0), Vector2(1.0, 1.5)),
        _bb(Vector2(0, 0), Vector2(2.0, 0), 1.0, [true, false, false, false]),
    ]
    for i: int in range(states.size()):
        var ia := a.tick(0.05, states[i])
        var ib := b.tick(0.05, states[i])
        assert_str(ia.kind).override_failure_message("第 %d 帧意图应一致" % i).is_equal(ib.kind)
        assert_int(ia.skill_slot).override_failure_message("第 %d 帧槽位应一致" % i).is_equal(ib.skill_slot)
        assert_float(ia.desired_pos.x).override_failure_message("第 %d 帧目标点应一致" % i).is_equal_approx(ib.desired_pos.x, 0.0001)
        assert_float(ia.desired_pos.y).override_failure_message("第 %d 帧目标点应一致" % i).is_equal_approx(ib.desired_pos.y, 0.0001)
