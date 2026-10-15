#!/usr/bin/env python3
"""Reference voices for Chatterbox from two openly licensed speech datasets (both CC BY 4.0):

  VCTK 0.92   110 English speakers, many accents, with age/gender/accent in speaker-info.txt
  LibriTTS-R  audiobook readers, restored audio (24 kHz); dev-clean alone has about 40 speakers

For every speaker it stitches clean utterances into one 10 to 15 s reference clip (silence trimmed,
short gaps, mono, 24 kHz, peak-normalised) and writes a catalogue. With --audition it also has Chatterbox
read one test line in each voice, so you can pick a cast by ear.

  python make_refs.py vctk      D:/data/VCTK-Corpus-0.92      --out refs
  python make_refs.py libritts  D:/data/LibriTTS_R/dev-clean  --out refs
  python make_refs.py audition  --out refs   [--line "Freighter, cleared to berth six."]

Output:
  refs/vctk/p225.wav, refs/libritts/84.wav, ...      reference clips (Chatterbox audio_prompt_path)
  refs/catalog.csv                                    dataset, speaker, gender, age, accent, region, seconds, path
  refs/auditions/<dataset>_<speaker>.wav              with `audition`

Needs: numpy, soundfile, torch + torchaudio (already in a Chatterbox environment). chatterbox-tts for
`audition`.
"""
import argparse
import csv
import glob
import os
import sys

import numpy as np
import soundfile as sf

SR = 24000
TARGET_S = (10.0, 15.0)
GAP_S = 0.2


def _resample(x, sr):
    if sr == SR:
        return x
    import torch
    import torchaudio
    return torchaudio.functional.resample(torch.from_numpy(x).float()[None], sr, SR)[0].numpy()


def _trim(x, thresh_db=-40.0, pad_s=0.05):
    """Cut leading and trailing silence (anything under thresh_db of the peak)."""
    if x.size == 0:
        return x
    a = np.abs(x)
    th = a.max() * (10 ** (thresh_db / 20.0))
    loud = np.where(a > th)[0]
    if loud.size == 0:
        return x[:0]
    pad = int(pad_s * SR)
    return x[max(0, loud[0] - pad):min(x.size, loud[-1] + pad)]


def _load(path):
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    return _trim(_resample(x.mean(axis=1), sr))


def _stitch(files):
    """Clean utterances, longest-first-ish, until the clip is 10 to 15 s."""
    parts, total = [], 0.0
    for f in files:
        try:
            x = _load(f)
        except Exception as e:  # a damaged file: skip it
            print("  skip %s (%s)" % (f, e))
            continue
        d = x.size / SR
        if d < 1.5 or d > 9.0:      # too short to carry the voice, or too long to fit
            continue
        if total + d > TARGET_S[1]:
            continue
        parts += [x, np.zeros(int(GAP_S * SR), dtype=np.float32)]
        total += d + GAP_S
        if total >= TARGET_S[0]:
            break
    if not parts:
        return None
    y = np.concatenate(parts[:-1])
    return (y / max(1e-6, np.abs(y).max()) * 0.9).astype(np.float32)


def _write(out, dataset, speaker, clip, meta, rows):
    d = os.path.join(out, dataset)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "%s.wav" % speaker)
    sf.write(p, clip, SR)
    rows.append({"dataset": dataset, "speaker": speaker, "gender": meta.get("gender", ""), "age": meta.get("age", ""),
                 "accent": meta.get("accent", ""), "region": meta.get("region", ""),
                 "seconds": "%.1f" % (clip.size / SR), "path": os.path.relpath(p, out)})
    print("  %s %s  %.1f s  %s" % (dataset, speaker, clip.size / SR, " ".join(v for v in meta.values() if v)))


def vctk(root, out, rows, only):
    """VCTK 0.92: wav48_silence_trimmed/<p225>/<p225_001>_mic1.flac, speaker-info.txt."""
    info = {}
    si = os.path.join(root, "speaker-info.txt")
    if os.path.exists(si):
        for line in open(si, encoding="utf-8", errors="replace").read().splitlines()[1:]:
            bits = line.split()
            if len(bits) >= 4:
                sid = bits[0] if bits[0].startswith("p") or bits[0].startswith("s") else "p" + bits[0]
                info[sid] = {"age": bits[1], "gender": bits[2], "accent": bits[3], "region": " ".join(bits[4:]).strip("()")}
    audio = os.path.join(root, "wav48_silence_trimmed")
    if not os.path.isdir(audio):
        audio = os.path.join(root, "wav48")
    for spk in sorted(os.listdir(audio)):
        if only and spk not in only:
            continue
        files = sorted(glob.glob(os.path.join(audio, spk, "*_mic1.flac"))) or sorted(glob.glob(os.path.join(audio, spk, "*.flac"))) \
            or sorted(glob.glob(os.path.join(audio, spk, "*.wav")))
        files = files[24:] + files[:24]   # skip the first few: the same "please call Stella" passage for everyone
        clip = _stitch(files)
        if clip is not None:
            _write(out, "vctk", spk, clip, info.get(spk, {}), rows)


def libritts(root, out, rows, only):
    """LibriTTS-R: <subset>/<speaker>/<chapter>/<spk>_<chap>_<utt>.wav. Gender from speakers.tsv if found."""
    info = {}
    for cand in [os.path.join(root, "speakers.tsv"), os.path.join(os.path.dirname(root.rstrip("/\\")), "speakers.tsv"),
                 os.path.join(root, "SPEAKERS.txt"), os.path.join(os.path.dirname(root.rstrip("/\\")), "SPEAKERS.txt")]:
        if os.path.exists(cand):
            for line in open(cand, encoding="utf-8", errors="replace"):
                if line.startswith(";") or line.startswith("READER"):
                    continue
                bits = [b.strip() for b in (line.split("\t") if "\t" in line else line.split("|"))]
                if len(bits) >= 2 and bits[0].isdigit():
                    info[bits[0]] = {"gender": bits[1]}
            break
    for spk in sorted(os.listdir(root), key=lambda s: (len(s), s)):
        if not os.path.isdir(os.path.join(root, spk)) or (only and spk not in only):
            continue
        files = sorted(glob.glob(os.path.join(root, spk, "*", "*.wav")))
        clip = _stitch(files)
        if clip is not None:
            _write(out, "libritts", spk, clip, info.get(spk, {}), rows)


def _save_catalog(out, rows):
    path = os.path.join(out, "catalog.csv")
    old = []
    if os.path.exists(path):
        keep = {(r["dataset"], r["speaker"]) for r in rows}
        old = [r for r in csv.DictReader(open(path, encoding="utf-8")) if (r["dataset"], r["speaker"]) not in keep]
    allrows = sorted(old + rows, key=lambda r: (r["dataset"], r["speaker"]))
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["dataset", "speaker", "gender", "age", "accent", "region", "seconds", "path"])
        w.writeheader()
        w.writerows(allrows)
    print("%d voices in %s" % (len(allrows), path))


def audition(out, line, exaggeration, cfg):
    from chatterbox.tts import ChatterboxTTS
    import torch
    import torchaudio as ta
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = ChatterboxTTS.from_pretrained(device=device)
    d = os.path.join(out, "auditions")
    os.makedirs(d, exist_ok=True)
    for r in csv.DictReader(open(os.path.join(out, "catalog.csv"), encoding="utf-8")):
        dst = os.path.join(d, "%s_%s.wav" % (r["dataset"], r["speaker"]))
        if os.path.exists(dst):
            continue
        torch.manual_seed(1)
        wav = model.generate(line, audio_prompt_path=os.path.join(out, r["path"]), exaggeration=exaggeration, cfg_weight=cfg)
        ta.save(dst, wav, model.sr)
        print("  " + dst)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", choices=["vctk", "libritts", "audition"])
    ap.add_argument("root", nargs="?", help="the dataset folder (VCTK-Corpus-0.92, or LibriTTS_R/dev-clean)")
    ap.add_argument("--out", default="refs")
    ap.add_argument("--speakers", default="", help="only these speakers, comma-separated (p225,p226 or 84,174)")
    ap.add_argument("--line", default="Freighter, traffic control. Cleared to berth six. Collar's lit green. Try to hit it.")
    ap.add_argument("--exaggeration", type=float, default=0.5)
    ap.add_argument("--cfg", type=float, default=0.5)
    a = ap.parse_args()
    if a.what == "audition":
        audition(a.out, a.line, a.exaggeration, a.cfg)
        return
    if not a.root or not os.path.isdir(a.root):
        sys.exit("Point it at the dataset folder.")
    only = set(s.strip() for s in a.speakers.split(",") if s.strip())
    rows = []
    (vctk if a.what == "vctk" else libritts)(a.root, a.out, rows, only)
    _save_catalog(a.out, rows)


if __name__ == "__main__":
    main()
