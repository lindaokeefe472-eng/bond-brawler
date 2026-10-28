## 截一张运行画面：godot --path . --script res://tools/capture.gd
## 等场景跑够帧数（角色已生成、相机已就位）后抓 viewport 存 PNG，然后退出。
extends SceneTree

const WAIT_FRAMES: int = 90
const OUT_PATH: String = "res://docs/screenshot.png"

var _frames: int = 0

func _initialize() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
    if packed == null:
        push_error("capture: 无法加载 main.tscn")
        quit(1)
        return
    root.add_child(packed.instantiate())

func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < WAIT_FRAMES:
        return false
    var texture: ViewportTexture = root.get_texture()
    if texture == null:
        push_error("capture: 没有 viewport 纹理")
        quit(1)
        return true
    var image: Image = texture.get_image()
    var err: int = image.save_png(OUT_PATH)
    print("capture: %dx%d -> %s (err=%d)" % [image.get_width(), image.get_height(), OUT_PATH, err])
    quit(0)
    return true
