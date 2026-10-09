#import "RPHardening.h"
#import "RPContainer.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void RPSetBoolReturn(Class cls, SEL sel, BOOL v) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _s){ return v; }));
}
static void RPFailCompletion(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, imp_implementationWithBlock(^(id _self, void (^cb)(NSData*,NSError*)){
        if (!cb) return;
        NSError *e = [NSError errorWithDomain:@"com.apple.devicecheck.error" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Feature unsupported"}];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ cb(nil,e); });
    }));
}
static void RPFailCompletion2(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, imp_implementationWithBlock(^(id _self, id a, NSData *b, void (^cb)(id,NSError*)){
        if (!cb) return;
        NSError *e = [NSError errorWithDomain:@"com.apple.devicecheck.error" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Feature unsupported"}];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ cb(nil,e); });
    }));
}

@implementation RPHardening
+ (void)installForContainer:(RPContainer *)container {
    static dispatch_once_t once; dispatch_once(&once, ^{
        Class dc = NSClassFromString(@"DCDevice");
        if (dc) { RPSetBoolReturn(dc, @selector(isSupported), NO); RPFailCompletion(dc, NSSelectorFromString(@"generateTokenWithCompletionHandler:")); }
        Class da = NSClassFromString(@"DCAppAttestService");
        if (da) {
            RPSetBoolReturn(da, @selector(isSupported), NO);
            RPFailCompletion(da, NSSelectorFromString(@"generateKeyWithCompletionHandler:"));
            RPFailCompletion2(da, NSSelectorFromString(@"attestKey:clientDataHash:completionHandler:"));
            RPFailCompletion2(da, NSSelectorFromString(@"generateAssertion:clientDataHash:completionHandler:"));
        }
        // AutoFill strip
        Method m = class_getInstanceMethod([UITextField class], @selector(textContentType));
        if (m) {
            IMP orig = method_getImplementation(m);
            typedef NSString* (*Fn)(id,SEL);
            Fn fn = (Fn)orig;
            method_setImplementation(m, imp_implementationWithBlock(^NSString*(id _self){
                NSString *origVal = fn(_self, @selector(textContentType));
                if ([origVal isEqualToString:UITextContentTypeEmailAddress]||
                    [origVal isEqualToString:UITextContentTypeUsername]||
                    [origVal isEqualToString:UITextContentTypePassword]||
                    [origVal isEqualToString:UITextContentTypeNewPassword]) return nil;
                return origVal;
            }));
        }
        // Suppress APNs registration in isolated containers
        Class appCls = NSClassFromString(@"UIApplication");
        SEL regSel = NSSelectorFromString(@"registerForRemoteNotifications");
        Method regM = class_getInstanceMethod(appCls, regSel);
        if (regM) {
            // Only suppress when isolated: read store late
            IMP orig = method_getImplementation(regM);
            typedef void (*RegFn)(id,SEL);
            RegFn origReg = (RegFn)orig;
            method_setImplementation(regM, imp_implementationWithBlock(^(id _self){
                // check isolation via env HOME contains /Raptor/Instances/
                const char *home = getenv("HOME");
                NSString *hs = home ? [NSString stringWithUTF8String:home] : @"";
                if ([hs containsString:@"/Raptor/Instances/"]) return; // suppress
                origReg(_self, regSel);
            }));
        }
        // ATT spoof: return NotDetermined
        Class attCls = NSClassFromString(@"ATTrackingManager");
        SEL attSel = NSSelectorFromString(@"trackingAuthorizationStatus");
        Method attM = class_getClassMethod(attCls, attSel);
        if (attM) {
            method_setImplementation(attM, imp_implementationWithBlock(^NSInteger(id _self){ return 0; })); // NotDetermined
        }
    });
}
@end
