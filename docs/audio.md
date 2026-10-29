# 音效

## 现在的音效从哪来

`assets/audio/sfx/*.wav` 全部由 `tools/gen_placeholder_sfx.py` **程序合成**，
不是下载来的第三方素材 —— 仓库里没有许可链不清的二进制资源。

- 授权：自制，等同 CC0 / 公有领域，可随意替换。
- 复现：`python tools/gen_placeholder_sfx.py`（改动脚本里的参数就等于换音色）。
- 体积：8 个文件合计约 47 KB。

正式音效接进来时，直接替换同名 wav 即可，`assets/audio/cues.json` 不用动。

## 数据

`assets/audio/cues.json` 是 cue 名 → 资源 + 播放参数的映射：

```json
{
  "buses": ["master", "sfx", "bgm", "ui"],
  "cues": {
    "hit": {
      "file": "res://assets/audio/sfx/hit.wav",
      "bus": "sfx",
      "volume_db": -6.0,
      "pitch_jitter": 0.08,
      "debounce": 0.04,
      "voices": 4
    }
  }
}
```

| 字段 | 含义 |
|---|---|
| `file` | 资源路径，必须存在 |
| `bus` | 必须出现在 `buses` 里 |
| `volume_db` | 相对总线音量的增益 |
| `pitch_jitter` | 每次播放的音高随机幅度（±比例），连打时不会像机关枪 |
| `debounce` | 同一 cue 的最短间隔（秒），0 = 不限 |
| `voices` | 同一 cue 的并发上限（当前由全局池统一限流） |

## cue 清单

`GameConstants.SFX_CUES` 是唯一权威列表，`assets/audio/cues.json` 必须覆盖它的每一项。

| cue | 触发点 |
|---|---|
| `hit` | 普攻/技能命中 |
| `crit` | 暴击命中 |
| `guard` | 格挡成功 |
| `dodge` | 闪避成功 |
| `cast` | 技能出手（`skill.activated`） |
| `hurt` | 玩家挨打 |
| `death` | 角色死亡 |
| `ui_click` | 标题界面开始游戏 |

## 分层

```
IAudio（端口）            ← 领域/表现只认这个
  ├─ AudioDirector        ← 真实适配器：总线、播放器池、防叠音
  └─ 空实现（计数留在 FeedbackDirector 里，headless 测试用）
```

`AudioLibrary` 只读数据，不碰音频引擎，所以「cue 有没有映射、文件在不在」
可以用纯数据测试钉住（`tests/unit/infrastructure/test_audio_library.gd`）。

## 已知缺口

- 没有 BGM（`bgm` 总线已建，暂无曲目）。
- 没有按位置声像（`AudioStreamPlayer` 不带 pan；要做得换 `AudioStreamPlayer2D`）。
