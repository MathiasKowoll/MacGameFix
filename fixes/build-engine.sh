#!/bin/bash
# Build MacGameFix's engine fixes for NotProton, fixes/mgf-engine.dylib, from engine/, and run
# their checks.
#
#   build-engine.sh            # the ad-hoc build, the checks and its sha256
#   build-engine.sh --sign     # also the Developer ID copy in fixes/
#
# engine/mgf-engine.c says what the library is: one library, loaded by one NotProton row, that
# arms each game's fixes in that game alone. Each fix's source says what it does. It is built as
# NotProton builds its plugins (its Makefile's flags, as build-app.sh builds the plugins the app
# carries): both architectures, so a game under Rosetta or FEX loads it.
#
# THE CHECKS are Windows programs, built with mingw-w64 and run in a throwaway prefix under a
# copy of a NotProton runner whose ntdll.so, ntdll.dll, kernel32.dll and kernelbase.dll are
# CodeWeavers' own, so none of the engine patches the fixes stand in for is there:
#   - package-family/check.c looks FindPackagesByPackageFamily up in kernel32 and calls it: not
#     found without the fix, found and answering no packages with it, and kernel32's forwards to
#     ntdll and kernelbase still resolving;
#   - timer-overflow/check.c makes a threadpool timer, sets none, and measures its CPU time
#     while it sleeps 3 s: the timer thread spins without the fix, and is still with it.
#   - dualstack-ipv4/check.c sets IP_DONTFRAGMENT and IP_TTL on a dual-stack UDP socket, as
#     Forza Horizon 6 does with its game socket, and reads them back: WSAEINVAL without the fix,
#     and 200 from both IP_TTL and IPV6_UNICAST_HOPS with it;
#   - rosetta-cpu/check.c reads CPUID leaf 7 and runs CLWB, RDPID and a non-canonical read: the
#     leaf lacks the bits without the fix; with it they are there, both instructions run and the
#     read faults at -1 as on Windows. With it, it also arms execution breakpoints (Dr0, Dr7) as
#     Denuvo does, on a ud2 from that fault's handler and on a function through SetThreadContext,
#     and each has to stop the thread with the debug exception;
#   - direct-syscall runs engine/tests/direct-syscall-suspend/suspend.c (built with llvm-mingw,
#     LLVM_MINGW): threads making system calls with a syscall instruction of their own and threads
#     raising exceptions, while another suspends them. Without the fix a look at a thread never
#     returns, a call comes back with its own number, or Wine ends a thread; with it, none.
# Each runs without the library, where it has to fail (a check that passes either way tests
# nothing), and with it, the fix named by MGF_ENGINE_FIXES. low-allocations and once-reentry have
# no check of their own: they are played (see their sources). d3dmetal-hookable's check (d3dmetal-hookable/check.c, an
# x86_64 program under Rosetta, no Wine) runs with this library, the fix named the same way;
# build-d3dmetal-hookable.sh runs it without, where it has to fault.
# The runner is MGVF_CHECK_RUNNER (the 41303 runner by default); CodeWeavers' files come from
# MGVF_CHECK_STOCK (MacGameFix's backup of CrossOver Preview 41303's own by default). Without
# either, or without mingw, the checks are skipped and the script says so.
#
# The copy in fixes/ is the build signed with Developer ID, a timestamp and the hardened
# runtime, as MacGameFix distributes Mach-O files; its code is unchanged, which the script checks.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/engine"
WORK="$(mktemp -d)"
cleanup() { [ -z "${SERVER:-}" ] || WINEPREFIX="$WORK/pfx" "$SERVER" -k 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
/usr/bin/clang -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -Werror=unguarded-availability-new -std=c17 \
  -dynamiclib -O2 -Wall -Wextra -Werror -install_name @rpath/mgf-engine.dylib -o "$WORK/mgf-engine.dylib" \
  "$SRC/mgf-engine.c" "$SRC/low-allocations/mgf-low-allocations.c" "$SRC/package-family/mgf-package-family.c" \
  "$SRC/timer-overflow/mgf-timer-overflow.c" "$SRC/dualstack-ipv4/mgf-dualstack-ipv4.c" \
  "$SRC/rosetta-cpu/mgf-rosetta-cpu.c" "$SRC/direct-syscall/mgf-direct-syscall.c" "$SRC/once-reentry/mgf-once-reentry.c" "$SRC/mgf-signals.c" -DMGF_ENGINE "$HERE/d3dmetal-hookable/mgf-d3dmetal-hookable.c"
/usr/bin/codesign -f -s - "$WORK/mgf-engine.dylib" 2>/dev/null

RUNNER="${MGVF_CHECK_RUNNER:-$HOME/Library/Application Support/notproton/runners/crossover-27.0.0.41303-fex/CrossOver}"
STOCK="${MGVF_CHECK_STOCK:-$HOME/Library/Application Support/MacGameFix/engine-backup/CrossOver Preview.app-27.0.0.41303}"
if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
  echo "note: no x86_64-w64-mingw32-gcc, the checks are skipped"
elif [ ! -x "$RUNNER/lib/wine/x86_64-unix/wine" ]; then
  echo "note: no runner at $RUNNER (MGVF_CHECK_RUNNER), the checks are skipped"
elif [ ! -f "$STOCK/x86_64-unix/ntdll.so" ]; then
  echo "note: no CodeWeavers ntdll.so in $STOCK (MGVF_CHECK_STOCK), the checks are skipped"
else
  # The runner, cloned (APFS), with CodeWeavers' own files where the engine patches go.
  cp -cR "$RUNNER" "$WORK/runner"
  cp "$STOCK/x86_64-unix/ntdll.so" "$WORK/runner/lib/wine/x86_64-unix/ntdll.so"
  for f in ntdll.dll kernel32.dll kernelbase.dll; do
    [ ! -f "$STOCK/x86_64-windows/$f" ] || cp "$STOCK/x86_64-windows/$f" "$WORK/runner/lib/wine/x86_64-windows/$f"
  done
  WINE="$WORK/runner/lib/wine/x86_64-unix/wine"
  SERVER="$WORK/runner/bin/wineserver"; [ -x "$SERVER" ] || SERVER="$WORK/runner/bin/wineserver-x86"
  export WINEPREFIX="$WORK/pfx" WINEDEBUG=-all WINELOADER="$WINE" WINESERVER="$SERVER"
  "$WINE" wineboot -i >/dev/null 2>&1
  "$SERVER" -w
  check() {  # <fix> <the exit code without it> [libraries the check links]
    local fix="$1" without="$2" rc
    x86_64-w64-mingw32-gcc -O1 -Wall -Werror -o "$WORK/$fix.exe" "$SRC/$fix/check.c" "${@:3}"
    echo "== $fix, without the library: it has to fail"
    rc=0; "$WINE" "$WORK/$fix.exe" || rc=$?
    "$SERVER" -w
    [ "$rc" = "$without" ] || { echo "$fix: without the library the check ended with $rc, not $without: the runner may carry the engine patch, so the check would test nothing" >&2; exit 1; }
    echo "== $fix, with it"
    rc=0; MGF_ENGINE_FIXES="$fix" DYLD_INSERT_LIBRARIES="$WORK/mgf-engine.dylib" "$WINE" "$WORK/$fix.exe" 2>/dev/null || rc=$?
    "$SERVER" -w
    [ "$rc" = 0 ] || { echo "$fix: with the library the check ended with $rc" >&2; exit 1; }
  }
  check package-family 2
  check timer-overflow 3
  check dualstack-ipv4 2 -lws2_32
  check rosetta-cpu 2
  # suspend.c can hang for good without the fix: a watchdog ends it, and that is its failure.
  LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
  if [ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ]; then
    "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra -Werror -o "$WORK/suspend.exe" "$HERE/../engine/tests/direct-syscall-suspend/suspend.c"
    suspend_run() {  # <environment...>: the exit code, 9 when the watchdog ended it
      local pid dog rc=0
      env "$@" WINEMSYNC=1 "$WINE" "$WORK/suspend.exe" 8 >"$WORK/suspend.log" 2>&1 & pid=$!
      ( sleep 60; kill -9 $pid ) 2>/dev/null & dog=$!
      wait $pid || rc=$?
      kill $dog 2>/dev/null || true; wait $dog 2>/dev/null || true
      "$SERVER" -k 2>/dev/null || true; "$SERVER" -w 2>/dev/null || true
      [ "$rc" -lt 128 ] || rc=9
      echo "$rc"
    }
    echo "== direct-syscall, without the library: it has to fail"
    rc="$(suspend_run MGF_ENGINE_FIXES=none)"; tail -3 "$WORK/suspend.log"
    [ "$rc" != 0 ] || { echo "direct-syscall: without the library suspend.exe passed: the runner may carry 0028, so the check would test nothing" >&2; exit 1; }
    echo "== direct-syscall, with it"
    rc="$(suspend_run MGF_ENGINE_FIXES=direct-syscall DYLD_INSERT_LIBRARIES="$WORK/mgf-engine.dylib")"; tail -3 "$WORK/suspend.log"
    [ "$rc" = 0 ] || { echo "direct-syscall: with the library suspend.exe ended with $rc" >&2; exit 1; }
  else
    echo "note: no llvm-mingw at $LLVM_MINGW (LLVM_MINGW), the direct-syscall check is skipped"
  fi
fi
echo "== d3dmetal-hookable, with the library"
/usr/bin/clang -arch x86_64 -O1 -mmacosx-version-min=14.0 -Wall -Wextra -Werror "$HERE/d3dmetal-hookable/check.c" -o "$WORK/hookable-check"
MGF_ENGINE_FIXES=d3dmetal-hookable MGF_D3DM_HOOKABLE_TEST=1 MGF_D3DM_HOOKABLE_LOG=/dev/null \
  DYLD_INSERT_LIBRARIES="$WORK/mgf-engine.dylib" "$WORK/hookable-check"
shasum -a 256 "$WORK/mgf-engine.dylib"
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/mgf-engine.dylib"
cp "$WORK/mgf-engine.dylib" "$WORK/signed.dylib"
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime "$WORK/signed.dylib"
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t "$WORK/mgf-engine.dylib" | sed 1d) \
         <(otool -arch "$arch" -t "$WORK/signed.dylib" | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp "$WORK/signed.dylib" "$OUT"
chmod 755 "$OUT"
shasum -a 256 "$OUT"
