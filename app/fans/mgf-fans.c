// mgf-fans: runs the Mac's fans at full speed while a game that asked for it is running.
//
// macOS raises the fans about a minute after a game starts to load its world. By then the chip
// is at 73-78 C and the kernel's power manager cuts the processor to 40% of its speed for
// minutes (engine/README.md). With the fans already turning the chip stays under that.
//
//   mgf-fans              the daemon (root): every 2 s, looks for a game of the console user
//                         that asked. While one runs both fans are forced to their maximum;
//                         when none is left they go back to automatic.
//   mgf-fans --status     read only: fan mode, target, speed, and whether a game asks (no root)
//   mgf-fans --test       root: full speed for 20 s, then automatic again, printing the speeds
//   mgf-fans --auto       root: back to automatic now
//   mgf-fans --asked <log> <exe>      the NotProton rule against a log file, for the tests
//   mgf-fans --listed <list> <path>   the list rule against a list file and a path, for the tests
//
// A game asks in one of two ways:
//   - its folder is a line of ~/Library/Application Support/MacGameFix/fans.list, which the app
//     writes: a process whose executable is inside that folder, or a Wine process whose exe is;
//   - NotProton started it with MGF_FANS=max in its launch options. macOS gives nobody another
//     process's environment, root included, so that is read from NotProton's log: the last
//     "[launch] handed to /bin/sh -c:" line naming the exe of the running `run` script.
// Both are files the user can write. All they can ask for is more cooling.
//
// It can only raise the fans. SMC keys: FNum, F<i>Md (0 automatic, 1 forced), F<i>Tg (target rpm),
// F<i>Mx (maximum), Ftst (the unlock some Apple Silicon needs before a forced mode is taken).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#include <IOKit/IOKitLib.h>
#include <ctype.h>
#include <libproc.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

typedef struct { uint32_t key; struct { char major, minor, build, reserved[1]; uint16_t release; } vers;
  struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } plimit;
  struct { uint32_t dataSize, dataType; char dataAttributes; } keyInfo;
  char result, status, data8; uint32_t data32; char bytes[32]; } SMCParam;

static io_connect_t smc;
static volatile sig_atomic_t quit;
static const char *MARK = "/var/run/io.github.macgamefix.fans.forced";

static uint32_t k4(const char *s) { return ((uint32_t)s[0] << 24) | (s[1] << 16) | (s[2] << 8) | s[3]; }
static int call(SMCParam *in, SMCParam *out) {
  size_t o = sizeof *out;
  memset(out, 0, sizeof *out);
  return IOConnectCallStructMethod(smc, 2, in, sizeof *in, out, &o) || out->result;
}
static int smc_read(const char *key, unsigned char *buf, uint32_t *size) {
  SMCParam in = {0}, out;
  in.key = k4(key); in.data8 = 9;
  if (call(&in, &out)) return -1;
  *size = out.keyInfo.dataSize;
  memset(&in, 0, sizeof in); in.key = k4(key); in.keyInfo.dataSize = *size; in.data8 = 5;
  if (call(&in, &out)) return -1;
  memcpy(buf, out.bytes, *size > 32 ? 32 : *size);
  return 0;
}
static int smc_write(const char *key, const void *data, uint32_t size) {
  SMCParam in = {0}, out;
  in.key = k4(key); in.data8 = 9;
  if (call(&in, &out) || out.keyInfo.dataSize != size) return -1;
  memset(&in, 0, sizeof in); in.key = k4(key); in.keyInfo.dataSize = size; in.data8 = 6;
  memcpy(in.bytes, data, size);
  return call(&in, &out) ? -1 : 0;
}
static double fltkey(const char *key) {
  unsigned char b[32]; uint32_t n; float f;
  if (smc_read(key, b, &n) || n != 4) return -1;
  memcpy(&f, b, 4); return f;
}
static int bytekey(const char *key) {
  unsigned char b[32]; uint32_t n;
  return smc_read(key, b, &n) || n != 1 ? -1 : b[0];
}
static void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void say(const char *fmt, ...) {
  va_list ap; time_t t = time(NULL); struct tm tm; char ts[32];
  localtime_r(&t, &tm); strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &tm);
  printf("%s ", ts); va_start(ap, fmt); vprintf(fmt, ap); va_end(ap); printf("\n"); fflush(stdout);
}

static int fans(void) { int n = bytekey("FNum"); return n < 1 ? 0 : n > 8 ? 8 : n; }

static void show(void) {
  for (int i = 0; i < fans(); i++) {
    char md[8], tg[8], ac[8], mx[8];
    snprintf(md, 8, "F%dMd", i); snprintf(tg, 8, "F%dTg", i); snprintf(ac, 8, "F%dAc", i); snprintf(mx, 8, "F%dMx", i);
    say("fan %d: mode %d, target %.0f, speed %.0f, max %.0f", i, bytekey(md), fltkey(tg), fltkey(ac), fltkey(mx));
  }
}

static int set_max(void) {
  unsigned char one = 1; int n = fans(), ok = 1;
  for (int i = 0; i < n; i++) {
    char md[8]; snprintf(md, 8, "F%dMd", i);
    if (smc_write(md, &one, 1)) {
      // Apple Silicon: the forced mode is refused until Ftst says the fans are under test.
      if (bytekey("Ftst") >= 0) smc_write("Ftst", &one, 1);
      int tries = 0;
      while (smc_write(md, &one, 1) && ++tries < 100) usleep(100000);
      if (tries >= 100) { say("fan %d: the forced mode was refused", i); ok = 0; continue; }
    }
    char tg[8], mx[8]; snprintf(tg, 8, "F%dTg", i); snprintf(mx, 8, "F%dMx", i);
    float top = (float)fltkey(mx);
    if (top < 1000 || smc_write(tg, &top, 4)) { say("fan %d: the target was refused", i); ok = 0; }
  }
  if (ok) { FILE *f = fopen(MARK, "w"); if (f) fclose(f); }
  return ok;
}

static void set_auto(void) {
  unsigned char zero = 0;
  for (int i = 0; i < fans(); i++) {
    char md[8]; snprintf(md, 8, "F%dMd", i);
    if (smc_write(md, &zero, 1)) say("fan %d: could not go back to automatic", i);
  }
  if (bytekey("Ftst") > 0) smc_write("Ftst", &zero, 1);
  unlink(MARK);
}

// The last launch line of NotProton's log that names exe: did it carry MGF_FANS=max?
static int asked_in_log(const char *path, const char *exe) {
  static char tail[400000];
  FILE *f = fopen(path, "r");
  if (!f) return 0;
  fseek(f, 0, SEEK_END); long size = ftell(f), from = size > (long)sizeof tail - 1 ? size - ((long)sizeof tail - 1) : 0;
  fseek(f, from, SEEK_SET);
  size_t n = fread(tail, 1, sizeof tail - 1, f); fclose(f); tail[n] = 0;
  int asked = 0;
  for (char *line = tail; line && *line; ) {
    char *nl = strchr(line, '\n'); if (nl) *nl = 0;
    if (strstr(line, "handed to /bin/sh -c:") && strstr(line, "waitforexitandrun") && strstr(line, exe)) {
      char *m = strstr(line, "MGF_FANS=max");
      asked = m && (m[12] == ' ' || m[12] == 0) && (m == line || m[-1] == ' ');
    }
    line = nl ? nl + 1 : NULL;
  }
  return asked;
}

// Is path inside a folder of the list? A Mac path is compared as it is; a Windows one (a Wine
// process's argv[0], "S:\\steamapps\\common\\Game\\bin\\game.exe") by the folder's own name.
static int listed(const char *list, const char *path) {
  FILE *f = fopen(list, "r");
  if (!f) return 0;
  char line[2048], norm[2048]; int hit = 0;
  size_t n = 0;
  for (; path[n] && n < sizeof norm - 1; n++) norm[n] = path[n] == '\\' ? '/' : (char)tolower((unsigned char)path[n]);
  norm[n] = 0;
  int windows = strchr(path, '\\') != NULL || (path[0] && path[1] == ':');
  while (!hit && fgets(line, sizeof line, f)) {
    size_t len = strcspn(line, "\r\n");
    while (len > 1 && line[len - 1] == '/') len--;
    line[len] = 0;
    if (line[0] != '/' || len < 2) continue;
    if (!windows) { hit = !strncmp(path, line, len) && path[len] == '/'; continue; }
    const char *base = strrchr(line, '/') + 1;
    char want[1024]; size_t w = 0;
    want[w++] = '/';
    for (const char *c = base; *c && w < sizeof want - 2; c++) want[w++] = (char)tolower((unsigned char)*c);
    want[w++] = '/'; want[w] = 0;
    hit = w > 2 && strstr(norm, want) != NULL;
  }
  fclose(f);
  return hit;
}

static int argv0(pid_t pid, char *out, size_t size, char *buf, size_t bufsize, int *argc_out, char **args_out, char **end_out) {
  int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid }; size_t len = bufsize;
  if (sysctl(mib, 3, buf, &len, NULL, 0) || len < sizeof(int)) return -1;
  int argc; memcpy(&argc, buf, sizeof argc);
  char *p = buf + sizeof(int), *end = buf + len;
  while (p < end && *p) p++;            // the executable's path
  while (p < end && !*p) p++;
  if (p >= end) return -1;
  if (out) snprintf(out, size, "%s", p);
  if (argc_out) *argc_out = argc;
  if (args_out) *args_out = p;
  if (end_out) *end_out = end;
  return 0;
}

static int wanted(void) {
  struct stat st; uid_t user = stat("/dev/console", &st) ? (uid_t)-1 : st.st_uid;
  static pid_t pids[8192]; static char buf[262144];
  static pid_t known; static int known_asked;
  struct passwd *pw = user == (uid_t)-1 ? NULL : getpwuid(user);
  if (!pw) return 0;
  char list[1024], log[1024];
  snprintf(list, sizeof list, "%s/Library/Application Support/MacGameFix/fans.list", pw->pw_dir);
  snprintf(log, sizeof log, "%s/Library/Application Support/notproton/notproton.log", pw->pw_dir);
  int have_list = stat(list, &st) == 0 && st.st_size > 1;
  int n = proc_listallpids(pids, sizeof pids), found = 0;
  for (int i = 0; i < n; i++) {
    struct proc_bsdshortinfo info;
    if (proc_pidinfo(pids[i], PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof info) != sizeof info) continue;
    if (info.pbsi_uid != user) continue;
    int shell = !strcmp(info.pbsi_comm, "sh") || !strcmp(info.pbsi_comm, "bash");
    if (have_list) {
      char path[PROC_PIDPATHINFO_MAXSIZE], first[2048];
      if (proc_pidpath(pids[i], path, sizeof path) > 0 && listed(list, path)) return 1;
      // A Wine process: its argv[0] is the Windows path of the exe it runs.
      if (!shell && strstr(info.pbsi_comm, ".ex") && !argv0(pids[i], first, sizeof first, buf, sizeof buf, NULL, NULL, NULL)
          && listed(list, first)) return 1;
    }
    if (!shell) continue;
    int argc; char *p, *end;
    if (argv0(pids[i], NULL, 0, buf, sizeof buf, &argc, &p, &end)) continue;
    const char *exe = NULL; int tool = 0, run = 0;
    for (int a = 0; a < argc && p < end; a++) {
      if (strstr(p, "/compatibilitytools.d/")) tool = 1;
      if (run && !exe) exe = p;
      if (!strcmp(p, "waitforexitandrun")) run = 1;
      while (p < end && *p) p++;
      p++;
    }
    if (!tool || !exe) continue;
    found = 1;
    if (pids[i] != known) { known = pids[i]; known_asked = asked_in_log(log, exe); }
    if (known_asked) return 1;
  }
  if (!found) known = 0;
  return 0;
}

static void stop(int sig) { (void)sig; quit = 1; }

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  if (!strcmp(mode, "--asked") && argc == 4) { puts(asked_in_log(argv[2], argv[3]) ? "yes" : "no"); return 0; }
  if (!strcmp(mode, "--listed") && argc == 4) { puts(listed(argv[2], argv[3]) ? "yes" : "no"); return 0; }
  io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (!s || IOServiceOpen(s, mach_task_self(), 0, &smc)) { fprintf(stderr, "no SMC\n"); return 1; }
  if (!strcmp(mode, "--status")) { show(); say("a game asks for full speed: %s", wanted() ? "yes" : "no"); return 0; }
  if (geteuid()) { fprintf(stderr, "this needs root (sudo)\n"); return 1; }
  if (!strcmp(mode, "--auto")) { set_auto(); show(); return 0; }
  if (!strcmp(mode, "--test")) {
    show(); say("full speed for 20 s: %s", set_max() ? "accepted" : "REFUSED");
    for (int i = 0; i < 4; i++) { sleep(5); show(); }
    set_auto(); say("back to automatic"); sleep(5); show(); return 0;
  }
  signal(SIGTERM, stop); signal(SIGINT, stop);
  int forced = access(MARK, F_OK) == 0, checks = 0;
  say("started; fans %d, forced before: %d", fans(), forced);
  while (!quit) {
    int want = wanted();
    if (want && !forced) { forced = set_max(); say("a game asks: full speed %s", forced ? "on" : "REFUSED"); if (!forced) sleep(30); }
    else if (!want && forced) { set_auto(); forced = 0; say("no game asks: automatic"); }
    else if (forced && ++checks % 5 == 0 && bytekey("F0Md") != 1) { say("the forced mode was taken back; setting it again"); set_max(); }
    sleep(2);
  }
  if (forced) set_auto();
  say("stopped");
  return 0;
}
