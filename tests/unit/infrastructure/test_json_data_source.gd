extends GdUnitTestSuite

## 仓库不包含 data/（版权原因，见 README「数据与素材」）。
## 缺少数据时整组跳过，而不是报一堆红——clone 下来的人不该看到假失败。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

const DATA_ROOT: String = "res://data"
const MALFORMED_PATH: String = "user://infra_malformed_probe.json"

func test_reads_skills_dictionary_with_124_entries() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var doc: Variant = source.read_json("skills.json")
	assert_bool(doc is Dictionary).override_failure_message("skills.json 应为字典").is_true()
	if doc is Dictionary:
		assert_int((doc as Dictionary).size()).is_equal(124)

func test_reads_species_array_with_221_entries() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var doc: Variant = source.read_json("species.json")
	assert_bool(doc is Array).override_failure_message("species.json 应为数组").is_true()
	if doc is Array:
		assert_int((doc as Array).size()).is_equal(221)

func test_reads_movement_dictionary_with_entries() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var doc: Variant = source.read_json("movement.json")
	assert_bool(doc is Dictionary).override_failure_message("movement.json 应为字典").is_true()
	if doc is Dictionary:
		assert_int((doc as Dictionary).size()).is_equal(217)
		assert_str(str((doc as Dictionary).get("bulbasaur", ""))).is_equal("jump")

func test_accepts_absolute_res_path() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var doc: Variant = source.read_json("res://data/type_chart.json")
	assert_bool(doc is Dictionary).override_failure_message("带 res:// 前缀的路径应直接可用").is_true()
	if doc is Dictionary:
		assert_dict(doc as Dictionary).contains_keys("chart")

func test_missing_file_returns_empty_dictionary() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	assert_bool(source.exists("does_not_exist.json")).is_false()
	assert_dict(source.read_json("does_not_exist.json")).is_equal({})

func test_parse_failure_returns_empty_dictionary() -> void:
	var file: FileAccess = FileAccess.open(MALFORMED_PATH, FileAccess.WRITE)
	assert_object(file).override_failure_message("应能创建临时探针文件").is_not_null()
	if file == null:
		return
	file.store_string("{ 这不是合法 JSON ")
	file.close()

	var source := JsonDataSource.new(DATA_ROOT)
	assert_dict(source.read_json(MALFORMED_PATH)).override_failure_message("坏 JSON 应降级为空字典").is_equal({})
	DirAccess.remove_absolute(MALFORMED_PATH)

func test_second_read_comes_from_cache() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var first: Dictionary = source.read_json("skills.json")
	first["__cache_probe"] = true
	var second: Dictionary = source.read_json("skills.json")
	assert_bool(second.has("__cache_probe")).override_failure_message("第二次读取应命中缓存而非重新解析").is_true()

func test_clear_cache_forces_reparse() -> void:
	var source := JsonDataSource.new(DATA_ROOT)
	var first: Dictionary = source.read_json("skills.json")
	first["__cache_probe"] = true
	source.clear_cache()
	var second: Dictionary = source.read_json("skills.json")
	assert_bool(second.has("__cache_probe")).override_failure_message("清缓存后应重新从磁盘解析").is_false()
