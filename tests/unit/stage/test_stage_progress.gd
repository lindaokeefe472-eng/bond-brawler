extends GdUnitTestSuite

func _rooms() -> Array[StringName]:
    var out: Array[StringName] = [&"r1", &"r2", &"r3"]
    return out

func test_first_room_unlocked_initially() -> void:
    var progress := StageProgress.new(_rooms())
    assert_bool(progress.is_unlocked(&"r1")).is_true()
    assert_bool(progress.is_unlocked(&"r2")).is_false()
    assert_bool(progress.is_unlocked(&"unknown_room")).is_false()

func test_room_unlocks_after_previous_cleared() -> void:
    var progress := StageProgress.new(_rooms())
    progress.complete_room(&"r1")
    assert_bool(progress.is_unlocked(&"r2")).is_true()
    assert_bool(progress.is_unlocked(&"r3")).is_false()
    progress.complete_room(&"r2")
    assert_bool(progress.is_unlocked(&"r3")).is_true()

func test_complete_room_emits_event_once() -> void:
    var bus := DomainEventBus.new()
    var events: Array[Dictionary] = []
    bus.subscribe(GameConstants.EVT_ROOM_CLEARED, func(e: DomainEvent) -> void: events.append(e.payload))
    var progress := StageProgress.new(_rooms(), bus)
    progress.complete_room(&"r1")
    assert_int(events.size()).is_equal(1)
    assert_str(StringName(events[0]["room_id"])).is_equal(&"r1")
    assert_int(events[0]["index"]).is_equal(0)
    progress.complete_room(&"r1")
    assert_int(events.size()).is_equal(1)

func test_complete_locked_room_is_ignored() -> void:
    var progress := StageProgress.new(_rooms())
    progress.complete_room(&"r3")
    assert_int(progress.completed_rooms().size()).is_equal(0)
    assert_bool(progress.is_unlocked(&"r2")).is_false()

func test_snapshot_restore_roundtrip() -> void:
    var progress := StageProgress.new(_rooms())
    progress.complete_room(&"r1")
    progress.complete_room(&"r2")
    var snap: Dictionary = progress.snapshot()

    var restored := StageProgress.new(_rooms())
    restored.restore(snap)
    assert_array(restored.completed_rooms()).is_equal(progress.completed_rooms())
    assert_bool(restored.is_unlocked(&"r3")).is_true()
    var snap2: Dictionary = restored.snapshot()
    assert_array(snap2["rooms"]).is_equal(snap["rooms"])
    assert_array(snap2["completed"]).is_equal(snap["completed"])
    assert_int(snap2["version"]).is_equal(snap["version"])

func test_restore_rejects_non_contiguous_progress() -> void:
    var progress := StageProgress.new(_rooms())
    # r2 完成但 r1 未完成：非法进度，只保留连续前缀（这里为空）。
    progress.restore({"version": 1, "rooms": ["r1", "r2", "r3"], "completed": ["r2"]})
    assert_int(progress.completed_rooms().size()).is_equal(0)
    assert_bool(progress.is_unlocked(&"r1")).is_true()

func test_stage_complete_when_all_rooms_cleared() -> void:
    var progress := StageProgress.new(_rooms())
    assert_bool(progress.is_stage_complete()).is_false()
    progress.complete_room(&"r1")
    progress.complete_room(&"r2")
    progress.complete_room(&"r3")
    assert_bool(progress.is_stage_complete()).is_true()
