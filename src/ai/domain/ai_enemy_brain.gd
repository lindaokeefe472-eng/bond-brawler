## 敌人效用 AI：给每个候选意图打分，取最高分，并用「决策粘滞」抑制抖动。
##
## 为什么用效用打分而不是 if/else 优先级链：清版游戏的敌人需要同时权衡距离、
## 血量、纵深、技能冷却、威胁等互相冲突的因素；权重和曲线是具名常量，
## 性格参数（aggression/caution/range_preference/skill_range/stickiness）来自 profile，
## 策划只改数据就能调出「莽夫」「老六」「远程」等不同性格，而不用改代码。
##
## 数值全部来自构造参数 profile 或本文件的具名常量，逻辑里不出现裸数字。
class_name AiEnemyBrain
extends RefCounted

# ---------------------------------------------------------------- 默认 profile
## profile 缺省时的兜底值。数据加载失败也只会退化成中庸性格，不会崩。
const DEFAULT_AGGRESSION: float = 0.6
const DEFAULT_CAUTION: float = 0.3
const DEFAULT_RANGE_PREFERENCE: float = 1.6
const DEFAULT_SKILL_RANGE: float = 3.0
const DEFAULT_STICKINESS: float = 0.35
const DEFAULT_STICKY_MARGIN: float = 0.08
const DEFAULT_JITTER: float = 0.02
## 距离类参数的最小值，避免除零与「零射程」导致的退化。
const MIN_RANGE: float = 0.01

# ---------------------------------------------------------------- 行为几何
## approach 的停步点：目标身旁 1.2 米，纵深与目标对齐（契约要求）。
const APPROACH_DISTANCE: float = 1.2
## 从「攻击距离外」到「完全着急靠近」的过渡带宽度（米）。
const APPROACH_BAND: float = 1.0
## retreat 时向反方向后撤的距离（米）。
const RETREAT_DISTANCE: float = 3.0
## threat 超过它才考虑防御：威胁是 0..1 的归一化值。
const GUARD_THREAT_THRESHOLD: float = 0.75
## 把伤害换算成「疼痛压力」的参考值：受到这么多伤害约等于压力 1.0。
const PAIN_REFERENCE_DAMAGE: float = 10.0
## 疼痛压力每秒衰减量。
const PAIN_DECAY_PER_SECOND: float = 0.5
## 分数比较的容差：低于它视为同分，同分时保持当前意图。
const SCORE_EPSILON: float = 0.000001

# ---------------------------------------------------------------- consideration 权重
## 权重决定各意图的「最高可得分」。必须保持：
## retreat(低血) > skill > attack > approach/guard，且技能/攻击的窗口分
## 在条件不满足时归零，避免「站在远处空放技能」。
const W_IDLE: float = 0.1
const W_APPROACH_FAR: float = 2.0
const W_APPROACH_AGGRESSION: float = 0.7
const W_RETREAT_HP_GATE: float = 4.0
const W_RETREAT_HP_PRESSURE: float = 0.6
const W_RETREAT_CAUTION: float = 0.2
const W_RETREAT_PAIN: float = 1.5
const W_ATTACK_WINDOW: float = 3.5
const W_ATTACK_AGGRESSION: float = 0.2
const W_SKILL_WINDOW: float = 4.0
const W_SKILL_AGGRESSION: float = 0.2
const W_REPOSITION_MISALIGNED: float = 4.0
const W_GUARD_THREAT: float = 4.0
const W_GUARD_CAUTION: float = 0.2

var _rng: IRng = null
var _aggression: float = DEFAULT_AGGRESSION
var _caution: float = DEFAULT_CAUTION
var _range_preference: float = DEFAULT_RANGE_PREFERENCE
var _attack_range: float = DEFAULT_RANGE_PREFERENCE
var _skill_range: float = DEFAULT_SKILL_RANGE
var _stickiness: float = DEFAULT_STICKINESS
var _sticky_margin: float = DEFAULT_STICKY_MARGIN
var _jitter: float = DEFAULT_JITTER

## StringName -> Array[AiConsideration]
var _considerations: Dictionary = {}
## 用可变 Array 存疼痛值：lambda 捕获局部变量时 Array 是引用语义，
## 这样打分函数不必捕获 self，避免 brain <-> Callable 的强引用环导致 RefCounted 泄漏。
var _pain_box: Array = [0.0]

var _current_kind: StringName = &""
var _stick_timer: float = 0.0
var _cur_skill_slot: int = -1

func _init(profile: Dictionary, rng: IRng) -> void:
    _rng = rng
    _aggression = clampf(float(profile.get("aggression", DEFAULT_AGGRESSION)), 0.0, 1.0)
    _caution = clampf(float(profile.get("caution", DEFAULT_CAUTION)), 0.0, 1.0)
    _range_preference = maxf(float(profile.get("range_preference", DEFAULT_RANGE_PREFERENCE)), MIN_RANGE)
    # profile 没给单独的攻击距离时，range_preference 就是敌人愿意交手的距离，
    # 也是近战窗口；两者分开会让「想保持的距离」和「够得着的距离」打架。
    _attack_range = maxf(float(profile.get("attack_range", _range_preference)), MIN_RANGE)
    _skill_range = maxf(float(profile.get("skill_range", DEFAULT_SKILL_RANGE)), 0.0)
    _stickiness = maxf(float(profile.get("stickiness", DEFAULT_STICKINESS)), 0.0)
    _sticky_margin = maxf(float(profile.get("sticky_margin", DEFAULT_STICKY_MARGIN)), 0.0)
    _jitter = maxf(float(profile.get("jitter", DEFAULT_JITTER)), 0.0)
    if _rng == null:
        _jitter = 0.0
    _build_considerations()

## 推进一帧并返回决策。dt 用于粘滞计时与疼痛衰减，不参与几何计算。
func tick(dt: float, bb: AiBlackboard) -> AiIntent:
    _decay(dt)
    if bb == null or not bb.has_target():
        # 没有目标时不保留粘滞：目标一出现就要立刻重新决策。
        _current_kind = AiIntent.IDLE
        _stick_timer = 0.0
        return AiIntent.make(AiIntent.IDLE)

    _prepare(bb)
    var scores: Dictionary = _score_all(bb)
    var best_kind: StringName = _argmax(scores)
    var fresh: bool = _stick_timer <= 0.0 or _current_kind == &"" or _current_kind == AiIntent.IDLE
    if not fresh:
        var current_score: float = float(scores.get(_current_kind, 0.0))
        var best_score: float = float(scores.get(best_kind, 0.0))
        # 只有「明显更好」才允许替换；同分或略高都被粘滞挡住，防止每帧抖。
        if current_score <= 0.0 or best_score > current_score + _sticky_margin:
            fresh = true
    if fresh:
        _current_kind = best_kind
        _stick_timer = _stickiness
    return _build_intent(_current_kind, bb)

## 受击反馈：伤害累加成「疼痛压力」，短暂抬高撤退/自保的意愿。
func on_hit_taken(damage: float) -> void:
    if damage <= 0.0:
        return
    _pain_box[0] = minf(float(_pain_box[0]) + damage / PAIN_REFERENCE_DAMAGE, 1.0)

# ---------------------------------------------------------------- 打分
func _build_considerations() -> void:
    _considerations = {}
    # 把配置和可变状态抓成局部变量：lambda 按值捕获，不引用 self。
    var attack_range: float = _attack_range
    var skill_range: float = _skill_range
    var aggression: float = _aggression
    var caution: float = _caution
    var band: float = APPROACH_BAND
    var pain_box: Array = _pain_box

    var far_score: Callable = func(bb: AiBlackboard) -> float:
        var distance: float = PlaneMath.distance(bb.self_pos, bb.target_pos)
        return clampf((distance - attack_range) / band, 0.0, 1.0)

    var hp_score: Callable = func(bb: AiBlackboard) -> float:
        return bb.self_hp_ratio

    var pain_score: Callable = func(_bb: AiBlackboard) -> float:
        return float(pain_box[0])

    var strike_score: Callable = func(bb: AiBlackboard) -> float:
        var distance: float = PlaneMath.distance(bb.self_pos, bb.target_pos)
        var in_range: bool = distance <= attack_range
        var aligned: bool = PlaneMath.is_aligned(bb.self_pos, bb.target_pos)
        return 1.0 if in_range and aligned else 0.0

    var skill_score: Callable = func(bb: AiBlackboard) -> float:
        var distance: float = PlaneMath.distance(bb.self_pos, bb.target_pos)
        var ready: bool = AiPerception.first_ready_slot(bb) >= 0
        var aligned: bool = PlaneMath.is_aligned(bb.self_pos, bb.target_pos)
        return 1.0 if ready and distance <= skill_range and aligned else 0.0

    var reposition_score: Callable = func(bb: AiBlackboard) -> float:
        var misaligned: bool = not PlaneMath.is_aligned(bb.self_pos, bb.target_pos)
        var x_gap: float = absf(bb.self_pos.x - bb.target_pos.x)
        # 只处理「横向已经够得着、只差纵深」的情况；离得远时先 approach，
        # 否则敌人会在远处原地横移而不推进。
        return 1.0 if misaligned and x_gap <= attack_range else 0.0

    var threat_score: Callable = func(bb: AiBlackboard) -> float:
        return bb.threat

    _considerations[AiIntent.IDLE] = [
        AiConsideration.make(_constant_score(1.0), W_IDLE),
    ]
    _considerations[AiIntent.APPROACH] = [
        AiConsideration.make(far_score, W_APPROACH_FAR),
        AiConsideration.make(_constant_score(aggression), W_APPROACH_AGGRESSION),
    ]
    _considerations[AiIntent.RETREAT] = [
        AiConsideration.make(hp_score, W_RETREAT_HP_GATE,
                AiConsideration.ScoreCurve.THRESHOLD, caution, true),
        AiConsideration.make(hp_score, W_RETREAT_HP_PRESSURE, AiConsideration.ScoreCurve.INVERSE),
        AiConsideration.make(_constant_score(caution), W_RETREAT_CAUTION),
        AiConsideration.make(pain_score, W_RETREAT_PAIN),
    ]
    _considerations[AiIntent.ATTACK] = [
        AiConsideration.make(strike_score, W_ATTACK_WINDOW),
        AiConsideration.make(_constant_score(aggression), W_ATTACK_AGGRESSION),
    ]
    _considerations[AiIntent.SKILL] = [
        AiConsideration.make(skill_score, W_SKILL_WINDOW),
        AiConsideration.make(_constant_score(aggression), W_SKILL_AGGRESSION),
    ]
    _considerations[AiIntent.REPOSITION] = [
        AiConsideration.make(reposition_score, W_REPOSITION_MISALIGNED),
    ]
    _considerations[AiIntent.GUARD] = [
        AiConsideration.make(threat_score, W_GUARD_THREAT,
                AiConsideration.ScoreCurve.THRESHOLD, GUARD_THREAT_THRESHOLD),
        AiConsideration.make(_constant_score(caution), W_GUARD_CAUTION),
    ]

func _score_all(bb: AiBlackboard) -> Dictionary:
    var scores: Dictionary = {}
    for kind: StringName in AiIntent.KINDS:
        var total: float = 0.0
        var list: Array = _considerations.get(kind, [])
        for consideration: AiConsideration in list:
            total += consideration.weighted_score(bb)
        # 微小抖动只用来打破平局、让同类敌人不同步，幅度远小于任何规则的分差。
        if _rng != null and _jitter > 0.0:
            total += _rng.next_float() * _jitter
        scores[kind] = total
    return scores

func _argmax(scores: Dictionary) -> StringName:
    var best_kind: StringName = AiIntent.IDLE
    var best_score: float = -INF
    for kind: StringName in AiIntent.KINDS:
        var value: float = float(scores.get(kind, 0.0))
        if value > best_score + SCORE_EPSILON:
            best_score = value
            best_kind = kind
    return best_kind

func _constant_score(value: float) -> Callable:
    var clamped: float = clampf(value, 0.0, 1.0)
    return func(_bb: AiBlackboard) -> float: return clamped

# ---------------------------------------------------------------- 状态维护
## 几何一律由坐标现算（PlaneMath），黑板里的 distance/aligned 只是给其它消费者的派生缓存。
func _prepare(bb: AiBlackboard) -> void:
    _cur_skill_slot = AiPerception.first_ready_slot(bb)

func _decay(dt: float) -> void:
    if dt <= 0.0:
        return
    _pain_box[0] = maxf(float(_pain_box[0]) - PAIN_DECAY_PER_SECOND * dt, 0.0)
    _stick_timer = maxf(_stick_timer - dt, 0.0)

# ---------------------------------------------------------------- 意图构造
func _build_intent(kind: StringName, bb: AiBlackboard) -> AiIntent:
    var slot: int = -1
    var desired: Vector2 = PlaneMath.clamp_lane(bb.self_pos)
    match kind:
        AiIntent.APPROACH:
            # 站在目标「自己这一侧」1.2 米处，纵深直接对齐目标。
            var side: float = _side_sign(bb.self_pos.x - bb.target_pos.x)
            desired = PlaneMath.clamp_lane(
                    Vector2(bb.target_pos.x + side * APPROACH_DISTANCE, bb.target_pos.y))
        AiIntent.RETREAT:
            var away: float = _side_sign(bb.self_pos.x - bb.target_pos.x)
            desired = PlaneMath.clamp_lane(
                    Vector2(bb.self_pos.x + away * RETREAT_DISTANCE, bb.self_pos.y))
        AiIntent.REPOSITION:
            # 保持横向位置，只把纵深挪到目标那条线上。
            desired = PlaneMath.clamp_lane(Vector2(bb.self_pos.x, bb.target_pos.y))
        AiIntent.SKILL:
            slot = _cur_skill_slot
    return AiIntent.make(kind, bb.target_id, slot, desired)

static func _side_sign(delta: float) -> float:
    return 1.0 if delta >= 0.0 else -1.0
