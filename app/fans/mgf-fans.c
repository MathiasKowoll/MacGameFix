// mgf-fans: runs the Mac's fans at full speed while a game that asked for it is running.
//
// macOS raises the fans about a minute after a game starts to load its world. By then the chip
// is at 73-78 C and the kernel's power manager cuts the processor to 40% of its speed for
// minutes (engine/README.md). With the fans already turning the chip stays under that.
//
//   mgf-fans              the daemon (root): every 2 s, looks for a game of the console user
//                         that asked. While one runs both fans are forced to their maximum;
//                         when none is left they go back to automatic.
//   mgf-fans --version    the helper's version, a number that goes up when its code changes
//   mgf-fans --status     read only: fan mode, target, speed, and whether a game asks (no root)
//   mgf-fans --test       root: full speed for 20 s, then automatic again, printing the speeds
//   mgf-fans --auto       root: back to automatic now
//   mgf-fans --install    root: copies this program to /Library/PrivilegedHelperTools, writes its
//                         LaunchDaemon and starts it (again, when it was there already)
//   mgf-fans --remove     root: fans back to automatic, the daemon stopped, both files removed
//   mgf-fans --asked <log> <exe>      the NotProton rule against a log file, for the tests
//
// A game asks by NotProton starting it with MGF_FANS=max in its launch options, or with
// NOTPROTON_MGF_FANS=1, which is what NotProton's panel writes when its "Fans at full speed"
// row is switched on (a panel row's id has to start with NOTPROTON_). macOS gives nobody
// another process's environment, root included, so that is read from NotProton's log: the
// last "[launch] handed to /bin/sh -c:" line naming the exe of the running `run` script.
// The log is a file the user can write. All it can ask for is more cooling.
//
// It can only raise the fans. SMC keys: FNum, F<i>Md (0 automatic, 1 forced), F<i>Tg (target rpm),
// F<i>Mx (maximum), Ftst (the unlock some Apple Silicon needs before a forced mode is taken).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <fcntl.h>
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

// word appears in line as a word of its own: after a space or at the start, and followed by
// a space or the end.
static int has_word(const char *line, const char *word) {
  size_t n = strlen(word);
  for (const char *m = strstr(line, word); m; m = strstr(m + 1, word))
    if ((m == line || m[-1] == ' ') && (m[n] == ' ' || m[n] == 0)) return 1;
  return 0;
}

// The last launch line of NotProton's log that names exe: did it carry MGF_FANS=max, or the
// panel row's NOTPROTON_MGF_FANS=1?
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
      asked = has_word(line, "MGF_FANS=max") || has_word(line, "NOTPROTON_MGF_FANS=1");
    }
    line = nl ? nl + 1 : NULL;
  }
  return asked;
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
  char log[1024];
  snprintf(log, sizeof log, "%s/Library/Application Support/notproton/notproton.log", pw->pw_dir);
  int n = proc_listallpids(pids, sizeof pids), found = 0;
  for (int i = 0; i < n; i++) {
    struct proc_bsdshortinfo info;
    if (proc_pidinfo(pids[i], PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof info) != sizeof info) continue;
    if (info.pbsi_uid != user) continue;
    if (strcmp(info.pbsi_comm, "sh") && strcmp(info.pbsi_comm, "bash")) continue;
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

// What the app compares to tell an installed helper from the one it carries. Two builds of the
// same source are signed at different times and differ byte for byte, so the bytes cannot say;
// raise this when the helper's code changes.
#define VERSION 2
#define LABEL "io.github.macgamefix.fans"
static const char *PLIST =
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
  "<plist version=\"1.0\"><dict>\n"
  "  <key>Label</key><string>" LABEL "</string>\n"
  "  <key>ProgramArguments</key><array><string>%s</string></array>\n"
  "  <key>RunAtLoad</key><true/>\n"
  "  <key>KeepAlive</key><true/>\n"
  "  <key>StandardOutPath</key><string>/var/log/" LABEL ".log</string>\n"
  "  <key>StandardErrorPath</key><string>/var/log/" LABEL ".log</string>\n"
  "</dict></plist>\n";

static int launchctl(const char *verb, const char *what) {
  pid_t pid = fork();
  if (!pid) {
    int null = open("/dev/null", O_WRONLY);
    if (null >= 0) { dup2(null, 1); dup2(null, 2); }
    execl("/bin/launchctl", "launchctl", verb, "system", what, (char *)NULL);
    _exit(127);
  }
  int status = 0;
  return pid < 0 || waitpid(pid, &status, 0) < 0 ? -1 : WEXITSTATUS(status);
}

// MGF_FANS_PREFIX stands in for / in the tests, where nothing is started.
static int install(const char *self, int remove_it) {
  const char *prefix = getenv("MGF_FANS_PREFIX");
  char bin[1024], plist[1024], tmp[1100];
  snprintf(bin, sizeof bin, "%s/Library/PrivilegedHelperTools/" LABEL, prefix ? prefix : "");
  snprintf(plist, sizeof plist, "%s/Library/LaunchDaemons/" LABEL ".plist", prefix ? prefix : "");
  if (!prefix) launchctl("bootout", plist);
  if (remove_it) {
    if (!prefix) set_auto();
    unlink(bin); unlink(plist);
    return 0;
  }
  FILE *in = fopen(self, "rb");
  snprintf(tmp, sizeof tmp, "%s.new", bin);
  FILE *out = in ? fopen(tmp, "wb") : NULL;
  if (!out) { if (in) fclose(in); fprintf(stderr, "cannot write %s\n", tmp); return 1; }
  char block[65536]; size_t n; int bad = 0;
  while ((n = fread(block, 1, sizeof block, in)) > 0) if (fwrite(block, 1, n, out) != n) bad = 1;
  fclose(in); if (fclose(out)) bad = 1;
  if (bad || chmod(tmp, 0755) || (!prefix && chown(tmp, 0, 0)) || rename(tmp, bin)) { unlink(tmp); fprintf(stderr, "cannot install %s\n", bin); return 1; }
  FILE *f = fopen(plist, "w");
  if (!f) { fprintf(stderr, "cannot write %s\n", plist); return 1; }
  fprintf(f, PLIST, "/Library/PrivilegedHelperTools/" LABEL);
  if (fclose(f) || chmod(plist, 0644) || (!prefix && chown(plist, 0, 0))) return 1;
  if (!prefix && launchctl("bootstrap", plist)) { fprintf(stderr, "launchctl could not start it\n"); return 1; }
  return 0;
}

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  if (!strcmp(mode, "--version")) { printf("%d\n", VERSION); return 0; }
  if (!strcmp(mode, "--asked") && argc == 4) { puts(asked_in_log(argv[2], argv[3]) ? "yes" : "no"); return 0; }
  if (!strcmp(mode, "--install") || !strcmp(mode, "--remove")) {
    if (geteuid() && !getenv("MGF_FANS_PREFIX")) { fprintf(stderr, "this needs root\n"); return 1; }
    char self[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(getpid(), self, sizeof self) <= 0) return 1;
    if (!getenv("MGF_FANS_PREFIX")) {
      io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
      if (svc) IOServiceOpen(svc, mach_task_self(), 0, &smc);
    }
    return install(self, mode[2] == 'r');
  }
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
