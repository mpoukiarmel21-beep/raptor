#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPHomeRedirect : NSObject
+ (BOOL)applyForContainer:(RPContainer *)container;
+ (void)revertToRealHome;
@end
NS_ASSUME_NONNULL_END
