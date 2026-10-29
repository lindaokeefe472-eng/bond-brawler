## 音效表：cue 名 -> 资源路径 + 播放参数。
##
## 只负责读数据，不碰音频引擎 —— 所以「cue 有没有映射、文件在不在」
## 可以用纯数据测试钉住（tests/unit/infrastructure/test_audio_library.gd）。
class_name AudioLibrary
extends RefCounted

## 放在 assets 而不是 data：这份映射和占位音效都是本仓库自产的，
## 不像 data/ 那样受版权限制，可以随仓库分发。
const AUDIO_FILE: String = "res://assets/audio/cues.json"
const REQUIRED_FIELDS: Array[String] = [
	"file", "bus", "volume_db", "pitch_jitter", "debounce", "voices",
]
const DEFAULT_BUS: StringName = &"sfx"

var _buses: Array[StringName] = []
var _cues: Dictionary = {}

func _init(source: JsonDataSource = null) -> void:
	if source == null:
		return
	_parse(source.read_json(AUDIO_FILE))

func has_cue(id: StringName) -> bool:
	return _cues.has(String(id))

func cue(id: StringName) -> Dictionary:
	var raw: Variant = _cues.get(String(id), {})
	return raw if raw is Dictionary else {}

func cue_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: String in _cues.keys():
		out.append(StringName(key))
	out.sort()
	return out

func buses() -> Array[StringName]:
	return _buses

func _parse(raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	var data: Dictionary = raw
	var raw_buses: Variant = data.get("buses", [])
	if raw_buses is Array:
		for entry: Variant in raw_buses:
			_buses.append(StringName(str(entry)))
	if not _buses.has(&"master"):
		_buses.push_front(&"master")
	var raw_cues: Variant = data.get("cues", {})
	if raw_cues is Dictionary:
		_cues = (raw_cues as Dictionary).duplicate(true)
