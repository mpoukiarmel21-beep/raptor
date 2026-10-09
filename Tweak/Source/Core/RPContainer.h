#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kRPDefaultCID;

@interface RPContainer : NSObject <NSCopying>

@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isDefault;

@property (nonatomic, copy, nullable) NSNumber *latitude;
@property (nonatomic, copy, nullable) NSNumber *longitude;
@property (nonatomic, copy, nullable) NSString *locationName;

@property (nonatomic, copy, nullable) NSString *deviceModel;
@property (nonatomic, copy, nullable) NSString *marketingName;
@property (nonatomic, copy, nullable) NSString *iosVersion;

@property (nonatomic, copy, nullable) NSString *appLanguage;
@property (nonatomic, copy, nullable) NSString *regionCountry;

@property (nonatomic, copy, nullable) NSString *cameraVideoPath;

@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *lastUsedAt;

+ (instancetype)containerWithName:(NSString *)name;
+ (instancetype)defaultContainer;

- (instancetype)initWithDict:(NSDictionary *)dict;
- (NSDictionary *)toDict;

- (BOOL)hasLocation;
- (NSString *)displayLocationName;

@end

NS_ASSUME_NONNULL_END
