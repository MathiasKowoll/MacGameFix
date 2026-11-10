#!/usr/bin/env bash
#
# Install (or remove) the source-built Forza Horizon 5 fix for D3DMetal and
# Xbox networking under a NotProton Steam Play prefix.
#
#   MGVF_BOTTLE=/path/to/pfx install-fh5-fix.sh <game folder>
#   MGVF_BOTTLE=/path/to/pfx install-fh5-fix.sh <game folder> --status
#   MGVF_BOTTLE=/path/to/pfx install-fh5-fix.sh <game folder> --restore
#
# The shipped d3d12-fh5.dll is built from fh5-d3d12/, not copied from a release.
# The real apd12.dll carrier is made at install time from this runner's own
# D3DMetal d3d12.dll. MacGameFix therefore redistributes no Apple DLL.
#
# WHAT IT FIXES. D3DMetal's descriptor increment and several D3D12 behaviours
# differ from the NVIDIA-like device FH5 expects. The game used to finish Xbox
# sign-in, then stay forever in its blurred loading screen. With the proxy it
# reaches PLEASE WAIT, Optimizing for your PC and the normal game load. The
# companion ws2_32 proxy keeps FH5's Xbox UDP socket open for Horizon Life.
#
# MGVF-SCOPE: prefix
# MGVF-GAME: Forza Horizon 5 | ForzaHorizon5.exe |
# MGVF-WHY: After Xbox sign-in it never leaves the blurred loading screen: a source-built D3D12 proxy translates the NVIDIA-style descriptor layout Forza expects to D3DMetal and fills the D3D12 gaps it reaches; the Xbox UDP proxy keeps online play's socket open.
# MGVF-LOG: fh5-netfix.log
# MGVF-CREDIT: xvferxedd, fh5-d3dmetal-fix (github.com/xvferxedd/fh5-d3dmetal-fix, no longer online) | https://github.com/Andytizer/fh5-crossover-steam-fix/tree/main/upstream/source
# MGVF-CREDIT: Andytizer, who preserved it (fh5-crossover-steam-fix) | https://github.com/Andytizer/fh5-crossover-steam-fix
# MGVF-CREDIT: Gauthier Piarrette (Highball tsshim) | https://github.com/gauthierpiarrette/highball
# MGVF-CREDIT: MACxus (FH5 profile: the NVIDIA identity)
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

find_runner() {
  if [ -n "${MGVF_CX:-}" ]; then
    [ -x "${MGVF_CX%/}/bin/wine" ] || return 1
    printf '%s\n' "${MGVF_CX%/}"
    return 0
  fi
  local record build candidate
  record="$(dirname "$PFX")/notproton-build"
  if [ -f "$record" ]; then
    IFS= read -r build < "$record"
    [ -n "$build" ] || return 1
    candidate="$HOME/Library/Application Support/notproton/runners/crossover-$build/CrossOver"
    [ -x "$candidate/bin/wine" ] || return 1
    printf '%s\n' "$candidate"
    return 0
  fi
  if command -v crossover_for_bottle >/dev/null 2>&1; then
    candidate="$(crossover_for_bottle "$PFX" 2>/dev/null)" || return 1
    [ -n "$candidate" ] && [ -x "$candidate/bin/wine" ] || return 1
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

RUNNER="$(find_runner)" || {
  echo "error: could not identify the CrossOver/NotProton runner that owns this prefix." >&2
  echo "       Set MGVF_CX to its CrossOver folder. Nothing was changed." >&2
  exit 1
}

# D3DMetal is kept apart from Wine's normal d3d12. NotProton's d3dmetal
# backend selects apple_gptk; apple_gptk3 is accepted for older runners.
find_d3dmetal() {
  local root="$1" name
  for name in apple_gptk apple_gptk3; do
    if [ -f "$root/lib/$name/wine/x86_64-windows/d3d12.dll" ] \
       && [ -f "$root/lib/$name/wine/x86_64-unix/d3d12.so" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  return 1
}

BACKEND="$(find_d3dmetal "$RUNNER")" || {
  echo "error: this runner has no complete D3DMetal x86_64 module." >&2
  echo "       Select D3DMetal for this game and install GPTK/D3DMetal first." >&2
  exit 1
}

W="$RUNNER/lib/wine/x86_64-windows"
U="$RUNNER/lib/wine/x86_64-unix"
REAL="$RUNNER/lib/$BACKEND/wine/x86_64-windows/d3d12.dll"
REAL_UNIX="$RUNNER/lib/$BACKEND/wine/x86_64-unix/d3d12.so"
R_ALIAS="$W/apd12.dll"
U_ALIAS="$U/apd12.so"
U_TARGET="../../$BACKEND/wine/x86_64-unix/d3d12.so"
OWNERS="$W/.mgf-fh5-d3d12-owners"
SYS="$PFX/drive_c/windows/system32"
P_ALIAS="$SYS/apd12.dll"
P_KEPT="$SYS/apd12.dll.mgf-original"
PROXY="$HERE/d3d12-fh5.dll"
LIVE="$GAME/d3d12.dll"
KEPT="$GAME/d3d12.dll.mgf-original"
KEY="Software\\Wine\\AppDefaults\\ForzaHorizon5.exe\\DllOverrides"
VALUE="*d3d12"
NET_INSTALLER="$HERE/install-fh5-netfix.sh"
NET_PROXY="$HERE/ws2_32-fh5.dll"
NOTICES="$HERE/fh5-THIRD-PARTY-LICENCES.md"

[ -f "$PROXY" ] || { echo "error: d3d12-fh5.dll is not beside this installer" >&2; exit 1; }
[ -x "$NET_INSTALLER" ] && [ -f "$NET_PROXY" ] || {
  echo "error: the FH5 network-fix helper or its payload is missing" >&2
  exit 1
}
[ -f "$NOTICES" ] || { echo "error: the FH5 third-party notices are missing" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EXPECTED="$WORK/apd12.dll"
cp -p "$REAL" "$EXPECTED"
perl "$HERE/pe.pl" rename-export "$EXPECTED" apd12.dll >/dev/null

# Refuse a proxy built with a different D3D12 export table.
perl "$HERE/pe.pl" exports "$REAL" --ordinals > "$WORK/real.exports"
perl "$HERE/pe.pl" exports "$PROXY" --ordinals > "$WORK/proxy.exports"
cmp -s "$WORK/real.exports" "$WORK/proxy.exports" || {
  echo "error: d3d12-fh5.dll does not match this D3DMetal export table." >&2
  echo "       Nothing was changed." >&2
  exit 1
}

# NotProton launches through a per-game runner clone. Install the same private
# alias there when it exists; otherwise the next launch can clone the base
# runner that was just prepared.
CLONE=""
if [ -f "$(dirname "$PFX")/notproton-build" ]; then
  candidate="$HOME/Library/Application Support/notproton/launchers/1551360/runner"
  [ ! -x "$candidate/bin/wine" ] || CLONE="$candidate"
fi
if [ -n "$CLONE" ]; then
  CLONE_BACKEND="$(find_d3dmetal "$CLONE")" || {
    echo "error: Forza's NotProton runner clone has no D3DMetal module." >&2
    exit 1
  }
  CLONE_REAL="$CLONE/lib/$CLONE_BACKEND/wine/x86_64-windows/d3d12.dll"
  cmp -s "$CLONE_REAL" "$REAL" || {
    echo "error: Forza's runner clone and its base runner have different D3DMetal DLLs." >&2
    echo "       Let NotProton refresh the clone, then install again. Nothing was changed." >&2
    exit 1
  }
fi

is_proxy() { [ -f "$1" ] && cmp -s "$1" "$PROXY"; }
is_alias() { [ -f "$1" ] && cmp -s "$1" "$EXPECTED"; }
override_present() { user_reg_has_value "$PFX" "$KEY" "$VALUE"; }
pair_ok() {
  local root="$1" backend="$2"
  is_alias "$root/lib/wine/x86_64-windows/apd12.dll" \
    && [ -L "$root/lib/wine/x86_64-unix/apd12.so" ] \
    && [ "$(readlink "$root/lib/wine/x86_64-unix/apd12.so")" = "../../$backend/wine/x86_64-unix/d3d12.so" ] \
    && [ -e "$root/lib/wine/x86_64-unix/apd12.so" ]
}

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

net_status() {
  MGVF_CX="$RUNNER" MGVF_BOTTLE="$PFX" MGVF_STATUS_ONLY=1 \
    "$NET_INSTALLER" "$GAME" --status 2>/dev/null | tail -1
}

d3d_parts() {
  local pieces=0 total=4
  is_proxy "$LIVE" && pieces=$((pieces + 1))
  is_alias "$P_ALIAS" && pieces=$((pieces + 1))
  pair_ok "$RUNNER" "$BACKEND" && pieces=$((pieces + 1))
  override_present && pieces=$((pieces + 1)) || true
  if [ -n "$CLONE" ]; then
    total=5
    pair_ok "$CLONE" "$CLONE_BACKEND" && pieces=$((pieces + 1))
  fi
  printf '%s %s\n' "$pieces" "$total"
}

status() {
  local pieces total net
  read -r pieces total < <(d3d_parts)
  net="$(net_status || true)"
  echo "looking at $PFX and $RUNNER"
  if [ "$pieces" -eq "$total" ] && [ "$net" = installed ]; then
    echo installed
  elif [ "$pieces" -gt 0 ] || [ "$net" = installed ] || [ "$net" = half ]; then
    echo "Why: $pieces of $total D3D parts are in place; network fix is ${net:-absent}" >&2
    echo half
  else
    echo absent
  fi
}

owner_present() { [ -f "$OWNERS" ] && /usr/bin/grep -Fqx "owner=$PFX" "$OWNERS"; }
add_owner() {
  local made_dll="$1" made_so="$2"
  if [ ! -f "$OWNERS" ]; then
    { echo "created-dll=$made_dll"; echo "created-so=$made_so"; } > "$OWNERS"
  else
    /usr/bin/grep -Eq '^created-dll=[01]$' "$OWNERS" \
      && /usr/bin/grep -Eq '^created-so=[01]$' "$OWNERS" || return 1
  fi
  owner_present || echo "owner=$PFX" >> "$OWNERS"
}

drop_owner() {
  [ -f "$OWNERS" ] || return 0
  local next="$WORK/owners" made_dll=0 made_so=0
  /usr/bin/grep -vF "owner=$PFX" "$OWNERS" > "$next" || true
  if /usr/bin/grep -q '^owner=' "$next"; then mv -f "$next" "$OWNERS"; return 0; fi
  /usr/bin/grep -q '^created-dll=1$' "$next" && made_dll=1 || true
  /usr/bin/grep -q '^created-so=1$' "$next" && made_so=1 || true
  if [ "$made_dll" = 1 ] && is_alias "$R_ALIAS"; then rm -f "$R_ALIAS"; fi
  if [ "$made_so" = 1 ] && [ -L "$U_ALIAS" ] && [ "$(readlink "$U_ALIAS")" = "$U_TARGET" ]; then rm -f "$U_ALIAS"; fi
  rm -f "$OWNERS"
}

place_pair() {
  local root="$1" backend="$2" win unix target
  win="$root/lib/wine/x86_64-windows/apd12.dll"
  unix="$root/lib/wine/x86_64-unix/apd12.so"
  target="../../$backend/wine/x86_64-unix/d3d12.so"
  if [ -e "$win" ] && ! is_alias "$win"; then
    echo "error: $win is a different file; it was not touched." >&2
    return 1
  fi
  if [ -e "$unix" ] || [ -L "$unix" ]; then
    [ -L "$unix" ] && [ "$(readlink "$unix")" = "$target" ] && [ -e "$unix" ] || {
      echo "error: $unix is a different or broken link; it was not touched." >&2
      return 1
    }
  fi
  [ -e "$win" ] || cp -p "$EXPECTED" "$win"
  [ -e "$unix" ] || ln -s "$target" "$unix"
  pair_ok "$root" "$backend"
}

case "$MODE" in
  --status) status; exit 0 ;;
  --restore)
    stopped || exit 1
    net_rc=0
    MGVF_CX="$RUNNER" MGVF_BOTTLE="$PFX" "$NET_INSTALLER" "$GAME" --restore || net_rc=$?
    if is_proxy "$LIVE"; then
      if [ -f "$KEPT" ] && ! is_proxy "$KEPT"; then mv -f "$KEPT" "$LIVE"
      else rm -f "$LIVE" "$KEPT"; fi
    else
      [ -f "$LIVE" ] && echo "the game's d3d12.dll is not ours; it stays"
    fi
    if is_alias "$P_ALIAS"; then rm -f "$P_ALIAS"; fi
    if [ ! -e "$P_ALIAS" ] && [ -f "$P_KEPT" ]; then mv -f "$P_KEPT" "$P_ALIAS"; fi
    user_reg_edit "$PFX" delete "$KEY" "$VALUE" || true
    if [ -n "$CLONE" ]; then
      cw="$CLONE/lib/wine/x86_64-windows/apd12.dll"
      cu="$CLONE/lib/wine/x86_64-unix/apd12.so"
      is_alias "$cw" && rm -f "$cw"
      [ -L "$cu" ] && [ "$(readlink "$cu")" = "../../$CLONE_BACKEND/wine/x86_64-unix/d3d12.so" ] && rm -f "$cu"
    fi
    drop_owner
    echo "restored the game's D3D12 path and the FH5 network fix"
    [ "$net_rc" = 0 ] || exit "$net_rc"
    echo restored
    exit 0 ;;
  --install|install) ;;
  *) usage ;;
esac

stopped || exit 1

# Refuse ambiguous files before changing anything.
if [ -f "$KEPT" ] && is_proxy "$KEPT"; then
  echo "error: the kept game d3d12.dll is another proxy, not an original." >&2
  exit 1
fi
if [ -f "$LIVE" ] && ! is_proxy "$LIVE" && [ -f "$KEPT" ]; then
  echo "error: both a different game d3d12.dll and a kept original exist." >&2
  exit 1
fi
if [ -f "$P_KEPT" ] && is_alias "$P_KEPT"; then
  echo "error: the kept system32 apd12.dll is another alias, not an original." >&2
  exit 1
fi
if [ -f "$P_ALIAS" ] && ! is_alias "$P_ALIAS" && [ -f "$P_KEPT" ]; then
  echo "error: both a different system32 apd12.dll and a kept original exist." >&2
  exit 1
fi

made_dll=0; made_so=0
[ -e "$R_ALIAS" ] || made_dll=1
[ -e "$U_ALIAS" ] || [ -L "$U_ALIAS" ] || made_so=1
place_pair "$RUNNER" "$BACKEND"
add_owner "$made_dll" "$made_so" || { echo "error: runner ownership record is malformed" >&2; exit 1; }
if [ -n "$CLONE" ]; then place_pair "$CLONE" "$CLONE_BACKEND"; fi

if [ -f "$P_ALIAS" ] && ! is_alias "$P_ALIAS"; then mv -f "$P_ALIAS" "$P_KEPT"; fi
cp -p "$EXPECTED" "$P_ALIAS.mgf-new" && mv -f "$P_ALIAS.mgf-new" "$P_ALIAS"

if [ -f "$LIVE" ] && ! is_proxy "$LIVE"; then mv -f "$LIVE" "$KEPT"; fi
cp -p "$PROXY" "$LIVE.mgf-new" && mv -f "$LIVE.mgf-new" "$LIVE"

user_reg_edit "$PFX" set "$KEY" "$VALUE" native || {
  echo "error: files are in place, but the Forza-only d3d12 override could not be written" >&2
  exit 1
}

is_proxy "$LIVE" && is_alias "$P_ALIAS" && pair_ok "$RUNNER" "$BACKEND" && override_present || {
  echo "error: the D3D installation did not verify; --status reports the missing part" >&2
  exit 1
}
if [ -n "$CLONE" ]; then pair_ok "$CLONE" "$CLONE_BACKEND" || exit 1; fi

# Online play is a separate mechanism but one MacGameFix action installs both.
MGVF_CX="$RUNNER" MGVF_BOTTLE="$PFX" "$NET_INSTALLER" "$GAME" --install || {
  echo "error: the D3D fix is installed, but the Xbox UDP helper failed." >&2
  echo "       Run this installer again after correcting the reported network-fix issue." >&2
  exit 1
}

echo "installed the source-built FH5 D3DMetal and Xbox UDP fixes"
if [ -f "$(dirname "$PFX")/notproton-build" ]; then
  echo "For NotProton, keep these Steam launch variables until MacGameFix can set them per game:"
  echo "  NOTPROTON_ENV_D3DM_VENDOR_ID=4318 NOTPROTON_ENV_D3DM_DEVICE_ID=10118"
  echo "  NOTPROTON_ENV_D3DM_DEVICE_DESCRIPTION=\"NVIDIA GeForce RTX 4070\""
  echo "  NOTPROTON_ENV_WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=\"--disable-features=CalculateNativeWinOcclusion\""
else
  echo "Keep these environment variables on the CrossOver bottle:"
  echo "  D3DM_VENDOR_ID=4318 D3DM_DEVICE_ID=10118"
  echo "  D3DM_DEVICE_DESCRIPTION=\"NVIDIA GeForce RTX 4070\""
  echo "  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=\"--disable-features=CalculateNativeWinOcclusion\""
fi
echo "The Xbox sign-in window also needs WebView2 to run as Windows 7 in this prefix"
echo "(legacy/wiki/Forza-Horizon-5.md, \"Xbox sign-in\")."
echo installed
