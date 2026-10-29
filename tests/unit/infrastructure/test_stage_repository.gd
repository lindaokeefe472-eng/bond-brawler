## 关卡数据校验：刷怪表引用的物种/角色必须存在，AI 性格必须定义。
##
## 这类「数据引用数据」的错误不会报错，只会让某只怪变成默认物种、
## 或者所有敌人悄悄共用一套性格 —— 只能靠测试盯。
extends GdUnitTestSuite

const MANIFEST: String = "res://assets/sprites/characters/manifest.json"

func before(_do_skip := not FileAccess.file_exists("res://data/stages.json"),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

func _repo() -> StageRepository:
	return StageRepository.new(JsonDataSource.new("res://data"))

func test_default_stage_exists() -> void:
	var stage: StageDefinition = _repo().first()
	assert_object(stage).override_failure_message("data/stages.json 里没有关卡").is_not_null()
	assert_int(stage.spawn_count()).is_greater(0)

func test_every_spawn_references_known_species() -> void:
	var species: SpeciesRepository = SpeciesRepository.new(JsonDataSource.new("res://data"))
	var bad: Array[String] = []
	for stage_id: StringName in _repo().all_ids():
		var stage: StageDefinition = _repo().find(stage_id)
		for spawn: Dictionary in stage.spawns:
			var species_id: StringName = spawn.get("species", &"")
			if species.find(species_id).is_empty():
				bad.append("%s/%s" % [stage_id, species_id])
	assert_array(bad).override_failure_message("刷怪表引用了不存在的物种：%s" % [bad]).is_empty()

func test_every_spawn_references_known_character() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var characters: Dictionary = manifest.get("characters", {})
	var bad: Array[String] = []
	for stage_id: StringName in _repo().all_ids():
		var stage: StageDefinition = _repo().find(stage_id)
		for spawn: Dictionary in stage.spawns:
			var character: String = str(spawn.get("character", ""))
			if not characters.has(character):
				bad.append("%s/%s" % [stage_id, character])
	assert_array(bad).override_failure_message("刷怪表引用了不存在的角色图集：%s" % [bad]).is_empty()

func test_every_spawn_has_a_defined_brain() -> void:
	var bad: Array[String] = []
	for stage_id: StringName in _repo().all_ids():
		var stage: StageDefinition = _repo().find(stage_id)
		for missing: StringName in stage.missing_brains():
			bad.append("%s/%s" % [stage_id, missing])
	assert_array(bad).override_failure_message("这些性格 id 没有定义：%s" % [bad]).is_empty()

func test_brain_profile_has_expected_keys() -> void:
	var stage: StageDefinition = _repo().first()
	var profile: Dictionary = stage.brain_profile(&"default")
	for key: String in ["aggression", "caution", "range_preference", "skill_range", "stickiness"]:
		assert_bool(profile.has(key)).override_failure_message("default 性格缺 %s" % key).is_true()

func test_unknown_stage_returns_null() -> void:
	assert_object(_repo().find(&"nope")).is_null()
