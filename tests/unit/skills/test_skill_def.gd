extends GdUnitTestSuite

func test_from_dict_tolerates_missing_fields() -> void:
    var def := SkillDef.from_dict({})
    assert_that(def.id).is_equal(&"")
    assert_float(def.power).is_equal_approx(0.0, 0.0001)
    assert_float(def.cost).is_equal_approx(0.0, 0.0001)
    assert_float(def.cooldown).is_equal_approx(0.0, 0.0001)
    assert_float(def.windup).is_equal_approx(0.0, 0.0001)
    assert_float(def.recovery).is_equal_approx(0.0, 0.0001)
    assert_that(def.template).is_equal(&"melee")
    assert_that(def.type).is_equal(&"neutral")
    assert_bool(def.dodgeable).is_true()
    assert_bool(def.extra is Dictionary).is_true()

func test_from_dict_maps_abbreviated_fields() -> void:
    var from_cd := SkillDef.from_dict({"id": "y", "cd": 3.5, "wind": 0.25})
    assert_float(from_cd.cooldown).is_equal_approx(3.5, 0.0001)
    assert_float(from_cd.windup).is_equal_approx(0.25, 0.0001)
    # 显式契约字段优先于数据缩写，避免两份数据冲突时行为不确定。
    var explicit := SkillDef.from_dict({"id": "x", "cd": 3.5, "cooldown": 9.0})
    assert_float(explicit.cooldown).is_equal_approx(9.0, 0.0001)

func test_from_dict_keeps_template_params_in_extra() -> void:
    var def := SkillDef.from_dict({
        "id": "ember",
        "name": "火花",
        "template": "volley",
        "volley_count": 6.0,
        "cone": 0.5,
    })
    assert_float(float(def.extra.get("volley_count", 0.0))).is_equal_approx(6.0, 0.0001)
    assert_float(float(def.extra.get("cone", 0.0))).is_equal_approx(0.5, 0.0001)
    # 已消费字段不应残留在 extra 里，否则模板参数会混入元数据。
    assert_bool(def.extra.has("name")).is_false()
    assert_bool(def.extra.has("template")).is_false()

func test_dual_type_skill_keeps_both_types() -> void:
    var def := SkillDef.from_dict({"id": "dual", "type": ["fire", "flying"], "template": "volley"})
    assert_that(def.type).is_equal(&"fire")
    var types: Array = def.extra.get("types", [])
    assert_int(types.size()).is_equal(2)
    assert_that(types[0]).is_equal(&"fire")
    assert_that(types[1]).is_equal(&"flying")

func test_from_dict_uses_id_as_name_fallback() -> void:
    var def := SkillDef.from_dict({"id": "tackle"})
    assert_str(def.name).is_equal("tackle")
