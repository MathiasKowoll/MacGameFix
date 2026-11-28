// Compiled shaders kept whole, as a game starts: ShaderCache.swift's work, done by the game itself.
//
// Metal keeps a process's compiled functions under the process's bundle, in
// <user cache>/<bundle id>/com.apple.metal/<GPU and macOS>/functions.data, functions1.data, ...,
// each with a .list beside it. A process takes one file no other process holds, keeps a lock on
// it while it runs, and reads that one alone. NotProton starts each game from a bundle of its own
// (com.notproton.launcher.<app id>), and the processes of a start (Wine's explorer, Steam's
// launcher for the game, the game, its crash handler) each take one, so which one the game gets
// changes from one start to the next, and it compiles again what another file held.
//
// NotProton loads this library into every process of a game whose row is on, before the game's
// code runs. Each looks at its bundle's folders: while no process holds any of the files, the
// fullest is cloned over the others (an APFS clone, no space of its own until written to), with
// every file locked until the clones are in place. The first process of a start finds them free
// and does it; the ones after find them the same, or one held, and leave them. So the game starts
// from the fullest file at every start, where the menu bar agent does it only after the game is
// closed, and only on a Mac where it runs.
//
// Nothing else: no hook, no patch, nothing of the game's or Wine's code is touched.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#include "notproton_plugin.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <sys/clonefile.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#define TAG "mgf-shaders"
#define PREFIX "com.notproton.launcher."
#define MAX_FILES 32

static const struct np_plugin_api *api;

#define say(...) do { if (api) api->log(TAG, __VA_ARGS__); } while (0)

static long long file_size(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 ? (long long)st.st_size : -1;
}

// functions, functions1, functions2, functions3, and any further numbered one Metal made.
static int names(const char *dir, int out[MAX_FILES]) {
    int n = 0;
    for (int i = 0; i < 4; i++) out[n++] = i;
    DIR *d = opendir(dir);
    if (!d) return n;
    struct dirent *e;
    while ((e = readdir(d)) && n < MAX_FILES) {
        const char *s = e->d_name;
        size_t len = strlen(s);
        if (strncmp(s, "functions", 9) != 0 || len <= 14 || strcmp(s + len - 5, ".data") != 0) continue;
        int k = 0, digits = 0;
        for (const char *p = s + 9; p < s + len - 5; p++, digits++) {
            if (*p < '0' || *p > '9' || k > 100000) { digits = -1; break; }
            k = k * 10 + (*p - '0');
        }
        if (digits <= 0 || k < 4) continue;
        int seen = 0;
        for (int i = 0; i < n; i++) seen |= out[i] == k;
        if (!seen) out[n++] = k;
    }
    closedir(d);
    return n;
}

static void file_path(char *out, size_t len, const char *dir, int k, const char *ext) {
    if (k == 0) snprintf(out, len, "%s/functions.%s", dir, ext);
    else snprintf(out, len, "%s/functions%d.%s", dir, k, ext);
}

static int clone_over(const char *from, const char *to) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s.mgf-new", to);
    unlink(tmp);
    if (clonefile(from, tmp, 0) != 0) return -1;
    if (rename(tmp, to) != 0) { unlink(tmp); return -1; }
    return 0;
}

// One folder: 1 when it copied, 0 when there was nothing to do or it is in use, -1 on a failure.
static int keep(const char *dir) {
    int files[MAX_FILES];
    int n = names(dir, files);
    long long data[MAX_FILES], list[MAX_FILES], most = -1;
    int best = -1;
    char path[PATH_MAX];
    for (int i = 0; i < n; i++) {
        file_path(path, sizeof path, dir, files[i], "data"); data[i] = file_size(path);
        file_path(path, sizeof path, dir, files[i], "list"); list[i] = file_size(path);
        if (data[i] > most) { most = data[i]; best = i; }
    }
    if (best < 0 || most <= 0 || list[best] < 0) return 0;
    int same = 1;
    for (int i = 0; i < n; i++) same &= data[i] == most && list[i] == list[best];
    if (same) return 0;

    // Metal keeps a lock on the file a process took: all of them free means nobody uses the
    // folder, and they stay locked here until the clones are in place.
    int held[MAX_FILES], nheld = 0, result = 0, copied = 0;
    for (int i = 0; i < n; i++) {
        if (data[i] < 0) continue;
        file_path(path, sizeof path, dir, files[i], "data");
        int fd = open(path, O_RDONLY);
        if (fd < 0) { result = -1; goto out; }
        held[nheld++] = fd;
        if (flock(fd, LOCK_EX | LOCK_NB) != 0) goto out;
    }
    char from[PATH_MAX], to[PATH_MAX];
    for (int i = 0; i < n; i++) {
        if (i == best || (data[i] == most && list[i] == list[best])) continue;
        file_path(from, sizeof from, dir, files[best], "data");
        file_path(to, sizeof to, dir, files[i], "data");
        if (clone_over(from, to) != 0) { say("%s: cannot clone over %s: %s", dir, to, strerror(errno)); result = -1; goto out; }
        file_path(from, sizeof from, dir, files[best], "list");
        file_path(to, sizeof to, dir, files[i], "list");
        if (clone_over(from, to) != 0) { say("%s: cannot clone over %s: %s", dir, to, strerror(errno)); result = -1; goto out; }
        copied++;
    }
    if (copied) {
        say("the fullest shader cache (%lld bytes) cloned over %d other%s in %s", most, copied, copied == 1 ? "" : "s", dir);
        result = 1;
    }
out:
    for (int i = 0; i < nheld; i++) { flock(held[i], LOCK_UN); close(held[i]); }
    return result;
}

// The bundle Metal files this process's shaders under, when it is one of NotProton's games.
static int bundle_id(char *out, size_t len) {
    CFBundleRef main = CFBundleGetMainBundle();
    CFStringRef id = main ? CFBundleGetIdentifier(main) : NULL;
    if (!id || !CFStringGetCString(id, out, (CFIndex)len, kCFStringEncodingUTF8)) return 0;
    return strncmp(out, PREFIX, strlen(PREFIX)) == 0 && strchr(out, '/') == NULL;
}

__attribute__((constructor)) static void mgf_shaders(void) {
    char id[256], root[PATH_MAX], metal[PATH_MAX], dir[PATH_MAX];
    // The tests stand in for the user cache and the bundle, together and only together.
    const char *forced = getenv("MGF_SHADERS_CACHE_DIR"), *bundle = getenv("MGF_SHADERS_BUNDLE");
    if (forced && *forced && bundle && !strncmp(bundle, PREFIX, strlen(PREFIX)) && !strchr(bundle, '/')) snprintf(id, sizeof id, "%s", bundle);
    else if (!bundle_id(id, sizeof id)) return;
    else forced = NULL;
    if (forced && *forced) snprintf(root, sizeof root, "%s", forced);
    else if (confstr(_CS_DARWIN_USER_CACHE_DIR, root, sizeof root) == 0) return;
    snprintf(metal, sizeof metal, "%s/%s/com.apple.metal", root, id);
    DIR *d = opendir(metal);
    if (!d) return;
    api = np_plugin_api();
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        snprintf(dir, sizeof dir, "%s/%s", metal, e->d_name);
        keep(dir);
    }
    closedir(d);
}
