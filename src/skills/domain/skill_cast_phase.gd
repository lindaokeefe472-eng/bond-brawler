## 施法相位枚举。单独成类是为了让 caster、表现层、AI 共享同一套相位编号，
## 避免各自定义魔数导致「IDLE 是 0 还是 1」这种跨模块误解。
class_name SkillCastPhase
extends RefCounted

enum { IDLE, WINDUP, ACTIVE, RECOVERY }
