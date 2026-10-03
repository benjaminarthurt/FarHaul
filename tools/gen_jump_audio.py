#!/usr/bin/env python3
"""Synthesises the FTL jump sounds into assets/audio/jump/*.wav (16-bit mono, 44.1 kHz).

No samples, no licences: everything is made from sine sweeps and filtered noise, so the numbers below are
the knobs. Loops are built to be seamless (whole cycles, circular filtering). flight.gd mixes them with
volume and pitch following the jump timeline (see scripts/jump_audio.gd).

    python3 tools/gen_jump_audio.py            # writes the files
    python3 tools/gen_jump_audio.py --report   # also prints peak/RMS per file
"""
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "jump")
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def fade(x, a=0.005, b=0.05):
    n = len(x)
    na, nb = int(SR * a), int(SR * b)
    x = x.copy()
    x[:na] *= np.linspace(0, 1, na)
    x[-nb:] *= np.linspace(1, 0, nb)
    return x


def lowpass(x, hz, order=4):
    return signal.sosfilt(signal.butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=4):
    return signal.sosfilt(signal.butter(order, hz, "high", fs=SR, output="sos"), x)


def circular_noise(seconds, lo, hi):
    """Band-limited noise that loops with no seam: shaped in the frequency domain."""
    n = int(SR * seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    shape = np.where((f >= lo) & (f <= hi), 1.0 / np.sqrt(np.maximum(f, 20.0)), 0.0)   # pink-ish
    return np.fft.irfft(spec * shape, n)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return x


def hum():
    """The drive's idle: a low chord with a slow throb. 4 s, whole cycles of every partial."""
    t = t_axis(4.0)
    x = (np.sin(2 * np.pi * 55 * t) + 0.7 * np.sin(2 * np.pi * 82.5 * t + 0.6) + 0.5 * np.sin(2 * np.pi * 110 * t + 1.1)
         + 0.25 * np.sin(2 * np.pi * 165 * t + 2.0))
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t)          # throb, two beats in the loop
    n = circular_noise(4.0, 30, 400)
    x += 0.5 * n / np.max(np.abs(n))
    return norm(x, 0.8)


def whine():
    """The rising tone: a bright triangle-ish voice with a shimmer. Pitch-shifted by the game."""
    t = t_axis(2.0)
    x = np.sin(2 * np.pi * 440 * t) + 0.5 * np.sin(2 * np.pi * 880 * t + 0.3) + 0.25 * np.sin(2 * np.pi * 1320 * t + 1.2)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 6 * t)               # 12 shimmers in the loop
    return norm(x, 0.6)


def rush():
    """The sound of the stars going by: wind-like noise. 3 s, seamless."""
    x = circular_noise(3.0, 80, 7000)
    x = x / np.max(np.abs(x))
    return norm(x, 0.8)


def boom():
    """The flash: a sub-bass thump that falls away, a wide noise burst and a bright crack. 3.5 s."""
    t = t_axis(3.5)
    f = 28 + 90 * np.exp(-t * 5.0)
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t * 1.3)
    burst = lowpass(rng.standard_normal(len(t)), 1800) * np.exp(-t * 3.0)
    crack = highpass(rng.standard_normal(len(t)), 3000) * np.exp(-t * 60.0)
    tail = lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t * 1.6) * 0.5
    x = 1.0 * body + 0.7 * burst + 0.5 * crack + tail
    return fade(norm(x, 0.95), 0.001, 0.2)


def engage():
    """Switching the drive on: a click and a short rising chirp. 0.7 s."""
    t = t_axis(0.7)
    chirp = np.sin(2 * np.pi * np.cumsum(180 + 900 * (t / 0.7) ** 2) / SR) * np.minimum(t * 20, 1) * np.exp(-t * 2.5)
    click = highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t * 90.0)
    return fade(norm(chirp * 0.7 + click * 0.8, 0.8), 0.001, 0.15)


def settle():
    """Dropping out of the jump: a soft low thud and a fading ring. 1.4 s."""
    t = t_axis(1.4)
    thud = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 4) + 40) / SR) * np.exp(-t * 5.0)
    ring = np.sin(2 * np.pi * 330 * t) * np.exp(-t * 6.0) * 0.25
    return fade(norm(thud + ring, 0.7), 0.002, 0.2)


FILES = {"hum.wav": hum, "whine.wav": whine, "rush.wav": rush, "boom.wav": boom, "engage.wav": engage, "settle.wav": settle}

if __name__ == "__main__":
    for name, fn in FILES.items():
        x = write(name, fn())
        if "--report" in sys.argv:
            print("%-12s %5.2fs  peak %.2f  rms %.3f" % (name, len(x) / SR, np.max(np.abs(x)), np.sqrt(np.mean(x ** 2))))
