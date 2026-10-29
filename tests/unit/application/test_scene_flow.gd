## 场景流程状态机：只允许合法的跳转，非法跳转不改状态。
extends GdUnitTestSuite

func test_starts_in_title() -> void:
	var flow := SceneFlow.new()
	assert_int(flow.state()).is_equal(SceneFlow.State.TITLE)
	assert_bool(flow.is_playing()).is_false()

func test_title_to_playing() -> void:
	var flow := SceneFlow.new()
	assert_bool(flow.start()).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.PLAYING)
	assert_bool(flow.is_playing()).is_true()

func test_pause_and_resume_round_trip() -> void:
	var flow := SceneFlow.new()
	flow.start()
	assert_bool(flow.pause()).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.PAUSED)
	assert_bool(flow.is_playing()).is_false()
	assert_bool(flow.resume()).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.PLAYING)

func test_cannot_pause_from_title() -> void:
	var flow := SceneFlow.new()
	assert_bool(flow.pause()).is_false()
	assert_int(flow.state()).is_equal(SceneFlow.State.TITLE)

func test_death_goes_to_result() -> void:
	var flow := SceneFlow.new()
	flow.start()
	assert_bool(flow.finish(false)).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.RESULT)
	assert_bool(flow.is_playing()).is_false()

func test_restart_from_result() -> void:
	var flow := SceneFlow.new()
	flow.start()
	flow.finish(true)
	assert_bool(flow.restart()).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.PLAYING)

func test_cannot_restart_while_playing() -> void:
	var flow := SceneFlow.new()
	flow.start()
	assert_bool(flow.restart()).is_false()
	assert_int(flow.state()).is_equal(SceneFlow.State.PLAYING)
