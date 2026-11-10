#!/usr/bin/env bash
# Build the FH5 ws2_32 proxy from source against one CrossOver/NotProton ws2_32.dll.
#
#   build-fh5-netfix.sh /path/to/lib/wine/x86_64-windows/ws2_32.dll [output]
#
# The reference supplies the exact export names and ordinals. The result is a
# native proxy; at runtime ws2_o.dll is the renamed Wine builtin it forwards to.
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REFERENCE="${1:?usage: build-fh5-netfix.sh <Wine ws2_32.dll> [output DLL]}"
OUTPUT="${2:-$HERE/ws2_32-fh5.dll}"
[ -f "$REFERENCE" ] || { echo "error: no such ws2_32.dll: $REFERENCE" >&2; exit 1; }

MINGW_BIN="${MINGW_BIN:-$HOME/.local/cxge/toolchains/llvm-mingw/bin}"
CC=""
for candidate in "$MINGW_BIN/x86_64-w64-mingw32-clang" \
                 "$MINGW_BIN/x86_64-w64-mingw32-gcc" \
                 "$(command -v x86_64-w64-mingw32-clang 2>/dev/null || true)" \
                 "$(command -v x86_64-w64-mingw32-gcc 2>/dev/null || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && { CC="$candidate"; break; }
done
[ -n "$CC" ] || { echo "error: no x86_64-w64-mingw32 compiler found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DEF="$WORK/ws2_32.def"

{
  echo "LIBRARY ws2_32.dll"
  echo "EXPORTS"
  python3 "$HERE/pe.py" exports "$REFERENCE" --ordinals |
    while read -r ordinal symbol; do
      case "$symbol" in
        socket|WSASocketW|WSASocketA|WSAIoctl|setsockopt|closesocket)
          printf '    %s=wrap_%s @%s\n' "$symbol" "$symbol" "$ordinal" ;;
        *)
          printf '    %s=ws2_o.%s @%s\n' "$symbol" "$symbol" "$ordinal" ;;
      esac
    done
} > "$DEF"

count=$(($(wc -l < "$DEF") - 2))
[ "$count" -gt 0 ] || { echo "error: the reference exports nothing" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"
"$CC" -O2 -fno-builtin -fno-stack-protector -Wall -Wextra -Wno-cast-function-type \
  -shared -nostdlib -Wl,-e,DllMain -o "$OUTPUT" "$HERE/fh5-netfix.c" "$DEF" -lkernel32

got=$(python3 "$HERE/pe.py" exports "$OUTPUT" | wc -l | tr -d ' ')
[ "$got" = "$count" ] || { echo "error: built proxy exports $got symbols, expected $count" >&2; exit 1; }

echo "built $OUTPUT"
echo "  $count exports matched to $(basename "$REFERENCE")"
echo "  sha256 $(shasum -a 256 "$OUTPUT" | cut -d' ' -f1)"

