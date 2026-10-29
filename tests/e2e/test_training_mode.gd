## 训练场端到端：一个玩家 + 一个站桩靶子。
##
## 这一层守的是「调试工具本身别坏」：靶子必须真的不动、不还手、打不死，
## 换角色必须真的换掉前伸，挪靶子必须真的改变量出来的距离。
extends GdUnitTestSuite

const TRAINING_SCENE := "res://scenes/training.tscn"
const BOOT_FRAMES: int = 30
const IDLE_FRAMES: int = 180

## 场景同时依赖 data/ 与角色图集，两者都随仓库排除。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json") or not FileAccess.file_exists("res://assets/sprites/characters/knight/knight_idle.png"),
		_skip_reason := "需要本地 data/ 与 assets/sprites/，见 README「数据与素材」") -> void:
	pass

func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false

func test_training_boots_with_one_player_and_one_dummy() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var session: BattleSession = scene.get("_session")
	assert_int(session.actor_ids().size()).override_failure_message(
			"训练场只该有玩家 + 靶子两个人").is_equal(2)
	var dummy_id: int = int(scene.get("_dummy_actor_id"))
	assert_int(dummy_id).is_greater(0)
	assert_object(session.get_actor(dummy_id)).is_not_null()
	# 角色列表来自素材清单：数据驱动，不是写死的三个常量
	var state: Dictionary = scene.call("training_state")
	var manifest: Dictionary = scene.get("_manifest")
	assert_int(int(state["player_count"])).is_equal(manifest["characters"].size())

func test_training_starts_playing_without_title_screen() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var flow: SceneFlow = runner.scene().get("_flow")
	assert_object(flow).is_not_null()
	assert_int(flow.state()).override_failure_message(
			"训练场进来就该能打，不该停在标题界面").is_equal(SceneFlow.State.PLAYING)

## 站桩的核心契约：没有 AI、不移动、不还手。
func test_dummy_has_no_brain_and_never_acts() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var session: BattleSession = scene.get("_session")
	var dummy: ActorRuntime = session.get_actor(int(scene.get("_dummy_actor_id")))
	assert_object(dummy).is_not_null()
	assert_object(dummy.brain).override_failure_message("站桩不该挂 AI，否则它会走上来打人").is_null()

	var before: Vector2 = dummy.plane_pos
	var player: ActorRuntime = session.get_actor(int(scene.get("_player_id")))
	var hp_before: float = player.stats.current_hp
	await runner.simulate_frames(IDLE_FRAMES)

	assert_float(dummy.plane_pos.x).override_failure_message("站桩被推走了").is_equal_approx(before.x, 0.001)
	assert_float(dummy.plane_pos.y).override_failure_message("站桩被推走了").is_equal_approx(before.y, 0.001)
	assert_float(player.stats.current_hp).override_failure_message(
			"站桩还手了，玩家血量掉了").is_equal_approx(hp_before, 0.001)

## 换角色必须重建运行时：前伸来自每个角色自己的图集，不重建就还是旧值。
func test_switching_player_character_rebuilds_melee_reach() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var session: BattleSession = scene.get("_session")
	var before_id: int = int(scene.get("_player_id"))
	var before_reach: float = float(session.get_actor(before_id).melee_config()["range"])

	assert_bool(scene.call("select_player_character", "greatsword_skeleton")).is_true()
	await runner.simulate_frames(2)

	var after_id: int = int(scene.get("_player_id"))
	assert_int(after_id).is_not_equal(before_id)
	assert_object(session.get_actor(before_id)).override_failure_message(
			"旧角色没有从会话里移除，场上会多出一个人").is_null()

	var player: ActorRuntime = session.get_actor(after_id)
	assert_object(player).is_not_null()
	var expected: float = _expected_reach(scene, "greatsword_skeleton")
	assert_float(expected).override_failure_message("大剑角色在素材清单里该有更长的前伸").is_greater(before_reach)
	assert_float(float(player.melee_config()["range"])).override_failure_message(
			"换角色后前伸没跟着变，说明没有按新角色重建").is_equal_approx(expected, 0.01)

	var views: Dictionary = scene.get("_views")
	var view: ActorView = views.get(after_id, null) as ActorView
	assert_object(view).is_not_null()
	assert_str(view.character_id).is_equal("greatsword_skeleton")

## 挪靶子：距离要真的变，视图也要真的跟着挪。
func test_moving_dummy_changes_measured_distance() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var before: float = float(scene.call("training_state")["distance"])
	assert_float(before).is_greater(0.0)

	scene.call("move_dummy", 0.5, 0.0)
	await runner.simulate_frames(2)

	var after: float = float(scene.call("training_state")["distance"])
	assert_float(after).override_failure_message("靶子挪远了，但量出来的距离没变").is_greater(before)
	var views: Dictionary = scene.get("_views")
	var dummy_view: ActorView = views.get(int(scene.get("_dummy_actor_id")), null) as ActorView
	assert_object(dummy_view).is_not_null()
	assert_float(dummy_view.global_position.x).override_failure_message(
			"靶子的模型没跟着挪，看到的和量到的会脱节").is_equal_approx(2.5, 0.02)

## 面板上的「上次命中距离」就是核对射程的第一手数据，必须真的记下来。
func test_damage_on_dummy_records_hit_distance_and_total() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var session: BattleSession = scene.get("_session")
	var player_id: int = int(scene.get("_player_id"))
	var dummy_id: int = int(scene.get("_dummy_actor_id"))
	var dummy: ActorRuntime = session.get_actor(dummy_id)

	var req := CombatDamageRequest.new()
	req.attacker_id = player_id
	req.target_id = dummy_id
	req.power = 30.0
	dummy.take_hit(req)

	var state: Dictionary = scene.call("training_state")
	assert_int(int(state["hit_count"])).is_equal(1)
	assert_float(float(state["total_damage"])).is_greater(0.0)
	# 玩家在 -2、靶子在 +2
	assert_float(float(state["last_hit_distance"])).override_failure_message(
			"没有记录命中距离，面板上的核对数据就是假的").is_equal_approx(4.0, 0.05)

## 靶子打不死：血量足够高，被削到只剩 1 点仍然活着。
func test_dummy_cannot_be_killed_by_a_single_burst() -> void:
	var runner: GdUnitSceneRunner = scene_runner(TRAINING_SCENE)
	await runner.simulate_frames(BOOT_FRAMES)
	var scene: Node = runner.scene()
	var session: BattleSession = scene.get("_session")
	var dummy: ActorRuntime = session.get_actor(int(scene.get("_dummy_actor_id")))
	assert_object(dummy).is_not_null()
	assert_float(dummy.stats.max_hp()).override_failure_message(
			"靶子血量太低，一套连招就会把它打死").is_greater_equal(1000.0)
	dummy.stats.take_raw_damage(dummy.stats.max_hp() - 1.0)
	assert_bool(dummy.is_alive()).is_true()
	# 停手后要回满，否则反复测同一招时靶子会被打空
	await runner.simulate_frames(IDLE_FRAMES)
	assert_float(dummy.stats.current_hp).override_failure_message(
			"靶子没有自动回血，测几轮就没血了").is_equal_approx(dummy.stats.max_hp(), 0.5)

func _expected_reach(scene: Node, character_id: String) -> float:
	var manifest: Dictionary = scene.get("_manifest")
	var characters: Variant = manifest.get("characters", {})
	if not (characters is Dictionary):
		return 0.0
	var entry: Variant = (characters as Dictionary).get(character_id, {})
	if not (entry is Dictionary):
		return 0.0
	var overrides: Dictionary = scene.get("_melee_overrides")
	var raw_chars: Variant = overrides.get("characters", {})
	var override: Dictionary = {}
	if raw_chars is Dictionary:
		var raw: Variant = (raw_chars as Dictionary).get(character_id, {})
		if raw is Dictionary:
			override = raw
	return float(override.get("reach", (entry as Dictionary).get("melee_reach", 0.0)))
