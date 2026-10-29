## 判定窗口：整个 ACTIVE 段每帧都在判，同一目标一次挥击只吃一次。
##
## 回归：以前只在「进入 ACTIVE」那一帧结算一次。判定帧有十来帧，目标晚两帧
## 走进盒子，肉眼看到打中了却一滴血不掉 —— 这是最难查的一类手感问题。
extends GdUnitTestSuite

const STEP: float = GameConstants.TICK_DELTA
const SWING_FRAMES: int = 60

var _bus: DomainEventBus = null

func _session() -> BattleSession:
	_bus = DomainEventBus.new()
	return BattleSession.new({
		BattleSession.SERVICE_BUS: _bus,
		BattleSession.SERVICE_RNG: DeterministicRng.new(5),
	})

func _attacker_spec() -> Dictionary:
	return {
		"species_id": "attacker",
		"faction": GameConstants.FACTION_PLAYER,
		"plane_pos": Vector2.ZERO,
		"stats": {"max_hp": 200.0, "attack": 10.0, "defense": 0.0, "types": []},
		"melee": {"range": 1.5, "power_ratio": 1.0, "knockback": 0.0},
		# 判定窗口拉到 0.5 秒，测试才好在中途插入目标
		"action_profile": {"attack_windup": 0.05, "attack_active": 0.5, "attack_recovery": 0.05},
	}

func _target_spec(pos: Vector2) -> Dictionary:
	return {
		"species_id": "target",
		"faction": GameConstants.FACTION_ENEMY,
		"plane_pos": pos,
		"stats": {"max_hp": 200.0, "attack": 1.0, "defense": 0.0, "types": []},
		"brain_profile": null,
	}

func _press_attack(session: BattleSession, attacker_id: int) -> void:
	var frame := LocoInputFrame.empty()
	frame.attack = true
	session.tick(STEP, {attacker_id: frame})

func test_target_entering_mid_window_still_gets_hit() -> void:
	var session: BattleSession = _session()
	var attacker_id: int = session.spawn_actor(_attacker_spec())
	var target_id: int = session.spawn_actor(_target_spec(Vector2(6.0, 0.0)))
	var attacker: ActorRuntime = session.get_actor(attacker_id)
	var target: ActorRuntime = session.get_actor(target_id)
	var hp_before: float = target.stats.current_hp

	_press_attack(session, attacker_id)
	var guard: int = 0
	while not attacker.is_attack_active() and guard < 30:
		session.tick(STEP, {})
		guard += 1
	assert_bool(attacker.is_attack_active()).override_failure_message("没进入判定窗口").is_true()
	assert_float(target.stats.current_hp).override_failure_message(
			"目标还在射程外就掉血了").is_equal_approx(hp_before, 0.001)

	# 窗口中途走进射程。注意 plane_pos 每帧由动作机写回，
	# 直接赋值会被覆盖，必须通过动作机改。
	target.action.set_plane_pos(Vector2(1.0, 0.0))
	for _i: int in range(5):
		session.tick(STEP, {})
	assert_float(target.stats.current_hp).override_failure_message(
			"目标在判定窗口中途走进盒子却没掉血").is_less(hp_before)

func test_target_is_hit_only_once_per_swing() -> void:
	var session: BattleSession = _session()
	var hits: Array[int] = []
	_bus.subscribe(GameConstants.EVT_DAMAGE_APPLIED, func(_event: DomainEvent) -> void:
		hits.append(1))
	var attacker_id: int = session.spawn_actor(_attacker_spec())
	session.spawn_actor(_target_spec(Vector2(1.0, 0.0)))

	_press_attack(session, attacker_id)
	for _i: int in range(SWING_FRAMES):
		session.tick(STEP, {})
	assert_int(hits.size()).override_failure_message(
			"一次挥击里同一个目标被结算了 %d 次" % hits.size()).is_equal(1)

func test_no_damage_when_target_never_enters_range() -> void:
	var session: BattleSession = _session()
	var attacker_id: int = session.spawn_actor(_attacker_spec())
	var target_id: int = session.spawn_actor(_target_spec(Vector2(6.0, 0.0)))
	var target: ActorRuntime = session.get_actor(target_id)
	var hp_before: float = target.stats.current_hp
	_press_attack(session, attacker_id)
	for _i: int in range(SWING_FRAMES):
		session.tick(STEP, {})
	assert_float(target.stats.current_hp).is_equal_approx(hp_before, 0.001)
