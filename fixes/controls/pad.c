// pad.h's helpers: pad.log, Game Feel's settings, the game, the clock and the real-time thread.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pad.h"

// /tmp/macgamefix-<uid>, made if it is not there: the pads' sockets and pad.log. The checks
// (build-controls.sh) name a folder of their own in MGF_CONTROLS_DIR, so that a stand-in pad of
// theirs is no pad to a game being played at the time, and their lines stay out of its log.
void pad_dir(char *dir, size_t size) {
    const char *other = getenv("MGF_CONTROLS_DIR");
    if (other && *other == '/' && strlen(other) < size) snprintf(dir, size, "%s", other);
    else snprintf(dir, size, "/tmp/macgamefix-%u", (unsigned)getuid());
    mkdir(dir, 0700);
}

// The game this process runs for: the Steam app id Steam and NotProton give a game (SteamAppId,
// SteamGameId, STEAM_COMPAT_APP_ID), else the one in a Steam Play prefix's path,
// compatdata/<id>/pfx. winedevice.exe, where winebus runs, gets the game's own environment.
void pad_game(char *id, size_t size) {
    static const char *const names[] = {"SteamAppId", "SteamGameId", "STEAM_COMPAT_APP_ID"};
    const char *v;

    id[0] = 0;
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (!(v = getenv(names[i])) || !*v || strspn(v, "0123456789") != strlen(v) || !strcmp(v, "0")) continue;
        snprintf(id, size, "%s", v);
        return;
    }
    if ((v = getenv("WINEPREFIX")) && (v = strstr(v, "/compatdata/"))) {
        v += strlen("/compatdata/");
        size_t n = strspn(v, "0123456789");
        if (n && n < size && !strncmp(v + n, "/pfx", 4)) snprintf(id, size, "%.*s", (int)n, v);
    }
}

// A line of pad.log: a game's own stderr often reaches no log at all. Each line names the game,
// which MacGameFix reads back for what it learns of each one.
void pad_log(const char *format, ...) {
    char path[64], stamp[32], game[24];
    time_t now = time(NULL);
    struct tm tm;
    va_list args;
    FILE *f;

    pad_dir(path, sizeof(path));
    snprintf(path + strlen(path), sizeof(path) - strlen(path), "/pad.log");
    if (!(f = fopen(path, "a"))) return;
    localtime_r(&now, &tm);
    strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm);
    pad_game(game, sizeof(game));
    fprintf(f, "%s [%d] game=%s ", stamp, (int)getpid(), game[0] ? game : "-");
    va_start(args, format);
    vfprintf(f, format, args);
    va_end(args);
    fclose(f);
}

// Game Feel's settings files, the game's first: pass 0 is pad.d/<app id>.conf (none without a game
// id), pass 1 pad.conf, both in ~/Library/Application Support/MacGameFix. false when there is no
// such file to look for.
bool pad_conf(const char *game, int pass, char *path, size_t size) {
    const char *home = getenv("HOME");

    path[0] = 0;
    if (!home || (pass == 0 && !game[0])) return false;
    if (pass == 0) snprintf(path, size, "%s/Library/Application Support/MacGameFix/pad.d/%s.conf", home, game);
    else snprintf(path, size, "%s/Library/Application Support/MacGameFix/pad.conf", home);
    return true;
}

// Game Feel's settings: ~/Library/Application Support/MacGameFix/pad.d/<app id>.conf for this game,
// then pad.conf for every game; the first line with a key wins. A line is key=value. Read once, and
// again by pad_reload when Game Feel writes them while the game runs.
static char lines[32][96];
static int count = -1, game_count;
static pthread_once_t loaded = PTHREAD_ONCE_INIT;

// Both files into `into`, the game's own first; *own is how many lines are the game's.
static int read_lines(char into[32][96], int *own, bool *from_game, char game[24]) {
    char path[1024], line[128];
    int n = 0;

    *own = 0;
    *from_game = false;
    pad_game(game, 24);
    for (int pass = 0; pass < 2; pass++) {
        FILE *f;
        if (!pad_conf(game, pass, path, sizeof(path)) || !(f = fopen(path, "r"))) continue;
        if (pass == 0) *from_game = true;
        while (n < 32 && fgets(line, sizeof(line), f)) {
            size_t length = strcspn(line, "\r\n");
            line[length] = 0;
            if (length && line[0] != '#') snprintf(into[n++], sizeof(into[0]), "%s", line);
        }
        if (pass == 0) *own = n;
        fclose(f);
    }
    return n;
}

static void load(void) {
    char game[24];
    bool from_game;

    count = read_lines(lines, &game_count, &from_game, game);
    pad_log("settings: %s%s\n", game[0] ? "game " : "no game id, ", game[0] ? game : "every game's");
    if (from_game) pad_log("settings: pad.d/%s.conf read before pad.conf\n", game);
}

const char *pad_value(const char *key) {
    size_t length = strlen(key);

    pthread_once(&loaded, load);
    for (int i = 0; i < count; i++)
        if (!strncmp(lines[i], key, length) && lines[i][length] == '=') return lines[i] + length + 1;
    return "";
}

// Game Feel's settings as they are now: read again into a copy, then put in place, so a reader on
// another thread sees the old lines or the new ones.
void pad_reload(void) {
    static char fresh[32][96];
    char game[24];
    bool from_game;
    int own, n;

    pthread_once(&loaded, load);
    n = read_lines(fresh, &own, &from_game, game);
    count = n < count ? n : count;
    memcpy(lines, fresh, sizeof(lines));
    game_count = own;
    count = n;
}

// The two files' modification times together, to tell when Game Feel wrote them.
long long pad_settings_stamp(void) {
    char path[1024], game[24];
    long long stamp = 0;
    struct stat st;

    pad_game(game, sizeof(game));
    for (int pass = 0; pass < 2; pass++)
        if (pad_conf(game, pass, path, sizeof(path)) && !stat(path, &st))
            stamp += (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
    return stamp;
}

// Whether the game's own settings, pad.d/<app id>.conf, say "key=value"; pad.conf does not count.
bool pad_game_option(const char *option) {
    pthread_once(&loaded, load);
    for (int i = 0; i < game_count; i++)
        if (!strcmp(lines[i], option)) return true;
    return false;
}

// Whether a setting is "key=value".
bool pad_option(const char *option) {
    const char *eq = strchr(option, '=');
    char key[32];

    if (!eq || eq - option >= (int)sizeof(key)) return false;
    snprintf(key, sizeof(key), "%.*s", (int)(eq - option), option);
    return !strcmp(pad_value(key), eq + 1);
}

// A number as MacGameFix writes it, "2.50", read digit by digit: strtof follows the locale and
// stops at a point where a decimal comma is expected. A comma is taken too. NAN without a digit.
float pad_number(const char *s) {
    double v = 0, scale = 1;
    int digits = 0;

    for (; *s >= '0' && *s <= '9'; s++, digits++) v = v * 10 + (*s - '0');
    if (*s == '.' || *s == ',')
        for (s++; *s >= '0' && *s <= '9'; s++, digits++) v += (*s - '0') * (scale /= 10);
    return digits ? (float)v : NAN;
}

static mach_timebase_info_data_t timebase;

// mach_absolute_time's ticks in a span of seconds, and the other way round.
uint64_t pad_ticks(double seconds) {
    if (!timebase.denom) mach_timebase_info(&timebase);
    return (uint64_t)(seconds * 1e9 * timebase.denom / timebase.numer);
}

double pad_seconds(uint64_t ticks) {
    if (!timebase.denom) mach_timebase_info(&timebase);
    return (double)ticks * timebase.numer / timebase.denom / 1e9;
}

// The calling thread gets an audio deadline: a plain sleep is coalesced by up to 100 ms while
// another app holds Game Mode.
void pad_realtime(double period, double constraint) {
    thread_time_constraint_policy_data_t policy = {
        .period = (uint32_t)pad_ticks(period),
        .computation = (uint32_t)pad_ticks(0.001),
        .constraint = (uint32_t)pad_ticks(constraint),
        .preemptible = TRUE,
    };
    thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY,
                      (thread_policy_t)&policy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);
}
