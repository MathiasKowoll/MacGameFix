#!/usr/bin/env bash
#
# Internal helper that installs the source-built Forza Horizon 5 Xbox UDP fix.
# The user-facing install-fh5-fix.sh calls this together with the D3D12 fix.
#
#   MGVF_BOTTLE=/path/to/pfx install-fh5-netfix.sh <game folder>
#   MGVF_BOTTLE=/path/to/pfx install-fh5-netfix.sh <game folder> --status
#   MGVF_BOTTLE=/path/to/pfx install-fh5-netfix.sh <game folder> --restore
#
# No DLL from the reference release is installed. ws2_32-fh5.dll is built from
# fh5-netfix.c, against the export table of the Wine ws2_32 in the NotProton
# runner. The runner's own ws2_32 is copied under the private name ws2_o, which
# is what the proxy forwards to. The prefix's original ws2_32 is kept and put
# back by --restore.
#
# WHAT IT FIXES. Wine does not implement SIO_UDP_NETRESET, and macOS rejects
# IPv4 options on FH5's dual-stack IPv6 Xbox socket. The game then closes that
# socket and cannot enter Horizon Life or Horizon Open. The proxy reports the
# first operation as successful and applies the IPv6 equivalent of a failing
# IPv4 option before reporting success.
#
# These failures explain offline Horizon Life; the D3D12 proxy, not this socket
# proxy, is what fixed the earlier endless loading after Xbox sign-in.
# MGVF-LOG: fh5-netfix.log
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail
: "${HOME:?this needs HOME; a caller passing an explicit environment must include it}"

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="${1:-}"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi

usage() { sed -n '3,11p' "$0" >&2; exit 1; }
[ -n "$GAME" ] || usage
[ -f "$GAME/ForzaHorizon5.exe" ] || {
  echo "error: no ForzaHorizon5.exe in $GAME" >&2
  echo "       Pick the folder where Steam installed Forza Horizon 5." >&2
  exit 1
}

. "$HERE/bottles.sh"

PFX="${MGVF_BOTTLE:-}"
PFX="${PFX%/}"
[ -n "$PFX" ] && [ -f "$PFX/user.reg" ] && [ -d "$PFX/drive_c/windows/system32" ] || {
  echo "error: this fix needs the Steam Play prefix in MGVF_BOTTLE." >&2
  echo "       It must contain user.reg and drive_c/windows/system32. Nothing was changed." >&2
  exit 1
}

# MacGameFix can be told the exact engine. For a NotProton Steam Play prefix it
# can also recover it from NotProton's build record beside pfx, so the app does
# not have to guess among several runner copies.
find_runner() {
  if [ -n "${MGVF_CX:-}" ]; then
    [ -x "${MGVF_CX%/}/bin/wine" ] || {
      echo "error: MGVF_CX does not name a CrossOver runner: $MGVF_CX" >&2
      return 1
    }
    printf '%s\n' "${MGVF_CX%/}"
    return 0
  fi
  local record build candidate
  record="$(dirname "$PFX")/notproton-build"
  [ -f "$record" ] || return 1
  IFS= read -r build < "$record"
  [ -n "$build" ] || return 1
  candidate="$HOME/Library/Application Support/notproton/runners/crossover-$build/CrossOver"
  [ -x "$candidate/bin/wine" ] || return 1
  printf '%s\n' "$candidate"
}

RUNNER="$(find_runner)" || {
  echo "error: could not identify the CrossOver/NotProton runner that owns this prefix." >&2
  echo "       Set MGVF_CX to its CrossOver folder. Nothing was changed." >&2
  exit 1
}
W="$RUNNER/lib/wine/x86_64-windows"
U="$RUNNER/lib/wine/x86_64-unix"
SYS="$PFX/drive_c/windows/system32"
REAL="$W/ws2_32.dll"
REAL_UNIX="$U/ws2_32.so"
R_ALIAS="$W/ws2_o.dll"
U_ALIAS="$U/ws2_o.so"
OWNERS="$W/.mgf-fh5-netfix-owners"
PROXY="$HERE/ws2_32-fh5.dll"
LIVE="$SYS/ws2_32.dll"
STOCK="$SYS/ws2_32.dll.mgf-stock"
P_ALIAS="$SYS/ws2_o.dll"
P_KEPT="$SYS/ws2_o.dll.mgf-original"
KEY="Software\\Wine\\AppDefaults\\ForzaHorizon5.exe\\DllOverrides"
VALUE="*ws2_32"

[ -f "$REAL" ] && [ -f "$REAL_UNIX" ] || {
  echo "error: this runner has no x86_64 ws2_32 pair: $RUNNER" >&2
  exit 1
}
[ -f "$PROXY" ] || { echo "error: ws2_32-fh5.dll is not beside this installer" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EXPECTED="$WORK/ws2_o.dll"
cp -p "$REAL" "$EXPECTED"
perl "$HERE/pe.pl" rename-export "$EXPECTED" ws2_o.dll >/dev/null

# A proxy is safe only with the exact names and ordinals of this runner. This
# refuses an engine update instead of forwarding an ordinal to the wrong API.
perl "$HERE/pe.pl" exports "$REAL" --ordinals > "$WORK/real.exports"
perl "$HERE/pe.pl" exports "$PROXY" --ordinals > "$WORK/proxy.exports"
cmp -s "$WORK/real.exports" "$WORK/proxy.exports" || {
  echo "error: ws2_32-fh5.dll was built for another Wine export table." >&2
  echo "       Rebuild it with build-fh5-netfix.sh against $REAL. Nothing was changed." >&2
  exit 1
}

is_proxy() { [ -f "$1" ] && cmp -s "$1" "$PROXY"; }
is_alias() { [ -f "$1" ] && cmp -s "$1" "$EXPECTED"; }
override_present() { user_reg_has_value "$PFX" "$KEY" "$VALUE"; }

stopped() {
  local rc=0
  bottle_server_alive "$PFX" || rc=$?
  case "$rc" in
    1) return 0 ;;
    0) echo "error: something is running in this prefix: $PFX" >&2
       echo "       Quit Forza and Steam, then try again. Nothing was changed." >&2 ;;
    *) echo "error: cannot tell whether this prefix is stopped. Nothing was changed." >&2 ;;
  esac
  return 1
}

runner_aliases_ok() {
  is_alias "$R_ALIAS" && [ -L "$U_ALIAS" ] && [ "$(readlink "$U_ALIAS")" = ws2_32.so ] && [ -e "$U_ALIAS" ]
}

status() {
  local pieces=0 o=1
  is_proxy "$LIVE" && pieces=$((pieces + 1))
  is_alias "$P_ALIAS" && pieces=$((pieces + 1))
  runner_aliases_ok && pieces=$((pieces + 1))
  override_present && o=0 && pieces=$((pieces + 1)) || true
  echo "looking at $PFX and $RUNNER"
  if [ "$pieces" -eq 4 ]; then
    echo installed
  elif [ "$pieces" -gt 0 ]; then
    echo "Why: only $pieces of 4 network-fix parts are in place"
    echo half
  else
    echo absent
  fi
}

owner_present() { [ -f "$OWNERS" ] && /usr/bin/grep -Fqx "owner=$PFX" "$OWNERS"; }

add_owner() {
  local made_dll="$1" made_so="$2"
  if [ ! -f "$OWNERS" ]; then
    {
      echo "created-dll=$made_dll"
      echo "created-so=$made_so"
    } > "$OWNERS"
  else
    /usr/bin/grep -Eq '^created-dll=[01]$' "$OWNERS" && /usr/bin/grep -Eq '^created-so=[01]$' "$OWNERS" || {
      echo "error: the runner ownership record is malformed: $OWNERS" >&2
      return 1
    }
  fi
  owner_present || echo "owner=$PFX" >> "$OWNERS"
}

drop_owner_and_maybe_aliases() {
  [ -f "$OWNERS" ] || return 0
  local next="$WORK/owners" made_dll=0 made_so=0
  /usr/bin/grep -vF "owner=$PFX" "$OWNERS" > "$next" || true
  if /usr/bin/grep -q '^owner=' "$next"; then
    mv -f "$next" "$OWNERS"
    return 0
  fi
  /usr/bin/grep -q '^created-dll=1$' "$next" && made_dll=1 || true
  /usr/bin/grep -q '^created-so=1$' "$next" && made_so=1 || true
  if [ "$made_dll" = 1 ]; then
    if is_alias "$R_ALIAS"; then rm -f "$R_ALIAS"
    elif [ -e "$R_ALIAS" ]; then echo "warning: runner ws2_o.dll changed after installation, so it stays" >&2; fi
  fi
  if [ "$made_so" = 1 ]; then
    if [ -L "$U_ALIAS" ] && [ "$(readlink "$U_ALIAS")" = ws2_32.so ]; then rm -f "$U_ALIAS"
    elif [ -e "$U_ALIAS" ] || [ -L "$U_ALIAS" ]; then echo "warning: runner ws2_o.so changed after installation, so it stays" >&2; fi
  fi
  rm -f "$OWNERS"
}

case "$MODE" in
  --status) status; exit 0 ;;
  --restore)
    stopped || exit 1
    if is_proxy "$LIVE"; then
      if [ -f "$STOCK" ] && ! is_proxy "$STOCK"; then mv -f "$STOCK" "$LIVE"
      else rm -f "$LIVE" "$STOCK"; fi
    elif [ -f "$LIVE" ]; then
      echo "the prefix's ws2_32.dll is not ours; it stays"
    fi
    if is_alias "$P_ALIAS"; then rm -f "$P_ALIAS"; fi
    if [ ! -e "$P_ALIAS" ] && [ -f "$P_KEPT" ]; then mv -f "$P_KEPT" "$P_ALIAS"; fi
    user_reg_edit "$PFX" delete "$KEY" "$VALUE" || {
      echo "error: could not remove the Forza-only DLL override" >&2
      exit 1
    }
    drop_owner_and_maybe_aliases
    echo "restored the prefix's ws2_32.dll and removed the Forza-only override"
    echo restored
    exit 0 ;;
  --install|install) ;;
  *) usage ;;
esac

stopped || exit 1

# Refuse ambiguous files before moving any of them.
if [ -e "$R_ALIAS" ] && ! is_alias "$R_ALIAS"; then
  echo "error: the runner already has a different ws2_o.dll; it was not touched." >&2
  exit 1
fi
if [ -e "$U_ALIAS" ] || [ -L "$U_ALIAS" ]; then
  [ -L "$U_ALIAS" ] && [ "$(readlink "$U_ALIAS")" = ws2_32.so ] && [ -e "$U_ALIAS" ] || {
    echo "error: the runner already has a different or broken ws2_o.so; it was not touched." >&2
    exit 1
  }
fi
if [ -f "$STOCK" ] && is_proxy "$STOCK"; then
  echo "error: the kept ws2_32.dll is another proxy, not the prefix original." >&2
  exit 1
fi
if [ -f "$LIVE" ] && ! is_proxy "$LIVE" && [ -f "$STOCK" ]; then
  echo "error: both a non-fix ws2_32.dll and a kept original exist in system32." >&2
  echo "       Nothing was changed; decide which one is the original first." >&2
  exit 1
fi
if [ -f "$P_ALIAS" ] && ! is_alias "$P_ALIAS" && [ -f "$P_KEPT" ]; then
  echo "error: both a different ws2_o.dll and a kept original exist in system32." >&2
  exit 1
fi

made_dll=0
made_so=0
if [ ! -e "$R_ALIAS" ]; then cp -p "$EXPECTED" "$R_ALIAS"; made_dll=1; fi
if [ ! -e "$U_ALIAS" ] && [ ! -L "$U_ALIAS" ]; then ln -s ws2_32.so "$U_ALIAS"; made_so=1; fi
add_owner "$made_dll" "$made_so"

if [ -f "$P_ALIAS" ] && ! is_alias "$P_ALIAS"; then mv -f "$P_ALIAS" "$P_KEPT"; fi
cp -p "$EXPECTED" "$P_ALIAS.mgf-new"
mv -f "$P_ALIAS.mgf-new" "$P_ALIAS"

if [ -f "$LIVE" ] && ! is_proxy "$LIVE" && [ ! -f "$STOCK" ]; then mv -f "$LIVE" "$STOCK"; fi
cp -p "$PROXY" "$LIVE.mgf-new"
mv -f "$LIVE.mgf-new" "$LIVE"

user_reg_edit "$PFX" set "$KEY" "$VALUE" "native,builtin" || {
  echo "error: the files are in place, but the Forza-only DLL override could not be written" >&2
  exit 1
}

runner_aliases_ok && is_alias "$P_ALIAS" && is_proxy "$LIVE" && override_present || {
  echo "error: installation did not verify; --status reports which part is missing" >&2
  exit 1
}

echo "installed the source-built ws2_32 proxy for ForzaHorizon5.exe only"
echo installed
