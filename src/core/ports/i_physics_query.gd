## 出站端口：场景物理查询。
## 只有「关卡几何」走物理（墙、地面、门）；角色之间的命中判定一律在领域层用
## PlaneMath 纯计算完成，保证确定性、可单测、可回放。
class_name IPhysicsQuery
extends RefCounted

## 射线检测。命中返回 {hit: bool, point: Vector3, normal: Vector3, collider_id: int}
func raycast(_from: Vector3, _to: Vector3, _mask: int) -> Dictionary:
	push_error("IPhysicsQuery.raycast() 未实现")
	return {"hit": false}

## 球形重叠，返回碰撞体实例 id 列表。
func overlap_sphere(_center: Vector3, _radius: float, _mask: int) -> Array[int]:
	push_error("IPhysicsQuery.overlap_sphere() 未实现")
	return []
