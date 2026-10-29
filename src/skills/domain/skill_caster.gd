## 施法状态机：IDLE -> WINDUP -> ACTIVE -> RECOVERY -> IDLE。
##
## 设计要点：
##   1. 能量不存放在 caster 里（ActorRuntime 才是能量池的主人），
##      begin_cast 只校验并记录本次消耗，调用方据此扣能量；
##      取消时把返还量累积到 energy_refunded，由调用方取走加回。
##   2. ACTIVE 进入瞬间发 skill.activated，载荷带命中盒与效果列表，
##      下游据此做窄相判定与效果结算 —— 领域层不碰血量。
##   3. 前摇取消只赔 50%：既不让误按完全无代价，也不让一次误按毁掉整场。
class_name SkillCaster
extends RefCounted

## 取消前摇时返还的能量与冷却比例。
const CANCEL_REFUND_FRACTION: float = 0.5
## ACTIVE 至少持续一拍，保证激活事件不会被同一帧的推进直接吞掉。
const MIN_PHASE_DURATION: float = GameConstants.TICK_DELTA
## 单帧内最多推进的相位次数，防御异常数据造成的死循环。
const MAX_PHASE_STEPS: int = 8

var actor_id: int = 0
var phase: int = SkillCastPhase.IDLE
var active_slot: int = -1

## 最近一次成功 begin_cast 的能量消耗，供调用方从能量池扣除。
var energy_spent: float = 0.0
## 取消前摇累积的待返还能量，用 take_refunded_energy() 取走。
var energy_refunded: float = 0.0

var _bus: DomainEventBus = null
var _slots: Dictionary = {}
var _phase_time: float = 0.0
var _phase_duration: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _facing: int = 1

func _init(p_actor_id: int, p_bus: DomainEventBus) -> void:
	actor_id = p_actor_id
	_bus = p_bus

func equip(slot: int, inst: SkillInstance) -> void:
	if inst == null:
		return
	_slots[slot] = inst

## 供测试与调用方查询槽位实例，不参与状态机。
func instance(slot: int) -> SkillInstance:
	var inst: SkillInstance = _slots.get(slot, null)
	return inst

func can_cast(slot: int, energy: float) -> bool:
	if phase != SkillCastPhase.IDLE:
		return false
	var inst: SkillInstance = _slots.get(slot, null)
	if inst == null or inst.def == null or not inst.is_ready():
		return false
	return energy >= inst.def.cost

func begin_cast(slot: int, aim: Vector2, facing: int, energy: float) -> bool:
	if not can_cast(slot, energy):
		return false
	var inst: SkillInstance = _slots[slot]
	active_slot = slot
	_aim = aim
	_facing = facing if facing != 0 else 1
	energy_spent = inst.def.cost
	inst.consume()

	phase = SkillCastPhase.WINDUP
	_phase_time = 0.0
	_phase_duration = maxf(inst.def.windup, 0.0)
	_emit(GameConstants.EVT_SKILL_CAST_STARTED, {
		"actor_id": actor_id,
		"slot": slot,
		"skill_id": inst.def.id,
		"aim": aim,
		"facing": _facing,
	})
	# 无前摇技能在同一帧进入 ACTIVE，避免玩家等一个空相位。
	if _phase_duration <= 0.0:
		_enter_active()
	return true

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_tick_cooldowns(dt)
	if phase == SkillCastPhase.IDLE:
		return
	_phase_time += dt
	var steps: int = 0
	while phase != SkillCastPhase.IDLE and _phase_time >= _phase_duration:
		var overflow: float = _phase_time - _phase_duration
		_advance_phase()
		_phase_time = overflow
		steps += 1
		if steps >= MAX_PHASE_STEPS:
			break

## 被打断：立即回 IDLE，不返还任何资源（打断就是要付出代价）。
func interrupt(reason: StringName) -> void:
	if phase == SkillCastPhase.IDLE and active_slot < 0:
		return
	var slot: int = active_slot
	_finish_cast()
	_emit(GameConstants.EVT_SKILL_INTERRUPTED, {
		"actor_id": actor_id,
		"slot": slot,
		"reason": reason,
	})

## 只在前摇期生效：返还一半冷却与能量；ACTIVE 之后已经出手，不再退还。
func cancel_windup() -> void:
	if phase != SkillCastPhase.WINDUP:
		return
	var inst: SkillInstance = _current_instance()
	if inst != null:
		inst.refund(CANCEL_REFUND_FRACTION)
		energy_refunded += inst.refunded_energy
	_finish_cast()

func is_busy() -> bool:
	return phase != SkillCastPhase.IDLE

func phase_progress() -> float:
	if phase == SkillCastPhase.IDLE:
		return 0.0
	if _phase_duration <= 0.0:
		return 1.0
	return clampf(_phase_time / _phase_duration, 0.0, 1.0)

## 取走待返还能量并清零，调用方直接加到自己的能量池。
func take_refunded_energy() -> float:
	var amount: float = energy_refunded
	energy_refunded = 0.0
	return amount

func _tick_cooldowns(dt: float) -> void:
	for slot: Variant in _slots.keys():
		var inst: SkillInstance = _slots[slot]
		if inst.tick(dt):
			_emit(GameConstants.EVT_SKILL_COOLDOWN_READY, {
				"actor_id": actor_id,
				"slot": int(slot),
				"skill_id": inst.def.id if inst.def != null else &"",
			})

func _current_instance() -> SkillInstance:
	if active_slot < 0:
		return null
	var inst: SkillInstance = _slots.get(active_slot, null)
	return inst

func _advance_phase() -> void:
	match phase:
		SkillCastPhase.WINDUP:
			_enter_active()
		SkillCastPhase.ACTIVE:
			_enter_recovery()
		SkillCastPhase.RECOVERY:
			_finish_cast()
		_:
			_finish_cast()

func _enter_active() -> void:
	var inst: SkillInstance = _current_instance()
	if inst == null or inst.def == null:
		_finish_cast()
		return
	phase = SkillCastPhase.ACTIVE
	_phase_time = 0.0
	_phase_duration = maxf(inst.def.commit, MIN_PHASE_DURATION)
	_emit(GameConstants.EVT_SKILL_ACTIVATED, {
		"actor_id": actor_id,
		"slot": active_slot,
		"skill_id": inst.def.id,
		"hitbox": SkillTemplateRegistry.hitbox(inst.def),
		"effects": SkillTemplateRegistry.build(inst.def),
	})

func _enter_recovery() -> void:
	var inst: SkillInstance = _current_instance()
	phase = SkillCastPhase.RECOVERY
	_phase_time = 0.0
	_phase_duration = maxf(inst.def.recovery, 0.0) if inst != null and inst.def != null else 0.0
	if _phase_duration <= 0.0:
		_finish_cast()

func _finish_cast() -> void:
	phase = SkillCastPhase.IDLE
	active_slot = -1
	_phase_time = 0.0
	_phase_duration = 0.0

func _emit(type: StringName, payload: Dictionary) -> void:
	if _bus == null:
		return
	_bus.emit(DomainEvent.new(type, payload))
