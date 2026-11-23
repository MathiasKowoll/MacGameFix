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
#      with bit 47 set. Engine patch 0038 (the Rosetta improvement's ntdll.so) keeps such
#      allocations low. This script only checks that the runner has it.
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
# WHAT IT PUTS WHERE.
#   - Swofty Launcher's Windows release, downloaded from Swofty's own index
#     (https://cdn.swofty.net/launcher/latest.json, which names the file, its size and its
#     SHA-256) into ~/Library/Application Support/MacGameFix/swofty/launcher. It is not
#     part of MacGameFix and is not redistributed by it. MGVF_SWOFTY_ZIP names a release
#     .zip already downloaded, to use instead. The launcher updates itself afterwards.
#   - f125-swofty-play.sh and f125-swofty-run.cmd beside it.
#   - In the prefix's user.reg: the version override for F1_25.exe, and ActiveUser.
#   - In the prefix's Steam folder, links to Steam's own files: config/loginusers.vdf, the
#     manifests of the game's installed depots in depotcache/, and logs/content_log.txt.
#     Swofty checks every game file against Steam's list at each start and looks at that
#     log to see that Steam is not changing the game. The prefix that was played had all
#     three; which of the last two Swofty cannot do without is not known.
#   - In Steam's launch options for the game: the play script before %command%
#     (steam-launch-options.pl; Steam must be closed).
#   - In NotProton's plugins folder: two rows for this game alone (notproton-plugins.sh,
#     np-plugin-f125-swofty.conf), shown on its Compatibility page: "Start through Swofty
#     Launcher", switched on by the first install, and "Play opens", the game or Swofty
#     Launcher's window. A NotProton row cannot change the program Steam starts, so the rows
#     load nothing: they are the switches the play script reads.
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
# MGVF-WHY: F1 25 only starts on a Mac through Swofty Launcher, and on NotProton it crashed half a minute in and Swofty could not find Steam. This downloads Swofty from its own site, prepares the game's prefix and makes Steam's Play start the game through it. Offline, without EA AntiCheat or multiplayer. NotProton with CrossOver Preview 41303 (Rosetta) only.
# MGVF-CREDIT: Swofty Launcher, the mod launcher and offline play this starts | https://f1.swofty.net
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
INDEX_URL="${MGVF_SWOFTY_INDEX:-https://cdn.swofty.net/launcher/latest.json}"
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
NTDLL="$RUNNER/lib/wine/x86_64-unix/ntdll.so"
# 0038 carries its switch's name; CrossOver's own ntdll.so and ours before it do not.
carries_fix() { [ -f "$NTDLL" ] && LC_ALL=C /usr/bin/grep -qa 'WINE_LOW_ALLOCATIONS_FIRST' "$NTDLL"; }
right_runner() {
  case "$BUILD" in 27.0.0.41303|27.0.0.41303-fex) ;; *) return 1 ;; esac
  case "$SIDE" in *Rosetta*) return 0 ;; esac
  return 1
}

np_plugins_setup "$APPID" "$PFX" "$HERE/np-plugin-f125-swofty.conf"
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

# Swofty Launcher's Windows release, into $LAUNCHER. Its index names the file with its size
# and SHA-256; the download is checked against both before anything is unpacked.
fetch_launcher() {
  local work rc=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/mgf-swofty.XXXXXX")" || return 1
  fetch_launcher_into "$work" || rc=$?
  rm -rf "$work"
  return "$rc"
}
fetch_launcher_into() {  # <work folder>
  local work="$1" zip name="" url="" sha="" got top
  zip="${MGVF_SWOFTY_ZIP:-}"
  if [ -n "$zip" ]; then
    [ -f "$zip" ] || { echo "error: MGVF_SWOFTY_ZIP names no file: $zip" >&2; return 1; }
    echo "  using $zip"
  else
    echo "  asking $INDEX_URL for the current release"
    curl -fsSL --retry 2 --max-time 60 -o "$work/latest.json" "$INDEX_URL" || {
      echo "error: could not reach Swofty's release index; check the connection and install again" >&2
      return 1
    }
    # name, url and sha256 of the one Windows asset; an index that does not have exactly that is refused.
    read -r name url sha < <(/usr/bin/perl -MJSON::PP -e '
      local $/; my $d = eval { decode_json(<STDIN>) } or exit 1;
      my @a = grep { ($_->{name} // "") =~ /^swofty-launcher-v[0-9][0-9.]*-windows-x86_64\.zip$/ } @{ $d->{assets} || [] };
      exit 1 unless @a == 1;
      my ($n, $u, $s) = @{ $a[0] }{qw(name url sha256)};
      exit 1 unless ($u // "") =~ m{^https://(cdn\.swofty\.net|github\.com/Swofty-Developments/SwoftyLauncher)/[A-Za-z0-9._/-]+$}
                 && ($s // "") =~ /^[0-9a-f]{64}$/;
      print "$n $u $s\n";
    ' < "$work/latest.json") || true
    [ -n "$sha" ] || { echo "error: Swofty's release index does not name a Windows release this understands; nothing was changed" >&2; return 1; }
    echo "  fetching $name (about 90 MB) from ${url%/"$name"}"
    zip="$work/$name"
    curl -fsSL --retry 2 -o "$zip" "$url" || {
      echo "error: could not download $name; check the connection and install again" >&2
      return 1
    }
    got="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || {
      echo "error: the download is not the file the index names (sha256 $got); nothing was changed" >&2
      return 1
    }
  fi
  mkdir "$work/out"
  ditto -x -k "$zip" "$work/out" || { echo "error: could not unpack $(basename "$zip")" >&2; return 1; }
  # The release unpacks to one folder, or straight to bin/ and loader/.
  top="$(find "$work/out" -maxdepth 3 -type f -path '*/bin/swofty.exe' | head -1)"
  [ -z "$top" ] || top="$(dirname "$(dirname "$top")")"
  [ -n "$top" ] && [ -s "$top/bin/swofty.exe" ] && [ -d "$top/loader" ] || {
    echo "error: $(basename "$zip") does not hold bin/swofty.exe and loader/ where expected; nothing was changed" >&2
    return 1
  }
  mkdir -p "$STORE"
  rm -rf "$LAUNCHER.new"
  mv "$top" "$LAUNCHER.new"
  rm -rf "$LAUNCHER"
  mv "$LAUNCHER.new" "$LAUNCHER"
  echo "  kept in $LAUNCHER"
}

case "$MODE" in
--status)
  right_runner || norecipe "the game runs on NotProton's runner for CrossOver $BUILD${SIDE:+ ($SIDE)}; this needs CrossOver Preview 41303's, on Rosetta"
  echo "looking at $PFX, $STORE and Steam's launch options"
  have=0; of=8; why=""
  miss() { why="${why:+$why; }$1"; }
  launcher_ok && have=$((have+1)) || miss "Swofty Launcher is not in $LAUNCHER"
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
  elif [ "$have" -eq "$of" ] && carries_fix; then echo installed
  elif [ "$have" -eq "$of" ]; then
    echo "Why: everything is in place, but the runner's ntdll.so does not keep the game's memory low: update the Rosetta improvement, or the game closes half a minute in" >&2
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
carries_fix || refuse "the runner's ntdll.so ($NTDLL) does not keep the game's memory low: put in or update the Rosetta improvement for CrossOver Preview 41303 first."
ACCOUNT="$(steam_account)" || refuse "cannot tell which account Steam is signed in with ($STEAM_LOGIN): open Steam, sign in, quit it, and install again."
np_plugins_ready || refuse "NotProton's support folder ($NP_SUPPORT) is not there: open NotProton once, then install again."
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

echo "[1/4] Swofty Launcher"
if launcher_ok && [ -z "${MGVF_SWOFTY_ZIP:-}" ]; then echo "  kept in $LAUNCHER"
else fetch_launcher || exit 1; fi
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
echo "  Steam's Play now starts F1 25 through Swofty Launcher, with Swofty's active profile."
echo "  On the game's Compatibility page in NotProton, \"Play opens\" chooses Swofty Launcher's window instead."
echo "  The first Play shows Swofty's offline play terms in a console window and waits for your answer."
