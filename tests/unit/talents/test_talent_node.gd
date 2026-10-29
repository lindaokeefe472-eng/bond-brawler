extends GdUnitTestSuite

func test_state_locked_when_prerequisite_missing() -> void:
	var node := TalentNode.from_dict({"id": "crit", "prerequisites": ["power"]})
	assert_int(node.state({})).is_equal(TalentNode.LOCKED)
	assert_int(node.state({&"other": 1})).is_equal(TalentNode.LOCKED)

func test_state_available_when_all_prerequisites_met() -> void:
	var node := TalentNode.from_dict({"id": "crit", "prerequisites": ["power", "speed"]})
	assert_int(node.state({&"power": 1})).is_equal(TalentNode.LOCKED)
	assert_int(node.state({&"power": 1, &"speed": 1})).is_equal(TalentNode.AVAILABLE)

func test_state_active_when_own_rank_positive() -> void:
	var node := TalentNode.from_dict({"id": "crit", "max_rank": 3})
	node.rank = 2
	# 快照还没刷新时，节点自身 rank 也应立刻显示为已激活。
	assert_int(node.state({})).is_equal(TalentNode.ACTIVE)

func test_state_active_from_snapshot() -> void:
	var node := TalentNode.from_dict({"id": "crit"})
	assert_int(node.state({&"crit": 1})).is_equal(TalentNode.ACTIVE)

func test_from_dict_parses_effects_and_clamps_ranks() -> void:
	var node := TalentNode.from_dict({
		"id": "power",
		"name": "力量",
		"max_rank": 0,
		"cost": -2,
		"effects": [{"kind": "stat_modifier", "stat": "attack", "flat": 4.0}],
	})
	assert_str(node.name).is_equal("力量")
	assert_int(node.max_rank).override_failure_message("max_rank 至少为 1").is_equal(1)
	assert_int(node.cost).override_failure_message("cost 不允许为负").is_equal(0)
	assert_int(node.effects.size()).is_equal(1)
	assert_bool(node.effects[0] is TalentEffect).is_true()

func test_can_rank_up_respects_max_rank() -> void:
	var node := TalentNode.from_dict({"id": "power", "max_rank": 2})
	assert_bool(node.can_rank_up()).is_true()
	node.rank = 2
	assert_bool(node.can_rank_up()).is_false()
	assert_bool(node.is_max_rank()).is_true()
