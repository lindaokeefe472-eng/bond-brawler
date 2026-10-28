extends GdUnitTestSuite

## 仓库不包含 data/（版权原因，见 README「数据与素材」）。
## 缺少数据时整组跳过，而不是报一堆红——clone 下来的人不该看到假失败。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
        _skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
    pass

func _repo() -> SpeciesRepository:
    return SpeciesRepository.new(JsonDataSource.new("res://data"))

func test_loads_all_221_species() -> void:
    assert_int(_repo().size()).is_equal(221)
    assert_int(_repo().all().size()).is_equal(221)

func test_find_known_species_returns_raw_fields() -> void:
    var species := _repo().find(&"absol")
    assert_bool(species.is_empty()).is_false()
    assert_str(str(species.get("id", ""))).is_equal("absol")
    assert_str(str(species.get("types", ""))).is_equal("dark")
    # 战斗血量用 battle_hp，不是图鉴的 hp —— 这里顺带钉住这个坑。
    assert_float(float(species.get("battle_hp", 0.0))).is_equal_approx(400.0, 0.0001)

func test_find_unknown_returns_empty_dictionary() -> void:
    assert_bool(_repo().find(&"missingno").is_empty()).is_true()

func test_starter_returns_a_starter_source_entry() -> void:
    var species := _repo().starter()
    assert_bool(species.is_empty()).is_false()
    assert_str(str(species.get("source", ""))).is_equal("starter")

func test_starters_lists_all_five_candidates() -> void:
    assert_int(_repo().starters().size()).is_equal(5)
