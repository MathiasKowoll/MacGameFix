#!/bin/sh
# F1 25 through Swofty Launcher, from Steam's Play under NotProton. install-f125-swofty.sh keeps
# a copy of this beside the launcher it downloads and puts it in the game's launch options:
#
#   "<store>/f125-swofty-play.sh" %command%
#
# Steam's Play hands NotProton's tool the game's own launcher, EAAntiCheat.GameServiceLauncher.exe,
# which does not run under Wine. This puts Swofty's command line in its place, in the same prefix
# and with what NotProton gives a game: Swofty builds its active profile, starts F1_25.exe and puts
# the game folder back when the game exits.
#
# Two of MacGameFix's shared rows, on the game's Compatibility page in NotProton, decide what it does. NotProton keeps a
# row's value as a variable in the launch options, in front of this script, so the script
# finds it in its environment (each game's options are its own):
#   NOTPROTON_MGF_MODTOOL=1     "Start through the mod tool", a row MacGameFix's games share.
#                               Without it, Steam's own command runs unchanged.
#   NOTPROTON_MGF_PLAY=window   "Play opens": Swofty Launcher's window instead of the game.
#   NOTPROTON_MGF_PLAY=nomods   "Play opens": the game with Swofty's profile without addons.
#   NOTPROTON_MGF_PLAY=notes    "Play opens": the game, with Wine writing every exception it
#                               raises to NotProton's Wine log, for a report.
#                               Anything else, or nothing: the game with the active profile.
#
# Anything else Steam runs through the tool, such as its install scripts, goes through unchanged.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
here="$(cd "$(dirname "$0")" && pwd)"
tool="$1"; verb="$2"; game="$3"
if [ "$verb" != waitforexitandrun ] || [ ! -f "$here/launcher/bin/swofty.exe" ] || [ ! -f "$here/f125-swofty-run.cmd" ]; then
  exec "$@"
fi
case "$game" in */EAAntiCheat.GameServiceLauncher.exe|*/F1_25.exe) ;; *) exec "$@" ;; esac
app="${STEAM_COMPAT_APP_ID:-}"
case "$app" in ""|*[!0-9]*) exec "$@" ;; esac
switch="${NOTPROTON_MGF_MODTOOL:-}"; play="${NOTPROTON_MGF_PLAY:-game}"
opens=game; profile=active; notes=off
case "$play" in window) opens=window ;; nomods) profile=vanilla ;; notes) notes=on ;; esac
[ "$switch" = 1 ] || exec "$@"
# A path as the prefix sees it: the Steam library on the drive NotProton gives it there (S: so
# far, read from the prefix's dosdevices), anything else under Z:.
library="${STEAM_COMPAT_DATA_PATH%/steamapps/compatdata/*}"
drive=""
for link in "$STEAM_COMPAT_DATA_PATH"/pfx/dosdevices/?:; do
  [ -L "$link" ] && [ "$(readlink "$link")" = "$library" ] && { drive="$(printf '%s' "${link##*/}" | tr a-z A-Z)"; break; }
done
windows() {
  case "$1" in
  "$library"/*) [ -n "$drive" ] && { printf '%s\\%s' "$drive" "$(printf '%s' "${1#"$library"/}" | tr / '\\')"; return; } ;;
  esac
  printf 'Z:%s' "$(printf '%s' "$1" | tr / '\\')"
}
# What f125-swofty-run.cmd reads. NOTPROTON_ENV_<NAME> is how NotProton hands a variable to the
# game however it starts it; a plain variable does not survive every route.
# Steam's own command for the game goes to Swofty after "--", as Steam on Windows hands it to a
# launch option.
export NOTPROTON_ENV_F125_STEAM_COMMAND="$(windows "$game")"
if [ "$opens" = window ]; then
  # The launcher's window draws to a plain window: Wine's DirectComposition gives it nothing.
  export NOTPROTON_ENV_F125_OPENS=window NOTPROTON_ENV_GPUI_DISABLE_DIRECT_COMPOSITION=1
fi
# A profile's name goes to Swofty as it is; "active" is the row's word for none given.
case "$profile" in ""|active|*[!A-Za-z0-9._-]*) ;; *) export NOTPROTON_ENV_F125_PROFILE="$profile" ;; esac
# The two settings every session played so far had (CrossOver bottle and NotProton, 2026-11-23).
export NOTPROTON_ENV_SWOFTY_ARM_SYNC="${SWOFTY_ARM_SYNC:-1}" NOTPROTON_ENV_SWOFTY_RTAS_GUARD="${SWOFTY_RTAS_GUARD:-0}"
# NotProton's Steam stub starts a program by name or Windows path, not a .cmd by its unix path.
[ "$notes" != on ] || export WINEDEBUG="err+all,fixme-all,+seh,+timestamp,+pid"
exec "$tool" "$verb" cmd.exe /d /c call "$(windows "$here/f125-swofty-run.cmd")"
