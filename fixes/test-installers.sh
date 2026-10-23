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

if [ "$fails" = 0 ]; then echo "==> every installer: installed, outdated, updated, restored; Cyberpunk 2077's app patched, signed and put back"; else echo "==> $fails failed"; exit 1; fi
