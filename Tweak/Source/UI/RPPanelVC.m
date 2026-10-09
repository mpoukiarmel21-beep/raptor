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
#import <PhotosUI/PhotosUI.h>

@interface RPPanelVC () <UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<RPContainer*> *containers;
@end

@implementation RPPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[RPTheme panelBackground];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.title=@"Raptor";
    // nav
    UILabel *titleLabel=[[UILabel alloc] init];
    titleLabel.text=@"Raptor"; titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; titleLabel.textColor=[RPTheme primaryText];
    self.navigationItem.titleView=titleLabel;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    UIBarButtonItem *plus=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(create)];
    // lang toggle
    UISegmentedControl *seg=[[UISegmentedControl alloc] initWithItems:@[@"FR",@"EN"]];
    seg.selectedSegmentIndex=[RPLang() isEqualToString:@"en"] ? 1 : 0;
    seg.frame=CGRectMake(0,0,70,26);
    [seg addTarget:self action:@selector(langChanged:) forControlEvents:UIControlEventValueChanged];
    seg.selectedSegmentTintColor=[RPTheme accent];
    UIBarButtonItem *langItem=[[UIBarButtonItem alloc] initWithCustomView:seg];
    self.navigationItem.rightBarButtonItems=@[plus, langItem];
    // degraded banner
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
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"rp"]; if(!c) c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"rp"];
    RPContainer *ct=_containers[ip.row];
    c.textLabel.text=ct.name; c.textLabel.textColor=[RPTheme primaryText];
    NSString *sub=[RPDeviceIdentity marketingNameForIdentifier:ct.deviceModel ?: [RPDeviceIdentity seededModelForCID:ct.cid].identifier];
    if (ct.hasLocation && ct.locationName.length) sub=[sub stringByAppendingFormat:@"  ·  📍 %@", ct.locationName];
    c.detailTextLabel.text=sub; c.detailTextLabel.textColor=[RPTheme secondaryText];
    c.backgroundColor=[RPTheme glassFill];
    BOOL active=[ct.cid isEqualToString:[RPContainerStore shared].activeCID];
    c.accessoryType=active?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; c.tintColor=[RPTheme accent];
    // leading pin button
    UIButton *pin=[UIButton buttonWithType:UIButtonTypeSystem];
    pin.frame=CGRectMake(0,0,44,44);
    NSString *sym = ct.hasLocation?@"mappin.circle.fill":@"mappin.and.ellipse";
    [pin setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
    pin.tintColor=[RPTheme accent]; pin.tag=ip.row;
    [pin addTarget:self action:@selector(pinTap:) forControlEvents:UIControlEventTouchUpInside];
    c.accessoryView=pin;
    // keep checkmark too
    if (active) {
        // show both: accessoryView already pin, so add checkmark as imageView?
        // keep pin as accessoryView, show checkmark via background
        c.tintColor=[RPTheme accent];
    }
    return c;
}
- (void)pinTap:(UIButton*)b {
    RPContainer *ct=_containers[b.tag];
    RPMapPickerVC *vc=[[RPMapPickerVC alloc] initWithContainer:ct onCommit:^{ [self reload]; }];
    [self.navigationController pushViewController:vc animated:YES];
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    RPContainer *ct=_containers[ip.row];
    BOOL active=[ct.cid isEqualToString:[RPContainerStore shared].activeCID];
    RPActionSheet *sheet=[[RPActionSheet alloc] initWithTitle:ct.name message:nil];
    if (!active) {
        [sheet addAction:[RPAction actionWithTitle:RPLL(@"panel.activate",@"Activer ce conteneur") symbol:@"checkmark.circle.fill" style:RPActionStyleAccent handler:^{
            NSError *err=nil;
            [[RPContainerStore shared] setActiveCID:ct.cid error:&err];
            if(err){ UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Erreur" message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; return; }
            NSString *msg=[NSString stringWithFormat:RPLL(@"panel.activated.m",@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser."), ct.name];
            UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Raptor" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*d){ RPCloseAppForRelaunch(); }]];
            [self presentViewController:a animated:YES completion:nil];
        }]];
    }
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
