## 效果器执行上下文：把「谁放的、打谁、从哪放、朝哪、随机源、怎么发事件」打包。
##
## stats_provider 与 emit 用 Callable 而不是直接持有 bus / stats 对象，
## 是为了让效果器不知道事件总线和战斗系统的具体实现，只依赖这两个端口。
class_name SkillEffectContext
extends RefCounted

var caster_id: int = 0
var target_ids: Array[int] = []
var origin: Vector2 = Vector2.ZERO
var facing: int = 1
var rng: IRng = null
## func(actor_id: int) -> CombatActorStats，拿不到时返回 null。
var stats_provider: Callable = Callable()
## func(event: DomainEvent)，领域层唯一的对外出口。
var emit: Callable = Callable()

func _init(p_caster_id: int = 0,
        p_target_ids: Array[int] = [],
        p_origin: Vector2 = Vector2.ZERO,
        p_facing: int = 1,
        p_rng: IRng = null,
        p_stats_provider: Callable = Callable(),
        p_emit: Callable = Callable()) -> void:
    caster_id = p_caster_id
    # 复制一份，避免效果器之间或调用方后续改动互相影响。
    target_ids = p_target_ids.duplicate()
    origin = p_origin
    facing = p_facing if p_facing != 0 else 1
    rng = p_rng
    stats_provider = p_stats_provider
    emit = p_emit

## 统一出口：效果器只调这里，null 检查只写一次。
func emit_event(type: StringName, payload: Dictionary) -> void:
    if not emit.is_valid():
        return
    emit.call(DomainEvent.new(type, payload))
