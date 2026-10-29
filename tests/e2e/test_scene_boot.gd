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

## 起一局并直接进入 PLAYING —— 绝大多数用例关心的是战斗本身，不是标题界面。
func _boot() -> GdUnitSceneRunner:
	var runner: GdUnitSceneRunner = _boot_raw()
	var scene: Node = runner.scene()
	var flow: SceneFlow = scene.get("_flow")
	if flow != null:
		flow.start()
	return runner

## 停在标题界面，给流程用例用。
func _boot_raw() -> GdUnitSceneRunner:
	return scene_runner(MAIN_SCENE)

## 暂停会冻结整棵树；用例中途失败也必须解开，否则后面的用例全废。
func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false

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

## 微调器必须真的改到盒子，而且窄相跟着一起变 —— 否则「看到的」和「打得到的」又分家。
func test_hitbox_tuner_resizes_the_box() -> void:
	var runner := _boot()
	await runner.simulate_frames(SPAWN_FRAMES)
	var scene: Node = runner.scene()
	var tuner: HitboxTuner = scene.get_node_or_null("HitboxTuner") as HitboxTuner
	assert_object(tuner).is_not_null()
	var views: Dictionary = scene.get("_views")
	var pid: int = int(scene.get("_player_id"))
	var view: ActorView = views.get(pid, null) as ActorView
	assert_object(view).is_not_null()

	var before_width: float = _hitbox_box(view).size.x
	var before_range: float = float(view.runtime.melee_config()["range"])

	assert_bool(tuner.tune_actor(pid, &"range", 4.0)).override_failure_message(
			"微调器没有改动 range").is_true()

	var after_range: float = float(view.runtime.melee_config()["range"])
	var after_box: BoxShape3D = _hitbox_box(view)
	assert_float(after_range).is_greater(before_range)
	assert_float(after_box.size.x).override_failure_message(
			"range 变了但判定盒没跟着变，宽相会和窄相脱节").is_greater(before_width)
	# 前沿必须始终 = range + margin
	var hitbox: Area3D = view.get_node_or_null("Hitbox") as Area3D
	var margin: float = float(view.runtime.melee_config()["margin"])
	assert_float(hitbox.position.x + after_box.size.x * 0.5).is_equal_approx(after_range + margin, 0.01)

func _hitbox_box(view: ActorView) -> BoxShape3D:
	var hitbox: Area3D = view.get_node_or_null("Hitbox") as Area3D
	var shape_node: CollisionShape3D = hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return shape_node.shape as BoxShape3D

## 回归：所有角色共用一个 reach。主角剑长显得刚好，兽人斧子短，
## 判定盒就明显超出去一截 —— 每个角色的前伸必须来自它自己的图集。
func test_melee_reach_comes_from_the_character_art() -> void:
	var runner := _boot()
	await runner.simulate_frames(SPAWN_FRAMES)
	var scene: Node = runner.scene()
	var manifest: Dictionary = scene.get("_manifest")
	var views: Dictionary = scene.get("_views")
	var checked: int = 0
	for key: Variant in views.keys():
		var view: ActorView = views[key] as ActorView
		var characters: Dictionary = manifest["characters"]
		if not characters.has(view.character_id):
			continue
		var entry: Dictionary = characters[view.character_id]
		# data/melee.json 的手改值优先，没有才用图集算出来的值
		var override: Dictionary = _melee_override(scene, view.character_id)
		var expected: float = float(override.get("reach", entry.get("melee_reach", 0.0)))
		if expected <= 0.0:
			continue
		var actual: float = float(view.runtime.melee_config()["range"])
		assert_float(actual).override_failure_message(
				"%s 的 reach 没跟着图集走（期望 %.2f，实际 %.2f）" % [view.character_id, expected, actual]
			).is_equal_approx(expected, 0.01)
		checked += 1
	assert_int(checked).is_greater_equal(2)

func _melee_override(scene: Node, character_id: String) -> Dictionary:
	var overrides: Dictionary = scene.get("_melee_overrides")
	var characters: Variant = overrides.get("characters", {})
	if not (characters is Dictionary):
		return {}
	var entry: Variant = (characters as Dictionary).get(character_id, {})
	return entry if entry is Dictionary else {}

## HUD 必须反映真实状态：快照里要有玩家和敌人，血条比例要跟着掉血走。
func test_hud_reflects_player_and_enemies() -> void:
	var runner := _boot()
	await runner.simulate_frames(SPAWN_FRAMES)
	var scene: Node = runner.scene()
	var presenter: HudPresenter = scene.get("_hud_presenter")
	assert_object(presenter).is_not_null()
	var pid: int = int(scene.get("_player_id"))
	assert_int(presenter.model.entries().size()).override_failure_message(
			"HUD 至少要有玩家 + 敌人两个条目").is_greater_equal(2)
	var before: float = _hud_hp_ratio(presenter, pid)
	assert_float(before).is_greater(0.0)
	var runtime: ActorRuntime = scene.get("_session").get_actor(pid)
	runtime.stats.take_raw_damage(50.0)
	await runner.simulate_frames(5)
	var after: float = _hud_hp_ratio(presenter, pid)
	assert_float(after).override_failure_message("掉血了但 HUD 血条没动").is_less(before)

func _hud_hp_ratio(presenter: HudPresenter, actor_id: int) -> float:
	for raw: Variant in presenter.model.entries():
		var entry: Dictionary = raw
		if int(entry.get("id", 0)) == actor_id:
			return float(entry.get("hp_ratio", 0.0))
	return -1.0

## 流程：标题 -> 开局 -> 暂停 -> 继续 -> 死亡 -> 结算。
## 关键不变量：暂停期间领域时钟必须停住，否则「暂停」只是画面停住、后台照打。
func test_scene_flow_pause_freezes_domain_clock() -> void:
	var runner: GdUnitSceneRunner = _boot_raw()
	await runner.simulate_frames(SPAWN_FRAMES)
	var scene: Node = runner.scene()
	var flow: SceneFlow = scene.get("_flow")
	assert_object(flow).is_not_null()
	assert_int(flow.state()).override_failure_message("应该从标题开始").is_equal(SceneFlow.State.TITLE)

	var session: BattleSession = scene.get("_session")
	var t0: float = session.time()
	await runner.simulate_frames(10)
	assert_float(session.time()).override_failure_message(
			"标题界面不该推进战斗").is_equal_approx(t0, 0.0001)

	assert_bool(flow.start()).is_true()
	await runner.simulate_frames(10)
	var t1: float = session.time()
	assert_float(t1).override_failure_message("开局后时钟要走").is_greater(t0)

	assert_bool(flow.pause()).is_true()
	get_tree().paused = true
	await runner.simulate_frames(10)
	assert_float(session.time()).override_failure_message(
			"暂停期间领域时钟不能推进").is_equal_approx(t1, 0.0001)

	assert_bool(flow.resume()).is_true()
	get_tree().paused = false
	await runner.simulate_frames(10)
	assert_float(session.time()).is_greater(t1)

	assert_bool(flow.finish(false)).is_true()
	assert_int(flow.state()).is_equal(SceneFlow.State.RESULT)
	assert_bool(flow.is_playing()).is_false()

## 音效链路：伤害事件必须真的落到 AudioDirector 上，而不是只在 FeedbackDirector 里计数。
func test_damage_reaches_audio_director() -> void:
	var runner := _boot()
	await runner.simulate_frames(SPAWN_FRAMES)
	var scene: Node = runner.scene()
	var audio: AudioDirector = scene.get("_audio")
	assert_object(audio).is_not_null()
	var before: int = audio.play_count()
	var session: BattleSession = scene.get("_session")
	var pid: int = int(scene.get("_player_id"))
	var enemy_id: int = 0
	for id: int in session.actor_ids():
		if id != pid:
			enemy_id = id
			break
	assert_int(enemy_id).is_greater(0)
	var player: ActorRuntime = session.get_actor(pid)
	var request := CombatDamageRequest.new()
	request.attacker_id = enemy_id
	request.target_id = pid
	request.power = 10.0
	player.take_hit(request)
	await runner.simulate_frames(3)
	assert_int(audio.play_count()).override_failure_message(
			"伤害事件没有传到 AudioDirector，音效链路是断的").is_greater(before)
