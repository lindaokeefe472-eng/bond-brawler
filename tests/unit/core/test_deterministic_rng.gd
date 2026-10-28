extends GdUnitTestSuite

func test_same_seed_same_sequence() -> void:
    var a := DeterministicRng.new(12345)
    var b := DeterministicRng.new(12345)
    for i: int in 16:
        assert_int(a.next_int(1000)).is_equal(b.next_int(1000))

func test_different_seed_diverges() -> void:
    var a := DeterministicRng.new(1)
    var b := DeterministicRng.new(2)
    var same: int = 0
    for i: int in 16:
        if a.next_int(1000) == b.next_int(1000):
            same += 1
    assert_float(float(same)).is_less(4.0)

func test_float_range() -> void:
    var r := DeterministicRng.new(7)
    for i: int in 200:
        var v := r.next_float()
        assert_bool(v >= 0.0 and v < 1.0).is_true()

func test_state_roundtrip() -> void:
    var a := DeterministicRng.new(99)
    a.next_int(100)
    var snapshot := a.get_state()
    var expected := a.next_int(100)
    var b := DeterministicRng.new(0)
    b.set_state(snapshot)
    assert_int(b.next_int(100)).is_equal(expected)
