extends SceneTree

var _f: int = 0
var _scene: Node = null
var _session: Variant = null
var _pid: int = 0

func _initialize() -> void:
    _scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(_scene)

func _process(_delta: float) -> bool:
    _f += 1
    if _session == null:
        _session = _scene.get("_session")
        _pid = int(_scene.get("_player_id"))
        return false
    var p: Variant = _session.get_actor(_pid)
    var views: Dictionary = _scene.get("_views")
    var pv: Node = views.get(_pid, null)
    if pv != null and p != null:
        var hb: Area3D = pv.get_node_or_null("Hitbox") as Area3D
        var phase: int = p.action.attack_phase()
        var n: int = -1
        if hb.monitoring:
            n = hb.get_overlapping_areas().size()
        if _f >= 40 and _f <= 120 and (_f % 2 == 0):
            print("f%3d state=%d phase=%d  _active=%s mon=%s  overlaps=%d" % [
                _f, p.action.current_state(), phase,
                str(hb.get("_active")), str(hb.monitoring), n])
    # 一直按攻击
    var frame: LocoInputFrame = LocoInputFrame.empty()
    frame.attack = (_f % 15) == 0
    frame.move = Vector2(1.0, 0.0)
    var inputs: Dictionary = {}
    inputs[_pid] = frame
    _session.tick(GameConstants.TICK_DELTA, inputs)
    if _f >= 130:
        quit(0)
        return true
    return false
