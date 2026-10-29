## 种族仓库：data/species.json 是数组，对外直接给原始字典。
##
## 为什么不建 SpeciesDef：ARCHITECTURE 目前没有种族定义契约，领域层只是按需读字段；
## 过早定型会锁死数据策划的字段演进。等出现第二个消费者、字段稳定后再抽类。
class_name SpeciesRepository
extends RefCounted

const SOURCE_STARTER: String = "starter"

var _by_id: Dictionary = {}          # StringName -> Dictionary
var _all: Array[Dictionary] = []
var _starters: Array[Dictionary] = []

func _init(data: IDataSource) -> void:
	_load(data)

func find(id: StringName) -> Dictionary:
	var value: Variant = _by_id.get(StringName(str(id)), null)
	return value if value is Dictionary else {}

## 返回内部数组，调用方只读遍历；保持数据文件顺序（已按 id 升序）。
func all() -> Array[Dictionary]:
	return _all

## 首个可玩种族。数据里 source == "starter" 有 5 个（各系一只），
## 这里取数据顺序的第一个；需要全部候选时用 starters()。
func starter() -> Dictionary:
	if not _starters.is_empty():
		return _starters[0]
	if not _all.is_empty():
		return _all[0]
	return {}

func starters() -> Array[Dictionary]:
	return _starters

func size() -> int:
	return _all.size()

func _load(data: IDataSource) -> void:
	var raw: Variant = data.read_json("species.json")
	if not (raw is Array):
		push_warning("SpeciesRepository: species.json 不是数组，种族表为空")
		return
	for entry: Variant in raw:
		if not (entry is Dictionary):
			push_warning("SpeciesRepository: 跳过非字典种族条目")
			continue
		var species: Dictionary = entry
		var id: String = str(species.get("id", ""))
		if id.is_empty():
			push_warning("SpeciesRepository: 跳过缺少 id 的种族条目")
			continue
		var key: StringName = StringName(id)
		if _by_id.has(key):
			push_warning("SpeciesRepository: 种族 id 重复 %s，保留先出现的一条" % id)
			continue
		_by_id[key] = species
		_all.append(species)
		if str(species.get("source", "")) == SOURCE_STARTER:
			_starters.append(species)
