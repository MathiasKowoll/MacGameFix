#include "wolffix_core.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static uint32_t rd32(const unsigned char *p)
{
    return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static void wr32(unsigned char *p, uint32_t v)
{
    p[0] = v;
    p[1] = v >> 8;
    p[2] = v >> 16;
    p[3] = v >> 24;
}

/* ---- DXBC checksum: MD5 with its own final block, over everything after the checksum. */
static void md5_block(uint32_t st[4], const unsigned char *blk)
{
    static const unsigned char S[64] = {7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,
            5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21};
    static const uint32_t K[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,
        0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,
        0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,
        0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,
        0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,
        0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391};
    uint32_t M[16], a = st[0], b = st[1], c = st[2], d = st[3], f, g, i;

    for (i = 0; i < 16; i++)
        M[i] = rd32(blk + 4 * i);
    for (i = 0; i < 64; i++)
    {
        if (i < 16) { f = (b & c) | (~b & d); g = i; }
        else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
        else { f = c ^ (b | ~d); g = (7 * i) % 16; }
        f += a + K[i] + M[g];
        a = d; d = c; c = b;
        b += (f << S[i]) | (f >> (32 - S[i]));
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d;
}

void wolffix_dxbc_checksum(unsigned char *dxbc, size_t size)
{
    uint32_t st[4] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476};
    uint32_t bits = (uint32_t)(size - 20) * 8;
    const unsigned char *d = dxbc + 20;
    size_t n = size - 20, i, rest;
    unsigned char blk[64];

    for (i = 0; i + 64 <= n; i += 64)
        md5_block(st, d + i);
    rest = n - i;
    memset(blk, 0, 64);
    if (rest >= 56)
    {
        memcpy(blk, d + i, rest);
        blk[rest] = 0x80;
        md5_block(st, blk);
        memset(blk, 0, 64);
        wr32(blk, bits);
    }
    else
    {
        wr32(blk, bits);
        memcpy(blk + 4, d + i, rest);
        blk[4 + rest] = 0x80;
    }
    wr32(blk + 60, (bits >> 2) | 1);
    md5_block(st, blk);
    for (i = 0; i < 4; i++)
        wr32(dxbc + 4 + 4 * i, st[i]);
}

/* ---- sample remap */
#define OP_LD_MS        46
#define OP_CUSTOMDATA   53
#define IMM32_SCALAR    0x00004001u

void *wolffix_remap_samples(const void *dxbc, size_t size, int *count)
{
    const unsigned char *in = dxbc;
    unsigned char *out = NULL;
    uint32_t chunks, i;

    *count = 0;
    if (!in || size < 32 || memcmp(in, "DXBC", 4) || rd32(in + 24) != size)
        return NULL;
    chunks = rd32(in + 28);
    if (32 + (size_t)chunks * 4 > size)
        return NULL;
    for (i = 0; i < chunks; i++)
    {
        size_t off = rd32(in + 32 + 4 * i), end, tokens, pos;

        if (off + 16 > size || (memcmp(in + off, "SHEX", 4) && memcmp(in + off, "SHDR", 4)))
            continue;
        /* the chunk's own size, the program's length in dwords, and the file, whichever ends first */
        end = off + 8 + rd32(in + off + 4);
        tokens = off + 8 + (size_t)rd32(in + off + 12) * 4;
        if (tokens < end)
            end = tokens;
        if (size < end)
            end = size;
        /* instructions start after the version and length dwords */
        for (pos = off + 16; pos + 4 <= end; )
        {
            uint32_t token = rd32(in + pos), op = token & 0x7ff, len = (token >> 24) & 0x7f;

            /* customdata, and declarations too long for the 7-bit field, keep the length in the next dword */
            if (op == OP_CUSTOMDATA || !len)
            {
                if (pos + 8 > end)
                    break;
                len = rd32(in + pos + 4);
            }
            if (!len || pos + (size_t)len * 4 > end)
                break;
            /* ld_ms dest, address, resource, sampleIndex: an immediate sample index is the last two dwords */
            if (op == OP_LD_MS && len >= 6 && rd32(in + pos + (len - 2) * 4) == IMM32_SCALAR)
            {
                uint32_t sample = rd32(in + pos + (len - 1) * 4);

                if (sample >= 4 && sample < 8)
                {
                    if (!out)
                    {
                        if (!(out = malloc(size)))
                            return NULL;
                        memcpy(out, in, size);
                    }
                    wr32(out + pos + (len - 1) * 4, sample - 4);
                    ++*count;
                }
            }
            pos += (size_t)len * 4;
        }
    }
    if (out)
        wolffix_dxbc_checksum(out, size);
    return out;
}
