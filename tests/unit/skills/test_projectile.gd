## 弹体领域模型：移动、过期、穿透、阵营过滤。
##
## 为什么这些规则必须能脱离引擎单测：命中判定是玩法契约，一旦被物理引擎的
## 帧延迟或碰撞层配置影响，就会出现「看得见打不到」这种最难查的问题。
extends GdUnitTestSuite

const ENEMY: StringName = GameConstants.FACTION_ENEMY
const PLAYER: StringName = GameConstants.FACTION_PLAYER

func _config(extra: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = {
		"speed": 10.0,
		"range": 20.0,
		"power": 40.0,
		"damage_type": &"fire",
		"knockback": 3.0,
		"radius": 0.4,
	}
	for key: Variant in extra.keys():
		cfg[key] = extra[key]
	return cfg

func _shot(facing: int = 1, extra: Dictionary = {}) -> Projectile:
	return Projectile.create(1, PLAYER, Vector2.ZERO, facing, _config(extra))

func test_create_points_velocity_along_facing() -> void:
	var right: Projectile = _shot(1)
	assert_float(right.velocity.x).is_equal_approx(10.0, 0.001)
	assert_float(right.velocity.y).is_equal_approx(0.0, 0.001)
	var left: Projectile = _shot(-1)
	assert_float(left.velocity.x).is_equal_approx(-10.0, 0.001)

func test_lifetime_derived_from_range_when_missing() -> void:
	var shot: Projectile = _shot(1)
	# range 20 / speed 10 = 2 秒
	assert_float(shot.lifetime).is_equal_approx(2.0, 0.001)

func test_step_moves_along_velocity() -> void:
	var shot: Projectile = _shot(1)
	shot.step(0.5)
	assert_float(shot.plane_pos.x).is_equal_approx(5.0, 0.001)
	assert_bool(shot.alive).is_true()

func test_expires_after_lifetime() -> void:
	var shot: Projectile = _shot(1)
	shot.step(2.5)
	assert_bool(shot.alive).is_false()

func test_cannot_hit_own_faction() -> void:
	var shot: Projectile = _shot(1)
	assert_bool(shot.can_hit(2, PLAYER, Vector2(0.1, 0.0))).is_false()

func test_can_hit_enemy_inside_radius() -> void:
	var shot: Projectile = _shot(1)
	assert_bool(shot.can_hit(2, ENEMY, Vector2(0.3, 0.0))).is_true()
	assert_bool(shot.can_hit(2, ENEMY, Vector2(3.0, 0.0))).is_false()

func test_cannot_hit_same_target_twice() -> void:
	var shot: Projectile = _shot(1, {"piercing": true})
	assert_bool(shot.register_hit(2)).is_true()
	assert_bool(shot.can_hit(2, ENEMY, Vector2(0.1, 0.0))).is_false()
	assert_bool(shot.can_hit(3, ENEMY, Vector2(0.1, 0.0))).is_true()

func test_piercing_survives_first_hit() -> void:
	var shot: Projectile = _shot(1, {"piercing": true})
	assert_bool(shot.register_hit(2)).is_true()
	assert_bool(shot.alive).is_true()

func test_non_piercing_dies_on_first_hit() -> void:
	var shot: Projectile = _shot(1)
	assert_bool(shot.register_hit(2)).is_false()
	assert_bool(shot.alive).is_false()

func test_dead_projectile_hits_nothing() -> void:
	var shot: Projectile = _shot(1)
	shot.alive = false
	assert_bool(shot.can_hit(2, ENEMY, Vector2.ZERO)).is_false()
