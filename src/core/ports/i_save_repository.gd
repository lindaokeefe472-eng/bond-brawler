## 出站端口：存档读写。
##
## 应用层只关心「存下去 / 读回来」，不关心是 JSON 文件、还是将来换成云存档。
class_name ISaveRepository
extends RefCounted

func save_slot(_slot: String, _data: Dictionary) -> bool:
	push_error("ISaveRepository.save_slot() 未实现")
	return false

func load_slot(_slot: String) -> Dictionary:
	push_error("ISaveRepository.load_slot() 未实现")
	return {}

func has_slot(_slot: String) -> bool:
	return false
