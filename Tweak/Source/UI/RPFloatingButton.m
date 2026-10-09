#import "RPFloatingButton.h"
#import "RPPanelVC.h"
#import "RPTheme.h"
#import <objc/runtime.h>

@interface RPOverlayWindow : UIWindow @end
@implementation RPOverlayWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *h=[super hitTest:p withEvent:e];
    if (self.rootViewController.presentedViewController) return h;
    // only button is interactive
    for (UIView *v in self.subviews) if ([v isKindOfClass:[UIButton class]] && CGRectContainsPoint(v.frame, p)) return v;
    // search inside container
    for (UIView *v in self.subviews) {
        UIView *r=[v hitTest:[self convertPoint:p toView:v] withEvent:e];
        if ([r isKindOfClass:[UIButton class]]) return r;
    }
    return nil;
}
@end

@interface RPFloatingButton () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) RPOverlayWindow *window;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, weak) UIWindow *prevKeyWindow;
@end

@implementation RPFloatingButton
+ (instancetype)shared { static RPFloatingButton *s; static dispatch_once_t t; dispatch_once(&t,^{ s=[self new]; }); return s; }

- (void)show {
    if (_window && !_window.hidden) {
        // heal if presentedViewController gone but hidden
        if (!_window.rootViewController.presentedViewController) _container.hidden = NO;
        return;
    }
    UIWindowScene *scene=nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) if ([sc isKindOfClass:[UIWindowScene class]]) { scene=(UIWindowScene*)sc; break; }
    if (!scene) return;
    _window=[[RPOverlayWindow alloc] initWithWindowScene:scene];
    _window.windowLevel=UIWindowLevelAlert+1;
    _window.frame=scene.coordinateSpace.bounds;
    _window.backgroundColor=[UIColor clearColor];
    _window.rootViewController=[UIViewController new];
    _window.rootViewController.view.backgroundColor=[UIColor clearColor];
    _window.hidden=NO;

    _container=[[UIView alloc] initWithFrame:CGRectMake(0,0,60,60)];
    _container.backgroundColor=[UIColor colorWithRed:0.06 green:0.05 blue:0.10 alpha:0.92];
    _container.layer.cornerRadius=14; _container.clipsToBounds=NO;
    _container.layer.shadowColor=[RPTheme accentDeep].CGColor; _container.layer.shadowOpacity=0.5; _container.layer.shadowRadius=14; _container.layer.shadowOffset=CGSizeMake(0,7);
    _container.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.10].CGColor; _container.layer.borderWidth=1;

    _button=[UIButton buttonWithType:UIButtonTypeSystem];
    _button.frame=_container.bounds; _button.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    UIImage *img=[UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]];
    [_button setImage:img forState:UIControlStateNormal]; _button.tintColor=[UIColor whiteColor];
    [_button addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    [_container addSubview:_button];
    [_window addSubview:_container];

    // restore position
    NSString *saved=[[NSUserDefaults standardUserDefaults] stringForKey:@"RPFloatingButtonCenter"];
    CGPoint c = saved.length ? CGPointFromString(saved) : CGPointMake(_window.bounds.size.width-40, _window.bounds.size.height*0.55);
    _container.center=[self clampedCenter:c inBounds:_window.bounds];

    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [_container addGestureRecognizer:pan];

    // observe DidBecomeActive to heal
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(heal) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)hide { _window.hidden=YES; }
- (void)heal { if (_window && !_window.hidden && !_window.rootViewController.presentedViewController) _container.hidden=NO; }

- (CGPoint)clampedCenter:(CGPoint)p inBounds:(CGRect)b {
    UIEdgeInsets safe=_window.safeAreaInsets;
    CGFloat r=34;
    CGFloat minX=b.origin.x+safe.left+r, maxX=b.origin.x+b.size.width-safe.right-r;
    CGFloat minY=b.origin.y+safe.top+r, maxY=b.origin.y+b.size.height-safe.bottom-r;
    return CGPointMake(MAX(minX,MIN(maxX,p.x)), MAX(minY,MIN(maxY,p.y)));
}

- (void)pan:(UIPanGestureRecognizer*)gr {
    CGPoint t=[gr translationInView:_window];
    if (gr.state==UIGestureRecognizerStateChanged) {
        _container.center=CGPointMake(_container.center.x+t.x, _container.center.y+t.y);
        [gr setTranslation:CGPointZero inView:_window];
    } else if (gr.state==UIGestureRecognizerStateEnded) {
        CGPoint c=_container.center;
        BOOL toRight = c.x > _window.bounds.size.width/2;
        CGFloat x = toRight ? _window.bounds.size.width-34 : 34;
        CGPoint target=[self clampedCenter:CGPointMake(x,c.y) inBounds:_window.bounds];
        BOOL reduce=UIAccessibilityIsReduceMotionEnabled();
        if (reduce) { _container.center=target; }
        else [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{ self->_container.center=target; } completion:nil];
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(target) forKey:@"RPFloatingButtonCenter"];
    }
}

- (void)tap {
    if (_window.rootViewController.presentedViewController) return;
    _prevKeyWindow=[UIApplication sharedApplication].keyWindow;
    RPPanelVC *panel=[RPPanelVC new];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle=UIModalPresentationPageSheet;
    nav.presentationController.delegate=self;
    // scale feedback
    _container.transform=CGAffineTransformMakeScale(0.9,0.9);
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{ self->_container.transform=CGAffineTransformIdentity; } completion:nil];
    [_window makeKeyAndVisible];
    [_window.rootViewController presentViewController:nav animated:YES completion:^{ self->_container.hidden=YES; }];
}

#pragma mark - delegate
- (void)presentationControllerDidDismiss:(UIPresentationController *)pc {
    _container.hidden=NO;
    if (_prevKeyWindow) [_prevKeyWindow makeKeyWindow];
}

@end

// Global helpers called from Bootstrap
void RPScheduleFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserver:[RPFloatingButton shared] selector:@selector(heal) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[RPFloatingButton shared] show];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[RPFloatingButton shared] show];
    });
}
