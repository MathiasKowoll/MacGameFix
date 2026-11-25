/* The check for mgf-timer-overflow.dylib: a Windows program, run under a NotProton runner.
 *
 * It makes a threadpool timer and sets none, so Wine's timer thread has no relative timer
 * pending and arms its own with rel_now - MAXLONGLONG, then sleeps 3 s and measures its own CPU
 * time. On a runner without patch 0021 the timer thread spins: most of a core. With the
 * library, or 0021, the process is idle.
 *
 * Prints the CPU time and exits 0 when it was under 0.3 s, 3 when it was more (spinning).
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <windows.h>
#include <stdio.h>

static void CALLBACK never_called(PTP_CALLBACK_INSTANCE instance, void *context, PTP_TIMER timer)
{
    (void)instance; (void)context; (void)timer;
}

static double cpu_seconds(void)
{
    FILETIME created, exited, kernel, user;
    ULARGE_INTEGER k, u;
    GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
    k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
    u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
    return (double)(k.QuadPart + u.QuadPart) / 1e7;
}

int main(void)
{
    PTP_TIMER timer = CreateThreadpoolTimer(never_called, NULL, NULL);
    double before, spent;

    if (!timer) { printf("FAIL: CreateThreadpoolTimer\n"); return 1; }
    Sleep(300);
    before = cpu_seconds();
    Sleep(3000);
    spent = cpu_seconds() - before;
    CloseThreadpoolTimer(timer);
    printf("%s: %.2f s of CPU in 3 s with a threadpool timer and none set\n", spent < 0.3 ? "ok" : "spinning", spent);
    return spent < 0.3 ? 0 : 3;
}
