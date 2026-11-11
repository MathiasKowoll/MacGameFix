#!/usr/bin/env bash
# Build the Forza Horizon 6 D3DMetal compatibility proxy from the shared GPL source.
#
#   build-fh6-d3d12.sh [output DLL]
#
# FH6 uses the common D3DMetal fixes but deliberately omits FH5's descriptor
# stride and unwind containment layers.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/fh6-d3d12"
OUTPUT="${1:-$HERE/d3d12-fh6.dll}"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Build under the name Wine will load. The PE/PDB metadata otherwise embeds
# the distribution filename and makes the semantic rebuild check report drift.
"$CC" -shared -O2 -Wall -static-libgcc -DMGF_FH6_PROFILE=1 \
  -o "$WORK/d3d12.dll" \
  "$SRC/d3d12.c" "$SRC/dxil_shadingrate.c" "$SRC/inspect.c" "$SRC/d3d12.def"
mv -f "$WORK/d3d12.dll" "$OUTPUT"

shasum -a 256 "$OUTPUT"
perl "$HERE/pe.pl" exports "$OUTPUT" --ordinals
