#!/bin/bash
# Test for the FH6 exception chain carried by the proxy (fixes/fh6-d3d12/exception_chain.h).
#
#   /bin/bash engine/tests/fh6-exception-chain/run.sh
#
# The chain was engine patches 0023-0025 in MacGameFix's own ntdll.dll; the proxy now hooks it into the
# ntdll.dll CrossOver Preview 41303 ships. This runs the probe written for the patch,
# engine/sources/fh6-20261111/pe/exception_chain_probe.c, against that: a copy of the 41303 NotProton runner
# with CodeWeavers' own ntdll.dll and ntdll.so (MGVF_CHECK_RUNNER, MGVF_CHECK_STOCK, as build-engine.sh), and
# chaintest.dll, the hook on its own, exporting the counters the probe reads. Two changes to the probe, made
# here on a copy: it reads them from chaintest.dll, which it loads, instead of ntdll.dll; and a handler
# registered first sees the real exceptions only, not the links (the hook calls again only the handler that
# dealt with the previous one), so it counts handler calls less links.
#
# Without the switch (WINE_SOFTWARE_EXCEPTION_CHAIN unset, a program that is not FH6) the hook stays out and
# the probe passes as on a plain ntdll. With WINE_SOFTWARE_EXCEPTION_CHAIN=probe the hook goes in and the probe
# passes with 128,000 links in its sequential run.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fix="$here/../../../fixes/fh6-d3d12"; src="$here/../../sources/fh6-20261111/pe"
runner="${MGVF_CHECK_RUNNER:-$HOME/Library/Application Support/notproton/runners/crossover-27.0.0.41303-fex/CrossOver}"
stock="${MGVF_CHECK_STOCK:-$HOME/Library/Application Support/MacGameFix/engine-backup/CrossOver Preview.app-27.0.0.41303}"
cc="${LLVM_MINGW:-$HOME/.local/cxge/toolchains/llvm-mingw}/bin/x86_64-w64-mingw32-clang"
[ -x "$cc" ] || { echo "no llvm-mingw clang at $cc (LLVM_MINGW)"; exit 1; }
[ -f "$stock/x86_64-windows/ntdll.dll" ] && [ -f "$stock/x86_64-unix/ntdll.so" ] || { echo "no CodeWeavers ntdll in $stock (MGVF_CHECK_STOCK)"; exit 1; }
work="$(mktemp -d)"
server=""
trap '[ -z "$server" ] || WINEPREFIX="$work/pfx" "$server" -k 2>/dev/null || true; rm -rf "$work"' EXIT
cp -cR "$runner" "$work/runner"
cp "$stock/x86_64-unix/ntdll.so" "$work/runner/lib/wine/x86_64-unix/ntdll.so"
cp "$stock/x86_64-windows/ntdll.dll" "$work/runner/lib/wine/x86_64-windows/ntdll.dll"
wine="$work/runner/lib/wine/x86_64-unix/wine"; server="$work/runner/bin/wineserver-x86"
mkdir -p "$work/bin"
"$cc" -shared -O2 -Wall -I"$fix" -o "$work/bin/chaintest.dll" "$here/chaintest.c" "$here/chaintest.def" -lntdll
python3 -I - "$src/exception_chain_probe.c" "$work/probe.c" <<'PY'
import sys
s = open(sys.argv[1]).read()
n = s.count('GetModuleHandleA("ntdll.dll")')
assert n >= 10, n
s = s.replace('GetModuleHandleA("ntdll.dll")', 'chain_module()')
s = s.replace('#include <string.h>\n', '#include <string.h>\nstatic HMODULE chain_module(void){static HMODULE m;if(!m)m=LoadLibraryA("chaintest.dll");return m;}\n', 1)
old = 'if(first_handler_calls!=handler_calls)InterlockedIncrement(&failures);'
assert s.count(old) == 1
s = s.replace(old, 'if(first_handler_calls!=handler_calls-stats[1])InterlockedIncrement(&failures);')
open(sys.argv[2], 'w').write(s)
PY
"$cc" -O2 -I"$fix/exception_chain" -o "$work/bin/exception_chain_probe.exe" "$work/probe.c" "$src/exception_chain_probe.S"
export WINEPREFIX="$work/pfx" WINEDEBUG=-all WINELOADER="$wine" WINESERVER="$server"
"$wine" wineboot -i >/dev/null 2>&1; "$server" -w
status=0
run() {  # <label> <expected hook> <probe argument> [environment...]
    local label="$1" hook="$2" arg="$3" rc=0; shift 3
    echo "==> $label"
    ( cd "$work/bin" && env "$@" "$wine" exception_chain_probe.exe "$arg" ) > "$work/out.txt" 2>&1 || rc=$?
    "$server" -w
    /usr/bin/grep -E '^(HOOK|SEQUENTIAL|FALLBACKS|CONCURRENT|SUMMARY)' "$work/out.txt" || tail -5 "$work/out.txt"
    if [ "$rc" != 0 ] || ! /usr/bin/grep -q "^HOOK installed=$hook " "$work/out.txt"; then echo "    FAILED (exit $rc)"; status=1; fi
}
run "a program that is not FH6, no switch: the hook stays out" 0 disabled
run "WINE_SOFTWARE_EXCEPTION_CHAIN=probe: the hook goes in" 1 enabled \
    WINE_SOFTWARE_EXCEPTION_CHAIN=probe WINE_EXCEPTION_BURST_AUTO=probe WINE_SOFTWARE_BRIDGE_RESUME=1
[ $status = 0 ] && echo "==> passed" || echo "==> FAILED"
exit $status
