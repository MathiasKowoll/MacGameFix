#!/bin/bash
# Probes for patch 0026 (IPv4 options on a dual-stack socket).
#
#   /bin/bash engine/tests/dualstack-udp/run.sh
#   /bin/bash engine/tests/dualstack-udp/run.sh <CrossOver folder> [x86_64|arm64]
#
# Without arguments: dsprobe.c, built with the Mac's clang for arm64 and for x86_64 (Rosetta),
# checks what the kernel does (needs nothing but Xcode's command line tools).
# With the CrossOver folder of a NotProton runner (the one holding bin/ and lib/wine):
# udpopts.c, built with llvm-mingw (LLVM_MINGW, as build.sh), runs under that Wine's Intel
# side (x86_64, the default) or its FEX side (arm64), in a throwaway prefix. Without 0026 in
# that side's ntdll.so it fails 8 checks; with it, none.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ $# -eq 0 ]; then
  for arch in arm64 x86_64; do
    /usr/bin/clang -arch "$arch" -std=c99 -Wall -Wextra -Werror -o "$work/dsprobe-$arch" "$here/dsprobe.c"
    echo "==> dsprobe ($arch)"
    "$work/dsprobe-$arch"
  done
  exit 0
fi

crossover="$1"; side="${2:-x86_64}"
case "$side" in
x86_64) wine="$crossover/lib/wine/x86_64-unix/wine"; wineserver="$crossover/bin/wineserver-x86" ;;
arm64)  wine="$crossover/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine"; wineserver="$crossover/bin/wineserver-arm64" ;;
*) echo "unknown side $side (x86_64 or arm64)"; exit 2 ;;
esac
[ -x "$wine" ] && [ -x "$wineserver" ] || { echo "no $side Wine in $crossover"; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || { echo "llvm-mingw not found at $LLVM_MINGW (set LLVM_MINGW)"; exit 1; }

"$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra -Werror -o "$work/udpopts.exe" "$here/udpopts.c" -lws2_32
echo "==> udpopts.exe on $side ($(shasum -a 256 "$crossover/lib/wine/${side/arm64/aarch64}-unix/ntdll.so" | cut -c1-16) ntdll.so)"
status=0
WINEPREFIX="$work/prefix" WINESERVER="$wineserver" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
  "$wine" "$work/udpopts.exe" || status=$?
WINEPREFIX="$work/prefix" "$wineserver" -k 2>/dev/null || true
exit $status
