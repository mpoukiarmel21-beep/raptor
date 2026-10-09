#import "RPPanelVC.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import "RPPaths.h"
#import "RPDeviceIdentity.h"
#import "RPTheme.h"
#import "RPGlass.h"
#import "RPL10n.h"
#import "RPActionSheet.h"
#import "RPCreateVC.h"
#import "RPMapPickerVC.h"
#import "RPAppRelaunch.h"

@interface RPPanelVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<RPContainer*> *containers;
@end

@implementation RPPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[RPTheme panelBackground];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.title=@"Raptor";
    UILabel *titleLabel=[[UILabel alloc] init];
    titleLabel.text=@"Raptor"; titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; titleLabel.textColor=[RPTheme primaryText];
    self.navigationItem.titleView=titleLabel;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    UIBarButtonItem *plus=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(create)];
    UISegmentedControl *seg=[[UISegmentedControl alloc] initWithItems:@[@"FR",@"EN"]];
    seg.selectedSegmentIndex=[RPLang() isEqualToString:@"en"] ? 1 : 0;
    seg.frame=CGRectMake(0,0,70,26);
    [seg addTarget:self action:@selector(langChanged:) forControlEvents:UIControlEventValueChanged];
    seg.selectedSegmentTintColor=[RPTheme accent];
    UIBarButtonItem *langItem=[[UIBarButtonItem alloc] initWithCustomView:seg];
    self.navigationItem.rightBarButtonItems=@[plus, langItem];
    if ([RPContainerStore shared].isolationDegraded) {
        UILabel *banner=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,32)];
        banner.text=RPLL(@"panel.degraded",@"⚠️ isolation inactive — redémarrage requis");
        banner.textColor=[UIColor systemRedColor]; banner.font=[UIFont systemFontOfSize:12]; banner.textAlignment=NSTextAlignmentCenter;
        banner.backgroundColor=[UIColor colorWithRed:1 green:0 blue:0 alpha:0.12];
        self.navigationItem.titleView=banner;
    }
    _table=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _table.dataSource=self; _table.delegate=self;
    _table.backgroundColor=[RPTheme panelBackground]; _table.rowHeight=76;
    _table.tableFooterView=[self makeResetFooter];
    [self.view addSubview:_table];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:kRPContainersChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:kRPActiveChanged object:nil];
    [self reload];
}

- (UIView*)makeResetFooter {
    UIView *f=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,88)];
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.frame=CGRectMake(16,20,f.frame.size.width-32,44);
    b.backgroundColor=[RPTheme glassFill]; b.layer.cornerRadius=14; b.clipsToBounds=YES;
    b.layer.borderColor=[UIColor systemRedColor].CGColor; b.layer.borderWidth=1;
    [b setTitle:RPLL(@"panel.reset",@"Tout réinitialiser") forState:UIControlStateNormal];
    [b setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [b addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    [f addSubview:b];
    return f;
}

- (void)reload { _containers=[RPContainerStore shared].containers; [_table reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)langChanged:(UISegmentedControl*)s {
    NSString *lang = s.selectedSegmentIndex==1?@"en":@"fr";
    [RPL10n setOverrideLanguage:lang];
    [self reload];
}
- (void)create { RPCreateVC *vc=[[RPCreateVC alloc] initWithContainer:nil]; [self.navigationController pushViewController:vc animated:YES]; }

#pragma mark - table

- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s { return _containers.count; }

- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip {
    static NSString *ID=@"rp";
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:ID];
    if(!c){
        c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ID];
        c.backgroundView=[[UIView alloc] init];
        c.backgroundView.backgroundColor=[RPTheme glassFill];
        c.backgroundView.layer.cornerRadius=14; c.backgroundView.clipsToBounds=YES;
        c.backgroundView.layer.borderColor=[RPTheme glassStroke].CGColor; c.backgroundView.layer.borderWidth=1;
        c.selectedBackgroundView=[[UIView alloc] init];
        c.selectedBackgroundView.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];
    }
    RPContainer *ct=_containers[ip.row];
    c.textLabel.text=ct.name; c.textLabel.textColor=[RPTheme primaryText];
    c.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    NSString *sub=[RPDeviceIdentity marketingNameForIdentifier:ct.deviceModel ?: [RPDeviceIdentity seededModelForCID:ct.cid].identifier];
    if (ct.hasLocation && ct.locationName.length) sub=[sub stringByAppendingFormat:@"  ·  📍 %@", ct.locationName];
    c.detailTextLabel.text=sub; c.detailTextLabel.textColor=[RPTheme secondaryText]; c.detailTextLabel.font=[UIFont systemFontOfSize:12];
    c.backgroundColor=[UIColor clearColor]; // let backgroundView show (glass)
    BOOL active=[ct.cid isEqualToString:[RPContainerStore shared].activeCID];
    c.tintColor=[RPTheme accent];

    // Build accessory container: checkmark (if active) + pin button — accessoryView is the ONLY slot, so stack them in one view
    UIView *acc=[[UIView alloc] initWithFrame:CGRectMake(0,0, active? 76:44, 44)];
    CGFloat x=0;
    if (active) {
        UIImageView *check=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        check.tintColor=[RPTheme accent]; check.frame=CGRectMake(0,10,24,24); check.contentMode=UIViewContentModeScaleAspectFit;
        [acc addSubview:check]; x=32;
    }
    UIButton *pin=[UIButton buttonWithType:UIButtonTypeSystem];
    pin.frame=CGRectMake(x,0,44,44);
    NSString *sym = ct.hasLocation?@"mappin.circle.fill":@"mappin.and.ellipse";
    [pin setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
    pin.tintColor=[RPTheme accent];
    // use indexPath, not tag — tag breaks on reuse/reload
    [pin addTarget:self action:@selector(pinTap:) forControlEvents:UIControlEventTouchUpInside];
    pin.tag=ip.row;
    [acc addSubview:pin];
    c.accessoryView=acc;
    c.accessoryType=UITableViewCellAccessoryNone; // we draw our own checkmark
    return c;
}

- (void)pinTap:(UIButton*)b {
    NSInteger row=b.tag;
    if (row<0 || row >= (NSInteger)_containers.count) return;
    RPContainer *ct=_containers[row];
    RPMapPickerVC *vc=[[RPMapPickerVC alloc] initWithContainer:ct onCommit:^{ [self reload]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    RPContainer *ct=_containers[ip.row];
    BOOL active=[ct.cid isEqualToString:[RPContainerStore shared].activeCID];
    if (!active) {
        // Direct switch — no sheet, auto-relaunch (demandé)
        NSError *err=nil;
        [[RPContainerStore shared] setActiveCID:ct.cid error:&err];
        if(err){
            UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Erreur" message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil]; return;
        }
        NSString *msg=[NSString stringWithFormat:RPLL(@"panel.activated.m",@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser."), ct.name];
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Raptor" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*d){ RPCloseAppForRelaunch(); }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    // Active container: show management sheet
    RPActionSheet *sheet=[[RPActionSheet alloc] initWithTitle:ct.name message:nil];
    [sheet addAction:[RPAction actionWithTitle:@"Modifier" symbol:@"pencil" style:RPActionStyleDefault handler:^{
        RPCreateVC *vc=[[RPCreateVC alloc] initWithContainer:ct]; [self.navigationController pushViewController:vc animated:YES];
    }]];
    [sheet addAction:[RPAction actionWithTitle:RPLL(@"panel.delete",@"Supprimer") symbol:@"trash" style:RPActionStyleDestructive handler:^{
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Supprimer ?" message:[NSString stringWithFormat:@"Supprimer « %@ » et toutes ses données ?", ct.name] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Supprimer" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*d){
            NSError *err=nil; [[RPContainerStore shared] removeContainer:ct error:&err];
            if(err){ UIAlertController *e=[UIAlertController alertControllerWithTitle:@"Erreur" message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:e animated:YES completion:nil]; }
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }]];
    [sheet addAction:[RPAction actionWithTitle:RPLL(@"common.cancel",@"Annuler") symbol:nil style:RPActionStyleCancel handler:nil]];
    [sheet presentFrom:self];
}

- (void)confirmReset {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tout réinitialiser ?" message:@"Tous les conteneurs (sauf Default) et leurs données seront supprimés." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Réinitialiser" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*d){
        [[RPContainerStore shared] resetAll];
        UIAlertController *done=[UIAlertController alertControllerWithTitle:@"Fait" message:@"Réinitialisation terminée. L'app va se fermer." preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){ RPCloseAppForRelaunch(); }]];
        [self presentViewController:done animated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if(self.view.window==nil && self.presentingViewController) [self dismissViewControllerAnimated:NO completion:nil]; }

@end
