#import "RPGlass.h"
@implementation RPGlass
+ (BOOL)liquidGlassAvailable { return NSClassFromString(@"UIGlassEffect") != nil; }
+ (UIView *)glassViewWithCornerRadius:(CGFloat)r tint:(UIColor *)tint interactive:(BOOL)interactive {
    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        UIView *v=[[UIView alloc] init];
        v.backgroundColor=[UIColor colorWithRed:0.11 green:0.094 blue:0.188 alpha:1];
        v.layer.cornerRadius=r; v.clipsToBounds=YES;
        v.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.16].CGColor; v.layer.borderWidth=1;
        return v;
    }
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        id eff = [[ge alloc] init];
        @try { [eff setValue:(tint ?: [UIColor colorWithWhite:1 alpha:0.10]) forKey:@"tintColor"]; [eff setValue:@(interactive) forKey:@"interactive"]; } @catch(NSException *e){}
        UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:(UIVisualEffect*)eff];
        v.layer.cornerRadius=r; v.clipsToBounds=YES;
        return v;
    }
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:blur];
    v.layer.cornerRadius=r; v.clipsToBounds=YES;
    return v;
}
@end
