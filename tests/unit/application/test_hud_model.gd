## HUD 视图模型：纯逻辑，不碰 Node、不碰领域对象。
extends GdUnitTestSuite

func _entry(id: int, hp: float = 100.0, max_hp: float = 100.0) -> Dictionary:
	return HudModel.make_entry(id, "actor%d" % id, hp, max_hp, 50.0, 180.0, [0.0, 0.0, 0.0, 0.0], true)

func test_snapshot_builds_entries_in_order() -> void:
	var model := HudModel.new()
	model.apply_snapshot([_entry(3), _entry(1)])
	var ids: Array[int] = []
	for entry: Dictionary in model.entries():
		ids.append(int(entry["id"]))
	assert_array(ids).contains_exactly([3, 1])

func test_snapshot_updates_values_and_keeps_order() -> void:
	var model := HudModel.new()
	model.apply_snapshot([_entry(3), _entry(1)])
	model.apply_snapshot([_entry(1, 40.0), _entry(3, 90.0)])
	var first: Dictionary = model.entries()[0]
	assert_int(int(first["id"])).is_equal(3)
	assert_float(float(first["hp"])).is_equal_approx(90.0, 0.001)

func test_hp_ratio_is_clamped() -> void:
	var model := HudModel.new()
	model.apply_snapshot([_entry(1, 150.0, 100.0)])
	assert_float(float(model.entries()[0]["hp_ratio"])).is_equal_approx(1.0, 0.001)

func test_combo_increments_and_expires() -> void:
	var model := HudModel.new()
	model.note_player_hit()
	model.note_player_hit()
	assert_int(model.combo()).is_equal(2)
	model.tick(HudModel.COMBO_WINDOW * 0.5)
	assert_int(model.combo()).is_equal(2)
	model.tick(HudModel.COMBO_WINDOW)
	assert_int(model.combo()).is_equal(0)

func test_damage_flash_decays() -> void:
	var model := HudModel.new()
	model.apply_snapshot([_entry(1)])
	model.note_damage(1)
	assert_float(model.flash_ratio(1)).is_equal_approx(1.0, 0.001)
	model.tick(HudModel.FLASH_SECONDS)
	assert_float(model.flash_ratio(1)).is_equal_approx(0.0, 0.001)

func test_missing_actor_flash_is_zero() -> void:
	var model := HudModel.new()
	assert_float(model.flash_ratio(99)).is_equal_approx(0.0, 0.001)
