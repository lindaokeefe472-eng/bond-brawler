## 天赋应用层：加成要真的落到角色属性上，摘掉也要干净。
extends GdUnitTestSuite

func _service() -> TalentService:
	var service := TalentService.new(DomainEventBus.new())
	service.tree.add_node(TalentNode.from_dict({
		"id": "might",
		"max_rank": 2,
		"cost": 1,
		"effects": [{"kind": "stat_modifier", "stat": "attack", "flat": 10.0}],
	}))
	return service

func _actor() -> ActorRuntime:
	var session := BattleSession.new({
		BattleSession.SERVICE_BUS: DomainEventBus.new(),
		BattleSession.SERVICE_RNG: DeterministicRng.new(3),
	})
	var id: int = session.spawn_actor({
		"species_id": "tester",
		"faction": GameConstants.FACTION_PLAYER,
		"plane_pos": Vector2.ZERO,
		"stats": {"max_hp": 100.0, "attack": 10.0, "defense": 0.0, "types": []},
	})
	return session.get_actor(id)

func test_locked_talent_gives_no_bonus() -> void:
	var service: TalentService = _service()
	var actor: ActorRuntime = _actor()
	var before: float = actor.stats.value(&"attack")
	service.apply_to(actor)
	assert_float(actor.stats.value(&"attack")).is_equal_approx(before, 0.001)

func test_unlocked_talent_raises_attack() -> void:
	var service: TalentService = _service()
	var actor: ActorRuntime = _actor()
	var before: float = actor.stats.value(&"attack")
	service.grant_points(3)
	assert_bool(service.unlock(&"might")).is_true()
	service.apply_to(actor)
	assert_float(actor.stats.value(&"attack")).override_failure_message(
			"天赋加了点但属性没变").is_greater(before)

func test_clear_from_removes_bonus() -> void:
	var service: TalentService = _service()
	var actor: ActorRuntime = _actor()
	var before: float = actor.stats.value(&"attack")
	service.grant_points(3)
	service.unlock(&"might")
	service.apply_to(actor)
	service.clear_from(actor)
	assert_float(actor.stats.value(&"attack")).is_equal_approx(before, 0.001)

func test_respec_returns_points() -> void:
	var service: TalentService = _service()
	service.grant_points(2)
	service.unlock(&"might")
	assert_int(service.available_points()).is_equal(1)
	assert_int(service.respec()).is_equal(1)
	assert_int(service.available_points()).is_equal(2)
