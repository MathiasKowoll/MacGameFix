/* The FH6 exception chain's hook (fixes/fh6-d3d12/exception_chain.h) on its own, for run.sh: a DLL that
 * installs it when loaded and exports the chain's counters and diagnostics under the names the patched
 * ntdll.dll gave them, so exception_chain_probe.c reads them here.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later */
#define CHAIN_DIAGNOSTICS 1
#include "exception_chain.h"
#include <stdio.h>

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        HMODULE pinned; const char *why;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCWSTR)(void *)DllMain, &pinned);
        printf("HOOK installed=%d %s\n", chain_install(&why), why);
        fflush(stdout);
    }
    return TRUE;
}
