#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define slotsize 2048
#define tokenmarker "FILZASBX_TOKEN"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

__attribute__((used)) char gfilzasbxtokenslot[slotsize] = tokenmarker;

static int64_t gconsumehandle = 0;

static void append_line_to_path(NSString *path, NSString *line) {
    if (!path || !line) {
        return;
    }

    const char *cpath = [path fileSystemRepresentation];
    const char *cline = [line UTF8String];
    if (!cpath || !cline) {
        return;
    }

    int fd = open(cpath, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) {
        return;
    }

    (void)write(fd, cline, strlen(cline));
    (void)close(fd);
}

static NSArray<NSString *> *candidate_log_paths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];

    NSString *home = NSHomeDirectory();
    if (home.length > 0) {
        [paths addObject:[home stringByAppendingPathComponent:@"Documents/sbx.log"]];
        [paths addObject:[home stringByAppendingPathComponent:@"tmp/sbx.log"]];
    }

    NSArray<NSURL *> *docs = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                     inDomains:NSUserDomainMask];
    if (docs.count > 0) {
        NSString *docPath = [[docs[0] URLByAppendingPathComponent:@"sbx.log"] path];
        if (docPath.length > 0 && ![paths containsObject:docPath]) {
            [paths addObject:docPath];
        }
    }

    [paths addObject:@"/tmp/sbx.log"];
    return paths;
}

static NSString *timestamp_line(NSString *message) {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [NSString stringWithFormat:@"[%@] %@\n", [fmt stringFromDate:[NSDate date]], message ?: @"(null)"];
}

static void log_event(NSString *message) {
    NSString *line = timestamp_line(message);
    for (NSString *path in candidate_log_paths()) {
        append_line_to_path(path, line);
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
    NSString *home = NSHomeDirectory() ?: @"(nil)";
    log_event([NSString stringWithFormat:@"initializer started; HOME=%@", home]);

    NSMutableString *pathDump = [NSMutableString stringWithString:@"log candidates:"];
    for (NSString *path in candidate_log_paths()) {
        [pathDump appendFormat:@" %@;", path];
    }
    log_event(pathDump);

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
