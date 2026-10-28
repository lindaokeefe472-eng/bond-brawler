## 天赋树节点：DAG 上的一个可重复投入点数的条目。
##
## 设计取舍：
##   - rank 是「已投入几级」的唯一权威，节点自身不缓存「能否解锁」这类派生状态，
##     因此存档只需要搬运 rank，回滚时不会留下不一致的布尔位。
##   - state() 接收外部快照而不是直接查树，是为了让 UI 能用一份只读字典渲染整棵树，
##     而不必为了画一个节点去反向调用 TalentTree。
class_name TalentNode
extends RefCounted

## state() 的返回值。契约固定 0/1/2，UI 可直接当数组下标使用。
enum { LOCKED, AVAILABLE, ACTIVE }

var id: StringName = &""
var name: String = ""
var max_rank: int = 1
var rank: int = 0
var cost: int = 1
var prerequisites: Array[StringName] = []
var effects: Array = []

## 数据驱动构造：字段一律带默认值，坏数据降级而不是抛错（见 CONVENTIONS 3.7）。
static func from_dict(d: Dictionary) -> TalentNode:
    var node := TalentNode.new()
    node.id = StringName(str(d.get("id", "")))
    node.name = str(d.get("name", String(node.id)))
    node.max_rank = maxi(1, int(d.get("max_rank", 1)))
    node.cost = maxi(0, int(d.get("cost", 1)))
    var prereqs: Variant = d.get("prerequisites", [])
    if prereqs is Array:
        for p: Variant in prereqs:
            node.prerequisites.append(StringName(str(p)))
    var raw_effects: Variant = d.get("effects", [])
    if raw_effects is Array:
        for e: Variant in raw_effects:
            if e is TalentEffect:
                node.effects.append(e)
            elif e is Dictionary:
                node.effects.append(TalentEffect.from_dict(e))
    return node

func is_active() -> bool:
    return rank > 0

func is_max_rank() -> bool:
    return rank >= max_rank

## 该节点自身是否还能继续投入点数。
func can_rank_up() -> bool:
    return rank < max_rank

## tree_unlocked: 树内已激活节点的快照，id -> 已激活（值为 0 / false 视为未激活）。
## 先看自身 rank 再看快照，是为了让「刚解锁、快照还没刷新」的节点也能立刻显示为 ACTIVE。
func state(tree_unlocked: Dictionary) -> int:
    if is_active() or bool(tree_unlocked.get(id, false)):
        return ACTIVE
    for prereq: StringName in prerequisites:
        if not bool(tree_unlocked.get(prereq, false)):
            return LOCKED
    return AVAILABLE

func _to_string() -> String:
    return "TalentNode(%s rank=%d/%d)" % [id, rank, max_rank]
