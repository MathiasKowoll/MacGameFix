#!/bin/bash
# Build the library F1 25's fix installs into NotProton, fixes/mgf-low-allocations.dylib, from
# low-allocations/.
#
#   build-low-allocations.sh            # the ad-hoc build and its sha256
#   build-low-allocations.sh --sign     # also the Developer ID copy in fixes/
#
# low-allocations/mgf-low-allocations.c says what the library does and why. It is built as
# NotProton builds its plugins (its Makefile's flags, as build-app.sh builds the plugins the app
# carries): both architectures, so a game under Rosetta or FEX loads it. It acts only through
# NotProton's plugin host, inside a game's process, so there is no check to run here: it was
# played (see the source).
#
# The copy in fixes/ is the build signed with Developer ID, a timestamp and the hardened
# runtime, as MacGameFix distributes Mach-O files; its code is unchanged, which the script checks.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
/usr/bin/clang -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -Werror=unguarded-availability-new -std=c17 \
  -dynamiclib -O2 -Wall -Wextra -Werror -install_name @rpath/mgf-low-allocations.dylib \
  -o "$WORK/mgf-low-allocations.dylib" "$HERE/low-allocations/mgf-low-allocations.c"
/usr/bin/codesign -f -s - "$WORK/mgf-low-allocations.dylib" 2>/dev/null
shasum -a 256 "$WORK/mgf-low-allocations.dylib"
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/mgf-low-allocations.dylib"
cp "$WORK/mgf-low-allocations.dylib" "$WORK/signed.dylib"
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime "$WORK/signed.dylib"
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t "$WORK/mgf-low-allocations.dylib" | sed 1d) \
         <(otool -arch "$arch" -t "$WORK/signed.dylib" | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp "$WORK/signed.dylib" "$OUT"
chmod 755 "$OUT"
shasum -a 256 "$OUT"
