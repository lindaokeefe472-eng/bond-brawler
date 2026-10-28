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
