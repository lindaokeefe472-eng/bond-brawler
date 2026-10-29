## 一场战斗的编排根：持有全部 ActorRuntime，并按固定顺序把各上下文的 tick 串起来。
##
## 这里是唯一允许「知道所有上下文」的地方，因此它只做顺序编排与依赖注入，
## 不放任何数值规则：伤害数字来自 combat，命中几何来自 PlaneMath，AI 决策来自 ai。
## 只要保持 tick 的顺序稳定，整局就可以用「输入 + 随机种子」完整回放。
class_name BattleSession
extends RefCounted

# ---------------------------------------------------------------- 服务键
## services 字典的键。用常量而不是裸字符串，避免调用方拼错时静默降级。
const SERVICE_BUS: StringName = &"bus"
const SERVICE_RNG: StringName = &"rng"
const SERVICE_DAMAGE_CALCULATOR: StringName = &"damage_calculator"
const SERVICE_TYPE_CHART: StringName = &"type_chart"
const SERVICE_WAVE_SPAWNER: StringName = &"wave_spawner"
const SERVICE_SPECIES: StringName = &"species"

## AI 想走到某个点时的死区：太小会让角色在目标点附近抖，太大又走不到。
const AI_MOVE_DEADZONE: float = 0.1
## 距离比较的浮点容差；同距时按 actor_id 裁决，保证决策可复现。
const DISTANCE_EPSILON: float = 0.000001

var _bus: DomainEventBus = null
var _rng: IRng = null
var _calculator: CombatDamageCalculator = null
var _pipeline: CombatPipeline = null
var _projectiles: ProjectileSystem = null
## 本帧由宽相（Area3D）给出的候选：{attacker_id: Array[int]}。空字典 = 不做过滤。
var _broadphase: Dictionary = {}
var _waves: StageWaveSpawner = null
var _species: Dictionary = {}

var _actors: Dictionary = {}
var _next_id: int = 1
var _time: float = 0.0

## 上一帧 AI 决策产出的输入，下一帧动作机消费。
var _ai_inputs: Dictionary = {}
## 上一帧的意图，供调试面板/测试查询。
var _intents: Dictionary = {}
## 由波次生成器生成的 actor，死亡时只向生成器回报这些，避免误减存活计数。
var _wave_actors: Dictionary = {}
var _dead_reported: Dictionary = {}

func _init(services: Dictionary = {}) -> void:
	_bus = services.get(SERVICE_BUS, null)
	_rng = services.get(SERVICE_RNG, null)
	_waves = services.get(SERVICE_WAVE_SPAWNER, null)
	var raw_species: Variant = services.get(SERVICE_SPECIES, {})
	if raw_species is Dictionary:
		_species = raw_species

	_calculator = services.get(SERVICE_DAMAGE_CALCULATOR, null)
	if _calculator == null:
		var chart: CombatTypeChart = services.get(SERVICE_TYPE_CHART, null)
		# 组合根没提供结算器时，用空克制表兜底：伤害公式仍可用，只是没有属性倍率。
		_calculator = CombatDamageCalculator.new(chart, _rng)
	_pipeline = CombatPipeline.new(_bus, _rng)
	# 弹体走独立流水线；管线只负责把「生成」这个事件转过来。
	_projectiles = ProjectileSystem.new()
	_projectiles.bounds_x = GameConstants.ARENA_HALF_WIDTH
	_pipeline.projectile_sink = _on_projectile_spawned

# ------------------------------------------------------------------ 角色管理
## 从 spec 建一个 ActorRuntime。spec 字段：
##   species_id / faction / plane_pos / stats / skills / brain_profile / melee / action_profile
## 可选 id 用于读档时恢复原 id；不传则自增分配。
func spawn_actor(spec: Dictionary) -> int:
	var requested: int = int(spec.get("id", 0))
	var actor_id: int = requested
	if actor_id <= 0 or _actors.has(actor_id):
		actor_id = _next_id
	_next_id = maxi(_next_id, actor_id + 1)

	var actor := ActorRuntime.new(actor_id, spec, _bus, _calculator, _rng)
	actor.stats_provider = _make_stats_provider()
	_actors[actor_id] = actor

	_emit(GameConstants.EVT_ACTOR_SPAWNED, {
		"actor_id": actor_id,
		"faction": actor.faction,
		"species_id": StringName(str(spec.get("species_id", ""))),
		"plane_pos": actor.plane_pos,
	})
	return actor_id

func remove_actor(id: int) -> void:
	_actors.erase(id)
	_ai_inputs.erase(id)
	_intents.erase(id)
	_wave_actors.erase(id)
	_dead_reported.erase(id)

func get_actor(id: int) -> ActorRuntime:
	return _actors.get(id, null)

func actor_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: Variant in _actors.keys():
		ids.append(int(key))
	ids.sort()
	return ids

func time() -> float:
	return _time

## 最近一次 AI 决策；没有脑子的角色返回 null。调试面板用。
func intent_for(actor_id: int) -> AiIntent:
	return _intents.get(actor_id, null)

# ------------------------------------------------------------------ 主循环
## 固定顺序：玩家输入 -> 动作机 -> AI 决策 -> 技能相位 -> 命中结算 -> 状态结算 -> 波次。
## 顺序本身就是契约：AI 在动作机之后决策，所以意图下一帧才生效，不会和玩家抢同一帧的输入。
## broadphase: {attacker_id: Array[int]}，由表现层的 Area3D 宽相提供。
## 不传时退化为全量扫描，领域层不依赖物理是否存在。
func tick(dt: float, inputs: Dictionary = {}, broadphase: Dictionary = {}) -> void:
	var step: float = maxf(dt, 0.0)
	if step <= 0.0:
		return
	_time += step
	_broadphase = broadphase
	var ids: Array[int] = actor_ids()

	# 1. 玩家输入：显式输入优先；AI 角色沿用上一帧决策产出的输入。
	var frames: Dictionary = {}
	for actor_id: int in ids:
		var frame: LocoInputFrame = null
		var explicit: Variant = inputs.get(actor_id, null)
		if explicit is LocoInputFrame:
			frame = explicit
		else:
			var ai_frame: Variant = _ai_inputs.get(actor_id, null)
			if ai_frame is LocoInputFrame:
				frame = ai_frame
		frames[actor_id] = frame if frame != null else LocoInputFrame.empty()

	# 2. 动作机（含资源回复与普攻 ACTIVE 窗口标记）
	for actor_id: int in ids:
		var actor: ActorRuntime = _actors[actor_id]
		actor.tick_action(step, frames[actor_id])

	# 3. AI 决策：产出意图与下一帧输入，技能意图在此刻起手
	_run_ai(step)

	# 4. 技能相位：冷却/充能/前摇推进，进入 ACTIVE 时记录激活
	for actor_id: int in ids:
		var actor: ActorRuntime = _actors[actor_id]
		actor.tick_skill(step)

	# 5. 命中结算：普攻与技能都在这里转成真实伤害
	_resolve_hits()

	# 5.5 弹体：齐射排期 -> 移动 -> 命中 -> 回收。
	# 放在技能激活之后，保证「这一帧刚放出去的弹体」不会立刻结算到目标身上。
	_projectiles.tick(step, _actors, _apply_projectile_hit)

	# 6. 状态结算：推进异常状态时长并发过期事件
	for actor_id: int in ids:
		var actor: ActorRuntime = _actors[actor_id]
		actor.tick_status(step)

	# 7. 波次：回报死亡、推进生成器、把待生成请求变成真实角色
	_tick_waves(step)

# ------------------------------------------------------------------ AI
func _run_ai(dt: float) -> void:
	for actor_id: int in actor_ids():
		var actor: ActorRuntime = _actors[actor_id]
		if actor.brain == null or not actor.is_alive():
			_ai_inputs.erase(actor_id)
			continue
		var target: ActorRuntime = _nearest_enemy(actor)
		if target == null:
			_ai_inputs.erase(actor_id)
			continue

		var blackboard := AiPerception.observe(
				actor.id, actor.plane_pos, actor.hp_ratio(),
				target.id, target.plane_pos, target.hp_ratio(),
				target.is_guarding(), actor.skills_ready(), _time)
		var intent: AiIntent = actor.brain.tick(dt, blackboard)
		_intents[actor_id] = intent

		# 意图事件是调试面板/录像的唯一观测口，必须每帧都发。
		_emit(GameConstants.EVT_INTENT_EMITTED, {
			"actor_id": actor_id,
			"kind": intent.kind,
			"target_id": intent.target_id,
			"skill_slot": intent.skill_slot,
			"desired_pos": intent.desired_pos,
		})

		if intent.kind == AiIntent.SKILL and intent.skill_slot >= 0:
			# 起手失败（能量不足/冷却）不需要回滚：下一帧 AI 会重新评估。
			actor.try_cast_skill(intent.skill_slot, target.plane_pos)
		_ai_inputs[actor_id] = _intent_to_frame(actor, intent)

func _nearest_enemy(actor: ActorRuntime) -> ActorRuntime:
	var best: ActorRuntime = null
	var best_distance: float = INF
	for other_id: int in actor_ids():
		var other: ActorRuntime = _actors[other_id]
		if other == null or other.id == actor.id or not other.is_alive():
			continue
		if other.faction == actor.faction:
			continue
		var distance: float = PlaneMath.distance(actor.plane_pos, other.plane_pos)
		if distance < best_distance - DISTANCE_EPSILON:
			best = other
			best_distance = distance
		elif absf(distance - best_distance) <= DISTANCE_EPSILON \
				and (best == null or other.id < best.id):
			# 同距时取小 id，避免 Dictionary 遍历顺序影响回放。
			best = other
	return best

## 意图 -> 一帧输入。这里只做「翻译」，不重新决策。
func _intent_to_frame(actor: ActorRuntime, intent: AiIntent) -> LocoInputFrame:
	var frame := LocoInputFrame.empty()
	match intent.kind:
		AiIntent.APPROACH, AiIntent.RETREAT, AiIntent.REPOSITION:
			var delta: Vector2 = intent.desired_pos - actor.plane_pos
			if delta.length() > AI_MOVE_DEADZONE:
				frame.move = delta.normalized()
		AiIntent.ATTACK:
			# 只在能起手的动作状态里「按下」；攻击期间保持 false，
			# 动作机才能在下一次回到 IDLE 时看到新的上升沿，形成连续攻击。
			if _can_press_attack(actor):
				frame.attack = true
		AiIntent.GUARD:
			frame.guard = true
	return frame

func _can_press_attack(actor: ActorRuntime) -> bool:
	match actor.action.current_state():
		LocoActionState.IDLE, LocoActionState.RUN, LocoActionState.LAND, \
				LocoActionState.JUMP, LocoActionState.FALL:
			return true
	return false

# ------------------------------------------------------------------ 命中结算
func _resolve_hits() -> void:
	for actor_id: int in actor_ids():
		var actor: ActorRuntime = _actors[actor_id]
		if not actor.is_alive():
			continue
		var activation: Dictionary = actor.consume_skill_activation()
		if not activation.is_empty():
			_pipeline.resolve_skill(activation, _actors)
		# 边沿：开新一次挥击，清空已命中集合。
		if actor.consume_attack_activation():
			actor.begin_attack_swing()
			# 远程段在起手那一帧放一发弹体，整段 ACTIVE 不再做命中判定。
			if actor.is_ranged_attack():
				_fire_basic_projectile(actor)
		# 整个 ACTIVE 窗口每帧都判：盒子亮着的时候就是真能打到的时候。
		# 近战扇形和绕身范围都走这一条，形态由 attack_config 的 kind 决定。
		if actor.is_attack_active() and not actor.is_ranged_attack():
			_pipeline.resolve_basic_attack(actor, _actors, actor.attack_config(),
					_broadphase.get(actor.id, null), actor.attack_hit_ids())

## 普攻弹体：和技能弹体走同一条流水线，命中结算、顿帧、跳字、音效全部复用。
## 威力仍然按「攻击力 × 倍率」算，和近战普攻同一个口径。
func _fire_basic_projectile(actor: ActorRuntime) -> void:
	if actor.stats == null:
		return
	var cfg: Dictionary = actor.projectile_config()
	var origin: Vector2 = actor.plane_pos \
			+ Vector2(float(actor.facing) * GameConstants.BODY_RADIUS, 0.0)
	_projectiles.spawn_from_payload(actor.id, actor.faction, {
		"origin": origin,
		"facing": actor.facing,
		"count": 1,
		"speed": float(cfg.get("speed", 0.0)),
		"power": actor.stats.value(&"attack") * float(cfg.get("power_ratio", 1.0)),
		"damage_type": cfg.get("damage_type", &"neutral"),
		"knockback": float(cfg.get("knockback", 0.0)),
		"range": float(cfg.get("range", 0.0)),
		"radius": float(cfg.get("radius", Projectile.DEFAULT_RADIUS)),
		"piercing": bool(cfg.get("piercing", false)),
		"sprite": cfg.get("sprite", &""),
	})

## 弹体生成：效果器只发事件，落到这里才真的建实体。
## 阵营取自施法者，避免技能数据里再抄一份。
func _on_projectile_spawned(payload: Dictionary) -> void:
	var owner_id: int = int(payload.get("owner_id", 0))
	var owner: ActorRuntime = _actors.get(owner_id, null)
	if owner == null or not owner.is_alive():
		return
	_projectiles.spawn_from_payload(owner_id, owner.faction, payload)

## 弹体命中：转给战斗管线结算，和技能/普攻同一条链。
func _apply_projectile_hit(projectile: Projectile, target: Variant) -> Variant:
	var caster: ActorRuntime = _actors.get(projectile.owner_id, null)
	return _pipeline.resolve_projectile_hit(projectile, caster, target as ActorRuntime)

## 场上的弹体（表现层只读，用来同步视图）。
func projectiles() -> Array[Projectile]:
	return _projectiles.items()

# ------------------------------------------------------------------ 波次
func _tick_waves(dt: float) -> void:
	if _waves == null:
		return

	# 只回报「由波次生成」的死亡，避免把玩家/场景角色的死亡算进敌人存活数。
	for key: Variant in _wave_actors.keys():
		var actor_id: int = int(key)
		if _dead_reported.has(actor_id):
			continue
		var actor: ActorRuntime = _actors.get(actor_id, null)
		if actor == null or actor.is_alive():
			continue
		_dead_reported[actor_id] = true
		_waves.on_actor_died(actor_id)

	_waves.tick(dt)
	for request: Dictionary in _waves.pending_spawns():
		var spawned: int = _spawn_from_wave(request)
		if spawned > 0:
			_wave_actors[spawned] = true

func _spawn_from_wave(request: Dictionary) -> int:
	var species_id: StringName = StringName(str(request.get("species_id", "")))
	var entry: Variant = _species.get(species_id, null)
	if entry == null:
		# JSON 字典的键是 String，而这里用的是 StringName，两种都查一次。
		entry = _species.get(String(species_id), {})

	var stats: Dictionary = {}
	var skills: Array = []
	var brain_profile: Variant = {}
	if entry is Dictionary and not (entry as Dictionary).is_empty():
		var data: Dictionary = entry
		if data.get("stats") is Dictionary:
			# 显式分组的数据：{stats, skills, brain_profile}
			stats = (data["stats"] as Dictionary).duplicate(true)
			if data.get("skills") is Array:
				skills = (data["skills"] as Array).duplicate(true)
			if data.get("brain_profile") is Dictionary:
				brain_profile = (data["brain_profile"] as Dictionary).duplicate(true)
		else:
			# 物种表原样传入（flat 字段）：直接当 stats 用。
			stats = data.duplicate(true)

	return spawn_actor({
		"species_id": species_id,
		"faction": StringName(str(request.get("faction", GameConstants.FACTION_ENEMY))),
		"plane_pos": request.get("plane_pos", Vector2.ZERO),
		"stats": stats,
		"skills": skills,
		"brain_profile": brain_profile,
	})

# ------------------------------------------------------------------ 快照
## 序列化全部角色状态（存档 / 回放对账）。数组形式的坐标是为了能直接 JSON.stringify。
func snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor_id: int in actor_ids():
		actors.append(_actors[actor_id].snapshot())
	return {
		"time": _time,
		"next_id": _next_id,
		"actors": actors,
	}

## 从快照重建会话。波次生成器状态不在快照内（它属于关卡进度，另有 StageProgress 负责）。
func restore(data: Dictionary) -> void:
	_actors.clear()
	_ai_inputs.clear()
	_intents.clear()
	_wave_actors.clear()
	_dead_reported.clear()
	_time = float(data.get("time", 0.0))
	_next_id = maxi(int(data.get("next_id", 1)), 1)

	var raw_actors: Variant = data.get("actors", [])
	if raw_actors is Array:
		for raw: Variant in raw_actors:
			if raw is Dictionary:
				_restore_actor(raw)

func _restore_actor(data: Dictionary) -> void:
	var brain_profile: Variant = null
	if bool(data.get("has_brain", false)):
		var raw_brain: Variant = data.get("brain_profile", {})
		brain_profile = raw_brain if raw_brain is Dictionary else {}

	var skills: Variant = data.get("skills", [])
	var spec: Dictionary = {
		"id": int(data.get("id", 0)),
		"species_id": StringName(str(data.get("species_id", ""))),
		"faction": StringName(str(data.get("faction", GameConstants.FACTION_NEUTRAL))),
		"plane_pos": _as_vec2(data.get("plane_pos", Vector2.ZERO)),
		"height": float(data.get("height", 0.0)),
		"facing": int(data.get("facing", 1)),
		"stats": _as_dict(data.get("stats", {})),
		"skills": skills if skills is Array else [],
		"brain_profile": brain_profile,
		"melee": _as_dict(data.get("melee", {})),
	}
	var actor_id: int = spawn_actor(spec)
	var actor: ActorRuntime = _actors.get(actor_id, null)
	if actor != null:
		actor.restore_state(data)

# ------------------------------------------------------------------ 内部
## 用弱引用包一层，避免 ActorRuntime -> Callable -> BattleSession 的强引用环
## 让 RefCounted 无法释放（领域层没有 GC 兜底）。
func _make_stats_provider() -> Callable:
	var session_ref: WeakRef = weakref(self)
	return func(target_id: int) -> CombatActorStats:
		var session: Variant = session_ref.get_ref()
		if session == null:
			return null
		var target: Variant = session.get_actor(target_id)
		if target == null:
			return null
		return target.stats

func _emit(type: StringName, payload: Dictionary) -> void:
	if _bus == null:
		return
	_bus.emit_type(type, payload)

static func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func _as_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
