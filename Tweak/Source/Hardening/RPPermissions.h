#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPPermissions : NSObject
+ (void)installForContainer:(RPContainer *)container;
@end
NS_ASSUME_NONNULL_END
