#!/usr/bin/env bash
#
# Install (or remove) Red Dead Online's connection fix.
#
#   install-rdo-tcp.sh <game folder>            install
#   install-rdo-tcp.sh <game folder> --status   report
#   install-rdo-tcp.sh <game folder> --restore  remove
#
# The prefix is MGVF_BOTTLE: the Steam Play prefix NotProton keeps for the game,
#   .../steamapps/compatdata/1174180/pfx
#
# NOTHING IN THE GAME FOLDER IS TOUCHED. The fix is one empty file beside the prefix,
# compatdata/1174180/notproton-tcp-noopt, NotProton's own switch for it.
#
# WHAT THIS FIXES. Red Dead Online never connected to its servers on a Mac: its TCP
# connections have to be made without TCP options (macOS's TCP_NOOPT: no MSS, window
# scale, SACK or timestamps). NotProton's creator found it and handed MacGameFix the
# fix; engine patch 0037 (CrossOver Preview 41303, both sides' ntdll.so, part of the
# Rosetta improvement) makes the connections that way for a process whose prefix has
# that file beside it, or whose environment has WINE_TCP_NOOPT=1. NotProton does not
# always hand a launch option's WINE_* variable to the game (a launch through `open`
# keeps only NOTPROTON_ENV_*), so the file is what this writes. Without window scaling a
# connection keeps at most 64 KB in flight, so it is only for this game's prefix.
#
# Played on 2026-11-20 on NotProton's 41303 runner (Rosetta): Red Dead Online reached
# its online world and held its connections to Rockstar's servers.
#
# A CrossOver bottle is not done here: the file would sit in the Bottles folder, beside
# every bottle, and a bottle's own environment would reach Steam's downloads too.
#
# MGVF-SCOPE: prefix
# MGVF-NEEDS: rosetta
# MGVF-GAME: Red Dead Redemption 2 | RDR2.exe |
# MGVF-WHY: Red Dead Online never connects to its servers on a Mac: its TCP connections have to be made without TCP options. The Wine modules' ntdll does that for this game's prefix alone, with NotProton's own switch. NotProton with CrossOver Preview 41303 only.
# MGVF-CREDIT: NotProton's creator, who found the cause and wrote the fix | https://github.com/NotProtonNot/NotProton
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

usage() { sed -n '3,7p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage
HERE="$(cd "$(dirname "$0")" && pwd)"
# Sourced for what it tells the app: an installer that sources bottles.sh is handed the
# prefix it works on in MGVF_BOTTLE (games.json's needsPrefix).
. "$HERE/bottles.sh"

GAME="${1%/}"
MODE="${2:---install}"
# See install-p5s-bridge.sh: a read-only caller must never land on --install.
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
case "$MODE" in --install|install|--status|--restore) ;; *) usage ;; esac

[ -f "$GAME/RDR2.exe" ] || {
  echo "error: no RDR2.exe in $GAME" >&2
  echo "       Pick the folder Red Dead Redemption 2 is installed in." >&2
  exit 1
}

PFX="${MGVF_BOTTLE:-}"; PFX="${PFX%/}"
norecipe() { echo "Why: $1" >&2; echo norecipe; exit 0; }
refuse() { echo "error: $1" >&2; echo "       Nothing was changed." >&2; exit 1; }
if [ -z "$PFX" ] || [ ! -f "$PFX/system.reg" ] || [ ! -d "$PFX/drive_c" ]; then
  [ "$MODE" = --status ] && norecipe "no prefix to look at (MGVF_BOTTLE)"
  refuse "no prefix to work on: set MGVF_BOTTLE to the game's Steam Play prefix."
fi
if [ -f "$PFX/cxbottle.conf" ] || [ ! -f "$(dirname "$PFX")/notproton-build" ]; then
  [ "$MODE" = --status ] && norecipe "this game runs in a CrossOver bottle; the fix is for NotProton only"
  refuse "$PFX is not a prefix NotProton keeps; the fix is for NotProton only."
fi

SWITCH="$(dirname "$PFX")/notproton-tcp-noopt"
# notproton-build's first line names the runner: 27.0.0.41303 or 27.0.0.41303-fex; MGVF_CX, when
# the app passes it, is that runner's CrossOver folder.
BUILD=""; IFS= read -r BUILD < "$(dirname "$PFX")/notproton-build" || true
RUNNER="${MGVF_CX:-$HOME/Library/Application Support/notproton/runners/crossover-$BUILD/CrossOver}"
RUNNER="${RUNNER%/}"
NTDLL="$RUNNER/lib/wine/x86_64-unix/ntdll.so"
# 0037 carries the switch's file name; CrossOver's own ntdll.so and ours before it do not.
carries_fix() { [ -f "$NTDLL" ] && LC_ALL=C /usr/bin/grep -qa 'notproton-tcp-noopt' "$NTDLL"; }

case "$MODE" in
--status)
  case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *)
    norecipe "the game runs on NotProton's runner for CrossOver $BUILD; the fix needs CrossOver Preview 41303's" ;;
  esac
  echo "looking at $PFX and $RUNNER"
  if [ -f "$SWITCH" ] && carries_fix; then echo installed
  elif [ -f "$SWITCH" ]; then
    echo "Why: the switch is in place, but the runner's ntdll.so does not have the fix: update the Rosetta improvement" >&2
    echo half
  else echo absent; fi
  exit 0 ;;
--restore)
  rm -f "$SWITCH"
  echo "restored -- Red Dead Redemption 2's connections use TCP options again"
  echo restored
  exit 0 ;;
esac

case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *)
  refuse "the game runs on NotProton's runner for CrossOver $BUILD; the fix needs CrossOver Preview 41303's." ;;
esac
carries_fix || refuse "the runner's ntdll.so ($NTDLL) does not have the fix: put in or update the Rosetta improvement for CrossOver Preview 41303 first."
: > "$SWITCH" || refuse "could not write $SWITCH"
echo "installed"
echo "  $SWITCH is in place: the game's TCP connections are made without TCP options"
