#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define slotsize 2048
#define tokenmarker "FILZASBX_TOKEN"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

__attribute__((used)) char gfilzasbxtokenslot[slotsize] = tokenmarker;

static int64_t gconsumehandle = 0;

static void append(const char *path, const char *line) {
    if (!path || !line) {
        return;
    }

    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) {
        return;
    }

    (void)write(fd, line, strlen(line));
    (void)close(fd);
}

static void log(const char *fmt, ...) {
    char msg[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    char ts[64] = {0};
    time_t now = time(NULL);
    struct tm local_tm = {0};
    if (localtime_r(&now, &local_tm)) {
        strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &local_tm);
    } else {
        snprintf(ts, sizeof(ts), "time-unknown");
    }

    char line[2300];
    snprintf(line, sizeof(line), "[%s] %s\n", ts, msg);

    const char *home = getenv("HOME");
    if (home && home[0] != '\0') {
        char p1[PATH_MAX];
        char p2[PATH_MAX];
        snprintf(p1, sizeof(p1), "%s/Documents/sbx.log", home);
        snprintf(p2, sizeof(p2), "%s/tmp/sbx.log", home);
        append(p1, line);
        append(p2, line);
    }

    append("/tmp/sbx.log", line);
}

static int tokenslotpatched(void) {
    if (gfilzasbxtokenslot[0] == '\0') {
        return 0;
    }
    return strcmp(gfilzasbxtokenslot, tokenmarker) != 0;
}

static void sanitizetokenslot(void) {
    size_t n = strnlen(gfilzasbxtokenslot, slotsize);
    if (n == 0 || n >= slotsize) {
        return;
    }

    while (n > 0 && (gfilzasbxtokenslot[n - 1] == '\n' || gfilzasbxtokenslot[n - 1] == '\r')) {
        gfilzasbxtokenslot[n - 1] = '\0';
        n--;
    }
}

static void consume(void) {
    if (gconsumehandle > 0) {
        log("token already consumed (handle=%lld)", (long long)gconsumehandle);
        return;
    }

    if (!tokenslotpatched()) {
        log("token slot not patched");
        return;
    }

    sanitizetokenslot();

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        log("failed to open libsystem_sandbox");
        return;
    }

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");
    if (!consume_fn) {
        log("sandbox_extension_consume not found");
        dlclose(lib);
        return;
    }

    int64_t handle = consume_fn(gfilzasbxtokenslot);
    if (handle <= 0) {
        log("sandbox token invalid");
        dlclose(lib);
        return;
    }

    gconsumehandle = handle;
    log("sandbox token consumed (handle=%lld)", (long long)gconsumehandle);
    dlclose(lib);
}

__attribute__((constructor))
static void initializer(void) {
    const char *home = getenv("HOME");
    log("initializer started; HOME=%s", home ? home : "(null)");
    consume();
}

__attribute__((destructor))
static void deinitializer(void) {
    if (gconsumehandle <= 0) {
        log("deinitializer: no consume handle to release");
        return;
    }

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        log("deinitializer: failed to open libsystem_sandbox");
        return;
    }

    sandbox_extension_release_fn release_fn =
        (sandbox_extension_release_fn)dlsym(lib, "sandbox_extension_release");
    if (release_fn) {
        (void)release_fn(gconsumehandle);
        log("released consume handle=%lld", (long long)gconsumehandle);
    } else {
        log("deinitializer: sandbox_extension_release not found");
    }

    gconsumehandle = 0;
    dlclose(lib);
}
