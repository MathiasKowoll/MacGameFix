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
  "$SRC/pe.c" "$SRC/setupapi.c" "$SRC/container.c" "$SRC/mmdevapi.c" "$SRC/endpoints.c" "$SRC/xaudio2.c"
/usr/bin/codesign -f -s - "$OUT/mgf-controls.dylib" 2>/dev/null
echo "built: $OUT/mgf-controls.dylib $(/usr/bin/shasum -a 256 "$OUT/mgf-controls.dylib" | cut -c1-8)"
[ "${MGVF_CONTROLS_CHECKS:-0}" = 1 ] || exit 0

# THE CHECKS (MGVF_CONTROLS_CHECKS=1), for the Windows side: Windows programs (controls/checks),
# run in a copy of the runner with CodeWeavers' own file for the module, without the library,
# where each has to fail, and with it. As build-engine.sh runs the engine's.
#   - checks/setupapi.c reads a device's base container id with the ANSI function: ANSI without
#     the library (exit 2), WCHAR with it, and another string still ANSI.
#     Then the same check with mgf-engine.dylib inserted before and after this library: both
#     take NtMapViewOfSection, and both have to be armed.
#   - checks/container.c stores a USB device's container as ntoskrnl does: as winebus.sys gave
#     it without the library (exit 2), the location's with it, and five others as given. No
#     module's file is put for it: the bus drivers are off here, and it is the write it checks.
#   - checks/mmdevapi.c asks every audio output for its container, with a stand-in for a
#     Bluetooth pad where the library looks for pads: no output has the pad's container
#     without the library (exit 2), one has it with it.
#   - checks/endpoints.c asks SetupAPI for the audio outputs, with the same stand-in: none has
#     the pad's container without the library (exit 2), one has it with it.
#   - checks/xaudio2.c names the stand-in's output to an XAudio2 mastering voice and counts the
#     voice's channels (the stand-in's has four, the Mac's own two): the default output's with
#     the xaudio2 part left out (exit 3), the named one's with it.
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
check() {  # <CodeWeavers' files to put, or -> <check> <the exit code without the library> [libraries the check links]
  local files="$1" name="$2" without="$3" rc file; shift 3
  if [ "$files" != - ]; then
    for file in $files; do cp "$STOCK/$file" "$WORK/runner/lib/wine/$file"; done
  fi
  x86_64-w64-mingw32-gcc -O1 -Wall -Werror -o "$WORK/$name.exe" "$SRC/checks/$name.c" "$@"
  rc=0; "$WINE" "$WORK/$name.exe" >/dev/null 2>&1 || rc=$?
  "$SERVER" -w
  if [ "$rc" != "$without" ]; then echo "  FAIL  $name without the library: exit $rc, not $without"; failed=1; fi
  rc=0; DYLD_INSERT_LIBRARIES="$OUT/mgf-controls.dylib" "$WINE" "$WORK/$name.exe" >/dev/null 2>&1 || rc=$?
  "$SERVER" -k 2>/dev/null || true; "$SERVER" -w 2>/dev/null || true
  if [ "$rc" != 0 ]; then echo "  FAIL  $name with the library: exit $rc"; failed=1; else echo "  ok    $name: fails without the library ($without), passes with it"; fi
}
# A check that the rest of the library lets pass half way: it has to fail with its own part
# left out (MGF_CONTROLS_WITHOUT), with the exit code given.
left_out() {  # <check, built by check> <the part> <the exit code without the part>
  local name="$1" part="$2" without="$3" rc=0
  MGF_CONTROLS_WITHOUT="$part" DYLD_INSERT_LIBRARIES="$OUT/mgf-controls.dylib" "$WINE" "$WORK/$name.exe" >/dev/null 2>&1 || rc=$?
  "$SERVER" -k 2>/dev/null || true; "$SERVER" -w 2>/dev/null || true
  if [ "$rc" != "$without" ]; then echo "  FAIL  $name with $part left out: exit $rc, not $without"; failed=1
  else echo "  ok    $name: fails with $part left out ($without)"; fi
}
check x86_64-windows/setupapi.dll setupapi 2 -lsetupapi
# With mgf-engine.dylib too, whose package-family takes the same syscall table entry as this
# library (NtMapViewOfSection): in either order both have to be armed (mgf_hooks.h).
together() {  # <the libraries, in the order they are inserted>
  local rc=0
  MGF_ENGINE_FIXES=package-family DYLD_INSERT_LIBRARIES="$1" "$WINE" "$WORK/setupapi.exe" >/dev/null 2>"$WORK/together.log" || rc=$?
  "$SERVER" -k 2>/dev/null || true; "$SERVER" -w 2>/dev/null || true
  if [ "$rc" != 0 ] || /usr/bin/grep -q 'not armed' "$WORK/together.log" || ! /usr/bin/grep -q 'FindPackagesByPackageFamily added' "$WORK/together.log"; then
    echo "  FAIL  together, $2: setupapi exit $rc; $(/usr/bin/grep -m1 'not armed' "$WORK/together.log")"; failed=1
  else echo "  ok    together, $2: both libraries armed"; fi
}
if [ -f "$HERE/mgf-engine.dylib" ]; then
  together "$HERE/mgf-engine.dylib:$OUT/mgf-controls.dylib" "mgf-engine first"
  together "$OUT/mgf-controls.dylib:$HERE/mgf-engine.dylib" "mgf-controls first"
fi
check - container 2 -lsetupapi
# The stand-in pad: a socket named as bt.c names a Bluetooth pad's, which the audio side lists, in
# a folder of the checks' own (MGF_CONTROLS_DIR): no game being played sees it. /tmp, as a
# socket's path has to be short.
export MGF_CONTROLS_DIR="/tmp/mgf-controls-check-$$"; mkdir -p "$MGF_CONTROLS_DIR"
trap '"$SERVER" -k 2>/dev/null || true; [ -z "${MGVF_KEEP_LOG:-}" ] || cp "$MGF_CONTROLS_DIR/pad.log" "$MGVF_KEEP_LOG" 2>/dev/null; rm -rf "$WORK" "$MGF_CONTROLS_DIR"' EXIT
STANDIN="$MGF_CONTROLS_DIR/pad-00c0ffee-0ce6-0ce6.sock"
/usr/bin/python3 -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM); s.bind(sys.argv[1]); time.sleep(300)' "$STANDIN" & standin=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$STANDIN" ] && break; /bin/sleep 0.2; done
check "x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so" mmdevapi 2 -lole32
check "x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so" endpoints 2 -lole32 -lsetupapi
check "x86_64-windows/xaudio2_9.dll" xaudio2 2 -lole32
left_out xaudio2 xaudio2 3
{ kill "$standin" && wait "$standin"; } 2>/dev/null || true
[ "$failed" = 0 ] || exit 1
