#!/bin/bash
# Test for patches 0028 and 0029 (a direct system call, or an exception, while the thread is being
# suspended).
#
#   /bin/bash engine/tests/direct-syscall-suspend/run.sh <CrossOver folder> [seconds] [step]
#
# The CrossOver folder is a NotProton runner's (the one holding bin/ and lib/wine). suspend.c,
# built with llvm-mingw (LLVM_MINGW, as build.sh), runs under that Wine's Intel side, which is
# the side Rosetta runs, in a throwaway prefix, for 20 seconds unless told otherwise, with msync
# and then without. Its header says what it does.
#
# Without 0028 in that side's ntdll.so it fails within a second or two: a look at a thread never
# returns from GetThreadContext, or direct system calls come back with their own number as the
# status. With 0028 and without 0029 the threads that raise exceptions stop, each ended by Wine
# with "nested exception on signal stack". With both, it passes. WINE_DIRECT_SYSCALL_DEFERRAL=0
# in the environment turns both off: it fails again.
#
# Intel side only: both are in signal_x86_64.c, which the FEX side's ntdll.so does not compile.
set -eu
[ $# -ge 1 ] || { sed -n '3,5p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
crossover="$1"; seconds="${2:-20}"; step="${3:-}"
wine="$crossover/lib/wine/x86_64-unix/wine"; wineserver="$crossover/bin/wineserver-x86"
[ -x "$wine" ] && [ -x "$wineserver" ] || { echo "no Intel-side Wine in $crossover"; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || { echo "llvm-mingw not found at $LLVM_MINGW (set LLVM_MINGW)"; exit 1; }
work="$(mktemp -d)"
trap 'WINEPREFIX="$work/prefix" "$wineserver" -k 2>/dev/null || true; rm -rf "$work"' EXIT

"$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra -Werror -o "$work/suspend.exe" "$here/suspend.c"
echo "==> suspend.exe on $(shasum -a 256 "$crossover/lib/wine/x86_64-unix/ntdll.so" | cut -c1-16) ntdll.so"
status=0
for msync in 1 0; do
  echo "==> WINEMSYNC=$msync, $seconds s"
  WINEPREFIX="$work/prefix" WINESERVER="$wineserver" WINEDEBUG=fixme-all,err-all,err+virtual WINEDLLOVERRIDES="mscoree,mshtml=" WINEMSYNC=$msync \
    "$wine" "$work/suspend.exe" "$seconds" $step &
  pid=$!
  # A thread lost to the defect spins for ever, and the process may not end by itself.
  ( sleep $((seconds + 60)); kill -9 $pid ) 2>/dev/null &
  watchdog=$!
  wait $pid || status=1
  kill $watchdog 2>/dev/null || true
  wait $watchdog 2>/dev/null || true
  # each pass gets a server of its own: started against the first pass's server, the second printed
  # nothing and failed
  WINEPREFIX="$work/prefix" "$wineserver" -k 2>/dev/null || true
  WINEPREFIX="$work/prefix" "$wineserver" -w 2>/dev/null || true
done
[ $status -eq 0 ] && echo "==> passed" || echo "==> FAILED"
exit $status
