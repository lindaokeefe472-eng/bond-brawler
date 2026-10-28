# 数据字段说明

> 这些 JSON 来自《宝可梦羁绊之旅》1.0.0 的数值还原，**字段名保持原样**，未做重命名。
> 文件本身不随仓库分发，需要本地自备（见 README「数据与素材」）。
> 新增字段时请同步更新本文件。

## skills.json

以技能 id 为键的字典，124 条。

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 中文名 |
| `type` | string | 属性（18 种，见 type_chart.json） |
| `kind` | string | 大类：melee/bolt/beam/dash/spread/heal/buff/wall/clone/smoke/area/channel |
| `template` | string | 执行模板（56 种，本项目归一到 10 种） |
| `power` | float | 威力 |
| `cost` | float | 能量消耗（上限 180） |
| `cd` | float | 冷却（秒） |
| `range` | float | 射程 |
| `knockback` | float | 击退强度 |
| `wind` | float | 前摇（秒） |
| `commit` | float | 前摇中锁定朝向的时长 |
| `recovery` | float | 后摇（秒，不可取消） |
| `duration` | float | 持续（光束/引导） |
| `clash_class` | string | 对撞等级 A~E |
| `clash_power` | float | 对撞强度 8~84 |
| `status` | string | 附加状态 id，无则空 |
| `dodgeable` | bool | 是否可闪避 |
| `description` | string | 描述 |

模板专用参数（`air_stall`、`volley_count`、`tick`、`homing_cone` 等）原样保留在字典里，
`SkillDef.from_dict` 会把未知字段收进 `extra`。

## species.json

**数组**，221 条。

| 字段 | 说明 |
|---|---|
| `id` / `name` | 标识与中文名 |
| `types` | 属性，多个用 `/` 分隔 |
| `hp` | 基础 HP |
| `battle_hp` | 战斗实际 HP（**不是 hp**，容易踩坑） |
| `attack` / `speed` / `weight` / `size` | 战斗数值 |
| `jumps` / `flight` | 跳跃次数 / 是否飞行 |
| `movement` | 移动型：jump / flight / float / psychic / heavy |
| `moves` | 技能池，`/` 分隔 |
| `initial` / `defaults` | 初始技能 / 默认技能 |
| `unlocks` | 解锁等级映射（JSON 字符串） |

## type_chart.json

```json
{ "names": {"fire": "火", ...}, "chart": {"fire": {"grass": 1.2, ...}} }
```

倍率只有三档：`1.2` 克制 / `0.8` 被抗 / `0.2` 免疫或强抗，其余 `1.0`。
双属性相乘。

## actions.json

动作帧数据与经济：移动、闪避、格挡、普攻、技能施放、切换、资源、伤害公式、状态时长。
**所有时间单位是秒。**

## combat_params.json

战斗系统参数原文件（clash / hit / types / moves / ai）。

## movement.json

种族 id → 移动型。

## 单位与陷阱

- 时间一律秒，不是帧。
- `battle_hp` 才是战斗血量，`hp` 是图鉴值。
- 属性倍率是 1.2 / 0.8 / 0.2，不是 2 / 0.5 / 0。
