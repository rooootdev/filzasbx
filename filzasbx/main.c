#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define slotsize 2048
#define tokenmarker "FILZASBX_TOKEN"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

__attribute__((used)) char gfilzasbxtokenslot[slotsize] = tokenmarker;

static int64_t gconsumehandle = 0;

static int tokenslotpatched(void) {
    if (gfilzasbxtokenslot[0] == '\0') {
        return 0;
    }
    return strcmp(gfilzasbxtokenslot, FILZASBX_TOKEN_MARKER) != 0;
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
        fprintf(stderr, "[filzasbx] token already consumed (handle=%lld)\n", (long long)gconsumehandle);
        return;
    }

    if (!tokenslotpatched()) {
        fprintf(stderr, "[filzasbx] token slot not patched\n");
        return;
    }

    sanitizetokenslot();

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        fprintf(stderr, "[filzasbx] failed to open libsystem_sandbox\n");
        return;
    }

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");
    if (!consume_fn) {
        fprintf(stderr, "[filzasbx] sandbox_extension_consume not found\n");
        dlclose(lib);
        return;
    }

    int64_t handle = consume_fn(gfilzasbxtokenslot);
    if (handle <= 0) {
        fprintf(stderr, "[filzasbx] sandbox token invalid\n");
        dlclose(lib);
        return;
    }

    gconsumehandle = handle;
    fprintf(stderr, "[filzasbx] sandbox token consumed (handle=%lld)\n", (long long)gconsumehandle);
    dlclose(lib);
}

__attribute__((constructor))
static void initializer(void) {
    consume();
}

__attribute__((destructor))
static void deinitializer(void) {
    if (gconsumehandle <= 0) {
        return;
    }

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        return;
    }

    sandbox_extension_release_fn release_fn =
        (sandbox_extension_release_fn)dlsym(lib, "sandbox_extension_release");
    if (release_fn) {
        (void)release_fn(gconsumehandle);
    }

    gconsumehandle = 0;
    dlclose(lib);
}
