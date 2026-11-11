#!/usr/bin/env bash
#
# Install or remove the source-built Forza Horizon 6 D3DMetal compatibility
# proxy in a NotProton Steam Play prefix.
#
#   MGVF_BOTTLE=/path/to/pfx install-fh6-fix.sh <game folder>
#   MGVF_BOTTLE=/path/to/pfx install-fh6-fix.sh <game folder> --status
#   MGVF_BOTTLE=/path/to/pfx install-fh6-fix.sh <game folder> --restore
#
# MGVF-SCOPE: prefix
# MGVF-NEEDS: rosetta
# MGVF-STATUS: WIP
# MGVF-GAME: Forza Horizon 6 | forzahorizon6.exe |
# MGVF-WHY: WIP: sign-in and driving validated on Rosetta with the paired ntdll, timers and exception acceleration. Further routes and hardware remain unvalidated. The game starts on D3DMetal 4, but its shaders hit unsupported SV_ShadingRate paths and several pipelines use D3D12 layouts D3DMetal translates incorrectly; a source-built game-specific proxy fixes those paths without FH5's descriptor-stride translation.
# MGVF-CREDIT: Gauthier Piarrette (Highball tsshim and FH6 measurements) | https://github.com/gauthierpiarrette/highball
# MGVF-CREDIT: xvferxedd, FH6 D3DMetal extensions preserved with fh5-d3dmetal-fix (repository no longer online) | https://github.com/Andytizer/fh5-crossover-steam-fix/tree/main/upstream/source
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail
: "${HOME:?this needs HOME; a caller passing an explicit environment must include it}"

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="${1:-}"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi

usage() { sed -n '3,10p' "$0" >&2; exit 1; }
[ -n "$GAME" ] || usage
[ -f "$GAME/forzahorizon6.exe" ] || {
  echo "error: no forzahorizon6.exe in $GAME" >&2
  echo "       Pick the folder where Steam installed Forza Horizon 6." >&2
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
  echo "error: could not identify the CrossOver/NotProton runner for this prefix." >&2
  echo "       Set MGVF_CX to its CrossOver folder. Nothing was changed." >&2
  exit 1
}

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
  echo "       Select D3DMetal and install GPTK/D3DMetal first." >&2
  exit 1
}

W="$RUNNER/lib/wine/x86_64-windows"
U="$RUNNER/lib/wine/x86_64-unix"
REAL="$RUNNER/lib/$BACKEND/wine/x86_64-windows/d3d12.dll"
R_ALIAS="$W/apd12.dll"
U_ALIAS="$U/apd12.so"
U_TARGET="../../$BACKEND/wine/x86_64-unix/d3d12.so"
OWNERS="$W/.mgf-fh6-d3d12-owners"
SYS="$PFX/drive_c/windows/system32"
P_ALIAS="$SYS/apd12.dll"
P_KEPT="$SYS/apd12.dll.mgf-original"
PROXY="$HERE/d3d12-fh6.dll"
LIVE="$GAME/d3d12.dll"
KEPT="$GAME/d3d12.dll.mgf-original"
KEY="Software\\Wine\\AppDefaults\\forzahorizon6.exe\\DllOverrides"
VALUE="*d3d12"
NOTICES="$HERE/fh5-THIRD-PARTY-LICENCES.md"

[ -f "$PROXY" ] || { echo "error: d3d12-fh6.dll is not beside this installer" >&2; exit 1; }
[ -f "$NOTICES" ] || { echo "error: the Forza third-party notices are missing" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EXPECTED="$WORK/apd12.dll"
cp -p "$REAL" "$EXPECTED"
perl "$HERE/pe.pl" rename-export "$EXPECTED" apd12.dll >/dev/null

perl "$HERE/pe.pl" exports "$REAL" --ordinals > "$WORK/real.exports"
perl "$HERE/pe.pl" exports "$PROXY" --ordinals > "$WORK/proxy.exports"
cmp -s "$WORK/real.exports" "$WORK/proxy.exports" || {
  echo "error: d3d12-fh6.dll does not match this D3DMetal export table." >&2
  echo "       Nothing was changed." >&2
  exit 1
}

CLONE=""
if [ -f "$(dirname "$PFX")/notproton-build" ]; then
  candidate="$HOME/Library/Application Support/notproton/launchers/2483190/runner"
  [ ! -x "$candidate/bin/wine" ] || CLONE="$candidate"
fi
if [ -n "$CLONE" ]; then
  CLONE_BACKEND="$(find_d3dmetal "$CLONE")" || {
    echo "error: FH6's NotProton runner clone has no D3DMetal module." >&2
    exit 1
  }
  CLONE_REAL="$CLONE/lib/$CLONE_BACKEND/wine/x86_64-windows/d3d12.dll"
  cmp -s "$CLONE_REAL" "$REAL" || {
    echo "error: FH6's runner clone and base runner have different D3DMetal DLLs." >&2
    echo "       Let NotProton refresh the clone, then install again. Nothing was changed." >&2
    exit 1
  }
fi

. "$HERE/fh6-runtime.sh"
# Xbox sign-in. XAL looks its device key up with CredEnumerateW("Xbl|DeviceKey*"). On macOS
# Wine's CredEnumerateW also asks the host keychain through mountmgr, which answers
# STATUS_NOT_FOUND when nothing there matches, and CredEnumerateW took that as the failure of
# the whole call although the registry held the key. XAL then made a new device at every
# start, and Xbox asked for sign-in again. advapi32-fh6-<build>.dll is that build's advapi32
# with the host's "not found" taken as no host credential (fh6-advapi32/). It is a Wine
# builtin and replaces the advapi32.dll of FH6's own runner clone, so every other game keeps
# CodeWeavers' file, and only where that file is the one it was built against. Beside the
# game as a native DLL it does not load: every importer of advapi32 then failed with
# c0000135 (measured 2026-11-11 on 41303).
# Bundled: $HERE/advapi32-fh6-27.0.0.41073.dll $HERE/advapi32-fh6-27.0.0.41303.dll
A_SRC="${HERE}/advapi32-fh6-${FH6_BUILD:-none}.dll"
A_LIVE=""
[ -z "$CLONE" ] || A_LIVE="$CLONE/lib/wine/x86_64-windows/advapi32.dll"
A_KEPT="$A_LIVE.mgf-fh6-original"
case "$FH6_BUILD" in
  27.0.0.41073) A_BASE_SHA=7c5e5f2f573e001eabfc39d252428dfcc79c773262b7d00b46301f53fb143dab ;;
  27.0.0.41303) A_BASE_SHA=8790c1b25ce4805c6f5fe1f5f103ea51c9439869c04297763652f2970b94febc ;;
  *) A_BASE_SHA="" ;;
esac
is_advapi() { [ -f "$A_SRC" ] && [ -f "$1" ] && cmp -s "$1" "$A_SRC"; }
is_any_advapi() { cmp -s "$1" "$HERE/advapi32-fh6-27.0.0.41073.dll" 2>/dev/null || cmp -s "$1" "$HERE/advapi32-fh6-27.0.0.41303.dll" 2>/dev/null; }
is_base_advapi() { [ -n "$A_BASE_SHA" ] && [ "$(fh6sha "$1")" = "$A_BASE_SHA" ]; }
# The clone's file is CodeWeavers' own, or ours over a kept CodeWeavers' own.
advapi_fits() {
  [ -n "$A_LIVE" ] && [ -f "$A_SRC" ] || return 1
  is_base_advapi "$A_LIVE" || { is_advapi "$A_LIVE" && is_base_advapi "$A_KEPT"; }
}
# Bundled dependencies used by fh6-runtime.sh:
# $HERE/fh6-launch-options.pl $HERE/notproton-rosetta-trap-boost.dylib

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

parts() {
  local pieces=0 total=4
  is_proxy "$LIVE" && pieces=$((pieces + 1))
  is_alias "$P_ALIAS" && pieces=$((pieces + 1))
  pair_ok "$RUNNER" "$BACKEND" && pieces=$((pieces + 1))
  override_present && pieces=$((pieces + 1)) || true
  if [ -n "$CLONE" ]; then
    total=5
    pair_ok "$CLONE" "$CLONE_BACKEND" && pieces=$((pieces + 1))
  fi
  if advapi_fits; then
    total=$((total + 1))
    is_advapi "$A_LIVE" && pieces=$((pieces + 1))
  fi
  total=$((total + 2))
  fh6_runtime_ok && pieces=$((pieces + 1)) || true
  fh6_options status >/dev/null 2>&1 && pieces=$((pieces + 1)) || true
  printf '%s %s\n' "$pieces" "$total"
}

status() {
  if [ "$(fh6sha "$GAME/forzahorizon6.exe")" != "$GAME_SHA" ]; then
    echo "Why: this game update has not been validated for the FH6 WIP runtime"
    echo norecipe; return
  fi
  local pieces total
  read -r pieces total < <(parts)
  echo "looking at $PFX and $RUNNER"
  if [ "$pieces" -eq "$total" ]; then echo installed
  elif [ "$pieces" -gt 0 ]; then
    echo "Why: $pieces of $total compatibility components are in place (D3D12, ntdll, Xbox sign-in and launch options)" >&2
    echo half
  else echo absent; fi
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
  local next="$WORK/owners" made_dll=0 made_so=0 other="$W/.mgf-fh5-d3d12-owners"
  /usr/bin/grep -vF "owner=$PFX" "$OWNERS" > "$next" || true
  if /usr/bin/grep -q '^owner=' "$next"; then mv -f "$next" "$OWNERS"; return 0; fi
  /usr/bin/grep -q '^created-dll=1$' "$next" && made_dll=1 || true
  /usr/bin/grep -q '^created-so=1$' "$next" && made_so=1 || true
  # A shared apd12 carrier must stay while FH5 still owns it.
  if [ ! -f "$other" ] || ! /usr/bin/grep -q '^owner=' "$other"; then
    if [ "$made_dll" = 1 ] && is_alias "$R_ALIAS"; then rm -f "$R_ALIAS"; fi
    if [ "$made_so" = 1 ] && [ -L "$U_ALIAS" ] && [ "$(readlink "$U_ALIAS")" = "$U_TARGET" ]; then rm -f "$U_ALIAS"; fi
  fi
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
  --diagnostics-on|--diagnostics-off)
    stopped || exit 1
    fh6_options "${MODE#--}"
    exit 0 ;;
  --restore)
    stopped || exit 1
    # Do not dismantle an unowned working baseline or an unknown proxy.
    [ -f "$PFX/.mgf-fh6-managed" ] || { echo "error: this baseline was installed outside MacGameFix; removal is not owned here." >&2; exit 1; }
    is_proxy "$LIVE" || { echo "error: D3D12 changed outside MacGameFix; removal refused." >&2; exit 1; }
    fh6_options restore
    fh6_restore_runtime
    if is_proxy "$LIVE"; then
      if [ -f "$KEPT" ] && ! is_proxy "$KEPT"; then mv -f "$KEPT" "$LIVE"
      else rm -f "$LIVE" "$KEPT"; fi
    else [ ! -f "$LIVE" ] || echo "the game's d3d12.dll is not ours; it stays"; fi
    if [ -n "$A_LIVE" ] && [ -f "$A_KEPT" ] && ! is_any_advapi "$A_KEPT" && is_any_advapi "$A_LIVE"; then
      mv -f "$A_KEPT" "$A_LIVE"
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
    echo "restored the game's original D3D12 path"
    rm -f "$PFX/.mgf-fh6-managed"
    echo restored
    exit 0 ;;
  --install|install) ;;
  *) usage ;;
esac

stopped || exit 1
fh6_preflight || exit 1

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

fh6_install_runtime

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
  echo "error: files are in place, but the FH6-only d3d12 override could not be written" >&2
  exit 1
}

is_proxy "$LIVE" && is_alias "$P_ALIAS" && pair_ok "$RUNNER" "$BACKEND" && override_present || {
  echo "error: the D3D installation did not verify; --status reports the missing part" >&2
  exit 1
}
if [ -n "$CLONE" ]; then pair_ok "$CLONE" "$CLONE_BACKEND" || exit 1; fi

if advapi_fits; then
  is_advapi "$A_LIVE" || {
    cp -p "$A_LIVE" "$A_KEPT"
    cp -p "$A_SRC" "$A_LIVE.mgf-new" && mv -f "$A_LIVE.mgf-new" "$A_LIVE"
  }
  is_advapi "$A_LIVE" && is_base_advapi "$A_KEPT" || {
    echo "error: the Xbox sign-in fix did not verify" >&2
    exit 1
  }
  echo "installed the Xbox sign-in fix (advapi32 CredEnumerateW) in FH6's runner clone"
elif [ -z "$A_LIVE" ]; then
  echo "note: FH6 has no runner clone of its own here, and the Xbox sign-in fix goes only there; FH6 asks for sign-in at each start."
else
  echo "note: this runner's advapi32.dll is not one the Xbox sign-in fix was built for; FH6 asks for sign-in at each start."
fi

: > "$PFX/.mgf-fh6-managed"
echo "installed the source-built FH6 D3DMetal compatibility proxy"
echo "The existing native Visual C++ runtime override remains responsible for the November 3 crash fix."
echo installed
