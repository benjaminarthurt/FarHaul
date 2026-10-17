@echo off
rem Double-click to record every voice line. Safe to close and run again: it carries on where it left off.
rem Progress also goes to tools\voice\run.log. It rests 4 s after each clip to keep the GPU cooler.
title Far Haul voice recording
set "PYTHONUNBUFFERED=1"
set "TQDM_DISABLE=1"
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -Command "& tools\voice\voice.bat run --rest 4 2>&1 | Tee-Object -FilePath tools\voice\run.log -Append"
echo.
echo Finished. Next: tools\voice\voice.bat review
pause
