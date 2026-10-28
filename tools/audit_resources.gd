## 全量资源加载审计：把项目里每个 .gd / .tscn / .json / .png 都 load 一遍，
## 报出加载失败的路径。用来抓「只有运行时才会暴露」的坏引用。
extends SceneTree

const EXTS: Array[String] = ["gd", "tscn", "json", "png", "tres"]
const SKIP: Array[String] = ["res://.godot", "res://addons", "res://reports"]

var _fail: Array[String] = []
var _ok: int = 0

func _initialize() -> void:
    _walk("res://")
    print("---- audit ----")
    print("loaded ok: %d, failed: %d" % [_ok, _fail.size()])
    for f: String in _fail:
        print("  FAIL " + f)
    quit(1 if _fail.size() > 0 else 0)

func _walk(path: String) -> void:
    var dir: DirAccess = DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    var name: String = dir.get_next()
    while name != "":
        if name.begins_with("."):
            name = dir.get_next()
            continue
        var full: String = path.path_join(name)
        if dir.current_is_dir():
            var skip: bool = false
            for s: String in SKIP:
                if full.begins_with(s):
                    skip = true
            if not skip:
                _walk(full)
        else:
            var ext: String = name.get_extension()
            if ext in EXTS:
                if ResourceLoader.exists(full):
                    var res: Resource = ResourceLoader.load(full)
                    if res == null:
                        _fail.append(full)
                    else:
                        _ok += 1
                else:
                    _fail.append(full + "  (不存在)")
        name = dir.get_next()
    dir.list_dir_end()
