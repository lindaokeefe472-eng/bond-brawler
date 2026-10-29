## 增益效果：只发 buff 事件，由 combat 的 CombatModifier 系统落实数值。
## percent 用 0.15 表示 +15%，与 CombatModifier 的语义保持一致。
class_name SkillBuffEffect
extends SkillEffect

var stat: StringName = &"attack"
var flat: float = 0.0
var percent: float = 0.0
var duration: float = 0.0
var stacks: int = 1
var buff_id: StringName = &""

func _init(p_stat: StringName = &"attack",
		p_flat: float = 0.0,
		p_percent: float = 0.0,
		p_duration: float = 0.0,
		p_stacks: int = 1,
		p_buff_id: StringName = &"") -> void:
	stat = p_stat
	flat = p_flat
	percent = p_percent
	duration = p_duration
	stacks = p_stacks
	buff_id = p_buff_id

func apply(ctx: SkillEffectContext) -> void:
	if ctx == null:
		return
	ctx.emit_event(EVT_BUFF_APPLIED, {
		"actor_id": ctx.caster_id,
		"source_id": ctx.caster_id,
		"buff_id": buff_id,
		"stat": stat,
		"flat": flat,
		"percent": percent,
		"duration": duration,
		"stacks": stacks,
	})
