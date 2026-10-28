extends GdUnitTestSuite

func test_stat_modifier_scales_with_rank() -> void:
    var effect := TalentEffect.stat_modifier(&"attack", 5.0, 0.1)
    assert_bool(effect.is_stat_modifier()).is_true()
    assert_float(effect.scaled_flat(3)).is_equal_approx(15.0, 0.0001)
    assert_float(effect.scaled_percent(3)).is_equal_approx(0.3, 0.0001)
    assert_float(effect.scaled_flat(0)).is_equal_approx(0.0, 0.0001)

func test_to_modifier_carries_rank_as_stacks() -> void:
    var effect := TalentEffect.stat_modifier(&"attack", 5.0, 0.1)
    var modifier := effect.to_modifier(&"talent:1:power:0", &"power", 3)
    assert_object(modifier).is_not_null()
    assert_str(modifier.stat).is_equal(&"attack")
    assert_float(modifier.flat).is_equal_approx(5.0, 0.0001)
    assert_float(modifier.percent).is_equal_approx(0.1, 0.0001)
    assert_int(modifier.stacks).is_equal(3)
    assert_int(modifier.max_stacks).is_equal(3)
    assert_str(modifier.source).is_equal(&"power")
    assert_bool(modifier.is_permanent()).override_failure_message("天赋加成默认永久").is_true()
    # 战斗聚合按 stacks 乘算，3 级合计 +15。
    assert_float(modifier.effective_flat()).is_equal_approx(15.0, 0.0001)

func test_skill_unlock_effect_produces_no_modifier() -> void:
    var effect := TalentEffect.skill_unlock(&"thunder")
    assert_bool(effect.is_skill_unlock()).is_true()
    assert_str(effect.skill_id).is_equal(&"thunder")
    assert_that(effect.to_modifier(&"talent:1:a:0", &"a", 1)).is_null()

func test_from_dict_defaults_are_permanent() -> void:
    var effect := TalentEffect.from_dict({})
    assert_str(effect.kind).is_equal(TalentEffect.KIND_STAT_MODIFIER)
    assert_float(effect.flat).is_equal_approx(0.0, 0.0001)
    assert_float(effect.percent).is_equal_approx(0.0, 0.0001)
    assert_float(effect.duration).is_equal_approx(-1.0, 0.0001)
    assert_str(effect.skill_id).is_equal(&"")

func test_from_dict_reads_skill_unlock() -> void:
    var effect := TalentEffect.from_dict({"kind": "skill_unlock", "skill_id": "ice_beam"})
    assert_bool(effect.is_skill_unlock()).is_true()
    assert_str(effect.skill_id).is_equal(&"ice_beam")
