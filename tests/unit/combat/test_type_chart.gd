extends GdUnitTestSuite

const CHART: Dictionary = {
	"fire": {"grass": 1.2, "water": 0.8, "fire": 0.8},
	"water": {"fire": 1.2, "water": 0.8},
	"electric": {"water": 1.2, "ground": 0.2},
}

func _chart() -> CombatTypeChart:
	return CombatTypeChart.new(CHART, {"fire": "火", "grass": "草"})

func _types(names: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for n: Variant in names:
		out.append(StringName(str(n)))
	return out

func test_single_type_advantage() -> void:
	assert_float(_chart().multiplier(&"fire", _types([&"grass"]))).is_equal_approx(1.2, 0.0001)

func test_dual_type_multiplies() -> void:
	# 电打水/地面：1.2 * 0.2 = 0.24
	assert_float(_chart().multiplier(&"electric", _types([&"water", &"ground"]))).is_equal_approx(0.24, 0.0001)

func test_unknown_attack_type_is_neutral() -> void:
	assert_float(_chart().multiplier(&"neutral", _types([&"grass"]))).is_equal_approx(1.0, 0.0001)

func test_empty_defender_types_is_neutral() -> void:
	assert_float(_chart().multiplier(&"fire", _types([]))).is_equal_approx(1.0, 0.0001)

func test_display_name_is_resolved() -> void:
	assert_float(_chart().multiplier(&"火", _types([&"grass"]))).is_equal_approx(1.2, 0.0001)
