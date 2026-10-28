## 纯位移效果：用于没有伤害、只需要把目标推开/拉近的模板。
## 方向由 origin 与朝向给出，具体落点由 locomotion 决定。
class_name SkillKnockbackEffect
extends SkillEffect

var strength: float = 0.0
var is_aerial: bool = false

func _init(p_strength: float = 0.0, p_is_aerial: bool = false) -> void:
    strength = p_strength
    is_aerial = p_is_aerial

func apply(ctx: SkillEffectContext) -> void:
    if ctx == null:
        return
    var direction: Vector2 = Vector2(float(ctx.facing), 0.0)
    for target_id: int in ctx.target_ids:
        ctx.emit_event(EVT_KNOCKBACK, {
            "attacker_id": ctx.caster_id,
            "target_id": target_id,
            "strength": strength,
            "direction": direction,
            "is_aerial": is_aerial,
        })
