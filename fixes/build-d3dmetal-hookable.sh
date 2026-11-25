#!/bin/bash
# Build d3dmetal-hookable/ on its own and run its check, with it and without it. What ships is
# the same source inside mgf-engine.dylib (build-engine.sh), which starts it in EA SPORTS FC 27;
# --sign still writes a signed copy, fixes/mgf-d3dmetal-hookable.dylib, which nothing installs.
#
#   build-d3dmetal-hookable.sh            # the ad-hoc build, its check and its sha256
#   build-d3dmetal-hookable.sh --sign     # also the Developer ID copy in fixes/
#
# d3dmetal-hookable/mgf-d3dmetal-hookable.c says what the library does and why. The check
# (d3dmetal-hookable/check.c) is an x86_64 program, so it runs under Rosetta as a game does: a
# stub of D3DMetal's shape, rewritten while another thread calls it, then hooked the way the
# overlay that crashed hooks. The same program without the library faults on that hook, which
# the script also asks for: a check that passes either way would say nothing.
#
# The copy in fixes/ is the build signed with Developer ID, a timestamp and the hardened
# runtime, as MacGameFix distributes Mach-O files; its code is unchanged, which the script checks.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/d3dmetal-hookable"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC/mgf-d3dmetal-hookable.c" "$SRC/check.c" "$WORK/"
cd "$WORK"
mkdir build
/usr/bin/clang -arch x86_64 -arch arm64 -O2 -dynamiclib -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
  mgf-d3dmetal-hookable.c -install_name @rpath/mgf-d3dmetal-hookable.dylib -o build/mgf-d3dmetal-hookable.dylib
/usr/bin/codesign -f -s - build/mgf-d3dmetal-hookable.dylib 2>/dev/null
/usr/bin/clang -arch x86_64 -O1 -mmacosx-version-min=14.0 -Wall -Wextra -Werror check.c -o check
echo "== the check, with the library"
MGF_D3DM_HOOKABLE_TEST=1 MGF_D3DM_HOOKABLE_LOG=/dev/null DYLD_INSERT_LIBRARIES="$WORK/build/mgf-d3dmetal-hookable.dylib" ./check
echo "== and without it: the hook has to fault"
if ( ./check > without.txt 2>&1 ) 2>/dev/null; then echo "the check passes without the library: it tests nothing" >&2; exit 1; fi
/usr/bin/grep -q 'FAIL: the stub was not rewritten' without.txt || { cat without.txt >&2; echo "without the library the check ended some other way" >&2; exit 1; }
echo "ok: without the library the stub stays as it was and the hook does not survive"
shasum -a 256 build/mgf-d3dmetal-hookable.dylib
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/mgf-d3dmetal-hookable.dylib"
cp build/mgf-d3dmetal-hookable.dylib signed.dylib
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime signed.dylib
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t build/mgf-d3dmetal-hookable.dylib | sed 1d) \
         <(otool -arch "$arch" -t signed.dylib | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp signed.dylib "$OUT"
chmod 755 "$OUT"
shasum -a 256 "$OUT"
