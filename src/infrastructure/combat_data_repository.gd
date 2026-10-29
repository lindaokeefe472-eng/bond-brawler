## 战斗静态数据仓库：属性克制表 + 两份原始参数字典。
##
## 为什么不把 actions / combat_params 也解析成类：这两份是调参表，字段随玩法迭代
## 频繁增删；现阶段按「原始字典 + 调用方给默认值」暴露，能避免仓库层成为数据演进瓶颈。
## 属性表则必须包装成 combat 上下文的克制表对象，因为倍率查表规则（双属性相乘）
## 属于领域知识，不能散落在每个消费者手里。
##
## 依赖说明：infrastructure 是适配器，可以静态依赖领域上下文（见 ARCHITECTURE §1）。
class_name CombatDataRepository
extends RefCounted

var _type_chart: CombatTypeChart = null
var _type_names: Dictionary = {}
var _actions: Dictionary = {}
var _combat_params: Dictionary = {}

func _init(data: IDataSource) -> void:
	_load_type_chart(data)
	_actions = _read_dict(data, "actions.json")
	_combat_params = _read_dict(data, "combat_params.json")

## 永远非 null：数据缺失时也会构造一张「全 1.0」的克制表，战斗照常能跑。
func type_chart() -> CombatTypeChart:
	return _type_chart

func type_names() -> Dictionary:
	return _type_names

func actions() -> Dictionary:
	return _actions

func combat_params() -> Dictionary:
	return _combat_params

func _load_type_chart(data: IDataSource) -> void:
	var raw: Variant = data.read_json("type_chart.json")
	var chart: Dictionary = {}
	if raw is Dictionary:
		var doc: Dictionary = raw
		_type_names = _as_dict(doc.get("names", {}))
		chart = _as_dict(doc.get("chart", {}))
	else:
		push_warning("CombatDataRepository: type_chart.json 格式异常，克制表按全 1.0 处理")
	_type_chart = CombatTypeChart.new(chart, _type_names)

func _read_dict(data: IDataSource, file_name: String) -> Dictionary:
	var raw: Variant = data.read_json(file_name)
	if raw is Dictionary:
		return raw
	push_warning("CombatDataRepository: %s 缺失或格式异常，回退为空字典" % file_name)
	return {}

func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
