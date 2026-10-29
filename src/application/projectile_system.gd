## 弹体管理器：生成、推进、命中结算、回收。
##
## 为什么单独成类而不是塞进 BattleSession：会话只该决定「什么时候发生」。
## 弹体是一条独立的流水线（齐射排期 -> 移动 -> 命中 -> 回收），
## 拆出来才能脱离整局战斗单独测。
class_name ProjectileSystem
extends RefCounted

## 同时存在的弹体上限。超了就不再生成，避免刷屏技能把帧率拖垮。
const MAX_ACTIVE: int = 96
const TIME_EPSILON: float = 0.000001

## 横向出界阈值（米），0 表示不限。撞墙就回收，避免弹体飞到天边还占着槽位。
var bounds_x: float = 0.0

var _items: Array[Projectile] = []
## 齐射里还没到点的后续几发。
var _pending: Array[Dictionary] = []
var _next_id: int = 1

func items() -> Array[Projectile]:
	return _items

func active_count() -> int:
	return _items.size()

func pending_count() -> int:
	return _pending.size()

func clear() -> void:
	_items.clear()
	_pending.clear()
	_next_id = 1

## 从技能事件负载生成弹体，字段名与 SkillSpawnProjectileEffect 的 payload 一致。
## 返回本次「立刻」生成的数量；齐射的后续几发按 interval 排队，要等 tick 才出来。
func spawn_from_payload(owner_id: int, faction: StringName, payload: Dictionary) -> int:
	var count: int = maxi(int(payload.get("count", 1)), 1)
	var interval: float = maxf(float(payload.get("interval", 0.0)), 0.0)
	var origin: Vector2 = _as_vec2(payload.get("origin", Vector2.ZERO))
	var facing: int = 1 if int(payload.get("facing", 1)) >= 0 else -1
	var spread: float = float(payload.get("spread", 0.0))
	var base: Dictionary = {
		"speed": float(payload.get("speed", 0.0)),
		"power": float(payload.get("power", 0.0)),
		"damage_type": payload.get("damage_type", &"neutral"),
		"knockback": float(payload.get("knockback", 0.0)),
		"piercing": bool(payload.get("piercing", false)),
		"lifetime": float(payload.get("lifetime", 0.0)),
		"range": float(payload.get("range", 0.0)),
		"radius": float(payload.get("radius", Projectile.DEFAULT_RADIUS)),
		"height": float(payload.get("height", 1.0)),
		"sprite": payload.get("sprite", ""),
	}
	var spawned: int = 0
	for i: int in range(count):
		var config: Dictionary = base.duplicate()
		# 以朝向为轴左右对称摊开：count=3、spread=0.1 -> -0.1 / 0 / +0.1
		config["angle"] = (float(i) - float(count - 1) * 0.5) * spread
		if i == 0 or interval <= 0.0:
			_spawn_one(owner_id, faction, origin, facing, config)
			spawned += 1
		else:
			_pending.append({
				"owner_id": owner_id,
				"faction": faction,
				"origin": origin,
				"facing": facing,
				"config": config,
				"delay": interval * float(i),
				"elapsed": 0.0,
			})
	return spawned

## 推进一帧：先放齐射排期，再移动，再按顺序结算命中，最后回收。
## actors 只需要有 id / faction / plane_pos / is_alive()，测试可以用替身。
## apply_hit: func(projectile, target) -> Variant，返回值非 null 就收进结果里。
func tick(dt: float, actors: Dictionary, apply_hit: Callable) -> Array:
	var step: float = maxf(dt, 0.0)
	_flush_pending(step)
	for shot: Projectile in _items:
		shot.step(step)
		if bounds_x > 0.0 and absf(shot.plane_pos.x) > bounds_x:
			shot.alive = false
	var results: Array = []
	for shot: Projectile in _items:
		if not shot.alive:
			continue
		for key: Variant in actors.keys():
			var target: Variant = actors[key]
			if target == null or not target.is_alive():
				continue
			if not shot.can_hit(int(target.id), target.faction, target.plane_pos):
				continue
			if apply_hit.is_valid():
				var outcome: Variant = apply_hit.call(shot, target)
				if outcome != null:
					results.append(outcome)
			shot.register_hit(int(target.id))
			if not shot.alive:
				break
	var kept: Array[Projectile] = []
	for shot: Projectile in _items:
		if shot.alive:
			kept.append(shot)
	_items = kept
	return results

func _flush_pending(dt: float) -> void:
	if _pending.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		entry["elapsed"] = float(entry["elapsed"]) + dt
		if float(entry["elapsed"]) + TIME_EPSILON >= float(entry["delay"]):
			_spawn_one(int(entry["owner_id"]), StringName(entry["faction"]),
					entry["origin"] as Vector2, int(entry["facing"]), entry["config"] as Dictionary)
		else:
			remaining.append(entry)
	_pending = remaining

func _spawn_one(owner_id: int, faction: StringName, origin: Vector2, facing: int,
		config: Dictionary) -> void:
	if _items.size() >= MAX_ACTIVE:
		return
	var shot: Projectile = Projectile.create(owner_id, faction, origin, facing, config)
	shot.id = _next_id
	_next_id += 1
	_items.append(shot)

static func _as_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO
