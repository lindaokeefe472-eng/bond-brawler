## 天赋树：节点集合构成的有向无环图（DAG）+ 每个节点已投入的 rank。
##
## 为什么是 DAG 而不是树：一个天赋允许被多个前置共同解锁（流派交叉），
## 但绝不允许成环 —— 成环会让「前置全部激活」永远无法满足，整棵子树死锁。
## 因此在 add_node 阶段就拒绝成环，而不是等 can_unlock 永远返回 false。
class_name TalentTree
extends RefCounted

## 快照格式版本。存档迁移时据此判断是否需要转换。
const SNAPSHOT_VERSION: int = 1

var _nodes: Dictionary = {}          # StringName -> TalentNode
var _order: Array[StringName] = []   # 插入顺序：让 modifiers_for / snapshot 输出稳定
var _points: int = 0
var _bus: DomainEventBus = null

func _init(bus: DomainEventBus) -> void:
    _bus = bus

# ------------------------------------------------------------------ 构建
## 加入节点。重复 id 或会形成环时告警并拒绝，保持已有图不变。
func add_node(node: TalentNode) -> void:
    if node == null:
        push_error("TalentTree.add_node: 节点为 null")
        return
    if node.id == &"":
        push_error("TalentTree.add_node: 节点缺少 id")
        return
    if _nodes.has(node.id):
        push_warning("TalentTree.add_node: 节点 id 重复 %s" % node.id)
        return
    if _would_create_cycle(node):
        push_warning("TalentTree.add_node: 节点 %s 会形成环，已拒绝" % node.id)
        return
    node.max_rank = maxi(1, node.max_rank)
    node.cost = maxi(0, node.cost)
    node.rank = clampi(node.rank, 0, node.max_rank)
    _nodes[node.id] = node
    _order.append(node.id)

func find_node(id: StringName) -> TalentNode:
    return _nodes.get(id, null)

func has_talent(id: StringName) -> bool:
    return _nodes.has(id)

func node_ids() -> Array[StringName]:
    return _order.duplicate()

# ------------------------------------------------------------------ 点数
func available_points() -> int:
    return _points

func grant_points(n: int) -> void:
    if n < 0:
        push_warning("TalentTree.grant_points: 点数不能为负 (%d)" % n)
        return
    _points += n

## 已投入的总点数（洗点返还的依据）。
func total_spent_points() -> int:
    var total: int = 0
    for id: StringName in _order:
        var node: TalentNode = _nodes[id]
        total += node.rank * node.cost
    return total

# ------------------------------------------------------------------ 解锁
## 可解锁 = 节点存在 + 未满级 + 点数够 + 所有前置已激活。
func can_unlock(id: StringName) -> bool:
    var node: TalentNode = _nodes.get(id, null)
    if node == null:
        return false
    if not node.can_rank_up():
        return false
    if _points < node.cost:
        return false
    for prereq: StringName in node.prerequisites:
        if _rank_of(prereq) <= 0:
            return false
    return true

## 投一点到该节点。失败返回 false 且不改动任何状态（调用方可直接用来做按钮反馈）。
func unlock(id: StringName) -> bool:
    if not can_unlock(id):
        return false
    var node: TalentNode = _nodes[id]
    _points -= node.cost
    _set_rank(node, node.rank + 1)
    if _bus != null:
        _bus.emit_type(GameConstants.EVT_TALENT_UNLOCKED, {
            "talent_id": id,
            "rank": node.rank,
            "max_rank": node.max_rank,
            "cost": node.cost,
            "points_left": _points,
        })
    return true

## 洗点：清空全部 rank，返还已投入的总点数。返回返还值。
## 即使返还为 0 也要清空 —— 0 费节点不产生返还，但它的 rank 同样必须洗掉。
func respec() -> int:
    var refund: int = total_spent_points()
    for id: StringName in _order:
        _set_rank(_nodes[id], 0)
    _points += refund
    return refund

## 节点当前状态，语义与 TalentNode.state 一致（0 LOCKED / 1 AVAILABLE / 2 ACTIVE）。
func state_of(id: StringName) -> int:
    var node: TalentNode = _nodes.get(id, null)
    if node == null:
        return TalentNode.LOCKED
    return node.state(unlocked_map())

## 已激活节点快照，id -> rank。0 值同样视为未激活，方便直接喂给 TalentNode.state。
func unlocked_map() -> Dictionary:
    var out: Dictionary = {}
    for id: StringName in _order:
        var rank: int = _rank_of(id)
        if rank > 0:
            out[id] = rank
    return out

# ------------------------------------------------------------------ 效果
## 把已激活节点的效果折算成战斗修改器。
## actor_id 进入修改器 id：同一棵树若被多个角色共享，各角色的修改器不会互相覆盖。
func modifiers_for(actor_id: int) -> Array[CombatModifier]:
    var out: Array[CombatModifier] = []
    for id: StringName in _order:
        var node: TalentNode = _nodes[id]
        if node.rank <= 0:
            continue
        for i: int in range(node.effects.size()):
            var effect: Variant = node.effects[i]
            if not (effect is TalentEffect):
                continue
            var modifier_id: StringName = StringName("talent:%d:%s:%d" % [actor_id, node.id, i])
            var modifier: CombatModifier = effect.to_modifier(modifier_id, node.id, node.rank)
            if modifier != null:
                out.append(modifier)
    return out

## 已激活的 skill_unlock 效果汇总（去重，保持解锁顺序）。
func unlocked_skills() -> Array[StringName]:
    var out: Array[StringName] = []
    for id: StringName in _order:
        var node: TalentNode = _nodes[id]
        if node.rank <= 0:
            continue
        for effect: Variant in node.effects:
            if effect is TalentEffect and effect.is_skill_unlock():
                if effect.skill_id != &"" and not out.has(effect.skill_id):
                    out.append(effect.skill_id)
    return out

# ------------------------------------------------------------------ 存档
func snapshot() -> Dictionary:
    var ranks: Dictionary = {}
    for id: StringName in _order:
        ranks[id] = _rank_of(id)
    return {
        "version": SNAPSHOT_VERSION,
        "points": _points,
        "ranks": ranks,
    }

## 恢复存档。空数据视为「没有存档」，保持当前状态而不是把进度清零。
## 未知节点 id 忽略，缺失节点按 0 级处理 —— 让旧存档在天赋表扩容后仍可加载。
func restore(data: Dictionary) -> void:
    if data.is_empty():
        push_warning("TalentTree.restore: 存档为空，忽略")
        return
    var version: int = int(data.get("version", SNAPSHOT_VERSION))
    if version > SNAPSHOT_VERSION:
        push_warning("TalentTree.restore: 存档版本 %d 高于当前 %d，尝试按当前格式读取" % [version, SNAPSHOT_VERSION])
    _points = maxi(0, int(data.get("points", 0)))
    var normalized: Dictionary = _normalize_ranks(data.get("ranks", {}))
    for id: StringName in _order:
        var node: TalentNode = _nodes[id]
        _set_rank(node, int(normalized.get(id, 0)))

# ------------------------------------------------------------------ 内部
func _rank_of(id: StringName) -> int:
    var node: TalentNode = _nodes.get(id, null)
    return node.rank if node != null else 0

func _set_rank(node: TalentNode, rank: int) -> void:
    node.rank = clampi(rank, 0, node.max_rank)

## 新节点的入边是 prerequisites。沿「节点 -> 前置」反向走，
## 若能走回新节点自身，说明加上这条边后成环。
func _would_create_cycle(node: TalentNode) -> bool:
    var stack: Array[StringName] = node.prerequisites.duplicate()
    var seen: Dictionary = {}
    while not stack.is_empty():
        var current: StringName = stack.pop_back()
        if current == node.id:
            return true
        if seen.has(current):
            continue
        seen[current] = true
        var other: TalentNode = _nodes.get(current, null)
        if other == null:
            continue
        for prereq: StringName in other.prerequisites:
            stack.append(prereq)
    return false

## 存档里的键可能是 JSON 读回来的 String，统一成 StringName 再查表。
func _normalize_ranks(raw: Variant) -> Dictionary:
    var out: Dictionary = {}
    if not (raw is Dictionary):
        return out
    for key: Variant in raw.keys():
        out[StringName(str(key))] = int(raw[key])
    return out
