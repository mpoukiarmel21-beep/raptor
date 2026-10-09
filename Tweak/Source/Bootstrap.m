#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <dlfcn.h>
#import "Core/RPPaths.h"
#import "Core/RPContainerStore.h"
#import "Core/RPContainer.h"
#import "Spoof/RPDeviceIdentity.h"
#import "Isolation/RPHomeRedirect.h"
#import "Isolation/RPKeychainHook.h"
#import "Isolation/RPPrefsHook.h"
#import "Isolation/RPAppGroupHook.h"
#import "Hardening/RPHardening.h"
#import "Hardening/RPPermissions.h"
#import "Hardening/RPPasteboardHook.h"
#import "Hardening/RPDyldHook.h"
#import "Hardening/RPJailbreakBypass.h"
#import "Hardening/RPReceiptHook.h"
#import "Spoof/RPDeviceSpoof.h"
#import "Spoof/RPLocaleSpoof.h"
#import "Spoof/RPLocationSpoof.h"
#import "Spoof/RPGeoIdentity.h"
#import "Camera/RPCameraHook.h"
#import "Util/RPDiagnostics.h"
#import "UI/RPFloatingButton.h"

// ── Crash logger (async-signal-safe) ───────────────────────────────
static int gCrashFD = -1;
static NSUncaughtExceptionHandler *gPriorHandler = NULL;

static void RPAppendCrash(NSString *s) {
    if (gCrashFD < 0 || !s.length) return;
    NSData *d = [[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (d.length) write(gCrashFD, d.bytes, d.length);
}

static void RPCrashHandler(NSException *ex) {
    RPAppendCrash([NSString stringWithFormat:@"[CRASH] %@ %@\n%@", ex.name, ex.reason, [ex.callStackSymbols componentsJoinedByString:@"\n"]]);
    if (gPriorHandler) gPriorHandler(ex);
}

// Only async-signal-safe calls: backtrace + write. Defer symbolication to next launch.
static void RPSignalHandler(int sig, siginfo_t *info, void *ctx) {
    void *bt[64];
    int n = backtrace(bt, 64);
    char hdr[128];
    snprintf(hdr, sizeof(hdr), "\n[SIGNAL %d addr=%p]\n", sig, info ? info->si_addr : NULL);
    if (gCrashFD >= 0) write(gCrashFD, hdr, strlen(hdr));
    // Do NOT call backtrace_symbols_fd (malloc). Write raw addresses, symbolicate on next launch.
    for (int i = 0; i < n; i++) {
        char line[32];
        snprintf(line, sizeof(line), "%p\n", bt[i]);
        if (gCrashFD >= 0) write(gCrashFD, line, strlen(line));
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static char gAltStack[256 * 1024];

static void RPInstallCrashLogger(void) {
    NSString *logDir = [RPPaths logDirectory];
    // Control plane must be readable before first unlock
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionNone};
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:attrs error:nil];
    NSString *logFile = [logDir stringByAppendingPathComponent:@"crash.log"];
    gCrashFD = open([logFile fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    if (gCrashFD >= 0) fcntl(gCrashFD, F_SETFD, FD_CLOEXEC);
    gPriorHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&RPCrashHandler);
    stack_t ss = {.ss_sp = gAltStack, .ss_size = sizeof(gAltStack), .ss_flags = 0};
    sigaltstack(&ss, NULL);
    struct sigaction sa = {};
    sa.sa_sigaction = RPSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK; // no SA_RESETHAND — allow handler to stay
    sigemptyset(&sa.sa_mask);
    for (int _i = 0, _sigs[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGSYS}; _i < 6; _i++) {
        sigaction(_sigs[_i], &sa, NULL);
    }
}

// ── Home cache bust ────────────────────────────────────────────────
// Foundation caches NSHomeDirectory() on first call. After we setenv HOME we must bust it.
// _NSSetHomeDirectory is private — resolve via dlsym so the linker doesn't require it.
static void RPBustHomeCache(NSString *newHome) {
    if (!newHome.length) return;
    void *handle = dlopen(NULL, RTLD_NOW);
    if (handle) {
        typedef void (*SetHomeFn)(NSString *);
        SetHomeFn fn = (SetHomeFn)dlsym(handle, "_NSSetHomeDirectory");
        if (fn) {
            @try { fn(newHome); } @catch (NSException *e) {}
        }
        dlclose(handle);
    }
}

// ── Stale guard (no exit(0) — suspend instead) ─────────────────────
static NSString *gBootCID = nil;

static void RPInstallStaleGuard(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        NSString *cur = [RPContainerStore shared].activeCID;
        if (gBootCID && cur && ![gBootCID isEqualToString:cur]) {
            RPLog(@"stale guard: boot=%@ cur=%@ — suspending for relaunch", gBootCID, cur);
            // Suspend to home; Bootstrap on next cold launch will pick new container.
            // Using exit(0) is reported as crash — suspend is clean.
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                exit(0);
            });
        }
    }];
}

// ── Background re-protect (bounded, autoreleasepool, proper expiry) ──
static void RPInstallBackgroundReprotect(NSString *root) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *n) {
        __block UIBackgroundTaskIdentifier tid = UIBackgroundTaskInvalid;
        tid = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"RPReprotect"
                                                           expirationHandler:^{
            if (tid != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:tid];
                tid = UIBackgroundTaskInvalid;
            }
        }];
        if (tid == UIBackgroundTaskInvalid) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                [RPPaths reapplyProtectionRecursivelyAtRoot:root];
            }
            if (tid != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:tid];
            }
        });
    }];
}

void RPScheduleFloatingButton(void);

__attribute__((constructor))
static void RPBootstrap(void) {
    @autoreleasepool {
        // 1) real HOME + chip before anything touches them
        [RPPaths captureRealHome];
        [RPDeviceIdentity captureRealChip];
        RPInstallCrashLogger();

        // 2) Always-on anti-detection (works even in Default container)
        [RPJailbreakBypass install];
        [RPDyldHook install];
        [RPReceiptHook install];
        [RPPasteboardHook install];

        // 3) load store
        [[RPContainerStore shared] load];
        RPContainer *active = [RPContainerStore shared].activeContainer;
        if (!active) active = [RPContainer defaultContainer];
        gBootCID = [active.cid copy];
        RPLog(@"RAPTOR load — active=%@ (%@) chip=%@", active.name, active.cid, [RPDeviceIdentity realChipFamily]);

        // 4) isolation atomique 4-piliers
        BOOL isolated = NO;
        if (!active.isDefault) {
            BOOL ok1 = [RPHomeRedirect applyForContainer:active];
            if (ok1) {
                // Bust Foundation cache immediately after HOME redirect
                RPBustHomeCache([RPPaths containerRootForCID:active.cid]);
            }
            BOOL ok2 = [RPKeychainHook installWithPrefix:[NSString stringWithFormat:@"RP:%@:", active.cid]];
            BOOL ok3 = [RPPrefsHook installForContainer:active];
            BOOL ok4 = [RPAppGroupHook installForContainer:active];
            isolated = ok1 && ok2 && ok3 && ok4;
            if (!isolated) {
                [RPHomeRedirect revertToRealHome];
                RPBustHomeCache([RPPaths realHome]);
                [RPContainerStore shared].isolationDegraded = YES;
                RPErr(@"isolation failed — degraded (ok1=%d ok2=%d ok3=%d ok4=%d)", ok1, ok2, ok3, ok4);
            } else {
                // Auto-adapt locale/timezone from location if user didn't force one
                [RPGeoIdentity autoAdaptContainer:active];
            }
        } else {
            [RPKeychainHook installDefaultHideMode];
        }

        // 5) spoof + hardening (only when isolated, sauf camera/location/pasteboard/dyld)
        if (isolated) {
            [RPDeviceSpoof installForContainer:active];
            [RPLocaleSpoof installForContainer:active];
            [RPHardening installForContainer:active];
            [RPPermissions installForContainer:active];
            // Re-protect with proper expiry handling
            RPInstallBackgroundReprotect([RPPaths containerRootForCID:active.cid]);
        } else if (!active.isDefault) {
            [RPHardening installForContainer:active];
        }

        [RPCameraHook installGlobal];
        [RPLocationSpoof install];

        RPScheduleFloatingButton();
        RPInstallStaleGuard();
    }
}
