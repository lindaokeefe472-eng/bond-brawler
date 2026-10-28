extends GdUnitTestSuite

class _StatsStub extends RefCounted:
    var hp_max: float = 100.0

    func max_hp() -> float:
        return hp_max

var _events: Array[DomainEvent] = []

func _ctx(targets: Array[int]) -> SkillEffectContext:
    _events.clear()
    var stats := _StatsStub.new()
    return SkillEffectContext.new(
        1,
        targets,
        Vector2(2.0, 0.0),
        1,
        DeterministicRng.new(7),
        func(actor_id: int) -> Variant:
            if actor_id == 1:
                return stats
            return null,
        func(event: DomainEvent) -> void:
            _events.append(event))

func test_damage_effect_emits_request_per_target() -> void:
    var targets: Array[int] = [2, 3]
    var ctx := _ctx(targets)
    SkillDamageEffect.new(15.0, &"fire", 2.0).apply(ctx)
    assert_int(_events.size()).is_equal(2)
    assert_that(_events[0].type).is_equal(GameConstants.EVT_DAMAGE_APPLIED)
    assert_int(_events[0].payload.get("attacker_id")).is_equal(1)
    assert_int(_events[0].payload.get("target_id")).is_equal(2)
    assert_float(float(_events[0].payload.get("power", 0.0))).is_equal_approx(15.0, 0.0001)
    assert_that(_events[0].payload.get("damage_type")).is_equal(&"fire")
    assert_int(_events[1].payload.get("target_id")).is_equal(3)

func test_status_effect_respects_chance() -> void:
    var targets: Array[int] = [2]
    SkillStatusEffect.new(&"burn", 3.0, 1, 1.0).apply(_ctx(targets))
    assert_int(_events.size()).is_equal(1)
    assert_that(_events[0].payload.get("status")).is_equal(&"burn")
    assert_int(_events[0].payload.get("actor_id")).is_equal(2)
    # 概率 0 时绝不施加，避免「必然触发」的测试数据掩盖随机源问题。
    SkillStatusEffect.new(&"burn", 3.0, 1, 0.0).apply(_ctx(targets))
    assert_int(_events.size()).is_equal(0)

func test_heal_effect_uses_max_hp_ratio() -> void:
    var targets: Array[int] = [1]
    SkillHealEffect.new(10.0, 0.5).apply(_ctx(targets))
    assert_int(_events.size()).is_equal(1)
    assert_that(_events[0].type).is_equal(SkillEffect.EVT_HEALED)
    assert_int(_events[0].payload.get("actor_id")).is_equal(1)
    assert_float(float(_events[0].payload.get("amount", 0.0))).is_equal_approx(60.0, 0.0001)

func test_buff_projectile_and_knockback_effects_emit() -> void:
    var targets: Array[int] = [2]
    var ctx := _ctx(targets)
    SkillBuffEffect.new(&"speed", 0.0, 0.25, 4.0, 2, &"haste").apply(ctx)
    SkillSpawnProjectileEffect.new(3, 18.0, 0.1, 5.0, &"water", false, 1.0, 0.05).apply(ctx)
    SkillKnockbackEffect.new(3.5).apply(ctx)
    assert_int(_events.size()).is_equal(3)
    assert_that(_events[0].type).is_equal(SkillEffect.EVT_BUFF_APPLIED)
    assert_float(float(_events[0].payload.get("percent", 0.0))).is_equal_approx(0.25, 0.0001)
    assert_that(_events[1].type).is_equal(SkillEffect.EVT_PROJECTILE_SPAWNED)
    assert_int(_events[1].payload.get("count")).is_equal(3)
    assert_int(_events[1].payload.get("owner_id")).is_equal(1)
    assert_that(_events[2].type).is_equal(SkillEffect.EVT_KNOCKBACK)
    assert_int(_events[2].payload.get("target_id")).is_equal(2)
    assert_float(float(_events[2].payload.get("strength", 0.0))).is_equal_approx(3.5, 0.0001)
