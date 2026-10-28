## 效用 AI 的一个打分项：原始分（0..1）经曲线整形后乘以权重。
##
## 为什么把曲线做成枚举而不是让调用方自己写函数：敌人参数来自 JSON，
## 曲线必须能被数据描述；同时 score() 恒落在 0..1，不同权重的意图分才可横向比较。
class_name AiConsideration
extends RefCounted

enum ScoreCurve {
    LINEAR,     # 原始分直接使用
    INVERSE,    # 取反：原始分越高，得分越低（例如「距离越远越不想打」）
    THRESHOLD,  # 过阈值给满分，否则 0（invert 时改为「低于阈值给满分」）
}

const DEFAULT_THRESHOLD: float = 0.5

## 原始打分函数：func(bb: AiBlackboard) -> float，返回值会被夹到 0..1。
var scoring: Callable = Callable()
var weight: float = 1.0
var curve: int = ScoreCurve.LINEAR
## 仅 THRESHOLD 曲线使用。
var threshold: float = DEFAULT_THRESHOLD
## 仅 THRESHOLD 曲线使用：true = 低于阈值得 1 分（血量越低越危险）。
var invert: bool = false

static func make(scoring_fn: Callable, weight_value: float = 1.0,
        curve_kind: int = ScoreCurve.LINEAR, threshold_value: float = DEFAULT_THRESHOLD,
        invert_value: bool = false) -> AiConsideration:
    var consideration := AiConsideration.new()
    consideration.scoring = scoring_fn
    consideration.weight = weight_value
    consideration.curve = curve_kind
    consideration.threshold = threshold_value
    consideration.invert = invert_value
    return consideration

## 曲线整形前的原始分。无效 Callable 视为 0，避免坏配置让整局 AI 崩掉。
func raw_score(bb: AiBlackboard) -> float:
    if not scoring.is_valid():
        return 0.0
    var value: Variant = scoring.call(bb)
    if value == null:
        return 0.0
    return clampf(float(value), 0.0, 1.0)

func score(bb: AiBlackboard) -> float:
    var raw: float = raw_score(bb)
    match curve:
        ScoreCurve.INVERSE:
            return 1.0 - raw
        ScoreCurve.THRESHOLD:
            if invert:
                return 1.0 if raw <= threshold else 0.0
            return 1.0 if raw >= threshold else 0.0
        _:
            return raw

func weighted_score(bb: AiBlackboard) -> float:
    return weight * score(bb)
