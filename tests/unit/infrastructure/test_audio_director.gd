## 音效适配器：cue 映射、防叠音、并发上限、总线音量。
##
## 这些是「有没有声音」的判定逻辑，不涉及音质，所以可以脱离听感单测。
extends GdUnitTestSuite

var _directors: Array[AudioDirector] = []

func before(_do_skip := not FileAccess.file_exists("res://assets/audio/cues.json"),
		_skip_reason := "缺少 assets/audio/cues.json") -> void:
	pass

func _director() -> AudioDirector:
	var director := AudioDirector.new()
	director.configure(AudioLibrary.new(JsonDataSource.new("res://data")))
	_directors.append(director)
	return director

func after_test() -> void:
	for director: AudioDirector in _directors:
		director.dispose()
	_directors.clear()

func test_unknown_cue_is_ignored() -> void:
	var director: AudioDirector = _director()
	director.play(&"nope")
	assert_int(director.play_count()).is_equal(0)

func test_known_cue_plays_once() -> void:
	var director: AudioDirector = _director()
	director.play(&"hit")
	assert_int(director.play_count()).is_equal(1)

func test_debounce_blocks_repeat_within_window() -> void:
	var director: AudioDirector = _director()
	director.play(&"hit")
	director.play(&"hit")
	assert_int(director.play_count()).override_failure_message(
			"同一 cue 在 debounce 窗口内不该重复播放").is_equal(1)
	assert_int(director.debounce_count()).is_equal(1)
	director.tick(0.1)
	director.play(&"hit")
	assert_int(director.play_count()).is_equal(2)

func test_different_cues_do_not_block_each_other() -> void:
	var director: AudioDirector = _director()
	director.play(&"hit")
	director.play(&"crit")
	assert_int(director.play_count()).is_equal(2)

func test_bus_volume_accepts_extremes() -> void:
	var director: AudioDirector = _director()
	director.set_bus_volume(&"sfx", 0.0)
	director.set_bus_volume(&"sfx", 1.0)
	director.set_bus_volume(&"sfx", 5.0)
	assert_int(director.play_count()).is_equal(0)
