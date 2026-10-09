#import "RPReceiptHook.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@implementation RPReceiptHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Sideloaded apps have no valid App Store receipt. Instagram checks appStoreReceiptURL.
        // We make it return nil (same as App Store build before receipt download) — less suspicious than a fake.
        // Also hook SKReceiptRefreshRequest to silently succeed.
        Class bundleCls = [NSBundle class];
        SEL sel = @selector(appStoreReceiptURL);
        Method m = class_getInstanceMethod(bundleCls, sel);
        if (m) {
            // Don't hide receipt aggressively — sideloadly already patches this.
            // Just ensure it doesn't leak our container path as receipt location.
            // Leave as-is for now; the sideloaded receipt bypass is handled by the signer.
            (void)m;
        }
        // Hook receipt refresh to no-op success (prevents Instagram from detecting refresh failure as sideload signal)
        Class reqCls = NSClassFromString(@"SKReceiptRefreshRequest");
        if (reqCls) {
            SEL startSel = NSSelectorFromString(@"start");
            Method sm = class_getInstanceMethod(reqCls, startSel);
            if (sm) {
                method_setImplementation(sm, imp_implementationWithBlock(^(id _self){
                    // Simulate successful refresh — call delegate's requestDidFinish: after short delay
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        SEL didFinish = NSSelectorFromString(@"requestDidFinish:");
                        if ([_self respondsToSelector:didFinish]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            [_self performSelector:didFinish withObject:_self];
#pragma clang diagnostic pop
                        }
                    });
                }));
            }
        }
    });
}

@end
