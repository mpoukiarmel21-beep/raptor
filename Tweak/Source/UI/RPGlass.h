#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPGlass : NSObject
+ (UIView *)glassViewWithCornerRadius:(CGFloat)r tint:(nullable UIColor *)tint interactive:(BOOL)interactive;
+ (BOOL)liquidGlassAvailable;
@end
NS_ASSUME_NONNULL_END
