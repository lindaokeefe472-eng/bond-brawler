## 端到端：弹体技能必须真的把血打掉，并且照常进入冷却。
##
## 契约测试只保证「生成了弹体」，这条保证「生成了之后会打到人」——
## 少任何一环，玩家看到的都是「技能放出去毫无反应」。
extends GdUnitTestSuite

const STEP: float = GameConstants.TICK_DELTA
const MAX_TICKS: int = 180

func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

func test_fireball_damages_the_player() -> void:
	_assert_skill_hits(&"fireball")

func test_razor_volley_damages_the_player() -> void:
	_assert_skill_hits(&"razor")

func _assert_skill_hits(skill_id: StringName) -> void:
	var app: CompositionRoot = CompositionRoot.create("res://data", 20261029)
	var def: SkillDef = app.skills.find(skill_id)
	assert_object(def).override_failure_message("data 里找不到技能 %s" % skill_id).is_not_null()

	var session := BattleSession.new({
		BattleSession.SERVICE_BUS: DomainEventBus.new(),
		BattleSession.SERVICE_RNG: DeterministicRng.new(11),
	})
	var caster_id: int = session.spawn_actor({
		"species_id": "tester",
		"faction": GameConstants.FACTION_ENEMY,
		"plane_pos": Vector2.ZERO,
		"facing": -1,
		"stats": {"max_hp": 500.0, "attack": 20.0, "defense": 0.0, "types": []},
		"skills": [def],
	})
	var target_id: int = session.spawn_actor({
		"species_id": "dummy",
		"faction": GameConstants.FACTION_PLAYER,
		"plane_pos": Vector2(-4.0, 0.0),
		"stats": {"max_hp": 500.0, "attack": 1.0, "defense": 0.0, "types": []},
	})
	var caster: ActorRuntime = session.get_actor(caster_id)
	var target: ActorRuntime = session.get_actor(target_id)
	caster.facing = -1
	assert_bool(caster.try_cast_skill(0, Vector2(-1.0, 0.0))).override_failure_message(
			"%s 起手失败" % skill_id).is_true()

	var hp_before: float = target.stats.current_hp
	for _i: int in range(MAX_TICKS):
		session.tick(STEP, {})
		if target.stats.current_hp < hp_before:
			break
	assert_float(target.stats.current_hp).override_failure_message(
			"%s 打出去之后目标一点血都没掉" % skill_id).is_less(hp_before)
	# 冷却照常进入：刚放完不能再放
	assert_bool(caster.caster.can_cast(0, caster.energy)).override_failure_message(
			"%s 放完没有进入冷却" % skill_id).is_false()
