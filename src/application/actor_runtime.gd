## 单个角色的运行时聚合：把 stats / status / action / caster / brain / 资源池绑在同一个对象上。
##
## 为什么需要这一层：各领域上下文彼此不认识（combat 不认识 skills，skills 不认识 locomotion），
## 只有 application 能把它们装进同一个「活着的角色」里。这里不放业务规则，
## 只按固定顺序推进各自的 tick，并把跨上下文的调用翻译成一次方法调用。
class_name ActorRuntime
extends RefCounted

# ---------------------------------------------------------------- 资源经济
## 数值来自 data/actions.json 的 resources 段；构造 spec 可覆盖，逻辑里不出现裸数字。
const ENERGY_REGEN_PER_SECOND: float = 5.0
const ENERGY_MAX_DEFAULT: float = 180.0
const ENERGY_START_DEFAULT: float = 180.0
const STAMINA_MAX_DEFAULT: float = 100.0
const STAMINA_REGEN_PER_SECOND: float = 14.0
const STAMINA_REGEN_DELAY: float = 0.4

# ---------------------------------------------------------------- 普攻默认值
## 来自 data/actions.json 的 basic_attack 段：威力由 attack 折算，射程 2.4。
const MELEE_RANGE_DEFAULT: float = 2.4
const MELEE_POWER_RATIO_DEFAULT: float = 1.0
const MELEE_KNOCKBACK_DEFAULT: float = 0.65
const MELEE_HALF_ARC_DEFAULT: float = 0.0
const HIT_KIND_LIGHT: StringName = &"light"

const DEFAULT_FACTION: StringName = GameConstants.FACTION_NEUTRAL
const SKILL_SLOT_COUNT: int = LocoInputFrame.SKILL_SLOTS

# ---------------------------------------------------------------- 契约字段
var id: int = 0
var faction: StringName = DEFAULT_FACTION
var stats: CombatActorStats = null
var status: CombatStatusSet = null
var action: LocoActionMachine = null
var caster: SkillCaster = null
var brain: AiEnemyBrain = null
var facing: int = 1
var plane_pos: Vector2 = Vector2.ZERO
var height: float = 0.0
var energy: float = ENERGY_START_DEFAULT
var stamina: float = STAMINA_MAX_DEFAULT

## func(actor_id) -> CombatActorStats。伤害结算需要攻击方数值，由 BattleSession 注入。
## 用 Callable 而不是直接持有会话：ActorRuntime 只依赖一个端口，便于单测。
var stats_provider: Callable = Callable()

var _bus: DomainEventBus = null
var _calculator: CombatDamageCalculator = null
var _species_id: StringName = &""
var _stats_base: Dictionary = {}
var _skill_specs: Array[Dictionary] = []
var _brain_profile: Dictionary = {}
var _melee: Dictionary = {}

var _energy_max: float = ENERGY_MAX_DEFAULT
var _energy_regen: float = ENERGY_REGEN_PER_SECOND
var _stamina_max: float = STAMINA_MAX_DEFAULT
var _stamina_regen: float = STAMINA_REGEN_PER_SECOND
var _stamina_regen_delay: float = STAMINA_REGEN_DELAY
var _stamina_delay_left: float = 0.0

var _is_guarding: bool = false
var _last_output: LocoActionOutput = null
var _prev_skill_inputs: Array[bool] = [false, false, false, false]
var _attack_pending: bool = false
var _skill_pending: Dictionary = {}
## 本次施法的定义在起手时记住：ACTIVE 可能短于一帧，事后无法再从 caster 取回。
var _cast_def: SkillDef = null
var _cast_slot: int = -1
var _cast_activation_done: bool = false
var _dead_emitted: bool = false

func _init(p_id: int = 0, p_spec: Dictionary = {}, p_bus: DomainEventBus = null,
        p_calculator: CombatDamageCalculator = null, p_rng: IRng = null) -> void:
    id = p_id
    _bus = p_bus
    _calculator = p_calculator
    faction = StringName(str(p_spec.get("faction", DEFAULT_FACTION)))
    _species_id = StringName(str(p_spec.get("species_id", "")))

    # stats 的原始字典要留下来：快照/存档需要能重建同一个角色，而不是只存当前血量。
    _stats_base = _as_dict(p_spec.get("stats", {}))
    stats = CombatActorStats.new(id, _stats_base)
    status = CombatStatusSet.new(_as_dict(p_spec.get("status_durations", {})))

    _read_resource_config(p_spec)

    plane_pos = PlaneMath.clamp_lane(_as_vec2(p_spec.get("plane_pos", Vector2.ZERO)))
    height = maxf(float(p_spec.get("height", 0.0)), 0.0)
    facing = 1 if int(p_spec.get("facing", 1)) >= 0 else -1

    var action_profile: Dictionary = _as_dict(p_spec.get("action_profile", {}))
    action_profile["actor_id"] = id
    action_profile["start_pos"] = plane_pos
    action_profile["start_height"] = height
    action_profile["facing"] = facing
    action = LocoActionMachine.new(action_profile, p_bus)

    caster = SkillCaster.new(id, p_bus)
    _equip_skills(p_spec.get("skills", []))

    var raw_brain: Variant = p_spec.get("brain_profile", null)
    if raw_brain is Dictionary:
        _brain_profile = (raw_brain as Dictionary).duplicate(true)
        brain = AiEnemyBrain.new(_brain_profile, p_rng)

    _melee = _as_dict(p_spec.get("melee", {}))

    var raw_provider: Variant = p_spec.get("stats_provider", null)
    if raw_provider is Callable and (raw_provider as Callable).is_valid():
        stats_provider = raw_provider

# ------------------------------------------------------------------ 主循环
## 契约入口：一帧推进。顺序固定为 资源 -> 动作机 -> 技能相位 -> 状态。
## BattleSession 为了把 AI 决策插在动作机与技能相位之间，会拆开调用下面三个方法；
## 单独使用 ActorRuntime 时用这个入口即可。
func tick(dt: float, input: LocoInputFrame, services: Dictionary = {}) -> LocoActionOutput:
    var step: float = maxf(dt, 0.0)
    var output: LocoActionOutput = tick_action(step, input)
    tick_skill(step)
    if bool(services.get("advance_status", true)):
        tick_status(step)
    return output

## 动作机 + 资源回复 + 输入边沿。攻击命中窗口在这里被标记，由 BattleSession 消费。
func tick_action(dt: float, input: LocoInputFrame) -> LocoActionOutput:
    var step: float = maxf(dt, 0.0)
    if not is_alive():
        # 死亡后仍然让动作机推进到 DEAD，表现层才能拿到正确输出。
        _last_output = action.tick(step, null, false)
        return _last_output

    _advance_resources(step)
    # 格挡是「按住」语义，只有能行动时才算数；眩晕/定身期间盾会自然落下。
    _is_guarding = input != null and input.guard and status.can_act()
    _read_skill_input(input)

    var effective: LocoInputFrame = input
    if not status.can_act():
        # 定身/眩晕只保留物理位移（击退、重力），不接受任何动作输入。
        effective = LocoInputFrame.empty()

    var prev_state: int = action.current_state()
    var prev_phase: int = action.attack_phase()
    _last_output = action.tick(step, effective, true)
    plane_pos = _last_output.plane_pos
    height = _last_output.height
    facing = _last_output.facing

    # 只在 ACTIVE 的首帧标记一次，否则一次挥击会在 ACTIVE 期间每帧都结算。
    if _last_output.state == LocoActionState.ATTACK \
            and action.attack_phase() == LocoActionMachine.ATTACK_PHASE_ACTIVE \
            and (prev_state != LocoActionState.ATTACK
                or prev_phase != LocoActionMachine.ATTACK_PHASE_ACTIVE):
        _attack_pending = true
    return _last_output

## 技能相位：冷却、充能、施法相位与取消返还都归 SkillCaster 管，这里只做能量池同步。
func tick_skill(dt: float) -> void:
    if not is_alive():
        return
    var prev_phase: int = caster.phase
    caster.tick(maxf(dt, 0.0))
    var refund: float = caster.take_refunded_energy()
    if refund > 0.0:
        energy = minf(_energy_max, energy + refund)

    # 激活的判定不能只看「tick 之后是否还停在 ACTIVE」：commit 很短时，
    # 一次 tick 内会走完 ACTIVE 直接进 RECOVERY，因此还要看相位是否越过了 WINDUP。
    if not _cast_activation_done and _cast_def != null:
        var reached_active: bool = prev_phase == SkillCastPhase.ACTIVE \
                or caster.phase == SkillCastPhase.ACTIVE \
                or (prev_phase == SkillCastPhase.WINDUP and caster.phase != SkillCastPhase.WINDUP)
        if reached_active:
            _capture_skill_activation(_cast_def, _cast_slot)
            _cast_activation_done = true
    if caster.phase == SkillCastPhase.IDLE:
        _cast_def = null
        _cast_slot = -1
        _cast_activation_done = false

## 状态结算：推进状态时长并发过期事件。BattleSession 把它排在命中结算之后。
func tick_status(dt: float) -> void:
    if dt <= 0.0:
        return
    var expired: Array[StringName] = status.tick(dt)
    for status_id: StringName in expired:
        _emit(GameConstants.EVT_STATUS_EXPIRED, {
            "actor_id": id,
            "status": status_id,
        })

# ------------------------------------------------------------------ 伤害
## 走 CombatDamageCalculator 结算一次伤害：扣血、发事件、必要时切死亡状态。
## 返回结果给调用方（CombatPipeline / 表现层）做跳字、击退与顿帧。
func take_hit(request: CombatDamageRequest) -> CombatDamageResult:
    var result := CombatDamageResult.new()
    if request == null or stats == null or stats.is_dead():
        return result
    if _calculator == null:
        push_warning("ActorRuntime.take_hit: 未注入 CombatDamageCalculator，伤害被丢弃")
        return result

    var attacker: CombatActorStats = null
    if stats_provider.is_valid():
        attacker = stats_provider.call(request.attacker_id)

    var invulnerable: bool = _last_output != null and _last_output.invulnerable
    result = _calculator.resolve(request, attacker, stats, status, invulnerable, _is_guarding)

    if result.is_dodged:
        _emit(GameConstants.EVT_ACTOR_DODGED, {
            "attacker_id": request.attacker_id,
            "target_id": id,
            "damage_type": request.damage_type,
        })
        return result

    if result.is_guarded:
        _emit(GameConstants.EVT_ACTOR_GUARDED, {
            "attacker_id": request.attacker_id,
            "target_id": id,
            "amount": result.amount,
        })

    if result.amount > 0.0:
        _emit(GameConstants.EVT_DAMAGE_APPLIED, {
            "attacker_id": request.attacker_id,
            "target_id": id,
            "amount": result.amount,
            "is_crit": result.is_crit,
            "is_guarded": result.is_guarded,
            "is_lethal": result.is_lethal,
            "damage_type": request.damage_type,
            "hit_kind": request.hit_kind,
        })
        # 只有「实际伤害低于原始威力」才算被减伤，避免给正常伤害也发一条噪音事件。
        if result.amount < request.power:
            _emit(GameConstants.EVT_DAMAGE_MITIGATED, {
                "attacker_id": request.attacker_id,
                "target_id": id,
                "raw": request.power,
                "amount": result.amount,
                "is_guarded": result.is_guarded,
            })
        if brain != null:
            brain.on_hit_taken(result.amount)

    # 挨打就醒：3.5 秒的睡眠在清版游戏里等于把玩家交给敌人白打。
    # 只有真的吃到伤害才破睡，被格挡或闪避不算。
    if result.amount > 0.0 and status.has(&"sleep"):
        status.remove(&"sleep")

    if stats.is_dead():
        _die(request.attacker_id)
    return result

# ------------------------------------------------------------------ 技能
## 尝试施放一个槽位。能量在这里扣除，冷却与充能由 SkillCaster/SkillInstance 负责。
func try_cast_skill(slot: int, aim: Vector2) -> bool:
    if not is_alive() or not status.can_act():
        return false
    if not caster.can_cast(slot, energy):
        return false
    if not caster.begin_cast(slot, aim, facing, energy):
        return false
    spend_energy(caster.energy_spent)
    var inst: SkillInstance = caster.instance(slot)
    if inst != null and inst.def != null:
        # 施法期间锁住动作机，避免玩家一边前摇一边跑动。
        action.request_skill_lock(inst.def.windup + inst.def.commit + inst.def.recovery)
        # 记住本次施法的定义：ACTIVE 相位可能短于一帧，届时 caster 已经回到 IDLE。
        _cast_def = inst.def
        _cast_slot = slot
        _cast_activation_done = false
    return true

## 取出本帧新产生的技能激活（无则空字典）。一次激活只结算一次。
func consume_skill_activation() -> Dictionary:
    var out: Dictionary = _skill_pending
    _skill_pending = {}
    return out

## 取出本帧新进入攻击 ACTIVE 的标记（无则 false）。
func consume_attack_activation() -> bool:
    var out: bool = _attack_pending
    _attack_pending = false
    return out

func skills_ready() -> Array[bool]:
    var out: Array[bool] = []
    for slot: int in range(SKILL_SLOT_COUNT):
        out.append(caster.can_cast(slot, energy))
    return out

# ------------------------------------------------------------------ 资源
## 返回实际扣除量：资源池不会变成负数。
func spend_energy(amount: float) -> float:
    if amount <= 0.0:
        return 0.0
    var actual: float = minf(amount, energy)
    energy = maxf(0.0, energy - actual)
    return actual

## 耐力消耗后要等 STAMINA_REGEN_DELAY 才开始回复，避免连按冲刺时耐力瞬间回满。
func spend_stamina(amount: float) -> float:
    if amount <= 0.0:
        return 0.0
    var actual: float = minf(amount, stamina)
    stamina = maxf(0.0, stamina - actual)
    _stamina_delay_left = _stamina_regen_delay
    return actual

# ------------------------------------------------------------------ 查询
func is_alive() -> bool:
    return stats != null and not stats.is_dead()

func is_dead() -> bool:
    return stats == null or stats.is_dead()

func is_guarding() -> bool:
    return _is_guarding

func hp_ratio() -> float:
    if stats == null:
        return 0.0
    var cap: float = stats.max_hp()
    if cap <= 0.0:
        return 0.0
    return clampf(stats.current_hp / cap, 0.0, 1.0)

func species_id() -> StringName:
    return _species_id

## 普攻参数：BattleSession 传给 CombatPipeline，避免把数值散落在编排代码里。
func melee_config() -> Dictionary:
    return {
        "range": maxf(float(_melee.get("range", MELEE_RANGE_DEFAULT)), 0.0),
        "power_ratio": float(_melee.get("power_ratio", MELEE_POWER_RATIO_DEFAULT)),
        "knockback": maxf(float(_melee.get("knockback", MELEE_KNOCKBACK_DEFAULT)), 0.0),
        "half_arc": maxf(float(_melee.get("half_arc", MELEE_HALF_ARC_DEFAULT)), 0.0),
        "damage_type": StringName(str(_melee.get("damage_type", "neutral"))),
        "hit_kind": HIT_KIND_LIGHT,
    }

# ------------------------------------------------------------------ 快照
func snapshot() -> Dictionary:
    return {
        "id": id,
        "faction": faction,
        "species_id": _species_id,
        "plane_pos": [plane_pos.x, plane_pos.y],
        "height": height,
        "facing": facing,
        "hp": stats.current_hp if stats != null else 0.0,
        "energy": energy,
        "stamina": stamina,
        "stats": _stats_base.duplicate(true),
        "skills": _skill_specs.duplicate(true),
        "has_brain": brain != null,
        "brain_profile": _brain_profile.duplicate(true),
        "melee": _melee.duplicate(true),
        # 动作机的内部计时全部转成 JSON 可序列化的标量/数组，存档才能直接落盘。
        "action": _action_snapshot(),
    }

## 从快照恢复可变状态。动作机不提供状态注入接口，因此只恢复位置/高度/朝向与资源。
func restore_state(data: Dictionary) -> void:
    if data.is_empty():
        return
    if stats != null:
        stats.current_hp = clampf(float(data.get("hp", stats.current_hp)), 0.0, stats.max_hp())
    energy = clampf(float(data.get("energy", energy)), 0.0, _energy_max)
    stamina = clampf(float(data.get("stamina", stamina)), 0.0, _stamina_max)
    plane_pos = PlaneMath.clamp_lane(_as_vec2(data.get("plane_pos", plane_pos)))
    height = maxf(float(data.get("height", height)), 0.0)
    facing = 1 if int(data.get("facing", facing)) >= 0 else -1
    action.set_plane_pos(plane_pos)
    action.set_height(height)
    action.set_facing(facing)
    if stats != null and stats.is_dead():
        # 恢复一个已死亡角色时不要重发 actor.died，读档不该产生新的击杀播报。
        _last_output = action.tick(0.0, null, false)
        _dead_emitted = true

# ------------------------------------------------------------------ 内部
## 动作机 snapshot 里的 Vector2/StringName 不能直接进 JSON，这里做一次扁平化转换。
func _action_snapshot() -> Dictionary:
    var raw: Dictionary = action.snapshot()
    var pos: Vector2 = raw.get("plane_pos", Vector2.ZERO)
    var velocity: Vector2 = raw.get("velocity", Vector2.ZERO)
    return {
        "state": int(raw.get("state", LocoActionState.IDLE)),
        "state_name": str(raw.get("state_name", &"unknown")),
        "plane_pos": [pos.x, pos.y],
        "velocity": [velocity.x, velocity.y],
        "height": float(raw.get("height", 0.0)),
        "vertical_velocity": float(raw.get("vertical_velocity", 0.0)),
        "facing": int(raw.get("facing", 1)),
        "state_time": float(raw.get("state_time", 0.0)),
        "combo_index": int(raw.get("combo_index", 0)),
        "combo_timer": float(raw.get("combo_timer", 0.0)),
        "attack_phase": int(raw.get("attack_phase", 0)),
        "coyote_timer": float(raw.get("coyote_timer", 0.0)),
        "super_armor": bool(raw.get("super_armor", false)),
        "invulnerable": bool(raw.get("invulnerable", false)),
        "time": float(raw.get("time", 0.0)),
    }

func _read_resource_config(spec: Dictionary) -> void:
    _energy_max = maxf(float(spec.get("energy_max", ENERGY_MAX_DEFAULT)), 0.0)
    _energy_regen = maxf(float(spec.get("energy_regen", ENERGY_REGEN_PER_SECOND)), 0.0)
    var start: float = float(spec.get("energy", spec.get("energy_start", ENERGY_START_DEFAULT)))
    energy = clampf(start, 0.0, _energy_max)
    _stamina_max = maxf(float(spec.get("stamina_max", STAMINA_MAX_DEFAULT)), 0.0)
    stamina = clampf(float(spec.get("stamina", _stamina_max)), 0.0, _stamina_max)
    _stamina_regen = maxf(float(spec.get("stamina_regen", STAMINA_REGEN_PER_SECOND)), 0.0)
    _stamina_regen_delay = maxf(float(spec.get("stamina_regen_delay", STAMINA_REGEN_DELAY)), 0.0)

func _advance_resources(dt: float) -> void:
    if dt <= 0.0:
        return
    energy = minf(_energy_max, energy + _energy_regen * dt)
    if _stamina_delay_left > 0.0:
        _stamina_delay_left = maxf(0.0, _stamina_delay_left - dt)
        return
    stamina = minf(_stamina_max, stamina + _stamina_regen * dt)

func _read_skill_input(input: LocoInputFrame) -> void:
    if input == null:
        for slot: int in range(SKILL_SLOT_COUNT):
            _prev_skill_inputs[slot] = false
        return
    for slot: int in range(SKILL_SLOT_COUNT):
        var pressed: bool = slot < input.skills.size() and input.skills[slot]
        if pressed and not _prev_skill_inputs[slot]:
            try_cast_skill(slot, _aim_for_slot(slot))
        _prev_skill_inputs[slot] = pressed

func _aim_for_slot(slot: int) -> Vector2:
    var inst: SkillInstance = caster.instance(slot)
    var reach: float = inst.def.range if inst != null and inst.def != null else 0.0
    return plane_pos + Vector2(float(facing) * maxf(reach, 0.0), 0.0)

func _capture_skill_activation(def: SkillDef, slot: int) -> void:
    if def == null:
        return
    _skill_pending = {
        "actor_id": id,
        "slot": slot,
        "skill_id": def.id,
        "def": def,
        "hitbox": SkillTemplateRegistry.hitbox(def),
        "effects": SkillTemplateRegistry.build(def),
        "origin": plane_pos,
        "facing": facing,
    }

func _equip_skills(raw_skills: Variant) -> void:
    _skill_specs = []
    for slot: int in range(SKILL_SLOT_COUNT):
        _skill_specs.append({})
    if not (raw_skills is Array):
        return
    var entries: Array = raw_skills
    for slot: int in range(mini(entries.size(), SKILL_SLOT_COUNT)):
        _equip_skill(slot, entries[slot])

func _equip_skill(slot: int, entry: Variant) -> void:
    var def: SkillDef = null
    var spec: Dictionary = {}
    var instance: SkillInstance = null
    if entry is SkillInstance:
        instance = entry
        if instance.def == null:
            return
        def = instance.def
        spec = _def_to_dict(def)
    elif entry is SkillDef:
        def = entry
        spec = _def_to_dict(def)
    elif entry is Dictionary:
        var data: Dictionary = entry
        if data.is_empty():
            return
        def = SkillDef.from_dict(data)
        spec = data.duplicate(true)
    else:
        return
    # 调用方已经准备好 SkillInstance 时直接复用，保留它已有的冷却/充能状态。
    if instance == null:
        instance = SkillInstance.new(def)
    caster.equip(slot, instance)
    _skill_specs[slot] = spec

func _die(killer_id: int) -> void:
    if _dead_emitted:
        return
    _dead_emitted = true
    _is_guarding = false
    _skill_pending = {}
    _attack_pending = false
    _cast_def = null
    _cast_slot = -1
    _cast_activation_done = false
    _last_output = action.tick(0.0, null, false)
    plane_pos = _last_output.plane_pos
    height = _last_output.height
    _emit(GameConstants.EVT_ACTOR_DIED, {
        "actor_id": id,
        "killer_id": killer_id,
        "faction": faction,
        "plane_pos": plane_pos,
    })

func _emit(type: StringName, payload: Dictionary) -> void:
    if _bus == null:
        return
    _bus.emit_type(type, payload)

# ------------------------------------------------------------------ 工具
## SkillDef 没有 to_dict，这里显式重建一份，保证快照能通过 from_dict 原样还原。
static func _def_to_dict(def: SkillDef) -> Dictionary:
    if def == null:
        return {}
    var out: Dictionary = {
        "id": str(def.id),
        "name": def.name,
        "type": str(def.type),
        "kind": str(def.kind),
        "template": str(def.template),
        "power": def.power,
        "cost": def.cost,
        "cooldown": def.cooldown,
        "range": def.range,
        "knockback": def.knockback,
        "windup": def.windup,
        "commit": def.commit,
        "recovery": def.recovery,
        "duration": def.duration,
        "clash_class": str(def.clash_class),
        "clash_power": def.clash_power,
        "status": str(def.status),
        "dodgeable": def.dodgeable,
    }
    for key: Variant in def.extra.keys():
        out[key] = def.extra[key]
    return out

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
