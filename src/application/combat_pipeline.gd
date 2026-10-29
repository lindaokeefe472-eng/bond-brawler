## 战斗结算助手：把「一次技能激活 / 一次普攻挥击」翻译成「对每个候选目标的伤害结算」。
##
## 为什么单独成类：BattleSession 只该负责「什么时候发生」，不该关心「命中盒怎么筛人、
## 效果器事件怎么落地」。把这些机械工作收敛在这里，会话的 tick 才能保持成一条可读的流水线。
## 注意：这里同样不产生伤害数字 —— 所有数字仍然只由 CombatDamageCalculator 产生。
class_name CombatPipeline
extends RefCounted

const HIT_KIND_SKILL: StringName = &"skill"
const MIN_DIRECTION_SQUARED: float = 0.0001

## 硬直时长区间（秒）。分敌我是有意的：
##   玩家要随时能操作 -> 短；敌人要给足受击反馈 -> 长到能播完 hurt 动画。
const HITSTUN_PLAYER_BASE: float = 0.12
const HITSTUN_PLAYER_CAP: float = 0.22
const HITSTUN_ENEMY_BASE: float = 0.28
const HITSTUN_ENEMY_CAP: float = 0.36

## 弹体类模板的伤害由弹体命中时再结算，激活瞬间只负责生成弹体。
## 若在这里直接结算，远程技能会变成「隔空瞬发」，和表现完全脱节。
const PROJECTILE_TEMPLATES: Array[StringName] = [
	SkillTemplateRegistry.TEMPLATE_PROJECTILE,
	SkillTemplateRegistry.TEMPLATE_VOLLEY,
]

var _bus: DomainEventBus = null
var _rng: IRng = null

func _init(bus: DomainEventBus = null, rng: IRng = null) -> void:
	_bus = bus
	_rng = rng

# ------------------------------------------------------------------ 技能
## 技能激活 -> 命中盒筛目标 -> 依次执行效果链。返回 {targets, results}。
## activation 是 ActorRuntime.consume_skill_activation() 给出的字典。
func resolve_skill(activation: Dictionary, actors: Dictionary) -> Dictionary:
	var out: Dictionary = {"targets": [], "results": []}
	var caster_id: int = int(activation.get("actor_id", 0))
	var caster: ActorRuntime = actors.get(caster_id, null)
	if caster == null or not caster.is_alive():
		return out
	var def: SkillDef = activation.get("def", null)
	if def == null:
		return out

	var origin: Vector2 = _as_vec2(activation.get("origin", caster.plane_pos))
	var facing: int = int(activation.get("facing", caster.facing))
	var hitbox: Dictionary = activation.get("hitbox", {})
	var targets: Array[int] = skill_targets(caster_id, origin, facing, hitbox, actors)
	out["targets"] = targets

	var collected: Array[CombatDamageResult] = []
	# 效果器只认识 emit 端口；这里把「事件」路由成「真正的结算」，
	# 效果器因此永远不需要知道 CombatDamageCalculator 或 ActorRuntime 的存在。
	var sink: Callable = func(event: DomainEvent) -> void:
		_route_effect_event(event, actors, caster, collected)
	var ctx := SkillEffectContext.new(caster_id, targets, origin, facing, _rng,
			_stats_provider_for(actors), sink)

	var skip_damage: bool = _is_projectile_template(def.template)
	var effects: Variant = activation.get("effects", [])
	if effects is Array:
		for effect: Variant in effects:
			if skip_damage and effect is SkillDamageEffect:
				continue
			if effect is SkillEffect:
				(effect as SkillEffect).apply(ctx)

	out["results"] = collected
	return out

## 命中盒筛目标：只保留敌对且活着的角色。用 PlaneMath.in_cone 做窄相，
## 再叠加技能自己的纵深容差（光束类可以比普攻更宽）。
func skill_targets(caster_id: int, origin: Vector2, facing: int, hitbox: Dictionary,
		actors: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var caster: ActorRuntime = actors.get(caster_id, null)
	var caster_faction: StringName = GameConstants.FACTION_NEUTRAL
	if caster != null:
		caster_faction = caster.faction
	var reach: float = maxf(float(hitbox.get("reach", 0.0)), 0.0)
	var half_arc: float = maxf(float(hitbox.get("half_arc", 0.0)), 0.0)
	var lane_tolerance: float = maxf(
			float(hitbox.get("lane_tolerance", GameConstants.LANE_ALIGN_TOLERANCE)), 0.0)

	for key: Variant in actors.keys():
		var target: ActorRuntime = actors[key]
		if target == null or target.id == caster_id or not target.is_alive():
			continue
		if target.faction == caster_faction:
			continue
		if absf(target.plane_pos.y - origin.y) > lane_tolerance:
			continue
		if not PlaneMath.in_cone(origin, facing, target.plane_pos, reach, half_arc):
			continue
		out.append(target.id)
	out.sort()
	return out

# ------------------------------------------------------------------ 普攻
## 普攻窄相：PlaneMath.in_cone 自带纵深对齐，因此不需要物理碰撞体参与。
## config 来自 ActorRuntime.melee_config()，数值不在这里硬编码。
## candidate_ids 是宽相（Area3D）给出的「可能命中」提示。
##   null / 空数组 -> 不做过滤，全量扫描（headless 测试与物理未就绪时的退化路径）。
##   非空 -> 只结算其中的目标。判定盒由近战参数推导且各方向加了 HITBOX_MARGIN，
##   所以它是窄相的严格超集，过滤只会省掉无用的遍历，不会漏掉本该命中的目标。
func resolve_melee(attacker: ActorRuntime, actors: Dictionary,
		config: Dictionary, candidate_ids: Variant = null) -> Array[CombatDamageResult]:
	var results: Array[CombatDamageResult] = []
	if attacker == null or not attacker.is_alive():
		return results

	var reach: float = maxf(float(config.get("range", 0.0)), 0.0)
	var half_arc: float = maxf(float(config.get("half_arc", 0.0)), 0.0)
	var power_ratio: float = float(config.get("power_ratio", 0.0))
	var knockback: float = maxf(float(config.get("knockback", 0.0)), 0.0)
	var damage_type: StringName = StringName(str(config.get("damage_type", "neutral")))
	var hit_kind: StringName = StringName(str(config.get("hit_kind", &"light")))
	# 普攻威力 = 攻击力 * 倍率；技能威力由 SkillDef.power 自带，不走这条路径。
	var power: float = attacker.stats.value(&"attack") * power_ratio

	for key: Variant in actors.keys():
		var target: ActorRuntime = actors[key]
		if target == null or target.id == attacker.id or not target.is_alive():
			continue
		if target.faction == attacker.faction:
			continue
		if candidate_ids is Array and not (candidate_ids as Array).is_empty()                 and not (candidate_ids as Array).has(target.id):
			continue
		if not PlaneMath.in_cone(attacker.plane_pos, attacker.facing, target.plane_pos, reach, half_arc):
			continue

		var req := CombatDamageRequest.new()
		req.attacker_id = attacker.id
		req.target_id = target.id
		req.power = power
		req.damage_type = damage_type
		req.hit_kind = hit_kind
		req.knockback = knockback
		req.can_crit = true
		req.is_aerial = attacker.height > 0.0
		req.knockback_direction = target.plane_pos - attacker.plane_pos

		var result: CombatDamageResult = target.take_hit(req)
		results.append(result)
		_apply_knockback(target, result)
	return results

# ------------------------------------------------------------------ 效果事件落地
## 效果器发出的事件在这里分流：带 power 的伤害是「结算请求」，其余是通知。
func _route_effect_event(event: DomainEvent, actors: Dictionary, caster: ActorRuntime,
		collected: Array[CombatDamageResult]) -> void:
	if event == null:
		return
	var payload: Dictionary = event.payload
	match event.type:
		SkillEffect.EVT_DAMAGE:
			# 同一个事件名既被效果器当请求、又被结算器当结果；
			# power 是请求独有的字段，用它区分，避免二次扣血。
			if payload.has("power"):
				var target: ActorRuntime = actors.get(int(payload.get("target_id", 0)), null)
				if target == null or not target.is_alive():
					return
				var req: CombatDamageRequest = _build_request(payload, caster, target)
				var result: CombatDamageResult = target.take_hit(req)
				collected.append(result)
				_apply_knockback(target, result)
				return
			_emit(event)
		SkillEffect.EVT_STATUS_APPLIED:
			var status_target: ActorRuntime = actors.get(int(payload.get("actor_id", 0)), null)
			if status_target != null:
				status_target.status.apply(
						StringName(str(payload.get("status", ""))),
						float(payload.get("duration", 0.0)),
						int(payload.get("stacks", 1)))
			_emit(event)
		SkillEffect.EVT_HEALED:
			var heal_target: ActorRuntime = actors.get(int(payload.get("actor_id", 0)), null)
			if heal_target != null:
				heal_target.stats.heal(float(payload.get("amount", 0.0)))
			_emit(event)
		SkillEffect.EVT_BUFF_APPLIED:
			_apply_buff(payload, actors)
			_emit(event)
		SkillEffect.EVT_KNOCKBACK:
			# 之前这个事件没有任何订阅者，SkillKnockbackEffect 等于空转：
			# 带击退的技能（area_burst / dash_attack）打上去只掉血、不位移。
			var kb_target: ActorRuntime = actors.get(int(payload.get("target_id", 0)), null)
			if kb_target != null and kb_target.is_alive():
				var raw_dir: Variant = payload.get("direction", Vector2.ZERO)
				var dir: Vector2 = raw_dir if raw_dir is Vector2 else Vector2.ZERO
				if dir.length_squared() < 0.0001:
					dir = Vector2(float(caster.facing), 0.0)
				kb_target.action.set_knockback(dir.normalized() * float(payload.get("strength", 0.0)))
			_emit(event)
		_:
			_emit(event)

func _build_request(payload: Dictionary, caster: ActorRuntime,
		target: ActorRuntime) -> CombatDamageRequest:
	var req := CombatDamageRequest.new()
	req.attacker_id = int(payload.get("attacker_id", caster.id))
	req.target_id = target.id
	req.power = float(payload.get("power", 0.0))
	req.damage_type = StringName(str(payload.get("damage_type", "neutral")))
	req.hit_kind = StringName(str(payload.get("hit_kind", HIT_KIND_SKILL)))
	req.knockback = maxf(float(payload.get("knockback", 0.0)), 0.0)
	req.can_crit = bool(payload.get("can_crit", true))
	req.is_aerial = caster.height > 0.0
	req.tags = _as_tags(payload.get("tags", []))
	req.knockback_direction = target.plane_pos - caster.plane_pos
	return req

func _apply_buff(payload: Dictionary, actors: Dictionary) -> void:
	var target: ActorRuntime = actors.get(int(payload.get("actor_id", 0)), null)
	if target == null:
		return
	var duration: float = float(payload.get("duration", 0.0))
	# 效果器用 0 表示「没填时长」；CombatModifier 用负数表示永久，这里做一次语义翻译。
	if duration <= 0.0:
		duration = -1.0
	var modifier := CombatModifier.make(
			StringName(str(payload.get("stat", "attack"))),
			float(payload.get("flat", 0.0)),
			float(payload.get("percent", 0.0)),
			duration)
	modifier.stacks = maxi(1, int(payload.get("stacks", 1)))
	modifier.max_stacks = modifier.stacks
	modifier.id = StringName(str(payload.get("buff_id", "")))
	if modifier.id == &"":
		modifier.id = modifier.stat
	target.stats.add_modifier(modifier)

func _apply_knockback(target: ActorRuntime, result: CombatDamageResult) -> void:
	if result == null or target == null or not target.is_alive():
		return
	var kb: Vector2 = result.knockback_vector
	if kb.length_squared() <= MIN_DIRECTION_SQUARED:
		return
	# 硬直分敌我：
	#   玩家要随时能操作，所以短（0.10~0.20 秒），配合 0.35 秒免疫窗口，
	#   被三个敌人围殴时最多也只锁 20% 的时间；
	#   敌人要给出看得清的受击反馈，hurt 动画 4 帧 @12fps ≈ 0.33 秒，
	#   所以给到 0.20~0.34 秒，正好让动画播完。
	var is_player: bool = target.faction == GameConstants.FACTION_PLAYER
	var base: float = HITSTUN_PLAYER_BASE if is_player else HITSTUN_ENEMY_BASE
	var cap: float = HITSTUN_PLAYER_CAP if is_player else HITSTUN_ENEMY_CAP
	var stun: float = clampf(base + kb.length() * 0.02, base, cap)
	target.action.apply_hitstun(stun, kb)
	# 霸体 / 无敌 / 硬直免疫时 apply_hitstun 会提前返回，此时仍然要施加击退。
	if not target.action.is_in_hurt():
		target.action.set_knockback(kb)

func _stats_provider_for(actors: Dictionary) -> Callable:
	return func(actor_id: int) -> CombatActorStats:
		var actor: ActorRuntime = actors.get(actor_id, null)
		if actor == null:
			return null
		return actor.stats

func _emit(event: DomainEvent) -> void:
	if _bus != null:
		_bus.emit(event)

func _is_projectile_template(template: StringName) -> bool:
	return PROJECTILE_TEMPLATES.has(SkillTemplateRegistry.normalize_template(template))

func _as_tags(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if raw is Array:
		for entry: Variant in raw:
			out.append(StringName(str(entry)))
	return out

static func _as_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
