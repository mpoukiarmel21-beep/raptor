#import "RPTheme.h"
@implementation RPTheme
+ (UIColor *)accent { return [UIColor colorWithRed:0.42 green:0.28 blue:0.90 alpha:1]; }
+ (UIColor *)accentDeep { return [UIColor colorWithRed:0.278 green:0.168 blue:0.72 alpha:1]; }
+ (UIColor *)panelBackground { return [UIColor colorWithRed:0.07 green:0.063 blue:0.11 alpha:1]; }
+ (UIColor *)elevatedSurface { return [UIColor colorWithRed:0.11 green:0.094 blue:0.188 alpha:1]; }
+ (UIColor *)glassFill { return [UIColor colorWithWhite:1 alpha:0.10]; }
+ (UIColor *)glassStroke { return [UIColor colorWithWhite:1 alpha:0.16]; }
+ (UIColor *)primaryText { return [UIColor colorWithWhite:1 alpha:0.95]; }
+ (UIColor *)secondaryText { return [UIColor colorWithWhite:1 alpha:0.55]; }
+ (UIColor *)hairline { return [UIColor colorWithWhite:1 alpha:0.35]; }
- (void)applyAppearance {}
+ (void)applyAppearance {
    UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
    [a configureWithOpaqueBackground];
    a.backgroundColor = [self panelBackground];
    a.titleTextAttributes = @{NSForegroundColorAttributeName:[self primaryText]};
    [UINavigationBar appearance].standardAppearance = a;
    [UINavigationBar appearance].scrollEdgeAppearance = a;
}
@end
