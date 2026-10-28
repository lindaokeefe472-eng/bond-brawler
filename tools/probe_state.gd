extends SceneTree

const NAMES: Array[String] = ["IDLE", "RUN", "JUMP", "FALL", "LAND", "DASH", "ATTACK", "SKILL", "HURT", "DEAD"]
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
    if p == null:
        return false
    if _f % 20 == 0:
        var st: Variant = p.status
        var tags: Array[String] = []
        for s: StringName in [&"paralyze", &"sleep", &"root", &"slow", &"burn", &"poison", &"weaken", &"wet"]:
            if st.has(s):
                tags.append("%s x%d" % [s, st.stacks(s)])
        print("f%4d state=%-6s can_act=%-5s hp=%3.0f  status=[%s]" % [
            _f, NAMES[p.action.current_state()], str(st.can_act()), p.stats.current_hp, ", ".join(tags)])
    var frame: LocoInputFrame = LocoInputFrame.empty()
    frame.attack = (_f % 15) == 0
    frame.move = Vector2(1.0, 0.0)
    var inputs: Dictionary = {}
    inputs[_pid] = frame
    _session.tick(GameConstants.TICK_DELTA, inputs)
    if _f >= 400:
        quit(0)
        return true
    return false
