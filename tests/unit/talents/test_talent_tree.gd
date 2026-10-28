extends GdUnitTestSuite

var bus: DomainEventBus
var tree: TalentTree

func before_test() -> void:
    bus = DomainEventBus.new()
    tree = TalentTree.new(bus)

func _make_node(id: StringName, prereqs: Array = [], cost: int = 1, max_rank: int = 1) -> TalentNode:
    var node := TalentNode.new()
    node.id = id
    node.name = String(id)
    node.cost = cost
    node.max_rank = max_rank
    for prereq: Variant in prereqs:
        node.prerequisites.append(StringName(str(prereq)))
    return node

# ------------------------------------------------------------------ 前置与点数
func test_unlock_rejected_when_prerequisite_inactive() -> void:
    tree.add_node(_make_node(&"power"))
    tree.add_node(_make_node(&"crit", [&"power"]))
    tree.grant_points(10)
    assert_bool(tree.can_unlock(&"crit")).is_false()
    assert_bool(tree.unlock(&"crit")).is_false()
    assert_int(tree.available_points()).override_failure_message("失败不应扣点").is_equal(10)
    assert_int(tree.state_of(&"crit")).is_equal(TalentNode.LOCKED)

func test_unlock_requires_every_prerequisite() -> void:
    tree.add_node(_make_node(&"power"))
    tree.add_node(_make_node(&"speed"))
    tree.add_node(_make_node(&"crit", [&"power", &"speed"]))
    tree.grant_points(10)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.can_unlock(&"crit")).override_failure_message("只满足一个前置时仍应拒绝").is_false()
    assert_bool(tree.unlock(&"speed")).is_true()
    assert_bool(tree.can_unlock(&"crit")).is_true()

func test_unlock_rejected_when_points_insufficient() -> void:
    tree.add_node(_make_node(&"power", [], 3))
    tree.grant_points(2)
    assert_bool(tree.can_unlock(&"power")).is_false()
    assert_bool(tree.unlock(&"power")).is_false()
    assert_int(tree.find_node(&"power").rank).is_equal(0)
    assert_int(tree.available_points()).is_equal(2)
    assert_int(tree.state_of(&"power")).override_failure_message("前置满足但点数不够，仍显示可解锁").is_equal(TalentNode.AVAILABLE)

# ------------------------------------------------------------------ 解锁状态
func test_unlock_activates_node_and_changes_state() -> void:
    tree.add_node(_make_node(&"power"))
    tree.grant_points(1)
    assert_int(tree.state_of(&"power")).is_equal(TalentNode.AVAILABLE)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_int(tree.state_of(&"power")).is_equal(TalentNode.ACTIVE)
    assert_int(tree.find_node(&"power").rank).is_equal(1)

func test_unlock_consumes_points_and_emits_event() -> void:
    var events: Array = []
    bus.subscribe(GameConstants.EVT_TALENT_UNLOCKED, func(event: DomainEvent) -> void: events.append(event))
    tree.add_node(_make_node(&"power", [], 2))
    tree.grant_points(5)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_int(tree.available_points()).is_equal(3)
    assert_int(events.size()).is_equal(1)
    assert_str(events[0].get_value(&"talent_id")).is_equal(&"power")
    assert_int(events[0].get_value(&"rank")).is_equal(1)
    assert_int(events[0].get_value(&"points_left")).is_equal(3)

func test_rank_up_stops_at_max_rank() -> void:
    tree.add_node(_make_node(&"power", [], 1, 2))
    tree.grant_points(10)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.can_unlock(&"power")).is_false()
    assert_bool(tree.unlock(&"power")).is_false()
    assert_int(tree.find_node(&"power").rank).is_equal(2)
    assert_int(tree.available_points()).is_equal(8)

# ------------------------------------------------------------------ DAG 校验
func test_cycle_is_rejected() -> void:
    tree.add_node(_make_node(&"power"))
    # 前向引用允许：b 的前置 c 稍后加入。
    tree.add_node(_make_node(&"b", [&"c"]))
    var cyclic := _make_node(&"c", [&"b"])
    tree.add_node(cyclic)
    assert_bool(tree.has_talent(&"c")).override_failure_message("成环节点必须被拒绝").is_false()
    assert_int(tree.node_ids().size()).is_equal(2)

func test_self_prerequisite_is_rejected() -> void:
    tree.add_node(_make_node(&"loop", [&"loop"]))
    assert_bool(tree.has_talent(&"loop")).is_false()

func test_duplicate_node_id_is_rejected() -> void:
    tree.add_node(_make_node(&"power"))
    tree.add_node(_make_node(&"power", [], 9))
    assert_int(tree.node_ids().size()).is_equal(1)
    assert_int(tree.find_node(&"power").cost).override_failure_message("拒绝重复节点时不能覆盖原节点").is_equal(1)

# ------------------------------------------------------------------ 洗点
func test_respec_refunds_all_spent_points() -> void:
    tree.add_node(_make_node(&"power", [], 2, 2))
    tree.add_node(_make_node(&"crit", [&"power"], 3))
    tree.grant_points(10)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"crit")).is_true()
    assert_int(tree.available_points()).is_equal(3)
    assert_int(tree.respec()).is_equal(7)
    assert_int(tree.available_points()).is_equal(10)
    assert_int(tree.find_node(&"power").rank).is_equal(0)
    assert_int(tree.find_node(&"crit").rank).is_equal(0)
    assert_int(tree.state_of(&"crit")).is_equal(TalentNode.LOCKED)
    assert_int(tree.respec()).override_failure_message("没有投入时洗点不返还").is_equal(0)

func test_respec_clears_free_nodes_too() -> void:
    tree.add_node(_make_node(&"free", [], 0))
    tree.grant_points(1)
    assert_bool(tree.unlock(&"free")).is_true()
    assert_int(tree.find_node(&"free").rank).is_equal(1)
    assert_int(tree.respec()).is_equal(0)
    assert_int(tree.find_node(&"free").rank).override_failure_message("0 费节点也要被洗掉").is_equal(0)

# ------------------------------------------------------------------ 修改器
func test_modifiers_for_matches_rank() -> void:
    var node := _make_node(&"power", [], 1, 3)
    node.effects.append(TalentEffect.stat_modifier(&"attack", 5.0, 0.1))
    tree.add_node(node)
    tree.grant_points(3)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"power")).is_true()

    var modifiers := tree.modifiers_for(7)
    assert_int(modifiers.size()).is_equal(1)
    var modifier: CombatModifier = modifiers[0]
    assert_str(modifier.stat).is_equal(&"attack")
    assert_float(modifier.flat).is_equal_approx(5.0, 0.0001)
    assert_float(modifier.percent).is_equal_approx(0.1, 0.0001)
    assert_int(modifier.stacks).is_equal(3)
    assert_float(modifier.effective_flat()).override_failure_message("3 级合计 +15 攻击").is_equal_approx(15.0, 0.0001)
    assert_str(modifier.source).is_equal(&"power")

func test_modifiers_for_ignores_locked_nodes() -> void:
    var node := _make_node(&"power")
    node.effects.append(TalentEffect.stat_modifier(&"attack", 5.0))
    tree.add_node(node)
    assert_int(tree.modifiers_for(1).size()).is_equal(0)

func test_unlocked_skills_collects_and_dedupes() -> void:
    var node := _make_node(&"storm", [], 1, 2)
    node.effects.append(TalentEffect.skill_unlock(&"thunder"))
    node.effects.append(TalentEffect.skill_unlock(&"thunder"))
    tree.add_node(node)
    tree.grant_points(2)
    assert_bool(tree.unlock(&"storm")).is_true()
    assert_array(tree.unlocked_skills()).is_equal([&"thunder"])

# ------------------------------------------------------------------ 存档
func test_snapshot_restore_roundtrip() -> void:
    var power := _make_node(&"power", [], 2, 2)
    power.effects.append(TalentEffect.stat_modifier(&"attack", 5.0))
    tree.add_node(power)
    tree.add_node(_make_node(&"crit", [&"power"], 1))
    tree.grant_points(10)
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"power")).is_true()
    assert_bool(tree.unlock(&"crit")).is_true()

    var other := TalentTree.new(DomainEventBus.new())
    var power_copy := _make_node(&"power", [], 2, 2)
    power_copy.effects.append(TalentEffect.stat_modifier(&"attack", 5.0))
    other.add_node(power_copy)
    other.add_node(_make_node(&"crit", [&"power"], 1))
    # 走一遍 JSON：存档里的键会变成 String，restore 必须能归一化。
    var decoded: Dictionary = JSON.parse_string(JSON.stringify(tree.snapshot()))
    other.restore(decoded)

    assert_int(other.available_points()).is_equal(tree.available_points())
    assert_int(other.total_spent_points()).is_equal(tree.total_spent_points())
    assert_int(other.find_node(&"power").rank).is_equal(2)
    assert_int(other.find_node(&"crit").rank).is_equal(1)
    assert_int(other.state_of(&"crit")).is_equal(TalentNode.ACTIVE)
    var modifiers := other.modifiers_for(3)
    assert_int(modifiers.size()).is_equal(1)
    assert_int(modifiers[0].stacks).is_equal(2)

func test_restore_ignores_empty_and_unknown_data() -> void:
    tree.add_node(_make_node(&"power"))
    tree.grant_points(5)
    tree.restore({})
    assert_int(tree.available_points()).override_failure_message("空存档不能清空当前进度").is_equal(5)
    tree.restore({"points": 3, "ranks": {"ghost": 2}})
    assert_int(tree.available_points()).is_equal(3)
    assert_int(tree.find_node(&"power").rank).override_failure_message("未知节点被忽略，已知节点按 0 级").is_equal(0)
    assert_int(tree.node_ids().size()).is_equal(1)

# ------------------------------------------------------------------ 点数
func test_grant_points_accumulates_and_rejects_negative() -> void:
    tree.grant_points(2)
    tree.grant_points(3)
    assert_int(tree.available_points()).is_equal(5)
    tree.grant_points(-4)
    assert_int(tree.available_points()).is_equal(5)
