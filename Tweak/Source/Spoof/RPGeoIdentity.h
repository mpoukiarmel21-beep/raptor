#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPGeoIdentity : NSObject
+ (void)autoAdaptContainer:(RPContainer *)container;
+ (nullable NSDictionary *)profileForRegion:(NSString *)region;
@end
NS_ASSUME_NONNULL_END
