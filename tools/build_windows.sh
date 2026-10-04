#!/usr/bin/env bash
# Builds the portable Windows exe: build/windows/FarHaul.exe, one file with the game packed inside.
#
# Needs: Godot 4.4.1 with its export templates, and go-winres (go install github.com/tc-hib/go-winres@latest)
# to put the Far Haul icon and name into the exe. Godot's own way to do that (Application > Modify Resources)
# needs rcedit, which needs Windows or Wine; this script patches a copy of the template instead.
# On Windows you can simply export "Windows Desktop" from the editor, with rcedit set in
# Editor Settings > Export > Windows if you want the icon.
#
# Usage: tools/build_windows.sh [path-to-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
TPL_DIR="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/4.4.1.stable}"
TPL="$TPL_DIR/windows_release_x86_64.exe"
[ -f "$TPL.orig" ] || cp "$TPL" "$TPL.orig"          # keep Godot's own template untouched beside it
cp "$TPL.orig" "$TPL"
(cd tools/winres && go-winres patch --in winres.json --no-backup "$TPL")
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/FarHaul.exe
ls -l build/windows/FarHaul.exe
