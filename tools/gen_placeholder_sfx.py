# -*- coding: utf-8 -*-
"""生成占位音效（自产，无第三方许可问题）。

为什么自己合成而不是下载 CC0 音效包：
  1. 仓库里不引入来路不明的二进制资源，许可链干净；
  2. 脚本可复现，换音色只改参数；
  3. 每个文件只有几 KB，CI 和 clone 都不疼。

正式音效接进来时，把 assets/audio/sfx/*.wav 换掉即可，
data/audio.json 里的映射不用动（除非 cue 名字也变）。

用法: python tools/gen_placeholder_sfx.py
"""
import io
import math
import os
import struct
import wave

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")


def envelope(i, total, attack=0.01, release=0.35):
    """简单的攻击-衰减包络，避免爆音。"""
    t = i / float(total)
    if t < attack:
        return t / attack
    tail = (t - attack) / max(release, 0.0001)
    return max(0.0, 1.0 - tail) if tail < 1.0 else 0.0


def tone(freq_start, freq_end, seconds, shape="sine", gain=0.6, noise=0.0):
    total = int(RATE * seconds)
    out = []
    phase = 0.0
    rng = 12345
    for i in range(total):
        t = i / float(max(total - 1, 1))
        freq = freq_start + (freq_end - freq_start) * t
        phase += 2.0 * math.pi * freq / RATE
        if shape == "square":
            sample = 1.0 if math.sin(phase) >= 0.0 else -1.0
        else:
            sample = math.sin(phase)
        if noise > 0.0:
            rng = (1103515245 * rng + 12345) & 0x7FFFFFFF
            sample += noise * ((rng / float(0x7FFFFFFF)) * 2.0 - 1.0)
        out.append(sample * envelope(i, total) * gain)
    return out


CUES = {
    # 名字 -> 参数。改动这里就等于改音色。
    "hit": dict(freq_start=260, freq_end=180, seconds=0.09, shape="square", gain=0.5, noise=0.25),
    "crit": dict(freq_start=620, freq_end=420, seconds=0.13, shape="square", gain=0.6, noise=0.35),
    "guard": dict(freq_start=340, freq_end=300, seconds=0.10, shape="square", gain=0.45, noise=0.15),
    "dodge": dict(freq_start=900, freq_end=1500, seconds=0.07, shape="sine", gain=0.35, noise=0.05),
    "cast": dict(freq_start=380, freq_end=820, seconds=0.16, shape="sine", gain=0.45, noise=0.05),
    "hurt": dict(freq_start=200, freq_end=140, seconds=0.12, shape="square", gain=0.5, noise=0.2),
    "death": dict(freq_start=180, freq_end=70, seconds=0.38, shape="sine", gain=0.55, noise=0.1),
    "ui_click": dict(freq_start=1000, freq_end=900, seconds=0.04, shape="sine", gain=0.3, noise=0.0),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, params in sorted(CUES.items()):
        samples = tone(**params)
        path = os.path.join(OUT_DIR, "%s.wav" % name)
        with wave.open(path, "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
            f.writeframes(frames)
        print("%-10s %6d 帧  %5.1f KB" % (name, len(samples), os.path.getsize(path) / 1024.0))
    print("输出目录:", OUT_DIR)


if __name__ == "__main__":
    main()
