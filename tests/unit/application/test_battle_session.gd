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

var _bus: DomainEventBus = null

func before_test() -> void:
    _bus = DomainEventBus.new()

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
        "brain_profile": null,
    }
    for key: Variant in overrides.keys():
        base[key] = overrides[key]
    return base

func _player_spec(overrides: Dictionary = {}) -> Dictionary:
    return _spec(overrides)

func _enemy_spec(pos: Vector2, overrides: Dictionary = {}) -> Dictionary:
    var base := {
        "species_id": "enemymon",
        "faction": GameConstants.FACTION_ENEMY,
        "plane_pos": pos,
        "stats": _stats(),
        "melee": {"range": 2.4, "power_ratio": 1.0, "knockback": 0.0},
        "brain_profile": null,
    }
    for key: Variant in overrides.keys():
        base[key] = overrides[key]
    return base

func _session(extra: Dictionary = {}) -> BattleSession:
    var services := {
        "bus": _bus,
        "rng": FakeRng.new([1.0]),
        "type_chart": CombatTypeChart.new({}, {}),
    }
    for key: Variant in extra.keys():
        services[key] = extra[key]
    return BattleSession.new(services)

func _duel(enemy_pos: Vector2) -> BattleSession:
    var session := _session()
    session.spawn_actor(_player_spec())
    session.spawn_actor(_enemy_spec(enemy_pos))
    return session

## 按一次攻击后推进足够长的帧，让 windup -> active 的判定窗口真正走到。
func _press_attack_and_wait(session: BattleSession, actor_id: int) -> void:
    var frame := LocoInputFrame.empty()
    frame.attack = true
    session.tick(GameConstants.TICK_DELTA, {actor_id: frame})
    for _i: int in range(30):
        session.tick(GameConstants.TICK_DELTA, {})

func test_spawn_assigns_incrementing_ids() -> void:
    var session := _session()
    var first := session.spawn_actor(_player_spec())
    var second := session.spawn_actor(_enemy_spec(Vector2(2.0, 0.0)))
    assert_int(first).is_equal(1)
    assert_int(second).is_equal(2)
    assert_array(session.actor_ids()).is_equal([1, 2])
    assert_object(session.get_actor(1)).is_not_null()
    assert_that(session.get_actor(99)).is_null()

func test_player_attack_hits_aligned_target() -> void:
    var session := _duel(Vector2(1.5, 0.0))
    var enemy := session.get_actor(2)
    _press_attack_and_wait(session, 1)
    assert_float(enemy.stats.current_hp).override_failure_message(
        "同纵深目标应吃到 10 点普攻伤害").is_equal_approx(90.0, 0.001)

func test_player_attack_misses_when_lane_misaligned() -> void:
    var session := _duel(Vector2(1.5, 2.0))
    var enemy := session.get_actor(2)
    _press_attack_and_wait(session, 1)
    assert_float(enemy.stats.current_hp).override_failure_message(
        "纵深差 2.0 超过对齐容差，不该命中").is_equal_approx(100.0, 0.001)

func test_player_attack_misses_target_behind() -> void:
    var session := _duel(Vector2(-1.5, 0.0))
    var enemy := session.get_actor(2)
    _press_attack_and_wait(session, 1)
    assert_float(enemy.stats.current_hp).override_failure_message(
        "背后目标不该被正面攻击命中").is_equal_approx(100.0, 0.001)

func test_skill_input_damages_target_and_spends_energy() -> void:
    var skill := {
        "id": "test_bolt",
        "name": "测试电击",
        "type": "neutral",
        "template": "melee",
        "power": 25.0,
        "cost": 10.0,
        "cooldown": 1.0,
        "range": 3.0,
        "windup": 0.0,
        "commit": 0.05,
        "recovery": 0.0,
    }
    var session := _session()
    session.spawn_actor(_player_spec({"skills": [skill]}))
    session.spawn_actor(_enemy_spec(Vector2(1.5, 0.0)))
    var player := session.get_actor(1)
    var enemy := session.get_actor(2)

    var frame := LocoInputFrame.empty()
    frame.skills[0] = true
    session.tick(GameConstants.TICK_DELTA, {1: frame})

    assert_float(enemy.stats.current_hp).override_failure_message(
        "技能威力 25 应完整结算").is_equal_approx(75.0, 0.001)
    assert_float(player.energy).override_failure_message(
        "释放技能扣 10 点能量").is_equal_approx(170.0, 0.001)

## 零时长技能（无前摇/无 commit/无后摇）会在一次 tick 内走完整个相位，
## 激活检测必须仍然能抓到它，否则这类技能永远打不出伤害。
func test_zero_duration_skill_still_resolves() -> void:
    var skill := {
        "id": "instant",
        "template": "melee",
        "power": 20.0,
        "cost": 5.0,
        "cooldown": 1.0,
        "range": 3.0,
        "windup": 0.0,
        "commit": 0.0,
        "recovery": 0.0,
    }
    var session := _session()
    session.spawn_actor(_player_spec({"skills": [skill]}))
    session.spawn_actor(_enemy_spec(Vector2(1.5, 0.0)))
    var enemy := session.get_actor(2)

    var frame := LocoInputFrame.empty()
    frame.skills[0] = true
    session.tick(GameConstants.TICK_DELTA, {1: frame})

    assert_float(enemy.stats.current_hp).is_equal_approx(80.0, 0.001)

func test_snapshot_round_trip_preserves_actor_state() -> void:
    var skill := {
        "id": "test_bolt",
        "template": "melee",
        "power": 20.0,
        "cost": 10.0,
        "cooldown": 1.0,
        "range": 3.0,
    }
    var session := _session()
    var player_id := session.spawn_actor(_player_spec({"skills": [skill]}))
    var enemy_id := session.spawn_actor(_enemy_spec(Vector2(2.0, 0.5)))
    var player := session.get_actor(player_id)
    player.spend_energy(55.0)
    player.spend_stamina(30.0)

    var snap := session.snapshot()
    assert_bool(JSON.stringify(snap).length() > 0).override_failure_message(
        "快照必须能直接 JSON 序列化").is_true()
    var restored := _session()
    restored.restore(snap)

    assert_array(restored.actor_ids()).is_equal(session.actor_ids())
    var restored_player := restored.get_actor(player_id)
    var restored_enemy := restored.get_actor(enemy_id)
    assert_object(restored_player).is_not_null()
    assert_object(restored_enemy).is_not_null()
    assert_float(restored_player.energy).is_equal_approx(player.energy, 0.0001)
    assert_float(restored_player.stamina).is_equal_approx(player.stamina, 0.0001)
    assert_float(restored_player.stats.current_hp).is_equal_approx(player.stats.current_hp, 0.0001)
    assert_float(restored_player.plane_pos.x).is_equal_approx(player.plane_pos.x, 0.0001)
    assert_float(restored_player.plane_pos.y).is_equal_approx(player.plane_pos.y, 0.0001)
    assert_float(restored_enemy.plane_pos.y).is_equal_approx(0.5, 0.0001)
    assert_str(restored_player.faction).is_equal(GameConstants.FACTION_PLAYER)
    assert_float(restored.snapshot().get("time", -1.0)).is_equal_approx(
        snap.get("time", 0.0), 0.0001)

func test_ai_emits_intent_event_for_enemy() -> void:
    var session := _session()
    session.spawn_actor(_player_spec())
    var enemy_id := session.spawn_actor(_enemy_spec(Vector2(3.0, 0.0), {"brain_profile": {}}))
    var intents: Array = []
    _bus.subscribe(GameConstants.EVT_INTENT_EMITTED, func(e: DomainEvent) -> void:
        intents.append(e.payload))

    session.tick(GameConstants.TICK_DELTA)

    assert_float(float(intents.size())).is_greater(0.0)
    assert_int(int(intents[0].get("actor_id", -1))).is_equal(enemy_id)
    assert_object(session.intent_for(enemy_id)).is_not_null()

func test_wave_spawner_creates_enemy_actor() -> void:
    var waves := StageWaveSpawner.new([
        {"count": 1, "species": ["bulbasaur"], "spawn_x": 4.0, "lane": 0.0, "delay": 0.0},
    ], _bus)
    var session := _session({
        "wave_spawner": waves,
        "species": {"bulbasaur": {"max_hp": 80.0, "attack": 8.0}},
    })
    session.spawn_actor(_player_spec())
    session.tick(GameConstants.TICK_DELTA)

    assert_int(session.actor_ids().size()).is_equal(2)
    var enemy := session.get_actor(2)
    assert_object(enemy).is_not_null()
    assert_str(enemy.faction).is_equal(GameConstants.FACTION_ENEMY)
    assert_float(enemy.stats.max_hp()).is_equal_approx(80.0, 0.0001)

func test_wave_clears_after_wave_enemy_dies() -> void:
    var waves := StageWaveSpawner.new([
        {"count": 1, "species": ["bulbasaur"], "spawn_x": 4.0, "lane": 0.0, "delay": 0.0},
    ], _bus)
    var session := _session({
        "wave_spawner": waves,
        "species": {"bulbasaur": {"max_hp": 80.0}},
    })
    session.spawn_actor(_player_spec())
    session.tick(GameConstants.TICK_DELTA)
    var enemy := session.get_actor(2)
    assert_object(enemy).is_not_null()

    enemy.stats.take_raw_damage(999.0)
    session.tick(GameConstants.TICK_DELTA)
    assert_bool(waves.is_cleared()).override_failure_message(
        "波次敌人死亡后生成器应收到回报并清空").is_true()
