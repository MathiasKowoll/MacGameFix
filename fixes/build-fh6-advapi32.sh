#!/bin/bash
# Build advapi32-fh6-<build>.dll: Wine's advapi32 whose CredEnumerateW takes the host
# keychain's "not found" as no host credential, for Forza Horizon 6's Xbox sign-in.
#
#   build-fh6-advapi32.sh <build> <that CrossOver's Wine source> [work folder]
#   build-fh6-advapi32.sh 27.0.0.41303 ~/Development/sources-cx-20261111/sources/wine
#
# The source is wine/ from the crossover-sources tarball the build was made from
# (27.0.0.41073: 20261015, Wine 11.17; 27.0.0.41303: 20261111, Wine 11.21). The patch is
# fh6-advapi32/; only the x86_64 half is built (FH6 runs on the Intel side), configured as
# engine/build.sh configures CrossOver's modules. It stays a Wine builtin, signature at 0x40
# kept: install-fh6-fix.sh puts it in place of the builtin advapi32.dll of FH6's runner
# clone. It writes advapi32-fh6-<build>.dll beside this script and prints its sha256, which
# fh6-advapi32/ORIGIN.md records.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: LGPL-2.1-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="${1:?the CrossOver build id}"
SRC="$(cd "${2:?the Wine source of that build}" && pwd)"
WORK="${3:-$(mktemp -d)}"
case "$BUILD" in
  27.0.0.41073) want='Wine version 11.17' ;;
  27.0.0.41303) want='Wine version 11.21' ;;
  *) echo "no recipe for build $BUILD" >&2; exit 1 ;;
esac
[ "$(cat "$SRC/VERSION")" = "$want" ] || { echo "$SRC is not $want" >&2; exit 1; }
[[ "$SRC" != *' '* && "$WORK" != *' '* ]] || { echo 'Wine build paths must not contain spaces.' >&2; exit 1; }
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}"
export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SDK="$(xcrun --show-sdk-path)"
mkdir -p "$WORK/tree" "$WORK/build"
(cd "$SRC" && tar cf - .) | (cd "$WORK/tree" && tar xf -)
(cd "$WORK/tree" && patch -p1 --forward --fuzz=0 < "$HERE/fh6-advapi32/0001-advapi32-credenumerate-host-not-found.patch")
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
make -j10 dlls/advapi32/all > make.log 2>&1
OUT="$HERE/advapi32-fh6-$BUILD.dll"
llvm-strip -o "$OUT" dlls/advapi32/x86_64-windows/advapi32.dll
/usr/bin/python3 -I -c 'import sys
b = open(sys.argv[1], "rb").read()
assert b[0x40:0x50] == b"Wine builtin DLL", "no builtin signature where it was expected"' "$OUT"
shasum -a 256 "$OUT"
