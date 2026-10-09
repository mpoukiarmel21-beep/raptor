#import "RPActionSheet.h"
#import "RPTheme.h"
#import "RPGlass.h"
@implementation RPAction
+ (instancetype)actionWithTitle:(NSString *)t symbol:(NSString *)s style:(RPActionStyle)st handler:(void(^)(void))h {
    RPAction *a=[self new]; a.title=t; a.symbol=s; a.style=st; a.handler=h; return a;
}
@end
@interface RPActionSheet ()
@property (nonatomic, copy) NSString *sheetTitle; @property (nonatomic, copy) NSString *sheetMessage;
@property (nonatomic, strong) NSMutableArray<RPAction*>*actions;
@property (nonatomic, strong) UIView *backdrop, *tray;
@end
@implementation RPActionSheet
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    self=[super init]; if(self){ _sheetTitle=title; _sheetMessage=message; _actions=[NSMutableArray array]; self.modalPresentationStyle=UIModalPresentationOverFullScreen; self.modalTransitionStyle=UIModalTransitionStyleCrossDissolve; } return self;
}
- (void)addAction:(RPAction *)a { [_actions addObject:a]; }
- (void)presentFrom:(UIViewController *)vc { [vc presentViewController:self animated:NO completion:nil]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor clearColor];
    _backdrop=[[UIView alloc] initWithFrame:self.view.bounds]; _backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _backdrop.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55];
    [_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
    [self.view addSubview:_backdrop];
    _tray=[[UIView alloc] init]; _tray.backgroundColor=[UIColor clearColor];
    [self.view addSubview:_tray];
    CGFloat W=self.view.bounds.size.width;
    CGFloat pad=18, trayW=MIN(W-pad*2, 420);
    CGFloat y=pad, h=58, gap=8;
    // header
    if (_sheetTitle.length || _sheetMessage.length) {
        UIView *card=[RPGlass glassViewWithCornerRadius:16 tint:[RPTheme glassFill] interactive:NO];
        card.layer.borderColor=[RPTheme glassStroke].CGColor; card.layer.borderWidth=1;
        UILabel *tl=[[UILabel alloc] init]; tl.text=_sheetTitle; tl.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; tl.textColor=[RPTheme primaryText]; tl.numberOfLines=0; tl.textAlignment=NSTextAlignmentCenter;
        UILabel *ml=[[UILabel alloc] init]; ml.text=_sheetMessage; ml.font=[UIFont systemFontOfSize:13]; ml.textColor=[RPTheme secondaryText]; ml.numberOfLines=0; ml.textAlignment=NSTextAlignmentCenter;
        CGFloat ch=16; if(_sheetTitle.length) ch+=20; if(_sheetMessage.length) ch+=18;
        card.frame=CGRectMake((W-trayW)/2, y, trayW, ch+16);
        tl.frame=CGRectMake(12,8,trayW-24,20); ml.frame=CGRectMake(12,28,trayW-24,18);
        if(_sheetTitle.length) [card addSubview:tl]; if(_sheetMessage.length) [card addSubview:ml];
        [_tray addSubview:card]; y+= ch+16+gap;
        _tray.frame=CGRectMake(0,0,W,y+200);
    } else {
        _tray.frame=CGRectMake(0,0,W,200);
    }
    CGFloat curY = _tray.subviews.lastObject ? CGRectGetMaxY(_tray.subviews.lastObject.frame)+gap : y;
    CGFloat btnW=trayW;
    for (RPAction *a in _actions) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
        b.frame=CGRectMake((W-btnW)/2, curY, btnW, h);
        b.layer.cornerRadius=16; b.clipsToBounds=YES;
        [b setTitle:a.title forState:UIControlStateNormal]; b.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        if (a.symbol) { UIImage *img=[UIImage systemImageNamed:a.symbol]; [b setImage:img forState:UIControlStateNormal]; b.tintColor=[RPTheme primaryText]; b.imageEdgeInsets=UIEdgeInsetsMake(0,-6,0,6); }
        if (a.style==RPActionStyleAccent) { b.backgroundColor=[RPTheme accent]; [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; b.tintColor=[UIColor whiteColor]; }
        else if (a.style==RPActionStyleAccentSoft) { UIView *bg=[RPGlass glassViewWithCornerRadius:16 tint:[RPTheme glassFill] interactive:NO]; bg.frame=b.bounds; bg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; bg.userInteractionEnabled=NO; [b insertSubview:bg atIndex:0]; [b setTitleColor:[RPTheme accent] forState:UIControlStateNormal]; b.layer.borderColor=[UIColor colorWithRed:0.42 green:0.28 blue:0.90 alpha:0.55].CGColor; b.layer.borderWidth=1; }
        else if (a.style==RPActionStyleDestructive) { UIView *bg=[RPGlass glassViewWithCornerRadius:16 tint:[RPTheme glassFill] interactive:NO]; bg.frame=b.bounds; bg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; bg.userInteractionEnabled=NO; [b insertSubview:bg atIndex:0]; [b setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal]; b.tintColor=[UIColor systemRedColor]; }
        else if (a.style==RPActionStyleCancel) { b.backgroundColor=[RPTheme elevatedSurface]; [b setTitleColor:[RPTheme primaryText] forState:UIControlStateNormal]; }
        else { UIView *bg=[RPGlass glassViewWithCornerRadius:16 tint:[RPTheme glassFill] interactive:NO]; bg.frame=b.bounds; bg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; bg.userInteractionEnabled=NO; [b insertSubview:bg atIndex:0]; [b setTitleColor:[RPTheme primaryText] forState:UIControlStateNormal]; b.layer.borderColor=[RPTheme glassStroke].CGColor; b.layer.borderWidth=1; }
        RPAction *cap=a; [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside]; b.tag=[_actions indexOfObject:a]; (void)cap;
        [_tray addSubview:b]; curY+= h+gap;
    }
    CGFloat totalH = curY + 16 + self.view.safeAreaInsets.bottom;
    _tray.frame=CGRectMake(0, self.view.bounds.size.height, W, totalH);
}
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; [UIView animateWithDuration:0.34 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0 options:0 animations:^{ self->_tray.frame=CGRectMake(0, self.view.bounds.size.height-self->_tray.frame.size.height, self.view.bounds.size.width, self->_tray.frame.size.height); } completion:nil]; }
- (void)tap:(UIButton*)b { RPAction *act=_actions[b.tag]; [self dismissThen:act.handler]; }
- (void)dismiss { [self dismissThen:nil]; }
- (void)dismissThen:(void(^)(void))h {
    [UIView animateWithDuration:0.22 animations:^{ self->_tray.frame=CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, self.view.bounds.size.height); self->_backdrop.alpha=0; } completion:^(BOOL f){
        [self dismissViewControllerAnimated:NO completion:h];
    }];
}
@end
