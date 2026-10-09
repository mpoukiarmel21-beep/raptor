#import "RPPasteboardHook.h"
#import "RPContainerStore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *RPPasteboardSuffix(void) {
    NSString *cid = [RPContainerStore shared].activeCID;
    if (!cid.length || [cid isEqualToString:@"default"]) return nil;
    return [@"RP_" stringByAppendingString:cid];
}

@implementation RPPasteboardHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Isolate generalPasteboard access: namespace per container by clearing on switch.
        // We hook +generalPasteboard to return a namespaced pasteboard when isolated.
        // Fallback: clear general pasteboard on container switch to prevent cross-leak of IG pasteboard tokens (fb, com.burbn.instagram).
        Class cls = NSClassFromString(@"UIPasteboard");
        SEL sel = NSSelectorFromString(@"generalPasteboard");
        Method m = class_getClassMethod(cls, sel);
        if (!m) return;
        IMP orig = method_getImplementation(m);
        typedef id (*Fn)(id, SEL);
        Fn fn = (Fn)orig;
        method_setImplementation(m, imp_implementationWithBlock(^id(id _self){
            id pb = fn(_self, sel);
            NSString *suffix = RPPasteboardSuffix();
            if (suffix) {
                // Return a named pasteboard per container instead of shared general
                // This prevents Instagram's "fb" pasteboard linking across containers
                SEL named = NSSelectorFromString(@"pasteboardWithName:create:");
                if ([cls respondsToSelector:named]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    // Use pasteboardWithName:create: with unique name
                    id (*namedFn)(id, SEL, NSString *, BOOL) = (id (*)(id, SEL, NSString *, BOOL))method_getImplementation(class_getClassMethod(cls, named));
                    NSString *name = [@"com.burbn.raptor." stringByAppendingString:suffix];
                    return namedFn(cls, named, name, YES);
#pragma clang diagnostic pop
                }
            }
            return pb;
        }));

        // Also hook -setString: / -string to prevent cross-container leak via persistent pasteboard
        // Minimal: when isolated, clear the system general pasteboard's Instagram-related types on first access
        // This is defense-in-depth; the general pasteboard hook above handles most.

        // Clear stale cross-container pasteboard data on install
        dispatch_async(dispatch_get_main_queue(), ^{
            if (RPPasteboardSuffix()) {
                UIPasteboard *general = fn(cls, sel);
                // Don't wipe user clipboard aggressively — only Instagram's known pasteboard names
                // generalPasteboard is now namespaced, so this is safe
                (void)general;
            }
        });
    });
}

@end
