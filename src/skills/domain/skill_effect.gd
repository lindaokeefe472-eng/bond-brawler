## 效果器基类：技能激活时，由模板注册表产出一串效果，依次 apply。
##
## 铁律：效果器只发领域事件，绝不直接改血量/状态。
## 真正的伤害与状态结算在 combat 上下文完成，这样技能可以被单测、回放、同步。
class_name SkillEffect
extends RefCounted

## 复用 core 已有的事件名；技能独有的补充事件在下面本地定义，
## 避免为了几个事件去改公共的 GameConstants。
const EVT_DAMAGE: StringName = GameConstants.EVT_DAMAGE_APPLIED
const EVT_STATUS_APPLIED: StringName = GameConstants.EVT_STATUS_APPLIED
const EVT_HEALED: StringName = &"combat.healed"
const EVT_BUFF_APPLIED: StringName = &"combat.buff_applied"
const EVT_KNOCKBACK: StringName = &"skill.knockback_applied"
const EVT_PROJECTILE_SPAWNED: StringName = &"skill.projectile_spawned"

func apply(_ctx: SkillEffectContext) -> void:
    pass
