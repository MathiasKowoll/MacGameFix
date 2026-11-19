#!/usr/bin/env bash
#
# Compile Ori and the Will of the Wisps' shaders ahead of time, for NotProton.
#
# This is macprotips' Ori Shader Warmer (github.com/macprotips/ori-shader-warmer),
# run with the runner NotProton starts the game from, and its result put where
# a game started by NotProton reads it.
#
#     install-ori-shaders.sh <game folder>            compile, or compile again after an update
#     install-ori-shaders.sh <game folder> --status   report
#     install-ori-shaders.sh <game folder> --restore  forget it was done
#
# WHAT IT FIXES. The game hitches whenever something new comes on screen.
# Direct3D 11 does not tell the driver ahead of time which shaders a game will
# draw with, nor with which blend, depth and vertex settings, so D3DMetal builds
# the Metal pipeline for each combination at the first draw that uses it.
# macprotips recorded about 90,000 combinations from the game, across its
# scenes and boss fights; their tool reads the shaders out of the player's own
# copy of the game and draws every combination once, so that D3DMetal and Metal
# keep them compiled.
#
# Measured on 2026-11-18 (NotProton, CrossOver Preview 27.0.0.41303's Wine under
# Rosetta, D3DMetal 4.0b3, M4 Max, game build 5845748), read from Metal's own
# record of the game's process:
#   - before: 1,123 shaders compiled in 222 seconds of play, and 70 of those
#     seconds held a frame more than 50 ms late, 60 of them seconds in which a
#     shader was compiled;
#   - after: 6 compiled and 1,092 taken from the cache in 158 seconds, 21
#     seconds with a frame that late, 2 of them compiling.
# Compiling took 272 seconds on that Mac; macprotips say 10 to 30 minutes
# depending on the Mac.
#
# WHERE THE RESULT GOES. D3DMetal keeps its own cache under the executable's
# name (<user cache>/d3dm/oriwotw.exe), and Metal keeps the compiled functions
# under the bundle the process runs from. NotProton starts each game from a
# bundle of its own, and the running game was seen (lsof) holding
# <user cache>/com.notproton.launcher.1057090/com.apple.metal/<GPU>/functionsN.data,
# so that is where the functions are put, in all four numbered files: a process
# takes whichever is free. Nothing another game uses is replaced.
#
# NOTHING OF THEIRS SHIPS WITH MACGAMEFIX. Their release is fetched once from
# their own repository, pinned by sha256, and kept in the user's cache folder:
# the program that reads the shaders, the one that draws them and the list of
# combinations. Nothing from the game ships either.
#
# NOT FOR CROSSOVER. Every game in every CrossOver bottle shares one Metal
# cache, and a build for Ori replaces it; macprotips' own app does that and says
# so. This installer refuses anything but a game NotProton has started.
#
# Run it again after an update to macOS, to the runner or to the game: --status
# says "broken" once any of them is not what the shaders were compiled with.
#
# HOW FAR IT IS. With MGVF_PROGRESS=1, as the app runs it, the compiling prints
# lines of "MGVF-PROGRESS <done> <total>", which the app draws as a bar; without
# it, a line in words at every twentieth of the way.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MGVF-SCOPE: folder
# MGVF-GAME: Ori and the Will of the Wisps | oriwotw.exe |
# MGVF-WHY: Compiles the game's shaders ahead of time, so it no longer hitches when something new comes on screen. NotProton only; takes 5 to 30 minutes.
# MGVF-CREDIT: macprotips | https://github.com/macprotips/ori-shader-warmer

set -euo pipefail

usage() { sed -n '3,11p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
# See install-p5s-bridge.sh: a read-only caller must never land on --install.
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi

APPID=1057090
EXE="$GAME/oriwotw.exe"
MARKER="$GAME/mgf-shaders-compiled.txt"
BUNDLE="com.notproton.launcher.$APPID"
# The name the drawing program runs under: D3DMetal names its cache after it.
WARMER=mgf-oriwarm.exe

# macprotips' Ori Shader Warmer 1.1: extract, oriwarm_t.exe and plan.txt.gz.
TOOLS_URL="${MGVF_ORI_URL:-https://github.com/macprotips/ori-shader-warmer/releases/download/v1.1/Ori-Shader-Warmer.zip}"
TOOLS_SHA256="${MGVF_ORI_SHA256:-dd23eab5741baf9b5f1136a53c238f90bcb2ae7d9a0ba1ffe4e73697bada2fd2}"
STORE="${MGVF_ORI_STORE:-$HOME/Library/Caches/MacGameFix/ori-shader-warmer}"
TOOLS="$STORE/tools-${TOOLS_SHA256:0:12}"
WORK="$STORE/work"

# The runner NotProton made for this game: a copy of the runner's Wine whose
# loader carries the game's bundle. It exists once the game has been started.
RUNNER="${MGVF_ORI_RUNNER:-$HOME/Library/Application Support/notproton/launchers/$APPID/runner}"
CACHES="${MGVF_ORI_CACHES:-$(getconf DARWIN_USER_CACHE_DIR)}"
CACHES="${CACHES%/}"
D3DM="$CACHES/d3dm"
BUILT="$D3DM/$WARMER/shaders.cache"
METAL="$CACHES/$BUNDLE/com.apple.metal"

loader() {
  local l
  for l in "$RUNNER/lib/wine/x86_64-unix/wine.app/Contents/MacOS/wine" "$RUNNER/lib/wine/x86_64-unix/wine"; do
    [ -x "$l" ] && { printf '%s\n' "$l"; return 0; }
  done
  return 1
}

# Steam's build number for the game, from the library's manifest; for a copy
# with no manifest beside it, the executable's size.
game_build() {
  local acf="$GAME/../../appmanifest_$APPID.acf" b=""
  [ -r "$acf" ] && b="$(sed -n 's/^[[:space:]]*"buildid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$acf" | head -1)"
  [ -n "$b" ] || b="exe-$(stat -L -f %z "$EXE" 2>/dev/null || echo 0)"
  printf '%s\n' "$b"
}

# The runner's D3DMetal, as its version and the size of its binary, and the
# CrossOver build its Wine comes from. A cache serves only the pair that made it.
d3dmetal_version() {
  local d fw
  for d in lib lib64; do
    fw="$RUNNER/$d/apple_gptk/external/D3DMetal.framework"
    [ -e "$fw/D3DMetal" ] || continue
    printf '%s-%s\n' \
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$fw/Resources/Info.plist" 2>/dev/null || echo '?')" \
      "$(stat -L -f %z "$fw/D3DMetal")"
    return 0
  done
  return 1
}
runner_build() {
  LC_ALL=C sed -n 's/^"ProductVersion"[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$RUNNER/share/crossover/data/CrossOver.conf" 2>/dev/null | head -1
}

# What the shaders were compiled with: the game, D3DMetal, the runner's Wine,
# macOS and the list of combinations.
made_with() {
  printf '%s|%s|%s|%s|%s\n' "$(game_build)" "$(d3dmetal_version || echo none)" "$(runner_build)" \
    "$(sw_vers -buildVersion)" "${TOOLS_SHA256:0:12}"
}
marked() { [ -r "$MARKER" ] || return 0; sed -n 's/^compiled_with[[:space:]]*=[[:space:]]*//p' "$MARKER" | head -1; }

# Whether a process holds one of the game's Metal cache files: Metal keeps a lock
# on the one a process took, so the game, or Steam's launcher for it, is running.
held() {
  /usr/bin/perl -e 'use Fcntl qw(:flock);
    for (@ARGV) { open(my $f, "<", $_) or next; flock($f, LOCK_EX | LOCK_NB) or exit 0; }
    exit 1' "$@"
}
metal_files() { find "$METAL" -maxdepth 2 -name 'functions*.data' 2>/dev/null; }
game_running() {
  ps -Ao command | LC_ALL=C grep -qiE '^[a-z]:\\.*\\oriwotw\.exe' && return 0
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(metal_files)
  [ ${#files[@]} -gt 0 ] && held "${files[@]}"
}

[ -f "$EXE" ] || {
  echo "error: no oriwotw.exe in $GAME" >&2
  echo "       Pick the folder Ori and the Will of the Wisps is installed in." >&2
  exit 1
}

case "$MODE" in
--status)
  if [ ! -f "$MARKER" ]; then echo absent
  elif [ "$(marked)" != "$(made_with)" ]; then
    echo "the game, macOS or the NotProton runner changed since the shaders were compiled; install again" >&2
    echo broken
  elif [ -z "$(metal_files)" ]; then
    echo "the compiled shaders are gone from the cache folder; install again" >&2
    echo broken
  else echo installed; fi
  exit 0
  ;;
--restore)
  if [ -f "$MARKER" ]; then
    rm -f "$MARKER"
    echo "restored -- MacGameFix no longer counts the shaders as compiled"
    echo "  the compiled shaders stay: they are a cache, and the game works with or without them"
  else
    echo "nothing to restore"
  fi
  rm -rf "$STORE"
  exit 0
  ;;
--install) ;;
*) usage ;;
esac

[ "$(uname -m)" = arm64 ] || { echo "error: this is for Apple Silicon Macs." >&2; exit 1; }

LOADER="$(loader)" || {
  echo "error: NotProton has not started Ori and the Will of the Wisps on this Mac with a Rosetta runner." >&2
  echo "       Start the game once with NotProton, close it, and install again." >&2
  echo "       Under CrossOver, macprotips' own app compiles the shaders:" >&2
  echo "       https://github.com/macprotips/ori-shader-warmer" >&2
  exit 1
}
d3dmetal_version > /dev/null || {
  echo "error: the runner NotProton starts the game from has no D3DMetal; nothing was changed" >&2
  exit 1
}
if game_running; then
  echo "error: Ori and the Will of the Wisps is running. Close the game and install again." >&2
  exit 1
fi
if pgrep -qf "$WARMER"; then
  echo "error: the shaders are being compiled already." >&2
  exit 1
fi
mkdir -p "$STORE"
free_kb="$(df -k "$STORE" | awk 'NR == 2 { print $4 }')"
[ "${free_kb:-0}" -gt 3000000 ] || {
  echo "error: not enough free disk space; about 3 GB is needed." >&2
  exit 1
}

SERVER="$RUNNER/bin/wineserver"; [ -x "$SERVER" ] || SERVER="$RUNNER/bin/wineserver-x86"
# Wine for the drawing program: the game's runner, D3DMetal, and a prefix of its
# own, made here and thrown away -- neither cache depends on the prefix.
wine_env() {
  export CX_ROOT="$RUNNER" CX_HOME="$HOME/Library/Application Support/CrossOver" WINEPREFIX="$WORK/prefix"
  export WINELOADER="$LOADER" WINESERVER="$SERVER"
  export WINEDLLPATH="$RUNNER/lib/wine/x86_64-windows:$RUNNER/lib/wine/x86_64-unix"
  export ROSETTA_ADVERTISE_AVX=1 CX_GRAPHICS_BACKEND=d3dmetal WINEMSYNC=1
  export WINEDLLOVERRIDES="winedbg.exe=d;mscoree=d;mshtml=d" WINEDEBUG=-all
  export PATH="$RUNNER/bin:/usr/bin:/bin"
  local shared
  for shared in "$RUNNER/lib64/apple_gptk/external/libd3dshared.dylib" "$RUNNER/lib/apple_gptk/external/libd3dshared.dylib"; do
    [ -f "$shared" ] && { export CX_APPLEGPTK_LIBD3DSHARED_PATH="$shared"; break; }
  done
  return 0
}
stop_wine() {
  pkill -9 -f "$WARMER" 2>/dev/null || true
  [ -d "$WORK/prefix" ] && (wine_env; "$SERVER" -k > /dev/null 2>&1) || true
}
tidy() { stop_wine; rm -rf "$WORK" "$D3DM/$WARMER"; }
trap tidy EXIT
trap 'echo "stopped; nothing the game reads was changed" >&2; exit 2' INT TERM HUP PIPE

rm -rf "$WORK" "$D3DM/$WARMER"
mkdir -p "$WORK/run"

echo "[1/4] macprotips' Ori Shader Warmer"
tools_ok() { [ -x "$TOOLS/extract" ] && [ -s "$TOOLS/oriwarm_t.exe" ] && [ -s "$TOOLS/plan.txt.gz" ]; }
if tools_ok; then
  echo "  kept in $TOOLS"
else
  echo "  fetching it once (7 MB) from github.com/macprotips/ori-shader-warmer"
  curl -fsSL --retry 2 -o "$WORK/tools.zip" "$TOOLS_URL" || {
    echo "error: could not download it; check the connection and install again" >&2
    exit 1
  }
  got="$(shasum -a 256 "$WORK/tools.zip" | cut -d' ' -f1)"
  [ "$got" = "$TOOLS_SHA256" ] || {
    echo "error: the download is not the expected file (sha256 $got); nothing was changed" >&2
    exit 1
  }
  mkdir "$WORK/tools"
  ditto -x -k "$WORK/tools.zip" "$WORK/tools"
  res="$(find "$WORK/tools" -maxdepth 4 -type d -name Resources -path '*.app/Contents/*' | head -1)"
  [ -n "$res" ] && [ -f "$res/extract" ] && [ -f "$res/oriwarm_t.exe" ] && [ -f "$res/plan.txt.gz" ] || {
    echo "error: the download does not hold the three files where expected; nothing was changed" >&2
    exit 1
  }
  rm -rf "$TOOLS.new"
  mkdir -p "$TOOLS.new"
  cp "$res/extract" "$res/oriwarm_t.exe" "$res/plan.txt.gz" "$TOOLS.new/"
  chmod 755 "$TOOLS.new/extract"
  rm -rf "$TOOLS"
  mv "$TOOLS.new" "$TOOLS"
  rm -rf "$WORK/tools" "$WORK/tools.zip"
  tools_ok || { echo "error: the download is not usable on this Mac" >&2; exit 1; }
  echo "  kept in $TOOLS"
fi

echo "[2/4] reading the shaders out of your copy of the game"
"$TOOLS/extract" "$GAME" "$WORK/shaders" > "$WORK/extract.out" 2>&1 || {
  echo "error: could not read the game's files." >&2
  echo "       If macOS asked whether MacGameFix may reach the disk the game is on, allow it and install again." >&2
  exit 1
}
gunzip -c "$TOOLS/plan.txt.gz" > "$WORK/plan.txt" || { echo "error: could not unpack the list of combinations" >&2; exit 1; }
# The list names each shader by its content. Lines whose shaders this copy of
# the game has are drawn; a game version the list was not made for has few.
ls "$WORK/shaders" | sed 's/\.dxbc$//' > "$WORK/have.txt"
counts="$(awk 'NR == FNR { have[$1] = 1; next }
  { n++; if (($1 in have) && ($2 == "-" || ($2 in have))) ok++ }
  END { printf "%d %d\n", ok, n }' "$WORK/have.txt" "$WORK/plan.txt")"
total="${counts% *}"; listed="${counts#* }"
[ "$listed" -gt 0 ] && [ $((total * 10)) -ge $((listed * 9)) ] || {
  echo "error: this version of the game is not the one the list was recorded from" >&2
  echo "       ($total of its $listed combinations use shaders this copy has); nothing was changed" >&2
  exit 1
}
echo "  $(wc -l < "$WORK/have.txt" | tr -d ' ') shaders, $total combinations to compile"

echo "[3/4] compiling: this takes 5 to 30 minutes, and the Mac works hard meanwhile"
cp "$TOOLS/oriwarm_t.exe" "$WORK/run/$WARMER"
win() { printf 'Z:%s' "$(printf '%s' "$1" | tr '/' '\\')"; }
drawn() { local n; n="$(LC_ALL=C grep -c '^DRAW' "$WORK/run/warm.log" 2>/dev/null)" || true; echo "${n:-0}"; }
skip=0; shown=-1
POLL="${MGVF_ORI_POLL:-5}"   # seconds between looks at its progress
# If the drawing program stops, or draws nothing new for five minutes, it is
# started again after the last combination it finished; what it compiled so far
# is kept. The Mac is kept awake while it runs.
for attempt in 1 2 3 4 5 6; do
  rm -f "$WORK/run/warm.log"
  ( wine_env; cd "$WORK/run"
    exec /usr/bin/caffeinate -i "$LOADER" "$(win "$WORK/run/$WARMER")" "$(win "$WORK/shaders")" \
      --plan "$(win "$WORK/plan.txt")" --skipdraws "$skip" --sleep 20000 > "$WORK/run/wine.out" 2>&1 ) &
  pid=$!; seen=-1; still=0
  while kill -0 "$pid" 2>/dev/null; do
    n="$(drawn)"
    if [ "${MGVF_PROGRESS:-0}" = 1 ]; then
      # A program that draws the progress asked for it: one line a look.
      [ "$n" = "$seen" ] || echo "MGVF-PROGRESS $((skip + n)) $total"
    else
      step=$(( (skip + n) * 20 / (total > 0 ? total : 1) ))
      if [ "$step" -gt "$shown" ] && [ $((skip + n)) -gt 0 ]; then
        shown="$step"; echo "  $((skip + n)) of $total"
      fi
    fi
    if [ "$n" = "$seen" ]; then
      still=$((still + 1)); [ $((still * POLL)) -gt 300 ] && break
    else seen="$n"; still=0; fi
    sleep "$POLL"
  done
  LC_ALL=C grep -q '^SUMMARY' "$WORK/run/warm.log" 2>/dev/null && break
  stop_wine
  wait "$pid" 2>/dev/null || true
  last="$(LC_ALL=C grep '^DRAW' "$WORK/run/warm.log" 2>/dev/null | tail -1 | awk '{ print $2 }')" || true
  if [ -n "${last:-}" ]; then skip=$((last + 1))
  elif [ "$attempt" = 1 ]; then
    echo "error: the drawing program did not start under the game's runner; nothing was changed" >&2
    tail -3 "$WORK/run/wine.out" 2>/dev/null | sed 's/^/       /' >&2
    exit 1
  fi
  sleep 2
done
LC_ALL=C grep -q '^SUMMARY' "$WORK/run/warm.log" 2>/dev/null || {
  echo "error: the drawing program kept stopping; nothing was changed" >&2
  exit 1
}
wait "$pid" 2>/dev/null || true
# What it drew: a few of the list's combinations it leaves out by itself.
compiled=$((skip + $(drawn)))
stop_wine

echo "[4/4] putting the compiled shaders where the game reads them"
# Metal names the folder after this Mac's GPU and macOS.
data="$(ls "$BUILT"/*/functions.data 2>/dev/null | head -1)"
[ -n "$data" ] && ls -d "$BUILT"/MTLGPUFamily* > /dev/null 2>&1 || {
  echo "error: no compiled shaders came out; nothing was changed" >&2
  exit 1
}
if game_running; then
  echo "error: the game was started while the shaders were compiled; nothing was changed." >&2
  echo "       Close it and install again." >&2
  exit 1
fi
built_metal="$(dirname "$data")"
dest="$METAL/$(basename "$built_metal")"
mkdir -p "$dest" "$D3DM/oriwotw.exe/shaders.cache"
# From here on a stop would leave the game with half of each cache, so nothing
# stops it and nothing is written to a reader that may be gone until it is done.
trap '' INT TERM HUP PIPE
# A copy is an APFS clone: the four files take the space of one.
for n in "" 1 2 3; do
  for ext in data list; do
    cp -c "$built_metal/functions.$ext" "$dest/functions$n.$ext.mgf-new" 2>/dev/null \
      || cp "$built_metal/functions.$ext" "$dest/functions$n.$ext.mgf-new"
    mv -f "$dest/functions$n.$ext.mgf-new" "$dest/functions$n.$ext"
  done
done
# D3DMetal's own cache, under the game's executable name.
for dir in "$BUILT"/MTLGPUFamily*; do
  live="$D3DM/oriwotw.exe/shaders.cache/$(basename "$dir")"
  rm -rf "$live.mgf-new" "$live.mgf-old"
  cp -cR "$dir" "$live.mgf-new" 2>/dev/null || cp -R "$dir" "$live.mgf-new"
  [ -e "$live" ] && mv "$live" "$live.mgf-old"
  mv "$live.mgf-new" "$live"
  rm -rf "$live.mgf-old"
done

printf '# Ori and the Will of the Wisps: shaders compiled ahead of time by MacGameFix,\n# with macprotips'"'"' Ori Shader Warmer. --status compares the line below with\n# the game, D3DMetal, the runner, macOS and the list as they are now.\ncompiled_with = %s\ncombinations = %s\n' \
  "$(made_with)" "$compiled" > "$MARKER.new"
mv -f "$MARKER.new" "$MARKER"
{ echo
  echo "installed"
  echo "  $compiled combinations compiled; install again after an update to macOS, the runner or the game"
} 2> /dev/null || true
