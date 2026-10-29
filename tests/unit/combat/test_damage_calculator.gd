extends GdUnitTestSuite

## 按顺序吐出预设随机数，用来精确命中闪避/暴击分支。
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

const CHART: Dictionary = {
	"fire": {"grass": 1.2, "water": 0.8, "fire": 0.8},
	"water": {"fire": 1.2, "water": 0.8},
	"electric": {"water": 1.2, "ground": 0.2},
}

func _calculator(rng: IRng = null) -> CombatDamageCalculator:
	var chart := CombatTypeChart.new(CHART, {})
	return CombatDamageCalculator.new(chart, rng if rng != null else FakeRng.new())

func _stats(overrides: Dictionary = {}) -> CombatActorStats:
	var base := {
		"max_hp": 100.0,
		"attack": 20.0,
		"defense": 0.0,
		"crit_rate": 0.0,
		"crit_mult": 2.0,
		"dodge": 0.0,
		"types": [],
	}
	for key: Variant in overrides.keys():
		base[key] = overrides[key]
	return CombatActorStats.new(1, base)

func _request(power: float = 50.0, damage_type: StringName = &"neutral") -> CombatDamageRequest:
	var req := CombatDamageRequest.new()
	req.attacker_id = 1
	req.target_id = 2
	req.power = power
	req.damage_type = damage_type
	req.knockback = 4.0
	return req

func test_invulnerable_returns_zero() -> void:
	var defender := _stats()
	var result := _calculator().resolve(_request(), _stats(), defender, CombatStatusSet.new(), true, false)
	assert_float(result.amount).is_equal_approx(0.0, 0.0001)
	assert_float(defender.current_hp).is_equal_approx(100.0, 0.0001)
	assert_bool(result.is_dodged).is_false()

func test_dodge_returns_zero_damage() -> void:
	var defender := _stats({"dodge": 0.5})
	var result := _calculator(FakeRng.new([0.1])).resolve(
			_request(), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_bool(result.is_dodged).is_true()
	assert_float(result.amount).is_equal_approx(0.0, 0.0001)
	assert_float(defender.current_hp).is_equal_approx(100.0, 0.0001)

func test_guard_quarters_damage_and_skips_crit() -> void:
	var attacker := _stats({"crit_rate": 1.0})
	var rng := FakeRng.new([0.0])
	var result := _calculator(rng).resolve(
			_request(), attacker, _stats(), CombatStatusSet.new(), false, true)
	assert_bool(result.is_guarded).is_true()
	assert_bool(result.is_crit).is_false()
	assert_float(result.amount).is_equal_approx(12.5, 0.0001)
	# 格挡分支不掷暴击骰
	assert_int(rng.index).is_equal(0)

func test_crit_multiplies_damage() -> void:
	var attacker := _stats({"crit_rate": 0.5, "crit_mult": 2.0})
	var result := _calculator(FakeRng.new([0.1])).resolve(
			_request(), attacker, _stats(), CombatStatusSet.new(), false, false)
	assert_bool(result.is_crit).is_true()
	assert_float(result.amount).is_equal_approx(100.0, 0.0001)

func test_can_crit_false_skips_crit() -> void:
	var req := _request()
	req.can_crit = false
	var attacker := _stats({"crit_rate": 1.0})
	var rng := FakeRng.new([0.0])
	var result := _calculator(rng).resolve(
			req, attacker, _stats(), CombatStatusSet.new(), false, false)
	assert_bool(result.is_crit).is_false()
	assert_float(result.amount).is_equal_approx(50.0, 0.0001)
	assert_int(rng.index).is_equal(0)

func test_type_advantage_multiplies_damage() -> void:
	var defender := _stats({"types": ["grass"]})
	var result := _calculator().resolve(
			_request(50.0, &"fire"), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_float(result.amount).is_equal_approx(60.0, 0.0001)

func test_dual_type_multiplier_applies() -> void:
	# 电打水/地面：50 * (1.2 * 0.2) = 12
	var defender := _stats({"types": ["water", "ground"]})
	var result := _calculator().resolve(
			_request(50.0, &"electric"), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_float(result.amount).is_equal_approx(12.0, 0.001)

func test_defense_mitigation() -> void:
	# 100 / (100 + 100) = 0.5
	var defender := _stats({"defense": 100.0})
	var result := _calculator().resolve(
			_request(), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_float(result.amount).is_equal_approx(25.0, 0.0001)

func test_minimum_damage_is_one() -> void:
	var defender := _stats({"defense": 99999.0})
	var result := _calculator().resolve(
			_request(0.5), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_float(result.amount).is_equal_approx(1.0, 0.0001)

func test_lethal_deducts_hp_and_sets_flag() -> void:
	var defender := _stats({"max_hp": 30.0})
	var result := _calculator().resolve(
			_request(50.0), _stats(), defender, CombatStatusSet.new(), false, false)
	assert_bool(result.is_lethal).is_true()
	assert_float(defender.current_hp).is_equal_approx(0.0, 0.0001)
	assert_float(result.amount).is_equal_approx(50.0, 0.0001)

func test_knockback_uses_request_direction() -> void:
	var req := _request()
	req.knockback = 4.0
	req.knockback_direction = Vector2(1.0, 0.0)
	var result := _calculator().resolve(
			req, _stats(), _stats(), CombatStatusSet.new(), false, false)
	assert_float(result.knockback_vector.x).is_equal_approx(4.0, 0.001)
	assert_float(result.knockback_vector.y).is_equal_approx(0.0, 0.001)

func test_knockback_is_zero_without_direction() -> void:
	var result := _calculator().resolve(
			_request(), _stats(), _stats(), CombatStatusSet.new(), false, false)
	assert_float(result.knockback_vector.x).is_equal_approx(0.0, 0.001)
	assert_float(result.knockback_vector.y).is_equal_approx(0.0, 0.001)
