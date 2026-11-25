#!/usr/bin/env bash
#
# Install (or remove) what F1 25 needs to start through Swofty Launcher from Steam's Play.
#
#   install-f125-swofty.sh <game folder>            install
#   install-f125-swofty.sh <game folder> --status   report
#   install-f125-swofty.sh <game folder> --restore  remove
#
# The prefix is MGVF_BOTTLE: the Steam Play prefix NotProton keeps for the game,
#   .../steamapps/compatdata/3059520/pfx
#
# AT YOUR OWN RISK. MacGameFix takes no responsibility for failures in the game: this starts
# it without EA AntiCheat, through a third-party mod launcher that changes the game's files
# while it runs. MacGameFix made neither Swofty Launcher nor its offline play nor any mod, and
# does not answer for a game that stops working or a save that is lost. The install says so
# before it ends, and f125-instructions.md opens with it.
#
# NOTHING IN THE GAME FOLDER IS TOUCHED by this script. Swofty itself changes the game
# folder while a session runs and puts it back when the game exits.
#
# WHAT THIS IS FOR. F1 25 starts through EA AntiCheat's launcher, which does not run under
# Wine, so on a Mac the game only starts through Swofty Launcher (https://f1.swofty.net), a
# mod launcher whose sessions are offline and without EA AntiCheat. Swofty is made for
# Windows, and for Linux with Proton. On a Mac with NotProton, four things were in the way
# (2026-11-23, NotProton's runner for CrossOver Preview 41303, Rosetta):
#
#   1. Wine 11.21 gave the game addresses from 0x7ff000000000 up once its 6.5 GB image had
#      filled the low reserved area, and the game crashed some 30 s after start on a pointer
#      with bit 47 set. MacGameFix's engine library (engine/mgf-engine.c), which NotProton
#      loads through the shared "Engine fixes" row and which arms its fix for this game alone,
#      keeps such allocations low (engine/low-allocations/mgf-low-allocations.c). It
#      does from outside ntdll.so what engine patch 0038 does inside it for every game, so the
#      runner need not carry 0038, and NotProton's own ntdll.so does as well as ours.
#   2. Swofty's mod loader is a version.dll beside the game; Wine loads its own unless
#      F1_25.exe has the override version=native,builtin.
#   3. Swofty wants Steam running and signed in: it reads ActiveProcess\pid and ActiveUser
#      under HKCU\Software\Valve\Steam and config\loginusers.vdf in Steam's folder.
#      NotProton's Steam stub writes the pid while Steam's Play runs the game, but no
#      ActiveUser, and its Steam folder has no loginusers.vdf.
#   4. Steam's Play has to start Swofty instead of EA AntiCheat's launcher, in the game's
#      prefix. f125-swofty-play.sh does that from the launch options; f125-swofty-run.cmd
#      says why it goes through cmd.exe.
#
# SWOFTY LAUNCHER IS THE PLAYER'S TO PROVIDE. It is not part of MacGameFix, and nothing here
# downloads it: the player downloads its Windows release from Swofty's site
# (https://f1.swofty.net). While no launcher is kept, the install ASKS where that download is,
# with macOS's file chooser, from MacGameFix's window: the .zip, or, where the browser unpacked
# it, swofty.exe in its bin folder. Cancel changes nothing. The launcher updates itself
# afterwards, so an install with one kept asks nothing and the agent can run it. From a
# terminal nothing is asked: MGVF_SWOFTY names the .zip, the unpacked folder or its swofty.exe,
# and takes the place of a launcher kept before.
#
# WHAT IT PUTS WHERE.
#   - The Swofty Launcher the player gave, copied into
#     ~/Library/Application Support/MacGameFix/swofty/launcher.
#   - f125-swofty-play.sh and f125-swofty-run.cmd beside it.
#   - In the prefix's user.reg: the version override for F1_25.exe, and ActiveUser.
#   - In the prefix's Steam folder, links to Steam's own files: config/loginusers.vdf, the
#     manifests of the game's installed depots in depotcache/, and logs/content_log.txt.
#     Swofty checks every game file against Steam's list at each start and looks at that
#     log to see that Steam is not changing the game. The prefix that was played had all
#     three; which of the last two Swofty cannot do without is not known.
#   - In Steam's launch options for the game: the play script before %command%
#     (steam-launch-options.pl; Steam must be closed).
#   - In NotProton's plugins folder: no row of its own. The game is added to MacGameFix's shared
#     rows (notproton-plugins.sh, np-plugin-shared.conf, plugins/mgf-shared.conf), shown on its
#     Compatibility page with every game that uses them: "Engine fixes", whose library,
#     mgf-engine.dylib, keeps the game's memory low; "Start through the mod tool", the switch the
#     play script reads; and "Play opens", the game with Swofty's active profile, the game without
#     mods, the game with Wine's exception notes, or Swofty Launcher's window. The two switches go
#     on by the install that first brings them. A NotProton row cannot change the program Steam
#     starts, so the switch is one the play script reads. Whatever a player may set is a row:
#     nothing is typed into the launch options by hand. The library needs NotProton's plugin
#     host, which NotProton's Update installs; the install refuses without it. An earlier
#     install's rows of its own and mgf-low-allocations.dylib are taken out.
# .mgf-f125-swofty in the prefix lists which of these this script added, and --restore
# removes those. The launcher, its data in the prefix and its saves stay.
#
# WHAT IT DOES NOT DO. Swofty's offline play has terms the player reads and accepts, and an
# extension Swofty downloads itself: the first Play shows the terms in a console window and
# waits for the answer. Nothing here accepts them, and nothing here reads, changes or copies
# that extension.
#
# Played on 2026-11-23 with these steps done by hand: the modded profile reached the menu
# and a race from Steam's Play, the game's objects at 0x4.., 0x5.. and 0x6...
#
# MGVF-SCOPE: prefix
# MGVF-NEEDS: rosetta
# MGVF-GAME: F1 25 | F1_25.exe |
# MGVF-TESTING: Mathias Kowoll
# MGVF-INSTRUCTIONS: f125-instructions.md
# MGVF-WHY: F1 25 only starts on a Mac through Swofty Launcher, a mod launcher you download yourself, and on NotProton it crashed half a minute in and Swofty could not find Steam. This asks you where your Swofty download is and copies it, keeps the game's memory where it does not crash, for this game alone, prepares the game's prefix and makes Steam's Play start the game through it. Offline, without EA AntiCheat or multiplayer. NotProton with CrossOver Preview 41303 (Rosetta) only. AT YOUR OWN RISK: MacGameFix does not answer for failures in the game, its saves or its mods.
# MGVF-CREDIT: Swofty Launcher, the mod launcher and offline play this starts and does not include | https://f1.swofty.net
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

[ -f "$GAME/F1_25.exe" ] || {
  echo "error: no F1_25.exe in $GAME" >&2
  echo "       Pick the folder F1 25 is installed in." >&2
  exit 1
}

APPID=3059520
PLAY="$HERE/f125-swofty-play.sh"
RUN="$HERE/f125-swofty-run.cmd"
OPTIONS="$HERE/steam-launch-options.pl"
ENGINE="$HERE/mgf-engine.dylib"
SHARED_ROWS="$HERE/np-plugin-shared.conf"
STORE="${MGVF_SWOFTY_STORE:-$HOME/Library/Application Support/MacGameFix/swofty}"
LAUNCHER="$STORE/launcher"
STEAM="${MGVF_STEAM_ROOT:-$HOME/Library/Application Support/Steam}"
OVERRIDE_KEY='Software\Wine\AppDefaults\F1_25.exe\DllOverrides'
ACTIVE_KEY='Software\Valve\Steam\ActiveProcess'

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
right_runner() {
  case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *) return 1 ;; esac
  case "$SIDE" in *Rosetta*) return 0 ;; esac
  return 1
}

# The shared rows get the group "MacGameFix" on the game's Compatibility page where NotProton
# knows groups: a NotProton that does not refuses a row that names one, so the tool's own reader
# is asked (its run script checks the field by name). MGVF_NOTPROTON_GROUPS=0 or 1 answers for a
# test.
ROWS="$HERE/np-plugin-f125-swofty.conf"
np_knows_groups() {
  case "${MGVF_NOTPROTON_GROUPS:-}" in 0) return 1 ;; 1) return 0 ;; esac
  local run
  for run in "$STEAM"/compatibilitytools.d/notproton-*/run; do
    [ -f "$run" ] && LC_ALL=C /usr/bin/grep -qF 'names[i] == "group"' "$run" && return 0
  done
  return 1
}
np_plugins_setup "$APPID" "$PFX" "$ROWS"
# The game's rows are MacGameFix's shared ones (np-plugin-shared.conf), in the group
# "MacGameFix" where NotProton knows groups.
NP_SHARED_TEMPLATE="$SHARED_ROWS"; NP_SHARED_LIBRARY="$ENGINE"
NP_SHARED_USES="NOTPROTON_MGF_ENGINE NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_PLAY"
if np_knows_groups; then NP_SHARED_GROUP="MacGameFix"; fi
NP_WRAPPER="$STORE/f125-swofty-play.sh"
# NotProton loads a row's library through its plugin host; without it the row is not offered.
host_ok() { [ -f "$NP_SUPPORT/plugin-host.dylib" ]; }
JOURNAL="$PFX/.mgf-f125-launch-options.json"
STATE="$PFX/.mgf-f125-swofty"          # what this script added, one word a line
BRIDGE="$PFX/drive_c/Program Files (x86)/Steam"
LOGIN="$BRIDGE/config/loginusers.vdf"
STEAM_LOGIN="$STEAM/config/loginusers.vdf"

added() { [ -f "$STATE" ] && /usr/bin/grep -qxF "$1" "$STATE"; }
note() { added "$1" || echo "$1" >> "$STATE"; }
options() { /usr/bin/perl "$OPTIONS" "$1" "$APPID" "$JOURNAL" --wrapper "$STORE/f125-swofty-play.sh"; }

# The account Steam last signed in: loginusers.vdf's entry with MostRecent 1, else its only
# one. An account id is the low 32 bits of the 64-bit Steam id that names the entry.
steam_account() {
  [ -f "$STEAM_LOGIN" ] || return 1
  /usr/bin/perl -e '
    use strict; use warnings; local $/; my $s = <STDIN>; my (@ids, $recent);
    while ($s =~ /"(7656\d{13})"\s*\{([^{}]*)\}/g) {
      push @ids, $1; $recent = $1 if $2 =~ /"MostRecent"\s+"1"/i;
    }
    $recent //= $ids[0] if @ids == 1;
    exit 1 unless defined $recent;
    print $recent - 76561197960265728, "\n";
  ' < "$STEAM_LOGIN"
}

# The game's installed depots as Steam names their manifests: <depot>_<manifest>.manifest.
APPMANIFEST="$(dirname "$(dirname "$(dirname "$PFX")")")/appmanifest_$APPID.acf"
depot_manifests() {
  [ -f "$APPMANIFEST" ] || return 0
  /usr/bin/awk -F'"' '
    $2 == "InstalledDepots" { inside = 1; next }
    inside && /^\t}/ { exit }
    inside && $2 ~ /^[0-9]+$/ && $4 == "" { depot = $2; next }
    inside && $2 == "manifest" && $4 ~ /^[0-9]+$/ { print depot "_" $4 ".manifest" }
  ' "$APPMANIFEST"
}
# Every list Steam has is reachable from the prefix's Steam folder.
lists_ok() {
  local name
  while IFS= read -r name; do
    [ ! -f "$STEAM/depotcache/$name" ] || [ -e "$BRIDGE/depotcache/$name" ] || return 1
  done < <(depot_manifests)
  [ ! -f "$STEAM/logs/content_log.txt" ] || [ -e "$BRIDGE/logs/content_log.txt" ]
}
link_lists() {
  local name
  mkdir -p "$BRIDGE/depotcache" "$BRIDGE/logs"
  while IFS= read -r name; do
    if [ -f "$STEAM/depotcache/$name" ] && [ ! -e "$BRIDGE/depotcache/$name" ] && [ ! -L "$BRIDGE/depotcache/$name" ]; then
      ln -s "$STEAM/depotcache/$name" "$BRIDGE/depotcache/$name"; note "depot:$name"
    fi
  done < <(depot_manifests)
  if [ -f "$STEAM/logs/content_log.txt" ] && [ ! -e "$BRIDGE/logs/content_log.txt" ] && [ ! -L "$BRIDGE/logs/content_log.txt" ]; then
    ln -s "$STEAM/logs/content_log.txt" "$BRIDGE/logs/content_log.txt"; note contentlog
  fi
}
unlink_lists() {
  local line
  [ -f "$STATE" ] || return 0
  while IFS= read -r line; do
    case "$line" in
    depot:*) [ ! -L "$BRIDGE/depotcache/${line#depot:}" ] || rm -f "$BRIDGE/depotcache/${line#depot:}" ;;
    contentlog) [ ! -L "$BRIDGE/logs/content_log.txt" ] || rm -f "$BRIDGE/logs/content_log.txt" ;;
    esac
  done < "$STATE"
}

launcher_ok() { [ -s "$LAUNCHER/bin/swofty.exe" ] && [ -d "$LAUNCHER/loader" ]; }
scripts_ok() { cmp -s "$PLAY" "$STORE/f125-swofty-play.sh" && cmp -s "$RUN" "$STORE/f125-swofty-run.cmd"; }
scripts_any() { [ -e "$STORE/f125-swofty-play.sh" ] || [ -e "$STORE/f125-swofty-run.cmd" ]; }
login_ok() { [ -e "$LOGIN" ]; }
# 0 there, 1 not there, 2 the file cannot say (something runs in the prefix).
reg_has() { local rc=0; user_reg_has_value "$PFX" "$1" "$2" || rc=$?; return "$rc"; }

stopped() {
  local rc=0
  bottle_server_alive "$PFX" || rc=$?
  case "$rc" in
  1) return 0 ;;
  0) echo "error: something is running in $PFX." >&2
     echo "       Quit F1 25 and wait for Swofty to put the game folder back, then try again. Nothing was changed." >&2 ;;
  *) echo "error: cannot tell whether anything runs in $PFX. Nothing was changed." >&2 ;;
  esac
  return 1
}

# macOS's file chooser, from MacGameFix's window only. Prints the path, or nothing when the
# player cancels. MGVF_CHOOSER stands in for it in the tests.
ask_download() {
  local prompt="Where is your Swofty Launcher download? Choose the Windows release .zip from f1.swofty.net, or, if your browser unpacked it, swofty.exe in its bin folder."
  if [ -n "${MGVF_CHOOSER:-}" ]; then "$MGVF_CHOOSER" "$prompt" 2>/dev/null || true; return 0; fi
  /usr/bin/osascript -e 'on run argv' -e 'try' -e 'return POSIX path of (choose file with prompt (item 1 of argv))' \
    -e 'on error' -e 'return ""' -e 'end try' -e 'end run' "$prompt" 2>/dev/null || true
}
# What this install takes the launcher from, or nothing when the one kept stays (or none is
# given). The window asks only while no launcher is kept.
chosen() {
  local d=""
  if [ -n "${MGVF_SWOFTY:-}" ]; then d="$MGVF_SWOFTY"
  elif ! launcher_ok && [ "${MGVF_FRONTEND:-}" = app ]; then d="$(ask_download)"
  fi
  d="${d%/}"
  [ -n "$d" ] && printf '%s\n' "$d"
  return 0
}
# The launcher's folder in what the player gave: the one that holds bin/swofty.exe and loader/.
# A .zip is unpacked into <work> first. Nothing when there is not exactly one.
launcher_in() {  # <given> <work>
  local from="$1" work="$2" found
  case "$from" in
  *.zip|*.ZIP)
    mkdir -p "$work/out"
    ditto -x -k "$from" "$work/out" || return 0
    from="$work/out" ;;
  *.exe|*.EXE) from="$(dirname "$(dirname "$from")")" ;;
  esac
  [ -d "$from" ] || return 0
  found="$(find "$from" -maxdepth 3 -type f -path '*/bin/swofty.exe' 2>/dev/null)"
  [ "$(printf '%s' "$found" | /usr/bin/grep -c .)" = 1 ] || return 0
  found="$(dirname "$(dirname "$found")")"
  [ -s "$found/bin/swofty.exe" ] && [ -d "$found/loader" ] && printf '%s\n' "$found"
  return 0
}
take_launcher() {  # <launcher folder>
  mkdir -p "$STORE"
  rm -rf "$LAUNCHER.new"
  ditto "$1" "$LAUNCHER.new" || { rm -rf "$LAUNCHER.new"; echo "error: could not copy $1" >&2; return 1; }
  rm -rf "$LAUNCHER"
  mv "$LAUNCHER.new" "$LAUNCHER"
  echo "  copied into $LAUNCHER"
}

case "$MODE" in
--status)
  right_runner || norecipe "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; this needs CrossOver Preview 41303's, on Rosetta"
  echo "looking at $PFX, $STORE and Steam's launch options"
  have=0; of=8; why=""
  miss() { why="${why:+$why; }$1"; }
  launcher_ok && have=$((have+1)) || miss "Swofty Launcher is not in $LAUNCHER: install again and choose your Swofty download"
  scripts_ok && have=$((have+1)) || { scripts_any && old_scripts=1; miss "the play script is not in place"; }
  o=0; reg_has "$OVERRIDE_KEY" version || o=$?
  [ "$o" = 1 ] && miss "F1_25.exe has no version override" || have=$((have+1))
  a=0; reg_has "$ACTIVE_KEY" ActiveUser || a=$?
  [ "$a" = 1 ] && miss "the prefix does not name Steam's signed-in user" || have=$((have+1))
  login_ok && have=$((have+1)) || miss "the prefix's Steam folder has no loginusers.vdf"
  lists_ok && have=$((have+1)) || miss "the prefix's Steam folder does not reach Steam's lists of the game's files"
  wrapped=0; options status >/dev/null 2>&1 && { have=$((have+1)); wrapped=1; } || miss "Steam's launch options do not start the play script"
  # The rows' files only: a row the player switched off is not a broken fix.
  rows="$(np_plugins_status 2>/dev/null | tail -1)"
  [ "$rows" = installed ] && have=$((have+1)) || miss "the game's rows are not in NotProton's plugins folder"
  # Absent is judged by what is only ever this script's: the play script, the launch option, the
  # rows and its own list. The launcher stays after a restore, and a value the user had is not ours.
  if [ "$wrapped" = 0 ] && ! scripts_any && [ ! -f "$STATE" ] && [ "$rows" = absent ]; then echo absent
  elif [ "$have" -eq "$of" ] && host_ok; then echo installed
  elif [ "$have" -eq "$of" ]; then
    echo "Why: everything is in place, but NotProton's plugin host is not, so the row that keeps the game's memory low is not offered: update NotProton, or the game closes half a minute in" >&2
    echo half
  elif [ "$have" -eq $((of-1)) ] && [ "${old_scripts:-0}" = 1 ] && launcher_ok; then
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
  if added version; then user_reg_edit "$PFX" delete "$OVERRIDE_KEY" version || { echo "error: could not take the override out of $PFX/user.reg" >&2; exit 1; }; fi
  if added activeuser; then user_reg_edit "$PFX" delete "$ACTIVE_KEY" ActiveUser || { echo "error: could not take ActiveUser out of $PFX/user.reg" >&2; exit 1; }; fi
  if added loginusers && [ -L "$LOGIN" ]; then rm -f "$LOGIN"; fi
  unlink_lists
  # After the play script is out of the launch options: the rows' switches are plain variables.
  np_plugins_restore || exit 1
  rm -f "$STORE/f125-swofty-play.sh" "$STORE/f125-swofty-run.cmd" "$STATE"
  echo "restored -- Steam's Play starts F1 25's own launcher again"
  echo "  Swofty Launcher stays in $LAUNCHER, and its data and saves in the prefix; remove them by hand if you want them gone"
  echo restored
  exit 0 ;;
esac

right_runner || refuse "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; this needs CrossOver Preview 41303's, on Rosetta."
ACCOUNT="$(steam_account)" || refuse "cannot tell which account Steam is signed in with ($STEAM_LOGIN): open Steam, sign in, quit it, and install again."
np_plugins_ready || refuse "NotProton's support folder ($NP_SUPPORT) is not there: open NotProton once, then install again."
host_ok || refuse "NotProton's plugin host ($NP_SUPPORT/plugin-host.dylib) is not there, and the row that keeps the game's memory low needs it: update NotProton, then install again."
[ -f "$ENGINE" ] && [ -f "$SHARED_ROWS" ] || refuse "mgf-engine.dylib and np-plugin-shared.conf are not beside the installer."
stopped || exit 1
# Everything that can refuse does so before anything is written.
mkdir -p "$STORE"
# The rows' switch goes into the launch options the first time, by an editor that takes a
# program there for someone else's. An install from before the rows left the play script
# there: it comes out for the moment and goes back in below.
lifted=0
if [ ! -f "$NP_SWITCHED" ] && [ -f "$JOURNAL" ] && options status >/dev/null 2>&1; then
  options restore >/dev/null || exit 1
  lifted=1
fi
if ! np_plugins_preflight || ! options preflight >/dev/null; then
  [ "$lifted" = 0 ] || options install >/dev/null || true
  exit 1
fi
# The player's download, asked for after everything else that can refuse without it.
put_back() { [ "$lifted" = 0 ] || options install >/dev/null || true; }
GIVEN="$(chosen)"
FROM=""
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mgf-swofty.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
if [ -n "$GIVEN" ]; then
  FROM="$(launcher_in "$GIVEN" "$WORK")"
  [ -n "$FROM" ] || { put_back; refuse "$GIVEN is not Swofty Launcher's Windows release: it, or one folder in it, has to hold bin/swofty.exe and loader/."; }
elif ! launcher_ok; then
  put_back
  echo "error: no Swofty Launcher was given." >&2
  echo "       Swofty Launcher is not part of MacGameFix: download its Windows release from https://f1.swofty.net," >&2
  if [ "${MGVF_FRONTEND:-}" = app ]; then echo "       then install again and choose the download when you are asked." >&2
  else echo "       then install again with MGVF_SWOFTY=<the .zip, or the unpacked folder>." >&2; fi
  echo "       Nothing was changed." >&2
  exit 1
fi

echo "[1/4] Swofty Launcher"
if [ -n "$FROM" ]; then take_launcher "$FROM" || exit 1
else echo "  kept in $LAUNCHER"; fi
launcher_ok || refuse "Swofty Launcher is not usable in $LAUNCHER."

echo "[2/4] the play script"
cp "$PLAY" "$STORE/f125-swofty-play.sh.new" && chmod 755 "$STORE/f125-swofty-play.sh.new" && mv -f "$STORE/f125-swofty-play.sh.new" "$STORE/f125-swofty-play.sh"
cp "$RUN" "$STORE/f125-swofty-run.cmd.new" && mv -f "$STORE/f125-swofty-run.cmd.new" "$STORE/f125-swofty-run.cmd"

echo "[3/4] the game's prefix"
o=0; reg_has "$OVERRIDE_KEY" version || o=$?
if [ "$o" = 1 ]; then
  user_reg_edit "$PFX" set "$OVERRIDE_KEY" version native,builtin || { echo "error: could not write the override into $PFX/user.reg" >&2; exit 1; }
  note version
fi
a=0; reg_has "$ACTIVE_KEY" ActiveUser || a=$?
if [ "$a" = 1 ]; then
  user_reg_edit "$PFX" setdword "$ACTIVE_KEY" ActiveUser "$ACCOUNT" || { echo "error: could not write ActiveUser into $PFX/user.reg" >&2; exit 1; }
  note activeuser
fi
if ! login_ok; then
  mkdir -p "$BRIDGE/config"
  ln -s "$STEAM_LOGIN" "$LOGIN"
  note loginusers
fi
link_lists

echo "[4/4] NotProton's rows and Steam's launch options"
np_plugins_install || exit 1
options install >/dev/null || exit 1

echo "installed"
echo
echo "  ****************************************************************************"
echo "  *  WARNING: AT YOUR OWN RISK                                               *"
echo "  *  MacGameFix takes no responsibility for failures in the game.            *"
echo "  *  F1 25 now starts without EA AntiCheat, through Swofty Launcher, a       *"
echo "  *  third-party mod launcher that changes the game's files while it runs.   *"
echo "  *  A game that stops working, or a save or career that is lost, is not     *"
echo "  *  MacGameFix's to answer for. Removing the fix gives Steam's Play back.   *"
echo "  ****************************************************************************"
echo
echo "  Steam's Play now starts F1 25 through Swofty Launcher, with Swofty's active profile."
echo "  On the game's Compatibility page in NotProton, \"Play opens\" chooses the game without mods, or Swofty Launcher's window."
echo "  The first Play shows Swofty's offline play terms in a console window and waits for your answer."
