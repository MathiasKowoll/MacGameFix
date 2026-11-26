# FH6 runtime integration, sourced by install-fh6-fix.sh.
# ntdll is owned by the existing Rosetta improvement, never a new section; on 41303 neither half is ours.
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
# On 41303 the exception chain is the proxy's (fh6-d3d12/exception_chain.h), hooked into the ntdll.dll
# NotProton ships, and played as well as MacGameFix's own (2026-11-25): the fix no longer puts an
# ntdll.dll anywhere, and the Wine modules leave the runner's to NotProton (engine-modules.sh). The
# copies an earlier install put in the game's runner copy and its prefix are taken out again. On 41073
# the pair stays as it was.
FH6_OWN_PE=1
[ "$FH6_BUILD" = 27.0.0.41303 ] && FH6_OWN_PE=0
# On 41303 the ntdll.so is NotProton's (CodeWeavers') as well: what MacGameFix's brought FH6 (0021,
# 0026 to 0029) comes from NotProton's Engine fixes row, which this fix switches on, and FH6 was
# played that way online (2026-11-25). The Wine modules leave the runner's to CodeWeavers', and one
# an earlier install put in the game's runner copy goes, the kept one back in its place.
FH6_OWN_UNIX=1
[ "$FH6_BUILD" = 27.0.0.41303 ] && FH6_OWN_UNIX=0
# ntdll.dll builds MacGameFix shipped before for 41303, which an update may replace like its own:
# 6664770a is 0023 + 0024, before 0025 put the chain's switches in the DLL; 0e5f9579 is 0025, before
# 0031 took the diagnostics' 40 MB out of the file for 2XKO (#117); fe379ae0 is that one, with 0031
# to 0035, before the modules were built again with 0038 to 0040, which gave 2d9b044e, and once
# more from a new tree with 0041. None of 0038 to 0041 touches ntdll.dll's source: a module built
# again is another file all the same, and this fix knows the file by its sha256.
FH6_PREVIOUS_PE="6664770a4c9fa70e0dbfbd28f0bb5af37754f84f708045b30c9b9fd4754f479b 0e5f9579d9a84396b1c5761a1b7bb9d6f46bb010a768f88316a34ed06a696b48 fe379ae00dade5fcc76863aadcf32b940e43f4b770d534814ff722b4f0ccfdc1 2d9b044ec764ffa76b7a11b15f5c567ebd0e9c0c2fa6a1af2feff759afd33c41"
fh6_pe_known() {
  fh6_pe_ok "$1" && return 0
  [ "$FH6_BUILD" = 27.0.0.41303 ] && [ -f "$1" ] && case " $FH6_PREVIOUS_PE " in *" $(fh6sha "$1") "*) return 0 ;; esac
  return 1
}
# The ntdll.dll builds with 0025, which need no chain variables in the launch options: 0025's own,
# the one with 0031 to 0035 (#117), which keeps the chain as it was, and the two builds after it
# (0038 to 0040, then 0041), which change nothing in ntdll.dll.
FH6_CHAIN_IN_NTDLL="0e5f9579d9a84396b1c5761a1b7bb9d6f46bb010a768f88316a34ed06a696b48 fe379ae00dade5fcc76863aadcf32b940e43f4b770d534814ff722b4f0ccfdc1 2d9b044ec764ffa76b7a11b15f5c567ebd0e9c0c2fa6a1af2feff759afd33c41 4694a475c8a5ded68d4c9fde5cfd3dacd54368f3615978c5a19428755b4cc25e"
fh6_chain_in_ntdll() { case " $FH6_CHAIN_IN_NTDLL " in *" $BASELINE_PE "*) echo 1 ;; *) echo 0 ;; esac; }
fh6_unix_ok() {
  [ -f "$1" ] && { { [ -n "$BASELINE_UNIX" ] && [ "$(fh6sha "$1")" = "$BASELINE_UNIX" ]; } || { [ -f "$NT_UNIX" ] && cmp -s "$1" "$NT_UNIX"; }; }
}
fh6_runtime_ok() {
  local root="${CLONE:-$RUNNER}"
  if [ "$FH6_OWN_PE" = 0 ]; then
    # No ntdll.dll of ours left where the game runs, and the modules' ntdll.so only where this
    # runner still takes it.
    if [ "$FH6_OWN_UNIX" = 0 ]; then ! fh6_unix_ok "$root/lib/wine/x86_64-unix/ntdll.so" || return 1
    else fh6_unix_ok "$root/lib/wine/x86_64-unix/ntdll.so" || return 1; fi
    ! fh6_pe_known "$root/lib/wine/x86_64-windows/ntdll.dll" && ! fh6_pe_known "$SYS/ntdll.dll"
    return
  fi
  fh6_pe_ok "$root/lib/wine/x86_64-windows/ntdll.dll" && fh6_unix_ok "$root/lib/wine/x86_64-unix/ntdll.so" && fh6_pe_ok "$SYS/ntdll.dll"
}
# Where an earlier install put an ntdll.dll of ours, the runner's own goes back: the one kept beside it,
# or, for the game's runner copy, the runner's (by then NotProton's: the modules retire theirs first).
fh6_pe_out() {  # <live file> <the runner's own file>
  local live="$1" own="$2"
  fh6_pe_known "$live" || { rm -f "$live.mgf-fh6-original"; return 0; }
  if [ -f "$live.mgf-fh6-original" ] && ! fh6_pe_known "$live.mgf-fh6-original"; then mv -f "$live.mgf-fh6-original" "$live"
  elif [ -f "$own" ] && ! fh6_pe_known "$own"; then cp -p "$own" "$live.mgf-new" && mv -f "$live.mgf-new" "$live"
  else echo "error: no ntdll.dll of the runner's own to put back in place of $live" >&2; return 1; fi
}
# The same for an ntdll.so of ours in the game's runner copy (41303).
fh6_unix_out() {  # <live file> <the runner's own file>
  local live="$1" own="$2"
  fh6_unix_ok "$live" || { rm -f "$live.mgf-fh6-original"; return 0; }
  if [ -f "$live.mgf-fh6-original" ] && ! fh6_unix_ok "$live.mgf-fh6-original"; then mv -f "$live.mgf-fh6-original" "$live"
  elif [ -f "$own" ] && ! fh6_unix_ok "$own"; then cp -p "$own" "$live.mgf-new" && mv -f "$live.mgf-new" "$live"
  else echo "error: no ntdll.so of the runner's own to put back in place of $live" >&2; return 1; fi
}
fh6_options() { MGF_FH6_CHAIN_IN_NTDLL="$(fh6_chain_in_ntdll)" /usr/bin/perl "$HERE/fh6-launch-options.pl" "$1" "$PFX"; }
fh6_preflight() {
  [ -n "$FH6_BUILD" ] || {
    echo 'error: FH6 requires the standard NotProton runner for CrossOver Preview 27.0.0.41073 or 27.0.0.41303, using Rosetta.' >&2; return 1; }
  [ "$(fh6sha "$GAME/forzahorizon6.exe")" = "$GAME_SHA" ] || { echo 'error: this FH6 executable has not been validated for this runtime. Nothing changed.' >&2; return 1; }
  { [ "$FH6_OWN_UNIX" = 0 ] || [ -f "$NT_UNIX" ]; } && { [ "$FH6_OWN_PE" = 0 ] || fh6_pe_ok "$NT_DLL"; } || { echo 'error: download this prerelease’s Wine modules in Improvements first.' >&2; return 1; }
  # All runtime copies must be backed up before an update. Unknown copies are not overwritten.
  local root f live stock
  for root in "$RUNNER" ${CLONE:+"$CLONE"}; do
    for f in x86_64-windows/ntdll.dll x86_64-unix/ntdll.so; do
      live="$root/lib/wine/$f"; stock="$live.mgf-fh6-original"
      [ -f "$live" ] || return 1
      [ "$FH6_OWN_PE" = 0 ] && [ "$f" = x86_64-windows/ntdll.dll ] && continue
      [ "$FH6_OWN_UNIX" = 0 ] && [ "$f" = x86_64-unix/ntdll.so ] && continue
      if [ -f "$stock" ]; then
        case "$f" in *dll) fh6_pe_known "$live" ;; *) fh6_unix_ok "$live" ;; esac || { echo "error: $live changed outside MacGameFix; it stays." >&2; return 1; }
      fi
    done
  done
  if [ "$FH6_OWN_PE" = 1 ] && [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_known "$SYS/ntdll.dll" || return 1; fi
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
  # On 41303 the same run retires the modules' Intel-side ntdll.so from the runner. A runner whose
  # Rosetta part is all left to NotProton and CodeWeavers has nothing to install: nomodules, not a failure.
  if [ -f "$MODULES/engine-modules.sh" ]; then
    /bin/bash "$MODULES/engine-modules.sh" "$RUNNER" --part=rosetta \
      || [ "$(/bin/bash "$MODULES/engine-modules.sh" "$RUNNER" --status --part=rosetta 2>/dev/null | tail -1)" = nomodules ] || return 1
  fi
  if [ "$FH6_OWN_PE" = 0 ]; then
    if [ -n "$CLONE" ]; then
      fh6_pe_out "$CLONE/lib/wine/x86_64-windows/ntdll.dll" "$RUNNER/lib/wine/x86_64-windows/ntdll.dll" || return 1
      if [ "$FH6_OWN_UNIX" = 0 ]; then
        fh6_unix_out "$CLONE/lib/wine/x86_64-unix/ntdll.so" "$RUNNER/lib/wine/x86_64-unix/ntdll.so" || return 1
      else
        fh6_put "$NT_UNIX" "$CLONE/lib/wine/x86_64-unix/ntdll.so"
      fi
    fi
    fh6_pe_out "$SYS/ntdll.dll" "$RUNNER/lib/wine/x86_64-windows/ntdll.dll" || return 1
  else
    if [ -n "$CLONE" ]; then
      fh6_put "$NT_DLL" "$CLONE/lib/wine/x86_64-windows/ntdll.dll"
      fh6_put "$NT_UNIX" "$CLONE/lib/wine/x86_64-unix/ntdll.so"
    fi
    fh6_put "$NT_DLL" "$SYS/ntdll.dll"
  fi
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
description = Raises Rosetta exception delivery priority for the FH6 profile
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
      [ "$FH6_OWN_PE" = 0 ] && [ "$f" = x86_64-windows/ntdll.dll ] && continue   # none of ours there
      [ "$FH6_OWN_UNIX" = 0 ] && [ "$f" = x86_64-unix/ntdll.so ] && { fh6_unix_out "$live" "$RUNNER/lib/wine/$f" || return 1; continue; }
      if [ -f "$live.mgf-fh6-original" ]; then
        case "$f" in *dll) fh6_pe_ok "$live" ;; *) fh6_unix_ok "$live" ;; esac || return 1
        mv -f "$live.mgf-fh6-original" "$live"
      fi
    done
  done
  if [ "$FH6_OWN_PE" = 1 ] && [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_ok "$SYS/ntdll.dll" || return 1; mv -f "$SYS/ntdll.dll.mgf-fh6-original" "$SYS/ntdll.dll"; fi
}
