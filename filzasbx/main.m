#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

#define slotsize 2048
#define tokenmarker "FILZASBX_TOKEN"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

__attribute__((used)) char gfilzasbxtokenslot[slotsize] = tokenmarker;

static int64_t gconsumehandle = 0;

static NSURL *log_file_url(void) {
    NSArray<NSURL *> *docs = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                     inDomains:NSUserDomainMask];
    if (docs.count == 0) {
        return [NSURL fileURLWithPath:@"/tmp/sbx.log"];
    }
    return [docs[0] URLByAppendingPathComponent:@"sbx.log"];
}

static void log_event(NSString *message) {
    if (!message) {
        return;
    }

    NSURL *logURL = log_file_url();
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [fmt stringFromDate:[NSDate date]], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logURL.path]) {
        [data writeToURL:logURL atomically:YES];
        return;
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:logURL error:nil];
    if (!fh) {
        [data writeToURL:logURL atomically:YES];
        return;
    }

    @try {
        [fh seekToEndOfFile];
        [fh writeData:data];
    } @catch (__unused NSException *e) {
        [data writeToURL:logURL atomically:YES];
    } @finally {
        [fh closeFile];
    }
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
        log_event([NSString stringWithFormat:@"token already consumed (handle=%lld)",
                   (long long)gconsumehandle]);
        return;
    }

    if (!tokenslotpatched()) {
        log_event(@"token slot not patched");
        return;
    }

    sanitizetokenslot();

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        log_event(@"failed to open libsystem_sandbox");
        return;
    }

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");
    if (!consume_fn) {
        log_event(@"sandbox_extension_consume not found");
        dlclose(lib);
        return;
    }

    int64_t handle = consume_fn(gfilzasbxtokenslot);
    if (handle <= 0) {
        log_event(@"sandbox token invalid");
        dlclose(lib);
        return;
    }

    gconsumehandle = handle;
    log_event([NSString stringWithFormat:@"sandbox token consumed (handle=%lld)",
               (long long)gconsumehandle]);
    dlclose(lib);
}

__attribute__((constructor))
static void initializer(void) {
    log_event(@"initializer started");
    consume();
}

__attribute__((destructor))
static void deinitializer(void) {
    if (gconsumehandle <= 0) {
        log_event(@"deinitializer: no consume handle to release");
        return;
    }

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        log_event(@"deinitializer: failed to open libsystem_sandbox");
        return;
    }

    sandbox_extension_release_fn release_fn =
        (sandbox_extension_release_fn)dlsym(lib, "sandbox_extension_release");
    if (release_fn) {
        (void)release_fn(gconsumehandle);
        log_event([NSString stringWithFormat:@"released consume handle=%lld", (long long)gconsumehandle]);
    } else {
        log_event(@"deinitializer: sandbox_extension_release not found");
    }

    gconsumehandle = 0;
    dlclose(lib);
}
