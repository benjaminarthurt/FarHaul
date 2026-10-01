@echo off
setlocal enabledelayedexpansion
rem Far Haul one-click launcher. Double-click to play (runs the game, not the editor).
rem Finds Godot 4 automatically. If it cannot, it asks once and remembers (.godot-path.txt).
cd /d "%~dp0"

set "G="
if defined GODOT if exist "%GODOT%" set "G=%GODOT%"
if not defined G if exist ".godot-path.txt" set /p G=<".godot-path.txt"
if defined G if not exist "!G!" set "G="

if not defined G for /f "delims=" %%i in ('where godot 2^>nul') do if not defined G set "G=%%i"
if not defined G for /f "delims=" %%i in ('where Godot_v4*.exe 2^>nul') do if not defined G set "G=%%i"

if not defined G for %%d in ("%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop" "%USERPROFILE%\Documents" "%LOCALAPPDATA%\Programs" "%ProgramFiles%" "D:\Dev" "D:\Tools" "C:\Tools") do (
  if not defined G if exist %%d (
    for /f "delims=" %%i in ('dir /b /s "%%~d\Godot*4*.exe" 2^>nul ^| findstr /v /i "console"') do if not defined G set "G=%%i"
  )
)

if not defined G (
  echo Could not find Godot 4. Paste the full path to your Godot .exe and press Enter:
  set /p G=
  set "G=!G:"=!"
)
if not exist "!G!" (
  echo "!G!" does not exist.
  pause
  exit /b 1
)
>".godot-path.txt" echo !G!

echo Starting Far Haul with !G!
start "" "!G!" --path "%~dp0"
