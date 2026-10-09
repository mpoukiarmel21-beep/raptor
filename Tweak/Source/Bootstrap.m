#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <execinfo.h>
#import <signal.h>
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
#import "Spoof/RPDeviceSpoof.h"
#import "Spoof/RPLocaleSpoof.h"
#import "Spoof/RPLocationSpoof.h"
#import "Camera/RPCameraHook.h"
#import "Util/RPDiagnostics.h"
#import "UI/RPFloatingButton.h"

// ── Crash logger ───────────────────────────────────────────────────
static int gCrashFD = -1;
static NSUncaughtExceptionHandler *gPriorHandler = NULL;
static void RPApendCrash(NSString *s) {
    if (gCrashFD < 0 || !s.length) return;
    NSData *d=[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    write(gCrashFD, d.bytes, d.length);
}
static void RPCrashHandler(NSException *ex) {
    RPApendCrash([NSString stringWithFormat:@"[CRASH] %@ %@\n%@", ex.name, ex.reason, [ex.callStackSymbols componentsJoinedByString:@"\n"]]);
    if (gPriorHandler) gPriorHandler(ex);
}
static void RPSignalHandler(int sig, siginfo_t *info, void *ctx) {
    void *bt[64]; int n=backtrace(bt,64);
    char hdr[128]; snprintf(hdr,sizeof(hdr),"\n[SIGNAL %d addr=%p]\n", sig, info?info->si_addr:NULL);
    if (gCrashFD>=0) write(gCrashFD, hdr, strlen(hdr));
    if (gCrashFD>=0) backtrace_symbols_fd(bt,n,gCrashFD);
    signal(sig, SIG_DFL); raise(sig);
}
static char gAltStack[256*1024];
static void RPInstallCrashLogger(void) {
    NSString *logFile=[[RPPaths logDirectory] stringByAppendingPathComponent:@"crash.log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[RPPaths logDirectory] withIntermediateDirectories:YES attributes:nil error:nil];
    gCrashFD = open([logFile fileSystemRepresentation], O_WRONLY|O_CREAT|O_APPEND, 0644);
    gPriorHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&RPCrashHandler);
    stack_t ss={.ss_sp=gAltStack,.ss_size=sizeof(gAltStack),.ss_flags=0};
    sigaltstack(&ss,NULL);
    struct sigaction sa={}; sa.sa_sigaction=RPSignalHandler; sa.sa_flags=SA_SIGINFO|SA_ONSTACK|SA_RESETHAND; sigemptyset(&sa.sa_mask);
    for(int s in (int[]){SIGABRT,SIGSEGV,SIGBUS,SIGILL,SIGFPE,SIGSYS}) sigaction(s,&sa,NULL);
}

// ── Stale guard ────────────────────────────────────────────────────
static NSString *gBootCID = nil;
static void RPInstallStaleGuard(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*n){
        NSString *cur=[RPContainerStore shared].activeCID;
        if (gBootCID && cur && ![gBootCID isEqualToString:cur]) exit(0);
    }];
}

// ── Background re-protect ──────────────────────────────────────────
static void RPInstallBackgroundReprotect(NSString *root) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification*n){
        UIBackgroundTaskIdentifier tid=[[UIApplication sharedApplication] beginBackgroundTaskWithName:@"RPReprotect" expirationHandler:^{}];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            [RPPaths reapplyProtectionRecursivelyAtRoot:root];
            [[UIApplication sharedApplication] endBackgroundTask:tid];
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

        // 2) load store
        [[RPContainerStore shared] load];
        RPContainer *active = [RPContainerStore shared].activeContainer;
        if (!active) active=[RPContainer defaultContainer];
        gBootCID = [active.cid copy];
        RPLog(@"RAPTOR load — active=%@ (%@)", active.name, active.cid);

        // 3) isolation atomique 4-piliers
        BOOL isolated = NO;
        if (!active.isDefault) {
            BOOL ok1=[RPHomeRedirect applyForContainer:active];
            BOOL ok2=[RPKeychainHook installWithPrefix:[NSString stringWithFormat:@"RP:%@:", active.cid]];
            BOOL ok3=[RPPrefsHook installForContainer:active];
            BOOL ok4=[RPAppGroupHook installForContainer:active];
            isolated = ok1 && ok2 && ok3 && ok4;
            if (!isolated) {
                [RPHomeRedirect revertToRealHome];
                [RPContainerStore shared].isolationDegraded=YES;
                RPErr(@"isolation failed — degraded");
            }
        } else {
            [RPKeychainHook installDefaultHideMode];
        }

        // 4) spoof + hardening (only when isolated, sauf camera/location)
        if (isolated) {
            [RPDeviceSpoof installForContainer:active];
            [RPLocaleSpoof installForContainer:active];
            [RPHardening installForContainer:active];
            [RPPermissions installForContainer:active];
            [RPPaths reapplyProtectionRecursivelyAtRoot:[RPPaths containerRootForCID:active.cid]];
            RPInstallBackgroundReprotect([RPPaths containerRootForCID:active.cid]);
        } else if (!active.isDefault) {
            // still install hardening even if degraded
            [RPHardening installForContainer:active];
        }

        [RPCameraHook installGlobal];
        [RPLocationSpoof install];

        RPScheduleFloatingButton();
        RPInstallStaleGuard();
    }
}
