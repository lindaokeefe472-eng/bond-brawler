## 弹体管理器：齐射排期、推进、命中回调、回收。
extends GdUnitTestSuite

## 只暴露命中判定需要的字段，避免测试为了一个弹体去装配整个 ActorRuntime。
class FakeTarget extends RefCounted:
	var id: int = 0
	var faction: StringName = GameConstants.FACTION_ENEMY
	var plane_pos: Vector2 = Vector2.ZERO
	var alive: bool = true

	func is_alive() -> bool:
		return alive

func _payload(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"owner_id": 1,
		"origin": Vector2.ZERO,
		"facing": 1,
		"count": 1,
		"speed": 10.0,
		"spread": 0.0,
		"power": 30.0,
		"damage_type": &"fire",
		"knockback": 1.0,
		"piercing": false,
		"lifetime": 1.0,
		"interval": 0.0,
		"range": 20.0,
	}
	for key: Variant in extra.keys():
		out[key] = extra[key]
	return out

func _targets() -> Dictionary:
	var one := FakeTarget.new()
	one.id = 2
	one.plane_pos = Vector2(0.5, 0.0)
	var two := FakeTarget.new()
	two.id = 3
	two.plane_pos = Vector2(5.0, 0.0)
	return {2: one, 3: two}

func _noop() -> Callable:
	return func(_p: Projectile, _t: Variant) -> Variant: return null

func test_spawn_from_payload_creates_one_projectile() -> void:
	var sys := ProjectileSystem.new()
	assert_int(sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, _payload())).is_equal(1)
	assert_int(sys.items().size()).is_equal(1)

func test_volley_spawns_shots_on_interval() -> void:
	var sys := ProjectileSystem.new()
	var payload: Dictionary = _payload({"count": 3, "interval": 0.1})
	sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, payload)
	assert_int(sys.items().size()).is_equal(1)
	sys.tick(0.05, {}, _noop())
	assert_int(sys.items().size()).is_equal(1)
	sys.tick(0.06, {}, _noop())
	assert_int(sys.items().size()).is_equal(2)
	sys.tick(0.1, {}, _noop())
	assert_int(sys.items().size()).is_equal(3)

func test_tick_moves_projectiles() -> void:
	var sys := ProjectileSystem.new()
	sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, _payload({"count": 1}))
	# 把目标挪远，先只看移动
	sys.tick(0.2, {}, _noop())
	assert_float(sys.items()[0].plane_pos.x).is_equal_approx(2.0, 0.001)

func test_hit_calls_sink_and_kills_projectile() -> void:
	var sys := ProjectileSystem.new()
	sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, _payload())
	var hit_ids: Array[int] = []
	var sink: Callable = func(_p: Projectile, target: Variant) -> Variant:
		hit_ids.append(int(target.id))
		return "hit"
	var results: Array = sys.tick(0.01, _targets(), sink)
	assert_array(hit_ids).contains_exactly([2])
	assert_int(results.size()).is_equal(1)
	assert_int(sys.items().size()).is_equal(0)

func test_own_faction_is_never_hit() -> void:
	var sys := ProjectileSystem.new()
	sys.spawn_from_payload(1, GameConstants.FACTION_ENEMY, _payload())
	var targets: Dictionary = _targets()
	var hit_ids: Array[int] = []
	var sink: Callable = func(_p: Projectile, target: Variant) -> Variant:
		hit_ids.append(int(target.id))
		return null
	sys.tick(0.01, targets, sink)
	# 两个目标都是敌方阵营，和弹体同阵营 -> 一发都不该命中
	assert_array(hit_ids).is_empty()

func test_expired_projectiles_are_recycled() -> void:
	var sys := ProjectileSystem.new()
	sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, _payload({"lifetime": 0.5}))
	sys.tick(0.6, {}, _noop())
	assert_int(sys.items().size()).is_equal(0)

func test_out_of_bounds_is_recycled() -> void:
	var sys := ProjectileSystem.new()
	sys.bounds_x = 5.0
	sys.spawn_from_payload(1, GameConstants.FACTION_PLAYER, _payload({"speed": 20.0}))
	sys.tick(0.1, {}, _noop())
	assert_int(sys.items().size()).is_equal(1)
	sys.tick(0.2, {}, _noop())
	assert_int(sys.items().size()).is_equal(0)
