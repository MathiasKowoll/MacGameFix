// A check for mgf-d3dmetal-hookable.dylib, x86_64 under Rosetta: a stub of D3DMetal's shape in
// writable memory where Wine keeps DLLs, called before and after the rewrite, and then hooked
// the way the overlay that crashed does it (first instructions copied, a jump back after them).
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>

__attribute__((noinline, ms_abi)) static int method(int a, int b) { return a * 100 + b; }
typedef int (__attribute__((ms_abi)) *method_fn)(int, int);

static volatile int stop; static volatile unsigned long calls, wrong;
static method_fn hot;
static void *caller(void *arg) { (void)arg; while (!stop) { if (hot(3, 7) != 307) wrong++; calls++; } return NULL; }

int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  uint8_t *at = mmap((void *)0x6FFFE0000000ull, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
  if (at == MAP_FAILED) { perror("mmap"); return 2; }
  uint8_t *stub = at + 0x80, *tramp = at + 0x1000;
  uint64_t target = (uint64_t)(uintptr_t)method;
  const uint8_t old[8] = { 0x66, 0x90, 0xFF, 0x25, 0, 0, 0, 0 };
  memcpy(stub, old, 8); memcpy(stub + 8, &target, 8);
  hot = (method_fn)(uintptr_t)stub;
  int fail = 0;
  if (hot(1, 2) != 102) { printf("FAIL: the old stub does not work here\n"); return 2; }
  // The overlay's way on the OLD stub, to see the fault's cause: copy 8 bytes, the jump reads what follows.
  pthread_t t; pthread_create(&t, NULL, caller, NULL);   // a thread calling it all along
  for (int i = 0; i < 50 && stub[0] == 0x66; i++) usleep(100000);
  usleep(300000); stop = 1; pthread_join(t, NULL);
  const uint8_t want[2] = { 0x48, 0xB8 };
  if (memcmp(stub, want, 2) || memcmp(stub + 2, &target, 8) || stub[10] != 0xFF || stub[11] != 0xE0) { printf("FAIL: the stub was not rewritten\n"); fail = 1; }
  else printf("ok: rewritten in place\n");
  printf("%s: %lu calls from another thread across the rewrite, %lu wrong\n", wrong ? "FAIL" : "ok", calls, wrong); fail |= wrong != 0;
  if (hot(4, 5) != 405) { printf("FAIL: the new stub returns something else\n"); fail = 1; } else printf("ok: the new stub calls the method\n");
  // Hook it as the overlay does: the first instruction (10 bytes) copied, then jmp [rip+0] back to stub+10.
  memcpy(tramp, stub, 10);
  const uint8_t back[6] = { 0xFF, 0x25, 0, 0, 0, 0 }; uint64_t rest = (uint64_t)(uintptr_t)(stub + 10);
  memcpy(tramp + 10, back, 6); memcpy(tramp + 16, &rest, 8);
  // and the jump over the stub's first bytes, to the copy (standing in for the hook, which calls the original).
  uint8_t jump[5] = { 0xE9 }; int32_t rel = (int32_t)(tramp - (stub + 5)); memcpy(jump + 1, &rel, 4);
  memcpy(stub, jump, 5);
  if (hot(6, 8) != 608) { printf("FAIL: hooked, the original is not reached\n"); fail = 1; } else printf("ok: hooked through a copied first instruction, the original is reached\n");
  return fail;
}
