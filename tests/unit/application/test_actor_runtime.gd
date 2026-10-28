extends GdUnitTestSuite

## 按顺序吐出预设随机数；默认 1.0 表示「永不触发闪避/暴击」，让伤害数字可精确断言。
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

func _calculator() -> CombatDamageCalculator:
    return CombatDamageCalculator.new(CombatTypeChart.new({}, {}), FakeRng.new([1.0]))

func _stats(overrides: Dictionary = {}) -> Dictionary:
    var base := {
        "max_hp": 100.0,
        "attack": 10.0,
        "defense": 0.0,
        "crit_rate": 0.0,
        "dodge": 0.0,
        "types": [],
    }
    for key: Variant in overrides.keys():
        base[key] = overrides[key]
    return base

func _spec(overrides: Dictionary = {}) -> Dictionary:
    var base := {
        "species_id": "testmon",
        "faction": GameConstants.FACTION_PLAYER,
        "plane_pos": Vector2.ZERO,
        "stats": _stats(),
        "melee": {"range": 2.4, "power_ratio": 1.0, "knockback": 0.0},
    }
    for key: Variant in overrides.keys():
        base[key] = overrides[key]
    return base

func _runtime(spec: Dictionary, bus: DomainEventBus) -> ActorRuntime:
    return ActorRuntime.new(1, spec, bus, _calculator(), FakeRng.new([1.0]))

func _request(power: float) -> CombatDamageRequest:
    var req := CombatDamageRequest.new()
    req.attacker_id = 99
    req.target_id = 1
    req.power = power
    req.damage_type = &"neutral"
    req.hit_kind = &"light"
    return req

func test_spawn_initializes_contract_fields() -> void:
    var actor := _runtime(_spec(), DomainEventBus.new())
    assert_int(actor.id).is_equal(1)
    assert_str(actor.faction).is_equal(GameConstants.FACTION_PLAYER)
    assert_float(actor.stats.current_hp).is_equal_approx(100.0, 0.0001)
    assert_float(actor.energy).is_equal_approx(ActorRuntime.ENERGY_START_DEFAULT, 0.0001)
    assert_float(actor.stamina).is_equal_approx(ActorRuntime.STAMINA_MAX_DEFAULT, 0.0001)
    assert_that(actor.brain).override_failure_message("玩家 spec 没有 brain_profile 时不应创建 AI").is_null()

func test_energy_regenerates_five_per_second() -> void:
    var actor := _runtime(_spec(), DomainEventBus.new())
    actor.spend_energy(50.0)
    assert_float(actor.energy).is_equal_approx(130.0, 0.0001)
    actor.tick_action(1.0, LocoInputFrame.empty())
    assert_float(actor.energy).is_equal_approx(135.0, 0.0001)

func test_stamina_regen_waits_for_delay() -> void:
    var actor := _runtime(_spec(), DomainEventBus.new())
    actor.spend_stamina(40.0)
    assert_float(actor.stamina).is_equal_approx(60.0, 0.0001)
    actor.tick_action(0.2, LocoInputFrame.empty())
    actor.tick_action(0.19, LocoInputFrame.empty())
    assert_float(actor.stamina).override_failure_message("延迟未结束前不该回复").is_equal_approx(60.0, 0.0001)
    actor.tick_action(0.02, LocoInputFrame.empty())
    assert_float(actor.stamina).override_failure_message("延迟归零的这一帧仍不回复").is_equal_approx(60.0, 0.0001)
    actor.tick_action(0.1, LocoInputFrame.empty())
    assert_float(actor.stamina).is_equal_approx(61.4, 0.0001)

func test_skill_cast_consumes_energy_and_starts_windup() -> void:
    var skill := {
        "id": "test_bolt",
        "template": "melee",
        "power": 20.0,
        "cost": 30.0,
        "cooldown": 1.0,
        "range": 2.0,
        "windup": 0.1,
        "commit": 0.1,
        "recovery": 0.1,
    }
    var actor := _runtime(_spec({"skills": [skill]}), DomainEventBus.new())
    var cast: bool = actor.try_cast_skill(0, Vector2(2.0, 0.0))
    assert_bool(cast).is_true()
    assert_float(actor.energy).is_equal_approx(150.0, 0.0001)
    assert_int(actor.caster.phase).is_equal(SkillCastPhase.WINDUP)

func test_take_hit_deducts_hp_and_emits_damage_event() -> void:
    var bus := DomainEventBus.new()
    var damage_events: Array = []
    bus.subscribe(GameConstants.EVT_DAMAGE_APPLIED, func(e: DomainEvent) -> void:
        damage_events.append(e.payload))
    var actor := _runtime(_spec(), bus)
    var result := actor.take_hit(_request(30.0))
    assert_float(result.amount).is_equal_approx(30.0, 0.0001)
    assert_float(actor.stats.current_hp).is_equal_approx(70.0, 0.0001)
    assert_int(damage_events.size()).is_equal(1)
    assert_float(float(damage_events[0].get("amount", 0.0))).is_equal_approx(30.0, 0.0001)

func test_death_emits_actor_died_and_enters_dead_state() -> void:
    var bus := DomainEventBus.new()
    var died: Array = []
    bus.subscribe(GameConstants.EVT_ACTOR_DIED, func(e: DomainEvent) -> void:
        died.append(e.payload))
    var actor := _runtime(_spec({"stats": _stats({"max_hp": 20.0})}), bus)
    var result := actor.take_hit(_request(30.0))
    assert_bool(result.is_lethal).is_true()
    assert_float(actor.stats.current_hp).is_equal_approx(0.0, 0.0001)
    assert_int(actor.action.current_state()).is_equal(LocoActionState.DEAD)
    assert_int(died.size()).is_equal(1)
    assert_int(int(died[0].get("actor_id", -1))).is_equal(1)

func test_dash_invulnerability_negates_damage() -> void:
    var actor := _runtime(_spec(), DomainEventBus.new())
    var frame := LocoInputFrame.empty()
    frame.dash = true
    actor.tick_action(GameConstants.TICK_DELTA, frame)
    var result := actor.take_hit(_request(30.0))
    assert_float(result.amount).is_equal_approx(0.0, 0.0001)
    assert_float(actor.stats.current_hp).is_equal_approx(100.0, 0.0001)

func test_guard_reduces_damage_and_emits_guard_event() -> void:
    var bus := DomainEventBus.new()
    var guarded: Array = []
    bus.subscribe(GameConstants.EVT_ACTOR_GUARDED, func(e: DomainEvent) -> void:
        guarded.append(e.payload))
    var actor := _runtime(_spec(), bus)
    var frame := LocoInputFrame.empty()
    frame.guard = true
    actor.tick_action(GameConstants.TICK_DELTA, frame)
    assert_bool(actor.is_guarding()).is_true()
    var result := actor.take_hit(_request(40.0))
    assert_bool(result.is_guarded).is_true()
    assert_float(result.amount).is_equal_approx(10.0, 0.0001)
    assert_float(actor.stats.current_hp).is_equal_approx(90.0, 0.0001)
    assert_int(guarded.size()).is_equal(1)
