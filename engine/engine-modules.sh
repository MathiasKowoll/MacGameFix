#!/bin/bash
# Puts the Wine modules into one CrossOver, or takes them out.
#
#   engine-modules.sh <CrossOver folder> --status    installed, outdated, half, absent or nomodules
#   engine-modules.sh <CrossOver folder>             install
#   engine-modules.sh <CrossOver folder> --restore   put CrossOver's own files back
#   ... --part=controls|rosetta                      the same for one improvement only
#
# The modules are two improvements, each installed and removed on its own:
#   controls  the DualSense's haptics, triggers, Bluetooth and XInput: every module but ntdll.so
#   rosetta   Rosetta's CPU for copy protection: ntdll.so, which also carries the
#             timer thread's fix (0021), on the FEX side too where a build has one
# Without --part every improvement the build carries is meant, as before there were two.
# An improvement removed with --part is noted in the backup folder, so that its status
# is absent and not outdated while the other one stays in.
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
# with a list of what was put in their place; a file kept there is never replaced, since
# the folder is one CrossOver build and its own files do not change. Nothing is changed
# while a Wine of that
# CrossOver runs. A CrossOver app is signed again (ad hoc) after a change, since changing
# files inside it breaks CodeWeavers' signature.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-}"; MODE=install; PART=all
[ $# -gt 0 ] && shift
for arg in "$@"; do
  case "$arg" in
    --part=controls|--part=rosetta) PART="${arg#--part=}" ;;
    --part=*) printf 'Unknown improvement: %s\n' "${arg#--part=}"; exit 2 ;;
    *) MODE="$arg" ;;
  esac
done
ROOT="${ROOT%/}"
# Which improvement a module belongs to.
part_of() { case "${1##*/}" in ntdll.so) echo rosetta ;; *) echo controls ;; esac; }
in_part() { [ "$PART" = all ] || [ "$(part_of "$1")" = "$PART" ]; }
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
XINPUT_DLLS="xinput1_1.dll xinput1_2.dll xinput1_3.dll xinput1_4.dll xinput9_1_0.dll xinputuap.dll"
FILES=""
for side in x86_64 aarch64; do
  [ -d "$LIB/$side-unix" ] || continue
  if [ -f "$(src "$side-unix/winecoreaudio.so")" ]; then
    FILES="$FILES $side-windows/winebus.sys $side-windows/mmdevapi.dll $side-unix/winecoreaudio.so"
    # winebus.so (the Bluetooth DualSense), hidclass.sys and xinput (XInput),
    # then setupapi.dll and xaudio2_9.dll, and ntdll.so (Rosetta's CPU fidelity on the
    # Intel side, the timer fix on both), came later; a build may not carry them.
    for f in $side-unix/winebus.so $side-unix/ntdll.so $side-windows/hidclass.sys $side-windows/setupapi.dll $side-windows/xaudio2_9.dll $XINPUT_DLLS; do
      case "$f" in */*) ;; *) f="$side-windows/$f" ;; esac
      [ -f "$(src "$f")" ] && FILES="$FILES $f"
    done
  elif [ "$MODE" != --restore ]; then
    say "This CrossOver has a $side side, and there are no modules for it."
  fi
done
# The improvement asked for alone.
KEEP=""
for f in $FILES; do in_part "$f" && KEEP="$KEEP $f"; done
FILES="$KEEP"
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
recorded() { [ -f "$SAVE/installed.list" ] && sed -n "s|^\([0-9a-f]*\)  $1\$|\1|p" "$SAVE/installed.list"; }
# The improvements taken out on their own, one name a line.
is_off() { [ -f "$SAVE/off.list" ] && grep -qx "$(part_of "$1")" "$SAVE/off.list"; }

state() {
  local n=0 ours=0 old=0 f t
  for f in $FILES; do
    n=$((n + 1)); t="$(sha "$LIB/$f")"
    if [ "$t" = "$(sha "$(src "$f")")" ]; then ours=$((ours + 1))
    elif [ -n "$t" ] && [ "$t" = "$(recorded "$f")" ]; then old=$((old + 1))
    # A file newer modules add, beside an install that did not have it: an update,
    # unless its improvement was taken out on its own.
    elif [ -n "$t" ] && [ -f "$SAVE/installed.list" ] && [ -z "$(recorded "$f")" ] && ! is_off "$f"; then
      old=$((old + 1)); fi
  done
  if [ "$n" -gt 0 ] && [ "$ours" -eq "$n" ]; then echo installed
  elif [ "$old" -gt 0 ] && [ $((ours + old)) -eq "$n" ]; then echo outdated
  elif [ $((ours + old)) -gt 0 ]; then echo half
  else echo absent; fi
}

if [ "$MODE" = --status ]; then
  [ -n "$FILES" ] || { say "There is nothing of this improvement for CrossOver $BUILD yet."; say nomodules; exit 0; }
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

# A file goes in under another name first and is renamed over the old one, so that the
# folder holding it changes too. NotProton's Game Mode (its main since d01287d) runs each
# game from a copy of the runner, and makes the copy again only when the runner's
# lib/wine folders, its loader or the 26.3 ntdll.so change: a file written over in place
# changes none of those, and the game would keep the modules it had. The file keeps the
# mode of the one it replaces.
put() {
  local from="$1" to="$2" tmp
  tmp="$(dirname "$2")/.$(basename "$2").mgvf-new"
  rm -f "$tmp" 2>/dev/null
  if cp ${3:-} "$from" "$tmp" 2>/dev/null &&
     { [ ! -e "$to" ] || chmod "$(stat -f %Lp "$to")" "$tmp"; } && mv -f "$tmp" "$to" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
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
  # What another improvement put in stays on the list.
  : >"$SAVE/installed.list.new"
  if [ -f "$SAVE/installed.list" ]; then
    while read -r h f; do
      case " $FILES " in *" $f "*) ;; *) printf '%s  %s\n' "$h" "$f" >>"$SAVE/installed.list.new" ;; esac
    done <"$SAVE/installed.list"
  fi
  for f in $FILES; do
    t="$(sha "$LIB/$f")"; s="$(sha "$(src "$f")")"
    # The first time, a file that is neither ours nor what we last put there is
    # CrossOver's own: keep it. One CrossOver does not have at all is noted, so
    # that removing takes ours out. Once kept, CrossOver's own stays as it was:
    # what stands in its place later (an update putting it back, a development
    # build) is replaced and not kept over it.
    if [ -f "$SAVE/$f" ] || [ -f "$SAVE/$f.absent" ]; then
      [ -n "$t" ] && [ "$t" != "$s" ] && [ "$t" != "$(recorded "$f")" ] && [ "$t" != "$(sha "$SAVE/$f")" ] &&
        say "  $f was neither CrossOver's nor ours; CrossOver's own stays kept"
    elif [ -z "$t" ] && [ -z "$(recorded "$f")" ]; then
      mkdir -p "$SAVE/$(dirname "$f")" && : > "$SAVE/$f.absent" || exit 1
    elif [ "$t" != "$s" ] && [ "$t" != "$(recorded "$f")" ]; then
      mkdir -p "$SAVE/$(dirname "$f")" && cp -p "$LIB/$f" "$SAVE/$f" || exit 1
    fi
    put "$(src "$f")" "$LIB/$f" || refused "$LIB/$f"
    say "  $f"
    printf '%s  %s\n' "$s" "$f" >>"$SAVE/installed.list.new"
  done
  mv "$SAVE/installed.list.new" "$SAVE/installed.list"
  if [ -f "$SAVE/off.list" ]; then
    for f in $FILES; do grep -vx "$(part_of "$f")" "$SAVE/off.list" >"$SAVE/off.list.new"; mv "$SAVE/off.list.new" "$SAVE/off.list"; done
    [ -s "$SAVE/off.list" ] || rm -f "$SAVE/off.list"
  fi
  resign
  say "Installed the modules for CrossOver $BUILD into $ROOT." ;;
--restore)
  [ -d "$SAVE" ] || { say "Nothing of MacGameFix's is in $ROOT."; exit 0; }
  for f in x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-windows/hidclass.sys \
           x86_64-unix/winecoreaudio.so x86_64-unix/winebus.so x86_64-unix/ntdll.so aarch64-windows/winebus.sys \
           aarch64-windows/mmdevapi.dll aarch64-windows/hidclass.sys aarch64-unix/winecoreaudio.so \
           aarch64-unix/winebus.so aarch64-unix/ntdll.so x86_64-windows/setupapi.dll aarch64-windows/setupapi.dll \
           x86_64-windows/xaudio2_9.dll aarch64-windows/xaudio2_9.dll \
           $(for x in $XINPUT_DLLS; do printf 'x86_64-windows/%s aarch64-windows/%s ' "$x" "$x"; done); do
    in_part "$f" || continue
    if [ -f "$SAVE/$f.absent" ]; then
      rm -f "$LIB/$f" 2>/dev/null || refused "$LIB/$f"
      say "  $f (CrossOver had none)"
      continue
    fi
    [ -f "$SAVE/$f" ] || continue
    put "$SAVE/$f" "$LIB/$f" -p || refused "$LIB/$f"
    say "  $f"
  done
  # One improvement out: its lines leave the list and it is noted as off. The folder goes
  # with the last of them, as it went with everything before.
  if [ "$PART" != all ] && [ -f "$SAVE/installed.list" ]; then
    : >"$SAVE/installed.list.new"
    while read -r h f; do in_part "$f" || printf '%s  %s\n' "$h" "$f" >>"$SAVE/installed.list.new"; done <"$SAVE/installed.list"
    mv "$SAVE/installed.list.new" "$SAVE/installed.list"
  fi
  if [ "$PART" = all ] || [ ! -s "$SAVE/installed.list" ]; then
    rm -rf "$SAVE"
  else
    grep -qx "$PART" "$SAVE/off.list" 2>/dev/null || echo "$PART" >>"$SAVE/off.list"
  fi
  resign
  say "Put CrossOver's own files back in $ROOT." ;;
*) sed -n '4,6p' "$0"; exit 2 ;;
esac
