extends GdUnitTestSuite

var _events: Array[DomainEvent] = []

func _def(overrides: Dictionary = {}) -> SkillDef:
	var data: Dictionary = {
		"id": "test_skill",
		"name": "测试技能",
		"type": "normal",
		"kind": "melee",
		"template": "melee",
		"power": 10.0,
		"cost": 20.0,
		"cd": 2.0,
		"range": 2.0,
		"knockback": 1.0,
		"wind": 0.2,
		"commit": 0.1,
		"recovery": 0.3,
		"dodgeable": true,
	}
	for key: Variant in overrides.keys():
		data[key] = overrides[key]
	return SkillDef.from_dict(data)

func _make_caster(def: SkillDef) -> SkillCaster:
	_events.clear()
	var bus := DomainEventBus.new()
	bus.subscribe(&"*", func(event: DomainEvent) -> void: _events.append(event))
	var caster := SkillCaster.new(1, bus)
	caster.equip(0, SkillInstance.new(def))
	return caster

func _events_of(type: StringName) -> Array[DomainEvent]:
	var out: Array[DomainEvent] = []
	for event: DomainEvent in _events:
		if event.type == type:
			out.append(event)
	return out

func test_energy_insufficient_rejected() -> void:
	var caster := _make_caster(_def())
	assert_bool(caster.can_cast(0, 19.9)).is_false()
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 19.9)).is_false()
	assert_int(caster.phase).is_equal(SkillCastPhase.IDLE)
	assert_bool(caster.is_busy()).is_false()
	# 被拒绝时不能消耗充能，否则玩家会因为能量不足而白丢一次技能。
	assert_bool(caster.instance(0).is_ready()).is_true()
	assert_int(_events.size()).is_equal(0)
	assert_bool(caster.can_cast(0, 20.0)).is_true()

func test_phase_advances_in_order() -> void:
	var caster := _make_caster(_def())
	assert_bool(caster.begin_cast(0, Vector2(1, 0), 1, 20.0)).is_true()
	assert_int(caster.phase).is_equal(SkillCastPhase.WINDUP)
	assert_bool(caster.is_busy()).is_true()
	caster.tick(0.21)
	assert_int(caster.phase).is_equal(SkillCastPhase.ACTIVE)
	caster.tick(0.11)
	assert_int(caster.phase).is_equal(SkillCastPhase.RECOVERY)
	caster.tick(0.31)
	assert_int(caster.phase).is_equal(SkillCastPhase.IDLE)
	assert_int(caster.active_slot).is_equal(-1)
	assert_bool(caster.is_busy()).is_false()
	assert_float(caster.phase_progress()).is_equal_approx(0.0, 0.0001)

func test_cast_started_event_payload() -> void:
	var caster := _make_caster(_def())
	assert_bool(caster.begin_cast(0, Vector2(3.0, -1.0), -1, 20.0)).is_true()
	var started := _events_of(GameConstants.EVT_SKILL_CAST_STARTED)
	assert_int(started.size()).is_equal(1)
	var payload: Dictionary = started[0].payload
	assert_int(payload.get("actor_id")).is_equal(1)
	assert_int(payload.get("slot")).is_equal(0)
	assert_that(payload.get("skill_id")).is_equal(&"test_skill")
	assert_int(payload.get("facing")).is_equal(-1)
	var aim: Vector2 = payload.get("aim", Vector2.ZERO)
	assert_float(aim.x).is_equal_approx(3.0, 0.001)
	assert_float(aim.y).is_equal_approx(-1.0, 0.001)

func test_activated_event_carries_hitbox_and_effects() -> void:
	var caster := _make_caster(_def({
		"template": "projectile",
		"range": 7.5,
		"cone": 0.5,
		"speed": 12.0,
	}))
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 20.0)).is_true()
	caster.tick(0.21)
	var activated := _events_of(GameConstants.EVT_SKILL_ACTIVATED)
	assert_int(activated.size()).is_equal(1)
	var payload: Dictionary = activated[0].payload
	assert_int(payload.get("actor_id")).is_equal(1)
	assert_int(payload.get("slot")).is_equal(0)
	var hitbox: Dictionary = payload.get("hitbox", {})
	assert_float(float(hitbox.get("reach", 0.0))).is_equal_approx(7.5, 0.0001)
	assert_float(float(hitbox.get("half_arc", 0.0))).is_equal_approx(0.5, 0.0001)
	assert_float(float(hitbox.get("lane_tolerance", 0.0))).is_equal_approx(GameConstants.LANE_ALIGN_TOLERANCE, 0.0001)
	var effects: Array = payload.get("effects", [])
	assert_bool(effects.size() >= 2).is_true()
	assert_bool(effects[0] is SkillDamageEffect).is_true()
	assert_bool(effects[1] is SkillSpawnProjectileEffect).is_true()

func test_cancel_windup_refunds_half() -> void:
	var caster := _make_caster(_def())
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 20.0)).is_true()
	caster.tick(0.05)
	assert_int(caster.phase).is_equal(SkillCastPhase.WINDUP)
	caster.cancel_windup()
	assert_int(caster.phase).is_equal(SkillCastPhase.IDLE)
	assert_int(caster.active_slot).is_equal(-1)
	# 前摇期间冷却也在走：2.0 - 0.05(已流逝) - 1.0(返还一半) = 0.95
	assert_float(caster.instance(0).cooldown_left).is_equal_approx(0.95, 0.0001)
	assert_float(caster.take_refunded_energy()).is_equal_approx(10.0, 0.0001)
	# 取走后必须清零，否则会被重复加回能量池。
	assert_float(caster.take_refunded_energy()).is_equal_approx(0.0, 0.0001)
	assert_float(caster.energy_spent).is_equal_approx(20.0, 0.0001)

func test_cancel_ignored_outside_windup() -> void:
	var caster := _make_caster(_def({"wind": 0.0}))
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 20.0)).is_true()
	assert_int(caster.phase).is_equal(SkillCastPhase.ACTIVE)
	caster.cancel_windup()
	assert_int(caster.phase).is_equal(SkillCastPhase.ACTIVE)
	assert_float(caster.energy_refunded).is_equal_approx(0.0, 0.0001)
	assert_float(caster.instance(0).cooldown_left).is_equal_approx(2.0, 0.0001)

func test_interrupt_returns_idle_and_emits() -> void:
	var caster := _make_caster(_def())
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 20.0)).is_true()
	caster.interrupt(&"hitstun")
	assert_int(caster.phase).is_equal(SkillCastPhase.IDLE)
	assert_int(caster.active_slot).is_equal(-1)
	var interrupted := _events_of(GameConstants.EVT_SKILL_INTERRUPTED)
	assert_int(interrupted.size()).is_equal(1)
	assert_int(interrupted[0].payload.get("actor_id")).is_equal(1)
	assert_int(interrupted[0].payload.get("slot")).is_equal(0)
	assert_that(interrupted[0].payload.get("reason")).is_equal(&"hitstun")

func test_busy_caster_rejects_second_cast() -> void:
	var caster := _make_caster(_def())
	caster.equip(1, SkillInstance.new(_def({"id": "other_skill"})))
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 40.0)).is_true()
	assert_bool(caster.can_cast(1, 40.0)).is_false()
	assert_bool(caster.begin_cast(1, Vector2.ZERO, 1, 40.0)).is_false()

func test_cooldown_ready_event_after_ticking() -> void:
	var caster := _make_caster(_def({"cd": 1.0}))
	assert_bool(caster.begin_cast(0, Vector2.ZERO, 1, 20.0)).is_true()
	caster.tick(0.21)
	caster.tick(0.11)
	caster.tick(0.31)
	assert_int(caster.phase).is_equal(SkillCastPhase.IDLE)
	assert_int(_events_of(GameConstants.EVT_SKILL_COOLDOWN_READY).size()).is_equal(0)
	caster.tick(0.4)
	assert_int(_events_of(GameConstants.EVT_SKILL_COOLDOWN_READY).size()).is_equal(1)
	assert_bool(caster.instance(0).is_ready()).is_true()
