/*
 * hlslc.c -- compile HLSL on the Mac with the DXC that ships inside D3DMetal.
 *
 *   hlslc <libdxcompiler.dylib> <in.hlsl> <out.dxil> <target> [extra dxc args...]
 *
 * D3DMetal.framework/Versions/A/Resources/libdxcompiler.dylib exports
 * DxcCreateInstance; IDxcCompiler3::Compile is called with -T <target> -E main.
 * Used for the shaders fixes/ replaces, e.g. fixes/mk11-morph/.
 *
 *   clang -O2 -arch x86_64 -o hlslc tools/hlslc.c    (the dylib is x86_64: runs under Rosetta)
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>

typedef struct { uint32_t a; uint16_t b, c; uint8_t d[8]; } guid;
static const guid clsid_compiler = { 0x73e22d93, 0xe6ce, 0x47f3, { 0xb5, 0xbf, 0xf0, 0x66, 0x4f, 0x39, 0xc1, 0xb0 } };
static const guid iid_compiler3 = { 0x228b4687, 0x5a6a, 0x4730, { 0x90, 0x0c, 0x97, 0x02, 0xb2, 0x20, 0x3f, 0x54 } };
static const guid iid_opresult = { 0xcedb484a, 0xd4e9, 0x445a, { 0xb9, 0x91, 0xca, 0x21, 0xca, 0x15, 0x7d, 0xc2 } };
typedef struct { const void *ptr; size_t size; uint32_t encoding; } dxcbuffer;
typedef int (*compile_fn)(void *, const dxcbuffer *, const wchar_t **, uint32_t, void *, const guid *, void **);
#define VT(o, i) ((*(void ***)(o))[i])

static wchar_t *widen(const char *s) { size_t n = strlen(s) + 1; wchar_t *w = malloc(n * sizeof(wchar_t)); mbstowcs(w, s, n); return w; }

int main(int argc, char **argv)
{
    void *lib, *comp = NULL, *res = NULL, *blob = NULL, *err = NULL;
    int (*create)(const guid *, const guid *, void **);
    const wchar_t *args[32];
    uint32_t nargs = 0;
    dxcbuffer src;
    char *text;
    long n;
    int hr, status = 0, i;
    FILE *f;
    if (argc < 5) { fprintf(stderr, "usage: hlslc lib in.hlsl out.dxil target [args]\n"); return 2; }
    if (!(lib = dlopen(argv[1], RTLD_NOW)) || !(create = dlsym(lib, "DxcCreateInstance"))) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    if ((hr = create(&clsid_compiler, &iid_compiler3, &comp)) || !comp) { fprintf(stderr, "create %x\n", hr); return 1; }
    if (!(f = fopen(argv[2], "rb"))) return 1;
    fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
    text = malloc(n + 1); fread(text, 1, n, f); text[n] = 0; fclose(f);
    src.ptr = text; src.size = n; src.encoding = 65001;  /* UTF-8 */
    args[nargs++] = L"-T"; args[nargs++] = widen(argv[4]);
    args[nargs++] = L"-E"; args[nargs++] = L"main";
    for (i = 5; i < argc && nargs < 30; i++) args[nargs++] = widen(argv[i]);
    hr = ((compile_fn)VT(comp, 3))(comp, &src, args, nargs, NULL, &iid_opresult, &res);
    if (hr || !res) { fprintf(stderr, "compile call %x\n", hr); return 1; }
    ((int (*)(void *, int *))VT(res, 3))(res, &status);
    ((int (*)(void *, void **))VT(res, 5))(res, &err);
    if (err && ((size_t (*)(void *))VT(err, 4))(err))
        fprintf(stderr, "%.*s\n", (int)((size_t (*)(void *))VT(err, 4))(err), (const char *)((void *(*)(void *))VT(err, 3))(err));
    if (status) { fprintf(stderr, "status %x\n", status); return 1; }
    ((int (*)(void *, void **))VT(res, 4))(res, &blob);
    if (!blob) return 1;
    if (!(f = fopen(argv[3], "wb"))) return 1;
    fwrite(((void *(*)(void *))VT(blob, 3))(blob), 1, ((size_t (*)(void *))VT(blob, 4))(blob), f);
    fclose(f);
    return 0;
}
