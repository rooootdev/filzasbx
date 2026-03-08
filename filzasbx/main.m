#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

#define slotsize 2048
#define tokenmarker "FILZASBX_TOKEN"

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

__attribute__((used)) char gfilzasbxtokenslot[slotsize] = tokenmarker;

static int64_t gconsumehandle = 0;

static void showalert(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        if (!app) {
            return;
        }

        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in app.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) {
                    continue;
                }
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState != UISceneActivationStateForegroundActive) {
                    continue;
                }
                for (UIWindow *candidate in windowScene.windows) {
                    if (candidate.isKeyWindow) {
                        window = candidate;
                        break;
                    }
                }
                if (!window) {
                    window = windowScene.windows.firstObject;
                }
                if (window) {
                    break;
                }
            }
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!window) {
            window = app.keyWindow ?: app.windows.firstObject;
        }
#pragma clang diagnostic pop

        UIViewController *controller = window.rootViewController;
        if (!controller) {
            return;
        }

        while (controller.presentedViewController) {
            controller = controller.presentedViewController;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"filzasbx"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
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
        showalert([NSString stringWithFormat:@"token already consumed (handle=%lld)",
                                           (long long)gconsumehandle]);
        return;
    }

    if (!tokenslotpatched()) {
        showalert(@"token slot not patched");
        return;
    }

    sanitizetokenslot();

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) {
        showalert(@"failed to open libsystem_sandbox");
        return;
    }

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");
    if (!consume_fn) {
        showalert(@"sandbox_extension_consume not found");
        dlclose(lib);
        return;
    }

    int64_t handle = consume_fn(gfilzasbxtokenslot);
    if (handle <= 0) {
        showalert(@"sandbox token invalid");
        dlclose(lib);
        return;
    }

    gconsumehandle = handle;
    showalert([NSString stringWithFormat:@"sandbox token consumed (handle=%lld)",
                                       (long long)gconsumehandle]);
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
