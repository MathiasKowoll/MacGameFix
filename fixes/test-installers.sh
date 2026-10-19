#!/bin/bash
#
# Every folder installer through its life, offline:
#
#     fixes/test-installers.sh
#
# absent -> installed -> an older build ("outdated") -> installed again ->
# restored to the game's own file, and for the fixes that carry a reader, an
# older reader (outdated) and a missing one (broken). KINGDOM HEARTS and NieR
# copy their original out of a bottle, so for them only what --status says is
# tried; nothing here asks or starts a bottle. NINJA GAIDEN 3 goes into a
# prefix, and its whole life is tried in a fake Steam Play one.
#
# No game is needed. The game's "original" is the fix's own DLL with its
# markers and forwarder names blanked: the same exports, and not recognised as
# ours.
#
# It runs the installers as the app does: /bin/bash and the system PATH only.
# (Homebrew's bash 5.3.15 crashed in about 9 runs in 100 here on macOS 27,
# inside CoreFoundation's locale lookup, which reads as an installer failing.)
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
FIX="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$W"' EXIT
fails=0
say() { printf '  %-5s %s\n' "$1" "$2"; [ "$1" = ok ] || { fails=$((fails+1)); ls -la "${g:-/nonexistent}" 2>/dev/null | sed 's/^/        /'; }; }
st() { /bin/bash "$FIX/$1" "$2" --status 2>/dev/null | /usr/bin/grep -E '^(installed|outdated|absent|half|broken)$' | head -1; }
fake() { # fake <proxy> <dest> <marker>...
  /usr/bin/python3 -I - "$@" <<'PY'
import sys
src, dst, *marks = sys.argv[1:]
b = open(src, 'rb').read()
for m in marks + ['_real.']:
    mb = m.encode()
    b = b.replace(mb, b'x' * len(mb))
open(dst, 'wb').write(b)
PY
}
older() { printf 'x' >> "$1"; }

cycle() { # cycle <label> <installer> <game folder> <live> <proxy> [reader live] [reader]
  local label="$1" sh="$2" g="$3" live="$4" proxy="$5" rlive="${6:-}" rsrc="${7:-}"
  local orig; orig="$(mktemp "$W/orig.XXXX")"; cp "$live" "$orig"
  [ "$(st "$sh" "$g")" = absent ] && say ok "$label: absent before" || say FAIL "$label: absent before ($(st "$sh" "$g"))"
  /bin/bash "$FIX/$sh" "$g" > "$W/$label.install1.log" 2>&1 || say FAIL "$label: install failed: $(tail -2 "$W/$label.install1.log")"
  [ "$(st "$sh" "$g")" = installed ] && say ok "$label: installed" || say FAIL "$label: installed ($(st "$sh" "$g"))"
  older "$live"
  [ "$(st "$sh" "$g")" = outdated ] && say ok "$label: an older build is outdated" || say FAIL "$label: older build ($(st "$sh" "$g"))"
  /bin/bash "$FIX/$sh" "$g" > "$W/$label.install2.log" 2>&1 || say FAIL "$label: update failed: $(tail -2 "$W/$label.install2.log")"
  [ "$(st "$sh" "$g")" = installed ] && cmp -s "$live" "$proxy" && say ok "$label: installing again updates it" \
    || say FAIL "$label: update ($(st "$sh" "$g"))"
  if [ -n "$rlive" ]; then
    older "$rlive"
    [ "$(st "$sh" "$g")" = outdated ] && say ok "$label: an older reader is outdated" || say FAIL "$label: older reader ($(st "$sh" "$g"))"
    /bin/bash "$FIX/$sh" "$g" > /dev/null 2>&1
    [ "$(st "$sh" "$g")" = installed ] && cmp -s "$rlive" "$rsrc" && say ok "$label: and updated" || say FAIL "$label: reader update ($(st "$sh" "$g"))"
    rm -f "$rlive"
    [ "$(st "$sh" "$g")" = broken ] && say ok "$label: a missing reader is broken" || say FAIL "$label: missing reader ($(st "$sh" "$g"))"
    /bin/bash "$FIX/$sh" "$g" > /dev/null 2>&1
    [ "$(st "$sh" "$g")" = installed ] && say ok "$label: and repaired" || say FAIL "$label: reader repair ($(st "$sh" "$g"))"
  fi
  /bin/bash "$FIX/$sh" "$g" --restore > "$W/$label.restore.log" 2>&1 || say FAIL "$label: restore failed: $(tail -2 "$W/$label.restore.log")"
  [ "$(st "$sh" "$g")" = absent ] && cmp -s "$live" "$orig" && say ok "$label: restored to the game's own" \
    || say FAIL "$label: restore ($(st "$sh" "$g"))"
}

g="$W/tmnt"; mkdir -p "$g"; touch "$g/TMNTSF.exe"
fake "$FIX/fmod-tmnt.dll" "$g/fmod.dll" d3d12-guards.log rootsig-guard.log
cycle tmnt install-tmnt-fix.sh "$g" "$g/fmod.dll" "$FIX/fmod-tmnt.dll"

g="$W/tormented"; b="$g/TormentedSouls2/Binaries/Win64"; mkdir -p "$b"; touch "$g/TormentedSouls2.exe"
fake "$FIX/OpenColorIO_2_3-tormented.dll" "$b/OpenColorIO_2_3.dll" d3d12-guards.log
cycle tormented install-tormented-fix.sh "$g" "$b/OpenColorIO_2_3.dll" "$FIX/OpenColorIO_2_3-tormented.dll"

g="$W/ctl"; mkdir -p "$g"; touch "$g/CONTROLResonant.exe"
fake "$FIX/PxFoundation_x64-ctl.dll" "$g/PxFoundation_x64.dll" ctl-window-fix.log
cycle ctl install-ctl-fix.sh "$g" "$g/PxFoundation_x64.dll" "$FIX/PxFoundation_x64-ctl.dll"

g="$W/w3"; b="$g/bin/x64_dx12"; mkdir -p "$b"; touch "$b/witcher3.exe"
fake "$FIX/amd_fidelityfx_loader_dx12-w3.dll" "$b/amd_fidelityfx_loader_dx12.dll" w3-streamout-fix.log
cycle w3 install-w3-fix.sh "$g" "$b/amd_fidelityfx_loader_dx12.dll" "$FIX/amd_fidelityfx_loader_dx12-w3.dll"

g="$W/ng4"; mkdir -p "$g"; touch "$g/NINJAGAIDEN4-Steam.exe"
fake "$FIX/dstorage-ng4.dll" "$g/dstorage.dll"
cycle ng4 install-ng4-fix.sh "$g" "$g/dstorage.dll" "$FIX/dstorage-ng4.dll"

g="$W/resonance"; mkdir -p "$g"; touch "$g/Resonance.exe"
fake "$FIX/NvCloth_x64-resonance.dll" "$g/NvCloth_x64.dll"
cycle resonance install-resonance-fix.sh "$g" "$g/NvCloth_x64.dll" "$FIX/NvCloth_x64-resonance.dll"

g="$W/p5s"; mkdir -p "$g"; touch "$g/game.exe"
fake "$FIX/amd_ags_x64.dll" "$g/amd_ags_x64.dll" p5s-video-bridge.log mf-observe.log
cycle p5s install-p5s-bridge.sh "$g" "$g/amd_ags_x64.dll" "$FIX/amd_ags_x64.dll" "$g/mgvf-asf-reader.dll" "$FIX/mgvf-asf-reader.dll"

g="$W/wolong"; mkdir -p "$g"; touch "$g/WoLong.exe"
fake "$FIX/libxess.dll" "$g/libxess.dll" dwo-video-bridge.log
cycle wolong install-dwo-bridge.sh "$g" "$g/libxess.dll" "$FIX/libxess.dll"

g="$W/beast"; o="$g/Engine/Binaries/ThirdParty/Ogg/Win64/VS2015"; mkdir -p "$o"
fake "$FIX/libogg_64.dll" "$o/libogg_64.dll" ue5-runtime-fix.log ue5-vpx-cpupath.log electra-probe.log electra-h264-fix.log ue5-media-fix.log
cycle runtime install-runtime-fix.sh "$g" "$o/libogg_64.dll" "$FIX/libogg_64.dll"

g="$W/gow"; mkdir -p "$g"; touch "$g/GoW.exe"
fake "$FIX/libSceJobManager-gow.dll" "$g/libSceJobManager.dll" gow-depth-fix.log
cycle gow install-gow-fix.sh "$g" "$g/libSceJobManager.dll" "$FIX/libSceJobManager-gow.dll"

g="$W/mk11"; b="$g/Binaries/Retail"; mkdir -p "$b"; touch "$b/MK11_DX12.exe"
fake "$FIX/amd_ags_x64-mk11.dll" "$b/amd_ags_x64.dll" mk11-face-fix.log
cycle mk11 install-mk11-fix.sh "$g" "$b/amd_ags_x64.dll" "$FIX/amd_ags_x64-mk11.dll"

g="$W/nioh"; mkdir -p "$g"; touch "$g/nioh.exe"
fake "$FIX/GfeSDK.dll" "$g/GfeSDK.dll" p5s-video-bridge.log
cycle nioh install-nioh-bridge.sh "$g" "$g/GfeSDK.dll" "$FIX/GfeSDK.dll" "$g/mgvf-asf-reader.dll" "$FIX/mgvf-asf-reader.dll"

g="$W/nioh3"; mkdir -p "$g"; touch "$g/Nioh3.exe"
fake "$FIX/amd_ags_x64-nioh3.dll" "$g/amd_ags_x64.dll" dwo-video-bridge.log
cycle nioh3 install-nioh3-bridge.sh "$g" "$g/amd_ags_x64.dll" "$FIX/amd_ags_x64-nioh3.dll" "$g/mgvf-asf-reader.dll" "$FIX/mgvf-asf-reader.dll"

g="$W/dmc5"; mkdir -p "$g"; touch "$g/DevilMayCry5.exe"
fake "$FIX/amd_ags_x64-dmc5.dll" "$g/amd_ags_x64.dll" mgvf-mf-fallback.log
cycle dmc5 install-re-vc1-fix.sh "$g" "$g/amd_ags_x64.dll" "$FIX/amd_ags_x64-dmc5.dll" "$g/mgvf-asf-reader.dll" "$FIX/mgvf-asf-reader.dll"

# Installed from a bottle's own dinput8, so only what --status says is tried:
# an older bridge, and for NieR a missing reader.
g="$W/kh"; mkdir -p "$g"; touch "$g/KINGDOM HEARTS HD 1.5+2.5 Launcher.exe"
cp "$FIX/dinput8-kh.dll" "$g/dinput8.dll"; older "$g/dinput8.dll"; touch "$g/dinput8_real.dll"
[ "$(st install-kh-bridge.sh "$g")" = outdated ] && say ok "kh: an older bridge is outdated" || say FAIL "kh: older bridge ($(st install-kh-bridge.sh "$g"))"
g="$W/nier"; mkdir -p "$g"; touch "$g/NieR Replicant ver.1.22474487139.exe"
cp "$FIX/dinput8-nier.dll" "$g/dinput8.dll"; older "$g/dinput8.dll"; touch "$g/dinput8_real.dll"
cp "$FIX/mgvf-asf-reader.dll" "$g/mgvf-asf-reader.dll"
[ "$(st install-nier-bridge.sh "$g")" = outdated ] && say ok "nier: an older bridge is outdated" || say FAIL "nier: older bridge ($(st install-nier-bridge.sh "$g"))"
cp "$FIX/mgvf-asf-reader.dll" "$g/mgvf-asf-reader.dll"; cp "$FIX/dinput8-nier.dll" "$g/dinput8.dll"; older "$g/mgvf-asf-reader.dll"
[ "$(st install-nier-bridge.sh "$g")" = outdated ] && say ok "nier: an older reader is outdated" || say FAIL "nier: older reader ($(st install-nier-bridge.sh "$g"))"
rm "$g/mgvf-asf-reader.dll"
[ "$(st install-nier-bridge.sh "$g")" = broken ] && say ok "nier: a missing reader is broken" || say FAIL "nier: missing reader ($(st install-nier-bridge.sh "$g"))"
pfx="$W/pfx"; mkdir -p "$pfx/drive_c/windows/system32"; touch "$pfx/user.reg" "$pfx/system.reg"
cp "$FIX/mgvf-asf-reader.dll" "$g/mgvf-asf-reader.dll"; older "$g/dinput8.dll"
[ "$(MGVF_BOTTLE="$pfx" st install-nier-bridge.sh "$g")" = outdated ] && say ok "nier in a Steam Play prefix: an older bridge is outdated" \
  || say FAIL "nier prefix: older bridge ($(MGVF_BOTTLE="$pfx" st install-nier-bridge.sh "$g"))"
cp "$FIX/dinput8-nier.dll" "$g/dinput8.dll"
[ "$(MGVF_BOTTLE="$pfx" st install-nier-bridge.sh "$g")" = installed ] && say ok "nier in a Steam Play prefix: the current bridge is installed" \
  || say FAIL "nier prefix: current bridge ($(MGVF_BOTTLE="$pfx" st install-nier-bridge.sh "$g"))"

# NINJA GAIDEN 3 goes into the prefix, not the game folder. A Steam Play prefix
# is edited as a file while nothing runs in it, so its whole life is tried here:
# the prefix's own d3d9 kept aside and put back, the four overrides written and
# taken out, a Wine build put back over one of ours read as broken and kept as
# the prefix's own when the fix is repaired, and none of ours kept as an original
# by installing twice.
g="$W/ng3"; mkdir -p "$g"; touch "$g/NINJA GAIDEN 3 Razor's Edge.exe"
pfx="$W/ng3pfx"; sys="$pfx/drive_c/windows/system32"; mkdir -p "$sys"
printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n' > "$pfx/user.reg"
touch "$pfx/system.reg"
echo "the prefix's own d3d9" > "$sys/d3d9.dll"
ng3st() { MGVF_BOTTLE="$pfx" st install-ng3-fix.sh "$g"; }
ng3() { MGVF_BOTTLE="$pfx" /bin/bash "$FIX/install-ng3-fix.sh" "$g" "$@"; }
keyed() { /usr/bin/grep -c "native,builtin" "$pfx/user.reg"; }
[ "$(ng3st)" = absent ] && say ok "ng3 in a Steam Play prefix: absent before" || say FAIL "ng3 prefix: absent before ($(ng3st))"
ng3 > "$W/ng3.install1.log" 2>&1 || say FAIL "ng3 prefix: install failed: $(tail -2 "$W/ng3.install1.log")"
[ "$(ng3st)" = installed ] && cmp -s "$sys/d3d9.dll" "$FIX/ng3-d3d9.dll" && [ "$(cat "$sys/d3d9.dll.mgvf-stock")" = "the prefix's own d3d9" ] \
  && say ok "ng3 in a Steam Play prefix: installed, the prefix's own d3d9 kept aside" || say FAIL "ng3 prefix: installed ($(ng3st))"
[ "$(keyed)" = 4 ] && /usr/bin/grep -qF "[Software\\\\Wine\\\\AppDefaults\\\\NINJA GAIDEN 3 Razor's Edge.exe\\\\DllOverrides]" "$pfx/user.reg" \
  && say ok "ng3 in a Steam Play prefix: four overrides, for its executable only" || say FAIL "ng3 prefix: overrides ($(keyed))"
echo "Wine's own qasf" > "$sys/qasf.dll"
[ "$(ng3st)" = broken ] && say ok "ng3 in a Steam Play prefix: a Wine build put back over one of ours is broken" || say FAIL "ng3 prefix: replaced qasf ($(ng3st))"
ng3 > "$W/ng3.install2.log" 2>&1 || say FAIL "ng3 prefix: repair failed: $(tail -2 "$W/ng3.install2.log")"
[ "$(ng3st)" = installed ] && [ "$(keyed)" = 4 ] && say ok "ng3 in a Steam Play prefix: installing again repairs it" || say FAIL "ng3 prefix: repair ($(ng3st), $(keyed))"
last="$(ng3 --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(ng3st)" = absent ] && [ "$(cat "$sys/d3d9.dll")" = "the prefix's own d3d9" ] \
  && [ "$(cat "$sys/qasf.dll")" = "Wine's own qasf" ] && [ ! -e "$sys/quartz.dll" ] && [ -z "$(ls "$sys" | /usr/bin/grep mgvf-stock)" ] \
  && ! /usr/bin/grep -q "NINJA GAIDEN" "$pfx/user.reg" \
  && say ok "ng3 in a Steam Play prefix: restored, the overrides gone" || say FAIL "ng3 prefix: restore ($last, $(ng3st))"

if [ "$fails" = 0 ]; then echo "==> every installer: installed, outdated, updated, restored"; else echo "==> $fails failed"; exit 1; fi
