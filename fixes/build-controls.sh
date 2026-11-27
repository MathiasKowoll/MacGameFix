#!/bin/bash
# Builds mgf-controls.dylib, the DualSense controls as a NotProton plugin (controls/mgf-controls.c),
# both sides (x86_64 for Rosetta, arm64 for FEX), ad hoc; tools/sign-payload.sh signs it before it
# is committed.
#
#   build-controls.sh [<out folder>]   # default: beside this script
#   MGVF_CONTROLS_CHECKS=1 build-controls.sh [<out folder>]   # and run the Windows side's checks
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/controls"
OUT="${1:-$HERE}"
/usr/bin/clang -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -Werror=unguarded-availability-new -std=c17 \
  -dynamiclib -O2 -Wall -Wextra -Werror -install_name @rpath/mgf-controls.dylib \
  -framework IOKit -framework CoreFoundation -framework CoreAudio -framework AudioToolbox -o "$OUT/mgf-controls.dylib" \
  "$SRC/mgf-controls.c" "$SRC/bus.c" "$SRC/bt.c" "$SRC/triggers.c" "$SRC/audio.c" "$SRC/pad.c" \
  "$SRC/pe.c" "$SRC/setupapi.c"
/usr/bin/codesign -f -s - "$OUT/mgf-controls.dylib" 2>/dev/null
echo "built: $OUT/mgf-controls.dylib $(/usr/bin/shasum -a 256 "$OUT/mgf-controls.dylib" | cut -c1-8)"
[ "${MGVF_CONTROLS_CHECKS:-0}" = 1 ] || exit 0

# THE CHECKS (MGVF_CONTROLS_CHECKS=1), for the Windows side: Windows programs (controls/checks),
# run in a copy of the runner with CodeWeavers' own file for the module, without the library,
# where each has to fail, and with it. As build-engine.sh runs the engine's.
#   - checks/setupapi.c reads a device's base container id with the ANSI function: ANSI without
#     the library (exit 2), WCHAR with it, and another string still ANSI.
RUNNER="${MGVF_CHECK_RUNNER:-$HOME/Library/Application Support/notproton/runners/crossover-27.0.0.41303-fex/CrossOver}"
STOCK="${MGVF_CHECK_STOCK:-$HOME/Library/Application Support/MacGameFix/engine-backup/crossover-27.0.0.41303-fex}"
if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then echo "note: no x86_64-w64-mingw32-gcc, the checks are skipped"; exit 0; fi
if [ ! -x "$RUNNER/lib/wine/x86_64-unix/wine" ]; then echo "note: no runner at $RUNNER (MGVF_CHECK_RUNNER), the checks are skipped"; exit 0; fi
if [ ! -f "$STOCK/x86_64-windows/setupapi.dll" ]; then echo "note: no CodeWeavers setupapi.dll in $STOCK (MGVF_CHECK_STOCK), the checks are skipped"; exit 0; fi
WORK="$(mktemp -d)"
cp -cR "$RUNNER" "$WORK/runner"
WINE="$WORK/runner/lib/wine/x86_64-unix/wine"
SERVER="$WORK/runner/bin/wineserver"; [ -x "$SERVER" ] || SERVER="$WORK/runner/bin/wineserver-x86"
# No bus drivers: a check prefix that opened the HID devices would seize a controller the
# player is using in a game at the time, and start a second writer to it (2026-11-26).
export WINEDLLOVERRIDES="winebus.sys,winebth.sys,wineusb.sys=d"
export WINEPREFIX="$WORK/pfx" WINEDEBUG=-all WINELOADER="$WINE" WINESERVER="$SERVER"
trap '"$SERVER" -k 2>/dev/null || true; rm -rf "$WORK"' EXIT
"$WINE" wineboot -i >/dev/null 2>&1
"$SERVER" -w
failed=0
check() {  # <module's file> <check> <the exit code without the library> [libraries the check links]
  local file="$1" name="$2" without="$3" rc; shift 3
  cp "$STOCK/x86_64-windows/$file" "$WORK/runner/lib/wine/x86_64-windows/$file"
  x86_64-w64-mingw32-gcc -O1 -Wall -Werror -o "$WORK/$name.exe" "$SRC/checks/$name.c" "$@"
  rc=0; "$WINE" "$WORK/$name.exe" >/dev/null 2>&1 || rc=$?
  "$SERVER" -w
  if [ "$rc" != "$without" ]; then echo "  FAIL  $name without the library: exit $rc, not $without"; failed=1; fi
  rc=0; DYLD_INSERT_LIBRARIES="$OUT/mgf-controls.dylib" "$WINE" "$WORK/$name.exe" >/dev/null 2>&1 || rc=$?
  "$SERVER" -k 2>/dev/null || true; "$SERVER" -w 2>/dev/null || true
  if [ "$rc" != 0 ]; then echo "  FAIL  $name with the library: exit $rc"; failed=1; else echo "  ok    $name: fails without the library ($without), passes with it"; fi
}
check setupapi.dll setupapi 2 -lsetupapi
[ "$failed" = 0 ] || exit 1
