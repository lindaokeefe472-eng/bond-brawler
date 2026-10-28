## 只读 JSON 数据源（生产实现）。
##
## 为什么带缓存：data/ 下的单文件上百 KB，仓库层启动时会连续读取同一批文件，
## 战斗中技能/属性表还会被反复查询；缓存解析结果可以避免重复 IO 和重复解析。
## 解析失败只告警并返回空字典 —— 遵循「数据坏了也要能进游戏」的降级原则，
## 绝不因为一个坏 JSON 让整局崩溃。
class_name JsonDataSource
extends IDataSource

## 数据根目录。仓库层传入相对文件名（"skills.json"），由这里拼成完整路径。
var _root: String = "res://data"

var _text_cache: Dictionary = {}   # 完整路径 -> 原始文本
var _json_cache: Dictionary = {}   # 完整路径 -> 解析结果（Dictionary / Array / ...）

func _init(root: String = "res://data") -> void:
    _root = root.trim_suffix("/")

func exists(path: String) -> bool:
    return FileAccess.file_exists(_resolve(path))

func read_text(path: String) -> String:
    var full: String = _resolve(path)
    if _text_cache.has(full):
        return str(_text_cache[full])
    var file: FileAccess = FileAccess.open(full, FileAccess.READ)
    if file == null:
        push_warning("JsonDataSource: 无法读取 %s（错误码 %d）" % [full, FileAccess.get_open_error()])
        return ""
    var text: String = file.get_as_text()
    file.close()
    _text_cache[full] = text
    return text

func read_json(path: String) -> Variant:
    var full: String = _resolve(path)
    if _json_cache.has(full):
        return _json_cache[full]
    var text: String = read_text(path)
    if text.is_empty():
        return {}
    var parser := JSON.new()
    var err: int = parser.parse(text)
    if err != OK:
        # 把失败结果也缓存下来：坏文件不该每帧重试并刷屏告警。
        push_warning("JsonDataSource: %s 解析失败（第 %d 行：%s），回退为空字典"
            % [full, parser.get_error_line(), parser.get_error_message()])
        _json_cache[full] = {}
        return {}
    _json_cache[full] = parser.data
    return parser.data

## 热重载与测试隔离用：清空后下次读取会重新访问磁盘。
func clear_cache() -> void:
    _text_cache.clear()
    _json_cache.clear()

## 带协议前缀的路径（res:// / user://）或系统绝对路径原样使用，其余拼到根目录。
## 这样仓库层能用短名字，测试也能直接指向临时文件，不必再造一个数据源子类。
func _resolve(path: String) -> String:
    if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
        return path
    return _root.path_join(path)
