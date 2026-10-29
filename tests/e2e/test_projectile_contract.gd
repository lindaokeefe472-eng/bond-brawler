## 契约测试：data 里所有 projectile / volley 模板的技能，释放后必须真的产生弹体。
##
## 之前 combat_pipeline 对这两类模板跳过直接伤害，指望「弹体命中时再结算」，
## 但全项目没有任何地方生成弹体 —— 20 个技能放出去既没有伤害也没有画面。
## 这条用例专门防止这种「静默空转」再次出现。
extends GdUnitTestSuite

const STEP: float = GameConstants.TICK_DELTA
const MAX_TICKS: int = 150

func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

func test_every_projectile_skill_spawns_a_projectile() -> void:
	var app: CompositionRoot = CompositionRoot.create("res://data", 20261029)
	var checked: int = 0
	var offenders: Array[String] = []
	for def: SkillDef in app.skills.all():
		if not _is_projectile_template(def.template):
			continue
		checked += 1
		if not _casts_and_spawns(def):
			offenders.append(str(def.id))
	assert_int(checked).override_failure_message(
			"data 里找不到弹体技能，这条用例失去意义").is_greater(0)
	assert_array(offenders).override_failure_message(
			"这些弹体技能放出去没有产生任何弹体（静默空转）：%s" % [offenders]).is_empty()

## 开一局干净的会话，放一次技能，看场上有没有出现弹体。
func _casts_and_spawns(def: SkillDef) -> bool:
	var session := BattleSession.new({
		BattleSession.SERVICE_BUS: DomainEventBus.new(),
		BattleSession.SERVICE_RNG: DeterministicRng.new(7),
	})
	var caster_id: int = session.spawn_actor({
		"species_id": "tester",
		"faction": GameConstants.FACTION_PLAYER,
		"plane_pos": Vector2.ZERO,
		"stats": {"max_hp": 500.0, "attack": 10.0, "defense": 0.0, "types": []},
		"skills": [def],
	})
	var caster: ActorRuntime = session.get_actor(caster_id)
	if caster == null or not caster.try_cast_skill(0, Vector2(1.0, 0.0)):
		return false
	var inputs: Dictionary = {caster_id: LocoInputFrame.empty()}
	for _i: int in range(MAX_TICKS):
		session.tick(STEP, inputs)
		if session.projectiles().size() > 0:
			return true
	return false

func _is_projectile_template(template: StringName) -> bool:
	var normalized: StringName = SkillTemplateRegistry.normalize_template(template)
	return normalized == SkillTemplateRegistry.TEMPLATE_PROJECTILE \
			or normalized == SkillTemplateRegistry.TEMPLATE_VOLLEY
