## 三段普攻可以各有各的形态：近战扇形 / 绕身范围 / 远程弹体。
##
## 回归：以前三段共用第 1 段的参数，第二、三段只是「同一个攻击再打一次」——
## 前伸、时序、判定形状全都一样，动作播的却是不同的挥砍。
extends GdUnitTestSuite

func _stats() -> Dictionary:
	return {"max_hp": 100.0, "attack": 10.0, "defense": 0.0, "crit_rate": 0.0, "dodge": 0.0, "types": []}

func _actor(id: int, pos: Vector2, faction: StringName, melee: Dictionary = {}) -> ActorRuntime:
	var base: Dictionary = {"range": 2.0, "power_ratio": 1.0, "knockback": 0.0}
	for key: Variant in melee.keys():
		base[key] = melee[key]
	var rng := DeterministicRng.new(20261028)
	return ActorRuntime.new(id, {
		"species_id": "testmon",
		"faction": faction,
		"plane_pos": pos,
		"stats": _stats(),
		"melee": base,
		"brain_profile": null,
	}, DomainEventBus.new(), CombatDamageCalculator.new(CombatTypeChart.new({}, {}), rng), rng)

func _pipeline() -> CombatPipeline:
	return CombatPipeline.new(DomainEventBus.new(), DeterministicRng.new(20261028))

func _attack_config(kind: String, extra: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = {
		"kind": kind,
		"range": 2.0,
		"half_arc": 0.0,
		"radius": 1.8,
		"power_ratio": 1.0,
		"knockback": 0.0,
		"damage_type": "neutral",
		"hit_kind": "light",
	}
	for key: Variant in extra.keys():
		cfg[key] = extra[key]
	return cfg

## 近战的判定是扇形：身后的目标打不到。
func test_melee_does_not_hit_behind() -> void:
	var attacker := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER)
	var behind := _actor(2, Vector2(-1.0, 0.0), GameConstants.FACTION_ENEMY)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: behind},
			_attack_config("melee"))
	assert_int(results.size()).is_equal(0)
	assert_float(behind.stats.current_hp).is_equal_approx(100.0, 0.001)

## 范围攻击绕身一圈：身后的目标也要吃到。
func test_aoe_hits_behind_the_attacker() -> void:
	var attacker := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER)
	var behind := _actor(2, Vector2(-1.0, 0.0), GameConstants.FACTION_ENEMY)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: behind},
			_attack_config("aoe"))
	assert_int(results.size()).override_failure_message(
			"范围攻击没打到身后的目标").is_equal(1)
	assert_float(behind.stats.current_hp).is_less(100.0)

## 范围攻击仍然是「范围内才吃」：超出半径就没事。
func test_aoe_respects_its_radius() -> void:
	var attacker := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER)
	var far := _actor(2, Vector2(2.5, 0.0), GameConstants.FACTION_ENEMY)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: far},
			_attack_config("aoe", {"radius": 1.8}))
	assert_int(results.size()).is_equal(0)

## 范围攻击不分方向，但纵深算在距离里：斜后方太远也打不到。
func test_aoe_distance_includes_lane() -> void:
	var attacker := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER)
	var diagonal := _actor(2, Vector2(-1.4, 1.4), GameConstants.FACTION_ENEMY)
	var results := _pipeline().resolve_basic_attack(attacker, {1: attacker, 2: diagonal},
			_attack_config("aoe", {"radius": 1.8}))
	assert_int(results.size()).override_failure_message(
			"斜向距离约 1.98 m，超出 1.8 m 半径不该命中").is_equal(0)

## 逐段覆盖：reach 换算成 range，kind 逐段生效，段数由数据决定。
func test_attack_config_merges_the_step_override() -> void:
	var actor := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER, {
		"range": 2.0,
		"attacks": {
			"1": {"reach": 2.0},
			"2": {"reach": 2.6},
			"3": {"kind": "aoe", "radius": 1.7, "reach": 3.5},
		},
	})
	assert_int(actor.attack_step_count()).is_equal(3)
	assert_float(float(actor.attack_config(1)["range"])).is_equal_approx(2.0, 0.001)
	assert_float(float(actor.attack_config(2)["range"])).override_failure_message(
			"第二段的 reach 没有换算成 range").is_equal_approx(2.6, 0.001)
	assert_str(str(actor.attack_config(3)["kind"])).is_equal("aoe")
	assert_float(float(actor.attack_config(3)["radius"])).is_equal_approx(1.7, 0.001)
	assert_float(float(actor.attack_config(3)["range"])).is_equal_approx(3.5, 0.001)

## 没写 kind 的段沿用角色级 attack；角色级是 projectile 就整段远程。
func test_kind_falls_back_to_the_character_level() -> void:
	var ranged := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER, {
		"range": 2.0,
		"attack": "projectile",
		"attacks": {"1": {"reach": 2.0}, "3": {"kind": "aoe", "radius": 1.5}},
	})
	assert_str(str(ranged.attack_kind(1))).is_equal("ranged")
	assert_str(str(ranged.attack_kind(3))).override_failure_message(
			"逐段的 kind 应该盖过角色级默认").is_equal("aoe")

	var melee := _actor(2, Vector2.ZERO, GameConstants.FACTION_PLAYER, {"range": 2.0})
	assert_str(str(melee.attack_kind(1))).is_equal("melee")
	assert_int(melee.attack_step_count()).is_equal(1)

## 微调 range 必须同时改「当前这一段」的 reach：判定盒读的是 attack_config()，
## 只改基础 range 的话盒子原地不动，宽相和窄相就分家了。
func test_setting_range_updates_the_current_step_reach() -> void:
	var actor := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER, {
		"range": 2.0,
		"attacks": {"1": {"reach": 2.0}, "2": {"reach": 2.6}},
	})
	actor.set_melee_param(&"range", 3.4)
	assert_float(float(actor.melee_config()["range"])).is_equal_approx(3.4, 0.001)
	assert_float(float(actor.attack_config(1)["range"])).override_failure_message(
			"调 range 没有写进第 1 段的 reach，判定盒会停在旧尺寸").is_equal_approx(3.4, 0.001)
	# 别的段不受影响：每段的前伸是独立量出来的。
	assert_float(float(actor.attack_config(2)["range"])).is_equal_approx(2.6, 0.001)

## 存档和 data/melee.json 写的是 reach，运行时叫 range —— 两个键必须互通，
## 否则「下次启动自动套用微调」永远是空转。
func test_setting_reach_alias_updates_range() -> void:
	var actor := _actor(1, Vector2.ZERO, GameConstants.FACTION_PLAYER, {"range": 2.0})
	actor.set_melee_param(&"reach", 2.75)
	assert_float(float(actor.melee_config()["range"])).is_equal_approx(2.75, 0.001)
	assert_float(float(actor.attack_config(1)["range"])).is_equal_approx(2.75, 0.001)
