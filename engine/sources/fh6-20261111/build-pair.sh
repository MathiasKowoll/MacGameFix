#!/bin/bash
# Build a fresh pair separately; never overwrite the retained module artifacts.
# Usage: build-pair.sh <prepared corresponding Wine source> <empty work folder>
# LLVM-mingw (x86_64-w64-mingw32-clang), bison and make must be on PATH.
set -euo pipefail
SRC="$(cd "${1:?prepared Wine source}" && pwd)"
OUT="${2:?new work folder}"
[ ! -e "$OUT" ] || { echo 'Use a new work folder; the retained baseline must stay intact.' >&2; exit 1; }
[ "$(cat "$SRC/VERSION")" = 'Wine version 11.17' ] || exit 1
[[ "$SRC" != *' '* && "$OUT" != *' '* ]] || { echo 'Wine build paths must not contain spaces.' >&2; exit 1; }
mkdir -p "$OUT"; cd "$OUT"
SDK="$(xcrun --show-sdk-path)"
CC="/usr/bin/clang -arch x86_64 -isysroot $SDK -mmacosx-version-min=14.0" \
CXX="/usr/bin/clang++ -arch x86_64 -isysroot $SDK -mmacosx-version-min=14.0" \
LDFLAGS="-Wl,-headerpad_max_install_names -isysroot $SDK -mmacosx-version-min=14.0" \
"$SRC/configure" --host=x86_64-apple-darwin --enable-archs=x86_64 \
 --without-freetype --without-x --without-gstreamer --without-vulkan --without-opengl \
 --without-cups --without-dbus --without-fontconfig --without-gnutls --without-krb5 --without-gssapi \
 --without-opencl --without-pcap --without-usb --without-v4l2 --without-sane --without-capi \
 --without-gphoto --without-netapi --without-pulse --without-alsa --without-oss --without-udev \
 --without-unwind --without-ffmpeg --without-inotify ac_cv_func_pipe2=no > configure.log 2>&1
make -j4 dlls/ntdll/ntdll.so dlls/ntdll/x86_64-windows/ntdll.dll > build.log 2>&1
mkdir artifacts
cp dlls/ntdll/ntdll.so artifacts/ntdll.so
cp dlls/ntdll/x86_64-windows/ntdll.dll artifacts/ntdll.dll
strip -x artifacts/ntdll.so
install_name_tool -add_rpath '@loader_path/../../../lib/x86_64' artifacts/ntdll.so
codesign -f -s - artifacts/ntdll.so
shasum -a 256 artifacts/*
