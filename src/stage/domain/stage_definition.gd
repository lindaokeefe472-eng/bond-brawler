## 关卡定义：这一段关卡刷哪些怪、每只怪用哪套 AI 性格。
##
## 之前刷怪表写死在 GameRoot 的常量里，而且所有敌人共用一套 ENEMY_BRAIN_PROFILE ——
## 三只怪行为一模一样，也没法按关卡调难度。现在全部来自 data/stages.json。
class_name StageDefinition
extends RefCounted

const DEFAULT_BRAIN: StringName = &"default"
const DEFAULT_AGGRESSION: float = 0.7

var id: StringName = &""
var display_name: String = ""
## 每条：{species: StringName, character: String, plane_pos: Vector2, brain: StringName}
var spawns: Array = []
## StringName -> Dictionary，AI 性格参数。
var brains: Dictionary = {}

static func from_dict(d: Dictionary, shared_brains: Dictionary = {}) -> StageDefinition:
	var stage := StageDefinition.new()
	stage.id = StringName(str(d.get("id", "")))
	stage.display_name = str(d.get("name", String(stage.id)))
	stage.brains = shared_brains.duplicate(true)
	var local_brains: Variant = d.get("brains", {})
	if local_brains is Dictionary:
		for key: Variant in (local_brains as Dictionary).keys():
			stage.brains[StringName(str(key))] = (local_brains as Dictionary)[key]
	var raw_spawns: Variant = d.get("spawns", [])
	if raw_spawns is Array:
		for entry: Variant in raw_spawns:
			if not (entry is Dictionary):
				continue
			var spawn: Dictionary = entry
			stage.spawns.append({
				"species": StringName(str(spawn.get("species", ""))),
				"character": str(spawn.get("character", "")),
				"plane_pos": _as_vec2(spawn.get("plane_pos", [0.0, 0.0])),
				"brain": StringName(str(spawn.get("brain", String(DEFAULT_BRAIN)))),
			})
	return stage

## 取某套性格。没配就返回空字典，调用方自己决定兜底。
func brain_profile(brain_id: StringName) -> Dictionary:
	var raw: Variant = brains.get(brain_id, null)
	return raw if raw is Dictionary else {}

func spawn_count() -> int:
	return spawns.size()

## 数据校验用：这一关引用到的性格 id 是否都有定义。
func missing_brains() -> Array[StringName]:
	var out: Array[StringName] = []
	for spawn: Dictionary in spawns:
		var brain: StringName = spawn.get("brain", DEFAULT_BRAIN)
		if brain == DEFAULT_BRAIN and brains.has(DEFAULT_BRAIN):
			continue
		if not brains.has(brain) and not out.has(brain):
			out.append(brain)
	return out

static func _as_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO
