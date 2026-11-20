/*
 * The worker's pipeline cache (pipeline_cache.mm) for a game that runs D3DMetal in
 * its own process, as a game on the Rosetta side of a runner does.
 *
 * Metal's system cache, a fixed file of about 1.1 GB, fills during Phantom Blade
 * Zero's precompile: on the Preview runner under Rosetta functions2.data stood at
 * 1,110,048,768 bytes and the precompile slowed from about 64% on, every pipeline
 * after that compiled again on every launch.
 *
 * NotProton loads this library into every process of a launch whose
 * NOTPROTON_ROSETTA_PIPELINE_CACHE plugin is on (DYLD_INSERT_LIBRARIES). Nothing
 * happens until D3DMetal itself asks Metal for a device: MTLCreateSystemDefaultDevice
 * and MTLCopyAllDevices are interposed, and the first call made from D3DMetal's image
 * starts the cache, after the call has returned, outside any loader lock. Other
 * processes, and the bridge's worker, which keeps its own cache, are left alone.
 *
 * Archives go to <user cache>/notproton-rosetta/pipelines/<exe>/<GPU>-<OS build>/.
 * NOTPROTON_ROSETTA_PIPELINE_CACHE_MAX_MB caps what is written (10240).
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mach-o/dyld.h>

extern "C" void pbz_pipeline_cache_configure(const char *prefix, const char *off, const char *cap, const char *root);
extern "C" void pbz_pipeline_cache_start(const char *game);
extern "C" void pbz_pipeline_cache_finish_within(const char *why, double seconds);

namespace {

std::atomic<bool> started;

/* wineserver kills a Wine process about a second after it starts to end, so the end
 * waits a little for pipelines still being written; what is cut off is compiled and
 * kept again next time, and the next start removes its folders and .part files. */
void finish_at_exit()
{
    pbz_pipeline_cache_finish_within("the game ended", 0.3);
}

/* Starts the cache the first time D3DMetal asks for a device. */
void start_for(const void *caller)
{
    if (started.load(std::memory_order_acquire)) return;
    Dl_info info;
    if (!dladdr(caller, &info) || !info.dli_fname || !std::strstr(info.dli_fname, "/D3DMetal")) return;
    /* The bridge's worker loads D3DMetal too, and caches with its own copy of this code. */
    const char *main_image = _dyld_get_image_name(0);
    if (main_image && std::strstr(main_image, "pbz-d3dmetal-worker")) return;
    if (started.exchange(true)) return;
    pbz_pipeline_cache_configure("notproton-rosetta", "NOTPROTON_ROSETTA_PIPELINE_CACHE",
                                 "NOTPROTON_ROSETTA_PIPELINE_CACHE_MAX_MB", "notproton-rosetta");
    std::fprintf(stderr, "notproton-rosetta: pipeline cache: starting for %s\n", getprogname());
    pbz_pipeline_cache_start(getprogname());
    std::atexit(finish_at_exit);
}

id<MTLDevice> interposed_create_device(void)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    start_for(__builtin_return_address(0));
    return device;
}

NSArray<id<MTLDevice>> *interposed_copy_devices(void)
{
    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
    start_for(__builtin_return_address(0));
    return devices;
}

} // namespace

/* dyld's interposing: every other image's calls come here; this image's own go to Metal. */
__attribute__((used, section("__DATA,__interpose"))) static const struct
{
    const void *replacement;
    const void *original;
} interposers[] = {
    {reinterpret_cast<const void *>(interposed_create_device), reinterpret_cast<const void *>(MTLCreateSystemDefaultDevice)},
    {reinterpret_cast<const void *>(interposed_copy_devices), reinterpret_cast<const void *>(MTLCopyAllDevices)},
};
