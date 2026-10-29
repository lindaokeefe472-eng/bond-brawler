## 存档服务：往返一致、缺档回空、坏档回退、旧版本迁移。
extends GdUnitTestSuite

const DIR: String = "user://test_save_service"

func before_test() -> void:
	_cleanup()

func after_test() -> void:
	_cleanup()

func _cleanup() -> void:
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(DIR.path_join(file_name))
	DirAccess.remove_absolute(DIR)

func _service() -> SaveService:
	return SaveService.new(SaveStore.new(DIR))

func _talents() -> TalentTree:
	var tree := TalentTree.new(DomainEventBus.new())
	tree.add_node(TalentNode.from_dict({"id": "might", "max_rank": 3, "cost": 1}))
	tree.grant_points(5)
	return tree

func _stage() -> StageProgress:
	var progress := StageProgress.new([&"room_a", &"room_b"])
	progress.complete_room(&"room_a")
	return progress

func test_round_trip_preserves_stage_talents_settings() -> void:
	var service: SaveService = _service()
	var stage: StageProgress = _stage()
	var talents: TalentTree = _talents()
	talents.unlock(&"might")
	var settings := SettingsModel.new()
	settings.set_volume(&"sfx", 0.25)
	settings.set_language(&"en")
	assert_bool(service.save(stage, talents, settings)).is_true()

	var reloaded_stage := StageProgress.new([&"room_a", &"room_b"])
	var reloaded_talents := TalentTree.new(DomainEventBus.new())
	reloaded_talents.add_node(TalentNode.from_dict({"id": "might", "max_rank": 3, "cost": 1}))
	var reloaded_settings := SettingsModel.new()
	service.apply_snapshot(service.load_snapshot(), reloaded_stage, reloaded_talents, reloaded_settings)

	assert_bool(reloaded_stage.is_unlocked(&"room_a")).is_true()
	assert_int(reloaded_talents.state_of(&"might")).is_equal(TalentNode.ACTIVE)
	assert_float(reloaded_settings.volume(&"sfx")).is_equal_approx(0.25, 0.001)
	assert_that(reloaded_settings.language).is_equal(&"en")

func test_missing_save_returns_empty() -> void:
	assert_bool(_service().has_save()).is_false()
	assert_bool(_service().load_snapshot().is_empty()).is_true()

func test_corrupt_save_falls_back_to_empty() -> void:
	var store := SaveStore.new(DIR)
	store.save_slot(SaveService.SLOT, {"version": SaveService.DTO_VERSION, "talents": {}})
	var path: String = store.slot_path(SaveService.SLOT)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ 这不是合法 JSON")
	file.close()
	# SaveStore 负责把坏档降级成空字典，上层据此开新档
	assert_bool(_service().load_snapshot().is_empty()).is_true()

func test_old_version_is_migrated() -> void:
	var store := SaveStore.new(DIR)
	store.save_slot(SaveService.SLOT, {"version": 1, "talents": {"points": 2}})
	var snapshot: Dictionary = _service().load_snapshot()
	assert_int(int(snapshot.get("version", 0))).is_equal(SaveService.DTO_VERSION)
	assert_bool(snapshot.has("stage")).is_true()
	assert_bool(snapshot.has("settings")).is_true()
