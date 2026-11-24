// D3DMetal freeze fix
#include "../notproton_plugin.h"

#include <stdio.h>
#include <string.h>

#define TAG "d3dmetal-freeze"
#define E_INVALIDARG ((int32_t)0x80070057)

#if defined(__x86_64__)
#define MSABI __attribute__((ms_abi))
#else
#define MSABI
#endif

#define SYM_IN_CLASS_VTABLE "__ZN11DXGIAdapter20QueryVideoMemoryInfoEj25DXGI_MEMORY_SEGMENT_GROUPP28DXGI_QUERY_VIDEO_MEMORY_INFO"
#define SYM_IN_UNIXCALL_TABLE "__ZL39DXGIAdapter_QueryVideoMemoryInfo_unpackR39DXGIAdapter_QueryVideoMemoryInfo_params"
#define SYM_IN_DIRECT_VTABLE "__ZL34IDXGIAdapter4_QueryVideoMemoryInfoP13IDXGIAdapter4j25DXGI_MEMORY_SEGMENT_GROUPP28DXGI_QUERY_VIDEO_MEMORY_INFO"

typedef int32_t (MSABI *method_fn)(void *self, uint32_t node, int32_t group, void *info);
static method_fn real_method;

static MSABI int32_t method_hook(void *self, uint32_t node, int32_t group, void *info) {
    if (node != 0) return E_INVALIDARG;
    return real_method(self, node, group, info);
}

struct qvmi_params {
    void    *self;
    uint32_t node;
    int32_t  group;
    void    *info;
    int32_t  result;
};

typedef uint32_t (*unpack_fn)(struct qvmi_params *p);
static unpack_fn real_unpack;

static uint32_t unpack_hook(struct qvmi_params *p) {
    if (p->node != 0) {
        p->result = E_INVALIDARG;
        return 0;
    }
    return real_unpack(p);
}

static const struct np_plugin_api *api;

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    char version[32] = "";
    if (!api->bundle_short_version(image, version, sizeof(version))) {
        api->log(TAG, "D3DMetal at %s has no readable version, not armed", image);
        return;
    }

    int v3 = strcmp(version, "3.0") == 0;
    int v4b2 = strcmp(version, "4.0b2") == 0;
    if (!v3 && !v4b2) {
        api->log(TAG, "D3DMetal %s is not a version this fix knows, not armed", version);
        return;
    }

    uintptr_t fn = api->symbol(mh, slide, v3 ? SYM_IN_CLASS_VTABLE : SYM_IN_DIRECT_VTABLE);
    uintptr_t unixcall_fn = v4b2 ? api->symbol(mh, slide, SYM_IN_UNIXCALL_TABLE) : 0;
    if (!fn || (v4b2 && !unixcall_fn)) {
        api->log(TAG, "D3DMetal %s: QueryVideoMemoryInfo not found, not armed", version);
        return;
    }

    uintptr_t *slot = NULL, *unixcall_slot = NULL;
    int refs = api->count_pointers(mh, slide, fn, &slot);
    int unixcall_refs = v4b2 ? api->count_pointers(mh, slide, unixcall_fn, &unixcall_slot) : 1;
    if (refs != 1 || unixcall_refs != 1) {
        api->log(TAG, "D3DMetal %s: %d and %d table entries point at the functions instead of 1, not armed",
                 version, refs, unixcall_refs);
        return;
    }

    real_method = (method_fn)fn;
    if (v4b2) real_unpack = (unpack_fn)unixcall_fn;
    if (!api->swap_pointer(slot, fn, (uintptr_t)method_hook)) {
        api->log(TAG, "D3DMetal %s: the table entry could not be written, not armed", version);
        return;
    }
    if (v4b2 && !api->swap_pointer(unixcall_slot, unixcall_fn, (uintptr_t)unpack_hook)) {
        api->swap_pointer(slot, (uintptr_t)method_hook, fn);
        api->log(TAG, "D3DMetal %s: the table entry could not be written, not armed", version);
        return;
    }
    api->log(TAG, "D3DMetal %s: QueryVideoMemoryInfo refuses nodes other than 0", version);
}

#ifndef NP_PLUGIN_TEST
__attribute__((constructor))
#endif
static void freeze_init(void) {
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, not armed\n");
        return;
    }
    api->on_first_image("D3DMetal", "D3DMetal.framework/", arm);
}
