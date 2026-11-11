// stride_math.h: host-independent descriptor-handle translation math (no Windows / D3D12 types).
// A "fake" heap presents descriptors at fake_inc bytes apart starting at fake_cpu / fake_gpu; the real heap has them
// real_inc apart starting at real_cpu / real_gpu. A handle inside a fake range maps to real_start + index*real_inc.
#ifndef STRIDE_MATH_H
#define STRIDE_MATH_H
#include <stdint.h>

typedef struct { uint64_t real_cpu, real_gpu, fake_cpu, fake_gpu; uint32_t n; } sm_heap;
enum { SM_PASS = 0, SM_OK = 1, SM_CLAMPED = 2, SM_MISALIGNED = 3 };   // status of one translation (SM_MISALIGNED also translates, rounding down)

// h: handle value; gpu: 0 = CPU handle, 1 = GPU handle. Range checked is [fake, fake + n*fake_inc] (one past the end is legal).
// A zero fake base marks a dead entry and never matches.
static inline uint64_t sm_xlat(const sm_heap *hp, int nh, int gpu, uint64_t h, uint32_t fake_inc, uint32_t real_inc, int *st)
{
    int i;
    if (st) *st = SM_PASS;
    if (!h) return h;
    for (i = 0; i < nh; i++) {
        uint64_t fb = gpu ? hp[i].fake_gpu : hp[i].fake_cpu;
        uint64_t rb = gpu ? hp[i].real_gpu : hp[i].real_cpu;
        uint64_t span = (uint64_t)hp[i].n * fake_inc;
        if (!fb || h < fb || h > fb + span) continue;
        {
            uint64_t off = h - fb, idx = off / fake_inc; int s = SM_OK;
            if (off % fake_inc) s = SM_MISALIGNED;
            if (idx > hp[i].n) { idx = hp[i].n; s = SM_CLAMPED; }
            if (st) *st = s;
            return rb + idx * real_inc;
        }
    }
    return h;
}
#endif
