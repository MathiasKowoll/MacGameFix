/*
 * A cache of the GPU code of the pipelines D3DMetal compiles, kept by the worker.
 *
 * D3DMetal caches its DXIL translation (d3dm/<exe>/shaders.cache) but leaves the
 * last step, Metal IR to GPU code, to Metal's system cache, a fixed file of about
 * 1.1 GB (functions.data stayed at 1,172,017,152 bytes whatever
 * MTL_SHADER_CACHE_SIZE said). Phantom Blade Zero's 75,000 pipelines do not fit:
 * MTLCompilerService ran at 850-1050% CPU through the last third of every
 * launch's precompile.
 *
 * Metal 4's compiler can capture what it compiles (a pipeline data set
 * serializer on MTL4CompilerDescriptor) and look compiled code up in archives
 * before compiling (MTL4CompilerTaskOptions.lookupArchives). The worker hands
 * every compiler D3DMetal makes a serializer, writes what it captured to
 * <user cache>/notproton-bridge/pipelines/<game>/<GPU>-<OS build>/ every 2,000
 * pipelines and when it ends, and gives every pipeline compile the archives the
 * two previous sessions wrote. D3DMetal makes most pipelines through the classic
 * calls, which are cached one pipeline to an archive (below). A game sees nothing
 * of it, as of a driver's shader cache. NOTPROTON_BRIDGE_PIPELINE_CACHE=0 turns it off.
 * rosetta_pipeline_cache.mm runs the same cache inside a Rosetta game, where D3DMetal
 * is loaded into the game itself (pbz_pipeline_cache_configure names it).
 *
 * It also counts and times every pipeline Metal is asked for, by the call D3DMetal
 * used, so a run says which path D3DMetal takes and whether the cache helped.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <limits.h>
#include <unistd.h>
#include <objc/runtime.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern "C" NSString *MTLGetShaderCachePath(void);

namespace {

/* Every global with a destructor is made with new and never destroyed: at exit
 * D3DMetal's threads go on calling the hooks while static destructors run, and a
 * destroyed mutex aborted the process (libc++, "mutex lock failed"). */

enum PipelineCall { kMtl4Render, kMtl4Compute, kRender, kRenderError, kCompute, kComputeFunction, kMesh, kCalls };
const char *const kCallNames[kCalls] = {
    "MTL4 render", "MTL4 compute", "render", "render (error only)", "compute", "compute from function", "mesh",
};

std::atomic<uint64_t> call_count[kCalls], call_ns[kCalls];
std::atomic<uint64_t> total_calls;

/* Who is logging, which variable turns the cache off, and the folder under the user
 * cache it keeps its archives in: the bridge's worker and the Rosetta plugin differ. */
const char *log_prefix = "pbz-d3dmetal-worker";
const char *off_variable = "NOTPROTON_BRIDGE_PIPELINE_CACHE";
const char *cache_root = "notproton-bridge";

bool cache_on;
NSString *cache_directory;            /* retained */
NSArray *lookup_archives;             /* retained; read only once set */
std::mutex &serializer_mutex = *new std::mutex;
NSMutableArray *serializers;          /* retained; under serializer_mutex */
std::atomic<uint64_t> captured_since_flush;
std::atomic<uint32_t> archives_written;
constexpr uint64_t kFlushEvery = 2000;

/* The classic calls' cache: one MTLBinaryArchive per pipeline, found by a key
 * made from what its functions were made of.
 *
 * Metal inflates a classic archive opened from a file into malloc'd memory: one
 * of 165 MB, 2,000 of PBZ's pipelines, left 3.7 GB of MALLOC_LARGE resident
 * (6.3 GB at peak), and loading the 36 that two PBZ sessions wrote took a
 * process to an 80 GB footprint on a 48 GB Mac. So no archive stays open. A
 * library D3DMetal makes from data or a file is tagged with a hash of its bytes,
 * a function with its library's tag and its name, and a pipeline's key is a hash
 * of its functions' tags. A classic call opens only the archives filed under its
 * key, makes the pipeline with them, and lets them go. A key with no archive is
 * made as asked, and what it compiled is written to an archive of its own,
 * classic/<xx>/<key>-<pid>-<n>.bin, off the calling thread from a copy of the
 * descriptor. (Adding under one lock on the calling thread made 16 pipeline threads
 * queue: 140 ms a pipeline instead of 17-62.)
 *
 * The key leaves out function constants and pipeline state: Metal matches the
 * whole pipeline inside the archives, so a key shared by several pipelines only
 * means one more file to open. */
std::mutex &classic_mutex = *new std::mutex;
std::unordered_map<std::string, std::vector<std::string>> &classic_index =
    *new std::unordered_map<std::string, std::vector<std::string>>;   /* key -> files; under classic_mutex */
NSString *classic_directory;          /* retained */
dispatch_queue_t capture_queue;
dispatch_group_t capture_group;

/* Adding a pipeline to an archive makes a gpuarchiver-* folder of about 380 KB in
 * Metal's shader cache, which serializing reads and nothing ever removes: one PBZ run
 * of this cache left 67,321 of them, 36 GB. Loading a written archive makes none. As
 * in Mullion, an archive is in flight from before its add until it is let go, and a
 * sweep removes the folders made before the oldest archive in flight: at start, every
 * 16 archives let go, and at the end. What the classic cache writes stops at
 * <prefix>_MAX_MB (10240 MB): PBZ's pipelines come to about 84 KB each. */
std::mutex &flight_mutex = *new std::mutex;
std::vector<double> &in_flight = *new std::vector<double>;        /* start times; under flight_mutex */
std::mutex &sweep_mutex = *new std::mutex;
std::atomic<uint64_t> swept, let_go, kept_bytes, over_cap;
uint64_t cap_bytes = 10240ull << 20;
const char *cap_variable = "NOTPROTON_BRIDGE_PIPELINE_CACHE_MAX_MB";

/* An archive is written as <file>.part and renamed into place, so a process killed
 * while writing (wineserver kills a Wine process a second after it starts to end)
 * leaves no half archive under a real name; the next start removes the .part. */
NSURL *part_of(NSString *path)
{
    return [NSURL fileURLWithPath:[path stringByAppendingString:@".part"]];
}

bool put_in_place(NSString *path)
{
    return !rename([path stringByAppendingString:@".part"].fileSystemRepresentation, path.fileSystemRepresentation);
}

double wall_now()
{
    struct timespec t;
    clock_gettime(CLOCK_REALTIME, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

double begin_flight()
{
    const double start = wall_now();
    std::lock_guard<std::mutex> lock(flight_mutex);
    in_flight.push_back(start);
    return start;
}

void sweep();

void end_flight(double start)
{
    {
        std::lock_guard<std::mutex> lock(flight_mutex);
        for (auto it = in_flight.begin(); it != in_flight.end(); ++it)
            if (*it == start) { in_flight.erase(it); break; }
    }
    if (let_go.fetch_add(1) % 16 == 15) sweep();
}

/* Where Metal makes the gpuarchiver-* folders: its shader cache path, read each time
 * (D3DMetal sets it itself), and the process's own cache folder,
 * <user cache>/<bundle id>/com.apple.gpuarchiver. In a Rosetta game under NotProton
 * every folder went to the second (com.codeweavers.CrossOver.wineloader): 26,386 of
 * them, 11 GB, in PBZ's first minutes of the cache on 2026-11-01, none in the first. */
NSArray<NSString *> *archiver_folders()
{
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    NSString *metal_cache = MTLGetShaderCachePath();
    if (metal_cache.length) [folders addObject:metal_cache];
    char user_cache[PATH_MAX];
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    if (bundle.length && confstr(_CS_DARWIN_USER_CACHE_DIR, user_cache, sizeof(user_cache)))
        [folders addObject:[NSString pathWithComponents:@[@(user_cache), bundle, @"com.apple.gpuarchiver"]]];
    return folders;
}

/* An archive's folder is made after it is put in flight, so a folder older than the
 * cutoff, taken with the list held, is not one an archive in flight still needs. The
 * bundle's folder is shared by every Wine process of the launcher, whose archives in
 * flight this one does not know: a folder there goes only when it is a minute older
 * than that too, and an add takes seconds. */
void sweep()
{
    std::unique_lock<std::mutex> busy(sweep_mutex, std::try_to_lock);
    if (!busy.owns_lock()) return;
    @autoreleasepool
    {
        double cutoff;
        {
            std::lock_guard<std::mutex> lock(flight_mutex);
            cutoff = wall_now();
            for (double start : in_flight) cutoff = std::min(cutoff, start);
        }
        cutoff = std::min(cutoff, wall_now() - 60);
        for (NSString *metal_cache in archiver_folders())
        {
            DIR *folder = opendir(metal_cache.fileSystemRepresentation);
            uint64_t removed = 0;
            while (folder)
            {
                struct dirent *entry = readdir(folder);
                if (!entry) break;
                if (std::strncmp(entry->d_name, "gpuarchiver-", 12)) continue;
                NSString *path = [metal_cache stringByAppendingPathComponent:@(entry->d_name)];
                struct stat info;
                if (lstat(path.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) ||
                    info.st_birthtimespec.tv_sec + info.st_birthtimespec.tv_nsec / 1e9 >= cutoff)
                    continue;
                if ([[NSFileManager defaultManager] removeItemAtPath:path error:nil]) ++removed;
            }
            if (folder) closedir(folder);
            if (removed && !swept.fetch_add(removed))
                std::fprintf(stderr, "%s: pipeline cache: removed %llu gpuarchiver folders Metal left in %s\n", log_prefix,
                             static_cast<unsigned long long>(removed), metal_cache.UTF8String);
        }
    }
}
std::atomic<uint32_t> classic_written;
std::atomic<uint64_t> classic_hits, classic_misses, classic_failed, classic_unkeyed, classic_opened, classic_most;
char tag_key;                         /* the associated object holding a tag */
IMP original_library_data, original_library_file, original_function_name, original_function_constants,
    original_function_descriptor;
Class library_class;
id<MTLDevice> cache_device;           /* retained */

IMP original_new_compiler, original_mtl4_render, original_mtl4_compute;
IMP original_render, original_render_error, original_compute, original_compute_function, original_mesh;

struct CallTimer
{
    PipelineCall call;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    explicit CallTimer(PipelineCall which) : call(which) {}
    ~CallTimer()
    {
        const auto elapsed = std::chrono::steady_clock::now() - start;
        call_count[call].fetch_add(1, std::memory_order_relaxed);
        call_ns[call].fetch_add(std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed).count(),
                                std::memory_order_relaxed);
        const uint64_t total = total_calls.fetch_add(1, std::memory_order_relaxed) + 1;
        if (total % 5000 == 0) pbz_report_pipeline_calls();
    }
    static void pbz_report_pipeline_calls();
};

void CallTimer::pbz_report_pipeline_calls()
{
    for (int i = 0; i < kCalls; ++i)
    {
        const uint64_t count = call_count[i].load(std::memory_order_relaxed);
        if (!count) continue;
        std::fprintf(stderr, "%s: pipelines %s: %llu, %.2f ms each\n", log_prefix, kCallNames[i],
                     static_cast<unsigned long long>(count),
                     call_ns[i].load(std::memory_order_relaxed) / 1e6 / count);
    }
}

/* Writes what every serializer captured since the last time into new archives. */
void flush_serializers(const char *why) API_AVAILABLE(macos(26.0))
{
    std::lock_guard<std::mutex> lock(serializer_mutex);
    if (!captured_since_flush.exchange(0)) return;
    @autoreleasepool
    {
        for (id<MTL4PipelineDataSetSerializer> serializer in serializers)
        {
            NSString *name = [NSString stringWithFormat:@"archive-%d-%u.bin", getpid(),
                                       archives_written.fetch_add(1)];
            NSString *path = [cache_directory stringByAppendingPathComponent:name];
            NSError *error = nil;
            if (![serializer serializeAsArchiveAndFlushToURL:part_of(path) error:&error] || !put_in_place(path))
                std::fprintf(stderr, "%s: pipeline cache: writing %s failed (%s): %s\n", log_prefix,
                             name.UTF8String, why, error.localizedDescription.UTF8String ?: "unknown");
            else
                std::fprintf(stderr, "%s: pipeline cache: wrote %s (%s)\n", log_prefix, name.UTF8String, why);
        }
    }
}

void note_captured() API_AVAILABLE(macos(26.0))
{
    if (cache_on && captured_since_flush.fetch_add(1) + 1 >= kFlushEvery) flush_serializers("2000 pipelines");
}

id hook_new_compiler(id self, SEL cmd, MTL4CompilerDescriptor *descriptor, NSError **error) API_AVAILABLE(macos(26.0))
{
    using Fn = id (*)(id, SEL, MTL4CompilerDescriptor *, NSError **);
    if (!cache_on || (descriptor && descriptor.pipelineDataSetSerializer))
        return reinterpret_cast<Fn>(original_new_compiler)(self, cmd, descriptor, error);
    MTL4CompilerDescriptor *mine = descriptor ? [descriptor copy] : [[MTL4CompilerDescriptor alloc] init];
    MTL4PipelineDataSetSerializerDescriptor *serializer_descriptor =
        [[MTL4PipelineDataSetSerializerDescriptor alloc] init];
    serializer_descriptor.configuration = MTL4PipelineDataSetSerializerConfigurationCaptureBinaries;
    id<MTL4PipelineDataSetSerializer> serializer =
        [static_cast<id<MTLDevice>>(self) newPipelineDataSetSerializerWithDescriptor:serializer_descriptor];
    [serializer_descriptor release];
    if (serializer)
    {
        mine.pipelineDataSetSerializer = serializer;
        std::lock_guard<std::mutex> lock(serializer_mutex);
        [serializers addObject:serializer];
        [serializer release];
    }
    id compiler = reinterpret_cast<Fn>(original_new_compiler)(self, cmd, mine, error);
    [mine release];
    return compiler;
}

/* The task options with the previous runs' archives to look compiled code up in. */
MTL4CompilerTaskOptions *with_archives(MTL4CompilerTaskOptions *options) API_AVAILABLE(macos(26.0))
{
    if (!cache_on || !lookup_archives.count) return nil;
    MTL4CompilerTaskOptions *mine = options ? [options copy] : [[MTL4CompilerTaskOptions alloc] init];
    NSArray *existing = options.lookupArchives;
    mine.lookupArchives = existing.count ? [existing arrayByAddingObjectsFromArray:lookup_archives] : lookup_archives;
    return mine;
}

id hook_mtl4_render(id self, SEL cmd, MTL4PipelineDescriptor *descriptor, MTL4CompilerTaskOptions *options,
                    NSError **error) API_AVAILABLE(macos(26.0))
{
    using Fn = id (*)(id, SEL, MTL4PipelineDescriptor *, MTL4CompilerTaskOptions *, NSError **);
    CallTimer timer(kMtl4Render);
    MTL4CompilerTaskOptions *mine = with_archives(options);
    id state = reinterpret_cast<Fn>(original_mtl4_render)(self, cmd, descriptor, mine ?: options, error);
    [mine release];
    if (state) note_captured();
    return state;
}

id hook_mtl4_compute(id self, SEL cmd, MTL4ComputePipelineDescriptor *descriptor, MTL4CompilerTaskOptions *options,
                     NSError **error) API_AVAILABLE(macos(26.0))
{
    using Fn = id (*)(id, SEL, MTL4ComputePipelineDescriptor *, MTL4CompilerTaskOptions *, NSError **);
    CallTimer timer(kMtl4Compute);
    MTL4CompilerTaskOptions *mine = with_archives(options);
    id state = reinterpret_cast<Fn>(original_mtl4_compute)(self, cmd, descriptor, mine ?: options, error);
    [mine release];
    if (state) note_captured();
    return state;
}

/* The first 16 bytes of a SHA-256, as 32 hex digits. */
std::string hex_of(const unsigned char *digest)
{
    static const char digits[] = "0123456789abcdef";
    std::string text(32, '0');
    for (int i = 0; i < 16; ++i)
    {
        text[2 * i] = digits[digest[i] >> 4];
        text[2 * i + 1] = digits[digest[i] & 15];
    }
    return text;
}

void set_tag(id object, const unsigned char *digest)
{
    NSData *tag = [[NSData alloc] initWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    objc_setAssociatedObject(object, &tag_key, tag, OBJC_ASSOCIATION_RETAIN);
    [tag release];
}

NSData *tag_of(id object)
{
    return object ? objc_getAssociatedObject(object, &tag_key) : nil;
}

/* A function's tag: its library's, a kind, and the names it was made from. */
void tag_function(id function, id library, unsigned char kind, NSString *name, NSString *specialized)
{
    NSData *library_tag = tag_of(library);
    if (!function || !library_tag) return;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    CC_SHA256_Update(&context, library_tag.bytes, static_cast<CC_LONG>(library_tag.length));
    CC_SHA256_Update(&context, &kind, 1);
    const char *text = name.UTF8String ?: "";
    CC_SHA256_Update(&context, text, static_cast<CC_LONG>(std::strlen(text) + 1));
    text = specialized.UTF8String ?: "";
    CC_SHA256_Update(&context, text, static_cast<CC_LONG>(std::strlen(text) + 1));
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    set_tag(function, digest);
}

id hook_function_name(id self, SEL cmd, NSString *name)
{
    id function = reinterpret_cast<id (*)(id, SEL, NSString *)>(original_function_name)(self, cmd, name);
    tag_function(function, self, 0, name, nil);
    return function;
}

id hook_function_constants(id self, SEL cmd, NSString *name, MTLFunctionConstantValues *values, NSError **error)
{
    id function = reinterpret_cast<id (*)(id, SEL, NSString *, MTLFunctionConstantValues *, NSError **)>(
        original_function_constants)(self, cmd, name, values, error);
    tag_function(function, self, 1, name, nil);
    return function;
}

id hook_function_descriptor(id self, SEL cmd, MTLFunctionDescriptor *descriptor, NSError **error)
{
    id function = reinterpret_cast<id (*)(id, SEL, MTLFunctionDescriptor *, NSError **)>(
        original_function_descriptor)(self, cmd, descriptor, error);
    tag_function(function, self, 2, descriptor.name, descriptor.specializedName);
    return function;
}

IMP replace(Class cls, const char *selector, IMP replacement, IMP *original);

/* Tags a library, and the first time hooks its class's function calls. Libraries
 * of another class keep no tag, so their pipelines are made without the cache. */
void tag_library(id library, const unsigned char *digest)
{
    {
        std::lock_guard<std::mutex> lock(classic_mutex);
        if (!library_class)
        {
            library_class = object_getClass(library);
            replace(library_class, "newFunctionWithName:",
                                             reinterpret_cast<IMP>(hook_function_name), &original_function_name);
            replace(library_class, "newFunctionWithName:constantValues:error:",
                                                  reinterpret_cast<IMP>(hook_function_constants), &original_function_constants);
            replace(library_class, "newFunctionWithDescriptor:error:",
                                                   reinterpret_cast<IMP>(hook_function_descriptor), &original_function_descriptor);
        }
        if (object_getClass(library) != library_class || !original_function_name || !original_function_constants ||
            !original_function_descriptor)
            return;
    }
    set_tag(library, digest);
}

id hook_library_data(id self, SEL cmd, dispatch_data_t data, NSError **error)
{
    id library = reinterpret_cast<id (*)(id, SEL, dispatch_data_t, NSError **)>(original_library_data)(
        self, cmd, data, error);
    if (!library || !data) return library;
    __block CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    dispatch_data_apply(data, ^bool(dispatch_data_t, size_t, const void *bytes, size_t size) {
        CC_SHA256_Update(&context, bytes, static_cast<CC_LONG>(size));
        return true;
    });
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    tag_library(library, digest);
    return library;
}

id hook_library_file(id self, SEL cmd, NSString *path, NSError **error)
{
    id library = reinterpret_cast<id (*)(id, SEL, NSString *, NSError **)>(original_library_file)(
        self, cmd, path, error);
    if (!library || !path) return library;
    @autoreleasepool
    {
        NSData *bytes = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (!bytes) return library;
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(bytes.bytes, static_cast<CC_LONG>(bytes.length), digest);
        tag_library(library, digest);
    }
    return library;
}

/* A pipeline's key from its functions' tags; empty when one has none. */
std::string key_of(MTLRenderPipelineDescriptor *descriptor)
{
    NSData *vertex = tag_of(descriptor.vertexFunction), *fragment = tag_of(descriptor.fragmentFunction);
    if ((descriptor.vertexFunction && !vertex) || (descriptor.fragmentFunction && !fragment) || (!vertex && !fragment))
        return {};
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const unsigned char kind[3] = {'r', static_cast<unsigned char>(vertex ? 'v' : '-'), static_cast<unsigned char>(fragment ? 'f' : '-')};
    CC_SHA256_Update(&context, kind, sizeof(kind));
    if (vertex) CC_SHA256_Update(&context, vertex.bytes, static_cast<CC_LONG>(vertex.length));
    if (fragment) CC_SHA256_Update(&context, fragment.bytes, static_cast<CC_LONG>(fragment.length));
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return hex_of(digest);
}

std::string key_of(MTLComputePipelineDescriptor *descriptor)
{
    NSData *compute = tag_of(descriptor.computeFunction);
    if (!compute) return {};
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const unsigned char kind = 'c';
    CC_SHA256_Update(&context, &kind, 1);
    CC_SHA256_Update(&context, compute.bytes, static_cast<CC_LONG>(compute.length));
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return hex_of(digest);
}

NSString *classic_folder(const std::string &key)
{
    return [classic_directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%.2s", key.c_str()]];
}

/* Writes what a classic call compiled to an archive of its own, off the calling thread. */
template <typename Descriptor> void classic_capture_later(Descriptor *descriptor, std::string key, bool render)
{
    if (kept_bytes.load(std::memory_order_relaxed) >= cap_bytes)
    {
        if (!over_cap.fetch_add(1))
            std::fprintf(stderr, "%s: pipeline cache: %llu MB kept, the cap; later pipelines are not kept\n",
                         log_prefix, static_cast<unsigned long long>(cap_bytes >> 20));
        return;
    }
    /* A block copies a C++ object it names, not one it reaches through a reference.
     * The descriptor is copied here, on the calling thread: D3DMetal goes on using
     * its own and changes it for the next pipeline while this one is being kept, and
     * reading it from the other thread then corrupted the heap (Rosetta, in-process). */
    descriptor = [descriptor copy];
    dispatch_group_async(capture_group, capture_queue, ^{
        const double flight = begin_flight();
        @autoreleasepool
        {
            MTLBinaryArchiveDescriptor *empty = [[MTLBinaryArchiveDescriptor alloc] init];
            id<MTLBinaryArchive> archive = [cache_device newBinaryArchiveWithDescriptor:empty error:nil];
            [empty release];
            NSError *error = nil;
            BOOL added = archive && (render
                ? [archive addRenderPipelineFunctionsWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                                               error:&error]
                : [archive addComputePipelineFunctionsWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
                                                                error:&error]);
            NSString *folder = classic_folder(key);
            NSString *name = [NSString stringWithFormat:@"%s-%d-%u.bin", key.c_str(), getpid(),
                                       classic_written.fetch_add(1)];
            NSString *path = [folder stringByAppendingPathComponent:name];
            if (added)
            {
                [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES
                                                           attributes:nil error:nil];
                added = [archive serializeToURL:part_of(path) error:&error] && put_in_place(path);
            }
            if (!added && classic_failed.fetch_add(1) < 5)
                std::fprintf(stderr, "%s: pipeline cache: keeping a pipeline failed: %s\n", log_prefix,
                             error.localizedDescription.UTF8String ?: "unknown");
            if (added)
            {
                kept_bytes.fetch_add([[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize],
                                     std::memory_order_relaxed);
                std::lock_guard<std::mutex> lock(classic_mutex);
                classic_index[key].push_back(path.UTF8String);
            }
            [archive release];
        }
        end_flight(flight);
        [descriptor release];
    });
}

/* A classic call through the cache: looked up first, compiled and kept on a miss. */
template <typename Descriptor> id classic_call(IMP original, id self, SEL cmd, Descriptor *descriptor,
                                               NSUInteger options, id *reflection, NSError **error, bool cached,
                                               bool render)
{
    using Fn = id (*)(id, SEL, id, NSUInteger, id *, NSError **);
    if (!cached || !classic_directory || !descriptor)
        return reinterpret_cast<Fn>(original)(self, cmd, descriptor, options, reflection, error);
    const std::string key = key_of(descriptor);
    if (key.empty())
    {
        classic_unkeyed.fetch_add(1, std::memory_order_relaxed);
        return reinterpret_cast<Fn>(original)(self, cmd, descriptor, options, reflection, error);
    }
    std::vector<std::string> files;
    {
        std::lock_guard<std::mutex> lock(classic_mutex);
        auto found = classic_index.find(key);
        if (found != classic_index.end()) files = found->second;
    }
    if (!files.empty())
    {
        /* The call itself stays out of any autorelease pool of this code: the
         * reflection it hands back is autoreleased, and a pool drained here freed it
         * under D3DMetal, which released it again. */
        id state = nil;
        bool archives_tried = false;
        NSMutableArray *archives = [[NSMutableArray alloc] initWithCapacity:files.size()];
        @autoreleasepool
        {
            for (const std::string &file : files)
            {
                MTLBinaryArchiveDescriptor *source = [[MTLBinaryArchiveDescriptor alloc] init];
                source.url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:file.c_str()]];
                id<MTLBinaryArchive> archive = [static_cast<id<MTLDevice>>(self) newBinaryArchiveWithDescriptor:source
                                                                                                         error:nil];
                [source release];
                if (!archive) continue;
                [archives addObject:archive];
                [archive release];
            }
        }
        classic_opened.fetch_add(archives.count, std::memory_order_relaxed);
        uint64_t most = classic_most.load(std::memory_order_relaxed);
        while (archives.count > most && !classic_most.compare_exchange_weak(most, archives.count)) {}
        archives_tried = archives.count != 0;
        if (archives.count)
        {
            Descriptor *mine = [descriptor copy];
            NSArray *existing = descriptor.binaryArchives;
            NSArray *all = existing.count ? [existing arrayByAddingObjectsFromArray:archives] : nil;
            mine.binaryArchives = all ?: archives;
            /* No MTLPipelineOptionFailOnBinaryArchiveMiss: with it, in a Rosetta game
             * with D3DMetal in-process, 6 warm runs in 31 of the cache probe ended in
             * malloc's heap-corruption abort on the main thread; without it 1 in 32,
             * as the probe does with no cache at all (1 in 20). Metal uses the
             * archives when they hold the pipeline and compiles it otherwise, so a
             * key shared by two pipelines costs the second a compile it is not kept
             * for. */
            state = reinterpret_cast<Fn>(original)(self, cmd, mine, options, reflection, error);
            [mine release];
        }
        [archives release];
        if (state)
        {
            classic_hits.fetch_add(1, std::memory_order_relaxed);
            return state;
        }
        if (archives_tried)
        {
            /* Compiled with the archives and failed: the same call without them would too. */
            return state;
        }
    }
    id state = reinterpret_cast<Fn>(original)(self, cmd, descriptor, options, reflection, error);
    if (state)
    {
        classic_misses.fetch_add(1, std::memory_order_relaxed);
        classic_capture_later(descriptor, key, render);
    }
    return state;
}

/* Whether D3DMetal made the call, from the address it returns to: Metal's
 * driver makes its own pipelines through the same calls (its acceleration
 * structure kernels), and adding those to an archive made Metal's compiler
 * call a NULL pointer. Only D3DMetal's are cached. */
bool called_by_d3dmetal(const void *return_address)
{
    Dl_info info;
    const bool known = dladdr(return_address, &info) && info.dli_fname;
    if (known && std::strstr(info.dli_fname, "/D3DMetal")) return true;
    static std::atomic<int> said;
    if (said.fetch_add(1) < 4)
        std::fprintf(stderr, "%s: pipeline cache: not caching a pipeline made from %s\n", log_prefix,
                     known ? info.dli_fname : "an unknown image");
    return false;
}

/* The classic calls are counted and timed; D3DMetal's render and compute descriptors are cached. */
id hook_render(id self, SEL cmd, MTLRenderPipelineDescriptor *descriptor, NSUInteger options, id *reflection,
               NSError **error)
{
    CallTimer timer(kRender);
    const bool cached = called_by_d3dmetal(__builtin_return_address(0));
    return classic_call(original_render, self, cmd, descriptor, options, reflection, error, cached, true);
}

id hook_render_error(id self, SEL cmd, id descriptor, NSError **error)
{
    CallTimer timer(kRenderError);
    return reinterpret_cast<id (*)(id, SEL, id, NSError **)>(original_render_error)(self, cmd, descriptor, error);
}

id hook_compute(id self, SEL cmd, MTLComputePipelineDescriptor *descriptor, NSUInteger options, id *reflection,
                NSError **error)
{
    CallTimer timer(kCompute);
    const bool cached = called_by_d3dmetal(__builtin_return_address(0));
    return classic_call(original_compute, self, cmd, descriptor, options, reflection, error, cached, false);
}

id hook_compute_function(id self, SEL cmd, id function, NSError **error)
{
    CallTimer timer(kComputeFunction);
    return reinterpret_cast<id (*)(id, SEL, id, NSError **)>(original_compute_function)(self, cmd, function, error);
}

id hook_mesh(id self, SEL cmd, id descriptor, NSUInteger options, id *reflection, NSError **error)
{
    CallTimer timer(kMesh);
    return reinterpret_cast<id (*)(id, SEL, id, NSUInteger, id *, NSError **)>(original_mesh)(
        self, cmd, descriptor, options, reflection, error);
}

/* The original is stored before the hook goes in: another thread may call the
 * method the moment it does (D3DMetal makes functions on 16 threads while the
 * library class is hooked), and found it NULL when it was stored after. */
IMP replace(Class cls, const char *selector, IMP replacement, IMP *original)
{
    Method method = class_getInstanceMethod(cls, sel_registerName(selector));
    if (!method)
    {
        std::fprintf(stderr, "%s: pipeline cache: %s has no %s\n", log_prefix, class_getName(cls), selector);
        *original = nullptr;
        return nullptr;
    }
    __atomic_store_n(original, method_getImplementation(method), __ATOMIC_RELEASE);
    method_setImplementation(method, replacement);
    return *original;
}

NSString *sanitized(NSString *text)
{
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    return [[text componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}

/* Every session captures every pipeline it compiled or found in an archive, so
 * its archives hold all it used: the two most recent sessions' are kept, the
 * older ones go. Archives are named archive-<pid>-<n>.bin. */
void prune_sessions()
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableDictionary *newest = [NSMutableDictionary dictionary];   /* session -> its newest time */
    NSArray *names = [files contentsOfDirectoryAtPath:cache_directory error:nil];
    for (NSString *file in names)
    {
        NSArray *parts = [file componentsSeparatedByString:@"-"];
        if (![file hasPrefix:@"archive-"] || ![file hasSuffix:@".bin"] || parts.count != 3) continue;
        NSDate *date = [[files attributesOfItemAtPath:[cache_directory stringByAppendingPathComponent:file] error:nil]
                        fileModificationDate];
        NSDate *seen = newest[parts[1]];
        if (date && (!seen || [date compare:seen] == NSOrderedDescending)) newest[parts[1]] = date;
    }
    NSArray *sessions = [newest keysSortedByValueUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [b compare:a];
    }];
    if (sessions.count <= 2) return;
    NSSet *kept = [NSSet setWithArray:[sessions subarrayWithRange:NSMakeRange(0, 2)]];
    for (NSString *file in names)
    {
        NSArray *parts = [file componentsSeparatedByString:@"-"];
        if (![file hasPrefix:@"archive-"] || ![file hasSuffix:@".bin"] || parts.count != 3 ||
            [kept containsObject:parts[1]]) continue;
        [files removeItemAtPath:[cache_directory stringByAppendingPathComponent:file] error:nil];
        std::fprintf(stderr, "%s: pipeline cache: removed %s, from an older session\n", log_prefix,
                     file.UTF8String);
    }
}

} // namespace

/* The Rosetta plugin runs the same cache inside the game; it names itself, its
 * variables and its folder before starting. */
extern "C" void pbz_pipeline_cache_configure(const char *prefix, const char *off, const char *cap, const char *root)
{
    log_prefix = prefix;
    off_variable = off;
    cap_variable = cap;
    cache_root = root;
}

extern "C" void pbz_pipeline_cache_start(const char *game)
{
    @autoreleasepool
    {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return;
        Class device_class = object_getClass(device);
        replace(device_class, "newRenderPipelineStateWithDescriptor:options:reflection:error:",
                                  reinterpret_cast<IMP>(hook_render), &original_render);
        replace(device_class, "newRenderPipelineStateWithDescriptor:error:",
                                        reinterpret_cast<IMP>(hook_render_error), &original_render_error);
        replace(device_class, "newComputePipelineStateWithDescriptor:options:reflection:error:",
                                   reinterpret_cast<IMP>(hook_compute), &original_compute);
        replace(device_class, "newComputePipelineStateWithFunction:error:",
                                            reinterpret_cast<IMP>(hook_compute_function), &original_compute_function);
        replace(device_class, "newRenderPipelineStateWithMeshDescriptor:options:reflection:error:",
                                reinterpret_cast<IMP>(hook_mesh), &original_mesh);

        if (@available(macOS 26.0, *))
        {
            const char *setting = std::getenv(off_variable);
            cache_on = !(setting && !std::strcmp(setting, "0"));
            MTL4CompilerDescriptor *probe_descriptor = [[MTL4CompilerDescriptor alloc] init];
            id<MTL4Compiler> probe = [device newCompilerWithDescriptor:probe_descriptor error:nil];
            [probe_descriptor release];
            if (!probe)
            {
                std::fprintf(stderr, "%s: pipeline cache: no Metal 4 compiler\n", log_prefix);
                cache_on = false;
            }
            else
            {
                Class compiler_class = object_getClass(probe);
                replace(compiler_class, "newRenderPipelineStateWithDescriptor:compilerTaskOptions:error:",
                                               reinterpret_cast<IMP>(hook_mtl4_render), &original_mtl4_render);
                replace(compiler_class, "newComputePipelineStateWithDescriptor:compilerTaskOptions:error:",
                                                reinterpret_cast<IMP>(hook_mtl4_compute), &original_mtl4_compute);
                [probe release];
            }
            if (cache_on)
                replace(device_class, "newCompilerWithDescriptor:error:",
                                                reinterpret_cast<IMP>(hook_new_compiler), &original_new_compiler);
            if (cache_on && (!original_new_compiler || !original_mtl4_render || !original_mtl4_compute))
                cache_on = false;

            if (cache_on)
            {
                char base[PATH_MAX] = {0};
                confstr(_CS_DARWIN_USER_CACHE_DIR, base, sizeof(base));
                NSString *os = sanitized([[NSProcessInfo processInfo] operatingSystemVersionString]);
                NSString *gpu = sanitized(device.name);
                NSString *name = sanitized([NSString stringWithUTF8String:game && *game ? game : "unknown"]);
                cache_directory = [[[[[NSString stringWithUTF8String:base]
                    stringByAppendingPathComponent:[NSString stringWithFormat:@"%s/pipelines", cache_root]]
                    stringByAppendingPathComponent:name]
                    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", gpu, os]] retain];
                [[NSFileManager defaultManager] createDirectoryAtPath:cache_directory withIntermediateDirectories:YES
                                                           attributes:nil error:nil];
                /* Spotlight indexed the thousands of archives a first PBZ run writes,
                 * mds_stores at 87% of a core beside the game. */
                [[NSFileManager defaultManager]
                    createFileAtPath:[[NSString stringWithUTF8String:base]
                                         stringByAppendingPathComponent:[NSString stringWithFormat:@"%s/.metadata_never_index", cache_root]]
                            contents:nil attributes:nil];
                prune_sessions();
                /* Metal writes an archive through a <UUID>.metallib beside it; a process
                 * killed while writing leaves that, empty, and this code's .part. */
                NSDirectoryEnumerator *parts = [[NSFileManager defaultManager] enumeratorAtPath:cache_directory];
                for (NSString *relative in parts)
                    if ([relative hasSuffix:@".part"] || [relative hasSuffix:@".metallib"])
                        [[NSFileManager defaultManager]
                            removeItemAtPath:[cache_directory stringByAppendingPathComponent:relative] error:nil];
                NSMutableArray *archives = [NSMutableArray array];
                uint64_t bytes = 0;
                for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cache_directory error:nil])
                {
                    if (![file hasPrefix:@"archive-"] || ![file hasSuffix:@".bin"]) continue;
                    NSString *path = [cache_directory stringByAppendingPathComponent:file];
                    NSError *error = nil;
                    id<MTL4Archive> archive = [device newArchiveWithURL:[NSURL fileURLWithPath:path] error:&error];
                    if (!archive)
                    {
                        std::fprintf(stderr, "%s: pipeline cache: %s does not load (%s)\n", log_prefix,
                                     file.UTF8String, error.localizedDescription.UTF8String ?: "unknown");
                        continue;
                    }
                    [archives addObject:archive];
                    [archive release];
                    bytes += [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
                }
                lookup_archives = [archives copy];
                serializers = [[NSMutableArray alloc] init];

                /* The first classic cache kept every session's pipelines in a few big
                 * archives, flat in the directory; they are not opened any more. */
                uint64_t classic_bytes = 0, classic_files = 0;
                for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cache_directory error:nil])
                    if ([file hasPrefix:@"classic-"] && [file hasSuffix:@".bin"])
                        [[NSFileManager defaultManager]
                            removeItemAtPath:[cache_directory stringByAppendingPathComponent:file] error:nil];
                classic_directory = [[cache_directory stringByAppendingPathComponent:@"classic"] retain];
                NSDirectoryEnumerator *walk = [[NSFileManager defaultManager] enumeratorAtPath:classic_directory];
                for (NSString *relative in walk)
                {
                    NSString *file = relative.lastPathComponent;
                    if (![file hasSuffix:@".bin"] || file.length < 33) continue;
                    classic_index[std::string(file.UTF8String, 32)].push_back(
                        [classic_directory stringByAppendingPathComponent:relative].UTF8String);
                    classic_bytes += walk.fileAttributes.fileSize;
                    ++classic_files;
                }
                kept_bytes = classic_bytes;
                const char *cap = std::getenv(cap_variable);
                if (cap && std::atoll(cap) > 0) cap_bytes = static_cast<uint64_t>(std::atoll(cap)) << 20;
                sweep();
                cache_device = [device retain];
                capture_queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
                capture_group = dispatch_group_create();
                replace(device_class, "newLibraryWithData:error:",
                                                reinterpret_cast<IMP>(hook_library_data), &original_library_data);
                replace(device_class, "newLibraryWithFile:error:",
                                                reinterpret_cast<IMP>(hook_library_file), &original_library_file);
                std::fprintf(stderr, "%s: pipeline cache: %lu Metal 4 archives (%.1f MB) and %llu "
                             "classic pipelines in %zu keys (%.1f MB) in %s\n", log_prefix,
                             static_cast<unsigned long>(lookup_archives.count), bytes / 1e6,
                             static_cast<unsigned long long>(classic_files), classic_index.size(), classic_bytes / 1e6,
                             cache_directory.UTF8String);
            }
        }
        [device release];
    }
}

/* Writes what was captured since the last archive, and says what Metal was asked for. */
extern "C" void pbz_pipeline_cache_finish_within(const char *why, double seconds)
{
    if (@available(macOS 26.0, *))
        if (cache_on) flush_serializers(why);
    if (cache_on && capture_group)
    {
        if (dispatch_group_wait(capture_group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC))))
            std::fprintf(stderr, "%s: pipeline cache: pipelines still being kept after %.1f s, left to the next start\n",
                         log_prefix, seconds);
        sweep();
        std::fprintf(stderr, "%s: pipeline cache: classic %llu made with archives, %llu compiled and kept, "
                     "%llu not keyed; %llu archives opened, at most %llu for one pipeline; %.1f MB kept of a %llu MB "
                     "cap, %llu not kept over it; %llu gpuarchiver folders removed\n", log_prefix,
                     static_cast<unsigned long long>(classic_hits.load()),
                     static_cast<unsigned long long>(classic_misses.load()),
                     static_cast<unsigned long long>(classic_unkeyed.load()),
                     static_cast<unsigned long long>(classic_opened.load()),
                     static_cast<unsigned long long>(classic_most.load()), kept_bytes.load() / 1e6,
                     static_cast<unsigned long long>(cap_bytes >> 20),
                     static_cast<unsigned long long>(over_cap.load()),
                     static_cast<unsigned long long>(swept.load()));
    }
    CallTimer::pbz_report_pipeline_calls();
}

extern "C" void pbz_pipeline_cache_finish(const char *why)
{
    pbz_pipeline_cache_finish_within(why, 120);
}
