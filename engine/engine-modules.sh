#!/bin/bash
# Puts the DualSense Wine modules into one CrossOver, or takes them out.
#
#   engine-modules.sh <CrossOver folder> --status    installed, outdated, half, absent or nomodules
#   engine-modules.sh <CrossOver folder>             install
#   engine-modules.sh <CrossOver folder> --restore   put CrossOver's own files back
#
# <CrossOver folder> is the folder that holds lib/wine: a NotProton runner's
#   ~/Library/Application Support/notproton/runners/crossover-<build>[-fex]/CrossOver
# or a CrossOver app's
#   <app>/Contents/SharedSupport/CrossOver
#
# The modules sit beside this script, flat, as engine-<build>-<dir>-<file>
# (engine-27.0.0.41069-x86_64-unix-winecoreaudio.so), and engine-modules.json says which
# builds there are and which Wine each was built from. A build is installed only into a
# CrossOver of that exact build running that Wine; both sides, Intel (x86_64) and FEX
# (aarch64), where the CrossOver has the side and the build carries it.
#
# CrossOver's own files are kept under $MGVF_ENGINE_BACKUP/<runner, or app and build>,
# with a list of what was put in their place. Nothing is changed while a Wine of that
# CrossOver runs. A CrossOver app is signed again (ad hoc) after a change, since changing
# files inside it breaks CodeWeavers' signature.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-}"; MODE="${2:-install}"
ROOT="${ROOT%/}"
BACKUPS="${MGVF_ENGINE_BACKUP:-$HOME/Library/Application Support/MacGameFix/engine-backup}"
LIB="$ROOT/lib/wine"
MANIFEST="$HERE/engine-modules.json"

say() { printf '%s\n' "$*"; }
[ -n "$ROOT" ] || { sed -n '4,6p' "$0"; exit 2; }
[ -f "$LIB/x86_64-unix/ntdll.so" ] || { say "No CrossOver Wine at $ROOT."; exit 1; }

APP=""
case "$ROOT" in
  */runners/crossover-*/CrossOver)
    KEY="$(basename "$(dirname "$ROOT")")"
    BUILD="${KEY#crossover-}"; BUILD="${BUILD%%-*}" ;;
  */Contents/SharedSupport/CrossOver)
    APP="${ROOT%/Contents/SharedSupport/CrossOver}"
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null)"
    KEY="$(basename "$APP")-$BUILD" ;;
  *) say "Not a NotProton runner or a CrossOver app: $ROOT"; exit 1 ;;
esac
SAVE="$BACKUPS/$KEY"

# Which Wine this build's modules were built from, from engine-modules.json.
WINE=""; i=0
while b="$(plutil -extract "builds.$i.build" raw -o - "$MANIFEST" 2>/dev/null)"; do
  [ "$b" = "$BUILD" ] && { WINE="$(plutil -extract "builds.$i.wine" raw -o - "$MANIFEST")"; break; }
  i=$((i + 1))
done
HAVE="$(LC_ALL=C grep -a -o -m1 -E 'wine-[0-9]+\.[0-9]+' "$LIB/x86_64-unix/ntdll.so")"
if [ -z "$WINE" ] || [ "$HAVE" != "wine-$WINE" ]; then
  if [ -z "$WINE" ]; then say "There are no modules for CrossOver $BUILD yet."
  else say "The modules for CrossOver $BUILD are for Wine $WINE; this one runs $HAVE."; fi
  [ "$MODE" = --status ] && { say nomodules; exit 0; }
  [ "$MODE" = --restore ] || exit 1
fi

src() { printf '%s/engine-%s-%s' "$HERE" "$BUILD" "$(printf '%s' "$1" | tr / -)"; }
FILES=""
for side in x86_64 aarch64; do
  [ -d "$LIB/$side-unix" ] || continue
  if [ -f "$(src "$side-unix/winecoreaudio.so")" ]; then
    FILES="$FILES $side-windows/winebus.sys $side-windows/mmdevapi.dll $side-unix/winecoreaudio.so"
    # winebus.so (the Bluetooth DualSense) came later; a build may not carry it.
    [ -f "$(src "$side-unix/winebus.so")" ] && FILES="$FILES $side-unix/winebus.so"
  elif [ "$MODE" != --restore ]; then
    say "This CrossOver has a $side side, and there are no modules for it."
  fi
done
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
recorded() { [ -f "$SAVE/installed.list" ] && sed -n "s|^\([0-9a-f]*\)  $1\$|\1|p" "$SAVE/installed.list"; }

state() {
  local n=0 ours=0 old=0 f t
  for f in $FILES; do
    n=$((n + 1)); t="$(sha "$LIB/$f")"
    if [ "$t" = "$(sha "$(src "$f")")" ]; then ours=$((ours + 1))
    elif [ -n "$t" ] && [ "$t" = "$(recorded "$f")" ]; then old=$((old + 1))
    # A file newer modules add, beside an install that did not have it: an update.
    elif [ -n "$t" ] && [ -f "$SAVE/installed.list" ] && [ -z "$(recorded "$f")" ]; then old=$((old + 1)); fi
  done
  if [ "$n" -gt 0 ] && [ "$ours" -eq "$n" ]; then echo installed
  elif [ "$old" -gt 0 ] && [ $((ours + old)) -eq "$n" ]; then echo outdated
  elif [ $((ours + old)) -gt 0 ]; then echo half
  else echo absent; fi
}

if [ "$MODE" = --status ]; then
  s="$(state)"
  [ "$s" = absent ] && [ -f "$SAVE/installed.list" ] && say "Something replaced the modules since they were installed."
  say "$s"; exit 0
fi

# A Wine of this CrossOver keeps its modules open; changing them under it is not safe.
if ps -axo args= | grep -F -- "$ROOT/" | grep -v -F -e "grep" -e "$0" >/dev/null; then
  say "A game or program of this CrossOver is running. Quit it first."
  exit 1
fi

refused() {
  say "macOS did not let MacGameFix change $1."
  [ -n "$APP" ] && say "Allow MacGameFix in System Settings > Privacy & Security > App Management, then try again."
  exit 1
}

resign() {
  [ -n "$APP" ] || return 0
  say "Signing $(basename "$APP") again (ad hoc): CodeWeavers' signature no longer covers its files."
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || say "Could not sign $APP again."
  xattr -cr "$APP" 2>/dev/null
}

case "$MODE" in
install)
  [ -n "$FILES" ] || { say "Nothing to install for CrossOver $BUILD."; exit 1; }
  mkdir -p "$SAVE" || exit 1
  : >"$SAVE/installed.list.new"
  for f in $FILES; do
    t="$(sha "$LIB/$f")"; s="$(sha "$(src "$f")")"
    # A file that is neither ours nor what we last put there is CrossOver's own:
    # the first time, or after an update put its files back. Keep it. One
    # CrossOver does not have at all is noted, so that removing takes ours out.
    if [ -z "$t" ] && [ -z "$(recorded "$f")" ]; then
      mkdir -p "$SAVE/$(dirname "$f")" && : > "$SAVE/$f.absent" || exit 1
    elif [ "$t" != "$s" ] && [ "$t" != "$(recorded "$f")" ]; then
      mkdir -p "$SAVE/$(dirname "$f")" && cp -p "$LIB/$f" "$SAVE/$f" && rm -f "$SAVE/$f.absent" || exit 1
    fi
    cp "$(src "$f")" "$LIB/$f" 2>/dev/null || refused "$LIB/$f"
    say "  $f"
    printf '%s  %s\n' "$s" "$f" >>"$SAVE/installed.list.new"
  done
  mv "$SAVE/installed.list.new" "$SAVE/installed.list"
  resign
  say "Installed the modules for CrossOver $BUILD into $ROOT." ;;
--restore)
  [ -d "$SAVE" ] || { say "Nothing of MacGameFix's is in $ROOT."; exit 0; }
  for f in x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so \
           x86_64-unix/winebus.so aarch64-windows/winebus.sys aarch64-windows/mmdevapi.dll \
           aarch64-unix/winecoreaudio.so aarch64-unix/winebus.so; do
    if [ -f "$SAVE/$f.absent" ]; then
      rm -f "$LIB/$f" 2>/dev/null || refused "$LIB/$f"
      say "  $f (CrossOver had none)"
      continue
    fi
    [ -f "$SAVE/$f" ] || continue
    cp -p "$SAVE/$f" "$LIB/$f" 2>/dev/null || refused "$LIB/$f"
    say "  $f"
  done
  rm -rf "$SAVE"
  resign
  say "Put CrossOver's own files back in $ROOT." ;;
*) sed -n '4,6p' "$0"; exit 2 ;;
esac
