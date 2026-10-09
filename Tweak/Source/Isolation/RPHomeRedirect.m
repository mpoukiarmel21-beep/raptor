#import "RPHomeRedirect.h"
#import "RPContainer.h"
#import "RPPaths.h"

@implementation RPHomeRedirect

+ (BOOL)applyForContainer:(RPContainer *)container {
    if (!container || container.isDefault || [container.cid isEqualToString:kRPDefaultCID]) {
        return YES;
    }
    NSString *root = [RPPaths containerRootForCID:container.cid];
    NSError *err = nil;
    if (![RPPaths ensureSkeletonAtRoot:root error:&err]) return NO;
    NSString *tmp = [root stringByAppendingPathComponent:@"tmp"];
    setenv("CFFIXED_USER_HOME", [root UTF8String], 1);
    setenv("HOME", [root UTF8String], 1);
    setenv("TMPDIR", [[tmp stringByAppendingString:@"/"] UTF8String], 1);
    return YES;
}

+ (void)revertToRealHome {
    NSString *real = [RPPaths realHome];
    if (!real.length) real = NSHomeDirectory();
    setenv("CFFIXED_USER_HOME", [real UTF8String], 1);
    setenv("HOME", [real UTF8String], 1);
    NSString *tmp = [real stringByAppendingPathComponent:@"tmp"];
    setenv("TMPDIR", [[tmp stringByAppendingString:@"/"] UTF8String], 1);
}

@end
