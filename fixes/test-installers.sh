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
# prefix, and its whole life is tried in a fake Steam Play one. Cyberpunk 2077's
# changes a macOS game's app, and its whole life is tried on a fake app built
# here with cc and signed ad hoc.
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
st() { /bin/bash "$FIX/$1" "$2" --status 2>/dev/null | /usr/bin/grep -E '^(installed|outdated|absent|half|broken|norecipe|blocked)$' | head -1; }
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

g="$W/gowr"; mkdir -p "$g"; touch "$g/GoWR.exe"
fake "$FIX/bink2w64-gowr.dll" "$g/bink2w64.dll" gowr-triggers.log
cycle gowr install-gowr-triggers.sh "$g" "$g/bink2w64.dll" "$FIX/bink2w64-gowr.dll"

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

# Red Dead Online's fix switches on NotProton's Red Dead Online fix row (NOTPROTON_TCP_NOOPT=1 in
# the game's launch options), on 41303's runner on Rosetta, where MacGameFix keeps that row, and
# gives the Rockstar Games Launcher's window 0033's win32u.so as a runner variant the options ask for.
rh="$W/rdohome"; rc="$W/rdo/compatdata/1174180"; rp="$rc/pfx"; rg="$W/rdo/game"; rfix="$W/rdo/fixes"
rnp="$rh/Library/Application Support/notproton"; rvdf="$rh/Library/Application Support/Steam/userdata/1/config/localconfig.vdf"
mkdir -p "$rp/drive_c" "$rg" "$rnp/plugins" "$rfix" "$(dirname "$rvdf")"; : > "$rp/system.reg"; : > "$rp/user.reg"; : > "$rg/RDR2.exe"
for n in install-rdo-tcp.sh bottles.sh steam-launch-options.pl; do cp "$FIX/$n" "$rfix/$n"; done
rw32="$rfix/engine-27.0.0.41303-x86_64-unix-win32u.so"; echo "ours win32u.so" > "$rw32"   # as the modules catalog names it
rwin="$rh/Library/Application Support/MacGameFix/rdr2/launcher-window"; rvar="$rnp/variants/mgf-rdr2-launcher.conf"
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$rfix/steam-launch-options.pl"
printf '27.0.0.41303-fex\nCrossOver Preview 27.0.0.41303 - Rosetta\n' > "$rc/notproton-build"
printf '"UserLocalConfigStore"\n{\n\t"Software" { "Valve" { "Steam" { "apps" {\n\t\t"1174180"\n\t\t{\n\t\t\t"LaunchOptions"\t\t"NOTPROTON_ENV_WINE_TCP_NOOPT=1 %%command%%"\n\t\t}\n\t} } } }\n}\n' > "$rvdf"
rvdf0="$(cat "$rvdf")"
rdo() { HOME="$rh" MGVF_BOTTLE="$rp" /bin/bash "$rfix/install-rdo-tcp.sh" "$rg" "$@"; }
rdost() { rdo --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half|norecipe)$' | tail -1; }
[ "$(rdost)" = absent ] && say ok "rdo: absent before" || say FAIL "rdo: absent before ($(rdost))"
! rdo > "$W/rdo1.log" 2>&1 && [ "$(cat "$rvdf")" = "$rvdf0" ] && /usr/bin/grep -q 'Red Dead Online fix row is not' "$W/rdo1.log" \
  && say ok "rdo: refused while NotProton has no Red Dead Online row, nothing written" || say FAIL "rdo: refused without the row"
: > "$rnp/plugin-host.dylib"; : > "$rnp/plugins/tcp-noopt.dylib"
printf '[NOTPROTON_TCP_NOOPT]\nlabel = Red Dead Online fix\ninject = 1\nrequires = Library/Application Support/notproton/plugins/tcp-noopt.dylib\n' > "$rnp/plugins/60-red-dead-online.conf"
: > "$rc/notproton-tcp-noopt"
[ "$(rdost)" = half ] && say ok "rdo: the switch file of the 0037 version alone is half" || say FAIL "rdo: old switch ($(rdost))"
MGVF_STATUS_ONLY=1 rdo > /dev/null 2>&1; [ "$(cat "$rvdf")" = "$rvdf0" ] \
  && say ok "rdo: MGVF_STATUS_ONLY never installs" || say FAIL "rdo: MGVF_STATUS_ONLY wrote the launch options"
rdo > "$W/rdo2.log" 2>&1 && [ "$(rdost)" = installed ] && [ ! -e "$rc/notproton-tcp-noopt" ] \
  && /usr/bin/grep -q 'NOTPROTON_TCP_NOOPT=1 ' "$rvdf" && /usr/bin/grep -q 'NOTPROTON_RUNNER_VARIANT=mgf-rdr2-launcher-window ' "$rvdf" \
  && /usr/bin/grep -q 'NOTPROTON_ENV_WINE_TCP_NOOPT=1 %command%' "$rvdf" \
  && cmp -s "$rwin/x86_64-unix/win32u.so" "$rw32" && /usr/bin/grep -qx '\[mgf-rdr2-launcher-window\]' "$rvar" \
  && /usr/bin/grep -qx "src = $rwin" "$rvar" && /usr/bin/grep -qx 'build = 27.0.0.41303-fex' "$rvar" && /usr/bin/grep -qx 'apps = 1174180' "$rvar" \
  && [ -z "$(ls -A "$rg" | /usr/bin/grep -v '^RDR2.exe$')" ] \
  && say ok "rdo: installed, the row and the Launcher window's variant on in the launch options, the variant with 0033's win32u.so, the old switch gone, nothing in the game folder" || say FAIL "rdo: install ($(rdost), $(tail -1 "$W/rdo2.log"))"
rm -rf "$rwin"
[ "$(rdost)" = half ] && rdo > /dev/null 2>&1 && [ "$(rdost)" = installed ] && cmp -s "$rwin/x86_64-unix/win32u.so" "$rw32" \
  && say ok "rdo: the Launcher window's module gone is half, and installing again brings it" || say FAIL "rdo: window repair ($(rdost))"
rm "$rnp/plugins/tcp-noopt.dylib"
[ "$(rdost)" = half ] && say ok "rdo: half when the row's library is gone" || say FAIL "rdo: half ($(rdost))"
: > "$rnp/plugins/tcp-noopt.dylib"
rdo --restore > /dev/null 2>&1 && [ "$(rdost)" = absent ] && [ "$(cat "$rvdf")" = "$rvdf0" ] && [ ! -e "$rvar" ] && [ ! -e "$rwin" ] \
  && say ok "rdo: restore gives the launch options back as they were, and takes the variant out" || say FAIL "rdo: restore ($(rdost))"
mv "$rw32" "$rw32.away"
! rdo > "$W/rdo3.log" 2>&1 && /usr/bin/grep -q 'update MacGameFix' "$W/rdo3.log" && [ "$(cat "$rvdf")" = "$rvdf0" ] && [ ! -e "$rvar" ] \
  && say ok "rdo: a modules catalog without win32u.so is refused, nothing written" || say FAIL "rdo: no win32u ($(tail -1 "$W/rdo3.log"))"
mv "$rw32.away" "$rw32"
printf '27.0.0.41303-fex\nCrossOver Preview 27.0.0.41303 - FEX\n' > "$rc/notproton-build"
[ "$(rdost)" = norecipe ] && ! rdo > /dev/null 2>&1 && [ "$(cat "$rvdf")" = "$rvdf0" ] \
  && say ok "rdo: the FEX side is norecipe, and refused" || say FAIL "rdo: FEX ($(rdost))"
printf '27.0.0.41073-fex\nCrossOver Preview 27.0.0.41073 - Rosetta\n' > "$rc/notproton-build"
[ "$(rdost)" = norecipe ] && ! rdo > /dev/null 2>&1 \
  && say ok "rdo: another runner build is norecipe, and refused" || say FAIL "rdo: another build ($(rdost))"
: > "$rp/cxbottle.conf"
[ "$(rdost)" = norecipe ] && ! rdo > /dev/null 2>&1 \
  && say ok "rdo: a CrossOver bottle is norecipe, and refused" || say FAIL "rdo: a bottle ($(rdost))"

# Phantom Blade Zero's fix is registry values for PBZ.exe and the H.264 decoder
# in system32: tried in a fake Steam Play prefix, as NINJA GAIDEN 3's.
pfx="$W/pbzpfx"; psys="$pfx/drive_c/windows/system32"; mkdir -p "$psys"
echo "CrossOver's own msmpeg2vdec" > "$psys/msmpeg2vdec.dll"
printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n' > "$pfx/user.reg"
touch "$pfx/system.reg"
pbzst() { MGVF_BOTTLE="$pfx" st install-pbz-fix.sh "$W/pbz"; }
pbz() { MGVF_BOTTLE="$pfx" /bin/bash "$FIX/install-pbz-fix.sh" "$W/pbz" "$@"; }
mkdir -p "$W/pbz"
[ "$(pbzst)" = absent ] && say ok "pbz in a Steam Play prefix: absent before" || say FAIL "pbz prefix: absent before ($(pbzst))"
pbz > "$W/pbz.install.log" 2>&1 || say FAIL "pbz prefix: install failed: $(tail -2 "$W/pbz.install.log")"
[ "$(pbzst)" = installed ] && /usr/bin/grep -qF '"WINE_ROSETTA_CPUID7_OR"="01800000,00400000"' "$pfx/user.reg" \
  && [ "$(/usr/bin/grep -c '"=\"native,builtin\"' "$pfx/user.reg")" = 9 ] \
  && /usr/bin/grep -qF "[Software\\\\Wine\\\\AppDefaults\\\\PBZ.exe\\\\Environment]" "$pfx/user.reg" \
  && cmp -s "$psys/msmpeg2vdec.dll" "$FIX/msmpeg2vdec-sw.dll" \
  && [ "$(cat "$psys/msmpeg2vdec.dll.mgvf-stock")" = "CrossOver's own msmpeg2vdec" ] \
  && say ok "pbz in a Steam Play prefix: the CPUID value, nine overrides and the decoder, for PBZ.exe only" || say FAIL "pbz prefix: installed ($(pbzst))"
MGVF_BOTTLE="$pfx" /bin/bash -c '. "$0/bottles.sh"; user_reg_edit "$1" delete "Software\\Wine\\AppDefaults\\PBZ.exe\\DllOverrides" "*msvcp140"' "$FIX" "$pfx"
[ "$(pbzst)" = half ] && say ok "pbz in a Steam Play prefix: a value taken out is half" || say FAIL "pbz prefix: half ($(pbzst))"
pbz > "$W/pbz.install2.log" 2>&1 && [ "$(pbzst)" = installed ] && say ok "pbz in a Steam Play prefix: installing again repairs it" || say FAIL "pbz prefix: repair ($(pbzst))"
cp "$psys/msmpeg2vdec.dll.mgvf-stock" "$psys/msmpeg2vdec.dll"
[ "$(pbzst)" = half ] && say ok "pbz in a Steam Play prefix: the decoder put back by a prefix update is half" || say FAIL "pbz prefix: decoder half ($(pbzst))"
pbz > "$W/pbz.install3.log" 2>&1 && [ "$(pbzst)" = installed ] \
  && [ "$(cat "$psys/msmpeg2vdec.dll.mgvf-stock")" = "CrossOver's own msmpeg2vdec" ] \
  && say ok "pbz in a Steam Play prefix: installing over it keeps CrossOver's file once" || say FAIL "pbz prefix: reinstall over stock ($(pbzst))"
last="$(pbz --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(pbzst)" = absent ] && ! /usr/bin/grep -q '"WINE_ROSETTA_CPUID7_OR"\|native,builtin' "$pfx/user.reg" \
  && [ "$(cat "$psys/msmpeg2vdec.dll")" = "CrossOver's own msmpeg2vdec" ] && [ ! -e "$psys/msmpeg2vdec.dll.mgvf-stock" ] \
  && say ok "pbz in a Steam Play prefix: restored, every value gone and CrossOver's decoder back" || say FAIL "pbz prefix: restore ($last, $(pbzst))"

# In a NotProton prefix the fix also turns the pipeline cache on: the plugin and its
# descriptor in NotProton's plugins folder and the switch in PBZ's Steam launch options.
# A disposable HOME, and a copy of the launch-options editor that does not look for Steam.
npc="$W/pbznp"; nhome="$npc/home"; npfx="$npc/compatdata/4115450/pfx"
mkdir -p "$npfx/drive_c/windows/system32" "$nhome/Library/Application Support/notproton" "$npc/fixes"
printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "$npfx/user.reg"; touch "$npfx/system.reg"
echo 27.0.0.41303-fex > "$npc/compatdata/4115450/notproton-build"
for n in install-pbz-fix.sh bottles.sh msmpeg2vdec-sw.dll notproton-rosetta-pipeline-cache.dylib steam-launch-options.pl notproton-plugins.sh np-plugin-pbz.conf np-plugin-shared.conf mgf-engine.dylib; do cp "$FIX/$n" "$npc/fixes/$n"; done
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$npc/fixes/steam-launch-options.pl"
nvdf="$nhome/Library/Application Support/Steam/userdata/1/config/localconfig.vdf"; mkdir -p "$(dirname "$nvdf")"
printf '"UserLocalConfigStore"\n{\n\t"Software" { "Valve" { "Steam" { "apps" {\n\t\t"4115450"\n\t\t{\n\t\t\t"LaunchOptions"\t\t"D3DM_SUPPORT_DXR=0 %%command%%"\n\t\t}\n\t} } } }\n}\n' > "$nvdf"
nvdf0="$(cat "$nvdf")"
nplug="$nhome/Library/Application Support/notproton/plugins"
npst() { HOME="$nhome" MGVF_BOTTLE="$npfx" /bin/bash "$npc/fixes/install-pbz-fix.sh" "$npc/game" --status 2>/dev/null | tail -1; }
npbz() { HOME="$nhome" MGVF_BOTTLE="$npfx" /bin/bash "$npc/fixes/install-pbz-fix.sh" "$npc/game" "$@"; }
mkdir -p "$npc/game"
[ "$(npst)" = absent ] && say ok "pbz in NotProton: absent before" || say FAIL "pbz NotProton: absent before ($(npst))"
npbz > "$W/pbznp.install.log" 2>&1 || say FAIL "pbz NotProton: install failed: $(tail -2 "$W/pbznp.install.log")"
[ "$(npst)" = installed ] && cmp -s "$nplug/notproton-rosetta-pipeline-cache.dylib" "$FIX/notproton-rosetta-pipeline-cache.dylib" \
  && /usr/bin/grep -qx '\[NOTPROTON_ROSETTA_PIPELINE_CACHE\]' "$nplug/rosetta-pipeline-cache.conf" \
  && /usr/bin/grep -qF '"NOTPROTON_ROSETTA_PIPELINE_CACHE=1 D3DM_SUPPORT_DXR=0 %command%"' "$nvdf" \
  && say ok "pbz in NotProton: the plugin, its descriptor and the switch in front of the user's options" || say FAIL "pbz NotProton: installed ($(npst))"
sed -i '' 's/NOTPROTON_ROSETTA_PIPELINE_CACHE=1 //' "$nvdf"
[ "$(npst)" = half ] && say ok "pbz in NotProton: the switch taken out of the launch options is half" || say FAIL "pbz NotProton: half ($(npst))"
npbz > /dev/null 2>&1 && [ "$(npst)" = installed ] && say ok "pbz in NotProton: installing again puts the switch back" || say FAIL "pbz NotProton: repair ($(npst))"
# The user's own descriptor and an earlier unsigned build of the same code: the descriptor
# stays, the library becomes the signed one.
printf '[NOTPROTON_ROSETTA_PIPELINE_CACHE]\nlabel = mine\ninject = 1\nrequires = /abs/notproton-rosetta-pipeline-cache.dylib\n' > "$nplug/rosetta-pipeline-cache.conf"
printf 'not the plugin\n' > "$nplug/notproton-rosetta-pipeline-cache.dylib"
npbz > /dev/null 2>&1; [ "$(cat "$nplug/notproton-rosetta-pipeline-cache.dylib")" = "not the plugin" ] \
  && say ok "pbz in NotProton: a library that is not ours is not overwritten" || say FAIL "pbz NotProton: foreign library overwritten"
mine_sum="$(shasum -a 256 "$nplug/notproton-rosetta-pipeline-cache.dylib" | cut -d' ' -f1)"
sed -i '' "s/^CACHE_EARLIER=\"/CACHE_EARLIER=\"$mine_sum /" "$npc/fixes/install-pbz-fix.sh"
npbz > /dev/null 2>&1 && cmp -s "$nplug/notproton-rosetta-pipeline-cache.dylib" "$FIX/notproton-rosetta-pipeline-cache.dylib" \
  && /usr/bin/grep -q '^label = mine$' "$nplug/rosetta-pipeline-cache.conf" && [ "$(npst)" = installed ] \
  && say ok "pbz in NotProton: an earlier build is replaced, the user's descriptor kept" || say FAIL "pbz NotProton: earlier build ($(npst))"
last="$(npbz --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(npst)" = absent ] && [ "$(cat "$nvdf")" = "$nvdf0" ] \
  && [ -f "$nplug/notproton-rosetta-pipeline-cache.dylib" ] && /usr/bin/grep -q '^label = mine$' "$nplug/rosetta-pipeline-cache.conf" \
  && say ok "pbz in NotProton: restored, the launch options as they were and the user's descriptor kept" || say FAIL "pbz NotProton: restore ($last, $(npst))"
rm -f "$nplug/rosetta-pipeline-cache.conf"; npbz > /dev/null 2>&1; npbz --restore > /dev/null 2>&1
[ ! -e "$nplug/rosetta-pipeline-cache.conf" ] && [ ! -e "$nplug/notproton-rosetta-pipeline-cache.dylib" ] && [ "$(cat "$nvdf")" = "$nvdf0" ] \
  && say ok "pbz in NotProton: what the fix wrote is gone again after a restore" || say FAIL "pbz NotProton: own files left ($(ls "$nplug"))"
# On 41303 on Rosetta, with NotProton's plugin host: PBZ also takes the shared "Engine fixes"
# row (0017, 0019 and 0020 from mgf-engine.dylib), its switch beside the pipeline cache's.
[ ! -e "$nplug/mgf-4115450.uses" ] && say ok "pbz in NotProton without the plugin host or Rosetta named: no Engine fixes row" \
  || say FAIL "pbz NotProton: a row without the host"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$npc/compatdata/4115450/notproton-build"
echo host > "$nhome/Library/Application Support/notproton/plugin-host.dylib"
npbzr() { MGVF_NOTPROTON_VERSION=1.2.7 MGVF_STEAM_RUNNING=0 npbz "$@"; }
npstr() { HOME="$nhome" MGVF_BOTTLE="$npfx" MGVF_NOTPROTON_VERSION=1.2.7 MGVF_STEAM_RUNNING=0 /bin/bash "$npc/fixes/install-pbz-fix.sh" "$npc/game" --status 2>/dev/null | tail -1; }
[ "$(npstr)" = absent ] && say ok "pbz in NotProton on 41303 Rosetta: absent before" || say FAIL "pbz rows: absent before ($(npstr))"
npbzr > "$W/pbzrows.install.log" 2>&1 && [ "$(npstr)" = installed ] \
  && cmp -s "$nplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && /usr/bin/grep -q '^# shared rows: NOTPROTON_MGF_ENGINE$' "$nplug/mgf-4115450.uses" \
  && /usr/bin/grep -qxF '[NOTPROTON_MGF_ENGINE]' "$nplug/mgf-shared.conf" && ! /usr/bin/grep -q '^apps' "$nplug/mgf-shared.conf" \
  && /usr/bin/grep -qF '"NOTPROTON_MGF_ENGINE=1 NOTPROTON_ROSETTA_PIPELINE_CACHE=1 D3DM_SUPPORT_DXR=0 %command%"' "$nvdf" \
  && say ok "pbz in NotProton on 41303 Rosetta: the shared Engine fixes row, its library and its switch beside the pipeline cache's" \
  || say FAIL "pbz rows: install ($(npstr), $(tail -3 "$W/pbzrows.install.log" | tr '\n' ' '))"
rm -f "$nplug/mgf-shared.conf"
[ "$(npstr)" = half ] && say ok "pbz in NotProton on 41303 Rosetta: the shared row missing is half" || say FAIL "pbz rows: missing row ($(npstr))"
npbzr > /dev/null 2>&1 && [ "$(npstr)" = installed ] && say ok "pbz in NotProton on 41303 Rosetta: installing again puts it back" || say FAIL "pbz rows: repair ($(npstr))"
# The games a row is for (needed_for, improves) are written only where every NotProton in Steam
# reads the fields, which each tool's run script says. For one that does not, the rows are what
# they were before the fields existed: it refuses a row with a field it does not know.
nshared0="$(printf '%s\n' '# MacGameFix writes this file for the games whose fixes use its rows, and removes it with the last of them; edits do not last.' \
  '[NOTPROTON_MGF_ENGINE]' 'label = Engine fixes (MacGameFix)' \
  'description = Each game gets only its own fixes. Leave it on; turn it on for a game with Denuvo' \
  'on = 1' 'inject = 1' 'requires = Library/Application Support/notproton/plugins/mgf-engine.dylib' 'tools = notproton-fex-rosetta*')"
ncache0="$(printf '%s\n' '[NOTPROTON_ROSETTA_PIPELINE_CACHE]' 'label = Rosetta pipeline cache' \
  "description = Keeps the GPU code of the pipelines D3DMetal compiles in a Rosetta game, beyond Metal's 1.1 GB cache" \
  'section = dev' 'on = 1' 'inject = 1' 'requires = Library/Application Support/notproton/plugins/notproton-rosetta-pipeline-cache.dylib')"
ncache="$nplug/rosetta-pipeline-cache.conf"; nshared="$nplug/mgf-shared.conf"
[ "$(cat "$nshared")" = "$nshared0" ] && [ "$(cat "$ncache")" = "$ncache0" ] \
  && say ok "pbz in NotProton: with no NotProton that reads needed_for and improves, the rows are written as before the fields" \
  || say FAIL "pbz rows: the rows without the fields ($(cat "$nshared" "$ncache" | tr '\n' '|'))"
ntool="$nhome/Library/Application Support/Steam/compatibilitytools.d"; mkdir -p "$ntool/notproton-a"
nrun() { printf '      split("label description section on off depends requires inject env tools type choice default apps patch%s", f, " ")\n' "$2" > "$ntool/$1/run"; }
nrun notproton-a " group improves needed_for"
[ "$(npstr)" = half ] && npbzr > /dev/null 2>&1 && [ "$(npstr)" = installed ] \
  && /usr/bin/grep -qx 'needed_for = 4115450 The game never opens a window.' "$nshared" && /usr/bin/grep -qx 'needed_for = 3059520 The game crashes about a minute after it starts.' "$nshared" \
  && [ "$(/usr/bin/grep -c '^needed_for = ' "$nshared")" = 5 ] && [ "$(/usr/bin/grep -c '^improves = ' "$nshared")" = 1 ] \
  && /usr/bin/grep -qx 'improves = 2483190 Online sessions connect, and an idle timer thread stops using the processor.' "$nshared" \
  && [ "$(/usr/bin/grep -vE '^(needed_for|improves) = ' "$nshared")" = "$nshared0" ] \
  && /usr/bin/grep -qx 'improves = 4115450 The game compiles far fewer shaders at each start.' "$ncache" && [ "$(/usr/bin/grep -v '^improves = ' "$ncache")" = "$ncache0" ] \
  && say ok "pbz in NotProton: a NotProton that reads the fields gets the games each row is for, Engine fixes for every game it has a fix for, and nothing else changes" \
  || say FAIL "pbz rows: the games a row is for ($(npstr), $(cat "$nshared" "$ncache" | tr '\n' '|'))"
! /usr/bin/awk '/^\[/ { delete seen } /^(needed_for|improves) = / { if ($3 in seen) bad = 1; seen[$3] = 1; if (length($0) - index($0, $3) - length($3) > 200) bad = 1 } /^type = / { typed = 1 } END { exit !(bad || typed) }' "$nshared" \
  && say ok "pbz in NotProton: no game is named twice in a row, no sentence is past NotProton's 200 characters, and no such row has a type" \
  || say FAIL "pbz rows: a row NotProton would refuse ($(cat "$nshared" | tr '\n' '|'))"
mkdir -p "$ntool/notproton-b"; nrun notproton-b " group"
[ "$(npstr)" = half ] && npbzr > /dev/null 2>&1 && [ "$(npstr)" = installed ] && [ "$(cat "$nshared")" = "$nshared0" ] && [ "$(cat "$ncache")" = "$ncache0" ] \
  && say ok "pbz in NotProton: one NotProton in Steam that does not read the fields, and the rows are as before them again" \
  || say FAIL "pbz rows: one NotProton without the fields ($(npstr), $(cat "$nshared" "$ncache" | tr '\n' '|'))"
nrun notproton-b " group improves"
npbzr > /dev/null 2>&1 && [ "$(npstr)" = installed ] && ! /usr/bin/grep -q '^needed_for' "$nshared" && [ "$(/usr/bin/grep -c '^improves = ' "$nshared")" = 1 ] \
  && /usr/bin/grep -q '^improves = 4115450 ' "$ncache" \
  && say ok "pbz in NotProton: a field only some NotProton reads is left out, the one they all read is written" \
  || say FAIL "pbz rows: improves alone ($(npstr), $(cat "$nshared" | tr '\n' '|'))"
printf '[NOTPROTON_ROSETTA_PIPELINE_CACHE]\nlabel = mine\ninject = 1\nrequires = Library/Application Support/notproton/plugins/notproton-rosetta-pipeline-cache.dylib\n' > "$ncache"
npbzr > /dev/null 2>&1 && /usr/bin/grep -q '^label = mine$' "$ncache" && ! /usr/bin/grep -q '^improves' "$ncache" \
  && say ok "pbz in NotProton: a pipeline cache descriptor the user wrote is not given the line" || say FAIL "pbz rows: the user's descriptor ($(cat "$ncache" | tr '\n' '|'))"
# A shared row that is not on every game's page names only the games whose fix uses it.
nrun notproton-b " group improves needed_for"
( HOME="$nhome"; . "$npc/fixes/notproton-plugins.sh"
  printf '%s\n' '# every game = NOTPROTON_MGF_ALL' '[NOTPROTON_MGF_ALL]' 'label = All' 'improves = 111 One.' 'needed_for = 222 Two.' \
    '[NOTPROTON_MGF_SOME]' 'label = Some' 'needed_for = 111 One.' 'needed_for = 222 Two.' 'improves = 333 Three.' 'improves = 444 Four.' > "$npc/shared-test.conf"
  NP_SHARED_TEMPLATE="$npc/shared-test.conf"; NP_PLUGINS="$npc/no-plugins"
  got="$(printf '222 NOTPROTON_MGF_ALL\n222 NOTPROTON_MGF_SOME\n333 NOTPROTON_MGF_SOME\n' | MGVF_NOTPROTON_VERSION=1.2.8 np_shared_expected | /usr/bin/grep -v '^#' | tr '\n' '|')"
  [ "$got" = '[NOTPROTON_MGF_ALL]|label = All (MacGameFix)|improves = 111 One.|needed_for = 222 Two.|[NOTPROTON_MGF_SOME]|label = Some (MacGameFix)|needed_for = 222 Two.|improves = 333 Three.|apps = 222|apps = 333|' ] ) \
  && say ok "shared rows: a row for every game names every game the template gives it; a row with apps names only the games that use it" \
  || say FAIL "shared rows: the games of a row with apps"
rm -rf "$ntool" "$ncache" "$npc/shared-test.conf"
npbzr > /dev/null 2>&1; [ "$(npstr)" = installed ] && [ "$(cat "$nshared")" = "$nshared0" ] && [ "$(cat "$ncache")" = "$ncache0" ] \
  || say FAIL "pbz rows: back to a NotProton without the fields ($(npstr))"
last="$(npbzr --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(npstr)" = absent ] && [ "$(cat "$nvdf")" = "$nvdf0" ] \
  && [ ! -e "$nplug/mgf-4115450.uses" ] && [ ! -e "$nplug/mgf-shared.conf" ] && [ ! -e "$nplug/mgf-engine.dylib" ] \
  && say ok "pbz in NotProton on 41303 Rosetta: restored, the row, its library and both switches gone" \
  || say FAIL "pbz rows: restore ($last, $(npstr), $(cat "$nvdf" | tr '\n' ' '))"
rm -f "$nhome/Library/Application Support/notproton/plugin-host.dylib"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "4115450" { "LaunchOptions" "wrapper %%command%%" } } } } } }\n' > "$nvdf"
! npbz > /dev/null 2>&1 && [ ! -e "$nplug/notproton-rosetta-pipeline-cache.dylib" ] && ! /usr/bin/grep -q native "$npfx/user.reg" \
  && say ok "pbz in NotProton: options it cannot edit stop the install before anything changes" || say FAIL "pbz NotProton: wrapper not refused up front"

# F1 25 through Swofty Launcher, in a NotProton prefix: the launcher copied from the player's
# own download, the play script beside it, two registry values and a link in the prefix, the
# library that keeps the game's memory low, and the script before %command% in Steam's launch
# options. A disposable HOME with a stand-in for NotProton's plugin host, a stock runner (the
# library does 0038's job), and a release .zip made here (nothing is downloaded).
fc="$W/f125"; fhome="$fc/home"; fpfx="$fc/compatdata/3059520/pfx"; fstore="$fc/store"
mkdir -p "$fpfx/drive_c/Program Files (x86)/Steam" "$fc/fixes" "$fc/game" "$fc/runner/lib/wine/x86_64-unix" "$fc/rel/swofty-launcher-v9.9.9-windows-x86_64/bin" "$fc/rel/swofty-launcher-v9.9.9-windows-x86_64/loader"
touch "$fc/game/F1_25.exe" "$fpfx/system.reg"
freg0='WINE REGISTRY Version 2\n#arch=win64\n\n[Software\\\\Valve\\\\Steam\\\\ActiveProcess] 1795450608\n#time=1dd7b660a4f4a78\n"pid"=dword:00000020\n'
printf "$freg0" > "$fpfx/user.reg"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$fc/compatdata/3059520/notproton-build"
echo stock > "$fc/runner/lib/wine/x86_64-unix/ntdll.so"
echo launcher > "$fc/rel/swofty-launcher-v9.9.9-windows-x86_64/bin/swofty.exe"; echo core > "$fc/rel/swofty-launcher-v9.9.9-windows-x86_64/loader/version.dll"
(cd "$fc/rel" && ditto -c -k --keepParent swofty-launcher-v9.9.9-windows-x86_64 "$fc/sw.zip")
for n in install-f125-swofty.sh bottles.sh f125-swofty-play.sh f125-swofty-run.cmd steam-launch-options.pl notproton-plugins.sh np-plugin-f125-swofty.conf mgf-engine.dylib np-plugin-shared.conf; do cp "$FIX/$n" "$fc/fixes/$n"; done
# Swofty Launcher's window modules, as the Wine modules catalog names them (MGVF_MODULES unset: beside the installer).
for n in dwrite.dll directmanipulation.dll; do echo "ours $n" > "$fc/fixes/engine-27.0.0.41303-x86_64-windows-$n"; done
fnp="$fhome/Library/Application Support/notproton"; mkdir -p "$fnp"; fplug="$fnp/plugins"; echo host > "$fnp/plugin-host.dylib"
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$fc/fixes/steam-launch-options.pl"
fsteam="$fhome/Library/Application Support/Steam"; fvdf="$fsteam/userdata/1/config/localconfig.vdf"; mkdir -p "$(dirname "$fvdf")" "$fsteam/config"
fvdf_with() { printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "3059520" { "LaunchOptions" "%s" } } } } } }\n' "$1" > "$fvdf"; }
fvdf_with 'MGF_FANS=max %command%'; fvdf0="$(cat "$fvdf")"
mkdir -p "$fsteam/depotcache" "$fsteam/logs"; echo list > "$fsteam/depotcache/3059521_44.manifest"; echo log > "$fsteam/logs/content_log.txt"
printf '"AppState"\n{\n\t"appid"\t\t"3059520"\n\t"InstalledDepots"\n\t{\n\t\t"3059521"\n\t\t{\n\t\t\t"manifest"\t\t"44"\n\t\t\t"size"\t\t"1"\n\t\t}\n\t\t"3059522"\n\t\t{\n\t\t\t"manifest"\t\t"55"\n\t\t}\n\t}\n\t"UserConfig"\n\t{\n\t}\n}\n' > "$fc/appmanifest_3059520.acf"
fbridge="$fpfx/drive_c/Program Files (x86)/Steam"
printf '"users"\n{\n\t"76561198037788801"\n\t{\n\t\t"AccountName"\t\t"someone"\n\t\t"MostRecent"\t\t"1"\n\t}\n}\n' > "$fsteam/config/loginusers.vdf"
f1env() { env HOME="$fhome" MGVF_BOTTLE="$fpfx" MGVF_CX="$fc/runner" MGVF_SWOFTY_STORE="$fstore" MGVF_NOTPROTON_VERSION=1.2.7 MGVF_STEAM_RUNNING=0 "$@"; }
f1() { f1env MGVF_SWOFTY="$fc/sw.zip" /bin/bash "$fc/fixes/install-f125-swofty.sh" "$fc/game" "$@"; }
f1st() { f1 --status 2>/dev/null | tail -1; }
# Each switch once, before the play script, which stands right before %command%.
fswitched() {
  local o; o="$(/usr/bin/sed -n 's/.*"LaunchOptions" "\(.*\)".*/\1/p' "$fvdf")"
  for k in "$@"; do case " $o " in *" ${k}=1 "*) ;; *) return 1 ;; esac; done
  case "$o" in *"\\\"$fstore/f125-swofty-play.sh\\\" %command%") ;; *) return 1 ;; esac
  [ "$(printf '%s' "$o" | /usr/bin/grep -o 'f125-swofty-play.sh' | /usr/bin/grep -c .)" = 1 ]
}
flogin="$fpfx/drive_c/Program Files (x86)/Steam/config/loginusers.vdf"
fprof="$fpfx/drive_c/users/steamuser/AppData/Local/Swofty/profiles"; mkdir -p "$fprof"
for n in default race-setup 'bad name' vanilla; do echo '{}' > "$fprof/$n.json"; done
[ "$(f1st)" = absent ] && say ok "f1 25 in NotProton: absent before" || say FAIL "f1 25: absent before ($(f1st))"
f1 > "$W/f125.install.log" 2>&1 || say FAIL "f1 25: install failed: $(tail -2 "$W/f125.install.log")"
[ "$(f1st)" = installed ] && [ "$(cat "$fstore/launcher/bin/swofty.exe")" = launcher ] && [ -f "$fstore/launcher/loader/version.dll" ] \
  && cmp -s "$fstore/f125-swofty-play.sh" "$FIX/f125-swofty-play.sh" && [ -x "$fstore/f125-swofty-play.sh" ] && cmp -s "$fstore/f125-swofty-run.cmd" "$FIX/f125-swofty-run.cmd" \
  && /usr/bin/grep -qx '"version"="native,builtin"' "$fpfx/user.reg" && /usr/bin/grep -qx '"ActiveUser"=dword:049ee881' "$fpfx/user.reg" \
  && [ -L "$flogin" ] && /usr/bin/grep -q someone "$flogin" \
  && [ "$(cat "$fbridge/depotcache/3059521_44.manifest")" = list ] && [ ! -e "$fbridge/depotcache/3059522_55.manifest" ] && [ "$(cat "$fbridge/logs/content_log.txt")" = log ] \
  && fswitched NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_ENGINE && /usr/bin/grep -q 'MGF_FANS=max' "$fvdf" \
  && [ "$(/usr/bin/grep -c '^\[' "$fplug/mgf-3059520.uses")" = 0 ] && /usr/bin/grep -qx '# shared rows: NOTPROTON_MGF_ENGINE NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_PLAY NOTPROTON_MGF_PROFILE' "$fplug/mgf-3059520.uses" \
  && [ "$(/usr/bin/grep -c '^\[' "$fplug/mgf-shared.conf")" = 4 ] && /usr/bin/grep -qx '\[NOTPROTON_MGF_ENGINE\]' "$fplug/mgf-shared.conf" \
  && /usr/bin/grep -qx 'choice = default = default' "$fplug/mgf-shared.conf" && /usr/bin/grep -qx 'choice = race-setup = race-setup' "$fplug/mgf-shared.conf" \
  && ! /usr/bin/grep -q 'choice = bad' "$fplug/mgf-shared.conf" && [ "$(/usr/bin/grep -c '^choice = vanilla' "$fplug/mgf-shared.conf")" = 1 ] \
  && /usr/bin/grep -qx '\[NOTPROTON_MGF_MODTOOL\]' "$fplug/mgf-shared.conf" && /usr/bin/grep -qx '\[NOTPROTON_MGF_PLAY\]' "$fplug/mgf-shared.conf" \
  && [ "$(/usr/bin/grep -c '^apps = 3059520$' "$fplug/mgf-shared.conf")" = 3 ] && [ "$(/usr/bin/grep -c '^apps' "$fplug/mgf-shared.conf")" = 3 ] \
  && [ "$(/usr/bin/grep -c '^description = ' "$fplug/mgf-shared.conf")" = 4 ] && [ "$(/usr/bin/grep -c '^label = .* (MacGameFix)$' "$fplug/mgf-shared.conf")" = 4 ] \
  && /usr/bin/grep -qx 'requires = Library/Application Support/notproton/plugins/mgf-engine.dylib' "$fplug/mgf-shared.conf" && cmp -s "$fplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && ! /usr/bin/grep -q 'NOTPROTON_MGF_PLAY' "$fvdf" \
  && cmp -s "$fstore/window/x86_64-windows/dwrite.dll" "$fc/fixes/engine-27.0.0.41303-x86_64-windows-dwrite.dll" \
  && cmp -s "$fstore/window/x86_64-windows/directmanipulation.dll" "$fc/fixes/engine-27.0.0.41303-x86_64-windows-directmanipulation.dll" \
  && /usr/bin/grep -qx '\[mgf-f125-swofty-window\]' "$fnp/variants/mgf-f125-swofty.conf" && /usr/bin/grep -qx "src = $fstore/window" "$fnp/variants/mgf-f125-swofty.conf" \
  && /usr/bin/grep -qx 'build = 27.0.0.41303-fex' "$fnp/variants/mgf-f125-swofty.conf" && /usr/bin/grep -qx 'apps = 3059520' "$fnp/variants/mgf-f125-swofty.conf" \
  && say ok "f1 25 in NotProton: Swofty Launcher's window gets the two Wine modules as a runner variant for 41303; the player's launcher, the play script, the two values, the links, no row of its own but four shared rows for it, each saying where it was played, Swofty's profiles offered by name (not one it could not carry, nor vanilla twice), the engine library, both shared switches and the script in the launch options, on a runner without patch 0038" || say FAIL "f1 25: installed ($(f1st)): $(tail -3 "$W/f125.install.log")"
mv "$fnp/plugin-host.dylib" "$fnp/plugin-host.away"
fout="$(f1 --status 2>&1)"   # read whole: a reader that leaves early would end the status with a broken pipe
[ "$(f1st)" = half ] && case "$fout" in *'update NotProton'*) true ;; *) false ;; esac \
  && say ok "f1 25 in NotProton: without NotProton's plugin host it is half, and says to update NotProton" || say FAIL "f1 25: no plugin host ($(f1st))"
mv "$fnp/plugin-host.away" "$fnp/plugin-host.dylib"
echo '# older' >> "$fstore/f125-swofty-play.sh"
[ "$(f1st)" = outdated ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] \
  && say ok "f1 25 in NotProton: an older play script is outdated, and installing again brings this one" || say FAIL "f1 25: outdated ($(f1st))"
MGVF_BOTTLE="$fpfx" /bin/bash -c '. "$0/bottles.sh"; user_reg_edit "$1" delete "Software\\Wine\\AppDefaults\\F1_25.exe\\DllOverrides" version' "$FIX" "$fpfx"
[ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] \
  && say ok "f1 25 in NotProton: the override taken out is half, and installing again repairs it" || say FAIL "f1 25: half and repair ($(f1st))"
rm -f "$fbridge/depotcache/3059521_44.manifest"
[ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] && [ -L "$fbridge/depotcache/3059521_44.manifest" ] \
  && say ok "f1 25 in NotProton: a link to Steam's list taken out is half, and installing again repairs it" || say FAIL "f1 25: half and repair ($(f1st))"
rm -f "$fplug/mgf-engine.dylib"
[ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] && cmp -s "$fplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && say ok "f1 25 in NotProton: the library taken out is half, and installing again puts it back" || say FAIL "f1 25: library repair ($(f1st))"
echo "ours dwrite.dll, a newer build" > "$fc/fixes/engine-27.0.0.41303-x86_64-windows-dwrite.dll"
[ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] && cmp -s "$fstore/window/x86_64-windows/dwrite.dll" "$fc/fixes/engine-27.0.0.41303-x86_64-windows-dwrite.dll" \
  && mv "$fc/fixes/engine-27.0.0.41303-x86_64-windows-dwrite.dll" "$fc/dwrite.away" && ! f1 > "$W/f125.nowindow.log" 2>&1 && /usr/bin/grep -q 'update MacGameFix' "$W/f125.nowindow.log" \
  && say ok "f1 25 in NotProton: a newer window module in the catalog is half and installing again brings it; a catalog without one is refused" || say FAIL "f1 25: window modules ($(f1st)): $(tail -2 "$W/f125.nowindow.log" 2>/dev/null)"
[ -f "$fc/dwrite.away" ] && mv "$fc/dwrite.away" "$fc/fixes/engine-27.0.0.41303-x86_64-windows-dwrite.dll"
last="$(f1 --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(f1st)" = absent ] && [ "$(cat "$fvdf")" = "$fvdf0" ] && [ "$(cat "$fpfx/user.reg")" = "$(printf "$freg0")" ] \
  && [ ! -e "$fplug/mgf-3059520.uses" ] && [ ! -e "$fplug/mgf-shared.conf" ] && [ ! -e "$fplug/mgf-engine.dylib" ] && [ ! -e "$flogin" ] && [ ! -L "$flogin" ] && [ ! -L "$fbridge/depotcache/3059521_44.manifest" ] && [ ! -L "$fbridge/logs/content_log.txt" ] && [ ! -e "$fstore/f125-swofty-play.sh" ] && [ -f "$fstore/launcher/bin/swofty.exe" ] && [ ! -e "$fpfx/.mgf-f125-swofty" ] \
  && [ ! -e "$fnp/variants/mgf-f125-swofty.conf" ] && [ ! -e "$fstore/window" ] \
  && say ok "f1 25 in NotProton: restored, the launch options and the registry as they were, the library and the window's variant out, the launcher kept" || say FAIL "f1 25: restore ($last, $(f1st))"
# A profile made in Swofty's window since: the fix reads half, and installing again offers it.
f1 > /dev/null 2>&1; echo '{}' > "$fprof/wet.json"
[ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && [ "$(f1st)" = installed ] && /usr/bin/grep -qx 'choice = wet = wet' "$fplug/mgf-shared.conf" \
  && rm -f "$fprof/wet.json" && [ "$(f1st)" = half ] && f1 > /dev/null 2>&1 && ! /usr/bin/grep -q 'choice = wet' "$fplug/mgf-shared.conf" \
  && say ok "f1 25 in NotProton: a Swofty profile made or removed since reads half, and installing again offers what is there" || say FAIL "f1 25: profiles followed ($(f1st))"
f1 --restore > /dev/null 2>&1
# Two games on the shared rows: each row's apps are the games that use it (Engine fixes has none:
# it shows on every game), and removing one leaves the rows, their library and the other game's
# app. A stand-in descriptor plays FC 27's part.
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_PLAY\n' > "$fplug/mgf-4080220.uses"
f1 > /dev/null 2>&1
[ "$(f1st)" = installed ] && [ "$(/usr/bin/grep -c '^apps = ' "$fplug/mgf-shared.conf")" = 5 ] && [ "$(/usr/bin/grep -c '^apps = 4080220$' "$fplug/mgf-shared.conf")" = 2 ] \
  && f1 --restore > /dev/null 2>&1 && [ "$(f1st)" = absent ] && /usr/bin/grep -qx 'apps = 4080220' "$fplug/mgf-shared.conf" && ! /usr/bin/grep -q 'apps = 3059520' "$fplug/mgf-shared.conf" \
  && cmp -s "$fplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && say ok "f1 25 in NotProton: two games share the rows, and removing one leaves them and the library for the other" || say FAIL "f1 25: shared engine row ($(f1st))"
# A game whose fix uses no shared row writes the shared file again too, and names no template:
# Engine fixes still gets no apps from it (FH5's install took the row off every other game's page).
[ "$(printf '4080220 NOTPROTON_MGF_ENGINE\n4080220 NOTPROTON_MGF_MODTOOL\n' | HOME="$fhome" MGVF_NOTPROTON_VERSION=1.2.8 /bin/bash -c '. "$1"; NP_SHARED_TEMPLATE=""; np_shared_expected' _ "$FIX/notproton-plugins.sh" | /usr/bin/grep -c '^apps = ')" = 1 ] \
  && say ok "shared rows: written by a game that names no template, Engine fixes still shows on every game" || say FAIL "shared rows: Engine fixes got apps from a game that names no template"
rm -f "$fplug/mgf-4080220.uses" "$fplug/mgf-shared.conf" "$fplug/mgf-engine.dylib"
# The rows kept for every game (notproton-every-game.sh): Engine fixes for a Mac where no game's
# fix was installed, put in only with Steam and NotProton closed, by the writer the games use.
egh="$W/every/home"; egnp="$egh/Library/Application Support/notproton"; egp="$egnp/plugins"
egtool="$egh/Library/Application Support/Steam/compatibilitytools.d/notproton-a"; mkdir -p "$egtool"
printf '      split("label description section on off depends requires inject env tools type choice default apps patch group improves needed_for", f, " ")\n      if (names[i] == "group") next\n' > "$egtool/run"
eg() { HOME="$egh" MGVF_NOTPROTON_VERSION=1.2.8 MGVF_STEAM_RUNNING="${egsteam:-0}" MGVF_NOTPROTON_RUNNING="${egapp:-0}" /bin/bash "$FIX/notproton-every-game.sh" "$@"; }
egst() { eg --status 2>/dev/null | tail -1; }
[ "$(egst)" = unavailable ] && ! eg > /dev/null 2>&1 && [ ! -d "$egp" ] \
  && say ok "every game's rows: with no NotProton there is nothing to install into, and nothing is made" || say FAIL "every game's rows: no NotProton ($(egst))"
mkdir -p "$egnp"
[ "$(egst)" = unavailable ] && eg --status 2>&1 | /usr/bin/grep -q "plugin host is not installed" \
  && say ok "every game's rows: a NotProton with no plugin host could not load the library, so they are not offered" || say FAIL "every game's rows: no plugin host ($(egst))"
echo host > "$egnp/plugin-host.dylib"
[ "$(egst)" = absent ] && say ok "every game's rows: absent before an install" || say FAIL "every game's rows: before an install ($(egst))"
egout="$(egsteam=1 eg 2>&1)" && egrc=0 || egrc=$?
[ "$egrc" = 1 ] && printf '%s' "$egout" | /usr/bin/grep -q "Steam is open. Quit Steam" && [ ! -d "$egp" ] \
  && say ok "every game's rows: with Steam open the install is refused and nothing is written" || say FAIL "every game's rows: Steam open ($egrc, $egout)"
egout="$(egapp=1 eg 2>&1)" && egrc=0 || egrc=$?
[ "$egrc" = 1 ] && printf '%s' "$egout" | /usr/bin/grep -q "NotProton is open. Quit NotProton" && [ ! -d "$egp" ] \
  && say ok "every game's rows: and with NotProton's app open" || say FAIL "every game's rows: NotProton open ($egrc, $egout)"
eg > /dev/null 2>&1
[ "$(egst)" = installed ] && /usr/bin/grep -qx '\[NOTPROTON_MGF_ENGINE\]' "$egp/mgf-shared.conf" && [ "$(/usr/bin/grep -c '^\[' "$egp/mgf-shared.conf")" = 1 ] \
  && ! /usr/bin/grep -q '^apps' "$egp/mgf-shared.conf" && /usr/bin/grep -qx 'group = MacGameFix / Game fixes' "$egp/mgf-shared.conf" \
  && /usr/bin/grep -q '^needed_for = 3059520 ' "$egp/mgf-shared.conf" && cmp -s "$FIX/mgf-engine.dylib" "$egp/mgf-engine.dylib" \
  && /usr/bin/grep -qx '# shared rows: NOTPROTON_MGF_ENGINE' "$egp/mgf-every-game.uses" \
  && say ok "every game's rows: installed with both closed, Engine fixes is on every game's page with its library, and no other shared row" || say FAIL "every game's rows: install ($(egst), $(cat "$egp/mgf-shared.conf" 2>/dev/null | tr '\n' '|'))"
# A game's fix that uses the shared rows, after: its rows join, Engine fixes is still for every
# game, and removing the game's leaves Engine fixes and the library.
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE NOTPROTON_MGF_MODTOOL\n' > "$egp/mgf-4080220.uses"
egwrite() { ( HOME="$egh"; export MGVF_NOTPROTON_VERSION=1.2.8; . "$FIX/notproton-plugins.sh"; NP_SHARED_TEMPLATE="$FIX/np-plugin-shared.conf"; NP_SHARED_LIBRARY="$FIX/mgf-engine.dylib"; NP_SHARED_GROUP=MacGameFix; np_shared_write ); }
egwrite
[ "$(/usr/bin/grep -c '^\[' "$egp/mgf-shared.conf")" = 2 ] && [ "$(/usr/bin/grep -c '^apps = ' "$egp/mgf-shared.conf")" = 1 ] && /usr/bin/grep -qx 'apps = 4080220' "$egp/mgf-shared.conf" \
  && ! /usr/bin/grep -qx 'apps = 0' "$egp/mgf-shared.conf" && [ "$(egst)" = installed ] \
  && say ok "every game's rows: a game's fix adds its own rows to the same file, for its app alone, and Engine fixes stays for every game" || say FAIL "every game's rows: with a game ($(cat "$egp/mgf-shared.conf" | tr '\n' '|'))"
rm -f "$egp/mgf-4080220.uses"; egwrite
[ "$(/usr/bin/grep -c '^\[' "$egp/mgf-shared.conf")" = 1 ] && [ "$(egst)" = installed ] && [ -f "$egp/mgf-engine.dylib" ] \
  && say ok "every game's rows: the game's fix removed, Engine fixes and its library stay" || say FAIL "every game's rows: after the game left ($(egst))"
echo "description = edited by hand" >> "$egp/mgf-shared.conf"
[ "$(egst)" = half ] && egsteam=1 eg > /dev/null 2>&1 && [ "$(egst)" = installed ] \
  && say ok "every game's rows: once installed they are brought up to date with Steam open too" || say FAIL "every game's rows: upkeep ($(egst))"
printf 'not a build of ours' > "$egp/mgf-engine.dylib"
! eg > /dev/null 2>&1 && [ "$(cat "$egp/mgf-engine.dylib")" = "not a build of ours" ] \
  && say ok "every game's rows: a library there that MacGameFix never shipped is not replaced" || say FAIL "every game's rows: foreign library"
cp "$FIX/mgf-engine.dylib" "$egp/mgf-engine.dylib"
# NotProton's Plugins page deletes the file and the library it requires; the note stays.
rm -f "$egp/mgf-shared.conf" "$egp/mgf-engine.dylib"
[ "$(egst)" = absent ] && ! egsteam=1 eg > /dev/null 2>&1 && [ ! -e "$egp/mgf-shared.conf" ] && eg > /dev/null 2>&1 && [ "$(egst)" = installed ] \
  && say ok "every game's rows: deleted in NotProton they read absent, and come back only by an install with Steam closed" || say FAIL "every game's rows: deleted in NotProton ($(egst))"
# A Mac from before the note, where a game's fix put Engine fixes in: adopted, it reads installed
# with nothing rewritten, and it stays when that game's fix goes.
rm -f "$egp/mgf-every-game.uses"
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE\n' > "$egp/mgf-4080220.uses"
egwrite; egbefore="$(cat "$egp/mgf-shared.conf")"
[ "$(egst)" = absent ] && egsteam=1 eg --adopt > /dev/null 2>&1 && [ "$(egst)" = installed ] && [ "$(cat "$egp/mgf-shared.conf")" = "$egbefore" ] \
  && rm -f "$egp/mgf-4080220.uses" && egwrite && [ "$(egst)" = installed ] && ! eg --adopt > /dev/null 2>&1 \
  && say ok "every game's rows: where a game's fix already put them in they are adopted as installed, with Steam open and nothing rewritten" || say FAIL "every game's rows: adopt ($(egst))"
rm -f "$egp/mgf-every-game.uses" "$egp/mgf-shared.conf"
! eg --adopt > /dev/null 2>&1 && [ ! -e "$egp/mgf-every-game.uses" ] && eg > /dev/null 2>&1 \
  && say ok "every game's rows: with no row there, there is nothing to adopt" || say FAIL "every game's rows: adopt with nothing"
# Removed while a game's fix uses the row: the note goes, the row and the library stay, and it says so.
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE\n' > "$egp/mgf-4080220.uses"
egout="$(eg --restore 2>&1)"
printf '%s' "$egout" | /usr/bin/grep -q "the row stays, the fix of 1 game(s) uses it" && [ "$(egst)" = absent ] && /usr/bin/grep -qx '\[NOTPROTON_MGF_ENGINE\]' "$egp/mgf-shared.conf" && [ -f "$egp/mgf-engine.dylib" ] \
  && say ok "every game's rows: removed while a game's fix uses the row, it stays for that game and the removal says so" || say FAIL "every game's rows: restore with a game ($egout)"
rm -f "$egp/mgf-4080220.uses"; eg > /dev/null 2>&1
! egsteam=1 eg --restore > /dev/null 2>&1 && [ "$(egst)" = installed ] && eg --restore > /dev/null 2>&1 && [ "$(egst)" = absent ] \
  && [ ! -e "$egp/mgf-shared.conf" ] && [ ! -e "$egp/mgf-engine.dylib" ] && [ ! -e "$egp/mgf-every-game.uses" ] \
  && say ok "every game's rows: removed with both closed, the file, the library and the note are gone" || say FAIL "every game's rows: restore ($(egst), $(ls "$egp" | tr '\n' ' '))"
# An earlier install's mgf-low-allocations.dylib, the build PR #154 shipped, is taken out; a file of that name that is not that build stays.
if /usr/bin/git -C "$FIX" show 1a2cb2a:fixes/mgf-low-allocations.dylib > "$W/f125-old-lib" 2>/dev/null; then
  mkdir -p "$fplug"; cp "$W/f125-old-lib" "$fplug/mgf-low-allocations.dylib"
  f1 > "$W/f125.retire.log" 2>&1; [ ! -e "$fplug/mgf-low-allocations.dylib" ] && /usr/bin/grep -q 'no longer uses, taken out' "$W/f125.retire.log" \
    && echo other > "$fplug/mgf-low-allocations.dylib" && f1 > /dev/null 2>&1 && [ "$(cat "$fplug/mgf-low-allocations.dylib")" = other ] \
    && say ok "f1 25 in NotProton: the library an earlier install put in is taken out, and a file of that name that is not ours stays" || say FAIL "f1 25: retired library: $(tail -2 "$W/f125.retire.log")"
  rm -f "$fplug/mgf-low-allocations.dylib"; f1 --restore > /dev/null 2>&1
fi
# The player's switches are theirs: a row turned off stays off through another install, and the fix still reads installed.
f1 > /dev/null 2>&1; sed -i '' 's/NOTPROTON_MGF_MODTOOL=1 //' "$fvdf"
[ "$(f1st)" = installed ] && f1 > /dev/null 2>&1 && ! /usr/bin/grep -q 'NOTPROTON_MGF_MODTOOL' "$fvdf" && fswitched NOTPROTON_MGF_ENGINE \
  && say ok "f1 25 in NotProton: a row the player switched off is not a broken fix, and installing again leaves it off" || say FAIL "f1 25: the player's switch ($(f1st))"
# An install from before the memory row: its switch was never put in. The install that brings the row switches it on, once, and leaves the player's other switch as it is.
fsw="$fc/compatdata/3059520/.mgf-notproton-plugins-switched"
/usr/bin/sed -i '' '/^NOTPROTON_MGF_ENGINE=/d' "$fsw"; sed -i '' 's/NOTPROTON_MGF_ENGINE=1 //' "$fvdf"
[ "$(f1st)" = half ] && f1 > "$W/f125.newrow.log" 2>&1 && [ "$(f1st)" = installed ] && fswitched NOTPROTON_MGF_ENGINE && ! /usr/bin/grep -q 'NOTPROTON_MGF_MODTOOL' "$fvdf" \
  && /usr/bin/grep -q 'a row new to this fix' "$W/f125.newrow.log" && /usr/bin/grep -qx 'NOTPROTON_MGF_ENGINE=1' "$fsw" \
  && sed -i '' 's/NOTPROTON_MGF_ENGINE=1 //' "$fvdf" && f1 > /dev/null 2>&1 && ! /usr/bin/grep -q 'NOTPROTON_MGF_ENGINE' "$fvdf" \
  && say ok "f1 25 in NotProton: a row the fix gained and never switched on reads half; the install switches it on, once, and the player's other switch stays off" || say FAIL "f1 25: new row ($(f1st)): $(tail -2 "$W/f125.newrow.log")"
f1 --restore > /dev/null 2>&1; [ "$(cat "$fvdf")" = "$fvdf0" ] && [ "$(f1st)" = absent ] || say FAIL "f1 25: restore after the new row ($(f1st))"
# An install from before the rows: the script already in the options, the rows never switched. The switches still go in.
f1 > /dev/null 2>&1
rm -f "$fsw" "$fc/compatdata/3059520/.mgf-notproton-plugins.json" "$fplug/mgf-3059520.uses"
sed -i '' -e 's/NOTPROTON_MGF_MODTOOL=1 //' -e 's/NOTPROTON_MGF_ENGINE=1 //' "$fvdf"
f1 > "$W/f125.rows.log" 2>&1 && [ "$(f1st)" = installed ] && fswitched NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_ENGINE \
  && say ok "f1 25 in NotProton: over an install from before the rows, the switches go in and the script stays once" || say FAIL "f1 25: rows over an earlier install ($(f1st)): $(tail -2 "$W/f125.rows.log")"
f1 --restore > /dev/null 2>&1; [ "$(f1st)" = absent ] || say FAIL "f1 25: restore after the rows ($(f1st))"
fvdf_with 'MGF_FANS=max %command%'
# Where NotProton knows groups, the rows carry one of the game's own; where it does not, none, as it would refuse the row.
MGVF_NOTPROTON_GROUPS=1 f1 > /dev/null 2>&1
[ "$(/usr/bin/grep -c '^group = MacGameFix / Mods$' "$fplug/mgf-shared.conf")" = 3 ] && [ "$(/usr/bin/grep -c '^group = MacGameFix / Game fixes$' "$fplug/mgf-shared.conf")" = 1 ] && ! /usr/bin/grep -q '^subgroup' "$fplug/mgf-shared.conf" && ! /usr/bin/grep -q '^label = .*MacGameFix' "$fplug/mgf-shared.conf" && ! /usr/bin/grep -q '^description = .*MacGameFix' "$fplug/mgf-shared.conf" && [ "$(MGVF_NOTPROTON_GROUPS=1 f1 --status 2>/dev/null | tail -1)" = installed ] \
  && say ok "f1 25 in NotProton: with a NotProton that knows groups, every shared row is in MacGameFix's group and names it nowhere else" || say FAIL "f1 25: grouped rows ($(MGVF_NOTPROTON_GROUPS=1 f1 --status 2>/dev/null | tail -1))"
f1 > /dev/null 2>&1; ! /usr/bin/grep -q '^group' "$fplug/mgf-shared.conf" && [ "$(/usr/bin/grep -c '^label = .* (MacGameFix)$' "$fplug/mgf-shared.conf")" = 4 ] && [ "$(f1st)" = installed ] \
  && say ok "f1 25 in NotProton: with one that does not, the rows carry no group and their labels name MacGameFix" || say FAIL "f1 25: ungrouped rows ($(f1st))"
f1 --restore > /dev/null 2>&1
# What the user had before stays theirs: an override, an ActiveUser and a loginusers.vdf of their own.
MGVF_BOTTLE="$fpfx" /bin/bash -c '. "$0/bottles.sh"; user_reg_edit "$1" set "Software\\Wine\\AppDefaults\\F1_25.exe\\DllOverrides" version native,builtin; user_reg_edit "$1" setdword "Software\\Valve\\Steam\\ActiveProcess" ActiveUser 7' "$FIX" "$fpfx"
mkdir -p "$(dirname "$flogin")"; echo mine > "$flogin"
f1 > /dev/null 2>&1; [ "$(f1st)" = installed ] || say FAIL "f1 25: install over the user's own values ($(f1st))"
f1 --restore > /dev/null 2>&1
/usr/bin/grep -qx '"version"="native,builtin"' "$fpfx/user.reg" && /usr/bin/grep -qx '"ActiveUser"=dword:00000007' "$fpfx/user.reg" && [ "$(cat "$flogin")" = mine ] && [ "$(cat "$fvdf")" = "$fvdf0" ] \
  && [ "$(f1st)" = absent ] \
  && say ok "f1 25 in NotProton: values and a loginusers.vdf that were there before stay after a restore, which reads absent" || say FAIL "f1 25: the user's own values ($(f1st))"
printf "$freg0" > "$fpfx/user.reg"; rm -rf "$flogin" "$fstore" "$fbridge/depotcache" "$fbridge/logs" "$fplug"
# Swofty Launcher is the player's: nothing given and none kept is refused with where to get it;
# something that is not its release is refused; the window asks, and Cancel changes nothing.
f1bare() { f1env "$@" /bin/bash "$fc/fixes/install-f125-swofty.sh" "$fc/game"; }
! f1bare > "$W/f125.none.log" 2>&1 && /usr/bin/grep -q 'f1.swofty.net' "$W/f125.none.log" && /usr/bin/grep -q 'MGVF_SWOFTY=' "$W/f125.none.log" \
  && [ ! -e "$fstore/launcher" ] && ! /usr/bin/grep -q native "$fpfx/user.reg" && [ ! -e "$fplug/mgf-3059520.uses" ] && [ "$(cat "$fvdf")" = "$fvdf0" ] \
  && say ok "f1 25 in NotProton: with no Swofty given and none kept nothing changes, and it says where to download it" || say FAIL "f1 25: no Swofty not refused: $(tail -3 "$W/f125.none.log")"
mkdir -p "$fc/notswofty"; echo x > "$fc/notswofty/readme.txt"
! f1bare MGVF_SWOFTY="$fc/notswofty" > "$W/f125.not.log" 2>&1 && /usr/bin/grep -q 'bin/swofty.exe and loader/' "$W/f125.not.log" \
  && [ ! -e "$fstore/launcher" ] && ! /usr/bin/grep -q native "$fpfx/user.reg" && [ "$(cat "$fvdf")" = "$fvdf0" ] \
  && say ok "f1 25 in NotProton: a folder that is not Swofty's release is refused before anything changes" || say FAIL "f1 25: not Swofty taken: $(tail -2 "$W/f125.not.log")"
printf '#!/bin/sh\nexit 0\n' > "$fc/cancel"; chmod +x "$fc/cancel"
! f1bare MGVF_FRONTEND=app MGVF_CHOOSER="$fc/cancel" > "$W/f125.cancel.log" 2>&1 && /usr/bin/grep -q 'choose the download when you are asked' "$W/f125.cancel.log" \
  && [ ! -e "$fstore/launcher" ] && ! /usr/bin/grep -q native "$fpfx/user.reg" && [ "$(cat "$fvdf")" = "$fvdf0" ] \
  && say ok "f1 25 in NotProton: Cancel in the window's chooser changes nothing" || say FAIL "f1 25: cancel: $(tail -2 "$W/f125.cancel.log")"
printf '#!/bin/sh\necho "%s/bin/swofty.exe"\n' "$fc/rel/swofty-launcher-v9.9.9-windows-x86_64" > "$fc/pick"; chmod +x "$fc/pick"
f1bare MGVF_FRONTEND=app MGVF_CHOOSER="$fc/pick" > "$W/f125.pick.log" 2>&1 && [ "$(cat "$fstore/launcher/bin/swofty.exe")" = launcher ] && [ -f "$fstore/launcher/loader/version.dll" ] && [ "$(f1st)" = installed ] \
  && say ok "f1 25 in NotProton: from the window, swofty.exe in an unpacked download is taken, with its folder" || say FAIL "f1 25: picked exe: $(tail -2 "$W/f125.pick.log")"
printf '#!/bin/sh\necho asked > "%s/asked"\n' "$fc" > "$fc/tattle"; chmod +x "$fc/tattle"
f1bare MGVF_FRONTEND=app MGVF_CHOOSER="$fc/tattle" > /dev/null 2>&1 && [ ! -e "$fc/asked" ] && [ "$(f1st)" = installed ] \
  && say ok "f1 25 in NotProton: with a launcher kept, installing again asks nothing" || say FAIL "f1 25: asked with a launcher kept"
f1 --restore > /dev/null 2>&1
printf "$freg0" > "$fpfx/user.reg"; rm -rf "$flogin" "$fstore" "$fbridge/depotcache" "$fbridge/logs" "$fplug"
# Refused before anything is written: no plugin host, options with another program, Steam not signed in.
mv "$fnp/plugin-host.dylib" "$fnp/plugin-host.away"
! f1 > "$W/f125.refuse.log" 2>&1 && /usr/bin/grep -q 'plugin host' "$W/f125.refuse.log" && [ ! -e "$fstore" ] && [ "$(cat "$fvdf")" = "$fvdf0" ] && ! /usr/bin/grep -q native "$fpfx/user.reg" \
  && say ok "f1 25 in NotProton: without NotProton's plugin host the install stops before anything changes" || say FAIL "f1 25: no plugin host not refused"
mv "$fnp/plugin-host.away" "$fnp/plugin-host.dylib"
fvdf_with 'gamemoderun %command%'
! f1 > /dev/null 2>&1 && [ ! -e "$fstore/launcher" ] && ! /usr/bin/grep -q native "$fpfx/user.reg" && [ ! -e "$flogin" ] && [ ! -e "$fplug/mgf-3059520.uses" ] \
  && say ok "f1 25 in NotProton: launch options with another program stop the install before anything changes" || say FAIL "f1 25: wrapper not refused up front"
fvdf_with 'MGF_FANS=max %command%'; mv "$fsteam/config/loginusers.vdf" "$fsteam/config/loginusers.vdf.away"
! f1 > "$W/f125.refuse.log" 2>&1 && /usr/bin/grep -q 'signed in' "$W/f125.refuse.log" && [ ! -e "$fstore/launcher" ] \
  && say ok "f1 25 in NotProton: no signed-in Steam account stops the install" || say FAIL "f1 25: no account not refused"
mv "$fsteam/config/loginusers.vdf.away" "$fsteam/config/loginusers.vdf"
# The FEX side and a CrossOver bottle have no recipe.
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - FEX\n' > "$fc/compatdata/3059520/notproton-build"
[ "$(f1st)" = norecipe ] && say ok "f1 25 in NotProton: the FEX side has no recipe" || say FAIL "f1 25: FEX ($(f1st))"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$fc/compatdata/3059520/notproton-build"
# The play script, with a tool that only says what it was given: the rows are variables in its
# environment, and the profile row's choice reaches Swofty as its --profile.
printf '#!/bin/sh\nprintf "%%s|" "$@"; printf "\\nprofile=%%s opens=%%s%%s%%s\\n" "${NOTPROTON_ENV_F125_PROFILE:-}" "${NOTPROTON_ENV_F125_OPENS:-}" "${WINEDEBUG:+ debug=$WINEDEBUG}" "${NOTPROTON_RUNNER_VARIANT:+ variant=$NOTPROTON_RUNNER_VARIANT}"\n' > "$fc/tool"; chmod +x "$fc/tool"
mkdir -p "$fc/play/launcher/bin" "$fc/playpfx/pfx/dosdevices"; cp "$FIX/f125-swofty-play.sh" "$FIX/f125-swofty-run.cmd" "$fc/play/"; touch "$fc/play/launcher/bin/swofty.exe"
fplay() { env -i HOME="$fhome" PATH=/usr/bin:/bin STEAM_COMPAT_APP_ID=3059520 STEAM_COMPAT_DATA_PATH="$fc/playpfx" "$@" "$fc/play/f125-swofty-play.sh" "$fc/tool" waitforexitandrun /lib/steamapps/common/F1/F1_25.exe; }
fout="$(fplay)"; case "$fout" in "waitforexitandrun|/lib/steamapps/common/F1/F1_25.exe|"*) true ;; *) false ;; esac \
  && say ok "f1 25's play script: with the row off, Steam's own command goes through" || say FAIL "f1 25 play: row off: $fout"
fout="$(fplay NOTPROTON_MGF_MODTOOL=1)"; case "$fout" in "waitforexitandrun|cmd.exe|/d|/c|call|"*"profile= opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PLAY=game)" && case "$fout" in *"profile= opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PROFILE=vanilla)" && case "$fout" in *"profile=vanilla opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PROFILE=race-setup)" && case "$fout" in *"profile=race-setup opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PROFILE=active)" && case "$fout" in *"profile= opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 'NOTPROTON_MGF_PROFILE=a b&c')" && case "$fout" in *"profile= opens=") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PLAY=window)" && case "$fout" in *"profile= opens=window") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PLAY=notes)" && case "$fout" in *"profile= opens= debug=err+all,fixme-all,+seh,+timestamp,+pid") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 'NOTPROTON_MGF_PLAY=a b&c')" && case "$fout" in *"profile= opens=") true ;; *) false ;; esac \
  && mkdir -p "$fnp/variants" && touch "$fnp/variants/mgf-f125-swofty.conf" \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1)" && case "$fout" in *"profile= opens= variant=mgf-f125-swofty-window") true ;; *) false ;; esac \
  && fout="$(fplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_RUNNER_VARIANT=other)" && case "$fout" in *" variant=other+mgf-f125-swofty-window") true ;; *) false ;; esac \
  && fout="$(fplay)" && case "$fout" in *variant=*) false ;; *) true ;; esac && rm -f "$fnp/variants/mgf-f125-swofty.conf" \
  && say ok "f1 25's play script: the batch file takes the command's place; with the window's variant written, NotProton is asked for it, after any other; Mod profile's vanilla or a profile's name reaches Swofty as its profile (active and a name it could not carry do not); Play opens' window opens its window and notes turns Wine's exception notes on" || say FAIL "f1 25 play: rows: $fout"
touch "$fpfx/cxbottle.conf"; [ "$(f1st)" = norecipe ] && say ok "f1 25: a CrossOver bottle has no recipe" || say FAIL "f1 25: bottle ($(f1st))"; rm -f "$fpfx/cxbottle.conf"

# EA SPORTS FC 27 with FC 27 Live Editor, in a NotProton prefix: the Live Editor folder the
# player names copied to the store (nothing is downloaded or looked for), the play script beside
# it, the script before %command% in Steam's launch options, and two rows and a library in
# NotProton's plugins. A disposable HOME with a stand-in for NotProton's plugin host, a stock
# runner (the activation fix's library does 0041's job), and Live Editor folders made here.
ec="$W/fc27"; ehome="$ec/home"; epfx="$ec/compatdata/4080220/pfx"; estore="$ec/store"; edl="$ec/unpacked"
mkdir -p "$epfx/drive_c" "$ec/fixes" "$ec/game" "$ec/runner/lib/wine/x86_64-windows" "$edl"
touch "$ec/game/FC27.exe" "$epfx/system.reg"; printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "$epfx/user.reg"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$ec/compatdata/4080220/notproton-build"
echo stock > "$ec/runner/lib/wine/x86_64-windows/kernel32.dll"
# A Live Editor folder: <where> <what its DLL holds> <its DLL's time, touch -t>.
editor() { mkdir -p "$1/FakeEAACLauncher" "$1/lua" "$1/Logs"; echo launcher > "$1/Launcher.exe"; echo "$2" > "$1/FCLiveEditor.DLL"; echo standin > "$1/FakeEAACLauncher/EAAntiCheat.GameServiceLauncher.exe"; echo used > "$1/Logs/a.log"; touch -t "$3" "$1/FCLiveEditor.DLL"; }
for n in install-fc27-live-editor.sh bottles.sh fc27-le-play.sh fc27-le-run.cmd fc27-squads.pl steam-launch-options.pl notproton-plugins.sh np-plugin-fc27-live-editor.conf mgf-engine.dylib np-plugin-shared.conf; do cp "$FIX/$n" "$ec/fixes/$n"; done
enp="$ehome/Library/Application Support/notproton"; mkdir -p "$enp"; eplug="$enp/plugins"; echo host > "$enp/plugin-host.dylib"
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$ec/fixes/steam-launch-options.pl"
evdf="$ehome/Library/Application Support/Steam/userdata/1/config/localconfig.vdf"; mkdir -p "$(dirname "$evdf")"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "4080220" { "LaunchOptions" "%s" } } } } } }\n' 'MGF_FANS=max %command%' > "$evdf"; evdf0="$(cat "$evdf")"
e1() { HOME="$ehome" MGVF_BOTTLE="$epfx" MGVF_CX="$ec/runner" MGVF_FC27_STORE="$estore" MGVF_NOTPROTON_VERSION=1.2.7 MGVF_STEAM_RUNNING=0 /bin/bash "$ec/fixes/install-fc27-live-editor.sh" "$ec/game" "$@"; }
e1st() { e1 --status 2>/dev/null | tail -1; }
# Each switch once, before the play script, which stands right before %command%.
eswitched() {
  local o; o="$(/usr/bin/sed -n 's/.*"LaunchOptions" "\(.*\)".*/\1/p' "$evdf")"
  for k in "$@"; do case " $o " in *" ${k}=1 "*) ;; *) return 1 ;; esac; done
  case "$o" in *"\\\"$estore/fc27-le-play.sh\\\" %command%") ;; *) return 1 ;; esac
  [ "$(printf '%s' "$o" | /usr/bin/grep -o 'fc27-le-play.sh' | /usr/bin/grep -c .)" = 1 ]
}
[ "$(e1st)" = absent ] && say ok "fc 27 in NotProton: absent before" || say FAIL "fc 27: absent before ($(e1st))"
eout="$(e1 2>&1)" && say FAIL "fc 27: installed with no Live Editor to take" || { case "$eout" in *'is not part of MacGameFix'*'MGVF_LIVE_EDITOR='*'Nothing was changed'*) true ;; *) false ;; esac \
  && [ "$(cat "$evdf")" = "$evdf0" ] && [ ! -e "$estore" ] && [ ! -e "$eplug" ] \
  && say ok "fc 27 in NotProton: with no Live Editor folder given it stops, says how to give one, and changes nothing" || say FAIL "fc 27: no editor: $eout"; }
# From MacGameFix's window the install asks; a chooser of the test's stands in for macOS's.
printf '#!/bin/sh\ncat "%s/answer" 2>/dev/null\n' "$ec" > "$ec/chooser"; chmod +x "$ec/chooser"
ewin() { MGVF_FRONTEND=app MGVF_CHOOSER="$ec/chooser" e1 "$@"; }
: > "$ec/answer"
eout="$(ewin 2>&1)" && say FAIL "fc 27: installed after the chooser was cancelled" || { case "$eout" in *'choose the unpacked folder when you are asked'*'Nothing was changed'*) true ;; *) false ;; esac \
  && [ "$(cat "$evdf")" = "$evdf0" ] && [ ! -e "$estore" ] \
  && say ok "fc 27 in NotProton: from the window, a chooser the player cancels with no Live Editor in use changes nothing" || say FAIL "fc 27: cancelled: $eout"; }
editor "$edl/FC 27 LE v1" one 202611010000
printf '%s/\n' "$edl" > "$ec/answer"   # the folder around it, as the chooser gives one: with a slash
# The library an earlier install put in, the build PR #147 shipped: this install takes it out.
mkdir -p "$eplug"; /usr/bin/git -C "$FIX" show 17b51da:fixes/mgf-d3dmetal-hookable.dylib > "$eplug/mgf-d3dmetal-hookable.dylib" 2>/dev/null || rm -f "$eplug/mgf-d3dmetal-hookable.dylib"
ewin > "$W/fc27.install.log" 2>&1 || say FAIL "fc 27: install failed: $(tail -2 "$W/fc27.install.log")"
[ "$(e1st)" = installed ] && [ "$(cat "$estore/LiveEditor/FCLiveEditor.DLL")" = one ] && [ -f "$estore/LiveEditor/FakeEAACLauncher/EAAntiCheat.GameServiceLauncher.exe" ] && [ ! -e "$estore/LiveEditor/Logs" ] \
  && cmp -s "$estore/fc27-le-play.sh" "$FIX/fc27-le-play.sh" && [ -x "$estore/fc27-le-play.sh" ] && cmp -s "$estore/fc27-le-run.cmd" "$FIX/fc27-le-run.cmd" && cmp -s "$estore/fc27-squads.pl" "$FIX/fc27-squads.pl" \
  && eswitched NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_ENGINE && /usr/bin/grep -q 'MGF_FANS=max' "$evdf" \
  && [ "$(/usr/bin/grep -c '^\[' "$eplug/mgf-4080220.uses")" = 0 ] && /usr/bin/grep -qx '# shared rows: NOTPROTON_MGF_ENGINE NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_PLAY' "$eplug/mgf-4080220.uses" \
  && [ "$(/usr/bin/grep -c '^\[' "$eplug/mgf-shared.conf")" = 3 ] && [ "$(/usr/bin/grep -c '^apps = 4080220$' "$eplug/mgf-shared.conf")" = 2 ] \
  && ! /usr/bin/grep -q 'NOTPROTON_MGF_PLAY' "$evdf" && /usr/bin/grep -qx 'inject = 1' "$eplug/mgf-shared.conf" \
  && cmp -s "$eplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" && [ ! -e "$eplug/mgf-d3dmetal-hookable.dylib" ] \
  && [ ! -e "$ec/game/EAAntiCheat.GameServiceLauncher.exe" ] \
  && case "$(cat "$W/fc27.install.log")" in *'AT YOUR OWN RISK'*'Offline only'*) true ;; *) false ;; esac \
  && say ok "fc 27 in NotProton: the folder the player chose (the one around Live Editor's) copied without its logs, the play script, no row of its own but the three shared rows for it and the engine library, the two shared switches and the script in the launch options, on a runner without patch 0041, nothing in the game folder, and the warning" || say FAIL "fc 27: installed ($(e1st)): $(tail -3 "$W/fc27.install.log")"
mv "$enp/plugin-host.dylib" "$enp/plugin-host.away"
eout="$(e1 --status 2>&1)"
[ "$(e1st)" = half ] && case "$eout" in *'update NotProton'*) true ;; *) false ;; esac \
  && ! e1 > "$W/fc27.nohost.log" 2>&1 && /usr/bin/grep -q 'plugin host' "$W/fc27.nohost.log" \
  && say ok "fc 27 in NotProton: without NotProton's plugin host it is half and says to update NotProton, and an install stops" || say FAIL "fc 27: no plugin host ($(e1st))"
mv "$enp/plugin-host.away" "$enp/plugin-host.dylib"
# An install from before the activation row: its switch was never put in. It reads half, and the
# install that brings the row switches it on, once, with the play script already in the options.
esw="$ec/compatdata/4080220/.mgf-notproton-plugins-switched"
/usr/bin/sed -i '' '/^NOTPROTON_MGF_ENGINE=/d' "$esw"; sed -i '' 's/NOTPROTON_MGF_ENGINE=1 //' "$evdf"
[ "$(e1st)" = half ] && e1 > "$W/fc27.newrow.log" 2>&1 && [ "$(e1st)" = installed ] && eswitched NOTPROTON_MGF_MODTOOL NOTPROTON_MGF_ENGINE \
  && say ok "fc 27 in NotProton: over an install from before the engine row, the row is switched on once and the script stays once" || say FAIL "fc 27: new row ($(e1st)): $(tail -2 "$W/fc27.newrow.log")"
# A new version by hand: installing again asks again. Cancel keeps the copy in use, the same
# folder is not copied twice, and a new one is taken with the copy that was in use kept once.
echo mine > "$estore/LiveEditor/lua/mine.lua"
: > "$ec/answer"; ewin > /dev/null 2>&1
[ "$(e1st)" = installed ] && [ "$(cat "$estore/LiveEditor/FCLiveEditor.DLL")" = one ] && [ ! -e "$estore/LiveEditor.previous" ] && [ -f "$estore/LiveEditor/lua/mine.lua" ] \
  && say ok "fc 27 in NotProton: installing again and cancelling the chooser keeps the Live Editor in use" || say FAIL "fc 27: cancel with one in use"
printf '%s\n' "$edl/FC 27 LE v1" > "$ec/answer"; ewin > /dev/null 2>&1
[ ! -e "$estore/LiveEditor.previous" ] && [ -f "$estore/LiveEditor/lua/mine.lua" ] \
  && say ok "fc 27 in NotProton: choosing the Live Editor already in use copies nothing" || say FAIL "fc 27: same folder copied again"
editor "$ec/newer/FC 27 LE v2" two 202612010000
printf '%s\n' "$ec/newer/FC 27 LE v2" > "$ec/answer"; ewin > /dev/null 2>&1
[ "$(e1st)" = installed ] && [ "$(cat "$estore/LiveEditor/FCLiveEditor.DLL")" = two ] && [ "$(cat "$estore/LiveEditor.previous/FCLiveEditor.DLL")" = one ] && [ -f "$estore/LiveEditor.previous/lua/mine.lua" ] \
  && say ok "fc 27 in NotProton: a new Live Editor is taken by installing again and choosing its folder, and the copy that was in use is kept" || say FAIL "fc 27: new version ($(cat "$estore/LiveEditor/FCLiveEditor.DLL"))"
mkdir -p "$ec/notit"; echo x > "$ec/notit/Launcher.exe"
eout="$(MGVF_LIVE_EDITOR="$ec/notit" e1 2>&1)" && say FAIL "fc 27: took a folder that is no Live Editor" || { case "$eout" in *'is not a Live Editor folder'*) true ;; *) false ;; esac && [ "$(cat "$estore/LiveEditor/FCLiveEditor.DLL")" = two ] \
  && say ok "fc 27 in NotProton: a folder that is no Live Editor is refused, and the one in use stays" || say FAIL "fc 27: notit: $eout"; }
echo '# older' >> "$estore/fc27-le-play.sh"
[ "$(e1st)" = outdated ] && e1 > /dev/null 2>&1 && [ "$(e1st)" = installed ] && say ok "fc 27 in NotProton: an older play script reads outdated, and installing again brings this one" || say FAIL "fc 27: outdated ($(e1st))"
# The play script, with a tool that only says what it was given.
printf '#!/bin/sh\nprintf "%%s|" "$@"; printf "\\nopens=%%s trace=%%s log=%%s\\n" "${NOTPROTON_ENV_FC27_OPENS:-}" "${WINEDEBUG:-}" "${NOTPROTON_ENV_MGF_D3DM_HOOKABLE_LOG:-}"\n' > "$ec/tool"; chmod +x "$ec/tool"
ecfg="$epfx/drive_c/FC 27 Live Editor/le_config.json"; mkdir -p "$(dirname "$ecfg")"
ecfg_new() { printf '{\n    "launcher": {\n        "auto_inject": false,\n        "dll_inject_delay": 100,\n        "no_mods": false\n    }\n}\n' > "$ecfg"; }
elink='steam2ea://launchgame/4080220?platform=steam&theme=fc27'
esrv="$ec/ea"; eset="$epfx/drive_c/users/steamuser/AppData/Local/EA SPORTS FC 27/settings"
eplay() { env -i HOME="$ehome" PATH=/usr/bin:/bin STEAM_COMPAT_APP_ID=4080220 STEAM_COMPAT_DATA_PATH="$ec/compatdata/4080220" MGF_FC27_SQUADS_URL="file://$esrv" "$@" "$estore/fc27-le-play.sh" "$ec/tool" waitforexitandrun "$elink"; }
ecfg_new; eout="$(eplay)"
case "$eout" in "waitforexitandrun|$elink|"*) true ;; *) false ;; esac && /usr/bin/grep -q '"dll_inject_delay": 100,' "$ecfg" \
  && say ok "fc 27's play script: with the row off, Steam's own command goes through and Live Editor's settings are left alone" || say FAIL "fc 27 play: row off: $eout"
eout="$(eplay NOTPROTON_MGF_MODTOOL=1)"
case "$eout" in "waitforexitandrun|cmd.exe|/d|/c|call|Z:$(printf '%s' "$estore/fc27-le-run.cmd" | tr / '\\')|"*"opens= trace= log=$estore/fc27-le-hooks.log") true ;; *) false ;; esac \
  && /usr/bin/grep -q '"dll_inject_delay": 1000,' "$ecfg" && /usr/bin/grep -q '"auto_inject": true,' "$ecfg" && /usr/bin/grep -q '"no_mods": false' "$ecfg" \
  && say ok "fc 27's play script: with the row on, the batch file takes the command's place, and the launcher's delay is raised and its injection switched on" || say FAIL "fc 27 play: row on: $eout / $(tr -d '\n' < "$ecfg")"
sed -i '' 's/"dll_inject_delay": 1000/"dll_inject_delay": 2500/' "$ecfg"; eplay NOTPROTON_MGF_MODTOOL=1 > /dev/null
# EA's newest squads, from a server of the test's: a rosterupdate.xml and a compressed database
# of 20 literal bytes and a 5-byte copy back, "DB\0\x08" and 25 bytes unpacked. With the row on,
# Play adds it to the game's saved squads in the background, wrapped as a saved squad file.
# The earlier Plays started it too, with no settings folder to write to: they end first.
squads_quiet() { local i=0; while [ $i -lt 50 ] && /usr/bin/pgrep -f "$estore/fc27-squads.pl" > /dev/null; do /bin/sleep 0.2; i=$((i+1)); done; }
squads_quiet
mkdir -p "$esrv/fc/fclive/genxtitle/roster/pc64" "$eset"
printf '<squad><squadInfoSet><squadInfo platform="ps5"><dbMajor>1</dbMajor><dbMajorLoc>fc/fclive/genxtitle/roster/ps5/squads_20260101_1_1_n1.bin</dbMajorLoc></squadInfo><squadInfo platform="pc64"><dbMajor>7</dbMajor><dbMajorLoc>fc/fclive/genxtitle/roster/pc64/squads_20261101_7_1_n2.bin</dbMajorLoc></squadInfo></squadInfoSet></squad>\n' > "$esrv/fc/fclive/genxtitle/rosterupdate.xml"
/usr/bin/perl -e 'print "\x10\xfb\x00\x00\x1d\x00\x00\x00\x00\x00", "\xe4", "ABCDEFGHIJKLMNOPQRST", "\x08\x13"' > "$esrv/fc/fclive/genxtitle/roster/pc64/squads_20261101_7_1_n2.bin"
esq="$eset/Squads20261101000000"
wait_squads() { /bin/sleep 0.2; squads_quiet; }
rm -f "$estore/fc27-squads.log"; eplay NOTPROTON_MGF_MODTOOL=1 > /dev/null; wait_squads
[ -f "$esq" ] && [ "$(/usr/bin/wc -c < "$esq" | tr -d ' ')" = $((1126 + 48 + 4 + 29 + 45985)) ] \
  && /bin/dd if="$esq" bs=1 skip=1178 count=29 2>/dev/null | /usr/bin/cmp -s - <(printf 'DB\000\010ABCDEFGHIJKLMNOPQRSTABCDE') \
  && [ "$(/bin/dd if="$esq" bs=1 skip=18 count=23 2>/dev/null)" = EA_Squads20261101000000 ] \
  && [ "$(/bin/dd if="$esq" bs=1 skip=1126 count=15 2>/dev/null)" = SaveType_Squads ] \
  && [ "$(/bin/dd if="$esq" bs=1 skip=1207 count=4 2>/dev/null)" = BNRY ] \
  && say ok "fc 27's play script: with the row on, EA's newest squads (pc64) are unpacked and added to the game's saved squads, in the background" || say FAIL "fc 27 squads: added: $(cat "$estore/fc27-squads.log" 2>/dev/null)"
echo mine > "$esq"; rm -f "$estore/fc27-squads.log"; eplay NOTPROTON_MGF_MODTOOL=1 > /dev/null; wait_squads
[ "$(cat "$esq")" = mine ] && /usr/bin/grep -q 'has it' "$estore/fc27-squads.log" \
  && say ok "fc 27's play script: a squad file already there is never replaced" || say FAIL "fc 27 squads: replaced: $(cat "$estore/fc27-squads.log" 2>/dev/null)"
rm -f "$esq"; mv "$esrv" "$esrv.away"; rm -f "$estore/fc27-squads.log"; eout="$(eplay NOTPROTON_MGF_MODTOOL=1)"; wait_squads
case "$eout" in "waitforexitandrun|cmd.exe|"*) true ;; *) false ;; esac && [ ! -e "$esq" ] && ! ls "$eset" | /usr/bin/grep -q part \
  && /usr/bin/grep -q 'could not' "$estore/fc27-squads.log" \
  && say ok "fc 27's play script: with EA's server out of reach the game still starts, nothing is added and the log says so" || say FAIL "fc 27 squads: offline: $eout / $(cat "$estore/fc27-squads.log" 2>/dev/null)"
mv "$esrv.away" "$esrv"
/usr/bin/grep -q '"dll_inject_delay": 2500,' "$ecfg" && say ok "fc 27's play script: a longer delay the player set is kept" || say FAIL "fc 27 play: lowered a delay"
ecfg_new; eout="$(eplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PLAY=window)"
case "$eout" in *"opens=window trace= log="*) true ;; *) false ;; esac && /usr/bin/grep -q '"auto_inject": false,' "$ecfg" && /usr/bin/grep -q '"dll_inject_delay": 100,' "$ecfg" \
  && ecfg_new && eout="$(eplay NOTPROTON_MGF_MODTOOL=1 NOTPROTON_MGF_PLAY=notes)" \
  && case "$eout" in *"opens= trace=err+all,fixme-all,+seh,+timestamp,+pid log="*) true ;; *) false ;; esac && /usr/bin/grep -q '"auto_inject": true,' "$ecfg" \
  && say ok "fc 27's play script: Play opens' window asks for the launcher's window with the settings as they are, and its notes choice starts the game with Wine's exception notes on" || say FAIL "fc 27 play: window and notes: $eout"
eout="$(env -i HOME="$ehome" PATH=/usr/bin:/bin STEAM_COMPAT_APP_ID=4080220 NOTPROTON_MGF_MODTOOL=1 "$estore/fc27-le-play.sh" "$ec/tool" waitforexitandrun /some/installer.exe)"
case "$eout" in "waitforexitandrun|/some/installer.exe|"*) true ;; *) false ;; esac && say ok "fc 27's play script: anything else Steam runs through the tool goes through unchanged" || say FAIL "fc 27 play: other: $eout"
# Groups, where NotProton knows them: both rows carry the game's own, and the library still goes in.
e1 --restore > /dev/null 2>&1
MGVF_NOTPROTON_GROUPS=1 e1 > /dev/null 2>&1
[ "$(MGVF_NOTPROTON_GROUPS=1 e1st)" = installed ] && [ "$(/usr/bin/grep -c '^group = MacGameFix / ' "$eplug/mgf-shared.conf")" = 3 ] && /usr/bin/grep -qx 'group = MacGameFix / Game fixes' "$eplug/mgf-shared.conf" && cmp -s "$eplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && say ok "fc 27 in NotProton: where NotProton knows groups the shared rows carry MacGameFix's, and the library is found all the same" || say FAIL "fc 27: groups ($(MGVF_NOTPROTON_GROUPS=1 e1st))"
# A game with no row of its own keeps its note of the shared rows out of NotProton's list: as
# mgf-<appid>.uses, not as a .conf, which NotProton's app lists by its file name. The .conf an
# earlier install left reads half, and the next install takes it away.
[ -f "$eplug/mgf-4080220.uses" ] && [ ! -e "$eplug/mgf-4080220.conf" ] && [ "$(/usr/bin/grep -c '^\[' "$eplug/mgf-4080220.uses")" = 0 ] \
  && say ok "fc 27 in NotProton: its note of the shared rows it uses is no .conf, so NotProton's app does not list it" || say FAIL "fc 27: the note's name" "$(ls "$eplug")"
mv "$eplug/mgf-4080220.uses" "$eplug/mgf-4080220.conf"
enote="$(MGVF_NOTPROTON_GROUPS=1 e1st)"
MGVF_NOTPROTON_GROUPS=1 e1 > /dev/null 2>&1
[ "$enote" = half ] && [ "$(MGVF_NOTPROTON_GROUPS=1 e1st)" = installed ] && [ -f "$eplug/mgf-4080220.uses" ] && [ ! -e "$eplug/mgf-4080220.conf" ] \
  && /usr/bin/grep -q '^apps = 4080220$' "$eplug/mgf-shared.conf" \
  && say ok "fc 27 in NotProton: the note an earlier install left as a .conf reads half, and installing again renames it" || say FAIL "fc 27: the note migrated ($enote, $(MGVF_NOTPROTON_GROUPS=1 e1st))" "$(ls "$eplug")"
# Removing: the options and NotProton as they were, the player's Live Editor kept, and the game's
# own EA AntiCheat launcher back where a cut-short session left the stand-in.
echo standin > "$ec/game/EAAntiCheat.GameServiceLauncher.exe"; echo theirs > "$ec/game/EAAntiCheat.GameServiceLauncher.exe.backup"
MGVF_NOTPROTON_GROUPS=1 e1 --restore > "$W/fc27.restore.log" 2>&1
[ "$(e1st)" = absent ] && [ "$(cat "$evdf")" = "$evdf0" ] && [ ! -e "$eplug/mgf-4080220.uses" ] && [ ! -e "$eplug/mgf-d3dmetal-hookable.dylib" ] && [ ! -e "$eplug/mgf-shared.conf" ] && [ ! -e "$eplug/mgf-engine.dylib" ] \
  && [ ! -e "$estore/fc27-le-play.sh" ] && [ "$(cat "$estore/LiveEditor/FCLiveEditor.DLL")" = two ] \
  && [ "$(cat "$ec/game/EAAntiCheat.GameServiceLauncher.exe")" = theirs ] && [ ! -e "$ec/game/EAAntiCheat.GameServiceLauncher.exe.backup" ] \
  && say ok "fc 27 in NotProton: removed, the launch options and NotProton are as before, the player's Live Editor stays, and the game's own EA AntiCheat launcher is back" || say FAIL "fc 27: restore ($(e1st)): $(tail -3 "$W/fc27.restore.log")"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - FEX\n' > "$ec/compatdata/4080220/notproton-build"
[ "$(e1st)" = norecipe ] && say ok "fc 27: the FEX side has no recipe" || say FAIL "fc 27: FEX ($(e1st))"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$ec/compatdata/4080220/notproton-build"
touch "$epfx/cxbottle.conf"; [ "$(e1st)" = norecipe ] && say ok "fc 27: a CrossOver bottle has no recipe" || say FAIL "fc 27: bottle ($(e1st))"; rm -f "$epfx/cxbottle.conf"

# Need for Speed Unbound's fix changes the game's renderer DLL by recipe, keyed
# by its sha256. The game's DLL is not here, so the test makes one: the recipe's
# "from" bytes at their offsets in a file of 0xcc, and recipe rows for it, the
# real rows' bytes under this file's sha256s, beside a copy of the installer.
nf="$W/nfsfix"; g="$W/nfs"; mkdir -p "$nf" "$g"; touch "$g/NeedForSpeedUnbound.exe"
cp "$FIX/install-nfsu-fix.sh" "$nf/"
nd="$g/Engine.Render.Core2.PlatformPcDx12.dll"
/usr/bin/python3 -I - "$FIX/nfsu-prebuild.recipes" "$nf/nfsu-prebuild.recipes" "$nd" "$W/nfs-older.dll" <<'PY'
import hashlib, sys
src, rec, dll, old = sys.argv[1:]
rows = [l.split() for l in open(src) if l.strip() and not l.startswith('#')]
edits, older = [r for r in rows if r[0] == 'edit'], [r for r in rows if r[0] == 'older'][0]
def put(b, off, hexs): o = int(off, 16); v = bytes.fromhex(hexs); b[o:o + len(v)] = v
d = bytearray(b'\xcc' * 0x220000)
for e in edits: put(d, e[2], e[3])
put(d, older[3], older[4])
h = hashlib.sha256(d).hexdigest()
p = bytearray(d); [put(p, e[2], e[4]) for e in edits]
q = bytearray(d); put(q, older[3], older[5])
out = [f'result {h} {hashlib.sha256(p).hexdigest()}'] + [f'edit {h} {e[2]} {e[3]} {e[4]}' for e in edits]
out.append(f'older {hashlib.sha256(q).hexdigest()} {h} {older[3]} {older[4]} {older[5]}')
open(rec, 'w').write('\n'.join(out) + '\n')
open(dll, 'wb').write(d); open(old, 'wb').write(q)
PY
cp "$nd" "$W/nfs-orig.dll"
nfsst() { FIX="$nf" st install-nfsu-fix.sh "$g"; }
nfs() { /bin/bash "$nf/install-nfsu-fix.sh" "$g" "$@"; }
[ "$(nfsst)" = absent ] && say ok "nfs unbound: absent before" || say FAIL "nfs unbound: absent before ($(nfsst))"
nfs > "$W/nfs.install.log" 2>&1 && [ "$(nfsst)" = installed ] && cmp -s "$nd.mgvf-original" "$W/nfs-orig.dll" \
  && say ok "nfs unbound: installed, the original kept beside it" || say FAIL "nfs unbound: install ($(nfsst)): $(tail -2 "$W/nfs.install.log")"
nfs --restore > /dev/null 2>&1 && [ "$(nfsst)" = absent ] && cmp -s "$nd" "$W/nfs-orig.dll" && [ ! -e "$nd.mgvf-original" ] \
  && say ok "nfs unbound: restored from the kept original" || say FAIL "nfs unbound: restore ($(nfsst))"
nfs > /dev/null 2>&1; rm -f "$nd.mgvf-original"
nfs --restore > /dev/null 2>&1 && cmp -s "$nd" "$W/nfs-orig.dll" \
  && say ok "nfs unbound: restored without the kept copy, by undoing the recipe" || say FAIL "nfs unbound: restore by undoing ($(nfsst))"
cp "$W/nfs-older.dll" "$nd"
[ "$(nfsst)" = half ] && say ok "nfs unbound: the first fix (pre-build off) is half" || say FAIL "nfs unbound: older fix ($(nfsst))"
nfs > /dev/null 2>&1 && [ "$(nfsst)" = installed ] && cmp -s "$nd.mgvf-original" "$W/nfs-orig.dll" \
  && say ok "nfs unbound: installing over the first fix undoes it, and keeps the true original" || say FAIL "nfs unbound: over the first fix ($(nfsst))"
nfs --restore > /dev/null 2>&1
printf x >> "$nd"
[ "$(nfsst)" = norecipe ] && ! nfs > /dev/null 2>&1 && say ok "nfs unbound: another build waits for a recipe, untouched" || say FAIL "nfs unbound: unknown build ($(nfsst))"

# The Wolf Among Us Remastered's fix is a d3d11.dll beside the game and one
# override in the prefix: tried in a fake Steam Play prefix.
wp="$W/wolfpfx"; mkdir -p "$wp/drive_c"; touch "$wp/system.reg"
printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n' > "$wp/user.reg"
g="$W/wolf"; mkdir -p "$g"; touch "$g/TheWolfAmongUsRemastered.exe"
wst() { MGVF_BOTTLE="$wp" st install-wolf-fix.sh "$g"; }
wolf() { MGVF_BOTTLE="$wp" /bin/bash "$FIX/install-wolf-fix.sh" "$g" "$@"; }
wolfkey() { /usr/bin/grep -qF '"d3d11"="native,builtin"' "$wp/user.reg"; }
[ "$(wst)" = absent ] && say ok "wolf in a Steam Play prefix: absent before" || say FAIL "wolf: absent before ($(wst))"
echo "someone else's d3d11" > "$g/d3d11.dll"
wolf > "$W/wolf.install.log" 2>&1 && [ "$(wst)" = installed ] && cmp -s "$g/d3d11.dll" "$FIX/d3d11-wolf.dll" && wolfkey \
  && [ "$(cat "$g/d3d11.dll.mgvf-original")" = "someone else's d3d11" ] \
  && say ok "wolf in a Steam Play prefix: the DLL, the override for its exe, and the folder's own d3d11 kept" || say FAIL "wolf: install ($(wst)): $(tail -2 "$W/wolf.install.log")"
MGVF_BOTTLE="$wp" /bin/bash -c '. "$1/bottles.sh"; user_reg_edit "$2" delete "Software\\Wine\\AppDefaults\\TheWolfAmongUsRemastered.exe\\DllOverrides" d3d11' _ "$FIX" "$wp"
[ "$(wst)" = half ] && say ok "wolf in a Steam Play prefix: the override taken out is half" || say FAIL "wolf: half ($(wst))"
wolf > /dev/null 2>&1 && [ "$(wst)" = installed ] && say ok "wolf in a Steam Play prefix: installing again repairs it" || say FAIL "wolf: repair ($(wst))"
older "$g/d3d11.dll"
[ "$(wst)" = outdated ] && say ok "wolf in a Steam Play prefix: an older build is outdated" || say FAIL "wolf: older build ($(wst))"
wolf > /dev/null 2>&1
last="$(wolf --restore 2>/dev/null | tail -1)"
[ "$last" = restored ] && [ "$(wst)" = absent ] && ! wolfkey && [ "$(cat "$g/d3d11.dll")" = "someone else's d3d11" ] && [ ! -e "$g/d3d11.dll.mgvf-original" ] \
  && say ok "wolf in a Steam Play prefix: restored, the override gone and the folder's own d3d11 back" || say FAIL "wolf: restore ($last, $(wst))"

# Cyberpunk 2077's fix writes four bytes into a macOS game's executable and signs
# the app again, so it is tried on a fake app: a small executable built here,
# with the word the recipe changes behind a tag the test finds it by, signed ad
# hoc so the app has a seal, and a framework inside signed on its own. The
# installer is copied beside a recipe made for that executable. Its whole life:
# installed, with the hardened runtime and the two entitlements, the framework
# untouched and nothing else in the game folder changed; installed again, and
# after a Steam verify, without the kept original being replaced; a broken
# signature, or a change beside the patch, rebuilt from the original; restored
# byte for byte; two copies of one build sharing the kept original; stopped by
# Ctrl-C while signing, or by its reader going away, and put back. Refused, with nothing changed: on an M1
# or an M2, while the game runs (started by another spelling of its path), for
# a build with no recipe or an executable no row was made from, for one patched
# by hand, over a kept copy that is not the original, and when macOS refuses
# the write; one changed again after an install is put back from the kept
# original. The copies kept for other builds of this app go at an install and
# at a removal, a removal on a build with no recipe too; those of another app,
# or of another bundle id that begins the same, stay.
# The fake is called Cyberpunk2077, as the game is: the installer knows no other
# name, and finds the game running by its executable.
g="$W/cp2077"; app="$g/Cyberpunk2077.app"; exe="$app/Contents/MacOS/Cyberpunk2077"; seal="$app/Contents/_CodeSignature/CodeResources"
lib="$app/Contents/Frameworks/libFake.dylib"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$W/cpfix" "$W/cpbin" "$W/cpm1" "$W/cpslow"
cat > "$W/cp.c" <<'C'
#include <stdlib.h>
#include <unistd.h>
/* "MGVFTEST", then mov w0,#0. */
const volatile unsigned int word[] = { 0x4656474d, 0x54534554, 0x52800000 };
int main(int argc, char **argv) { if (argc > 1) sleep(atoi(argv[1])); return word[0] == 0x4656474d ? 0 : 1; }
C
printf 'int fake(void) { return 1; }\n' > "$W/lib.c"
cc -O1 -o "$exe" "$W/cp.c" && cc -dynamiclib -o "$lib" "$W/lib.c" || say FAIL "cp2077: the fake app could not be built (cc)"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.macgamefix.test.cp2077' -c 'Add :CFBundleExecutable string Cyberpunk2077' \
  -c 'Add :CFBundlePackageType string APPL' -c 'Add :CFBundleShortVersionString string 9.9' -c 'Add :CFBundleVersion string 42' \
  "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - "$lib" 2>/dev/null && codesign --force --sign - "$app" 2>/dev/null || say FAIL "cp2077: the fake app could not be signed"
cp "$exe" "$W/cp.orig"; cp "$seal" "$W/cp.seal"; cp "$lib" "$W/cp.lib"; cp "$app/Contents/Info.plist" "$W/cp.plist"
# A second copy of the same build, in another folder, for the kept copy they share.
g2="$W/cp2077-second"; ditto "$g" "$g2"
off="$(/usr/bin/python3 -I -c 'import sys; print(open(sys.argv[1], "rb").read().find(b"MGVFTEST") + 8)' "$exe")"
cp "$exe" "$W/cp.patched"; printf '\040\000\200\122' | dd of="$W/cp.patched" bs=4 seek=$((off / 4)) count=1 conv=notrunc 2>/dev/null
cp "$FIX/install-cp2077-denoiser.sh" "$W/cpfix/"
row="42 $(shasum -a 256 "$exe" | cut -d' ' -f1) $(printf '0x%x' "$off") 00008052 20008052 $(shasum -a 256 "$W/cp.patched" | cut -d' ' -f1)"
printf '# The fake app'"'"'s recipe.\n%s\n' "$row" > "$W/cpfix/cp2077-denoiser.recipes"
export MGVF_APP_BACKUP="$W/app-backup"
# The installer names the app by its real path: $W may be reached through a symbolic link.
canon="$(cd "$app" && pwd -P)"
kept="$MGVF_APP_BACKUP/io.github.macgamefix.test.cp2077-42"; stale="$MGVF_APP_BACKUP/io.github.macgamefix.test.cp2077-41"
mkdir -p "$stale"; echo "an older build's executable" > "$stale/Cyberpunk2077"; echo "$canon" > "$stale/apps"
other="$MGVF_APP_BACKUP/io.github.macgamefix.test.cp2077-40"; mkdir -p "$other"; echo "/elsewhere/Cyberpunk2077.app" > "$other/apps"
beta="$MGVF_APP_BACKUP/io.github.macgamefix.test.cp2077-beta-7"; mkdir -p "$beta"; echo "$canon" > "$beta/apps"
cpst() { FIX="$W/cpfix" st install-cp2077-denoiser.sh "$g"; }
cpst2() { FIX="$W/cpfix" st install-cp2077-denoiser.sh "$g2"; }
cp2077() { /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g" "$@"; }
at() { dd if="$exe" bs=4 skip=$((off / 4)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
back() { ditto "$W/cp.orig" "$exe"; ditto "$W/cp.seal" "$seal"; }
# Every file of the game folder and its sha256, to see what changed.
tree() { (cd "$g" && find . -type f -exec shasum -a 256 {} + | sort -k2); }
changed() { diff "$1" "$2" | sed -n 's/^[<>] [0-9a-f]*  //p' | sort -u | tr '\n' ' '; }
running() { # a fake game started from inside its folder, by a relative path
  (cd "$g" && exec ./Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077 30) & cppid=$!
  sleep 1
}
stopped() { kill "$cppid" 2>/dev/null; wait "$cppid" 2>/dev/null; }
[ "$(cpst)" = absent ] && say ok "cp2077 on a fake app: absent before" || say FAIL "cp2077: absent before ($(cpst))"
printf '#!/bin/sh\necho "Apple M2 Pro"\n' > "$W/cpbin/sysctl"; chmod +x "$W/cpbin/sysctl"
printf '#!/bin/sh\necho "Apple M1"\n' > "$W/cpm1/sysctl"; chmod +x "$W/cpm1/sysctl"
m2st="$(PATH="$W/cpbin:$PATH" cpst)"; m1st="$(PATH="$W/cpm1:$PATH" cpst)"
! PATH="$W/cpbin:$PATH" cp2077 > "$W/cp.m2.log" 2>&1 && /usr/bin/grep -q "M3 and later" "$W/cp.m2.log" && cmp -s "$exe" "$W/cp.orig" \
  && ! PATH="$W/cpm1:$PATH" cp2077 > "$W/cp.m1.log" 2>&1 && /usr/bin/grep -q "an Apple M1\. " "$W/cp.m1.log" && cmp -s "$exe" "$W/cp.orig" \
  && [ "$m2st" = blocked ] && [ "$m1st" = blocked ] && [ ! -e "$kept" ] && [ -d "$stale" ] \
  && say ok "cp2077 on a fake app: blocked on an M1 and an M2, and installing there changes nothing" || say FAIL "cp2077: M1/M2 ($m1st, $m2st, $(tail -1 "$W/cp.m2.log"))"
running
! /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g/" > "$W/cp.run.log" 2>&1 && /usr/bin/grep -q "is running" "$W/cp.run.log" && cmp -s "$exe" "$W/cp.orig" \
  && say ok "cp2077 on a fake app: refused while the game runs, started and named by other spellings of its path" || say FAIL "cp2077: running ($(tail -1 "$W/cp.run.log"))"
stopped
mkdir -p "$kept"; echo "not the original" > "$kept/Cyberpunk2077"; cp "$kept/Cyberpunk2077" "$W/cp.junk"
! cp2077 > "$W/cp.junk.log" 2>&1 && /usr/bin/grep -q "is not this build's original" "$W/cp.junk.log" && cmp -s "$exe" "$W/cp.orig" \
  && cmp -s "$kept/Cyberpunk2077" "$W/cp.junk" && [ "$(cpst)" = absent ] \
  && say ok "cp2077 on a fake app: a kept copy that is not the original is refused, and both stay as they were" || say FAIL "cp2077: junk copy ($(cpst), $(tail -1 "$W/cp.junk.log"))"
rm -rf "$kept"
# Two rows for one build: the one made from this executable is found, whichever comes first.
printf '42 %s 0x%x 00008052 20008052 %s\n%s\n' "$(printf 'a%.0s' $(seq 64))" "$off" "$(printf 'b%.0s' $(seq 64))" "$row" > "$W/cpfix/cp2077-denoiser.recipes"
[ "$(cpst)" = absent ] && say ok "cp2077 on a fake app: of two rows for one build, the one made from this executable is taken" || say FAIL "cp2077: two rows ($(cpst))"
tree > "$W/cp.tree.before"
cp2077 > "$W/cp.install1.log" 2>&1 || say FAIL "cp2077: install failed: $(tail -2 "$W/cp.install1.log")"
keys="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | /usr/bin/grep -o '<key>[^<]*</key>' | tr '\n' ' ')"
[ "$(cpst)" = installed ] && [ "$(at)" = 20008052 ] && codesign --verify --strict "$app" 2>/dev/null \
  && say ok "cp2077 on a fake app: installed, the four bytes written, the app's signature verifies" || say FAIL "cp2077: installed ($(cpst), $(at))"
flags="$(codesign -dv "$app" 2>&1 | /usr/bin/grep -o 'flags=[^ ]*')"
[ "$flags" = "flags=0x10002(adhoc,runtime)" ] \
  && [ "$keys" = "<key>com.apple.security.cs.allow-dyld-environment-variables</key> <key>com.apple.security.cs.disable-library-validation</key> " ] \
  && say ok "cp2077 on a fake app: signed ad hoc with the hardened runtime and the two entitlements" || say FAIL "cp2077: signature ($flags, $keys)"
tree > "$W/cp.tree.installed"
[ "$(changed "$W/cp.tree.before" "$W/cp.tree.installed")" = "./Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077 " ] && cmp -s "$seal" "$W/cp.seal" && cmp -s "$lib" "$W/cp.lib" \
  && say ok "cp2077 on a fake app: of every file in the game folder only the executable changed; the seal and the framework are the same" \
  || say FAIL "cp2077: files changed: $(changed "$W/cp.tree.before" "$W/cp.tree.installed")"
[ "$(cd "$kept" && ls -A | tr '\n' ' ')" = "CodeResources Cyberpunk2077 apps " ] && cmp -s "$kept/Cyberpunk2077" "$W/cp.orig" && cmp -s "$kept/CodeResources" "$W/cp.seal" \
  && [ "$(cat "$kept/apps")" = "$canon" ] \
  && say ok "cp2077 on a fake app: the original and its seal kept outside the app, for this app, and nothing else there" || say FAIL "cp2077: kept copy ($(cd "$kept" && ls -A | tr '\n' ' '))"
[ ! -e "$stale" ] && /usr/bin/grep -q "removed the copy kept for build 41" "$W/cp.install1.log" && [ -d "$other" ] && [ -d "$beta" ] \
  && say ok "cp2077 on a fake app: the copy kept for another build of this app is removed; another app's, and another bundle id's, stay" || say FAIL "cp2077: stale copies"
"$exe" && say ok "cp2077 on a fake app: the signed executable starts" || say FAIL "cp2077: the signed executable does not start"
inode="$(stat -f %i "$kept/Cyberpunk2077")"; cp "$exe" "$W/cp.installed"
cp2077 > "$W/cp.install2.log" 2>&1 && [ "$(cpst)" = installed ] && [ "$(stat -f %i "$kept/Cyberpunk2077")" = "$inode" ] && cmp -s "$exe" "$W/cp.installed" \
  && say ok "cp2077 on a fake app: installing again changes nothing" || say FAIL "cp2077: install twice ($(cpst))"
back
[ "$(cpst)" = absent ] && cp2077 > "$W/cp.install3.log" 2>&1 && [ "$(cpst)" = installed ] && [ "$(stat -f %i "$kept/Cyberpunk2077")" = "$inode" ] \
  && say ok "cp2077 on a fake app: after the original comes back it installs again, and the kept original is not replaced" || say FAIL "cp2077: after a verify ($(cpst))"
ditto "$W/cp.patched" "$exe"
[ "$(cpst)" = broken ] && cp2077 > "$W/cp.install4.log" 2>&1 && [ "$(cpst)" = installed ] && codesign --verify --strict "$app" 2>/dev/null \
  && say ok "cp2077 on a fake app: patched and not signed is broken, and installing signs it" || say FAIL "cp2077: broken ($(cpst))"
# Patched, with its tag changed too, and not signed: installing starts from the
# original, so the tag comes back and the executable starts (it fails without it).
cp "$W/cp.patched" "$W/cp.tampered"; printf 'X' | dd of="$W/cp.tampered" bs=1 seek=$((off - 8)) count=1 conv=notrunc 2>/dev/null
ditto "$W/cp.tampered" "$exe"
[ "$(cpst)" = broken ] && cp2077 > "$W/cp.install5.log" 2>&1 && [ "$(cpst)" = installed ] && "$exe" \
  && say ok "cp2077 on a fake app: a broken executable changed beside the patch is rebuilt from the original" || say FAIL "cp2077: tampered ($(cpst), $(tail -1 "$W/cp.install5.log"))"
# Ctrl-C while the app is being signed: the original goes back. The installer
# runs in a process group of its own with Ctrl-C not ignored, as from a
# terminal (a background job of a script ignores it), and its codesign waits
# until it is told.
printf '#!/bin/sh\ncase " $* " in *" --force "*) : > "%s"; sleep 5 ;; esac\nexec /usr/bin/codesign "$@"\n' "$W/cp.signing" > "$W/cpslow/codesign"
chmod +x "$W/cpslow/codesign"
back
PATH="$W/cpslow:$PATH" /usr/bin/python3 -I -c 'import os, signal, sys; os.setpgrp(); signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' \
  /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g" > "$W/cp.interrupted.log" 2>&1 & ipid=$!
n=0; while [ ! -e "$W/cp.signing" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -INT -- "-$ipid" 2>/dev/null; wait "$ipid"; irc=$?
[ -e "$W/cp.signing" ] && [ "$irc" != 0 ] && cmp -s "$exe" "$W/cp.orig" && cmp -s "$seal" "$W/cp.seal" && [ "$(cpst)" = absent ] \
  && [ -z "$(ls "$app/Contents/MacOS" | /usr/bin/grep -v '^Cyberpunk2077$')" ] && /usr/bin/grep -q "back in place" "$W/cp.interrupted.log" \
  && say ok "cp2077 on a fake app: Ctrl-C while signing puts the original back" || say FAIL "cp2077: interrupted ($(cpst), rc $irc, $(tail -1 "$W/cp.interrupted.log"))"
# The reader of its output gone in the middle, as when MacGameFix quits: the
# next line it writes fails, and the original goes back. Its sha256 is slowed
# so that the reader is gone by then, and SIGPIPE is not ignored, whatever
# started this test.
mkdir -p "$W/cpslowsha"; printf '#!/bin/sh\nsleep 1\nexec /usr/bin/shasum "$@"\n' > "$W/cpslowsha/shasum"; chmod +x "$W/cpslowsha/shasum"
PATH="$W/cpslowsha:$PATH" /usr/bin/python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' \
  /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g" 2> "$W/cp.gone.log" | head -n 4 > "$W/cp.gone.out"
[ "$(tail -1 "$W/cp.gone.out" | cut -c1-5)" = "[2/3]" ] && cmp -s "$exe" "$W/cp.orig" && cmp -s "$seal" "$W/cp.seal" && [ "$(cpst)" = absent ] \
  && /usr/bin/grep -q "back in place" "$W/cp.gone.log" \
  && say ok "cp2077 on a fake app: its reader gone after the write, the original goes back" || say FAIL "cp2077: reader gone ($(cpst), $(tail -1 "$W/cp.gone.log"))"
cp2077 > "$W/cp.install6.log" 2>&1 && [ "$(cpst)" = installed ] || say FAIL "cp2077: install after the interruption ($(cpst))"
# The second copy of the build shares the kept original, and keeps it until it is removed too.
/bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g2" > "$W/cp.second.log" 2>&1 && [ "$(cpst2)" = installed ] \
  && [ "$(sort "$kept/apps" | tr '\n' ' ')" = "$(printf '%s\n%s\n' "$canon" "$(cd "$g2/Cyberpunk2077.app" && pwd -P)" | sort | tr '\n' ' ')" ] \
  && say ok "cp2077 on a fake app: a second copy of the build shares the kept original" || say FAIL "cp2077: second copy ($(cpst2))"
running
! cp2077 --restore > "$W/cp.restore-run.log" 2>&1 && /usr/bin/grep -q "is running" "$W/cp.restore-run.log" && [ "$(cpst)" = installed ] \
  && say ok "cp2077 on a fake app: removing is refused while the game runs" || say FAIL "cp2077: restore while running ($(cpst))"
stopped
mkdir -p "$stale"; echo "an older build's executable" > "$stale/Cyberpunk2077"; echo "$canon" > "$stale/apps"
cp2077 --restore > "$W/cp.restore.log" 2>&1 || say FAIL "cp2077: restore failed: $(tail -2 "$W/cp.restore.log")"
[ "$(cpst)" = absent ] && cmp -s "$exe" "$W/cp.orig" && cmp -s "$seal" "$W/cp.seal" && codesign --verify --strict "$app" 2>/dev/null \
  && tree > "$W/cp.tree.restored" && cmp -s "$W/cp.tree.before" "$W/cp.tree.restored" \
  && say ok "cp2077 on a fake app: restored byte for byte, every file as before, its own signature back" || say FAIL "cp2077: restore ($(cpst))"
[ ! -e "$stale" ] && /usr/bin/grep -q "removed the copy kept for build 41" "$W/cp.restore.log" \
  && say ok "cp2077 on a fake app: removing drops the copy kept for another build too" || say FAIL "cp2077: stale copy at restore"
[ -d "$kept" ] && [ "$(cat "$kept/apps")" = "$(cd "$g2/Cyberpunk2077.app" && pwd -P)" ] && [ "$(cpst2)" = installed ] \
  && /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g2" --restore > "$W/cp.second-restore.log" 2>&1 && [ "$(cpst2)" = absent ] && [ ! -e "$kept" ] \
  && say ok "cp2077 on a fake app: the shared copy stays for the other copy, and goes when that one is removed" || say FAIL "cp2077: shared copy ($(cpst2))"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 43' "$app/Contents/Info.plist"
[ "$(cpst)" = norecipe ] && ! cp2077 > "$W/cp.norecipe.log" 2>&1 && cmp -s "$exe" "$W/cp.orig" && [ ! -e "$MGVF_APP_BACKUP/io.github.macgamefix.test.cp2077-43" ] \
  && say ok "cp2077 on a fake app: a build with no recipe is norecipe, and installing changes nothing" || say FAIL "cp2077: norecipe ($(cpst))"
# After a game update with no recipe yet, removing is all that clears the copy
# kept for the build before.
mkdir -p "$kept"; cp "$W/cp.orig" "$kept/Cyberpunk2077"; echo "$canon" > "$kept/apps"
cp2077 --restore > "$W/cp.restore-norecipe.log" 2>&1 && [ ! -e "$kept" ] && /usr/bin/grep -q "removed the copy kept for build 42" "$W/cp.restore-norecipe.log" \
  && cmp -s "$exe" "$W/cp.orig" && [ "$(cpst)" = norecipe ] \
  && say ok "cp2077 on a fake app: removing on a build with no recipe drops the copy kept for the build before" || say FAIL "cp2077: restore on norecipe ($(tail -1 "$W/cp.restore-norecipe.log"))"
rm -f "$app/Contents/Info.plist"
nost="$(/bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g" --status 2>&1)"
case "$nost" in *"Will Create"*|*"Game build"*) nost_ok=0 ;; *) nost_ok=1 ;; esac
[ "$nost_ok" = 1 ] && [ "$(cpst)" = norecipe ] && say ok "cp2077 on a fake app: with no Info.plist it names no build and has no recipe" || say FAIL "cp2077: no Info.plist ($nost)"
cp "$W/cp.plist" "$app/Contents/Info.plist"
# Signed again by someone else: neither the original nor patched, with a row for its build.
codesign --force --sign - --options runtime "$app" 2>/dev/null; cp "$exe" "$W/cp.other"
[ "$(cpst)" = blocked ] && ! cp2077 > "$W/cp.other.log" 2>&1 && /usr/bin/grep -q "Verify integrity" "$W/cp.other.log" && cmp -s "$exe" "$W/cp.other" \
  && say ok "cp2077 on a fake app: an executable no row was made from is blocked, with Steam's verify as the way back" || say FAIL "cp2077: other executable ($(cpst))"
back; cp2077 > /dev/null 2>&1; ditto "$W/cp.other" "$exe"
[ "$(cpst)" = blocked ] && cp2077 --restore > "$W/cp.restore-other.log" 2>&1 && [ "$(cpst)" = absent ] && cmp -s "$exe" "$W/cp.orig" && [ ! -e "$kept" ] \
  && say ok "cp2077 on a fake app: changed again after MacGameFix installed, it is blocked, and removing puts the kept original back" \
  || say FAIL "cp2077: changed after install ($(cpst), $(tail -1 "$W/cp.restore-other.log"))"
back; printf '\040\000\200\122' | dd of="$exe" bs=4 seek=$((off / 4)) count=1 conv=notrunc 2>/dev/null; cp "$exe" "$W/cp.byhand"
[ "$(cpst)" = half ] && ! cp2077 > "$W/cp.half.log" 2>&1 && /usr/bin/grep -q "Verify integrity" "$W/cp.half.log" && ! cp2077 --restore > /dev/null 2>&1 \
  && cmp -s "$exe" "$W/cp.byhand" && say ok "cp2077 on a fake app: patched by hand is half, and install and restore leave it" || say FAIL "cp2077: half ($(cpst))"
# App Management refuses a write into the app with EPERM; a sandbox that denies
# writes inside the app does the same.
back
! /usr/bin/sandbox-exec -p "(version 1)(allow default)(deny file-write* (subpath \"$canon\"))" \
    /bin/bash "$W/cpfix/install-cp2077-denoiser.sh" "$g" > "$W/cp.refused.log" 2>&1 \
  && /usr/bin/grep -q "App Management" "$W/cp.refused.log" && cmp -s "$exe" "$W/cp.orig" && [ "$(cpst)" = absent ] \
  && say ok "cp2077 on a fake app: a write macOS refuses points to App Management, nothing changed" || say FAIL "cp2077: refused ($(tail -2 "$W/cp.refused.log"))"
unset MGVF_APP_BACKUP

# Forza Horizon 5's user-facing installer coordinates two proxies and makes a
# private D3DMetal alias from the selected runner. A fake Steam Play prefix is
# enough to exercise its whole reversible life: the shipped proxies stand in
# for the runner modules because only their export tables are used here.
fh="$W/fh5"; fhhome="$fh/home"; fhrun="$fh/runner"; fhpfx="$fh/pfx"; fhgame="$fh/game"
mkdir -p "$fhhome" "$fhrun/bin" \
  "$fhrun/lib/apple_gptk/wine/x86_64-windows" "$fhrun/lib/apple_gptk/wine/x86_64-unix" \
  "$fhrun/lib/wine/x86_64-windows" "$fhrun/lib/wine/x86_64-unix" \
  "$fhpfx/drive_c/windows/system32" "$fhgame"
printf '#!/bin/sh\nexit 0\n' > "$fhrun/bin/wine"; chmod +x "$fhrun/bin/wine"
cp "$FIX/d3d12-fh5.dll" "$fhrun/lib/apple_gptk/wine/x86_64-windows/d3d12.dll"
touch "$fhrun/lib/apple_gptk/wine/x86_64-unix/d3d12.so"
cp "$FIX/ws2_32-fh5.dll" "$fhrun/lib/wine/x86_64-windows/ws2_32.dll"
touch "$fhrun/lib/wine/x86_64-unix/ws2_32.so"
# A WebView2 Version set before the fix must come back after --restore.
printf 'WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\AppDefaults\\\\msedgewebview2.exe] 1700000000\n#time=1d9e0a1b2c3d4e5\n"Version"="winxp"\n' > "$fhpfx/user.reg"
printf 'WINE REGISTRY Version 2\n' > "$fhpfx/system.reg"
printf 'fake executable\n' > "$fhgame/ForzaHorizon5.exe"
printf 'original game d3d12\n' > "$fhgame/d3d12.dll"
printf 'original prefix apd12\n' > "$fhpfx/drive_c/windows/system32/apd12.dll"
printf 'original prefix ws2\n' > "$fhpfx/drive_c/windows/system32/ws2_32.dll"
cp "$fhgame/d3d12.dll" "$fh/orig-d3d12"
cp "$fhpfx/drive_c/windows/system32/apd12.dll" "$fh/orig-apd12"
cp "$fhpfx/drive_c/windows/system32/ws2_32.dll" "$fh/orig-ws2"
fhdo() { HOME="$fhhome" MGVF_CX="$fhrun" MGVF_BOTTLE="$fhpfx" /bin/bash "$FIX/install-fh5-fix.sh" "$fhgame" "$@"; }
fhst() { fhdo --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half)$' | tail -1; }
fhreg() { /usr/bin/grep -c -F "$1" "$fhpfx/user.reg" || true; }
[ "$(fhst)" = absent ] && say ok "fh5 on a fake prefix: absent before" || say FAIL "fh5: absent before ($(fhst))"
fhdo --install > "$fh/install.log" 2>&1 \
  && [ "$(fhst)" = installed ] \
  && cmp -s "$fhgame/d3d12.dll" "$FIX/d3d12-fh5.dll" \
  && [ -f "$fhgame/d3d12.dll.mgf-original" ] \
  && [ -f "$fhpfx/drive_c/windows/system32/apd12.dll.mgf-original" ] \
  && [ -f "$fhpfx/drive_c/windows/system32/ws2_32.dll.mgf-stock" ] \
  && [ "$(fhreg '"Version"="win7"')" = 1 ] && [ "$(fhreg '"Version"="winxp"')" = 0 ] \
  && [ "$(fhreg '"ForzaHorizon5.exe"="--disable-features=CalculateNativeWinOcclusion"')" = 1 ] \
  && /usr/bin/grep -q -F '[Software\\Policies\\Microsoft\\Edge\\WebView2\\AdditionalBrowserArguments] ' "$fhpfx/user.reg" \
  && say ok "fh5 on a fake prefix: both source-built proxies, the runner alias and the sign-in values installed" \
  || say FAIL "fh5: install ($(fhst), $(tail -2 "$fh/install.log" | tr '\n' ' '))"
fhdo --install > "$fh/reinstall.log" 2>&1 && [ "$(fhst)" = installed ] \
  && say ok "fh5 on a fake prefix: installing again is safe" || say FAIL "fh5: reinstall ($(fhst))"
fhdo --restore > "$fh/restore.log" 2>&1 \
  && [ "$(fhst)" = absent ] \
  && cmp -s "$fhgame/d3d12.dll" "$fh/orig-d3d12" \
  && cmp -s "$fhpfx/drive_c/windows/system32/apd12.dll" "$fh/orig-apd12" \
  && cmp -s "$fhpfx/drive_c/windows/system32/ws2_32.dll" "$fh/orig-ws2" \
  && [ ! -e "$fhrun/lib/wine/x86_64-windows/apd12.dll" ] \
  && [ ! -e "$fhrun/lib/wine/x86_64-unix/apd12.so" ] \
  && [ ! -e "$fhrun/lib/wine/x86_64-windows/ws2_o.dll" ] \
  && [ ! -e "$fhrun/lib/wine/x86_64-unix/ws2_o.so" ] \
  && [ "$(fhreg '"Version"="winxp"')" = 1 ] && [ "$(fhreg '"Version"="win7"')" = 0 ] \
  && [ "$(fhreg 'CalculateNativeWinOcclusion')" = 0 ] && [ ! -e "$fhpfx/.mgf-fh5-signin" ] \
  && say ok "fh5 on a fake prefix: originals, runner and the earlier WebView2 Version restored" \
  || say FAIL "fh5: restore ($(fhst), $(tail -2 "$fh/restore.log" | tr '\n' ' '))"

# On NotProton's runner for CrossOver Preview 41303 (Rosetta) the fix also gives the game a row of
# its own, a patch of win32u.so in memory for the Xbox sign-in, and switches it on the first time.
# Only where NotProton has its plugin host and reads "patch". A disposable HOME, and a copy of the
# launch-options editor that does not look for Steam.
fn="$W/fh5np"; fnhome="$fn/home"; fnpfx="$fn/compatdata/1551360/pfx"; fngame="$fn/game"; fnfix="$fn/fixes"
fnnp="$fnhome/Library/Application Support/notproton"; fnrun="$fnnp/runners/crossover-27.0.0.41303-fex/CrossOver"
fntool="$fnhome/Library/Application Support/Steam/compatibilitytools.d/notproton-a"
mkdir -p "$fnrun/bin" "$fnrun/lib/apple_gptk/wine/x86_64-windows" "$fnrun/lib/apple_gptk/wine/x86_64-unix" \
  "$fnrun/lib/wine/x86_64-windows" "$fnrun/lib/wine/x86_64-unix" "$fnpfx/drive_c/windows/system32" "$fngame" "$fnfix" "$fntool"
printf '#!/bin/sh\nexit 0\n' > "$fnrun/bin/wine"; chmod +x "$fnrun/bin/wine"
cp "$FIX/d3d12-fh5.dll" "$fnrun/lib/apple_gptk/wine/x86_64-windows/d3d12.dll"; touch "$fnrun/lib/apple_gptk/wine/x86_64-unix/d3d12.so"
cp "$FIX/ws2_32-fh5.dll" "$fnrun/lib/wine/x86_64-windows/ws2_32.dll"; touch "$fnrun/lib/wine/x86_64-unix/ws2_32.so"
printf 'WINE REGISTRY Version 2\n' > "$fnpfx/user.reg"; printf 'WINE REGISTRY Version 2\n' > "$fnpfx/system.reg"
printf 'fake executable\n' > "$fngame/ForzaHorizon5.exe"
printf '27.0.0.41303-fex\nCrossOver Preview 20261111 - Rosetta\n' > "$fn/compatdata/1551360/notproton-build"
for n in install-fh5-fix.sh install-fh5-netfix.sh bottles.sh pe.pl d3d12-fh5.dll ws2_32-fh5.dll fh5-THIRD-PARTY-LICENCES.md notproton-plugins.sh np-plugin-fh5.conf steam-launch-options.pl; do cp "$FIX/$n" "$fnfix/$n"; done
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$fnfix/steam-launch-options.pl"
fnvdf="$fnhome/Library/Application Support/Steam/userdata/1/config/localconfig.vdf"; mkdir -p "$(dirname "$fnvdf")"
printf '"UserLocalConfigStore"\n{\n\t"Software" { "Valve" { "Steam" { "apps" {\n\t\t"1551360"\n\t\t{\n\t\t\t"LaunchOptions"\t\t"NOTPROTON_ENV_D3DM_VENDOR_ID=4318 %%command%%"\n\t\t}\n\t} } } }\n}\n' > "$fnvdf"
fnvdf0="$(cat "$fnvdf")"; fnconf="$fnnp/plugins/mgf-1551360.conf"
fnrun_with() { printf '      split("label description section on off depends requires inject env tools type choice default apps%s group", f, " ")\n      if (names[i] == "group") next\n' "$1" > "$fntool/run"; }
fnp() { HOME="$fnhome" MGVF_BOTTLE="$fnpfx" MGVF_NOTPROTON_VERSION=1.2.8 MGVF_STEAM_RUNNING=0 /bin/bash "$fnfix/install-fh5-fix.sh" "$fngame" "$@"; }
fnst() { fnp --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half)$' | tail -1; }
# No plugin host: the fix goes in without the row.
fnrun_with " patch"
fnp --install > "$fn/install0.log" 2>&1 && [ "$(fnst)" = installed ] && [ ! -e "$fnconf" ] && [ "$(cat "$fnvdf")" = "$fnvdf0" ] \
  && say ok "fh5 in NotProton: without NotProton's plugin host the fix installs and writes no row" || say FAIL "fh5 NotProton: no host ($(fnst), $(tail -2 "$fn/install0.log" | tr '\n' ' '))"
: > "$fnnp/plugin-host.dylib"; fnrun_with ""
[ "$(fnst)" = installed ] && fnp --install > /dev/null 2>&1 && [ ! -e "$fnconf" ] \
  && say ok "fh5 in NotProton: a NotProton that does not read patch gets no row either" || say FAIL "fh5 NotProton: no patch field ($(fnst))"
fnrun_with " patch"
[ "$(fnst)" = half ] && fnp --status 2>&1 | /usr/bin/grep -q "Xbox sign-in window row is not in place" \
  && say ok "fh5 in NotProton: with the plugin host and patch, a fix without its row reads half and says why" || say FAIL "fh5 NotProton: half before the row ($(fnst))"
fnp --install > "$fn/install.log" 2>&1 && [ "$(fnst)" = installed ] \
  && /usr/bin/grep -qx '\[NOTPROTON_MGF_FH5_SIGNIN_1551360\]' "$fnconf" && /usr/bin/grep -qx 'label = Xbox sign-in window' "$fnconf" \
  && /usr/bin/grep -qx 'group = MacGameFix / Game fixes' "$fnconf" && ! /usr/bin/grep -q '^subgroup' "$fnconf" && /usr/bin/grep -qx 'apps = 1551360' "$fnconf" && /usr/bin/grep -qx 'tools = notproton-fex-rosetta\*' "$fnconf" \
  && [ "$(/usr/bin/grep -c '^patch = win32u.so/x86_64: .* e9=c3 ?? ?? ?? ??$' "$fnconf")" = 1 ] && [ "$(/usr/bin/grep -c 'MacGameFix' "$fnconf")" = 2 ] \
  && /usr/bin/grep -qF '"NOTPROTON_MGF_FH5_SIGNIN_1551360=1 NOTPROTON_ENV_D3DM_VENDOR_ID=4318 %command%"' "$fnvdf" \
  && say ok "fh5 in NotProton: the sign-in row for this game alone, in MacGameFix's group, patching win32u.so, switched on in front of the player's options" \
  || say FAIL "fh5 NotProton: the row ($(fnst), $(tail -2 "$fn/install.log" | tr '\n' ' '))"
sed -i '' 's/NOTPROTON_MGF_FH5_SIGNIN_1551360=1 //' "$fnvdf"
[ "$(fnst)" = installed ] && fnp --install > /dev/null 2>&1 && ! /usr/bin/grep -q 'NOTPROTON_MGF_FH5_SIGNIN' "$fnvdf" \
  && say ok "fh5 in NotProton: a row the player switched off stays off, and the fix still reads installed" || say FAIL "fh5 NotProton: the player's switch ($(fnst))"
MGVF_NOTPROTON_GROUPS=0 fnp --install > /dev/null 2>&1 && /usr/bin/grep -qx 'label = Xbox sign-in window (MacGameFix)' "$fnconf" && ! /usr/bin/grep -q -E '^(sub)?group' "$fnconf" \
  && [ "$(MGVF_NOTPROTON_GROUPS=0 fnp --status 2>/dev/null | tail -1)" = installed ] \
  && say ok "fh5 in NotProton: where NotProton knows no groups, the row's label names MacGameFix" || say FAIL "fh5 NotProton: ungrouped row"
fnp --install > /dev/null 2>&1
# The row says the game does not run without it (needed_for) only to a NotProton that reads the
# field: NotProton then offers the row on the game's page when it is off. For one that does not
# read it, the descriptor is what it was before the field existed.
fnconf0="$(printf '%s\n' '# MacGameFix writes this file for app 1551360 and removes it with the fix; edits do not last.' \
  '[NOTPROTON_MGF_FH5_SIGNIN_1551360]' 'label = Xbox sign-in window' 'group = MacGameFix / Game fixes' \
  'description = Keeps the Xbox sign-in page from closing the game. Leave it on' 'on = 1' 'tools = notproton-fex-rosetta*' \
  'patch = win32u.so/x86_64: 48 8d 7b 38 e8 ?? ?? ?? ?? 48 89 df 48 83 c4 08 5b 41 5e 41 5f 5d e9=c3 ?? ?? ?? ??' 'apps = 1551360')"
[ "$(cat "$fnconf")" = "$fnconf0" ] && say ok "fh5 in NotProton: a NotProton that does not read needed_for gets the row as before the field" \
  || say FAIL "fh5 NotProton: the row without needed_for ($(cat "$fnconf" | tr '\n' '|'))"
fnrun_with " patch improves needed_for"
[ "$(fnst)" = half ] && fnp --install > /dev/null 2>&1 && [ "$(fnst)" = installed ] \
  && /usr/bin/grep -qx 'needed_for = 1551360 The Xbox sign-in page closes the game.' "$fnconf" && ! /usr/bin/grep -q '^improves' "$fnconf" \
  && [ "$(/usr/bin/grep -v '^needed_for = ' "$fnconf")" = "$fnconf0" ] && ! /usr/bin/grep -q 'NOTPROTON_MGF_FH5_SIGNIN' "$fnvdf" \
  && say ok "fh5 in NotProton: a NotProton that reads needed_for is told the game needs the row; the row the player switched off stays off" \
  || say FAIL "fh5 NotProton: needed_for ($(fnst), $(cat "$fnconf" | tr '\n' '|'))"
mkdir -p "$fntool/../notproton-b"; printf '      split("label description section on off type choice default apps patch group", f, " ")\n      if (names[i] == "group") next\n' > "$fntool/../notproton-b/run"
[ "$(fnst)" = half ] && fnp --install > /dev/null 2>&1 && [ "$(fnst)" = installed ] && [ "$(cat "$fnconf")" = "$fnconf0" ] \
  && say ok "fh5 in NotProton: one NotProton in Steam that does not read needed_for, and the row is as before the field again" \
  || say FAIL "fh5 NotProton: one NotProton without needed_for ($(fnst), $(cat "$fnconf" | tr '\n' '|'))"
rm -rf "$fntool/../notproton-b"; fnrun_with " patch"
fnp --restore > "$fn/restore.log" 2>&1 && [ "$(fnst)" = absent ] && [ ! -e "$fnconf" ] && [ "$(cat "$fnvdf")" = "$fnvdf0" ] \
  && say ok "fh5 in NotProton: restored, the row gone and the launch options as they were" || say FAIL "fh5 NotProton: restore ($(fnst), $(tail -2 "$fn/restore.log" | tr '\n' ' '))"

# FH6 uses its own profile of the shared D3D12 source. It deliberately has no
# FH5 network proxy or descriptor translation, but has the same reversible
# private-alias layout.
f6="$W/fh6"; f6home="$f6/home"; f6run="$f6/home/Library/Application Support/notproton/runners/crossover-27.0.0.41073-fex/CrossOver"; f6pfx="$f6/pfx"; f6game="$f6/game"
mkdir -p "$f6home" "$f6run/bin" \
  "$f6run/lib/apple_gptk/wine/x86_64-windows" "$f6run/lib/apple_gptk/wine/x86_64-unix" \
  "$f6run/lib/wine/x86_64-windows" "$f6run/lib/wine/x86_64-unix" \
  "$f6pfx/drive_c/windows/system32" "$f6game"
printf '#!/bin/sh\nexit 0\n' > "$f6run/bin/wine"; chmod +x "$f6run/bin/wine"
cp "$FIX/d3d12-fh5.dll" "$f6run/lib/apple_gptk/wine/x86_64-windows/d3d12.dll"
touch "$f6run/lib/apple_gptk/wine/x86_64-unix/d3d12.so"
printf 'WINE REGISTRY Version 2\n' > "$f6pfx/user.reg"
printf 'WINE REGISTRY Version 2\n' > "$f6pfx/system.reg"
printf 'fake executable\n' > "$f6game/forzahorizon6.exe"
printf 'original game d3d12\n' > "$f6game/d3d12.dll"
printf 'original prefix apd12\n' > "$f6pfx/drive_c/windows/system32/apd12.dll"
cp "$f6game/d3d12.dll" "$f6/orig-d3d12"
cp "$f6pfx/drive_c/windows/system32/apd12.dll" "$f6/orig-apd12"
# Exercise the exact installer on a fake executable, substituting only the fixture hash
# in a disposable copy. Production has no environment switch to bypass the build gate.
f6fix="$f6/fixes"; mkdir -p "$f6fix"
for n in install-fh6-fix.sh fh6-runtime.sh fh6-launch-options.pl bottles.sh pe.pl d3d12-fh6.dll fh5-THIRD-PARTY-LICENCES.md notproton-rosetta-trap-boost.dylib fh6-signin.sh advapi32-fh6-26.3.0.39832.dll advapi32-fh6-27.0.0.41073.dll advapi32-fh6-27.0.0.41303.dll notproton-plugins.sh np-plugin-fh6.conf np-plugin-shared.conf mgf-engine.dylib steam-launch-options.pl; do cp "$FIX/$n" "$f6fix/$n"; done
# The prefix's own advapi32.dll stands for 41073's: that build's hash is the fake's. The
# runner's must stay as it is.
printf "CodeWeavers' advapi32\n" > "$f6pfx/drive_c/windows/system32/advapi32.dll"
printf "runner advapi32\n" > "$f6run/lib/wine/x86_64-windows/advapi32.dll"
sed -i '' "s/^    7c5e5f2f573e001eabfc39d252428dfcc79c773262b7d00b46301f53fb143dab)/    $(shasum -a 256 "$f6pfx/drive_c/windows/system32/advapi32.dll" | cut -d' ' -f1))/" "$f6fix/fh6-signin.sh"
# The separate launch-options tests exercise the running-Steam refusal. This fixture
# substitutes only process discovery so the real user's open Steam is irrelevant.
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$f6fix/fh6-launch-options.pl" "$f6fix/steam-launch-options.pl"
fixturesha="$(shasum -a 256 "$f6game/forzahorizon6.exe" | cut -d' ' -f1)"
sed -i '' "s/^GAME_SHA=.*/GAME_SHA=$fixturesha/" "$f6fix/fh6-runtime.sh"
f6modules="$f6/modules"; mkdir -p "$f6modules"
python3 "$FIX/../app/bundle-engine.py" "$FIX/../engine/modules" "$f6modules" >/dev/null
cp "$FIX/../engine/engine-modules.sh" "$f6modules/engine-modules.sh"
cp "$f6modules/engine-27.0.0.41073-x86_64-unix-ntdll.so" "$f6run/lib/wine/x86_64-unix/ntdll.so"
printf 'original runner PE\n' > "$f6run/lib/wine/x86_64-windows/ntdll.dll"
printf 'original prefix PE\n' > "$f6pfx/drive_c/windows/system32/ntdll.dll"
# FH6's own runner clone, as NotProton's Game Mode makes it.
f6clone="$f6home/Library/Application Support/notproton/launchers/2483190/runner"
mkdir -p "$(dirname "$f6clone")"; cp -R "$f6run" "$f6clone"
printf '27.0.0.41073-fex\n' > "$f6/notproton-build"
f6config="$f6home/Library/Application Support/Steam/userdata/1/config"; mkdir -p "$f6config"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "2483190" { "LaunchOptions" "PERSONAL=keep %%command%%" } } } } } }\n' > "$f6config/localconfig.vdf"
f6do() { HOME="$f6home" MGVF_MODULES="$f6modules" MGVF_CX="$f6run" MGVF_BOTTLE="$f6pfx" /bin/bash "$f6fix/install-fh6-fix.sh" "$f6game" "$@"; }
f6st() { f6do --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half)$' | tail -1; }
[ "$(f6st)" = absent ] && say ok "fh6 on a fake prefix: absent before" || say FAIL "fh6: absent before ($(f6st))"
f6do --install > "$f6/install.log" 2>&1 \
  && [ "$(f6st)" = installed ] \
  && cmp -s "$f6game/d3d12.dll" "$FIX/d3d12-fh6.dll" \
  && [ -f "$f6game/d3d12.dll.mgf-original" ] \
  && [ -f "$f6pfx/drive_c/windows/system32/apd12.dll.mgf-original" ] \
  && [ ! -e "$f6pfx/drive_c/windows/system32/ws2_32.dll.mgf-stock" ] \
  && cmp -s "$f6pfx/drive_c/windows/system32/advapi32.dll" "$FIX/advapi32-fh6-27.0.0.41073.dll" \
  && [ "$(cat "$f6pfx/drive_c/windows/system32/advapi32.dll.mgf-fh6-original")" = "CodeWeavers' advapi32" ] \
  && /usr/bin/grep -q '^"advapi32"="native,builtin"' "$f6pfx/user.reg" \
  && [ "$(cat "$f6run/lib/wine/x86_64-windows/advapi32.dll")" = "runner advapi32" ] \
  && [ "$(cat "$f6clone/lib/wine/x86_64-windows/advapi32.dll")" = "runner advapi32" ] \
  && [ ! -e "$f6game/advapi32.dll" ] \
  && say ok "fh6 on a fake prefix: source-built profile, private runner alias and sign-in fix in the prefix" \
  || say FAIL "fh6: install ($(f6st), $(tail -2 "$f6/install.log" | tr '\n' ' '))"
f6do --install > "$f6/reinstall.log" 2>&1 && [ "$(f6st)" = installed ] \
  && say ok "fh6 on a fake prefix: installing again is safe" || say FAIL "fh6: reinstall ($(f6st))"
f6do --restore > "$f6/restore.log" 2>&1 \
  && [ "$(f6st)" = absent ] \
  && cmp -s "$f6game/d3d12.dll" "$f6/orig-d3d12" \
  && cmp -s "$f6pfx/drive_c/windows/system32/apd12.dll" "$f6/orig-apd12" \
  && [ ! -e "$f6run/lib/wine/x86_64-windows/apd12.dll" ] \
  && [ ! -e "$f6run/lib/wine/x86_64-unix/apd12.so" ] \
  && [ "$(cat "$f6pfx/drive_c/windows/system32/advapi32.dll")" = "CodeWeavers' advapi32" ] \
  && [ ! -e "$f6pfx/drive_c/windows/system32/advapi32.dll.mgf-fh6-original" ] \
  && ! /usr/bin/grep -q '^"advapi32"=' "$f6pfx/user.reg" \
  && say ok "fh6 on a fake prefix: originals, runner and clone restored byte for byte" \
  || say FAIL "fh6: restore ($(f6st), $(tail -2 "$f6/restore.log" | tr '\n' ' '))"
# Another advapi32.dll in the prefix: the D3D12 fix goes in, the sign-in fix does not.
printf "another advapi32\n" > "$f6pfx/drive_c/windows/system32/advapi32.dll"
f6do --install > "$f6/other.log" 2>&1 && [ "$(f6st)" = installed ] \
  && [ "$(cat "$f6pfx/drive_c/windows/system32/advapi32.dll")" = "another advapi32" ] \
  && [ ! -e "$f6pfx/drive_c/windows/system32/advapi32.dll.mgf-fh6-original" ] \
  && ! /usr/bin/grep -q '^"advapi32"=' "$f6pfx/user.reg" \
  && /usr/bin/grep -q 'not one the Xbox sign-in fix was built for' "$f6/other.log" \
  && say ok "fh6 on a fake prefix: another prefix advapi32 gets no sign-in fix" \
  || say FAIL "fh6: other advapi32 ($(f6st), $(tail -2 "$f6/other.log" | tr '\n' ' '))"
f6do --restore > /dev/null 2>&1
# A kept "original" that is the fix's own DLL, beside the same DLL in place (seen on a real
# FH6 folder, where the game ships no d3d12.dll): installed, the copy dropped; restored, no
# d3d12.dll is left. The fixture's own d3d12.dll goes back afterwards.
cp "$FIX/d3d12-fh6.dll" "$f6game/d3d12.dll"; cp "$FIX/d3d12-fh6.dll" "$f6game/d3d12.dll.mgf-original"
f6do --install > "$f6/keptproxy.log" 2>&1 && [ "$(f6st)" = installed ] \
  && cmp -s "$f6game/d3d12.dll" "$FIX/d3d12-fh6.dll" && [ ! -e "$f6game/d3d12.dll.mgf-original" ] \
  && /usr/bin/grep -q "was this fix's own DLL, not an original" "$f6/keptproxy.log" \
  && f6do --restore > /dev/null 2>&1 && [ "$(f6st)" = absent ] && [ ! -e "$f6game/d3d12.dll" ] \
  && say ok "fh6 on a fake prefix: a kept copy of its own DLL is no original: dropped at install, nothing left at restore" \
  || say FAIL "fh6: kept copy of its own DLL ($(f6st), $(tail -2 "$f6/keptproxy.log" | tr '\n' ' '))"
cp "$f6/orig-d3d12" "$f6game/d3d12.dll"

# The priority plugin: an earlier MacGameFix build is replaced by the one beside the installer,
# a user's own is kept. The fixture's "earlier build" is a fake whose hash stands for 28315251.
f6pl="$f6home/Library/Application Support/notproton/plugins"; mkdir -p "$f6pl"
printf 'earlier MacGameFix plugin\n' > "$f6pl/notproton-rosetta-trap-boost.dylib"; printf '[x]\n' > "$f6pl/rosetta-trap-boost.conf"
sed -i '' "s/28315251485196c816b3579c90a8e9fa81a4bb7b9b61d87c4269c8972c9f4197/$(shasum -a 256 "$f6pl/notproton-rosetta-trap-boost.dylib" | cut -d' ' -f1)/" "$f6fix/fh6-runtime.sh"
f6do --install > "$f6/plugin.log" 2>&1 && cmp -s "$f6pl/notproton-rosetta-trap-boost.dylib" "$FIX/notproton-rosetta-trap-boost.dylib" \
  && [ "$(cat "$f6pl/rosetta-trap-boost.conf")" = "[x]" ] \
  && say ok "fh6 on a fake prefix: an earlier MacGameFix priority plugin is updated" \
  || say FAIL "fh6: plugin update ($(tail -2 "$f6/plugin.log" | tr '\n' ' '))"
f6do --restore > /dev/null 2>&1
printf 'my own plugin\n' > "$f6pl/notproton-rosetta-trap-boost.dylib"
f6do --install > "$f6/plugin2.log" 2>&1 && [ "$(cat "$f6pl/notproton-rosetta-trap-boost.dylib")" = "my own plugin" ] \
  && say ok "fh6 on a fake prefix: a user's own priority plugin is kept" \
  || say FAIL "fh6: own plugin ($(tail -2 "$f6/plugin2.log" | tr '\n' ' '))"
# The priority plugin's descriptor names Forza Horizon 6 as the game it improves only for a
# NotProton that reads the field; the installer's own descriptor follows what NotProton reads,
# and one that is not its own stays.
f6boost="$f6pl/rosetta-trap-boost.conf"; f6ct="$f6home/Library/Application Support/Steam/compatibilitytools.d/notproton-a"
f6boost0="$(printf '%s\n' '[NOTPROTON_ROSETTA_TRAP_BOOST]' 'label = Rosetta exception priority' 'description = Raises Rosetta exception delivery priority for the FH6 profile' \
  'section = dev' 'on = 1' 'inject = 1' 'requires = Library/Application Support/notproton/plugins/notproton-rosetta-trap-boost.dylib')"
rm -f "$f6boost"
f6do --install > /dev/null 2>&1 && [ "$(cat "$f6boost")" = "$f6boost0" ] \
  && say ok "fh6 on a fake prefix: with no NotProton that reads improves, the priority plugin's descriptor is as before the field" \
  || say FAIL "fh6: descriptor without improves ($(cat "$f6boost" | tr '\n' '|'))"
mkdir -p "$f6ct"; printf '      split("label description section on off depends requires inject env tools type choice default apps patch improves needed_for", f, " ")\n' > "$f6ct/run"
f6do --install > /dev/null 2>&1 && /usr/bin/grep -qx "improves = 2483190 Cuts the waits while Rosetta handles the game's exceptions." "$f6boost" \
  && [ "$(/usr/bin/grep -v '^improves = ' "$f6boost")" = "$f6boost0" ] \
  && say ok "fh6 on a fake prefix: a NotProton that reads improves is told the priority plugin is for this game" \
  || say FAIL "fh6: descriptor with improves ($(cat "$f6boost" | tr '\n' '|'))"
printf '      split("label description section on off depends requires inject env tools type choice default apps patch", f, " ")\n' > "$f6ct/run"
f6do --install > /dev/null 2>&1 && [ "$(cat "$f6boost")" = "$f6boost0" ] \
  && say ok "fh6 on a fake prefix: a NotProton that no longer reads improves gets the descriptor without it" \
  || say FAIL "fh6: descriptor back without improves ($(cat "$f6boost" | tr '\n' '|'))"
printf '      split("label description section on off depends requires inject env tools type choice default apps patch improves needed_for", f, " ")\n' > "$f6ct/run"
printf '[x]\n' > "$f6boost"
f6do --install > /dev/null 2>&1 && [ "$(cat "$f6boost")" = "[x]" ] \
  && say ok "fh6 on a fake prefix: a descriptor that is not the installer's own is not given the line" \
  || say FAIL "fh6: a user's descriptor ($(cat "$f6boost" | tr '\n' '|'))"
rm -rf "$f6home/Library/Application Support/Steam/compatibilitytools.d"; printf 'my own plugin\n' > "$f6pl/notproton-rosetta-trap-boost.dylib"
# FH6's runner clone holding an earlier ntdll.so, as new Wine modules in the runner leave it.
# While the clone is the runner's current copy it is looked at: the fix reads half and an
# install refuses what it did not put there. Once NotProton is going to make the clone again
# (its .stamp no longer says what the runner's lib/wine looks like) it is not looked at.
f6cso="$f6clone/lib/wine/x86_64-unix/ntdll.so"
cp "$f6cso" "$f6/clone-ntdll.so"; printf 'stock\n' > "$f6cso.mgf-fh6-original"; printf 'an earlier build\n' > "$f6cso"
[ "$(f6st)" = half ] && ! f6do --install > "$f6/clone1.log" 2>&1 && /usr/bin/grep -q 'changed outside MacGameFix' "$f6/clone1.log" \
  && say ok "fh6 runner clone: an earlier ntdll.so in a clone with no stamp reads half and is not replaced" \
  || say FAIL "fh6 clone: no stamp ($(f6st), $(tail -1 "$f6/clone1.log"))"
printf '%s/lib/wine 1 1.000000000\n' "$f6run" > "$f6clone/.stamp"
[ "$(f6st)" = installed ] && f6do --install > "$f6/clone2.log" 2>&1 && [ "$(f6st)" = installed ] \
  && [ "$(cat "$f6cso")" = "an earlier build" ] \
  && say ok "fh6 runner clone: one NotProton will make again is not looked at: installed, and an install goes through" \
  || say FAIL "fh6 clone: stale stamp ($(f6st), $(tail -1 "$f6/clone2.log"))"
stat -f '%N %i %Fm' "$f6run/lib/wine" "$f6run/lib/wine"/* > "$f6clone/.stamp"
[ "$(f6st)" = half ] \
  && say ok "fh6 runner clone: one whose stamp is the runner's is looked at" \
  || say FAIL "fh6 clone: current stamp ($(f6st))"
printf '/another/runner/lib/wine 1 1.000000000\n' > "$f6clone/.stamp"
[ "$(f6st)" = half ] \
  && say ok "fh6 runner clone: a stamp about another runner changes nothing" \
  || say FAIL "fh6 clone: another runner's stamp ($(f6st))"
rm -f "$f6clone/.stamp" "$f6cso.mgf-fh6-original"; cp "$f6/clone-ntdll.so" "$f6cso"
f6do --restore > /dev/null 2>&1

# 41303 with engine patch 0025: the chain's switches are in ntdll.dll, so the launch options
# need only the plugin's, and the build shipped before it (6664770a) counts as MacGameFix's own
# when an update replaces it. The real DLLs: the new one from the modules, the old from git.
f6n="$W/fh6-41303"; mkdir -p "$f6n/m"
cp "$FIX/../engine/modules/27.0.0.41303/x86_64-windows/ntdll.dll" "$f6n/m/engine-27.0.0.41303-x86_64-windows-ntdll.dll"
git -C "$FIX/.." show 6373a11:engine/modules/27.0.0.41303/x86_64-windows/ntdll.dll > "$f6n/old.dll" 2>/dev/null
git -C "$FIX/.." show 5e74061:engine/modules/27.0.0.41303/x86_64-windows/ntdll.dll > "$f6n/0025.dll" 2>/dev/null
# The modules built again (0038 to 0041) are other files with the same ntdll.dll source: the one
# shipped before them (fe379ae0, #117) is replaced like the others, and the chain still reads as in the DLL.
git -C "$FIX/.." show 545bc09:engine/modules/27.0.0.41303/x86_64-windows/ntdll.dll > "$f6n/2xko.dll" 2>/dev/null
printf 'not ours\n' > "$f6n/other.dll"
f6n_run() {
  HERE="$f6n" MGVF_MODULES="$f6n/m" RUNNER="$1" /bin/bash -c '. "$0"; '"$2" "$FIX/fh6-runtime.sh"
}
if [ "$(shasum -a 256 "$f6n/old.dll" | cut -c1-8)" != 6664770a ]; then
  say ok "fh6 on 41303: skipped, the shipped 6664770a is not in this checkout's history"
elif [ "$(f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver fh6_chain_in_ntdll)" = 1 ] \
  && [ "$(f6n_run /x/runners/crossover-27.0.0.41073-fex/CrossOver fh6_chain_in_ntdll)" = 0 ] \
  && f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_known '$f6n/old.dll'" \
  && f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_known '$f6n/0025.dll'" \
  && { [ "$(shasum -a 256 "$f6n/2xko.dll" | cut -c1-8)" != fe379ae0 ] || cmp -s "$f6n/2xko.dll" "$f6n/m/engine-27.0.0.41303-x86_64-windows-ntdll.dll" \
       || f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_known '$f6n/2xko.dll'"; } \
  && ! f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_ok '$f6n/0025.dll'" \
  && ! f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_ok '$f6n/old.dll'" \
  && ! f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "fh6_pe_known '$f6n/other.dll'" \
  && ! f6n_run /x/runners/crossover-27.0.0.41073-fex/CrossOver "fh6_pe_known '$f6n/old.dll'"; then
  say ok "fh6 on 41303: the modules' ntdll drops the chain variables, and the builds before it are updated, not refused"
else
  say FAIL "fh6 on 41303: chain-in-ntdll detection or the previous build's acceptance"
fi
# 41303: the game's runner copy loses an ntdll.so of ours an earlier install put in, the kept one back,
# or, with none kept, the runner's own; one that is not ours stays. The fix asks for none.
f6u="$W/fh6-unix"; mkdir -p "$f6u/clone" "$f6u/runner"
printf 'ours\n' > "$f6n/m/engine-27.0.0.41303-x86_64-unix-ntdll.so"
cp "$f6n/m/engine-27.0.0.41303-x86_64-unix-ntdll.so" "$f6u/clone/ntdll.so"; printf 'kept\n' > "$f6u/clone/ntdll.so.mgf-fh6-original"
printf 'runner own\n' > "$f6u/runner/ntdll.so"
cp "$f6n/m/engine-27.0.0.41303-x86_64-unix-ntdll.so" "$f6u/clone/second.so"
printf 'someone else\n' > "$f6u/clone/other.so"
f6u_run() { f6n_run /x/runners/crossover-27.0.0.41303-fex/CrossOver "$1"; }
if [ "$(f6u_run 'echo $FH6_OWN_UNIX')" = 0 ] \
   && f6u_run "fh6_unix_out '$f6u/clone/ntdll.so' '$f6u/runner/ntdll.so'" && [ "$(cat "$f6u/clone/ntdll.so")" = kept ] && [ ! -e "$f6u/clone/ntdll.so.mgf-fh6-original" ] \
   && f6u_run "fh6_unix_out '$f6u/clone/second.so' '$f6u/runner/ntdll.so'" && [ "$(cat "$f6u/clone/second.so")" = "runner own" ] \
   && f6u_run "fh6_unix_out '$f6u/clone/other.so' '$f6u/runner/ntdll.so'" && [ "$(cat "$f6u/clone/other.so")" = "someone else" ] \
   && [ "$(f6n_run /x/runners/crossover-27.0.0.41073-fex/CrossOver 'echo $FH6_OWN_UNIX')" = 1 ]; then
  say ok "fh6 on 41303: an ntdll.so of ours in the game's runner copy goes, the kept or the runner's own back; 41073 keeps its pair"
else
  say FAIL "fh6 on 41303: the runner copy's ntdll.so ($(cat "$f6u/clone/ntdll.so" "$f6u/clone/second.so" "$f6u/clone/other.so" 2>&1 | tr '\n' ' '))"
fi

# 41303 on Rosetta, with NotProton's plugin host: FH6 also takes the shared "Engine fixes" row
# (0021 and 0026 from mgf-engine.dylib), its switch going into the launch options after FH6's
# own variables, and out again before them. On 41073 (above) the row is not part of the fix.
[ ! -e "$f6home/Library/Application Support/notproton/plugins/mgf-2483190.uses" ] \
  && say ok "fh6 on 41073: no Engine fixes row" || say FAIL "fh6 on 41073: a row was written"
f6r="$W/fh6-rows"; f6rhome="$f6r/home"; f6rnp="$f6rhome/Library/Application Support/notproton"; f6rplug="$f6rnp/plugins"
f6rrun="$f6rnp/runners/crossover-27.0.0.41303-fex/CrossOver"; f6rpfx="$f6r/pfx"; f6rfix="$f6r/fixes"
mkdir -p "$f6rrun" "$f6rfix" "$f6r/game"
cp -R "$f6run/" "$f6rrun/"; cp -R "$f6pfx" "$f6rpfx"; cp "$f6game/forzahorizon6.exe" "$f6r/game/"
# On 41303 the runner's ntdll.so is CodeWeavers' (the Wine modules leave it): FH6's part comes from the row.
printf "CodeWeavers' x86_64-unix/ntdll.so wine-11.21\n" > "$f6rrun/lib/wine/x86_64-unix/ntdll.so"
# Its FEX side too, which FH6 has no use for: the install puts none of the improvement's modules there.
mkdir -p "$f6rrun/lib/wine/aarch64-unix" "$f6rrun/lib/wine/aarch64-windows"
printf "CodeWeavers' aarch64-unix/ntdll.so wine-11.21\n" > "$f6rrun/lib/wine/aarch64-unix/ntdll.so"
echo host > "$f6rnp/plugin-host.dylib"
printf '27.0.0.41303-fex\nCrossOver 2026 11 11-ARM64 - Rosetta\n' > "$f6r/notproton-build"
for n in install-fh6-fix.sh fh6-runtime.sh fh6-launch-options.pl bottles.sh pe.pl d3d12-fh6.dll fh5-THIRD-PARTY-LICENCES.md notproton-rosetta-trap-boost.dylib fh6-signin.sh advapi32-fh6-26.3.0.39832.dll advapi32-fh6-27.0.0.41073.dll advapi32-fh6-27.0.0.41303.dll notproton-plugins.sh np-plugin-fh6.conf np-plugin-shared.conf mgf-engine.dylib steam-launch-options.pl; do cp "$FIX/$n" "$f6rfix/$n"; done
# The prefix's advapi32.dll stands for 41303's here.
sed -i '' "s/^    8790c1b25ce4805c6f5fe1f5f103ea51c9439869c04297763652f2970b94febc)/    $(shasum -a 256 "$f6rpfx/drive_c/windows/system32/advapi32.dll" | cut -d' ' -f1))/" "$f6rfix/fh6-signin.sh"
sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$f6rfix/fh6-launch-options.pl" "$f6rfix/steam-launch-options.pl"
sed -i '' "s/^GAME_SHA=.*/GAME_SHA=$fixturesha/" "$f6rfix/fh6-runtime.sh"
f6rconfig="$f6rhome/Library/Application Support/Steam/userdata/1/config"; mkdir -p "$f6rconfig"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "2483190" { "LaunchOptions" "PERSONAL=keep %%command%%" } } } } } }\n' > "$f6rconfig/localconfig.vdf"
f6rdo() { HOME="$f6rhome" MGVF_MODULES="$f6modules" MGVF_CX="$f6rrun" MGVF_BOTTLE="$f6rpfx" MGVF_NOTPROTON_VERSION=1.2.7 MGVF_STEAM_RUNNING=0 /bin/bash "$f6rfix/install-fh6-fix.sh" "$f6r/game" "$@"; }
f6rst() { f6rdo --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half)$' | tail -1; }
f6ropts() { /usr/bin/perl -ne 'print "$1\n" if /"LaunchOptions" "([^"]*)"/' "$f6rconfig/localconfig.vdf"; }
[ "$(f6rst)" = absent ] && say ok "fh6 on 41303 with the plugin host: absent before" || say FAIL "fh6 rows: absent before ($(f6rst))"
f6rdo --install > "$f6r/install.log" 2>&1 && [ "$(f6rst)" = installed ] \
  && cmp -s "$f6rplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
  && [ -f "$f6rplug/mgf-2483190.uses" ] && /usr/bin/grep -q '^# shared rows: NOTPROTON_MGF_ENGINE$' "$f6rplug/mgf-2483190.uses" \
  && [ "$(/usr/bin/grep -c '^\[' "$f6rplug/mgf-shared.conf")" = 1 ] \
  && /usr/bin/grep -q '^\[NOTPROTON_MGF_ENGINE\]$' "$f6rplug/mgf-shared.conf" \
  && /usr/bin/grep -qxF '[NOTPROTON_MGF_ENGINE]' "$f6rplug/mgf-shared.conf" && ! /usr/bin/grep -q '^apps' "$f6rplug/mgf-shared.conf" \
  && f6ropts | /usr/bin/grep -q '^NOTPROTON_MGF_ENGINE=1 .*NOTPROTON_ROSETTA_TRAP_BOOST=1 .*PERSONAL=keep %command%$' \
  && say ok "fh6 on 41303 with the plugin host: the shared Engine fixes row, its library and its switch go in with the fix" \
  || say FAIL "fh6 rows: install ($(f6rst), $(f6ropts), $(tail -3 "$f6r/install.log" | tr '\n' ' '))"
[ "$(cat "$f6rrun/lib/wine/aarch64-unix/ntdll.so")" = "CodeWeavers' aarch64-unix/ntdll.so wine-11.21" ] \
  && [ -z "$(ls -A "$f6rrun/lib/wine/aarch64-windows")" ] \
  && say ok "fh6 on 41303: nothing of the Rosetta improvement goes into the runner, on the FEX side either" \
  || say FAIL "fh6 on 41303: the improvement went into the runner ($(ls "$f6rrun/lib/wine/aarch64-windows" | tr '\n' ' '))"
rm -f "$f6rplug/mgf-shared.conf"
f6rwhy="$(f6rdo --status 2>&1)"
[ "$(f6rst)" = half ] && case "$f6rwhy" in *"Engine fixes row"*) true ;; *) false ;; esac \
  && say ok "fh6 on 41303: the shared row missing reads half, and says so" || say FAIL "fh6 rows: missing row ($(f6rst))"
f6rdo --install > "$f6r/install2.log" 2>&1 && [ "$(f6rst)" = installed ] \
  && [ "$(f6ropts | /usr/bin/grep -o 'NOTPROTON_MGF_ENGINE=1' | /usr/bin/grep -c .)" = 1 ] \
  && say ok "fh6 on 41303: installing again puts the row back, the switch once" || say FAIL "fh6 rows: reinstall ($(f6rst), $(f6ropts))"
# 41303 leaves ntdll.dll to NotProton (the exception chain is the proxy's): the install puts none in, and
# one an earlier install put in the prefix goes, the kept one back in its place.
f6rsys="$f6rpfx/drive_c/windows/system32"
! cmp -s "$f6rsys/ntdll.dll" "$f6modules/engine-27.0.0.41303-x86_64-windows-ntdll.dll" && ! cmp -s "$f6rrun/lib/wine/x86_64-windows/ntdll.dll" "$f6modules/engine-27.0.0.41303-x86_64-windows-ntdll.dll" \
  && say ok "fh6 on 41303: no ntdll.dll of MacGameFix's in the runner or the prefix" || say FAIL "fh6 on 41303: an ntdll.dll of ours went in"
cp "$f6modules/engine-27.0.0.41303-x86_64-windows-ntdll.dll" "$f6rsys/ntdll.dll"; printf "NotProton's ntdll.dll\n" > "$f6rsys/ntdll.dll.mgf-fh6-original"
[ "$(f6rst)" = half ] && say ok "fh6 on 41303: the ntdll.dll an earlier install put in the prefix reads half" || say FAIL "fh6 on 41303: earlier ntdll.dll ($(f6rst))"
f6rdo --install > "$f6r/install-pe.log" 2>&1 && [ "$(cat "$f6rsys/ntdll.dll")" = "NotProton's ntdll.dll" ] && [ ! -e "$f6rsys/ntdll.dll.mgf-fh6-original" ] && [ "$(f6rst)" = installed ] \
  && say ok "fh6 on 41303: installing again puts the kept ntdll.dll back in the prefix" || say FAIL "fh6 on 41303: ntdll.dll out ($(f6rst), $(tail -2 "$f6r/install-pe.log" | tr '\n' ' '))"
# The engine library #156 shipped is replaced like our own; another is refused.
if git -C "$FIX/.." show 5ac1817:fixes/mgf-engine.dylib > "$f6rplug/mgf-engine.dylib" 2>/dev/null; then
  f6rdo --install > "$f6r/install3.log" 2>&1 && cmp -s "$f6rplug/mgf-engine.dylib" "$FIX/mgf-engine.dylib" \
    && say ok "fh6 on 41303: the engine library an earlier MacGameFix shipped is updated" \
    || say FAIL "fh6 rows: earlier library ($(tail -2 "$f6r/install3.log" | tr '\n' ' '))"
else say ok "fh6 on 41303: skipped, #156's engine library is not in this checkout's history"; fi
printf 'not ours\n' > "$f6rplug/mgf-engine.dylib"
! f6rdo --install > "$f6r/install4.log" 2>&1 && /usr/bin/grep -q 'is a different library' "$f6r/install4.log" \
  && say ok "fh6 on 41303: an engine library that is not ours is refused" || say FAIL "fh6 rows: other library ($(tail -2 "$f6r/install4.log" | tr '\n' ' '))"
cp "$FIX/mgf-engine.dylib" "$f6rplug/mgf-engine.dylib"
mv "$f6rnp/plugin-host.dylib" "$f6rnp/plugin-host.away"
[ "$(f6rst)" = installed ] && say ok "fh6 on 41303 without the plugin host: the row is not part of the fix" || say FAIL "fh6 rows: no host ($(f6rst))"
mv "$f6rnp/plugin-host.away" "$f6rnp/plugin-host.dylib"
f6rdo --restore > "$f6r/restore.log" 2>&1 \
  && [ ! -e "$f6rplug/mgf-2483190.uses" ] && [ ! -e "$f6rplug/mgf-shared.conf" ] && [ ! -e "$f6rplug/mgf-engine.dylib" ] \
  && ! f6ropts | /usr/bin/grep -q NOTPROTON_MGF_ENGINE \
  && say ok "fh6 on 41303: restore takes the row, its library and its switch out" \
  || say FAIL "fh6 rows: restore ($(f6rst), $(f6ropts), $(tail -3 "$f6r/restore.log" | tr '\n' ' '))"

# A CrossOver bottle: only the Xbox sign-in fix, nothing in CrossOver itself.
f6cx="$f6/cx/CrossOver.app/Contents/SharedSupport/CrossOver"; f6b="$f6/bottle"; mkdir -p "$f6cx/bin" "$f6cx/lib/wine/x86_64-windows" "$f6b/drive_c/windows/system32" "$f6/cxgame"
printf '#!/bin/sh\nexit 0\n' > "$f6cx/bin/wine"; chmod +x "$f6cx/bin/wine"
printf 'cx advapi32\n' > "$f6cx/lib/wine/x86_64-windows/advapi32.dll"
printf 'WINE REGISTRY Version 2\n' > "$f6b/user.reg"; printf 'WINE REGISTRY Version 2\n' > "$f6b/system.reg"
printf "CodeWeavers' advapi32\n" > "$f6b/drive_c/windows/system32/advapi32.dll"
printf 'any build\n' > "$f6/cxgame/forzahorizon6.exe"
f6bdo() { HOME="$f6home" MGVF_CX="$f6cx" MGVF_BOTTLE="$f6b" /bin/bash "$f6fix/install-fh6-fix.sh" "$f6/cxgame" "$@"; }
f6bst() { f6bdo --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|half|norecipe)$' | tail -1; }
[ "$(f6bst)" = absent ] && say ok "fh6 in a CrossOver bottle: absent before" || say FAIL "fh6 bottle: absent before ($(f6bst))"
f6bdo --install > "$f6/bottle.log" 2>&1 && [ "$(f6bst)" = installed ] \
  && cmp -s "$f6b/drive_c/windows/system32/advapi32.dll" "$FIX/advapi32-fh6-27.0.0.41073.dll" \
  && /usr/bin/grep -q '^"advapi32"="native,builtin"' "$f6b/user.reg" \
  && ! /usr/bin/grep -q 'd3d12' "$f6b/user.reg" && [ ! -e "$f6/cxgame/d3d12.dll" ] \
  && [ "$(cat "$f6cx/lib/wine/x86_64-windows/advapi32.dll")" = "cx advapi32" ] \
  && /usr/bin/grep -q 'only the Xbox sign-in fix' "$f6/bottle.log" \
  && say ok "fh6 in a CrossOver bottle: the sign-in fix alone, CrossOver untouched" \
  || say FAIL "fh6 bottle: install ($(f6bst), $(tail -2 "$f6/bottle.log" | tr '\n' ' '))"
# An update of the bottle puts Wine's copy back: half, and installing again mends it.
printf "CodeWeavers' advapi32\n" > "$f6b/drive_c/windows/system32/advapi32.dll"
[ "$(f6bst)" = half ] && f6bdo --install >/dev/null 2>&1 && [ "$(f6bst)" = installed ] \
  && say ok "fh6 in a CrossOver bottle: a bottle update shows half, installing again mends it" \
  || say FAIL "fh6 bottle: after an update ($(f6bst))"
f6bdo --restore > "$f6/bottle-restore.log" 2>&1 && [ "$(f6bst)" = absent ] \
  && [ "$(cat "$f6b/drive_c/windows/system32/advapi32.dll")" = "CodeWeavers' advapi32" ] \
  && [ ! -e "$f6b/drive_c/windows/system32/advapi32.dll.mgf-fh6-original" ] \
  && ! /usr/bin/grep -q '^"advapi32"=' "$f6b/user.reg" \
  && say ok "fh6 in a CrossOver bottle: restored byte for byte" \
  || say FAIL "fh6 bottle: restore ($(f6bst), $(tail -2 "$f6/bottle-restore.log" | tr '\n' ' '))"
printf "another advapi32\n" > "$f6b/drive_c/windows/system32/advapi32.dll"
[ "$(f6bst)" = norecipe ] && say ok "fh6 in a CrossOver bottle: another advapi32 has no recipe" || say FAIL "fh6 bottle: other advapi32 ($(f6bst))"

# Ori and the Will of the Wisps' shaders, compiled ahead of time: macprotips'
# programs are fetched, the game's runner draws their list, and what comes out
# goes where the game reads it. None of that is here, so the test makes all of
# it: a release zip of its own (a reader that lists what a file in the game
# folder names, a list of combinations), a runner whose loader writes the draws
# it was asked for and a cache as D3DMetal and Metal would, and a cache folder.
# Its whole life: refused with no runner, with a download that is not the pinned
# one, while a process holds one of the game's cache files and for a game the
# list was not recorded from, each with nothing changed; installed, the four
# numbered files and D3DMetal's folder replaced and nothing left behind; a
# loader that stops half way started again after its last draw; broken once the
# game or D3DMetal is another; forgotten, with the compiled shaders left.
o="$W/ori"; g="$o/steamapps/common/Ori and the Will of the Wisps"; mkdir -p "$g"; touch "$g/oriwotw.exe"
printf '"AppState"\n{\n\t"appid"\t\t"1057090"\n\t"buildid"\t\t"100"\n}\n' > "$o/steamapps/appmanifest_1057090.acf"
for n in 1 2 3 4 5 6; do echo "s$n"; done > "$g/shaders.txt"
orun="$o/runner"; oload="$orun/lib/wine/x86_64-unix/wine.app/Contents/MacOS/wine"
mkdir -p "$(dirname "$oload")" "$orun/bin" "$orun/share/crossover/data" "$orun/lib/apple_gptk/external/D3DMetal.framework/Resources"
printf '"ProductVersion" = "27.0.0.1"\n' > "$orun/share/crossover/data/CrossOver.conf"
echo "D3DMetal" > "$orun/lib/apple_gptk/external/D3DMetal.framework/D3DMetal"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>4.0</string></dict></plist>\n' \
  > "$orun/lib/apple_gptk/external/D3DMetal.framework/Resources/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$orun/bin/wineserver"
# The loader: <exe> <shaders> --plan <list> --skipdraws <n> --sleep <ms>, paths as Z:\... .
cat > "$oload" <<'SH'
#!/bin/bash
unix() { printf '%s' "${1#Z:}" | tr '\\' '/'; }
exe="$(unix "$1")"; plan="$(unix "$4")"; skip="$6"; root="$CX_ROOT"
echo "$skip" >> "$root/skips.txt"
lines="$(wc -l < "$plan" | tr -d ' ')"
stop="$lines"; [ -f "$root/stop-half-way" ] && { stop=$((lines / 2)); rm -f "$root/stop-half-way"; }
out="$MGVF_ORI_CACHES/d3dm/$(basename "$exe")/shaders.cache"
mkdir -p "$out/1_2" "$out/MTLGPUFamilyTest"
i="$skip"; while [ "$i" -lt "$stop" ]; do echo "DRAW $i" >> warm.log; echo "f$i" >> "$out/1_2/functions.data"; i=$((i + 1)); done
echo "list" > "$out/1_2/functions.list"; echo "pipelines of $(basename "$exe")" > "$out/MTLGPUFamilyTest/pipeline_cache.bin"
[ "$stop" = "$lines" ] || exit 1
echo "SUMMARY $lines" >> warm.log
SH
chmod 755 "$oload" "$orun/bin/wineserver"
mkdir -p "$o/zip/Test.app/Contents/Resources"
printf '#!/bin/sh\nmkdir -p "$2" && while read -r n; do : > "$2/$n.dxbc"; done < "$1/shaders.txt"\n' > "$o/zip/Test.app/Contents/Resources/extract"
chmod 755 "$o/zip/Test.app/Contents/Resources/extract"
echo "not a program" > "$o/zip/Test.app/Contents/Resources/oriwarm_t.exe"
for n in 1 2 3 4 5; do echo "s$n s6 a/D/b/c/1 l 16"; echo "s$n - a/D/b/c/1 l 16"; done | gzip > "$o/zip/Test.app/Contents/Resources/plan.txt.gz"
(cd "$o/zip" && ditto -c -k --keepParent Test.app "$o/tools.zip")
osha="$(shasum -a 256 "$o/tools.zip" | cut -d' ' -f1)"
oc="$o/caches"; om="$oc/com.notproton.launcher.1057090/com.apple.metal/1_2"; mkdir -p "$om" "$oc/d3dm/oriwotw.exe/shaders.cache/MTLGPUFamilyTest"
for n in "" 1 2 3; do echo "the game's own $n" > "$om/functions$n.data"; echo "l$n" > "$om/functions$n.list"; done
echo "the game's own pipelines" > "$oc/d3dm/oriwotw.exe/shaders.cache/MTLGPUFamilyTest/pipeline_cache.bin"
ori() { MGVF_ORI_RUNNER="$orun" MGVF_ORI_CACHES="$oc" MGVF_ORI_STORE="$o/store" MGVF_ORI_URL="file://$o/tools.zip" \
  MGVF_ORI_SHA256="${OSHA:-$osha}" MGVF_ORI_POLL=1 /bin/bash "$FIX/install-ori-shaders.sh" "$g" "$@"; }
orist() { ori --status 2>/dev/null | /usr/bin/grep -E '^(installed|absent|broken)$' | head -1; }
oriown() { [ "$(cat "$om/functions2.data")" = "the game's own 2" ] && [ "$(cat "$oc/d3dm/oriwotw.exe/shaders.cache/MTLGPUFamilyTest/pipeline_cache.bin")" = "the game's own pipelines" ] && [ ! -e "$g/mgf-shaders-compiled.txt" ]; }
[ "$(orist)" = absent ] && say ok "ori shaders: absent before" || say FAIL "ori shaders: absent before ($(orist))"
! MGVF_ORI_RUNNER="$o/none" MGVF_ORI_CACHES="$oc" MGVF_ORI_STORE="$o/store" /bin/bash "$FIX/install-ori-shaders.sh" "$g" > "$o/norunner.log" 2>&1 \
  && /usr/bin/grep -q 'Start the game once with NotProton' "$o/norunner.log" && oriown \
  && say ok "ori shaders: refused where NotProton never started the game, nothing changed" || say FAIL "ori shaders: no runner ($(tail -1 "$o/norunner.log"))"
! OSHA="$(printf '%064d' 0)" ori > "$o/sha.log" 2>&1 && /usr/bin/grep -q 'not the expected file' "$o/sha.log" && oriown && [ ! -d "$o/store/tools-000000000000" ] \
  && say ok "ori shaders: a download that is not the pinned one is refused, nothing changed or kept" || say FAIL "ori shaders: wrong download ($(tail -1 "$o/sha.log"))"
/usr/bin/perl -e 'use Fcntl qw(:flock); open(my $f, "<", $ARGV[0]) or die; flock($f, LOCK_EX) or die; open(my $r, ">", $ARGV[1]); close($r); sleep 120' "$om/functions2.data" "$o/held" &
oholder=$!; while [ ! -e "$o/held" ]; do sleep 0.1; done
! ori > "$o/held.log" 2>&1 && /usr/bin/grep -q 'is running' "$o/held.log" && oriown \
  && say ok "ori shaders: refused while a process holds one of the game's cache files" || say FAIL "ori shaders: held ($(tail -1 "$o/held.log"))"
kill "$oholder" 2>/dev/null; wait "$oholder" 2>/dev/null
echo "s1" > "$g/shaders.txt"
! ori > "$o/version.log" 2>&1 && /usr/bin/grep -q 'not the one the list was recorded from' "$o/version.log" && oriown \
  && say ok "ori shaders: refused for a game the list was not recorded from, nothing changed" || say FAIL "ori shaders: other version ($(tail -1 "$o/version.log"))"
for n in 1 2 3 4 5 6; do echo "s$n"; done > "$g/shaders.txt"
ori > "$o/install.log" 2>&1; ocode=$?
osame=yes; for n in "" 1 2 3; do cmp -s "$om/functions$n.data" "$om/functions.data" && cmp -s "$om/functions$n.list" "$om/functions.list" || osame=no; done
[ "$ocode" = 0 ] && [ "$(orist)" = installed ] && [ "$osame" = yes ] && [ "$(wc -l < "$om/functions.data" | tr -d ' ')" = 10 ] \
  && [ "$(cat "$oc/d3dm/oriwotw.exe/shaders.cache/MTLGPUFamilyTest/pipeline_cache.bin")" = "pipelines of mgf-oriwarm.exe" ] \
  && /usr/bin/grep -q '^combinations = 10$' "$g/mgf-shaders-compiled.txt" \
  && say ok "ori shaders: installed, the four numbered files the same and D3DMetal's folder the new one" \
  || say FAIL "ori shaders: install ($ocode, $(orist), $(tail -2 "$o/install.log" | tr '\n' ' '))"
[ ! -e "$oc/d3dm/mgf-oriwarm.exe" ] && [ ! -e "$o/store/work" ] && [ -z "$(find "$oc" -name '*.mgf-*')" ] && [ -x "$o/store/tools-${osha:0:12}/extract" ] \
  && say ok "ori shaders: nothing left behind but the fetched programs" || say FAIL "ori shaders: left behind ($(find "$oc" "$o/store" -maxdepth 3 | tail -5 | tr '\n' ' '))"
: > "$orun/skips.txt"; touch "$orun/stop-half-way"
ori > "$o/again.log" 2>&1 && [ "$(tr '\n' ' ' < "$orun/skips.txt")" = "0 5 " ] && [ "$(wc -l < "$om/functions3.data" | tr -d ' ')" = 10 ] && [ "$(orist)" = installed ] \
  && say ok "ori shaders: a loader that stops half way is started again after its last draw" || say FAIL "ori shaders: restart ($(tr '\n' ' ' < "$orun/skips.txt"), $(tail -1 "$o/again.log"))"
sed -i '' 's/"100"/"101"/' "$o/steamapps/appmanifest_1057090.acf"
[ "$(orist)" = broken ] && ori > /dev/null 2>&1 && [ "$(orist)" = installed ] \
  && say ok "ori shaders: a game update shows broken, installing again compiles for it" || say FAIL "ori shaders: game update ($(orist))"
echo "another" >> "$orun/lib/apple_gptk/external/D3DMetal.framework/D3DMetal"
[ "$(orist)" = broken ] && say ok "ori shaders: another D3DMetal shows broken" || say FAIL "ori shaders: other D3DMetal ($(orist))"
ori > /dev/null 2>&1
last="$(ori --restore 2>/dev/null | head -1)"
[ "${last%% *}" = restored ] && [ "$(orist)" = absent ] && [ ! -e "$o/store" ] && [ "$(wc -l < "$om/functions.data" | tr -d ' ')" = 10 ] \
  && say ok "ori shaders: forgotten, the fetched programs gone and the compiled shaders left" || say FAIL "ori shaders: restore ($last, $(orist))"

if [ "$fails" = 0 ]; then echo "==> every installer: installed, outdated, updated, restored; Cyberpunk 2077's app patched, signed and put back"; else echo "==> $fails failed"; exit 1; fi
