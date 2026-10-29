## 设置模型：音量夹取、语言轮换。纯数据，不碰音频总线也不碰文件。
extends GdUnitTestSuite

func test_volume_defaults_in_range() -> void:
	var model := SettingsModel.new()
	assert_float(model.volume(&"master")).is_between(0.0, 1.0)
	assert_float(model.volume(&"sfx")).is_between(0.0, 1.0)
	assert_float(model.volume(&"bgm")).is_between(0.0, 1.0)

func test_volume_is_clamped() -> void:
	var model := SettingsModel.new()
	model.set_volume(&"master", 2.0)
	assert_float(model.volume(&"master")).is_equal_approx(1.0, 0.0001)
	model.set_volume(&"master", -1.0)
	assert_float(model.volume(&"master")).is_equal_approx(0.0, 0.0001)

func test_unknown_channel_is_ignored() -> void:
	var model := SettingsModel.new()
	model.set_volume(&"nope", 0.5)
	assert_float(model.volume(&"nope")).is_equal_approx(0.0, 0.0001)

func test_language_cycles_through_all() -> void:
	var model := SettingsModel.new()
	var seen: Array[StringName] = [model.language]
	for _i: int in range(SettingsModel.LANGUAGES.size() - 1):
		seen.append(model.cycle_language())
	assert_array(seen).contains_exactly(SettingsModel.LANGUAGES)

func test_set_language_rejects_unknown() -> void:
	var model := SettingsModel.new()
	var before: StringName = model.language
	assert_bool(model.set_language(&"klingon")).is_false()
	assert_that(model.language).is_equal(before)
