#!/bin/bash
# build.sh's signing, on a fake tree: build.sh itself, copied byte for byte, run
# on a Wine source tree that is two files, its tools stubbed (configure writes a
# Makefile; make writes PE files that are a few bytes and builds the two unix
# modules as real dylibs from a line of C; llvm-strip copies), so the steps after
# make run as they do on a real build: strip, the second rpath, the signature
# and built-for.json. No Wine is built.
#
#   /bin/bash engine/tests/build-signing/run.sh
#
# Without MACGAMEFIX_CODESIGN_IDENTITY: ad hoc, and build.sh says so. With an
# identity (MACGAMEFIX_CODESIGN_IDENTITY as this runs, or else the keychain's
# first Developer ID Application, as build-app.sh finds one): a Developer ID
# signature with a secure timestamp and the hardened runtime, the identifier the
# ad hoc signature gives, and built-for.json vouching for the signed files;
# without any, that half is skipped and says so. Both sides, x86_64 and arm64.
# And an identity the keychain does not have stops build.sh before it writes
# built-for.json. KEEP=1 keeps the fake tree.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
build_sh="$here/../../build.sh"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] && echo "kept $work" || rm -rf "$work"' EXIT
fail=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

# The tree build.sh runs in: its own copy, a series, and the stubs.
mkdir -p "$work/engine/patches/fake" "$work/src" "$work/mingw/bin" "$work/sdl"
cp "$build_sh" "$work/engine/build.sh"
cmp -s "$build_sh" "$work/engine/build.sh" || { echo "could not copy build.sh"; exit 1; }
printf 'MIN=14.0\nRPATH2=@loader_path/../../../lib/x86_64\nRPATH2_ARM64=@loader_path/../../../lib/aarch64\n' \
  > "$work/engine/patches/fake/build.conf"
echo "Wine version 11.17" > "$work/src/VERSION"
printf '#!/bin/sh\necho "all:" > Makefile\n' > "$work/src/configure"
chmod +x "$work/src/configure"
: > "$work/sdl/SDL.h"
printf '#!/bin/sh\n' > "$work/mingw/bin/x86_64-w64-mingw32-clang"
# llvm-strip -o <out> <in>
printf '#!/bin/sh\ncp "$3" "$2"\n' > "$work/mingw/bin/llvm-strip"
# make, in the build directory (build-<id>-<arch>): every PE file build.sh takes,
# for both sides, and the two unix modules for this one.
cat > "$work/mingw/bin/make" <<'MAKE'
#!/bin/sh
set -e
case "$(basename "$PWD")" in *-arm64) cpu=arm64 ;; *) cpu=x86_64 ;; esac
for pe in x86_64-windows aarch64-windows; do
  for f in winebus.sys/winebus.sys mmdevapi/mmdevapi.dll hidclass.sys/hidclass.sys setupapi/setupapi.dll \
           xaudio2_9/xaudio2_9.dll xinput1_1/xinput1_1.dll xinput1_2/xinput1_2.dll xinput1_3/xinput1_3.dll \
           xinput1_4/xinput1_4.dll xinput9_1_0/xinput9_1_0.dll xinputuap/xinputuap.dll; do
    mkdir -p "dlls/${f%/*}/$pe" && printf 'MZ fake %s\n' "$f" > "dlls/${f%/*}/$pe/${f#*/}"
  done
done
mkdir -p dlls/winebus.sys dlls/winecoreaudio.drv
echo 'int fake_module(void) { return 1; }' > fake.c
/usr/bin/clang -arch "$cpu" -dynamiclib -Wl,-headerpad_max_install_names -o dlls/winebus.sys/winebus.so fake.c
/usr/bin/clang -arch "$cpu" -dynamiclib -Wl,-headerpad_max_install_names -o dlls/winecoreaudio.drv/winecoreaudio.so fake.c
MAKE
chmod +x "$work/mingw/bin/make" "$work/mingw/bin/llvm-strip" "$work/mingw/bin/x86_64-w64-mingw32-clang"

run() { # <build id> <arch> [<identity>]; an empty identity is none
  MACGAMEFIX_CODESIGN_IDENTITY="${3:-}" LLVM_MINGW="$work/mingw" SDL2_INCLUDE="$work/sdl" CROSSOVER="Fake CrossOver" \
    /bin/sh "$work/engine/build.sh" "$1" "$work/src" fake "$2" > "$work/out-$1-$2.log" 2>&1
}
# Every unix module of a build: matches its built-for.json, and is signed as asked.
check() { # <build id> <arch> <adhoc|team id>
  local dir="$work/engine/modules/$1" unix so d n=0
  case "$2" in arm64) unix=aarch64-unix ;; *) unix=x86_64-unix ;; esac
  for so in "$dir/$unix/winebus.so" "$dir/$unix/winecoreaudio.so"; do
    [ -f "$so" ] || { bad "$1 $2: $(basename "$so") was not written"; return; }
    want="$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"].get(sys.argv[2], ""))' \
      "$dir/built-for.json" "$unix/$(basename "$so")")"
    [ "$want" = "$(shasum -a 256 "$so" | cut -d' ' -f1)" ] || { bad "$1 $2: built-for.json does not vouch for $(basename "$so")"; return; }
    codesign --verify --strict "$so" 2>/dev/null || { bad "$1 $2: $(basename "$so") does not verify"; return; }
    d="$(codesign -dvv "$so" 2>&1)"
    case "$(printf '%s\n' "$d" | sed -n 's/^Identifier=//p')" in
      "$(basename "$so" .so)"-55554944*) ;;
      *) bad "$1 $2: $(basename "$so")'s identifier is not the one an ad hoc signature gives"; return ;;
    esac
    if [ "$3" = adhoc ]; then
      printf '%s\n' "$d" | /usr/bin/grep -q '^Signature=adhoc$' || { bad "$1 $2: $(basename "$so") is not ad hoc"; return; }
    else
      printf '%s\n' "$d" | /usr/bin/grep -qx "TeamIdentifier=$3" &&
        printf '%s\n' "$d" | /usr/bin/grep -q '^Authority=Developer ID Application: ' &&
        printf '%s\n' "$d" | /usr/bin/grep -q '^Timestamp=' &&
        printf '%s\n' "$d" | /usr/bin/grep -q 'flags=0x10000(runtime)' ||
        { bad "$1 $2: $(basename "$so") is not signed with $3's Developer ID, a timestamp and the runtime"; return; }
    fi
    n=$((n + 1))
  done
  ok "$1 $2: both unix modules $( [ "$3" = adhoc ] && echo "ad hoc" || echo "signed by $3, with a secure timestamp and the hardened runtime"), as built-for.json records"
}

echo "== without an identity"
for arch in x86_64 arm64; do
  if run 0.0.0.1 "$arch"; then
    /usr/bin/grep -q '^==> signing .*-unix ad hoc (MACGAMEFIX_CODESIGN_IDENTITY is not set)' "$work/out-0.0.0.1-$arch.log" \
      && ok "0.0.0.1 $arch: build.sh says it signs ad hoc" || bad "0.0.0.1 $arch: build.sh did not say it signs ad hoc"
    check 0.0.0.1 "$arch" adhoc
  else
    bad "0.0.0.1 $arch: build.sh failed"; sed 's/^/        /' "$work/out-0.0.0.1-$arch.log" | tail -15
  fi
done

echo "== with an identity the keychain does not have"
if run 0.0.0.3 x86_64 "Developer ID Application: Nobody (ABCDEFGHIJ)"; then
  bad "0.0.0.3: build.sh went on after codesign failed"
elif [ -f "$work/engine/modules/0.0.0.3/built-for.json" ]; then
  bad "0.0.0.3: build.sh failed, and wrote a built-for.json anyway"
else
  ok "0.0.0.3: build.sh stops at the failed signature, before built-for.json"
fi

echo "== with a Developer ID"
ID="${MACGAMEFIX_CODESIGN_IDENTITY:-}"
[ -n "$ID" ] || ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/^ *[0-9]*) [0-9A-F]\{40\} "\(Developer ID Application: .*\)"$/\1/p' | head -1)"
TEAM="$(printf '%s\n' "$ID" | sed -n 's/^Developer ID Application: .*(\([A-Z0-9]\{10\}\))$/\1/p')"
if [ -z "$TEAM" ]; then
  echo "  skip  no Developer ID Application identity here (set MACGAMEFIX_CODESIGN_IDENTITY to its full name)"
else
  for arch in x86_64 arm64; do
    if run 0.0.0.2 "$arch" "$ID"; then
      /usr/bin/grep -qF "==> signing $( [ "$arch" = arm64 ] && echo aarch64 || echo x86_64)-unix with $ID, a secure timestamp and the hardened runtime" \
        "$work/out-0.0.0.2-$arch.log" && ok "0.0.0.2 $arch: build.sh names the identity" || bad "0.0.0.2 $arch: build.sh did not name the identity"
      check 0.0.0.2 "$arch" "$TEAM"
    else
      bad "0.0.0.2 $arch: build.sh failed"; sed 's/^/        /' "$work/out-0.0.0.2-$arch.log" | tail -15
    fi
  done
  # The identity's modules are the ad hoc build's code: otool -t the same.
  for unix in x86_64-unix aarch64-unix; do
    for m in winebus.so winecoreaudio.so; do
      cmp -s <(otool -t "$work/engine/modules/0.0.0.1/$unix/$m" | tail -n +2) <(otool -t "$work/engine/modules/0.0.0.2/$unix/$m" | tail -n +2) \
        || bad "$unix/$m: otool -t differs between the ad hoc and the Developer ID build"
    done
  done
  [ "$fail" = 0 ] && ok "otool -t of every module the same in both builds"
fi

echo
[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
