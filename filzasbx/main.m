#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdint.h>

typedef int64_t (*sandbox_extension_consume_fn)(const char *token);
typedef int32_t (*sandbox_extension_release_fn)(int64_t handle);

static int64_t g_consume_handle = 0;

int consume_token(const char *token) {
    if (!token || token[0] == '\0') return 0;
    if (g_consume_handle > 0) return 1;

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) return 0;

    sandbox_extension_consume_fn consume_fn =
        (sandbox_extension_consume_fn)dlsym(lib, "sandbox_extension_consume");

    if (!consume_fn) {
        dlclose(lib);
        return 0;
    }

    int64_t handle = consume_fn(token);
    dlclose(lib);

    if (handle <= 0) return 0;

    g_consume_handle = handle;
    return 1;
}


void release_token(void) {
    if (g_consume_handle <= 0) return;

    void *lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    if (!lib) return;

    sandbox_extension_release_fn release_fn = (sandbox_extension_release_fn)dlsym(lib, "sandbox_extension_release");

    if (release_fn) release_fn(g_consume_handle);

    g_consume_handle = 0;
    dlclose(lib);
}

static void show_alert(void);

static void show_alert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"filzasbx" message:@"Enter sandbox token" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Token"; }];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"Submit"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                NSString *token = alert.textFields.firstObject.text;

                if (token.length && consume_token(token.UTF8String)) {
                    [[NSUserDefaults standardUserDefaults]
                        setObject:token forKey:@"sbx_token"];
                } else {
                    show_alert();
                }
            }]
        ];

        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        UIViewController *vc = window.rootViewController;

        while (vc.presentedViewController) {
            vc = vc.presentedViewController;
        }

        if (vc) {
            [vc presentViewController:alert animated:YES completion:nil];
        } else {
            show_alert();
        }
    });
}

__attribute__((constructor))
static void initializer(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^checkToken)(void) = ^{
            NSString *saved =
                [[NSUserDefaults standardUserDefaults] stringForKey:@"sbx_token"];

            if (!saved || !consume_token(saved.UTF8String)) {
                show_alert();
            }
        };

        if (UIApplication.sharedApplication.applicationState ==
            UIApplicationStateActive) {
            checkToken();
        } else {
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                checkToken();
            }];
        }
    });
}

__attribute__((destructor))
static void deinitializer(void) {
    release_token();
}