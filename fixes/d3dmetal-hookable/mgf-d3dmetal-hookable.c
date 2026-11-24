// mgf-d3dmetal-hookable: gives D3DMetal's method stubs a shape an inline hook can copy.
//
// A library NotProton loads into a game's Wine processes (a plugin row with inject = 1). It is
// built by build-d3dmetal-hookable.sh; check.c beside it is its test.
//
// D3DMetal 4's PE DLLs (dxgi.dll, d3d12.dll, ... in CrossOver's lib/apple_gptk) hand a program
// COM methods that are 16-byte stubs, written at run time into the DLL's .data:
//
//     66 90                 nop
//     FF 25 00 00 00 00     jmp [rip+0]
//     <8 bytes>             the method, a function inside D3DMetal.framework
//
// A mod that hooks such a method inline (an in-game overlay: it reads the method's address from
// a vtable, writes a jump over its first bytes and keeps a copy of them to call the original)
// copies the first two instructions somewhere else. The jump still says "the pointer right after
// me", and there it reads the copy's own next instruction. Seen with FC 27 Live Editor v27.2.0
// on 2026-11-23: an execute fault at 0x3C25FF, the bytes FF 25 3C 00 00 00 00 00 taken as an
// address, on the first ExecuteCommandLists after its hooks went in, and the game gone without a
// message. On Windows these methods start with ordinary code.
//
// This rewrites each stub in place, same 16 bytes, to code that can be copied anywhere:
//
//     48 B8 <8 bytes>       mov rax, method      (rax is free at a Win64 call)
//     FF E0                 jmp rax
//     CC CC CC CC
//
// It looks for stubs among the memory where Wine keeps DLLs and takes only those whose pointer
// lands inside D3DMetal. D3DMetal writes them as it goes, an interface at a time (FC 27: 1302
// of them in three bursts over the first 9 s), so it looks every half second for the first
// minute and a half after D3DMetal loads, and every 5 s after that. A pass read 40 to 75 MB in
// 13 to 55 ms in that game.
//
// The 16 bytes go in with one store. A thread inside the old stub at that very moment could
// still read the pointer's place after it changed; the window is the stub's two instructions
// (check.c: 300 million calls from another thread across a rewrite, none wrong).
//
// With the stubs rewritten, that mod's hooks went in and the game went on to its main menu
// with the mod's window on screen (2026-11-23, NotProton, CrossOver Preview 41303, Rosetta,
// D3DMetal 4). Not known: whether anything in D3DMetal reads its own stubs back.
//
// MGF_D3DM_HOOKABLE_LOG=<file> takes its notes; without it they go to stderr, which is the
// game's Wine log. An arm64 process gets an empty library: the stubs are x86-64 code.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#if defined(__x86_64__)
#include <dlfcn.h>
#include <emmintrin.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define TAG "mgf-d3dmetal-hookable"
// Where Wine on macOS maps DLLs, the builtin ones and D3DMetal's among them (seen: 0x6FFFE9...,
// 0x6FFFFD...).
#define LOW  0x6F0000000000ull
#define HIGH 0x700000000000ull

static const uint8_t OLD[8] = { 0x66, 0x90, 0xFF, 0x25, 0, 0, 0, 0 };
static FILE *out;
static unsigned long total;

static void say(const char *fmt, ...) {
  va_list ap; struct timespec ts; struct tm tm; char when[32];
  clock_gettime(CLOCK_REALTIME, &ts); localtime_r(&ts.tv_sec, &tm); strftime(when, sizeof when, "%H:%M:%S", &tm);
  fprintf(out, "%s.%03ld " TAG "[%d]: ", when, ts.tv_nsec / 1000000, getpid());
  va_start(ap, fmt); vfprintf(out, fmt, ap); va_end(ap);
  fputc('\n', out); fflush(out);
}

// MGF_D3DM_HOOKABLE_TEST=1, for the check beside this file: any function of any loaded image
// counts as D3DMetal's.
static int testing;

static int d3dmetal_loaded(void) {
  if (testing) return 1;
  for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
    const char *name = _dyld_get_image_name(i);
    if (name && strstr(name, "D3DMetal.framework/")) return 1;
  }
  return 0;
}

// The pointer is a function of D3DMetal's (or of libd3dshared beside it)?
static int in_d3dmetal(uint64_t p, const char **symbol) {
  Dl_info info;
  if (p < 0x10000 || !dladdr((void *)(uintptr_t)p, &info) || !info.dli_fname) return 0;
  if (!testing && !strstr(info.dli_fname, "D3DMetal.framework/") && !strstr(info.dli_fname, "libd3dshared")) return 0;
  *symbol = info.dli_sname ? info.dli_sname : "?";
  return 1;
}

static int rewrite(uint64_t at, uint64_t method) {
  uint8_t code[16] = { 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xE0, 0xCC, 0xCC, 0xCC, 0xCC };
  memcpy(code + 2, &method, 8);
  long page = sysconf(_SC_PAGESIZE);
  void *start = (void *)(uintptr_t)(at & ~(uint64_t)(page - 1));
  // Through mprotect and an ordinary store, never mach_vm_write: Rosetta has to see both, or it
  // goes on running its translation of the old stub. What the kernel says of the page cannot
  // be given back afterwards: Rosetta keeps a page it has translated read-only on its side to
  // catch such stores, so a stub in use reads "not writable" there whatever Wine asked for.
  // A page D3DMetal fills with code as it goes is readable, writable and executable to the
  // program already; asking for that again changes nothing for it.
  if (mprotect(start, page, PROT_READ | PROT_WRITE | PROT_EXEC)) return 0;
  if (memcmp((void *)(uintptr_t)at, OLD, 8) || memcmp((void *)(uintptr_t)(at + 8), &method, 8)) return 0;
  _mm_storeu_si128((__m128i *)(uintptr_t)at, _mm_loadu_si128((const __m128i *)code));
  return 1;
}

static unsigned scan(double *seconds, unsigned long *bytes) {
  static uint8_t buf[1 << 20];
  struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
  unsigned found = 0; *bytes = 0;
  mach_vm_address_t addr = LOW;
  while (addr < HIGH) {
    mach_vm_size_t size = 0; vm_region_basic_info_data_64_t info; mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    if (mach_vm_region(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) break;
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (addr >= HIGH) break;
    // The stubs are in a DLL's .data. Once one has run, the kernel shows its page as readable and
    // executable only (Rosetta's doing, see rewrite), so that is looked at too; constants are not.
    if ((info.protection & VM_PROT_READ) && (info.protection & (VM_PROT_WRITE | VM_PROT_EXECUTE))) {
      for (mach_vm_size_t off = 0; off < size; off += sizeof buf) {
        mach_vm_size_t want = size - off < sizeof buf ? size - off : sizeof buf, got = 0;
        if (mach_vm_read_overwrite(mach_task_self(), addr + off, want, (mach_vm_address_t)(uintptr_t)buf, &got) != KERN_SUCCESS) continue;
        *bytes += got;
        for (mach_vm_size_t i = 0; i + 16 <= got; i += 16) {
          if (buf[i] != 0x66 || memcmp(buf + i, OLD, 8)) continue;
          uint64_t method; memcpy(&method, buf + i + 8, 8);
          const char *symbol;
          if (!in_d3dmetal(method, &symbol)) continue;
          if (!rewrite(addr + off + i, method)) continue;
          found++; total++;
          if (strstr(symbol, "SwapChain4_Present") || strstr(symbol, "ExecuteCommandLists") || strstr(symbol, "ResizeBuffers"))
            say("stub at 0x%llx -> %s (0x%llx)", (unsigned long long)(addr + off + i), symbol, (unsigned long long)method);
        }
      }
    }
    addr += size;
  }
  clock_gettime(CLOCK_MONOTONIC, &b);
  *seconds = (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
  return found;
}

static void *work(void *arg) {
  (void)arg;
  sigset_t all; sigfillset(&all); pthread_sigmask(SIG_BLOCK, &all, NULL);   // Wine's signals are not for this thread
  pthread_setname_np(TAG);
  int seen = 0; unsigned passes = 0;
  for (;;) {
    // Half a second while the game starts and D3DMetal writes its stubs; 5 s once that is over.
    // MGF_D3DM_HOOKABLE_TEST keeps the short one: the check does not wait a minute and a half.
    usleep(seen && passes >= 180 && !testing ? 5000000 : 500000);
    if (!seen) {
      if (!d3dmetal_loaded()) continue;
      seen = 1;
      say("D3DMetal is loaded: looking for its method stubs");
    }
    double seconds; unsigned long bytes;
    unsigned found = scan(&seconds, &bytes);
    passes++;
    if (found || passes == 180)
      say("pass %u: %u stub(s) rewritten, %lu in all; read %lu MB in %.1f ms%s", passes, found, total, bytes >> 20, seconds * 1000,
          passes == 180 ? "; from here every 5 s" : "");
  }
  return NULL;
}

__attribute__((constructor))
static void hookable_init(void) {
  const char *test = getenv("MGF_D3DM_HOOKABLE_TEST");
  testing = test && !strcmp(test, "1");
  const char *path = getenv("MGF_D3DM_HOOKABLE_LOG");
  out = path && *path ? fopen(path, "a") : NULL;
  if (!out) out = stderr;
  pthread_t thread; pthread_attr_t attr;
  pthread_attr_init(&attr); pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  if (pthread_create(&thread, &attr, work, NULL)) say("no thread: nothing done");
  pthread_attr_destroy(&attr);
}
#endif
