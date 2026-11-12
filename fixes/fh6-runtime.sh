# FH6 runtime integration, sourced by install-fh6-fix.sh.
# ntdll is owned by the existing Rosetta improvement, never a new section.
# SPDX-License-Identifier: GPL-3.0-or-later
MODULES="${MGVF_MODULES:-$HERE}"
GAME_SHA=63791d0b686186c23ade10a1ae02efd785045bd818cc89816f472cad9a69fcb9
fh6sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
# The NotProton runners whose Wine modules carry FH6's ntdll pair (ntdll.so with ntdll.dll):
# Preview 41073's, the retained baseline, and 41303's, the same dispatcher built from
# engine/patches/wine-11.21's 0023. The pair is the one the modules catalog has for that
# build. On 41073 the installed baseline's ad hoc ntdll.so is accepted as well.
case "$RUNNER" in
  */runners/crossover-27.0.0.41073/CrossOver|*/runners/crossover-27.0.0.41073-fex/CrossOver) FH6_BUILD=27.0.0.41073 ;;
  */runners/crossover-27.0.0.41303/CrossOver|*/runners/crossover-27.0.0.41303-fex/CrossOver) FH6_BUILD=27.0.0.41303 ;;
  *) FH6_BUILD="" ;;
esac
NT_DLL="$MODULES/engine-${FH6_BUILD:-none}-x86_64-windows-ntdll.dll"
NT_UNIX="$MODULES/engine-${FH6_BUILD:-none}-x86_64-unix-ntdll.so"
BASELINE_PE="$(fh6sha "$NT_DLL")"
BASELINE_UNIX=""
[ "$FH6_BUILD" = 27.0.0.41073 ] && BASELINE_UNIX=dd6ef76ff8d51da5e2d246bdb7432a6c0b110668d742b1937e82ffcbb05d3ea0
fh6_pe_ok() { [ -f "$1" ] && [ -n "$BASELINE_PE" ] && [ "$(fh6sha "$1")" = "$BASELINE_PE" ]; }
# ntdll.dll builds MacGameFix shipped before for 41303, which an update may replace like its own:
# 6664770a is 0023 + 0024, before 0025 put the chain's switches in the DLL.
FH6_PREVIOUS_PE="6664770a4c9fa70e0dbfbd28f0bb5af37754f84f708045b30c9b9fd4754f479b"
fh6_pe_known() {
  fh6_pe_ok "$1" && return 0
  [ "$FH6_BUILD" = 27.0.0.41303 ] && [ -f "$1" ] && case " $FH6_PREVIOUS_PE " in *" $(fh6sha "$1") "*) return 0 ;; esac
  return 1
}
# The ntdll.dll builds with 0025, which need no chain variables in the launch options.
FH6_CHAIN_IN_NTDLL="0e5f9579d9a84396b1c5761a1b7bb9d6f46bb010a768f88316a34ed06a696b48"
fh6_chain_in_ntdll() { case " $FH6_CHAIN_IN_NTDLL " in *" $BASELINE_PE "*) echo 1 ;; *) echo 0 ;; esac; }
fh6_unix_ok() {
  [ -f "$1" ] && { { [ -n "$BASELINE_UNIX" ] && [ "$(fh6sha "$1")" = "$BASELINE_UNIX" ]; } || { [ -f "$NT_UNIX" ] && cmp -s "$1" "$NT_UNIX"; }; }
}
fh6_runtime_ok() {
  local root="${CLONE:-$RUNNER}"
  fh6_pe_ok "$root/lib/wine/x86_64-windows/ntdll.dll" && fh6_unix_ok "$root/lib/wine/x86_64-unix/ntdll.so" && fh6_pe_ok "$SYS/ntdll.dll"
}
fh6_options() { MGF_FH6_CHAIN_IN_NTDLL="$(fh6_chain_in_ntdll)" /usr/bin/perl "$HERE/fh6-launch-options.pl" "$1" "$PFX"; }
fh6_preflight() {
  [ -n "$FH6_BUILD" ] || {
    echo 'error: FH6 WIP requires the standard NotProton runner for CrossOver Preview 27.0.0.41073 or 27.0.0.41303, using Rosetta.' >&2; return 1; }
  [ "$(fh6sha "$GAME/forzahorizon6.exe")" = "$GAME_SHA" ] || { echo 'error: this FH6 executable has not been validated for the WIP runtime. Nothing changed.' >&2; return 1; }
  fh6_pe_ok "$NT_DLL" && [ -f "$NT_UNIX" ] || { echo 'error: download this prerelease’s Wine modules in Improvements first.' >&2; return 1; }
  # All runtime copies must be backed up before an update. Unknown copies are not overwritten.
  local root f live stock
  for root in "$RUNNER" ${CLONE:+"$CLONE"}; do
    for f in x86_64-windows/ntdll.dll x86_64-unix/ntdll.so; do
      live="$root/lib/wine/$f"; stock="$live.mgf-fh6-original"
      [ -f "$live" ] || return 1
      if [ -f "$stock" ]; then
        case "$f" in *dll) fh6_pe_known "$live" ;; *) fh6_unix_ok "$live" ;; esac || { echo "error: $live changed outside MacGameFix; it stays." >&2; return 1; }
      fi
    done
  done
  if [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_known "$SYS/ntdll.dll" || return 1; fi
  fh6_options preflight
}
fh6_put() {
  local src="$1" dest="$2"
  cmp -s "$src" "$dest" && return 0
  # A validated ad-hoc library is already the same baseline. Signing the distribution copy
  # changes its file hash, not its code; leave the installed experiment intact.
  case "$dest" in */ntdll.so) fh6_unix_ok "$dest" && return 0 ;; esac
  [ -f "$dest.mgf-fh6-original" ] || cp -p "$dest" "$dest.mgf-fh6-original"
  cp -p "$src" "$dest.mgf-new" && mv -f "$dest.mgf-new" "$dest"
}
fh6_install_runtime() {
  # Stage the matching pair via the existing Rosetta installer; prefixes and per-game
  # launch clones are coordinated here because the generic installer does not own them.
  /bin/bash "$MODULES/engine-modules.sh" "$RUNNER" --part=rosetta
  if [ -n "$CLONE" ]; then
    fh6_put "$NT_DLL" "$CLONE/lib/wine/x86_64-windows/ntdll.dll"
    fh6_put "$NT_UNIX" "$CLONE/lib/wine/x86_64-unix/ntdll.so"
  fi
  fh6_put "$NT_DLL" "$SYS/ntdll.dll"
  local plugins="$HOME/Library/Application Support/notproton/plugins"
  mkdir -p "$plugins"
  # Keep an existing user plugin; our descriptor is only needed on a fresh installation. An
  # earlier MacGameFix build of the plugin (28315251, with the census and syscall reporting) is
  # replaced by the quiet one beside this installer.
  local live="$plugins/notproton-rosetta-trap-boost.dylib"
  if [ -f "$plugins/rosetta-trap-boost.conf" ] && [ -f "$live" ] \
     && [ "$(fh6sha "$live")" = 28315251485196c816b3579c90a8e9fa81a4bb7b9b61d87c4269c8972c9f4197 ]; then
    cp -p "$HERE/notproton-rosetta-trap-boost.dylib" "$live.mgf-new" && mv -f "$live.mgf-new" "$live"
  fi
  if [ ! -f "$plugins/rosetta-trap-boost.conf" ]; then
    cp -p "$HERE/notproton-rosetta-trap-boost.dylib" "$plugins/notproton-rosetta-trap-boost.dylib"
    cat > "$plugins/rosetta-trap-boost.conf" <<'CONF'
[NOTPROTON_ROSETTA_TRAP_BOOST]
label = Rosetta exception priority
description = Raises Rosetta exception delivery priority for the FH6 WIP profile
section = dev
on = 1
inject = 1
requires = Library/Application Support/notproton/plugins/notproton-rosetta-trap-boost.dylib
CONF
  fi
  fh6_options install
}
fh6_restore_runtime() {
  # Runtime improvement is shared by other games; removing a game fix never switches
  # it off globally. Only restore the prefix/clone copies actually backed up here.
  local root f live
  for root in ${CLONE:+"$CLONE"}; do
    for f in x86_64-windows/ntdll.dll x86_64-unix/ntdll.so; do
      live="$root/lib/wine/$f"
      if [ -f "$live.mgf-fh6-original" ]; then
        case "$f" in *dll) fh6_pe_ok "$live" ;; *) fh6_unix_ok "$live" ;; esac || return 1
        mv -f "$live.mgf-fh6-original" "$live"
      fi
    done
  done
  if [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_ok "$SYS/ntdll.dll" || return 1; mv -f "$SYS/ntdll.dll.mgf-fh6-original" "$SYS/ntdll.dll"; fi
}
