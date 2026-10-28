## 打开碰撞形状调试渲染并截图，用来核对判定盒的实际位置。
extends SceneTree

const OUT: String = "res://docs/shapes.png"
var _f: int = 0
var _scene: Node = null
var _session: Variant = null
var _pid: int = 0

func _initialize() -> void:
    _scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(_scene)
    debug_collisions_hint = true

func _process(_delta: float) -> bool:
    _f += 1
    if _session == null:
        _session = _scene.get("_session")
        _pid = int(_scene.get("_player_id"))
        return false
    # 让玩家一直往前压并攻击，敌人会靠上来
    var frame: LocoInputFrame = LocoInputFrame.empty()
    frame.attack = (_f % 15) == 0
    frame.move = Vector2(1.0, 0.0)
    var inputs: Dictionary = {}
    inputs[_pid] = frame
    _session.tick(GameConstants.TICK_DELTA, inputs)
    # 挑一个玩家正在攻击 ACTIVE 的帧截图
    if _f > 200:
        var p: Variant = _session.get_actor(_pid)
        if p.action.current_state() == 6 and p.action.attack_phase() == 1:
            var img: Image = root.get_texture().get_image()
            img.save_png(OUT)
            print("captured at f%d pos=%.2f" % [_f, p.plane_pos.x])
            quit(0)
            return true
    if _f > 600:
        quit(1)
        return true
    return false
