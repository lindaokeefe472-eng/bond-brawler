## 出站端口：只读数据源。仓库层（Repository）通过它读取 JSON/CSV，
## 从而让仓库本身可以在纯 GDScript 测试里用内存实现替换。
class_name IDataSource
extends RefCounted

func exists(_path: String) -> bool:
	push_error("IDataSource.exists() 未实现")
	return false

func read_text(_path: String) -> String:
	push_error("IDataSource.read_text() 未实现")
	return ""

## 返回解析后的 Variant（Dictionary / Array）。
func read_json(_path: String) -> Variant:
	push_error("IDataSource.read_json() 未实现")
	return null
