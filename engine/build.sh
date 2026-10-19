#!/bin/sh
# Build the Wine modules the DualSense patches touch, from the CrossOver sources a
# CrossOver build was made from.
#
#   ./build.sh <build id> <wine source dir> <patch series> [x86_64|arm64]
#   CROSSOVER="CrossOver Preview 20261006" \
#     ./build.sh 27.0.0.41069 ~/Development/sources-cx-20261006/sources/wine wine-11.17 arm64
#
# The build id is the CrossOver build's CFBundleVersion (27.0.0.41069), which is how the
# app and NotProton's runner folders name it.
#
# x86_64 (the default) is CrossOver's Intel side, run under Rosetta: it writes
# modules/<id>/x86_64-windows/{winebus.sys,mmdevapi.dll,hidclass.sys,xinput*.dll} and
# x86_64-unix/{winebus.so,winecoreaudio.so}. arm64 is the FEX side, where Wine runs
# natively: aarch64-windows/ the same PE files as ARM64X (arm64 and arm64ec in one
# file, as CrossOver ships them) and aarch64-unix/{winebus.so,winecoreaudio.so}.
# The six xinput DLLs are one source, dlls/xinput1_3.
# winebus.so is built with SDL, as CodeWeavers build theirs (it opens libSDL2 when it
# runs): SDL2's headers must be installed (brew install sdl2).
# modules/<id>/built-for.json lists every file built so far.
# The copied tree and the build directories go under .build/, which git ignores.
# winebus.sys, mmdevapi.dll, hidclass.sys and xinput are PE (llvm-mingw); winecoreaudio.so is the unix half
# (Wine 11 has no PE winecoreaudio.drv: mmdevapi loads the unix library itself).
# PATCHES=none builds the same modules unpatched, to compare with CodeWeavers' own.
set -eu
[ $# -eq 3 ] || [ $# -eq 4 ] || { sed -n '5,10p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
ID="$1"; SERIES="$here/patches/$3"; ARCH="${4:-x86_64}"
# A wrong argument here copies the wrong tree into .build: refuse it first.
case "$ID" in *[!0-9.]*|"") echo "not a CrossOver build id: '$ID'"; exit 2 ;; esac
[ -f "$2/configure" ] && [ -f "$2/VERSION" ] || { echo "not a Wine source tree: '$2'"; exit 2; }
SRC="$(cd "$2" && pwd)"
[ -d "$SERIES" ] || { echo "no patch series $SERIES"; exit 1; }
. "$SERIES/build.conf"
case "$ARCH" in
x86_64)
  HOST=x86_64-apple-darwin; ARCHS=x86_64; PE=x86_64-windows; UNIX=x86_64-unix ;;
arm64)
  [ -n "${RPATH2_ARM64:-}" ] || { echo "$3 has no arm64 (FEX) side"; exit 1; }
  HOST=aarch64-apple-darwin; ARCHS=aarch64,arm64ec; PE=aarch64-windows; UNIX=aarch64-unix
  RPATH2="$RPATH2_ARM64" ;;
*) echo "unknown architecture $ARCH"; exit 2 ;;
esac
suffix=""; [ "${PATCHES:-}" = none ] && suffix="-unpatched"
TREE="$here/.build/tree-$ID$suffix"   # a patched copy; the extracted sources stay pristine
BUILD="$here/.build/build-$ID$suffix-$ARCH"
if [ -n "$suffix" ]; then OUT="$here/.build/modules-$ID$suffix"; else OUT="$here/modules/$ID"; fi
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
SDL2_INCLUDE="${SDL2_INCLUDE:-/opt/homebrew/include/SDL2}"
[ -f "$SDL2_INCLUDE/SDL.h" ] || { echo "SDL2's headers not found at $SDL2_INCLUDE (brew install sdl2, or set SDL2_INCLUDE)"; exit 1; }
[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || { echo "llvm-mingw not found at $LLVM_MINGW (set LLVM_MINGW)"; exit 1; }
export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export SDKROOT="$(xcrun --show-sdk-path)"
# The unix halves need Apple's clang (its compiler runtime); llvm-mingw only builds the PE halves.
# Wine's build system does not survive a space in its path.
case "$here" in *\ *) echo "no spaces in $here"; exit 1 ;; esac
MIN="-mmacosx-version-min=$MIN"
CPU="${HOST%%-*}"; [ "$CPU" = aarch64 ] && CPU=arm64

if [ ! -d "$TREE" ]; then
  echo "==> copying $SRC"
  mkdir -p "$TREE" && (cd "$SRC" && tar cf - .) | (cd "$TREE" && tar xf -)
  if [ -z "$suffix" ]; then
    for p in "$SERIES"/*.patch; do
      [ -f "$p" ] || continue
      echo "==> applying $(basename "$p")"
      (cd "$TREE" && patch -p1 --forward <"$p")
    done
  fi
fi

if [ ! -f "$BUILD/Makefile" ]; then
  echo "==> configuring $ARCH (log: $BUILD/configure.log)"
  mkdir -p "$BUILD"
  (cd "$BUILD" && CC="/usr/bin/clang -arch $CPU -isysroot $SDKROOT $MIN" CXX="/usr/bin/clang++ -arch $CPU -isysroot $SDKROOT $MIN" \
    LDFLAGS="-isysroot $SDKROOT $MIN" "$TREE/configure" --host=$HOST --enable-archs=$ARCHS \
    --without-freetype --without-x --without-gstreamer --without-vulkan --without-opengl \
    --without-cups --without-dbus --without-fontconfig --without-gnutls --without-krb5 --without-gssapi \
    --without-opencl --without-pcap --without-usb --without-v4l2 --without-sane --without-capi \
    --without-gphoto --without-netapi --without-pulse --without-alsa --without-oss --without-udev \
    --without-unwind --without-ffmpeg --without-inotify \
    SDL2_CFLAGS="-I$SDL2_INCLUDE -D_THREAD_SAFE" ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib \
    >"$BUILD/configure.log" 2>&1) || { tail -20 "$BUILD/configure.log"; exit 1; }
fi

echo "==> building $ARCH (log: $BUILD/make.log)"
XINPUT="xinput1_1 xinput1_2 xinput1_3 xinput1_4 xinput9_1_0 xinputuap"
(cd "$BUILD" && make -j10 dlls/winebus.sys/all dlls/mmdevapi/all dlls/winecoreaudio.drv/all dlls/hidclass.sys/all \
  dlls/xinput1_1/all dlls/xinput1_2/all dlls/xinput1_3/all dlls/xinput1_4/all dlls/xinput9_1_0/all dlls/xinputuap/all \
  >"$BUILD/make.log" 2>&1) \
  || { tail -30 "$BUILD/make.log"; exit 1; }

# The shape the engine's own files have: PE files stripped (winebuild already wrote the
# 32-byte builtin signature), the unix half with CrossOver's second rpath and signed.
rm -rf "${OUT:?}/$PE" "${OUT:?}/$UNIX" && mkdir -p "$OUT/$PE" "$OUT/$UNIX"
for f in dlls/winebus.sys/$PE/winebus.sys dlls/mmdevapi/$PE/mmdevapi.dll dlls/hidclass.sys/$PE/hidclass.sys \
         $(for x in $XINPUT; do printf 'dlls/%s/%s/%s.dll ' "$x" "$PE" "$x"; done); do
  llvm-strip -o "$OUT/$PE/$(basename "$f")" "$BUILD/$f"
done
for f in dlls/winebus.sys/winebus.so dlls/winecoreaudio.drv/winecoreaudio.so; do
  so="$OUT/$UNIX/$(basename "$f")"
  cp "$BUILD/$f" "$so"
  strip -x "$so"
  install_name_tool -add_rpath "$RPATH2" "$so" 2>/dev/null
  codesign -f -s - "$so"
done

# CROSSOVER names the release for people ("CrossOver Preview 20261006"); a rebuild keeps
# the name the folder already has.
label="${CROSSOVER:-$(sed -n 's/.*"crossover": "\(.*\)",$/\1/p' "$OUT/built-for.json" 2>/dev/null)}"
{
  printf '{\n  "build": "%s",\n  "crossover": "%s",\n  "wine": "%s",\n  "patches": "%s",\n  "files": {\n' \
    "$ID" "$label" "$(cat "$SRC/VERSION")" "$( [ -n "$suffix" ] && echo none || basename "$SERIES")"
  (cd "$OUT" && find . -type f ! -name 'built-for.json*' | sed 's|^\./||' | sort) | while read -r f; do
    printf '    "%s": "%s",\n' "$f" "$(shasum -a 256 "$OUT/$f" | cut -d' ' -f1)"
  done | sed '$ s/,$//'
  printf '  }\n}\n'
} >"$OUT/built-for.json.new" && mv "$OUT/built-for.json.new" "$OUT/built-for.json"
cat "$OUT/built-for.json"
