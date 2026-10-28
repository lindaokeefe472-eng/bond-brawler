extends GdUnitTestSuite

func _wave(count: int, delay: float, trigger: String = "immediate", species: Array = ["slime"]) -> Dictionary:
    return {"count": count, "species": species, "delay": delay, "trigger": trigger}

func test_first_wave_spawns_after_delay() -> void:
    var spawner := StageWaveSpawner.new([_wave(2, 1.0)], DomainEventBus.new())
    assert_int(spawner.current_wave()).is_equal(-1)
    spawner.tick(0.5)
    # 延迟未到：波次已开始，但还不能生成。
    assert_int(spawner.current_wave()).is_equal(0)
    assert_int(spawner.pending_spawns().size()).is_equal(0)
    spawner.tick(0.5)
    var spawns: Array[Dictionary] = spawner.pending_spawns()
    assert_int(spawns.size()).is_equal(2)
    assert_int(spawns[0]["wave"]).is_equal(0)
    assert_str(StringName(spawns[0]["species_id"])).is_equal(&"slime")
    assert_bool(spawner.is_cleared()).is_false()

func test_immediate_wave_does_not_wait_for_clear() -> void:
    var spawner := StageWaveSpawner.new([_wave(2, 0.0), _wave(1, 0.0)], null)
    spawner.tick(0.0)
    var spawns: Array[Dictionary] = spawner.pending_spawns()
    assert_int(spawns.size()).is_equal(3)
    assert_int(spawner.current_wave()).is_equal(1)
    assert_int(spawner.alive_count()).is_equal(3)

func test_clear_trigger_waits_for_previous_wave() -> void:
    var spawner := StageWaveSpawner.new([_wave(1, 0.0), _wave(1, 0.0, "clear")], null)
    spawner.tick(0.0)
    assert_int(spawner.pending_spawns().size()).is_equal(1)
    assert_int(spawner.current_wave()).is_equal(0)
    spawner.on_actor_died(1)
    spawner.tick(0.0)
    assert_int(spawner.pending_spawns().size()).is_equal(1)
    assert_int(spawner.current_wave()).is_equal(1)

func test_is_cleared_after_all_waves_spawned_and_dead() -> void:
    var spawner := StageWaveSpawner.new([_wave(2, 0.0), _wave(1, 0.0)], null)
    spawner.tick(0.0)
    spawner.pending_spawns()
    assert_bool(spawner.is_cleared()).is_false()
    spawner.on_actor_died(1)
    spawner.on_actor_died(2)
    assert_bool(spawner.is_cleared()).is_false()
    spawner.on_actor_died(3)
    assert_bool(spawner.is_cleared()).is_true()
    assert_int(spawner.alive_count()).is_equal(0)

func test_death_count_ignores_extra_callbacks() -> void:
    var spawner := StageWaveSpawner.new([_wave(1, 0.0)], null)
    spawner.tick(0.0)
    spawner.on_actor_died(1)
    spawner.on_actor_died(2)
    assert_int(spawner.alive_count()).is_equal(0)
    assert_bool(spawner.is_cleared()).is_true()

func test_wave_events_are_emitted() -> void:
    var bus := DomainEventBus.new()
    var started: Array[Dictionary] = []
    var cleared: Array[Dictionary] = []
    bus.subscribe(GameConstants.EVT_WAVE_STARTED, func(e: DomainEvent) -> void: started.append(e.payload))
    bus.subscribe(GameConstants.EVT_WAVE_CLEARED, func(e: DomainEvent) -> void: cleared.append(e.payload))
    var spawner := StageWaveSpawner.new([_wave(1, 0.0)], bus)
    spawner.tick(0.0)
    assert_int(started.size()).is_equal(1)
    assert_int(started[0]["wave"]).is_equal(0)
    assert_int(started[0]["count"]).is_equal(1)
    assert_int(cleared.size()).is_equal(0)
    spawner.on_actor_died(1)
    assert_int(cleared.size()).is_equal(1)
    assert_int(cleared[0]["wave"]).is_equal(0)

func test_empty_wave_list_is_cleared() -> void:
    var spawner := StageWaveSpawner.new([], null)
    assert_bool(spawner.is_cleared()).is_true()
    assert_int(spawner.current_wave()).is_equal(-1)
    assert_int(spawner.pending_spawns().size()).is_equal(0)

func test_spawn_lanes_stay_inside_band() -> void:
    var spawner := StageWaveSpawner.new([_wave(3, 0.0)], null)
    spawner.tick(0.0)
    var spawns: Array[Dictionary] = spawner.pending_spawns()
    assert_int(spawns.size()).is_equal(3)
    var lanes: Array[float] = []
    for spawn: Dictionary in spawns:
        var pos: Vector2 = spawn["plane_pos"]
        assert_float(pos.y).is_between(GameConstants.LANE_MIN, GameConstants.LANE_MAX)
        lanes.append(pos.y)
    # 同一波不能重叠在同一纵深上。
    assert_float(lanes[0]).is_not_equal(lanes[1])
    assert_float(lanes[1]).is_not_equal(lanes[2])

func test_species_cycles_through_wave_list() -> void:
    var spawner := StageWaveSpawner.new([_wave(3, 0.0, "immediate", ["a", "b"])], null)
    spawner.tick(0.0)
    var spawns: Array[Dictionary] = spawner.pending_spawns()
    assert_int(spawns.size()).is_equal(3)
    assert_str(StringName(spawns[0]["species_id"])).is_equal(&"a")
    assert_str(StringName(spawns[1]["species_id"])).is_equal(&"b")
    assert_str(StringName(spawns[2]["species_id"])).is_equal(&"a")

func test_pending_spawns_drains_queue() -> void:
    var spawner := StageWaveSpawner.new([_wave(1, 0.0)], null)
    spawner.tick(0.0)
    assert_int(spawner.pending_spawns().size()).is_equal(1)
    # 取出后清空，避免调用方每帧重复生成同一批敌人。
    assert_int(spawner.pending_spawns().size()).is_equal(0)
