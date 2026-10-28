## 动作状态枚举与名字表。
## 事件载荷里传名字而不是数字：日志可读，且状态编号调整不会破坏回放数据。
class_name LocoActionState
extends RefCounted

const IDLE: int = 0
const RUN: int = 1
const JUMP: int = 2
const FALL: int = 3
const LAND: int = 4
const DASH: int = 5
const ATTACK: int = 6
const SKILL: int = 7
const HURT: int = 8
const DEAD: int = 9

## 状态 -> 事件名。表现层按名字映射动画，领域层内部仍用 int 比较。
const NAMES: Dictionary = {
    IDLE: &"idle",
    RUN: &"run",
    JUMP: &"jump",
    FALL: &"fall",
    LAND: &"land",
    DASH: &"dash",
    ATTACK: &"attack",
    SKILL: &"skill",
    HURT: &"hurt",
    DEAD: &"dead",
}

static func name_of(state: int) -> StringName:
    var value: StringName = NAMES.get(state, &"unknown")
    return value

static func from_name(name: StringName) -> int:
    for state: int in NAMES.keys():
        if NAMES[state] == name:
            return state
    return -1

static func is_valid(state: int) -> bool:
    return NAMES.has(state)
