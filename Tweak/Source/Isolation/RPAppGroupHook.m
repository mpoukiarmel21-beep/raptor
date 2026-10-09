#import "RPAppGroupHook.h"
#import "RPContainer.h"
#import "RPPaths.h"
#import <objc/runtime.h>

static NSString *RPSafeGroupComponent(NSString *gid) {
    if (!gid.length) return @"default";
    NSMutableString *s = [gid mutableCopy];
    [s replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@":" withString:@"_" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\0" withString:@"_" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

@implementation RPAppGroupHook

+ (BOOL)installForContainer:(RPContainer *)container {
    Class cls = [NSFileManager class];
    SEL sel = @selector(containerURLForSecurityApplicationGroupIdentifier:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return YES; // nothing to hook
    // Already default? passthrough
    if (!container || container.isDefault || [container.cid isEqualToString:kRPDefaultCID]) return YES;

    NSString *containerRoot = [RPPaths containerRootForCID:container.cid];
    IMP orig = method_getImplementation(m);
    typedef NSURL* (*OrigFn)(id, SEL, NSString*);
    OrigFn origFn = (OrigFn)orig;

    IMP newImp = imp_implementationWithBlock(^NSURL*(id _self, NSString *gid) {
        if (!gid.length) return origFn(_self, sel, gid);
        NSString *safe = RPSafeGroupComponent(gid);
        NSString *base = [[containerRoot stringByAppendingPathComponent:@"AppGroups"] stringByAppendingPathComponent:safe];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *sub in @[@"", @"Library", @"Library/Caches", @"Documents"]) {
            NSString *p = sub.length ? [base stringByAppendingPathComponent:sub] : base;
            if (![fm fileExistsAtPath:p]) [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
        }
        return [NSURL fileURLWithPath:base isDirectory:YES];
    });
    method_setImplementation(m, newImp);
    return YES;
}

@end
