#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSString *identifier;    // e.g. iPhone15,2
    NSString *marketingName; // e.g. iPhone 14 Pro
    NSString *chipFamily;    // e.g. A16 Bionic
} RPDeviceModel;

@interface RPDeviceIdentity : NSObject
+ (void)captureRealChip; // must be called before any sysctl hook, idempotent
+ (NSString *)realChipFamily;
+ (NSArray<NSValue *> *)allModels; // NSValue wrapping RPDeviceModel via box helper
+ (NSArray<NSValue *> *)modelsForRealChip;
+ (RPDeviceModel)modelForIdentifier:(NSString *)identifier;
+ (NSString *)marketingNameForIdentifier:(NSString *)identifier;
+ (RPDeviceModel)seededModelForCID:(NSString *)cid;
+ (NSArray<NSString *> *)iosVersions;
+ (NSString *)buildForIOSVersion:(NSString *)version;
+ (NSString *)seededIOSVersionForCID:(NSString *)cid;
+ (NSString *)serialForCID:(NSString *)cid;
+ (NSString *)modelNumberForCID:(NSString *)cid region:(nullable NSString *)region;
+ (NSValue *)boxModel:(RPDeviceModel)m;
+ (RPDeviceModel)unboxModel:(NSValue *)v;
@end

NS_ASSUME_NONNULL_END
