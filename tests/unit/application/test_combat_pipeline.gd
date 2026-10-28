extends GdUnitTestSuite

## 按顺序吐出预设随机数；默认 1.0 表示「永不触发闪避/暴击」。
class FakeRng extends IRng:
    var values: Array[float] = []
    var index: int = 0

    func _init(p_values: Array = []) -> void:
        values.assign(p_values)

    func next_float() -> float:
        if values.is_empty():
            return 1.0
        var value: float = values[index % values.size()]
        index += 1
        return value

func _rng() -> IRng:
    return FakeRng.new([1.0])

func _calculator() -> CombatDamageCalculator:
    return CombatDamageCalculator.new(CombatTypeChart.new({}, {}), _rng())

func _actor(actor_id: int, faction: StringName, pos: Vector2,
        bus: DomainEventBus) -> ActorRuntime:
    var spec := {
        "species_id": "testmon",
        "faction": faction,
        "plane_pos": pos,
        "stats": {
            "max_hp": 100.0,
            "attack": 10.0,
            "defense": 0.0,
            "crit_rate": 0.0,
            "dodge": 0.0,
        },
        "melee": {"range": 2.4, "power_ratio": 1.0, "knockback": 0.0},
    }
    return ActorRuntime.new(actor_id, spec, bus, _calculator(), _rng())

func test_skill_targets_ignores_same_faction() -> void:
    var bus := DomainEventBus.new()
    var caster := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
    var ally := _actor(2, GameConstants.FACTION_PLAYER, Vector2(1.5, 0.0), bus)
    var enemy := _actor(3, GameConstants.FACTION_ENEMY, Vector2(1.5, 0.0), bus)
    var actors := {1: caster, 2: ally, 3: enemy}
    var pipeline := CombatPipeline.new(bus, _rng())
    var hitbox := {"reach": 3.0, "half_arc": 0.0, "lane_tolerance": 0.85}

    var targets := pipeline.skill_targets(1, Vector2.ZERO, 1, hitbox, actors)
    assert_array(targets).is_equal([3])

func test_skill_targets_filters_lane_tolerance() -> void:
    var bus := DomainEventBus.new()
    var caster := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
    var near := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.5, 0.5), bus)
    var far := _actor(3, GameConstants.FACTION_ENEMY, Vector2(1.5, 1.5), bus)
    var actors := {1: caster, 2: near, 3: far}
    var pipeline := CombatPipeline.new(bus, _rng())
    var hitbox := {"reach": 3.0, "half_arc": 0.0, "lane_tolerance": 0.85}

    var targets := pipeline.skill_targets(1, Vector2.ZERO, 1, hitbox, actors)
    assert_array(targets).is_equal([2])

func test_resolve_melee_only_hits_aligned_target() -> void:
    var bus := DomainEventBus.new()
    var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
    var aligned := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.5, 0.0), bus)
    var misaligned := _actor(3, GameConstants.FACTION_ENEMY, Vector2(1.5, 2.0), bus)
    var actors := {1: attacker, 2: aligned, 3: misaligned}
    var pipeline := CombatPipeline.new(bus, _rng())

    var results := pipeline.resolve_melee(attacker, actors, attacker.melee_config())
    assert_int(results.size()).is_equal(1)
    assert_float(aligned.stats.current_hp).is_equal_approx(90.0, 0.0001)
    assert_float(misaligned.stats.current_hp).is_equal_approx(100.0, 0.0001)
