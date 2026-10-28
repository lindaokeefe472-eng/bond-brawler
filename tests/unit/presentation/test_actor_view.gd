extends GdUnitTestSuite

var _views: Array[ActorView] = []

func _view() -> ActorView:
    var view := ActorView.new()
    _views.append(view)
    return view

func after_test() -> void:
    for view: ActorView in _views:
        view.free()
    _views.clear()

func test_output_maps_plane_position_to_world() -> void:
    var view := _view()
    var output := LocoActionOutput.new()
    output.plane_pos = Vector2(3.0, -1.5)
    output.height = 0.8
    view.apply_output(output)
    # Vector2 分量是 32 位，浮点统一用 approx 比较（沿用原框架 0.0001 的 epsilon）
    assert_float(view.position.x).is_equal_approx(3.0, 0.0001)
    assert_float(view.position.y).is_equal_approx(0.8, 0.0001)
    assert_float(view.position.z).is_equal_approx(-1.5, 0.0001)

func test_dead_output_marks_view_dead_once() -> void:
    var view := _view()
    var output := LocoActionOutput.new()
    output.state = LocoActionState.DEAD
    view.apply_output(output)
    assert_bool(view.is_dead()).is_true()
    assert_int(view.collision_layer).is_equal(0)
    view.apply_output(output)
    assert_bool(view.is_dead()).is_true()

func test_null_output_is_ignored() -> void:
    var view := _view()
    view.position = Vector3(1.0, 2.0, 3.0)
    view.apply_output(null)
    assert_float(view.position.x).is_equal_approx(1.0, 0.0001)
