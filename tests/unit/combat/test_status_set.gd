extends GdUnitTestSuite

func test_apply_stacks_and_refresh() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"poison", 5.0)
    status.apply(&"poison", 5.0, 2)
    assert_bool(status.has(&"poison")).is_true()
    assert_int(status.stacks(&"poison")).is_equal(3)

func test_tick_returns_expired_status() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"slow", 0.3)
    var expired := status.tick(0.4)
    assert_bool(expired.has(&"slow")).is_true()
    assert_bool(status.has(&"slow")).is_false()

func test_status_survives_partial_tick() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"slow", 0.5)
    var expired := status.tick(0.2)
    assert_bool(expired.is_empty()).is_true()
    assert_bool(status.has(&"slow")).is_true()

func test_paralyze_and_sleep_are_stunned() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"paralyze", 2.4)
    assert_bool(status.is_stunned()).is_true()
    assert_bool(status.can_act()).is_false()
    status.remove(&"paralyze")
    status.apply(&"sleep", 3.5)
    assert_bool(status.is_stunned()).is_true()
    assert_bool(status.can_act()).is_false()

## 旧版这里断言 can_act() 为 false，等于把「定身也锁动作」的 bug 写进了测试。
## 正确语义：root 只把移速压到 0，动作不受限。
func test_root_zeroes_speed_but_keeps_actions() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"root", 1.2)
    assert_bool(status.is_stunned()).is_false()
    assert_float(status.speed_multiplier()).is_equal_approx(0.0, 0.0001)
    assert_bool(status.can_act()).is_true()

func test_slow_reduces_speed() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"slow", 2.5)
    assert_float(status.speed_multiplier()).is_equal_approx(0.6, 0.0001)
    assert_bool(status.can_act()).is_true()

func test_default_duration_from_table() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"wet", 0.0)
    assert_bool(status.tick(6.9).is_empty()).is_true()
    assert_bool(status.has(&"wet")).is_true()
    assert_bool(status.tick(0.2).has(&"wet")).is_true()

func test_constructor_overrides_duration() -> void:
    var status := CombatStatusSet.new({&"burn": 1.0})
    status.apply(&"burn", 0.0)
    assert_bool(status.tick(0.9).is_empty()).is_true()
    assert_bool(status.tick(0.2).has(&"burn")).is_true()

# ---------------------------------------------------------------- 控制效果边界
func test_root_does_not_block_actions() -> void:
    # 回归：root 曾经被算进 can_act()，导致被草系技能定住时既不能动也不能打。
    var status := CombatStatusSet.new()
    status.apply(&"root", 1.2)
    assert_bool(status.has(&"root")).is_true()
    assert_float(status.speed_multiplier()).is_equal_approx(0.0, 0.0001)
    assert_bool(status.can_act()).override_failure_message(
        "root 只该锁移动，不该锁动作").is_true()

func test_paralyze_still_blocks_actions() -> void:
    var status := CombatStatusSet.new()
    status.apply(&"paralyze", 2.4)
    assert_bool(status.can_act()).is_false()

func test_stacks_are_capped() -> void:
    # 回归：层数无上限，三个敌人围殴几秒就能把状态叠到不可收拾。
    var status := CombatStatusSet.new()
    for i: int in 20:
        status.apply(&"burn", 5.0)
    assert_int(status.stacks(&"burn")).is_equal(CombatStatusSet.MAX_STACKS)
