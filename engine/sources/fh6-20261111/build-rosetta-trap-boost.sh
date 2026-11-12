#!/bin/bash
# Build the Rosetta priority plugin FH6's improvement installs, fixes/notproton-rosetta-trap-boost.dylib,
# from rosetta-trap-boost.c and faultcount.h beside this script.
#
#   build-rosetta-trap-boost.sh            # the ad-hoc build, and its sha256
#   build-rosetta-trap-boost.sh --sign     # also the Developer ID copy in fixes/
#
# It is the quiet build (MGF_RBOOST_TELEMETRY=0): the priority policy and the per-thread SIGILL
# counts it needs, without the reporting-only syscall interposition, the fault-page listing, the
# thread census and the Wine debug redirection. Built as below, in a folder whose output names are
# artifacts/quiet-<arch>.dylib (they are the install names), the ad-hoc universal file is
# byte-identical to the one played on 2026-11-11: 882d6a31ff083c1478559c002447b58c4cb96eb855af8c4683511c2f4651d0f7.
# The copy in fixes/ is that file signed with Developer ID, a timestamp and the hardened runtime,
# as MacGameFix distributes Mach-O files; its code is unchanged.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/source" "$WORK/artifacts"
cp "$HERE/rosetta-trap-boost.c" "$HERE/faultcount.h" "$WORK/source/"
cd "$WORK"
for arch in x86_64 arm64; do
  /usr/bin/clang -arch "$arch" -O2 -Wall -Wextra -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter \
    -mmacosx-version-min=14.0 -dynamiclib -DMGF_RBOOST_TELEMETRY=0 source/rosetta-trap-boost.c -o "artifacts/quiet-$arch.dylib"
done
/usr/bin/lipo -create artifacts/quiet-x86_64.dylib artifacts/quiet-arm64.dylib -output artifacts/notproton-rosetta-trap-boost-quiet.dylib
/usr/bin/codesign -f -s - artifacts/notproton-rosetta-trap-boost-quiet.dylib 2>/dev/null
shasum -a 256 artifacts/notproton-rosetta-trap-boost-quiet.dylib
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/../../../fixes/notproton-rosetta-trap-boost.dylib"
cp artifacts/notproton-rosetta-trap-boost-quiet.dylib "$WORK/signed.dylib"
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime "$WORK/signed.dylib"
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t artifacts/notproton-rosetta-trap-boost-quiet.dylib | sed 1d) \
         <(otool -arch "$arch" -t "$WORK/signed.dylib" | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp "$WORK/signed.dylib" "$OUT"
shasum -a 256 "$OUT"
