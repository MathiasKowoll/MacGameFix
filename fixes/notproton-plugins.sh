# NotProton plugins for one game, sourced by that game's installer.
#
#   . "$HERE/notproton-plugins.sh"
#   np_plugins_setup <appid> <prefix> <template>...
#   NP_WRAPPER=<path>     the installer's play script, when one stands before %command%
#   NP_SHARED_TEMPLATE=<np-plugin-shared.conf> NP_SHARED_LIBRARY=<mgf-engine.dylib>
#   NP_SHARED_USES="<id>..." NP_SHARED_GROUP=<group, or empty>   the shared rows the game uses;
#                         the group is its own rows' too. A template row says which part of the
#                         group it goes under with "subgroup = <name>", written as
#                         "group = <group> / <name>" (NotProton's subgroups; one that does not
#                         know them shows that as one group's name)
#   NP_SHARED_CHOICES="<id> = <value> = <label>" lines   choices of its own for a shared row
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
# folder names it. NotProton's own Delete does the same from its side. A game with no record of
# its own has no descriptor for NotProton: what it uses of the shared rows is noted in
# plugins/mgf-<appid>.uses, which NotProton does not read (np_plugins_setup).
#
# SHARED ROWS. NotProton reads at most 32 records for every game together, so the rows that are
# not one game's own are written once and reused by every game that needs them: one file,
# plugins/mgf-shared.conf, from one template (np-plugin-shared.conf), with each record's "apps"
# the games that use it. A game says which it uses in its descriptor or its note, "# shared rows: <id>...";
# the file is written again from the descriptors whenever one comes or goes, a record goes with
# the last game that uses it, and the file with the last record. The one library the shared
# rows load (mgf-engine.dylib, which arms each game's own fixes in that game alone) goes when no
# record names it. A shared toggle's switch is one of each game's own: the same variable in the
# game's launch options, put in and taken out with the game's other switches. A shared choice's
# value is the game's too, as NotProton keeps every row's value per game. A game can add choices
# of its own to a shared choice row, such as its mod tool's profiles: its descriptor keeps them as
# "# shared choice: <id> = <value> = <label>", and the row offers every game's, its own first, up
# to NotProton's 16. The descriptor holds what the game has now, so a change reads as half and
# the next install writes the row again.
#
# THE GAMES A ROW IS FOR. A template's record says them with NotProton's own fields, one line a
# game: "needed_for = <appid> <one short sentence>" where the game does not run or crashes
# without the row, "improves = <appid> <one short sentence>" for the rest. NotProton's
# Compatibility page then offers a row that is off on that game's page, in a box "Fixes for This
# Game" with Apply and Dismiss, with the sentence under the row's name. The lines are written
# only where every NotProton in Steam reads the field (np_knows_field): one that does not refuses
# a record that carries it, and gets the record as it was before the fields existed. In a shared
# record a line is written for the games whose fix uses the row, and for every game the template
# names when the row is on every game's page. NotProton allows neither field on a row with a
# "type", an app in only one of the two per row, 16 of each, and 200 characters of sentence.
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
# Empty until a game's installer names its game (np_plugins_setup); the rows kept for every game have none.
NP_CONF=""
NP_CONF_OTHER=""
NP_TEMPLATES=()
NP_SUPPORT="$HOME/Library/Application Support/notproton"
NP_PLUGINS="$NP_SUPPORT/plugins"
NP_REQUIRES_BASE="Library/Application Support/notproton/plugins"
# NotProton reads at most this many records from the folder (NP_CONF_RECORDS_MAX).
NP_RECORDS_MAX=32

NP_SHARED_CONF="$NP_PLUGINS/mgf-shared.conf"
NP_SHARED_MARK="# shared rows:"
NP_EVERY_NOTE="$NP_PLUGINS/mgf-every-game.uses"
NP_SHARED_TEMPLATE=""
NP_SHARED_LIBRARY=""
NP_SHARED_USES=""
NP_SHARED_GROUP=""
NP_SHARED_CHOICES=""
NP_CHOICES_MAX=16

np_plugins_setup() {
  NP_APPID="$1"; NP_PFX="${2%/}"; shift 2
  NP_TEMPLATES=("$@")
  # A game with no row of its own keeps only a note of the shared rows it uses. NotProton's app
  # lists every .conf in the folder, by its first row's label, so a file with no row was listed
  # there by its file name, "mgf-<appid>", with nothing to say what it was, and offered for the
  # Trash (2026-11-27). Such a note is kept as mgf-<appid>.uses, which NotProton does not read or
  # list; a game with rows keeps mgf-<appid>.conf, listed by its first row's label. The other
  # name, left by an earlier install, goes at the next one.
  # (A template with no record in it, which is how a game with none calls this, counts as none.)
  if /usr/bin/grep -qs '^\[' "$@" </dev/null; then
    NP_CONF="$NP_PLUGINS/mgf-$NP_APPID.conf"; NP_CONF_OTHER="$NP_PLUGINS/mgf-$NP_APPID.uses"
  else
    NP_CONF="$NP_PLUGINS/mgf-$NP_APPID.uses"; NP_CONF_OTHER="$NP_PLUGINS/mgf-$NP_APPID.conf"
  fi
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

# Whether every NotProton in Steam reads a field: each tool's run script lists the fields it
# reads, and the app asks the same way (NotProtonRow.knows). With no run script to ask, no.
np_knows_field() {
  local run seen=1
  for run in "${MGVF_STEAM_ROOT:-$HOME/Library/Application Support/Steam}"/compatibilitytools.d/[Nn]ot[Pp]roton*/run; do
    [ -f "$run" ] || continue
    seen=0
    LC_ALL=C /usr/bin/grep -qE "split\\(\"label description[^\"]* $1[ \"]" "$run" || return 1
  done
  return $seen
}
# "1" or "0" for awk.
np_knows_flag() { if np_knows_field "$1"; then printf 1; else printf 0; fi; }

np_sha() { /usr/bin/shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

# The values of "# <name> = " lines in a template.
np_meta() { /usr/bin/sed -n "s/^# $2 = //p" "$1"; }

# The records of every template, as they go into the game's descriptor.
np_expected() {
  local t apps=0 nf im
  np_knows_apps && apps=1
  nf="$(np_knows_flag needed_for)"; im="$(np_knows_flag improves)"
  printf '# MacGameFix writes this file for app %s and removes it with the fix; edits do not last.\n' "$NP_APPID"
  [ -z "$NP_SHARED_USES" ] || printf '%s %s\n' "$NP_SHARED_MARK" "$NP_SHARED_USES"
  [ -z "$NP_SHARED_CHOICES" ] || printf '%s\n' "$NP_SHARED_CHOICES" | /usr/bin/grep . | /usr/bin/sed 's/^/# shared choice: /'
  for t in "${NP_TEMPLATES[@]}"; do
    # A row in the MacGameFix group does not name it again; with no group, its label does.
    /usr/bin/awk -v app="$NP_APPID" -v apps="$apps" -v group="$NP_SHARED_GROUP" -v nf="$nf" -v im="$im" '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
      /^needed_for[[:space:]]*=/ { if (nf) print; next }
      /^improves[[:space:]]*=/ { if (im) print; next }
      /^\[/ { if (open && apps) print "apps = " app
              sub(/\]$/, "_" app "]"); print; open = 1; next }
      /^label[[:space:]]*=/ { if (group != "") print; else print $0 " (MacGameFix)"; next }
      /^subgroup[[:space:]]*=/ { if (group != "") { sub(/^subgroup[[:space:]]*=[[:space:]]*/, ""); print "group = " group " / " $0 }; next }
      /^depends[[:space:]]*=/ { sub(/[[:space:]]*$/, ""); print $0 "_" app; next }
      { print }
      END { if (open && apps) print "apps = " app }' "$t"
  done
}

# Each record's id and the value that switches it on: toggles only (no "type"), the game's own
# and the shared ones it uses.
np_toggles() {
  /usr/bin/awk -v only="$1" '
    function out() { if (id != "" && !typed && (only == "" || index(only, " " id " "))) print id "=" (on == "" ? "1" : on) }
    /^\[/ { out(); id = substr($0, 2, length($0) - 2); on = ""; typed = 0; next }
    /^on[[:space:]]*=/ { on = $0; sub(/^on[[:space:]]*=[[:space:]]*/, "", on) }
    /^type[[:space:]]*=/ { typed = 1 }
    END { out() }'
}
np_switches() {
  np_expected | np_toggles ""
  [ -z "$NP_SHARED_USES" ] || np_shared_records | np_toggles " $NP_SHARED_USES "
}

# The shared rows' template: the one the game's installer names, else the one beside this file.
# A game with no shared row of its own names none, and still writes the shared file again
# (np_shared_write), so whatever reads the template has to find it the same way. Found on
# 2026-11-28: the "every game" line was read only from the named one, so FH5's install, which
# names none, gave Engine fixes its apps back and the row left every other game's page.
np_shared_template() {
  printf '%s\n' "${NP_SHARED_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/np-plugin-shared.conf}"
}

# The shared template's records, without its comments.
np_shared_records() {
  /usr/bin/grep -v -E '^[[:space:]]*(#|$)' "$(np_shared_template)"
}

# "<app> <id>" for every shared row each game's descriptor in the folder uses.
np_shared_table() {
  local f a
  for f in "$NP_PLUGINS"/mgf-*.conf "$NP_PLUGINS"/mgf-*.uses; do
    [ -f "$f" ] && [ "$f" != "$NP_SHARED_CONF" ] || continue
    a="$(basename "$f")"; a="${a#mgf-}"; a="${a%.conf}"; a="${a%.uses}"
    # The note of the rows kept for every game (np_every_install) stands in the table as app 0.
    [ "$f" != "$NP_EVERY_NOTE" ] || a=0
    case "$a" in *[!0-9]*|"") continue ;; esac
    /usr/bin/sed -n "s/^$NP_SHARED_MARK //p" "$f" | tr ' ' '\n' | /usr/bin/grep . | /usr/bin/sed "s/^/$a /"
  done | sort -n -k1,1 -s
}

# "<id> = <value> = <label>" for the choices the descriptors in the folder add, each once.
np_shared_choices() {
  local f
  for f in "$NP_PLUGINS"/mgf-*.conf "$NP_PLUGINS"/mgf-*.uses; do
    [ -f "$f" ] && [ "$f" != "$NP_SHARED_CONF" ] || continue
    /usr/bin/sed -n 's/^# shared choice: //p' "$f"
  done | /usr/bin/awk -F' = ' '!seen[$1 " = " $2]++'
}

# The shared rows' file for the table given on stdin: each record some game uses, with those
# games as its apps; nothing when no game uses any. A record the template names on a
# "# every game = <id>..." line gets no apps, so NotProton shows it on every game's page and the
# player can switch it on for a game no fix knows; it is written while some game's fix uses it,
# or while it is kept for every game (np_every_install, below).
np_shared_expected() {
  local table apps=0
  table="$(cat)"
  [ -n "$table" ] || return 0
  np_knows_apps && apps=1
  printf '# MacGameFix writes this file for the games whose fixes use its rows, and removes it with the last of them; edits do not last.\n'
  NP_TABLE="$table" NP_CHOICES="$(np_shared_choices)" np_shared_records | NP_TABLE="$table" NP_CHOICES="$(np_shared_choices)" \
    NP_EVERY="$(/usr/bin/sed -n 's/^# every game = //p' "$(np_shared_template)" 2>/dev/null)" \
    /usr/bin/awk -v group="$NP_SHARED_GROUP" -v apps="$apps" -v max="$NP_CHOICES_MAX" \
      -v nf="$(np_knows_flag needed_for)" -v im="$(np_knows_flag improves)" '
    BEGIN { n = split(ENVIRON["NP_TABLE"], rows, "\n"); for (i = 1; i <= n; i++) { split(rows[i], f, " "); use[f[2]] = use[f[2]] " " f[1] }
            n = split(ENVIRON["NP_EVERY"], f, " "); for (i = 1; i <= n; i++) every[f[i]] = 1
            n = split(ENVIRON["NP_CHOICES"], rows, "\n")
            for (i = 1; i <= n; i++) { p = index(rows[i], " = "); if (p) { k = substr(rows[i], 1, p - 1); extra[k] = extra[k] "\n" substr(rows[i], p + 3) } } }
    function flush(   i, k, a, m, last, have, c, v, e, ne) {
      if (id != "" && (id in use)) {
        last = 0; have = 0
        for (i = 1; i <= nb; i++) if (buf[i] ~ /^choice[[:space:]]*=/) { last = i; have++; v = buf[i]; sub(/^choice[[:space:]]*=[[:space:]]*/, "", v); sub(/[[:space:]]*=.*/, "", v); taken[v] = 1 }
        for (i = 1; i <= nb; i++) {
          # A row in the MacGameFix group does not name it again; with no group, its label does.
          if (buf[i] ~ /^label[[:space:]]*=/) { if (group != "") print buf[i]; else print buf[i] " (MacGameFix)"; continue }
          if (buf[i] ~ /^subgroup[[:space:]]*=/) { if (group != "") { v = buf[i]; sub(/^subgroup[[:space:]]*=[[:space:]]*/, "", v); print "group = " group " / " v }; continue }
          # The games the row is for: where NotProton reads the field, and for a game that uses
          # the row, or every game the template names when the row is on the page of every game.
          if (buf[i] ~ /^(needed_for|improves)[[:space:]]*=/) {
            if (!(buf[i] ~ /^needed_for/ ? nf : im)) continue
            v = buf[i]; sub(/^[a-z_]+[[:space:]]*=[[:space:]]*/, "", v); sub(/[[:space:]].*/, "", v)
            if (!(id in every) && !index(use[id] " ", " " v " ")) continue
          }
          print buf[i]
          if (i == last && (id in extra)) {
            ne = split(extra[id], e, "\n")
            for (k = 1; k <= ne; k++) {
              if (e[k] == "" || have >= max) continue
              v = e[k]; sub(/[[:space:]]*=.*/, "", v)
              if (v in taken) continue
              taken[v] = 1; have++; print "choice = " e[k]
            }
          }
        }
        delete taken
        if (apps && !(id in every)) { m = split(use[id], a, " "); for (k = 1; k <= m; k++) if (a[k] != 0) print "apps = " a[k] }
      }
      id = ""; nb = 0
    }
    /^\[/ { flush(); id = substr($0, 2, length($0) - 2) }
    { buf[++nb] = $0 }
    END { flush() }'
}

# The table with this game's shared rows in it, before its descriptor is written.
np_shared_table_with_me() {
  { np_shared_table | /usr/bin/grep -v "^$NP_APPID "; for id in $NP_SHARED_USES; do printf '%s %s\n' "$NP_APPID" "$id"; done; } | sort -n -k1,1 -s
}

# The shared rows' file written again from the descriptors, or removed with the last of them.
np_shared_write() {
  local text
  text="$(np_shared_table | np_shared_expected)"
  if [ -z "$text" ]; then /bin/rm -f "$NP_SHARED_CONF"; return 0; fi
  [ "$(cat "$NP_SHARED_CONF" 2>/dev/null)" = "$text" ] && return 0
  printf '%s\n' "$text" > "$NP_SHARED_CONF.mgf-new" && mv -f "$NP_SHARED_CONF.mgf-new" "$NP_SHARED_CONF"
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
  [ -z "$NP_SHARED_LIBRARY" ] || printf '%s\n' "$NP_SHARED_LIBRARY"
}

# A library in the folder is ours: the one we ship, or an earlier build a template names (the
# game's, or the shared rows' for the library they load).
np_lib_ours() {
  local src="$1" live="$NP_PLUGINS/$(basename "$1")" t
  [ -f "$live" ] || return 1
  cmp -s "$live" "$src" && return 0
  for t in "${NP_TEMPLATES[@]}" ${NP_SHARED_TEMPLATE:+"$NP_SHARED_TEMPLATE"}; do
    case " $(np_meta "$t" earlier | tr '\n' ' ') " in *" $(np_sha "$live") "*) return 0 ;; esac
  done
  return 1
}

# Records in the folder that are not in our descriptor.
np_other_records() {
  local f
  for f in "$NP_PLUGINS"/*.conf; do
    [ -f "$f" ] && [ "$f" != "$NP_CONF" ] && [ "$f" != "$NP_SHARED_CONF" ] || continue
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
  for id in $(np_ids) $NP_SHARED_USES; do
    if printf '%s\n' "$taken" | /usr/bin/grep -qx "$id"; then
      echo "error: another plugin file already has $id; nothing was changed." >&2; return 1
    fi
  done
  mine="$(np_ids | /usr/bin/grep -c .)"
  # The shared records this game would add to the file.
  if [ -n "$NP_SHARED_USES" ]; then
    mine=$(( mine + $(np_shared_table_with_me | np_shared_expected | /usr/bin/grep -c '^\[') - $(/usr/bin/grep -c '^\[' "$NP_SHARED_CONF" 2>/dev/null || echo 0) ))
  fi
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

# NotProton's own app, which lists and deletes plugins. MGVF_NOTPROTON_RUNNING=0 or 1 for a test.
np_notproton_running() {
  case "${MGVF_NOTPROTON_RUNNING:-}" in 0) return 1 ;; 1) return 0 ;; esac
  /bin/ps -axo comm= | /usr/bin/grep -qE '/NotProton\.app/Contents/MacOS/[^/]+$'
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
  /bin/rm -f "$NP_CONF_OTHER"
  [ -z "$(np_ids)" ] || echo "  NotProton: $(np_ids | /usr/bin/grep -c .) row(s) in plugins/mgf-$NP_APPID.conf$(np_knows_apps && echo ", shown on this game's page only")"
  np_shared_write || return 1
  [ -z "$NP_SHARED_USES" ] || echo "  NotProton: $(printf '%s\n' $NP_SHARED_USES | /usr/bin/grep -c .) shared row(s) used, in plugins/mgf-shared.conf: $(/usr/bin/grep -c '^\[' "$NP_SHARED_CONF") row(s) for $(np_shared_table | cut -d' ' -f1 | sort -u | /usr/bin/grep -c .) game(s)"
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
    if [ -f "$NP_CONF_OTHER" ]; then
      echo "Why: plugins/$(basename "$NP_CONF_OTHER") is the name an earlier install gave this game's file: install again" >&2
      echo half; return
    fi
    [ -f "$NP_SWITCHED" ] && { echo half; return; }
    echo absent; return
  fi
  [ "$(cat "$NP_CONF")" = "$(np_expected)" ] || { echo "Why: plugins/$(basename "$NP_CONF") is not what this fix writes" >&2; echo half; return; }
  if [ -n "$NP_SHARED_USES" ] && [ "$(cat "$NP_SHARED_CONF" 2>/dev/null)" != "$(np_shared_table | np_shared_expected)" ]; then
    echo "Why: plugins/mgf-shared.conf, the shared rows, is missing or not what the fixes write" >&2; echo half; return
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
  /bin/rm -f "$NP_CONF" "$NP_CONF_OTHER" "$NP_SWITCHED"
  # The shared rows without this game, or gone with the last one.
  [ -z "$NP_SHARED_USES" ] || np_shared_write || return 1
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


# THE ROWS KEPT FOR EVERY GAME. The shared rows the template names on "# every game = " (Engine
# fixes) are on every game's page, for a game no fix knows: one with Denuvo needs the row to
# start. Written only by a game's fix, the row was there only for whoever had installed the fix
# of one of five games. np_every_install keeps it whether or not any fix uses it: it puts the
# library in, and a note, plugins/mgf-every-game.uses, that stands in the shared rows' table as
# a game of its own (app 0), so the file is written by the one writer every game's installer
# uses and no game's install or restore takes the row out. Called by notproton-every-game.sh,
# which MacGameFix's app runs; it wants NP_SHARED_TEMPLATE, NP_SHARED_LIBRARY and NP_SHARED_GROUP
# set as a game's installer sets them.
#
# Put in only with Steam and NotProton's app closed: Steam reads the folder each time a game's
# page opens, and NotProton's app lists it and deletes from it. Once in, they are brought up to
# date (a newer library, a row that changed) with Steam open or not, as a game's own rows are.
# Deleted in NotProton's Plugins page (the file gone, the note left), they read absent and stay
# out until they are installed again.
np_every_ids() { /usr/bin/sed -n 's/^# every game = //p' "$(np_shared_template)" | tr ' ' '\n' | /usr/bin/grep .; }

np_every_note() { printf '# MacGameFix keeps these rows for every game; edits do not last.\n%s %s\n' "$NP_SHARED_MARK" "$(np_every_ids | tr '\n' ' ' | /usr/bin/sed 's/ $//')"; }

# The table with the every-game rows in it, as the note will give it.
np_every_table() {
  { np_shared_table | /usr/bin/grep -v '^0 '; np_every_ids | /usr/bin/sed 's/^/0 /'; } | sort -n -k1,1 -s
}

# unavailable (no NotProton, or one that cannot load a library), installed, half or absent.
np_every_status() {
  [ -d "$NP_SUPPORT" ] || { echo "Why: NotProton is not installed" >&2; echo unavailable; return; }
  [ -f "$NP_SUPPORT/plugin-host.dylib" ] || { echo "Why: NotProton's plugin host is not installed: its Update installs it" >&2; echo unavailable; return; }
  # Without the note they were never installed; without the file they were deleted in NotProton.
  [ -f "$NP_EVERY_NOTE" ] && [ -f "$NP_SHARED_CONF" ] || { echo absent; return; }
  [ "$(cat "$NP_EVERY_NOTE")" = "$(np_every_note)" ] || { echo "Why: plugins/$(basename "$NP_EVERY_NOTE") is not what MacGameFix writes" >&2; echo half; return; }
  [ "$(cat "$NP_SHARED_CONF" 2>/dev/null)" = "$(np_shared_table | np_shared_expected)" ] || { echo "Why: plugins/mgf-shared.conf is missing or not what MacGameFix writes" >&2; echo half; return; }
  cmp -s "$NP_SHARED_LIBRARY" "$NP_PLUGINS/$(basename "$NP_SHARED_LIBRARY")" || { echo "Why: $(basename "$NP_SHARED_LIBRARY") in NotProton's plugins folder is missing or another build" >&2; echo half; return; }
  echo installed
}

# What an install would refuse, before anything changes.
np_every_preflight() {
  local id taken live
  [ -d "$NP_SUPPORT" ] || { echo "error: NotProton is not installed." >&2; return 1; }
  [ -f "$NP_SUPPORT/plugin-host.dylib" ] || { echo "error: NotProton's plugin host is not installed. Run NotProton's Update, then install again." >&2; return 1; }
  # Putting the rows in wants both closed; keeping installed ones current does not.
  if [ ! -f "$NP_EVERY_NOTE" ] || [ ! -f "$NP_SHARED_CONF" ]; then
    if np_steam_running; then echo "error: Steam is open. Quit Steam, then install again; nothing was changed." >&2; return 1; fi
    if np_notproton_running; then echo "error: NotProton is open. Quit NotProton, then install again; nothing was changed." >&2; return 1; fi
  fi
  [ -f "$NP_SHARED_LIBRARY" ] || { echo "error: $(basename "$NP_SHARED_LIBRARY") is missing beside the installer." >&2; return 1; }
  live="$NP_PLUGINS/$(basename "$NP_SHARED_LIBRARY")"
  if [ -f "$live" ] && ! np_lib_ours "$NP_SHARED_LIBRARY"; then
    echo "error: $(basename "$live") in NotProton's plugins folder is not one MacGameFix shipped; nothing was changed." >&2; return 1
  fi
  taken="$(np_other_records)"
  for id in $(np_every_ids); do
    if printf '%s\n' "$taken" | /usr/bin/grep -qx "$id"; then
      echo "error: another plugin file already has $id; nothing was changed." >&2; return 1
    fi
  done
  if [ $(( $(printf '%s\n' "$taken" | /usr/bin/grep -c .) + $(np_every_table | np_shared_expected | /usr/bin/grep -c '^\[') )) -gt "$NP_RECORDS_MAX" ]; then
    echo "error: NotProton reads at most $NP_RECORDS_MAX plugin rows, and with these there would be more." >&2
    echo "       Remove a plugin you do not use in NotProton's Plugins page; nothing was changed." >&2
    return 1
  fi
}

np_every_install() {
  local live
  np_every_preflight || return 1
  /bin/mkdir -p "$NP_PLUGINS"
  live="$NP_PLUGINS/$(basename "$NP_SHARED_LIBRARY")"
  # Renamed into place, so a game still running keeps the library it loaded.
  cmp -s "$NP_SHARED_LIBRARY" "$live" || { cp -p "$NP_SHARED_LIBRARY" "$live.mgf-new" && mv -f "$live.mgf-new" "$live"; } || return 1
  np_every_note > "$NP_EVERY_NOTE.mgf-new" && mv -f "$NP_EVERY_NOTE.mgf-new" "$NP_EVERY_NOTE" || return 1
  np_shared_write || return 1
  echo "  NotProton: $(np_every_ids | /usr/bin/grep -c .) row(s) for every game, in plugins/mgf-shared.conf, off until switched on for a game"
}

# A Mac from before the note, where a game's fix already put the rows in: the note alone is
# written, so they read installed and stay when that game's fix goes. Nothing else changes (a
# row for every game is written the same with the note or without), so this asks for nothing
# to be closed. MacGameFix's app does it once, the first time it looks (NotProtonPlugins.swift).
np_every_adopt() {
  local id
  [ ! -f "$NP_EVERY_NOTE" ] && [ -f "$NP_SHARED_CONF" ] || return 1
  for id in $(np_every_ids); do /usr/bin/grep -qx "\[$id\]" "$NP_SHARED_CONF" || return 1; done
  np_every_note > "$NP_EVERY_NOTE.mgf-new" && mv -f "$NP_EVERY_NOTE.mgf-new" "$NP_EVERY_NOTE" || return 1
  np_shared_write
}

# After a restore: a row some game's fix uses is still on every game's page, and this says so.
np_every_kept() {
  local id games
  for id in $(np_every_ids); do
    games="$(np_shared_table | /usr/bin/grep -c " $id\$")"
    [ "$games" = 0 ] || echo "  NotProton: the row stays, the fix of $games game(s) uses it"
  done
}

# The note gone, and the rows with it unless a game's fix uses them; the library when no
# descriptor names it any more.
np_every_restore() {
  if np_steam_running; then echo "error: Steam is open. Quit Steam, then try again; nothing was changed." >&2; return 1; fi
  if np_notproton_running; then echo "error: NotProton is open. Quit NotProton, then try again; nothing was changed." >&2; return 1; fi
  /bin/rm -f "$NP_EVERY_NOTE"
  np_shared_write || return 1
  np_lib_named "$NP_SHARED_LIBRARY" || ! np_lib_ours "$NP_SHARED_LIBRARY" || /bin/rm -f "$NP_PLUGINS/$(basename "$NP_SHARED_LIBRARY")"
  return 0
}
