#!/bin/sh
# EA SPORTS FC 27 with FC 27 Live Editor, from Steam's Play under NotProton.
# install-fc27-live-editor.sh keeps a copy of this beside the Live Editor folder the player
# provided and puts it in the game's launch options:
#
#   "<store>/fc27-le-play.sh" %command%
#
# Steam's Play hands NotProton's tool the link steam2ea://launchgame/..., which the EA app in
# the prefix takes: it checks the licence and starts EAAntiCheat.GameServiceLauncher.exe. That
# launcher ends after 10 s with 0xE111000B and starts no game under Wine (2026-11-23). With
# Live Editor's launcher open, the file the EA app starts is Live Editor's stand-in, which
# starts FC27.exe, and its DLL goes into the game. This puts the batch file that does it in
# the place of Steam's command; fc27-le-run.cmd says what it does and why.
#
# Two rows on the game's Compatibility page in NotProton decide what happens. NotProton keeps
# a row's value as a variable in the launch options, in front of this script, so the script
# finds it in its environment (the app id is part of the name):
#   NOTPROTON_MGF_FC27_LE_<appid>=1          "Start with Live Editor". Without it, Steam's own
#                                            command runs unchanged. The same row has NotProton
#                                            load mgf-d3dmetal-hookable.dylib into the game.
#   NOTPROTON_MGF_FC27_OPENS_<appid>=window  "Play opens": Live Editor's launcher window alone.
#                                            Anything else, or nothing: the game.
#
# FC27_TRACE=1 before it in the launch options has Wine write every exception the game raises,
# with times, to NotProton's Wine log for the game (launchers/<appid>/notproton-wine.log): what
# a report of a game that closes needs. A Wine process gets its parent's unix environment, so
# it reaches FC27.exe through the EA app.
#
# Anything else Steam runs through the tool goes through unchanged.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
here="$(cd "$(dirname "$0")" && pwd)"
tool="$1"; verb="$2"; target="$3"
if [ "$verb" != waitforexitandrun ] || [ ! -f "$here/LiveEditor/Launcher.exe" ] || [ ! -f "$here/fc27-le-run.cmd" ]; then
  exec "$@"
fi
case "$target" in steam2ea://launchgame/*) ;; *) exec "$@" ;; esac
app="${STEAM_COMPAT_APP_ID:-}"
case "$app" in ""|*[!0-9]*) exec "$@" ;; esac
eval "switch=\${NOTPROTON_MGF_FC27_LE_$app:-}; opens=\${NOTPROTON_MGF_FC27_OPENS_$app:-game}"
[ "$switch" = 1 ] || exec "$@"

# Live Editor's launcher keeps its settings in the prefix, in C:\FC 27 Live Editor\le_config.json,
# which it writes when it closes. Two of them matter here, and both are its own to set:
#   dll_inject_delay  how long after FC27.exe appears the DLL goes in, 100 ms as it comes. At
#                     that the game's first thread and the injected one waited on each other
#                     for good in 2 starts of 10 ("Injecting", 0% CPU, loader_section in the
#                     Wine log); at 1000 ms in none of 6. Raised to 1000 when it is lower.
#   auto_inject       the launcher injects by itself when the game appears. The game does not
#                     run with the stand-in alone (it ends 9 s in), so playing needs it on.
# Before the launcher has run once the file is not there: fc27-le-run.cmd has it made first.
config="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/FC 27 Live Editor/le_config.json"
if [ -f "$config" ] && [ "$opens" != window ]; then
  /usr/bin/perl -0pi -e 's/("dll_inject_delay"\s*:\s*)(\d+)/$1 . ($2 < 1000 ? 1000 : $2)/e; s/("auto_inject"\s*:\s*)false/${1}true/' "$config"
fi

# A path as the prefix sees it: anything outside it is under Z:.
windows() { printf 'Z:%s' "$(printf '%s' "$1" | tr / '\\')"; }
# What fc27-le-run.cmd reads. NOTPROTON_ENV_<NAME> is how NotProton hands a variable to the
# game however it starts it; a plain variable does not survive every route.
export NOTPROTON_ENV_FC27_STEAM_COMMAND="$target"
[ "$opens" != window ] || export NOTPROTON_ENV_FC27_OPENS=window
# The library's notes, for this start alone.
: > "$here/fc27-le-hooks.log" 2>/dev/null && export NOTPROTON_ENV_MGF_D3DM_HOOKABLE_LOG="$here/fc27-le-hooks.log"
[ "${FC27_TRACE:-}" != 1 ] || export WINEDEBUG="err+all,fixme-all,+seh,+timestamp,+pid"
# NotProton's Steam stub starts a program by name or Windows path, not a .cmd by its unix path.
exec "$tool" "$verb" cmd.exe /d /c call "$(windows "$here/fc27-le-run.cmd")"
