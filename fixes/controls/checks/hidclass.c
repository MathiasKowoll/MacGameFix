/* A check for hidclass.c's arming: it maps the three modules in the order winedevice.exe has
 * them, ntoskrnl.exe, then hidclass.sys, then win32u.dll (which hidclass.sys needs, so the loader
 * maps it after), so that the library sees them as it does in a game.
 *
 * It only maps them; build-controls.sh then looks in the library's log for the line that says
 * the three exports hidclass.sys calls were taken. What the part does with them needs a pad that
 * winebus has opened, which no check has.
 * 0: the three were mapped. 1: one could not be; the line it prints says which.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#include <windows.h>
#include <stdio.h>

int main(void)
{
    static const char *const modules[] = {"C:\\windows\\system32\\ntoskrnl.exe",
                                          "C:\\windows\\system32\\drivers\\hidclass.sys",
                                          "C:\\windows\\system32\\win32u.dll"};
    unsigned i;

    if (GetModuleHandleA("win32u.dll")) return printf("win32u.dll is here already: the order cannot be checked\n"), 1;
    for (i = 0; i < sizeof(modules) / sizeof(modules[0]); i++)
        if (!LoadLibraryExA(modules[i], NULL, DONT_RESOLVE_DLL_REFERENCES))
            return printf("%s could not be mapped: %lu\n", modules[i], GetLastError()), 1;
    printf("ntoskrnl.exe, hidclass.sys and win32u.dll mapped, in that order\n");
    return 0;
}
