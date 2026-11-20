#!/bin/bash
# Build the pipeline cache plugin Phantom Blade Zero's fix installs into NotProton,
# fixes/notproton-rosetta-pipeline-cache.dylib, from pbz-pipeline-cache/.
#
#   build-pbz-pipeline-cache.sh            # the ad-hoc build, and its sha256
#   build-pbz-pipeline-cache.sh --sign     # also the Developer ID copy in fixes/
#
# The two sources are NotProton's experiments/fex-d3dmetal-bridge at 4c8b173 as they are
# (pbz-pipeline-cache/ORIGIN.md). Built as below, the ad-hoc universal file is byte-identical
# to the one that experiment's Makefile builds and that was played in PBZ on 2026-11-20:
# 389defc20850ff9fdc43cfc87b804f15c5243ef738202de559717bdd3229f1d6. The copy in fixes/ is that
# file signed with Developer ID, a timestamp and the hardened runtime, as MacGameFix
# distributes Mach-O files; its code is unchanged, which the script checks.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/pbz-pipeline-cache"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC/rosetta_pipeline_cache.mm" "$SRC/pipeline_cache.mm" "$WORK/"
cd "$WORK"
mkdir build
/usr/bin/clang++ -arch x86_64 -arch arm64 -std=c++17 -dynamiclib -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror -I. rosetta_pipeline_cache.mm pipeline_cache.mm -framework Foundation -framework Metal \
  -install_name @rpath/notproton-rosetta-pipeline-cache.dylib -o build/notproton-rosetta-pipeline-cache.dylib
shasum -a 256 build/notproton-rosetta-pipeline-cache.dylib
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/notproton-rosetta-pipeline-cache.dylib"
cp build/notproton-rosetta-pipeline-cache.dylib signed.dylib
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime signed.dylib
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t build/notproton-rosetta-pipeline-cache.dylib | sed 1d) \
         <(otool -arch "$arch" -t signed.dylib | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp signed.dylib "$OUT"
chmod 755 "$OUT"
shasum -a 256 "$OUT"
