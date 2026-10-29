## 场景层端到端：真的把 main.tscn 跑起来，验证组合根装配、角色视图、相机、
## 以及「敌人 AI 推进 -> 出手 -> 窄相命中 -> 扣血」在场景里也成立。
##
## 这一层补的是领域 e2e 覆盖不到的东西：节点装配、Sprite3D 贴图、相机跟随。
extends GdUnitTestSuite

## 场景端到端同时依赖 data/ 与角色图集，两者都随仓库排除。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json") or not FileAccess.file_exists("res://assets/sprites/characters/knight/knight_idle.png"),
        _skip_reason := "需要本地 data/ 与 assets/sprites/，见 README「数据与素材」") -> void:
    pass

const MAIN_SCENE := "res://scenes/main.tscn"
const SPAWN_FRAMES: int = 40
const COMBAT_FRAMES: int = 360

func _boot() -> GdUnitSceneRunner:
    return scene_runner(MAIN_SCENE)

func test_scene_boots_and_spawns_all_actors() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var scene: Node = runner.scene()
    assert_object(scene).is_not_null()
    var session: Variant = scene.get("_session")
    assert_object(session).is_not_null()
    # 1 个玩家 + 3 个敌人
    assert_int(session.actor_ids().size()).is_equal(4)

func test_every_actor_has_a_textured_sprite() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var sprites: Array[Node] = runner.scene().find_children("*", "Sprite3D", true, false)
    assert_int(sprites.size()).is_equal(4)
    for node: Node in sprites:
        var sprite: Sprite3D = node as Sprite3D
        assert_object(sprite.texture).override_failure_message(
            "%s 没有贴图，说明 manifest 或资源路径有问题" % sprite.get_path()).is_not_null()
        assert_float(sprite.pixel_size).override_failure_message(
            "%s 的 pixel_size 未从 manifest 应用，角色会变成小点" % sprite.get_path()).is_greater(0.001)

func test_camera_follows_player() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var cameras: Array[Node] = runner.scene().find_children("*", "Camera3D", true, false)
    assert_int(cameras.size()).is_equal(1)
    var camera: Camera3D = cameras[0] as Camera3D
    assert_bool(camera.current).is_true()

func test_enemies_damage_idle_player_in_scene() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var scene: Node = runner.scene()
    var session: Variant = scene.get("_session")
    var player_id: int = int(scene.get("_player_id"))
    var before: float = session.get_actor(player_id).stats.current_hp
    # 玩家完全不操作，敌人应当主动压上来并打中
    await runner.simulate_frames(COMBAT_FRAMES)
    var after: float = session.get_actor(player_id).stats.current_hp
    assert_float(after).override_failure_message(
        "玩家挂机 6 秒后血量没有下降，说明 AI 推进或命中链路在场景层断了").is_less(before)

## 宽相必须真的在报候选，否则 Area3D 就是摆设。
## 回归：判定盒的尺寸与位置必须由近战参数推导，和窄相同源。
## 修之前形状写死在 actor_view.tscn（2.4 x 1.6 x 1.8），领域层用另一套 range，
## 结果出现 2.67 m 的「隔空命中」。
func test_hitbox_geometry_matches_melee_config() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var scene: Node = runner.scene()
    var views: Dictionary = scene.get("_views")
    var pid: int = int(scene.get("_player_id"))
    var view: Node = views.get(pid, null)
    assert_object(view).is_not_null()

    var hitbox: Area3D = view.get_node_or_null("Hitbox") as Area3D
    var shape_node: CollisionShape3D = hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
    assert_object(shape_node).is_not_null()
    var box: BoxShape3D = shape_node.shape as BoxShape3D
    assert_object(box).is_not_null()

    var cfg: Dictionary = view.get("runtime").melee_config()
    var reach: float = float(cfg.get("range", 0.0))
    var lane: float = float(cfg.get("lane_tolerance", 0.0))
    var height: float = float(cfg.get("hit_height", 0.0))
    var margin: float = GameConstants.HITBOX_MARGIN
    var body: float = GameConstants.BODY_RADIUS

    assert_float(box.size.x).override_failure_message("x 轴尺寸应覆盖身后 body 到身前 reach").is_equal_approx(
            reach + body + margin * 2.0, 0.01)
    assert_float(box.size.z).override_failure_message("z 轴尺寸应覆盖纵深容差").is_equal_approx(
            lane * 2.0 + margin * 2.0, 0.01)
    # y 只在顶部留 margin：底面必须贴地，不能钻到地板下面
    assert_float(box.size.y).override_failure_message("y 轴尺寸应覆盖命中高度").is_equal_approx(
            height + margin, 0.01)
    # 盒子前沿 = reach + margin：再多就「隔空打人」，再少就漏判
    assert_float(hitbox.position.x + box.size.x * 0.5).override_failure_message(
            "判定盒前沿与 reach 不一致，视觉与判定会脱节").is_equal_approx(reach + margin, 0.01)

## 判定盒必须从脚底开始。回归：形状节点在 .tscn 里带 (0, 0.9, 0)，Area 又被设到
## hit_height/2，两处偏移叠加后盒子中心跑到 1.76 m —— 整个浮在头顶上方，
## 打得到人却看起来完全没对上角色。
func test_hitbox_starts_at_the_feet() -> void:
    var runner := _boot()
    await runner.simulate_frames(SPAWN_FRAMES)
    var scene: Node = runner.scene()
    var views: Dictionary = scene.get("_views")
    var pid: int = int(scene.get("_player_id"))
    var view: Node = views.get(pid, null)
    assert_object(view).is_not_null()

    var hitbox: Area3D = view.get_node_or_null("Hitbox") as Area3D
    assert_object(hitbox).is_not_null()
    var shape_node: CollisionShape3D = hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
    assert_object(shape_node).is_not_null()
    var box: BoxShape3D = shape_node.shape as BoxShape3D
    assert_object(box).is_not_null()

    assert_float(shape_node.position.y).override_failure_message(
            "形状节点自带 y 偏移会和 Area3D 的中心叠加，盒子会浮到头顶").is_equal_approx(0.0, 0.001)
    var bottom: float = hitbox.position.y - box.size.y * 0.5
    assert_float(bottom).override_failure_message(
            "判定盒底面离地 %.2f m，应该贴着脚底" % bottom).is_equal_approx(0.0, 0.02)
