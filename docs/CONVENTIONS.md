# 编码规范（CONVENTIONS）

> 目标：多人 / 多 agent 并行开发时，文件不冲突、命名不打架、测试不互相污染。

## 1. 目录所有权

每个上下文独占一个目录，**禁止跨目录改别人的文件**：

| 目录 | 归属上下文 | 允许依赖 |
|---|---|---|
| `src/core/` | 共享内核 | 无 |
| `src/combat/domain/` | 战斗与数值 | core |
| `src/skills/domain/` | 技能与效果 | core, combat |
| `src/talents/domain/` | 天赋树 | core, combat |
| `src/ai/domain/` | 敌人 AI | core, combat, skills |
| `src/locomotion/domain/` | 动作与移动 | core |
| `src/stage/domain/` | 关卡与进度 | core |
| `src/application/` | 用例编排 | 全部领域 |
| `src/infrastructure/` | 基础设施适配器 | core + 全部领域（负责把数据装配成领域对象） |
| `src/presentation/` | 表现层适配器 | core, application + 全部领域（读取值对象渲染） |
| `src/bootstrap/` | 组合根 | 全部 |
| `tests/unit/<context>/` | 对应上下文的测试 | — |

跨上下文需要新能力时：**在自己的目录里定义端口接口**，不要直接改对方实现。

## 2. 命名

| 对象 | 规则 | 示例 |
|---|---|---|
| 文件 | `snake_case.gd` | `damage_calculator.gd` |
| 类（`class_name`） | `PascalCase`，按上下文加前缀避免重名 | `CombatActorStats`、`SkillCaster`、`AiEnemyBrain` |
| 领域事件 | `<上下文>.<过去式>` | `combat.damage_applied` |
| 常量 | `SCREAMING_SNAKE` | `LANE_MAX` |
| 私有成员 | `_` 前缀 | `_cooldown_left` |
| 布尔 | `is_` / `has_` / `can_` | `is_ready()` |
| 时间 | 一律**秒**（float），字段名带单位后缀时用 `_seconds` | `duration` |

`class_name` 全局唯一。新增类前先 `grep -r "class_name 你的类名" src/` 确认不冲突。

## 3. GDScript 硬性约定

1. **缩进 4 空格**，禁止混用 Tab。
2. 所有函数必须标注参数与返回类型；成员变量尽量标注。
3. 领域层禁止 `await`、`yield`、信号（`signal`）。跨对象通信一律走 `DomainEventBus`。
4. 领域层禁止 `Time.get_ticks_msec()` / `randf()` / `randi()` —— 用 `IClock` / `IRng`。
5. 禁止在 `_process` 里做业务逻辑；逻辑只在 `tick(dt)` 里推进。
6. 浮点比较禁止用 `==`。`Vector2` 的分量是 **32 位浮点**，和 `float`（64 位）直接比较会失败，
   用 `assert_almost_eq` / `is_equal_approx`。
7. 字典取值一律带默认值：`d.get("k", 0.0)`，不要假设字段存在（数据来自外部 JSON）。
8. 禁止在领域层 `print`；需要日志时发事件或用 `push_warning`。
9. **订阅要配对退订**。`bus.subscribe(type, func(e): self.xxx(e))` 会形成
   `self -> bus -> lambda -> self` 的引用环，RefCounted 永远不会回收，
   整局对象图一起泄漏。在销毁路径上调 `bus.clear()` 或 `unsubscribe(handle)`，
   或者让 lambda 只捕获 `WeakRef`。测试里放在 `after_each()`。

## 4. 数值与配置

- 全部可调数值放在 `data/` 下的 JSON，或 `src/core/game_constants.gd`（仅限世界常量）。
- 新增数值字段必须同时更新 `docs/data-schema.md` 与对应仓库的默认值。
- 数据加载失败要**降级并告警**，不能让整局崩溃：`push_warning` + 用默认值。

## 5. 测试

- 一个源文件对应一个测试文件：`src/combat/domain/damage_calculator.gd`
  → `tests/unit/combat/test_damage_calculator.gd`。
- 测试方法名 `test_<行为>_<预期>`，例如 `test_dodge_returns_zero_damage`。
- 每个用例至少一条断言（框架会检查）。
- 领域测试不得加载场景、不得依赖 `SceneTree`。
- 改领域逻辑前先跑测试；新增逻辑先写测试（红 → 绿 → 重构）。

## 6. 提交与并行协作

- 一次提交只做一件事，消息格式：`<上下文>: <做了什么>`，例如 `combat: 加入格挡减伤`。
- 并行开发时，若必须改公共文件（`ARCHITECTURE.md`、`GameConstants`），
  先在 PR 描述里声明，合并后其他人 rebase。
