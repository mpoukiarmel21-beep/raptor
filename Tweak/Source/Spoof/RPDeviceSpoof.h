#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPDeviceSpoof : NSObject
+ (void)installForContainer:(RPContainer *)container;
+ (NSString *)effectiveModelForContainer:(RPContainer *)container;
@end
NS_ASSUME_NONNULL_END
