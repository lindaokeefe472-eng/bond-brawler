## 战斗数值聚合：基础值 + 修饰器 -> 最终值。
## 领域层唯一允许读写血量的地方；物理层的碰撞体适配器永远不碰 current_hp。
class_name CombatActorStats
extends RefCounted

## 缺字段时的兜底。crit_rate / crit_mult 抄自 data/combat_params.json 的 hit 段，
## 这样即使外部数据缺字段，战斗手感也与数据表一致。
const DEFAULT_BASE: Dictionary = {
    &"max_hp": 100.0,
    &"attack": 10.0,
    &"defense": 0.0,
    &"speed": 6.0,
    &"weight": 1.0,
    &"crit_rate": 0.0625,
    &"crit_mult": 2.0,
    &"dodge": 0.0,
    &"poise": 0.0,
}

var actor_id: int
var current_hp: float = 0.0
## 防御方属性，用于克制倍率。契约未列此字段，但伤害管线必须有它，
## 否则 CombatDamageCalculator 无法知道该乘哪个倍率。
var types: Array[StringName] = []

var _base: Dictionary = {}
var _modifiers: Array[CombatModifier] = []

func _init(p_actor_id: int, base: Dictionary) -> void:
    actor_id = p_actor_id
    _base = DEFAULT_BASE.duplicate()
    # 记录调用方是否显式给了 max_hp：合并默认值之后再判断会把默认值当成用户输入。
    var has_max_hp: bool = false
    for raw_key: Variant in base.keys():
        # JSON 的键是 String，领域层内部统一成 StringName，避免两套键并存。
        var key: StringName = StringName(str(raw_key))
        _base[key] = base[raw_key]
        if key == &"max_hp":
            has_max_hp = true
    # 数据表里战斗血量叫 battle_hp，图鉴值叫 hp；调用方原样传字典时按优先级取。
    if not has_max_hp:
        for alias: StringName in [&"battle_hp", &"hp"]:
            if _base.has(alias):
                _base[&"max_hp"] = _base[alias]
                break
    types = _parse_types(_base.get(&"types", []))
    current_hp = max_hp()

## 同 id 再次添加：层数叠加（封顶 max_stacks）并刷新时长。
func add_modifier(m: CombatModifier) -> void:
    if m == null:
        return
    if m.id == &"":
        m.id = m.stat
    var existing: CombatModifier = _find(m.id)
    if existing == null:
        _modifiers.append(m)
    else:
        # max_stacks 取较大值：后续用默认构造的修饰器刷新时，不该把已有上限压低。
        existing.max_stacks = maxi(existing.max_stacks, m.max_stacks)
        existing.stacks = mini(existing.max_stacks, existing.stacks + maxi(0, m.stacks))
        existing.stat = m.stat
        existing.flat = m.flat
        existing.percent = m.percent
        existing.duration = m.duration
    _clamp_hp_to_max()

func remove_modifier(id: StringName) -> void:
    for i: int in range(_modifiers.size() - 1, -1, -1):
        if _modifiers[i].id == id:
            _modifiers.remove_at(i)
    _clamp_hp_to_max()

func clear_modifiers() -> void:
    _modifiers.clear()
    _clamp_hp_to_max()

func tick(dt: float) -> void:
    for i: int in range(_modifiers.size() - 1, -1, -1):
        if _modifiers[i].tick(dt):
            _modifiers.remove_at(i)
    # max_hp 修饰器可能刚好过期，血量要跟着回落。
    _clamp_hp_to_max()

## 最终值 = (基础值 + Σflat) * (1 + Σpercent)。百分比是加算，不是连乘，
## 这样多个 +10% 收益稳定，便于数值平衡。
func value(stat: StringName) -> float:
    var base_value: float = float(_base.get(stat, 0.0))
    var flat_sum: float = 0.0
    var percent_sum: float = 0.0
    for m: CombatModifier in _modifiers:
        if m.stat != stat:
            continue
        flat_sum += m.effective_flat()
        percent_sum += m.effective_percent()
    return (base_value + flat_sum) * (1.0 + percent_sum)

func max_hp() -> float:
    return value(&"max_hp")

func is_dead() -> bool:
    return current_hp <= 0.0

## 返回实际扣除值：溢出伤害不记负数血量。
func take_raw_damage(amount: float) -> float:
    if amount <= 0.0:
        return 0.0
    var actual: float = minf(amount, maxf(0.0, current_hp))
    current_hp = maxf(0.0, current_hp - actual)
    return actual

## 返回实际治疗量：不会超过 max_hp。
func heal(amount: float) -> float:
    if amount <= 0.0:
        return 0.0
    var missing: float = maxf(0.0, max_hp() - current_hp)
    var actual: float = minf(amount, missing)
    current_hp += actual
    return actual

func _find(id: StringName) -> CombatModifier:
    for m: CombatModifier in _modifiers:
        if m.id == id:
            return m
    return null

func _clamp_hp_to_max() -> void:
    # max_hp 被负向修饰器压到 0 以下时，clampf 的上下界会反过来，先兜底。
    var cap: float = maxf(0.0, max_hp())
    current_hp = clampf(current_hp, 0.0, cap)

## types 支持 "rock/flying"、["rock", "flying"] 或单个字符串三种写法。
static func _parse_types(raw: Variant) -> Array[StringName]:
    var out: Array[StringName] = []
    if raw is Array:
        for entry: Variant in raw:
            var text: String = str(entry).strip_edges()
            if not text.is_empty():
                out.append(StringName(text))
    elif raw is String or raw is StringName:
        for text: String in str(raw).split("/", false):
            var trimmed: String = text.strip_edges()
            if not trimmed.is_empty():
                out.append(StringName(trimmed))
    return out
