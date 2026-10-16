# Recording the voices

The radio and aboard lines are recorded with Chatterbox TTS, using reference voices from VCTK and LibriTTS-R (both CC BY 4.0). The game plays them in place of the babble wherever a recording exists. Names (ships, stations, places, prices) are never spoken. The subtitle carries them.

| File | What it is |
|---|---|
| `voiced.json` | How each game line is spoken, and the value sets (berths, fines, tonnes...) to say in every variation. Edit this. |
| `build_lines.py` | Expands `voiced.json` into `lines.json`: 246 lines with ids. Checks them against the game's data. |
| `make_refs.py` | Builds 10–15 s reference clips and `catalog.csv` from the datasets. |
| `voice.bat`, `setup_torch.py` | The Windows front end: setup, download, refs, then the generator's commands. |
| `generate.py` | Records the lines into `assets/audio/voice/` as OGG, with the `index.json` the game reads. |
| `voices.json` | The cast, made by `generate.py cast`, then edited by hand. |
| `manifest.jsonl` | One row per recorded clip: seed, settings, length, checks. |

## Run it (Windows)

Everything lives in the repo under `tools\voice\`: the Python environment, the downloaded datasets, the reference clips and Chatterbox's model. Godot ignores that folder (`.gdignore`), and git ignores everything in it except the scripts. Only the recorded clips in `assets\audio\voice\` ship.

From `D:\Dev\FarHaul`:

```
tools\voice\voice.bat setup
tools\voice\voice.bat download
tools\voice\voice.bat refs
tools\voice\voice.bat cast
tools\voice\voice.bat plan
tools\voice\voice.bat preview
tools\voice\voice.bat run
tools\voice\voice.bat review
```

- **`setup`** makes a Python 3.11 venv in `tools\voice\.venv`. It installs Chatterbox, then swaps in the CUDA build of torch, and finally checks that the GPU is visible. It needs Python 3.11: run `winget install Python.Python.3.11` first if you don't have it.
- **`download`** fetches VCTK (11 GB) and LibriTTS-R dev-clean (1.3 GB) into `tools\voice\data\` and unpacks them. You can rerun it if a download breaks; it resumes.
- **`refs`** builds a 10–15 s reference clip per speaker in `tools\voice\refs\`, plus `catalog.csv`.
- **Every other command** goes to `generate.py`, after `build_lines.py` has refreshed `lines.json`. The first `preview` or `run` downloads Chatterbox's model (about 3 GB) into `tools\voice\.hf\`.

1. **`cast`** picks 48 speakers from `catalog.csv`. It alternates genders, spreads accents and never puts one voice in two roles. Radio roles use VCTK only. The result is written to `voices.json`.
2. **`plan`** shows what will be recorded: about 2,250 clips, about 3¼ hours of speech, and roughly 3½ to 7 hours on the RTX 2060.
3. **`preview`** writes one line per speaker to `tools\voice\preview\`. If you don't like a voice, change its `ref` in `voices.json` to another `vctk/pNNN.wav` from the catalogue and preview again (`--speaker control_kesh_1`).
4. **`run`** records everything. Stop it with Ctrl+C whenever you like; running it again carries on where it left off. Narrow a run with `--role control`, `--speaker ...`, `--key comms:greet` or `--limit 50`.
5. **`review`** writes `tools\voice\review.html`. Open it in a browser, play the clips and click ✕ on bad ones. Paste the list it gives you into `tools\voice\rejects.txt`. The next `run` moves those clips into `tools\voice\_rejected\` and records them again with a new seed.

## Settings

All of these are in `voices.json`:

- **Per species:** pitch in semitones, tempo, and formant (vocal-tract size: below 1 is a bigger body). The shift is done with Praat (praat-parselmouth), which keeps the words clear.
  - kesh: −3.5, 0.92, 0.9
  - ilyan: +3, 1.1, 1.08
  - vey: +1.5, 1.04, 1.03
  - orun: −2, 0.95, 0.95
- **Per role:** Chatterbox `exaggeration` (emotion) and `cfg_weight` (pace). Control is 0.4; distress is 0.7 with cfg 0.35.
- **Per line key:** overrides under `"lines"`. For example, maydays are louder.
- **Per speaker:** any of `exaggeration`, `cfg_weight`, `temperature`, `pitch` and `tempo`.
- **Takes:** 2 per line by default; 1 for lines that already vary by value (the berth number, say); 3 for greetings, holds and speed warnings.

To re-record with new settings, move the clips aside with `voice.bat redo` (`--speaker`, `--species`, `--role` or `--key`), then `voice.bat run`.

## Checks

Every take is checked two ways:

- **Length.** It's timed against how long the line should be. Rambling and repeated words run long; dropped words run short.
- **Words.** Whisper (faster-whisper, installed by `setup`) listens and compares what it hears with the line. Numbers and sound-alikes like berth/birth don't count as mistakes. Use `--no-asr` to skip this check.

A take that fails either check is re-rolled, up to `--tries` times (3 by default), and the best one is kept. Takes that still look off get a "?" on the review page, with what Whisper heard.

Invented words, such as the species names, are spelled for the ear in `voiced.json` ("Ill-yan", "Oh-roon", "Vay"). Whisper often mishears them anyway.

## After a change to the lines

Rerun `build_lines.py`, then `generate.py run`. New lines get recorded; existing clips are kept. A line whose wording changed keeps its old clips until you move them aside. Its file name comes from the id, not from the text.

## Output

- **Files:** `assets/audio/voice/<speaker>/<line-file>__<take>.ogg`. Mono, 22050 Hz, Ogg Vorbis, with silence trimmed and loudness evened out. They're recorded clean: the game adds the radio sound itself.
- **Index:** `assets/audio/voice/index.json` maps each line id (for example `comms:cleared|0|berth=6`) to its clips for each speaker.
- **Watermark:** Chatterbox puts an inaudible PerTh watermark in every clip. Leave it in.

## Credit (CC BY 4.0)

Reference voices from the CSTR VCTK Corpus (Yamagishi, Veaux & MacDonald, University of Edinburgh, CC BY 4.0) and LibriTTS-R (Koizumi et al., Google, CC BY 4.0), built on LibriVox recordings. Voices generated with Chatterbox TTS by Resemble AI.
