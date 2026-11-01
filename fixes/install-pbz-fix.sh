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
# NOTHING IN THE GAME FOLDER IS TOUCHED, and no file is placed: the fix is nine
# registry values under HKCU\Software\Wine\AppDefaults\PBZ.exe, so they apply to
# this executable only (its Steam bootstrapper and the game share the name).
#
# WHAT THIS FIXES.
#
# Under Rosetta the game's Denuvo spins one core at 100% and never opens a
# window. The Wine modules' ntdll.so (engine patch 0017, the Intel side of
# CrossOver 26.3 and Preview 41073) can show Rosetta's CPU with the leaf 7 bits
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
# What else it needs, and this does not do: the Wine modules on (Wine Modules
# tab), since CrossOver's own ntdll ignores the value; D3DMetal 4 (CrossOver
# Preview 27 carries it; 26.3 carries 3.0); the Intel side, not FEX. Played on
# 2026-11-01 with the same values passed in the launch options, on Preview
# 41073's NotProton runner: it passed Denuvo and was played for 32 minutes.
# Through this installer it has not been played yet.
#
# MGVF-SCOPE: prefix
# MGVF-GAME: Phantom Blade Zero | PBZ.exe | platform/steam
# MGVF-WHY: Never opens a window under Rosetta: its Denuvo checks the CPU for instructions Rosetta does not have. The Wine modules' ntdll shows them to this executable alone, and it loads Microsoft's Visual C++ runtime first.
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
COUNT=9   # the CPUID value and one override per DLL

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

status() {
  local n
  n="$(present)"
  if [ "$n" -eq "$COUNT" ]; then echo installed
  elif [ "$n" -gt 0 ]; then echo half
  else echo absent; fi
}

case "$ACTION" in
  --status) status; exit 0 ;;
  --restore)
      gone=1
      if [ -n "$PFX" ]; then
        prefix_stopped "$PFX" || exit 1
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
        echo "removed the values for $EXE"
        echo "restored"
      else
        echo "warning: some of the values for $EXE could not be taken out; --status says which state is left." >&2
        echo "restored-except-registry"
      fi
      exit 0 ;;
  install) ;;
  *) usage ;;
esac

if [ -n "$PFX" ]; then
  prefix_stopped "$PFX" || exit 1
  while IFS='|' read -r key name data; do
    # Written and then read back, as install-ng3-fix.sh does.
    if ! user_reg_edit "$PFX" set "$key" "$name" "$data" \
       || ! user_reg_has_value "$PFX" "$key" "$name"; then
      echo "error: could not write $name into $PFX/user.reg" >&2
      exit 1
    fi
  done < <(values)
  echo "  $COUNT values written for $EXE only, into the prefix's user.reg"
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
    || echo "note: this CrossOver's ntdll.so does not read $CPUID_NAME; turn the Wine modules on for it."
fi
echo "installed"
