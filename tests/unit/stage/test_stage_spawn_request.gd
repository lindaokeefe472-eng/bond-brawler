extends GdUnitTestSuite

func test_to_dict_contains_contract_fields() -> void:
    var request := StageSpawnRequest.new(&"pikachu", Vector2(3.5, -1.25), 2, GameConstants.FACTION_ENEMY)
    var data: Dictionary = request.to_dict()
    assert_str(StringName(data["species_id"])).is_equal(&"pikachu")
    assert_int(data["wave"]).is_equal(2)
    assert_str(StringName(data["faction"])).is_equal(GameConstants.FACTION_ENEMY)
    var pos: Vector2 = data["plane_pos"]
    assert_float(pos.x).is_equal_approx(3.5, 0.001)
    assert_float(pos.y).is_equal_approx(-1.25, 0.001)

func test_from_dict_roundtrip() -> void:
    var source := StageSpawnRequest.new(&"bulbasaur", Vector2(-2.0, 1.5), 1, GameConstants.FACTION_ENEMY)
    var back := StageSpawnRequest.from_dict(source.to_dict())
    assert_str(back.species_id).is_equal(&"bulbasaur")
    assert_int(back.wave).is_equal(1)
    assert_float(back.plane_pos.x).is_equal_approx(-2.0, 0.001)
    assert_float(back.plane_pos.y).is_equal_approx(1.5, 0.001)

func test_from_dict_defaults_are_safe() -> void:
    var request := StageSpawnRequest.from_dict({})
    assert_str(request.species_id).is_equal(&"")
    assert_int(request.wave).is_equal(0)
    assert_str(request.faction).is_equal(GameConstants.FACTION_ENEMY)
    assert_float(request.plane_pos.x).is_equal_approx(0.0, 0.001)
    assert_float(request.plane_pos.y).is_equal_approx(0.0, 0.001)
