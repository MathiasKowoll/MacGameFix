#!/bin/bash
# Build ncrypt-fh6.dll: Wine's ncrypt with persisted keys, for Forza Horizon 6's Xbox sign-in.
#
#   build-fh6-ncrypt.sh <CrossOver 27.0.0.41073 Wine source> [work folder]
#
# The source is wine/ from CodeWeavers' crossover-sources-20261015.tar.gz, the one
# CrossOver Preview 27.0.0.41073 was built from. The patch is fh6-ncrypt/; the build
# is the x86_64 half only (the game runs on the Intel side), configured as
# engine/build.sh configures CrossOver's modules. It writes ncrypt-fh6.dll beside
# this script and prints its sha256, which fh6-ncrypt/ORIGIN.md records.
# LLVM-mingw (x86_64-w64-mingw32-clang), bison and make must be found.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: LGPL-2.1-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${1:?the CrossOver 41073 Wine source}" && pwd)"
WORK="${2:-$(mktemp -d)}"
[ "$(cat "$SRC/VERSION")" = 'Wine version 11.17' ] || { echo "not Wine 11.17: $SRC" >&2; exit 1; }
[[ "$SRC" != *' '* && "$WORK" != *' '* ]] || { echo 'Wine build paths must not contain spaces.' >&2; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SDK="$(xcrun --show-sdk-path)"
mkdir -p "$WORK/tree" "$WORK/build"
(cd "$SRC" && tar cf - .) | (cd "$WORK/tree" && tar xf -)
(cd "$WORK/tree" && patch -p1 --forward < "$HERE/fh6-ncrypt/0001-ncrypt-persisted-keys.patch")
cd "$WORK/build"
CC="/usr/bin/clang -arch x86_64 -isysroot $SDK -mmacosx-version-min=14.0" \
CXX="/usr/bin/clang++ -arch x86_64 -isysroot $SDK -mmacosx-version-min=14.0" \
LDFLAGS="-isysroot $SDK -mmacosx-version-min=14.0" \
"$WORK/tree/configure" --host=x86_64-apple-darwin --enable-archs=x86_64 \
  --without-freetype --without-x --without-gstreamer --without-vulkan --without-opengl \
  --without-cups --without-dbus --without-fontconfig --without-gnutls --without-krb5 --without-gssapi \
  --without-opencl --without-pcap --without-usb --without-v4l2 --without-sane --without-capi \
  --without-gphoto --without-netapi --without-pulse --without-alsa --without-oss --without-udev \
  --without-unwind --without-ffmpeg --without-inotify --without-sdl ac_cv_func_pipe2=no > configure.log 2>&1
make -j10 dlls/ncrypt/all > make.log 2>&1
llvm-strip -o "$HERE/ncrypt-fh6.dll" dlls/ncrypt/x86_64-windows/ncrypt.dll
shasum -a 256 "$HERE/ncrypt-fh6.dll"
