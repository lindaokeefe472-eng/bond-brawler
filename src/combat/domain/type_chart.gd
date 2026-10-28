## 属性克制表。数据来自 data/type_chart.json，本类只做查表与相乘，不内置任何倍率。
## 为什么同时接受中文名：数据表与调试工具里直接写「火」更直观，
## 但内部统一用英文 id 计算，避免两套键名分裂。
class_name CombatTypeChart
extends RefCounted

var _chart: Dictionary = {}
var _names: Dictionary = {}

func _init(chart: Dictionary, names: Dictionary) -> void:
    _chart = chart if chart != null else {}
    _names = names if names != null else {}

## 双属性相乘（1.2 * 0.2 = 0.24）。未知属性、空防御属性都按 1.0 处理，
## 保证数据缺漏时伤害不会归零或爆表。
func multiplier(attack_type: StringName, defender_types: Array[StringName]) -> float:
    if defender_types.is_empty():
        return 1.0
    var row: Dictionary = _row_for(attack_type)
    if row.is_empty():
        return 1.0
    var result: float = 1.0
    for defender_type: StringName in defender_types:
        result *= _entry(row, defender_type)
    return result

func _row_for(attack_type: StringName) -> Dictionary:
    var row: Variant = _chart.get(String(attack_type), null)
    if row == null:
        row = _chart.get(attack_type, null)
    if row == null:
        var display_key: StringName = _key_from_display(String(attack_type))
        if display_key != &"":
            row = _chart.get(String(display_key), _chart.get(display_key, null))
    if row is Dictionary:
        return row
    return {}

func _entry(row: Dictionary, defender_type: StringName) -> float:
    var value: Variant = row.get(String(defender_type), null)
    if value == null:
        value = row.get(defender_type, null)
    if value == null:
        var display_key: StringName = _key_from_display(String(defender_type))
        if display_key != &"":
            value = row.get(String(display_key), row.get(display_key, null))
    if value == null:
        return 1.0
    return float(value)

## 反向查中文名 -> 英文 id。数据表很小，线性扫描足够，不值得建第二份索引。
func _key_from_display(display: String) -> StringName:
    if display.is_empty():
        return &""
    for key: Variant in _names.keys():
        if str(_names[key]) == display:
            return StringName(str(key))
    return &""
