## 弹体表现层：有贴图就用素材包的箭 / 法术图，没有才退回色块。
##
## 回归：素材包里一直有 Arrow(Projectile) 和 Magic(Projectile)，
## 但表现层从没接过它们，弓手射出去的是自己画的白方块。
extends GdUnitTestSuite

const ARROW_PATH: String = "res://assets/sprites/projectiles/arrow01.png"

func before(_do_skip := not FileAccess.file_exists(ARROW_PATH),
		_skip_reason := "需要本地 assets/sprites/projectiles/，见 README「数据与素材」") -> void:
	pass

func _manifest() -> Dictionary:
	return {"projectiles": {
		"arrow01": {"file": "arrow01.png", "frames": 1, "pixel_size": 0.0474},
	}}

func _shot(sprite: String) -> Projectile:
	return Projectile.create(1, GameConstants.FACTION_PLAYER, Vector2.ZERO, 1, {
		"speed": 10.0,
		"radius": 0.3,
		"damage_type": "neutral",
		"sprite": sprite,
	})

func test_configure_registers_the_arrow_sprite() -> void:
	var layer := ProjectileLayer.new()
	layer.configure(_manifest())
	assert_array(layer.known_sprites()).override_failure_message(
			"manifest 里有 arrow01，但表现层没认出来").contains(["arrow01"])
	layer.free()

func test_known_sprite_uses_the_atlas_texture() -> void:
	var layer := ProjectileLayer.new()
	layer.configure(_manifest())
	var items: Array[Projectile] = [_shot("arrow01")]
	layer.sync(items)
	assert_int(layer.active_views()).is_equal(1)
	var node: Sprite3D = layer.get_child(0) as Sprite3D
	assert_object(node).is_not_null()
	assert_object(node.texture).override_failure_message(
			"arrow01 没有贴上箭的贴图").is_not_null()
	assert_float(node.pixel_size).override_failure_message(
			"缩放应该用 manifest 给的 pixel_size").is_equal_approx(0.0474, 0.0001)
	assert_bool(node.modulate.is_equal_approx(Color.WHITE)).override_failure_message(
			"有贴图时不该再按属性染色").is_true()
	layer.free()

func test_unknown_sprite_falls_back_to_a_colored_block() -> void:
	var layer := ProjectileLayer.new()
	layer.configure(_manifest())
	var items: Array[Projectile] = [_shot("")]
	layer.sync(items)
	var node: Sprite3D = layer.get_child(0) as Sprite3D
	assert_object(node).is_not_null()
	assert_float(node.pixel_size).override_failure_message(
			"占位方块的边长应该由命中半径推出来").is_equal_approx(0.6, 0.01)
	assert_bool(node.modulate.is_equal_approx(Color.WHITE)).override_failure_message(
			"没有贴图时必须按属性染色，否则看不见").is_false()
	layer.free()

## 弹体消失后节点要还回池子，不然长时间放技能会一直 new 节点。
func test_released_projectile_is_reused() -> void:
	var layer := ProjectileLayer.new()
	layer.configure(_manifest())
	var first: Array[Projectile] = [_shot("arrow01")]
	layer.sync(first)
	assert_int(layer.get_child_count()).is_equal(1)
	layer.sync([] as Array[Projectile])
	assert_int(layer.active_views()).is_equal(0)
	var second: Array[Projectile] = [_shot("arrow01")]
	layer.sync(second)
	assert_int(layer.get_child_count()).override_failure_message(
			"新弹体应该复用池子里的节点").is_equal(1)
	layer.free()
