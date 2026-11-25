/* The check for mgf-package-family.dylib: a Windows program, run under a NotProton runner.
 *
 * It looks FindPackagesByPackageFamily up in kernel32.dll, as EA SPORTS FC 27 does, and calls
 * it: with the library it is found and answers no packages; without it, on a runner with
 * CrossOver's own kernel32.dll, it is not found. It also looks up and calls two of kernel32's
 * forwards (HeapAlloc to ntdll, GetPackagesByPackageFamily to kernelbase), which the library's
 * new export table must still resolve, and an ordinary export.
 *
 * Prints one line per check and exits 0 when the function was found and answered right, 2
 * when it was not found, 1 on anything wrong.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <windows.h>
#include <stdio.h>

typedef LONG (WINAPI *find_fn)(const WCHAR *, UINT32, UINT32 *, WCHAR **, UINT32 *, WCHAR *, UINT32 *);
typedef LONG (WINAPI *get_fn)(const WCHAR *, UINT32 *, WCHAR **, UINT32 *, WCHAR *);
typedef void *(WINAPI *heap_alloc_fn)(HANDLE, DWORD, SIZE_T);

int main(void)
{
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    heap_alloc_fn heap_alloc = (heap_alloc_fn)GetProcAddress(k32, "HeapAlloc");
    get_fn get = (get_fn)GetProcAddress(k32, "GetPackagesByPackageFamily");
    FARPROC tick = GetProcAddress(k32, "GetTickCount");
    find_fn find = (find_fn)GetProcAddress(k32, "FindPackagesByPackageFamily");
    UINT32 count = 7, len = 7;
    void *p;
    LONG r;

    if (!heap_alloc || !(p = heap_alloc(GetProcessHeap(), 0, 16))) { printf("FAIL: HeapAlloc, a forward to ntdll\n"); return 1; }
    printf("ok: HeapAlloc, a forward to ntdll, found and called\n");
    if (!get || get(L"x_y", &count, NULL, &len, NULL) != ERROR_SUCCESS || count || len)
    { printf("FAIL: GetPackagesByPackageFamily, a forward to kernelbase\n"); return 1; }
    printf("ok: GetPackagesByPackageFamily, a forward to kernelbase, found and called\n");
    if (!tick) { printf("FAIL: GetTickCount\n"); return 1; }
    printf("ok: GetTickCount found\n");
    if (!find) { printf("not found: FindPackagesByPackageFamily\n"); return 2; }
    count = len = 7;
    r = find(L"x_y", 0, &count, NULL, &len, NULL, NULL);
    if (r != ERROR_SUCCESS || count || len) { printf("FAIL: FindPackagesByPackageFamily answered %ld, count %u, len %u\n", r, count, len); return 1; }
    if (find(L"x_y", 0, NULL, NULL, &len, NULL, NULL) != ERROR_INVALID_PARAMETER
        || find(L"x_y", 0, &count, NULL, NULL, NULL, NULL) != ERROR_INVALID_PARAMETER)
    { printf("FAIL: FindPackagesByPackageFamily without count or buffer_len\n"); return 1; }
    printf("ok: FindPackagesByPackageFamily found: no packages, ERROR_SUCCESS; ERROR_INVALID_PARAMETER without count or buffer_len\n");
    return 0;
}
