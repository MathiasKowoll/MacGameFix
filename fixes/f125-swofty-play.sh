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
# F1_PROFILE=<name> before it in the launch options plays another Swofty profile for that run
# (vanilla is the one without addons). Anything else Steam runs through the tool, such as its
# install scripts, goes through unchanged.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
here="$(cd "$(dirname "$0")" && pwd)"
tool="$1"; verb="$2"; game="$3"
if [ "$verb" != waitforexitandrun ] || [ ! -f "$here/launcher/bin/swofty.exe" ] || [ ! -f "$here/f125-swofty-run.cmd" ]; then
  exec "$@"
fi
case "$game" in */EAAntiCheat.GameServiceLauncher.exe|*/F1_25.exe) ;; *) exec "$@" ;; esac
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
[ -z "${F1_PROFILE:-}" ] || export NOTPROTON_ENV_F125_PROFILE="$F1_PROFILE"
# The two settings every session played so far had (CrossOver bottle and NotProton, 2026-11-23).
export NOTPROTON_ENV_SWOFTY_ARM_SYNC="${SWOFTY_ARM_SYNC:-1}" NOTPROTON_ENV_SWOFTY_RTAS_GUARD="${SWOFTY_RTAS_GUARD:-0}"
# NotProton's Steam stub starts a program by name or Windows path, not a .cmd by its unix path.
exec "$tool" "$verb" cmd.exe /d /c call "$(windows "$here/f125-swofty-run.cmd")"
