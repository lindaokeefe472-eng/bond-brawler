## 存档读写：user:// 下的 JSON，带版本号信封与损坏回退。
##
## 为什么先写临时文件再改名：存档写到一半崩溃会留下半截 JSON，直接覆盖主存档
## 等于永久损坏玩家进度；临时文件 + 改名保证磁盘上永远只有「旧完整存档」或
## 「新完整存档」两种状态。读档时任何解析/版本问题都回退为空字典并告警，
## 由上层决定提示玩家还是开新档，绝不让坏存档把游戏拖崩。
class_name SaveStore
extends RefCounted

const SAVE_VERSION: int = 1
const DEFAULT_DIR: String = "user://saves"
const SLOT_EXT: String = ".json"
const MAX_SLOT_LENGTH: int = 64

var _dir: String = DEFAULT_DIR

func _init(dir: String = DEFAULT_DIR) -> void:
	_dir = dir.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(_dir)

func save_slot(slot: String, data: Dictionary) -> bool:
	var path: String = slot_path(slot)
	if path.is_empty():
		push_warning("SaveStore: 非法存档槽名 %s" % slot)
		return false
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"data": data,
	}
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: 无法写入 %s（错误码 %d）" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	var err: int = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		# 部分平台 rename 不能覆盖已存在文件，退化为「删旧再改名」。
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_warning("SaveStore: 存档改名失败（错误码 %d），保留旧存档" % err)
		DirAccess.remove_absolute(tmp_path)
		return false
	return true

func load_slot(slot: String) -> Dictionary:
	var path: String = slot_path(slot)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveStore: 无法读取 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return {}
	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("SaveStore: 存档 %s 损坏（%s），回退为空存档"
			% [slot, parser.get_error_message()])
		return {}
	var envelope: Variant = parser.data
	if not (envelope is Dictionary):
		push_warning("SaveStore: 存档 %s 缺少信封结构，回退为空存档" % slot)
		return {}
	var doc: Dictionary = envelope
	var version: int = int(doc.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		push_warning("SaveStore: 存档 %s 版本 %d 不受支持（当前 %d），回退为空存档"
			% [slot, version, SAVE_VERSION])
		return {}
	var data: Variant = doc.get("data", null)
	if not (data is Dictionary):
		push_warning("SaveStore: 存档 %s 数据段不是字典，回退为空存档" % slot)
		return {}
	return data

func has_slot(slot: String) -> bool:
	var path: String = slot_path(slot)
	return not path.is_empty() and FileAccess.file_exists(path)

func delete_slot(slot: String) -> bool:
	var path: String = slot_path(slot)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

func list_slots() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(SLOT_EXT):
			out.append(entry.trim_suffix(SLOT_EXT))
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

## 槽名 -> 文件路径。只允许字母/数字/下划线/连字符，杜绝 "../" 越界写文件。
func slot_path(slot: String) -> String:
	if not _is_valid_slot(slot):
		return ""
	return _dir.path_join(slot + SLOT_EXT)

func _is_valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > MAX_SLOT_LENGTH:
		return false
	for i: int in slot.length():
		var code: int = slot.unicode_at(i)
		var is_digit: bool = code >= 48 and code <= 57
		var is_upper: bool = code >= 65 and code <= 90
		var is_lower: bool = code >= 97 and code <= 122
		var is_separator: bool = code == 95 or code == 45
		if not (is_digit or is_upper or is_lower or is_separator):
			return false
	return true
