## 2.5D 平面几何：把「横轴 + 纵深带」的判定逻辑收敛成纯函数。
## 这是清版动作游戏手感的核心，独立可测，不依赖任何节点。
class_name PlaneMath
extends RefCounted

## 两点是否在同一纵深带上（可互相命中）。
static func is_aligned(a: Vector2, b: Vector2, tolerance: float = GameConstants.LANE_ALIGN_TOLERANCE) -> bool:
    return absf(a.y - b.y) <= tolerance

## 平面距离（含纵深权重）。depth_weight > 1 表示纵深方向更「难」够到。
static func distance(a: Vector2, b: Vector2, depth_weight: float = 1.0) -> float:
    var dx: float = a.x - b.x
    var dy: float = (a.y - b.y) * depth_weight
    return sqrt(dx * dx + dy * dy)

## b 是否落在 a 面前的一个扇形判定里。
##   reach     : 前向长度
##   half_arc  : 半张角（弧度），0 = 纯矩形
static func in_cone(a: Vector2, facing: int, b: Vector2, reach: float, half_arc: float = 0.0) -> bool:
    var forward: float = (b.x - a.x) * float(facing)
    if forward < -GameConstants.BODY_RADIUS:
        return false
    if forward > reach:
        return false
    if not is_aligned(a, b):
        return false
    if half_arc <= 0.0:
        return true
    var depth: float = absf(b.y - a.y)
    return depth <= forward * tan(half_arc) + GameConstants.BODY_RADIUS

## 把纵深限制在关卡允许的带宽内。
static func clamp_lane(p: Vector2) -> Vector2:
    return Vector2(p.x, clampf(p.y, GameConstants.LANE_MIN, GameConstants.LANE_MAX))

## 由输入方向得到朝向（-1 左 / 1 右），0 时保持原朝向。
static func facing_from_input(dx: float, current: int) -> int:
    if dx > 0.01:
        return 1
    if dx < -0.01:
        return -1
    return current

## 世界坐标 -> 平面坐标。
static func from_world(v: Vector3) -> Vector2:
    return Vector2(v.x, v.z)

## 平面坐标 -> 世界坐标（给定高度）。
static func to_world(p: Vector2, height: float = 0.0) -> Vector3:
    return Vector3(p.x, height, p.y)

## 击退位移：沿「攻击者 -> 目标」的方向施加，纵深方向权重衰减，避免飞出带外。
static func knockback_vector(from_pos: Vector2, to_pos: Vector2, strength: float, depth_weight: float = 0.55) -> Vector2:
    var dir: Vector2 = to_pos - from_pos
    if dir.length_squared() < 0.0001:
        dir = Vector2(1.0, 0.0)
    dir = dir.normalized()
    dir.y *= depth_weight
    return dir * strength
