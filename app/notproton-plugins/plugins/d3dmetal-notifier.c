// D3DMetal video crash fix
#include "../notproton_plugin.h"

#include <os/lock.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define TAG "d3dmetal-notifier"

#if defined(__x86_64__)
#define MSABI __attribute__((ms_abi))
#else
#define MSABI
#endif

typedef int32_t HRESULT;
typedef struct { uint32_t d1; uint16_t d2, d3; uint8_t d4[8]; } GUID;

#define S_OK                    ((HRESULT)0)
#define E_POINTER               ((HRESULT)0x80004003)
#define E_OUTOFMEMORY           ((HRESULT)0x8007000E)
#define DXGI_ERROR_INVALID_CALL ((HRESULT)0x887A0001)
#define DXGI_ERROR_NOT_FOUND    ((HRESULT)0x887A0002)

static const GUID IID_ID3DDestructionNotifier =
    { 0xa06eb39a, 0x50da, 0x425b, { 0x8c, 0x31, 0x4e, 0xec, 0xd6, 0xc2, 0x70, 0xf3 } };
static const GUID NOTIFIER_SLOT =
    { 0x6f1c2a4e, 0x93b7, 0x4d58, { 0xa1, 0x0e, 0x5c, 0x27, 0xd4, 0x88, 0x3b, 0x91 } };

typedef HRESULT  (MSABI *qi_fn)(void *self, const GUID *riid, void **out);
typedef uint32_t (MSABI *ref_fn)(void *self);
typedef HRESULT  (MSABI *getpd_fn)(void *self, const GUID *guid, uint32_t *size, void *data);
typedef HRESULT  (MSABI *setpd_fn)(void *self, const GUID *guid, uint32_t size, const void *data);
typedef void     (MSABI *destruction_fn)(void *data);

enum { SLOT_QI, SLOT_ADDREF, SLOT_RELEASE, SLOT_GETPD, SLOT_SETPD, SLOTS };

struct cls {
    const char *name;
    uintptr_t  *vtbl;
    qi_fn       qi;
    ref_fn      addref, release;
    getpd_fn    getpd;
    setpd_fn    setpd;
};

#define NCLS 2
static struct cls g_cls[NCLS];

struct callback {
    destruction_fn fn;
    void          *data;
    uint32_t       id;
};

struct notifier {
    const void *const *vtbl;
    struct cls        *cls;
    void              *resource;
    struct notifier   *next;
    os_unfair_lock     lock;
    os_unfair_lock     release_lock;
    uint32_t           next_id, count, cap;
    struct callback   *cbs;
};

#define BUCKETS 256
static struct notifier *g_buckets[BUCKETS];
static os_unfair_lock   g_map_lock = OS_UNFAIR_LOCK_INIT;
static uint32_t         g_live;
static int              g_said_handed, g_said_fired, g_said_store;
static const struct np_plugin_api *api;

static int guid_eq(const GUID *a, const GUID *b) { return memcmp(a, b, sizeof(*a)) == 0; }

static size_t bucket_of(const void *res) {
    uintptr_t v = (uintptr_t)res;
    return ((v >> 4) ^ (v >> 12)) & (BUCKETS - 1);
}

static int owns(const struct cls *c, void *res, const struct notifier *n) {
    struct notifier *got = NULL;
    uint32_t size = sizeof(got);
    return c->getpd(res, &NOTIFIER_SLOT, &size, &got) == S_OK && size == sizeof(got) && got == n;
}

static void unlink_locked(struct notifier *n) {
    for (struct notifier **p = &g_buckets[bucket_of(n->resource)]; *p; p = &(*p)->next)
        if (*p == n) { *p = n->next; break; }
}

static void destroy(struct notifier *n) {
    free(n->cbs);
    free(n);
    __atomic_sub_fetch(&g_live, 1, __ATOMIC_RELEASE);
}

static struct notifier *lookup_locked(struct cls *c, void *res) {
    for (struct notifier *n = g_buckets[bucket_of(res)]; n; n = n->next) {
        if (n->resource != res) continue;
        if (n->cls == c && owns(c, res, n)) return n;
        unlink_locked(n);
        destroy(n);
        return NULL;
    }
    return NULL;
}

static const void *const notifier_vtbl[];

static struct notifier *get_or_create(struct cls *c, void *res) {
    os_unfair_lock_lock(&g_map_lock);
    struct notifier *n = lookup_locked(c, res);
    if (!n && (n = calloc(1, sizeof(*n)))) {
        n->vtbl = notifier_vtbl;
        n->cls = c;
        n->resource = res;
        n->lock = OS_UNFAIR_LOCK_INIT;
        n->release_lock = OS_UNFAIR_LOCK_INIT;
        if (c->setpd(res, &NOTIFIER_SLOT, sizeof(n), &n) != S_OK) {
            free(n);
            n = NULL;
            if (!__atomic_exchange_n(&g_said_store, 1, __ATOMIC_RELAXED) && api)
                api->log(TAG, "a %s refused the notifier's private data, so it has no notifier", c->name);
        } else {
            size_t b = bucket_of(res);
            n->next = g_buckets[b];
            g_buckets[b] = n;
            __atomic_add_fetch(&g_live, 1, __ATOMIC_RELEASE);
        }
    }
    os_unfair_lock_unlock(&g_map_lock);
    return n;
}

static uint32_t resource_release(struct cls *c, void *res) {
    if (!__atomic_load_n(&g_live, __ATOMIC_ACQUIRE)) return c->release(res);
    os_unfair_lock_lock(&g_map_lock);
    struct notifier *n = lookup_locked(c, res);
    os_unfair_lock_unlock(&g_map_lock);
    if (!n) return c->release(res);

    os_unfair_lock_lock(&n->release_lock);
    if (c->addref(res) != 2) {
        c->release(res);
        uint32_t left = c->release(res);
        os_unfair_lock_unlock(&n->release_lock);
        return left;
    }

    os_unfair_lock_lock(&g_map_lock);
    unlink_locked(n);
    os_unfair_lock_unlock(&g_map_lock);
    struct notifier *none = NULL;
    c->setpd(res, &NOTIFIER_SLOT, sizeof(none), &none);

    os_unfair_lock_lock(&n->lock);
    struct callback *cbs = n->cbs;
    uint32_t count = n->count;
    n->cbs = NULL;
    n->count = n->cap = 0;
    os_unfair_lock_unlock(&n->lock);

    for (uint32_t i = 0; i < count; i++) cbs[i].fn(cbs[i].data);
    if (count && !__atomic_exchange_n(&g_said_fired, 1, __ATOMIC_RELAXED) && api)
        api->log(TAG, "first destruction callbacks ran (%u on a %s)", count, c->name);

    c->release(res);
    uint32_t left = c->release(res);
    os_unfair_lock_unlock(&n->release_lock);
    free(cbs);
    destroy(n);
    return left;
}

static HRESULT hook_qi(struct cls *c, void *res, const GUID *riid, void **out) {
    if (!riid || !guid_eq(riid, &IID_ID3DDestructionNotifier)) return c->qi(res, riid, out);
    if (!out) return E_POINTER;
    struct notifier *n = get_or_create(c, res);
    if (!n) {
        *out = NULL;
        return E_OUTOFMEMORY;
    }
    c->addref(res);
    *out = n;
    if (!__atomic_exchange_n(&g_said_handed, 1, __ATOMIC_RELAXED) && api)
        api->log(TAG, "first ID3DDestructionNotifier handed out, for a %s", c->name);
    return S_OK;
}

static HRESULT MSABI n_qi(void *self, const GUID *riid, void **out) {
    struct notifier *n = self;
    if (!out) return E_POINTER;
    if (riid && guid_eq(riid, &IID_ID3DDestructionNotifier)) {
        n->cls->addref(n->resource);
        *out = n;
        return S_OK;
    }
    return n->cls->qi(n->resource, riid, out);
}

static uint32_t MSABI n_addref(void *self) {
    struct notifier *n = self;
    return n->cls->addref(n->resource);
}

static uint32_t MSABI n_release(void *self) {
    struct notifier *n = self;
    return resource_release(n->cls, n->resource);
}

static HRESULT MSABI n_register(void *self, destruction_fn fn, void *data, uint32_t *id) {
    struct notifier *n = self;
    if (!fn) return DXGI_ERROR_INVALID_CALL;
    os_unfair_lock_lock(&n->lock);
    if (n->count == n->cap) {
        uint32_t cap = n->cap ? n->cap * 2 : 4;
        struct callback *grown = realloc(n->cbs, cap * sizeof(*grown));
        if (!grown) {
            os_unfair_lock_unlock(&n->lock);
            return E_OUTOFMEMORY;
        }
        n->cbs = grown;
        n->cap = cap;
    }
    uint32_t cid = n->next_id++;
    n->cbs[n->count++] = (struct callback){ fn, data, cid };
    os_unfair_lock_unlock(&n->lock);
    if (id) *id = cid;
    return S_OK;
}

static HRESULT MSABI n_unregister(void *self, uint32_t id) {
    struct notifier *n = self;
    HRESULT hr = DXGI_ERROR_NOT_FOUND;
    os_unfair_lock_lock(&n->lock);
    for (uint32_t i = 0; i < n->count; i++) {
        if (n->cbs[i].id != id) continue;
        memmove(&n->cbs[i], &n->cbs[i + 1], (n->count - i - 1) * sizeof(*n->cbs));
        n->count--;
        hr = S_OK;
        break;
    }
    os_unfair_lock_unlock(&n->lock);
    return hr;
}

static const void *const notifier_vtbl[] = {
    (const void *)n_qi, (const void *)n_addref, (const void *)n_release,
    (const void *)n_register, (const void *)n_unregister,
};

#define CLASS_HOOKS(N) \
    static HRESULT MSABI qi_hook_##N(void *s, const GUID *r, void **o) { return hook_qi(&g_cls[N], s, r, o); } \
    static uint32_t MSABI release_hook_##N(void *s) { return resource_release(&g_cls[N], s); }
CLASS_HOOKS(0)
CLASS_HOOKS(1)
static const uintptr_t qi_hooks[NCLS] = { (uintptr_t)qi_hook_0, (uintptr_t)qi_hook_1 };
static const uintptr_t release_hooks[NCLS] = { (uintptr_t)release_hook_0, (uintptr_t)release_hook_1 };

static int swap(uintptr_t *slot, uintptr_t expect, uintptr_t value) {
    if (api) return api->swap_pointer(slot, expect, value);
    return __atomic_compare_exchange_n(slot, &expect, value, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}

static void uninstall(int n) {
    for (int i = 0; i < n; i++) {
        struct cls *c = &g_cls[i];
        swap(&c->vtbl[SLOT_QI], qi_hooks[i], (uintptr_t)c->qi);
        swap(&c->vtbl[SLOT_RELEASE], release_hooks[i], (uintptr_t)c->release);
    }
}

static int install(uintptr_t *vt[NCLS], const char *names[NCLS]) {
    for (int i = 0; i < NCLS; i++) {
        struct cls *c = &g_cls[i];
        c->name = names[i];
        c->vtbl = vt[i];
        c->qi = (qi_fn)vt[i][SLOT_QI];
        c->addref = (ref_fn)vt[i][SLOT_ADDREF];
        c->release = (ref_fn)vt[i][SLOT_RELEASE];
        c->getpd = (getpd_fn)vt[i][SLOT_GETPD];
        c->setpd = (setpd_fn)vt[i][SLOT_SETPD];
    }
    for (int i = 0; i < NCLS; i++) {
        if (!swap(&vt[i][SLOT_QI], (uintptr_t)g_cls[i].qi, qi_hooks[i]) ||
            !swap(&vt[i][SLOT_RELEASE], (uintptr_t)g_cls[i].release, release_hooks[i])) {
            uninstall(i + 1);
            return 0;
        }
    }
    return 1;
}

static uintptr_t *direct_vtable(const struct mach_header_64 *mh, intptr_t slide, const char *sym) {
    static const char *const want[SLOTS] = {
        "ID3D12Resource2_QueryInterfaceP15ID3D12Resource2", "ID3D12Resource2_AddRefP15ID3D12Resource2",
        "ID3D12Resource2_ReleaseP15ID3D12Resource2", "ID3D12Resource2_GetPrivateDataP15ID3D12Resource2",
        "ID3D12Resource2_SetPrivateDataP15ID3D12Resource2",
    };
    uintptr_t *vt = (uintptr_t *)api->symbol(mh, slide, sym);
    if (!vt) return NULL;
    for (int i = 0; i < SLOTS; i++) {
        const char *n = api->symbol_name(mh, slide, vt[i]);
        if (!n || !strstr(n, want[i])) return NULL;
    }
    return vt;
}

static uintptr_t *class_vtable(const struct mach_header_64 *mh, intptr_t slide, const char *cls) {
    static const char *const method[SLOTS] = {
        "14QueryInterfaceERK5_GUIDPPv", "6AddRefEv", "7ReleaseEv",
        "14GetPrivateDataERK5_GUIDPjPv", "14SetPrivateDataERK5_GUIDjPKv",
    };
    uintptr_t fn[SLOTS];
    for (int i = 0; i < SLOTS; i++) {
        char sym[128];
        snprintf(sym, sizeof(sym), "__ZN%s%s", cls, method[i]);
        if (!(fn[i] = api->symbol(mh, slide, sym))) return NULL;
    }
    uintptr_t *vt = NULL;
    if (api->count_pointers(mh, slide, fn[SLOT_QI], &vt) != 1) return NULL;
    for (int i = 0; i < SLOTS; i++)
        if (vt[i] != fn[i]) return NULL;
    return vt;
}

static int env_on(const char *name) {
    const char *v = getenv(name);
    if (!v || !*v) return 0;
    return strcmp(v, "0") != 0 && strcasecmp(v, "false") != 0 && strcasecmp(v, "no") != 0;
}

static int g_armed;

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    char version[32] = "?";
    api->bundle_short_version(image, version, sizeof(version));

    if (api->symbol(mh, slide, "__ZN11D3DMUnknown31GetDestructionNotifierInterfaceEv")) {
        api->log(TAG, "D3DMetal %s answers ID3DDestructionNotifier itself, not armed", version);
        return;
    }

    static const char *names[NCLS] = { "texture", "buffer" };
    uintptr_t *vt[NCLS] = {
        direct_vtable(mh, slide, "__ZL25D3D12Texture_DirectVTable"),
        direct_vtable(mh, slide, "__ZL24D3D12Buffer_DirectVTable"),
    };
    const char *kind = "DirectVTable";
    if (vt[0] || vt[1]) {
        if (env_on("D3DM_WINE_UNIX_CALL")) {
            api->log(TAG, "D3DMetal %s runs through unix calls (D3DM_WINE_UNIX_CALL), not armed", version);
            return;
        }
    } else {
        vt[0] = class_vtable(mh, slide, "12D3D12Texture");
        vt[1] = class_vtable(mh, slide, "11D3D12Buffer");
        kind = "class vtable";
    }
    if (!vt[0] || !vt[1]) {
        api->log(TAG, "D3DMetal %s: the D3D12 resource tables are not the ones this fix knows, not armed", version);
        return;
    }
    if (!install(vt, names)) {
        api->log(TAG, "D3DMetal %s: a table entry could not be written, not armed", version);
        return;
    }
    g_armed = 1;
    api->log(TAG, "D3DMetal %s: D3D12 textures and buffers answer ID3DDestructionNotifier (%s)", version, kind);
}

#ifndef NP_PLUGIN_TEST
__attribute__((constructor))
#endif
static void notifier_init(void) {
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, not armed\n");
        return;
    }
    api->on_first_image("D3DMetal", "D3DMetal.framework/", arm);
}
