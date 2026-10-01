#!/usr/bin/env python3
"""Generates the Far Haul placeholder brand assets: logo, icon, boot splash and intro video.

Everything here is original, drawn from code (no third-party fonts or art). The video is a
PLACEHOLDER: replace assets/video/intro.ogv with the real thing whenever it exists.

Needs: Pillow, numpy, ffmpeg (with libtheora + libvorbis).
Run from the project root:  python3 tools/make_brand_assets.py [--no-video]
"""
import math
import os
import random
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Brand palette, mirrored in scripts/brand.gd
STEEL_DARK = (13, 16, 21)
STEEL = (28, 33, 41)
OFFWHITE = (230, 226, 214)
AMBER = (242, 167, 27)
MUTED = (140, 146, 156)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "assets", "brand")
VIDEO = os.path.join(ROOT, "assets", "video")

# Stencil block letters on a 5 x 7 unit grid. Each is a list of rectangles (x0, y0, x1, y1).
# The small gaps between rectangles are the stencil bridges.
GLYPHS = {
    "F": [(0, 1.7, 1.3, 7), (0, 0, 5, 1.3), (1.7, 3.2, 4.2, 4.5)],
    "A": [(0, 1.7, 1.3, 7), (3.7, 1.7, 5, 7), (0.9, 0, 4.1, 1.3), (1.7, 3.6, 3.3, 4.9)],
    "R": [(0, 1.7, 1.3, 7), (0, 0, 4.0, 1.3), (3.7, 1.7, 5, 3.4), (1.7, 3.4, 3.7, 4.6), (3.4, 5.0, 5, 7)],
    "H": [(0, 0, 1.3, 7), (3.7, 0, 5, 7), (1.7, 3.0, 3.3, 4.2)],
    "U": [(0, 0, 1.3, 5.3), (3.7, 0, 5, 5.3), (0, 5.7, 5, 7)],
    "L": [(0, 0, 1.3, 5.3), (0, 5.7, 5, 7)],
}


def wordmark(unit: int, color=OFFWHITE, tracking=1.6, word_gap=3.2) -> Image.Image:
    """Return an RGBA image of FAR HAUL. `unit` is pixels per grid unit."""
    words = ["FAR", "HAUL"]
    total = 0.0
    for wi, w in enumerate(words):
        total += len(w) * 5 + (len(w) - 1) * tracking
        if wi < len(words) - 1:
            total += word_gap
    img = Image.new("RGBA", (int(total * unit) + 2, 7 * unit + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = 0.0
    for wi, w in enumerate(words):
        for ch in w:
            for (x0, y0, x1, y1) in GLYPHS[ch]:
                d.rectangle([(x + x0) * unit, y0 * unit, (x + x1) * unit - 1, y1 * unit - 1], fill=color + (255,))
            x += 5 + tracking
        x += word_gap - tracking
    return img


def hazard_bar(w: int, h: int, stripe=28, c1=AMBER, c2=STEEL_DARK) -> Image.Image:
    img = Image.new("RGBA", (w, h), c2 + (255,))
    d = ImageDraw.Draw(img)
    for i in range(-h, w + h, stripe * 2):
        d.polygon([(i, h), (i + stripe, h), (i + stripe + h, 0), (i + h, 0)], fill=c1 + (255,))
    return img


def make_logo() -> Image.Image:
    unit = 40
    wm = wordmark(unit)
    pad = 60
    bar_h = 22
    w = wm.width + pad * 2
    h = wm.height + bar_h * 2 + 80 + pad
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.alpha_composite(hazard_bar(wm.width, bar_h), (pad, pad // 2))
    img.alpha_composite(wm, (pad, pad // 2 + bar_h + 40))
    img.alpha_composite(hazard_bar(wm.width, bar_h), (pad, pad // 2 + bar_h + 40 + wm.height + 40))
    return img


def make_icon(size=256) -> Image.Image:
    """A freight container end-on with a stencilled F."""
    s = 4
    S = size * s
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = int(S * 0.06)
    d.rounded_rectangle([m, m, S - m, S - m], radius=int(S * 0.08), fill=STEEL_DARK + (255,), outline=AMBER + (255,), width=int(S * 0.035))
    # corrugation ribs
    for i in range(1, 8):
        x = m + (S - 2 * m) * i / 8
        d.line([(x, m + S * 0.05), (x, S - m - S * 0.05)], fill=STEEL + (255,), width=int(S * 0.012))
    # stencilled F
    unit = int(S * 0.095)
    ox = int(S * 0.5 - 2.5 * unit)
    oy = int(S * 0.5 - 3.5 * unit)
    for (x0, y0, x1, y1) in GLYPHS["F"]:
        d.rectangle([ox + x0 * unit, oy + y0 * unit, ox + x1 * unit, oy + y1 * unit], fill=OFFWHITE + (255,))
    # corner castings
    c = int(S * 0.06)
    for (cx, cy) in [(m, m), (S - m - c, m), (m, S - m - c), (S - m - c, S - m - c)]:
        d.rectangle([cx, cy, cx + c, cy + c], fill=AMBER + (255,))
    return img.resize((size, size), Image.LANCZOS)


def starfield(w, h, seed=7, n=420) -> Image.Image:
    rnd = random.Random(seed)
    img = Image.new("RGB", (w, h), STEEL_DARK)
    px = img.load()
    for _ in range(n):
        x, y = rnd.randrange(w), rnd.randrange(h)
        v = rnd.randint(70, 255)
        tint = rnd.choice([(1, 0.92, 0.8), (0.85, 0.92, 1), (1, 1, 1)])
        px[x, y] = tuple(int(v * t) for t in tint)
    return img


def label_text(d, xy, text, fill, unit=3, tracking=1):
    """Tiny pixel block text for brand details (container codes). Uses PIL's default font."""
    d.text(xy, text, fill=fill)


def make_splash(w=1280, h=720) -> Image.Image:
    img = starfield(w, h, seed=11).convert("RGBA")
    # soft vignette
    v = Image.new("L", (w, h), 0)
    ImageDraw.Draw(v).ellipse([-w * 0.2, -h * 0.4, w * 1.2, h * 1.4], fill=255)
    v = v.filter(ImageFilter.GaussianBlur(160))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    img = Image.composite(img, dark, v)
    logo = make_logo()
    scale = 0.7 * w / logo.width
    logo = logo.resize((int(logo.width * scale), int(logo.height * scale)), Image.LANCZOS)
    img.alpha_composite(logo, ((w - logo.width) // 2, (h - logo.height) // 2 - 30))
    d = ImageDraw.Draw(img)
    tag = "BUILD YOUR SHIP.  HAUL THE FREIGHT.  PUSH THE FRONTIER."
    tile = Image.new("RGBA", (len(tag) * 7 + 8, 16), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((2, 2), tag, fill=MUTED + (255,))
    tile = tile.resize((tile.width * 2, tile.height * 2), Image.NEAREST)
    img.alpha_composite(tile, ((w - tile.width) // 2, (h + logo.height) // 2 + 10))
    return img.convert("RGB")


# --- Intro video (placeholder) -------------------------------------------------------------------

W, H, FPS = 1280, 720, 24
DUR = 14.0


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def fade_window(t, a, b, fi=0.5, fo=0.5):
    """0..1 opacity for a caption visible from a to b seconds."""
    return min(ease((t - a) / fi), ease((b - t) / fo))


def draw_ship(d, cx, cy, s, flame):
    """Side view of the starter 'space box truck': cab, hab, cargo box, engineering, engine."""
    def box(x0, y0, x1, y1, fill, outline=(8, 10, 13)):
        d.rectangle([cx + x0 * s, cy + y0 * s, cx + x1 * s, cy + y1 * s], fill=fill, outline=outline, width=2)
    # tanks and radiators underneath/behind
    box(-1.2, 0.6, 1.4, 1.1, (150, 150, 140))
    box(1.6, 0.55, 3.2, 1.1, (150, 150, 140))
    # main hull
    box(-3.4, -0.5, -2.4, 0.6, (60, 100, 150))       # cockpit
    box(-2.4, -0.4, -1.4, 0.5, (95, 100, 110))       # habitation
    box(-1.4, -0.7, 2.4, 0.6, (96, 108, 90))         # cargo
    for i in range(1, 8):                            # container ribs
        x = -1.4 + 3.8 * i / 8
        d.line([cx + x * s, cy - 0.65 * s, cx + x * s, cy + 0.55 * s], fill=(70, 80, 66), width=2)
    box(2.4, -0.45, 3.4, 0.5, (140, 70, 62))         # engineering
    box(3.4, -0.25, 3.9, 0.3, (200, 115, 50))        # engine
    # hazard stripe on the cargo box and canopy
    d.rectangle([cx - 3.35 * s, cy - 0.35 * s, cx - 2.5 * s, cy - 0.1 * s], fill=(150, 205, 235))
    d.rectangle([cx - 1.4 * s, cy + 0.42 * s, cx + 2.4 * s, cy + 0.5 * s], fill=AMBER)
    # engine flame
    if flame > 0:
        L = (1.2 + 0.25 * math.sin(flame * 40)) * s * flame
        d.polygon([(cx + 3.9 * s, cy - 0.2 * s), (cx + 3.9 * s + L, cy + 0.02 * s), (cx + 3.9 * s, cy + 0.25 * s)],
                  fill=(255, 190, 90))
        d.polygon([(cx + 3.9 * s, cy - 0.1 * s), (cx + 3.9 * s + L * 0.55, cy + 0.02 * s), (cx + 3.9 * s, cy + 0.15 * s)],
                  fill=(255, 245, 210))


CAPTIONS = [
    (0.8, 3.6, "HUMANITY IS REACHING FOR THE STARS."),
    (3.8, 6.6, "SOMEONE HAS TO CARRY THE FREIGHT."),
    (6.8, 8.8, "YOU ARE A SHIP OWNER."),
]


def render_frame(t, stars, big_logo, caption_font_scale=2):
    img = stars.copy().convert("RGBA")
    # slow parallax drift
    shift = int(t * 14)
    img = Image.fromarray(np.roll(np.array(img), -shift, axis=1))
    d = ImageDraw.Draw(img)

    # ship crossing, left to right then fading as the logo arrives
    ship_vis = 1.0 - ease((t - 8.4) / 0.8)
    if ship_vis > 0:
        sx = (W + 500) - (W + 650) * (t / 9.0)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        draw_ship(ld, sx, H * 0.50 + 6 * math.sin(t * 1.3), 70, flame=ease(t / 1.2))
        if ship_vis < 1:
            layer.putalpha(layer.getchannel("A").point(lambda a: int(a * ship_vis)))
        img.alpha_composite(layer)

    # captions (tiny default font scaled up)
    for (a, b, text) in CAPTIONS:
        o = fade_window(t, a, b)
        if o > 0:
            tile = Image.new("RGBA", (int(len(text) * 7) + 8, 16), (0, 0, 0, 0))
            ImageDraw.Draw(tile).text((2, 2), text, fill=OFFWHITE + (int(255 * o),))
            tile = tile.resize((tile.width * 3, tile.height * 3), Image.NEAREST)
            img.alpha_composite(tile, ((W - tile.width) // 2, int(H * 0.78)))

    # logo reveal
    lo = ease((t - 9.0) / 1.2) * (1 - ease((t - DUR + 0.6) / 0.6))
    if lo > 0:
        logo = big_logo.copy()
        logo.putalpha(logo.getchannel("A").point(lambda a: int(a * lo)))
        img.alpha_composite(logo, ((W - logo.width) // 2, int(H * 0.36) - logo.height // 2))
        tag = "BUILD YOUR SHIP.  HAUL THE FREIGHT.  PUSH THE FRONTIER."
        to = ease((t - 10.6) / 0.8) * (1 - ease((t - DUR + 0.6) / 0.6))
        tile = Image.new("RGBA", (len(tag) * 7 + 8, 16), (0, 0, 0, 0))
        ImageDraw.Draw(tile).text((2, 2), tag, fill=MUTED + (int(255 * to),))
        tile = tile.resize((tile.width * 2, tile.height * 2), Image.NEAREST)
        img.alpha_composite(tile, ((W - tile.width) // 2, int(H * 0.36) + logo.height // 2 + 30))

    # placeholder watermark
    wm = Image.new("RGBA", (260, 16), (0, 0, 0, 0))
    ImageDraw.Draw(wm).text((2, 2), "PLACEHOLDER INTRO  -  FHCU 000001-0", fill=MUTED + (160,))
    img.alpha_composite(wm, (W - 270, H - 24))

    # fade from/to black
    black = ease(1 - t / 0.6) if t < 0.6 else (ease((t - (DUR - 0.5)) / 0.5) if t > DUR - 0.5 else 0)
    if black > 0:
        img = Image.blend(img, Image.new("RGBA", (W, H), (0, 0, 0, 255)), black)
    return img.convert("RGB")


def make_audio(path, sr=44100):
    """Low machinery drone, a slow swell, relay clicks and a soft engine rumble. Fully synthesised."""
    n = int(DUR * sr)
    t = np.arange(n) / sr
    rnd = np.random.RandomState(3)
    drone = 0.22 * np.sin(2 * np.pi * 55 * t) + 0.12 * np.sin(2 * np.pi * 82.5 * t + 1.3) + 0.06 * np.sin(2 * np.pi * 110 * t)
    noise = rnd.randn(n)
    # brown-ish rumble
    rumble = np.cumsum(noise)
    rumble -= np.convolve(rumble, np.ones(2000) / 2000, mode="same")
    rumble = rumble / (np.abs(rumble).max() + 1e-9) * 0.35
    swell = np.clip((t - 0.2) / 2.0, 0, 1) * np.clip((DUR - t) / 1.2, 0, 1)
    sig = (drone + rumble) * swell
    # rising chord for the logo reveal
    rev = np.clip((t - 9.0) / 1.2, 0, 1) * np.clip((DUR - t) / 2.0, 0, 1)
    for f, g in [(110, 0.10), (165, 0.07), (220, 0.06), (330, 0.03)]:
        sig += g * np.sin(2 * np.pi * f * t) * rev
    # relay clicks
    for ct in [1.1, 2.0, 4.2, 5.6, 7.0, 9.0]:
        i = int(ct * sr)
        k = np.arange(int(0.03 * sr))
        sig[i:i + len(k)] += 0.35 * np.exp(-k / 120.0) * rnd.randn(len(k))
    sig = sig / (np.abs(sig).max() + 1e-9) * 0.8
    pcm = (sig * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def make_video():
    os.makedirs(VIDEO, exist_ok=True)
    tmp = os.path.join(VIDEO, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    stars = starfield(W, H, seed=21, n=700)
    logo = make_logo()
    scale = 0.5 * W / logo.width
    big_logo = logo.resize((int(logo.width * scale), int(logo.height * scale)), Image.LANCZOS)
    frames = int(DUR * FPS)
    for i in range(frames):
        render_frame(i / FPS, stars, big_logo).save(os.path.join(tmp, "f%04d.png" % i))
    wav = os.path.join(tmp, "a.wav")
    make_audio(wav)
    out = os.path.join(VIDEO, "intro.ogv")
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"),
        "-i", wav, "-c:v", "libtheora", "-q:v", "6", "-c:a", "libvorbis", "-q:a", "3", "-shortest", out,
    ], check=True)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    print("wrote", out, os.path.getsize(out) // 1024, "KB")


def main():
    os.makedirs(BRAND, exist_ok=True)
    make_logo().save(os.path.join(BRAND, "logo.png"))
    wordmark(48).save(os.path.join(BRAND, "wordmark.png"))
    make_icon(256).save(os.path.join(BRAND, "icon.png"))
    make_splash().save(os.path.join(BRAND, "boot_splash.png"))
    print("brand images written to", BRAND)
    if "--no-video" not in sys.argv:
        make_video()


if __name__ == "__main__":
    main()
