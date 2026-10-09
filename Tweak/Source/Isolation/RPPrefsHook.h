#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPPrefsHook : NSObject
+ (BOOL)installForContainer:(RPContainer *)container;
@end
NS_ASSUME_NONNULL_END
