#!/bin/bash
# Probe for patch 0037 (TCP connections without TCP options, on request).
#
#   /bin/bash engine/tests/tcp-noopt/run.sh <CrossOver folder> [x86_64|arm64]
#
# <CrossOver folder> is a NotProton runner's (the one holding bin/ and lib/wine). tcpconnect.c,
# built with llvm-mingw (LLVM_MINGW, as build.sh), connects to a listener on 127.0.0.1 under that
# Wine's Intel side (x86_64, the default) or its FEX side (arm64), in a throwaway prefix, and the
# listener reads which TCP options the connection uses. Four runs:
#   - nothing set: timestamps, SACK and window scaling, as macOS always does;
#   - WINE_TCP_NOOPT=1: none of them;
#   - NotProton's notproton-tcp-noopt file beside the prefix: none;
#   - the file and WINE_TCP_NOOPT=0: all three again.
# Without 0037 in that side's ntdll.so the second and third fail.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; wineserver=true
trap 'WINEPREFIX="$work/c/pfx" "$wineserver" -k 2>/dev/null || true; rm -rf "$work"' EXIT

crossover="${1:?usage: run.sh <CrossOver folder> [x86_64|arm64]}"; side="${2:-x86_64}"
case "$side" in
x86_64) wine="$crossover/lib/wine/x86_64-unix/wine"; wineserver="$crossover/bin/wineserver-x86" ;;
arm64)  wine="$crossover/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine"; wineserver="$crossover/bin/wineserver-arm64" ;;
*) echo "unknown side $side (x86_64 or arm64)"; exit 2 ;;
esac
[ -x "$wine" ] && [ -x "$wineserver" ] || { echo "no $side Wine in $crossover"; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || { echo "llvm-mingw not found at $LLVM_MINGW (set LLVM_MINGW)"; exit 1; }
"$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra -Werror -o "$work/tcpconnect.exe" "$here/tcpconnect.c" -lws2_32
echo "==> tcpconnect.exe on $side ($(shasum -a 256 "$crossover/lib/wine/${side/arm64/aarch64}-unix/ntdll.so" | cut -c1-16) ntdll.so)"
mkdir -p "$work/c"

fail=0
probe() { # <expected options> <label> [env assignments...]
  local want="$1" label="$2"; shift 2
  exec 3< <(/usr/bin/python3 -I "$here/listen.py")
  local port got
  read -r port <&3
  env "$@" WINEPREFIX="$work/c/pfx" WINESERVER="$wineserver" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
    "$wine" "$work/tcpconnect.exe" "$port" || echo "  (tcpconnect.exe exit $?)"
  read -r got <&3 || got="no connection"
  exec 3<&-
  case "${got%% *}" in
    "$want") echo "  ok    $label: $got" ;;
    *) echo "  FAIL  $label: options $got, expected $want"; fail=1 ;;
  esac
}
probe ts,sack,wscale "nothing set"
probe none "WINE_TCP_NOOPT=1" WINE_TCP_NOOPT=1
touch "$work/c/notproton-tcp-noopt"
probe none "notproton-tcp-noopt beside the prefix"
probe ts,sack,wscale "the file and WINE_TCP_NOOPT=0" WINE_TCP_NOOPT=0
[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
