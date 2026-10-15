@echo off
rem Far Haul voice recording, all inside the repo. Run from anywhere:
rem
rem   tools\voice\voice.bat setup      Python 3.11 venv in tools\voice\.venv, with CUDA torch and Chatterbox
rem   tools\voice\voice.bat download   VCTK and LibriTTS-R dev-clean into tools\voice\data (about 13 GB)
rem   tools\voice\voice.bat refs       reference clips into tools\voice\refs
rem   tools\voice\voice.bat cast       then plan, preview, run, review, index (see README.md)
rem
rem Everything lands under tools\voice, which Godot ignores (.gdignore) and git ignores (.gitignore),
rem apart from the scripts and the recorded clips in assets\audio\voice.

setlocal
set "V=%~dp0"
set "REPO=%~dp0..\.."
set "PY=%V%.venv\Scripts\python.exe"
rem Chatterbox's model download goes here too, not into your user folder.
set "HF_HOME=%V%.hf"
set "PYTHONUTF8=1"
cd /d "%REPO%"

if /i "%~1"=="setup" goto setup
if /i "%~1"=="download" goto download
if /i "%~1"=="refs" goto refs
if "%~1"=="" goto usage
if not exist "%PY%" goto nosetup
"%PY%" "%V%build_lines.py" || exit /b 1
"%PY%" "%V%generate.py" %*
exit /b %errorlevel%

:usage
echo Usage: tools\voice\voice.bat setup ^| download ^| refs ^| cast ^| plan ^| preview ^| run ^| review ^| index
echo See tools\voice\README.md
exit /b 0

:nosetup
echo No voice environment yet. Run: tools\voice\voice.bat setup
exit /b 1

:setup
py -3.11 --version >nul 2>&1
if errorlevel 1 (
  echo Chatterbox needs Python 3.11. Install it with:  winget install Python.Python.3.11
  echo then run this again.
  exit /b 1
)
if not exist "%PY%" (
  echo Making tools\voice\.venv ...
  py -3.11 -m venv "%V%.venv" || exit /b 1
)
"%PY%" -m pip install --upgrade pip
"%PY%" -m pip install chatterbox-tts soundfile librosa scipy faster-whisper || exit /b 1
rem pip gives the CPU-only torch on Windows: swap in the CUDA build of the same version.
"%PY%" "%V%setup_torch.py" || exit /b 1
"%PY%" -c "import torch, chatterbox, soundfile, librosa; print('torch', torch.__version__, '| CUDA:', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'no GPU')"
echo Setup done. Next: tools\voice\voice.bat download
exit /b 0

:download
if not exist "%V%data" mkdir "%V%data"
rem Each step leaves a .done file, so running this again picks up where it stopped (curl resumes too).
if not exist "%V%data\vctk_zip.done" (
  echo Downloading VCTK 0.92, about 11 GB ...
  curl.exe -L -f -C - -o "%V%data\VCTK-Corpus-0.92.zip" https://datashare.ed.ac.uk/bitstream/handle/10283/3443/VCTK-Corpus-0.92.zip || exit /b 1
  echo.> "%V%data\vctk_zip.done"
)
if not exist "%V%data\vctk.done" (
  echo Unpacking VCTK ...
  mkdir "%V%data\VCTK-Corpus-0.92" 2>nul
  tar -xf "%V%data\VCTK-Corpus-0.92.zip" -C "%V%data\VCTK-Corpus-0.92" || exit /b 1
  echo.> "%V%data\vctk.done"
)
if not exist "%V%data\libritts_tar.done" (
  echo Downloading LibriTTS-R dev-clean, about 1.3 GB ...
  curl.exe -L -f -C - -o "%V%data\dev_clean.tar.gz" https://www.openslr.org/resources/141/dev_clean.tar.gz || exit /b 1
  echo.> "%V%data\libritts_tar.done"
)
if not exist "%V%data\libritts.done" (
  echo Unpacking LibriTTS-R dev-clean ...
  tar -xzf "%V%data\dev_clean.tar.gz" -C "%V%data" || exit /b 1
  echo.> "%V%data\libritts.done"
)
echo Downloads done. The .zip and .tar.gz in tools\voice\data can go once refs are built. Next: tools\voice\voice.bat refs
exit /b 0

:refs
if not exist "%PY%" goto nosetup
"%PY%" "%V%make_refs.py" vctk "%V%data\VCTK-Corpus-0.92" --out "%V%refs" || exit /b 1
"%PY%" "%V%make_refs.py" libritts "%V%data\LibriTTS_R\dev-clean" --out "%V%refs" || exit /b 1
echo Next: tools\voice\voice.bat cast
exit /b 0
