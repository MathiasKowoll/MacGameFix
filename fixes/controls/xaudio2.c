// xaudio2_9.dll: the device a game names is the one its mastering voice opens. What engine patch
// 0011 does in the Wine modules' xaudio2_9.dll, done here on CodeWeavers' own.
//
// IXAudio2::CreateMasteringVoice takes the id of the audio device to open. Wine's ignores it and
// opens the default output. A game that plays a pad's haptics through XAudio2 names the pad's
// output, by its endpoint id or by its audio render interface's path,
// \\?\SWD#MMDEVAPI#<endpoint id>#{e6327cad-...} (endpoints.c lists it in SetupAPI under that
// path): Nioh 3 does, and with the name ignored the haptics would come out of the speakers.
//
// Wine's XAudio2 opens "the default device" by asking mmdevapi's device enumerator for the
// default render endpoint, on the thread that creates the voice. So nothing inside xaudio2_9.dll
// is changed: while a voice is being created for a named device, that question, from that thread,
// is answered with the named endpoint, if it is among the active ones (compared without regard to
// case, as the path can come in either); otherwise with the default one as before.
//
// To be there at the two moments, when xaudio2_9.dll is mapped its exports XAudio2Create and
// XAudio2CreateWithVersionInfo are pointed at functions here, run as Windows code (windows.h).
// They give the game the object as before and, the first time, point two COM methods at functions
// here: IXAudio2::CreateMasteringVoice in that object's table, and
// IMMDeviceEnumerator::GetDefaultAudioEndpoint in the table of an enumerator made for the purpose.
//
// An xaudio2_9.dll that already opens the named device (the Wine modules') never asks for the
// default one while such a voice is created, so nothing is answered differently.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pad.h"
#include "pe.h"
#include "windows.h"

#if defined(__x86_64__)
typedef struct { uint32_t Data1; uint16_t Data2, Data3; uint8_t Data4[8]; } guid;
static const guid enumerator_class = {0xbcde0395, 0xe52f, 0x467c, {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};
static const guid enumerator_interface = {0xa95664d2, 0x9614, 0x4f35, {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};

// A COM object: a pointer to its table of methods, each taking the object first.
typedef struct { uintptr_t *methods; } object;
#define METHOD(o, index, type) ((type)((object *)(o))->methods[index])

typedef int32_t (WINAPI *create_fn)(object **xaudio2, uint32_t flags, uint32_t processor);
typedef int32_t (WINAPI *create_version_fn)(object **xaudio2, uint32_t flags, uint32_t processor, uint32_t version);
typedef int32_t (WINAPI *mastering_voice_fn)(object *xaudio2, object **voice, uint32_t channels, uint32_t rate,
                                             uint32_t flags, const uint16_t *device, const void *effects,
                                             uint32_t category);
typedef int32_t (WINAPI *default_endpoint_fn)(object *enumerator, int flow, int role, object **endpoint);
typedef int32_t (WINAPI *enum_endpoints_fn)(object *enumerator, int flow, uint32_t states, object **endpoints);
typedef int32_t (WINAPI *count_fn)(object *endpoints, uint32_t *count);
typedef int32_t (WINAPI *item_fn)(object *endpoints, uint32_t index, object **endpoint);
typedef int32_t (WINAPI *id_fn)(object *endpoint, uint16_t **id);
typedef uint32_t (WINAPI *release_fn)(object *o);
typedef int32_t (WINAPI *create_instance_fn)(const guid *class, void *outer, uint32_t context, const guid *interface,
                                             object **out);
typedef int32_t (WINAPI *initialize_fn)(void *reserved, uint32_t model);
typedef void (WINAPI *uninitialize_fn)(void);
typedef void (WINAPI *free_fn)(void *memory);

enum { RELEASE = 2 };
enum { XAUDIO2_CREATE_MASTERING_VOICE = 7 };
enum { ENUMERATOR_ENUM_ENDPOINTS = 3, ENUMERATOR_DEFAULT_ENDPOINT = 4 };
enum { ENDPOINTS_COUNT = 3, ENDPOINTS_ITEM = 4 };
enum { ENDPOINT_ID = 5 };
#define RENDER 0
#define DEVICE_STATE_ACTIVE 1

static create_fn real_create;
static create_version_fn real_create_version;
static mastering_voice_fn real_mastering_voice;
static default_endpoint_fn real_default_endpoint;
// Imports of xaudio2_9.dll, read when they are needed: the loader has bound them by then.
static uintptr_t *create_instance_import, *free_import, *ntdll_import;

// The device each thread that is creating a voice named: the id, without the path around it.
static struct naming {
    uint32_t thread;  // 0: free
    const uint16_t *id;
    unsigned length;
} naming[8];

// ---- Run as Windows code: nothing below calls out of this file, except through pointers.

static uint16_t lower(uint16_t c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }

static bool same_id(const uint16_t *id, const struct naming *named) {
    unsigned i;
    for (i = 0; i < named->length && id[i]; i++)
        if (lower(id[i]) != lower(named->id[i])) return false;
    return i == named->length && !id[i];
}

static WINAPI int32_t default_endpoint(object *enumerator, int flow, int role, object **endpoint) {
    const struct naming *named = NULL;
    uint32_t thread = win_thread(), count = 0;
    object *endpoints;

    for (unsigned i = 0; i < 8 && thread; i++)
        if (naming[i].thread == thread) named = &naming[i];
    if (!named || flow != RENDER || !endpoint ||
        METHOD(enumerator, ENUMERATOR_ENUM_ENDPOINTS, enum_endpoints_fn)(enumerator, RENDER, DEVICE_STATE_ACTIVE, &endpoints))
        return real_default_endpoint(enumerator, flow, role, endpoint);
    METHOD(endpoints, ENDPOINTS_COUNT, count_fn)(endpoints, &count);
    for (uint32_t i = 0; i < count; i++) {
        object *candidate;
        uint16_t *id;
        bool same;

        if (METHOD(endpoints, ENDPOINTS_ITEM, item_fn)(endpoints, i, &candidate)) continue;
        if (!METHOD(candidate, ENDPOINT_ID, id_fn)(candidate, &id)) {
            same = same_id(id, named);
            ((free_fn)*free_import)(id);
            if (same) {
                METHOD(endpoints, RELEASE, release_fn)(endpoints);
                *endpoint = candidate;
                return 0;
            }
        }
        METHOD(candidate, RELEASE, release_fn)(candidate);
    }
    METHOD(endpoints, RELEASE, release_fn)(endpoints);
    return real_default_endpoint(enumerator, flow, role, endpoint);
}

static WINAPI int32_t mastering_voice(object *xaudio2, object **voice, uint32_t channels, uint32_t rate, uint32_t flags,
                                      const uint16_t *device, const void *effects, uint32_t category) {
    static const char prefix[] = "\\\\?\\SWD#MMDEVAPI#";
    struct naming *mine = NULL;
    uint32_t thread = win_thread();
    int32_t result;

    if (device && *device && real_default_endpoint && thread) {
        unsigned skip = 0, length = 0;
        while (prefix[skip] && lower(device[skip]) == lower((uint8_t)prefix[skip])) skip++;
        if (prefix[skip]) skip = 0;
        while (device[skip + length] && device[skip + length] != '#') length++;
        for (unsigned i = 0; i < 8 && !mine; i++) {
            uint32_t none = 0;
            if (__atomic_compare_exchange_n(&naming[i].thread, &none, thread, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
                mine = &naming[i];
        }
        if (mine) {
            mine->id = device + skip;
            mine->length = length;
        }
    }
    result = real_mastering_voice(xaudio2, voice, channels, rate, flags, device, effects, category);
    if (mine) __atomic_store_n(&mine->thread, 0, __ATOMIC_SEQ_CST);
    return result;
}

// The two methods pointed here, the first time the game has an XAudio2 object. An enumerator is
// made to reach its table, which every enumerator of mmdevapi shares.
static void take_methods(object *xaudio2) {
    static int state;  // 0 not tried, 1 being done or done
    const uint8_t *combase = win_image_of(*create_instance_import);
    win_protect_fn protect = win_export(win_image_of(*ntdll_import), "NtProtectVirtualMemory");
    initialize_fn initialize = win_export(combase, "CoInitializeEx");
    uninitialize_fn uninitialize = win_export(combase, "CoUninitialize");
    object *enumerator = NULL;
    int32_t initialized;

    if (__atomic_exchange_n(&state, 1, __ATOMIC_SEQ_CST) || !protect || !initialize || !uninitialize) return;
    initialized = initialize(NULL, 0 /* COINIT_MULTITHREADED */);
    if (!((create_instance_fn)*create_instance_import)(&enumerator_class, NULL, 1 /* CLSCTX_INPROC_SERVER */,
                                                       &enumerator_interface, &enumerator)) {
        uintptr_t *methods = enumerator->methods;
        real_default_endpoint = (default_endpoint_fn)methods[ENUMERATOR_DEFAULT_ENDPOINT];
        if ((uintptr_t)real_default_endpoint == (uintptr_t)default_endpoint ||
            !win_write_pointer(protect, &methods[ENUMERATOR_DEFAULT_ENDPOINT], (uintptr_t)default_endpoint))
            real_default_endpoint = NULL;
        METHOD(enumerator, RELEASE, release_fn)(enumerator);
    }
    if (initialized >= 0) uninitialize();
    if (!real_default_endpoint) return;
    real_mastering_voice = (mastering_voice_fn)xaudio2->methods[XAUDIO2_CREATE_MASTERING_VOICE];
    if (!win_write_pointer(protect, &xaudio2->methods[XAUDIO2_CREATE_MASTERING_VOICE], (uintptr_t)mastering_voice))
        real_mastering_voice = NULL;
}

static WINAPI int32_t create(object **xaudio2, uint32_t flags, uint32_t processor) {
    int32_t result = real_create(xaudio2, flags, processor);
    if (!result && xaudio2 && *xaudio2) take_methods(*xaudio2);
    return result;
}

static WINAPI int32_t create_version(object **xaudio2, uint32_t flags, uint32_t processor, uint32_t version) {
    int32_t result = real_create_version(xaudio2, flags, processor, version);
    if (!result && xaudio2 && *xaudio2) take_methods(*xaudio2);
    return result;
}

// ---- Run on the macOS side, when xaudio2_9.dll has just been mapped.

static void mapped(const struct pe_image *image) {
    // An export's entry reaches 4 GB above the image, so each goes through a jump in memory there:
    // mov rax, <the function here>; jmp rax.
    unsigned char jumps[24] = {0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0, 0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0};
    static int told;
    uintptr_t first = (uintptr_t)create, second = (uintptr_t)create_version;
    uint8_t *plain = pe_export(image, "XAudio2Create"), *versioned = pe_export(image, "XAudio2CreateWithVersionInfo");
    uint8_t *room;

    create_instance_import = pe_import_slot(image, "ole32.dll", "CoCreateInstance");
    free_import = pe_import_slot(image, "ole32.dll", "CoTaskMemFree");
    ntdll_import = pe_import_first(image, "ntdll.dll");
    if (!plain || !versioned || !create_instance_import || !free_import || !ntdll_import) {
        pad_log("controls: xaudio2_9.dll lacks an export or an import the named device needs, left as it is\n");
        return;
    }
    if (!(room = pe_room(image, sizeof(jumps)))) {
        pad_log("controls: no memory free within 4 GB above xaudio2_9.dll, left as it is\n");
        return;
    }
    memcpy(jumps + 2, &first, 8);
    memcpy(jumps + 14, &second, 8);
    memcpy(room, jumps, sizeof(jumps));
    real_create = (create_fn)plain;
    real_create_version = (create_version_fn)versioned;
    if (!pe_runs(room, sizeof(jumps)) || !pe_point_export(image, "XAudio2Create", room) ||
        !pe_point_export(image, "XAudio2CreateWithVersionInfo", room + 12)) {
        pad_log("controls: xaudio2_9.dll could not be written, left as it is\n");
        return;
    }
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: xaudio2_9.dll opens the audio device a game names\n");
}
#endif

void mgf_controls_xaudio2(void) {
#if defined(__x86_64__)
    if (!pad_part_off("xaudio2")) pe_on_map("xaudio2_9.dll", mapped);
#endif
}
