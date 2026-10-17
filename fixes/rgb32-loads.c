/*
 * rgb32-loads.c -- rewrite a shader's load from a three-float buffer view into
 * three one-float loads, for a view recreated as R32_FLOAT three times as long.
 *
 * Neither D3DMetal nor DXMT reads a DXGI_FORMAT_R32G32B32_FLOAT typed buffer
 * view as D3D does: Metal has no three-float texel format, and D3DMetal serves
 * the view as two floats an element, DXMT as one (legacy/wiki/Mortal-Kombat-11.md).
 * Both read an R32_FLOAT view correctly. So a fix creates the view as R32_FLOAT,
 * FirstElement * 3 and NumElements * 3, and has the shader read element a as the
 * floats 3a, 3a+1 and 3a+2:
 *
 *     ld_indexable(buffer) r0.xzw, r0.xxxx, t1.xzyw
 *  becomes
 *     imad r2.xyz, r0.xxxx, l(3, 3, 3, 3), l(0, 1, 2, 0)
 *     ld_indexable(buffer) r0.x, r2.xxxx, t1.xxxx
 *     ld_indexable(buffer) r0.z, r2.yyyy, t1.xxxx
 *     ld_indexable(buffer) r0.w, r2.zzzz, t1.xxxx
 *
 * with one more temporary register declared. It works on the game's own
 * bytecode as the game hands it over, so no game data ships with a fix. Anything
 * it does not expect -- a second load from the view, a relative index, an
 * address that is not a plain operand, a read of the fourth component -- makes it
 * give up and leave the shader as it is.
 *
 * Needs dxbc-checksum.c included before it.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <stdlib.h>

static uint32_t rgb32_rd32(const unsigned char *p) { uint32_t v; memcpy(&v, p, 4); return v; }

/* The data of the container's chunk with this tag, or NULL. */
static const unsigned char *dxbc_chunk(const unsigned char *d, size_t len, const char *tag, uint32_t *size)
{
    uint32_t n, i;
    if (len < 32 || memcmp(d, "DXBC", 4) || rgb32_rd32(d + 24) > len) return NULL;
    n = rgb32_rd32(d + 28);
    if (n > 64 || 32 + 4 * (size_t)n > len) return NULL;
    for (i = 0; i < n; i++)
    {
        uint32_t o = rgb32_rd32(d + 32 + 4 * i);
        if ((size_t)o + 8 > len) return NULL;
        if (!memcmp(d + o, tag, 4))
        {
            *size = rgb32_rd32(d + o + 4);
            return (size_t)o + 8 + *size <= len ? d + o + 8 : NULL;
        }
    }
    return NULL;
}

/* The register of the shader resource called `name`, if it is a three-float
 * typed buffer (Buffer<float3>); -1 if there is none, -2 if it is something else. */
static int rdef_float3_buffer(const unsigned char *d, size_t len, const char *name)
{
    uint32_t size, nbind, bindoff, version, stride, i;
    const unsigned char *r = dxbc_chunk(d, len, "RDEF", &size);
    size_t nlen = strlen(name);
    if (!r || size < 28) return -1;
    nbind = rgb32_rd32(r + 8); bindoff = rgb32_rd32(r + 12); version = rgb32_rd32(r + 16);
    stride = (version & 0xffff) >= 0x0501 ? 40 : 32;
    if (nbind > 4096 || (size_t)bindoff + (size_t)nbind * stride > size) return -1;
    for (i = 0; i < nbind; i++)
    {
        const unsigned char *b = r + bindoff + i * stride;
        uint32_t no = rgb32_rd32(b);
        if ((size_t)no + nlen + 1 > size || memcmp(r + no, name, nlen + 1)) continue;
        /* type 2 = texture, return type 5 = float, dimension 1 = buffer, 3 components */
        if (rgb32_rd32(b + 4) == 2 && rgb32_rd32(b + 8) == 5 && rgb32_rd32(b + 12) == 1 && rgb32_rd32(b + 24) == 1
                && ((rgb32_rd32(b + 28) >> 2) & 3) + 1 == 3)
            return (int)rgb32_rd32(b + 20);
        return -2;
    }
    return -1;
}

/* Tokens an operand takes, or 0 for an encoding not handled here. */
static unsigned operand_tokens(const uint32_t *t, unsigned left)
{
    unsigned n = 1, type, dim, i;
    if (!left) return 0;
    if (t[0] >> 31) n++;
    type = (t[0] >> 12) & 0xff;
    if (type == 4) n += (t[0] & 3) == 2 ? 4 : 1;         /* immediate32 */
    else if (type == 5) n += (t[0] & 3) == 2 ? 8 : 2;    /* immediate64 */
    else
    {
        dim = (t[0] >> 20) & 3;
        for (i = 0; i < dim; i++)
        {
            unsigned rep = (t[0] >> (22 + 3 * i)) & 7;
            if (rep == 0) n += 1;
            else if (rep == 1) n += 2;
            else return 0;                               /* a relative index */
        }
    }
    return n <= left ? n : 0;
}

/* The rewritten container (malloc'd, checksum written) and its size, or NULL
 * with the reason in *why. */
static void *rgb32_rewrite(const void *code, size_t len, int reg, size_t *out_len, const char **why)
{
    const unsigned char *d = code, *shex;
    uint32_t shex_size, nch, i, o;
    const uint32_t *t;
    uint32_t *nt;
    unsigned nt_n = 0, k, ntok, temps_at = 0, hits = 0, loads = 0;
    unsigned char *out;
    size_t out_size;

    *why = "not a DXBC container";
    if (!(shex = dxbc_chunk(d, len, "SHEX", &shex_size))) return NULL;
    *why = "malformed shader code";
    if (shex_size < 8 || shex_size % 4) return NULL;
    t = (const uint32_t *)shex;          /* chunk data is 4-byte aligned in the container */
    ntok = shex_size / 4;
    if (t[1] != ntok) return NULL;
    if (!(nt = malloc((ntok + 64) * 4))) return NULL;
    nt[nt_n++] = t[0]; nt[nt_n++] = t[1];
    for (k = 2; k < ntok; )
    {
        uint32_t op = t[k] & 0x7ff, n = (t[k] >> 24) & 0x7f;
        if (op == 0x35 && k + 1 < ntok) n = t[k + 1];              /* customdata */
        if (!n || k + n > ntok) { free(nt); return NULL; }
        if (op == 104 && n == 2) temps_at = nt_n + 1;               /* dcl_temps */
        if (op == 45)                                               /* ld */
        {
            unsigned e = 1, dl, al, r, c;
            uint32_t dest0, dest1, addr[8], rtok, mask, mode;
            while (e < n && (t[k + e - 1] >> 31)) e++;
            if (!(dl = operand_tokens(t + k + e, n - e)) || !(al = operand_tokens(t + k + e + dl, n - e - dl))
                    || e + dl + al + 2 > n) { free(nt); return NULL; }
            r = e + dl + al;
            rtok = t[k + r];
            if (((rtok >> 12) & 0xff) == 7 && t[k + r + 1] == (uint32_t)reg)
            {
                *why = "the view is read in a way this does not rewrite";
                dest0 = t[k + e]; dest1 = t[k + e + 1];
                if (hits || !temps_at || dl != 2 || (dest0 & 0xc) || ((dest0 >> 12) & 0xff) != 0 || al > 8)
                    { free(nt); return NULL; }
                memcpy(addr, t + k + e + dl, al * 4);
                mode = (addr[0] >> 2) & 3;
                if (mode == 1) addr[0] = (addr[0] & ~0xff0u) | ((((addr[0] >> 4) & 3) * 0x55) << 4);
                else if (mode != 2) { free(nt); return NULL; }
                mask = (dest0 >> 4) & 0xf;
                /* imad rN.xyz, addr, l(3,3,3,3), l(0,1,2,0) */
                nt[nt_n++] = 35u | ((1 + 2 + al + 10) << 24);
                nt[nt_n++] = 0x00100072; nt[nt_n++] = nt[temps_at];
                memcpy(nt + nt_n, addr, al * 4); nt_n += al;
                nt[nt_n++] = 0x00004002; nt[nt_n++] = 3; nt[nt_n++] = 3; nt[nt_n++] = 3; nt[nt_n++] = 3;
                nt[nt_n++] = 0x00004002; nt[nt_n++] = 0; nt[nt_n++] = 1; nt[nt_n++] = 2; nt[nt_n++] = 0;
                for (c = 0; c < 4; c++)
                {
                    uint32_t s = (rtok >> (4 + 2 * c)) & 3, j;
                    if (!((mask >> c) & 1)) continue;
                    if (s > 2) { free(nt); return NULL; }
                    nt[nt_n++] = (t[k] & ~(0x7fu << 24)) | ((e + 6) << 24);
                    for (j = 1; j < e; j++) nt[nt_n++] = t[k + j];
                    nt[nt_n++] = 0x00100002 | (1u << (4 + c)); nt[nt_n++] = dest1;
                    nt[nt_n++] = 0x00100006 | ((s * 0x55) << 4); nt[nt_n++] = nt[temps_at];
                    nt[nt_n++] = rtok & ~0xff0u; nt[nt_n++] = t[k + r + 1];
                    loads++;
                }
                hits++;
                k += n;
                continue;
            }
        }
        if (nt_n + n > ntok + 64) { free(nt); return NULL; }
        memcpy(nt + nt_n, t + k, n * 4); nt_n += n;
        k += n;
    }
    *why = "the shader does not read that view";
    if (hits != 1) { free(nt); return NULL; }
    nt[temps_at]++;
    nt[1] = nt_n;

    /* The container again, the shader chunk replaced and the statistics adjusted. */
    nch = rgb32_rd32(d + 28);
    out_size = 32 + 4 * (size_t)nch;
    for (i = 0; i < nch; i++)
    {
        const unsigned char *c = d + rgb32_rd32(d + 32 + 4 * i);
        out_size += 8 + (!memcmp(c, "SHEX", 4) ? nt_n * 4 : rgb32_rd32(c + 4));
    }
    *why = "out of memory";
    if (!(out = malloc(out_size))) { free(nt); return NULL; }
    memcpy(out, d, 32);
    memcpy(out + 24, &(uint32_t){ (uint32_t)out_size }, 4);
    o = 32 + 4 * nch;
    for (i = 0; i < nch; i++)
    {
        const unsigned char *c = d + rgb32_rd32(d + 32 + 4 * i);
        uint32_t size = !memcmp(c, "SHEX", 4) ? nt_n * 4 : rgb32_rd32(c + 4);
        memcpy(out + 32 + 4 * i, &o, 4);
        memcpy(out + o, c, 4);
        memcpy(out + o + 4, &size, 4);
        if (!memcmp(c, "SHEX", 4)) memcpy(out + o + 8, nt, size);
        else memcpy(out + o + 8, c + 8, size);
        if (!memcmp(c, "STAT", 4) && size >= 64)
        {
            uint32_t *s = (uint32_t *)(out + o + 8);
            s[0] += loads;          /* instructions */
            s[1] += 1;              /* temporary registers */
            s[5] += 1;              /* integer instructions */
            s[15] += loads - 1;     /* texture loads */
        }
        o += 8 + size;
    }
    free(nt);
    dxbc_checksum(out, out_size, (uint32_t *)(out + 4));
    *out_len = out_size;
    *why = NULL;
    return out;
}
