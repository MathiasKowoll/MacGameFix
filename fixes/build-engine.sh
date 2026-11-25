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
# Each runs without the library, where it has to fail (a check that passes either way tests
# nothing), and with it, the fix named by MGF_ENGINE_FIXES. low-allocations has no check of its
# own: it was played (see its source).
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
  "$SRC/timer-overflow/mgf-timer-overflow.c"
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
  check() {  # <fix> <the exit code without it>
    local fix="$1" without="$2" rc
    x86_64-w64-mingw32-gcc -O1 -Wall -Werror -o "$WORK/$fix.exe" "$SRC/$fix/check.c"
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
fi
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
