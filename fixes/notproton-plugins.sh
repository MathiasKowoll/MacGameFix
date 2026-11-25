# NotProton plugins for one game, sourced by that game's installer.
#
#   . "$HERE/notproton-plugins.sh"
#   np_plugins_setup <appid> <prefix> <template>...
#   NP_WRAPPER=<path>     the installer's play script, when one stands before %command%
#   NP_ENGINE_TEMPLATE=<np-plugin-engine.conf> NP_ENGINE_LIBRARY=<mgf-engine.dylib>
#   NP_ENGINE_GROUP=<group, or empty>     the game uses the shared engine row (below)
#   np_plugins_ready      true when NotProton keeps this prefix and its support folder is there
#   np_plugins_preflight  what an install would refuse, before anything changes
#   np_plugins_install    the game's descriptor, the libraries, and each row on the first time
#   np_plugins_status     installed, half or absent: the files only
#   np_plugins_restore    our switches out, the descriptor gone, and a library no descriptor names
#
# Each template is a plugin record beside the installer (np-plugin-<name>.conf) with an id
# that starts NOTPROTON_MGF_, which NotProton requires of every plugin (conf.c, conf_id_ok).
# Lines that start "# library = " name the files the record needs from beside the installer;
# they are copied into NotProton's plugins folder, which is where the record's "requires"
# points. "# earlier = <sha256>..." names builds of a library from before it was ours to
# ship, which are replaced like our own. "# retired = <file> <sha256>..." names a library an
# earlier version of the fix put in the folder and this one no longer uses: an install takes it
# out when it is one of those builds and no descriptor names it.
#
# ONE DESCRIPTOR PER GAME. Every record goes into plugins/mgf-<appid>.conf with the app id
# added to its id (NotProton refuses one id in two files) and, from NotProton 1.2.7, an
# "apps = <appid>" line, so the row shows on that game's page only. Removing one game's fix
# removes that file and nothing of another game's; a library goes once no descriptor in the
# folder names it. NotProton's own Delete does the same from its side.
#
# THE SHARED ENGINE ROW. NotProton reads at most 32 records for every game together, so the
# engine fixes (engine/mgf-engine.c) share one row, NOTPROTON_MGF_ENGINE, in its own file,
# plugins/mgf-engine.conf, with the one library that arms each game's fixes in that game alone.
# A game that uses it has "# engine fixes: on" in its descriptor; the row's "apps" are those
# games, written again from the descriptors whenever one comes or goes, and the row and its
# library go with the last of them. Its switch is one of the game's own: the same variable in
# each game's launch options, put in and taken out with the game's other switches.
#
# A ROW IS ON ONLY WHILE THE GAME'S LAUNCH OPTIONS CARRY <id>=<on>: NotProton has no other
# switch. The first install puts every toggle row's variable in, with steam-launch-options.pl
# (Steam closed, and a journal so a restore gives back what was there), and lists them in
# NP_SWITCHED; after that the switches are the player's, in the game's Compatibility page, and
# installing again never turns one back on. A toggle row a later version of the fix brings is
# not in that list, so the install that brings it switches it on, once, the same way. With
# Steam open the files go in and those rows stay off, and it says so.
# The status ignores the player's switches for the same reason: a row the player turned off is
# not a broken fix for the agent to repair. A row no install has switched on yet is: the status
# reads half until one can, with Steam closed.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

NP_APPID=""
NP_PFX=""
NP_TEMPLATES=()
NP_SUPPORT="$HOME/Library/Application Support/notproton"
NP_PLUGINS="$NP_SUPPORT/plugins"
NP_REQUIRES_BASE="Library/Application Support/notproton/plugins"
# NotProton reads at most this many records from the folder (NP_CONF_RECORDS_MAX).
NP_RECORDS_MAX=32

NP_ENGINE_ID=NOTPROTON_MGF_ENGINE
NP_ENGINE_CONF="$NP_PLUGINS/mgf-engine.conf"
NP_ENGINE_MARK="# engine fixes: on"
NP_ENGINE_TEMPLATE=""
NP_ENGINE_LIBRARY=""
NP_ENGINE_GROUP=""

np_plugins_setup() {
  NP_APPID="$1"; NP_PFX="${2%/}"; shift 2
  NP_TEMPLATES=("$@")
  NP_CONF="$NP_PLUGINS/mgf-$NP_APPID.conf"
  # Beside pfx, in compatdata/<appid>, where NotProton writes notproton-build.
  NP_GAME_DIR="$(dirname "$NP_PFX")"
  NP_JOURNAL="$NP_GAME_DIR/.mgf-notproton-plugins.json"
  NP_SWITCHED="$NP_GAME_DIR/.mgf-notproton-plugins-switched"
  NP_OPTIONS="$(dirname "${BASH_SOURCE[0]}")/steam-launch-options.pl"
}

np_plugins_ready() {
  [ -n "$NP_PFX" ] && [ -f "$NP_GAME_DIR/notproton-build" ] && [ -d "$NP_SUPPORT" ]
}

# NotProton's version, from its app, or MGVF_NOTPROTON_VERSION for a test.
np_version() {
  if [ -n "${MGVF_NOTPROTON_VERSION:-}" ]; then printf '%s' "$MGVF_NOTPROTON_VERSION"; return; fi
  local a
  for a in "/Applications/NotProton.app" "$HOME/Applications/NotProton.app"; do
    [ -f "$a/Contents/Info.plist" ] || continue
    /usr/bin/defaults read "$a/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null && return
  done
}

# 1.2.7 brought "apps"; an older NotProton refuses a record that carries it.
np_knows_apps() {
  local v a b c
  v="$(np_version)"; [ -n "$v" ] || return 1
  IFS=. read -r a b c _ <<< "${v%%-*}"
  a="${a//[^0-9]/}"; b="${b//[^0-9]/}"; c="${c//[^0-9]/}"
  [ "${a:-0}" -gt 1 ] && return 0
  [ "${a:-0}" -eq 1 ] && [ "${b:-0}" -gt 2 ] && return 0
  [ "${a:-0}" -eq 1 ] && [ "${b:-0}" -eq 2 ] && [ "${c:-0}" -ge 7 ]
}

np_sha() { /usr/bin/shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

# The values of "# <name> = " lines in a template.
np_meta() { /usr/bin/sed -n "s/^# $2 = //p" "$1"; }

# The records of every template, as they go into the game's descriptor.
np_expected() {
  local t apps=0
  np_knows_apps && apps=1
  printf '# MacGameFix writes this file for app %s and removes it with the fix; edits do not last.\n' "$NP_APPID"
  [ -z "$NP_ENGINE_TEMPLATE" ] || printf '%s\n' "$NP_ENGINE_MARK"
  for t in "${NP_TEMPLATES[@]}"; do
    /usr/bin/awk -v app="$NP_APPID" -v apps="$apps" '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
      /^\[/ { if (open && apps) print "apps = " app
              sub(/\]$/, "_" app "]"); print; open = 1; next }
      /^depends[[:space:]]*=/ { sub(/[[:space:]]*$/, ""); print $0 "_" app; next }
      { print }
      END { if (open && apps) print "apps = " app }' "$t"
  done
}

# Each record's id and the value that switches it on: toggles only (no "type"), and the shared
# engine row's when the game uses it.
np_switches() {
  np_expected | /usr/bin/awk '
    /^\[/ { if (id != "" && !typed) print id "=" (on == "" ? "1" : on)
            id = substr($0, 2, length($0) - 2); on = ""; typed = 0; next }
    /^on[[:space:]]*=/ { on = $0; sub(/^on[[:space:]]*=[[:space:]]*/, "", on) }
    /^type[[:space:]]*=/ { typed = 1 }
    END { if (id != "" && !typed) print id "=" (on == "" ? "1" : on) }'
  [ -z "$NP_ENGINE_TEMPLATE" ] || printf '%s=1\n' "$NP_ENGINE_ID"
}

# The apps whose descriptors use the engine row, this game's included when its descriptor is in.
np_engine_apps() {
  local f a
  for f in "$NP_PLUGINS"/mgf-*.conf; do
    [ -f "$f" ] && [ "$f" != "$NP_ENGINE_CONF" ] || continue
    /usr/bin/grep -qxF "$NP_ENGINE_MARK" "$f" || continue
    a="$(basename "$f" .conf)"; a="${a#mgf-}"
    case "$a" in *[!0-9]*|"") continue ;; esac
    printf '%s\n' "$a"
  done | sort -n
}

# The engine row's file for the apps given on stdin; nothing when there are none.
np_engine_expected() {
  local apps tpl
  apps="$(cat)"
  [ -n "$apps" ] || return 0
  tpl="${NP_ENGINE_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/np-plugin-engine.conf}"
  printf '# MacGameFix writes this file for the games whose fix uses its engine fixes, and removes it with the last of them; edits do not last.\n'
  /usr/bin/awk -v group="$NP_ENGINE_GROUP" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { print }
    /^label[[:space:]]*=/ && group != "" { print "group = " group }' "$tpl"
  if np_knows_apps; then printf '%s\n' "$apps" | /usr/bin/sed 's/^/apps = /'; fi
}

# The engine row's file written again from the descriptors, or removed with the last of them.
np_engine_write() {
  local text
  text="$(np_engine_apps | np_engine_expected)"
  if [ -z "$text" ]; then /bin/rm -f "$NP_ENGINE_CONF"; return 0; fi
  [ "$(cat "$NP_ENGINE_CONF" 2>/dev/null)" = "$text" ] && return 0
  printf '%s\n' "$text" > "$NP_ENGINE_CONF.mgf-new" && mv -f "$NP_ENGINE_CONF.mgf-new" "$NP_ENGINE_CONF"
}

# The switches no install has put in yet: every one the first time, then a row the fix gained.
np_new_switches() {
  local s
  if [ ! -f "$NP_SWITCHED" ]; then np_switches; return; fi
  np_switches | while IFS= read -r s; do
    /usr/bin/grep -q "^${s%%=*}=" "$NP_SWITCHED" || printf '%s\n' "$s"
  done
}

np_ids() { np_switches_all | cut -d= -f1; }
np_switches_all() { np_expected | /usr/bin/sed -n 's/^\[\(.*\)\]$/\1=/p'; }

# The libraries every template names, as "<template dir>/<file>".
np_libraries() {
  local t l
  for t in "${NP_TEMPLATES[@]}"; do
    while IFS= read -r l; do [ -n "$l" ] && printf '%s/%s\n' "$(dirname "$t")" "$l"; done < <(np_meta "$t" library)
  done
  [ -z "$NP_ENGINE_LIBRARY" ] || printf '%s\n' "$NP_ENGINE_LIBRARY"
}

# A library in the folder is ours: the one we ship, or an earlier build a template names.
np_lib_ours() {
  local src="$1" live="$NP_PLUGINS/$(basename "$1")" t
  [ -f "$live" ] || return 1
  cmp -s "$live" "$src" && return 0
  for t in "${NP_TEMPLATES[@]}"; do
    case " $(np_meta "$t" earlier | tr '\n' ' ') " in *" $(np_sha "$live") "*) return 0 ;; esac
  done
  return 1
}

# Records in the folder that are not in our descriptor.
np_other_records() {
  local f
  for f in "$NP_PLUGINS"/*.conf; do
    [ -f "$f" ] && [ "$f" != "$NP_CONF" ] && [ "$f" != "$NP_ENGINE_CONF" ] || continue
    /usr/bin/grep -h '^[[:space:]]*\[' "$f" | /usr/bin/sed 's/^[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/'
  done
}

# NP_WRAPPER, set by an installer whose play script stands before %command%, is named to the
# editor while that script is in the options, so it is taken for ours rather than refused as
# another program. Named only then: a switch put in before the script never takes it in.
np_options() {
  local w=()
  if [ -n "${NP_WRAPPER:-}" ] && /usr/bin/perl "$NP_OPTIONS" status "$NP_APPID" "$NP_JOURNAL" --wrapper "$NP_WRAPPER" >/dev/null 2>&1; then
    w=(--wrapper "$NP_WRAPPER")
  fi
  /usr/bin/perl "$NP_OPTIONS" "$1" "$NP_APPID" "$NP_JOURNAL" ${w[@]+"${w[@]}"} "${@:2}"
}

np_plugins_preflight() {
  local id taken mine
  [ -f "$NP_OPTIONS" ] || { echo "error: steam-launch-options.pl is not beside the installer" >&2; return 1; }
  while IFS= read -r l; do
    [ -f "$l" ] || { echo "error: $(basename "$l") is not beside the installer" >&2; return 1; }
    if [ -f "$NP_PLUGINS/$(basename "$l")" ] && ! np_lib_ours "$l"; then
      echo "error: $NP_PLUGINS/$(basename "$l") is a different library; nothing was changed." >&2; return 1
    fi
  done < <(np_libraries)
  taken="$(np_other_records)"
  for id in $(np_ids) ${NP_ENGINE_TEMPLATE:+$NP_ENGINE_ID}; do
    if printf '%s\n' "$taken" | /usr/bin/grep -qx "$id"; then
      echo "error: another plugin file already has $id; nothing was changed." >&2; return 1
    fi
  done
  mine="$(np_ids | /usr/bin/grep -c .)"
  [ -z "$NP_ENGINE_TEMPLATE" ] || [ -f "$NP_ENGINE_CONF" ] || mine=$((mine + 1))
  if [ $(( $(printf '%s\n' "$taken" | /usr/bin/grep -c .) + mine )) -gt "$NP_RECORDS_MAX" ]; then
    echo "error: NotProton reads at most $NP_RECORDS_MAX plugin rows, and with this game's there would be more." >&2
    echo "       Remove a plugin you do not use in NotProton's Plugins page; nothing was changed." >&2
    return 1
  fi
  # Whether the install can switch on the rows none has switched on yet: options it cannot
  # edit stop the install, Steam open only leaves the rows off. NP_SWITCH is on, steam or none.
  NP_SWITCH=none
  NP_NEW="$(np_new_switches)"
  if [ -n "$NP_NEW" ]; then
    local why
    if why="$(np_options preflight $NP_NEW 2>&1 >/dev/null)"; then NP_SWITCH=on
    elif np_steam_running; then NP_SWITCH=steam
    else printf '%s\n' "$why" >&2; return 1; fi
  fi
}

# MGVF_STEAM_RUNNING=0 or 1 answers for a test, which must not see the Steam of the Mac it runs on.
np_steam_running() {
  case "${MGVF_STEAM_RUNNING:-}" in 0) return 1 ;; 1) return 0 ;; esac
  /bin/ps -axo comm= | /usr/bin/grep -qE '(/Steam\.app/Contents/MacOS/steam|/steam_osx)$'
}

np_plugins_install() {
  local l live
  [ -n "${NP_SWITCH:-}" ] || np_plugins_preflight || return 1
  /bin/mkdir -p "$NP_PLUGINS"
  # Renamed into place, so a game still running keeps the library it loaded.
  while IFS= read -r l; do
    live="$NP_PLUGINS/$(basename "$l")"
    cmp -s "$l" "$live" && continue
    cp -p "$l" "$live.mgf-new" && mv -f "$live.mgf-new" "$live"
  done < <(np_libraries)
  np_expected > "$NP_CONF.mgf-new" && mv -f "$NP_CONF.mgf-new" "$NP_CONF"
  echo "  NotProton: $(np_ids | /usr/bin/grep -c .) row(s) in plugins/mgf-$NP_APPID.conf$(np_knows_apps && echo ", shown on this game's page only")"
  np_engine_write || return 1
  [ -z "$NP_ENGINE_TEMPLATE" ] || echo "  NotProton: the shared engine row in plugins/mgf-engine.conf, for $(np_engine_apps | /usr/bin/grep -c .) game(s)"
  np_retire
  local first=1
  [ ! -f "$NP_SWITCHED" ] || first=0
  case "$NP_SWITCH" in
  on)
    np_options install $NP_NEW >/dev/null || return 1
    printf '%s\n' "$NP_NEW" >> "$NP_SWITCHED"
    if [ "$first" = 1 ]; then echo "  NotProton: switched on in the game's launch options: $(printf '%s\n' "$NP_NEW" | tr '\n' ' ')"
    else echo "  NotProton: a row new to this fix, switched on in the game's launch options: $(printf '%s\n' "$NP_NEW" | tr '\n' ' ')"; fi ;;
  steam)
    if [ "$first" = 1 ]; then echo "  NotProton: Steam is open, so the rows are off. Switch them on in the game's Compatibility page,"
    else echo "  NotProton: Steam is open, so the row new to this fix is off ($(printf '%s\n' "$NP_NEW" | cut -d= -f1 | tr '\n' ' ')). Switch it on in the game's Compatibility page,"; fi
    echo "             or quit Steam and install again to have them switched on." ;;
  *)
    [ ! -f "$NP_SWITCHED" ] || echo "  NotProton: the rows' switches are as you left them in the game's Compatibility page" ;;
  esac
}

np_plugins_status() {
  local l
  if [ ! -f "$NP_CONF" ]; then
    [ -f "$NP_SWITCHED" ] && { echo half; return; }
    echo absent; return
  fi
  [ "$(cat "$NP_CONF")" = "$(np_expected)" ] || { echo "Why: plugins/mgf-$NP_APPID.conf is not what this fix writes" >&2; echo half; return; }
  if [ -n "$NP_ENGINE_TEMPLATE" ] && [ "$(cat "$NP_ENGINE_CONF" 2>/dev/null)" != "$(np_engine_apps | np_engine_expected)" ]; then
    echo "Why: plugins/mgf-engine.conf, the shared engine row, is missing or not what the fixes write" >&2; echo half; return
  fi
  while IFS= read -r l; do
    cmp -s "$l" "$NP_PLUGINS/$(basename "$l")" || { echo "Why: $(basename "$l") in NotProton's plugins folder is missing or another build" >&2; echo half; return; }
  done < <(np_libraries)
  # A row the fix gained that no install could switch on yet (Steam was open): installing
  # again with Steam closed does it. The rows the player switched off are in the list.
  if [ -f "$NP_SWITCHED" ] && [ -n "$(np_new_switches)" ]; then
    echo "Why: a row new to this fix is not switched on yet: quit Steam and install again" >&2; echo half; return
  fi
  echo installed
}

# Is a library named by any descriptor still in the folder.
np_lib_named() { /usr/bin/grep -lqF "/$(basename "$1")" "$NP_PLUGINS"/*.conf 2>/dev/null; }

np_plugins_restore() {
  local l
  if [ -f "$NP_JOURNAL" ]; then np_options restore $(np_switches) >/dev/null || return 1; fi
  /bin/rm -f "$NP_CONF" "$NP_SWITCHED"
  # The engine row without this game, or gone with the last one.
  [ -z "$NP_ENGINE_TEMPLATE" ] || np_engine_write || return 1
  while IFS= read -r l; do
    np_lib_named "$l" || ! np_lib_ours "$l" || /bin/rm -f "$NP_PLUGINS/$(basename "$l")"
  done < <(np_libraries)
  return 0
}

# Libraries an earlier version of the fix put in the folder and this one no longer uses.
np_retire() {
  local t line file shas live
  for t in "${NP_TEMPLATES[@]}"; do
    while IFS= read -r line; do
      file="${line%% *}"; shas=" ${line#* } "
      case "$file" in ""|*/*) continue ;; esac
      live="$NP_PLUGINS/$file"
      [ -f "$live" ] || continue
      np_lib_named "$live" && continue
      case "$shas" in *" $(np_sha "$live") "*) /bin/rm -f "$live"; echo "  NotProton: $file, which this fix no longer uses, taken out" ;; esac
    done < <(np_meta "$t" retired)
  done
}
