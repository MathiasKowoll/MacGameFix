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
# NOTHING IN THE GAME FOLDER IS TOUCHED. The fix is NOTPROTON_TCP_NOOPT=1 in front of the
# game's Steam launch options, which switches on NotProton's "Red Dead Online fix" row for it,
# and the Rockstar Games Launcher's window (below).
#
# WHAT THIS FIXES. Red Dead Online never connected to its servers on a Mac: its TCP
# connections have to be made without TCP options (macOS's TCP_NOOPT: no MSS, window
# scale, SACK or timestamps). NotProton's creator found it and wrote the fix. The row's
# library, tcp-noopt.dylib (app/notproton-plugins/plugins/tcp-noopt.c, which MacGameFix
# puts in NotProton's plugins folder), sets the option on the game's sockets before they
# connect, from outside ntdll. Engine patch 0037 did the same inside the Wine modules'
# ntdll.so, switched on by NotProton's file notproton-tcp-noopt beside the prefix, which
# earlier versions of this fix wrote; since NotProton's runner for CrossOver Preview 41303
# keeps NotProton's own ntdll.so on Rosetta, the row is what does it, and an install takes
# that file away. Without window scaling a connection keeps at most 64 KB in flight, so it
# is for this game alone.
#
# Played on 2026-11-20 with 0037 on NotProton's 41303 runner (Rosetta): Red Dead Online
# reached its online world. Played again on 2026-11-26 on that runner with NotProton's ntdll.so,
# the row and the Launcher's window below: Red Dead Online reached its online world.
#
# THE LAUNCHER'S WINDOW. The Rockstar Games Launcher draws Social Club's page in another
# process (SocialClubHelper.exe, Chromium) into its own window. CodeWeavers' win32u.so never
# shows that window, and the Launcher gives up after 30 s: "timed out loading both its online
# and offline content". Engine patch 0033 (win32u.so: a window surface flushed to a top-level
# window of another process) fixes it; NotProton's shared runner keeps CodeWeavers' win32u.so
# (engine-modules.sh), so this copies the Wine modules' win32u.so into rdr2/launcher-window
# and writes a NotProton runner variant of it (notproton/variants/mgf-rdr2-launcher.conf),
# which NOTPROTON_RUNNER_VARIANT in the launch options asks for: the game alone runs on a
# runner copy that has it. On 2026-11-26, with CodeWeavers' win32u.so the Launcher timed out
# twice; with 0033's it signed in, and Red Dead Online was played.
#
# A CrossOver bottle is not done here: NotProton's plugins do not load in one.
#
# MGVF-SCOPE: prefix
# MGVF-GAME: Red Dead Redemption 2 | RDR2.exe |
# MGVF-WHY: Red Dead Online never connects to its servers on a Mac, and on NotProton's runner the Rockstar Games Launcher times out before its window shows. This switches on NotProton's Red Dead Online fix row for the game and gives it the Launcher's window fix, for this game alone. Quit Steam before installing. NotProton with CrossOver Preview 41303 (Rosetta) only.
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

APPID=1174180
ID=NOTPROTON_TCP_NOOPT
NP_SUPPORT="$HOME/Library/Application Support/notproton"
PLUGINS="$NP_SUPPORT/plugins"
JOURNAL="$PFX/.mgf-rdo-launch-options.json"
# The Launcher's window: 0033's win32u.so from the Wine modules catalog (MGVF_MODULES, the
# app's), as a runner variant the launch options ask for.
MODULES="${MGVF_MODULES:-$HERE}"
WINDOW="${MGVF_RDR2_STORE:-$HOME/Library/Application Support/MacGameFix/rdr2}/launcher-window"
VARIANT_ID=mgf-rdr2-launcher-window
VARIANT="$NP_SUPPORT/variants/mgf-rdr2-launcher.conf"
WIN32U="$MODULES/engine-27.0.0.41303-x86_64-unix-win32u.so"
window_conf() {
  printf '# MacGameFix writes this file for app %s and removes it with the fix; edits do not last.\n' "$APPID"
  printf '[%s]\nlabel = Rockstar Games Launcher window (MacGameFix)\nvariant = Rockstar Games Launcher window\n' "$VARIANT_ID"
  printf 'src = %s\ndst = lib/wine\nbuild = 27.0.0.41303-fex\nbuild = 27.0.0.41303\napps = %s\n' "$WINDOW" "$APPID"
}
window_ok() { cmp -s "$WIN32U" "$WINDOW/x86_64-unix/win32u.so" && [ "$(window_conf)" = "$(cat "$VARIANT" 2>/dev/null)" ]; }
# Renamed into place: NotProton remakes a variant when its files' stat changes.
window_install() {
  mkdir -p "$WINDOW/x86_64-unix" "$(dirname "$VARIANT")" || return 1
  cp "$WIN32U" "$WINDOW/x86_64-unix/win32u.so.new" && mv -f "$WINDOW/x86_64-unix/win32u.so.new" "$WINDOW/x86_64-unix/win32u.so" || return 1
  window_conf > "$VARIANT.new" && mv -f "$VARIANT.new" "$VARIANT"
}
window_remove() { rm -f "$VARIANT"; rm -rf "$WINDOW"; }
# The switch file engine patch 0037 read, which earlier versions of this fix wrote.
SWITCH="$(dirname "$PFX")/notproton-tcp-noopt"
# notproton-build: the runner's build on the first line (27.0.0.41303-fex), and on the second
# what it runs on ("... - Rosetta" or "... - FEX").
BUILD=""; SIDE=""
{ IFS= read -r BUILD || true; IFS= read -r SIDE || true; } < "$(dirname "$PFX")/notproton-build"
right_runner() {
  case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *) return 1 ;; esac
  case "$SIDE" in *Rosetta*) return 0 ;; esac
  return 1
}
options() { /usr/bin/perl "$HERE/steam-launch-options.pl" "$1" "$APPID" "$JOURNAL" "$ID=1" "NOTPROTON_RUNNER_VARIANT=$VARIANT_ID"; }
# The row MacGameFix keeps in NotProton's plugins folder (NotProtonPlugins.swift), or one
# NotProton ships under the same id, with the library it names.
row_ok() {
  local conf lib
  [ -f "$NP_SUPPORT/plugin-host.dylib" ] || return 1
  conf="$(/usr/bin/grep -lx "\[$ID\]" "$PLUGINS"/*.conf 2>/dev/null | head -1)"
  [ -n "$conf" ] || return 1
  lib="$(/usr/bin/sed -n "/^\[$ID\]/,/^\[/s|^requires = ||p" "$conf" | head -1)"
  [ -n "$lib" ] && [ -f "$HOME/$lib" ]
}
NOROW="NotProton's Red Dead Online fix row is not in its plugins folder: it needs NotProton's plugin host (NotProton's Update), and MacGameFix puts the row in place (Improvements, Put in Place)"

case "$MODE" in
--status)
  right_runner || norecipe "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; the fix needs CrossOver Preview 41303's, on Rosetta"
  echo "looking at $PFX"
  if options status >/dev/null 2>&1 && row_ok && window_ok; then echo installed
  elif options status >/dev/null 2>&1 && ! row_ok; then echo "Why: $NOROW" >&2; echo half
  elif options status >/dev/null 2>&1 || [ -f "$VARIANT" ] || [ -f "$JOURNAL" ]; then
    echo "Why: the Rockstar Games Launcher's window, or its switch in the launch options, is not in place: install it again" >&2
    echo half
  elif [ -f "$SWITCH" ]; then
    echo "Why: an earlier version of the fix, for the Wine modules' ntdll: install it again" >&2
    echo half
  else echo absent; fi
  exit 0 ;;
--restore)
  if [ -f "$JOURNAL" ]; then options preflight >/dev/null || exit 1; options restore >/dev/null || exit 1; fi
  rm -f "$SWITCH"
  window_remove
  echo "restored -- Red Dead Redemption 2's connections use TCP options again"
  echo restored
  exit 0 ;;
esac

right_runner || refuse "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; the fix needs CrossOver Preview 41303's, on Rosetta."
row_ok || refuse "$NOROW."
[ -f "$WIN32U" ] || refuse "the Wine modules catalog ($MODULES) has no win32u.so for CrossOver 27.0.0.41303, which the Rockstar Games Launcher's window needs: update MacGameFix, then install again."
# Steam closed and no wrapper in the game's options, before anything changes.
options preflight >/dev/null || exit 1
window_install || { echo "error: could not put the Launcher's window module in $WINDOW and $VARIANT" >&2; exit 1; }
options install >/dev/null || exit 1
rm -f "$SWITCH"
echo "installed"
echo "  $ID=1 is in the game's launch options: NotProton's Red Dead Online fix row is on for it"
echo "  NOTPROTON_RUNNER_VARIANT=$VARIANT_ID: the Rockstar Games Launcher's window, on a runner copy for this game"
