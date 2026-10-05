#!/usr/bin/env python3
"""Synthesises the everyday sounds into assets/audio/world/*.wav (16-bit mono, 44.1 kHz).

Like the jump sounds (tools/gen_jump_audio.py), everything is made from tones and filtered noise, so
there are no samples or licences, and any file can be swapped for a recording later. Loops are seamless.
scripts/world_audio.gd plays them; levels live in data/runtime/world_audio.json.

    python3 tools/gen_world_audio.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "world")
rng = np.random.default_rng(21)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def fade(x, a=0.003, b=0.03):
    x = x.copy()
    na, nb = max(1, int(SR * a)), max(1, int(SR * b))
    x[:na] *= np.linspace(0, 1, na)
    x[-nb:] *= np.linspace(1, 0, nb)
    return x


def band(x, lo, hi, order=3):
    return signal.sosfilt(signal.butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def lowpass(x, hz, order=4):
    return signal.sosfilt(signal.butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=4):
    return signal.sosfilt(signal.butter(order, hz, "high", fs=SR, output="sos"), x)


def loop_noise(seconds, lo, hi, tilt=0.5):
    """Band-limited noise that loops with no seam (shaped in the frequency domain)."""
    n = int(SR * seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    shape = np.where((f >= lo) & (f <= hi), 1.0 / np.maximum(f, 20.0) ** tilt, 0.0)
    x = np.fft.irfft(spec * shape, n)
    return x / (np.max(np.abs(x)) + 1e-9)


def tone(t, hz, phase=0.0):
    return np.sin(2 * np.pi * hz * t + phase)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- Loops (every partial a whole number of cycles in the loop) ---------------------------------------

def port_hum():
    """A station concourse: air handlers, a mains hum and a far-off murmur of people. 8 s."""
    t = t_axis(8.0)
    mains = 0.35 * tone(t, 60) + 0.2 * tone(t, 120, 0.4) + 0.08 * tone(t, 180, 1.0)
    air = loop_noise(8.0, 60, 2500, 0.8) * 0.9
    murmur = loop_noise(8.0, 250, 1400, 0.3)
    murmur *= 0.5 + 0.5 * np.abs(tone(t, 0.75) * tone(t, 1.25, 0.7))   # voices coming and going
    return norm(mains + air + 0.35 * murmur, 0.7)


def hab_hum():
    """A moon base hab: pumps, a lower hum and the tick of the air recycler. 8 s."""
    t = t_axis(8.0)
    pump = (0.4 * tone(t, 50) + 0.15 * tone(t, 100, 0.3)) * (0.8 + 0.2 * tone(t, 1.0))
    air = loop_noise(8.0, 40, 1500, 0.9)
    ticks = np.zeros_like(t)
    for k in range(16):
        i = int(k * 0.5 * SR)
        n = int(0.02 * SR)
        ticks[i:i + n] += np.exp(-np.arange(n) / (0.003 * SR)) * 0.3
    return norm(pump + 0.8 * air + highpass(ticks, 1500), 0.65)


def ship_hum():
    """Aboard: the reactor's drone and the ventilation. 6 s."""
    t = t_axis(6.0)
    drone = 0.5 * tone(t, 45) + 0.3 * tone(t, 67.5, 0.5) + 0.12 * tone(t, 90, 1.3)
    drone *= 0.85 + 0.15 * tone(t, 1 / 3)
    return norm(drone + 0.7 * loop_noise(6.0, 50, 1800, 0.9), 0.65)


def engine():
    """The main engine through the hull: a deep roar. 3 s."""
    t = t_axis(3.0)
    roar = loop_noise(3.0, 25, 900, 0.7)
    rumble = 0.4 * tone(t, 32) * (0.8 + 0.2 * tone(t, 4))
    return norm(roar + rumble, 0.85)


def lift():
    """Lift jets: a hissing, crackling blast. 3 s."""
    hiss = loop_noise(3.0, 300, 9000, 0.2)
    body = loop_noise(3.0, 40, 600, 0.6)
    return norm(0.7 * hiss + body, 0.85)


def breath():
    """Breathing in a suit: in, a pause, out, a pause. 4 s."""
    t = t_axis(4.0)
    air = loop_noise(4.0, 200, 3500, 0.4)
    env = np.zeros_like(t)
    env += np.clip(np.sin(np.pi * np.clip((t - 0.1) / 1.2, 0, 1)), 0, 1) ** 1.5           # in
    env += 0.8 * np.clip(np.sin(np.pi * np.clip((t - 1.9) / 1.5, 0, 1)), 0, 1) ** 1.5     # out
    return norm(band(air, 300, 2500, 2) * env, 0.6)


# --- One-shots ---------------------------------------------------------------------------------------

def step_metal(k):
    """A boot on deck plating: a dull knock with a short metallic ring."""
    t = t_axis(0.25)
    knock = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t * 45)
    ring = (tone(t, 380 + 60 * k) + 0.5 * tone(t, 910 + 90 * k)) * np.exp(-t * 30) * 0.25
    return fade(norm(knock + ring, 0.7), 0.001, 0.05)


def step_dust(k):
    """A boot in regolith: a soft crunch."""
    t = t_axis(0.3)
    crunch = band(rng.standard_normal(len(t)), 500 + 150 * k, 4000, 2) * np.exp(-t * 18) * (0.6 + 0.4 * rng.random(len(t)))
    thud = lowpass(rng.standard_normal(len(t)), 250) * np.exp(-t * 30)
    return fade(norm(crunch + thud, 0.6), 0.002, 0.08)


def low_air():
    """Two short warning beeps."""
    t = t_axis(0.6)
    x = np.zeros_like(t)
    for start in (0.0, 0.25):
        m = (t >= start) & (t < start + 0.14)
        x[m] = tone(t[m], 1320) * 0.8 + tone(t[m], 2640) * 0.2
    return fade(norm(lowpass(x, 6000), 0.55), 0.001, 0.02)


def ui():
    """A soft desk click."""
    t = t_axis(0.12)
    x = tone(t, 1800) * np.exp(-t * 60) + highpass(rng.standard_normal(len(t)), 3000) * np.exp(-t * 200) * 0.4
    return fade(norm(x, 0.45), 0.0005, 0.02)


def done():
    """Something done: a rising two-note chime."""
    t = t_axis(0.7)
    a = tone(t, 660) * np.exp(-t * 6) * (t < 0.7)
    b = tone(t - 0.12, 990) * np.exp(-np.maximum(t - 0.12, 0) * 5) * (t >= 0.12)
    return fade(norm(a + b, 0.5), 0.001, 0.1)


def thud():
    """A crate set down: a heavy, short thump."""
    t = t_axis(0.4)
    body = tone(t, 70 + 50 * np.exp(-t * 20)) * np.exp(-t * 14)
    dust = lowpass(rng.standard_normal(len(t)), 1200) * np.exp(-t * 25) * 0.4
    return fade(norm(body + dust, 0.75), 0.001, 0.08)


def main():
    write("port_hum.wav", port_hum())
    write("hab_hum.wav", hab_hum())
    write("ship_hum.wav", ship_hum())
    write("engine.wav", engine())
    write("lift.wav", lift())
    write("breath.wav", breath())
    for k in range(3):
        write("step_metal_%d.wav" % k, step_metal(k))
        write("step_dust_%d.wav" % k, step_dust(k))
    write("low_air.wav", low_air())
    write("ui.wav", ui())
    write("done.wav", done())
    write("thud.wav", thud())


if __name__ == "__main__":
    main()
