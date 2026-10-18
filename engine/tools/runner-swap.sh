#!/bin/sh
# Developer tool: put one build's modules into a CrossOver lib/wine folder for a test,
# or put that folder's own files back.
#
#   tools/runner-swap.sh install <build id> <CrossOver dir>
#   tools/runner-swap.sh restore <build id> <CrossOver dir>
#
#   <CrossOver dir> is the folder holding lib/wine, e.g.
#   ~/Library/Application Support/notproton/runners/crossover-27.0.0.41069-fex/CrossOver
#
# The first install keeps the folder's own three files under .build/runner-backup/,
# outside lib/wine, so nothing Wine scans changes; restore copies them back. It refuses
# while any Wine process runs, and an install refuses a build whose Wine does not match
# the folder's (wine-<version> in ntdll.so against the build's built-for.json).
set -eu
engine="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 3 ] || { sed -n '5,10p' "$0"; exit 2; }
verb="$1"; ID="$2"; ROOT="$3"
LIB="$ROOT/lib/wine"
MODULES="$engine/modules/$ID"
# A NotProton runner is named by its folder, a CrossOver app by its bundle name.
key=$(printf '%s' "$ROOT" | sed -n -e 's|.*/runners/\([^/]*\)/CrossOver/*$|\1|p' \
  -e 's|.*/\([^/]*\.app\)/Contents/SharedSupport/CrossOver/*$|\1|p')
[ -n "$key" ] || { echo "not a runner's or a CrossOver app's CrossOver folder: $ROOT"; exit 1; }
SAVE="$engine/.build/runner-backup/$key"
FILES="x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so"
# The FEX side, where the folder has one (CrossOver 27) and the build carries it.
if [ -d "$LIB/aarch64-unix" ] && { [ "$verb" = restore ] || [ -f "$MODULES/aarch64-unix/winecoreaudio.so" ]; }; then
  FILES="$FILES aarch64-windows/winebus.sys aarch64-windows/mmdevapi.dll aarch64-unix/winecoreaudio.so"
fi
[ -f "$LIB/x86_64-unix/ntdll.so" ] || { echo "no Wine at $LIB"; exit 1; }
if pgrep -f 'wineserver|\.exe' >/dev/null; then echo "a Wine process is running; not touching $LIB"; exit 1; fi
case "$verb" in
install)
  [ -f "$MODULES/built-for.json" ] || { echo "no modules for build $ID"; exit 1; }
  want=$(sed -n 's/.*"wine": "Wine version \([0-9.]*\)".*/\1/p' "$MODULES/built-for.json")
  have=$(LC_ALL=C grep -a -o -m1 -E 'wine-[0-9]+\.[0-9]+' "$LIB/x86_64-unix/ntdll.so" | head -1)
  [ "wine-$want" = "$have" ] || { echo "build $ID is Wine $want, this folder runs $have"; exit 1; }
  for f in $FILES; do
    if [ ! -f "$SAVE/$f" ]; then mkdir -p "$SAVE/$(dirname "$f")"; cp -p "$LIB/$f" "$SAVE/$f"; fi
    cp "$MODULES/$f" "$LIB/$f"
  done ;;
restore)
  for f in $FILES; do [ -f "$SAVE/$f" ] && cp -p "$SAVE/$f" "$LIB/$f"; done ;;
*) sed -n '5,10p' "$0"; exit 2 ;;
esac
for f in $FILES; do printf '%s  %s\n' "$(shasum -a 256 "$LIB/$f" | cut -c1-12)" "$f"; done
