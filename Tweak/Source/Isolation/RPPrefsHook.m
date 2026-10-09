#import "RPPrefsHook.h"
#import "RPContainer.h"
#import "RPPaths.h"
#import <objc/runtime.h>

static BOOL gInstalled = NO;

@implementation RPPrefsHook

+ (BOOL)installForContainer:(RPContainer *)container {
    if (gInstalled) return YES;
    if (!container || container.isDefault || [container.cid isEqualToString:kRPDefaultCID]) {
        gInstalled = YES;
        return YES;
    }
    // Private CFPrefsPlistSource selector
    Class cls = NSClassFromString(@"CFPrefsPlistSource");
    if (!cls) cls = NSClassFromString(@"__CFPrefsPlistSource");
    SEL sel = NSSelectorFromString(@"initWithDomain:user:byHost:containerPath:containingPreferences:");
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        // Fail-loud so Bootstrap can revert atomically
        return NO;
    }
    // Save orig
    IMP orig = method_getImplementation(m);
    typedef id (*OrigFn)(id, SEL, CFStringRef, CFStringRef, BOOL, CFStringRef, CFDictionaryRef);
    OrigFn origFn = (OrigFn)orig;

    NSString *containerPrefsPath = [[RPPaths containerRootForCID:container.cid] stringByAppendingPathComponent:@"Library/Preferences"];
    [[NSFileManager defaultManager] createDirectoryAtPath:containerPrefsPath withIntermediateDirectories:YES attributes:nil error:nil];

    IMP newImp = imp_implementationWithBlock(^id(id _self, CFStringRef domain, CFStringRef user, BOOL byHost, CFStringRef containerPath, CFDictionaryRef containingPrefs) {
        NSString *dom = (__bridge NSString *)domain;
        BOOL isApple = [dom hasPrefix:@"com.apple."];
        CFStringRef effectiveContainerPath = containerPath;
        CFStringRef effectiveUser = user;
        NSString *redirectPath = nil;
        if (!isApple && dom.length) {
            redirectPath = containerPrefsPath;
            effectiveContainerPath = (__bridge CFStringRef)redirectPath;
            // Force CurrentUser when redirected
            if (user && CFEqual(user, kCFPreferencesAnyUser)) {
                effectiveUser = kCFPreferencesCurrentUser;
            }
        }
        return origFn(_self, sel, domain, effectiveUser, byHost, effectiveContainerPath, containingPrefs);
    });
    method_setImplementation(m, newImp);
    gInstalled = YES;
    return YES;
}

@end
