#!/bin/bash
# Host test of the DualShock 4 translations (pad_as=dualshock4). Patch 0013 is
# the only copy of dualshock4.h: this takes the header out of it, builds
# dualshock4_test.c against it with the Mac's own clang and runs it.
#
#   /bin/bash engine/tests/dualshock4/run.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
patch_file="$here/../../patches/wine-11.17/0013-winebus-dualshock4.patch"
[ -f "$patch_file" ] || { echo "no $patch_file"; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The new file's hunk: every line after its +++ header that the patch adds.
awk '
  /^\+\+\+ b\/dlls\/winebus\.sys\/dualshock4\.h$/ { on = 1; next }
  on && /^--- / { on = 0 }
  on && /^@@ / { next }
  on && /^\+/ { print substr($0, 2) }
' "$patch_file" >"$work/dualshock4.h"
[ -s "$work/dualshock4.h" ] || { echo "dualshock4.h not found in $patch_file"; exit 1; }

/usr/bin/clang -std=c99 -Wall -Wextra -Werror -I"$work" -o "$work/dualshock4_test" "$here/dualshock4_test.c"
"$work/dualshock4_test"
