## 远程角色的普攻必须真的发弹体，而不是隔着几米用扇形结算。
##
## 回归：弓手 / 法师的攻击动作是拉弓、施法，但判定走的是近战扇形 ——
## 动作播的是射箭，画面上却什么都没有飞出去，人却隔空掉血。
extends GdUnitTestSuite

func _stats() -> Dictionary:
	return {"max_hp": 100.0, "attack": 10.0, "defense": 0.0, "crit_rate": 0.0, "dodge": 0.0, "types": []}

func _session() -> BattleSession:
	return BattleSession.new({
		"bus": DomainEventBus.new(),
		"rng": DeterministicRng.new(20261028),
		"type_chart": CombatTypeChart.new({}, {}),
	})

func _spec(plane_pos: Vector2, faction: StringName, melee: Dictionary) -> Dictionary:
	return {
		"species_id": "testmon",
		"faction": faction,
		"plane_pos": plane_pos,
		"stats": _stats(),
		"melee": melee,
		"brain_profile": null,
	}

func _ranged_melee() -> Dictionary:
	return {
		"range": 1.2,
		"attack": "projectile",
		"projectile": {"speed": 20.0, "range": 10.0, "power_ratio": 1.0, "knockback": 0.0},
	}

func _melee_only() -> Dictionary:
	return {"range": 1.2, "power_ratio": 1.0, "knockback": 0.0}

func _press_attack(session: BattleSession, actor_id: int, frames: int) -> void:
	var frame := LocoInputFrame.empty()
	frame.attack = true
	session.tick(GameConstants.TICK_DELTA, {actor_id: frame})
	for _i: int in range(frames):
		session.tick(GameConstants.TICK_DELTA, {})

## 一边按攻击一边推进，返回「这段时间里有没有生成过弹体」。
func _attack_until_projectile(session: BattleSession, actor_id: int, max_frames: int = 60) -> bool:
	var frame := LocoInputFrame.empty()
	frame.attack = true
	session.tick(GameConstants.TICK_DELTA, {actor_id: frame})
	for _i: int in range(max_frames):
		session.tick(GameConstants.TICK_DELTA, {})
		if not session.projectiles().is_empty():
			return true
	return false

func test_ranged_flag_and_config_come_from_data() -> void:
	var session := _session()
	var id: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _ranged_melee()))
	var actor: ActorRuntime = session.get_actor(id)
	assert_bool(actor.is_ranged_attack()).is_true()
	var cfg: Dictionary = actor.projectile_config()
	assert_float(float(cfg["speed"])).is_equal_approx(20.0, 0.001)
	assert_float(float(cfg["range"])).is_equal_approx(10.0, 0.001)

func test_melee_character_is_not_ranged() -> void:
	var session := _session()
	var id: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _melee_only()))
	assert_bool(session.get_actor(id).is_ranged_attack()).is_false()

func test_ranged_attack_spawns_a_projectile() -> void:
	var session := _session()
	var shooter: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _ranged_melee()))
	session.spawn_actor(_spec(Vector2(6.0, 0.0), GameConstants.FACTION_ENEMY, _melee_only()))
	assert_bool(_attack_until_projectile(session, shooter)).override_failure_message(
			"远程普攻没有生成任何弹体 —— 动作在射箭，判定却还在用近战扇形").is_true()

## 关键断言：目标在 6 m 外，近战 range 只有 1.2 m，靠弹体才打得到。
func test_ranged_attack_damages_a_distant_target() -> void:
	var session := _session()
	var shooter: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _ranged_melee()))
	var target: int = session.spawn_actor(
			_spec(Vector2(6.0, 0.0), GameConstants.FACTION_ENEMY, _melee_only()))
	var before: float = session.get_actor(target).stats.current_hp
	_press_attack(session, shooter, 90)
	assert_float(session.get_actor(target).stats.current_hp).override_failure_message(
			"6 m 外的目标没掉血，弹体要么没生成要么没飞到位").is_less(before)

## 近战角色不能凭空多出弹体，否则「远程」这条分支会污染所有角色。
func test_melee_attack_never_spawns_projectiles() -> void:
	var session := _session()
	var shooter: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _melee_only()))
	var target: int = session.spawn_actor(
			_spec(Vector2(6.0, 0.0), GameConstants.FACTION_ENEMY, _melee_only()))
	var before: float = session.get_actor(target).stats.current_hp
	_press_attack(session, shooter, 90)
	assert_int(session.projectiles().size()).is_equal(0)
	assert_float(session.get_actor(target).stats.current_hp).override_failure_message(
			"近战角色在 6 m 外打中了目标").is_equal_approx(before, 0.001)

## 弹体不能原地生效：发射当帧目标远在 6 m 外，应该还没掉血。
func test_projectile_damage_is_not_instant() -> void:
	var session := _session()
	var shooter: int = session.spawn_actor(
			_spec(Vector2.ZERO, GameConstants.FACTION_PLAYER, _ranged_melee()))
	var target: int = session.spawn_actor(
			_spec(Vector2(6.0, 0.0), GameConstants.FACTION_ENEMY, _melee_only()))
	var before: float = session.get_actor(target).stats.current_hp
	assert_bool(_attack_until_projectile(session, shooter)).is_true()
	assert_float(session.get_actor(target).stats.current_hp).override_failure_message(
			"弹体刚生成就打到了 6 m 外的目标，等于没有飞行过程").is_equal_approx(before, 0.001)
