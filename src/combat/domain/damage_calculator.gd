## 伤害结算：唯一产生伤害数字的地方。
## 管线顺序是契约（ARCHITECTURE 4.2），不得调整：
## 无敌 -> 闪避 -> 格挡 -> 暴击 -> 属性倍率 -> 防御减免 -> 最小伤害 -> 扣血
class_name CombatDamageCalculator
extends RefCounted

## 默认调参。数值来自 data/actions.json 的 guard.damage_taken_normal 与
## 防御软上限经验公式；构造时可覆盖，避免把可调数值焊死在逻辑里。
const DEFAULT_TUNING: Dictionary = {
    &"guard_damage_ratio": 0.25,
    &"defense_softness": 100.0,
    &"min_damage": 1.0,
}

var _type_chart: CombatTypeChart
var _rng: IRng
var _tuning: Dictionary = {}

func _init(type_chart: CombatTypeChart, rng: IRng, tuning: Dictionary = {}) -> void:
    _type_chart = type_chart
    _rng = rng
    _tuning = DEFAULT_TUNING.duplicate()
    for raw_key: Variant in tuning.keys():
        _tuning[StringName(str(raw_key))] = tuning[raw_key]

@warning_ignore("unused_parameter")
func resolve(req: CombatDamageRequest, attacker: CombatActorStats, defender: CombatActorStats,
        defender_status: CombatStatusSet, defender_invulnerable: bool,
        defender_guarding: bool) -> CombatDamageResult:
    var result := CombatDamageResult.new()
    if req == null or defender == null:
        return result

    # 1. 无敌：直接 0，不消耗随机数，也不扣血。
    if defender_invulnerable:
        return result

    # 2. 闪避：只有存在闪避率时才掷骰，避免无意义的随机数消耗破坏回放序列。
    var dodge_chance: float = defender.value(&"dodge")
    if dodge_chance > 0.0 and _rng != null and _rng.next_float() < dodge_chance:
        result.is_dodged = true
        return result

    # 基础伤害就是 power：攻击力已由上游折算，管线内再乘会重复计算。
    var damage: float = req.power

    # 3. 格挡：减伤且不进入暴击分支（格挡是「稳」，暴击是「爆」，二者互斥）。
    if defender_guarding:
        result.is_guarded = true
        damage *= float(_tuning[&"guard_damage_ratio"])
    elif req.can_crit:
        # 4. 暴击：暴击率来自攻击方最终属性，可被天赋修饰。
        var crit_rate: float = 0.0
        var crit_mult: float = 1.0
        if attacker != null:
            crit_rate = attacker.value(&"crit_rate")
            crit_mult = attacker.value(&"crit_mult")
        if crit_rate > 0.0 and _rng != null and _rng.next_float() < crit_rate:
            result.is_crit = true
            damage *= crit_mult

    # 5. 属性倍率：双属性相乘，未知/空属性按 1.0。
    if _type_chart != null and req.damage_type != &"":
        damage *= _type_chart.multiplier(req.damage_type, defender.types)

    # 6. 防御减免：软上限公式，防御再高也不会完全免疫（100/(100+defense)）。
    var defense: float = maxf(0.0, defender.value(&"defense"))
    var softness: float = float(_tuning[&"defense_softness"])
    damage *= softness / (softness + defense)

    # 7. 最小伤害：命中就该掉血，避免高防把伤害压成 0 导致「打不动」。
    damage = maxf(damage, float(_tuning[&"min_damage"]))
    result.amount = damage

    # 8. 扣血：由本层落地，保证「伤害数字只由领域层产生」。
    defender.take_raw_damage(damage)
    result.is_lethal = defender.is_dead()
    result.knockback_vector = _knockback_for(req)
    return result

## 结算器没有坐标，只能按上游给的方向与强度算位移；
## 没给方向时返回零向量，由表现层/移动层决定兜底方向。
func _knockback_for(req: CombatDamageRequest) -> Vector2:
    if req.knockback <= 0.0:
        return Vector2.ZERO
    var direction: Vector2 = req.knockback_direction
    if direction.length_squared() <= 0.0001:
        return Vector2.ZERO
    return PlaneMath.knockback_vector(Vector2.ZERO, direction, req.knockback)
