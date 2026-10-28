extends GdUnitTestSuite

func _def(overrides: Dictionary = {}) -> SkillDef:
    var data: Dictionary = {"id": "t", "cost": 20.0, "cd": 2.0}
    for key: Variant in overrides.keys():
        data[key] = overrides[key]
    return SkillDef.from_dict(data)

func test_cooldown_counts_down_and_becomes_ready() -> void:
    var inst := SkillInstance.new(_def())
    assert_bool(inst.is_ready()).is_true()
    inst.consume()
    assert_bool(inst.is_ready()).is_false()
    assert_float(inst.cooldown_left).is_equal_approx(2.0, 0.0001)
    assert_bool(inst.tick(1.0)).is_false()
    assert_float(inst.cooldown_left).is_equal_approx(1.0, 0.0001)
    assert_bool(inst.tick(1.0)).is_true()
    assert_bool(inst.is_ready()).is_true()
    assert_float(inst.cooldown_left).is_equal_approx(0.0, 0.0001)

func test_multi_charge_refills_one_at_a_time() -> void:
    var inst := SkillInstance.new(_def({"charges": 2.0}))
    assert_int(inst.max_charges).is_equal(2)
    assert_int(inst.charges).is_equal(2)
    inst.consume()
    inst.consume()
    assert_bool(inst.is_ready()).is_false()
    assert_int(inst.charges).is_equal(0)
    assert_bool(inst.tick(2.0)).is_true()
    assert_int(inst.charges).is_equal(1)
    assert_bool(inst.is_ready()).is_true()

func test_refund_returns_half_cooldown_and_energy() -> void:
    var inst := SkillInstance.new(_def())
    inst.consume()
    inst.refund(0.5)
    assert_float(inst.cooldown_left).is_equal_approx(1.0, 0.0001)
    assert_float(inst.refunded_energy).is_equal_approx(10.0, 0.0001)

func test_full_instance_does_not_count_down() -> void:
    var inst := SkillInstance.new(_def())
    assert_bool(inst.tick(1.0)).is_false()
    assert_int(inst.charges).is_equal(1)
    assert_float(inst.cooldown_left).is_equal_approx(0.0, 0.0001)
