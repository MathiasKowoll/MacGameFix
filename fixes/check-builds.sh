#!/usr/bin/env bash
#
# Does every shipped DLL still match the source it claims to come from?
#
#     fixes/check-builds.sh            report
#     fixes/check-builds.sh --verbose  and say what differs
#
# WHY THIS EXISTS. One afternoon this repository held three different builds of
# the same proxy at once: the source said one thing, the shipped amd_ags_x64.dll was
# several revisions behind it, and the copy installed in the game was a third
# build that matched neither. Nothing anywhere said so. Every measurement taken
# against "the fix" was really a measurement of whichever of the three happened
# to be in the path, and a fix that had been rewritten twice was still shipping
# its oldest form.
#
# It asks the binaries, not a manifest. A manifest is one more thing to forget
# to update; a rebuild cannot be out of date with itself.
#
# NOTHING IS HARDCODED except one compile flag. For each DLL in fixes/:
#   - the carrier is read from the forwarders it exports  (X_real.<symbol>)
#   - the source is the file in fixes/ or tools/ that writes the log it names
#     (<name>.log)
#   - the export table is read from the DLL itself, so no game has to be
#     installed for this to run
# It then rebuilds from that source and compares.
#
# Builds are not bit-reproducible -- the linker stamps a fresh build id every
# time -- so the comparison is on what the source decides: the export table,
# exactly, and the set of long printable strings, which is where the messages,
# the hook names and the format strings live.
#
# Needs llvm-mingw (or any x86_64-w64-mingw32 toolchain), same as the build
# scripts. Without one it says so and stops rather than reporting everything
# clean, because "no compiler" and "no drift" must never look the same.
#
# After those, three checks that need no compiler: no bottle name of this Mac in
# anything published, the MGVF-GAME lines against process-features.json, and
# the copies inside a built MacGameFix.app against fixes/.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PE="$HERE/pe.py"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

MINGW_BIN="${MINGW_BIN:-$HOME/.local/cxge/toolchains/llvm-mingw/bin}"
CC=""
for c in "$MINGW_BIN/x86_64-w64-mingw32-clang" "$MINGW_BIN/x86_64-w64-mingw32-gcc" \
         "$(command -v x86_64-w64-mingw32-clang 2>/dev/null || true)" \
         "$(command -v x86_64-w64-mingw32-gcc 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { CC="$c"; break; }
done
[ -n "$CC" ] || {
  echo "error: no x86_64-w64-mingw32 compiler found." >&2
  echo "       set MINGW_BIN, or install llvm-mingw:" >&2
  echo "       https://github.com/mstorsjo/llvm-mingw/releases" >&2
  exit 2
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The one thing that cannot be read off a binary: ng4-observe.c compiles either
# as a probe or, with this flag, as the shipped repair. The DLL that ships is
# the repair.
flags_for() {
  case "$1" in
    ng4-observe.c) echo "-DNG4_FIX" ;;
    *)             echo "" ;;
  esac
}

# Strings the linker invents rather than the source: build ids, PDB names.
# Filtered so a fresh stamp does not read as a changed fix.
meaningful() {
  LC_ALL=C strings -a "$1" \
    | grep -aE '^[ -~]{12,}$' \
    | grep -avE 'RSDS|LLD PDB|\.pdb$' \
    | sort -u
}

drifted=0
checked=0
missing_source=0

for dll in "$HERE"/*.dll; do
  name="$(basename "$dll")"

  # Third-party binaries we redistribute rather than build. They cannot be
  # rebuilt from a source in this repository, so the proxy test below says
  # nothing useful about them -- and reported as unknown they read like drift.
  # What is checked instead is that they still hash to what was published.
  case "$name" in
    ng3-*.dll|mgvf-asf-reader.dll)
      case "$name" in
        ng3-*) record="$HERE/ng3-THIRD-PARTY-LICENCES.md" ;;
        *)     record="$HERE/mgvf-asf-reader-LICENCES.md" ;;
      esac
      want="$(grep -E "\`$name\`" "$record" 2>/dev/null | grep -oE '[0-9a-f]{64}' | tail -1)"
      have="$(shasum -a256 "$dll" | cut -d' ' -f1)"
      if [ -z "$want" ]; then
        printf '  %-32s ?  third-party, and no sha256 recorded for it\n' "$name"
      elif [ "$want" = "$have" ]; then
        printf '  %-32s ok   third-party, matches its recorded sha256\n' "$name"
      else
        printf '  %-32s DRIFTED  third-party, does not match its recorded sha256\n' "$name"
        # Counted. This used to set a variable the exit line never read, so a
        # third-party file that no longer hashed to its record still exited 0.
        drifted=$((drifted + 1))
      fi
      continue ;;
  esac

  stem="$(LC_ALL=C strings -a "$dll" | grep -aoE '^[A-Za-z0-9_]+_real\.' | head -1 | sed 's/_real\.$//')"
  mark="$(LC_ALL=C strings -a "$dll" | grep -aoE '[A-Za-z0-9_-]+\.log' | head -1)"
  if [ -z "$stem" ] || [ -z "$mark" ]; then
    printf '  %-32s ?  not a proxy of ours, or it names neither carrier nor log\n' "$name"
    continue
  fi

  # NINJA GAIDEN 4's fix is built from a probe kept in tools/ (flags_for).
  src=""
  for d in fixes tools; do
    for candidate in "$ROOT/$d"/*.c; do
      [ -f "$candidate" ] || continue
      LC_ALL=C grep -qaF "\"$mark\"" "$candidate" 2>/dev/null && { src="$candidate"; break 2; }
      LC_ALL=C grep -qaF "$mark" "$candidate" 2>/dev/null && { src="$candidate"; break 2; }
    done
  done
  if [ -z "$src" ]; then
    printf '  %-32s ?  names %s and no source writes that\n' "$name" "$mark"
    missing_source=$((missing_source + 1))
    continue
  fi

  out="$TMP/$name.d"; mkdir -p "$out"
  def="$out/$stem.def"
  {
    echo "LIBRARY $stem.dll"
    echo "EXPORTS"
    python3 "$PE" exports "$dll" --ordinals |
      while read -r ordinal sym; do
        printf '    %s = %s_real.%s @%s\n' "$sym" "$stem" "$sym" "$ordinal"
      done
  } > "$def"

  if ! "$CC" -shared -O2 $(flags_for "$(basename "$src")") -I"$HERE" \
        -o "$out/$stem.dll" "$src" "$def" \
        -Wl,--enable-stdcall-fixup \
        -lmfuuid -lole32 -luuid -lshlwapi -lkernel32 -static-libgcc 2>"$out/err"; then
    printf '  %-32s !! %s does not compile\n' "$name" "$(basename "$src")"
    [ "$VERBOSE" = 1 ] && sed 's/^/       /' "$out/err"
    drifted=$((drifted + 1)); continue
  fi

  checked=$((checked + 1))
  python3 "$PE" exports "$dll"           | sort > "$out/exp.old"
  python3 "$PE" exports "$out/$stem.dll" | sort > "$out/exp.new"
  meaningful "$dll"           > "$out/str.old"
  meaningful "$out/$stem.dll" > "$out/str.new"

  exp_delta="$(comm -3 "$out/exp.old" "$out/exp.new" | wc -l | tr -d ' ')"
  gone="$(comm -23 "$out/str.old" "$out/str.new")"
  came="$(comm -13 "$out/str.old" "$out/str.new")"
  n_gone="$(printf '%s' "$gone" | grep -c . )"
  n_came="$(printf '%s' "$came" | grep -c . )"

  if [ "$exp_delta" = 0 ] && [ "$n_gone" = 0 ] && [ "$n_came" = 0 ]; then
    printf '  %-32s ok   %s\n' "$name" "$(basename "$src")"
    continue
  fi

  drifted=$((drifted + 1))
  printf '  %-32s DRIFT  %s  (exports %s, strings -%s +%s)\n' \
    "$name" "$(basename "$src")" "$exp_delta" "$n_gone" "$n_came"
  if [ "$VERBOSE" = 1 ]; then
    printf '%s\n' "$gone" | grep . | head -8 | sed 's/^/       shipped only: /'
    printf '%s\n' "$came" | grep . | head -8 | sed 's/^/       source only:  /'
  fi
done

# Nobody else's bottle names in anything we ship.
#
# Bottle names are made up by whoever makes the bottle: ours are not a fact
# about anyone else's machine, and they are not ours to publish. They had leaked
# twice -- once into the wiki, once into comments inside installers that ship in
# the app -- so this reads the names actually on THIS machine and refuses to
# find them in anything that goes out.
#
# A bottle simply called "Steam" cannot be checked this way and is not: the word
# appears legitimately all over a project about Steam games. Names that are
# merely the default are not the ones that identify somebody's setup anyway.
echo
name_leak=0
while IFS= read -r root; do
  for b in "$root"/*/; do
    [ -d "$b" ] || continue
    n="$(basename "${b%/}")"
    [ ${#n} -gt 5 ] || continue
    case "$n" in Steam|steam) continue ;; esac
    hits="$(grep -rl -- "$n" "$HERE" "$ROOT/tools" "$ROOT/legacy" "$ROOT/README.md" \
              "$ROOT/process-features.json" "$ROOT"/app/*.swift "$ROOT"/app/*.sh 2>/dev/null \
            | grep -v '/check-builds\.sh$' || true)"
    [ -n "$hits" ] || continue
    echo "  bottle name leaked: \"$n\" appears in" >&2
    printf '%s\n' "$hits" | sed "s|$ROOT/|       |" >&2
    name_leak=1
  done
done < <(. "$HERE/bottles.sh"; bottle_roots)
[ "$name_leak" = 0 ] && echo "  no bottle name of this machine appears in anything shipped or published"

# The MGVF-GAME lines against the table.
#
# The app is built from both: build-app.sh takes every MGVF-GAME line of a
# folder installer and reads the rest of the row from process-features.json by
# executable. A line whose executable has no row is left out of the app with
# one line of build output, and a row no installer declares is never offered,
# so the two are compared here, where a mismatch is an error. The executable is
# the identity: there is no AppID anywhere here, and the folder name is
# Valve's to choose.
echo
decl_drift=0
if python3 - "$ROOT" <<'PY'
import json, re, sys, pathlib
root = pathlib.Path(sys.argv[1])
rows = json.loads((root/"process-features.json").read_text())["processes"]

got = {}
bad = []
for f in sorted((root/"fixes").glob("install-*.sh")):
    for line in re.findall(r'^# MGVF-GAME: (.+)$', f.read_text(), re.M):
        parts = [x.strip() for x in line.split("|")]
        name, exe = parts[0], (parts[1] if len(parts) > 1 else "")
        if exe in got:
            bad.append(f"{exe} is declared by both {got[exe][1]} and {f.name}")
        got[exe] = (name, f.name)

for exe, (name, script) in sorted(got.items()):
    row = rows.get(exe)
    if row is None:
        bad.append(f"{script} declares {name} ({exe}), and process-features.json has no row for it")
    elif row.get("title") != name:
        bad.append(f"{script} calls {exe} \"{name}\", process-features.json calls it \"{row.get('title')}\"")
for exe in sorted(set(rows) - set(got)):
    bad.append(f"process-features.json has {rows[exe].get('title')} ({exe}) and no installer declares it")

for b in bad:
    print(f"  declaration: {b}")
sys.exit(1 if bad else 0)
PY
then
  echo "  declarations: every MGVF-GAME line has its row in process-features.json, and every row its line"
else
  decl_drift=1
fi

# The other copy of every one of these: the app runs the copies in its bundle
# (or in a newer signed catalog), not these. A copy that differs from fixes/
# is an app built before the last change here.
echo
bundle="$ROOT/app/MacGameFix.app/Contents/Resources"
bundle_drift=0
if [ -d "$bundle" ]; then
  compared=0
  for f in "$HERE"/*.dll "$HERE"/install-*.sh "$HERE"/pe.pl "$HERE"/bottles.sh "$HERE"/sm2-shadertool \
           "$HERE"/*-LICENCES.md "$HERE"/*.recipes; do
    [ -f "$f" ] || continue
    b="$bundle/$(basename "$f")"
    [ -f "$b" ] || continue
    compared=$((compared + 1))
    cmp -s "$f" "$b" || { echo "  bundle stale: $(basename "$f")"; bundle_drift=$((bundle_drift + 1)); }
  done
  [ "$bundle_drift" = 0 ] && echo "  bundle: all $compared copies in MacGameFix.app match fixes/"
else
  echo "  bundle: app/MacGameFix.app is not built, so there is nothing to compare"
fi

echo
echo "  $checked rebuilt and compared, $drifted drifted, $missing_source unattributed"
[ "$drifted" = 0 ] && [ "$bundle_drift" = 0 ] && [ "$missing_source" = 0 ] \
  && [ "$decl_drift" = 0 ] && [ "$name_leak" = 0 ] || exit 1
exit 0
