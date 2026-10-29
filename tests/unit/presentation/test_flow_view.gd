## 流程覆盖层的按键处理：不能在视口已经消失时崩掉。
##
## 回归：结算界面按 R 会 reload_current_scene()，回调返回时 FlowView 已经
## 不在树上，get_viewport() 返回 null —— 旧代码直接
## "Cannot call method 'set_input_as_handled' on a null value"。
extends GdUnitTestSuite

func test_restart_key_is_safe_when_detached() -> void:
	var view := FlowView.new()
	add_child(view)
	var flow := SceneFlow.new()
	view.bind(flow)
	flow.start()
	flow.finish(false)
	var restarted: Array[bool] = []
	view.on_restart = func() -> void: restarted.append(true)

	# 模拟 reload 之后：节点已经离开场景树
	remove_child(view)
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = true
	view._unhandled_input(event)

	assert_array(restarted).override_failure_message("回调没被触发").is_not_empty()
	view.free()

func test_unknown_key_does_nothing() -> void:
	var view := FlowView.new()
	add_child(view)
	var flow := SceneFlow.new()
	view.bind(flow)
	flow.start()
	var restarted: Array[bool] = []
	view.on_restart = func() -> void: restarted.append(true)
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = true
	# 还在 PLAYING，不该触发重开
	view._unhandled_input(event)
	assert_array(restarted).is_empty()
	remove_child(view)
	view.free()
