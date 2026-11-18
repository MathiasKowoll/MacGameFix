#!/bin/bash
# What a CrossOver's Wine shows a game of the pad that is connected: its HID interfaces with
# their container (read with the W and the ANSI function, patch 0010), the XInput slots, and
# the audio render endpoints with their container (0002, 0003, 0005, 0009).
#
#   /bin/bash engine/tests/pad-probe/run.sh <CrossOver folder>
#
# The folder is the one holding bin/ and lib/wine, of a NotProton runner or a copy of one.
# padprobe.c is built with llvm-mingw (LLVM_MINGW, as build.sh) and runs under that Wine's
# Intel side in a throwaway prefix. It decides nothing: read what it prints. With the
# modules in and a DualSense connected on Bluetooth (shown as on a cable, the default), the
# pad is a HID interface whose container is {<location>-27F2-4948-9654-152804AF6378}, both
# functions give that string, an XInput slot is connected (XInput's vibration on, the
# default) and one audio endpoint has the same container. Quit that CrossOver's games first:
# the probe opens the pad.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 <CrossOver folder>"; exit 2; }
crossover="$1"
wine="$crossover/lib/wine/x86_64-unix/wine"
wineserver="$crossover/bin/wineserver"; [ -x "$wineserver" ] || wineserver="$crossover/bin/wineserver-x86"
[ -x "$wine" ] && [ -x "$wineserver" ] || { echo "no Intel-side Wine in $crossover"; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || { echo "llvm-mingw not found at $LLVM_MINGW (set LLVM_MINGW)"; exit 1; }
work="$(mktemp -d)"
trap 'WINEPREFIX="$work/prefix" "$wineserver" -k 2>/dev/null || true; rm -rf "$work"' EXIT

"$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" -O2 -Wall -o "$work/padprobe.exe" "$here/padprobe.c" \
  -lsetupapi -lhid -lxinput -lole32 -luuid
status=0
WINEPREFIX="$work/prefix" WINESERVER="$wineserver" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
  "$wine" "$work/padprobe.exe" || status=$?
exit $status
