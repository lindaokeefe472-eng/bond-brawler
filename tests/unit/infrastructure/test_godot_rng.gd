extends GdUnitTestSuite

func test_same_seed_same_sequence() -> void:
	var a := GodotRng.new(12345)
	var b := GodotRng.new(12345)
	for i: int in 32:
		assert_int(a.next_int(100000)).is_equal(b.next_int(100000))

func test_different_seeds_diverge() -> void:
	var a := GodotRng.new(1)
	var b := GodotRng.new(2)
	var same: int = 0
	for i: int in 32:
		if a.next_int(100000) == b.next_int(100000):
			same += 1
	assert_float(float(same)).is_less(4.0)

func test_float_stays_in_unit_interval() -> void:
	var r := GodotRng.new(7)
	for i: int in 200:
		var v: float = r.next_float()
		assert_bool(v >= 0.0 and v < 1.0).is_true()

func test_next_int_respects_bounds() -> void:
	var r := GodotRng.new(3)
	for i: int in 200:
		var v: int = r.next_int(10)
		assert_bool(v >= 0 and v < 10).is_true()
	assert_int(r.next_int(0)).override_failure_message("非正上界应返回 0 而不是崩溃").is_equal(0)

func test_get_seed_returns_constructor_seed() -> void:
	var r := GodotRng.new(4242)
	assert_int(r.get_seed()).is_equal(4242)

func test_reseed_restarts_sequence() -> void:
	var r := GodotRng.new(88)
	var first: int = r.next_int(100000)
	r.reseed(88)
	assert_int(r.next_int(100000)).is_equal(first)

func test_fork_same_label_is_reproducible() -> void:
	var a := GodotRng.new(99)
	var b := GodotRng.new(99)
	var ai_a: IRng = a.fork(&"ai")
	var ai_b: IRng = b.fork(&"ai")
	for i: int in 16:
		assert_int(ai_a.next_int(1000)).is_equal(ai_b.next_int(1000))

func test_fork_does_not_consume_parent_stream() -> void:
	var a := GodotRng.new(99)
	a.next_int(1000)
	var forked_after_draw: IRng = a.fork(&"ai")
	var fresh := GodotRng.new(99)
	var forked_fresh: IRng = fresh.fork(&"ai")
	for i: int in 16:
		assert_int(forked_after_draw.next_int(1000)).is_equal(forked_fresh.next_int(1000))

func test_fork_labels_diverge() -> void:
	var parent := GodotRng.new(99)
	var ai: IRng = parent.fork(&"ai")
	var loot: IRng = parent.fork(&"loot")
	var same: int = 0
	for i: int in 32:
		if ai.next_int(1000) == loot.next_int(1000):
			same += 1
	assert_float(float(same)).is_less(4.0)
