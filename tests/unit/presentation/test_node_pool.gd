extends GdUnitTestSuite

var _pools: Array[NodePool] = []

func _pool() -> NodePool:
    var pool := NodePool.new(func() -> Node: return Node.new())
    _pools.append(pool)
    return pool

func after_test() -> void:
    for pool: NodePool in _pools:
        pool.clear()
    _pools.clear()

func test_prewarm_creates_nodes_without_acquire() -> void:
    var pool := _pool()
    var made: int = pool.prewarm(3)
    assert_int(made).is_equal(3)
    assert_int(pool.created_count()).is_equal(3)
    assert_int(pool.free_count()).is_equal(3)
    assert_int(pool.active_count()).is_equal(0)

func test_prewarm_then_acquire_does_not_create_again() -> void:
    var pool := _pool()
    pool.prewarm(2)
    var node: Node = pool.acquire()
    assert_object(node).is_not_null()
    assert_int(pool.created_count()).is_equal(2)
    assert_int(pool.free_count()).is_equal(1)
    assert_int(pool.active_count()).is_equal(1)

func test_acquire_reuses_released_node() -> void:
    var pool := _pool()
    pool.prewarm(1)
    var first: Node = pool.acquire()
    pool.release(first)
    var second: Node = pool.acquire()
    # 原断言比较的是对象引用，用 is_same 保持语义（is_equal 会做属性深比较）
    assert_object(second).is_same(first)
    assert_int(pool.created_count()).is_equal(1)

func test_growth_disabled_returns_null_instead_of_instantiating() -> void:
    var pool := _pool()
    pool.set_allow_growth(false)
    assert_that(pool.acquire()).is_null()
    assert_int(pool.created_count()).is_equal(0)

func test_double_release_is_ignored() -> void:
    var pool := _pool()
    pool.prewarm(1)
    var node: Node = pool.acquire()
    pool.release(node)
    pool.release(node)
    assert_int(pool.free_count()).is_equal(1)
    assert_int(pool.active_count()).is_equal(0)
