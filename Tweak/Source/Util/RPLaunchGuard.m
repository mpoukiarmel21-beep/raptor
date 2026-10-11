#import "RPLaunchGuard.h"
#import "RPDiagnostics.h"
#import "RPAppRelaunch.h"
#import "RPL10n.h"
#import "Core/RPPaths.h"
#import <UIKit/UIKit.h>

// After this many launches in a row that never reached the foreground, we stop
// applying the risky stages. Settings/containers are always kept.
static const NSInteger kRPSafeModeThreshold = 3;

static NSString *RPGuardPath(void) {
    return [[RPPaths controlDir] stringByAppendingPathComponent:@"launchguard.plist"];
}

static NSMutableDictionary *RPGuardRead(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:RPGuardPath()];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

static void RPGuardWrite(NSDictionary *d) {
    [RPPaths ensureControlDir];
    [d writeToFile:RPGuardPath() atomically:YES];
}

static void RPGuardNoteStable(void) {
    NSMutableDictionary *d = RPGuardRead();
    NSInteger streak = [d[@"crashStreak"] integerValue];
    if (streak > 0) RPLog(@"[LaunchGuard] reached foreground OK (previous streak=%ld)", (long)streak);
    d[@"crashStreak"] = @0;
    d[@"lastStatus"] = @"ok";
    if (d[@"safeMode"] == nil) d[@"safeMode"] = @NO;
    RPGuardWrite(d);
}

@implementation RPLaunchGuard

+ (void)noteLaunchBegin {
    [RPPaths ensureControlDir];
    NSMutableDictionary *d = RPGuardRead();
    NSInteger streak = [d[@"crashStreak"] integerValue];
    NSString *prev = d[@"lastStatus"] ?: @"";
    // If the previous launch never reported "ok", it crashed before the foreground.
    if ([prev isEqualToString:@"launching"]) streak += 1;
    else streak = 1;
    d[@"crashStreak"] = @(streak);
    d[@"lastStatus"] = @"launching";

    if (streak >= kRPSafeModeThreshold) {
        BOOL wasOff = ![d[@"safeMode"] boolValue];
        d[@"safeMode"] = @YES;
        if (wasOff) d[@"disabledAt"] = [NSDate date];
        RPLog(@"[LaunchGuard] %ld consecutive launch crashes -> SAFE MODE ON (settings kept, applied off)", (long)streak);
    } else {
        RPLog(@"[LaunchGuard] launch begin streak=%ld safeMode=%d", (long)streak, [d[@"safeMode"] boolValue]);
    }
    RPGuardWrite(d);
}

+ (BOOL)safeModeActive {
    return [RPGuardRead()[@"safeMode"] boolValue];
}

+ (BOOL)shouldRunRiskyStages {
    return ![self safeModeActive];
}

+ (void)clearSafeMode {
    NSMutableDictionary *d = RPGuardRead();
    d[@"safeMode"] = @NO;
    d[@"crashStreak"] = @0;
    d[@"lastStatus"] = @"cleared";
    RPGuardWrite(d);
    RPLog(@"[LaunchGuard] safe mode cleared by user");
}

// ── UI ──────────────────────────────────────────────────────────────
static UIViewController *RPTopViewController(void) {
    UIWindow *key = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    UIViewController *vc = key.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)presentSafeModeAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = RPTopViewController();
        if (!top) return;
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:RPLL(@"safe.title", @"Mode sans échec")
                             message:RPLL(@"safe.msg", @"Un réglage a fait planter l'app 3 fois de suite. Les tweaks ont été désactivés, tes réglages sont conservés.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:RPLL(@"safe.reenable", @"Réactiver")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
            [RPLaunchGuard clearSafeMode];
            RPCloseAppForRelaunch();
        }]];
        [a addAction:[UIAlertAction actionWithTitle:RPLL(@"safe.keep", @"Laisser désactivé")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [top presentViewController:a animated:YES completion:nil];
    });
}

+ (void)install {
    static BOOL gAlertShown = NO;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *_Nonnull n) {
        RPGuardNoteStable();
        if (!gAlertShown && [RPLaunchGuard safeModeActive]) {
            gAlertShown = YES;
            [RPLaunchGuard presentSafeModeAlert];
        }
    }];
}

@end
