#!/bin/bash
# Builds mgf-controls.dylib, the DualSense controls as a NotProton plugin (controls/mgf-controls.c),
# both sides (x86_64 for Rosetta, arm64 for FEX), ad hoc; tools/sign-payload.sh signs it before it
# is committed.
#
#   build-controls.sh [<out folder>]   # default: beside this script
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
  "$SRC/mgf-controls.c" "$SRC/bus.c" "$SRC/bt.c" "$SRC/triggers.c" "$SRC/audio.c" "$SRC/pad.c"
/usr/bin/codesign -f -s - "$OUT/mgf-controls.dylib" 2>/dev/null
echo "built: $OUT/mgf-controls.dylib $(/usr/bin/shasum -a 256 "$OUT/mgf-controls.dylib" | cut -c1-8)"
