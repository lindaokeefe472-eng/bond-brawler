## 关卡表：读 data/stages.json，按 id 取关卡定义。
##
## 读不到文件时返回空，由 GameRoot 退回内置的兜底刷怪表 —— 公开仓库不含 data/，
## 缺数据也要能跑起来。
class_name StageRepository
extends RefCounted

const STAGES_FILE: String = "stages.json"

var _stages: Dictionary = {}
var _order: Array[StringName] = []

func _init(source: JsonDataSource = null) -> void:
	if source == null:
		return
	_parse(source.read_json(STAGES_FILE))

func find(id: StringName) -> StageDefinition:
	var raw: Variant = _stages.get(id, null)
	return raw as StageDefinition

func first() -> StageDefinition:
	if _order.is_empty():
		return null
	return find(_order[0])

func all_ids() -> Array[StringName]:
	return _order.duplicate()

func is_empty() -> bool:
	return _order.is_empty()

func _parse(raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	var data: Dictionary = raw
	var shared: Dictionary = {}
	var raw_brains: Variant = data.get("brains", {})
	if raw_brains is Dictionary:
		for key: Variant in (raw_brains as Dictionary).keys():
			shared[StringName(str(key))] = (raw_brains as Dictionary)[key]
	var raw_stages: Variant = data.get("stages", [])
	if not (raw_stages is Array):
		return
	for entry: Variant in raw_stages:
		if not (entry is Dictionary):
			continue
		var stage: StageDefinition = StageDefinition.from_dict(entry, shared)
		if stage.id == &"":
			continue
		_stages[stage.id] = stage
		_order.append(stage.id)
