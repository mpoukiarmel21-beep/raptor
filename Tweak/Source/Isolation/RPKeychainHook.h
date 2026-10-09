#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPKeychainHook : NSObject
+ (BOOL)installWithPrefix:(NSString *)prefix;
+ (BOOL)installDefaultHideMode;
+ (void)purgeItemsWithPrefix:(NSString *)prefix;
+ (NSUInteger)countItemsWithPrefix:(NSString *)prefix;
+ (void)purgeRealPasswordItems;
@end
NS_ASSUME_NONNULL_END
