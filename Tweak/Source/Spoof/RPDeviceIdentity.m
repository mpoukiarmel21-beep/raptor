#import "RPDeviceIdentity.h"
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static NSString *gRealChipFamily = nil;
static NSString *gRealIdentifier = nil;
static dispatch_once_t gCaptureOnce;

static NSArray<NSDictionary *> *RPBuildMatrix(void) {
    // identifier, marketingName, chipFamily — newest first
    return @[
        @{@"id":@"iPhone18,2", @"name":@"iPhone 17 Pro Max", @"chip":@"A19 Pro"},
        @{@"id":@"iPhone18,1", @"name":@"iPhone 17 Pro",     @"chip":@"A19 Pro"},
        @{@"id":@"iPhone18,4", @"name":@"iPhone Air",        @"chip":@"A19 Pro"},
        @{@"id":@"iPhone18,3", @"name":@"iPhone 17",         @"chip":@"A19"},
        @{@"id":@"iPhone18,5", @"name":@"iPhone 17e",        @"chip":@"A19"},
        @{@"id":@"iPhone17,2", @"name":@"iPhone 16 Pro Max", @"chip":@"A18 Pro"},
        @{@"id":@"iPhone17,1", @"name":@"iPhone 16 Pro",     @"chip":@"A18 Pro"},
        @{@"id":@"iPhone17,4", @"name":@"iPhone 16 Plus",    @"chip":@"A18"},
        @{@"id":@"iPhone17,3", @"name":@"iPhone 16",         @"chip":@"A18"},
        @{@"id":@"iPhone17,5", @"name":@"iPhone 16e",        @"chip":@"A18"},
        @{@"id":@"iPhone16,2", @"name":@"iPhone 15 Pro Max", @"chip":@"A17 Pro"},
        @{@"id":@"iPhone16,1", @"name":@"iPhone 15 Pro",     @"chip":@"A17 Pro"},
        @{@"id":@"iPhone15,5", @"name":@"iPhone 15 Plus",    @"chip":@"A16 Bionic"},
        @{@"id":@"iPhone15,4", @"name":@"iPhone 15",         @"chip":@"A16 Bionic"},
        @{@"id":@"iPhone15,3", @"name":@"iPhone 14 Pro Max", @"chip":@"A16 Bionic"},
        @{@"id":@"iPhone15,2", @"name":@"iPhone 14 Pro",     @"chip":@"A16 Bionic"},
        @{@"id":@"iPhone14,8", @"name":@"iPhone 14 Plus",    @"chip":@"A15 (5-core)"},
        @{@"id":@"iPhone14,7", @"name":@"iPhone 14",         @"chip":@"A15 (5-core)"},
        @{@"id":@"iPhone14,3", @"name":@"iPhone 13 Pro Max", @"chip":@"A15 (5-core)"},
        @{@"id":@"iPhone14,2", @"name":@"iPhone 13 Pro",     @"chip":@"A15 (5-core)"},
        @{@"id":@"iPhone14,5", @"name":@"iPhone 13",         @"chip":@"A15 (4-core)"},
        @{@"id":@"iPhone14,4", @"name":@"iPhone 13 mini",    @"chip":@"A15 (4-core)"},
        @{@"id":@"iPhone13,4", @"name":@"iPhone 12 Pro Max", @"chip":@"A14 Bionic"},
        @{@"id":@"iPhone13,3", @"name":@"iPhone 12 Pro",     @"chip":@"A14 Bionic"},
        @{@"id":@"iPhone13,2", @"name":@"iPhone 12",         @"chip":@"A14 Bionic"},
        @{@"id":@"iPhone13,1", @"name":@"iPhone 12 mini",    @"chip":@"A14 Bionic"},
        @{@"id":@"iPhone12,5", @"name":@"iPhone 11 Pro Max", @"chip":@"A13 Bionic"},
        @{@"id":@"iPhone12,3", @"name":@"iPhone 11 Pro",     @"chip":@"A13 Bionic"},
        @{@"id":@"iPhone12,1", @"name":@"iPhone 11",         @"chip":@"A13 Bionic"},
    ];
}

@implementation RPDeviceIdentity

+ (void)captureRealChip {
    dispatch_once(&gCaptureOnce, ^{
        size_t len = 0;
        sysctlbyname("hw.machine", NULL, &len, NULL, 0);
        if (len > 0 && len < 64) {
            char buf[64] = {0};
            sysctlbyname("hw.machine", buf, &len, NULL, 0);
            gRealIdentifier = [[NSString stringWithUTF8String:buf] copy] ?: @"unknown";
        } else {
            gRealIdentifier = @"unknown";
        }
        // map to chipFamily
        NSString *chip = nil;
        for (NSDictionary *d in RPBuildMatrix()) {
            if ([d[@"id"] isEqualToString:gRealIdentifier]) { chip = d[@"chip"]; break; }
        }
        gRealChipFamily = [chip copy] ?: [gRealIdentifier copy];
    });
}

+ (NSString *)realChipFamily {
    [self captureRealChip];
    return gRealChipFamily ?: @"unknown";
}

+ (NSArray<NSValue *> *)allModels {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in RPBuildMatrix()) {
        RPDeviceModel m = { d[@"id"], d[@"name"], d[@"chip"] };
        [a addObject:[self boxModel:m]];
    }
    return a;
}

+ (NSArray<NSValue *> *)modelsForRealChip {
    [self captureRealChip];
    NSMutableArray *out = [NSMutableArray array];
    NSString *chip = [self realChipFamily];
    for (NSDictionary *d in RPBuildMatrix()) {
        if ([d[@"chip"] isEqualToString:chip]) {
            RPDeviceModel m = { d[@"id"], d[@"name"], d[@"chip"] };
            [out addObject:[self boxModel:m]];
        }
    }
    if (out.count == 0) {
        // synthetic: device newer than matrix
        RPDeviceModel m = { gRealIdentifier ?: @"unknown", gRealIdentifier ?: @"unknown", chip };
        [out addObject:[self boxModel:m]];
    }
    return out;
}

+ (RPDeviceModel)modelForIdentifier:(NSString *)identifier {
    for (NSDictionary *d in RPBuildMatrix()) {
        if ([d[@"id"] isEqualToString:identifier]) return (RPDeviceModel){ d[@"id"], d[@"name"], d[@"chip"] };
    }
    return (RPDeviceModel){ identifier, identifier, @"unknown" };
}

+ (NSString *)marketingNameForIdentifier:(NSString *)identifier {
    return [self modelForIdentifier:identifier].marketingName;
}

// ── seeding ──────────────────────────────────────────────────────────

static void RPSeedBytes(NSString *s, unsigned char out[CC_SHA256_DIGEST_LENGTH]) {
    NSData *d = [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
}

static uint32_t RPSeededIndex(NSString *cid, NSString *tag) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    RPSeedBytes([NSString stringWithFormat:@"%@|%@", cid ?: @"", tag], h);
    return ((uint32_t)h[0]<<24)|((uint32_t)h[1]<<16)|((uint32_t)h[2]<<8)|(uint32_t)h[3];
}

+ (RPDeviceModel)seededModelForCID:(NSString *)cid {
    NSArray<NSValue *> *cands = [self modelsForRealChip];
    uint32_t idx = RPSeededIndex(cid, @"model-pick") % (uint32_t)cands.count;
    return [self unboxModel:cands[idx]];
}

+ (NSArray<NSString *> *)iosVersions {
    // Real recent iOS — includes requested 27.0.1 / 26.7.1 head, then 18.5..17.5.1.
    // In sideload context the OS reports real version; this list is display + seeded identity.
    return @[@"27.0.1",@"27.0",@"26.7.1",@"26.7",@"26.6.1",@"26.6",@"26.5",@"18.5",@"18.4.1",@"18.4",@"18.3.1",@"18.3",@"18.2",@"18.1.1",@"18.1",@"18.0",@"17.6.1",@"17.5.1"];
}

+ (NSString *)buildForIOSVersion:(NSString *)v {
    NSDictionary *map = @{@"27.0.1":@"23K50",@"27.0":@"23K40",@"26.7.1":@"23J82",@"26.7":@"23J71",@"26.6.1":@"23G83",@"26.6":@"23G71",@"26.5":@"23F84",@"18.5":@"22F76",@"18.4.1":@"22E772",@"18.4":@"22E240",@"18.3.1":@"22D72",@"18.3":@"22D63",@"18.2":@"22C152",@"18.1.1":@"22B91",@"18.1":@"22B83",@"18.0":@"22A3354",@"17.6.1":@"21G101",@"17.5.1":@"21F90"};
    return map[v] ?: @"23K50";
}

+ (NSString *)seededIOSVersionForCID:(NSString *)cid {
    NSArray *vs = [self iosVersions];
    uint32_t idx = RPSeededIndex(cid, @"ios-pick") % (uint32_t)vs.count;
    return vs[idx];
}

+ (NSString *)serialForCID:(NSString *)cid {
    static NSString *charset = @"0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    RPSeedBytes([NSString stringWithFormat:@"%@|serial", cid ?: @""], h);
    NSMutableString *s = [NSMutableString stringWithCapacity:10];
    for (int i=0;i<10;i++) [s appendFormat:@"%C", [charset characterAtIndex:h[i]%charset.length]];
    return s;
}

+ (NSString *)modelNumberForCID:(NSString *)cid region:(NSString *)region {
    NSDictionary *suffix = @{@"US":@"LL",@"FR":@"F",@"GB":@"B",@"DE":@"D",@"IT":@"T",@"ES":@"Y",@"CA":@"C",@"AU":@"X",@"JP":@"J",@"CN":@"CH",@"BE":@"FS",@"NL":@"FS"};
    NSString *suf = suffix[region] ?: @"LL";
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    RPSeedBytes([NSString stringWithFormat:@"%@|modelnum", cid ?: @""], h);
    NSString *charset = @"0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSMutableString *mid = [NSMutableString stringWithCapacity:4];
    for (int i=0;i<4;i++) [mid appendFormat:@"%C", [charset characterAtIndex:h[i]%charset.length]];
    return [NSString stringWithFormat:@"M%@%@/A", mid, suf];
}

+ (NSValue *)boxModel:(RPDeviceModel)m {
    return [NSValue valueWithBytes:&m objCType:@encode(RPDeviceModel)];
}
+ (RPDeviceModel)unboxModel:(NSValue *)v {
    if ([v isKindOfClass:[NSValue class]]) { RPDeviceModel mm; [v getValue:&mm]; return mm; }
    return (RPDeviceModel){@"unknown",@"unknown",@"unknown"};
}

@end
