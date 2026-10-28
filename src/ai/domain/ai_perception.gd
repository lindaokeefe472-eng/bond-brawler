## 把外部原始观测整理成 AiBlackboard 的静态工厂。
##
## 为什么由这里算 distance / aligned：这两个派生量必须和战斗窄相用同一套几何
## （PlaneMath），否则 AI 以为能打、判定却不中，敌人会贴着空气挥拳。
class_name AiPerception
extends RefCounted

## 类型化入口：调用方通常已经拿到了各个字段。
static func observe(self_id: int, self_pos: Vector2, self_hp_ratio: float,
        target_id: int, target_pos: Vector2, target_hp_ratio: float,
        target_guarding: bool, skill_ready: Array, time: float,
        threat: float = 0.0) -> AiBlackboard:
    var bb := AiBlackboard.new()
    bb.self_id = self_id
    bb.self_pos = self_pos
    bb.self_hp_ratio = clampf(self_hp_ratio, 0.0, 1.0)
    bb.target_id = target_id
    bb.target_pos = target_pos
    bb.target_hp_ratio = clampf(target_hp_ratio, 0.0, 1.0)
    bb.target_guarding = target_guarding
    bb.skill_ready = _sanitize_ready(skill_ready)
    bb.distance = PlaneMath.distance(self_pos, target_pos)
    bb.aligned = PlaneMath.is_aligned(self_pos, target_pos)
    bb.threat = clampf(threat, 0.0, 1.0)
    bb.time = time
    return bb

## 字典入口：适配器 / 回放拿到的通常就是一包原始观测。
## 说明：观测里的 "self_facing" 不写进黑板 —— 契约没有朝向字段，AI 的正面判定
## 只用纵深对齐；保留该键不报错，是为了调用方能原样传整包观测而不必拆字段。
static func from_observation(raw: Dictionary) -> AiBlackboard:
    var raw_ready: Variant = raw.get("skill_ready", [])
    var ready: Array = raw_ready if raw_ready is Array else []
    return observe(
        int(raw.get("self_id", -1)),
        _as_vec2(raw.get("self_pos", Vector2.ZERO)),
        float(raw.get("self_hp_ratio", 1.0)),
        int(raw.get("target_id", -1)),
        _as_vec2(raw.get("target_pos", Vector2.ZERO)),
        float(raw.get("target_hp_ratio", 1.0)),
        bool(raw.get("target_guarding", false)),
        ready,
        float(raw.get("time", 0.0)),
        float(raw.get("threat", 0.0))
    )

## 第一个就绪槽位；没有则 -1。AI 选技能时按槽位序号取第一个，
## 保证同样的观测永远得到同样的技能选择（可回放）。
static func first_ready_slot(bb: AiBlackboard) -> int:
    if bb == null:
        return -1
    for i: int in range(bb.skill_ready.size()):
        if bb.skill_ready[i]:
            return i
    return -1

static func _sanitize_ready(raw: Array) -> Array[bool]:
    var out: Array[bool] = []
    for value: Variant in raw:
        out.append(bool(value))
    return out

static func _as_vec2(value: Variant) -> Vector2:
    if value is Vector2:
        return value
    return Vector2.ZERO
