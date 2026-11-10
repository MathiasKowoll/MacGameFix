#!/usr/bin/env bash
# Build the Forza Horizon 5 D3DMetal compatibility proxy from its GPL source.
#
#   build-fh5-d3d12.sh [output DLL]
#
# Needs an x86_64-w64-mingw32 GCC or Clang toolchain. The shipped payload is
# rebuilt by check-builds.sh; this script is for maintainers, not players.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/fh5-d3d12"
OUTPUT="${1:-$HERE/d3d12-fh5.dll}"
CC="${MGVF_MINGW_CC:-}"

if [ -z "$CC" ]; then
  for candidate in \
    "$HOME/.local/cxge/toolchains/llvm-mingw/bin/x86_64-w64-mingw32-clang" \
    x86_64-w64-mingw32-clang x86_64-w64-mingw32-gcc; do
    if [[ "$candidate" = */* ]]; then
      [ -x "$candidate" ] && { CC="$candidate"; break; }
    elif command -v "$candidate" >/dev/null 2>&1; then
      CC="$candidate"; break
    fi
  done
fi
[ -n "$CC" ] || {
  echo "error: no x86_64-w64-mingw32 C compiler found" >&2
  exit 1
}

"$CC" -shared -O2 -Wall -static-libgcc \
  -o "$OUTPUT" \
  "$SRC/d3d12.c" "$SRC/dxil_shadingrate.c" "$SRC/inspect.c" "$SRC/d3d12.def"

shasum -a 256 "$OUTPUT"
perl "$HERE/pe.pl" exports "$OUTPUT" --ordinals
