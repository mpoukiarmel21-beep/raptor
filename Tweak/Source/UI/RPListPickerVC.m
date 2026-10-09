#import "RPListPickerVC.h"
#import "RPTheme.h"
@implementation RPListOption
+ (instancetype)optionWithValue:(NSString*)v title:(NSString*)t subtitle:(NSString*)s { RPListOption *o=[self new]; o.value=v;o.title=t;o.subtitle=s; return o; }
@end
@interface RPListPickerVC ()
@property (nonatomic, strong) NSArray<RPListOption*>*opts;
@property (nonatomic, copy) NSString *sel;
@property (nonatomic, copy) void(^cb)(RPListOption*);
@end
@implementation RPListPickerVC
- (instancetype)initWithTitle:(NSString*)title options:(NSArray*)opts selectedValue:(NSString*)sel onPick:(void(^)(RPListOption*))cb {
    self=[super initWithStyle:UITableViewStyleInsetGrouped]; if(self){ self.title=title; _opts=opts; _sel=sel; _cb=cb; } return self;
}
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=[RPTheme panelBackground]; self.tableView.backgroundColor=[RPTheme panelBackground]; }
- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s { return _opts.count; }
- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"r"]; if(!c) c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"r"];
    RPListOption *o=_opts[ip.row];
    c.textLabel.text=o.title; c.textLabel.textColor=[RPTheme primaryText];
    c.detailTextLabel.text=o.subtitle; c.detailTextLabel.textColor=[RPTheme secondaryText];
    c.backgroundColor=[RPTheme glassFill]; c.layer.cornerRadius=12; c.clipsToBounds=YES;
    c.accessoryType=[o.value isEqualToString:_sel] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.tintColor=[RPTheme accent];
    return c;
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip {
    RPListOption *o=_opts[ip.row]; if(_cb) _cb(o); [self.navigationController popViewControllerAnimated:YES];
}
@end
