#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FILZA2K_TOKEN_SLOT_SIZE 2048
#define FILZA2K_TOKEN_MARKER "SL2K_TOKEN_SLOT_V1"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

// This slot is patched by symlin2k before injection.
// Keep it writable and with a fixed size so the offset remains stable.
__attribute__((used)) char gFilza2KTokenSlot[FILZA2K_TOKEN_SLOT_SIZE] = FILZA2K_TOKEN_MARKER;

static int64_t gConsumeHandle = 0;

static int token_slot_is_patched(void) {
    if (gFilza2KTokenSlot[0] == '\0') {
        return 0;
    }
    return strcmp(gFilza2KTokenSlot, FILZA2K_TOKEN_MARKER) != 0;
}

static void filza2k_consume_token_if_valid(void) {
    if (!token_slot_is_patched()) {
        fprintf(stderr, "[filza2k] token slot not patched\n");
        return;
    }

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        fprintf(stderr, "[filza2k] failed to open libsystem_sandbox\n");
        return;
    }

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");
    if (!consume_fn) {
        fprintf(stderr, "[filza2k] sandbox_extension_consume not found\n");
        dlclose(lib);
        return;
    }

    int64_t handle = consume_fn(gFilza2KTokenSlot);
    if (handle <= 0) {
        fprintf(stderr, "[filza2k] sandbox token invalid\n");
        dlclose(lib);
        return;
    }

    gConsumeHandle = handle;
    fprintf(stderr, "[filza2k] sandbox token valid and consumed\n");
    dlclose(lib);
}

__attribute__((constructor))
static void filza2k_initializer(void) {
    // Run on every load to verify and consume the patched token.
    filza2k_consume_token_if_valid();
}

__attribute__((destructor))
static void filza2k_deinitializer(void) {
    if (gConsumeHandle <= 0) {
        return;
    }

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        return;
    }

    sandbox_extension_release_fn release_fn =
        (sandbox_extension_release_fn)dlsym(lib, "sandbox_extension_release");
    if (release_fn) {
        (void)release_fn(gConsumeHandle);
    }

    gConsumeHandle = 0;
    dlclose(lib);
}
