#!/usr/bin/env bash
#
# Install God of War Ragnarök's adaptive triggers.
#
#     install-gowr-triggers.sh <game folder>            install
#     install-gowr-triggers.sh <game folder> --status   report
#     install-gowr-triggers.sh <game folder> --restore  undo
#
# Under Wine, Steam tells the game it runs on a Steam Deck, so it never loads
# Sony's library: every adaptive-trigger effect it builds goes to its
# scePadSetTriggerEffect wrapper, which drops it. Measured on 2026-10-23: 979
# effects in eight minutes, all dropped. The fix sends each one to the pad as
# the DualSense's own trigger effect (gowr-triggers.c), and the pad's rumble
# stays as it was. Played with Steam Input on, a DualSense Edge shown as a
# DualSense over Bluetooth: L2's vibration came through.
#
# It rides on bink2w64.dll, which the game imports and no runner ships, so no
# DLL override is needed. It finds the game's wrapper by the name the wrapper
# hands on, not by an address; a game update that changed that code finds
# nothing, and the game runs as without the fix (its log says so).
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MGVF-SCOPE: folder
# MGVF-GAME: God of War Ragnarök | GoWR.exe |
# MGVF-WHY: Adaptive triggers never reach the pad: told it runs on a Steam Deck, the game never loads Sony's library and drops every trigger effect.
# MGVF-LOG: gowr-triggers.log

set -euo pipefail

usage() { sed -n '3,7p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
# See install-p5s-bridge.sh: a read-only caller must never land on --install.
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
HERE="$(cd "$(dirname "$0")" && pwd)"

LIVE="$GAME/bink2w64.dll"
REAL="$GAME/bink2w64_real.dll"
PROXY="$HERE/bink2w64-gowr.dll"
EXPORTS="$HERE/pe.pl"
MARKER='gowr-triggers.log'

is_ours() { [ -f "$1" ] && LC_ALL=C grep -qa "$MARKER" "$1"; }

[ -f "$GAME/GoWR.exe" ] || {
  echo "error: no GoWR.exe in $GAME" >&2
  echo "       Pick the folder God of War Ragnarök is installed in (God of War Ragnarok)." >&2
  exit 1
}

case "$MODE" in
--status)
  if is_ours "$LIVE" && [ -f "$REAL" ]; then
    # An older build of ours still works, and installing again brings the
    # current one: "outdated".
    if cmp -s "$LIVE" "$PROXY"; then echo installed
    else echo "an older build of the fix is in place; installing again brings this one" >&2; echo outdated; fi
  elif is_ours "$LIVE"; then echo broken
  elif [ ! -f "$LIVE" ] && [ -f "$REAL" ]; then echo half
  else echo absent; fi
  exit 0
  ;;
--restore)
  if [ -f "$REAL" ]; then
    mv -f "$REAL" "$LIVE"
    echo "restored -- the game is back to its own bink2w64.dll"
  else
    echo "nothing to restore"
  fi
  rm -f "$GAME/$MARKER"
  exit 0
  ;;
--install) ;;
*) usage ;;
esac

if is_ours "$LIVE" && [ -f "$REAL" ] && cmp -s "$LIVE" "$PROXY"; then
  echo "the fix is already installed, nothing to do"
  exit 0
fi
if is_ours "$LIVE" && [ ! -f "$REAL" ]; then
  echo "error: $LIVE is already the fix but $REAL is gone." >&2
  echo "       Verify the game files in Steam, then run this again." >&2
  exit 1
fi
# The saved original must never be overwritten (see install-sm2-fix.sh).
if ! is_ours "$LIVE" && [ -f "$REAL" ]; then
  echo "error: $REAL already exists and $LIVE is not this fix." >&2
  echo "       Run this with --restore first, or verify the game files in Steam." >&2
  exit 1
fi

if ! is_ours "$LIVE"; then
  echo "[1/2] checking the proxy forwards everything the game imports"
  if ! live_exports="$(/usr/bin/perl "$EXPORTS" exports "$LIVE" 2>&1)"; then
    echo "error: cannot read the exports of $LIVE" >&2
    exit 1
  fi
  proxy_exports="$(/usr/bin/perl "$EXPORTS" exports "$PROXY")"
  missing="$(comm -23 <(printf '%s\n' "$live_exports" | sort) <(printf '%s\n' "$proxy_exports" | sort))"
  if [ -n "$missing" ]; then
    echo "error: this build's bink2w64 exports symbols the shipped proxy does not:" >&2
    echo "$missing" | sed 's/^/       /' >&2
    exit 1
  fi
else
  echo "[1/2] the fix's bink2w64.dll is in place"
fi

echo "[2/2] installing"
if is_ours "$LIVE"; then
  if ! cmp -s "$LIVE" "$PROXY"; then
    # The original stays under $REAL; only our own file is replaced.
    cp "$PROXY" "$LIVE.new" && mv -f "$LIVE.new" "$LIVE" || {
      rm -f "$LIVE.new"; echo "error: could not replace the older fix DLL" >&2; exit 1; }
  fi
else
  # The original is moved aside before anything is written over it
  # (see install-p5s-bridge.sh for the failure this order prevents).
  mv -f "$LIVE" "$REAL" || { echo "error: could not move the original aside; nothing was changed" >&2; exit 1; }
  [ -f "$REAL" ] || { echo "error: the original is not where it should be; refusing to write" >&2; exit 1; }
  cp "$PROXY" "$LIVE" || {
    echo "error: could not install the fix; putting the original back" >&2
    mv -f "$REAL" "$LIVE" || echo "       and that failed too -- it is at $REAL" >&2
    exit 1
  }
fi
echo
echo "installed"
echo "  the game's trigger effects go to the pad; it writes $MARKER beside itself"
