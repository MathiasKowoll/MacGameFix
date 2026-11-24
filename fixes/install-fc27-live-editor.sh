#!/usr/bin/env bash
#
# Install (or remove) what EA SPORTS FC 27 needs to start with FC 27 Live Editor from Steam's Play.
#
#   install-fc27-live-editor.sh <game folder>            install
#   install-fc27-live-editor.sh <game folder> --status   report
#   install-fc27-live-editor.sh <game folder> --restore  remove
#
# The prefix is MGVF_BOTTLE: the Steam Play prefix NotProton keeps for the game,
#   .../steamapps/compatdata/4080220/pfx
#
# AT YOUR OWN RISK. MacGameFix takes no responsibility for failures in the game: this starts
# it without EA AntiCheat, with a third-party mod tool inside it that the player downloaded
# and provides. MacGameFix made neither FC 27 Live Editor nor its stand-in for EA AntiCheat's
# launcher, does not distribute them, and does not answer for a game that stops working, a
# save or a career that is lost, or what EA does about an account. Offline only. The install
# says so before it ends, and fc27-instructions.md opens with it.
#
# WHAT THIS IS FOR. The Steam copy of EA SPORTS FC 27 starts through the EA app, which checks
# the licence and starts EA AntiCheat's launcher. On a Mac with NotProton (2026-11-23, the
# runner for CrossOver Preview 41303, Rosetta) the EA app and the licence work, and three
# things were in the way of the game with Live Editor (github.com/xAranaktu/FC-27-Live-Editor,
# an editor of players, teams and the career database that runs inside the game, offline):
#
#   1. The game imports FindPackagesByPackageFamily from kernel32, which Wine 11.21 lacks:
#      "There is a problem with your game's setup. Please reinstall your game." Engine patch
#      0041 (the Rosetta improvement's kernelbase.dll and kernel32.dll) adds it. This script
#      only checks that the runner has it.
#   2. EA AntiCheat's launcher ends after 10 s with 0xE111000B and starts no game. Live
#      Editor's own launcher puts a stand-in in its place for the session; with the stand-in
#      alone the game ends 9 s in, with Live Editor's DLL injected it goes on. So the game
#      runs here only with Live Editor in it, and Steam's Play has to open Live Editor's
#      launcher first, start the game and stay until it is gone: fc27-le-play.sh and
#      fc27-le-run.cmd, from the launch options.
#   3. Live Editor draws its window inside the game by hooking Direct3D methods, and
#      D3DMetal's start with a jump such a hook cannot copy: the game closed the moment the
#      hooks went in. mgf-d3dmetal-hookable.dylib, which NotProton loads into the game,
#      rewrites those starts (d3dmetal-hookable/mgf-d3dmetal-hookable.c).
#
# LIVE EDITOR IS THE PLAYER'S TO PROVIDE. It is not part of MacGameFix and nothing here
# downloads it or looks for it: its author distributes it, and each version is made for one
# version of the game. The player unpacks the download, and the install ASKS for the folder
# (the one that holds Launcher.exe and FCLiveEditor.DLL, or the one around it) with macOS's
# folder chooser, every time it is run from MacGameFix's window. That is also how a new
# version goes in, by hand: install again and choose the new folder. Cancel keeps the copy in
# use. The copy that was in use is kept once, as LiveEditor.previous, for the Lua scripts and
# anything else the player kept in it. Because it asks, the fix is installed from the window
# only (MGVF-BY-HAND): the agent never runs it in the background.
# From a terminal nothing is asked: MGVF_LIVE_EDITOR names the folder, and without it the copy
# in use stays.
#
# WHAT IT PUTS WHERE.
#   - The Live Editor folder the player chose, copied to
#     ~/Library/Application Support/MacGameFix/fc27-live-editor/LiveEditor.
#   - fc27-le-play.sh and fc27-le-run.cmd beside it.
#   - In Steam's launch options for the game: the play script before %command%
#     (steam-launch-options.pl; Steam must be closed).
#   - In NotProton's plugins folder: mgf-d3dmetal-hookable.dylib and three rows for this game
#     alone (notproton-plugins.sh, np-plugin-fc27-live-editor.conf), shown on its Compatibility
#     page: "Start with Live Editor", switched on by the first install, which is also what has
#     NotProton load the library; "Play opens", the game or Live Editor's launcher window; and
#     "Exception notes for a report". Whatever a player may set is a row: nothing is typed into
#     the launch options by hand.
# Nothing is written into the prefix. Live Editor's launcher keeps its own settings there
# (C:\FC 27 Live Editor), and the play script raises one of them, the injection delay.
#
# THE GAME FOLDER. This script puts nothing in it. Live Editor's launcher does, while a session
# starts: it keeps EA AntiCheat's launcher as EAAntiCheat.GameServiceLauncher.exe.backup, puts
# its stand-in there and gives the file back when it closes. A session that is cut short can
# leave the backup behind; --restore puts it back when it finds one.
#
# WHAT IT DOES NOT DO. Nothing here reads, changes or re-creates Live Editor, its DLL or its
# stand-in: they run as their author made them, started by their own launcher.
#
# Played on 2026-11-23 with these steps done by hand: licence checked by the EA app, the game
# to its main menu with Live Editor's window on F9, a session of 4 min 35 s closed by the
# player. Not played: the editors themselves, a long session, a match.
#
# MGVF-SCOPE: prefix
# MGVF-NEEDS: rosetta
# MGVF-GAME: EA SPORTS FC 27 | FC27.exe |
# MGVF-TESTING: Mathias Kowoll
# MGVF-INSTRUCTIONS: fc27-instructions.md
# MGVF-BY-HAND: It asks you for your Live Editor folder, so it is never run in the background: install it again from here when a game update needs a new Live Editor.
# MGVF-WHY: The Steam copy only starts on a Mac with FC 27 Live Editor in it, a mod tool you download and provide: EA AntiCheat's launcher starts nothing here, and the game closed the moment the editor's window went in. This asks you for your Live Editor folder and copies it, loads a library that lets its Direct3D hooks work on D3DMetal and makes Steam's Play start the game with it. Offline, without EA AntiCheat or online modes. NotProton with CrossOver Preview 41303 (Rosetta) only. AT YOUR OWN RISK: MacGameFix does not answer for failures in the game, its saves, its mods or your account.
# MGVF-CREDIT: xAranaktu, FC 27 Live Editor, the mod tool this starts and does not include | https://github.com/xAranaktu/FC-27-Live-Editor
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

usage() { sed -n '3,7p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/bottles.sh"
. "$HERE/notproton-plugins.sh"

GAME="${1%/}"
MODE="${2:---install}"
# See install-p5s-bridge.sh: a read-only caller must never land on --install.
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
case "$MODE" in --install|install|--status|--restore) ;; *) usage ;; esac

[ -f "$GAME/FC27.exe" ] || {
  echo "error: no FC27.exe in $GAME" >&2
  echo "       Pick the folder EA SPORTS FC 27 is installed in." >&2
  exit 1
}

APPID=4080220
PLAY="$HERE/fc27-le-play.sh"
RUN="$HERE/fc27-le-run.cmd"
OPTIONS="$HERE/steam-launch-options.pl"
# The library np-plugin-fc27-live-editor.conf names; notproton-plugins.sh copies it.
HOOKS="$HERE/mgf-d3dmetal-hookable.dylib"
STORE="${MGVF_FC27_STORE:-$HOME/Library/Application Support/MacGameFix/fc27-live-editor}"
EDITOR="$STORE/LiveEditor"
STEAM="${MGVF_STEAM_ROOT:-$HOME/Library/Application Support/Steam}"
AC="EAAntiCheat.GameServiceLauncher.exe"

PFX="${MGVF_BOTTLE:-}"; PFX="${PFX%/}"
norecipe() { echo "Why: $1" >&2; echo norecipe; exit 0; }
refuse() { echo "error: $1" >&2; echo "       Nothing was changed." >&2; exit 1; }
if [ -z "$PFX" ] || [ ! -f "$PFX/system.reg" ] || [ ! -d "$PFX/drive_c" ]; then
  [ "$MODE" = --status ] && norecipe "no prefix to look at (MGVF_BOTTLE); start the game once from Steam so NotProton makes it"
  refuse "no prefix to work on: start the game once from Steam so NotProton makes its prefix, then install again."
fi
if [ -f "$PFX/cxbottle.conf" ] || [ ! -f "$(dirname "$PFX")/notproton-build" ]; then
  [ "$MODE" = --status ] && norecipe "this game runs in a CrossOver bottle; this is for NotProton only"
  refuse "$PFX is not a prefix NotProton keeps; this is for NotProton only."
fi

# notproton-build: the runner's build on the first line (27.0.0.41303-fex), and on the second
# what it runs on ("... - Rosetta" or "... - FEX"). MGVF_CX, when the app passes it, is that
# runner's CrossOver folder.
BUILD=""; SIDE=""
{ IFS= read -r BUILD || true; IFS= read -r SIDE || true; } < "$(dirname "$PFX")/notproton-build"
RUNNER="${MGVF_CX:-$HOME/Library/Application Support/notproton/runners/crossover-$BUILD/CrossOver}"
RUNNER="${RUNNER%/}"
KERNEL32="$RUNNER/lib/wine/x86_64-windows/kernel32.dll"
# 0041 adds the function's name to kernel32.dll's exports; CrossOver's own does not have it.
carries_fix() { [ -f "$KERNEL32" ] && LC_ALL=C /usr/bin/grep -qa 'FindPackagesByPackageFamily' "$KERNEL32"; }
right_runner() {
  case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *) return 1 ;; esac
  case "$SIDE" in *Rosetta*) return 0 ;; esac
  return 1
}

# The rows get a group of their own on the game's Compatibility page, as F1 25's do
# (install-f125-swofty.sh says how a NotProton that knows groups is told from one that does not).
ROWS="$HERE/np-plugin-fc27-live-editor.conf"
ROWS_GROUP="MacGameFix · FC 27"
np_knows_groups() {
  case "${MGVF_NOTPROTON_GROUPS:-}" in 0) return 1 ;; 1) return 0 ;; esac
  local run
  for run in "$STEAM"/compatibilitytools.d/notproton-*/run; do
    [ -f "$run" ] && LC_ALL=C /usr/bin/grep -qF 'names[i] == "group"' "$run" && return 0
  done
  return 1
}
if np_knows_groups; then
  ROWS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mgf-fc27-rows.XXXXXX")"
  trap 'rm -rf "$ROWS_TMP"' EXIT
  /usr/bin/awk -v group="$ROWS_GROUP" '{ print } /^label[[:space:]]*=/ { print "group = " group }' "$ROWS" > "$ROWS_TMP/np-plugin-fc27-live-editor.conf"
  # The library is looked for beside the template.
  ln -s "$HOOKS" "$ROWS_TMP/mgf-d3dmetal-hookable.dylib"
  ROWS="$ROWS_TMP/np-plugin-fc27-live-editor.conf"
fi
np_plugins_setup "$APPID" "$PFX" "$ROWS"
JOURNAL="$PFX/.mgf-fc27-launch-options.json"

options() { /usr/bin/perl "$OPTIONS" "$1" "$APPID" "$JOURNAL" --wrapper "$STORE/fc27-le-play.sh"; }

# A folder is a Live Editor when it holds its launcher, its DLL and its stand-in.
is_editor() { [ -s "$1/Launcher.exe" ] && [ -s "$1/FCLiveEditor.DLL" ] && [ -s "$1/FakeEAACLauncher/$AC" ]; }
editor_ok() { is_editor "$EDITOR"; }
# The folder as the player gave it, or the one folder inside it that is a Live Editor: the
# download unpacks to a folder of its own, and either is a fair thing to point at.
editor_in() {  # <folder>
  local d="${1%/}" inner found="" n=0
  if is_editor "$d"; then printf '%s\n' "$d"; return 0; fi
  for inner in "$d"/*/; do
    inner="${inner%/}"
    is_editor "$inner" && { found="$inner"; n=$((n+1)); }
  done
  [ "$n" = 1 ] && printf '%s\n' "$found"
}
# macOS's folder chooser, from MacGameFix's window only. Prints the folder, or nothing when the
# player cancels. MGVF_CHOOSER stands in for it in the tests.
ask_folder() {
  local prompt="Choose your FC 27 Live Editor folder: the one that holds Launcher.exe and FCLiveEditor.DLL."
  editor_ok && prompt="$prompt Cancel keeps the Live Editor already in use."
  if [ -n "${MGVF_CHOOSER:-}" ]; then "$MGVF_CHOOSER" "$prompt" 2>/dev/null || true; return 0; fi
  /usr/bin/osascript -e 'on run argv' -e 'try' -e 'return POSIX path of (choose folder with prompt (item 1 of argv))' \
    -e 'on error' -e 'return ""' -e 'end try' -e 'end run' "$prompt" 2>/dev/null || true
}
# The folder this install takes, or nothing when the copy in use stays.
chosen() {
  local d=""
  if [ -n "${MGVF_LIVE_EDITOR:-}" ]; then d="${MGVF_LIVE_EDITOR%/}"
  elif [ "${MGVF_FRONTEND:-}" = app ]; then d="$(ask_folder)"; d="${d%/}"
  fi
  [ -n "$d" ] && printf '%s\n' "$d"
  return 0
}
take_editor() {  # <folder>
  local from="$1"
  if editor_ok && cmp -s "$from/FCLiveEditor.DLL" "$EDITOR/FCLiveEditor.DLL" && cmp -s "$from/Launcher.exe" "$EDITOR/Launcher.exe"; then
    echo "  $from is the Live Editor already in use: kept in $EDITOR"; return 0
  fi
  mkdir -p "$STORE"
  rm -rf "$EDITOR.new"
  ditto "$from" "$EDITOR.new" || { rm -rf "$EDITOR.new"; echo "error: could not copy $from" >&2; return 1; }
  # A copy of a folder that was used elsewhere brings that use's logs along.
  rm -rf "$EDITOR.new/Logs"
  if [ -d "$EDITOR" ]; then rm -rf "$EDITOR.previous"; mv "$EDITOR" "$EDITOR.previous"; echo "  the copy that was in use is kept as $EDITOR.previous"; fi
  mv "$EDITOR.new" "$EDITOR"
  echo "  copied from $from"
}

scripts_ok() { cmp -s "$PLAY" "$STORE/fc27-le-play.sh" && cmp -s "$RUN" "$STORE/fc27-le-run.cmd"; }
scripts_any() { [ -e "$STORE/fc27-le-play.sh" ] || [ -e "$STORE/fc27-le-run.cmd" ]; }

stopped() {
  local rc=0
  bottle_server_alive "$PFX" || rc=$?
  case "$rc" in
  1) return 0 ;;
  0) echo "error: something is running in $PFX." >&2
     echo "       Quit EA SPORTS FC 27 and wait for Steam to show it stopped, then try again. Nothing was changed." >&2 ;;
  *) echo "error: cannot tell whether anything runs in $PFX. Nothing was changed." >&2 ;;
  esac
  return 1
}

case "$MODE" in
--status)
  right_runner || norecipe "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; this needs CrossOver Preview 41303's, on Rosetta"
  echo "looking at $STORE, NotProton's plugins and Steam's launch options"
  have=0; of=4; why=""; old_scripts=0
  miss() { why="${why:+$why; }$1"; }
  editor_ok && have=$((have+1)) || miss "no Live Editor folder in $EDITOR"
  scripts_ok && have=$((have+1)) || { scripts_any && old_scripts=1; miss "the play script is not in place"; }
  wrapped=0; options status >/dev/null 2>&1 && { have=$((have+1)); wrapped=1; } || miss "Steam's launch options do not start the play script"
  # The rows' files only: a row the player switched off is not a broken fix.
  rows="$(np_plugins_status 2>/dev/null | tail -1)"
  [ "$rows" = installed ] && have=$((have+1)) || miss "the game's rows or the library are not in NotProton's plugins folder"
  # Absent is judged by what is only ever this script's: the play script, the launch option and
  # the rows. The Live Editor folder is the player's and stays after a restore.
  if [ "$wrapped" = 0 ] && ! scripts_any && [ "$rows" = absent ]; then echo absent
  elif [ "$have" -eq "$of" ] && carries_fix; then echo installed
  elif [ "$have" -eq "$of" ]; then
    echo "Why: everything is in place, but the runner's kernel32.dll lacks the function the game asks for: update the Rosetta improvement, or the game says \"There is a problem with your game's setup\"" >&2
    echo half
  elif [ "$have" -eq $((of-1)) ] && [ "$old_scripts" = 1 ] && editor_ok; then
    echo "an older play script is in place; installing again brings this one" >&2
    echo outdated
  else
    echo "Why: $why" >&2
    echo half
  fi
  exit 0 ;;
--restore)
  stopped || exit 1
  [ ! -f "$JOURNAL" ] || options preflight >/dev/null || exit 1
  [ ! -f "$JOURNAL" ] || options restore >/dev/null || exit 1
  # After the play script is out of the launch options: the rows' switches are plain variables.
  np_plugins_restore || exit 1
  rm -f "$STORE/fc27-le-play.sh" "$STORE/fc27-le-run.cmd"
  # What a session that was cut short leaves in the game folder: the game's own file, kept by
  # Live Editor's launcher under another name, with the stand-in in its place.
  if [ -f "$GAME/$AC.backup" ]; then
    mv -f "$GAME/$AC.backup" "$GAME/$AC" && echo "  EA AntiCheat's own launcher is back in the game folder (a session had left Live Editor's stand-in there)"
  fi
  echo "restored -- Steam's Play starts EA SPORTS FC 27's own launcher again"
  echo "  your Live Editor folder stays in $EDITOR, and its settings in the prefix; remove them by hand if you want them gone"
  echo restored
  exit 0 ;;
esac

right_runner || refuse "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; this needs CrossOver Preview 41303's, on Rosetta."
carries_fix || refuse "the runner's kernel32.dll ($KERNEL32) lacks the function the game asks for: put in or update the Rosetta improvement for CrossOver Preview 41303 first."
np_plugins_ready || refuse "NotProton's support folder ($NP_SUPPORT) is not there: open NotProton once, then install again."
[ -f "$HOOKS" ] || refuse "mgf-d3dmetal-hookable.dylib is not beside the installer."
stopped || exit 1
# Everything that can refuse without the player's folder does so before the player is asked,
# and everything that can refuse at all before anything is written.
if ! np_plugins_preflight || ! options preflight >/dev/null; then exit 1; fi
GIVEN="$(chosen)"
FROM=""
if [ -n "$GIVEN" ]; then
  FROM="$(editor_in "$GIVEN" || true)"
  [ -n "$FROM" ] || refuse "$GIVEN is not a Live Editor folder: it, or one folder inside it, has to hold Launcher.exe, FCLiveEditor.DLL and FakeEAACLauncher."
elif ! editor_ok; then
  echo "error: no Live Editor folder was given." >&2
  echo "       FC 27 Live Editor is not part of MacGameFix: download it from its author and unpack it," >&2
  if [ "${MGVF_FRONTEND:-}" = app ]; then echo "       then install again and choose the unpacked folder when you are asked." >&2
  else echo "       then install again with MGVF_LIVE_EDITOR=<the unpacked folder>." >&2; fi
  echo "       Nothing was changed." >&2
  exit 1
fi

echo "[1/3] your Live Editor"
if [ -n "$FROM" ]; then take_editor "$FROM" || exit 1
else echo "  kept in $EDITOR"; fi
editor_ok || refuse "the Live Editor folder is not usable in $EDITOR."

echo "[2/3] the play script"
cp "$PLAY" "$STORE/fc27-le-play.sh.new" && chmod 755 "$STORE/fc27-le-play.sh.new" && mv -f "$STORE/fc27-le-play.sh.new" "$STORE/fc27-le-play.sh"
cp "$RUN" "$STORE/fc27-le-run.cmd.new" && mv -f "$STORE/fc27-le-run.cmd.new" "$STORE/fc27-le-run.cmd"

echo "[3/3] NotProton's rows and library, and Steam's launch options"
np_plugins_install || exit 1
options install >/dev/null || exit 1

echo "installed"
echo
echo "  ****************************************************************************"
echo "  *  WARNING: AT YOUR OWN RISK                                               *"
echo "  *  MacGameFix takes no responsibility for failures in the game.            *"
echo "  *  EA SPORTS FC 27 now starts without EA AntiCheat, with FC 27 Live        *"
echo "  *  Editor inside it: a third-party mod tool that you downloaded, that      *"
echo "  *  MacGameFix neither made nor distributes. Offline only. A game that      *"
echo "  *  stops working, a save or career that is lost, or what happens to an     *"
echo "  *  account is not MacGameFix's to answer for. Removing the fix gives       *"
echo "  *  Steam's Play back.                                                      *"
echo "  ****************************************************************************"
echo
echo "  Steam's Play now starts EA SPORTS FC 27 with Live Editor; F9 shows its window in the game."
echo "  The first Play only has Live Editor's launcher write its settings, and asks you to press Play again."
echo "  On the game's Compatibility page in NotProton, \"Play opens\" chooses Live Editor's launcher window instead."
echo "  A new version of Live Editor: download and unpack it, install this again and choose the new folder."
