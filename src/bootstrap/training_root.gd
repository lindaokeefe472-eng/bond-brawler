## 训练场：一个可换角色的玩家 + 一个不会动的站桩靶子。
##
## 为什么继承 GameRoot：训练场要复用的正是「组合根装配 → 场地 → 角色视图 → 定步长 tick」
## 这一整套，只有刷怪规则不同。所以只重写 _spawn_actors()，其余流程原样继承。
##
## 站桩的设计取舍：
##   - 不给 brain（brain_profile 传 null）→ AI 决策那一步直接跳过，它永远不会动、不会还手；
##   - 血量给得足够高 + 停手一会儿自动回满 → 靶子不会被打死，可以反复测同一招；
##   - 每帧钉在指定坐标 → 击退和推挤都推不走它，量出来的距离才是稳定的。
class_name TrainingRoot
extends GameRoot

const TRAINING_PLAYER_SPAWN: Vector2 = Vector2(-2.0, 0.0)
const DUMMY_SPAWN: Vector2 = Vector2(2.0, 0.0)
## 靶子血量：普通一套连招打不死，配合回满可以一直测。
const DUMMY_MAX_HP: float = 2000.0
## 停手多久后靶子回满血。太短看不清掉血，太长会打着打着没血。
const DUMMY_REFILL_DELAY: float = 1.5
## 每次按键挪动靶子的距离（米）。
const DUMMY_MOVE_STEP: float = 0.1
## 靶子离墙的最小间距，免得贴进墙里看不见。
const ARENA_EDGE_MARGIN: float = 1.0
const DEFAULT_PLAYER_CHARACTER: String = "knight"
const DEFAULT_DUMMY_CHARACTER: String = "orc"
## 靶子不带种族：无属性克制、无技能、攻击力 0，伤害数字才可比。
const DUMMY_STATS: Dictionary = {
	"max_hp": DUMMY_MAX_HP,
	"attack": 0.0,
	"defense": 0.0,
	"types": [],
}

## 角色列表来自素材清单，按 id 排序，Q/E 与 Z/C 在它上面循环。
var _characters: Array[String] = []
var _player_index: int = 0
var _dummy_index: int = 0
## 靶子相对 DUMMY_SPAWN 的偏移，由 [ ] 与 ; ' 调整。
var _dummy_offset: Vector2 = Vector2.ZERO
var _dummy_actor_id: int = 0
var _last_hit_distance: float = -1.0
var _total_damage: float = 0.0
var _hit_count: int = 0
## 上一次挨打的会话时间。回血按领域时钟算，不按真实帧时间 ——
## headless 下 _process 的 delta 接近 0，用它会算出一堆不可复现的结果。
var _last_damage_time: float = 0.0
var _panel: TrainingView = null

func _ready() -> void:
	super._ready()
	_build_panel()
	# 训练场没有「标题 → 开始」这一步：进来就该能打。
	if _flow != null and _flow.start() and _flow_view != null:
		_flow_view.render(_flow)
		_sync_hud_visibility()
	# 暂停时按 T 回主菜单。父类的标题界面按 T 是「进训练场」，两边互不干扰。
	if _flow_view != null:
		_flow_view.on_exit = _on_training_exit
	_refresh_panel()

func _build_panel() -> void:
	_panel = TrainingView.new()
	_panel.name = "TrainingPanel"
	add_child(_panel)

# ---------------------------------------------------------------- 刷怪
func _spawn_actors() -> void:
	_load_character_list()
	_player_index = _index_of(DEFAULT_PLAYER_CHARACTER)
	_dummy_index = _index_of(DEFAULT_DUMMY_CHARACTER)
	_spawn_player(TRAINING_PLAYER_SPAWN)
	_spawn_dummy()

func _load_character_list() -> void:
	_characters.clear()
	var raw: Variant = _manifest.get("characters", {})
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			_characters.append(str(key))
	_characters.sort()
	# 素材目录被仓库排除时也要能跑：至少留一个角色名，别让列表空着。
	if _characters.is_empty():
		_characters.append(DEFAULT_PLAYER_CHARACTER)

func _index_of(character_id: String) -> int:
	var index: int = _characters.find(character_id)
	return index if index >= 0 else 0

func _spawn_player(at: Vector2) -> void:
	_player_id = _session.spawn_actor(_build_spec(
			_species.starter(), GameConstants.FACTION_PLAYER, at, null, player_character()))
	var view: ActorView = _create_view(_player_id, player_character())
	if view != null and _camera != null:
		_camera.set_target(view)

func _spawn_dummy() -> void:
	var spec: Dictionary = _build_spec(
			{}, GameConstants.FACTION_ENEMY, _dummy_position(), null, dummy_character())
	spec["stats"] = DUMMY_STATS.duplicate(true)
	_dummy_actor_id = _session.spawn_actor(spec)
	_create_view(_dummy_actor_id, dummy_character())
	_last_damage_time = _session.time()

## 换角色必须重建 ActorRuntime：前伸、判定窗口、贴图路径都是建号时算进 spec 的。
func _respawn_player() -> void:
	var at: Vector2 = TRAINING_PLAYER_SPAWN
	var old: ActorRuntime = _session.get_actor(_player_id)
	if old != null:
		at = old.plane_pos
	_despawn(_player_id)
	_spawn_player(at)
	if _hud_presenter != null:
		_hud_presenter.set_player_id(_player_id)

func _respawn_dummy() -> void:
	_despawn(_dummy_actor_id)
	_spawn_dummy()
	_pin_dummy()

func _despawn(actor_id: int) -> void:
	if actor_id <= 0:
		return
	var view: ActorView = _views.get(actor_id, null) as ActorView
	_views.erase(actor_id)
	if _feedback != null:
		_feedback.unregister_actor_view(actor_id)
	if _tuner != null:
		_tuner.unregister(actor_id)
	if view != null and is_instance_valid(view):
		view.queue_free()
	if _session != null:
		_session.remove_actor(actor_id)

# ---------------------------------------------------------------- 选择与摆位
func player_character() -> String:
	if _characters.is_empty():
		return DEFAULT_PLAYER_CHARACTER
	return _characters[clampi(_player_index, 0, _characters.size() - 1)]

func dummy_character() -> String:
	if _characters.is_empty():
		return DEFAULT_DUMMY_CHARACTER
	return _characters[clampi(_dummy_index, 0, _characters.size() - 1)]

func cycle_player_character(step: int) -> void:
	if _characters.is_empty():
		return
	_player_index = wrapi(_player_index + step, 0, _characters.size())
	_respawn_player()

func cycle_dummy_character(step: int) -> void:
	if _characters.is_empty():
		return
	_dummy_index = wrapi(_dummy_index + step, 0, _characters.size())
	_respawn_dummy()

## 直接指定角色（调试脚本与用例用）。已经是该角色时返回 false，不重建。
func select_player_character(character_id: String) -> bool:
	var index: int = _characters.find(character_id)
	if index < 0 or index == _player_index:
		return false
	_player_index = index
	_respawn_player()
	return true

func select_dummy_character(character_id: String) -> bool:
	var index: int = _characters.find(character_id)
	if index < 0 or index == _dummy_index:
		return false
	_dummy_index = index
	_respawn_dummy()
	return true

func dummy_actor_id() -> int:
	return _dummy_actor_id

func _dummy_position() -> Vector2:
	var p: Vector2 = DUMMY_SPAWN + _dummy_offset
	var limit: float = GameConstants.ARENA_HALF_WIDTH - ARENA_EDGE_MARGIN
	p.x = clampf(p.x, -limit, limit)
	return PlaneMath.clamp_lane(p)

func move_dummy(dx: float, dy: float) -> void:
	_dummy_offset += Vector2(dx, dy)
	_pin_dummy()
	_refresh_panel()

func reset_dummy_position() -> void:
	_dummy_offset = Vector2.ZERO
	_pin_dummy()
	_refresh_panel()

func reset_stats() -> void:
	_last_hit_distance = -1.0
	_total_damage = 0.0
	_hit_count = 0
	_refresh_panel()

## 把靶子钉回指定坐标并转向玩家。击退和推挤都改不动它，量出来的距离才稳定。
func _pin_dummy() -> void:
	var dummy: ActorRuntime = _session.get_actor(_dummy_actor_id)
	if dummy == null or not dummy.is_alive():
		return
	var target: Vector2 = _dummy_position()
	dummy.plane_pos = target
	dummy.height = 0.0
	dummy.action.set_plane_pos(target)
	dummy.action.set_height(0.0)
	var player: ActorRuntime = _session.get_actor(_player_id)
	if player == null:
		return
	var facing: int = 1 if player.plane_pos.x >= target.x else -1
	dummy.facing = facing
	dummy.action.set_facing(facing)

# ---------------------------------------------------------------- 主循环
## 领域 tick 之后再钉一次靶子：动作机这一帧可能刚把它击退过。
func _sync_views() -> void:
	_tick_dummy()
	_pin_dummy()
	super._sync_views()

func _process(delta: float) -> void:
	super._process(delta)
	_refresh_panel()

## 停手一会儿就把血回满，靶子永远不会被打空。
func _tick_dummy() -> void:
	var dummy: ActorRuntime = _session.get_actor(_dummy_actor_id)
	if dummy == null or dummy.stats == null:
		return
	var max_hp: float = dummy.stats.max_hp()
	if dummy.stats.current_hp < max_hp \
			and _session.time() - _last_damage_time >= DUMMY_REFILL_DELAY:
		dummy.stats.heal(max_hp)
	# 兜底：万一被一击打死，换一个新的。训练场不该出现「靶子没了」。
	if not dummy.is_alive():
		_respawn_dummy()

# ---------------------------------------------------------------- 观测
## 给面板和用例读的一份纯数据。
func training_state() -> Dictionary:
	var player: ActorRuntime = _session.get_actor(_player_id)
	var dummy: ActorRuntime = _session.get_actor(_dummy_actor_id)
	var distance: float = -1.0
	var lane_delta: float = 0.0
	var would_hit: bool = false
	var reach: float = 0.0
	var lane_tolerance: float = 0.0
	var ranged: bool = player != null and player.is_ranged_attack()
	var projectile_range: float = 0.0
	if player != null:
		var cfg: Dictionary = player.melee_config()
		reach = float(cfg.get("range", 0.0))
		lane_tolerance = float(cfg.get("lane_tolerance", 0.0))
		if ranged:
			projectile_range = float(player.projectile_config().get("range", 0.0))
		if dummy != null:
			distance = PlaneMath.distance(player.plane_pos, dummy.plane_pos)
			lane_delta = dummy.plane_pos.y - player.plane_pos.y
			would_hit = _would_hit(player, dummy, cfg, ranged)
	return {
		"player_character": player_character(),
		"dummy_character": dummy_character(),
		"player_index": _player_index,
		"player_count": _characters.size(),
		"dummy_index": _dummy_index,
		"dummy_count": _characters.size(),
		"distance": distance,
		"lane_delta": lane_delta,
		"reach": reach,
		"lane_tolerance": lane_tolerance,
		"ranged": ranged,
		"projectile_range": projectile_range,
		"would_hit": would_hit,
		"last_hit_distance": _last_hit_distance,
		"total_damage": _total_damage,
		"hit_count": _hit_count,
	}

## 面板上的「判定」必须和真实结算用同一个谓词，否则调试工具本身就在骗人。
##   近战：PlaneMath.in_cone（和 CombatPipeline.resolve_melee 完全一致）
##   远程：弹体沿 x 轴直线飞，命中条件是「在正前方、射程内、横向偏移 < 命中半径 + 身位半径」
func _would_hit(player: ActorRuntime, dummy: ActorRuntime, cfg: Dictionary,
		ranged: bool) -> bool:
	if not ranged:
		return PlaneMath.in_cone(player.plane_pos, player.facing, dummy.plane_pos,
				float(cfg.get("range", 0.0)), float(cfg.get("half_arc", 0.0)))
	var pcfg: Dictionary = player.projectile_config()
	var forward: float = (dummy.plane_pos.x - player.plane_pos.x) * float(player.facing)
	var lateral: float = absf(dummy.plane_pos.y - player.plane_pos.y)
	var hit_width: float = float(pcfg.get("radius", Projectile.DEFAULT_RADIUS)) \
			+ GameConstants.BODY_RADIUS
	return forward >= 0.0 and forward <= float(pcfg.get("range", 0.0)) and lateral <= hit_width

## 记录「玩家打中靶子」时的真实距离 —— 这就是核对射程的第一手数据。
func _on_damage_applied(event: DomainEvent) -> void:
	super._on_damage_applied(event)
	if event == null:
		return
	var payload: Dictionary = event.payload
	if int(payload.get("target_id", 0)) != _dummy_actor_id:
		return
	if int(payload.get("attacker_id", 0)) != _player_id:
		return
	var player: ActorRuntime = _session.get_actor(_player_id)
	var dummy: ActorRuntime = _session.get_actor(_dummy_actor_id)
	if player == null or dummy == null:
		return
	_last_hit_distance = PlaneMath.distance(player.plane_pos, dummy.plane_pos)
	_total_damage += float(payload.get("amount", 0.0))
	_hit_count += 1
	_last_damage_time = _session.time()

func _refresh_panel() -> void:
	if _panel != null:
		_panel.render(training_state())

# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	# 微调模式下所有按键都归调参器，别在这里抢。
	if _tuner != null and _tuner.is_tuning():
		return
	match key.keycode:
		KEY_Q:
			cycle_player_character(-1)
		KEY_E:
			cycle_player_character(1)
		KEY_Z:
			cycle_dummy_character(-1)
		KEY_C:
			cycle_dummy_character(1)
		KEY_BRACKETLEFT:
			move_dummy(-DUMMY_MOVE_STEP, 0.0)
		KEY_BRACKETRIGHT:
			move_dummy(DUMMY_MOVE_STEP, 0.0)
		KEY_SEMICOLON:
			move_dummy(0.0, -DUMMY_MOVE_STEP)
		KEY_APOSTROPHE:
			move_dummy(0.0, DUMMY_MOVE_STEP)
		KEY_G:
			reset_dummy_position()
		KEY_H:
			reset_stats()
		_:
			return
	_refresh_panel()

func _on_training_exit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameRoot.MAIN_SCENE)
