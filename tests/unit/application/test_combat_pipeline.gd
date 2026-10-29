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

func test_resolve_basic_attack_only_hits_aligned_target() -> void:
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
	var aligned := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.5, 0.0), bus)
	var misaligned := _actor(3, GameConstants.FACTION_ENEMY, Vector2(1.5, 2.0), bus)
	var actors := {1: attacker, 2: aligned, 3: misaligned}
	var pipeline := CombatPipeline.new(bus, _rng())

	var results := pipeline.resolve_basic_attack(attacker, actors, attacker.melee_config())
	assert_int(results.size()).is_equal(1)
	assert_float(aligned.stats.current_hp).is_equal_approx(90.0, 0.0001)
	assert_float(misaligned.stats.current_hp).is_equal_approx(100.0, 0.0001)

# ---------------------------------------------------------------- 宽相候选过滤
func _pipeline() -> CombatPipeline:
	return CombatPipeline.new(DomainEventBus.new(), _rng())

func test_melee_accepts_target_inside_candidates() -> void:
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
	var target := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.0, 0.0), bus)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: target},
			attacker.melee_config(), [2])
	assert_int(results.size()).is_equal(1)

func test_melee_skips_target_outside_candidates() -> void:
	# 宽相说「没看到你」，就不结算——这是碰撞箱真正生效的地方。
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
	var target := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.0, 0.0), bus)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: target},
			attacker.melee_config(), [3])
	assert_int(results.size()).is_equal(0)
	assert_float(target.stats.current_hp).is_equal(100.0)

func test_melee_falls_back_to_full_scan_when_candidates_empty() -> void:
	# 没有宽相数据（headless / 物理未就绪）时必须退化为全量扫描，不能漏伤害。
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
	var target := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.0, 0.0), bus)
	var actors := {1: attacker, 2: target}
	assert_int(_pipeline().resolve_basic_attack(attacker, actors, attacker.melee_config(), null).size()).is_equal(1)
	assert_int(_pipeline().resolve_basic_attack(attacker, actors, attacker.melee_config(), []).size()).is_equal(1)

## 回归：敌人的硬直要长到能播完受击动画（hurt 4 帧 @12fps ≈ 0.33 秒）。
## 修之前只有 0.08~0.26 秒，实测受击动画只闪了 4 帧就没了。
func test_enemy_hitstun_covers_hurt_animation() -> void:
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, bus)
	var target := _actor(2, GameConstants.FACTION_ENEMY, Vector2(1.0, 0.0), bus)
	var cfg := {"range": GameConstants.MELEE_REACH, "power_ratio": 1.0, "knockback": 3.0, "half_arc": 0.0}
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: target}, cfg, [2])
	assert_int(results.size()).is_equal(1)
	assert_bool(target.action.is_in_hurt()).override_failure_message(
		"命中后敌人必须进入硬直").is_true()
	for i: int in 15:
		target.action.tick(GameConstants.TICK_DELTA, LocoInputFrame.empty(), true)
	assert_bool(target.action.is_in_hurt()).override_failure_message(
		"敌人硬直不足 0.25 秒，受击动画会被直接截断").is_true()

## 玩家的硬直必须短，否则被围殴时完全失去操作。
func test_player_hitstun_is_shorter_than_enemy() -> void:
	var bus := DomainEventBus.new()
	var attacker := _actor(1, GameConstants.FACTION_ENEMY, Vector2.ZERO, bus)
	var target := _actor(2, GameConstants.FACTION_PLAYER, Vector2(1.0, 0.0), bus)
	var cfg := {"range": GameConstants.MELEE_REACH, "power_ratio": 1.0, "knockback": 3.0, "half_arc": 0.0}
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: target}, cfg, [2])
	assert_int(results.size()).is_equal(1)
	for i: int in 14:
		target.action.tick(GameConstants.TICK_DELTA, LocoInputFrame.empty(), true)
	assert_bool(target.action.is_in_hurt()).override_failure_message(
		"玩家硬直超过 0.23 秒，会明显影响操作手感").is_false()
