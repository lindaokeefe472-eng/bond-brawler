extends GdUnitTestSuite

var _pools: Array[DamageNumberPool] = []

func _pool(prewarm_count: int = 1) -> DamageNumberPool:
    var pool := DamageNumberPool.new(null, prewarm_count)
    _pools.append(pool)
    return pool

func after_test() -> void:
    for pool: DamageNumberPool in _pools:
        pool.clear()
    _pools.clear()

func test_spawn_uses_a_prewarmed_label() -> void:
    var pool := _pool(2)
    var label: Label3D = pool.spawn(Vector3.ZERO, 12)
    assert_object(label).is_not_null()
    assert_str(label.text).is_equal("12")
    assert_int(pool.active_count()).is_equal(1)
    assert_int(pool.free_count()).is_equal(1)
    assert_int(pool.created_count()).is_equal(2)

func test_expired_label_returns_to_pool() -> void:
    var pool := _pool(1)
    var label: Label3D = pool.spawn(Vector3.ZERO, 5)
    pool.tick(DamageNumberPool.LIFETIME + 0.01)
    assert_int(pool.active_count()).is_equal(0)
    assert_int(pool.free_count()).is_equal(1)
    var again: Label3D = pool.spawn(Vector3.ZERO, 6)
    # 原断言比较的是对象引用，用 is_same 保持语义（is_equal 会做属性深比较）
    assert_object(again).is_same(label)
    assert_int(pool.created_count()).is_equal(1)

func test_label_rises_while_alive() -> void:
    var pool := _pool(1)
    var label: Label3D = pool.spawn(Vector3(0.0, 1.0, 0.0), 3)
    var start_y: float = label.position.y
    pool.tick(0.1)
    assert_float(label.position.y).is_greater(start_y)

func test_pool_without_prewarm_degrades_to_null() -> void:
    var pool := _pool(0)
    assert_that(pool.spawn(Vector3.ZERO, 1)).is_null()
    assert_int(pool.created_count()).is_equal(0)

func test_crit_kind_uses_crit_color() -> void:
    var pool := _pool(1)
    var label: Label3D = pool.spawn(Vector3.ZERO, 99, &"crit")
    assert_bool(label.modulate.is_equal_approx(DamageNumberPool.CRIT_COLOR)).is_true()
