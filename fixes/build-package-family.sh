#!/bin/bash
# Build the library EA SPORTS FC 27's fix installs into NotProton, fixes/mgf-package-family.dylib,
# from package-family/, and run its check.
#
#   build-package-family.sh            # the ad-hoc build, its check and its sha256
#   build-package-family.sh --sign     # also the Developer ID copy in fixes/
#
# package-family/mgf-package-family.c says what the library does and why. It is built as
# NotProton builds its plugins (its Makefile's flags, as build-app.sh builds the plugins the app
# carries): both architectures, so a game under Rosetta or FEX loads it.
#
# The check (package-family/check.c) is a Windows program, built with mingw-w64, run in a
# throwaway prefix under a NotProton runner whose kernel32.dll lacks the function (CrossOver's
# own): without the library it has to say the function is not found, with it the function has
# to be found and answer no packages, and kernel32's forwards to ntdll and kernelbase still have
# to resolve. MGVF_CHECK_RUNNER names the runner's CrossOver folder; without a runner or mingw
# the check is skipped, and the script says so.
#
# The copy in fixes/ is the build signed with Developer ID, a timestamp and the hardened
# runtime, as MacGameFix distributes Mach-O files; its code is unchanged, which the script checks.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
/usr/bin/clang -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -Werror=unguarded-availability-new -std=c17 \
  -dynamiclib -O2 -Wall -Wextra -Werror -install_name @rpath/mgf-package-family.dylib \
  -o "$WORK/mgf-package-family.dylib" "$HERE/package-family/mgf-package-family.c"
/usr/bin/codesign -f -s - "$WORK/mgf-package-family.dylib" 2>/dev/null

RUNNER="${MGVF_CHECK_RUNNER:-$HOME/Library/Application Support/notproton/runners/crossover-27.0.0.41303-fex/CrossOver}"
WINE="$RUNNER/lib/wine/x86_64-unix/wine"
SERVER="$RUNNER/bin/wineserver"; [ -x "$SERVER" ] || SERVER="$RUNNER/bin/wineserver-x86"
if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
  echo "note: no x86_64-w64-mingw32-gcc, the check is skipped"
elif [ ! -x "$WINE" ] || [ ! -x "$SERVER" ]; then
  echo "note: no runner at $RUNNER (MGVF_CHECK_RUNNER), the check is skipped"
else
  x86_64-w64-mingw32-gcc -O1 -Wall -Werror -o "$WORK/check.exe" "$HERE/package-family/check.c"
  export WINEPREFIX="$WORK/pfx" WINEDEBUG=-all WINELOADER="$WINE" WINESERVER="$SERVER"
  "$WINE" wineboot -i >/dev/null 2>&1
  "$SERVER" -w
  echo "== the check, without the library: the function has to be missing"
  rc=0; "$WINE" "$WORK/check.exe" || rc=$?
  "$SERVER" -w
  [ "$rc" = 2 ] || { echo "without the library the check ended with $rc, not 2: the runner's kernel32.dll may have the function, so the check would test nothing" >&2; exit 1; }
  echo "== and with it"
  rc=0; DYLD_INSERT_LIBRARIES="$WORK/mgf-package-family.dylib" "$WINE" "$WORK/check.exe" 2>/dev/null || rc=$?
  "$SERVER" -w
  [ "$rc" = 0 ] || { echo "with the library the check ended with $rc" >&2; exit 1; }
fi
shasum -a 256 "$WORK/mgf-package-family.dylib"
[ "${1:-}" = --sign ] || exit 0
ID="${MGVF_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$ID" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
OUT="$HERE/mgf-package-family.dylib"
cp "$WORK/mgf-package-family.dylib" "$WORK/signed.dylib"
/usr/bin/codesign -f -s "$ID" --timestamp --options runtime "$WORK/signed.dylib"
for arch in x86_64 arm64; do
  cmp -s <(otool -arch "$arch" -t "$WORK/mgf-package-family.dylib" | sed 1d) \
         <(otool -arch "$arch" -t "$WORK/signed.dylib" | sed 1d) \
    || { echo "signing changed the $arch code" >&2; exit 1; }
done
cp "$WORK/signed.dylib" "$OUT"
chmod 755 "$OUT"
shasum -a 256 "$OUT"
