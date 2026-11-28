#!/usr/bin/env bash
#
# The NotProton rows MacGameFix keeps for every game, whether or not a game's fix uses them:
# "Engine fixes" and the library it loads (np-plugin-shared.conf, "# every game = ").
#
#   notproton-every-game.sh             install: Steam and NotProton have to be closed
#   notproton-every-game.sh --status    installed, half, absent, or unavailable
#   notproton-every-game.sh --restore   the rows out, unless a game's fix uses them
#   notproton-every-game.sh --adopt     rows a game's fix already put in, taken as installed
#
# WHY. Engine fixes is on every game's page so that a game no fix knows can have it switched on:
# one with Denuvo needs Rosetta's CPU as its copy protection expects it. The row was written
# only by the installer of a game whose fix uses it, so whoever had installed none of those
# fixes had no row to switch on. This installs it for every Mac with NotProton, from MacGameFix's
# app (Improvements, NotProton plugins) or by hand. It is the same file and the same writer the
# games' installers use (notproton-plugins.sh, "THE ROWS KEPT FOR EVERY GAME"): a game's fix
# installed before or after finds the row there and adds its own.
#
# The row is off until it is switched on for a game, in the game's Compatibility page in Steam.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

# No "set -u": the library reads its game's templates as an array, empty here, which the
# system's bash 3.2 takes for unset.
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
case "$MODE" in ""|--status|--restore|--adopt) ;; *) sed -n '3,10p' "$0" >&2; exit 1 ;; esac

. "$HERE/notproton-plugins.sh"
NP_SHARED_TEMPLATE="$HERE/np-plugin-shared.conf"; NP_SHARED_LIBRARY="$HERE/mgf-engine.dylib"
# The group "MacGameFix" where NotProton knows groups, as the games' installers decide it.
for run in "${MGVF_STEAM_ROOT:-$HOME/Library/Application Support/Steam}"/compatibilitytools.d/notproton-*/run; do
  [ -f "$run" ] && LC_ALL=C /usr/bin/grep -qF 'names[i] == "group"' "$run" && NP_SHARED_GROUP="MacGameFix"
done
case "${MGVF_NOTPROTON_GROUPS:-}" in 0) NP_SHARED_GROUP="" ;; 1) NP_SHARED_GROUP="MacGameFix" ;; esac

case "$MODE" in
--status) np_every_status ;;
--restore) np_every_restore || exit 1; np_every_kept; echo "Restored." ;;
--adopt) np_every_adopt || exit 1; echo "Adopted." ;;
*) np_every_install || exit 1; echo "Installed." ;;
esac
