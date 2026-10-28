extends GdUnitTestSuite

## 仓库不包含 data/（版权原因，见 README「数据与素材」）。
## 缺少数据时整组跳过，而不是报一堆红——clone 下来的人不该看到假失败。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
        _skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
    pass

func _repo() -> SkillRepository:
    return SkillRepository.new(JsonDataSource.new("res://data"))

func test_loads_all_124_skills() -> void:
    assert_int(_repo().all().size()).is_equal(124)
    assert_int(_repo().size()).is_equal(124)

func test_find_known_skill_returns_parsed_definition() -> void:
    var def := _repo().find(&"aerial")
    assert_object(def).is_not_null()
    if def == null:
        return
    assert_str(str(def.id)).is_equal("aerial")
    assert_str(str(def.template)).is_equal("lunge_melee")
    assert_float(def.power).is_equal_approx(28.0, 0.0001)
    # 数据里用 cd 缩写，SkillDef 应归一化到 cooldown。
    assert_float(def.cooldown).is_equal_approx(4.0, 0.0001)

func test_find_accepts_plain_string() -> void:
    assert_object(_repo().find("aerial")).override_failure_message("String 与 StringName 应等价查表").is_not_null()

func test_find_unknown_returns_null() -> void:
    assert_that(_repo().find(&"definitely_not_a_skill")).is_null()

func test_by_template_returns_only_that_template() -> void:
    var group := _repo().by_template(&"lunge_melee")
    assert_float(float(group.size())).is_greater(0.0)
    for def: SkillDef in group:
        assert_str(str(def.template)).is_equal("lunge_melee")

func test_by_template_unknown_returns_empty() -> void:
    assert_bool(_repo().by_template(&"no_such_template").is_empty()).is_true()

func test_skill_ids_are_unique() -> void:
    var seen: Dictionary = {}
    for def: SkillDef in _repo().all():
        assert_bool(seen.has(def.id)).override_failure_message("重复技能 id %s" % def.id).is_false()
        seen[def.id] = true
