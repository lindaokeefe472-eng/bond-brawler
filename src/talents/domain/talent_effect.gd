## 天赋效果：把「节点加成」翻译成战斗系统能直接消费的对象。
##
## 效果本身是纯数据，不持有 rank —— 同一条效果被不同等级的天赋复用时，
## 由调用方传入 rank 决定强度，避免效果对象随天赋升级而变异。
class_name TalentEffect
extends RefCounted

const KIND_STAT_MODIFIER: StringName = &"stat_modifier"
const KIND_SKILL_UNLOCK: StringName = &"skill_unlock"

var kind: StringName = KIND_STAT_MODIFIER
var stat: StringName = &""
## 每级提供的固定值。最终贡献 = flat * stacks，stacks 由天赋等级决定。
var flat: float = 0.0
## 每级提供的百分比；0.15 = 每级 +15%。
var percent: float = 0.0
## 秒；< 0 表示永久。天赋加成默认永久。
var duration: float = -1.0
## kind == skill_unlock 时要解锁的技能 id。
var skill_id: StringName = &""

## 数据驱动构造：字段一律带默认值，坏数据降级而不是抛错（见 CONVENTIONS 3.7）。
static func from_dict(d: Dictionary) -> TalentEffect:
    var effect := TalentEffect.new()
    effect.kind = StringName(str(d.get("kind", String(KIND_STAT_MODIFIER))))
    effect.stat = StringName(str(d.get("stat", "")))
    effect.flat = float(d.get("flat", 0.0))
    effect.percent = float(d.get("percent", 0.0))
    effect.duration = float(d.get("duration", -1.0))
    effect.skill_id = StringName(str(d.get("skill_id", "")))
    return effect

static func stat_modifier(p_stat: StringName, p_flat: float = 0.0, p_percent: float = 0.0, p_duration: float = -1.0) -> TalentEffect:
    var effect := TalentEffect.new()
    effect.kind = KIND_STAT_MODIFIER
    effect.stat = p_stat
    effect.flat = p_flat
    effect.percent = p_percent
    effect.duration = p_duration
    return effect

static func skill_unlock(p_skill_id: StringName) -> TalentEffect:
    var effect := TalentEffect.new()
    effect.kind = KIND_SKILL_UNLOCK
    effect.skill_id = p_skill_id
    return effect

func is_stat_modifier() -> bool:
    return kind == KIND_STAT_MODIFIER

func is_skill_unlock() -> bool:
    return kind == KIND_SKILL_UNLOCK

## 按等级换算后的固定值，方便 UI 直接显示「+15 攻击」。
func scaled_flat(rank: int) -> float:
    return flat * float(maxi(rank, 0))

func scaled_percent(rank: int) -> float:
    return percent * float(maxi(rank, 0))

func to_dict() -> Dictionary:
    return {
        "kind": String(kind),
        "stat": String(stat),
        "flat": flat,
        "percent": percent,
        "duration": duration,
        "skill_id": String(skill_id),
    }

## 生成 CombatModifier；非 stat_modifier 效果返回 null。
## 数值保持「每级」口径，用 stacks = rank 表达等级，交给 CombatActorStats 聚合，
## 这样同一 id 的修改器重复添加时仍能按契约里的 stacks 语义正确叠加。
func to_modifier(modifier_id: StringName, source: StringName, rank: int = 1) -> CombatModifier:
    if not is_stat_modifier():
        return null
    var modifier := CombatModifier.make(stat, flat, percent, duration)
    modifier.id = modifier_id
    modifier.source = source
    var clamped_rank: int = maxi(rank, 1)
    modifier.stacks = clamped_rank
    modifier.max_stacks = clamped_rank
    return modifier

func _to_string() -> String:
    if is_skill_unlock():
        return "TalentEffect(skill_unlock:%s)" % skill_id
    return "TalentEffect(%s flat=%.3f percent=%.3f)" % [stat, flat, percent]
