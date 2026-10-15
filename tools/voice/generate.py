#!/usr/bin/env python3
"""Record Far Haul's radio and aboard voices with Chatterbox, as OGG files the game plays.

Run from the repo root, in the Chatterbox environment (it already has torch, torchaudio and librosa):

  python tools/voice/generate.py cast --refs D:/TTS/voices/refs   pick a cast from the reference voices
  python tools/voice/generate.py plan                             how many clips, and roughly how long
  python tools/voice/generate.py preview                          one line per speaker, to check the cast
  python tools/voice/generate.py run                              record everything (resumable)
  python tools/voice/generate.py review                           a page to listen and mark bad takes
  python tools/voice/generate.py run                              again: re-records what you marked
  python tools/voice/generate.py index                            rebuild the game's index only

Reads
  tools/voice/lines.json     every spoken line (python tools/voice/build_lines.py makes it)
  tools/voice/voices.json    the cast: who says what, with which reference voice and settings
Writes
  assets/audio/voice/<speaker>/<line>__<take>.ogg   mono, 22050 Hz, Vorbis
  assets/audio/voice/index.json                      what the game reads (scripts/comms/voice_bank.gd)
  tools/voice/manifest.jsonl                         one row per recorded clip: seed, length, checks
  tools/voice/review.html, tools/voice/preview/      for listening

Lines are recorded clean. The game adds the radio sound (band-pass, hiss, squelch) itself.

Options for `run`:
  --role control,ship   only these roles        --speaker control_kesh_1   only these speakers
  --key comms:greet     only these line keys    --limit 20                 stop after this many new clips
  --asr                 check each take with Whisper (faster-whisper or openai-whisper, if installed)
                        and re-roll ones that don't say the line
  --tries 3             takes to try per clip before keeping the best one
  --device cuda|cpu     default: cuda if available
  --fake                no Chatterbox: synthetic noise of the right length, for testing the pipeline
"""
import argparse
import csv
import glob
import json
import math
import os
import random
import re
import shutil
import sys
import time
import zlib

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "voice")
OUT = os.path.join(ROOT, "assets", "audio", "voice")
LINES = os.path.join(HERE, "lines.json")
CAST = os.path.join(HERE, "voices.json")
MANIFEST = os.path.join(HERE, "manifest.jsonl")
REJECTS = os.path.join(HERE, "rejects.txt")
REJECTED = os.path.join(HERE, "_rejected")
GAME_SR = 22050

# How each species sounds, on top of the reference voice. The babble voices in comms.json run the same
# way: kesh low and slow, ilyan high and quick, vey a little high, orun a little low.
SPECIES = {
    "human": {"pitch": 0.0, "tempo": 1.0},
    "kesh": {"pitch": -3.5, "tempo": 0.92},
    "ilyan": {"pitch": 3.0, "tempo": 1.1},
    "vey": {"pitch": 1.5, "tempo": 1.04},
    "orun": {"pitch": -2.0, "tempo": 0.95},
}

# How each role speaks. exaggeration: Chatterbox's emotion (0.25 flat to 1.0 wild). cfg_weight: lower is
# looser and quicker. Override per speaker, or per line key in voices.json "lines".
ROLES = {
    "control": {"exaggeration": 0.4, "cfg_weight": 0.5},
    "pad": {"exaggeration": 0.45, "cfg_weight": 0.5},
    "camp": {"exaggeration": 0.6, "cfg_weight": 0.4},
    "ship": {"exaggeration": 0.5, "cfg_weight": 0.5},
    "patrol": {"exaggeration": 0.35, "cfg_weight": 0.5},
    "tug": {"exaggeration": 0.45, "cfg_weight": 0.5},
    "distress": {"exaggeration": 0.7, "cfg_weight": 0.35},
    "rival": {"exaggeration": 0.6, "cfg_weight": 0.45},
    "passenger": {"exaggeration": 0.55, "cfg_weight": 0.5},
}

# Who's in each role, by species. The game picks a speaker of the right role and species, by a hash of
# who's calling, so a station keeps its voice; with no speaker of that species it uses any in the role.
SLOTS = {
    "control": ["human", "human", "kesh", "kesh", "ilyan", "ilyan", "vey", "vey", "orun", "orun"],
    "pad": ["human", "kesh", "ilyan", "vey", "orun"],
    "camp": ["human", "orun", "kesh"],
    "ship": ["human", "human", "human", "kesh", "kesh", "ilyan", "vey", "orun"],
    "patrol": ["human", "kesh"],
    "tug": ["human", "orun"],
    "distress": ["human", "human", "kesh", "ilyan", "vey", "orun"],
    "rival": ["human", "human", "kesh", "orun"],
    "passenger": ["human", "human", "human", "kesh", "ilyan", "ilyan", "vey", "orun"],
}

LINE_DEFAULTS = {
    "comms:sos": {"exaggeration": 0.8, "cfg_weight": 0.3},
    "comms:sos_answer": {"exaggeration": 0.85, "cfg_weight": 0.3},
    "comms:sos_bye": {"exaggeration": 0.6},
    "comms:fined": {"exaggeration": 0.5},
    "comms:camp_fined": {"exaggeration": 0.75, "cfg_weight": 0.35},
    "comms:rival_warned_ok": {"exaggeration": 0.75},
    "comms:rival_warned_no": {"exaggeration": 0.7},
    "aboard:late": {"exaggeration": 0.65},
}

TAKES = {"default": 2, "with_values": 1, "keys": {"comms:greet": 3, "comms:hold": 3, "comms:speed": 3}}


# ---------------------------------------------------------------- cast

def load_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def save_json(p, d, indent=2):
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=indent, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, p)


def cmd_cast(a):
    """Pick a cast from refs/catalog.csv: varied accents, both genders, nobody in two roles."""
    if os.path.exists(CAST) and not a.force:
        sys.exit("%s exists. Edit it, or pass --force to pick a fresh cast (the old one is kept as voices.old.json)." % CAST)
    refs = os.path.abspath(a.refs)
    cat = os.path.join(refs, "catalog.csv")
    if not os.path.exists(cat):
        sys.exit("No catalog at %s. Run make_refs.py first." % cat)
    rows = [r for r in csv.DictReader(open(cat, encoding="utf-8")) if float(r.get("seconds") or 0) >= 8.0]
    rng = random.Random(a.seed)
    rng.shuffle(rows)

    def gender(r):
        g = (r.get("gender") or "").strip().upper()[:1]
        return g if g in ("M", "F") else "?"

    used = set()
    speakers = []
    for role, slots in SLOTS.items():
        # VCTK's short read sentences make crisp radio voices; anyone suits a passenger.
        pool = [r for r in rows if role == "passenger" or r["dataset"] == "vctk"] or rows
        accents_used = {}
        for i, sp in enumerate(slots):
            want = "F" if i % 2 == 0 else "M"
            free = [r for r in pool if (r["dataset"], r["speaker"]) not in used]
            if not free:
                free = [r for r in rows if (r["dataset"], r["speaker"]) not in used] or pool
            # Prefer the gender we want, then an accent this role hasn't had yet.
            free.sort(key=lambda r: (gender(r) != want and gender(r) != "?", accents_used.get(r.get("accent", ""), 0)))
            r = free[0]
            used.add((r["dataset"], r["speaker"]))
            accents_used[r.get("accent", "")] = accents_used.get(r.get("accent", ""), 0) + 1
            n = sum(1 for s in speakers if s["roles"] == [role] and s["species"] == sp) + 1
            speakers.append({
                "id": "%s_%s_%d" % (role, sp, n), "roles": [role], "species": sp,
                "ref": r["path"].replace("\\", "/"),
                "about": " ".join(x for x in [r["dataset"], r["speaker"], gender(r), r.get("age", ""), r.get("accent", ""), r.get("region", "")] if x and x != "?"),
            })
    if os.path.exists(CAST):
        shutil.copyfile(CAST, os.path.join(HERE, "voices.old.json"))
    cast = {
        "description": "Who says what. Edit freely: swap 'ref' for another voice in the catalogue, add speakers, or set "
                       "exaggeration, cfg_weight, temperature, pitch (semitones) or tempo on a speaker. 'species' and 'roles' "
                       "are what the game matches on. Re-record one speaker by moving its folder out of assets/audio/voice.",
        "refs_dir": refs.replace("\\", "/"),
        "species": SPECIES, "roles": ROLES, "lines": LINE_DEFAULTS, "takes": TAKES,
        "speakers": speakers,
    }
    save_json(CAST, cast)
    print("%d speakers -> %s" % (len(speakers), os.path.relpath(CAST, ROOT)))
    for s in speakers:
        print("  %-22s %s" % (s["id"], s["about"]))


def load_cast():
    if not os.path.exists(CAST):
        sys.exit("No cast yet. Run: python tools/voice/generate.py cast --refs <your refs folder>")
    c = load_json(CAST)
    for k, v in (("species", SPECIES), ("roles", ROLES), ("lines", LINE_DEFAULTS), ("takes", TAKES)):
        c.setdefault(k, v)
    return c


def load_lines():
    if not os.path.exists(LINES):
        sys.exit("No lines.json. Run: python tools/voice/build_lines.py")
    return load_json(LINES)["lines"]


def says(speaker, line):
    """Does this speaker say this line? Right role, and if the line names a species, theirs."""
    if line["role"] not in speaker["roles"]:
        return False
    sp = line.get("values", {}).get("species")
    return sp is None or sp == speaker["species"]


def takes_for(cast, line):
    t = cast["takes"]
    if line["key"] in t.get("keys", {}):
        return int(t["keys"][line["key"]])
    return int(t.get("with_values", 1) if line.get("values") else t.get("default", 2))


def settings(cast, speaker, line):
    s = {"exaggeration": 0.5, "cfg_weight": 0.5, "temperature": 0.8}
    sp = cast["species"].get(speaker["species"], {})
    s["pitch"] = float(sp.get("pitch", 0.0))
    s["tempo"] = float(sp.get("tempo", 1.0))
    for role in speaker["roles"]:
        s.update(cast["roles"].get(role, {}))
    s.update(cast["lines"].get(line["key"], {}))
    for k in ("exaggeration", "cfg_weight", "temperature", "pitch", "tempo"):
        if k in speaker:
            s[k] = speaker[k]
    return s


def rel_clip(speaker, line, take):
    return "%s/%s__%d.ogg" % (speaker["id"], line["file"], take)


def jobs(cast, lines, a=None):
    """Every clip the cast should have: (speaker, line, take, relative path)."""
    roles = set(_split(getattr(a, "role", ""))) if a else set()
    only = set(_split(getattr(a, "speaker", ""))) if a else set()
    keys = set(_split(getattr(a, "key", ""))) if a else set()
    out = []
    for s in cast["speakers"]:
        if only and s["id"] not in only:
            continue
        if roles and not roles.intersection(s["roles"]):
            continue
        for l in lines:
            if keys and l["key"] not in keys:
                continue
            if says(s, l):
                for t in range(1, takes_for(cast, l) + 1):
                    out.append((s, l, t, rel_clip(s, l, t)))
    return out


def _split(s):
    return [x.strip() for x in (s or "").split(",") if x.strip()]


def words(text):
    return re.findall(r"[a-z']+", text.lower())


def expected_seconds(text):
    """About how long Chatterbox takes to say this, before any tempo change."""
    w = len(words(text))
    stops = len(re.findall(r"[.!?]", text))
    return 0.35 + w / 2.7 + 0.25 * stops


# ---------------------------------------------------------------- plan

def cmd_plan(a):
    cast, lines = load_cast(), load_lines()
    js = jobs(cast, lines, a)
    done = sum(1 for j in js if os.path.exists(os.path.join(OUT, j[3])))
    secs = sum(expected_seconds(j[1]["text"]) for j in js)
    by = {}
    for s, l, t, p in js:
        by.setdefault(s["id"], [0, 0.0])
        by[s["id"]][0] += 1
        by[s["id"]][1] += expected_seconds(l["text"])
    for sid in sorted(by):
        print("  %-22s %4d clips  %5.1f min" % (sid, by[sid][0], by[sid][1] / 60))
    print("%d clips, %d recorded, %d to go. About %.0f minutes of speech." % (len(js), done, len(js) - done, secs / 60))
    # Chatterbox on a 12 GB RTX 2060 runs at very roughly 1x real time, plus a second or so per clip.
    left = sum(expected_seconds(j[1]["text"]) + 1.5 for j in js if not os.path.exists(os.path.join(OUT, j[3])))
    print("Rough recording time on an RTX 2060: %.1f to %.1f hours (more with --asr)." % (left / 3600 * 0.8, left / 3600 * 1.6))
    unvoiced = sorted({l["role"] for l in lines} - {r for s in cast["speakers"] for r in s["roles"]})
    if unvoiced:
        print("No speaker for: " + ", ".join(unvoiced))


# ---------------------------------------------------------------- the model

class Voice:
    """Chatterbox, holding one speaker's conditioning at a time (preparing it is the slow part)."""

    def __init__(self, cast, device, fake):
        self.cast, self.fake, self.ref = cast, fake, None
        self.sr = 24000
        if fake:
            return
        try:
            import torch
            from chatterbox.tts import ChatterboxTTS
        except ImportError as e:
            sys.exit("Chatterbox isn't importable here (%s). Run this in the Chatterbox environment, or pass --fake." % e)
        self.torch = torch
        if not device:
            device = "cuda" if torch.cuda.is_available() else "cpu"
        print("Loading Chatterbox on %s..." % device)
        self.model = ChatterboxTTS.from_pretrained(device=device)
        self.sr = int(self.model.sr)

    def ref_path(self, speaker):
        p = speaker["ref"]
        if not os.path.isabs(p):
            p = os.path.join(self.cast.get("refs_dir", ""), p)
        if not os.path.exists(p):
            sys.exit("%s: no reference voice at %s" % (speaker["id"], p))
        return p

    def say(self, speaker, text, s, seed):
        if self.fake:
            return _fake_speech(text, self.sr, seed)
        torch = self.torch
        ref = self.ref_path(speaker)
        if ref != self.ref:
            self.model.prepare_conditionals(ref, exaggeration=s["exaggeration"])
            self.ref = ref
        torch.manual_seed(seed)
        if torch.cuda.is_available():
            torch.cuda.manual_seed_all(seed)
        kw = {"exaggeration": s["exaggeration"], "cfg_weight": s["cfg_weight"], "temperature": s["temperature"]}
        try:
            wav = self.model.generate(text, **kw)
        except TypeError:   # an older Chatterbox without temperature
            kw.pop("temperature")
            wav = self.model.generate(text, **kw)
        return wav.detach().cpu().numpy().reshape(-1).astype(np.float32)


def _fake_speech(text, sr, seed):
    """Noise shaped like speech, the length Chatterbox would take. For --fake runs."""
    r = np.random.default_rng(seed)
    n = int(expected_seconds(text) * sr * r.uniform(0.85, 1.15))
    t = np.arange(n) / sr
    env = np.clip(np.sin(2 * np.pi * 3.3 * t + r.uniform(0, 6)) * 0.8 + 0.4, 0, 1)
    x = (np.sin(2 * np.pi * 140 * t) * 0.3 + r.normal(0, 0.1, n)) * env
    pad = np.zeros(int(0.3 * sr), dtype=np.float32)
    return np.concatenate([pad, x.astype(np.float32), pad])


class Ear:
    """Whisper, to hear whether a take says the line. Optional."""

    def __init__(self, device):
        self.kind = None
        try:
            from faster_whisper import WhisperModel
            dev = device or ("cuda" if _cuda() else "cpu")
            self.m = WhisperModel("small.en", device=dev, compute_type="float16" if dev == "cuda" else "int8")
            self.kind = "faster"
        except Exception:
            try:
                import whisper
                self.m = whisper.load_model("small.en", device=device or ("cuda" if _cuda() else "cpu"))
                self.kind = "openai"
            except Exception as e:
                sys.exit("--asr needs faster-whisper or openai-whisper (pip install faster-whisper). %s" % e)
        print("Checking takes with %s-whisper." % self.kind)

    def hear(self, x, sr):
        x16 = _resample(x, sr, 16000).astype(np.float32)
        if self.kind == "faster":
            segs, _ = self.m.transcribe(x16, language="en", beam_size=1)
            return " ".join(s.text for s in segs)
        return self.m.transcribe(x16, language="en", fp16=_cuda())["text"]


def _cuda():
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False


def wer(ref, hyp):
    a, b = words(ref), words(hyp)
    if not a:
        return 0.0
    d = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(b) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] != b[j - 1]))
            prev = cur
    return d[len(b)] / len(a)


# ---------------------------------------------------------------- after the model

def _resample(x, sr, to):
    if sr == to:
        return x
    try:
        import librosa
        return librosa.resample(x, orig_sr=sr, target_sr=to)
    except ImportError:
        from scipy.signal import resample_poly
        g = math.gcd(sr, to)
        return resample_poly(x, to // g, sr // g).astype(np.float32)


def _frames_db(x, sr, hop_s=0.01):
    hop = max(1, int(sr * hop_s))
    n = len(x) // hop
    if n == 0:
        return np.array([-120.0]), hop
    f = x[:n * hop].reshape(n, hop)
    return 20 * np.log10(np.sqrt((f ** 2).mean(axis=1)) + 1e-9), hop


def tidy_silence(x, sr, below=-42.0, keep_edge=0.06, max_gap=0.45):
    """Trim the ends, and shorten any pause longer than max_gap (Chatterbox sometimes stops to think)."""
    db, hop = _frames_db(x, sr)
    loud = db > (db.max() + below)
    if not loud.any():
        return x[:0]
    first, last = np.argmax(loud), len(loud) - 1 - np.argmax(loud[::-1])
    x = x[max(0, first * hop - int(keep_edge * sr)):min(len(x), (last + 1) * hop + int(keep_edge * sr))]
    db, hop = _frames_db(x, sr)
    loud = db > (db.max() + below)
    out, i, n = [], 0, len(loud)
    gap = int(max_gap / 0.01)
    while i < n:
        j = i
        while j < n and loud[j] == loud[i]:
            j += 1
        seg = x[i * hop:j * hop] if j < n else x[i * hop:]
        if not loud[i] and (j - i) > gap and i > 0 and j < n:
            half = int(max_gap * sr / 2)
            seg = np.concatenate([seg[:half], seg[-half:]])
        out.append(seg)
        i = j
    return np.concatenate(out) if out else x


def shift(x, sr, pitch, tempo):
    """Species colour: pitch in semitones, tempo as a speed factor."""
    if abs(pitch) < 0.01 and abs(tempo - 1.0) < 0.005:
        return x
    import librosa
    if abs(pitch) >= 0.01:
        x = librosa.effects.pitch_shift(x, sr=sr, n_steps=pitch, res_type="soxr_hq")
    if abs(tempo - 1.0) >= 0.005:
        x = librosa.effects.time_stretch(x, rate=tempo)
    return x.astype(np.float32)


def level(x, sr, rms_db=-20.0, peak_db=-1.0):
    """Even loudness across speakers: speech frames to rms_db, peaks no higher than peak_db."""
    try:
        from scipy.signal import butter, sosfilt
        x = sosfilt(butter(2, 70, "highpass", fs=sr, output="sos"), x).astype(np.float32)
    except ImportError:
        pass
    db, hop = _frames_db(x, sr)
    act = db > db.max() - 30
    n = len(db)
    frames = x[:n * hop].reshape(n, hop)[act] if n * hop <= len(x) and act.any() else x
    rms = np.sqrt((np.asarray(frames) ** 2).mean()) + 1e-9
    x = x * (10 ** (rms_db / 20) / rms)
    pk = np.abs(x).max() + 1e-9
    lim = 10 ** (peak_db / 20)
    if pk > lim:   # soft-knee: squash only what goes over
        x = np.where(np.abs(x) > lim * 0.7, np.sign(x) * (lim * 0.7 + (lim * 0.3) * np.tanh((np.abs(x) - lim * 0.7) / (lim * 0.3))), x)
    fi, fo = int(0.005 * sr), int(0.02 * sr)
    if len(x) > fi + fo:
        x[:fi] *= np.linspace(0, 1, fi)
        x[-fo:] *= np.linspace(1, 0, fo)
    return x.astype(np.float32)


def finish(x, sr, s):
    x = tidy_silence(x, sr)
    x = shift(x, sr, float(s.get("pitch", 0)), float(s.get("tempo", 1)))
    x = _resample(x, sr, GAME_SR)
    return level(x, GAME_SR)


def write_ogg(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path[:-4] + ".tmp.ogg"
    try:
        sf.write(tmp, x, GAME_SR, format="OGG", subtype="VORBIS", compression_level=0.6)
    except TypeError:   # soundfile before 0.12
        sf.write(tmp, x, GAME_SR, format="OGG", subtype="VORBIS")
    os.replace(tmp, path)


def check(text, raw, sr, ear):
    """How wrong a take looks: 0 is fine. Too long (rambling, repeating) or too short (dropped words) is bad;
    with Whisper, so is saying something else."""
    d = len(tidy_silence(raw, sr)) / sr
    want = expected_seconds(text)
    ratio = d / want if want else 1.0
    bad = 0.0
    if ratio > 1.9:
        bad += ratio - 1.9
    if ratio < 0.55:
        bad += 0.55 - ratio
    if not np.isfinite(raw).all() or d < 0.3:
        bad += 10
    heard, w = None, None
    if ear:
        heard = ear.hear(raw, sr)
        w = wer(text, heard)
        bad += max(0.0, w - 0.15) * 2
    return bad, {"seconds": round(d, 2), "ratio": round(ratio, 2), "wer": None if w is None else round(w, 3), "heard": heard}


# ---------------------------------------------------------------- run

def seed_for(line_id, speaker_id, take, attempt, tri):
    return zlib.crc32(("%s|%s|%d|%d|%d" % (line_id, speaker_id, take, attempt, tri)).encode()) & 0x7FFFFFFF


def attempts(rel):
    """How many times this clip has been rejected (each rejection moves a file to _rejected)."""
    base = os.path.join(REJECTED, rel[:-4])
    return len(glob.glob(glob.escape(base) + ".r*.ogg"))


def take_rejects():
    """Move the clips listed in rejects.txt aside, so `run` records them again with a new seed."""
    if not os.path.exists(REJECTS):
        return 0
    names = [l.strip().replace("\\", "/") for l in open(REJECTS, encoding="utf-8") if l.strip() and not l.startswith("#")]
    moved = 0
    for rel in names:
        src = os.path.join(OUT, rel)
        if not os.path.exists(src):
            continue
        n = attempts(rel) + 1
        dst = os.path.join(REJECTED, "%s.r%d.ogg" % (rel[:-4], n))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.replace(src, dst)
        imp = src + ".import"   # Godot's import record for it
        if os.path.exists(imp):
            os.replace(imp, dst + ".import")
        moved += 1
    with open(os.path.join(HERE, "rejects_done.txt"), "a", encoding="utf-8") as f:
        f.write("# %s\n" % time.strftime("%Y-%m-%d %H:%M"))
        f.writelines(n + "\n" for n in names)
    open(REJECTS, "w", encoding="utf-8").write("# One clip per line, as review.html lists them. `run` re-records them.\n")
    return moved


def cmd_run(a):
    cast, lines = load_cast(), load_lines()
    _gdignore()
    moved = take_rejects()
    if moved:
        print("%d rejected takes moved to %s, to record again." % (moved, os.path.relpath(REJECTED, ROOT)))
    todo = [j for j in jobs(cast, lines, a) if not os.path.exists(os.path.join(OUT, j[3]))]
    if a.limit:
        todo = todo[:a.limit]
    if not todo:
        print("Nothing to record.")
        write_index(cast, lines)
        return
    # Speaker by speaker: Chatterbox prepares a voice once and reuses it.
    order = {s["id"]: i for i, s in enumerate(cast["speakers"])}
    todo.sort(key=lambda j: (order[j[0]["id"]], j[1]["id"], j[2]))
    print("%d clips to record." % len(todo))
    voice = Voice(cast, a.device, a.fake)
    ear = Ear(a.device) if a.asr else None
    t0, said = time.time(), 0.0
    man = open(MANIFEST, "a", encoding="utf-8")
    try:
        for n, (s, l, take, rel) in enumerate(todo, 1):
            st = settings(cast, s, l)
            att = attempts(rel)
            best = None
            for tri in range(max(1, a.tries)):
                seed = seed_for(l["id"], s["id"], take, att, tri)
                raw = voice.say(s, l["text"], st, seed)
                bad, info = check(l["text"], raw, voice.sr, ear)
                if best is None or bad < best[0]:
                    best = (bad, raw, seed, info)
                if bad == 0:
                    break
            bad, raw, seed, info = best
            x = finish(raw, voice.sr, st)
            write_ogg(os.path.join(OUT, rel), x)
            said += len(x) / GAME_SR
            row = {"file": rel, "id": l["id"], "speaker": s["id"], "take": take, "seed": seed, "attempt": att,
                   "text": l["text"], "length": round(len(x) / GAME_SR, 2), "flag": round(bad, 2), **info,
                   **{k: st[k] for k in ("exaggeration", "cfg_weight", "temperature", "pitch", "tempo")},
                   "at": time.strftime("%Y-%m-%d %H:%M:%S")}
            man.write(json.dumps(row, ensure_ascii=False) + "\n")
            man.flush()
            el = time.time() - t0
            eta = el / n * (len(todo) - n)
            print("[%d/%d] %-20s %-44s %4.1fs%s  eta %dm" % (n, len(todo), s["id"], l["id"][:44], len(x) / GAME_SR,
                                                              "  CHECK" if bad > 0 else "", eta // 60))
            if n % 25 == 0:
                write_index(cast, lines, quiet=True)
    except KeyboardInterrupt:
        print("\nStopped. Run again to carry on where it left off.")
    finally:
        man.close()
        write_index(cast, lines)
    print("%.1f minutes of speech in %.1f minutes." % (said / 60, (time.time() - t0) / 60))


def _gdignore():
    """Keep Godot from importing the preview and rejected audio under tools/voice."""
    p = os.path.join(HERE, ".gdignore")
    if not os.path.exists(p):
        open(p, "w").close()


# ---------------------------------------------------------------- index

def write_index(cast, lines, quiet=False):
    """What the game reads: speakers, and for every line id the recorded files per speaker."""
    clips, total = {}, 0
    for s, l, t, rel in jobs(cast, lines):
        if os.path.exists(os.path.join(OUT, rel)):
            clips.setdefault(l["id"], {}).setdefault(s["id"], []).append(rel)
            total += 1
    idx = {
        "description": "Made by tools/voice/generate.py. Paths are relative to this folder. Line ids are build_lines.py's.",
        "version": 1, "rate": GAME_SR,
        "speakers": {s["id"]: {"roles": s["roles"], "species": s["species"]} for s in cast["speakers"]},
        "radio": sorted({l["key"] for l in lines if l.get("radio", True)}),
        "clips": clips,
    }
    os.makedirs(OUT, exist_ok=True)
    save_json(os.path.join(OUT, "index.json"), idx, indent=1)
    if not quiet:
        print("index.json: %d clips for %d of %d lines." % (total, len(clips), len(lines)))


def cmd_index(a):
    write_index(load_cast(), load_lines())


# ---------------------------------------------------------------- preview and review

def cmd_preview(a):
    """One line per speaker, finished (pitch, tempo, level) but not radio, into tools/voice/preview/."""
    cast, lines = load_cast(), load_lines()
    _gdignore()
    d = os.path.join(HERE, "preview")
    os.makedirs(d, exist_ok=True)
    voice = Voice(cast, a.device, a.fake)
    only = set(_split(a.speaker))
    for s in cast["speakers"]:
        if only and s["id"] not in only:
            continue
        mine = [l for l in lines if says(s, l)]
        if not mine:
            continue
        l = next((x for x in mine if x["key"] == a.key), None) if a.key else None
        l = l or max(mine[:12], key=lambda x: len(x["text"]))
        st = settings(cast, s, l)
        x = finish(voice.say(s, l["text"], st, seed_for(l["id"], s["id"], 0, 0, 0)), voice.sr, st)
        p = os.path.join(d, s["id"] + ".wav")
        sf.write(p, x, GAME_SR)
        print("  %-22s %s" % (s["id"], l["text"]))
    print("Previews in " + os.path.relpath(d, ROOT))


REVIEW_HTML = """<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Far Haul voice review</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#14181c;--fg:#dde3e8;--dim:#8a96a0;--line:#2a323a;--go:#6fc28b;--no:#e0665a}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif}
header{position:sticky;top:0;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 16px;display:flex;gap:12px;flex-wrap:wrap;align-items:center}
main{padding:8px 16px 80px;max-width:1100px}
.l{border-bottom:1px solid var(--line);padding:8px 0}
.t{margin-bottom:4px}.id{color:var(--dim);font-size:12px}
.c{display:inline-flex;align-items:center;gap:2px;margin:2px 8px 2px 0;font-size:13px}
.c button{background:#222a31;color:var(--fg);border:1px solid var(--line);border-radius:4px;padding:2px 7px;cursor:pointer}
.c button.p{border-color:var(--go)}.c.x .s{color:var(--no);text-decoration:line-through}
.flag{color:#e8b65a}
textarea{width:100%;height:110px;background:#0e1114;color:var(--fg);border:1px solid var(--line)}
footer{position:fixed;bottom:0;left:0;right:0;background:var(--bg);border-top:1px solid var(--line);padding:8px 16px}
</style></head><body>
<header><strong>Voice review</strong>
<label>Role <select id="role"><option value="">all</option></select></label>
<label>Speaker <select id="spk"><option value="">all</option></select></label>
<label><input type="checkbox" id="flagged"> flagged only</label>
<span id="count"></span></header>
<main id="m"></main>
<footer><details><summary><span id="nrej">0</span> marked. Paste these into tools/voice/rejects.txt, then run generate.py again.</summary>
<textarea id="out" readonly></textarea></details></footer>
<script>
const D=__DATA__;const base="../../assets/audio/voice/";const audio=new Audio();const rej=new Set();
const roles=[...new Set(D.lines.map(l=>l.role))].sort(),spks=[...new Set(D.lines.flatMap(l=>l.clips.map(c=>c.s)))].sort();
roles.forEach(r=>role.add(new Option(r,r)));spks.forEach(s=>spk.add(new Option(s,s)));
function draw(){const R=role.value,S=spk.value,F=flagged.checked;let n=0;m.innerHTML="";
for(const l of D.lines){if(R&&l.role!==R)continue;const cs=l.clips.filter(c=>(!S||c.s===S)&&(!F||c.f));if(!cs.length)continue;n+=cs.length;
const d=document.createElement("div");d.className="l";d.innerHTML=`<div class="t">${l.text}</div><div class="id">${l.id}</div>`;
for(const c of cs){const e=document.createElement("span");e.className="c"+(rej.has(c.p)?" x":"");
e.innerHTML=`<button class="play" title="play">&#9654;</button><span class="s">${c.s} ${c.t}${c.f?' <span class="flag" title="'+(c.h||'length looked off')+'">?</span>':''}</span><button class="rj" title="mark bad">&#10005;</button>`;
e.querySelector(".play").onclick=ev=>{audio.src=base+c.p;audio.play();document.querySelectorAll(".p").forEach(b=>b.classList.remove("p"));ev.target.classList.add("p")};
e.querySelector(".rj").onclick=()=>{rej.has(c.p)?rej.delete(c.p):rej.add(c.p);e.classList.toggle("x");out.value=[...rej].join("\\n");nrej.textContent=rej.size};
d.appendChild(e)}m.appendChild(d)}count.textContent=n+" clips"}
[role,spk,flagged].forEach(e=>e.onchange=draw);draw();
</script></body></html>"""


def cmd_review(a):
    cast, lines = load_cast(), load_lines()
    flags = {}
    if os.path.exists(MANIFEST):
        for row in open(MANIFEST, encoding="utf-8"):
            try:
                r = json.loads(row)
            except ValueError:
                continue
            flags[r["file"]] = (r.get("flag", 0) > 0, r.get("heard"))
    by = {}
    for s, l, t, rel in jobs(cast, lines):
        if os.path.exists(os.path.join(OUT, rel)):
            e = by.setdefault(l["id"], {"id": l["id"], "role": l["role"], "text": l["text"], "clips": []})
            f, h = flags.get(rel, (False, None))
            e["clips"].append({"s": s["id"], "t": t, "p": rel, "f": f, "h": h})
    data = {"lines": [by[l["id"]] for l in lines if l["id"] in by]}
    p = os.path.join(HERE, "review.html")
    open(p, "w", encoding="utf-8").write(REVIEW_HTML.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/")))
    print("%d clips -> %s (open it in a browser)" % (sum(len(v["clips"]) for v in data["lines"]), os.path.relpath(p, ROOT)))


# ----------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cast", help="pick a cast from the reference voices")
    c.add_argument("--refs", required=True, help="the folder make_refs.py wrote (has catalog.csv)")
    c.add_argument("--seed", type=int, default=7)
    c.add_argument("--force", action="store_true")
    for name in ("plan", "run", "preview"):
        p = sub.add_parser(name)
        p.add_argument("--role", default="")
        p.add_argument("--speaker", default="")
        p.add_argument("--key", default="")
        if name != "plan":
            p.add_argument("--device", default="")
            p.add_argument("--fake", action="store_true")
        if name == "run":
            p.add_argument("--limit", type=int, default=0)
            p.add_argument("--asr", action="store_true")
            p.add_argument("--tries", type=int, default=3)
    sub.add_parser("review")
    sub.add_parser("index")
    a = ap.parse_args()
    {"cast": cmd_cast, "plan": cmd_plan, "run": cmd_run, "preview": cmd_preview, "review": cmd_review, "index": cmd_index}[a.cmd](a)


if __name__ == "__main__":
    main()
