extends GdUnitTestSuite

const TEST_DIR: String = "user://test_saves_infra"
const SLOT: String = "roundtrip"
const CORRUPT_SLOT: String = "corrupt"
const FUTURE_SLOT: String = "future"

var _store: SaveStore

func before_test() -> void:
    _store = SaveStore.new(TEST_DIR)
    _store.delete_slot(SLOT)
    _store.delete_slot(CORRUPT_SLOT)
    _store.delete_slot(FUTURE_SLOT)

func after_test() -> void:
    if _store == null:
        return
    _store.delete_slot(SLOT)
    _store.delete_slot(CORRUPT_SLOT)
    _store.delete_slot(FUTURE_SLOT)

func test_roundtrip_preserves_nested_data() -> void:
    var data: Dictionary = {
        "player_name": "小智",
        "stage": 3,
        "hp_ratio": 0.5,
        "team": ["pikachu", "greninja"],
        "talents": {"fire": 2},
    }
    assert_bool(_store.save_slot(SLOT, data)).override_failure_message("写档应成功").is_true()
    var loaded: Dictionary = _store.load_slot(SLOT)
    assert_str(str(loaded.get("player_name", ""))).is_equal("小智")
    assert_int(int(loaded.get("stage", 0))).is_equal(3)
    assert_float(float(loaded.get("hp_ratio", 0.0))).is_equal_approx(0.5, 0.0001)
    assert_array(loaded.get("team", [])).is_equal(["pikachu", "greninja"])
    var talents: Variant = loaded.get("talents", {})
    assert_bool(talents is Dictionary).is_true()
    if talents is Dictionary:
        assert_int(int(talents.get("fire", 0))).is_equal(2)

func test_missing_slot_returns_empty_dictionary() -> void:
    assert_bool(_store.has_slot("never_written")).is_false()
    assert_bool(_store.load_slot("never_written").is_empty()).is_true()

func test_saved_file_contains_version_envelope() -> void:
    assert_bool(_store.save_slot(SLOT, {"x": 1})).is_true()
    var path: String = _store.slot_path(SLOT)
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    assert_object(file).is_not_null()
    if file == null:
        return
    var doc: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    assert_bool(doc is Dictionary).override_failure_message("存档文件应是 JSON 对象").is_true()
    if doc is Dictionary:
        assert_int(int(doc.get("version", 0))).is_equal(SaveStore.SAVE_VERSION)
        assert_bool(doc.has("data")).is_true()

func test_corrupt_file_falls_back_to_empty() -> void:
    var path: String = _store.slot_path(CORRUPT_SLOT)
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    assert_object(file).is_not_null()
    if file == null:
        return
    file.store_string("{ broken json")
    file.close()
    assert_bool(_store.load_slot(CORRUPT_SLOT).is_empty()).override_failure_message("损坏存档应回退为空").is_true()

func test_future_version_falls_back_to_empty() -> void:
    var path: String = _store.slot_path(FUTURE_SLOT)
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    assert_object(file).is_not_null()
    if file == null:
        return
    file.store_string(JSON.stringify({
        "version": SaveStore.SAVE_VERSION + 1,
        "data": {"x": 1},
    }))
    file.close()
    assert_bool(_store.load_slot(FUTURE_SLOT).is_empty()).override_failure_message("未知高版本应回退为空").is_true()

func test_invalid_slot_name_is_rejected() -> void:
    assert_bool(_store.save_slot("../escape", {"x": 1})).override_failure_message("不允许路径穿越").is_false()
    assert_bool(_store.save_slot("", {"x": 1})).override_failure_message("空槽名非法").is_false()
    assert_bool(_store.slot_path("../escape").is_empty()).is_true()

func test_delete_slot_removes_file() -> void:
    assert_bool(_store.save_slot(SLOT, {"x": 1})).is_true()
    assert_bool(_store.has_slot(SLOT)).is_true()
    assert_bool(_store.delete_slot(SLOT)).is_true()
    assert_bool(_store.has_slot(SLOT)).is_false()
