#!/bin/bash
# Probe for patch 0037 (TCP connections without TCP options, on request).
#
#   /bin/bash engine/tests/tcp-noopt/run.sh <CrossOver folder> [x86_64|arm64]
#   /bin/bash engine/tests/tcp-noopt/run.sh <CrossOver folder> --plugin <tcp-noopt.dylib>
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
#
# With --plugin it checks the Red Dead Online fix MacGameFix carries as a NotProton plugin
# (app/notproton-plugins/plugins/tcp-noopt.c, which Red Dead Redemption 2's fix switches on)
# instead, on the Intel side, under a runner whose ntdll.so has no 0037: the connection has
# timestamps, SACK and window scaling without the library, and none with it. The plugin leaves
# loopback connections alone, so these go to this Mac's own address on the network
# (MGVF_TCP_ADDR, else en0's or en1's), and it needs NotProton's plugin host
# (~/Library/Application Support/notproton/plugin-host.dylib).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; wineserver=true
trap 'WINEPREFIX="$work/c/pfx" "$wineserver" -k 2>/dev/null || true; rm -rf "$work"' EXIT

crossover="${1:?usage: run.sh <CrossOver folder> [x86_64|arm64] | --plugin <tcp-noopt.dylib>}"; side="${2:-x86_64}"
plugin=""; addr=""
if [ "$side" = --plugin ]; then
  plugin="${3:?--plugin needs the tcp-noopt.dylib to load}"; side=x86_64
  [ -f "$plugin" ] || { echo "no $plugin"; exit 1; }
  [ -f "$HOME/Library/Application Support/notproton/plugin-host.dylib" ] || { echo "no NotProton plugin host in ~/Library/Application Support/notproton"; exit 1; }
  addr="${MGVF_TCP_ADDR:-$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)}"
  [ -n "$addr" ] || { echo "no network address on en0 or en1 (set MGVF_TCP_ADDR)"; exit 1; }
fi
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
  exec 3< <(/usr/bin/python3 -I "$here/listen.py" ${addr:+"$addr"})
  local port got
  read -r port <&3
  env "$@" WINEPREFIX="$work/c/pfx" WINESERVER="$wineserver" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
    "$wine" "$work/tcpconnect.exe" "$port" ${addr:+"$addr"} || echo "  (tcpconnect.exe exit $?)"
  read -r got <&3 || got="no connection"
  exec 3<&-
  case "${got%% *}" in
    "$want") echo "  ok    $label: $got" ;;
    *) echo "  FAIL  $label: options $got, expected $want"; fail=1 ;;
  esac
}
if [ -n "$plugin" ]; then
  echo "    to $addr, the plugin $(shasum -a 256 "$plugin" | cut -c1-16)"
  probe ts,sack,wscale "without the plugin"
  probe none "with the plugin" DYLD_INSERT_LIBRARIES="$plugin"
  [ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
  exit 0
fi
probe ts,sack,wscale "nothing set"
probe none "WINE_TCP_NOOPT=1" WINE_TCP_NOOPT=1
touch "$work/c/notproton-tcp-noopt"
probe none "notproton-tcp-noopt beside the prefix"
probe ts,sack,wscale "the file and WINE_TCP_NOOPT=0" WINE_TCP_NOOPT=0
[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
