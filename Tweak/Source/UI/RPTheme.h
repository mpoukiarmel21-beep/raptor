#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPTheme : NSObject
+ (UIColor *)accent;
+ (UIColor *)accentDeep;
+ (UIColor *)panelBackground;
+ (UIColor *)elevatedSurface;
+ (UIColor *)glassFill;
+ (UIColor *)glassStroke;
+ (UIColor *)primaryText;
+ (UIColor *)secondaryText;
+ (UIColor *)hairline;
+ (void)applyAppearance;
@end
NS_ASSUME_NONNULL_END
