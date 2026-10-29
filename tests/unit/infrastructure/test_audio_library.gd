## 音效数据校验：cue 覆盖、资源存在、总线声明、字段完整。
##
## 这类「数据 → 资源」的映射最容易静默失效：少一条就是某个事件永远没声音，
## 而且不会有任何报错。所以每一项都用测试钉住。
extends GdUnitTestSuite

func before(_do_skip := not FileAccess.file_exists("res://assets/audio/cues.json"),
		_skip_reason := "缺少 assets/audio/cues.json") -> void:
	pass

func _library() -> AudioLibrary:
	return AudioLibrary.new(JsonDataSource.new("res://data"))

func test_every_cue_in_constants_is_mapped() -> void:
	var library: AudioLibrary = _library()
	var missing: Array[String] = []
	for cue: StringName in GameConstants.SFX_CUES:
		if not library.has_cue(cue):
			missing.append(str(cue))
	assert_array(missing).override_failure_message(
			"这些 cue 在 data/audio.json 里没有映射：%s" % [missing]).is_empty()

func test_every_cue_file_exists() -> void:
	var library: AudioLibrary = _library()
	var missing: Array[String] = []
	for cue: StringName in library.cue_ids():
		var path: String = str(library.cue(cue).get("file", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			missing.append("%s -> %s" % [cue, path])
	assert_array(missing).override_failure_message(
			"这些音效文件不存在：%s" % [missing]).is_empty()

func test_every_cue_uses_a_declared_bus() -> void:
	var library: AudioLibrary = _library()
	var buses: Array = library.buses()
	var bad: Array[String] = []
	for cue: StringName in library.cue_ids():
		var bus: String = str(library.cue(cue).get("bus", ""))
		if not buses.has(StringName(bus)):
			bad.append("%s -> %s" % [cue, bus])
	assert_array(bad).override_failure_message("这些 cue 用了未声明的总线：%s" % [bad]).is_empty()

func test_every_cue_has_required_fields() -> void:
	var library: AudioLibrary = _library()
	var bad: Array[String] = []
	for cue: StringName in library.cue_ids():
		var entry: Dictionary = library.cue(cue)
		for field: String in AudioLibrary.REQUIRED_FIELDS:
			if not entry.has(field):
				bad.append("%s 缺 %s" % [cue, field])
	assert_array(bad).override_failure_message("字段不完整：%s" % [bad]).is_empty()

func test_unknown_cue_is_empty() -> void:
	var library: AudioLibrary = _library()
	assert_bool(library.has_cue(&"nope")).is_false()
	assert_bool(library.cue(&"nope").is_empty()).is_true()
