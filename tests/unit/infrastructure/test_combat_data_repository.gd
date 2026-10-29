extends GdUnitTestSuite

## 仓库不包含 data/（版权原因，见 README「数据与素材」）。
## 缺少数据时整组跳过，而不是报一堆红——clone 下来的人不该看到假失败。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

func _repo() -> CombatDataRepository:
	return CombatDataRepository.new(JsonDataSource.new("res://data"))

func test_type_chart_exposes_18_types() -> void:
	assert_int(_repo().type_names().size()).is_equal(18)

func test_fire_is_strong_against_grass() -> void:
	var defenders: Array[StringName] = [&"grass"]
	assert_float(_repo().type_chart().multiplier(&"fire", defenders)).is_equal_approx(1.2, 0.0001)

func test_electric_is_weak_against_ground() -> void:
	var defenders: Array[StringName] = [&"ground"]
	assert_float(_repo().type_chart().multiplier(&"electric", defenders)).is_equal_approx(0.2, 0.0001)

func test_normal_cannot_hit_ghost() -> void:
	var defenders: Array[StringName] = [&"ghost"]
	assert_float(_repo().type_chart().multiplier(&"normal", defenders)).is_equal_approx(0.2, 0.0001)

func test_dual_type_multipliers_multiply() -> void:
	var defenders: Array[StringName] = [&"grass", &"steel"]
	assert_float(_repo().type_chart().multiplier(&"fire", defenders)).is_equal_approx(1.44, 0.0001)

func test_chinese_type_names_resolve_to_same_multiplier() -> void:
	var defenders: Array[StringName] = [&"草"]
	assert_float(_repo().type_chart().multiplier(&"火", defenders)).is_equal_approx(1.2, 0.0001)

func test_actions_and_combat_params_are_exposed() -> void:
	var repo := _repo()
	assert_dict(repo.actions()).contains_keys("dodge")
	assert_dict(repo.actions()).contains_keys("damage")
	assert_dict(repo.combat_params()).contains_keys("clash")
	assert_dict(repo.combat_params()).contains_keys("hit")
