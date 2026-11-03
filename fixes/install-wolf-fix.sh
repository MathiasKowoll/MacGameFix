#!/usr/bin/env bash
#
# Install THE WOLF AMONG US REMASTERED motion-trail fix.
#
#     install-wolf-fix.sh <game folder>            install
#     install-wolf-fix.sh <game folder> --status   report
#     install-wolf-fix.sh <game folder> --restore  undo
#
# The folder is the one Steam installed, holding TheWolfAmongUsRemastered.exe.
# The bottle or Steam Play prefix the game runs in comes in MGVF_BOTTLE, as the
# app passes it.
#
# WHAT IT FIXES. With anti-aliasing on, anything that moves leaves faded copies
# of itself behind. The game's TAA resolves 8x MSAA with shaders that read 8
# samples a pixel. Apple GPUs have no 8x: D3DMetal says so, and still creates
# the game's 8x textures with 4 samples, so the reads of samples 4 to 7 return
# black. The TAA's history clamp then always includes black, dark history is
# never thrown away, and old frames stay on screen.
#
# WHAT IT CHANGES. macprotips' d3d11.dll (WolfAmongUsFix 1.0, public domain,
# shipped as published; its source, wolffix.c, wolffix_core.c and wolffix.def,
# and its sha256 are beside this script, in wolffix-LICENCES.md) goes beside
# the game. When the game creates a pixel shader,
# it makes the reads of the missing samples use the 4 that exist, and passes
# everything else to the real d3d11.dll in system32. It does nothing on a device
# that really gives 8 samples. Wine prefers its own d3d11, so one value goes into
# the bottle or prefix: d3d11 = native,builtin under
# AppDefaults\TheWolfAmongUsRemastered.exe\DllOverrides, for this executable
# alone. user.reg is edited only while nothing runs there; quit the game first,
# and in a CrossOver bottle, Steam too.
#
# A d3d11.dll of someone else's in the folder is kept as d3d11.dll.mgvf-original
# and put back by --restore. One installed by macprotips' own app is ours (it is
# the same DLL), and the copy that app kept, d3d11.dll.wolffix-backup, is put back
# as well.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# (The DLL and its source are macprotips', public domain: wolffix-LICENCES.md.)
#
# MGVF-SCOPE: folder
# MGVF-GAME: The Wolf Among Us Remastered | TheWolfAmongUsRemastered.exe |
# MGVF-WHY: A d3d11.dll beside the game reads the 4 MSAA samples D3DMetal gives instead of the 8 the shaders expect, so the TAA stops leaving trails behind anything that moves.
# MGVF-TESTING: macprotips
# MGVF-CREDIT: macprotips | https://github.com/macprotips/WolfAmongUsFix

set -euo pipefail
: "${HOME:?this needs HOME; a caller passing an explicit environment must include it}"

usage() { sed -n '3,33p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
HERE="$(cd "$(dirname "$0")" && pwd)"

# Where the game runs: pinned_bottle, user_reg_has_value, user_reg_edit.
. "$HERE/bottles.sh"

EXE="TheWolfAmongUsRemastered.exe"
LIVE="$GAME/d3d11.dll"
OURS="$HERE/d3d11-wolf.dll"
KEPT="$GAME/d3d11.dll.mgvf-original"
THEIRS="$GAME/d3d11.dll.wolffix-backup"
KEY="Software\\Wine\\AppDefaults\\$EXE\\DllOverrides"
MARKER='wolffix d3d11.dll'

is_ours() { [ -f "$1" ] && LC_ALL=C /usr/bin/grep -qaF "$MARKER" "$1"; }

[ -f "$GAME/$EXE" ] || {
  echo "error: no '$EXE' in $GAME" >&2
  echo "       Pick the folder The Wolf Among Us Remastered is installed in." >&2
  exit 1
}

# The bottle or prefix the app chose, when it chose one.
PLACE=""
if [ -n "${MGVF_BOTTLE:-}" ] && [ -f "${MGVF_BOTTLE%/}/user.reg" ] && [ -d "${MGVF_BOTTLE%/}/drive_c" ]; then
  PLACE="${MGVF_BOTTLE%/}"
fi

stopped() {
  local rc=0
  bottle_server_alive "$PLACE" || rc=$?
  case "$rc" in
  1) return 0 ;;
  0) echo "error: something is running in $PLACE." >&2
     echo "       Quit the game, and in a CrossOver bottle Steam too, then try again. Nothing was changed." >&2 ;;
  *) echo "error: cannot tell whether anything runs in $PLACE. Nothing was changed." >&2 ;;
  esac
  return 1
}

# 0 the override is there, 1 it is not, 2 nobody can say (no place, or a file
# that cannot answer while a server holds it).
override() {
  [ -n "$PLACE" ] || return 2
  local rc=0
  user_reg_has_value "$PLACE" "$KEY" d3d11 || rc=$?
  return "$rc"
}

case "$MODE" in
--status)
  echo "looking at $LIVE${PLACE:+ and $PLACE}"
  o=0; override || o=$?
  if is_ours "$LIVE"; then
    if ! cmp -s "$LIVE" "$OURS"; then echo "an older build of the fix is in place; installing again brings this one" >&2; echo outdated
    elif [ "$o" = 1 ]; then echo "Why: the DLL is in place and the override is not, so Wine loads its own d3d11"; echo half
    else echo installed; fi
  elif [ "$o" = 0 ]; then echo "Why: the override is there and the DLL is not"; echo half
  else echo absent; fi
  exit 0
  ;;
--restore)
  [ -z "$PLACE" ] || stopped || exit 1
  if [ -f "$LIVE" ] && ! is_ours "$LIVE"; then
    echo "the d3d11.dll in the folder is not ours; it stays"
  else
    rm -f "$LIVE"
    if [ -f "$KEPT" ]; then mv -f "$KEPT" "$LIVE"; echo "put back the d3d11.dll that was there before"
    elif [ -f "$THEIRS" ]; then mv -f "$THEIRS" "$LIVE"; echo "put back the d3d11.dll macprotips' app kept"; fi
  fi
  if [ -n "$PLACE" ]; then
    user_reg_edit "$PLACE" delete "$KEY" d3d11 || { echo "error: could not take the override out of $PLACE/user.reg" >&2; exit 1; }
  fi
  echo "restored"
  exit 0
  ;;
--install) ;;
*) usage ;;
esac

[ -n "$PLACE" ] || {
  echo "error: no bottle or Steam Play prefix was given for the game (MGVF_BOTTLE)." >&2
  echo "       The fix needs one value there; choose where the game runs, then try again. Nothing was changed." >&2
  exit 1
}
stopped || exit 1

echo "[1/2] the DLL"
if [ -f "$LIVE" ] && ! is_ours "$LIVE"; then
  if [ -f "$KEPT" ]; then
    echo "error: the folder has a d3d11.dll of someone else's, and one is kept as $(basename "$KEPT") already." >&2
    echo "       Move one of them out of the folder, then try again. Nothing was changed." >&2
    exit 1
  fi
  mv -f "$LIVE" "$KEPT"
  echo "  the folder's own d3d11.dll is kept as $(basename "$KEPT")"
fi
cp "$OURS" "$LIVE.mgvf-new" && mv -f "$LIVE.mgvf-new" "$LIVE" || {
  rm -f "$LIVE.mgvf-new"; echo "error: could not copy the DLL into the game folder" >&2; exit 1; }

echo "[2/2] telling Wine to load it, for this game only"
user_reg_edit "$PLACE" set "$KEY" d3d11 "native,builtin" || {
  echo "error: could not write the override into $PLACE/user.reg" >&2; exit 1; }
echo
echo "installed"
