extends GdUnitTestSuite

func test_dispatch_order_by_priority() -> void:
	var bus := DomainEventBus.new()
	var seen: Array[String] = []
	var low := func(_e: DomainEvent) -> void: seen.append("low")
	var high := func(_e: DomainEvent) -> void: seen.append("high")
	bus.subscribe(&"x", low, 0)
	bus.subscribe(&"x", high, 10)
	bus.emit_type(&"x")
	assert_array(seen).is_equal(["high", "low"])

func test_unsubscribe_inside_handler() -> void:
	var bus := DomainEventBus.new()
	var hits: Array[int] = []
	var handle: Array[int] = [0]
	var cb := func(_e: DomainEvent) -> void:
		hits.append(1)
		bus.unsubscribe(handle[0])
	handle[0] = bus.subscribe(&"x", cb)
	bus.emit_type(&"x")
	bus.emit_type(&"x")
	assert_int(hits.size()).is_equal(1)

func test_recording() -> void:
	var bus := DomainEventBus.new()
	bus.set_recording(true)
	bus.emit_type(&"a", {"v": 1})
	bus.emit_type(&"b")
	var recorded := bus.recorded_events()
	assert_int(recorded.size()).is_equal(2)
	assert_int(recorded[0].get_value(&"v")).is_equal(1)

func test_sequence_is_monotonic() -> void:
	var bus := DomainEventBus.new()
	var e1 := DomainEvent.make(&"a")
	var e2 := DomainEvent.make(&"b")
	bus.emit(e1)
	bus.emit(e2)
	assert_bool(e2.sequence > e1.sequence).is_true()

func test_wildcard_receives_all() -> void:
	var bus := DomainEventBus.new()
	var count: Array[int] = [0]
	var cb := func(_e: DomainEvent) -> void: count[0] += 1
	bus.subscribe(&"*", cb)
	bus.emit_type(&"a")
	bus.emit_type(&"b")
	assert_int(count[0]).is_equal(2)
