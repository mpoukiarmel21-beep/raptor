#import "RPDeviceSpoof.h"
#import "RPDeviceIdentity.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static NSString *gVendorUUID = nil;
static NSString *gAdvUUID = nil;
static BOOL gInstalled = NO;

static void RPSeedBytes(NSString *s, unsigned char out[CC_SHA256_DIGEST_LENGTH]) {
    NSData *d = [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
}

static NSUUID *RPSeededUUID(NSString *cid, NSString *tag) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    RPSeedBytes([NSString stringWithFormat:@"%@|%@", cid, tag], h);
    return [[NSUUID alloc] initWithUUIDBytes:h];
}

static void RPSwizzleUUID(Class cls, SEL sel, NSString *(^uuidStr)(void)) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^NSUUID *(id _self){ return [[NSUUID alloc] initWithUUIDString:uuidStr()]; });
    method_setImplementation(m, imp);
}
static void RPSwizzleString(Class cls, SEL sel, NSString *(^str)(void)) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^NSString *(id _self){ return str(); });
    method_setImplementation(m, imp);
}

static NSString *RPSeededDeviceName(NSString *cid) {
    static const char *pool[] = {"Alex's iPhone","Sam's iPhone","Jordan's iPhone","Riley's iPhone","Casey's iPhone","Morgan's iPhone","Avery's iPhone","Quinn's iPhone","Jamie's iPhone","Taylor's iPhone","Drew's iPhone","Skyler's iPhone","Reese's iPhone","Emerson's iPhone","Finley's iPhone","Rowan's iPhone"};
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    RPSeedBytes([NSString stringWithFormat:@"%@|devname", cid ?: @""], h);
    return [NSString stringWithUTF8String:pool[h[0] % 16]];
}

@implementation RPDeviceSpoof

+ (NSString *)effectiveModelForContainer:(RPContainer *)container {
    if (container.deviceModel.length) return container.deviceModel;
    return [RPDeviceIdentity seededModelForCID:container.cid].identifier;
}

+ (void)installForContainer:(RPContainer *)container {
    if (gInstalled) return;
    if (!container || container.isDefault) return;
    gInstalled = YES;
    gVendorUUID = [RPSeededUUID(container.cid, @"idfv").UUIDString copy];
    gAdvUUID    = [RPSeededUUID(container.cid, @"idfa").UUIDString copy];
    RPSwizzleUUID([UIDevice class], @selector(identifierForVendor), ^NSString*{ return gVendorUUID; });
    Class am = NSClassFromString(@"ASIdentifierManager");
    RPSwizzleUUID(am, NSSelectorFromString(@"advertisingIdentifier"), ^NSString*{ return gAdvUUID; });
    NSString *devName = [RPSeededDeviceName(container.cid) copy];
    RPSwizzleString([UIDevice class], @selector(name), ^NSString*{ return devName; });
}

@end
