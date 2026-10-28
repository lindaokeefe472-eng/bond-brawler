extends GdUnitTestSuite

var _sprites: Array[SpriteBillboard] = []

func _sprite() -> SpriteBillboard:
    var sprite := SpriteBillboard.new()
    _sprites.append(sprite)
    return sprite

func after_test() -> void:
    for sprite: SpriteBillboard in _sprites:
        sprite.free()
    _sprites.clear()

func test_loop_wraps_to_first_frame() -> void:
    var sprite := _sprite()
    sprite.play_atlas(&"idle", null, 4, true, 10.0)
    sprite.tick(0.35)
    assert_int(sprite.current_frame()).is_equal(3)
    sprite.tick(0.2)
    assert_int(sprite.current_frame()).is_equal(1)

func test_non_loop_stops_on_last_frame() -> void:
    var sprite := _sprite()
    sprite.play_atlas(&"attack1", null, 3, false, 10.0)
    sprite.tick(1.0)
    assert_int(sprite.current_frame()).is_equal(2)
    assert_bool(sprite.is_finished()).is_true()
    assert_bool(sprite.is_playing()).is_false()

func test_facing_flips_sprite_horizontally() -> void:
    var sprite := _sprite()
    sprite.set_facing(-1)
    assert_bool(sprite.flip_h).is_true()
    sprite.set_facing(1)
    assert_bool(sprite.flip_h).is_false()

func test_replaying_same_animation_does_not_reset_frame() -> void:
    var sprite := _sprite()
    sprite.play_atlas(&"idle", null, 4, true, 10.0)
    sprite.tick(0.25)
    assert_int(sprite.current_frame()).is_equal(2)
    sprite.play_atlas(&"idle", null, 4, true, 10.0)
    assert_int(sprite.current_frame()).is_equal(2)
