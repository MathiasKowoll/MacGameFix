#!/usr/bin/env bash
#
# Install (or remove) the fix for Phantom Blade Zero.
#
#   install-pbz-fix.sh <bottle>            install
#   install-pbz-fix.sh <bottle> --restore  remove
#   install-pbz-fix.sh <bottle> --status   report what is in place
#
# <bottle> is the CrossOver bottle the game runs in, e.g.
#   ~/Library/Application Support/CrossOver/Bottles/Steam
# or the Steam Play prefix a runner such as NotProton keeps for it,
#   .../steamapps/compatdata/4115450/pfx
#
# NOTHING IN THE GAME FOLDER IS TOUCHED. The fix is ten registry values under
# HKCU\Software\Wine\AppDefaults\PBZ.exe, so they apply to this executable only
# (its Steam bootstrapper and the game share the name), and one DLL in the
# prefix's system32, msmpeg2vdec.dll, which only that override loads; CrossOver's
# own is kept beside it as msmpeg2vdec.dll.mgvf-stock and every other program
# keeps CrossOver's builtin.
#
# WHAT THIS FIXES.
#
# Under Rosetta the game's Denuvo spins one core at 100% and never opens a
# window. The Rosetta improvement's ntdll.so (engine patch 0017, the Intel side of a
# CrossOver app or of NotProton's 41073 runner) can show Rosetta's CPU with the leaf 7 bits
# the protection checks for, CLFLUSHOPT, CLWB and RDPID, and emulate the two
# instructions; it does so for a process only when WINE_ROSETTA_CPUID7_OR asks,
# and reads that from AppDefaults\<exe>\Environment as well as from the
# environment. The registry reaches the game when a Steam client that was already
# running starts it, which the launch's environment does not, and NotProton
# drops WINE_* variables from launch options.
#
# The game also checks its Visual C++ runtime and quits on Wine's builtin one,
# so msvcp140 and vcruntime140 and their parts load native first, for it alone.
#
# Its menu video is H.264 through Unreal's Electra, which takes NV12 and nothing
# else, and CrossOver on macOS does not offer NV12 from its H.264 decoder while
# saying the decoder is D3D aware: the menu stays black. msmpeg2vdec-sw.dll,
# built from h264-software-decoder.c, serves the same decoder class over
# CrossOver's own decoder and answers as winevideo's patch 0006 makes Wine
# answer: NV12 offered, no D3D awareness, so Electra decodes into system memory.
# It is the same file for CrossOver 26.3 and Preview 27.
#
# IN A NOTPROTON PREFIX it also turns on a pipeline cache. The game compiles about
# 66,000 Metal pipelines as it loads, and Metal's own cache stops at about 1.11 GB a
# file, so every start compiled some 40% of them again. NotProton loads
# notproton-rosetta-pipeline-cache.dylib (pbz-pipeline-cache/ORIGIN.md) into the game
# when NOTPROTON_ROSETTA_PIPELINE_CACHE=1 is in its launch options, and it keeps each
# pipeline D3DMetal compiles in a cache of its own, up to 10 GB. So this copies the
# library into NotProton's plugins folder with its descriptor, and puts that variable
# in front of PBZ's Steam launch options, which needs Steam closed. Measured on
# 2026-11-20 with the 41303 runner: the first start with it compiled 65,685 and wrote
# 7.9 GB; the next one compiled 113. A CrossOver bottle has no way to load it.
#
# What else it needs, and this does not do: outside NotProton's 41303 runner on
# Rosetta, the Rosetta improvement (Improvements tab), since CrossOver's own ntdll
# ignores the value (the install says so where it is missing); D3DMetal 4 (CrossOver
# Preview 27 carries it; 26.3 carries 3.0); the Intel side, not FEX. Played on
# 2026-11-01 with the same values passed in the launch options, on Preview
# 41073's NotProton runner: it passed Denuvo and was played for 32 minutes,
# with the menu video from winegstreamer carrying 0006. The decoder DLL was
# measured with a probe on all four CrossOvers (NV12 offered and 30 frames
# decoded into the caller's system-memory samples, where CrossOver's own offers
# no NV12); in the game it has not been played yet.
#
# MGVF-SCOPE: prefix
# MGVF-INSTRUCTIONS: pbz-instructions.md
# MGVF-GAME: Phantom Blade Zero | PBZ.exe | platform/steam
# MGVF-WHY: Never opens a window under Rosetta: its Denuvo checks the CPU for instructions Rosetta does not have. The Rosetta improvement's ntdll shows them to this executable alone, it loads Microsoft's Visual C++ runtime first, and an H.264 decoder that offers NV12 brings back the black menu video. In NotProton it also turns on a pipeline cache, so the shaders Metal's own cache has no room for are not compiled again at every start. On NotProton's 41303 runner on Rosetta the improvement is not needed: the fix switches on the shared Engine fixes row for the game (NOTPROTON_MGF_ENGINE=1), whose library shows the protection that CPU, on NotProton's own ntdll; played that way on 2026-11-25.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '3,14p' "$0" >&2; exit 1; }

# A bottle or a Steam Play prefix, from $1 or MGVF_BOTTLE, as install-ng3-fix.sh
# takes them (it says why both): the app passes the game folder as $1 and the
# place it chose in MGVF_BOTTLE.
is_bottle() { [ -n "$1" ] && [ -f "$1/cxbottle.conf" ] && [ -d "$1/drive_c" ]; }
is_prefix() {
  [ -n "$1" ] && [ -f "$1/user.reg" ] && [ -f "$1/system.reg" ] && [ ! -f "$1/cxbottle.conf" ] && [ -d "$1/drive_c" ]
}

BOTTLE=""
PFX=""
if is_bottle "${1:-}"; then
  BOTTLE="${1%/}"
elif is_prefix "${1:-}"; then
  PFX="${1%/}"
elif is_bottle "${MGVF_BOTTLE:-}"; then
  BOTTLE="${MGVF_BOTTLE%/}"
elif is_prefix "${MGVF_BOTTLE:-}"; then
  PFX="${MGVF_BOTTLE%/}"
else
  echo "error: no bottle or Steam Play prefix to work on." >&2
  echo "       Pass one, e.g. ~/Library/Application Support/CrossOver/Bottles/Steam," >&2
  echo "       or set MGVF_BOTTLE. A bottle is a folder with cxbottle.conf and drive_c;" >&2
  echo "       a Steam Play prefix, one with user.reg, system.reg and drive_c." >&2
  [ -n "${1:-}" ] && echo "       '$1' is not one." >&2
  [ -n "${MGVF_BOTTLE:-}" ] && echo "       MGVF_BOTTLE='$MGVF_BOTTLE' is not one either." >&2
  exit 1
fi
ACTION="${2:-install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then ACTION=--status; fi

EXE="PBZ.exe"
ENV_KEY="Software\\Wine\\AppDefaults\\$EXE\\Environment"
DLL_KEY="Software\\Wine\\AppDefaults\\$EXE\\DllOverrides"
CPUID_NAME="WINE_ROSETTA_CPUID7_OR"
# CLFLUSHOPT and CLWB in EBX, RDPID in ECX: the only bits 0017 accepts.
CPUID_DATA="01800000,00400000"
DLLS="msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids vcruntime140 vcruntime140_1 vcruntime140_threads"
COUNT=10  # the CPUID value, one override per runtime DLL, and the decoder's
# Named literally: build-app.sh ships the files an installer names beside itself.
DECODER="$HERE/msmpeg2vdec-sw.dll"
SYS="${BOTTLE:-$PFX}/drive_c/windows/system32"

# The pipeline cache, for a prefix NotProton keeps (it writes notproton-build beside
# pfx) while NotProton's support folder is there: Remove Everything takes that folder
# away, and this does not make it again.
NP_SUPPORT="$HOME/Library/Application Support/notproton"
PLUGINS="$NP_SUPPORT/plugins"
CACHE_LIB="$HERE/notproton-rosetta-pipeline-cache.dylib"
OPTIONS="$HERE/steam-launch-options.pl"
CACHE_ID=NOTPROTON_ROSETTA_PIPELINE_CACHE
CACHE_CONF="$PLUGINS/rosetta-pipeline-cache.conf"
CACHE_LIVE="$PLUGINS/notproton-rosetta-pipeline-cache.dylib"
APPID=4115450
JOURNAL="$PFX/.mgf-pbz-launch-options.json"
# The same code built before MacGameFix signed it: the experiment's own build and the
# copy its install script signed ad hoc. Either is replaced by the signed one.
CACHE_EARLIER="389defc20850ff9fdc43cfc87b804f15c5243ef738202de559717bdd3229f1d6 0d19abb364a827508b695300bcb85ceafadcf916f210a4a9b9c662366c48b9a2"
NOTPROTON=0
if [ -n "$PFX" ] && [ -f "$(dirname "$PFX")/notproton-build" ] && [ -d "$NP_SUPPORT" ]; then NOTPROTON=1; fi

# MacGameFix's engine fixes for PBZ, through NotProton's shared "Engine fixes" row: the library
# it loads, mgf-engine.dylib, arms in this game alone what engine patches 0017, 0019 and 0020 do
# in the Wine modules' ntdll (Rosetta's CPUID leaf 7, CLWB, RDPID, non-canonical faults, the
# CPUID Rosetta skips), from outside ntdll (engine/mgf-engine.c). PBZ has no row of its own: the
# record is the one other games use (np-plugin-shared.conf, plugins/mgf-shared.conf), and this
# game is added to its apps. On NotProton's runner for CrossOver Preview 41303 on Rosetta, with
# its plugin host, only. That runner keeps NotProton's own ntdll.so, so there the row is what
# shows the game the CPU (played on 2026-11-25), and the CPUID value below goes unread.
ROWS_ON=0
if [ "$NOTPROTON" = 1 ]; then
  . "$HERE/notproton-plugins.sh"
  PBZ_STEAM="${MGVF_STEAM_ROOT:-$HOME/Library/Application Support/Steam}"
  np_plugins_setup "$APPID" "$PFX" "$HERE/np-plugin-pbz.conf"
  NP_SHARED_TEMPLATE="$HERE/np-plugin-shared.conf"; NP_SHARED_LIBRARY="$HERE/mgf-engine.dylib"
  NP_SHARED_USES="NOTPROTON_MGF_ENGINE"
  # The group "MacGameFix" where NotProton knows groups, as F1 25's rows (install-f125-swofty.sh).
  for run in "$PBZ_STEAM"/compatibilitytools.d/notproton-*/run; do
    [ -f "$run" ] && LC_ALL=C /usr/bin/grep -qF 'names[i] == "group"' "$run" && NP_SHARED_GROUP="MacGameFix"
  done
  case "${MGVF_NOTPROTON_GROUPS:-}" in 0) NP_SHARED_GROUP="" ;; 1) NP_SHARED_GROUP="MacGameFix" ;; esac
  # notproton-build: the runner's build, then what it runs on ("... - Rosetta" or "... - FEX").
  { IFS= read -r pbz_build || true; IFS= read -r pbz_side || true; } < "$(dirname "$PFX")/notproton-build"
  case "$pbz_build" in 27.0.0.41303|27.0.0.41303-fex)
    case "$pbz_side" in *Rosetta*)
      [ -f "$NP_SUPPORT/plugin-host.dylib" ] && [ -f "$NP_SHARED_LIBRARY" ] && [ -f "$NP_SHARED_TEMPLATE" ] && ROWS_ON=1 ;;
    esac ;;
  esac
fi

# bottles.sh answers from user.reg without starting wine, and edits a prefix's.
[ -f "$HERE/bottles.sh" ] && . "$HERE/bottles.sh"

wine_in_bottle() {
  local bottle="$1" cx="$2"
  shift 2
  CX_BOTTLE_PATH="$(dirname "$bottle")" \
    "$cx/bin/wine" --bottle "$(basename "$bottle")" "$@"
}

# The CrossOver that owns the bottle, as install-ng3-fix.sh finds it: MGVF_CX
# when the caller names one, else the bottle's own engine, else by name. Running
# reg.exe under another engine updates the bottle to it.
find_crossover() {
  if [ -n "${MGVF_CX:-}" ]; then
    if [ -x "${MGVF_CX%/}/bin/wine" ]; then
      printf '%s' "${MGVF_CX%/}"; return 0
    fi
    echo "error: MGVF_CX is set to '$MGVF_CX' and there is no bin/wine there." >&2
    return 1
  fi
  if command -v crossover_for_bottle >/dev/null 2>&1 && [ -n "${BOTTLE:-}" ]; then
    local byBottle
    if byBottle="$(crossover_for_bottle "$BOTTLE" 2>/dev/null)" && [ -n "$byBottle" ]; then
      printf '%s' "$byBottle"; return 0
    fi
  fi
  local c
  for c in "/Applications/CrossOver.app" "/Applications/CrossOver"*.app "$HOME/Applications/CrossOver"*.app; do
    [ -x "$c/Contents/SharedSupport/CrossOver/bin/wine" ] || continue
    echo "$c/Contents/SharedSupport/CrossOver"; return 0
  done
  return 1
}

reachable() {
  wine_in_bottle "$1" "$2" --cx-app reg.exe query "HKEY_CURRENT_USER\\Software" \
    >/dev/null 2>&1
}

prefix_stopped() {  # prefix_stopped <prefix dir>
  local rc=0
  bottle_server_alive "$1" || rc=$?
  case "$rc" in
  1) return 0 ;;
  0) echo "error: something is running in this prefix: $1" >&2
     echo "       Quit the game first. Nothing was changed." >&2 ;;
  *) echo "error: cannot tell whether anything runs in this prefix: $1" >&2
     echo "       Nothing was changed." >&2 ;;
  esac
  return 1
}

if [ -n "$PFX" ]; then
  command -v user_reg_edit >/dev/null 2>&1 || {
    echo "error: a Steam Play prefix needs bottles.sh beside this script, and it is not there." >&2
    exit 1
  }
fi

# Each value as "<key>|<name>|<data>", one per line.
values() {
  printf '%s|%s|%s\n' "$ENV_KEY" "$CPUID_NAME" "$CPUID_DATA"
  local d
  for d in $DLLS; do printf '%s|*%s|native,builtin\n' "$DLL_KEY" "$d"; done
  # native,builtin: should the prefix lose our file, CrossOver's decoder loads.
  printf '%s|*msmpeg2vdec|native,builtin\n' "$DLL_KEY"
}

# Is our decoder the prefix's msmpeg2vdec.dll.
decoder_placed() { [ -f "$SYS/msmpeg2vdec.dll" ] && cmp -s "$SYS/msmpeg2vdec.dll" "$DECODER"; }

# CrossOver's file back, or ours gone when there is none to put back. A kept
# copy that is ours is not CrossOver's, as install-ng3-fix.sh learned.
decoder_out() {
  if [ -f "$SYS/msmpeg2vdec.dll.mgvf-stock" ] && ! cmp -s "$SYS/msmpeg2vdec.dll.mgvf-stock" "$DECODER"; then
    mv -f "$SYS/msmpeg2vdec.dll.mgvf-stock" "$SYS/msmpeg2vdec.dll"
  elif decoder_placed || [ -f "$SYS/msmpeg2vdec.dll.mgvf-stock" ]; then
    rm -f "$SYS/msmpeg2vdec.dll" "$SYS/msmpeg2vdec.dll.mgvf-stock"
  fi
}

# How many of the values are there. From user.reg for a prefix, and for a bottle
# while nothing runs in it (asking would start wine); otherwise the bottle is asked.
present() {
  local n=0 key name data alive=2 cx=""
  if [ -z "$PFX" ]; then
    if command -v bottle_server_alive >/dev/null 2>&1; then
      bottle_server_alive "$BOTTLE" && alive=0 || alive=$?
    fi
    if [ "$alive" != 1 ] || ! command -v user_reg_has_value >/dev/null 2>&1; then
      cx="$(find_crossover)" && reachable "$BOTTLE" "$cx" || cx=""
    fi
  fi
  while IFS='|' read -r key name data; do
    if [ -n "$cx" ]; then
      wine_in_bottle "$BOTTLE" "$cx" --cx-app reg.exe query "HKEY_CURRENT_USER\\$key" /v "$name" \
        >/dev/null 2>&1 && n=$((n+1))
    else
      user_reg_has_value "${PFX:-$BOTTLE}" "$key" "$name" && n=$((n+1))
    fi
  done < <(values)
  echo "$n"
}

cache_sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
# Our library, or the same code from before it was signed.
cache_lib_ours() {
  [ -f "$CACHE_LIVE" ] || return 1
  cmp -s "$CACHE_LIVE" "$CACHE_LIB" && return 0
  case " $CACHE_EARLIER " in *" $(cache_sha "$CACHE_LIVE") "*) return 0 ;; esac
  return 1
}
# A descriptor for the plugin's id, ours or one the user wrote, and a library for it.
cache_plugin_ok() { [ -f "$CACHE_CONF" ] && /usr/bin/grep -qx "\[$CACHE_ID\]" "$CACHE_CONF" && cache_lib_ours; }
cache_options() { /usr/bin/perl "$OPTIONS" "$1" "$APPID" "$JOURNAL" "$CACHE_ID=1"; }
cache_on() { cache_plugin_ok && cache_options status >/dev/null 2>&1; }
# The plugin can serve other games too: only PBZ's switch says the fix is partly here.
cache_any() { cache_options status >/dev/null 2>&1; }

# The plugin's descriptor. With 1 it names this game ("improves"), so NotProton offers the row on
# PBZ's Compatibility page when it is off; only for a NotProton that reads the field, as one
# that does not refuses the row (notproton-plugins.sh, "THE GAMES A ROW IS FOR").
cache_conf_text() {
  printf '[%s]\nlabel = Rosetta pipeline cache\n' "$CACHE_ID"
  printf "description = Keeps the GPU code of the pipelines D3DMetal compiles in a Rosetta game, beyond Metal's 1.1 GB cache\n"
  [ "$1" != 1 ] || printf 'improves = %s The game compiles far fewer shaders at each start.\n' "$APPID"
  printf 'section = dev\non = 1\ninject = 1\n'
  printf 'requires = Library/Application Support/notproton/plugins/notproton-rosetta-pipeline-cache.dylib\n'
}

cache_install() {
  mkdir -p "$PLUGINS"
  # The library is renamed into place, so a game still running keeps the one it loaded.
  if ! cmp -s "$CACHE_LIVE" "$CACHE_LIB"; then
    if [ -f "$CACHE_LIVE" ] && ! cache_lib_ours; then
      echo "error: $CACHE_LIVE is a different library; it was not touched." >&2
      return 1
    fi
    cp -p "$CACHE_LIB" "$CACHE_LIVE.mgf-new" && mv -f "$CACHE_LIVE.mgf-new" "$CACHE_LIVE"
  fi
  # One the user wrote stays: NotProton refuses a second descriptor for the same id. Ours, as
  # this installer writes it with the game's line or without, is brought to what NotProton reads.
  local named=0 text have
  np_knows_field improves && named=1
  text="$(cache_conf_text "$named")"; have="$(cat "$CACHE_CONF" 2>/dev/null || true)"
  if ! /usr/bin/grep -lqx "\[$CACHE_ID\]" "$PLUGINS"/*.conf 2>/dev/null \
     || { [ "$have" != "$text" ] && { [ "$have" = "$(cache_conf_text 0)" ] || [ "$have" = "$(cache_conf_text 1)" ]; }; }; then
    printf '%s\n' "$text" > "$CACHE_CONF.mgf-new" && mv -f "$CACHE_CONF.mgf-new" "$CACHE_CONF"
  fi
  cache_options install >/dev/null
  echo "  pipeline cache: plugin in NotProton's plugins folder, $CACHE_ID=1 in PBZ's launch options"
}

# Our launch option out; the plugin too once no game's launch options name it.
cache_restore() {
  [ -f "$JOURNAL" ] && { cache_options restore >/dev/null || return 1; }
  local f
  for f in "$HOME/Library/Application Support/Steam/userdata"/*/config/localconfig.vdf; do
    [ -f "$f" ] && /usr/bin/grep -q "$CACHE_ID=1" "$f" && return 0
  done
  if [ -f "$CACHE_CONF" ] && [ "$(/usr/bin/grep -c . "$CACHE_CONF")" -le 8 ] \
     && /usr/bin/grep -qx "requires = Library/Application Support/notproton/plugins/notproton-rosetta-pipeline-cache.dylib" "$CACHE_CONF"; then
    rm -f "$CACHE_CONF"
  fi
  # The library stays while any descriptor still names the id.
  /usr/bin/grep -lqx "\[$CACHE_ID\]" "$PLUGINS"/*.conf 2>/dev/null || ! cache_lib_ours || rm -f "$CACHE_LIVE"
  return 0
}

# The row's files only: a row the player switched off is not a broken fix.
rows_ok() { [ "$ROWS_ON" = 0 ] || [ "$(np_plugins_status | tail -1)" = installed ]; }

status() {
  local n
  n="$(present)"
  if [ "$n" -eq "$COUNT" ] && decoder_placed && { [ "$NOTPROTON" = 0 ] || cache_on; } && rows_ok; then echo installed
  elif [ "$n" -gt 0 ] || decoder_placed || { [ "$NOTPROTON" = 1 ] && cache_any; }; then
    if [ "$n" -eq "$COUNT" ] && decoder_placed; then
      if [ "$NOTPROTON" = 1 ] && ! cache_on; then echo "Why: the pipeline cache is not on in NotProton" >&2
      else echo "Why: NotProton's Engine fixes row is not in place for the game" >&2; fi
    fi
    echo half
  else echo absent; fi
}

case "$ACTION" in
  --status) status; exit 0 ;;
  --restore)
      gone=1
      if [ -n "$PFX" ]; then prefix_stopped "$PFX" || exit 1; fi
      if [ "$NOTPROTON" = 1 ] && [ -f "$JOURNAL" ]; then cache_options preflight >/dev/null || exit 1; fi
      [ "$NOTPROTON" = 0 ] || cache_restore || gone=0
      if [ "$NOTPROTON" = 1 ] && { [ -f "$NP_CONF" ] || [ -f "$NP_SWITCHED" ] || [ -f "$NP_JOURNAL" ]; }; then
        np_plugins_restore || gone=0
      fi
      decoder_out
      if [ -n "$PFX" ]; then
        while IFS='|' read -r key name data; do
          user_reg_edit "$PFX" delete "$key" "$name" || gone=0
        done < <(values)
      elif cx="$(find_crossover)" && reachable "$BOTTLE" "$cx"; then
        while IFS='|' read -r key name data; do
          wine_in_bottle "$BOTTLE" "$cx" --cx-app reg.exe query "HKEY_CURRENT_USER\\$key" /v "$name" >/dev/null 2>&1 || continue
          wine_in_bottle "$BOTTLE" "$cx" --cx-app reg.exe delete "HKEY_CURRENT_USER\\$key" /v "$name" /f \
            >/dev/null 2>&1 || gone=0
        done < <(values)
      else
        gone=0
      fi
      if [ "$gone" = 1 ]; then
        echo "removed the values for $EXE and put CrossOver's msmpeg2vdec.dll back"
        echo "restored"
      else
        echo "warning: some of the values for $EXE could not be taken out; --status says which state is left." >&2
        echo "restored-except-registry"
      fi
      exit 0 ;;
  install) ;;
  *) usage ;;
esac

[ -f "$DECODER" ] || { echo "error: msmpeg2vdec-sw.dll is not beside this script" >&2; exit 1; }
if [ -n "$PFX" ]; then prefix_stopped "$PFX" || exit 1; fi
if [ "$NOTPROTON" = 1 ]; then
  [ -f "$CACHE_LIB" ] && [ -f "$OPTIONS" ] || { echo "error: the pipeline cache's files are not beside this script" >&2; exit 1; }
  # Steam closed, the game in its settings and no wrapper in its options, before anything changes.
  cache_options preflight >/dev/null || exit 1
  if [ "$ROWS_ON" = 1 ]; then np_plugins_preflight || exit 1; fi
fi
[ -d "$SYS" ] || { echo "error: no system32 here yet -- run the game once first" >&2; exit 1; }
# Only CrossOver's own file is kept aside: ours, from an earlier install, is not
# an original to put back.
if [ -f "$SYS/msmpeg2vdec.dll" ] && [ ! -f "$SYS/msmpeg2vdec.dll.mgvf-stock" ] && ! decoder_placed; then
  mv "$SYS/msmpeg2vdec.dll" "$SYS/msmpeg2vdec.dll.mgvf-stock"
fi
cp "$DECODER" "$SYS/msmpeg2vdec.dll"
echo "  msmpeg2vdec.dll  <- msmpeg2vdec-sw.dll"

if [ -n "$PFX" ]; then
  while IFS='|' read -r key name data; do
    # Written and then read back, as install-ng3-fix.sh does.
    if ! user_reg_edit "$PFX" set "$key" "$name" "$data" \
       || ! user_reg_has_value "$PFX" "$key" "$name"; then
      echo "error: could not write $name into $PFX/user.reg" >&2
      exit 1
    fi
  done < <(values)
  echo "  $COUNT values written for $EXE only, into the prefix's user.reg"
  [ "$NOTPROTON" = 0 ] || cache_install || exit 1
  if [ "$ROWS_ON" = 1 ]; then np_plugins_install || exit 1
  elif [ "$NOTPROTON" = 1 ]; then
    # Without the row, only the Rosetta improvement's ntdll.so reads the value.
    pbz_ntdll="$NP_SUPPORT/runners/crossover-$pbz_build/CrossOver/lib/wine/x86_64-unix/ntdll.so"
    /usr/bin/grep -aqF "$CPUID_NAME" "$pbz_ntdll" 2>/dev/null \
      || echo "note: this runner's ntdll.so does not read $CPUID_NAME; put the Rosetta improvement in it."
  fi
else
  cx="$(find_crossover)" || { echo "error: no CrossOver found in /Applications" >&2; exit 1; }
  reachable "$BOTTLE" "$cx" || { echo "error: this bottle cannot run reg.exe, so nothing was written." >&2; exit 1; }
  while IFS='|' read -r key name data; do
    if ! wine_in_bottle "$BOTTLE" "$cx" --cx-app reg.exe add "HKEY_CURRENT_USER\\$key" \
           /v "$name" /d "$data" /f >/dev/null 2>&1 \
       || ! wine_in_bottle "$BOTTLE" "$cx" --cx-app reg.exe query "HKEY_CURRENT_USER\\$key" \
           /v "$name" >/dev/null 2>&1; then
      echo "error: could not write $name" >&2
      exit 1
    fi
  done < <(values)
  echo "  $COUNT values written for $EXE only, through the bottle"
  # The values do nothing under CrossOver's own ntdll.
  /usr/bin/grep -aqF "$CPUID_NAME" "$cx/lib/wine/x86_64-unix/ntdll.so" 2>/dev/null \
    || echo "note: this CrossOver's ntdll.so does not read $CPUID_NAME; put the Rosetta improvement in it."
fi
echo "installed"
